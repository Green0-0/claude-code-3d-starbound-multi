## The shared monster body.
##
## `MobBase` owns everything a creature needs that is not *thinking*: stats
## scaled by the planet's threat level, elemental resistances, the damage flash,
## the death dissolve and its loot, and the motor that turns "go right" into
## plane-space velocity, jumps, ledge handling and layer shifts.
##
## Decisions live in `MobBrain`, per-species mechanics in `MobBehaviour`,
## navigation in `MobPath`, the sprite in `MobVisual`. This class is the glue
## and the public API every other module talks to.
##
## Layer discipline: a monster's depth coordinate is *locked* to the centre of
## an integer layer at all times. It only ever changes layer through
## `step_toward_layer()`, which animates the same way the player's shift does.
## That is what makes "which plane is this thing in" always readable.
class_name MobBase
extends VoxelEntity

## `navigate_to` results.
const NAV_MOVING := 0
const NAV_ARRIVED := 1
const NAV_BLOCKED := 2

const PROJECTILE_SCENE := "res://combat/projectile.tscn"

# ------------------------------------------------------------------ identity
var species_id: StringName = &""
var species: MobSpecies = null
var threat_tier: int = 1
var planet_threat: int = 1
var spawn_opts: Dictionary = {}
var size_scale := 1.0

# ------------------------------------------------------------------- modules
var brain: MobBrain = null
var behaviour: MobBehaviour.Base = null
var visual: MobVisual = null

# ---------------------------------------------------------------- aggro/leash
var leash_range := 30.0
var home_pos := Vector3.ZERO
var home_layer := 0
## Pets follow this node instead of hunting the player.
var escort_of: Node3D = null
## Behaviours that want to sit off-plane set this (in layers behind the player).
var prefer_layer_offset := 0

# -------------------------------------------------------------------- combat
var knockback_immune := false
var shield_amount := 0.0
var shield_time := 0.0
var telegraph_value := 0.0
## Per-instance multiplier on incoming damage. Bosses raise it when a phase
## strips their armour; status effects can lower it.
var damage_taken_mult := 1.0
## Extra flat armour on top of the species value.
var bonus_armour := 0.0

# --------------------------------------------------------------------- motor
var motor_speed_boost := 1.0
var motor_wobble := Vector2.ZERO

var _move_lateral := 0.0
var _move_run := false
var _fly_target := Vector3.ZERO
var _has_fly_target := false
var _attack_cd := 0.0
var _layer_cd := 0.0
var _brain_suspend := 0.0
var _anim: StringName = MobVisual.ST_IDLE
var _anim_hold := 0.0
var _hurt_time := 0.0

# ------------------------------------------------------------------ pathing
var _path: Array[Vector3] = []
var _path_i := 0
var _path_goal := Vector3.ZERO
var _repath := 0.0
var _no_progress := 0.0
var _last_progress_pos := Vector3.ZERO

# ------------------------------------------------------------------ internal
var _lock_depth := 0.0
var _cached_view := -1
var _was_shifting := false
var _dying := false
var _sense_timer := 0.0
var _throttle := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	add_to_group(&"monsters")
	_rng.randomize()
	# Stagger the far-away think budget so the whole planet does not update on
	# the same frame.
	_throttle = _rng.randi() % 3
	if species == null and species_id != &"":
		apply_species(species_id, spawn_opts)
	damaged.connect(_on_self_damaged)
	_recompute_lock()
	home_pos = global_position
	home_layer = depth_layer()
	if brain != null:
		brain.bb.home = home_pos
		brain.bb.home_layer = home_layer
		brain.bb.patrol_min = plane_position().x - 8.0
		brain.bb.patrol_max = plane_position().x + 8.0


## `Game.spawn_entity` calls this. Keys: species, scale, generation, no_loot,
## threat, faction, escort, patrol.
func configure(setup: Dictionary) -> void:
	var sid: StringName = setup.get("species", setup.get("species_id", species_id))
	apply_species(sid, setup)


