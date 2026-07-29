## Autoloaded as `Liquids`. Cellular finite-volume liquid solver, sand-style
## gravity, and the entity-side effects of standing in a fluid.
##
## ============================================================================
## HOW IT RUNS
## ============================================================================
## A **fixed 10 Hz tick**, accumulated in `_physics_process` and decoupled from
## the frame rate (at most [constant MAX_STEPS_PER_FRAME] catch-up steps, so a
## hitch never turns into a simulation avalanche).
##
## Only **awake cells** are visited. The active set is a two-level map,
## `chunk position -> {local index -> tick due}`, which buys three things:
##
##  * an unloaded chunk costs literally nothing — its whole bucket is dropped in
##    `_on_chunk_unloaded`, so liquid outside the streamed slab is frozen in
##    place rather than simulated;
##  * viscosity is free — a cell records the tick it may next move, so lava
##    updates every 4th tick without being polled in between;
##  * the per-tick budget can be shared **fairly** between chunks by round-robin
##    (see [method _tick_liquids]). A big flood in one chunk therefore degrades
##    into "the flood advances slower" instead of "everything else stalls".
##
## Cells **sleep**: an update that moves nothing does not re-arm itself, and
## does not touch its neighbours. Settled water costs zero. Anything that
## changes a voxel — the solver itself, `Events.block_changed`, a bucket, an
## explosion — wakes the handful of cells that could care.
##
## ============================================================================
## HOW IT FLOWS
## ============================================================================
## Per cell, in order: react with neighbouring liquids/blocks, fall **down**,
## then equalise **sideways across all four horizontal directions** (this is a
## 3D world; +X is not privileged over +Z, and the four directions are visited
## in a rotating order so ties do not bias one axis), then climb **up** if the
## cell is under pressure. Pressure is stored in quarter-blocks of head, sourced
## from the column above a full cell, and propagated through connected full
## cells (losing `pressure_loss` per lateral step, one block per upward step).
## That is what makes water rise to its source level through a U-bend, and what
## stops it doing so forever.
##
## ============================================================================
## HOW IT STAYS LEGIBLE
## ============================================================================
## The player sees one plane. Liquid arriving from a layer they cannot see is
## the single most confusing thing this module can do, so every transfer that
## crosses **into the play layer from a hidden layer** emits a splash particle,
## a sound and (rarely, throttled) a toast — see [method _cue_cross_layer].
## Levels are exact and stored per voxel, so a plane the player flips into reads
## correctly the instant the mesher rebuilds it.
extends Node

# ------------------------------------------------------------------- tuning
## Simulation rate. 10 Hz is fast enough that a waterfall reads as continuous
## and slow enough that a 1200-cell budget covers a serious flood.
const TICK_HZ := 10.0
const TICK_DT := 1.0 / TICK_HZ
## Cell updates allowed per tick, shared round-robin between active chunks.
const DEFAULT_BUDGET := 1200
## No chunk gets less than this, so a single chunk can never be starved out.
const MIN_CHUNK_SHARE := 16
## Hard ceiling on the active set. Past this, new cells are not woken; existing
## work drains first. Prevents a pathological flood eating all memory.
const MAX_ACTIVE_CELLS := 20000
## Catch-up steps after a frame hitch.
const MAX_STEPS_PER_FRAME := 2

const FULL := Const.MAX_LIQUID
const PRESSURE_UNIT := LiqType.PRESSURE_UNIT

const DOWN := Vector3i(0, -1, 0)
const UP := Vector3i(0, 1, 0)
## All four horizontal directions — never assume the depth axis is special.
const H_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Rotations/reflections of the four directions, picked at random per spread so
## ties break evenly instead of always favouring +X.
const H_ORDERS := [
	[0, 1, 2, 3], [1, 2, 3, 0], [2, 3, 0, 1], [3, 0, 1, 2],
	[3, 2, 1, 0], [2, 1, 0, 3], [1, 0, 3, 2], [0, 3, 2, 1],
]

## Cross-layer inflow cues: at most this many per tick, and one per cell per
## this many ticks.
const CUE_PER_TICK := 3
const CUE_COOLDOWN := 15
const CUE_TOAST_COOLDOWN := 120
const CUE_RANGE := 26.0

# --------------------------------------------------------------------- state
## Master switch — the space agent turns this off during travel cutscenes.
var enabled := true
var cell_budget := DEFAULT_BUDGET

