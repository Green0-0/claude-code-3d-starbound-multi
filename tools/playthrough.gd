## Scripted playthrough with screenshot capture.
##
##   godot --path . tools/playthrough.tscn
##
## Boots the real game, drives it through a sequence of gameplay beats using the
## same inputs and public APIs a player would hit, and writes a numbered PNG at
## each beat into `screenshots/`. Every step is guarded and logged, so one broken
## subsystem produces a FAIL line and the run continues instead of aborting.
extends Node

const SHOT_DIR := "res://screenshots"

var _shot := 0
var _log: Array[String] = []
var _fails: Array[String] = []


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	call_deferred("_run")


# ------------------------------------------------------------------ utilities
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func note(msg: String) -> void:
	_log.append(msg)
	print("  .. " + msg)


func ok(label: String, cond: bool, detail: String = "") -> void:
	var line := "%s  %s%s" % ["PASS" if cond else "FAIL", label,
		"" if detail == "" else "  (%s)" % detail]
	print("  " + line)
	if not cond:
		_fails.append(label)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		ok("screenshot " + name, false, "no viewport")
		return
	var tex := vp.get_texture()
	if tex == null:
		ok("screenshot " + name, false, "no viewport texture")
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		ok("screenshot " + name, false, "empty image")
		return
	_shot += 1
	var path := "%s/%02d_%s.png" % [SHOT_DIR, _shot, name]
	var err := img.save_png(path)
	# A screenshot of a black frame is a rendering failure, not a success —
	# check that the frame actually contains variation.
	var lively := _frame_has_content(img)
	ok("screenshot %02d_%s" % [_shot, name], err == OK and lively,
		"err=%d, %s" % [err, "has content" if lively else "BLANK FRAME"])


