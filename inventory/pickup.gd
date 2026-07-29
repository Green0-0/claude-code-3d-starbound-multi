## Magnet pickup: the rule that turns a physical [ItemDrop] into inventory.
##
## Almost everything here is [b]static[/b] — [ItemDrop] calls
## [method update_drop] once per physics frame and that is the whole loop. The
## `Node` half is optional: drop one into the scene (usually as a child of the
## player) and it becomes a live tuning handle that techs and upgrades can
## write to, without anyone needing a reference to it.
##
## [b]Perspective rules.[/b] The world is 3D but the player sees one plane.
## A drop sitting on the player's own depth layer is pulled from far away. A
## drop on another layer is ignored until the player is nearly on top of it,
## and is then [i]peeled[/i] out of its layer toward the player's — the drop
## slides along the depth axis while a `peel` factor (0..1) drives the visual
## squash, so the item visibly leaves the background and joins the play plane.
##
## [codeblock]
## # Give the player something from anywhere in the codebase:
## var leftover := PickupMagnet.give_id(&"raw_iron", 5, player.global_position)
## # leftover > 0 -> inventory was full, the remainder was spilled as a drop.
## [/codeblock]
class_name PickupMagnet
extends Node

## Attraction radius, measured in the view plane, for same-layer drops.
const BASE_RADIUS := 5.0
## Radius used for drops on a different depth layer. Deliberately tight so the
## background does not vacuum itself into the player as they walk past.
const CROSS_LAYER_RADIUS := 1.9
## Depth difference (in voxels) below which a drop counts as "same layer".
const SAME_LAYER_EPSILON := 0.75
## Acceleration applied toward the player, voxels/s².
const PULL_ACCEL := 46.0
const MAX_PULL_SPEED := 17.0
## 3D distance at which the drop is absorbed.
const COLLECT_DISTANCE := 0.85
## How fast a drop slides along the depth axis when peeling into the play layer.
const PEEL_SPEED := 5.5

## Master switch — set false during cutscenes or when the player is dead.
static var enabled := true
## Added to [constant BASE_RADIUS] by techs / augments ("magnet upgrade").
static var radius_bonus := 0.0
## Multiplies pull acceleration. Cheap way to make a "vacuum" tech feel strong.
static var pull_multiplier := 1.0

static var _instance: PickupMagnet = null

@export var start_enabled := true
@export var extra_radius := 0.0


func _ready() -> void:
	_instance = self
	enabled = start_enabled
	radius_bonus = extra_radius


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## The live tuning node, if one was added to the scene. May be null.
static func instance() -> PickupMagnet:
	return _instance


## Effective same-layer attraction radius.
static func radius() -> float:
	return maxf(0.0, BASE_RADIUS + radius_bonus)


# ============================================================== inventory ====
## The player's inventory, or null. Guarded — the player agent's script may not
## expose one yet, and nothing here may crash if it does not.
static func player_inventory() -> Inventory:
	var p := Game.player
	if p == null:
		return null
	var v: Variant = p.get(&"inventory")
	var inv := v as Inventory
	if inv != null:
		return inv
	# During the first frame the player may still be holding the scene host
	# node from `inventory/inventory.tscn`; it exposes the model as `model`.
	var host := v as Object
	if host != null:
		return host.get(&"model") as Inventory
	return null


## Hand `stack` to the player. Returns the leftover count (0 = all taken) and
## emits `Events.item_picked_up` for the part that was taken. The leftover is
## [b]not[/b] spilled — use [method give_or_spill] for that.
static func give(stack: ItemStack, _world_pos: Vector3 = Vector3.ZERO) -> int:
	if stack == null or stack.is_empty():
		return 0
	var item_id := stack.id
	var before := stack.count
	# Pixels are a balance, not a slot item — credit them wherever they arrive.
	if item_id == Pixels.ITEM_ID:
		Pixels.add(before, "pickup")
		stack.clear()
		Events.item_picked_up.emit(String(item_id), before)
		return 0
	var inv := player_inventory()
	var left := before
	if inv != null:
		left = inv.add(stack)
	elif Game.player != null and Game.player.has_method(&"give_item"):
		if bool(Game.player.call(&"give_item", item_id, before)):
			left = 0
			stack.clear()
	var taken := before - left
	if taken > 0:
		Events.item_picked_up.emit(String(item_id), taken)
		Events.play_sound.emit(&"pickup", Vector3.ZERO)
	return left


## Give what fits and drop the rest at `world_pos` as a fresh [ItemDrop] with a
## pickup delay, so a full inventory spits items back out instead of eating
## them. Returns the leftover count that was spilled.
static func give_or_spill(stack: ItemStack, world_pos: Vector3) -> int:
	if stack == null or stack.is_empty():
		return 0
	var item_id := stack.id
	var left := give(stack, world_pos)
	if left > 0:
		spill(item_id, left, world_pos, stack.data)
		Events.toast("Inventory full", "warn")
	return left