var falling: LiqFalling = null
var ocean: LiqOcean = null
var weather: LiqWeather = null
var interaction: LiqInteraction = null

var _accum := 0.0
var _tick := 0
var _active: Dictionary = {}        ## Vector3i cpos -> Dictionary(idx -> due tick)
var _cursor: Dictionary = {}        ## Vector3i cpos -> resume index
var _active_count := 0
var _rr := 0
var _pressure: Dictionary = {}      ## Vector3i -> quarter-blocks of head
var _dissolve: Dictionary = {}      ## Vector3i -> hardness eaten so far
var _reactive: Dictionary = {}      ## block id -> bool (liquid/liquid rules)
var _blocky: Dictionary = {}        ## block id -> bool (liquid/solid rules)
var _intervals: Dictionary = {}     ## block id -> flow_interval
var _in_sim := false
var _rng := RandomNumberGenerator.new()

## Cross-layer cue throttling.
var _cue_seen: Dictionary = {}
var _cues_this_tick := 0
var _last_toast_tick := -9999

## Debug counters, surfaced through [method debug_info].
var _stat_updates := 0
var _stat_moves := 0

# Scratch buffers reused by _spread so the hot loop does not allocate.
var _s_targets: Array[Vector3i] = [Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO]
var _s_levels := PackedInt32Array([0, 0, 0, 0])
var _s_given := PackedInt32Array([0, 0, 0, 0])


func _ready() -> void:
	process_priority = -20
	_rng.randomize()
	ocean = LiqOcean.new()
	falling = LiqFalling.new()
	interaction = LiqInteraction.new()
	weather = LiqWeather.new()
	weather.setup()
	Events.block_changed.connect(_on_block_changed)
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.world_ready.connect(_on_world_ready)
	Events.world_unloaded.connect(_on_world_unloaded)


# ============================================================== the fixed tick
func _physics_process(delta: float) -> void:
	if not enabled or Game.paused or not World.ready_flag:
		return
	_accum += delta
	var steps := 0
	while _accum >= TICK_DT and steps < MAX_STEPS_PER_FRAME:
		_accum -= TICK_DT
		steps += 1
		_step()
	if _accum > TICK_DT * 4.0:
		_accum = 0.0   ## gave up catching up; drop the backlog


func _step() -> void:
	_tick += 1
	_in_sim = true
	_cues_this_tick = 0
	_stat_updates = 0
	_stat_moves = 0
	ocean.tick()
	_tick_liquids()
	falling.tick(_tick)
	interaction.tick(TICK_DT)
	weather.tick(TICK_DT, _tick)
	_in_sim = false
	if _cue_seen.size() > 512:
		_cue_seen.clear()
	if _pressure.size() > 8192:
		_pressure.clear()


## Fair round-robin over active chunks. Each chunk gets an equal share of the
## budget; whichever chunk we ran out of budget on is where the next tick
## resumes, and each chunk also remembers its own resume index so a flood
## bigger than the budget still advances evenly across its whole front.
func _tick_liquids() -> void:
	if _active.is_empty():
		return
	var chunk_list: Array = _active.keys()
	var n := chunk_list.size()
	var budget := cell_budget
	var share := maxi(MIN_CHUNK_SHARE, int(ceil(float(budget) / float(n))))
	var visited := 0
	while visited < n and budget > 0:
		var cp: Vector3i = chunk_list[(_rr + visited) % n]
		budget -= _tick_chunk(cp, mini(share, budget))
		visited += 1
	_rr = (_rr + maxi(1, visited)) % maxi(1, n)


func _tick_chunk(cp: Vector3i, share: int) -> int:
	var cells: Dictionary = _active.get(cp, {})
	if cells.is_empty():
		_active.erase(cp)
		_cursor.erase(cp)
		return 0
	if not World.chunks.has(cp):
		_active_count -= cells.size()
		_active.erase(cp)
		_cursor.erase(cp)
		return 0
	var keys: Array = cells.keys()
	var count := keys.size()
	var start: int = int(_cursor.get(cp, 0)) % count
	var origin := cp * Const.CHUNK_SIZE
	var spent := 0
	var i := 0
	while i < count and spent < share:
		var k: int = keys[(start + i) % count]
		i += 1
		if not cells.has(k):
			continue                       ## consumed by a neighbour's update
		if int(cells[k]) > _tick:
			continue                       ## viscous cell, not due yet
		cells.erase(k)
		_active_count -= 1
		_update_cell(origin + Chunk.from_index(k))
		spent += 1
		_stat_updates += 1
	_cursor[cp] = (start + i) % maxi(1, count)
	if cells.is_empty():
		_active.erase(cp)
		_cursor.erase(cp)
	return spent


