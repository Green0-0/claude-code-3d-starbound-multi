## Autoloaded as `World`. The single source of truth for voxel data.
##
## Streaming is *slab-shaped*: because the camera only ever sees one plane, we
## keep a wide box along the lateral axis, the full planet height near the
## player, and only a few chunks of depth on either side of the play layer.
## Flipping the view therefore re-orients the streaming box too.
extends Node

const LOAD_LATERAL := 5    ## chunks left/right of the player
const LOAD_VERTICAL := 4   ## chunks above/below
const LOAD_DEPTH := 2      ## chunks in front of / behind the play layer
const UNLOAD_SLACK := 2    ## extra chunks kept before eviction
## Full terrain generation measured at ~68 ms mean / 200 ms worst per chunk
## (tools/perf_probe.tscn), so generating even one chunk overruns a 60 fps
## frame. Rather than pretend otherwise, generate at most one per frame and
## then sit out enough frames to amortise the cost back toward the soft budget.
const MAX_GEN_PER_FRAME := 1
const GEN_TIME_BUDGET_USEC := 8000

var planet_id: String = ""
var planet: Dictionary = {}          ## metadata from Universe / PlanetGen
var size_x: int = Const.PLANET_SIZE_DEFAULT
var size_z: int = Const.PLANET_SIZE_DEFAULT
var seed_value: int = 0
var ready_flag := false

var chunks: Dictionary = {}          ## Vector3i -> Chunk
var _gen_queue: Array[Vector3i] = []
var _gen_set: Dictionary = {}
var _center_chunk := Vector3i(-9999, -9999, -9999)
## Frames to skip before generating again, to amortise a heavy chunk.
var _gen_debt_frames := 0
var _rng := RandomNumberGenerator.new()

## Blocks changed this frame, batched so the renderer / lighting only wake once.
var _dirty_chunks: Dictionary = {}


func _ready() -> void:
	process_priority = -50


# =============================================================== world lifecycle
func create_world(p_planet_id: String, p_seed: int, meta: Dictionary = {}) -> void:
	unload_world()
	planet_id = p_planet_id
	seed_value = p_seed
	planet = meta
	size_x = int(meta.get("size_x", Const.PLANET_SIZE_DEFAULT))
	size_z = int(meta.get("size_z", Const.PLANET_SIZE_DEFAULT))
	_rng.seed = p_seed
	if PlanetGen.has_method(&"begin_planet"):
		PlanetGen.begin_planet(p_seed, meta)
	ready_flag = true
	Events.world_ready.emit(planet_id)


func unload_world() -> void:
	if not ready_flag and chunks.is_empty():
		return
	# Hand every live chunk to the save layer BEFORE dropping it. Without this
	# step, travelling to another planet silently discards every block the
	# player changed since the last eviction.
	for cp: Vector3i in chunks:
		SaveManager.store_chunk(planet_id, chunks[cp])
	for cp: Vector3i in chunks.keys():
		Events.chunk_unloaded.emit(cp)
	chunks.clear()
	_gen_queue.clear()
	_gen_set.clear()
	_dirty_chunks.clear()
	_center_chunk = Vector3i(-9999, -9999, -9999)
	ready_flag = false
	Events.world_unloaded.emit()


# ==================================================================== wrapping
## Planets wrap horizontally on both axes, so every access normalises first.
func wrap_x(x: int) -> int:
	return posmod(x, size_x)


func wrap_z(z: int) -> int:
	return posmod(z, size_z)


func normalize(p: Vector3i) -> Vector3i:
	return Vector3i(posmod(p.x, size_x), p.y, posmod(p.z, size_z))


func in_bounds_y(y: int) -> bool:
	return y >= 0 and y < Const.WORLD_HEIGHT


