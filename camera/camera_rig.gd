## The orthographic plane camera: follow, flip presentation, effect composition.
##
## [b]Geometry.[/b] The rig node sits at the *focus point* and carries the view
## basis (`Basis(Vector3.UP, yaw)`); the `Camera3D` child hangs behind it at
## `+Z * orbit_radius` looking horizontally down `-Z`. So the camera orbits the
## focus on a fixed radius and `View.current_yaw()` is the only thing that
## decides which of the four planes we are looking at. Because the projection is
## orthographic, the radius does not affect framing at all — it only decides
## what falls inside near/far. Zoom is `Camera3D.size`.
##
## [b]Follow.[/b] All follow maths happens in plane space (`lateral`, `up`) so
## it behaves identically in all four views. A dead-zone box lets the player
## move without dragging the camera, an asymmetric look-ahead leads in the
## direction of travel (extends quickly, retracts lazily), the vertical spring
## stiffens while falling, and everything is integrated with an implicit
## critically damped spring so it is frame-rate independent and never
## overshoots. A teleport (or a planet-wrap) snaps instead of sweeping.
##
## [b]Flips.[/b] See `_capture_pin()` / `_pinned_origin()`. During a flip the
## follow springs are bypassed entirely and the rig is *solved backwards* from
## the requirement "the player must not move on screen".
class_name CamRig
extends Node3D

# --------------------------------------------------------------------- tuning
@export_group("Framing")
## Vertical extent of the view, in blocks. This is the master zoom control.
@export var ortho_size := 26.0
## How far behind the focus the camera sits. Orthographic, so this is only
## about clipping and depth of field, never about apparent size.
@export var orbit_radius := 44.0
## Focus this far above the middle of the player's box.
@export var eye_lift := 0.25
## Downward tilt of the camera, in degrees.
##
## A perfectly horizontal side view shows nothing but flat front faces, so the
## world reads as coloured silhouettes with no way to tell a near block from a
## far one. Tilting a little — the Don't Starve trick — exposes the +Y face of
## every voxel, which is what makes the grid legible as a solid 3D world while
## still playing as a 2D platformer. Keep it small: past ~25 degrees the
## vertical platforming read starts to suffer.
@export_range(0.0, 40.0, 0.5) var camera_pitch := 17.0
@export var near_plane := 0.05
@export var far_plane := 220.0

@export_group("Follow")
## Half-extents of the dead zone in plane units (blocks): the player can move
## this far from the focus before the camera starts tracking at all.
@export var dead_zone := Vector2(1.7, 2.4)
## The dead zone shrinks by this factor below the focus while falling, so the
## ground comes into view early.
@export var dead_zone_fall_scale := 0.35
## Spring frequency (rad/s) for lateral / vertical follow.
@export var follow_stiffness := Vector2(8.0, 6.5)
## Vertical spring frequency used once the player is falling fast.
@export var fall_stiffness := 12.0
## Downward speed (blocks/s) at which the fast vertical catch-up kicks in.
@export var fall_speed_threshold := 7.0
## Seconds of lateral velocity the camera leads by.
@export var look_ahead := 0.40
## Hard cap on the lead, in blocks.
@export var look_ahead_max := 5.5
## Rate the lead extends at (per second). Fast: the camera commits early.
@export var look_ahead_attack := 4.0
## Rate the lead retracts at. Slow and asymmetric: stopping or turning around
## must not yank the world sideways.
@export var look_ahead_release := 1.2
## Extra downward lead at terminal velocity, in blocks.
@export var fall_lead := 4.0
## A single-frame player movement bigger than this is a teleport, not motion.
@export var teleport_distance := 7.0

@export_group("Flip")
## Extra orbit radius at the midpoint of a flip (the dolly-out).
@export var flip_dolly := 7.0
## Fraction of `ortho_size` added at the midpoint of a flip (the pull-back).
@export var flip_zoom := 0.11
## 0 = pure smoothstep, 1 = the engine's `View.flip_eased()` curve. Both land
## with zero angular velocity, so the flip always settles firmly, never bounces.
@export var flip_curve_blend := 0.35
## Trauma emitted once, near the end of a flip, as the world locks in.
@export var flip_shake := 0.10
## Inward ortho punch on the frame the flip settles.
@export var flip_settle_punch := 0.035

const MIN_SIZE := 6.0
const MAX_SIZE := 96.0
## `_pin` is clamped to this so a pathological state can never throw the player
## off screen during a rotation.
const PIN_LIMIT := 0.86

