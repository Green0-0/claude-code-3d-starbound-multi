class_name WorldGen
extends RefCounted

## Terrain, biomes, ore distribution and structures.
##
## Pulled out of the voxel world so that a planet is a *configuration* rather
## than a code path: `configure()` takes the dictionary a `Universe.Planet`
## hands over and everything downstream — surface shape, palette, ore bias,
## which trees grow, what gets built on top — falls out of it. Travelling to a
## new world is reseeding this object and restreaming the chunks.
##
## The four depth strata are the spine of the mining progression: surface crust,
## mantle, deepstone and corestone, each hosting the ores of its tier, so
## digging down is the difficulty curve.

const WH := VoxelWorld.WH
const SEA := VoxelWorld.SEA

## Depth bands, top-down. Everything below `core_top` is corestone.
const DEEP_TOP := 16
const MID_TOP := 26
const CRUST_TOP := 34
const CORE_TOP := 8


class Palette extends RefCounted:
	var top := Blocks.GRASS
	var sub := Blocks.DIRT
	var filler := Blocks.STONE
	var beach := Blocks.SAND
	var liquid := Blocks.AIR              ## what fills below sea level
	var sea_level := SEA
	var amplitude := 7.0
	var roughness := 1.0
	var tree: StringName = &""            ## species prefix, "" for none
	var tree_chance := 71                 ## 1-in-N per column
	var foliage: Array[StringName] = []
	var flowers: Array[StringName] = []
	var cave_decor: Array[StringName] = []
	var ores: Array[StringName] = []      ## extra biome-flavoured ores
	var warmth := 0.0
	var hazard: StringName = &""          ## surface hazard scattered about


var seed_value := 1337
var biome: StringName = &"forest"
var threat := 1
var flat := false
var hostiles := true
var sky := Color(0.4, 0.6, 0.9)
var ground := Color(0.3, 0.5, 0.3)
var star := Color(1, 1, 1)
var palette := Palette.new()

var _height: FastNoiseLite
var _hill: FastNoiseLite
var _mountain: FastNoiseLite
var _blend: FastNoiseLite
var _cave: FastNoiseLite
var _ore: FastNoiseLite

## Stratum host blocks, resolved once per planet. See `_host_at`.
var _id_core := 0
var _id_deep := 0
var _id_mantle := 0


func _init() -> void:
	configure({})


func configure(cfg: Dictionary) -> void:
	seed_value = int(cfg.get("seed", 1337))
	biome = StringName(cfg.get("biome", &"forest"))
	threat = int(cfg.get("threat", 1))
	flat = bool(cfg.get("flat", false))
	hostiles = bool(cfg.get("hostiles", true))
	sky = cfg.get("sky", Color(0.4, 0.6, 0.9))
	ground = cfg.get("ground", Color(0.3, 0.5, 0.3))
	star = cfg.get("star", Color(1, 1, 1))
	palette = _palette_for(biome)
	_init_noise()
	# A different planet is a different surface; the cache cannot outlive it.
	_hc_key.resize(HEIGHT_CACHE)
	_hc_val.resize(HEIGHT_CACHE)
	_hc_val.fill(0)
	_id_core = _b(&"corestone")
	_id_deep = _b(&"deepstone")
	_id_mantle = _b(&"mantle_stone")


func _init_noise() -> void:
	_height = FastNoiseLite.new()
	_height.seed = seed_value
	_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height.frequency = 0.0055
	_height.fractal_octaves = 3

	_hill = FastNoiseLite.new()
	_hill.seed = seed_value + 71
	_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_hill.frequency = 0.013
	_hill.fractal_octaves = 3

	_mountain = FastNoiseLite.new()
	_mountain.seed = seed_value + 913
	_mountain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountain.frequency = 0.0085
	_mountain.fractal_octaves = 3

	_blend = FastNoiseLite.new()
	_blend.seed = seed_value + 4242
	_blend.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_blend.frequency = 0.0060
	_blend.fractal_octaves = 2

	_cave = FastNoiseLite.new()
	_cave.seed = seed_value + 77
	_cave.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_cave.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_cave.frequency = 0.030
	_cave.fractal_octaves = 2

	_ore = FastNoiseLite.new()
	_ore.seed = seed_value + 5150
	_ore.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ore.frequency = 0.055


# =============================================================================
# biome palettes
# =============================================================================

static func _b(name: StringName) -> int:
	return Blocks.id(name)


