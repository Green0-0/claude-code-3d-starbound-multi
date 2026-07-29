## Boss 3 — The Fourfold. **The perspective boss.**
##
## It does not occupy a place so much as a *way of looking*. At any moment it
## inhabits exactly one of the four viewing planes. While you are looking through
## that plane it is solid, vulnerable and murderous; the moment it slips into
## another it becomes a translucent afterimage that cannot be touched — and it
## starts pulling you apart at range until you flip (Q / E) to follow it.
##
## The whole fight is therefore a conversation with the camera:
##   * it announces which plane it has moved to,
##   * you flip to match it,
##   * it also shifts *depth layers* inside that plane, so you shift too,
##   * and from phase 2 it leaves echoes behind in the planes you abandoned.
extends MobBoss

## Which of the four views this creature is currently real in.
var home_view := 0

var _rotate_t := 9.0
var _bleed_t := 3.0
var _echoes: Array = []
var _announced := false


func _ready() -> void:
	species_id = &"boss_fourfold"
	if species == null:
		apply_species(species_id, spawn_opts)
	phases = [
		{"at": 0.66, "name": "Second Aspect"},
		{"at": 0.33, "name": "All Four At Once"},
	]
	super._ready()
	arena_radius = species.flagf(&"arena_radius", 30.0)
	home_view = View.view
	Events.toast("The Fourfold stands in the %s plane." % Const.VIEW_NAMES[home_view], "danger")


func rotate_interval() -> float:
	return [11.0, 8.0, 5.5][clampi(phase, 0, 2)]


func in_its_plane() -> bool:
	return View.view == home_view


# =============================================================== plane logic
func _boss_tick(delta: float) -> void:
	_plane_logic(delta)
	super._boss_tick(delta)


func _plane_logic(delta: float) -> void:
	if _intro > 0.0:
		return
	var here := in_its_plane()
	# Untouchable outside its own plane — but never invisible, so the player can
	# always see where it went.
	invulnerable = not here
	if visual != null:
		visual.set_dim(0.0 if here else 0.72)
		visual.set_glow(0.7 if here else 0.35)

	if here:
		if not _announced:
			_announced = true
			Events.toast("You are looking at it.", "warning")
		_bleed_t = 3.0
		# Inside its plane it hunts by depth: it will step into your layer.
		if depth_layer() != View.layer and randf() < 0.02:
			step_toward_layer(View.layer)
	else:
		_announced = false
		suspend_brain(0.2)
		motor_stop()
		# Drift back toward the arena so it is never lost off-screen.
		var goal := arena_centre
		goal.y = arena_centre.y + 2.0 + sin(float(Time.get_ticks_msec()) * 0.001) * 1.2
		motor_fly_to(goal, 0.5)
		_bleed_t -= delta
		if _bleed_t <= 0.0:
			_bleed_t = 3.0
			_unravel()

	_rotate_t -= delta
	if _rotate_t <= 0.0:
		_rotate_t = rotate_interval()
		_rotate_plane(1 if randf() < 0.5 else -1)


## Damage-over-time while the player refuses to follow it into its plane.
func _unravel() -> void:
	var p := Game.player
	if p == null or p.dead:
		return
	if p.global_position.distance_to(global_position) > 80.0:
		return
	p.apply_damage(attack_power() * 0.55, Const.ELEM_COSMIC, self)
	Events.toast("The %s plane pulls at you. Flip." % Const.VIEW_NAMES[home_view], "danger")
	Events.spawn_particles.emit(&"unravel", p.global_position + Vector3(0, 1, 0), 18)
	Events.screen_shake.emit(1.6, 0.3)


func _rotate_plane(dir: int) -> void:
	var from := home_view
	home_view = wrapi(home_view + dir, 0, Const.VIEW_COUNT)
	_announced = false
	if phase >= 2:
		_leave_echo(from)
	# Reposition into the geometry of the plane it is entering: offset from the
	# player along that plane's lateral axis, at the player's depth.
	var p := Game.player
	if p != null:
		var r: Vector3i = Const.VIEW_RIGHT[home_view]
		var side := 1.0 if randf() < 0.5 else -1.0
		var dest := p.global_position + Vector3(float(r.x), 0.0, float(r.z)) * (10.0 * side)
		dest.y = p.global_position.y + 2.0
		dest = VoxelPhysics.unstick(dest, box_size)
		teleport(dest)
		_recompute_lock()
	Events.toast("The Fourfold slips into the %s plane." % Const.VIEW_NAMES[home_view], "danger")
	Events.play_sound.emit(&"boss_shift_plane", global_position)
	Events.screen_shake.emit(3.2, 0.55)
	Events.spawn_particles.emit(&"phase", aabb_center(), 42)


