class_name Monster
extends Node3D

## A creature.
##
## Shares the player's hand-rolled voxel physics, so it behaves identically on
## ledges, in tunnels and inside houses — and, because it is just another
## billboard in the world, the cutaway reveals it the moment the camera slices
## open the tunnel it is standing in.
##
## The behaviour is a small state machine over three drives — **hunger**,
## **fear** and **alertness** — rather than a chase-the-player loop:
##
##   SLEEP → creatures keep hours, and a nocturnal one is genuinely asleep by day
##   GRAZE → hungry herbivores eat the ground cover, and stop watching while they do
##   WANDER → the default, bounded by territory or a herd's centre of mass
##   ALERT → something was heard; walk to where it was and look around
##   STALK → seen, but not committed yet — this is the window to back away
##   CHASE / ATTACK
##   FLEE → below its courage threshold, or its herd broke
##   RETURN → too far from home
##
## Perception is sight *and* hearing, and hearing reads `Player.noise_radius()`,
## so crouching genuinely hides you and sprinting genuinely does not.

signal died(monster: Monster)
signal state_changed(from: StringName, to: StringName)

const GRAVITY := 30.0

enum State { SLEEP, GRAZE, WANDER, ALERT, STALK, CHASE, ATTACK, FLEE, RETURN }
const STATE_NAMES := [&"sleep", &"graze", &"wander", &"alert", &"stalk",
	&"chase", &"attack", &"flee", &"return"]

var world: VoxelWorld
var player: Player
var game: Node
var species: SpeciesDB.Def

var velocity := Vector3.ZERO
var health := 30.0
var max_health := 30.0
var shell := 0.0                  ## armour hit points remaining
var on_floor := false
var threat_scale := 1.0

## 0 calm .. 1 starving. Drives grazing and, for hunters, how far they will go.
var hunger := 0.0
## 0 brave .. 1 panicking. Raised by damage and by seeing packmates die.
var fear := 0.0
## 0 oblivious .. 1 certain. Raised by sight and sound, decays with time.
var alert := 0.0
## Taming progress, raised by being fed what it likes.
var bond := 0.0
var tamed := false

var state: int = State.WANDER
var home := Vector3.ZERO
var last_known := Vector3.ZERO
var has_last_known := false

var _half := Vector3(0.4, 0.4, 0.4)
var _wander := Vector3.ZERO
var _think := 0.0
var _anim := 0.0
var _hop := 0.0
var _hurt_flash := 0.0
var _attack_cd := 0.0
var _charge := 0.0
var _charge_cd := 0.0
var _telegraph := 0.0
var _state_time := 0.0
var _hit_floor := false
var _revealed := 1.0
var _dying := false
var _graze_timer := 0.0
var _rng := RandomNumberGenerator.new()

var sprite: Sprite3D
var _glow: OmniLight3D
var _mood: Label3D


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
	m.home = at
	return m


func _ready() -> void:
	add_to_group(&"monsters")
	if species == null:
		queue_free()
		return
	_rng.randomize()
	max_health = species.health * threat_scale
	health = max_health
	shell = species.armour_hp * threat_scale
	_half = Vector3(species.size.x * 0.5, species.size.y * 0.5, species.size.z * 0.5)
	hunger = _rng.randf() * 0.4
	state = State.WANDER

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

	# A one-glyph mood tell above the head. It is the difference between "that
	# thing is wandering" and "that thing has decided about you".
	_mood = Label3D.new()
	_mood.font_size = 64
	_mood.outline_size = 18
	_mood.pixel_size = 0.005
	_mood.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mood.modulate = Color(1, 1, 1, 0)
	_mood.position = Vector3(0, species.size.y * 1.5, 0)
	add_child(_mood)


func is_boss() -> bool:
	return species.family == SpeciesDB.FAM_BOSS


func display_name() -> String:
	return species.display


func state_name() -> StringName:
	return STATE_NAMES[state]


