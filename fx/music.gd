## Procedural adaptive music. Owned by `Audio`, which adds it as a child.
##
## Each situation (explore / night / underground / combat / boss / ship /
## outpost / menu) is a tiny piece of music theory: a root, a mode, a tempo and
## a chord progression. From that we render **two short loopable phrases** — a
## harmonic *bed* and a melodic *lead* — and simply loop them. Rendering a fixed
## phrase rather than streaming a generator forever is the whole trick: the CPU
## cost is a few hundred milliseconds once per track, spread over frames, and
## then playback is free.
##
## Two players per layer give hard-free crossfades, and `intensity` (pushed up
## by combat) rides the lead layer so the arrangement thickens without the
## harmony ever changing underneath the player.
class_name FxMusic
extends Node

const SR := FxSynth.SR_LOOP
const BEATS_PER_BAR := 4

## Church modes plus the two pentatonics, as semitone offsets from the root.
## Scale-degree offsets the melody walks through, chord tones first.
const MELODY_STEPS: Array[int] = [0, 2, 4, 1, 5, 3]

const SCALES := {
	"major": [0, 2, 4, 5, 7, 9, 11],
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"penta_minor": [0, 3, 5, 7, 10],
	"penta_major": [0, 2, 4, 7, 9],
	"whole": [0, 2, 4, 6, 8, 10],
}

## `prog` entries are scale degrees; chords are built in thirds off the mode,
## so a progression is legal in every key without a lookup table.
const TRACKS := {
	&"explore": {
		"root": 57.0, "scale": "lydian", "bpm": 78.0, "bars": 4,
		"prog": [0, 4, 5, 3], "lead": 0.55, "perc": 0.0, "timbre": "soft",
		"bright": 2600.0, "notes": 10,
	},
	&"night": {
		"root": 52.0, "scale": "dorian", "bpm": 58.0, "bars": 4,
		"prog": [0, 5, 3, 5], "lead": 0.35, "perc": 0.0, "timbre": "glass",
		"bright": 1800.0, "notes": 6,
	},
	&"underground": {
		"root": 45.0, "scale": "phrygian", "bpm": 52.0, "bars": 4,
		"prog": [0, 1, 0, 6], "lead": 0.22, "perc": 0.0, "timbre": "dark",
		"bright": 900.0, "notes": 5,
	},
	&"combat": {
		"root": 50.0, "scale": "penta_minor", "bpm": 132.0, "bars": 2,
		"prog": [0, 3], "lead": 0.9, "perc": 0.9, "timbre": "hard",
		"bright": 3400.0, "notes": 14,
	},
	&"boss": {
		"root": 45.0, "scale": "phrygian", "bpm": 148.0, "bars": 2,
		"prog": [0, 1], "lead": 1.0, "perc": 1.0, "timbre": "hard",
		"bright": 4200.0, "notes": 16,
	},
	&"ship": {
		"root": 60.0, "scale": "lydian", "bpm": 68.0, "bars": 4,
		"prog": [0, 3, 4, 3], "lead": 0.45, "perc": 0.0, "timbre": "glass",
		"bright": 3200.0, "notes": 8,
	},
	&"outpost": {
		"root": 55.0, "scale": "mixolydian", "bpm": 98.0, "bars": 4,
		"prog": [0, 4, 3, 4], "lead": 0.6, "perc": 0.35, "timbre": "soft",
		"bright": 2800.0, "notes": 12,
	},
	&"menu": {
		"root": 60.0, "scale": "penta_major", "bpm": 62.0, "bars": 4,
		"prog": [0, 3, 4, 0], "lead": 0.4, "perc": 0.0, "timbre": "glass",
		"bright": 3000.0, "notes": 7,
	},
	&"space": {
		"root": 48.0, "scale": "whole", "bpm": 54.0, "bars": 4,
		"prog": [0, 2, 4, 2], "lead": 0.3, "perc": 0.0, "timbre": "glass",
		"bright": 2200.0, "notes": 5,
	},
}

