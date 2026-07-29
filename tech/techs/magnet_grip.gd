## Magnet Grip — passive ferrous attraction. Item drops fall toward you, and
## metal walls hold you fast enough to climb them.
##
## The drop search runs at 8 Hz, not per frame, and only inside the reachable
## slab, so the tech is cheap even in a room full of loot.
class_name TchMagnetGrip
extends TchBase

const PULL_RADIUS := 7.0
const PULL_FORCE := 16.0
const SCAN_INTERVAL := 0.125

## Blocks tagged with any of these count as ferrous for the wall grip.
const METAL_TAGS: Array[StringName] = [&"metal", &"ore"]

var _scan: float = 0.0
var gripping: bool = false


func on_update(delta: float) -> void:
	var p := player()
	if p == null or p.dead:
		gripping = false
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		_pull_drops(p)
	_metal_grip(p, delta)


func _pull_drops(p: VoxelEntity) -> void:
	for n: Node in p.get_tree().get_nodes_in_group(&"drops"):
		var e := n as Node3D
		if e == null:
			continue
		var to: Vector3 = p.aabb_center() - e.global_position
		var d := to.length()
		if d > PULL_RADIUS or d < 0.05:
			continue
		if manager != null and not bool(manager.call(&"node_in_reach", e)):
			continue
		var strength := PULL_FORCE * (1.0 - d / PULL_RADIUS)
		if e is VoxelEntity:
			(e as VoxelEntity).velocity += to.normalized() * strength * SCAN_INTERVAL * 6.0
		else:
			e.global_position = e.global_position.move_toward(p.aabb_center(), strength * SCAN_INTERVAL)


func _metal_grip(p: VoxelEntity, delta: float) -> void:
	gripping = false
	if p.on_floor or not p.on_wall or p.velocity.y > 1.0:
		return
	var probe := Const.floor_v(p.aabb_center()) + Vector3i(View.right() * p.facing)
	var bt := World.block_type_at(probe)
	var ferrous := false
	for t: StringName in METAL_TAGS:
		if bt.has_tag(t):
			ferrous = true
			break
	if not ferrous:
		return
	if manager != null and not bool(manager.call(&"spend", drain * delta)):
		return
	gripping = true
	# Full stop on metal, and you may climb it with the up key.
	p.velocity.y = p.move_speed * 0.55 * Input.get_axis(&"move_down", &"move_up")
	p.fall_start_y = p.global_position.y


func modifier(stat: String) -> float:
	if stat == "fall_damage" and gripping:
		return 0.0
	return 1.0
