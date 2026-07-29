## Environmental sound beds. Owned by `Audio`, which adds it as a child.
##
## Seven looping layers — wind, cave, ocean, lava, insects, machinery, rain —
## each a seamless procedurally generated loop whose gain is driven by what is
## actually around the player: how much sky is over their head, how enclosed
## they are, what liquid is nearby, the biome, the weather and the time of day.
## Nothing is scripted; the mix simply follows the world.
##
## Loops are built lazily (one per frame, only when a layer first becomes
## audible) and are `FxSynth.seamless()`-folded so they never click.
##
## `Events.layer_changed` re-evaluates immediately and briefly speeds the
## crossfade up, so stepping one voxel deeper audibly closes the world in.
class_name FxAmbience
extends Node

const SR := FxSynth.SR_LOOP
const LOOP_SEC := 5.0

## All beds, in build priority order.
const BEDS: Array[StringName] = [
	&"wind", &"cave", &"ocean", &"lava", &"insects", &"machine", &"rain",
]

## Sparse probe offsets used to sniff the surroundings without a real query.
const PROBE_UP := [3, 6, 10, 15, 21, 28, 36, 46]

var enabled := true
## How fast bed gains chase their target, in gain units per second.
var settle_rate := 0.5
var master_gain := 1.0

var _players: Dictionary = {}       ## id -> AudioStreamPlayer
var _gain: Dictionary = {}          ## id -> float 0..1
var _target: Dictionary = {}        ## id -> float 0..1
var _built: Dictionary = {}         ## id -> bool
var _forced: StringName = &""
var _eval := 0.0
var _rush := 0.0
var _weather := "clear"
var _weather_intensity := 0.0
var _sky_open := 1.0
var _enclosure := 0.0
var _water_near := 0.0
var _lava_near := 0.0
var _machine_near := 0.0
var _biome: StringName = &""


func _ready() -> void:
	for id in BEDS:
		var p := AudioStreamPlayer.new()
		p.name = "Bed_" + String(id)
		p.bus = "Ambient"
		p.volume_db = -60.0
		add_child(p)
		_players[id] = p
		_gain[id] = 0.0
		_target[id] = 0.0
		_built[id] = false
	Events.weather_changed.connect(_on_weather_changed)
	Events.layer_changed.connect(_on_layer_changed)
	Events.world_unloaded.connect(_on_world_unloaded)


func _process(delta: float) -> void:
	if not enabled:
		return
	_eval -= delta
	if _eval <= 0.0:
		_eval = 0.35
		_sense()
		_choose_targets()
	_rush = maxf(0.0, _rush - delta)
	_ride(delta * (3.0 if _rush > 0.0 else 1.0))
	_build_one()


## Pin a single bed on (`&"cave"`, `&"lava"`, ...) or pass `&""` to release.
func force_bed(id: StringName) -> void:
	_forced = id
	_eval = 0.0


func _on_weather_changed(weather: String, intensity: float) -> void:
	# `lightning` is a transient flash pulse, not a weather state — ignore it.
	if weather == "lightning":
		return
	_weather = weather
	_weather_intensity = clampf(intensity, 0.0, 1.0)
	_eval = 0.0


func _on_layer_changed(_layer: int, _view: int) -> void:
	_eval = 0.0
	_rush = 0.45


func _on_world_unloaded() -> void:
	for id: StringName in BEDS:
		_target[id] = 0.0


# ==================================================================== sensing
func _sense() -> void:
	var world := get_node_or_null(^"/root/World")
	var game := get_node_or_null(^"/root/Game")
	if world == null or game == null or not bool(world.get("ready_flag")):
		return
	var pl = game.get("player")
	if pl == null or not (pl is Node3D):
		return
	var base := Const.floor_v((pl as Node3D).global_position)

	var open := 0
	for dy: int in PROBE_UP:
		if not bool(world.call(&"is_opaque", base + Vector3i(0, dy, 0))):
			open += 1
	_sky_open = float(open) / float(PROBE_UP.size())
	_enclosure = 1.0 - _sky_open

	# One sparse box sweep for liquids and machinery. 27 lookups, ~3 Hz.
	var water := 0
	var lava := 0
	var machine := 0
	for dx in [-5, 0, 5]:
		for dy in [-3, 0, 4]:
			for dz in [-5, 0, 5]:
				var id: int = int(world.call(&"get_block", base + Vector3i(dx, dy, dz)))
				if id == Const.AIR:
					continue
				var bt: BlockType = Blocks.get_type(id)
				if bt == null:
					continue
				if bt.liquid:
					if bt.light > 0 or bt.damage_on_touch > 0.0:
						lava += 1
					else:
						water += 1
				elif bt.category == &"machine" or bt.has_tag(&"machine") or bt.has_tag(&"tech"):
					machine += 1
	_water_near = clampf(float(water) / 6.0, 0.0, 1.0)
	_lava_near = clampf(float(lava) / 4.0, 0.0, 1.0)
	_machine_near = clampf(float(machine) / 3.0, 0.0, 1.0)

	var gen := get_node_or_null(^"/root/PlanetGen")
	if gen != null and gen.has_method(&"biome_at"):
		_biome = gen.call(&"biome_at", base.x, base.z)


