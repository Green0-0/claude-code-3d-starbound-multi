## Target-selection helpers shared by weapons, projectiles and monster AI.
##
## Everything here reasons in **plane space** — `Vector2(lateral, up)` — because
## the game is a side-scroller that happens to live in a voxel volume. A cone
## is a cone *on screen*; a "nearest enemy" search normally refuses to look into
## other depth layers at all.
##
## Depth is a first-class filter, never an afterthought: pass `layer_rule` in
## the options dictionary of any query.
class_name CbtTargeting
extends RefCounted


# ============================================================== entity access
## Every live `VoxelEntity` in the scene tree.
static func all_entities(group: StringName = &"entities") -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for n: Node in tree.get_nodes_in_group(group):
		var e := n as VoxelEntity
		if e != null and not e.dead and e.is_inside_tree():
			out.append(e)
	return out


## Default option set for every query in this file.
##
## ```
## {
##   "layer_rule":   CbtDamage.LAYER_SAME,
##   "layer_min":    0, "layer_max": 0,     # LAYER_RANGE only, signed away from camera
##   "origin_layer": View.layer,
##   "exclude":      Node | Array[Node],
##   "faction":      StringName,            # only entities of this faction
##   "hostile_to":   Node,                  # only entities whose faction differs
##   "group":        &"entities",
##   "max_targets":  0,                     # 0 = unlimited
##   "require_los":  false,                 # voxel line-of-sight from the origin
## }
## ```
static func default_opts() -> Dictionary:
	return {
		"layer_rule": CbtDamage.LAYER_SAME,
		"layer_min": 0,
		"layer_max": 0,
		"origin_layer": View.layer,
		"exclude": null,
		"faction": &"",
		"hostile_to": null,
		"group": &"entities",
		"max_targets": 0,
		"require_los": false,
	}


## Is this entity a legal target under `opts` (faction, exclusions, depth)?
static func accepts(e: VoxelEntity, opts: Dictionary) -> bool:
	if e == null or e.dead:
		return false
	var ex: Variant = opts.get("exclude", null)
	if ex is Array:
		if (ex as Array).has(e):
			return false
	elif ex != null and ex == e:
		return false
	var fac: StringName = opts.get("faction", &"")
	if fac != &"" and e.faction != fac:
		return false
	var hostile_to: Variant = opts.get("hostile_to", null)
	if hostile_to is VoxelEntity:
		var other := hostile_to as VoxelEntity
		if e.faction == other.faction:
			return false
		if e.faction == &"neutral" and other.faction != &"hostile":
			return false
	return layer_ok(e, opts)


## The depth-layer gate, shared with [CbtDamage] so a weapon's targeting and its
## damage always agree about what it can reach.
static func layer_ok(node: Node3D, opts: Dictionary) -> bool:
	var rule := int(opts.get("layer_rule", CbtDamage.LAYER_SAME))
	if rule == CbtDamage.LAYER_ALL:
		return true
	var origin := int(opts.get("origin_layer", View.layer))
	var l := floori(View.depth_of(node.global_position))
	if rule == CbtDamage.LAYER_SAME:
		return l == origin
	var off := (l - origin) * View.depth_sign()
	return off >= int(opts.get("layer_min", 0)) and off <= int(opts.get("layer_max", 0))


## Plane-space AABB of an entity: `Rect2(bottom-left, size)` in (lateral, up).
static func plane_rect(e: VoxelEntity) -> Rect2:
	var p := View.to_plane(e.global_position)
	var s := e.get_aabb_size()
	# Both lateral axes of the box are the same width in practice; use x.
	var half := maxf(0.1, s.x * 0.5)
	return Rect2(p.x - half, p.y, half * 2.0, maxf(0.1, s.y))


## Plane-space centre of an entity.
static func plane_center(e: VoxelEntity) -> Vector2:
	return View.to_plane(e.aabb_center())


# ================================================================ shape tests
## Entities whose plane box overlaps an axis-aligned rectangle.
static func in_rect(rect: Rect2, opts: Dictionary = {}) -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	var limit := int(opts.get("max_targets", 0))
	for e: VoxelEntity in all_entities(opts.get("group", &"entities")):
		if not accepts(e, opts):
			continue
		if not rect.intersects(plane_rect(e)):
			continue
		out.append(e)
		if limit > 0 and out.size() >= limit:
			break
	return out


## Entities inside a plane-space circle (measured to the entity's centre, with
## its box radius added so big monsters are easier to clip).
static func in_circle(origin: Vector2, radius: float, opts: Dictionary = {}) -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	var limit := int(opts.get("max_targets", 0))
	for e: VoxelEntity in all_entities(opts.get("group", &"entities")):
		if not accepts(e, opts):
			continue
		var r := plane_rect(e)
		if _rect_circle_overlap(r, origin, radius):
			out.append(e)
			if limit > 0 and out.size() >= limit:
				break
	return out


