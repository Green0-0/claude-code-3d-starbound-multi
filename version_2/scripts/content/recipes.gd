extends RefCounted

## The recipe book.
##
## Ordering matters for readability rather than for correctness: negative
## `ordered()` values float the first-ten-minutes recipes to the top of the
## hand-crafting tab, so a new player's list opens on exactly the things they
## are about to need.


static func register_all() -> void:
	_hand()
	_workbench()
	_smelting()
	_metalwork()
	_building()
	_tools()
	_weapons()
	_armor()
	_food()
	_tech()
	_taming()


static func r(id: String, station: StringName) -> Crafting.Recipe:
	return Crafting.add(Crafting.make(id, station))


# ============================================================== bare hands ====
static func _hand() -> void:
	r("planks_from_log", &"hand").takes(&"wood_log", 1).gives(&"wood_planks", 4) \
		.byproduct(&"sawdust", 1, 0.5).in_category(&"materials").ordered(-100) \
		.describe("Split a log into rough boards.").known_at_start()

	r("sticks", &"hand").takes(&"wood_planks", 1).gives(&"stick", 4) \
		.in_category(&"materials").ordered(-99) \
		.describe("Four handles out of one board.").known_at_start()

	r("plant_string", &"hand").takes(&"plant_fibre", 3).gives(&"string", 1) \
		.in_category(&"materials").ordered(-98) \
		.describe("Twist fibre until it stops being fibre.").known_at_start()

	r("torch", &"hand").takes(&"stick", 1).takes(&"raw_coal", 1).gives(&"torch", 4) \
		.in_category(&"light").ordered(-97) \
		.describe("Light is the difference between mining and dying.").known_at_start()

	r("torch_charcoal", &"hand").takes(&"stick", 1).takes(&"charcoal", 1) \
		.gives(&"torch", 4).in_category(&"light").ordered(-96) \
		.learned_from_material(&"charcoal")

	r("torch_glow", &"hand").takes(&"stick", 1).takes(&"luminous_powder", 1) \
		.gives(&"torch", 6).in_category(&"light") \
		.describe("Cold light. Will not set the forest alight.") \
		.learned_from_material(&"luminous_powder")

	r("workbench", &"hand").takes(&"wood_planks", 8).gives(&"workbench", 1) \
		.in_category(&"objects").ordered(-95) \
		.describe("A flat surface and a vice. Everything starts here.").known_at_start()

	r("campfire", &"hand").takes(&"wood_planks", 4).takes(&"stick", 2) \
		.takes(&"cobblestone", 3).gives(&"campfire", 1) \
		.in_category(&"objects").ordered(-94) \
		.describe("Cooks, warms, and keeps the dark at arm's length.").known_at_start()

	r("stone_furnace", &"hand").takes(&"cobblestone", 12).gives(&"furnace", 1) \
		.in_category(&"objects").ordered(-93) \
		.describe("A stone box that holds a fire in one place.").known_at_start()

	r("stone_pickaxe", &"hand").takes(&"stick", 2).takes(&"cobblestone", 3) \
		.takes(&"plant_fibre", 2).gives(&"stone_pickaxe", 1) \
		.in_category(&"tools").ordered(-92) \
		.describe("Barely a tool. Enough to find a better one.").known_at_start()

	r("stone_axe", &"hand").takes(&"stick", 2).takes(&"cobblestone", 3) \
		.takes(&"plant_fibre", 2).gives(&"stone_axe", 1) \
		.in_category(&"tools").ordered(-91).known_at_start()

	r("flint_spear", &"hand").takes(&"stick", 3).takes(&"flint", 3) \
		.takes(&"plant_fibre", 2).gives(&"copper_spear", 1) \
		.in_category(&"weapons").ordered(-90) \
		.describe("Pointy end goes in the monster.").known_at_start()

	r("wooden_ladder", &"hand").takes(&"wood_planks", 4).takes(&"stick", 2) \
		.gives(&"wooden_ladder", 6).in_category(&"building").ordered(-89) \
		.describe("The cheapest way down that you can also come back up.") \
		.known_at_start()

	r("wood_platform", &"hand").takes(&"wood_planks", 2).gives(&"wood_platform", 6) \
		.in_category(&"building").ordered(-88).known_at_start()

	r("bandage", &"hand").takes(&"plant_fibre", 3).takes(&"plant_matter", 1) \
		.gives(&"bandage", 1).in_category(&"medical") \
		.describe("Stops the bleeding. Does nothing about the cause.") \
		.known_at_start()


