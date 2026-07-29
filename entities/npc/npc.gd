## Every friendly humanoid in the game: villagers, merchants, guards, quest
## givers and crew.
##
## An NPC is a [VoxelEntity] with three layers bolted on:
##
## [b]A day[/b] — [member schedule] maps [member Game.day_fraction] onto an
## activity (sleep / work / wander / socialise / idle) and each activity picks a
## destination: bed, workplace, a wander point near home, the village green.
##
## [b]A brain[/b] — plane-space walking. All steering is expressed as a lateral
## delta in the *current* viewing plane, so an NPC pacing left-to-right keeps
## pacing left-to-right after the player flips, exactly like the player does. If
## the monster agent has shipped `entities/monsters/pathing.gd` we defer to it;
## otherwise a competent little walker handles steps, gaps and jumps.
##
## [b]A memory[/b] — [NpcReputation] holds how this specific person feels about
## you, which gates dialogue branches, shop prices, hiring and quests.
class_name NpcBase
extends VoxelEntity

## Where the monster agent's shared pathing lives, if it exists.
const PATHING_SCRIPT := "res://entities/monsters/pathing.gd"

## Player distance at which a greeting bubble may fire.
const GREET_RANGE := 7.0
## Player distance at which `interact` is accepted.
const TALK_RANGE := 2.8
## Distance at which a hostile counts as danger.
const DANGER_RANGE := 13.0
const GREET_COOLDOWN := 24.0

# --- identity ----------------------------------------------------------------
@export var npc_id: StringName = &""
@export var display_name: String = "Villager"
@export var race: StringName = &"human"
@export var role_id: StringName = &"villager"
@export var village_id: StringName = &""
@export var visual_seed: int = 0
## Overrides the role's default tree when non-empty.
@export var dialogue_tree: String = ""
@export var crew_skill: StringName = &"engineer"

# --- places ------------------------------------------------------------------
## The position this NPC belongs to and, for guards, defends.
@export var home_position := Vector3.INF
@export var work_position := Vector3.INF
@export var bed_position := Vector3.INF
@export var social_position := Vector3.INF
@export var wander_radius := 9.0
@export var defend_radius := 18.0

# --- behaviour flags ---------------------------------------------------------
@export var flees := true
@export var can_offer_quests := true
@export var quest_bias: StringName = &""
## Melee damage per swing; 0 means this NPC cannot fight back.
@export var melee_damage := 0.0
@export var melee_reach := 1.9
@export var swing_cooldown := 0.85

# --- shop --------------------------------------------------------------------
var shop_kinds: Array[int] = []
var shop_size: int = 8
var shop_tier_bonus: int = 0

# --- runtime -----------------------------------------------------------------
var role: NpcRole = null
var visual: NpcVisual = null
var activity: StringName = &"idle"
var is_crew := false
var threat_target: VoxelEntity = null
var attack_cooldown := 0.0
var portrait_color := Color(0.72, 0.78, 0.9)
## Set while the player is mid-conversation with this NPC.
var in_conversation := false

var schedule: Array[Dictionary] = []

var _target := Vector3.INF
var _think_t := 0.0
var _danger_t := 0.0
var _greet_t := 0.0
var _stuck_t := 0.0
var _last_lateral := 0.0
var _wander_pause := 0.0
var _stock: Array[Dictionary] = []
var _stock_day := -999
var _pending_quest := ""
var _rng := RandomNumberGenerator.new()

## Waypoints from the monster agent's A*, when that module is present.
var _path: Array[Vector3] = []
var _path_i := 0
var _repath_t := 0.0
var _path_goal := Vector3.INF

## `MobPath` (entities/monsters/pathing.gd), or null when that agent's module is
## absent — in which case the built-in walker below takes over.
static var _pathing: Object = null
static var _pathing_probed := false


