## Autoloaded as `Audio`. Owns the bus graph, the voice pools, the procedural
## sound bank, the adaptive music director and the ambience beds.
##
## ---------------------------------------------------------------------------
## Plane-aware audio
## ---------------------------------------------------------------------------
## The camera is orthographic and parked 40 m back, so Godot's stock 3D panning
## would flatten every sound to dead centre. Instead each voice is placed on a
## *virtual* sphere around the listener:
##
##   pan   = lateral offset in **plane space** (`View.lateral_of`) / PAN_WIDTH
##   tilt  = vertical offset / PAN_WIDTH, at half weight
##   depth = the emitter's layer offset (`View.depth_of` vs `View.layer`)
##
## Pan and tilt aim the voice; the *true* distance to the player sets its
## loudness. Depth does not move the voice — it picks a **bus**: sounds on the
## play layer are dry, one or two layers away go through a 2.6 kHz low-pass,
## and anything deeper is heavily filtered and quieter. Layers you cannot see
## you can still hear, muffled, exactly as if they were behind a wall — which
## they are. That single rule is what makes depth legible by ear.
extends Node

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambient"
const BUS_UI := "UI"
## Depth-muffled children of SFX. Never address these directly; `play()` picks.
const BUS_SFX_MID := "SFXMid"
const BUS_SFX_FAR := "SFXFar"

const POOL_3D := 28
const POOL_2D := 8

## Plane-space distance that maps to full left/right.
const PAN_WIDTH := 14.0
## Beyond this many metres from the player a positional sound is dropped.
const MAX_AUDIBLE := 52.0
## Layers behind the play plane that are still worth hearing.
const MAX_DEPTH_AUDIBLE := 18
## dB lost per layer of depth separation.
const DEPTH_DB_PER_LAYER := -1.15
const DEPTH_DB_FLOOR := -14.0

var bank: FxSoundBank = null
var music: FxMusic = null
var ambience: FxAmbience = null

## Master mute; `set_muted(true)` silences everything without unloading it.
var muted := false
## Global trim applied on top of every SFX voice, in dB.
var sfx_trim := 0.0

var _pool3: Array[AudioStreamPlayer3D] = []
var _pool2: Array[AudioStreamPlayer] = []
var _voice_id: Array[StringName] = []
var _voice_free: PackedFloat64Array = PackedFloat64Array()
var _voice2_id: Array[StringName] = []
var _voice2_free: PackedFloat64Array = PackedFloat64Array()
var _last_start: Dictionary = {}

var _host: Node3D = null
var _voices_root: Node3D = null
var _music_filter_idx := -1
var _flip_duck := 0.0
var _warm_queue: Array[StringName] = []
var _warm_take := 0


# =================================================================== lifecycle
func _ready() -> void:
	process_priority = -60
	_build_buses()
	bank = FxSoundBank.new()
	_voices_root = Node3D.new()
	_voices_root.name = "Voices"
	add_child(_voices_root)
	_build_pools()
	music = FxMusic.new()
	music.name = "Music"
	add_child(music)
	ambience = FxAmbience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	_warm_queue.assign(FxSoundBank.HOT_IDS)
	Events.play_sound.connect(_on_play_sound)
	Events.view_flip_started.connect(_on_flip_started)
	Events.view_flip_finished.connect(_on_flip_finished)


func _process(delta: float) -> void:
	# Spread the boot warm-up over idle frames: one voice per frame never
	# hitches, and after the first pass we quietly fill in the other takes.
	if not _warm_queue.is_empty():
		var id: StringName = _warm_queue.pop_front()
		if bank != null:
			bank.warm(id, _warm_take)
	elif _warm_take < FxSoundBank.TAKES - 1:
		_warm_take += 1
		_warm_queue.assign(FxSoundBank.HOT_IDS)
	_update_flip_duck(delta)


