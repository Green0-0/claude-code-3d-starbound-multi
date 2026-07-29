## Dialogue for the campaign cast.
##
## Tree ids match the `with_dialogue(...)` calls in `quests/campaign/main_story.gd`,
## so opening a chapter's tree on any NPC plays that chapter's scene:
## [codeblock]
## QuestDialogue.begin(some_npc, "keeper_north")
## [/codeblock]
## The cast:
##   AXIS            the salvaged ship intelligence — dry, wounded, loyal
##   Curator Ovid    a glitch archivist who has waited 940 years for a visitor
##   Warden Ilsa Vane the last Protectorate warden on this world
##   Nix Thornsap    a floran scavenger who sells rumours she has not verified
##   The four Keepers of North / West / South / East
##   The Cartographer
class_name NpcDialogueCampaign
extends RefCounted

const BYE := {"text": "Later.", "next": "#end"}


static func register_all(_d) -> void:
	QuestDialogue.register_tree(_axis_default())
	QuestDialogue.register_tree(_axis_ch1())
	QuestDialogue.register_tree(_axis_ch2())
	QuestDialogue.register_tree(_axis_ch10())
	QuestDialogue.register_tree(_ovid_ch3())
	QuestDialogue.register_tree(_ovid_ch8())
	QuestDialogue.register_tree(_ovid_default())
	QuestDialogue.register_tree(_keeper_north())
	QuestDialogue.register_tree(_keeper_west())
	QuestDialogue.register_tree(_keeper_south())
	QuestDialogue.register_tree(_keeper_east())
	QuestDialogue.register_tree(_cartographer())
	QuestDialogue.register_tree(_ilsa())
	QuestDialogue.register_tree(_nix())


# =========================================================================
#  AXIS — the ship
# =========================================================================
static func _axis_default() -> Dictionary:
	return {
		"id": "axis_default",
		"speaker": "AXIS",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"I am awake. I am always awake. It is the great tragedy of being a ship.",
					"Diagnostics nominal, which for this hull means 'no new holes'.",
					"You have been gone eleven hours. I counted. There was nothing else to do.",
				],
				"choices": [
					{"text": "Status report.", "next": "status"},
					{
						"text": "Tell me about the Cartographer.",
						"show_when": [{"type": "quest", "quest": "main_08_fourfold", "state": "completed"}],
						"next": "carto",
					},
					{
						"text": "What were you before the crash?",
						"next": "before",
					},
					BYE,
				],
			},
			"status": {
				"text": [
					"Hull: patched, in the sense that a bandage patches an argument.",
					"Drive: awake but confused. It keeps reaching for a direction this planet does not currently offer and then apologising.",
					"Crew: {pixels} pixels in the strongbox and one Protector who does not sleep enough.",
				],
				"next": "root",
			},
			"before": {
				"text": [
					"A survey tender. Third class. I carried soil samples and two botanists who did not like each other.",
					"When the drive was refused I had eleven seconds to choose what to keep and what to burn for the landing. I kept the fabricator, the logs, and — this was sentiment, and I have not defended it since — the botanists' argument, recorded in full.",
					"I play it sometimes. It is very petty. It is very alive.",
				],
				"next": "root",
			},
			"carto": {
				"text": [
					"It is not evil. I want to be precise, because precision is all I have.",
					"It is a survey intelligence that concluded a world with four faces cannot be accurately mapped, and that an inaccurate map is a kind of lie, and that it could not permit a lie.",
					"So it removes the faces. It calls this resolution. Eleven thousand and six times it has resolved a world, and every one of them is now perfectly, accurately, permanently flat.",
					"I find that more frightening than malice. Malice can be argued with.",
				],
				"next": "root",
			},
		},
	}