## Convenience: build `count` of `id` and hand it over, spilling the remainder.
## Returns the leftover count.
static func give_id(id: StringName, count: int, world_pos: Vector3) -> int:
	if count <= 0 or not Items.has(id):
		return maxi(0, count)
	return give_or_spill(Items.make(id, count), world_pos)


## Spawn a drop that cannot be picked up for a moment (used for spill-back and
## for items the player deliberately throws away).
static func spill(id: StringName, count: int, world_pos: Vector3, data: Dictionary = {}) -> Node:
	var node := Game.spawn_item_drop(world_pos + Vector3(0, 0.4, 0), id, count, data)
	if node != null and node.has_method(&"mark_player_dropped"):
		node.call(&"mark_player_dropped")
	return node


# =================================================================== magnet ====
## Advance the magnet for one drop. Returns true when the drop was absorbed —
## the caller must stop touching it (it has been freed).
##
## `drop` is any [VoxelEntity] exposing `stack: ItemStack` and
## `can_be_picked_up() -> bool`; [ItemDrop] is the one the game uses.
static func update_drop(drop: VoxelEntity, delta: float) -> bool:
	if not enabled or drop == null:
		return false
	var st := drop.get(&"stack") as ItemStack
	if st == null or st.is_empty():
		return false
	var player := Game.player
	if player == null or player.dead:
		_set_magnetised(drop, false)
		return false
	if drop.has_method(&"can_be_picked_up") and not bool(drop.call(&"can_be_picked_up")):
		_set_magnetised(drop, false)
		return false

	var target := player.aabb_center()
	var here := drop.global_position + Vector3(0, drop.box_size.y * 0.5, 0)

	# Plane-space distance: this is what "close" means to the player's eye.
	var plane_delta := View.to_plane(target) - View.to_plane(here)
	var plane_dist := plane_delta.length()
	var depth_delta := View.depth_of(target) - View.depth_of(here)
	var same_layer := absf(depth_delta) <= SAME_LAYER_EPSILON
	var reach := radius() if same_layer else CROSS_LAYER_RADIUS
	if plane_dist > reach:
		_set_magnetised(drop, false)
		return false

	_set_magnetised(drop, true)

	# Peel out of the background: slide along the depth axis toward the player.
	if not same_layer:
		var d := View.depth_of(drop.global_position)
		var want := View.depth_of(player.global_position)
		var moved := move_toward(d, want, PEEL_SPEED * delta)
		drop.global_position = View.with_depth(drop.global_position, moved)
		drop.set(&"peel", clampf(1.0 - absf(want - moved) / maxf(0.001, CROSS_LAYER_RADIUS), 0.0, 1.0))
	else:
		drop.set(&"peel", 1.0)
		# Snap gently onto the exact play layer so the drop never renders behind
		# the player by half a voxel.
		var d2 := View.depth_of(drop.global_position)
		var want2 := View.depth_of(player.global_position)
		if absf(want2 - d2) > 0.02:
			drop.global_position = View.with_depth(
				drop.global_position, move_toward(d2, want2, PEEL_SPEED * delta))

	# Accelerate in the view plane; strength ramps up as it closes in.
	var falloff := 1.0 - clampf(plane_dist / maxf(0.001, reach), 0.0, 1.0)
	var dir := View.plane_dir_to_world(plane_delta.normalized())
	drop.velocity += dir * PULL_ACCEL * pull_multiplier * (0.35 + falloff) * delta
	if drop.velocity.length() > MAX_PULL_SPEED:
		drop.velocity = drop.velocity.normalized() * MAX_PULL_SPEED

	if here.distance_to(target) <= COLLECT_DISTANCE:
		return collect(drop)
	return false


## Absorb a drop immediately, ignoring distance. Returns true if it was taken
## (fully or partially); the node is freed when nothing is left.
static func collect(drop: VoxelEntity) -> bool:
	if drop == null:
		return false
	var st := drop.get(&"stack") as ItemStack
	if st == null or st.is_empty():
		return false
	var pos := drop.global_position
	var left := give(st, pos)
	if left > 0:
		# Inventory filled up mid-pull: bounce the remainder away and cool down.
		drop.velocity = Vector3(0, 4.0, 0) + View.plane_dir_to_world(Vector2(randf_range(-1.0, 1.0), 0.0)) * 2.0
		if drop.has_method(&"set_pickup_delay"):
			drop.call(&"set_pickup_delay", 1.5)
		return false
	Events.spawn_particles.emit("pickup", pos, 4)
	drop.queue_free()
	return true


static func _set_magnetised(drop: VoxelEntity, v: bool) -> void:
	if bool(drop.get(&"magnetised")) != v:
		drop.set(&"magnetised", v)
