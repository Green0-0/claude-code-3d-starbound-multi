class_name TechManager
extends RefCounted

## Techs: what you have unlocked, what you are wearing, and what happens when
## you press the button.
##
## One tech per slot, three slots, so a loadout is a real decision rather than a
## checklist. `legs` and `body` techs are active (bound to `G`, or to a second
## jump in mid-air); `head` techs are passive and simply report true when asked.

signal changed()

var unlocked := {}                   ## tech id -> true
var equipped := {&"legs": &"", &"body": &"", &"head": &""}
var player: Player = null
var game: Node = null

var _cooldown := {}
var _holding: StringName = &""
var _air_used := false
var _glide := false
var _cling := false


func _init() -> void:
	TechCatalog.get_def(&"dash")   # forces the catalogue to be referenced early


func has(id: StringName) -> bool:
	return unlocked.has(id)


## Unlock a tech. Fails if its prerequisites are missing.
func unlock(id: StringName) -> bool:
	var d := TechCatalog.get_def(id)
	if d.is_empty() or unlocked.has(id):
		return false
	for req in d.get("requires", []):
		if not unlocked.has(StringName(req)):
			return false
	unlocked[id] = true
	# equipping the first tech in a slot automatically is a kindness, not a rule
	var slot := StringName(d["slot"])
	if equipped.get(slot, &"") == &"":
		equipped[slot] = id
	changed.emit()
	return true


func equip(id: StringName) -> bool:
	if not unlocked.has(id):
		return false
	var d := TechCatalog.get_def(id)
	equipped[StringName(d["slot"])] = id
	changed.emit()
	return true


func unequip(slot: StringName) -> void:
	equipped[slot] = &""
	changed.emit()


func equipped_in(slot: StringName) -> StringName:
	return equipped.get(slot, &"")


## Is a passive tech active right now? Head techs answer yes when worn and
## affordable; everything else answers no.
func passive(id: StringName) -> bool:
	if equipped.get(&"head", &"") != id:
		return false
	var d := TechCatalog.get_def(id)
	if d.is_empty():
		return false
	var drain := float(d["drain"])
	return drain <= 0.0 or (player != null and player.energy > 1.0)


func owned_list() -> Array:
	var out: Array = []
	for d: Dictionary in TechCatalog.ALL:
		if unlocked.has(d["id"]):
			out.append(d)
	return out


# =============================================================================
# activation
# =============================================================================

func _ready_to_fire(id: StringName) -> bool:
	return float(_cooldown.get(id, 0.0)) <= 0.0


## The `G` key: fire whichever active tech is equipped, legs before body.
func activate() -> bool:
	if player == null:
		return false
	for slot: StringName in [&"legs", &"body"]:
		var id: StringName = equipped.get(slot, &"")
		if id == &"" or not _ready_to_fire(id):
			continue
		if _fire(id):
			return true
	return false


## Called when the player presses jump with no ground and no coyote time left.
func air_tech(p: Player) -> bool:
	var id: StringName = equipped.get(&"legs", &"")
	if id != &"double_jump" and id != &"pulse_jump" and id != &"rocket_boost":
		return false
	if _air_used and id != &"rocket_boost":
		return false
	if not _fire(id):
		return false
	if id != &"rocket_boost":
		_air_used = true
	return true


func _fire(id: StringName) -> bool:
	var d := TechCatalog.get_def(id)
	if d.is_empty() or player == null:
		return false
	var cost := float(d["energy"])
	if cost > 0.0 and not player.spend_energy(cost):
		if game != null:
			game.notify("Not enough energy.", &"warn")
		return false
	_cooldown[id] = 0.45

	var facing := Vector3.ZERO
	if player.rig != null:
		facing = (Vector3(player.rig.lateral()) * player.facing_sign)
		var v := Vector3(player.velocity.x, 0, player.velocity.z)
		if v.length() > 0.5:
			facing = v.normalized()

	match id:
		&"double_jump":
			player.velocity.y = Player.JUMP_SPEED * 0.92
		&"pulse_jump":
			player.velocity.y = Player.JUMP_SPEED * 1.15
			if game != null:
				game.shockwave(player.global_position, 4.0, 14.0)
		&"rocket_boost":
			player.velocity.y = maxf(player.velocity.y, 0.0) + 3.2
			_holding = id
		&"dash":
			player.velocity += facing * 13.0
		&"sprint_burst":
			player.velocity += facing * 6.0
			_holding = id
		&"blink":
			_blink(facing, 5.0, false)
		&"phase_step":
			# steps into the volume the cutaway has opened between lens and player
			_blink(_cut_direction(), 6.5, true)
		&"morph_ball", &"spike_ball":
			player.velocity += facing * 8.0
		&"bubble_boost":
			player.velocity.y = maxf(player.velocity.y, 6.0)
		&"glide":
			_glide = true
		&"wall_cling":
			_cling = true
		&"fold":
			if game != null:
				game.fold_cutaway()
		&"scan_pulse":
			if game != null:
				game.survey_pulse(player.global_position, 22.0)
		_:
			return false
	if game != null:
		game.on_tech_used(id)
	return true


