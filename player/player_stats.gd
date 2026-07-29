## The player's vital statistics and the death / respawn cycle.
##
## Health lives on [VoxelEntity] (so combat's damage pipeline works unchanged);
## this node mirrors it onto the [signal Events.stat_changed] bus alongside the
## stats it owns outright: **energy**, **breath**, **hunger** and
## **temperature**.
##
## The survival agent drives hunger/temperature/status effects. It should set
## [member external_survival] to true and then call [method set_hunger] /
## [method set_temperature]; the simple built-in drain below exists only so the
## game is playable before that module lands.
##
## Stats broadcast on `Events.stat_changed(stat, value, maximum)` with the keys:
## `"health"`, `"energy"`, `"breath"`, `"hunger"`, `"temperature"`.
class_name PlayerStats
extends Node

const BASE_MAX_ENERGY := 100.0
const BASE_MAX_BREATH := 100.0
const BASE_MAX_HUNGER := 100.0

const ENERGY_REGEN := 19.0        ## per second, once the delay has elapsed
const ENERGY_REGEN_DELAY := 1.15  ## seconds after the last spend
const BREATH_DRAIN := 4.2         ## per second with the head underwater
const BREATH_REFILL := 34.0
const DROWN_DAMAGE := 6.0         ## per second at zero breath
const HUNGER_DRAIN := 0.13        ## per second (~13 minutes from full)
const STARVE_DAMAGE := 1.4
const HEALTH_REGEN := 0.65        ## per second while fed and out of combat
const REGEN_COMBAT_DELAY := 6.0

## The owning [PlayerActor]. Deliberately untyped: typing it would create a
## cyclic `class_name` dependency between this script and `player.gd`.
var player = null                                               # noqa: type

var max_energy := BASE_MAX_ENERGY
var max_breath := BASE_MAX_BREATH
var max_hunger := BASE_MAX_HUNGER

var energy := BASE_MAX_ENERGY
var breath := BASE_MAX_BREATH
var hunger := BASE_MAX_HUNGER
var temperature := 0.5            ## 0 = freezing, 0.5 = comfortable, 1 = burning

## Fraction of the inventory scattered on death (Starbound "survival" rules).
@export var death_drop_fraction := 0.3
@export var respawn_delay := 2.6
## Set true by the survival agent when it takes over hunger/temperature.
var external_survival := false
## Set false by the survival agent for airless planets / suit breaches.
var breathable_air := true

var respawn_point := Vector3.ZERO
var respawn_kind := "spawn"
var dying := false

var _energy_delay := 0.0
var _combat_timer := 0.0
var _last_health := -1.0
var _last_broadcast := {}


func setup(p) -> void:                                          # noqa: type
	player = p
	respawn_point = p.global_position
	Events.environment_changed.connect(_on_environment_changed)
	Events.travel_finished.connect(_on_travel_finished)
	p.damaged.connect(func(_a: float, _e: String, _s: Node) -> void: _combat_timer = REGEN_COMBAT_DELAY)
	on_bonuses_changed()
	_broadcast_all()


# ==================================================================== ticking
func tick(delta: float) -> void:
	if player == null or dying:
		return
	_energy_delay = maxf(0.0, _energy_delay - delta)
	_combat_timer = maxf(0.0, _combat_timer - delta)
	_tick_energy(delta)
	_tick_breath(delta)
	_tick_hunger(delta)
	_tick_health(delta)
	if player.health != _last_health:
		_last_health = player.health
		_emit("health", player.health, player.max_health)


func _tick_energy(delta: float) -> void:
	if energy >= max_energy or _energy_delay > 0.0:
		return
	var rate := ENERGY_REGEN * Status.modifier("energy_regen", player) * Tech.modifier("energy_regen")
	set_energy(energy + rate * delta)


