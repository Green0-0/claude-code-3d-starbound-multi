## The main storyline: ten chapters that teach, then weaponise, the perspective
## mechanic.
##
## [b]Premise.[/b] The Protectorate's gate network never ran on engines. It ran on
## the Fourfold — the fact that a world has four faces and a traveller may choose
## which one is true. Something called the Cartographer has been going from world
## to world *flattening* them: pinning each planet to a single plane so it can be
## surveyed, indexed and held. A flattened world cannot be jumped from, which is
## why your drive is dead and your ship is in a crater.
##
## Chapters 4-7 are the four Plane Shrines, one per viewing plane, each teaching
## a deeper use of flipping and shifting. Chapter 8 binds them, 9 is the boss, 10
## is the way out.
##
## Every chapter completes on its own objectives rather than a turn-in visit, so
## the campaign is playable before any other agent's NPCs exist. Where a chapter
## also wants a landmark or a boss from another module, that hook is an
## [i]optional[/i] objective and is documented in the report.
class_name QuestCampaign
extends RefCounted

## Faction key the campaign's reputation rewards go to.
const PROTECTORATE: StringName = &"protectorate"

## Objective keys the worldgen / structure / monster agents can satisfy by
## calling [method Quests.report]. All optional — the campaign never blocks on
## them, they just make it richer.
##   report(&"explore", &"ancient_gateway")
##   report(&"explore", &"four_faced_shrine" | &"impossible_chamber"
##                    | &"blind_treasury" | &"depth_labyrinth" | &"plane_lock_vault")
## Those are real ids from `worldgen/structures/structures/perspective_structs.gd`;
## `entities/npc/spawn.gd` already fires them from `structure_anchor` tile data,
## so no other agent has to do anything.
##   report(&"kill",    &"cartographer")


## Called by the quest manager at boot. The [param quests] argument is the
## manager node; we use the `Quests` autoload directly so every call type-checks.
static func register_all(_quests: Node) -> void:
	_ch1()
	_ch2()
	_ch3()
	_ch4()
	_ch5()
	_ch6()
	_ch7()
	_ch8()
	_ch9()
	_ch10()
	# Chapter one is on the table from the first frame of a new game.
	if not Quests.is_completed("main_01_crash") and not Quests.is_active("main_01_crash"):
		Quests.offer("main_01_crash", null)


# =========================================================================
static func _ch1() -> void:
	Quests.define("main_01_crash", "Hard Landing").as_main(1) \
		.from_npc(&"axis", "AXIS").completes_instantly().at_threat(1) \
		.described("Salvage what you can from the wreck and get a roof over your head.",
			"The drive did not fail. It was refused.") \
		.needs(QuestObjective.mine(&"", 12).described("Break 12 blocks — you need a hole to sleep in")) \
		.needs(QuestObjective.collect(&"", 10).described("Salvage 10 items from the ground and the wreck")) \
		.needs(QuestObjective.craft(&"", 1).described("Craft anything at all").as_optional()) \
		.pays(120).pays_reputation(PROTECTORATE, 5) \
		.sets_flag("ch1_landed").unlocks_quest("main_02_repair") \
		.with_dialogue("axis_ch1") \
		.says(
			"AXIS online. Hull integrity: comical. Atmosphere: breathable, which is more than I expected of a planet that threw us at itself.\n\nListen. I have run the flight recorder eleven thousand times. The drive did not fail. At 04:12 ship-time the drive was *refused* — the jump geometry simply stopped being available, the way a door stops being a door when someone bricks it up.\n\nI cannot fix that from a crater. You can. Start smaller: break ground, gather what the wreck spat out, and do not die in the first hour. It would embarrass us both.",
			"Adequate. You have a hole and a handful of scrap, which is how most civilisations began.\n\nI have been listening while you dug. There is a resonance under this crust — a slow four-beat, like something enormous counting. It is not natural and it is not us. We are going to find out what it is, and then I suspect we are going to be very rude to it.")


