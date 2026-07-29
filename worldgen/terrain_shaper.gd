## Pass 1 and 2 of the generator: the heightfield and the rock it is made of.
##
## The shape of a planet is built from
##   continental noise  -> base elevation and the coastlines
##   ridged noise       -> mountain spines, masked to land
##   plateau noise      -> terracing (mesas, step canyons)
##   river noise        -> valleys carved back down to sea level
##   3D overhang noise  -> cliffs that undercut, arches, sea stacks
##   3D island noise    -> floating islands in the sky band
##
## Everything below the surface is banded into strata — soil, sedimentary,
## deep stone, mantle, core — with a hard bedrock floor at y=0. The bands are
## deliberately *horizontal*: they read identically from all four viewing
## planes, which is the whole point of this world.
class_name TerrainShaper
extends RefCounted

const BEDROCK_SALT := 0x8ED0
const SED_BAND := 6            ## thickness of one sedimentary stripe

var noise: NoiseBank
var profile: Dictionary = {}
var palette: PackedInt32Array = PackedInt32Array()
## One soft weight per biome table index, from the planet's `biome_weights`.
var biome_bonus: PackedFloat32Array = PackedFloat32Array()

var size_x := 512
var size_z := 512
var sea_level := 96
## Mean altitude of dry land. Kept separate from `sea_level` so that a moon
## (no ocean) still gets its terrain at a sensible height, and an ocean world
## still gets most of its terrain below the waves.
var land_base := 104
var elev_ref := 96             ## the y that counts as elevation 0
var base_amp := 26.0           ## continental relief, blocks
var mountain_amp := 62.0       ## extra height on ridge spines
var detail_amp := 4.0
var temp_bias := 0.0
var hum_bias := 0.0
var temp_var := 1.0
var hum_var := 1.0
var roughness := 1.0
var overhang_strength := 1.0
var island_chance := 1.0       ## 0 disables floating islands
var island_low := 150
var island_high := 224
var mantle_y := 52
var core_y := 22
var liquid_name: StringName = &"water"

var _h_cache: Dictionary = {}
var _b_cache: Dictionary = {}
var _id_bedrock := 1
var _sed_ids := PackedInt32Array()
var _mantle_id := 1
var _core_id := 1
var _deep_id := 1


## Bind the shaper to a planet. `meta` is the raw planet dictionary,
## `p_profile` the `BiomeTable.planet_profile()` result for its type.
func configure(p_noise: NoiseBank, meta: Dictionary, p_profile: Dictionary) -> void:
	noise = p_noise
	profile = p_profile
	size_x = int(meta.get("size_x", Const.PLANET_SIZE_DEFAULT))
	size_z = int(meta.get("size_z", Const.PLANET_SIZE_DEFAULT))
	sea_level = int(meta.get("sea_level", profile.get("sea", 96)))
	# `surface_level` is the space agent's name for the mean land altitude.
	land_base = int(meta.get("base", meta.get("surface_level", profile.get("base", 0))))
	if land_base <= 0:
		land_base = sea_level + 8
	# `ocean_level` (0..1) says how much of the surface should end up submerged;
	# it only applies when the planet did not name an explicit land altitude.
	if not meta.has("base") and not meta.has("surface_level") and meta.has("ocean_level"):
		land_base = sea_level + int(round((0.5 - clampf(float(meta["ocean_level"]), 0.0, 1.0)) * 44.0))
	# Elevation is measured from the waterline, except on worlds with no ocean
	# worth the name, where it is measured from just below the mean land level.
	elev_ref = maxi(sea_level, land_base - 10)
	roughness = float(meta.get("roughness", profile.get("roughness", 1.0)))
	var mountains := float(meta.get("mountains", profile.get("mountains", 1.0)))
	base_amp = 26.0 * clampf(mountains, 0.3, 2.0)
	mountain_amp = 62.0 * clampf(mountains, 0.3, 2.0)
	detail_amp = 4.0 * roughness
	# The planet's own `temperature` (-1 frozen .. +1 scorching) shifts the whole
	# climate field on top of the archetype's bias.
	temp_bias = float(profile.get("temp", 0.0)) + clampf(float(meta.get("temperature", 0.0)), -1.0, 1.0) * 0.25
	hum_bias = float(profile.get("hum", 0.0))
	temp_var = float(profile.get("temp_var", 1.0))
	hum_var = float(profile.get("hum_var", 1.0))
	liquid_name = StringName(meta.get("liquid", profile.get("liquid", &"water")))
	overhang_strength = float(meta.get("overhangs", 1.0))
	island_chance = float(meta.get("islands", 1.0))
	island_low = clampi(sea_level + 54, 120, 190)
	island_high = clampi(island_low + 60, 150, Const.WORLD_HEIGHT - 24)
	mantle_y = clampi(int(meta.get("mantle_y", 52)), 24, 90)
	core_y = clampi(int(meta.get("core_y", 22)), 6, mantle_y - 8)
	_build_palette(meta)
	_h_cache.clear()
	_b_cache.clear()
	_resolve_blocks()


