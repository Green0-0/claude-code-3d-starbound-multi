## Dialogue for every NPC role. Loaded automatically by [QuestDialogue].
##
## Conventions used throughout:
##  * `show_when` hides a choice entirely; `when` greys it out with a `hint`.
##  * `#end` closes the window.
##  * `{npc}` `{village}` `{planet}` `{time}` `{pixels}` expand at read time.
##  * `text` is one line, or an array of pages the player clicks through.
##  * `say` is a bank of interchangeable one-liners; one is picked at random.
class_name NpcDialogueRoles
extends RefCounted

# Reusable choice fragments, so every role offers work and trade identically.
const CHOICE_WORK := {
	"text": "Got any work going?",
	"show_when": [{"type": "has_work"}],
	"do": [{"type": "offer_work"}],
	"next": "work_offered",
}
const CHOICE_TURN_IN := {
	"text": "About that job — it's done.",
	"show_when": [{"type": "turn_in_ready"}],
	"do": [{"type": "turn_in"}],
	"next": "thanks",
}
const CHOICE_SHOP := {
	"text": "Show me what you've got.",
	"show_when": [{"type": "sells"}],
	"when": [{"type": "reputation", "min": -39.0}],
	"hint": "they won't trade with you",
	"do": [{"type": "open_shop"}],
	"next": "#end",
}
const CHOICE_BYE := {"text": "Another time.", "next": "#end"}

const NODE_WORK_OFFERED := {
	"text": [
		"Right. Details are on the notice — read it before you agree to it.",
		"I'll be here when it's done. I'm always here.",
	],
	"next": "root",
}
const NODE_THANKS := {
	"say": [
		"That's the one. You've a knack for this.",
		"Faster than I'd have managed. Take your cut.",
		"Well. I'll stop doubting off-worlders.",
	],
	"next": "root",
}


static func register_all(_d) -> void:
	QuestDialogue.register_tree(_villager())
	QuestDialogue.register_tree(_merchant())
	QuestDialogue.register_tree(_innkeeper())
	QuestDialogue.register_tree(_blacksmith())
	QuestDialogue.register_tree(_doctor())
	QuestDialogue.register_tree(_guard())
	QuestDialogue.register_tree(_scientist())
	QuestDialogue.register_tree(_crew())
	QuestDialogue.register_tree(_trader())