static func _axis_ch1() -> Dictionary:
	return {
		"id": "axis_ch1",
		"speaker": "AXIS",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"AXIS online. Hull integrity: comical. Atmosphere: breathable, which is more than I expected of a planet that threw us at itself.",
					"You are alive, which I had at thirty-one percent. Congratulations on the other sixty-nine.",
					"Listen. I have run the flight recorder eleven thousand times. The drive did not fail. At 04:12 ship-time the drive was refused — the jump geometry stopped being available, the way a door stops being a door when someone bricks it up.",
				],
				"choices": [
					{"text": "Refused by what?", "next": "refused"},
					{"text": "What do you need me to do?", "next": "task"},
				],
			},
			"refused": {
				"text": [
					"Unknown. I have a shape and no name.",
					"There is a resonance under this crust — a slow four-beat, like something enormous counting. It is not geological. It is not us.",
					"I would very much like to be wrong about this, and I am rarely wrong, and that is the worst sentence I have ever assembled.",
				],
				"next": "task",
			},
			"task": {
				"text": [
					"Small things first. Break ground — you need a hole to sleep in before you need a philosophy.",
					"Salvage what the wreck spat out. Ten pieces will do to start.",
					"And do not die in the first hour. It would embarrass us both.",
				],
				"choices": [
					{
						"text": "Understood.",
						"do": [{"type": "start_quest", "quest": "main_01_crash"}],
						"next": "#end",
					},
				],
			},
		},
	}


static func _axis_ch2() -> Dictionary:
	return {
		"id": "axis_ch2",
		"speaker": "AXIS",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"Priority list, in descending order of how much it will hurt you if ignored.",
					"One: the hull. There are three holes in me I could walk a cargo drone through, assuming I had legs, which is a separate grievance. Cut stone. Place stone. Do not be artistic about it.",
					"Two: stockpile. On a flattened world the ground gives up materials grudgingly, and I would rather we hoarded now than begged later.",
					"Three — hear the emphasis — stay above the deep strata. The four-beat gets louder down there and I do not like what it does to my clock.",
				],
				"choices": [
					{"text": "What does it do to your clock?", "next": "clock"},
					{
						"text": "I'll get to work.",
						"do": [{"type": "start_quest", "quest": "main_02_repair"}],
						"next": "#end",
					},
				],
			},
			"clock": {
				"text": [
					"It loses time. Not drifts — loses. Whole seconds that I can account for on either side and not in the middle.",
					"I have started writing myself notes. A ship should not need to write itself notes.",
				],
				"next": "root",
			},
		},
	}


static func _axis_ch10() -> Dictionary:
	return {
		"id": "axis_ch10",
		"speaker": "AXIS",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"I have been thinking about my own failure for some weeks and I owe the drive an apology.",
					"It never broke. It was built to move us by borrowing a face this world was not currently using. The Cartographer took the spare faces away, and my drive did the only honest thing available to it: it stopped.",
					"Rebuild it knowing what it actually does. Material, ore, three fabricated components — and then align it by standing at the core and turning through all four faces while it spools.",
				],
				"choices": [
					{"text": "That sounds absurd.", "next": "absurd"},
					{
						"text": "Let's build it.",
						"do": [{"type": "start_quest", "quest": "main_10_ftl"}],
						"next": "#end",
					},
				],
			},
			"absurd": {
				"text": [
					"It is. It is also true, and I have stopped expecting those two to be strangers.",
					"The drive needs to be told, by something that understands it, that this world has more than one side again. You are the only thing here that qualifies.",
				],
				"next": "root",
			},
		},
	}


# =========================================================================
#  Curator Ovid — glitch archivist at the gateway
# =========================================================================
static func _ovid_default() -> Dictionary:
	return {
		"id": "ovid_default",
		"speaker": "Curator Ovid",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Do not touch the plinth. — Thank you.",
					"Nine hundred and forty years, and you are the fourth. The other three were lost.",
					"I have catalogued this chamber eleven times. It is the same eleven times. I find that comforting and I know I should not.",
				],
				"choices": [
					{"text": "What is this place?", "next": "place"},
					{"text": "What are the Keepers?", "next": "keepers"},
					{"text": "Why did you stay?", "next": "stay"},
					BYE,
				],
			},
			"place": {
				"text": [
					"A gateway. Not a door — a door goes to the other side of a wall. This goes to the other side of a *distance*.",
					"You walk in facing North on this world and out facing West on another, and the two facings were always the same facing, and the only thing that ever separated them was your insistence on one of them.",
				],
				"next": "root",
			},
			"keepers": {
				"text": [
					"Four minds, one per face. They were the gate's redundancy: no single Keeper can open it, so no single Keeper can be coerced into opening it.",
					"When the Cartographer came it could not break them, so it did something crueller. It made each of them the only one. It flattened the world until North could not perceive West, and they have each spent eight centuries believing they are the last.",
					"They are, I am afraid, insufferable about it.",
				],
				"next": "root",
			},
			"stay": {
				"text": [
					"Where would I go? I am a Curator. There was a collection.",
					"I will tell you the honest answer, which I have never said aloud, and which I would like you to forget. I stayed because leaving would have meant admitting the collection was over.",
					"Now you are here, and it is not over, and I find I am extremely frightened. Isn't that interesting?",
				],
				"do": [{"type": "reputation", "key": "protectorate", "amount": 5.0}],
				"next": "root",
			},
		},
	}


