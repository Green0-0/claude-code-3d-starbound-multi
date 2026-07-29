## Autoloaded as `View`. The game's signature mechanic lives here.
##
## The world is a full 3D voxel grid, but the player only ever sees one
## *plane* of it at a time, rendered orthographically like a 2D side-scroller.
## Four planes exist (yaw 0/90/180/270). Flipping rotates which world axis is
## "depth" (into the screen) and which is "lateral" (screen-right); the player
## does not move at all during a flip, so a flip is always geometrically legal.
##
## Separately, the player can *shift* one layer deeper or shallower along the
## current depth axis — that is the traversal move, and it can be blocked.
extends Node

## Current settled plane, 0..3. During a flip this is already the destination.
var view: int = 0
## Integer depth coordinate of the plane the player occupies.
var layer: int = 0

var flipping: bool = false
var flip_from: int = 0
var flip_to: int = 0
var flip_dir: int = 1
var flip_t: float = 0.0        ## 0..1 eased progress, driven by the camera rig
var flip_duration: float = 0.45

var shifting: bool = false
var shift_t: float = 0.0
var shift_from_layer: int = 0
var shift_duration: float = 0.22

## Set false by cutscenes / menus / the star map.
var flips_enabled: bool = true


# ------------------------------------------------------------------ geometry
func forward() -> Vector3i:
	return Const.VIEW_FORWARD[view]


func right() -> Vector3i:
	return Const.VIEW_RIGHT[view]


func depth_axis() -> int:
	return Const.VIEW_DEPTH_AXIS[view]


func depth_sign() -> int:
	return Const.VIEW_DEPTH_SIGN[view]


func view_name() -> String:
	return Const.VIEW_NAMES[view]


## Yaw in radians for a given plane index. The camera rig lerps between these.
static func yaw_of(v: int) -> float:
	return deg_to_rad(90.0 * float(v))


## Interpolated yaw, valid mid-flip. Always takes the short way round in the
## direction the player asked for.
func current_yaw() -> float:
	if not flipping:
		return yaw_of(view)
	return yaw_of(flip_from) + deg_to_rad(90.0 * float(flip_dir)) * flip_t


func camera_basis() -> Basis:
	return Basis(Vector3.UP, current_yaw())


## World position -> (screen-right, up) coordinates in the current plane.
func to_plane(world_pos: Vector3, v: int = -1) -> Vector2:
	var vv := view if v < 0 else v
	return Vector2(Const.lateral_of(world_pos, vv), world_pos.y)


## (screen-right, up) + depth -> world position.
func to_world(plane_pos: Vector2, depth: float, v: int = -1) -> Vector3:
	var vv := view if v < 0 else v
	return Const.from_plane(plane_pos.x, plane_pos.y, depth, vv)


## Depth component of a world position under the current plane.
func depth_of(world_pos: Vector3) -> float:
	return world_pos.x if depth_axis() == 0 else world_pos.z


## Lateral component of a world position under the current plane.
func lateral_of(world_pos: Vector3) -> float:
	return Const.lateral_of(world_pos, view)


## Copy `src` but replace its depth component with `depth`.
func with_depth(src: Vector3, depth: float) -> Vector3:
	var out := src
	if depth_axis() == 0:
		out.x = depth
	else:
		out.z = depth
	return out


## Convert a screen-space direction (right/up) into a world direction.
func plane_dir_to_world(d: Vector2) -> Vector3:
	var r := right()
	return Vector3(d.x * r.x, d.y, d.x * r.z)


## The world-space unit vector pointing away from the camera.
func depth_step() -> Vector3i:
	var a := depth_axis()
	var s := depth_sign()
	return Vector3i(s, 0, 0) if a == 0 else Vector3i(0, 0, s)