# =============================================================== workbench ====
static func _workbench() -> void:
	r("rope", &"workbench").takes(&"string", 4).gives(&"rope", 1) \
		.in_category(&"materials").learned_from_material(&"string")
	r("cloth", &"workbench").takes(&"cotton_wool", 3).gives(&"cloth", 1) \
		.in_category(&"materials").learned_from_material(&"cotton_wool")
	r("paper", &"workbench").takes(&"plant_matter", 3).gives(&"paper", 2) \
		.in_category(&"materials").learned_from_material(&"plant_matter")
	r("leather", &"workbench").takes(&"hide", 2).takes(&"salt", 1) \
		.gives(&"leather", 1).in_category(&"materials") \
		.describe("Salt, time and a smell you will not get out of the workshop.") \
		.learned_from_material(&"hide")
	r("tough_leather", &"workbench").takes(&"leather", 3).takes(&"resin", 1) \
		.gives(&"tough_leather", 1).in_category(&"materials") \
		.learned_from_material(&"resin")
	r("chest", &"workbench").takes(&"wood_planks", 12).takes(&"iron_bar", 2) \
		.gives(&"chest", 1).in_category(&"objects").ordered(-40) \
		.describe("Twenty-four slots of somewhere else to put things.") \
		.learned_from_material(&"iron_bar")
	r("barrel", &"workbench").takes(&"wood_planks", 8).gives(&"barrel", 1) \
		.in_category(&"objects").known_at_start()
	r("anvil", &"workbench").takes(&"iron_bar", 8).takes(&"stone_brick", 4) \
		.gives(&"anvil", 1).in_category(&"objects").ordered(-39) \
		.learned_from_material(&"iron_bar")
	r("kitchen", &"workbench").takes(&"wood_planks", 10).takes(&"iron_bar", 3) \
		.takes(&"glass", 2).gives(&"kitchen", 1).in_category(&"objects") \
		.learned_from_material(&"iron_bar")
	r("bed", &"workbench").takes(&"wood_planks", 8).takes(&"cloth", 4) \
		.gives(&"bed", 1).in_category(&"objects").learned_from_material(&"cloth")
	r("chair", &"workbench").takes(&"wood_planks", 5).gives(&"chair", 1) \
		.in_category(&"objects").known_at_start()
	r("table", &"workbench").takes(&"wood_planks", 7).gives(&"table", 1) \
		.in_category(&"objects").known_at_start()
	r("wooden_door", &"workbench").takes(&"wood_planks", 6).takes(&"iron_bar", 1) \
		.gives(&"wooden_door", 1).in_category(&"objects") \
		.learned_from_material(&"iron_bar")
	r("brazier", &"workbench").takes(&"iron_bar", 3).takes(&"cobblestone", 4) \
		.gives(&"brazier", 1).in_category(&"light").learned_from_material(&"iron_bar")
	r("waypoint_flag", &"workbench").takes(&"stick", 2).takes(&"cloth", 2) \
		.gives(&"waypoint_flag", 1).in_category(&"objects") \
		.learned_from_material(&"cloth")
	r("capture_pod", &"workbench").takes(&"iron_bar", 2).takes(&"battery", 1) \
		.takes(&"crystal_shard", 2).gives(&"monster_capture_pod", 1) \
		.in_category(&"tools").learned_from_material(&"battery")
	r("repair_kit", &"workbench").takes(&"iron_bar", 2).takes(&"adhesive", 1) \
		.gives(&"repair_kit", 1).in_category(&"tools") \
		.learned_from_material(&"adhesive")
	r("empty_flask", &"workbench").takes(&"glass", 2).gives(&"empty_flask", 2) \
		.in_category(&"materials").learned_from_material(&"glass")
	r("adhesive", &"workbench").takes(&"tree_sap", 2).takes(&"plant_matter", 1) \
		.gives(&"adhesive", 2).in_category(&"materials") \
		.learned_from_material(&"tree_sap")


# ================================================================ smelting ====
static func _smelt(metal: StringName, display: String, tier: int) -> void:
	r("smelt_" + String(metal), &"furnace").takes(StringName("raw_" + String(metal)), 2) \
		.takes(&"coal", 1).gives(StringName(String(metal) + "_bar"), 1) \
		.at_tier(tier).takes_time(4.0).in_category(&"bars").in_group(&"smelting") \
		.describe("Two of raw %s and a lump of coal." % display.to_lower()) \
		.learned_from_material(StringName("raw_" + String(metal)))


static func _smelting() -> void:
	for row: Array in [
		[&"copper", "Copper", 0], [&"tin", "Tin", 0], [&"iron", "Iron", 0],
		[&"lead", "Lead", 1], [&"silver", "Silver", 1], [&"gold", "Gold", 1],
		[&"tungsten", "Tungsten", 2], [&"titanium", "Titanium", 2],
		[&"platinum", "Platinum", 2], [&"cerulium", "Cerulium", 2],
		[&"durasteel", "Durasteel", 2], [&"aegisalt", "Aegisalt", 2],
		[&"ferozium", "Ferozium", 2], [&"violium", "Violium", 2],
		[&"rubium", "Rubium", 2], [&"solarium", "Solarium", 2],
	]:
		_smelt(row[0], String(row[1]), int(row[2]))

	r("smelt_coal", &"furnace").takes(&"raw_coal", 1).gives(&"coal", 1) \
		.takes_time(2.0).in_category(&"bars").in_group(&"smelting").at_tier(0) \
		.describe("Bake the stone grit off it.").known_at_start()
	r("charcoal", &"furnace").takes(&"wood_log", 1).gives(&"charcoal", 2) \
		.takes_time(3.0).in_category(&"bars").in_group(&"smelting").at_tier(0) \
		.describe("Wood cooked without air.").known_at_start()
	r("glass_from_sand", &"furnace").takes(&"sand", 2).gives(&"glass", 1) \
		.takes_time(3.0).in_category(&"materials").in_group(&"smelting").at_tier(0) \
		.known_at_start()
	r("brick_from_clay", &"furnace").takes(&"clay_lump", 2).gives(&"brick", 1) \
		.takes_time(3.0).in_category(&"materials").in_group(&"smelting").at_tier(0) \
		.learned_from_material(&"clay_lump")
	r("silicon", &"furnace").takes(&"raw_silicon", 2).takes(&"coal", 1) \
		.gives(&"silicon_wafer", 1).takes_time(5.0).at_tier(1) \
		.in_category(&"components").in_group(&"smelting") \
		.learned_from_material(&"raw_silicon")
	r("cooked_meat_fire", &"furnace").takes(&"raw_meat", 1).gives(&"cooked_meat", 1) \
		.takes_time(3.0).at_tier(0).in_category(&"food").in_group(&"cooking") \
		.learned_from_material(&"raw_meat")