## Decide which biomes this planet may use. A planet that ships
## `biome_weights` (see `space/universe.gd`) gets exactly those, translated
## through `BiomeTable.alias()`; anything else falls back to the archetype's
## palette. The weights survive as a soft bonus in `BiomeTable.select()`.
func _build_palette(meta: Dictionary) -> void:
	palette = PackedInt32Array()
	biome_bonus = PackedFloat32Array()
	biome_bonus.resize(BiomeTable.count())
	var seen := {}
	var weights: Dictionary = meta.get("biome_weights", {})
	for k in weights:
		var mapped := BiomeTable.alias(StringName(k))
		if mapped == &"":
			continue
		var idx := BiomeTable.index_of(mapped)
		var w := float(weights[k])
		biome_bonus[idx] = maxf(biome_bonus[idx], w)
		if not seen.has(idx):
			seen[idx] = true
			palette.append(idx)
	var primary := BiomeTable.alias(StringName(meta.get("primary_biome", &"")))
	if primary != &"":
		var pi := BiomeTable.index_of(primary)
		if not seen.has(pi):
			seen[pi] = true
			palette.append(pi)
		biome_bonus[pi] = maxf(biome_bonus[pi], 0.5)
	if palette.is_empty():
		palette = BiomeTable.palette_indices(profile)


func _resolve_blocks() -> void:
	_id_bedrock = Biome.block_id(&"bedrock", &"stone")
	_mantle_id = Biome.first_block([&"mantle_stone", &"magmarock", &"basalt", &"obsidian"], &"stone")
	_core_id = Biome.first_block([&"corestone", &"core_stone", &"obsidian"], &"stone")
	_deep_id = Biome.first_block([&"deepstone", &"gneiss", &"schist"], &"stone")
	_sed_ids = PackedInt32Array([
		Biome.first_block([&"limestone", &"sandstone", &"marble"], &"stone"),
		Biome.first_block([&"sandstone", &"limestone", &"slate"], &"stone"),
		Biome.first_block([&"slate", &"granite", &"marble"], &"stone"),
	])


# ============================================================== column queries
func _key(x: int, z: int) -> int:
	return (posmod(x, size_x) << 20) | posmod(z, size_z)


## Surface height (topmost solid y of the ground, ignoring trees and islands).
func height_at(x: int, z: int) -> int:
	var k := _key(x, z)
	var v: int = _h_cache.get(k, -1)
	if v >= 0:
		return v
	v = _compute_height(posmod(x, size_x), posmod(z, size_z))
	if _h_cache.size() > 300000:
		_h_cache.clear()
	_h_cache[k] = v
	return v


