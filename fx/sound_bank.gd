## The actual sound design. Eighty-odd effects, all synthesised on the fly by
## `FxSynth` and cached as `AudioStreamWAV`.
##
## Every id exists in `TAKES` deterministic variants: `FxSynth.seeded(id, take)`
## means take 2 of `break_glass` is always the same shards, but consecutive
## plays cycle through the takes so a mining session never machine-guns the
## identical waveform. Only a short hot list is built at boot; everything else
## is generated the first time it is asked for and then kept.
##
## Ids are resolved structurally: anything `step_*`, `break_*` or `place_*` is
## built from the material table, so a block that asks for `step_obsidian`
## still gets a sensible sound instead of silence.
class_name FxSoundBank
extends RefCounted

const SR := FxSynth.SR
## Distinct variants generated per sound id.
const TAKES := 3

## Per-material voicing for footsteps, breaking and placing.
##   bp/q     centre and sharpness of the noise band — the "grain"
##   lp       low-pass ceiling, i.e. how dull the material is
##   tone     pitched partial (0 = unpitched)
##   thump    body frequency of the impact (0 = none)
##   crack    amount of secondary debris ticks
##   dur      base footstep length
const MATERIALS := {
	&"stone": {"bp": 780.0, "q": 1.2, "lp": 4500.0, "tone": 0.0, "thump": 96.0, "crack": 0.35, "dur": 0.075, "crunch": 0.0},
	&"dirt": {"bp": 320.0, "q": 0.8, "lp": 900.0, "tone": 0.0, "thump": 68.0, "crack": 0.06, "dur": 0.090, "crunch": 0.0},
	&"grass": {"bp": 2200.0, "q": 0.6, "lp": 6200.0, "tone": 0.0, "thump": 55.0, "crack": 0.10, "dur": 0.105, "crunch": 0.0},
	&"sand": {"bp": 3600.0, "q": 0.5, "lp": 9000.0, "tone": 0.0, "thump": 0.0, "crack": 0.0, "dur": 0.130, "crunch": 0.0},
	&"snow": {"bp": 4600.0, "q": 0.45, "lp": 9000.0, "tone": 0.0, "thump": 0.0, "crack": 0.45, "dur": 0.140, "crunch": 0.6},
	&"wood": {"bp": 900.0, "q": 1.9, "lp": 5000.0, "tone": 236.0, "thump": 0.0, "crack": 0.25, "dur": 0.090, "crunch": 0.0},
	&"metal": {"bp": 1500.0, "q": 2.8, "lp": 9500.0, "tone": 1180.0, "thump": 0.0, "crack": 0.20, "dur": 0.100, "crunch": 0.0},
	&"glass": {"bp": 5200.0, "q": 1.8, "lp": 11000.0, "tone": 3300.0, "thump": 0.0, "crack": 0.55, "dur": 0.075, "crunch": 0.0},
	&"leaves": {"bp": 3000.0, "q": 0.7, "lp": 8000.0, "tone": 0.0, "thump": 0.0, "crack": 0.0, "dur": 0.120, "crunch": 0.0},
	&"liquid": {"bp": 520.0, "q": 0.9, "lp": 1500.0, "tone": 0.0, "thump": 0.0, "crack": 0.0, "dur": 0.150, "crunch": 0.0},
}

## Ids that are not built from the material table.
const ACTION_IDS: Array[StringName] = [
	&"jump", &"land", &"land_heavy", &"hurt", &"death", &"heal", &"pickup",
	&"craft", &"denied", &"ui_click", &"ui_hover", &"open", &"close",
	&"explosion", &"swing", &"hit_flesh", &"hit_metal", &"arrow", &"laser",
	&"charge", &"splash", &"lava", &"door", &"chest", &"teleport", &"warp",
	&"levelup", &"quest", &"flip", &"shift",
	&"mine_hit", &"tool_break", &"equip", &"eat", &"drink", &"coin", &"beep",
	&"scan", &"zap", &"freeze", &"burn", &"poison", &"shield", &"bow_draw",
	&"thunder", &"boss_roar", &"growl", &"machine", &"respawn", &"notify",
	&"crit", &"bubble", &"page", &"unlock",
]

## Vocabulary other modules emit that maps onto an existing voice. Keeping this
## table fat is far cheaper than eighty more oscillator recipes, and it means a
## module can invent an id without ever getting silence.
const ALIASES := {
	# generic
	&"error": &"denied", &"click": &"ui_click", &"hover": &"ui_hover",
	&"footstep": &"step_stone", &"step_ice": &"step_glass",
	&"break_ice": &"break_glass", &"place_ice": &"place_glass",
	&"step_gravel": &"step_sand", &"step_ladder": &"step_wood",
	&"hit_stone": &"mine_hit", &"hit_wood": &"break_wood",
	&"portal": &"teleport", &"magic": &"teleport", &"ui_open": &"open",
	&"ui_close": &"close", &"sting": &"quest", &"pickup_coin": &"coin",
	&"drop": &"pickup", &"use": &"ui_click", &"select": &"ui_click",
	&"interact": &"ui_click", &"ui_hint": &"ui_hover",
	&"chart_unfold": &"page", &"scanner": &"scan",
	# mining / building / tools
	&"block_hit": &"mine_hit", &"block_raise": &"place_stone",
	&"item_break": &"tool_break", &"tool_beam_break": &"tool_break",
	&"tool_mode": &"beep", &"tool_paint": &"step_liquid",
	&"tool_pour": &"splash", &"tool_slurp": &"drink",
	&"harvest": &"break_grass", &"till": &"step_dirt", &"plant": &"step_grass",
	&"scoop": &"step_sand", &"dig": &"break_dirt", &"forge": &"craft",
	# movement
	&"bounce": &"jump", &"leap": &"jump", &"drop_through": &"step_wood",
	&"ledge_grab": &"step_stone", &"wall_kick": &"jump",
	# combat / monsters
	&"monster_hit": &"hit_flesh", &"monster_death": &"death",
	&"monster_shoot": &"laser", &"monster_shift": &"shift",
	&"monster_alert": &"growl", &"hiss": &"growl", &"howl": &"growl",
	&"ambush": &"growl", &"mimic_reveal": &"growl",
	&"eel_strike": &"hit_flesh", &"burrow_rise": &"break_dirt",
	&"parry": &"hit_metal", &"guard_break": &"hit_metal",
	&"shell_curl": &"hit_metal", &"player_die": &"death",
	&"swing_windup": &"bow_draw", &"pod_throw": &"swing",
	&"pod_release": &"open", &"drown": &"bubble", &"pop": &"bubble",
	# bosses
	&"boss_spawn": &"boss_roar", &"boss_phase": &"boss_roar",
	&"boss_windup": &"charge", &"boss_slam": &"land_heavy",
	&"boss_quake": &"explosion", &"boss_plane_rip": &"warp",
	&"boss_shift_plane": &"flip", &"eruption": &"explosion",
	# charging / tech
	&"charge_start": &"charge", &"charge_windup": &"charge",
	&"charge_full": &"charge", &"fuse": &"charge", &"special": &"charge",
	&"beacon_activate": &"charge", &"blink": &"teleport",
	&"teleport_in": &"teleport", &"teleport_out": &"teleport",
	&"tech_anchor": &"shield", &"tech_depth_sight": &"scan",
	&"tech_fold": &"warp", &"tech_fold_end": &"teleport",
	&"tech_perspective_dash": &"flip", &"tech_phase": &"teleport",
	&"warp_enter": &"warp", &"warp_exit": &"warp",
	# containers / economy / progression
	&"container_open": &"chest", &"item_transfer": &"pickup",
	&"pixels_spend": &"coin", &"vendor_buy": &"coin", &"vendor_sell": &"coin",
	&"upgrade": &"levelup", &"ship_upgrade": &"craft",
	&"ship_refuel": &"machine", &"ship_takeoff": &"warp",
	&"quest_start": &"notify", &"quest_step": &"beep",
	&"quest_complete": &"quest", &"capture_success": &"levelup",
	&"capture_fail": &"denied", &"stim": &"heal", &"medicine": &"drink",
	&"wire_arm": &"beep", &"wire_connect": &"ui_click",
}

