extends Node

## The three cut modes, photographed underground where they are actually used.
##
##     godot --path . tools/cut_shots.tscn
##
## Carves a room with a side tunnel, stands the player in it under a hillside,
## and takes one frame per mode. This is the check that the predicate rewrite
## did not just satisfy the assertions but still produces a picture you can
## play with.

const SHOT_DIR := "user://cut_shots"

var game: Node3D
var world: VoxelWorld
var player: Player
var out_dir := ""
var headless := false


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	out_dir = OS.get_environment("VOXELBOUND_SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var packed: PackedScene = load("res://main.tscn")
	game = packed.instantiate()
	add_child(game)
	world = game.get_node("World")
	player = game.get_node("Player")
	_run()


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _settle(24)
	print("[cut] %s  fps=%d" % [name, Engine.get_frames_per_second()])
	if headless:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png("%s/%s.png" % [out_dir, name])


func _run() -> void:
	await world.world_ready
	await _settle(40)

	# A room under the hill, with a corridor running off it, and solid rock
	# above — so there is genuinely something between the player and the lens.
	var feet := player.feet_block()
	var y := maxi(5, feet.y - 12)
	var cx := feet.x
	var cz := feet.z
	for dx in range(-6, 7):
		for dz in range(-5, 6):
			for dy in range(0, 5):
				world.set_block(cx + dx, y + dy, cz + dz, Blocks.AIR)
	# a corridor heading off north
	for dz in range(-26, -5):
		for dx in range(-1, 2):
			for dy in range(0, 3):
				world.set_block(cx + dx, y + dy, cz + dz, Blocks.AIR)
	# and a couple of lamps so the room is not a black box
	world.set_block(cx - 4, y + 3, cz - 3, Blocks.id(&"glowstone"))
	world.set_block(cx + 4, y + 3, cz + 3, Blocks.id(&"glowstone"))
	world.set_block(cx, y + 2, cz - 18, Blocks.id(&"glowstone"))

	player.teleport(Vector3(cx + 0.5, float(y) + 0.05, cz + 0.5))
	game.sky.fraction = 0.5
	await _settle(60)

	for mode: int in [Cutaway.Mode.CYLINDER, Cutaway.Mode.FILL, Cutaway.Mode.PLANAR]:
		world.set_cutaway_mode(mode)
		world.cutaway.enabled = true
		await _settle(30)
		await _shot("cut_%s" % world.cutaway.mode_name().to_lower())

	# and planar again from a turned camera, since it is the mode whose whole
	# definition is "which coordinate plane"
	world.set_cutaway_mode(Cutaway.Mode.PLANAR)
	game.rig.rotate_view(1)
	await _settle(40)
	await _shot("cut_planar_turned")

	print("[cut] done -> %s" % out_dir)
	get_tree().quit(0)
