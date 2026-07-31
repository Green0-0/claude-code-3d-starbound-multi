class_name TameDB
extends RefCounted

## How every creature in the bestiary is won over.
##
## Two traditions, deliberately kept distinct because they play differently:
##
## **RimWorld's** is a *social* system. A handler walks up with food and tries;
## the chance is `(4% + 3% × handling) × 2 × (1 − wildness)`, gated by a minimum
## handling skill the animal will not tolerate anyone below. Failure costs you a
## cooldown, and on a bad roll the animal takes revenge. Success may produce a
## **bond**. Anything with wildness above zero drifts back toward wild unless you
## keep feeding it.
##
## **Ark's** is a *violent* system. You beat the creature unconscious with
## something that deals torpor rather than damage, then fill its inventory with
## food while it sleeps. Torpor drains the whole time — narcotics buy you more —
## and every point of real damage it takes while under lowers the **taming
## effectiveness**, which is what decides how good the creature is afterwards.
##
## Both need food, and food is tiered: plain forage is slow and lossy, the
## creature's preferred food is decent, and purpose-made kibble is fast and
## nearly lossless. That tiering is what makes the exotic creatures a project
## rather than an errand.
##
## Every creature is tameable. The difficult ones are not gated by bigger
## numbers but by *conditions* — be crouched, be in the dark, come at night,
## crack its shell first, bring the one food it wants, have the skill.

# ------------------------------------------------------------------- methods
const METHOD_PASSIVE := &"passive"     ## walk up and offer food
const METHOD_KNOCKOUT := &"knockout"   ## render unconscious, then feed
const METHOD_TRAP := &"trap"           ## must be boxed in first
const METHOD_REPAIR := &"repair"       ## not alive; feed it parts

# ---------------------------------------------------------------- conditions
const COND_CROUCH := &"crouch"             ## you must be sneaking
const COND_NIGHT := &"night"
const COND_DAY := &"day"
const COND_DARK := &"dark"                 ## low light where it stands
const COND_SHELL_BROKEN := &"shell_broken"
const COND_WOUNDED := &"wounded"           ## below a quarter health
const COND_TRAPPED := &"trapped"           ## nowhere for it to walk out to
const COND_ASLEEP := &"asleep"
const COND_ALONE := &"alone"               ## no others of its kind nearby
const COND_RAIN := &"rain"

## Feeds that work on every creature in the bestiary, whatever its diet.
const UNIVERSAL_FOOD := {
	&"kibble": 2.0,
	&"creature_feed": 0.55,
}

const COND_TEXT := {
	COND_CROUCH: "approached while crouched",
	COND_NIGHT: "tamed after dark",
	COND_DAY: "tamed in daylight",
	COND_DARK: "tamed away from any light",
	COND_SHELL_BROKEN: "its shell broken open first",
	COND_WOUNDED: "brought below a quarter of its health",
	COND_TRAPPED: "boxed in with nowhere to walk out to",
	COND_ASLEEP: "caught asleep",
	COND_ALONE: "separated from its kind",
	COND_RAIN: "tamed in the rain",
}