## Built during the first idle frames so the common cases never hitch in play.
const HOT_IDS: Array[StringName] = [
	&"ui_click", &"ui_hover", &"step_stone", &"step_dirt", &"step_grass",
	&"jump", &"land", &"flip", &"shift", &"break_stone", &"place_stone",
	&"pickup", &"denied", &"swing", &"hurt",
]

## Mixing hints consumed by `Audio`: trim in dB, pitch jitter, simultaneous
## voice cap for this id, and the minimum gap between two starts in seconds.
const SPECS := {
	&"ui_click": {"db": -12.0, "pitch": 0.02, "limit": 3, "gap": 0.02, "bus": "UI"},
	&"ui_hover": {"db": -20.0, "pitch": 0.04, "limit": 2, "gap": 0.05, "bus": "UI"},
	&"open": {"db": -9.0, "pitch": 0.03, "limit": 2, "gap": 0.05, "bus": "UI"},
	&"close": {"db": -9.0, "pitch": 0.03, "limit": 2, "gap": 0.05, "bus": "UI"},
	&"notify": {"db": -10.0, "pitch": 0.01, "limit": 2, "gap": 0.10, "bus": "UI"},
	&"page": {"db": -14.0, "pitch": 0.05, "limit": 2, "gap": 0.04, "bus": "UI"},
	&"beep": {"db": -14.0, "pitch": 0.03, "limit": 2, "gap": 0.04, "bus": "UI"},
	&"explosion": {"db": -1.0, "pitch": 0.10, "limit": 3, "gap": 0.03},
	&"thunder": {"db": -2.0, "pitch": 0.08, "limit": 2, "gap": 0.50},
	&"flip": {"db": -4.0, "pitch": 0.03, "limit": 2, "gap": 0.05},
	&"shift": {"db": -8.0, "pitch": 0.05, "limit": 2, "gap": 0.05},
	&"hurt": {"db": -4.0, "pitch": 0.07, "limit": 2, "gap": 0.08},
	&"death": {"db": -3.0, "pitch": 0.03, "limit": 1, "gap": 0.50},
	&"levelup": {"db": -4.0, "pitch": 0.0, "limit": 1, "gap": 0.50},
	&"quest": {"db": -6.0, "pitch": 0.0, "limit": 1, "gap": 0.30},
	&"warp": {"db": -4.0, "pitch": 0.02, "limit": 1, "gap": 0.50},
	&"teleport": {"db": -6.0, "pitch": 0.04, "limit": 2, "gap": 0.10},
	&"lava": {"db": -10.0, "pitch": 0.10, "limit": 2, "gap": 0.30},
	&"machine": {"db": -14.0, "pitch": 0.06, "limit": 2, "gap": 0.20},
	&"boss_roar": {"db": -2.0, "pitch": 0.05, "limit": 1, "gap": 1.00},
	&"swing": {"db": -10.0, "pitch": 0.09, "limit": 3, "gap": 0.05},
	&"mine_hit": {"db": -11.0, "pitch": 0.10, "limit": 3, "gap": 0.06},
	&"laser": {"db": -7.0, "pitch": 0.06, "limit": 4, "gap": 0.03},
	&"arrow": {"db": -9.0, "pitch": 0.08, "limit": 4, "gap": 0.03},
}

## Default mixing hints for every id not listed above.
const DEFAULT_SPEC := {"db": -7.0, "pitch": 0.06, "limit": 4, "gap": 0.0, "bus": "SFX"}

var _cache: Dictionary = {}          ## "id#take" -> AudioStreamWAV
var _next_take: Dictionary = {}      ## id -> next variant index
var _spec_cache: Dictionary = {}
var _built := 0


# ==================================================================== queries
## Resolve aliases. Always call this before looking anything up.
func canonical(id: StringName) -> StringName:
	return ALIASES.get(id, id)


## True when this id has a hand-written voice (structural `step_*` style ids
## count, since the material table synthesises them on demand).
func has(id: StringName) -> bool:
	var c := canonical(id)
	if ACTION_IDS.has(c):
		return true
	var s := String(c)
	return s.begins_with("step_") or s.begins_with("break_") or s.begins_with("place_")


## Mixing hints for an id — see `SPECS`.
func spec(id: StringName) -> Dictionary:
	var c := canonical(id)
	if _spec_cache.has(c):
		return _spec_cache[c]
	var out := DEFAULT_SPEC.duplicate()
	var s := String(c)
	if s.begins_with("step_"):
		out["db"] = -17.0
		out["pitch"] = 0.10
		out["limit"] = 2
		out["gap"] = 0.05
	elif s.begins_with("place_"):
		out["db"] = -10.0
		out["pitch"] = 0.07
		out["gap"] = 0.02
	elif s.begins_with("break_"):
		out["db"] = -7.0
		out["pitch"] = 0.08
		out["gap"] = 0.02
	if SPECS.has(c):
		for k: String in SPECS[c]:
			out[k] = SPECS[c][k]
	_spec_cache[c] = out
	return out


## Every id the bank can build, for debug listings.
func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for m: StringName in MATERIALS:
		out.append(StringName("step_" + String(m)))
		out.append(StringName("break_" + String(m)))
		out.append(StringName("place_" + String(m)))
	out.append_array(ACTION_IDS)
	return out


func built_count() -> int:
	return _built


# =================================================================== fetching
## The stream for a sound id, generating it if this is the first request.
## Omit `take` to cycle deterministically through the variants.
func stream(id: StringName, take: int = -1) -> AudioStreamWAV:
	var c := canonical(id)
	var t := take
	if t < 0:
		t = int(_next_take.get(c, 0))
		_next_take[c] = (t + 1) % TAKES
	t = t % TAKES
	var key := "%s#%d" % [c, t]
	var cached: AudioStreamWAV = _cache.get(key)
	if cached != null:
		return cached
	var buf := _build(c, t)
	if buf.is_empty():
		return null
	var w := FxSynth.to_wav(buf, SR, false)
	_cache[key] = w
	_built += 1
	return w


## Build one variant now (used by the boot warm-up). Returns false if the id is
## already resident.
func warm(id: StringName, take: int = 0) -> bool:
	var key := "%s#%d" % [canonical(id), take % TAKES]
	if _cache.has(key):
		return false
	stream(id, take)
	return true


func clear() -> void:
	_cache.clear()
	_next_take.clear()
	_built = 0


# =================================================================== building
func _build(id: StringName, take: int) -> PackedFloat32Array:
	var rng := FxSynth.seeded(id, take)
	var s := String(id)
	if s.begins_with("step_"):
		return _step(StringName(s.substr(5)), rng)
	if s.begins_with("break_"):
		return _break(StringName(s.substr(6)), rng)
	if s.begins_with("place_"):
		return _place(StringName(s.substr(6)), rng)
	match s:
		"jump": return _jump(rng)
		"land": return _land(rng, 1.0)
		"land_heavy": return _land(rng, 1.9)
		"hurt": return _hurt(rng)
		"death": return _death(rng)
		"heal": return _heal(rng)
		"pickup": return _pickup(rng)
		"coin": return _coin(rng)
		"craft": return _craft(rng)
		"denied": return _denied(rng)
		"ui_click": return _ui_click(rng)
		"ui_hover": return _ui_hover(rng)
		"open": return _panel(rng, true)
		"close": return _panel(rng, false)
		"explosion": return _explosion(rng)
		"swing": return _swing(rng)
		"hit_flesh": return _hit_flesh(rng)
		"hit_metal": return _hit_metal(rng)
		"arrow": return _arrow(rng)
		"laser": return _laser(rng)
		"charge": return _charge(rng)
		"splash": return _splash(rng)
		"lava": return _lava(rng)
		"door": return _door(rng)
		"chest": return _chest(rng)
		"teleport": return _teleport(rng)
		"warp": return _warp(rng)
		"levelup": return _levelup(rng)
		"quest": return _quest(rng)
		"flip": return _flip(rng)
		"shift": return _shift(rng)
		"mine_hit": return _mine_hit(rng)
		"tool_break": return _tool_break(rng)
		"equip": return _equip(rng)
		"eat": return _eat(rng)
		"drink": return _drink(rng)
		"beep": return _beep(rng)
		"scan": return _scan(rng)
		"zap": return _zap(rng)
		"freeze": return _freeze(rng)
		"burn": return _burn(rng)
		"poison": return _poison(rng)
		"shield": return _shield(rng)
		"bow_draw": return _bow_draw(rng)
		"thunder": return _thunder(rng)
		"boss_roar": return _boss_roar(rng)
		"growl": return _growl(rng)
		"machine": return _machine(rng)
		"respawn": return _respawn(rng)
		"notify": return _notify(rng)
		"crit": return _crit(rng)
		"bubble": return _bubble(rng)
		"page": return _page(rng)
		"unlock": return _unlock(rng)
	return _blip(rng)


