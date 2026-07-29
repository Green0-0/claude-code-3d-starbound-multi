## Special-behaviour modules: the per-species mechanics that a shared behaviour
## tree cannot express.
##
## One instance is created per monster (`MobBehaviour.create(species.behaviour)`)
## and ticked *before* the brain, so a behaviour can take the wheel entirely by
## calling `mob.suspend_brain(seconds)`.
##
## The `mob` parameter is deliberately untyped: `MobBase` already depends on this
## file, and typing it here would close a script-resolution cycle.
class_name MobBehaviour
extends RefCounted


## The interface every behaviour module implements. It is an inner class so the
## modules below can inherit it without this script having to reference its own
## global name.
class Base extends RefCounted:
	var age := 0.0

	## Called once, right after the monster's species has been applied.
	func on_spawn(_mob) -> void:
		pass

	## Called every physics frame, before the behaviour tree.
	func on_tick(_mob, delta: float) -> void:
		age += delta

	## Return the (possibly modified) damage. Default is a pass-through.
	func modify_damage(_mob, amount: float, _element: String, _source: Node) -> float:
		return amount

	func on_damaged(_mob, _amount: float, _element: String, _source: Node) -> void:
		pass

	## Return true to suppress the default melee swing.
	func on_attack(_mob, _target) -> bool:
		return false

	func on_death(_mob, _source: Node) -> void:
		pass

	## The play plane changed under us (the player flipped the camera).
	func on_view_flipped(_mob, _from_view: int, _to_view: int) -> void:
		pass

	# ------------------------------------------------------------- helpers
	static func _player() -> Node3D:
		return Game.player

	static func _player_layer() -> int:
		return View.layer

	## Ask the spawn director for another monster. Guarded so a behaviour never
	## crashes when the director has not booted yet.
	static func _spawn(species_id: StringName, pos: Vector3, extra: Dictionary = {}) -> Node:
		var em: Node3D = Game.entities_root
		if em != null and em.has_method(&"spawn_species"):
			return em.call(&"spawn_species", species_id, pos, extra)
		return null


# ================================================================== factory
static func create(id: StringName) -> Base:
	match id:
		&"burrower": return Burrower.new()
		&"stalker": return Stalker.new()
		&"ambusher": return Ambusher.new()
		&"mimic": return Mimic.new()
		&"exploder": return Exploder.new()
		&"splitter": return Splitter.new()
		&"healer": return Healer.new()
		&"shielder": return Shielder.new()
		&"charger": return Charger.new()
		&"leaper": return Leaper.new()
		&"diver": return Diver.new()
		&"swarm": return Swarm.new()
		&"turret": return Turret.new()
		&"artillery": return Artillery.new()
		&"blinker": return Blinker.new()
		&"poison_cloud": return PoisonCloud.new()
		&"phaser": return Phaser.new()
		&"projection": return PlaneProjection.new()
		&"pack_hunter": return PackHunter.new()
		&"armoured": return Armoured.new()
		&"eel_ambush": return EelAmbush.new()
		&"floater": return Floater.new()
		&"shocker": return Shocker.new()
		&"skittish": return Skittish.new()
		&"": return null
		_:
			push_warning("[Mobs] unknown behaviour '%s'" % id)
			return null


# =============================================================================
# GROUND
# =============================================================================

