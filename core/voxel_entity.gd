## Base class for everything that lives in the world and obeys voxel physics:
## the player, monsters, NPCs, item drops, projectiles with gravity.
##
## Entities exist at true 3D positions but *think* in the current view plane:
## `move_dir` is (screen-right, up), which is what makes AI written once work
## identically in all four planes.
class_name VoxelEntity
extends Node3D

signal died(entity: VoxelEntity)
signal damaged(amount: float, element: String, source: Node)
signal landed(fall_distance: float)

@export var box_size := Vector3(0.7, 1.8, 0.7)
@export var max_health := 100.0
@export var gravity_scale := 1.0
@export var move_speed := 6.0
@export var jump_speed := 12.0
@export var faction: StringName = &"neutral"
@export var invulnerable := false
@export var affected_by_liquid := true
## Whether this entity prevents a block being placed in the voxels it
## overlaps. True for actors; item drops and other scenery set it false so
## you can mine a block and immediately place it back.
@export var blocks_placement := true

var health := 100.0
var velocity := Vector3.ZERO
var on_floor := false
var on_ceiling := false
var on_wall := false
var facing := 1                     ## +1 right, -1 left, in plane space
var dead := false
var submersion := 0.0
var fall_start_y := 0.0
var falling := false
var drop_through := false
var iframes := 0.0
var knockback_lock := 0.0

## Layer-shift animation state (set by View.request_shift).
var _shift_from := Vector3.ZERO
var _shift_to := Vector3.ZERO
var _shifting := false
var _shift_t := 0.0

var _last_floor_block := Const.AIR

## Mirror of `global_position` that stays valid after the node leaves the tree.
## Save-on-quit runs from `_exit_tree`, where `global_position` has already
## collapsed to the identity transform — reading it there would persist every
## entity at the world origin.
var _last_global_pos := Vector3.ZERO


func _ready() -> void:
	health = max_health
	add_to_group(&"entities")
	fall_start_y = global_position.y
	_last_global_pos = global_position


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and is_inside_tree():
		_last_global_pos = global_position


## Position that is safe to read at any point in the node lifecycle.
func stable_position() -> Vector3:
	return global_position if is_inside_tree() else _last_global_pos


func get_aabb_size() -> Vector3:
	return box_size


func aabb_center() -> Vector3:
	return global_position + Vector3(0, box_size.y * 0.5, 0)


# ------------------------------------------------------------------- physics
## Standard integration. Subclasses set `velocity` (or use `plane_velocity`)
## then call this from `_physics_process`.
func integrate(delta: float) -> void:
	if _shifting:
		_advance_shift(delta)
		return
	if iframes > 0.0:
		iframes -= delta
	if knockback_lock > 0.0:
		knockback_lock -= delta

	# Terrain that has not streamed in yet reads as air, so an entity standing
	# over an unloaded chunk would accelerate into the void and never come back.
	# Suspend *gravity* across a streaming gap — but keep running the collision
	# step below, so anything spawned slightly embedded still resolves itself.
	var ground_ready := not World.ready_flag or _ground_is_loaded()

	# The world can be written *around* an entity — a structure stamping its
	# fixtures, a player walling someone in, sand collapsing. Extract rather
	# than staying trapped inside solid voxels.
	if ground_ready and not VoxelPhysics.aabb_is_free(global_position, box_size):
		global_position = VoxelPhysics.unstick(global_position, box_size)
		_last_global_pos = global_position

	if affected_by_liquid:
		submersion = VoxelPhysics.liquid_submersion(global_position, box_size)
	var g := Const.GRAVITY * gravity_scale
	if submersion > 0.35:
		g *= 0.32
		velocity *= 1.0 - minf(0.9, 3.5 * delta * submersion)
	if ground_ready:
		velocity.y = maxf(velocity.y - g * delta, -Const.TERMINAL_VELOCITY)
	else:
		velocity.y = 0.0

	var res := VoxelPhysics.move(global_position, box_size, velocity * delta,
		{"drop_through": drop_through, "auto_step": true})
	var was_on_floor := on_floor
	global_position = res["position"]
	_last_global_pos = global_position
	on_floor = res["on_floor"]
	on_ceiling = res["on_ceiling"]
	on_wall = res["on_wall"]
	_last_floor_block = res["floor_block"]

	if res["hit_y"]:
		velocity.y = 0.0
	if res["hit_x"]:
		velocity.x = 0.0
	if res["hit_z"]:
		velocity.z = 0.0

	# Fall damage bookkeeping.
	if not on_floor and velocity.y < -0.1:
		if not falling:
			falling = true
			fall_start_y = global_position.y
	elif on_floor:
		if falling:
			var dist := fall_start_y - global_position.y
			falling = false
			landed.emit(dist)
			_on_landed(dist)
		if not was_on_floor:
			var bt := Blocks.get_type(_last_floor_block)
			Events.play_sound.emit(bt.step_sound, global_position)

	_apply_touch_damage(delta)


