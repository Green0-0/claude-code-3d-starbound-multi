## Every armour piece in the game.
##
## [b]Naming contract[/b] — the crafting agent's recipes key off these ids:
## [br]• The per-tier ladder is `<metal>_helm` / `<metal>_chest` /
##   `<metal>_greaves`, over exactly the metal ladder that
##   `content/items/10_materials.gd` established: `copper iron silver gold
##   titanium durasteel aegisalt ferozium violium solarium`. Each piece is
##   crafted from `<metal>_bar`.
## [br]• Environmental suits are `<suit>_helm` / `_chest` / `_greaves` with
##   `suit` one of `firewalker frostwalker hazmat vacuum`.
## [br]• Vanity pieces have bespoke ids and carry `&"vanity"`.
##
## [b]Do not look armour up by id if you can avoid it.[/b] Query by tag —
## those are stable even if a piece is renamed:
##
## | tag | meaning |
## |---|---|
## | `armor` | every piece here |
## | `helm` / `chest` / `greaves` | slot |
## | `set_<name>` | the pieces of one set (`set_copper`, `set_vacuum`, ...) |
## | `resist_fire` `resist_ice` `resist_radiation` `resist_vacuum` | environmental protection |
## | `vanity` | cosmetic only, zero defence |
## | `tier_<n>` | progression band |
##
## [b]Resistances[/b] live in `ItemType.stat_bonuses` under the keys
## `resist_<element>` for the six [constant Const.ELEMENTS], plus the two
## environmental pseudo-elements `resist_radiation` and `resist_vacuum` that
## the survival and space modules read. Values are fractions, 0..1. The
## inventory module sums them in `total_resistance(element)`; the combat damage
## pipeline reads that through [method CbtDamage.resistance_of].
##
## Other `stat_bonuses` keys used here, all additive: `max_health`,
## `max_energy`, `energy_regen`, `move_speed`, `jump_speed`, `mining_speed`,
## `crit_chance`, `warmth`, `oxygen`, `fall_damage`.
extends RefCounted

## key, display, colour, tool tier, rank (1..10), rarity
const METALS := [
	[&"copper", "Copper", Color(0.84, 0.48, 0.24), 0, 1, Const.RARITY_COMMON],
	[&"iron", "Iron", Color(0.66, 0.62, 0.58), 1, 2, Const.RARITY_COMMON],
	[&"silver", "Silver", Color(0.86, 0.88, 0.92), 1, 3, Const.RARITY_COMMON],
	[&"gold", "Gold", Color(0.96, 0.79, 0.28), 2, 4, Const.RARITY_UNCOMMON],
	[&"titanium", "Titanium", Color(0.72, 0.76, 0.80), 2, 5, Const.RARITY_UNCOMMON],
	[&"durasteel", "Durasteel", Color(0.45, 0.50, 0.56), 3, 6, Const.RARITY_UNCOMMON],
	[&"aegisalt", "Aegisalt", Color(0.36, 0.62, 0.60), 4, 7, Const.RARITY_RARE],
	[&"ferozium", "Ferozium", Color(0.35, 0.85, 0.66), 5, 8, Const.RARITY_RARE],
	[&"violium", "Violium", Color(0.60, 0.34, 0.78), 5, 9, Const.RARITY_RARE],
	[&"solarium", "Solarium", Color(0.98, 0.90, 0.42), 6, 10, Const.RARITY_LEGENDARY],
]

## suffix, display noun, slot, defence multiplier, icon
const PIECES := [
	[&"helm", "Helm", ItemType.SLOT_HEAD, 0.85, &"helm"],
	[&"chest", "Chestplate", ItemType.SLOT_CHEST, 1.5, &"chest"],
	[&"greaves", "Greaves", ItemType.SLOT_LEGS, 1.05, &"greaves"],
]

