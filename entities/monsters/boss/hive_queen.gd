## Boss 2 — The Hive Queen.
##
## A flying boss that fights through her brood. Three phases: she opens at range
## with acid, starts spawning swarms at 75%, and at 40% she abandons ranged
## attacks entirely for repeated dives. Her brood spawns on the *play* layer, so
## shifting away from her does not shake them.
extends MobBoss

var _dive_target := Vector3.ZERO
var _brood: Array = []


func _ready() -> void:
	species_id = &"boss_hive_queen"
	if species == null:
		apply_species(species_id, spawn_opts)
	phases = [
		{"at": 0.75, "name": "The Brood Wakes"},
		{"at": 0.40, "name": "Nothing Left To Send"},
	]
	super._ready()
	arena_radius = species.flagf(&"arena_radius", 26.0)


func _choose_action(_delta: float) -> void:
	var t := player_target()
	if t == null:
		_action_cd = 1.0
		return
	_prune_brood()
	var d := plane_distance_to(t.global_position)
	var roll := randf()

	if phase >= 2:
		# Enraged: dive, dive, dive.
		begin_telegraph(&"dive", 0.7, {})
		_action_cd = 1.9
		return
	if _brood.size() < 2 + phase * 2 and roll < 0.45:
		begin_telegraph(&"brood", 1.1, {"shout": true, "shout_text": "She calls the brood."})
		_action_cd = 6.5 - float(phase)
		return
	if d < 7.0:
		begin_telegraph(&"dive", 0.8, {})
		_action_cd = 3.0
	elif not same_play_layer_as(t):
		begin_telegraph(&"sweep", 1.2, {"shout": true,
			"shout_text": "She banks across the layers."})
		_action_cd = 4.5
	else:
		begin_telegraph(&"spray", 0.8, {})
		_action_cd = 2.6 - float(phase) * 0.4


func _fire_attack(id: StringName, _meta: Dictionary) -> void:
	var t := player_target()
	match id:
		&"spray":
			if t == null:
				return
			for i in 3 + phase:
				_attack_cd = 0.0
				do_ranged(t, {"spread": (float(i) - 1.5) * 0.14})
		&"dive":
			if t == null:
				return
			_dive_target = t.global_position
			motor_fly_to(_dive_target, 3.0)
			suspend_brain(1.1)
			set_anim(MobVisual.ST_ATTACK)
			await get_tree().create_timer(0.55).timeout
			if is_instance_valid(self) and not dead:
				area_damage(global_position, 3.4, attack_power() * 1.5, species.element)
				Events.screen_shake.emit(2.5, 0.3)
		&"sweep":
			# She crosses depth layers to reach you, spitting the whole way.
			if t != null:
				step_toward_layer(floori(View.depth_of(t.global_position)))
				await get_tree().create_timer(0.25).timeout
				if is_instance_valid(self) and not dead:
					_attack_cd = 0.0
					do_ranged(t, {"pierce_layers": true})
		&"brood":
			var kids := summon(&"bitegnat_swarm", 2 + phase, 7.0)
			for k in kids:
				_brood.append(k)
			if phase >= 1:
				_brood.append_array(summon(&"gasbag_floater", 1, 6.0))


func _prune_brood() -> void:
	var live: Array = []
	for b in _brood:
		if b != null and is_instance_valid(b) and not (b as VoxelEntity).dead:
			live.append(b)
	_brood = live


func _on_phase_changed(p: int) -> void:
	move_speed = species.move_speed * (1.0 + 0.3 * float(p))
	if p >= 2:
		damage_taken_mult = 1.2
		Events.toast("The Hive Queen stops laying and starts hunting.", "danger")
