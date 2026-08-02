class_name Player
extends Node3D

## Paper-Mario-style billboard actor with hand-rolled voxel AABB physics.
## Godot's physics server never sees the terrain — a swept box against the
## bitmask field is both faster and far more predictable in a world you can
## rewrite a hundred blocks a second.
##
## The movement core (gravity, the sub-stepped sweep, the auto-step assist and
## the coyote/buffer jump windows) is unchanged. Everything layered on top of it
## — the inventory, tool tiers, weapons, liquids, ladders, hazards and needs —
## reads the same voxel field through the same accessors.

signal stats_changed()
signal died()
signal interacted(target: Node)

const HALF := Vector3(0.32, 0.9, 0.32)   ## half extents; origin sits at the feet
## Crouched, the box is short enough to fit a one-block gap and the sprite
## folds down to match.
const CROUCH_HALF := Vector3(0.32, 0.47, 0.32)
const CROUCH_SPEED := 2.7
const EYE := 1.45
const GRAVITY := 30.0
const JUMP_SPEED := 10.6
const WALK_SPEED := 5.4
const RUN_SPEED := 8.4
const AIR_CONTROL := 0.55
const MAX_FALL := 46.0
const REACH := 5.8
const COYOTE := 0.12
const JUMP_BUFFER := 0.14
const FALL_SAFE := 20.0
const STEP_HEIGHT := 1.0
## Sentinel for "no legal cell", so placement never has to return a Variant.
const NO_CELL := Vector3i(-2147483647, 0, 0)

## liquids and ladders
const SWIM_GRAVITY := 6.0
const SWIM_SPEED := 3.6
const SWIM_RISE := 3.2
const CLIMB_SPEED := 4.4

@export var max_health := 100.0
@export var max_energy := 100.0

var world: VoxelWorld
var rig: CameraRig
var game: Node                      ## set by game.gd; the hub everything reaches through

var velocity := Vector3.ZERO
var on_floor := false
var health := 100.0
var energy := 100.0
var facing_sign := 1.0

var inventory := Inventory.new()
var stats: PlayerStats = null       ## survival needs and status effects

var aim_hit := {}
var mine_target := Vector3i(-9999, 0, 0)
var mine_progress := 0.0
var mine_needed := 1.0
var swing_timer := 0.0

var in_liquid := false
var submerged := false
var on_ladder := false
var crouching := false
var liquid_block := Blocks.AIR

## The live half-extents. Everything in the physics reads this rather than the
## constant, so crouching genuinely changes the shape the world is swept
## against instead of only changing the picture.
var half := HALF

var _coyote := 0.0
var _buffer := 0.0
var _hit_floor := false
var _anim := 0.0
var _step_lerp := 0.0
var _spawn_point := Vector3.ZERO
var _alive := true
var _hazard_tick := 0.0
var _floor_friction := 1.0
var _swing_flash := 0.0
var _crouch_lerp := 0.0

@onready var sprite: Sprite3D = $Sprite
@onready var lantern: OmniLight3D = $Lantern


func _ready() -> void:
	add_to_group(&"player")
	sprite.texture = TexGen.build_character()
	sprite.hframes = TexGen.CH_FRAMES
	sprite.frame = 0
	sprite.pixel_size = 1.9 / float(TexGen.CH_H)   # ~1.9 blocks tall
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.shaded = true
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	sprite.position = Vector3(0, 0.95, 0)
	health = max_health
	energy = max_energy
	stats = PlayerStats.new()
	stats.player = self
	inventory.changed.connect(func() -> void: stats_changed.emit())


func teleport(p: Vector3) -> void:
	global_position = p
	_spawn_point = p
	velocity = Vector3.ZERO


func effective_max_health() -> float:
	return max_health + inventory.bonus("max_health")


func effective_max_energy() -> float:
	return max_energy + inventory.bonus("max_energy")


# =============================================================================
# frame
# =============================================================================

