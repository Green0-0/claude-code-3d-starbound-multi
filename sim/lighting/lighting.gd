## Autoloaded as `Lighting`. Owner of every light byte in the world and of the
## sky the player stands under.
##
## ---------------------------------------------------------------------------
## WHO DARKENS WHAT — read this before touching vertex colours in `render/`.
## ---------------------------------------------------------------------------
## There are exactly two multiplicative terms and they have separate owners:
##
##   1. **Per-voxel illumination — owned here.** `factor_at(pos)` returns 0..1
##      for a *world-space voxel*: how much light physically reaches it.
##      Skylight (scaled by the time of day) maxed with block light, run
##      through a perceptual curve and floored at the planet's ambient. This is
##      the term the mesher bakes into vertex colours. It knows nothing about
##      the camera, the view plane or the player's layer.
##
##   2. **Depth cueing — owned by `render/`.** The slab shader darkens,
##      desaturates and eventually dissolves voxels by how many layers they sit
##      behind the play layer, using `View.shader_params()`.
##
## They multiply. **Neither side may apply the other's term.** `factor_at()`
## must never look at `View.layer`, and the shader must never re-apply a light
## level. If a chunk looks doubly dark, exactly one of those two rules was
## broken. `depth_tint(layer_offset)` below is published as the *reference
## curve* for term 2 so both agents agree on the falloff, and the global shader
## uniforms `lit_*` (registered in `day_night.gd`, `LitDayNight._register_globals`)
## carry the sky/ambient state the shader needs to tint distant layers toward
## the sky/fog colour rather than toward black — that is what makes far layers
## read as *far* instead of *unlit*.
##
## `light_map()` is the fast path for a mesher that already walks
## `Chunk.light` itself: it hands over the exact byte -> factor table, so the
## renderer gets the planet curve, weather dimming and ambient floor for free
## instead of recomputing `max(block, sky * Game.daylight) / 15`.
##
## ---------------------------------------------------------------------------
## Budget
## ---------------------------------------------------------------------------
## All voxel work is queued and pumped from `_process` inside a microsecond
## budget (`budget_usec`, default 2200µs ≈ 13% of a 60fps frame). Chunks are
## lit nearest-to-the-player first and top-down within a column. A chunk is
## meshable only once `is_lit(cpos)` is true.
extends Node

# ------------------------------------------------------------------- tuning
## Soft per-frame time budget for all voxel light work, in microseconds.
var budget_usec := 2200
## Hard ceiling on BFS node pops per frame, so a pathological slice cannot run
## away between clock reads.
var max_ops_per_frame := 24000
## How many chunks may be seeded from scratch in a single frame.
var max_seeds_per_frame := 3
## Longest a re-mesh request is held back waiting for the flood to settle.
var dirty_max_hold := 0.35
## Perceptual curve: light level 0..15 -> displayed factor. Minecraft-ish
## exponential, softened toward linear so mid-levels stay readable.
var curve_base := 0.855
var curve_linear_mix := 0.30
## Lowest factor any lit surface can reach; planets override it (a midnight
## planet raises it so caves are not literally invisible).
var ambient_floor := 0.055
## Set false to freeze all propagation (debug / profiling).
var enabled := true

# ---------------------------------------------------------------------- state
var flood := LitFlood.new()
var day_night: LitDayNight = null
var planet: LitPlanet = null
var dynamic: LitDynamic = null
var weather: LitWeather = null
var debug: LitDebug = null

## cpos -> true, chunks awaiting their first (or a forced) flood.
var _seed_set: Dictionary = {}
var _seed_queue: Array[Vector3i] = []
var _seed_sorted := false
var _relight: Dictionary = {}     ## cpos -> true, chunks that must be re-seeded
var _center := Vector3i.ZERO
## Batched re-mesh requests; see `_emit_pending`.
var _dirty_pending: Dictionary = {}
var _dirty_age := 0.0

