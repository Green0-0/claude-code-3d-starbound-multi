## Autoloaded as `Status`. The status-effect engine for *every* `VoxelEntity`
## in the game, and the parent of the rest of the survival simulation.
##
## ## What lives here
##
## * the effect **registry** (`survival/effects/*.gd`, ~49 definitions);
## * the per-entity **holders** — which effects are running, for how long, at
##   how many stacks — plus the flattened modifier cache;
## * the two **perspective hooks** the signature effects need: a reference
##   counted flip lock (`plane_locked`) and the interaction-depth widening
##   (`phase_sight`);
## * the survival subsystems, added as children so they tick with the game and
##   pause with it: [member needs], [member environment], [member weather],
##   [member farming], [member cooking], [member medical].
##
## ## The contract other modules use
##
## ```gdscript
## Status.apply(&"burning", monster, 6.0)      # duration <0 uses the default
## Status.remove(&"burning", monster)
## if Status.has(&"frozen", monster): ...
## amount *= Status.modifier("damage_taken", target)
## ```
##
## [method modifier] is called several times per damage packet, so it is a
## dictionary lookup into a cache that is only rebuilt when the entity's effect
## set actually changes.
extends Node

## Emitted for every target, unlike `Events.status_applied` which is
## player-only (the HUD has no target parameter to filter on).
signal effect_applied(target: Node, id: StringName, stacks: int, duration: float)
signal effect_removed(target: Node, id: StringName, reason: String)
## Coarse "something about this entity's effects changed" pulse, for renderers.
signal effects_changed(target: Node)

# ------------------------------------------------------------- subsystems
var needs: SrvNeeds = null
var environment: SrvEnvironment = null
var weather: SrvWeather = null
var farming: SrvFarming = null
var cooking: SrvCooking = null
var medical: SrvMedical = null

## Spellings other modules already use, mapped onto the canonical ids. Cheaper
## than asking six agents to rename a constant, and it means a status id typo
## degrades into the right effect instead of a warning and nothing happening.
const ALIASES := {
	&"water_breathing": &"breathing", &"oxygen": &"breathing",
	&"poison": &"poisoned", &"bleed": &"bleeding", &"burn": &"burning",
	&"on_fire": &"burning", &"ignited": &"burning", &"freeze": &"frozen",
	&"cold": &"chilled", &"shock": &"shocked", &"electrified": &"shocked",
	&"radiation": &"irradiated", &"speed": &"haste", &"slowness": &"slow",
	&"slowed": &"slow", &"night_sight": &"night_vision",
	&"low_gravity": &"gravity_reduced", &"lightweight": &"gravity_reduced",
	&"stuck": &"slimed", &"acid": &"corroded", &"soaked": &"wet",
	&"hungry": &"peckish", &"tired": &"drowsy", &"warmth": &"warm",
	&"phaselock": &"plane_locked", &"plane_lock": &"plane_locked",
	&"phasesight": &"phase_sight", &"phase": &"phase_sight",
}

# --------------------------------------------------------------- registry
var _defs: Dictionary = {}          ## StringName -> SrvStatusEffect
var _holders: Dictionary = {}       ## int instance id -> SrvStatusHolder

## Reference count of active plane locks. `View.flips_enabled` is only handed
## back when this returns to zero, so overlapping locks compose.
var _flip_locks: int = 0
var _flips_were_enabled: bool = true

## Extra depth layers the player can currently see and reach through.
var phase_sight_layers: int = 0

var _sweep := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = -10
	_rng.randomize()
	SrvEffectLibrary.register_all(self)
	# Cheap and always correct: any change to the player's effect set may have
	# changed how many extra depth layers `phase_sight` is granting.
	effects_changed.connect(func(t: Node) -> void:
		if t != null and t == Game.player:
			refresh_phase_sight())
	Events.entity_died.connect(_on_entity_died)
	Events.player_died.connect(_on_player_died)
	Events.world_unloaded.connect(_on_world_unloaded)
	_spawn_subsystems()
	print("[Status] %d status effects registered" % _defs.size())


