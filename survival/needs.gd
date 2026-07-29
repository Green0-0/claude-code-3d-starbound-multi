## The survival loop: hunger, thirst and fatigue, their drain rates, and what
## happens when a meter bottoms out.
##
## ## Difficulty
##
## `Game.difficulty` reshapes the whole system rather than just scaling a
## number:
##
## | | casual (0) | survival (1) | hardcore (2) |
## |---|---|---|---|
## | drain | 0.35x | 1.0x | 1.55x |
## | empty hunger | no penalty | `starving` | `starving`, faster |
## | thirst | off | on | on |
## | fatigue | cosmetic | `drowsy` / `exhausted` | plus health decay |
## | death | respawn | respawn | **permadeath** |
##
## Casual still *shows* the bars and still grants `well_fed`, so food is a
## reward rather than a chore.
##
## ## Talking to the HUD
##
## Everything is published through `Events.stat_changed(stat, value, maximum)`
## with the stat keys `hunger`, `thirst` and `fatigue` (plus `breath`,
## `temperature` and `radiation` from `survival/environment.gd`). No HUD
## reference is ever held.
class_name SrvNeeds
extends Node

const MAX_VALUE := 100.0

## Seconds of *idle* play to empty a full bar at survival difficulty.
const HUNGER_SECONDS := 780.0
const THIRST_SECONDS := 560.0
const FATIGUE_SECONDS := 900.0

## Below this you are `peckish`; at zero you are `starving`.
const PECKISH_AT := 28.0
## Eating above this grants `well_fed`.
const WELL_FED_AT := 82.0
const DROWSY_AT := 72.0
const EXHAUSTED_AT := 93.0

## 0 casual, 1 survival, 2 hardcore.
const DRAIN_BY_DIFFICULTY := [0.35, 1.0, 1.55]

var hunger := MAX_VALUE
var thirst := MAX_VALUE
## Rises with time awake; 100 means you are about to fall over.
var fatigue := 0.0

var thirst_enabled := true
var enabled := true

## Multiplier derived from what the player is doing right now, 1.0 = standing.
var activity := 1.0

var _emit_timer := 0.0
var _last_mined := 0.0
var _mining_heat := 0.0
var _asleep := false
var _sleep_rate := 0.0
var _permadeath_done := false


func _ready() -> void:
	process_priority = -8
	Events.player_spawned.connect(_on_player_spawned)
	Events.player_died.connect(_on_player_died)
	Events.player_respawned.connect(_on_player_respawned)
	Events.world_ready.connect(_on_world_ready)


func _on_player_spawned(_p: Node) -> void:
	_publish(true)


func _on_world_ready(_planet: String) -> void:
	thirst_enabled = Game.difficulty >= 1 or bool(World.planet.get("arid", false))
	_publish(true)


# ==================================================================== ticking
func _physics_process(delta: float) -> void:
	if not enabled or Game.paused or Game.player == null or not World.ready_flag:
		return
	var player := Game.player
	if player.dead:
		return
	var scaled := delta * Game.time_scale
	_update_activity(player, delta)

	if _asleep:
		_tick_sleep(scaled)
	else:
		_drain(player, scaled)

	_apply_consequences(player, scaled)

	_emit_timer += delta
	if _emit_timer >= 0.25:
		_emit_timer = 0.0
		_publish(false)


func _difficulty_scale() -> float:
	return DRAIN_BY_DIFFICULTY[clampi(Game.difficulty, 0, DRAIN_BY_DIFFICULTY.size() - 1)]