## 256-entry lookup tables from a packed light byte to the final value.
## Rebuilt only when the daylight factor or the ambient floor actually move.
var _factor_lut := PackedFloat32Array()
var _level_lut := PackedByteArray()
var _lut_daylight := -1.0
var _lut_floor := -1.0
var _daylight_eff := 1.0

## One-entry chunk cache for `factor_at` / `level_at`. Invalidated whenever a
## light byte anywhere changes, and on chunk unload.
var _fc_x := 0x7FFFFFFF
var _fc_y := 0
var _fc_z := 0
var _fc_ok := false
var _fc_light := PackedByteArray()
var _cw_x := 32
var _cw_z := 32

## Value returned for voxels in chunks that are not loaded. Full sky rather
## than black: an unloaded neighbour must not paint a dark seam on a chunk edge.
var _open_factor := 1.0

var stats_chunks_lit := 0
var stats_ops := 0
var stats_seeds := 0


# ==================================================================== lifecycle
func _ready() -> void:
	# After World (-50) so chunks created this frame are already in the map,
	# before Game (100) — a one-frame-old `daylight` is imperceptible.
	process_priority = -40
	_factor_lut.resize(256)
	_level_lut.resize(256)
	_build_luts(1.0)

	planet = LitPlanet.new()
	planet.name = "PlanetLighting"
	add_child(planet)
	weather = LitWeather.new()
	weather.name = "WeatherLighting"
	add_child(weather)
	day_night = LitDayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	dynamic = LitDynamic.new()
	dynamic.name = "DynamicLights"
	add_child(dynamic)
	debug = LitDebug.new()
	debug.name = "LightDebug"
	add_child(debug)

	Events.world_ready.connect(_on_world_ready)
	Events.world_unloaded.connect(_on_world_unloaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.player_moved_chunk.connect(_on_player_moved_chunk)


func _on_world_ready(_planet_id: String) -> void:
	_cw_x = maxi(1, World.size_x >> 4)
	_cw_z = maxi(1, World.size_z >> 4)
	flood.set_world(World.size_x, World.size_z, World.chunks)
	flood.rebuild_luts()
	_seed_set.clear()
	_seed_queue.clear()
	_relight.clear()
	_dirty_pending.clear()
	_invalidate_cache()
	stats_chunks_lit = 0


func _on_world_unloaded() -> void:
	flood.clear_queues()
	flood.touched.clear()
	flood.roof.clear()
	_seed_set.clear()
	_seed_queue.clear()
	_relight.clear()
	_dirty_pending.clear()
	_invalidate_cache()


func _on_chunk_unloaded(cpos: Vector3i) -> void:
	_seed_set.erase(cpos)
	_relight.erase(cpos)
	_dirty_pending.erase(cpos)
	flood.forget_chunk(cpos)
	_invalidate_cache()


func _on_player_moved_chunk(cpos: Vector3i) -> void:
	_center = cpos
	_seed_sorted = false


# =============================================================== world callbacks
## `World` calls this the moment a chunk enters the map, before `chunk_loaded`.
func on_chunk_loaded(cpos: Vector3i) -> void:
	var c: Chunk = World.chunks.get(cpos)
	if c == null:
		return
	c.lit = false
	if not _seed_set.has(cpos):
		_seed_set[cpos] = true
		_seed_queue.append(cpos)
		_seed_sorted = false
	# Note: the already-lit neighbours are deliberately *not* re-flooded here.
	# Sideways and upward light is handled by this chunk's own border seeds
	# (light in) and frontier seeds (light out), and the only case a neighbour
	# can be genuinely stale is the chunk below getting a new ceiling, which
	# `LitFlood.roof_changed()` detects exactly, once, after seeding.


## `World.set_block` calls this for every block edit. Runs the classic
## two-queue removal-then-refill so a torch can be mined without rebuilding
## the chunk.
func on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if not enabled or old_id == new_id:
		return
	if flood.luts_stale():
		flood.rebuild_luts()
	var n := World.normalize(pos)
	var c: Chunk = World.chunk_at_block(n)
	if c == null:
		return
	if not c.lit:
		return  # it has not had its first flood yet; that will pick this up
	flood.end_slice()
	var i := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	var byte: int = c.light[i]
	var old_sky: int = byte >> 4
	var old_blk: int = byte & 15
	var old_op: int = flood.opacity[old_id] if old_id < flood.opacity.size() else 0
	var new_op: int = flood.opacity[new_id] if new_id < flood.opacity.size() else 0
	var new_emit: int = flood.emission[new_id] if new_id < flood.emission.size() else 0

	var x := n.x
	var y := n.y
	var z := n.z

	# ---- block light -------------------------------------------------------
	# Anything that changes opacity or removes an emitter invalidates the light
	# standing in this voxel; erase it and let the removal wave find the edge.
	if old_blk > 0:
		c.set_block_light(i, 0)
		flood.queue_block_remove(x, y, z, old_blk)
	if new_emit > 0:
		c.set_block_light(i, new_emit)
		flood.queue_block_add(x, y, z, new_emit)

	# ---- sky light ---------------------------------------------------------
	if new_op >= LitFlood.OPAQUE_COST:
		if old_sky > 0:
			c.set_sky_light(i, 0)
			flood.queue_sky_remove(x, y, z, old_sky)
	elif new_op > old_op and old_sky > 0:
		# Still translucent but dimmer: erase and refill from the neighbours.
		c.set_sky_light(i, 0)
		flood.queue_sky_remove(x, y, z, old_sky)

	# The voxel got easier to pass through: pull light in from all six sides.
	if new_op < old_op or new_op < LitFlood.OPAQUE_COST:
		_seed_from_neighbours(x, y, z)

	World.mark_dirty(Const.chunk_of(n))
	_invalidate_cache()


func _seed_from_neighbours(x: int, y: int, z: int) -> void:
	for d in 6:
		var ny: int = y + int(LitFlood.DY[d])
		if ny < 0 or ny >= Const.WORLD_HEIGHT:
			continue
		var nx: int = World.wrap_x(x + int(LitFlood.DX[d]))
		var nz: int = World.wrap_z(z + int(LitFlood.DZ[d]))
		var c: Chunk = World.chunks.get(Vector3i(nx >> 4, ny >> 4, nz >> 4))
		if c == null:
			continue
		var i := ((ny & 15) << 8) | ((nz & 15) << 4) | (nx & 15)
		var byte: int = c.light[i]
		flood.queue_sky_add(nx, ny, nz, byte >> 4)
		flood.queue_block_add(nx, ny, nz, byte & 15)


# ======================================================================= pump
func _process(delta: float) -> void:
	_refresh_daylight()
	if not enabled or not World.ready_flag:
		return
	if flood.luts_stale():
		flood.rebuild_luts()
	_pump(delta)


func _pump(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var deadline := t0 + budget_usec
	var ops := 0

	# 1. Re-seeds queued by cascades take priority: they fix visible errors.
	var relit := 0
	while relit < max_seeds_per_frame and not _relight.is_empty() and Time.get_ticks_usec() < deadline:
		var cp: Vector3i = _relight.keys()[0]
		_relight.erase(cp)
		var c: Chunk = World.chunks.get(cp)
		if c == null:
			continue
		ops += flood.seed_chunk(c, true)
		relit += 1
		stats_seeds += 1
		# Cascade: the column below this one may now be lit from a wrong roof.
		if flood.roof_changed(cp):
			_queue_relight(Vector3i(cp.x, cp.y - 1, cp.z))

	# 2. First-time floods, nearest to the player and top-down.
	var seeded := 0
	while seeded < max_seeds_per_frame and not _seed_queue.is_empty() \
			and Time.get_ticks_usec() < deadline and ops < max_ops_per_frame:
		if not _seed_sorted:
			_sort_seed_queue()
		var cp: Vector3i = _seed_queue.pop_front()
		_seed_set.erase(cp)
		var c: Chunk = World.chunks.get(cp)
		if c == null:
			continue
		ops += flood.seed_chunk(c, c.lit)
		c.lit = true
		stats_chunks_lit += 1
		seeded += 1
		# A chunk lit above a chunk that was already lit may invalidate it.
		if flood.roof_changed(cp):
			_queue_relight(Vector3i(cp.x, cp.y - 1, cp.z))

	# 3. Spread. Budgeted node pops, removals first.
	while ops < max_ops_per_frame and flood.pending() > 0 and Time.get_ticks_usec() < deadline:
		var spent := flood.run_slice(mini(2048, max_ops_per_frame - ops))
		if spent <= 0:
			break
		ops += spent

	flood.end_slice()
	stats_ops = ops
	if not flood.touched.is_empty():
		_flush_touched()
	_emit_pending(_delta)


## Collect every chunk whose light bytes moved. The `chunk_dirty` signal is
## *batched*: a BFS sweeping across twenty chunks would otherwise ask the
## renderer to rebuild each of them once per frame while the wave passes. We
## hold them until the queues drain (or `dirty_max_hold` seconds pass), so each
## chunk is re-meshed once with its final light.
func _flush_touched() -> void:
	# Drop the read cache *first*: `chunk_dirty` can re-enter through the
	# mesher, which reads `factor_at` on the very chunks we just rewrote.
	_invalidate_cache()
	for cp: Vector3i in flood.touched:
		var c: Chunk = World.chunks.get(cp)
		if c == null:
			continue
		c.dirty = true
		if c.lit:
			_dirty_pending[cp] = true
	flood.touched.clear()


func _emit_pending(delta: float) -> void:
	if _dirty_pending.is_empty():
		_dirty_age = 0.0
		return
	_dirty_age += delta
	if flood.pending() > 0 and _dirty_age < dirty_max_hold:
		return
	for cp: Vector3i in _dirty_pending:
		if World.chunks.has(cp):
			Events.chunk_dirty.emit(cp)
	_dirty_pending.clear()
	_dirty_age = 0.0


func _sort_seed_queue() -> void:
	var cc := _center
	_seed_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var da := (a.x - cc.x) * (a.x - cc.x) + (a.z - cc.z) * (a.z - cc.z) \
			+ (a.y - cc.y) * (a.y - cc.y)
		var db := (b.x - cc.x) * (b.x - cc.x) + (b.z - cc.z) * (b.z - cc.z) \
			+ (b.y - cc.y) * (b.y - cc.y)
		if da != db:
			return da < db
		return a.y > b.y)
	_seed_sorted = true


func _queue_relight(cpos: Vector3i) -> void:
	if World.chunks.has(cpos):
		_relight[cpos] = true


func _wrap_cpos(cp: Vector3i) -> Vector3i:
	return Vector3i(posmod(cp.x, _cw_x), cp.y, posmod(cp.z, _cw_z))


# ================================================================= public API
## True once a chunk's initial flood has finished. **The renderer must not
## build a mesh for a chunk until this returns true** — meshing earlier bakes
## an all-black vertex colour that nothing will come back to fix except the
## `chunk_dirty` this module emits when lighting lands.
func is_lit(cpos: Vector3i) -> bool:
	var c: Chunk = World.chunks.get(cpos)
	return c != null and c.lit


## Light a chunk right now, ignoring the frame budget. For spawn placement,
## teleports and save loading, where a hitch beats a black screen.
func light_chunk_now(cpos: Vector3i) -> void:
	var c: Chunk = World.chunks.get(cpos)
	if c == null:
		return
	if flood.luts_stale():
		flood.rebuild_luts()
	flood.seed_chunk(c, c.lit)
	c.lit = true
	_seed_set.erase(cpos)
	var idx := _seed_queue.find(cpos)
	if idx >= 0:
		_seed_queue.remove_at(idx)
	var guard := 0
	while flood.pending() > 0 and guard < 512:
		flood.run_slice(4096)
		guard += 1
	flood.end_slice()
	_flush_touched()
	_emit_pending(dirty_max_hold + 1.0)


## Force a chunk (and its light) to be rebuilt from scratch.
func request_relight(cpos: Vector3i) -> void:
	_queue_relight(cpos)


## Re-flood every loaded chunk. Used by the debug overlay and after a planet
## swap changes the block palette.
func relight_all() -> void:
	for cp: Vector3i in World.chunks.keys():
		_relight[cp] = true


## Combined 0..15 illumination at a voxel, already blended with `Game.daylight`.
func level_at(pos: Vector3i) -> int:
	var cy := pos.y >> 4
	if cy < 0 or cy >= Const.WORLD_HEIGHT_CHUNKS:
		return Const.MAX_LIGHT if pos.y >= Const.WORLD_HEIGHT else 0
	var cx := pos.x >> 4
	var cz := pos.z >> 4
	if cx != _fc_x or cy != _fc_y or cz != _fc_z:
		_bind_cache(cx, cy, cz)
	if not _fc_ok:
		return int(round(_daylight_eff * float(Const.MAX_LIGHT)))
	return _level_lut[_fc_light[((pos.y & 15) << 8) | ((pos.z & 15) << 4) | (pos.x & 15)]]


## 0..1 vertex-colour factor for the mesher. This is the hottest function in
## the module — called several times per vertex per chunk rebuild — so it is a
## cached chunk lookup plus one index into a 256-entry table, and allocates
## nothing. It deliberately contains no depth, view or layer term; see the
## header for the split with `render/`.
func factor_at(pos: Vector3i) -> float:
	var cy := pos.y >> 4
	if cy < 0 or cy >= Const.WORLD_HEIGHT_CHUNKS:
		return _open_factor if pos.y >= Const.WORLD_HEIGHT else ambient_floor
	var cx := pos.x >> 4
	var cz := pos.z >> 4
	if cx != _fc_x or cy != _fc_y or cz != _fc_z:
		_bind_cache(cx, cy, cz)
	if not _fc_ok:
		return _open_factor
	return _factor_lut[_fc_light[((pos.y & 15) << 8) | ((pos.z & 15) << 4) | (pos.x & 15)]]


## The full byte -> factor table, indexed by a raw `Chunk.light` byte
## (`sky << 4 | block`). Exactly what `factor_at` looks up.
##
## **Renderer hook.** A mesher that walks `chunk.light` itself should index
## this instead of computing `max(block, sky * Game.daylight) / 15`: it is the
## same shape but already carries the planet's daylight curve, the weather
## dimming, the perceptual response and the ambient floor — so voxels at light
## level 0 come out at the planet's floor rather than pure black. Read-only;
## re-fetch it each rebuild, it is rebuilt whenever the light of day moves.
func light_map() -> PackedFloat32Array:
	return _factor_lut


## The darkest a lit surface gets on this planet, 0..1.
func ambient_floor_value() -> float:
	return _lut_floor


## Raw stored skylight, 0..15, ignoring the time of day.
func sky_level_at(pos: Vector3i) -> int:
	var c: Chunk = World.chunk_at_block(pos)
	if c == null:
		return Const.MAX_LIGHT
	return c.light[((pos.y & 15) << 8) | ((pos.z & 15) << 4) | (pos.x & 15)] >> 4


## Raw stored block light, 0..15.
func block_level_at(pos: Vector3i) -> int:
	var c: Chunk = World.chunk_at_block(pos)
	if c == null:
		return 0
	return c.light[((pos.y & 15) << 8) | ((pos.z & 15) << 4) | (pos.x & 15)] & 15


## Ambient sky colour for the current time of day, planet and weather.
## Safe to call before the world exists.
func sky_color() -> Color:
	if day_night != null:
		return day_night.horizon_color
	return Color(0.35, 0.55, 0.9).lerp(Color(0.02, 0.02, 0.06), 1.0 - Game.daylight)


## Colour the renderer should tint *toward* for far layers, and the colour fog
## and particles should key off.
func ambient_color() -> Color:
	return day_night.ambient_color if day_night != null else Color(0.6, 0.66, 0.78)


func fog_color() -> Color:
	return day_night.fog_color if day_night != null else Color(0.32, 0.4, 0.55)


## Unit vector the sunlight travels along (sun -> ground).
func sun_direction() -> Vector3:
	return day_night.sun_dir if day_night != null else Vector3(-0.4, -0.8, -0.45).normalized()


## 0..1 overall daylight after planet and weather modifiers. This is what
## skylight is multiplied by; `Game.daylight` is the raw solar term.
func daylight() -> float:
	return _daylight_eff


## **Reference curve for the renderer's depth cueing** (term 2 in the header).
## `layer_offset` is `View.layer_offset(pos)`: 0 = play layer, positive =
## further from the camera. Returns the brightness multiplier the slab shader
## should apply *on top of* `factor_at()`. Published here so the falloff is
## defined in exactly one place; `render/` may inline it in GLSL.
func depth_tint(layer_offset: int) -> float:
	if layer_offset <= 0:
		return 1.0
	var t := float(layer_offset) / float(maxi(1, Const.SLAB_BEHIND))
	return clampf(1.0 - 0.72 * sqrt(minf(t, 1.0)), 0.16, 1.0)


func stats() -> Dictionary:
	return {
		"queued_chunks": _seed_queue.size(),
		"relight": _relight.size(),
		"pending_nodes": flood.pending(),
		"ops_last_frame": stats_ops,
		"chunks_lit": stats_chunks_lit,
		"daylight": _daylight_eff,
	}


# ================================================================== internals
func _bind_cache(cx: int, cy: int, cz: int) -> void:
	_fc_x = cx
	_fc_y = cy
	_fc_z = cz
	var c: Chunk = World.chunks.get(Vector3i(posmod(cx, _cw_x), cy, posmod(cz, _cw_z)))
	if c == null:
		_fc_ok = false
		return
	_fc_ok = true
	_fc_light = c.light


func _invalidate_cache() -> void:
	_fc_x = 0x7FFFFFFF
	_fc_ok = false


## Blend the raw solar term with the planet's daylight curve, its ambient floor
## and the current weather, then rebuild the byte->value tables if anything
## actually moved. Cheap enough to call every frame.
func _refresh_daylight() -> void:
	var raw: float = Game.daylight
	var eff := raw
	if planet != null:
		eff = planet.daylight_curve(raw)
	if weather != null:
		eff *= weather.light_scale
	eff = clampf(eff, 0.0, 1.0)
	var floor_v := ambient_floor
	if planet != null:
		floor_v = maxf(floor_v, planet.ambient_floor())
	_daylight_eff = eff
	if absf(eff - _lut_daylight) > 0.004 or absf(floor_v - _lut_floor) > 0.002:
		_build_luts(eff, floor_v)
		_invalidate_cache()


func _build_luts(daylight_factor: float, floor_v: float = -1.0) -> void:
	if floor_v < 0.0:
		floor_v = ambient_floor
	_lut_daylight = daylight_factor
	_lut_floor = floor_v
	_open_factor = _curve(int(round(daylight_factor * 15.0)), floor_v)
	for byte in 256:
		var b := byte & 15
		var s := int(round(float(byte >> 4) * daylight_factor))
		var lvl := maxi(b, s)
		_level_lut[byte] = lvl
		_factor_lut[byte] = _curve(lvl, floor_v)


func _curve(level: int, floor_v: float) -> float:
	var l := clampi(level, 0, 15)
	var expo := pow(curve_base, float(15 - l))
	var lin := float(l) / 15.0
	var f: float = lerpf(expo, lin, curve_linear_mix)
	return clampf(floor_v + (1.0 - floor_v) * f, 0.0, 1.0)