## Biome `music` keys (see `worldgen/biome.gd`) folded onto the situations.
const TRACK_ALIASES := {
	&"music_calm": &"explore", &"music_forest": &"explore",
	&"music_desert": &"explore", &"music_tundra": &"night",
	&"music_ocean": &"night", &"music_jungle": &"outpost",
	&"music_volcanic": &"combat", &"music_alien": &"space",
	&"music_barren": &"space", &"music_cave": &"underground",
	&"music_dark": &"underground", &"music_boss": &"boss",
	&"music_ship": &"ship", &"music_town": &"outpost",
	&"music_menu": &"menu", &"exploration": &"explore",
	&"cave": &"underground", &"battle": &"combat",
	&"jukebox": &"outpost", &"music_jukebox": &"outpost",
	&"title": &"menu", &"starmap": &"space", &"music_space": &"space",
}

## Seconds of crossfade when the situation changes.
var fade_time := 2.6
## 0..1 — arrangement density. Combat drives this, or set it by hand.
var intensity := 0.35
## Set false to leave track selection entirely to `play_track()`.
var auto_select := true
var base_db := -4.0

var current: StringName = &""
var _requested: StringName = &""
var _cache: Dictionary = {}          ## track -> {"bed": AudioStreamWAV, "lead": AudioStreamWAV}
var _rendering: StringName = &""
var _slot := 0
var _bed: Array[AudioStreamPlayer] = []
var _lead: Array[AudioStreamPlayer] = []
var _target_db := PackedFloat32Array()
var _combat_until := 0.0
## Deliberately late: the first seconds of a run are the busiest frames in the
## game, and rendering a phrase into them would be felt.
var _eval_timer := 5.0
var _boss_until := 0.0
var _forced := false


func _ready() -> void:
	for i in 2:
		var b := AudioStreamPlayer.new()
		b.name = "Bed%d" % i
		b.bus = "Music"
		b.volume_db = -60.0
		add_child(b)
		_bed.append(b)
		var l := AudioStreamPlayer.new()
		l.name = "Lead%d" % i
		l.bus = "Music"
		l.volume_db = -60.0
		add_child(l)
		_lead.append(l)
	_target_db.resize(4)
	for i in 4:
		_target_db[i] = -60.0
	Events.player_damaged.connect(_on_player_damaged)
	Events.entity_damaged.connect(_on_entity_damaged)
	Events.travel_started.connect(_on_travel_started)
	Events.travel_finished.connect(_on_travel_finished)
	Events.ship_boarded.connect(func() -> void: play_track(&"ship"))
	Events.ship_left.connect(func() -> void: _forced = false)
	Events.world_ready.connect(func(_p: String) -> void: _forced = false)


func _process(delta: float) -> void:
	_ride_volumes(delta)
	_eval_timer -= delta
	if _eval_timer <= 0.0:
		_eval_timer = 1.5
		if auto_select and not _forced:
			var want := _evaluate_situation()
			if want != &"" and want != _requested:
				play_track(want)
		var now := float(Time.get_ticks_msec()) * 0.001
		var want_i := 0.9 if now < _combat_until else 0.35
		intensity = move_toward(intensity, want_i, 0.35)


# ==================================================================== control
## Switch to a track. Accepts a situation key or a biome `music_*` key.
func play_track(track: StringName) -> void:
	var key := _canon(track)
	if key == &"" or key == _requested:
		return
	_requested = key
	if _cache.has(key):
		_swap_to(key)
	elif _rendering != key:
		_render_track(key)


## Pin the music to one track until `release()` (used by cutscenes and the ship).
func force_track(track: StringName) -> void:
	_forced = true
	play_track(track)


func release() -> void:
	_forced = false


func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)


func stop() -> void:
	_requested = &""
	current = &""
	for i in 2:
		_target_db[i] = -60.0
		_target_db[2 + i] = -60.0


func _canon(track: StringName) -> StringName:
	if TRACKS.has(track):
		return track
	if TRACK_ALIASES.has(track):
		return TRACK_ALIASES[track]
	var s := String(track)
	for k: StringName in TRACKS:
		if s.findn(String(k)) >= 0:
			return k
	return &"explore"


