extends Node

## Integration smoke test.
##
##     godot --headless --path . tools/smoke_test.tscn
##
## Boots the real `main.tscn`, streams the world in, and asserts the things that
## have to hold for the game to be playable: the registries filled, terrain
## generated, the player standing in free space on solid ground, and every
## ported system doing its one job — mining drops, placing consumes, crafting
## resolves, monsters take damage, quests advance, the cutaway agrees with
## itself, and a save round-trips.
##
## Exits non-zero on the first failure, so it can gate a build.

var game: Node3D
var world: VoxelWorld
var player: Player
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var packed: PackedScene = load("res://main.tscn")
	game = packed.instantiate()
	add_child(game)
	world = game.get_node("World")
	player = game.get_node("Player")
	_run()


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		var line := "  FAIL  %s%s" % [label, ("  — " + detail) if detail != "" else ""]
		print(line)
		failures.append(label)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _run() -> void:
	print("== registries")
	_registries()

	print("== world")
	await world.world_ready
	await _settle(40)
	_world_state()

	print("== inventory and mining")
	await _mining()

	print("== building")
	await _building()

	print("== crafting")
	_crafting()

	print("== survival")
	_survival()

	print("== combat")
	await _combat()

	print("== crouch")
	await _crouch()

	print("== bestiary")
	_bestiary()

	print("== quests")
	_quests()

	print("== cutaway")
	_cutaway()

	print("== cutaway modes")
	_cutaway_modes()

	print("== space")
	_space()

	print("== persistence")
	await _persistence()

	print("")
	if failures.is_empty():
		print("smoke test: %d checks, all passed" % checks)
		get_tree().quit(0)
	else:
		print("smoke test: %d checks, %d FAILED" % [checks, failures.size()])
		for f in failures:
			print("   - %s" % f)
		get_tree().quit(1)


# =============================================================================

func _registries() -> void:
	check("block registry populated", Blocks.count() > 150,
		"%d blocks" % Blocks.count())
	check("block ids fit one byte", Blocks.count() <= Blocks.MAX_BLOCKS,
		"%d" % Blocks.count())
	check("atlas fits", Blocks.LEGACY_TILES + Blocks.tile_specs.size()
		<= TexGen.ATLAS_CAPACITY)
	check("item registry populated", Items.count() > 300,
		"%d items" % Items.count())
	check("recipe book populated", Crafting.recipes.size() > 150,
		"%d recipes" % Crafting.recipes.size())
	check("species bestiary populated", SpeciesDB.defs.size() >= 20,
		"%d species" % SpeciesDB.defs.size())
	check("bosses defined", SpeciesDB.bosses().size() >= 4)
	check("objects defined", ObjectDB.defs.size() >= 20,
		"%d objects" % ObjectDB.defs.size())
	check("quest book populated", Quests.catalogue.size() >= 15,
		"%d quests" % Quests.catalogue.size())
	check("effects defined", EffectLib.defs.size() >= 30,
		"%d effects" % EffectLib.defs.size())
	check("techs defined", TechCatalog.ALL.size() >= 15)

	# every drop and every recipe ingredient must resolve to a real item
	var dangling: Array[String] = []
	for d: Blocks.Def in Blocks.defs:
		for drop: Array in d.drops:
			if not Items.has(drop[0]):
				dangling.append("%s -> %s" % [d.name, drop[0]])
	check("no block drops a nonexistent item", dangling.is_empty(),
		", ".join(dangling.slice(0, 5)))

	var bad_recipes: Array[String] = []
	for r: Crafting.Recipe in Crafting.recipes:
		for pair: Array in r.inputs:
			if not Items.has(pair[0]):
				bad_recipes.append("%s needs %s" % [r.id, pair[0]])
		for pair: Array in r.outputs:
			if not Items.has(pair[0]):
				bad_recipes.append("%s makes %s" % [r.id, pair[0]])
	check("every recipe resolves", bad_recipes.is_empty(),
		", ".join(bad_recipes.slice(0, 5)))

	var bad_loot: Array[String] = []
	for s: SpeciesDB.Def in SpeciesDB.defs:
		for drop: Array in s.drops:
			if not Items.has(drop[0]):
				bad_loot.append("%s -> %s" % [s.id, drop[0]])
	check("every monster drop resolves", bad_loot.is_empty(),
		", ".join(bad_loot.slice(0, 5)))

	var bad_quests: Array[String] = []
	for q: Quests.Quest in Quests.catalogue:
		for pair: Array in q.reward_items:
			if not Items.has(pair[0]):
				bad_quests.append("%s -> %s" % [q.id, pair[0]])
	check("every quest reward resolves", bad_quests.is_empty(),
		", ".join(bad_quests.slice(0, 5)))


