## Plane-space navigation for monsters.
##
## The search space is a 2-D slice of the voxel grid: the *lateral* axis of the
## current view plus world +Y, taken at one depth layer. That is exactly the
## slice the player can see, so a path that looks sensible on screen is the path
## the monster actually walks.
##
## The interesting part is the third dimension. A slice can be walled off, and
## the neighbouring layer often is not — so the graph also carries **layer
## transition edges**: a node may step one voxel along the depth axis for a
## (deliberately expensive) cost. The A* therefore produces routes like
## "run right, shift one layer behind the wall, run right again, shift back into
## the player's plane" without any of that being special-cased.
##
## Everything here is static and stateless apart from a small path cache and a
## per-frame budget: `begin_frame()` is called once by the entity manager and no
## more than `MAX_SEARCHES_PER_FRAME` A* runs happen before the next one.
class_name MobPath
extends RefCounted

const PROFILE_WALK := &"walk"
const PROFILE_FLY := &"fly"
const PROFILE_SWIM := &"swim"
const PROFILE_AMPHIBIOUS := &"amphibious"
const PROFILE_GHOST := &"ghost"     ## ignores geometry entirely (wraiths, blinkers)

const MAX_SEARCHES_PER_FRAME := 3
const DEFAULT_MAX_NODES := 900
const CACHE_TTL := 1.4
const CACHE_LIMIT := 96
## A layer transition is worth about five lateral steps: monsters prefer to stay
## in the plane you can see, but will duck behind it when that is much shorter.
const DEFAULT_LAYER_COST := 5.0

static var _budget := MAX_SEARCHES_PER_FRAME
static var _cache: Dictionary = {}
static var _epoch: int = 0
static var _searches_run: int = 0
static var _nodes_visited: int = 0


# ============================================================ frame plumbing
## Called once per physics frame by the entity manager.
static func begin_frame() -> void:
	_budget = MAX_SEARCHES_PER_FRAME


## Any world edit invalidates every cached route. Cheap: we bump a counter and
## stale entries are ignored on lookup, then evicted lazily.
static func invalidate() -> void:
	_epoch += 1
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()


static func budget_left() -> int:
	return _budget


static func stats() -> Dictionary:
	return {"searches": _searches_run, "nodes": _nodes_visited, "cached": _cache.size()}


# ============================================================ plane geometry
## Index of the world axis that maps to screen-right (0 = X, 2 = Z).
static func lateral_axis(view: int = -1) -> int:
	var v: int = View.view if view < 0 else view
	return 0 if Const.VIEW_DEPTH_AXIS[v] == 2 else 2


static func depth_axis(view: int = -1) -> int:
	var v: int = View.view if view < 0 else view
	return Const.VIEW_DEPTH_AXIS[v]


## Unit step along the lateral axis, in world block space, for `dir` = ±1 in
## *screen* space. Uses `VIEW_RIGHT` so screen-right is screen-right in all four
## planes.
static func lateral_step(dir: int, view: int = -1) -> Vector3i:
	var v: int = View.view if view < 0 else view
	var r: Vector3i = Const.VIEW_RIGHT[v]
	return Vector3i(r.x * dir, 0, r.z * dir)


static func depth_unit(view: int = -1) -> Vector3i:
	return Vector3i(1, 0, 0) if depth_axis(view) == 0 else Vector3i(0, 0, 1)


## Screen-space (lateral, up) delta between two world points.
static func plane_delta(from: Vector3, to: Vector3, view: int = -1) -> Vector2:
	var v: int = View.view if view < 0 else view
	return Vector2(Const.lateral_of(to - from, v), to.y - from.y)


## Raw depth-layer index (the integer coordinate along the depth axis).
static func layer_of(world_pos: Vector3, view: int = -1) -> int:
	var v: int = View.view if view < 0 else view
	return floori(Const.depth_of(world_pos, v))


# ============================================================ voxel queries
static func _blocks(p: Vector3i) -> bool:
	var id := World.get_block(p)
	if id == Const.AIR:
		return false
	if not Blocks.is_solid(id):
		return false
	return not Blocks.is_platform(id)


static func _supports(p: Vector3i) -> bool:
	var id := World.get_block(p)
	return id != Const.AIR and Blocks.is_solid(id)


