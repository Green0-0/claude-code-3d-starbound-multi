## The behaviour of one crafting station, as a plain composable object.
##
## This is deliberately [b]not[/b] a Node: the objects agent owns the placeable
## machine and simply holds one of these, forwards `_physics_process` into
## [method tick], and relays the signals to its UI.
##
## [codeblock]
## # objects/furnace.gd
## extends Node3D
## var station := CraftStation.new(&"furnace", 1)
##
## func _ready() -> void:
##     station.needs_fuel = true
##     station.groups = [&"smelting", &"cooking"]
##     station.craft_finished.connect(func(rid: String, _n: int) -> void:
##         Events.toast("Smelted %s" % rid, "craft"))
##     station.owner_node = self
##
## func _physics_process(delta: float) -> void:
##     station.tick(delta)
##
## func interact(_player: Node) -> bool:
##     Events.station_opened.emit(String(station.station_id), self)
##     return true
## [/codeblock]
##
## The UI calls [method enqueue] / [method cancel] / [method available]; it
## never touches `Recipes` for a station-bound craft.
class_name CraftStation
extends RefCounted

## Emitted every tick while a job runs. `t` is 0..1.
signal progress_changed(recipe_id: String, t: float)
## A job left the queue and began processing.
signal craft_started(recipe_id: String)
## A job completed and its outputs were delivered. `count` is the batch size.
signal craft_finished(recipe_id: String, count: int)
## A job could not run (materials vanished, tier too low, out of fuel).
signal craft_failed(recipe_id: String, reason: String)
## The queue contents changed (enqueue, cancel, completion).
signal queue_changed()
## Remaining burn seconds changed. Furnace UIs draw a flame from this.
signal fuel_changed(seconds: float, capacity: float)

# ------------------------------------------------------------------ identity
## One of `CraftRecipe.STATIONS`.
var station_id: StringName = &"workbench"
var display_name: String = ""
## Station tier. Recipes with a higher `required_tier` are hidden.
var tier: int = 0
## Recipe groups this station exposes as tabs. Empty = every group the station
## has recipes for.
var groups: Array[StringName] = []

# ----------------------------------------------------------------- behaviour
## Instant stations resolve a craft the moment it is requested (workbench,
## anvil). Timed stations queue jobs and grind through them (furnace, chemistry).
var instant: bool = false
## Maximum pending jobs, including the one in progress.
var queue_limit: int = 12
## Multiplies recipe time. Upgraded machines run faster.
var speed_multiplier: float = 1.0
## Furnaces refuse to run without burn time available.
var needs_fuel: bool = false
var fuel_capacity: float = 400.0
var fuel_seconds: float = 0.0
## Set false while the machine is unpowered / broken.
var enabled: bool = true

## Optional: the node that owns this station, used for drop positions and for
## `Events.station_opened`. Purely informational here.
var owner_node: Node = null
## Optional: an inventory to draw from instead of the player's (a machine with
## its own input slots). Must satisfy the `Inventory` API.
var source_inventory: Variant = null

# --------------------------------------------------------------------- state
## `[{ "recipe": CraftRecipe, "count": int, "elapsed": float, "total": float }]`
var queue: Array[Dictionary] = []


## `p_tier` defaults to the station's nominal tier from
## `CraftRecipe.STATION_TIER`; pass a lower number for a downgraded machine
## (a campfire is `CraftStation.new(&"furnace", 0)`).
func _init(p_station: StringName = &"workbench", p_tier: int = -1) -> void:
	station_id = p_station
	tier = p_tier if p_tier >= 0 else int(CraftRecipe.STATION_TIER.get(p_station, 0))
	display_name = String(CraftRecipe.STATION_LABELS.get(p_station, String(p_station).capitalize()))
	instant = p_station in [&"hand", &"workbench", &"anvil", &"forge"]
	needs_fuel = p_station == &"furnace"


