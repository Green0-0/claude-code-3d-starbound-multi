class_name Blocks
extends RefCounted

## The block registry.
##
## Everything in the world is one of these ids, and the id is stored in a single
## byte per voxel — so the registry is hard-capped at 256 entries and asserts if
## a content file overruns it. Ids 0..26 are frozen: they are the set the
## renderer, the spawn carver and the starter hotbar were written against, and
## their hand-painted atlas tiles are the visual signature of the game.
##
## Everything after that is defined by the `content/blk_*.gd` files with the
## fluent builder below, and gets its atlas tile synthesised from
## `(pattern, colour, alt colour)` at boot.
##
## The four accessors the chunk mesher calls per face — `tile_of`, `is_opaque`,
## `emission` — resolve through flat packed arrays rather than the Def objects,
## because they are the hottest code in the project.

# =============================================================================
# vocabulary
# =============================================================================

## How a block is turned into geometry.
enum Render {
	CUBE,         ## full opaque cube, occludes its neighbours
	TRANSPARENT,  ## full cube in the alpha pass (glass, ice, bars)
	CROSS,        ## two crossed quads (foliage, crops, torches)
	LIQUID,       ## full cube in the alpha pass, flows, never collides
}

## Tile patterns the atlas painter understands.
enum Pattern {
	FLAT, NOISE, SPECKLE, STRATA, BRICK, PLANK, ORE, CRYSTAL, GRASS_TOP,
	METAL, CIRCUIT, ORGANIC, CLOTH, GLASS, SAND, ICE, LEAF, LOG,
}

## Damage elements, shared with the combat pipeline.
const ELEM_PHYSICAL := &"physical"
const ELEM_FIRE := &"fire"
const ELEM_ICE := &"ice"
const ELEM_ELECTRIC := &"electric"
const ELEM_POISON := &"poison"
const ELEM_COSMIC := &"cosmic"

## Tool tier ladder: 0 stone/copper, 1 iron, 2 tungsten, 3 titanium,
## 4 durasteel, 5 aegisalt-class, 6 solarium-class, 99 never.
const MAX_BLOCKS := 256

# =============================================================================
# frozen ids — do not renumber
# =============================================================================

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4
const SAND := 5
const LOG := 6
const LEAVES := 7
const PLANKS := 8
const GLASS := 9
const LAMP := 10
const COAL_ORE := 11
const IRON_ORE := 12
const CRYSTAL_ORE := 13
const SNOW := 14
const BRICK := 15
const BEDROCK := 16
const MOSSY := 17
const CRYSTAL := 18
const DARK_PLANKS := 19
const ROOF := 20
const STONE_BRICK := 21
const ICE := 22
const GRAVEL := 23
const CLAY := 24
const OBSIDIAN := 25
const MUD := 26

const COUNT := 27   ## frozen-id count; the registry grows well past this

# Hand-painted atlas slots for the frozen set.
const T_GRASS_TOP := 0
const T_GRASS_SIDE := 1
const T_DIRT := 2
const T_STONE := 3
const T_COBBLE := 4
const T_SAND := 5
const T_LOG_SIDE := 6
const T_LOG_TOP := 7
const T_LEAVES := 8
const T_PLANKS := 9
const T_GLASS := 10
const T_LAMP := 11
const T_COAL := 12
const T_IRON := 13
const T_CRYSTAL_ORE := 14
const T_SNOW := 15
const T_BRICK := 16
const T_BEDROCK := 17
const T_MOSSY := 18
const T_CRYSTAL := 19
const T_DARK_PLANKS := 20
const T_ROOF := 21
const T_STONE_BRICK := 22
const T_ICE := 23
const T_GRAVEL := 24
const T_CLAY := 25
const T_OBSIDIAN := 26
const T_MUD := 27

## Number of hand-painted tiles; synthesised tiles are allocated from here up.
const LEGACY_TILES := 28


# =============================================================================
# one block type
# =============================================================================

