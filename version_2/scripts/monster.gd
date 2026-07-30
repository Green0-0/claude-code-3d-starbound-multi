class_name Monster
extends Node3D

## Every hostile in the game, driven by a `SpeciesDB.Def`.
##
## Shares the player's hand-rolled voxel physics, so a monster behaves
## identically on ledges, in tunnels and inside houses — and, because it is just
## another billboard in the world, the cutaway reveals it the moment the camera
## slices open the tunnel it is standing in.
##
## Two behaviours exist specifically because of that camera: `phases_terrain`
## monsters travel through solid rock and are only ever visible inside the cut
## volume, and `only_visible_in_cut` ones fade out entirely when the cross
## section is not covering them. Turning the camera is a combat action.

signal died(monster: Monster)

const GRAVITY := 30.0

var world: VoxelWorld
var player: Player
var game: Node
var species: SpeciesDB.Def

var velocity := Vector3.ZERO
var health := 30.0
var max_health := 30.0
var on_floor := false
var threat_scale := 1.0

var _half := Vector3(0.4, 0.4, 0.4)
var _wander := Vector3.ZERO
var _think := 0.0
var _anim := 0.0
var _hop := 0.0
var _hurt_flash := 0.0
var _attack_cd := 0.0
var _charge := 0.0
var _charge_cd := 0.0
var _hit_floor := false
var _home := Vector3.ZERO
var _revealed := 1.0
var _dying := false

var sprite: Sprite3D
var _glow: OmniLight3D


static func spawn(parent: Node, w: VoxelWorld, p: Player, g: Node,
		id: StringName, at: Vector3, threat := 1.0) -> Monster:
	var def := SpeciesDB.get_def(id)
	if def == null:
		return null
	var m := Monster.new()
	m.world = w
	m.player = p
	m.game = g
	m.species = def
	m.threat_scale = threat
	parent.add_child(m)
	m.global_position = at
	m._home = at
	return m


func _ready() -> void:
	add_to_group(&"monsters")
	if species == null:
		queue_free()
		return
	# Threat scales the numbers, never the behaviour.
	max_health = species.health * threat_scale
	health = max_health
	_half = Vector3(species.size.x * 0.5, species.size.y * 0.5, species.size.z * 0.5)

	sprite = Sprite3D.new()
	sprite.texture = TexGen.build_creature(species.shape, species.color,
		species.alt, species.features)
	sprite.hframes = TexGen.MB_FRAMES
	sprite.pixel_size = (species.size.y * 1.35) / float(TexGen.MB_H)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.shaded = true
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	sprite.position = Vector3(0, species.size.y * 0.62, 0)
	add_child(sprite)

	var glow := float(species.features.get("glow", 0.0))
	if glow > 0.05:
		_glow = OmniLight3D.new()
		_glow.light_color = species.alt.lightened(0.2)
		_glow.light_energy = glow * 1.6
		_glow.omni_range = 4.0 + glow * 5.0
		_glow.position = Vector3(0, species.size.y * 0.6, 0)
		add_child(_glow)

	if is_boss():
		sprite.modulate = Color(1.05, 1.0, 1.0)


func is_boss() -> bool:
	return species.family == SpeciesDB.FAM_BOSS


func display_name() -> String:
	return species.display


# =============================================================================
# frame
# =============================================================================

func _physics_process(delta: float) -> void:
	if world == null or species == null or _dying:
		return

	_think -= delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)

	var target := _target()
	var chasing := target != null

	match species.behaviour:
		&"turret": _act_turret(delta, target)
		&"ranged": _act_ranged(delta, target)
		&"flyer": _act_flyer(delta, target)
		&"charger": _act_charger(delta, target)
		&"pack_hunter": _act_pack(delta, target)
		&"ambusher": _act_ambusher(delta, target)
		&"hopper": _act_hopper(delta, target)
		_: _act_melee(delta, target)

	if species.behaviour != &"flyer" and species.behaviour != &"turret":
		_apply_gravity(delta)
	_sweep(delta)

	if global_position.y < -6.0:
		queue_free()
		return

	_touch_damage(delta)
	_animate(delta, chasing)


## The player, if they are close enough and this species cares.
func _target() -> Player:
	if player == null or not player.is_alive():
		return null
	var to := player.global_position - global_position
	if to.length() > species.aggro * (2.0 if is_boss() else 1.0):
		return null
	# A disguised mimic ignores you until you are practically on top of it.
	if bool(species.flags.get(&"disguised", false)) and to.length() > species.aggro:
		return null
	return player


# ------------------------------------------------------------------ behaviours

func _act_melee(delta: float, target: Player) -> void:
	if target != null:
		_steer_toward(target.global_position, delta, 1.0)
		_try_melee(target)
	else:
		_wander_about(delta)
	_maybe_hop(target != null)


