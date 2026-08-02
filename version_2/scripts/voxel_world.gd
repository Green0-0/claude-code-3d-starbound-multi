class_name VoxelWorld
extends Node3D

## The voxel planet.
##
## Storage is column-major: every (x, z) column of the world is a single 64-bit
## bitmask of "is there something here", which makes face-culling a handful of
## bitwise ops per column instead of a loop over every voxel. That is what lets
## a pure-GDScript mesher keep up with a streaming world.

signal generation_progress(done: int, total: int)
signal world_ready()

const CW := 16                 ## chunk width / depth
const WH := 48                 ## world height (must stay < 63 for the bitmasks)
const COLS := CW * CW
const EXT := CW + 2            ## padded column grid used while meshing
const SEA := 12

## Flood-fill budget. The box has to reach the camera as well as the pocket, so
## it is centred on the player and sized to cover the lens at full zoom.
const FILL_EXTENT := Vector3i(52, 48, 52)
const MAX_FILL_CELLS := 3000
const MAX_MARKED_CELLS := 26000
## How many chunks the unbudgeted player-edit remesh may rebuild in one frame.
const MAX_URGENT_MESH := 3

@export var view_radius := 5
@export var gen_budget_us := 6000
@export var mesh_budget_us := 6000
@export var load_budget_us := 26000

# ---------------------------------------------------------------- block tables
# face ids: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z
const FACE_NORMAL := [
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
]
const FACE_VERTS := [
	[Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
]
const FACE_UV := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
const AO_LUT := [0.44, 0.66, 0.85, 1.0]

## The same three tables again, flat and typed, for the mesher's inner loop.
##
## `FACE_VERTS[dir][j]` is two Variant unboxes per vertex and there are four
## vertices on every face of every chunk in the world; `FLAT_VERTS[dir * 4 + j]`
## is one typed read. Meshing is the largest single cost in the frame and this
## loop is all of it, so the duplication earns its keep. The originals stay
## because they read better everywhere that is not this loop.
##
## `static var` rather than `const` only because GDScript will not accept a
## packed array as a constant expression. Nothing writes to them.
static var FLAT_VERTS := PackedVector3Array([
	Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1),
	Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0),
	Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0),
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1),
	Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
])
static var FLAT_NORMAL := PackedVector3Array([
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
])
static var FLAT_UV := PackedVector2Array([
	Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
])
static var FLAT_AO := PackedFloat32Array([0.44, 0.66, 0.85, 1.0])
## face ids for the four horizontal directions handled by the shared side loop
const SIDE_FACE := [0, 1, 4, 5]
## The six axis steps. A constant because every place that wants them wants them
## inside a loop, and an array literal in a loop body is rebuilt every pass.
const NEIGHBOURS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# ------------------------------------------------------------------ chunk data
class Chunk:
	var cx: int
	var cz: int
	var types := PackedByteArray()
	var solid := PackedInt64Array()   ## opaque occluders, one bitmask per column
	var any := PackedInt64Array()     ## anything non-air, one bitmask per column
	var coll := PackedInt64Array()    ## anything an entity cannot walk through
	var mi: MeshInstance3D
	var generated := false
	var dirty := true

	func _init(x: int, z: int) -> void:
		cx = x
		cz = z
		types.resize(VoxelWorld.COLS * VoxelWorld.WH)
		solid.resize(VoxelWorld.COLS)
		any.resize(VoxelWorld.COLS)
		coll.resize(VoxelWorld.COLS)


var _chunks := {}                       ## Vector2i -> Chunk
var _pending := {}                      ## Vector2i -> Array[Vector4i] deferred structure blocks
var _gen_queue: Array[Vector2i] = []
## The chunk currently being filled, and how far through it we are. Held out of
## `_chunks` until complete; see `_begin_chunk`.
var _building: Chunk = null
var _build_key := Vector2i.ZERO
var _build_col := 0
var _mesh_queue: Array[Vector2i] = []
var _center := Vector2i(9999, 9999)
var _initial_done := false
var _initial_total := 1

var atlas: ImageTexture
var mat_opaque: ShaderMaterial
var mat_glass: ShaderMaterial
var mat_cross: ShaderMaterial
var mat_cap: ShaderMaterial

var cutaway := Cutaway.new()
var _cap_mi: MeshInstance3D
## Kept and refilled rather than replaced, so a rebuild does not churn an RID.
var _cap_mesh := ArrayMesh.new()
## The cross-section under construction: one entry per quad in each. Typed and
## reused so a rebuild does not box a few thousand Variants on the way to a mesh.
var _cap_cells := PackedVector3Array()
var _cap_meta := PackedInt32Array()
## One byte per cell of the cylinder's bounding box, so the drill march can tell
## whether it has already offered a cell without hashing it.
var _cap_seen := PackedByteArray()
## The same trick for the fill mode's flood; see `_rebuild_fill`.
var _flood_seen := PackedByteArray()

## Chunks a player edit touched, remeshed next frame ahead of streaming work.
var _edit_dirty: Array[Vector2i] = []
var _fill_img: Image
var _fill_tex: ImageTexture
## Bumped by every block write. Part of the cut signature, so mining inside a
## cross-section rebuilds it on the same frame instead of leaving the old
## geometry hanging in the air.
var _world_version := 0
## The signature the cached cap mesh was built for, in three parts. Held as
## integer vectors rather than a formatted string because this is compared on
## every single frame; see Cutaway.sig_head.
var _cut_head := Vector4i(-1, -1, -1, -1)
var _cut_lo := Vector4i.ZERO
var _cut_hi := Vector4i.ZERO
## Which chunks the planar cull currently hides; see Cutaway.planar_cull_key.
var _cull_key := Vector3i.ZERO
## How many times the cross-section has actually been rebuilt. Standing still
## must not increment this.
var cut_rebuilds := 0

## Terrain, biomes, ores and structures all live in the generator, so a planet
## is a configuration rather than a code path.
var gen := WorldGen.new()
var world_seed := 1337
var house_spawn := Vector3i.ZERO
## Structures placed this session that the game still has to populate with
## entities: [{"kind": StringName, "at": Vector3i, ...}, ...]
var pending_structures: Array = []

var _ext_solid := PackedInt64Array()
var _ext_any := PackedInt64Array()
var _bitidx := PackedInt32Array()
var _live := false


# =============================================================================
# lifecycle
# =============================================================================

func _ready() -> void:
	_ext_solid.resize(EXT * EXT)
	_ext_any.resize(EXT * EXT)
	_bitidx.resize(67)
	for k in 62:
		_bitidx[(1 << k) % 67] = k

	gen.configure({"seed": world_seed})
	_init_materials()

	_cap_mi = MeshInstance3D.new()
	_cap_mi.name = "CutawayCaps"
	_cap_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_cap_mi.mesh = _cap_mesh
	add_child(_cap_mi)

	cutaway.push_to_shader_globals()


func _init_materials() -> void:
	atlas = TexGen.build_atlas()

	mat_opaque = ShaderMaterial.new()
	mat_opaque.shader = load("res://shaders/voxel.gdshader")
	mat_opaque.set_shader_parameter("atlas", atlas)

	mat_glass = ShaderMaterial.new()
	mat_glass.shader = load("res://shaders/voxel_glass.gdshader")
	mat_glass.set_shader_parameter("atlas", atlas)

	mat_cross = ShaderMaterial.new()
	mat_cross.shader = load("res://shaders/voxel_cross.gdshader")
	mat_cross.set_shader_parameter("atlas", atlas)

	mat_cap = ShaderMaterial.new()
	mat_cap.shader = load("res://shaders/cut_cap.gdshader")
	mat_cap.set_shader_parameter("atlas", atlas)
	mat_cap.set_shader_parameter("atlas_tile", Vector2(
		1.0 / float(TexGen.ATLAS_COLS), 1.0 / float(TexGen.ATLAS_ROWS)))


# =============================================================================
# coordinate helpers
# =============================================================================

static func chunk_of(gx: int, gz: int) -> Vector2i:
	return Vector2i(gx >> 4, gz >> 4)


func get_chunk(cx: int, cz: int) -> Chunk:
	return _chunks.get(Vector2i(cx, cz))


func get_block(gx: int, gy: int, gz: int) -> int:
	if gy < 0 or gy >= WH:
		return Blocks.AIR
	var c: Chunk = _chunks.get(Vector2i(gx >> 4, gz >> 4))
	if c == null:
		return Blocks.AIR
	return c.types[(((gx & 15) * CW) + (gz & 15)) * WH + gy]


## Collision test. Foliage, liquids and ladders are in `any` but not in `coll`,
## so you can walk through a meadow and swim through water.
func is_solid_at(gx: int, gy: int, gz: int) -> bool:
	if gy < 0:
		return true
	if gy >= WH:
		return false
	var c: Chunk = _chunks.get(Vector2i(gx >> 4, gz >> 4))
	if c == null:
		return false
	return (c.coll[((gx & 15) * CW) + (gz & 15)] >> gy) & 1 == 1


## True when anything at all occupies the cell, collidable or not.
func is_occupied(gx: int, gy: int, gz: int) -> bool:
	if gy < 0 or gy >= WH:
		return false
	var c: Chunk = _chunks.get(Vector2i(gx >> 4, gz >> 4))
	if c == null:
		return false
	return (c.any[((gx & 15) * CW) + (gz & 15)] >> gy) & 1 == 1


## How many chunks are currently resident, for the test harness and the HUD.
func loaded_chunk_count() -> int:
	return _chunks.size()


func is_loaded(gx: int, gz: int) -> bool:
	return _chunks.has(Vector2i(gx >> 4, gz >> 4))


func solid_mask_at(gx: int, gz: int) -> int:
	var c: Chunk = _chunks.get(Vector2i(gx >> 4, gz >> 4))
	if c == null:
		return 0
	return c.solid[((gx & 15) * CW) + (gz & 15)]


func any_mask_at(gx: int, gz: int) -> int:
	var c: Chunk = _chunks.get(Vector2i(gx >> 4, gz >> 4))
	if c == null:
		return 0
	return c.any[((gx & 15) * CW) + (gz & 15)]


## Highest occupied voxel in a column, or -1.
func column_top(gx: int, gz: int) -> int:
	var m := any_mask_at(gx, gz)
	if m == 0:
		return -1
	var top := -1
	while m != 0:
		m >>= 1
		top += 1
	return top


