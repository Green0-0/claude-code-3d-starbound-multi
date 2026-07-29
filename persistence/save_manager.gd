## Autoloaded as `SaveManager`. Three-tier chunk paging plus the whole-game
## save archive.
##
## Why three tiers
## ---------------
## `World` calls `load_chunk()` on **every** chunk it builds and `store_chunk()`
## on **every** chunk it evicts. With a slab-shaped streaming box that is dozens
## of calls a second, forever, across many planets. Naively serialising each one
## would be unusable, so the work is split:
##
## * **Hot** — an in-memory LRU of recently evicted `Chunk` objects. Walking
##   back and forth across a chunk boundary is a dictionary lookup and nothing
##   else: no decode, no allocation, no disk.
## * **Warm** — one `SavRegion` file per 16x16x16 block of chunks, per planet.
##   Writes are batched and executed on a `WorkerThreadPool` task; the game loop
##   never waits on the filesystem. Region *slot tables* are cached in RAM, so
##   the overwhelmingly common "this chunk was never modified" answer costs one
##   hash lookup and zero I/O.
## * **Cold** — `user://saves/slot_N/`, the complete archive: `save.dat`,
##   `save.bak`, `meta.json` and the planet region directories.
##
## Modified-chunk detection — the heart of the design
## --------------------------------------------------
## Terrain is a pure function of `(seed, chunk position)`, so an untouched chunk
## must never reach the disk: it is cheaper to regenerate it than to read it.
## Three cooperating signals decide:
##
## 1. **Edit tracking.** `Events.block_changed` marks the owning chunk modified
##    in O(1). This catches every player mine/place.
## 2. **Generation hash.** The first time a chunk is built from the generator we
##    record `hash(blocks) ^ hash(liquid)` as its *baseline*. On eviction we
##    re-hash; equal means "the generator would produce this again" and the
##    chunk is dropped. This is the backstop that catches writes which bypass
##    the signal — `set_block(..., notify=false)`, the liquid simulation,
##    falling sand, explosion cleanup.
## 3. **Tile data.** Any chunk holding tile entities (chests, machines, signs)
##    is modified by definition; `SavEntityPersistence.set_object_data()` also
##    marks explicitly, because a chest's *contents* can change without the
##    dictionary's shape changing.
##
## A chunk that comes back off the disk is flagged modified permanently — it is
## already divergent, so it stays authoritative.
##
## Net effect: a planet costs region files proportional to what the player
## actually touched, not to where they walked.
extends Node

const SAVE_ROOT := "user://saves"
const SAVE_FILE := "save.dat"
const SAVE_FILE_JSON := "save.json"
const META_FILE := "meta.json"
const PLANET_DIR := "planets"
const ENTITY_FILE := "entities.dat"
const SLOT_COUNT := 8

## Chunks held in the hot LRU. ~24 KB each once liquid + light are counted, so
## 768 is roughly 18 MB — small next to the meshes the renderer holds.
const HOT_CAPACITY := 768
## Trim this many past the target so the O(n log n) sort is amortised away.
const TRIM_SLACK := 96

## Background write cadence.
const WRITE_INTERVAL := 3.0
const WRITE_BATCH := 48
## Region files kept open at once.
const REGION_CACHE := 12

## Keep the baseline hash table bounded on very long sessions.
const MAX_BASELINES := 200000

## Emitted after a background batch reaches the disk. `count` chunks written.
signal chunks_flushed(count: int)
## Emitted when a slot finishes saving or loading, mirroring `Events`.
signal slot_changed(slot: int)

## The settings node, parented to `/root/Settings`. See `SavSettings`.
var settings: SavSettings = null
## NPC / pet registry and the tile-data helpers.
var entities: SavEntityPersistence = null
## Autosave scheduler.
var autosave: SavAutosave = null

## Slot the live session is paging chunks into. Chunk data is written into the
## slot directory as you play (Minecraft-style); `save_game()` writes the
## metadata document that makes the slot loadable.
var current_slot := 0
## Seconds of wall-clock play in this run, persisted in the save meta.
var playtime := 0.0
var save_name := ""
## True while `load_game` is rebuilding the world. Other modules (and the
## autosave scheduler) must not react to the travel/world signals it emits.
var loading := false
var _created_unix := 0

