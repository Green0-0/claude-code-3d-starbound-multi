## The ship's progression track: hull tiers, FTL tiers, fuel and crew.
##
## Lives at `Universe.upgrades`. Three currencies feed it:
##   * **ship upgrade modules** (`ship_upgrade_module` item) — hull tiers
##   * **pixels** — the money side of every upgrade
##   * **erchius fuel** (`erchius_fuel` item) — the FTL drive's consumable
##
## The FTL tier is the gate on exploration: `Universe.can_travel_to()` refuses
## any body whose `threat` exceeds `ftl_tier`, so the galaxy opens up one band
## at a time. Hull tiers are the *spatial* progression — each one unlocks more
## rooms in `space/ship_interior.gd`.
class_name SpcShipUpgrades
extends Node

## Highest hull tier the interior generator knows how to build.
const MAX_HULL := 5
## Highest FTL tier; equals the highest reachable threat band.
const MAX_FTL := 6

## Cost to reach hull tier N (index 0 unused). `{"modules": int, "pixels": int}`.
const HULL_COSTS := [
	{"modules": 0, "pixels": 0},
	{"modules": 0, "pixels": 0},
	{"modules": 2, "pixels": 600},
	{"modules": 4, "pixels": 2200},
	{"modules": 8, "pixels": 7000},
	{"modules": 14, "pixels": 20000},
]

## Cost to reach FTL tier N (index 0 unused).
const FTL_COSTS := [
	{"modules": 0, "pixels": 0, "fuel": 0},
	{"modules": 0, "pixels": 0, "fuel": 0},
	{"modules": 1, "pixels": 400, "fuel": 10},
	{"modules": 3, "pixels": 1500, "fuel": 25},
	{"modules": 6, "pixels": 5000, "fuel": 50},
	{"modules": 10, "pixels": 14000, "fuel": 80},
	{"modules": 16, "pixels": 40000, "fuel": 120},
]

## Fuel tank size and crew berths by hull tier.
const FUEL_BY_HULL := [0, 100, 200, 400, 800, 1600]
const CREW_BY_HULL := [0, 2, 4, 6, 8, 12]

## Display names, so the UI does not have to invent them.
const HULL_NAMES := [
	"", "Shuttle", "Cutter", "Corvette", "Frigate", "Cruiser",
]
const FTL_NAMES := [
	"", "Chemical Boost", "Erchius Drive", "Warp Coil", "Fold Engine",
	"Singularity Drive", "Ansible Core",
]

signal hull_changed(tier: int)
signal ftl_changed(tier: int)
signal fuel_changed(fuel: int, capacity: int)

var hull_tier: int = 1
var ftl_tier: int = 1
var fuel: int = 20
var fuel_capacity: int = 100
var crew_capacity: int = 2
## Ids of crew members currently berthed; the NPC agent may append to this.
var crew: Array[String] = []


func _ready() -> void:
	# Plain defaults only: this runs from inside `Universe._ready()`, so nothing
	# here may call back into `Universe`.
	hull_tier = 1
	ftl_tier = 1
	fuel = 20
	fuel_capacity = int(FUEL_BY_HULL[1])
	crew_capacity = int(CREW_BY_HULL[1])


## Back to a fresh run. Called by `Universe.generate()`.
func reset() -> void:
	hull_tier = 1
	ftl_tier = 1
	fuel_capacity = int(FUEL_BY_HULL[1])
	crew_capacity = int(CREW_BY_HULL[1])
	fuel = 20
	crew.clear()
	_announce()


func _announce() -> void:
	hull_changed.emit(hull_tier)
	ftl_changed.emit(ftl_tier)
	fuel_changed.emit(fuel, fuel_capacity)
	Universe.notify_capabilities_changed()


# ---------------------------------------------------------------------- names
func hull_name() -> String:
	return String(HULL_NAMES[clampi(hull_tier, 0, MAX_HULL)])


func ftl_name() -> String:
	return String(FTL_NAMES[clampi(ftl_tier, 0, MAX_FTL)])


## The highest planet `threat` the drive can currently reach.
func max_threat() -> int:
	return ftl_tier


# ----------------------------------------------------------------------- fuel
## Top up the tank. Returns how much actually fit.
func add_fuel(amount: int) -> int:
	if amount <= 0:
		return 0
	var room := fuel_capacity - fuel
	var added := mini(room, amount)
	if added <= 0:
		Events.toast("Fuel tank is full.", "warn")
		return 0
	fuel += added
	fuel_changed.emit(fuel, fuel_capacity)
	Universe.notify_capabilities_changed()
	return added


## Burn fuel. Returns false (and burns nothing) if there is not enough.
func consume_fuel(amount: int) -> bool:
	if amount <= 0:
		return true
	if fuel < amount:
		return false
	fuel -= amount
	fuel_changed.emit(fuel, fuel_capacity)
	Universe.notify_capabilities_changed()
	return true