# =============================================================== metalwork ====
static func _metalwork() -> void:
	r("bronze_bar", &"forge").takes(&"copper_bar", 2).takes(&"tin_bar", 1) \
		.gives(&"bronze_bar", 2).at_tier(1).in_category(&"bars") \
		.describe("Copper is soft. Tin fixes that.") \
		.learned_from_material(&"tin_bar")
	r("steel_bar", &"forge").takes(&"iron_bar", 2).takes(&"coal", 2) \
		.gives(&"steel_bar", 2).at_tier(2).in_category(&"bars") \
		.learned_from_material(&"iron_bar")
	r("electrum_bar", &"forge").takes(&"gold_bar", 1).takes(&"silver_bar", 1) \
		.gives(&"electrum_bar", 2).at_tier(2).in_category(&"bars") \
		.learned_from_material(&"gold_bar")
	r("impervium_bar", &"forge").takes(&"aegisalt_bar", 1).takes(&"ferozium_bar", 1) \
		.takes(&"violium_bar", 1).gives(&"impervium_bar", 2).at_tier(4) \
		.in_category(&"bars").learned_from_material(&"violium_bar")
	r("cosmic_alloy", &"replicator").takes(&"impervium_bar", 2) \
		.takes(&"cosmic_dust", 4).takes(&"star_dust", 2).gives(&"cosmic_alloy", 1) \
		.at_tier(6).in_category(&"bars").learned_from_material(&"cosmic_dust")

	r("copper_wire", &"anvil").takes(&"copper_bar", 1).gives(&"copper_wire", 4) \
		.in_category(&"components").learned_from_material(&"copper_bar")
	r("iron_gear", &"anvil").takes(&"iron_bar", 2).gives(&"iron_gear", 2) \
		.in_category(&"components").learned_from_material(&"iron_bar")
	r("circuit_board", &"assembler").takes(&"silicon_wafer", 1) \
		.takes(&"copper_wire", 3).takes(&"gold_bar", 1).gives(&"circuit_board", 1) \
		.at_tier(2).in_category(&"components").learned_from_material(&"silicon_wafer")
	r("advanced_circuit", &"assembler").takes(&"circuit_board", 2) \
		.takes(&"platinum_bar", 1).takes(&"nanowire", 1).gives(&"advanced_circuit", 1) \
		.at_tier(4).in_category(&"components").learned_from_material(&"nanowire")
	r("battery", &"assembler").takes(&"copper_wire", 2).takes(&"lead_bar", 1) \
		.takes(&"sulphur", 2).gives(&"battery", 1).at_tier(2) \
		.in_category(&"components").learned_from_material(&"lead_bar")
	r("energy_cell", &"assembler").takes(&"battery", 2).takes(&"crystal_shard", 2) \
		.gives(&"energy_cell", 1).at_tier(3).in_category(&"components") \
		.learned_from_material(&"battery")
	r("power_core", &"assembler").takes(&"energy_cell", 3).takes(&"diamond", 1) \
		.takes(&"advanced_circuit", 1).gives(&"power_core", 1).at_tier(5) \
		.in_category(&"components").learned_from_material(&"advanced_circuit")
	r("nanowire", &"chemistry").takes(&"carbon_powder", 4).takes(&"silver_bar", 1) \
		.gives(&"nanowire", 2).at_tier(4).in_category(&"components") \
		.learned_from_material(&"carbon_powder")
	r("polymer", &"chemistry").takes(&"tar", 2).takes(&"sulphur", 1) \
		.gives(&"polymer", 2).at_tier(3).in_category(&"materials") \
		.learned_from_material(&"tar")
	r("gunpowder", &"chemistry").takes(&"charcoal", 1).takes(&"sulphur", 1) \
		.takes(&"saltpetre", 1).gives(&"gunpowder", 3).at_tier(2) \
		.in_category(&"materials").learned_from_material(&"saltpetre")
	r("carbon_powder", &"chemistry").takes(&"coal", 2).gives(&"carbon_powder", 3) \
		.at_tier(2).in_category(&"materials").learned_from_material(&"coal")

	# --- machines
	r("forge", &"anvil").takes(&"stone_brick", 20).takes(&"iron_bar", 10) \
		.takes(&"coal", 8).gives(&"forge", 1).in_category(&"objects").ordered(-30) \
		.learned_from_material(&"stone_brick")
	r("assembler", &"forge").takes(&"steel_bar", 12).takes(&"circuit_board", 4) \
		.takes(&"iron_gear", 6).gives(&"assembler", 1).at_tier(3) \
		.in_category(&"objects").learned_from_material(&"circuit_board")
	r("chemistry_lab", &"forge").takes(&"steel_bar", 8).takes(&"glass", 12) \
		.takes(&"copper_wire", 6).gives(&"chemistry_lab", 1).at_tier(3) \
		.in_category(&"objects").learned_from_material(&"steel_bar")
	r("replicator", &"assembler").takes(&"durasteel_bar", 16) \
		.takes(&"advanced_circuit", 4).takes(&"power_core", 2) \
		.gives(&"replicator", 1).at_tier(5).in_category(&"objects") \
		.learned_from_material(&"power_core")
	r("manipulator_bench", &"anvil").takes(&"iron_bar", 8).takes(&"crystal_shard", 6) \
		.takes(&"copper_wire", 4).gives(&"manipulator_bench", 1) \
		.in_category(&"objects").learned_from_material(&"crystal_shard")
	r("tech_console", &"assembler").takes(&"steel_bar", 8).takes(&"circuit_board", 3) \
		.takes(&"sensor_lens", 2).gives(&"tech_console", 1).at_tier(3) \
		.in_category(&"objects").learned_from_material(&"sensor_lens")
	r("refinery", &"forge").takes(&"steel_bar", 10).takes(&"iron_gear", 6) \
		.takes(&"circuit_board", 2).gives(&"refinery", 1).at_tier(3) \
		.in_category(&"objects").learned_from_material(&"iron_gear")
	r("teleporter_pad", &"assembler").takes(&"durasteel_bar", 8) \
		.takes(&"advanced_circuit", 2).takes(&"prisilite", 2) \
		.gives(&"teleporter_pad", 1).at_tier(5).in_category(&"objects") \
		.learned_from_material(&"prisilite")
	r("healing_station", &"assembler").takes(&"steel_bar", 8).takes(&"glass", 6) \
		.takes(&"circuit_board", 2).gives(&"healing_station", 1).at_tier(4) \
		.in_category(&"objects").learned_from_material(&"circuit_board")
	r("sprinkler", &"anvil").takes(&"iron_bar", 3).takes(&"copper_wire", 2) \
		.gives(&"sprinkler", 1).in_category(&"objects") \
		.learned_from_material(&"copper_wire")
	r("mini_fridge", &"assembler").takes(&"steel_bar", 6).takes(&"copper_wire", 4) \
		.takes(&"glass", 2).gives(&"mini_fridge", 1).at_tier(3) \
		.in_category(&"objects").learned_from_material(&"steel_bar")