static func _ch2() -> void:
	Quests.define("main_02_repair", "What the Ship Needs").as_main(2) \
		.from_npc(&"axis", "AXIS").completes_instantly().at_threat(1) \
		.after("main_01_crash") \
		.described("Patch the hull and get AXIS enough power to think straight.",
			"A ship is a promise you make to vacuum.") \
		.needs(QuestObjective.mine(&"", 40).described("Cut 40 blocks of material out of the world")) \
		.needs(QuestObjective.build(&"", 20).described("Place 20 blocks — patch the hull, wall the crater")) \
		.needs(QuestObjective.collect(&"", 30).described("Stockpile 30 items")) \
		.pays(260).pays_reputation(PROTECTORATE, 8) \
		.sets_flag("ship_repaired").unlocks_quest("main_03_gateway") \
		.with_dialogue("axis_ch2") \
		.says(
			"Priority list, in descending order of how much it will hurt you if ignored.\n\nOne: the hull. There are three holes in me I could walk a cargo drone through, assuming I had legs, which is a separate grievance. Cut stone. Place stone. Do not be artistic about it.\n\nTwo: stockpile. Everything you can carry. On a flattened world the ground gives up materials grudgingly and I would rather we hoarded now than begged later.\n\nThree — and I want you to hear the emphasis — stay above the deep strata. The four-beat gets louder down there and I do not like what it does to my clock.",
			"Hull sealed. Power stable. I can hold a thought longer than nine seconds, which I am told is the minimum for personhood.\n\nWith the sensors back I can finally read that resonance properly, and I need you to understand what I am about to say is not a metaphor. The signal is not coming from a place. It is coming from a *direction* — one that this planet is currently refusing to have. Something has pinned this world flat, and the pin is roughly nine hundred metres that way, under a hill.\n\nGo and look at the hill.")


static func _ch3() -> void:
	Quests.define("main_03_gateway", "The Signal Under the Hill").as_main(3) \
		.from_npc(&"axis", "AXIS").completes_instantly().at_threat(2) \
		.after("main_02_repair") \
		.described("Dig to the buried gateway and learn to turn the world.",
			"Turn, and the wall becomes a door.") \
		.needs(QuestObjective.mine(&"", 60).described("Dig down toward the resonance")) \
		.needs(QuestObjective.flips(4).described("Turn the world four times — get the feel of it")) \
		.needs(QuestObjective.observe_plane(&"gateway_west", 1)
			.described("Stand square to the West plane and look at what the hill was hiding")) \
		.needs(QuestObjective.explore(&"ancient_gateway")
			.described("Enter the gateway chamber").as_optional()) \
		.pays(400).pays_reputation(PROTECTORATE, 10) \
		.sets_flag("gateway_found").unlocks_quest("main_04_shrine_north") \
		.with_dialogue("ovid_ch3") \
		.says(
			"You are standing on it. Dig.\n\nAnd — this is the part where I would like your full attention, because your species historically skims — when you get down there, the chamber will look sealed. It will look like solid rock in every direction. It will be lying to you.\n\nA world has four faces. You have been walking around on one of them your entire life like a man reading a single page of a book and complaining that the plot is thin. Turn. Q and E. The stone does not move; *you* stop agreeing to see it from one side. What was a wall is a corridor. It has always been a corridor. You were simply facing the wrong way to have it.",
			"CURATOR OVID: Ah. Ah! A visitor. Do not touch the plinth — no, do not — thank you.\n\nI have been the Curator of this gateway for nine hundred and forty years, which sounds impressive until you learn that for eight hundred of them nothing has come through it. It is not broken. It is *unbound*. The Fourfold that powered it has been taken apart and scattered into four shrines, one for each face of this world, and each of them is sulking.\n\nBind them and the gate opens. Bind them and your ship remembers how to leave. Fail, and — well. You will be here with me, and I am poor company.")


# =========================================================================
#  The four Plane Shrines
# =========================================================================
static func _ch4() -> void:
	Quests.define("main_04_shrine_north", "Shrine of the North — The Turn").as_main(4) \
		.from_npc(&"keeper_north", "Keeper of the North").completes_instantly().at_threat(3) \
		.after("main_03_gateway") \
		.described("The North Keeper teaches the flip: nothing moves but you.",
			"You did not move. The world agreed to be seen differently.") \
		.needs(QuestObjective.flips(10).described("Turn the world ten times")) \
		.needs(QuestObjective.observe_plane(&"north_face", 0)
			.described("Face the North plane at the shrine")) \
		.needs(QuestObjective.observe_plane(&"south_face", 2)
			.described("Then face the South plane — the same stone, the other side")) \
		.needs(QuestObjective.explore(&"four_faced_shrine").described("Find the North Shrine").as_optional()) \
		.pays(500).pays_reputation(PROTECTORATE, 12).pays_tech(&"plane_sense") \
		.sets_flag("shrine_north").unlocks_quest("main_05_shrine_west") \
		.with_dialogue("keeper_north") \
		.says(
			"KEEPER OF THE NORTH: Stop. Before you take anything from this room, answer me one question, and answer it honestly, because I have heard every lie.\n\nWhen you turn — when the world swings ninety degrees around you — what moved?\n\nMost say the world. The world does not move. The world has never moved. It has four faces at once and always has; you are simply incapable of holding more than one of them in your head at a time, and turning is the small, humiliating ritual by which you swap which one you are holding.\n\nDo it ten times. Not to please me. To stop being surprised by it.",
			"KEEPER OF THE NORTH: Good. You flinched less at the end than the beginning.\n\nTake the North sigil. It will not help you fight and it will not help you dig. What it does is much smaller and much worse: from now on, when you look at a wall, some part of you will wonder what it is from the other three sides. You will never be able to stop wondering. I am sorry. It is the price of the whole discipline.")