# ------------------------------------------------------------------ materials
func _mat(name: StringName) -> Dictionary:
	if MATERIALS.has(name):
		return MATERIALS[name]
	# Unknown material: guess from the name so new blocks still sound plausible.
	var s := String(name)
	for k: StringName in MATERIALS:
		if s.findn(String(k)) >= 0:
			return MATERIALS[k]
	return MATERIALS[&"stone"]


## The shared impact voice: a filtered noise grain, an optional pitched
## partial, an optional body thump, and optional debris ticks.
func _impact(name: StringName, length: float, debris: int, tone_gain: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var m := _mat(name)
	var dur: float = float(m["dur"]) * length
	var out := FxSynth.buffer(dur + 0.10)
	var grain := FxSynth.noise(dur, 1.0, rng, SR)
	grain = FxSynth.biquad(grain, FxSynth.Filter.BANDPASS,
			FxSynth.vary(rng, float(m["bp"]), 0.14), float(m["q"]), SR)
	grain = FxSynth.lowpass1(grain, float(m["lp"]), SR)
	grain = FxSynth.perc(grain, 0.0015, 2.4 + rng.randf() * 1.2, SR)
	if float(m["crunch"]) > 0.0:
		grain = FxSynth.bitcrush(grain, 5.0, 2)
		grain = FxSynth.gain(grain, 0.8)
	FxSynth.mix_into(out, FxSynth.normalize(grain, 0.85), 1.0, 0.0, SR)

	var thump: float = float(m["thump"])
	if thump > 0.0:
		var body := FxSynth.osc(FxSynth.Wave.SINE, minf(0.14, dur * 1.6),
				FxSynth.vary(rng, thump, 0.12), thump * 0.72, 0.9, SR)
		body = FxSynth.perc(body, 0.001, 3.4, SR)
		FxSynth.mix_into(out, body, 0.55 * length, 0.0, SR)

	var tone: float = float(m["tone"])
	if tone > 0.0 and tone_gain > 0.0:
		var f := FxSynth.vary(rng, tone, 0.05)
		var ring := FxSynth.resonator(dur * 3.0, f, dur * 2.4, 0.7, rng, SR)
		FxSynth.mix_into(out, ring, tone_gain, 0.0, SR)
		var ring2 := FxSynth.resonator(dur * 2.0, f * 2.71, dur * 1.4, 0.4, rng, SR)
		FxSynth.mix_into(out, ring2, tone_gain * 0.45, 0.001, SR)

	var crack: float = float(m["crack"])
	for i in debris:
		if crack <= 0.0 and i > debris / 2:
			break
		var tick := FxSynth.noise(0.018, 1.0, rng, SR)
		tick = FxSynth.biquad(tick, FxSynth.Filter.BANDPASS,
				float(m["bp"]) * rng.randf_range(0.8, 2.6), 2.5, SR)
		tick = FxSynth.perc(tick, 0.0005, 4.0, SR)
		FxSynth.mix_into(out, tick, (0.25 + crack * 0.5) * rng.randf_range(0.4, 1.0),
				dur * 0.5 + rng.randf() * (0.05 + dur * 2.0), SR)

	if name == &"liquid":
		var bloop := FxSynth.osc(FxSynth.Wave.SINE, 0.12,
				FxSynth.vary(rng, 460.0, 0.2), 190.0, 0.6, SR)
		bloop = FxSynth.perc(bloop, 0.004, 2.0, SR)
		FxSynth.mix_into(out, bloop, 0.7, 0.005, SR)
	return out


func _step(name: StringName, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _impact(name, 1.0, 1, 0.25, rng)
	return FxSynth.normalize(b, 0.7)


func _break(name: StringName, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _impact(name, 2.3, 6, 0.9, rng)
	b = FxSynth.pad(b, 0.10, SR)
	b = FxSynth.reverb(b, 0.28, 0.55, 0.16, SR)
	return FxSynth.normalize(b, 0.92)


func _place(name: StringName, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _impact(name, 1.35, 2, 0.45, rng)
	var thunk := FxSynth.osc(FxSynth.Wave.SINE, 0.09,
			FxSynth.vary(rng, 118.0, 0.1), 80.0, 0.8, SR)
	thunk = FxSynth.perc(thunk, 0.001, 3.0, SR)
	FxSynth.mix_into(b, thunk, 0.5, 0.0, SR)
	return FxSynth.normalize(b, 0.82)


# -------------------------------------------------------------------- motion
func _jump(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.20)
	var body := FxSynth.osc(FxSynth.Wave.SINE, 0.16,
			FxSynth.vary(rng, 230.0, 0.06), 430.0, 0.9, SR)
	body = FxSynth.perc(body, 0.004, 2.2, SR)
	FxSynth.mix_into(out, body, 0.7, 0.0, SR)
	var cloth := FxSynth.noise(0.11, 0.5, rng, SR)
	cloth = FxSynth.biquad(cloth, FxSynth.Filter.BANDPASS, 1900.0, 0.7, SR)
	cloth = FxSynth.perc(cloth, 0.006, 2.0, SR)
	FxSynth.mix_into(out, cloth, 0.45, 0.0, SR)
	return FxSynth.normalize(out, 0.8)


func _land(rng: RandomNumberGenerator, weight: float) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.28 * weight)
	var thud := FxSynth.osc(FxSynth.Wave.SINE, 0.17 * weight,
			FxSynth.vary(rng, 105.0, 0.08) * (1.0 / weight), 48.0, 1.0, SR)
	thud = FxSynth.perc(thud, 0.001, 2.6, SR)
	FxSynth.mix_into(out, thud, 0.9, 0.0, SR)
	var dust := FxSynth.noise(0.13 * weight, 0.7, rng, SR)
	dust = FxSynth.lowpass1(dust, 1100.0, SR)
	dust = FxSynth.perc(dust, 0.002, 2.6, SR)
	FxSynth.mix_into(out, dust, 0.6, 0.0, SR)
	if weight > 1.4:
		out = FxSynth.distort(out, 2.2)
	return FxSynth.normalize(out, 0.9)


# ----------------------------------------------------------- life and damage
func _hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.24)
	var v := FxSynth.osc(FxSynth.Wave.SAW, 0.18,
			FxSynth.vary(rng, 320.0, 0.09), 165.0, 0.8, SR)
	v = FxSynth.filter_sweep(v, FxSynth.Filter.LOWPASS, 2600.0, 700.0, 1.4, SR)
	v = FxSynth.perc(v, 0.003, 2.0, SR)
	FxSynth.mix_into(out, v, 0.8, 0.0, SR)
	var slap := FxSynth.noise(0.05, 0.8, rng, SR)
	slap = FxSynth.biquad(slap, FxSynth.Filter.BANDPASS, 900.0, 1.0, SR)
	slap = FxSynth.perc(slap, 0.0008, 3.0, SR)
	FxSynth.mix_into(out, slap, 0.6, 0.0, SR)
	out = FxSynth.distort(out, 2.6)
	return FxSynth.normalize(out, 0.9)


func _death(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.20)
	for i in 3:
		var det := 1.0 + float(i - 1) * 0.012
		var v := FxSynth.osc(FxSynth.Wave.SAW, 0.95, 300.0 * det, 62.0, 0.5, SR)
		v = FxSynth.filter_sweep(v, FxSynth.Filter.LOWPASS, 3000.0, 300.0, 2.0, SR)
		FxSynth.mix_into(out, v, 0.5, 0.0, SR)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.03, 1.0], [0.55, 0.7], [1.0, 0.0]])
	var breath := FxSynth.noise(0.5, 0.4, rng, SR)
	breath = FxSynth.biquad(breath, FxSynth.Filter.BANDPASS, 620.0, 0.8, SR)
	breath = FxSynth.perc(breath, 0.02, 1.6, SR)
	FxSynth.mix_into(out, breath, 0.5, 0.05, SR)
	out = FxSynth.reverb(out, 0.6, 0.4, 0.3, SR)
	return FxSynth.normalize(out, 0.95)


