## Boss 1 — The Colossus of the Barrens.
##
## A slow, enormous ground boss. Three phases, all built around attacks you can
## see coming a full second before they land: the fight is about where you are
## standing, not how fast you click. Its slam covers the whole plane at ground
## level, so the answer is often to *shift a layer* rather than to run.
extends MobBoss


func _ready() -> void:
	species_id = &"boss_stone_titan"
	if species == null:
		apply_species(species_id, spawn_opts)
	phases = [
		{"at": 0.7, "name": "Cracked Shell"},
		{"at": 0.35, "name": "Quaking Fury"},
	]
	super._ready()
	arena_radius = species.flagf(&"arena_radius", 24.0)


func _choose_action(_delta: float) -> void:
	var t := player_target()
	if t == null:
		_action_cd = 1.0
		return
	var d := plane_distance_to(t.global_position)
	var same := same_play_layer_as(t)
	var roll := randf()

	if not same and roll < 0.5:
		# It cannot reach across layers, so it brings the layer down instead.
		begin_telegraph(&"quake", 1.4, {"shout": true,
			"shout_text": "The Colossus raises a fist over the whole slab."})
		_action_cd = 5.0
		return
	if d < 6.0:
		begin_telegraph(&"slam", 1.0)
		_action_cd = 3.4 - float(phase) * 0.5
	elif d < 20.0 and roll < 0.55:
		begin_telegraph(&"boulder", 0.85)
		_action_cd = 2.8 - float(phase) * 0.4
	elif phase >= 1 and roll < 0.8:
		begin_telegraph(&"summon", 1.2, {"shout": true,
			"shout_text": "Stone splits and stands up."})
		_action_cd = 9.0
	else:
		_action_cd = 1.2      # close the distance with the normal brain


func _fire_attack(id: StringName, _meta: Dictionary) -> void:
	match id:
		&"slam":
			set_anim(MobVisual.ST_ATTACK)
			shockwave(7.5 + float(phase) * 1.5, attack_power() * 1.6)
			# The shock rips a shallow trench in front of it.
			var ahead := global_position + Vector3(View.right()) * float(facing) * 3.0
			World.explode(ahead, 1.6, 2.0)
		&"boulder":
			var t := player_target()
			if t != null:
				for i in 1 + phase:
					do_ranged(t, {"arc": true, "gravity": 0.8, "spread": 0.12 * float(i)})
					_attack_cd = 0.0
		&"quake":
			# Damages everything standing on the ground in the *play* layer, at
			# any lateral distance. Shifting a layer, or being airborne, saves you.
			var hit := 0
			for e: VoxelEntity in Game.entities_in_radius(global_position, 60.0):
				if e == self or e.faction == &"hostile":
					continue
				if floori(View.depth_of(e.global_position)) != View.layer:
					continue
				if not e.on_floor:
					continue
				e.apply_damage(attack_power() * 1.3, Const.ELEM_PHYSICAL, self)
				e.knockback(Vector3.UP, 9.0)
				hit += 1
			Events.screen_shake.emit(6.0, 0.9)
			Events.spawn_particles.emit(&"quake", global_position, 60)
			Events.play_sound.emit(&"boss_quake", global_position)
			if hit == 0:
				Events.toast("The quake passes under you.", "info")
		&"summon":
			summon(&"boulder_beetle", 2 + phase, 8.0)


func _on_phase_changed(p: int) -> void:
	move_speed = species.move_speed * (1.0 + 0.25 * float(p))
	if p >= 2:
		Events.toast("The Colossus stops defending itself.", "danger")
		bonus_armour = -6.0          # the shell is gone: it hits harder, takes more
		damage_taken_mult = 1.3