static func _is_liquid(p: Vector3i) -> bool:
	return Blocks.is_liquid(World.get_block(p))


static func _climbable(p: Vector3i) -> bool:
	return Blocks.is_climbable(World.get_block(p))


## Is a creature `height` blocks tall able to occupy the column at `p`?
static func _free(p: Vector3i, height: int) -> bool:
	for i in height:
		if _blocks(p + Vector3i(0, i, 0)):
			return false
	return true


static func _grounded(p: Vector3i, height: int) -> bool:
	return _free(p, height) and _supports(p + Vector3i(0, -1, 0))


## First landing cell at or below `p`, or null-ish (`p.y = -9999`) if the drop
## exceeds `max_fall` or falls into the void.
static func _fall_to(p: Vector3i, height: int, max_fall: int) -> Vector3i:
	var q := p
	for _i in range(max_fall + 1):
		if _supports(q + Vector3i(0, -1, 0)):
			return q
		q.y -= 1
		if q.y < 1 or not _free(q, height):
			break
	return Vector3i(p.x, -9999, p.z)


# ============================================================ public helpers
## True when the ground disappears one step ahead — used by the cheap steering
## fallback so a monster without a path does not stroll off a cliff.
static func is_ledge_ahead(world_pos: Vector3, dir: int, height: int = 2, look: int = 1) -> bool:
	var p := Const.floor_v(world_pos) + lateral_step(dir) * look
	if _blocks(p):
		return false
	for d in range(1, 5):
		if _supports(p - Vector3i(0, d, 0)):
			return false
	return true


## Height of the obstacle directly ahead, in blocks (0 = clear path).
static func obstacle_height(world_pos: Vector3, dir: int, height: int = 2, max_probe: int = 4) -> int:
	var base := Const.floor_v(world_pos)
	var ahead := base + lateral_step(dir)
	if not _blocks(ahead):
		return 0
	for h in range(1, max_probe + 1):
		if _free(ahead + Vector3i(0, h, 0), height):
			return h
	return max_probe + 1


## True when nothing solid sits between two points in the same plane. Cheap
## line-of-sight for aggro checks.
static func line_of_sight(from: Vector3, to: Vector3, max_dist: float = 40.0) -> bool:
	var d := to - from
	var dist := d.length()
	if dist < 0.001:
		return true
	if dist > max_dist:
		return false
	var hit := World.raycast(from, d / dist, dist)
	return not bool(hit.get("hit", false))


## Can this creature stand here? Used by the spawn director too.
static func can_stand(world_pos: Vector3, size: Vector3) -> bool:
	if not VoxelPhysics.aabb_is_free(world_pos, size):
		return false
	return VoxelPhysics.ground_below(world_pos + Vector3(0, 0.2, 0), 3.0) >= 0.0


# ================================================================== the search
## Find a route from `from` to `to`.
##
## `opts`:
##   profile:StringName   walk | fly | swim | amphibious | ghost
##   height:int           creature height in blocks (default 2)
##   jump:int             max jump height in blocks (default 2)
##   max_fall:int         survivable drop (default 5)
##   allow_layer:bool     may the route shift depth layers? (default true)
##   layer_span:int       how many layers either side may be used (default 3)
##   layer_cost:float     penalty per layer transition
##   max_nodes:int        search cap
##   view:int             plane to reason in (default the live one)
##
## Returns an `Array[Vector3]` of world waypoints (block centres, feet height),
## empty when no route was found or the budget was spent.
static func find_path(from: Vector3, to: Vector3, opts: Dictionary = {}) -> Array[Vector3]:
	var empty: Array[Vector3] = []
	var profile: StringName = opts.get("profile", PROFILE_WALK)
	var view: int = int(opts.get("view", View.view))
	var start := Const.floor_v(from)
	var goal := Const.floor_v(to)

	if profile == PROFILE_GHOST:
		var direct: Array[Vector3] = [_centre(goal)]
		return direct
	if start == goal:
		return empty

	var key := "%d|%d,%d,%d|%d,%d,%d|%s" % [view, start.x, start.y, start.z,
		goal.x, goal.y, goal.z, profile]
	var now := float(Time.get_ticks_msec()) * 0.001
	var hit: Dictionary = _cache.get(key, {})
	if not hit.is_empty():
		if int(hit["epoch"]) == _epoch and now - float(hit["time"]) < CACHE_TTL:
			var cached: Array[Vector3] = hit["path"]
			return cached.duplicate()
		_cache.erase(key)

	if _budget <= 0:
		return empty
	_budget -= 1
	_searches_run += 1

	var path := _astar(start, goal, profile, view, opts)
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_cache[key] = {"path": path.duplicate(), "epoch": _epoch, "time": now}
	return path


