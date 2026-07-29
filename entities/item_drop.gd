## A physical [ItemStack] lying in the world: what a mined block, a dead
## monster or a thrown item becomes.
##
## Everything is built procedurally — the visual is a billboard quad textured
## from `Atlas.item_icon()` when the render agent has one, and a flat coloured
## quad tinted by the item's `icon_color` when it does not. There are no binary
## assets anywhere in the chain.
##
## [b]Lifecycle[/b]
## [br]1. `setup(stack)` — called by `Game.spawn_item_drop()` before the node
##    enters the tree. This is the only required entry point.
## [br]2. A spawn pop: the drop is launched in a small arc in the view plane and
##    scales up from nothing.
## [br]3. Immunity frames: for [member pickup_delay] seconds the drop cannot be
##    collected, so an item the player throws away does not fly straight back.
## [br]4. Merging: identical drops within [constant MERGE_RADIUS] on the same
##    depth layer fuse into the older one, which is what keeps a big mining
##    session from spawning three hundred entities.
## [br]5. Despawn: after [constant DESPAWN_TIME] the drop blinks for the last
##    [constant WARN_TIME] seconds and vanishes. Quest and Essential-rarity
##    items never despawn.
class_name ItemDrop
extends VoxelEntity

## Seconds before a drop disappears.
const DESPAWN_TIME := 300.0
## How long the "about to vanish" blink lasts.
const WARN_TIME := 12.0
## Drops closer than this (and on the same layer) fuse together.
const MERGE_RADIUS := 1.15
## Seconds between merge / hazard checks.
const MERGE_INTERVAL := 0.5
## Above this many live drops the oldest are culled aggressively.
const SOFT_ENTITY_CAP := 220
## Default immunity after spawning, so the pop-arc is visible.
const DEFAULT_PICKUP_DELAY := 0.55
## Immunity applied to an item the player deliberately threw away.
const THROWN_PICKUP_DELAY := 1.25

const ICON_SIZE := 0.55
const BOB_HEIGHT := 0.07
const SPIN_SPEED := 2.4

## The goods. Never null after `setup`; freed when it empties.
var stack: ItemStack = null
## Seconds since spawn.
var age := 0.0
## Remaining immunity. While > 0 the magnet ignores this drop.
var pickup_delay := DEFAULT_PICKUP_DELAY
## Set by [PickupMagnet] while the drop is being pulled in.
var magnetised := false
## 0 = fully in a background layer, 1 = on the player's play layer. Driven by
## the magnet's "peel" and used here to squash the quad as it crosses over.
var peel := 1.0
## Quest items and Essential rarity survive forever.
var never_despawn := false

var _icon: MeshInstance3D = null
var _glow: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _glow_mat: StandardMaterial3D = null
var _bob_phase := 0.0
var _spin := 0.0
var _pop := 0.0
var _merge_timer := 0.0
var _base_alpha := 1.0


func _ready() -> void:
	blocks_placement = false  # a floating drop must not veto placing a block
	box_size = Vector3(0.34, 0.34, 0.34)
	max_health = 1.0
	gravity_scale = 1.0
	invulnerable = true
	affected_by_liquid = true
	faction = &"neutral"
	super._ready()
	add_to_group(&"item_drops")
	_bob_phase = randf() * TAU
	_spin = randf() * TAU
	_merge_timer = randf() * MERGE_INTERVAL
	_build_visual()
	_pop_arc()
	_cull_if_swarming()


## Give this drop its contents. Called by `Game.spawn_item_drop()` before the
## node is added to the tree; safe to call again afterwards to re-skin it.
func setup(p_stack: ItemStack) -> void:
	stack = p_stack
	if stack != null:
		var t := stack.type()
		never_despawn = t != null and (t.kind == ItemType.Kind.QUEST or t.rarity >= Const.RARITY_ESSENTIAL)
	if is_inside_tree():
		_build_visual()


## True when the magnet is allowed to take this drop.
func can_be_picked_up() -> bool:
	return pickup_delay <= 0.0 and stack != null and not stack.is_empty() and not dead