class Profile extends RefCounted:
	var species: StringName = &""
	var method: StringName = TameDB.METHOD_PASSIVE
	## 0 = a farm animal, 1 = will never willingly go near a person.
	var wildness := 0.4
	## Handling skill the creature will not tolerate anyone below.
	var min_handling := 0
	## Chance a failed passive attempt turns it on you.
	var revenge := 0.15
	## Chance a successful tame also produces a bond.
	var bond_chance := 0.2
	## Ark side: how much torpor it takes, and how fast it wears off.
	var torpor_max := 100.0
	var torpor_drain := 1.4
	## How much food it has to get through while under.
	var feed_required := 4
	## Seconds between bites while unconscious.
	var feed_interval := 6.0
	## Slots in the creature's own inventory.
	var carry_slots := 8
	## What it can be trained to do once obedient.
	var trainable: Array[StringName] = []
	## Ordered best-first. Each entry is [item, quality] where quality scales
	## both taming speed and the effectiveness you keep.
	var foods: Array = []
	## Everything that has to be true at the moment of taming.
	var conditions: Array[StringName] = []
	var note := ""

	func food_quality(item: StringName) -> float:
		for f: Array in foods:
			if f[0] == item:
				return float(f[1])
		# Two feeds work on everything. Kibble is the handler's shortcut and is
		# better than most creatures' own favourite; plain feed always works and
		# is always slow, so nobody is ever stuck for want of the right berry.
		return float(TameDB.UNIVERSAL_FOOD.get(item, 0.0))

	func best_food() -> StringName:
		return foods[0][0] if not foods.is_empty() else &""

	func accepts(item: StringName) -> bool:
		return food_quality(item) > 0.0

	## RimWorld's curve, verbatim: 4% + 3% per skill level, doubled, scaled by
	## how wild the thing is.
	func tame_chance(handling: int) -> float:
		return clampf((0.04 + 0.03 * float(handling)) * 2.0 * (1.0 - wildness),
			0.0, 0.98)

	func condition_text() -> String:
		if conditions.is_empty():
			return ""
		var bits: Array[String] = []
		for c: StringName in conditions:
			bits.append(String(TameDB.COND_TEXT.get(c, String(c))))
		return "; ".join(bits)


static var profiles := {}
static var _booted := false


static func boot() -> void:
	if _booted:
		return
	_booted = true
	SpeciesDB.boot()
	_define()
	_fill_defaults()


static func get_profile(species: StringName) -> Profile:
	boot()
	return profiles.get(species)


static func define(species: StringName, method: StringName, wildness: float) -> Profile:
	var p := Profile.new()
	p.species = species
	p.method = method
	p.wildness = wildness
	# RimWorld gates by wildness; so do we, on the same shape of curve.
	p.min_handling = int(floor(maxf(0.0, (wildness - 0.25) * 14.0)))
	profiles[species] = p
	return p


## Anything the bestiary adds without an explicit profile still gets one, built
## from its temperament and threat, so no creature is ever untameable by
## oversight.
static func _fill_defaults() -> void:
	for d: SpeciesDB.Def in SpeciesDB.defs:
		if profiles.has(d.id):
			continue
		var wild := clampf(0.25 + float(d.threat) * 0.11, 0.1, 0.95)
		var method := METHOD_PASSIVE if d.threat <= 1 else METHOD_KNOCKOUT
		var p := define(d.id, method, wild)
		p.torpor_max = 60.0 + d.health * 0.9
		p.feed_required = 3 + d.threat
		p.carry_slots = 6 + d.threat * 2
		p.trainable = [&"obedience", &"haul"] as Array[StringName]
		for item: StringName in d.diet:
			p.foods.append([item, 1.0])
		if p.foods.is_empty():
			p.foods.append([&"raw_meat", 1.0])
		p.note = "No special handling known."


# =============================================================================
# the hand-written profiles
# =============================================================================

