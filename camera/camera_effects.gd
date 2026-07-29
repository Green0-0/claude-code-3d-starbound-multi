## Trauma-based screen shake, hit-stop, zoom punches, landing dip and idle sway.
##
## This node produces *numbers only* — it never touches the camera transform
## itself. `CamRig` reads `offset()`, `roll()`, `size_multiplier()` and
## `depth_offset()` once per frame and composes them into the final camera
## transform, so the follow logic can never be corrupted by an effect.
##
## Offsets are returned as a fraction of the camera's half-height, which makes
## every effect look identical at any zoom level and any resolution.
##
## Shake follows the standard trauma model: callers add *trauma*, the shake
## amplitude is `trauma * trauma` so small hits stay subtle and big ones bloom,
## and trauma decays linearly back to zero.
class_name CamEffects
extends Node

# ------------------------------------------------------------------- tuning
@export_group("Shake")
## Screen offset at trauma == 1, as a fraction of the camera half-height.
@export var max_shake := 0.055
## Camera roll at trauma == 1, in radians.
@export var max_roll := 0.030
## Noise samples per second. Higher = buzzier, lower = wobblier.
@export var shake_frequency := 24.0
## Trauma lost per second when no duration was requested.
@export var trauma_decay := 1.6
## Hard ceiling on accumulated trauma.
@export var max_trauma := 1.0

@export_group("Impacts")
## Fraction of half-height the camera drops on a maximum-force landing.
@export var landing_dip := 0.06
## Fall distance (blocks) that produces a full-strength dip.
@export var landing_full_fall := 14.0
## Spring frequency the dip recovers with.
@export var dip_stiffness := 13.0
## `Engine.time_scale` used while a hit-stop is active.
@export var hit_stop_scale := 0.06
## Longest hit-stop that can ever be requested, in real seconds.
@export var max_hit_stop := 0.35

@export_group("Zoom")
## Spring frequency zoom punches recover with.
@export var zoom_stiffness := 10.0
## Clamp on the additive zoom offset (1.0 == the base ortho size).
@export var max_zoom_punch := 0.35

@export_group("Idle")
@export var idle_sway_amount := 0.005
@export var idle_sway_speed := 0.55
## Plane speed (blocks/s) above which the sway is fully suppressed.
@export var idle_sway_cutoff := 2.5

# -------------------------------------------------------------------- state
## Current trauma, 0..1. Read-only for other modules; use `add_trauma`.
var trauma := 0.0

var _decay := 1.6
var _noise: FastNoiseLite = null
var _time := 0.0

var _dip := 0.0
var _dip_vel := 0.0
var _zoom := 0.0
var _zoom_vel := 0.0
var _zoom_stiff := 10.0

var _hit_active := false
var _hit_until_ms := 0
var _base_time_scale := 1.0
var _stuck_since_ms := 0
var _warned_stuck := false

var _player: VoxelEntity = null
var _offset := Vector2.ZERO
var _roll := 0.0


func _ready() -> void:
	# Must keep ticking while the tree is paused, otherwise a hit-stop started
	# just before a pause would strand `Engine.time_scale`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 5
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_noise.seed = randi()
	Events.screen_shake.connect(_on_screen_shake)
	Events.player_damaged.connect(_on_player_damaged)
	Events.entity_died.connect(_on_entity_died)
	Events.player_died.connect(_on_player_died)
	Events.player_spawned.connect(_bind_player)
	if Game.player != null:
		_bind_player(Game.player)


func _exit_tree() -> void:
	_end_hit_stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_end_hit_stop()