func is_hostile() -> bool:
	return not tamed and species.will_fight() \
		and (state == State.CHASE or state == State.ATTACK)


# =============================================================================
# frame
# =============================================================================

func _physics_process(delta: float) -> void:
	if world == null or species == null or _dying:
		return

	_think -= delta
	_state_time += delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_telegraph = maxf(_telegraph - delta, 0.0)
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)

	_tick_drives(delta)
	_perceive(delta)
	_choose_state()
	_act(delta)

	if species.locomotion != &"fly" and species.locomotion != &"float" \
			and species.locomotion != &"root":
		_apply_gravity(delta)
	_sweep(delta)

	if global_position.y < -6.0:
		queue_free()
		return

	_animate(delta)


## Hunger climbs steadily; fear bleeds away when nothing is happening.
func _tick_drives(delta: float) -> void:
	hunger = minf(hunger + delta * 0.012, 1.0)
	fear = maxf(fear - delta * 0.10, 0.0)
	alert = maxf(alert - delta * (0.55 if state == State.CHASE else 0.28), 0.0)


# =============================================================================
# perception
# =============================================================================

## Sight is a cone, hearing is a radius, and both are checked against what the
## player is actually doing. This is the whole reason crouching exists.
func _perceive(delta: float) -> void:
	if tamed or player == null or not player.is_alive():
		return
	var to: Vector3 = player.global_position + Vector3(0, 0.9, 0) \
		- (global_position + Vector3(0, _half.y, 0))
	var dist := to.length()

	# --- hearing. A sprinting player is audible through walls; a crouching one
	# is nearly silent even in the open.
	var heard := dist < minf(species.hearing, player.noise_radius())

	# --- sight. Narrow cone, blocked by terrain, and halved at night for
	# anything that hunts by day.
	var seen := false
	var range_v := species.sight
	if game != null and game.sky.is_night() and species.activity == SpeciesDB.ACTIVE_DAY:
		range_v *= 0.5
	if dist < range_v:
		var facing := Vector3(velocity.x, 0, velocity.z)
		if facing.length_squared() < 0.04:
			facing = _wander if _wander != Vector3.ZERO else Vector3(0, 0, 1)
		var cone := species.sight_cone
		# a lure or an all-round eye has no blind side at all
		if cone <= -0.5 or to.normalized().dot(facing.normalized()) > cone:
			seen = _line_of_sight(to, dist)

	if seen:
		alert = minf(alert + delta * 2.4, 1.0)
		last_known = player.global_position
		has_last_known = true
	elif heard:
		alert = minf(alert + delta * 1.1, 1.0)
		last_known = player.global_position
		has_last_known = true


func _line_of_sight(to: Vector3, dist: float) -> bool:
	if bool(species.flags.get(&"phases_terrain", false)):
		return true
	var from := global_position + Vector3(0, _half.y, 0)
	return not world.raycast(from, to / dist, dist, false).get("hit", false)


## Shout. Packs converge, herds bolt together.
func alarm(source: Vector3, radius: float, panic := false) -> void:
	if game == null:
		return
	for n in get_parent().get_children():
		var m := n as Monster
		if m == null or m == self or m._dying:
			continue
		if m.species.id != species.id and not panic:
			continue
		if m.global_position.distance_to(global_position) > radius:
			continue
		m.alert = maxf(m.alert, 0.85)
		m.last_known = source
		m.has_last_known = true
		if panic:
			m.fear = maxf(m.fear, 0.8)


# =============================================================================
# deciding
# =============================================================================

func _set_state(next: int) -> void:
	if state == next:
		return
	var from: StringName = STATE_NAMES[state]
	state = next
	_state_time = 0.0
	state_changed.emit(from, STATE_NAMES[next])