# ============================================================= species setup
## Build this monster from a species definition. Safe to call before or after
## the node enters the tree.
func apply_species(p_id: StringName, opts: Dictionary = {}) -> void:
	spawn_opts = opts.duplicate()
	species_id = p_id
	species = MobSpeciesDB.get_species(p_id)
	if species == null:
		push_warning("[Mobs] unknown species '%s'" % p_id)
		species = MobSpecies.new(p_id, "Anomaly")
	planet_threat = int(opts.get("threat", _planet_threat()))
	threat_tier = species.tier
	size_scale = float(opts.get("scale", 1.0))

	box_size = species.box_size * size_scale
	max_health = species.scaled_health(planet_threat) * size_scale
	health = max_health
	move_speed = species.move_speed
	jump_speed = species.jump_speed
	leash_range = species.leash_range
	faction = opts.get("faction", species.faction)
	affected_by_liquid = true
	gravity_scale = 0.0 if species.is_flying() or species.is_rooted() else 1.0
	if species.locomotion == MobSpecies.LOCO_SWIM:
		gravity_scale = 0.15

	brain = MobBrain.build(opts.get("brain", species.brain))
	behaviour = MobBehaviour.create(species.behaviour)
	_build_visual()
	if behaviour != null:
		behaviour.on_spawn(self)
	if opts.has("escort"):
		escort_of = opts["escort"]
	if is_inside_tree():
		# Species that want to lurk off-plane start there.
		if prefer_layer_offset != 0:
			snap_to_layer(View.layer + prefer_layer_offset * View.depth_sign())
		_recompute_lock()
		home_pos = global_position
		home_layer = depth_layer()
		if brain != null:
			brain.bb.home = home_pos
			brain.bb.home_layer = home_layer


func _planet_threat() -> int:
	var meta: Dictionary = World.planet
	return int(meta.get("threat", meta.get("threat_level", 1)))


func _build_visual() -> void:
	if visual != null:
		visual.queue_free()
	visual = MobVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(species.visual, int(spawn_opts.get("variant", _rng.randi() & 3)),
		box_size.y)
	visual.position = Vector3.ZERO


# ================================================================= main loop
func _physics_process(delta: float) -> void:
	if _dying or species == null:
		return
	if Game.paused or not World.ready_flag:
		return
	if _cached_view != View.view:
		_on_view_changed()
	_tick_timers(delta)

	# Distance throttle: creatures far from the camera think at a third rate.
	var far := plane_distance_to(_player_pos()) > 30.0
	_throttle = (_throttle + 1) % 3
	var think := not far or _throttle == 0
	var step: float = delta * (3.0 if (far and think) else 1.0)

	if think:
		_sense(step)
		if behaviour != null:
			behaviour.on_tick(self, step)
		if _brain_suspend <= 0.0 and brain != null:
			brain.tick(self, step)
	_apply_motor(delta)
	integrate(delta)
	_post_integrate()
	_update_visual_state()