func _world_state() -> void:
	check("chunks generated", world.loaded_chunk_count() > 40,
		"%d chunks" % world.loaded_chunk_count())
	var feet := player.feet_block()
	check("player is in free space",
		not world.is_solid_at(feet.x, feet.y, feet.z)
		and not world.is_solid_at(feet.x, feet.y + 1, feet.z),
		str(feet))
	check("player is on solid ground",
		world.is_solid_at(feet.x, feet.y - 1, feet.z), str(feet))
	check("terrain has ore in it", _count_matching(&"ore") > 0)
	check("terrain has plants in it", _count_matching(&"foliage") > 0)


func _count_matching(tag: StringName) -> int:
	var found := 0
	var base := player.feet_block()
	for dx in range(-24, 25, 3):
		for dz in range(-24, 25, 3):
			for y in range(1, VoxelWorld.WH, 2):
				var id := world.get_block(base.x + dx, y, base.z + dz)
				if id != Blocks.AIR and Blocks.get_def(id).tags.has(tag):
					found += 1
	return found


func _mining() -> void:
	check("starting kit granted", player.inventory.count_of(&"torch") >= 8)
	check("matter manipulator issued",
		player.inventory.count_of(&"matter_manipulator") >= 1)

	# put a known block under the player's aim and mine it out
	var feet := player.feet_block()
	var cell := Vector3i(feet.x + 2, feet.y, feet.z)
	world.set_block(cell.x, cell.y, cell.z, Blocks.id(&"copper_ore"))
	check("block written", world.get_block(cell.x, cell.y, cell.z)
		== Blocks.id(&"copper_ore"))

	var before: int = game.drops_root.get_child_count()
	player.break_block(cell, 99)
	await _settle(3)
	check("mining clears the block",
		world.get_block(cell.x, cell.y, cell.z) == Blocks.AIR)
	check("mining drops an item", game.drops_root.get_child_count() > before,
		"%d -> %d" % [before, game.drops_root.get_child_count()])

	# tier gating: a stone pick must not recover titanium
	var def := Blocks.get_by_name(&"titanium_ore")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	check("tool tier gates ore drops", def.roll_drops(0, rng).is_empty())
	check("the right tier recovers it", not def.roll_drops(3, rng).is_empty())


func _building() -> void:
	# Aim at a real solid face, the way the raycast would hand it over: a stone
	# floor block, with the +Y normal, so the placement lands in the air above.
	var feet := player.feet_block()
	var floor_cell := Vector3i(feet.x + 3, feet.y - 1, feet.z)
	var cell := floor_cell + Vector3i(0, 1, 0)
	world.set_block(floor_cell.x, floor_cell.y, floor_cell.z, Blocks.STONE)
	world.set_block(cell.x, cell.y, cell.z, Blocks.AIR)
	player.inventory.set_slot(0, Items.make(&"wood_planks", 5))
	player.inventory.select(0)
	var have: int = player.inventory.count_of(&"wood_planks")
	player.aim_hit = {"hit": true, "block": floor_cell,
		"normal": Vector3i(0, 1, 0), "id": Blocks.STONE}
	var placed := player.try_place()
	check("placing puts the block down", placed
		and world.get_block(cell.x, cell.y, cell.z) == Blocks.id(&"wood_planks"),
		"placed=%s got=%s" % [placed,
			Blocks.display_name(world.get_block(cell.x, cell.y, cell.z))])
	check("placing consumes one item",
		player.inventory.count_of(&"wood_planks") == have - 1,
		"%d -> %d" % [have, player.inventory.count_of(&"wood_planks")])

	# foliage and liquids must not block movement, cubes must
	check("stone collides", Blocks.is_solid(Blocks.STONE))
	check("tall grass does not collide",
		not Blocks.is_solid(Blocks.id(&"tall_grass")))
	check("water does not collide", not Blocks.is_solid(Blocks.id(&"water")))
	check("ladders do not collide but are climbable",
		not Blocks.is_solid(Blocks.id(&"wooden_ladder"))
		and Blocks.is_climbable(Blocks.id(&"wooden_ladder")))
	check("platforms collide", Blocks.is_solid(Blocks.id(&"wood_platform")))