# --------------------------------------------------------------------- flips
## `dir` is -1 (counter-clockwise) or +1 (clockwise).
func request_flip(dir: int) -> bool:
	if not flips_enabled:
		Events.flip_blocked.emit("disabled")
		return false
	if flipping or shifting:
		return false
	dir = -1 if dir < 0 else 1
	flip_from = view
	flip_to = wrapi(view + dir, 0, Const.VIEW_COUNT)
	flip_dir = dir
	flip_t = 0.0
	flipping = true
	# The destination plane is authoritative immediately so gameplay logic that
	# runs during the animation already reasons in the new frame.
	view = flip_to
	_recompute_layer()
	Events.view_flip_started.emit(flip_from, flip_to, dir)
	Events.play_sound.emit(&"flip", _player_pos())
	return true


func flip_to_view(target: int) -> bool:
	target = wrapi(target, 0, Const.VIEW_COUNT)
	if target == view:
		return false
	var delta := wrapi(target - view, 0, Const.VIEW_COUNT)
	return request_flip(1 if delta <= 2 else -1)


## Called every frame by the camera rig while `flipping` is true.
func advance_flip(delta: float) -> void:
	if not flipping:
		return
	flip_t = minf(1.0, flip_t + delta / maxf(0.0001, flip_duration))
	if flip_t >= 1.0:
		flipping = false
		flip_t = 0.0
		Events.view_flip_finished.emit(view)


func flip_eased() -> float:
	# Slight overshoot-free ease so the world "snaps" into the new plane.
	return ease(flip_t, 0.35)


# -------------------------------------------------------------------- layers
## Recompute the play layer from the player's actual position. Called after a
## flip (the depth axis changed) and whenever the player is teleported.
func _recompute_layer() -> void:
	var p := _player_pos()
	set_layer(floori(depth_of(p)), false)


func set_layer(l: int, emit: bool = true) -> void:
	if layer == l:
		return
	layer = l
	if emit:
		Events.layer_changed.emit(layer, view)


## Move one layer deeper (+1, away from camera) or shallower (-1).
## Returns false when the destination is occupied.
func request_shift(dir: int) -> bool:
	if flipping or shifting or not flips_enabled:
		return false
	dir = -1 if dir < 0 else 1
	var player := Game.player
	if player == null:
		return false
	var step := depth_step() * dir
	var dest: Vector3 = player.global_position + Vector3(step)
	if not VoxelPhysics.aabb_is_free(dest, player.get_aabb_size()):
		Events.flip_blocked.emit("occupied")
		Events.play_sound.emit(&"denied", dest)
		return false
	shift_from_layer = layer
	shifting = true
	shift_t = 0.0
	player.begin_layer_shift(dest)
	set_layer(layer + dir)
	Events.play_sound.emit(&"shift", dest)
	return true


func advance_shift(delta: float) -> void:
	if not shifting:
		return
	shift_t = minf(1.0, shift_t + delta / maxf(0.0001, shift_duration))
	if shift_t >= 1.0:
		shifting = false
		shift_t = 0.0


## True when `pos` is on the plane the player is standing in.
func is_play_layer(pos: Vector3i) -> bool:
	var d := pos.x if depth_axis() == 0 else pos.z
	return d == layer


## How many layers behind the play plane `pos` sits (negative = in front).
func layer_offset(pos: Vector3i) -> int:
	var d := pos.x if depth_axis() == 0 else pos.z
	return (d - layer) * depth_sign()


func _player_pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO


# ------------------------------------------------------------------ shaders
## Pushed to every voxel material each frame so the slab shader can fade out
## layers in front of the player and tint the ones behind.
func shader_params() -> Dictionary:
	return {
		"depth_axis": float(depth_axis()),
		"depth_sign": float(depth_sign()),
		"play_layer": float(layer),
		"slab_behind": float(Const.SLAB_BEHIND),
		"slab_front": float(Const.SLAB_FRONT),
		"flip_blend": flip_eased() if flipping else 0.0,
	}


func save_state() -> Dictionary:
	return {"view": view, "layer": layer}


func load_state(d: Dictionary) -> void:
	view = clampi(int(d.get("view", 0)), 0, 3)
	layer = int(d.get("layer", 0))
	flipping = false
	shifting = false
	Events.view_flip_finished.emit(view)
	Events.layer_changed.emit(layer, view)
