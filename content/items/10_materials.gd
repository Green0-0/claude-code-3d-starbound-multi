## The materials backbone: every raw resource and intermediate part that
## crafting, vendors, loot tables and quests key off.
##
## [b]Naming contract[/b] — other agents write against these ids, so they do not
## change:
## [br]• Ores drop as `raw_<metal>` (`raw_copper`, `raw_iron`, ...). This is the
##   name the ore *blocks* in `content/blocks/` must use in their `.drop()`.
## [br]• Smelted metal is `<metal>_bar` (`copper_bar` ... `solarium_bar`).
##   `durasteel_bar` is an alloy and has no ore.
## [br]• The tier ladder, low to high:
##   copper → iron → silver → gold → titanium → durasteel → aegisalt →
##   ferozium → violium → solarium, plus the side metals the ore blocks drop
##   (tin, lead, silicon, tungsten, platinum, uranium, plutonium, rubium) and
##   the alloys the recipe book smelts (bronze, steel, electrum, impervium,
##   cosmic_alloy). Every metal item carries a `tier_<n>` tag so a recipe or a
##   vendor can reason about progression without a lookup table of its own.
## [br]• ~167 items in total, grouped by `category`: `ore` `bar` `fuel` `gem`
##   `organic` `wood` `monster` `component` `alien` `fossil` `quest` `crafting`.
##
## [b]Tags[/b] every item here carries `material`, plus its group tag: `ore`,
## `bar`, `metal`, `smeltable`, `refined`, `fuel`, `gem`, `crystal`, `organic`,
## `fibre`, `leather`, `wood`, `monster_drop`, `component`, `electronic`,
## `alien`, `exotic`, `fossil`, `treasure`, `quest`, `no_sell`, `junk`.
##
## [b]Collision safety[/b] — a material is only registered when no block and no
## earlier content file already claimed the id, so a block placer item always
## wins. That means `wood`, `coal` and similar may resolve to a block item on
## some worlds; the id stays valid either way.
extends RefCounted


static func register_all(reg) -> void:
	_metals(reg)
	_fuels(reg)
	_gems(reg)
	_organics(reg)
	_woods(reg)
	_monster_drops(reg)
	_components(reg)
	_alien(reg)
	_fossils(reg)
	_quest_items(reg)
	_crafting_misc(reg)


## Define one material unless a block or an earlier file already owns the id.
## Returns null when it was skipped, so callers must null-check before adding
## extra builder calls.
static func _mat(reg, id: StringName, display: String, color: Color, value: int,
		rarity: int, category: StringName, shape: StringName, tags: Array,
		desc: String) -> ItemType:
	if reg.has(id) or Blocks.has(id):
		return null
	var it: ItemType = reg.define(id, display)
	it.of_kind(ItemType.Kind.MATERIAL).look(color, shape).worth(value, rarity) \
		.in_category(category).describe(desc).tag(&"material")
	for t: Variant in tags:
		it.tag(StringName(t))
	return it