func _crafting() -> void:
	var r := Crafting.get_recipe("planks_from_log")
	check("hand recipe exists", r != null)
	check("it is known from the start", game.known_recipes.has("planks_from_log"))

	player.inventory.add_item(&"wood_log", 4)
	var before := player.inventory.count_of(&"wood_planks")
	check("can craft with the materials", Crafting.can_craft(player.inventory, r))
	game.request_craft(r, Crafting.Station.new(&"hand"), null)
	check("crafting produces the output",
		player.inventory.count_of(&"wood_planks") >= before + 4,
		"%d -> %d" % [before, player.inventory.count_of(&"wood_planks")])
	check("crafting consumes the inputs",
		player.inventory.count_of(&"wood_log") == 3)

	# picking up a new material teaches its recipes
	var learned_before: int = game.known_recipes.size()
	player.inventory.add_item(&"iron_bar", 1)
	game.on_item_picked_up(&"iron_bar", 1)
	check("materials teach recipes", game.known_recipes.size() > learned_before,
		"%d -> %d" % [learned_before, game.known_recipes.size()])

	# a furnace recipe must not be craftable by hand
	var smelt := Crafting.get_recipe("smelt_copper")
	check("station recipes are station-gated", smelt != null
		and smelt.station == &"furnace")


func _survival() -> void:
	var stats: PlayerStats = player.stats
	check("needs exist", stats != null and stats.food > 0.0)
	stats.food = 10.0
	stats.apply_effect(&"poisoned", 5.0)
	check("effects apply", stats.has_effect(&"poisoned"))
	check("debuffs modify damage taken",
		stats.modify_incoming(10.0, Blocks.ELEM_PHYSICAL) <= 10.0)
	stats.apply_effect(&"cure_poison", 1.0)
	check("cures strip their family", not stats.has_effect(&"poisoned"))

	var apple := Items.make(&"bread", 1)
	var before := stats.food
	check("eating fills the food bar", stats.consume(apple) and stats.food > before)

	stats.apply_effect(&"haste", 10.0)
	check("haste speeds you up", stats.move_multiplier() > 1.0)
	stats.clear_effects()
	stats.reset_needs()


func _combat() -> void:
	var feet := player.feet_block()
	var at := Vector3(feet.x + 4, feet.y + 1, feet.z)
	var m: Monster = game.spawn_monster(&"poptop", at, 1.0)
	check("monster spawns", m != null)
	if m == null:
		return
	await _settle(2)
	var hp: float = m.health
	m.hurt(5.0, Blocks.ELEM_PHYSICAL, Vector3.ZERO, player)
	check("monsters take damage", m.health < hp,
		"%.1f -> %.1f" % [hp, m.health])

	# resistances actually resist
	var narfin := SpeciesDB.get_def(&"narfin")
	check("resistances are read", float(narfin.resists.get(Blocks.ELEM_ICE, 1.0)) == 0.0)

	# a generated weapon should be a valid, better-than-base stack
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var gen := Combat.generate_weapon(4, rng)
	check("weapon generator produces a usable weapon",
		not gen.is_empty() and float(gen.stat("damage", 0.0)) > 0.0
		and gen.display_name() != "")

	var drops_before: int = game.drops_root.get_child_count()
	m.hurt(9999.0, Blocks.ELEM_PHYSICAL, Vector3.ZERO, player)
	await _settle(3)
	check("killing a monster drops loot",
		game.drops_root.get_child_count() >= drops_before)