func _tick_breath(delta: float) -> void:
	var head: Vector3 = player.global_position + Vector3(0.0, player.box_size.y - 0.25, 0.0)
	var drowning := Blocks.is_liquid(World.get_block(Const.floor_v(head))) or not breathable_air
	if drowning:
		var rate := BREATH_DRAIN * Status.modifier("breath_drain", player)
		set_breath(breath - rate * delta)
		if breath <= 0.0:
			player.apply_damage(DROWN_DAMAGE * delta, Const.ELEM_PHYSICAL, null)
	elif breath < max_breath:
		set_breath(breath + BREATH_REFILL * delta)


func _tick_hunger(delta: float) -> void:
	if external_survival:
		return
	if hunger > 0.0:
		var rate := HUNGER_DRAIN
		if player.is_sprinting():
			rate *= 1.7
		set_hunger(hunger - rate * delta)
	else:
		player.apply_damage(STARVE_DAMAGE * delta, Const.ELEM_PHYSICAL, null)


func _tick_health(delta: float) -> void:
	if _combat_timer > 0.0 or hunger < max_hunger * 0.3:
		return
	if player.health < player.max_health:
		player.heal(HEALTH_REGEN * Status.modifier("health_regen", player) * delta)


# ==================================================================== setters
func set_energy(v: float) -> void:
	var nv := clampf(v, 0.0, max_energy)
	if is_equal_approx(nv, energy):
		return
	energy = nv
	_emit("energy", energy, max_energy)


## Returns false (and spends nothing) when there is not enough energy.
func spend_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true
	var cost := amount * Tech.modifier("energy_cost") * Status.modifier("energy_cost", player)
	if energy < cost:
		Events.play_sound.emit(&"denied", player.global_position)
		return false
	_energy_delay = ENERGY_REGEN_DELAY
	set_energy(energy - cost)
	return true


func add_energy(amount: float) -> void:
	set_energy(energy + amount)


func set_breath(v: float) -> void:
	var nv := clampf(v, 0.0, max_breath)
	if is_equal_approx(nv, breath):
		return
	breath = nv
	_emit("breath", breath, max_breath)


func set_hunger(v: float) -> void:
	var nv := clampf(v, 0.0, max_hunger)
	if is_equal_approx(nv, hunger):
		return
	hunger = nv
	_emit("hunger", hunger, max_hunger)


func feed(amount: float) -> void:
	set_hunger(hunger + amount)