func _choose_state() -> void:
	if tamed:
		_set_state(State.WANDER)
		return

	# --- broken: nothing else matters
	if fear > 0.6 or (species.courage > 0.0 and health < max_health * species.courage):
		_set_state(State.FLEE)
		return

	var night: bool = game != null and game.sky.is_night()
	var awake := species.is_awake(night)

	# --- asleep, unless something is right on top of it
	if not awake and alert < 0.75:
		_set_state(State.SLEEP)
		return

	# --- too far from home
	if species.leash > 0.0 and global_position.distance_to(home) > species.leash:
		_set_state(State.RETURN)
		return

	var engaged := alert >= 0.99 and _target_in_reach()
	match species.temperament:
		SpeciesDB.TEMPER_PASSIVE:
			# never initiates; only runs, and only if it has been hurt
			_set_state(State.GRAZE if _wants_to_eat() else State.WANDER)
		SpeciesDB.TEMPER_SKITTISH:
			if alert > 0.45:
				_set_state(State.FLEE)
			elif _wants_to_eat():
				_set_state(State.GRAZE)
			else:
				_set_state(State.WANDER)
		SpeciesDB.TEMPER_DEFENSIVE:
			# only commits once you are inside its patch
			if engaged and _inside_territory():
				_set_state(State.ATTACK if _in_melee() else State.CHASE)
			elif alert > 0.55 and _inside_territory():
				_set_state(State.STALK)
			elif alert > 0.25 and has_last_known:
				_set_state(State.ALERT)
			elif _wants_to_eat():
				_set_state(State.GRAZE)
			else:
				_set_state(State.WANDER)
		SpeciesDB.TEMPER_AMBUSH:
			# perfectly still until you are almost touching it
			if alert > 0.9 or _in_melee():
				_set_state(State.ATTACK if _in_melee() else State.CHASE)
			else:
				_set_state(State.SLEEP)
		_:
			if alert >= 0.85:
				_set_state(State.ATTACK if _in_melee() else State.CHASE)
			elif alert > 0.35 and has_last_known:
				_set_state(State.ALERT)
			elif _wants_to_eat():
				_set_state(State.GRAZE)
			else:
				_set_state(State.WANDER)


func _wants_to_eat() -> bool:
	return species.grazes and hunger > 0.45


func _inside_territory() -> bool:
	if species.territory <= 0.0:
		return true
	return home.distance_to(player.global_position) < species.territory * 2.0 \
		or global_position.distance_to(player.global_position) < species.territory


func _target_in_reach() -> bool:
	if player == null or not player.is_alive():
		return false
	return global_position.distance_to(player.global_position) < species.leash


func _in_melee() -> bool:
	if player == null or not player.is_alive():
		return false
	return global_position.distance_to(player.global_position) \
		< _half.x + 1.2 + species.size.x * 0.5


# =============================================================================
# acting
# =============================================================================

func _act(delta: float) -> void:
	match state:
		State.SLEEP: _do_sleep(delta)
		State.GRAZE: _do_graze(delta)
		State.WANDER: _do_wander(delta)
		State.ALERT: _do_alert(delta)
		State.STALK: _do_stalk(delta)
		State.CHASE: _do_chase(delta)
		State.ATTACK: _do_attack(delta)
		State.FLEE: _do_flee(delta)
		State.RETURN: _do_return(delta)


func _do_sleep(delta: float) -> void:
	_drive(Vector3.ZERO, delta, 30.0)


func _do_graze(delta: float) -> void:
	_graze_timer -= delta
	if _graze_timer > 0.0:
		_drive(Vector3.ZERO, delta, 20.0)
		return
	# eat whatever is underfoot, then amble to the next patch
	var feet := Vector3i(floori(global_position.x),
		floori(global_position.y - 0.1), floori(global_position.z))
	var here := world.get_block(feet.x, feet.y, feet.z)
	var above := world.get_block(feet.x, feet.y + 1, feet.z)
	if species.likes(Blocks.get_def(above).name):
		world.set_block(feet.x, feet.y + 1, feet.z, Blocks.AIR)
		hunger = maxf(hunger - 0.35, 0.0)
		_graze_timer = 2.5
		return
	if Blocks.get_def(here).tags.has(&"surface_cover"):
		hunger = maxf(hunger - 0.12, 0.0)
		_graze_timer = 3.0
		return
	_wander_about(delta, 0.55)


