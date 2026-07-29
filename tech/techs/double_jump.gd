## Double Jump — one extra mid-air kick, refunded when you touch the ground.
##
## Touches nothing outside the player's own velocity, so it needs no view claim.
class_name TchDoubleJump
extends TchBase

## How many extra jumps per airborne stretch. Upgrades may raise this.
var extra_jumps: int = 1

var _used: int = 0
var _was_on_floor: bool = true


func on_equip() -> void:
	_used = 0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or p.is_shifting():
		return false
	if p.on_floor:
		# On the ground a plain jump is free — refuse rather than charge for it.
		p.jump()
		return false
	if _used >= extra_jumps:
		return false
	_used += 1
	p.velocity.y = p.jump_speed * 0.94
	p.falling = true
	p.fall_start_y = p.global_position.y
	_fx(&"tech_double_jump", 14)
	_sound(&"tech_jump")
	return true


func on_update(_delta: float) -> void:
	var p := player()
	if p == null:
		return
	if p.on_floor or p.submersion > 0.6 or p.on_wall:
		_used = 0
	_was_on_floor = p.on_floor


func modifier(stat: String) -> float:
	# Landing from a tech-assisted hop hurts a little less.
	return 0.85 if stat == "fall_damage" else 1.0


func save_state() -> Dictionary:
	return {"extra": extra_jumps}


func load_state(d: Dictionary) -> void:
	extra_jumps = maxi(1, int(d.get("extra", 1)))
