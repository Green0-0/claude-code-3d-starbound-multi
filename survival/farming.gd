## The farming loop, and the random-tick scheduler that drives it.
##
## ## The crop table
##
## [method crop_table] is the single source of truth for every crop in the game.
## `content/blocks/30_crops.gd` builds the `<crop>_stage_N` blocks from it,
## `content/items/41_seeds.gd` builds the seeds from it and
## `content/items/40_food.gd` builds the raw produce from it. Adding a crop
## means adding one row here.
##
## ## The random-tick scheduler
##
## `BlockType.on_random_tick` had no driver — this is it. Every second we sample
## `RANDOM_TICKS_PER_CHUNK` random voxels *per loaded chunk* and invoke the hook
## on whatever we land on. That is the Minecraft model, and it is what makes
## soil dry out, fires spread and wild plants creep.
##
## Planted crops additionally register a **site**, ticked round-robin on a fixed
## interval, because a purely random sampler over two million loaded voxels
## visits any given block roughly once every three minutes — fine for soil,
## far too coarse for "this stalk of wheat should ripen in a minute". Both paths
## call the *same* `on_random_tick` callable, so there is one growth code path.
##
## ## Perspective
##
## Crops are `Render.CROSS` — two quads crossed at 90°, which is rotationally
## symmetric across all four viewing planes. A farm plot laid out along X reads
## identically after a flip that makes Z the lateral axis: you see the same
## plants from a new side, never an edge-on invisible sliver. Nothing in this
## file uses `.x` as "horizontal"; irrigation and greenhouse searches are done
## in true 3D neighbourhoods so they behave the same in every view.
class_name SrvFarming
extends Node

## Random voxel samples per loaded chunk per second.
const RANDOM_TICKS_PER_CHUNK := 20.0
## Hard ceiling so a stall or a huge streaming radius cannot blow the frame.
const MAX_TICKS_PER_FRAME := 700

## Planted crops get a guaranteed visit this often (seconds).
const SITE_INTERVAL := 1.0
## Sites visited per batch pass.
const SITES_PER_PASS := 48

## How far irrigation reaches, in blocks (3D radius).
const IRRIGATION_RANGE := 4
## How far above a crop a greenhouse panel still counts.
const GREENHOUSE_HEIGHT := 8
## Growth advances a fertilised plot uses up before it reverts.
const FERTILISER_CHARGES := 6

## Multipliers on the time one growth stage takes.
const FERTILISER_SPEED := 0.55
const GREENHOUSE_SPEED := 0.7
const ROTATION_SPEED := 0.85
## Extra produce chance from planting a different crop family than last time.
const ROTATION_YIELD_BONUS := 0.5

var enabled := true
## Scales every growth timer; quests and debug tools may speed this up.
var growth_scale := 1.0

var _rng := RandomNumberGenerator.new()
var _tick_accum := 0.0
var _chunk_keys: Array = []
var _keys_dirty := true

## Vector3i -> last visit time (seconds since world load).
var _sites: Dictionary = {}
var _site_order: Array[Vector3i] = []
var _site_cursor := 0
var _site_timer := 0.0
var _clock := 0.0

var _scan_queue: Array[Vector3i] = []

# Resolved ids, rebuilt whenever the block registry could have changed.
var _tilled := Const.AIR
var _watered := Const.AIR
var _fertilised := Const.AIR
var _greenhouse := Const.AIR
var _irrigation := Const.AIR
var _water := Const.AIR
var _crop_lut: PackedByteArray = PackedByteArray()
## block id -> {"crop": StringName, "stage": int}
var _crop_by_id: Dictionary = {}
## StringName crop -> PackedInt32Array of stage block ids
var _stages_of: Dictionary = {}
## StringName crop -> Dictionary row from the crop table
var _rows: Dictionary = {}

static var _table_cache: Array[Dictionary] = []


func _ready() -> void:
	process_priority = -5
	_rng.randomize()
	_resolve_ids()
	_install_hooks()
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.block_changed.connect(_on_block_changed)
	Events.world_unloaded.connect(_on_world_unloaded)