## Activity is read from the entity's own physics state, so it works identically
## in all four view planes (plane velocity, never `.x`).
func _update_activity(player: VoxelEntity, delta: float) -> void:
	var lateral := absf(player.plane_velocity())
	var speed_frac := clampf(lateral / maxf(0.5, player.move_speed), 0.0, 1.6)
	var a := 1.0 + speed_frac * 0.75
	if not player.on_floor:
		a += 0.14
	if player.submersion > 0.3:
		a += 0.35

	# Mining is the other big calorie sink; derive it from the global counter so
	# no coupling to the tool agent is needed.
	var mined := float(Game.stats.get("blocks_mined", 0))
	if mined > _last_mined:
		_mining_heat = minf(2.5, _mining_heat + (mined - _last_mined) * 0.25)
	_last_mined = mined
	_mining_heat = maxf(0.0, _mining_heat - delta * 0.8)
	a += _mining_heat * 0.3

	activity = a


func _drain(player: VoxelEntity, scaled: float) -> void:
	var scale := _difficulty_scale()
	var hunger_rate := (MAX_VALUE / HUNGER_SECONDS) * scale * activity \
		* Status.modifier("hunger_rate", player)
	hunger = maxf(0.0, hunger - hunger_rate * scaled)

	if thirst_enabled:
		var thirst_rate := (MAX_VALUE / THIRST_SECONDS) * scale * activity \
			* Status.modifier("thirst_rate", player)
		thirst = maxf(0.0, thirst - thirst_rate * scaled)

	var fatigue_rate := (MAX_VALUE / FATIGUE_SECONDS) * scale \
		* Status.modifier("fatigue_rate", player)
	fatigue = minf(MAX_VALUE, fatigue + fatigue_rate * scaled)


func _tick_sleep(scaled: float) -> void:
	fatigue = maxf(0.0, fatigue - _sleep_rate * scaled)
	# Sleeping still costs calories, just slowly.
	hunger = maxf(0.0, hunger - (MAX_VALUE / HUNGER_SECONDS) * 0.35 * scaled)
	if fatigue <= 0.0:
		wake(true)


# =============================================================== consequences
func _apply_consequences(player: VoxelEntity, scaled: float) -> void:
	var casual := Game.difficulty <= 0

	# --- hunger
	if hunger <= 0.0 and not casual:
		if not Status.has(&"starving", player):
			Status.apply(&"starving", player, SrvStatusEffect.PERMANENT)
			Events.toast("You are starving.", "danger")
		Status.remove(&"peckish", player)
	elif hunger < PECKISH_AT:
		Status.remove(&"starving", player)
		if not casual and not Status.has(&"peckish", player):
			Status.apply(&"peckish", player, SrvStatusEffect.PERMANENT)
	else:
		Status.remove(&"starving", player)
		Status.remove(&"peckish", player)

	# --- thirst
	if thirst_enabled and thirst <= 0.0 and not casual:
		if not Status.has(&"dehydrated", player):
			Status.apply(&"dehydrated", player, SrvStatusEffect.PERMANENT)
			Events.toast("You are dangerously dehydrated.", "danger")
	elif Status.has(&"dehydrated", player):
		Status.remove(&"dehydrated", player)

	# --- fatigue
	if casual:
		return
	if fatigue >= EXHAUSTED_AT:
		if not Status.has(&"exhausted", player):
			Status.apply(&"exhausted", player, SrvStatusEffect.PERMANENT)
			Events.toast("You are exhausted. Find a bed.", "warn")
		Status.remove(&"drowsy", player)
		if Game.difficulty >= 2:
			# Hardcore: staying awake grinds you down.
			player.health = maxf(1.0, player.health - 0.6 * scaled)
	elif fatigue >= DROWSY_AT:
		Status.remove(&"exhausted", player)
		if not Status.has(&"drowsy", player):
			Status.apply(&"drowsy", player, SrvStatusEffect.PERMANENT)
	else:
		Status.remove(&"drowsy", player)
		Status.remove(&"exhausted", player)


# ==================================================================== eating
## Restore hunger. Returns the amount actually consumed (0 when already full,
## which is how `cooking.gd` refuses to waste a meal).
func feed(amount: float, allow_overeat: bool = false) -> float:
	if amount <= 0.0:
		return 0.0
	if hunger >= MAX_VALUE - 0.01 and not allow_overeat:
		return 0.0
	var before := hunger
	hunger = minf(MAX_VALUE, hunger + amount)
	_publish(true)
	return hunger - before