func _heal(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.75)
	var notes := [69.0, 73.0, 76.0, 81.0]
	for i in notes.size():
		var f := FxSynth.note_hz(float(notes[i]))
		var v := FxSynth.osc(FxSynth.Wave.SINE, 0.45, f, f * 1.004, 0.5, SR)
		v = FxSynth.adsr(v, 0.05, 0.12, 0.5, 0.28, SR)
		FxSynth.mix_into(out, v, 0.45, float(i) * 0.075, SR)
	out = FxSynth.reverb(out, 0.5, 0.3, 0.3, SR)
	return FxSynth.normalize(out, 0.75)


func _respawn(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.10)
	for i in 4:
		var f := FxSynth.note_hz(50.0 + float(i) * 7.0)
		var v := FxSynth.osc(FxSynth.Wave.TRIANGLE, 0.9, f * 0.5, f, 0.5, SR)
		v = FxSynth.adsr(v, 0.25, 0.2, 0.6, 0.4, SR)
		FxSynth.mix_into(out, v, 0.4, float(i) * 0.05, SR)
	out = FxSynth.reverb(out, 0.75, 0.3, 0.4, SR)
	return FxSynth.normalize(out, 0.8)


# --------------------------------------------------------------- items and ui
func _pickup(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.24)
	var f := FxSynth.vary(rng, FxSynth.note_hz(84.0), 0.02)
	var a := FxSynth.osc(FxSynth.Wave.SINE, 0.09, f, f, 0.8, SR)
	a = FxSynth.perc(a, 0.002, 2.5, SR)
	FxSynth.mix_into(out, a, 0.7, 0.0, SR)
	var b := FxSynth.osc(FxSynth.Wave.SINE, 0.14, f * 1.5, f * 1.5, 0.8, SR)
	b = FxSynth.perc(b, 0.002, 2.5, SR)
	FxSynth.mix_into(out, b, 0.7, 0.055, SR)
	return FxSynth.normalize(out, 0.7)


func _coin(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.40)
	for i in 3:
		var f := FxSynth.vary(rng, 2400.0 + float(i) * 900.0, 0.06)
		var v := FxSynth.fm(0.30, f, 2.41, 3.0, 0.2, 0.6, SR)
		v = FxSynth.perc(v, 0.001, 3.5, SR)
		FxSynth.mix_into(out, v, 0.5, float(i) * 0.012, SR)
	return FxSynth.normalize(out, 0.7)


func _craft(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.60)
	for i in 3:
		var tick := FxSynth.noise(0.03, 1.0, rng, SR)
		tick = FxSynth.biquad(tick, FxSynth.Filter.BANDPASS, 1500.0 + float(i) * 350.0, 2.0, SR)
		tick = FxSynth.perc(tick, 0.0005, 3.0, SR)
		FxSynth.mix_into(out, tick, 0.7, float(i) * 0.065, SR)
	var ping := FxSynth.fm(0.42, 1180.0, 1.99, 4.0, 0.3, 0.7, SR)
	ping = FxSynth.perc(ping, 0.002, 2.6, SR)
	FxSynth.mix_into(out, ping, 0.6, 0.17, SR)
	var body := FxSynth.osc(FxSynth.Wave.SINE, 0.14, 150.0, 105.0, 0.7, SR)
	body = FxSynth.perc(body, 0.001, 3.0, SR)
	FxSynth.mix_into(out, body, 0.5, 0.17, SR)
	return FxSynth.normalize(out, 0.85)


func _denied(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.26)
	for i in 2:
		var v := FxSynth.osc(FxSynth.Wave.SQUARE, 0.075, 168.0 - float(i) * 22.0,
				-1.0, 0.5, SR, null, 0.35)
		v = FxSynth.lowpass1(v, 1600.0, SR)
		v = FxSynth.perc(v, 0.003, 1.4, SR)
		FxSynth.mix_into(out, v, 0.8, float(i) * 0.105, SR)
	return FxSynth.normalize(out, 0.72)


func _ui_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.noise(0.022, 1.0, rng, SR)
	out = FxSynth.biquad(out, FxSynth.Filter.BANDPASS, 2300.0, 1.6, SR)
	out = FxSynth.perc(out, 0.0004, 5.0, SR)
	var tick := FxSynth.osc(FxSynth.Wave.SINE, 0.02, 1600.0, 1100.0, 0.5, SR)
	tick = FxSynth.perc(tick, 0.0003, 4.0, SR)
	FxSynth.mix_into(out, tick, 0.5, 0.0, SR)
	return FxSynth.normalize(out, 0.6)


func _ui_hover(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.osc(FxSynth.Wave.SINE, 0.045, 1420.0, 1560.0, 0.6, SR)
	out = FxSynth.perc(out, 0.004, 2.6, SR)
	return FxSynth.normalize(out, 0.35)


func _panel(rng: RandomNumberGenerator, opening: bool) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.36)
	var air := FxSynth.noise(0.30, 0.8, rng, SR)
	if opening:
		air = FxSynth.filter_sweep(air, FxSynth.Filter.BANDPASS, 500.0, 3200.0, 1.1, SR)
		air = FxSynth.env_shape(air, [[0.0, 0.0], [0.25, 1.0], [1.0, 0.0]])
	else:
		air = FxSynth.filter_sweep(air, FxSynth.Filter.BANDPASS, 3200.0, 420.0, 1.1, SR)
		air = FxSynth.env_shape(air, [[0.0, 1.0], [0.6, 0.5], [1.0, 0.0]])
	FxSynth.mix_into(out, air, 0.55, 0.0, SR)
	var chord := [62.0, 66.0, 69.0] if opening else [57.0, 62.0, 65.0]
	for i in chord.size():
		var f := FxSynth.note_hz(float(chord[i]))
		var v := FxSynth.osc(FxSynth.Wave.TRIANGLE, 0.28, f, f, 0.4, SR)
		v = FxSynth.adsr(v, 0.02 if opening else 0.005, 0.10, 0.35, 0.15, SR)
		FxSynth.mix_into(out, v, 0.35, 0.02 * float(i), SR)
	return FxSynth.normalize(out, 0.7)


func _page(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.noise(0.13, 1.0, rng, SR)
	out = FxSynth.filter_sweep(out, FxSynth.Filter.BANDPASS, 2600.0, 5200.0, 0.8, SR)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.2, 1.0], [0.6, 0.4], [1.0, 0.0]])
	out = FxSynth.tremolo(out, 45.0, 0.5, SR, 90.0)
	return FxSynth.normalize(out, 0.5)


func _notify(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.45)
	var n := [76.0, 83.0]
	for i in n.size():
		var f := FxSynth.note_hz(float(n[i]))
		var v := FxSynth.fm(0.30, f, 3.0, 1.6, 0.1, 0.6, SR)
		v = FxSynth.perc(v, 0.004, 2.6, SR)
		FxSynth.mix_into(out, v, 0.55, float(i) * 0.10, SR)
	return FxSynth.normalize(out, 0.7)