## Bulk setup from the object agent's exported dictionary.
## Recognised keys: station, tier, groups, instant, queue_limit, speed,
## needs_fuel, fuel_capacity, name.
func configure(d: Dictionary) -> CraftStation:
	if d.has("station"):
		station_id = StringName(d["station"])
		display_name = String(CraftRecipe.STATION_LABELS.get(station_id, String(station_id).capitalize()))
	tier = int(d.get("tier", tier))
	if d.has("groups"):
		groups.clear()
		for g: Variant in d["groups"]:
			groups.append(StringName(g))
	instant = bool(d.get("instant", instant))
	queue_limit = int(d.get("queue_limit", queue_limit))
	speed_multiplier = maxf(0.05, float(d.get("speed", speed_multiplier)))
	needs_fuel = bool(d.get("needs_fuel", needs_fuel))
	fuel_capacity = float(d.get("fuel_capacity", fuel_capacity))
	display_name = String(d.get("name", display_name))
	return self


# ------------------------------------------------------------------- queries
func _inv() -> Variant:
	if source_inventory != null:
		return source_inventory
	return Game.player.get("inventory") if Game.player != null else null


## Known recipes this station can offer, craftable ones first. Straight through
## to `Recipes.available_for` with the station's own tier and group filter.
func available(inv: Variant = null) -> Array[CraftRecipe]:
	var list := Recipes.available_for(station_id, inv if inv != null else _inv(), tier)
	if groups.is_empty():
		return list
	var out: Array[CraftRecipe] = []
	for r: CraftRecipe in list:
		if groups.has(r.group):
			out.append(r)
	return out


## Can this station physically run the recipe (right station, tier, group)?
## Ignores materials — use `Recipes.has_materials` for that.
func can_accept(recipe: Variant) -> bool:
	var r := _as_recipe(recipe)
	if r == null or not enabled:
		return false
	if r.station != station_id or r.required_tier > tier:
		return false
	return groups.is_empty() or groups.has(r.group)


func _as_recipe(recipe: Variant) -> CraftRecipe:
	if recipe is CraftRecipe:
		return recipe as CraftRecipe
	return Recipes.get_recipe(String(recipe))


func is_busy() -> bool:
	return not queue.is_empty()


func queue_size() -> int:
	return queue.size()


func current_recipe_id() -> String:
	return String(queue[0]["recipe"].id) if not queue.is_empty() else ""


## 0..1 progress of the job in front. Returns 0 when idle.
func progress() -> float:
	if queue.is_empty():
		return 0.0
	var job: Dictionary = queue[0]
	var total := float(job["total"])
	return 1.0 if total <= 0.0 else clampf(float(job["elapsed"]) / total, 0.0, 1.0)


## Seconds left on the whole queue, for a tooltip.
func time_remaining() -> float:
	var t := 0.0
	for job: Dictionary in queue:
		t += maxf(0.0, float(job["total"]) - float(job["elapsed"]))
	return t


# ------------------------------------------------------------------ crafting
## Requests `count` runs of a recipe.
##
## Instant stations craft immediately and return true on success. Timed stations
## consume the materials up front (so the player cannot spend them twice) and
## append a job; the outputs arrive when the timer elapses.
func enqueue(recipe_id: String, count: int = 1) -> bool:
	var r := _as_recipe(recipe_id)
	if r == null:
		return false
	if not can_accept(r):
		craft_failed.emit(recipe_id, "wrong_station")
		return false
	count = maxi(1, count)
	var inv: Variant = _inv()
	if not Recipes.is_known(r.id):
		craft_failed.emit(recipe_id, "unknown_recipe")
		return false
	if not Recipes.has_materials(r.id, inv) or Recipes.max_crafts(r.id, inv) < count:
		craft_failed.emit(recipe_id, "missing_materials")
		return false

	if instant or r.is_instant():
		if not Recipes.craft(r.id, inv, count):
			craft_failed.emit(recipe_id, "consume_failed")
			return false
		craft_started.emit(recipe_id)
		craft_finished.emit(recipe_id, count)
		queue_changed.emit()
		return true

	if queue.size() >= queue_limit:
		craft_failed.emit(recipe_id, "queue_full")
		return false
	if not Recipes.take_from(inv, r.scaled_inputs(count)):
		craft_failed.emit(recipe_id, "consume_failed")
		return false
	queue.append({
		"recipe": r, "count": count, "elapsed": 0.0,
		"total": maxf(0.05, r.time * float(count) / speed_multiplier),
	})
	Events.inventory_changed.emit()
	queue_changed.emit()
	if queue.size() == 1:
		craft_started.emit(recipe_id)
	return true


