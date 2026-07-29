## Scene host for everything visual in `fx/`. Instanced by `main.tscn` as `FX`.
##
## Owns the particle pool, the weather rig and the decal pool, and is the single
## place where the `Events` bus is turned into things you can see:
##
##   `spawn_particles`  -> pooled burst, tinted for `block_break`
##   `block_changed`    -> remembers the colour of blocks that just died, since
##                         `World.break_block()` clears the voxel *before* it
##                         asks for particles
##   `play_sound`       -> the 3D-side reaction: footprints in snow, blood on a
##                         flesh hit, scorch after an explosion
##   `screen_shake`     -> delegated to the camera rig if it implements shake,
##                         otherwise applied to the camera's frustum offsets
##   `view_flip_started`-> the `flip_wake` streaks around the player
##
## It also culls live emitters that have drifted outside the visible slab; a
## burst twelve layers behind the play plane is not worth a draw call.
extends Node3D

const SHAKE_DECAY := 3.4
const BROKEN_TTL := 1.0

@onready var particles: FxParticles = $Particles as FxParticles
@onready var weather: FxWeatherFX = $Weather as FxWeatherFX
@onready var decals: FxDecals = $Decals as FxDecals

## Live screen-shake state, readable by the camera agent via
## `Game.fx_root.shake_offset()`.
var shake_strength := 0.0
var shake_time := 0.0
var _shake_offset := Vector2.ZERO
var _delegated := false

var _broken: Dictionary = {}          ## Vector3i -> [Color, time]
var _prune := 0.0
var _cull := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Game.fx_root = self
	_rng.seed = 0xF00D
	if weather != null:
		weather.particles = particles
	var audio := get_node_or_null(^"/root/Audio")
	if audio != null and audio.has_method(&"attach_host"):
		audio.call(&"attach_host", self)

	Events.spawn_particles.connect(_on_spawn_particles)
	Events.block_changed.connect(_on_block_changed)
	Events.play_sound.connect(_on_play_sound)
	Events.screen_shake.connect(_on_screen_shake)
	Events.view_flip_started.connect(_on_flip_started)
	Events.entity_died.connect(_on_entity_died)
	Events.player_healed.connect(_on_player_healed)
	Events.world_unloaded.connect(_on_world_unloaded)


func _process(delta: float) -> void:
	_tick_shake(delta)
	_prune -= delta
	if _prune <= 0.0:
		_prune = 1.0
		_prune_broken()
	_cull -= delta
	if _cull <= 0.0:
		_cull = 0.25
		if particles != null:
			particles.cull_outside_slab()


# ================================================================== particles
func _on_spawn_particles(effect_id: String, world_pos: Vector3, amount: int) -> void:
	if particles == null:
		return
	var id := StringName(effect_id)
	var tint := Color(0, 0, 0, 0)
	if id == &"block_break" or id == &"break":
		tint = _broken_color(world_pos)
	particles.emit(id, world_pos, amount, tint)
	if id == &"explosion":
		particles.emit(&"smoke", world_pos, maxi(8, amount / 3))
		if decals != null:
			decals.scorch_burst(world_pos, 3.0, 5)


## `World.set_block` fires before the particle request, so the colour of a
## block that has just been mined is still recoverable here.
func _on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if new_id != Const.AIR or old_id == Const.AIR:
		return
	var bt: BlockType = Blocks.get_type(old_id)
	if bt == null:
		return
	_broken[pos] = [bt.color, float(Time.get_ticks_msec()) * 0.001]


func _broken_color(world_pos: Vector3) -> Color:
	var key := Const.floor_v(world_pos)
	var e: Array = _broken.get(key, [])
	if e.size() == 2:
		_broken.erase(key)
		return e[0] as Color
	return Color(0.62, 0.6, 0.58)


func _prune_broken() -> void:
	if _broken.is_empty():
		return
	var now := float(Time.get_ticks_msec()) * 0.001
	for k: Vector3i in _broken.keys():
		var e: Array = _broken[k]
		if now - float(e[1]) > BROKEN_TTL:
			_broken.erase(k)