func set_temperature(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if is_equal_approx(nv, temperature):
		return
	temperature = nv
	_emit("temperature", temperature, 1.0)


## Recompute the maxima from equipped gear bonuses. Called by [PlayerActor].
func on_bonuses_changed() -> void:
	if player == null:
		return
	var hp_max: float = 100.0 + float(player.stat_bonus("max_health"))
	if not is_equal_approx(hp_max, player.max_health):
		var ratio: float = float(player.health) / maxf(1.0, float(player.max_health))
		player.max_health = maxf(10.0, hp_max)
		player.health = minf(player.max_health, player.max_health * ratio)
		_emit("health", player.health, player.max_health)
	max_energy = maxf(10.0, BASE_MAX_ENERGY + player.stat_bonus("max_energy"))
	max_breath = maxf(10.0, BASE_MAX_BREATH + player.stat_bonus("max_breath"))
	set_energy(energy)
	set_breath(breath)


func _on_environment_changed(_temperature: float, _radiation: float, breathable: bool) -> void:
	breathable_air = breathable


func _on_travel_finished(_planet_id: String) -> void:
	if player != null:
		respawn_point = player.global_position
		respawn_kind = "landing"


# ================================================================ death cycle
## Where the player wakes up: a bed, a teleporter beacon or the ship.
func set_respawn_point(pos: Vector3, kind: String = "bed") -> void:
	respawn_point = pos
	respawn_kind = kind
	Events.toast("Respawn point set (%s)" % kind, "info")


## Entry point from [method PlayerActor.on_death]. Never frees the player.
func begin_death(source: Node) -> void:
	if dying:
		return
	dying = true
	var cause := "unknown"
	if source is VoxelEntity:
		cause = String((source as VoxelEntity).faction)
	elif source != null:
		cause = String(source.name)
	Game.bump_stat("deaths")
	Events.player_died.emit(cause)
	Events.screen_shake.emit(1.6, 0.6)
	Events.play_sound.emit(&"player_die", player.global_position)
	Events.spawn_particles.emit(&"death_burst", player.aabb_center(), 26)
	player.visual.play_death()
	_scatter_inventory()
	_respawn_after(respawn_delay)


func _respawn_after(delay: float) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	if is_instance_valid(player):
		respawn()


## Put the player back on their feet at the last bed / teleporter / ship.
func respawn() -> void:
	dying = false
	player.dead = false
	player.health = player.max_health
	player.velocity = Vector3.ZERO
	player.iframes = 2.0
	player.hitstun = 0.0
	energy = max_energy
	breath = max_breath
	if not external_survival:
		hunger = maxf(hunger, max_hunger * 0.5)
	player.teleport(respawn_point)
	View.set_layer(floori(View.depth_of(player.global_position)))
	player.visual.play_respawn()
	player.input.flush()
	_broadcast_all()
	Events.player_respawned.emit()
	Events.toast("You wake up at your %s." % respawn_kind, "info")


## Drop [member death_drop_fraction] of the pack where the player fell.
func _scatter_inventory() -> void:
	if death_drop_fraction <= 0.0 or Game.difficulty <= 0:
		return
	var inv = player.inventory                                  # noqa: type
	var at: Vector3 = player.aabb_center()
	if inv != null and inv.has_method(&"drop_on_death"):
		inv.call(&"drop_on_death", death_drop_fraction, at)
		Events.inventory_changed.emit()
		return
	if inv != null and inv.has_method(&"all_stacks") and inv.has_method(&"remove_stack"):
		var stacks: Array = inv.call(&"all_stacks")
		for s: Variant in stacks:
			var st := s as ItemStack
			if st == null or st.is_empty():
				continue
			var n := int(ceilf(float(st.count) * death_drop_fraction))
			if n <= 0:
				continue
			inv.call(&"remove_stack", st.id, n)
			Game.spawn_item_drop(at, st.id, n, st.data)
		Events.inventory_changed.emit()
		return
	# Fallback bag (no inventory module yet).
	var bag: Dictionary = player._fallback_bag
	for id: StringName in bag.keys():
		var n := int(ceilf(float(bag[id]) * death_drop_fraction))
		if n <= 0:
			continue
		bag[id] = maxi(0, int(bag[id]) - n)
		if bag[id] == 0:
			bag.erase(id)
		Game.spawn_item_drop(at, id, n)


# ================================================================= broadcast
func _emit(key: String, value: float, maximum: float) -> void:
	var prev: float = _last_broadcast.get(key, NAN)
	if not is_nan(prev) and is_equal_approx(prev, value):
		return
	_last_broadcast[key] = value
	Events.stat_changed.emit(key, value, maximum)


func _broadcast_all() -> void:
	_last_broadcast.clear()
	_emit("health", player.health, player.max_health)
	_emit("energy", energy, max_energy)
	_emit("breath", breath, max_breath)
	_emit("hunger", hunger, max_hunger)
	_emit("temperature", temperature, 1.0)


func save_state() -> Dictionary:
	return {
		"energy": energy, "breath": breath, "hunger": hunger,
		"temperature": temperature,
		"respawn": [respawn_point.x, respawn_point.y, respawn_point.z],
		"respawn_kind": respawn_kind,
	}


func load_state(d: Dictionary) -> void:
	energy = float(d.get("energy", max_energy))
	breath = float(d.get("breath", max_breath))
	hunger = float(d.get("hunger", max_hunger))
	temperature = float(d.get("temperature", 0.5))
	var r: Array = d.get("respawn", [0, 0, 0])
	respawn_point = Vector3(r[0], r[1], r[2])
	respawn_kind = String(d.get("respawn_kind", "spawn"))
	dying = false
	_broadcast_all()