# ================================================================ public API
## Mark a voxel as needing a liquid update. `delay` is in sim ticks.
func wake(pos: Vector3i, delay: int = 0) -> void:
	if _active_count >= MAX_ACTIVE_CELLS:
		return
	if pos.y < 0 or pos.y >= Const.WORLD_HEIGHT:
		return
	var n := World.normalize(pos)
	var cp := Vector3i(n.x >> 4, n.y >> 4, n.z >> 4)
	if not World.chunks.has(cp):
		return
	var bucket: Variant = _active.get(cp)
	if bucket == null:
		bucket = {}
		_active[cp] = bucket
	var cells: Dictionary = bucket
	var idx := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	var due := _tick + maxi(0, delay)
	if cells.has(idx):
		if int(cells[idx]) > due:
			cells[idx] = due
		return
	cells[idx] = due
	_active_count += 1


## Required stub signature: queue a liquid cell for re-evaluation.
func queue_liquid(pos: Vector3i) -> void:
	wake(pos, 0)


## Required stub signature: a block flagged `falls` was placed or unsupported.
func queue_falling(pos: Vector3i) -> void:
	if falling != null:
		falling.queue(pos)


## Required stub signature: 0..Const.MAX_LIQUID fill level of a voxel.
##
## A liquid block whose stored level is 0 (the worldgen writes blocks without
## touching `Chunk.liquid`) counts as **full**, so hand-authored lakes and
## generated oceans render and behave correctly without a migration pass.
func level_at(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= Const.WORLD_HEIGHT:
		return 0
	var n := World.normalize(pos)
	var c: Chunk = World.chunks.get(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))
	if c == null:
		return 0
	var i := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	if not Blocks.is_liquid(c.blocks[i]):
		return 0
	var v := c.liquid[i]
	return FULL if v == 0 else v


## Fill fraction 0..1, for the mesher's surface height and the camera fog.
func fill_at(pos: Vector3i) -> float:
	return float(level_at(pos)) / float(FULL)


func is_liquid_at(pos: Vector3i) -> bool:
	return Blocks.is_liquid(World.get_block(pos))


## Liquid StringName at a voxel, or `&""`.
func liquid_name_at(pos: Vector3i) -> StringName:
	return LiqType.name_of_block(World.get_block(pos))


## Add `amount` units of a named liquid, returning how much actually fitted.
## Used by buckets, pumps, rain and machine outputs.
func add_liquid(pos: Vector3i, liquid: StringName, amount: int = FULL) -> int:
	var id := LiqType.block_id(liquid)
	if id == Const.AIR:
		return 0
	var added := _add(pos, id, amount)
	if added > 0:
		wake(pos, 0)
		_wake_liquid_neighbours(pos, 0)
	return added


## Remove up to `amount` units, returning how much was taken. Ocean sources are
## inexhaustible and always return the full request.
func remove_liquid(pos: Vector3i, amount: int = FULL) -> int:
	var id := World.get_block(pos)
	if id == Const.AIR or not Blocks.is_liquid(id):
		return 0
	var v := level_at(pos)
	if ocean.is_source(pos, id):
		_wake_liquid_neighbours(pos, 0)
		return mini(amount, FULL)
	var take := mini(amount, v)
	if take <= 0:
		return 0
	_write(pos, id, v - take)
	_wake_liquid_neighbours(pos, 0)
	return take


## Wake every liquid cell in a box — explosions, teleports, structure spawns.
func wake_area(center: Vector3i, radius: int = 3) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var q := center + Vector3i(dx, dy, dz)
				if is_liquid_at(q):
					wake(q, 0)


## Unit direction the liquid at `pos` is flowing, or `Vector3.ZERO` when it is
## still. Drives entity currents and the mesher's surface tilt.
func flow_dir_at(pos: Vector3i) -> Vector3:
	var id := World.get_block(pos)
	if id == Const.AIR or not Blocks.is_liquid(id):
		return Vector3.ZERO
	var v := level_at(pos)
	var d := Vector3.ZERO
	for h: Vector3i in H_DIRS:
		var acc := _accepts(pos + h, id)
		if acc >= 0 and acc < v:
			d += Vector3(h) * float(v - acc)
	var down := _accepts(pos + DOWN, id)
	if down >= 0 and down < FULL:
		d.y -= float(FULL - down) * 0.75
	return d.normalized() if d.length_squared() > 0.001 else Vector3.ZERO


