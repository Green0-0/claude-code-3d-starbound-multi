## The spawn director. Attached to the `Entities` node in `main.tscn`, so it is
## both `Game.entities_root` (the parent of every spawned actor) and the thing
## that decides what exists at all.
##
## Rules it enforces:
##   * a population budget derived from biome, planet threat, time of day and
##     light level — dark caves at night are busy, a lit garden at noon is not;
##   * monsters only appear **outside the camera's slice** but inside the
##     streamed slab, at a depth layer near (not necessarily equal to) the
##     player's, so the world feels populated in the layers behind you;
##   * everything far away is deleted and nothing is persisted — creatures
##     respawn, they do not travel;
##   * `Events.chunk_loaded` / `chunk_unloaded` / `layer_changed` are respected;
##   * `chunk.tile_data` entries tagged as spawners (placed by the structures
##     agent) become managed spawn points with their own budgets.
class_name MobEntityManager
extends Node3D

const TICK_INTERVAL := 0.5
## Half-extent of the region the camera can actually see, in blocks.
const VIEW_HALF_LATERAL := 24.0
const VIEW_HALF_VERTICAL := 15.0
## Ring the director spawns into: outside the view, inside the streamed slab.
const SPAWN_MIN := 27.0
const SPAWN_MAX := 50.0
const SPAWN_LAYER_SPREAD := 3
const DESPAWN_PLANE := 96.0
const DESPAWN_LAYERS := 9
const SPAWN_ATTEMPTS := 6

## Sound ids loud enough for a monster to investigate.
const LOUD_SOUNDS: Array[String] = [
	"explosion", "block_break", "boss_slam", "boss_quake", "gunshot",
	"monster_alert", "howl", "eruption", "break_stone", "break_wood",
]

var enabled := true
var debug_spawns := false

var _mobs: Array[MobBase] = []
## Vector3i chunk -> Array of spawner records.
var _spawners: Dictionary = {}
var _tick := 0.0
var _rng := RandomNumberGenerator.new()
var _spawn_fail_streak := 0


func _ready() -> void:
	Game.entities_root = self
	_rng.randomize()
	MobSpeciesDB.ensure_loaded()
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.layer_changed.connect(_on_layer_changed)
	Events.world_unloaded.connect(_on_world_unloaded)
	Events.block_changed.connect(_on_block_changed)
	Events.play_sound.connect(_on_play_sound)
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	# Hand the pathfinder its per-frame search budget before any monster ticks.
	MobPath.begin_frame()
	if Game.paused or not World.ready_flag or not enabled:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_INTERVAL
	_prune()
	_despawn_far()
	_tick_spawners(TICK_INTERVAL)
	_ambient_spawn()


# =============================================================== population
## Live monsters this manager is tracking (excluding pets and bosses).
func mob_count() -> int:
	var n := 0
	for m in _mobs:
		if m != null and not m.dead and m.faction == &"hostile":
			n += 1
	return n


func total_count() -> int:
	return _mobs.size()


## How many hostiles this planet, biome and hour of day should support.
func population_cap() -> int:
	var threat := _planet_threat()
	var cap := 12 + threat * 3
	if Game.is_night():
		cap = int(float(cap) * 1.45)
	match Game.difficulty:
		0: cap = int(float(cap) * 0.7)
		2: cap = int(float(cap) * 1.3)
	if _player_underground():
		cap += 4
	return clampi(cap, 4, 40)


func _planet_threat() -> int:
	var meta: Dictionary = World.planet
	return int(meta.get("threat", meta.get("threat_level", 1)))


func _player_underground() -> bool:
	var p := Game.player
	if p == null:
		return false
	var b := Const.floor_v(p.global_position)
	var surface := World.surface_y(b.x, b.z, Const.WORLD_HEIGHT - 1)
	return surface > b.y + 4


func _light_at(p: Vector3i) -> int:
	if Lighting.has_method(&"level_at"):
		return int(Lighting.call(&"level_at", p))
	if Lighting.has_method(&"light_at"):
		return int(Lighting.call(&"light_at", p))
	var c := World.chunk_at_block(p)
	if c == null:
		return 15
	var n := World.normalize(p)
	return c.combined_light(Chunk.index(n.x & 15, n.y & 15, n.z & 15), Game.daylight)


