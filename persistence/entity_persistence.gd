## Decides what survives a save, and where it is stored.
##
## The rule
## --------
## | thing | persists | stored in |
## |---|---|---|
## | NPCs, pets, tamed creatures | yes | per-planet entity list, keyed by chunk |
## | placed objects, machines, doors | yes | `Chunk.tile_data` (rides the chunk) |
## | containers and their contents | yes | `Chunk.tile_data` |
## | monsters | **no** | respawned by the spawner |
## | item drops, projectiles, fx | **no** | gone on unload, by design |
##
## Anything voxel-anchored belongs in `Chunk.tile_data`, because that is already
## carried by the region file for free and cannot desynchronise from the block
## it belongs to. Anything free-roaming (an NPC wandering a village) belongs in
## the per-planet entity list, bucketed by the chunk it was standing in, so it
## reappears where you left it when that chunk streams back in.
##
## Volatile entities are deliberately *not* saved: respawning a monster is
## cheaper, smaller on disk, and better gameplay than resurrecting one mid-swing.
class_name SavEntityPersistence
extends RefCounted

## Membership in any of these groups means "write me down".
const PERSIST_GROUPS: Array[StringName] = [
	&"npcs", &"npc", &"pets", &"pet", &"objects", &"containers", &"persistent",
]
## Membership in any of these means "never write me down".
const VOLATILE_GROUPS: Array[StringName] = [
	&"monsters", &"monster", &"drops", &"item_drops", &"projectiles",
	&"particles", &"temporary", &"volatile",
]
## These outrank volatility. A tamed creature is added to `pets` while staying
## in `monsters` (see `entities/monsters/monster.gd`) — the taming is exactly the
## thing the player expects to survive a save, so the opt-in has to win.
const OVERRIDE_GROUPS: Array[StringName] = [&"persistent", &"pets", &"pet"]
## Factions whose entities respawn rather than persist.
const VOLATILE_FACTIONS: Array[StringName] = [&"hostile", &"wild"]

## planet_id -> { "cx,cy,cz" -> Array[Dictionary] }
var by_planet: Dictionary = {}
## Chunks whose NPCs are currently alive in the scene, so we do not double-spawn.
var _spawned: Dictionary = {}
var _dirty_planets: Dictionary = {}


# =============================================================== classification
## Should this node be written to disk?
static func should_persist(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node == Game.player:
		return false          ## the player has its own save section
	var e := node as VoxelEntity
	if e != null and e.dead:
		return false

	for g: StringName in OVERRIDE_GROUPS:
		if node.is_in_group(g):
			return true       ## opt-in beats both the volatile list and faction

	for g: StringName in VOLATILE_GROUPS:
		if node.is_in_group(g):
			return false
	var explicit := false
	for g: StringName in PERSIST_GROUPS:
		if node.is_in_group(g):
			explicit = true
			break
	if not explicit:
		return false
	if e != null and VOLATILE_FACTIONS.has(e.faction):
		return false
	return true


## True for the entities that must be thrown away on unload.
static func is_volatile(node: Node) -> bool:
	if node == null:
		return true
	for g: StringName in OVERRIDE_GROUPS:
		if node.is_in_group(g):
			return false
	for g: StringName in VOLATILE_GROUPS:
		if node.is_in_group(g):
			return true
	return false


# ================================================================== capture
## Serialise one node into a restorable record. Returns `{}` if it declines.
static func capture(node: Node) -> Dictionary:
	if not should_persist(node):
		return {}
	var script_path := ""
	var scr: Variant = node.get_script()
	if scr is Script:
		script_path = (scr as Script).resource_path
	var rec := {
		"scene": node.scene_file_path,
		"script": script_path,
		"name": String(node.name),
		"groups": [],
	}
	for g: StringName in PERSIST_GROUPS:
		if node.is_in_group(g):
			(rec["groups"] as Array).append(String(g))
	if node is Node3D:
		var p: Vector3 = (node as Node3D).global_position
		rec["pos"] = [p.x, p.y, p.z]
	if node.has_method(&"save_state"):
		var st: Variant = node.call(&"save_state")
		if st is Dictionary:
			rec["state"] = st
	# Containers keep their inventory in a sibling object; ask nicely.
	var inv: Variant = node.get(&"inventory")
	if inv != null and inv is Object and (inv as Object).has_method(&"to_dict"):
		rec["inventory"] = (inv as Object).call(&"to_dict")
	if rec.get("scene", "") == "" and rec.get("script", "") == "":
		return {}      ## nothing we could rebuild it from
	return rec


## Rebuild a node from a record. Returns null when the scene no longer exists
## (an entity type removed between builds must not break the load).
static func restore(rec: Dictionary) -> Node:
	var scene := String(rec.get("scene", ""))
	var pos := Vector3.ZERO
	var pa: Array = rec.get("pos", [])
	if pa.size() == 3:
		pos = Vector3(pa[0], pa[1], pa[2])
	var node: Node = null
	if scene != "" and ResourceLoader.exists(scene):
		node = Game.spawn_entity(scene, pos)
	elif String(rec.get("script", "")) != "":
		var sp := String(rec["script"])
		if ResourceLoader.exists(sp):
			var scr := load(sp)
			var obj: Variant = scr.new() if scr != null else null
			if obj is Node:
				node = obj as Node
				if node is Node3D:
					(node as Node3D).global_position = pos
				var parent: Node = Game.entities_root if Game.entities_root != null else Game.main
				if parent != null:
					parent.add_child(node)
	if node == null:
		return null
	for g: Variant in (rec.get("groups", []) as Array):
		var gn := StringName(str(g))
		if not node.is_in_group(gn):
			node.add_to_group(gn)
	if rec.has("state") and node.has_method(&"load_state"):
		node.call(&"load_state", rec["state"])
	if rec.has("inventory"):
		var inv: Variant = node.get(&"inventory")
		if inv != null and inv is Object and (inv as Object).has_method(&"from_dict"):
			(inv as Object).call(&"from_dict", rec["inventory"])
	return node


# ======================================================== per-planet registries
static func chunk_key(cpos: Vector3i) -> String:
	return "%d,%d,%d" % [cpos.x, cpos.y, cpos.z]


static func chunk_of_world(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x) >> 4, floori(p.y) >> 4, floori(p.z) >> 4)