func _spawn_subsystems() -> void:
	needs = SrvNeeds.new()
	needs.name = "Needs"
	add_child(needs)
	environment = SrvEnvironment.new()
	environment.name = "Environment"
	add_child(environment)
	weather = SrvWeather.new()
	weather.name = "Weather"
	add_child(weather)
	farming = SrvFarming.new()
	farming.name = "Farming"
	add_child(farming)
	cooking = SrvCooking.new()
	cooking.name = "Cooking"
	add_child(cooking)
	medical = SrvMedical.new()
	medical.name = "Medical"
	add_child(medical)


# ==================================================================== registry
## Register one effect definition. Returns it so the content files can chain.
func define(id: StringName, display: String = "") -> SrvStatusEffect:
	if _defs.has(id):
		push_error("[Status] duplicate status effect '%s'" % id)
		return _defs[id]
	var e := SrvStatusEffect.new(id, display)
	_defs[id] = e
	return e


## Resolve an alias (or an already-canonical id) to the registered id.
func canonical(id: StringName) -> StringName:
	if _defs.has(id):
		return id
	return ALIASES.get(id, id)


func definition(id: StringName) -> SrvStatusEffect:
	var d: SrvStatusEffect = _defs.get(canonical(id))
	return d


func is_defined(id: StringName) -> bool:
	return _defs.has(canonical(id))


func all_definitions() -> Array:
	return _defs.values()


# ================================================================== apply API
## Apply `id` to `target` (defaults to the player). `duration` below zero uses
## the definition's own default; `SrvStatusEffect.PERMANENT` means open-ended.
func apply(p_id: StringName, target: Node, duration: float = -1.0, stacks: int = 1) -> void:
	var id := canonical(p_id)
	var def: SrvStatusEffect = _defs.get(id)
	if def == null:
		push_warning("[Status] unknown status effect '%s'" % p_id)
		return
	var subject := _resolve(target)
	if subject == null:
		return
	var ve := subject as VoxelEntity
	if ve != null and ve.dead:
		return

	var h := _holder_for(subject, true)
	for b: StringName in def.blocked_by:
		if h.effects.has(b):
			return
	for c: StringName in def.cancels:
		if h.effects.has(c):
			_finish(h, c, "cancelled")

	# A negative duration means "use the definition's default", and that default
	# may itself be PERMANENT — which is exactly the value we want to keep.
	var dur := duration if duration >= 0.0 else def.default_duration

	var existing: SrvStatusHolder.Active = h.effects.get(id)
	if existing != null:
		_restack(h, existing, dur, stacks)
		return

	var act := SrvStatusHolder.Active.new(def, dur, stacks)
	h.effects[id] = act
	h.dirty = true
	if def.on_apply.is_valid():
		def.on_apply.call(subject, act)
	if def.apply_sound != &"":
		Events.play_sound.emit(def.apply_sound, _pos_of(subject))
	effect_applied.emit(subject, id, act.stacks, act.duration)
	effects_changed.emit(subject)
	if h.is_player:
		Events.status_applied.emit(String(id), act.duration)


func _restack(h: SrvStatusHolder, act: SrvStatusHolder.Active, dur: float, stacks: int) -> void:
	match act.def.stack_mode:
		SrvStatusEffect.Stack.IGNORE:
			return
		SrvStatusEffect.Stack.EXTEND:
			if act.is_permanent() or dur < 0.0:
				act.remaining = SrvStatusEffect.PERMANENT
				act.duration = SrvStatusEffect.PERMANENT
			else:
				act.remaining += dur
				act.duration = maxf(act.duration, act.remaining)
		SrvStatusEffect.Stack.STACK:
			var before := act.stacks
			act.stacks = clampi(act.stacks + maxi(1, stacks), 1, act.def.max_stacks)
			_refresh_timer(act, dur)
			if act.stacks != before:
				h.dirty = true
		_:
			_refresh_timer(act, dur)
	effect_applied.emit(h.target, act.def.id, act.stacks, act.duration)
	effects_changed.emit(h.target)
	if h.is_player:
		Events.status_applied.emit(String(act.def.id), act.duration)