func _biome_at(p: Vector3i) -> StringName:
	if PlanetGen.has_method(&"biome_at"):
		return PlanetGen.call(&"biome_at", p.x, p.z)
	return &"forest"


# ================================================================== spawning
## Create one monster. This is the entry point every other module uses.
##
## `opts` (all optional): threat, scale, faction, no_loot, generation, variant,
## level, brain, escort, persistent, patrol.
func spawn_species(id: StringName, pos: Vector3, opts: Dictionary = {}) -> MobBase:
	if not MobSpeciesDB.has(id):
		push_warning("[Mobs] spawn of unknown species '%s'" % id)
		return null
	if MobBoss.is_boss(id):
		return spawn_boss(id, pos, opts)
	var o := opts.duplicate()
	if not o.has("threat"):
		o["threat"] = _planet_threat()
	var m := MobBase.new()
	m.name = "Mob_%s_%d" % [id, _mobs.size()]
	# Position and species go in before the node enters the tree so `_ready`
	# records the right home point and depth layer first time.
	m.position = _snap_to_layer_centre(pos)
	m.species_id = id
	m.spawn_opts = o
	add_child(m)
	m.teleport(VoxelPhysics.unstick(m.global_position, m.box_size))
	if bool(o.get("persistent", false)):
		m.add_to_group(&"persistent")
	_mobs.append(m)
	return m


## Spawn a group. Pack members are spread laterally and share a wake-up.
func spawn_pack(id: StringName, pos: Vector3, count: int = -1, opts: Dictionary = {}) -> Array:
	var sp := MobSpeciesDB.get_species(id)
	if sp == null:
		return []
	var n: int = count if count > 0 else _rng.randi_range(sp.pack_min, sp.pack_max)
	var out: Array = []
	for i in n:
		var lat := float(i - n / 2) * 1.8 + _rng.randf_range(-0.6, 0.6)
		var r := View.right()
		var p := pos + Vector3(float(r.x), 0.0, float(r.z)) * lat
		var m := spawn_species(id, p, opts)
		if m != null:
			out.append(m)
	return out


## Bosses get their own subclass and never despawn.
func spawn_boss(id: StringName, pos: Vector3, opts: Dictionary = {}) -> MobBoss:
	var b := MobBoss.make(id)
	if b == null:
		return null
	var o := opts.duplicate()
	if not o.has("threat"):
		o["threat"] = _planet_threat()
	b.name = "Boss_%s" % id
	b.position = _snap_to_layer_centre(pos)
	b.spawn_opts = o
	add_child(b)
	b.teleport(VoxelPhysics.unstick(b.global_position, b.box_size))
	# The arena is wherever it woke up, not wherever the node briefly sat.
	b.arena_centre = b.global_position
	b.arena_layer = b.depth_layer()
	_mobs.append(b)
	Events.toast("A boss stirs nearby.", "danger")
	return b


func _snap_to_layer_centre(pos: Vector3) -> Vector3:
	var out := pos
	if View.depth_axis() == 0:
		out.x = floorf(pos.x) + 0.5
	else:
		out.z = floorf(pos.z) + 0.5
	return out


# ========================================================== ambient spawning
func _ambient_spawn() -> void:
	var player := Game.player
	if player == null or player.dead:
		return
	var cap := population_cap()
	if mob_count() >= cap or _mobs.size() >= cap + 14:
		return
	for _attempt in SPAWN_ATTEMPTS:
		var site := _find_spawn_site(player)
		if site.is_empty():
			continue
		var sp: MobSpecies = MobSpeciesDB.pick(site["ctx"], _rng)
		if sp == null:
			continue
		if not _site_suits(sp, site):
			continue
		var pos: Vector3 = site["pos"]
		if sp.pack_max > 1:
			spawn_pack(sp.id, pos)
		else:
			spawn_species(sp.id, pos)
		_spawn_fail_streak = 0
		if debug_spawns:
			print("[Mobs] spawned %s at %v (%s)" % [sp.id, pos, site["ctx"]["biome"]])
		return
	_spawn_fail_streak += 1