## Move every `erchius_fuel` item out of the player's inventory and into the
## tank. Driven by the fuel hatch in the engine room. Returns units loaded.
func refuel_from_inventory(max_units: int = 0) -> int:
	var have := count_item(&"erchius_fuel")
	if have <= 0:
		Events.toast("No erchius fuel aboard.", "warn")
		return 0
	var room := fuel_capacity - fuel
	if room <= 0:
		Events.toast("Fuel tank is full.", "warn")
		return 0
	var want := mini(have, room)
	if max_units > 0:
		want = mini(want, max_units)
	if not take_item(&"erchius_fuel", want):
		return 0
	add_fuel(want)
	Events.toast("Loaded %d units of erchius fuel." % want, "good")
	Events.play_sound.emit(&"ship_refuel", _player_pos())
	return want


# ------------------------------------------------------------------- upgrades
## `{tier, modules, pixels, have_modules, have_pixels, ok, reason}` for the
## next hull tier. Ready to render straight into the upgrade UI.
func hull_upgrade_quote() -> Dictionary:
	var next := hull_tier + 1
	var out := {
		"tier": next, "modules": 0, "pixels": 0,
		"have_modules": count_item(&"ship_upgrade_module"), "have_pixels": pixels(),
		"ok": false, "reason": "",
	}
	if next > MAX_HULL:
		out["reason"] = "Hull is fully expanded."
		return out
	var cost: Dictionary = HULL_COSTS[next]
	out["modules"] = int(cost["modules"])
	out["pixels"] = int(cost["pixels"])
	if int(out["have_modules"]) < int(out["modules"]):
		out["reason"] = "Needs %d upgrade modules." % int(out["modules"])
		return out
	if int(out["have_pixels"]) < int(out["pixels"]):
		out["reason"] = "Needs %d pixels." % int(out["pixels"])
		return out
	out["ok"] = true
	return out


## Pay for and apply the next hull tier. Re-stamps the ship if the player is
## aboard, so the new rooms appear immediately.
func upgrade_hull() -> bool:
	var q := hull_upgrade_quote()
	if not bool(q["ok"]):
		Events.toast(String(q["reason"]), "warn")
		return false
	if not take_item(&"ship_upgrade_module", int(q["modules"])):
		return false
	if not spend_pixels(int(q["pixels"])):
		return false
	hull_tier = int(q["tier"])
	fuel_capacity = int(FUEL_BY_HULL[clampi(hull_tier, 0, MAX_HULL)])
	crew_capacity = int(CREW_BY_HULL[clampi(hull_tier, 0, MAX_HULL)])
	hull_changed.emit(hull_tier)
	fuel_changed.emit(fuel, fuel_capacity)
	Universe.notify_capabilities_changed()
	Events.upgrade_purchased.emit("hull_%d" % hull_tier)
	Events.toast("Hull expanded — %s class." % hull_name(), "good")
	Events.play_sound.emit(&"ship_upgrade", _player_pos())
	if Universe.ship != null:
		Universe.ship.refit()
	return true


## `{tier, modules, pixels, fuel, ok, reason}` for the next FTL tier.
func ftl_upgrade_quote() -> Dictionary:
	var next := ftl_tier + 1
	var out := {
		"tier": next, "modules": 0, "pixels": 0, "fuel": 0,
		"have_modules": count_item(&"ship_upgrade_module"), "have_pixels": pixels(),
		"ok": false, "reason": "",
	}
	if next > MAX_FTL:
		out["reason"] = "Drive is fully tuned."
		return out
	var cost: Dictionary = FTL_COSTS[next]
	out["modules"] = int(cost["modules"])
	out["pixels"] = int(cost["pixels"])
	out["fuel"] = int(cost["fuel"])
	if int(out["have_modules"]) < int(out["modules"]):
		out["reason"] = "Needs %d upgrade modules." % int(out["modules"])
		return out
	if int(out["have_pixels"]) < int(out["pixels"]):
		out["reason"] = "Needs %d pixels." % int(out["pixels"])
		return out
	if fuel < int(out["fuel"]):
		out["reason"] = "Needs %d fuel in the tank to calibrate." % int(out["fuel"])
		return out
	out["ok"] = true
	return out