func _palette_for(key: StringName) -> Palette:
	var p := Palette.new()
	match key:
		&"forest", &"garden":
			p.top = _b(&"forest_grass")
			p.sub = _b(&"loam")
			p.liquid = _b(&"water")
			p.tree = &"oak"
			p.tree_chance = 52
			p.foliage = [&"tall_grass", &"fern", &"mushroom_brown", &"mushroom_red"]
			p.flowers = [&"flower_red", &"flower_yellow"]
			p.cave_decor = [&"dim_moss", &"faint_lichen", &"glow_fungus"]
			p.ores = [&"copper_ore", &"iron_ore", &"tin_ore"]
		&"savannah":
			p.top = _b(&"savannah_grass")
			p.sub = _b(&"savannah_soil")
			p.liquid = _b(&"water")
			p.amplitude = 4.5
			p.tree = &"palm"
			p.tree_chance = 140
			p.foliage = [&"dry_grass", &"tall_grass"]
			p.flowers = [&"flower_yellow"]
			p.cave_decor = [&"faint_lichen"]
			p.ores = [&"copper_ore", &"gold_ore", &"salt_deposit"]
			p.warmth = 0.3
		&"desert":
			p.top = _b(&"sand")
			p.sub = _b(&"sandstone")
			p.filler = _b(&"sandstone")
			p.beach = _b(&"red_sand")
			p.liquid = Blocks.AIR
			p.sea_level = 0
			p.amplitude = 5.5
			p.tree = &"palm"
			p.tree_chance = 260
			p.foliage = [&"dead_bush", &"cactus"]
			p.cave_decor = [&"faint_lichen"]
			p.ores = [&"salt_deposit", &"copper_ore", &"gold_ore"]
			p.warmth = 0.65
		&"tundra", &"snow":
			p.top = _b(&"snow_cover")
			p.sub = _b(&"frozen_dirt")
			p.filler = _b(&"ice_stone")
			p.beach = _b(&"packed_snow")
			p.liquid = _b(&"water")
			p.amplitude = 6.0
			p.tree = &"pine"
			p.tree_chance = 84
			p.foliage = [&"tall_grass"]
			p.flowers = [&"flower_blue"]
			p.cave_decor = [&"faint_lichen"]
			p.ores = [&"cerulium_ore", &"iron_ore", &"silver_ore"]
			p.warmth = -0.6
		&"jungle", &"swamp":
			p.top = _b(&"jungle_grass")
			p.sub = _b(&"rich_soil")
			p.liquid = _b(&"swamp_water")
			p.sea_level = SEA + 1
			p.amplitude = 8.0
			p.tree = &"jungle"
			p.tree_chance = 34
			p.foliage = [&"fern", &"tall_grass", &"vine", &"mushroom_red"]
			p.flowers = [&"flower_red"]
			p.cave_decor = [&"dim_moss", &"glow_fungus"]
			p.ores = [&"copper_ore", &"emerald_ore", &"iron_ore"]
			p.warmth = 0.35
		&"ocean":
			p.top = _b(&"white_sand")
			p.sub = _b(&"silt")
			p.filler = _b(&"limestone")
			p.beach = _b(&"white_sand")
			p.liquid = _b(&"water")
			p.sea_level = SEA + 8
			p.amplitude = 4.0
			p.foliage = [&"kelp", &"coral_glow"]
			p.cave_decor = [&"deepglow_algae"]
			p.ores = [&"cerulium_ore", &"silver_ore", &"sapphire_ore"]
		&"toxic":
			p.top = _b(&"toxic_grass")
			p.sub = _b(&"toxic_dirt")
			p.filler = _b(&"toxic_stone")
			p.beach = _b(&"toxic_sand")
			p.liquid = _b(&"toxic_water")
			p.amplitude = 6.5
			p.foliage = [&"glow_mushroom", &"slime_growth"]
			p.cave_decor = [&"glow_fungus"]
			p.ores = [&"uranium_ore", &"sulphur_ore", &"lead_ore"]
			p.hazard = &"poison_spikes"
			p.warmth = 0.2
		&"volcanic", &"scorched":
			p.top = _b(&"ash")
			p.sub = _b(&"basalt")
			p.filler = _b(&"basalt")
			p.beach = _b(&"cinder")
			p.liquid = _b(&"lava")
			p.sea_level = 5
			p.amplitude = 9.0
			p.foliage = []
			p.cave_decor = [&"crystal_ember", &"magma_block"]
			p.ores = [&"core_fragment_ore", &"sulphur_ore", &"rubium_ore"]
			p.hazard = &"magma_block"
			p.warmth = 0.85
		&"moon":
			p.top = _b(&"moon_dust")
			p.sub = _b(&"moon_rock")
			p.filler = _b(&"moon_rock")
			p.beach = _b(&"moon_dust")
			p.liquid = Blocks.AIR
			p.sea_level = 0
			p.amplitude = 8.0
			p.cave_decor = [&"erchius_crystal"]
			p.ores = [&"erchius_crystal", &"titanium_ore", &"platinum_ore"]
			p.warmth = -0.4
		&"barren":
			p.top = _b(&"gravel")
			p.sub = _b(&"crust_stone")
			p.filler = _b(&"crust_stone")
			p.beach = _b(&"gravel")
			p.liquid = Blocks.AIR
			p.sea_level = 0
			p.amplitude = 6.0
			p.foliage = [&"dead_bush"]
			p.cave_decor = [&"bone_block", &"faint_lichen"]
			p.ores = [&"iron_ore", &"lead_ore", &"meteorite"]
		&"alien":
			p.top = _b(&"alien_grass")
			p.sub = _b(&"alien_dirt")
			p.filler = _b(&"alien_rock")
			p.beach = _b(&"alien_sand")
			p.liquid = _b(&"healing_water")
			p.amplitude = 8.5
			p.tree = &"alien"
			p.tree_chance = 64
			p.foliage = [&"glow_flower", &"glow_vine", &"flesh_block"]
			p.flowers = [&"glow_flower"]
			p.cave_decor = [&"crystal_violet", &"glow_fungus"]
			p.ores = [&"aegisalt_ore", &"ferozium_ore", &"violium_ore", &"prisilite_ore"]
		&"crystal":
			p.top = _b(&"gravel")
			p.sub = _b(&"granite")
			p.filler = _b(&"geode_shell")
			p.beach = _b(&"gravel")
			p.liquid = Blocks.AIR
			p.sea_level = 0
			p.amplitude = 10.0
			p.cave_decor = [&"crystal_blue", &"crystal_violet", &"glowstone"]
			p.ores = [&"diamond_ore", &"amethyst_ore", &"prisilite_ore"]
		&"ancient_ruins":
			p.top = _b(&"gravel")
			p.sub = _b(&"crust_stone")
			p.filler = _b(&"limestone")
			p.beach = _b(&"sand")
			p.liquid = Blocks.AIR
			p.sea_level = 0
			p.amplitude = 5.0
			p.foliage = [&"dead_bush", &"tall_grass"]
			p.cave_decor = [&"dim_moss", &"ancient_accent"]
			p.ores = [&"gold_ore", &"platinum_ore", &"diamond_ore"]
		_:
			p.top = _b(&"forest_grass")
			p.sub = _b(&"loam")
			p.liquid = _b(&"water")
			p.tree = &"oak"
			p.foliage = [&"tall_grass"]
			p.ores = [&"copper_ore", &"iron_ore"]
	if p.top == Blocks.AIR:
		p.top = Blocks.GRASS
	if p.sub == Blocks.AIR:
		p.sub = Blocks.DIRT
	if p.filler == Blocks.AIR:
		p.filler = Blocks.STONE
	return p


