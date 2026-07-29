## Sea-level enforcement for ocean biomes.
##
## An ocean is *not* simulated. A planet-wide body of water would keep tens of
## thousands of cells awake forever and the result would be indistinguishable
## from a flat plane of water. The whole design is four rules:
##
## 1. **Static sources.** Any liquid voxel at or below `sea_level` in an ocean
##    column is a *source*: the solver may take liquid out of it forever without
##    it ever decreasing, and it never needs updating for its own sake. A source
##    costs exactly nothing until something next to it changes.
##
## 2. **Boundary waking.** The only way an ocean starts flowing is a world edit
##    below the waterline — the player digs the seabed, an explosion opens a
##    bulkhead, a sand block falls out of a wall. `Liquids` forwards those edits
##    to [method on_hole_opened], which wakes just the handful of source cells
##    touching the new hole. Water rushes in, the cavity fills, everything goes
##    back to sleep. Cost is proportional to the size of the hole, not the sea.
##
## 3. **Above-sea clamp.** A source never donates to a voxel above `sea_level`,
##    so no amount of digging makes the ocean climb out of its basin. Ordinary
##    (non-source) water still obeys the normal pressure rules and will rise up
##    a flooded shaft to the level of its own surface.
##
## 4. **Generation is somebody else's job.** `PlanetGen`/`WorldDecorator`
##    already stamp every below-sea-level air voxel with the biome's liquid at
##    generation time (`fill_liquids`), so there is nothing to fill in the
##    common case. The repair pass in [method _fill_chunk] exists only for
##    planets that opt into it with `meta.ocean_fill = true` — it must never
##    flood an air pocket some other agent deliberately authored.
##
## Sea level comes from the planet metadata, falling back to `PlanetGen`'s own
## `sea_level`; if neither exists the module stays disabled and costs nothing.
class_name LiqOcean
extends RefCounted

## Biome keys treated as open ocean. Matched against `PlanetGen.biome_at`.
const OCEAN_BIOMES: Array[StringName] = [
	&"ocean", &"deep_ocean", &"sea", &"shallows", &"reef", &"ocean_floor",
	&"tar_pit", &"acid_sea", &"magma_sea", &"toxic_sea", &"kelp_forest",
]

const FILL_CHUNKS_PER_TICK := 2
const COLUMN_CACHE_LIMIT := 4096
## Columns are sampled on an 8x8 grid; biomes never change faster than that.
const COLUMN_GRID := 3

var sea_level: int = -1              ## -1 disables the whole module
var default_liquid: StringName = &"water"
var enabled: bool = false
## Opt-in repair pass; the terrain generator normally fills oceans itself.
var enforce_fill: bool = false
## Water world: every column counts as ocean, no biome query at all.
var all_ocean: bool = false

var _fill_queue: Array[Vector3i] = []
var _fill_set: Dictionary = {}
var _columns: Dictionary = {}        ## Vector2i -> {"ocean": bool, "id": int}
var _filled_chunks: Dictionary = {}
var _stat_filled := 0


## Re-read the planet metadata. Called on `world_ready`.
##
## Recognised keys: `sea_level` / `ocean_level` (int), `liquid` / `ocean_liquid`
## (StringName), `ocean` (bool — treat the whole planet as sea), `ocean_fill`
## (bool — run the repair pass).
func configure(meta: Dictionary) -> void:
	reset()
	sea_level = int(meta.get("sea_level", meta.get("ocean_level", -1)))
	if sea_level < 0:
		var probe: Variant = PlanetGen.get(&"sea_level")
		if probe != null:
			sea_level = int(probe)
	default_liquid = StringName(meta.get("liquid", meta.get("ocean_liquid", &"water")))
	all_ocean = bool(meta.get("ocean", false))
	enforce_fill = bool(meta.get("ocean_fill", false))
	enabled = sea_level >= 0 and _default_id() != Const.AIR


## Manual override for tests, the map editor and scripted set-pieces.
func set_sea_level(y: int, liquid: StringName = &"water") -> void:
	sea_level = y
	default_liquid = liquid
	enabled = y >= 0 and _default_id() != Const.AIR
	_columns.clear()
	_filled_chunks.clear()


func reset() -> void:
	sea_level = -1
	enabled = false
	all_ocean = false
	enforce_fill = false
	_fill_queue.clear()
	_fill_set.clear()
	_columns.clear()
	_filled_chunks.clear()


func _default_id() -> int:
	var id := LiqType.block_id(default_liquid)
	if id == Const.AIR and Blocks.has(&"water"):
		id = Blocks.id(&"water")
	return id