func _beep(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.osc(FxSynth.Wave.SQUARE, 0.07, 1760.0, -1.0, 0.5, SR, null, 0.5)
	out = FxSynth.adsr(out, 0.003, 0.01, 0.8, 0.02, SR)
	out = FxSynth.bitcrush(out, 7.0, 1)
	return FxSynth.normalize(out, 0.5)


func _equip(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.32)
	var slide := FxSynth.noise(0.16, 1.0, rng, SR)
	slide = FxSynth.filter_sweep(slide, FxSynth.Filter.BANDPASS, 1800.0, 4600.0, 1.5, SR)
	slide = FxSynth.env_shape(slide, [[0.0, 0.2], [0.6, 1.0], [1.0, 0.0]])
	FxSynth.mix_into(out, slide, 0.6, 0.0, SR)
	var clip := FxSynth.resonator(0.22, 2100.0, 0.10, 0.8, rng, SR)
	FxSynth.mix_into(out, clip, 0.5, 0.14, SR)
	return FxSynth.normalize(out, 0.75)


func _unlock(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.55)
	for i in 4:
		var tick := FxSynth.noise(0.02, 1.0, rng, SR)
		tick = FxSynth.biquad(tick, FxSynth.Filter.BANDPASS, 1200.0 + float(i) * 260.0, 3.0, SR)
		tick = FxSynth.perc(tick, 0.0004, 4.0, SR)
		FxSynth.mix_into(out, tick, 0.6, float(i) * 0.045, SR)
	var clunk := FxSynth.resonator(0.30, 380.0, 0.16, 0.9, rng, SR)
	FxSynth.mix_into(out, clunk, 0.7, 0.20, SR)
	return FxSynth.normalize(out, 0.8)


func _eat(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.42)
	for i in 2:
		var bite := FxSynth.noise(0.10, 1.0, rng, SR)
		bite = FxSynth.biquad(bite, FxSynth.Filter.BANDPASS, 1400.0, 0.8, SR)
		bite = FxSynth.perc(bite, 0.004, 2.0, SR)
		bite = FxSynth.ring_mod(bite, 60.0 + float(i) * 18.0, 0.5, SR)
		FxSynth.mix_into(out, bite, 0.7, float(i) * 0.17, SR)
	return FxSynth.normalize(out, 0.7)


func _drink(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.55)
	for i in 4:
		var g := FxSynth.osc(FxSynth.Wave.SINE, 0.07,
				FxSynth.vary(rng, 300.0 - float(i) * 22.0, 0.12), 180.0, 0.7, SR)
		g = FxSynth.perc(g, 0.005, 2.0, SR)
		FxSynth.mix_into(out, g, 0.6, float(i) * 0.11, SR)
	out = FxSynth.lowpass1(out, 2200.0, SR)
	return FxSynth.normalize(out, 0.7)


# ------------------------------------------------------------------- combat
func _swing(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.noise(0.19, 1.0, rng, SR)
	out = FxSynth.filter_sweep(out, FxSynth.Filter.BANDPASS,
			FxSynth.vary(rng, 420.0, 0.15), FxSynth.vary(rng, 2600.0, 0.15), 1.3, SR)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.55, 1.0], [1.0, 0.0]])
	return FxSynth.normalize(out, 0.62)


func _mine_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.20)
	var chip := FxSynth.noise(0.06, 1.0, rng, SR)
	chip = FxSynth.biquad(chip, FxSynth.Filter.BANDPASS,
			FxSynth.vary(rng, 1900.0, 0.2), 1.6, SR)
	chip = FxSynth.perc(chip, 0.0006, 4.0, SR)
	FxSynth.mix_into(out, chip, 0.9, 0.0, SR)
	var body := FxSynth.osc(FxSynth.Wave.SINE, 0.08, 150.0, 92.0, 0.8, SR)
	body = FxSynth.perc(body, 0.001, 3.2, SR)
	FxSynth.mix_into(out, body, 0.5, 0.0, SR)
	var ring := FxSynth.resonator(0.10, FxSynth.vary(rng, 2600.0, 0.12), 0.05, 0.4, rng, SR)
	FxSynth.mix_into(out, ring, 0.35, 0.001, SR)
	return FxSynth.normalize(out, 0.72)


func _hit_flesh(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.24)
	var wet := FxSynth.noise(0.13, 1.0, rng, SR)
	wet = FxSynth.lowpass1(wet, 1300.0, SR)
	wet = FxSynth.perc(wet, 0.001, 2.4, SR)
	wet = FxSynth.ring_mod(wet, 42.0, 0.4, SR)
	FxSynth.mix_into(out, wet, 0.8, 0.0, SR)
	var body := FxSynth.osc(FxSynth.Wave.SINE, 0.11,
			FxSynth.vary(rng, 128.0, 0.12), 74.0, 0.9, SR)
	body = FxSynth.perc(body, 0.001, 2.8, SR)
	FxSynth.mix_into(out, body, 0.7, 0.0, SR)
	return FxSynth.normalize(out, 0.85)


func _hit_metal(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.55)
	var partials := [1420.0, 2310.0, 3870.0, 5210.0]
	for i in partials.size():
		var f := FxSynth.vary(rng, float(partials[i]), 0.06)
		var r := FxSynth.resonator(0.5, f, 0.28 - float(i) * 0.05, 0.8 - float(i) * 0.15, rng, SR)
		FxSynth.mix_into(out, r, 0.55, 0.0, SR)
	var clank := FxSynth.noise(0.03, 1.0, rng, SR)
	clank = FxSynth.biquad(clank, FxSynth.Filter.HIGHPASS, 1800.0, 0.8, SR)
	clank = FxSynth.perc(clank, 0.0004, 4.0, SR)
	FxSynth.mix_into(out, clank, 0.8, 0.0, SR)
	return FxSynth.normalize(out, 0.88)


func _crit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _hit_metal(rng)
	var shine := FxSynth.fm(0.35, 3200.0, 1.5, 6.0, 0.5, 0.6, SR)
	shine = FxSynth.perc(shine, 0.001, 3.0, SR)
	out = FxSynth.mix_into(out, shine, 0.6, 0.0, SR)
	return FxSynth.normalize(out, 0.95)


func _arrow(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.24)
	var air := FxSynth.noise(0.20, 1.0, rng, SR)
	air = FxSynth.filter_sweep(air, FxSynth.Filter.BANDPASS, 1600.0, 4200.0, 2.2, SR)
	air = FxSynth.env_shape(air, [[0.0, 0.1], [0.3, 1.0], [1.0, 0.0]])
	FxSynth.mix_into(out, air, 0.6, 0.0, SR)
	var whistle := FxSynth.osc(FxSynth.Wave.SINE, 0.18, 2600.0, 3600.0, 0.35, SR)
	whistle = FxSynth.env_shape(whistle, [[0.0, 0.0], [0.4, 1.0], [1.0, 0.0]])
	FxSynth.mix_into(out, whistle, 0.4, 0.0, SR)
	return FxSynth.normalize(out, 0.62)


func _bow_draw(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.noise(0.42, 1.0, rng, SR)
	out = FxSynth.filter_sweep(out, FxSynth.Filter.BANDPASS, 700.0, 1500.0, 3.0, SR)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.15, 0.8], [0.8, 1.0], [1.0, 0.0]])
	out = FxSynth.tremolo(out, 22.0, 0.35, SR, 9.0)
	return FxSynth.normalize(out, 0.5)


func _laser(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.32)
	var beam := FxSynth.osc(FxSynth.Wave.SAW, 0.22,
			FxSynth.vary(rng, 1900.0, 0.08), 380.0, 0.8, SR)
	beam = FxSynth.ring_mod(beam, 118.0, 0.5, SR)
	beam = FxSynth.filter_sweep(beam, FxSynth.Filter.LOWPASS, 6000.0, 900.0, 3.0, SR)
	beam = FxSynth.perc(beam, 0.002, 1.8, SR)
	FxSynth.mix_into(out, beam, 0.8, 0.0, SR)
	var zip := FxSynth.osc(FxSynth.Wave.SQUARE, 0.06, 3200.0, 1400.0, 0.4, SR, null, 0.3)
	zip = FxSynth.perc(zip, 0.0005, 3.0, SR)
	FxSynth.mix_into(out, zip, 0.4, 0.0, SR)
	out = FxSynth.bitcrush(out, 8.0, 1)
	return FxSynth.normalize(out, 0.8)


func _zap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.noise(0.26, 1.0, rng, SR)
	out = FxSynth.biquad(out, FxSynth.Filter.BANDPASS, 2600.0, 1.2, SR)
	out = FxSynth.ring_mod(out, 320.0, 0.8, SR)
	out = FxSynth.bitcrush(out, 4.0, 3)
	out = FxSynth.env_shape(out, [[0.0, 1.0], [0.25, 0.5], [0.5, 0.8], [1.0, 0.0]])
	return FxSynth.normalize(out, 0.8)