## True when the chunk the entity occupies and the one just beneath it are both
## resident. Used to suspend gravity across a streaming gap rather than letting
## entities fall out of the world.
func _ground_is_loaded() -> bool:
	var here := Const.floor_v(global_position)
	if World.chunk_at_block(here) == null:
		return false
	var below := here - Vector3i(0, 1, 0)
	if below.y < 0:
		return true
	return World.chunk_at_block(below) != null


func _on_landed(distance: float) -> void:
	if distance > 6.0 and not invulnerable:
		apply_damage((distance - 6.0) * 4.0, Const.ELEM_PHYSICAL, null)


func _apply_touch_damage(delta: float) -> void:
	if invulnerable or dead:
		return
	for p: Vector3i in VoxelPhysics.overlapping_blocks(global_position, box_size):
		var bt := Blocks.get_type(World.get_block(p))
		if bt.damage_on_touch > 0.0:
			apply_damage(bt.damage_on_touch * delta, bt.damage_element, null)
		if bt.on_entity_inside.is_valid():
			bt.on_entity_inside.call(p, self, delta)


# --------------------------------------------------------------- plane motion
## Horizontal velocity expressed in the current view plane (screen-right).
func plane_velocity() -> float:
	return Const.lateral_of(velocity, View.view)


func set_plane_velocity(lateral: float) -> void:
	var r := View.right()
	velocity.x = lateral * r.x
	velocity.z = lateral * r.z


func plane_position() -> Vector2:
	return View.to_plane(global_position)


func face_toward(world_pos: Vector3) -> void:
	var d := Const.lateral_of(world_pos - global_position, View.view)
	if absf(d) > 0.05:
		facing = 1 if d > 0.0 else -1


func distance_to_entity(other: Node3D) -> float:
	return global_position.distance_to(other.global_position)


## True when `other` shares the player's visible plane (same depth layer).
func in_same_layer(other: Node3D) -> bool:
	return floori(View.depth_of(global_position)) == floori(View.depth_of(other.global_position))


func jump(strength: float = -1.0) -> void:
	if not on_floor:
		return
	velocity.y = jump_speed if strength < 0.0 else strength
	falling = true
	fall_start_y = global_position.y
	Events.play_sound.emit(&"jump", global_position)


# ---------------------------------------------------------------------- combat
func apply_damage(amount: float, element: String = Const.ELEM_PHYSICAL, source: Node = null) -> float:
	if dead or invulnerable or amount <= 0.0:
		return 0.0
	if iframes > 0.0 and element == Const.ELEM_PHYSICAL:
		return 0.0
	var final := modify_incoming_damage(amount, element, source)
	if final <= 0.0:
		return 0.0
	health = maxf(0.0, health - final)
	damaged.emit(final, element, source)
	Events.entity_damaged.emit(self, final, element, source)
	Events.damage_number.emit(aabb_center(), final, element, false)
	if health <= 0.0:
		die(source)
	return final


## Override point for armour / resistances.
func modify_incoming_damage(amount: float, _element: String, _source: Node) -> float:
	return amount


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(max_health, health + amount)


func knockback(dir: Vector3, strength: float) -> void:
	if strength <= 0.0:
		return
	velocity += dir.normalized() * strength
	knockback_lock = 0.18


## `dead` is set BEFORE `on_death()` runs, so a re-entrant `die()` from inside
## an override is a safe no-op. Exploders rely on this: their death blast can
## damage themselves without recursing.
func die(source: Node = null) -> void:
	if dead:
		return
	dead = true
	died.emit(self)
	Events.entity_died.emit(self)
	on_death(source)


## Override for loot, gibs, respawn logic.
func on_death(_source: Node) -> void:
	queue_free()


# ------------------------------------------------------------- layer shifting
func begin_layer_shift(dest: Vector3) -> void:
	_shift_from = global_position
	_shift_to = dest
	_shifting = true
	_shift_t = 0.0


func _advance_shift(delta: float) -> void:
	_shift_t = minf(1.0, _shift_t + delta / maxf(0.001, View.shift_duration))
	var t := ease(_shift_t, 0.4)
	global_position = _shift_from.lerp(_shift_to, t)
	if _shift_t >= 1.0:
		_shifting = false
		global_position = VoxelPhysics.unstick(_shift_to, box_size)


func is_shifting() -> bool:
	return _shifting


func teleport(dest: Vector3) -> void:
	global_position = VoxelPhysics.unstick(dest, box_size)
	_last_global_pos = global_position
	velocity = Vector3.ZERO
	falling = false
	fall_start_y = global_position.y


# ------------------------------------------------------------- serialisation
func save_state() -> Dictionary:
	return {
		"pos": [stable_position().x, stable_position().y, stable_position().z],
		"health": health, "facing": facing, "faction": String(faction),
	}


func load_state(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 0, 0])
	global_position = Vector3(p[0], p[1], p[2])
	health = float(d.get("health", max_health))
	facing = int(d.get("facing", 1))