func _process(delta: float) -> void:
	# Real (unscaled) time, so the hit-stop timer cannot be slowed by the very
	# slowdown it is supposed to end.
	var now := Time.get_ticks_msec()
	if _hit_active and now >= _hit_until_ms:
		_end_hit_stop()
	_watchdog_time_scale(now)

	delta = minf(delta, 0.1)
	_time += delta

	# --- trauma ---------------------------------------------------------
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - _decay * delta)
		if trauma <= 0.0:
			_decay = trauma_decay

	var shake_mul := CamSettings.shake_scale()
	var amp := trauma * trauma * shake_mul
	if amp > 0.0001:
		var t := _time * shake_frequency
		_offset = Vector2(
			_noise.get_noise_2d(t, 0.0),
			_noise.get_noise_2d(t, 137.0)) * (max_shake * amp)
		_roll = _noise.get_noise_2d(t, 311.0) * max_roll * amp
	else:
		_offset = Vector2.ZERO
		_roll = 0.0

	# --- landing dip ----------------------------------------------------
	var dip_step := _spring(_dip, _dip_vel, 0.0, dip_stiffness, delta)
	_dip = dip_step.x
	_dip_vel = dip_step.y

	# --- zoom punch -----------------------------------------------------
	var zoom_step := _spring(_zoom, _zoom_vel, 0.0, _zoom_stiff, delta)
	_zoom = clampf(zoom_step.x, -max_zoom_punch, max_zoom_punch)
	_zoom_vel = zoom_step.y

	# --- idle sway ------------------------------------------------------
	if CamSettings.idle_sway_enabled and not CamSettings.reduce_motion:
		var calm := 1.0
		if _player != null and is_instance_valid(_player):
			var speed := absf(Const.lateral_of(_player.velocity, View.view))
			speed = maxf(speed, absf(_player.velocity.y))
			calm = clampf(1.0 - speed / maxf(0.01, idle_sway_cutoff), 0.0, 1.0)
		var s := _time * idle_sway_speed
		_offset += Vector2(sin(s), sin(s * 0.73 + 1.3) * 0.6) * (idle_sway_amount * calm)

	_offset.y += _dip


# ------------------------------------------------------------------ outputs
## Camera-space offset (screen-right, up) as a fraction of the half-height.
func offset() -> Vector2:
	return _offset


## Camera roll in radians.
func roll() -> float:
	return _roll


## Multiplier on the rig's base orthographic size. 1.0 == no change.
func size_multiplier() -> float:
	return 1.0 + _zoom


## Extra distance to push the camera back along its own view axis. Purely for
## near-plane safety during big punches; invisible under orthographic.
func depth_offset() -> float:
	return maxf(0.0, _zoom) * 6.0


# ----------------------------------------------------------------- shake API
## Add trauma. `amount` is 0..1; `duration` (seconds) tunes how fast it decays,
## 0 = use the default decay rate.
func add_trauma(amount: float, duration: float = 0.0) -> void:
	if amount <= 0.0 or CamSettings.shake_scale() <= 0.0:
		return
	trauma = minf(max_trauma, trauma + amount)
	if duration > 0.0:
		_decay = clampf(trauma / duration, 0.35, 8.0)
	else:
		_decay = trauma_decay


## Alias matching the `Events.screen_shake(strength, duration)` contract.
func shake(strength: float, duration: float = 0.3) -> void:
	add_trauma(strength, duration)


## Cancel all shake immediately (cutscenes, teleports, menus).
func clear_shake() -> void:
	trauma = 0.0
	_offset = Vector2.ZERO
	_roll = 0.0


# -------------------------------------------------------------- hit-stop API
## Freeze time for `duration` real seconds. Safe to call repeatedly: the longest
## outstanding request wins, and the restore is guaranteed by this node's own
## real-time clock even if the caller is freed mid-freeze.
func hit_stop(duration: float, freeze_scale: float = -1.0) -> void:
	if not CamSettings.hit_stop_enabled or duration <= 0.0:
		return
	if Game.paused:
		return
	duration = minf(duration, max_hit_stop)
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	if _hit_active:
		_hit_until_ms = maxi(_hit_until_ms, until)
		return
	# Only capture the base scale when it looks like a sane, unmodified value,
	# so we never "restore" someone else's slowdown.
	var current := Engine.time_scale
	_base_time_scale = current if current > 0.5 else 1.0
	_hit_active = true
	_hit_until_ms = until
	Engine.time_scale = freeze_scale if freeze_scale > 0.0 else hit_stop_scale


## True while time is frozen.
func is_hit_stopped() -> bool:
	return _hit_active