## Set bonuses, granted when all three pieces of a set are worn together.
##
## The inventory module owns the "is the set complete" check; it can find the
## members with `Items.all_with_tag(&"set_<name>")` and read the bonus here via
## `load("res://content/items/31_armor.gd").set_bonus(&"copper")`.
const SET_BONUSES := {
	&"copper": {"name": "Prospector", "max_health": 8.0, "mining_speed": 0.08,
		"text": "Prospector: +8 health, +8% mining speed."},
	&"iron": {"name": "Ironclad", "max_health": 16.0, "defense": 3.0,
		"text": "Ironclad: +16 health, +3 defence."},
	&"silver": {"name": "Quicksilver", "move_speed": 0.1, "max_energy": 15.0,
		"text": "Quicksilver: +10% move speed, +15 energy."},
	&"gold": {"name": "Gilded", "max_health": 24.0, "value_bonus": 0.15,
		"text": "Gilded: +24 health, vendors pay 15% more."},
	&"titanium": {"name": "Aerodyne", "jump_speed": 0.12, "fall_damage": -0.4,
		"text": "Aerodyne: +12% jump, 40% less fall damage."},
	&"durasteel": {"name": "Siegeworks", "defense": 9.0, "knockback_taken": -0.3,
		"text": "Siegeworks: +9 defence, 30% less knockback taken."},
	&"aegisalt": {"name": "Deflector", "defense": 12.0, "resist_physical": 0.1,
		"text": "Deflector: +12 defence, 10% physical resistance."},
	&"ferozium": {"name": "Overcharge", "max_energy": 60.0, "energy_regen": 0.35,
		"text": "Overcharge: +60 energy, +35% energy regeneration."},
	&"violium": {"name": "Duellist", "crit_chance": 0.08, "move_speed": 0.08,
		"text": "Duellist: +8% critical chance, +8% move speed."},
	&"solarium": {"name": "Solar Crown", "max_health": 60.0, "max_energy": 60.0,
		"defense": 18.0, "resist_cosmic": 0.15,
		"text": "Solar Crown: +60 health, +60 energy, +18 defence, 15% cosmic resistance."},
	&"firewalker": {"name": "Firewalker", "resist_fire": 0.25, "warmth": 30.0,
		"text": "Firewalker: fully immune to ambient heat, +25% fire resistance."},
	&"frostwalker": {"name": "Frostwalker", "resist_ice": 0.25, "warmth": -30.0,
		"text": "Frostwalker: fully immune to ambient cold, +25% ice resistance."},
	&"hazmat": {"name": "Sealed", "resist_radiation": 0.3, "resist_poison": 0.2,
		"text": "Sealed: complete radiation seal, +20% poison resistance."},
	&"vacuum": {"name": "Untethered", "resist_vacuum": 0.35, "oxygen": 120.0,
		"text": "Untethered: +120 seconds of oxygen, safe in hard vacuum."},
}


static func register_all(reg) -> void:
	_ladder(reg)
	_environment_suits(reg)
	_vanity(reg)


## The set bonus dictionary for a set id, or an empty dictionary.
static func set_bonus(set_id: StringName) -> Dictionary:
	return SET_BONUSES.get(set_id, {})


## Every set id that has a bonus.
static func set_ids() -> Array:
	return SET_BONUSES.keys()


# ============================================================= shared builder
static func _a(reg, id: StringName, display: String, slot: StringName, tier: int,
		defense: float, rarity: int, color: Color, icon: StringName, desc: String,
		bonuses: Dictionary = {}, tags: Array = []) -> ItemType:
	if reg.has(id):
		return reg.get_type(id)
	var it: ItemType = reg.define(id, display)
	it.of_kind(ItemType.Kind.ARMOR)
	it.as_armor(slot, snappedf(defense, 0.1))
	it.look(color, icon)
	it.describe(desc)
	it.worth(int((14 + 16 * tier) * (1 + rarity)), rarity)
	it.in_category(&"armor")
	it.tag(&"armor")
	it.tag(StringName("tier_%d" % tier))
	it.tool_tier = tier
	match slot:
		ItemType.SLOT_HEAD:
			it.tag(&"helm")
		ItemType.SLOT_CHEST:
			it.tag(&"chest")
		ItemType.SLOT_LEGS:
			it.tag(&"greaves")
	for k: String in bonuses:
		it.bonus(k, float(bonuses[k]))
	for t: Variant in tags:
		it.tag(StringName(t))
	return it