## Pick a legal, unseen point in the streamed slab. Returns {} on failure.
func _find_spawn_site(player: Node3D) -> Dictionary:
	var lateral_sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var lateral := lateral_sign * _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var r := View.right()
	var base := player.global_position + Vector3(float(r.x), 0.0, float(r.z)) * lateral
	var layer := View.layer + _rng.randi_range(-SPAWN_LAYER_SPREAD, SPAWN_LAYER_SPREAD)
	if View.depth_axis() == 0:
		base.x = float(layer) + 0.5
	else:
		base.z = float(layer) + 0.5

	var underground := _player_underground() and _rng.randf() < 0.75
	var col := Const.floor_v(base)
	var y := -1
	if underground:
		y = _find_cave_pocket(col, floori(player.global_position.y))
	else:
		var surface := World.surface_y(col.x, col.z, mini(Const.WORLD_HEIGHT - 1,
			floori(player.global_position.y) + 30))
		if surface >= 0:
			y = surface + 1
	if y < 1:
		return {}
	var pos := Vector3(base.x, float(y), base.z)
	if not World.has_chunk(Const.chunk_of(Const.floor_v(pos))):
		return {}
	if _in_camera_slice(pos, player):
		return {}
	if absf(pos.y - player.global_position.y) > 40.0:
		return {}

	var block := Const.floor_v(pos)
	var ctx := {
		"biome": _biome_at(block),
		"threat": _planet_threat(),
		"night": Game.is_night(),
		"light": _light_at(block),
		"underwater": Blocks.is_liquid(World.get_block(block)),
		"underground": underground,
		"hostile_only": false,
	}
	return {"pos": pos, "ctx": ctx, "underground": underground}


func _find_cave_pocket(col: Vector3i, around_y: int) -> int:
	for _i in 8:
		var y := around_y + _rng.randi_range(-14, 14)
		if y < 2 or y >= Const.WORLD_HEIGHT - 2:
			continue
		var p := Vector3i(col.x, y, col.z)
		if World.is_air(p) and World.is_air(p + Vector3i(0, 1, 0)) \
				and World.is_solid(p - Vector3i(0, 1, 0)):
			return y
	return -1


## Is this point inside the slice of world the orthographic camera renders?
func _in_camera_slice(pos: Vector3, player: Node3D) -> bool:
	var lat: float = absf(Const.lateral_of(pos - player.global_position, View.view))
	var dy: float = absf(pos.y - player.global_position.y)
	if lat > VIEW_HALF_LATERAL or dy > VIEW_HALF_VERTICAL:
		return false
	# Layers in front of the play plane are dissolved, so they are not "seen".
	var offset := (floori(Const.depth_of(pos, View.view)) - View.layer) * View.depth_sign()
	return offset >= 0 and offset <= Const.SLAB_BEHIND


func _site_suits(sp: MobSpecies, site: Dictionary) -> bool:
	var pos: Vector3 = site["pos"]
	var box := sp.box_size
	if not VoxelPhysics.aabb_is_free(pos, box):
		return false
	var block := Const.floor_v(pos)
	if sp.needs_water:
		return Blocks.is_liquid(World.get_block(block))
	if sp.locomotion == MobSpecies.LOCO_WALK or sp.locomotion == MobSpecies.LOCO_BURROW:
		return World.is_solid(block - Vector3i(0, 1, 0))
	if sp.is_rooted():
		return World.is_solid(block - Vector3i(0, 1, 0))
	return true


# ================================================================== despawn
func _prune() -> void:
	var live: Array[MobBase] = []
	for m in _mobs:
		if m != null and is_instance_valid(m) and not m.is_queued_for_deletion():
			live.append(m)
	_mobs = live


func _despawn_far() -> void:
	var player := Game.player
	if player == null:
		return
	var survivors: Array[MobBase] = []
	for m in _mobs:
		if m == null or not is_instance_valid(m):
			continue
		if m.dead or m.is_in_group(&"persistent") or m.is_in_group(&"boss") or m.is_in_group(&"pets"):
			survivors.append(m)
			continue
		var lat: float = absf(Const.lateral_of(m.global_position - player.global_position, View.view))
		var dy: float = absf(m.global_position.y - player.global_position.y)
		var dl: int = absi(m.depth_layer() - View.layer)
		if lat > DESPAWN_PLANE or dy > 72.0 or dl > DESPAWN_LAYERS:
			m.queue_free()
			continue
		survivors.append(m)
	_mobs = survivors