func _charge(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.05)
	var core := FxSynth.osc(FxSynth.Wave.SAW, 1.0, 90.0, 880.0, 0.6, SR)
	core = FxSynth.filter_sweep(core, FxSynth.Filter.BANDPASS, 300.0, 2600.0, 2.4, SR)
	core = FxSynth.tremolo(core, 6.0, 0.6, SR, 34.0)
	FxSynth.mix_into(out, core, 0.7, 0.0, SR)
	var sub := FxSynth.osc(FxSynth.Wave.SINE, 1.0, 55.0, 120.0, 0.5, SR)
	FxSynth.mix_into(out, sub, 0.5, 0.0, SR)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.7, 0.8], [0.95, 1.0], [1.0, 0.0]])
	return FxSynth.normalize(out, 0.8)


func _shield(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.55)
	for i in 3:
		var f := 420.0 * (1.0 + float(i) * 0.5)
		var v := FxSynth.osc(FxSynth.Wave.SINE, 0.45, f * 0.7, f, 0.5, SR)
		v = FxSynth.adsr(v, 0.02, 0.15, 0.4, 0.25, SR)
		FxSynth.mix_into(out, v, 0.45, 0.0, SR)
	out = FxSynth.ring_mod(out, 7.0, 0.3, SR)
	out = FxSynth.reverb(out, 0.4, 0.4, 0.25, SR)
	return FxSynth.normalize(out, 0.72)


func _tool_break(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.55)
	var snap := FxSynth.noise(0.05, 1.0, rng, SR)
	snap = FxSynth.biquad(snap, FxSynth.Filter.BANDPASS, 2400.0, 1.0, SR)
	snap = FxSynth.perc(snap, 0.0004, 3.0, SR)
	FxSynth.mix_into(out, snap, 0.9, 0.0, SR)
	for i in 5:
		var bit := FxSynth.resonator(0.2, rng.randf_range(700.0, 3400.0), 0.09, 0.5, rng, SR)
		FxSynth.mix_into(out, bit, 0.35, 0.03 + rng.randf() * 0.22, SR)
	var sad := FxSynth.osc(FxSynth.Wave.TRIANGLE, 0.3, 300.0, 190.0, 0.4, SR)
	sad = FxSynth.perc(sad, 0.01, 2.0, SR)
	FxSynth.mix_into(out, sad, 0.4, 0.10, SR)
	return FxSynth.normalize(out, 0.85)


## Short creature vocal: a formant-filtered growl with a wobble. Every monster
## alert, hiss and howl in the game routes here through `ALIASES`.
func _growl(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.55)
	var f0 := FxSynth.vary(rng, 150.0, 0.25)
	for i in 2:
		var v := FxSynth.osc(FxSynth.Wave.SAW, 0.42, f0 * (1.0 + float(i) * 0.013),
				f0 * rng.randf_range(0.7, 1.25), 0.5, SR)
		FxSynth.mix_into(out, v, 0.5, 0.0, SR)
	# Two formants turn a buzz into a throat.
	out = FxSynth.biquad(out, FxSynth.Filter.PEAK, FxSynth.vary(rng, 620.0, 0.2), 3.0, SR, 12.0)
	out = FxSynth.biquad(out, FxSynth.Filter.PEAK, FxSynth.vary(rng, 1450.0, 0.2), 4.0, SR, 9.0)
	out = FxSynth.lowpass1(out, 2600.0, SR)
	out = FxSynth.tremolo(out, rng.randf_range(18.0, 32.0), 0.45, SR, rng.randf_range(10.0, 22.0))
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.1, 1.0], [0.6, 0.8], [1.0, 0.0]])
	var breath := FxSynth.noise(0.4, 0.5, rng, SR)
	breath = FxSynth.biquad(breath, FxSynth.Filter.BANDPASS, 900.0, 0.7, SR)
	breath = FxSynth.perc(breath, 0.03, 1.5, SR)
	FxSynth.mix_into(out, breath, 0.4, 0.02, SR)
	out = FxSynth.distort(out, 2.4)
	return FxSynth.normalize(out, 0.88)


func _boss_roar(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.60)
	for i in 3:
		var det := 1.0 + float(i) * 0.017
		var v := FxSynth.osc(FxSynth.Wave.SAW, 1.35, 70.0 * det, 46.0 * det, 0.5, SR)
		v = FxSynth.filter_sweep(v, FxSynth.Filter.LOWPASS, 1400.0, 400.0, 2.0, SR)
		FxSynth.mix_into(out, v, 0.5, 0.0, SR)
	var growl := FxSynth.noise(1.3, 0.7, rng, SR)
	growl = FxSynth.biquad(growl, FxSynth.Filter.BANDPASS, 480.0, 0.7, SR)
	FxSynth.mix_into(out, growl, 0.5, 0.02, SR)
	out = FxSynth.tremolo(out, 24.0, 0.4, SR, 15.0)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.08, 1.0], [0.7, 0.85], [1.0, 0.0]])
	out = FxSynth.distort(out, 3.2)
	out = FxSynth.reverb(out, 0.8, 0.35, 0.3, SR)
	return FxSynth.normalize(out, 0.98)


# ---------------------------------------------------------------- explosions
func _explosion(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.60)
	var blast := FxSynth.noise(1.35, 1.0, rng, SR)
	blast = FxSynth.filter_sweep(blast, FxSynth.Filter.LOWPASS, 5200.0, 130.0, 1.1, SR)
	blast = FxSynth.env_shape(blast, [[0.0, 1.0], [0.12, 0.65], [0.5, 0.25], [1.0, 0.0]])
	FxSynth.mix_into(out, blast, 0.9, 0.0, SR)
	var sub := FxSynth.osc(FxSynth.Wave.SINE, 0.65, FxSynth.vary(rng, 78.0, 0.1), 28.0, 1.0, SR)
	sub = FxSynth.perc(sub, 0.002, 2.2, SR)
	FxSynth.mix_into(out, sub, 0.9, 0.0, SR)
	for i in 8:
		var deb := FxSynth.noise(0.05, 1.0, rng, SR)
		deb = FxSynth.biquad(deb, FxSynth.Filter.BANDPASS, rng.randf_range(600.0, 4200.0), 2.0, SR)
		deb = FxSynth.perc(deb, 0.0005, 4.0, SR)
		FxSynth.mix_into(out, deb, 0.3, 0.08 + rng.randf() * 0.8, SR)
	out = FxSynth.distort(out, 2.4)
	out = FxSynth.reverb(out, 0.85, 0.3, 0.35, SR)
	return FxSynth.normalize(out, 1.0)


func _thunder(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(2.20)
	var crack := FxSynth.noise(0.30, 1.0, rng, SR)
	crack = FxSynth.filter_sweep(crack, FxSynth.Filter.BANDPASS, 3000.0, 700.0, 0.9, SR)
	crack = FxSynth.perc(crack, 0.001, 2.5, SR)
	FxSynth.mix_into(out, crack, 0.8, 0.0, SR)
	var rumble := FxSynth.noise(1.9, 1.0, rng, SR)
	rumble = FxSynth.lowpass1(rumble, 220.0, SR)
	rumble = FxSynth.lowpass1(rumble, 300.0, SR)
	rumble = FxSynth.env_shape(rumble, [[0.0, 0.3], [0.15, 1.0], [0.45, 0.55], [0.7, 0.8], [1.0, 0.0]])
	FxSynth.mix_into(out, rumble, 1.0, 0.10, SR)
	out = FxSynth.reverb(out, 1.0, 0.25, 0.4, SR)
	return FxSynth.normalize(out, 0.95)


# ------------------------------------------------------------------- element
func _burn(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.noise(0.75, 1.0, rng, SR)
	out = FxSynth.biquad(out, FxSynth.Filter.BANDPASS, 1400.0, 0.5, SR)
	out = FxSynth.tremolo(out, 17.0, 0.6, SR, 9.0)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.1, 1.0], [0.6, 0.6], [1.0, 0.0]])
	var whoosh := FxSynth.osc(FxSynth.Wave.PINK, 0.4, 1.0, -1.0, 0.6, SR, rng)
	whoosh = FxSynth.perc(whoosh, 0.02, 1.6, SR)
	out = FxSynth.mix_into(out, whoosh, 0.5, 0.0, SR)
	return FxSynth.normalize(out, 0.7)