static func _centre(p: Vector3i) -> Vector3:
	return Vector3(float(p.x) + 0.5, float(p.y), float(p.z) + 0.5)


static func _astar(start: Vector3i, goal: Vector3i, profile: StringName, view: int,
		opts: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var height: int = maxi(1, int(opts.get("height", 2)))
	var jump: int = maxi(0, int(opts.get("jump", 2)))
	var max_fall: int = maxi(0, int(opts.get("max_fall", 5)))
	var allow_layer: bool = bool(opts.get("allow_layer", true))
	var layer_span: int = maxi(0, int(opts.get("layer_span", 3)))
	var layer_cost: float = float(opts.get("layer_cost", DEFAULT_LAYER_COST))
	var max_nodes: int = maxi(32, int(opts.get("max_nodes", DEFAULT_MAX_NODES)))

	var lat_ax := lateral_axis(view)
	var dep_ax := depth_axis(view)
	var lat_pos := Vector3i(1, 0, 0) if lat_ax == 0 else Vector3i(0, 0, 1)
	var dep_pos := Vector3i(1, 0, 0) if dep_ax == 0 else Vector3i(0, 0, 1)
	var start_depth: int = start.x if dep_ax == 0 else start.z
	var goal_depth: int = goal.x if dep_ax == 0 else goal.z

	# Give up early on absurd requests rather than burning the node budget.
	var span := Vector3(goal - start)
	if absf(span[lat_ax]) + absf(span.y) > 110.0:
		return out

	var came: Dictionary = {}       # Vector3i -> Vector3i
	var g_score: Dictionary = {}    # Vector3i -> float
	g_score[start] = 0.0
	var closed: Dictionary = {}
	# Open list: a plain array kept as a binary heap of [f, counter, cell].
	var open: Array = []
	var counter := 0
	_heap_push(open, [_heuristic(start, goal, lat_ax, dep_ax, layer_cost), counter, start])

	var best := start
	var best_h := _heuristic(start, goal, lat_ax, dep_ax, layer_cost)
	var visited := 0

	while not open.is_empty() and visited < max_nodes:
		var top: Array = _heap_pop(open)
		var cur: Vector3i = top[2]
		if closed.has(cur):
			continue
		closed[cur] = true
		visited += 1
		if cur == goal:
			best = cur
			best_h = 0.0
			break
		var h := _heuristic(cur, goal, lat_ax, dep_ax, layer_cost)
		if h < best_h:
			best_h = h
			best = cur

		var cur_g: float = g_score[cur]
		for edge: Array in _neighbours(cur, profile, height, jump, max_fall, lat_pos, dep_pos,
				allow_layer, layer_span, layer_cost, start_depth, goal_depth, dep_ax):
			var nxt: Vector3i = edge[0]
			if closed.has(nxt):
				continue
			var ng: float = cur_g + float(edge[1])
			if g_score.has(nxt) and ng >= float(g_score[nxt]):
				continue
			g_score[nxt] = ng
			came[nxt] = cur
			counter += 1
			_heap_push(open, [ng + _heuristic(nxt, goal, lat_ax, dep_ax, layer_cost), counter, nxt])

	_nodes_visited += visited
	# A partial route toward the goal is far more useful than nothing: monsters
	# re-path constantly, so "get closer" converges.
	if best == start:
		return out
	var chain: Array[Vector3i] = [best]
	var walk := best
	while came.has(walk):
		walk = came[walk]
		chain.append(walk)
		if chain.size() > 512:
			break
	chain.reverse()
	for i in range(1, chain.size()):
		out.append(_centre(chain[i]))
	return out


static func _heuristic(a: Vector3i, b: Vector3i, lat_ax: int, dep_ax: int, layer_cost: float) -> float:
	var dl: float = absf(float(b[lat_ax] - a[lat_ax]))
	var dy: float = absf(float(b.y - a.y))
	var dd: float = absf(float(b[dep_ax] - a[dep_ax]))
	return dl + dy * 1.08 + dd * layer_cost


static func _neighbours(p: Vector3i, profile: StringName, height: int, jump: int, max_fall: int,
		lat_pos: Vector3i, dep_pos: Vector3i, allow_layer: bool, layer_span: int,
		layer_cost: float, start_depth: int, goal_depth: int, dep_ax: int) -> Array:
	var out: Array = []
	var swims := profile == PROFILE_SWIM
	var flies := profile == PROFILE_FLY
	var amphibious := profile == PROFILE_AMPHIBIOUS

	if flies or swims or amphibious:
		# Free 2-D movement in the plane; diagonals cost the honest amount.
		for dl in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dl == 0 and dy == 0:
					continue
				var q: Vector3i = p + lat_pos * dl + Vector3i(0, dy, 0)
				if not _free(q, height):
					continue
				if swims and not _is_liquid(q):
					continue
				var c: float = 1.0 if (dl == 0 or dy == 0) else 1.42
				if amphibious and not _is_liquid(q):
					c *= 1.6            # crawls awkwardly out of water
				out.append([q, c])
	else:
		for dir in [-1, 1]:
			var step: Vector3i = lat_pos * dir
			var q: Vector3i = p + step
			if _free(q, height):
				if _supports(q + Vector3i(0, -1, 0)):
					out.append([q, 1.0])
				else:
					var land := _fall_to(q, height, max_fall)
					if land.y > -9000:
						out.append([land, 1.0 + 0.35 * float(q.y - land.y)])
			else:
				# Blocked: try to hop over. One block is a free auto-step.
				for jh in range(1, jump + 1):
					if not _free(p + Vector3i(0, jh, 0), height):
						break
					var up: Vector3i = q + Vector3i(0, jh, 0)
					if not _free(up, height):
						continue
					if _supports(up + Vector3i(0, -1, 0)):
						out.append([up, 1.15 if jh == 1 else 1.4 + 0.55 * float(jh)])
					break
		# Ladders / vines.
		if _climbable(p) or _climbable(p + Vector3i(0, 1, 0)):
			var up := p + Vector3i(0, 1, 0)
			if _free(up, height):
				out.append([up, 1.25])
		var down := p - Vector3i(0, 1, 0)
		if _climbable(down) and _free(down, height):
			out.append([down, 1.0])

	# ---- layer transition edges: the whole point of this file. -------------
	if allow_layer:
		var here_depth: int = p[dep_ax]
		for dd in [-1, 1]:
			var nd: int = here_depth + dd
			if absi(nd - start_depth) > layer_span and absi(nd - goal_depth) > layer_span:
				continue
			var q: Vector3i = p + dep_pos * dd
			if not _free(q, height):
				continue
			if flies:
				out.append([q, layer_cost])
				continue
			if swims or amphibious:
				if swims and not _is_liquid(q):
					continue
				out.append([q, layer_cost])
				continue
			if _supports(q + Vector3i(0, -1, 0)):
				out.append([q, layer_cost])
			else:
				var land := _fall_to(q, height, max_fall)
				if land.y > -9000:
					out.append([land, layer_cost + 0.35 * float(q.y - land.y)])
	return out


# ============================================================== binary heap
static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _less(heap[i], heap[parent]):
			var t: Array = heap[i]
			heap[i] = heap[parent]
			heap[parent] = t
			i = parent
		else:
			break


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var small := i
			if l < n and _less(heap[l], heap[small]):
				small = l
			if r < n and _less(heap[r], heap[small]):
				small = r
			if small == i:
				break
			var t: Array = heap[i]
			heap[i] = heap[small]
			heap[small] = t
			i = small
	return top


static func _less(a: Array, b: Array) -> bool:
	if float(a[0]) != float(b[0]):
		return float(a[0]) < float(b[0])
	return int(a[1]) < int(b[1])
