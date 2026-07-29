## The weather state machine. One weather at a time per planet, chosen from a
## per-biome table, with a ramping intensity and real gameplay consequences.
##
## ## Weather ids
##
## `clear` `cloudy` `fog` `rain` `storm` `snow` `blizzard` `sandstorm`
## `ash_fall` `meteor_shower` `acid_rain`
##
## Every change is announced with `Events.weather_changed(id, intensity)`; the
## FX agent renders the particles and the lighting agent dims the sky. This file
## never draws anything — it only decides what is happening and applies the
## consequences: wetness, cold, blindness, corrosion, lightning fires and
## meteor impacts.
##
## ## Why intensity ramps
##
## A storm that snaps to full strength looks like a bug. Every state fades in
## over `RAMP` seconds and out over the last `RAMP` seconds of its life, so the
## particle count, the temperature shift and the visibility penalty all breathe.
class_name SrvWeather
extends Node

const RAMP := 6.0

## `id -> {temp, visibility, wet, weight-independent gameplay flags}`.
## `temp` is added to the environment's ambient reading at full intensity.
const PROFILES := {
	&"clear":         {"temp": 0.0,   "vis": 1.0,  "wet": 0.0, "min": 90.0, "max": 300.0},
	&"cloudy":        {"temp": -0.05, "vis": 0.92, "wet": 0.0, "min": 60.0, "max": 200.0},
	&"fog":           {"temp": -0.08, "vis": 0.45, "wet": 0.2, "min": 60.0, "max": 180.0},
	&"rain":          {"temp": -0.18, "vis": 0.7,  "wet": 1.0, "min": 60.0, "max": 210.0},
	&"storm":         {"temp": -0.25, "vis": 0.55, "wet": 1.0, "min": 45.0, "max": 150.0},
	&"snow":          {"temp": -0.4,  "vis": 0.72, "wet": 0.3, "min": 80.0, "max": 240.0},
	&"blizzard":      {"temp": -0.75, "vis": 0.3,  "wet": 0.4, "min": 45.0, "max": 140.0},
	&"sandstorm":     {"temp": 0.25,  "vis": 0.25, "wet": 0.0, "min": 45.0, "max": 140.0},
	&"ash_fall":      {"temp": 0.3,   "vis": 0.5,  "wet": 0.0, "min": 60.0, "max": 200.0},
	&"meteor_shower": {"temp": 0.15,  "vis": 0.8,  "wet": 0.0, "min": 40.0, "max": 110.0},
	&"acid_rain":     {"temp": 0.05,  "vis": 0.6,  "wet": 0.6, "min": 45.0, "max": 130.0},
}

## Per-biome transition weights. Unknown biomes fall back to `_DEFAULT_TABLE`.
const TABLES := {
	&"forest":    {&"clear": 46, &"cloudy": 22, &"rain": 20, &"storm": 8, &"fog": 4},
	&"plains":    {&"clear": 52, &"cloudy": 22, &"rain": 18, &"storm": 8},
	&"jungle":    {&"clear": 26, &"cloudy": 18, &"rain": 34, &"storm": 16, &"fog": 6},
	&"savannah":  {&"clear": 58, &"cloudy": 16, &"rain": 14, &"storm": 8, &"sandstorm": 4},
	&"desert":    {&"clear": 60, &"cloudy": 10, &"sandstorm": 26, &"storm": 4},
	&"tundra":    {&"clear": 34, &"cloudy": 18, &"snow": 34, &"blizzard": 14},
	&"arctic":    {&"clear": 22, &"cloudy": 14, &"snow": 36, &"blizzard": 28},
	&"ocean":     {&"clear": 34, &"cloudy": 20, &"rain": 26, &"storm": 14, &"fog": 6},
	&"magma":     {&"clear": 30, &"ash_fall": 48, &"meteor_shower": 12, &"cloudy": 10},
	&"volcanic":  {&"clear": 28, &"ash_fall": 50, &"meteor_shower": 14, &"cloudy": 8},
	&"toxic":     {&"clear": 28, &"acid_rain": 44, &"fog": 16, &"cloudy": 12},
	&"alien":     {&"clear": 34, &"cloudy": 18, &"acid_rain": 18, &"meteor_shower": 16, &"fog": 14},
	&"moon":      {&"clear": 64, &"meteor_shower": 36},
	&"barren":    {&"clear": 62, &"meteor_shower": 22, &"sandstorm": 16},
}

const _DEFAULT_TABLE := {&"clear": 55, &"cloudy": 22, &"rain": 15, &"storm": 8}

## Weather never changes faster than this, whatever the table says.
const MIN_HOLD := 25.0

var current: StringName = &"clear"
var intensity := 0.0
var target_intensity := 1.0
var enabled := true

