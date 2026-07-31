extends Node3D

## Root orchestration: registries, input bindings, the boot sequence, and the
## once-per-frame hand-off that keeps the camera, the cutaway predicate and the
## cross-section geometry in agreement.
##
## Everything that needs to reach across module boundaries goes through here
## rather than through a web of direct references — the player asks the hub to
## resolve a swing, the hub asks combat; a monster dies and tells the hub, the
## hub tells the quest manager and drops the loot. That keeps the actors small
## and means there is exactly one file to read to understand the wiring.

const MAX_MONSTERS := 22
const MAX_DROPS := 180
const SPAWN_INTERVAL := 3.5
const AUTOSAVE_INTERVAL := 120.0
const SAVE_PATH := "user://voxelbound_save.json"

@onready var world: VoxelWorld = $World
@onready var player: Player = $Player
@onready var rig: CameraRig = $CameraRig
@onready var hud: HUD = $HUD
@onready var highlight: MeshInstance3D = $Highlight
@onready var monsters_root: Node3D = $Critters
@onready var sun: DirectionalLight3D = $Sun
@onready var environment_node: WorldEnvironment = $WorldEnvironment

var ui: UIManager
var drops_root: Node3D
var objects_root: Node3D
var npcs_root: Node3D
var shots_root: Node3D

var universe := Universe.new()
var quests := Quests.Manager.new()
var tech := TechManager.new()
var liquids := Liquids.new()
var sky := SkyCycle.new()

var known_recipes := {}
var ship_fuel := 4
var current_planet_id := ""
var run_seed := 20260730
var input_locked := false
var stats := {}

var _booted := false
var _spawn_timer := 0.0
var _autosave := AUTOSAVE_INTERVAL
var _rng := RandomNumberGenerator.new()
var _pending_spawn := Vector3.ZERO
var _hand_station := Crafting.Station.new(&"hand")
var _deepest := 999
var _travel_target := ""


# =============================================================================
# boot
# =============================================================================

func _enter_tree() -> void:
	# Registries first: the world's _ready() builds the atlas out of them, and a
	# parent's _enter_tree always runs before any child's.
	Blocks.boot()
	Items.boot()
	Crafting.boot()
	ObjectDB.boot()
	SpeciesDB.boot()
	NpcRoles.boot()
	EffectLib.boot()
	Quests.boot()
	_setup_input()


func _ready() -> void:
	_rng.seed = run_seed
	player.visible = false
	player.world = world
	player.rig = rig
	player.game = self
	rig.target = player
	hud.player = player
	hud.rig = rig
	hud.world = world
	hud.game = self

	drops_root = _container("Drops")
	objects_root = _container("Objects")
	npcs_root = _container("Npcs")
	shots_root = _container("Shots")

	ui = UIManager.new()
	ui.game = self
	ui.player = player
	add_child(ui)
	ui.panel_opened.connect(func(_n: StringName) -> void: input_locked = true)
	ui.panel_closed.connect(func() -> void: input_locked = false)

	quests.game = self
	tech.player = player
	tech.game = self
	liquids.world = world
	liquids.game = self
	sky.setup(sun, environment_node, player)
	known_recipes = Crafting.starting_knowledge()

	highlight.mesh = _make_wire_box()
	highlight.visible = false

	world.generation_progress.connect(_on_progress)
	world.world_ready.connect(_on_world_ready)
	player.died.connect(func() -> void: hud.show_death(true))
	player.inventory.picked_up.connect(_on_item_picked)

	universe.generate(run_seed)
	var start := universe.starting_planet()
	current_planet_id = start.id
	start.visited = true
	world.load_planet(start.world_config())
	sky.configure(start.world_config())

	world.focus_on(Vector3.ZERO)
	hud.set_loading(0, 1)

	if OS.get_cmdline_args().has("--dev-shots"):
		var cap: Node = load("res://scripts/dev_capture.gd").new()
		add_child(cap)
		cap.run(self)