# ================================================================ block access
func get_block(p: Vector3i) -> int:
	if p.y < 0 or p.y >= Const.WORLD_HEIGHT:
		return Const.AIR
	var n := normalize(p)
	var c: Chunk = chunks.get(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))
	if c == null:
		return Const.AIR
	return c.blocks[((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)]


func get_block_xyz(x: int, y: int, z: int) -> int:
	return get_block(Vector3i(x, y, z))


## Returns true when the write actually happened.
func set_block(p: Vector3i, id: int, notify: bool = true) -> bool:
	if p.y < 0 or p.y >= Const.WORLD_HEIGHT:
		return false
	var n := normalize(p)
	var cp := Vector3i(n.x >> 4, n.y >> 4, n.z >> 4)
	var c: Chunk = chunks.get(cp)
	if c == null:
		return false
	var i := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	var old := c.blocks[i]
	if old == id:
		return false
	c.set_at(i, id)
	c.tile_data.erase(i)
	_dirty_chunks[cp] = true
	_mark_neighbour_chunks(n, cp)
	if notify:
		Events.block_changed.emit(n, old, id)
		var bt := Blocks.get_type(id)
		if bt.falls:
			Liquids.queue_falling(n)
		Lighting.on_block_changed(n, old, id)
		_notify_neighbours(n)
	return true


func is_solid(p: Vector3i) -> bool:
	return Blocks.is_solid(get_block(p))


func is_air(p: Vector3i) -> bool:
	return get_block(p) == Const.AIR


func is_opaque(p: Vector3i) -> bool:
	return Blocks.is_opaque(get_block(p))


func block_type_at(p: Vector3i) -> BlockType:
	return Blocks.get_type(get_block(p))


## Break a block, spawning its drops. `tier` gates whether drops are produced.
func break_block(p: Vector3i, tier: int = 99, spawn_drops: bool = true) -> Array:
	var id := get_block(p)
	if id == Const.AIR:
		return []
	var bt := Blocks.get_type(id)
	if not bt.breakable:
		return []
	var loot := bt.roll_drops(tier, _rng)
	var centre := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	# Announce the break while the voxel is still readable. Signals are
	# synchronous, so an FX listener that samples `World.get_block(p)` to tint
	# its debris sees the real block instead of the AIR that replaces it.
	Events.play_sound.emit(bt.break_sound, centre)
	Events.spawn_particles.emit(&"block_break", centre, 12)
	set_block(p, Const.AIR)
	if spawn_drops:
		for l: Dictionary in loot:
			Game.spawn_item_drop(Vector3(p) + Vector3(0.5, 0.5, 0.5), l["item"], l["count"])
	return loot


## Place a block if the target is replaceable and nothing is standing there.
func place_block(p: Vector3i, id: int) -> bool:
	var existing := get_block(p)
	if existing != Const.AIR and not Blocks.is_replaceable(existing):
		return false
	if Blocks.is_solid(id) and Game.entity_occupies(p):
		return false
	if not set_block(p, id):
		return false
	var bt := Blocks.get_type(id)
	Events.play_sound.emit(bt.place_sound, Vector3(p) + Vector3(0.5, 0.5, 0.5))
	return true


# =============================================================== chunk access
func get_chunk(cp: Vector3i) -> Chunk:
	return chunks.get(cp)


func has_chunk(cp: Vector3i) -> bool:
	return chunks.has(cp)


func chunk_at_block(p: Vector3i) -> Chunk:
	var n := normalize(p)
	return chunks.get(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))


func mark_dirty(cp: Vector3i) -> void:
	if chunks.has(cp):
		chunks[cp].dirty = true
		_dirty_chunks[cp] = true


func loaded_chunk_positions() -> Array:
	return chunks.keys()


func _mark_neighbour_chunks(n: Vector3i, cp: Vector3i) -> void:
	# A block on a chunk border changes the neighbour's visible faces.
	var lx := n.x & 15
	var ly := n.y & 15
	var lz := n.z & 15
	if lx == 0: _dirty_chunks[Vector3i(cp.x - 1, cp.y, cp.z)] = true
	if lx == 15: _dirty_chunks[Vector3i(cp.x + 1, cp.y, cp.z)] = true
	if ly == 0: _dirty_chunks[Vector3i(cp.x, cp.y - 1, cp.z)] = true
	if ly == 15: _dirty_chunks[Vector3i(cp.x, cp.y + 1, cp.z)] = true
	if lz == 0: _dirty_chunks[Vector3i(cp.x, cp.y, cp.z - 1)] = true
	if lz == 15: _dirty_chunks[Vector3i(cp.x, cp.y, cp.z + 1)] = true


func _notify_neighbours(p: Vector3i) -> void:
	for nrm: Vector3i in Const.FACE_NORMALS:
		var q := p + nrm
		var bt := Blocks.get_type(get_block(q))
		if bt.on_neighbour_changed.is_valid():
			bt.on_neighbour_changed.call(q, p)


