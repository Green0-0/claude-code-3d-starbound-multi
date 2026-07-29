## Populates villages from the worldgen/structure agent's markers.
##
## The structure agent writes tile-entity payloads into [member Chunk.tile_data]
## when it stamps a settlement. This node watches [signal Events.chunk_loaded],
## reads every payload that looks like an NPC marker, and builds the villager it
## describes — name, race, role, home, workplace and schedule all derived
## deterministically from the world seed and the marker's block position, so the
## same planet always produces the same village.
##
## [b]Marker contract — deliberately forgiving.[/b] A payload counts as an NPC
## marker when any of these keys holds any of these values:
## [codeblock]
##   keys:   kind | type | marker | tag | entity | spawn | id | class
##   values: npc | villager | npc_spawn | villager_spawn | settler |
##           inhabitant | citizen | crew | merchant | guard | innkeeper |
##           blacksmith | doctor | scientist | trader  (any role id or alias)
## [/codeblock]
## Optional payload fields, each with several accepted spellings:
## [codeblock]
##   role      role | job | profession | occupation | class | npc_role
##   race      race | species | ancestry
##   name      name | npc_name | display_name | title
##   village   village | village_id | settlement | town | camp
##   home      home | home_pos | anchor | position
##   work      work | work_pos | workplace | station | job_pos
##   bed       bed | bed_pos | sleep | sleep_pos
##   social    social | social_pos | plaza | gathering | green
##   tier      tier | threat | level | difficulty
##   tree      tree | dialogue | dialogue_tree | conversation
##   seed      seed | rng | variant
##   count     count | amount | number      (spawn N villagers from one marker)
##   quest     quest | quest_id             (this villager offers it by name)
## [/codeblock]
## Positions may be [Vector3], [Vector3i] or a 3-element [Array]; if omitted they
## default to the marker's own block, snapped to the ground.
class_name NpcSpawner
extends Node

const NPC_SCENE := "res://entities/npc/npc.tscn"

## Values that identify a payload as an NPC marker.
const MARKER_VALUES: Array[StringName] = [
	&"npc", &"villager", &"npc_spawn", &"villager_spawn", &"settler",
	&"inhabitant", &"citizen", &"townsfolk", &"spawn_npc",
]
const MARKER_KEYS: Array[String] = [
	"kind", "type", "marker", "tag", "entity", "spawn", "id", "class", "what",
]

## `job` is checked before `role` because worldgen writes the coarse role
## ("villager") in one and the useful specialisation ("smith") in the other.
const ROLE_KEYS: Array[String] = ["job", "role", "profession", "occupation", "class", "npc_role"]
const RACE_KEYS: Array[String] = ["race", "species", "ancestry"]
const NAME_KEYS: Array[String] = ["name", "npc_name", "display_name", "title"]
const VILLAGE_KEYS: Array[String] = ["village", "village_id", "settlement", "town", "camp"]
const WANDER_KEYS: Array[String] = ["wander", "wander_radius", "roam", "range"]
const HOME_KEYS: Array[String] = ["home", "home_pos", "anchor", "position"]
const WORK_KEYS: Array[String] = ["work", "work_pos", "workplace", "station", "job_pos"]
const BED_KEYS: Array[String] = ["bed", "bed_pos", "sleep", "sleep_pos"]
const SOCIAL_KEYS: Array[String] = ["social", "social_pos", "plaza", "gathering", "green"]
const TIER_KEYS: Array[String] = ["tier", "threat", "level", "difficulty"]
const TREE_KEYS: Array[String] = ["tree", "dialogue", "dialogue_tree", "conversation"]
const SEED_KEYS: Array[String] = ["seed", "rng", "variant"]
const COUNT_KEYS: Array[String] = ["count", "amount", "number"]
const QUEST_KEYS: Array[String] = ["quest", "quest_id"]
const ID_KEYS: Array[String] = ["npc_id", "unique_id", "uid"]

## Hard ceiling so a pathological structure cannot flood the scene tree.
const MAX_LIVE_NPCS := 48

## Structure-anchor payloads are informational, but they are also the only
## authority on "the player is standing in the Ancient Gateway". We collect them
## and fire `Quests.report(&"explore", struct_id)` on approach, which is what
## the campaign's landmark objectives listen for.
const ANCHOR_KIND := "structure_anchor"
const ANCHOR_RANGE := 18.0
const ANCHOR_CHECK_INTERVAL := 0.6

## "planet:x,y,z" -> true for markers already turned into a villager.
var _spawned: Dictionary = {}
var _trader: Node = null
## struct_id -> world position, for structures loaded around the player.
var _anchors: Dictionary = {}
var _entered: Dictionary = {}
var _anchor_t := 0.0