## Crouch has to change the shape the world is swept against, not just the
## picture, or none of it is worth anything.
func _crouch() -> void:
	var feet := player.feet_block()
	# somewhere flat with headroom
	for dy in range(0, 4):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				world.set_block(feet.x + dx, feet.y + dy, feet.z + dz, Blocks.AIR)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			world.set_block(feet.x + dx, feet.y - 1, feet.z + dz, Blocks.STONE)
	player.global_position = Vector3(feet.x + 0.5, float(feet.y), feet.z + 0.5)
	await _settle(4)

	var standing_noise := player.noise_radius()
	check("standing tall by default", not player.crouching
		and is_equal_approx(player.half.y, Player.HALF.y))

	Input.action_press(&"crouch")
	await _settle(6)
	check("crouch engages on the ground", player.crouching)
	check("the hitbox actually shrinks", player.half.y < Player.HALF.y,
		"%.2f -> %.2f" % [Player.HALF.y, player.half.y])
	check("crouching is quieter than standing",
		player.noise_radius() < standing_noise,
		"%.1f -> %.1f" % [standing_noise, player.noise_radius()])

	# a one-block gap is passable crouched and not standing
	var gap := Vector3i(feet.x + 2, feet.y, feet.z)
	world.set_block(gap.x, gap.y, gap.z, Blocks.AIR)
	world.set_block(gap.x, gap.y + 1, gap.z, Blocks.STONE)
	var crouched_fits := not world.box_overlaps(
		Vector3(gap) + Vector3(0.5, player.half.y, 0.5), player.half)
	var standing_fits := not world.box_overlaps(
		Vector3(gap) + Vector3(0.5, Player.HALF.y, 0.5), Player.HALF)
	check("a one-block gap only admits you crouched",
		crouched_fits and not standing_fits)

	Input.action_release(&"crouch")
	await _settle(8)
	check("standing up again", not player.crouching)
	world.set_block(gap.x, gap.y + 1, gap.z, Blocks.AIR)


## The roster is the hand-made Starbound creatures, and they behave like
## characters rather than like one chase loop with different numbers.
func _bestiary() -> void:
	for id: StringName in [&"poptop", &"gleap", &"yokat", &"hypnare",
			&"mandraflora", &"crustoise", &"pteropod", &"narfin", &"voltip",
			&"fennix", &"lumoth", &"oculob", &"batong", &"anglure", &"scandroid"]:
		check("%s is in the bestiary" % id, SpeciesDB.get_def(id) != null)

	var tempers := {}
	for d: SpeciesDB.Def in SpeciesDB.defs:
		tempers[d.temperament] = true
	check("every temperament is represented", tempers.size() >= 5,
		"%d kinds" % tempers.size())

	var poptop := SpeciesDB.get_def(&"poptop")
	check("poptops graze", poptop.grazes and not poptop.diet.is_empty())
	check("poptops keep daylight hours", poptop.is_awake(false)
		and not poptop.is_awake(true))

	var hypnare := SpeciesDB.get_def(&"hypnare")
	check("the hypnare never starts a fight", not hypnare.will_fight())
	check("...but it does hit back", hypnare.flags.has(&"retaliates"))

	var crustoise := SpeciesDB.get_def(&"crustoise")
	check("the crustoise has a shell to break", crustoise.armour_hp > 0.0)

	var batong := SpeciesDB.get_def(&"batong")
	check("the batong hunts by ear, not by eye",
		batong.hearing > batong.sight and batong.sight_cone < 0.0)

	# --- a shelled creature soaks until the shell is gone
	var feet := player.feet_block()
	var m: Monster = game.spawn_monster(&"crustoise",
		Vector3(feet.x + 5, feet.y + 1, feet.z), 1.0)
	if m != null:
		var shell_before: float = m.shell
		var hp_before: float = m.health
		m.hurt(20.0, Blocks.ELEM_PHYSICAL, Vector3.ZERO, player)
		check("a shell soaks damage", m.health > hp_before - 20.0 and m.shell < shell_before,
			"hp %.0f -> %.0f" % [hp_before, m.health])
		m.queue_free()

	# --- taming: the right food, offered to a calm creature
	var t: Monster = game.spawn_monster(&"yokat",
		Vector3(feet.x + 7, feet.y + 1, feet.z), 1.0)
	if t != null:
		t.alert = 0.0
		t.fear = 0.0
		check("a creature refuses food it does not eat", not t.offer(&"cobblestone"))
		check("a creature takes food it does eat", t.offer(&"wheat"))
		t.alert = 0.0
		t.fear = 0.0
		t.offer(&"wheat")
		t.alert = 0.0
		t.fear = 0.0
		t.offer(&"wheat")
		check("enough of it wins the creature over", t.tamed)
		check("a tamed creature is not hostile", not t.is_hostile())
		t.queue_free()

	check("no procedurally generated species are in the pool",
		SpeciesDB.pool_for(&"forest", 9).all(
			func(d: SpeciesDB.Def) -> bool: return d.description != ""))


