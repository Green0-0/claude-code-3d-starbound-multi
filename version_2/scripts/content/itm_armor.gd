extends RefCounted

## Every armour piece.
##
## **Naming contract** — the recipe book keys off these ids: the ladder is
## `<metal>_helm` / `<metal>_chest` / `<metal>_greaves`, and the environmental
## suits are `<suit>_helm` / `_chest` / `_greaves` with `suit` one of
## `firewalker frostwalker hazmat vacuum`.
##
## Prefer querying by tag over by id — `armor`, `helm`/`chest`/`greaves`,
## `set_<name>`, `resist_fire`/`resist_ice`/`resist_radiation`/`resist_vacuum`,
## `vanity`, `tier_<n>`.
##
## Resistances live in `stat_bonuses` under `resist_<element>` for the six
## elements, plus `resist_radiation` and `resist_vacuum` that the survival and
## space modules read. Values are fractions 0..1; the inventory sums them and
## the damage pipeline reads the total.

const METALS := [
	[&"copper", "Copper", Color(0.84, 0.48, 0.24), 0, 1, 0],
	[&"iron", "Iron", Color(0.66, 0.62, 0.58), 1, 2, 0],
	[&"silver", "Silver", Color(0.86, 0.88, 0.92), 1, 3, 0],
	[&"gold", "Gold", Color(0.96, 0.79, 0.28), 2, 4, 1],
	[&"titanium", "Titanium", Color(0.72, 0.76, 0.80), 2, 5, 1],
	[&"durasteel", "Durasteel", Color(0.45, 0.50, 0.56), 3, 6, 1],
	[&"aegisalt", "Aegisalt", Color(0.36, 0.62, 0.60), 4, 7, 2],
	[&"ferozium", "Ferozium", Color(0.35, 0.85, 0.66), 5, 8, 2],
	[&"violium", "Violium", Color(0.60, 0.34, 0.78), 5, 9, 2],
	[&"solarium", "Solarium", Color(0.98, 0.90, 0.42), 6, 10, 3],
]

## suffix, noun, slot, defence multiplier, icon
const PIECES := [
	[&"helm", "Helm", Items.SLOT_HEAD, 0.85, &"helm"],
	[&"chest", "Chestplate", Items.SLOT_CHEST, 1.5, &"chest"],
	[&"greaves", "Greaves", Items.SLOT_LEGS, 1.05, &"greaves"],
]

## Granted only when all three pieces of a set are worn together.
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
		"text": "Solar Crown: +60 health, +60 energy, +18 defence, 15% cosmic resist."},
	&"firewalker": {"name": "Firewalker", "resist_fire": 0.25, "warmth": 30.0,
		"text": "Firewalker: immune to ambient heat, +25% fire resistance."},
	&"frostwalker": {"name": "Frostwalker", "resist_ice": 0.25, "warmth": -30.0,
		"text": "Frostwalker: immune to ambient cold, +25% ice resistance."},
	&"hazmat": {"name": "Sealed", "resist_radiation": 0.3, "resist_poison": 0.2,
		"text": "Sealed: complete radiation seal, +20% poison resistance."},
	&"vacuum": {"name": "Untethered", "resist_vacuum": 0.35, "oxygen": 120.0,
		"text": "Untethered: +120 seconds of oxygen, safe in hard vacuum."},
}


static func set_bonus(set_id: StringName) -> Dictionary:
	return SET_BONUSES.get(set_id, {})


static func set_ids() -> Array:
	return SET_BONUSES.keys()


static func a(id: StringName, display: String, slot: StringName, tier: int,
		defense: float, rarity: int, color: Color, icon: StringName, desc: String,
		bonuses := {}, tags: Array = []) -> Items.Type:
	if Items.has(id):
		return Items.get_type(id)
	var it := Items.define(id, display)
	it.as_armor(slot, snappedf(defense, 0.1))
	it.look(color, icon).describe(desc)
	it.worth(int((14 + 16 * tier) * (1 + rarity)), rarity)
	it.in_category(&"armor").tag(&"armor").tag(StringName("tier_%d" % tier))
	it.tool_tier = tier
	match slot:
		Items.SLOT_HEAD: it.tag(&"helm")
		Items.SLOT_CHEST: it.tag(&"chest")
		Items.SLOT_LEGS: it.tag(&"greaves")
	for k: String in bonuses:
		it.bonus(k, float(bonuses[k]))
	for t in tags:
		it.tag(StringName(t))
	return it


static func register_all() -> void:
	_ladder()
	_environment_suits()
	_vanity()


static func _ladder() -> void:
	for m: Array in METALS:
		var key: StringName = m[0]
		var mdisplay: String = m[1]
		var tier: int = m[3]
		var rank: int = m[4]
		var base := 2.0 + 2.4 * float(rank) + 0.22 * float(rank * rank)
		var bonus_text := String(SET_BONUSES.get(key, {}).get("text", ""))
		for p: Array in PIECES:
			a(StringName("%s_%s" % [key, p[0]]), "%s %s" % [mdisplay, p[1]],
				p[2], tier, base * float(p[3]), int(m[5]), m[2], p[4],
				"%s plate, shaped and riveted.\nSet bonus — %s" % [mdisplay, bonus_text],
				_ladder_bonuses(key, p[0], rank),
				[&"craftable", &"ladder", StringName("set_" + String(key))])