# ---------------------------------------------------------------------- nodes
## The live `Camera3D`. Other modules should go through `CamProject` instead of
## touching this, but it is public because `Game.camera_rig.camera` is a very
## natural thing to reach for.
var camera: Camera3D = null
var effects: CamEffects = null
var depth_of_field: CamDepthOfField = null
var flip_transition: CamFlipTransition = null
var plane_indicator: CamPlaneIndicator = null

# ---------------------------------------------------------------------- state
var _focus_lat := 0.0
var _focus_up := 0.0
var _focus_depth := 0.0
var _vel_lat := 0.0
var _vel_up := 0.0
var _lead := 0.0
var _vlead := 0.0

var _yaw := 0.0
var _flip_active := false
var _flip_shaken := false
var _flip_bulge := 0.0
var _flip_dolly_now := 0.0
## Player position in camera space at flip start, normalised by the half-extents
## of the view. Held constant for the whole rotation == pinned on screen.
var _pin := Vector2.ZERO

var _last_player_pos := Vector3.ZERO
var _has_last := false
var _seeded := false

## Multiplier on the follow spring frequencies, driven by the user's
## `gameplay/camera_smoothing` setting. 1.0 == the tuned defaults.
var _smooth_scale := 1.0
var _settings: Node = null
var _settings_attempts := 0


func _ready() -> void:
	# After `main.gd` (priority 0) so `View.flip_t` is already this frame's value.
	process_priority = 10
	_build_children()
	_yaw = View.current_yaw()
	Events.view_flip_started.connect(_on_flip_started)
	Events.view_flip_finished.connect(_on_flip_finished)
	Events.player_spawned.connect(func(_p: Node) -> void: snap())
	Events.player_respawned.connect(snap)
	Events.travel_finished.connect(func(_id: String) -> void: snap())
	call_deferred(&"snap")
	call_deferred(&"_bind_settings")


# --------------------------------------------------------------- user settings
## Optional bridge to `/root/Settings` (`persistence/settings.gd`), which the
## save agent parents to the root at boot. Entirely duck-typed and guarded: if
## that module is absent or renamed, the camera just keeps its own defaults.
##
## `video/screen_shake`  -> `CamSettings.screen_shake_scale`
## `video/flash_effects` -> `CamSettings.flip_transition_enabled`
## `gameplay/camera_smoothing` -> follow spring frequencies
func _bind_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		return
	_settings_attempts += 1
	var s := get_node_or_null(^"/root/Settings")
	if s == null or not s.has_method(&"get_value"):
		if _settings_attempts < 5 and is_inside_tree():
			get_tree().create_timer(0.75).timeout.connect(_bind_settings, CONNECT_ONE_SHOT)
		return
	_settings = s
	if s.has_signal(&"changed") and not s.is_connected(&"changed", _on_setting_changed):
		s.connect(&"changed", _on_setting_changed)
	_pull_setting("video", "screen_shake")
	_pull_setting("video", "flash_effects")
	_pull_setting("gameplay", "camera_smoothing")


func _pull_setting(section: String, key: String) -> void:
	if _settings == null:
		return
	var v: Variant = _settings.call(&"get_value", section, key, null)
	if v != null:
		_on_setting_changed(section, key, v)


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "video":
		if key == "screen_shake":
			CamSettings.screen_shake_scale = clampf(float(value), 0.0, 2.0)
		elif key == "flash_effects":
			CamSettings.flip_transition_enabled = bool(value)
	elif section == "gameplay" and key == "camera_smoothing":
		# 0 = rigid and snappy, 1 = loose and floaty.
		_smooth_scale = lerpf(2.0, 0.7, clampf(float(value), 0.0, 1.0))


func _build_children() -> void:
	camera = get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	camera.cull_mask = 0xFFFFF

	effects = get_node_or_null(^"Effects") as CamEffects
	if effects == null:
		effects = CamEffects.new()
		effects.name = "Effects"
		add_child(effects)

	depth_of_field = get_node_or_null(^"DepthOfField") as CamDepthOfField
	if depth_of_field == null:
		depth_of_field = CamDepthOfField.new()
		depth_of_field.name = "DepthOfField"
		add_child(depth_of_field)

	flip_transition = get_node_or_null(^"FlipTransition") as CamFlipTransition
	if flip_transition == null:
		flip_transition = CamFlipTransition.new()
		flip_transition.name = "FlipTransition"
		add_child(flip_transition)

	plane_indicator = get_node_or_null(^"PlaneIndicator") as CamPlaneIndicator
	if plane_indicator == null:
		plane_indicator = CamPlaneIndicator.new()
		plane_indicator.name = "PlaneIndicator"
		add_child(plane_indicator)