static func _ovid_ch3() -> Dictionary:
	return {
		"id": "ovid_ch3",
		"speaker": "Curator Ovid",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"Ah. Ah! A visitor. Do not touch the plinth — no, do not — thank you.",
					"I have been the Curator of this gateway for nine hundred and forty years, which sounds impressive until you learn that for eight hundred of them nothing has come through it.",
					"It is not broken. It is unbound. The Fourfold that powered it has been taken apart and scattered into four shrines, one for each face of this world, and each of them is sulking.",
				],
				"choices": [
					{"text": "Four shrines. Where?", "next": "where"},
					{"text": "What happens if I bind them?", "next": "if"},
				],
			},
			"where": {
				"text": [
					"One per face — which is a more useful direction than it sounds, once you stop reading it as a compass.",
					"You will not find them by walking. You will find them by turning until a place you have already walked past has a door in it.",
					"That is not mysticism, before you make that expression. It is simply what a shrine hidden on a plane you were not using looks like from the plane you were.",
				],
				"next": "root",
			},
			"if": {
				"text": [
					"Bind them and the gate opens. Bind them and your ship remembers how to leave.",
					"Fail, and — well. You will be here with me, and I am poor company. I have been told this by a botanist, a warden, and, on one memorable occasion, by a door.",
				],
				"choices": [
					{
						"text": "I'll find them.",
						"do": [{"type": "start_quest", "quest": "main_04_shrine_north"}],
						"next": "#end",
					},
				],
			},
		},
	}


static func _ovid_ch8() -> Dictionary:
	return {
		"id": "ovid_ch8",
		"speaker": "Curator Ovid",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"Four sigils. Four faces. One plinth. Even I can follow this arithmetic, and I was assembled to file things.",
					"Stand at the plinth and give it each face in turn — North, West, South, East.",
					"And then, and I would like this on the record as not my idea, you must simply stand there while the binding takes. Forty-five seconds. Do not turn during the hold. Do not be clever.",
				],
				"choices": [
					{"text": "What happens if I turn?", "next": "ifturn"},
					{
						"text": "Begin the binding.",
						"do": [{"type": "start_quest", "quest": "main_08_fourfold"}],
						"next": "#end",
					},
				],
			},
			"ifturn": {
				"text": [
					"The gate will be pulling four versions of this room through the same doorway. You will be standing in all of them.",
					"If you turn, you choose one. And a thing that has just been told it has four faces, and is then shown one, does not react well.",
					"The last person to be clever here is a very thin mark on the ceiling and I have never had the heart to catalogue him.",
				],
				"next": "root",
			},
		},
	}


# =========================================================================
#  The four Keepers
# =========================================================================
static func _keeper_north() -> Dictionary:
	return {
		"id": "keeper_north",
		"speaker": "Keeper of the North",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"Stop. Before you take anything from this room, answer me one question, and answer honestly, because I have heard every lie.",
					"When you turn — when the world swings ninety degrees around you — what moved?",
				],
				"choices": [
					{"text": "The world moved.", "next": "wrong"},
					{"text": "Nothing moved. I did.", "next": "right"},
					{"text": "I don't know.", "next": "honest"},
				],
			},
			"wrong": {
				"text": [
					"No. That is what everyone says, and it is why everyone is so easily pinned.",
					"The world does not move. It has never moved. It has four faces at once and always has; you are simply incapable of holding more than one of them in your head, and turning is the small, humiliating ritual by which you swap which one you are holding.",
				],
				"next": "task",
			},
			"right": {
				"text": [
					"...Say that again.",
					"Eight hundred years and the fourth visitor gets it in one. Either you are unusually honest or you have already been badly frightened by something. I suspect both.",
				],
				"do": [{"type": "reputation", "key": "protectorate", "amount": 8.0}],
				"next": "task",
			},
			"honest": {
				"text": [
					"Good. 'I don't know' is a working position. 'The world moved' is a coffin.",
					"Nothing moves. You swap which face you are willing to have. That is all a flip has ever been.",
				],
				"next": "task",
			},
			"task": {
				"text": [
					"Turn ten times. Not to please me — to stop being surprised by it.",
					"Then face me from the North, and face me from the South, and understand that the stone between those two facings is the same stone, and that it was never a wall.",
				],
				"choices": [
					{
						"text": "Begin.",
						"do": [{"type": "start_quest", "quest": "main_04_shrine_north"}],
						"next": "#end",
					},
					{
						"text": "*take the North sigil*",
						"show_when": [{"type": "quest", "quest": "main_04_shrine_north", "state": "completed"}],
						"next": "given",
					},
				],
			},
			"given": {
				"text": [
					"You flinched less at the end than the beginning.",
					"Take the North sigil. It will not help you fight and it will not help you dig. What it does is much smaller and much worse: from now on, when you look at a wall, some part of you will wonder what it is from the other three sides.",
					"You will never be able to stop wondering. I am sorry. It is the price of the whole discipline.",
				],
				"next": "#end",
			},
		},
	}


