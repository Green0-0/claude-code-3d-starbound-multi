## Every `FastNoiseLite` the planet generator uses, configured and seeded in one
## place so that field frequencies stay comparable and nothing is ever seeded
## twice with the same number.
##
## Two things every caller should know:
##
## * **Everything wraps.** Planets are toruses on X and Z, so raw noise would
##   show a seam. `n2()` / `n3()` cross-fade the sample with its mirror one
##   planet-width away inside a margin band, which is continuous across the
##   seam and costs extra samples only near it.
## * **Everything is pure.** No sample depends on generation order, only on
##   (seed, world coordinate). `hash_i()` / `rand01()` give the same guarantee
##   for the discrete decisions (which cell holds a tree, which ore rolls).
class_name NoiseBank
extends RefCounted

## Width of the seam cross-fade band, in blocks, at each planet edge.
const WRAP_MARGIN := 96.0

# ------------------------------------------------------------ terrain shaping
var continent: FastNoiseLite      ## broad land/sea mass, drives base elevation
var ridge: FastNoiseLite          ## mountain spines (use through `ridged2`)
var detail: FastNoiseLite         ## small surface roughness
var plateau: FastNoiseLite        ## where the heightfield gets terraced
var river: FastNoiseLite          ## river network (ridge lines carved down)
var cliff_warp: FastNoiseLite     ## domain-warp offsets for continent/ridge
var overhang: FastNoiseLite       ## 3D subtraction that undercuts cliffs
var island: FastNoiseLite         ## 3D blobs for floating islands
var strata: FastNoiseLite         ## wobble applied to the depth stratum bands

# ---------------------------------------------------------------- underground
var cave_worm_a: FastNoiseLite    ## first tunnel field  (|n| < t)
var cave_worm_b: FastNoiseLite    ## second tunnel field (intersection = worm)
var cave_cheese: FastNoiseLite    ## blobby chambers
var cave_shaft: FastNoiseLite     ## 2D field for vertical shafts
var ravine: FastNoiseLite         ## 2D ridge lines for canyons
var lava_tube: FastNoiseLite      ## worm field restricted to the mantle

# -------------------------------------------------------------- ores / biomes
var ore_density: FastNoiseLite    ## regional richness multiplier
var geode: FastNoiseLite          ## rare gem-cluster hot spots
var temperature: FastNoiseLite
var humidity: FastNoiseLite
var scatter: FastNoiseLite        ## cheap decoration jitter

var seed_value := 0
var size_x := 0.0
var size_z := 0.0
var margin := WRAP_MARGIN


func _init(p_seed: int = 0, p_size_x: int = 512, p_size_z: int = 512, roughness: float = 1.0) -> void:
	configure(p_seed, p_size_x, p_size_z, roughness)