func set_block(gx: int, gy: int, gz: int, id: int, mark_dirty := true,
		urgent := false) -> bool:
	if gy < 0 or gy >= WH:
		return false
	var key := Vector2i(gx >> 4, gz >> 4)
	var c: Chunk = _chunks.get(key)
	if c == null:
		return false
	var lx := gx & 15
	var lz := gz & 15
	var ci := lx * CW + lz
	var idx := ci * WH + gy
	if c.types[idx] == id:
		return false
	var was := c.types[idx]
	c.types[idx] = id
	var bit := 1 << gy
	if id == Blocks.AIR:
		c.any[ci] &= ~bit
		c.solid[ci] &= ~bit
		c.coll[ci] &= ~bit
	else:
		c.any[ci] |= bit
		if Blocks.is_opaque(id):
			c.solid[ci] |= bit
		else:
			c.solid[ci] &= ~bit
		if Blocks.is_solid(id):
			c.coll[ci] |= bit
		else:
			c.coll[ci] &= ~bit
	# Only bump the version the cut watches when the write could actually have
	# changed the cross-section. Every cap the three modes build is an opaque
	# block's face, and the fill's flood travels by the collision mask, so a
	# write that touches neither cannot move a single vertex.
	#
	# This is not a micro-saving. Liquid flow and crop growth write blocks on
	# their own timers, several a second, forever — and with the version bumped
	# unconditionally, standing beside a waterfall rebuilt the whole slice on
	# every frame that water moved. Neither water nor wheat is opaque, so
	# neither one now costs anything.
	if Blocks.is_opaque(was) or Blocks.is_opaque(id) \
			or Blocks.is_solid(was) != Blocks.is_solid(id):
		_world_version += 1
	if mark_dirty:
		_touch(key, urgent)
		if lx == 0:
			_touch(key + Vector2i(-1, 0), urgent)
		elif lx == CW - 1:
			_touch(key + Vector2i(1, 0), urgent)
		if lz == 0:
			_touch(key + Vector2i(0, -1), urgent)
		elif lz == CW - 1:
			_touch(key + Vector2i(0, 1), urgent)
	return true


## The block the *player* just broke or placed. Identical to `set_block` except
## that the remesh jumps the streaming queue.
##
## Only a write the player is waiting on earns that. See `_touch`.
func edit_block(gx: int, gy: int, gz: int, id: int) -> bool:
	return set_block(gx, gy, gz, id, true, true)


func _touch(key: Vector2i, urgent := false) -> void:
	var c: Chunk = _chunks.get(key)
	if c == null or not c.generated:
		return
	if not c.dirty:
		c.dirty = true
		_mesh_queue.push_front(key)
	# An edit the player is waiting on is not streaming work and must not queue
	# behind it: a block you just destroyed has to stop being drawn *now*, and
	# under load — which in cut modes means most of the time — a budgeted queue
	# can leave it standing for many frames. That is the ghost.
	#
	# But only the player's own edits. `set_block` is how the *whole simulation*
	# writes: water flows, sand falls, wheat grows, structures decorate. Those
	# all took the unbudgeted path too, so a chunk with a stream in it remeshed
	# outside the frame budget several times a second, forever — which measured
	# as the single largest source of stutter in the game. They belong on the
	# queue above, which already puts them at the front and still respects the
	# budget, so they lose nothing but the ability to blow a frame.
	if urgent and not _edit_dirty.has(key):
		_edit_dirty.append(key)


# =============================================================================
# streaming
# =============================================================================

func focus_on(world_pos: Vector3) -> void:
	var key := Vector2i(int(floor(world_pos.x)) >> 4, int(floor(world_pos.z)) >> 4)
	if key == _center:
		return
	_center = key
	_rebuild_queues()


func _rebuild_queues() -> void:
	var gr := view_radius + 1
	var wanted: Array[Vector2i] = []
	for dz in range(-gr, gr + 1):
		for dx in range(-gr, gr + 1):
			wanted.append(_center + Vector2i(dx, dz))
	wanted.sort_custom(func(a, b):
		return (a - _center).length_squared() < (b - _center).length_squared())

	_gen_queue.clear()
	for k in wanted:
		if not _chunks.has(k):
			_gen_queue.append(k)

	# drop anything far away
	var cull := gr + 2
	for k in _chunks.keys():
		var d: Vector2i = k - _center
		if absi(d.x) > cull or absi(d.y) > cull:
			var c: Chunk = _chunks[k]
			if c.mi != null:
				c.mi.queue_free()
			_chunks.erase(k)

	# The chunk in flight, if the player has already left it behind. Half a
	# chunk of noise is not worth carrying, and it is regenerated from scratch
	# if they turn around.
	if _building != null:
		var bd: Vector2i = _build_key - _center
		if absi(bd.x) > cull or absi(bd.y) > cull:
			_building = null

	# And the blocks a structure wrote into a chunk that never arrived.
	#
	# These are held for a chunk that has not generated yet, and are consumed
	# when it does. A structure that reaches into ground the player then walks
	# away from is never consumed, so without this the dictionary keeps one
	# entry per such chunk for the rest of the session — a slow leak that tracks
	# how much of the world has been explored, which is exactly the shape of
	# leak a long session finds.
	#
	# Dropping them is only safe because the chunk that *wrote* them will be
	# regenerated too, and will write them again. That is what the extra margin
	# buys: a structure spans at most a few chunks, so anything still holding
	# writes for a chunk this far out has certainly been culled itself, and
	# cannot come back without re-running its own decoration. Pruning at the
	# plain cull distance left a window where the writer was still resident, and
	# the structure would have come back one wall short.
	var pending_cull := cull + 4
	for k in _pending.keys():
		var d: Vector2i = k - _center
		if absi(d.x) > pending_cull or absi(d.y) > pending_cull:
			_pending.erase(k)

	if _initial_total <= 1:
		_initial_total = maxi(_gen_queue.size(), 1)


func _process(_delta: float) -> void:
	# Player edits first, unbudgeted. There are at most a handful of chunks in
	# here — a single block touches one, or three at a chunk seam — so this
	# cannot run away, and it is what guarantees a broken block stops being
	# drawn on the very next frame instead of whenever the streaming queue gets
	# round to it.
	var p := Prof.mark()
	# A single block edit touches at most three chunks — its own, and a
	# neighbour on each axis if it sat on a seam — so the cap is never reached
	# by a player mining normally. What it bounds is the pathological case: an
	# area tool, a collapsing structure, a harness digging a shaft a frame. The
	# overflow is not dropped, only deferred; `_touch` already pushed it to the
	# front of the mesh queue, so it is the very next thing that runs.
	if not _edit_dirty.is_empty():
		var done := 0
		for key: Vector2i in _edit_dirty:
			if done >= MAX_URGENT_MESH:
				break
			var c: Chunk = _chunks.get(key)
			if c != null and c.dirty and _neighbours_ready(key):
				_build_chunk_mesh(c)
				done += 1
		_edit_dirty.clear()
	Prof.add(&"stream.edits", p)

	var budget := load_budget_us if not _initial_done else gen_budget_us
	var t0 := Time.get_ticks_usec()

	p = Prof.mark()
	var deadline := t0 + budget
	while Time.get_ticks_usec() < deadline:
		if _building == null:
			if _gen_queue.is_empty():
				break
			var k: Vector2i = _gen_queue.pop_front()
			if _chunks.has(k):
				continue
			_begin_chunk(k)
		if not _fill_columns(deadline):
			break
		_finish_chunk()
	Prof.add(&"stream.generate", p)

	budget = load_budget_us if not _initial_done else mesh_budget_us
	t0 = Time.get_ticks_usec()
	p = Prof.mark()
	while Time.get_ticks_usec() - t0 < budget:
		var nk = _next_meshable()
		if nk == null:
			break
		_build_chunk_mesh(_chunks[nk])
	Prof.add(&"stream.mesh", p)

	if not _initial_done:
		var remaining := _gen_queue.size()
		generation_progress.emit(_initial_total - remaining, _initial_total)
		if remaining == 0 and _building == null and _next_meshable() == null:
			_initial_done = true
			world_ready.emit()

	p = Prof.mark()
	refresh_cutaway()
	Prof.add(&"cutaway.rebuild", p)


