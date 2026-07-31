extends RefCounted

## The gear of the animal handler.
##
## Four groups, one per stage of the work:
##
##   1. **Sedatives** — weapons and ammunition that deal torpor instead of
##      damage. Every one of them hits softer than its ordinary equivalent,
##      which is the whole trade: taming effectiveness falls with every point of
##      real damage a creature takes on the way down.
##   2. **Chemistry** — narcotics to keep it under, stimulant to bring it back.
##   3. **Restraints** — bolas and nets, for the creatures that must be held
##      still before anything else can happen.
##   4. **Husbandry** — collars, saddlebags and feed, for after.


static func register_all() -> void:
	_sedatives()
	_chemistry()
	_restraints()
	_husbandry()


# =============================================================================
# sedatives
# =============================================================================

static func _sedatives() -> void:
	# --- ammunition. Damage is deliberately feeble; torpor is the point.
	var ammo := [
		[&"tranq_arrow", "Tranquiliser Arrow", Color(0.56, 0.82, 0.60), 9, 1, 14.0,
			"A blunt head and a glass bulb of sedative. It will barely scratch "
			+ "a hide, which is exactly what you want."],
		[&"tranq_dart", "Tranquiliser Dart", Color(0.42, 0.74, 0.86), 18, 1, 26.0,
			"Machined, weighted and dosed for something large. Fired from a "
			+ "rifle, it puts a creature down without taking much off it."],
		[&"shock_dart", "Shock Dart", Color(0.94, 0.86, 0.40), 34, 2, 52.0,
			"Discharges on contact. Enough to drop the things a dart cannot, "
			+ "though it leaves a mark doing it."],
	]
	for r: Array in ammo:
		if Items.has(r[0]):
			continue
		Items.define(r[0], String(r[1])).of_kind(Items.Kind.MATERIAL) \
			.look(r[2], &"rod").worth(int(r[3]), int(r[4])).stacks(200) \
			.in_category(&"ammo").tag(&"ammo").tag(&"tranquiliser") \
			.describe(String(r[6])).flags({"torpor": float(r[5])})

	# --- the weapons that fire them
	if not Items.has(&"tranq_bow"):
		Items.define(&"tranq_bow", "Sedative Bow") \
			.as_weapon(2.0, 0.9, Blocks.ELEM_PHYSICAL) \
			.look(Color(0.52, 0.74, 0.58), &"bow").worth(180, Items.RARITY_UNCOMMON) \
			.in_category(&"weapons").tag(&"weapon").tag(&"bow").tag(&"tranquiliser") \
			.flags({"projectile": "arrow", "knockback": 1.0, "torpor": 12.0}) \
			.describe("Underdrawn on purpose. It carries a tranquiliser arrow "
				+ "far enough to be useful and not hard enough to kill.")

	if not Items.has(&"tranq_rifle"):
		Items.define(&"tranq_rifle", "Tranquiliser Rifle") \
			.as_weapon(3.5, 0.7, Blocks.ELEM_PHYSICAL) \
			.look(Color(0.44, 0.60, 0.68), &"gun").worth(620, Items.RARITY_RARE) \
			.in_category(&"weapons").tag(&"weapon").tag(&"gun").tag(&"tranquiliser") \
			.flags({"projectile": "bolt", "energy_cost": 6.0, "knockback": 1.5,
				"two_handed": true, "torpor": 30.0}) \
			.describe("Long barrel, low charge, and a chamber sized for darts. "
				+ "The standard answer to anything that will not be reasoned with.")

	# --- and the club, for when you have nothing else
	if not Items.has(&"sap_club"):
		Items.define(&"sap_club", "Sap Club") \
			.as_weapon(4.0, 1.1, Blocks.ELEM_PHYSICAL) \
			.look(Color(0.60, 0.46, 0.34), &"hammer").worth(45) \
			.in_category(&"weapons").tag(&"weapon").tag(&"broadsword") \
			.tag(&"tranquiliser").lasts(220) \
			.flags({"knockback": 2.0, "torpor": 9.0}) \
			.describe("A weighted length of hardwood. Crude, close range, and "
				+ "the only sedative available to somebody who has just landed.")


# =============================================================================
# chemistry
# =============================================================================