# ================================================================ crop table
## Every crop in the game. Read by the three content files and by the wild-crop
## decorator; treat the returned rows as read-only.
static func crop_table() -> Array[Dictionary]:
	if not _table_cache.is_empty():
		return _table_cache
	var t: Array[Dictionary] = []
	# ------------------------------------------------------------ staples
	t.append(_row(&"wheat", "Wheat", &"grain", 3, 46.0,
		Color(0.55, 0.72, 0.32), Color(0.87, 0.75, 0.34), 7.0,
		{"biome": &"biome_forest", "yield": [1, 3], "value": 3}))
	t.append(_row(&"corn", "Corn", &"grain", 4, 62.0,
		Color(0.42, 0.68, 0.28), Color(0.96, 0.82, 0.28), 13.0,
		{"biome": &"biome_savannah", "value": 5}))
	t.append(_row(&"rice", "Rice", &"grain", 3, 42.0,
		Color(0.52, 0.74, 0.40), Color(0.90, 0.88, 0.66), 9.0,
		{"biome": &"biome_ocean", "needs_water": true, "yield": [2, 3], "value": 3}))
	t.append(_row(&"beakseed", "Beakseed", &"grain", 3, 58.0,
		Color(0.58, 0.66, 0.34), Color(0.93, 0.73, 0.42), 10.0,
		{"biome": &"biome_savannah", "value": 5}))
	# -------------------------------------------------------------- roots
	t.append(_row(&"potato", "Potato", &"root", 3, 52.0,
		Color(0.36, 0.60, 0.28), Color(0.79, 0.66, 0.42), 12.0,
		{"biome": &"biome_forest", "yield": [2, 4], "value": 4}))
	t.append(_row(&"carrot", "Carrot", &"root", 3, 46.0,
		Color(0.40, 0.66, 0.26), Color(0.93, 0.55, 0.18), 10.0,
		{"biome": &"biome_forest", "yield": [1, 3], "value": 4,
			"effects": [[&"night_vision", 45.0]]}))
	t.append(_row(&"dirturchin", "Dirturchin", &"root", 3, 70.0,
		Color(0.34, 0.40, 0.26), Color(0.44, 0.34, 0.28), 12.0,
		{"biome": &"biome_barren", "value": 8, "light": 0,
			"effects": [[&"defense_up", 40.0]]}))
	# --------------------------------------------------------- vegetables
	t.append(_row(&"tomato", "Tomato", &"vegetable", 3, 54.0,
		Color(0.36, 0.62, 0.28), Color(0.87, 0.20, 0.16), 11.0,
		{"biome": &"biome_forest", "yield": [1, 3], "value": 5}))
	t.append(_row(&"chili", "Chili", &"vegetable", 3, 58.0,
		Color(0.34, 0.60, 0.26), Color(0.86, 0.14, 0.10), 6.0,
		{"biome": &"biome_savannah", "value": 6,
			"effects": [[&"fire_resistance", 60.0]]}))
	t.append(_row(&"pearlpea", "Pearlpea", &"legume", 3, 40.0,
		Color(0.44, 0.70, 0.34), Color(0.88, 0.93, 0.82), 9.0,
		{"biome": &"biome_forest", "yield": [2, 4], "value": 4}))
	t.append(_row(&"eggshoot", "Eggshoot", &"vegetable", 3, 66.0,
		Color(0.46, 0.66, 0.34), Color(0.97, 0.93, 0.80), 14.0,
		{"biome": &"biome_alien", "value": 8}))
	# -------------------------------------------------------------- fibre
	t.append(_row(&"cotton", "Cotton", &"fibre", 3, 64.0,
		Color(0.42, 0.62, 0.32), Color(0.96, 0.96, 0.93), 0.0,
		{"biome": &"biome_desert", "material": true, "yield": [1, 3], "value": 6}))
	t.append(_row(&"sugarcane", "Sugarcane", &"fibre", 3, 38.0,
		Color(0.50, 0.72, 0.34), Color(0.80, 0.87, 0.44), 4.0,
		{"biome": &"biome_jungle", "needs_water": true, "yield": [2, 3], "value": 4}))
	t.append(_row(&"wartweed", "Wartweed", &"alien", 3, 52.0,
		Color(0.42, 0.44, 0.36), Color(0.57, 0.38, 0.48), 0.0,
		{"biome": &"biome_toxic", "material": true, "value": 9, "light": 3}))
	# ------------------------------------------------------------- fruits
	t.append(_row(&"thornfruit", "Thornfruit", &"fruit", 3, 66.0,
		Color(0.44, 0.56, 0.30), Color(0.86, 0.35, 0.30), 12.0,
		{"biome": &"biome_desert", "value": 7, "needs_water": false}))
	t.append(_row(&"grapes", "Grapes", &"fruit", 4, 76.0,
		Color(0.38, 0.58, 0.28), Color(0.56, 0.24, 0.62), 10.0,
		{"biome": &"biome_forest", "perennial": true, "yield": [2, 4], "value": 7}))
	t.append(_row(&"banana", "Banana", &"fruit", 4, 104.0,
		Color(0.34, 0.62, 0.30), Color(0.95, 0.85, 0.28), 16.0,
		{"biome": &"biome_jungle", "perennial": true, "value": 9}))
	t.append(_row(&"pineapple", "Pineapple", &"fruit", 4, 96.0,
		Color(0.40, 0.62, 0.30), Color(0.91, 0.71, 0.22), 18.0,
		{"biome": &"biome_jungle", "value": 10}))
	t.append(_row(&"kiwi", "Kiwi", &"fruit", 4, 82.0,
		Color(0.38, 0.58, 0.30), Color(0.53, 0.63, 0.28), 12.0,
		{"biome": &"biome_jungle", "perennial": true, "value": 8}))
	t.append(_row(&"coffee", "Coffee", &"fruit", 4, 92.0,
		Color(0.32, 0.56, 0.28), Color(0.46, 0.24, 0.14), 4.0,
		{"biome": &"biome_jungle", "perennial": true, "value": 11,
			"produce": &"coffee_beans", "produce_name": "Coffee Beans",
			"material": true}))
	# ---------------------------------------------------- alien signature
	t.append(_row(&"avesmingo", "Avesmingo", &"alien", 4, 86.0,
		Color(0.44, 0.36, 0.62), Color(0.99, 0.62, 0.30), 15.0,
		{"biome": &"biome_alien", "perennial": true, "value": 14,
			"effects": [[&"haste", 60.0]]}))
	t.append(_row(&"boneboo", "Boneboo", &"alien", 4, 116.0,
		Color(0.62, 0.60, 0.54), Color(0.91, 0.89, 0.81), 0.0,
		{"biome": &"biome_barren", "perennial": true, "material": true,
			"value": 16, "light": 0, "needs_water": false}))
	t.append(_row(&"currentcorn", "Currentcorn", &"alien", 3, 72.0,
		Color(0.34, 0.62, 0.66), Color(0.44, 0.86, 1.0), 12.0,
		{"biome": &"biome_alien", "glow": 6, "value": 13,
			"effects": [[&"energised", 90.0]]}))
	t.append(_row(&"feathercrown", "Feathercrown", &"alien", 3, 74.0,
		Color(0.56, 0.62, 0.68), Color(0.88, 0.92, 0.99), 11.0,
		{"biome": &"biome_alien", "value": 13,
			"effects": [[&"gravity_reduced", 45.0]]}))
	t.append(_row(&"neonmelon", "Neonmelon", &"alien", 4, 100.0,
		Color(0.30, 0.58, 0.36), Color(0.36, 1.0, 0.55), 20.0,
		{"biome": &"biome_alien", "perennial": true, "glow": 8, "value": 18,
			"effects": [[&"night_vision", 120.0]]}))
	t.append(_row(&"toxictop", "Toxictop", &"alien", 3, 64.0,
		Color(0.44, 0.56, 0.24), Color(0.63, 0.87, 0.22), 8.0,
		{"biome": &"biome_toxic", "value": 9,
			"effects": [[&"poisoned", 8.0]]}))
	t.append(_row(&"automato", "Automato", &"alien", 3, 78.0,
		Color(0.42, 0.50, 0.46), Color(0.86, 0.35, 0.22), 13.0,
		{"biome": &"biome_alien", "glow": 4, "value": 15,
			"effects": [[&"energised", 60.0]]}))
	t.append(_row(&"diodia", "Diodia", &"alien", 3, 56.0,
		Color(0.40, 0.34, 0.52), Color(0.71, 0.35, 0.86), 8.0,
		{"biome": &"biome_alien", "glow": 7, "value": 11,
			"effects": [[&"glowing", 120.0]]}))
	t.append(_row(&"oculemon", "Oculemon", &"alien", 4, 94.0,
		Color(0.46, 0.52, 0.36), Color(0.89, 0.87, 0.30), 16.0,
		{"biome": &"biome_alien", "perennial": true, "glow": 5, "value": 24,
			"rarity": Const.RARITY_RARE,
			"effects": [[&"phase_sight", 30.0]]}))
	# ------------------------------------------------------------ aquatic
	t.append(_row(&"reefpod", "Reefpod", &"aquatic", 3, 68.0,
		Color(0.28, 0.60, 0.58), Color(0.36, 0.79, 0.73), 12.0,
		{"biome": &"biome_ocean", "aquatic": true, "light": 4, "value": 12,
			"effects": [[&"breathing", 60.0]]}))
	t.append(_row(&"coralcreep", "Coralcreep", &"aquatic", 4, 70.0,
		Color(0.62, 0.40, 0.48), Color(0.96, 0.45, 0.55), 9.0,
		{"biome": &"biome_ocean", "aquatic": true, "perennial": true,
			"light": 4, "glow": 4, "value": 12}))
	_table_cache = t
	return _table_cache


