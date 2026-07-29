## Pass 3 and 4: the underground. Caves, then the things worth digging for.
##
## Every feature here is chosen for **3D coherence** — a cave system that only
## reads from one axis is a bug in this game, because the player rotates the
## camera through four viewing planes:
##
## * *worm tunnels* — the intersection of two 3D noise fields, so they twist
##   through all three axes and stay traversable from any view;
## * *cheese chambers* — blobby rooms, isotropic by construction;
## * *vertical shafts* — chimneys punched from the surface down; a column looks
##   identical from all four sides and always reads as a route;
## * *ravines* — carved along a curving 2D ridge line, so the chasm snakes
##   across the map diagonally instead of running down one axis;
## * *lava tubes* threading the mantle;
## * *hidden passages* — deliberately axis-aligned corridors one voxel wide.
##   In the view where a corridor runs into the screen it is just a dark hole
##   you can squeeze into with `PgUp`/`PgDn`; flip 90° and the same corridor is
##   a walkable tunnel. This is the generator's main "reward for flipping".
##
## Cell-grid features (shafts, passages, ores, geodes) are generated from the
## neighbourhood of cells around a chunk, never from the chunk itself, so the
## result never depends on which chunk happened to be built first.
class_name CaveGen
extends RefCounted

const SALT_SHAFT := 0x5AF7
const SALT_PASSAGE := 0x9A55
const SALT_ORE := 0x0DE0
const SALT_GEODE := 0x6E0D

## Cell sizes are powers of two so the grids tile the planet exactly (planet
## sizes are multiples of 32 in practice); otherwise features would be cut in
## half at the wrap seam.
const SHAFT_CELL := 32
const PASSAGE_CELL := 32
const PASSAGE_CELL_Y := 16
const PASSAGE_MAX_LEN := 48
const ORE_CELL := 16
const GEODE_CELL := 64
const GEODE_CELL_Y := 32

var noise: NoiseBank
var shaper: TerrainShaper
var cave_scale := 1.0
var lava_level := 26
var lava_tubes := true

var _id_lava := 0
var _id_water := 0
var _id_bedrock := 0
var _ores: Array[Dictionary] = []
var _gem_ids: PackedInt32Array = PackedInt32Array()
var _geode_shell := 0
## Per-ore multiplier from the planet meta (`ore_bias`), keyed by block name.
var _ore_bias: Dictionary = {}

## The chunk's voxel array while a pass is running. Kept as a member on purpose:
## GDScript's packed arrays are copy-on-write, so handing one to a helper that
## writes a single voxel would clone 16 KB per call. Writing through a member
## keeps every write in place.
var _buf: PackedInt32Array = PackedInt32Array()


func configure(p_noise: NoiseBank, p_shaper: TerrainShaper, meta: Dictionary, profile: Dictionary) -> void:
	noise = p_noise
	shaper = p_shaper
	cave_scale = float(meta.get("caves", meta.get("cave_density", profile.get("cave", 1.0))))
	_ore_bias = {}
	var bias_in: Dictionary = meta.get("ore_bias", {})
	for k in bias_in:
		_ore_bias[StringName(k)] = float(bias_in[k])
	lava_level = clampi(int(meta.get("lava_level", 26)), 4, 80)
	lava_tubes = bool(meta.get("lava_tubes", true))
	_id_lava = Biome.block_id(&"lava", &"lava")
	_id_water = Biome.block_id(&"water", &"water")
	_id_bedrock = Biome.block_id(&"bedrock", &"stone")
	_geode_shell = Biome.first_block([&"geode_shell", &"marble", &"limestone"], &"stone")
	_gem_ids = PackedInt32Array()
	for n: StringName in [&"crystal_blue", &"crystal_violet", &"crystal_ember", &"amethyst_ore", &"topaz_ore"]:
		if Blocks.has(n):
			_gem_ids.append(Blocks.id(n))
	if _gem_ids.is_empty():
		_gem_ids.append(Biome.block_id(&"stone", &"stone"))
	_build_ore_table(float(meta.get("threat", 1)), StringName(meta.get("type", &"forest")))