# ================================================================== metals ====
## The whole ore → bar ladder, including the side metals agent 1's ore blocks
## drop and the alloys the recipe book smelts. Ore items are `raw_<metal>` and
## match `content/blocks/11_ores.gd` exactly; bars are `<metal>_bar`.
static func _metals(reg) -> void:
	# key, display, colour, tier, raw value, bar value, rarity, has ore, has bar
	var ladder := [
		[&"copper", "Copper", Color(0.84, 0.48, 0.24), 0, 5, 14, Const.RARITY_COMMON, true, true],
		[&"tin", "Tin", Color(0.78, 0.80, 0.84), 0, 6, 18, Const.RARITY_COMMON, true, true],
		[&"bronze", "Bronze", Color(0.72, 0.45, 0.20), 1, 0, 30, Const.RARITY_COMMON, false, true],
		[&"lead", "Lead", Color(0.42, 0.42, 0.52), 1, 7, 20, Const.RARITY_COMMON, true, true],
		[&"iron", "Iron", Color(0.66, 0.62, 0.58), 1, 8, 22, Const.RARITY_COMMON, true, true],
		[&"silver", "Silver", Color(0.86, 0.88, 0.92), 1, 15, 40, Const.RARITY_COMMON, true, true],
		[&"silicon", "Silicon", Color(0.60, 0.66, 0.72), 1, 18, 0, Const.RARITY_COMMON, true, false],
		[&"steel", "Steel", Color(0.60, 0.62, 0.66), 2, 0, 60, Const.RARITY_COMMON, false, true],
		[&"gold", "Gold", Color(0.96, 0.79, 0.28), 2, 25, 65, Const.RARITY_UNCOMMON, true, true],
		[&"tungsten", "Tungsten", Color(0.50, 0.52, 0.48), 2, 30, 85, Const.RARITY_UNCOMMON, true, true],
		[&"titanium", "Titanium", Color(0.72, 0.76, 0.80), 2, 40, 110, Const.RARITY_UNCOMMON, true, true],
		[&"platinum", "Platinum", Color(0.86, 0.88, 0.90), 3, 55, 140, Const.RARITY_UNCOMMON, true, true],
		[&"electrum", "Electrum", Color(0.90, 0.84, 0.50), 3, 0, 150, Const.RARITY_UNCOMMON, false, true],
		[&"durasteel", "Durasteel", Color(0.45, 0.50, 0.56), 3, 70, 180, Const.RARITY_UNCOMMON, true, true],
		[&"uranium", "Uranium", Color(0.52, 0.96, 0.34), 3, 95, 0, Const.RARITY_RARE, true, false],
		[&"plutonium", "Plutonium", Color(0.36, 1.00, 0.62), 4, 130, 0, Const.RARITY_RARE, true, false],
		[&"aegisalt", "Aegisalt", Color(0.36, 0.62, 0.60), 4, 90, 240, Const.RARITY_RARE, true, true],
		[&"ferozium", "Ferozium", Color(0.35, 0.85, 0.66), 5, 120, 320, Const.RARITY_RARE, true, true],
		[&"violium", "Violium", Color(0.60, 0.34, 0.78), 5, 140, 380, Const.RARITY_RARE, true, true],
		[&"rubium", "Rubium", Color(1.00, 0.26, 0.30), 5, 150, 400, Const.RARITY_RARE, true, true],
		[&"impervium", "Impervium", Color(0.30, 0.70, 0.75), 5, 0, 460, Const.RARITY_RARE, false, true],
		[&"solarium", "Solarium", Color(0.98, 0.90, 0.42), 6, 200, 550, Const.RARITY_LEGENDARY, true, true],
	]
	for row: Array in ladder:
		var key: StringName = row[0]
		var display: String = row[1]
		var color: Color = row[2]
		var tier: int = row[3]
		var tier_tag := StringName("tier_%d" % tier)
		if bool(row[7]):
			_mat(reg, StringName("raw_" + String(key)), "Raw " + display,
				color.darkened(0.18), int(row[4]), int(row[6]), &"ore", &"chunk",
				[&"ore", &"raw", &"metal", &"smeltable", tier_tag],
				"Unrefined %s, straight out of the rock. Smelt it into a bar." % display.to_lower())
		if bool(row[8]):
			_mat(reg, StringName(String(key) + "_bar"), display + " Bar",
				color, int(row[5]), int(row[6]), &"bar", &"bar",
				[&"bar", &"metal", &"refined", tier_tag],
				"A cast bar of %s. The backbone of tier %d gear." % [display.to_lower(), tier])

	# Odds and ends of the smelting chain that do not fit the raw/bar pattern.
	_bulk(reg, [
		[&"cosmic_alloy", "Cosmic Alloy", Color(0.72, 0.82, 0.98), 700, Const.RARITY_LEGENDARY,
			&"bar", [&"bar", &"metal", &"refined", &"exotic", &"tier_6"],
			"Metal folded through a fold in space. Weighs nothing at all."],
	], &"bar")
	_bulk(reg, [
		[&"slag", "Slag", Color(0.34, 0.32, 0.30), 1, Const.RARITY_COMMON,
			&"chunk", [&"junk", &"smeltable"],
			"Furnace waste. Re-smelt enough of it and you get metal back."],
		[&"quicklime", "Quicklime", Color(0.94, 0.94, 0.90), 8, Const.RARITY_COMMON,
			&"dust", [&"reagent", &"building_mat"],
			"Burnt limestone. Do not get it wet, and do not get it on you."],
		[&"scrap_metal", "Scrap Metal", Color(0.50, 0.48, 0.46), 4, Const.RARITY_COMMON,
			&"chunk", [&"metal", &"junk", &"smeltable"],
			"Bent, rusted and previously somebody's ship. Re-smeltable."],
	], &"crafting")
	_bulk(reg, [
		[&"core_fragment", "Core Fragment", Color(1.00, 0.56, 0.14), 340, Const.RARITY_LEGENDARY,
			&"chunk", [&"exotic", &"fuel", &"tier_6"],
			"A piece of the planet's heart, still furious about it."],
		[&"prisilite", "Prisilite", Color(0.60, 0.94, 1.00), 210, Const.RARITY_RARE,
			&"gem", [&"crystal", &"exotic", &"tier_5"],
			"Refracts light into eleven colours, three of which have no names."],
	], &"alien")