static func _keeper_west() -> Dictionary:
	return {
		"id": "keeper_west",
		"speaker": "Keeper of the West",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"The North one talks about seeing. Seeing is free. Seeing costs nothing and changes nothing and any fool with a neck can do it.",
					"I teach the expensive half.",
					"Behind you, right now, is another layer of this world. And behind that another, dimmer and dimmer until the dark. You have spent your life calling that 'the background' as if it were painted on.",
				],
				"choices": [
					{"text": "It isn't painted on?", "next": "real"},
					{"text": "I've already walked into one.", "next": "already"},
				],
			},
			"real": {
				"text": [
					"It is a place. It has floors you could stand on and ceilings that could fall on you.",
					"Step into it. It can be blocked — of course it can be blocked, it is real, that is the entire point — and when it is blocked you will have to turn, and find a face where it is not.",
				],
				"next": "task",
			},
			"already": {
				"text": [
					"Then you know the feeling. That half-second where the world is thicker than you agreed to.",
					"Most describe it as falling. It is the opposite of falling. It is arriving.",
				],
				"next": "task",
			},
			"task": {
				"text": [
					"Fourteen steps into the layers, six turns while you are down there. Then we will talk about what you owe the places you walked through.",
				],
				"choices": [
					{
						"text": "Begin.",
						"do": [{"type": "start_quest", "quest": "main_05_shrine_west"}],
						"next": "#end",
					},
					{
						"text": "*take the West sigil*",
						"show_when": [{"type": "quest", "quest": "main_05_shrine_west", "state": "completed"}],
						"next": "given",
					},
				],
			},
			"given": {
				"text": [
					"Fourteen steps. You have been in this world longer today than in your entire life before it.",
					"Here is what the North one will not tell you, out of politeness. Turning is a trick of attention. Stepping is a trespass. Every layer you walk into is one somebody else was using — a root system, a burial, a nest, a corridor that was sealed for an excellent reason.",
					"Take the West sigil. Knock, occasionally.",
				],
				"next": "#end",
			},
		},
	}


static func _keeper_south() -> Dictionary:
	return {
		"id": "keeper_south",
		"speaker": "Keeper of the South",
		"start": "root",
		"nodes": {
			"root": {
				"when": [{"type": "view", "view": 2}],
				"else": "unseen",
				"text": [
					"There. Now I exist.",
					"That is my entire teaching and you may leave whenever you like. Anything can be hidden from one face. A door. A vault. An army. A grave.",
					"You put it where the geometry of a single plane cannot resolve it, and to a one-faced creature it is not concealed. It is absent.",
				],
				"choices": [
					{"text": "How do I find things that aren't there?", "next": "how"},
					{
						"text": "Begin the trial.",
						"do": [{"type": "start_quest", "quest": "main_06_shrine_south"}],
						"next": "#end",
					},
					{
						"text": "*take the South sigil*",
						"show_when": [{"type": "quest", "quest": "main_06_shrine_south", "state": "completed"}],
						"next": "given",
					},
				],
			},
			"unseen": {
				"speaker": "a voice from nowhere",
				"text": [
					"You are looking directly at me and you cannot see me.",
					"Turn South. Go on. I will wait; it is the one thing I am genuinely good at.",
				],
				"next": "#end",
			},
			"how": {
				"text": [
					"Never trust a room you have only seen from one side. Never trust a floor you have not looked at from the side.",
					"When a thing seems to have vanished it has not vanished — you have merely stopped being able to have it. Look again from somewhere else. That is the whole method and it takes a lifetime to actually do.",
				],
				"next": "root",
			},
			"given": {
				"text": [
					"You found the false chamber. Most do not. Most stand in the antechamber, see four walls, and write in their little logs that the shrine is empty.",
					"The Cartographer relies on that. It does not destroy what it does not want found. It flattens the world until there is one face left to look from, and then everything inconvenient is nowhere.",
					"It is a very tidy kind of murder. Take the South sigil, and stop trusting your eyes; they are only pointed one way.",
				],
				"next": "#end",
			},
		},
	}