# ================================================================ building ====
static func _building() -> void:
	var stone := [
		["stone_brick", &"cobblestone", 4, &"stone_brick", 4],
		["clay_brick", &"brick", 4, &"clay_brick", 4],
		["sandstone_brick", &"sandstone", 4, &"sandstone_brick", 4],
		["marble_tile", &"marble_tile", 0, &"marble_tile", 0],
		["basalt_brick", &"basalt", 4, &"basalt_brick", 4],
		["concrete", &"cobblestone", 4, &"concrete", 4],
	]
	for row: Array in stone:
		if int(row[2]) == 0:
			continue
		r(String(row[0]) + "_craft", &"workbench").takes(row[1], int(row[2])) \
			.gives(row[3], int(row[4])).in_category(&"building") \
			.learned_from_material(row[1])

	r("obsidian_brick", &"forge").takes(&"obsidian", 4).gives(&"obsidian_brick", 4) \
		.at_tier(3).in_category(&"building").learned_from_material(&"obsidian")
	r("iron_plating", &"anvil").takes(&"iron_bar", 2).gives(&"iron_plating", 4) \
		.in_category(&"building").learned_from_material(&"iron_bar")
	r("steel_plate", &"anvil").takes(&"steel_bar", 2).gives(&"steel_plate", 4) \
		.at_tier(2).in_category(&"building").learned_from_material(&"steel_bar")
	r("titanium_plating", &"forge").takes(&"titanium_bar", 2) \
		.gives(&"titanium_plating", 4).at_tier(2).in_category(&"building") \
		.learned_from_material(&"titanium_bar")
	r("durasteel_plating", &"forge").takes(&"durasteel_bar", 2) \
		.gives(&"durasteel_plating", 4).at_tier(3).in_category(&"building") \
		.learned_from_material(&"durasteel_bar")
	r("iron_bars_block", &"anvil").takes(&"iron_bar", 3).gives(&"iron_bars", 6) \
		.in_category(&"building").learned_from_material(&"iron_bar")
	r("metal_ladder", &"anvil").takes(&"iron_bar", 2).gives(&"metal_ladder", 8) \
		.in_category(&"building").learned_from_material(&"iron_bar")
	r("metal_platform", &"anvil").takes(&"iron_bar", 2).gives(&"metal_platform", 8) \
		.in_category(&"building").learned_from_material(&"iron_bar")
	r("stone_platform", &"workbench").takes(&"stone_brick", 2) \
		.gives(&"stone_platform", 6).in_category(&"building") \
		.learned_from_material(&"stone_brick")
	r("rope_ladder", &"workbench").takes(&"rope", 2).takes(&"stick", 3) \
		.gives(&"rope_ladder", 8).in_category(&"building").learned_from_material(&"rope")
	r("glass_pane", &"furnace").takes(&"glass_shard", 4).gives(&"glass", 1) \
		.takes_time(2.0).at_tier(0).in_category(&"building") \
		.learned_from_material(&"glass_shard")
	r("tinted_glass", &"workbench").takes(&"glass", 4).takes(&"coal", 1) \
		.gives(&"tinted_glass", 4).in_category(&"building") \
		.learned_from_material(&"glass")
	r("stained_glass_red", &"workbench").takes(&"glass", 4).takes(&"ruby", 1) \
		.gives(&"stained_glass_red", 8).in_category(&"building") \
		.learned_from_material(&"ruby")
	r("stained_glass_blue", &"workbench").takes(&"glass", 4).takes(&"sapphire", 1) \
		.gives(&"stained_glass_blue", 8).in_category(&"building") \
		.learned_from_material(&"sapphire")
	r("stained_glass_green", &"workbench").takes(&"glass", 4).takes(&"emerald", 1) \
		.gives(&"stained_glass_green", 8).in_category(&"building") \
		.learned_from_material(&"emerald")
	r("carpet_red", &"workbench").takes(&"cloth", 2).gives(&"carpet_red", 4) \
		.in_category(&"building").learned_from_material(&"cloth")
	r("carpet_blue", &"workbench").takes(&"cloth", 2).takes(&"sapphire", 1) \
		.gives(&"carpet_blue", 8).in_category(&"building").learned_from_material(&"cloth")
	r("wallpaper", &"workbench").takes(&"paper", 3).gives(&"wallpaper", 6) \
		.in_category(&"building").learned_from_material(&"paper")
	r("thatch", &"hand").takes(&"plant_fibre", 4).gives(&"thatch", 2) \
		.in_category(&"building").known_at_start()
	r("greenhouse_panel", &"workbench").takes(&"glass", 2).takes(&"iron_bar", 1) \
		.gives(&"greenhouse_panel", 4).in_category(&"building") \
		.learned_from_material(&"glass")
	r("lantern", &"anvil").takes(&"iron_bar", 2).takes(&"glass", 2) \
		.takes(&"torch", 1).gives(&"lantern", 2).in_category(&"light") \
		.learned_from_material(&"iron_bar")
	r("glowstone", &"workbench").takes(&"glow_dust", 4).takes(&"sand", 2) \
		.gives(&"glowstone", 1).in_category(&"light").learned_from_material(&"glow_dust")
	r("floodlight", &"assembler").takes(&"steel_bar", 3).takes(&"glass", 2) \
		.takes(&"energy_cell", 1).gives(&"floodlight", 2).at_tier(3) \
		.in_category(&"light").learned_from_material(&"energy_cell")
	r("standing_lamp", &"workbench").takes(&"iron_bar", 2).takes(&"glass", 2) \
		.takes(&"cloth", 1).gives(&"standing_lamp", 1).in_category(&"light") \
		.learned_from_material(&"glass")