## **Perspective monster.** Travels inside the rock where nothing can touch it,
## tracking the player by sound. The moment the player flips the camera, it
## surfaces in the *new* plane — the wall you just turned into a corridor was
## already full of teeth.
class Burrower extends Base:
	enum { BURIED, RISING, SURFACED, DIVING }
	var phase := BURIED
	var timer := 0.0
	var surfaced_time := 0.0
	var flip_pending := false

	func on_spawn(mob) -> void:
		mob.invulnerable = true
		mob.visual_hidden(true)
		mob.gravity_scale = 0.0

	func on_view_flipped(mob, _from_view: int, _to_view: int) -> void:
		if phase == BURIED and mob.distance_to_player() < 26.0:
			flip_pending = true

	func on_tick(mob, delta: float) -> void:
		age += delta
		timer -= delta
		mob.suspend_brain(0.05)
		var p := _player()
		match phase:
			BURIED:
				mob.velocity = Vector3.ZERO
				if p == null:
					return
				# Creep through the ground toward the player's plane position.
				var goal: Vector3 = mob.surface_point_near(p.global_position, _player_layer())
				var to: Vector3 = goal - mob.global_position
				to.y = 0.0
				if to.length() > 0.6:
					mob.global_position += to.normalized() * mob.species.move_speed * 1.5 * delta
					mob.global_position.y = lerpf(mob.global_position.y, goal.y - 2.0, delta * 2.0)
				var close: bool = mob.plane_distance_to(p.global_position) < 3.5
				if (close or flip_pending) and timer <= 0.0:
					flip_pending = false
					phase = RISING
					timer = 0.55
					mob.teleport(mob.surface_point_near(p.global_position, _player_layer()))
					mob.visual_hidden(false)
					mob.telegraph(0.55)
					Events.spawn_particles.emit(&"dig", mob.global_position, 18)
					Events.play_sound.emit(&"burrow_rise", mob.global_position)
			RISING:
				mob.velocity = Vector3(0, 6.0, 0)
				if timer <= 0.0:
					phase = SURFACED
					surfaced_time = 6.5
					mob.invulnerable = false
					mob.gravity_scale = 1.0
					mob.telegraph(0.0)
					if p != null:
						mob.set_target(p)
			SURFACED:
				surfaced_time -= delta
				mob.suspend_brain(0.0)     # hand control back to the tree
				if surfaced_time <= 0.0 or mob.health < mob.max_health * 0.3:
					phase = DIVING
					timer = 0.5
					mob.telegraph(0.4)
			DIVING:
				mob.velocity = Vector3(0, -7.0, 0)
				if timer <= 0.0:
					phase = BURIED
					timer = 2.5
					mob.invulnerable = true
					mob.gravity_scale = 0.0
					mob.visual_hidden(true)
					mob.telegraph(0.0)
					Events.spawn_particles.emit(&"dig", mob.global_position, 12)


## **Perspective monster.** A weeping-angel: it can only move while it is *not*
## in the plane the player is looking at. Freeze it by keeping it on screen —
## and it closes the gap every time you flip away.
class Stalker extends Base:
	var lunge := 0.0

	func on_tick(mob, delta: float) -> void:
		age += delta
		lunge -= delta
		var p := _player()
		if p == null:
			return
		if mob.in_play_layer():
			# Seen. Absolutely still — unless it is already on top of you.
			mob.suspend_brain(0.08)
			mob.motor_stop()
			mob.set_anim(MobVisual.ST_IDLE)
			mob.visual_dim(0.0)
			if mob.plane_distance_to(p.global_position) < mob.species.attack_range and lunge <= 0.0:
				lunge = mob.species.attack_cooldown
				mob.do_melee(p)
			return
		# Unseen. It moves — fast, silently, and it will step into your plane.
		mob.suspend_brain(0.08)
		var lat: float = mob.lateral_to(p.global_position)
		if absf(lat) > 1.2:
			mob.motor_move_lateral(signf(lat), true)
			mob.set_anim(MobVisual.ST_RUN)
			mob.auto_hop()
		else:
			mob.motor_stop()
			mob.step_toward_layer(_player_layer())