func planet_bucket(planet_id: String) -> Dictionary:
	if not by_planet.has(planet_id):
		by_planet[planet_id] = {}
	return by_planet[planet_id]


## Groups scanned when harvesting a chunk. Kept as one list so the per-eviction
## early-out below only has to ask the SceneTree for counts.
const SCAN_GROUPS: Array[StringName] = [&"npcs", &"npc", &"pets", &"pet", &"persistent"]


## Harvest every persistent entity currently standing in `cpos` and file it
## under that chunk, then free the nodes. Called as the chunk streams out, which
## happens dozens of times a second — so it bails out before allocating anything
## when no persistent entity exists at all.
func capture_chunk(planet_id: String, cpos: Vector3i) -> int:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return 0
	var tree := loop as SceneTree
	var any := false
	for g: StringName in SCAN_GROUPS:
		if tree.get_node_count_in_group(g) > 0:
			any = true
			break
	if not any:
		return 0
	var key := chunk_key(cpos)
	var records: Array = []
	for g: StringName in SCAN_GROUPS:
		for n: Node in tree.get_nodes_in_group(g):
			if not (n is Node3D):
				continue
			if chunk_of_world((n as Node3D).global_position) != cpos:
				continue
			var rec := capture(n)
			if rec.is_empty():
				continue
			if records.has(rec):
				continue
			records.append(rec)
			n.queue_free()
	var bucket := planet_bucket(planet_id)
	if records.is_empty():
		if bucket.has(key):
			bucket.erase(key)
			_dirty_planets[planet_id] = true
	else:
		bucket[key] = records
		_dirty_planets[planet_id] = true
	_spawned.erase("%s|%s" % [planet_id, key])
	return records.size()


## Re-instantiate the entities filed under `cpos`. Idempotent.
func respawn_chunk(planet_id: String, cpos: Vector3i) -> int:
	var key := chunk_key(cpos)
	var guard := "%s|%s" % [planet_id, key]
	if _spawned.has(guard):
		return 0
	var bucket: Dictionary = by_planet.get(planet_id, {})
	var records: Array = bucket.get(key, [])
	if records.is_empty():
		return 0
	_spawned[guard] = true
	var n := 0
	for rec: Variant in records:
		if rec is Dictionary and restore(rec) != null:
			n += 1
	return n


