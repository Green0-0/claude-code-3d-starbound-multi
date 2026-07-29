## The monster mind: a behaviour tree whose top-level choice is made by utility
## scoring rather than fixed priority, so a monster picks the action that makes
## the most sense right now instead of walking down a ladder of `if`s.
##
## Composition
##   `UtilitySelector` scores its children each tick and runs the winner, with
##   hysteresis so a monster does not twitch between two near-equal options.
##   Underneath it, ordinary `Sequence` / `Selector` / decorators express the
##   internals of one behaviour.
##
## Everything is plane-space. "Left" and "right" mean screen-left and
## screen-right in the *current* view; the depth axis is treated as a first
## class part of navigation via `LayerPursue`, which is what lets a monster on
## another layer route around a wall and step into the player's plane.
##
## `mob` is untyped throughout to keep this script free of a dependency on
## `MobBase` (which depends on this one).
class_name MobBrain
extends RefCounted


# =============================================================== blackboard
## Everything the tree remembers between ticks.
class Blackboard extends RefCounted:
	var target: Node3D = null
	var threat_source: Node = null
	## Where the target was last actually perceived, and on which depth layer.
	var last_known_pos: Vector3 = Vector3.ZERO
	var last_known_layer: int = 0
	var time_since_seen: float = 999.0
	## 0..1 build-up before a monster commits to hunting.
	var alert: float = 0.0
	## Accumulated "how dangerous is this fight" estimate; drives fleeing.
	var threat: float = 0.0
	var home: Vector3 = Vector3.ZERO
	var home_layer: int = 0
	var sound_pos: Vector3 = Vector3.ZERO
	var has_sound: bool = false
	var called_help: bool = false
	## Plane-space lateral bounds of the patrol beat.
	var patrol_min: float = 0.0
	var patrol_max: float = 0.0
	var patrol_dir: int = 1
	var wander_dir: int = 1
	var wander_timer: float = 0.0
	var strafe_dir: int = 1
	var strafe_timer: float = 0.0
	var cooldowns: Dictionary = {}
	var flags: Dictionary = {}

	func forget() -> void:
		target = null
		time_since_seen = 999.0
		alert = 0.0
		threat = 0.0

	func ready(key: StringName) -> bool:
		return float(cooldowns.get(key, 0.0)) <= 0.0

	func arm(key: StringName, seconds: float) -> void:
		cooldowns[key] = seconds

	func advance(delta: float) -> void:
		for k: StringName in cooldowns.keys():
			var v: float = float(cooldowns[k]) - delta
			if v <= 0.0:
				cooldowns.erase(k)
			else:
				cooldowns[k] = v


# ================================================================ tree nodes
## Base behaviour-tree node. `score` is only consulted by `UtilitySelector`.
class BNode extends RefCounted:
	const FAILURE := 0
	const SUCCESS := 1
	const RUNNING := 2

	var node_name: String = "node"

	func tick(_mob, _bb: Blackboard, _delta: float) -> int:
		return FAILURE

	## Utility, roughly 0..10. Negative means "never pick me".
	func score(_mob, _bb: Blackboard) -> float:
		return 0.0

	func reset(_mob, _bb: Blackboard) -> void:
		pass


class Sequence extends BNode:
	var children: Array = []
	var _index := 0

	func _init(p_children: Array = []) -> void:
		children = p_children
		node_name = "sequence"

	func tick(mob, bb: Blackboard, delta: float) -> int:
		while _index < children.size():
			var r: int = (children[_index] as BNode).tick(mob, bb, delta)
			if r == RUNNING:
				return RUNNING
			if r == FAILURE:
				_index = 0
				return FAILURE
			_index += 1
		_index = 0
		return SUCCESS

	func reset(mob, bb: Blackboard) -> void:
		_index = 0
		for c: BNode in children:
			c.reset(mob, bb)