func _act_pack(delta: float, target: Player) -> void:
	if target == null:
		_wander_about(delta)
		_maybe_hop(false)
		return
	# flank: aim slightly to one side of the player so a pack surrounds
	var side := Vector3(-1, 0, 0) if int(get_instance_id()) % 2 == 0 else Vector3(1, 0, 0)
	var aim: Vector3 = target.global_position + side * 1.4
	_steer_toward(aim, delta, 1.15)
	_try_melee(target)
	_maybe_hop(true)


func _act_charger(delta: float, target: Player) -> void:
	if target == null:
		_wander_about(delta)
		_maybe_hop(false)
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var range_v := float(species.flags.get(&"charge_range", 12.0))
	if _charge > 0.0:
		_charge -= delta
		var boost := float(species.flags.get(&"charge_speed", 2.4))
		_drive(to.normalized() * species.speed * boost, delta, 40.0)
		_try_melee(target)
		return
	if _charge_cd <= 0.0 and to.length() < range_v and to.length() > 3.0:
		_charge = 1.4
		_charge_cd = 3.4
		return
	_steer_toward(target.global_position, delta, 0.8)
	_try_melee(target)
	_maybe_hop(true)


func _act_ranged(delta: float, target: Player) -> void:
	if target == null:
		_wander_about(delta)
		_maybe_hop(false)
		return
	var to: Vector3 = target.global_position - global_position
	var want := float(species.flags.get(&"range", 14.0)) * 0.6
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() > want:
		_steer_toward(target.global_position, delta, 0.9)
	elif flat.length() < want * 0.6:
		_drive(-flat.normalized() * species.speed * 0.8, delta, 16.0)
	else:
		_drive(Vector3.ZERO, delta, 12.0)
	_try_shoot(target)
	_maybe_hop(false)


func _act_turret(_delta: float, target: Player) -> void:
	velocity = Vector3.ZERO
	if target != null:
		_try_shoot(target)


func _act_flyer(delta: float, target: Player) -> void:
	var goal := _home + Vector3(0, 2.0, 0)
	if target != null:
		goal = target.global_position + Vector3(0, 1.0, 0)
	else:
		if _think <= 0.0:
			_think = randf_range(1.5, 3.5)
			_wander = Vector3(randf_range(-1, 1), randf_range(-0.4, 0.6),
				randf_range(-1, 1)).normalized()
		goal = global_position + _wander * 6.0
	var to := goal - global_position
	# bob so a hovering mob never looks frozen
	to.y += sin(Time.get_ticks_msec() * 0.002 + float(get_instance_id() % 100)) * 0.8
	_drive(to.normalized() * species.speed, delta, 12.0)
	if target != null:
		_try_melee(target)
		if species.flags.has(&"projectile"):
			_try_shoot(target)


func _act_hopper(delta: float, target: Player) -> void:
	# skittish: runs from the player rather than at them
	if target != null:
		var away := global_position - target.global_position
		away.y = 0.0
		_drive(away.normalized() * species.speed * 1.4, delta, 20.0)
		if on_floor and _hop <= 0.0:
			velocity.y = species.jump
			_hop = 0.55
	else:
		_wander_about(delta)
		_maybe_hop(false)
	_hop -= delta
	_try_melee(target)


## Waits, still and quiet, until you are close — then commits entirely.
func _act_ambusher(delta: float, target: Player) -> void:
	if target == null:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		return
	_steer_toward(target.global_position, delta, 1.3)
	_try_melee(target)
	_maybe_hop(true)


# ------------------------------------------------------------------ movement

func _steer_toward(goal: Vector3, delta: float, speed_mult: float) -> void:
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	_drive(to.normalized() * species.speed * speed_mult, delta, 22.0)


func _drive(want: Vector3, delta: float, accel: float) -> void:
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)
	if species.behaviour == &"flyer":
		velocity.y = move_toward(velocity.y, want.y, accel * delta)


func _wander_about(delta: float) -> void:
	if _think <= 0.0:
		_think = randf_range(1.2, 3.4)
		if randf() < 0.35:
			_wander = Vector3.ZERO
		else:
			var a := randf() * TAU
			_wander = Vector3(cos(a), 0, sin(a))
	# leash: never stray far from where it spawned
	if global_position.distance_to(_home) > species.leash:
		var back := _home - global_position
		back.y = 0.0
		_wander = back.normalized()
	_drive(_wander * species.speed, delta, 22.0)


func _maybe_hop(chasing: bool) -> void:
	_hop -= get_physics_process_delta_time()
	if not on_floor or _hop > 0.0 or species.jump <= 0.0:
		return
	if _wander == Vector3.ZERO and not chasing:
		return
	var ahead := Vector3(velocity.x, 0, velocity.z).normalized() * 0.7
	if _overlaps(global_position + ahead) or (chasing and randf() < 0.03):
		velocity.y = species.jump
		_hop = 0.5


func _apply_gravity(delta: float) -> void:
	velocity.y = maxf(velocity.y - GRAVITY * delta, -44.0)