func _physics_process(delta: float) -> void:
	if world == null or rig == null:
		return
	if not _alive:
		return

	_sample_environment()
	_gather_input(delta)
	_integrate(delta)
	_animate(delta)
	_apply_hazards(delta)
	if stats != null:
		stats.tick(delta)

	swing_timer = maxf(swing_timer - delta, 0.0)
	_swing_flash = maxf(_swing_flash - delta, 0.0)
	var regen := 9.0 * (1.0 + inventory.bonus("energy_regen"))
	energy = minf(energy + delta * regen, effective_max_energy())


## Read the blocks the player is standing in and on, once per frame. Everything
## downstream — swimming, climbing, grip, contact damage — comes from here.
func _sample_environment() -> void:
	var feet := feet_block()
	var mid := Vector3i(int(floor(global_position.x)),
		int(floor(global_position.y + half.y)), int(floor(global_position.z)))
	var head := Vector3i(mid.x,
		int(floor(global_position.y + half.y * 2.0 - 0.3)), mid.z)

	var b_mid := world.get_block(mid.x, mid.y, mid.z)
	var b_feet := world.get_block(feet.x, feet.y, feet.z)
	var b_head := world.get_block(head.x, head.y, head.z)

	liquid_block = b_mid if Blocks.is_liquid(b_mid) else (
		b_feet if Blocks.is_liquid(b_feet) else Blocks.AIR)
	in_liquid = liquid_block != Blocks.AIR
	submerged = Blocks.is_liquid(b_head)
	on_ladder = Blocks.is_climbable(b_mid) or Blocks.is_climbable(b_feet)

	var below := world.get_block(feet.x, feet.y - 1, feet.z)
	_floor_friction = Blocks.friction_of(below) if below != Blocks.AIR else 1.0


func _gather_input(delta: float) -> void:
	if game != null and game.get("input_locked"):
		return
	var ix := Input.get_axis(&"move_left", &"move_right")
	var iz := Input.get_axis(&"move_back", &"move_forward")
	var wish := Vector3.ZERO
	if ix != 0.0 or iz != 0.0:
		var fwd := Vector3(rig.axis())
		var right := Vector3(rig.lateral())
		wish = (right * ix + fwd * iz).normalized()

	_update_crouch()

	var can_sprint: bool = energy > 1.0 and wish != Vector3.ZERO and not in_liquid \
		and not crouching
	var sprinting := Input.is_action_pressed(&"sprint") and can_sprint
	var speed := RUN_SPEED if sprinting else WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	speed *= 1.0 + inventory.bonus("move_speed")
	if stats != null:
		speed *= stats.move_multiplier()
	if in_liquid:
		speed = SWIM_SPEED
	if sprinting:
		energy = maxf(energy - delta * 18.0, 0.0)

	# Ice keeps momentum, mud eats it. `friction` multiplies how hard the
	# controller can push the velocity toward what you asked for.
	var grip: float = _floor_friction if on_floor else 1.0
	var accel := 14.0 if on_floor else 14.0 * AIR_CONTROL
	accel *= clampf(grip, 0.08, 1.2)
	var target_v := wish * speed
	velocity.x = move_toward(velocity.x, target_v.x, accel * delta * 3.0)
	velocity.z = move_toward(velocity.z, target_v.z, accel * delta * 3.0)

	# which way the billboard faces, in camera-screen terms
	if wish != Vector3.ZERO:
		var screen_dir := wish.dot(Vector3(rig.lateral()))
		if absf(screen_dir) > 0.05:
			facing_sign = signf(screen_dir)

	if Input.is_action_just_pressed(&"jump"):
		_buffer = JUMP_BUFFER
	_buffer = maxf(_buffer - delta, 0.0)

	# On a ladder, jump climbs and crouch descends; in liquid, jump swims up.
	if on_ladder:
		var climb := 0.0
		if Input.is_action_pressed(&"jump"):
			climb += 1.0
		if Input.is_action_pressed(&"crouch"):
			climb -= 1.0
		if climb != 0.0:
			velocity.y = climb * CLIMB_SPEED
			_buffer = 0.0
		elif velocity.y < 0.0:
			velocity.y = maxf(velocity.y, -1.2)   # cling rather than slide
		return

	if in_liquid:
		if Input.is_action_pressed(&"jump"):
			velocity.y = minf(velocity.y + SWIM_RISE * delta * 8.0, SWIM_RISE)
			_buffer = 0.0
		elif Input.is_action_pressed(&"crouch"):
			velocity.y = maxf(velocity.y - SWIM_RISE * delta * 8.0, -SWIM_RISE)
		return

	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_SPEED * (1.0 + inventory.bonus("jump_speed"))
		_buffer = 0.0
		_coyote = 0.0
		on_floor = false
	elif _buffer > 0.0 and game != null and game.has_method(&"try_air_tech"):
		# double jump and the rest live in the tech manager, not here
		if game.try_air_tech(self):
			_buffer = 0.0


## Crouch while the key is held and there is somewhere to crouch; keep
## crouching afterwards if standing up would put your head in a block.
func _update_crouch() -> void:
	var want: bool = Input.is_action_pressed(&"crouch") and on_floor \
		and not on_ladder and not in_liquid
	if crouching and not want and not _can_stand():
		want = true
	crouching = want
	half = CROUCH_HALF if crouching else HALF


## Only the band of space that standing up would newly occupy matters. Testing
## the whole standing box instead would sample the floor the feet are resting
## on, and a player standing a hair below the integer would never get up again.
func _can_stand() -> bool:
	var lo := CROUCH_HALF.y * 2.0
	var hi := HALF.y * 2.0
	var mid := (lo + hi) * 0.5
	return not world.box_overlaps(global_position + Vector3(0, mid, 0),
		Vector3(HALF.x, (hi - lo) * 0.5, HALF.z))


func _integrate(delta: float) -> void:
	var g := SWIM_GRAVITY if in_liquid else GRAVITY
	if on_ladder:
		g = 0.0
	var terminal := 6.0 if in_liquid else MAX_FALL
	velocity.y = maxf(velocity.y - g * delta, -terminal)

	var was_on_floor := on_floor
	var fall_speed := velocity.y

	# sub-step so we never tunnel through a block at terminal velocity.
	# `on_floor` keeps last frame's value for the duration of the loop so the
	# auto-step assist knows whether we were actually walking.
	var motion := velocity * delta
	var steps := maxi(1, int(ceil(motion.length() / 0.4)))
	var d := motion / float(steps)
	_hit_floor = false
	for i in steps:
		_move_axis(d.x, 0)
		_move_axis(d.z, 2)
		_move_axis(d.y, 1)
	on_floor = _hit_floor

	if on_floor:
		_coyote = COYOTE
		if not was_on_floor and fall_speed < -FALL_SAFE and not in_liquid:
			var dmg := (-fall_speed - FALL_SAFE) * 3.4
			dmg *= 1.0 + inventory.bonus("fall_damage")
			if dmg > 0.0:
				hurt(dmg)
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	if global_position.y < -6.0:
		hurt(9999.0)


func _overlaps(at: Vector3) -> bool:
	return world.box_overlaps(at + Vector3(0, half.y, 0), half)


func _move_axis(amount: float, axis: int) -> void:
	if amount == 0.0:
		return
	var p := global_position
	var before := p
	p[axis] += amount
	# Sneaking never walks you off an edge, which is the whole reason to sneak
	# while building out over a drop.
	if axis != 1 and crouching and on_floor and not _ground_under(p):
		return
	global_position = p
	if not _overlaps(p):
		return

	# Horizontal blockage: try to step up onto a single block first.
	if axis != 1 and on_floor:
		var lifted := p
		lifted.y += STEP_HEIGHT
		if not _overlaps(lifted):
			global_position = lifted
			_step_lerp = STEP_HEIGHT
			return

	# Snap flush against the offending face.
	var lo := before[axis]
	var hi := p[axis]
	for i in 8:
		var mid := (lo + hi) * 0.5
		var t := p
		t[axis] = mid
		if _overlaps(t):
			hi = mid
		else:
			lo = mid
	var res := p
	res[axis] = lo
	global_position = res
	if axis == 1:
		if amount < 0.0:
			_hit_floor = true
			# a bounce block throws you back up instead of stopping you
			var below := world.get_block(int(floor(res.x)),
				int(floor(res.y - 0.1)), int(floor(res.z)))
			var bounce := Blocks.get_def(below).bounce
			if bounce > 0.0 and velocity.y < -4.0:
				velocity.y = -velocity.y * bounce
				return
		velocity.y = 0.0
	else:
		velocity[axis] = 0.0