## Snapshot for the debug overlay.
func debug_info() -> Dictionary:
	return {
		"tick": _tick,
		"active_cells": _active_count,
		"active_chunks": _active.size(),
		"updates": _stat_updates,
		"moves": _stat_moves,
		"budget": cell_budget,
		"pressure_nodes": _pressure.size(),
		"falling": falling.debug_info() if falling != null else {},
		"ocean": ocean.debug_info() if ocean != null else {},
		"weather": weather.debug_info() if weather != null else {},
	}


# ================================================================ cell update
func _update_cell(p: Vector3i) -> void:
	var id := World.get_block(p)
	if id == Const.AIR or not Blocks.is_liquid(id):
		return
	var lt := LiqType.for_block(id)
	if lt.is_empty():
		return
	var v := level_at(p)
	if v <= 0:
		_clear(p)
		return

	var interval := int(lt["flow_interval"])
	var src: bool = ocean.is_source(p, id)

	# ---- 0. reactions ------------------------------------------------------
	# A reaction rewrites blocks and levels around us, so the cell re-reads the
	# world next tick rather than flowing on stale numbers.
	if _react(p, id, lt, v, interval):
		wake(p, interval)
		return

	var start_v := v
	var moved := false
	var rate := int(lt["flow_rate"])

	# ---- 1. straight down --------------------------------------------------
	var below := p + DOWN
	var below_open := false
	if _may_donate(src, below):
		var acc := _accepts(below, id)
		if acc >= 0 and acc < FULL:
			var give := mini(rate, FULL - acc)
			if not src:
				give = mini(give, v)
			var t := _add(below, id, give)
			if t > 0:
				if not src:
					v -= t
				moved = true
				_cue_cross_layer(p, below, id)
			below_open = (acc + t) < FULL
	# a blocked or full cell below is exactly what makes liquid spread sideways

	# ---- 2. equalise sideways ---------------------------------------------
	if v > 0 and not below_open and v >= int(lt["min_lateral"]):
		var spread := _spread(p, id, v, rate, src)
		if spread > 0:
			if not src:
				v -= spread
			moved = true

	# ---- 3. pressure: climb toward the source level ------------------------
	var loss := int(lt["pressure_loss"])
	var head := int(_pressure.get(p, 0))
	_pressure.erase(p)
	if loss < 90 and v >= FULL:
		head = maxi(head, _head_above(p, id, int(lt["max_head"])) * PRESSURE_UNIT)
		if head > 0:
			var above := p + UP
			if _level_of_same(above, id) >= FULL:
				_push_pressure(above, head - PRESSURE_UNIT, interval)
			for h: Vector3i in H_DIRS:
				if _level_of_same(p + h, id) >= FULL:
					_push_pressure(p + h, head - loss, interval)
			if head >= PRESSURE_UNIT and _may_donate(src, above):
				var acc_up := _accepts(above, id)
				if acc_up >= 0 and acc_up < FULL:
					var t2 := _add(above, id, 1)
					if t2 > 0:
						if not src:
							v -= t2
						moved = true
						_cue_cross_layer(p, above, id)

	# ---- 4. evaporation of unsupported remnants ---------------------------
	if not moved and not src and v <= int(lt["evaporate_at"]):
		var chance := float(lt["evaporate"])
		if chance > 0.0 and not _has_supply(p, id, v) and _rng.randf() < chance:
			_clear(p)
			_wake_liquid_neighbours(p, interval)
			Events.spawn_particles.emit(&"evaporate", Vector3(p) + Vector3(0.5, 0.6, 0.5), 3)
			return

	# ---- 5. write back and decide whether to stay awake --------------------
	if v != start_v:
		_write(p, id, v)
	if moved:
		_stat_moves += 1
		wake(p, interval)
		_wake_liquid_neighbours(p, interval)
	# else: nothing changed — the cell sleeps and costs nothing until something
	# next to it wakes it again.