## Ore progression, mirroring the tier ladder that `content/blocks/11_ores.gd`
## documents: tier 0 needs a stone pick, tier 6 needs a solarium-class one. The
## `max_y` bands turn that ladder into a *depth* ladder, so digging deeper is
## the same thing as climbing the tech tree. `chance` is rolled per attempt per
## 16³ cell, then scaled by the biome's `ore_weights` and the planet's
## `ore_bias`.
func _build_ore_table(threat: float, planet_type: StringName) -> void:
	var t := clampf(threat, 1.0, 10.0)
	_ores = []
	#        name                 tier  min_y max_y tries  size    chance
	# tier 0 — surface strata, stone pickaxe
	_add_ore(&"coal_ore",            0,    4,  150,    3,  4, 9,  0.55)
	_add_ore(&"copper_ore",          0,    4,  140,    3,  3, 8,  0.50)
	_add_ore(&"iron_ore",            0,    4,  120,    3,  3, 7,  0.45)
	_add_ore(&"tin_ore",             0,    4,  120,    2,  3, 6,  0.36)
	_add_ore(&"salt_deposit",        0,    6,  110,    2,  3, 7,  0.22)
	# tier 1 — iron pickaxe
	_add_ore(&"lead_ore",            1,    4,   92,    2,  3, 6,  0.30)
	_add_ore(&"silver_ore",          1,    4,   88,    2,  3, 6,  0.30)
	_add_ore(&"gold_ore",            1,    4,   72,    2,  2, 5,  0.26)
	_add_ore(&"silicon_ore",         1,    4,   80,    2,  2, 5,  0.24)
	_add_ore(&"sulphur_ore",         1,    4,   68,    2,  2, 5,  0.22)
	# tier 2 — tungsten pickaxe
	_add_ore(&"tungsten_ore",        2,    4,   64,    2,  2, 5,  0.20)
	_add_ore(&"titanium_ore",        2,    4,   58,    2,  2, 5,  0.20)
	_add_ore(&"platinum_ore",        2,    4,   50,    2,  2, 4,  0.16)
	_add_ore(&"amethyst_ore",        2,    3,   46,    1,  1, 3,  0.12)
	_add_ore(&"topaz_ore",           2,    3,   46,    1,  1, 3,  0.12)
	# tier 3 — titanium pickaxe
	_add_ore(&"durasteel_ore",       3,    2,   40,    2,  2, 4,  0.14)
	_add_ore(&"uranium_ore",         3,    2,   40,    2,  2, 4,  0.12 + 0.02 * t)
	_add_ore(&"diamond_ore",         3,    2,   32,    2,  1, 4,  0.10)
	_add_ore(&"ruby_ore",            3,    2,   34,    1,  1, 3,  0.09)
	_add_ore(&"sapphire_ore",        3,    2,   34,    1,  1, 3,  0.09)
	_add_ore(&"emerald_ore",         3,    2,   34,    1,  1, 3,  0.09)
	# tier 4 — durasteel pickaxe
	_add_ore(&"plutonium_ore",       4,    2,   28,    2,  1, 3,  0.08 + 0.015 * t)
	_add_ore(&"aegisalt_ore",        4,    2,   30,    1,  2, 4,  0.07)
	_add_ore(&"ferozium_ore",        4,    2,   28,    1,  2, 4,  0.07)
	_add_ore(&"violium_ore",         4,    2,   26,    1,  1, 3,  0.06)
	# tier 5 — aegisalt-class pickaxe
	_add_ore(&"rubium_ore",          5,    2,   20,    1,  1, 3,  0.05)
	_add_ore(&"solarium_ore",        5,    2,   18,    1,  1, 3,  0.04)
	_add_ore(&"prisilite_ore",       5,    2,   18,    1,  1, 3,  0.04)
	# tier 6 — the mantle itself
	_add_ore(&"core_fragment_ore",   6,    1,   12,    2,  2, 5,  0.30)
	# Erchius is the moon's signature resource and vanishingly rare elsewhere.
	if planet_type == &"moon":
		_add_ore(&"erchius_crystal", 2,    2,  130,    2,  2, 5,  0.24)
	else:
		_add_ore(&"erchius_crystal", 2,    2,   24,    1,  1, 3,  0.05)


func _add_ore(name: StringName, tier: int, min_y: int, max_y: int, tries: int,
		size_min: int, size_max: int, chance: float) -> void:
	if not Blocks.has(name):
		return   # the block agent has not defined this ore yet — skip silently
	_ores.append({
		"id": Blocks.id(name), "name": name, "tier": tier,
		"min_y": min_y, "max_y": max_y, "tries": tries,
		"size_min": size_min, "size_max": size_max, "chance": chance,
	})


