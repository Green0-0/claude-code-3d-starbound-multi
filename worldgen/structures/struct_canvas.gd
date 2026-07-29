## A chunk-clipped voxel writer. This is how every structure handles being
## bigger than 16 blocks.
##
## `StructPlacer` binds one canvas to the chunk currently being populated and
## hands it to a structure's `build()`. The generator then draws the *whole*
## structure in absolute world coordinates; anything outside this chunk is
## silently dropped. Because generation is deterministic, each overlapping chunk
## draws the same structure and keeps only its own slice — no cross-chunk state,
## no ordering requirements.
##
## Fills are clipped before iterating, so drawing a 64-block dungeon into a chunk
## it barely touches costs almost nothing. Planets wrap on X and Z; the canvas
## handles the seam for you.
class_name StructCanvas
extends RefCounted

var chunk: Chunk
## Inclusive world-space bounds of the bound chunk.
var cmin: Vector3i
var cmax: Vector3i
var period_x: int = Const.PLANET_SIZE_DEFAULT
var period_z: int = Const.PLANET_SIZE_DEFAULT
## Bumped every time a voxel actually lands in this chunk. Lets a generator ask
## "did any of that matter?" without a second pass.
var writes: int = 0


func _init(p_chunk: Chunk) -> void:
	chunk = p_chunk
	cmin = p_chunk.origin()
	cmax = cmin + Vector3i(15, 15, 15)
	if World.size_x > 0:
		period_x = World.size_x
	if World.size_z > 0:
		period_z = World.size_z


# ============================================================ bounds & clipping
static func _spans_overlap(lo: int, hi: int, c0: int, c1: int, period: int) -> bool:
	if hi < lo:
		return false
	if hi - lo + 1 >= period:
		return true
	var l := posmod(lo, period)
	var h := l + (hi - lo)
	for k in [0, period]:
		if not (h < c0 + k or l > c1 + k):
			return true
	return false


## Intervals of [lo,hi] (in the caller's un-wrapped space) that land in the
## chunk on one wrapping axis. At most two.
static func _clip_spans(lo: int, hi: int, c0: int, c1: int, period: int) -> Array:
	var out: Array = []
	if hi < lo:
		return out
	var shift := lo - posmod(lo, period)
	for k in [-period, 0, period]:
		var a := maxi(lo, c0 + shift + k)
		var b := mini(hi, c1 + shift + k)
		if a <= b:
			out.append(Vector2i(a, b))
	return out


## True when the inclusive world box [a,b] touches this chunk at all.
func intersects(a: Vector3i, b: Vector3i) -> bool:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	if hi.y < cmin.y or lo.y > cmax.y:
		return false
	if not _spans_overlap(lo.x, hi.x, cmin.x, cmax.x, period_x):
		return false
	return _spans_overlap(lo.z, hi.z, cmin.z, cmax.z, period_z)


## Convenience: box around `centre` with half-extents `r`.
func intersects_radius(centre: Vector3i, r: int) -> bool:
	return intersects(centre - Vector3i(r, r, r), centre + Vector3i(r, r, r))


## Local index of a world position, or -1 when it is not in this chunk.
func _index_of(p: Vector3i) -> int:
	if p.y < cmin.y or p.y > cmax.y or p.y < 0 or p.y >= Const.WORLD_HEIGHT:
		return -1
	var x := posmod(p.x, period_x) - cmin.x
	if x < 0 or x > 15:
		return -1
	var z := posmod(p.z, period_z) - cmin.z
	if z < 0 or z > 15:
		return -1
	return ((p.y - cmin.y) << 8) | (z << 4) | x


# ================================================================ point writes
## Write a block, overwriting whatever is there. `id` may be `Const.AIR`.
func put(p: Vector3i, id: int) -> void:
	var i := _index_of(p)
	if i < 0:
		return
	chunk.set_at(i, id)
	writes += 1


## Write only where the target is air or a replaceable block (grass, snow...).
## Use for decoration that must not eat a wall someone else placed.
func put_soft(p: Vector3i, id: int) -> void:
	var i := _index_of(p)
	if i < 0:
		return
	var cur := chunk.blocks[i]
	if cur != Const.AIR and not Blocks.is_replaceable(cur):
		return
	chunk.set_at(i, id)
	writes += 1


## Write only where the target is currently solid (patching a wall into terrain).
func put_hard(p: Vector3i, id: int) -> void:
	var i := _index_of(p)
	if i < 0:
		return
	if chunk.blocks[i] == Const.AIR:
		return
	chunk.set_at(i, id)
	writes += 1


## Hollow out a voxel. Air is what makes a room readable in the side view, so
## generators carve far more than they build.
func carve(p: Vector3i) -> void:
	put(p, Const.AIR)


## Read back a voxel this canvas already wrote. Returns -1 outside the chunk,
## which callers must treat as "unknown" rather than "air".
func peek(p: Vector3i) -> int:
	var i := _index_of(p)
	return -1 if i < 0 else chunk.blocks[i]