# =================================================================== tools ====
static func _tool_set(metal: StringName, bar: StringName, kinds: Array,
		station: StringName, tier: int) -> void:
	for kind: StringName in kinds:
		var id := StringName("%s_%s" % [metal, kind])
		if not Items.has(id):
			continue
		r("craft_" + String(id), station).takes(bar, 3).takes(&"stick", 2) \
			.gives(id, 1).at_tier(tier).in_category(&"tools") \
			.learned_from_material(bar)


static func _tools() -> void:
	_tool_set(&"copper", &"copper_bar", [&"pickaxe", &"axe"], &"workbench", 1)
	_tool_set(&"iron", &"iron_bar", [&"pickaxe", &"axe", &"shovel"], &"anvil", 2)
	_tool_set(&"tungsten", &"tungsten_bar", [&"pickaxe", &"axe", &"shovel", &"drill", &"hoe"],
		&"anvil", 2)
	_tool_set(&"titanium", &"titanium_bar", [&"pickaxe"], &"forge", 3)
	_tool_set(&"durasteel", &"durasteel_bar", [&"pickaxe", &"axe", &"shovel", &"drill"],
		&"forge", 4)
	_tool_set(&"aegisalt", &"aegisalt_bar", [&"pickaxe", &"axe", &"shovel", &"drill"],
		&"assembler", 5)
	_tool_set(&"solarium", &"solarium_bar", [&"pickaxe"], &"replicator", 6)

	r("wood_hoe", &"workbench").takes(&"wood_planks", 3).takes(&"stick", 2) \
		.gives(&"wood_hoe", 1).in_category(&"tools").known_at_start()
	r("watering_can", &"anvil").takes(&"iron_bar", 3).gives(&"watering_can", 1) \
		.in_category(&"tools").learned_from_material(&"iron_bar")
	r("scanner", &"assembler").takes(&"sensor_lens", 1).takes(&"circuit_board", 1) \
		.takes(&"iron_bar", 2).gives(&"scanner", 1).at_tier(3).in_category(&"tools") \
		.learned_from_material(&"sensor_lens")
	r("flashlight", &"workbench").takes(&"iron_bar", 1).takes(&"glass", 1) \
		.takes(&"battery", 1).gives(&"flashlight", 1).in_category(&"tools") \
		.learned_from_material(&"battery")
	r("grappling_hook", &"assembler").takes(&"steel_bar", 4).takes(&"rope", 4) \
		.takes(&"iron_gear", 2).gives(&"grappling_hook", 1).at_tier(4) \
		.in_category(&"tools").learned_from_material(&"rope")
	r("sensor_lens", &"chemistry").takes(&"glass", 2).takes(&"quartz", 2) \
		.gives(&"sensor_lens", 1).at_tier(3).in_category(&"components") \
		.learned_from_material(&"quartz")


