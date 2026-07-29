## Low-level voxel stamping helper used by the hand-authored `space/` worlds
## (the player's ship and the outpost).
##
## `World.set_block()` is the right call for gameplay — it notifies lighting,
## liquids and the renderer per block. Stamping a whole ship that way would fire
## tens of thousands of signals, so this writes straight into `Chunk` and
## batches the invalidation into one `commit()` at the end.
##
## Usage:
## ```gdscript
## var s := SpcStamp.new()
## s.ensure_region(Vector3i(16, 48, 16), Vector3i(48, 111, 48))
## s.blank_region(Vector3i(16, 48, 16), Vector3i(48, 111, 48))
## s.room(Vector3i(28, 72, 28), Vector3i(36, 78, 36), hull, floor_id, hull)
## s.commit()
## ```
class_name SpcStamp
extends RefCounted

## Chunk positions touched since construction; `commit()` re-lights and re-meshes
## exactly these.
var touched: Dictionary = {}

## Reusable all-air block payload, so blanking a chunk is O(1) instead of O(4096).
## Packed arrays are copy-on-write, so handing the same instance to every chunk
## is safe: the first `set_at()` gives that chunk its own copy.
static var _empty_blocks := PackedInt32Array()


static func _empty() -> PackedInt32Array:
	if _empty_blocks.size() != Const.CHUNK_VOL:
		_empty_blocks.resize(Const.CHUNK_VOL)
		_empty_blocks.fill(Const.AIR)
	return _empty_blocks


# ------------------------------------------------------------------ resolving
## Block id by name with a fallback chain that never returns garbage.
static func bid(name: StringName, fallback: StringName = &"stone") -> int:
	if name != &"" and Blocks.has(name):
		return Blocks.id(name)
	if fallback != &"" and Blocks.has(fallback):
		return Blocks.id(fallback)
	return Const.AIR


# -------------------------------------------------------------------- chunks
## Force every chunk covering the inclusive block box to exist right now.
## Generation is drained synchronously — this is a load-time operation.
func ensure_region(p0: Vector3i, p1: Vector3i) -> void:
	var lo := Vector3i(mini(p0.x, p1.x), mini(p0.y, p1.y), mini(p0.z, p1.z))
	var hi := Vector3i(maxi(p0.x, p1.x), maxi(p0.y, p1.y), maxi(p0.z, p1.z))
	for cy in range(maxi(0, lo.y >> 4), mini(Const.WORLD_HEIGHT_CHUNKS - 1, hi.y >> 4) + 1):
		for cx in range(lo.x >> 4, (hi.x >> 4) + 1):
			for cz in range(lo.z >> 4, (hi.z >> 4) + 1):
				World.request_chunk(Vector3i(
					posmod(cx, maxi(1, World.size_x >> 4)), cy,
					posmod(cz, maxi(1, World.size_z >> 4))))
	if World.has_method(&"_pump_generation_all"):
		World.call(&"_pump_generation_all")


## Reset one chunk to pure air without touching its 4096 entries individually.
static func blank_chunk(c: Chunk) -> void:
	if c == null:
		return
	c.blocks = _empty()
	c.solid_count = 0
	c.empty = true
	c.dirty = true
	c.tile_data.clear()


## Blank every chunk overlapping the box. Used to carve the void a hand-authored
## world sits in, whatever the terrain generator decided to put there.
func blank_region(p0: Vector3i, p1: Vector3i) -> void:
	var lo := Vector3i(mini(p0.x, p1.x), mini(p0.y, p1.y), mini(p0.z, p1.z))
	var hi := Vector3i(maxi(p0.x, p1.x), maxi(p0.y, p1.y), maxi(p0.z, p1.z))
	for cy in range(maxi(0, lo.y >> 4), mini(Const.WORLD_HEIGHT_CHUNKS - 1, hi.y >> 4) + 1):
		for cx in range(lo.x >> 4, (hi.x >> 4) + 1):
			for cz in range(lo.z >> 4, (hi.z >> 4) + 1):
				var cp := Vector3i(
					posmod(cx, maxi(1, World.size_x >> 4)), cy,
					posmod(cz, maxi(1, World.size_z >> 4)))
				var c := World.get_chunk(cp)
				if c != null:
					blank_chunk(c)
					touched[cp] = true


