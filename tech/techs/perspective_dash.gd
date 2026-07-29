## Perspective Dash — dash, and rotate the world ninety degrees halfway through
## it. You come out the far side in a different plane with the dash still under
## you.
##
## ---------------------------------------------------------------------------
## WHY THE MOMENTUM CARRIES
## ---------------------------------------------------------------------------
## A flip does not move the player, it re-labels the axes. Before the flip the
## dash speed lives on the old lateral axis; after it, that same world axis is
## the new *depth* axis — drifting along it would push the player out of their
## own layer. So at the moment of the flip we re-express the dash in the new
## frame: `set_plane_velocity(speed * dir)` writes velocity from the new
## `View.right()` and, as a side effect, zeroes the component on the new depth
## axis. One call both carries the momentum and cleans up the leak.
##
## `View.request_flip` sets `View.view` to the destination immediately and calls
## `_recompute_layer()`, so by the time it returns we are already reasoning in
## the new frame — the conversion must happen *after* it, never before.
##
## ---------------------------------------------------------------------------
## VIEW STATE
## ---------------------------------------------------------------------------
## Mutated under `claim_view()`:
##   `View.flip_duration` -> 0.20   the dash-flip is snappier than a manual one
##   player `gravity_scale` -> 0.0  the dash is flat
##   `View.view` / `View.layer`     via `View.request_flip`, the real effect
## Restored in `on_deactivate`:
##   `gravity_scale` from its saved value, `flip_duration` by `release_view()`.
##   The view and layer are *not* rolled back — landing in the new plane is the
##   point. If the flip was refused (`flips_enabled` false, another flip already
##   running) the tech simply completes as an ordinary flat dash.
class_name TchPerspectiveDash
extends TchBase

const SPEED_MULT := 3.2
const FLIP_AT := 0.55        ## fraction of `duration` remaining when we flip
const FLIP_DURATION := 0.20

var _dir: int = 1
var _flip_dir: int = 1
var _speed: float = 0.0
var _saved_gravity: float = 1.0
var _flipped: bool = false


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or p.is_shifting() or View.flipping or View.shifting:
		return false

	var axis := Input.get_axis(&"move_left", &"move_right")
	_dir = signi(int(sign(axis))) if absf(axis) > 0.2 else p.facing
	if _dir == 0:
		_dir = 1
	# Dashing right rotates the world clockwise, left counter-clockwise, so the
	# flip always reads as "the dash turned the corner".
	_flip_dir = 1 if _dir > 0 else -1
	_speed = p.move_speed * SPEED_MULT
	_flipped = false

	claim_view()
	View.flip_duration = FLIP_DURATION
	_saved_gravity = p.gravity_scale
	p.gravity_scale = 0.0
	p.velocity.y = 0.0
	p.set_plane_velocity(_speed * float(_dir))
	p.facing = _dir
	p.iframes = maxf(p.iframes, duration)

	Events.spawn_particles.emit(&"tech_perspective_dash", p.aabb_center(), 24)
	Events.play_sound.emit(&"tech_perspective_dash", p.global_position)
	return true


func on_update(_delta: float) -> void:
	if not active:
		return
	var p := player()
	if p == null:
		return
	p.velocity.y = 0.0

	if not _flipped and time_left <= duration * FLIP_AT:
		_flipped = true
		if View.request_flip(_flip_dir):
			# We are already in the destination frame here — re-express the
			# dash and drop any velocity that would now count as depth drift.
			p.set_plane_velocity(_speed * float(_dir))
			p.facing = _dir
			Events.screen_shake.emit(1.4, 0.22)
			Events.spawn_particles.emit(&"tech_perspective_flip", p.aabb_center(), 30)
		else:
			# Flips are locked (cutscene, star map, another tech). Fall back to
			# a plain dash rather than eating the input.
			Events.flip_blocked.emit("perspective_dash")
	else:
		p.set_plane_velocity(_speed * float(_dir))


func on_deactivate() -> void:
	var p := player()
	if p != null:
		p.gravity_scale = _saved_gravity
		p.set_plane_velocity(p.move_speed * 1.2 * float(_dir))
		p.fall_start_y = p.global_position.y
	release_view()


func modifier(stat: String) -> float:
	return 0.0 if (active and stat == "fall_damage") else 1.0