# =================================================================== fuels ====
static func _fuels(reg) -> void:
	var rows := [
		[&"coal", "Coal", Color(0.16, 0.15, 0.17), 6, 0, &"lump", [&"fuel", &"smeltable"],
			"Burns hot and long. Furnace fuel, and the carbon in durasteel."],
		[&"raw_coal", "Raw Coal", Color(0.13, 0.12, 0.14), 5, 0, &"chunk", [&"fuel", &"ore", &"raw", &"smeltable"],
			"Straight from the seam, still gritty with stone."],
		[&"charcoal", "Charcoal", Color(0.22, 0.20, 0.19), 4, 0, &"lump", [&"fuel"],
			"Wood cooked without air. Cheaper than coal, burns nearly as well."],
		[&"crude_oil", "Crude Oil", Color(0.10, 0.09, 0.12), 12, 0, &"vial", [&"fuel", &"liquid_sample"],
			"Thick black sludge. Useless until it has been through a refinery."],
		[&"erchius_fuel", "Erchius Fuel", Color(0.62, 0.86, 0.98), 55, 1, &"vial", [&"fuel", &"ship_fuel", &"alien", &"glowing"],
			"Ground erchius, suspended and unstable. What ships actually run on."],
		[&"ftl_fuel", "FTL Fuel", Color(0.52, 0.72, 0.98), 90, 1, &"vial", [&"fuel", &"ship_fuel"],
			"Erchius cut with catalyst. Enough for one short jump."],
		[&"refined_ftl_fuel", "Refined FTL Fuel", Color(0.92, 0.62, 0.20), 220, 2, &"vial", [&"fuel", &"ship_fuel", &"refined"],
			"Cracked, filtered and stabilised. This one crosses systems."],
		[&"sulphur", "Sulphur", Color(0.92, 0.86, 0.28), 9, 0, &"dust", [&"reagent", &"explosive"],
			"Acrid yellow powder. Half of every explosive worth building."],
		[&"saltpetre", "Saltpetre", Color(0.90, 0.90, 0.84), 10, 0, &"dust", [&"reagent", &"explosive"],
			"White crystalline nitrate. The other half."],
		[&"gunpowder", "Gunpowder", Color(0.28, 0.26, 0.24), 24, 0, &"dust", [&"reagent", &"explosive"],
			"Charcoal, sulphur and saltpetre, in an argument."],
		[&"tar", "Tar", Color(0.09, 0.08, 0.09), 7, 0, &"blob", [&"fuel", &"adhesive"],
			"Sticky, flammable, and unpleasant to carry. Waterproofs anything."],
		[&"carbon_powder", "Carbon Powder", Color(0.20, 0.20, 0.22), 8, 0, &"dust", [&"reagent"],
			"Milled carbon. Alloys, filters and one very sharp cutting edge."],
	]
	_bulk(reg, rows, &"fuel")


# ==================================================================== gems ====
static func _gems(reg) -> void:
	var rows := [
		[&"crystal_shard", "Crystal Shard", Color(0.72, 0.90, 0.98), 14, 0, &"shard", [&"gem", &"crystal"],
			"A splinter of cave crystal. Focuses energy, badly but cheaply."],
		[&"quartz", "Quartz", Color(0.92, 0.92, 0.95), 18, 0, &"gem", [&"gem", &"crystal"],
			"Clear and piezoelectric. Every oscillator starts here."],
		[&"amethyst", "Amethyst", Color(0.62, 0.36, 0.86), 45, 1, &"gem", [&"gem", &"crystal"],
			"Violet quartz. Vendors like it more than engineers do."],
		[&"emerald", "Emerald", Color(0.24, 0.80, 0.46), 60, 1, &"gem", [&"gem", &"crystal"],
			"Deep green beryl, flawed more often than not."],
		[&"ruby", "Ruby", Color(0.86, 0.18, 0.26), 70, 1, &"gem", [&"gem", &"crystal"],
			"Red corundum. Makes a superb laser cavity."],
		[&"sapphire", "Sapphire", Color(0.22, 0.42, 0.92), 70, 1, &"gem", [&"gem", &"crystal"],
			"The same mineral as ruby, in a better mood."],
		[&"topaz", "Topaz", Color(0.95, 0.68, 0.22), 55, 1, &"gem", [&"gem", &"crystal"],
			"Golden and hard. Cuts glass, cuts prices."],
		[&"diamond", "Diamond", Color(0.88, 0.96, 1.0), 160, 2, &"gem", [&"gem", &"crystal", &"treasure"],
			"Compressed carbon, harder than anything you own. Yet."],
		[&"prism_shard", "Prism Shard", Color(0.80, 0.70, 0.98), 95, 2, &"shard", [&"gem", &"crystal", &"exotic"],
			"Splits light into colours that have no business existing."],
		[&"crystal", "Crystal", Color(0.70, 0.86, 0.96), 40, 0, &"gem", [&"gem", &"crystal", &"refined"],
			"A cut, clean crystal. Lenses, lasers and cheap jewellery."],
		[&"ice_crystal", "Ice Crystal", Color(0.72, 0.92, 1.00), 26, 1, &"gem", [&"gem", &"crystal", &"cold"],
			"Cold enough to burn, and it never melts. Nobody knows why."],
		[&"luminous_powder", "Luminous Powder", Color(0.66, 0.98, 0.78), 30, 1, &"dust", [&"gem", &"reagent", &"glowing"],
			"Ground glow-crystal. Faintly warm, permanently lit."],
		[&"glow_dust", "Glow Dust", Color(0.78, 0.98, 0.62), 16, 0, &"dust", [&"reagent", &"glowing"],
			"Scraped off cave crystal. Enough of it will light a tunnel."],
	]
	_bulk(reg, rows, &"gem")