# =============================================================================
# shape
# =============================================================================

static func hash3(x: int, y: int, z: int, salt: int) -> int:
	var h := x * 374761393 + y * 668265263 + z * 2147483647 + salt * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


## How many columns the height cache remembers. Must be a power of two.
##
## Direct-mapped and fixed size on purpose. A dictionary keyed by column would
## be a better cache and an unbounded one: this is asked about every column the
## player has ever walked over, and over a long session that dictionary is a
## leak with a good hit rate. A fixed table cannot grow, needs no eviction
## policy, and access here is spatially coherent enough that collisions are
## rare — a structure probing its footprint and the generator filling a chunk
## both sweep a small rectangle.
const HEIGHT_CACHE := 8192
var _hc_key := PackedInt64Array()
var _hc_val := PackedInt32Array()


## The surface at a column.
##
## Three noise lookups, and it is asked for far more often than there are
## columns: the generator wants every column of a chunk, each structure probes
## its whole footprint for flatness before it commits, and the trees and grass
## ask again. Caching it took the largest single bite out of chunk generation.
func surface_height(gx: int, gz: int) -> int:
	if flat:
		return 22
	var key := (gx << 32) | (gz & 0xffffffff)
	var slot := int((gx * 73856093) ^ (gz * 19349663)) & (HEIGHT_CACHE - 1)
	# A height is always clamped into [5, WH - 8], so zero can stand for "this
	# slot has never been written" and the table needs no separate valid bit.
	if _hc_val[slot] != 0 and _hc_key[slot] == key:
		return _hc_val[slot]
	var base := 22.0
	base += _height.get_noise_2d(gx, gz) * palette.amplitude
	base += _hill.get_noise_2d(gx, gz) * 1.9 * palette.roughness
	var m := _mountain.get_noise_2d(gx, gz)
	if m > 0.36:
		base += (m - 0.36) * 17.0
	var out := clampi(int(round(base)), 5, WH - 8)
	_hc_key[slot] = key
	_hc_val[slot] = out
	return out