## **Perspective monster.** Lies in wait one layer behind the play plane,
## perfectly inert, then shifts forward into the player's face.
class Ambusher extends Base:
	var sprung := false
	var patience := 0.0

	func on_spawn(mob) -> void:
		patience = 0.0
		mob.prefer_layer_offset = 1     # one layer behind the play plane

	func on_tick(mob, delta: float) -> void:
		age += delta
		if sprung:
			return
		var p := _player()
		if p == null:
			return
		mob.suspend_brain(0.08)
		mob.motor_stop()
		mob.set_anim(MobVisual.ST_IDLE)
		if mob.in_play_layer():
			sprung = true
			return
		var lat: float = absf(mob.lateral_to(p.global_position))
		var dy: float = absf(p.global_position.y - mob.global_position.y)
		if lat < 3.2 and dy < 3.0:
			patience += delta
			if patience > 0.25:
				# Spring: shift into the play plane and lunge in the same beat.
				if mob.step_toward_layer(_player_layer()):
					sprung = true
					mob.set_target(p)
					mob.prefer_layer_offset = 0
					mob.telegraph(0.0)
					mob.knockback(Vector3.UP, 4.0)
					Events.play_sound.emit(&"ambush", mob.global_position)
					Events.screen_shake.emit(1.4, 0.2)
			else:
				mob.telegraph(patience / 0.25)
		else:
			patience = 0.0
			mob.telegraph(0.0)
		# Drift laterally to stay lined up with the player, still unseen.
		var lat_signed: float = mob.lateral_to(p.global_position)
		if absf(lat_signed) > 4.0:
			mob.motor_move_lateral(signf(lat_signed), false)


## **Perspective monster.** Disguised as scenery in a layer you have not visited.
## Springs when the player shifts into its layer or flips the camera onto it.
class Mimic extends Base:
	var sprung := false

	func on_spawn(mob) -> void:
		mob.set_anim(MobVisual.ST_IDLE)
		mob.visual_freeze(true)

	func on_view_flipped(mob, _from_view: int, _to_view: int) -> void:
		if not sprung and mob.distance_to_player() < 7.0:
			_spring(mob)

	func on_damaged(mob, _amount: float, _element: String, _source: Node) -> void:
		if not sprung:
			_spring(mob)

	func on_tick(mob, delta: float) -> void:
		age += delta
		if sprung:
			return
		mob.suspend_brain(0.08)
		mob.motor_stop()
		var p := _player()
		if p != null and mob.in_play_layer() and mob.plane_distance_to(p.global_position) < 4.0:
			_spring(mob)

	func _spring(mob) -> void:
		sprung = true
		mob.visual_freeze(false)
		mob.set_anim(MobVisual.ST_ATTACK)
		mob.knockback(Vector3.UP, 6.0)
		var p := _player()
		if p != null:
			mob.set_target(p)
		Events.play_sound.emit(&"mimic_reveal", mob.global_position)
		Events.screen_shake.emit(2.0, 0.3)
		Events.toast("It was not a chest.", "warning")


## Winds up, then sprints in a straight plane-space line until it hits something.
class Charger extends Base:
	enum { READY, WINDUP, CHARGE, STUN }
	var phase := READY
	var timer := 0.0
	var dir := 1.0
	var cooldown := 0.0

	func on_tick(mob, delta: float) -> void:
		age += delta
		timer -= delta
		cooldown -= delta
		var t = mob.target()
		match phase:
			READY:
				if t == null or cooldown > 0.0:
					return
				if not mob.same_play_layer_as(t):
					return
				var lat: float = mob.lateral_to(t.global_position)
				if absf(lat) < mob.species.flagf(&"charge_range", 12.0) and absf(lat) > 2.0:
					phase = WINDUP
					timer = 0.7
					dir = signf(lat)
					mob.face_lateral(int(dir))
					mob.telegraph(1.0)
					mob.set_anim(MobVisual.ST_WINDUP)
					Events.play_sound.emit(&"charge_windup", mob.global_position)
			WINDUP:
				mob.suspend_brain(0.1)
				mob.motor_stop()
				if timer <= 0.0:
					phase = CHARGE
					timer = mob.species.flagf(&"charge_time", 1.4)
					mob.telegraph(0.0)
			CHARGE:
				mob.suspend_brain(0.1)
				mob.motor_move_lateral(dir, true)
				mob.motor_speed_boost = mob.species.flagf(&"charge_speed", 2.4)
				mob.set_anim(MobVisual.ST_RUN)
				if t != null and mob.plane_distance_to(t.global_position) < 1.6:
					mob.do_melee(t, 1.6)
					mob.knockback_target(t, 12.0)
				if timer <= 0.0 or mob.on_wall:
					phase = STUN
					timer = 0.9 if mob.on_wall else 0.3
					mob.motor_speed_boost = 1.0
					if mob.on_wall:
						Events.screen_shake.emit(2.2, 0.25)
						Events.spawn_particles.emit(&"impact", mob.global_position, 14)
			STUN:
				mob.suspend_brain(0.1)
				mob.motor_stop()
				mob.set_anim(MobVisual.ST_HURT)
				if timer <= 0.0:
					phase = READY
					cooldown = mob.species.flagf(&"charge_cooldown", 3.0)