# ======================================================================= buses
## Build Master -> {Music, SFX -> {SFXMid, SFXFar}, Ambient, UI} in code.
## Idempotent: an existing bus with the right name is reused, so a project that
## later ships a real bus layout is not clobbered.
func _build_buses() -> void:
	_ensure_bus(BUS_MUSIC, BUS_MASTER)
	_ensure_bus(BUS_SFX, BUS_MASTER)
	_ensure_bus(BUS_AMBIENT, BUS_MASTER)
	_ensure_bus(BUS_UI, BUS_MASTER)
	_ensure_bus(BUS_SFX_MID, BUS_SFX)
	_ensure_bus(BUS_SFX_FAR, BUS_SFX)

	var mid := AudioServer.get_bus_index(BUS_SFX_MID)
	if mid >= 0 and AudioServer.get_bus_effect_count(mid) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 2600.0
		lp.resonance = 0.1
		AudioServer.add_bus_effect(mid, lp)
		AudioServer.set_bus_volume_db(mid, -2.0)

	var far := AudioServer.get_bus_index(BUS_SFX_FAR)
	if far >= 0 and AudioServer.get_bus_effect_count(far) == 0:
		var lp2 := AudioEffectLowPassFilter.new()
		lp2.cutoff_hz = 820.0
		lp2.resonance = 0.1
		AudioServer.add_bus_effect(far, lp2)
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.55
		rv.damping = 0.7
		rv.wet = 0.22
		rv.dry = 0.9
		AudioServer.add_bus_effect(far, rv)
		AudioServer.set_bus_volume_db(far, -6.0)

	# A bypassed low-pass on Music; the flip sweeps it to sell the rotation.
	var mus := AudioServer.get_bus_index(BUS_MUSIC)
	if mus >= 0:
		if AudioServer.get_bus_effect_count(mus) == 0:
			var mf := AudioEffectLowPassFilter.new()
			mf.cutoff_hz = 20000.0
			mf.resonance = 0.1
			AudioServer.add_bus_effect(mus, mf)
		_music_filter_idx = 0
		AudioServer.set_bus_volume_db(mus, -6.0)
	var amb := AudioServer.get_bus_index(BUS_AMBIENT)
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, -9.0)


func _ensure_bus(bus_name: String, send_to: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.get_bus_count()
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)
	return idx


## Set a bus volume in decibels. Unknown bus names are ignored.
func set_bus_volume(bus: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, clampf(db, -80.0, 12.0))


## Current volume of a bus in decibels, or -80 when it does not exist.
func get_bus_volume(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(idx) if idx >= 0 else -80.0


## Silence (or restore) everything. Streams keep running so music does not
## restart when the player unmutes.
func set_muted(v: bool) -> void:
	muted = v
	var idx := AudioServer.get_bus_index(BUS_MASTER)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, v)


# ======================================================================= pools
func _build_pools() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice3D_%d" % i
		p.bus = BUS_SFX
		p.unit_size = 9.0
		p.max_db = 3.0
		p.max_distance = MAX_AUDIBLE + 8.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 2.2
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		# Depth muffling is done with buses, not with the built-in air filter.
		p.attenuation_filter_cutoff_hz = 20500.0
		_voices_root.add_child(p)
		_pool3.append(p)
		_voice_id.append(&"")
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.name = "Voice2D_%d" % i
		p2.bus = BUS_UI
		add_child(p2)
		_pool2.append(p2)
		_voice2_id.append(&"")
	_voice_free.resize(POOL_3D)
	_voice2_free.resize(POOL_2D)


## `FxRoot` registers itself here on `_ready`. The voice pool deliberately
## stays parented to this autoload rather than moving into the gameplay scene:
## both live in the root viewport so 3D panning is identical either way, and a
## scene reload must never take the pool down with it. The reference is kept so
## FX-side code can find the audio host without a scene-tree walk.
func attach_host(host: Node3D) -> void:
	_host = host


## The FX scene node, if one has registered.
func host() -> Node3D:
	return _host


## Stop every positional and 2D voice (used on world unload / travel).
func stop_all() -> void:
	for p in _pool3:
		p.stop()
	for p2 in _pool2:
		p2.stop()
	for i in _voice_id.size():
		_voice_id[i] = &""
	for i in _voice2_id.size():
		_voice2_id[i] = &""


# ==================================================================== playback
func _on_play_sound(sound_id: String, world_pos: Vector3) -> void:
	play(StringName(sound_id), world_pos)