## Extend the immunity window (used when an inventory-full pickup bounces).
func set_pickup_delay(seconds: float) -> void:
	pickup_delay = maxf(pickup_delay, seconds)


## Flag this drop as deliberately thrown away by the player: longer immunity
## and a shove away from whoever dropped it.
func mark_player_dropped() -> void:
	pickup_delay = THROWN_PICKUP_DELAY
	var away := 1.0
	if Game.player != null:
		var d := View.lateral_of(global_position) - View.lateral_of(Game.player.global_position)
		away = 1.0 if d >= 0.0 else -1.0
	set_plane_velocity(away * randf_range(2.5, 4.0))
	velocity.y = randf_range(4.5, 6.0)


# ================================================================== physics ====
func _physics_process(delta: float) -> void:
	if stack == null or stack.is_empty():
		queue_free()
		return
	age += delta
	if pickup_delay > 0.0:
		pickup_delay -= delta

	if PickupMagnet.update_drop(self, delta):
		return  # absorbed; this node is gone

	gravity_scale = 0.0 if magnetised else 1.0
	if magnetised:
		# Cancel residual fall so the pull reads as a clean arc into the player.
		velocity.y = maxf(velocity.y, -2.0)
	elif on_floor:
		set_plane_velocity(move_toward(plane_velocity(), 0.0, 26.0 * delta))

	integrate(delta)

	_merge_timer -= delta
	if _merge_timer <= 0.0:
		_merge_timer = MERGE_INTERVAL
		if _burn_check():
			return
		_try_merge()

	if not never_despawn and age >= DESPAWN_TIME:
		queue_free()


## Items dropped into lava burn away instead of bobbing on it forever.
func _burn_check() -> bool:
	for p: Vector3i in VoxelPhysics.overlapping_blocks(global_position, box_size):
		var bt := Blocks.get_type(World.get_block(p))
		if bt != null and bt.damage_on_touch >= 6.0 and bt.damage_element == Const.ELEM_FIRE:
			Events.spawn_particles.emit("burn", global_position, 3)
			Events.play_sound.emit(&"burn", global_position)
			queue_free()
			return true
	return false


## Fuse with nearby identical drops. The older drop always wins so the merged
## entity keeps the earlier despawn deadline and the result is deterministic.
func _try_merge() -> void:
	if stack == null or stack.is_empty() or stack.count >= stack.max_stack():
		return
	var r2 := MERGE_RADIUS * MERGE_RADIUS
	for n: Node in get_tree().get_nodes_in_group(&"item_drops"):
		var o := n as ItemDrop
		if o == null or o == self or not is_instance_valid(o):
			continue
		if o.stack == null or o.stack.is_empty():
			continue
		if not stack.can_merge_with(o.stack):
			continue
		if global_position.distance_squared_to(o.global_position) > r2:
			continue
		if not in_same_layer(o):
			continue
		# Younger drop yields to older; ties broken by instance id.
		if o.age > age or (o.age == age and o.get_instance_id() > get_instance_id()):
			continue
		if stack.merge_from(o.stack) > 0:
			pickup_delay = maxf(pickup_delay, o.pickup_delay)
			_pop = 0.55  # little bump so the fusion is visible
			if o.stack.is_empty():
				o.queue_free()
			if stack.count >= stack.max_stack():
				return


## Hard backstop against entity explosions during a long mining run: when the
## world is drowning in drops, the oldest non-quest drop makes way.
func _cull_if_swarming() -> void:
	var drops := get_tree().get_nodes_in_group(&"item_drops")
	if drops.size() <= SOFT_ENTITY_CAP:
		return
	var oldest: ItemDrop = null
	for n: Node in drops:
		var o := n as ItemDrop
		if o == null or o == self or o.never_despawn:
			continue
		if oldest == null or o.age > oldest.age:
			oldest = o
	if oldest != null:
		oldest.queue_free()


