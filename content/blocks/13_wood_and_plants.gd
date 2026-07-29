## Everything that grows.
##
## Ten tree species, each registered by `PsBlocks.tree_set` as a matched
## quartet — `<species>_log`, `<species>_leaves`, `<species>_planks`,
## `<species>_sapling`. The worldgen agent can pick a species per biome with
## `Blocks.all_with_tag(&"tree_log")` filtered by the `biome_*` tag; the
## crafting agent can turn any `tree_log` into its `_planks` with one generic
## recipe because the naming is mechanical.
##
## Undergrowth uses `Render.CROSS` (two crossed quads, never solid) and is
## `replaceable` so the player can build straight through a meadow. Vines and
## kelp are `climbable`; cactus and thorns carry `damage_on_touch`.
extends RefCounted


static func register_all(reg) -> void:
	_trees(reg)
	_undergrowth(reg)
	_desert(reg)
	_fungus(reg)
	_aquatic(reg)
	_alien(reg)


# --------------------------------------------------------------------- trees
static func _trees(reg) -> void:
	PsBlocks.tree_set(reg, &"oak", "Oak",
		Color(0.44, 0.32, 0.20), Color(0.34, 0.24, 0.15),
		Color(0.28, 0.55, 0.24), Color(0.68, 0.52, 0.32), &"biome_forest", 1.3)
	PsBlocks.tree_set(reg, &"birch", "Birch",
		Color(0.88, 0.86, 0.80), Color(0.32, 0.30, 0.28),
		Color(0.46, 0.68, 0.30), Color(0.86, 0.80, 0.64), &"biome_forest", 1.1)
	PsBlocks.tree_set(reg, &"pine", "Pine",
		Color(0.34, 0.25, 0.18), Color(0.24, 0.18, 0.13),
		Color(0.16, 0.40, 0.26), Color(0.72, 0.58, 0.38), &"biome_tundra", 1.2)
	PsBlocks.tree_set(reg, &"acacia", "Acacia",
		Color(0.52, 0.30, 0.22), Color(0.38, 0.22, 0.16),
		Color(0.22, 0.46, 0.30), Color(0.78, 0.50, 0.34), &"biome_forest", 1.4)
	PsBlocks.tree_set(reg, &"jungle", "Jungle",
		Color(0.38, 0.30, 0.16), Color(0.27, 0.21, 0.11),
		Color(0.18, 0.58, 0.18), Color(0.60, 0.48, 0.24), &"biome_jungle", 1.5)
	PsBlocks.tree_set(reg, &"cherry", "Cherry",
		Color(0.38, 0.25, 0.24), Color(0.28, 0.18, 0.17),
		Color(0.94, 0.62, 0.76), Color(0.80, 0.56, 0.50), &"biome_forest", 1.2)
	PsBlocks.tree_set(reg, &"palm", "Palm",
		Color(0.60, 0.48, 0.30), Color(0.46, 0.37, 0.23),
		Color(0.38, 0.66, 0.28), Color(0.82, 0.68, 0.44), &"biome_desert", 1.0)
	PsBlocks.tree_set(reg, &"alien", "Alien",
		Color(0.36, 0.22, 0.44), Color(0.26, 0.15, 0.32),
		Color(0.66, 0.30, 0.86), Color(0.56, 0.38, 0.66), &"biome_alien", 1.8, 0.85)

	PsBlocks.tree_set(reg, &"willow", "Willow",
		Color(0.40, 0.34, 0.24), Color(0.29, 0.24, 0.17),
		Color(0.44, 0.60, 0.32), Color(0.66, 0.58, 0.40), &"biome_jungle", 1.2)
	PsBlocks.tree_set(reg, &"glow", "Glowwood",
		Color(0.30, 0.34, 0.42), Color(0.22, 0.26, 0.33),
		Color(0.38, 0.92, 0.82), Color(0.52, 0.60, 0.68), &"biome_alien", 1.3)
	# Glowwood earns its name: both halves are emissive.
	var glow_log: BlockType = reg.get_by_name(&"glow_log")
	if glow_log != null:
		glow_log.glows(4, 0.6).tag(&"light_source")
	var glow_leaves: BlockType = reg.get_by_name(&"glow_leaves")
	if glow_leaves != null:
		glow_leaves.glows(9, 1.0).tag(&"light_source")

	# Dead wood. These are trunk-only species for the decorator's `dead` tree
	# shape, plus the generic fallbacks every species chain ends in.
	_bare_log(reg, &"dead_log", "Dead Log", Color(0.44, 0.38, 0.31), Color(0.32, 0.27, 0.22), &"biome_barren")
	_bare_log(reg, &"charred_log", "Charred Log", Color(0.20, 0.17, 0.16), Color(0.13, 0.11, 0.10), &"biome_magma")
	_bare_log(reg, &"wood_log", "Wood Log", Color(0.46, 0.34, 0.21), Color(0.34, 0.25, 0.15), &"biome_forest")
	reg.define(&"leaves", "Leaves").look(Color(0.30, 0.58, 0.26, 0.92), BlockType.Pattern.LEAF, Color(0.21, 0.41, 0.18)) \
		.mode(BlockType.Render.TRANSPARENT).mining(0.25, &"any", 0).sounds(&"step_leaves") \
		.drop(&"plant_fibre", 1, 2, 0.35).in_category(&"plant").tag(&"leaves") \
		.tag(&"tree_leaves").tag(&"biome_forest").flags({"flammable": true})

	# A non-renewable "species": petrified wood found in deep strata.
	reg.define(&"petrified_log", "Petrified Log").look(Color(0.48, 0.44, 0.42), BlockType.Pattern.LOG, Color(0.36, 0.33, 0.32)) \
		.mining(3.2, &"pickaxe", 2).sounds(&"step_stone").drop(&"petrified_log") \
		.in_category(&"plant").tag(&"stone").tag(&"tree_log").tag(&"stratum_deep")


