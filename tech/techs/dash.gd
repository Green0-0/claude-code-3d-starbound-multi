## Dash — a flat, gravity-free burst along the current plane.
##
## Guarded state: the player's `gravity_scale`. Restored in `on_deactivate`,
## which `Tech` guarantees runs on expiry, cancel, unequip and death.
class_name TchDash
extends TchBase

const SPEED_MULT := 3.4

var _dir: int = 1
var _saved_gravity: float = 1.0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or p.is_shifting():
		return false
	# Prefer the direction the player is actually pushing; fall back to facing.
	var axis := Input.get_axis(&"move_left", &"move_right")
	_dir = signi(int(sign(axis))) if absf(axis) > 0.2 else p.facing
	if _dir == 0:
		_dir = 1
	claim_view()
	_saved_gravity = p.gravity_scale
	p.gravity_scale = 0.0
	p.velocity.y = 0.0
	p.set_plane_velocity(p.move_speed * SPEED_MULT * float(_dir))
	p.facing = _dir
	p.iframes = maxf(p.iframes, duration * 0.6)
	_fx(&"tech_dash", 18)
	_sound(&"tech_dash")
	Events.screen_shake.emit(0.8, 0.12)
	return true


func on_update(_delta: float) -> void:
	var p := player()
	if p == null or not active:
		return
	# Hold the burst flat: the dash must not be eaten by gravity or friction.
	p.velocity.y = 0.0
	p.set_plane_velocity(p.move_speed * SPEED_MULT * float(_dir))


func on_deactivate() -> void:
	var p := player()
	if p != null:
		p.gravity_scale = _saved_gravity
		# Bleed out rather than stop dead, so the dash chains into a run.
		p.set_plane_velocity(p.move_speed * 1.1 * float(_dir))
	release_view()
