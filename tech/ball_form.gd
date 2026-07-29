## Shared machinery for the four "curl into a sphere" body techs (Morph Ball,
## Spike Ball, Distortion Sphere, Bubble Boost).
##
## The player's `box_size` is the one piece of shared state these techs mutate.
## Shrinking is always legal — entity positions are bottom-centre, so a smaller
## box can never intersect anything a larger one did not. *Growing* can, so
## `_unmorph` restores the box and then runs `VoxelPhysics.unstick`, which
## pushes the player out of whatever they grew into. That is why unmorphing can
## never fail and never wedges the player inside a wall.
class_name TchBallForm
extends TchBase

## Edge length of the ball form.
var ball_size: float = 0.72

var _saved_box: Vector3 = Vector3.ZERO
var _morphed: bool = false


func _morph() -> bool:
	var p := player()
	if p == null or p.dead or p.is_shifting() or _morphed:
		return false
	claim_view()
	_saved_box = p.box_size
	p.box_size = Vector3(ball_size, ball_size, ball_size)
	_morphed = true
	if manager != null:
		manager.set("morph_active", true)
	_fx(&"tech_morph", 12)
	_sound(&"tech_morph")
	return true


func _unmorph() -> void:
	var p := player()
	if _morphed and p != null:
		p.box_size = _saved_box if _saved_box.y > 0.0 else Vector3(0.7, 1.75, 0.7)
		p.global_position = VoxelPhysics.unstick(p.global_position, p.box_size)
		_fx(&"tech_morph", 8)
	_morphed = false
	if manager != null:
		manager.set("morph_active", false)
	release_view()


func is_morphed() -> bool:
	return _morphed


func on_activate() -> bool:
	return _morph()


func on_deactivate() -> void:
	_unmorph()


func on_unequip() -> void:
	_unmorph()


func modifier(stat: String) -> float:
	if not _morphed:
		return 1.0
	match stat:
		"jump_speed":
			return 0.0     ## a ball cannot jump
		"mining_speed":
			return 0.0     ## nor use tools
	return 1.0
