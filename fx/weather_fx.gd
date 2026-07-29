## Weather particles and lightning, confined to the visible slab.
##
## A planet is 512x512 voxels; simulating weather across all of it would be
## invisible and ruinous. Instead one emitter box rides above the player,
## rotated to the current view so its *local* X is screen-lateral and its local
## Z is depth, and sized to exactly the slab the player can see
## (`Const.SLAB_BEHIND` layers). Flipping the world re-aims the box; shifting
## layers slides it. The player never sees the edge.
##
## Lightning drives two things: a local flash light so the effect works
## standalone, and `Events.weather_changed("lightning", strength)` — a transient
## *pulse* rather than a state change, which the lighting agent can hook to
## whiten the sky. Anything listening for weather states must ignore the
## `lightning` key; `FxAmbience` shows the pattern.
class_name FxWeatherFX
extends Node3D

## Recognised weather states. Anything else is treated as `clear`.
const STATES: Array[String] = [
	"clear", "rain", "storm", "snow", "ash", "sandstorm", "meteor",
]

## Half-extents of the spawn box: lateral, vertical, depth.
const BOX := Vector3(30.0, 1.6, 6.0)
## Height above the player that precipitation spawns at.
const SPAWN_HEIGHT := 17.0

var particles: FxParticles = null      ## assigned by `FxRoot` for its sprites
## Set false to leave weather entirely to other modules.
var auto_weather := true
var enabled := true

var weather := "clear"
var intensity := 0.0

var _emitter: GPUParticles3D = null
var _proc: ParticleProcessMaterial = null
var _mat: StandardMaterial3D = null
var _mesh: QuadMesh = null
var _flash: OmniLight3D = null
var _flash_t := 0.0
var _flash_peak := 0.0
var _strike_in := 0.0
var _thunder_in := -1.0
var _thunder_gain := 0.0
var _next_change := 60.0
var _external_until := 0.0
var _self_emit := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x5EED_BEEF
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(0.05, 0.6)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat.billboard_keep_scale = true
	_mat.disable_receive_shadows = true

	_proc = ParticleProcessMaterial.new()
	_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_proc.emission_box_extents = BOX
	_proc.direction = Vector3.DOWN
	_proc.spread = 4.0
	_proc.gravity = Vector3(0, -9.0, 0)

	_emitter = GPUParticles3D.new()
	_emitter.name = "Precipitation"
	_emitter.emitting = false
	_emitter.one_shot = false
	_emitter.local_coords = false
	_emitter.amount = 300
	_emitter.lifetime = 2.2
	_emitter.preprocess = 1.5
	_emitter.explosiveness = 0.0
	_emitter.randomness = 0.6
	_emitter.draw_pass_1 = _mesh
	_emitter.process_material = _proc
	_emitter.material_override = _mat
	_emitter.layers = Const.RL_EFFECTS
	_emitter.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	add_child(_emitter)

	_flash = OmniLight3D.new()
	_flash.name = "LightningFlash"
	_flash.light_energy = 0.0
	_flash.omni_range = 90.0
	_flash.light_color = Color(0.85, 0.92, 1.0)
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)

	Events.weather_changed.connect(_on_weather_changed)
	Events.world_ready.connect(_on_world_ready)


func _process(delta: float) -> void:
	if not enabled:
		return
	_follow_player()
	_tick_lightning(delta)
	if auto_weather:
		_next_change -= delta
		var now := float(Time.get_ticks_msec()) * 0.001
		if _next_change <= 0.0 and now >= _external_until:
			_next_change = _rng.randf_range(55.0, 130.0)
			_pick_weather()


# ==================================================================== control
## Set the weather directly. `intensity` 0..1. This also announces it on
## `Events.weather_changed` so lighting and ambience follow.
func set_weather(state: String, strength: float = 1.0) -> void:
	var s := state if STATES.has(state) else "clear"
	weather = s
	intensity = clampf(strength, 0.0, 1.0)
	_configure()
	_self_emit = true
	Events.weather_changed.emit(s, intensity)
	_self_emit = false


func _on_weather_changed(state: String, strength: float) -> void:
	if state == "lightning":
		return
	if _self_emit:
		return
	# Somebody else owns the weather; back off the auto-director for a while.
	_external_until = float(Time.get_ticks_msec()) * 0.001 + 180.0
	weather = state if STATES.has(state) else "clear"
	intensity = clampf(strength, 0.0, 1.0)
	_configure()


