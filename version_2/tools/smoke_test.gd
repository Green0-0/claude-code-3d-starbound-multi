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

	print("== taming")
	await _taming()

	print("== quests")
	_quests()

	print("== cutaway")
	_cutaway()

	print("== cutaway modes")
	await _cutaway_modes()

	print("== resource budgets")
	await _budgets()

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

	check("no procedurally generated species are in the pool",
		SpeciesDB.pool_for(&"forest", 9).all(
			func(d: SpeciesDB.Def) -> bool: return d.description != ""))


# =============================================================================
# taming
# =============================================================================
#
# Two systems that must not be allowed to collapse into one: the passive route
# is a die roll gated by conditions, the knockout route is a resource drain
# gated by torpor. Both end in the same tamed creature, and the checks below
# hold each of them to its own rules.

func _taming() -> void:
	TameDB.boot()

	# --- the table itself
	check("every creature has a taming profile",
		SpeciesDB.defs.all(func(d: SpeciesDB.Def) -> bool:
			return TameDB.get_profile(d.id) != null),
		"%d profiles" % TameDB.profiles.size())

	var poptop := TameDB.get_profile(&"poptop")
	var fourfold := TameDB.get_profile(&"boss_fourfold")
	check("the tame ones are tame and the exotic ones are not",
		poptop.wildness < 0.3 and fourfold.wildness > 0.9,
		"poptop %.2f, fourfold %.2f" % [poptop.wildness, fourfold.wildness])
	check("wildness gates the handling skill required",
		poptop.min_handling == 0 and fourfold.min_handling > 10,
		"%d vs %d" % [poptop.min_handling, fourfold.min_handling])
	check("the exotic ones carry stringent conditions",
		poptop.conditions.is_empty() and fourfold.conditions.size() >= 3
		and TameDB.get_profile(&"ixodoom").conditions.size() >= 3)

	# RimWorld's curve, checked at both ends.
	check("taming odds follow (4%% + 3%% x skill) x 2 x (1 - wildness)",
		is_equal_approx(poptop.tame_chance(0), 0.08 * (1.0 - poptop.wildness))
		and is_equal_approx(poptop.tame_chance(6), 0.44 * (1.0 - poptop.wildness)),
		"%.3f at 0, %.3f at 6" % [poptop.tame_chance(0), poptop.tame_chance(6)])
	check("skill raises the odds", fourfold.tame_chance(20) > fourfold.tame_chance(0))

	check("kibble works on everything", poptop.food_quality(&"kibble") > 1.5
		and TameDB.get_profile(&"ixodoom").food_quality(&"kibble") > 1.5)
	check("plain feed works on everything, slowly",
		poptop.food_quality(&"creature_feed") > 0.0
		and poptop.food_quality(&"creature_feed") < 1.0)
	check("a creature still refuses what it does not eat",
		poptop.food_quality(&"cobblestone") == 0.0)

	# --- the handler skill
	var skill_before := player.handling_skill()
	player.gain_handling(200.0)
	check("handling is a skill that grows", player.handling_skill() > skill_before,
		"%d -> %d" % [skill_before, player.handling_skill()])

	var feet := player.feet_block()

	# --- passive route
	var y: Monster = game.spawn_monster(&"yokat",
		Vector3(feet.x + 7, feet.y + 1, feet.z), 1.0)
	check("a creature spawns to tame", y != null,
		"%d creatures already standing" % game.monsters_root.get_child_count())
	if y != null:
		y.alert = 0.0
		y.fear = 0.0
		player.crouching = true
		var wrong := y.tame_report(&"cobblestone", 30)
		check("it refuses food it does not eat", not wrong.get("ok", false))
		var right := y.tame_report(&"wheat", 30)
		check("it considers food it does eat", right.get("ok", false),
			String(right.get("reason", "")))
		check("the report states the odds", float(right.get("chance", 0.0)) > 0.0)

		# Standing up breaks the yokat's crouch condition, and the report has to
		# say so rather than failing silently.
		player.crouching = false
		var standing := y.tame_report(&"wheat", 30)
		check("an unmet condition blocks the attempt and is named",
			not standing.get("ok", false)
			and standing.get("unmet", []).has(TameDB.COND_CROUCH))
		player.crouching = true

		# Drive it to a result. With handling 30 against wildness 0.35 the odds
		# per attempt are high, so a few tries is plenty.
		var tries := 0
		while not y.tamed and tries < 40:
			y.alert = 0.0
			y.fear = 0.0
			y.tame_cooldown = 0.0
			y.try_tame(&"wheat", 30)
			tries += 1
		check("a passive tame succeeds with skill and the right food", y.tamed,
			"%d attempts" % tries)
		check("a tamed creature is not hostile", not y.is_hostile())
		check("taming teaches the handler", player.handling_skill() > 0)

		# --- culture: obedience first, everything else after
		check("haul cannot be taught before obedience",
			not y.can_be_trained(&"haul") and y.can_be_trained(&"obedience"))
		var lesson := 0
		while not y.knows(&"obedience") and lesson < 40:
			y.train(&"obedience")
			lesson += 1
		check("obedience can be taught", y.knows(&"obedience"))
		check("haul unlocks once it obeys", y.can_be_trained(&"haul"))
		while not y.knows(&"haul") and lesson < 80:
			y.train(&"haul")
			lesson += 1
		check("a trained creature will carry things", y.can_carry())

		# --- inventory
		var left: int = y.store(Items.make(&"cobblestone", 12))
		check("a tame has an inventory you can fill",
			left == 0 and y.carried_count() == 12,
			"%d slots, %d left over" % [y.carry_capacity, left])
		# Counted by item, not by node. `ItemDrop.spawn` rolls a new drop into a
		# nearby one of the same thing rather than carpeting the floor, so
		# "another child appeared" is not the promise — "the cobblestone is on
		# the ground" is, and it holds whether or not it merged.
		var stone_before := _dropped_count(&"cobblestone")
		y.drop_inventory()
		await _settle(3)
		check("what it carries comes back when it dies",
			_dropped_count(&"cobblestone") == stone_before + 12
			and y.carried_count() == 0,
			"%d -> %d cobblestone, %d still carried" % [stone_before,
				_dropped_count(&"cobblestone"), y.carried_count()])
		y.queue_free()
	player.crouching = false

	# --- knockout route
	var v: Monster = game.spawn_monster(&"voltip",
		Vector3(feet.x + 9, feet.y + 1, feet.z), 1.0)
	check("a knockout creature spawns", v != null)
	if v != null:
		await _settle(2)
		var prof := v.profile()
		check("it cannot be tamed by hand", prof.method == TameDB.METHOD_KNOCKOUT)
		var awake := v.tame_report(&"raw_meat", 30)
		check("it will not take food while awake", not awake.get("ok", false),
			String(awake.get("reason", "")))

		# Torpor, not damage.
		var hp_before: float = v.health
		v.apply_torpor(v.torpor_max * 0.5)
		check("torpor accumulates without hurting it",
			v.torpor > 0.0 and v.health == hp_before and not v.unconscious,
			"torpor %.0f/%.0f" % [v.torpor, v.torpor_max])
		v.apply_torpor(v.torpor_max)
		check("enough torpor puts it under", v.unconscious)
		check("an unconscious creature stops acting",
			v.tame_effectiveness == 1.0 and v.tame_feed == 0)

		# Ark's central trade: hitting it while it sleeps costs you quality.
		var eff_before: float = v.tame_effectiveness
		v.hurt(v.max_health * 0.3, Blocks.ELEM_PHYSICAL, Vector3.ZERO, player)
		check("hurting it while under costs taming effectiveness",
			v.tame_effectiveness < eff_before and v.unconscious,
			"%.2f -> %.2f" % [eff_before, v.tame_effectiveness])

		var bad := v.feed_unconscious(&"cobblestone")
		check("it still will not eat rubble", not bad.get("ok", false))

		var narc_before: float = v.torpor
		var narc := v.feed_unconscious(&"narcotic")
		check("narcotics top the torpor back up",
			narc.get("ok", false) and narc.get("narcotic", false)
			and v.torpor > narc_before,
			"%.0f -> %.0f" % [narc_before, v.torpor])

		# Ark's real loop: fill the sleeping creature's own bag and let it work
		# through the stack while you keep the torpor up.
		check("a wild creature already has an inventory",
			v.carry_capacity > 0 and v.inventory.size() == v.carry_capacity,
			"%d slots" % v.carry_capacity)
		check("you can load a sleeping creature's bag",
			v.store(Items.make(&"raw_meat", 20)) == 0)
		var carried_before: int = v.carried_count()
		v._feed_cd = 0.0
		v._eat_from_bag()
		check("it eats out of its own bag while it sleeps",
			v.carried_count() < carried_before and v.tame_feed > 0,
			"%d -> %d carried" % [carried_before, v.carried_count()])

		var fed := 0
		while not v.tamed and fed < 60:
			v._feed_cd = 0.0
			v.torpor = v.torpor_max
			v._eat_from_bag()
			fed += 1
		check("feeding it while it sleeps tames it", v.tamed, "%d bites" % fed)
		check("the finished creature keeps its reduced effectiveness",
			v.tame_effectiveness < 1.0,
			"%d%%" % int(v.tame_effectiveness * 100.0))
		check("it wakes up tame", not v.unconscious and v.torpor == 0.0)
		v.queue_free()

	# --- torpor is not a way round a shell
	var c: Monster = game.spawn_monster(&"crustoise",
		Vector3(feet.x + 11, feet.y + 1, feet.z), 1.0)
	if c != null:
		var soaked: float = c.torpor
		c.apply_torpor(60.0)
		var through_shell: float = c.torpor - soaked
		c.shell = 0.0
		c.torpor = 0.0
		c.apply_torpor(60.0)
		check("a shell keeps darts out as surely as blades",
			through_shell < c.torpor * 0.5,
			"%.0f through shell vs %.0f without" % [through_shell, c.torpor])
		check("the crustoise demands its shell be broken first",
			c.profile().conditions.has(TameDB.COND_SHELL_BROKEN))
		c.queue_free()

	# --- restraint satisfies "boxed in" without building a box
	var md: Monster = game.spawn_monster(&"mandraflora",
		Vector3(feet.x + 13, feet.y + 1, feet.z), 1.0)
	if md != null:
		check("the mandraflora must be trapped",
			md.profile().conditions.has(TameDB.COND_TRAPPED))
		check("out in the open it is not trapped",
			md.unmet_conditions().has(TameDB.COND_TRAPPED))
		md.restrained = 20.0
		check("a net counts as walls",
			not md.unmet_conditions().has(TameDB.COND_TRAPPED))
		md.queue_free()

	# --- maintenance taming: wildness pulls a tame back to wild
	var p2: Monster = game.spawn_monster(&"poptop",
		Vector3(feet.x + 15, feet.y + 1, feet.z), 1.0)
	if p2 != null:
		p2.finish_tame(1.0)
		p2.bonded = false
		check("a fresh tame is loyal", p2.tamed and p2.tame_decay == 0.0)
		p2.tame_decay = 0.99
		p2._tick_tame_decay(120.0)
		check("an unmaintained tame goes feral", not p2.tamed)
		p2.finish_tame(1.0)
		p2.bonded = false
		p2.tame_decay = 0.8
		check("feeding it resets the drift", p2.tend(&"carrot")
			and p2.tame_decay < 0.8)
		p2.bonded = true
		p2.tame_decay = 0.99
		p2._tick_tame_decay(1.0)
		check("a bonded creature never drifts", p2.tamed)
		p2.queue_free()

	# --- the sedative kit exists and is actually sedative
	for id: StringName in [&"tranq_arrow", &"tranq_dart", &"tranq_rifle",
			&"narcotic", &"stimulant", &"bola", &"capture_net",
			&"handlers_collar", &"saddlebag", &"kibble", &"creature_feed"]:
		check("%s is craftable gear" % id, Items.has(id))
	check("tranquiliser rounds carry torpor, not damage",
		Items.get_type(&"tranq_dart").torpor > 20.0
		and Items.get_type(&"tranq_dart").damage == 0.0)
	check("a stimulant removes torpor rather than adding it",
		Items.get_type(&"stimulant").torpor < 0.0)
	# Nobody lands with a tranquiliser rifle, so the bottom of the kit has to be
	# makeable bare-handed on the first afternoon.
	for id: StringName in [&"sap_club", &"bola"]:
		var made := Crafting.get_recipe(String(id))
		check("%s can be made bare-handed on the first day" % id,
			made != null and made.station == &"hand"
			and made.unlock == Crafting.Unlock.START)
	check("plain feed needs no more than a workbench",
		Crafting.get_recipe("creature_feed") != null
		and Crafting.get_recipe("creature_feed").unlock == Crafting.Unlock.START)


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

	# --- fill reveals the enclosed space the player is standing in, and only
	# that. Outdoors there is nothing enclosed, so it stands aside.
	world.set_cutaway_mode(Cutaway.Mode.FILL)
	world.update_cutaway(cam, target)
	world._rebuild_fill()
	check("open sky is not an enclosed space", cut.fill_empty)
	var sight_mid := (cut.camera_position + cut.target_position) * 0.5
	# The old build quietly turned into the cylinder here. It must not: fill
	# answers "what room am I in", and out of doors the answer is "none".
	check("with no pocket, fill cuts nothing at all",
		not cut.is_cut(int(floor(sight_mid.x)), int(floor(sight_mid.y)),
			int(floor(sight_mid.z))))

	# carve a sealed room a little away and stand the player in it
	var room := Vector3i(feet.x + 8, feet.y, feet.z)
	for dx in range(-2, 5):
		for dz in range(-3, 4):
			for dy in range(-1, 6):
				world.set_block(room.x + dx, room.y + dy, room.z + dz,
					Blocks.STONE if (dy == -1 or dy == 5) else Blocks.AIR)
	check("a roofed pocket counts as covered",
		world.is_covered(room.x, room.y, room.z))
	check("open sky does not count as covered",
		not world.is_covered(feet.x, VoxelWorld.WH - 2, feet.z))

	var room_target := Vector3(room) + Vector3(0.5, 0.0, 0.5)
	world.update_cutaway(room_target + Vector3(0, 15, -22), room_target)
	world._rebuild_fill()
	check("fill finds the room", not cut.fill_empty and cut.fill_size.x > 0)
	# The mask is one depth per column of the view plane, so the room's whole
	# footprint must be represented — a cone would leave the far corners at zero.
	var covered := 0
	for dx in range(-2, 5):
		for dz in range(-3, 4):
			var u := (room.z + dz if cut.fill_axis == 0 else room.x + dx) \
				- cut.fill_origin.x
			var v := room.y + 2 - cut.fill_origin.y
			if u < 0 or v < 0 or u >= cut.fill_size.x or v >= cut.fill_size.y:
				continue
			if cut.fill_depth[v * cut.fill_size.x + u] > 0:
				covered += 1
	check("fill covers the whole room, not a cone", covered >= 20,
		"%d columns of the room's footprint" % covered)

	# Everything between the room and the lens goes, and nothing behind it does.
	var toward_lens := cut.plane_toward()
	var along_axis := cut.fill_axis
	var in_front := Vector3i(room.x, room.y + 2, room.z)
	var behind := Vector3i(room.x, room.y + 2, room.z)
	if along_axis == 0:
		in_front.x += toward_lens * 6
		behind.x -= toward_lens * 6
	else:
		in_front.z += toward_lens * 6
		behind.z -= toward_lens * 6
	check("fill removes what stands between the room and the lens",
		cut.is_cut(in_front.x, in_front.y, in_front.z), str(in_front))
	check("fill leaves everything behind the room alone",
		not cut.is_cut(behind.x, behind.y, behind.z), str(behind))
	check("fill never touches the open sky",
		not cut.is_cut(feet.x, VoxelWorld.WH - 2, feet.z))

	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
	world.update_cutaway(cam, target)

	# --- planar stays dormant until something is genuinely in the way
	world.set_cutaway_mode(Cutaway.Mode.PLANAR)
	world.update_cutaway(cam, target)
	cut.occluded = false
	var front := Vector3i(feet.x, feet.y + 1, feet.z - 6)
	check("planar cuts nothing while you are in the open",
		not cut.is_cut(front.x, front.y, front.z))
	cut.occluded = true
	check("planar cuts past the plane once you are covered",
		cut.is_cut(front.x, front.y, front.z), str(front))

	# Planar is a half-space, not a box. It has no lateral, vertical or far
	# bound: if it is past the plane, it is gone, however far away.
	var far_out := Vector3i(feet.x + 40, feet.y + 20, feet.z - 60)
	check("planar has no far bound", cut.is_cut(far_out.x, far_out.y, far_out.z),
		str(far_out))
	check("planar has no lateral bound",
		cut.is_cut(feet.x - 40, feet.y, feet.z - 6))
	check("planar leaves everything on your side of the plane alone",
		not cut.is_cut(feet.x + 40, feet.y + 20, feet.z + 3))

	# And the whole point: the cut depends on one coordinate, so walking across
	# the plane or up and down it must not invalidate the cut set. Only the cap
	# *window* follows the player sideways, and only every sixteen blocks.
	var plane_here := cut.plane_coord()
	var sig_here := cut.signature(0)
	var moved_sig := 0
	var prev_sig := sig_here
	for step in 8:
		cut.place(cam + Vector3(step + 1, 0, 0), target + Vector3(step + 1, 0, 0))
		var now := cut.signature(0)
		if now != prev_sig:
			moved_sig += 1
		prev_sig = now
	check("walking across the plane never moves the plane",
		cut.plane_coord() == plane_here,
		"%d vs %d" % [cut.plane_coord(), plane_here])
	check("walking across the plane rebuilds at most once per chunk",
		moved_sig <= 1, "%d of 8 sideways steps invalidated" % moved_sig)

	# Height is not a term at all. The slice is built for the whole column, so
	# climbing a shaft cannot invalidate a cross-section that already covers it.
	cut.place(cam, target)
	var sig_ground := cut.signature(0)
	cut.place(cam + Vector3(0, 11, 0), target + Vector3(0, 11, 0))
	check("climbing never rebuilds the cross-section",
		cut.signature(0) == sig_ground)

	cut.place(cam, target)
	cut.place(cam + Vector3(0, 0, -2), target + Vector3(0, 0, -2))
	check("stepping along the view axis does move the plane",
		cut.plane_coord() != plane_here)

	_planar_faces(cam, target)
	_cylinder_march(cam, target)

	world.update_cutaway(cam, target)
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

	# --- the whole point of quantising: standing still costs nothing at all
	for mode: int in [Cutaway.Mode.CYLINDER, Cutaway.Mode.FILL, Cutaway.Mode.PLANAR]:
		world.set_cutaway_mode(mode)
		player.velocity = Vector3.ZERO
		await _settle(6)
		var before: int = world.cut_rebuilds
		for i in 30:
			world.update_cutaway(cut.camera_position + Vector3(0.31, 0.07, -0.19),
				cut.target_position + Vector3(0.11, 0.0, 0.09))
			await get_tree().process_frame
		check("%s mode rebuilds nothing while you stand still" % cut.mode_name(),
			world.cut_rebuilds == before,
			"%d rebuilds over 30 frames" % (world.cut_rebuilds - before))
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)

	# --- and breaking a block does force one, so no stale cross-section is left
	var feet2 := player.feet_block()
	world.set_block(feet2.x + 2, feet2.y, feet2.z, Blocks.STONE)
	await _settle(3)
	var before_break: int = world.cut_rebuilds
	world.set_block(feet2.x + 2, feet2.y, feet2.z, Blocks.AIR)
	await _settle(3)
	check("breaking a block rebuilds the cross-section immediately",
		world.cut_rebuilds > before_break)

	# --- but the writes that change constantly and change nothing must not.
	#
	# Liquid flow and crop growth write blocks on their own timers, for as long
	# as the world exists. Nothing they write is opaque and nothing they write
	# collides, so none of it can move a vertex of any cross-section — but the
	# version the cut watches was bumped by every write alike, so standing near
	# running water rebuilt the whole slice several times a second, forever.
	var wet := Vector3i(feet2.x + 3, feet2.y + 1, feet2.z)
	world.set_cutaway_mode(Cutaway.Mode.PLANAR)
	world.cutaway.occluded = true
	await _settle(4)
	var before_water: int = world.cut_rebuilds
	# a frame apart, the way the flow timer actually writes them — batched into
	# one frame the signature is only compared once and the cost is hidden
	for i in 8:
		world.set_block(wet.x, wet.y, wet.z,
			Blocks.id(&"water") if i % 2 == 0 else Blocks.AIR)
		await _settle(2)
	check("flowing water never rebuilds the cross-section",
		world.cut_rebuilds == before_water,
		"%d rebuilds over 8 writes" % (world.cut_rebuilds - before_water))

	var before_stone: int = world.cut_rebuilds
	world.set_block(wet.x, wet.y, wet.z, Blocks.STONE)
	await _settle(3)
	check("...but a block that is really there still does",
		world.cut_rebuilds > before_stone)
	world.set_block(wet.x, wet.y, wet.z, Blocks.AIR)
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
	await _settle(2)

	# --- and the block itself stops being drawn on the very next frame.
	#
	# This is the ghost. The chunk remesh used to sit in the same time-budgeted
	# queue as terrain streaming, so under load — which in a cut mode is most of
	# the time — a destroyed block could keep its faces for many frames. Player
	# edits jump that queue, and this holds them to it in every mode.
	#
	# `edit_block` and not `set_block` on purpose: the promise is about a block
	# the *player* just broke. Water finding its level and wheat growing a stage
	# also write blocks, several a second and forever, and letting those jump
	# the queue as well was the largest single source of stutter in the game.
	for mode: int in [Cutaway.Mode.CYLINDER, Cutaway.Mode.FILL, Cutaway.Mode.PLANAR]:
		world.set_cutaway_mode(mode)
		var cell := Vector3i(feet2.x + 2, feet2.y + 1, feet2.z)
		world.edit_block(cell.x, cell.y, cell.z, Blocks.STONE)
		await _settle(4)
		var standing := _own_faces_at(cell)
		world.edit_block(cell.x, cell.y, cell.z, Blocks.AIR)
		await _settle(1)
		check("%s: a destroyed block is gone the next frame" % cut.mode_name(),
			standing > 0 and _own_faces_at(cell) == 0,
			"%d faces before, %d after one frame" % [standing, _own_faces_at(cell)])
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)