class Selector extends BNode:
	var children: Array = []

	func _init(p_children: Array = []) -> void:
		children = p_children
		node_name = "selector"

	func tick(mob, bb: Blackboard, delta: float) -> int:
		for c: BNode in children:
			var r: int = c.tick(mob, bb, delta)
			if r != FAILURE:
				return r
		return FAILURE


## The interesting composite: scores every child and runs the best one.
class UtilitySelector extends BNode:
	var children: Array = []
	var hysteresis := 1.15
	var _current: BNode = null

	func _init(p_children: Array = []) -> void:
		children = p_children
		node_name = "utility"

	func tick(mob, bb: Blackboard, delta: float) -> int:
		var best: BNode = null
		var best_score := -INF
		for c: BNode in children:
			var s: float = c.score(mob, bb)
			if c == _current:
				s *= hysteresis          # stickiness: finish what you started
			if s > best_score:
				best_score = s
				best = c
		if best == null or best_score <= 0.0:
			return FAILURE
		if best != _current:
			if _current != null:
				_current.reset(mob, bb)
			_current = best
		node_name = best.node_name
		return best.tick(mob, bb, delta)

	func current_name() -> String:
		return _current.node_name if _current != null else "none"


## Runs its child at most once every `seconds`.
class Cooldown extends BNode:
	var child: BNode = null
	var seconds := 1.0
	var key: StringName = &"cd"

	func _init(p_key: StringName, p_seconds: float, p_child: BNode) -> void:
		key = p_key
		seconds = p_seconds
		child = p_child
		node_name = "cooldown:" + String(p_key)

	func tick(mob, bb: Blackboard, delta: float) -> int:
		if not bb.ready(key):
			return FAILURE
		var r: int = child.tick(mob, bb, delta)
		if r == SUCCESS:
			bb.arm(key, seconds)
		return r


class Condition extends BNode:
	var predicate: Callable
	var child: BNode = null

	func _init(p_predicate: Callable, p_child: BNode = null) -> void:
		predicate = p_predicate
		child = p_child
		node_name = "condition"

	func tick(mob, bb: Blackboard, delta: float) -> int:
		if not predicate.is_valid() or not bool(predicate.call(mob, bb)):
			return FAILURE
		if child == null:
			return SUCCESS
		return child.tick(mob, bb, delta)


# =============================================================== leaf actions
## Walk a fixed beat between two lateral extremes, turning at ledges and walls.
class Patrol extends BNode:
	func _init() -> void:
		node_name = "patrol"

	func score(_mob, bb: Blackboard) -> float:
		return 0.6 if bb.target == null else 0.0

	func tick(mob, bb: Blackboard, _delta: float) -> int:
		if bb.patrol_max - bb.patrol_min < 1.0:
			var l: float = mob.plane_position().x
			bb.patrol_min = l - 7.0
			bb.patrol_max = l + 7.0
		var lat: float = mob.plane_position().x
		if lat <= bb.patrol_min:
			bb.patrol_dir = 1
		elif lat >= bb.patrol_max:
			bb.patrol_dir = -1
		if mob.blocked_ahead(bb.patrol_dir):
			bb.patrol_dir = -bb.patrol_dir
		mob.motor_move_lateral(float(bb.patrol_dir), false)
		mob.set_anim(MobVisual.ST_WALK)
		return RUNNING


## Aimless drifting with occasional pauses. Baseline for everything idle.
class Wander extends BNode:
	func _init() -> void:
		node_name = "wander"

	func score(_mob, bb: Blackboard) -> float:
		return 0.5 if bb.target == null else 0.0

	func tick(mob, bb: Blackboard, delta: float) -> int:
		bb.wander_timer -= delta
		if bb.wander_timer <= 0.0:
			bb.wander_timer = randf_range(1.2, 3.4)
			bb.wander_dir = [-1, 0, 0, 1][randi() % 4]
		if bb.wander_dir == 0:
			mob.motor_stop()
			mob.set_anim(MobVisual.ST_IDLE)
			return RUNNING
		if mob.blocked_ahead(bb.wander_dir):
			bb.wander_dir = -bb.wander_dir
		mob.motor_move_lateral(float(bb.wander_dir), false)
		mob.set_anim(MobVisual.ST_WALK)
		return RUNNING