static func _ch5() -> void:
	Quests.define("main_05_shrine_west", "Shrine of the West — The Step").as_main(5) \
		.from_npc(&"keeper_west", "Keeper of the West").completes_instantly().at_threat(3) \
		.after("main_04_shrine_north") \
		.described("The West Keeper teaches the shift: the layers behind you are real.",
			"Background is only foreground you have not walked into yet.") \
		.needs(QuestObjective.shifts(14).described("Step fourteen layers into and out of the world")) \
		.needs(QuestObjective.observe_plane(&"west_face", 1)
			.described("Hold the West plane at the shrine")) \
		.needs(QuestObjective.flips(6).described("Turn six times while you are down there")) \
		.needs(QuestObjective.explore(&"impossible_chamber").described("Find the West Shrine").as_optional()) \
		.pays(650).pays_reputation(PROTECTORATE, 12).pays_tech(&"depth_dash") \
		.sets_flag("shrine_west").unlocks_quest("main_06_shrine_south") \
		.with_dialogue("keeper_west") \
		.says(
			"KEEPER OF THE WEST: The North one talks about *seeing*. Seeing is free. Seeing costs you nothing and changes nothing and any fool with a neck can do it.\n\nI teach the expensive half.\n\nBehind you, right now, is another layer of this world. And behind that another, and another, dimmer and dimmer until the dark. You have spent your life calling that 'the background' as if it were painted on. It is not painted on. It is a place. It has floors you could stand on and ceilings that could fall on you.\n\nStep into it. Page up, page down. It can be blocked — of course it can be blocked, it is *real*, that is the entire point — and when it is blocked you will have to turn, and find a face where it is not.",
			"KEEPER OF THE WEST: Fourteen steps. You have been in this world longer today than in your entire life before it.\n\nHere is what the North one will not tell you, out of politeness. Turning is a trick of attention. Stepping is a trespass. Every layer you walk into is one somebody else was using — a root system, a burial, a nest, a corridor that was sealed for an excellent reason.\n\nTake the West sigil. Knock, occasionally.")


static func _ch6() -> void:
	Quests.define("main_06_shrine_south", "Shrine of the South — The Hidden").as_main(6) \
		.from_npc(&"keeper_south", "Keeper of the South").completes_instantly().at_threat(4) \
		.after("main_05_shrine_west") \
		.described("The South Keeper teaches concealment: what one plane hides, another shows.",
			"Anything can be hidden. Nothing can be hidden four times.") \
		.needs(QuestObjective.observe_plane(&"south_face", 2)
			.described("Face South at the shrine — the sigil is only there from South")) \
		.needs(QuestObjective.shifts(10).described("Search the layers behind the shrine wall")) \
		.needs(QuestObjective.mine(&"", 30).described("Open the false chamber")) \
		.needs(QuestObjective.flips(8).described("Check every face before you trust the room")) \
		.needs(QuestObjective.explore(&"blind_treasury").described("Find the South Shrine").as_optional()) \
		.pays(800).pays_reputation(PROTECTORATE, 14).pays_tech(&"phase_step") \
		.sets_flag("shrine_south").unlocks_quest("main_07_shrine_east") \
		.with_dialogue("keeper_south") \
		.says(
			"KEEPER OF THE SOUTH: You are looking directly at me and you cannot see me. Turn South. Go on.\n\n...There. Now I exist.\n\nThat is my entire teaching and you may leave whenever you like. Anything can be hidden from one face. A door. A vault. An army. A grave. You put it where the geometry of a single plane cannot resolve it, and to a one-faced creature it is simply not there — not concealed, not disguised, *absent*.\n\nSo: never trust a room you have only seen from one side. Never trust a floor you have not looked at from the side. And when a thing seems to have vanished, it has not vanished, you have merely stopped being able to have it. Look again from somewhere else.",
			"KEEPER OF THE SOUTH: You found the false chamber. Most do not. Most stand in the antechamber, see four walls, and write in their little logs that the shrine is empty.\n\nThe Cartographer relies on that, you know. It does not destroy what it does not want found. It simply flattens the world until there is only one face left to look from, and then everything inconvenient is nowhere. It is a very tidy kind of murder.\n\nTake the South sigil. And stop trusting your eyes; they are only pointed one way.")