## A trunk with no matching leaf set — used by dead / burnt tree shapes.
static func _bare_log(reg, p_name: StringName, display: String, col: Color, alt: Color,
		biome: StringName) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, BlockType.Pattern.LOG, alt)
	bt.with_top(alt.lightened(0.12))
	bt.mining(1.1, &"axe", 0)
	bt.sounds(&"step_wood")
	bt.flags({"flammable": true})
	bt.in_category(&"plant").tag(&"wood").tag(&"tree_log").tag(biome)
	return bt


# --------------------------------------------------------------- undergrowth
static func _undergrowth(reg) -> void:
	PsBlocks.foliage(reg, &"tall_grass", "Tall Grass", Color(0.36, 0.64, 0.28),
		Color(0.26, 0.50, 0.20), &"biome_forest", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"dry_grass", "Dry Grass", Color(0.72, 0.66, 0.34),
		Color(0.58, 0.52, 0.26), &"biome_savannah", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"fern", "Fern", Color(0.24, 0.52, 0.28),
		Color(0.17, 0.38, 0.20), &"biome_jungle", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"dead_bush", "Dead Bush", Color(0.50, 0.38, 0.22),
		Color(0.38, 0.28, 0.16), &"biome_desert", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"reed", "Reed", Color(0.42, 0.62, 0.34),
		Color(0.30, 0.48, 0.24), &"biome_jungle", &"grass_tuft", &"reed_stalk")
	PsBlocks.foliage(reg, &"moss_carpet", "Moss Carpet", Color(0.30, 0.50, 0.26),
		Color(0.22, 0.38, 0.19), &"biome_forest", &"grass_tuft", &"moss_clump") \
		.flags({"replaceable": true})

	# Per-biome tufts. The worldgen decorator asks for these names by biome and
	# silently skips any that are missing, so each one is a biome that visibly
	# gains undergrowth.
	PsBlocks.foliage(reg, &"grass_tuft", "Grass Tuft", Color(0.40, 0.68, 0.30),
		Color(0.28, 0.52, 0.22), &"biome_forest", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"savannah_shrub", "Savannah Shrub", Color(0.62, 0.60, 0.28),
		Color(0.46, 0.44, 0.20), &"biome_savannah", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"desert_shrub", "Desert Shrub", Color(0.56, 0.50, 0.30),
		Color(0.42, 0.37, 0.22), &"biome_desert", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"snow_shrub", "Snow Shrub", Color(0.60, 0.70, 0.66),
		Color(0.44, 0.54, 0.50), &"biome_tundra", &"grass_tuft", &"plant_fibre") \
		.sounds(&"step_snow").flags({"replaceable": true, "flammable": false})
	PsBlocks.foliage(reg, &"jungle_fern", "Jungle Fern", Color(0.18, 0.56, 0.24),
		Color(0.12, 0.40, 0.17), &"biome_jungle", &"grass_tuft", &"plant_fibre") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"ember_shrub", "Ember Shrub", Color(0.46, 0.24, 0.16),
		Color(0.86, 0.36, 0.12), &"biome_magma", &"grass_tuft", &"plant_fibre") \
		.glows(2, 0.4).flags({"replaceable": true})
	PsBlocks.foliage(reg, &"toxic_fungus", "Toxic Fungus", Color(0.54, 0.72, 0.24),
		Color(0.34, 0.46, 0.16), &"biome_toxic", &"mushroom", &"spore_cluster") \
		.tag(&"fungus").glows(2, 0.4)
	PsBlocks.foliage(reg, &"alien_shoot", "Alien Shoot", Color(0.66, 0.34, 0.88),
		Color(0.42, 0.22, 0.58), &"biome_alien", &"grass_tuft", &"alien_seed") \
		.flags({"replaceable": true})
	PsBlocks.foliage(reg, &"sea_grass", "Sea Grass", Color(0.24, 0.60, 0.44),
		Color(0.16, 0.42, 0.31), &"biome_ocean", &"grass_tuft", &"kelp_frond") \
		.sounds(&"step_liquid").flags({"replaceable": true, "flammable": false})
	PsBlocks.foliage(reg, &"glowbulb", "Glowbulb", Color(0.44, 0.92, 0.86),
		Color(0.24, 0.56, 0.52), &"biome_alien", &"grass_tuft", &"glow_sap") \
		.glows(6, 0.9).tag(&"light_source")
	PsBlocks.foliage(reg, &"glow_mushroom", "Glow Mushroom", Color(0.52, 0.72, 1.00),
		Color(0.30, 0.44, 0.70), &"biome_forest", &"mushroom", &"mushroom_blue") \
		.tag(&"fungus").glows(7, 1.0).tag(&"light_source")

	PsBlocks.foliage(reg, &"flower_red", "Red Bloom", Color(0.88, 0.24, 0.26),
		Color(0.30, 0.54, 0.24), &"biome_forest", &"flower")
	PsBlocks.foliage(reg, &"flower_yellow", "Sunbud", Color(0.96, 0.84, 0.28),
		Color(0.30, 0.54, 0.24), &"biome_savannah", &"flower")
	PsBlocks.foliage(reg, &"flower_blue", "Bluebell", Color(0.36, 0.48, 0.94),
		Color(0.30, 0.54, 0.24), &"biome_tundra", &"flower")
	PsBlocks.foliage(reg, &"flower_purple", "Violet Star", Color(0.70, 0.36, 0.92),
		Color(0.30, 0.54, 0.24), &"biome_jungle", &"flower")
	PsBlocks.foliage(reg, &"flower_white", "Frostpetal", Color(0.96, 0.96, 0.98),
		Color(0.38, 0.52, 0.40), &"biome_tundra", &"flower")
	PsBlocks.foliage(reg, &"flower_orange", "Emberpetal", Color(0.96, 0.56, 0.18),
		Color(0.30, 0.54, 0.24), &"biome_savannah", &"flower")
	PsBlocks.foliage(reg, &"flower_pink", "Blushbell", Color(0.96, 0.56, 0.74),
		Color(0.30, 0.54, 0.24), &"biome_jungle", &"flower")
	PsBlocks.foliage(reg, &"toxic_flower", "Blightbloom", Color(0.72, 0.88, 0.24),
		Color(0.34, 0.44, 0.18), &"biome_toxic", &"flower") \
		.tag(&"hazard").flags({"damage_on_touch": 1.0, "damage_element": Const.ELEM_POISON})
	PsBlocks.foliage(reg, &"glow_flower", "Lumibloom", Color(0.60, 0.92, 1.00),
		Color(0.26, 0.46, 0.54), &"biome_alien", &"flower") \
		.glows(6, 0.9).tag(&"light_source")

	# Climbable growth. `mode(CROSS)` already cleared `solid`, so `climbable`
	# alone gives the ladder behaviour the player controller looks for.
	reg.define(&"vine", "Vine").look(Color(0.26, 0.50, 0.24), BlockType.Pattern.ORGANIC, Color(0.19, 0.37, 0.18)) \
		.mode(BlockType.Render.CROSS).mining(0.15, &"any", 0).sounds(&"step_leaves") \
		.drop(&"plant_fibre", 1, 2).in_category(&"plant").tag(&"vine").tag(&"climbable").tag(&"foliage") \
		.tag(&"organic").tag(&"biome_jungle").flags({"climbable": true, "flammable": true})
	reg.define(&"thorn_vine", "Thorn Vine").look(Color(0.34, 0.42, 0.20), BlockType.Pattern.ORGANIC, Color(0.62, 0.56, 0.22)) \
		.mode(BlockType.Render.CROSS).mining(0.3, &"any", 0).sounds(&"step_leaves") \
		.drop(&"plant_fibre").in_category(&"plant").tag(&"vine").tag(&"climbable") \
		.tag(&"hazard").tag(&"foliage").tag(&"biome_jungle") \
		.flags({"climbable": true, "flammable": true, "damage_on_touch": 2.0})
	reg.define(&"glow_vine", "Glow Vine").look(Color(0.34, 0.78, 0.62), BlockType.Pattern.ORGANIC, Color(0.20, 0.52, 0.44)) \
		.mode(BlockType.Render.CROSS).mining(0.15, &"any", 0).sounds(&"step_leaves") \
		.glows(7, 0.9).drop(&"glow_sap", 1, 2).in_category(&"plant").tag(&"vine") \
		.tag(&"climbable").tag(&"light_source").tag(&"foliage").tag(&"biome_alien") \
		.flags({"climbable": true})


