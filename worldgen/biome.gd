## One biome: a bundle of climate bounds, block palette, flora, fauna and mood.
##
## Biomes are pure data. `BiomeTable` builds them once per run and every other
## module reads them: the terrain shaper for palettes, the decorator for flora,
## the monster agent for `monsters`, weather/music for `sky`, `hazard` and
## `music`. Nothing here mutates during play.
##
## Block names are *requests*, not guarantees — the block-content agent may not
## have registered `&"jungle_leaves"` yet. Everything resolves through
## `Biome.block_id()`, which walks a fallback chain and never returns an
## unregistered id.
class_name Biome
extends RefCounted

## Hazard keys the survival / weather agents read from `hazard`.
const HAZARD_NONE := &"none"
const HAZARD_HEAT := &"heat"
const HAZARD_COLD := &"cold"
const HAZARD_TOXIC := &"toxic"
const HAZARD_RADIATION := &"radiation"
const HAZARD_AIRLESS := &"airless"
const HAZARD_DARK := &"dark"

var key: StringName = &"forest"
var display_name: String = "Forest"

# ------------------------------------------------------------------- climate
## Preferred climate box. `select()` scores distance to the centre of each box,
## so overlapping boxes are fine and gaps never leave a column biome-less.
var temp_min := 0.0
var temp_max := 1.0
var hum_min := 0.0
var hum_max := 1.0
## Elevation band in "sea levels": -1 = deep ocean, 0 = shoreline, 1 = peaks.
var elev_min := -1.0
var elev_max := 1.0
## Tie-break bonus. Raise for signature biomes, lower for fallbacks.
var weight := 1.0

# ------------------------------------------------------------- block palette
var surface_block: StringName = &"grass"
var subsurface_block: StringName = &"dirt"
var stone_block: StringName = &"stone"
var deep_block: StringName = &"stone"
var sand_block: StringName = &"sand"
var underwater_block: StringName = &"sand"
var liquid_block: StringName = &"water"
var soil_depth := 4

# ---------------------------------------------------------------------- flora
## Species keys understood by `WorldDecorator`; see its `SPECIES` table.
var trees: Array[StringName] = []
var tree_density := 0.0        ## 0..1 chance per 5x5 candidate cell
var plants: Array[StringName] = []
var plant_density := 0.0       ## per-column chance of a grass tuft
var flowers: Array[StringName] = []
var flower_density := 0.0
## Extra scatter: keys are boulder, log, mushroom, cactus, coral, crystal,
## bones, vine — values are per-cell chances 0..1.
var scatter: Dictionary = {}
## Blanket laid over the surface after decoration: &"", &"snow" or &"ash".
var cover: StringName = &""

# ----------------------------------------------------------------- terrain
var height_scale := 1.0        ## multiplies the mountain amplitude
var roughness := 1.0           ## multiplies surface detail
var plateau_bias := 0.0        ## 0..1 how strongly the heightfield terraces
var cave_bias := 1.0           ## multiplies cave volume under this biome
var overhang_bias := 1.0       ## multiplies cliff undercutting

# -------------------------------------------------------------------- ores
## Multipliers applied on top of the global ore table, keyed by ore block name.
var ore_weights: Dictionary = {}

# -------------------------------------------------------------------- mood
var sky_color := Color(0.42, 0.62, 0.92)
var light_tint := Color(1.0, 1.0, 1.0)
var fog_color := Color(0.62, 0.74, 0.88)
var ambient_light := 0.0       ## extra baseline glow, 0..1 (caves, midnight)

# -------------------------------------------------------------------- life
var monsters: Array[StringName] = []
var night_monsters: Array[StringName] = []
var monster_density := 1.0
var critters: Array[StringName] = []

# -------------------------------------------------------------- presentation
var music: StringName = &"music_calm"
var ambience: StringName = &"amb_wind"
var hazard: StringName = HAZARD_NONE
var hazard_strength := 0.0

var _ids: Dictionary = {}


func _init(p_key: StringName, p_display: String = "") -> void:
	key = p_key
	display_name = p_display if p_display != "" else String(p_key).capitalize()


# ----------------------------------------------------------------- fluent API
func climate(t0: float, t1: float, h0: float, h1: float, e0: float = -1.0, e1: float = 1.0, w: float = 1.0) -> Biome:
	temp_min = t0
	temp_max = t1
	hum_min = h0
	hum_max = h1
	elev_min = e0
	elev_max = e1
	weight = w
	return self