## Phase 3: the plane it just left keeps a piece of it.
func _leave_echo(view_index: int) -> void:
	var em: Node3D = Game.entities_root
	if em == null or not em.has_method(&"spawn_species"):
		return
	_prune_echoes()
	if _echoes.size() >= 2:
		return
	var e = em.call(&"spawn_species", &"plane_wraith", global_position,
		{"threat": planet_threat, "no_loot": true, "scale": 0.8})
	if e != null:
		_echoes.append(e)
		Events.toast("An echo stays behind in the %s plane." % Const.VIEW_NAMES[view_index], "warning")


func _prune_echoes() -> void:
	var live: Array = []
	for e in _echoes:
		if e != null and is_instance_valid(e) and not (e as VoxelEntity).dead:
			live.append(e)
	_echoes = live


# =================================================================== attacks
func _choose_action(_delta: float) -> void:
	if not in_its_plane():
		_action_cd = 0.6
		return
	var t := player_target()
	if t == null:
		_action_cd = 1.0
		return
	var d := plane_distance_to(t.global_position)
	var roll := randf()

	if phase >= 1 and roll < 0.22:
		begin_telegraph(&"plane_rip", 1.3, {"shout": true,
			"shout_text": "Stand in its layer, or be cut out of yours."})
		_action_cd = 7.0
	elif d < 5.0 or not same_play_layer_as(t):
		begin_telegraph(&"lunge", 0.6, {})
		_action_cd = 2.4
	else:
		begin_telegraph(&"volley", 0.7, {})
		_action_cd = 2.2 - float(phase) * 0.4


func _fire_attack(id: StringName, _meta: Dictionary) -> void:
	var t := player_target()
	match id:
		&"volley":
			if t == null:
				return
			for i in 3 + phase:
				_attack_cd = 0.0
				do_ranged(t, {"spread": (float(i) - 1.5) * 0.13, "pierce_layers": true})
		&"lunge":
			if t == null:
				return
			step_toward_layer(floori(View.depth_of(t.global_position)))
			motor_fly_to(t.global_position, 3.2)
			suspend_brain(0.8)
			set_anim(MobVisual.ST_ATTACK)
			await get_tree().create_timer(0.4).timeout
			if is_instance_valid(self) and not dead:
				area_damage(global_position, 3.0, attack_power() * 1.4, Const.ELEM_COSMIC)
				Events.screen_shake.emit(2.4, 0.3)
		&"plane_rip":
			# Inverts the whole rule of the fight: for one beat, the only safe
			# place is the layer the boss itself is standing in.
			var safe := depth_layer()
			var caught := false
			for e: VoxelEntity in Game.entities_in_radius(global_position, 70.0):
				if e == self or e.faction == &"hostile":
					continue
				if floori(View.depth_of(e.global_position)) == safe:
					continue
				e.apply_damage(attack_power() * 1.8, Const.ELEM_COSMIC, self)
				caught = true
			Events.spawn_particles.emit(&"plane_rip", global_position, 60)
			Events.screen_shake.emit(5.0, 0.7)
			Events.play_sound.emit(&"boss_plane_rip", global_position)
			if not caught:
				Events.toast("You were standing in the right layer.", "success")


func _on_phase_changed(p: int) -> void:
	_rotate_t = minf(_rotate_t, rotate_interval())
	if p >= 1:
		Events.toast("The Fourfold begins to hurry.", "danger")
	if p >= 2:
		damage_taken_mult = 1.15
		Events.toast("It is in every plane now. Keep turning.", "danger")


func on_death(source: Node) -> void:
	for e in _echoes:
		if e != null and is_instance_valid(e) and e is VoxelEntity:
			(e as VoxelEntity).die(self)
	super.on_death(source)