static func _chemistry() -> void:
	if not Items.has(&"narcotic"):
		Items.define(&"narcotic", "Narcotic").of_kind(Items.Kind.CONSUMABLE) \
			.look(Color(0.68, 0.44, 0.78), &"flask").worth(40).stacks(100) \
			.in_category(&"medicine").tag(&"narcotic").tag(&"taming") \
			.flags({"torpor": 40.0}) \
			.describe("Fed to a sleeping creature it stays sleeping. Taming a "
				+ "large animal is mostly a question of having enough of these.")

	if not Items.has(&"strong_narcotic"):
		Items.define(&"strong_narcotic", "Concentrated Narcotic") \
			.of_kind(Items.Kind.CONSUMABLE) \
			.look(Color(0.50, 0.28, 0.66), &"flask") \
			.worth(150, Items.RARITY_UNCOMMON).stacks(50) \
			.in_category(&"medicine").tag(&"narcotic").tag(&"taming") \
			.flags({"torpor": 130.0}) \
			.describe("Distilled down until a single flask will hold a boss "
				+ "under for the length of a proper meal.")

	if not Items.has(&"stimulant"):
		Items.define(&"stimulant", "Stimulant").of_kind(Items.Kind.CONSUMABLE) \
			.look(Color(0.96, 0.72, 0.34), &"flask").worth(35).stacks(100) \
			.in_category(&"medicine").tag(&"taming") \
			.with_effect(&"haste", 25.0) \
			.flags({"torpor": -60.0}) \
			.describe("Wakes a creature immediately. Useful on yourself, and "
				+ "useful on a tame you would rather have on its feet now.")


# =============================================================================
# restraints
# =============================================================================

static func _restraints() -> void:
	if not Items.has(&"bola"):
		Items.define(&"bola", "Bola").of_kind(Items.Kind.CONSUMABLE) \
			.look(Color(0.74, 0.66, 0.50), &"orb").worth(28).stacks(50) \
			.in_category(&"tools").tag(&"restraint").tag(&"taming") \
			.describe("Three weights on a cord. Wraps the legs of anything "
				+ "roughly your size and holds it for long enough to matter.")

	if not Items.has(&"capture_net"):
		Items.define(&"capture_net", "Capture Net").of_kind(Items.Kind.CONSUMABLE) \
			.look(Color(0.58, 0.72, 0.64), &"pane") \
			.worth(90, Items.RARITY_UNCOMMON).stacks(20) \
			.in_category(&"tools").tag(&"restraint").tag(&"taming") \
			.describe("Weighted mesh. Counts as walls for anything that has to "
				+ "be boxed in, and saves you building the box.")


# =============================================================================
# husbandry
# =============================================================================

static func _husbandry() -> void:
	if not Items.has(&"handlers_collar"):
		Items.define(&"handlers_collar", "Handler's Collar") \
			.of_kind(Items.Kind.CONSUMABLE) \
			.look(Color(0.78, 0.56, 0.34), &"rod") \
			.worth(120, Items.RARITY_UNCOMMON).stacks(20) \
			.in_category(&"tools").tag(&"taming") \
			.describe("Fitted to a tame, it will follow a spoken instruction. "
				+ "Everything a creature can be taught begins here.")

	if not Items.has(&"saddlebag"):
		Items.define(&"saddlebag", "Saddlebag").of_kind(Items.Kind.CONSUMABLE) \
			.look(Color(0.66, 0.50, 0.36), &"cube") \
			.worth(160, Items.RARITY_UNCOMMON).stacks(20) \
			.in_category(&"tools").tag(&"taming") \
			.describe("Eight more slots on a creature already willing to carry "
				+ "things for you.")

	if not Items.has(&"creature_feed"):
		Items.define(&"creature_feed", "Creature Feed").of_kind(Items.Kind.CONSUMABLE) \
			.as_food(6.0, 0.0).look(Color(0.82, 0.70, 0.38), &"round") \
			.worth(8).stacks(200).in_category(&"food").tag(&"taming") \
			.tag(&"feed").describe("Mixed grain and dried meat. No creature "
				+ "prefers it and every creature will eat it, which is the "
				+ "point of keeping a sack by the door.")

	if not Items.has(&"kibble"):
		Items.define(&"kibble", "Kibble").of_kind(Items.Kind.CONSUMABLE) \
			.as_food(14.0, 2.0).look(Color(0.90, 0.62, 0.30), &"round") \
			.worth(45, Items.RARITY_UNCOMMON).stacks(100) \
			.in_category(&"food").tag(&"taming").tag(&"feed").tag(&"kibble") \
			.describe("Cooked down from eggs and vegetables into something a "
				+ "creature will cross a field for. Halves the work of any tame.")
