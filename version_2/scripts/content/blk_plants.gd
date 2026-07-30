extends RefCounted

## Everything that grows.
##
## Four tree species beyond the generic oak set that ships in the frozen ids,
## each registered as a matched quartet — `<species>_log`, `<species>_leaves`,
## `<species>_planks`, `<species>_sapling` — so the decorator can pick a species
## per biome with `Blocks.all_with_tag(&"tree_log")` filtered by biome, and the
## recipe book can turn any log into its planks with one mechanical rule.
##
## Undergrowth is `Render.CROSS`: two quads crossed at 90°, which is the same
## silhouette from all four camera facings. That matters here more than in a
## normal voxel game, because the camera is rotated constantly — a single quad
## would turn a meadow into a field of invisible edges on every turn.


static func tree_set(base: StringName, display: String, log_col: Color, log_alt: Color,
		leaf_col: Color, plank_col: Color, biome: StringName, hard := 0.6) -> void:
	Blocks.define(StringName(String(base) + "_log"), display + " Log") \
		.look(log_col, Blocks.Pattern.LOG, log_alt) \
		.with_top(log_alt.lightened(0.15)).mining(hard, &"axe", 0) \
		.sounds(&"step_wood").drop(StringName(String(base) + "_log")) \
		.in_category(&"plant").tag(&"wood").tag(&"tree_log").tag(biome) \
		.flags({"flammable": true})

	Blocks.define(StringName(String(base) + "_leaves"), display + " Leaves") \
		.look(leaf_col, Blocks.Pattern.LEAF, leaf_col.darkened(0.3)) \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true, "flammable": true}) \
		.mining(0.14, &"any", 0).sounds(&"step_leaves") \
		.drop(StringName(String(base) + "_sapling"), 1, 1, 0.08) \
		.drop(&"plant_fibre", 1, 2, 0.35) \
		.in_category(&"plant").tag(&"leaves").tag(&"tree_leaves").tag(biome)

	Blocks.define(StringName(String(base) + "_planks"), display + " Planks") \
		.look(plank_col, Blocks.Pattern.PLANK, plank_col.darkened(0.22)) \
		.mining(0.5, &"axe", 0).sounds(&"step_wood") \
		.drop(StringName(String(base) + "_planks")) \
		.in_category(&"building").tag(&"wood").flags({"flammable": true})

	Blocks.define(StringName(String(base) + "_sapling"), display + " Sapling") \
		.look(leaf_col.lightened(0.1), Blocks.Pattern.ORGANIC, log_col) \
		.mode(Blocks.Render.CROSS).mining(0.04, &"any", 0).sounds(&"step_leaves") \
		.drop(StringName(String(base) + "_sapling")) \
		.in_category(&"plant").tag(&"sapling").tag(&"foliage").tag(biome) \
		.flags({"flammable": true})


static func foliage(p_name: StringName, display: String, col: Color, alt: Color,
		biome: StringName, role: StringName, drop_item: StringName = &"") -> Blocks.Def:
	var b := Blocks.define(p_name, display)
	b.look(col, Blocks.Pattern.ORGANIC, alt).mode(Blocks.Render.CROSS) \
		.mining(0.04, &"any", 0).sounds(&"step_grass") \
		.in_category(&"plant").tag(role).tag(&"organic").tag(&"foliage") \
		.flags({"flammable": true})
	if biome != &"":
		b.tag(biome)
	if drop_item != &"":
		b.drop(drop_item)
	return b


static func register_all() -> void:
	_trees()
	_undergrowth()
	_fungus()
	_aquatic()
	_alien()