func despawn_all(include_persistent: bool = false) -> void:
	for m in _mobs:
		if m == null or not is_instance_valid(m):
			continue
		if not include_persistent and (m.is_in_group(&"persistent") or m.is_in_group(&"pets")):
			continue
		m.queue_free()
	_prune()


# ==================================================================== queries
func nearby_mobs(pos: Vector3, radius: float, same_layer_only: bool = false) -> Array:
	var out: Array = []
	for m in _mobs:
		if m == null or not is_instance_valid(m) or m.dead:
			continue
		if same_layer_only and m.depth_layer() != View.layer:
			continue
		if m.global_position.distance_to(pos) <= radius:
			out.append(m)
	return out


# ================================================================== spawners
## Spawner markers are `chunk.tile_data` payloads written by the structures
## agent (`StructMarkers.spawner` / `StructMarkers.boss_spawn`). The canonical
## schema is:
##
##   {"kind":"spawner", "pool":String, "tier":int, "count":int, "max_alive":int,
##    "radius":float, "trigger":"proximity"|"always", "once":bool,
##    "theme":String, "seed":int}
##   {"kind":"boss_spawn", "boss":String, "tier":int,
##    "arena_min":[x,y,z], "arena_max":[x,y,z], "reward_table":String}
##
## `pool` is a *logical* group ("cave_crawler", "floran_ward", ...) resolved to a
## concrete species by `MobPools`; unknown pools degrade to a biome-appropriate
## roll. Everything is read defensively, because that schema is explicitly
## allowed to grow — so these spellings are all accepted too:
##
##   kind / type        : "spawner" | "monster_spawner" | "mob_spawner"
##   pool / species / monster / mob / creature / entity : String or Array
##   family             : restrict a generic spawner to one family
##   tier / threat / level / difficulty : int
##   radius / range / r : float, how far from the marker creatures appear
##   max_alive / max / cap / limit : int, concurrent budget
##   count / pack / pack_size / group / wave : int or [min, max], per wave
##   interval / rate / cooldown / delay / every : seconds between waves
##   once / one_shot / single : bool
##   trigger            : "proximity" (default) or "always"
##   activation / trigger_range : float, player distance that arms it
##   boss / is_boss / boss_spawn : the marker spawns a boss instead
const SPAWNER_KINDS: Array[String] = [
	"spawner", "monster_spawner", "mob_spawner", "mob_spawner_marker", "boss_spawn",
]


func _on_chunk_loaded(cpos: Vector3i) -> void:
	var c := World.get_chunk(cpos)
	if c == null or c.tile_data.is_empty():
		return
	var found: Array = []
	for idx: int in c.tile_data:
		var raw: Variant = c.tile_data[idx]
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		if not _is_spawner_payload(d):
			continue
		var local := Chunk.from_index(idx)
		var world := Vector3(c.origin() + local) + Vector3(0.5, 0.0, 0.5)
		found.append(_make_spawner(world, d))
	if not found.is_empty():
		_spawners[cpos] = found


func _on_chunk_unloaded(cpos: Vector3i) -> void:
	_spawners.erase(cpos)
	# Anything that lived in that chunk goes with it.
	var origin := cpos * Const.CHUNK_SIZE
	var box := AABB(Vector3(origin), Vector3.ONE * float(Const.CHUNK_SIZE))
	var survivors: Array[MobBase] = []
	for m in _mobs:
		if m == null or not is_instance_valid(m):
			continue
		if not (m.is_in_group(&"persistent") or m.is_in_group(&"pets") or m.is_in_group(&"boss")) \
				and box.has_point(m.global_position):
			m.queue_free()
			continue
		survivors.append(m)
	_mobs = survivors


func _is_spawner_payload(d: Dictionary) -> bool:
	for k: String in ["kind", "type", "tile", "marker"]:
		var v: Variant = d.get(k, null)
		if v == null:
			continue
		if String(v) in SPAWNER_KINDS:
			return true
	return bool(d.get("spawner", false))