# ------------------------------------------------------------------- hot tier
var _hot: Dictionary = {}        ## key -> Chunk
var _hot_seq: Dictionary = {}    ## key -> int, LRU stamp
var _seq := 0

# ------------------------------------------- modified-chunk bookkeeping
var _baseline: Dictionary = {}       ## key -> generation hash
var _known_modified: Dictionary = {} ## key -> true

# ------------------------------------------------------------------ warm tier
var _regions: Dictionary = {}    ## "planet|rx,ry,rz" -> SavRegion
var _region_lru: Array[String] = []
var _region_mutex := Mutex.new()

var _queue: Dictionary = {}      ## key -> write record (coalesced)
var _queue_mutex := Mutex.new()
var _batch: Array = []
var _task_id := -1
var _write_timer := 0.0

# ------------------------------------------------------------------ telemetry
var _stat_hot_hits := 0
var _stat_warm_hits := 0
var _stat_misses := 0
var _stat_written := 0
var _stat_discarded := 0
var _stat_bytes := 0   ## reserved for byte-throughput telemetry
var _last_error := ""


# ================================================================== lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 90

	settings = SavSettings.new()
	settings.load_settings()
	get_tree().root.call_deferred(&"add_child", settings)
	settings.apply_all.call_deferred()

	entities = SavEntityPersistence.new()

	autosave = SavAutosave.new()
	add_child(autosave)

	DirAccess.make_dir_recursive_absolute(SAVE_ROOT)
	_cleanup_orphan_sessions()

	Events.block_changed.connect(_on_block_changed)
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.world_unloaded.connect(_on_world_unloaded)

	_created_unix = int(Time.get_unix_time_from_system())


func _process(delta: float) -> void:
	if not Game.paused:
		playtime += delta
	_poll_task()
	if _queue.is_empty():
		return
	_write_timer += delta
	if _task_id >= 0:
		return
	if _write_timer >= WRITE_INTERVAL or _queue.size() >= WRITE_BATCH:
		_submit_batch()


func _exit_tree() -> void:
	_drain_writes()
	_close_regions()


# =========================================================== HOT PATH: chunks
## Called by `World` for every chunk it builds. Returns the stored chunk, or
## `null` to mean "generate it from the seed".
##
## Fast path: one dictionary lookup for hot, one for the warm index. Only a
## chunk the player genuinely modified ever touches the filesystem here.
func load_chunk(planet_id: String, cp: Vector3i) -> Chunk:
	var key := _key(planet_id, cp)

	var hot: Chunk = _hot.get(key)
	if hot != null:
		_hot_seq[key] = _seq
		_seq += 1
		_stat_hot_hits += 1
		return hot

	var c := _read_warm(planet_id, cp, key)
	if c != null:
		_stat_warm_hits += 1
		# Anything on disk is divergent from the generator by construction.
		_known_modified[key] = true
		_hot[key] = c
		_hot_seq[key] = _seq
		_seq += 1
		if _hot.size() > HOT_CAPACITY:
			_trim_hot()
		return c

	_stat_misses += 1
	return null


## Called by `World` for every chunk it evicts. Cheap: an LRU insert plus, for
## a modified chunk, a snapshot appended to the background write queue.
func store_chunk(planet_id: String, chunk: Chunk) -> void:
	if chunk == null:
		return
	var key := _key(planet_id, chunk.cpos)
	_hot[key] = chunk
	_hot_seq[key] = _seq
	_seq += 1
	if _hot.size() > HOT_CAPACITY:
		_trim_hot()

	if _is_modified(key, chunk):
		_known_modified[key] = true
		_enqueue(planet_id, chunk, key)
	else:
		_stat_discarded += 1


## Push everything for `planet_id` to disk and wait for it. Called by
## `Game.travel_to_planet` before the world is torn down, so a frame hitch here
## is invisible behind the travel transition.
func flush_world(planet_id: String) -> void:
	if planet_id == "":
		return
	_capture_loaded_chunks(planet_id)
	if entities != null:
		entities.capture_all(planet_id)
		_write_planet_entities(planet_id)
	_drain_writes()
	_commit_regions()


# ------------------------------------------------------ modified-chunk logic
## Force a chunk to be treated as modified. Call this after any change that
## does not go through `World.set_block` — most importantly a `tile_data` write,
## which is invisible to both the block signal and the shape of the chunk.
func mark_chunk_modified(planet_id: String, cp: Vector3i) -> void:
	_known_modified[_key(planet_id, cp)] = true