## Big arcing jumps — including jumps that change depth layer mid-flight, which
## is how it crosses chasms the player cannot.
class Leaper extends Base:
	var cooldown := 0.0
	var airborne := false
	var layer_hop := 0

	func on_tick(mob, delta: float) -> void:
		age += delta
		cooldown -= delta
		var t = mob.target()
		if t == null:
			return
		if airborne:
			if layer_hop != 0 and mob.velocity.y < 1.0:
				mob.step_toward_layer(mob.depth_layer() + layer_hop)
				layer_hop = 0
			if mob.on_floor:
				airborne = false
				mob.set_anim(MobVisual.ST_IDLE)
			return
		if cooldown > 0.0 or not mob.on_floor:
			return
		var lat: float = mob.lateral_to(t.global_position)
		var dl: int = mob.layer_delta_to(t)
		if absf(lat) > 3.0 and absf(lat) < 14.0:
			cooldown = mob.species.flagf(&"leap_cooldown", 2.4)
			airborne = true
			mob.face_lateral(signi(int(signf(lat))))
			mob.jump(mob.species.jump_speed * 1.25)
			mob.set_plane_velocity(signf(lat) * mob.species.move_speed * 1.9)
			mob.set_anim(MobVisual.ST_ATTACK)
			# Mid-air layer change: the leap can carry it into your plane.
			layer_hop = signi(dl)
			Events.play_sound.emit(&"leap", mob.global_position)


## Shell-curl: takes almost nothing while curled, but cannot act.
class Armoured extends Base:
	var curled := 0.0

	func modify_damage(mob, amount: float, element: String, _source: Node) -> float:
		if curled > 0.0:
			return amount * 0.12
		if element == Const.ELEM_PHYSICAL and amount > mob.max_health * 0.12:
			curled = 1.6
			mob.set_anim(MobVisual.ST_HURT)
			Events.play_sound.emit(&"shell_curl", mob.global_position)
		return amount

	func on_tick(mob, delta: float) -> void:
		age += delta
		if curled > 0.0:
			curled -= delta
			mob.suspend_brain(0.08)
			mob.motor_stop()
			mob.set_anim(MobVisual.ST_IDLE)
			mob.visual_squash(0.5)
			if curled <= 0.0:
				mob.visual_squash(1.0)


## Wolf-style pack: shares aggro with everything of its species nearby.
class PackHunter extends Base:
	var howl := 0.0

	func on_damaged(mob, _amount: float, _element: String, source: Node) -> void:
		if howl <= 0.0 and source != null:
			howl = 8.0
			mob.call_for_help(18.0)
			Events.play_sound.emit(&"howl", mob.global_position)

	func on_tick(mob, delta: float) -> void:
		age += delta
		howl -= delta
		if howl <= 0.0 and mob.target() != null and mob.brain != null and not mob.brain.bb.called_help:
			mob.brain.bb.called_help = true
			howl = 8.0
			mob.call_for_help(18.0)


# =============================================================================
# FLYING
# =============================================================================

