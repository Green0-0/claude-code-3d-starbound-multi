## Swept-AABB collision against the voxel grid. Pure static — no state.
##
## Entity positions are the *bottom-centre* of the box, so `position.y` is the
## feet height. Motion is resolved one axis at a time (Y, then lateral, then
## depth) which is what gives platformer-feeling movement.
class_name VoxelPhysics
extends RefCounted

const SKIN := 0.001
const MAX_STEP := 1.05      ## auto-step height, in blocks


static func _box_min(pos: Vector3, size: Vector3) -> Vector3:
	return Vector3(pos.x - size.x * 0.5, pos.y, pos.z - size.z * 0.5)


static func _box_max(pos: Vector3, size: Vector3) -> Vector3:
	return Vector3(pos.x + size.x * 0.5, pos.y + size.y, pos.z + size.z * 0.5)


## True when no solid voxel overlaps the box at `pos`.
static func aabb_is_free(pos: Vector3, size: Vector3, ignore_platforms: bool = true) -> bool:
	var lo := _box_min(pos, size)
	var hi := _box_max(pos, size)
	for x in range(floori(lo.x + SKIN), floori(hi.x - SKIN) + 1):
		for y in range(floori(lo.y + SKIN), floori(hi.y - SKIN) + 1):
			for z in range(floori(lo.z + SKIN), floori(hi.z - SKIN) + 1):
				var id := World.get_block(Vector3i(x, y, z))
				if id == Const.AIR or not Blocks.is_solid(id):
					continue
				if ignore_platforms and Blocks.is_platform(id):
					continue
				return false
	return true


## Every solid voxel overlapping the box, as Vector3i.
static func overlapping_blocks(pos: Vector3, size: Vector3) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var lo := _box_min(pos, size)
	var hi := _box_max(pos, size)
	for x in range(floori(lo.x + SKIN), floori(hi.x - SKIN) + 1):
		for y in range(floori(lo.y + SKIN), floori(hi.y - SKIN) + 1):
			for z in range(floori(lo.z + SKIN), floori(hi.z - SKIN) + 1):
				if World.get_block(Vector3i(x, y, z)) != Const.AIR:
					out.append(Vector3i(x, y, z))
	return out


static func _blocked_on_axis(pos: Vector3, size: Vector3, axis: int, moving_down: bool, drop_through: bool) -> bool:
	var lo := _box_min(pos, size)
	var hi := _box_max(pos, size)
	for x in range(floori(lo.x + SKIN), floori(hi.x - SKIN) + 1):
		for y in range(floori(lo.y + SKIN), floori(hi.y - SKIN) + 1):
			for z in range(floori(lo.z + SKIN), floori(hi.z - SKIN) + 1):
				var id := World.get_block(Vector3i(x, y, z))
				if id == Const.AIR or not Blocks.is_solid(id):
					continue
				if Blocks.is_platform(id):
					# One-way: only stops a downward move whose feet started
					# above the platform's top surface.
					if axis != 1 or not moving_down or drop_through:
						continue
					if lo.y < float(y) + 0.999 - SKIN:
						continue
				return true
	return false


