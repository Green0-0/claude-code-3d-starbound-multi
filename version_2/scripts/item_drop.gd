class_name ItemDrop
extends Node3D

## A stack of items lying on the ground.
##
## Uses the same swept-box-against-the-bitmask physics as everything else, so a
## drop lands on a ledge exactly where the player would, and falls down the
## same shaft. Sprite3D and Y-billboarded, which means the cutaway reveals loot
## sitting in a tunnel the moment the camera slices it open.

const HALF := Vector3(0.16, 0.16, 0.16)
const GRAVITY := 26.0
const MAGNET_RANGE := 2.6
const MAGNET_SPEED := 9.0
const PICKUP_RANGE := 0.75
const LIFETIME := 300.0
const MERGE_RANGE := 0.9

var world: VoxelWorld
var stack: Items.Stack
var velocity := Vector3.ZERO

var _age := 0.0
var _pickup_delay := 0.35
var _bob := 0.0
var _sprite: Sprite3D
var _hit_floor := false


static func spawn(parent: Node, w: VoxelWorld, at: Vector3, s: Items.Stack,
		scatter := true) -> ItemDrop:
	if s == null or s.is_empty():
		return null
	# roll into a nearby drop of the same thing instead of carpeting the floor
	for other in parent.get_children():
		var d := other as ItemDrop
		if d == null or d.stack == null or d.stack.is_empty():
			continue
		if d.stack.id != s.id or d.stack.data != s.data:
			continue
		if d.global_position.distance_to(at) > MERGE_RANGE:
			continue
		if d.stack.count + s.count <= d.stack.max_stack():
			d.stack.count += s.count
			d._age = 0.0
			return d
	var drop := ItemDrop.new()
	drop.world = w
	drop.stack = s
	parent.add_child(drop)
	drop.global_position = at
	if scatter:
		drop.velocity = Vector3(randf_range(-1.6, 1.6), randf_range(2.0, 3.6),
			randf_range(-1.6, 1.6))
	return drop


func _ready() -> void:
	add_to_group(&"item_drops")
	_sprite = Sprite3D.new()
	var t := stack.type() if stack != null else null
	_sprite.texture = t.icon() if t != null else TexGen.build_item_icon(&"chunk",
		Color(0.7, 0.7, 0.7))
	_sprite.pixel_size = 0.55 / float(TexGen.ICON)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.5
	_sprite.shaded = true
	_sprite.double_sided = true
	_sprite.position = Vector3(0, 0.28, 0)
	add_child(_sprite)

	# rare loot announces itself
	if t != null and t.rarity >= Items.RARITY_RARE:
		var glow := OmniLight3D.new()
		glow.light_color = t.rarity_color()
		glow.light_energy = 0.9
		glow.omni_range = 3.2
		glow.position = Vector3(0, 0.35, 0)
		add_child(glow)


func _physics_process(delta: float) -> void:
	if world == null or stack == null or stack.is_empty():
		queue_free()
		return

	_age += delta
	_pickup_delay = maxf(_pickup_delay - delta, 0.0)
	if _age > LIFETIME:
		queue_free()
		return

	var player := _nearest_player()
	var magnetised := false
	if player != null and _pickup_delay <= 0.0:
		var to: Vector3 = player.global_position + Vector3(0, 0.7, 0) - global_position
		var dist := to.length()
		if dist < PICKUP_RANGE:
			_try_pickup(player)
			return
		if dist < MAGNET_RANGE and player.has_method(&"can_accept_item") \
				and player.can_accept_item(stack.id):
			# accelerate toward the player, ignoring terrain: nothing is more
			# irritating than loot stuck behind the lip you just mined off
			velocity = velocity.lerp(to.normalized() * MAGNET_SPEED, 0.35)
			global_position += velocity * delta
			magnetised = true

	if not magnetised:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -32.0)
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		var motion := velocity * delta
		var steps := maxi(1, int(ceil(motion.length() / 0.25)))
		var d := motion / float(steps)
		_hit_floor = false
		for i in steps:
			_move_axis(d.x, 0)
			_move_axis(d.z, 2)
			_move_axis(d.y, 1)
		if _hit_floor:
			velocity.x *= 0.6
			velocity.z *= 0.6

	if global_position.y < -6.0:
		queue_free()
		return

	# a slow bob and spin so a dropped stack reads as loot, not as scenery
	_bob += delta
	_sprite.position.y = 0.28 + sin(_bob * 2.2) * 0.06
	# fade out over the last ten seconds of life
	var left := LIFETIME - _age
	_sprite.modulate.a = clampf(left / 10.0, 0.15, 1.0)


func _overlaps(at: Vector3) -> bool:
	return world.box_overlaps(at + Vector3(0, HALF.y, 0), HALF)


func _move_axis(amount: float, axis: int) -> void:
	if amount == 0.0:
		return
	var before := global_position
	var p := before
	p[axis] += amount
	global_position = p
	if not _overlaps(p):
		return
	var lo := before[axis]
	var hi := p[axis]
	for i in 6:
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
		velocity.y = 0.0
	else:
		velocity[axis] = 0.0


func _nearest_player() -> Node3D:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func _try_pickup(player: Node) -> void:
	if not player.has_method(&"collect_stack"):
		return
	var leftover: int = player.collect_stack(stack)
	if leftover <= 0:
		queue_free()
	else:
		stack.count = leftover
		# bag is full: shove it away so it stops rattling against the player
		velocity = Vector3(randf_range(-2.0, 2.0), 2.5, randf_range(-2.0, 2.0))
		_pickup_delay = 1.2