## Per-piece sprinkles, so a mixed loadout is a real decision rather than a
## strictly worse one.
static func _ladder_bonuses(key: StringName, piece: StringName, rank: int) -> Dictionary:
	var out := {}
	var r := float(rank)
	match piece:
		&"helm": out["max_energy"] = 3.0 * r
		&"chest": out["max_health"] = 4.0 * r
		&"greaves": out["move_speed"] = 0.012 * r
	match key:
		&"gold": out["value_bonus"] = 0.03
		&"titanium": out["jump_speed"] = 0.02
		&"durasteel": out["resist_physical"] = 0.03
		&"aegisalt": out["resist_electric"] = 0.05
		&"ferozium":
			out["resist_poison"] = 0.05
			out["energy_regen"] = 0.05
		&"violium": out["crit_chance"] = 0.012
		&"solarium":
			out["resist_fire"] = 0.06
			out["resist_cosmic"] = 0.05
	return out


## The four survival suits. Temperature, radiation and vacuum all read these.
static func _environment_suits() -> void:
	var suits := [
		{"key": &"firewalker", "display": "Firewalker", "tier": 3,
			"color": Color(0.88, 0.4, 0.18), "rarity": Items.RARITY_UNCOMMON,
			"resist": "resist_fire", "amount": 0.28, "extra": {"warmth": 12.0},
			"tag": &"resist_fire",
			"desc": "Ceramic scale over a heat-shedding weave. Walks a lava flow\n"
				+ "without noticing, and shrugs off most fire damage."},
		{"key": &"frostwalker", "display": "Frostwalker", "tier": 3,
			"color": Color(0.55, 0.82, 0.95), "rarity": Items.RARITY_UNCOMMON,
			"resist": "resist_ice", "amount": 0.28, "extra": {"warmth": -12.0},
			"tag": &"resist_ice",
			"desc": "Insulated, sealed and heated at the seams. Ice worlds stop\n"
				+ "being a countdown and start being scenery."},
		{"key": &"hazmat", "display": "Hazmat", "tier": 4,
			"color": Color(0.85, 0.85, 0.35), "rarity": Items.RARITY_RARE,
			"resist": "resist_radiation", "amount": 0.3,
			"extra": {"resist_poison": 0.15}, "tag": &"resist_radiation",
			"desc": "Lead-lined and positively pressurised. The dosimeter has\n"
				+ "never gone above green, which is either reassuring or broken."},
		{"key": &"vacuum", "display": "Vacuum", "tier": 5,
			"color": Color(0.82, 0.86, 0.9), "rarity": Items.RARITY_RARE,
			"resist": "resist_vacuum", "amount": 0.35,
			"extra": {"oxygen": 40.0, "resist_cosmic": 0.08}, "tag": &"resist_vacuum",
			"desc": "A real pressure suit with a real air supply. Required for\n"
				+ "anywhere without a sky, which is most places."},
	]
	for s: Dictionary in suits:
		var key: StringName = s["key"]
		var tier: int = int(s["tier"])
		var base := 3.0 + 2.0 * float(tier)
		var bonus_text := String(SET_BONUSES.get(key, {}).get("text", ""))
		for p: Array in PIECES:
			var scale := 1.0 if p[0] == &"chest" else 0.5
			var bonuses := {}
			bonuses[String(s["resist"])] = float(s["amount"]) * scale
			for k: String in (s["extra"] as Dictionary):
				bonuses[k] = float((s["extra"] as Dictionary)[k]) * scale
			a(StringName("%s_%s" % [key, p[0]]),
				"%s %s" % [String(s["display"]), p[1]], p[2], tier,
				base * float(p[3]), int(s["rarity"]), s["color"] as Color, p[4],
				"%s\nSet bonus — %s" % [String(s["desc"]), bonus_text], bonuses,
				[&"craftable", &"suit", StringName(s["tag"]),
					StringName("set_" + String(key))])


## Cosmetic only: zero defence, no bonuses.
static func _vanity() -> void:
	var rows := [
		[&"straw_hat", "Straw Hat", Items.SLOT_HEAD, &"helm", Color(0.85, 0.74, 0.42),
			"Wide brim, honest intentions. Keeps exactly one star off your face."],
		[&"captains_cap", "Captain's Cap", Items.SLOT_HEAD, &"helm", Color(0.16, 0.2, 0.34),
			"Someone's rank, somebody else's ship. Fits surprisingly well."],
		[&"flight_jacket", "Flight Jacket", Items.SLOT_CHEST, &"chest", Color(0.42, 0.28, 0.18),
			"Cracked leather, six squadron patches, none of them yours."],
		[&"lab_coat", "Lab Coat", Items.SLOT_CHEST, &"chest", Color(0.92, 0.93, 0.95),
			"Immaculate. The pockets are full of somebody's unfinished notes."],
		[&"work_trousers", "Work Trousers", Items.SLOT_LEGS, &"greaves", Color(0.28, 0.34, 0.5),
			"Reinforced knees. Every pocket holds one bolt of unknown thread."],
		[&"survey_leggings", "Survey Leggings", Items.SLOT_LEGS, &"greaves", Color(0.34, 0.42, 0.36),
			"Ripstop, forty pockets, a permanent smell of somewhere else."],
	]
	for r: Array in rows:
		a(r[0], String(r[1]), r[2], 0, 0.0, Items.RARITY_COMMON, r[4] as Color,
			r[3], String(r[5]), {}, [&"vanity", &"cosmetic", &"no_defense"])
