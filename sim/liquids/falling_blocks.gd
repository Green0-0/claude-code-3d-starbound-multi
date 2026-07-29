## Gravity for sand, gravel, snow, ash and anything else flagged `falls`.
##
## `World.set_block` calls `Liquids.queue_falling(pos)` for every `falls` block
## it writes, and the solver forwards "a solid below you disappeared" edits here
## too, so nothing else has to remember to poke this module.
##
## Two movement modes, chosen per block and per situation:
##
## * **ENTITY** — spawn a [LiqFallingBlock], a real physics entity that tumbles
##   down, crushes what it lands on and writes itself back as a block. Looks
##   much better, costs a node, so it is reserved for falls the player can
##   actually see (near the camera, more than one block of drop) and capped at
##   [constant MAX_ENTITIES] live at once.
## * **STEP** — move the voxel down one cell per sim tick. Costs nothing, works
##   off-screen and in unloaded-adjacent chunks, and is what a 200-block sand
##   collapse on the far side of the planet gets.
##
## The default is AUTO (entity when visible, step otherwise); per-block
## overrides live in [member modes] and can be changed by any other agent via
## [method set_mode].
class_name LiqFalling
extends RefCounted

enum Mode {
	AUTO,    ## entity when the fall is on-screen, stepping otherwise
	ENTITY,  ## always spawn a falling entity
	STEP,    ## always move the voxel down a cell per tick
}

## Voxels resolved per sim tick. A cascading cliff collapse therefore takes
## several ticks instead of stalling the frame.
const BUDGET := 96
const MAX_ENTITIES := 48
## Falls further than this from the player are stepped, never animated.
const ENTITY_RANGE := 48.0
const MIN_ENTITY_DROP := 2
const MAX_FALL_SCAN := 32
## Damage for being buried by a settling block.
const BURY_DAMAGE := 12.0
const QUEUE_COMPACT := 256
const MAX_QUEUE := 8192

const DOWN := Vector3i(0, -1, 0)
const UP := Vector3i(0, 1, 0)
const H_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Per-block overrides, keyed by block StringName.
var modes: Dictionary = {
	&"sand": Mode.AUTO,
	&"gravel": Mode.AUTO,
	&"red_sand": Mode.AUTO,
	&"ash": Mode.STEP,       ## ash slumps rather than tumbles
	&"snow": Mode.STEP,
	&"snow_block": Mode.STEP,
	&"silt": Mode.STEP,
	&"dust": Mode.STEP,
}

var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _head := 0
var _live_entities := 0
var _stat_settled := 0
var _stat_entities := 0


## Change how one block falls. Other agents may call this at any time.
func set_mode(block_name: StringName, mode: Mode) -> void:
	modes[block_name] = mode


## Queue a voxel for a support check.
func queue(pos: Vector3i) -> void:
	if _queued.size() >= MAX_QUEUE:
		return
	var n := World.normalize(pos)
	if n.y <= 0 or n.y >= Const.WORLD_HEIGHT:
		return
	if _queued.has(n):
		return
	_queued[n] = true
	_queue.append(n)


func reset() -> void:
	_queue.clear()
	_queued.clear()
	_head = 0
	_live_entities = 0


func tick(_sim_tick: int) -> void:
	var n := 0
	# Only entries that were queued *before* this tick are processed: a stepping
	# block re-queues itself one voxel lower, and without this it would fall the
	# whole shaft in a single tick and eat the whole budget doing it.
	var limit := _queue.size()
	while n < BUDGET and _head < limit:
		var p: Vector3i = _queue[_head]
		_head += 1
		_queued.erase(p)
		_resolve(p)
		n += 1
	if _head >= _queue.size():
		_queue.clear()
		_head = 0
	elif _head > QUEUE_COMPACT:
		_queue = _queue.slice(_head)
		_head = 0


func debug_info() -> Dictionary:
	return {
		"queued": _queue.size() - _head,
		"entities": _live_entities,
		"settled": _stat_settled,
		"spawned": _stat_entities,
	}


# ------------------------------------------------------------------ resolve
func _resolve(p: Vector3i) -> void:
	var id := World.get_block(p)
	if id == Const.AIR:
		return
	var bt := Blocks.get_type(id)
	if not bt.falls:
		return
	if World.chunk_at_block(p) == null:
		return
	var below := p + DOWN
	if not _can_displace(below):
		return
	var drop := _fall_distance(p)
	if drop <= 0:
		return
	if _use_entity(bt, p, drop) and _spawn_entity(p, id):
		return
	_step_down(p, id)


## How far this voxel could fall before hitting something, capped.
func _fall_distance(p: Vector3i) -> int:
	var q := p
	var d := 0
	for _i in MAX_FALL_SCAN:
		q += DOWN
		if q.y < 0 or not _can_displace(q):
			break
		d += 1
	return d


## Can a falling block occupy this voxel? Liquids and washable plants yield;
## solids (including one-way platforms) stop the fall.
func _can_displace(q: Vector3i) -> bool:
	if q.y < 0 or q.y >= Const.WORLD_HEIGHT:
		return false
	if World.chunk_at_block(q) == null:
		return false
	var id := World.get_block(q)
	if id == Const.AIR:
		return true
	if Blocks.is_liquid(id):
		return true
	if Blocks.is_solid(id):
		return false
	return Blocks.is_replaceable(id)


