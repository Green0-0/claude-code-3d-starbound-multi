## Block-to-block conversions: masonry, metalwork, glass, platforms, doors and
## the wiring parts.
##
## Every output here is a block id from `content/blocks/`, so the placer items
## already exist — this file is the one place in the recipe book where nothing
## has to be invented.
extends RefCounted

static func register_all(reg) -> void:
	_masonry(reg)
	_wood(reg)
	_metal(reg)
	_glass(reg)
	_platforms(reg)
	_doors(reg)
	_wiring(reg)


## `[output, input, in_count, out_count, tier, description]`
static func _masonry(reg) -> void:
	var rows: Array[Array] = [
		[&"stone_brick", &"stone", 4, 4, 0, "Neat, square, forgettable."],
		[&"cracked_stone_brick", &"stone_brick", 4, 4, 0, ""],
		[&"stone_pillar", &"stone_brick", 3, 3, 0, ""],
		[&"sandstone", &"sand", 4, 4, 0, ""],
		[&"sandstone_brick", &"sandstone", 4, 4, 0, ""],
		[&"cracked_sandstone", &"sandstone_brick", 4, 4, 0, ""],
		[&"red_sandstone", &"red_sand", 4, 4, 0, ""],
		[&"basalt_brick", &"basalt", 4, 4, 1, ""],
		[&"slate_tile", &"slate", 4, 4, 1, ""],
		[&"marble_tile", &"marble", 4, 4, 1, ""],
		[&"obsidian_brick", &"obsidian", 4, 4, 2, "Volcanic glass, cut square."],
		[&"ice_brick", &"packed_ice", 4, 4, 1, ""],
		[&"snow_brick", &"packed_snow", 4, 4, 0, ""],
		[&"quartzite", &"quartz", 4, 2, 1, ""],
		[&"packed_snow", &"snow", 4, 1, 0, ""],
		[&"packed_ice", &"ice", 4, 1, 0, ""],
	]
	for row: Array in rows:
		reg.add(CraftRecipe.make("build_%s" % row[0], &"workbench")
			.takes(StringName(row[1]), int(row[2])).gives(StringName(row[0]), int(row[3]))
			.needs_tier(int(row[4]))
			.in_category(&"blocks").in_group(&"construction")
			.describe(String(row[5]))
			.learned_from_material(StringName(row[1])))

	reg.add(CraftRecipe.make("build_mossy_stone_brick", &"workbench")
		.takes(&"stone_brick", 4).takes(&"moss_carpet", 1).gives(&"mossy_stone_brick", 4)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"moss_carpet"))

	reg.add(CraftRecipe.make("build_concrete", &"workbench")
		.takes(&"gravel", 4).takes(&"sand", 2).takes(&"cement_mix", 1)
		.gives(&"concrete", 8)
		.in_category(&"blocks").in_group(&"construction")
		.describe("Cheap, grey, and it holds up a roof.")
		.learned_from_material(&"cement_mix"))

	reg.add(CraftRecipe.make("build_reinforced_concrete", &"assembler")
		.takes(&"concrete", 8).takes(&"iron_nail", 8).gives(&"reinforced_concrete", 8)
		.lasts(1.5).needs_tier(3)
		.in_category(&"blocks").in_group(&"construction")
		.describe("Rated to survive whatever you were planning.")
		.learned_at_tier(3))

	reg.add(CraftRecipe.make("build_hazard_stripe", &"workbench")
		.takes(&"concrete", 4).takes(&"topaz", 1).gives(&"hazard_stripe", 4)
		.needs_tier(2)
		.in_category(&"blocks").in_group(&"construction")
		.learned_at_tier(2))