# ================================================================ organics ====
static func _organics(reg) -> void:
	var rows := [
		[&"plant_fibre", "Plant Fibre", Color(0.55, 0.72, 0.34), 2, 0, &"strand", [&"organic", &"fibre"],
			"Stripped from tall grass. The first thing anyone crafts with."],
		[&"plant_matter", "Plant Matter", Color(0.38, 0.58, 0.26), 2, 0, &"blob", [&"organic", &"compostable"],
			"Pulped greenery. Compost, feed, or the base of a cheap bandage."],
		[&"vine_cord", "Vine Cord", Color(0.42, 0.60, 0.28), 5, 0, &"strand", [&"organic", &"fibre"],
			"A tough living vine, cut and coiled. Nearly as good as rope."],
		[&"tree_sap", "Tree Sap", Color(0.86, 0.66, 0.28), 6, 0, &"blob", [&"organic", &"adhesive"],
			"Sweet, sticky and slow. Glue, syrup or bait."],
		[&"resin", "Resin", Color(0.78, 0.52, 0.20), 9, 0, &"blob", [&"organic", &"adhesive"],
			"Hardened sap. Seals a hull well enough to survive one re-entry."],
		[&"bark_strip", "Bark Strip", Color(0.44, 0.32, 0.20), 3, 0, &"strand", [&"organic", &"wood"],
			"Peeled bark. Tinder, cordage, and a passable roof tile."],
		[&"cotton_wool", "Cotton Wool", Color(0.94, 0.93, 0.88), 6, 0, &"puff", [&"organic", &"fibre"],
			"Soft bolls waiting to be spun."],
		[&"silk_thread", "Silk Thread", Color(0.92, 0.90, 0.78), 14, 1, &"strand", [&"organic", &"fibre"],
			"Spun by something with too many legs. Absurdly strong."],
		[&"string", "String", Color(0.88, 0.86, 0.74), 5, 0, &"strand", [&"organic", &"fibre", &"refined"],
			"Twisted fibre. Bowstrings, stitching, tripwire."],
		[&"cloth", "Cloth", Color(0.80, 0.74, 0.62), 18, 0, &"cloth", [&"organic", &"fibre", &"refined"],
			"A bolt of woven cloth. Clothing, sails, parachutes, bandages."],
		[&"sinew_strand", "Sinew Strand", Color(0.86, 0.70, 0.62), 9, 0, &"strand", [&"organic", &"fibre", &"monster_drop"],
			"Dried tendon. Stronger than rope, and it knows it."],
		[&"glow_sap", "Glow Sap", Color(0.74, 0.98, 0.60), 22, 1, &"blob", [&"organic", &"adhesive", &"glowing"],
			"Sap from a lantern-vine. Sticky, and it lights your hands."],
		[&"leather", "Leather", Color(0.55, 0.36, 0.22), 12, 0, &"hide", [&"organic", &"leather"],
			"Cured hide. Flexible armour for people who dislike clanking."],
		[&"tough_leather", "Tough Leather", Color(0.40, 0.26, 0.16), 28, 1, &"hide", [&"organic", &"leather", &"refined"],
			"Boiled and layered until it turns a claw."],
		[&"hide", "Raw Hide", Color(0.62, 0.45, 0.30), 6, 0, &"hide", [&"organic", &"leather", &"monster_drop"],
			"Untreated skin. Tan it before it turns."],
		[&"feather", "Feather", Color(0.90, 0.88, 0.92), 4, 0, &"strand", [&"organic", &"monster_drop"],
			"Light, springy and stubbornly aerodynamic."],
		[&"straw", "Straw", Color(0.86, 0.76, 0.42), 1, 0, &"strand", [&"organic", &"junk"],
			"Dried stalks. Bedding, thatch, and very little else."],
	]
	_bulk(reg, rows, &"organic")


