## Distortion Sphere — a frictionless sphere that rolls at nearly double
## running speed and shrugs off knockback.
class_name TchDistortionSphere
extends TchBallForm

var _saved_kb_lock: float = 0.0


func on_activate() -> bool:
	ball_size = 0.66
	if not _morph():
		return false
	var p := player()
	if p != null:
		p.knockback_lock = 0.0
	Events.screen_shake.emit(0.5, 0.15)
	return true


func on_update(_delta: float) -> void:
	if not active or not is_morphed():
		return
	var p := player()
	if p == null:
		return
	# The sphere is knockback-immune: any lock imposed this frame is cleared.
	p.knockback_lock = 0.0
	if p.on_floor:
		Events.spawn_particles.emit(&"tech_distortion", p.global_position, 1)


func modifier(stat: String) -> float:
	if not is_morphed():
		return 1.0
	match stat:
		"move_speed":
			return 1.9
		"defense":
			return 1.15
	return super.modifier(stat)
