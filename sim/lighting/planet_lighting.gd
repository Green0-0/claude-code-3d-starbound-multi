## Per-planet lighting mood: sky palette, ambient tint, fog and — importantly —
## the *daylight curve*, which is what stops every planet feeling like Earth.
##
## `Game.daylight` is the raw solar term (0 at midnight, 1 at noon). Every
## planet remaps it: a midnight world clamps it to a permanent dusk, a volcanic
## world never gets truly dark because the ground glows, an airless moon snaps
## between full sun and black with no dawn at all.
##
## The palette is read from `World.planet["type"]` (the metadata `Universe`
## hands `World.create_world`). Unknown types fall back to `&"default"`, and a
## planet may override any field directly in its meta under `"lighting"`.
##
## `Events.travel_finished` cross-fades to the new palette over
## `transition_time` seconds so arriving somewhere reads as a change of place
## rather than a hard cut.
class_name LitPlanet
extends Node

## One planet's complete lighting mood. Every field is blendable.
class Palette extends RefCounted:
	var key: StringName = &"default"
	# ---- sky -------------------------------------------------------------
	var sky_top := Color(0.16, 0.34, 0.68)
	var sky_horizon := Color(0.62, 0.72, 0.86)
	var sky_low := Color(0.07, 0.07, 0.10)     ## below the horizon line
	var night_top := Color(0.015, 0.02, 0.055)
	var night_horizon := Color(0.05, 0.07, 0.13)
	# ---- lights ----------------------------------------------------------
	var sun_color := Color(1.0, 0.96, 0.88)
	var sun_energy := 1.15
	var dawn_color := Color(1.0, 0.62, 0.36)
	var moon_color := Color(0.62, 0.72, 1.0)
	var moon_energy := 0.16
	var fill_color := Color(0.62, 0.70, 0.90)
	var fill_energy := 0.25
	## 0 = soft, wrapped light. 1 = airless: no fill, black shadows.
	var hardness := 0.0
	# ---- ambient / fog ---------------------------------------------------
	var ambient_day := Color(0.60, 0.66, 0.78)
	var ambient_night := Color(0.10, 0.13, 0.22)
	var ambient_energy := 0.72
	var fog_day := Color(0.62, 0.72, 0.86)
	var fog_night := Color(0.06, 0.08, 0.14)
	var fog_density := 0.0040
	# ---- voxel light -----------------------------------------------------
	## Floor under `Lighting.factor_at` — the "you can still see the walls" term.
	var floor_light := 0.055
	## Remap of Game.daylight: out = min + (max-min) * pow(raw, gamma).
	var day_min := 0.0
	var day_max := 1.0
	var day_gamma := 1.0
	# ---- sky decoration --------------------------------------------------
	var star_alpha := 1.0        ## how bright the starfield gets at midnight
	var star_density := 1.0
	var star_color := Color(1.0, 1.0, 1.0)
	var moon_visible := true
	var moon_size := 0.055
	var moon_tint := Color(0.92, 0.93, 1.0)

	func blend(o: Palette, t: float) -> Palette:
		var p := Palette.new()
		p.key = o.key if t >= 0.5 else key
		p.sky_top = sky_top.lerp(o.sky_top, t)
		p.sky_horizon = sky_horizon.lerp(o.sky_horizon, t)
		p.sky_low = sky_low.lerp(o.sky_low, t)
		p.night_top = night_top.lerp(o.night_top, t)
		p.night_horizon = night_horizon.lerp(o.night_horizon, t)
		p.sun_color = sun_color.lerp(o.sun_color, t)
		p.sun_energy = lerpf(sun_energy, o.sun_energy, t)
		p.dawn_color = dawn_color.lerp(o.dawn_color, t)
		p.moon_color = moon_color.lerp(o.moon_color, t)
		p.moon_energy = lerpf(moon_energy, o.moon_energy, t)
		p.fill_color = fill_color.lerp(o.fill_color, t)
		p.fill_energy = lerpf(fill_energy, o.fill_energy, t)
		p.hardness = lerpf(hardness, o.hardness, t)
		p.ambient_day = ambient_day.lerp(o.ambient_day, t)
		p.ambient_night = ambient_night.lerp(o.ambient_night, t)
		p.ambient_energy = lerpf(ambient_energy, o.ambient_energy, t)
		p.fog_day = fog_day.lerp(o.fog_day, t)
		p.fog_night = fog_night.lerp(o.fog_night, t)
		p.fog_density = lerpf(fog_density, o.fog_density, t)
		p.floor_light = lerpf(floor_light, o.floor_light, t)
		p.day_min = lerpf(day_min, o.day_min, t)
		p.day_max = lerpf(day_max, o.day_max, t)
		p.day_gamma = lerpf(day_gamma, o.day_gamma, t)
		p.star_alpha = lerpf(star_alpha, o.star_alpha, t)
		p.star_density = lerpf(star_density, o.star_density, t)
		p.star_color = star_color.lerp(o.star_color, t)
		p.moon_visible = o.moon_visible if t >= 0.5 else moon_visible
		p.moon_size = lerpf(moon_size, o.moon_size, t)
		p.moon_tint = moon_tint.lerp(o.moon_tint, t)
		return p

	func apply_overrides(d: Dictionary) -> void:
		for k: String in d:
			if k in self:
				set(k, d[k])