## Rebuild every field for a new planet. `roughness` scales the frequency of the
## shaping fields: <1 gives long lazy landmasses, >1 gives broken alien terrain.
func configure(p_seed: int, p_size_x: int, p_size_z: int, roughness: float = 1.0) -> void:
	seed_value = p_seed
	size_x = float(maxi(p_size_x, 0))
	size_z = float(maxi(p_size_z, 0))
	margin = minf(WRAP_MARGIN, minf(size_x, size_z) * 0.25)
	var r := clampf(roughness, 0.4, 2.5)

	continent = _make(1, FastNoiseLite.TYPE_SIMPLEX, 0.0016 * r, 5, 0.5, 2.0)
	ridge = _make(2, FastNoiseLite.TYPE_SIMPLEX, 0.0042 * r, 4, 0.55, 2.1)
	detail = _make(3, FastNoiseLite.TYPE_SIMPLEX, 0.020 * r, 3, 0.5, 2.0)
	plateau = _make(4, FastNoiseLite.TYPE_SIMPLEX, 0.0031, 2, 0.5, 2.0)
	river = _make(5, FastNoiseLite.TYPE_SIMPLEX, 0.0021, 2, 0.5, 2.0)
	strata = _make(6, FastNoiseLite.TYPE_SIMPLEX, 0.011, 2, 0.5, 2.0)

	# Domain warp source. Sampled directly (not via `domain_warp_enabled`) so the
	# same offsets can be reused by several fields and stay wrap-corrected.
	cliff_warp = _make(7, FastNoiseLite.TYPE_SIMPLEX, 0.0055, 3, 0.5, 2.0)

	overhang = _make(8, FastNoiseLite.TYPE_SIMPLEX, 0.036 * r, 3, 0.5, 2.1)
	island = _make(9, FastNoiseLite.TYPE_SIMPLEX, 0.021, 3, 0.5, 2.0)

	cave_worm_a = _make(11, FastNoiseLite.TYPE_SIMPLEX, 0.0125, 2, 0.5, 2.0)
	cave_worm_b = _make(12, FastNoiseLite.TYPE_SIMPLEX, 0.0125, 2, 0.5, 2.0)
	cave_cheese = _make(13, FastNoiseLite.TYPE_SIMPLEX, 0.028, 3, 0.55, 2.1)
	cave_shaft = _make(14, FastNoiseLite.TYPE_SIMPLEX, 0.017, 2, 0.5, 2.0)
	ravine = _make(15, FastNoiseLite.TYPE_SIMPLEX, 0.0038, 2, 0.5, 2.0)
	lava_tube = _make(16, FastNoiseLite.TYPE_SIMPLEX, 0.019, 2, 0.5, 2.0)

	ore_density = _make(21, FastNoiseLite.TYPE_SIMPLEX, 0.045, 2, 0.5, 2.0)
	geode = _make(22, FastNoiseLite.TYPE_CELLULAR, 0.020, 1, 0.5, 2.0)
	geode.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	geode.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	geode.cellular_jitter = 1.0

	temperature = _make(31, FastNoiseLite.TYPE_SIMPLEX, 0.0013, 3, 0.5, 2.0)
	humidity = _make(32, FastNoiseLite.TYPE_SIMPLEX, 0.0015, 3, 0.5, 2.0)
	scatter = _make(33, FastNoiseLite.TYPE_VALUE, 0.35, 1, 0.5, 2.0)

	# A little intrinsic warping on the biome fields keeps their borders from
	# looking like contour lines on a map.
	_warp(temperature, 41, 30.0, 0.0035)
	_warp(humidity, 42, 30.0, 0.0035)
	_warp(cave_cheese, 43, 12.0, 0.02)
	_warp(ridge, 44, 22.0, 0.006)