## Close on the target through the current plane, pathing around obstacles.
class Chase extends BNode:
	func _init() -> void:
		node_name = "chase"

	func score(mob, bb: Blackboard) -> float:
		if bb.target == null:
			return 0.0
		if not mob.same_play_layer_as(bb.target):
			return 0.0
		var d: float = mob.plane_distance_to(bb.last_known_pos)
		if d > mob.leash_range:
			return 0.0
		if d <= mob.species.attack_range:
			return 1.0        # Attack should win, but keep chase warm
		return 5.0 - bb.threat * 0.5

	func tick(mob, bb: Blackboard, _delta: float) -> int:
		var goal: Vector3 = bb.target.global_position if bb.target != null else bb.last_known_pos
		var r: int = mob.navigate_to(goal, true)
		mob.set_anim(MobVisual.ST_RUN)
		mob.face_toward(goal)
		return RUNNING if r != 2 else FAILURE


## **The layer-aware pursuit.** The target is in another depth layer, so the
## route has to leave the plane the player is watching, travel behind the
## scenery, and come back in. `MobPath` supplies layer-transition edges; this
## node just commits to the result and, when pathing fails, brute-forces its way
## across by lining up laterally and stepping through.
class LayerPursue extends BNode:
	var _stuck := 0.0

	func _init() -> void:
		node_name = "layer_pursue"

	func score(mob, bb: Blackboard) -> float:
		if bb.target == null:
			return 0.0
		var dl: int = mob.layer_delta_to(bb.target)
		if dl == 0:
			return 0.0
		if absi(dl) > mob.species.sight_layers + 2:
			return 0.0
		var d: float = mob.plane_distance_to(bb.target.global_position)
		if d > mob.leash_range * 1.25:
			return 0.0
		# Wanting to reach the player beats almost everything else.
		return 6.2 - float(absi(dl)) * 0.25

	func reset(_mob, _bb: Blackboard) -> void:
		_stuck = 0.0

	func tick(mob, bb: Blackboard, delta: float) -> int:
		var t: Node3D = bb.target
		if t == null:
			return FAILURE
		var r: int = mob.navigate_to(t.global_position, true)
		mob.set_anim(MobVisual.ST_RUN)
		if r == 2:
			_stuck += delta
		else:
			_stuck = maxf(0.0, _stuck - delta * 0.5)
		# Fallback: align laterally, then push straight through the depth axis.
		if _stuck > 0.6:
			var lat: float = mob.lateral_to(t.global_position)
			if absf(lat) > 1.0:
				mob.motor_move_lateral(signf(lat), true)
				mob.auto_hop()
			else:
				mob.motor_stop()
				if not mob.step_toward_layer(mob.depth_layer() + signi(mob.layer_delta_to(t))):
					# Blocked even head-on: try going the long way round.
					mob.step_toward_layer(mob.depth_layer() - signi(mob.layer_delta_to(t)))
				_stuck = 0.0
		return RUNNING


## Melee swing with a wind-up the player can read and dodge.
class Attack extends BNode:
	var _windup := -1.0

	func _init() -> void:
		node_name = "attack"

	func score(mob, bb: Blackboard) -> float:
		if bb.target == null or not mob.same_play_layer_as(bb.target):
			return 0.0
		if mob.plane_distance_to(bb.target.global_position) > mob.species.attack_range:
			return 0.0
		if _windup >= 0.0:
			return 9.0
		return 8.0 if mob.can_attack() else 0.0

	func reset(_mob, _bb: Blackboard) -> void:
		_windup = -1.0

	func tick(mob, bb: Blackboard, delta: float) -> int:
		var t: Node3D = bb.target
		if t == null:
			return FAILURE
		mob.motor_stop()
		mob.face_toward(t.global_position)
		if _windup < 0.0:
			_windup = mob.species.attack_windup
			mob.set_anim(MobVisual.ST_WINDUP)
			mob.telegraph(1.0)
			return RUNNING
		_windup -= delta
		if _windup > 0.0:
			return RUNNING
		_windup = -1.0
		mob.telegraph(0.0)
		mob.set_anim(MobVisual.ST_ATTACK)
		mob.do_melee(t)
		return SUCCESS