## Index into `BiomeTable` for a column.
func biome_index_at(x: int, z: int) -> int:
	var k := _key(x, z)
	var v: int = _b_cache.get(k, -1)
	if v >= 0:
		return v
	var nx := posmod(x, size_x)
	var nz := posmod(z, size_z)
	v = _compute_biome(nx, nz, height_at(nx, nz))
	if _b_cache.size() > 300000:
		_b_cache.clear()
	_b_cache[k] = v
	return v


func biome_at(x: int, z: int) -> Biome:
	return BiomeTable.by_index(biome_index_at(x, z))


## Everything a caller might want about one column, in one dictionary.
## Used by the decorator, the spawn finder and (via `PlanetGen`) structures.
func column(x: int, z: int) -> Dictionary:
	var h := height_at(x, z)
	var bi := biome_index_at(x, z)
	var b := BiomeTable.by_index(bi)
	return {
		"height": h,
		"biome": b.key,
		"biome_index": bi,
		"underwater": h < sea_level,
		"beach": h >= sea_level - 2 and h <= sea_level + 2,
		"slope": slope_at(x, z),
		"elevation": elevation_of(h),
	}


## Largest height difference to the four neighbours — the cliff detector.
func slope_at(x: int, z: int) -> float:
	var h := height_at(x, z)
	var m := 0
	m = maxi(m, absi(height_at(x + 1, z) - h))
	m = maxi(m, absi(height_at(x - 1, z) - h))
	m = maxi(m, absi(height_at(x, z + 1) - h))
	m = maxi(m, absi(height_at(x, z - 1) - h))
	return float(m)


## Height expressed in "sea levels": -1 deep ocean, 0 shore, +1 peaks.
func elevation_of(h: int) -> float:
	if h >= elev_ref:
		return clampf(float(h - elev_ref) / maxf(base_amp + mountain_amp * 0.6, 1.0), 0.0, 1.0)
	return clampf(float(h - elev_ref) / maxf(float(elev_ref) * 0.5, 1.0), -1.0, 0.0)


# ============================================================== the heightfield
func _compute_height(x: int, z: int) -> int:
	var fx := float(x)
	var fz := float(z)
	# Domain warp: folds the coastline and the ridge lines so they stop looking
	# like smooth noise contours.
	var w := noise.warp_xz(fx, 0.0, fz, 26.0)
	var wx := fx + w.x
	var wz := fz + w.y

	var cont := noise.n2(noise.continent, wx, wz)
	var h := float(land_base) + cont * base_amp

	# Mountains only grow above the waterline, and grow harder inland.
	var land_mask := clampf((h - float(sea_level)) / 24.0, 0.0, 1.0)
	if land_mask > 0.0:
		var rid := noise.ridged(noise.ridge, wx * 1.0, wz * 1.0)
		h += rid * mountain_amp * land_mask

	# Terracing. `plateau` decides where mesas appear; inside those regions the
	# height snaps to bands, which reads as layered cliffs from every view.
	var pl := NoiseBank.unit(noise.n2(noise.plateau, fx, fz))
	if pl > 0.58 and h > float(sea_level):
		var strength := clampf((pl - 0.58) * 3.4, 0.0, 1.0)
		var step := 7.0
		var terraced := roundf(h / step) * step
		h = lerpf(h, terraced, strength * 0.85)

	# Rivers: the ridge line of a low-frequency field, carved down to just below
	# sea level. They cut through mountains, giving vertical-walled gorges.
	var rv := 1.0 - absf(noise.n2(noise.river, wx * 0.85, wz * 0.85))
	if rv > 0.965 and h > float(sea_level) - 4.0:
		var t := clampf((rv - 0.965) / 0.035, 0.0, 1.0)
		var bed := float(sea_level) - 3.0 - 2.0 * NoiseBank.unit(noise.n2(noise.detail, fx * 0.3, fz * 0.3))
		h = lerpf(h, bed, smoothstep(0.0, 1.0, t))

	# Surface detail, scaled by the biome the coarse height implies.
	var coarse := int(clampf(h, 4.0, float(Const.WORLD_HEIGHT - 12)))
	var b := BiomeTable.by_index(_compute_biome(x, z, coarse))
	h += noise.n2(noise.detail, fx, fz) * detail_amp * b.roughness

	return clampi(int(round(h)), 3, Const.WORLD_HEIGHT - 12)


