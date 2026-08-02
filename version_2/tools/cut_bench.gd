extends Node

## What the three cut modes actually cost while the player is moving.
##
## The old planar mode was a box anchored to the player's cell in all three
## axes, so every block of movement in any direction invalidated the cross-
## section and rebuilt it. This walks the player in a straight line, sideways
## and forward, and reports how many rebuilds each mode asks for and how long
## they take — which is the number that decides whether the mode is usable.

var game: Node3D
var world: VoxelWorld
var player: Player
var rows: Array[String] = []


func _ready() -> void:
	var packed: PackedScene = load("res://main.tscn")
	game = packed.instantiate()
	add_child(game)
	world = game.get_node("World")
	player = game.get_node("Player")
	_run()


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await world.world_ready
	await _settle(40)

	# Underground, where the cut modes are actually used and where a slice has
	# the most geometry to build.
	var feet := player.feet_block()
	var y := maxi(6, feet.y - 14)
	for dx in range(-40, 41):
		for dz in range(-40, 41):
			for dy in range(0, 4):
				world.set_block(feet.x + dx, y + dy, feet.z + dz, Blocks.AIR)
	player.teleport(Vector3(feet.x + 0.5, float(y) + 0.05, feet.z + 0.5))
	await _settle(60)

	for mode: int in [Cutaway.Mode.CYLINDER, Cutaway.Mode.FILL, Cutaway.Mode.PLANAR]:
		await _walk(mode, Vector3(1, 0, 0), "sideways")
		await _walk(mode, Vector3(0, 0, 1), "along view")

	print("")
	print("mode      direction    rebuilds  total ms  worst ms")
	for r: String in rows:
		print(r)
	get_tree().quit(0)


func _walk(mode: int, step: Vector3, label: String) -> void:
	world.set_cutaway_mode(mode)
	world.cutaway.enabled = true
	var start := player.global_position
	await _settle(30)

	var before: int = world.cut_rebuilds
	var total := 0.0
	var worst := 0.0
	for i in 32:
		player.teleport(start + step * float(i))
		world.update_cutaway(game.rig.camera.global_position,
			player.global_position)
		var t0 := Time.get_ticks_usec()
		# exactly the work _process would do, and time only that
		world.refresh_cutaway()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		await get_tree().process_frame

	rows.append("%-9s %-12s %8d  %8.2f  %8.2f" % [
		world.cutaway.mode_name(), label, world.cut_rebuilds - before,
		total, worst])
	player.teleport(start)
	await _settle(10)
