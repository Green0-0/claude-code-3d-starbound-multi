## Plane-space swept hitboxes.
##
## A hitbox is a *shape on screen* that lives for a few frames, is re-tested
## every physics tick as it sweeps, and remembers who it already hit so one
## swing can never double-dip. Melee weapons, whip cracks, explosion shells and
## beam sweeps all use it.
##
## Shapes: [constant SHAPE_ARC], [constant SHAPE_RECT], [constant SHAPE_CONE],
## [constant SHAPE_CAPSULE], [constant SHAPE_CIRCLE].
##
## The depth rule is part of the shape, not an afterthought:
##
## * `CbtDamage.LAYER_SAME`  — only the play layer. A monster one voxel behind
##   you is on screen and untouchable. Almost every melee weapon is this.
## * `CbtDamage.LAYER_ALL`   — depth is ignored. Piercing beams, shockwaves.
## * `CbtDamage.LAYER_RANGE` — `layer_min`..`layer_max` layers *away from the
##   camera*, relative to the attack origin. `{1, 1}` is the strange and lovely
##   case: hits **only** the layer behind you, and nothing in front of it.
##
## Typical use from a weapon:
##
## ```gdscript
## var hb := CbtHitbox.arc_box(origin, 2.6, -35.0, 55.0)
## hb.packet = CbtDamage.packet_from_weapon(stack, wielder)
## hb.owner_node = wielder
## hb.duration = 0.14
## # then every physics frame while active:
## hb.sweep(delta, new_origin)
## ```
class_name CbtHitbox
extends RefCounted

const SHAPE_ARC := 0
const SHAPE_RECT := 1
const SHAPE_CONE := 2
const SHAPE_CAPSULE := 3
const SHAPE_CIRCLE := 4

## Emitted for each *newly* hit entity, with the damage actually dealt.
signal hit(entity: VoxelEntity, damage: float)
## Emitted once when the box expires.
signal expired()

var shape: int = SHAPE_ARC
## Plane-space apex / centre, in (lateral, up).
var origin: Vector2 = Vector2.ZERO
## Facing, in plane space. Rotates arcs and cones.
var direction: Vector2 = Vector2.RIGHT
var radius: float = 2.0
var inner_radius: float = 0.0
## Arc sweep, degrees relative to `direction`.
var arc_from: float = -40.0
var arc_to: float = 40.0
## Rect half-extents, plane space.
var extents: Vector2 = Vector2(1.0, 1.0)
var cone_half_angle: float = 30.0
var capsule_end: Vector2 = Vector2.ZERO
var thickness: float = 0.4

## Damage packet handed to [CbtDamage.apply] for every entity struck.
var packet: Dictionary = {}
## Attacker. Excluded from its own hitbox and used for faction filtering.
var owner_node: Node = null
## Faction options merged into every query (see [CbtTargeting.default_opts]).
var opts: Dictionary = {}

var duration: float = 0.1
var elapsed: float = 0.0
var active: bool = true
## 0 = single hit per entity for the box's whole life (the default).
## > 0 = an entity may be hit again after this many seconds (multi-hit sweeps,
## flamethrowers, drills).
var rehit_interval: float = 0.0
var max_hits: int = 0            ## 0 = unlimited
var hit_count: int = 0

## entity instance id -> time it was last hit.
var _hit_set: Dictionary = {}


# ============================================================== constructors
## Arc swing: a fan from `from_deg` to `to_deg`, measured from `direction`.
static func arc_box(p_origin: Vector2, p_radius: float, from_deg: float,
		to_deg: float, inner: float = 0.0) -> CbtHitbox:
	var h := CbtHitbox.new()
	h.shape = SHAPE_ARC
	h.origin = p_origin
	h.radius = p_radius
	h.arc_from = from_deg
	h.arc_to = to_deg
	h.inner_radius = inner
	return h


## Axis-aligned rectangle centred on `p_origin`, `half` in each direction.
static func rect_box(p_origin: Vector2, half: Vector2) -> CbtHitbox:
	var h := CbtHitbox.new()
	h.shape = SHAPE_RECT
	h.origin = p_origin
	h.extents = half
	return h


## Cone with apex at `p_origin` opening `half_angle` either side of `dir`.
static func cone_box(p_origin: Vector2, dir: Vector2, length: float,
		half_angle: float) -> CbtHitbox:
	var h := CbtHitbox.new()
	h.shape = SHAPE_CONE
	h.origin = p_origin
	h.direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	h.radius = length
	h.cone_half_angle = half_angle
	return h


## Thick line segment — thrusts, whips, beams, laser sweeps.
static func capsule_box(a: Vector2, b: Vector2, p_thickness: float) -> CbtHitbox:
	var h := CbtHitbox.new()
	h.shape = SHAPE_CAPSULE
	h.origin = a
	h.capsule_end = b
	h.thickness = p_thickness
	return h


## Plain circle — explosions, auras, spin attacks.
static func circle_box(p_origin: Vector2, p_radius: float) -> CbtHitbox:
	var h := CbtHitbox.new()
	h.shape = SHAPE_CIRCLE
	h.origin = p_origin
	h.radius = p_radius
	return h


# =============================================================== layer rules
## Restrict to the attacker's own depth layer. This is the default and it is
## what makes stepping one layer back a real dodge.
func same_layer() -> CbtHitbox:
	packet["layer_rule"] = CbtDamage.LAYER_SAME
	return self