## Stand off and shoot; back away when the target closes.
class RetreatAndShoot extends BNode:
	func _init() -> void:
		node_name = "ranged"

	func score(mob, bb: Blackboard) -> float:
		if bb.target == null or not mob.species.is_ranged():
			return 0.0
		if not mob.same_play_layer_as(bb.target):
			return 0.0
		var d: float = mob.plane_distance_to(bb.target.global_position)
		if d > mob.species.attack_range:
			return 0.0
		return 7.5

	func tick(mob, bb: Blackboard, delta: float) -> int:
		var t: Node3D = bb.target
		if t == null:
			return FAILURE
		var d: float = mob.plane_distance_to(t.global_position)
		var ideal: float = mob.species.attack_range * 0.62
		mob.face_toward(t.global_position)
		if d < ideal * 0.6:
			mob.motor_move_lateral(-signf(mob.lateral_to(t.global_position)), true)
			mob.set_anim(MobVisual.ST_RUN)
		elif d > ideal * 1.25:
			mob.motor_move_lateral(signf(mob.lateral_to(t.global_position)), false)
			mob.set_anim(MobVisual.ST_WALK)
		else:
			mob.motor_stop()
			mob.set_anim(MobVisual.ST_IDLE)
		if mob.can_attack() and mob.has_line_of_sight(t):
			mob.set_anim(MobVisual.ST_WINDUP)
			mob.do_ranged(t)
		bb.strafe_timer -= delta
		return RUNNING


## Orbit the target inside the plane so a melee monster is not a stationary
## punching bag between swings.
class CircleStrafe extends BNode:
	func _init() -> void:
		node_name = "strafe"

	func score(mob, bb: Blackboard) -> float:
		if bb.target == null or not mob.same_play_layer_as(bb.target):
			return 0.0
		var d: float = mob.plane_distance_to(bb.target.global_position)
		if d > mob.species.attack_range * 2.2:
			return 0.0
		return 0.0 if mob.can_attack() else 6.5

	func tick(mob, bb: Blackboard, delta: float) -> int:
		var t: Node3D = bb.target
		if t == null:
			return FAILURE
		bb.strafe_timer -= delta
		if bb.strafe_timer <= 0.0:
			bb.strafe_timer = randf_range(0.7, 1.6)
			bb.strafe_dir = -bb.strafe_dir
		var dir := float(bb.strafe_dir)
		if mob.blocked_ahead(bb.strafe_dir):
			bb.strafe_dir = -bb.strafe_dir
			dir = float(bb.strafe_dir)
		mob.motor_move_lateral(dir * 0.75, false)
		mob.face_toward(t.global_position)
		mob.set_anim(MobVisual.ST_WALK)
		return RUNNING


## Run away, preferring to break line of sight — including by leaving the plane.
class Flee extends BNode:
	func _init() -> void:
		node_name = "flee"

	func score(mob, bb: Blackboard) -> float:
		if bb.target == null and bb.threat_source == null:
			return 0.0
		var frac: float = mob.health / maxf(1.0, mob.max_health)
		var timid: float = mob.species.flagf(&"timid", 0.0)
		if mob.species.is_passive():
			return 8.0
		if frac < mob.species.flagf(&"flee_below", 0.0) or timid > 0.0:
			return 7.0 + (1.0 - frac) * 2.0
		return 0.0

	func tick(mob, bb: Blackboard, _delta: float) -> int:
		var from: Node3D = bb.target
		if from == null and bb.threat_source is Node3D:
			from = bb.threat_source
		if from == null:
			return FAILURE
		var away := -signf(mob.lateral_to(from.global_position))
		if away == 0.0:
			away = 1.0
		if mob.blocked_ahead(int(away)):
			# Cornered — vanish into an adjacent layer instead.
			if not mob.step_toward_layer(mob.depth_layer() + 1):
				mob.step_toward_layer(mob.depth_layer() - 1)
		mob.motor_move_lateral(away, true)
		mob.auto_hop()
		mob.set_anim(MobVisual.ST_RUN)
		return RUNNING