static func _trees() -> void:
	# The frozen `wood_log` / `leaves` / `wood_planks` are the oak set; it only
	# needs its sapling so the leaf drop resolves.
	Blocks.define(&"oak_sapling", "Oak Sapling") \
		.look(Color(0.38, 0.65, 0.34), Blocks.Pattern.ORGANIC, Color(0.44, 0.32, 0.20)) \
		.mode(Blocks.Render.CROSS).mining(0.04, &"any", 0).sounds(&"step_leaves") \
		.drop(&"oak_sapling").in_category(&"plant").tag(&"sapling").tag(&"foliage") \
		.tag(&"biome_forest").flags({"flammable": true})

	tree_set(&"pine", "Pine", Color(0.34, 0.25, 0.18), Color(0.24, 0.18, 0.13),
		Color(0.16, 0.40, 0.26), Color(0.72, 0.58, 0.38), &"biome_tundra")
	tree_set(&"jungle", "Jungle", Color(0.38, 0.30, 0.16), Color(0.27, 0.21, 0.11),
		Color(0.18, 0.58, 0.18), Color(0.60, 0.48, 0.24), &"biome_jungle", 0.75)
	tree_set(&"palm", "Palm", Color(0.60, 0.48, 0.30), Color(0.46, 0.37, 0.23),
		Color(0.38, 0.66, 0.28), Color(0.82, 0.68, 0.44), &"biome_desert", 0.5)
	tree_set(&"alien", "Alien", Color(0.36, 0.22, 0.44), Color(0.26, 0.15, 0.32),
		Color(0.66, 0.30, 0.86), Color(0.56, 0.38, 0.66), &"biome_alien", 0.9)



static func _undergrowth() -> void:
	foliage(&"tall_grass", "Tall Grass", Color(0.36, 0.64, 0.28), Color(0.26, 0.50, 0.20),
		&"biome_forest", &"grass_tuft", &"plant_fibre").flags({"replaceable": true})
	foliage(&"dry_grass", "Dry Grass", Color(0.72, 0.66, 0.34), Color(0.58, 0.52, 0.26),
		&"biome_savannah", &"grass_tuft", &"plant_fibre").flags({"replaceable": true})
	foliage(&"fern", "Fern", Color(0.24, 0.52, 0.28), Color(0.17, 0.38, 0.20),
		&"biome_jungle", &"grass_tuft", &"plant_fibre").flags({"replaceable": true})
	foliage(&"dead_bush", "Dead Bush", Color(0.50, 0.38, 0.22), Color(0.38, 0.28, 0.16),
		&"biome_desert", &"grass_tuft", &"plant_fibre").flags({"replaceable": true})

	foliage(&"flower_red", "Red Bloom", Color(0.88, 0.24, 0.26), Color(0.30, 0.54, 0.24),
		&"biome_forest", &"flower", &"flower_red")
	foliage(&"flower_yellow", "Sunbud", Color(0.96, 0.84, 0.28), Color(0.30, 0.54, 0.24),
		&"biome_savannah", &"flower", &"flower_yellow")
	foliage(&"flower_blue", "Bluebell", Color(0.36, 0.48, 0.94), Color(0.30, 0.54, 0.24),
		&"biome_tundra", &"flower", &"flower_blue")
	foliage(&"glow_flower", "Lumibloom", Color(0.60, 0.92, 1.00), Color(0.26, 0.46, 0.54),
		&"biome_alien", &"flower", &"glow_sap").glows(6, 0.9).tag(&"light_source")

	# Climbable growth. CROSS already cleared `collide`, so `climbable` alone
	# gives the ladder behaviour the player controller looks for.
	Blocks.define(&"vine", "Vine") \
		.look(Color(0.26, 0.50, 0.24), Blocks.Pattern.ORGANIC, Color(0.19, 0.37, 0.18)) \
		.mode(Blocks.Render.CROSS).mining(0.08, &"any", 0).sounds(&"step_leaves") \
		.drop(&"plant_fibre", 1, 2).in_category(&"plant").tag(&"vine") \
		.tag(&"climbable").tag(&"foliage").tag(&"biome_jungle") \
		.flags({"climbable": true, "flammable": true})
	Blocks.define(&"glow_vine", "Glow Vine") \
		.look(Color(0.34, 0.78, 0.62), Blocks.Pattern.ORGANIC, Color(0.20, 0.52, 0.44)) \
		.mode(Blocks.Render.CROSS).mining(0.08, &"any", 0).sounds(&"step_leaves") \
		.glows(7, 0.9).drop(&"glow_sap", 1, 2).in_category(&"plant").tag(&"vine") \
		.tag(&"climbable").tag(&"light_source").tag(&"foliage").tag(&"biome_alien") \
		.flags({"climbable": true})

	Blocks.define(&"cactus", "Cactus") \
		.look(Color(0.24, 0.52, 0.28), Blocks.Pattern.ORGANIC, Color(0.18, 0.40, 0.21)) \
		.mining(0.25, &"any", 0).sounds(&"step_grass").drop(&"cactus_pulp", 1, 2) \
		.in_category(&"plant").tag(&"organic").tag(&"hazard").tag(&"biome_desert") \
		.flags({"opaque": false, "damage_on_touch": 3.0})