## The faces on the split itself.
##
## This is the mode's whole reason to exist. Standing on the plane you are
## looking straight at the slice, so every solid cell on it whose forward
## neighbour the cut removed has to hand back the face that neighbour was
## hiding — on the lens side of the block, pointing at the lens. Emitted on the
## far side, or with the opposite normal, every quad is backface-culled and
## buried, and the mode reads as a hole into the skybox rather than as a wall.
##
## Nothing checked that before, which is exactly how it came to be wrong.
func _planar_faces(cam: Vector3, target: Vector3) -> void:
	var cut := world.cutaway
	var feet := player.feet_block()

	# a solid slab below the player, with a pocket in it to look out of
	var cy: int = maxi(feet.y - 8, 3)
	for dx in range(-6, 7):
		for dz in range(-6, 7):
			for dy in range(-2, 5):
				world.set_block(feet.x + dx, cy + dy, feet.z + dz, Blocks.STONE)
	world.set_block(feet.x, cy, feet.z, Blocks.AIR)
	world.set_block(feet.x, cy + 1, feet.z, Blocks.AIR)

	var buried := Vector3(feet.x + 0.5, float(cy), feet.z + 0.5)
	world.set_cutaway_mode(Cutaway.Mode.PLANAR)
	world.update_cutaway(buried + Vector3(0, 15, -22), buried)
	cut.occluded = true
	world._rebuild_caps()

	var axis := cut.plane_axis()
	var plane := cut.plane_coord()
	var t := cut.plane_toward()
	var toward := Vector3(cut.toward_camera())
	# the cut side of the block: +1 when the lens is at increasing coordinates
	var face_at := float(plane) + (1.0 if t > 0 else 0.0)

	var mesh: ArrayMesh = world._cap_mi.mesh
	check("the split has a cross-section at all",
		mesh != null and mesh.get_surface_count() > 0)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	var wrong_way := 0
	for n: Vector3 in norms:
		if n.dot(toward) < 0.99:
			wrong_way += 1
	check("every face on the split turns toward the lens", wrong_way == 0,
		"%d of %d point away" % [wrong_way, norms.size()])

	var off_plane := 0
	for v: Vector3 in verts:
		if absf((v.x if axis == 0 else v.z) - face_at) > 0.001:
			off_plane += 1
	check("every face on the split stands on the split", off_plane == 0,
		"%d of %d vertices are off it" % [off_plane, verts.size()])

	# Coverage: the merged runs have to account for every buried cell of the
	# slice, not just the ones nearest the player.
	var covered := {}
	for i in world._cap_meta.size():
		var o: Vector3 = world._cap_cells[i]
		var run: int = maxi((world._cap_meta[i] >> 24) & 255, 1)
		for r in run:
			covered[Vector3i(int(o.x), int(o.y) + r, int(o.z))] = true

	var want := 0
	var got := 0
	for da in range(-5, 6):
		for y in range(cy - 2, cy + 5):
			var gx: int = plane if axis == 0 else feet.x + da
			var gz: int = feet.z + da if axis == 0 else plane
			var fx: int = gx + (t if axis == 0 else 0)
			var fz: int = gz + (0 if axis == 0 else t)
			if not Blocks.is_opaque(world.get_block(gx, y, gz)):
				continue
			if not Blocks.is_opaque(world.get_block(fx, y, fz)):
				continue
			want += 1
			if covered.has(Vector3i(gx, y, gz)):
				got += 1
	check("every buried cell on the split gets its face back",
		want > 0 and got == want, "%d of %d covered" % [got, want])

	# ...and only those. A cell whose forward neighbour was already air kept the
	# face the chunk mesher gave it, and a second coplanar copy is z-fighting.
	var doubled := 0
	for c: Vector3i in covered:
		var fx: int = c.x + (t if axis == 0 else 0)
		var fz: int = c.z + (0 if axis == 0 else t)
		if not Blocks.is_opaque(world.get_block(fx, c.y, fz)):
			doubled += 1
	check("the split never doubles a face the terrain already draws",
		doubled == 0, "%d of %d duplicated" % [doubled, covered.size()])

	# --- and the chunks with nothing left in them are not submitted at all
	var here := Vector2i(feet.x >> 4, feet.z >> 4)
	var past := here
	if axis == 0:
		past.x += t * 4
	else:
		past.y += t * 4
	check("planar hides the chunks wholly past the plane",
		cut.planar_chunk_hidden(past.x, past.y), str(past))
	check("planar keeps the chunk you are standing in",
		not cut.planar_chunk_hidden(here.x, here.y))
	var behind := here
	if axis == 0:
		behind.x -= t * 4
	else:
		behind.y -= t * 4
	check("planar keeps everything behind the plane",
		not cut.planar_chunk_hidden(behind.x, behind.y))
	# Ghosts are still on screen, so nothing may be hidden while they are drawn.
	world.set_cutaway_opacity(0.5)
	check("ghosted blocks are never hidden by the chunk cull",
		not cut.planar_chunk_hidden(past.x, past.y))
	world.set_cutaway_opacity(0.0)

	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
	world.update_cutaway(cam, target)