func _do_wander(delta: float) -> void:
	_wander_about(delta, 0.7 if not tamed else 1.0)
	if tamed and player != null:
		# a tamed creature keeps station a couple of paces away
		var to := player.global_position - global_position
		to.y = 0.0
		if to.length() > 5.0:
			_steer_toward(player.global_position, delta, 1.1)
	_maybe_hop(false)


## Walk to where the noise came from and have a look round.
func _do_alert(delta: float) -> void:
	if not has_last_known:
		_do_wander(delta)
		return
	var to := last_known - global_position
	to.y = 0.0
	if to.length() < 1.6:
		has_last_known = false
		_drive(Vector3.ZERO, delta, 18.0)
		return
	_steer_toward(last_known, delta, 0.6)
	_maybe_hop(false)


## Seen you, not committed. This is the window in which backing off works.
func _do_stalk(delta: float) -> void:
	if _state_time < species.wariness:
		_drive(Vector3.ZERO, delta, 24.0)
		return
	_steer_toward(player.global_position, delta, 0.45)


func _do_chase(delta: float) -> void:
	if player == null:
		return
	var flags := species.flags
	# --- charger: wind up, then commit in a straight line
	if flags.has(&"charge_range"):
		var to: Vector3 = player.global_position - global_position
		to.y = 0.0
		if _charge > 0.0:
			_charge -= delta
			_drive(to.normalized() * species.speed
				* float(flags.get(&"charge_speed", 2.4)), delta, 44.0)
			_try_melee()
			return
		if _charge_cd <= 0.0 and to.length() < float(flags[&"charge_range"]) \
				and to.length() > 3.0:
			_charge = 1.3
			_charge_cd = 3.6
			_telegraph = 0.45
			return

	# --- ranged: hold the preferred distance and shoot
	if flags.has(&"projectile"):
		var want := float(flags.get(&"range", 14.0)) * 0.62
		var flat: Vector3 = player.global_position - global_position
		flat.y = 0.0
		if flat.length() > want:
			_steer_toward(player.global_position, delta, 0.95)
		elif flat.length() < want * 0.55:
			_drive(-flat.normalized() * species.speed * 0.8, delta, 18.0)
		else:
			_drive(Vector3.ZERO, delta, 14.0)
		_try_shoot()
		_maybe_hop(false)
		return

	# --- pack hunters flank rather than queue up behind each other
	var aim := player.global_position
	if species.social == SpeciesDB.SOCIAL_PACK:
		var side := Vector3(1, 0, 0) if int(get_instance_id()) % 2 == 0 \
			else Vector3(-1, 0, 0)
		aim += side * 1.8
	_steer_toward(aim, delta, 1.0)
	_try_melee()
	_maybe_hop(true)


func _do_attack(delta: float) -> void:
	_drive(Vector3.ZERO, delta, 26.0)
	_try_melee()
	if species.flags.has(&"projectile"):
		_try_shoot()


func _do_flee(delta: float) -> void:
	if player == null:
		_do_wander(delta)
		return
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	# herds run as one animal: steer toward the herd's average heading
	if species.social == SpeciesDB.SOCIAL_HERD:
		away = away.normalized().lerp(_herd_heading(away.normalized()), 0.45)
	_drive(away.normalized() * species.speed * 1.35, delta, 30.0)
	if on_floor and _hop <= 0.0 and _blocked_ahead():
		velocity.y = species.jump
		_hop = 0.45
	_hop -= delta


func _do_return(delta: float) -> void:
	_steer_toward(home, delta, 0.8)
	_maybe_hop(false)
	if global_position.distance_to(home) < 2.0:
		_set_state(State.WANDER)