# ================================================================= weapons ====
static func _weapons() -> void:
	var ladder := [
		[&"copper", &"copper_bar", &"workbench", 1],
		[&"iron", &"iron_bar", &"anvil", 2],
		[&"silver", &"silver_bar", &"anvil", 2],
		[&"gold", &"gold_bar", &"anvil", 2],
		[&"titanium", &"titanium_bar", &"forge", 3],
		[&"durasteel", &"durasteel_bar", &"forge", 4],
		[&"aegisalt", &"aegisalt_bar", &"assembler", 5],
		[&"ferozium", &"ferozium_bar", &"assembler", 5],
		[&"violium", &"violium_bar", &"assembler", 5],
		[&"solarium", &"solarium_bar", &"replicator", 6],
	]
	for row: Array in ladder:
		for kind: StringName in [&"sword", &"spear", &"hammer", &"bow", &"gun"]:
			var id := StringName("%s_%s" % [row[0], kind])
			if not Items.has(id):
				continue
			var rec := r("craft_" + String(id), row[2]).takes(row[1], 4) \
				.gives(id, 1).at_tier(int(row[3])).in_category(&"weapons") \
				.learned_from_material(row[1])
			if kind == &"bow":
				rec.takes(&"string", 2)
			elif kind == &"gun":
				rec.takes(&"copper_wire", 2).takes(&"battery", 1)
			else:
				rec.takes(&"stick", 2)

	r("arrow", &"workbench").takes(&"stick", 1).takes(&"flint", 1) \
		.takes(&"feather", 1).gives(&"arrow", 8).in_category(&"ammo") \
		.known_at_start()
	r("iron_arrow", &"anvil").takes(&"iron_bar", 1).takes(&"stick", 4) \
		.takes(&"feather", 2).gives(&"iron_arrow", 12).in_category(&"ammo") \
		.learned_from_material(&"iron_bar")
	r("bolt", &"assembler").takes(&"steel_bar", 1).takes(&"nanowire", 1) \
		.gives(&"bolt", 16).at_tier(4).in_category(&"ammo") \
		.learned_from_material(&"nanowire")


# =================================================================== armor ====
static func _armor() -> void:
	var ladder := [
		[&"copper", &"copper_bar", &"workbench", 1],
		[&"iron", &"iron_bar", &"anvil", 2],
		[&"silver", &"silver_bar", &"anvil", 2],
		[&"gold", &"gold_bar", &"anvil", 2],
		[&"titanium", &"titanium_bar", &"forge", 3],
		[&"durasteel", &"durasteel_bar", &"forge", 4],
		[&"aegisalt", &"aegisalt_bar", &"assembler", 5],
		[&"ferozium", &"ferozium_bar", &"assembler", 5],
		[&"violium", &"violium_bar", &"assembler", 5],
		[&"solarium", &"solarium_bar", &"replicator", 6],
	]
	var costs := {&"helm": 4, &"chest": 7, &"greaves": 5}
	for row: Array in ladder:
		for piece: StringName in [&"helm", &"chest", &"greaves"]:
			var id := StringName("%s_%s" % [row[0], piece])
			if not Items.has(id):
				continue
			r("craft_" + String(id), row[2]).takes(row[1], int(costs[piece])) \
				.gives(id, 1).at_tier(int(row[3])).in_category(&"armor") \
				.learned_from_material(row[1])

	var suits := {
		&"firewalker": [&"obsidian_shard", &"forge", 3],
		&"frostwalker": [&"ice_crystal", &"forge", 3],
		&"hazmat": [&"lead_bar", &"chemistry", 4],
		&"vacuum": [&"polymer", &"assembler", 5],
	}
	for suit: StringName in suits:
		var spec: Array = suits[suit]
		for piece: StringName in [&"helm", &"chest", &"greaves"]:
			var id := StringName("%s_%s" % [suit, piece])
			if not Items.has(id):
				continue
			r("craft_" + String(id), spec[1]).takes(spec[0], 4) \
				.takes(&"cloth", 3).gives(id, 1).at_tier(int(spec[2])) \
				.in_category(&"armor").learned_from_material(spec[0])