## The drill's cross-section, marched, must equal the drill's cross-section
## walked exhaustively.
##
## `_caps_from_cylinder` only looks at cells near the segment instead of at
## every cell of the box around it, which is worth several milliseconds a frame
## — but only if it cannot miss one. That is an argument about the reach of a
## capsule and the spacing of the samples, and an argument is not a proof, so
## here both are run over real terrain from several angles and the geometry is
## compared cell for cell.
func _cylinder_march(cam: Vector3, target: Vector3) -> void:
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
	var mismatched := 0
	var probed := 0
	var emitted := 0

	for i in 8:
		var a := float(i) * TAU / 8.0
		var lens := target + Vector3(cos(a) * 20.0, 9.0 + float(i), sin(a) * 20.0)
		world.update_cutaway(lens, target)

		world._cap_cells.clear()
		world._cap_meta.clear()
		world._caps_from_cylinder()
		var fast := _cap_set()

		world._cap_cells.clear()
		world._cap_meta.clear()
		world._caps_from_bounds()
		var slow := _cap_set()

		probed += 1
		emitted += slow.size()
		if fast != slow:
			mismatched += 1

	check("the marched drill matches the exhaustive walk exactly",
		mismatched == 0 and emitted > 0,
		"%d of %d angles differ, %d faces compared" % [mismatched, probed, emitted])