## A chunk can only be meshed once its 8 neighbours exist, otherwise we would
## bake seams that have to be thrown away moments later.
## A chunk can only be meshed once its eight neighbours exist, or the seams get
## baked wrong and thrown away moments later.
func _neighbours_ready(k: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n: Chunk = _chunks.get(k + Vector2i(dx, dz))
			if n == null or not n.generated:
				return false
	return true


func _next_meshable():
	var i := 0
	while i < _mesh_queue.size():
		var k: Vector2i = _mesh_queue[i]
		var c: Chunk = _chunks.get(k)
		if c == null or not c.dirty:
			_mesh_queue.remove_at(i)
			continue
		var d := k - _center
		if absi(d.x) > view_radius or absi(d.y) > view_radius:
			i += 1
			continue
		var ok := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n: Chunk = _chunks.get(k + Vector2i(dx, dz))
				if n == null or not n.generated:
					ok = false
					break
			if not ok:
				break
		if ok:
			_mesh_queue.remove_at(i)
			return k
		i += 1
	return null


# =============================================================================
# terrain generation
# =============================================================================

static func _hash3(x: int, y: int, z: int, salt: int) -> int:
	return WorldGen.hash3(x, y, z, salt)


func surface_height(gx: int, gz: int) -> int:
	return gen.surface_height(gx, gz)


## Point the world at a planet and throw away everything already streamed.
func load_planet(cfg: Dictionary) -> void:
	gen.configure(cfg)
	world_seed = int(cfg.get("seed", world_seed))
	pending_structures.clear()
	for k in _chunks.keys():
		var c: Chunk = _chunks[k]
		if c.mi != null:
			c.mi.queue_free()
	_chunks.clear()
	_pending.clear()
	_gen_queue.clear()
	_mesh_queue.clear()
	_building = null
	_center = Vector2i(9999, 9999)
	_initial_done = false
	_initial_total = 1
	_live = false
	# A new planet is a new world under the same cross-section. Nothing bumps
	# _world_version — generation writes chunk arrays directly rather than going
	# through set_block — so without this the old slice hangs in the air until
	# the player happens to cross a block boundary.
	_invalidate_cut()
	_cull_key = Vector3i.ZERO


## Start a chunk. It is deliberately *not* put in `_chunks` yet.
##
## Filling one takes far longer than a frame's whole streaming budget — it is
## two hundred and fifty six columns of layered noise — so it is filled a few
## columns at a time across however many frames it needs. Everything else in the
## game reads the world through `_chunks`, so a half-filled chunk must not be in
## there: it would read as a column of air, and entities would fall through it.
## Keeping it aside costs one reference and makes the partial state invisible.
func _begin_chunk(key: Vector2i) -> void:
	_building = Chunk.new(key.x, key.y)
	_build_key = key
	_build_col = 0


## Fill columns until the deadline. True when the chunk is complete.
func _fill_columns(deadline_us: int) -> bool:
	var ch := _building
	var ox := _build_key.x * CW
	var oz := _build_key.y * CW
	var types := ch.types
	var solid := ch.solid
	var any := ch.any
	var coll := ch.coll

	# Hoisted: the fold below runs once per voxel, twelve thousand times a chunk,
	# and `Blocks.is_opaque(id)` is a static call wrapping exactly this read.
	var t_opaque := Blocks.opaque_table()
	var t_collide := Blocks.collide_table()

	while _build_col < COLS:
		# The clock is read every eighth column rather than every column: a
		# column is some sixty microseconds, so this overruns the deadline by
		# half a millisecond at worst, and reading it 256 times a chunk would
		# itself be measurable.
		if _build_col & 7 == 0 and Time.get_ticks_usec() >= deadline_us:
			return false
		var lx := _build_col >> 4
		var lz := _build_col & 15
		_build_col += 1
		var gx := ox + lx
		var gz := oz + lz
		var ci := lx * CW + lz
		var base := ci * WH
		gen.fill_column(gx, gz, types, base)
		# Fold the column into its three bitmasks in one pass: what exists,
		# what occludes, and what an entity cannot walk through.
		var m_any := 0
		var m_solid := 0
		var m_coll := 0
		var bit := 1
		for y in WH:
			var id := types[base + y]
			if id != Blocks.AIR:
				m_any |= bit
				if t_opaque[id] == 1:
					m_solid |= bit
				if t_collide[id] == 1:
					m_coll |= bit
			bit <<= 1
		any[ci] = m_any
		solid[ci] = m_solid
		coll[ci] = m_coll
	return true


## Publish the finished chunk: it becomes part of the world here and nowhere
## else, which is what keeps the incremental fill invisible to everything.
func _finish_chunk() -> void:
	var ch := _building
	var key := _build_key
	_building = null
	ch.generated = true
	_chunks[key] = ch

	# structures written into us by neighbours that generated first
	var pend = _pending.get(key)
	if pend != null:
		for e in pend:
			_write_raw(ch, e.x, e.y, e.z, e.w)
		_pending.erase(key)

	var pd := Prof.mark()
	_decorate(ch)
	Prof.add(&"gen.decorate", pd)

	ch.dirty = true
	_mesh_queue.append(key)
	# our decorations may have reached into already-meshed neighbours
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dz != 0:
				_touch(key + Vector2i(dx, dz))


## Direct write during generation; queues the block if the target chunk is not
## resident yet so structures can straddle chunk borders.
func _write_gen(gx: int, gy: int, gz: int, id: int) -> void:
	if gy < 0 or gy >= WH:
		return
	if _live:
		set_block(gx, gy, gz, id)
		return
	var key := Vector2i(gx >> 4, gz >> 4)
	var c: Chunk = _chunks.get(key)
	if c == null or not c.generated:
		if not _pending.has(key):
			_pending[key] = []
		_pending[key].append(Vector4i(gx, gy, gz, id))
		return
	_write_raw(c, gx, gy, gz, id)


func _write_raw(c: Chunk, gx: int, gy: int, gz: int, id: int) -> void:
	var ci := ((gx & 15) * CW) + (gz & 15)
	c.types[ci * WH + gy] = id
	var bit := 1 << gy
	if id == Blocks.AIR:
		c.any[ci] &= ~bit
		c.solid[ci] &= ~bit
		c.coll[ci] &= ~bit
	else:
		c.any[ci] |= bit
		if Blocks.is_opaque(id):
			c.solid[ci] |= bit
		else:
			c.solid[ci] &= ~bit
		if Blocks.is_solid(id):
			c.coll[ci] |= bit
		else:
			c.coll[ci] &= ~bit


func _decorate(ch: Chunk) -> void:
	gen.decorate(ch.cx, ch.cz, _write_gen, gen.surface_height,
		func(x: int, y: int, z: int) -> int: return get_block(x, y, z))
	_place_structure(ch)


## Structures are chosen from a hash of the chunk position, so they are stable
## across reloads and never have to be remembered — only the entities that live
## inside them do, and those are queued for the game to spawn.
func _place_structure(ch: Chunk) -> void:
	var spec := gen.structure_for(ch.cx, ch.cz)
	if spec.is_empty():
		return
	var ox := ch.cx * CW
	var oz := ch.cz * CW
	var gx := ox + 4 + (_hash3(ch.cx, 1, ch.cz, 9) % 6)
	var gz := oz + 4 + (_hash3(ch.cx, 2, ch.cz, 13) % 6)
	match StringName(spec["kind"]):
		&"house":
			_try_house(gx, gz)
		&"village":
			_build_village(gx, gz, int(spec.get("houses", 3)))
		&"ruin":
			_build_ruin(gx, gz)
		&"camp":
			_build_camp(gx, gz)
		&"mineshaft":
			_build_mineshaft(gx, gz)


## A cluster of houses with a lit square between them, and a roster of villagers
## queued for the game to spawn once the chunk is resident.
func _build_village(gx: int, gz: int, houses: int) -> void:
	var lo := 999
	var hi := -999
	var span := 10 + houses * 8
	for x in range(gx - 4, gx + span):
		for z in range(gz - 4, gz + 14):
			var sfc := surface_height(x, z)
			lo = mini(lo, sfc)
			hi = maxi(hi, sfc)
	if hi - lo > 5 or lo - 1 <= gen.palette.sea_level:
		return
	var placed := 0
	for i in houses:
		var hx := gx + i * 9
		var hz := gz + (i % 2) * 8
		_flatten(hx - 1, hz - 1, 9, 8, lo)
		_build_house(hx, hz, lo)
		placed += 1
	# a square: lit, paved, and somewhere for the roster to stand
	for x in range(gx - 2, gx + span - 6):
		for z in range(gz + 3, gz + 6):
			_flatten_cell(x, z, lo)
			_write_gen(x, lo, z, Blocks.id(&"stone_brick"))
	for i in placed + 1:
		_write_gen(gx - 1 + i * 9, lo + 1, gz + 4, Blocks.id(&"lantern"))
	pending_structures.append({
		"kind": &"village", "at": Vector3i(gx, lo + 1, gz + 4),
		"count": placed + 2,
	})


## A broken shell of ancient masonry with a sealed vault at the back of it. The
## vault has exactly one way in, and which wall it is in depends on the seed —
## so finding it is a matter of turning the camera rather than digging.
func _build_ruin(gx: int, gz: int) -> void:
	var lo := 999
	for x in range(gx - 1, gx + 13):
		for z in range(gz - 1, gz + 11):
			lo = mini(lo, surface_height(x, z))
	if lo - 1 <= gen.palette.sea_level:
		return
	var wall := Blocks.id(&"ancient_wall")
	var floor_id := Blocks.id(&"ancient_floor")
	var accent := Blocks.id(&"ancient_accent")
	_flatten(gx - 1, gz - 1, 14, 12, lo)
	for x in 12:
		for z in 10:
			_write_gen(gx + x, lo, gz + z, floor_id)
			for y in range(lo + 1, lo + 6):
				_write_gen(gx + x, y, gz + z, Blocks.AIR)
	# a ragged perimeter: half the courses have fallen
	for x in 12:
		for z in 10:
			if x != 0 and x != 11 and z != 0 and z != 9:
				continue
			var height := 1 + (_hash3(gx + x, 0, gz + z, 7) % 4)
			for y in height:
				_write_gen(gx + x, lo + 1 + y, gz + z, wall)
	# the vault
	for x in range(4, 8):
		for z in range(3, 7):
			for y in range(lo + 1, lo + 5):
				_write_gen(gx + x, y, gz + z, Blocks.AIR)
			_write_gen(gx + x, lo + 5, gz + z, wall)
	for x in range(3, 9):
		for z in range(2, 8):
			var edge := x == 3 or x == 8 or z == 2 or z == 7
			if not edge:
				continue
			for y in range(lo + 1, lo + 5):
				_write_gen(gx + x, y, gz + z, wall)
	# exactly one door, on a seed-chosen wall
	var side := _hash3(gx, 3, gz, 404) % 4
	var door := Vector3i(gx + 5, lo + 1, gz + 2)
	match side:
		1: door = Vector3i(gx + 5, lo + 1, gz + 7)
		2: door = Vector3i(gx + 3, lo + 1, gz + 4)
		3: door = Vector3i(gx + 8, lo + 1, gz + 4)
	_write_gen(door.x, door.y, door.z, Blocks.AIR)
	_write_gen(door.x, door.y + 1, door.z, Blocks.AIR)
	_write_gen(gx + 5, lo + 4, gz + 4, accent)
	pending_structures.append({
		"kind": &"ruin", "at": Vector3i(gx + 5, lo + 1, gz + 4),
	})


## A hostile camp: a fire, a couple of tents and something guarding it.
func _build_camp(gx: int, gz: int) -> void:
	var lo := 999
	for x in range(gx, gx + 8):
		for z in range(gz, gz + 8):
			lo = mini(lo, surface_height(x, z))
	if lo - 1 <= gen.palette.sea_level:
		return
	_flatten(gx, gz, 8, 8, lo)
	_write_gen(gx + 4, lo + 1, gz + 4, Blocks.id(&"campfire"))
	for corner in [Vector2i(1, 1), Vector2i(6, 1), Vector2i(1, 6)]:
		for x in 2:
			for z in 2:
				_write_gen(gx + corner.x + x, lo + 1, gz + corner.y + z,
					Blocks.id(&"thatch"))
	pending_structures.append({
		"kind": &"camp", "at": Vector3i(gx + 4, lo + 1, gz + 4), "count": 3,
	})


## A timbered shaft down into the mid stratum, lit and lined. This is the
## cutaway's showcase: from the surface it is a hole, and the moment you drop
## into it the camera peels the hillside off and the whole gallery is legible.
func _build_mineshaft(gx: int, gz: int) -> void:
	var top := surface_height(gx, gz)
	if top - 1 <= gen.palette.sea_level:
		return
	var floor_y := maxi(top - 18, 4)
	for y in range(floor_y, top + 1):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				_write_gen(gx + dx, y, gz + dz, Blocks.AIR)
	for y in range(floor_y, top + 1):
		_write_gen(gx + 1, y, gz, Blocks.id(&"wooden_ladder"))
	for y in range(floor_y, top, 4):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if absi(dx) == 2 or absi(dz) == 2:
					_write_gen(gx + dx, y, gz + dz, Blocks.PLANKS)
		_write_gen(gx - 1, y + 2, gz, Blocks.id(&"lantern"))
	# a gallery running off the bottom, with ore left in the walls
	for i in 20:
		for dy in 4:
			for dz in range(-1, 2):
				_write_gen(gx + 2 + i, floor_y + dy, gz + dz, Blocks.AIR)
		if i % 5 == 0:
			for dy in 4:
				_write_gen(gx + 2 + i, floor_y + dy, gz - 2, Blocks.PLANKS)
				_write_gen(gx + 2 + i, floor_y + dy, gz + 2, Blocks.PLANKS)
			_write_gen(gx + 2 + i, floor_y + 3, gz, Blocks.id(&"lantern"))
	pending_structures.append({
		"kind": &"mineshaft", "at": Vector3i(gx + 12, floor_y + 1, gz),
	})


## Level a footprint to `target` and clear the air above it.
func _flatten(gx: int, gz: int, w: int, d: int, target: int) -> void:
	for x in range(gx, gx + w):
		for z in range(gz, gz + d):
			_flatten_cell(x, z, target)


func _flatten_cell(x: int, z: int, target: int) -> void:
	for y in range(target + 1, WH):
		_write_gen(x, y, z, Blocks.AIR)
	for y in range(maxi(target - 3, 1), target + 1):
		if get_block(x, y, z) == Blocks.AIR:
			_write_gen(x, y, z, gen.palette.sub)


func _try_house(gx: int, gz: int) -> void:
	var w := 7
	var d := 6
	# reject slopes: everything under the footprint must be within a block
	var lo := 999
	var hi := -999
	for x in range(gx - 1, gx + w + 1):
		for z in range(gz - 1, gz + d + 1):
			var s := surface_height(x, z)
			lo = mini(lo, s)
			hi = maxi(hi, s)
	if hi - lo > 3 or lo - 1 <= SEA:
		return
	_build_house(gx, gz, lo)


func _build_house(gx: int, gz: int, base: int) -> void:
	var w := 7
	var d := 6
	var wall := Blocks.STONE_BRICK if (_hash3(gx, 3, gz, 17) % 2 == 0) else Blocks.BRICK
	var height := 5

	# foundation + floor
	for x in w:
		for z in d:
			for y in range(base - 2, base):
				_write_gen(gx + x, y, gz + z, Blocks.COBBLE)
			_write_gen(gx + x, base, gz + z, Blocks.DARK_PLANKS)
			# clear the interior volume
			for y in range(base + 1, base + height + 1):
				_write_gen(gx + x, y, gz + z, Blocks.AIR)

	# walls
	for y in range(base + 1, base + height):
		for x in w:
			_write_gen(gx + x, y, gz, wall)
			_write_gen(gx + x, y, gz + d - 1, wall)
		for z in d:
			_write_gen(gx, y, gz + z, wall)
			_write_gen(gx + w - 1, y, gz + z, wall)

	# corner posts
	for y in range(base + 1, base + height):
		_write_gen(gx, y, gz, Blocks.LOG)
		_write_gen(gx + w - 1, y, gz, Blocks.LOG)
		_write_gen(gx, y, gz + d - 1, Blocks.LOG)
		_write_gen(gx + w - 1, y, gz + d - 1, Blocks.LOG)

	# windows on all four walls, so the cutaway reads well from any angle
	for x in [2, 4]:
		_write_gen(gx + x, base + 2, gz, Blocks.GLASS)
		_write_gen(gx + x, base + 3, gz, Blocks.GLASS)
		_write_gen(gx + x, base + 2, gz + d - 1, Blocks.GLASS)
		_write_gen(gx + x, base + 3, gz + d - 1, Blocks.GLASS)
	for z in [2, 3]:
		_write_gen(gx, base + 2, gz + z, Blocks.GLASS)
		_write_gen(gx + w - 1, base + 2, gz + z, Blocks.GLASS)

	# doorway
	_write_gen(gx + 3, base + 1, gz, Blocks.AIR)
	_write_gen(gx + 3, base + 2, gz, Blocks.AIR)

	# roof — stepped pyramid, gives the cutaway something chunky to slice
	var ry := base + height
	var inset := 0
	while inset * 2 < mini(w, d):
		for x in range(inset, w - inset):
			for z in range(inset, d - inset):
				_write_gen(gx + x, ry, gz + z, Blocks.ROOF)
		ry += 1
		inset += 1

	# furnishings
	_write_gen(gx + 1, base + 1, gz + 1, Blocks.PLANKS)
	_write_gen(gx + 2, base + 1, gz + 1, Blocks.PLANKS)
	_write_gen(gx + w - 2, base + 1, gz + d - 2, Blocks.LAMP)
	_write_gen(gx + 1, base + height - 1, gz + d - 2, Blocks.LAMP)
	_write_gen(gx + w - 2, base + 1, gz + 1, Blocks.LOG)


func _place_tree(gx: int, base: int, gz: int) -> void:
	var h := 4 + (_hash3(gx, 1, gz, 3) % 3)
	for y in h:
		_write_gen(gx, base + y, gz, Blocks.LOG)
	var top := base + h
	for dy in range(-2, 2):
		var r := 2 if dy < 0 else 1
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r:
					continue
				if dx == 0 and dz == 0 and dy < 1:
					continue
				_write_gen(gx + dx, top + dy, gz + dz, Blocks.LEAVES)
	_write_gen(gx, top + 1, gz, Blocks.LEAVES)


## Hand-authored starting area: a mineshaft with a ladder-well and a side
## gallery, so the cutaway system has something to show off immediately.
func carve_spawn_features(spawn: Vector3i) -> void:
	_live = true
	var sx := spawn.x
	var sz := spawn.z
	var top := column_top(sx, sz)
	if top < 0:
		return

	# vertical shaft, 3x3, going 14 down
	var floor_y := maxi(top - 14, 3)
	for y in range(floor_y, top + 1):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				set_block(sx + 4 + dx, y, sz + dz, Blocks.AIR)
	# plank lining on the way down
	for y in range(floor_y, top + 1, 3):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if absi(dx) == 2 or absi(dz) == 2:
					if get_block(sx + 4 + dx, y, sz + dz) != Blocks.AIR:
						set_block(sx + 4 + dx, y, sz + dz, Blocks.PLANKS)

	# horizontal gallery running along +X at the bottom
	for i in 26:
		for dy in range(0, 4):
			for dz in range(-1, 2):
				set_block(sx + 4 + i, floor_y + dy, sz + dz, Blocks.AIR)
		if i % 6 == 0:
			for dy in range(0, 4):
				set_block(sx + 4 + i, floor_y + dy, sz - 2, Blocks.PLANKS)
				set_block(sx + 4 + i, floor_y + dy, sz + 2, Blocks.PLANKS)
			set_block(sx + 4 + i, floor_y + 3, sz, Blocks.LAMP)
		if i % 5 == 2:
			set_block(sx + 4 + i, floor_y, sz + 1, Blocks.CRYSTAL_ORE)

	# a small chamber at the far end
	for dx in range(0, 7):
		for dz in range(-3, 4):
			for dy in range(0, 6):
				set_block(sx + 30 + dx, floor_y + dy, sz + dz, Blocks.AIR)
	set_block(sx + 33, floor_y + 4, sz, Blocks.LAMP)
	for dz in range(-2, 3):
		set_block(sx + 33, floor_y, sz + dz, Blocks.CRYSTAL)

	# a staircase down from the surface into the shaft, so you can walk in
	for i in 10:
		for dy in range(0, 4):
			for dz in range(-1, 2):
				set_block(sx - i, top - i / 2 + dy, sz + dz, Blocks.AIR)
		for dz in range(-1, 2):
			set_block(sx - i, top - i / 2 - 1, sz + dz, Blocks.PLANKS)

	# a starter cabin a short walk away, on a properly levelled pad so the
	# interior reveal has something to demonstrate on from the first second
	var hx := sx - 4
	var hz := sz + 9
	var pad := 5
	var lo := 999
	for x in range(hx - pad, hx + 7 + pad):
		for z in range(hz - pad, hz + 6 + pad):
			var t := column_top(x, z)
			if t >= 0:
				lo = mini(lo, t)
	if lo < 900:
		for x in range(hx - pad, hx + 7 + pad):
			for z in range(hz - pad, hz + 6 + pad):
				# blend the pad out to the untouched terrain at its rim
				var edge := maxi(maxi(hx - 1 - x, x - (hx + 7)), maxi(hz - 1 - z, z - (hz + 6)))
				var target := lo + maxi(0, edge - 1)
				for y in range(target + 1, WH):
					set_block(x, y, z, Blocks.AIR)
				for y in range(maxi(target - 3, 1), target + 1):
					set_block(x, y, z, Blocks.DIRT)
				set_block(x, target, z, Blocks.GRASS)
		_build_house(hx, hz, lo)
	house_spawn = Vector3i(hx + 3, lo + 1, hz + 3)


## Somewhere to stand: the top of a loaded column that is solid, dry, and has
## headroom. Deliberately written against the block *flags* rather than against
## a list of ids, so every biome's surface cover works without being enumerated.
func find_spawn() -> Vector3i:
	for r in 16:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and maxi(absi(dx), absi(dz)) != r:
					continue
				var cell := _spawn_candidate(dx, dz)
				if cell.y >= 0:
					return cell
	return Vector3i(0, WH - 4, 0)


func _spawn_candidate(gx: int, gz: int) -> Vector3i:
	if not is_loaded(gx, gz):
		return Vector3i(gx, -1, gz)
	var top := column_top(gx, gz)
	if top < 2 or top >= WH - 3:
		return Vector3i(gx, -1, gz)
	var here := get_block(gx, top, gz)
	if not Blocks.is_solid(here) or Blocks.is_liquid(here):
		return Vector3i(gx, -1, gz)
	if Blocks.touch_damage(here) > 0.0:
		return Vector3i(gx, -1, gz)
	# two blocks of headroom, so we do not land inside a tree
	if world_occupied(gx, top + 1, gz) or world_occupied(gx, top + 2, gz):
		return Vector3i(gx, -1, gz)
	return Vector3i(gx, top + 1, gz)


func world_occupied(gx: int, gy: int, gz: int) -> bool:
	return is_solid_at(gx, gy, gz)


# =============================================================================
# meshing
# =============================================================================

func _fill_ext(ch: Chunk) -> void:
	var refs := []
	refs.resize(9)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			refs[(dz + 1) * 3 + (dx + 1)] = _chunks.get(Vector2i(ch.cx + dx, ch.cz + dz))
	var es := _ext_solid
	var ea := _ext_any
	for lx in range(-1, CW + 1):
		var ncx := 0
		var ax := lx
		if lx < 0:
			ncx = -1
			ax = CW - 1
		elif lx >= CW:
			ncx = 1
			ax = 0
		for lz in range(-1, CW + 1):
			var ncz := 0
			var az := lz
			if lz < 0:
				ncz = -1
				az = CW - 1
			elif lz >= CW:
				ncz = 1
				az = 0
			var c: Chunk = refs[(ncz + 1) * 3 + (ncx + 1)]
			var e := (lx + 1) * EXT + (lz + 1)
			if c == null:
				es[e] = 0
				ea[e] = 0
			else:
				var ci := ax * CW + az
				es[e] = c.solid[ci]
				ea[e] = c.any[ci]
	_ext_solid = es
	_ext_any = ea


func _build_chunk_mesh(ch: Chunk) -> void:
	ch.dirty = false
	_fill_ext(ch)

	var es := _ext_solid
	var ea := _ext_any
	var bi := _bitidx
	var types := ch.types

	# face records: pos = x | y<<8 | z<<16 | dir<<24, meta = id | ao<<8..15
	var op_pos := PackedInt32Array()
	var op_meta := PackedInt32Array()
	var gl_pos := PackedInt32Array()
	var gl_meta := PackedInt32Array()
	# cross-quad records: cell = x | y<<8 | z<<16, plus the block id
	var cr_cell := PackedInt32Array()
	var cr_id := PackedInt32Array()

	for lx in CW:
		for lz in CW:
			var ci := lx * CW + lz
			var a := ch.any[ci]
			if a == 0:
				continue
			var s := ch.solid[ci]
			var e := (lx + 1) * EXT + (lz + 1)

			var m_px := es[e + EXT]
			var m_nx := es[e - EXT]
			var m_pz := es[e + 1]
			var m_nz := es[e - 1]
			var m_pxpz := es[e + EXT + 1]
			var m_pxnz := es[e + EXT - 1]
			var m_nxpz := es[e - EXT + 1]
			var m_nxnz := es[e - EXT - 1]

			var base := ci * WH
			var xyz := lx | (lz << 16)

			# ---------------------------------------------------- opaque faces
			# +Y
			var f := s & ~(s >> 1)
			while f != 0:
				var b := f & -f
				f &= f - 1
				var y := bi[b % 67]
				var yu := y + 1
				var n_px := (m_px >> yu) & 1
				var n_nx := (m_nx >> yu) & 1
				var n_pz := (m_pz >> yu) & 1
				var n_nz := (m_nz >> yu) & 1
				var a0 := _ao(n_nx, n_pz, (m_nxpz >> yu) & 1)
				var a1 := _ao(n_px, n_pz, (m_pxpz >> yu) & 1)
				var a2 := _ao(n_px, n_nz, (m_pxnz >> yu) & 1)
				var a3 := _ao(n_nx, n_nz, (m_nxnz >> yu) & 1)
				op_pos.append(xyz | (y << 8) | (2 << 24))
				op_meta.append(types[base + y] | (a0 << 8) | (a1 << 10) | (a2 << 12) | (a3 << 14))

			# -Y (skip the world floor)
			f = (s & ~(s << 1)) & ~1
			while f != 0:
				var b := f & -f
				f &= f - 1
				var y := bi[b % 67]
				var yd := y - 1
				var n_px := (m_px >> yd) & 1
				var n_nx := (m_nx >> yd) & 1
				var n_pz := (m_pz >> yd) & 1
				var n_nz := (m_nz >> yd) & 1
				var a0 := _ao(n_nx, n_nz, (m_nxnz >> yd) & 1)
				var a1 := _ao(n_px, n_nz, (m_pxnz >> yd) & 1)
				var a2 := _ao(n_px, n_pz, (m_pxpz >> yd) & 1)
				var a3 := _ao(n_nx, n_pz, (m_nxpz >> yd) & 1)
				op_pos.append(xyz | (y << 8) | (3 << 24))
				op_meta.append(types[base + y] | (a0 << 8) | (a1 << 10) | (a2 << 12) | (a3 << 14))

			# +X / -X / +Z / -Z share a shape: side column + two diagonal columns
			for dir in 4:
				var side: int
				var cp: int
				var cn: int
				match dir:
					0:
						f = s & ~m_px
						side = m_px
						cp = m_pxpz
						cn = m_pxnz
					1:
						f = s & ~m_nx
						side = m_nx
						cp = m_nxnz
						cn = m_nxpz
					2:
						f = s & ~m_pz
						side = m_pz
						cp = m_nxpz
						cn = m_pxpz
					_:
						f = s & ~m_nz
						side = m_nz
						cp = m_pxnz
						cn = m_nxnz
				var face_id: int = SIDE_FACE[dir]
				while f != 0:
					var b := f & -f
					f &= f - 1
					var y := bi[b % 67]
					var up := (side >> (y + 1)) & 1
					var dn := 1 if y == 0 else (side >> (y - 1)) & 1
					var sp := (cp >> y) & 1
					var sn := (cn >> y) & 1
					var c_dn_n := 1 if y == 0 else (cn >> (y - 1)) & 1
					var c_dn_p := 1 if y == 0 else (cp >> (y - 1)) & 1
					var c_up_n := (cn >> (y + 1)) & 1
					var c_up_p := (cp >> (y + 1)) & 1
					# vertex order is (-Y,+t) (-Y,-t) (+Y,-t) (+Y,+t) for +X/-X and
					# (-Y,-t) (-Y,+t) (+Y,+t) (+Y,-t) for +Z/-Z; cp/cn are chosen
					# above so that "p" always means the first-listed tangent.
					var a0 := _ao(dn, sp, c_dn_p)
					var a1 := _ao(dn, sn, c_dn_n)
					var a2 := _ao(up, sn, c_up_n)
					var a3 := _ao(up, sp, c_up_p)
					op_pos.append(xyz | (y << 8) | (face_id << 24))
					op_meta.append(types[base + y] | (a0 << 8) | (a1 << 10) | (a2 << 12) | (a3 << 14))

			# ------------------------------------------------- cross quads
			# Foliage, crops and torches are two crossed quads rather than a
			# cube. Split them out of the non-opaque set first; whatever is
			# left is a real transparent cube (glass, ice, water).
			var g := a & ~s
			var cross := 0
			if g != 0:
				var scan := g
				while scan != 0:
					var cb := scan & -scan
					scan &= scan - 1
					var cy: int = bi[cb % 67]
					if Blocks.render_of(types[base + cy]) == Blocks.Render.CROSS:
						cross |= cb
				g &= ~cross
				while cross != 0:
					var cb2 := cross & -cross
					cross &= cross - 1
					var cy2: int = bi[cb2 % 67]
					cr_cell.append(xyz | (cy2 << 8))
					cr_id.append(types[base + cy2])

			# --------------------------------------------- transparent faces
			# Glass/ice only hide faces against other non-air blocks, so a pane
			# still shows its outline when set into a wall.
			if g != 0:
				var ga := ea[e]
				var gm := [
					g & ~(ga >> 1), 2,
					(g & ~(ga << 1)) & ~1, 3,
					g & ~ea[e + EXT], 0,
					g & ~ea[e - EXT], 1,
					g & ~ea[e + 1], 4,
					g & ~ea[e - 1], 5,
				]
				for gi in 6:
					var gf: int = gm[gi * 2]
					var gd: int = gm[gi * 2 + 1]
					while gf != 0:
						var gb := gf & -gf
						gf &= gf - 1
						var gy: int = bi[gb % 67]
						# transparent blocks skip AO entirely (full brightness)
						gl_pos.append(xyz | (gy << 8) | (gd << 24))
						gl_meta.append(types[base + gy] | (3 << 8) | (3 << 10) | (3 << 12) | (3 << 14))

	# ------------------------------------------------------------ build arrays
	var mesh := ArrayMesh.new()
	var added := 0
	if op_pos.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _faces_to_arrays(op_pos, op_meta))
		mesh.surface_set_material(added, mat_opaque)
		added += 1
	if gl_pos.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _faces_to_arrays(gl_pos, gl_meta))
		mesh.surface_set_material(added, mat_glass)
		added += 1
	if cr_cell.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _cross_arrays(cr_cell, cr_id))
		mesh.surface_set_material(added, mat_cross)
		added += 1

	if ch.mi == null:
		ch.mi = MeshInstance3D.new()
		ch.mi.name = "Chunk_%d_%d" % [ch.cx, ch.cz]
		ch.mi.position = Vector3(ch.cx * CW, 0, ch.cz * CW)
		ch.mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(ch.mi)
	ch.mi.mesh = mesh if added > 0 else null
	# A chunk that streams in behind the plane must arrive already hidden, or it
	# pops into view for however long it takes the player to cross a boundary.
	ch.mi.visible = not cutaway.planar_chunk_hidden(ch.cx, ch.cz)