func _ready() -> void:
	name = "NpcSpawner"
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.world_unloaded.connect(_on_world_unloaded)
	Events.travel_finished.connect(_on_travel_finished)


func _process(delta: float) -> void:
	if _anchors.is_empty() or Game.paused:
		return
	_anchor_t -= delta
	if _anchor_t > 0.0:
		return
	_anchor_t = ANCHOR_CHECK_INTERVAL
	_check_anchors()


## Reports every structure the player has walked into since the last check.
func _check_anchors() -> void:
	var p := Game.player
	if p == null:
		return
	for key: Variant in _anchors:
		var id := str(key)
		if _entered.has(id):
			continue
		if p.global_position.distance_to(_anchors[key]) > ANCHOR_RANGE:
			continue
		_entered[id] = true
		Quests.report(&"explore", StringName(id), 1)


# =========================================================================
#  Chunk scanning
# =========================================================================
func _on_chunk_loaded(cpos: Vector3i) -> void:
	var chunk := World.get_chunk(cpos)
	if chunk == null or chunk.tile_data.is_empty():
		return
	scan_chunk(chunk)


## Public so worldgen can force a rescan after stamping a structure late.
func scan_chunk(chunk: Chunk) -> void:
	var origin := chunk.origin()
	var indices: Array = chunk.tile_data.keys()
	indices.sort()   # deterministic order within the chunk
	for i: Variant in indices:
		var payload := chunk.tile_data[i] as Dictionary
		if payload == null or payload.is_empty():
			continue
		var local := Chunk.from_index(int(i))
		if str(payload.get("kind", "")) == ANCHOR_KIND:
			_note_anchor(origin + local, payload)
			continue
		if not _is_npc_marker(payload):
			continue
		spawn_from_marker(origin + local, payload)


func _note_anchor(block_pos: Vector3i, payload: Dictionary) -> void:
	var id := str(payload.get("struct", payload.get("id", "")))
	if id == "":
		return
	var centre := Vector3(block_pos) + Vector3(0.5, 1.0, 0.5)
	var size: Variant = payload.get("size", null)
	if size is Array and (size as Array).size() >= 3:
		var s := size as Array
		centre += Vector3(float(s[0]) * 0.5, 0.0, float(s[2]) * 0.5)
	_anchors[id] = centre


func _on_chunk_unloaded(cpos: Vector3i) -> void:
	var lo := cpos * Const.CHUNK_SIZE
	var hi := lo + Vector3i(Const.CHUNK_SIZE, Const.CHUNK_SIZE, Const.CHUNK_SIZE)
	for n: Node in get_tree().get_nodes_in_group(&"npc"):
		var npc := n as NpcBase
		if npc == null or npc.is_crew or npc.in_conversation:
			continue
		var p := Const.floor_v(npc.global_position)
		if p.x < lo.x or p.x >= hi.x or p.y < lo.y or p.y >= hi.y or p.z < lo.z or p.z >= hi.z:
			continue
		if npc.has_meta(&"npc_marker_key"):
			_spawned.erase(str(npc.get_meta(&"npc_marker_key")))
		npc.queue_free()


func _on_world_unloaded() -> void:
	_spawned.clear()
	_anchors.clear()
	_entered.clear()


func _on_travel_finished(_planet_id: String) -> void:
	_spawned.clear()
	_anchors.clear()
	_entered.clear()
	NpcCrew.respawn_all()
	maybe_spawn_ship_trader()


# =========================================================================
#  Marker interpretation
# =========================================================================
static func _is_npc_marker(d: Dictionary) -> bool:
	for k: String in MARKER_KEYS:
		if not d.has(k):
			continue
		var v := StringName(str(d[k]).to_lower().strip_edges())
		if MARKER_VALUES.has(v):
			return true
		# A payload that names a role directly ("kind": "merchant") counts too,
		# but only when it also looks person-shaped rather than machine-shaped.
		if NpcRoles.exists(v) and (d.has("npc") or _has_any(d, ROLE_KEYS)
				or _has_any(d, RACE_KEYS) or _has_any(d, NAME_KEYS)):
			return true
	return d.has("npc") and bool(d["npc"])


static func _has_any(d: Dictionary, keys: Array[String]) -> bool:
	for k: String in keys:
		if d.has(k):
			return true
	return false


static func _first(d: Dictionary, keys: Array[String], fallback: Variant = null) -> Variant:
	for k: String in keys:
		if d.has(k):
			return d[k]
	return fallback


static func _first_string(d: Dictionary, keys: Array[String], fallback: String = "") -> String:
	var v: Variant = _first(d, keys, null)
	return str(v) if v != null else fallback


static func _first_vec(d: Dictionary, keys: Array[String], fallback: Vector3) -> Vector3:
	var v: Variant = _first(d, keys, null)
	if v == null:
		return fallback
	return NpcBase._to_vec(v, fallback)


