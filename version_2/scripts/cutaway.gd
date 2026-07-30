class_name Cutaway
extends RefCounted

## ---------------------------------------------------------------------------
## Camera Obstruction System (Line-of-Sight Cylinder)
##
## Instead of a complex cross-section wedge, this system casts a cylindrical
## "drill" from the camera lens to the player. Any block intersecting this
## cylinder is considered "cut" (hidden).
##
## This perfectly handles cases like falling down a hole: the cylinder punches
## straight through the roof blocks above the player, exposing the hole all the
## way down, without unnecessarily gouging out the rest of the terrain.
##
## The volume is defined by:
##   1. A cylinder of `radius` blocks around the line from camera to target.
##   2. A small spherical cap at the target end (`target_padding`) to ensure
##      the player's immediate surroundings are visible even if pressed against
##      a wall.
## ---------------------------------------------------------------------------

var camera_position := Vector3.ZERO
var target_position := Vector3.ZERO
var radius := 1.5
var target_padding := 1.0 ## Extra clearance around the player
var enabled := true


func copy_from(o: Cutaway) -> void:
	camera_position = o.camera_position
	target_position = o.target_position
	radius = o.radius
	target_padding = o.target_padding
	enabled = o.enabled


## The predicate. Must stay bit-for-bit in step with voxel.gdshader::is_cut().
func is_cut(bx: int, by: int, bz: int) -> bool:
	if not enabled:
		return false
		
	var block_center := Vector3(bx + 0.5, by + 0.5, bz + 0.5)
	var cam_to_target := target_position - camera_position
	var cam_to_block := block_center - camera_position
	
	var length_sq := cam_to_target.length_squared()
	if length_sq < 0.001:
		# Camera and target are at the exact same position
		return block_center.distance_squared_to(camera_position) <= (radius + target_padding) * (radius + target_padding)
		
	# Project cam_to_block onto cam_to_target to find 't'
	# t = 0 is at the camera, t = 1 is at the target
	var t := cam_to_block.dot(cam_to_target) / length_sq
	
	# Find the closest point on the line segment to the block center
	var closest_point: Vector3
	if t <= 0.0:
		# Block is behind the camera
		closest_point = camera_position
	elif t >= 1.0:
		# Block is past the target (player)
		closest_point = target_position
	else:
		# Block is between camera and target
		closest_point = camera_position + cam_to_target * t
		
	var dist_sq := block_center.distance_squared_to(closest_point)
	
	# If the block is past the target, allow extra padding so the player isn't clipped
	var effective_radius := radius
	if t >= 1.0:
		effective_radius += target_padding
		
	return dist_sq <= effective_radius * effective_radius


## Returns the integer bounding box of the cut volume. 
## Used by the cap builder to scan only the relevant shell.
func get_int_bounds() -> AABB:
	var min_pos := camera_position.min(target_position) - Vector3(radius + target_padding, radius + target_padding, radius + target_padding)
	var max_pos := camera_position.max(target_position) + Vector3(radius + target_padding, radius + target_padding, radius + target_padding)
	
	var min_i := Vector3i(floor(min_pos.x), floor(min_pos.y), floor(min_pos.z))
	var max_i := Vector3i(ceil(max_pos.x), ceil(max_pos.y), ceil(max_pos.z))
	
	return AABB(min_i, max_i - min_i)


func push_to_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"cut_cam_pos", camera_position)
	RenderingServer.global_shader_parameter_set(&"cut_target_pos", target_position)
	RenderingServer.global_shader_parameter_set(&"cut_radius", float(radius))
	RenderingServer.global_shader_parameter_set(&"cut_target_padding", float(target_padding))
	RenderingServer.global_shader_parameter_set(&"cut_enabled", 1.0 if enabled else 0.0)
