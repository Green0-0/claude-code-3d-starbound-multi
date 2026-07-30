class_name SkyCycle
extends RefCounted

## The day/night cycle and the weather, driving the sun, the environment and the
## planet's ambient temperature.
##
## The cycle is the reason to build a shelter and the reason a torch matters, so
## it is deliberately quick — a full day is a few minutes — and night is dark
## enough that the cutaway's glow is doing real work down a tunnel.

signal time_changed(day: int, fraction: float)
signal weather_changed(kind: StringName)

const DAY_SECONDS := 420.0
const DAWN := 0.22
const NOON := 0.5
const DUSK := 0.78

const WEATHERS := [&"clear", &"clear", &"clear", &"overcast", &"rain", &"storm"]

var day := 0
var fraction := 0.36              ## 0 midnight, 0.5 noon
var time_scale := 1.0
var weather: StringName = &"clear"
var weather_timer := 90.0

var sun: DirectionalLight3D
var env: WorldEnvironment
var planet_sky := Color(0.4, 0.6, 0.9)
var ground := Color(0.3, 0.5, 0.3)
var star_color := Color(1, 1, 1)
var airless := false               ## moons and barren rock: hard shadows, no haze

var _rng := RandomNumberGenerator.new()
var _rain: GPUParticles3D
var _follow: Node3D

# The authored look from main.tscn, captured once. The cycle *modulates* these
# rather than replacing them: the environment in the scene is a hand-tuned HD-2D
# grade, and a day/night system that throws it away is a day/night system that
# has broken the game's art direction.
var _base_energy := 1.0
var _base_sun := Color(1, 1, 1)
var _base_ambient := Color(0.36, 0.38, 0.54)
var _base_ambient_energy := 0.66
var _base_fog := Color(0.27, 0.20, 0.24)
var _base_fog_energy := 0.55
var _base_fog_density := 0.0042
var _base_sky_top := Color(0.05, 0.05, 0.10)
var _base_sky_horizon := Color(0.35, 0.19, 0.18)
var _base_ground_horizon := Color(0.24, 0.13, 0.12)


func setup(p_sun: DirectionalLight3D, p_env: WorldEnvironment, follow: Node3D) -> void:
	sun = p_sun
	env = p_env
	_follow = follow
	if sun != null:
		_base_energy = sun.light_energy
		_base_sun = sun.light_color
	if env != null and env.environment != null:
		var e := env.environment
		_base_ambient = e.ambient_light_color
		_base_ambient_energy = e.ambient_light_energy
		_base_fog = e.fog_light_color
		_base_fog_energy = e.fog_light_energy
		_base_fog_density = e.fog_density
		if e.sky != null and e.sky.sky_material is ProceduralSkyMaterial:
			var m := e.sky.sky_material as ProceduralSkyMaterial
			_base_sky_top = m.sky_top_color
			_base_sky_horizon = m.sky_horizon_color
			_base_ground_horizon = m.ground_horizon_color
	_rng.randomize()
	_build_rain()


func configure(planet: Dictionary) -> void:
	planet_sky = planet.get("sky", Color(0.4, 0.6, 0.9))
	ground = planet.get("ground", Color(0.3, 0.5, 0.3))
	star_color = planet.get("star", Color(1, 1, 1))
	var type: StringName = planet.get("type", &"garden")
	airless = type in [&"moon", &"barren", &"crystal"]
	weather = &"clear"
	weather_timer = 60.0


func is_night() -> bool:
	return fraction < DAWN or fraction > DUSK


## 0 at midnight, 1 at noon — the value everything else reads.
func daylight() -> float:
	return clampf(sin(fraction * PI) * 1.25 - 0.05, 0.0, 1.0)