## Re-record a chunk's generation baseline. Worldgen agents that populate
## structures, ores or decorations *after* `chunk_loaded` should call this once
## their pass is done; otherwise their output looks like a player edit and gets
## written to disk needlessly (correct, but wasteful).
func rebaseline_chunk(planet_id: String, chunk: Chunk) -> void:
	if chunk == null:
		return
	var key := _key(planet_id, chunk.cpos)
	if _known_modified.has(key):
		return
	_baseline[key] = _content_hash(chunk)


## Is this chunk currently considered player-modified?
func is_chunk_modified(planet_id: String, cp: Vector3i) -> bool:
	return _known_modified.has(_key(planet_id, cp))


func _is_modified(key: String, chunk: Chunk) -> bool:
	if _known_modified.has(key):
		return true
	if not chunk.tile_data.is_empty():
		return true
	if not _baseline.has(key):
		# Unknown provenance (loaded before we were listening, or hand-built).
		# Err towards keeping the player's world.
		return true
	return _content_hash(chunk) != int(_baseline[key])


## Cheap fingerprint of everything the generator is responsible for. `hash()`
## is a native buffer hash, so this is microseconds for 4096 voxels — orders of
## magnitude below the cost of regenerating the chunk it protects us from.
## Light is deliberately excluded: it is derived, not authored.
func _content_hash(chunk: Chunk) -> int:
	return (hash(chunk.blocks) * 31) ^ hash(chunk.liquid)


func _on_block_changed(pos: Vector3i, _old_id: int, _new_id: int) -> void:
	_known_modified[_key(World.planet_id, Vector3i(pos.x >> 4, pos.y >> 4, pos.z >> 4))] = true


func _on_chunk_loaded(cp: Vector3i) -> void:
	var c: Chunk = World.chunks.get(cp)
	if c == null:
		return
	var key := _key(World.planet_id, cp)
	if not _known_modified.has(key) and not _baseline.has(key):
		if _baseline.size() >= MAX_BASELINES:
			_prune_baselines()
		_baseline[key] = _content_hash(c)
	if entities != null:
		entities.respawn_chunk(World.planet_id, cp)


## Safety net: `World.unload_world()` clears its chunk table without calling
## `store_chunk`, but it does emit `chunk_unloaded` while the chunk is still
## present. Normal eviction has already erased it by this point, so this never
## does double work.
func _on_chunk_unloaded(cp: Vector3i) -> void:
	if entities != null:
		entities.capture_chunk(World.planet_id, cp)
	var c: Chunk = World.chunks.get(cp)
	if c != null:
		store_chunk(World.planet_id, c)


func _on_world_unloaded() -> void:
	pass


func _prune_baselines() -> void:
	# Keep only what is still resident; everything else can be re-derived on the
	# next visit (at the cost of one conservative save).
	var keep := {}
	for k: String in _hot:
		if _baseline.has(k):
			keep[k] = _baseline[k]
	_baseline = keep


# ---------------------------------------------------------------- hot tier
func _trim_hot() -> void:
	var target := maxi(16, HOT_CAPACITY - TRIM_SLACK)
	if _hot.size() <= target:
		return
	var stamps: Array = []
	stamps.resize(_hot_seq.size())
	var i := 0
	for k: String in _hot_seq:
		stamps[i] = [int(_hot_seq[k]), k]
		i += 1
	stamps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var drop := _hot.size() - target
	for j in mini(drop, stamps.size()):
		var k: String = stamps[j][1]
		_hot.erase(k)
		_hot_seq.erase(k)


func _key(planet_id: String, cp: Vector3i) -> String:
	return "%s:%d,%d,%d" % [planet_id, cp.x, cp.y, cp.z]


# ================================================================= warm tier
func _read_warm(planet_id: String, cp: Vector3i, _key_str: String) -> Chunk:
	if planet_id == "":
		return null
	_region_mutex.lock()
	var region := _region_for(planet_id, cp, false)
	var payload: Dictionary = {}
	if region != null and region.has_chunk(cp):
		payload = region.read_chunk(cp)
	_region_mutex.unlock()
	if payload.is_empty():
		return null
	# A payload that fails to rebuild is treated exactly like a missing chunk:
	# the world regenerates it and play continues.
	var c: Chunk = null
	if payload.has("b") and payload.has("c"):
		c = Chunk.from_dict(payload)
	if c == null:
		push_warning("[SaveManager] chunk %s failed to rebuild — regenerating" % cp)
		return null
	c.cpos = cp
	c.dirty = true
	return c


