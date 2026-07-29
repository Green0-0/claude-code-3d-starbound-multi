## Morph Ball — curl into a one-block sphere that fits down a mining shaft.
class_name TchMorphBall
extends TchBallForm


func on_activate() -> bool:
	ball_size = 0.72
	return _morph()


func on_update(delta: float) -> void:
	if not active or not is_morphed():
		return
	var p := player()
	if p == null:
		return
	# A ball rolls: it keeps a little momentum instead of stopping dead.
	var lat := p.plane_velocity()
	if absf(Input.get_axis(&"move_left", &"move_right")) < 0.2 and p.on_floor:
		p.set_plane_velocity(lerpf(lat, 0.0, delta * 2.2))


func modifier(stat: String) -> float:
	if not is_morphed():
		return 1.0
	if stat == "move_speed":
		return 1.15
	return super.modifier(stat)