func _refresh_timer(act: SrvStatusHolder.Active, dur: float) -> void:
	if dur < 0.0:
		act.remaining = SrvStatusEffect.PERMANENT
		act.duration = SrvStatusEffect.PERMANENT
	elif act.is_permanent():
		pass
	else:
		act.remaining = maxf(act.remaining, dur)
		act.duration = maxf(act.duration, act.remaining)


## Apply a list of `{"id": ..., "duration": ...}` dictionaries — the shape
## `ItemType.with_effect()` produces.
func apply_list(entries: Array, target: Node) -> void:
	for e in entries:
		if e is Dictionary:
			var d: Dictionary = e
			apply(StringName(d.get("id", &"")), target,
				float(d.get("duration", -1.0)), int(d.get("stacks", 1)))


## Roll a `{"id", "chance", "duration", "stacks"}` entry — the shape
## `combat/damage.gd`'s `status_on_hit` packets use.
func try_apply(entry: Dictionary, target: Node) -> bool:
	var chance := float(entry.get("chance", 1.0))
	if chance < 1.0 and _rng.randf() > chance:
		return false
	apply(StringName(entry.get("id", &"")), target,
		float(entry.get("duration", -1.0)), int(entry.get("stacks", 1)))
	return true


func remove(p_id: StringName, target: Node) -> void:
	var subject := _resolve(target)
	if subject == null:
		return
	var id := canonical(p_id)
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h != null and h.effects.has(id):
		_finish(h, id, "removed")


## Drop one stack; removes the effect entirely when the last stack goes.
func remove_stack(id: StringName, target: Node, count: int = 1) -> void:
	var subject := _resolve(target)
	if subject == null:
		return
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return
	var act: SrvStatusHolder.Active = h.effects.get(id)
	if act == null:
		return
	act.stacks -= maxi(1, count)
	h.dirty = true
	if act.stacks <= 0:
		_finish(h, id, "removed")
	else:
		effects_changed.emit(h.target)


func has(id: StringName, target: Node) -> bool:
	var subject := _resolve(target)
	if subject == null:
		return false
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	return h != null and h.effects.has(canonical(id))


## Seconds left, `INF` for a permanent effect, 0.0 when not present.
func remaining(id: StringName, target: Node) -> float:
	var act := _active(id, target)
	if act == null:
		return 0.0
	return INF if act.is_permanent() else act.remaining


func stacks(id: StringName, target: Node) -> int:
	var act := _active(id, target)
	return act.stacks if act != null else 0


func _active(id: StringName, target: Node) -> SrvStatusHolder.Active:
	var subject := _resolve(target)
	if subject == null:
		return null
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return null
	var act: SrvStatusHolder.Active = h.effects.get(canonical(id))
	return act


# =================================================================== modifier
## Aggregate multiplier for `stat` across every active effect. `1.0` means
## "unmodified"; the value is cached and only recomputed when the entity's
## effect set changes, because the damage pipeline calls this on every hit.
func modifier(stat: String, target: Node) -> float:
	if target == null:
		return 1.0
	var h: SrvStatusHolder = _holders.get(target.get_instance_id())
	if h == null:
		return 1.0
	if h.dirty:
		h.rebuild()
	var m: float = h.mods.get(stat, 1.0)
	return m


## Same aggregation but expressed as an additive delta: `+0.25` for a 1.25x.
func bonus(stat: String, target: Node) -> float:
	return modifier(stat, target) - 1.0


# ================================================================== inspection
## HUD-facing list of the target's visible effects, worst first.
func list(target: Node, include_hidden: bool = false) -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	var subject := _resolve(target)
	if subject == null:
		return empty
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return empty
	return h.snapshot(include_hidden)


func count_on(target: Node) -> int:
	var subject := _resolve(target)
	if subject == null:
		return 0
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	return h.effects.size() if h != null else 0


## Blended sprite tint for the entity renderer (alpha 0 = leave it alone).
func tint_of(target: Node) -> Color:
	var subject := _resolve(target)
	if subject == null:
		return Color(0, 0, 0, 0)
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return Color(0, 0, 0, 0)
	if h.dirty:
		h.rebuild()
	return h.tint


