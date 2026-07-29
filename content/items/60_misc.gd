## Space-flight consumables and key items: fuel, upgrade modules, scanner
## charges, star charts, teleporter cores and distress beacons.
##
## Owned by the space agent. These are the items every `space/` system spends,
## so their StringNames are load-bearing:
##
##   `erchius_fuel`         FTL fuel. `SpcShipUpgrades.refuel_from_inventory()`
##   `ship_upgrade_module`  hull and FTL tiers
##   `scanner_charge`       `SpcScanning.scan()`
##   `star_chart`           reveals an unknown system
##   `teleporter_core`      crafting ingredient for `ship_teleporter_pad`
##   `distress_beacon`      calls trouble down on your head, deliberately
##
## `pixels` (the currency) is deliberately **not** defined here — the inventory
## agent owns it. `SpcShipUpgrades.pixels()` finds it however it ends up modelled.
class_name SpcMiscItems
extends RefCounted

const ERCHIUS := Color(0.62, 0.44, 0.92)
const MODULE := Color(0.95, 0.78, 0.32)
const SCANNER := Color(0.40, 0.88, 0.95)
const CHART := Color(0.80, 0.85, 0.95)
const CORE := Color(0.45, 0.95, 0.72)
const BEACON := Color(0.95, 0.35, 0.30)


static func register_all(reg) -> void:
	# `content/items/10_materials.gd` loads first and may already own this id.
	# Adopt the existing entry and layer the ship-fuel behaviour onto it rather
	# than registering a duplicate.
	var erchius: ItemType = reg.get_type(&"erchius_fuel") if reg.has(&"erchius_fuel") \
		else reg.define(&"erchius_fuel", "Erchius Crystal")
	erchius \
		.of_kind(ItemType.Kind.MATERIAL).look(ERCHIUS, &"crystal") \
		.describe("Volatile lilac crystal. One unit of FTL fuel. Use aboard the ship to load the tank.") \
		.worth(30, Const.RARITY_UNCOMMON).stacks(1000) \
		.in_category(&"materials").tag(&"fuel").tag(&"space") \
		.flags({"on_use": SpcMiscItems._use_fuel})

	reg.define(&"ship_upgrade_module", "Ship Upgrade Module") \
		.of_kind(ItemType.Kind.AUGMENT).look(MODULE, &"chip") \
		.describe("A licensed hull expansion permit. Spend it at the ship's console to add compartments or tune the FTL drive.") \
		.worth(2500, Const.RARITY_LEGENDARY).stacks(100) \
		.in_category(&"upgrades").tag(&"upgrade").tag(&"space")

	reg.define(&"scanner_charge", "Scanner Charge") \
		.of_kind(ItemType.Kind.CONSUMABLE).look(SCANNER, &"vial") \
		.describe("Single-use survey pulse. Reveals a world's threat, biomes and resources from orbit without burning fuel.") \
		.worth(120, Const.RARITY_UNCOMMON).stacks(200) \
		.in_category(&"consumables").tag(&"scanner").tag(&"space") \
		.flags({"on_use": SpcMiscItems._use_scanner})

	reg.define(&"star_chart", "Star Chart") \
		.of_kind(ItemType.Kind.CONSUMABLE).look(CHART, &"scroll") \
		.describe("Somebody else's survey data. Reveals one uncharted system on your star map.") \
		.worth(400, Const.RARITY_RARE).stacks(50) \
		.in_category(&"consumables").tag(&"chart").tag(&"space") \
		.flags({"on_use": SpcMiscItems._use_chart})

	reg.define(&"teleporter_core", "Teleporter Core") \
		.of_kind(ItemType.Kind.MATERIAL).look(CORE, &"gem") \
		.describe("A paired-state anchor. The heart of every teleporter pad; craft one into a pad to link a new destination.") \
		.worth(800, Const.RARITY_RARE).stacks(100) \
		.in_category(&"materials").tag(&"teleporter").tag(&"space")

	# Already owned by 10_materials.gd; adopt and layer behaviour on.
	var beacon: ItemType = reg.get_type(&"distress_beacon") if reg.has(&"distress_beacon") \
		else reg.define(&"distress_beacon", "Distress Beacon")
	beacon \
		.of_kind(ItemType.Kind.CONSUMABLE).look(BEACON, &"beacon") \
		.describe("Broadcasts your position on every band. Something always answers. Place it somewhere you can defend.") \
		.worth(600, Const.RARITY_RARE).stacks(20) \
		.in_category(&"consumables").tag(&"beacon").tag(&"space") \
		.flags({"on_use": SpcMiscItems._use_beacon})


# ------------------------------------------------------------------ use hooks
## `on_use(player, ctx) -> bool`; returning true consumes one from the stack.

static func _use_fuel(_player: Node, _ctx: Dictionary) -> bool:
	if not Universe.ship.is_aboard():
		Events.toast("Erchius has to be loaded aboard the ship.", "warn")
		return false
	if Universe.fuel() >= Universe.fuel_capacity():
		Events.toast("Fuel tank is full.", "warn")
		return false
	Universe.upgrades.add_fuel(1)
	Events.play_sound.emit(&"ship_refuel", _pos())
	return true


static func _use_scanner(_player: Node, _ctx: Dictionary) -> bool:
	var target := Universe.selection()
	if target == "":
		target = Universe.travel.orbiting
	if target == "":
		Events.toast("Select a world on the star map first.", "warn")
		return false
	# `scan()` spends the charge itself, so report "not consumed" here.
	Universe.scanning.scan(target, Universe.scan_of(target) >= 1)
	return false


static func _use_chart(_player: Node, _ctx: Dictionary) -> bool:
	var revealed := Universe.reveal_random_system()
	if revealed == "":
		Events.toast("Nothing left on this chart you do not already know.", "warn")
		return false
	Events.toast("Charted %s." % String(Universe.system_info(revealed).get("name", revealed)), "good")
	Events.play_sound.emit(&"chart_unfold", _pos())
	return true


static func _use_beacon(player: Node, _ctx: Dictionary) -> bool:
	if Universe.ship.is_aboard():
		Events.toast("Not in here. Take it somewhere open.", "warn")
		return false
	var pos := _pos()
	Events.toast("Beacon active. Something heard you.", "warn")
	Events.play_sound.emit(&"beacon_activate", pos)
	Events.spawn_particles.emit(&"beacon_flare", pos, 60)
	Events.screen_shake.emit(1.4, 0.8)
	# The entity agent listens for this; if nothing does, the beacon is flavour.
	Events.quest_offered.emit("distress_%s" % World.planet_id, player)
	return true


static func _pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO
