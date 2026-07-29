## Planeshift's player actor — "Paper Mario in a voxel world".
##
## The node is a [VoxelEntity] at a true 3D position, but **every line of
## movement code in this file is written in plane space** (lateral = screen
## right, up = world +Y) through [method VoxelEntity.set_plane_velocity] and
## [method Const.lateral_of]. Nothing here may read `velocity.x` as
## "horizontal": that would break three of the four viewing planes.
##
## Composition — the four sibling scripts each own one concern:
##   * [PlayerInput]        raw actions, buffering, UI/pause gating
##   * [PlayerStats]        health / energy / breath / hunger, death, respawn
##   * [PlayerInteraction]  aiming, mining, placing, interacting
##   * [PlayerVisual]       the procedural paper doll and its animations
##
## Public API other modules may call through `Game.player`:
## [codeblock]
##   give_item(id, count, data) -> bool      take_items(id, count) -> bool
##   held_stack() -> ItemStack               held_type() -> ItemType
##   equipped_stack(slot) -> ItemStack       consume_held(n) -> bool
##   set_inventory(inv)                      inventory            (var)
##   stats / visual / input / interaction    (child nodes)
##   spend_energy(a) -> bool                 add_energy(a)
##   stat_bonus(key) -> float                defense_total() -> float
##   grant_extra_jumps(n)                    set_respawn_point(pos, kind)
##   freeze_input(v)  input_frozen  (var)    pose() -> StringName
##   aim_point() -> Vector3                  aim_target() -> Dictionary
##   is_sprinting()/is_crouching()/is_swimming()/is_climbing()/is_hanging()
## [/codeblock]
class_name PlayerActor
extends VoxelEntity

## Emitted whenever the animation-facing pose changes (&"run", &"swim", ...).
signal pose_changed(from: StringName, to: StringName)
## Emitted the frame a flip finishes and the player regains control.
signal flip_recovered()

# ------------------------------------------------------------------- tuning
const RUN_SPEED := 6.4
const SPRINT_SPEED := 10.2
const CROUCH_SPEED := 2.7
const SWIM_SPEED := 5.0
const SWIM_VERTICAL := 5.2
const CLIMB_SPEED := 4.4

const GROUND_ACCEL := 64.0
const GROUND_DECEL := 58.0
const AIR_ACCEL := 30.0
const AIR_DECEL := 7.0
const TURN_BOOST := 1.9

const JUMP_VELOCITY := 12.6
const AIR_JUMP_VELOCITY := 11.2
const JUMP_CUT := 0.42
const COYOTE_TIME := 0.11

const WALL_SLIDE_SPEED := 3.2
const WALL_JUMP_LATERAL := 8.6
const WALL_JUMP_UP := 11.8
const WALL_JUMP_LOCK := 0.17
const LEDGE_COOLDOWN := 0.32

const HITSTUN := 0.26
const HIT_IFRAMES := 0.7

## How much lateral speed survives a flip. See `_on_flip_started` for the
## reasoning behind "preserve magnitude, keep the *screen* direction".
const FLIP_MOMENTUM_KEEP := 0.6
## Blocks/second the player is quietly slid back onto the centre of their
## depth layer. This motion is purely along the camera axis, so under the
## orthographic projection it moves the sprite exactly zero pixels.
const DEPTH_RECENTRE_SPEED := 3.2

# ------------------------------------------------------------------ children
@onready var visual: PlayerVisual = $Visual
@onready var input: PlayerInput = $Input
@onready var stats: PlayerStats = $Stats
@onready var interaction: PlayerInteraction = $Interaction

# ---------------------------------------------------------------- inventory
## Assigned by the inventory agent (class `Inventory`). Untyped on purpose so
## this file compiles before that module exists.
var inventory = null                                          # noqa: type
## Holds pickups until an inventory is attached, so nothing is ever lost.
var _fallback_bag: Dictionary = {}

# --------------------------------------------------------------- live state
var input_frozen := false
var hitstun := 0.0

var _pose: StringName = &"idle"
var _sprinting := false
var _crouching := false
var _swimming := false
var _on_ladder := false
var _hanging := false
var _wall_side := 0

var _coyote := 0.0
var _air_jumps := 0
var _extra_jumps := 0
var _jump_rising := false
var _drop_timer := 0.0
var _wall_jump_lock := 0.0
var _ledge_cooldown := 0.0
var _ladder_ignore := 0.0
var _no_fall_damage := 0.0

var _flip_lock := 0.0
var _flip_carry := 0.0
var _was_grounded_at_flip := false
var _depth_target := 0.0
var _last_layer := 0

var _bonuses: Dictionary = {}
var _defense := 0.0


func _ready() -> void:
	box_size = Vector3(0.62, 1.75, 0.62)
	max_health = 100.0
	move_speed = RUN_SPEED
	jump_speed = JUMP_VELOCITY
	faction = &"player"
	super._ready()
	add_to_group(&"player")
	Game.player = self

	visual.setup(self)
	stats.setup(self)
	input.setup(self)
	interaction.setup(self)

	_last_layer = View.layer
	_depth_target = float(View.layer) + 0.5
	_adopt_inventory()
	_recompute_bonuses()

	Events.view_flip_started.connect(_on_flip_started)
	Events.view_flip_finished.connect(_on_flip_finished)
	Events.layer_changed.connect(_on_layer_changed)
	Events.inventory_changed.connect(_recompute_bonuses)
	damaged.connect(_on_damaged)


# ============================================================ physics update
func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if dead:
		set_plane_velocity(move_toward(plane_velocity(), 0.0, 24.0 * delta))
		drop_through = false
		integrate(delta)
		return

	# A layer shift is a scripted lerp owned by VoxelEntity; stay out of it.
	if is_shifting():
		integrate(delta)
		return

	input.poll(delta)
	_sense()

	if _control_locked():
		_locked_motion(delta)
	else:
		_control(delta)

	integrate(delta)
	_recentre_depth(delta)

	if _jump_rising and velocity.y <= 0.0:
		_jump_rising = false

	stats.tick(delta)
	if not _control_locked():
		interaction.tick(delta)
	_update_pose()


func _tick_timers(delta: float) -> void:
	_coyote = maxf(0.0, _coyote - delta)
	_drop_timer = maxf(0.0, _drop_timer - delta)
	_wall_jump_lock = maxf(0.0, _wall_jump_lock - delta)
	_ledge_cooldown = maxf(0.0, _ledge_cooldown - delta)
	_ladder_ignore = maxf(0.0, _ladder_ignore - delta)
	_no_fall_damage = maxf(0.0, _no_fall_damage - delta)
	_flip_lock = maxf(0.0, _flip_lock - delta)
	hitstun = maxf(0.0, hitstun - delta)


func _control_locked() -> bool:
	return input_frozen or _flip_lock > 0.0 or hitstun > 0.0 or Game.paused


## Momentum-only motion: gravity and the carried run speed still apply, but the
## player cannot steer. Used during the flip animation and during hitstun.
func _locked_motion(delta: float) -> void:
	drop_through = false
	if hitstun > 0.0:
		return                       # keep the knockback vector VoxelEntity set
	_flip_carry = move_toward(_flip_carry, 0.0, 2.5 * delta)
	set_plane_velocity(_flip_carry)


# ------------------------------------------------------------------- sensing
func _sense() -> void:
	_swimming = submersion > 0.55
	_on_ladder = _ladder_ignore <= 0.0 and _climbable_here()
	_wall_side = _probe_wall()
	if on_floor:
		_coyote = COYOTE_TIME
		_air_jumps = max_air_jumps()
		_hanging = false
	gravity_scale = 0.0 if (_hanging or _on_ladder) else 1.0


func _climbable_here() -> bool:
	var mid := global_position + Vector3(0.0, box_size.y * 0.55, 0.0)
	if Blocks.is_climbable(World.get_block(Const.floor_v(mid))):
		return true
	return Blocks.is_climbable(World.get_block(Const.floor_v(global_position + Vector3(0, 0.25, 0))))


## Which screen side has a wall against the body: +1 right, -1 left, 0 none.
func _probe_wall() -> int:
	var r := Vector3(View.right())
	for s: int in [1, -1]:
		var off := r * (float(s) * (box_size.x * 0.5 + 0.14))
		for h: float in [0.35, box_size.y * 0.55, box_size.y - 0.25]:
			var id := World.get_block(Const.floor_v(global_position + off + Vector3(0, h, 0)))
			if id != Const.AIR and Blocks.is_solid(id) and not Blocks.is_platform(id):
				return s
	return 0


## Friction of the block currently underfoot (ice < 1 < grip pads).
func _floor_friction() -> float:
	if not on_floor:
		return 1.0
	return clampf(Blocks.get_type(_last_floor_block).friction, 0.06, 3.0)


func _target_speed() -> float:
	var s := RUN_SPEED
	if _crouching:
		s = CROUCH_SPEED
	elif _sprinting:
		s = SPRINT_SPEED
	s += stat_bonus("move_speed")
	s *= Status.modifier("move_speed", self)
	s *= Tech.modifier("move_speed")
	return maxf(0.6, s)


# ------------------------------------------------------------------ control
func _control(delta: float) -> void:
	var move := input.move_axis

	_crouching = input.crouch_held and on_floor and not _on_ladder and not _swimming
	_sprinting = input.sprint_held and not _crouching and not _swimming and absf(move) > 0.1

	# Crouch + jump on a one-way platform drops through it.
	if _crouching and input.has_buffered_jump() and Blocks.is_platform(_last_floor_block):
		input.consume_jump()
		_drop_timer = 0.3
		Events.play_sound.emit(&"drop_through", global_position)
	drop_through = _drop_timer > 0.0

	if _swimming:
		_swim(delta, move)
	elif _on_ladder:
		_climb(delta, move)
	elif _hanging:
		_ledge_hang(move)
	else:
		_walk(delta, move)


func _walk(delta: float, move: float) -> void:
	var lat := plane_velocity()
	var top := _target_speed()
	var f := _floor_friction()
	var accel := (GROUND_ACCEL * f) if on_floor else AIR_ACCEL
	var decel := (GROUND_DECEL * f) if on_floor else AIR_DECEL
	if _wall_jump_lock > 0.0:
		accel *= 0.25
		decel *= 0.25

	if absf(move) > 0.05:
		var want := move * top
		if absf(lat) > 0.15 and signf(want) != signf(lat):
			accel *= TURN_BOOST
		lat = move_toward(lat, want, accel * delta)
		facing = 1 if move > 0.0 else -1
	else:
		lat = move_toward(lat, 0.0, decel * delta)
	set_plane_velocity(lat)

	# --- wall slide ---------------------------------------------------------
	var sliding := (not on_floor) and _wall_side != 0 and velocity.y < 0.0 \
		and signf(move) == float(_wall_side)
	if sliding:
		velocity.y = maxf(velocity.y, -WALL_SLIDE_SPEED)
		facing = _wall_side
		fall_start_y = global_position.y      # sliding down a wall is not a fall

	# --- ledge grab ---------------------------------------------------------
	if (not on_floor) and velocity.y < 0.5 and _wall_side == facing \
			and _ledge_cooldown <= 0.0 and not input.crouch_held:
		var top_y := _ledge_top(_wall_side)
		if top_y > -1.0:
			_begin_hang(top_y)
			return

	# --- jumps --------------------------------------------------------------
	if input.has_buffered_jump():
		if _coyote > 0.0:
			input.consume_jump()
			_do_jump(JUMP_VELOCITY)
		elif sliding or (_wall_side != 0 and not on_floor):
			input.consume_jump()
			_do_wall_jump(_wall_side)
		elif _air_jumps > 0:
			input.consume_jump()
			_air_jumps -= 1
			_do_jump(AIR_JUMP_VELOCITY)
			Events.spawn_particles.emit(&"double_jump", global_position, 10)
			visual.play_double_jump()

	# --- variable jump height ----------------------------------------------
	if _jump_rising and velocity.y > 0.0 and not input.jump_held:
		velocity.y *= JUMP_CUT
		_jump_rising = false


func _do_jump(strength: float) -> void:
	velocity.y = strength * Tech.modifier("jump") * Status.modifier("jump", self)
	_coyote = 0.0
	_jump_rising = true
	falling = true
	fall_start_y = global_position.y
	Events.play_sound.emit(&"jump", global_position)
	visual.play_jump()


func _do_wall_jump(side: int) -> void:
	velocity.y = WALL_JUMP_UP
	set_plane_velocity(-float(side) * WALL_JUMP_LATERAL)
	facing = -side
	_wall_jump_lock = WALL_JUMP_LOCK
	_jump_rising = true
	_coyote = 0.0
	fall_start_y = global_position.y
	Events.play_sound.emit(&"jump", global_position)
	Events.spawn_particles.emit(&"wall_kick", global_position, 6)
	visual.play_jump()


# ------------------------------------------------------------------- swimming
func _swim(delta: float, move: float) -> void:
	var lat := plane_velocity()
	var top := SWIM_SPEED * Status.modifier("swim_speed", self)
	if absf(move) > 0.05:
		lat = move_toward(lat, move * top, 26.0 * delta)
		facing = 1 if move > 0.0 else -1
	else:
		lat = move_toward(lat, 0.0, 16.0 * delta)
	set_plane_velocity(lat)

	var v := input.vert_axis
	if input.jump_held or v > 0.1:
		velocity.y = move_toward(velocity.y, SWIM_VERTICAL, 34.0 * delta)
	elif v < -0.1:
		velocity.y = move_toward(velocity.y, -SWIM_VERTICAL * 0.85, 34.0 * delta)
	else:
		# Buoyancy: the player slowly bobs back up to the surface.
		velocity.y = move_toward(velocity.y, 1.1 * submersion, 14.0 * delta)

	# Breaking the surface with jump held launches you out of the water.
	if submersion < 0.72 and input.has_buffered_jump():
		input.consume_jump()
		_do_jump(JUMP_VELOCITY * 0.82)

	_air_jumps = max_air_jumps()
	_hanging = false
	fall_start_y = global_position.y


# ------------------------------------------------------------------ climbing
func _climb(delta: float, move: float) -> void:
	var speed := CLIMB_SPEED * Status.modifier("climb_speed", self)
	velocity.y = input.vert_axis * speed
	if input.vert_axis == 0.0 and on_floor:
		velocity.y = 0.0
	var lat := move_toward(plane_velocity(), move * speed * 0.55, 40.0 * delta)
	set_plane_velocity(lat)
	if absf(move) > 0.05:
		facing = 1 if move > 0.0 else -1

	_air_jumps = max_air_jumps()
	_hanging = false
	fall_start_y = global_position.y

	if input.has_buffered_jump():
		input.consume_jump()
		_ladder_ignore = 0.28
		_on_ladder = false
		gravity_scale = 1.0
		_do_jump(JUMP_VELOCITY * 0.86)


# ---------------------------------------------------------------- ledge grab
## Height of the walkable surface of the ledge on `side`, or -1.0 if there is
## no grabbable ledge there.
func _ledge_top(side: int) -> float:
	if side == 0:
		return -1.0
	var r := Vector3(View.right()) * float(side)
	var probe := global_position + r * (box_size.x * 0.5 + 0.35)
	var chest := Const.floor_v(probe + Vector3(0, box_size.y - 0.5, 0))
	var above := chest + Vector3i(0, 1, 0)
	if not World.is_solid(chest):
		return -1.0
	if World.is_solid(above) or World.is_solid(above + Vector3i(0, 1, 0)):
		return -1.0
	# Need clear air over our own head too, or we would clip into the ceiling.
	if World.is_solid(Const.floor_v(global_position + Vector3(0, box_size.y + 0.15, 0))):
		return -1.0
	# The hang pose must itself be a legal position.
	var top := float(chest.y + 1)
	var hang := global_position
	hang.y = top - box_size.y + 0.42
	if not VoxelPhysics.aabb_is_free(hang, box_size):
		return -1.0
	return top


func _begin_hang(ledge_y: float) -> void:
	_hanging = true
	velocity = Vector3.ZERO
	gravity_scale = 0.0
	global_position.y = ledge_y - box_size.y + 0.42
	facing = _wall_side
	fall_start_y = global_position.y
	_no_fall_damage = 0.25
	Events.play_sound.emit(&"ledge_grab", global_position)
	visual.play_ledge()


func _ledge_hang(move: float) -> void:
	velocity = Vector3.ZERO
	if input.has_buffered_jump():
		input.consume_jump()
		_hanging = false
		gravity_scale = 1.0
		_ledge_cooldown = LEDGE_COOLDOWN
		velocity.y = JUMP_VELOCITY * 0.94
		set_plane_velocity(float(facing) * 3.6)
		_jump_rising = true
		Events.play_sound.emit(&"jump", global_position)
		visual.play_jump()
		return
	if input.crouch_held or signf(move) == float(-facing):
		_hanging = false
		gravity_scale = 1.0
		_ledge_cooldown = LEDGE_COOLDOWN


# ================================================================ flip / shift
## A flip never moves the player in world space, but the *meaning* of the
## velocity vector changes: the axis that was lateral becomes the depth axis.
##
## Momentum rule (chosen for feel, not physics): the run **speed is preserved
## and re-projected onto the new lateral axis with the same screen direction**,
## scaled by [constant FLIP_MOMENTUM_KEEP]. Sprinting right before a flip means
## you are still sprinting right after it — the world turned, you did not.
## Vertical velocity is untouched (jump arcs survive a flip intact) and all
## depth velocity is dropped, which is what keeps the player pinned to the
## plane instead of drifting into the screen.
func _on_flip_started(from_view: int, _to_view: int, dir: int) -> void:
	# View.view is *already* the destination when this fires.
	var old_lateral := Const.lateral_of(velocity, from_view)
	_flip_carry = old_lateral * FLIP_MOMENTUM_KEEP
	velocity.x = 0.0
	velocity.z = 0.0
	set_plane_velocity(_flip_carry)

	_flip_lock = View.flip_duration
	_was_grounded_at_flip = on_floor
	_hanging = false
	_ledge_cooldown = LEDGE_COOLDOWN
	_drop_timer = 0.0
	drop_through = false
	gravity_scale = 1.0
	input.flush()
	interaction.cancel()
	_pick_depth_target()
	visual.play_flip(dir)


func _on_flip_finished(_view: int) -> void:
	_flip_lock = 0.0
	_pick_depth_target()

	# Edge case: the sub-block depth re-centring can slide the player off a
	# one-block ledge that only existed in the old plane. Never charge fall
	# damage for a drop the flip caused, snap down onto anything within a
	# step's reach, and otherwise hand out an extra-generous coyote window so
	# the player can always save themselves.
	fall_start_y = global_position.y
	_no_fall_damage = 0.6
	if _was_grounded_at_flip and not on_floor:
		var g := VoxelPhysics.ground_below(global_position, 1.5)
		if g >= 0.0 and global_position.y - g <= 1.3:
			global_position.y = g
			on_floor = true
			_coyote = COYOTE_TIME
		else:
			_coyote = COYOTE_TIME * 1.8
			Events.spawn_particles.emit(&"flip_slip", global_position, 6)
	if not VoxelPhysics.aabb_is_free(global_position, box_size):
		global_position = VoxelPhysics.unstick(global_position, box_size)
	# The flip re-derived the layer silently (View._recompute_layer does not
	# emit), so resync our own copy or the next shift animates the wrong way.
	_last_layer = View.layer
	visual.end_flip()
	flip_recovered.emit()


func _on_layer_changed(layer: int, _view: int) -> void:
	_depth_target = float(layer) + 0.5
	if is_shifting() or View.shifting:
		visual.play_shift(signi(layer - _last_layer))
	_last_layer = layer


## Pick the depth coordinate the body should settle on: the centre of its own
## voxel layer, unless that would push it into geometry.
func _pick_depth_target() -> void:
	var d := View.depth_of(global_position)
	var centre := floorf(d) + 0.5
	if VoxelPhysics.aabb_is_free(View.with_depth(global_position, centre), box_size):
		_depth_target = centre
	else:
		_depth_target = d


## Slide the body onto the centre of its layer. The motion is parallel to the
## camera's forward axis, so under an orthographic projection it is invisible;
## it exists purely so the 0.62-wide box never straddles two depth layers and
## collides with voxels the slab renderer has dissolved.
func _recentre_depth(delta: float) -> void:
	if is_shifting():
		return
	var d := View.depth_of(global_position)
	var diff := _depth_target - d
	if absf(diff) < 0.002:
		return
	var step := clampf(diff, -DEPTH_RECENTRE_SPEED * delta, DEPTH_RECENTRE_SPEED * delta)
	var np := View.with_depth(global_position, d + step)
	if VoxelPhysics.aabb_is_free(np, box_size):
		global_position = np
	else:
		_depth_target = d


# ==================================================================== damage
func modify_incoming_damage(amount: float, element: String, _source: Node) -> float:
	var def := defense_total()
	var mult := Status.modifier("damage_taken", self) * Tech.modifier("damage_taken")
	if element != Const.ELEM_PHYSICAL:
		def *= 0.6
	return maxf(amount * 0.05, (amount - def * 0.5) * mult)


func _on_damaged(amount: float, element: String, source: Node) -> void:
	iframes = maxf(iframes, HIT_IFRAMES)
	hitstun = maxf(hitstun, HITSTUN)
	_hanging = false
	gravity_scale = 1.0
	Events.player_damaged.emit(amount, element, source)
	Events.screen_shake.emit(minf(1.4, amount * 0.06), 0.18)
	visual.play_hurt()
	if source is Node3D:
		var away := global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length_squared() < 0.001:
			away = Vector3(View.right()) * float(-facing)
		knockback(Vector3(away.normalized().x, 0.7, away.normalized().z), 6.0)


func _on_landed(distance: float) -> void:
	visual.play_land(distance)
	if _no_fall_damage > 0.0:
		return
	super._on_landed(distance)


func on_death(source: Node) -> void:
	# Do NOT free the player; PlayerStats runs the death + respawn cycle.
	stats.begin_death(source)


# ================================================================= inventory
## Attach the inventory model. The inventory agent may call this directly, or
## drop an `inventory.tscn` into `res://inventory/` and it is picked up here.
func set_inventory(inv) -> void:                                # noqa: type
	inventory = inv
	_flush_fallback_bag()
	_recompute_bonuses()


func _adopt_inventory() -> void:
	if inventory != null:
		return
	if ResourceLoader.exists("res://inventory/inventory.tscn"):
		var packed: PackedScene = load("res://inventory/inventory.tscn")
		if packed != null:
			var n: Node = packed.instantiate()
			add_child(n)
			set_inventory(n)


func _flush_fallback_bag() -> void:
	if inventory == null or _fallback_bag.is_empty():
		return
	var pending := _fallback_bag.duplicate()
	_fallback_bag.clear()
	for id: StringName in pending:
		_push_to_inventory(id, int(pending[id]), {})


func _push_to_inventory(item_id: StringName, count: int, data: Dictionary) -> bool:
	if inventory == null:
		return false
	if inventory.has_method(&"add_item"):
		inventory.call(&"add_item", item_id, count, data)
		return true
	if inventory.has_method(&"add"):
		inventory.call(&"add", ItemStack.new(item_id, count, data))
		return true
	if inventory.has_method(&"give"):
		inventory.call(&"give", item_id, count)
		return true
	return false


## Put items in the player's pockets. Safe before the inventory agent lands:
## anything that cannot be stored yet waits in an internal bag.
func give_item(item_id: StringName, count: int = 1, data: Dictionary = {}) -> bool:
	if count <= 0 or not Items.has(item_id):
		return false
	if not _push_to_inventory(item_id, count, data):
		_fallback_bag[item_id] = int(_fallback_bag.get(item_id, 0)) + count
	Events.item_picked_up.emit(String(item_id), count)
	Events.inventory_changed.emit()
	return true


## Remove `count` of `item_id`. Returns false when the player does not have it.
func take_items(item_id: StringName, count: int = 1) -> bool:
	if inventory != null:
		for m: StringName in [&"remove_item", &"take", &"consume"]:
			if inventory.has_method(m):
				var r: Variant = inventory.call(m, item_id, count)
				return true if not (r is bool) else bool(r)
	var have := int(_fallback_bag.get(item_id, 0))
	if have < count:
		return false
	if have == count:
		_fallback_bag.erase(item_id)
	else:
		_fallback_bag[item_id] = have - count
	Events.inventory_changed.emit()
	return true


## The hotbar stack currently in the player's hand, or null.
func held_stack() -> ItemStack:
	if inventory != null:
		for m: StringName in [&"selected_stack", &"held_stack", &"get_selected", &"hotbar_selected"]:
			if inventory.has_method(m):
				var s: Variant = inventory.call(m)
				return s as ItemStack
	return null


func held_type() -> ItemType:
	var s := held_stack()
	if s == null or s.is_empty():
		return null
	return s.type()


## Equipment in an armour slot (`ItemType.SLOT_HEAD` etc.), or null.
func equipped_stack(slot: StringName) -> ItemStack:
	if inventory == null:
		return null
	for m: StringName in [&"equipped", &"get_equipped", &"equipment", &"armor_in"]:
		if inventory.has_method(m):
			var s: Variant = inventory.call(m, slot)
			return s as ItemStack
	return null


## Spend `n` of the held stack (placing a block, eating food).
func consume_held(n: int = 1) -> bool:
	if inventory != null:
		for m: StringName in [&"consume_selected", &"remove_selected", &"take_selected"]:
			if inventory.has_method(m):
				var r: Variant = inventory.call(m, n)
				Events.inventory_changed.emit()
				return true if not (r is bool) else bool(r)
	var s := held_stack()
	if s != null and not s.is_empty():
		s.count = maxi(0, s.count - n)
		if s.count == 0:
			s.clear()
		Events.inventory_changed.emit()
		return true
	return false