## Seconds a planet-to-planet cross-fade takes.
var transition_time := 1.6

var palettes: Dictionary = {}      ## StringName -> Palette
var current: Palette = null

var _from: Palette = null
var _to: Palette = null
var _t := 1.0


func _ready() -> void:
	_build_palettes()
	current = palettes[&"default"]
	_to = current
	_from = current
	Events.travel_finished.connect(_on_travel_finished)
	Events.world_ready.connect(func(_id: String) -> void: _adopt(false))


func _process(delta: float) -> void:
	if _t >= 1.0:
		return
	_t = minf(1.0, _t + delta / maxf(0.05, transition_time))
	var e := ease(_t, 0.6)
	current = _from.blend(_to, e)


func _on_travel_finished(_planet_id: String) -> void:
	_adopt(true)


## Pick the palette for the world that is loaded now.
func _adopt(smooth: bool) -> void:
	var meta: Dictionary = World.planet if World != null else {}
	var key := StringName(str(meta.get("type", "default")).to_lower())
	var p: Palette = palettes.get(key)
	if p == null:
		p = palettes.get(_alias(key), palettes[&"default"])
	var over: Variant = meta.get("lighting")
	if over is Dictionary:
		var clone := p.blend(p, 0.0)
		clone.apply_overrides(over)
		p = clone
	_from = current if current != null else p
	_to = p
	_t = 0.0 if smooth else 1.0
	if not smooth:
		current = p


## Map the many names worldgen/space may use onto the palettes we define.
func _alias(key: StringName) -> StringName:
	match key:
		&"garden", &"lush", &"plains", &"grassland", &"temperate":
			return &"forest"
		&"snow", &"arctic", &"frozen", &"ice", &"glacier":
			return &"tundra"
		&"volcanic", &"lava", &"inferno", &"hell", &"scorched":
			return &"magma"
		&"luna", &"airless", &"vacuum", &"asteroid", &"rock":
			return &"moon"
		&"dark", &"shadow", &"eternal_night", &"void":
			return &"midnight"
		&"radioactive", &"irradiated", &"acid", &"swamp":
			return &"toxic"
		&"sea", &"water", &"aquatic":
			return &"ocean"
		&"savannah", &"badlands", &"arid", &"dune":
			return &"desert"
		&"crystal", &"gemstone", &"prism":
			return &"alien"
		&"barren", &"dead", &"wasteland":
			return &"barren"
	return &"default"


# ============================================================== read by others
## Remap the raw solar term through this planet's curve.
func daylight_curve(raw: float) -> float:
	var p := current
	if p == null:
		return raw
	var shaped := pow(clampf(raw, 0.0, 1.0), maxf(0.01, p.day_gamma))
	return clampf(p.day_min + (p.day_max - p.day_min) * shaped, 0.0, 1.0)


## Minimum `factor_at` value on this planet.
func ambient_floor() -> float:
	return current.floor_light if current != null else 0.055


func palette() -> Palette:
	return current if current != null else palettes[&"default"]


# =================================================================== the table
func _def(key: StringName) -> Palette:
	var p := Palette.new()
	p.key = key
	palettes[key] = p
	return p