func _freeze(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.85)
	for i in 5:
		var f := 2200.0 + float(i) * 1150.0
		var v := FxSynth.resonator(0.7, f, 0.35 - float(i) * 0.05, 0.7, null, SR)
		FxSynth.mix_into(out, v, 0.4, float(i) * 0.035, SR)
	var crackle := FxSynth.osc(FxSynth.Wave.SINE, 0.6, 900.0, 260.0, 0.4, SR)
	crackle = FxSynth.perc(crackle, 0.01, 2.0, SR)
	FxSynth.mix_into(out, crackle, 0.5, 0.0, SR)
	out = FxSynth.reverb(out, 0.5, 0.2, 0.3, SR)
	return FxSynth.normalize(out, 0.75)


func _poison(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.80)
	for i in 6:
		var b := FxSynth.osc(FxSynth.Wave.SINE, 0.10,
				rng.randf_range(220.0, 620.0), rng.randf_range(120.0, 300.0), 0.6, SR)
		b = FxSynth.perc(b, 0.004, 2.4, SR)
		FxSynth.mix_into(out, b, 0.45, rng.randf() * 0.62, SR)
	out = FxSynth.lowpass1(out, 1800.0, SR)
	return FxSynth.normalize(out, 0.62)


func _bubble(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.28)
	for i in 3:
		var b := FxSynth.osc(FxSynth.Wave.SINE, 0.07,
				rng.randf_range(500.0, 1100.0), rng.randf_range(900.0, 1800.0), 0.6, SR)
		b = FxSynth.perc(b, 0.003, 3.0, SR)
		FxSynth.mix_into(out, b, 0.5, float(i) * 0.06 + rng.randf() * 0.03, SR)
	return FxSynth.normalize(out, 0.55)


func _splash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.70)
	var body := FxSynth.noise(0.45, 1.0, rng, SR)
	body = FxSynth.filter_sweep(body, FxSynth.Filter.LOWPASS, 4200.0, 700.0, 1.0, SR)
	body = FxSynth.env_shape(body, [[0.0, 1.0], [0.25, 0.5], [1.0, 0.0]])
	FxSynth.mix_into(out, body, 0.8, 0.0, SR)
	var gulp := FxSynth.osc(FxSynth.Wave.SINE, 0.18, 640.0, 180.0, 0.7, SR)
	gulp = FxSynth.perc(gulp, 0.004, 2.2, SR)
	FxSynth.mix_into(out, gulp, 0.6, 0.0, SR)
	for i in 4:
		var d := FxSynth.osc(FxSynth.Wave.SINE, 0.05,
				rng.randf_range(900.0, 2200.0), rng.randf_range(1400.0, 3000.0), 0.5, SR)
		d = FxSynth.perc(d, 0.002, 3.0, SR)
		FxSynth.mix_into(out, d, 0.35, 0.12 + rng.randf() * 0.4, SR)
	return FxSynth.normalize(out, 0.85)


func _lava(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.70)
	var rumble := FxSynth.osc(FxSynth.Wave.PINK, 1.6, 1.0, -1.0, 1.0, SR, rng)
	rumble = FxSynth.lowpass1(rumble, 180.0, SR)
	rumble = FxSynth.tremolo(rumble, 2.4, 0.5, SR, 3.6)
	FxSynth.mix_into(out, rumble, 1.0, 0.0, SR)
	for i in 6:
		var pop := FxSynth.osc(FxSynth.Wave.SINE, 0.09,
				rng.randf_range(120.0, 320.0), rng.randf_range(50.0, 110.0), 0.7, SR)
		pop = FxSynth.perc(pop, 0.002, 2.6, SR)
		FxSynth.mix_into(out, pop, 0.5, rng.randf() * 1.5, SR)
	out = FxSynth.distort(out, 1.8)
	return FxSynth.normalize(out, 0.8)


func _machine(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.00)
	var hum := FxSynth.osc(FxSynth.Wave.SAW, 0.95, 92.0, -1.0, 0.4, SR)
	hum = FxSynth.lowpass1(hum, 900.0, SR)
	FxSynth.mix_into(out, hum, 0.6, 0.0, SR)
	for i in 5:
		var clank := FxSynth.resonator(0.16, rng.randf_range(600.0, 1900.0), 0.07, 0.6, rng, SR)
		FxSynth.mix_into(out, clank, 0.35, float(i) * 0.19, SR)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.08, 1.0], [0.9, 1.0], [1.0, 0.0]])
	return FxSynth.normalize(out, 0.62)


func _scan(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.70)
	for i in 3:
		var v := FxSynth.osc(FxSynth.Wave.SINE, 0.16, 900.0 + float(i) * 420.0,
				1400.0 + float(i) * 520.0, 0.5, SR)
		v = FxSynth.adsr(v, 0.01, 0.04, 0.5, 0.08, SR)
		FxSynth.mix_into(out, v, 0.5, float(i) * 0.18, SR)
	out = FxSynth.bitcrush(out, 9.0, 1)
	return FxSynth.normalize(out, 0.6)


# ------------------------------------------------------------------- objects
func _door(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.85)
	var creak := FxSynth.osc(FxSynth.Wave.SAW, 0.55,
			FxSynth.vary(rng, 260.0, 0.15), FxSynth.vary(rng, 190.0, 0.15), 0.5, SR)
	creak = FxSynth.tremolo(creak, 12.0, 0.85, SR, 26.0)
	creak = FxSynth.biquad(creak, FxSynth.Filter.BANDPASS, 1100.0, 3.0, SR)
	creak = FxSynth.env_shape(creak, [[0.0, 0.0], [0.15, 1.0], [0.8, 0.6], [1.0, 0.0]])
	FxSynth.mix_into(out, creak, 0.7, 0.0, SR)
	var latch := FxSynth.resonator(0.25, 420.0, 0.10, 0.9, rng, SR)
	FxSynth.mix_into(out, latch, 0.7, 0.55, SR)
	return FxSynth.normalize(out, 0.8)


func _chest(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.95)
	var creak := FxSynth.osc(FxSynth.Wave.SAW, 0.40, 180.0, 240.0, 0.5, SR)
	creak = FxSynth.tremolo(creak, 15.0, 0.8, SR, 30.0)
	creak = FxSynth.biquad(creak, FxSynth.Filter.BANDPASS, 800.0, 3.0, SR)
	creak = FxSynth.env_shape(creak, [[0.0, 0.0], [0.2, 1.0], [1.0, 0.0]])
	FxSynth.mix_into(out, creak, 0.6, 0.0, SR)
	var lid := FxSynth.resonator(0.35, 210.0, 0.14, 0.9, rng, SR)
	FxSynth.mix_into(out, lid, 0.8, 0.42, SR)
	var ping := FxSynth.fm(0.4, 1800.0, 2.0, 3.0, 0.2, 0.5, SR)
	ping = FxSynth.perc(ping, 0.002, 3.0, SR)
	FxSynth.mix_into(out, ping, 0.35, 0.48, SR)
	return FxSynth.normalize(out, 0.85)


# ---------------------------------------------------------------- progression
func _levelup(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.30)
	var arp := [60.0, 64.0, 67.0, 72.0, 76.0, 79.0]
	for i in arp.size():
		var f := FxSynth.note_hz(float(arp[i]))
		var v := FxSynth.fm(0.6, f, 2.0, 2.4, 0.2, 0.55, SR)
		v = FxSynth.perc(v, 0.004, 2.2, SR)
		FxSynth.mix_into(out, v, 0.5, float(i) * 0.085, SR)
	var rise := FxSynth.noise(0.55, 0.5, null, SR)
	rise = FxSynth.filter_sweep(rise, FxSynth.Filter.BANDPASS, 800.0, 6000.0, 1.5, SR)
	rise = FxSynth.env_shape(rise, [[0.0, 0.0], [0.85, 0.7], [1.0, 0.0]])
	FxSynth.mix_into(out, rise, 0.4, 0.0, SR)
	out = FxSynth.reverb(out, 0.6, 0.3, 0.28, SR)
	return FxSynth.normalize(out, 0.9)