# ==================================================================== wood ====
static func _woods(reg) -> void:
	var rows := [
		[&"wood", "Wood", Color(0.55, 0.38, 0.22), 3, 0, &"log", [&"wood", &"organic", &"flammable_mat"],
			"Honest lumber. Burns, builds, floats."],
		[&"plank", "Wooden Plank", Color(0.68, 0.50, 0.30), 5, 0, &"plank", [&"wood", &"refined"],
			"Sawn flat and square. Furniture, floors, crates."],
		[&"stick", "Stick", Color(0.60, 0.44, 0.26), 2, 0, &"rod", [&"wood"],
			"Two of these and a rock is most of a tool."],
		[&"sawdust", "Sawdust", Color(0.78, 0.66, 0.44), 1, 0, &"dust", [&"wood", &"junk"],
			"What the saw left behind. Someone will want it eventually."],
		[&"driftwood", "Driftwood", Color(0.62, 0.58, 0.52), 4, 0, &"log", [&"wood"],
			"Salt-bleached and hollow. Floats better than it burns."],
		[&"petrified_wood", "Petrified Wood", Color(0.48, 0.42, 0.40), 22, 1, &"log", [&"wood", &"fossil"],
			"Wood that became stone and kept its grain."],
		[&"living_wood", "Living Wood", Color(0.40, 0.62, 0.34), 30, 1, &"log", [&"wood", &"exotic"],
			"Still growing, slowly, wherever you put it down."],
		[&"alien_wood", "Alien Wood", Color(0.52, 0.36, 0.66), 26, 1, &"log", [&"wood", &"alien"],
			"Fibrous purple heartwood. Smells faintly of ozone."],
		[&"frozen_wood", "Frozen Wood", Color(0.66, 0.82, 0.90), 20, 1, &"log", [&"wood", &"cold"],
			"Frozen through to the core. Cold to hold, hard to split."],
		[&"cinder_wood", "Cinder Wood", Color(0.32, 0.20, 0.18), 20, 1, &"log", [&"wood", &"fuel"],
			"Charred outside, smouldering inside. Never quite goes out."],
	]
	_bulk(reg, rows, &"wood")


# =========================================================== monster drops ====
static func _monster_drops(reg) -> void:
	var rows := [
		[&"chitin", "Chitin", Color(0.62, 0.52, 0.30), 8, 0, &"plate", [&"monster_drop", &"organic"],
			"Flaked insect shell. Light, and surprisingly hard to cut."],
		[&"chitin_plate", "Chitin Plate", Color(0.48, 0.40, 0.24), 22, 1, &"plate", [&"monster_drop", &"organic", &"refined"],
			"A whole intact segment. Straps onto armour with no fuss."],
		[&"venom_gland", "Venom Gland", Color(0.44, 0.82, 0.32), 26, 1, &"vial", [&"monster_drop", &"reagent", &"toxic"],
			"Still turgid. Handle by the duct, never the bulb."],
		[&"monster_fur", "Monster Fur", Color(0.58, 0.44, 0.34), 7, 0, &"puff", [&"monster_drop", &"fibre"],
			"Coarse pelt hair. Warm, once you get the smell out."],
		[&"bone", "Bone", Color(0.90, 0.88, 0.78), 5, 0, &"bone", [&"monster_drop"],
			"Somebody's, once. Tools, meal, or a very rude decoration."],
		[&"bone_shard", "Bone Shard", Color(0.86, 0.84, 0.74), 3, 0, &"shard", [&"monster_drop", &"junk"],
			"Splinters from something bigger. Sharp enough to matter."],
		[&"bone_meal", "Bone Meal", Color(0.94, 0.92, 0.86), 6, 0, &"dust", [&"monster_drop", &"fertiliser"],
			"Ground bone. Crops adore it."],
		[&"ectoplasm", "Ectoplasm", Color(0.66, 0.92, 0.86), 55, 2, &"blob", [&"monster_drop", &"exotic", &"glowing"],
			"Cold, luminous, and it drips upward if you stop watching."],
		[&"slime_glob", "Slime Glob", Color(0.52, 0.86, 0.44), 4, 0, &"blob", [&"monster_drop", &"adhesive"],
			"Adhesive, edible, and morally questionable in soup."],
		[&"scale_plate", "Scale Plate", Color(0.34, 0.54, 0.48), 24, 1, &"plate", [&"monster_drop", &"armour_mat"],
			"Overlapping scales torn free in one sheet."],
		[&"sharp_claw", "Sharp Claw", Color(0.82, 0.78, 0.70), 20, 1, &"claw", [&"monster_drop", &"weapon_mat"],
			"Keeps its edge better than most knives you can buy."],
		[&"fang", "Fang", Color(0.94, 0.92, 0.84), 18, 1, &"claw", [&"monster_drop", &"weapon_mat"],
			"Hollow, grooved, and clearly built for delivering something."],
		[&"glow_gland", "Glow Gland", Color(0.72, 0.96, 0.52), 38, 1, &"orb", [&"monster_drop", &"glowing"],
			"Lights a room for a week. Then it doesn't, forever."],
	]
	_bulk(reg, rows, &"monster")


