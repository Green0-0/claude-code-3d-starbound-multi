## Bootstrap block set **and** the shared vocabulary every other content agent
## keys off. Owned by the block-content agent, which extends it with the
## further `res://content/blocks/NN_*.gd` files (loaded in filename order).
##
## Every block registered here must keep its StringName: other modules key off
## these names.
##
## ---------------------------------------------------------------------------
## CATEGORY vocabulary (`.in_category`) — one per block, drives crafting-menu
## and inventory grouping:
##   natural   terrain fill: stone, soil, sand, ice, gravel
##   ore       ore-bearing rock; always drops a `raw_*` material
##   plant     logs, leaves, foliage, fungus, coral, fleshy growths
##   building  crafted construction blocks, glass, platforms, ladders, trim
##   light     light sources
##   liquid    everything with `Render.LIQUID`
##   hazard    blocks that damage, poison, burn or otherwise punish contact
##   dungeon   themed structure sets (see `theme_*` tags)
##   special   bedrock, markers, spawners, and the perspective mechanics
##
## TAG vocabulary (`.tag`) — a block may carry several:
##
##   material : stone soil sand snow ice wood leaves metal glass crystal
##              organic flesh fungus cloth brick ash liquid
##   function : ore gem fuel falls platform ladder climbable slippery sticky
##              hazard radioactive unbreakable marker spawner teleporter
##              quest_locked decor trim door_frame light_source perspective
##   role     : wall floor accent locked            (dungeon set members)
##   biome    : biome_forest biome_desert biome_tundra biome_jungle
##              biome_savannah biome_alien biome_toxic biome_magma
##              biome_ocean biome_moon biome_barren
##   stratum  : stratum_surface stratum_upper stratum_mid stratum_deep
##              stratum_core                     (worldgen depth banding)
##   worldgen : terrain_fill surface_cover cave_decor tree_log tree_leaves
##              sapling vine grass_tuft flower mushroom coral
##   theme    : theme_apex theme_avian theme_floran theme_glitch theme_hylotl
##              theme_human theme_ancient
##
## TOOL TIER ladder (`.mining(hardness, tool, tier)`):
##   0 stone/copper · 1 iron · 2 tungsten/titanium · 3 durasteel
##   4 aegisalt/ferozium/violium · 5 rubium/solarium · 6 core-forged · 99 never
##
## STEP SOUND vocabulary (synthesised by the audio agent):
##   step_stone step_dirt step_grass step_sand step_snow step_wood
##   step_metal step_glass step_leaves step_liquid
class_name PsBlocks
extends RefCounted

## Canonical category list, for UI code that wants to enumerate them.
const CATEGORIES := [
	&"natural", &"ore", &"plant", &"building", &"light",
	&"liquid", &"hazard", &"dungeon", &"special",
]

## Canonical dungeon theme tags, in the order the structure agent should
## unlock them.
const THEMES := [
	&"theme_human", &"theme_apex", &"theme_avian", &"theme_floran",
	&"theme_glitch", &"theme_hylotl", &"theme_ancient",
]

## Every step/break/place sound name used anywhere in the block library.
const STEP_SOUNDS := [
	&"step_stone", &"step_dirt", &"step_grass", &"step_sand", &"step_snow",
	&"step_wood", &"step_metal", &"step_glass", &"step_leaves", &"step_liquid",
]