## Circles above its target, then commits to a fast dive.
class Diver extends Base:
	enum { CIRCLE, DIVE, CLIMB }
	var phase := CIRCLE
	var timer := 0.0
	var orbit := 0.0

	func on_tick(mob, delta: float) -> void:
		age += delta
		timer -= delta
		var t = mob.target()
		if t == null:
			return
		mob.suspend_brain(0.08)
		var tp: Vector3 = t.global_position
		match phase:
			CIRCLE:
				orbit += delta * 2.2
				var goal := tp + Vector3(0, mob.species.flagf(&"dive_height", 7.0), 0)
				goal = mob.plane_offset(goal, cos(orbit) * 5.0)
				mob.motor_fly_to(goal, 1.0)
				mob.set_anim(MobVisual.ST_WALK)
				if timer <= 0.0 and absf(mob.lateral_to(tp)) < 2.5:
					phase = DIVE
					timer = 1.4
					mob.telegraph(1.0)
			DIVE:
				mob.motor_fly_to(tp + Vector3(0, 0.4, 0), 2.6)
				mob.set_anim(MobVisual.ST_RUN)
				if mob.plane_distance_to(tp) < 1.7:
					mob.do_melee(t, 1.4)
					mob.knockback_target(t, 8.0)
					phase = CLIMB
					timer = 1.6
					mob.telegraph(0.0)
				elif timer <= 0.0:
					phase = CLIMB
					timer = 1.4
					mob.telegraph(0.0)
			CLIMB:
				mob.motor_fly_to(tp + Vector3(0, mob.species.flagf(&"dive_height", 7.0) + 2.0, 0), 1.3)
				if timer <= 0.0:
					phase = CIRCLE
					timer = mob.species.flagf(&"dive_cooldown", 2.2)


## A cloud of tiny things. Moves erratically and splits when hurt.
class Swarm extends Base:
	var wobble := 0.0
	var split_done := false

	func on_tick(mob, delta: float) -> void:
		age += delta
		wobble += delta * 6.0
		mob.motor_wobble = Vector2(sin(wobble * 1.3) * 2.2, cos(wobble) * 1.6)

	func on_damaged(mob, _amount: float, _element: String, _source: Node) -> void:
		if split_done or mob.health > mob.max_health * 0.5:
			return
		split_done = true
		var child: StringName = mob.species.flag(&"child", &"")
		if child == &"":
			return
		for i in 2:
			var off := Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.8), randf_range(-0.6, 0.6))
			_spawn(child, mob.global_position + off, {"scale": 0.7, "no_loot": true})


## Rises slowly, pops loudly.
class Floater extends Base:
	func on_spawn(mob) -> void:
		mob.gravity_scale = -0.06

	func on_tick(mob, delta: float) -> void:
		age += delta
		mob.velocity.y = clampf(mob.velocity.y, -2.0, 2.2)

	func on_death(mob, _source: Node) -> void:
		var r: float = mob.species.flagf(&"pop_radius", 3.2)
		mob.area_damage(mob.global_position, r, mob.attack_power() * 1.4, mob.species.element)
		Events.spawn_particles.emit(&"gas_pop", mob.global_position, 26)
		Events.play_sound.emit(&"pop", mob.global_position)


## **Perspective monster.** Oscillates between depth layers on a fixed beat, so
## it is only hittable on half the rhythm. Utterly infuriating; entirely fair.
class Phaser extends Base:
	var timer := 0.0
	var dir := 1

	func on_tick(mob, delta: float) -> void:
		age += delta
		timer -= delta
		if timer > 0.0:
			return
		timer = mob.species.flagf(&"phase_interval", 1.6)
		var here: int = mob.depth_layer()
		var play: int = _player_layer()
		# Bias back toward the play layer so it never wanders off screen.
		if absi(here - play) >= 2:
			dir = signi(play - here)
		elif here == play:
			dir = 1 if randf() < 0.5 else -1
		if not mob.step_toward_layer(here + dir):
			dir = -dir
		Events.spawn_particles.emit(&"phase", mob.global_position, 8)


## **Perspective monster.** Whatever plane you look from, it is already there:
## it re-materialises in the play layer the instant the layer changes.
class PlaneProjection extends Base:
	var settle := 0.0

	func on_view_flipped(mob, _f: int, _t: int) -> void:
		settle = 0.35
		mob.snap_to_layer(_player_layer())
		Events.spawn_particles.emit(&"phase", mob.global_position, 14)

	func on_tick(mob, delta: float) -> void:
		age += delta
		settle -= delta
		if settle > 0.0:
			mob.suspend_brain(0.05)
			mob.motor_stop()
			return
		if not mob.in_play_layer():
			mob.snap_to_layer(_player_layer())