class Def extends RefCounted:
	var id := 0
	var name: StringName = &""
	var display := ""
	var description := ""

	var render: int = Blocks.Render.CUBE
	var pattern: int = Blocks.Pattern.NOISE
	var color := Color(0.5, 0.5, 0.5)
	var color_alt := Color(0.4, 0.4, 0.4)
	var top_color := Color(0, 0, 0, 0)   ## alpha 0 means "no distinct top face"

	var opaque := true
	var collide := true
	var replaceable := false
	var climbable := false
	var platform := false
	var falls := false
	var flammable := false
	var breakable := true

	var light := 0                        ## 0..15, feeds the block-light sim
	var emission := 0.0                   ## 0..1, feeds the shader
	var hardness := 1.0                   ## seconds at tool power 1.0
	var tool: StringName = &"any"
	var tier := 0
	var friction := 1.0
	var bounce := 0.0
	var blast := 1.0
	var touch_damage := 0.0
	var touch_element: StringName = Blocks.ELEM_PHYSICAL

	var drops: Array = []                 ## [[item_id, lo, hi, chance], ...]
	var category: StringName = &"natural"
	var tags := {}
	var item: StringName = &""            ## placer item; defaults to `name`
	var step: StringName = &"step_stone"

	var tiles := PackedInt32Array([0, 0, 0])   ## top, side, bottom

	# --- fluent builders -----------------------------------------------------

	func look(c: Color, pat: int, alt := Color(0, 0, 0, 0)) -> Def:
		color = c
		pattern = pat
		color_alt = alt if alt.a > 0.0 else c.darkened(0.24)
		return self

	func with_top(c: Color) -> Def:
		top_color = c
		return self

	func mode(r: int) -> Def:
		render = r
		match r:
			Blocks.Render.TRANSPARENT:
				opaque = false
			Blocks.Render.CROSS:
				opaque = false
				collide = false
			Blocks.Render.LIQUID:
				opaque = false
				collide = false
		return self

	func mining(h: float, t: StringName = &"any", tr := 0) -> Def:
		hardness = h
		tool = t
		tier = tr
		return self

	func glows(level: int, emis := 1.0) -> Def:
		light = level
		emission = emis
		return self

	func drop(item_id: StringName, lo := 1, hi := 1, chance := 1.0) -> Def:
		drops.append([item_id, lo, hi, chance])
		return self

	func sounds(s: StringName) -> Def:
		step = s
		return self

	func places(item_id: StringName) -> Def:
		item = item_id
		return self

	func describe(text: String) -> Def:
		description = text
		return self

	func in_category(c: StringName) -> Def:
		category = c
		return self

	func tag(t: StringName) -> Def:
		tags[t] = true
		return self

	func has_tag(t: StringName) -> bool:
		return tags.has(t)

	## Bulk-set the scalar flags. Accepts every key the v1 content files used.
	func flags(d: Dictionary) -> Def:
		for k: String in d:
			match k:
				"solid": collide = bool(d[k])
				"opaque": opaque = bool(d[k])
				"replaceable": replaceable = bool(d[k])
				"climbable": climbable = bool(d[k])
				"platform": platform = bool(d[k])
				"falls": falls = bool(d[k])
				"flammable": flammable = bool(d[k])
				"breakable": breakable = bool(d[k])
				"friction": friction = float(d[k])
				"bounce": bounce = float(d[k])
				"blast_resistance": blast = float(d[k])
				"hardness": hardness = float(d[k])
				"damage_on_touch": touch_damage = float(d[k])
				"damage_element": touch_element = StringName(d[k])
				_: push_warning("Blocks: unknown flag '%s' on %s" % [k, name])
		return self

	## Roll this block's drops for a tool of `tier`. Returns [[item, count], ...].
	func roll_drops(tool_tier: int, rng: RandomNumberGenerator) -> Array:
		var out: Array = []
		if tool_tier < tier:
			return out
		for d: Array in drops:
			if rng.randf() > float(d[3]):
				continue
			var n := rng.randi_range(int(d[1]), int(d[2]))
			if n > 0:
				out.append([d[0], n])
		return out


# =============================================================================
# registry
# =============================================================================

static var defs: Array[Def] = []
static var by_name := {}
## Tile requests for TexGen: index -> {pattern, color, alt}. Index 0..27 are the
## hand-painted legacy tiles and are absent from this dictionary.
static var tile_specs := {}

static var _booted := false