## Ignore depth entirely — the piercing-beam rule.
func all_layers() -> CbtHitbox:
	packet["layer_rule"] = CbtDamage.LAYER_ALL
	return self


## Hit layers `p_min`..`p_max` away from the origin layer, where **positive is
## further from the camera**. `layer_range(1, 1)` hits only the layer behind
## you; `layer_range(0, 3)` is a depth-charge bomb.
func layer_range(p_min: int, p_max: int, falloff: float = 1.0) -> CbtHitbox:
	packet["layer_rule"] = CbtDamage.LAYER_RANGE
	packet["layer_min"] = p_min
	packet["layer_max"] = p_max
	packet["layer_falloff"] = falloff
	return self


## Fix the layer this attack was launched from. Defaults to `View.layer` at
## resolve time; set it explicitly for attacks by monsters standing elsewhere.
func from_layer(l: int) -> CbtHitbox:
	packet["origin_layer"] = l
	return self


# ==================================================================== driving
## Advance the box by `delta` and resolve it against the world. Pass a new
## `p_origin` (and optionally `p_direction`) to make the box *sweep* — a moving
## hitbox tested every tick, which is how a swing covers the ground between
## frames without tunnelling past a fast monster.
##
## Returns the entities newly hit this tick.
func sweep(delta: float, p_origin: Vector2 = Vector2.INF,
		p_direction: Vector2 = Vector2.INF) -> Array[VoxelEntity]:
	var none: Array[VoxelEntity] = []
	if not active:
		return none
	if p_origin.x != INF:
		origin = p_origin
	if p_direction.x != INF and p_direction.length_squared() > 0.0001:
		direction = p_direction.normalized()
	elapsed += delta
	var struck := resolve()
	if elapsed >= duration:
		active = false
		expired.emit()
	return struck


## Test the box exactly once, right now, without ageing it. Returns the
## entities newly hit.
func resolve() -> Array[VoxelEntity]:
	var struck: Array[VoxelEntity] = []
	if max_hits > 0 and hit_count >= max_hits:
		return struck
	var query := _query_opts()
	var found := _candidates(query)
	var now := elapsed
	for e: VoxelEntity in found:
		var key := e.get_instance_id()
		if _hit_set.has(key):
			if rehit_interval <= 0.0:
				continue
			if now - float(_hit_set[key]) < rehit_interval:
				continue
		_hit_set[key] = now
		var dealt := CbtDamage.apply(e, _packet_for(e))
		if dealt <= 0.0:
			continue
		hit_count += 1
		struck.append(e)
		hit.emit(e, dealt)
		if max_hits > 0 and hit_count >= max_hits:
			break
	return struck


## Has this box already connected with `e`?
func has_hit(e: Node) -> bool:
	return e != null and _hit_set.has(e.get_instance_id())


## Forget every recorded hit — lets a combo re-use one box object.
func reset_hits() -> void:
	_hit_set.clear()
	hit_count = 0
	elapsed = 0.0
	active = true


## Every entity the box currently overlaps, ignoring the hit-set. Useful for
## previews, telegraphs and AI reasoning.
func peek() -> Array[VoxelEntity]:
	return _candidates(_query_opts())


# ================================================================= internals
func _query_opts() -> Dictionary:
	var q := CbtTargeting.default_opts()
	q["layer_rule"] = int(packet.get("layer_rule", CbtDamage.LAYER_SAME))
	q["layer_min"] = int(packet.get("layer_min", 0))
	q["layer_max"] = int(packet.get("layer_max", 0))
	q["origin_layer"] = int(packet.get("origin_layer", View.layer))
	q["exclude"] = owner_node
	if owner_node is VoxelEntity:
		q["hostile_to"] = owner_node
	for k: String in opts:
		q[k] = opts[k]
	return q


func _candidates(query: Dictionary) -> Array[VoxelEntity]:
	match shape:
		SHAPE_RECT:
			var r := Rect2(origin - extents, extents * 2.0)
			return CbtTargeting.in_rect(r, query)
		SHAPE_CONE:
			return CbtTargeting.in_cone(origin, direction, radius, cone_half_angle, query)
		SHAPE_CAPSULE:
			return CbtTargeting.in_capsule(origin, capsule_end, thickness, query)
		SHAPE_CIRCLE:
			return CbtTargeting.in_circle(origin, radius, query)
		_:
			var base := rad_to_deg(atan2(direction.y, direction.x))
			return CbtTargeting.in_arc(origin, radius, base + arc_from, base + arc_to,
				inner_radius, query)


func _packet_for(e: VoxelEntity) -> Dictionary:
	var p := packet.duplicate(true)
	if not p.has("origin_layer"):
		p["origin_layer"] = View.layer
	var d := CbtTargeting.plane_center(e) - origin
	if not p.has("knockback_dir"):
		var kd := d
		if kd.length_squared() < 0.0001:
			kd = direction
		p["knockback_dir"] = Vector2(signf(kd.x) if absf(kd.x) > 0.05 else direction.x, 0.3).normalized()
	# Backstab: struck from behind, i.e. the attacker is on the side the target
	# is *not* facing. Daggers live on this.
	var bs := float(p.get("backstab_mult", 0.0))
	if bs > 1.0 and absf(d.x) > 0.15 and signf(d.x) == signf(float(e.facing)):
		p["scale"] = float(p.get("scale", 1.0)) * bs
		p["tag"] = "backstab"
		p["crit_chance"] = clampf(float(p.get("crit_chance", 0.05)) + 0.25, 0.0, 1.0)
	return p