func _make(salt: int, type: int, freq: float, octaves: int, gain: float, lacunarity: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = hash_i(seed_value, salt * 7919, salt, 0x5EED)
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = maxi(octaves, 1)
	n.fractal_gain = gain
	n.fractal_lacunarity = lacunarity
	return n


## Turn on FastNoiseLite's own domain warping for a field. `salt` nudges the
## field's sampling offset so two warped fields never fold identically.
func _warp(n: FastNoiseLite, salt: int, amplitude: float, freq: float) -> void:
	n.domain_warp_enabled = true
	n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	n.domain_warp_amplitude = amplitude
	n.domain_warp_frequency = freq
	n.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_INDEPENDENT
	n.domain_warp_fractal_octaves = 2
	n.offset = Vector3(float(salt * 37), 0.0, float(salt * 71))


# ============================================================ wrapped sampling
## 2D sample that is continuous across the planet's X/Z seams.
func n2(n: FastNoiseLite, x: float, z: float) -> float:
	if size_x <= 0.0 or margin <= 0.0:
		return n.get_noise_2d(x, z)
	var xa := x
	var wx := 1.0
	if x < margin:
		xa = x + size_x
		wx = 0.5 + 0.5 * (x / margin)
	elif x > size_x - margin:
		xa = x - size_x
		wx = 0.5 + 0.5 * ((size_x - x) / margin)
	var za := z
	var wz := 1.0
	if z < margin:
		za = z + size_z
		wz = 0.5 + 0.5 * (z / margin)
	elif z > size_z - margin:
		za = z - size_z
		wz = 0.5 + 0.5 * ((size_z - z) / margin)
	if wx >= 1.0 and wz >= 1.0:
		return n.get_noise_2d(x, z)
	var v00 := n.get_noise_2d(x, z)
	var v10 := n.get_noise_2d(xa, z)
	var v01 := n.get_noise_2d(x, za)
	var v11 := n.get_noise_2d(xa, za)
	return lerpf(lerpf(v11, v01, wx), lerpf(v10, v00, wx), wz)


## 3D sample that is continuous across the planet's X/Z seams. Y never wraps.
func n3(n: FastNoiseLite, x: float, y: float, z: float) -> float:
	if size_x <= 0.0 or margin <= 0.0:
		return n.get_noise_3d(x, y, z)
	var xa := x
	var wx := 1.0
	if x < margin:
		xa = x + size_x
		wx = 0.5 + 0.5 * (x / margin)
	elif x > size_x - margin:
		xa = x - size_x
		wx = 0.5 + 0.5 * ((size_x - x) / margin)
	var za := z
	var wz := 1.0
	if z < margin:
		za = z + size_z
		wz = 0.5 + 0.5 * (z / margin)
	elif z > size_z - margin:
		za = z - size_z
		wz = 0.5 + 0.5 * ((size_z - z) / margin)
	if wx >= 1.0 and wz >= 1.0:
		return n.get_noise_3d(x, y, z)
	var v00 := n.get_noise_3d(x, y, z)
	var v10 := n.get_noise_3d(xa, y, z)
	var v01 := n.get_noise_3d(x, y, za)
	var v11 := n.get_noise_3d(xa, y, za)
	return lerpf(lerpf(v11, v01, wx), lerpf(v10, v00, wx), wz)


# ==================================================================== helpers
## Ridged transform: 0 in the valleys, 1 along the spines. Squared so the ridges
## stay thin and the flats stay flat.
func ridged(n: FastNoiseLite, x: float, z: float) -> float:
	var v := 1.0 - absf(n2(n, x, z))
	return v * v


## 3D ridged variant, used for tunnel walls and lava tubes.
func ridged3(n: FastNoiseLite, x: float, y: float, z: float) -> float:
	var v := 1.0 - absf(n3(n, x, y, z))
	return v * v


## Domain-warp offset for a column: add it to a sample position to turn smooth
## noise borders into folded, geological-looking ones.
func warp_xz(x: float, y: float, z: float, amount: float = 24.0) -> Vector2:
	var ox := n3(cliff_warp, x, y * 0.35, z)
	var oz := n3(cliff_warp, x + 411.0, y * 0.35, z - 137.0)
	return Vector2(ox * amount, oz * amount)


## Remap a -1..1 noise value to 0..1.
static func unit(v: float) -> float:
	return clampf(v * 0.5 + 0.5, 0.0, 1.0)


# =============================================================== lattice cache
## 3D noise is far too expensive to evaluate per voxel in GDScript, so the
## volume passes sample a 9x9x9 lattice over the chunk (every second voxel,
## inclusive of the far face) and trilinearly interpolate. Eight times fewer
## noise calls, and the fields it is used for are smooth anyway.
const LAT_N := 9
const LAT_STEP := 2

## Sample `n` over one chunk. `sx`/`sy`/`sz` scale world coordinates before
## sampling, letting one noise field serve several feature sizes.
func lattice3(n: FastNoiseLite, o: Vector3i, sx: float, sy: float, sz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LAT_N * LAT_N * LAT_N)
	var k := 0
	for yi in LAT_N:
		var wy := float(o.y + yi * LAT_STEP) * sy
		for zi in LAT_N:
			var wz := float(o.z + zi * LAT_STEP)
			for xi in LAT_N:
				var wx := float(o.x + xi * LAT_STEP)
				out[k] = n3(n, wx * sx, wy, wz * sz)
				k += 1
	return out


## Sample `n` over one chunk's columns (9x9).
func lattice2(n: FastNoiseLite, o: Vector3i, sx: float, sz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LAT_N * LAT_N)
	var k := 0
	for zi in LAT_N:
		var wz := float(o.z + zi * LAT_STEP)
		for xi in LAT_N:
			var wx := float(o.x + xi * LAT_STEP)
			out[k] = n2(n, wx * sx, wz * sz)
			k += 1
	return out


## Trilinear read of a `lattice3` at chunk-local voxel coordinates (0..16).
static func lat3(l: PackedFloat32Array, lx: int, ly: int, lz: int) -> float:
	var xi := lx >> 1
	var yi := ly >> 1
	var zi := lz >> 1
	var fx := float(lx & 1) * 0.5
	var fy := float(ly & 1) * 0.5
	var fz := float(lz & 1) * 0.5
	var xi1 := mini(xi + 1, LAT_N - 1)
	var yi1 := mini(yi + 1, LAT_N - 1)
	var zi1 := mini(zi + 1, LAT_N - 1)
	var b00 := (yi * LAT_N + zi) * LAT_N
	var b01 := (yi * LAT_N + zi1) * LAT_N
	var b10 := (yi1 * LAT_N + zi) * LAT_N
	var b11 := (yi1 * LAT_N + zi1) * LAT_N
	var c00 := lerpf(l[b00 + xi], l[b00 + xi1], fx)
	var c01 := lerpf(l[b01 + xi], l[b01 + xi1], fx)
	var c10 := lerpf(l[b10 + xi], l[b10 + xi1], fx)
	var c11 := lerpf(l[b11 + xi], l[b11 + xi1], fx)
	return lerpf(lerpf(c00, c01, fz), lerpf(c10, c11, fz), fy)


## Bilinear read of a `lattice2` at chunk-local column coordinates (0..16).
static func lat2(l: PackedFloat32Array, lx: int, lz: int) -> float:
	var xi := lx >> 1
	var zi := lz >> 1
	var fx := float(lx & 1) * 0.5
	var fz := float(lz & 1) * 0.5
	var xi1 := mini(xi + 1, LAT_N - 1)
	var zi1 := mini(zi + 1, LAT_N - 1)
	var a := lerpf(l[zi * LAT_N + xi], l[zi * LAT_N + xi1], fx)
	var b := lerpf(l[zi1 * LAT_N + xi], l[zi1 * LAT_N + xi1], fx)
	return lerpf(a, b, fz)


# ================================================================ pure hashing
## Floor division — GDScript's `/` truncates toward zero, which puts a seam in
## every cell grid at the origin.
static func fdiv(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b


## 64-bit integer hash. Deterministic, order independent, cheap enough for
## per-voxel use. Feed it world coordinates plus a per-feature salt.
static func hash_i(a: int, b: int, c: int, salt: int) -> int:
	var h := a * 0x27D4EB2D + b * 0x165667B1 + c * 0x9E3779B1 + salt * 0x85EBCA6B
	h ^= h >> 15
	h *= 0x2545F491
	h ^= h >> 13
	h *= 0x9E3779B1
	h ^= h >> 16
	return h


## Uniform 0..1 from a hash triple.
static func rand01(a: int, b: int, c: int, salt: int) -> float:
	return float(hash_i(a, b, c, salt) & 0xFFFFFF) / 16777216.0


## Uniform integer in [lo, hi] from a hash triple.
static func rand_range_i(a: int, b: int, c: int, salt: int, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + (absi(hash_i(a, b, c, salt)) % (hi - lo + 1))


## A `RandomNumberGenerator` seeded purely from coordinates — use it when a
## feature needs a whole stream of numbers (a tree, a vein, a geode).
static func rng_at(a: int, b: int, c: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash_i(a, b, c, salt)
	return r