static func register_all(reg) -> void:
	reg.define(&"stone", "Stone").look(Color(0.48, 0.48, 0.52), BlockType.Pattern.NOISE) \
		.mining(1.5, &"pickaxe", 0).drop(&"cobblestone").in_category(&"natural").tag(&"stone")
	reg.define(&"cobblestone", "Cobblestone").look(Color(0.42, 0.42, 0.45), BlockType.Pattern.SPECKLE) \
		.mining(1.6, &"pickaxe", 0).in_category(&"building")
	reg.define(&"dirt", "Dirt").look(Color(0.42, 0.29, 0.18), BlockType.Pattern.NOISE) \
		.mining(0.5, &"shovel").in_category(&"natural").tag(&"soil")
	reg.define(&"grass", "Grassy Dirt").look(Color(0.42, 0.29, 0.18), BlockType.Pattern.GRASS_TOP) \
		.with_top(Color(0.35, 0.62, 0.26)).mining(0.6, &"shovel").drop(&"dirt") \
		.in_category(&"natural").tag(&"soil")
	reg.define(&"sand", "Sand").look(Color(0.85, 0.79, 0.55), BlockType.Pattern.SAND) \
		.mining(0.4, &"shovel").in_category(&"natural").flags({"falls": true})
	reg.define(&"bedrock", "Core Fragment").look(Color(0.12, 0.12, 0.16), BlockType.Pattern.STRATA) \
		.mining(999.0, &"pickaxe", 99).flags({"breakable": false, "blast_resistance": 9999.0})
	reg.define(&"water", "Water").look(Color(0.18, 0.42, 0.85, 0.62), BlockType.Pattern.FLAT) \
		.mode(BlockType.Render.LIQUID).in_category(&"liquid")
	reg.define(&"lava", "Lava").look(Color(0.95, 0.42, 0.1, 0.9), BlockType.Pattern.FLAT) \
		.mode(BlockType.Render.LIQUID).glows(14, 1.0).in_category(&"liquid") \
		.flags({"damage_on_touch": 18.0, "damage_element": Const.ELEM_FIRE})

	# The core eight carry the shared vocabulary too, so `all_with_tag` queries
	# written against the tables above never miss them.
	_retag(reg, &"stone", [&"terrain_fill", &"stratum_upper"], &"step_stone")
	_retag(reg, &"cobblestone", [&"stone"], &"step_stone")
	_retag(reg, &"dirt", [&"terrain_fill", &"stratum_surface"], &"step_dirt")
	_retag(reg, &"grass", [&"surface_cover", &"biome_forest"], &"step_grass")
	_retag(reg, &"sand", [&"sand", &"falls", &"terrain_fill", &"biome_desert"], &"step_sand")
	_retag(reg, &"bedrock", [&"unbreakable", &"marker"], &"step_stone")
	_retag(reg, &"water", [&"liquid"], &"step_liquid")
	_retag(reg, &"lava", [&"liquid", &"hazard"], &"step_liquid")


static func _retag(reg, p_name: StringName, extra: Array, step: StringName) -> void:
	var bt: BlockType = reg.get_by_name(p_name)
	if bt == null:
		return
	for t: StringName in extra:
		bt.tag(t)
	bt.sounds(step)


# ===========================================================================
#  Shared builders. Used by 10_*..18_* so the content files stay readable and
#  every family of blocks gets a consistent stat shape.
# ===========================================================================

## An ore-bearing rock: host `base` colour speckled with `metal`, mined with a
## pickaxe of at least `tier`, dropping `drop_item`.
static func ore(reg, p_name: StringName, display: String, base: Color, metal: Color,
		hardness: float, tier: int, drop_item: StringName,
		lo: int = 1, hi: int = 1, light: int = 0, emission: float = 0.0) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(base, BlockType.Pattern.ORE, metal)
	bt.mining(hardness, &"pickaxe", tier)
	bt.drop(drop_item, lo, hi)
	bt.sounds(&"step_stone")
	bt.in_category(&"ore").tag(&"ore").tag(&"stone")
	if light > 0:
		bt.glows(light, emission)
	return bt


## A plain terrain rock. Drops itself unless `drop_item` is given.
static func rock(reg, p_name: StringName, display: String, col: Color, alt: Color,
		pat: BlockType.Pattern, hardness: float, tier: int = 0,
		drop_item: StringName = &"") -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, pat, alt)
	bt.mining(hardness, &"pickaxe", tier)
	bt.sounds(&"step_stone")
	bt.in_category(&"natural").tag(&"stone").tag(&"terrain_fill")
	if drop_item != &"":
		bt.drop(drop_item)
	return bt


