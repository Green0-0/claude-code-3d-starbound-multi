## Boss 4 — The Magma Heart.
##
## A rooted, four-phase siege fight. It cannot move, so the arena does the
## moving: eruption columns walk along the plane toward you, fire waves sweep the
## layer, and between phases it seals itself behind a shell of adds. Its one
## concession to mobility is that it re-seats itself in the player's depth layer
## whenever you try to fight it from behind.
extends MobBoss

var _shell: Array = []
var _sealed := false
var _column_lateral := 0.0


func _ready() -> void:
	species_id = &"boss_magma_heart"
	if species == null:
		apply_species(species_id, spawn_opts)
	phases = [
		{"at": 0.78, "name": "First Vent"},
		{"at": 0.52, "name": "Sealed Core"},
		{"at": 0.26, "name": "Meltdown"},
	]
	super._ready()
	arena_radius = species.flagf(&"arena_radius", 22.0)
	knockback_immune = true


func _boss_tick(delta: float) -> void:
	# It reaches through the depth axis rather than walking: if the player tries
	# to fight from an adjacent layer, the core simply surfaces there.
	var p := Game.player
	if p != null and _intro <= 0.0 and not _sealed:
		var pl := floori(View.depth_of(p.global_position))
		if pl != depth_layer() and randf() < 0.01:
			begin_telegraph(&"reseat", 1.0, {"shout": true,
				"shout_text": "The core burns through to your layer."})
	_maintain_shell()
	super._boss_tick(delta)


func _maintain_shell() -> void:
	if not _sealed:
		return
	var live: Array = []
	for s in _shell:
		if s != null and is_instance_valid(s) and not (s as VoxelEntity).dead:
			live.append(s)
	_shell = live
	if _shell.is_empty():
		_sealed = false
		invulnerable = false
		telegraph(0.0)
		Events.toast("The shell breaks. The core is exposed.", "success")
	else:
		invulnerable = true


func _choose_action(_delta: float) -> void:
	if _sealed:
		_action_cd = 1.0
		return
	var t := player_target()
	if t == null:
		_action_cd = 1.0
		return
	var roll := randf()
	if phase >= 3 and roll < 0.3:
		begin_telegraph(&"meltdown", 1.6, {"shout": true,
			"shout_text": "The Magma Heart begins to come apart."})
		_action_cd = 8.0
	elif roll < 0.34:
		_column_lateral = lateral_to(t.global_position)
		begin_telegraph(&"eruption", 1.2, {})
		_action_cd = 4.0 - float(phase) * 0.5
	elif roll < 0.62:
		begin_telegraph(&"firewave", 1.0, {})
		_action_cd = 3.6 - float(phase) * 0.4
	elif roll < 0.85:
		begin_telegraph(&"bolts", 0.7, {})
		_action_cd = 2.4
	else:
		begin_telegraph(&"brood", 1.2, {"shout": true, "shout_text": "The vents open."})
		_action_cd = 9.0


func _fire_attack(id: StringName, _meta: Dictionary) -> void:
	var t := player_target()
	match id:
		&"bolts":
			if t == null:
				return
			for i in 2 + phase:
				_attack_cd = 0.0
				do_ranged(t, {"spread": (float(i) - 1.0) * 0.16, "arc": true})
		&"eruption":
			# Three columns walking outward from the boss along the plane. The
			# gaps between them are the safe ground.
			for step in 3:
				var lat: float = _column_lateral * (0.4 + 0.3 * float(step))
				var centre := plane_offset(global_position, lat)
				area_damage(centre, 3.2, attack_power() * 1.1, Const.ELEM_FIRE)
				Events.spawn_particles.emit(&"eruption", centre, 24)
			Events.screen_shake.emit(3.4, 0.5)
			Events.play_sound.emit(&"eruption", global_position)
		&"firewave":
			# Sweeps the whole layer at low height: jump, or shift out of it.
			for e: VoxelEntity in Game.entities_in_radius(global_position, 40.0):
				if e == self or e.faction == &"hostile":
					continue
				if floori(View.depth_of(e.global_position)) != depth_layer():
					continue
				if e.global_position.y > global_position.y + 2.4:
					continue
				e.apply_damage(attack_power() * 1.25, Const.ELEM_FIRE, self)
				e.knockback(Vector3.UP, 6.0)
			Events.spawn_particles.emit(&"firewave", global_position, 40)
			Events.screen_shake.emit(2.6, 0.5)
		&"reseat":
			var p := Game.player
			if p != null:
				snap_to_layer(floori(View.depth_of(p.global_position)))
				shockwave(5.0, attack_power(), Const.ELEM_FIRE)
		&"brood":
			var adds := summon(&"magma_crawler", 1 + phase, 7.0)
			adds.append_array(summon(&"ember_wisp", 1 + phase, 8.0))
		&"meltdown":
			shockwave(11.0, attack_power() * 2.0, Const.ELEM_FIRE)
			World.explode(global_position + Vector3(0, 1.0, 0), 3.0, 3.5)


func _on_phase_changed(p: int) -> void:
	if p == 2:
		_seal()
	if p >= 3:
		damage_taken_mult = 1.25
		Events.toast("The core is glowing white.", "danger")


## Phase 3 opener: it hides behind a wall of adds until you clear them.
func _seal() -> void:
	_shell = summon(&"bulwark_drone", 2, 5.0)
	_shell.append_array(summon(&"magma_crawler", 2, 7.0))
	if _shell.is_empty():
		return
	_sealed = true
	invulnerable = true
	telegraph(0.6)
	Events.toast("The Magma Heart seals itself. Break the shell.", "danger")