func _region_key(planet_id: String, rpos: Vector3i) -> String:
	return "%s|%d,%d,%d" % [planet_id, rpos.x, rpos.y, rpos.z]


## Caller must hold `_region_mutex`.
func _region_for(planet_id: String, cp: Vector3i, create: bool) -> SavRegion:
	var rpos := SavRegion.region_of(cp)
	var rk := _region_key(planet_id, rpos)
	var r: SavRegion = _regions.get(rk)
	if r != null:
		return r
	var path := "%s/%s" % [planet_dir(current_slot, planet_id), SavRegion.file_name(rpos)]
	if not create and not FileAccess.file_exists(path):
		return null
	r = SavRegion.new()
	if not r.open_file(path):
		_last_error = r.error
		return null
	_regions[rk] = r
	_region_lru.append(rk)
	while _region_lru.size() > REGION_CACHE:
		var old: String = _region_lru.pop_front()
		if old == rk:
			_region_lru.append(rk)   ## never evict the region we just opened
			break
		var dead: SavRegion = _regions.get(old)
		if dead != null:
			dead.close()
			_regions.erase(old)
	return r


func _commit_regions() -> void:
	_region_mutex.lock()
	for k: String in _regions:
		var r: SavRegion = _regions[k]
		if r != null:
			r.commit()
	_region_mutex.unlock()


func _close_regions() -> void:
	_region_mutex.lock()
	for k: String in _regions:
		var r: SavRegion = _regions[k]
		if r != null:
			r.close()
	_regions.clear()
	_region_lru.clear()
	_region_mutex.unlock()


## Run a compaction pass over every open region that has accumulated dead heap.
## Cheap to call — regions that are tidy return immediately.
func compact_regions() -> int:
	var n := 0
	_region_mutex.lock()
	for k: String in _regions:
		var r: SavRegion = _regions[k]
		if r != null and r.needs_compaction():
			if r.compact():
				n += 1
	_region_mutex.unlock()
	return n


# ----------------------------------------------------------- write pipeline
## A 4096-byte run of zeros, so "is this chunk's liquid layer empty?" is a
## native buffer comparison rather than a GDScript loop.
static var _ZERO_LIQUID := PackedByteArray()


static func _liquid_is_empty(l: PackedByteArray) -> bool:
	if _ZERO_LIQUID.size() != Const.CHUNK_VOL:
		_ZERO_LIQUID.resize(Const.CHUNK_VOL)
	return l == _ZERO_LIQUID


## Snapshot the chunk on the calling (main) thread so the worker can compress
## and write without ever racing the live world. The copies are 16 KB + 4 KB and
## only happen for chunks that are actually modified.
func _enqueue(planet_id: String, chunk: Chunk, key: String) -> void:
	var liquid := PackedByteArray()
	if not _liquid_is_empty(chunk.liquid):
		liquid = chunk.liquid.duplicate()
	var rec := {
		"planet": planet_id,
		"cpos": chunk.cpos,
		"c": [chunk.cpos.x, chunk.cpos.y, chunk.cpos.z],
		"b": chunk.blocks.duplicate(),
		"l": liquid,
		"t": chunk.tile_data.duplicate(true) if not chunk.tile_data.is_empty() else {},
		"g": chunk.generated,
		"p": chunk.populated,
	}
	_queue_mutex.lock()
	_queue[key] = rec          ## newest snapshot wins; coalesces oscillation
	_queue_mutex.unlock()


func _submit_batch() -> void:
	_queue_mutex.lock()
	_batch = _queue.values()
	_queue.clear()
	_queue_mutex.unlock()
	_write_timer = 0.0
	if _batch.is_empty():
		return
	_task_id = WorkerThreadPool.add_task(_worker_write, false, "Planeshift chunk flush")


func _worker_write() -> void:
	var n := _write_records(_batch)
	call_deferred(&"_on_batch_done", n)


func _on_batch_done(n: int) -> void:
	chunks_flushed.emit(n)


func _poll_task() -> void:
	if _task_id < 0:
		return
	if WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_batch = []