# ------------------------------------------------------------------- bonuses
func _recompute_bonuses() -> void:
	_bonuses.clear()
	_defense = 0.0
	for slot: StringName in [ItemType.SLOT_HEAD, ItemType.SLOT_CHEST,
			ItemType.SLOT_LEGS, ItemType.SLOT_BACK]:
		var st := equipped_stack(slot)
		if st == null or st.is_empty():
			continue
		var t := st.type()
		if t == null:
			continue
		_defense += float(st.stat("defense", t.defense))
		for k: String in t.stat_bonuses:
			_bonuses[k] = float(_bonuses.get(k, 0.0)) + float(t.stat_bonuses[k])
	if stats != null:
		stats.on_bonuses_changed()
	if visual != null:
		visual.refresh_equipment()


## Additive bonus for a stat key contributed by equipped gear.
func stat_bonus(key: String) -> float:
	return float(_bonuses.get(key, 0.0))


func defense_total() -> float:
	return _defense + stat_bonus("defense")


# ==================================================================== helpers
func spend_energy(amount: float) -> bool:
	return stats.spend_energy(amount)


func add_energy(amount: float) -> void:
	stats.add_energy(amount)


## The tech agent calls this to grant/revoke extra mid-air jumps.
func grant_extra_jumps(n: int) -> void:
	_extra_jumps = maxi(0, n)


## How many mid-air jumps the player currently has. Double jump only exists
## once the tech module says so, so the base game is a single-jump platformer.
func max_air_jumps() -> int:
	return _extra_jumps + (1 if _double_jump_unlocked() else 0)


func _double_jump_unlocked() -> bool:
	if Tech.has_method(&"has_tech") and bool(Tech.call(&"has_tech", &"double_jump")):
		return true
	var eq: Variant = Tech.get("equipped")
	if eq is Dictionary:
		for v: Variant in (eq as Dictionary).values():
			if StringName(v) == &"double_jump":
				return true
	return false


func set_respawn_point(pos: Vector3, kind: String = "bed") -> void:
	stats.set_respawn_point(pos, kind)


func freeze_input(v: bool) -> void:
	input_frozen = v
	if v:
		input.flush()
		interaction.cancel()


func pose() -> StringName:
	return _pose


func aim_point() -> Vector3:
	return interaction.aim_point()


func aim_target() -> Dictionary:
	return interaction.aim_target()


func is_sprinting() -> bool: return _sprinting
func is_crouching() -> bool: return _crouching
func is_swimming() -> bool: return _swimming
func is_climbing() -> bool: return _on_ladder
func is_hanging() -> bool: return _hanging
func wall_side() -> int: return _wall_side


# ------------------------------------------------------------------- posing
func _update_pose() -> void:
	var p: StringName = &"idle"
	if dead:
		p = &"dead"
	elif hitstun > 0.0:
		p = &"hurt"
	elif _hanging:
		p = &"ledge"
	elif _on_ladder:
		p = &"climb"
	elif _swimming:
		p = &"swim"
	elif not on_floor:
		if _wall_side != 0 and velocity.y < 0.0 and signf(input.move_axis) == float(_wall_side):
			p = &"wall_slide"
		else:
			p = &"jump" if velocity.y > 0.5 else &"fall"
	elif _crouching:
		p = &"crouch"
	elif absf(plane_velocity()) > 0.35:
		p = &"run"
	if p == _pose:
		return
	var was := _pose
	_pose = p
	visual.set_pose(p)
	pose_changed.emit(was, p)


# ------------------------------------------------------------- serialisation
func save_state() -> Dictionary:
	var d := super.save_state()
	d["stats"] = stats.save_state()
	d["extra_jumps"] = _extra_jumps
	d["bag"] = _fallback_bag.duplicate()
	return d


func load_state(d: Dictionary) -> void:
	super.load_state(d)
	if d.has("stats"):
		stats.load_state(d["stats"])
	_extra_jumps = int(d.get("extra_jumps", 0))
	_fallback_bag = (d.get("bag", {}) as Dictionary).duplicate()
	dead = false
	_pose = &"idle"
	_last_layer = View.layer
	_pick_depth_target()
	_flush_fallback_bag()