# =========================================================================
#  Spawning
# =========================================================================
## Builds the villager described by [param payload] at block [param block_pos].
## Idempotent: a marker only ever produces one villager per world load.
func spawn_from_marker(block_pos: Vector3i, payload: Dictionary) -> Node:
	var key := _marker_key(block_pos)
	if _spawned.has(key):
		return null
	if get_tree().get_nodes_in_group(&"npc").size() >= MAX_LIVE_NPCS:
		return null
	_spawned[key] = true

	var count := clampi(int(_first(payload, COUNT_KEYS, 1)), 1, 6)
	var first: Node = null
	for i in count:
		var n := _spawn_one(block_pos, payload, i)
		if n != null:
			# Remembered so unloading the chunk can release the marker again.
			n.set_meta(&"npc_marker_key", key)
		if first == null:
			first = n
	return first


func _spawn_one(block_pos: Vector3i, payload: Dictionary, sub: int) -> Node:
	var world_seed := World.seed_value if World.seed_value != 0 else Game.run_seed
	var marker := block_pos + Vector3i(sub, 0, 0)
	var rng := NpcNames.rng_at(world_seed, marker, 17)

	# --- village -----------------------------------------------------------
	# worldgen writes `village_id` as a stable int; turn it into a name a
	# villager would actually say out loud.
	var village := _first_string(payload, VILLAGE_KEYS, "")
	if village == "" or village == "0":
		var vrng := NpcNames.rng_at(world_seed, Const.chunk_of(block_pos), 71)
		village = str(NpcNames.village_id(vrng))
	elif village.is_valid_int():
		var vrng2 := RandomNumberGenerator.new()
		vrng2.seed = world_seed ^ (village.to_int() * 2654435761)
		village = str(NpcNames.village_id(vrng2))
	var village_race := NpcNames.RACES[NpcNames.hash_at(world_seed,
		Const.chunk_of(block_pos), 313) % NpcNames.RACES.size()]

	# --- role --------------------------------------------------------------
	var tier := clampi(int(_first(payload, TIER_KEYS, _planet_tier())), 1, 10)
	# A payload may carry both ("role":"villager", "job":"smith"); take whichever
	# resolves to something more specific than the default.
	var role := ""
	for k: String in ROLE_KEYS:
		if not payload.has(k):
			continue
		var candidate := StringName(str(payload[k]).to_lower().strip_edges())
		if candidate == &"":
			continue
		var canon := NpcRoles.canonical(candidate)
		if canon != &"villager":
			role = str(canon)
			break
		if role == "":
			role = "villager"
	if role == "":
		# "kind": "blacksmith" is a role; "kind": "npc" is only a marker.
		var marker_val := StringName(_first_string(payload, MARKER_KEYS, "").to_lower())
		if NpcRoles.exists(marker_val) and not MARKER_VALUES.has(marker_val):
			role = str(marker_val)
	if role == "":
		var slot := NpcNames.hash_at(world_seed, marker, 4242) % NpcRoles.VILLAGE_COMPOSITION.size()
		role = str(NpcRoles.for_index(slot, tier, rng))
	role = str(NpcRoles.canonical(StringName(role)))

	# --- identity ----------------------------------------------------------
	var race := StringName(_first_string(payload, RACE_KEYS, ""))
	if race == &"" or not NpcNames.RACES.has(race):
		race = NpcNames.race_for(rng, village_race)
	var npc_name := _first_string(payload, NAME_KEYS, "")
	if npc_name == "":
		npc_name = NpcNames.full_name(rng, race)
	var id := StringName(_first_string(payload, ID_KEYS, ""))
	if id == &"":
		id = NpcNames.npc_id(world_seed, marker, race)

	# --- places ------------------------------------------------------------
	var ground := _ground_at(block_pos)
	var home := _first_vec(payload, HOME_KEYS, ground)
	var work := _first_vec(payload, WORK_KEYS, Vector3.INF)
	var bed := _first_vec(payload, BED_KEYS, Vector3.INF)
	var social := _first_vec(payload, SOCIAL_KEYS, Vector3.INF)
	if work == Vector3.INF:
		work = _offset_from(home, rng.randf_range(3.0, 9.0) * (1.0 if rng.randf() < 0.5 else -1.0))
	if bed == Vector3.INF:
		bed = home
	if social == Vector3.INF:
		social = _offset_from(home, rng.randf_range(-6.0, 6.0))

	var setup := {
		"npc_id": str(id),
		"name": npc_name,
		"race": str(race),
		"role": role,
		"village": village,
		"seed": int(_first(payload, SEED_KEYS, NpcNames.hash_at(world_seed, marker, 5) % 2147483647)),
		"skill": str(NpcNames.crew_skill(rng)),
		"home": [home.x, home.y, home.z],
		"work": [work.x, work.y, work.z],
		"bed": [bed.x, bed.y, bed.z],
		"social": [social.x, social.y, social.z],
		"wander_radius": float(_first(payload, WANDER_KEYS, rng.randf_range(6.0, 13.0))),
	}
	var tree := _first_string(payload, TREE_KEYS, "")
	if tree != "":
		setup["tree"] = tree

	var npc := Game.spawn_entity(NPC_SCENE, ground, setup)
	if npc == null:
		return null
	var authored := _first_string(payload, QUEST_KEYS, "")
	if authored != "" and Quests.has_def(authored):
		var qd := Quests.get_def(authored)
		qd.from_npc(id, npc_name)
	return npc


