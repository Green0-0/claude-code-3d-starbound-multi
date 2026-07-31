extends RefCounted

## The quest book: a ten-beat main story that teaches the game in order, and a
## pool of side quests the village roles hand out.
##
## The campaign is deliberately built out of the same objectives as the side
## quests. There is no special-cased scripting anywhere in it — each beat is a
## counter, and the chain is one `then()` per quest.


static func register_all() -> void:
	_campaign()
	_side_merchant()
	_side_guard()
	_side_scientist()
	_side_villager()
	_side_drifter()
	_side_handler()


# ================================================================= campaign ====
static func _campaign() -> void:
	var q := Quests.make("main_01_landfall", "Landfall")
	q.main_story = true
	q.turn_in = false
	q.summary = "The escape pod is scrap and you are on the surface of a world "\
		+ "nobody bothered to name. Cut some wood, knock together a bench, and "\
		+ "make yourself a light before the sun goes."
	q.add(Quests.Kind.GATHER, &"wood_log", 6, "Fell timber")
	q.add(Quests.Kind.CRAFT, &"workbench", 1, "Build a workbench")
	q.add(Quests.Kind.CRAFT, &"torch", 4, "Make torches")
	q.rewards(60, [[&"bandage", 2]]).then("main_02_ironbound")

	q = Quests.make("main_02_ironbound", "Ironbound")
	q.main_story = true
	q.turn_in = false
	q.summary = "Stone tools will get you into the rock but not through it. "\
		+ "Find a seam, smelt what comes out of it, and put a real pick in "\
		+ "your hand."
	q.add(Quests.Kind.GATHER, &"raw_iron", 8, "Mine iron ore")
	q.add(Quests.Kind.CRAFT, &"furnace", 1, "Build a furnace")
	q.add(Quests.Kind.CRAFT, &"iron_pickaxe", 1, "Forge an iron pickaxe")
	q.rewards(140, [[&"coal", 12]]).then("main_03_the_deep")

	q = Quests.make("main_03_the_deep", "The Deep")
	q.main_story = true
	q.turn_in = false
	q.summary = "Everything worth having is underneath you. Go down far enough "\
		+ "that the sky stops helping, and come back with something that glows."
	q.add(Quests.Kind.DEPTH, &"y", 8, "Reach bedrock depth")
	q.add(Quests.Kind.GATHER, &"crystal_shard", 12, "Recover crystal")
	q.add(Quests.Kind.KILL, &"any", 8, "Clear out whatever objects")
	q.rewards(220, [[&"lantern", 4]]).then("main_04_neighbours")

	q = Quests.make("main_04_neighbours", "Neighbours")
	q.main_story = true
	q.summary = "There is a settlement out there. Find it, and find out what "\
		+ "they have been losing sleep over."
	q.giver = &"merchant"
	q.add(Quests.Kind.TALK, &"merchant", 1, "Find the settlement merchant")
	q.add(Quests.Kind.GATHER, &"pixels", 400, "Earn pixels by trading")
	q.rewards(200, [[&"iron_bar", 6]]).then("main_05_the_signal")

	q = Quests.make("main_05_the_signal", "The Signal")
	q.main_story = true
	q.summary = "The xenologist has been picking up a repeating transmission "\
		+ "from under the ruins. It wants a relay built, and it wants it built "\
		+ "out of things that do not exist on this planet."
	q.giver = &"scientist"
	q.add(Quests.Kind.GATHER, &"circuit_board", 4, "Fabricate circuit boards")
	q.add(Quests.Kind.GATHER, &"ancient_fragment", 6, "Recover ancient fragments")
	q.rewards(400, [[&"scan_pulse_tech_card", 1]]).teaches("erchius_to_ftl") \
		.then("main_06_fuel")

	q = Quests.make("main_06_fuel", "Enough To Leave")
	q.main_story = true
	q.turn_in = false
	q.summary = "Erchius burns hot enough to cross a system, if you can find "\
		+ "the moons that grow it and stabilise what you dig out."
	q.add(Quests.Kind.GATHER, &"erchius_fuel", 10, "Mine erchius")
	q.add(Quests.Kind.CRAFT, &"ftl_fuel", 4, "Refine FTL fuel")
	q.rewards(500, [[&"vacuum_chest", 1]]).then("main_07_the_gate")

	q = Quests.make("main_07_the_gate", "The Gate")
	q.main_story = true
	q.summary = "The transmission was coordinates, and the coordinates are a "\
		+ "gate. It is sealed, and it wants six essences to open."
	q.giver = &"scientist"
	q.add(Quests.Kind.VISIT, &"ancient_ruins", 1, "Find the ruins")
	q.add(Quests.Kind.GATHER, &"ancient_essence", 6, "Distil ancient essence")
	q.rewards(800, [[&"phase_step_tech_card", 1]]).then("main_08_the_fourfold")

	q = Quests.make("main_08_the_fourfold", "The Fourfold")
	q.main_story = true
	q.turn_in = false
	q.summary = "Something is standing on the other side of the gate, in four "\
		+ "places at once. It will not be where you are looking. Turn the "\
		+ "camera; that is the fight."
	q.add(Quests.Kind.KILL, &"boss_fourfold", 1, "Bind the Fourfold")
	q.rewards(2000, [[&"null_sequence", 1]]).then("main_09_the_long_way")

	q = Quests.make("main_09_the_long_way", "The Long Way Out")
	q.main_story = true
	q.turn_in = false
	q.summary = "The gate is open and the chart is yours. There are a great "\
		+ "many systems out there and no particular hurry."
	q.add(Quests.Kind.VISIT, &"new_system", 1, "Jump to another system")
	q.rewards(1200, [[&"refined_ftl_fuel", 4]])