# ---------------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if camera == null:
		return
	delta = minf(delta, 0.1)

	_update_flip_presentation(delta)

	var size := ortho_size * (1.0 + _flip_bulge)
	if effects != null:
		size *= effects.size_multiplier()
	size = clampf(size, MIN_SIZE, MAX_SIZE)

	var origin: Vector3
	if _flip_active:
		origin = _pinned_origin(size)
	else:
		origin = _follow(delta, size)

	_write_transform(origin, size)


# ------------------------------------------------------------------- following
func _follow(delta: float, size: float) -> Vector3:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return _focus_world()
	if not _seeded:
		_seed_from_player(player)

	var pw := player.global_position
	if _has_last and pw.distance_to(_last_player_pos) > teleport_distance:
		# Teleport, respawn, or a wrap across the planet seam: snap, never sweep.
		_seed_from_player(player)
		_last_player_pos = pw
		return _focus_world()
	_last_player_pos = pw
	_has_last = true

	var pl := View.to_plane(pw)
	pl.y += player.box_size.y * 0.5 + eye_lift

	# --- asymmetric look-ahead ------------------------------------------
	var v_lat := Const.lateral_of(player.velocity, View.view)
	var lead_target := clampf(v_lat * look_ahead, -look_ahead_max, look_ahead_max)
	var extending := absf(lead_target) >= absf(_lead) and signf(lead_target) == signf(_lead)
	var lead_rate := look_ahead_attack if extending or is_zero_approx(_lead) else look_ahead_release
	_lead = lerpf(_lead, lead_target, 1.0 - exp(-lead_rate * delta))

	# --- vertical lead while falling ------------------------------------
	var v_y := player.velocity.y
	var vlead_target := 0.0
	if v_y < -fall_speed_threshold:
		var f := clampf((-v_y - fall_speed_threshold) / Const.TERMINAL_VELOCITY, 0.0, 1.0)
		vlead_target = -fall_lead * f
	_vlead = lerpf(_vlead, vlead_target, 1.0 - exp(-5.0 * delta))

	var target_lat := pl.x + _lead
	var target_up := pl.y + _vlead

	# --- dead zone -------------------------------------------------------
	var goal_lat := _focus_lat
	var d_lat := target_lat - _focus_lat
	if absf(d_lat) > dead_zone.x:
		goal_lat = target_lat - signf(d_lat) * dead_zone.x

	var falling := v_y < -fall_speed_threshold
	var dz_up := dead_zone.y
	var d_up := target_up - _focus_up
	if d_up < 0.0 and falling:
		dz_up *= dead_zone_fall_scale
	var goal_up := _focus_up
	if absf(d_up) > dz_up:
		goal_up = target_up - signf(d_up) * dz_up

	# --- critically damped springs ---------------------------------------
	var omega_up := (fall_stiffness if falling else follow_stiffness.y) * _smooth_scale
	var s_lat := _spring(_focus_lat, _vel_lat, goal_lat, follow_stiffness.x * _smooth_scale, delta)
	_focus_lat = s_lat.x
	_vel_lat = s_lat.y
	var s_up := _spring(_focus_up, _vel_up, goal_up, omega_up, delta)
	_focus_up = s_up.x
	_vel_up = s_up.y

	# --- world bounds ----------------------------------------------------
	var half_h := size * 0.5
	var lo := half_h
	var hi := float(Const.WORLD_HEIGHT) - half_h
	if lo < hi:
		var clamped := clampf(_focus_up, lo, hi)
		if not is_equal_approx(clamped, _focus_up):
			_focus_up = clamped
			_vel_up = 0.0

	# --- depth: ride the player's layer ----------------------------------
	_focus_depth = lerpf(_focus_depth, View.depth_of(pw), 1.0 - exp(-9.0 * delta))

	return _focus_world()


func _focus_world() -> Vector3:
	return View.to_world(Vector2(_focus_lat, _focus_up), _focus_depth)


func _seed_from_player(player: VoxelEntity) -> void:
	var pl := View.to_plane(player.global_position)
	_focus_lat = pl.x
	_focus_up = pl.y + player.box_size.y * 0.5 + eye_lift
	_focus_depth = View.depth_of(player.global_position)
	_vel_lat = 0.0
	_vel_up = 0.0
	_lead = 0.0
	_vlead = 0.0
	_seeded = true