## Log + leaves + planks + sapling for one tree species.
## `biome` is the biome tag stamped on the natural (non-plank) members.
static func tree_set(reg, base: StringName, display: String, log_col: Color, log_alt: Color,
		leaf_col: Color, plank_col: Color, biome: StringName,
		hardness: float = 1.2, leaf_alpha: float = 0.92) -> void:
	var lg: BlockType = reg.define(StringName(String(base) + "_log"), display + " Log")
	lg.look(log_col, BlockType.Pattern.LOG, log_alt)
	lg.with_top(log_alt.lightened(0.15))
	lg.mining(hardness, &"axe", 0)
	lg.sounds(&"step_wood")
	lg.flags({"flammable": true})
	lg.in_category(&"plant").tag(&"wood").tag(&"tree_log").tag(biome)

	var lv: BlockType = reg.define(StringName(String(base) + "_leaves"), display + " Leaves")
	lv.look(Color(leaf_col.r, leaf_col.g, leaf_col.b, leaf_alpha), BlockType.Pattern.LEAF, leaf_col.darkened(0.3))
	lv.mode(BlockType.Render.TRANSPARENT)
	lv.mining(0.25, &"any", 0)
	lv.sounds(&"step_leaves")
	lv.flags({"flammable": true})
	lv.drop(StringName(String(base) + "_sapling"), 1, 1, 0.08)
	lv.drop(&"plant_fibre", 1, 2, 0.35)
	lv.in_category(&"plant").tag(&"leaves").tag(&"tree_leaves").tag(biome)

	var pl: BlockType = reg.define(StringName(String(base) + "_planks"), display + " Planks")
	pl.look(plank_col, BlockType.Pattern.PLANK, plank_col.darkened(0.22))
	pl.mining(1.1, &"axe", 0)
	pl.sounds(&"step_wood")
	pl.flags({"flammable": true, "friction": 1.0})
	pl.in_category(&"building").tag(&"wood")

	var sp: BlockType = reg.define(StringName(String(base) + "_sapling"), display + " Sapling")
	sp.look(leaf_col.lightened(0.1), BlockType.Pattern.ORGANIC, log_col)
	sp.mode(BlockType.Render.CROSS)
	sp.mining(0.05, &"any", 0)
	sp.sounds(&"step_leaves")
	sp.flags({"flammable": true, "replaceable": false})
	sp.in_category(&"plant").tag(&"sapling").tag(&"foliage").tag(biome)


## One member of a dungeon theme set. `role` is wall / floor / accent / locked.
static func themed(reg, p_name: StringName, display: String, col: Color, alt: Color,
		pat: BlockType.Pattern, hardness: float, tier: int, theme: StringName,
		role: StringName, step: StringName = &"step_stone") -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, pat, alt)
	bt.mining(hardness, &"pickaxe", tier)
	bt.sounds(step)
	bt.in_category(&"dungeon").tag(theme).tag(role)
	if role == &"locked":
		bt.flags({"breakable": false, "blast_resistance": 9999.0})
		bt.tag(&"unbreakable")
	return bt


## A cross-quad plant (tuft, flower, fungus). Never solid, never opaque.
static func foliage(reg, p_name: StringName, display: String, col: Color, alt: Color,
		biome: StringName, role: StringName, drop_item: StringName = &"") -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, BlockType.Pattern.ORGANIC, alt)
	bt.mode(BlockType.Render.CROSS)
	bt.mining(0.05, &"any", 0)
	bt.sounds(&"step_grass")
	bt.flags({"flammable": true})
	bt.in_category(&"plant").tag(role).tag(&"organic").tag(&"foliage")
	if biome != &"":
		bt.tag(biome)
	if drop_item != &"":
		bt.drop(drop_item)
	return bt