# hot lookup tables, rebuilt by _bake()
static var _tiles := PackedInt32Array()
static var _opaque := PackedByteArray()
static var _collide := PackedByteArray()
static var _emis := PackedFloat32Array()
static var _hard := PackedFloat32Array()
static var _light := PackedByteArray()
static var _render := PackedByteArray()
static var _liquid := PackedByteArray()
static var _climb := PackedByteArray()
static var _platform := PackedByteArray()
static var _replace := PackedByteArray()
static var _fric := PackedFloat32Array()
static var _touch := PackedFloat32Array()
static var _legacy_drop := PackedInt32Array()

const CONTENT := [
	"res://scripts/content/blk_stone.gd",
	"res://scripts/content/blk_ores.gd",
	"res://scripts/content/blk_soil.gd",
	"res://scripts/content/blk_plants.gd",
	"res://scripts/content/blk_building.gd",
	"res://scripts/content/blk_hazard.gd",
	"res://scripts/content/blk_light.gd",
	"res://scripts/content/blk_dungeon.gd",
	"res://scripts/content/blk_crops.gd",
]


## Build the registry. Safe to call more than once; only the first call works.
static func boot() -> void:
	if _booted:
		return
	_booted = true
	defs.clear()
	by_name.clear()
	tile_specs.clear()
	_define_frozen()
	for path: String in CONTENT:
		var script: GDScript = load(path)
		script.register_all()
	_bake()


## Register a new block. Returns the Def so it can be built up fluently.
static func define(p_name: StringName, display: String) -> Def:
	if by_name.has(p_name):
		return by_name[p_name]
	assert(defs.size() < MAX_BLOCKS,
		"Block registry full (%d): voxel storage is one byte per cell." % MAX_BLOCKS)
	var d := Def.new()
	d.id = defs.size()
	d.name = p_name
	d.display = display
	defs.append(d)
	by_name[p_name] = d
	return d


static func has(p_name: StringName) -> bool:
	return by_name.has(p_name)


static func id(p_name: StringName) -> int:
	var d: Def = by_name.get(p_name)
	return d.id if d != null else AIR


static func get_by_name(p_name: StringName) -> Def:
	return by_name.get(p_name)


static func get_def(block_id: int) -> Def:
	if block_id < 0 or block_id >= defs.size():
		return defs[0]
	return defs[block_id]


static func count() -> int:
	return defs.size()


static func all_with_tag(t: StringName) -> Array[Def]:
	var out: Array[Def] = []
	for d: Def in defs:
		if d.tags.has(t):
			out.append(d)
	return out


static func all_in_category(c: StringName) -> Array[Def]:
	var out: Array[Def] = []
	for d: Def in defs:
		if d.category == c:
			out.append(d)
	return out


## Allocate (or reuse) an atlas tile for a pattern/colour combination.
static func alloc_tile(pattern: int, color: Color, alt: Color) -> int:
	var key := "%d:%08x:%08x" % [pattern, color.to_rgba32(), alt.to_rgba32()]
	var found: Variant = tile_specs.get(key)
	if found != null:
		return int(found["index"])
	var index := LEGACY_TILES + tile_specs.size()
	tile_specs[key] = {"index": index, "pattern": pattern, "color": color, "alt": alt}
	return index


## Every synthesised tile, ordered by atlas index. TexGen paints these.
static func synth_tiles() -> Array:
	var out: Array = tile_specs.values()
	out.sort_custom(func(a, b): return int(a["index"]) < int(b["index"]))
	return out


# =============================================================================
# hot accessors — the mesher's inner loop
# =============================================================================

## Face ids: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z.
static func tile_of(block_id: int, face: int) -> int:
	if face == 2:
		return _tiles[block_id * 3]
	if face == 3:
		return _tiles[block_id * 3 + 2]
	return _tiles[block_id * 3 + 1]


static func is_opaque(block_id: int) -> bool:
	return _opaque[block_id] == 1


## Does this block stop a moving entity? Air, foliage and liquids do not.
static func is_solid(block_id: int) -> bool:
	return _collide[block_id] == 1


static func emission(block_id: int) -> float:
	return _emis[block_id]


static func hardness(block_id: int) -> float:
	return _hard[block_id]


static func light_of(block_id: int) -> int:
	return _light[block_id]


static func render_of(block_id: int) -> int:
	return _render[block_id]


static func is_liquid(block_id: int) -> bool:
	return _liquid[block_id] == 1


static func is_climbable(block_id: int) -> bool:
	return _climb[block_id] == 1


static func is_platform(block_id: int) -> bool:
	return _platform[block_id] == 1


