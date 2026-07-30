## Attached to the `WorldRenderer` node in `main.tscn`. Owns one set of
## `MeshInstance3D`s per loaded chunk and keeps them in step with the voxel data.
##
## Scheduling
## ----------
## Dirty chunks go into a priority queue ordered by (a) whether the chunk is
## inside the visible slab and (b) distance to the player. Each frame we spend a
## small, fixed budget re-meshing from the front of that queue, so a cave-in or
## a wave of newly streamed chunks costs frame *latency* rather than a hitch.
## Chunks outside the slab are still rebuilt, just last — the player cannot see
## them until they flip or shift, and both of those re-prioritise the queue.
##
## Meshing itself runs on `WorkerThreadPool` via `render/mesh_worker.gd`; the
## snapshot half stays on the main thread and is the only part that reads
## `World`. If threading is unavailable the same code paths run inline.
##
## Wrapping
## --------
## Planets wrap on X and Z, so `World` hands out wrapped chunk coordinates. A
## chunk is positioned at whichever wrapped representative is nearest the player,
## which keeps the world continuous when they walk across the seam.
extends Node3D

## Wall-clock budget for meshing work per frame, in microseconds.
const BUDGET_USEC := 2200
## Never start more than this many chunks in one frame, however cheap they look.
const MAX_STARTS_PER_FRAME := 4
## Never upload more than this many finished meshes in one frame.
const MAX_UPLOADS_PER_FRAME := 4
## Re-sorting 500 queued chunks every frame is pointless; this throttles it.
const RESORT_INTERVAL := 0.2
## Chunks whose centre is further outside the slab than this are deprioritised.
const SLAB_MARGIN := 16.0

var _chunks: Dictionary = {}            ## Vector3i -> Dictionary of nodes
## True when a real lighting module is present (it flips `Chunk.lit`). With the
## stub, nothing ever becomes lit, so gating on it would render an empty world.
var _lighting_active := false
## cpos -> msec when we first deferred it, so a chunk whose light never arrives
## still gets drawn instead of staying invisible forever.
var _lit_wait: Dictionary = {}
const LIT_WAIT_MS := 6000

var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _worker := MeshWorker.new()

var _player_chunk := Vector3i.ZERO
var _resort_timer := 0.0
var _needs_sort := true
var _world_chunks_x := 32
var _world_chunks_z := 32

## Rolling counters other modules (and the debug HUD) can read.
var stats := {"meshed": 0, "queued": 0, "visible": 0, "tris": 0}


func _ready() -> void:
	_lighting_active = Lighting.has_method(&"is_lit")
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.chunk_dirty.connect(_on_chunk_dirty)
	Events.world_unloaded.connect(_on_world_unloaded)
	Events.world_ready.connect(_on_world_ready)
	Events.player_moved_chunk.connect(_on_player_moved_chunk)
	Events.view_flip_finished.connect(_on_view_changed)
	Events.layer_changed.connect(_on_layer_changed)
	Atlas.ensure_built()
	# Chunks that loaded before this node was wired up.
	for cpos: Vector3i in World.loaded_chunk_positions():
		_enqueue(cpos)


func _exit_tree() -> void:
	_worker.shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_worker.shutdown()


# ================================================================ event wiring
func _on_world_ready(_planet_id: String) -> void:
	_world_chunks_x = maxi(1, World.size_x >> 4)
	_world_chunks_z = maxi(1, World.size_z >> 4)
	_needs_sort = true


func _on_chunk_loaded(cpos: Vector3i) -> void:
	_enqueue(cpos)


func _on_chunk_unloaded(cpos: Vector3i) -> void:
	_release(cpos)
	_queued.erase(cpos)


func _on_chunk_dirty(cpos: Vector3i) -> void:
	_enqueue(cpos)


func _on_world_unloaded() -> void:
	for cpos: Vector3i in _chunks.keys():
		_release(cpos)
	_chunks.clear()
	_queue.clear()
	_queued.clear()


func _on_player_moved_chunk(cpos: Vector3i) -> void:
	_player_chunk = cpos
	_needs_sort = true
	_reposition_all()


func _on_view_changed(_view: int) -> void:
	_needs_sort = true


func _on_layer_changed(_layer: int, _view: int) -> void:
	_needs_sort = true