# =============================================================== metal ladder
static func _ladder(reg) -> void:
	for m: Array in METALS:
		var key: StringName = m[0]
		var mdisplay: String = m[1]
		var color: Color = m[2]
		var tier: int = m[3]
		var rank: int = m[4]
		var rarity: int = m[5]
		var base := 2.0 + 2.4 * float(rank) + 0.22 * float(rank * rank)
		var bonus_text: String = String(SET_BONUSES.get(key, {}).get("text", ""))
		for p: Array in PIECES:
			var suffix: StringName = p[0]
			var noun: String = p[1]
			var slot: StringName = p[2]
			var mult: float = p[3]
			var icon: StringName = p[4]
			var bonuses := _ladder_bonuses(key, suffix, rank)
			_a(reg, StringName("%s_%s" % [key, suffix]),
				"%s %s" % [mdisplay, noun], slot, tier, base * mult, rarity,
				color, icon,
				"%s plate, shaped and riveted.\nSet bonus — %s" % [mdisplay, bonus_text],
				bonuses, [&"craftable", &"ladder", StringName("set_" + String(key))])


## Per-piece stat sprinkles so a mixed loadout is a real decision rather than
## a strictly worse one.
static func _ladder_bonuses(key: StringName, piece: StringName, rank: int) -> Dictionary:
	var out := {}
	var r := float(rank)
	match piece:
		&"helm":
			out["max_energy"] = 3.0 * r
		&"chest":
			out["max_health"] = 4.0 * r
		&"greaves":
			out["move_speed"] = 0.012 * r
	# The high-tier metals carry their own elemental flavour.
	match key:
		&"gold":
			out["value_bonus"] = 0.03
		&"titanium":
			out["jump_speed"] = 0.02
		&"durasteel":
			out["resist_physical"] = 0.03
		&"aegisalt":
			out["resist_electric"] = 0.05
		&"ferozium":
			out["resist_poison"] = 0.05
			out["energy_regen"] = 0.05
		&"violium":
			out["crit_chance"] = 0.012
		&"solarium":
			out["resist_fire"] = 0.06
			out["resist_cosmic"] = 0.05
	return out


# =========================================================== environment suits
## The four survival suits. The survival module (temperature, radiation) and
## the space module (vacuum, oxygen) both need these to exist, so they are
## defined here even though the effects are applied elsewhere.
static func _environment_suits(reg) -> void:
	var suits := [
		{
			"key": &"firewalker", "display": "Firewalker", "tier": 3,
			"color": Color(0.88, 0.4, 0.18), "rarity": Const.RARITY_UNCOMMON,
			"resist": &"resist_fire", "amount": 0.28,
			"extra": {"warmth": 12.0},
			"tag": &"resist_fire",
			"desc": "Ceramic scale over a heat-shedding weave. Walks on lava\n"
				+ "flows without noticing, and shrugs off most fire damage.",
		},
		{
			"key": &"frostwalker", "display": "Frostwalker", "tier": 3,
			"color": Color(0.55, 0.82, 0.95), "rarity": Const.RARITY_UNCOMMON,
			"resist": &"resist_ice", "amount": 0.28,
			"extra": {"warmth": -12.0},
			"tag": &"resist_ice",
			"desc": "Insulated, sealed and heated at the seams. Ice worlds stop\n"
				+ "being a countdown and start being scenery.",
		},
		{
			"key": &"hazmat", "display": "Hazmat", "tier": 4,
			"color": Color(0.85, 0.85, 0.35), "rarity": Const.RARITY_RARE,
			"resist": &"resist_radiation", "amount": 0.3,
			"extra": {"resist_poison": 0.15},
			"tag": &"resist_radiation",
			"desc": "Lead-lined and positively pressurised. The dosimeter on the\n"
				+ "chest has never gone above green, which is either reassuring\n"
				+ "or broken.",
		},
		{
			"key": &"vacuum", "display": "Vacuum", "tier": 5,
			"color": Color(0.82, 0.86, 0.9), "rarity": Const.RARITY_RARE,
			"resist": &"resist_vacuum", "amount": 0.35,
			"extra": {"oxygen": 40.0, "resist_cosmic": 0.08},
			"tag": &"resist_vacuum",
			"desc": "A real pressure suit with a real air supply. Required for\n"
				+ "anywhere without a sky, which is most places.",
		},
	]
	for s: Dictionary in suits:
		var key: StringName = s["key"]
		var tier: int = int(s["tier"])
		var base := 3.0 + 2.0 * float(tier)
		var bonus_text: String = String(SET_BONUSES.get(key, {}).get("text", ""))
		for p: Array in PIECES:
			var suffix: StringName = p[0]
			var noun: String = p[1]
			var slot: StringName = p[2]
			var mult: float = p[3]
			var icon: StringName = p[4]
			var bonuses := {}
			bonuses[String(s["resist"])] = float(s["amount"]) * (0.5 if suffix != &"chest" else 1.0)
			for k: String in (s["extra"] as Dictionary):
				bonuses[k] = float((s["extra"] as Dictionary)[k]) * (0.5 if suffix != &"chest" else 1.0)
			_a(reg, StringName("%s_%s" % [key, suffix]),
				"%s %s" % [String(s["display"]), noun], slot, tier,
				base * mult, int(s["rarity"]), s["color"] as Color, icon,
				"%s\nSet bonus — %s" % [String(s["desc"]), bonus_text],
				bonuses,
				[&"craftable", &"suit", StringName(s["tag"]),
					StringName("set_" + String(key))])