# =============================================================================
# AQUATIC
# =============================================================================

## **Perspective monster.** Hangs in the water one layer back, invisible against
## the murk, and strikes sideways out of the wall of water beside you.
class EelAmbush extends Base:
	var struck := false
	var recover := 0.0

	func on_spawn(mob) -> void:
		mob.prefer_layer_offset = 1

	func on_tick(mob, delta: float) -> void:
		age += delta
		recover -= delta
		var p := _player()
		if p == null:
			return
		if struck:
			if recover <= 0.0 and mob.plane_distance_to(p.global_position) > 8.0:
				struck = false
				mob.prefer_layer_offset = 1
			return
		mob.suspend_brain(0.08)
		var lat: float = mob.lateral_to(p.global_position)
		var dy: float = p.global_position.y - mob.global_position.y
		if absf(lat) > 2.5 or absf(dy) > 2.5:
			mob.motor_fly_to(mob.plane_offset(p.global_position, 0.0), 0.55)
			mob.set_anim(MobVisual.ST_WALK)
			mob.telegraph(0.0)
			return
		mob.telegraph(minf(1.0, mob.telegraph_value + delta * 3.0))
		if mob.telegraph_value >= 1.0:
			if mob.step_toward_layer(_player_layer()):
				struck = true
				recover = 3.0
				mob.set_target(p)
				mob.prefer_layer_offset = 0
				mob.telegraph(0.0)
				mob.do_melee(p, 2.2)
				Events.screen_shake.emit(1.6, 0.2)
				Events.play_sound.emit(&"eel_strike", mob.global_position)


## Contact shock, slow drift, immune to its own element.
class Shocker extends Base:
	var pulse := 0.0

	func on_tick(mob, delta: float) -> void:
		age += delta
		pulse -= delta
		mob.visual_glow(0.25 + 0.25 * sin(age * 3.0))
		if pulse > 0.0:
			return
		var p := _player()
		if p == null or not mob.same_play_layer_as(p):
			return
		if mob.global_position.distance_to(p.global_position) <= mob.species.attack_range + 0.6:
			pulse = mob.species.attack_cooldown
			mob.area_damage(mob.global_position, mob.species.attack_range + 0.6,
				mob.attack_power(), mob.species.element)
			Events.spawn_particles.emit(&"shock", mob.global_position, 12)


# =============================================================================
# RANGED
# =============================================================================

## Rooted plant that tracks and spits.
class Turret extends Base:
	var cooldown := 0.0

	func on_spawn(mob) -> void:
		mob.gravity_scale = 0.0
		mob.knockback_immune = true

	func on_tick(mob, delta: float) -> void:
		age += delta
		cooldown -= delta
		mob.suspend_brain(0.08)
		mob.motor_stop()
		var t = mob.target()
		if t == null:
			mob.set_anim(MobVisual.ST_IDLE)
			return
		mob.face_toward(t.global_position)
		if not mob.same_play_layer_as(t):
			mob.set_anim(MobVisual.ST_IDLE)
			return
		if cooldown <= 0.0 and mob.plane_distance_to(t.global_position) <= mob.species.attack_range:
			cooldown = mob.species.attack_cooldown
			mob.set_anim(MobVisual.ST_WINDUP)
			mob.do_ranged(t)


## Lobs a high arc: it can shell you over terrain, and backs off when closed on.
class Artillery extends Base:
	var cooldown := 0.0

	func on_tick(mob, delta: float) -> void:
		age += delta
		cooldown -= delta
		var t = mob.target()
		if t == null:
			return
		var d: float = mob.plane_distance_to(t.global_position)
		if d < mob.species.flagf(&"min_range", 6.0):
			mob.suspend_brain(0.08)
			mob.motor_move_lateral(-signf(mob.lateral_to(t.global_position)), true)
			mob.set_anim(MobVisual.ST_RUN)
			return
		if cooldown <= 0.0 and d <= mob.species.attack_range and mob.same_play_layer_as(t):
			cooldown = mob.species.attack_cooldown
			mob.suspend_brain(0.5)
			mob.motor_stop()
			mob.set_anim(MobVisual.ST_WINDUP)
			mob.do_ranged(t, {"arc": true, "gravity": 0.7})