## Global safety net. `Engine.time_scale` is a process-wide global that several
## systems poke (this node, `combat/hit_stop_driver.gd`, techs, cutscenes). If
## two of them overlap, one can capture the other's dilated value as its
## "restore" value and latch the whole game into slow motion forever.
##
## Nothing legitimately holds time below `STUCK_SCALE` for longer than a
## hit-stop, so if it stays there past `STUCK_MS` of *real* time with no
## hit-stop of ours running, we put it back. Slow-motion effects above that
## threshold (0.5x boss intros, tech time dilation) are never touched.
const STUCK_SCALE := 0.2
const STUCK_MS := 900


func _watchdog_time_scale(now: int) -> void:
	if _hit_active or Engine.time_scale > STUCK_SCALE:
		_stuck_since_ms = 0
		return
	if _stuck_since_ms == 0:
		_stuck_since_ms = now
		return
	if now - _stuck_since_ms < STUCK_MS:
		return
	_stuck_since_ms = 0
	Engine.time_scale = 1.0
	if not _warned_stuck:
		_warned_stuck = true
		push_warning("[CamEffects] Engine.time_scale was stuck below %s — restored to 1.0" % STUCK_SCALE)


func _end_hit_stop() -> void:
	if not _hit_active:
		return
	_hit_active = false
	Engine.time_scale = _base_time_scale


# ------------------------------------------------------------ punches / dips
## Additive change to the orthographic size, as a fraction of the base size.
## Negative punches in (feels like an impact), positive pulls out.
func zoom_punch(amount: float, recover: float = -1.0) -> void:
	if CamSettings.reduce_motion:
		return
	_zoom = clampf(_zoom + amount, -max_zoom_punch, max_zoom_punch)
	_zoom_stiff = zoom_stiffness if recover <= 0.0 else maxf(1.0, TAU / recover)


## Push the framing down (negative) or up, as a fraction of the half-height.
## Springs back to zero.
func dip(amount: float) -> void:
	if CamSettings.reduce_motion:
		return
	_dip += amount
	_dip = clampf(_dip, -0.25, 0.25)


# -------------------------------------------------------------------- events
func _on_screen_shake(strength: float, duration: float) -> void:
	add_trauma(strength, duration)


func _on_player_damaged(amount: float, _element: String, _source: Node) -> void:
	var maxhp := 100.0
	if _player != null and is_instance_valid(_player):
		maxhp = maxf(1.0, _player.max_health)
	var frac := clampf(amount / maxhp, 0.0, 1.0)
	add_trauma(0.18 + frac * 0.55, 0.32 + frac * 0.25)
	zoom_punch(-0.02 - frac * 0.05, 0.35)
	if frac > 0.12:
		hit_stop(0.05 + frac * 0.18)


func _on_player_died(_cause: String) -> void:
	add_trauma(0.7, 0.9)
	hit_stop(0.3)
	zoom_punch(0.12, 1.2)


func _on_entity_died(entity: Node) -> void:
	# Sparingly: only nearby deaths, scaled by distance, never for the player
	# (that is handled above with a much bigger response).
	if entity == null or not is_instance_valid(entity) or entity == _player:
		return
	var n3 := entity as Node3D
	if n3 == null:
		return
	var here := (get_parent() as Node3D).global_position if get_parent() is Node3D else Vector3.ZERO
	var d := here.distance_to(n3.global_position)
	if d > 24.0:
		return
	var falloff := 1.0 - d / 24.0
	add_trauma(0.10 * falloff * falloff, 0.22)


func _bind_player(p: Node) -> void:
	var e := p as VoxelEntity
	if e == null:
		return
	_player = e
	if not e.landed.is_connected(_on_player_landed):
		e.landed.connect(_on_player_landed)


func _on_player_landed(fall_distance: float) -> void:
	if fall_distance < 1.5:
		return
	var f := clampf(fall_distance / maxf(1.0, landing_full_fall), 0.0, 1.0)
	f = f * f
	dip(-landing_dip * f)
	if f > 0.25:
		add_trauma(0.12 * f, 0.22)
	if fall_distance > landing_full_fall:
		hit_stop(0.06)


# ------------------------------------------------------------------- helpers
## One step of an implicit critically damped spring. Unconditionally stable at
## any frame rate, unlike `lerp(a, b, delta * k)`.
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