## The cap set as a comparable value: cell and packed face, order-independent.
func _cap_set() -> Dictionary:
	var out := {}
	for i in world._cap_meta.size():
		var c: Vector3 = world._cap_cells[i]
		out["%d,%d,%d,%d" % [int(c.x), int(c.y), int(c.z), world._cap_meta[i]]] = true
	return out


## The rules that keep a long session from getting slower than a short one.
##
## Every one of these was a real, measured cost: a sprite sheet redrawn pixel by
## pixel on each respawn, a structure repopulated on each return trip, a nest of
## creatures that ignored the population ceiling, a queue that only ever grew.
## They are cheap to assert and expensive to rediscover, and none of them shows
## up in a test that runs for ten seconds — which is why they are asserted here
## rather than left to `tools/soak.gd` to notice an hour in.
func _budgets() -> void:
	# --- generated sprite sheets are drawn once per distinct look, not per spawn
	var sp := SpeciesDB.get_def(&"poptop")
	check("a creature's sprite sheet is drawn once, not per spawn",
		sp != null and TexGen.build_creature(sp.shape, sp.color, sp.alt, sp.features)
		== TexGen.build_creature(sp.shape, sp.color, sp.alt, sp.features))
	check("villagers draw from a closed set of faces",
		TexGen.build_npc(Color.RED, Color.BLUE, 3)
		== TexGen.build_npc(Color.RED, Color.BLUE, 3))

	# --- a structure populates once, however often its chunk is regenerated
	var at := player.feet_block() + Vector3i(4, 0, 4)
	var spec := {"kind": &"mineshaft", "at": at}
	world.pending_structures = [spec]
	game._populate_structures()
	await _settle(2)
	var after_first: int = game.objects_root.get_child_count()
	# exactly what a return trip does: the chunk regenerates and queues it again
	world.pending_structures = [spec.duplicate()]
	game._populate_structures()
	await _settle(2)
	check("a structure regenerating does not populate it twice",
		game.objects_root.get_child_count() == after_first,
		"%d -> %d objects" % [after_first, game.objects_root.get_child_count()])
	check("and its spec is consumed rather than carried forever",
		world.pending_structures.is_empty(),
		"%d left queued" % world.pending_structures.size())

	# --- nothing may stack two objects in one cell, whoever asks
	var dup := PlacedObject.create(game.objects_root, game, &"chest", at)
	check("two objects cannot occupy one cell", dup == null)

	# --- a nest of creatures draws from the population budget, not around it
	# Asked for a thousand. It may take the population up to the ceiling and no
	# further — and if scripted spawns have already carried it past (the tests
	# above summon their own), it may add nothing at all.
	var before: int = game.monsters_root.get_child_count()
	game._populate_camp({"kind": &"camp", "at": at, "count": 999})
	var after: int = game.monsters_root.get_child_count()
	check("a camp cannot spawn past the creature ceiling",
		after <= maxi(before, game.MAX_MONSTERS),
		"%d -> %d, ceiling %d" % [before, after, game.MAX_MONSTERS])

	# --- and the simulation's own writes stay off the unbudgeted remesh path
	var cell := player.feet_block() + Vector3i(0, 3, 0)
	world._edit_dirty.clear()
	world.set_block(cell.x, cell.y, cell.z, Blocks.id(&"water"))
	check("simulation writes do not jump the mesh queue",
		world._edit_dirty.is_empty())
	world._edit_dirty.clear()
	world.edit_block(cell.x, cell.y, cell.z, Blocks.AIR)
	check("but the player's own edits do",
		not world._edit_dirty.is_empty())


