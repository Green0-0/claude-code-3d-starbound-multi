class_name TechCatalog
extends RefCounted

## Every tech in the game, as pure data.
##
## A tech occupies one of three slots — `legs`, `body`, `head` — and only one
## per slot can be equipped at a time, so the loadout is a real decision. `G`
## activates the equipped `legs`/`body` tech; `head` techs are passive.
##
## `energy` is the one-shot cost, `drain` the per-second cost while held. Techs
## that cost neither are passive.
##
## Three of them are built on the camera-obstruction system rather than on
## movement, and they are the ones worth reading: `phase_step` walks you into
## the volume the cutaway has opened, `depth_sight` marks what the cut is
## hiding, and `fold` re-anchors the cut itself.

const SLOT_LEGS := &"legs"
const SLOT_BODY := &"body"
const SLOT_HEAD := &"head"
const SLOTS := [SLOT_LEGS, SLOT_BODY, SLOT_HEAD]

const ALL := [
	# ------------------------------------------------------------------ legs
	{"id": &"double_jump", "name": "Double Jump", "slot": SLOT_LEGS,
		"energy": 15.0, "drain": 0.0, "price": 600, "rarity": 0,
		"color": Color(0.62, 0.86, 1.0), "requires": [],
		"desc": "A second jump in mid-air, from nothing at all."},
	{"id": &"dash", "name": "Dash", "slot": SLOT_LEGS,
		"energy": 20.0, "drain": 0.0, "price": 800, "rarity": 0,
		"color": Color(0.98, 0.78, 0.32), "requires": [],
		"desc": "A short burst along the ground in the direction you are moving."},
	{"id": &"sprint_burst", "name": "Sprint Burst", "slot": SLOT_LEGS,
		"energy": 0.0, "drain": 4.0, "price": 700, "rarity": 0,
		"color": Color(0.96, 0.56, 0.28), "requires": [],
		"desc": "Hold to run considerably faster, for as long as the energy lasts."},
	{"id": &"rocket_boost", "name": "Rocket Boost", "slot": SLOT_LEGS,
		"energy": 0.0, "drain": 12.0, "price": 1800, "rarity": 1,
		"color": Color(1.0, 0.48, 0.20), "requires": [&"double_jump"],
		"desc": "Hold to hover on thrust. Loud, hot, and it will get you out."},
	{"id": &"pulse_jump", "name": "Pulse Jump", "slot": SLOT_LEGS,
		"energy": 24.0, "drain": 0.0, "price": 1400, "rarity": 1,
		"color": Color(0.72, 0.62, 1.0), "requires": [&"double_jump"],
		"desc": "A hard vertical shove that also knocks back anything alongside."},
	{"id": &"blink", "name": "Blink Step", "slot": SLOT_LEGS,
		"energy": 30.0, "drain": 0.0, "price": 2600, "rarity": 2,
		"color": Color(0.66, 0.44, 0.94), "requires": [&"dash"],
		"desc": "Teleport a few blocks along your aim, through anything thin."},
	{"id": &"phase_step", "name": "Phase Step", "slot": SLOT_LEGS,
		"energy": 26.0, "drain": 0.0, "price": 3200, "rarity": 2,
		"color": Color(0.52, 0.90, 0.86), "requires": [&"blink"],
		"desc": "Step into the volume the cutaway has opened between you and the "
			+ "lens — straight through whatever the camera is currently hiding."},

	# ------------------------------------------------------------------ body
	{"id": &"morph_ball", "name": "Morph Ball", "slot": SLOT_BODY,
		"energy": 0.0, "drain": 0.0, "price": 1200, "rarity": 1,
		"color": Color(0.66, 0.70, 0.78), "requires": [],
		"desc": "Curl into a ball that fits down a one-block gap and rolls."},
	{"id": &"spike_ball", "name": "Spike Ball", "slot": SLOT_BODY,
		"energy": 0.0, "drain": 3.0, "price": 2200, "rarity": 2,
		"color": Color(0.86, 0.34, 0.30), "requires": [&"morph_ball"],
		"desc": "The ball, with spines. Rolls through anything soft."},
	{"id": &"bubble_boost", "name": "Bubble Boost", "slot": SLOT_BODY,
		"energy": 18.0, "drain": 0.0, "price": 1000, "rarity": 1,
		"color": Color(0.44, 0.82, 0.96), "requires": [],
		"desc": "A bubble of held air that shoves you upward through liquid."},
	{"id": &"glide", "name": "Glide", "slot": SLOT_BODY,
		"energy": 0.0, "drain": 2.5, "price": 900, "rarity": 0,
		"color": Color(0.82, 0.88, 0.94), "requires": [],
		"desc": "Hold to fall slowly and travel a long way doing it."},
	{"id": &"wall_cling", "name": "Wall Cling", "slot": SLOT_BODY,
		"energy": 0.0, "drain": 1.5, "price": 1100, "rarity": 1,
		"color": Color(0.60, 0.52, 0.40), "requires": [],
		"desc": "Hold against a wall to stick to it, and jump off it again."},
	{"id": &"fold", "name": "Fold", "slot": SLOT_BODY,
		"energy": 40.0, "drain": 0.0, "price": 4200, "rarity": 3,
		"color": Color(0.94, 0.72, 1.0), "requires": [&"phase_step"],
		"desc": "Re-anchor the cutaway to a point you are aiming at instead of "
			+ "to yourself, and hold it there. The world opens somewhere else."},

	# ------------------------------------------------------------------ head
	{"id": &"water_breathing", "name": "Water Breathing", "slot": SLOT_HEAD,
		"energy": 0.0, "drain": 0.0, "price": 800, "rarity": 0,
		"color": Color(0.36, 0.78, 0.90), "requires": [],
		"desc": "Passive. Your air never runs out under water."},
	{"id": &"nightvision", "name": "Nightvision", "slot": SLOT_HEAD,
		"energy": 0.0, "drain": 0.8, "price": 1000, "rarity": 1,
		"color": Color(0.56, 0.94, 0.56), "requires": [],
		"desc": "Passive. Unlit caves stop being guesswork."},
	{"id": &"depth_sight", "name": "Depth Sight", "slot": SLOT_HEAD,
		"energy": 0.0, "drain": 1.2, "price": 2800, "rarity": 2,
		"color": Color(0.98, 0.62, 0.86), "requires": [&"nightvision"],
		"desc": "Passive. Outlines every creature and cache the cutaway is "
			+ "hiding from you, whichever way the camera is turned."},
	{"id": &"scan_pulse", "name": "Survey Pulse", "slot": SLOT_HEAD,
		"energy": 22.0, "drain": 0.0, "price": 1600, "rarity": 1,
		"color": Color(0.44, 0.90, 0.94), "requires": [],
		"desc": "A ping that marks ore veins through solid rock for a while."},
]


static func get_def(id: StringName) -> Dictionary:
	for d: Dictionary in ALL:
		if d["id"] == id:
			return d
	return {}


static func card_id(id: StringName) -> StringName:
	return StringName(String(id) + "_tech_card")


static func in_slot(slot: StringName) -> Array:
	var out: Array = []
	for d: Dictionary in ALL:
		if d["slot"] == slot:
			out.append(d)
	return out