func _make_spawner(world: Vector3, d: Dictionary) -> Dictionary:
	var kind := String(_first(d, ["kind", "type"], ""))
	var pools: Array[StringName] = []
	for k: String in ["pool", "pools", "species", "monster", "monsters", "mob", "creature", "entity"]:
		var v: Variant = d.get(k, null)
		if v == null:
			continue
		if v is Array:
			for e in (v as Array):
				pools.append(StringName(String(e)))
		else:
			pools.append(StringName(String(v)))
		if not pools.is_empty():
			break

	# Boss markers name the boss under "boss" and carry an arena AABB.
	var boss_name := StringName(String(_first(d, ["boss", "boss_id"], "")))
	var is_boss: bool = kind == "boss_spawn" or boss_name != &"" \
		or bool(_first(d, ["is_boss"], false))

	var count: int = maxi(1, int(_first(d, ["count", "pack", "pack_size", "group", "wave"], 1)))
	var pack_lo := count
	var pack_hi := count
	var pack: Variant = _first(d, ["pack", "pack_size", "group"], null)
	if pack is Array and (pack as Array).size() >= 2:
		pack_lo = int((pack as Array)[0])
		pack_hi = int((pack as Array)[1])

	var trigger := String(_first(d, ["trigger"], "proximity"))
	var activation: float = float(_first(d, ["activation", "trigger_range", "activate"], 34.0))
	if trigger == "always":
		activation = 96.0
	return {
		"pos": world,
		"pools": pools,
		"boss": is_boss,
		"boss_name": boss_name,
		"arena_min": _first(d, ["arena_min"], null),
		"arena_max": _first(d, ["arena_max"], null),
		"family": StringName(String(_first(d, ["family"], ""))),
		"tier": int(_first(d, ["tier", "threat", "level", "threat_tier", "difficulty"], -1)),
		"radius": float(_first(d, ["radius", "range", "r"], 6.0)),
		"max_alive": maxi(1, int(_first(d, ["max_alive", "max", "cap", "limit"], count))),
		"interval": float(_first(d, ["interval", "rate", "cooldown", "delay", "every"], 9.0)),
		"once": bool(_first(d, ["once", "one_shot", "single"], false)),
		"activation": activation,
		"pack_lo": pack_lo,
		"pack_hi": pack_hi,
		"timer": 1.0,
		"alive": [],
		"spent": false,
	}


static func _first(d: Dictionary, keys: Array, fallback: Variant) -> Variant:
	for k: String in keys:
		if d.has(k):
			return d[k]
	return fallback


func _tick_spawners(delta: float) -> void:
	var player := Game.player
	if player == null:
		return
	for cpos: Vector3i in _spawners:
		for s: Dictionary in _spawners[cpos]:
			_tick_spawner(s, delta, player)


func _tick_spawner(s: Dictionary, delta: float, player: Node3D) -> void:
	if bool(s["spent"]):
		return
	var pos: Vector3 = s["pos"]
	var dist := player.global_position.distance_to(pos)
	if dist > float(s["activation"]):
		return
	# Prune the ones it already made.
	var live: Array = []
	for m in (s["alive"] as Array):
		if m != null and is_instance_valid(m) and not (m as MobBase).dead:
			live.append(m)
	s["alive"] = live
	if live.size() >= int(s["max_alive"]):
		return
	s["timer"] = float(s["timer"]) - delta
	if float(s["timer"]) > 0.0:
		return
	s["timer"] = float(s["interval"])
	# Do not pop a monster into existence in front of the player.
	if _in_camera_slice(pos, player) and dist < 12.0:
		return

	var opts := {"threat": _planet_threat()}
	if int(s["tier"]) >= 0:
		opts["threat"] = int(s["tier"])

	if bool(s["boss"]):
		_spawn_marker_boss(s, pos, opts)
		return

	var sid := _spawner_species(s, pos)
	if sid == &"":
		return
	var site := _spawner_site(s, pos)
	if site == Vector3.INF:
		return
	if MobBoss.is_boss(sid):
		s["boss_name"] = sid
		_spawn_marker_boss(s, pos, opts)
		return
	var n: int = _rng.randi_range(int(s["pack_lo"]), int(s["pack_hi"]))
	n = mini(n, int(s["max_alive"]) - (s["alive"] as Array).size())
	if n < 1:
		return
	var made: Array = spawn_pack(sid, site, n, opts) if n > 1 else [spawn_species(sid, site, opts)]
	for m in made:
		if m != null:
			(s["alive"] as Array).append(m)
	if bool(s["once"]):
		s["spent"] = true