## Shout: wakes every ally of the same species within earshot.
class CallForHelp extends BNode:
	func _init() -> void:
		node_name = "call_help"

	func score(_mob, bb: Blackboard) -> float:
		if bb.target == null or bb.called_help:
			return 0.0
		return 8.6

	func tick(mob, bb: Blackboard, _delta: float) -> int:
		bb.called_help = true
		mob.motor_stop()
		mob.set_anim(MobVisual.ST_WINDUP)
		mob.call_for_help(mob.species.hearing_range)
		Events.play_sound.emit(&"monster_alert", mob.global_position)
		return SUCCESS


## Walk to where a noise came from and look around.
class InvestigateSound extends BNode:
	var _linger := 0.0

	func _init() -> void:
		node_name = "investigate"

	func score(_mob, bb: Blackboard) -> float:
		if not bb.has_sound or bb.target != null:
			return 0.0
		return 3.4

	func tick(mob, bb: Blackboard, delta: float) -> int:
		if _linger > 0.0:
			_linger -= delta
			mob.motor_stop()
			mob.set_anim(MobVisual.ST_IDLE)
			if _linger <= 0.0:
				bb.has_sound = false
			return RUNNING
		var r: int = mob.navigate_to(bb.sound_pos, false)
		mob.set_anim(MobVisual.ST_WALK)
		if r != 1:
			return RUNNING
		_linger = 2.0
		return RUNNING


## Give up and go back to the spawn point — including back to its home layer.
class ReturnHome extends BNode:
	func _init() -> void:
		node_name = "return_home"

	func score(mob, bb: Blackboard) -> float:
		if bb.target != null:
			return 0.0
		var d: float = mob.plane_distance_to(bb.home)
		if d < 3.0 and mob.depth_layer() == bb.home_layer:
			return 0.0
		return 1.8 + minf(3.0, d * 0.05)

	func tick(mob, bb: Blackboard, _delta: float) -> int:
		var goal: Vector3 = mob.world_at_layer(bb.home, bb.home_layer)
		var r: int = mob.navigate_to(goal, false)
		mob.set_anim(MobVisual.ST_WALK)
		return SUCCESS if r == 1 else RUNNING


## Follow the player around, across layers, and pick fights on their behalf.
## Used by captured pets.
class Escort extends BNode:
	func _init() -> void:
		node_name = "escort"

	func score(mob, bb: Blackboard) -> float:
		if mob.escort_of == null:
			return 0.0
		# Beats wandering always; loses to a fight the pet can actually join.
		return 4.0 if bb.target == null else 1.0

	func tick(mob, bb: Blackboard, _delta: float) -> int:
		var leader: Node3D = mob.escort_of
		if leader == null:
			return FAILURE
		# A pet must never be stranded a plane away from its owner.
		if mob.depth_layer() != View.layer:
			mob.step_toward_layer(View.layer)
		var d: float = mob.plane_distance_to(leader.global_position)
		if d > mob.species.flagf(&"follow_distance", 3.0):
			mob.navigate_to(leader.global_position, d > 9.0)
			mob.set_anim(MobVisual.ST_RUN if d > 9.0 else MobVisual.ST_WALK)
		else:
			mob.motor_stop()
			mob.set_anim(MobVisual.ST_IDLE)
		if d > 26.0:
			mob.teleport(leader.global_position + Vector3(0, 1.0, 0))
		bb.home = leader.global_position
		return RUNNING