# ==================================================================== food ====
static func _food() -> void:
	r("flour", &"kitchen").takes(&"wheat", 2).gives(&"flour", 1) \
		.in_category(&"food").learned_from_material(&"wheat")
	r("dough", &"kitchen").takes(&"flour", 2).gives(&"dough", 1) \
		.in_category(&"food").learned_from_material(&"flour")
	r("bread", &"kitchen").takes(&"dough", 1).gives(&"bread", 1).takes_time(4.0) \
		.in_category(&"food").learned_from_material(&"flour")
	r("cooked_meat", &"kitchen").takes(&"raw_meat", 1).gives(&"cooked_meat", 1) \
		.takes_time(3.0).in_category(&"food").learned_from_material(&"raw_meat")
	r("cooked_fish", &"kitchen").takes(&"raw_fish", 1).gives(&"cooked_fish", 1) \
		.takes_time(3.0).in_category(&"food").learned_from_material(&"raw_fish")
	r("roast_vegetables", &"kitchen").takes(&"potato", 2).takes(&"carrot", 1) \
		.gives(&"roast_vegetables", 2).takes_time(4.0).in_category(&"food") \
		.learned_from_material(&"potato")
	r("vegetable_stew", &"kitchen").takes(&"potato", 1).takes(&"carrot", 1) \
		.takes(&"tomato", 1).takes(&"water_flask", 1).gives(&"vegetable_stew", 2) \
		.takes_time(6.0).in_category(&"food").learned_from_material(&"tomato")
	r("mushroom_soup", &"kitchen").takes(&"mushroom_brown", 2) \
		.takes(&"water_flask", 1).gives(&"mushroom_soup", 1).takes_time(5.0) \
		.in_category(&"food").learned_from_material(&"mushroom_brown")
	r("alien_skewer", &"kitchen").takes(&"raw_alien_meat", 1).takes(&"stick", 1) \
		.takes(&"currentcorn", 1).gives(&"alien_skewer", 1).takes_time(5.0) \
		.at_tier(2).in_category(&"food").learned_from_material(&"raw_alien_meat")
	r("jerky", &"kitchen").takes(&"raw_meat", 2).takes(&"salt", 1) \
		.gives(&"jerky", 3).takes_time(8.0).in_category(&"food") \
		.learned_from_material(&"salt")
	r("hardtack", &"kitchen").takes(&"flour", 1).takes(&"salt", 1) \
		.gives(&"hardtack", 3).takes_time(5.0).in_category(&"food") \
		.learned_from_material(&"salt")
	r("water_flask", &"kitchen").takes(&"empty_flask", 1).gives(&"water_flask", 1) \
		.in_category(&"food").learned_from_material(&"empty_flask")
	r("herbal_tea", &"kitchen").takes(&"water_flask", 1).takes(&"plant_fibre", 2) \
		.takes(&"flower_red", 1).gives(&"herbal_tea", 1).takes_time(3.0) \
		.in_category(&"food").learned_from_material(&"flower_red")
	r("coffee_brew", &"kitchen").takes(&"water_flask", 1).takes(&"currentcorn", 1) \
		.gives(&"coffee", 1).takes_time(3.0).at_tier(2).in_category(&"food") \
		.learned_from_material(&"currentcorn")
	r("hearty_platter", &"kitchen").takes(&"cooked_meat", 1).takes(&"bread", 1) \
		.takes(&"roast_vegetables", 1).gives(&"hearty_platter", 1).takes_time(10.0) \
		.at_tier(2).in_category(&"food").learned_from_material(&"bread")
	r("voyagers_feast", &"kitchen").takes(&"hearty_platter", 1) \
		.takes(&"mushroom_soup", 1).takes(&"alien_skewer", 1) \
		.gives(&"voyagers_feast", 1).takes_time(14.0).at_tier(2) \
		.in_category(&"food").learned_from_material(&"alien_skewer")
	r("starlit_confection", &"kitchen").takes(&"honey", 2).takes(&"glow_sap", 2) \
		.takes(&"star_dust", 1).gives(&"starlit_confection", 1).takes_time(12.0) \
		.at_tier(2).in_category(&"food").learned_from_material(&"star_dust")

	# --- medicine
	r("medkit", &"chemistry").takes(&"bandage", 2).takes(&"plant_matter", 3) \
		.takes(&"cloth", 1).gives(&"medkit", 1).at_tier(2).in_category(&"medical") \
		.learned_from_material(&"cloth")
	r("antidote", &"chemistry").takes(&"venom_gland", 1).takes(&"plant_matter", 2) \
		.takes(&"empty_flask", 1).gives(&"antidote", 2).at_tier(2) \
		.in_category(&"medical").learned_from_material(&"venom_gland")
	r("stim_pack", &"chemistry").takes(&"glow_gland", 1).takes(&"empty_flask", 1) \
		.takes(&"crystal_shard", 2).gives(&"stim_pack", 1).at_tier(3) \
		.in_category(&"medical").learned_from_material(&"glow_gland")
	r("rad_purge", &"chemistry").takes(&"lead_bar", 1).takes(&"plant_matter", 4) \
		.takes(&"empty_flask", 1).gives(&"rad_purge", 2).at_tier(3) \
		.in_category(&"medical").learned_from_material(&"lead_bar")
	r("panacea", &"chemistry").takes(&"medkit", 2).takes(&"antidote", 2) \
		.takes(&"starlight_essence", 1).gives(&"panacea", 1).at_tier(4) \
		.in_category(&"medical").learned_from_material(&"starlight_essence")
	r("glow_tonic", &"chemistry").takes(&"glow_sap", 2).takes(&"luminous_powder", 1) \
		.takes(&"empty_flask", 1).gives(&"glow_tonic", 2).at_tier(2) \
		.in_category(&"medical").learned_from_material(&"glow_sap")
	r("fertiliser", &"workbench").takes(&"bone_meal", 1).takes(&"plant_matter", 2) \
		.gives(&"fertiliser", 4).in_category(&"materials") \
		.learned_from_material(&"bone_meal")
	r("bone_meal", &"workbench").takes(&"bone", 1).gives(&"bone_meal", 3) \
		.in_category(&"materials").learned_from_material(&"bone")


