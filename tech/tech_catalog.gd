## The single source of truth for every tech's *metadata*.
##
## Behaviour lives in `res://tech/techs/<id>.gd` (one `TchBase` subclass each);
## numbers, names, slots, prices and the unlock tree live here. Keeping them
## split means the content-item file can build a tech card for every tech
## without loading twenty scripts, and `Items` (autoload #3) can read this
## table long before `Tech` (autoload #14) exists.
##
## [b]Energy model.[/b] `energy` is the one-off cost paid the instant the tech
## activates; `drain` is the per-second cost while it stays active. A tech that
## cannot pay its drain deactivates cleanly rather than going negative.
##
## [b]Modes.[/b]
##   `instant`  fires once, `duration` may still gate an animation window
##   `hold`     stays active while `tech_action` is held
##   `toggle`   press to turn on, press again (or run dry) to turn off
##   `passive`  never activates; `on_update` runs every frame while equipped
class_name TchCatalog
extends RefCounted

const SLOT_HEAD := &"head"
const SLOT_BODY := &"body"
const SLOT_LEGS := &"legs"
const SLOTS: Array[StringName] = [SLOT_HEAD, SLOT_BODY, SLOT_LEGS]

const SCRIPT_DIR := "res://tech/techs/"

## Prefix for the inventory item that unlocks a tech: `tech_double_jump`.
const CARD_PREFIX := "tech_"