## Spread liquid over the four horizontal neighbours, one unit at a time to
## whichever acceptor is currently lowest. Conserves volume exactly, never lifts
## a neighbour to this cell's own level (which is what stops two cells trading a
## unit back and forth forever) and stops at `rate` units so viscous liquids
## crawl. Returns the number of units that left `p`.
func _spread(p: Vector3i, id: int, v: int, rate: int, src: bool) -> int:
	var order: Array = H_ORDERS[_rng.randi() & 7]
	var count := 0
	for oi in 4:
		var h: Vector3i = H_DIRS[order[oi]]
		var q := p + h
		if not _may_donate(src, q):
			continue
		var acc := _accepts(q, id)
		if acc < 0 or acc >= v:
			continue
		_s_targets[count] = q
		_s_levels[count] = acc
		_s_given[count] = 0
		count += 1
	if count == 0:
		return 0

	var budget := rate
	if not src:
		budget = mini(budget, v)
	var mine := v
	var moved := 0
	for _unit in budget:
		var best := -1
		for i in count:
			if _s_levels[i] >= mine - 1:
				continue           ## already level with us; do not oscillate
			if best < 0 or _s_levels[i] < _s_levels[best]:
				best = i
		if best < 0:
			break
		_s_levels[best] += 1
		_s_given[best] += 1
		moved += 1
		if not src:
			mine -= 1
	if moved == 0:
		return 0

	var actually := 0
	for i in count:
		if _s_given[i] <= 0:
			continue
		var t := _add(_s_targets[i], id, _s_given[i])
		actually += t
		if t > 0:
			_cue_cross_layer(p, _s_targets[i], id)
	return actually


# ---------------------------------------------------------------- pressure
## Number of full cells of `id` stacked directly on top of `p`.
func _head_above(p: Vector3i, id: int, limit: int) -> int:
	var q := p
	var h := 0
	for _i in limit:
		q.y += 1
		if q.y >= Const.WORLD_HEIGHT:
			break
		if _level_of_same(q, id) < FULL:
			break
		h += 1
	return h


func _push_pressure(q: Vector3i, value: int, delay: int) -> void:
	if value <= 0:
		return
	var n := World.normalize(q)
	if int(_pressure.get(n, 0)) >= value:
		return
	_pressure[n] = value
	wake(n, delay)


## Level of `q` when it holds exactly liquid `id`, else -1.
func _level_of_same(q: Vector3i, id: int) -> int:
	return level_at(q) if World.get_block(q) == id else -1


# ------------------------------------------------------------------ helpers
## Current fill of `q` when liquid `id` may enter it, else -1.
func _accepts(q: Vector3i, id: int) -> int:
	if q.y < 0 or q.y >= Const.WORLD_HEIGHT:
		return -1
	var n := World.normalize(q)
	var c: Chunk = World.chunks.get(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))
	if c == null:
		return -1        ## never spill into an unloaded chunk: liquid would vanish
	var i := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	var b := c.blocks[i]
	if b == id:
		var lv := c.liquid[i]
		return FULL if lv == 0 else lv
	if b == Const.AIR:
		return 0
	if Blocks.is_liquid(b) or Blocks.is_solid(b):
		return -1
	return 0 if Blocks.is_replaceable(b) else -1


## Ocean sources never lift water above the waterline (see `ocean.gd`).
func _may_donate(src: bool, target: Vector3i) -> bool:
	return (not src) or ocean.may_donate_to(target)