func _herd_heading(fallback: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for other in get_parent().get_children():
		var m := other as Monster
		if m == null or m == self or m.species.id != species.id:
			continue
		if m.global_position.distance_to(global_position) > 14.0:
			continue
		var v := Vector3(m.velocity.x, 0, m.velocity.z)
		if v.length_squared() > 0.25:
			sum += v.normalized()
			n += 1
	return fallback if n == 0 else (sum / float(n)).normalized()


# =============================================================================
# movement
# =============================================================================

func _steer_toward(goal: Vector3, delta: float, speed_mult: float) -> void:
	var to := goal - global_position
	if species.locomotion == &"fly" or species.locomotion == &"float":
		if to.length() < 0.05:
			return
		# bob, so a hovering creature never looks frozen
		to.y += sin(float(Time.get_ticks_msec()) * 0.002
			+ float(get_instance_id() % 100)) * 0.7
		_drive(to.normalized() * species.speed * speed_mult, delta, 16.0)
		return
	to.y = 0.0
	if to.length() < 0.05:
		return
	_drive(to.normalized() * species.speed * speed_mult, delta, 22.0)


func _drive(want: Vector3, delta: float, accel: float) -> void:
	if species.locomotion == &"root":
		velocity = Vector3.ZERO
		return
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)
	if species.locomotion == &"fly" or species.locomotion == &"float":
		velocity.y = move_toward(velocity.y, want.y, accel * delta)


func _wander_about(delta: float, speed_mult := 0.7) -> void:
	if _think <= 0.0:
		_think = randf_range(1.4, 4.0)
		if randf() < 0.4:
			_wander = Vector3.ZERO
		else:
			var a := randf() * TAU
			_wander = Vector3(cos(a), 0, sin(a))
		# stay inside the patch, or near the herd
		var anchor := home
		if species.social == SpeciesDB.SOCIAL_HERD:
			anchor = _herd_centre()
		var pull := anchor - global_position
		pull.y = 0.0
		var limit: float = species.territory if species.territory > 0.0 else 16.0
		if pull.length() > limit:
			_wander = pull.normalized()
	_drive(_wander * species.speed * speed_mult, delta, 20.0)


func _herd_centre() -> Vector3:
	var sum := global_position
	var n := 1
	for other in get_parent().get_children():
		var m := other as Monster
		if m == null or m == self or m.species.id != species.id:
			continue
		if m.global_position.distance_to(global_position) > 18.0:
			continue
		sum += m.global_position
		n += 1
	return sum / float(n)


func _blocked_ahead() -> bool:
	var ahead := Vector3(velocity.x, 0, velocity.z)
	if ahead.length_squared() < 0.04:
		return false
	return _overlaps(global_position + ahead.normalized() * 0.7)


func _maybe_hop(chasing: bool) -> void:
	_hop -= get_physics_process_delta_time()
	if not on_floor or _hop > 0.0 or species.jump <= 0.0:
		return
	if _wander == Vector3.ZERO and not chasing:
		return
	if _blocked_ahead() or (chasing and randf() < 0.03):
		velocity.y = species.jump
		_hop = 0.5


func _apply_gravity(delta: float) -> void:
	velocity.y = maxf(velocity.y - GRAVITY * delta, -44.0)


func _sweep(delta: float) -> void:
	if _phases():
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


# =============================================================================
# attacking
# =============================================================================

func _try_melee() -> void:
	if tamed or player == null or _attack_cd > 0.0 or not _in_melee():
		return
	if not species.will_fight() and not bool(species.flags.get(&"retaliates", false)):
		return
	_attack_cd = species.attack_cd
	var to: Vector3 = player.global_position + Vector3(0, 0.9, 0) \
		- (global_position + Vector3(0, _half.y, 0))
	var dmg := species.damage * threat_scale
	player.hurt(dmg, species.element)
	player.velocity += to.normalized() * species.knockback * 0.4 + Vector3.UP * 3.0
	velocity += -to.normalized() * 3.0
	var inflict: StringName = species.flags.get(&"inflicts", &"")
	if inflict != &"" and player.stats != null:
		player.stats.apply_effect(inflict, float(species.flags.get(&"inflict_time", 5.0)))
	if game != null:
		game.on_monster_hit_player(self, dmg)


