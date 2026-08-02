class_name Npc
extends Node3D

## A villager. Wanders a short leash, greets you, and opens whatever its role
## does: a shop, a heal, a repair, or a quest.
##
## Uses the same billboard-and-voxel-physics recipe as the player and the
## monsters, so an NPC standing inside a building is revealed by the cutaway the
## moment the camera slices the wall away — which is how you find the shopkeeper
## without walking round the outside first.

const HALF := Vector3(0.3, 0.85, 0.3)
const GRAVITY := 30.0
const LEASH := 7.0

var world: VoxelWorld
var player: Player
var game: Node

var role: NpcRoles.Role
var npc_name := "Settler"
var reputation := 0
var stock: Array[Items.Stack] = []
var quest_id := ""

var velocity := Vector3.ZERO
var _home := Vector3.ZERO
var _wander := Vector3.ZERO
var _think := 0.0
var _anim := 0.0
var _hit_floor := false
var on_floor := false
var _seed := 0
## Which of the cached face variants this villager wears. See `spawn`.
var _face := 0

var sprite: Sprite3D
var _tag: Label3D


static func spawn(parent: Node, w: VoxelWorld, p: Player, g: Node,
		role_id: StringName, at: Vector3, rng: RandomNumberGenerator) -> Npc:
	NpcRoles.boot()
	var r := NpcRoles.get_role(role_id)
	if r == null:
		return null
	var n := Npc.new()
	n.world = w
	n.player = p
	n.game = g
	n.role = r
	n.npc_name = NpcRoles.random_name(rng)
	n._seed = rng.randi()
	# The sprite sheet is cached by role and variant, so the number of distinct
	# faces has to be a small closed set rather than one per villager ever
	# spawned. Sixteen per role is more variety than a village can show at once,
	# and the greeting and idle lines still use the full seed, so two villagers
	# who look alike do not sound alike.
	n._face = n._seed & 15
	parent.add_child(n)
	n.global_position = at
	n._home = at
	n._roll_stock(rng)
	return n


func _ready() -> void:
	add_to_group(&"npcs")
	sprite = Sprite3D.new()
	sprite.texture = TexGen.build_npc(role.color, role.accent, _face)
	sprite.hframes = TexGen.CH_FRAMES
	sprite.pixel_size = 1.85 / float(TexGen.CH_H)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.shaded = true
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	sprite.position = Vector3(0, 0.92, 0)
	add_child(sprite)

	_tag = Label3D.new()
	_tag.text = "%s\n%s" % [npc_name, role.display]
	_tag.font_size = 44
	_tag.outline_size = 14
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = false
	_tag.modulate = Color(1, 1, 1, 0.0)
	_tag.position = Vector3(0, 2.15, 0)
	add_child(_tag)


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_think -= delta

	# stand still and face the player while they are close enough to talk to
	var close := player != null \
		and player.global_position.distance_to(global_position) < 3.4
	if close:
		_wander = Vector3.ZERO
	elif _think <= 0.0:
		_think = randf_range(2.0, 5.0)
		if randf() < 0.45:
			_wander = Vector3.ZERO
		else:
			var a := randf() * TAU
			_wander = Vector3(cos(a), 0, sin(a))
		if global_position.distance_to(_home) > LEASH:
			var back := _home - global_position
			back.y = 0.0
			_wander = back.normalized()

	var want := _wander * 1.9
	velocity.x = move_toward(velocity.x, want.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 18.0 * delta)
	velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)

	var motion := velocity * delta
	var steps := maxi(1, int(ceil(motion.length() / 0.35)))
	var d := motion / float(steps)
	_hit_floor = false
	for i in steps:
		_move_axis(d.x, 0)
		_move_axis(d.z, 2)
		_move_axis(d.y, 1)
	on_floor = _hit_floor

	if global_position.y < -6.0:
		global_position = _home

	# a low wall or a step: hop it rather than get stuck on the doorway
	if on_floor and _wander != Vector3.ZERO \
			and _overlaps(global_position + _wander * 0.6):
		velocity.y = 8.0

	_animate(delta, close)


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
		if _wander != Vector3.ZERO:
			_wander = _wander.rotated(Vector3.UP, PI * 0.5)


func _animate(delta: float, close: bool) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar > 0.3:
		_anim += delta * (3.0 + planar)
		sprite.frame = 1 + (int(_anim) % 4)
	else:
		sprite.frame = 0
	if player != null:
		var to := player.global_position - global_position
		sprite.flip_h = to.x + to.z < 0.0
	# the name tag only appears when you are close enough for it to matter
	_tag.modulate.a = lerpf(_tag.modulate.a, 1.0 if close else 0.0,
		1.0 - exp(-9.0 * delta))


# =============================================================================
# talking and trading
# =============================================================================

func greeting() -> String:
	if role.greeting.is_empty():
		return "..."
	return role.greeting[absi(_seed + reputation) % role.greeting.size()]


func idle_line() -> String:
	if role.idle.is_empty():
		return "..."
	return role.idle[absi(_seed / 3) % role.idle.size()]


## The options this NPC offers, as [label, action] pairs the dialogue panel
## turns into buttons.
func options() -> Array:
	var out: Array = []
	if not role.shop_tags.is_empty():
		out.append(["Trade", &"shop"])
	if role.heals:
		out.append(["Patch me up  (40 px)", &"heal"])
	if role.repairs:
		out.append(["Repair my gear  (60 px)", &"repair"])
	if role.offers_quests:
		out.append(["Anything I can do?", &"quest"])
	out.append(["Just passing through.", &"leave"])
	return out


func _roll_stock(rng: RandomNumberGenerator) -> void:
	Items.boot()
	var pool: Array[Items.Type] = []
	for tag: StringName in role.shop_tags:
		for t: Items.Type in Items.all_in_category(tag):
			if t.has_tag(&"no_sell") or t.value <= 0:
				continue
			pool.append(t)
	if pool.is_empty():
		return
	var wanted := mini(role.shop_size, pool.size())
	var picked := {}
	var guard := 0
	while picked.size() < wanted and guard < 200:
		guard += 1
		var t: Items.Type = pool[rng.randi() % pool.size()]
		if picked.has(t.id):
			continue
		picked[t.id] = true
		var n := 1
		if t.stack_size > 1:
			n = rng.randi_range(2, 12)
		stock.append(Items.make(t.id, n))


func buy_price(stack: Items.Stack) -> int:
	var t := stack.type()
	if t == null:
		return 0
	var rep_discount := clampf(float(reputation) * 0.01, 0.0, 0.25)
	return maxi(1, int(float(t.value) * role.markup * (1.0 - rep_discount)))


func sell_price(stack: Items.Stack) -> int:
	var t := stack.type()
	if t == null or t.has_tag(&"no_sell"):
		return 0
	var bonus := 0.0
	if player != null:
		bonus = player.inventory.bonus("value_bonus")
	return maxi(1, int(float(t.value) * role.buys * (1.0 + bonus)))