# =========================================================================
static func _villager() -> Dictionary:
	return {
		"id": "villager_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"when": [{"type": "reputation", "min": -39.0}],
				"else": "cold",
				"say": [
					"{village}'s not much, but it's ours. Mind the goats.",
					"You're the one who came down in fire. Everyone's talking about it.",
					"It's {time}. Late for questions, early for answers.",
					"Say what you like about this rock, the soil's honest.",
				],
				"choices": [
					CHOICE_TURN_IN,
					CHOICE_WORK,
					{"text": "Tell me about {village}.", "next": "about"},
					{"text": "Has anything strange happened here?", "next": "strange"},
					{
						"text": "*hand over a gift*",
						"show_when": [{"type": "has_item", "item": "cobblestone", "count": 8}],
						"once": true,
						"do": [
							{"type": "take_item", "item": "cobblestone", "count": 8},
							{"type": "reputation", "amount": 12.0},
							{"type": "notify", "text": "{npc} warms to you.", "kind": "good"},
						],
						"next": "gift",
					},
					CHOICE_BYE,
				],
			},
			"cold": {
				"say": [
					"I've nothing to say to you.",
					"Keep walking. The guards are watching.",
					"You know what you did.",
				],
				"choices": [
					{
						"text": "*apologise, and pay for the trouble*",
						"when": [{"type": "pixels", "min": 200}],
						"hint": "200 pixels",
						"do": [
							{"type": "take_pixels", "amount": 200},
							{"type": "reputation", "amount": 25.0},
						],
						"next": "forgiven",
					},
					{"text": "Fine.", "next": "#end"},
				],
			},
			"forgiven": {
				"text": "...Hm. It doesn't undo it. But it's something. We'll start again.",
				"next": "#end",
			},
			"gift": {
				"text": "Stone? For me? — no, honestly, that's the wall by the well, that is. Thank you.",
				"next": "root",
			},
			"about": {
				"when": [{"type": "race", "race": "floran"}],
				"else": "about_general",
				"text": [
					"{village}? Ssmells of wet wood and old peoplesss. Isss good. Quiet.",
					"Floran came here becausse the grove wasss dying. Floran ssstayed becausse nobody assked usss to leave.",
				],
				"next": "root",
			},
			"about_general": {
				"text": [
					"Forty of us on a good year. Fewer, lately.",
					"There's a shrine out past the fields that nobody built and nobody can date. Kids dare each other to sleep in it. Nobody ever does twice.",
				],
				"next": "root",
			},
			"strange": {
				"when": [{"type": "time", "night": true}],
				"else": "strange_day",
				"text": [
					"At night? Everything. Listen — no, properly listen.",
					"There. That's not wind. My grandmother called it the counting.",
					"She said the world used to have more sides to it, and something came and took three of them away, and the counting is it checking they're still gone.",
				],
				"next": "root",
			},
			"strange_day": {
				"text": [
					"Strange? Depends what you're used to.",
					"Old Bel swears a doorway in her cellar wall opens when you stand side-on to it. We all nod and say yes, Bel.",
					"Mind you. Nobody's ever actually stood side-on to it.",
				],
				"next": "root",
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _merchant() -> Dictionary:
	return {
		"id": "merchant_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"when": [{"type": "reputation", "min": -39.0}],
				"else": "refused",
				"say": [
					"Everything you can see is for sale. Most of what you can't, too.",
					"Prices are fair. Fair to me, obviously, but fair.",
					"You've got {pixels} pixels on you. I can tell. It's a gift.",
				],
				"choices": [
					CHOICE_SHOP,
					CHOICE_TURN_IN,
					CHOICE_WORK,
					{"text": "Where does your stock come from?", "next": "sourcing"},
					{
						"text": "Any discount for a friend?",
						"show_when": [{"type": "reputation", "min": 40.0}],
						"next": "discount",
					},
					CHOICE_BYE,
				],
			},
			"refused": {
				"text": "I don't trade with people who hurt my neighbours. Get off my step.",
				"next": "#end",
			},
			"sourcing": {
				"text": [
					"Caravans, mostly. Twice a season, if the road holds.",
					"The interesting things come from diggers — people like you, who go down and come back up with something that shouldn't exist.",
					"Bring me anything you can't identify. I'll give you an honest price and a dishonest story about where I got it.",
				],
				"next": "root",
			},
			"discount": {
				"text": "For you? ...Five percent. Don't tell anyone. Don't tell *me*, I'll deny it.",
				"do": [{"type": "reputation", "amount": 2.0}],
				"next": "root",
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _innkeeper() -> Dictionary:
	return {
		"id": "innkeeper_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Sit down before you fall down. It's {time} and you look it.",
					"Room, board, or gossip? I stock all three.",
					"Whatever's on your boots, leave it outside.",
				],
				"choices": [
					{
						"text": "I'd like a room.",
						"when": [{"type": "pixels", "min": 40}],
						"hint": "40 pixels",
						"next": "rent",
					},
					CHOICE_SHOP,
					CHOICE_TURN_IN,
					CHOICE_WORK,
					{"text": "What's the talk?", "next": "gossip"},
					CHOICE_BYE,
				],
			},
			"rent": {
				"text": "Top of the stairs, second door. Don't mind the noise, that's just the counting.",
				"do": [
					{"type": "take_pixels", "amount": 40},
					{"type": "rest", "until": 0.27},
				],
				"next": "morning",
			},
			"morning": {
				"text": "Morning. You slept through the whole of it, which is more than most manage.",
				"next": "root",
			},
			"gossip": {
				"when": [{"type": "quest", "quest": "main_03_gateway", "state": "completed"}],
				"else": "gossip_early",
				"text": [
					"You've been down the hill, haven't you. I can always tell.",
					"People come back from there and they stop looking at walls properly. They look *past* them, like they're checking.",
					"Drink up. It doesn't help but it's traditional.",
				],
				"next": "root",
			},
			"gossip_early": {
				"text": [
					"A digger came through last month. Said he'd found a corridor under the hill that was only there if you stood a certain way.",
					"We laughed at him. He left. Somebody found his pack three fields over with nothing missing.",
					"Now we don't laugh. We just don't talk about it.",
				],
				"next": "root",
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _blacksmith() -> Dictionary:
	return {
		"id": "blacksmith_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Mind the quench. It takes fingers.",
					"Bring me metal and I'll bring you murder.",
					"That thing on your belt is crying out for attention.",
				],
				"choices": [
					{
						"text": "Can you improve my gear?",
						"do": [{"type": "open_upgrade"}],
						"next": "upgrade_talk",
					},
					CHOICE_SHOP,
					CHOICE_TURN_IN,
					CHOICE_WORK,
					{"text": "What can you actually do?", "next": "explain"},
					CHOICE_BYE,
				],
			},
			"upgrade_talk": {
				"text": "Put it on the anvil and stand back. Bars and pixels, both — I don't work for love.",
				"next": "root",
			},
			"explain": {
				"text": [
					"Five improvements to any one piece. After that the grain goes and it cracks in the cold.",
					"Every second improvement I re-temper the edge hard enough to bite a better class of stone.",
					"Bring bars. The better the bar, the fewer I need. That's the whole of metallurgy and I've just given it away.",
				],
				"next": "root",
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _doctor() -> Dictionary:
	return {
		"id": "doctor_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Sit. Let me see it.",
					"You're bleeding on my floor, and I've only the one floor.",
					"Whatever bit you, don't let it do that twice.",
				],
				"choices": [
					{
						"text": "Patch me up.",
						"show_when": [{"type": "hurt", "below": 0.99}],
						"do": [{"type": "doctor_treat"}],
						"next": "treated",
					},
					{
						"text": "Something's wrong with me. Purge it.",
						"do": [{"type": "doctor_cure"}],
						"next": "treated",
					},
					CHOICE_SHOP,
					CHOICE_TURN_IN,
					CHOICE_WORK,
					{"text": "Do you see many like me?", "next": "patients"},
					CHOICE_BYE,
				],
			},
			"treated": {
				"say": [
					"Better. Try to keep it that way for an afternoon.",
					"There. Now go and undo all my work.",
					"You'll live. Which I appreciate is not always a compliment.",
				],
				"next": "root",
			},
			"patients": {
				"text": [
					"Diggers, mostly. And the ones who come back from the shrines.",
					"They're not hurt. That's what I can't write down. They come in perfectly well and perfectly wrong — they'll flinch at a doorway, or stand looking at a corner for an hour.",
					"One told me she'd walked through a wall and hadn't noticed until she was on the other side. I gave her something to help her sleep. She said sleeping was the problem.",
				],
				"next": "root",
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _guard() -> Dictionary:
	return {
		"id": "guard_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"when": [{"type": "reputation", "min": -39.0}],
				"else": "warning",
				"say": [
					"Move along. Nothing here worth your time.",
					"Weapon stays holstered inside the palisade. That's not a request.",
					"Quiet shift. Long may it last.",
				],
				"choices": [
					CHOICE_TURN_IN,
					CHOICE_WORK,
					{"text": "What comes over that wall?", "next": "threats"},
					{
						"text": "Who's in charge here?",
						"next": "authority",
					},
					CHOICE_BYE,
				],
			},
			"warning": {
				"text": [
					"I know your face. Half the village does, and none of them fondly.",
					"You get one warning and this is it. Touch anyone in {village} again and I'll put you down where you stand.",
				],
				"next": "#end",
			},
			"threats": {
				"when": [{"type": "time", "night": true}],
				"else": "threats_day",
				"text": [
					"At night? Things that weren't there in the afternoon.",
					"And I'll tell you the part they laugh at me for. Twice now I've watched something come *through* the west wall. Not over. Not under.",
					"So I stand here and I look at the wall side-on, every hour, like an idiot. And twice it's been worth it.",
				],
				"next": "root",
			},
			"threats_day": {
				"text": [
					"Daytime it's vermin and off-world idiots. Present company noted.",
					"Come back after dark and ask me again. You'll get a longer answer and a worse night's sleep.",
				],
				"next": "root",
			},
			"authority": {
				"text": "Nobody, officially. The innkeeper, actually. Don't tell her I said so; she'll start charging for it.",
				"next": "root",
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _scientist() -> Dictionary:
	return {
		"id": "scientist_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Don't touch the array. It's calibrated to within a degree of arc and I am not.",
					"Have you flipped today? Properly, I mean, not by accident.",
					"Four planes. Four. Whatever the Protectorate taught you, it was three at best.",
				],
				"choices": [
					CHOICE_TURN_IN,
					{
						"text": "You have fieldwork. I can tell.",
						"show_when": [{"type": "has_work"}],
						"do": [{"type": "offer_work"}],
						"next": "work_offered",
					},
					{"text": "Explain the flip to me.", "next": "lesson1"},
					{"text": "And the shift?", "next": "lesson2"},
					{
						"text": "What's actually wrong with this world?",
						"show_when": [{"type": "quest", "quest": "main_03_gateway", "state": "completed"}],
						"next": "theory",
					},
					CHOICE_BYE,
				],
			},
			"lesson1": {
				"text": [
					"Right. Hold your hand up flat and look at it edge-on. It's a line. Now turn your wrist. It's a hand.",
					"Did your hand change? No. Your *relationship* to it did. That is a flip, and it costs nothing, and it changes everything about what you can walk through.",
					"The rock doesn't move. You stop insisting on one face of it. Q and E, and try not to be smug about it in front of the villagers, they find it unnerving.",
				],
				"next": "root",
			},
			"lesson2": {
				"text": [
					"The shift is the honest one. That's real travel, into the layers behind you.",
					"You've been calling them background your whole life. They're not. They're rooms. Some of them have things in.",
					"And a shift can be *blocked*, which a flip never can, because a flip asks nothing of the world and a shift asks it to make space.",
				],
				"next": "root",
			},
			"theory": {
				"text": [
					"You want my theory? Fine. It's not a theory, it's arithmetic, and it's why nobody will fund me.",
					"A healthy world has four faces and a traveller can pick one. This world has four faces and something is *holding three of them shut*.",
					"You can measure it. The astrogation tables here don't just fail, they fail in a pattern, and the pattern is a survey grid. Somebody mapped this planet and then filed it flat so it would stop moving while they worked.",
					"I've written to the Protectorate nine times. The ninth letter came back marked 'resolved'. That word has kept me up for two years.",
				],
				"do": [{"type": "reputation", "amount": 5.0}],
				"next": "root",
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _crew() -> Dictionary:
	return {
		"id": "crew_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"when": [{"type": "crew", "hired": true}],
				"else": "recruit",
				"say": [
					"Ship's holding together. Mostly me holding it, but still.",
					"Say the word and I'm behind you.",
					"I've seen four planets now. Four! And I've been sick on three.",
				],
				"choices": [
					{"text": "How are you finding it?", "next": "aboard"},
					{"text": "I need you to stay behind for a while.", "next": "dismiss_confirm"},
					CHOICE_BYE,
				],
			},
			"recruit": {
				"say": [
					"You came down in that ship, didn't you. Is there... room?",
					"I've never been off-world. Not once. Everyone here dies within sight of where they were born.",
					"I can fix anything with a lid on it. That's a real skill. That's transferable.",
				],
				"choices": [
					{
						"text": "Sign on with me.",
						"when": [{"type": "can_hire"}],
						"hint": "they need to trust you more, and you need a free bunk",
						"do": [{"type": "hire_crew"}],
						"next": "signed",
					},
					CHOICE_TURN_IN,
					CHOICE_WORK,
					{"text": "What could you do for a ship?", "next": "pitch"},
					CHOICE_BYE,
				],
			},
			"pitch": {
				"text": [
					"Honestly? Whatever needed doing. That's not modesty, that's the job.",
					"Prove you're not going to get us both killed and I'll come without being asked twice.",
				],
				"next": "recruit",
			},
			"signed": {
				"text": [
					"Right. Right! I'll get my things — there aren't many.",
					"Lead on, then. Before I think about it.",
				],
				"next": "#end",
			},
			"aboard": {
				"say": [
					"Better than the village. Colder, though.",
					"I keep looking out and there's no horizon. I don't think I'll ever get used to that.",
					"Ask me again when I've stopped being sick.",
				],
				"next": "root",
			},
			"dismiss_confirm": {
				"text": "...Ah. Right. No, that's fair. I'll be here.",
				"choices": [
					{"text": "Sorry.", "do": [{"type": "dismiss_crew"}], "next": "#end"},
					{"text": "Actually, forget I said it.", "next": "root"},
				],
			},
			"work_offered": NODE_WORK_OFFERED,
			"thanks": NODE_THANKS,
		},
	}


# =========================================================================
static func _trader() -> Dictionary:
	return {
		"id": "trader_default",
		"speaker": "{npc}",
		"start": "root",
		"nodes": {
			"root": {
				"say": [
					"Docked without asking. Old habit. You'll find I have several.",
					"I have three of these left in the sector. Possibly two. Possibly one, now I look at it.",
					"No, I won't say where I got it. Yes, that does affect the price.",
				],
				"choices": [
					{"text": "Let's see the cargo.", "do": [{"type": "open_shop"}], "next": "#end"},
					{"text": "How did you get aboard?", "next": "how"},
					{
						"text": "You've been to the shrines.",
						"show_when": [{"type": "quest", "quest": "main_04_shrine_north", "state": "completed"}],
						"next": "shrines",
					},
					CHOICE_BYE,
				],
			},
			"how": {
				"text": [
					"Same way as always. I waited until your ship was facing a direction it wasn't using, and I walked in.",
					"Don't look like that. Everybody does it. Most people just don't know which direction they aren't using.",
				],
				"next": "root",
			},
			"shrines": {
				"text": [
					"I can smell the ozone on you. Four Keepers, is it? Or only some.",
					"I traded with the Keepers once, long enough ago that I'd rather not do the arithmetic. Do you know what the East one wanted? Nothing. Not a thing. It said the only currency it accepted was being understood.",
					"I gave it a very good try and it gave me nothing, so, you know. Buyer beware.",
				],
				"next": "root",
			},
		},
	}