# ================================================================== visuals ====
func _build_visual() -> void:
	if stack == null:
		return
	var t := stack.type()
	if _icon == null:
		_icon = MeshInstance3D.new()
		_icon.name = "Icon"
		_icon.layers = Const.RL_ENTITIES
		add_child(_icon)
	var quad := QuadMesh.new()
	quad.size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.mesh = quad
	_icon.position = Vector3(0, box_size.y * 0.5 + 0.06, 0)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.billboard_keep_scale = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = false

	var tex: Texture2D = null
	if Atlas != null and Atlas.has_method(&"item_icon"):
		tex = Atlas.item_icon(stack.id) as Texture2D
	if tex != null:
		_mat.albedo_texture = tex
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_mat.albedo_color = Color.WHITE
	else:
		# Fallback: a flat chip in the item's own colour.
		_mat.albedo_color = t.icon_color if t != null else Color(0.75, 0.75, 0.78)
	_base_alpha = _mat.albedo_color.a
	_icon.material_override = _mat

	_build_glow(t)


func _build_glow(t: ItemType) -> void:
	var rarity := stack.rarity()
	if t == null or rarity < Const.RARITY_RARE:
		if _glow != null:
			_glow.queue_free()
			_glow = null
		return
	if _glow == null:
		_glow = MeshInstance3D.new()
		_glow.name = "Glow"
		_glow.layers = Const.RL_ENTITIES
		add_child(_glow)
	var quad := QuadMesh.new()
	quad.size = Vector2(ICON_SIZE * 1.9, ICON_SIZE * 1.9)
	_glow.mesh = quad
	_glow.position = Vector3(0, box_size.y * 0.5 + 0.06, 0)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow_mat.billboard_keep_scale = true
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c: Color = Const.RARITY_COLORS[clampi(rarity, 0, Const.RARITY_COLORS.size() - 1)]
	c.a = 0.28
	_glow_mat.albedo_color = c
	_glow.material_override = _glow_mat


func _pop_arc() -> void:
	if velocity.length_squared() > 0.01:
		return  # the spawner already threw it somewhere
	set_plane_velocity(randf_range(-2.1, 2.1))
	velocity.y = randf_range(4.0, 6.2)


func _process(delta: float) -> void:
	if _icon == null:
		return
	_pop = minf(1.0, _pop + delta * 3.6)
	_spin += delta * SPIN_SPEED * (2.2 if magnetised else 1.0)

	# Bob, and squash horizontally to fake a slow spin without fighting the
	# billboard basis. Peel squashes the drop as it crosses layers.
	var bob := sin(_bob_phase + age * 2.2) * BOB_HEIGHT
	var grow := ease(_pop, 0.35)
	var spin_scale := absf(cos(_spin)) * 0.55 + 0.45
	var peel_scale := lerpf(0.55, 1.0, clampf(peel, 0.0, 1.0))
	_icon.position.y = box_size.y * 0.5 + 0.06 + bob
	_icon.scale = Vector3(grow * spin_scale * peel_scale, grow, 1.0)

	var alpha := _base_alpha * lerpf(0.45, 1.0, clampf(peel, 0.0, 1.0))
	if not never_despawn:
		var left := DESPAWN_TIME - age
		if left < WARN_TIME:
			# Blink faster the closer it gets to vanishing.
			var rate := lerpf(2.5, 12.0, 1.0 - clampf(left / WARN_TIME, 0.0, 1.0))
			alpha *= 0.35 + 0.65 * (0.5 + 0.5 * sin(age * rate * TAU * 0.5))
	_mat.albedo_color.a = alpha
	if _glow != null:
		_glow.position.y = _icon.position.y
		_glow.scale = Vector3.ONE * (grow * (0.9 + 0.1 * sin(age * 3.0)))


# ============================================================ serialisation ====
func save_state() -> Dictionary:
	var d := super.save_state()
	d["stack"] = stack.to_dict() if stack != null else {}
	d["age"] = age
	return d


func load_state(d: Dictionary) -> void:
	super.load_state(d)
	var sd: Dictionary = d.get("stack", {})
	if not sd.is_empty():
		setup(ItemStack.from_dict(sd))
	age = float(d.get("age", 0.0))