# =================================================================== streaming
func _process(_delta: float) -> void:
	if not ready_flag:
		return
	_pump_generation()
	_flush_dirty()


## Called by the player every frame (and by the world on load) to re-centre the
## streaming box. Uses the *view-aligned* box described at the top of the file.
func update_streaming(center_world: Vector3) -> void:
	if not ready_flag:
		return
	var cc := Vector3i(
		floori(center_world.x) >> 4,
		clampi(floori(center_world.y) >> 4, 0, Const.WORLD_HEIGHT_CHUNKS - 1),
		floori(center_world.z) >> 4)
	if cc == _center_chunk:
		return
	_center_chunk = cc
	Events.player_moved_chunk.emit(cc)
	_request_box(cc)
	_evict_far(cc)


func _request_box(cc: Vector3i) -> void:
	var lateral_axis := 0 if View.depth_axis() == 2 else 2
	var wanted: Array[Vector3i] = []
	for dy in range(-LOAD_VERTICAL, LOAD_VERTICAL + 1):
		var cy := cc.y + dy
		if cy < 0 or cy >= Const.WORLD_HEIGHT_CHUNKS:
			continue
		for dl in range(-LOAD_LATERAL, LOAD_LATERAL + 1):
			for dd in range(-LOAD_DEPTH, LOAD_DEPTH + 1):
				var cx := cc.x
				var cz := cc.z
				if lateral_axis == 0:
					cx += dl
					cz += dd
				else:
					cz += dl
					cx += dd
				wanted.append(Vector3i(posmod(cx, size_x >> 4), cy, posmod(cz, size_z >> 4)))
	# Nearest-first so the plane the player is looking at appears immediately.
	wanted.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return (a - cc).length_squared() < (b - cc).length_squared())
	for cp: Vector3i in wanted:
		request_chunk(cp)


func request_chunk(cp: Vector3i) -> void:
	if chunks.has(cp) or _gen_set.has(cp):
		return
	if cp.y < 0 or cp.y >= Const.WORLD_HEIGHT_CHUNKS:
		return
	_gen_set[cp] = true
	_gen_queue.append(cp)


func _pump_generation() -> void:
	# Pay down the debt from an expensive chunk before starting another.
	if _gen_debt_frames > 0:
		_gen_debt_frames -= 1
		return
	var budget := MAX_GEN_PER_FRAME
	var started := Time.get_ticks_usec()
	while budget > 0 and not _gen_queue.is_empty():
		var cp: Vector3i = _gen_queue.pop_front()
		_gen_set.erase(cp)
		if chunks.has(cp):
			continue
		_build_chunk(cp)
		budget -= 1
		if Time.get_ticks_usec() - started >= GEN_TIME_BUDGET_USEC:
			break
	var spent := Time.get_ticks_usec() - started
	if spent > GEN_TIME_BUDGET_USEC:
		# Spread one heavy chunk over the next few frames instead of stacking
		# another on top of it. Capped so streaming still makes progress.
		_gen_debt_frames = mini(4, spent / GEN_TIME_BUDGET_USEC)


## Drain the whole queue synchronously. Only for spawn placement and teleports,
## where a frame hitch is preferable to dropping the player into the void.
func _pump_generation_all(limit: int = 4096) -> void:
	var n := 0
	while not _gen_queue.is_empty() and n < limit:
		var cp: Vector3i = _gen_queue.pop_front()
		_gen_set.erase(cp)
		if not chunks.has(cp):
			_build_chunk(cp)
		n += 1


func _build_chunk(cp: Vector3i) -> void:
	var c: Chunk = SaveManager.load_chunk(planet_id, cp)
	if c == null:
		c = Chunk.new(cp)
		if PlanetGen.has_method(&"generate_chunk"):
			PlanetGen.generate_chunk(c)
		c.generated = true
	chunks[cp] = c
	Lighting.on_chunk_loaded(cp)
	Events.chunk_loaded.emit(cp)
	_dirty_chunks[cp] = true
	# Newly loaded neighbours must re-mesh: their border faces may now be hidden.
	for nrm: Vector3i in Const.FACE_NORMALS:
		var np := cp + nrm
		if chunks.has(np):
			_dirty_chunks[np] = true