## One crop row. `extra` overrides any default below.
static func _row(id: StringName, display: String, family: StringName, stages: int,
		growth: float, young: Color, ripe: Color, food: float,
		extra: Dictionary = {}) -> Dictionary:
	var d := {
		"id": id,
		"name": display,
		"family": family,
		"stages": maxi(2, stages),
		"growth": growth,
		"young": young,
		"ripe": ripe,
		"food": food,
		"heal": food * 0.25,
		"produce": id,
		"produce_name": display,
		"yield": [1, 2],
		"seeds": [1, 2],
		"light": 7,
		"needs_water": true,
		"perennial": false,
		"aquatic": false,
		"material": false,
		"glow": 0,
		"value": 5,
		"rarity": Const.RARITY_COMMON,
		"biome": &"biome_forest",
		"effects": [],
	}
	for k: String in extra:
		d[k] = extra[k]
	# Perennials regrow from the stage before ripe, so a tree keeps its trunk.
	d["regrow"] = maxi(1, int(d["stages"]) - 2)
	return d


## Row for one crop id, or an empty dictionary.
static func crop_row(id: StringName) -> Dictionary:
	for r: Dictionary in crop_table():
		if r["id"] == id:
			return r
	return {}


## `<crop>_stage_<n>` — the naming convention the block content file uses.
static func stage_block_name(crop: StringName, stage: int) -> StringName:
	return StringName("%s_stage_%d" % [crop, stage])


