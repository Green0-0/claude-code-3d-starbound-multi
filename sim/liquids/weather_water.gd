## Rain, puddles and snowfall — the weather's effect on the world's water.
##
## Weather *state* belongs to the survival agent. This module is a pure
## consumer: it listens to the shared `Events.weather_changed(weather, intensity)`
## hook, and on world load it politely asks whoever owns the weather what it is
## right now (guarded by `has_method`, so if weather does not exist yet the
## planet is simply clear and nothing here ever runs).
##
## What it does while it is raining:
##
## * **Puddles.** A trickle of water is deposited on sky-exposed ground. One
##   unit at a time, which the solver spreads and then evaporates — so flat
##   ground gets a shimmer that dries up, and a dip collects a real pool.
## * **Filling containers.** Nothing special is needed: an open-topped tank, a
##   walled roof gutter or a hole in the rock is just terrain that water cannot
##   escape from, so the same trickle fills it. Cells that already hold water
##   are topped up preferentially, which makes catchment feel deliberate.
## * **Snow.** When the weather is snow (or the column is a cold biome), a snow
##   block is laid down instead, stacking a few blocks above the terrain height.
## * **Dousing.** Rain puts out exposed fire.
##
## Cost control: samples are taken only inside the streamed slab, only near the
## player, only every [constant SAMPLE_EVERY] sim ticks, and only
## [constant SAMPLES] columns per pass.
class_name LiqWeather
extends RefCounted

## Weather ids that deposit water.
const WET := ["rain", "storm", "thunderstorm", "drizzle", "acid_rain", "monsoon"]
## Weather ids that deposit snow.
const SNOWY := ["snow", "blizzard", "sleet"]
## Weather id -> the liquid it rains, when it is not plain water.
const WEATHER_LIQUID := {
	"acid_rain": &"acid",
}

const SAMPLE_EVERY := 5        ## sim ticks between passes (0.5 s at 10 Hz)
const SAMPLES := 6             ## columns sampled per pass
const RADIUS := 26             ## blocks around the player, in the view plane
const DEPTH_SPREAD := 4        ## layers either side of the play layer
const SCAN_UP := 40            ## how far above the player we look for sky
const SCAN_DOWN := 72          ## how far down we hunt for the surface
const SNOW_STACK := 3          ## max snow blocks above the natural terrain

var weather: String = "clear"
var intensity: float = 0.0

var _rng := RandomNumberGenerator.new()
var _stat_drops := 0
var _stat_snow := 0


func setup() -> void:
	_rng.randomize()
	Events.weather_changed.connect(_on_weather_changed)


## Ask the weather owner for the current state; default to clear.
##
## The survival agent keeps a `SrvWeather` node at `Status.weather` and emits
## `Events.weather_changed` on every change, but it may not exist yet — hence
## the three layers of guard and the "clear" default.
func on_world_ready() -> void:
	weather = "clear"
	intensity = 0.0
	if Status.has_method(&"current_weather"):
		var w: Variant = Status.call(&"current_weather")
		if w is String:
			weather = w
			intensity = 1.0
		elif w is Dictionary:
			weather = String((w as Dictionary).get("weather", "clear"))
			intensity = float((w as Dictionary).get("intensity", 1.0))
		return
	var node: Variant = Status.get(&"weather")
	if node is Object:
		var cur: Variant = (node as Object).get(&"current")
		if cur != null:
			weather = String(cur)
			var inten: Variant = (node as Object).get(&"intensity")
			intensity = float(inten) if inten != null else 1.0


func _on_weather_changed(p_weather: String, p_intensity: float) -> void:
	weather = p_weather
	intensity = clampf(p_intensity, 0.0, 1.0)


func is_raining() -> bool:
	return intensity > 0.05 and WET.has(weather)


func is_snowing() -> bool:
	return intensity > 0.05 and SNOWY.has(weather)


## Manual override, for tests and for the space agent's scripted storms.
func set_weather(p_weather: String, p_intensity: float = 1.0) -> void:
	weather = p_weather
	intensity = clampf(p_intensity, 0.0, 1.0)