static func is_replaceable(block_id: int) -> bool:
	return _replace[block_id] == 1


static func friction_of(block_id: int) -> float:
	return _fric[block_id]


static func touch_damage(block_id: int) -> float:
	return _touch[block_id]


## Legacy single-block drop, kept because the frozen tables are written in it.
static func drop_of(block_id: int) -> int:
	return _legacy_drop[block_id]


static func display_name(block_id: int) -> String:
	return defs[block_id].display if block_id < defs.size() else "Air"


## The item a mined block yields when it has no explicit drop list.
static func item_of(block_id: int) -> StringName:
	var d := get_def(block_id)
	return d.item if d.item != &"" else d.name


static func _bake() -> void:
	var n := defs.size()
	_tiles.resize(n * 3)
	_opaque.resize(n)
	_collide.resize(n)
	_emis.resize(n)
	_hard.resize(n)
	_light.resize(n)
	_render.resize(n)
	_liquid.resize(n)
	_climb.resize(n)
	_platform.resize(n)
	_replace.resize(n)
	_fric.resize(n)
	_touch.resize(n)
	_legacy_drop.resize(n)
	for i in n:
		var d: Def = defs[i]
		# Blocks past the frozen set get their tiles synthesised now.
		if i >= COUNT:
			var side := alloc_tile(d.pattern, d.color, d.color_alt)
			var top := side
			if d.top_color.a > 0.0:
				top = alloc_tile(
					Pattern.NOISE if d.pattern == Pattern.GRASS_TOP else d.pattern,
					d.top_color, d.top_color.darkened(0.22))
			d.tiles = PackedInt32Array([top, side, side])
		_tiles[i * 3] = d.tiles[0]
		_tiles[i * 3 + 1] = d.tiles[1]
		_tiles[i * 3 + 2] = d.tiles[2]
		_opaque[i] = 1 if (d.opaque and i != AIR) else 0
		_collide[i] = 1 if (d.collide and i != AIR) else 0
		_emis[i] = d.emission
		_hard[i] = d.hardness
		_light[i] = d.light
		_render[i] = d.render
		_liquid[i] = 1 if d.render == Render.LIQUID else 0
		_climb[i] = 1 if d.climbable else 0
		_platform[i] = 1 if d.platform else 0
		_replace[i] = 1 if (d.replaceable or i == AIR) else 0
		_fric[i] = d.friction
		_touch[i] = d.touch_damage
		_legacy_drop[i] = i
	# The frozen set's block-for-block drops, as the original table had them.
	_legacy_drop[GRASS] = DIRT
	_legacy_drop[STONE] = COBBLE
	_legacy_drop[BEDROCK] = AIR


# =============================================================================
# the frozen set
# =============================================================================

static func _frozen(p_name: StringName, display: String, top: int, side: int,
		bottom: int, opaque: bool, emis: float, hard: float) -> Def:
	var d := define(p_name, display)
	d.tiles = PackedInt32Array([top, side, bottom])
	d.opaque = opaque
	d.emission = emis
	d.hardness = hard
	d.light = int(round(emis * 15.0))
	if not opaque and p_name != &"air":
		d.render = Render.TRANSPARENT
	return d