## Is there anything to stand on beneath the box at this position?
func _ground_under(at: Vector3) -> bool:
	for dx in [-half.x, half.x]:
		for dz in [-half.z, half.z]:
			var c := at + Vector3(dx, -0.06, dz)
			if world.is_solid_at(int(floor(c.x)), int(floor(c.y)), int(floor(c.z))):
				return true
	return false


func _animate(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if not on_floor:
		sprite.frame = 5
	elif crouching and planar <= 0.4:
		_anim = 0.0
		sprite.frame = 0
	elif planar > 0.4:
		_anim += delta * (3.0 + planar * 1.1)
		sprite.frame = 1 + (int(_anim) % 4)
	else:
		_anim = 0.0
		sprite.frame = 0
	sprite.flip_h = facing_sign < 0.0

	# a little squash on landing / stretch in the air, Paper-Mario style, and a
	# deeper fold when crouching so the pose reads at a glance
	_crouch_lerp = lerpf(_crouch_lerp, 1.0 if crouching else 0.0,
		1.0 - exp(-16.0 * delta))
	var target_scale := Vector3.ONE
	if not on_floor:
		target_scale = Vector3(0.94, 1.07, 1.0)
	target_scale = target_scale.lerp(Vector3(1.14, 0.55, 1.0), _crouch_lerp)
	sprite.scale = sprite.scale.lerp(target_scale, 1.0 - exp(-14.0 * delta))

	# keep the lantern between the lens and the sprite, so a Y-billboard is lit
	# face-on instead of edge-on however the camera is turned
	lantern.position = Vector3(0, 1.15, 0) - Vector3(rig.axis()) * 1.1
	var held_light := inventory.bonus("light")
	lantern.omni_range = 9.0 + held_light
	if stats != null and stats.has_effect(&"night_vision"):
		lantern.omni_range += 12.0

	# smooth out auto-step so the camera does not jolt
	if _step_lerp > 0.0:
		_step_lerp = maxf(_step_lerp - delta * 7.0, 0.0)
	sprite.position.y = 0.95 - _step_lerp * 0.35 - _crouch_lerp * 0.42

	# hurt/swing tint
	if _swing_flash > 0.0:
		sprite.modulate = Color(1.4, 1.3, 1.1)
	else:
		sprite.modulate = Color(1, 1, 1)


## Contact damage from every block overlapping the body box, applied per second.
func _apply_hazards(delta: float) -> void:
	_hazard_tick -= delta
	if _hazard_tick > 0.0:
		return
	_hazard_tick = 0.25
	var centre := global_position + Vector3(0, half.y, 0)
	var worst := 0.0
	var element: StringName = Blocks.ELEM_PHYSICAL
	var healing := 0.0
	for x in range(int(floor(centre.x - half.x)), int(floor(centre.x + half.x)) + 1):
		for y in range(int(floor(centre.y - half.y)), int(floor(centre.y + half.y)) + 1):
			for z in range(int(floor(centre.z - half.z)), int(floor(centre.z + half.z)) + 1):
				var id := world.get_block(x, y, z)
				if id == Blocks.AIR:
					continue
				var dmg := Blocks.touch_damage(id)
				if dmg > worst:
					worst = dmg
					element = Blocks.get_def(id).touch_element
				if Blocks.get_def(id).tags.has(&"healing"):
					healing = 6.0
	if worst > 0.0:
		hurt(worst * 0.25, element)
		if element == Blocks.ELEM_FIRE and stats != null:
			stats.apply_effect(&"burning", 4.0)
		elif element == Blocks.ELEM_POISON and stats != null:
			stats.apply_effect(&"poisoned", 6.0)
	if healing > 0.0:
		heal(healing * 0.25)


# =============================================================================
# interaction
# =============================================================================

func update_aim(camera: Camera3D, mouse: Vector2) -> void:
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var hit := world.raycast(from, dir, 200.0, true)
	if hit.get("hit", false):
		var centre: Vector3 = Vector3(hit["block"]) + Vector3(0.5, 0.5, 0.5)
		if centre.distance_to(global_position + Vector3(0, EYE * 0.5, 0)) > reach():
			hit = {"hit": false, "far": true, "block": hit["block"], "normal": hit["normal"]}
	aim_hit = hit


## Reach comes from the held tool, so a drill really is short-armed.
func reach() -> float:
	var t := held_type()
	if t != null and t.kind == Items.Kind.TOOL and t.tool_range > 0.0:
		return t.tool_range
	return REACH


func held_stack() -> Items.Stack:
	return inventory.selected_stack()


func held_type() -> Items.Type:
	var s := held_stack()
	return s.type() if not s.is_empty() else null


## Mining speed multiplier and the ore tier the held tool can recover.
func tool_profile(block_id: int) -> Dictionary:
	var def := Blocks.get_def(block_id)
	var t := held_type()
	var power := 0.55            # bare hands
	var tier := 0
	if t != null and t.kind == Items.Kind.TOOL:
		tier = t.tool_tier
		# the right tool for the job is roughly twice as fast as the wrong one
		power = t.tool_power * (1.0 if _tool_matches(t.tool_kind, def.tool) else 0.45)
	elif t != null and t.kind == Items.Kind.WEAPON:
		power = 0.4
	power *= 1.0 + inventory.bonus("mining_speed")
	if stats != null and stats.has_effect(&"mining_haste"):
		power *= 1.5
	return {"power": maxf(power, 0.08), "tier": tier}


static func _tool_matches(held: StringName, wanted: StringName) -> bool:
	if wanted == &"any" or held == &"beam" or held == &"drill":
		return true
	return held == wanted


func try_mine(delta: float) -> void:
	if not aim_hit.get("hit", false):
		cancel_mine()
		return
	var b: Vector3i = aim_hit["block"]
	var id: int = aim_hit["id"]
	var def := Blocks.get_def(id)
	if not def.breakable or def.hardness < 0.0:
		return
	var profile := tool_profile(id)
	if b != mine_target:
		mine_target = b
		mine_progress = 0.0
		mine_needed = maxf(def.hardness, 0.02)
	mine_progress += delta * float(profile["power"])
	if mine_progress < mine_needed:
		return

	mine_progress = 0.0
	mine_target = Vector3i(-9999, 0, 0)
	break_block(b, int(profile["tier"]))
	# wear the tool one point per block
	var s := held_stack()
	if not s.is_empty() and s.type() != null and s.type().kind == Items.Kind.TOOL:
		if s.damage_durability(1) and game != null:
			game.notify("Your tool broke.", &"warn")
	stats_changed.emit()


## Remove a block and scatter whatever it yields. Shared by mining, explosions
## and the harvest path, so drops behave identically however the block died.
func break_block(b: Vector3i, tool_tier: int) -> void:
	var id := world.get_block(b.x, b.y, b.z)
	if id == Blocks.AIR:
		return
	var def := Blocks.get_def(id)
	if not def.breakable:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var yields := def.roll_drops(tool_tier, rng)
	if yields.is_empty() and def.drops.is_empty() and tool_tier >= def.tier:
		yields.append([Items.item_of_block(id), 1])
	world.edit_block(b.x, b.y, b.z, Blocks.AIR)
	if game != null:
		game.on_block_broken(b, id, yields)


func cancel_mine() -> void:
	mine_target = Vector3i(-9999, 0, 0)
	mine_progress = 0.0


## Right-click: place the held block, or use the held item.
func try_place() -> bool:
	var stack := held_stack()
	if stack.is_empty():
		return false
	var t := stack.type()
	if t == null:
		return false

	if t.kind == Items.Kind.OBJECT:
		return _place_object(stack, t)
	if t.kind == Items.Kind.CONSUMABLE or t.kind == Items.Kind.SEED \
			or t.kind == Items.Kind.TECH:
		return game != null and game.use_item(self, stack)
	if t.place_block == &"":
		return game != null and game.use_item(self, stack)

	var cell := _place_target()
	if cell == NO_CELL:
		return false
	if not _placement_is_clear(cell):
		return false
	if not world.edit_block(cell.x, cell.y, cell.z, Blocks.id(t.place_block)):
		return false
	stack.count -= 1
	if stack.count <= 0:
		stack.clear()
	inventory.changed.emit()
	if game != null:
		game.on_block_placed(cell, Blocks.id(t.place_block))
	return true


func _place_object(stack: Items.Stack, t: Items.Type) -> bool:
	var cell := _place_target()
	if cell == NO_CELL or game == null:
		return false
	if not game.place_object(t.id, cell, self):
		return false
	stack.count -= 1
	if stack.count <= 0:
		stack.clear()
	inventory.changed.emit()
	return true


## The cell a placement would occupy: the neighbour of the aimed face, unless
## the aimed block is replaceable (grass, snow layer) in which case it is that
## block itself.
func _place_target() -> Vector3i:
	if not aim_hit.get("hit", false):
		return NO_CELL
	var b: Vector3i = aim_hit["block"]
	if Blocks.is_replaceable(world.get_block(b.x, b.y, b.z)):
		return b
	var n: Vector3i = aim_hit["normal"]
	return b + n


func _placement_is_clear(cell: Vector3i) -> bool:
	var existing := world.get_block(cell.x, cell.y, cell.z)
	if existing != Blocks.AIR and not Blocks.is_replaceable(existing):
		return false
	# never brick yourself in
	var centre := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var mine := global_position + Vector3(0, half.y, 0)
	if absf(centre.x - mine.x) < half.x + 0.5 \
			and absf(centre.y - mine.y) < half.y + 0.5 \
			and absf(centre.z - mine.z) < half.z + 0.5:
		return false
	if game != null and game.entity_occupies(cell):
		return false
	return true


## Melee swing. The arc is a cone in front of the billboard, which is what makes
## the camera facing matter: turn the camera and you swing somewhere else.
func swing() -> void:
	var t := held_type()
	var speed: float = t.attack_speed if t != null and t.damage > 0.0 else 1.0
	if swing_timer > 0.0:
		return
	swing_timer = 0.42 / maxf(speed, 0.2)
	_swing_flash = 0.12
	if game != null:
		game.player_attack(self, held_stack())


func interact() -> void:
	if game != null:
		game.player_interact(self)


# =============================================================================
# inventory plumbing
# =============================================================================

## Called by ItemDrop before it magnetises, so a full bag does not vacuum.
func can_accept_item(item_id: StringName) -> bool:
	if item_id == &"pixels":
		return true
	if inventory.count_of(item_id) > 0:
		return true
	return not inventory.is_full()


## Take what fits and report the remainder, so the drop can stay on the floor.
func collect_stack(stack: Items.Stack) -> int:
	var before := stack.count
	var left := inventory.add(stack)
	if left < before and game != null:
		game.on_item_picked_up(stack.id, before - left)
	return left


func give(item_id: StringName, count := 1) -> int:
	return inventory.add_item(item_id, count)


func select_slot(i: int) -> void:
	inventory.select(i)
	stats_changed.emit()


func cycle_slot(d: int) -> void:
	inventory.cycle(d)
	stats_changed.emit()


# =============================================================================
# health
# =============================================================================

func hurt(amount: float, element: StringName = Blocks.ELEM_PHYSICAL) -> void:
	if not _alive or amount <= 0.0:
		return
	var reduced := amount
	# flat defence first, then the fractional elemental resistance
	reduced = maxf(reduced - inventory.total_defense() * 0.35, amount * 0.15)
	reduced *= 1.0 - inventory.resistance(element)
	if stats != null:
		reduced = stats.modify_incoming(reduced, element)
	health = maxf(health - reduced, 0.0)
	stats_changed.emit()
	if game != null:
		game.on_player_damaged(reduced, element)
	if health <= 0.0:
		_alive = false
		died.emit()


func heal(amount: float) -> void:
	if not _alive:
		return
	health = minf(health + amount, effective_max_health())
	stats_changed.emit()


func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	stats_changed.emit()
	return true


func respawn() -> void:
	_alive = true
	health = effective_max_health()
	energy = effective_max_energy()
	velocity = Vector3.ZERO
	if stats != null:
		stats.clear_effects()
		stats.reset_needs()
	var p := _spawn_point
	var top := world.column_top(int(floor(p.x)), int(floor(p.z)))
	if top >= 0:
		p.y = float(top + 1)
	global_position = p
	stats_changed.emit()


func set_spawn(p: Vector3) -> void:
	_spawn_point = p


func spawn_point() -> Vector3:
	return _spawn_point


func is_alive() -> bool:
	return _alive


## How far away a creature can hear you. Sprinting carries, walking is ordinary,
## and crouching is close to silent — which is what makes sneaking a tactic
## rather than a pose.
func noise_radius() -> float:
	var speed := Vector2(velocity.x, velocity.z).length()
	if crouching:
		return 3.0 + speed * 0.6
	if speed > RUN_SPEED * 0.8:
		return 26.0
	if speed > 0.6:
		return 15.0
	return 7.0


func is_sneaking() -> bool:
	return crouching


# =============================================================================
# animal handling
# =============================================================================
#
# The one skill the player carries, because taming is the one system that needs
# to be gated by experience rather than by equipment. Every creature has a
# minimum handling level below which it will not tolerate anyone, and the odds
# on a passive attempt scale directly off it.

var handling_xp := 0.0


func handling_skill() -> int:
	# Each level costs a little more than the last, so the early ones come from
	# taming a few poptops and the late ones do not.
	return int(floor(sqrt(handling_xp / 3.0)))


func handling_progress() -> float:
	var lvl := handling_skill()
	var here := 3.0 * float(lvl * lvl)
	var next := 3.0 * float((lvl + 1) * (lvl + 1))
	return clampf((handling_xp - here) / maxf(next - here, 1.0), 0.0, 1.0)


func gain_handling(amount: float) -> void:
	var before := handling_skill()
	handling_xp = maxf(handling_xp + amount, 0.0)
	if handling_skill() > before:
		stats_changed.emit()


## Block the player's feet occupy — the anchor for the whole cutaway system.
func feet_block() -> Vector3i:
	return Vector3i(
		int(floor(global_position.x)),
		int(floor(global_position.y + 0.05)),
		int(floor(global_position.z)))


# =============================================================================
# persistence
# =============================================================================

func save_state() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"spawn": [_spawn_point.x, _spawn_point.y, _spawn_point.z],
		"health": health, "energy": energy,
		"inventory": inventory.to_dict(),
		"handling_xp": handling_xp,
		"stats": stats.save_state() if stats != null else {},
	}


func load_state(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 20, 0])
	global_position = Vector3(p[0], p[1], p[2])
	var s: Array = d.get("spawn", p)
	_spawn_point = Vector3(s[0], s[1], s[2])
	health = float(d.get("health", max_health))
	energy = float(d.get("energy", max_energy))
	inventory.from_dict(d.get("inventory", {}))
	handling_xp = float(d.get("handling_xp", 0.0))
	if stats != null:
		stats.load_state(d.get("stats", {}))
	_alive = health > 0.0
	stats_changed.emit()