## Two quads crossed at 90° per cell. `COLOR.b` carries the vertex's height up
## the plant, which is what the cross shader sways by, so roots stay planted.
const CROSS_QUADS := [
	[Vector3(0.09, 0.0, 0.09), Vector3(0.91, 0.0, 0.91),
	 Vector3(0.91, 1.0, 0.91), Vector3(0.09, 1.0, 0.09)],
	[Vector3(0.91, 0.0, 0.09), Vector3(0.09, 0.0, 0.91),
	 Vector3(0.09, 1.0, 0.91), Vector3(0.91, 1.0, 0.09)],
]
const CROSS_UV := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]


func _cross_arrays(cells: PackedInt32Array, ids: PackedInt32Array) -> Array:
	var n := cells.size() * 2         # two quads per plant
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * 4)
	norms.resize(n * 4)
	uvs.resize(n * 4)
	cols.resize(n * 4)
	idx.resize(n * 6)

	var tw := 1.0 / float(TexGen.ATLAS_COLS)
	var th := 1.0 / float(TexGen.ATLAS_ROWS)
	var eps := 0.0008
	var vi := 0
	var ii := 0
	for k in cells.size():
		var p := cells[k]
		var id := ids[k]
		var origin := Vector3(p & 255, (p >> 8) & 255, (p >> 16) & 255)
		var tile := Blocks.tile_of(id, 4)
		var emis := Blocks.emission(id)
		var u0 := float(tile % TexGen.ATLAS_COLS) * tw + eps
		var v0 := float(tile / TexGen.ATLAS_COLS) * th + eps
		var uw := tw - eps * 2.0
		var vh := th - eps * 2.0
		for q in 2:
			var quad: Array = CROSS_QUADS[q]
			var nrm: Vector3 = (Vector3(1, 0, -1) if q == 0 else Vector3(1, 0, 1)).normalized()
			for j in 4:
				var v: Vector3 = quad[j]
				verts[vi + j] = origin + v
				norms[vi + j] = nrm
				var uv: Vector2 = CROSS_UV[j]
				uvs[vi + j] = Vector2(u0 + uv.x * uw, v0 + uv.y * vh)
				cols[vi + j] = Color(1.0, emis, v.y, 1.0)
			idx[ii] = vi; idx[ii + 1] = vi + 2; idx[ii + 2] = vi + 1
			idx[ii + 3] = vi; idx[ii + 4] = vi + 3; idx[ii + 5] = vi + 2
			vi += 4
			ii += 6

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