func _compute_biome(x: int, z: int, h: int) -> int:
	var fx := float(x)
	var fz := float(z)
	var elev := elevation_of(h)
	var t := NoiseBank.unit(noise.n2(noise.temperature, fx, fz) * temp_var) + temp_bias
	var hum := NoiseBank.unit(noise.n2(noise.humidity, fx, fz) * hum_var) + hum_bias
	# Altitude is cold; deep water is temperate and wet.
	t -= maxf(elev, 0.0) * 0.28
	hum += clampf(-elev, 0.0, 1.0) * 0.2
	return BiomeTable.select(clampf(t, 0.0, 1.0), clampf(hum, 0.0, 1.0), elev, palette, biome_bonus)


# ============================================================ the fill itself
## Write terrain into `chunk`. Leaves air everywhere the surface is above it,
## which lets the cave and decoration passes early-out cheaply.
##
## Packed arrays are copy-on-write, so every pass takes the array, returns it,
## and only the owning function assigns it back to the chunk.
func fill_chunk(chunk: Chunk) -> void:
	var o := chunk.origin()
	var max_h := -1
	var min_h := Const.WORLD_HEIGHT
	for lz in Const.CHUNK_SIZE:
		for lx in Const.CHUNK_SIZE:
			var h := height_at(o.x + lx, o.z + lz)
			max_h = maxi(max_h, h)
			min_h = mini(min_h, h)

	var in_islands := island_chance > 0.0 and o.y + 15 >= island_low and o.y <= island_high
	if o.y > max_h and not in_islands:
		chunk.recount()
		return  # pure sky

	var blocks := chunk.blocks
	if o.y <= max_h:
		blocks = _fill_ground(blocks, o, min_h, max_h)
	if in_islands:
		blocks = _fill_islands(blocks, o)
	chunk.blocks = blocks
	chunk.recount()


func _fill_ground(blocks: PackedInt32Array, o: Vector3i, min_h: int, max_h: int) -> PackedInt32Array:
	# Overhang carving only matters near the surface of steep terrain, so the
	# 3D field is sampled once per chunk and only when the band overlaps.
	var oh := PackedFloat32Array()
	if overhang_strength > 0.0 and o.y + 15 >= min_h - 22 and o.y <= max_h:
		oh = noise.lattice3(noise.overhang, o, 1.0, 0.75, 1.0)
	var carving := not oh.is_empty()

	var strata_wobble := noise.n2(noise.strata, float(o.x), float(o.z)) * 3.0
	for lz in Const.CHUNK_SIZE:
		var wz := o.z + lz
		for lx in Const.CHUNK_SIZE:
			var wx := o.x + lx
			var h := height_at(wx, wz)
			if o.y > h:
				continue
			var b := BiomeTable.by_index(biome_index_at(wx, wz))
			var ids: Dictionary = b.ids()
			var slope := slope_at(wx, wz)
			var underwater := h < sea_level
			var cut_thr := (0.42 - clampf(slope, 0.0, 8.0) * 0.022) / maxf(b.overhang_bias * overhang_strength, 0.05)
			var steep := slope >= 2.0
			var top := mini(h - o.y, 15)
			for ly in range(0, top + 1):
				var y := o.y + ly
				if carving and steep and y > core_y and y < h - 1 and y > h - 22:
					if NoiseBank.lat3(oh, lx, ly, lz) > cut_thr:
						continue
				blocks[(ly << 8) | (lz << 4) | lx] = _stratum(
					y, h, b, ids, slope, underwater, strata_wobble, wx, wz)
	return blocks