static func seed_item_name(crop: StringName) -> StringName:
	return StringName(String(crop) + "_seed")


# =================================================================== bootstrap
func _resolve_ids() -> void:
	_tilled = _bid(&"tilled_soil")
	_watered = _bid(&"watered_soil")
	_fertilised = _bid(&"fertilised_soil")
	_greenhouse = _bid(&"greenhouse_panel")
	_irrigation = _bid(&"irrigation_pipe")
	_water = _bid(&"water")
	_crop_lut = PackedByteArray()
	_crop_lut.resize(Blocks.count())
	_crop_by_id.clear()
	_stages_of.clear()
	_rows.clear()
	for row: Dictionary in crop_table():
		var crop: StringName = row["id"]
		_rows[crop] = row
		var ids := PackedInt32Array()
		for s in int(row["stages"]):
			var bid := _bid(stage_block_name(crop, s))
			ids.append(bid)
			if bid != Const.AIR:
				_crop_lut[bid] = 1
				_crop_by_id[bid] = {"crop": crop, "stage": s}
		_stages_of[crop] = ids


static func _bid(n: StringName) -> int:
	if not Blocks.has(n):
		return Const.AIR
	var id: int = Blocks.id(n)
	return id


## Install `on_random_tick` on every crop stage and on the soils. This is the
## documented way gameplay modules attach behaviour to blocks they do not own
## the *definition* of — we own both here, but the hook is still the seam.
func _install_hooks() -> void:
	for row: Dictionary in crop_table():
		var crop: StringName = row["id"]
		for s in int(row["stages"]):
			var bt := Blocks.get_by_name(stage_block_name(crop, s))
			if bt == null:
				continue
			bt.on_random_tick = _crop_random_tick
			bt.on_interact = _crop_interact
			bt.on_neighbour_changed = _crop_neighbour_changed
	for soil: StringName in [&"tilled_soil", &"watered_soil", &"fertilised_soil"]:
		var bt := Blocks.get_by_name(soil)
		if bt != null:
			bt.on_random_tick = _soil_random_tick


# =============================================================== random ticks
func _physics_process(delta: float) -> void:
	if not enabled or Game.paused or not World.ready_flag:
		return
	_clock += delta
	_drain_scan_queue()
	_run_random_ticks(delta)
	_run_site_ticks(delta)


func _run_random_ticks(delta: float) -> void:
	if _keys_dirty:
		_chunk_keys = World.chunks.keys()
		_keys_dirty = false
	var n_chunks := _chunk_keys.size()
	if n_chunks == 0:
		return
	_tick_accum += delta * RANDOM_TICKS_PER_CHUNK * float(n_chunks) * Game.time_scale
	var budget := mini(int(_tick_accum), MAX_TICKS_PER_FRAME)
	if budget <= 0:
		return
	_tick_accum -= float(budget)
	for _i in budget:
		var cp: Vector3i = _chunk_keys[_rng.randi() % n_chunks]
		var c: Chunk = World.chunks.get(cp)
		if c == null or c.empty:
			continue
		var idx := _rng.randi() & (Const.CHUNK_VOL - 1)
		var id := c.blocks[idx]
		if id == Const.AIR:
			continue
		var bt := Blocks.get_type(id)
		if bt.on_random_tick.is_valid():
			bt.on_random_tick.call(c.origin() + Chunk.from_index(idx))