## Block until every queued chunk is on disk. Used by travel, save and quit.
func _drain_writes() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_batch = []
	_queue_mutex.lock()
	var pending: Array = _queue.values()
	_queue.clear()
	_queue_mutex.unlock()
	if pending.is_empty():
		return
	_write_records(pending)
	_commit_regions()


## Group records by region, write them, commit each touched header once.
## Runs on the worker thread in the common case.
func _write_records(records: Array) -> int:
	var touched: Dictionary = {}
	var n := 0
	for rec: Variant in records:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec
		var planet := String(r["planet"])
		var cp: Vector3i = r["cpos"]
		var payload := _pack(r)
		_region_mutex.lock()
		var region := _region_for(planet, cp, true)
		if region != null:
			if region.write_chunk(cp, payload):
				n += 1
				_stat_written += 1
			touched[_region_key(planet, SavRegion.region_of(cp))] = true
		_region_mutex.unlock()
	_region_mutex.lock()
	for k: String in touched:
		var reg: SavRegion = _regions.get(k)
		if reg != null:
			reg.commit()
	_region_mutex.unlock()
	return n


## Turn a raw snapshot into the on-disk payload. Mirrors `Chunk.to_dict()`
## exactly so `Chunk.from_dict()` reads it, but the expensive zstd passes happen
## here — on the worker — instead of in `store_chunk`.
func _pack(rec: Dictionary) -> Dictionary:
	var blocks: PackedInt32Array = rec["b"]
	var liquid: PackedByteArray = rec["l"]
	return {
		"c": rec["c"],
		"b": var_to_bytes(blocks).compress(FileAccess.COMPRESSION_ZSTD),
		"bn": blocks.size(),
		"l": liquid.compress(FileAccess.COMPRESSION_ZSTD) if liquid.size() > 0 else PackedByteArray(),
		"t": rec["t"],
		"g": rec["g"],
		"p": rec["p"],
	}


## Snapshot every chunk the world currently holds for `planet_id`, so a save or
## a planet change never loses the ground under the player's feet.
func _capture_loaded_chunks(planet_id: String) -> void:
	if not World.ready_flag or World.planet_id != planet_id:
		return
	for cp: Vector3i in World.chunks:
		var c: Chunk = World.chunks[cp]
		if c == null:
			continue
		var key := _key(planet_id, cp)
		if _is_modified(key, c):
			_known_modified[key] = true
			_enqueue(planet_id, c, key)


# =============================================================== cold tier
## `user://saves/slot_N`
func slot_dir(slot: int) -> String:
	return "%s/slot_%d" % [SAVE_ROOT, slot]


## `user://saves/slot_N/planets/<planet>`
func planet_dir(slot: int, planet_id: String) -> String:
	return "%s/%s/%s" % [slot_dir(slot), PLANET_DIR, _safe_name(planet_id)]


func save_path(slot: int) -> String:
	return "%s/%s" % [slot_dir(slot), SAVE_FILE]


func meta_path(slot: int) -> String:
	return "%s/%s" % [slot_dir(slot), META_FILE]


static func _safe_name(s: String) -> String:
	return s.validate_filename() if s != "" else "unknown"