# ================================================================== situation
func _evaluate_situation() -> StringName:
	var now := float(Time.get_ticks_msec()) * 0.001
	if now < _boss_until:
		return &"boss"
	if now < _combat_until:
		return &"combat"
	var game := get_node_or_null(^"/root/Game")
	if game == null:
		return &"explore"
	var pl = game.get("player")
	if pl == null or not (pl is Node3D):
		return &"menu"
	if _is_underground((pl as Node3D).global_position):
		return &"underground"
	if bool(game.call(&"is_night")):
		return &"night"
	return _biome_track((pl as Node3D).global_position)


## Twelve voxels of stone over your head counts as underground. Cheaper and
## more honest than a surface-height query, and it reacts to digging in.
func _is_underground(pos: Vector3) -> bool:
	var world := get_node_or_null(^"/root/World")
	if world == null or not bool(world.get("ready_flag")):
		return false
	var base := Const.floor_v(pos)
	var solid := 0
	for i in 12:
		if bool(world.call(&"is_opaque", base + Vector3i(0, 3 + i * 2, 0))):
			solid += 1
	return solid >= 7


func _biome_track(pos: Vector3) -> StringName:
	var gen := get_node_or_null(^"/root/PlanetGen")
	if gen == null or not gen.has_method(&"biome_at"):
		return &"explore"
	var key: StringName = gen.call(&"biome_at", int(floorf(pos.x)), int(floorf(pos.z)))
	if key == &"":
		return &"explore"
	return _canon(StringName("music_" + String(key)))


func _on_player_damaged(_a: float, _e: String, _s: Node) -> void:
	_combat_until = float(Time.get_ticks_msec()) * 0.001 + 9.0


func _on_entity_damaged(_e: Node, _a: float, _el: String, source: Node) -> void:
	var game := get_node_or_null(^"/root/Game")
	if game != null and source != null and source == game.get("player"):
		_combat_until = float(Time.get_ticks_msec()) * 0.001 + 7.0


func _on_travel_started(_from: String, _to: String) -> void:
	force_track(&"space")


func _on_travel_finished(_planet: String) -> void:
	_forced = false
	_requested = &""


# =================================================================== playback
func _swap_to(key: StringName) -> void:
	var entry: Dictionary = _cache.get(key, {})
	if entry.is_empty():
		return
	var next := 1 - _slot
	_bed[next].stream = entry.get("bed")
	_lead[next].stream = entry.get("lead")
	_bed[next].volume_db = -60.0
	_lead[next].volume_db = -60.0
	_bed[next].play()
	_lead[next].play()
	_target_db[next] = base_db
	_target_db[2 + next] = -60.0        # the lead rides in on `intensity`
	_target_db[_slot] = -60.0
	_target_db[2 + _slot] = -60.0
	_slot = next
	current = key


func _ride_volumes(delta: float) -> void:
	var lead_weight: float = float(TRACKS.get(current, {}).get("lead", 0.5)) if current != &"" else 0.0
	if current != &"":
		_target_db[2 + _slot] = lerpf(-30.0, base_db + 1.0, clampf(intensity * lead_weight * 1.6, 0.0, 1.0))
	var step := 60.0 / maxf(0.1, fade_time) * delta
	for i in 2:
		_ride_one(_bed[i], _target_db[i], step)
		_ride_one(_lead[i], _target_db[2 + i], step)


func _ride_one(p: AudioStreamPlayer, target: float, step: float) -> void:
	if not p.playing and target <= -59.0:
		return
	var v := move_toward(p.volume_db, target, step)
	p.volume_db = v
	if v <= -59.5 and p.playing:
		p.stop()