func _evict_far(cc: Vector3i) -> void:
	var lateral_axis := 0 if View.depth_axis() == 2 else 2
	var max_l := LOAD_LATERAL + UNLOAD_SLACK
	var max_d := LOAD_DEPTH + UNLOAD_SLACK
	var max_v := LOAD_VERTICAL + UNLOAD_SLACK
	var doomed: Array[Vector3i] = []
	var wx := size_x >> 4
	var wz := size_z >> 4
	for cp: Vector3i in chunks:
		if absi(cp.y - cc.y) > max_v:
			doomed.append(cp)
			continue
		var dx := wrapi(cp.x - cc.x, -(wx >> 1), wx >> 1)
		var dz := wrapi(cp.z - cc.z, -(wz >> 1), wz >> 1)
		var dl := dx if lateral_axis == 0 else dz
		var dd := dz if lateral_axis == 0 else dx
		if absi(dl) > max_l or absi(dd) > max_d:
			doomed.append(cp)
	for cp: Vector3i in doomed:
		var c: Chunk = chunks[cp]
		SaveManager.store_chunk(planet_id, c)
		chunks.erase(cp)
		Events.chunk_unloaded.emit(cp)


func _flush_dirty() -> void:
	if _dirty_chunks.is_empty():
		return
	for cp: Vector3i in _dirty_chunks:
		if chunks.has(cp):
			chunks[cp].dirty = true
			Events.chunk_dirty.emit(cp)
	_dirty_chunks.clear()


# ==================================================================== queries
## First solid block scanning downward from `y`; returns -1 if none.
func surface_y(x: int, z: int, from_y: int = Const.WORLD_HEIGHT - 1) -> int:
	for y in range(mini(from_y, Const.WORLD_HEIGHT - 1), -1, -1):
		if is_solid(Vector3i(x, y, z)):
			return y
	return -1


## Raycast through the voxel grid (Amanatides & Woo). Returns
## {hit: bool, pos: Vector3i, normal: Vector3i, distance: float}.
func raycast(from: Vector3, dir: Vector3, max_dist: float, want_liquid: bool = false) -> Dictionary:
	var miss := {"hit": false, "pos": Vector3i.ZERO, "normal": Vector3i.ZERO, "distance": max_dist}
	if dir.length_squared() < 0.000001:
		return miss
	dir = dir.normalized()
	var p := Const.floor_v(from)
	var step := Vector3i(signi(int(sign(dir.x))), signi(int(sign(dir.y))), signi(int(sign(dir.z))))
	var t_delta := Vector3(
		INF if absf(dir.x) < 1e-8 else absf(1.0 / dir.x),
		INF if absf(dir.y) < 1e-8 else absf(1.0 / dir.y),
		INF if absf(dir.z) < 1e-8 else absf(1.0 / dir.z))
	var t_max := Vector3()
	for a in 3:
		if absf(dir[a]) < 1e-8:
			t_max[a] = INF
		else:
			var boundary: float = float(p[a] + (1 if step[a] > 0 else 0))
			t_max[a] = (boundary - from[a]) / dir[a]
	var t := 0.0
	var normal := Vector3i.ZERO
	while t <= max_dist:
		var id := get_block(p)
		if id != Const.AIR and (Blocks.is_solid(id) or (want_liquid and Blocks.is_liquid(id))):
			return {"hit": true, "pos": normalize(p), "normal": normal, "distance": t}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			p.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			p.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			p.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
		if p.y < -1 or p.y > Const.WORLD_HEIGHT:
			break
	return miss


## Sphere of destruction used by explosions.
func explode(center: Vector3, radius: float, power: float = 4.0) -> void:
	var r := ceili(radius)
	var c := Const.floor_v(center)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var off := Vector3(dx, dy, dz)
				var d := off.length()
				if d > radius:
					continue
				var p := c + Vector3i(dx, dy, dz)
				var bt := Blocks.get_type(get_block(p))
				if bt.id == Const.AIR or not bt.breakable:
					continue
				if bt.blast_resistance > power * (1.0 - d / radius) * 4.0:
					continue
				break_block(p, 99, _rng.randf() < 0.25)
	Events.spawn_particles.emit(&"explosion", center, 40)
	Events.play_sound.emit(&"explosion", center)
	Events.screen_shake.emit(radius * 0.8, 0.4)
