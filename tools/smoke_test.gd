## Headless integration smoke test.
##
##   godot --headless --path . tools/smoke_test.tscn
##
## Boots the real `main.tscn`, lets the world stream in, then asserts the things
## that must be true for the game to be playable at all: the registries filled,
## terrain generated, the player is standing on solid ground, and both halves of
## the perspective mechanic (flip and layer shift) actually change state.
## Exits non-zero on failure so it can gate a build.
extends Node

const BOOT_FRAMES := 240
const SETTLE_FRAMES := 90

var _fail: Array[String] = []
var _pass: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass.append(label)
		print("  PASS  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])
	else:
		_fail.append(label)
		print("  FAIL  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	print("\n=== PLANESHIFT SMOKE TEST ===\n")
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(BOOT_FRAMES)

	# ---------------------------------------------------------- registries
	print("-- registries --")
	check("blocks registered", Blocks.count() > 100, "%d" % Blocks.count())
	check("items registered", Items.count() > 100, "%d" % Items.count())
	check("air is id 0", Blocks.id(&"air") == Const.AIR)
	check("stone resolves", Blocks.has(&"stone") and Blocks.id(&"stone") != Const.AIR)
	# A shader that fails to compile makes `Atlas` hand back an untextured
	# StandardMaterial3D fallback, and the whole world silently renders white.
	# Assert we got the real slab shader on every voxel pass.
	for pass_name: Array in [["opaque", Atlas.get_material(false)],
			["transparent", Atlas.get_material(true)],
			["liquid", Atlas.get_liquid_material()]]:
		check("voxel material compiled: " + String(pass_name[0]),
			pass_name[1] is ShaderMaterial,
			"got %s" % ("ShaderMaterial" if pass_name[1] is ShaderMaterial else str(pass_name[1])))

	# --------------------------------------------------------------- world
	print("-- world --")
	check("world ready", World.ready_flag, World.planet_id)
	check("chunks streamed", World.chunks.size() > 0, "%d chunks" % World.chunks.size())
	var solid := 0
	for cp: Vector3i in World.chunks:
		solid += (World.chunks[cp] as Chunk).solid_count
	check("terrain has solid voxels", solid > 0, "%d voxels" % solid)

	# -------------------------------------------------------------- player
	print("-- player --")
	var p: VoxelEntity = Game.player
	check("player exists", p != null)
	if p == null:
		return _finish()
	await _frames(SETTLE_FRAMES)
	var pos: Vector3 = p.global_position
	check("player inside world height", pos.y > 0.0 and pos.y < float(Const.WORLD_HEIGHT),
		"y=%.1f" % pos.y)
	check("player not falling through world", not (pos.y < 1.0), "y=%.1f" % pos.y)
	var free := VoxelPhysics.aabb_is_free(pos, p.get_aabb_size())
	var overlap_desc := ""
	if not free:
		var names: Array[String] = []
		for b: Vector3i in VoxelPhysics.overlapping_blocks(pos, p.get_aabb_size()):
			var bt := Blocks.get_type(World.get_block(b))
			names.append("%s@%v solid=%s platform=%s" % [bt.name, b, bt.solid, bt.platform])
		overlap_desc = "; ".join(names)
	check("player box is free", free, overlap_desc)

	# ------------------------------------------------------- FLIP mechanic
	print("-- perspective: flip --")
	var view_before: int = View.view
	var pos_before: Vector3 = p.global_position
	var started := View.request_flip(1)
	check("flip accepted", started)
	# main.gd drives View.advance_flip; wait past flip_duration.
	await _frames(int(View.flip_duration * 70.0) + 30)
	check("view index advanced", View.view == wrapi(view_before + 1, 0, Const.VIEW_COUNT),
		"%d -> %d" % [view_before, View.view])
	check("flip finished", not View.flipping)
	check("depth axis swapped", View.depth_axis() != Const.VIEW_DEPTH_AXIS[view_before],
		"axis %d" % View.depth_axis())
	# The defining property: a flip rotates the world, it never moves the player
	# laterally or vertically. A sub-block depth re-centre is expected.
	var moved: Vector3 = p.global_position - pos_before
	check("player did not move vertically", absf(moved.y) < 1.5, "dy=%.3f" % moved.y)

	# ------------------------------------------------------ SHIFT mechanic
	print("-- perspective: layer shift --")
	var layer_before: int = View.layer
	var shifted := View.request_shift(1)
	if shifted:
		await _frames(int(View.shift_duration * 70.0) + 30)
		check("layer advanced", View.layer == layer_before + 1,
			"%d -> %d" % [layer_before, View.layer])
		check("shift finished", not View.shifting)
		check("player still in free space",
			VoxelPhysics.aabb_is_free(p.global_position, p.get_aabb_size()))
	else:
		# Refusal is legitimate — the destination layer was solid. It must be
		# refused cleanly, leaving no half-applied state behind.
		check("blocked shift left no state", not View.shifting and View.layer == layer_before,
			"destination occupied, refused cleanly")

	# ------------------------------------------------- superflat proving ground
	print("-- superflat test world --")
	var flat_id: String = Universe.SUPERFLAT_ID
	check("superflat world exists", Universe.planet_meta(flat_id).has("id"), flat_id)
	check("superflat is discovered from the start", Universe.is_discovered(flat_id))
	check("superflat is in the home system",
		Universe.system_body_ids(Universe.current_system_id()).has(flat_id)
			or Universe.system_body_ids(Universe.home_system).has(flat_id))
	check("superflat costs no fuel", Universe.fuel_cost_to(flat_id) == 0,
		"%d fuel" % Universe.fuel_cost_to(flat_id))
	var gate: Dictionary = Universe.can_travel_to(flat_id)
	check("superflat is reachable now", bool(gate.get("ok", false)),
		String(gate.get("reason", "")))
	check("superflat declares no hostiles",
		not bool(Universe.planet_meta(flat_id).get("hostiles", true)))

	# Actually travel there and inspect the terrain.
	Game.travel_to_planet(flat_id)
	await _frames(240)
	check("landed on superflat", World.planet_id == flat_id, World.planet_id)
	var ground: int = int(Universe.planet_meta(flat_id).get("flat_height", 64))
	var flat_ok := true
	var sample := ""
	for dx in [-6, 0, 7]:
		for dz in [-6, 0, 7]:
			var col_x: int = (World.size_x >> 1) + dx
			var col_z: int = (World.size_z >> 1) + dz
			var g := World.ground_y(col_x, col_z)
			if g != ground:
				flat_ok = false
				sample = "column (%d,%d) ground %d, expected %d" % [col_x, col_z, g, ground]
			if not World.is_air(Vector3i(col_x, ground + 1, col_z)):
				flat_ok = false
				sample = "column (%d,%d) is not clear above the surface" % [col_x, col_z]
	check("superflat terrain is flat", flat_ok, sample if sample != "" else "ground y=%d" % ground)
	var em: Node = Game.entities_root
	check("hostile population cap is zero on superflat",
		em != null and em.has_method(&"population_cap") and int(em.call(&"population_cap")) == 0)

	# --------------------------------------------------------- starting kit
	print("-- starting kit --")
	var inv: Variant = p.get("inventory")
	var dirt := 0
	if inv != null and inv.has_method(&"count_of"):
		dirt = int(inv.call(&"count_of", &"dirt"))
	elif p.has_method(&"count_item"):
		dirt = int(p.call(&"count_item", &"dirt"))
	check("player starts with 99 dirt", dirt == 99, "%d dirt" % dirt)

	# ------------------------------------------------------------ plane maths
	print("-- plane-space round trip --")
	var ok_round := true
	for v in Const.VIEW_COUNT:
		var w := Vector3(12.5, 40.0, -7.25)
		var plane := View.to_plane(w, v)
		var back := View.to_world(plane, Const.depth_of(w, v), v)
		if back.distance_to(w) > 0.001:
			ok_round = false
	check("to_plane/to_world invert in all 4 views", ok_round)

	_finish()


func _finish() -> void:
	print("\n=== %d passed, %d failed ===" % [_pass.size(), _fail.size()])
	if not _fail.is_empty():
		print("FAILURES:")
		for f: String in _fail:
			print("  - " + f)
	get_tree().quit(0 if _fail.is_empty() else 1)