func _container(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	add_child(n)
	return n


func _on_progress(done: int, total: int) -> void:
	if not _booted:
		hud.set_loading(done, total)


func _on_world_ready() -> void:
	if _booted:
		_finish_travel()
		return
	_booted = true

	var spawn := world.find_spawn()
	world.carve_spawn_features(spawn)

	var p := Vector3(spawn.x + 0.5, spawn.y + 0.2, spawn.z + 0.5)
	var top := world.column_top(spawn.x, spawn.z)
	if top >= 0:
		p.y = float(top) + 1.05
	player.teleport(p)
	player.visible = true
	_grant_starting_kit()
	quests.start("main_01_landfall")

	rig.global_position = p + Vector3(0, rig.height_offset, 0)
	_sync_cutaway()

	hud.finish_loading()
	notify("You are down, and you are alive. Start with wood.", &"quest")
	for i in 6:
		_spawn_monster_near_player()
	_populate_structures()


## Enough to get out of the first five minutes without a lucky spawn.
func _grant_starting_kit() -> void:
	player.give(&"matter_manipulator", 1)
	player.give(&"stone_pickaxe", 1)
	player.give(&"torch", 8)
	player.give(&"bread", 3)
	player.give(&"water_flask", 2)
	player.give(&"wood_planks", 24)
	player.inventory.pixels = 120
	player.inventory.select(0)


# =============================================================================
# frame
# =============================================================================

func _process(delta: float) -> void:
	if not _booted:
		return

	world.focus_on(player.global_position)
	_sync_cutaway()
	sky.tick(delta)
	sky.follow(player.global_position)
	liquids.tick(delta)
	tech.tick(delta)
	_update_environment()

	var mouse := get_viewport().get_mouse_position()
	if not input_locked:
		player.update_aim(rig.camera, mouse)
		_update_highlight()
		if player.is_alive():
			if Input.is_action_pressed(&"mine"):
				player.try_mine(delta)
			else:
				player.cancel_mine()
	else:
		highlight.visible = false
		player.cancel_mine()

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_tick_population()

	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = AUTOSAVE_INTERVAL
		save_game()

	# depth is a quest objective, and worth a note the first time
	var y: int = int(floor(player.global_position.y))
	if y < _deepest:
		_deepest = y
		quests.on_depth(y)


## The single point where camera state becomes cutaway state. Everything else —
## the shader discard, the cross-section caps, the raycast — reads from here.
func _sync_cutaway() -> void:
	world.update_cutaway(rig.camera.global_position, player.global_position)


## Ambient temperature and daylight, fed to the survival needs.
func _update_environment() -> void:
	if player.stats == null:
		return
	var feet := player.feet_block()
	var sheltered := world.column_top(feet.x, feet.z) > feet.y + 1
	player.stats.warmth = sky.warmth_at(world.gen.palette.warmth,
		float(feet.y), sheltered)


func _update_highlight() -> void:
	if player.aim_hit.get("hit", false):
		var b: Vector3i = player.aim_hit["block"]
		highlight.visible = true
		highlight.global_position = Vector3(b) + Vector3(0.5, 0.5, 0.5)
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.02
		highlight.scale = Vector3.ONE * pulse
	else:
		highlight.visible = false


# =============================================================================
# input
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cancel"):
		if ui.is_open():
			ui.close()
		elif hud.help_panel.visible:
			hud.toggle_help()
		else:
			get_tree().quit()
		return

	if event.is_action_pressed(&"inventory"):
		ui.open(&"inventory")
	elif event.is_action_pressed(&"crafting"):
		ui.open_crafting(_station_in_reach(), _station_object_in_reach())
	elif event.is_action_pressed(&"quest_log"):
		ui.open(&"quests")
	elif event.is_action_pressed(&"star_map"):
		ui.open(&"starmap")
	elif event.is_action_pressed(&"tech_panel"):
		ui.open(&"tech")
	elif event.is_action_pressed(&"toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed(&"toggle_cutaway"):
		world.set_cutaway_enabled(not world.cutaway.enabled)
		notify("Cutaway %s." % ("on" if world.cutaway.enabled else "off"), &"info")
	elif event.is_action_pressed(&"cutaway_mode"):
		_cycle_cutaway_mode()
	elif event.is_action_pressed(&"cutaway_opacity"):
		_cycle_cutaway_opacity()
	elif event.is_action_pressed(&"cutaway_select"):
		world.set_cutaway_selectable(not world.cutaway.selectable)
		notify("Cut blocks are %s." % ("mineable" if world.cutaway.selectable
			else "locked"), &"info")
	elif event.is_action_pressed(&"quick_save"):
		save_game()
		notify("Saved.", &"info")
	elif event.is_action_pressed(&"respawn"):
		if not player.is_alive():
			player.respawn()
			hud.show_death(false)

	if input_locked:
		return

	if event.is_action_pressed(&"place"):
		if player.is_alive() and player.try_place():
			hud.flash_stack(player.held_stack())
	elif event.is_action_pressed(&"attack"):
		if player.is_alive():
			player.swing()
	elif event.is_action_pressed(&"interact"):
		if player.is_alive():
			player_interact(player)
	elif event.is_action_pressed(&"tech"):
		if player.is_alive():
			tech.activate()
	elif event.is_action_pressed(&"drop_item"):
		_drop_held()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.ctrl_pressed:
			player.cycle_slot(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.ctrl_pressed:
			player.cycle_slot(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		for i in 9:
			if event.physical_keycode == KEY_1 + i:
				player.select_slot(i)
				hud.flash_stack(player.held_stack())
				return


## The three cut shapes, in the order they are worth trying: the drill, the
## whole-room fill, and the flat cross-section.
func _cycle_cutaway_mode() -> void:
	var next := wrapi(world.cutaway.mode + 1, 0, 3)
	world.set_cutaway_mode(next)
	var blurb := {
		Cutaway.Mode.CYLINDER: "a drill from the lens to you",
		Cutaway.Mode.FILL: "the whole room or tunnel you are standing in",
		Cutaway.Mode.PLANAR: "a flat slab in front of you when you are covered",
	}
	notify("Cutaway: %s — %s." % [world.cutaway.mode_name(), blurb[next]], &"info")


## Off, ghost, or solid-ish. Zero deletes cut blocks outright; anything above
## draws them as dithered ghosts that thin out with distance from you.
func _cycle_cutaway_opacity() -> void:
	const STEPS := [0.0, 0.35, 0.65]
	var current := world.cutaway.opacity
	var index := 0
	for i in STEPS.size():
		if is_equal_approx(current, STEPS[i]):
			index = i
	var next: float = STEPS[wrapi(index + 1, 0, STEPS.size())]
	world.set_cutaway_opacity(next)
	if next <= 0.0:
		notify("Cut blocks removed outright.", &"info")
	else:
		notify("Cut blocks ghosted at %d%%, fading over %d blocks."
			% [int(next * 100.0), int(world.cutaway.fade_distance)], &"info")


func _drop_held() -> void:
	var s := player.held_stack()
	if s.is_empty():
		return
	var out := s.split(s.count)
	var dir := Vector3(rig.axis())
	ItemDrop.spawn(drops_root, world,
		player.global_position + Vector3(0, 1.0, 0) + dir * 0.8, out)
	player.inventory.changed.emit()


# =============================================================================
# blocks
# =============================================================================

func on_block_broken(at: Vector3i, block_id: int, yields: Array) -> void:
	var centre := Vector3(at) + Vector3(0.5, 0.5, 0.5)
	for pair: Array in yields:
		if pair[0] == &"":
			continue
		ItemDrop.spawn(drops_root, world, centre, Items.make(pair[0], int(pair[1])))
	liquids.on_block_changed(at)
	_prune_drops()
	bump_stat("blocks_mined", 1)
	# a crop harvested by hand is still a harvest
	liquids.forget(at)
	var def := Blocks.get_def(block_id)
	if def.tags.has(&"crop_mature"):
		bump_stat("crops_harvested", 1)


func on_block_placed(at: Vector3i, block_id: int) -> void:
	liquids.on_block_changed(at)
	bump_stat("blocks_placed", 1)
	var def := Blocks.get_def(block_id)
	quests.on_block_placed(def.name)
	# planting: a seedling registers with the growth ticker
	if def.tags.has(&"crop_stage"):
		var row := CropTable.row_of(_crop_of(def))
		if not row.is_empty():
			liquids.plant(at, float(row["seconds"]))


static func _crop_of(def: Blocks.Def) -> StringName:
	var parts := String(def.name).split("_stage_")
	return StringName(parts[0]) if parts.size() == 2 else &""


## Blow a sphere of terrain out and hurt anything inside it. Blast resistance
## means obsidian survives what dirt does not.
func explode(centre: Vector3, radius: float, damage: float,
		element: StringName, source: Node) -> void:
	var r := int(ceil(radius))
	var c := Vector3i(int(floor(centre.x)), int(floor(centre.y)), int(floor(centre.z)))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var d := Vector3(dx, dy, dz).length()
				if d > radius:
					continue
				var cell := c + Vector3i(dx, dy, dz)
				var id := world.get_block(cell.x, cell.y, cell.z)
				if id == Blocks.AIR:
					continue
				var def := Blocks.get_def(id)
				if not def.breakable or def.blast > radius * 12.0:
					continue
				world.set_block(cell.x, cell.y, cell.z, Blocks.AIR)
				if _rng.randf() < 0.25:
					var drops := def.roll_drops(99, _rng)
					for pair: Array in drops:
						ItemDrop.spawn(drops_root, world,
							Vector3(cell) + Vector3(0.5, 0.5, 0.5),
							Items.make(pair[0], int(pair[1])))
	_damage_sphere(centre, radius + 1.0, damage, element, source)
	spawn_impact(centre, Color(1.0, 0.7, 0.3))
	liquids.on_block_changed(c)


## The Depth Charge's blast: a cylinder running back along the camera's line of
## sight instead of a sphere, so it clears exactly the corridor the cutaway has
## opened up in front of you.
func depth_blast(centre: Vector3, radius: float, depth: float, damage: float,
		element: StringName, source: Node) -> void:
	var axis := (rig.camera.global_position - centre)
	axis.y = 0.0
	if axis.length() < 0.01:
		axis = Vector3(rig.axis())
	axis = axis.normalized()
	var steps := int(depth / 1.5)
	for i in steps:
		var at := centre + axis * (float(i) * 1.5)
		explode(at, maxf(radius * (1.0 - float(i) / float(steps) * 0.4), 1.0),
			damage * 0.55, element, source)


func shockwave(centre: Vector3, radius: float, damage: float) -> void:
	_damage_sphere(centre, radius, damage, Blocks.ELEM_PHYSICAL, player)
	spawn_impact(centre, Color(0.9, 0.85, 0.7))


func _damage_sphere(centre: Vector3, radius: float, damage: float,
		element: StringName, source: Node) -> void:
	for n in monsters_root.get_children():
		var m := n as Monster
		if m == null:
			continue
		var d := m.global_position.distance_to(centre)
		if d > radius:
			continue
		var falloff := 1.0 - d / radius
		m.hurt(damage * falloff, element,
			(m.global_position - centre).normalized() * 8.0, source)
	if source != player and player.is_alive():
		var pd := player.global_position.distance_to(centre)
		if pd < radius:
			player.hurt(damage * (1.0 - pd / radius) * 0.6, element)


# =============================================================================
# items and crafting
# =============================================================================

func on_item_picked_up(item_id: StringName, count: int) -> void:
	quests.on_item_gained(item_id, count)
	_learn_from(item_id)


func _on_item_picked(item_id: StringName, count: int) -> void:
	if item_id != &"":
		hud.flash_pickup(item_id, count)


## Picking a material up for the first time teaches every recipe that uses it.
## That is how the game explains itself: mine copper, learn what copper is for.
func _learn_from(item_id: StringName) -> void:
	var taught := Crafting.taught_by(item_id)
	var learned := 0
	for r: Crafting.Recipe in taught:
		if known_recipes.has(r.id):
			continue
		known_recipes[r.id] = true
		learned += 1
	if learned > 0:
		notify("%d new recipe%s." % [learned, "" if learned == 1 else "s"], &"craft")


func use_item(who: Player, stack: Items.Stack) -> bool:
	var t := stack.type()
	if t == null:
		return false
	match t.kind:
		Items.Kind.CONSUMABLE:
			if who.stats != null and who.stats.consume(stack):
				stack.count -= 1
				if stack.count <= 0:
					stack.clear()
				who.inventory.changed.emit()
				bump_stat("items_eaten", 1)
				return true
			return false
		Items.Kind.SEED:
			return _plant_seed(who, stack, t)
		Items.Kind.TECH:
			if tech.unlock(t.tech_id):
				stack.count -= 1
				if stack.count <= 0:
					stack.clear()
				who.inventory.changed.emit()
				notify("Tech unlocked: %s." % Items.get_type(stack.id).display, &"quest")
				return true
			notify("Missing the prerequisite tech.", &"warn")
			return false
	# tools with a use: the hoe tills, the watering can waters
	if t.tool_kind == &"hoe":
		return _till(who)
	if t.tool_kind == &"watering_can":
		return _water(who)
	return false


func _target_cell(who: Player) -> Vector3i:
	if not who.aim_hit.get("hit", false):
		return Player.NO_CELL
	return who.aim_hit["block"]


func _till(who: Player) -> bool:
	var cell := _target_cell(who)
	if cell == Player.NO_CELL:
		return false
	var def := Blocks.get_def(world.get_block(cell.x, cell.y, cell.z))
	if not def.tags.has(&"soil"):
		return false
	if world.get_block(cell.x, cell.y + 1, cell.z) != Blocks.AIR:
		return false
	world.set_block(cell.x, cell.y, cell.z, Blocks.id(&"tilled_soil"))
	return false            # tools are never consumed


func _water(who: Player) -> bool:
	var cell := _target_cell(who)
	if cell == Player.NO_CELL:
		return false
	if Blocks.get_def(world.get_block(cell.x, cell.y, cell.z)).tags.has(&"tilled"):
		world.set_block(cell.x, cell.y, cell.z, Blocks.id(&"watered_soil"))
	return false


func _plant_seed(who: Player, stack: Items.Stack, t: Items.Type) -> bool:
	var cell := _target_cell(who)
	if cell == Player.NO_CELL:
		return false
	var soil := Blocks.get_def(world.get_block(cell.x, cell.y, cell.z))
	if not soil.tags.has(&"tilled"):
		notify("Seeds need tilled soil. Use a hoe.", &"warn")
		return false
	var above := cell + Vector3i.UP
	if world.get_block(above.x, above.y, above.z) != Blocks.AIR:
		return false
	var stage0 := Blocks.id(CropTable.stage_block_name(t.seed_crop, 0))
	if stage0 == Blocks.AIR:
		return false
	world.set_block(above.x, above.y, above.z, stage0)
	stack.count -= 1
	if stack.count <= 0:
		stack.clear()
	who.inventory.changed.emit()
	return true


func request_craft(r: Crafting.Recipe, station: Crafting.Station,
		obj: PlacedObject) -> void:
	if not Crafting.can_craft(player.inventory, r):
		notify("Not enough materials.", &"warn")
		return
	if station != null and not station.instant and r.seconds > 0.0:
		if station.needs_fuel and station.fuel <= 0.0 and not _refuel(station):
			notify("The furnace needs fuel.", &"warn")
			return
		for pair: Array in r.inputs:
			player.inventory.remove(pair[0], int(pair[1]))
		station.enqueue(r)
		notify("Queued: %s." % r.display_name(), &"craft")
		return
	var overflow := Crafting.craft(player.inventory, r, _rng)
	_spill(overflow)
	_after_craft(r)
	if obj != null:
		pass


## Auto-feed the furnace out of the bag, cheapest fuel first.
func _refuel(station: Crafting.Station) -> bool:
	for id: StringName in [&"coal", &"charcoal", &"raw_coal", &"wood_planks", &"wood_log"]:
		if player.inventory.count_of(id) > 0:
			player.inventory.remove(id, 1)
			station.add_fuel(id)
			return true
	return false


func on_station_finished(obj: PlacedObject, r: Crafting.Recipe) -> void:
	var overflow: Array = []
	for pair: Array in r.outputs:
		var s := Items.make(pair[0], int(pair[1]))
		if obj != null and obj.def.kind == ObjectDB.Kind.MACHINE:
			# machines hold their output until you come back for it
			if obj.store(s) > 0:
				overflow.append(s)
		elif player.inventory.add(s) > 0:
			overflow.append(s)
	_spill(overflow)
	_after_craft(r)


func _after_craft(r: Crafting.Recipe) -> void:
	quests.on_crafted(r.result_id(), r.result_count())
	bump_stat("items_crafted", r.result_count())
	notify("Made %s." % r.display_name(), &"craft")


func _spill(stacks: Array) -> void:
	for s in stacks:
		ItemDrop.spawn(drops_root, world,
			player.global_position + Vector3(0, 1.0, 0), s)


# =============================================================================
# objects
# =============================================================================

func place_object(id: StringName, cell: Vector3i, who: Player) -> bool:
	var d := ObjectDB.get_def(id)
	if d == null:
		return false
	var height := maxi(1, int(ceil(d.size.y)))
	for dy in height:
		var c := cell + Vector3i(0, dy, 0)
		if world.get_block(c.x, c.y, c.z) != Blocks.AIR:
			return false
		if entity_occupies(c):
			return false
	if not world.is_solid_at(cell.x, cell.y - 1, cell.z):
		return false
	var obj := PlacedObject.create(objects_root, self, id, cell)
	if obj == null:
		return false
	notify("Placed %s." % d.display, &"info")
	quests.on_block_placed(id)
	return true


func entity_occupies(cell: Vector3i) -> bool:
	for n in objects_root.get_children():
		var o := n as PlacedObject
		if o != null and o.blocks(cell):
			return true
	return false


func object_at(cell: Vector3i) -> PlacedObject:
	for n in objects_root.get_children():
		var o := n as PlacedObject
		if o != null and o.occupies(cell):
			return o
	return null


## The nearest crafting station within arm's reach, or bare hands.
func _station_in_reach() -> Crafting.Station:
	var obj := _station_object_in_reach()
	return obj.station if obj != null else _hand_station


func _station_object_in_reach() -> PlacedObject:
	var best: PlacedObject = null
	var best_d := 4.0
	for n in objects_root.get_children():
		var o := n as PlacedObject
		if o == null or o.station == null:
			continue
		var d := o.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


func quick_deposit(container: PlacedObject) -> void:
	if container == null:
		return
	var moved := 0
	for i in Inventory.ARMOR_START:
		var s := player.inventory.get_slot(i)
		if s.is_empty():
			continue
		var wanted := false
		for held: Items.Stack in container.storage:
			if not held.is_empty() and held.id == s.id:
				wanted = true
				break
		if not wanted:
			continue
		var before := s.count
		container.store(s)
		moved += before - s.count
	player.inventory.changed.emit()
	if moved > 0:
		notify("Stowed %d." % moved, &"info")


# =============================================================================
# interaction
# =============================================================================

func player_interact(who: Player) -> void:
	# A creature within arm's reach comes before anything else: walking up to an
	# animal and pressing the interact key is never ambiguous.
	if _try_creature(who):
		return
	# NPCs next: they are what you usually mean
	var npc := _nearest(npcs_root, who.global_position, 3.2) as Npc
	if npc != null:
		ui.open_dialogue(npc)
		quests.on_talked(npc.role.id)
		return
	var obj := _nearest(objects_root, who.global_position, 3.4) as PlacedObject
	if obj == null and who.aim_hit.get("hit", false):
		obj = object_at(who.aim_hit["block"])
	if obj == null:
		return
	match obj.def.kind:
		ObjectDB.Kind.CONTAINER:
			ui.open_container(obj)
		ObjectDB.Kind.STATION, ObjectDB.Kind.MACHINE:
			if obj.def.station == &"tech":
				ui.open(&"tech")
			else:
				ui.open_crafting(obj.station, obj)
		ObjectDB.Kind.DOOR:
			obj.interact(who)
		ObjectDB.Kind.FURNITURE:
			if obj.def.has_tag(&"sleep"):
				_sleep()
			else:
				obj.interact(who)
		ObjectDB.Kind.UTILITY:
			_use_utility(obj)
		_:
			obj.interact(who)


# =============================================================================
# creatures
# =============================================================================

## The nearest creature you could plausibly be reaching for. An unconscious one
## wins ties, because you are almost certainly there to feed it.
func creature_in_reach(who: Player, radius := 4.0) -> Monster:
	var best: Monster = null
	var best_score := -1.0
	for n in monsters_root.get_children():
		var m := n as Monster
		if m == null:
			continue
		var d := m.global_position.distance_to(who.global_position)
		if d > radius:
			continue
		var score := radius - d
		if m.unconscious:
			score += 10.0
		elif m.tamed:
			score += 5.0
		if score > best_score:
			best_score = score
			best = m
	return best


## Everything the interact key does to an animal, in the order somebody walking
## up to one would expect.
func _try_creature(who: Player) -> bool:
	var m := creature_in_reach(who)
	if m == null:
		return false
	var stack := who.held_stack()

	# --- empty hands on a creature you have a stake in: open its sheet
	if stack.is_empty():
		if m.tamed or m.unconscious:
			ui.open_creature(m)
			return true
		return false

	var t := stack.type()
	if t == null:
		return false

	# --- restraints, before anything else. A held creature is a tameable one.
	if t.has_tag(&"restraint"):
		return _use_restraint(who, stack, m)

	# --- husbandry, on a creature already yours
	if t.has_tag(&"taming") and (stack.id == &"handlers_collar"
			or stack.id == &"saddlebag"):
		return _use_husbandry(who, stack, m)

	# --- the sedative chemistry
	if stack.id == &"stimulant" and m.unconscious:
		m.apply_torpor(t.torpor)     # negative: it wakes up
		_spend_held(who, stack)
		notify("%s comes awake." % m.nickname(), &"info")
		return true

	# --- feeding a sleeping creature: narcotics and food both go in the mouth
	if m.unconscious:
		var res := m.feed_unconscious(stack.id)
		if not res.get("ok", false):
			_explain_refusal(m, res)
			return true
		_spend_held(who, stack)
		bump_stat("creatures_fed", 1)
		if res.get("narcotic", false):
			notify("%s sinks deeper. Torpor %d." % [m.species.display,
				int(m.torpor)], &"info")
		elif res.get("done", false):
			bump_stat("creatures_tamed", 1)
		else:
			notify("%s eats. %d%% of the way, %d%% effective." % [
				m.species.display, int(m.tame_progress() * 100.0),
				int(m.tame_effectiveness * 100.0)], &"info")
		return true

	# --- an animal already yours: this is maintenance, not taming
	if m.tamed:
		if m.tend(stack.id):
			_spend_held(who, stack)
			bump_stat("creatures_fed", 1)
			notify("%s eats from your hand." % m.nickname(), &"info")
			return true
		notify("%s has no interest in that." % m.nickname(), &"warn")
		return true

	# --- and finally the passive attempt
	var report := m.try_tame(stack.id, who.handling_skill())
	if not report.get("ok", false):
		_explain_refusal(m, report)
		return true
	_spend_held(who, stack)
	bump_stat("creatures_fed", 1)
	if report.get("tamed", false):
		bump_stat("creatures_tamed", 1)
	elif report.get("revenge", false):
		notify("The %s takes the food and turns on you." % m.species.display,
			&"warn")
	else:
		notify("The %s eats, and backs off. (%d%% chance)" % [m.species.display,
			int(float(report.get("chance", 0.0)) * 100.0)], &"info")
	return true


## Turn a refusal dictionary into one sentence the player can act on. This is
## the whole interface to the condition system, so it has to be specific.
func _explain_refusal(m: Monster, res: Dictionary) -> void:
	var line: String = String(res.get("reason", "It refuses."))
	var wants: StringName = res.get("wants", &"")
	if wants != &"":
		var wt := Items.get_type(wants)
		if wt != null:
			line += " It wants %s." % wt.display
	var method: StringName = res.get("method", &"")
	if method == TameDB.METHOD_KNOCKOUT or method == TameDB.METHOD_REPAIR:
		line += " Put it under first."
	elif method == TameDB.METHOD_TRAP:
		line += " Box it in first."
	notify("%s %s" % [m.species.display + ":", line], &"warn")


func _use_restraint(who: Player, stack: Items.Stack, m: Monster) -> bool:
	if m.tamed:
		notify("%s is already yours." % m.nickname(), &"warn")
		return true
	# A net counts as walls; a bola counts as legs that no longer work. Both
	# express themselves the same way: the creature stops going anywhere, and
	# for as long as that holds it satisfies "boxed in".
	var seconds := 12.0 if stack.id == &"bola" else 30.0
	m.restrained = maxf(m.restrained, seconds)
	m.apply_torpor(m.torpor_max * (0.35 if stack.id == &"capture_net" else 0.2))
	m.velocity = Vector3.ZERO
	_spend_held(who, stack)
	notify("The %s is tangled — %ds." % [m.species.display, int(seconds)], &"quest")
	return true


func _use_husbandry(who: Player, stack: Items.Stack, m: Monster) -> bool:
	if not m.tamed:
		notify("%s is not yours to fit that to." % m.species.display, &"warn")
		return true
	if stack.id == &"saddlebag":
		m.carry_capacity += 8
		m._ensure_inventory()
		_spend_held(who, stack)
		notify("%s can carry %d now." % [m.nickname(), m.carry_capacity], &"info")
		return true
	# The collar is the teaching aid: one use, one training attempt, cheapest
	# skill first so that obedience always comes before anything built on it.
	for skill: StringName in [&"obedience", &"haul", &"release"]:
		if not m.can_be_trained(skill):
			continue
		_spend_held(who, stack)
		if m.train(skill):
			who.gain_handling(2.0)
		else:
			notify("%s does not take the lesson." % m.nickname(), &"warn")
		return true
	notify("%s has nothing left to learn from you." % m.nickname(), &"info")
	return true


func _spend_held(who: Player, stack: Items.Stack) -> void:
	stack.count -= 1
	if stack.count <= 0:
		stack.clear()
	who.inventory.changed.emit()


func on_monster_tamed(m: Monster) -> void:
	quests.on_tamed(m.species.id)
	notify("Handling %d." % player.handling_skill(), &"info")


## Scatter one stack where a creature stood. Used when a tame dies or reverts.
func drop_item(id: StringName, count: int, at: Vector3) -> void:
	ItemDrop.spawn(drops_root, world, at, Items.make(id, count))


## Every creature currently yours, for the HUD and the journal.
func tamed_creatures() -> Array[Monster]:
	var out: Array[Monster] = []
	for n in monsters_root.get_children():
		var m := n as Monster
		if m != null and m.tamed:
			out.append(m)
	return out


func _use_utility(obj: PlacedObject) -> void:
	if obj.def.has_tag(&"heal"):
		player.heal(player.effective_max_health())
		if player.stats != null:
			player.stats.apply_effect(&"regeneration", 30.0)
		notify("Patched up.", &"info")
	elif obj.def.has_tag(&"teleport"):
		player.set_spawn(obj.global_position)
		notify("Teleporter bound. You will respawn here.", &"info")
	elif obj.def.has_tag(&"waypoint"):
		notify("Waypoint set.", &"info")
	elif obj.def.has_tag(&"summon"):
		_summon_boss(obj.global_position)
	else:
		obj.interact(player)


## Sleeping through the night is the reward for building a shelter.
func _sleep() -> void:
	if not sky.is_night():
		notify("It is not night yet.", &"warn")
		return
	sky.fraction = 0.26
	sky.day += 1
	player.heal(player.effective_max_health() * 0.5)
	if player.stats != null:
		player.stats.apply_effect(&"rested", 240.0)
	notify("You sleep until dawn.", &"info")


# =============================================================================
# combat
# =============================================================================

func player_attack(who: Player, stack: Items.Stack) -> void:
	var t := stack.type()
	var damage := 6.0
	var element: StringName = Blocks.ELEM_PHYSICAL
	var knock := 6.0
	var projectile: StringName = &""
	var energy := 0.0
	var torpor := 0.0
	if t != null:
		torpor = t.torpor
		damage = maxf(float(stack.stat("damage", 0.0)), t.damage)
		element = StringName(stack.stat("element", String(t.element)))
		knock = float(stack.stat("knockback", t.knockback))
		projectile = StringName(stack.stat("projectile", String(t.projectile)))
		energy = float(stack.stat("energy_cost", t.energy_cost))
		if damage <= 0.0:
			damage = 4.0 + float(t.tool_tier) * 2.0
	if who.stats != null:
		damage *= who.stats.damage_multiplier()
	damage *= 1.0 + who.inventory.bonus("damage_bonus")

	var origin := who.global_position + Vector3(0, 1.0, 0)
	var aim := _aim_direction(who)

	# --- ranged
	if projectile != &"":
		if energy > 0.0 and not who.spend_energy(energy):
			notify("Out of energy.", &"warn")
			return
		var sedative: bool = t != null and t.has_tag(&"tranquiliser")
		if t != null and (t.has_tag(&"bow") or sedative):
			var round_id := _spend_arrow(who, sedative)
			if round_id == &"":
				notify("Out of ammunition.", &"warn")
				return
			# The dart carries most of the dose; the weapon only delivers it.
			var round_type := Items.get_type(round_id)
			if round_type != null:
				torpor += round_type.torpor
				damage += round_type.torpor * 0.06
		var pellets := 7 if (t != null and t.has_tag(&"shotgun")) else 1
		for i in pellets:
			var spread := Vector3(_rng.randf_range(-0.08, 0.08),
				_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.08, 0.08))
			spawn_projectile(projectile, origin,
				(aim + spread * (0.0 if pellets == 1 else 1.0)).normalized(),
				damage, element, who, torpor / float(pellets))
		bump_stat("shots_fired", pellets)
		return

	# --- melee: a cone in front of the billboard
	var pierce := t != null and t.has_tag(&"cutaway_pierce")
	var occluded_only := t != null and t.has_tag(&"cutaway_occluded")
	var reach := 2.9
	if t != null and (t.has_tag(&"spear") or t.has_tag(&"whip")):
		reach = 4.4
	var hits := 0
	for n in monsters_root.get_children():
		var m := n as Monster
		if m == null:
			continue
		var to: Vector3 = m.global_position + Vector3(0, m.species.size.y * 0.5, 0) - origin
		if to.length() > reach + m.species.size.x * 0.5:
			continue
		if to.normalized().dot(aim) < 0.15 and to.length() > 1.3:
			continue
		# the two cutaway weapons ask the cut predicate, not the terrain
		var inside := _inside_cut(m.global_position)
		if occluded_only and not inside:
			continue
		if not pierce and not occluded_only and not _line_of_sight(origin, m.global_position):
			continue
		var rolled := Combat.roll_damage(damage,
			who.inventory.bonus("crit_chance"), _rng)
		m.hurt(float(rolled[0]), element, to.normalized() * knock + Vector3.UP * 3.0, who)
		if torpor > 0.0:
			m.apply_torpor(torpor)
		on_element_applied(m, element)
		hud.pop_damage(m.global_position + Vector3(0, m.species.size.y, 0),
			float(rolled[0]), element, bool(rolled[1]))
		hits += 1
	if hits > 0:
		bump_stat("hits_landed", hits)
		_wear_weapon(who, stack)
	elif occluded_only:
		notify("Nothing in the cross-section.", &"warn")


func _aim_direction(who: Player) -> Vector3:
	if who.aim_hit.get("hit", false):
		var target: Vector3 = Vector3(who.aim_hit["block"]) + Vector3(0.5, 0.5, 0.5)
		var d := target - (who.global_position + Vector3(0, 1.0, 0))
		if d.length() > 0.1:
			return d.normalized()
	return (Vector3(who.rig.lateral()) * who.facing_sign).normalized()


## Pull one round from the bag and report what it was worth. A tranquiliser
## weapon looks for sedative ammunition first, because that is unambiguously
## what somebody holding a tranquiliser rifle meant to load.
func _spend_arrow(who: Player, sedative := false) -> StringName:
	var order: Array[StringName] = [&"bolt", &"iron_arrow", &"arrow"]
	if sedative:
		order = [&"shock_dart", &"tranq_dart", &"tranq_arrow", &"bolt",
			&"iron_arrow", &"arrow"]
	for id: StringName in order:
		if who.inventory.count_of(id) > 0:
			who.inventory.remove(id, 1)
			return id
	return &""


func _wear_weapon(who: Player, stack: Items.Stack) -> void:
	var t := stack.type()
	if t == null or t.durability <= 0:
		return
	if stack.damage_durability(1):
		notify("Your weapon broke.", &"warn")
		who.inventory.changed.emit()


func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	var d := to + Vector3(0, 0.5, 0) - from
	var hit := world.raycast(from, d.normalized(), d.length(), true)
	return not hit.get("hit", false)


func _inside_cut(pos: Vector3) -> bool:
	return world.cutaway.is_cut(int(floor(pos.x)), int(floor(pos.y + 0.5)),
		int(floor(pos.z)))


func spawn_projectile(kind: StringName, from: Vector3, dir: Vector3,
		damage: float, element: StringName, source: Node, torpor := 0.0) -> void:
	Projectile.fire(shots_root, world, self, kind, from, dir, damage, element,
		source, source != player, torpor)


func on_element_applied(m: Monster, element: StringName) -> void:
	var eff: Variant = Combat.ELEMENT_EFFECTS.get(element)
	if eff == null or m == null:
		return
	# monsters do not carry a status holder; the element expresses itself as a
	# short burst of extra damage instead, which keeps the actor small
	m.hurt(float(eff[1]) * 0.4, element)


func on_monster_damaged(m: Monster, amount: float, element: StringName,
		source: Node) -> void:
	if source == player:
		hud.pop_damage(m.global_position + Vector3(0, m.species.size.y, 0),
			amount, element, false)


func on_monster_hit_player(_m: Monster, _damage: float) -> void:
	hud.flash_hurt()


func on_player_damaged(_amount: float, _element: StringName) -> void:
	hud.flash_hurt()


func on_monster_died(m: Monster, source: Node) -> void:
	var luck := 0.0
	if player.stats != null and player.stats.has_effect(&"lucky"):
		luck = 0.2
	for pair: Array in m.species.roll_drops(_rng, luck):
		ItemDrop.spawn(drops_root, world,
			m.global_position + Vector3(0, 0.4, 0),
			Items.make(pair[0], int(pair[1])))
	# a fair chance of a generated weapon from anything dangerous
	if m.species.threat >= 2 and _rng.randf() < 0.06 + float(m.species.threat) * 0.02:
		ItemDrop.spawn(drops_root, world, m.global_position + Vector3(0, 0.5, 0),
			Combat.generate_weapon(m.species.threat, _rng))
	if source == player:
		quests.on_kill(m.species.id)
		bump_stat("kills", 1)
		if m.is_boss():
			notify("%s falls." % m.display_name(), &"quest")
	_prune_drops()


func try_air_tech(who: Player) -> bool:
	return tech.air_tech(who)


func on_tech_used(_id: StringName) -> void:
	bump_stat("techs_used", 1)


## The Fold tech: pin the cutaway to where you are aiming instead of to
## yourself, so the world opens up somewhere you are not.
func fold_cutaway() -> void:
	if not player.aim_hit.get("hit", false):
		notify("Aim at something first.", &"warn")
		return
	var at: Vector3 = Vector3(player.aim_hit["block"]) + Vector3(0.5, 0.5, 0.5)
	world.update_cutaway(rig.camera.global_position, at)
	notify("Cutaway folded.", &"info")


func survey_pulse(centre: Vector3, radius: float) -> void:
	var found := 0
	var r := int(radius)
	var c := Vector3i(int(centre.x), int(centre.y), int(centre.z))
	for dx in range(-r, r + 1, 2):
		for dy in range(-r / 2, r / 2 + 1, 2):
			for dz in range(-r, r + 1, 2):
				var cell := c + Vector3i(dx, dy, dz)
				if Blocks.get_def(world.get_block(cell.x, cell.y, cell.z)).tags.has(&"ore"):
					found += 1
	notify("Survey: %d ore signatures within %d blocks." % [found, r], &"info")


func spawn_impact(at: Vector3, col: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	mat.color = col
	p.process_material = mat
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.12)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = col
	mesh.material = mm
	p.draw_pass_1 = mesh
	shots_root.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


# =============================================================================
# population
# =============================================================================

func _tick_population() -> void:
	if not world.gen.hostiles:
		return
	if monsters_root.get_child_count() < MAX_MONSTERS:
		_spawn_monster_near_player()
	for n in monsters_root.get_children():
		var m := n as Monster
		if m != null and m.global_position.distance_to(player.global_position) > 70.0:
			m.queue_free()
	_populate_structures()


## Stock the area around the player. Cave-dwellers only appear underground and
## surface creatures only above it, and anything currently asleep is much less
## likely to be placed — a nocturnal roster genuinely thins out by day.
func _spawn_monster_near_player() -> void:
	var underground := _player_is_underground()
	var pool := SpeciesDB.pool_for(world.gen.biome, world.gen.threat + 1)
	var eligible: Array[SpeciesDB.Def] = []
	for d: SpeciesDB.Def in pool:
		if bool(d.flags.get(&"underground", false)) != underground:
			continue
		eligible.append(d)
	if eligible.is_empty():
		return

	var night: bool = sky.is_night()
	for attempt in 24:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(11.0, 26.0)
		var x := int(floor(player.global_position.x + cos(a) * r))
		var z := int(floor(player.global_position.z + sin(a) * r))
		if not world.is_loaded(x, z):
			continue
		var spot := _spawn_spot(x, z, underground)
		if spot.y < 0:
			continue
		var def: SpeciesDB.Def = eligible[_rng.randi() % eligible.size()]
		if not def.is_awake(night) and _rng.randf() < 0.75:
			continue
		if not night and def.threat >= 3 and _rng.randf() < 0.6:
			continue
		var count := _rng.randi_range(def.pack_min, def.pack_max)
		for i in count:
			var at := Vector3(spot) + Vector3(0.5 + float(i) * 0.8, 0.1, 0.5)
			spawn_monster(def.id, at, 1.0 + float(world.gen.threat) * 0.22)
		return


func _player_is_underground() -> bool:
	var feet := player.feet_block()
	return world.column_top(feet.x, feet.z) > feet.y + 2


## A cell with floor under it and headroom above, on the surface or in a cave.
func _spawn_spot(x: int, z: int, underground: bool) -> Vector3i:
	if not underground:
		var top := world.column_top(x, z)
		if top < 4 or top >= VoxelWorld.WH - 3:
			return Vector3i(x, -1, z)
		if world.is_solid_at(x, top + 1, z) or world.is_solid_at(x, top + 2, z):
			return Vector3i(x, -1, z)
		return Vector3i(x, top + 1, z)
	var floor_y := player.feet_block().y
	for dy: int in [0, -2, 2, -4, 4, -6, 6]:
		var y := floor_y + dy
		if y < 2 or y >= VoxelWorld.WH - 2:
			continue
		if not world.is_solid_at(x, y - 1, z):
			continue
		if world.is_solid_at(x, y, z) or world.is_solid_at(x, y + 1, z):
			continue
		return Vector3i(x, y, z)
	return Vector3i(x, -1, z)


func spawn_monster(id: StringName, at: Vector3, threat := 1.0) -> Monster:
	if monsters_root.get_child_count() >= MAX_MONSTERS + 8:
		return null
	return Monster.spawn(monsters_root, world, player, self, id, at, threat)


func _summon_boss(at: Vector3) -> void:
	var pool := SpeciesDB.bosses()
	if pool.is_empty():
		return
	var b: SpeciesDB.Def = pool[_rng.randi() % pool.size()]
	spawn_monster(b.id, at + Vector3(0, 2.0, 0), 1.0 + float(world.gen.threat) * 0.3)
	notify("%s answers." % b.display, &"warn")


## Fill in the entities that structures asked for once their chunks are live.
func _populate_structures() -> void:
	if world.pending_structures.is_empty():
		return
	var still: Array = []
	for spec: Dictionary in world.pending_structures:
		var at: Vector3i = spec["at"]
		if not world.is_loaded(at.x, at.z):
			still.append(spec)
			continue
		match StringName(spec["kind"]):
			&"village": _populate_village(spec)
			&"camp": _populate_camp(spec)
			&"ruin": _populate_ruin(spec)
			&"mineshaft": _populate_mineshaft(spec)
	world.pending_structures = still


func _populate_village(spec: Dictionary) -> void:
	var at: Vector3i = spec["at"]
	var roster := NpcRoles.village_roster(int(spec.get("count", 4)), _rng)
	for i in roster.size():
		var p := Vector3(at) + Vector3(float(i) * 2.4 - 3.0, 0.2, _rng.randf_range(-1.5, 1.5))
		Npc.spawn(npcs_root, world, player, self, roster[i], p, _rng)
	PlacedObject.create(objects_root, self, &"chest", at + Vector3i(0, 0, 2))


func _populate_camp(spec: Dictionary) -> void:
	var at: Vector3i = spec["at"]
	var pool := SpeciesDB.pool_for(world.gen.biome, world.gen.threat + 2)
	if pool.is_empty():
		return
	for i in int(spec.get("count", 3)):
		var def: SpeciesDB.Def = pool[_rng.randi() % pool.size()]
		spawn_monster(def.id, Vector3(at) + Vector3(_rng.randf_range(-3, 3), 0.4,
			_rng.randf_range(-3, 3)), 1.1 + float(world.gen.threat) * 0.25)


func _populate_ruin(spec: Dictionary) -> void:
	var at: Vector3i = spec["at"]
	var chest := PlacedObject.create(objects_root, self, &"safe", at)
	if chest != null:
		for i in _rng.randi_range(2, 4):
			chest.store(_ruin_loot())
	# and something guarding it
	spawn_monster(&"scandroid" if _rng.randf() < 0.5 else &"ixoling",
		Vector3(at) + Vector3(2.0, 0.4, 0.0), 1.2)


func _ruin_loot() -> Items.Stack:
	var roll := _rng.randf()
	if roll < 0.25:
		return Combat.generate_weapon(2 + world.gen.threat, _rng)
	var pool: Array[StringName] = [&"ancient_fragment", &"gold_bar", &"diamond",
		&"amber_shard", &"circuit_board", &"ancient_artifact", &"pixels"]
	var id: StringName = pool[_rng.randi() % pool.size()]
	return Items.make(id, _rng.randi_range(1, 60 if id == &"pixels" else 4))


func _populate_mineshaft(spec: Dictionary) -> void:
	var at: Vector3i = spec["at"]
	var chest := PlacedObject.create(objects_root, self, &"chest", at)
	if chest != null:
		chest.store(Items.make(&"iron_bar", _rng.randi_range(2, 6)))
		chest.store(Items.make(&"torch", _rng.randi_range(4, 12)))
		chest.store(Items.make(&"bread", _rng.randi_range(1, 3)))


func _prune_drops() -> void:
	var kids := drops_root.get_child_count()
	if kids <= MAX_DROPS:
		return
	for i in kids - MAX_DROPS:
		drops_root.get_child(i).queue_free()


func _nearest(root: Node3D, from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for n in root.get_children():
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d := n3.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n3
	return best


# =============================================================================
# NPC services
# =============================================================================

func buy_from(npc: Npc, stack: Items.Stack, price: int) -> void:
	if player.inventory.pixels < price:
		notify("Not enough pixels.", &"warn")
		return
	var one := stack.split(1)
	if player.inventory.add(one) > 0:
		stack.merge_from(one)
		notify("No room.", &"warn")
		return
	player.inventory.pixels -= price
	npc.reputation += 1
	bump_stat("items_bought", 1)
	player.inventory.changed.emit()


func sell_to(npc: Npc, stack: Items.Stack, price: int) -> void:
	if stack.is_empty():
		return
	var one := stack.split(1)
	player.inventory.pixels += price
	npc.reputation += 1
	npc.stock.append(one)
	bump_stat("items_sold", 1)
	player.inventory.changed.emit()


func npc_heal(npc: Npc) -> void:
	if player.inventory.pixels < 40:
		notify("Not enough pixels.", &"warn")
		return
	player.inventory.pixels -= 40
	player.heal(player.effective_max_health())
	if player.stats != null:
		player.stats.apply_effect(&"cure_all", 1.0)
		player.stats.reset_needs()
	npc.reputation += 1
	notify("Patched up, fed and watered.", &"info")


func npc_repair(npc: Npc) -> void:
	if player.inventory.pixels < 60:
		notify("Not enough pixels.", &"warn")
		return
	var repaired := 0
	for i in Inventory.TOTAL:
		var s := player.inventory.get_slot(i)
		var t := s.type()
		if t == null or t.durability <= 0:
			continue
		if s.durability() < t.durability:
			s.data["durability"] = t.durability
			repaired += 1
	if repaired == 0:
		notify("Nothing needs mending.", &"warn")
		return
	player.inventory.pixels -= 60
	npc.reputation += 1
	player.inventory.changed.emit()
	notify("Repaired %d item%s." % [repaired, "" if repaired == 1 else "s"], &"info")


func npc_offer_quest(npc: Npc) -> void:
	var offers := Quests.offers_from(npc.role.id, _active_ids(), quests.completed)
	if offers.is_empty():
		notify("\"Nothing right now.\"", &"info")
		return
	var q: Quests.Quest = offers[_rng.randi() % offers.size()]
	quests.start(q.id)
	npc.quest_id = q.id
	notify("New quest: %s." % q.title, &"quest")


func _active_ids() -> Dictionary:
	var out := {}
	for q: Quests.Quest in quests.active:
		out[q.id] = true
	return out


func grant_quest_rewards(q: Quests.Quest) -> void:
	player.inventory.pixels += q.reward_pixels
	var overflow: Array = []
	for pair: Array in q.reward_items:
		var s := Items.make(pair[0], int(pair[1]))
		if player.inventory.add(s) > 0:
			overflow.append(s)
	_spill(overflow)
	for rid in q.reward_recipes:
		known_recipes[rid] = true
	bump_stat("quests_done", 1)
	notify("Quest complete: %s." % q.title, &"quest")


# =============================================================================
# travel
# =============================================================================

func travel_to(planet_id: String) -> void:
	var p := universe.get_planet(planet_id)
	if p == null or planet_id == current_planet_id:
		return
	if ship_fuel < p.fuel_cost:
		notify("Not enough fuel.", &"warn")
		return
	ship_fuel -= p.fuel_cost
	_travel_target = planet_id
	input_locked = true
	hud.set_loading(0, 1)
	for root in [monsters_root, drops_root, npcs_root, shots_root, objects_root]:
		for n in root.get_children():
			n.queue_free()
	world.load_planet(p.world_config())
	sky.configure(p.world_config())
	world.focus_on(Vector3.ZERO)
	notify("Breaking orbit for %s." % p.display, &"quest")


func _finish_travel() -> void:
	if _travel_target == "":
		return
	var p := universe.get_planet(_travel_target)
	_travel_target = ""
	current_planet_id = p.id
	p.visited = true
	universe.discover(p.id)
	universe.scan_system(p.system)
	var spawn := world.find_spawn()
	var top := world.column_top(spawn.x, spawn.z)
	# The column top is authoritative — spawn.y is only a fallback for a world
	# that streamed in empty, and landing on it means a fatal drop.
	var y := (float(top) + 1.05) if top >= 0 else float(spawn.y)
	var at := Vector3(spawn.x + 0.5, y, spawn.z + 0.5)
	player.teleport(at)
	player.velocity = Vector3.ZERO
	player.health = maxf(player.health, 1.0)
	rig.global_position = at + Vector3(0, rig.height_offset, 0)
	input_locked = false
	hud.finish_loading()
	quests.on_visited(p.biome)
	quests.on_visited(&"new_system")
	_deepest = 999
	notify("Landed on %s. %s, %s." % [p.display, p.type_name, p.threat_name()],
		&"quest")
	for i in 5:
		_spawn_monster_near_player()


# =============================================================================
# feedback and stats
# =============================================================================

func notify(text: String, kind: StringName = &"info") -> void:
	if hud != null:
		hud.notify(text, kind)


func bump_stat(key: String, amount: int) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


# =============================================================================
# persistence
# =============================================================================

func save_game() -> void:
	var objs: Array = []
	for n in objects_root.get_children():
		var o := n as PlacedObject
		if o != null:
			objs.append(o.save_state())
	var data := {
		"version": 2,
		"seed": run_seed,
		"planet": current_planet_id,
		"fuel": ship_fuel,
		"player": player.save_state(),
		"quests": quests.save_state(),
		"tech": tech.save_state(),
		"universe": universe.save_state(),
		"sky": sky.save_state(),
		"cutaway": world.cutaway.save_state(),
		"liquids": liquids.save_state(),
		"recipes": known_recipes.keys(),
		"objects": objs,
		"stats": stats,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write the save file.")
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed

	ship_fuel = int(data.get("fuel", 4))
	stats = data.get("stats", {})
	known_recipes.clear()
	for id in data.get("recipes", []):
		known_recipes[String(id)] = true
	universe.load_state(data.get("universe", {}))
	quests.load_state(data.get("quests", {}))
	tech.load_state(data.get("tech", {}))
	sky.load_state(data.get("sky", {}))
	world.cutaway.load_state(data.get("cutaway", {}))
	world.set_cutaway_mode(world.cutaway.mode)
	liquids.load_state(data.get("liquids", {}))

	var planet_id := String(data.get("planet", current_planet_id))
	var p := universe.get_planet(planet_id)
	if p != null and planet_id != current_planet_id:
		current_planet_id = planet_id
		world.load_planet(p.world_config())
		sky.configure(p.world_config())

	for spec in data.get("objects", []):
		var cell: Array = spec.get("cell", [0, 0, 0])
		var o := PlacedObject.create(objects_root, self, StringName(spec["id"]),
			Vector3i(int(cell[0]), int(cell[1]), int(cell[2])))
		if o != null:
			o.load_state(spec)

	player.load_state(data.get("player", {}))
	world.focus_on(player.global_position)
	notify("Loaded.", &"info")
	return true


# =============================================================================
# scene furniture
# =============================================================================

static func _make_wire_box() -> ArrayMesh:
	var s := 0.504
	var c := [
		Vector3(-s, -s, -s), Vector3(s, -s, -s), Vector3(s, -s, s), Vector3(-s, -s, s),
		Vector3(-s, s, -s), Vector3(s, s, -s), Vector3(s, s, s), Vector3(-s, s, s),
	]
	var pairs := [
		0, 1, 1, 2, 2, 3, 3, 0,
		4, 5, 5, 6, 6, 7, 7, 4,
		0, 4, 1, 5, 2, 6, 3, 7,
	]
	var verts := PackedVector3Array()
	for i in pairs:
		verts.append(c[i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	mesh.surface_set_material(0, mat)
	return mesh


# =============================================================================
# input map, built at runtime so the project has no fragile serialised bindings
# =============================================================================

static func _bind(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.4)
	for e in events:
		InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mb(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _setup_input() -> void:
	_bind(&"move_left", [_key(KEY_A), _key(KEY_LEFT)])
	_bind(&"move_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_bind(&"move_forward", [_key(KEY_W), _key(KEY_UP)])
	_bind(&"move_back", [_key(KEY_S), _key(KEY_DOWN)])
	_bind(&"jump", [_key(KEY_SPACE)])
	_bind(&"crouch", [_key(KEY_CTRL), _key(KEY_C)])
	_bind(&"sprint", [_key(KEY_SHIFT)])
	_bind(&"rotate_ccw", [_key(KEY_Q)])
	_bind(&"rotate_cw", [_key(KEY_E)])
	_bind(&"mine", [_mb(MOUSE_BUTTON_LEFT)])
	_bind(&"place", [_mb(MOUSE_BUTTON_RIGHT)])
	_bind(&"attack", [_key(KEY_F)])
	_bind(&"interact", [_key(KEY_R)])
	_bind(&"tech", [_key(KEY_G)])
	_bind(&"drop_item", [_key(KEY_X)])
	_bind(&"inventory", [_key(KEY_I), _key(KEY_TAB)])
	_bind(&"crafting", [_key(KEY_K)])
	_bind(&"quest_log", [_key(KEY_J)])
	_bind(&"star_map", [_key(KEY_M)])
	_bind(&"tech_panel", [_key(KEY_T)])
	_bind(&"quick_save", [_key(KEY_F5)])
	_bind(&"toggle_help", [_key(KEY_F1)])
	_bind(&"toggle_cutaway", [_key(KEY_V)])
	_bind(&"cutaway_mode", [_key(KEY_B)])
	_bind(&"cutaway_opacity", [_key(KEY_N)])
	_bind(&"cutaway_select", [_key(KEY_H)])
	_bind(&"respawn", [_key(KEY_ENTER)])
	_bind(&"cancel", [_key(KEY_ESCAPE)])