func drink(amount: float) -> float:
	if not thirst_enabled:
		# Drinks still count as a little food when thirst is switched off.
		return feed(amount * 0.3)
	var before := thirst
	thirst = minf(MAX_VALUE, thirst + amount)
	_publish(true)
	return thirst - before


## True when a meal should also grant `well_fed`.
func is_well_fed() -> bool:
	return hunger >= WELL_FED_AT


func hunger_fraction() -> float:
	return hunger / MAX_VALUE


func thirst_fraction() -> float:
	return thirst / MAX_VALUE


func fatigue_fraction() -> float:
	return fatigue / MAX_VALUE


# ==================================================================== sleeping
## Climb into a bed. `rate` is fatigue points shed per second; the objects agent
## passes a higher number for better beds.
func sleep(rate: float = 14.0) -> bool:
	if _asleep or Game.player == null or Game.player.dead:
		return false
	if Game.is_night() == false and Game.difficulty >= 2:
		Events.toast("You can only sleep at night out here.", "warn")
		return false
	_asleep = true
	_sleep_rate = maxf(1.0, rate)
	Game.time_scale = maxf(Game.time_scale, 12.0)
	Events.toast("Sleeping...", "info")
	return true


func is_asleep() -> bool:
	return _asleep


## Leave the bed. `completed` is true when fatigue actually reached zero, which
## is what earns the `rested` buff.
func wake(completed: bool) -> void:
	if not _asleep:
		return
	_asleep = false
	Game.time_scale = 1.0
	if completed and Game.player != null:
		Status.apply(&"rested", Game.player)
		Game.player.heal(Game.player.max_health * 0.25)
		Events.toast("You wake up rested.", "good")
	_publish(true)


## Reduce fatigue without a full sleep (a campfire nap, a stimulant).
func restore_energy(amount: float) -> void:
	fatigue = maxf(0.0, fatigue - amount)
	_publish(true)


# =============================================================== permadeath
func _on_player_died(cause: String) -> void:
	if _asleep:
		wake(false)
	if Game.difficulty < 2 or _permadeath_done:
		return
	_permadeath_done = true
	Events.toast("Hardcore run over — %s. This save is gone." % cause, "danger")
	Game.set_meta(&"permadeath", true)
	if SaveManager != null and SaveManager.has_method(&"delete_save"):
		SaveManager.call(&"delete_save", 0)


func _on_player_respawned() -> void:
	hunger = maxf(hunger, 45.0)
	thirst = maxf(thirst, 45.0)
	fatigue = minf(fatigue, 55.0)
	_publish(true)


# ================================================================= publishing
func _publish(force: bool) -> void:
	if not force and Game.player == null:
		return
	Events.stat_changed.emit("hunger", hunger, MAX_VALUE)
	if thirst_enabled:
		Events.stat_changed.emit("thirst", thirst, MAX_VALUE)
	Events.stat_changed.emit("fatigue", fatigue, MAX_VALUE)


func save_state() -> Dictionary:
	return {
		"hunger": hunger, "thirst": thirst, "fatigue": fatigue,
		"thirst_enabled": thirst_enabled, "enabled": enabled,
	}


func load_state(d: Dictionary) -> void:
	hunger = clampf(float(d.get("hunger", MAX_VALUE)), 0.0, MAX_VALUE)
	thirst = clampf(float(d.get("thirst", MAX_VALUE)), 0.0, MAX_VALUE)
	fatigue = clampf(float(d.get("fatigue", 0.0)), 0.0, MAX_VALUE)
	thirst_enabled = bool(d.get("thirst_enabled", thirst_enabled))
	enabled = bool(d.get("enabled", true))
	_asleep = false
	_publish(true)