static func _ao(s1: int, s2: int, c: int) -> int:
	if s1 == 1 and s2 == 1:
		return 0
	return 3 - s1 - s2 - c


func _faces_to_arrays(fpos: PackedInt32Array, fmeta: PackedInt32Array) -> Array:
	var n := fpos.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * 4)
	norms.resize(n * 4)
	uvs.resize(n * 4)
	cols.resize(n * 4)
	idx.resize(n * 6)

	var tw := 1.0 / float(TexGen.ATLAS_COLS)
	var th := 1.0 / float(TexGen.ATLAS_ROWS)
	var eps := 0.0008

	var uw := tw - eps * 2.0
	var vh := th - eps * 2.0
	# Hoisted out of the loop: every one of these was a Variant index or a heap
	# allocation *per face*, and a surface chunk has several thousand faces.
	var uv0: Vector2 = FLAT_UV[0]
	var uv1: Vector2 = FLAT_UV[1]
	var uv2: Vector2 = FLAT_UV[2]
	var uv3: Vector2 = FLAT_UV[3]

	var vi := 0
	var ii := 0
	for k in n:
		var p := fpos[k]
		var m := fmeta[k]
		var x := p & 255
		var y := (p >> 8) & 255
		var z := (p >> 16) & 255
		var dir := (p >> 24) & 255
		var id := m & 255
		var tile := Blocks.tile_of(id, dir)
		var emis := Blocks.emission(id)

		var a0: int = (m >> 8) & 3
		var a1: int = (m >> 10) & 3
		var a2: int = (m >> 12) & 3
		var a3: int = (m >> 14) & 3

		# A touch of per-block tone jitter keeps big flat faces from banding.
		# Inlined rather than calling WorldGen.hash3: the call was one of the
		# three most expensive things in the mesher purely by being a call.
		var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
		h = (h ^ (h >> 13)) * 1274126177
		var tone := 0.93 + float((h >> 7) & 127) / 128.0 * 0.14

		var u0 := float(tile % TexGen.ATLAS_COLS) * tw + eps
		var v0 := float(tile / TexGen.ATLAS_COLS) * th + eps

		var origin := Vector3(x, y, z)
		var nrm: Vector3 = FLAT_NORMAL[dir]
		var vb := dir * 4
		verts[vi] = origin + FLAT_VERTS[vb]
		verts[vi + 1] = origin + FLAT_VERTS[vb + 1]
		verts[vi + 2] = origin + FLAT_VERTS[vb + 2]
		verts[vi + 3] = origin + FLAT_VERTS[vb + 3]
		norms[vi] = nrm
		norms[vi + 1] = nrm
		norms[vi + 2] = nrm
		norms[vi + 3] = nrm
		uvs[vi] = Vector2(u0 + uv0.x * uw, v0 + uv0.y * vh)
		uvs[vi + 1] = Vector2(u0 + uv1.x * uw, v0 + uv1.y * vh)
		uvs[vi + 2] = Vector2(u0 + uv2.x * uw, v0 + uv2.y * vh)
		uvs[vi + 3] = Vector2(u0 + uv3.x * uw, v0 + uv3.y * vh)
		cols[vi] = Color(FLAT_AO[a0] * tone, emis, 1.0, 1.0)
		cols[vi + 1] = Color(FLAT_AO[a1] * tone, emis, 1.0, 1.0)
		cols[vi + 2] = Color(FLAT_AO[a2] * tone, emis, 1.0, 1.0)
		cols[vi + 3] = Color(FLAT_AO[a3] * tone, emis, 1.0, 1.0)

		# Godot winds front faces clockwise; flip the quad's diagonal when the
		# occlusion is asymmetric so the AO gradient stays smooth.
		if a0 + a2 > a1 + a3:
			idx[ii] = vi + 1; idx[ii + 1] = vi + 3; idx[ii + 2] = vi + 2
			idx[ii + 3] = vi + 1; idx[ii + 4] = vi; idx[ii + 5] = vi + 3
		else:
			idx[ii] = vi; idx[ii + 1] = vi + 2; idx[ii + 2] = vi + 1
			idx[ii + 3] = vi; idx[ii + 4] = vi + 3; idx[ii + 5] = vi + 2
		vi += 4
		ii += 6

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