## The ore table as plain data, for the item/crafting agents.
func ore_table() -> Array[Dictionary]:
	return _ores


# ================================================================== carving
## Hollow out `chunk`. Runs after the shaper, before ores.
func carve(chunk: Chunk) -> void:
	if chunk.empty or cave_scale <= 0.0:
		return
	var o := chunk.origin()
	var max_h := 0
	for lz in Const.CHUNK_SIZE:
		for lx in Const.CHUNK_SIZE:
			max_h = maxi(max_h, shaper.height_at(o.x + lx, o.z + lz))
	if o.y > max_h:
		return

	var worm_a := noise.lattice3(noise.cave_worm_a, o, 1.0, 1.35, 1.0)
	var worm_b := noise.lattice3(noise.cave_worm_b, o, 1.0, 1.35, 1.0)
	var cheese := noise.lattice3(noise.cave_cheese, o, 1.0, 1.15, 1.0)
	var tubes := PackedFloat32Array()
	if lava_tubes and o.y <= shaper.mantle_y + 20:
		tubes = noise.lattice3(noise.lava_tube, o, 1.0, 1.2, 1.0)
	var shafts := _shafts_near(o)

	_buf = chunk.blocks
	var lava_cells: Array[int] = []

	for lz in Const.CHUNK_SIZE:
		var wz := o.z + lz
		for lx in Const.CHUNK_SIZE:
			var wx := o.x + lx
			var h := shaper.height_at(wx, wz)
			if o.y > h:
				continue
			var b := BiomeTable.by_index(shaper.biome_index_at(wx, wz))
			var bias := cave_scale * b.cave_bias
			if bias <= 0.0:
				continue
			var flooded := h < shaper.sea_level     # keep the seabed sealed
			var shaft_floor := _shaft_floor(shafts, wx, wz)
			var ravine := _ravine_strength(wx, wz)
			var crust := 9 if flooded else 4
			for ly in Const.CHUNK_SIZE:
				var i := (ly << 8) | (lz << 4) | lx
				var cur := _buf[i]
				if cur == Const.AIR or cur == _id_bedrock:
					continue
				var y := o.y + ly
				if y <= 2:
					continue
				if y > h - crust:
					# Only shafts and ravines are allowed to breach the crust,
					# which is what makes them readable entrances from outside.
					if not flooded and shaft_floor > 0 and y >= shaft_floor:
						_buf[i] = Const.AIR
					elif not flooded and ravine > 0.0 and y < h - 1:
						_buf[i] = Const.AIR
					continue
				var depth_t := clampf(float(h - y) / 90.0, 0.0, 1.0)
				var lid := 0
				var carved := false
				# 1. cheese chambers, opening up with depth
				if NoiseBank.lat3(cheese, lx, ly, lz) > lerpf(0.50, 0.32, depth_t) / maxf(bias, 0.05):
					carved = true
				# 2. worm tunnels: two fields near zero at once = a 3D tube
				if not carved and absf(NoiseBank.lat3(worm_a, lx, ly, lz)) < 0.085 * bias:
					if absf(NoiseBank.lat3(worm_b, lx, ly, lz)) < 0.085 * bias:
						carved = true
				# 3. shafts and ravines
				if not carved and shaft_floor > 0 and y >= shaft_floor:
					carved = true
				if not carved and ravine > 0.0 and y > 12 and y < h - 2:
					carved = true
				# 4. lava tubes near the mantle
				if not carved and not tubes.is_empty() and y > 4 and y <= shaper.mantle_y + 12:
					if absf(NoiseBank.lat3(tubes, lx, ly, lz)) < 0.06:
						carved = true
						lid = _id_lava
				if not carved:
					continue
				if lid != 0 and y <= lava_level + 10:
					_buf[i] = lid
					lava_cells.append(i)
				else:
					_buf[i] = Const.AIR

	_carve_passages(o)
	chunk.blocks = _buf
	_buf = PackedInt32Array()
	for i: int in lava_cells:
		chunk.set_liquid(i, Const.MAX_LIQUID)
	chunk.recount()