## Hover in place, bobbing. For rooted and floating things.
class Hold extends BNode:
	func _init() -> void:
		node_name = "hold"

	func score(_mob, _bb: Blackboard) -> float:
		return 0.35

	func tick(mob, _bb: Blackboard, _delta: float) -> int:
		mob.motor_stop()
		mob.set_anim(MobVisual.ST_IDLE)
		return RUNNING


# ==================================================================== brain
var bb := Blackboard.new()
var root: BNode = null
var profile: StringName = &"melee"


func tick(mob, delta: float) -> void:
	bb.advance(delta)
	bb.time_since_seen += delta
	if root != null:
		root.tick(mob, bb, delta)


func current_action() -> String:
	if root is UtilitySelector:
		return (root as UtilitySelector).current_name()
	return root.node_name if root != null else "idle"


func reset(mob) -> void:
	if root != null:
		root.reset(mob, bb)


# ================================================================== profiles
## Build a tree for a species brain profile. Unknown profiles fall back to
## `melee`, which is a perfectly serviceable monster.
static func build(p_profile: StringName) -> MobBrain:
	var b := MobBrain.new()
	b.profile = p_profile
	var common: Array = [Wander.new(), Patrol.new(), ReturnHome.new(), InvestigateSound.new()]
	match p_profile:
		&"melee":
			b.root = UtilitySelector.new([
				Attack.new(), CircleStrafe.new(), Chase.new(), LayerPursue.new(),
				CallForHelp.new(), Flee.new()] + common)
		&"pack":
			b.root = UtilitySelector.new([
				Attack.new(), CircleStrafe.new(), Chase.new(), LayerPursue.new(),
				CallForHelp.new(), Flee.new()] + common)
		&"ranged":
			b.root = UtilitySelector.new([
				RetreatAndShoot.new(), Attack.new(), Chase.new(), LayerPursue.new(),
				Flee.new()] + common)
		&"artillery":
			b.root = UtilitySelector.new([
				RetreatAndShoot.new(), Chase.new(), Flee.new()] + common)
		&"turret":
			b.root = UtilitySelector.new([RetreatAndShoot.new(), Hold.new()])
		&"flier":
			b.root = UtilitySelector.new([
				Attack.new(), Chase.new(), LayerPursue.new(), Flee.new(),
				Wander.new(), ReturnHome.new(), InvestigateSound.new()])
		&"aquatic":
			b.root = UtilitySelector.new([
				Attack.new(), Chase.new(), LayerPursue.new(), Flee.new(),
				Wander.new(), ReturnHome.new()])
		&"ambusher":
			b.root = UtilitySelector.new([
				Attack.new(), Chase.new(), LayerPursue.new(), Hold.new()])
		&"stalker":
			b.root = UtilitySelector.new([Attack.new(), LayerPursue.new(), Chase.new(), Hold.new()])
		&"passive":
			b.root = UtilitySelector.new([Flee.new(), Wander.new(), ReturnHome.new()])
		&"support":
			b.root = UtilitySelector.new([
				Flee.new(), RetreatAndShoot.new(), Chase.new()] + common)
		&"suicide":
			b.root = UtilitySelector.new([Chase.new(), LayerPursue.new()] + common)
		&"pet":
			b.root = UtilitySelector.new([
				Attack.new(), Chase.new(), LayerPursue.new(), Escort.new(), Wander.new()])
		&"boss":
			b.root = UtilitySelector.new([
				Attack.new(), RetreatAndShoot.new(), Chase.new(), LayerPursue.new(),
				CircleStrafe.new(), Hold.new()])
		_:
			b.root = UtilitySelector.new([
				Attack.new(), Chase.new(), LayerPursue.new()] + common)
	# Every tree needs a guaranteed floor, or a monster whose situation matches
	# nothing at all would freeze mid-stride with an empty utility set.
	if b.root is UtilitySelector:
		(b.root as UtilitySelector).children.append(Hold.new())
	return b