func time_string() -> String:
	var minutes := int(fraction * 1440.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func tick(delta: float) -> void:
	fraction += delta * time_scale / DAY_SECONDS
	while fraction >= 1.0:
		fraction -= 1.0
		day += 1
	time_changed.emit(day, fraction)

	weather_timer -= delta
	if weather_timer <= 0.0:
		_roll_weather()

	_apply()


func _roll_weather() -> void:
	weather_timer = _rng.randf_range(70.0, 200.0)
	var next: StringName = WEATHERS[_rng.randi() % WEATHERS.size()]
	if airless:
		next = &"clear"
	if next != weather:
		weather = next
		weather_changed.emit(weather)
	if _rain != null:
		_rain.emitting = weather == &"rain" or weather == &"storm"
		_rain.amount_ratio = 1.0 if weather == &"storm" else 0.45


func _apply() -> void:
	var light := daylight()
	var dim := 1.0
	match weather:
		&"overcast": dim = 0.68
		&"rain": dim = 0.52
		&"storm": dim = 0.36

	if sun != null:
		# a low arc, so shadows stay long and the world stays legible side-on
		var angle := (fraction - 0.25) * TAU
		sun.rotation = Vector3(-sin(angle) * 1.15 - 0.35, cos(angle) * 0.6 + 2.2, 0.0)
		sun.light_energy = _base_energy * (0.05 + light * 0.95) * dim
		# only the last of the light goes warm, and only a little
		var low := clampf(1.0 - light * 1.6, 0.0, 1.0)
		sun.light_color = _base_sun.lerp(star_color, 0.35) \
			.lerp(Color(1.0, 0.70, 0.46), low * 0.45)
		sun.visible = light > 0.01

	if env == null or env.environment == null:
		return
	var e := env.environment
	# Ambient keeps the authored cool cast and is only nudged toward the
	# planet's own daylight tint at noon.
	e.ambient_light_color = _base_ambient.lerp(
		_base_ambient.lerp(planet_sky, 0.35), light)
	e.ambient_light_energy = _base_ambient_energy * (0.28 + light * 0.72) * dim
	e.fog_light_color = _base_fog.lerp(_base_fog.lerp(planet_sky, 0.3), light * 0.6)
	e.fog_light_energy = _base_fog_energy * (0.5 + light * 0.5)
	e.fog_density = _base_fog_density \
		* (1.0 + (1.6 if weather == &"rain" or weather == &"storm" else 0.0)) \
		* (0.55 if airless else 1.0)

	if e.sky != null and e.sky.sky_material is ProceduralSkyMaterial:
		var m := e.sky.sky_material as ProceduralSkyMaterial
		# The night sky is the authored one; day lifts it toward the planet tint.
		m.sky_top_color = _base_sky_top.lerp(planet_sky.darkened(0.25), light * 0.9)
		m.sky_horizon_color = _base_sky_horizon.lerp(
			planet_sky.lerp(Color(0.95, 0.86, 0.70), 0.25), light * 0.85)
		m.ground_horizon_color = _base_ground_horizon.lerp(
			ground.darkened(0.35), light * 0.7)


## Ambient temperature at a position: biome base, plus night, minus depth.
func warmth_at(base: float, y: float, sheltered: bool) -> float:
	var t := base
	if not sheltered:
		t -= (1.0 - daylight()) * 0.35
	if weather == &"rain" or weather == &"storm":
		t -= 0.15
	# deep rock is cold until it is very deep, then it is not
	if y < 16.0:
		t += (16.0 - y) * 0.02
	return clampf(t, -1.0, 1.0)


func _build_rain() -> void:
	if _follow == null:
		return
	_rain = GPUParticles3D.new()
	_rain.amount = 900
	_rain.lifetime = 1.1
	_rain.visibility_aabb = AABB(Vector3(-24, -20, -24), Vector3(48, 40, 48))
	_rain.emitting = false
	_rain.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(22, 0.5, 22)
	mat.direction = Vector3(0.1, -1, 0)
	mat.spread = 2.0
	mat.initial_velocity_min = 22.0
	mat.initial_velocity_max = 30.0
	mat.gravity = Vector3(0, -12, 0)
	mat.scale_min = 0.6
	mat.scale_max = 1.0
	mat.color = Color(0.66, 0.78, 0.94, 0.5)
	_rain.process_material = mat

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.42, 0.03)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.72, 0.82, 0.96, 0.55)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.vertex_color_use_as_albedo = true
	mesh.material = mm
	_rain.draw_pass_1 = mesh

	_follow.get_parent().add_child.call_deferred(_rain)


## Keep the rain volume over the player.
func follow(pos: Vector3) -> void:
	if _rain != null and _rain.is_inside_tree():
		_rain.global_position = pos + Vector3(0, 16, 0)


func save_state() -> Dictionary:
	return {"day": day, "fraction": fraction, "weather": String(weather)}


func load_state(d: Dictionary) -> void:
	day = int(d.get("day", 0))
	fraction = float(d.get("fraction", 0.3))
	weather = StringName(d.get("weather", "clear"))
	_apply()