## Every tech in the game. `requires` lists tech ids that must already be
## unlocked; an empty list means the card alone is enough.
const ALL := [
	# ------------------------------------------------------------ legs: motion
	{
		"id": &"double_jump", "name": "Double Jump", "slot": &"legs",
		"script": "double_jump.gd", "mode": "instant",
		"energy": 25.0, "drain": 0.0, "cooldown": 0.30, "duration": 0.0,
		"color": Color(0.55, 0.85, 1.0), "rarity": 1, "price": 400, "requires": [],
		"desc": "A second kick of thrust in mid-air. The foundation every other leg tech is bolted onto.",
	},
	{
		"id": &"dash", "name": "Dash", "slot": &"legs",
		"script": "dash.gd", "mode": "instant",
		"energy": 30.0, "drain": 0.0, "cooldown": 0.75, "duration": 0.18,
		"color": Color(0.9, 0.75, 0.35), "rarity": 1, "price": 700, "requires": [&"double_jump"],
		"desc": "A flat, gravity-free burst along the plane. Cancels fall speed for its duration.",
	},
	{
		"id": &"sprint_burst", "name": "Sprint Burst", "slot": &"legs",
		"script": "sprint_burst.gd", "mode": "hold",
		"energy": 12.0, "drain": 7.0, "cooldown": 0.20, "duration": 0.0,
		"color": Color(0.95, 0.55, 0.3), "rarity": 1, "price": 500, "requires": [],
		"desc": "Hold to run at 1.6x speed. Drains while held; releases the moment you let go.",
	},
	{
		"id": &"rocket_boost", "name": "Rocket Boost", "slot": &"legs",
		"script": "rocket_boost.gd", "mode": "hold",
		"energy": 10.0, "drain": 24.0, "cooldown": 0.40, "duration": 0.0,
		"color": Color(1.0, 0.5, 0.2), "rarity": 2, "price": 2200, "requires": [&"glide"],
		"desc": "Sustained vertical thrust. Expensive, but the fastest way out of a hole.",
	},
	{
		"id": &"pulse_jump", "name": "Pulse Jump", "slot": &"legs",
		"script": "pulse_jump.gd", "mode": "instant",
		"energy": 18.0, "drain": 0.0, "cooldown": 0.55, "duration": 0.0,
		"color": Color(0.6, 0.95, 0.8), "rarity": 2, "price": 1600, "requires": [&"dash"],
		"desc": "Unlimited but weaker mid-air pulses. Height is capped by your energy bar, not a jump counter.",
	},
	{
		"id": &"blink", "name": "Blink Step", "slot": &"legs",
		"script": "blink.gd", "mode": "instant",
		"energy": 35.0, "drain": 0.0, "cooldown": 1.60, "duration": 0.0,
		"color": Color(0.75, 0.6, 1.0), "rarity": 2, "price": 2400, "requires": [&"dash"],
		"desc": "Teleport up to four blocks along the plane, straight through thin walls.",
	},
	{
		"id": &"phase_step", "name": "Phase Step", "slot": &"legs",
		"script": "phase_step.gd", "mode": "instant",
		"energy": 35.0, "drain": 0.0, "cooldown": 1.20, "duration": 0.30,
		"color": Color(0.45, 0.95, 0.9), "rarity": 2, "price": 2800, "requires": [],
		"desc": "Shift two layers at once, passing clean through the solid layer between them.",
	},
	{
		"id": &"perspective_dash", "name": "Perspective Dash", "slot": &"legs",
		"script": "perspective_dash.gd", "mode": "instant",
		"energy": 40.0, "drain": 0.0, "cooldown": 2.20, "duration": 0.44,
		"color": Color(1.0, 0.65, 0.95), "rarity": 3, "price": 6500,
		"requires": [&"phase_step", &"dash"],
		"desc": "Dash, and flip the world ninety degrees halfway through it. You emerge in the new plane with the dash still under you.",
	},

	# -------------------------------------------------------------- body: form
	{
		"id": &"morph_ball", "name": "Morph Ball", "slot": &"body",
		"script": "morph_ball.gd", "mode": "toggle",
		"energy": 15.0, "drain": 4.0, "cooldown": 0.35, "duration": 0.0,
		"color": Color(0.7, 0.7, 0.78), "rarity": 1, "price": 900, "requires": [],
		"desc": "Curl into a one-block sphere. Fits down mining shafts; cannot jump or use tools.",
	},
	{
		"id": &"spike_ball", "name": "Spike Ball", "slot": &"body",
		"script": "spike_ball.gd", "mode": "toggle",
		"energy": 25.0, "drain": 11.0, "cooldown": 0.60, "duration": 0.0,
		"color": Color(0.85, 0.3, 0.35), "rarity": 2, "price": 3000, "requires": [&"morph_ball"],
		"desc": "The morph ball, weaponised. Bounces hard and shreds anything it rolls into.",
	},
	{
		"id": &"distortion_sphere", "name": "Distortion Sphere", "slot": &"body",
		"script": "distortion_sphere.gd", "mode": "toggle",
		"energy": 20.0, "drain": 7.0, "cooldown": 0.50, "duration": 0.0,
		"color": Color(0.5, 0.4, 0.9), "rarity": 2, "price": 3200, "requires": [&"morph_ball"],
		"desc": "A frictionless sphere that rolls at nearly double running speed and ignores knockback.",
	},
	{
		"id": &"bubble_boost", "name": "Bubble Boost", "slot": &"body",
		"script": "bubble_boost.gd", "mode": "toggle",
		"energy": 20.0, "drain": 10.0, "cooldown": 0.50, "duration": 0.0,
		"color": Color(0.45, 0.8, 1.0), "rarity": 2, "price": 2600, "requires": [&"morph_ball"],
		"desc": "Encase yourself in a buoyant bubble. Rises through liquid, drifts gently in air.",
	},
	{
		"id": &"glide", "name": "Glide", "slot": &"body",
		"script": "glide.gd", "mode": "hold",
		"energy": 0.0, "drain": 8.0, "cooldown": 0.10, "duration": 0.0,
		"color": Color(0.8, 0.9, 0.95), "rarity": 1, "price": 1100, "requires": [&"double_jump"],
		"desc": "Deploy a membrane: terminal velocity drops to a crawl and you drift forward.",
	},
	{
		"id": &"wall_cling", "name": "Wall Cling", "slot": &"body",
		"script": "wall_cling.gd", "mode": "passive",
		"energy": 0.0, "drain": 5.0, "cooldown": 0.0, "duration": 0.0,
		"color": Color(0.55, 0.7, 0.5), "rarity": 1, "price": 800, "requires": [],
		"desc": "Grip any wall you press into. Costs energy only while you are actually hanging.",
	},
	{
		"id": &"magnet_grip", "name": "Magnet Grip", "slot": &"body",
		"script": "magnet_grip.gd", "mode": "passive",
		"energy": 0.0, "drain": 3.0, "cooldown": 0.0, "duration": 0.0,
		"color": Color(0.6, 0.65, 0.85), "rarity": 2, "price": 1800, "requires": [&"wall_cling"],
		"desc": "Ferrous attraction: item drops fall toward you, and metal walls hold you fast.",
	},
	{
		"id": &"fold", "name": "Fold", "slot": &"body",
		"script": "fold.gd", "mode": "toggle",
		"energy": 50.0, "drain": 9.0, "cooldown": 4.00, "duration": 6.0,
		"color": Color(1.0, 0.45, 0.6), "rarity": 3, "price": 9000,
		"requires": [&"depth_sight", &"plane_anchor"],
		"desc": "Collapse the layer behind you into your own for a few seconds. Two rooms, one fight.",
	},

	# -------------------------------------------------------- head: perception
	{
		"id": &"water_breathing", "name": "Water Breathing", "slot": &"head",
		"script": "water_breathing.gd", "mode": "passive",
		"energy": 0.0, "drain": 4.0, "cooldown": 0.0, "duration": 0.0,
		"color": Color(0.3, 0.75, 0.9), "rarity": 1, "price": 1200, "requires": [],
		"desc": "Electrolyses breathable air out of liquid. Only drains while you are actually under.",
	},
	{
		"id": &"nightvision", "name": "Nightvision", "slot": &"head",
		"script": "nightvision.gd", "mode": "toggle",
		"energy": 5.0, "drain": 1.5, "cooldown": 0.30, "duration": 0.0,
		"color": Color(0.45, 0.95, 0.5), "rarity": 1, "price": 700, "requires": [],
		"desc": "Amplifies whatever light there is. Cheap enough to leave running all night.",
	},
	{
		"id": &"plane_anchor", "name": "Plane Anchor", "slot": &"head",
		"script": "plane_anchor.gd", "mode": "toggle",
		"energy": 25.0, "drain": 5.0, "cooldown": 2.00, "duration": 8.0,
		"color": Color(0.95, 0.85, 0.4), "rarity": 3, "price": 5200, "requires": [&"phase_step"],
		"desc": "Drives a pin through the world's depth axis. Flip freely — nothing hostile can follow you across.",
	},
	{
		"id": &"depth_sight", "name": "Depth Sight", "slot": &"head",
		"script": "depth_sight.gd", "mode": "toggle",
		"energy": 30.0, "drain": 7.0, "cooldown": 1.50, "duration": 6.0,
		"color": Color(0.6, 1.0, 0.85), "rarity": 3, "price": 6000, "requires": [&"phase_step"],
		"desc": "The three layers behind you resolve into focus and become as solid to your tools as the one you stand in.",
	},
]


## Definition dictionary for an id, or `{}`.
static func get_def(tech_id: StringName) -> Dictionary:
	for d: Dictionary in ALL:
		if d["id"] == tech_id:
			return d
	return {}


static func has(tech_id: StringName) -> bool:
	return not get_def(tech_id).is_empty()


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d: Dictionary in ALL:
		out.append(d["id"])
	return out


static func in_slot(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for d: Dictionary in ALL:
		if d["slot"] == slot:
			out.append(d["id"])
	return out


static func script_path(tech_id: StringName) -> String:
	var d := get_def(tech_id)
	return "" if d.is_empty() else SCRIPT_DIR + String(d["script"])


## The item id of the card that unlocks `tech_id`.
static func card_id(tech_id: StringName) -> StringName:
	return StringName(CARD_PREFIX + String(tech_id))


## Inverse of [method card_id]; returns `&""` when the item is not a tech card.
static func tech_of_card(item_id: StringName) -> StringName:
	var s := String(item_id)
	if not s.begins_with(CARD_PREFIX):
		return &""
	var t := StringName(s.substr(CARD_PREFIX.length()))
	return t if has(t) else &""
