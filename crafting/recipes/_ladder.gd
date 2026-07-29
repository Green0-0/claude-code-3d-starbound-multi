## Shared progression data for the whole recipe book, plus the furnace fuel
## table. Loaded like any other recipe file, but registers fuels instead of
## recipes; the tables below are read by `weapons.gd`, `armor.gd`, `tools.gd`,
## `smelting.gd` and `advanced.gd` so the ore ladder is defined exactly once.
##
## [b]Id contract[/b] — mirrors `content/items/10_materials.gd`,
## `30_weapons.gd` and `31_armor.gd` exactly:
## [br]• ore item `raw_<metal>`, ingot `<metal>_bar`;
## [br]• weapons `<metal>_sword` `<metal>_spear` `<metal>_hammer` `<metal>_bow`
##   `<metal>_gun`;
## [br]• armour `<metal>_helm` `<metal>_chest` `<metal>_greaves`;
## [br]• environment suits `firewalker_*` `frostwalker_*` `hazmat_*` `vacuum_*`;
## [br]• tools `<material>_pickaxe` `<material>_axe` `<material>_shovel`
##   `<material>_hoe` `<material>_drill` — this module's convention, since no
##   content file claims tool ids yet.
class_name CraftLadder
extends RefCounted

## Every smeltable metal. `ore` is `&""` for alloys, `bar` is `&""` for the two
## metals that are only ever a reagent (silicon, uranium, plutonium).
const METALS: Array[Dictionary] = [
	{"name": &"copper", "tier": 0, "bar": &"copper_bar", "ore": &"raw_copper"},
	{"name": &"tin", "tier": 0, "bar": &"tin_bar", "ore": &"raw_tin"},
	{"name": &"lead", "tier": 1, "bar": &"lead_bar", "ore": &"raw_lead"},
	{"name": &"iron", "tier": 1, "bar": &"iron_bar", "ore": &"raw_iron"},
	{"name": &"silver", "tier": 1, "bar": &"silver_bar", "ore": &"raw_silver"},
	{"name": &"gold", "tier": 2, "bar": &"gold_bar", "ore": &"raw_gold"},
	{"name": &"tungsten", "tier": 2, "bar": &"tungsten_bar", "ore": &"raw_tungsten"},
	{"name": &"titanium", "tier": 2, "bar": &"titanium_bar", "ore": &"raw_titanium"},
	{"name": &"platinum", "tier": 3, "bar": &"platinum_bar", "ore": &"raw_platinum"},
	{"name": &"durasteel", "tier": 3, "bar": &"durasteel_bar", "ore": &"raw_durasteel"},
	{"name": &"aegisalt", "tier": 4, "bar": &"aegisalt_bar", "ore": &"raw_aegisalt"},
	{"name": &"ferozium", "tier": 5, "bar": &"ferozium_bar", "ore": &"raw_ferozium"},
	{"name": &"violium", "tier": 5, "bar": &"violium_bar", "ore": &"raw_violium"},
	{"name": &"rubium", "tier": 5, "bar": &"rubium_bar", "ore": &"raw_rubium"},
	{"name": &"solarium", "tier": 6, "bar": &"solarium_bar", "ore": &"raw_solarium"},
	# Alloys — no ore, made at a furnace or forge from other bars.
	{"name": &"bronze", "tier": 1, "bar": &"bronze_bar", "ore": &""},
	{"name": &"steel", "tier": 2, "bar": &"steel_bar", "ore": &""},
	{"name": &"electrum", "tier": 3, "bar": &"electrum_bar", "ore": &""},
	{"name": &"impervium", "tier": 5, "bar": &"impervium_bar", "ore": &""},
]

## The ten metals that get a full weapon + armour set, in ladder order. This is
## exactly `content/items/30_weapons.gd`'s `METALS`.
const GEAR_METALS: PackedStringArray = [
	"copper", "iron", "silver", "gold", "titanium",
	"durasteel", "aegisalt", "ferozium", "violium", "solarium",
]

## Tier of each gear metal, from the combat agent's table.
const GEAR_TIER := {
	&"copper": 0, &"iron": 1, &"silver": 1, &"gold": 2, &"titanium": 2,
	&"durasteel": 3, &"aegisalt": 4, &"ferozium": 5, &"violium": 5,
	&"solarium": 6,
}

## The five weapon archetypes the combat agent registers per metal.
const WEAPON_SHAPES: Array[Dictionary] = [
	{"suffix": &"sword", "metal": 5, "handle": 1, "desc": "A straight blade with a wide arc."},
	{"suffix": &"spear", "metal": 4, "handle": 3, "desc": "Reach beats speed."},
	{"suffix": &"hammer", "metal": 8, "handle": 2, "desc": "Slow. Emphatic."},
	{"suffix": &"bow", "metal": 4, "handle": 2, "desc": "Draw to full for a flat, fast shot."},
	{"suffix": &"gun", "metal": 6, "handle": 1, "desc": "Costs energy, not arrows."},
]