# =============================================================================
# cutaway cross-section caps
# =============================================================================

## Called every frame. Almost every call is a no-op: the cut is anchored to
## whole voxels, so nothing happens until the player crosses a block boundary or
## the camera settles on a new facing.
func update_cutaway(cam_pos: Vector3, target_pos: Vector3) -> void:
	var moved := cutaway.place(cam_pos, target_pos)
	if not moved:
		return
	# Only planar needs to know whether the view is blocked, and only so it can
	# stay dormant in the open. One raycast per block crossing, not per frame.
	if cutaway.mode == Cutaway.Mode.PLANAR:
		cutaway.occluded = _is_occluded(cam_pos, target_pos)


## Rebuild the cross-section if — and only if — something it depends on changed.
## Returns true when it actually rebuilt.
##
## One signature governs the whole cut. While it holds, the cross-section is
## unchanged and there is nothing at all to do, which is the point of quantising
## the predicate to voxel coordinates in the first place. Comparing it costs
## three integer-vector compares and allocates nothing, so the frame on which
## the player does not cross a block boundary is genuinely free.
func refresh_cutaway() -> bool:
	var head := cutaway.sig_head(_world_version)
	var lo := cutaway.sig_lo()
	var hi := cutaway.sig_hi()
	if head == _cut_head and lo == _cut_lo and hi == _cut_hi:
		return false
	_cut_head = head
	_cut_lo = lo
	_cut_hi = hi
	cut_rebuilds += 1
	if cutaway.enabled and cutaway.mode == Cutaway.Mode.FILL:
		_rebuild_fill()
	_rebuild_caps()
	_apply_chunk_visibility()
	return true


## Force the next `refresh_cutaway` to rebuild whatever the player did.
func _invalidate_cut() -> void:
	_cut_head = Vector4i(-1, -1, -1, -1)


## Hide the chunks that lie wholly past the plane.
##
## Their fragments are all discarded anyway, but a discarded fragment has still
## been transformed, rasterised and shaded up to the point of the `discard`, and
## the chunk has still been submitted to the shadow pass. In planar mode about
## half the streamed world is on the far side of the plane, and this is the only
## saving in the whole system that grows with view distance instead of with the
## size of the cross-section.
##
## The early return is not an optimisation so much as the price of admission.
## Sweeping every loaded chunk costs about two milliseconds — `Node3D.visible`
## propagates through a subtree and emits a signal, so it is nothing like a
## field write — and doing that on every step along the view axis cost more than
## the cross-section rebuild it was meant to accompany. The threshold only moves
## once every sixteen blocks, and while it holds no chunk can have changed side.
func _apply_chunk_visibility() -> void:
	var key := cutaway.planar_cull_key()
	if key == _cull_key:
		return
	_cull_key = key
	var axis_x := key.x == 1
	for k: Vector2i in _chunks:
		var c: Chunk = _chunks[k]
		if c.mi == null:
			continue
		var want := true
		if key.x != 0:
			var cc := k.x if axis_x else k.y
			want = not (cc >= key.z if key.y > 0 else cc <= key.z)
		if c.mi.visible != want:
			c.mi.visible = want


func set_cutaway_mode(m: int) -> void:
	if cutaway.mode == m:
		return
	cutaway.mode = m
	cutaway.clear_fill()
	if m == Cutaway.Mode.PLANAR:
		cutaway.occluded = _is_occluded(cutaway.camera_position, cutaway.target_position)
	_invalidate_cut()


## Is the straight line from the lens to the player actually blocked? Only the
## planar mode needs to know, and only so it can stay dormant in the open.
func _is_occluded(cam_pos: Vector3, target_pos: Vector3) -> bool:
	var to := (target_pos + Vector3(0, 0.9, 0)) - cam_pos
	var dist := to.length()
	if dist < 0.01:
		return false
	var hit := raycast(cam_pos, to / dist, dist, false)
	return hit.get("hit", false)


func set_cutaway_enabled(v: bool) -> void:
	if cutaway.enabled == v:
		return
	cutaway.enabled = v
	_invalidate_cut()


## Ghost opacity and the mine-through toggle. Both are pure presentation, but
## the caps change with them, so they go through here.
func set_cutaway_opacity(v: float) -> void:
	cutaway.opacity = clampf(v, 0.0, 1.0)
	_invalidate_cut()


func set_cutaway_selectable(v: bool) -> void:
	cutaway.selectable = v


## True while the world is actually being sliced open for the camera.
func has_cutaway_geometry() -> bool:
	return _cap_mesh.get_surface_count() > 0


static func dir_index(v: Vector3i) -> int:
	if v.x > 0:
		return 0
	if v.x < 0:
		return 1
	if v.y > 0:
		return 2
	if v.y < 0:
		return 3
	if v.z > 0:
		return 4
	return 5


# =============================================================================
# the flood-filled cut volume
# =============================================================================

## Build the FILL mode's cut set.
##
## Flood the enclosed air pocket the player is standing in, then remove whatever
## occludes it. The result reveals one interconnected space — a tunnel, a
## gallery, a house — in its entirety, and touches nothing outside it. There is
## no cylinder mixed in: if you are standing in a room, the room is what you
## want to see, not a cone bored through the hill behind it.
##
## The flood only travels through *covered* air, which is what stops a doorway
## leaking it into the open sky. Standing outdoors there is no pocket at all,
## and the mode falls back to the drill so you are never left blind.
func _rebuild_fill() -> void:
	var cut := cutaway
	cut.clear_fill()
	var target := cut.target_position

	var axis := cut.plane_axis()
	var toward := cut.plane_toward()
	var start := Vector3i(floori(target.x), floori(target.y), floori(target.z))

	# --- 1. the pocket. A plain flood through covered air, which is exactly
	# "the airspace in which the player lies" and nothing else. The cover test is
	# what stops a doorway leaking the flood into the open sky.
	#
	# Visited cells are marked in a byte grid over the flood's own extent rather
	# than kept in a set. Three thousand cells with six neighbours each is
	# eighteen thousand membership tests, and hashing a `Vector3i` that many
	# times was most of what this mode cost — the grid answers the same question
	# with one multiply and one array read. It is allocated once and refilled.
	var half_x := FILL_EXTENT.x / 2
	var half_z := FILL_EXTENT.z / 2
	var span_x := half_x * 2 + 1
	var span_z := half_z * 2 + 1
	if _flood_seen.size() < span_x * WH * span_z:
		_flood_seen.resize(span_x * WH * span_z)
	_flood_seen.fill(0)

	var pocket: Array[Vector3i] = []
	var queue: Array[Vector3i] = [start]
	if is_covered(start.x, start.y, start.z) and not is_solid_at(start.x, start.y, start.z):
		# the start cell sits at the centre of the grid by construction
		_flood_seen[(half_x * WH + start.y) * span_z + half_z] = 1
	else:
		queue.clear()

	var lo := start
	var hi := start
	var head := 0
	while head < queue.size() and pocket.size() < MAX_FILL_CELLS:
		var c: Vector3i = queue[head]
		head += 1
		pocket.append(c)
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
		# NEIGHBOURS is a constant, not a literal written here: an array literal
		# inside a loop is rebuilt on every iteration, and this one ran three
		# thousand times a rebuild.
		for d: Vector3i in NEIGHBOURS:
			var n: Vector3i = c + d
			var ux := n.x - start.x + half_x
			var uz := n.z - start.z + half_z
			if ux < 0 or uz < 0 or ux >= span_x or uz >= span_z \
					or n.y < 0 or n.y >= WH:
				continue
			var mi := (ux * WH + n.y) * span_z + uz
			if _flood_seen[mi] != 0:
				continue
			_flood_seen[mi] = 1
			if is_solid_at(n.x, n.y, n.z) or not is_covered(n.x, n.y, n.z):
				continue
			queue.append(n)

	if pocket.is_empty():
		# Standing in the open. There is no room to reveal, so the mode does
		# nothing — it does not quietly turn into a drill.
		_upload_fill(1, 1)
		return

	# --- 2. the depth mask. One byte per column of the plane across the view
	# axis, holding how far toward the lens that column's pocket reaches. That
	# single number is the whole occlusion test: anything further toward the lens
	# in the same column is in the way, whatever shape the room is.
	var across_lo := lo.z if axis == 0 else lo.x
	var across_hi := hi.z if axis == 0 else hi.x
	cut.fill_axis = axis
	cut.fill_toward = toward
	cut.fill_slope = cut.view_slope()
	# depths count from the pocket's far side, so they start at 1 and stay small
	cut.fill_base = (lo.x if toward > 0 else hi.x) if axis == 0 \
		else (lo.z if toward > 0 else hi.z)

	# The sheared rows the pocket occupies. It has to be measured rather than
	# derived: the shear tilts the pocket, so its row span is not its height.
	var row_lo := 1 << 30
	var row_hi := -(1 << 30)
	for c: Vector3i in pocket:
		var along := c.x if axis == 0 else c.z
		var r := cut.fill_row(c.y, (along - cut.fill_base) * toward)
		row_lo = mini(row_lo, r)
		row_hi = maxi(row_hi, r)

	var size := Vector2i(across_hi - across_lo + 1, row_hi - row_lo + 1)
	cut.fill_origin = Vector3i(across_lo, row_lo, 0)
	cut.fill_size = size

	var depth := PackedByteArray()
	depth.resize(size.x * size.y)
	depth.fill(0)
	for c: Vector3i in pocket:
		var along := c.x if axis == 0 else c.z
		var k: int = (along - cut.fill_base) * toward
		var u := (c.z if axis == 0 else c.x) - across_lo
		var v := cut.fill_row(c.y, k) - row_lo
		var i := v * size.x + u
		if k + 1 > int(depth[i]):
			depth[i] = mini(k + 1, 255)
	cut.fill_depth = depth
	cut.fill_empty = false

	# --- 3. the hidden cells, for the cross-section.
	#
	# The predicate hides everything in front of the pocket out to infinity, but
	# a hidden cell can only *expose* a face if one of its neighbours is not
	# hidden — and a neighbour is hidden exactly when the run in its own column
	# has started. So each column only needs walking as far as the deepest of its
	# four neighbours: past that, everything around it is gone too and there is
	# nothing left to draw. In an open cavern that stops almost immediately and
	# only the silhouette's rim runs the full way to the lens.
	var reach := int(cut.camera_position.x if axis == 0 else cut.camera_position.z)
	var far := ((reach - cut.fill_base) * toward) + 1
	var hidden := PackedInt32Array()
	for v in size.y:
		for u in size.x:
			var i := v * size.x + u
			var d := int(depth[i])
			if d == 0:
				continue
			var limit := 0
			for n: int in [
					i - 1 if u > 0 else -1,
					i + 1 if u < size.x - 1 else -1,
					i - size.x if v > 0 else -1,
					i + size.x if v < size.y - 1 else -1]:
				# a column with no pocket is never hidden, so it can be exposed
				# for the whole run
				limit = far if n < 0 else maxi(limit, int(depth[n]) - 1)
				if limit >= far:
					break
			limit = mini(limit, far)
			if limit < d:
				continue
			var row := row_lo + v
			var across := across_lo + u
			for k in range(d, limit + 1):
				if hidden.size() >= MAX_MARKED_CELLS:
					break
				var along := cut.fill_base + k * toward
				# undo the shear to get back to a real cell
				var y := row + roundi(float(k) * cut.fill_slope)
				if y < 0 or y >= WH:
					continue
				hidden.append(_pack_cell(
					along if axis == 0 else across, y,
					across if axis == 0 else along))
	cut.fill_cells = hidden
	_upload_fill(size.x, size.y)