func _on_world_ready(_planet_id: String) -> void:
	_next_change = 20.0
	weather = "clear"
	intensity = 0.0
	_configure()


func _pick_weather() -> void:
	var b := String(_biome_key())
	var roll := _rng.randf()
	if b.findn("desert") >= 0 or b.findn("barren") >= 0:
		set_weather("sandstorm" if roll < 0.35 else "clear", _rng.randf_range(0.4, 1.0))
	elif b.findn("tundra") >= 0 or b.findn("snow") >= 0 or b.findn("ice") >= 0:
		set_weather("snow" if roll < 0.6 else "clear", _rng.randf_range(0.35, 0.9))
	elif b.findn("volcan") >= 0 or b.findn("ash") >= 0 or b.findn("magma") >= 0:
		set_weather("ash" if roll < 0.65 else "clear", _rng.randf_range(0.4, 1.0))
	elif b.findn("moon") >= 0 or b.findn("space") >= 0 or b.findn("void") >= 0:
		set_weather("meteor" if roll < 0.3 else "clear", _rng.randf_range(0.3, 0.8))
	elif roll < 0.24:
		set_weather("rain", _rng.randf_range(0.35, 0.85))
	elif roll < 0.32:
		set_weather("storm", _rng.randf_range(0.6, 1.0))
	else:
		set_weather("clear", 0.0)


func _biome_key() -> StringName:
	var gen := get_node_or_null(^"/root/PlanetGen")
	var p := _player_pos()
	if gen == null or not gen.has_method(&"biome_at"):
		return &""
	return gen.call(&"biome_at", int(floorf(p.x)), int(floorf(p.z)))


# ================================================================== placement
func _player_pos() -> Vector3:
	var game := get_node_or_null(^"/root/Game")
	if game == null:
		return Vector3.ZERO
	var pl = game.get("player")
	return (pl as Node3D).global_position if pl is Node3D else Vector3.ZERO


## Keep the spawn box over the player, straddling the visible layers, and
## rotated so its local axes line up with lateral / depth for this view.
func _follow_player() -> void:
	if _emitter == null or not _emitter.emitting:
		return
	var p := _player_pos()
	var lat := View.lateral_of(p)
	var depth := float(View.layer) + float(View.depth_sign()) * (BOX.z * 0.5 - 1.0)
	var origin := View.to_world(Vector2(lat, p.y + SPAWN_HEIGHT), depth)
	_emitter.global_position = origin
	_emitter.global_rotation = Vector3(0.0, View.current_yaw(), 0.0)
	if _flash.visible:
		_flash.global_position = p + Vector3(0.0, 22.0, 0.0)