## Push `amount` units into `q`, creating the liquid block if needed. Returns
## the units actually stored, which is 0 when the write failed.
func _add(q: Vector3i, id: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var cur := _accepts(q, id)
	if cur < 0 or cur >= FULL:
		return 0
	var nv := mini(FULL, cur + amount)
	if World.get_block(q) != id:
		if not World.set_block(q, id, true):
			return 0
	_set_level_raw(q, nv)
	# Wake on the *receiver's* schedule, so a viscous liquid stays viscous even
	# when something fast is pouring into it.
	wake(q, _interval_of(id))
	return nv - cur


## Cached `flow_interval` for a liquid block id.
func _interval_of(id: int) -> int:
	var hit: Variant = _intervals.get(id)
	if hit != null:
		return int(hit)
	var lt := LiqType.for_block(id)
	var n := 1 if lt.is_empty() else int(lt["flow_interval"])
	_intervals[id] = n
	return n


## Write a level, converting to air at 0.
func _write(p: Vector3i, id: int, v: int) -> void:
	if v <= 0:
		_clear(p)
		return
	if World.get_block(p) != id:
		if not World.set_block(p, id, true):
			return
	_set_level_raw(p, v)


func _clear(p: Vector3i) -> void:
	_set_level_raw(p, 0)
	_pressure.erase(World.normalize(p))
	if Blocks.is_liquid(World.get_block(p)):
		World.set_block(p, Const.AIR, true)


## Direct write into `Chunk.liquid`, marking the chunk (and any chunk whose mesh
## borders this voxel) for a rebuild. Bypasses `World.set_block` because the
## block id is unchanged — only the fill level moved.
func _set_level_raw(p: Vector3i, v: int) -> void:
	var n := World.normalize(p)
	var cp := Vector3i(n.x >> 4, n.y >> 4, n.z >> 4)
	var c: Chunk = World.chunks.get(cp)
	if c == null:
		return
	var i := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	if c.liquid[i] == v:
		return
	c.liquid[i] = v
	c.dirty = true
	World.mark_dirty(cp)
	var lx := n.x & 15
	var ly := n.y & 15
	var lz := n.z & 15
	if lx == 0: World.mark_dirty(cp - Vector3i(1, 0, 0))
	elif lx == 15: World.mark_dirty(cp + Vector3i(1, 0, 0))
	if ly == 0: World.mark_dirty(cp - Vector3i(0, 1, 0))
	elif ly == 15: World.mark_dirty(cp + Vector3i(0, 1, 0))
	if lz == 0: World.mark_dirty(cp - Vector3i(0, 0, 1))
	elif lz == 15: World.mark_dirty(cp + Vector3i(0, 0, 1))


## Wake the six neighbours that actually hold liquid. Air neighbours are left
## alone: they cannot flow on their own, and waking them would burn budget.
func _wake_liquid_neighbours(p: Vector3i, delay: int = 0) -> void:
	for nrm: Vector3i in Const.FACE_NORMALS:
		var q := p + nrm
		if is_liquid_at(q):
			wake(q, delay)


## Is this thin cell being fed from above or from a fuller neighbour?
func _has_supply(p: Vector3i, id: int, v: int) -> bool:
	if _level_of_same(p + UP, id) > 0:
		return true
	for h: Vector3i in H_DIRS:
		if _level_of_same(p + h, id) > v:
			return true
	return false


func _is_reactive(id: int) -> bool:
	var hit: Variant = _reactive.get(id)
	if hit != null:
		return bool(hit)
	var r := LiqType.is_reactive(LiqType.name_of_block(id))
	_reactive[id] = r
	return r


func _touches_blocks(id: int) -> bool:
	var hit: Variant = _blocky.get(id)
	if hit != null:
		return bool(hit)
	var r := LiqType.touches_blocks(LiqType.name_of_block(id))
	_blocky[id] = r
	return r


# ================================================================= reactions
## One pass over the six neighbours, handling both liquid/liquid rules (water
## meets lava) and liquid/solid rules (lava sets wood alight, acid eats the
## wall). Merged into a single loop because it is the second-hottest thing the
## solver does and each half only needed the same `get_block` call.
##
## Returns true when something changed and the cell should re-read the world.
func _react(p: Vector3i, id: int, lt: Dictionary, v: int, interval: int) -> bool:
	var check_liquids := _is_reactive(id)
	var check_blocks := _touches_blocks(id)
	if not check_liquids and not check_blocks:
		return false
	var self_name := StringName(lt["name"])
	var dissolve := float(lt["dissolve"])
	var dissolve_max := float(lt["dissolve_max"])
	var dt := float(interval) * TICK_DT
	for nrm: Vector3i in Const.FACE_NORMALS:
		var q := p + nrm
		var ob := World.get_block(q)
		if ob == Const.AIR or ob == id:
			continue
		if Blocks.is_liquid(ob):
			if not check_liquids:
				continue
			var other := LiqType.name_of_block(ob)
			if other == &"":
				continue
			var r := LiqType.reaction(self_name, other)
			if r.is_empty():
				continue
			_apply_reaction(p, id, v, q, ob, r)
			return true
		if not check_blocks:
			continue
		if _react_block(p, id, self_name, q, ob, dissolve, dissolve_max, dt):
			return true
	return false


func _apply_reaction(p: Vector3i, id: int, v: int, q: Vector3i, ob: int, r: Dictionary) -> void:
	var mid := (Vector3(p) + Vector3(q)) * 0.5 + Vector3(0.5, 0.5, 0.5)
	var side := String(r["block_side"])

	# 1. the solid product (obsidian, stone, ice, ...)
	if side != "":
		var target := p if side == "self" else q
		var lvl := v if side == "self" else level_at(q)
		var list: Array = r["block"] if lvl >= FULL else r["weak_block"]
		var bid := LiqType.resolve_block(list, &"stone")
		_clear(target)
		if bid > 0:
			World.set_block(target, bid, true)

	# 2. conversions (tar catching fire becomes lava)
	var conv_self := StringName(r["convert_self"])
	if conv_self != &"":
		_convert(p, conv_self, v)
	var conv_other := StringName(r["convert_other"])
	if conv_other != &"":
		_convert(q, conv_other, level_at(q))

	# 3. consumption
	if conv_self == &"" and side != "self":
		_consume(p, id, int(r["consume_self"]))
	if conv_other == &"" and side != "other":
		_consume(q, ob, int(r["consume_other"]))

	# 4. presentation and blast
	var particles := StringName(r["particles"])
	if particles != &"":
		Events.spawn_particles.emit(particles, mid, int(r["amount"]))
	var snd := StringName(r["sound"])
	if snd != &"":
		Events.play_sound.emit(snd, mid)
	var shake := float(r["shake"])
	if shake > 0.0 and _near_player(mid, 32.0):
		Events.screen_shake.emit(shake, 0.35)
	var blast := float(r["explode"])
	if blast > 0.0:
		World.explode(mid, blast, blast * 1.5)
		# The explosion's own `block_changed` events are suppressed while the
		# solver is running, so re-wake the crater by hand.
		wake_area(Const.floor_v(mid), ceili(blast) + 1)

	_wake_liquid_neighbours(p, 1)
	_wake_liquid_neighbours(q, 1)


func _convert(p: Vector3i, liquid: StringName, level: int) -> void:
	var nid := LiqType.block_id(liquid)
	if nid == Const.AIR:
		_clear(p)
		return
	_set_level_raw(p, 0)
	if World.set_block(p, nid, true):
		_set_level_raw(p, maxi(1, level))
		wake(p, 1)


func _consume(p: Vector3i, id: int, amount: int) -> void:
	if amount <= 0:
		return
	if World.get_block(p) != id:
		return
	if ocean.is_source(p, id):
		return          ## the sea does not run out
	var v := level_at(p)
	_write(p, id, v - amount)


## Liquid meeting one solid block: lava setting wood alight, water killing fire,
## nitrogen frosting soil, acid eating its way through the world. Returns true
## when the world changed enough that the calling cell must re-read it.
func _react_block(p: Vector3i, id: int, self_name: StringName, q: Vector3i,
		bid: int, dissolve: float, dissolve_max: float, dt: float) -> bool:
	var spot := Vector3(q) + Vector3(0.5, 0.5, 0.5)
	var rule := LiqType.block_reaction(self_name, bid)
	if not rule.is_empty():
		if _rng.randf() > float(rule.get("chance", 1.0)):
			return false
		var res: Array = rule.get("result", [&"air"])
		var nid := LiqType.resolve_block(res, &"")
		if nid < 0:
			return false
		World.set_block(q, nid, true)
		if nid != Const.AIR and Blocks.is_liquid(nid):
			_set_level_raw(q, FULL)
		var pc := StringName(rule.get("particles", &""))
		if pc != &"":
			Events.spawn_particles.emit(pc, spot, int(rule.get("amount", 6)))
		var snd := StringName(rule.get("sound", &""))
		if snd != &"":
			Events.play_sound.emit(snd, spot)
		_consume(p, id, int(rule.get("consume", 0)))
		wake(q, 1)
		return true

	# ---- acid and friends: chew through the block over several ticks -------
	if dissolve <= 0.0:
		return false
	var bt := Blocks.get_type(bid)
	if not bt.breakable or bt.hardness > dissolve_max:
		return false
	var key := World.normalize(q)
	var eaten := float(_dissolve.get(key, 0.0)) + dissolve * dt
	if eaten < bt.hardness:
		_dissolve[key] = eaten
		if _rng.randf() < 0.25:
			Events.spawn_particles.emit(&"acid_bubble", spot, 2)
		return false
	_dissolve.erase(key)
	World.break_block(q, 99, false)
	Events.spawn_particles.emit(&"acid_bubble", spot, 8)
	Events.play_sound.emit(&"hiss", spot)
	_consume(p, id, 1)
	wake(q, 1)
	return true


# ============================================================ cross-layer cue
## The player only sees one plane. Liquid that arrives from a layer they cannot
## see must announce itself, or a flooding room reads as a bug.
func _cue_cross_layer(from: Vector3i, to: Vector3i, id: int) -> void:
	if _cues_this_tick >= CUE_PER_TICK:
		return
	if not View.is_play_layer(to) or View.is_play_layer(from):
		return
	var key := World.normalize(to)
	if _tick - int(_cue_seen.get(key, -99999)) < CUE_COOLDOWN:
		return
	var centre := Vector3(to) + Vector3(0.5, 0.5, 0.5)
	if not _near_player(centre, CUE_RANGE):
		return
	_cue_seen[key] = _tick
	_cues_this_tick += 1
	var lt := LiqType.for_block(id)
	Events.spawn_particles.emit(StringName(lt.get("splash", &"splash_water")), centre, 8)
	Events.spawn_particles.emit(&"liquid_seep", centre, 4)
	Events.play_sound.emit(StringName(lt.get("enter_sound", &"splash")), centre)
	if _tick - _last_toast_tick > CUE_TOAST_COOLDOWN and _near_player(centre, 12.0):
		_last_toast_tick = _tick
		Events.toast("%s is pouring in from another layer." % String(lt.get("display", "Liquid")), "warn")


func _near_player(world_pos: Vector3, radius: float) -> bool:
	if Game.player == null:
		return false
	return Game.player.global_position.distance_squared_to(world_pos) <= radius * radius


# ==================================================================== events
func _on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if _in_sim:
		return       ## the solver already wakes exactly what it disturbed
	if old_id != Const.AIR and Blocks.is_liquid(old_id) and not Blocks.is_liquid(new_id):
		_set_level_raw(pos, 0)
	wake(pos, 0)
	_wake_liquid_neighbours(pos, 0)
	if Blocks.is_solid(old_id) and not Blocks.is_solid(new_id):
		ocean.on_hole_opened(pos)
		falling.queue(pos + UP)
	_dissolve.erase(World.normalize(pos))


func _on_chunk_loaded(cpos: Vector3i) -> void:
	ocean.on_chunk_loaded(cpos)
	_wake_chunk_border(cpos)


## When a chunk streams in, liquid already sitting against its faces may now
## have somewhere to go. Waking only the six faces (not the volume) keeps this
## at ~1500 cheap tests instead of 4096 updates, and the small random delay
## spreads the resulting work over the next half second.
func _wake_chunk_border(cpos: Vector3i) -> void:
	var c: Chunk = World.chunks.get(cpos)
	if c == null or c.empty:
		return
	var o := cpos * Const.CHUNK_SIZE
	var last := Const.CHUNK_SIZE - 1
	for a in Const.CHUNK_SIZE:
		for b in Const.CHUNK_SIZE:
			_wake_if_liquid(o + Vector3i(a, b, 0))
			_wake_if_liquid(o + Vector3i(a, b, last))
			_wake_if_liquid(o + Vector3i(0, a, b))
			_wake_if_liquid(o + Vector3i(last, a, b))
			_wake_if_liquid(o + Vector3i(a, 0, b))
			_wake_if_liquid(o + Vector3i(a, last, b))


func _wake_if_liquid(p: Vector3i) -> void:
	if is_liquid_at(p):
		wake(p, _rng.randi_range(0, 4))


func _on_chunk_unloaded(cpos: Vector3i) -> void:
	var cells: Dictionary = _active.get(cpos, {})
	_active_count -= cells.size()
	_active.erase(cpos)
	_cursor.erase(cpos)
	ocean.on_chunk_unloaded(cpos)


func _on_world_ready(_planet_id: String) -> void:
	_reset()
	LiqType.invalidate()
	ocean.configure(World.planet)
	weather.on_world_ready()


func _on_world_unloaded() -> void:
	_reset()
	ocean.reset()


func _reset() -> void:
	_active.clear()
	_cursor.clear()
	_pressure.clear()
	_dissolve.clear()
	_cue_seen.clear()
	_reactive.clear()
	_blocky.clear()
	_intervals.clear()
	_active_count = 0
	_rr = 0
	if falling != null:
		falling.reset()


# =============================================================== persistence
## Liquid levels live inside `Chunk.liquid`, so the save system already covers
## them; only the transient scheduler state needs restoring, and the cheapest
## correct answer is to wake nothing and let the next edit wake what matters.
func save_state() -> Dictionary:
	return {"tick": _tick, "sea_level": ocean.sea_level}


func load_state(d: Dictionary) -> void:
	_tick = int(d.get("tick", 0))
	var sl := int(d.get("sea_level", -1))
	if sl >= 0:
		ocean.set_sea_level(sl, ocean.default_liquid)