static func _wood(reg) -> void:
	var rows: Array[Array] = [
		[&"wood_planks", &"plank", 4, 4],
		[&"wood_trim", &"plank", 4, 4],
		[&"carved_trim", &"wood_planks", 4, 4],
		[&"wood_bars", &"plank", 6, 8],
	]
	for row: Array in rows:
		reg.add(CraftRecipe.make("build_%s" % row[0], &"workbench")
			.takes(StringName(row[1]), int(row[2])).gives(StringName(row[0]), int(row[3]))
			.in_category(&"blocks").in_group(&"construction")
			.learned_from_material(StringName(row[1])))

	reg.add(CraftRecipe.make("build_dark_wood", &"workbench")
		.takes(&"wood_planks", 4).takes(&"charcoal", 1).gives(&"dark_wood", 4)
		.in_category(&"blocks").in_group(&"construction")
		.describe("Stained black. Hides fingerprints, shows dust.")
		.learned_from_material(&"charcoal"))

	reg.add(CraftRecipe.make("build_wallpaper", &"workbench")
		.takes(&"plant_matter", 4).takes(&"tree_sap", 1).gives(&"wallpaper", 8)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"tree_sap"))

	reg.add(CraftRecipe.make("build_wallpaper_striped", &"workbench")
		.takes(&"wallpaper", 4).takes(&"luminous_powder", 1).gives(&"wallpaper_striped", 4)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"wallpaper"))

	for c: String in ["red", "blue"]:
		reg.add(CraftRecipe.make("build_carpet_%s" % c, &"workbench")
			.takes(&"cloth", 3).takes(StringName("ruby" if c == "red" else "sapphire"), 1)
			.gives(StringName("carpet_%s" % c), 8)
			.in_category(&"blocks").in_group(&"construction")
			.learned_from_material(&"cloth"))


static func _metal(reg) -> void:
	# Nine bars compress into a storage block; the block gives them back.
	var blocks: Array[Array] = [
		[&"copper_block", &"copper_bar", 0],
		[&"iron_block", &"iron_bar", 1],
		[&"silver_block", &"silver_bar", 1],
		[&"gold_block", &"gold_bar", 2],
	]
	for row: Array in blocks:
		reg.add(CraftRecipe.make("build_%s" % row[0], &"workbench")
			.takes(StringName(row[1]), 9).gives(StringName(row[0]), 1)
			.needs_tier(int(row[2]))
			.in_category(&"blocks").in_group(&"construction")
			.describe("Nine bars, one tidy cube.")
			.learned_from_material(StringName(row[1])))
		reg.add(CraftRecipe.make("unpack_%s" % row[0], &"workbench")
			.takes(StringName(row[0]), 1).gives(StringName(row[1]), 9)
			.needs_tier(int(row[2]))
			.in_category(&"materials").in_group(&"construction")
			.learned_from_material(StringName(row[1])))

	var plating: Array[Array] = [
		[&"iron_plating", &"iron_bar", 1, &"anvil"],
		[&"titanium_plating", &"titanium_bar", 2, &"forge"],
		[&"durasteel_plating", &"durasteel_bar", 3, &"forge"],
		[&"aegisalt_plating", &"aegisalt_bar", 4, &"forge"],
	]
	for row: Array in plating:
		reg.add(CraftRecipe.make("build_%s" % row[0], StringName(row[3]))
			.takes(StringName(row[1]), 2).gives(StringName(row[0]), 4)
			.lasts(0.8).needs_tier(int(row[2]))
			.in_category(&"blocks").in_group(&"metalwork")
			.describe("Hull plate. Blast-resistant, and it looks the part.")
			.learned_from_material(StringName(row[1])))

	reg.add(CraftRecipe.make("build_steel_plate", &"anvil")
		.takes(&"iron_bar", 2).takes(&"carbon_powder", 1).gives(&"steel_plate", 4)
		.lasts(1.0).needs_tier(1)
		.in_category(&"blocks").in_group(&"metalwork")
		.learned_from_material(&"carbon_powder"))

	reg.add(CraftRecipe.make("build_steel_floor", &"anvil")
		.takes(&"steel_plate", 2).gives(&"steel_floor", 4)
		.lasts(0.8).needs_tier(1)
		.in_category(&"blocks").in_group(&"metalwork")
		.learned_from_material(&"steel_plate"))

	reg.add(CraftRecipe.make("build_iron_bars", &"anvil")
		.takes(&"iron_bar", 3).gives(&"iron_bars", 8)
		.lasts(0.8).needs_tier(1)
		.in_category(&"blocks").in_group(&"metalwork")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("build_metal_grate", &"anvil")
		.takes(&"iron_bar", 2).gives(&"metal_grate", 6)
		.lasts(0.8).needs_tier(1)
		.in_category(&"blocks").in_group(&"metalwork")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("build_metal_pillar", &"anvil")
		.takes(&"steel_plate", 3).gives(&"metal_pillar", 3)
		.lasts(0.8).needs_tier(1)
		.in_category(&"blocks").in_group(&"metalwork")
		.learned_from_material(&"steel_plate"))

	reg.add(CraftRecipe.make("build_metal_trim", &"anvil")
		.takes(&"iron_bar", 1).takes(&"silver_bar", 1).gives(&"metal_trim", 4)
		.lasts(0.8).needs_tier(1)
		.in_category(&"blocks").in_group(&"metalwork")
		.learned_from_material(&"silver_bar"))

	reg.add(CraftRecipe.make("build_gilded_trim", &"forge")
		.takes(&"gold_bar", 2).takes(&"marble", 2).gives(&"gilded_trim", 4)
		.lasts(1.5).needs_tier(2)
		.in_category(&"blocks").in_group(&"metalwork")
		.describe("Ostentatious. That is the whole point.")
		.learned_from_material(&"gold_bar"))

	reg.add(CraftRecipe.make("build_scaffold", &"anvil")
		.takes(&"iron_bar", 1).takes(&"plank", 2).gives(&"scaffold", 8)
		.lasts(0.6).needs_tier(1)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("build_metal_ladder", &"anvil")
		.takes(&"iron_bar", 2).gives(&"metal_ladder", 8)
		.lasts(0.6).needs_tier(1)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("build_circuit_panel", &"assembler")
		.takes(&"steel_plate", 2).takes(&"copper_wire", 4).gives(&"circuit_panel", 4)
		.lasts(1.5).needs_tier(3)
		.in_category(&"blocks").in_group(&"electronics")
		.learned_at_tier(3))

	reg.add(CraftRecipe.make("build_bone_block", &"workbench")
		.takes(&"bone", 9).gives(&"bone_block", 1)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"bone"))

	reg.add(CraftRecipe.make("build_crystal_block", &"workbench")
		.takes(&"crystal_shard", 9).gives(&"crystal_block", 1)
		.needs_tier(1)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"crystal_shard"))


