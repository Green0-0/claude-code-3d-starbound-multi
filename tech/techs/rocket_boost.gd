## Rocket Boost — sustained vertical thrust while the tech key is held.
class_name TchRocketBoost
extends TchBase

const THRUST := 46.0
const MAX_RISE := 15.0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or p.is_shifting():
		return false
	p.velocity.y = maxf(p.velocity.y, 2.0)
	p.falling = true
	p.fall_start_y = p.global_position.y
	_sound(&"tech_rocket")
	return true


func on_update(delta: float) -> void:
	if not active:
		return
	var p := player()
	if p == null:
		return
	if p.on_ceiling:
		p.velocity.y = minf(p.velocity.y, 0.0)
		return
	p.velocity.y = minf(p.velocity.y + THRUST * delta, MAX_RISE)
	# Falling never starts from the boosted apex — this is the whole point.
	p.fall_start_y = p.global_position.y
	Events.spawn_particles.emit(&"tech_rocket_exhaust", p.global_position, 2)


func on_deactivate() -> void:
	var p := player()
	if p != null:
		p.fall_start_y = p.global_position.y


func modifier(stat: String) -> float:
	return 0.0 if (active and stat == "fall_damage") else 1.0
