## Screen <-> world projection for the orthographic plane camera.
##
## This is the one utility every other module should use for mouse aiming.
## Do not call `Camera3D.project_ray_*` yourself: the camera is orthographic,
## it orbits, and mid-flip it is not even looking along the depth axis. All of
## that is handled here.
##
## The "play plane" is the infinite vertical plane through the layer the player
## occupies, perpendicular to `View.depth_axis()`. Projecting the mouse onto it
## gives the world point the cursor is over, which is what mining, building,
## shooting and targeting all want.
##
## [codeblock]
## var aim: Vector3 = CamProject.mouse_to_plane_point()           # player's layer
## var aim2: Vector3 = CamProject.mouse_to_plane_point(12.0)      # explicit depth
## var pos: Vector2 = CamProject.world_to_screen(monster.global_position)
## var dir: Vector3 = CamProject.aim_direction_from(muzzle)       # unit, in-plane
## [/codeblock]
##
## Pure static class — never instantiate it.
class_name CamProject
extends RefCounted

## Below this |dot| the view ray is too parallel to the play plane to give a
## meaningful hit, which happens during the first/last moments of a flip.
const PARALLEL_EPSILON := 0.25


# ------------------------------------------------------------------- camera
## The camera the player is actually looking through, or null before boot.
## Prefers the rig registered in `Game`, falls back to the viewport's camera.
static func active_camera() -> Camera3D:
	var rig: Node = Game.camera_rig
	if rig != null and is_instance_valid(rig):
		var c: Variant = rig.get(&"camera")
		if c is Camera3D and is_instance_valid(c) and (c as Camera3D).is_inside_tree():
			return c as Camera3D
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_camera_3d()


## Size of the viewport the camera renders into, in pixels.
static func viewport_size() -> Vector2:
	var cam := active_camera()
	if cam == null:
		var loop := Engine.get_main_loop() as SceneTree
		if loop == null or loop.root == null:
			return Vector2(1280, 720)
		return loop.root.get_visible_rect().size
	return cam.get_viewport().get_visible_rect().size


## Current mouse position in viewport pixels (already unstretched).
static func mouse_position() -> Vector2:
	var cam := active_camera()
	if cam == null:
		var loop := Engine.get_main_loop() as SceneTree
		if loop == null or loop.root == null:
			return Vector2.ZERO
		return loop.root.get_mouse_position()
	return cam.get_viewport().get_mouse_position()


# ------------------------------------------------------------ screen -> world
## Project the mouse onto a vertical plane at `depth` along the current depth
## axis and return the world point.
##
## `depth` is a coordinate on `View.depth_axis()` (world X for views 1/3, world
## Z for views 0/2) — i.e. exactly what `View.depth_of()` returns. Pass nothing
## (or `NAN`) to use the plane the player is standing in, which is what you
## want in virtually every case.
##
## Always returns a finite point: if there is no camera yet, or the view ray is
## degenerate (which happens for a few frames mid-flip), it degrades to the
## player's own position on that plane rather than returning garbage.
static func mouse_to_plane_point(depth: float = NAN) -> Vector3:
	return screen_to_plane_point(mouse_position(), depth)


## As `mouse_to_plane_point`, for an arbitrary viewport pixel.
static func screen_to_plane_point(screen_pos: Vector2, depth: float = NAN) -> Vector3:
	var d := resolve_depth(depth)
	var cam := active_camera()
	if cam == null:
		return _fallback_point(d)
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	# A point known to lie on the target plane; only its depth component matters.
	var on_plane := View.with_depth(origin, d)
	var n := Vector3(1.0, 0.0, 0.0) if View.depth_axis() == 0 else Vector3(0.0, 0.0, 1.0)
	var denom := dir.dot(n)
	if absf(denom) < PARALLEL_EPSILON:
		# Mid-flip: `View.view` is already the destination but the camera is
		# still swinging towards it. Fall back to the plane the camera really
		# faces, through the same point, so aiming stays continuous.
		n = -cam.global_basis.z
		denom = dir.dot(n)
		if absf(denom) < 0.001:
			return on_plane
	var t := (on_plane - origin).dot(n) / denom
	return origin + dir * t


## The mouse position in plane space: `Vector2(lateral, up)`, matching
## `View.to_plane()`. Handy for 2D-style aiming maths.
static func mouse_to_plane_vector(depth: float = NAN) -> Vector2:
	return View.to_plane(mouse_to_plane_point(depth))


## Unit world direction from `origin` towards the cursor, flattened into the
## play plane (its depth component is exactly zero). Returns `View.right()` as
## a last resort if the cursor sits on top of `origin`.
static func aim_direction_from(origin: Vector3) -> Vector3:
	var target := mouse_to_plane_point(View.depth_of(origin))
	var d := View.with_depth(target - origin, 0.0)
	if d.length_squared() < 0.000001:
		return Vector3(View.right())
	return d.normalized()


## Signed angle, in radians, from screen-right to the cursor as seen from
## `origin`. 0 = right, PI/2 = up. View-independent, so weapon sprites and
## projectile spawns can use it directly.
static func aim_angle_from(origin: Vector3) -> float:
	var d := aim_direction_from(origin)
	return atan2(d.y, Const.lateral_of(d, View.view))


# ------------------------------------------------------------ world -> screen
## Viewport-pixel position of a world point.
##
## The camera is orthographic, so this stays linear and well-behaved even for
## points beside or behind the camera; use `is_point_visible()` if you need to
## know whether it is actually on screen.
static func world_to_screen(p: Vector3) -> Vector2:
	var cam := active_camera()
	if cam == null:
		return Vector2.ZERO
	return cam.unproject_position(p)


## True when `p` projects inside the viewport (expanded by `margin` pixels) and
## is not behind the near plane.
static func is_point_visible(p: Vector3, margin: float = 0.0) -> bool:
	var cam := active_camera()
	if cam == null:
		return false
	if cam.is_position_behind(p):
		return false
	var s := cam.unproject_position(p)
	var vp := cam.get_viewport().get_visible_rect().size
	return s.x >= -margin and s.y >= -margin and s.x <= vp.x + margin and s.y <= vp.y + margin


## How many world units one screen pixel covers. Constant across the frame
## because the projection is orthographic — use it to size world-space UI.
static func world_units_per_pixel() -> float:
	var cam := active_camera()
	if cam == null:
		return 1.0
	var h := cam.get_viewport().get_visible_rect().size.y
	if h <= 0.0:
		return 1.0
	return cam.size / h


# ------------------------------------------------------------------ internals
## Resolve a `depth` argument: `NAN` means "the plane the player is in".
static func resolve_depth(depth: float) -> float:
	if not is_nan(depth):
		return depth
	if Game.player != null and is_instance_valid(Game.player):
		return View.depth_of(Game.player.global_position)
	return float(View.layer) + 0.5


static func _fallback_point(depth: float) -> Vector3:
	if Game.player != null and is_instance_valid(Game.player):
		return View.with_depth(Game.player.global_position, depth)
	return View.to_world(Vector2.ZERO, depth)