## Extra light the entity emits because of its effects, in blocks.
func light_bonus(target: Node) -> float:
	var subject := _resolve(target)
	if subject == null:
		return 0.0
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return 0.0
	if h.dirty:
		h.rebuild()
	return h.light_radius


## Every live entity currently carrying `id`. Far cheaper than walking the
## `entities` group and asking each one — `survival/medical.gd` uses it to find
## who is bleeding without touching the scene tree.
func holders_with(id: StringName) -> Array[Node]:
	var out: Array[Node] = []
	var key := canonical(id)
	for tid: int in _holders:
		var h: SrvStatusHolder = _holders[tid]
		if h.alive() and h.effects.has(key):
			out.append(h.target)
	return out


func any_debuff(target: Node) -> bool:
	var subject := _resolve(target)
	if subject == null:
		return false
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return false
	for k: StringName in h.effects:
		if not (h.effects[k] as SrvStatusHolder.Active).def.beneficial:
			return true
	return false


# ================================================================== clearing
func clear(target: Node) -> void:
	var subject := _resolve(target)
	if subject == null:
		return
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return
	for id: StringName in h.effects.keys():
		_finish(h, id, "cleared")
	_holders.erase(subject.get_instance_id())


## Strip every non-beneficial effect. Returns how many went.
func clear_debuffs(target: Node) -> int:
	var subject := _resolve(target)
	if subject == null:
		return 0
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return 0
	var n := 0
	for id: StringName in h.effects.keys():
		var act: SrvStatusHolder.Active = h.effects.get(id)
		if act != null and not act.def.beneficial:
			_finish(h, id, "cured")
			n += 1
	return n


## Clear everything treatable by a medicine `keyword` (`bandage`, `antidote`,
## `antirad`, `cure`, `warmth`, `cooling`). Returns how many were cleared.
func cure(target: Node, keyword: StringName) -> int:
	var subject := _resolve(target)
	if subject == null:
		return 0
	var h: SrvStatusHolder = _holders.get(subject.get_instance_id())
	if h == null:
		return 0
	var n := 0
	for id: StringName in h.effects.keys():
		var act: SrvStatusHolder.Active = h.effects.get(id)
		if act != null and act.def.is_cured_by(keyword):
			_finish(h, id, "cured")
			n += 1
	return n


# =============================================================== perspective
## Raise the plane lock. Every caller must pair this with [method pop_flip_lock].
func push_flip_lock() -> void:
	if _flip_locks == 0:
		_flips_were_enabled = View.flips_enabled
	_flip_locks += 1
	View.flips_enabled = false


func pop_flip_lock() -> void:
	_flip_locks = maxi(0, _flip_locks - 1)
	if _flip_locks == 0:
		View.flips_enabled = _flips_were_enabled


func flip_locks() -> int:
	return _flip_locks


## True while the player is pinned to their plane by any source.
func is_plane_locked() -> bool:
	return _flip_locks > 0


## Recompute how far `phase_sight` currently reaches and publish it. Renderers
## read `View.get_meta(&"phase_sight", 0)`; gameplay reads the methods below.
func refresh_phase_sight() -> void:
	var n := 0
	if Game.player != null:
		var act := _active(&"phase_sight", Game.player)
		if act != null:
			n = act.stacks
	phase_sight_layers = n
	View.set_meta(&"phase_sight", n)


## Extra depth layers `target` may see, mine, place and interact through.
## Zero for everyone without `phase_sight`.
func interaction_layer_slack(target: Node = null) -> int:
	var subject := _resolve(target)
	if subject == null:
		return 0
	var act := _active(&"phase_sight", subject)
	return act.stacks if act != null else 0


## The widened interaction rule. Normally only the play layer is reachable;
## `phase_sight` extends that by one layer *behind* the player per stack — the
## direction that is already visible in the slab, never the invisible front.
func can_interact_with_layer(pos: Vector3i, target: Node = null) -> bool:
	if View.is_play_layer(pos):
		return true
	var slack := interaction_layer_slack(target)
	if slack <= 0:
		return false
	var off := View.layer_offset(pos)
	return off > 0 and off <= slack