## Guaranteed visits for planted crops, round-robin in small batches.
func _run_site_ticks(delta: float) -> void:
	if _site_order.is_empty():
		return
	_site_timer += delta
	if _site_timer < SITE_INTERVAL / maxf(1.0, ceilf(float(_site_order.size()) / SITES_PER_PASS)):
		return
	_site_timer = 0.0
	var passes := mini(SITES_PER_PASS, _site_order.size())
	for _i in passes:
		if _site_order.is_empty():
			return
		_site_cursor = (_site_cursor + 1) % _site_order.size()
		var pos: Vector3i = _site_order[_site_cursor]
		if not World.has_chunk(Const.chunk_of(pos)):
			_forget_site(pos)
			continue
		var id := World.get_block(pos)
		if id >= _crop_lut.size() or _crop_lut[id] == 0:
			_forget_site(pos)
			continue
		_crop_random_tick(pos)


func _remember_site(pos: Vector3i) -> void:
	var p := World.normalize(pos)
	if _sites.has(p):
		return
	_sites[p] = _clock
	_site_order.append(p)


func _forget_site(pos: Vector3i) -> void:
	if not _sites.has(pos):
		return
	_sites.erase(pos)
	var i := _site_order.find(pos)
	if i >= 0:
		_site_order.remove_at(i)
		if _site_cursor >= i and _site_cursor > 0:
			_site_cursor -= 1


func _on_chunk_loaded(cpos: Vector3i) -> void:
	_keys_dirty = true
	if not _scan_queue.has(cpos):
		_scan_queue.append(cpos)


func _on_chunk_unloaded(cpos: Vector3i) -> void:
	_keys_dirty = true
	for pos: Vector3i in _sites.keys():
		if Const.chunk_of(pos) == cpos:
			_forget_site(pos)


## Newly streamed chunks may contain a farm the player planted an hour ago.
## Scanning 4096 voxels is cheap but not free, so it is queued and drained a
## couple of chunks per frame.
func _drain_scan_queue() -> void:
	var budget := 2
	while budget > 0 and not _scan_queue.is_empty():
		budget -= 1
		var cp: Vector3i = _scan_queue.pop_front()
		var c: Chunk = World.get_chunk(cp)
		if c == null or c.empty:
			continue
		var origin := c.origin()
		var lut_size := _crop_lut.size()
		for i in Const.CHUNK_VOL:
			var id := c.blocks[i]
			if id != Const.AIR and id < lut_size and _crop_lut[id] == 1:
				_remember_site(origin + Chunk.from_index(i))


func _on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	var lut_size := _crop_lut.size()
	if new_id < lut_size and new_id != Const.AIR and _crop_lut[new_id] == 1:
		_remember_site(pos)
	elif old_id < lut_size and old_id != Const.AIR and _crop_lut[old_id] == 1:
		_forget_site(World.normalize(pos))


func _on_world_unloaded() -> void:
	_sites.clear()
	_site_order.clear()
	_site_cursor = 0
	_scan_queue.clear()
	_chunk_keys.clear()
	_keys_dirty = true


# ==================================================================== growth
## `BlockType.on_random_tick` for every crop stage.
func _crop_random_tick(pos: Vector3i) -> void:
	var id := World.get_block(pos)
	var info: Dictionary = _crop_by_id.get(id, {})
	if info.is_empty():
		return
	var crop: StringName = info["crop"]
	var stage: int = info["stage"]
	var row: Dictionary = _rows[crop]
	var p := World.normalize(pos)
	var last := float(_sites.get(p, -1.0))
	var elapsed := (_clock - last) if last >= 0.0 else 12.0
	_remember_site(p)
	_sites[p] = _clock

	if stage >= int(row["stages"]) - 1:
		return                                   # already ripe
	if not _conditions_met(pos, row):
		return

	var seconds := float(row["growth"]) / maxf(0.01, growth_scale)
	seconds *= _speed_multiplier(pos, row)
	var chance := clampf(elapsed / maxf(1.0, seconds), 0.0, 1.0)
	if _rng.randf() > chance:
		return
	_advance(pos, crop, stage + 1)


func _advance(pos: Vector3i, crop: StringName, stage: int) -> void:
	var ids: PackedInt32Array = _stages_of.get(crop, PackedInt32Array())
	if stage >= ids.size() or ids[stage] == Const.AIR:
		return
	World.set_block(pos, ids[stage])
	_remember_site(pos)
	_consume_fertiliser(pos + Vector3i(0, -1, 0))
	Events.spawn_particles.emit(&"grow", Vector3(pos) + Vector3(0.5, 0.4, 0.5), 3)