# ------------------------------------------------------------------ columns
## `{"ocean": bool, "id": int}` for a world column, cached on an 8x8 grid.
##
## `id` is the block id of *that column's* sea liquid, so a toxic ocean, a tar
## pit and a normal sea can coexist on one planet without the source test ever
## mistaking a pocket of lava for the sea it is sitting under.
func column_info(x: int, z: int) -> Dictionary:
	var key := Vector2i(x >> COLUMN_GRID, z >> COLUMN_GRID)
	var hit: Variant = _columns.get(key)
	if hit is Dictionary:
		return hit
	var info := {"ocean": all_ocean, "id": _default_id()}
	if not all_ocean and PlanetGen.has_method(&"biome_at"):
		info["ocean"] = OCEAN_BIOMES.has(StringName(PlanetGen.biome_at(x, z)))
	if info["ocean"] and PlanetGen.has_method(&"biome_of"):
		var b: Variant = PlanetGen.biome_of(x, z)
		if b != null and b.has_method(&"ids"):
			var ids: Variant = b.call(&"ids")
			if ids is Dictionary:
				var lid := int((ids as Dictionary).get("liquid", Const.AIR))
				if lid != Const.AIR and Blocks.is_liquid(lid):
					info["id"] = lid
	if _columns.size() > COLUMN_CACHE_LIMIT:
		_columns.clear()
	_columns[key] = info
	return info


## Is this column part of an ocean?
func is_ocean_column(x: int, z: int) -> bool:
	return enabled and bool(column_info(x, z)["ocean"])


## Block id of the liquid that fills this column's sea.
func liquid_id_for(x: int, z: int) -> int:
	return int(column_info(x, z)["id"])


## True when `pos` holds an inexhaustible ocean cell of `block_id`.
##
## Hot path — it runs once per liquid cell update — so the integer comparisons
## come first and the cached column lookup last.
func is_source(pos: Vector3i, block_id: int) -> bool:
	if not enabled or pos.y > sea_level:
		return false
	if block_id == Const.AIR or not Blocks.is_liquid(block_id):
		return false
	var info := column_info(pos.x, pos.z)
	return bool(info["ocean"]) and int(info["id"]) == block_id


## A source will not push liquid above the waterline.
func may_donate_to(target: Vector3i) -> bool:
	return target.y <= sea_level


# --------------------------------------------------------------- chunk fill
## Queue a freshly streamed chunk for the (opt-in) repair pass.
func on_chunk_loaded(cpos: Vector3i) -> void:
	if not enabled or not enforce_fill:
		return
	if _filled_chunks.has(cpos) or _fill_set.has(cpos):
		return
	if (cpos.y << 4) > sea_level:
		return   ## entirely above the waterline
	_fill_set[cpos] = true
	_fill_queue.append(cpos)


func on_chunk_unloaded(cpos: Vector3i) -> void:
	_filled_chunks.erase(cpos)
	if _fill_set.erase(cpos):
		_fill_queue.erase(cpos)


## Drain a slice of the fill queue. Called once per sim tick.
func tick() -> void:
	if not enabled or _fill_queue.is_empty():
		return
	var n := 0
	while n < FILL_CHUNKS_PER_TICK and not _fill_queue.is_empty():
		var cpos: Vector3i = _fill_queue.pop_front()
		_fill_set.erase(cpos)
		_fill_chunk(cpos)
		n += 1


## Top-down until the seabed, so caves under the floor and sealed chambers stay
## dry until something actually breaks through to them.
func _fill_chunk(cpos: Vector3i) -> void:
	var chunk: Chunk = World.get_chunk(cpos)
	if chunk == null:
		return
	_filled_chunks[cpos] = true
	var origin := cpos * Const.CHUNK_SIZE
	var touched := false
	for lx in Const.CHUNK_SIZE:
		for lz in Const.CHUNK_SIZE:
			var wx := World.wrap_x(origin.x + lx)
			var wz := World.wrap_z(origin.z + lz)
			if not is_ocean_column(wx, wz):
				continue
			var lid := liquid_id_for(wx, wz)
			if lid == Const.AIR:
				continue
			for ly in range(Const.CHUNK_SIZE - 1, -1, -1):
				var y := origin.y + ly
				if y > sea_level:
					continue
				var i := Chunk.index(lx, ly, lz)
				var existing := chunk.blocks[i]
				if existing == lid:
					if chunk.liquid[i] != Const.MAX_LIQUID:
						chunk.liquid[i] = Const.MAX_LIQUID
						touched = true
					continue
				if existing != Const.AIR:
					break
				chunk.set_at(i, lid)
				chunk.liquid[i] = Const.MAX_LIQUID
				touched = true
				_stat_filled += 1
	if touched:
		chunk.dirty = true
		World.mark_dirty(cpos)
		for nrm: Vector3i in Const.FACE_NORMALS:
			World.mark_dirty(cpos + nrm)


# ---------------------------------------------------------- boundary waking
## A voxel below the waterline changed. Wake only the liquid cells that touch
## it — this is the entire cost of "the ocean reacts to digging".
func on_hole_opened(pos: Vector3i) -> void:
	if not enabled or pos.y > sea_level:
		return
	for nrm: Vector3i in Const.FACE_NORMALS:
		var q := World.normalize(pos + nrm)
		if q.y < 0 or q.y >= Const.WORLD_HEIGHT:
			continue
		if Blocks.is_liquid(World.get_block(q)):
			Liquids.wake(q, 0)


func debug_info() -> Dictionary:
	return {
		"enabled": enabled,
		"sea_level": sea_level,
		"liquid": default_liquid,
		"all_ocean": all_ocean,
		"fill_queue": _fill_queue.size(),
		"cells_filled": _stat_filled,
	}
