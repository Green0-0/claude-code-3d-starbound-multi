## Furnace and blast-furnace (forge) recipes: ore to bar, sand to glass, alloys
## and cooking over a flame. Fuel values live in `_ladder.gd`.
##
## Every furnace recipe is timed; `CraftStation` burns
## `recipe.effective_fuel_cost()` seconds of fuel per run and refuses to start
## with an empty firebox.
##
## The campfire is the same `&"furnace"` station at tier 0 exposing only the
## `&"cooking"` group, so meat cooks on it but ore does not smelt.
extends RefCounted

static func register_all(reg) -> void:
	_ore_to_bar(reg)
	_alloys(reg)
	_minerals(reg)
	_cooking(reg)
	_reclamation(reg)


static func _ore_to_bar(reg) -> void:
	for m: Dictionary in CraftLadder.METALS:
		var ore := StringName(m.get("ore", &""))
		if ore == &"":
			continue
		var mn := StringName(m["name"])
		var tier := int(m["tier"])
		var station: StringName = &"furnace" if tier <= 2 else &"forge"
		reg.add(CraftRecipe.make("smelt_%s" % mn, station)
			.takes(ore, 1).gives(StringName(m["bar"]), 1)
			.byproduct(&"ash", 1, 0.2)
			.lasts(1.5 + float(tier) * 0.6).needs_tier(tier)
			.burns(2.0 + float(tier))
			.in_category(&"materials").in_group(&"smelting").ordered(tier)
			.describe("Cook the rock until the metal runs out of it.")
			.learned_from_material(ore))

	# A forge runs hotter: two ore and a lump of coal give four bars.
	for n: String in ["copper", "iron", "silver", "gold", "titanium"]:
		var m := CraftLadder.metal(StringName(n))
		reg.add(CraftRecipe.make("blast_%s" % n, &"forge")
			.takes(StringName(m["ore"]), 2).takes(&"coal", 1)
			.gives(StringName(m["bar"]), 4)
			.byproduct(&"ash", 2, 0.5)
			.lasts(4.0).needs_tier(3).burns(10.0)
			.in_category(&"materials").in_group(&"smelting").ordered(20)
			.describe("A hotter fire pulls twice the metal from the same rock.")
			.learned_at_tier(3))


static func _alloys(reg) -> void:
	reg.add(CraftRecipe.make("carbon_powder", &"furnace")
		.takes(&"coal", 1).gives(&"carbon_powder", 2)
		.lasts(1.5).burns(2.0).needs_tier(1)
		.in_category(&"materials").in_group(&"smelting").ordered(28)
		.describe("Milled to a black flour. Alloys, filters and edges.")
		.learned_from_material(&"coal"))

	reg.add(CraftRecipe.make("alloy_durasteel", &"forge")
		.takes(&"titanium_bar", 2).takes(&"iron_bar", 2).takes(&"carbon_powder", 3)
		.gives(&"durasteel_bar", 3)
		.lasts(6.0).burns(18.0).needs_tier(3)
		.in_category(&"materials").in_group(&"smelting").ordered(30)
		.describe("Titanium and carbon folded into iron. Almost unbreakable.")
		.learned_from_material(&"titanium_bar"))

	reg.add(CraftRecipe.make("silicon_wafer", &"furnace")
		.takes(&"quartz", 2).takes(&"carbon_powder", 1).gives(&"silicon_wafer", 1)
		.lasts(3.5).burns(6.0).needs_tier(2)
		.in_category(&"tech").in_group(&"smelting").ordered(32)
		.describe("Grown from a melt, sliced thin, polished to a mirror.")
		.learned_from_material(&"quartz"))