# ---------------------------------------------------------------- arid flora
static func _desert(reg) -> void:
	reg.define(&"cactus", "Cactus").look(Color(0.24, 0.52, 0.28), BlockType.Pattern.ORGANIC, Color(0.18, 0.40, 0.21)) \
		.mining(0.5, &"any", 0).sounds(&"step_grass").drop(&"cactus_pulp", 1, 2) \
		.in_category(&"plant").tag(&"organic").tag(&"hazard").tag(&"biome_desert") \
		.flags({"opaque": false, "damage_on_touch": 3.0})
	reg.define(&"barrel_cactus", "Barrel Cactus").look(Color(0.30, 0.56, 0.30), BlockType.Pattern.ORGANIC, Color(0.72, 0.60, 0.24)) \
		.mining(0.5, &"any", 0).sounds(&"step_grass").drop(&"cactus_pulp", 2, 3) \
		.in_category(&"plant").tag(&"organic").tag(&"hazard").tag(&"biome_desert") \
		.flags({"opaque": false, "damage_on_touch": 4.0})
	PsBlocks.foliage(reg, &"flower_cactus", "Desert Bloom", Color(0.94, 0.52, 0.30),
		Color(0.36, 0.52, 0.30), &"biome_desert", &"flower")


# ------------------------------------------------------------------- fungus
static func _fungus(reg) -> void:
	PsBlocks.foliage(reg, &"mushroom_brown", "Brown Mushroom", Color(0.60, 0.44, 0.30),
		Color(0.82, 0.76, 0.66), &"biome_forest", &"mushroom", &"mushroom_brown") \
		.tag(&"fungus")
	PsBlocks.foliage(reg, &"mushroom_red", "Red Mushroom", Color(0.82, 0.20, 0.18),
		Color(0.92, 0.90, 0.84), &"biome_forest", &"mushroom", &"mushroom_red") \
		.tag(&"fungus")
	PsBlocks.foliage(reg, &"mushroom_blue", "Azure Cap", Color(0.28, 0.46, 0.86),
		Color(0.80, 0.86, 0.94), &"biome_alien", &"mushroom", &"mushroom_blue") \
		.tag(&"fungus").glows(5, 0.8).tag(&"light_source")
	reg.define(&"mushroom_stem", "Mushroom Stem").look(Color(0.86, 0.82, 0.72), BlockType.Pattern.ORGANIC, Color(0.72, 0.68, 0.58)) \
		.mining(0.5, &"axe", 0).sounds(&"step_wood").in_category(&"plant") \
		.tag(&"fungus").tag(&"organic").tag(&"biome_forest").flags({"flammable": true})
	reg.define(&"mushroom_cap", "Mushroom Cap").look(Color(0.74, 0.24, 0.22), BlockType.Pattern.ORGANIC, Color(0.90, 0.88, 0.80)) \
		.mining(0.5, &"axe", 0).sounds(&"step_wood").drop(&"mushroom_red", 1, 2) \
		.in_category(&"plant").tag(&"fungus").tag(&"organic").tag(&"biome_forest") \
		.flags({"flammable": true})
	reg.define(&"spore_pod", "Spore Pod").look(Color(0.56, 0.66, 0.34), BlockType.Pattern.ORGANIC, Color(0.78, 0.86, 0.42)) \
		.mode(BlockType.Render.CROSS).mining(0.2, &"any", 0).sounds(&"step_leaves") \
		.glows(3, 0.5).drop(&"spore_cluster").in_category(&"plant").tag(&"fungus") \
		.tag(&"hazard").tag(&"foliage").tag(&"biome_toxic") \
		.flags({"damage_on_touch": 1.5, "damage_element": Const.ELEM_POISON})