func _quest(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.00)
	var motif := [67.0, 71.0, 74.0]
	for i in motif.size():
		var f := FxSynth.note_hz(float(motif[i]))
		var v := FxSynth.fm(0.55, f, 3.0, 1.8, 0.15, 0.55, SR)
		v = FxSynth.perc(v, 0.006, 2.0, SR)
		FxSynth.mix_into(out, v, 0.55, float(i) * 0.12, SR)
	out = FxSynth.reverb(out, 0.55, 0.35, 0.25, SR)
	return FxSynth.normalize(out, 0.82)


# ================================================== the two signature mechanics
## A Shepard-style cluster: `octaves` sines an octave apart, all gliding by the
## same interval while a rotating amplitude window hands the glide from one
## octave to the next. The pitch appears to turn continuously without ever
## actually going anywhere — which is precisely what a flip does to the world.
func _shepard(dur: float, base: float, octaves: int, glide: float,
		spin: float) -> PackedFloat32Array:
	var n := FxSynth.samples(dur, SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var isr := 1.0 / float(SR)
	var inv := 1.0 / float(maxi(1, n - 1))
	var phases := PackedFloat32Array()
	phases.resize(octaves)
	for i in n:
		var t := float(i) * inv
		var bend := pow(glide, t)
		var acc := 0.0
		for k in octaves:
			var f: float = base * pow(2.0, float(k)) * bend
			if f > float(SR) * 0.45:
				continue
			phases[k] = fposmod(phases[k] + f * isr, 1.0)
			# Rotating raised-cosine window over the octave stack.
			var w := 0.5 - 0.5 * cos(TAU * fposmod(float(k) / float(octaves) + t * spin, 1.0))
			acc += sin(phases[k] * TAU) * w
		out[i] = acc / float(octaves)
	return out


## FLIP — the world turns. A rising-then-falling filtered whoosh, a Shepard
## cluster rotating up a fourth, a paper-riffle flutter whose rate accelerates,
## and a sub thump on the beat the new plane snaps into place.
func _flip(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.62
	var out := FxSynth.buffer(dur + 0.25)

	var rot := _shepard(dur * 0.95, 138.0, 5, 1.3348, 1.0)
	rot = FxSynth.env_shape(rot, [[0.0, 0.0], [0.12, 1.0], [0.72, 0.85], [1.0, 0.0]])
	rot = FxSynth.filter_sweep(rot, FxSynth.Filter.LOWPASS, 1200.0, 5200.0, 1.1, SR)
	FxSynth.mix_into(out, rot, 0.75, 0.0, SR)

	var air := FxSynth.noise(dur * 0.9, 1.0, rng, SR)
	air = FxSynth.filter_sweep(air, FxSynth.Filter.BANDPASS, 320.0, 3900.0, 1.5, SR)
	air = FxSynth.env_shape(air, [[0.0, 0.0], [0.45, 1.0], [0.8, 0.45], [1.0, 0.0]])
	FxSynth.mix_into(out, air, 0.55, 0.0, SR)

	var flutter := FxSynth.noise(0.34, 1.0, rng, SR)
	flutter = FxSynth.biquad(flutter, FxSynth.Filter.BANDPASS, 2400.0, 1.1, SR)
	flutter = FxSynth.tremolo(flutter, 9.0, 0.95, SR, 46.0)
	flutter = FxSynth.env_shape(flutter, [[0.0, 0.3], [0.5, 1.0], [1.0, 0.0]])
	FxSynth.mix_into(out, flutter, 0.4, 0.05, SR)

	var snap := FxSynth.osc(FxSynth.Wave.SINE, 0.22, 132.0, 46.0, 1.0, SR)
	snap = FxSynth.perc(snap, 0.001, 2.6, SR)
	FxSynth.mix_into(out, snap, 0.85, 0.44, SR)
	var tick := FxSynth.noise(0.03, 1.0, rng, SR)
	tick = FxSynth.biquad(tick, FxSynth.Filter.BANDPASS, 4200.0, 1.4, SR)
	tick = FxSynth.perc(tick, 0.0004, 4.0, SR)
	FxSynth.mix_into(out, tick, 0.5, 0.44, SR)

	out = FxSynth.reverb(out, 0.45, 0.4, 0.22, SR)
	return FxSynth.normalize(out, 0.95)


## SHIFT — a step into the page. Deliberately the quiet sibling of `flip`:
## a muffled thunk, one page-turn rustle, and a short breath of air pressure.
func _shift(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(0.34)

	var thunk := FxSynth.osc(FxSynth.Wave.SINE, 0.20,
			FxSynth.vary(rng, 158.0, 0.05), 92.0, 1.0, SR)
	thunk = FxSynth.perc(thunk, 0.004, 2.8, SR)
	FxSynth.mix_into(out, thunk, 0.85, 0.0, SR)

	var rustle := FxSynth.noise(0.11, 1.0, rng, SR)
	rustle = FxSynth.biquad(rustle, FxSynth.Filter.BANDPASS,
			FxSynth.vary(rng, 1750.0, 0.12), 0.9, SR)
	rustle = FxSynth.tremolo(rustle, 30.0, 0.7, SR, 62.0)
	rustle = FxSynth.env_shape(rustle, [[0.0, 0.0], [0.3, 1.0], [1.0, 0.0]])
	FxSynth.mix_into(out, rustle, 0.45, 0.01, SR)

	var press := FxSynth.osc(FxSynth.Wave.SINE, 0.16, 300.0, 210.0, 0.4, SR)
	press = FxSynth.adsr(press, 0.03, 0.06, 0.3, 0.07, SR)
	FxSynth.mix_into(out, press, 0.3, 0.0, SR)

	out = FxSynth.lowpass1(out, 2400.0, SR)
	return FxSynth.normalize(out, 0.66)


# ------------------------------------------------------------------- travel
func _teleport(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.00)
	for k in 4:
		var f := 260.0 * pow(1.5, float(k))
		var v := FxSynth.osc(FxSynth.Wave.SINE, 0.75, f, f * 3.2, 0.5, SR)
		v = FxSynth.env_shape(v, [[0.0, 0.0], [0.3, 1.0], [1.0, 0.0]])
		FxSynth.mix_into(out, v, 0.4, float(k) * 0.045, SR)
	var grit := FxSynth.noise(0.5, 0.6, rng, SR)
	grit = FxSynth.bitcrush(grit, 3.0, 5)
	grit = FxSynth.biquad(grit, FxSynth.Filter.BANDPASS, 2600.0, 1.0, SR)
	grit = FxSynth.env_shape(grit, [[0.0, 0.4], [0.5, 1.0], [1.0, 0.0]])
	FxSynth.mix_into(out, grit, 0.35, 0.12, SR)
	out = FxSynth.reverb(out, 0.7, 0.3, 0.4, SR)
	return FxSynth.normalize(out, 0.85)


func _warp(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.buffer(1.90)
	for k in 3:
		var det := 1.0 + float(k) * 0.02
		var v := FxSynth.osc(FxSynth.Wave.SAW, 1.5, 110.0 * det, 1500.0 * det, 0.45, SR)
		v = FxSynth.filter_sweep(v, FxSynth.Filter.LOWPASS, 700.0, 7000.0, 2.6, SR)
		FxSynth.mix_into(out, v, 0.45, 0.0, SR)
	var sub := FxSynth.osc(FxSynth.Wave.SINE, 1.6, 46.0, 30.0, 0.8, SR)
	FxSynth.mix_into(out, sub, 0.6, 0.0, SR)
	var wind := FxSynth.noise(1.6, 0.6, rng, SR)
	wind = FxSynth.filter_sweep(wind, FxSynth.Filter.BANDPASS, 500.0, 5200.0, 1.0, SR)
	FxSynth.mix_into(out, wind, 0.4, 0.0, SR)
	out = FxSynth.env_shape(out, [[0.0, 0.0], [0.15, 0.7], [0.78, 1.0], [0.86, 0.5], [1.0, 0.0]])
	out = FxSynth.reverb(out, 0.95, 0.25, 0.42, SR)
	return FxSynth.normalize(out, 0.95)


func _blip(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := FxSynth.osc(FxSynth.Wave.TRIANGLE, 0.10, 660.0, 520.0, 0.6, SR)
	out = FxSynth.perc(out, 0.003, 2.4, SR)
	return FxSynth.normalize(out, 0.5)