func _try_shoot() -> void:
	if tamed or player == null or _attack_cd > 0.0 or game == null:
		return
	var kind: StringName = species.flags.get(&"projectile", &"")
	if kind == &"":
		return
	var reach := float(species.flags.get(&"range", 14.0))
	var from := global_position + Vector3(0, _half.y * 1.4, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.9, 0) - from
	if to.length() > reach:
		return
	if world.raycast(from, to.normalized(), to.length(), false).get("hit", false):
		return
	# some creatures wind up visibly first, which is the tell you play around
	var wind := float(species.flags.get(&"telegraph", 0.0))
	if wind > 0.0 and _telegraph <= 0.0 and _attack_cd <= 0.0:
		_telegraph = wind
		_attack_cd = wind
		return
	_attack_cd = species.attack_cd
	for i in int(species.flags.get(&"burst", 1)):
		var spread := Vector3(randf_range(-0.05, 0.05), randf_range(-0.03, 0.05),
			randf_range(-0.05, 0.05)) * float(i)
		game.spawn_projectile(kind, from, (to.normalized() + spread).normalized(),
			species.damage * threat_scale, species.element, self)


# =============================================================================
# taming
# =============================================================================

## Offer food. Works best on a calm creature — a frightened or hostile one will
## not take anything from you.
func offer(item: StringName) -> bool:
	if tamed or not species.likes(item):
		return false
	if alert > 0.6 or fear > 0.4:
		return false
	hunger = maxf(hunger - 0.5, 0.0)
	bond += 0.34
	_mood_flash("<3", Color(0.98, 0.62, 0.72))
	if bond >= 1.0:
		tamed = true
		fear = 0.0
		alert = 0.0
		if game != null:
			game.notify("The %s decides you are alright." % species.display, &"quest")
	return true


# =============================================================================
# rendering
# =============================================================================

const MOOD_GLYPHS := {
	State.SLEEP: "z", State.GRAZE: "~", State.ALERT: "?", State.STALK: "!",
	State.CHASE: "!", State.ATTACK: "!", State.FLEE: "!!",
}
const MOOD_COLORS := {
	State.SLEEP: Color(0.62, 0.68, 0.86), State.GRAZE: Color(0.66, 0.86, 0.56),
	State.ALERT: Color(0.96, 0.88, 0.42), State.STALK: Color(0.98, 0.70, 0.32),
	State.CHASE: Color(0.96, 0.36, 0.30), State.ATTACK: Color(0.96, 0.36, 0.30),
	State.FLEE: Color(0.70, 0.78, 0.96),
}


func _mood_flash(text: String, col: Color) -> void:
	if _mood == null:
		return
	_mood.text = text
	_mood.modulate = Color(col.r, col.g, col.b, 1.0)