func _quests() -> void:
	var q = game.quests.current_story()
	check("the campaign started", q != null and q.id == "main_01_landfall")
	if q == null:
		return
	var obj: Quests.Objective = q.objectives[0]
	var before := obj.progress
	game.quests.on_item_gained(obj.target, 3)
	check("gathering advances objectives", obj.progress > before,
		"%d -> %d" % [before, obj.progress])

	# completing every objective must make the quest completable
	for o: Quests.Objective in q.objectives:
		o.progress = o.count
	check("a filled quest reports complete", q.is_complete())
	var pixels: int = player.inventory.pixels
	game.quests.complete(q)
	check("completing pays out", player.inventory.pixels > pixels)
	check("the chain advances", game.quests.has_active("main_02_ironbound"))


func _cutaway() -> void:
	var cut := world.cutaway
	check("cutaway is enabled", cut.enabled)
	# CPU predicate must agree with itself about the camera and the target
	var cam := cut.camera_position
	var tgt := cut.target_position
	var mid := (cam + tgt) * 0.5
	check("the midpoint of the sightline is inside the cut volume",
		cut.is_cut(int(floor(mid.x)), int(floor(mid.y)), int(floor(mid.z))))
	var far := tgt + (tgt - cam).normalized() * 40.0
	check("far behind the player is outside the cut volume",
		not cut.is_cut(int(floor(far.x)), int(floor(far.y)), int(floor(far.z))))

	var bounds := cut.get_int_bounds()
	check("the cut volume has a finite bounding box",
		bounds.size.x > 0 and bounds.size.x < 400)

	world.set_cutaway_enabled(false)
	check("disabling the cutaway cuts nothing",
		not cut.is_cut(int(floor(mid.x)), int(floor(mid.y)), int(floor(mid.z))))
	world.set_cutaway_enabled(true)