static func _fungus() -> void:
	foliage(&"mushroom_brown", "Brown Mushroom", Color(0.60, 0.44, 0.30),
		Color(0.82, 0.76, 0.66), &"biome_forest", &"mushroom", &"mushroom_brown") \
		.tag(&"fungus")
	foliage(&"mushroom_red", "Red Mushroom", Color(0.82, 0.20, 0.18),
		Color(0.92, 0.90, 0.84), &"biome_forest", &"mushroom", &"mushroom_red") \
		.tag(&"fungus")
	foliage(&"glow_mushroom", "Azure Cap", Color(0.52, 0.72, 1.00),
		Color(0.30, 0.44, 0.70), &"biome_alien", &"mushroom", &"mushroom_blue") \
		.tag(&"fungus").glows(7, 1.0).tag(&"light_source")


static func _aquatic() -> void:
	Blocks.define(&"kelp", "Kelp") \
		.look(Color(0.20, 0.44, 0.30), Blocks.Pattern.ORGANIC, Color(0.14, 0.32, 0.22)) \
		.mode(Blocks.Render.CROSS).mining(0.08, &"any", 0).sounds(&"step_liquid") \
		.drop(&"kelp_frond", 1, 2).in_category(&"plant").tag(&"vine") \
		.tag(&"climbable").tag(&"foliage").tag(&"biome_ocean").flags({"climbable": true})
	Blocks.define(&"coral_glow", "Glowcoral") \
		.look(Color(0.36, 0.90, 0.80), Blocks.Pattern.CRYSTAL, Color(0.22, 0.66, 0.60)) \
		.mining(0.45, &"pickaxe", 0).sounds(&"step_stone").glows(9, 1.0) \
		.drop(&"coral_glow").in_category(&"plant").tag(&"coral") \
		.tag(&"light_source").tag(&"biome_ocean")


static func _alien() -> void:
	Blocks.define(&"flesh_block", "Fleshy Growth") \
		.look(Color(0.72, 0.28, 0.34), Blocks.Pattern.ORGANIC, Color(0.54, 0.18, 0.24)) \
		.mining(0.45, &"axe", 0).sounds(&"step_dirt").drop(&"raw_flesh", 1, 2) \
		.in_category(&"plant").tag(&"flesh").tag(&"organic").tag(&"biome_alien") \
		.flags({"flammable": true, "friction": 0.8})
	Blocks.define(&"slime_growth", "Slime Growth") \
		.look(Color(0.44, 0.86, 0.46, 0.85), Blocks.Pattern.ORGANIC, Color(0.30, 0.66, 0.32)) \
		.mode(Blocks.Render.TRANSPARENT).mining(0.2, &"any", 0).sounds(&"step_dirt") \
		.drop(&"slime_glob", 1, 2).in_category(&"plant").tag(&"organic").tag(&"sticky") \
		.tag(&"biome_toxic").flags({"solid": true, "friction": 0.4, "bounce": 0.55})
