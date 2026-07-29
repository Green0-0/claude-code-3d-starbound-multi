## How weather bends the light.
##
## **The survival agent owns weather.** This module only listens to
## `Events.weather_changed(weather, intensity)` and never emits it; with no
## weather system running at all the defaults are clear skies and every scale
## sits at 1.0, so nothing here can darken a world that nobody asked to be
## darkened.
##
## The outputs are plain multipliers read by `LitDayNight` (lights, ambient,
## fog, stars) and by `Lighting._refresh_daylight` (`light_scale`, which is the
## only one that reaches the *voxel* light — it scales the skylight nibble, so
## a thunderstorm genuinely makes caves and interiors darker, not just the
## sky). Block light is never touched: a torch burns the same in a blizzard.
##
## Every value is spring-smoothed, because weather that snaps is weather that
## looks like a bug.
class_name LitWeather
extends Node

## One weather mood. All fields are multipliers or 0..1 amounts.
class Mood extends RefCounted:
	var key: StringName = &"clear"
	var light_scale := 1.0        ## multiplies daylight -> reaches voxel light
	var ambient_scale := 1.0
	var fog_scale := 1.0
	var fog_add := 0.0            ## absolute fog density added on top
	var tint := Color(1, 1, 1)
	var tint_amount := 0.0
	var star_visibility := 1.0
	var depth_boost := 0.0        ## extra depth cueing for the slab shader
	var flicker := 0.0            ## lightning amplitude

	func _init(p_key: StringName = &"clear") -> void:
		key = p_key


## Seconds a weather change takes to fully land.
var blend_time := 3.0

# ------------------------------------------------------------------- outputs
var light_scale := 1.0
var ambient_scale := 1.0
var fog_scale := 1.0
var fog_add := 0.0
var tint := Color(1, 1, 1)
var tint_amount := 0.0
var star_visibility := 1.0
var depth_boost := 0.0

var current_weather: StringName = &"clear"
var intensity := 0.0

var moods: Dictionary = {}
var _target: Mood = null
var _clear: Mood = null
var _flash := 0.0
var _flash_timer := 2.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_moods()
	_clear = moods[&"clear"]
	_target = _clear
	Events.weather_changed.connect(_on_weather_changed)
	Events.travel_finished.connect(func(_id: String) -> void: _on_weather_changed("clear", 0.0))


func _on_weather_changed(weather: String, p_intensity: float) -> void:
	var key := StringName(weather.to_lower())
	var m: Mood = moods.get(key)
	if m == null:
		m = moods.get(_alias(key), _clear)
	current_weather = m.key
	intensity = clampf(p_intensity, 0.0, 1.0)
	_target = m


func _alias(key: StringName) -> StringName:
	match key:
		&"rain", &"drizzle", &"showers":
			return &"rain"
		&"thunder", &"thunderstorm", &"lightning", &"tempest":
			return &"storm"
		&"snow", &"blizzard", &"hail", &"sleet":
			return &"snow"
		&"fog", &"mist", &"haze", &"smog":
			return &"fog"
		&"ash", &"ashfall", &"cinders", &"smoke":
			return &"ash"
		&"sandstorm", &"dust", &"duststorm":
			return &"sandstorm"
		&"acid", &"acid_rain", &"toxic_rain":
			return &"acid"
		&"meteor", &"meteors", &"meteor_shower":
			return &"meteor"
	return &"clear"


func _process(delta: float) -> void:
	var m := _target if _target != null else _clear
	var i := intensity
	var k: float = clampf(delta / maxf(0.05, blend_time), 0.0, 1.0)
	# Interpolate toward "clear blended with the mood by intensity".
	light_scale = lerpf(light_scale, lerpf(1.0, m.light_scale, i), k)
	ambient_scale = lerpf(ambient_scale, lerpf(1.0, m.ambient_scale, i), k)
	fog_scale = lerpf(fog_scale, lerpf(1.0, m.fog_scale, i), k)
	fog_add = lerpf(fog_add, m.fog_add * i, k)
	tint = tint.lerp(m.tint, k)
	tint_amount = lerpf(tint_amount, m.tint_amount * i, k)
	star_visibility = lerpf(star_visibility, lerpf(1.0, m.star_visibility, i), k)
	depth_boost = lerpf(depth_boost, m.depth_boost * i, k)
	_update_lightning(m, i, delta)