# ---------------------------------------------------------------- shafts
## Shaft anchors whose radius could reach into this chunk, as
## `Vector4i(x, z, radius, floor_y)`.
func _shafts_near(o: Vector3i) -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	var c0x := NoiseBank.fdiv(o.x - 4, SHAFT_CELL)
	var c0z := NoiseBank.fdiv(o.z - 4, SHAFT_CELL)
	var c1x := NoiseBank.fdiv(o.x + Const.CHUNK_SIZE + 4, SHAFT_CELL)
	var c1z := NoiseBank.fdiv(o.z + Const.CHUNK_SIZE + 4, SHAFT_CELL)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var h := _cell_hash(cx * SHAFT_CELL, 0, cz * SHAFT_CELL, SALT_SHAFT)
			if (absi(h) % 100) >= 34:
				continue
			var sx := cx * SHAFT_CELL + 4 + (absi(h >> 3) % (SHAFT_CELL - 8))
			var sz := cz * SHAFT_CELL + 4 + (absi(h >> 11) % (SHAFT_CELL - 8))
			var r := 1 + (absi(h >> 19) % 2)
			# Depth comes from a smooth field so neighbouring shafts bottom out
			# at related depths and tend to meet the same cave layer.
			var depth_n := NoiseBank.unit(noise.n2(noise.cave_shaft, float(sx), float(sz)))
			var floor_y := 12 + int(depth_n * 44.0) + (absi(h >> 23) % 8)
			out.append(Vector4i(sx, sz, r, floor_y))
	return out


## Lowest y of the shaft covering this column, or 0 when there is none.
func _shaft_floor(shafts: Array[Vector4i], x: int, z: int) -> int:
	for s: Vector4i in shafts:
		var dx := wrapi(x - s.x, -(shaper.size_x >> 1), shaper.size_x >> 1)
		var dz := wrapi(z - s.y, -(shaper.size_z >> 1), shaper.size_z >> 1)
		if dx * dx + dz * dz <= s.z * s.z:
			return s.w
	return 0


## >0 inside a ravine. The ridge line curves through XZ, so the chasm crosses
## the map diagonally and stays legible from every plane.
func _ravine_strength(x: int, z: int) -> float:
	var w := noise.warp_xz(float(x), 0.0, float(z), 18.0)
	var v := 1.0 - absf(noise.n2(noise.ravine, float(x) + w.x, float(z) + w.y))
	if v < 0.991:
		return 0.0
	return (v - 0.991) / 0.009


# ------------------------------------------------------------ hidden passages
func _carve_passages(o: Vector3i) -> void:
	var cx0 := NoiseBank.fdiv(o.x - PASSAGE_MAX_LEN - PASSAGE_CELL, PASSAGE_CELL)
	var cx1 := NoiseBank.fdiv(o.x + Const.CHUNK_SIZE + PASSAGE_MAX_LEN, PASSAGE_CELL)
	var cz0 := NoiseBank.fdiv(o.z - PASSAGE_MAX_LEN - PASSAGE_CELL, PASSAGE_CELL)
	var cz1 := NoiseBank.fdiv(o.z + Const.CHUNK_SIZE + PASSAGE_MAX_LEN, PASSAGE_CELL)
	var cy0 := NoiseBank.fdiv(o.y - PASSAGE_CELL_Y, PASSAGE_CELL_Y)
	var cy1 := NoiseBank.fdiv(o.y + Const.CHUNK_SIZE, PASSAGE_CELL_Y)
	for cy in range(cy0, cy1 + 1):
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				_carve_one_passage(o, cx, cy, cz)
	return


func _carve_one_passage(o: Vector3i, cx: int, cy: int, cz: int) -> void:
	var h := _cell_hash(cx * PASSAGE_CELL, cy * PASSAGE_CELL_Y, cz * PASSAGE_CELL, SALT_PASSAGE)
	if (absi(h) % 100) >= 30:
		return
	var py := cy * PASSAGE_CELL_Y + (absi(h >> 19) % PASSAGE_CELL_Y)
	if py < 6 or py + 1 - o.y < 0 or py - o.y > 15:
		return
	var px := cx * PASSAGE_CELL + (absi(h >> 3) % PASSAGE_CELL)
	var pz := cz * PASSAGE_CELL + (absi(h >> 11) % PASSAGE_CELL)
	if py > shaper.height_at(px, pz) - 8:
		return
	var along_x := ((h >> 27) & 1) == 1
	var dir := 1 if ((h >> 29) & 1) == 1 else -1
	var length := 18 + (absi(h >> 5) % (PASSAGE_MAX_LEN - 18))
	# Bounding-box reject before touching any voxels.
	var ex := px + (length * dir if along_x else 0)
	var ez := pz + (0 if along_x else length * dir)
	if not _span_hits(mini(px, ex), maxi(px, ex), o.x, shaper.size_x):
		return
	if not _span_hits(mini(pz, ez), maxi(pz, ez), o.z, shaper.size_z):
		return
	for step in length:
		var wx := px + (step * dir if along_x else 0)
		var wz := pz + (0 if along_x else step * dir)
		_set_air(o, wx, py, wz)
		_set_air(o, wx, py + 1, wz)
	return