## Write the complete archive. Non-blocking for the chunk tier is not possible
## here — a save must be a consistent point in time — but the heavy lifting
## (encode + compress + write) is the small metadata document, not the world.
func save_game(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("[SaveManager] slot %d out of range" % slot)
		return false
	var t0 := Time.get_ticks_msec()

	# 1. Everything the world is holding right now becomes durable.
	_capture_loaded_chunks(World.planet_id)
	if entities != null:
		entities.capture_all(World.planet_id)
	_drain_writes()
	_commit_regions()

	# 2. "Save as" into a different slot: carry the region data across.
	if slot != current_slot:
		_close_regions()
		_copy_dir(slot_dir(current_slot) + "/" + PLANET_DIR, slot_dir(slot) + "/" + PLANET_DIR)
		current_slot = slot

	if World.planet_id != "":
		_write_planet_entities(World.planet_id)

	# 3. The metadata document.
	var doc := SavSaveFile.collect(slot, save_name, playtime, _created_unix)
	var path := save_path(slot)
	if SavCodec.debug_json:
		path = "%s/%s" % [slot_dir(slot), SAVE_FILE_JSON]
	if not SavCodec.write_atomic(path, doc):
		_last_error = "could not write %s" % path
		Events.toast("Save failed: %s" % _last_error, "error")
		return false
	var doc_meta: Dictionary = doc.get("meta", {})
	_write_meta(slot, doc_meta)

	var ms := Time.get_ticks_msec() - t0
	if bool(SavSettings.get_setting("debug", "verbose_saves", false)):
		print("[SaveManager] saved slot %d in %d ms — %s" % [slot, ms, JSON.stringify(stats())])
	Events.game_saved.emit(slot)
	slot_changed.emit(slot)
	return true


## Read a slot back and hand each section to its owning module.
func load_game(slot: int) -> bool:
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		var jpath := "%s/%s" % [slot_dir(slot), SAVE_FILE_JSON]
		if FileAccess.file_exists(jpath):
			path = jpath
		else:
			_last_error = "no save in slot %d" % slot
			return false
	var res := SavCodec.read_with_fallback(path)
	if not bool(res["ok"]):
		_last_error = String(res["error"])
		push_error("[SaveManager] load failed: %s" % _last_error)
		Events.toast("Load failed: %s" % _last_error, "error")
		return false
	if bool(res.get("from_backup", false)):
		Events.toast("Primary save was damaged — loaded the backup.", "warn")

	# Drop every trace of the previous session before the new one starts.
	_drain_writes()
	_close_regions()
	_hot.clear()
	_hot_seq.clear()
	_baseline.clear()
	_known_modified.clear()
	if entities != null:
		entities.clear_all()
	current_slot = slot

	var doc: Dictionary = res["data"]
	var meta: Dictionary = doc.get("meta", {})
	save_name = String(meta.get("name", ""))
	playtime = float(meta.get("playtime", 0.0))
	_created_unix = int(meta.get("created", Time.get_unix_time_from_system()))

	loading = true
	var ok := SavSaveFile.apply(doc)
	loading = false
	if ok and World.planet_id != "":
		_read_planet_entities(World.planet_id)
	call_deferred(&"_settle_after_load", doc)
	Events.game_loaded.emit(slot)
	slot_changed.emit(slot)
	return ok


## After the world has had a couple of frames to stream in, put the player back
## exactly where the save said and re-centre streaming on them.
func _settle_after_load(doc: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var sections: Dictionary = doc.get("sections", {})
	var ps: Variant = sections.get("player", null)
	var player: Node = Game.player
	if ps is Dictionary and player != null and is_instance_valid(player):
		var pa: Array = (ps as Dictionary).get("pos", [])
		if pa.size() == 3 and player is Node3D:
			var dest := Vector3(pa[0], pa[1], pa[2])
			var cp := Vector3i(floori(dest.x) >> 4, floori(dest.y) >> 4, floori(dest.z) >> 4)
			for dy in range(-1, 2):
				World.request_chunk(Vector3i(cp.x, cp.y + dy, cp.z))
			if World.has_method(&"_pump_generation_all"):
				World.call(&"_pump_generation_all", 256)
			if player.has_method(&"teleport"):
				player.call(&"teleport", dest)
			else:
				(player as Node3D).global_position = dest
	if Game.player != null:
		World.update_streaming(Game.player.global_position)


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(save_path(slot)) \
		or FileAccess.file_exists("%s/%s" % [slot_dir(slot), SAVE_FILE_JSON])


## Every populated slot, newest first. Reads only `meta.json`, so drawing a
## load menu never decodes a full save.
func list_saves() -> Array:
	var out: Array = []
	for slot in SLOT_COUNT:
		if not has_save(slot):
			continue
		var meta := _read_meta(slot)
		meta["slot"] = slot
		meta["exists"] = true
		if not meta.has("name"):
			meta["name"] = "Slot %d" % slot
		out.append(meta)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("saved", 0)) > int((b as Dictionary).get("saved", 0)))
	return out


## Erase a slot completely, chunk data included. Used by hardcore death and by
## the menus agent.
func delete_save(slot: int) -> bool:
	if slot == current_slot:
		_drain_writes()
		_close_regions()
		_hot.clear()
		_hot_seq.clear()
		_baseline.clear()
		_known_modified.clear()
	var dir := slot_dir(slot)
	var ok := _remove_dir(dir)
	if ok:
		Events.toast("Save slot %d deleted." % slot, "warn")
	return ok