## Attach a tile-data payload (see `StructMarkers`). Usually paired with a
## block write on the same voxel.
func tile(p: Vector3i, payload: Dictionary) -> void:
	var i := _index_of(p)
	if i < 0:
		return
	chunk.set_tile_data(i, payload)


## Block + payload in one call.
func put_tile(p: Vector3i, id: int, payload: Dictionary) -> void:
	var i := _index_of(p)
	if i < 0:
		return
	chunk.set_at(i, id)
	chunk.set_tile_data(i, payload)
	writes += 1


func set_liquid(p: Vector3i, level: int = Const.MAX_LIQUID) -> void:
	var i := _index_of(p)
	if i < 0:
		return
	chunk.set_liquid(i, level)


# ================================================================= volume fills
## Solid inclusive box.
func box(a: Vector3i, b: Vector3i, id: int) -> void:
	_fill(a, b, id, 0)


## Box that only writes into air / replaceable voxels.
func box_soft(a: Vector3i, b: Vector3i, id: int) -> void:
	_fill(a, b, id, 1)


## Carve an inclusive box to air.
func carve_box(a: Vector3i, b: Vector3i) -> void:
	_fill(a, b, Const.AIR, 0)


func _fill(a: Vector3i, b: Vector3i, id: int, mode: int) -> void:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	var y0 := maxi(lo.y, maxi(cmin.y, 0))
	var y1 := mini(hi.y, mini(cmax.y, Const.WORLD_HEIGHT - 1))
	if y1 < y0:
		return
	var xs := _clip_spans(lo.x, hi.x, cmin.x, cmax.x, period_x)
	if xs.is_empty():
		return
	var zs := _clip_spans(lo.z, hi.z, cmin.z, cmax.z, period_z)
	if zs.is_empty():
		return
	for xr: Vector2i in xs:
		for zr: Vector2i in zs:
			for y in range(y0, y1 + 1):
				var row := (y - cmin.y) << 8
				for z in range(zr.x, zr.y + 1):
					var zi := row | ((z & 15) << 4)
					for x in range(xr.x, xr.y + 1):
						var i := zi | (x & 15)
						if mode == 1:
							var cur := chunk.blocks[i]
							if cur != Const.AIR and not Blocks.is_replaceable(cur):
								continue
						chunk.set_at(i, id)
						writes += 1


## Box shell: walls of `wall_id`, floor `floor_id`, ceiling `ceil_id`, interior
## carved to air. Pass `Const.AIR` for any of the three to leave it open.
func room(a: Vector3i, b: Vector3i, wall_id: int, floor_id: int = -1, ceil_id: int = -1) -> void:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	if not intersects(lo, hi):
		return
	var fid := wall_id if floor_id < 0 else floor_id
	var cid := wall_id if ceil_id < 0 else ceil_id
	# Only hollow out when there is actually an interior; a 1- or 2-thick box is
	# a wall, not a room, and `_fill` would otherwise normalise the inverted
	# range and eat the masonry either side of it.
	if hi.x - lo.x >= 2 and hi.y - lo.y >= 2 and hi.z - lo.z >= 2:
		carve_box(lo + Vector3i(1, 1, 1), hi - Vector3i(1, 1, 1))
	# four vertical walls
	box(Vector3i(lo.x, lo.y, lo.z), Vector3i(lo.x, hi.y, hi.z), wall_id)
	box(Vector3i(hi.x, lo.y, lo.z), Vector3i(hi.x, hi.y, hi.z), wall_id)
	box(Vector3i(lo.x, lo.y, lo.z), Vector3i(hi.x, hi.y, lo.z), wall_id)
	box(Vector3i(lo.x, lo.y, hi.z), Vector3i(hi.x, hi.y, hi.z), wall_id)
	box(Vector3i(lo.x, lo.y, lo.z), Vector3i(hi.x, lo.y, hi.z), fid)
	box(Vector3i(lo.x, hi.y, lo.z), Vector3i(hi.x, hi.y, hi.z), cid)


## Just the four vertical walls of a box (no floor/ceiling).
func walls(a: Vector3i, b: Vector3i, id: int) -> void:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	box(Vector3i(lo.x, lo.y, lo.z), Vector3i(lo.x, hi.y, hi.z), id)
	box(Vector3i(hi.x, lo.y, lo.z), Vector3i(hi.x, hi.y, hi.z), id)
	box(Vector3i(lo.x, lo.y, lo.z), Vector3i(hi.x, hi.y, lo.z), id)
	box(Vector3i(lo.x, lo.y, hi.z), Vector3i(hi.x, hi.y, hi.z), id)