## Lightning is a short additive spike on `light_scale`, so it flashes the
## whole world including the inside of caves — cheap, and it reads.
func _update_lightning(m: Mood, i: float, delta: float) -> void:
	if m.flicker <= 0.0 or i <= 0.05:
		_flash = maxf(0.0, _flash - delta * 6.0)
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash_timer = _rng.randf_range(3.5, 11.0) / maxf(0.15, i)
		_flash = m.flicker * i
		Events.play_sound.emit(&"thunder", _listener())
	_flash = maxf(0.0, _flash - delta * 4.5)
	light_scale = clampf(light_scale + _flash, 0.0, 1.6)


func _listener() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO


## True while a lightning flash is lighting the scene, for the fx agent.
func lightning_flash() -> float:
	return _flash


func _def(key: StringName) -> Mood:
	var m := Mood.new(key)
	moods[key] = m
	return m


func _build_moods() -> void:
	_def(&"clear")

	var rain := _def(&"rain")
	rain.light_scale = 0.66
	rain.ambient_scale = 0.85
	rain.fog_scale = 2.2
	rain.fog_add = 0.004
	rain.tint = Color(0.55, 0.62, 0.72)
	rain.tint_amount = 0.45
	rain.star_visibility = 0.05
	rain.depth_boost = 0.06

	var storm := _def(&"storm")
	storm.light_scale = 0.42
	storm.ambient_scale = 0.70
	storm.fog_scale = 2.8
	storm.fog_add = 0.007
	storm.tint = Color(0.38, 0.44, 0.56)
	storm.tint_amount = 0.62
	storm.star_visibility = 0.0
	storm.depth_boost = 0.12
	storm.flicker = 0.55

	var snow := _def(&"snow")
	snow.light_scale = 0.78
	snow.ambient_scale = 1.15
	snow.fog_scale = 3.4
	snow.fog_add = 0.006
	snow.tint = Color(0.86, 0.90, 0.98)
	snow.tint_amount = 0.55
	snow.star_visibility = 0.05
	snow.depth_boost = 0.14

	var fog := _def(&"fog")
	fog.light_scale = 0.82
	fog.ambient_scale = 1.10
	fog.fog_scale = 6.0
	fog.fog_add = 0.014
	fog.tint = Color(0.74, 0.78, 0.82)
	fog.tint_amount = 0.60
	fog.star_visibility = 0.10
	fog.depth_boost = 0.20

	var ash := _def(&"ash")
	ash.light_scale = 0.48
	ash.ambient_scale = 0.80
	ash.fog_scale = 4.0
	ash.fog_add = 0.010
	ash.tint = Color(0.40, 0.30, 0.26)
	ash.tint_amount = 0.70
	ash.star_visibility = 0.0
	ash.depth_boost = 0.16

	var sand := _def(&"sandstorm")
	sand.light_scale = 0.55
	sand.ambient_scale = 0.95
	sand.fog_scale = 5.5
	sand.fog_add = 0.016
	sand.tint = Color(0.80, 0.64, 0.36)
	sand.tint_amount = 0.75
	sand.star_visibility = 0.0
	sand.depth_boost = 0.22

	var acid := _def(&"acid")
	acid.light_scale = 0.60
	acid.ambient_scale = 0.90
	acid.fog_scale = 3.0
	acid.fog_add = 0.008
	acid.tint = Color(0.56, 0.76, 0.30)
	acid.tint_amount = 0.65
	acid.star_visibility = 0.05
	acid.depth_boost = 0.10

	var meteor := _def(&"meteor")
	meteor.light_scale = 0.85
	meteor.ambient_scale = 1.05
	meteor.fog_scale = 1.4
	meteor.tint = Color(1.0, 0.62, 0.34)
	meteor.tint_amount = 0.40
	meteor.star_visibility = 0.9
	meteor.flicker = 0.22