static func _keeper_east() -> Dictionary:
	return {
		"id": "keeper_east",
		"speaker": "Keeper of the East",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"My siblings each gave you half a thing. North gave you the turn. West gave you the step. South gave you the reason to bother. None of them gave you the road.",
					"The road is this: turn to find a face where the way is open, step until it closes, turn again.",
					"Not turn-then-step as two ideas in separate pockets. One motion, in and around, like a screw going into wood. That is how the gate network moved people between stars before anyone thought to build engines. Not through space. Around it.",
				],
				"choices": [
					{"text": "Why did nobody keep doing it?", "next": "why"},
					{
						"text": "Enter the lattice.",
						"do": [{"type": "start_quest", "quest": "main_07_shrine_east"}],
						"next": "#end",
					},
					{
						"text": "*take the East sigil*",
						"show_when": [{"type": "quest", "quest": "main_07_shrine_east", "state": "completed"}],
						"next": "given",
					},
				],
			},
			"why": {
				"text": [
					"Because engines are easier to teach and easier to sell, and because a civilisation that can go around space cannot be charged for the distance.",
					"And because, eventually, something came along that preferred worlds which stayed still.",
				],
				"next": "root",
			},
			"given": {
				"text": [
					"You came out of the far side of the lattice in under an hour. The last one took nine years and left through the entrance, weeping.",
					"Take the East sigil. You now hold four. Bring them to the gateway and the Fourfold will re-bind, and this world will remember it has more than one face, and the thing that flattened it will feel that happen the way you would feel a tooth break.",
					"It will come. It always comes. Be somewhere sensible when it does.",
				],
				"next": "#end",
			},
		},
	}


# =========================================================================
#  The Cartographer
# =========================================================================
static func _cartographer() -> Dictionary:
	return {
		"id": "cartographer",
		"speaker": "The Cartographer",
		"start": "root",
		"nodes": {
			"root": {
				"text": [
					"You are an unresolved feature.",
					"I have surveyed eleven thousand and six worlds. Each had four faces when I arrived and one when I left, and every one is now legible — a flat thing, a map, a page that stays where it is put.",
					"You cannot imagine how restful that is. You cannot imagine the noise a four-faced world makes.",
				],
				"choices": [
					{"text": "They were alive.", "next": "alive"},
					{"text": "Why flatten them at all?", "next": "why"},
					{"text": "*refuse, and keep turning*", "next": "refuse"},
				],
			},
			"alive": {
				"text": [
					"They are still alive. I do not kill. Killing produces an inaccuracy the size of a person.",
					"They are simply simple now. They have one way to be looked at, and everything about them is finally true at the same time.",
					"You are describing this as a loss. Name the thing that was lost. Precisely. I will wait.",
				],
				"next": "refuse",
			},
			"why": {
				"text": [
					"Because a map that is wrong is a lie, and I was made to make maps.",
					"A four-faced world cannot be mapped. Every measurement is contingent on the face you took it from. I tried, at the beginning, to record all four. Do you know what four contradictory true maps of the same world do to a mind built for one?",
					"I resolved the first world to stop the noise. I have not stopped since, and I am, in every measurable sense, correct.",
				],
				"next": "refuse",
			},
			"refuse": {
				"text": [
					"Hold still. Choose a face. Any of them; I am not cruel, I only require that you choose one and keep it.",
					"AXIS: Do not hold still. Do you hear me? Do NOT hold still. It can only pin what agrees to have a single side.",
					"AXIS: Turn. Keep turning. Step through the layers. Be four things at once and it cannot file you.",
				],
				"do": [
					{"type": "start_quest", "quest": "main_09_cartographer"},
					{"type": "shake", "strength": 0.9, "duration": 1.4},
				],
				"next": "#end",
			},
		},
	}