## Entities inside a cone: apex at `origin`, axis `dir`, reach `length`,
## opening `half_angle_deg` either side of the axis. The classic flamethrower /
## shotgun / breath-attack volume.
static func in_cone(origin: Vector2, dir: Vector2, length: float,
		half_angle_deg: float, opts: Dictionary = {}) -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	if dir.length_squared() < 0.0001:
		return out
	var axis := dir.normalized()
	var cos_limit := cos(deg_to_rad(clampf(half_angle_deg, 0.0, 180.0)))
	var limit := int(opts.get("max_targets", 0))
	for e: VoxelEntity in all_entities(opts.get("group", &"entities")):
		if not accepts(e, opts):
			continue
		var to := plane_center(e) - origin
		var d := to.length()
		if d > length:
			continue
		# Anything overlapping the apex counts, whatever the angle.
		if d < 0.35:
			out.append(e)
		elif to.normalized().dot(axis) >= cos_limit:
			out.append(e)
		else:
			continue
		if limit > 0 and out.size() >= limit:
			break
	return out


## Entities inside an annular arc — a sword swing. `from_deg`/`to_deg` are
## measured from screen-right, counter-clockwise, and the band between
## `inner` and `radius` is what actually connects, so a big overhead swing
## does not hit something standing on your toes.
static func in_arc(origin: Vector2, radius: float, from_deg: float, to_deg: float,
		inner: float = 0.0, opts: Dictionary = {}) -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	var limit := int(opts.get("max_targets", 0))
	var a0 := minf(from_deg, to_deg)
	var a1 := maxf(from_deg, to_deg)
	for e: VoxelEntity in all_entities(opts.get("group", &"entities")):
		if not accepts(e, opts):
			continue
		var r := plane_rect(e)
		if not _rect_circle_overlap(r, origin, radius):
			continue
		var to := plane_center(e) - origin
		var d := to.length()
		if d < inner and d > 0.35:
			continue
		if d < 0.35:
			out.append(e)
		else:
			var ang := rad_to_deg(atan2(to.y, to.x))
			if _angle_between(ang, a0, a1):
				out.append(e)
			else:
				continue
		if limit > 0 and out.size() >= limit:
			break
	return out


## Entities touched by a thick line segment — a thrust, a beam, a whip crack.
static func in_capsule(a: Vector2, b: Vector2, thickness: float,
		opts: Dictionary = {}) -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	var limit := int(opts.get("max_targets", 0))
	for e: VoxelEntity in all_entities(opts.get("group", &"entities")):
		if not accepts(e, opts):
			continue
		var c := plane_center(e)
		var r := plane_rect(e)
		var reach := thickness + maxf(r.size.x, r.size.y) * 0.5
		if _point_segment_distance(c, a, b) <= reach:
			out.append(e)
			if limit > 0 and out.size() >= limit:
				break
	return out


# ============================================================ picking targets
## The closest legal target to `origin` (plane-space distance). By default this
## refuses to see anything outside the play layer — which is exactly why
## stepping one layer back is a real defensive option.
static func nearest(origin: Vector2, max_dist: float, opts: Dictionary = {}) -> VoxelEntity:
	var best: VoxelEntity = null
	var best_d := max_dist
	for e: VoxelEntity in all_entities(opts.get("group", &"entities")):
		if not accepts(e, opts):
			continue
		var d := origin.distance_to(plane_center(e))
		if d >= best_d:
			continue
		if bool(opts.get("require_los", false)):
			var from := View.to_world(origin, float(View.layer) + 0.5)
			if not has_line_of_sight(from, e.aabb_center()):
				continue
		best_d = d
		best = e
	return best


## Nearest entity hostile to `to`. `to` is usually the player or a monster.
static func nearest_hostile(to: VoxelEntity, max_dist: float = 24.0,
		opts: Dictionary = {}) -> VoxelEntity:
	if to == null:
		return null
	var o := default_opts()
	o["origin_layer"] = floori(View.depth_of(to.global_position))
	o["hostile_to"] = to
	o["exclude"] = to
	for k: String in opts:
		o[k] = opts[k]
	return nearest(View.to_plane(to.aabb_center()), max_dist, o)


## All hostiles to `to` within `max_dist`, nearest first.
static func hostiles_near(to: VoxelEntity, max_dist: float = 24.0,
		opts: Dictionary = {}) -> Array[VoxelEntity]:
	var o := default_opts()
	o["origin_layer"] = floori(View.depth_of(to.global_position)) if to != null else View.layer
	o["hostile_to"] = to
	o["exclude"] = to
	for k: String in opts:
		o[k] = opts[k]
	var origin := View.to_plane(to.aabb_center()) if to != null else Vector2.ZERO
	var found := in_circle(origin, max_dist, o)
	found.sort_custom(func(a: VoxelEntity, b: VoxelEntity) -> bool:
		return origin.distance_squared_to(plane_center(a)) < origin.distance_squared_to(plane_center(b)))
	return found


## Entities in *other* depth layers within `max_dist` on screen — the "I can see
## it but I cannot hit it" set. AI uses this to taunt; the HUD uses it to draw
## ghost markers; layer-piercing weapons use it to pick victims.
static func visible_other_layers(origin: Vector2, max_dist: float,
		behind_only: bool = true) -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	for e: VoxelEntity in all_entities():
		var off := (floori(View.depth_of(e.global_position)) - View.layer) * View.depth_sign()
		if off == 0:
			continue
		if behind_only and off < 0:
			continue
		if off > Const.SLAB_BEHIND:
			continue
		if origin.distance_to(plane_center(e)) <= max_dist:
			out.append(e)
	return out