# =================================================================== rendering
## Renders a track across several frames so a track change never drops one.
func _render_track(key: StringName) -> void:
	if _rendering != &"":
		return
	_rendering = key
	var def: Dictionary = TRACKS.get(key, TRACKS[&"explore"])
	var bpm: float = float(def["bpm"])
	var bars: int = int(def["bars"])
	var beat := 60.0 / bpm
	var bar_sec := beat * float(BEATS_PER_BAR)
	var loop_sec := bar_sec * float(bars)
	var tail := bar_sec * 0.9
	var scale: Array = SCALES.get(String(def["scale"]), SCALES["minor"])
	var prog: Array = def["prog"]
	var root: float = float(def["root"])
	var rng := FxSynth.seeded(key, _planet_seed())

	var bed := FxSynth.buffer(loop_sec + tail, SR)
	var lead := FxSynth.buffer(loop_sec + tail, SR)

	for b in bars:
		var degree: int = int(prog[b % prog.size()])
		var chord := _chord(scale, root, degree)
		_render_chord(bed, chord, b, bar_sec, def, rng)
		_render_bass(bed, chord[0] - 12.0, b, bar_sec, beat, def)
		if not is_inside_tree():
			_rendering = &""
			return
		await get_tree().process_frame

	_render_lead(lead, scale, root, prog, bars, bar_sec, beat, def, rng)
	if not is_inside_tree():
		_rendering = &""
		return
	await get_tree().process_frame
	if float(def.get("perc", 0.0)) > 0.0:
		_render_perc(bed, bars, beat, float(def["perc"]), rng)
		await get_tree().process_frame

	var n := FxSynth.samples(loop_sec, SR)
	bed = _wrap_tail(bed, n)
	lead = _wrap_tail(lead, n)
	bed = FxSynth.lowpass1(bed, float(def.get("bright", 2600.0)) * 1.6, SR)
	bed = FxSynth.normalize(bed, 0.72)
	lead = FxSynth.normalize(lead, 0.62)
	var bp := FxSynth.stereo_pair(bed, 0.9, SR)
	var lp := FxSynth.stereo_pair(lead, 1.2, SR)
	_cache[key] = {
		"bed": FxSynth.to_wav_stereo(bp[0], bp[1], SR, true),
		"lead": FxSynth.to_wav_stereo(lp[0], lp[1], SR, true),
	}
	_rendering = &""
	if _requested == key:
		_swap_to(key)


func _planet_seed() -> int:
	var world := get_node_or_null(^"/root/World")
	return int(world.get("seed_value")) if world != null else 0


