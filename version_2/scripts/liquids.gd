class_name Liquids
extends RefCounted

## Liquid flow, falling blocks and the crop growth ticker.
##
## All three are the same shape of problem — a cell wants to become a different
## cell, some number of seconds from now — so they share one budgeted queue.
## The budget matters: a broken dam near a streaming boundary can otherwise
## cascade into thousands of writes in a single frame.

const MAX_UPDATES_PER_TICK := 220
const FLOW_INTERVAL := 0.14
const FALL_INTERVAL := 0.10
const GROW_INTERVAL := 1.0
## How far a liquid will spread horizontally from its source before it stops.
const MAX_SPREAD := 6

var world: VoxelWorld
var game: Node

var _flow: Array[Vector3i] = []
var _flow_set := {}
var _fall: Array[Vector3i] = []
var _fall_set := {}
## planted crop cells -> seconds until the next growth stage
var _crops := {}

var _flow_timer := 0.0
var _fall_timer := 0.0
var _grow_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Called whenever a block changes, so the sim only ever looks at what moved.
func on_block_changed(at: Vector3i) -> void:
	for d: Vector3i in [Vector3i.ZERO, Vector3i.UP, Vector3i.DOWN, Vector3i(1, 0, 0),
			Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var c := at + d
		var id := world.get_block(c.x, c.y, c.z)
		if Blocks.is_liquid(id):
			_queue_flow(c)
		elif Blocks.get_def(id).falls:
			_queue_fall(c)
	# something resting on the changed cell may now have nothing under it
	var above := at + Vector3i.UP
	if Blocks.get_def(world.get_block(above.x, above.y, above.z)).falls:
		_queue_fall(above)


func _queue_flow(c: Vector3i) -> void:
	if _flow_set.has(c):
		return
	_flow_set[c] = true
	_flow.append(c)


func _queue_fall(c: Vector3i) -> void:
	if _fall_set.has(c):
		return
	_fall_set[c] = true
	_fall.append(c)


func plant(at: Vector3i, seconds: float) -> void:
	_crops[at] = seconds


func forget(at: Vector3i) -> void:
	_crops.erase(at)


func tick(delta: float) -> void:
	if world == null:
		return
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		_flow_timer = FLOW_INTERVAL
		_step_flow()
	_fall_timer -= delta
	if _fall_timer <= 0.0:
		_fall_timer = FALL_INTERVAL
		_step_fall()
	_grow_timer -= delta
	if _grow_timer <= 0.0:
		_grow_timer = GROW_INTERVAL
		_step_growth()


# =============================================================================
# flow
# =============================================================================

func _step_flow() -> void:
	var budget := MAX_UPDATES_PER_TICK
	while budget > 0 and not _flow.is_empty():
		budget -= 1
		var c: Vector3i = _flow.pop_front()
		_flow_set.erase(c)
		var id := world.get_block(c.x, c.y, c.z)
		if not Blocks.is_liquid(id):
			continue
		_spread(c, id)


func _spread(c: Vector3i, id: int) -> void:
	# down first: liquid always prefers to fall
	var below := c + Vector3i.DOWN
	if _can_flow_into(below):
		_set_liquid(below, id)
		return
	# then sideways, but only if there is something to stand on
	var spread := 0
	for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
			Vector3i(0, 0, -1)]:
		var side := c + d
		if not _can_flow_into(side):
			continue
		# a source that has already run this far stops, so a spill has an edge
		if _distance_to_drop(side, id) > MAX_SPREAD:
			continue
		_set_liquid(side, id)
		spread += 1
		if spread >= 2:
			return


func _can_flow_into(c: Vector3i) -> bool:
	if c.y < 1 or c.y >= VoxelWorld.WH:
		return false
	if not world.is_loaded(c.x, c.z):
		return false
	var id := world.get_block(c.x, c.y, c.z)
	if id == Blocks.AIR:
		return true
	return Blocks.is_replaceable(id) and not Blocks.is_liquid(id)


## How far this cell is from a place the liquid could fall, laterally. Used as a
## cheap stand-in for pressure, so puddles have a finite radius.
func _distance_to_drop(c: Vector3i, _id: int) -> int:
	for r in range(1, MAX_SPREAD + 2):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var probe := Vector3i(c.x + dx, c.y - 1, c.z + dz)
				if world.get_block(probe.x, probe.y, probe.z) == Blocks.AIR:
					return r
	return MAX_SPREAD + 2