func _build_palettes() -> void:
	# ---------------------------------------------------------------- default
	_def(&"default")

	# ---------------------------------------------------------------- forest
	var forest := _def(&"forest")
	forest.sky_top = Color(0.15, 0.36, 0.72)
	forest.sky_horizon = Color(0.66, 0.78, 0.90)
	forest.ambient_day = Color(0.62, 0.70, 0.76)
	forest.fog_day = Color(0.66, 0.76, 0.88)
	forest.fog_density = 0.0038
	forest.sun_color = Color(1.0, 0.97, 0.90)

	# ---------------------------------------------------------------- desert
	var desert := _def(&"desert")
	desert.sky_top = Color(0.30, 0.50, 0.78)
	desert.sky_horizon = Color(0.92, 0.82, 0.62)
	desert.sun_color = Color(1.0, 0.94, 0.78)
	desert.sun_energy = 1.35
	desert.ambient_day = Color(0.80, 0.72, 0.58)
	desert.ambient_night = Color(0.10, 0.12, 0.20)
	desert.fog_day = Color(0.88, 0.80, 0.62)
	desert.fog_density = 0.0026
	desert.hardness = 0.35
	desert.fill_energy = 0.16
	desert.day_max = 1.0
	desert.star_alpha = 1.1

	# ---------------------------------------------------------------- tundra
	var tundra := _def(&"tundra")
	tundra.sky_top = Color(0.42, 0.58, 0.80)
	tundra.sky_horizon = Color(0.84, 0.89, 0.95)
	tundra.sun_color = Color(0.92, 0.96, 1.0)
	tundra.sun_energy = 0.95
	tundra.ambient_day = Color(0.72, 0.80, 0.90)
	tundra.ambient_night = Color(0.12, 0.17, 0.28)
	tundra.fog_day = Color(0.82, 0.88, 0.95)
	tundra.fog_density = 0.0072
	tundra.floor_light = 0.08
	tundra.moon_color = Color(0.72, 0.82, 1.0)

	# ---------------------------------------------------------------- jungle
	var jungle := _def(&"jungle")
	jungle.sky_top = Color(0.20, 0.44, 0.62)
	jungle.sky_horizon = Color(0.66, 0.80, 0.68)
	jungle.sun_color = Color(0.96, 1.0, 0.86)
	jungle.ambient_day = Color(0.50, 0.66, 0.48)
	jungle.fog_day = Color(0.56, 0.72, 0.58)
	jungle.fog_density = 0.0090
	jungle.day_max = 0.94

	# ---------------------------------------------------------------- ocean
	var ocean := _def(&"ocean")
	ocean.sky_top = Color(0.12, 0.36, 0.70)
	ocean.sky_horizon = Color(0.56, 0.78, 0.88)
	ocean.ambient_day = Color(0.48, 0.68, 0.80)
	ocean.fog_day = Color(0.42, 0.66, 0.80)
	ocean.fog_density = 0.0130
	ocean.floor_light = 0.07

	# ---------------------------------------------------------------- toxic
	var toxic := _def(&"toxic")
	toxic.sky_top = Color(0.22, 0.34, 0.16)
	toxic.sky_horizon = Color(0.62, 0.74, 0.26)
	toxic.night_top = Color(0.04, 0.07, 0.03)
	toxic.night_horizon = Color(0.10, 0.16, 0.06)
	toxic.sun_color = Color(0.86, 1.0, 0.62)
	toxic.sun_energy = 0.90
	toxic.dawn_color = Color(0.80, 0.96, 0.40)
	toxic.ambient_day = Color(0.48, 0.62, 0.32)
	toxic.ambient_night = Color(0.12, 0.22, 0.10)
	toxic.fog_day = Color(0.46, 0.62, 0.28)
	toxic.fog_night = Color(0.08, 0.14, 0.06)
	toxic.fog_density = 0.0165
	toxic.floor_light = 0.085
	toxic.day_min = 0.10
	toxic.day_max = 0.88
	toxic.star_color = Color(0.80, 1.0, 0.70)
	toxic.moon_tint = Color(0.75, 1.0, 0.60)

	# ---------------------------------------------------------------- magma
	# A volcanic world: red ambient that never goes out, because the ground
	# itself is the light source.
	var magma := _def(&"magma")
	magma.sky_top = Color(0.26, 0.07, 0.06)
	magma.sky_horizon = Color(0.72, 0.22, 0.08)
	magma.night_top = Color(0.10, 0.02, 0.02)
	magma.night_horizon = Color(0.32, 0.07, 0.03)
	magma.sun_color = Color(1.0, 0.60, 0.34)
	magma.sun_energy = 1.05
	magma.dawn_color = Color(1.0, 0.34, 0.16)
	magma.moon_color = Color(1.0, 0.44, 0.26)
	magma.moon_energy = 0.24
	magma.fill_color = Color(1.0, 0.40, 0.22)
	magma.fill_energy = 0.40
	magma.ambient_day = Color(0.72, 0.34, 0.22)
	magma.ambient_night = Color(0.40, 0.13, 0.07)
	magma.ambient_energy = 0.85
	magma.fog_day = Color(0.52, 0.20, 0.12)
	magma.fog_night = Color(0.24, 0.07, 0.04)
	magma.fog_density = 0.0180
	magma.floor_light = 0.14
	magma.day_min = 0.24
	magma.day_max = 0.92
	magma.star_alpha = 0.35
	magma.star_color = Color(1.0, 0.72, 0.55)

	# ---------------------------------------------------------------- moon
	# Airless: no atmosphere means no scatter — a black sky in broad daylight,
	# hard shadows, no fill light, and stars that never fade.
	var moon := _def(&"moon")
	moon.sky_top = Color(0.0, 0.0, 0.0)
	moon.sky_horizon = Color(0.02, 0.02, 0.035)
	moon.sky_low = Color(0.0, 0.0, 0.0)
	moon.night_top = Color(0.0, 0.0, 0.0)
	moon.night_horizon = Color(0.01, 0.01, 0.02)
	moon.sun_color = Color(1.0, 1.0, 0.98)
	moon.sun_energy = 1.5
	moon.dawn_color = Color(1.0, 1.0, 0.98)
	moon.fill_energy = 0.0
	moon.moon_energy = 0.05
	moon.hardness = 1.0
	moon.ambient_day = Color(0.16, 0.17, 0.22)
	moon.ambient_night = Color(0.03, 0.03, 0.05)
	moon.ambient_energy = 0.30
	moon.fog_day = Color(0.02, 0.02, 0.04)
	moon.fog_night = Color(0.0, 0.0, 0.01)
	moon.fog_density = 0.0
	moon.floor_light = 0.02
	moon.day_gamma = 0.45          ## no dawn: the terminator is a hard edge
	moon.star_alpha = 1.0
	moon.star_density = 1.6
	moon.moon_visible = false

	# ---------------------------------------------------------------- barren
	var barren := _def(&"barren")
	barren.sky_top = Color(0.24, 0.24, 0.30)
	barren.sky_horizon = Color(0.56, 0.50, 0.46)
	barren.sun_color = Color(1.0, 0.92, 0.84)
	barren.sun_energy = 1.05
	barren.ambient_day = Color(0.48, 0.46, 0.46)
	barren.fog_day = Color(0.50, 0.47, 0.45)
	barren.fog_density = 0.0060
	barren.hardness = 0.6
	barren.fill_energy = 0.12
	barren.floor_light = 0.04

	# ---------------------------------------------------------------- midnight
	# A world in permanent twilight. `day_max` is the whole trick: noon here is
	# dimmer than dusk anywhere else, and it is never, ever bright.
	var midnight := _def(&"midnight")
	midnight.sky_top = Color(0.03, 0.02, 0.08)
	midnight.sky_horizon = Color(0.13, 0.08, 0.24)
	midnight.night_top = Color(0.010, 0.008, 0.030)
	midnight.night_horizon = Color(0.06, 0.03, 0.13)
	midnight.sun_color = Color(0.52, 0.46, 0.78)
	midnight.sun_energy = 0.34
	midnight.dawn_color = Color(0.52, 0.26, 0.62)
	midnight.moon_color = Color(0.60, 0.52, 1.0)
	midnight.moon_energy = 0.30
	midnight.fill_color = Color(0.40, 0.34, 0.70)
	midnight.fill_energy = 0.16
	midnight.ambient_day = Color(0.18, 0.16, 0.32)
	midnight.ambient_night = Color(0.07, 0.06, 0.16)
	midnight.ambient_energy = 0.55
	midnight.fog_day = Color(0.12, 0.09, 0.24)
	midnight.fog_night = Color(0.04, 0.03, 0.10)
	midnight.fog_density = 0.0150
	midnight.floor_light = 0.10
	midnight.day_min = 0.05
	midnight.day_max = 0.30       ## never bright
	midnight.day_gamma = 1.4
	midnight.star_alpha = 1.2
	midnight.star_density = 1.4
	midnight.star_color = Color(0.86, 0.82, 1.0)
	midnight.moon_size = 0.085
	midnight.moon_tint = Color(0.78, 0.70, 1.0)

	# ---------------------------------------------------------------- alien
	var alien := _def(&"alien")
	alien.sky_top = Color(0.26, 0.12, 0.42)
	alien.sky_horizon = Color(0.78, 0.44, 0.72)
	alien.night_top = Color(0.04, 0.02, 0.10)
	alien.night_horizon = Color(0.16, 0.06, 0.24)
	alien.sun_color = Color(0.92, 0.78, 1.0)
	alien.dawn_color = Color(1.0, 0.46, 0.86)
	alien.moon_color = Color(0.80, 0.60, 1.0)
	alien.ambient_day = Color(0.58, 0.46, 0.72)
	alien.ambient_night = Color(0.14, 0.10, 0.26)
	alien.fog_day = Color(0.58, 0.38, 0.68)
	alien.fog_night = Color(0.10, 0.05, 0.18)
	alien.fog_density = 0.0110
	alien.floor_light = 0.09
	alien.star_color = Color(1.0, 0.86, 1.0)
	alien.moon_size = 0.075