func debug_info() -> Dictionary:
	return {"weather": weather, "intensity": intensity,
		"drops": _stat_drops, "snow": _stat_snow}


# --------------------------------------------------------------------- tick
func tick(_dt: float, sim_tick: int) -> void:
	if Game.player == null or not World.ready_flag:
		return
	if sim_tick % SAMPLE_EVERY != 0:
		return
	var wet := is_raining()
	var snowy := is_snowing()
	if not wet and not snowy:
		return
	var liquid := StringName(WEATHER_LIQUID.get(weather, &"water"))
	var samples := maxi(1, int(round(float(SAMPLES) * intensity)))
	for _i in samples:
		_sample_column(liquid, snowy)


func _sample_column(liquid: StringName, snowy: bool) -> void:
	var origin := Game.player.global_position
	# Sample in *plane* space so the band of weather follows the camera in every
	# view, then spread a few layers into the depth axis so the world behind the
	# play plane gets wet too.
	var lateral := Const.lateral_of(origin, View.view) + float(_rng.randi_range(-RADIUS, RADIUS))
	var depth := View.depth_of(origin) + float(_rng.randi_range(-DEPTH_SPREAD, DEPTH_SPREAD))
	var world := Const.from_plane(lateral, origin.y, depth, View.view)
	var x := World.wrap_x(floori(world.x))
	var z := World.wrap_z(floori(world.z))

	var top := mini(Const.WORLD_HEIGHT - 1, floori(origin.y) + SCAN_UP)
	var surface := -1
	for i in SCAN_DOWN:
		var y := top - i
		if y < 0:
			break
		var p := Vector3i(x, y, z)
		if World.chunk_at_block(p) == null:
			continue
		var id := World.get_block(p)
		if id == Const.AIR:
			continue
		if Blocks.is_liquid(id):
			# Open water: rain lands on it and tops it up.
			_deposit(Vector3i(x, y, z), liquid)
			return
		if Blocks.is_solid(id) or Blocks.is_opaque(id):
			surface = y
			break
	if surface < 0:
		return

	var above := Vector3i(x, surface + 1, z)
	var above_id := World.get_block(above)
	# Rain douses exposed fire.
	if above_id != Const.AIR and not Blocks.is_liquid(above_id):
		var bname := Blocks.get_type(above_id).name
		if bname == &"fire" or bname == &"ember":
			World.set_block(above, Const.AIR, true)
			Events.spawn_particles.emit(&"steam", Vector3(above) + Vector3(0.5, 0.5, 0.5), 6)
			Events.play_sound.emit(&"hiss", Vector3(above) + Vector3(0.5, 0.5, 0.5))
		return
	if snowy and _snow(above, surface, x, z):
		return
	_deposit(above, liquid)


func _deposit(pos: Vector3i, liquid: StringName) -> void:
	if LiqBucket.trickle(pos, liquid, 1) > 0:
		_stat_drops += 1
		if _rng.randf() < 0.25:
			Events.spawn_particles.emit(&"rain_splash", Vector3(pos) + Vector3(0.5, 0.1, 0.5), 2)


## Lay a snow block down, up to [constant SNOW_STACK] blocks above the natural
## terrain height so a long blizzard does not bury the planet.
func _snow(above: Vector3i, surface: int, x: int, z: int) -> bool:
	var snow_id := LiqType.resolve_block([&"snow", &"snow_block", &"powder_snow"], &"")
	if snow_id <= 0:
		return false
	if World.get_block(above) != Const.AIR:
		return false
	var natural := surface
	if PlanetGen.has_method(&"height_at"):
		natural = int(PlanetGen.height_at(x, z))
	if surface - natural >= SNOW_STACK:
		return false
	if not World.set_block(above, snow_id, true):
		return false
	_stat_snow += 1
	Events.spawn_particles.emit(&"snow_settle", Vector3(above) + Vector3(0.5, 0.2, 0.5), 3)
	return true