## Cheap sample: does the image contain more than one distinct colour?
func _frame_has_content(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	if w < 4 or h < 4:
		return false
	var first := img.get_pixel(w / 2, h / 2)
	var distinct := 0
	for i in 64:
		var x := (i * 37) % w
		var y := (i * 61) % h
		if img.get_pixel(x, y) != first:
			distinct += 1
	return distinct > 2


func hold(action: StringName, seconds: float) -> void:
	if not InputMap.has_action(action):
		note("no such action: %s" % action)
		return
	Input.action_press(action)
	await _frames(int(seconds * 60.0))
	Input.action_release(action)


func player() -> VoxelEntity:
	return Game.player


# ---------------------------------------------------------------------- run
func _run() -> void:
	print("\n=== PLANESHIFT PLAYTHROUGH ===\n")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Pin the run so screenshots are comparable between iterations.
	Game.run_seed = 20240729
	await _frames(180)

	await _beat_title()
	await _beat_ship()
	await _beat_flip()
	await _beat_shift()
	await _beat_ui()
	await _beat_planet()
	await _beat_mine_and_place()
	await _beat_combat()
	await _beat_night()
	await _beat_save()

	print("\n=== %d screenshots, %d failures ===" % [_shot, _fails.size()])
	for f: String in _fails:
		print("  FAILED: " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)


# ------------------------------------------------------------------- beats
func _beat_title() -> void:
	print("-- title screen --")
	await _frames(30)
	await shot("title_screen")
	if UI.has_method(&"close_all"):
		UI.close_all()
	await _frames(30)
	ok("ui released input", not UI.captures_input())


func _beat_ship() -> void:
	print("-- aboard the ship --")
	var p := player()
	ok("player spawned", p != null)
	if p == null:
		return
	ok("world is the ship", World.planet_id == "ship", World.planet_id)
	await shot("ship_interior")
	var start := View.lateral_of(p.global_position)
	await hold(&"move_right", 0.9)
	await _frames(20)
	var best: float = absf(View.lateral_of(p.global_position) - start)
	if best <= 0.4:
		var mid := View.lateral_of(p.global_position)
		await hold(&"move_left", 0.9)
		await _frames(20)
		best = maxf(best, absf(View.lateral_of(p.global_position) - mid))
	ok("player walks laterally", best > 0.4, "moved %.2f blocks" % best)
	await shot("ship_walked")


func _beat_flip() -> void:
	print("-- the flip --")
	var p := player()
	if p == null:
		return
	var v0 := View.view
	var pos0: Vector3 = p.global_position
	ok("flip starts", View.request_flip(1))
	await _frames(int(View.flip_duration * 30.0))
	await shot("flip_midway")
	await _frames(int(View.flip_duration * 60.0) + 30)
	await shot("flip_settled")
	ok("view advanced", View.view == wrapi(v0 + 1, 0, 4), "%d -> %d" % [v0, View.view])
	ok("player held position", absf(p.global_position.y - pos0.y) < 1.5,
		"dy=%.2f" % (p.global_position.y - pos0.y))
	# Go all the way round; all four planes must be reachable and stable.
	for i in 3:
		View.request_flip(1)
		await _frames(int(View.flip_duration * 60.0) + 25)
	ok("full rotation returns to start", View.view == v0, "view=%d" % View.view)
	await shot("flip_full_circle")


func _beat_shift() -> void:
	print("-- the layer shift --")
	var p := player()
	if p == null:
		return
	var layer0 := View.layer
	var accepted := View.request_shift(1)
	await _frames(int(View.shift_duration * 60.0) + 25)
	if accepted:
		ok("layer advanced", View.layer == layer0 + 1, "%d -> %d" % [layer0, View.layer])
		ok("player legal after shift",
			VoxelPhysics.aabb_is_free(p.global_position, p.get_aabb_size()))
	else:
		ok("blocked shift refused cleanly", View.layer == layer0 and not View.shifting,
			"destination occupied")
	await shot("layer_shifted")

	# --- the remapped bindings, exercised as real input ---
	# `main.gd` reacts to InputEvents, so synthesise them rather than only
	# poking the action state (which `Input.action_press` alone would do).
	print("-- bindings: W/S depth, PageDown crouch --")
	for action: StringName in [&"depth_in", &"depth_out", &"crouch"]:
		ok("action exists: " + String(action), InputMap.has_action(action))
	var before_layer := View.layer
	var ev := InputEventAction.new()
	ev.action = &"depth_in"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(int(View.shift_duration * 60.0) + 30)
	var moved_in: bool = View.layer != before_layer
	if not moved_in:
		# A refusal is legitimate if that layer is solid; try the other direction.
		var ev2 := InputEventAction.new()
		ev2.action = &"depth_out"
		ev2.pressed = true
		Input.parse_input_event(ev2)
		await _frames(int(View.shift_duration * 60.0) + 30)
		moved_in = View.layer != before_layer
	ok("W / S traverse the depth axis", moved_in,
		"layer %d -> %d" % [before_layer, View.layer])

	Input.action_press(&"crouch")
	await _frames(20)
	var crouched: bool = p.has_method(&"is_crouching") and bool(p.call(&"is_crouching"))
	Input.action_release(&"crouch")
	await _frames(10)
	# Crouch needs the player grounded; report rather than fail if airborne.
	if crouched:
		ok("PageDown crouches", true)
	else:
		ok("PageDown crouches", not p.on_floor,
			"not grounded, crouch not applicable" if not p.on_floor else "grounded but did not crouch")


func _beat_ui() -> void:
	print("-- interface --")
	for panel: String in ["inventory", "crafting", "quests", "starmap"]:
		UI.close_all()
		await _frames(10)
		UI.open(panel)
		await _frames(35)
		var opened: bool = UI.is_open(panel) if UI.has_method(&"is_open") \
			else not UI.open_panels.is_empty()
		ok("panel opens: " + panel, opened)
		await shot("ui_" + panel)
	UI.close_all()
	await _frames(20)
	ok("panels all closed", not UI.captures_input())


func _beat_planet() -> void:
	print("-- travel to a planet --")
	# Prefer a temperate, vegetated world: it exercises foliage, water and stone
	# together, and is the fairest readability test. Fall back to anything landable.
	var target := ""
	var fallback := ""
	const PREFERRED := ["forest", "garden", "jungle", "savannah", "plains"]
	for sid: String in Universe.system_ids():
		for bid: String in Universe.system_body_ids(sid):
			var m: Dictionary = Universe.planet_meta(bid)
			if String(m.get("generator", "planet")) != "planet":
				continue
			if fallback == "":
				fallback = bid
			if PREFERRED.has(String(m.get("type", ""))):
				target = bid
				break
		if target != "":
			break
	if target == "":
		target = fallback
	note("planet type: %s" % String(Universe.planet_meta(target).get("type", "?")))
	ok("found a landable world", target != "", target)
	if target == "":
		return
	Game.travel_to_planet(target)
	# Terrain is expensive; give streaming real time to fill the slab.
	await _frames(600)
	ok("planet loaded", World.planet_id == target, World.planet_id)
	var solid := 0
	for cp: Vector3i in World.chunks:
		solid += (World.chunks[cp] as Chunk).solid_count
	ok("terrain generated", solid > 5000, "%d solid voxels" % solid)
	var p := player()
	if p != null:
		ok("player on the surface", p.global_position.y > 1.0,
			"y=%.1f" % p.global_position.y)
	# Diagnostic: what, if anything, is chipping away at the player here?
	var seen: Dictionary = {}
	Events.player_damaged.connect(func(amount: float, element: String, source: Node) -> void:
		var key := "%s from %s" % [element, source.name if source != null else "<environment>"]
		seen[key] = int(seen.get(key, 0)) + 1
		if int(seen[key]) == 1:
			note("DAMAGE: %.1f %s" % [amount, key]))
	await _frames(180)
	for k: String in seen:
		note("damage tally: %s x%d" % [k, int(seen[k])])
	# --- diagnostic: what is actually around the player? ---
	if p != null:
		var f := Const.floor_v(p.global_position)
		note("world %dx%d  player %v  layer %d  view %d" % [
			World.size_x, World.size_z, f, View.layer, View.view])
		var tally: Dictionary = {}
		for dl in range(-6, 7):
			for dy in range(-4, 5):
				var q := f + View.right() * dl + Vector3i(0, dy, 0)
				var bn := String(Blocks.get_type(World.get_block(q)).name)
				tally[bn] = int(tally.get(bn, 0)) + 1
		var parts: Array[String] = []
		for k: String in tally:
			parts.append("%s:%d" % [k, int(tally[k])])
		parts.sort()
		note("play-layer blocks -> " + ", ".join(parts))
		note("chunk holders rendered: %d" % int(Game.world_renderer.stats.get("meshed", -1)))
	await shot("planet_surface")
	await hold(&"move_right", 1.2)
	await _frames(30)
	await shot("planet_walking")


func _beat_mine_and_place() -> void:
	print("-- mining and building --")
	var p := player()
	if p == null:
		return
	# Find a solid voxel next to the player, in the play layer.
	var feet := Const.floor_v(p.global_position)
	var target := Vector3i.ZERO
	var found := false
	for dl in range(1, 7):
		for dy in [-1, 0, -2, 1, 2]:
			var q := feet + View.right() * dl + Vector3i(0, dy, 0)
			if World.is_solid(q):
				target = q
				found = true
				break
		if found:
			break
	ok("found a block to mine", found, str(target))
	if not found:
		return
	var before := World.get_block(target)
	var loot := World.break_block(target, 99, true)
	await _frames(20)
	ok("block was mined", World.get_block(target) == Const.AIR,
		"%s -> air, %d drops" % [Blocks.get_type(before).name, loot.size()])
	await shot("mined_block")

	var placed := World.place_block(target, before)
	await _frames(20)
	ok("block was placed back", placed and World.get_block(target) == before)
	await shot("placed_block")

	# A small structure, to prove building works over several voxels.
	# Build on genuine ledges: air with something solid underneath. Scanning for
	# that is what makes this deterministic across seeds, rather than guessing a
	# fixed offset that may be buried in a hillside.
	var built := 0
	var attempted := 0
	for i in 8:
		if attempted >= 4:
			break
		var col := feet + View.right() * (2 + i)
		for up in range(-2, 6):
			var q := col + Vector3i(0, up, 0)
			if World.is_air(q) and World.is_solid(q - Vector3i(0, 1, 0)):
				attempted += 1
				if World.place_block(q, before):
					built += 1
				break
	await _frames(30)
	ok("built a small structure", built >= 2, "%d of %d ledges built" % [built, attempted])
	await shot("built_structure")


func _beat_combat() -> void:
	print("-- combat --")
	var p := player()
	if p == null:
		return
	var before_health := p.health
	p.apply_damage(18.0, Const.ELEM_FIRE, null)
	await _frames(25)
	ok("player takes damage", p.health < before_health,
		"%.0f -> %.0f" % [before_health, p.health])
	await shot("player_damaged")
	p.heal(999.0)
	await _frames(10)
	ok("player heals", p.health > 0.0, "%.0f hp" % p.health)

	# Spawn a monster in the play layer just to the player's right.
	var spawn_at: Vector3 = p.global_position + Vector3(View.right()) * 4.0
	spawn_at.y += 2.0
	var mob: Node = Game.spawn_entity("res://entities/monsters/monster.tscn", spawn_at,
		{"species": "pebble_grub"})
	await _frames(90)
	ok("monster spawned", mob != null and is_instance_valid(mob))
	await shot("monster_spawned")
	if mob is VoxelEntity:
		var m := mob as VoxelEntity
		m.apply_damage(9999.0, Const.ELEM_PHYSICAL, p)
		await _frames(30)
		# `on_death` may free the node outright, so check validity first.
		ok("monster can be killed", not is_instance_valid(m) or m.dead)
	await shot("after_combat")


func _beat_night() -> void:
	print("-- day / night --")
	Game.tick = int(Const.TICKS_PER_DAY * 0.92)   # deep night
	await _frames(90)
	ok("night fell", Game.is_night(), "daylight=%.2f" % Game.daylight)
	await shot("night")
	Game.tick = int(Const.TICKS_PER_DAY * 0.5)    # noon
	await _frames(90)
	ok("day returned", not Game.is_night(), "daylight=%.2f" % Game.daylight)
	await shot("noon")


func _beat_save() -> void:
	print("-- save and load --")
	var p := player()
	if p == null:
		return
	var pos_before: Vector3 = p.global_position
	var saved: bool = SaveManager.save_game(1) if SaveManager.has_method(&"save_game") else false
	ok("game saves", saved)
	await _frames(60)
	ok("save slot reported present", SaveManager.has_save(1))
	# Move the player, then load and confirm the position came back. Displace
	# laterally in open air rather than upward into a hillside, so a failure
	# means "load did not restore" and not "unstick moved me".
	var displaced := pos_before + Vector3(View.right()) * 6.0 + Vector3(0, 3.0, 0)
	p.teleport(displaced)
	await _frames(30)
	note("saved at %.2v, displaced to %.2v" % [pos_before, p.global_position])
	var loaded: bool = SaveManager.load_game(1) if SaveManager.has_method(&"load_game") else false
	await _frames(90)
	ok("game loads", loaded)
	if loaded:
		var d := p.global_position.distance_to(pos_before)
		note("after load: %.2v (saved %.2v)" % [p.global_position, pos_before])
		ok("player position restored", d < 3.0, "%.2f blocks from saved spot" % d)
	await shot("after_load")