## **Perspective monster.** Blinks one layer sideways whenever it is hurt or
## whenever the player closes in — it fights you from the layer behind the wall.
class Blinker extends Base:
	var cooldown := 0.0

	func on_damaged(mob, _amount: float, _element: String, _source: Node) -> void:
		if cooldown <= 0.0:
			_blink(mob)

	func on_tick(mob, delta: float) -> void:
		age += delta
		cooldown -= delta
		var t = mob.target()
		if t == null:
			return
		if cooldown <= 0.0 and mob.plane_distance_to(t.global_position) < 4.0:
			_blink(mob)
		# It fires across layers: being off-plane is not safety, it is cover.
		if mob.can_attack() and mob.plane_distance_to(t.global_position) <= mob.species.attack_range:
			mob.do_ranged(t, {"pierce_layers": true})

	func _blink(mob) -> void:
		cooldown = mob.species.flagf(&"blink_cooldown", 2.6)
		var dir := 1 if randf() < 0.5 else -1
		if not mob.step_toward_layer(mob.depth_layer() + dir):
			mob.step_toward_layer(mob.depth_layer() - dir)
		Events.spawn_particles.emit(&"blink", mob.global_position, 16)
		Events.play_sound.emit(&"blink", mob.global_position)


# =============================================================================
# SPECIAL
# =============================================================================

## Runs at you and detonates. Death and contact both trigger it.
class Exploder extends Base:
	var fuse := -1.0
	var blown := false

	func on_tick(mob, delta: float) -> void:
		age += delta
		if blown:
			return
		var t = mob.target()
		if fuse >= 0.0:
			fuse -= delta
			mob.telegraph(1.0 - clampf(fuse / 0.9, 0.0, 1.0))
			mob.motor_speed_boost = 1.4
			if fuse <= 0.0:
				_detonate(mob)
			return
		if t != null and mob.same_play_layer_as(t) \
				and mob.plane_distance_to(t.global_position) < mob.species.flagf(&"fuse_range", 2.6):
			fuse = 0.9
			Events.play_sound.emit(&"fuse", mob.global_position)

	func on_death(mob, _source: Node) -> void:
		if not blown:
			_detonate(mob)

	func on_attack(mob, _t) -> bool:
		if fuse < 0.0:
			fuse = 0.5
		return true

	func _detonate(mob) -> void:
		if blown:
			return
		blown = true
		var r: float = mob.species.flagf(&"blast_radius", 4.0)
		mob.area_damage(mob.global_position, r, mob.attack_power() * 2.6, mob.species.element)
		if mob.species.flagb(&"terrain_damage", false):
			World.explode(mob.global_position + Vector3(0, 0.4, 0), r * 0.6, 3.0)
		Events.spawn_particles.emit(&"explosion", mob.global_position, 34)
		Events.play_sound.emit(&"explosion", mob.global_position)
		Events.screen_shake.emit(r, 0.35)
		mob.die_quietly()


## Dies into smaller copies of itself, recursively, down to a floor size.
class Splitter extends Base:
	func on_death(mob, _source: Node) -> void:
		var gen: int = int(mob.spawn_opts.get("generation", 0))
		var max_gen: int = mob.species.flagi(&"generations", 2)
		if gen >= max_gen:
			return
		var n: int = mob.species.flagi(&"split_count", 2)
		var child: StringName = mob.species.flag(&"child", mob.species_id)
		var s: float = float(mob.spawn_opts.get("scale", 1.0)) * mob.species.flagf(&"split_scale", 0.62)
		for i in n:
			var ang := TAU * float(i) / float(n)
			var off := Vector3(cos(ang) * 0.5, 0.35, sin(ang) * 0.5)
			var c = _spawn(child, mob.global_position + off,
				{"scale": s, "generation": gen + 1, "no_loot": gen + 1 >= max_gen})
			if c != null and c is VoxelEntity:
				(c as VoxelEntity).knockback(off.normalized() + Vector3.UP * 0.5, 5.0)
		Events.spawn_particles.emit(&"splat", mob.global_position, 20)