# -------------------------------------------------------------------- writing
## Write one voxel. Silently ignores positions whose chunk is not resident.
func set_block(p: Vector3i, id: int) -> void:
	if p.y < 0 or p.y >= Const.WORLD_HEIGHT:
		return
	var n := World.normalize(p)
	var cp := Vector3i(n.x >> 4, n.y >> 4, n.z >> 4)
	var c := World.get_chunk(cp)
	if c == null:
		return
	c.set_at(Chunk.index(n.x & 15, n.y & 15, n.z & 15), id)
	touched[cp] = true


func get_block(p: Vector3i) -> int:
	return World.get_block(p)


## Solid box fill, inclusive on both corners.
func fill(p0: Vector3i, p1: Vector3i, id: int) -> void:
	var lo := Vector3i(mini(p0.x, p1.x), mini(p0.y, p1.y), mini(p0.z, p1.z))
	var hi := Vector3i(maxi(p0.x, p1.x), maxi(p0.y, p1.y), maxi(p0.z, p1.z))
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				set_block(Vector3i(x, y, z), id)


## Hollow shell: the six faces of the box, interior untouched.
func shell(p0: Vector3i, p1: Vector3i, id: int) -> void:
	var lo := Vector3i(mini(p0.x, p1.x), mini(p0.y, p1.y), mini(p0.z, p1.z))
	var hi := Vector3i(maxi(p0.x, p1.x), maxi(p0.y, p1.y), maxi(p0.z, p1.z))
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				if x == lo.x or x == hi.x or y == lo.y or y == hi.y or z == lo.z or z == hi.z:
					set_block(Vector3i(x, y, z), id)


## A habitable room: `p0`..`p1` is the **outer** box. Walls and ceiling take
## `wall_id`, the bottom slab takes `floor_id`, the interior is cleared.
func room(p0: Vector3i, p1: Vector3i, wall_id: int, floor_id: int, ceiling_id: int = -1) -> void:
	var lo := Vector3i(mini(p0.x, p1.x), mini(p0.y, p1.y), mini(p0.z, p1.z))
	var hi := Vector3i(maxi(p0.x, p1.x), maxi(p0.y, p1.y), maxi(p0.z, p1.z))
	shell(lo, hi, wall_id)
	fill(lo + Vector3i(1, 1, 1), hi - Vector3i(1, 1, 1), Const.AIR)
	fill(Vector3i(lo.x, lo.y, lo.z), Vector3i(hi.x, lo.y, hi.z), floor_id)
	if ceiling_id >= 0:
		fill(Vector3i(lo.x, hi.y, lo.z), Vector3i(hi.x, hi.y, hi.z), ceiling_id)


## Punch a doorway (air) through a wall, `w` wide and `h` tall, anchored at the
## floor level `y`.
func doorway(centre: Vector3i, axis: int, w: int, h: int) -> void:
	var half := w >> 1
	for dy in range(0, h):
		for d in range(-half, half + 1):
			var p := centre + Vector3i(0, dy, 0)
			if axis == 0:
				p.z += d
			else:
				p.x += d
			set_block(p, Const.AIR)


## Vertical ladder column between two heights.
func ladder(x: int, z: int, y0: int, y1: int, id: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		set_block(Vector3i(x, y, z), id)


# ----------------------------------------------------------------- tile data
## Attach a tile-entity payload to a voxel. Call **after** writing the block:
## `World.set_block()` clears tile data, this helper does not.
func tile(p: Vector3i, d: Dictionary) -> void:
	var n := World.normalize(p)
	var cp := Vector3i(n.x >> 4, n.y >> 4, n.z >> 4)
	var c := World.get_chunk(cp)
	if c == null:
		return
	c.set_tile_data(Chunk.index(n.x & 15, n.y & 15, n.z & 15), d)
	touched[cp] = true


## Read a tile-entity payload back out.
static func tile_at(p: Vector3i) -> Dictionary:
	var n := World.normalize(p)
	var c := World.get_chunk(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))
	if c == null:
		return {}
	return c.get_tile_data(Chunk.index(n.x & 15, n.y & 15, n.z & 15))


## Mark a chunk as hand-authored so the void guard leaves it alone.
func mark_populated(p: Vector3i) -> void:
	var n := World.normalize(p)
	var c := World.get_chunk(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))
	if c != null:
		c.populated = true


# ------------------------------------------------------------------- commit
## Re-light and re-mesh everything written since construction, then forget it.
func commit() -> void:
	for cp: Vector3i in touched:
		var c := World.get_chunk(cp)
		if c == null:
			continue
		c.populated = true
		c.lit = false
		if Lighting.has_method(&"on_chunk_loaded"):
			Lighting.call(&"on_chunk_loaded", cp)
		World.mark_dirty(cp)
	touched.clear()