var _elapsed := 0.0
var _duration := 120.0
var _biome: StringName = &"plains"
var _biome_timer := 0.0
var _strike_timer := 0.0
var _hazard_timer := 0.0
var _reported := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = -6
	_rng.randomize()
	Events.world_ready.connect(_on_world_ready)


func _on_world_ready(_planet_id: String) -> void:
	_rng.seed = World.seed_value ^ 0x5EED
	_biome = &"plains"
	_set_state(&"clear", 90.0, true)


# ==================================================================== ticking
func _physics_process(delta: float) -> void:
	if not enabled or Game.paused or not World.ready_flag or Game.player == null:
		return
	var scaled := delta * Game.time_scale

	_biome_timer += delta
	if _biome_timer >= 3.0:
		_biome_timer = 0.0
		_refresh_biome()

	_elapsed += scaled
	_advance_intensity(delta)
	if _elapsed >= _duration:
		_roll_next()

	_apply_effects(delta)

	if absf(intensity - _reported) > 0.06:
		_reported = intensity
		Events.weather_changed.emit(String(current), intensity)


func _advance_intensity(delta: float) -> void:
	var want := target_intensity
	var left := _duration - _elapsed
	if left < RAMP:
		want *= clampf(left / RAMP, 0.0, 1.0)
	intensity = move_toward(intensity, want, delta / RAMP)


func _refresh_biome() -> void:
	if not PlanetGen.has_method(&"biome_at"):
		return
	var p := Const.floor_v(Game.player.global_position)
	var b: StringName = PlanetGen.biome_at(p.x, p.z)
	if b == _biome:
		return
	_biome = b
	# A biome change can invalidate the current weather (a blizzard does not
	# follow you into the desert) — cut it short rather than snapping.
	if not _table().has(current) and current != &"clear":
		_duration = minf(_duration, _elapsed + RAMP)


func _table() -> Dictionary:
	var t: Variant = TABLES.get(_biome)
	if t is Dictionary:
		var known: Dictionary = t
		return known
	# Planet-level override, e.g. a permanently stormy gas giant.
	var forced: Variant = World.planet.get("weather_table")
	if forced is Dictionary:
		var custom: Dictionary = forced
		return custom
	return _DEFAULT_TABLE


func _roll_next() -> void:
	var table := _table()
	var total := 0
	for k: StringName in table:
		total += int(table[k])
	if total <= 0:
		_set_state(&"clear", 120.0, false)
		return
	var roll := _rng.randi_range(1, total)
	var pick: StringName = &"clear"
	for k: StringName in table:
		roll -= int(table[k])
		if roll <= 0:
			pick = k
			break
	# Never immediately repeat a severe weather; give the player a breather.
	if pick == current and pick != &"clear" and pick != &"cloudy":
		pick = &"clear"
	var prof: Dictionary = PROFILES.get(pick, PROFILES[&"clear"])
	var dur := _rng.randf_range(float(prof["min"]), float(prof["max"]))
	_set_state(pick, dur, false)


func _set_state(id: StringName, duration: float, instant: bool) -> void:
	current = id
	_duration = maxf(MIN_HOLD, duration)
	_elapsed = 0.0
	target_intensity = 1.0 if id == &"clear" else _rng.randf_range(0.55, 1.0)
	if instant:
		intensity = target_intensity
	_reported = -1.0
	Events.weather_changed.emit(String(current), intensity)
	if id != &"clear" and id != &"cloudy":
		Events.toast(_announce(id), "info")


static func _announce(id: StringName) -> String:
	match id:
		&"rain": return "Rain sets in."
		&"storm": return "A storm is rolling in."
		&"snow": return "It starts to snow."
		&"blizzard": return "Blizzard! Visibility is gone."
		&"sandstorm": return "Sandstorm incoming."
		&"ash_fall": return "Ash begins to fall."
		&"meteor_shower": return "Meteor shower — find cover."
		&"acid_rain": return "Acid rain. Get inside."
		&"fog": return "Fog rolls across the surface."
		_: return "The weather changes."


## Force a weather for scripting, quests and debug.
func set_weather(id: StringName, duration: float = 120.0, p_intensity: float = 1.0) -> void:
	if not PROFILES.has(id):
		push_warning("[Weather] unknown weather '%s'" % id)
		return
	_set_state(id, duration, true)
	target_intensity = clampf(p_intensity, 0.0, 1.0)
	intensity = target_intensity


# ==================================================================== queries
func profile() -> Dictionary:
	var p: Dictionary = PROFILES.get(current, PROFILES[&"clear"])
	return p


## 0..1 — how far you can see. The camera/lighting agents multiply fog by this.
func visibility() -> float:
	return lerpf(1.0, float(profile()["vis"]), intensity)


## Added to the ambient temperature by `survival/environment.gd`.
func temperature_shift() -> float:
	return float(profile()["temp"]) * intensity


## 0..1 — how much water is falling. Farming uses it to keep soil moist.
func wetness() -> float:
	return float(profile()["wet"]) * intensity


