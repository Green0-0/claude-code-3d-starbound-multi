extends Node

## Development helper. Runs only when the game is launched with `--dev-shots`;
## drives the player through the situations the cutaway system exists for and
## writes a PNG of each so the look can be reviewed without a human at the
## keyboard. Harmless in normal play — Game only instantiates it on the flag.

const SHOT_DIR := "user://shots"

var game: Node3D
var world: VoxelWorld
var player: Player
var rig: CameraRig
var out_dir := ""


func run(g: Node3D) -> void:
	game = g
	world = g.get_node("World")
	player = g.get_node("Player")
	rig = g.get_node("CameraRig")
	out_dir = OS.get_environment("VOXELBOUND_SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_sequence()


func _sequence() -> void:
	await world.world_ready
	await _settle(90)
	await _shot("01_surface")

	var spawn := player.global_position

	# --- top of the pre-carved mineshaft
	var sx := int(floor(spawn.x)) + 4
	var sz := int(floor(spawn.z))
	var shaft_top := _standable(sx, sz, true)
	if shaft_top != Vector3.ZERO:
		player.teleport(shaft_top)
		await _settle(70)
		await _shot("02_shaft_mouth")

	# --- bottom of the shaft
	var shaft_bottom := _standable(sx, sz, false)
	if shaft_bottom != Vector3.ZERO:
		player.teleport(shaft_bottom)
		await _settle(70)
		await _shot("03_shaft_bottom")

		# --- deep in the horizontal gallery
		var gx := sx + 16
		var gy := int(shaft_bottom.y)
		if not world.is_solid_at(gx, gy, sz) and world.is_solid_at(gx, gy - 1, sz):
			player.teleport(Vector3(gx + 0.5, float(gy) + 0.05, sz + 0.5))
			await _settle(70)
			await _shot("04_tunnel")

			rig.rotate_view(1)
			await _settle(80)
			await _shot("05_tunnel_rotated")

			rig.rotate_view(1)
			await _settle(80)
			await _shot("06_tunnel_rotated_180")
			rig.rotate_view(-1)
			rig.rotate_view(-1)
			await _settle(80)

			# --- the three cut shapes, from the same spot in the gallery
			world.set_cutaway_mode(Cutaway.Mode.FILL)
			await _settle(60)
			await _shot("04b_tunnel_fill")
			world.set_cutaway_mode(Cutaway.Mode.PLANAR)
			await _settle(60)
			await _shot("04c_tunnel_planar")
			world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
			world.set_cutaway_opacity(0.45)
			await _settle(60)
			await _shot("04d_tunnel_ghosted")
			world.set_cutaway_opacity(0.0)
			await _settle(30)

	# --- back to the surface for a control pair
	player.teleport(spawn)
	await _settle(70)
	await _shot("07_surface_cutaway_on")
	world.set_cutaway_enabled(false)
	await _settle(40)
	await _shot("08_surface_cutaway_off")
	world.set_cutaway_enabled(true)

	# --- inside a house
	var house := _find_interior()
	if house != Vector3.ZERO:
		player.teleport(house + Vector3(0, 0, 0))
		await _settle(90)
		await _shot("09_house_interior")
		rig.rotate_view(1)
		await _settle(80)
		await _shot("10_house_rotated")
		world.set_cutaway_mode(Cutaway.Mode.FILL)
		await _settle(70)
		await _shot("11_house_fill")
		world.set_cutaway_mode(Cutaway.Mode.CYLINDER)

	# --- the keep shell: stand next to a tree and check it survives
	var tree := _find_tree()
	if tree != Vector3.ZERO:
		player.teleport(tree)
		await _settle(90)
		await _shot("12_tree_reachable")

	print("[dev_capture] wrote shots to ", out_dir)
	game.get_tree().quit()


## Highest (or lowest) cell in a column you could stand in.
func _standable(x: int, z: int, highest: bool) -> Vector3:
	var found := Vector3.ZERO
	for y in range(1, VoxelWorld.WH - 2):
		if world.is_solid_at(x, y, z):
			continue
		if world.is_solid_at(x, y + 1, z):
			continue
		if not world.is_solid_at(x, y - 1, z):
			continue
		found = Vector3(x + 0.5, float(y) + 0.05, z + 0.5)
		if not highest:
			return found
	return found


## Somewhere to stand right beside a tree trunk, which is the case the keep
## shell exists for: the trunk must not vanish as you walk up to it.
func _find_tree() -> Vector3:
	var c := player.global_position
	for r in range(3, 70, 2):
		for i in 48:
			var a := TAU * float(i) / 48.0
			var x := int(c.x + cos(a) * r)
			var z := int(c.z + sin(a) * r)
			if not world.is_loaded(x, z):
				continue
			for y in range(6, VoxelWorld.WH - 4):
				var id := world.get_block(x, y, z)
				if id == Blocks.AIR or not Blocks.get_def(id).tags.has(&"tree_log"):
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
						Vector2i(0, 1), Vector2i(0, -1)]:
					var sx2 := x + d.x
					var sz2 := z + d.y
					if world.is_solid_at(sx2, y, sz2) \
							or world.is_solid_at(sx2, y + 1, sz2):
						continue
					if not world.is_solid_at(sx2, y - 1, sz2):
						continue
					return Vector3(sx2 + 0.5, float(y) + 0.05, sz2 + 0.5)
	return Vector3.ZERO


## Look for an enclosed pocket of air with a plank floor — i.e. a house.
func _find_interior() -> Vector3:
	if world.house_spawn != Vector3i.ZERO:
		var h := world.house_spawn
		if not world.is_solid_at(h.x, h.y, h.z):
			return Vector3(h.x + 0.5, float(h.y) + 0.05, h.z + 0.5)
	var c := player.global_position
	for r in range(6, 90, 2):
		for i in 36:
			var a := TAU * float(i) / 36.0
			var x := int(c.x + cos(a) * r)
			var z := int(c.z + sin(a) * r)
			if not world.is_loaded(x, z):
				continue
			for y in range(4, VoxelWorld.WH - 2):
				if world.get_block(x, y, z) != Blocks.DARK_PLANKS:
					continue
				if world.is_solid_at(x, y + 1, z) or world.is_solid_at(x, y + 2, z):
					continue
				if not world.is_solid_at(x, y + 4, z):
					continue    # needs a roof over it
				return Vector3(x + 0.5, y + 1.05, z + 0.5)
	return Vector3.ZERO


func _settle(frames: int) -> void:
	for i in frames:
		await game.get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := game.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("[dev_capture] ", name)