func _spawn_marker_boss(s: Dictionary, pos: Vector3, opts: Dictionary) -> void:
	var boss_id := MobPools.resolve_boss(StringName(s["boss_name"]))
	var site := _spawner_site(s, pos)
	if site == Vector3.INF:
		site = pos
	var b := spawn_boss(boss_id, site, opts)
	if b == null:
		return
	# Honour the arena the dungeon generator carved for it.
	var lo: Variant = s["arena_min"]
	var hi: Variant = s["arena_max"]
	if lo is Array and hi is Array and (lo as Array).size() == 3 and (hi as Array).size() == 3:
		var a := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
		var c := Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
		b.arena_centre = (a + c) * 0.5
		b.arena_layer = b.depth_layer()
		b.arena_radius = maxf(8.0, (c - a).length() * 0.5)
	(s["alive"] as Array).append(b)
	s["spent"] = true


## Turn the marker's logical pool into a concrete species for *this* spot.
func _spawner_species(s: Dictionary, pos: Vector3) -> StringName:
	var block := Const.floor_v(pos)
	var ctx := {
		"biome": _biome_at(block),
		"threat": int(s["tier"]) if int(s["tier"]) >= 0 else _planet_threat(),
		"night": Game.is_night(),
		"light": _light_at(block),
		"underwater": Blocks.is_liquid(World.get_block(block)),
		"underground": true,
		"hostile_only": true,
	}
	if StringName(s["family"]) != &"":
		ctx["family"] = s["family"]
	var pools: Array = s["pools"]
	if not pools.is_empty():
		var pool: StringName = pools[_rng.randi() % pools.size()]
		var sid := MobPools.resolve(pool, ctx, _rng)
		if sid != &"":
			return sid
	var sp: MobSpecies = MobSpeciesDB.pick(ctx, _rng)
	return sp.id if sp != null else &""


func _spawner_site(s: Dictionary, pos: Vector3) -> Vector3:
	var radius: float = maxf(1.0, float(s["radius"]))
	for _i in 8:
		var r := View.right()
		var lat := _rng.randf_range(-radius, radius)
		var p := pos + Vector3(float(r.x), 0.0, float(r.z)) * lat
		p.y += float(_rng.randi_range(0, 2))
		p = _snap_to_layer_centre(p)
		if VoxelPhysics.aabb_is_free(p, Vector3(1.0, 1.8, 1.0)):
			return p
	if VoxelPhysics.aabb_is_free(pos, Vector3(1.0, 1.8, 1.0)):
		return pos
	return Vector3.INF


# ==================================================================== events
func _on_layer_changed(_layer: int, _view: int) -> void:
	# The play plane moved; every cached route is now measured from the wrong
	# slice, and monsters should re-evaluate who they can see.
	MobPath.invalidate()


func _on_block_changed(_pos: Vector3i, _old_id: int, _new_id: int) -> void:
	MobPath.invalidate()


func _on_world_unloaded() -> void:
	_spawners.clear()
	despawn_all(true)


func _on_play_sound(sound_id: String, world_pos: Vector3) -> void:
	if not LOUD_SOUNDS.has(sound_id):
		return
	for m in _mobs:
		if m != null and is_instance_valid(m) and not m.dead:
			m.hear(world_pos, 1.0)


# ===================================================================== debug
func debug_report() -> String:
	var lines: Array[String] = []
	lines.append("mobs %d/%d  spawners %d  %s" % [mob_count(), population_cap(),
		_spawners.size(), MobPath.stats()])
	for m in _mobs:
		if m != null and is_instance_valid(m) and not m.dead:
			lines.append("  " + m.debug_line())
	return "\n".join(lines)