## Start a fresh run in `slot`, discarding any world data already sitting there.
func begin_new_run(slot: int = 0) -> void:
	_drain_writes()
	_close_regions()
	_hot.clear()
	_hot_seq.clear()
	_baseline.clear()
	_known_modified.clear()
	if entities != null:
		entities.clear_all()
	_remove_dir(slot_dir(slot) + "/" + PLANET_DIR)
	current_slot = slot
	playtime = 0.0
	save_name = ""
	_created_unix = int(Time.get_unix_time_from_system())


# ---------------------------------------------------------------- meta / io
func _write_meta(slot: int, meta: Dictionary) -> void:
	var f := FileAccess.open(meta_path(slot), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(SavCodec.to_json_safe(meta), "\t"))
	f.flush()
	f.close()


func _read_meta(slot: int) -> Dictionary:
	var p := meta_path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var v: Variant = JSON.parse_string(text)
	if v is Dictionary:
		var d: Variant = SavCodec.from_json_safe(v)
		if d is Dictionary:
			return d
	return {}


func _write_planet_entities(planet_id: String) -> void:
	if entities == null or not entities.is_planet_dirty(planet_id):
		return
	var path := "%s/%s" % [planet_dir(current_slot, planet_id), ENTITY_FILE]
	if SavCodec.write_atomic(path, entities.planet_to_dict(planet_id)):
		entities.clear_planet_dirty(planet_id)


func _read_planet_entities(planet_id: String) -> void:
	if entities == null:
		return
	var path := "%s/%s" % [planet_dir(current_slot, planet_id), ENTITY_FILE]
	if not FileAccess.file_exists(path):
		return
	var res := SavCodec.read_with_fallback(path)
	if bool(res["ok"]):
		entities.planet_from_dict(planet_id, res["data"])


## Region data with no `save.dat` beside it is the residue of a session that
## was never saved. Clearing it at boot stops a new game inheriting the ghost
## of an abandoned one.
func _cleanup_orphan_sessions() -> void:
	for slot in SLOT_COUNT:
		if has_save(slot):
			continue
		var pdir := slot_dir(slot) + "/" + PLANET_DIR
		if DirAccess.dir_exists_absolute(pdir):
			_remove_dir(pdir)


static func _remove_dir(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	var d := DirAccess.open(path)
	if d == null:
		return false
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := path + "/" + entry
		if d.current_is_dir():
			_remove_dir(full)
		else:
			DirAccess.remove_absolute(full)
		entry = d.get_next()
	d.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


static func _copy_dir(from: String, to: String) -> bool:
	if not DirAccess.dir_exists_absolute(from):
		return false
	DirAccess.make_dir_recursive_absolute(to)
	var d := DirAccess.open(from)
	if d == null:
		return false
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var src := from + "/" + entry
		var dst := to + "/" + entry
		if d.current_is_dir():
			_copy_dir(src, dst)
		else:
			DirAccess.copy_absolute(src, dst)
		entry = d.get_next()
	d.list_dir_end()
	return true


# ================================================================ diagnostics
## Live counters for the debug overlay.
func stats() -> Dictionary:
	return {
		"slot": current_slot,
		"hot": _hot.size(),
		"hot_hits": _stat_hot_hits,
		"warm_hits": _stat_warm_hits,
		"misses": _stat_misses,
		"written": _stat_written,
		"discarded_unmodified": _stat_discarded,
		"modified_tracked": _known_modified.size(),
		"baselines": _baseline.size(),
		"queued": _queue.size(),
		"regions_open": _regions.size(),
		"flushing": _task_id >= 0,
		"playtime": playtime,
		"last_error": _last_error,
	}


## Human-readable one-liner for the HUD.
func status_line() -> String:
	return "save: hot %d | q %d | wrote %d | skipped %d | hit %.0f%%" % [
		_hot.size(), _queue.size(), _stat_written, _stat_discarded,
		100.0 * float(_stat_hot_hits) / maxf(1.0, float(_stat_hot_hits + _stat_warm_hits + _stat_misses)),
	]


func last_error() -> String:
	return _last_error


## Round-trip a synthetic world through every tier and report. Wired to the
## debug overlay; see `persistence/save_migration.gd`.
func run_self_test() -> Dictionary:
	var t := SavSelfTest.new()
	return t.run_all()