## World cell packed into one int. Y is 6 bits, x and z 13 each with a bias, so
## the whole streamed world fits and unpacking is two shifts.
func _pack_cell(x: int, y: int, z: int) -> int:
	return ((x + 4096) << 19) | ((z + 4096) << 6) | (y & 63)


func _unpack(i: int) -> Vector3i:
	return Vector3i(((i >> 19) & 8191) - 4096, i & 63, ((i >> 6) & 8191) - 4096)


## Is there anything solid above this cell? The flood fill only travels through
## covered air, which is what confines it to the tunnel or the room the player
## is actually in. Without it a doorway leaks the fill into the open sky and the
## whole landscape gets removed.
func is_covered(gx: int, gy: int, gz: int) -> bool:
	if gy < 0 or gy >= WH - 1:
		return false
	return (solid_mask_at(gx, gz) >> (gy + 1)) != 0




## Hand the packed mask to the terrain materials. One R8 image, no mipmaps, so
## the upload is a straight memcpy of the array we already built.
func _upload_fill(width: int, height: int) -> void:
	var cut := cutaway
	# The empty case is real: outdoors there is no pocket at all, and a 1x1
	# texture still needs its one byte or the image constructor refuses it.
	if cut.fill_depth.size() < width * height:
		cut.fill_depth.resize(width * height)
	if _fill_img == null or _fill_img.get_width() != width \
			or _fill_img.get_height() != height:
		_fill_img = Image.create_from_data(width, height, false, Image.FORMAT_R8,
			cut.fill_depth)
		_fill_tex = ImageTexture.create_from_image(_fill_img)
	else:
		_fill_img.set_data(width, height, false, Image.FORMAT_R8, cut.fill_depth)
		_fill_tex.update(_fill_img)
	for mat in [mat_opaque, mat_glass, mat_cross, mat_cap]:
		if mat == null:
			continue
		mat.set_shader_parameter("cut_fill_tex", _fill_tex)
		mat.set_shader_parameter("cut_fill_origin", Vector3(cut.fill_origin))
		mat.set_shader_parameter("cut_fill_size", Vector2(cut.fill_size))
		mat.set_shader_parameter("cut_fill_axis", float(cut.fill_axis))
		mat.set_shader_parameter("cut_fill_toward", float(cut.fill_toward))
		mat.set_shader_parameter("cut_fill_base", float(cut.fill_base))
		mat.set_shader_parameter("cut_fill_slope", cut.fill_slope)


## Walks the boundary of the cut volume and emits every face that the discard in
## voxel.gdshader just exposed. Without this you would be looking at the inside
## of the terrain shell, which has no geometry at all.
##
## The one `ArrayMesh` is kept and its surface replaced rather than a new mesh
## being built each time, so a rebuild does not churn a rendering-server RID.
func _rebuild_caps() -> void:
	var cut := cutaway
	cut.push_to_shader_globals()
	_cap_cells.clear()
	_cap_meta.clear()

	if cut.enabled:
		if cut.mode == Cutaway.Mode.PLANAR:
			if cut.occluded:
				_caps_from_plane()
		elif cut.mode == Cutaway.Mode.FILL:
			if not cut.fill_cells.is_empty():
				_caps_from_cells()
		else:
			_caps_from_cylinder()

	_cap_mesh.clear_surfaces()
	if _cap_cells.is_empty():
		return
	_cap_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _cap_arrays())
	_cap_mesh.surface_set_material(0, mat_cap)


## The cross-section of a half-space is one flat plane, so that is all this
## builds: a single slice of faces, one per solid cell on the last slice that is
## still drawn, every one of them turned toward the lens.
##
## That orientation is the whole point of the mode. Standing on the plane you
## are looking straight at the faces this emits — they are the wall of the
## Terraria-style side-on view, and if they are missing you are staring through
## the terrain shell into nothing. The face wanted is the one on the block's
## *camera-facing* side, `toward_camera`, because that is the side the removed
## neighbour used to be against.
##
## Nothing else can be exposed. Everything past the plane is gone and everything
## behind it is untouched, so the only newly bare surfaces in the entire world
## are on that one plane. The old box cut had five faces to walk and about 1,200
## cells to test; this walks one slice, reads it a whole column at a time out of
## the solid bitmask, and merges vertical runs of the same block into single
## quads — which underground collapses a 48-block column into one or two.
func _caps_from_plane() -> void:
	var cut := cutaway
	var cam := cut.camera_position
	var axis := cut.plane_axis()
	var plane := cut.plane_coord()
	var toward := cut.plane_toward()
	# the block's own face on the side the lens is, which is the side the cut
	# just emptied. The opposite face is buried and points away from the camera.
	var dir := dir_index(cut.toward_camera())
	var reach := cut.planar_cap_reach

	# The window is anchored to the player's chunk, not to the player, so that it
	# matches the signature that decides when this runs at all.
	var chunk_base := (cut.plane_across() >> 4) << 4
	var lo := chunk_base - reach
	var hi := chunk_base + CW - 1 + reach

	# The columns of a slice run consecutively across one axis, so they fall into
	# a handful of chunks rather than a hundred separate ones. Resolving the
	# chunk per chunk instead of per column is what this loop is shaped around:
	# `solid_mask_at` and `get_block` each hash a Vector2i every time they are
	# called, and at forty-eight cells a column that hashing was the rebuild.
	var plane_c := plane >> 4
	var far_c := (plane + toward) >> 4
	var plane_l := plane & 15
	var far_l := (plane + toward) & 15

	var across := lo
	while across <= hi:
		var ac := across >> 4
		# how far this chunk carries, so the two lookups amortise over 16 columns
		var run_end := mini(hi, (ac << 4) + CW - 1)
		var near: Chunk = _chunks.get(
			Vector2i(plane_c, ac) if axis == 0 else Vector2i(ac, plane_c))
		if near == null:
			across = run_end + 1
			continue
		var far: Chunk = _chunks.get(
			Vector2i(far_c, ac) if axis == 0 else Vector2i(ac, far_c))
		while across <= run_end:
			var al := across & 15
			var ci := (plane_l * CW + al) if axis == 0 else (al * CW + plane_l)
			# Only cells whose removed neighbour was itself opaque need a cap: if
			# it was air or glass the chunk mesher already drew this face, and a
			# second coplanar copy is z-fighting, not a cross-section.
			var fi := (far_l * CW + al) if axis == 0 else (al * CW + far_l)
			var mask: int = near.solid[ci] & (0 if far == null else far.solid[fi])
			if mask == 0:
				across += 1
				continue
			var gx := plane if axis == 0 else across
			var gz := across if axis == 0 else plane
			var base := ci * WH
			var types := near.types
			var y := 0
			while y < WH:
				if (mask >> y) & 1 == 0:
					y += 1
					continue
				# how far the run of the *same* block carries upward
				var id: int = types[base + y]
				var top := y + 1
				while top < WH and (mask >> top) & 1 != 0 \
						and types[base + top] == id:
					top += 1
				var ao := clampf(1.0 - Vector3(gx, y, gz).distance_to(cam) * 0.02,
					0.62, 1.0)
				_cap_cells.append(Vector3(gx, y, gz))
				_cap_meta.append(dir | (int(ao * 255.0) << 8) | (id << 16)
					| ((top - y) << 24))
				y = top
			across += 1


