## Blink Step — instant lateral teleport straight through thin walls.
##
## Everything is computed in plane space, so it works identically in all four
## views. The landing spot is the furthest legal one, walked back one block at a
## time, which means it never drops the player inside geometry.
class_name TchBlink
extends TchBase

const MAX_BLOCKS := 4


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or p.is_shifting():
		return false
	var axis := Input.get_axis(&"move_left", &"move_right")
	var dir := signi(int(sign(axis))) if absf(axis) > 0.2 else p.facing
	if dir == 0:
		dir = 1
	var step := View.plane_dir_to_world(Vector2(float(dir), 0.0))
	var size := p.get_aabb_size()
	var dest := Vector3.ZERO
	var found := false
	for n in range(MAX_BLOCKS, 0, -1):
		var candidate: Vector3 = p.global_position + step * float(n)
		if VoxelPhysics.aabb_is_free(candidate, size):
			dest = candidate
			found = true
			break
	if not found:
		Events.flip_blocked.emit("blink_blocked")
		return false

	var from := p.global_position
	Events.spawn_particles.emit(&"tech_blink_out", from + Vector3(0, size.y * 0.5, 0), 16)
	p.global_position = dest
	p.velocity.y = minf(p.velocity.y, 0.0)
	p.facing = dir
	p.iframes = maxf(p.iframes, 0.25)
	Events.spawn_particles.emit(&"tech_blink_in", dest + Vector3(0, size.y * 0.5, 0), 16)
	_sound(&"tech_blink")
	return true