## Removes a queued job and refunds its materials. Index 0 (in progress) is
## refundable too — this is a sandbox, not a punishment simulator.
func cancel(index: int = 0) -> bool:
	if index < 0 or index >= queue.size():
		return false
	var job: Dictionary = queue[index]
	var r: CraftRecipe = job["recipe"]
	var inv: Variant = _inv()
	var refund := r.scaled_inputs(int(job["count"]))
	for k: StringName in refund:
		Recipes.give_to(inv, k, int(refund[k]), true)
	queue.remove_at(index)
	Events.inventory_changed.emit()
	queue_changed.emit()
	return true


func clear_queue() -> void:
	while not queue.is_empty():
		cancel(0)


# ---------------------------------------------------------------------- fuel
## Feeds `count` of a fuel item into the furnace. Returns how many were
## actually burnt-in (0 when the item is not fuel or the buffer is full).
func add_fuel(item_id: StringName, count: int = 1) -> int:
	if not needs_fuel:
		return 0
	var per := Recipes.fuel_value(item_id)
	if per <= 0.0:
		return 0
	var taken := 0
	while taken < count and fuel_seconds + per <= fuel_capacity:
		fuel_seconds += per
		taken += 1
	if taken > 0:
		fuel_changed.emit(fuel_seconds, fuel_capacity)
	return taken


## Pulls fuel out of the bound inventory automatically. Returns true when the
## furnace has burn time afterwards.
func autofeed_fuel(inv: Variant = null) -> bool:
	if not needs_fuel or fuel_seconds > 0.0:
		return fuel_seconds > 0.0
	var real: Variant = inv if inv != null else _inv()
	if real == null or not real.has_method(&"count_of"):
		return false
	for fid: StringName in Recipes.all_fuels():
		if int(real.call(&"count_of", fid)) <= 0:
			continue
		if Recipes.take_from(real, {fid: 1}):
			add_fuel(fid, 1)
			Events.inventory_changed.emit()
			return true
	return false


func fuel_fraction() -> float:
	return clampf(fuel_seconds / maxf(0.001, fuel_capacity), 0.0, 1.0)


# ---------------------------------------------------------------------- tick
## Drive from the owning node's `_physics_process`. Safe to call when idle.
func tick(delta: float) -> void:
	if not enabled or queue.is_empty() or delta <= 0.0:
		return
	var job: Dictionary = queue[0]
	var r: CraftRecipe = job["recipe"]

	if needs_fuel:
		if fuel_seconds <= 0.0 and not autofeed_fuel():
			return
		fuel_seconds = maxf(0.0, fuel_seconds - delta)
		fuel_changed.emit(fuel_seconds, fuel_capacity)

	job["elapsed"] = float(job["elapsed"]) + delta
	queue[0] = job
	progress_changed.emit(r.id, progress())
	if float(job["elapsed"]) < float(job["total"]):
		return

	queue.remove_at(0)
	Recipes.deliver_outputs(r, _inv(), int(job["count"]))
	craft_finished.emit(r.id, int(job["count"]))
	queue_changed.emit()
	if not queue.is_empty():
		craft_started.emit(String(queue[0]["recipe"].id))


# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	var jobs: Array = []
	for job: Dictionary in queue:
		jobs.append({
			"recipe": (job["recipe"] as CraftRecipe).id, "count": int(job["count"]),
			"elapsed": float(job["elapsed"]), "total": float(job["total"]),
		})
	return {
		"station": String(station_id), "tier": tier, "fuel": fuel_seconds,
		"queue": jobs, "enabled": enabled, "speed": speed_multiplier,
	}


func load_state(d: Dictionary) -> void:
	station_id = StringName(d.get("station", station_id))
	tier = int(d.get("tier", tier))
	fuel_seconds = float(d.get("fuel", 0.0))
	enabled = bool(d.get("enabled", true))
	speed_multiplier = maxf(0.05, float(d.get("speed", 1.0)))
	queue.clear()
	for j: Dictionary in d.get("queue", []):
		var r := Recipes.get_recipe(String(j.get("recipe", "")))
		if r == null:
			continue
		queue.append({
			"recipe": r, "count": int(j.get("count", 1)),
			"elapsed": float(j.get("elapsed", 0.0)),
			"total": float(j.get("total", maxf(0.05, r.time))),
		})
	queue_changed.emit()
