## Wall Cling — passive. Press into a wall in mid-air and you stick to it,
## sliding slowly; jump off it to climb a shaft.
##
## Passive techs never "activate", so they pay their drain manually. This one
## only bills the player while they are actually hanging.
class_name TchWallCling
extends TchBase

const SLIDE_SPEED := -2.4
const KICK_LATERAL := 0.85

var clinging: bool = false
var _cling_time: float = 0.0


func on_update(delta: float) -> void:
	var p := player()
	if p == null or p.dead or p.is_shifting():
		clinging = false
		return

	var pushing := Input.get_axis(&"move_left", &"move_right")
	var want := p.on_wall and not p.on_floor and absf(pushing) > 0.2 \
		and signi(int(sign(pushing))) == p.facing and p.velocity.y < 1.0

	if want and manager != null and not bool(manager.call(&"spend", drain * delta)):
		want = false

	if want:
		if not clinging:
			_sound(&"tech_cling")
		clinging = true
		_cling_time += delta
		p.velocity.y = maxf(p.velocity.y, SLIDE_SPEED)
		p.fall_start_y = p.global_position.y
		if fmod(_cling_time, 0.25) < delta:
			Events.spawn_particles.emit(&"tech_cling_dust", p.global_position, 2)
		# Wall kick: jumping while clung throws you off the surface.
		if Input.is_action_just_pressed(&"jump"):
			p.velocity.y = p.jump_speed * 0.95
			p.set_plane_velocity(-p.move_speed * KICK_LATERAL * float(p.facing))
			p.facing = -p.facing
			clinging = false
			_sound(&"tech_wall_kick")
	else:
		clinging = false
		_cling_time = 0.0


func on_unequip() -> void:
	clinging = false


func modifier(stat: String) -> float:
	return 0.0 if (clinging and stat == "fall_damage") else 1.0