func _use_entity(bt: BlockType, p: Vector3i, drop: int) -> bool:
	var mode: int = int(modes.get(bt.name, Mode.AUTO))
	if mode == Mode.STEP:
		return false
	if _live_entities >= MAX_ENTITIES or Game.entities_root == null:
		return false
	if mode == Mode.ENTITY:
		return true
	if drop < MIN_ENTITY_DROP:
		return false
	# AUTO: only animate what the player can plausibly see. Anything in a hidden
	# layer or far away is stepped, which is both cheaper and less distracting.
	if Game.player == null:
		return false
	var centre := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	if Game.player.global_position.distance_to(centre) > ENTITY_RANGE:
		return false
	return absi(View.layer_offset(p)) <= Const.SLAB_BEHIND


func _spawn_entity(p: Vector3i, id: int) -> bool:
	var e := LiqFallingBlock.new()
	e.setup(id)
	var parent: Node = Game.entities_root
	if parent == null:
		return false
	World.set_block(p, Const.AIR, true)
	parent.add_child(e)
	e.global_position = Vector3(p) + Vector3(0.5, 0.0, 0.5)
	e.tree_exited.connect(_on_entity_gone)
	_live_entities += 1
	_stat_entities += 1
	_cascade(p)
	return true


func _on_entity_gone() -> void:
	_live_entities = maxi(0, _live_entities - 1)


## Cheap mode: shove the voxel one cell down and let the automatic re-queue
## from `World.set_block` carry it the rest of the way.
func _step_down(p: Vector3i, id: int) -> void:
	var below := p + DOWN
	_displace_liquid(below)
	if not World.set_block(below, id, true):
		return
	World.set_block(p, Const.AIR, true)
	_bury(below, id)
	_stat_settled += 1
	_cascade(p)
	queue(below)


## Whatever was resting on the voxel we just vacated now has to check itself —
## this is what turns one removed support block into a whole collapsing pile.
## The hole left behind is also a hole in the seabed, so the ocean is told.
func _cascade(p: Vector3i) -> void:
	queue(p + UP)
	Liquids.ocean.on_hole_opened(p)


## Liquid in the way is pushed up a cell if it can be, otherwise it is lost.
func _displace_liquid(q: Vector3i) -> void:
	var id := World.get_block(q)
	if id == Const.AIR or not Blocks.is_liquid(id):
		return
	var liquid := LiqType.name_of_block(id)
	var level := Liquids.level_at(q)
	if liquid != &"" and level > 0:
		var spill := Liquids.add_liquid(q + UP, liquid, level)
		if spill < level:
			for h: Vector3i in H_DIRS:
				if spill >= level:
					break
				spill += Liquids.add_liquid(q + h, liquid, level - spill)
	Liquids.remove_liquid(q, Const.MAX_LIQUID)
	Events.spawn_particles.emit(&"splash_water", Vector3(q) + Vector3(0.5, 0.5, 0.5), 4)


# ------------------------------------------------------------------- settle
## Called by [LiqFallingBlock] when it stops moving. Tries the voxel it rests
## in, then the one above (so two blocks landing on the same tick stack instead
## of eating each other), and finally gives up and drops an item.
func settle(target: Vector3i, block_id: int, source: Node = null) -> void:
	# The live-entity counter is released by `tree_exited`, not here.
	var bt := Blocks.get_type(block_id)
	var spot := target
	if not _can_place(spot):
		spot = target + UP
		if not _can_place(spot):
			_drop_as_item(target, bt)
			return
	_displace_liquid(spot)
	if not World.set_block(spot, block_id, true):
		_drop_as_item(target, bt)
		return
	_stat_settled += 1
	_bury(spot, block_id, source)
	Events.play_sound.emit(bt.step_sound, Vector3(spot) + Vector3(0.5, 0.5, 0.5))
	Events.spawn_particles.emit(&"block_dust", Vector3(spot) + Vector3(0.5, 0.5, 0.5), 8)
	queue(spot)
	_cascade(spot)


func _can_place(q: Vector3i) -> bool:
	if q.y < 0 or q.y >= Const.WORLD_HEIGHT:
		return false
	if World.chunk_at_block(q) == null:
		return false
	var id := World.get_block(q)
	if id == Const.AIR or Blocks.is_liquid(id):
		return true
	return Blocks.is_replaceable(id) and not Blocks.is_solid(id)


func _drop_as_item(pos: Vector3i, bt: BlockType) -> void:
	var centre := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	if Items.has(bt.name):
		Game.spawn_item_drop(centre, bt.name, 1)
	Events.spawn_particles.emit(&"block_dust", centre, 6)


## Entities standing in the voxel a block just settled into are buried: they
## take damage and get shoved up out of the solid, which is far kinder than
## leaving them stuck inside it.
func _bury(q: Vector3i, block_id: int, source: Node = null) -> void:
	if not Blocks.is_solid(block_id):
		return
	var centre := Vector3(q) + Vector3(0.5, 0.5, 0.5)
	var voxel := AABB(Vector3(q), Vector3.ONE)
	for e: VoxelEntity in Game.entities_in_radius(centre, 2.0):
		if e.dead or e is LiqFallingBlock:
			continue
		var s := e.get_aabb_size()
		var box := AABB(e.global_position - Vector3(s.x * 0.5, 0.0, s.z * 0.5), s)
		if not box.intersects(voxel):
			continue
		e.apply_damage(BURY_DAMAGE, Const.ELEM_PHYSICAL, source)
		e.global_position = VoxelPhysics.unstick(e.global_position, s)
		Events.spawn_particles.emit(&"block_dust", e.aabb_center(), 10)