# ============================================================= side quests ====
static func _side(id: String, title: String, giver: StringName,
		summary: String) -> Quests.Quest:
	var q := Quests.make(id, title)
	q.giver = giver
	q.summary = summary
	q.repeatable = true
	return q


static func _side_merchant() -> void:
	_side("side_supply_run", "Supply Run", &"merchant",
		"Stock is short and the caravan is late. Bring me raw material and I "\
		+ "will make it worth your while.") \
		.add(Quests.Kind.GATHER, &"iron_bar", 10, "Deliver iron bars") \
		.rewards(260, [[&"medkit", 1]])

	_side("side_glassworks", "Glassworks", &"merchant",
		"Every window in the settlement is a hole with a shutter on it. That is "\
		+ "not a settlement, that is a camp.") \
		.add(Quests.Kind.GATHER, &"glass", 16, "Deliver glass") \
		.rewards(180, [[&"lantern", 2]])

	_side("side_larder", "The Larder", &"merchant",
		"Winter is a rumour here but the larder does not know that.") \
		.add(Quests.Kind.GATHER, &"jerky", 6, "Deliver preserved food") \
		.rewards(220, [[&"canned_stew", 3]])


static func _side_guard() -> void:
	_side("side_cull", "Thinning Them Out", &"guard",
		"Something has been coming up out of the caves and it is getting "\
		+ "braver. Go down there and make it less brave.") \
		.add(Quests.Kind.KILL, &"any", 12, "Clear hostiles") \
		.rewards(300, [[&"iron_arrow", 24]])

	_side("side_perimeter", "Perimeter", &"guard",
		"I want the approach lit. If I can see it coming, I can shoot it.") \
		.add(Quests.Kind.PLACE, &"lantern", 8, "Place lanterns") \
		.rewards(200, [[&"iron_bar", 4]])

	_side("side_the_big_one", "Shell Game", &"guard",
		"There are crustoise out past the ridge that the patrols will not go "\
		+ "near. I am not asking them to. I am asking you.") \
		.add(Quests.Kind.KILL, &"crustoise", 3, "Kill crustoise") \
		.rewards(520, [[&"titanium_bar", 3]])


static func _side_scientist() -> void:
	_side("side_specimens", "Specimens", &"scientist",
		"I need tissue, and I need it from something that was recently alive "\
		+ "and is now emphatically not.") \
		.add(Quests.Kind.GATHER, &"venom_gland", 4, "Collect venom glands") \
		.add(Quests.Kind.GATHER, &"chitin", 8, "Collect chitin") \
		.rewards(340, [[&"antidote", 3]])

	_side("side_strata", "Strata Survey", &"scientist",
		"The deep rock here is not the deep rock anywhere else. Bring me a "\
		+ "column of it and I will tell you why that matters.") \
		.add(Quests.Kind.GATHER, &"deepstone", 12, "Sample deepstone") \
		.add(Quests.Kind.GATHER, &"corestone", 4, "Sample corestone") \
		.rewards(460, [[&"scanner", 1]])

	_side("side_the_glow", "What Makes It Glow", &"scientist",
		"Half the cave life on this world is luminous and none of it agrees on "\
		+ "how. Bring me glands.") \
		.add(Quests.Kind.GATHER, &"glow_gland", 3, "Collect glow glands") \
		.rewards(400, [[&"glow_tonic", 2]])