static func _define_frozen() -> void:
	_frozen(&"air", "Air", 0, 0, 0, false, 0.0, 0.0) \
		.flags({"replaceable": true, "solid": false})
	defs[AIR].render = Render.CUBE   # air is never meshed; keep the LUT boring

	_frozen(&"grass", "Grass", T_GRASS_TOP, T_GRASS_SIDE, T_DIRT, true, 0.0, 0.35) \
		.mining(0.35, &"shovel").drop(&"dirt").sounds(&"step_grass") \
		.in_category(&"natural").tag(&"soil").tag(&"surface_cover") \
		.tag(&"biome_forest").flags({"flammable": true})
	_frozen(&"dirt", "Dirt", T_DIRT, T_DIRT, T_DIRT, true, 0.0, 0.30) \
		.mining(0.30, &"shovel").drop(&"dirt").sounds(&"step_dirt") \
		.in_category(&"natural").tag(&"soil").tag(&"terrain_fill")
	_frozen(&"stone", "Stone", T_STONE, T_STONE, T_STONE, true, 0.0, 0.75) \
		.mining(0.75, &"pickaxe").drop(&"cobblestone").sounds(&"step_stone") \
		.in_category(&"natural").tag(&"stone").tag(&"terrain_fill") \
		.tag(&"stratum_upper")
	_frozen(&"cobblestone", "Cobblestone", T_COBBLE, T_COBBLE, T_COBBLE, true, 0.0, 0.70) \
		.mining(0.70, &"pickaxe").drop(&"cobblestone").sounds(&"step_stone") \
		.in_category(&"building").tag(&"stone")
	_frozen(&"sand", "Sand", T_SAND, T_SAND, T_SAND, true, 0.0, 0.28) \
		.mining(0.28, &"shovel").drop(&"sand").sounds(&"step_sand") \
		.in_category(&"natural").tag(&"sand").tag(&"falls").tag(&"terrain_fill") \
		.tag(&"biome_desert").flags({"falls": true})
	_frozen(&"wood_log", "Log", T_LOG_TOP, T_LOG_SIDE, T_LOG_TOP, true, 0.0, 0.55) \
		.mining(0.55, &"axe").drop(&"wood_log").sounds(&"step_wood") \
		.in_category(&"plant").tag(&"wood").tag(&"tree_log").tag(&"biome_forest") \
		.flags({"flammable": true})
	_frozen(&"leaves", "Leaves", T_LEAVES, T_LEAVES, T_LEAVES, true, 0.0, 0.18) \
		.mining(0.18, &"any").drop(&"plant_fibre", 1, 2, 0.4) \
		.drop(&"oak_sapling", 1, 1, 0.08).sounds(&"step_leaves") \
		.in_category(&"plant").tag(&"leaves").tag(&"tree_leaves") \
		.flags({"flammable": true})
	_frozen(&"wood_planks", "Planks", T_PLANKS, T_PLANKS, T_PLANKS, true, 0.0, 0.45) \
		.mining(0.45, &"axe").drop(&"wood_planks").sounds(&"step_wood") \
		.in_category(&"building").tag(&"wood").flags({"flammable": true})
	_frozen(&"glass", "Glass", T_GLASS, T_GLASS, T_GLASS, false, 0.05, 0.25) \
		.mining(0.25, &"pickaxe").drop(&"glass").sounds(&"step_glass") \
		.in_category(&"building").tag(&"glass").flags({"solid": true})
	_frozen(&"lantern_block", "Lantern Block", T_LAMP, T_LAMP, T_LAMP, true, 1.0, 0.30) \
		.mining(0.30, &"any").drop(&"lantern_block").sounds(&"step_metal") \
		.in_category(&"light").tag(&"light_source").tag(&"metal")
	_frozen(&"coal_ore", "Coal Ore", T_COAL, T_COAL, T_COAL, true, 0.0, 0.90) \
		.mining(0.90, &"pickaxe", 0).drop(&"raw_coal", 1, 2).sounds(&"step_stone") \
		.in_category(&"ore").tag(&"ore").tag(&"stone").tag(&"fuel") \
		.tag(&"stratum_surface")
	_frozen(&"iron_ore", "Iron Ore", T_IRON, T_IRON, T_IRON, true, 0.0, 1.10) \
		.mining(1.10, &"pickaxe", 0).drop(&"raw_iron", 1, 2).sounds(&"step_stone") \
		.in_category(&"ore").tag(&"ore").tag(&"stone").tag(&"stratum_upper")
	_frozen(&"crystal_ore", "Crystal Ore", T_CRYSTAL_ORE, T_CRYSTAL_ORE, T_CRYSTAL_ORE,
			true, 0.30, 1.30) \
		.mining(1.30, &"pickaxe", 1).drop(&"crystal_shard", 1, 3) \
		.sounds(&"step_stone").in_category(&"ore").tag(&"ore").tag(&"crystal") \
		.tag(&"stratum_mid")
	_frozen(&"snow", "Snow", T_SNOW, T_SNOW, T_SNOW, true, 0.0, 0.22) \
		.mining(0.22, &"shovel").drop(&"snowball", 2, 4).sounds(&"step_snow") \
		.in_category(&"natural").tag(&"snow").tag(&"falls").tag(&"biome_tundra") \
		.tag(&"terrain_fill").flags({"falls": true, "friction": 0.88})
	_frozen(&"brick", "Brick", T_BRICK, T_BRICK, T_BRICK, true, 0.0, 0.80) \
		.mining(0.80, &"pickaxe").drop(&"brick_block").sounds(&"step_stone") \
		.in_category(&"building").tag(&"brick").tag(&"stone").places(&"brick_block")
	_frozen(&"bedrock", "Core Fragment", T_BEDROCK, T_BEDROCK, T_BEDROCK, true, 0.0, -1.0) \
		.mining(-1.0, &"pickaxe", 99).sounds(&"step_stone").in_category(&"special") \
		.tag(&"unbreakable").flags({"breakable": false, "blast_resistance": 9999.0})
	_frozen(&"mossy_stone", "Mossy Stone", T_MOSSY, T_MOSSY, T_MOSSY, true, 0.0, 0.70) \
		.mining(0.70, &"pickaxe").drop(&"mossy_stone").sounds(&"step_stone") \
		.in_category(&"natural").tag(&"stone").tag(&"cave_decor").tag(&"biome_forest")
	_frozen(&"crystal_block", "Crystal", T_CRYSTAL, T_CRYSTAL, T_CRYSTAL, true, 0.90, 0.60) \
		.mining(0.60, &"pickaxe").drop(&"crystal_shard", 1, 3).sounds(&"step_glass") \
		.in_category(&"light").tag(&"crystal").tag(&"light_source").tag(&"cave_decor")
	_frozen(&"dark_wood", "Dark Planks", T_DARK_PLANKS, T_DARK_PLANKS, T_DARK_PLANKS,
			true, 0.0, 0.45) \
		.mining(0.45, &"axe").drop(&"dark_wood").sounds(&"step_wood") \
		.in_category(&"building").tag(&"wood").tag(&"trim").flags({"flammable": true})
	_frozen(&"roof_tile", "Roof Tile", T_ROOF, T_ROOF, T_ROOF, true, 0.0, 0.50) \
		.mining(0.50, &"pickaxe").drop(&"roof_tile").sounds(&"step_stone") \
		.in_category(&"building").tag(&"brick")
	_frozen(&"stone_brick", "Stone Brick", T_STONE_BRICK, T_STONE_BRICK, T_STONE_BRICK,
			true, 0.0, 0.85) \
		.mining(0.85, &"pickaxe").drop(&"stone_brick").sounds(&"step_stone") \
		.in_category(&"building").tag(&"brick").tag(&"stone")
	_frozen(&"ice", "Ice", T_ICE, T_ICE, T_ICE, false, 0.02, 0.30) \
		.mining(0.30, &"pickaxe").drop(&"ice").sounds(&"step_snow") \
		.in_category(&"natural").tag(&"ice").tag(&"slippery").tag(&"biome_tundra") \
		.flags({"solid": true, "friction": 0.35})
	_frozen(&"gravel", "Gravel", T_GRAVEL, T_GRAVEL, T_GRAVEL, true, 0.0, 0.35) \
		.mining(0.35, &"shovel").drop(&"gravel").drop(&"flint", 1, 1, 0.12) \
		.sounds(&"step_sand").in_category(&"natural").tag(&"stone").tag(&"falls") \
		.tag(&"terrain_fill").flags({"falls": true})
	_frozen(&"clay", "Clay", T_CLAY, T_CLAY, T_CLAY, true, 0.0, 0.35) \
		.mining(0.35, &"shovel").drop(&"clay_lump", 3, 4).sounds(&"step_dirt") \
		.in_category(&"natural").tag(&"soil").tag(&"biome_ocean")
	_frozen(&"obsidian", "Obsidian", T_OBSIDIAN, T_OBSIDIAN, T_OBSIDIAN, true, 0.04, 2.20) \
		.mining(2.20, &"pickaxe", 3).drop(&"obsidian").sounds(&"step_stone") \
		.in_category(&"natural").tag(&"stone").tag(&"stratum_core").tag(&"biome_magma") \
		.flags({"blast_resistance": 400.0})
	_frozen(&"mud", "Mud", T_MUD, T_MUD, T_MUD, true, 0.0, 0.32) \
		.mining(0.32, &"shovel").drop(&"mud").sounds(&"step_dirt") \
		.in_category(&"natural").tag(&"soil").tag(&"sticky").tag(&"biome_jungle") \
		.flags({"friction": 0.55})