func _sweep(delta: float) -> void:
	if _phases():
		# ignores terrain entirely; that is the whole point of it
		global_position += velocity * delta
		on_floor = false
		return
	var motion := velocity * delta
	var steps := maxi(1, int(ceil(motion.length() / 0.35)))
	var d := motion / float(steps)
	_hit_floor = false
	for i in steps:
		_move_axis(d.x, 0)
		_move_axis(d.z, 2)
		_move_axis(d.y, 1)
	on_floor = _hit_floor


func _phases() -> bool:
	return bool(species.flags.get(&"phases_terrain", false))


func _overlaps(at: Vector3) -> bool:
	return world.box_overlaps(at + Vector3(0, _half.y, 0), _half)


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


# ------------------------------------------------------------------ attacking

func _try_melee(target: Player) -> void:
	if target == null or _attack_cd > 0.0:
		return
	var to: Vector3 = target.global_position + Vector3(0, 0.9, 0) \
		- (global_position + Vector3(0, _half.y, 0))
	if to.length() > _half.x + 1.0:
		return
	_attack_cd = species.attack_cd
	var dmg := species.damage * threat_scale
	target.hurt(dmg, species.element)
	target.velocity += to.normalized() * species.knockback * 0.4 + Vector3.UP * 3.0
	velocity += -to.normalized() * 3.0
	if game != null:
		game.on_monster_hit_player(self, dmg)


func _try_shoot(target: Player) -> void:
	if target == null or _attack_cd > 0.0 or game == null:
		return
	var kind: StringName = species.flags.get(&"projectile", &"")
	if kind == &"":
		return
	var reach := float(species.flags.get(&"range", 14.0))
	var from := global_position + Vector3(0, _half.y * 1.4, 0)
	var to: Vector3 = target.global_position + Vector3(0, 0.9, 0) - from
	if to.length() > reach:
		return
	# do not fire through a wall we cannot see past
	var hit := world.raycast(from, to.normalized(), to.length(), false)
	if hit.get("hit", false):
		return
	_attack_cd = species.attack_cd
	var burst := int(species.flags.get(&"burst", 1))
	for i in burst:
		var spread := Vector3(randf_range(-0.06, 0.06), randf_range(-0.04, 0.06),
			randf_range(-0.06, 0.06)) * float(i)
		game.spawn_projectile(kind, from, (to.normalized() + spread).normalized(),
			species.damage * threat_scale, species.element, self)


## Contact damage for things that hurt to touch even when not attacking.
func _touch_damage(_delta: float) -> void:
	if player == null or not player.is_alive():
		return
	if not bool(species.flags.get(&"explodes", false)):
		return


# ------------------------------------------------------------------ rendering

func _animate(delta: float, chasing: bool) -> void:
	_anim += delta * (3.0 + Vector2(velocity.x, velocity.z).length() * 0.8)
	sprite.frame = int(_anim) % TexGen.MB_FRAMES
	sprite.flip_h = velocity.x + velocity.z < 0.0

	# Monsters that live inside the cut only exist while the cut covers them.
	var want_alpha := 1.0
	if bool(species.flags.get(&"only_visible_in_cut", false)):
		var b := Vector3i(int(floor(global_position.x)),
			int(floor(global_position.y + _half.y)), int(floor(global_position.z)))
		want_alpha = 1.0 if world.cutaway.is_cut(b.x, b.y, b.z) else 0.12
	_revealed = lerpf(_revealed, want_alpha, 1.0 - exp(-8.0 * delta))

	var tint := Color(1, 1, 1, _revealed)
	if _hurt_flash > 0.0:
		tint = Color(3.0, 0.9, 0.9, _revealed)
	elif chasing:
		tint = Color(1.12, 1.0, 1.0, _revealed)
	sprite.modulate = tint


# =============================================================================
# damage
# =============================================================================

## Take a hit. Returns the damage actually dealt, after the species' resists.
func hurt(amount: float, element: StringName = Blocks.ELEM_PHYSICAL,
		knock := Vector3.ZERO, source: Node = null) -> float:
	if _dying:
		return 0.0
	var mult := float(species.resists.get(element, 1.0))
	var dealt := amount * mult
	health -= dealt
	_hurt_flash = 0.16
	velocity += knock
	# being hit is what wakes an ambusher and un-disguises a mimic
	if species.flags.has(&"disguised"):
		species.flags.erase(&"disguised")
	if game != null:
		game.on_monster_damaged(self, dealt, element, source)
	if health <= 0.0:
		_die(source)
	return dealt


func _die(source: Node) -> void:
	if _dying:
		return
	_dying = true
	if game != null:
		game.on_monster_died(self, source)
	# an ooze mother is worse dead than alive
	var split: StringName = species.flags.get(&"splits", &"")
	if split != &"" and game != null:
		for i in int(species.flags.get(&"split_count", 2)):
			var a := float(i) / float(maxi(1, int(species.flags.get(&"split_count", 2)))) * TAU
			game.spawn_monster(split,
				global_position + Vector3(cos(a), 0.4, sin(a)) * 1.2, threat_scale)
	died.emit(self)
	queue_free()
