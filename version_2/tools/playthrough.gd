extends Node

## Scripted play session.
##
##     godot --path . tools/playthrough.tscn            (needs a real renderer)
##     godot --headless --path . tools/playthrough.tscn (logic only)
##
## Drives a full session — walk, mine, build, craft, fight, farm, place objects,
## talk to a villager, open every panel, travel to another planet, save and
## reload — and writes a numbered PNG per beat into `$VOXELBOUND_SHOT_DIR` when
## a renderer is present.
##
## The panels are the reason this exists: they are only built when opened, so
## nothing else in the test suite ever executes them. Any error printed during
## this run is a real failure, and the exit code reflects it.

const SHOT_DIR := "user://playthrough"

var game: Node3D
var world: VoxelWorld
var player: Player
var ui: UIManager
var out_dir := ""
var shot := 0
var headless := false
var errors := 0


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	out_dir = OS.get_environment("VOXELBOUND_SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path(SHOT_DIR)
	if not headless:
		DirAccess.make_dir_recursive_absolute(out_dir)
	var packed: PackedScene = load("res://main.tscn")
	game = packed.instantiate()
	add_child(game)
	world = game.get_node("World")
	player = game.get_node("Player")
	_run()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _beat(name: String) -> void:
	shot += 1
	print("[playthrough] %02d %s" % [shot, name])
	await _settle(8)
	if headless:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("blank frame at %s" % name)
		errors += 1
		return
	img.save_png("%s/%02d_%s.png" % [out_dir, shot, name])


func _run() -> void:
	await world.world_ready
	await _settle(40)
	ui = game.ui
	await _beat("landfall")

	# --- walking and the camera
	player.velocity = Vector3(3.0, 0.0, 0.0)
	await _settle(40)
	await _beat("walked")
	game.rig.rotate_view(1)
	await _settle(40)
	await _beat("camera_turned")

	# --- mining and building
	var feet := player.feet_block()
	for i in 5:
		var c := Vector3i(feet.x + 2 + i, feet.y - 1, feet.z)
		world.set_block(c.x, c.y, c.z, Blocks.id(&"iron_ore"))
		player.break_block(c, 99)
	await _settle(30)
	await _beat("mined")

	player.give(&"stone_brick", 40)
	for i in 6:
		world.set_block(feet.x + 3, feet.y + i, feet.z + 3, Blocks.id(&"stone_brick"))
	await _settle(20)
	await _beat("built")

	# --- every panel, which is what this harness is really for
	player.give(&"wood_log", 12)
	player.give(&"iron_bar", 12)
	player.give(&"cobblestone", 30)
	ui.open(&"inventory")
	await _beat("panel_inventory")
	ui.open(&"crafting")
	await _beat("panel_crafting")
	ui.open(&"quests")
	await _beat("panel_quests")
	ui.open(&"starmap")
	await _beat("panel_starmap")
	game.tech.unlock(&"double_jump")
	game.tech.unlock(&"dash")
	ui.open(&"tech")
	await _beat("panel_tech")
	ui.close()

	# --- crafting for real, through the panel's own path
	var r := Crafting.get_recipe("planks_from_log")
	game.request_craft(r, Crafting.Station.new(&"hand"), null)
	await _settle(10)

	# --- objects: place a chest and a station, then open both
	var spot := Vector3i(feet.x + 4, feet.y, feet.z + 4)
	world.set_block(spot.x, spot.y - 1, spot.z, Blocks.STONE)
	world.set_block(spot.x, spot.y, spot.z, Blocks.AIR)
	world.set_block(spot.x, spot.y + 1, spot.z, Blocks.AIR)
	game.place_object(&"chest", spot, player)
	var chest: PlacedObject = game.object_at(spot)
	if chest != null:
		chest.store(Items.make(&"diamond", 4))
		ui.open_container(chest)
		await _beat("panel_container")
		game.quick_deposit(chest)
		ui.close()

	var bench := Vector3i(feet.x + 6, feet.y, feet.z + 4)
	world.set_block(bench.x, bench.y - 1, bench.z, Blocks.STONE)
	world.set_block(bench.x, bench.y, bench.z, Blocks.AIR)
	world.set_block(bench.x, bench.y + 1, bench.z, Blocks.AIR)
	game.place_object(&"workbench", bench, player)
	var wb: PlacedObject = game.object_at(bench)
	if wb != null:
		ui.open_crafting(wb.station, wb)
		await _beat("panel_station")
		ui.close()

	# --- an NPC and its shop
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var npc := Npc.spawn(game.npcs_root, world, player, game, &"merchant",
		player.global_position + Vector3(2.0, 0.5, 0.0), rng)
	await _settle(20)
	if npc != null:
		ui.open_dialogue(npc)
		await _beat("panel_dialogue")
		ui.open_dialogue(npc, true)
		await _beat("panel_shop")
		if not npc.stock.is_empty():
			player.inventory.pixels = 5000
			game.buy_from(npc, npc.stock[0], npc.buy_price(npc.stock[0]))
		ui.close()
		game.npc_offer_quest(npc)

	# --- combat
	var m: Monster = game.spawn_monster(&"thorn_creeper",
		player.global_position + Vector3(2.5, 0.6, 0.0), 1.0)
	await _settle(20)
	player.inventory.set_slot(0, Items.make(&"iron_sword", 1))
	player.inventory.select(0)
	player.aim_hit = {"hit": false}
	game.player_attack(player, player.held_stack())
	await _beat("combat")
	if m != null and is_instance_valid(m):
		m.hurt(9999.0, Blocks.ELEM_PHYSICAL, Vector3.ZERO, player)
	await _settle(20)

	# --- a projectile, and the cutaway weapons' code paths
	game.spawn_projectile(&"bullet", player.global_position + Vector3(0, 1.2, 0),
		Vector3(1, 0.1, 0).normalized(), 12.0, Blocks.ELEM_PHYSICAL, player)
	game.spawn_projectile(&"phase_lance", player.global_position + Vector3(0, 1.2, 0),
		Vector3(0, 0.1, 1).normalized(), 12.0, Blocks.ELEM_COSMIC, player)
	await _settle(30)
	game.explode(player.global_position + Vector3(6, 0, 0), 2.5, 10.0,
		Blocks.ELEM_FIRE, player)
	game.depth_blast(player.global_position + Vector3(-6, 0, 0), 2.0, 6.0, 8.0,
		Blocks.ELEM_ICE, player)
	await _beat("explosions")

	# --- farming: till, plant, and let it grow
	var plot := Vector3i(feet.x - 3, feet.y - 1, feet.z)
	world.set_block(plot.x, plot.y, plot.z, Blocks.id(&"tilled_soil"))
	world.set_block(plot.x, plot.y + 1, plot.z, Blocks.AIR)
	player.inventory.set_slot(0, Items.make(&"wheat_seed", 4))
	player.inventory.select(0)
	player.aim_hit = {"hit": true, "block": plot, "normal": Vector3i(0, 1, 0),
		"id": world.get_block(plot.x, plot.y, plot.z)}
	game.use_item(player, player.held_stack())
	await _settle(20)
	await _beat("farming")

	# --- liquids
	world.set_block(feet.x - 5, feet.y + 3, feet.z, Blocks.id(&"water"))
	game.liquids.on_block_changed(Vector3i(feet.x - 5, feet.y + 3, feet.z))
	await _settle(60)
	await _beat("water")

	# --- techs
	game.tech.equip(&"dash")
	game.tech.activate()
	await _settle(10)
	game.tech.equip(&"double_jump")
	player.velocity.y = 2.0
	game.tech.air_tech(player)
	await _settle(10)
	game.fold_cutaway()
	game.survey_pulse(player.global_position, 20.0)
	await _beat("techs")

	# --- night, so the lighting cycle actually runs
	game.sky.fraction = 0.03
	await _settle(20)
	await _beat("night")
	game.sky.fraction = 0.5
	await _settle(20)
	await _beat("noon")

	# --- travel, which reseeds and restreams the whole world
	game.ship_fuel = 99
	game.travel_to(Universe.PROVING_ID)
	await world.world_ready
	await _settle(60)
	await _beat("proving_ground")

	# --- save and reload
	game.save_game()
	await _settle(5)
	var ok: bool = game.load_game()
	if not ok:
		printerr("load failed")
		errors += 1
	await _settle(30)
	await _beat("after_load")

	print("[playthrough] %d beats, %d errors" % [shot, errors])
	get_tree().quit(1 if errors > 0 else 0)