## Support: heals the most wounded ally in range and keeps its distance.
class Healer extends Base:
	var cooldown := 0.0

	func on_tick(mob, delta: float) -> void:
		age += delta
		cooldown -= delta
		if cooldown > 0.0:
			return
		var radius: float = mob.species.flagf(&"heal_radius", 10.0)
		var best = null
		var worst := 1.0
		for other in mob.allies_in_radius(radius):
			if other == mob:
				continue
			var frac: float = other.health / maxf(1.0, other.max_health)
			if frac < worst and frac < 0.95:
				worst = frac
				best = other
		if best == null:
			return
		cooldown = mob.species.attack_cooldown
		best.heal(mob.species.flagf(&"heal_amount", 12.0))
		mob.set_anim(MobVisual.ST_WINDUP)
		Events.spawn_particles.emit(&"heal", best.global_position, 12)
		Events.play_sound.emit(&"heal", best.global_position)


## Support: projects a damage-reduction bubble over nearby monsters.
class Shielder extends Base:
	var pulse := 0.0

	func modify_damage(mob, amount: float, _element: String, _source: Node) -> float:
		return amount * (1.0 - mob.species.flagf(&"self_shield", 0.35))

	func on_tick(mob, delta: float) -> void:
		age += delta
		pulse -= delta
		mob.visual_glow(0.2 + 0.2 * sin(age * 2.0))
		if pulse > 0.0:
			return
		pulse = 1.0
		var radius: float = mob.species.flagf(&"shield_radius", 9.0)
		var amount: float = mob.species.flagf(&"shield_strength", 0.4)
		for other in mob.allies_in_radius(radius):
			if other != mob and other.has_method(&"grant_shield"):
				other.grant_shield(amount, 1.4)


## Drifts as a lingering hazard; hurts everything organic that shares its cell.
class PoisonCloud extends Base:
	var tick_timer := 0.0

	func on_spawn(mob) -> void:
		mob.gravity_scale = 0.0
		mob.knockback_immune = true

	func modify_damage(_mob, amount: float, element: String, _source: Node) -> float:
		# Diffuse: physical weapons pass straight through most of it.
		return amount * (0.25 if element == Const.ELEM_PHYSICAL else 1.0)

	func on_tick(mob, delta: float) -> void:
		age += delta
		tick_timer -= delta
		mob.velocity = Vector3(mob.velocity.x, sin(age * 0.9) * 0.4, mob.velocity.z)
		if tick_timer > 0.0:
			return
		tick_timer = 0.6
		var r: float = mob.species.flagf(&"cloud_radius", 3.0)
		mob.area_damage(mob.global_position, r, mob.attack_power() * 0.35, Const.ELEM_POISON)
		mob.apply_status_in_radius(&"poison", 4.0, r)
		Events.spawn_particles.emit(&"miasma", mob.global_position, 6)


## Passive critter: bolts away from anything that threatens it.
class Skittish extends Base:
	var panic := 0.0

	func on_damaged(mob, _amount: float, _element: String, source: Node) -> void:
		panic = 6.0
		if source != null:
			mob.brain.bb.threat_source = source

	func on_tick(mob, delta: float) -> void:
		age += delta
		panic -= delta
		var p := _player()
		if p == null:
			return
		var d: float = mob.plane_distance_to(p.global_position)
		if d < mob.species.flagf(&"flee_range", 6.0) or panic > 0.0:
			mob.suspend_brain(0.08)
			var away := -signf(mob.lateral_to(p.global_position))
			if away == 0.0:
				away = 1.0
			mob.motor_move_lateral(away, true)
			mob.set_anim(MobVisual.ST_RUN)
			mob.auto_hop()
			# Cornered against a wall? Duck into another layer.
			if mob.on_wall and randf() < 0.05:
				mob.step_toward_layer(mob.depth_layer() + (1 if randf() < 0.5 else -1))