## Rectangular outline on the XZ plane at height `y`.
func rect_xz(lo: Vector3i, hi: Vector3i, y: int, id: int) -> void:
	box(Vector3i(lo.x, y, lo.z), Vector3i(hi.x, y, lo.z), id)
	box(Vector3i(lo.x, y, hi.z), Vector3i(hi.x, y, hi.z), id)
	box(Vector3i(lo.x, y, lo.z), Vector3i(lo.x, y, hi.z), id)
	box(Vector3i(hi.x, y, lo.z), Vector3i(hi.x, y, hi.z), id)


## Vertical cylinder, centred on `c` (a floor-level centre), radius `r`,
## `height` blocks tall. `hollow` leaves the interior untouched.
func cylinder(c: Vector3i, r: int, height: int, id: int, hollow: bool = false) -> void:
	if not intersects(c - Vector3i(r, 0, r), c + Vector3i(r, height, r)):
		return
	var r2 := r * r
	var inner := (r - 1) * (r - 1)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var d := dx * dx + dz * dz
			if d > r2:
				continue
			if hollow and d <= inner:
				continue
			box(Vector3i(c.x + dx, c.y, c.z + dz), Vector3i(c.x + dx, c.y + height - 1, c.z + dz), id)


## Filled or hollow sphere / dome. `y_min_offset` clips the bottom (dome = 0).
func sphere(c: Vector3i, r: int, id: int, hollow: bool = false, y_min_offset: int = -99) -> void:
	if not intersects_radius(c, r):
		return
	var r2 := r * r
	var inner := (r - 1) * (r - 1)
	for dy in range(maxi(-r, y_min_offset), r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d := dx * dx + dy * dy + dz * dz
				if d > r2:
					continue
				if hollow and d <= inner:
					continue
				put(c + Vector3i(dx, dy, dz), id)


## Straight run of blocks between two points (3D Bresenham-ish, thickness 1).
func line(a: Vector3i, b: Vector3i, id: int) -> void:
	var d := b - a
	var steps := maxi(maxi(absi(d.x), absi(d.y)), absi(d.z))
	if steps == 0:
		put(a, id)
		return
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		put(Vector3i(
			a.x + roundi(float(d.x) * t),
			a.y + roundi(float(d.y) * t),
			a.z + roundi(float(d.z) * t)), id)


## An axis-aligned tunnel: carves a `w` x `h` corridor from `a` to `b` (which
## must share two of three coordinates) and optionally shells it.
func tunnel(a: Vector3i, b: Vector3i, w: int, h: int, shell_id: int = -1, floor_id: int = -1) -> void:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	var half := (w - 1) / 2
	# Widen across whichever horizontal axis is not the run direction.
	if hi.x - lo.x >= hi.z - lo.z:
		lo.z -= half
		hi.z += w - 1 - half
	else:
		lo.x -= half
		hi.x += w - 1 - half
	hi.y = lo.y + h - 1
	if shell_id >= 0:
		box(lo - Vector3i(1, 1, 1), hi + Vector3i(1, 1, 1), shell_id)
	carve_box(lo, hi)
	if floor_id >= 0:
		box(Vector3i(lo.x, lo.y - 1, lo.z), Vector3i(hi.x, lo.y - 1, hi.z), floor_id)


## Staircase climbing along the +/-X or +/-Z axis. `dir` must be an axis unit.
func stairs(start: Vector3i, dir: Vector3i, steps: int, width: int, id: int, headroom: int = 3) -> void:
	var side := Vector3i(0, 0, 1) if dir.x != 0 else Vector3i(1, 0, 0)
	for i in range(steps):
		var base := start + dir * i + Vector3i(0, i, 0)
		for w in range(width):
			var p := base + side * w
			put(p, id)
			carve_box(p + Vector3i(0, 1, 0), p + Vector3i(0, headroom, 0))


## Drop `id` where `chance` fires, using `r`. Handy for rubble and moss.
func scatter(lo: Vector3i, hi: Vector3i, id: int, chance: float, r: RandomNumberGenerator) -> void:
	if id == Const.AIR:
		return
	for y in range(mini(lo.y, hi.y), maxi(lo.y, hi.y) + 1):
		for z in range(mini(lo.z, hi.z), maxi(lo.z, hi.z) + 1):
			for x in range(mini(lo.x, hi.x), maxi(lo.x, hi.x) + 1):
				if r.randf() < chance:
					put_soft(Vector3i(x, y, z), id)


## Punch a doorway of `w` x `h` at `p`, opening along `axis` (0 = X, 2 = Z).
## The *axis* is the direction you walk through, which is exactly the axis whose
## views (0/2 for X, 1/3 for Z) can traverse it — this is the primitive every
## perspective puzzle is built from.
func doorway(p: Vector3i, axis: int, w: int = 1, h: int = 2, depth: int = 1) -> void:
	var across := Vector3i(0, 0, 1) if axis == 0 else Vector3i(1, 0, 0)
	var through := Vector3i(1, 0, 0) if axis == 0 else Vector3i(0, 0, 1)
	for d in range(depth):
		for a in range(w):
			carve_box(p + through * d + across * a,
					p + through * d + across * a + Vector3i(0, h - 1, 0))