func _tick_timers(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_layer_cd = maxf(0.0, _layer_cd - delta)
	_brain_suspend = maxf(0.0, _brain_suspend - delta)
	_repath = maxf(0.0, _repath - delta)
	_hurt_time = maxf(0.0, _hurt_time - delta)
	_anim_hold = maxf(0.0, _anim_hold - delta)
	if shield_time > 0.0:
		shield_time -= delta
		if shield_time <= 0.0:
			shield_amount = 0.0


func _on_view_changed() -> void:
	var from := _cached_view
	_cached_view = View.view
	# The depth axis just changed meaning; re-derive the lock and drop the path.
	_recompute_lock()
	_path.clear()
	_path_i = 0
	_repath = 0.0
	if behaviour != null and from >= 0:
		behaviour.on_view_flipped(self, from, View.view)


func _recompute_lock() -> void:
	_lock_depth = float(depth_layer()) + 0.5
	_cached_view = View.view


func _post_integrate() -> void:
	if is_shifting():
		_was_shifting = true
		return
	if _was_shifting:
		_was_shifting = false
		_recompute_lock()
	# Hold the creature exactly in its layer so "which plane is it in" is never
	# ambiguous by half a block.
	var p := global_position
	if View.depth_axis() == 0:
		p.x = _lock_depth
	else:
		p.z = _lock_depth
	global_position = p


# ================================================================= perception
func _sense(delta: float) -> void:
	if brain == null:
		return
	var bb := brain.bb
	_sense_timer -= delta
	if _sense_timer > 0.0:
		return
	_sense_timer = 0.22

	if faction == &"ally":
		_sense_ally(bb)
		return
	if species.is_passive() and bb.target == null:
		# Critters only "target" what frightens them; proximity is enough.
		var pl := Game.player
		if pl != null and plane_distance_to(pl.global_position) < species.aggro_range * 0.6 \
				and same_play_layer_as(pl):
			bb.target = pl
			bb.last_known_pos = pl.global_position
			bb.time_since_seen = 0.0
		return

	var target: Node3D = bb.target
	var player := Game.player
	if target == null and player != null and not player.dead:
		var dl: int = absi(layer_delta_to(player))
		var d: float = plane_distance_to(player.global_position)
		var range_mult: float = 1.0 if dl == 0 else 0.7
		if dl <= species.sight_layers and d <= species.aggro_range * range_mult:
			if dl > 0 or has_line_of_sight(player):
				bb.alert = minf(1.0, bb.alert + 0.5)
				if bb.alert >= 0.5:
					set_target(player)
			else:
				bb.alert = maxf(0.0, bb.alert - 0.15)
		else:
			bb.alert = maxf(0.0, bb.alert - 0.1)

	target = bb.target
	if target != null:
		var gone: bool = not is_instance_valid(target) or (target is VoxelEntity and (target as VoxelEntity).dead)
		var d2: float = 1e9 if gone else plane_distance_to(target.global_position)
		if not gone:
			bb.last_known_pos = target.global_position
			bb.last_known_layer = floori(View.depth_of(target.global_position))
			bb.time_since_seen = 0.0
			bb.threat = clampf(1.0 - health / maxf(1.0, max_health), 0.0, 1.0) * 4.0
		if gone or d2 > leash_range * 1.6:
			bb.forget()
			_path.clear()


func _sense_ally(bb: MobBrain.Blackboard) -> void:
	if bb.target != null and is_instance_valid(bb.target) \
			and not (bb.target is VoxelEntity and (bb.target as VoxelEntity).dead):
		return
	bb.target = null
	var best: Node3D = null
	var best_d := species.aggro_range
	for n: Node in get_tree().get_nodes_in_group(&"monsters"):
		var m := n as MobBase
		if m == null or m == self or m.dead or m.faction != &"hostile":
			continue
		var d := plane_distance_to(m.global_position)
		if d < best_d and absi(layer_delta_to(m)) <= 1:
			best_d = d
			best = m
	if best != null:
		set_target(best)


## Forwarded by the spawn director for loud world events.
func hear(world_pos: Vector3, loudness: float = 1.0) -> void:
	if brain == null or dead or species.is_rooted():
		return
	if global_position.distance_to(world_pos) > species.hearing_range * loudness:
		return
	brain.bb.sound_pos = world_pos
	brain.bb.has_sound = true


func set_target(t: Node3D) -> void:
	if brain == null or t == null:
		return
	if brain.bb.target == t:
		return
	brain.bb.target = t
	brain.bb.last_known_pos = t.global_position
	brain.bb.last_known_layer = floori(View.depth_of(t.global_position))
	brain.bb.time_since_seen = 0.0
	brain.bb.alert = 1.0
	_path.clear()


func target() -> Node3D:
	return brain.bb.target if brain != null else null


func clear_target() -> void:
	if brain != null:
		brain.bb.forget()


func has_line_of_sight(t: Node3D) -> bool:
	if t == null:
		return false
	return MobPath.line_of_sight(aabb_center(), t.global_position + Vector3(0, 0.8, 0),
		species.aggro_range + 4.0)


# ============================================================== plane helpers
## Integer depth layer this monster occupies under the current view.
func depth_layer() -> int:
	return floori(View.depth_of(global_position))


func in_play_layer() -> bool:
	return depth_layer() == View.layer


## How many layers away `other` is (positive = deeper than us).
func layer_delta_to(other: Node3D) -> int:
	if other == null:
		return 0
	return floori(View.depth_of(other.global_position)) - depth_layer()


func layer_delta_to_pos(pos: Vector3) -> int:
	return floori(View.depth_of(pos)) - depth_layer()


func same_play_layer_as(other: Node3D) -> bool:
	return other != null and layer_delta_to(other) == 0


## Signed screen-right distance to a world point.
func lateral_to(pos: Vector3) -> float:
	return Const.lateral_of(pos - global_position, View.view)


## Distance measured only in the visible plane (lateral + vertical).
func plane_distance_to(pos: Vector3) -> float:
	return Vector2(lateral_to(pos), pos.y - global_position.y).length()


func distance_to_player() -> float:
	var p := Game.player
	return 1e9 if p == null else global_position.distance_to(p.global_position)


func _player_pos() -> Vector3:
	var p := Game.player
	return p.global_position if p != null else global_position


## Copy `pos` but placed in depth layer `layer`.
func world_at_layer(pos: Vector3, layer: int) -> Vector3:
	var out := pos
	if View.depth_axis() == 0:
		out.x = float(layer) + 0.5
	else:
		out.z = float(layer) + 0.5
	return out


## `pos` nudged `amount` blocks along screen-right.
func plane_offset(pos: Vector3, amount: float) -> Vector3:
	var r := View.right()
	return pos + Vector3(float(r.x), 0.0, float(r.z)) * amount


## Ground-level point in `layer` directly above/below the given position.
func surface_point_near(pos: Vector3, layer: int) -> Vector3:
	var p := world_at_layer(pos, layer)
	var y := World.surface_y(floori(p.x), floori(p.z), floori(p.y) + 8)
	p.y = float(y + 1) if y >= 0 else pos.y
	return p


# ============================================================== layer shifting
## Move one voxel along the depth axis toward `target_layer`. Returns false when
## the destination is solid, which is exactly the rule the player's shift obeys.
func step_toward_layer(target_layer: int) -> bool:
	if dead or is_shifting() or _layer_cd > 0.0:
		return false
	var cur := depth_layer()
	if cur == target_layer:
		return false
	var s := signi(target_layer - cur)
	var dest := world_at_layer(global_position, cur + s)
	if not VoxelPhysics.aabb_is_free(dest, box_size):
		return false
	_layer_cd = species.flagf(&"layer_cooldown", 0.4)
	_lock_depth = float(cur + s) + 0.5
	begin_layer_shift(dest)
	Events.spawn_particles.emit(&"layer_shift", global_position, 6)
	Events.play_sound.emit(&"monster_shift", global_position)
	return true


## Hard teleport into a layer, no animation. For phase / projection monsters.
func snap_to_layer(layer: int) -> void:
	if dead:
		return
	teleport(world_at_layer(global_position, layer))


## Any teleport re-derives the depth lock, otherwise the next physics frame
## would yank the creature back to the layer it used to be in.
func teleport(dest: Vector3) -> void:
	super.teleport(dest)
	_recompute_lock()
	_path.clear()


## How far behind the play plane this monster sits (negative = in front).
func layer_offset_from_play() -> int:
	return (depth_layer() - View.layer) * View.depth_sign()


# ==================================================================== motor
func motor_stop() -> void:
	_move_lateral = 0.0
	_has_fly_target = false


func motor_move_lateral(dir: float, run: bool = false) -> void:
	_move_lateral = clampf(dir, -1.5, 1.5)
	_move_run = run
	_has_fly_target = false
	if absf(dir) > 0.05:
		face_lateral(1 if dir > 0.0 else -1)


func motor_fly_to(world_pos: Vector3, speed_mult: float = 1.0) -> void:
	_fly_target = world_pos
	_has_fly_target = true
	_move_run = speed_mult > 1.2
	motor_speed_boost = speed_mult
	face_toward(world_pos)


func face_lateral(dir: int) -> void:
	facing = 1 if dir >= 0 else -1


## Jump over a one-or-two block obstacle if there is one right in front.
func auto_hop() -> void:
	if not on_floor or species.is_flying():
		return
	var dir := facing
	var h := MobPath.obstacle_height(global_position, dir, _height_blocks())
	if h >= 1 and h <= 3:
		jump()


## True when moving `dir` would walk into a wall too tall to hop, or off a
## ledge the creature will not survive.
func blocked_ahead(dir: int) -> bool:
	if species.is_flying() or species.locomotion == MobSpecies.LOCO_SWIM:
		return not VoxelPhysics.aabb_is_free(
			global_position + Vector3(View.right()) * float(dir), box_size)
	var h := MobPath.obstacle_height(global_position, dir, _height_blocks())
	if h > 3:
		return true
	if species.flagb(&"reckless", false):
		return false
	return MobPath.is_ledge_ahead(global_position, dir, _height_blocks())


func _height_blocks() -> int:
	return maxi(1, ceili(box_size.y))


func _apply_motor(delta: float) -> void:
	if is_shifting():
		return
	var speed := move_speed * motor_speed_boost
	if _move_run:
		speed *= species.run_multiplier
	if knockback_lock > 0.0:
		return

	match species.locomotion:
		MobSpecies.LOCO_STATIC:
			velocity.x = 0.0
			velocity.z = 0.0
		MobSpecies.LOCO_FLY, MobSpecies.LOCO_HOVER:
			_fly_motor(speed, delta)
		MobSpecies.LOCO_SWIM:
			if submersion > 0.3:
				_fly_motor(speed, delta)
			else:
				set_plane_velocity(_move_lateral * speed * 0.4)
		_:
			set_plane_velocity(_move_lateral * speed)
	motor_speed_boost = 1.0


func _fly_motor(speed: float, delta: float) -> void:
	var desired := Vector2.ZERO
	if _has_fly_target:
		var d := Vector2(lateral_to(_fly_target), _fly_target.y - global_position.y)
		if d.length() > 0.25:
			desired = d.normalized() * speed
	elif absf(_move_lateral) > 0.01:
		desired = Vector2(_move_lateral * speed, 0.0)
	desired += motor_wobble
	var cur := Vector2(plane_velocity(), velocity.y)
	cur = cur.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
	set_plane_velocity(cur.x)
	velocity.y = cur.y


# ================================================================ navigation
func _path_opts() -> Dictionary:
	var profile := MobPath.PROFILE_WALK
	match species.locomotion:
		MobSpecies.LOCO_FLY, MobSpecies.LOCO_HOVER:
			profile = MobPath.PROFILE_FLY
		MobSpecies.LOCO_SWIM:
			profile = MobPath.PROFILE_SWIM
		MobSpecies.LOCO_AMPHIBIOUS:
			profile = MobPath.PROFILE_AMPHIBIOUS
	return {
		"profile": profile,
		"height": _height_blocks(),
		"jump": species.flagi(&"jump_blocks", 2),
		"max_fall": species.flagi(&"max_fall", 6),
		"allow_layer": not species.flagb(&"no_layer_shift", false),
		"layer_span": maxi(1, species.sight_layers),
		"layer_cost": species.flagf(&"layer_cost", MobPath.DEFAULT_LAYER_COST),
		"max_nodes": 320 + species.tier * 140,
	}


## Steer toward `goal`, pathing when the plane is blocked and shifting layers
## when the route says so. Returns NAV_MOVING / NAV_ARRIVED / NAV_BLOCKED.
func navigate_to(goal: Vector3, run: bool = false) -> int:
	var arrive: float = maxf(0.6, species.attack_range * 0.7)
	if plane_distance_to(goal) <= arrive and layer_delta_to_pos(goal) == 0:
		motor_stop()
		return NAV_ARRIVED

	# Re-path on a timer, never once per frame: the search budget is shared by
	# every monster on the planet.
	if _repath <= 0.0 or _path_goal.distance_to(goal) > 2.5:
		_repath = species.flagf(&"repath_interval", 0.7) + _rng.randf() * 0.3
		_path_goal = goal
		var found := MobPath.find_path(global_position, goal, _path_opts())
		if found.is_empty():
			_repath = minf(_repath, 0.25)      # budget was spent; try again soon
		else:
			_path = found
			_path_i = 0
			_no_progress = 0.0
			_last_progress_pos = global_position

	if _path.is_empty() or _path_i >= _path.size():
		return _steer_direct(goal, run)

	var wp: Vector3 = _path[_path_i]
	var wp_layer := floori(View.depth_of(wp))
	if wp_layer != depth_layer():
		motor_stop()
		if step_toward_layer(wp_layer):
			_path_i += 1
			return NAV_MOVING
		# The shift is blocked: try to shuffle laterally and retry next tick.
		if _layer_cd <= 0.0:
			_no_progress += 0.2
			if _no_progress > 1.0:
				_path.clear()
				return NAV_BLOCKED
		return NAV_MOVING

	if plane_distance_to(wp) < 0.85:
		_path_i += 1
		_no_progress = 0.0
		_last_progress_pos = global_position
		if _path_i >= _path.size():
			_path.clear()
			return NAV_MOVING
		wp = _path[_path_i]

	if global_position.distance_to(_last_progress_pos) < 0.15:
		_no_progress += get_physics_process_delta_time()
		if _no_progress > 1.3:
			_path.clear()
			_no_progress = 0.0
			return NAV_BLOCKED
	else:
		_no_progress = 0.0
		_last_progress_pos = global_position

	if species.is_flying() or (species.locomotion == MobSpecies.LOCO_SWIM and submersion > 0.3):
		motor_fly_to(wp, 1.4 if run else 1.0)
	else:
		var lat := lateral_to(wp)
		motor_move_lateral(signf(lat) if absf(lat) > 0.15 else 0.0, run)
		if wp.y > global_position.y + 0.55 and on_floor:
			jump()
		elif on_wall:
			auto_hop()
	return NAV_MOVING


func _steer_direct(goal: Vector3, run: bool) -> int:
	if species.is_flying() or (species.locomotion == MobSpecies.LOCO_SWIM and submersion > 0.3):
		motor_fly_to(goal, 1.5 if run else 1.0)
		return NAV_MOVING
	var lat := lateral_to(goal)
	var dir := signf(lat)
	if absf(lat) < 0.2:
		dir = 0.0
	if dir != 0.0 and blocked_ahead(int(dir)):
		auto_hop()
		if not on_floor:
			motor_move_lateral(dir, run)
			return NAV_MOVING
		return NAV_BLOCKED
	motor_move_lateral(dir, run)
	if goal.y > global_position.y + 1.0 and on_floor:
		auto_hop()
	return NAV_MOVING


# ==================================================================== combat
func attack_power() -> float:
	return species.scaled_damage(planet_threat) * size_scale


func can_attack() -> bool:
	return _attack_cd <= 0.0 and not dead and not is_shifting()


## Melee swing. Honours the species' behaviour override.
func do_melee(t: Node3D, reach: float = -1.0) -> bool:
	if t == null or dead:
		return false
	if behaviour != null and behaviour.on_attack(self, t):
		_attack_cd = species.attack_cooldown
		return true
	var r: float = species.attack_range if reach < 0.0 else reach
	if plane_distance_to(t.global_position) > r + 0.35 or not same_play_layer_as(t):
		return false
	_attack_cd = species.attack_cooldown
	set_anim(MobVisual.ST_ATTACK)
	face_toward(t.global_position)
	if t.has_method(&"apply_damage"):
		t.call(&"apply_damage", attack_power(), species.element, self)
	knockback_target(t, species.flagf(&"hit_knockback", 6.0))
	Events.play_sound.emit(&"monster_hit", global_position)
	Events.spawn_particles.emit(&"hit", t.global_position + Vector3(0, 0.8, 0), 6)
	return true


## Fire the species projectile. Falls back to an instant tracer when the combat
## module has not landed yet, so ranged monsters are never harmless.
func do_ranged(t: Node3D, opts: Dictionary = {}) -> bool:
	if t == null or dead or not can_attack():
		return false
	_attack_cd = species.attack_cooldown
	var origin := aabb_center()
	var aim: Vector3 = t.global_position + Vector3(0, 0.8, 0)
	var dir := (aim - origin).normalized()
	# Spread is applied *in the plane*, so a fan of shots reads as a fan on
	# screen rather than spraying into layers the player cannot see.
	var spread := float(opts.get("spread", 0.0))
	if absf(spread) > 0.0001:
		var flat := Vector2(Const.lateral_of(dir, View.view), dir.y).rotated(spread)
		dir = View.plane_dir_to_world(flat).normalized()
	set_anim(MobVisual.ST_ATTACK)
	face_toward(t.global_position)
	Events.play_sound.emit(&"monster_shoot", origin)

	if ResourceLoader.exists(PROJECTILE_SCENE):
		var setup := {
			"projectile": species.projectile,
			"damage": attack_power(),
			"element": species.element,
			"speed": species.projectile_speed,
			"direction": dir,
			"source": self,
			"faction": faction,
		}
		for k: String in opts:
			setup[k] = opts[k]
		var p := Game.spawn_entity(PROJECTILE_SCENE, origin + dir * 0.5, setup)
		if p != null:
			Events.projectile_spawned.emit(p)
			return true
	# Fallback: hitscan with a visible tracer.
	var pierce: bool = bool(opts.get("pierce_layers", false))
	if (pierce or same_play_layer_as(t)) and MobPath.line_of_sight(origin, aim, species.attack_range + 2.0):
		if t.has_method(&"apply_damage"):
			t.call(&"apply_damage", attack_power() * 0.8, species.element, self)
	Events.spawn_particles.emit(&"tracer", origin + dir, 4)
	return true


func knockback_target(t: Node3D, strength: float) -> void:
	if t is VoxelEntity and strength > 0.0:
		var dir := (t.global_position - global_position).normalized()
		dir.y = maxf(dir.y, 0.35)
		# Knockback never pushes anything out of its plane.
		(t as VoxelEntity).knockback(_flatten_to_plane(dir), strength)


## Damage everything hostile to us inside a sphere.
func area_damage(centre: Vector3, radius: float, amount: float, element: String) -> void:
	for e: VoxelEntity in Game.entities_in_radius(centre, radius):
		if e == self or e.dead:
			continue
		if not _is_enemy(e):
			continue
		var falloff := 1.0 - clampf(e.global_position.distance_to(centre) / maxf(0.01, radius), 0.0, 1.0)
		e.apply_damage(amount * (0.4 + 0.6 * falloff), element, self)
		e.knockback(_flatten_to_plane((e.global_position - centre).normalized() + Vector3.UP * 0.4), 6.0)


func apply_status_in_radius(status_id: StringName, duration: float, radius: float) -> void:
	if not Status.has_method(&"apply"):
		return
	for e: VoxelEntity in Game.entities_in_radius(global_position, radius):
		if e == self or not _is_enemy(e):
			continue
		Status.call(&"apply", status_id, e, duration)


## Only actors are enemies — never item drops or projectiles that happen to be
## `VoxelEntity`s standing in the blast radius.
func _is_enemy(e: VoxelEntity) -> bool:
	if not (e.is_in_group(&"player") or e.is_in_group(&"monsters")
			or e.is_in_group(&"npc") or e.is_in_group(&"npcs")):
		return false
	if faction == &"hostile":
		return e.faction != &"hostile"
	return e.faction == &"hostile"


func _flatten_to_plane(v: Vector3) -> Vector3:
	# Zero the depth component so knockback stays inside the visible plane.
	var out := v
	if View.depth_axis() == 0:
		out.x = 0.0
	else:
		out.z = 0.0
	return out


## Monsters never get shoved out of their layer.
func knockback(dir: Vector3, strength: float) -> void:
	if knockback_immune or dead:
		return
	var resist: float = clampf(species.knockback_resist, 0.0, 1.0) if species != null else 0.0
	super.knockback(_flatten_to_plane(dir), strength * (1.0 - resist))


func grant_shield(amount: float, duration: float) -> void:
	shield_amount = maxf(shield_amount, clampf(amount, 0.0, 0.9))
	shield_time = maxf(shield_time, duration)


## Resistances, armour, shields and the behaviour override, in that order.
func modify_incoming_damage(amount: float, element: String, source: Node) -> float:
	if species == null:
		return amount
	var out := amount * species.resistance_to(element) * damage_taken_mult
	out = maxf(out - (species.armour + bonus_armour), out * 0.15)
	if shield_amount > 0.0:
		out *= 1.0 - shield_amount
	# Status effects (frozen, marked, armour-shredded, ...) get their say too.
	if Status.has_method(&"modifier"):
		out *= float(Status.call(&"modifier", "damage_taken", self))
	if behaviour != null:
		out = behaviour.modify_damage(self, out, element, source)
	return out


func _on_self_damaged(amount: float, element: String, source: Node) -> void:
	_hurt_time = 0.28
	if visual != null:
		visual.flash(0.16)
	set_anim(MobVisual.ST_HURT)
	if behaviour != null:
		behaviour.on_damaged(self, amount, element, source)
	if brain != null:
		brain.bb.threat_source = source
		brain.bb.threat += 1.0
	if source is Node3D and faction != &"ally":
		set_target(source as Node3D)
	elif source == null and Game.player != null:
		set_target(Game.player)


## Wake every nearby monster of the same species and hand them our target.
func call_for_help(radius: float) -> void:
	var t := target()
	for n: Node in get_tree().get_nodes_in_group(&"monsters"):
		var m := n as MobBase
		if m == null or m == self or m.dead:
			continue
		if m.species_id != species_id and m.faction != faction:
			continue
		if global_position.distance_to(m.global_position) > radius:
			continue
		if t != null:
			m.set_target(t)
		elif brain != null:
			m.hear(global_position, 1.0)


func allies_in_radius(radius: float) -> Array:
	var out: Array = []
	for n: Node in get_tree().get_nodes_in_group(&"monsters"):
		var m := n as MobBase
		if m == null or m.dead or m.faction != faction:
			continue
		if global_position.distance_to(m.global_position) <= radius:
			out.append(m)
	return out


func suspend_brain(seconds: float) -> void:
	_brain_suspend = seconds


# ================================================================ presentation
func set_anim(state: StringName) -> void:
	_anim = state
	# Attack poses hold for a beat so the locomotion state cannot stomp on the
	# swing the player is meant to be reading.
	if state == MobVisual.ST_ATTACK:
		_anim_hold = 0.3
	elif state == MobVisual.ST_WINDUP:
		_anim_hold = maxf(_anim_hold, 0.12)
	if visual != null:
		visual.set_state(state)


func telegraph(v: float) -> void:
	telegraph_value = clampf(v, 0.0, 1.0)
	if visual != null:
		visual.set_telegraph(telegraph_value)


func visual_hidden(hidden: bool) -> void:
	if visual != null:
		visual.visible = not hidden


func visual_dim(t: float) -> void:
	if visual != null:
		visual.set_dim(t)


func visual_glow(g: float) -> void:
	if visual != null:
		visual.set_glow(g)


func visual_squash(s: float) -> void:
	if visual != null:
		visual.set_squash(s)


func visual_freeze(frozen: bool) -> void:
	if visual != null:
		visual.set_frozen(frozen)


func _update_visual_state() -> void:
	if visual == null:
		return
	visual.set_facing(facing)
	# Off-plane creatures are drawn dim so the player can read "not yet a
	# threat" at a glance — and watch it get brighter as it shifts closer.
	var off := absi(depth_layer() - View.layer)
	visual.set_dim(clampf(float(off) * 0.28, 0.0, 0.85))
	# Hurt flinches, telegraphed wind-ups and swings all own the pose while they
	# last; only then does locomotion get to pick the animation again.
	if _hurt_time > 0.0 or telegraph_value > 0.0:
		return
	if _anim_hold > 0.0 and (_anim == MobVisual.ST_ATTACK or _anim == MobVisual.ST_WINDUP):
		return
	var sp := absf(plane_velocity())
	if not on_floor and not species.is_flying():
		visual.set_state(MobVisual.ST_WALK)
	elif sp > move_speed * 1.25:
		visual.set_state(MobVisual.ST_RUN)
	elif sp > 0.35:
		visual.set_state(MobVisual.ST_WALK)
	else:
		visual.set_state(MobVisual.ST_IDLE)


# ===================================================================== death
func die_quietly() -> void:
	die(null)


func on_death(source: Node) -> void:
	if _dying:
		return
	_dying = true
	if behaviour != null:
		behaviour.on_death(self, source)
	if not bool(spawn_opts.get("no_loot", false)):
		_drop_loot()
	remove_from_group(&"monsters")
	velocity = Vector3.ZERO
	Events.spawn_particles.emit(&"monster_death", aabb_center(), 16)
	Events.play_sound.emit(&"monster_death", global_position)
	var wait := 0.75
	if visual != null:
		wait = visual.begin_death()
	await get_tree().create_timer(wait).timeout
	queue_free()


func _drop_loot() -> void:
	var origin := aabb_center()
	for entry: Dictionary in species.loot:
		if _rng.randf() > float(entry.get("chance", 1.0)):
			continue
		var lo: int = int(entry.get("min", 1))
		var hi: int = int(entry.get("max", lo))
		var n: int = _rng.randi_range(lo, maxi(lo, hi))
		if n <= 0:
			continue
		var item := MobSpecies.resolve_item(entry["item"])
		if item == &"":
			continue                    # the item content agent has not landed it yet
		Game.spawn_item_drop(origin, item, n)
	var px: int = int(round(float(species.pixels) * (1.0 + 0.25 * float(planet_threat)) * size_scale))
	var currency := MobSpecies.resolve_item(&"pixels")
	if px > 0 and currency != &"":
		Game.spawn_item_drop(origin, currency, px)


# ==================================================================== capture
## Fraction of health remaining — capture pods only stick to weakened monsters.
func health_fraction() -> float:
	return health / maxf(1.0, max_health)


func is_capturable() -> bool:
	return not dead and species != null and species.family != MobSpecies.FAM_BOSS \
		and not species.flagb(&"uncapturable", false)


## Convert into a pet owned by `owner`.
func become_pet(owner: Node3D) -> void:
	faction = &"ally"
	escort_of = owner
	add_to_group(&"pets")
	leash_range = 1e9
	brain = MobBrain.build(&"pet")
	brain.bb.home = global_position
	brain.bb.home_layer = depth_layer()
	health = max_health
	if visual != null:
		visual.set_glow(0.18)


# ============================================================== serialisation
## Wild monsters are never written to disk (`SavEntityPersistence` lists
## `monsters` as volatile) — but a captured pet is, so this has to round-trip.
func save_state() -> Dictionary:
	var d := super.save_state()
	d["species"] = String(species_id)
	d["opts"] = spawn_opts.duplicate()
	d["threat"] = planet_threat
	d["pet"] = is_in_group(&"pets")
	return d


func load_state(d: Dictionary) -> void:
	apply_species(StringName(d.get("species", "")), d.get("opts", {}))
	if bool(d.get("pet", false)):
		become_pet(Game.player)
	super.load_state(d)
	_recompute_lock()


func debug_line() -> String:
	return "%s L%d %s hp %.0f/%.0f" % [species_id, depth_layer(),
		brain.current_action() if brain != null else "-", health, max_health]