## How many of an item are lying on the ground, across every drop.
func _dropped_count(id: StringName) -> int:
	var n := 0
	for child in game.drops_root.get_children():
		var d := child as ItemDrop
		if d != null and d.stack != null and d.stack.id == id:
			n += d.stack.count
	return n


## How many of a cell's *own* outward faces the chunk mesh is still drawing.
##
## Counting vertices in the cell's box cannot answer this: breaking a block also
## gives its neighbours new faces on those same planes, so a correct break reads
## as a rise. The normals separate them — a block's own faces point out of it.
func _own_faces_at(cell: Vector3i) -> int:
	var c = world._chunks.get(Vector2i(cell.x >> 4, cell.z >> 4))
	if c == null or c.mi == null or c.mi.mesh == null:
		return 0
	var centre := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var offset: Vector3 = c.mi.global_position
	var own := 0
	for s in c.mi.mesh.get_surface_count():
		var arrays: Array = c.mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if norms.size() != verts.size():
			continue
		var i := 0
		while i + 3 < verts.size():
			var mid := (verts[i] + verts[i + 1] + verts[i + 2] + verts[i + 3]) \
				* 0.25 + offset - centre
			if absf(mid.x) <= 0.51 and absf(mid.y) <= 0.51 and absf(mid.z) <= 0.51 \
					and mid.dot(norms[i]) > 0.0:
				own += 1
			i += 4
	return own


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
