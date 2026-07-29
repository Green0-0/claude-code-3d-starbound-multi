## THE TILE-DATA CONTRACT for everything worldgen/structures/ emits.
##
## Structures never spawn nodes. They write a Dictionary payload into
## `chunk.set_tile_data(local_index, payload)` and the owning gameplay module
## picks it up lazily (on chunk load, on first interaction, on first open).
## Every payload has a `"kind"` string; read that first and ignore kinds you do
## not own. Unknown extra keys must be tolerated — they will grow.
##
## Consumers, by kind:
##   container / crate        -> objects + inventory agents
##   spawner / boss_spawn     -> entities agent
##   npc_spawn                -> entities (NPC) agent
##   teleporter               -> space agent
##   door / lever / lock      -> objects agent
##   trap                     -> combat / objects agents
##   light                    -> objects + lighting agents
##   sign                     -> objects / ui agents
##   structure_anchor         -> quests, star map, minimap (informational)
##
## ---------------------------------------------------------------------------
## SCHEMAS (exact key names; all coordinates are absolute world Vector3i encoded
## as a 3-element Array[int] so the payload survives `var_to_bytes` round-trips)
## ---------------------------------------------------------------------------
##
## container
##   {"kind":"container", "loot_table":String, "tier":int, "theme":String,
##    "capacity":int, "seed":int, "struct":String, "opened":false,
##    "locked":bool, "key":String, "guaranteed":[String]  (optional)}
##   Contents are NOT pre-rolled. Call `StructLoot.roll_payload(payload)` on
##   first open — it rolls the table and prepends any "guaranteed" item ids
##   (quest keys, plot relics) — then set "opened" = true so it never rerolls.
##   "guaranteed" is absent on most containers; treat a missing key as [].
##
## spawner
##   {"kind":"spawner", "pool":String, "tier":int, "count":int, "max_alive":int,
##    "radius":float, "trigger":"proximity"|"always", "once":bool,
##    "theme":String, "seed":int}
##   `pool` is a monster-pool key ("floran_hunter", "cave_crawler", ...); the
##   entities agent maps pool -> concrete monster scenes.
##
## boss_spawn
##   {"kind":"boss_spawn", "boss":String, "tier":int, "arena_min":[x,y,z],
##    "arena_max":[x,y,z], "reward_table":String, "seed":int}
##
## npc_spawn
##   {"kind":"npc_spawn", "role":String, "species":String, "job":String,
##    "faction":String, "home":[x,y,z], "work":[x,y,z]|null, "wander":float,
##    "village_id":int, "dialogue":String, "shop":String, "seed":int}
##   role: "villager"|"merchant"|"guard"|"questgiver"|"hermit"|"prisoner"|"boss_npc"
##   species is the theme name ("apex", "avian", "floran", "glitch",
##   "hylotl", "human", "ancient").
##
## teleporter
##   {"kind":"teleporter", "network":String, "gate_id":int, "target":[x,y,z]|null,
##    "target_planet":String, "requires_key":String, "active":bool, "two_way":bool}
##
## door
##   {"kind":"door", "door_type":String, "axis":"x"|"z", "locked":bool,
##    "key":String, "lock_id":int, "width":int, "height":int}
##   `axis` is the world axis the door *slides/faces along* — a door on axis "x"
##   is walkable in views 0/2. Perspective-locked doors set only one axis.
##
## lever  (also used for vault wheels, rune switches, valve handles)
##   {"kind":"lever", "lock_id":int, "puzzle":String, "state":false,
##    "controls":[[x,y,z], ...], "hint":String}
##   Flipping it must set every voxel listed in "controls" to air (or toggle a
##   door with the matching lock_id).
##
## trap
##   {"kind":"trap", "trap":String, "tier":int, "armed":true, "damage":float,
##    "element":String, "radius":float}
##   trap: "dart"|"spike"|"flame"|"collapse"|"gas"|"shock"|"alarm"
##
## light
##   {"kind":"light", "fixture":String, "level":int, "color":[r,g,b]}
##
## sign
##   {"kind":"sign", "text":String, "lore":String}
##
## structure_anchor
##   {"kind":"structure_anchor", "struct":String, "theme":String, "tier":int,
##    "size":[dx,dy,dz], "origin":[x,y,z], "seed":int, "name":String}
##   One per structure, written at its origin voxel. Safe to ignore.
class_name StructMarkers
extends RefCounted