static func _minerals(reg) -> void:
	reg.add(CraftRecipe.make("glass", &"furnace")
		.takes(&"sand", 2).gives(&"glass", 1)
		.lasts(1.5).burns(2.5)
		.in_category(&"blocks").in_group(&"smelting")
		.describe("Sand, hot enough to forget it was ever sand.")
		.learned_from_material(&"sand"))

	reg.add(CraftRecipe.make("glass_from_shards", &"furnace")
		.takes(&"glass_shard", 4).gives(&"glass", 1)
		.lasts(1.0).burns(1.5)
		.in_category(&"blocks").in_group(&"smelting")
		.learned_from_material(&"glass_shard"))

	reg.add(CraftRecipe.make("clay_brick_fired", &"furnace")
		.takes(&"clay_lump", 2).gives(&"clay_brick", 2)
		.lasts(1.5).burns(2.5)
		.in_category(&"blocks").in_group(&"smelting")
		.learned_from_material(&"clay_lump"))

	reg.add(CraftRecipe.make("clay_tile_fired", &"furnace")
		.takes(&"clay_lump", 1).takes(&"sand", 1).gives(&"clay_tile", 2)
		.lasts(1.5).burns(2.5)
		.in_category(&"blocks").in_group(&"smelting")
		.learned_from_material(&"clay_lump"))

	reg.add(CraftRecipe.make("ceramic_tile_fired", &"furnace")
		.takes(&"clay_lump", 2).takes(&"quartz", 1).gives(&"ceramic_tile", 4)
		.lasts(2.5).burns(4.0).needs_tier(1)
		.in_category(&"blocks").in_group(&"smelting")
		.learned_from_material(&"quartz"))

	reg.add(CraftRecipe.make("smooth_stone", &"furnace")
		.takes(&"cobblestone", 1).gives(&"stone", 1)
		.lasts(1.0).burns(1.5)
		.in_category(&"blocks").in_group(&"smelting")
		.learned_from_material(&"cobblestone"))

	reg.add(CraftRecipe.make("charcoal", &"furnace")
		.takes(&"wood", 2).gives(&"charcoal", 2)
		.byproduct(&"ash", 1, 0.5)
		.lasts(2.0).burns(3.0)
		.in_category(&"materials").in_group(&"smelting")
		.describe("Wood, starved of air. Burns longer than the log did.")
		.known_at_start())

	reg.add(CraftRecipe.make("cement_fired", &"furnace")
		.takes(&"limestone", 3).gives(&"cement_mix", 4)
		.lasts(2.5).burns(4.0).needs_tier(1)
		.in_category(&"materials").in_group(&"smelting")
		.learned_from_material(&"limestone"))

	reg.add(CraftRecipe.make("salt_from_seawater", &"furnace")
		.takes(&"salt_water", 2).gives(&"salt", 2)
		.lasts(3.0).burns(4.0)
		.in_category(&"materials").in_group(&"smelting")
		.describe("Boil it off and sweep up what stays behind.")
		.learned_from_material(&"salt_water"))

	reg.add(CraftRecipe.make("obsidian_cast", &"forge")
		.takes(&"cobblestone", 6).takes(&"magma_block", 1).gives(&"obsidian", 4)
		.lasts(5.0).burns(12.0).needs_tier(3)
		.in_category(&"blocks").in_group(&"smelting")
		.describe("Quenched lava rock. Brittle, black, and very sharp.")
		.learned_from_material(&"magma_block"))

	reg.add(CraftRecipe.make("obsidian_knapping", &"workbench")
		.takes(&"obsidian", 1).gives(&"obsidian_shard", 3)
		.in_category(&"materials").in_group(&"general")
		.learned_from_material(&"obsidian"))


## Cooking a single ingredient over a flame. Multi-ingredient meals live in
## `food.gd` and need a kitchen.
static func _cooking(reg) -> void:
	var cooks: Array[Array] = [
		[&"raw_meat", &"cooked_meat", 2.0, "Charred outside, safe inside."],
		[&"raw_fish", &"grilled_fish", 1.8, ""],
		[&"corn", &"corn_cob", 1.8, ""],
		[&"egg", &"boiled_egg", 1.5, ""],
		[&"raw_alien_meat", &"cooked_alien_meat", 3.0, "Probably fine."],
		[&"potato", &"baked_potato", 2.5, ""],
		[&"dough", &"bread", 3.0, "Worth the wait."],
	]
	for c: Array in cooks:
		reg.add(CraftRecipe.make("cook_%s" % c[0], &"furnace")
			.takes(StringName(c[0]), 1).gives(StringName(c[1]), 1)
			.lasts(float(c[2])).burns(float(c[2]) * 1.5)
			.in_category(&"food").in_group(&"cooking")
			.describe(String(c[3]))
			.learned_from_material(StringName(c[0])))


static func _reclamation(reg) -> void:
	reg.add(CraftRecipe.make("smelt_scrap", &"furnace")
		.takes(&"scrap_metal", 4).gives(&"iron_bar", 1)
		.byproduct(&"copper_bar", 1, 0.3)
		.lasts(3.0).burns(5.0).needs_tier(1)
		.in_category(&"materials").in_group(&"smelting")
		.describe("Somebody's ship, given a second career.")
		.learned_from_material(&"scrap_metal"))

	reg.add(CraftRecipe.make("smelt_rusted", &"furnace")
		.takes(&"rusted_metal", 3).gives(&"scrap_metal", 4)
		.lasts(2.0).burns(3.0)
		.in_category(&"materials").in_group(&"smelting")
		.learned_from_material(&"rusted_metal"))

	reg.add(CraftRecipe.make("iron_nails", &"anvil")
		.takes(&"iron_bar", 1).gives(&"iron_nail", 12)
		.lasts(0.8).needs_tier(1)
		.in_category(&"materials").in_group(&"metalwork")
		.describe("Sold by the handful, lost by the handful.")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("ash_reclaim", &"forge")
		.takes(&"ash", 8).takes(&"cement_mix", 1).gives(&"iron_bar", 1)
		.byproduct(&"silver_bar", 1, 0.15)
		.lasts(5.0).burns(8.0).needs_tier(3)
		.in_category(&"materials").in_group(&"smelting")
		.describe("There is always a little metal left in the ashes.")
		.learned_at_tier(3))