# ==================================================================== tech ====
static func _tech() -> void:
	# Fuel, which is what actually gates the star map.
	r("erchius_to_ftl", &"chemistry").takes(&"erchius_fuel", 2) \
		.takes(&"crystal_shard", 1).gives(&"ftl_fuel", 1).at_tier(2) \
		.in_category(&"fuel").ordered(-20) \
		.describe("The jump fuel. Nothing leaves this system without it.") \
		.learned_from_material(&"erchius_fuel")
	r("refined_ftl", &"chemistry").takes(&"ftl_fuel", 3).takes(&"prisilite", 1) \
		.gives(&"refined_ftl_fuel", 1).at_tier(4).in_category(&"fuel") \
		.learned_from_material(&"prisilite")

	# Tech cards are printed rather than found, once you can afford them.
	for d: Dictionary in TechCatalog.ALL:
		var card := TechCatalog.card_id(d["id"])
		if not Items.has(card):
			continue
		var rec := r("print_" + String(d["id"]), &"tech") \
			.gives(card, 1).at_tier(3).in_category(&"tech") \
			.learned_from_material(&"circuit_board") \
			.describe(String(d["desc"]))
		var price := int(d["price"])
		rec.takes(&"circuit_board", maxi(1, price / 500))
		rec.takes(&"crystal_shard", maxi(2, price / 260))
		if price >= 2000:
			rec.takes(&"advanced_circuit", 2)
		if price >= 3000:
			rec.takes(&"quantum_processor", 1)


# ================================================================= taming ====
## The handler's kit. Deliberately cheap at the bottom — a sap club and a bola
## cost a morning's foraging — and expensive at the top, because a dart rifle
## and concentrated narcotic are what stand between you and the exotics.
static func _taming() -> void:
	r("sap_club", &"hand").takes(&"wood_log", 1).takes(&"stick", 2) \
		.takes(&"plant_fibre", 3).gives(&"sap_club", 1).in_category(&"weapons") \
		.describe("A weighted club that puts creatures out rather than down.") \
		.known_at_start()

	r("bola", &"hand").takes(&"plant_fibre", 3).takes(&"stone", 3) \
		.gives(&"bola", 2).in_category(&"tools") \
		.describe("Three stones and a cord.").known_at_start()

	r("capture_net", &"workbench").takes(&"plant_fibre", 8).takes(&"stick", 4) \
		.takes(&"leather", 2).gives(&"capture_net", 1).at_tier(1) \
		.in_category(&"tools").learned_from_material(&"leather")

	r("creature_feed", &"workbench").takes(&"wheat", 2).takes(&"raw_meat", 1) \
		.gives(&"creature_feed", 6).in_category(&"food") \
		.describe("A sack of the stuff every creature will eat.").known_at_start()

	r("kibble", &"kitchen").takes(&"egg", 1).takes(&"carrot", 2) \
		.takes(&"cooked_meat", 1).gives(&"kibble", 4).at_tier(1) \
		.in_category(&"food") \
		.describe("Halves the work of any tame.").learned_from_material(&"egg")

	r("tranq_arrow", &"workbench").takes(&"arrow", 4).takes(&"venom_gland", 1) \
		.takes(&"plant_matter", 2).gives(&"tranq_arrow", 4).at_tier(1) \
		.in_category(&"ammo").learned_from_material(&"venom_gland")

	r("tranq_bow", &"workbench").takes(&"stick", 4).takes(&"plant_fibre", 6) \
		.takes(&"leather", 2).gives(&"tranq_bow", 1).at_tier(1) \
		.in_category(&"weapons").learned_from_material(&"leather")

	r("narcotic", &"chemistry").takes(&"venom_gland", 1).takes(&"plant_matter", 4) \
		.takes(&"empty_flask", 1).gives(&"narcotic", 3).at_tier(2) \
		.in_category(&"medical").learned_from_material(&"venom_gland")

	r("stimulant", &"chemistry").takes(&"glow_gland", 1).takes(&"empty_flask", 1) \
		.takes(&"plant_matter", 2).gives(&"stimulant", 3).at_tier(2) \
		.in_category(&"medical").learned_from_material(&"glow_gland")

	r("strong_narcotic", &"chemistry").takes(&"narcotic", 4) \
		.takes(&"crystal_shard", 2).takes(&"empty_flask", 1) \
		.gives(&"strong_narcotic", 1).at_tier(3).in_category(&"medical")

	r("tranq_dart", &"anvil").takes(&"iron_bar", 1).takes(&"narcotic", 1) \
		.gives(&"tranq_dart", 8).at_tier(2).in_category(&"ammo") \
		.learned_from_material(&"narcotic")

	r("shock_dart", &"assembler").takes(&"tranq_dart", 4).takes(&"battery", 1) \
		.takes(&"copper_wire", 2).gives(&"shock_dart", 4).at_tier(3) \
		.in_category(&"ammo")

	r("tranq_rifle", &"assembler").takes(&"iron_bar", 4).takes(&"copper_wire", 4) \
		.takes(&"circuit_board", 1).takes(&"leather", 2).gives(&"tranq_rifle", 1) \
		.at_tier(3).in_category(&"weapons")

	r("handlers_collar", &"workbench").takes(&"leather", 3).takes(&"copper_bar", 1) \
		.takes(&"plant_fibre", 4).gives(&"handlers_collar", 1).at_tier(2) \
		.in_category(&"tools").learned_from_material(&"leather")

	r("saddlebag", &"workbench").takes(&"leather", 5).takes(&"cloth", 3) \
		.takes(&"plant_fibre", 6).gives(&"saddlebag", 1).at_tier(2) \
		.in_category(&"tools")