static func _v(p: Vector3i) -> Array:
	return [p.x, p.y, p.z]


## Chest / crate / locker. Contents roll lazily — see `StructLoot`.
static func container(table: String, tier: int, theme: StringName, seed_value: int,
		struct_id: String = "", capacity: int = 16, locked: bool = false,
		key: String = "") -> Dictionary:
	return {
		"kind": "container", "loot_table": table, "tier": tier,
		"theme": String(theme), "capacity": capacity, "seed": seed_value,
		"struct": struct_id, "opened": false, "locked": locked, "key": key,
	}


## Monster spawner. `pool` is a logical monster group, not a scene path.
static func spawner(pool: String, tier: int, count: int = 3, radius: float = 6.0,
		theme: StringName = &"natural", seed_value: int = 0, once: bool = false,
		trigger: String = "proximity") -> Dictionary:
	return {
		"kind": "spawner", "pool": pool, "tier": tier, "count": count,
		"max_alive": count, "radius": radius, "trigger": trigger,
		"once": once, "theme": String(theme), "seed": seed_value,
	}


static func boss_spawn(boss: String, tier: int, arena_min: Vector3i, arena_max: Vector3i,
		reward_table: String = "boss", seed_value: int = 0) -> Dictionary:
	return {
		"kind": "boss_spawn", "boss": boss, "tier": tier,
		"arena_min": _v(arena_min), "arena_max": _v(arena_max),
		"reward_table": reward_table, "seed": seed_value,
	}


## Villager / merchant / guard / hermit spawn point.
static func npc(role: String, species: StringName, home: Vector3i, job: String = "",
		village_id: int = 0, wander: float = 8.0, seed_value: int = 0,
		shop: String = "", dialogue: String = "") -> Dictionary:
	return {
		"kind": "npc_spawn", "role": role, "species": String(species), "job": job,
		"faction": "village" if village_id != 0 else String(species),
		"home": _v(home), "work": null, "wander": wander,
		"village_id": village_id, "dialogue": dialogue, "shop": shop,
		"seed": seed_value,
	}


static func teleporter(network: String, gate_id: int, requires_key: String = "",
		active: bool = true, target_planet: String = "") -> Dictionary:
	return {
		"kind": "teleporter", "network": network, "gate_id": gate_id,
		"target": null, "target_planet": target_planet,
		"requires_key": requires_key, "active": active, "two_way": true,
	}


static func door(door_type: String, axis: String, locked: bool = false,
		key: String = "", lock_id: int = 0, width: int = 1, height: int = 2) -> Dictionary:
	return {
		"kind": "door", "door_type": door_type, "axis": axis, "locked": locked,
		"key": key, "lock_id": lock_id, "width": width, "height": height,
	}


static func lever(lock_id: int, puzzle: String, controls: Array = [], hint: String = "") -> Dictionary:
	var enc: Array = []
	for p: Vector3i in controls:
		enc.append(_v(p))
	return {
		"kind": "lever", "lock_id": lock_id, "puzzle": puzzle, "state": false,
		"controls": enc, "hint": hint,
	}


static func trap(kind: String, tier: int, damage: float = 8.0,
		element: String = Const.ELEM_PHYSICAL, radius: float = 1.5) -> Dictionary:
	return {
		"kind": "trap", "trap": kind, "tier": tier, "armed": true,
		"damage": damage, "element": element, "radius": radius,
	}


static func light(fixture: String, level: int = 12, color: Color = Color(1.0, 0.86, 0.6)) -> Dictionary:
	return {"kind": "light", "fixture": fixture, "level": level,
			"color": [color.r, color.g, color.b]}


static func sign(text: String, lore: String = "") -> Dictionary:
	return {"kind": "sign", "text": text, "lore": lore}


static func anchor(struct_id: String, theme: StringName, tier: int, origin: Vector3i,
		size: Vector3i, seed_value: int, display: String = "") -> Dictionary:
	return {
		"kind": "structure_anchor", "struct": struct_id, "theme": String(theme),
		"tier": tier, "size": _v(size), "origin": _v(origin), "seed": seed_value,
		"name": display if display != "" else struct_id.capitalize(),
	}