# =============================================== sound-driven world reactions
## The 3D side of `play_sound`: a handful of ids leave a mark or a puff. Audio
## itself is handled by the `Audio` autoload; this only adds the visuals so the
## two can never drift apart.
func _on_play_sound(sound_id: String, world_pos: Vector3) -> void:
	if world_pos.is_zero_approx():
		return
	match _canonical_sound(sound_id):
		"step_snow":
			if decals != null and _rng.randf() < 0.9:
				decals.footprint(world_pos, Color(0.62, 0.68, 0.8, 0.5))
		"step_sand":
			if decals != null and _rng.randf() < 0.7:
				decals.footprint(world_pos, Color(0.55, 0.46, 0.3, 0.4))
			if particles != null and _rng.randf() < 0.4:
				particles.emit(&"dust", world_pos, 4, Color(0.86, 0.76, 0.5))
		"hit_flesh":
			if particles != null:
				particles.emit(&"blood", world_pos, 10)
			if decals != null:
				_splat_below(world_pos, &"blood")
		"hit_metal", "crit":
			if particles != null:
				particles.emit(&"sparks", world_pos, 10)
		"splash":
			if particles != null:
				particles.emit(&"splash", world_pos, 16)
		"lava", "burn":
			if particles != null:
				particles.emit(&"fire", world_pos, 10)
		"teleport", "warp":
			if particles != null:
				particles.emit(&"teleport", world_pos, 24)
		"levelup":
			if particles != null:
				particles.emit(&"levelup", world_pos, 30)
		"laser", "zap":
			if particles != null:
				particles.emit(&"electricity", world_pos, 12)


## Resolve through the sound bank's alias table so `monster_hit` leaves the
## same blood as `hit_flesh` without listing every synonym twice.
func _canonical_sound(sound_id: String) -> String:
	var audio := get_node_or_null(^"/root/Audio")
	if audio == null:
		return sound_id
	var b = audio.get("bank")
	if b == null or not b.has_method(&"canonical"):
		return sound_id
	return String(b.call(&"canonical", StringName(sound_id)))


func _splat_below(world_pos: Vector3, kind: StringName) -> void:
	var world := get_node_or_null(^"/root/World")
	if world == null or decals == null:
		return
	var hit: Dictionary = world.call(&"raycast", world_pos, Vector3.DOWN, 3.5)
	if not bool(hit.get("hit", false)):
		return
	var n := Vector3(hit.get("normal", Vector3i.UP))
	var p := Vector3(hit.get("pos", Vector3i.ZERO)) + Vector3(0.5, 0.5, 0.5) + n * 0.5
	decals.add(kind, p, n, randf_range(0.7, 1.3))


func _on_entity_died(e: Node) -> void:
	if particles == null or not (e is Node3D):
		return
	var p := (e as Node3D).global_position + Vector3(0, 0.5, 0)
	particles.emit(&"smoke", p, 10)
	particles.emit(&"blood", p, 12)


func _on_player_healed(_amount: float) -> void:
	if particles == null or Game.player == null:
		return
	particles.emit(&"heal", Game.player.global_position + Vector3(0, 0.8, 0), 12)


func _on_world_unloaded() -> void:
	_broken.clear()
	if decals != null:
		decals.clear()


# ======================================================== the flip, seen not heard
## Vertical streaks around the player along the rotation axis (world +Y — a
## flip is a yaw), thrown at the instant the world starts turning.
func _on_flip_started(_from: int, _to: int, dir: int) -> void:
	if particles == null:
		return
	var p := Game.player.global_position if Game.player != null else Vector3.ZERO
	particles.emit(&"flip_wake", p + Vector3(0, 0.6, 0), 44)
	_on_screen_shake(0.35, 0.18)
	# The dust a spin kicks up sells the weight of it.
	particles.emit(&"dust", p + Vector3(0, 0.1, 0), 6,
			Color(0.70, 0.72, 0.82) if dir > 0 else Color(0.78, 0.72, 0.82))


# =============================================================== screen shake
func _on_screen_shake(strength: float, duration: float) -> void:
	shake_strength = maxf(shake_strength, strength)
	shake_time = maxf(shake_time, duration)
	var rig := Game.camera_rig
	if rig != null and (rig.has_method(&"add_shake") or rig.has_method(&"shake")):
		_delegated = true
		if rig.has_method(&"add_shake"):
			rig.call(&"add_shake", strength, duration)
		else:
			rig.call(&"shake", strength, duration)


## Current shake displacement in plane space (lateral, up), for anything that
## wants to follow it. Always valid, whether or not the camera rig uses it.
func shake_offset() -> Vector2:
	return _shake_offset


func _tick_shake(delta: float) -> void:
	if shake_time <= 0.0:
		if _shake_offset != Vector2.ZERO:
			_shake_offset = Vector2.ZERO
			_apply_shake(Vector2.ZERO)
		return
	shake_time = maxf(0.0, shake_time - delta)
	shake_strength = maxf(0.0, shake_strength - delta * SHAKE_DECAY * shake_strength)
	var amp := shake_strength * clampf(shake_time * 4.0, 0.0, 1.0) * 0.12
	_shake_offset = Vector2(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0)) * amp
	if shake_time <= 0.0:
		shake_strength = 0.0
		_shake_offset = Vector2.ZERO
	if not _delegated:
		_apply_shake(_shake_offset)


## Frustum offsets, not a transform: the camera rig overwrites its transform
## every frame, so nudging `h_offset` / `v_offset` is the only way to shake it
## without fighting the owner of that node.
func _apply_shake(off: Vector2) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	cam.h_offset = off.x
	cam.v_offset = off.y
