## Bubble Boost — a buoyant sphere. Rises through liquid, drifts in air, and
## carries its own air supply.
class_name TchBubbleBoost
extends TchBallForm

const LIFT := 12.0
const AIR_DRIFT := -2.2   ## terminal velocity while bubbled, in air

var _saved_liquid: bool = true


func on_activate() -> bool:
	ball_size = 0.8
	if not _morph():
		return false
	var p := player()
	if p != null:
		_saved_liquid = p.affected_by_liquid
	if manager != null:
		manager.set("oxygen_immune", true)
	return true


func on_update(delta: float) -> void:
	if not active or not is_morphed():
		return
	var p := player()
	if p == null:
		return
	if p.submersion > 0.25:
		p.velocity.y = minf(p.velocity.y + LIFT * delta, 6.0)
		Events.spawn_particles.emit(&"bubble", p.aabb_center(), 1)
	elif p.velocity.y < AIR_DRIFT:
		p.velocity.y = AIR_DRIFT
	p.fall_start_y = maxf(p.fall_start_y, p.global_position.y)


func on_deactivate() -> void:
	var p := player()
	if p != null:
		p.affected_by_liquid = _saved_liquid
		p.fall_start_y = p.global_position.y
	if manager != null:
		manager.set("oxygen_immune", false)
	_unmorph()


func modifier(stat: String) -> float:
	if not is_morphed():
		return 1.0
	match stat:
		"swim_speed":
			return 1.7
		"fall_damage":
			return 0.0
	return super.modifier(stat)