func _enqueue(cpos: Vector3i) -> void:
	if _queued.has(cpos):
		return
	_queued[cpos] = true
	_queue.append(cpos)
	_needs_sort = true


# ======================================================================= frame
func _process(delta: float) -> void:
	_push_shader_params()
	if not World.ready_flag:
		return

	for cpos: Vector3i in _worker.watchdog():
		_enqueue(cpos)
	_collect_results()

	_resort_timer -= delta
	if _needs_sort and _resort_timer <= 0.0 and _queue.size() > 1:
		_sort_queue()
		_resort_timer = RESORT_INTERVAL
		_needs_sort = false

	_pump(delta)
	stats["queued"] = _queue.size()
	if Game.debug_overlay:
		_draw_debug()


## The slab uniforms have to be current *before* anything draws, every frame:
## they encode where the player is standing, which is what decides whether a
## voxel is discarded, tinted, or drawn at full brightness.
func _push_shader_params() -> void:
	var fog := Color(0.09, 0.11, 0.16)
	if Lighting.has_method(&"sky_color"):
		fog = Lighting.sky_color().darkened(0.55)
	Atlas.set_view_params(View.shader_params(), fog)


func _collect_results() -> void:
	var done := _worker.drain(MAX_UPLOADS_PER_FRAME)
	for built: Dictionary in done:
		_apply(built)


func _pump(_delta: float) -> void:
	if _queue.is_empty():
		return
	var start := Time.get_ticks_usec()
	var started := 0
	# Chunks waiting on their light. Re-queued *after* the loop so this frame
	# cannot pop them again and spin.
	var deferred: Array[Vector3i] = []
	while started < MAX_STARTS_PER_FRAME and not _queue.is_empty():
		if Time.get_ticks_usec() - start > BUDGET_USEC:
			break
		var cpos: Vector3i = _queue.pop_front()
		_queued.erase(cpos)
		var chunk: Chunk = World.get_chunk(cpos)
		if chunk == null:
			continue
		# Do not bake a mesh before its light has been flooded. An unlit chunk
		# falls back to full brightness, which renders underground stone as a
		# near-white slab — the single worst readability artefact in the game.
		# `Lighting` emits `chunk_dirty` when the flood lands, which re-queues us.
		if not chunk.lit and _lighting_active:
			var now := Time.get_ticks_msec()
			var since: int = int(_lit_wait.get(cpos, now))
			if not _lit_wait.has(cpos):
				_lit_wait[cpos] = now
			if now - since < LIT_WAIT_MS:
				deferred.append(cpos)
				continue
			# Light never arrived; draw it rather than leave a hole.
		_lit_wait.erase(cpos)
		chunk.dirty = false
		# All-air chunks never get geometry; dropping them here is what keeps
		# the sky above a planet free.
		if chunk.empty:
			_release_meshes(cpos)
			continue
		if _worker.in_flight(cpos):
			# Already being meshed with older data — redo it once that lands.
			_enqueue(cpos)
			break
		var snap := ChunkMesher.snapshot(cpos)
		if snap.is_empty():
			_release_meshes(cpos)
			continue
		started += 1
		if _worker.submit(snap):
			continue
		# Synchronous fallback: threading is off, or the queue is saturated.
		_apply(ChunkMesher.build_arrays(snap))

	for cpos: Vector3i in deferred:
		_enqueue(cpos)


func _apply(built: Dictionary) -> void:
	var cpos: Vector3i = built.get("cpos", Vector3i.ZERO)
	if not World.has_chunk(cpos):
		return
	var holder := _holder(cpos)
	var tris := 0
	for key: String in ["opaque", "transparent", "liquid"]:
		var bucket: Array = built[key]
		var indices: PackedInt32Array = bucket[ChunkMesher.B_IDX]
		tris += indices.size() / 3
		_set_surface(holder, key, ChunkMesher.arrays_to_mesh(bucket))
	holder["tris"] = tris
	stats["meshed"] += 1


# ================================================================ mesh objects
func _holder(cpos: Vector3i) -> Dictionary:
	var holder: Dictionary = _chunks.get(cpos, {})
	if holder.is_empty():
		var root := Node3D.new()
		root.name = "Chunk_%d_%d_%d" % [cpos.x, cpos.y, cpos.z]
		root.position = _render_origin(cpos)
		add_child(root)
		holder = {"root": root, "opaque": null, "transparent": null, "liquid": null, "tris": 0}
		_chunks[cpos] = holder
	return holder


