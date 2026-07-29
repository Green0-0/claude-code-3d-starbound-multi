## The tool ladder — pickaxes, axes, shovels, hoes, drills — plus the matter
## manipulator upgrade modules.
##
## Ids follow `<material>_<tool>`: `wooden_pickaxe`, `iron_axe`,
## `titanium_drill`. Manipulator parts are `mm_<feature>_<level>` (modules) and
## `mm_core_<n>` (cores, in `advanced.gd`).
##
## Handles are `stick`, from `content/items/10_materials.gd`.
##
## No content file claims tool ids yet, so `<material>_<tool>` is this module's
## convention — the tools agent should follow it.
extends RefCounted

static func register_all(reg) -> void:
	_ladder_tools(reg)
	_drills(reg)
	_manipulator(reg)
	_misc(reg)


## Pickaxe / axe / shovel / hoe, one per entry in `CraftLadder.TOOL_MATERIALS`.
static func _ladder_tools(reg) -> void:
	var shapes: Array[Dictionary] = [
		{"suffix": &"pickaxe", "mat": 3, "handle": 2, "desc": "Chews through stone and ore."},
		{"suffix": &"axe", "mat": 3, "handle": 2, "desc": "Chews through wood."},
		{"suffix": &"shovel", "mat": 1, "handle": 2, "desc": "Moves dirt in a hurry."},
		{"suffix": &"hoe", "mat": 2, "handle": 2, "desc": "Turns soil into farmland."},
	]
	for tm: Dictionary in CraftLadder.TOOL_MATERIALS:
		var mname := StringName(tm["name"])
		var mat := StringName(tm["mat"])
		var tier := int(tm["tier"])
		var station := StringName(tm["station"])
		for s: Dictionary in shapes:
			# Shovels and hoes stop being worth making past durasteel.
			if (s["suffix"] == &"shovel" or s["suffix"] == &"hoe") and tier >= 4:
				continue
			var item := StringName("%s_%s" % [mname, s["suffix"]])
			var r := CraftRecipe.make("craft_%s" % item, station) \
				.takes(mat, CraftLadder.metal_cost(tier, int(s["mat"]))) \
				.gives(item, 1) \
				.lasts(0.6 + float(tier) * 0.4) \
				.needs_tier(tier) \
				.in_category(&"tools").in_group(&"toolsmith") \
				.ordered(tier * 10) \
				.describe(String(s["desc"]))
			if mat != CraftLadder.HANDLE:
				r.takes(CraftLadder.HANDLE, int(s["handle"]))
			if tier >= 1:
				r.takes(CraftLadder.binder_for(tier), 1)
			if tier == 0 and (mname == &"wooden" or mname == &"stone"):
				r.known_at_start()
			else:
				r.learned_from_material(mat)
			reg.add(r)


## Drills are the fast, expensive branch: no handle, lots of metal, a motor.
static func _drills(reg) -> void:
	var drills: Array[Dictionary] = [
		{"name": &"iron", "tier": 1, "station": &"anvil", "motor": &"iron_gear"},
		{"name": &"titanium", "tier": 2, "station": &"forge", "motor": &"electric_motor"},
		{"name": &"durasteel", "tier": 3, "station": &"forge", "motor": &"electric_motor"},
		{"name": &"aegisalt", "tier": 4, "station": &"forge", "motor": &"hydraulic_piston"},
		{"name": &"ferozium", "tier": 5, "station": &"replicator", "motor": &"power_core"},
	]
	for d: Dictionary in drills:
		var mname := StringName(d["name"])
		var tier := int(d["tier"])
		reg.add(CraftRecipe.make("craft_%s_drill" % mname, StringName(d["station"]))
			.takes(CraftLadder.bar_of(mname), 8 + tier * 2)
			.takes(StringName(d["motor"]), 1 + tier / 3)
			.takes(&"energy_cell", maxi(1, tier - 1))
			.gives(StringName("%s_drill" % mname), 1)
			.lasts(2.0 + float(tier)).needs_tier(tier)
			.in_category(&"tools").in_group(&"toolsmith").ordered(tier * 10 + 5)
			.describe("Mines a wider bite, and drinks power doing it.")
			.learned_from_material(StringName(d["motor"])))