func _choose_targets() -> void:
	var game := get_node_or_null(^"/root/Game")
	var night := bool(game.call(&"is_night")) if game != null else false
	var b := String(_biome)
	var lush := 1.0 if (b.findn("forest") >= 0 or b.findn("jungle") >= 0 or b.findn("plain") >= 0 or b.findn("grass") >= 0 or b.findn("swamp") >= 0) else 0.25
	var arid := 1.0 if (b.findn("desert") >= 0 or b.findn("barren") >= 0 or b.findn("moon") >= 0 or b.findn("tundra") >= 0) else 0.4
	var rainy := _weather_intensity if (_weather == "rain" or _weather == "storm") else 0.0
	var snowy := _weather_intensity if (_weather == "snow" or _weather == "sandstorm" or _weather == "ash") else 0.0

	if _forced != &"":
		for id: StringName in BEDS:
			_target[id] = 1.0 if id == _forced else 0.0
		return

	_target[&"wind"] = clampf(_sky_open * (0.35 + 0.45 * arid + 0.5 * snowy), 0.0, 1.0)
	_target[&"cave"] = clampf(_enclosure * _enclosure * 1.15, 0.0, 1.0)
	_target[&"ocean"] = clampf(_water_near * (0.4 + 0.6 * _sky_open), 0.0, 1.0)
	_target[&"lava"] = clampf(_lava_near, 0.0, 1.0)
	_target[&"insects"] = clampf((1.0 if night else 0.15) * _sky_open * lush, 0.0, 1.0)
	_target[&"machine"] = clampf(_machine_near * 0.8, 0.0, 1.0)
	_target[&"rain"] = clampf(rainy * (0.25 + 0.75 * _sky_open), 0.0, 1.0)


func _ride(delta: float) -> void:
	for id: StringName in BEDS:
		var g := float(_gain[id])
		var t := float(_target[id])
		g = move_toward(g, t, settle_rate * delta)
		_gain[id] = g
		var p: AudioStreamPlayer = _players[id]
		var want := g * master_gain
		if want <= 0.002:
			if p.playing:
				p.stop()
			p.volume_db = -60.0
			continue
		if not p.playing and p.stream != null:
			p.play(randf() * LOOP_SEC)
		p.volume_db = linear_to_db(clampf(want, 0.002, 1.0))


## Build at most one loop per frame, and only for beds that want to be heard.
func _build_one() -> void:
	for id: StringName in BEDS:
		if bool(_built[id]):
			continue
		if float(_target[id]) <= 0.01:
			continue
		_built[id] = true
		var p: AudioStreamPlayer = _players[id]
		p.stream = _make_bed(id)
		return


# =================================================================== synthesis
func _make_bed(id: StringName) -> AudioStreamWAV:
	var rng := FxSynth.seeded(id, 0)
	var mono: PackedFloat32Array
	match String(id):
		"wind": mono = _wind(rng)
		"cave": mono = _cave(rng)
		"ocean": mono = _ocean(rng)
		"lava": mono = _lava(rng)
		"insects": mono = _insects(rng)
		"machine": mono = _machine(rng)
		"rain": mono = _rain(rng)
		_: mono = _wind(rng)
	mono = FxSynth.seamless(mono, 0.6, SR)
	mono = FxSynth.normalize(mono, 0.75)
	var pair := FxSynth.stereo_pair(mono, 1.0, SR)
	return FxSynth.to_wav_stereo(pair[0], pair[1], SR, true)


## Two slow out-of-phase LFOs read as gusting far better than one.
func _gusts(buf: PackedFloat32Array, r0: float, r1: float, depth: float) -> PackedFloat32Array:
	var n := buf.size()
	var inv := 1.0 / float(maxi(1, n))
	for i in n:
		var t := float(i) * inv
		var m := 0.5 + 0.5 * sin(TAU * (t * r0))
		var m2 := 0.5 + 0.5 * sin(TAU * (t * r1) + 1.9)
		buf[i] = buf[i] * lerpf(1.0, m * 0.65 + m2 * 0.55, depth)
	return buf


func _wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := FxSynth.osc(FxSynth.Wave.PINK, LOOP_SEC + 0.6, 1.0, -1.0, 1.0, SR, rng)
	b = FxSynth.biquad(b, FxSynth.Filter.BANDPASS, 620.0, 0.55, SR)
	b = _gusts(b, 2.0, 3.0, 0.85)
	var low := FxSynth.osc(FxSynth.Wave.PINK, LOOP_SEC + 0.6, 1.0, -1.0, 0.7, SR, rng)
	low = FxSynth.lowpass1(low, 190.0, SR)
	FxSynth.mix_into(b, low, 0.6, 0.0, SR)
	return b