static func _define() -> void:
	# ----------------------------------------------------------- easy company
	var p := define(&"poptop", METHOD_PASSIVE, 0.20)
	p.foods = [[&"carrot", 1.6], [&"tomato", 1.3], [&"tall_grass", 1.0]]
	p.trainable = [&"obedience", &"haul"] as Array[StringName]
	p.torpor_max = 70.0
	p.feed_required = 3
	p.carry_slots = 8
	p.bond_chance = 0.35
	p.revenge = 0.10
	p.note = "Curious and greedy. Hold out a carrot and it will do the rest."

	p = define(&"gleap", METHOD_PASSIVE, 0.30)
	p.foods = [[&"mushroom_brown", 1.5], [&"tall_grass", 1.0]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_CROUCH] as Array[StringName]
	p.torpor_max = 60.0
	p.feed_required = 3
	p.carry_slots = 6
	p.note = "Bolts at the first sudden movement. Crouch, and be patient."

	p = define(&"yokat", METHOD_PASSIVE, 0.35)
	p.foods = [[&"wheat", 1.6], [&"carrot", 1.3], [&"dry_grass", 1.0]]
	p.trainable = [&"obedience", &"haul"] as Array[StringName]
	p.conditions = [COND_CROUCH] as Array[StringName]
	p.torpor_max = 80.0
	p.feed_required = 4
	p.carry_slots = 12
	p.bond_chance = 0.3
	p.note = "A herd animal: separate one from the others and it settles faster."

	p = define(&"lumoth", METHOD_PASSIVE, 0.25)
	p.foods = [[&"glow_dust", 1.8], [&"luminous_powder", 2.0]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_DARK] as Array[StringName]
	p.torpor_max = 40.0
	p.feed_required = 2
	p.carry_slots = 4
	p.bond_chance = 0.45
	p.note = "Will not come near a lit torch. Put the light away and offer dust."

	p = define(&"batong", METHOD_PASSIVE, 0.45)
	p.foods = [[&"raw_meat", 1.4], [&"mushroom_brown", 1.0]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_NIGHT, COND_CROUCH] as Array[StringName]
	p.torpor_max = 50.0
	p.feed_required = 3
	p.carry_slots = 4
	p.note = "Deaf to reason by day, because by day it is asleep. Go at night, "\
		+ "and go quietly — it hunts entirely by ear."

	# ------------------------------------------------------ the passive plant
	p = define(&"hypnare", METHOD_PASSIVE, 0.40)
	p.foods = [[&"glow_flower", 1.8], [&"flower_blue", 1.5], [&"mushroom_red", 1.0]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_CROUCH, COND_ALONE] as Array[StringName]
	p.revenge = 0.0
	p.torpor_max = 90.0
	p.feed_required = 4
	p.carry_slots = 6
	p.bond_chance = 0.4
	p.note = "It has never attacked anybody unprovoked, and it will not start "\
		+ "with you. Simply do not provoke it."

	# ------------------------------------------------------------- knockouts
	p = define(&"voltip", METHOD_KNOCKOUT, 0.50)
	p.foods = [[&"crystal_shard", 1.5], [&"battery", 2.0], [&"raw_meat", 1.0]]
	p.trainable = [&"obedience", &"haul", &"release"] as Array[StringName]
	p.torpor_max = 110.0
	p.feed_required = 5
	p.carry_slots = 10
	p.note = "Put it out before you try anything. It earths itself through "\
		+ "whoever is closest."

	p = define(&"pteropod", METHOD_KNOCKOUT, 0.55)
	p.foods = [[&"venom_gland", 1.8], [&"raw_meat", 1.0]]
	p.trainable = [&"obedience", &"release"] as Array[StringName]
	p.conditions = [COND_NIGHT] as Array[StringName]
	p.torpor_max = 100.0
	p.feed_required = 5
	p.carry_slots = 8
	p.note = "Only comes down within reach after dark."

	p = define(&"narfin", METHOD_KNOCKOUT, 0.55)
	p.foods = [[&"raw_fish", 1.7], [&"raw_meat", 1.1]]
	p.trainable = [&"obedience", &"haul"] as Array[StringName]
	p.conditions = [COND_ALONE] as Array[StringName]
	p.torpor_max = 120.0
	p.feed_required = 5
	p.carry_slots = 14
	p.note = "Provoke one and you have provoked the pack. Cut one out first."

	p = define(&"snaunt", METHOD_KNOCKOUT, 0.58)
	p.foods = [[&"raw_meat", 1.5], [&"bone", 1.1]]
	p.trainable = [&"obedience", &"release"] as Array[StringName]
	p.conditions = [COND_NIGHT] as Array[StringName]
	p.torpor_max = 110.0
	p.feed_required = 5
	p.carry_slots = 8

	p = define(&"oculob", METHOD_KNOCKOUT, 0.52)
	p.foods = [[&"slime_glob", 1.6], [&"raw_meat", 1.0]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_DARK] as Array[StringName]
	p.torpor_max = 90.0
	p.feed_required = 4
	p.carry_slots = 6
	p.note = "There is no angle it cannot see you from, so do not bother "\
		+ "sneaking. Bring something that hits hard and does not kill."

	p = define(&"ixoling", METHOD_KNOCKOUT, 0.35)
	p.foods = [[&"raw_meat", 1.4], [&"chitin", 1.0]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.torpor_max = 50.0
	p.feed_required = 2
	p.carry_slots = 4

	# ---------------------------------------------------------- the difficult
	p = define(&"crustoise", METHOD_KNOCKOUT, 0.62)
	p.foods = [[&"kelp_frond", 1.6], [&"mushroom_brown", 1.2], [&"raw_meat", 1.0]]
	p.trainable = [&"obedience", &"haul"] as Array[StringName]
	p.conditions = [COND_SHELL_BROKEN] as Array[StringName]
	p.torpor_max = 160.0
	p.torpor_drain = 1.0
	p.feed_required = 6
	p.carry_slots = 20
	p.note = "Nothing reaches it through the shell — not food, not tranquiliser. "\
		+ "Crack that first and it becomes an ordinary knockout."

	p = define(&"mandraflora", METHOD_TRAP, 0.60)
	p.foods = [[&"fertiliser", 1.9], [&"bone_meal", 1.6], [&"plant_matter", 1.0]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_TRAPPED] as Array[StringName]
	p.torpor_max = 120.0
	p.feed_required = 5
	p.carry_slots = 6
	p.note = "It uproots and charges the moment it is seen, so it has to be "\
		+ "boxed in before anything else can happen. Then it will take feed."

	p = define(&"anglure", METHOD_TRAP, 0.66)
	p.foods = [[&"raw_fish", 1.8], [&"glow_gland", 2.0], [&"raw_meat", 1.0]]
	p.trainable = [&"obedience", &"release"] as Array[StringName]
	p.conditions = [COND_TRAPPED, COND_DARK] as Array[StringName]
	p.torpor_max = 150.0
	p.feed_required = 6
	p.carry_slots = 10
	p.note = "It will not leave its ambush, which makes walling it in easy and "\
		+ "everything after that hard."

	p = define(&"petricub", METHOD_KNOCKOUT, 0.68)
	p.foods = [[&"cooked_meat", 1.9], [&"raw_meat", 1.2]]
	p.trainable = [&"obedience", &"haul", &"release"] as Array[StringName]
	p.conditions = [COND_WOUNDED] as Array[StringName]
	p.torpor_max = 190.0
	p.torpor_drain = 0.9
	p.feed_required = 7
	p.carry_slots = 18
	p.note = "Stone hide. Torpor barely registers until it has been worn down, "\
		+ "so hurt it first and then put it out."

	p = define(&"skimbus", METHOD_KNOCKOUT, 0.70)
	p.foods = [[&"ice_crystal", 1.9], [&"crystal_shard", 1.3]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_WOUNDED] as Array[StringName]
	p.torpor_max = 170.0
	p.feed_required = 6
	p.carry_slots = 10
	p.note = "It drifts through rock, so it cannot be trapped and it cannot be "\
		+ "cornered. The only approach is a straight fight, stopped short."

	p = define(&"scandroid", METHOD_REPAIR, 0.72)
	p.foods = [[&"circuit_board", 2.0], [&"copper_wire", 1.4], [&"scrap_metal", 1.0]]
	p.trainable = [&"obedience", &"haul", &"release"] as Array[StringName]
	p.conditions = [COND_TRAPPED] as Array[StringName]
	p.torpor_max = 140.0
	p.torpor_drain = 0.6
	p.feed_required = 6
	p.carry_slots = 16
	p.bond_chance = 0.0
	p.note = "Not alive, so none of the usual applies. Disable it, then feed "\
		+ "parts into the chassis until it decides you are maintenance."

	# ------------------------------------------------------------ the exotic
	p = define(&"fennix", METHOD_KNOCKOUT, 0.82)
	p.foods = [[&"alien_skewer", 2.2], [&"cooked_meat", 1.5], [&"raw_meat", 1.0]]
	p.trainable = [&"obedience", &"haul", &"release"] as Array[StringName]
	p.conditions = [COND_NIGHT, COND_ALONE, COND_WOUNDED] as Array[StringName]
	p.torpor_max = 240.0
	p.torpor_drain = 1.8
	p.feed_required = 9
	p.feed_interval = 5.0
	p.carry_slots = 16
	p.bond_chance = 0.5
	p.min_handling = 8
	p.note = "Hunts in threes, breathes fire and burns off tranquiliser almost "\
		+ "as fast as it goes in. Catch one alone, at night, already hurt — and "\
		+ "have something cooked ready before it wakes."

	p = define(&"mother_poptop", METHOD_KNOCKOUT, 0.88)
	p.foods = [[&"hearty_platter", 2.4], [&"carrot", 1.2]]
	p.trainable = [&"obedience", &"haul"] as Array[StringName]
	p.conditions = [COND_WOUNDED, COND_ALONE] as Array[StringName]
	p.torpor_max = 420.0
	p.torpor_drain = 1.6
	p.feed_required = 12
	p.carry_slots = 26
	p.min_handling = 10
	p.bond_chance = 0.6
	p.note = "She will not be separated from the brood while any of it stands. "\
		+ "Clear them, wear her down, and then cook her something."

	p = define(&"ixodoom", METHOD_KNOCKOUT, 0.94)
	p.foods = [[&"voyagers_feast", 2.6], [&"raw_alien_meat", 1.3]]
	p.trainable = [&"obedience", &"haul", &"release"] as Array[StringName]
	p.conditions = [COND_SHELL_BROKEN, COND_WOUNDED, COND_ALONE] as Array[StringName]
	p.torpor_max = 700.0
	p.torpor_drain = 2.4
	p.feed_required = 16
	p.feed_interval = 4.0
	p.carry_slots = 40
	p.min_handling = 14
	p.bond_chance = 0.7
	p.note = "Armoured, venomous, and it hatches replacements faster than you "\
		+ "can clear them. Crack the shell, kill the brood, take it to the edge "\
		+ "of death, put it under, and have a feast ready."

	p = define(&"boss_magma_heart", METHOD_KNOCKOUT, 0.96)
	p.foods = [[&"starlit_confection", 3.0], [&"core_fragment", 1.6]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_WOUNDED, COND_RAIN] as Array[StringName]
	p.torpor_max = 900.0
	p.torpor_drain = 3.0
	p.feed_required = 18
	p.carry_slots = 30
	p.min_handling = 16
	p.note = "It cannot be cooled enough to sleep under its own sky. Wait for "\
		+ "weather, wear it down, and keep the narcotics coming."

	p = define(&"boss_fourfold", METHOD_PASSIVE, 0.99)
	p.foods = [[&"ancient_essence", 3.2]]
	p.trainable = [&"obedience"] as Array[StringName]
	p.conditions = [COND_DARK, COND_ALONE, COND_CROUCH] as Array[StringName]
	p.revenge = 0.0
	p.torpor_max = 800.0
	p.feed_required = 20
	p.carry_slots = 20
	p.min_handling = 18
	p.bond_chance = 1.0
	p.note = "It cannot be struck and it cannot be held. It can, apparently, be "\
		+ "waited for — in the dark, alone, kneeling, holding out something it "\
		+ "recognises."