## Pay for and apply the next FTL tier, unlocking one more threat band.
func upgrade_ftl() -> bool:
	var q := ftl_upgrade_quote()
	if not bool(q["ok"]):
		Events.toast(String(q["reason"]), "warn")
		return false
	if not take_item(&"ship_upgrade_module", int(q["modules"])):
		return false
	if not spend_pixels(int(q["pixels"])):
		return false
	consume_fuel(int(q["fuel"]))
	ftl_tier = int(q["tier"])
	ftl_changed.emit(ftl_tier)
	Universe.notify_capabilities_changed()
	Events.upgrade_purchased.emit("ftl_%d" % ftl_tier)
	Events.toast("FTL drive upgraded — %s. Threat %d systems unlocked."
		% [ftl_name(), ftl_tier], "good")
	Events.play_sound.emit(&"ship_upgrade", _player_pos())
	return true


# --------------------------------------------------------------------- crew
func can_take_crew() -> bool:
	return crew.size() < crew_capacity


## Berth a crew member. The NPC agent calls this when a recruit joins.
func add_crew(npc_id: String) -> bool:
	if not can_take_crew():
		Events.toast("No free berths — expand the hull.", "warn")
		return false
	if crew.has(npc_id):
		return false
	crew.append(npc_id)
	Events.toast("%s joined the crew." % npc_id.capitalize(), "good")
	return true


func remove_crew(npc_id: String) -> void:
	crew.erase(npc_id)


# ------------------------------------------------- inventory / currency bridge
# The inventory module is owned by another agent and may not exist yet, so every
# call here is guarded and degrades to "you have nothing" rather than crashing.

func _inventory() -> Object:
	if Game.player == null:
		return null
	var inv: Variant = Game.player.get("inventory")
	return inv if inv is Object else null


func _player_pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO


## How many of `item_id` the player carries.
func count_item(item_id: StringName) -> int:
	var inv := _inventory()
	if inv == null:
		return 0
	for m: StringName in [&"count_of", &"count", &"amount_of"]:
		if inv.has_method(m):
			return int(inv.call(m, item_id))
	return 0


## Remove `n` of `item_id`; false if the player does not have them.
func take_item(item_id: StringName, n: int) -> bool:
	if n <= 0:
		return true
	var inv := _inventory()
	if inv == null:
		return false
	if count_item(item_id) < n:
		return false
	for m: StringName in [&"remove_item", &"take", &"consume", &"remove"]:
		if inv.has_method(m):
			inv.call(m, item_id, n)
			Events.inventory_changed.emit()
			return true
	return false


## Give `n` of `item_id` back to the player, or drop it at their feet.
func give_item(item_id: StringName, n: int) -> bool:
	if n <= 0:
		return true
	if Game.player != null and Game.player.has_method(&"give_item"):
		if bool(Game.player.call(&"give_item", item_id, n)):
			return true
	Game.spawn_item_drop(_player_pos() + Vector3(0, 0.5, 0), item_id, n)
	return true


## Current pixel balance, however the inventory agent chose to model it.
func pixels() -> int:
	var inv := _inventory()
	if inv != null:
		for m: StringName in [&"pixels", &"currency", &"get_pixels"]:
			if inv.has_method(m):
				return int(inv.call(m))
		var v: Variant = inv.get("pixels")
		if v != null:
			return int(v)
	if Game.player != null:
		var pv: Variant = Game.player.get("pixels")
		if pv != null:
			return int(pv)
	return count_item(&"pixels")


## Deduct pixels. Returns false when the player cannot afford it.
func spend_pixels(amount: int) -> bool:
	if amount <= 0:
		return true
	if pixels() < amount:
		Events.toast("Not enough pixels.", "warn")
		return false
	var inv := _inventory()
	if inv != null:
		for m: StringName in [&"spend_pixels", &"take_pixels", &"add_pixels"]:
			if inv.has_method(m):
				inv.call(m, -amount if m == &"add_pixels" else amount)
				Events.currency_changed.emit(pixels())
				return true
	if take_item(&"pixels", amount):
		Events.currency_changed.emit(pixels())
		return true
	# No currency implementation yet — let the upgrade through rather than
	# soft-locking progression on another agent's absence.
	return true


# ------------------------------------------------------------------ save/load
func save_state() -> Dictionary:
	return {
		"hull": hull_tier, "ftl": ftl_tier, "fuel": fuel,
		"capacity": fuel_capacity, "crew_capacity": crew_capacity,
		"crew": crew.duplicate(),
	}


func load_state(d: Dictionary) -> void:
	hull_tier = clampi(int(d.get("hull", 1)), 1, MAX_HULL)
	ftl_tier = clampi(int(d.get("ftl", 1)), 1, MAX_FTL)
	fuel_capacity = int(d.get("capacity", int(FUEL_BY_HULL[hull_tier])))
	crew_capacity = int(d.get("crew_capacity", int(CREW_BY_HULL[hull_tier])))
	fuel = clampi(int(d.get("fuel", 20)), 0, fuel_capacity)
	crew.clear()
	for c in (d.get("crew", []) as Array):
		crew.append(String(c))
	_announce()