# ============================================================== components ====
static func _components(reg) -> void:
	var rows := [
		[&"copper_wire", "Copper Wire", Color(0.86, 0.52, 0.28), 10, 0, &"coil", [&"component", &"electronic"],
			"Drawn thin and coiled. Carries current, badly insulated."],
		[&"silicon_wafer", "Silicon Wafer", Color(0.62, 0.66, 0.72), 22, 0, &"chip", [&"component", &"electronic"],
			"A polished disc of doped silicon awaiting a pattern."],
		[&"circuit_board", "Circuit Board", Color(0.24, 0.62, 0.38), 40, 0, &"chip", [&"component", &"electronic"],
			"Etched, drilled and populated. The brain of cheap machines."],
		[&"advanced_circuit", "Advanced Circuit", Color(0.28, 0.78, 0.72), 110, 1, &"chip", [&"component", &"electronic"],
			"Twelve layers of it. Do not attempt a field repair."],
		[&"quantum_processor", "Quantum Processor", Color(0.42, 0.46, 0.88), 190, 2, &"chip", [&"component", &"electronic"],
			"Enough compute to fly a ship, in the size of a thumbnail."],
		[&"battery", "Battery", Color(0.90, 0.78, 0.22), 35, 0, &"cell", [&"component", &"power"],
			"Charged, sealed, and only mildly prone to venting."],
		[&"energy_cell", "Energy Cell", Color(0.96, 0.82, 0.24), 70, 0, &"cell", [&"component", &"power"],
			"The standard charge unit. Tools, doors and torches all take one."],
		[&"dense_energy_cell", "Dense Energy Cell", Color(0.98, 0.56, 0.22), 210, 2, &"cell", [&"component", &"power"],
			"Four cells' charge in one casing, and twice the warning labels."],
		[&"high_capacity_battery", "High-Capacity Battery", Color(0.96, 0.62, 0.18), 120, 1, &"cell", [&"component", &"power"],
			"Holds a day of tool charge. Or half a second of a mistake."],
		[&"power_core", "Power Core", Color(0.36, 0.88, 0.94), 260, 2, &"orb", [&"component", &"power"],
			"A humming lattice that gives back more than it was fed."],
		[&"fusion_core", "Fusion Core", Color(0.98, 0.86, 0.40), 620, 3, &"orb", [&"component", &"power", &"exotic"],
			"A star, penned in and made to work shifts."],
		[&"iron_gear", "Iron Gear", Color(0.58, 0.58, 0.62), 16, 0, &"gear", [&"component", &"mechanical"],
			"Cut iron teeth. Turns one kind of effort into another."],
		[&"electric_motor", "Electric Motor", Color(0.48, 0.52, 0.60), 85, 1, &"gear", [&"component", &"mechanical"],
			"Precise, geared and quiet. Doors, arms and legs."],
		[&"sensor_lens", "Sensor Lens", Color(0.70, 0.88, 0.94), 65, 1, &"gem", [&"component", &"electronic"],
			"Ground to a tolerance you cannot see and cannot afford to ruin."],
		[&"nanowire", "Nanowire", Color(0.78, 0.82, 0.90), 180, 2, &"coil", [&"component", &"electronic", &"exotic"],
			"One molecule thick, and it will still hold your weight."],
		[&"hydraulic_piston", "Hydraulic Piston", Color(0.52, 0.56, 0.58), 95, 1, &"rod", [&"component", &"mechanical"],
			"Shoves harder than anything its size has a right to."],
	]
	_bulk(reg, rows, &"component")