func is_precipitation() -> bool:
	return wetness() > 0.05


func is_severe() -> bool:
	return intensity > 0.5 and current in [&"storm", &"blizzard", &"sandstorm",
		&"meteor_shower", &"acid_rain"]


# ================================================================ consequences
func _apply_effects(delta: float) -> void:
	var player := Game.player
	if player.dead or intensity < 0.15:
		return
	var exposed := Status.environment != null and not Status.environment.is_sheltered()

	if exposed:
		match current:
			&"rain", &"storm":
				Status.apply(&"wet", player, 12.0)
				Status.remove(&"burning", player)
			&"blizzard":
				Status.apply(&"blinded", player, 3.0)
				Status.apply(&"chilled", player, 5.0)
			&"sandstorm":
				Status.apply(&"blinded", player, 3.0)
			&"acid_rain":
				_hazard_timer += delta
				if _hazard_timer >= 2.0:
					_hazard_timer = 0.0
					Status.apply(&"corroded", player, 12.0)
			&"ash_fall":
				if _rng.randf() < delta * 0.05 * intensity:
					Status.apply(&"burning", player, 3.0)

	if current == &"storm":
		_strike_timer += delta
		if _strike_timer >= lerpf(14.0, 4.0, intensity):
			_strike_timer = 0.0
			_lightning_strike()
	elif current == &"meteor_shower":
		_strike_timer += delta
		if _strike_timer >= lerpf(12.0, 3.5, intensity):
			_strike_timer = 0.0
			_meteor_impact()
	else:
		_strike_timer = 0.0

	if is_precipitation() and Status.farming != null:
		Status.farming.rain_tick(delta * wetness())


## Pick an exposed column near the player, in plane space so the bolt always
## lands somewhere the camera can see, and set what it hits on fire.
func _lightning_strike() -> void:
	var player := Game.player
	var lateral := View.lateral_of(player.global_position) + _rng.randf_range(-22.0, 22.0)
	var depth := View.depth_of(player.global_position) + float(_rng.randi_range(-1, 1))
	var probe := View.to_world(Vector2(lateral, player.global_position.y + 30.0), depth)
	var col := Const.floor_v(probe)
	var y := World.surface_y(col.x, col.z, col.y)
	if y < 0:
		return
	var hit := World.normalize(Vector3i(col.x, y, col.z))
	var centre := Vector3(hit) + Vector3(0.5, 1.0, 0.5)

	Events.spawn_particles.emit(&"lightning", centre, 40)
	Events.play_sound.emit(&"thunder", centre)
	Events.screen_shake.emit(0.5, 0.35)

	# Light a fire on top if the block below will burn and fire exists.
	var below := Blocks.get_type(World.get_block(hit))
	var above := hit + Vector3i(0, 1, 0)
	if below.flammable and Blocks.has(&"fire") and World.is_air(above):
		World.set_block(above, Blocks.id(&"fire"))

	for e: VoxelEntity in Game.entities_in_radius(centre, 3.5):
		if e.dead:
			continue
		Status.apply(&"shocked", e, 5.0)
		if below.flammable:
			Status.apply(&"burning", e, 4.0)
		e.apply_damage(18.0, Const.ELEM_ELECTRIC, null)


## A small explosion somewhere near the player, plus a scatter of `burning`.
func _meteor_impact() -> void:
	var player := Game.player
	var lateral := View.lateral_of(player.global_position) + _rng.randf_range(-26.0, 26.0)
	var depth := View.depth_of(player.global_position) + float(_rng.randi_range(-1, 1))
	var probe := View.to_world(Vector2(lateral, player.global_position.y + 20.0), depth)
	var col := Const.floor_v(probe)
	var y := World.surface_y(col.x, col.z, col.y)
	if y < 0:
		return
	var centre := Vector3(World.normalize(Vector3i(col.x, y, col.z))) + Vector3(0.5, 0.5, 0.5)
	Events.spawn_particles.emit(&"meteor", centre + Vector3(0, 12, 0), 24)
	World.explode(centre, 2.0 + intensity, 3.0)
	for e: VoxelEntity in Game.entities_in_radius(centre, 4.0):
		if not e.dead:
			Status.apply(&"burning", e, 5.0)


# ============================================================== serialisation
func save_state() -> Dictionary:
	return {"current": String(current), "elapsed": _elapsed,
		"duration": _duration, "intensity": intensity}


func load_state(d: Dictionary) -> void:
	current = StringName(d.get("current", "clear"))
	if not PROFILES.has(current):
		current = &"clear"
	_elapsed = float(d.get("elapsed", 0.0))
	_duration = maxf(MIN_HOLD, float(d.get("duration", 120.0)))
	intensity = clampf(float(d.get("intensity", 0.0)), 0.0, 1.0)
	target_intensity = intensity
	_reported = -1.0
	Events.weather_changed.emit(String(current), intensity)