## Sweep the whole scene into the registry. Used before a full save and before
## leaving a planet, where chunk-by-chunk capture would miss entities that are
## still loaded.
func capture_all(planet_id: String) -> int:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return 0
	var tree := loop as SceneTree
	var bucket := planet_bucket(planet_id)
	var fresh: Dictionary = {}
	var seen: Dictionary = {}
	for g: StringName in SCAN_GROUPS:
		for n: Node in tree.get_nodes_in_group(g):
			if seen.has(n.get_instance_id()):
				continue
			seen[n.get_instance_id()] = true
			if not (n is Node3D):
				continue
			var rec := capture(n)
			if rec.is_empty():
				continue
			var key := chunk_key(chunk_of_world((n as Node3D).global_position))
			if not fresh.has(key):
				fresh[key] = []
			(fresh[key] as Array).append(rec)
	# Keep buckets for chunks that are not loaded right now; replace the rest.
	for key: String in fresh:
		bucket[key] = fresh[key]
	_dirty_planets[planet_id] = true
	return seen.size()


## Forget a planet's entity list entirely (new game / slot switch).
func clear_planet(planet_id: String) -> void:
	by_planet.erase(planet_id)
	for k: String in _spawned.keys():
		if k.begins_with(planet_id + "|"):
			_spawned.erase(k)


func clear_all() -> void:
	by_planet.clear()
	_spawned.clear()
	_dirty_planets.clear()


func mark_chunk_unspawned(planet_id: String, cpos: Vector3i) -> void:
	_spawned.erase("%s|%s" % [planet_id, chunk_key(cpos)])


func is_planet_dirty(planet_id: String) -> bool:
	return _dirty_planets.has(planet_id)


func clear_planet_dirty(planet_id: String) -> void:
	_dirty_planets.erase(planet_id)


func entity_count(planet_id: String = "") -> int:
	var n := 0
	for pid: String in by_planet:
		if planet_id != "" and pid != planet_id:
			continue
		for key: String in (by_planet[pid] as Dictionary):
			n += (by_planet[pid][key] as Array).size()
	return n


# ================================================================ disk sections
## The per-planet entity file body.
func planet_to_dict(planet_id: String) -> Dictionary:
	return {"planet": planet_id, "chunks": by_planet.get(planet_id, {}).duplicate(true)}


func planet_from_dict(planet_id: String, d: Dictionary) -> void:
	by_planet[planet_id] = d.get("chunks", {})


## The `entities` section of the top-level save: every planet at once. Small,
## because only named NPCs and pets ever land in here.
func to_dict() -> Dictionary:
	return {"by_planet": by_planet.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	by_planet = d.get("by_planet", {})
	_spawned.clear()


# =============================================================== tile-data API
## Placed objects, machines and containers store their state in the chunk they
## occupy, so it travels with the region file automatically. These helpers do
## the index maths *and* mark the chunk modified — a tile-data write does not
## emit `block_changed`, so without this call the save layer would legitimately
## conclude the chunk still matches the generator and discard it.
static func set_object_data(world_pos: Vector3i, data: Dictionary) -> bool:
	var c := World.chunk_at_block(world_pos)
	if c == null:
		return false
	var n := World.normalize(world_pos)
	c.set_tile_data(Chunk.index(n.x & 15, n.y & 15, n.z & 15), data)
	SaveManager.mark_chunk_modified(World.planet_id, c.cpos)
	return true


static func get_object_data(world_pos: Vector3i) -> Dictionary:
	var c := World.chunk_at_block(world_pos)
	if c == null:
		return {}
	var n := World.normalize(world_pos)
	return c.get_tile_data(Chunk.index(n.x & 15, n.y & 15, n.z & 15))


static func clear_object_data(world_pos: Vector3i) -> bool:
	return set_object_data(world_pos, {})


## Merge a few keys into an existing tile-data payload without clobbering the
## rest — the common case for "chest contents changed" or "machine ticked".
static func patch_object_data(world_pos: Vector3i, patch: Dictionary) -> bool:
	var d := get_object_data(world_pos)
	var merged := d.duplicate()
	for k: Variant in patch:
		merged[k] = patch[k]
	return set_object_data(world_pos, merged)


## Every tile-data entry in the loaded world, as `{world_pos: data}`. Used for
## the save file's placed-object registry and by the debug overlay.
static func scan_loaded_objects() -> Dictionary:
	var out := {}
	if not World.ready_flag:
		return out
	for cp: Vector3i in World.chunks:
		var c: Chunk = World.chunks[cp]
		if c == null or c.tile_data.is_empty():
			continue
		var o := c.origin()
		for i: Variant in c.tile_data:
			var li := int(i)
			var l := Chunk.from_index(li)
			out["%d,%d,%d" % [o.x + l.x, o.y + l.y, o.z + l.z]] = c.tile_data[i]
	return out