## Re-derive the plane-space follow state from an absolute world focus point.
## Used at the end of a flip, where the whole plane basis has just changed.
func _seed_from_world(origin: Vector3) -> void:
	_focus_lat = Const.lateral_of(origin, View.view)
	_focus_up = origin.y
	_focus_depth = View.depth_of(origin)
	_vel_lat = 0.0
	_vel_up = 0.0
	_lead = 0.0
	_vlead = 0.0
	_seeded = true


# ------------------------------------------------------------------ flip anim
func _update_flip_presentation(delta: float) -> void:
	if View.flipping:
		if not _flip_active:
			# Missed the signal (loaded save, scripted flip): pick it up anyway.
			_begin_flip()
		var t := View.flip_t
		# `View.flip_eased()` is an ease-out; smoothstep is symmetric. Blending
		# them gives an eager start with a firm, zero-velocity settle. Neither
		# curve overshoots, so a flip can never be mistaken for player input.
		var e := lerpf(smoothstep(0.0, 1.0, t), View.flip_eased(), clampf(flip_curve_blend, 0.0, 1.0))
		_yaw = View.yaw_of(View.flip_from) + deg_to_rad(90.0 * float(View.flip_dir)) * e
		var bulge := sin(PI * t)
		if CamSettings.reduce_motion:
			bulge = 0.0
		_flip_bulge = flip_zoom * bulge
		_flip_dolly_now = flip_dolly * bulge
		if not _flip_shaken and t > 0.86:
			_flip_shaken = true
			Events.screen_shake.emit(flip_shake, 0.18)
	else:
		if _flip_active:
			# Belt and braces: a flip that ended without us seeing the signal
			# must never leave the rig stuck in pinned mode.
			_on_flip_finished(View.view)
		_yaw = View.yaw_of(View.view)
		_flip_bulge = move_toward(_flip_bulge, 0.0, 0.6 * delta)
		_flip_dolly_now = move_toward(_flip_dolly_now, 0.0, 40.0 * delta)


func _on_flip_started(_from: int, _to: int, dir: int) -> void:
	_begin_flip()
	if flip_transition != null:
		flip_transition.play(dir)


func _begin_flip() -> void:
	_flip_active = true
	_flip_shaken = false
	_capture_pin()


## Record where the player currently sits in camera space, normalised by the
## half-extents of the view volume.
##
## This is the whole trick behind "the world turned, not me": the player's
## screen position is `(_pin.x, _pin.y)` in normalised device coordinates, and
## `_pinned_origin()` re-solves the focus point every frame so that value stays
## exactly constant while the yaw sweeps 90 degrees and the ortho size bulges.
## The player is therefore mathematically nailed to the same pixel, and the only
## thing the eye can attribute the motion to is the world rotating around them.
func _capture_pin() -> void:
	_pin = Vector2.ZERO
	var player := Game.player
	if player == null or not is_instance_valid(player) or camera == null:
		return
	var half_h := maxf(0.001, camera.size * 0.5)
	var half_w := maxf(0.001, half_h * _aspect())
	var rel := _player_focus(player) - global_position
	_pin = Vector2(
		rel.dot(global_basis.x) / half_w,
		rel.y / half_h)
	_pin.x = clampf(_pin.x, -PIN_LIMIT, PIN_LIMIT)
	_pin.y = clampf(_pin.y, -PIN_LIMIT, PIN_LIMIT)


## Solve the focus point that keeps the player at `_pin` for the current yaw and
## ortho size. Note the offset is rebuilt from `size` every frame, so the
## mid-flip zoom bulge cannot slide the player around either.
func _pinned_origin(size: float) -> Vector3:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return _focus_world()
	var half_h := size * 0.5
	var half_w := half_h * _aspect()
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	return _player_focus(player) - right * (_pin.x * half_w) - Vector3(0.0, _pin.y * half_h, 0.0)


func _player_focus(player: VoxelEntity) -> Vector3:
	var p := player.global_position
	p.y += player.box_size.y * 0.5 + eye_lift
	return p


func _on_flip_finished(_view: int) -> void:
	if not _flip_active:
		# `View.load_state()` fires this without a flip ever running.
		snap()
		return
	_flip_active = false
	_flip_shaken = false
	_yaw = View.yaw_of(View.view)
	_flip_bulge = 0.0
	_flip_dolly_now = 0.0
	# Hand the pinned framing straight to the follow springs so there is no
	# jump on the hand-over frame; the dead zone absorbs the residual offset and
	# the spring walks the rest of it back with no bounce.
	_seed_from_world(_pinned_origin(clampf(ortho_size, MIN_SIZE, MAX_SIZE)))
	if Game.player != null and is_instance_valid(Game.player):
		_last_player_pos = Game.player.global_position
		_has_last = true
	if effects != null:
		effects.zoom_punch(-flip_settle_punch, 0.30)