## Light, moisture and (for aquatic crops) submersion.
func _conditions_met(pos: Vector3i, row: Dictionary) -> bool:
	var below := pos + Vector3i(0, -1, 0)
	var soil := World.get_block(below)
	if bool(row["aquatic"]):
		if not Blocks.is_liquid(World.get_block(pos)) and not Blocks.is_liquid(World.get_block(pos + Vector3i(0, 1, 0))):
			return false
	elif bool(row["needs_water"]) and not _is_moist(below, soil):
		return false

	var need_light := int(row["light"])
	if need_light > 0 and not _in_greenhouse(pos):
		if _light_at(pos) < need_light:
			return false
	return true


## Fertiliser, greenhouse and crop rotation all shorten the stage timer.
func _speed_multiplier(pos: Vector3i, row: Dictionary) -> float:
	var m := 1.0
	var below := pos + Vector3i(0, -1, 0)
	if World.get_block(below) == _fertilised:
		m *= FERTILISER_SPEED
	if _in_greenhouse(pos):
		m *= GREENHOUSE_SPEED
	var tile := _tile_of(below)
	if tile.get("rotated", false):
		m *= ROTATION_SPEED
	# Weather helps: rain waters everything under open sky.
	if Status.weather != null and Status.weather.is_precipitation():
		m *= 0.92
	return m


func _light_at(pos: Vector3i) -> int:
	var c := World.chunk_at_block(pos)
	if c == null:
		return Const.MAX_LIGHT
	var n := World.normalize(pos)
	var i := Chunk.index(n.x & 15, n.y & 15, n.z & 15)
	return c.combined_light(i, Game.daylight)


func _is_moist(below: Vector3i, soil: int) -> bool:
	if soil == _watered or soil == _fertilised:
		return true
	if soil != _tilled:
		# Growing on plain ground is allowed but only when actually irrigated.
		return _water_within(below, 2)
	return _water_within(below, IRRIGATION_RANGE)


## True 3D disc search, so irrigation behaves the same from every viewing plane.
## Only the soil's own level and the one below are checked — that is where a
## channel or a pipe realistically sits, and it keeps this off the hot path.
func _water_within(centre: Vector3i, radius: int) -> bool:
	if _water == Const.AIR and _irrigation == Const.AIR:
		return false
	var r2 := radius * radius
	for dy in [0, -1]:
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if dx * dx + dz * dz > r2:
					continue
				var id := World.get_block(centre + Vector3i(dx, dy, dz))
				if id != Const.AIR and (id == _water or id == _irrigation):
					return true
	return false


## A crop is "in a greenhouse" when a panel sits somewhere above it and the
## column between is not solid rock.
func _in_greenhouse(pos: Vector3i) -> bool:
	if _greenhouse == Const.AIR:
		return false
	for dy in range(1, GREENHOUSE_HEIGHT + 1):
		var id := World.get_block(pos + Vector3i(0, dy, 0))
		if id == _greenhouse:
			return true
		if id != Const.AIR and Blocks.is_opaque(id):
			return false
	return false


# ====================================================================== soil
## `on_random_tick` for the three soil blocks: drying out and reverting.
func _soil_random_tick(pos: Vector3i) -> void:
	var id := World.get_block(pos)
	var above := World.get_block(pos + Vector3i(0, 1, 0))
	var has_crop := above < _crop_lut.size() and above != Const.AIR and _crop_lut[above] == 1

	if id == _watered:
		if not _water_within(pos, IRRIGATION_RANGE) and not _raining_on(pos):
			swap_soil(pos, _tilled)
		return
	if id == _fertilised:
		return                                   # fertiliser holds its moisture
	if id == _tilled:
		if _water_within(pos, IRRIGATION_RANGE) or _raining_on(pos):
			swap_soil(pos, _watered)
		elif not has_crop and _rng.randf() < 0.06:
			var dirt := _bid(&"dirt")
			if dirt != Const.AIR:
				World.set_block(pos, dirt)          # untilled: the record is gone


## Change one soil block into another *keeping its tile data*.
##
## `World.set_block()` deliberately clears the tile data at the index it writes,
## which is right for a normal block swap and wrong for a plot drying out: the
## crop-rotation record and the remaining fertiliser charges must survive. Read,
## write, restore.
func swap_soil(pos: Vector3i, new_id: int) -> void:
	if new_id == Const.AIR:
		return
	var tile := _tile_of(pos).duplicate()
	if not World.set_block(pos, new_id):
		return
	if not tile.is_empty():
		_set_tile(pos, tile)


func _raining_on(pos: Vector3i) -> bool:
	if Status.weather == null or not Status.weather.is_precipitation():
		return false
	var p := pos + Vector3i(0, 1, 0)
	var top := mini(Const.WORLD_HEIGHT - 1, p.y + 40)
	while p.y < top:
		if World.is_opaque(p):
			return false
		p.y += 1
	return true