# ------------------------------------------------------------- ocean growth
static func _aquatic(reg) -> void:
	reg.define(&"kelp", "Kelp").look(Color(0.20, 0.44, 0.30), BlockType.Pattern.ORGANIC, Color(0.14, 0.32, 0.22)) \
		.mode(BlockType.Render.CROSS).mining(0.15, &"any", 0).sounds(&"step_liquid") \
		.drop(&"kelp_frond", 1, 2).in_category(&"plant").tag(&"vine").tag(&"climbable") \
		.tag(&"foliage").tag(&"biome_ocean").flags({"climbable": true})
	reg.define(&"coral", "Pink Coral").look(Color(0.94, 0.46, 0.62), BlockType.Pattern.CRYSTAL, Color(0.78, 0.32, 0.48)) \
		.mining(0.8, &"pickaxe", 0).sounds(&"step_stone").in_category(&"plant") \
		.tag(&"coral").tag(&"organic").tag(&"biome_ocean").flags({"opaque": false})
	reg.define(&"coral_blue", "Blue Coral").look(Color(0.30, 0.58, 0.92), BlockType.Pattern.CRYSTAL, Color(0.20, 0.42, 0.74)) \
		.mining(0.8, &"pickaxe", 0).sounds(&"step_stone").in_category(&"plant") \
		.tag(&"coral").tag(&"organic").tag(&"biome_ocean").flags({"opaque": false})
	reg.define(&"coral_glow", "Glowcoral").look(Color(0.36, 0.90, 0.80), BlockType.Pattern.CRYSTAL, Color(0.22, 0.66, 0.60)) \
		.mining(0.9, &"pickaxe", 0).sounds(&"step_stone").glows(9, 1.0) \
		.in_category(&"plant").tag(&"coral").tag(&"light_source").tag(&"biome_ocean") \
		.flags({"opaque": false})
	PsBlocks.foliage(reg, &"sea_anemone", "Sea Anemone", Color(0.88, 0.40, 0.30),
		Color(0.62, 0.24, 0.20), &"biome_ocean", &"coral") \
		.sounds(&"step_liquid").flags({"flammable": false})


