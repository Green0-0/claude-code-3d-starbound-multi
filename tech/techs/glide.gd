## Glide — deploy a membrane. Terminal velocity collapses and you drift
## forward along the plane.
class_name TchGlide
extends TchBase

const FALL_SPEED := -3.0
const FORWARD := 0.55   ## fraction of move_speed added along the plane


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or p.on_floor or p.is_shifting():
		return false
	_fx(&"tech_glide", 8)
	_sound(&"tech_glide")
	return true


func on_update(delta: float) -> void:
	if not active:
		return
	var p := player()
	if p == null:
		return
	if p.on_floor:
		if manager != null:
			manager.call(&"deactivate", String(slot))
		return
	if p.velocity.y < FALL_SPEED:
		p.velocity.y = lerpf(p.velocity.y, FALL_SPEED, minf(1.0, delta * 9.0))
	# Constant forward drift makes gliding a traversal move, not just a brake.
	var lat := p.plane_velocity()
	var want := p.move_speed * FORWARD * float(p.facing)
	if absf(lat) < absf(want):
		p.set_plane_velocity(lerpf(lat, want, minf(1.0, delta * 3.0)))
	p.fall_start_y = p.global_position.y


func on_deactivate() -> void:
	var p := player()
	if p != null:
		p.fall_start_y = p.global_position.y


func modifier(stat: String) -> float:
	return 0.0 if (active and stat == "fall_damage") else 1.0