## Called by the weather system while rain is falling: nudge exposed tilled
## soil to watered without waiting for the random sampler.
func rain_tick(amount: float) -> void:
	if _tilled == Const.AIR or Game.player == null or amount <= 0.0:
		return
	if _rng.randf() > amount * 0.35:
		return
	var origin := Const.floor_v(Game.player.global_position)
	for _i in 3:
		var p := origin + Vector3i(_rng.randi_range(-14, 14), _rng.randi_range(-4, 4),
			_rng.randi_range(-14, 14))
		if World.get_block(p) == _tilled and _raining_on(p):
			World.set_block(p, _watered)


func _tile_of(pos: Vector3i) -> Dictionary:
	var c := World.chunk_at_block(pos)
	if c == null:
		return {}
	var n := World.normalize(pos)
	return c.get_tile_data(Chunk.index(n.x & 15, n.y & 15, n.z & 15))


func _set_tile(pos: Vector3i, d: Dictionary) -> void:
	var c := World.chunk_at_block(pos)
	if c == null:
		return
	var n := World.normalize(pos)
	c.set_tile_data(Chunk.index(n.x & 15, n.y & 15, n.z & 15), d)


func _consume_fertiliser(soil: Vector3i) -> void:
	if World.get_block(soil) != _fertilised:
		return
	var d := _tile_of(soil).duplicate()
	var left := int(d.get("fert", FERTILISER_CHARGES)) - 1
	if left <= 0:
		d.erase("fert")
		swap_soil(soil, _watered if _watered != Const.AIR else _tilled)
		_set_tile(soil, d)
	else:
		d["fert"] = left
		_set_tile(soil, d)


# ================================================================ player verbs
## Turn a soil block into tilled soil. Returns false when the block is not
## tillable or something is sitting on top of it.
func till(pos: Vector3i, _user: Node = null) -> bool:
	if _tilled == Const.AIR:
		return false
	var bt := World.block_type_at(pos)
	if bt.id == Const.AIR or not (bt.has_tag(&"soil") or bt.has_tag(&"sand")):
		return false
	if bt.has_tag(&"hazard"):
		return false
	var above := World.get_block(pos + Vector3i(0, 1, 0))
	if above != Const.AIR and not Blocks.is_replaceable(above):
		return false
	if not World.set_block(pos, _tilled):
		return false
	Events.play_sound.emit(&"till", Vector3(pos) + Vector3(0.5, 1.0, 0.5))
	Events.spawn_particles.emit(&"dirt_puff", Vector3(pos) + Vector3(0.5, 1.0, 0.5), 6)
	return true


## Water a tilled plot (the watering can, or a bucket).
func water(pos: Vector3i, _user: Node = null) -> bool:
	if _watered == Const.AIR:
		return false
	var id := World.get_block(pos)
	if id == _watered or id == _fertilised:
		return true
	if id != _tilled:
		return false
	swap_soil(pos, _watered)
	Events.play_sound.emit(&"splash", Vector3(pos) + Vector3(0.5, 1.0, 0.5))
	Events.spawn_particles.emit(&"water_drip", Vector3(pos) + Vector3(0.5, 1.0, 0.5), 8)
	return true


## Fertilise a plot: faster growth for `FERTILISER_CHARGES` stage advances.
func fertilise(pos: Vector3i, _user: Node = null) -> bool:
	if _fertilised == Const.AIR:
		return false
	var id := World.get_block(pos)
	if id != _tilled and id != _watered and id != _fertilised:
		return false
	var tile := _tile_of(pos).duplicate()
	swap_soil(pos, _fertilised)
	tile["fert"] = FERTILISER_CHARGES
	_set_tile(pos, tile)
	Events.spawn_particles.emit(&"grow", Vector3(pos) + Vector3(0.5, 1.0, 0.5), 10)
	return true


## Plant `crop` on the soil block at `soil_pos`; the seedling goes above it.
func plant(crop: StringName, soil_pos: Vector3i, _user: Node = null) -> bool:
	var row: Dictionary = _rows.get(crop, {})
	if row.is_empty():
		return false
	var target := soil_pos + Vector3i(0, 1, 0)
	var ids: PackedInt32Array = _stages_of.get(crop, PackedInt32Array())
	if ids.is_empty() or ids[0] == Const.AIR:
		return false
	var here := World.get_block(target)
	var aquatic := bool(row["aquatic"])
	if here != Const.AIR and not Blocks.is_replaceable(here) \
			and not (aquatic and Blocks.is_liquid(here)):
		return false

	var soil := World.get_block(soil_pos)
	if aquatic:
		if not Blocks.is_solid(soil):
			return false
	elif soil != _tilled and soil != _watered and soil != _fertilised:
		return false

	if not World.set_block(target, ids[0]):
		return false
	_remember_site(target)

	# Crop rotation: planting a different family than last time earns a bonus.
	var tile := _tile_of(soil_pos)
	var last: StringName = StringName(tile.get("family", &""))
	tile["rotated"] = last != &"" and last != StringName(row["family"])
	tile["family"] = String(row["family"])
	_set_tile(soil_pos, tile)

	Events.play_sound.emit(&"plant", Vector3(target) + Vector3(0.5, 0.2, 0.5))
	return true


