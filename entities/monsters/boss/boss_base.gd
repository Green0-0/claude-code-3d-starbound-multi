## Shared boss machinery: multi-phase health gates, telegraphed attacks with a
## readable wind-up, arena awareness, and a broadcast health bar.
##
## A boss is a `MobBase` with a scripted attack loop layered on top of the normal
## brain: the tree still handles chasing and facing, but `_choose_action` decides
## when to interrupt it with a set-piece.
class_name MobBoss
extends MobBase

signal phase_changed(phase: int)

## `[{"at": 0.7, "name": "Second Wind"}]` — `at` is the health fraction the
## phase begins at, listed highest first.
var phases: Array[Dictionary] = []
var phase := 0
var boss_name := "Boss"

var arena_centre := Vector3.ZERO
var arena_radius := 26.0
var arena_layer := 0

var _telegraph_id: StringName = &""
var _telegraph_left := 0.0
var _telegraph_total := 0.0
var _telegraph_meta: Dictionary = {}
var _action_cd := 2.0
var _intro := 2.2
var _bar_timer := 0.0


func _ready() -> void:
	super._ready()
	add_to_group(&"boss")
	add_to_group(&"persistent")
	arena_centre = global_position
	arena_layer = depth_layer()
	invulnerable = true
	boss_name = species.display_name if species != null else boss_name
	Events.toast("%s awakens." % boss_name, "danger")
	Events.screen_shake.emit(3.0, 0.8)
	Events.play_sound.emit(&"boss_spawn", global_position)


func _physics_process(delta: float) -> void:
	if _dying or Game.paused or not World.ready_flag:
		return
	if _intro > 0.0:
		_intro -= delta
		telegraph(clampf(_intro / 2.2, 0.0, 1.0))
		if _intro <= 0.0:
			invulnerable = false
			telegraph(0.0)
	_boss_tick(delta)
	super._physics_process(delta)
	_broadcast_bar(delta)


func _boss_tick(delta: float) -> void:
	_action_cd = maxf(0.0, _action_cd - delta)
	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		telegraph(1.0 - clampf(_telegraph_left / maxf(0.01, _telegraph_total), 0.0, 1.0))
		suspend_brain(0.1)
		motor_stop()
		if _telegraph_left <= 0.0:
			telegraph(0.0)
			var id := _telegraph_id
			_telegraph_id = &""
			_fire_attack(id, _telegraph_meta)
			_action_cd = maxf(_action_cd, 0.8)
		return
	if _intro > 0.0:
		return
	_check_phase()
	_keep_in_arena()
	if _action_cd <= 0.0:
		_choose_action(delta)


func _broadcast_bar(delta: float) -> void:
	_bar_timer -= delta
	if _bar_timer > 0.0:
		return
	_bar_timer = 0.2
	Events.stat_changed.emit("boss_health", health, max_health)


# ================================================================== phases
func _check_phase() -> void:
	var frac := health_fraction()
	var want := 0
	for i in phases.size():
		if frac <= float(phases[i].get("at", 0.0)):
			want = i + 1
	if want == phase:
		return
	phase = want
	var label: String = "Phase %d" % (phase + 1)
	if phase - 1 >= 0 and phase - 1 < phases.size():
		label = String(phases[phase - 1].get("name", label))
	Events.toast("%s — %s" % [boss_name, label], "danger")
	Events.screen_shake.emit(4.0, 0.6)
	Events.spawn_particles.emit(&"boss_phase", aabb_center(), 40)
	Events.play_sound.emit(&"boss_phase", global_position)
	phase_changed.emit(phase)
	_on_phase_changed(phase)


## Override: react to entering a new phase.
func _on_phase_changed(_p: int) -> void:
	pass


# ================================================================== attacks
## Begin a wind-up the player can read. `_fire_attack` runs when it completes.
func begin_telegraph(id: StringName, duration: float, meta: Dictionary = {}) -> void:
	_telegraph_id = id
	_telegraph_left = duration
	_telegraph_total = duration
	_telegraph_meta = meta
	set_anim(MobVisual.ST_WINDUP)
	Events.play_sound.emit(&"boss_windup", global_position)
	if bool(meta.get("shout", false)):
		Events.toast(String(meta.get("shout_text", "!")), "danger")


## Override: perform the attack whose telegraph just finished.
func _fire_attack(_id: StringName, _meta: Dictionary) -> void:
	pass


## Override: pick the next set-piece. Set `_action_cd` before returning.
func _choose_action(_delta: float) -> void:
	pass


func player_target() -> Node3D:
	var t := target()
	if t == null:
		t = Game.player
		if t != null:
			set_target(t)
	return t


# ================================================================== arena
## Bosses do not chase you across the planet: they own a space and defend it.
func _keep_in_arena() -> void:
	var d := plane_distance_to(arena_centre)
	if d <= arena_radius:
		return
	suspend_brain(0.2)
	navigate_to(world_at_layer(arena_centre, depth_layer()), true)
	if d > arena_radius * 2.2:
		snap_to_layer(arena_layer)
		teleport(arena_centre + Vector3(0, 1.0, 0))
		heal(max_health * 0.12)
		Events.toast("%s recovers." % boss_name, "warning")


## A ring of damage in the play plane. The bread-and-butter boss attack.
func shockwave(radius: float, damage: float, element: String = Const.ELEM_PHYSICAL) -> void:
	area_damage(global_position, radius, damage, element)
	Events.spawn_particles.emit(&"shockwave", global_position, 30)
	Events.screen_shake.emit(radius * 0.35, 0.35)
	Events.play_sound.emit(&"boss_slam", global_position)


## Summon adds around the arena, on the player's layer so they matter.
func summon(species_id: StringName, count: int, spread: float = 6.0) -> Array:
	var out: Array = []
	var em: Node3D = Game.entities_root
	if em == null or not em.has_method(&"spawn_species"):
		return out
	for i in count:
		var lat: float = randf_range(-spread, spread)
		var pos := plane_offset(world_at_layer(global_position, View.layer), lat)
		pos.y += 1.0
		var m = em.call(&"spawn_species", species_id, pos, {"threat": planet_threat, "no_loot": true})
		if m != null:
			out.append(m)
	Events.spawn_particles.emit(&"summon", global_position, 24)
	return out


func on_death(source: Node) -> void:
	Events.toast("%s falls." % boss_name, "success")
	Events.screen_shake.emit(6.0, 1.2)
	Events.stat_changed.emit("boss_health", 0.0, max_health)
	super.on_death(source)


# ============================================================== construction
const BOSS_SCRIPTS := {
	&"boss_stone_titan": "res://entities/monsters/boss/stone_titan.gd",
	&"boss_hive_queen": "res://entities/monsters/boss/hive_queen.gd",
	&"boss_fourfold": "res://entities/monsters/boss/fourfold.gd",
	&"boss_magma_heart": "res://entities/monsters/boss/magma_heart.gd",
}


static func is_boss(species_id: StringName) -> bool:
	return BOSS_SCRIPTS.has(species_id)


static func boss_ids() -> Array:
	return BOSS_SCRIPTS.keys()


## Instantiate the right subclass for a boss species. The caller adds it to the
## tree and positions it.
static func make(species_id: StringName) -> MobBoss:
	var path: String = BOSS_SCRIPTS.get(species_id, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[Mobs] unknown boss '%s'" % species_id)
		return null
	var scr: Script = load(path)
	var b: MobBoss = scr.new()
	b.species_id = species_id
	return b