# ----------------------------------------------------------- alien / fleshy
static func _alien(reg) -> void:
	reg.define(&"flesh_block", "Fleshy Growth").look(Color(0.72, 0.28, 0.34), BlockType.Pattern.ORGANIC, Color(0.54, 0.18, 0.24)) \
		.mining(0.9, &"axe", 0).sounds(&"step_dirt").drop(&"raw_flesh", 1, 2) \
		.in_category(&"plant").tag(&"flesh").tag(&"organic").tag(&"biome_alien") \
		.flags({"flammable": true, "friction": 0.8})
	reg.define(&"sinew_block", "Sinew").look(Color(0.84, 0.62, 0.56), BlockType.Pattern.ORGANIC, Color(0.66, 0.44, 0.40)) \
		.mining(1.1, &"axe", 0).sounds(&"step_dirt").drop(&"sinew_strand", 1, 2) \
		.in_category(&"plant").tag(&"flesh").tag(&"organic").tag(&"biome_alien") \
		.flags({"bounce": 0.35})
	reg.define(&"flesh_tendril", "Flesh Tendril").look(Color(0.78, 0.34, 0.42), BlockType.Pattern.ORGANIC, Color(0.56, 0.20, 0.28)) \
		.mode(BlockType.Render.CROSS).mining(0.25, &"any", 0).sounds(&"step_dirt") \
		.drop(&"raw_flesh").in_category(&"plant").tag(&"flesh").tag(&"climbable") \
		.tag(&"foliage").tag(&"biome_alien").flags({"climbable": true})
	reg.define(&"alien_pod", "Alien Pod").look(Color(0.46, 0.26, 0.62), BlockType.Pattern.ORGANIC, Color(0.80, 0.44, 0.92)) \
		.mining(0.7, &"any", 0).sounds(&"step_dirt").glows(4, 0.7) \
		.drop(&"alien_seed", 1, 2).in_category(&"plant").tag(&"organic") \
		.tag(&"biome_alien").flags({"opaque": false})
	PsBlocks.foliage(reg, &"alien_flower", "Alien Bloom", Color(0.86, 0.32, 0.94),
		Color(0.44, 0.24, 0.56), &"biome_alien", &"flower") \
		.glows(4, 0.7).tag(&"light_source")
	reg.define(&"slime_growth", "Slime Growth").look(Color(0.44, 0.86, 0.46, 0.85), BlockType.Pattern.ORGANIC, Color(0.30, 0.66, 0.32)) \
		.mode(BlockType.Render.TRANSPARENT).mining(0.4, &"any", 0).sounds(&"step_dirt") \
		.drop(&"slime_glob", 1, 2).in_category(&"plant").tag(&"organic").tag(&"sticky") \
		.tag(&"biome_toxic").flags({"solid": true, "friction": 0.4, "bounce": 0.55})