## Play a sound. `world_pos == Vector3.ZERO` (or a UI-bus sound) plays flat.
## Returns the node that got the voice, or null when the request was culled.
func play(id: StringName, world_pos: Vector3 = Vector3.ZERO,
		volume_db: float = 0.0, pitch: float = 0.0) -> Node:
	if muted or bank == null:
		return null
	var c: StringName = bank.canonical(id)
	var spec: Dictionary = bank.spec(c)
	var now := float(Time.get_ticks_msec()) * 0.001
	var gap: float = spec.get("gap", 0.0)
	if gap > 0.0 and now - float(_last_start.get(c, -99.0)) < gap:
		return null

	var flat: bool = String(spec.get("bus", "SFX")) == BUS_UI or world_pos.is_zero_approx()
	var depth_off := 0
	var dist := 0.0
	if not flat:
		var ref := _listen_ref()
		dist = world_pos.distance_to(ref)
		if dist > MAX_AUDIBLE:
			return null
		depth_off = _layer_offset(world_pos)
		if depth_off > MAX_DEPTH_AUDIBLE or depth_off < -6:
			return null

	var stream := bank.stream(c)
	if stream == null:
		return null
	var rng_pitch: float = spec.get("pitch", 0.0)
	var p_scale := 1.0 + randf_range(-rng_pitch, rng_pitch) + pitch
	var db: float = float(spec.get("db", -7.0)) + volume_db + sfx_trim

	if flat:
		var v2 := _take_2d(c, int(spec.get("limit", 4)))
		if v2 == null:
			return null
		v2.bus = String(spec.get("bus", BUS_SFX))
		v2.stream = stream
		v2.pitch_scale = clampf(p_scale, 0.4, 2.5)
		v2.volume_db = db + randf_range(-1.0, 1.0)
		v2.play()
		_last_start[c] = now
		return v2

	var v := _take_3d(c, int(spec.get("limit", 4)))
	if v == null:
		return null
	var ad := absi(depth_off)
	if ad == 0:
		v.bus = BUS_SFX
	elif ad <= 2:
		v.bus = BUS_SFX_MID
	else:
		v.bus = BUS_SFX_FAR
	v.stream = stream
	v.pitch_scale = clampf(p_scale, 0.4, 2.5)
	v.volume_db = db + randf_range(-1.0, 1.0) \
			+ maxf(DEPTH_DB_FLOOR, float(ad) * DEPTH_DB_PER_LAYER)
	v.global_position = _virtual_position(world_pos, dist)
	v.play()
	_last_start[c] = now
	return v


## Convenience for menus and anything without a world position.
func play_ui(id: StringName, volume_db: float = 0.0) -> Node:
	return play(id, Vector3.ZERO, volume_db)


## Play a sound at the player, so it is always centred and unmuffled.
func play_at_player(id: StringName, volume_db: float = 0.0) -> Node:
	var p := _player_node()
	if p == null:
		return play_ui(id, volume_db)
	return play(id, p.global_position, volume_db)


func _take_3d(id: StringName, limit: int) -> AudioStreamPlayer3D:
	var same := 0
	var free_idx := -1
	var oldest := -1
	var oldest_t := INF
	for i in _pool3.size():
		var p := _pool3[i]
		if p.playing:
			if _voice_id[i] == id:
				same += 1
				if _voice_free[i] < oldest_t:
					oldest_t = _voice_free[i]
					oldest = i
		elif free_idx < 0:
			free_idx = i
	if same >= maxi(1, limit):
		# Voice-steal the longest-running instance of this same id.
		if oldest < 0:
			return null
		free_idx = oldest
	if free_idx < 0:
		return null
	_voice_id[free_idx] = id
	_voice_free[free_idx] = float(Time.get_ticks_msec()) * 0.001
	return _pool3[free_idx]


func _take_2d(id: StringName, limit: int) -> AudioStreamPlayer:
	var same := 0
	var free_idx := -1
	for i in _pool2.size():
		var p := _pool2[i]
		if p.playing:
			if _voice2_id[i] == id:
				same += 1
		elif free_idx < 0:
			free_idx = i
	if same >= maxi(1, limit) or free_idx < 0:
		return null
	_voice2_id[free_idx] = id
	_voice2_free[free_idx] = float(Time.get_ticks_msec()) * 0.001
	return _pool2[free_idx]