# =========================================================================
#  Construction
# =========================================================================
func _ready() -> void:
	super._ready()
	faction = &"friendly"
	add_to_group(&"npc")
	add_to_group(&"interactable")
	if npc_id == &"":
		npc_id = StringName("npc_%d" % get_instance_id())
	if visual_seed == 0:
		visual_seed = int(hash(npc_id))
	_rng.seed = visual_seed
	apply_role(role_id)
	_build_visual()
	if home_position == Vector3.INF:
		home_position = global_position
	if village_id != &"":
		NpcReputation.register_member(npc_id, village_id)
	_greet_t = _rng.randf_range(0.0, 6.0)
	_pick_destination()


## Applies (or re-applies) a role: stats, schedule, shop, dialogue.
func apply_role(new_role: StringName) -> void:
	role_id = NpcRoles.canonical(new_role)
	role = NpcRoles.get_role(role_id)
	role.configure(self)
	max_health = max_health * role.toughness()
	health = max_health
	build_schedule()
	if role.defends():
		flees = false


## Copies the role's routine and jitters it a little so a village of five guards
## does not move as one organism.
func build_schedule() -> void:
	schedule.clear()
	var jitter := _rng.randf_range(-0.03, 0.03)
	for entry: Dictionary in role.schedule():
		schedule.append({
			"from": fposmod(float(entry["from"]) + jitter, 1.0),
			"to": fposmod(float(entry["to"]) + jitter, 1.0),
			"activity": StringName(entry["activity"]),
		})
	# Guards split into two watches so somebody is always awake.
	if role_id == &"guard" and (visual_seed & 1) == 1:
		for e: Dictionary in schedule:
			e["from"] = fposmod(float(e["from"]) + 0.5, 1.0)
			e["to"] = fposmod(float(e["to"]) + 0.5, 1.0)


func _build_visual() -> void:
	if visual != null and is_instance_valid(visual):
		visual.queue_free()
	visual = NpcVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.setup(race, role_id, visual_seed)
	box_size = Vector3(0.62, visual.height, 0.62)
	portrait_color = visual.portrait_color()


## Bulk setup, called by [method Game.spawn_entity] and the spawner. Tolerant of
## missing keys — everything has a sensible default.
func configure(d: Dictionary) -> void:
	if d.has("npc_id"):
		npc_id = StringName(d["npc_id"])
	if d.has("name"):
		display_name = String(d["name"])
	if d.has("race"):
		race = StringName(d["race"])
	if d.has("role"):
		role_id = StringName(d["role"])
	if d.has("village"):
		village_id = StringName(d["village"])
	if d.has("seed"):
		visual_seed = int(d["seed"])
	if d.has("tree"):
		dialogue_tree = String(d["tree"])
	if d.has("skill"):
		crew_skill = StringName(d["skill"])
	if d.has("home"):
		home_position = _to_vec(d["home"], global_position)
	if d.has("work"):
		work_position = _to_vec(d["work"], Vector3.INF)
	if d.has("bed"):
		bed_position = _to_vec(d["bed"], Vector3.INF)
	if d.has("social"):
		social_position = _to_vec(d["social"], Vector3.INF)
	if d.has("wander_radius"):
		wander_radius = float(d["wander_radius"])
	if is_inside_tree():
		_rng.seed = visual_seed
		apply_role(role_id)
		_build_visual()
		if village_id != &"":
			NpcReputation.register_member(npc_id, village_id)