## Matter-manipulator modules. Installing one is the tech agent's business; we
## only build the module item. Each is gated on the progression tier.
static func _manipulator(reg) -> void:
	var mods: Array[Dictionary] = [
		{"id": &"mm_range_1", "tier": 1, "name": "Range Module I", "station": &"anvil",
		"cost": {&"copper_bar": 8, &"crystal_shard": 3}},
		{"id": &"mm_range_2", "tier": 3, "name": "Range Module II", "station": &"assembler",
		"cost": {&"titanium_bar": 10, &"quartz": 6, &"circuit_board": 2}},
		{"id": &"mm_range_3", "tier": 5, "name": "Range Module III", "station": &"replicator",
		"cost": {&"ferozium_bar": 12, &"quantum_processor": 2, &"prism_shard": 4}},
		{"id": &"mm_speed_1", "tier": 1, "name": "Speed Module I", "station": &"anvil",
		"cost": {&"iron_bar": 10, &"coal": 8}},
		{"id": &"mm_speed_2", "tier": 3, "name": "Speed Module II", "station": &"assembler",
		"cost": {&"titanium_bar": 12, &"electric_motor": 2, &"energy_cell": 4}},
		{"id": &"mm_speed_3", "tier": 5, "name": "Speed Module III", "station": &"replicator",
		"cost": {&"violium_bar": 12, &"power_core": 1, &"quantum_processor": 2}},
		{"id": &"mm_size_1", "tier": 2, "name": "Field Size Module I", "station": &"anvil",
		"cost": {&"iron_bar": 12, &"silver_bar": 4, &"quartz": 4}},
		{"id": &"mm_size_2", "tier": 4, "name": "Field Size Module II", "station": &"assembler",
		"cost": {&"durasteel_bar": 12, &"advanced_circuit": 2, &"amethyst": 4}},
		{"id": &"mm_liquid", "tier": 3, "name": "Liquid Collection Module", "station": &"assembler",
		"cost": {&"glass": 12, &"iron_bar": 8, &"rubber": 4}},
		{"id": &"mm_paint", "tier": 2, "name": "Paint Module", "station": &"assembler",
		"cost": {&"polymer": 4, &"ruby": 1, &"sapphire": 1, &"emerald": 1}},
		{"id": &"mm_scan", "tier": 4, "name": "Scanner Module", "station": &"assembler",
		"cost": {&"sensor_lens": 2, &"advanced_circuit": 2, &"aegisalt_bar": 4}},
		{"id": &"mm_precision", "tier": 6, "name": "Precision Module", "station": &"replicator",
		"cost": {&"solarium_bar": 8, &"quantum_processor": 4, &"nanowire": 6}},
	]
	for md: Dictionary in mods:
		var r := CraftRecipe.make("craft_%s" % md["id"], StringName(md["station"])) \
			.gives(StringName(md["id"]), 1) \
			.named(String(md["name"])) \
			.lasts(2.0 + float(md["tier"])) \
			.needs_tier(int(md["tier"])) \
			.in_category(&"tech").in_group(&"toolsmith") \
			.ordered(int(md["tier"]) * 10) \
			.describe("Bolts onto the matter manipulator.") \
			.learned_at_tier(int(md["tier"]))
		var cost: Dictionary = md["cost"]
		for k: StringName in cost:
			r.takes(k, int(cost[k]))
		reg.add(r)


## Everything that is a tool but not on the ladder.
static func _misc(reg) -> void:
	reg.add(CraftRecipe.make("fishing_rod", &"workbench")
		.takes(&"plank", 4).takes(&"plant_fibre", 4).gives(&"fishing_rod", 1)
		.lasts(1.0)
		.in_category(&"tools").in_group(&"general")
		.known_at_start())

	reg.add(CraftRecipe.make("bug_net", &"workbench")
		.takes(&"plank", 3).takes(&"cloth", 2).gives(&"bug_net", 1)
		.lasts(1.0)
		.in_category(&"tools").in_group(&"general")
		.learned_from_material(&"cloth"))

	reg.add(CraftRecipe.make("watering_can", &"anvil")
		.takes(&"iron_bar", 4).gives(&"watering_can", 1)
		.lasts(1.0).needs_tier(1)
		.in_category(&"tools").in_group(&"toolsmith")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("bucket", &"anvil")
		.takes(&"iron_bar", 3).gives(&"bucket", 1)
		.lasts(0.8).needs_tier(1)
		.in_category(&"tools").in_group(&"toolsmith")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("wire_cutters", &"anvil")
		.takes(&"iron_bar", 3).takes(&"rubber", 2).gives(&"wire_cutters", 1)
		.lasts(1.0).needs_tier(2)
		.in_category(&"tools").in_group(&"toolsmith")
		.describe("Snips wiring without electrocuting you. Mostly.")
		.learned_from_material(&"copper_wire"))

	reg.add(CraftRecipe.make("wrench", &"anvil")
		.takes(&"iron_bar", 5).gives(&"wrench", 1)
		.lasts(1.0).needs_tier(1)
		.in_category(&"tools").in_group(&"toolsmith")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("grappling_hook", &"assembler")
		.takes(&"titanium_bar", 6).takes(&"rope", 4).takes(&"iron_gear", 2)
		.gives(&"grappling_hook", 1)
		.lasts(3.0).needs_tier(3)
		.in_category(&"tools").in_group(&"toolsmith")
		.describe("Traversal, in a world where a wall becomes a corridor.")
		.learned_at_tier(3))

	reg.add(CraftRecipe.make("handheld_scanner", &"assembler")
		.takes(&"circuit_board", 3).takes(&"sensor_lens", 1).takes(&"silver_bar", 4)
		.gives(&"handheld_scanner", 1)
		.lasts(2.5).needs_tier(3)
		.in_category(&"tools").in_group(&"electronics")
		.describe("Names the block, the beast and the biome.")
		.learned_from_material(&"sensor_lens"))

	reg.add(CraftRecipe.make("paint_gun", &"assembler")
		.takes(&"iron_bar", 5).takes(&"polymer", 3).takes(&"rubber", 3)
		.gives(&"paint_gun", 1)
		.lasts(2.0).needs_tier(3)
		.in_category(&"tools").in_group(&"electronics")
		.learned_at_tier(3))

	reg.add(CraftRecipe.make("ore_detector", &"assembler")
		.takes(&"sensor_lens", 2).takes(&"copper_wire", 12).takes(&"energy_cell", 2)
		.gives(&"ore_detector", 1)
		.lasts(3.0).needs_tier(3)
		.in_category(&"tools").in_group(&"electronics")
		.describe("Pings when there is metal on another layer.")
		.learned_at_tier(3))