static func _glass(reg) -> void:
	var stains: Array[Array] = [
		[&"stained_glass_red", &"ruby"],
		[&"stained_glass_green", &"emerald"],
		[&"stained_glass_blue", &"sapphire"],
	]
	for row: Array in stains:
		reg.add(CraftRecipe.make("build_%s" % row[0], &"workbench")
			.takes(&"glass", 6).takes(StringName(row[1]), 1)
			.gives(StringName(row[0]), 6)
			.needs_tier(2)
			.in_category(&"blocks").in_group(&"construction")
			.describe("Ground gemstone in the melt. Expensive, and worth it.")
			.learned_from_material(StringName(row[1])))

	reg.add(CraftRecipe.make("build_tinted_glass", &"workbench")
		.takes(&"glass", 4).takes(&"carbon_powder", 1).gives(&"tinted_glass", 4)
		.needs_tier(1)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"carbon_powder"))

	reg.add(CraftRecipe.make("build_frosted_glass", &"workbench")
		.takes(&"glass", 4).takes(&"quartz", 1).gives(&"frosted_glass", 4)
		.needs_tier(1)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"quartz"))

	reg.add(CraftRecipe.make("build_reinforced_glass", &"assembler")
		.takes(&"glass", 6).takes(&"titanium_bar", 1).takes(&"polymer", 1)
		.gives(&"reinforced_glass", 6)
		.lasts(1.5).needs_tier(3)
		.in_category(&"blocks").in_group(&"construction")
		.describe("Rated to hold back an ocean, or a vacuum.")
		.learned_at_tier(3))

	reg.add(CraftRecipe.make("build_parallax_glass", &"assembler")
		.takes(&"reinforced_glass", 4).takes(&"prism_shard", 1)
		.gives(&"parallax_glass", 4)
		.lasts(3.0).needs_tier(5)
		.in_category(&"blocks").in_group(&"construction")
		.describe("Shows the layer behind it as though it were here.")
		.learned_at_tier(5))


static func _platforms(reg) -> void:
	var rows: Array[Array] = [
		[&"stone_platform", &"stone", 4, 8, 0, &"workbench"],
		[&"metal_platform", &"iron_bar", 2, 8, 1, &"anvil"],
		[&"glass_platform", &"glass", 4, 8, 1, &"workbench"],
	]
	for row: Array in rows:
		reg.add(CraftRecipe.make("build_%s" % row[0], StringName(row[5]))
			.takes(StringName(row[1]), int(row[2])).gives(StringName(row[0]), int(row[3]))
			.needs_tier(int(row[4]))
			.in_category(&"blocks").in_group(&"construction")
			.describe("Stand on it; hold down to drop through.")
			.learned_from_material(StringName(row[1])))