## The tool ladder. Silver and gold are too soft for tools, so the pick line
## runs wood → stone → copper → bronze → iron → steel → tungsten → titanium →
## durasteel → aegisalt → impervium → solarium.
const TOOL_MATERIALS: Array[Dictionary] = [
	{"name": &"wooden", "mat": &"plank", "tier": 0, "station": &"workbench"},
	{"name": &"stone", "mat": &"cobblestone", "tier": 0, "station": &"workbench"},
	{"name": &"copper", "mat": &"copper_bar", "tier": 0, "station": &"anvil"},
	{"name": &"bronze", "mat": &"bronze_bar", "tier": 1, "station": &"anvil"},
	{"name": &"iron", "mat": &"iron_bar", "tier": 1, "station": &"anvil"},
	{"name": &"steel", "mat": &"steel_bar", "tier": 2, "station": &"anvil"},
	{"name": &"tungsten", "mat": &"tungsten_bar", "tier": 2, "station": &"forge"},
	{"name": &"titanium", "mat": &"titanium_bar", "tier": 2, "station": &"forge"},
	{"name": &"durasteel", "mat": &"durasteel_bar", "tier": 3, "station": &"forge"},
	{"name": &"aegisalt", "mat": &"aegisalt_bar", "tier": 4, "station": &"forge"},
	{"name": &"impervium", "mat": &"impervium_bar", "tier": 5, "station": &"replicator"},
	{"name": &"solarium", "mat": &"solarium_bar", "tier": 6, "station": &"replicator"},
]

## The extra binding ingredient each tier band demands, so higher gear costs
## more than merely "more metal".
const BINDERS: Array[Dictionary] = [
	{"id": &"string", "from": 0},
	{"id": &"leather", "from": 1},
	{"id": &"iron_gear", "from": 2},
	{"id": &"circuit_board", "from": 4},
	{"id": &"energy_cell", "from": 5},
]

## Universal wooden handle / haft.
const HANDLE: StringName = &"stick"


static func metal(mname: StringName) -> Dictionary:
	for m: Dictionary in METALS:
		if m["name"] == mname:
			return m
	return {}


static func bar_of(mname: StringName) -> StringName:
	return StringName(metal(mname).get("bar", StringName(String(mname) + "_bar")))


static func ore_of(mname: StringName) -> StringName:
	return StringName(metal(mname).get("ore", &""))


## Progression tier of a metal. Gear metals use the combat agent's table so
## weapons, armour and ore all agree.
static func tier_of(mname: StringName) -> int:
	if GEAR_TIER.has(mname):
		return int(GEAR_TIER[mname])
	return int(metal(mname).get("tier", 1))


## Which station works this metal: anvil early, forge mid, replicator late.
static func station_of(mname: StringName) -> StringName:
	var t := tier_of(mname)
	if t <= 1:
		return &"anvil"
	if t <= 4:
		return &"forge"
	return &"replicator"


static func binder_for(tier: int) -> StringName:
	var best: StringName = &"string"
	for b: Dictionary in BINDERS:
		if tier >= int(b["from"]):
			best = StringName(b["id"])
	return best


## Base metal cost curve — gear gets steadily more expensive up the ladder.
static func metal_cost(tier: int, base: int) -> int:
	return base + tier


static func register_all(reg) -> void:
	# ------------------------------------------------------------- furnace fuel
	# Burn-seconds per unit. A plank is the baseline at 8s.
	reg.register_fuel(&"sawdust", 2.0)
	reg.register_fuel(&"straw", 2.0)
	reg.register_fuel(&"stick", 2.0)
	reg.register_fuel(&"plant_fibre", 1.0)
	reg.register_fuel(&"plant_matter", 1.5)
	reg.register_fuel(&"bark_strip", 3.0)
	reg.register_fuel(&"dead_bush", 3.0)
	reg.register_fuel(&"thatch", 4.0)
	reg.register_fuel(&"paper", 3.0)
	reg.register_fuel(&"resin", 6.0)
	reg.register_fuel(&"tallow", 8.0)
	reg.register_fuel(&"plank", 8.0)
	reg.register_fuel(&"wood_planks", 10.0)
	reg.register_fuel(&"driftwood", 12.0)
	reg.register_fuel(&"wood", 15.0)
	reg.register_fuel(&"wood_log", 15.0)
	reg.register_fuel(&"charred_log", 20.0)
	reg.register_fuel(&"cinder_wood", 50.0)
	reg.register_fuel(&"charcoal", 32.0)
	reg.register_fuel(&"coal", 40.0)
	reg.register_fuel(&"raw_coal", 40.0)
	reg.register_fuel(&"carbon_powder", 55.0)
	reg.register_fuel(&"tar", 60.0)
	reg.register_fuel(&"oil", 80.0)
	reg.register_fuel(&"crude_oil", 90.0)
	reg.register_fuel(&"ftl_fuel", 180.0)
	reg.register_fuel(&"refined_ftl_fuel", 400.0)
	reg.register_fuel(&"plasmic_gel", 700.0)
	reg.register_fuel(&"erchius_fuel", 900.0)
	reg.register_fuel(&"solarium_bar", 2400.0)