## Where the cutaway is currently pointing: from the player back toward the
## lens. Stepping along it is stepping into the slice.
func _cut_direction() -> Vector3:
	if player == null or player.world == null:
		return Vector3.FORWARD
	var cut := player.world.cutaway
	var d := cut.camera_position - cut.target_position
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3.FORWARD
	return d.normalized()


## Teleport up to `dist`, stopping at the last free cell. `through` ignores the
## terrain entirely, which is what makes Phase Step different from Blink.
func _blink(dir: Vector3, dist: float, through: bool) -> void:
	if player == null or dir.length() < 0.01:
		return
	dir = dir.normalized()
	var best := player.global_position
	var step := 0.4
	var travelled := 0.0
	while travelled < dist:
		travelled += step
		var probe := player.global_position + dir * travelled
		var blocked := player.world.box_overlaps(
			probe + Vector3(0, Player.HALF.y, 0), Player.HALF)
		if not blocked:
			best = probe
		elif not through:
			break
	player.global_position = best
	player.velocity.y = maxf(player.velocity.y, 0.0)


# =============================================================================
# per-frame
# =============================================================================

func tick(delta: float) -> void:
	for id in _cooldown.keys():
		_cooldown[id] = maxf(float(_cooldown[id]) - delta, 0.0)
	if player == null:
		return
	if player.on_floor:
		_air_used = false

	# held techs drain while the key is down
	var held := Input.is_action_pressed(&"tech")
	if _holding != &"":
		var d := TechCatalog.get_def(_holding)
		var drain := float(d.get("drain", 0.0))
		if not held or not player.spend_energy(drain * delta):
			_holding = &""
		else:
			match _holding:
				&"rocket_boost":
					player.velocity.y = minf(player.velocity.y + 26.0 * delta, 7.0)
				&"sprint_burst":
					pass

	# glide and wall cling are body techs that behave while you hold the key
	var body: StringName = equipped.get(&"body", &"")
	if body == &"glide" and held and not player.on_floor and player.velocity.y < 0.0:
		var d := TechCatalog.get_def(&"glide")
		if player.spend_energy(float(d["drain"]) * delta):
			player.velocity.y = maxf(player.velocity.y, -2.2)
	elif body == &"wall_cling" and held and not player.on_floor:
		var d := TechCatalog.get_def(&"wall_cling")
		if _touching_wall() and player.spend_energy(float(d["drain"]) * delta):
			player.velocity.y = maxf(player.velocity.y, -0.8)
			_air_used = false

	# head techs are passive drains
	var head: StringName = equipped.get(&"head", &"")
	if head != &"":
		var hd := TechCatalog.get_def(head)
		var hdr := float(hd.get("drain", 0.0))
		if hdr > 0.0:
			player.spend_energy(hdr * delta)


func _touching_wall() -> bool:
	if player == null:
		return false
	for dir in [Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0),
			Vector3(0, 0, 0.45), Vector3(0, 0, -0.45)]:
		if player.world.box_overlaps(
				player.global_position + dir + Vector3(0, Player.HALF.y, 0),
				Player.HALF):
			return true
	return false


# =============================================================================
# persistence
# =============================================================================

func save_state() -> Dictionary:
	var eq := {}
	for k: StringName in equipped:
		eq[String(k)] = String(equipped[k])
	return {"unlocked": unlocked.keys(), "equipped": eq}


func load_state(d: Dictionary) -> void:
	unlocked.clear()
	for id in d.get("unlocked", []):
		unlocked[StringName(id)] = true
	var eq: Dictionary = d.get("equipped", {})
	for k: String in eq:
		equipped[StringName(k)] = StringName(eq[k])
	changed.emit()