static func _doors(reg) -> void:
	var doors: Array[Array] = [
		[&"iron_door", &"iron_bar", 6, &"anvil", 1],
		[&"glass_door", &"glass", 6, &"workbench", 1],
		[&"blast_door", &"durasteel_bar", 8, &"assembler", 3],
		[&"airlock", &"titanium_bar", 10, &"assembler", 4],
	]
	for d: Array in doors:
		var r := CraftRecipe.make("build_%s" % d[0], StringName(d[3])) \
			.takes(StringName(d[1]), int(d[2])) \
			.gives(StringName(d[0]), 1) \
			.lasts(1.0 + float(d[4]) * 0.4) \
			.needs_tier(int(d[4])) \
			.in_category(&"furniture").in_group(&"construction") \
			.learned_from_material(StringName(d[1]))
		if int(d[4]) >= 3:
			r.takes(&"circuit_board", 1).takes(&"electric_motor", 1)
		reg.add(r)

	reg.add(CraftRecipe.make("build_door_frame_metal", &"anvil")
		.takes(&"iron_bar", 3).gives(&"door_frame_metal", 2)
		.lasts(0.8).needs_tier(1)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("build_hatch", &"anvil")
		.takes(&"iron_bar", 5).takes(&"iron_gear", 1).gives(&"hatch", 1)
		.lasts(1.0).needs_tier(1)
		.in_category(&"furniture").in_group(&"construction")
		.learned_from_material(&"iron_gear"))


## Wiring is the objects agent's subsystem; here we only make the parts.
static func _wiring(reg) -> void:
	reg.add(CraftRecipe.make("copper_wire", &"workbench")
		.takes(&"copper_bar", 1).gives(&"copper_wire", 6)
		.in_category(&"wiring").in_group(&"electronics")
		.describe("Drawn thin and coiled. Everything electrical starts here.")
		.learned_from_material(&"copper_bar"))

	var parts: Array[Dictionary] = [
		{"id": &"lever", "cost": {&"copper_wire": 2, &"plank": 1}, "tier": 1, "count": 2},
		{"id": &"button", "cost": {&"copper_wire": 2, &"cobblestone": 1}, "tier": 1, "count": 2},
		{"id": &"pressure_plate", "cost": {&"copper_wire": 2, &"plank": 2}, "tier": 1, "count": 2},
		{"id": &"wire_relay", "cost": {&"copper_wire": 4, &"iron_bar": 1}, "tier": 1, "count": 4},
		{"id": &"logic_and", "cost": {&"copper_wire": 4, &"silicon_wafer": 1}, "tier": 2, "count": 2},
		{"id": &"logic_or", "cost": {&"copper_wire": 4, &"silicon_wafer": 1}, "tier": 2, "count": 2},
		{"id": &"logic_not", "cost": {&"copper_wire": 3, &"silicon_wafer": 1}, "tier": 2, "count": 2},
		{"id": &"logic_xor", "cost": {&"copper_wire": 5, &"silicon_wafer": 1}, "tier": 2, "count": 2},
		{"id": &"timer_module", "cost": {&"copper_wire": 4, &"iron_gear": 1}, "tier": 2, "count": 2},
		{"id": &"proximity_sensor", "cost": {&"circuit_board": 1, &"sensor_lens": 1}, "tier": 3, "count": 2},
		{"id": &"day_sensor", "cost": {&"circuit_board": 1, &"glass": 3}, "tier": 3, "count": 1},
		{"id": &"liquid_sensor", "cost": {&"circuit_board": 1, &"rubber": 2}, "tier": 3, "count": 1},
		{"id": &"layer_sensor", "cost": {&"circuit_board": 1, &"prism_shard": 1}, "tier": 4, "count": 1},
	]
	for p: Dictionary in parts:
		var r := CraftRecipe.make("wire_%s" % p["id"], &"assembler") \
			.gives(StringName(p["id"]), int(p["count"])) \
			.lasts(0.8).needs_tier(int(p["tier"])) \
			.in_category(&"wiring").in_group(&"electronics") \
			.ordered(int(p["tier"])) \
			.learned_from_material(&"copper_wire")
		var cost: Dictionary = p["cost"]
		for k: StringName in cost:
			r.takes(k, int(cost[k]))
		reg.add(r)