## Layer bounds for a `CbtDamage` packet built by a phase-sighted attacker:
## `{"layer_rule": LAYER_RANGE, "layer_min": 0, "layer_max": slack}`.
func interaction_layer_range(target: Node = null) -> Vector2i:
	return Vector2i(0, interaction_layer_slack(target))


# ============================================================== subsystem API
## `{"weather": String, "intensity": float}` — the shape `sim/liquids` probes
## for so it can seed rain/snow accumulation on world load without waiting for
## the next `Events.weather_changed`.
func current_weather() -> Dictionary:
	if weather == null:
		return {"weather": "clear", "intensity": 0.0}
	return {"weather": String(weather.current), "intensity": weather.intensity}


## 0..1 how far the player can see through the current weather.
func visibility() -> float:
	return weather.visibility() if weather != null else 1.0


## Convenience passthroughs so callers do not have to null-check the children.
func hunger() -> float:
	return needs.hunger if needs != null else 100.0


func breath() -> float:
	return environment.breath if environment != null else 100.0


func body_temperature() -> float:
	return environment.body_temperature if environment != null else 0.0


# ===================================================================== ticking
func _physics_process(delta: float) -> void:
	if Game.paused or _holders.is_empty():
		return
	_sweep += delta
	var prune := _sweep >= 2.0
	if prune:
		_sweep = 0.0
	for tid: int in _holders.keys():
		var h: SrvStatusHolder = _holders[tid]
		if not h.alive():
			_holders.erase(tid)
			continue
		var ve := h.target as VoxelEntity
		if ve != null and ve.dead:
			_holders.erase(tid)
			continue
		_tick_holder(h, delta)
		if prune and h.is_empty():
			_holders.erase(tid)


func _tick_holder(h: SrvStatusHolder, delta: float) -> void:
	for id: StringName in h.effects.keys():
		var act: SrvStatusHolder.Active = h.effects.get(id)
		if act == null:
			continue
		var def := act.def

		if not act.is_permanent():
			act.remaining -= delta
			if act.remaining <= 0.0:
				_finish(h, id, "expired")
				continue

		if def.particle_rate > 0.0 and def.particle != &"":
			act.fx_timer += delta
			var period := 1.0 / def.particle_rate
			if act.fx_timer >= period:
				var n := mini(6, int(act.fx_timer / period))
				act.fx_timer = 0.0
				Events.spawn_particles.emit(def.particle, _pos_of(h.target), n * act.stacks)

		act.tick_timer += delta
		if act.tick_timer < def.tick_interval:
			continue
		var elapsed := act.tick_timer
		act.tick_timer = 0.0

		if def.damage_per_tick > 0.0:
			_status_damage(h.target, def.damage_per_tick * float(act.stacks),
				def.damage_element, def.id)
			# The tick may have killed the target, which clears the holder
			# out from under us via `Events.entity_died`.
			if not h.alive() or h.effects.is_empty():
				return
		if def.heal_per_tick > 0.0 and h.target.has_method(&"heal"):
			h.target.call(&"heal", def.heal_per_tick * float(act.stacks))
		if def.on_tick.is_valid():
			def.on_tick.call(h.target, act, elapsed)


## Damage-over-time delivery.
##
## Deliberately does **not** go through `combat/damage.gd`: a status tick must
## ignore i-frames (otherwise a burning player who was just hit stops burning)
## and must not be gated by the layer rule. We reproduce only the two stages
## that matter — the target's own `resist_<element>` and `damage_taken` status
## multipliers — then hand off to the entity, whose `modify_incoming_damage()`
## override still applies armour and innate resistances.
func _status_damage(target: Node, amount: float, element: String, source_id: StringName) -> void:
	if amount <= 0.0 or target == null or not is_instance_valid(target):
		return
	amount *= modifier("resist_" + element, target)
	amount *= modifier("damage_taken", target)
	if amount <= 0.0:
		return
	var ve := target as VoxelEntity
	if ve == null:
		if target.has_method(&"apply_damage"):
			target.call(&"apply_damage", amount, element, null)
		return
	if ve.dead or ve.invulnerable:
		return
	# I-frames exist to stop burst melee, not to pause a poison.
	var saved := ve.iframes
	ve.iframes = 0.0
	ve.apply_damage(amount, element, null)
	if is_instance_valid(ve) and ve.iframes <= 0.0:
		ve.iframes = saved