# ===================================================================== vanity
## Cosmetic only: zero defence, no bonuses, worn in the vanity slots. They
## exist so the paper-doll renderer and the wardrobe UI have something to show.
static func _vanity(reg) -> void:
	var rows := [
		[&"straw_hat", "Straw Hat", ItemType.SLOT_HEAD, &"helm", Color(0.85, 0.74, 0.42),
			"Wide brim, honest intentions. Keeps exactly one star off your face."],
		[&"captains_cap", "Captain's Cap", ItemType.SLOT_HEAD, &"helm", Color(0.16, 0.2, 0.34),
			"Someone's rank, somebody else's ship. Fits surprisingly well."],
		[&"tinfoil_crown", "Tinfoil Crown", ItemType.SLOT_HEAD, &"helm", Color(0.86, 0.88, 0.9),
			"Blocks nothing. Declares everything."],
		[&"welding_goggles", "Welding Goggles", ItemType.SLOT_HEAD, &"helm", Color(0.4, 0.34, 0.28),
			"Scratched to translucency. Worn on the forehead, universally."],
		[&"flight_jacket", "Flight Jacket", ItemType.SLOT_CHEST, &"chest", Color(0.42, 0.28, 0.18),
			"Cracked leather, six squadron patches, none of them yours."],
		[&"lab_coat", "Lab Coat", ItemType.SLOT_CHEST, &"chest", Color(0.92, 0.93, 0.95),
			"Immaculate. The pockets are full of somebody's unfinished notes."],
		[&"poncho", "Star-Weave Poncho", ItemType.SLOT_CHEST, &"chest", Color(0.6, 0.4, 0.7),
			"Hand-woven on a world with two suns and no looms worth the name."],
		[&"work_trousers", "Work Trousers", ItemType.SLOT_LEGS, &"greaves", Color(0.28, 0.34, 0.5),
			"Reinforced knees. Every pocket contains one bolt of unknown thread."],
		[&"survey_leggings", "Survey Leggings", ItemType.SLOT_LEGS, &"greaves", Color(0.34, 0.42, 0.36),
			"Ripstop, forty pockets, and a permanent smell of somewhere else."],
		[&"gala_skirt", "Gala Skirt", ItemType.SLOT_LEGS, &"greaves", Color(0.75, 0.2, 0.42),
			"For the one night a decade when somebody throws a party."],
	]
	for r: Array in rows:
		_a(reg, r[0], String(r[1]), r[2], 0, 0.0, Const.RARITY_COMMON,
			r[4] as Color, r[3], String(r[5]), {},
			[&"vanity", &"cosmetic", &"no_defense"])