func ground(surface: StringName, subsurface: StringName, stone: StringName,
		deep: StringName = &"", sand: StringName = &"sand", depth: int = 4) -> Biome:
	surface_block = surface
	subsurface_block = subsurface
	stone_block = stone
	deep_block = deep if deep != &"" else stone
	sand_block = sand
	soil_depth = depth
	return self


func water(liquid: StringName, under: StringName = &"sand") -> Biome:
	liquid_block = liquid
	underwater_block = under
	return self


func flora(p_trees: Array, density: float, p_plants: Array,
		p_flowers: Array = [], plant_d: float = 0.18, flower_d: float = 0.04) -> Biome:
	trees.assign(p_trees)
	tree_density = density
	plants.assign(p_plants)
	flowers.assign(p_flowers)
	plant_density = plant_d
	flower_density = flower_d
	return self


func decorate(d: Dictionary, p_cover: StringName = &"") -> Biome:
	scatter = d
	cover = p_cover
	return self


func shape(p_height: float, p_rough: float, p_plateau: float = 0.0,
		p_cave: float = 1.0, p_overhang: float = 1.0) -> Biome:
	height_scale = p_height
	roughness = p_rough
	plateau_bias = p_plateau
	cave_bias = p_cave
	overhang_bias = p_overhang
	return self


func ores(weights: Dictionary) -> Biome:
	ore_weights = weights
	return self


func palette(sky: Color, tint: Color, fog: Color = Color(0, 0, 0, 0), ambient: float = 0.0) -> Biome:
	sky_color = sky
	light_tint = tint
	fog_color = fog if fog.a > 0.0 else sky.lerp(Color(1, 1, 1), 0.35)
	ambient_light = ambient
	return self


func life(day: Array, night: Array = [], density: float = 1.0, p_critters: Array = []) -> Biome:
	monsters.assign(day)
	night_monsters.assign(night if not night.is_empty() else day)
	monster_density = density
	critters.assign(p_critters)
	return self


func audio(p_music: StringName, p_ambience: StringName = &"amb_wind") -> Biome:
	music = p_music
	ambience = p_ambience
	return self


func danger(p_hazard: StringName, strength: float = 1.0) -> Biome:
	hazard = p_hazard
	hazard_strength = strength
	return self


# ------------------------------------------------------------------- queries
## Squared climate distance, lower is better. Returns INF when the column falls
## outside the elevation band entirely (an ocean biome must never win a peak).
func score(t: float, h: float, e: float) -> float:
	if e < elev_min - 0.25 or e > elev_max + 0.25:
		return INF
	var dt := _axis_distance(t, temp_min, temp_max)
	var dh := _axis_distance(h, hum_min, hum_max)
	var de := _axis_distance(e, elev_min, elev_max)
	return dt * dt + dh * dh + de * de * 0.6 - weight * 0.02


func _axis_distance(v: float, lo: float, hi: float) -> float:
	if v < lo:
		return lo - v
	if v > hi:
		return v - hi
	return 0.0


## Resolved block ids for this biome. Cached after the first call; safe because
## the block registry is frozen once content files finish loading at boot.
func ids() -> Dictionary:
	if not _ids.is_empty():
		return _ids
	_ids = {
		"surface": block_id(surface_block, &"grass"),
		"subsurface": block_id(subsurface_block, &"dirt"),
		"stone": block_id(stone_block, &"stone"),
		"deep": block_id(deep_block, &"stone"),
		"sand": block_id(sand_block, &"sand"),
		"underwater": block_id(underwater_block, &"sand"),
		"liquid": block_id(liquid_block, &"water"),
		"plants": _resolve_list(plants),
		"flowers": _resolve_list(flowers),
		"cover": block_id(cover, &"") if cover != &"" else Const.AIR,
	}
	return _ids


func _resolve_list(names: Array[StringName]) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n: StringName in names:
		if Blocks.has(n):
			out.append(Blocks.id(n))
	return out


# ------------------------------------------------------------ static helpers
## Resolve a block name with a fallback chain that always ends somewhere real.
## Returns `Const.AIR` only when even the universal fallbacks are missing.
static func block_id(name: StringName, fallback: StringName = &"stone") -> int:
	if name != &"" and Blocks.has(name):
		return Blocks.id(name)
	if fallback != &"" and Blocks.has(fallback):
		return Blocks.id(fallback)
	for last: StringName in [&"stone", &"dirt"]:
		if Blocks.has(last):
			return Blocks.id(last)
	return Const.AIR


## First registered name out of `names`, else `fallback`.
static func first_block(names: Array, fallback: StringName = &"stone") -> int:
	for n in names:
		var sn := StringName(n)
		if Blocks.has(sn):
			return Blocks.id(sn)
	return block_id(fallback, &"stone")