## Which stratum block hosts ore at this depth.
##
## The four ids are resolved once in `configure` rather than here. This is asked
## about every voxel below the crust — some seven thousand times per chunk — and
## `Blocks.id(&"corestone")` is a StringName lookup in a dictionary, which made
## naming the rock the most expensive thing about generating it.
func _host_at(y: int) -> int:
	if y < CORE_TOP:
		return _id_core
	if y < DEEP_TOP:
		return _id_deep
	if y < MID_TOP:
		return _id_mantle
	return palette.filler


## Roll an ore for a cell, or AIR. Tier is gated by depth so the ladder is the
## descent: you cannot find solarium near the surface however lucky you are.
func _ore_at(gx: int, y: int, gz: int) -> int:
	# chunky 2x2x2 clusters, cheap integer hash
	var hv := hash3(gx >> 1, y >> 1, gz >> 1, 7) % 1000
	# No branch below reaches past 90 in a thousand, so this cell cannot be ore
	# whatever the vein noise says — and asking the noise is the single most
	# expensive thing in the generator. Testing the free gate first skips nine
	# calls in ten. The two tests are independent, so the ore field is unchanged.
	if hv >= 90:
		return Blocks.AIR
	var vein := _ore.get_noise_3d(float(gx), float(y) * 1.6, float(gz))
	if vein < 0.18:
		return Blocks.AIR

	# biome-flavoured ores get a shot first, so a toxic world really is uranium
	if hv < 10 and not palette.ores.is_empty():
		var pick: StringName = palette.ores[hash3(gx, y, gz, 91) % palette.ores.size()]
		var def := Blocks.get_by_name(pick)
		if def != null and _tier_allowed(def.tier, y):
			return def.id

	if y < CORE_TOP:
		if hv < 5: return _b(&"solarium_ore")
		if hv < 11: return _b(&"rubium_ore")
		if hv < 18: return _b(&"core_fragment_ore")
		if hv < 26: return _b(&"diamond_ore")
		if hv < 40: return _b(&"plutonium_ore")
	elif y < DEEP_TOP:
		if hv < 6: return _b(&"violium_ore")
		if hv < 12: return _b(&"ferozium_ore")
		if hv < 20: return _b(&"aegisalt_ore")
		if hv < 30: return _b(&"durasteel_ore")
		if hv < 42: return _b(&"uranium_ore")
		if hv < 56: return _b(&"titanium_ore")
		if hv < 66: return _b(&"ruby_ore")
		if hv < 74: return _b(&"sapphire_ore")
	elif y < MID_TOP:
		if hv < 10: return _b(&"platinum_ore")
		if hv < 22: return _b(&"tungsten_ore")
		if hv < 36: return _b(&"gold_ore")
		if hv < 50: return _b(&"silver_ore")
		if hv < 62: return _b(&"amethyst_ore")
		if hv < 74: return _b(&"silicon_ore")
		if hv < 90: return Blocks.IRON_ORE
	else:
		if hv < 14: return Blocks.IRON_ORE
		if hv < 30: return _b(&"copper_ore")
		if hv < 42: return _b(&"tin_ore")
		if hv < 58: return Blocks.COAL_ORE
		if hv < 68: return Blocks.GRAVEL
	return Blocks.AIR


static func _tier_allowed(tier: int, y: int) -> bool:
	if tier >= 5:
		return y < DEEP_TOP
	if tier >= 3:
		return y < MID_TOP
	return true