# ==================================================================== plumbing
func _finish(h: SrvStatusHolder, id: StringName, reason: String) -> void:
	var act: SrvStatusHolder.Active = h.effects.get(id)
	if act == null:
		return
	h.effects.erase(id)
	h.dirty = true
	var live := h.alive()
	if act.def.on_remove.is_valid():
		act.def.on_remove.call(h.target if live else null, act)
	if live:
		effect_removed.emit(h.target, id, reason)
		effects_changed.emit(h.target)
	if h.is_player:
		Events.status_removed.emit(String(id))


func _holder_for(target: Node, create: bool) -> SrvStatusHolder:
	var tid := target.get_instance_id()
	var h: SrvStatusHolder = _holders.get(tid)
	if h == null and create:
		h = SrvStatusHolder.new(target)
		_holders[tid] = h
	return h


## `null` means "the player", which is what nine callers out of ten want.
func _resolve(target: Node) -> Node:
	if target != null and is_instance_valid(target):
		return target
	return Game.player


func _pos_of(target: Node) -> Vector3:
	var n3 := target as Node3D
	if n3 == null or not is_instance_valid(n3):
		return Vector3.ZERO
	var ve := n3 as VoxelEntity
	return ve.aabb_center() if ve != null else n3.global_position


func _on_entity_died(e: Node) -> void:
	if e == null:
		return
	var tid := e.get_instance_id()
	var h: SrvStatusHolder = _holders.get(tid)
	if h == null:
		return
	for id: StringName in h.effects.keys():
		_finish(h, id, "died")
	_holders.erase(tid)


func _on_player_died(_cause: String) -> void:
	if Game.player != null:
		clear(Game.player)
	# A death must never leave the world flip-locked.
	_flip_locks = 0
	View.flips_enabled = true
	phase_sight_layers = 0
	View.set_meta(&"phase_sight", 0)


func _on_world_unloaded() -> void:
	for tid: int in _holders.keys():
		var h: SrvStatusHolder = _holders[tid]
		if not h.is_player:
			_holders.erase(tid)


# =============================================================== serialisation
func save_state() -> Dictionary:
	var player_fx: Array = []
	if Game.player != null:
		var h: SrvStatusHolder = _holders.get(Game.player.get_instance_id())
		if h != null:
			player_fx = h.save_state()
	return {
		"player": player_fx,
		"needs": needs.save_state() if needs != null else {},
		"environment": environment.save_state() if environment != null else {},
		"weather": weather.save_state() if weather != null else {},
		"farming": farming.save_state() if farming != null else {},
		"cooking": cooking.save_state() if cooking != null else {},
		"medical": medical.save_state() if medical != null else {},
	}


func load_state(d: Dictionary) -> void:
	if Game.player != null:
		clear(Game.player)
		for e in d.get("player", []):
			if not (e is Dictionary):
				continue
			var entry: Dictionary = e
			var id := StringName(entry.get("id", &""))
			if not _defs.has(id):
				continue
			apply(id, Game.player, float(entry.get("duration", -1.0)),
				int(entry.get("stacks", 1)))
			var act := _active(id, Game.player)
			if act != null and not act.is_permanent():
				act.remaining = float(entry.get("remaining", act.remaining))
	if needs != null:
		needs.load_state(d.get("needs", {}))
	if environment != null:
		environment.load_state(d.get("environment", {}))
	if weather != null:
		weather.load_state(d.get("weather", {}))
	if farming != null:
		farming.load_state(d.get("farming", {}))
	if cooking != null:
		cooking.load_state(d.get("cooking", {}))
	if medical != null:
		medical.load_state(d.get("medical", {}))
	refresh_phase_sight()