# =========================================================== alien matter ====
static func _alien(reg) -> void:
	var rows := [
		[&"alien_compound", "Alien Compound", Color(0.56, 0.34, 0.78), 45, 1, &"blob", [&"alien", &"reagent"],
			"Chemistry that does not appear in any of your reference tables."],
		[&"protocite", "Protocite", Color(0.94, 0.44, 0.62), 130, 2, &"chunk", [&"alien", &"exotic"],
			"Warm to the touch and slowly rearranging itself."],
		[&"cosmic_dust", "Cosmic Dust", Color(0.44, 0.36, 0.62), 90, 1, &"dust", [&"alien", &"exotic"],
			"Swept out of a dead nebula. Older than this planet."],
		[&"star_dust", "Star Dust", Color(0.92, 0.88, 0.98), 120, 2, &"dust", [&"alien", &"exotic", &"glowing"],
			"Scraped off a meteorite. Still remembers being a star."],
		[&"void_residue", "Void Residue", Color(0.14, 0.10, 0.22), 210, 2, &"blob", [&"alien", &"exotic"],
			"The stain something left when it stopped existing here."],
		[&"starlight_essence", "Starlight Essence", Color(0.98, 0.94, 0.70), 320, 3, &"orb", [&"alien", &"exotic", &"glowing"],
			"Bottled photons that have not yet agreed to be photons."],
		[&"plasmic_gel", "Plasmic Gel", Color(0.98, 0.42, 0.28), 140, 2, &"vial", [&"alien", &"reagent"],
			"Suspended plasma in a gel that really should not hold it."],
		[&"xeno_resin", "Xeno Resin", Color(0.36, 0.72, 0.44), 70, 1, &"blob", [&"alien", &"adhesive"],
			"Secreted, hardened, and stronger than the hull it grew on."],
		[&"aether_dust", "Aether Dust", Color(0.72, 0.62, 0.98), 260, 3, &"dust", [&"alien", &"exotic"],
			"Weighs slightly less than nothing. The scales disagree daily."],
		[&"quantum_fluid", "Quantum Fluid", Color(0.34, 0.94, 0.88), 400, 3, &"vial", [&"alien", &"exotic"],
			"It is in the flask. It is also, measurably, not."],
	]
	_bulk(reg, rows, &"alien")


# ================================================================= fossils ====
static func _fossils(reg) -> void:
	var rows := [
		[&"fossil_fragment", "Fossil Fragment", Color(0.72, 0.66, 0.54), 20, 0, &"shard", [&"fossil", &"treasure"],
			"A piece of something that died a very long time before you."],
		[&"ancient_fragment", "Ancient Fragment", Color(0.80, 0.72, 0.52), 90, 1, &"shard", [&"fossil", &"treasure", &"alien"],
			"Machined, not grown. Six of them make something that still works."],
		[&"ancient_artifact", "Ancient Artifact", Color(0.90, 0.80, 0.50), 420, 3, &"relic", [&"fossil", &"treasure", &"alien"],
			"Intact, humming, and older than the species that built the outpost."],
		[&"amber_shard", "Amber Shard", Color(0.94, 0.66, 0.24), 60, 1, &"gem", [&"fossil", &"treasure", &"gem"],
			"Fossil resin with a passenger, still mid-panic."],
		[&"trilobite_fossil", "Trilobite Fossil", Color(0.56, 0.50, 0.44), 110, 1, &"plate", [&"fossil", &"treasure"],
			"Complete, articulated, and worth more than the tool that found it."],
		[&"ancient_skull", "Ancient Skull", Color(0.84, 0.80, 0.68), 240, 2, &"bone", [&"fossil", &"treasure"],
			"Too many eye sockets, arranged with unsettling symmetry."],
		[&"petrified_egg", "Petrified Egg", Color(0.78, 0.72, 0.60), 380, 3, &"orb", [&"fossil", &"treasure"],
			"Unhatched, mineralised, and — the scanner insists — still warm."],
		[&"ancient_relic", "Ancient Relic", Color(0.86, 0.74, 0.44), 500, 3, &"relic", [&"fossil", &"treasure", &"alien"],
			"Machined by hands that had no business having this technology."],
	]
	_bulk(reg, rows, &"fossil")


# ============================================================ quest tokens ====
## Quest items: never sellable, never despawn as drops, one per slot.
static func _quest_items(reg) -> void:
	var rows := [
		[&"ancient_key", "Ancient Key", Color(0.88, 0.78, 0.40), &"key",
			"Fits exactly one door, somewhere on this planet."],
		[&"star_map_fragment", "Star Map Fragment", Color(0.46, 0.66, 0.98), &"scroll",
			"A torn slice of a much larger, much older chart."],
		[&"distress_beacon", "Distress Beacon", Color(0.92, 0.34, 0.30), &"orb",
			"Still transmitting. Someone is still waiting."],
		[&"data_slate", "Data Slate", Color(0.40, 0.72, 0.82), &"scroll",
			"Corrupted logs and one intact set of coordinates."],
		[&"cipher_key", "Cipher Key", Color(0.66, 0.44, 0.90), &"key",
			"Decodes the glyphs. Does not explain them."],
		[&"ancient_essence", "Ancient Essence", Color(0.94, 0.86, 0.56), &"orb",
			"Distilled from a relic. The Gate wants six of them."],
		[&"guild_token", "Guild Token", Color(0.78, 0.72, 0.62), &"relic",
			"Proof of a favour owed, redeemable at any outpost."],
		[&"beacon_shard", "Beacon Shard", Color(0.52, 0.92, 0.90), &"shard",
			"One quarter of a working teleport anchor."],
	]
	for row: Array in rows:
		var it := _mat(reg, row[0], row[1], row[2], 0, Const.RARITY_ESSENTIAL,
			&"quest", row[3], [&"quest", &"no_sell"], row[4])
		if it != null:
			it.of_kind(ItemType.Kind.QUEST).stacks(1)