func _cave(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := FxSynth.osc(FxSynth.Wave.PINK, LOOP_SEC + 0.6, 1.0, -1.0, 1.0, SR, rng)
	b = FxSynth.lowpass1(b, 130.0, SR)
	b = FxSynth.lowpass1(b, 200.0, SR)
	b = _gusts(b, 1.0, 2.0, 0.5)
	b = FxSynth.gain(b, 1.4)
	for i in 4:
		var drip := FxSynth.osc(FxSynth.Wave.SINE, 0.10,
				rng.randf_range(1100.0, 2900.0), rng.randf_range(600.0, 1400.0), 0.7, SR)
		drip = FxSynth.perc(drip, 0.002, 3.2, SR)
		drip = FxSynth.reverb(drip, 0.9, 0.25, 0.5, SR)
		FxSynth.mix_into(b, drip, 0.30, rng.randf() * (LOOP_SEC - 0.4), SR)
	return b


func _ocean(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := FxSynth.osc(FxSynth.Wave.PINK, LOOP_SEC + 0.6, 1.0, -1.0, 1.0, SR, rng)
	b = FxSynth.biquad(b, FxSynth.Filter.LOWPASS, 900.0, 0.7, SR)
	b = _gusts(b, 1.0, 1.0, 0.9)
	var hiss := FxSynth.noise(LOOP_SEC + 0.6, 0.5, rng, SR)
	hiss = FxSynth.biquad(hiss, FxSynth.Filter.BANDPASS, 3400.0, 0.6, SR)
	hiss = _gusts(hiss, 2.0, 1.0, 0.95)
	FxSynth.mix_into(b, hiss, 0.45, 0.0, SR)
	return b


func _lava(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := FxSynth.osc(FxSynth.Wave.PINK, LOOP_SEC + 0.6, 1.0, -1.0, 1.0, SR, rng)
	b = FxSynth.lowpass1(b, 105.0, SR)
	b = FxSynth.gain(b, 1.6)
	b = _gusts(b, 3.0, 5.0, 0.4)
	for i in 9:
		var pop := FxSynth.osc(FxSynth.Wave.SINE, 0.11,
				rng.randf_range(110.0, 300.0), rng.randf_range(45.0, 90.0), 0.8, SR)
		pop = FxSynth.perc(pop, 0.003, 2.6, SR)
		FxSynth.mix_into(b, pop, 0.32, rng.randf() * (LOOP_SEC - 0.3), SR)
	b = FxSynth.distort(b, 1.6)
	return b


func _insects(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := FxSynth.buffer(LOOP_SEC + 0.6, SR)
	# A steady cricket trill plus scattered individual chirps.
	var trill := FxSynth.noise(LOOP_SEC + 0.6, 0.5, rng, SR)
	trill = FxSynth.biquad(trill, FxSynth.Filter.BANDPASS, 4800.0, 6.0, SR)
	trill = FxSynth.tremolo(trill, 38.0, 1.0, SR)
	trill = _gusts(trill, 2.0, 3.0, 0.6)
	FxSynth.mix_into(b, trill, 0.5, 0.0, SR)
	for i in 14:
		var chirp := FxSynth.osc(FxSynth.Wave.SINE, 0.09,
				rng.randf_range(3200.0, 6200.0), rng.randf_range(3000.0, 5200.0), 0.6, SR)
		chirp = FxSynth.tremolo(chirp, rng.randf_range(45.0, 80.0), 1.0, SR)
		chirp = FxSynth.perc(chirp, 0.01, 1.8, SR)
		FxSynth.mix_into(b, chirp, 0.35, rng.randf() * (LOOP_SEC - 0.2), SR)
	return b


func _machine(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := FxSynth.osc(FxSynth.Wave.SAW, LOOP_SEC + 0.6, 58.0, -1.0, 0.5, SR)
	b = FxSynth.lowpass1(b, 420.0, SR)
	var whine := FxSynth.osc(FxSynth.Wave.SINE, LOOP_SEC + 0.6, 1740.0, -1.0, 0.10, SR)
	FxSynth.mix_into(b, whine, 0.5, 0.0, SR)
	var hiss := FxSynth.noise(LOOP_SEC + 0.6, 0.25, rng, SR)
	hiss = FxSynth.biquad(hiss, FxSynth.Filter.BANDPASS, 2600.0, 1.2, SR)
	FxSynth.mix_into(b, hiss, 0.4, 0.0, SR)
	for i in 5:
		var clank := FxSynth.resonator(0.18, rng.randf_range(500.0, 1600.0), 0.08, 0.6, rng, SR)
		FxSynth.mix_into(b, clank, 0.3, float(i) * (LOOP_SEC / 5.0) + rng.randf() * 0.2, SR)
	return b


func _rain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := FxSynth.noise(LOOP_SEC + 0.6, 1.0, rng, SR)
	b = FxSynth.biquad(b, FxSynth.Filter.BANDPASS, 3000.0, 0.5, SR)
	b = _gusts(b, 1.0, 2.0, 0.35)
	for i in 40:
		var drop := FxSynth.noise(0.012, 1.0, rng, SR)
		drop = FxSynth.biquad(drop, FxSynth.Filter.BANDPASS, rng.randf_range(1800.0, 6000.0), 3.0, SR)
		drop = FxSynth.perc(drop, 0.0004, 4.0, SR)
		FxSynth.mix_into(b, drop, 0.30, rng.randf() * (LOOP_SEC - 0.05), SR)
	return b