# ------------------------------------------------------------------- transform
func _write_transform(origin: Vector3, size: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), origin)
	camera.size = size
	camera.near = near_plane
	camera.far = far_plane
	var off := Vector2.ZERO
	var roll := 0.0
	var extra_z := 0.0
	if effects != null:
		off = effects.offset() * (size * 0.5)
		roll = effects.roll()
		extra_z = effects.depth_offset()
	# Pitch the camera down about its own X, then push it back along its new
	# view axis so the rig origin still lands dead centre of frame. Roll is
	# applied after, about the view axis, so shake never tilts the horizon oddly.
	var pitch := deg_to_rad(camera_pitch)
	var b := Basis(Vector3.RIGHT, -pitch)
	if not is_zero_approx(roll):
		b = b * Basis(Vector3.BACK, roll)
	var dist := orbit_radius + _flip_dolly_now + extra_z
	camera.transform = Transform3D(b, b.z * dist + b.x * off.x + b.y * off.y)


func _aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var s := vp.get_visible_rect().size
	if s.y <= 0.0:
		return 16.0 / 9.0
	return s.x / s.y


# ---------------------------------------------------------------- public API
## Jump the camera to the ideal framing for wherever the player is right now,
## with no smoothing. Call after teleports, respawns or planet travel — it is
## already wired to those signals, so you rarely need to.
func snap() -> void:
	if camera == null:
		return
	_flip_active = false
	_flip_bulge = 0.0
	_flip_dolly_now = 0.0
	_yaw = View.current_yaw()
	var player := Game.player
	if player != null and is_instance_valid(player):
		_seed_from_player(player)
		_last_player_pos = player.global_position
		_has_last = true
	elif not _seeded:
		_focus_lat = 0.0
		_focus_up = float(Const.WORLD_HEIGHT) * 0.5
		_focus_depth = float(View.layer) + 0.5
	if effects != null:
		effects.clear_shake()
	_write_transform(_focus_world(), clampf(ortho_size, MIN_SIZE, MAX_SIZE))


## The `Camera3D` this rig drives.
func get_camera() -> Camera3D:
	return camera


## World-space point the camera is centred on.
func focus_point() -> Vector3:
	return global_position


## The visible region of the play plane as `Rect2(lateral, up, w, h)`. Useful
## for culling, off-screen indicators and spawn placement.
func plane_bounds() -> Rect2:
	var size := camera.size if camera != null else ortho_size
	var half_h := size * 0.5
	var half_w := half_h * _aspect()
	var c := View.to_plane(global_position)
	return Rect2(c.x - half_w, c.y - half_h, half_w * 2.0, half_h * 2.0)


## True while the flip animation owns the camera.
func is_flip_playing() -> bool:
	return _flip_active


## Set the base zoom (vertical extent of the view in blocks).
func set_zoom(size: float) -> void:
	ortho_size = clampf(size, MIN_SIZE, MAX_SIZE)


func get_zoom() -> float:
	return ortho_size


# --- thin forwards so callers only need `Game.camera_rig` -------------------
## Add screen shake. Prefer `Events.screen_shake.emit(strength, duration)`.
func add_trauma(amount: float, duration: float = 0.0) -> void:
	if effects != null:
		effects.add_trauma(amount, duration)


## Freeze time for `duration` real seconds. The restore is guaranteed.
func hit_stop(duration: float, time_scale: float = -1.0) -> void:
	if effects != null:
		effects.hit_stop(duration, time_scale)


## Momentary change to the ortho size; negative punches in.
func zoom_punch(amount: float, recover: float = -1.0) -> void:
	if effects != null:
		effects.zoom_punch(amount, recover)


# ------------------------------------------------------------------- helpers
## One step of an implicit critically damped spring: no overshoot, no ringing,
## stable at any frame rate (which `lerp(a, b, k * delta)` is not).
## Returns `Vector2(position, velocity)`.
static func _spring(cur: float, vel: float, target: float, omega: float, delta: float) -> Vector2:
	var f := 1.0 + 2.0 * delta * omega
	var oo := omega * omega
	var hoo := delta * oo
	var hhoo := delta * hoo
	var det_inv := 1.0 / (f + hhoo)
	var det_x := f * cur + delta * vel + hhoo * target
	var det_v := vel + hoo * (target - cur)
	return Vector2(det_x * det_inv, det_v * det_inv)