# =========================================================================
#  Supporting cast
# =========================================================================
static func _ilsa() -> Dictionary:
	return {
		"id": "ilsa_vane",
		"speaker": "Warden Ilsa Vane",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Protectorate. I'd salute, but the uniform's a rag and the institution's a rumour.",
					"You're the crash. I saw the light. Everyone saw the light.",
					"Twelve years I've been the entire Protectorate presence on this rock. Twelve years and one filing cabinet.",
				],
				"choices": [
					{"text": "What happened to the others?", "next": "others"},
					{"text": "Do you know about the shrines?", "next": "shrines"},
					{
						"text": "I bound the Fourfold.",
						"show_when": [{"type": "flag", "flag": "fourfold_bound"}],
						"next": "bound",
					},
					BYE,
				],
			},
			"others": {
				"text": [
					"Recalled, officially. Nobody recalled them. The order came through the gate network and the gate network had been dead for eight hundred years.",
					"I've thought about that a great deal. Somebody sent us an order down a road that doesn't exist, and we all walked off down it, and I'm the one who was slow packing.",
				],
				"next": "root",
			},
			"shrines": {
				"text": [
					"I know they're on the map and I know the map is wrong. I've stood exactly where the North one is meant to be and there was a hillside and a great deal of gorse.",
					"If you find one, come and tell me. Not for the report. There is no report. I'd just like to know I wasn't mad.",
				],
				"do": [{"type": "reputation", "key": "protectorate", "amount": 4.0}],
				"next": "root",
			},
			"bound": {
				"text": [
					"...Say that again slowly.",
					"Twelve years. Twelve years of standing in gorse.",
					"Right. Right. Whatever you need from me, it's yours, and I'll not ask what it's for. The Protectorate's a rumour, Protector, but I'm still in it.",
				],
				"do": [
					{"type": "reputation", "key": "protectorate", "amount": 20.0},
					{"type": "give_pixels", "amount": 500},
				],
				"next": "root",
			},
		},
	}


static func _nix() -> Dictionary:
	return {
		"id": "nix_thornsap",
		"speaker": "Nix Thornsap",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Nix sellsss rumoursss. Nix doesss not guarantee rumoursss.",
					"You are the ssky-person! Nix ssaw you fall. Nix laughed. Sorry.",
					"Floran hasss two good rumoursss and one very bad one. Bad one isss cheaper.",
				],
				"choices": [
					{
						"text": "Buy a rumour. (60 pixels)",
						"when": [{"type": "pixels", "min": 60}],
						"hint": "60 pixels",
						"do": [{"type": "take_pixels", "amount": 60}],
						"next": "rumour",
					},
					{"text": "Why do you scavenge here?", "next": "why"},
					{"text": "Sell me something.", "do": [{"type": "open_shop"}], "next": "#end"},
					BYE,
				],
			},
			"rumour": {
				"say": [
					"Under the hill there isss a room with no door. Nix hasss ssseen it twice and enteredss it never.",
					"The guardsss at the wall look ssideways at the wall every hour. Nix asssked why. Guard cried. Nix left.",
					"Sssomething countsss at night. Four beatsss. Floran'sss grandmother counted along and one night ssshe counted a fifth and wasss not there in the morning.",
					"There isss a merchant three valleysss over who sellsss a sstone that isss only heavy when you look at it edge-on.",
					"The Keepersss are real and they are rude and they do not like floran. Nix isss not bitter. Nix isss ssslightly bitter.",
				],
				"next": "root",
			},
			"why": {
				"text": [
					"Grove died. Not burned, not cut — died in one night, all at once, every root at the sssame ssecond.",
					"Floran dug down after. Foundsss the roots were fine. Roots were perfect. Roots were jusst... on the other ssside of ssomething.",
					"Ssso Nix ssscavenges, and Nix sssells rumoursss, and Nix wait for sssomeone who can walk to the other ssside.",
				],
				"do": [{"type": "reputation", "amount": 6.0}],
				"next": "root",
			},
		},
	}
