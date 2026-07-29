## The roster of NPCs who have signed on with the player.
##
## Crew are the only NPCs that survive leaving a planet: their full descriptor is
## kept here, the node is despawned with the world, and [method respawn_all]
## rebuilds them next to the player after [signal Events.travel_finished]. They
## also track the player across depth layers, so a flip or a shift never strands
## them behind a wall.
class_name NpcCrew
extends RefCounted

const BASE_CAPACITY := 2
## Loaded by path rather than by class name: `NpcSpawner` already depends on this
## file, and a global-class cycle is the one thing GDScript will not forgive.
const SPAWNER_SCRIPT := "res://entities/npc/spawn.gd"

static var _roster: Dictionary = {}      ## npc_id -> descriptor Dictionary
static var _capacity_bonus: int = 0


static func capacity() -> int:
	return BASE_CAPACITY + _capacity_bonus


## Ship upgrades call this to widen the roster.
static func grant_capacity(extra: int) -> void:
	_capacity_bonus = maxi(0, _capacity_bonus + extra)


static func size() -> int:
	return _roster.size()


static func is_hired(npc_id: StringName) -> bool:
	return _roster.has(npc_id)


static func member(npc_id: StringName) -> Dictionary:
	return _roster.get(npc_id, {})


static func members() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: Variant in _roster:
		out.append(_roster[k] as Dictionary)
	return out


static func has_room() -> bool:
	return _roster.size() < capacity()


## Signs [param npc] on. Returns false when the roster is full or they are
## already aboard. The NPC itself flips into FOLLOW behaviour.
static func hire(npc: Node) -> bool:
	if npc == null:
		return false
	var id := StringName(npc.get("npc_id"))
	if id == &"" or _roster.has(id):
		return false
	if not has_room():
		Events.toast("Your ship has no bunk free.", "warn")
		return false
	_roster[id] = descriptor_of(npc)
	if npc.has_method(&"become_crew"):
		npc.call(&"become_crew")
	NpcReputation.adjust_npc(id, 15.0)
	Events.toast("%s joined your crew." % String(npc.get("display_name")), "good")
	Events.play_sound.emit(&"quest_complete", (npc as Node3D).global_position if npc is Node3D else Vector3.ZERO)
	return true


static func dismiss(npc_id: StringName) -> void:
	if not _roster.has(npc_id):
		return
	var name_str := String((_roster[npc_id] as Dictionary).get("name", String(npc_id)))
	_roster.erase(npc_id)
	for n: Node in _live_nodes():
		if StringName(n.get("npc_id")) == npc_id and n.has_method(&"leave_crew"):
			n.call(&"leave_crew")
	Events.toast("%s left your crew." % name_str, "info")


## Snapshot of everything needed to rebuild the NPC on another planet.
static func descriptor_of(npc: Node) -> Dictionary:
	var d := {
		"npc_id": String(npc.get("npc_id")),
		"name": String(npc.get("display_name")),
		"race": String(npc.get("race")),
		"role": String(npc.get("role_id")),
		"village": String(npc.get("village_id")),
		"tree": String(npc.get("dialogue_tree")),
		"skill": String(npc.get("crew_skill")),
		"seed": int(npc.get("visual_seed")),
	}
	if npc.has_method(&"save_state"):
		d["state"] = npc.call(&"save_state")
	return d


## Rebuilds every crew member near the player. Called after planet travel and
## after a save load.
static func respawn_all() -> void:
	var p := Game.player
	if p == null or _roster.is_empty():
		return
	var live := {}
	for n: Node in _live_nodes():
		live[StringName(n.get("npc_id"))] = true
	var spawner := load(SPAWNER_SCRIPT) as Script
	if spawner == null:
		return
	var i := 0
	for k: Variant in _roster:
		var id := StringName(k)
		if live.has(id):
			continue
		i += 1
		var side := 1.0 if i % 2 == 0 else -1.0
		var offset := View.plane_dir_to_world(Vector2(float(1 + i % 3) * side, 0.0))
		var spawn: Vector3 = p.global_position + offset + Vector3(0, 0.5, 0)
		var npc := spawner.call(&"spawn_from_descriptor", _roster[id] as Dictionary, spawn) as Node
		if npc != null and npc.has_method(&"become_crew"):
			npc.call(&"become_crew")


static func _live_nodes() -> Array[Node]:
	var out: Array[Node] = []
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return out
	for n: Node in loop.get_nodes_in_group(&"npc"):
		out.append(n)
	return out


static func clear() -> void:
	_roster.clear()
	_capacity_bonus = 0


# ------------------------------------------------------------ serialisation
static func save_state() -> Dictionary:
	var r := {}
	for k: Variant in _roster:
		r[String(k)] = _roster[k]
	return {"roster": r, "capacity_bonus": _capacity_bonus}


static func load_state(d: Dictionary) -> void:
	_roster.clear()
	for k: Variant in d.get("roster", {}):
		_roster[StringName(k)] = (d["roster"][k] as Dictionary).duplicate(true)
	_capacity_bonus = int(d.get("capacity_bonus", 0))