func _animate(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length()
	_anim += delta * (2.0 + moving * 0.9)
	sprite.frame = int(_anim) % TexGen.MB_FRAMES
	if moving > 0.15:
		sprite.flip_h = velocity.x + velocity.z < 0.0

	# Creatures that live inside the cut only exist while the cut covers them.
	var want_alpha := 1.0
	if bool(species.flags.get(&"only_visible_in_cut", false)):
		var b := Vector3i(floori(global_position.x),
			floori(global_position.y + _half.y), floori(global_position.z))
		want_alpha = 1.0 if world.cutaway.is_cut(b.x, b.y, b.z) else 0.12
	_revealed = lerpf(_revealed, want_alpha, 1.0 - exp(-8.0 * delta))

	var tint := Color(1, 1, 1, _revealed)
	if _hurt_flash > 0.0:
		tint = Color(3.0, 0.9, 0.9, _revealed)
	elif _telegraph > 0.0:
		tint = Color(1.9, 1.2, 0.9, _revealed)   # winding up
	elif state == State.CHASE or state == State.ATTACK:
		tint = Color(1.25, 0.98, 0.96, _revealed)
	elif state == State.SLEEP:
		tint = Color(0.72, 0.76, 0.88, _revealed)
	sprite.modulate = tint

	# squash while asleep so a sleeping creature reads at a glance
	var squash := Vector3.ONE
	if state == State.SLEEP:
		squash = Vector3(1.1, 0.7, 1.0)
	sprite.scale = sprite.scale.lerp(squash, 1.0 - exp(-8.0 * delta))

	if _mood != null:
		var glyph: String = MOOD_GLYPHS.get(state, "")
		if tamed:
			glyph = "<3"
		var target_a := 0.0
		if glyph != "":
			_mood.text = glyph
			var col: Color = MOOD_COLORS.get(state, Color(1, 1, 1))
			if tamed:
				col = Color(0.98, 0.62, 0.72)
			_mood.modulate = Color(col.r, col.g, col.b, _mood.modulate.a)
			# only worth showing when the player is close enough to act on it
			if player != null \
					and player.global_position.distance_to(global_position) < 26.0:
				target_a = 0.9
		_mood.modulate.a = lerpf(_mood.modulate.a, target_a,
			1.0 - exp(-9.0 * delta))


# =============================================================================
# damage
# =============================================================================

## Take a hit. A shelled creature soaks damage until its shell is broken, which
## is what makes "crack it open first" a real instruction rather than flavour.
func hurt(amount: float, element: StringName = Blocks.ELEM_PHYSICAL,
		knock := Vector3.ZERO, source: Node = null) -> float:
	if _dying:
		return 0.0
	var mult := float(species.resists.get(element, 1.0))
	var dealt := amount * mult

	if shell > 0.0:
		shell -= dealt
		dealt = maxf(dealt - species.armour, dealt * 0.15)
		if shell <= 0.0 and game != null:
			game.notify("%s's shell cracks." % species.display, &"warn")
			_mood_flash("!", Color(0.98, 0.86, 0.42))

	health -= dealt
	_hurt_flash = 0.16
	velocity += knock

	# being hit wakes anything, un-disguises an ambusher and frightens the timid
	alert = 1.0
	if player != null:
		last_known = player.global_position
		has_last_known = true
	species.flags.erase(&"disguised")
	fear = minf(fear + 0.3 * (1.0 - species.courage), 1.0)
	bond = maxf(bond - 0.5, 0.0)

	# a pack closes in; a herd scatters
	if species.social == SpeciesDB.SOCIAL_PACK:
		alarm(global_position, 18.0, false)
	elif species.social == SpeciesDB.SOCIAL_HERD:
		alarm(global_position, 14.0, true)
	var alarm_radius := float(species.flags.get(&"alarm", 0.0))
	if alarm_radius > 0.0:
		alarm(last_known, alarm_radius, false)

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
		if bool(species.flags.get(&"death_burst", false)):
			game.spawn_impact(global_position + Vector3(0, _half.y, 0),
				species.alt)
	# the ones that call for help do it loudest at the end
	if species.social == SpeciesDB.SOCIAL_PACK:
		alarm(global_position, 20.0, false)
	var summon: StringName = species.flags.get(&"summons", &"")
	if summon != &"" and game != null:
		for i in int(species.flags.get(&"summon_count", 2)):
			var a := TAU * float(i) / float(maxi(1, int(species.flags.get(
				&"summon_count", 2))))
			game.spawn_monster(summon,
				global_position + Vector3(cos(a), 0.4, sin(a)) * 1.4, threat_scale)
	died.emit(self)
	queue_free()