func _set_surface(holder: Dictionary, key: String, mesh: ArrayMesh) -> void:
	var mi: MeshInstance3D = holder[key]
	if mesh == null:
		if mi != null:
			mi.queue_free()
			holder[key] = null
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = key
		mi.layers = Const.RL_WORLD
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		match key:
			"opaque":
				mi.material_override = Atlas.get_material(false)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			"transparent":
				mi.material_override = Atlas.get_material(true)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				mi.material_override = Atlas.get_liquid_material()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(holder["root"] as Node3D).add_child(mi)
		holder[key] = mi
	mi.mesh = mesh


func _release(cpos: Vector3i) -> void:
	var holder: Dictionary = _chunks.get(cpos, {})
	if holder.is_empty():
		return
	var root: Node3D = holder["root"]
	if is_instance_valid(root):
		root.queue_free()
	_chunks.erase(cpos)


func _release_meshes(cpos: Vector3i) -> void:
	var holder: Dictionary = _chunks.get(cpos, {})
	if holder.is_empty():
		return
	for key: String in ["opaque", "transparent", "liquid"]:
		var mi: MeshInstance3D = holder[key]
		if mi != null:
			mi.queue_free()
			holder[key] = null
	holder["tris"] = 0


# ==================================================================== wrapping
## Nearest wrapped world position for a chunk, so the seam between x = size-1 and
## x = 0 is invisible while the player stands on it.
func _render_origin(cpos: Vector3i) -> Vector3:
	var half_x := _world_chunks_x >> 1
	var half_z := _world_chunks_z >> 1
	var cx := _player_chunk.x + wrapi(cpos.x - _player_chunk.x, -half_x, half_x)
	var cz := _player_chunk.z + wrapi(cpos.z - _player_chunk.z, -half_z, half_z)
	return Vector3(cx * Const.CHUNK_SIZE, cpos.y * Const.CHUNK_SIZE, cz * Const.CHUNK_SIZE)


func _reposition_all() -> void:
	for cpos: Vector3i in _chunks:
		var holder: Dictionary = _chunks[cpos]
		var root: Node3D = holder["root"]
		if is_instance_valid(root):
			root.position = _render_origin(cpos)


# =================================================================== priority
func _sort_queue() -> void:
	var layer := float(View.layer)
	var sign_d := float(View.depth_sign())
	var depth_is_x := View.depth_axis() == 0
	var behind := float(Const.SLAB_BEHIND)
	var pc := _player_chunk
	var scores: Dictionary = {}
	for cpos: Vector3i in _queue:
		var origin := _render_origin(cpos)
		var centre_depth: float = (origin.x if depth_is_x else origin.z) + 8.0
		var offset := (centre_depth - layer) * sign_d
		# Anything the player can actually see right now goes first.
		var out_of_slab: bool = offset < -SLAB_MARGIN or offset > behind + SLAB_MARGIN
		var d := Vector3(cpos - pc).length()
		scores[cpos] = d + (512.0 if out_of_slab else 0.0)
	_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return float(scores[a]) < float(scores[b]))


# ====================================================================== debug
func _draw_debug() -> void:
	var visible_count := 0
	var tris := 0
	for cpos: Vector3i in _chunks:
		var holder: Dictionary = _chunks[cpos]
		tris += int(holder["tris"])
		if int(holder["tris"]) > 0:
			visible_count += 1
		if absi(cpos.x - _player_chunk.x) <= 1 and absi(cpos.y - _player_chunk.y) <= 1 \
				and absi(cpos.z - _player_chunk.z) <= 1:
			var root: Node3D = holder["root"]
			if is_instance_valid(root):
				DebugDraw.box(AABB(root.position, Vector3.ONE * float(Const.CHUNK_SIZE)),
					DebugDraw.COL_CHUNK)
	stats["visible"] = visible_count
	stats["tris"] = tris


# ================================================================ public hooks
## Force every loaded chunk to re-mesh. Use after changing a global render
## setting (AO on/off, atlas rebuild).
func rebuild_all() -> void:
	Atlas.ensure_built()
	for cpos: Vector3i in World.loaded_chunk_positions():
		_enqueue(cpos)


## Number of chunks with live geometry.
func chunk_count() -> int:
	return _chunks.size()