## Triad (plus a ninth on top) built in thirds off the mode.
func _chord(scale: Array, root: float, degree: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for step in [0, 2, 4, 6]:
		var i: int = degree + int(step)
		var oct := i / scale.size()
		var semi: float = float(scale[i % scale.size()])
		out.append(root + semi + 12.0 * float(oct))
	return out


## Fold everything past the loop point back onto the head so releases and the
## reverb tail wrap round instead of clicking.
func _wrap_tail(buf: PackedFloat32Array, loop_len: int) -> PackedFloat32Array:
	var n := buf.size()
	var out := PackedFloat32Array()
	out.resize(loop_len)
	for i in loop_len:
		out[i] = buf[i]
	for i in range(loop_len, n):
		var j := i - loop_len
		if j >= loop_len:
			break
		out[j] = out[j] + buf[i]
	return out


func _voice(timbre: String, dur: float, midi: float, amp: float,
		bright: float) -> PackedFloat32Array:
	var f := FxSynth.note_hz(midi)
	var v: PackedFloat32Array
	match timbre:
		"glass":
			v = FxSynth.fm(dur, f, 2.0, 1.2, 0.15, amp, SR)
		"hard":
			v = FxSynth.osc(FxSynth.Wave.SAW, dur, f, f * 1.002, amp, SR)
		"dark":
			v = FxSynth.osc(FxSynth.Wave.TRIANGLE, dur, f * 0.5, f * 0.5, amp, SR)
		_:
			v = FxSynth.osc(FxSynth.Wave.TRIANGLE, dur, f, f * 1.003, amp, SR)
	return FxSynth.lowpass1(v, bright, SR)


func _render_chord(dst: PackedFloat32Array, chord: PackedFloat32Array, bar: int,
		bar_sec: float, def: Dictionary, rng: RandomNumberGenerator) -> void:
	var timbre := String(def.get("timbre", "soft"))
	var bright := float(def.get("bright", 2600.0))
	var at := float(bar) * bar_sec
	for i in chord.size():
		var midi: float = chord[i] + (12.0 if i == chord.size() - 1 else 0.0)
		var dur := bar_sec * rng.randf_range(0.85, 1.15)
		var v := _voice(timbre, dur, midi, 0.34 - float(i) * 0.04, bright)
		v = FxSynth.adsr(v, bar_sec * 0.22, bar_sec * 0.2, 0.7, bar_sec * 0.45, SR)
		FxSynth.mix_into(dst, v, 0.9, at + float(i) * 0.02, SR)


func _render_bass(dst: PackedFloat32Array, midi: float, bar: int, bar_sec: float,
		beat: float, def: Dictionary) -> void:
	var at := float(bar) * bar_sec
	var hits := 2 if float(def.get("perc", 0.0)) < 0.5 else 4
	for h in hits:
		var dur := (bar_sec / float(hits)) * 0.85
		var v := FxSynth.osc(FxSynth.Wave.SINE, dur, FxSynth.note_hz(midi - 12.0),
				-1.0, 0.55, SR)
		v = FxSynth.adsr(v, 0.01, dur * 0.3, 0.6, dur * 0.35, SR)
		FxSynth.mix_into(dst, v, 0.8, at + float(h) * beat * (float(BEATS_PER_BAR) / float(hits)), SR)


func _render_lead(dst: PackedFloat32Array, scale: Array, root: float, prog: Array,
		bars: int, bar_sec: float, _beat: float, def: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var count: int = int(def.get("notes", 8))
	var timbre := String(def.get("timbre", "soft"))
	var bright := float(def.get("bright", 2600.0))
	var total := bar_sec * float(bars)
	var slot := total / float(count)
	var idx := 0
	for i in count:
		if rng.randf() < 0.22:
			continue    # a rest: melodies need holes
		var bar := mini(bars - 1, int((float(i) * slot) / bar_sec))
		var degree: int = int(prog[bar % prog.size()])
		# Prefer chord tones (0/2/4 above the degree), stray to neighbours.
		var pick: int = degree + int(MELODY_STEPS[idx % MELODY_STEPS.size()])
		if rng.randf() < 0.3:
			pick += 2
		var oct: int = pick / scale.size()
		var midi: float = root + 12.0 + float(scale[pick % scale.size()]) + 12.0 * float(oct)
		var dur: float = slot * rng.randf_range(0.7, 1.6)
		var v := _voice("glass" if timbre != "hard" else "hard", dur, midi, 0.42, bright * 1.4)
		v = FxSynth.adsr(v, minf(0.06, dur * 0.15), dur * 0.25, 0.45, dur * 0.5, SR)
		FxSynth.mix_into(dst, v, 0.85, float(i) * slot, SR)
		idx += 1


func _render_perc(dst: PackedFloat32Array, bars: int, beat: float, weight: float,
		rng: RandomNumberGenerator) -> void:
	var steps := bars * BEATS_PER_BAR * 2
	for s in steps:
		var at := float(s) * beat * 0.5
		var in_bar := s % (BEATS_PER_BAR * 2)
		if in_bar == 0 or in_bar == 6:
			var kick := FxSynth.osc(FxSynth.Wave.SINE, 0.16, 130.0, 44.0, 0.9, SR)
			kick = FxSynth.perc(kick, 0.001, 2.6, SR)
			FxSynth.mix_into(dst, kick, 0.7 * weight, at, SR)
		if in_bar == 4:
			var sn := FxSynth.noise(0.13, 0.8, rng, SR)
			sn = FxSynth.biquad(sn, FxSynth.Filter.BANDPASS, 1500.0, 0.8, SR)
			sn = FxSynth.perc(sn, 0.001, 3.0, SR)
			FxSynth.mix_into(dst, sn, 0.5 * weight, at, SR)
		if s % 2 == 1:
			var hat := FxSynth.noise(0.045, 0.6, rng, SR)
			hat = FxSynth.biquad(hat, FxSynth.Filter.HIGHPASS, 6000.0, 0.7, SR)
			hat = FxSynth.perc(hat, 0.0005, 4.0, SR)
			FxSynth.mix_into(dst, hat, 0.28 * weight, at, SR)