## Does a world-space span overlap a chunk that starts at `origin`? Wrap-aware.
func _span_hits(lo: int, hi: int, origin: int, size: int) -> bool:
	var d_lo := wrapi(lo - origin, -(size >> 1), size >> 1)
	var d_hi := d_lo + (hi - lo)
	return d_hi >= 0 and d_lo <= 15


func _set_air(o: Vector3i, wx: int, wy: int, wz: int) -> void:
	var i := _local_index(o, wx, wy, wz)
	if i < 0 or _buf[i] == _id_bedrock:
		return
	_buf[i] = Const.AIR
	return


# ====================================================================== ores
## Ore veins and blobs, anchored to a 16³ cell grid and generated from the
## 3x3x3 neighbourhood so veins cross chunk borders seamlessly.
func place_ores(chunk: Chunk) -> void:
	if chunk.empty or _ores.is_empty():
		return
	var o := chunk.origin()
	_buf = chunk.blocks
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				_ores_for_cell(o, o.x + dx * ORE_CELL,
					o.y + dy * ORE_CELL, o.z + dz * ORE_CELL)
	chunk.blocks = _buf
	_buf = PackedInt32Array()


func _ores_for_cell(o: Vector3i, cx: int, cy: int, cz: int) -> void:
	if cy + ORE_CELL < 0 or cy >= Const.WORLD_HEIGHT:
		return
	var b := BiomeTable.by_index(shaper.biome_index_at(cx + 8, cz + 8))
	var richness := 1.0 + noise.n2(noise.ore_density, float(cx), float(cz)) * 0.55
	for oi in _ores.size():
		var ore: Dictionary = _ores[oi]
		if cy + ORE_CELL < int(ore["min_y"]) or cy > int(ore["max_y"]):
			continue
		var weight: float = float(b.ore_weights.get(ore["name"], 1.0)) * richness \
			* float(_ore_bias.get(ore["name"], 1.0))
		for t in int(ore["tries"]):
			var hh := _cell_hash(cx + oi * 131, cy + t * 17, cz, SALT_ORE)
			if float(absi(hh) % 1000) * 0.001 > float(ore["chance"]) * weight:
				continue
			var vy := cy + (absi(hh >> 9) % ORE_CELL)
			if vy < int(ore["min_y"]) or vy > int(ore["max_y"]):
				continue
			var vx := cx + (absi(hh >> 3) % ORE_CELL)
			var vz := cz + (absi(hh >> 15) % ORE_CELL)
			var span: int = maxi(1, int(ore["size_max"]) - int(ore["size_min"]) + 1)
			var size: int = int(ore["size_min"]) + absi(hh >> 21) % span
			_place_vein(o, vx, vy, vz, size, int(ore["id"]), hh)
	return


## A vein is a short random walk with a small blob at each step, so it reads as
## a streak from every direction rather than as a sphere.
func _place_vein(o: Vector3i, x: int, y: int, z: int,
		size: int, id: int, seed_h: int) -> void:
	var px := x
	var py := y
	var pz := z
	for s in maxi(size, 1):
		var hh := NoiseBank.hash_i(seed_h, s, id, SALT_ORE + 7)
		var radius := 1 if size <= 3 else (1 + (absi(hh) % 2))
		_blob(o, px, py, pz, radius, id)
		px += (absi(hh >> 4) % 3) - 1
		py += (absi(hh >> 8) % 3) - 1
		pz += (absi(hh >> 12) % 3) - 1
	return


func _blob(o: Vector3i, x: int, y: int, z: int, r: int, id: int) -> void:
	var r2 := r * r + 1
	for dy in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy + dz * dz > r2:
					continue
				_replace_stone(o, x + dx, y + dy, z + dz, id)
	return