# ================================================================ configuring
func _configure() -> void:
	if _emitter == null:
		return
	if weather == "clear" or intensity <= 0.02:
		_emitter.emitting = false
		_strike_in = 0.0
		return
	var tex_key := &"dot"
	var c0 := Color.WHITE
	var c1 := Color.WHITE
	match weather:
		"rain", "storm":
			tex_key = &"spark"
			_mesh.size = Vector2(0.035, 0.75)
			_proc.direction = Vector3(0.05, -1.0, 0.0)
			_proc.spread = 3.0
			_proc.initial_velocity_min = 22.0
			_proc.initial_velocity_max = 30.0
			_proc.gravity = Vector3(0, -14.0, 0)
			_proc.scale_min = 0.7
			_proc.scale_max = 1.4
			_proc.particle_flag_align_y = true
			c0 = Color(0.62, 0.74, 0.95, 0.55)
			c1 = Color(0.62, 0.74, 0.95, 0.28)
			_emitter.lifetime = 1.5
			_emitter.amount = int(lerpf(160.0, 620.0, intensity)) * (2 if weather == "storm" else 1)
		"snow":
			tex_key = &"dot"
			_mesh.size = Vector2(0.10, 0.10)
			_proc.direction = Vector3(0.25, -1.0, 0.1)
			_proc.spread = 32.0
			_proc.initial_velocity_min = 1.2
			_proc.initial_velocity_max = 3.0
			_proc.gravity = Vector3(0.4, -1.6, 0.0)
			_proc.scale_min = 0.5
			_proc.scale_max = 1.6
			_proc.particle_flag_align_y = false
			c0 = Color(1, 1, 1, 0.9)
			c1 = Color(0.92, 0.96, 1.0, 0.6)
			_emitter.lifetime = 9.0
			_emitter.amount = int(lerpf(120.0, 420.0, intensity))
		"ash":
			tex_key = &"smoke"
			_mesh.size = Vector2(0.14, 0.14)
			_proc.direction = Vector3(0.4, -1.0, 0.0)
			_proc.spread = 40.0
			_proc.initial_velocity_min = 0.8
			_proc.initial_velocity_max = 2.4
			_proc.gravity = Vector3(0.6, -1.1, 0.0)
			_proc.scale_min = 0.5
			_proc.scale_max = 2.0
			_proc.particle_flag_align_y = false
			c0 = Color(0.42, 0.36, 0.33, 0.75)
			c1 = Color(0.75, 0.35, 0.15, 0.25)
			_emitter.lifetime = 11.0
			_emitter.amount = int(lerpf(90.0, 320.0, intensity))
		"sandstorm":
			tex_key = &"smoke"
			_mesh.size = Vector2(0.5, 0.35)
			_proc.direction = Vector3(1.0, -0.15, 0.0)
			_proc.spread = 18.0
			_proc.initial_velocity_min = 14.0
			_proc.initial_velocity_max = 26.0
			_proc.gravity = Vector3(6.0, -1.0, 0.0)
			_proc.scale_min = 1.0
			_proc.scale_max = 3.5
			_proc.particle_flag_align_y = false
			c0 = Color(0.82, 0.70, 0.44, 0.42)
			c1 = Color(0.78, 0.66, 0.40, 0.0)
			_emitter.lifetime = 3.0
			_emitter.amount = int(lerpf(120.0, 380.0, intensity))
		"meteor":
			tex_key = &"spark"
			_mesh.size = Vector2(0.10, 1.6)
			_proc.direction = Vector3(0.6, -1.0, 0.0)
			_proc.spread = 6.0
			_proc.initial_velocity_min = 26.0
			_proc.initial_velocity_max = 40.0
			_proc.gravity = Vector3(4.0, -18.0, 0.0)
			_proc.scale_min = 0.8
			_proc.scale_max = 2.2
			_proc.particle_flag_align_y = true
			c0 = Color(1.0, 0.85, 0.45, 1.0)
			c1 = Color(1.0, 0.30, 0.05, 0.0)
			_emitter.lifetime = 2.0
			_emitter.amount = int(lerpf(4.0, 22.0, intensity))
	_proc.color_ramp = _ramp(c0, c1)
	_proc.emission_box_extents = Vector3(BOX.x, BOX.y, BOX.z)
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if weather == "meteor" \
			else BaseMaterial3D.BLEND_MODE_MIX
	if particles != null:
		_mat.albedo_texture = particles.sprite(tex_key)
	_emitter.emitting = true
	_emitter.restart()
	_strike_in = _rng.randf_range(4.0, 14.0) if weather == "storm" else 0.0


func _ramp(c0: Color, c1: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 32
	return t


# =================================================================== lightning
func _tick_lightning(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		# Two-stage flicker: bright stab, dip, second weaker stab.
		var u := _flash_t / 0.42
		var shape := u if u > 0.6 else (u * 2.2 if u > 0.3 else u * 0.8)
		_flash.light_energy = _flash_peak * clampf(shape, 0.0, 1.6)
		_flash.visible = _flash.light_energy > 0.01
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0:
			_thunder_in = -1.0
			var audio := get_node_or_null(^"/root/Audio")
			if audio != null and audio.has_method(&"play"):
				audio.call(&"play", &"thunder", _player_pos(), _thunder_gain)
	if _strike_in <= 0.0:
		return
	_strike_in -= delta
	if _strike_in <= 0.0:
		strike(_rng.randf_range(0.35, 1.0))
		_strike_in = _rng.randf_range(5.0, 22.0) / maxf(0.2, intensity)


## Fire a lightning flash now. `strength` 0..1 scales the light, the thunder
## delay (near strikes crack sooner) and the screen shake.
func strike(strength: float = 1.0) -> void:
	var s := clampf(strength, 0.05, 1.0)
	_flash_peak = lerpf(2.0, 9.0, s)
	_flash_t = 0.42
	_flash.global_position = _player_pos() + Vector3(0.0, 22.0, 0.0)
	_flash.visible = true
	_thunder_in = lerpf(4.5, 0.25, s)
	_thunder_gain = lerpf(-14.0, 0.0, s)
	# A pulse, not a state: listeners must not latch this as the weather.
	Events.weather_changed.emit("lightning", s)
	if s > 0.75:
		Events.screen_shake.emit(1.2 * s, 0.35)