## The cylinder's cross-section, found by walking the drill instead of the box
## that contains it.
##
## The drill is a capsule perhaps three blocks across bored through thirty of
## world; the axis-aligned box around it is some eight thousand cells. Testing
## all eight thousand to find the three hundred that are actually cut was, by
## the profiler, the single largest recurring cost in the frame — and it ran
## again on every block the player moved, because a line from the lens to the
## player genuinely does depend on both.
##
## So this marches the segment instead, and only looks at cells near it. The
## marker grid is what makes that safe: consecutive samples overlap heavily, and
## a cell must be offered to `_cap_neighbours` exactly once or the cross-section
## grows duplicate coplanar faces. It is indexed arithmetically rather than
## hashed, which is the difference between this and a Dictionary of visited
## cells.
##
## `_caps_from_bounds` is kept as the reference implementation. It is the same
## predicate walked exhaustively, and the smoke test holds the two to producing
## identical geometry.
func _caps_from_cylinder() -> void:
	var cut := cutaway
	var cam := cut.camera_position
	var bounds := cut.get_int_bounds()
	# Exactly the window `_caps_from_bounds` walks, so the two are comparable.
	var ox := int(bounds.position.x)
	var oz := int(bounds.position.z)
	var y0 := maxi(int(bounds.position.y), 0)
	var y1 := mini(int(bounds.end.y), WH)
	var w := int(bounds.size.x)
	var h := y1 - y0
	var d := int(bounds.size.z)
	if w <= 0 or h <= 0 or d <= 0:
		return
	if _cap_seen.size() < w * h * d:
		_cap_seen.resize(w * h * d)
	_cap_seen.fill(0)

	var seg := cut.target_position - cam
	# One sample per block of the drill, so no point on the segment is more than
	# half a block from a sample.
	var steps := maxi(int(ceil(seg.length())), 1)
	# A cut cell's centre lies within the drill's radius of the segment, so
	# within that plus the half-block sampling error of some sample, so within
	# that many cells of that sample's own cell. Nothing outside this can be
	# cut, whatever the keep shell does — the shell only ever removes.
	#
	# Only the sample at the player's end needs the wider radius: that is the
	# spherical cap that keeps them visible pressed against a wall, and paying
	# for it along the whole shaft is three times the cells for nothing.
	var shaft := int(ceil(cut.radius + 0.5))
	var capped := int(ceil(cut.radius + cut.target_padding + 0.5))

	for s in steps + 1:
		var pt := cam + seg * (float(s) / float(steps))
		var px := floori(pt.x)
		var py := floori(pt.y)
		var pz := floori(pt.z)
		var reach := capped if s == steps else shaft
		for dx in range(-reach, reach + 1):
			var lx := px + dx - ox
			if lx < 0 or lx >= w:
				continue
			var x := ox + lx
			for dy in range(-reach, reach + 1):
				var ly := py + dy - y0
				if ly < 0 or ly >= h:
					continue
				var y := y0 + ly
				var row := (lx * h + ly) * d
				for dz in range(-reach, reach + 1):
					var lz := pz + dz - oz
					if lz < 0 or lz >= d:
						continue
					var mi := row + lz
					if _cap_seen[mi] != 0:
						continue
					_cap_seen[mi] = 1
					if cut.is_cut(x, y, oz + lz):
						_cap_neighbours(x, y, oz + lz, cam)


func _caps_from_bounds() -> void:
	var cut := cutaway
	var bounds := cut.get_int_bounds()
	var cam := cut.camera_position
	var y0 := maxi(int(bounds.position.y), 0)
	var y1 := mini(int(bounds.end.y), WH)
	for x in range(bounds.position.x, bounds.end.x):
		for z in range(bounds.position.z, bounds.end.z):
			# A cut cell only matters if it has a solid neighbour to expose, so a
			# column with nothing in it or beside it can be skipped whole. Open
			# sky is most of the volume in every mode.
			var occupied := solid_mask_at(x, z) | solid_mask_at(x + 1, z) \
				| solid_mask_at(x - 1, z) | solid_mask_at(x, z + 1) \
				| solid_mask_at(x, z - 1)
			if occupied == 0:
				continue
			for y in range(y0, y1):
				if (occupied >> y) & 1 == 0 and (occupied >> maxi(y - 1, 0)) & 1 == 0 \
						and (occupied >> mini(y + 1, WH - 1)) & 1 == 0:
					continue
				if not cut.is_cut(x, y, z):
					continue
				_cap_neighbours(x, y, z, cam)


## The fill already produced its cut set as a list, so walking that is strictly
## cheaper than rescanning the box that contains it.
func _caps_from_cells() -> void:
	var cut := cutaway
	var cam := cut.camera_position
	for i in cut.fill_cells.size():
		var c: Vector3i = _unpack(cut.fill_cells[i])
		if cut.is_protected(Vector3(c) + Vector3(0.5, 0.5, 0.5)):
			continue
		_cap_neighbours(c.x, c.y, c.z, cam)


## Emit the faces the discard just exposed around one cut cell. Each face named
## here belongs to the *surviving* neighbour and points back at the cell that
## was removed, which is the same convention `_caps_from_plane` follows.
func _cap_neighbours(x: int, y: int, z: int, cam: Vector3) -> void:
	var cut := cutaway
	var dist_to_cam := Vector3(x, y, z).distance_to(cam)

	var b_up := get_block(x, y + 1, z)
	if b_up != Blocks.AIR and Blocks.is_opaque(b_up) and not cut.is_cut(x, y + 1, z):
		_cap_face(Vector3i(x, y + 1, z), 3, dist_to_cam)  # -Y of the block above
	var b_dn := get_block(x, y - 1, z)
	if b_dn != Blocks.AIR and Blocks.is_opaque(b_dn) and not cut.is_cut(x, y - 1, z):
		_cap_face(Vector3i(x, y - 1, z), 2, dist_to_cam)
	var b_px := get_block(x + 1, y, z)
	if b_px != Blocks.AIR and Blocks.is_opaque(b_px) and not cut.is_cut(x + 1, y, z):
		_cap_face(Vector3i(x + 1, y, z), 1, dist_to_cam)
	var b_nx := get_block(x - 1, y, z)
	if b_nx != Blocks.AIR and Blocks.is_opaque(b_nx) and not cut.is_cut(x - 1, y, z):
		_cap_face(Vector3i(x - 1, y, z), 0, dist_to_cam)
	var b_pz := get_block(x, y, z + 1)
	if b_pz != Blocks.AIR and Blocks.is_opaque(b_pz) and not cut.is_cut(x, y, z + 1):
		_cap_face(Vector3i(x, y, z + 1), 5, dist_to_cam)
	var b_nz := get_block(x, y, z - 1)
	if b_nz != Blocks.AIR and Blocks.is_opaque(b_nz) and not cut.is_cut(x, y, z - 1):
		_cap_face(Vector3i(x, y, z - 1), 4, dist_to_cam)


func _cap_face(cell: Vector3i, dir: int, dist: float) -> void:
	var id := get_block(cell.x, cell.y, cell.z)
	if id == Blocks.AIR:
		return
	# darken with distance so a deep slice reads as depth, not as a flat wall
	var ao := clampf(1.0 - dist * 0.02, 0.62, 1.0)
	_cap_cells.append(Vector3(cell))
	_cap_meta.append(dir | (int(ao * 255.0) << 8) | (id << 16) | (1 << 24))


func _cap_arrays() -> Array:
	var n := _cap_meta.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * 4)
	norms.resize(n * 4)
	uvs.resize(n * 4)
	uv2s.resize(n * 4)
	cols.resize(n * 4)
	idx.resize(n * 6)

	var tw := 1.0 / float(TexGen.ATLAS_COLS)
	var th := 1.0 / float(TexGen.ATLAS_ROWS)
	var eps := 0.0008
	var vi := 0
	var ii := 0
	for k in n:
		var origin := _cap_cells[k]
		var packed: int = _cap_meta[k]
		var dir := packed & 255
		var ao := float((packed >> 8) & 255) / 255.0
		var id := (packed >> 16) & 255
		var run := maxi((packed >> 24) & 255, 1)
		var tile := Blocks.tile_of(id, dir)
		var nrm: Vector3 = FACE_NORMAL[dir]
		var vt: Array = FACE_VERTS[dir]
		var u0 := float(tile % TexGen.ATLAS_COLS) * tw + eps
		var v0 := float(tile / TexGen.ATLAS_COLS) * th + eps
		var emis := Blocks.emission(id)
		for j in 4:
			# a merged run is one quad `run` cells tall; the shader repeats the
			# block's atlas tile across it rather than stretching it
			var corner: Vector3 = vt[j]
			verts[vi + j] = origin + Vector3(corner.x,
				corner.y * float(run), corner.z)
			norms[vi + j] = nrm
			var uv: Vector2 = FACE_UV[j]
			uvs[vi + j] = Vector2(uv.x, uv.y * float(run))
			uv2s[vi + j] = Vector2(u0, v0)
			cols[vi + j] = Color(ao, emis, 1.0, 1.0)
		idx[ii] = vi; idx[ii + 1] = vi + 2; idx[ii + 2] = vi + 1
		idx[ii + 3] = vi; idx[ii + 4] = vi + 3; idx[ii + 5] = vi + 2
		vi += 4
		ii += 6

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


# =============================================================================
# raycasting
# =============================================================================

## Amanatides & Woo voxel traversal.
##
## Blocks removed by the cutaway are skipped, so you always target what you can
## actually see. Two exceptions: when cut blocks are drawn as ghosts they are
## visible, so they are targetable in the primary pass; and when the primary
## pass finds nothing at all, a second pass ignores the cut entirely, so a
## cutaway can never leave you unable to mine something that is really there.
func raycast(from: Vector3, dir: Vector3, max_dist: float, respect_cutaway := true) -> Dictionary:
	if respect_cutaway and not cutaway.selectable_in_primary():
		var seen := _raycast_pass(from, dir, max_dist, true)
		if seen.get("hit", false) or not cutaway.selectable:
			return seen
		return _raycast_pass(from, dir, max_dist, false)
	return _raycast_pass(from, dir, max_dist, false)


func _raycast_pass(from: Vector3, dir: Vector3, max_dist: float,
		respect_cutaway: bool) -> Dictionary:
	var result := {"hit": false}
	if dir.length_squared() < 0.0001:
		return result
	dir = dir.normalized()

	var x := int(floor(from.x))
	var y := int(floor(from.y))
	var z := int(floor(from.z))
	var step_x := 1 if dir.x > 0.0 else -1
	var step_y := 1 if dir.y > 0.0 else -1
	var step_z := 1 if dir.z > 0.0 else -1

	var inf := 1.0e30
	var tdx := inf if absf(dir.x) < 1e-8 else absf(1.0 / dir.x)
	var tdy := inf if absf(dir.y) < 1e-8 else absf(1.0 / dir.y)
	var tdz := inf if absf(dir.z) < 1e-8 else absf(1.0 / dir.z)

	var bx := float(x + (1 if step_x > 0 else 0))
	var by := float(y + (1 if step_y > 0 else 0))
	var bz := float(z + (1 if step_z > 0 else 0))
	var tmx := inf if tdx == inf else (bx - from.x) / dir.x
	var tmy := inf if tdy == inf else (by - from.y) / dir.y
	var tmz := inf if tdz == inf else (bz - from.z) / dir.z

	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		if y >= 0 and y < WH:
			var id := get_block(x, y, z)
			if id != Blocks.AIR:
				if not (respect_cutaway and cutaway.is_cut(x, y, z)):
					result["hit"] = true
					result["block"] = Vector3i(x, y, z)
					result["id"] = id
					result["normal"] = normal
					result["dist"] = t
					result["point"] = from + dir * t
					return result
		if tmx < tmy and tmx < tmz:
			x += step_x
			t = tmx
			tmx += tdx
			normal = Vector3i(-step_x, 0, 0)
		elif tmy < tmz:
			y += step_y
			t = tmy
			tmy += tdy
			normal = Vector3i(0, -step_y, 0)
		else:
			z += step_z
			t = tmz
			tmz += tdz
			normal = Vector3i(0, 0, -step_z)
		if y < -1 or y > WH + 4:
			break
	return result


## Axis-aligned box overlap test against the voxel field, used by every moving
## entity in the game.
func box_overlaps(centre: Vector3, half: Vector3) -> bool:
	var x0 := int(floor(centre.x - half.x))
	var x1 := int(floor(centre.x + half.x))
	var y0 := int(floor(centre.y - half.y))
	var y1 := int(floor(centre.y + half.y))
	var z0 := int(floor(centre.z - half.z))
	var z1 := int(floor(centre.z + half.z))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				if is_solid_at(x, y, z):
					return true
	return false