## Rebuilds a crew member (or any NPC) from a saved descriptor.
static func spawn_from_descriptor(d: Dictionary, at: Vector3) -> Node:
	var setup := d.duplicate(true)
	setup.erase("state")
	var npc := Game.spawn_entity(NPC_SCENE, VoxelPhysics.unstick(at, Vector3(0.62, 1.8, 0.62)), setup)
	if npc != null and d.has("state") and npc.has_method(&"load_state"):
		npc.call(&"load_state", d["state"])
	return npc


## Places one named NPC, used by campaign scripting.
static func spawn_named(npc_id: StringName, npc_name: String, role: StringName,
		race: StringName, at: Vector3, tree: String = "") -> Node:
	var setup := {
		"npc_id": str(npc_id), "name": npc_name, "role": str(role),
		"race": str(race), "seed": int(hash(npc_id) & 0x7FFFFFFF),
		"home": [at.x, at.y, at.z],
	}
	if tree != "":
		setup["tree"] = tree
	return Game.spawn_entity(NPC_SCENE, at, setup)


# =========================================================================
#  The wandering trader
# =========================================================================
## Rolls for the trader after a jump. He materialises next to the player, which
## on the ship is the deck and on a planet is close enough.
func maybe_spawn_ship_trader() -> Node:
	if _trader != null and is_instance_valid(_trader):
		return _trader
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.run_seed ^ (Game.day * 7717) ^ hash(World.planet_id)
	if rng.randf() > NpcRoleTrader.VISIT_CHANCE:
		return null
	return spawn_ship_trader(Vector3.INF)


## Forces the trader in. Pass [constant Vector3.INF] to place him by the player.
func spawn_ship_trader(at: Vector3) -> Node:
	var p := Game.player
	var pos := at
	if pos == Vector3.INF:
		if p == null:
			return null
		pos = p.global_position + View.plane_dir_to_world(Vector2(3.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.run_seed ^ 990099
	var race := NpcNames.RACES[rng.randi_range(0, NpcNames.RACES.size() - 1)]
	_trader = spawn_named(&"wandering_trader", NpcNames.full_name(rng, race),
		&"trader", race, VoxelPhysics.unstick(pos, Vector3(0.62, 1.8, 0.62)), "trader_default")
	if _trader != null:
		Events.toast("A trader has docked.", "info")
		if _trader.has_method(&"say"):
			_trader.call(&"say", "Don't mind me. Doors were open.", 4.0)
	return _trader


# =========================================================================
#  Helpers
# =========================================================================
func _planet_tier() -> int:
	var meta: Dictionary = Universe.planet_meta(World.planet_id)
	return clampi(int(meta.get("threat", 1)), 1, 10)


static func _marker_key(p: Vector3i) -> String:
	return "%s:%d,%d,%d" % [World.planet_id, p.x, p.y, p.z]


## Snaps a marker block onto the first solid surface at or below it.
static func _ground_at(block_pos: Vector3i) -> Vector3:
	var x := World.wrap_x(block_pos.x)
	var z := World.wrap_z(block_pos.z)
	for dy in range(0, 24):
		var probe := Vector3i(x, block_pos.y - dy, z)
		if not World.in_bounds_y(probe.y):
			break
		if World.is_solid(probe):
			return Vector3(float(x) + 0.5, float(probe.y + 1), float(z) + 0.5)
	var s := World.surface_y(x, z)
	if s > 0:
		return Vector3(float(x) + 0.5, float(s + 1), float(z) + 0.5)
	return Vector3(float(x) + 0.5, float(block_pos.y), float(z) + 0.5)


## A point [param lateral] metres away in the *current* plane, on the ground.
static func _offset_from(base: Vector3, lateral: float) -> Vector3:
	var p: Vector3 = base + View.plane_dir_to_world(Vector2(lateral, 0.0))
	return _ground_at(Const.floor_v(p) + Vector3i(0, 3, 0))
