## Spike Ball — the morph ball, weaponised. Bounces off surfaces and shreds
## anything it rolls into.
class_name TchSpikeBall
extends TchBallForm

const CONTACT_DAMAGE := 14.0
const CONTACT_RADIUS := 1.3
const BOUNCE := 0.55

var _hit_cooldown: Dictionary = {}   ## entity instance id -> seconds


func on_activate() -> bool:
	ball_size = 0.78
	if not _morph():
		return false
	_hit_cooldown.clear()
	return true


func on_update(delta: float) -> void:
	if not active or not is_morphed():
		return
	var p := player()
	if p == null:
		return

	# Bounce: reverse a fraction of the impact speed off floors and ceilings.
	if p.on_floor and p.velocity.y <= 0.0 and absf(p.plane_velocity()) > 3.0:
		p.velocity.y = p.jump_speed * BOUNCE * 0.5

	for id: int in _hit_cooldown.keys():
		_hit_cooldown[id] = float(_hit_cooldown[id]) - delta
		if float(_hit_cooldown[id]) <= 0.0:
			_hit_cooldown.erase(id)

	var speed := absf(p.plane_velocity()) + absf(p.velocity.y)
	if speed < 2.0:
		return
	for e: VoxelEntity in Game.entities_in_radius(p.aabb_center(), CONTACT_RADIUS):
		if e == p or e.dead or e.faction == &"player":
			continue
		if manager != null and not bool(manager.call(&"node_in_reach", e)):
			continue
		var key := e.get_instance_id()
		if _hit_cooldown.has(key):
			continue
		_hit_cooldown[key] = 0.45
		e.apply_damage(CONTACT_DAMAGE * clampf(speed / 8.0, 0.5, 2.0), Const.ELEM_PHYSICAL, p)
		e.knockback(e.global_position - p.global_position + Vector3.UP * 0.4, 9.0)
		Events.spawn_particles.emit(&"tech_spike_hit", e.aabb_center(), 8)


func on_deactivate() -> void:
	_hit_cooldown.clear()
	_unmorph()


func modifier(stat: String) -> float:
	if not is_morphed():
		return 1.0
	match stat:
		"move_speed":
			return 1.25
		"defense":
			return 1.35
	return super.modifier(stat)