static func _side_villager() -> void:
	_side("side_homestead", "Homestead", &"villager",
		"We are trying to make this place liveable. Anything you can spare "\
		+ "that holds a roof up.") \
		.add(Quests.Kind.GATHER, &"wood_planks", 32, "Deliver planks") \
		.add(Quests.Kind.GATHER, &"stone_brick", 16, "Deliver stone brick") \
		.rewards(240, [[&"bed", 1]])

	_side("side_first_harvest", "First Harvest", &"villager",
		"Nothing we planted has come up. Show me it can be done and the rest "\
		+ "will follow.") \
		.add(Quests.Kind.GATHER, &"wheat", 12, "Harvest wheat") \
		.add(Quests.Kind.GATHER, &"potato", 8, "Harvest potatoes") \
		.rewards(200, [[&"fertiliser", 8]])


static func _side_drifter() -> void:
	_side("side_passage", "Working Passage", &"crew_recruit",
		"I will earn the berth. Get me the parts and I will keep your ship "\
		+ "running while you are down a hole somewhere.") \
		.add(Quests.Kind.GATHER, &"advanced_circuit", 2, "Deliver advanced circuits") \
		.add(Quests.Kind.GATHER, &"power_core", 1, "Deliver a power core") \
		.rewards(900, [[&"dense_energy_cell", 2]])


# ================================================================== taming ====
## The taming ladder, given out by the xenologist. It walks the player up the
## same rungs the system is built on: win one over by hand, put one under and
## feed it, teach one to work, and then go after something that needs all three.
static func _side_handler() -> void:
	_side("side_first_friend", "First Friend", &"scientist",
		"You will not survive out there alone, and I am not coming. Find "\
		+ "something with a mouth and no strong opinions, and feed it until it "\
		+ "follows you home.") \
		.add(Quests.Kind.TAME, &"any", 1, "Tame any creature") \
		.rewards(180, [[&"creature_feed", 12], [&"bola", 4]])

	_side("side_sleeping_it_off", "Sleeping It Off", &"scientist",
		"The interesting ones will not take food from a hand. They have to be "\
		+ "put down first — properly down, not dead. There is a considerable "\
		+ "difference and I would like you to learn it on something small.") \
		.add(Quests.Kind.CRAFT, &"tranq_arrow", 8, "Make tranquiliser arrows") \
		.add(Quests.Kind.TAME, &"voltip", 1, "Tame a voltip") \
		.rewards(420, [[&"narcotic", 6], [&"handlers_collar", 1]])

	_side("side_a_working_animal", "A Working Animal", &"scientist",
		"A tame that will not carry anything is a pet. I have no use for pets "\
		+ "and neither, out here, do you.") \
		.add(Quests.Kind.TAME, &"yokat", 1, "Tame a yokat") \
		.add(Quests.Kind.CRAFT, &"saddlebag", 1, "Make a saddlebag") \
		.rewards(360, [[&"kibble", 8]])

	_side("side_the_difficult_ones", "The Difficult Ones", &"scientist",
		"Now the ones with conditions attached. The crustoise will not let "\
		+ "anything through that shell, and the mandraflora has to be boxed in "\
		+ "before it will hold still long enough to be reasoned with.") \
		.add(Quests.Kind.TAME, &"crustoise", 1, "Tame a crustoise") \
		.add(Quests.Kind.TAME, &"mandraflora", 1, "Tame a mandraflora") \
		.rewards(880, [[&"strong_narcotic", 3], [&"capture_net", 4]])

	_side("side_the_fennix", "The One That Burns", &"scientist",
		"Three of them hunt together and they breathe fire, which does the "\
		+ "tranquiliser no favours at all. Catch one alone, after dark, and "\
		+ "already regretting its evening.") \
		.add(Quests.Kind.TAME, &"fennix", 1, "Tame a fennix") \
		.rewards(1600, [[&"tranq_rifle", 1], [&"tranq_dart", 24]])