static func _ch7() -> void:
	Quests.define("main_07_shrine_east", "Shrine of the East — The Fourfold").as_main(7) \
		.from_npc(&"keeper_east", "Keeper of the East").completes_instantly().at_threat(5) \
		.after("main_06_shrine_south") \
		.described("The East Keeper teaches the two moves together: turn, step, turn, step.",
			"Four faces and every depth between them. That is a road.") \
		.needs(QuestObjective.observe_plane(&"east_face", 3)
			.described("Face East at the shrine")) \
		.needs(QuestObjective.flips(16).described("Turn sixteen times inside the lattice")) \
		.needs(QuestObjective.shifts(16).described("Step sixteen layers inside the lattice")) \
		.needs(QuestObjective.explore(&"depth_labyrinth").described("Find the East Shrine").as_optional()) \
		.pays(1000).pays_reputation(PROTECTORATE, 16).pays_tech(&"plane_lattice") \
		.sets_flag("shrine_east").unlocks_quest("main_08_fourfold") \
		.with_dialogue("keeper_east") \
		.says(
			"KEEPER OF THE EAST: My siblings each gave you half a thing. North gave you the turn. West gave you the step. South gave you the reason to bother. None of them gave you the road.\n\nThe road is this: turn to find a face where the way is open, step until it closes, turn again. Not turn-then-step as two separate ideas you keep in separate pockets — one motion, in and around, like a screw going into wood. That is how the gate network moved people between stars before anyone thought to build engines. Not through space. *Around* it.\n\nThis lattice will not let you leave until you can do it without thinking. I have all the time there is. Begin.",
			"KEEPER OF THE EAST: You came out of the far side of the lattice in under an hour. The last one took nine years and left through the entrance, weeping.\n\nTake the East sigil. You now hold four. Bring them to the gateway and the Fourfold will re-bind, and this world will remember that it has more than one face, and the thing that flattened it will feel that happen the way you would feel a tooth break.\n\nIt will come. It always comes. Be somewhere sensible when it does.")


# =========================================================================
static func _ch8() -> void:
	Quests.define("main_08_fourfold", "The Fourfold Key").as_main(8) \
		.from_npc(&"ovid", "Curator Ovid").completes_instantly().at_threat(6) \
		.after("main_07_shrine_east") \
		.needs_flag("shrine_north").needs_flag("shrine_west") \
		.needs_flag("shrine_south").needs_flag("shrine_east") \
		.described("Bind the four sigils at the gateway and wake something that would rather stay asleep.",
			"You are about to make a very large machine notice you.") \
		.needs(QuestObjective.observe_plane(&"bind_north", 0).described("Bind the North sigil: face North")) \
		.needs(QuestObjective.observe_plane(&"bind_west", 1).described("Bind the West sigil: face West")) \
		.needs(QuestObjective.observe_plane(&"bind_south", 2).described("Bind the South sigil: face South")) \
		.needs(QuestObjective.observe_plane(&"bind_east", 3).described("Bind the East sigil: face East")) \
		.needs(QuestObjective.survive(45.0, &"binding")
			.described("Hold the binding for 45 seconds")) \
		.needs(QuestObjective.explore(&"plane_lock_vault")
			.described("Stand in the Fourfold Lock").as_optional()) \
		.pays(1200).pays_reputation(PROTECTORATE, 20) \
		.sets_flag("fourfold_bound").unlocks_quest("main_09_cartographer") \
		.with_dialogue("ovid_ch8") \
		.says(
			"CURATOR OVID: Four sigils. Four faces. One plinth. Even I can follow this arithmetic and I was assembled to file things.\n\nStand at the plinth and give it each face in turn — North, West, South, East — and then, and this is the part I would like on the record as 'not my idea', you must simply stand there while the binding takes. Forty-five seconds. It will feel considerably longer, because the gate will be pulling four versions of this room through the same doorway and you will be standing in all of them.\n\nDo not turn during the hold. I cannot stress this enough. Do not be clever.",
			"CURATOR OVID: It is bound. It is bound! Nine hundred and forty years and I — \n\nOh.\n\nThe gate is showing me something. It is showing me a survey. Every world it has ever connected, and beside each one a little mark, and the mark means *resolved*. Flattened. Indexed. Filed.\n\nThere are eleven thousand of them and the newest mark is this one, and it is not finished, and it has just noticed that we un-marked it.\n\nIt is coming up through the floor. From a direction the floor does not have.")