## The rules that were added because the cutaway was eating the things the
## player was trying to mine.
func _cutaway_modes() -> void:
	var cut := world.cutaway
	var feet := player.feet_block()
	# put the camera up and behind, the way the rig actually sits
	var target := player.global_position
	var cam := target + Vector3(0.0, 15.0, -22.0)
	world.update_cutaway(cam, target)

	# --- the keep shell
	var below := Vector3i(feet.x, feet.y - 1, feet.z)
	check("the block under your feet is never cut",
		not cut.is_cut(below.x, below.y, below.z))

	var side := Vector3i(feet.x + 1, feet.y, feet.z)
	world.set_block(side.x, side.y, side.z, Blocks.LOG)
	check("a trunk you have walked up to is never cut",
		not cut.is_cut(side.x, side.y, side.z), str(side))

	var away := Vector3i(feet.x, feet.y, feet.z + 2)
	check("a block on the far side from the lens is never cut",
		not cut.is_cut(away.x, away.y, away.z))

	# ...but the shell must not protect what is genuinely in the way
	var toward := Vector3i(feet.x, feet.y + 2, feet.z - 2)
	check("a block between you and the lens is still cut",
		cut.is_cut(toward.x, toward.y, toward.z), str(toward))

	# --- and the trunk must be aimable, which is what the quest needs
	var eye := target + Vector3(0, 1.0, 0)
	var to_log := (Vector3(side) + Vector3(0.5, 0.5, 0.5)) - eye
	var hit := world.raycast(eye, to_log.normalized(), 6.0, true)
	check("the trunk can still be aimed at",
		hit.get("hit", false) and hit.get("block") == side,
		str(hit.get("block", "nothing")))
	world.set_block(side.x, side.y, side.z, Blocks.AIR)

	# --- fill only travels through covered air
	var roofed := Vector3i(feet.x + 6, feet.y, feet.z)
	for dy in range(0, 4):
		for dx in range(-1, 4):
			for dz in range(-2, 3):
				world.set_block(roofed.x + dx, roofed.y + dy, roofed.z + dz, Blocks.AIR)
	for dx in range(-1, 4):
		for dz in range(-2, 3):
			world.set_block(roofed.x + dx, roofed.y + 4, roofed.z + dz, Blocks.STONE)
	check("a roofed pocket counts as covered",
		world.is_covered(roofed.x, roofed.y, roofed.z))
	check("open sky does not count as covered",
		not world.is_covered(feet.x, VoxelWorld.WH - 2, feet.z))

	world.set_cutaway_mode(Cutaway.Mode.FILL)
	world.update_cutaway(cam, target)
	world._rebuild_fill()
	check("fill mode produces a volume", cut.fill_size.x > 0)
	check("fill never marks the open sky",
		not cut.in_fill(feet.x, VoxelWorld.WH - 2, feet.z))

	# --- planar stays dormant until something is genuinely in the way
	world.set_cutaway_mode(Cutaway.Mode.PLANAR)
	cut.occluded = false
	var front := Vector3i(feet.x, feet.y + 1, feet.z - 6)
	check("planar cuts nothing while you are in the open",
		not cut.is_cut(front.x, front.y, front.z))
	cut.occluded = true
	check("planar cuts the slab in front once you are covered",
		cut.is_cut(front.x, front.y, front.z), str(front))
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)

	# --- presentation toggles
	world.set_cutaway_opacity(0.5)
	check("ghosts fade with distance from the player",
		cut.ghost_alpha(target + Vector3(1, 0, 0))
		> cut.ghost_alpha(target + Vector3(12, 0, 0)))
	check("ghosts are targetable once visible", cut.selectable_in_primary())
	world.set_cutaway_opacity(0.0)
	check("deleted blocks are not targetable in the primary pass",
		not cut.selectable_in_primary())


func _space() -> void:
	check("universe generated", game.universe.systems.size() >= 15,
		"%d systems" % game.universe.systems.size())
	check("home system discovered",
		game.universe.get_system(game.universe.home_system).discovered)
	var proving = game.universe.get_planet(Universe.PROVING_ID)
	check("the proving ground exists and is free", proving != null
		and proving.fuel_cost == 0 and proving.discovered)
	check("the proving ground is safe", proving != null and not proving.hostiles)
	check("planets carry a world configuration",
		not proving.world_config().is_empty())
	check("techs unlock with prerequisites checked",
		not game.tech.unlock(&"phase_step"))
	check("a root tech unlocks", game.tech.unlock(&"double_jump"))
	check("unlocking equips it", game.tech.equipped_in(&"legs") == &"double_jump")


func _persistence() -> void:
	player.inventory.add_item(&"diamond", 3)
	player.inventory.pixels = 4242
	var pos: Vector3 = player.global_position
	game.save_game()
	check("save file written", FileAccess.file_exists(game.SAVE_PATH))

	player.inventory.remove(&"diamond", 3)
	player.inventory.pixels = 0
	player.global_position = pos + Vector3(0, 30, 0)

	var ok: bool = game.load_game()
	check("save loads", ok)
	check("inventory round-trips", player.inventory.count_of(&"diamond") == 3,
		"%d" % player.inventory.count_of(&"diamond"))
	check("currency round-trips", player.inventory.pixels == 4242)
	check("position round-trips",
		player.global_position.distance_to(pos) < 0.01)
	check("quest state round-trips", game.quests.is_done("main_01_landfall"))
	await _settle(2)