## Which rock belongs at `y` in a column whose surface is `h`.
func _stratum(y: int, h: int, b: Biome, ids: Dictionary, slope: float,
		underwater: bool, wobble: float, wx: int, wz: int) -> int:
	if y <= 0:
		return _id_bedrock
	if y <= 3 and NoiseBank.rand01(wx, y, wz, BEDROCK_SALT) < float(4 - y) * 0.3:
		return _id_bedrock
	if y < core_y + int(wobble):
		return _core_id
	if y < mantle_y + int(wobble * 1.5):
		return _mantle_id

	var d := h - y
	if d == 0:
		if underwater:
			return int(ids["underwater"])
		if h <= sea_level + 2 and h >= sea_level - 2:
			return int(ids["sand"])       # beach
		if slope >= 5.0:
			return int(ids["stone"])      # bare cliff face
		return int(ids["surface"])
	if d <= b.soil_depth:
		if underwater:
			return int(ids["underwater"]) if d <= 2 else int(ids["subsurface"])
		if slope >= 6.0:
			return int(ids["stone"])
		return int(ids["subsurface"])
	# Sedimentary stripes: visible horizontal banding for the first ~30 blocks.
	# Layered strata are the one terrain feature that looks identical from all
	# four viewing planes, so they carry a lot of the underground's readability.
	if d <= 30:
		var band := int(floor((float(y) + wobble) / float(SED_BAND)))
		if posmod(band, 3) == 1:
			return _sed_ids[posmod(band / 3, _sed_ids.size())]
		return int(ids["stone"])
	# Below the stripes: the biome's own deep rock, then the planet-wide
	# deepstone shell that sits on top of the mantle.
	if y < mantle_y + 34:
		return _deep_id
	return int(ids["deep"])


# ========================================================== floating islands
## Sky islands: 3D blobs with a soft vertical envelope, capped with soil and
## grass. They are the clearest example of terrain that must read from every
## direction — you often only see the route onto one after a flip.
func _fill_islands(blocks: PackedInt32Array, o: Vector3i) -> PackedInt32Array:
	var lat := noise.lattice3(noise.island, o, 0.75, 1.5, 0.75)
	var mid := float(island_low + island_high) * 0.5
	var half := maxf(float(island_high - island_low) * 0.5, 1.0)
	var bonus := (island_chance - 1.0) * 0.15
	# Threshold per y, precomputed: a soft envelope keeps islands away from the
	# band edges so they end up as discrete lumps rather than a sky ceiling.
	var thr := PackedFloat32Array()
	thr.resize(Const.CHUNK_SIZE + 1)
	for ly in Const.CHUNK_SIZE + 1:
		var y := o.y + ly
		var env := clampf(1.0 - absf((float(y) - mid) / half), 0.0, 1.0)
		thr[ly] = 0.52 + (1.0 - env) * 0.55 - bonus
		if y < island_low or y > island_high:
			thr[ly] = 99.0

	for lz in Const.CHUNK_SIZE:
		for lx in Const.CHUNK_SIZE:
			var b := BiomeTable.by_index(biome_index_at(o.x + lx, o.z + lz))
			var ids: Dictionary = b.ids()
			for ly in Const.CHUNK_SIZE:
				var i := (ly << 8) | (lz << 4) | lx
				if blocks[i] != Const.AIR:
					continue
				var v := NoiseBank.lat3(lat, lx, ly, lz)
				if v <= thr[ly]:
					continue
				var above := NoiseBank.lat3(lat, lx, ly + 1, lz)
				if above <= thr[ly + 1]:
					blocks[i] = int(ids["surface"])
				elif v < thr[ly] + 0.06:
					blocks[i] = int(ids["subsurface"])
				else:
					blocks[i] = int(ids["stone"])
	return blocks