# ========================================================== crafting misc ====
static func _crafting_misc(reg) -> void:
	var rows := [
		[&"glass_shard", "Glass Shard", Color(0.76, 0.90, 0.92), 3, 0, &"shard", [&"crafting"],
			"Sharp, useless alone, and the start of every window."],
		[&"glass", "Glass", Color(0.80, 0.92, 0.94), 8, 0, &"plate", [&"crafting", &"building_mat"],
			"Melted sand, poured flat. Windows, lenses, bottles."],
		[&"brick", "Brick", Color(0.72, 0.38, 0.30), 6, 0, &"plate", [&"crafting", &"building_mat"],
			"Fired clay. Stacks square, outlasts everyone who stacked it."],
		[&"clay_lump", "Clay Lump", Color(0.68, 0.48, 0.40), 3, 0, &"blob", [&"crafting"],
			"Wet earth that remembers whatever shape you leave it in."],
		[&"flint", "Flint", Color(0.32, 0.32, 0.36), 4, 0, &"shard", [&"crafting", &"weapon_mat"],
			"Knapped stone. Sparks, cuts, and started all of this."],
		[&"paper", "Paper", Color(0.94, 0.92, 0.86), 4, 0, &"plate", [&"crafting"],
			"Pressed pulp. Notes, blueprints, and one very old map."],
		[&"latex", "Latex", Color(0.92, 0.90, 0.84), 8, 0, &"blob", [&"crafting", &"organic"],
			"Milky sap tapped from a rubber tree. Vulcanise before use."],
		[&"tallow", "Tallow", Color(0.94, 0.90, 0.74), 6, 0, &"blob", [&"crafting", &"organic"],
			"Rendered fat. Candles, soap, and waterproofing for boots."],
		[&"cement_mix", "Cement Mix", Color(0.72, 0.72, 0.70), 6, 0, &"dust", [&"crafting", &"building_mat"],
			"Just add water, then hurry."],
		[&"iron_nail", "Iron Nail", Color(0.62, 0.60, 0.58), 2, 0, &"rod", [&"crafting", &"metal"],
			"Sold by the handful, lost by the handful."],
		[&"rope", "Rope", Color(0.78, 0.68, 0.44), 12, 0, &"coil", [&"crafting", &"fibre"],
			"Twisted fibre. Climbing, hauling, and one bad idea."],
		[&"rubber", "Rubber", Color(0.22, 0.20, 0.20), 14, 0, &"blob", [&"crafting", &"insulator"],
			"Vulcanised sap. Grips, seals and refuses to conduct."],
		[&"salt", "Salt", Color(0.96, 0.96, 0.94), 4, 0, &"dust", [&"crafting", &"reagent", &"preservative"],
			"Preserves food, ruins metal, seasons everything."],
		[&"ash", "Ash", Color(0.44, 0.42, 0.42), 1, 0, &"dust", [&"crafting", &"junk", &"fertiliser"],
			"What is left when the burning finishes. Good for soil."],
		[&"obsidian_shard", "Obsidian Shard", Color(0.14, 0.12, 0.18), 26, 1, &"shard", [&"crafting", &"weapon_mat"],
			"Volcanic glass, honed to an edge one molecule wide."],
		[&"polymer", "Polymer", Color(0.82, 0.84, 0.86), 26, 0, &"plate", [&"crafting", &"refined"],
			"Long-chain plastic sheet. Light, tough, entirely artificial."],
		[&"adhesive", "Adhesive", Color(0.88, 0.84, 0.60), 16, 0, &"vial", [&"crafting", &"adhesive"],
			"Industrial glue. Bonds anything, including the applicator."],
	]
	_bulk(reg, rows, &"crafting")


## Register a table of rows shaped
## `[id, display, colour, value, rarity, icon_shape, tags, description]`.
static func _bulk(reg, rows: Array, category: StringName) -> void:
	for row: Array in rows:
		_mat(reg, row[0], row[1], row[2], int(row[3]), int(row[4]),
			category, row[5], row[6], row[7])