# =============================================================== line of sight
## Voxel line-of-sight between two world points, using `World.raycast`.
static func has_line_of_sight(from: Vector3, to: Vector3, slack: float = 0.6) -> bool:
	var delta := to - from
	var dist := delta.length()
	if dist < 0.01:
		return true
	var hit := World.raycast(from, delta / dist, dist)
	if not bool(hit.get("hit", false)):
		return true
	return float(hit.get("distance", dist)) >= dist - slack


## Line-of-sight that ignores depth: casts inside the view plane at the play
## layer's centre. Used by weapons that fire "on screen" regardless of where the
## shooter's box physically sits within its voxel.
static func plane_line_of_sight(a: Vector2, b: Vector2, depth: float = NAN) -> bool:
	var d := depth
	if is_nan(d):
		d = float(View.layer) + 0.5
	return has_line_of_sight(View.to_world(a, d), View.to_world(b, d))


## First voxel a plane-space shot runs into, or an empty dictionary on a miss.
## Returns the raw `World.raycast` result.
static func plane_raycast(from: Vector2, dir: Vector2, max_dist: float,
		depth: float = NAN) -> Dictionary:
	var d := depth
	if is_nan(d):
		d = float(View.layer) + 0.5
	var w_from := View.to_world(from, d)
	var w_dir := View.plane_dir_to_world(dir.normalized())
	return World.raycast(w_from, w_dir, max_dist)


# ================================================================== aim maths
## Straight-line aim from `shooter` to `target`, in plane space.
static func aim_at(shooter: Node3D, target: Node3D, height_bias: float = 0.5) -> Vector2:
	if shooter == null or target == null:
		return Vector2.RIGHT
	var a := View.to_plane(shooter.global_position)
	var b := View.to_plane(target.global_position)
	var tv := target as VoxelEntity
	if tv != null:
		b.y += tv.get_aabb_size().y * height_bias
	var d := b - a
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT


## Lead-the-target: where to aim a projectile of speed `speed` so it meets a
## target moving at `target_vel` (plane space). Solves the quadratic intercept;
## falls back to a straight shot when there is no solution.
static func lead_target(origin: Vector2, target_pos: Vector2, target_vel: Vector2,
		speed: float) -> Vector2:
	var to := target_pos - origin
	if speed <= 0.01:
		return to.normalized() if to.length_squared() > 0.0001 else Vector2.RIGHT
	var a := target_vel.length_squared() - speed * speed
	var b := 2.0 * to.dot(target_vel)
	var c := to.length_squared()
	var t := 0.0
	if absf(a) < 0.0001:
		if absf(b) > 0.0001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b + sq) / (2.0 * a)
			var t2 := (-b - sq) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = minf(t1, t2)
			else:
				t = maxf(t1, t2)
	if t <= 0.0:
		return to.normalized() if to.length_squared() > 0.0001 else Vector2.RIGHT
	var aim := to + target_vel * t
	return aim.normalized() if aim.length_squared() > 0.0001 else Vector2.RIGHT


## Ballistic launch direction for a gravity-affected shot (arrows, grenades).
## Returns the flat trajectory when both solutions exist, or a 45-degree lob
## when the target is out of range.
static func ballistic_aim(origin: Vector2, target_pos: Vector2, speed: float,
		gravity: float = Const.GRAVITY, high_arc: bool = false) -> Vector2:
	var d := target_pos - origin
	var g := maxf(0.01, gravity)
	var s2 := speed * speed
	var root := s2 * s2 - g * (g * d.x * d.x + 2.0 * d.y * s2)
	if root < 0.0:
		# Unreachable: throw as far as possible toward it.
		return Vector2(signf(d.x) if absf(d.x) > 0.01 else 1.0, 1.0).normalized()
	var sq := sqrt(root)
	var angle := atan2(s2 + (sq if high_arc else -sq), g * absf(d.x))
	var lateral := signf(d.x) if absf(d.x) > 0.01 else 1.0
	return Vector2(cos(angle) * lateral, sin(angle)).normalized()


## Plane-space velocity of an entity, for lead prediction.
static func plane_velocity_of(e: VoxelEntity) -> Vector2:
	if e == null:
		return Vector2.ZERO
	return Vector2(e.plane_velocity(), e.velocity.y)


# ================================================================== internals
static func _rect_circle_overlap(r: Rect2, c: Vector2, radius: float) -> bool:
	var nearest_pt := Vector2(
		clampf(c.x, r.position.x, r.position.x + r.size.x),
		clampf(c.y, r.position.y, r.position.y + r.size.y))
	return nearest_pt.distance_squared_to(c) <= radius * radius


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.00001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _angle_between(deg: float, a0: float, a1: float) -> bool:
	var span := a1 - a0
	if span >= 360.0:
		return true
	var d := fposmod(deg - a0, 360.0)
	return d <= fposmod(span, 360.0)
