## Sprint Burst — hold to run. Pure stat modifier, so it composes with anything
## the player agent does with `move_speed`.
class_name TchSprintBurst
extends TchBase

const SPEED_BONUS := 1.62

var _step_timer: float = 0.0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead:
		return false
	_step_timer = 0.0
	_fx(&"tech_sprint", 6)
	return true


func on_update(delta: float) -> void:
	if not active:
		return
	var p := player()
	if p == null:
		return
	# Sprinting while standing still is a waste of energy — drop out.
	if absf(p.plane_velocity()) < 0.5 and p.on_floor:
		if manager != null:
			manager.call(&"deactivate", String(slot))
		return
	_step_timer -= delta
	if _step_timer <= 0.0 and p.on_floor:
		_step_timer = 0.22
		Events.spawn_particles.emit(&"tech_sprint_dust", p.global_position, 3)


func modifier(stat: String) -> float:
	if not active:
		return 1.0
	match stat:
		"move_speed":
			return SPEED_BONUS
		"jump_speed":
			return 1.08
	return 1.0
