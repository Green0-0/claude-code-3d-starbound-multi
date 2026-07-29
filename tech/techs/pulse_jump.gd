## Pulse Jump — unlimited but weak mid-air pulses. Where Double Jump gives you
## a fixed budget, this one is capped only by the energy bar.
class_name TchPulseJump
extends TchBase

const PULSE := 0.58     ## fraction of jump_speed added per pulse
const CEILING := 17.0   ## pulses stop helping past this rise speed


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or p.is_shifting():
		return false
	if p.on_floor:
		p.jump()
		return false
	if p.velocity.y > CEILING:
		return false
	p.velocity.y = minf(CEILING, maxf(p.velocity.y, 0.0) + p.jump_speed * PULSE)
	p.falling = true
	p.fall_start_y = p.global_position.y
	_fx(&"tech_pulse", 10)
	_sound(&"tech_pulse")
	return true


func modifier(stat: String) -> float:
	return 0.7 if stat == "fall_damage" else 1.0