## Sweep `size` from `pos` by `motion`.
##
## Returns {
##   position, velocity, on_floor, on_ceiling, on_wall,
##   hit_x, hit_y, hit_z, stepped, floor_block
## }
static func move(pos: Vector3, size: Vector3, motion: Vector3, opts: Dictionary = {}) -> Dictionary:
	var drop_through: bool = opts.get("drop_through", false)
	var auto_step: bool = opts.get("auto_step", true)
	var out := {
		"position": pos, "on_floor": false, "on_ceiling": false, "on_wall": false,
		"hit_x": false, "hit_y": false, "hit_z": false, "stepped": false,
		"floor_block": Const.AIR,
	}
	var p := pos

	# ---- Y first: gravity resolution decides whether we are grounded.
	if absf(motion.y) > 0.0:
		var target := p + Vector3(0, motion.y, 0)
		if _blocked_on_axis(target, size, 1, motion.y < 0.0, drop_through):
			p = _resolve_axis(p, size, 1, motion.y, drop_through)
			out["hit_y"] = true
			if motion.y < 0.0:
				out["on_floor"] = true
				out["floor_block"] = World.get_block(Vector3i(floori(p.x), floori(p.y - 0.05), floori(p.z)))
			else:
				out["on_ceiling"] = true
		else:
			p = target

	# ---- horizontal axes, with an auto-step attempt on failure.
	for axis in [0, 2]:
		var m: float = motion[axis]
		if absf(m) <= 0.0:
			continue
		var target := p
		target[axis] += m
		if not _blocked_on_axis(target, size, axis, false, drop_through):
			p = target
			continue
		var stepped := false
		if auto_step:
			var lifted := target
			lifted.y += MAX_STEP
			if not _blocked_on_axis(lifted, size, axis, false, drop_through):
				# Settle back down onto the step.
				var settled := lifted
				for i in 12:
					var probe := settled
					probe.y -= MAX_STEP / 12.0
					if _blocked_on_axis(probe, size, 1, true, drop_through):
						break
					settled = probe
				if not _blocked_on_axis(settled, size, axis, false, drop_through):
					p = settled
					stepped = true
					out["stepped"] = true
					out["on_floor"] = true
		if not stepped:
			p = _resolve_axis(p, size, axis, m, drop_through)
			out["on_wall"] = true
			if axis == 0:
				out["hit_x"] = true
			else:
				out["hit_z"] = true

	# Grounded check even when we did not move vertically this frame.
	if not out["on_floor"] and motion.y <= 0.0:
		var probe := p
		probe.y -= 0.06
		if _blocked_on_axis(probe, size, 1, true, drop_through):
			out["on_floor"] = true
			out["floor_block"] = World.get_block(Vector3i(floori(p.x), floori(p.y - 0.1), floori(p.z)))

	out["position"] = p
	return out


## Binary-search the furthest legal position along one axis.
static func _resolve_axis(pos: Vector3, size: Vector3, axis: int, amount: float, drop_through: bool) -> Vector3:
	var lo := 0.0
	var hi := amount
	var best := pos
	for i in 10:
		var mid := (lo + hi) * 0.5
		var probe := pos
		probe[axis] += mid
		if _blocked_on_axis(probe, size, axis, amount < 0.0 and axis == 1, drop_through):
			hi = mid
		else:
			lo = mid
			best = probe
	# Nudge out of the surface so the next frame does not start embedded.
	best[axis] -= signf(amount) * SKIN
	return best


## Push a box out of any solid voxels it is embedded in. Used after teleports,
## world edits under an entity, and layer shifts.
static func unstick(pos: Vector3, size: Vector3, max_push: int = 4) -> Vector3:
	if aabb_is_free(pos, size):
		return pos
	var candidates: Array[Vector3] = []
	for d in range(1, max_push + 1):
		candidates.append(Vector3(0, d, 0))
		candidates.append(Vector3(d, 0, 0))
		candidates.append(Vector3(-d, 0, 0))
		candidates.append(Vector3(0, 0, d))
		candidates.append(Vector3(0, 0, -d))
		candidates.append(Vector3(0, -d, 0))
	for c: Vector3 in candidates:
		var q := pos + c
		if aabb_is_free(q, size):
			return q
	return pos


## Ground height directly beneath `pos`, or -1.0 when there is nothing below.
static func ground_below(pos: Vector3, max_drop: float = 64.0) -> float:
	var x := floori(pos.x)
	var z := floori(pos.z)
	var start := floori(pos.y)
	for y in range(start, maxi(-1, start - int(max_drop)), -1):
		var id := World.get_block(Vector3i(x, y, z))
		if id != Const.AIR and Blocks.is_solid(id):
			return float(y + 1)
	return -1.0


## Is the box standing in liquid, and how deep (0..1 of its height)?
static func liquid_submersion(pos: Vector3, size: Vector3) -> float:
	var lo := _box_min(pos, size)
	var hi := _box_max(pos, size)
	var total := 0
	var wet := 0
	for x in range(floori(lo.x), floori(hi.x - SKIN) + 1):
		for y in range(floori(lo.y), floori(hi.y - SKIN) + 1):
			for z in range(floori(lo.z), floori(hi.z - SKIN) + 1):
				total += 1
				if Blocks.is_liquid(World.get_block(Vector3i(x, y, z))):
					wet += 1
	return 0.0 if total == 0 else float(wet) / float(total)