func _set_liquid(c: Vector3i, id: int) -> void:
	# lava meeting water becomes stone, which is the only interaction worth having
	var neighbour_water := false
	var neighbour_lava := false
	for d: Vector3i in [Vector3i.UP, Vector3i.DOWN, Vector3i(1, 0, 0),
			Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n := world.get_block(c.x + d.x, c.y + d.y, c.z + d.z)
		if not Blocks.is_liquid(n):
			continue
		if Blocks.get_def(n).touch_element == Blocks.ELEM_FIRE:
			neighbour_lava = true
		else:
			neighbour_water = true
	var lava_source := Blocks.get_def(id).touch_element == Blocks.ELEM_FIRE
	if (lava_source and neighbour_water) or (not lava_source and neighbour_lava):
		world.set_block(c.x, c.y, c.z, Blocks.id(&"basalt"))
		if game != null:
			game.spawn_impact(Vector3(c) + Vector3(0.5, 0.5, 0.5),
				Color(0.9, 0.9, 0.95))
		return
	world.set_block(c.x, c.y, c.z, id)
	_queue_flow(c)


# =============================================================================
# falling blocks
# =============================================================================

func _step_fall() -> void:
	var budget := MAX_UPDATES_PER_TICK
	while budget > 0 and not _fall.is_empty():
		budget -= 1
		var c: Vector3i = _fall.pop_front()
		_fall_set.erase(c)
		var id := world.get_block(c.x, c.y, c.z)
		if id == Blocks.AIR or not Blocks.get_def(id).falls:
			continue
		var below := c + Vector3i.DOWN
		if below.y < 1:
			continue
		var under := world.get_block(below.x, below.y, below.z)
		if under != Blocks.AIR and not Blocks.is_liquid(under):
			continue
		world.set_block(c.x, c.y, c.z, Blocks.AIR)
		world.set_block(below.x, below.y, below.z, id)
		_queue_fall(below)
		var above := c + Vector3i.UP
		if Blocks.get_def(world.get_block(above.x, above.y, above.z)).falls:
			_queue_fall(above)


# =============================================================================
# crops
# =============================================================================

## Advance every planted crop whose timer has run out. Growth needs light and,
## for thirsty crops, water within a few blocks.
func _step_growth() -> void:
	if _crops.is_empty():
		return
	var done: Array[Vector3i] = []
	for c: Vector3i in _crops:
		if not world.is_loaded(c.x, c.z):
			continue
		var id := world.get_block(c.x, c.y, c.z)
		var info := _crop_info(id)
		if info.is_empty():
			done.append(c)
			continue
		_crops[c] = float(_crops[c]) - GROW_INTERVAL * _growth_rate(c, info)
		if float(_crops[c]) > 0.0:
			continue
		var row: Dictionary = info["row"]
		var stage := int(info["stage"]) + 1
		if stage >= int(row["stages"]):
			done.append(c)
			continue
		var next := Blocks.id(CropTable.stage_block_name(row["id"], stage))
		world.set_block(c.x, c.y, c.z, next)
		if stage >= int(row["stages"]) - 1:
			done.append(c)
		else:
			_crops[c] = float(row["seconds"])
	for c: Vector3i in done:
		_crops.erase(c)


static func _crop_info(block_id: int) -> Dictionary:
	var def := Blocks.get_def(block_id)
	if not def.tags.has(&"crop_stage"):
		return {}
	var parts := String(def.name).split("_stage_")
	if parts.size() != 2:
		return {}
	var row := CropTable.row_of(StringName(parts[0]))
	if row.is_empty():
		return {}
	return {"row": row, "stage": int(parts[1])}


## Watered soil grows at full speed, dry tilled soil at a crawl, and a
## greenhouse panel overhead speeds everything up by a third.
func _growth_rate(c: Vector3i, info: Dictionary) -> float:
	var rate := 1.0
	var soil := world.get_block(c.x, c.y - 1, c.z)
	var soil_def := Blocks.get_def(soil)
	if soil_def.tags.has(&"fertilised"):
		rate *= 1.8
	elif soil_def.tags.has(&"watered"):
		rate *= 1.0
	elif soil_def.tags.has(&"tilled"):
		rate *= 0.35
	else:
		return 0.0
	for dy in range(1, 9):
		if Blocks.get_def(world.get_block(c.x, c.y + dy, c.z)).tags.has(&"greenhouse"):
			rate *= 1.35
			break
	var row: Dictionary = info["row"]
	if bool(row["needs_water"]) and not _water_near(c):
		rate *= 0.4
	return rate


func _water_near(c: Vector3i) -> bool:
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			for dy in range(-1, 2):
				if Blocks.is_liquid(world.get_block(c.x + dx, c.y + dy, c.z + dz)):
					return true
	return false


func save_state() -> Dictionary:
	var rows: Array = []
	for c: Vector3i in _crops:
		rows.append([c.x, c.y, c.z, float(_crops[c])])
	return {"crops": rows}


func load_state(d: Dictionary) -> void:
	_crops.clear()
	for row in d.get("crops", []):
		_crops[Vector3i(int(row[0]), int(row[1]), int(row[2]))] = float(row[3])