# ======================================================== plane-aware placement
## How many layers behind the play plane this world position sits. Negative
## means it is in front of the player, i.e. between them and the camera.
func _layer_offset(world_pos: Vector3) -> int:
	return int(roundf((View.depth_of(world_pos) - float(View.layer)) * float(View.depth_sign())))


func _player_node() -> Node3D:
	var g: Node = get_node_or_null(^"/root/Game")
	if g == null:
		return null
	var p = g.get("player")
	return p as Node3D


## Distances are measured from the player, not the camera: a sound two metres
## from your feet must be loud even though the camera is forty metres back.
func _listen_ref() -> Vector3:
	var p := _player_node()
	if p != null:
		return p.global_position
	var cam := _camera()
	return cam.global_position if cam != null else Vector3.ZERO


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


## Aim the voice from the listener using plane-space lateral/vertical offsets,
## then push it out to the true gameplay distance.
func _virtual_position(world_pos: Vector3, dist: float) -> Vector3:
	var cam := _camera()
	if cam == null:
		return world_pos
	var ref := _listen_ref()
	var lat := View.lateral_of(world_pos) - View.lateral_of(ref)
	var vert := world_pos.y - ref.y
	var pan := clampf(lat / PAN_WIDTH, -1.0, 1.0)
	var tilt := clampf(vert / PAN_WIDTH, -1.0, 1.0) * 0.45
	var fwd := sqrt(maxf(0.08, 1.0 - pan * pan - tilt * tilt))
	var b := cam.global_transform.basis
	var dir := (b.x * pan + Vector3.UP * tilt - b.z * fwd).normalized()
	return cam.global_position + dir * maxf(0.75, dist)


# ======================================================================= music
## Hand a named track to the music director. Track names may be a situation
## (`explore`, `combat`, `night`, `underground`, `boss`, `ship`, `outpost`,
## `menu`, `space`) or a biome key such as `music_calm`.
##
## An explicit request pins the music: the adaptive director stops choosing
## until `play_music(&"auto")` (or leaving the planet) hands control back.
func play_music(track: StringName) -> void:
	if music == null:
		return
	if track == &"" or track == &"auto":
		music.release()
		return
	music.force_track(track)


func stop_music() -> void:
	if music != null:
		music.release()
		music.stop()


## 0..1 — how busy the arrangement should be. Combat pushes this up.
func set_music_intensity(v: float) -> void:
	if music != null:
		music.set_intensity(v)


## Force an ambience bed (`wind`, `cave`, `ocean`, `lava`, `insects`,
## `machine`, `rain`); pass `&""` to hand control back to the environment.
func play_ambience(id: StringName) -> void:
	if ambience != null:
		ambience.force_bed(id)


# ---------------------------------------------------------------- flip ducking
func _on_flip_started(_from: int, _to: int, _dir: int) -> void:
	_flip_duck = 1.0


func _on_flip_finished(_v: int) -> void:
	_flip_duck = minf(_flip_duck, 0.55)


## Sweeps the Music low-pass down and back while the world turns. Cheap, and it
## makes the flip feel like it happens *to* the whole soundscape.
func _update_flip_duck(delta: float) -> void:
	if _music_filter_idx < 0:
		return
	var target := 1.0 if View.flipping else 0.0
	_flip_duck = move_toward(_flip_duck, target, delta * (6.0 if target > 0.0 else 2.6))
	var idx := AudioServer.get_bus_index(BUS_MUSIC)
	if idx < 0:
		return
	var fx := AudioServer.get_bus_effect(idx, _music_filter_idx)
	var filt := fx as AudioEffectFilter
	if filt == null:
		return
	if _flip_duck <= 0.001:
		if filt.cutoff_hz < 19000.0:
			filt.cutoff_hz = 20000.0
		return
	filt.cutoff_hz = lerpf(20000.0, 700.0, ease(clampf(_flip_duck, 0.0, 1.0), 0.45))