static func _to_vec(v: Variant, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector3i:
		return Vector3(v)
	if v is Array and (v as Array).size() >= 3:
		var a := v as Array
		return Vector3(a[0], a[1], a[2])
	return fallback


# =========================================================================
#  Simulation
# =========================================================================
func _physics_process(delta: float) -> void:
	if dead:
		return
	if is_shifting():
		integrate(delta)
		return
	if Game.paused:
		return

	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	_danger_t -= delta
	if _danger_t <= 0.0:
		_danger_t = 0.35
		_scan_for_danger()

	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = _rng.randf_range(0.5, 0.9)
		_update_activity()
		_pick_destination()

	if role != null:
		role.tick(self, delta)

	if in_conversation:
		_stand_and_face(Game.player, delta)
	elif threat_target != null and is_instance_valid(threat_target) and not threat_target.dead:
		_combat_step(delta)
	elif is_crew:
		_follow_step(delta)
	else:
		_routine_step(delta)

	integrate(delta)
	_update_visual()


func _process(delta: float) -> void:
	if dead:
		return
	_greet_t -= delta
	_maybe_greet()
	_check_interact_input()


func _update_visual() -> void:
	if visual == null:
		return
	visual.set_motion(absf(plane_velocity()), on_floor)
	visual.set_facing(facing)
	visual.set_activity(&"talk" if in_conversation else activity)


# ------------------------------------------------------------------ schedule
func _update_activity() -> void:
	if is_crew:
		activity = &"follow"
		return
	if threat_target != null:
		activity = &"fight"
		return
	var now := Game.day_fraction
	for e: Dictionary in schedule:
		if _window_contains(float(e["from"]), float(e["to"]), now):
			activity = StringName(e["activity"])
			return
	activity = NpcRole.ACT_IDLE


static func _window_contains(from: float, to: float, now: float) -> bool:
	if from <= to:
		return now >= from and now < to
	return now >= from or now < to     # window wraps past midnight


func _pick_destination() -> void:
	if is_crew or in_conversation:
		return
	match activity:
		NpcRole.ACT_SLEEP:
			_target = bed_position if bed_position != Vector3.INF else home_position
		NpcRole.ACT_WORK:
			_target = work_position if work_position != Vector3.INF else home_position
		NpcRole.ACT_SOCIALISE:
			_target = social_position if social_position != Vector3.INF else _near_home(3.0)
		NpcRole.ACT_WANDER:
			if _wander_pause <= 0.0 or _target == Vector3.INF:
				_target = _near_home(wander_radius)
				_wander_pause = _rng.randf_range(2.5, 7.0)
		_:
			_target = home_position


## A random point in plane space around home, snapped down onto the ground.
func _near_home(radius: float) -> Vector3:
	var base := home_position if home_position != Vector3.INF else global_position
	var lateral := _rng.randf_range(-radius, radius)
	var p: Vector3 = base + View.plane_dir_to_world(Vector2(lateral, 0.0))
	var col := Const.floor_v(p)
	var y := World.surface_y(World.wrap_x(col.x), World.wrap_z(col.z), col.y + 6)
	if y > 0:
		p.y = float(y) + 1.0
	return p


# ---------------------------------------------------------------- behaviours
func _routine_step(delta: float) -> void:
	_wander_pause -= delta
	if activity == NpcRole.ACT_SLEEP and _at_target(1.4):
		set_plane_velocity(0.0)
		return
	if activity == NpcRole.ACT_WORK and _at_target(1.2):
		set_plane_velocity(0.0)
		face_toward(_target)
		return
	if _target == Vector3.INF or _at_target(0.8):
		set_plane_velocity(move_plane_damped(0.0, delta))
		return
	_walk_toward(_target, delta, 1.0)


func _combat_step(delta: float) -> void:
	var t := threat_target
	var stands := is_crew or (role != null and role.defends())
	if stands:
		# Guards defend their home; crew defend whatever the player is standing on.
		var anchor := home_position if home_position != Vector3.INF else global_position
		if is_crew and Game.player != null:
			anchor = Game.player.global_position
		if t.global_position.distance_to(anchor) > defend_radius * 1.4:
			threat_target = null
			return
		_walk_toward(t.global_position, delta, 1.15)
		face_toward(t.global_position)
		_swing_at(t)
	elif flees:
		var away: Vector3 = global_position + (global_position - t.global_position).normalized() * 8.0
		_walk_toward(away, delta, 1.3)
		if on_floor and on_wall:
			jump()
	else:
		set_plane_velocity(0.0)


## Generic melee. Roles raise [member melee_damage] to make it bite.
func _swing_at(t: VoxelEntity) -> void:
	if melee_damage <= 0.0 or attack_cooldown > 0.0 or t == null or t.dead:
		return
	if global_position.distance_to(t.global_position) > melee_reach:
		return
	attack_cooldown = swing_cooldown
	t.apply_damage(melee_damage * (1.0 + float(Game.difficulty) * 0.15), Const.ELEM_PHYSICAL, self)
	t.knockback(t.global_position - global_position, 6.0)
	Events.play_sound.emit(&"swing", global_position)


func _follow_step(delta: float) -> void:
	var p := Game.player
	if p == null:
		return
	_align_depth_with(p)
	var d := global_position.distance_to(p.global_position)
	if d > 26.0:
		# Lost them entirely (a teleport, a shift through solid rock): catch up.
		teleport(VoxelPhysics.unstick(p.global_position + View.plane_dir_to_world(Vector2(1.2, 0.0)), box_size))
		return
	var lat := absf(Const.lateral_of(p.global_position - global_position, View.view))
	if lat < 2.0:
		set_plane_velocity(move_plane_damped(0.0, delta))
		face_toward(p.global_position)
		return
	_walk_toward(p.global_position, delta, 1.2 if lat > 6.0 else 0.9)


## Crew mirror the player's depth layer so a shift never leaves them walled off.
func _align_depth_with(p: Node3D) -> void:
	var my_depth := View.depth_of(global_position)
	var their_depth := View.depth_of(p.global_position)
	if absf(my_depth - their_depth) < 0.75:
		return
	var dest := View.with_depth(global_position, their_depth)
	if VoxelPhysics.aabb_is_free(dest, box_size):
		begin_layer_shift(dest)


func _stand_and_face(p: Node3D, delta: float) -> void:
	set_plane_velocity(move_plane_damped(0.0, delta))
	if p != null:
		face_toward(p.global_position)


# =========================================================================
#  Plane-space walking
# =========================================================================
## Smoothly approaches a lateral speed instead of snapping to it.
func move_plane_damped(desired: float, delta: float) -> float:
	var cur := plane_velocity()
	return lerpf(cur, desired, clampf(delta * 9.0, 0.0, 1.0))


## Steps toward [param dest]. When the monster agent's `MobPath` module is
## present the route comes from its plane-space A* (which can duck behind walls
## by changing depth layer); otherwise the built-in walker below handles steps,
## gaps and jumps. [param urgency] scales speed.
func _walk_toward(dest: Vector3, delta: float, urgency: float = 1.0) -> void:
	_repath_t -= delta
	var steer := _waypoint_toward(dest, delta)
	var lateral_delta := Const.lateral_of(steer - global_position, View.view)
	if absf(lateral_delta) < 0.45:
		set_plane_velocity(move_plane_damped(0.0, delta))
		return
	var dir := signf(lateral_delta)

	facing = 1 if dir > 0.0 else -1
	var speed := move_speed * clampf(urgency, 0.4, 1.6)
	if activity == NpcRole.ACT_WANDER or activity == NpcRole.ACT_SOCIALISE:
		speed *= 0.55
	set_plane_velocity(move_plane_damped(dir * speed, delta))

	if not on_floor:
		return
	var climb := _obstacle_height(int(dir))
	if climb > 0:
		# One-block steps are handled by auto_step; anything taller needs a jump.
		if climb <= 2:
			jump(jump_speed * 0.85)
		else:
			_stuck_t += delta
			if _stuck_t > 1.2:
				_stuck_t = 0.0
				_abandon_path()
				_target = _near_home(wander_radius)
	elif _ledge_ahead(int(dir)) and not is_crew and threat_target == null:
		# Villagers do not walk off cliffs; they turn around.
		set_plane_velocity(0.0)
		_abandon_path()
		_target = _near_home(wander_radius)
	else:
		_stuck_t = 0.0


## Returns the point to steer at: the next A* waypoint when a route exists,
## otherwise [param dest] itself.
func _waypoint_toward(dest: Vector3, _delta: float) -> Vector3:
	if not _pathing_available():
		return dest
	if global_position.distance_to(dest) < 3.5:
		_abandon_path()
		return dest
	if _repath_t <= 0.0 or _path.is_empty() or dest.distance_to(_path_goal) > 4.0:
		_repath_t = _rng.randf_range(1.1, 1.9)
		_path_goal = dest
		var opts := {
			"profile": &"walk", "height": 2, "jump": 2, "max_fall": 4,
			"allow_layer": is_crew, "max_nodes": 500,
		}
		var route: Variant = _pathing.call(&"find_path", global_position, dest, opts)
		_path.clear()
		if route is Array:
			for w: Variant in route as Array:
				if w is Vector3:
					_path.append(w)
		_path_i = 0
	if _path.is_empty():
		return dest
	while _path_i < _path.size() \
			and absf(Const.lateral_of(_path[_path_i] - global_position, View.view)) < 0.9:
		_path_i += 1
	if _path_i >= _path.size():
		_abandon_path()
		return dest
	return _path[_path_i]


func _abandon_path() -> void:
	_path.clear()
	_path_i = 0
	_path_goal = Vector3.INF
	_repath_t = 0.4


func _pathing_available() -> bool:
	if not _pathing_probed:
		_pathing_probed = true
		if ResourceLoader.exists(PATHING_SCRIPT):
			var scr := load(PATHING_SCRIPT) as Script
			if scr != null and scr.has_method(&"find_path"):
				_pathing = scr
	return _pathing != null


func _foot_block(dir: float, dy: int) -> Vector3i:
	var ahead: Vector3 = global_position + View.plane_dir_to_world(Vector2(dir * 0.75, 0.0))
	return World.normalize(Const.floor_v(ahead) + Vector3i(0, dy, 0))


## Blocks of climbing needed to continue in [param dir]; 0 when the way is clear.
func _obstacle_height(dir: int) -> int:
	if _pathing_available() and _pathing.has_method(&"obstacle_height"):
		return int(_pathing.call(&"obstacle_height", global_position, dir, 2, 4))
	if not World.is_solid(_foot_block(float(dir), 0)):
		return 0
	if not World.is_solid(_foot_block(float(dir), 1)):
		return 1
	if not World.is_solid(_foot_block(float(dir), 2)):
		return 2
	return 3


func _ledge_ahead(dir: int) -> bool:
	if _pathing_available() and _pathing.has_method(&"is_ledge_ahead"):
		return bool(_pathing.call(&"is_ledge_ahead", global_position, dir, 2, 1))
	for dy in range(-1, -4, -1):
		if World.is_solid(_foot_block(float(dir), dy)):
			return false
	return true


func _at_target(tolerance: float) -> bool:
	if _target == Vector3.INF:
		return true
	return absf(Const.lateral_of(_target - global_position, View.view)) <= tolerance


# =========================================================================
#  Danger
# =========================================================================
func _scan_for_danger() -> void:
	if is_crew and Game.player != null:
		# Crew defend the player instead of a home.
		var foe := _nearest_hostile(global_position, DANGER_RANGE)
		threat_target = foe
		return
	var anchor := home_position if home_position != Vector3.INF else global_position
	var defends := role != null and role.defends()
	var radius := defend_radius if defends else DANGER_RANGE
	var t := _nearest_hostile(anchor if defends else global_position, radius)
	if t == null:
		threat_target = null
		return
	if defends:
		threat_target = t
		if activity != &"fight":
			say(_battle_cry(), 1.6)
		activity = &"fight"
	elif flees:
		threat_target = t
		activity = &"flee"


func _nearest_hostile(from: Vector3, radius: float) -> VoxelEntity:
	var best: VoxelEntity = null
	var best_d := radius * radius
	for n: Node in get_tree().get_nodes_in_group(&"entities"):
		var e := n as VoxelEntity
		if e == null or e.dead or e == self or e.faction != &"hostile":
			continue
		var d := from.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _battle_cry() -> String:
	var cries := ["To the wall!", "We have company!", "Sound the horn!", "Behind you!"]
	return cries[_rng.randi_range(0, cries.size() - 1)]


## Being hit turns a fleeing villager into a screaming one, and makes the whole
## village's guards care.
func modify_incoming_damage(amount: float, element: String, source: Node) -> float:
	if source == Game.player:
		NpcReputation.adjust_npc(npc_id, -20.0)
		if village_id != &"":
			NpcReputation.adjust_faction(village_id, -8.0)
		_alert_village(source as VoxelEntity)
		say("Why?!", 2.0)
	elif source is VoxelEntity and (source as VoxelEntity).faction == &"hostile":
		threat_target = source as VoxelEntity
	return super.modify_incoming_damage(amount, element, source)


func _alert_village(aggressor: VoxelEntity) -> void:
	if aggressor == null or village_id == &"":
		return
	for n: Node in get_tree().get_nodes_in_group(&"npc"):
		var other := n as NpcBase
		if other == null or other == self or other.village_id != village_id:
			continue
		if other.role != null and other.role.defends():
			other.threat_target = aggressor
			other.activity = &"fight"


func on_death(source: Node) -> void:
	Events.toast("%s has died." % display_name, "bad")
	if source == Game.player and village_id != &"":
		NpcReputation.adjust_faction(village_id, -25.0)
	NpcCrew.dismiss(npc_id)
	queue_free()


# =========================================================================
#  Talking
# =========================================================================
## Floating bark above the head.
func say(msg: String, duration: float = 3.0) -> void:
	if visual != null:
		visual.show_bubble(msg, duration)


func _maybe_greet() -> void:
	if _greet_t > 0.0 or in_conversation or activity == NpcRole.ACT_SLEEP:
		return
	var p := Game.player
	if p == null or not in_same_layer(p):
		return
	if global_position.distance_to(p.global_position) > GREET_RANGE:
		return
	_greet_t = GREET_COOLDOWN + _rng.randf_range(-4.0, 8.0)
	say(greeting_line(), 3.2)


## Picks a bark, shaded by how this NPC feels about the player.
func greeting_line() -> String:
	var rep := NpcReputation.of_npc(npc_id)
	if rep <= NpcReputation.BAND_THRESHOLDS[NpcReputation.BAND_COLD]:
		var cold := ["Keep walking.", "You've a nerve showing your face.",
			"I've nothing to say to you.", "Guards know your name now."]
		return cold[_rng.randi_range(0, cold.size() - 1)]
	if rep >= NpcReputation.BAND_THRESHOLDS[NpcReputation.BAND_TRUSTED]:
		var warm := ["There you are!", "Best news I've had all week.",
			"Friend! Come here.", "Anything you need, it's yours."]
		return warm[_rng.randi_range(0, warm.size() - 1)]
	var lines := role.greetings()
	if lines.is_empty():
		return "..."
	return lines[_rng.randi_range(0, lines.size() - 1)]


func _check_interact_input() -> void:
	if in_conversation or not QuestDialogue.is_finished():
		return
	if UI.captures_input() or Game.paused:
		return
	var p := Game.player
	if p == null or not in_same_layer(p):
		return
	if global_position.distance_to(p.global_position) > TALK_RANGE:
		return
	if Input.is_action_just_pressed(&"interact"):
		interact(p)


## Opens the conversation. Returns false when this NPC has nothing to say.
func interact(player: Node) -> bool:
	if dead or in_conversation:
		return false
	if activity == NpcRole.ACT_SLEEP:
		say("...mmf. Come back when the sun's up.", 2.5)
		return false
	if role != null and role.on_interact(self, player):
		return true
	if visual != null:
		visual.hide_bubble()
	if player is Node3D:
		face_toward((player as Node3D).global_position)
	in_conversation = true
	if not QuestDialogue.begin(self, dialogue_tree_id()):
		in_conversation = false
		say("...", 1.5)
		return false
	return true


## Called by [QuestDialogue] when the window closes.
func on_dialogue_ended() -> void:
	in_conversation = false


## Which tree to open: explicit override, then a quest's own tree, then the role.
func dialogue_tree_id() -> String:
	if dialogue_tree != "" and QuestDialogue.has_tree(dialogue_tree):
		return dialogue_tree
	for qid: String in Quests.active_ids():
		var q := Quests.quest_of(qid)
		if q != null and q.turn_in == npc_id and q.dialogue_tree != "" \
				and QuestDialogue.has_tree(q.dialogue_tree):
			return q.dialogue_tree
	if role != null:
		var t := role.dialogue_tree(self)
		if QuestDialogue.has_tree(t):
			return t
	return "villager_default"


# =========================================================================
#  Quests
# =========================================================================
## A quest id this NPC could hand over right now, or "". Hand-authored quests
## naming this NPC as giver win; otherwise one is generated on demand and cached.
func pending_quest_id() -> String:
	if not can_offer_quests:
		return ""
	if _pending_quest != "" and Quests.can_start(_pending_quest):
		return _pending_quest
	_pending_quest = ""
	var authored := Quests.offers_of(npc_id)
	if authored.size() > 0:
		_pending_quest = authored[0]
		return _pending_quest
	if NpcReputation.of_npc(npc_id) <= NpcReputation.BAND_THRESHOLDS[NpcReputation.BAND_COLD]:
		return ""
	_pending_quest = Quests.generate_for(self, 0)
	return _pending_quest


## Announces the pending quest so the menus agent can raise the accept window.
func offer_pending_quest() -> bool:
	var qid := pending_quest_id()
	if qid == "":
		return false
	Quests.offer(qid, self)
	return true


## Turn-in convenience used by dialogue trees.
func complete_quest_here(quest_id: String) -> bool:
	return Quests.complete(quest_id)


# =========================================================================
#  Shop
# =========================================================================
## `[{id, count, price}]`, rebuilt once per in-game day.
func shop_stock() -> Array[Dictionary]:
	if shop_kinds.is_empty():
		return []
	if Game.day != _stock_day:
		_stock_day = Game.day
		_stock = NpcShop.build_stock(npc_id, planet_tier() + shop_tier_bonus,
			shop_kinds, shop_size, Game.day)
	return _stock


func planet_tier() -> int:
	var meta: Dictionary = Universe.planet_meta(World.planet_id)
	return clampi(int(meta.get("threat", 1)), 1, 10)


func sells() -> bool:
	return not shop_kinds.is_empty()


# =========================================================================
#  Crew
# =========================================================================
func become_crew() -> void:
	is_crew = true
	activity = &"follow"
	flees = false
	move_speed = maxf(move_speed, 5.6)
	say("Right then. Lead on.", 3.0)


func leave_crew() -> void:
	is_crew = false
	home_position = global_position
	activity = NpcRole.ACT_IDLE


func crew_blurb() -> String:
	return NpcRoleCrew.blurb(crew_skill)


# =========================================================================
#  Persistence
# =========================================================================
func save_state() -> Dictionary:
	var d := super.save_state()
	d["npc_id"] = String(npc_id)
	d["name"] = display_name
	d["race"] = String(race)
	d["role"] = String(role_id)
	d["village"] = String(village_id)
	d["seed"] = visual_seed
	d["tree"] = dialogue_tree
	d["skill"] = String(crew_skill)
	d["crew"] = is_crew
	d["home"] = [home_position.x, home_position.y, home_position.z]
	if work_position != Vector3.INF:
		d["work"] = [work_position.x, work_position.y, work_position.z]
	if bed_position != Vector3.INF:
		d["bed"] = [bed_position.x, bed_position.y, bed_position.z]
	d["pending"] = _pending_quest
	return d


func load_state(d: Dictionary) -> void:
	super.load_state(d)
	configure(d)
	is_crew = bool(d.get("crew", false))
	_pending_quest = String(d.get("pending", ""))
	if is_crew:
		become_crew()