func _replace_stone(o: Vector3i, wx: int, wy: int, wz: int, id: int) -> void:
	if wy < 2:
		return
	var i := _local_index(o, wx, wy, wz)
	if i < 0:
		return
	var cur := _buf[i]
	if cur == Const.AIR or cur == _id_bedrock or cur == _id_lava or cur == _id_water:
		return
	if not Blocks.is_solid(cur):
		return
	if wy > shaper.height_at(wx, wz) - 3:
		return      # never seed ore into the soil layer or a cliff face
	_buf[i] = id
	return


# ==================================================================== geodes
## Big hollow gem chambers: a shell, a crystal lining and an air pocket. Rare,
## always underground, and one of the few reasons to dig sideways on purpose.
func place_geodes(chunk: Chunk) -> void:
	if chunk.empty:
		return
	var o := chunk.origin()
	_buf = chunk.blocks
	var cx0 := NoiseBank.fdiv(o.x - GEODE_CELL, GEODE_CELL)
	var cz0 := NoiseBank.fdiv(o.z - GEODE_CELL, GEODE_CELL)
	var cy0 := NoiseBank.fdiv(o.y - GEODE_CELL_Y, GEODE_CELL_Y)
	for cy in range(cy0, cy0 + 3):
		for cz in range(cz0, cz0 + 3):
			for cx in range(cx0, cx0 + 3):
				_geode_for_cell(o, cx, cy, cz)
	chunk.blocks = _buf
	_buf = PackedInt32Array()


func _geode_for_cell(o: Vector3i, cx: int, cy: int, cz: int) -> void:
	var h := _cell_hash(cx * GEODE_CELL, cy * GEODE_CELL_Y, cz * GEODE_CELL, SALT_GEODE)
	if (absi(h) % 100) >= 16:
		return
	var r := 4 + (absi(h >> 25) % 5)
	var gy := cy * GEODE_CELL_Y + (absi(h >> 19) % GEODE_CELL_Y)
	if gy - r - 1 - o.y > 15 or gy + r + 1 - o.y < 0:
		return
	var gx := cx * GEODE_CELL + (absi(h >> 3) % GEODE_CELL)
	var gz := cz * GEODE_CELL + (absi(h >> 11) % GEODE_CELL)
	if gy - r < 4 or gy + r > shaper.height_at(gx, gz) - 8:
		return
	var gem: int = _gem_ids[absi(h >> 7) % _gem_ids.size()]
	var r2 := float(r * r)
	var hollow := r2 - float(r) * 2.4
	var shell := r2 + float(r) * 2.0
	for dy in range(-r - 1, r + 2):
		for dz in range(-r - 1, r + 2):
			for dx in range(-r - 1, r + 2):
				var d2 := float(dx * dx + dy * dy + dz * dz)
				if d2 > shell:
					continue
				var id := _geode_shell
				if d2 < hollow:
					id = Const.AIR
				elif d2 < r2:
					# Thinned crystal lining so the shell still shows through.
					id = gem if (absi(NoiseBank.hash_i(gx + dx, gy + dy, gz + dz, SALT_GEODE + 3)) % 10) < 7 else _geode_shell
				_force_set(o, gx + dx, gy + dy, gz + dz, id)
	return


func _force_set(o: Vector3i, wx: int, wy: int, wz: int, id: int) -> void:
	if wy < 2:
		return
	var i := _local_index(o, wx, wy, wz)
	if i < 0 or _buf[i] == _id_bedrock:
		return
	_buf[i] = id
	return


# =================================================================== helpers
## Local voxel index for a world position, or -1 when it is outside the chunk.
## Wrap-aware, so features that straddle the planet seam still land correctly.
func _local_index(o: Vector3i, wx: int, wy: int, wz: int) -> int:
	if wy < 0 or wy >= Const.WORLD_HEIGHT:
		return -1
	var ly := wy - o.y
	if ly < 0 or ly > 15:
		return -1
	var lx := wrapi(wx - o.x, -(shaper.size_x >> 1), shaper.size_x >> 1)
	if lx < 0 or lx > 15:
		return -1
	var lz := wrapi(wz - o.z, -(shaper.size_z >> 1), shaper.size_z >> 1)
	if lz < 0 or lz > 15:
		return -1
	return (ly << 8) | (lz << 4) | lx


## Hash a cell anchor after wrapping it into the planet, so cell grids line up
## across the X/Z seam instead of producing half-features there.
func _cell_hash(x: int, y: int, z: int, salt: int) -> int:
	return NoiseBank.hash_i(posmod(x, shaper.size_x), y, posmod(z, shaper.size_z), salt)