## Harvest whatever crop is at `pos`. Returns true when something was taken.
##
## Ripe annuals are pulled up entirely; perennials fall back to their `regrow`
## stage so the plant survives. Immature crops are left alone — bumping into
## your own wheat field should never destroy it.
func harvest(pos: Vector3i, user: Node = null) -> bool:
	var id := World.get_block(pos)
	var info: Dictionary = _crop_by_id.get(id, {})
	if info.is_empty():
		return false
	var crop: StringName = info["crop"]
	var stage: int = info["stage"]
	var row: Dictionary = _rows[crop]
	if stage < int(row["stages"]) - 1:
		return false

	var soil := pos + Vector3i(0, -1, 0)
	var tile := _tile_of(soil)
	var bonus := ROTATION_YIELD_BONUS if bool(tile.get("rotated", false)) else 0.0
	var luck := Status.modifier("luck", user if user != null else Game.player)

	var span: Array = row["yield"]
	var amount := _rng.randi_range(int(span[0]), int(span[1]))
	amount = maxi(1, int(round(float(amount) * (1.0 + bonus) * luck)))
	var centre := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	_give(user, StringName(row["produce"]), amount, centre)

	var seed_span: Array = row["seeds"]
	var seeds := _rng.randi_range(int(seed_span[0]), int(seed_span[1]))
	if seeds > 0:
		_give(user, seed_item_name(crop), seeds, centre)

	if bool(row["perennial"]):
		_advance(pos, crop, int(row["regrow"]))
	else:
		World.set_block(pos, Const.AIR)
		_forget_site(World.normalize(pos))
		# Clear the rotation flag: it is spent.
		tile["rotated"] = false
		_set_tile(soil, tile)

	Events.play_sound.emit(&"harvest", centre)
	Events.spawn_particles.emit(&"leaf", centre, 6)
	return true


func _give(user: Node, item: StringName, count: int, at: Vector3) -> void:
	if count <= 0 or not Items.has(item):
		return
	if user != null and user.has_method(&"give_item") and bool(user.call(&"give_item", item, count)):
		Events.item_picked_up.emit(String(item), count)
		return
	Game.spawn_item_drop(at, item, count)


## `on_interact` for crop blocks — right-clicking a ripe plant harvests it.
func _crop_interact(pos: Vector3i, player: Node) -> bool:
	return harvest(pos, player)


## A crop with nothing solid under it falls over.
func _crop_neighbour_changed(pos: Vector3i, from: Vector3i) -> void:
	if from != pos + Vector3i(0, -1, 0):
		return
	var below := World.get_block(pos + Vector3i(0, -1, 0))
	var id := World.get_block(pos)
	var info: Dictionary = _crop_by_id.get(id, {})
	if info.is_empty():
		return
	var row: Dictionary = _rows[info["crop"]]
	if bool(row["aquatic"]):
		return
	if below == Const.AIR or Blocks.is_liquid(below):
		World.break_block(pos, 99, true)


# ================================================================== queries
## Is `id` any stage of any crop?
func is_crop_block(id: int) -> bool:
	return id > 0 and id < _crop_lut.size() and _crop_lut[id] == 1


## `{"crop": StringName, "stage": int}` or an empty dictionary.
func crop_info(id: int) -> Dictionary:
	var info: Dictionary = _crop_by_id.get(id, {})
	return info


## Ripe? Used by the tools agent to decide between "harvest" and "mine".
func is_ripe(pos: Vector3i) -> bool:
	var info: Dictionary = _crop_by_id.get(World.get_block(pos), {})
	if info.is_empty():
		return false
	return int(info["stage"]) >= int(_rows[info["crop"]]["stages"]) - 1


func planted_count() -> int:
	return _site_order.size()


# ============================================================== serialisation
func save_state() -> Dictionary:
	return {"growth_scale": growth_scale, "enabled": enabled}


func load_state(d: Dictionary) -> void:
	growth_scale = maxf(0.01, float(d.get("growth_scale", 1.0)))
	enabled = bool(d.get("enabled", true))
	_sites.clear()
	_site_order.clear()
	_site_cursor = 0
	# Sites are rediscovered as chunks stream back in.
	for cp: Vector3i in World.loaded_chunk_positions():
		_scan_queue.append(cp)