static func _ch9() -> void:
	Quests.define("main_09_cartographer", "The Cartographer").as_main(9) \
		.from_npc(&"axis", "AXIS").completes_instantly().at_threat(8) \
		.after("main_08_fourfold") \
		.described("Survive the thing that flattens worlds. You will not beat it by standing still.",
			"It can only hold you if you agree to have one face.") \
		.needs(QuestObjective.survive(150.0, &"cartographer_duel")
			.described("Outlast the Cartographer — 150 seconds")) \
		.needs(QuestObjective.flips(20).described("Refuse to be pinned: turn twenty times")) \
		.needs(QuestObjective.shifts(12).described("Refuse to be found: step twelve layers")) \
		.needs(QuestObjective.kill(&"cartographer", 1)
			.described("Unmake the Cartographer's core").as_optional()) \
		.fails_on(QuestDef.Fail.PLAYER_DEATH) \
		.pays(2500).pays_reputation(PROTECTORATE, 30).pays_tech(&"fourfold_step") \
		.sets_flag("cartographer_broken").unlocks_quest("main_10_ftl") \
		.branch("unmade", {"type": "flag", "flag": "cartographer_core_destroyed"},
			"The core is gone. Whatever it filed, it filed for the last time.", 1000) \
		.branch("outlasted", null,
			"It withdrew. Not defeated — declined. That will have to do for today.", 0) \
		.with_dialogue("cartographer") \
		.says(
			"THE CARTOGRAPHER: You are an unresolved feature.\n\nI have surveyed eleven thousand and six worlds. Each of them had four faces when I arrived and one face when I left, and every one of them is now legible — a flat thing, a map, a page that stays where it is put. You cannot imagine how restful that is. You cannot imagine the noise a four-faced world makes.\n\nHold still. Choose a face. Any of them; I am not cruel, I only require that you choose one and keep it. It takes a moment. Most of them are grateful, afterwards, to be simple.\n\nAXIS: Do not hold still. Do you hear me? Do NOT hold still. It can only pin what agrees to have a single side. Turn. Keep turning. Step through the layers. Be four things at once and it cannot file you.",
			"AXIS: It has gone. Not dead, I think — *declined*. It let go of this world the way you would drop something that turned out to be hot.\n\nThe planet has four faces again. I can feel it in the astrogation tables; they were nonsense an hour ago and now they are merely difficult.\n\nCome home. I know what the drive needs now.")


static func _ch10() -> void:
	Quests.define("main_10_ftl", "The Drive Remembers").as_main(10) \
		.from_npc(&"axis", "AXIS").completes_instantly().at_threat(6) \
		.after("main_09_cartographer") \
		.described("Rebuild the FTL drive on Fourfold principles and leave this rock.",
			"Not through space. Around it.") \
		.needs(QuestObjective.collect(&"", 60).described("Gather 60 items of drive material")) \
		.needs(QuestObjective.mine(&"", 80).described("Cut 80 blocks of ore and stone")) \
		.needs(QuestObjective.craft(&"", 3).described("Fabricate 3 components")) \
		.needs(QuestObjective.flips(4).described("Align the drive across all four faces")) \
		.needs(QuestObjective.visit(&"").described("Make the jump — go anywhere at all")) \
		.pays(3000).pays_reputation(PROTECTORATE, 40).pays_tech(&"fourfold_drive") \
		.sets_flag("ftl_restored") \
		.with_dialogue("axis_ch10") \
		.says(
			"AXIS: I have been thinking about my own failure for some weeks now and I owe the drive an apology.\n\nIt never broke. It was built to move us around space by borrowing a face this world was not currently using, and the Cartographer took all the spare faces away, and my drive did the only honest thing available to it: it stopped.\n\nSo. Rebuild it, but rebuild it knowing what it actually does. Material, ore, three fabricated components, and then — this will feel absurd, humour me — align it by standing at the core and turning through all four faces while it spools. The drive needs to be told, by something that understands it, that this world has more than one side again.\n\nThen we jump. Anywhere. I do not care where. I would like to be *choosing* a direction for once.",
			"AXIS: Jump complete. Drift: four metres. Four metres, after nine hundred years of a network nobody has flown.\n\nI want to say something appropriate and I find I have nothing in my libraries that fits, so I will simply state the facts. There are eleven thousand and five worlds still carrying that mark. They each have one face and they should have four. We have a drive that works on principles the thing which flattened them does not want anyone to remember.\n\nSet a course, Protector. Let us go and be very rude to it again.")