## Fill one column. Returns the surface height so the decorator can use it.
func fill_column(gx: int, gz: int, types: PackedByteArray, base: int) -> int:
	var h := surface_height(gx, gz)
	var sea := palette.sea_level
	var shore := h - 1 <= sea + 1

	for y in h:
		var id := palette.filler
		if y == 0:
			id = Blocks.BEDROCK
		elif y == h - 1:
			id = palette.beach if shore else palette.top
		elif y >= h - 4:
			id = palette.beach if shore else palette.sub
		elif y >= CRUST_TOP:
			id = palette.filler
		else:
			id = _host_at(y)
			var ore := _ore_at(gx, y, gz)
			if ore != Blocks.AIR:
				id = ore

		# caves: ridged noise carves connected tunnel networks
		if y > 1 and y < h - 3 and not flat:
			var cv := absf(_cave.get_noise_3d(float(gx), float(y) * 1.7, float(gz)))
			if cv > 0.865:
				id = Blocks.AIR
			elif cv > 0.83 and y < MID_TOP and not palette.cave_decor.is_empty():
				if hash3(gx, y, gz, 31) % 100 < 9:
					var d: StringName = palette.cave_decor[
						hash3(gx, y, gz, 55) % palette.cave_decor.size()]
					var dd := Blocks.get_by_name(d)
					if dd != null:
						id = dd.id

		types[base + y] = id

	# --- fill the sea, and anything a cave opened up below the water line
	if palette.liquid != Blocks.AIR:
		for y in range(h, sea + 1):
			types[base + y] = palette.liquid
		for y in range(1, mini(h, sea + 1)):
			if types[base + y] == Blocks.AIR:
				types[base + y] = palette.liquid
	return h


# =============================================================================
# decoration
# =============================================================================

## Trees, undergrowth and surface hazards for one chunk. `write` is a callable
## `(gx, gy, gz, id)` so this never needs to know how the world stores things.
func decorate(cx: int, cz: int, write: Callable, height_of: Callable,
		block_at: Callable) -> void:
	if flat:
		return
	var ox := cx * VoxelWorld.CW
	var oz := cz * VoxelWorld.CW
	for lx in VoxelWorld.CW:
		for lz in VoxelWorld.CW:
			var gx := ox + lx
			var gz := oz + lz
			var h: int = height_of.call(gx, gz)
			if h - 1 <= palette.sea_level:
				continue
			var surface: int = block_at.call(gx, h - 1, gz)
			if surface != palette.top and surface != palette.beach:
				continue

			# --- a tree
			if palette.tree != &"" \
					and hash3(gx, 0, gz, 21) % palette.tree_chance == 0:
				_tree(gx, h, gz, write)
				continue

			# --- undergrowth
			var roll := hash3(gx, 1, gz, 33) % 100
			if roll < 14 and not palette.foliage.is_empty():
				var f: StringName = palette.foliage[
					hash3(gx, 2, gz, 44) % palette.foliage.size()]
				var fd := Blocks.get_by_name(f)
				if fd != null:
					write.call(gx, h, gz, fd.id)
			elif roll < 18 and not palette.flowers.is_empty():
				var fl: StringName = palette.flowers[
					hash3(gx, 3, gz, 66) % palette.flowers.size()]
				var fld := Blocks.get_by_name(fl)
				if fld != null:
					write.call(gx, h, gz, fld.id)
			elif roll == 99 and palette.hazard != &"":
				var hz := Blocks.get_by_name(palette.hazard)
				if hz != null:
					write.call(gx, h, gz, hz.id)


func _tree(gx: int, base: int, gz: int, write: Callable) -> void:
	var log_id := Blocks.id(StringName(String(palette.tree) + "_log"))
	var leaf_id := Blocks.id(StringName(String(palette.tree) + "_leaves"))
	if log_id == Blocks.AIR:
		log_id = Blocks.LOG
	if leaf_id == Blocks.AIR:
		leaf_id = Blocks.LEAVES
	var h := 4 + (hash3(gx, 1, gz, 3) % 4)
	for y in h:
		write.call(gx, base + y, gz, log_id)
	var top := base + h
	for dy in range(-2, 2):
		var r := 2 if dy < 0 else 1
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r:
					continue
				if dx == 0 and dz == 0 and dy < 1:
					continue
				write.call(gx + dx, top + dy, gz + dz, leaf_id)
	write.call(gx, top + 1, gz, leaf_id)


# =============================================================================
# structures
# =============================================================================

## Structures are chosen per chunk from a hash, so they are stable across
## reloads and never need to be remembered. Returns a description of what it
## placed so the game can hang entities (NPCs, chests, spawners) off it.
func structure_for(cx: int, cz: int) -> Dictionary:
	if flat:
		return {}
	var roll := hash3(cx, 0, cz, 1201) % 100
	var h := hash3(cx, 7, cz, 88)
	if roll < 3:
		return {"kind": &"village", "houses": 3 + h % 3}
	if roll < 6:
		return {"kind": &"ruin"}
	if roll < 9:
		return {"kind": &"camp"}
	if roll < 13:
		return {"kind": &"house"}
	if roll < 17:
		return {"kind": &"mineshaft"}
	return {}
