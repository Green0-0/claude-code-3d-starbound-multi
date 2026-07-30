extends RefCounted

## Every hand-authored weapon.
##
## **Naming contract** — the recipe book keys off these ids:
##   * the per-tier ladder is `<metal>_<archetype>` over the same metal ladder
##     the materials file established, with archetypes `sword spear hammer bow
##     gun`, each crafted from `<metal>_bar`;
##   * procedurally generated weapons are written onto the `gen_<archetype>`
##     base items — never craft or sell those directly;
##   * uniques and boss drops have bespoke ids and carry `unique` / `boss_drop`.
##
## Every weapon carries its archetype tag, which is what the combat code reads
## to pick a swing behaviour, plus a `tier_<n>` tag and optionally:
##   * `special_<id>` — a secondary-fire special;
##   * `cutaway_pierce` / `cutaway_occluded` / `cutaway_depth` — the three
##     weapons built around the camera-obstruction system. This is the signature
##     mechanic in item form: one ignores the cross-section entirely and hits
##     what the cutaway is hiding, one hits *only* what is currently sliced away,
##     and one detonates along the camera's line of sight.

## key, display, colour, tool tier, rank 1..10, rarity
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

## suffix, noun, archetype, damage multiplier, speed, icon, blurb
const LADDER := [
	[&"sword", "Sword", &"broadsword", 1.0, 1.0, &"sword",
		"A straight blade with a wide arc. Reliable, unfussy, lethal."],
	[&"spear", "Spear", &"spear", 1.1, 0.85, &"spear",
		"Reach beats speed. Skewers everything on the line in front of you."],
	[&"hammer", "Hammer", &"hammer", 1.5, 0.6, &"hammer",
		"Slow enough to regret, heavy enough not to. Smashes the wall too."],
	[&"bow", "Bow", &"bow", 0.95, 1.0, &"bow",
		"Draw to full for a flat, fast shot. Half-drawn arrows drop like stones."],
	[&"gun", "Blaster", &"gun", 0.8, 1.5, &"gun",
		"Costs energy, not arrows. The bolt crosses the screen almost at once."],
]


static func w(id: StringName, display: String, arch: StringName, tier: int,
		dmg: float, speed: float, elem: StringName, rarity: int, color: Color,
		icon: StringName, desc: String, extra := {}, tags: Array = []) -> Items.Type:
	if Items.has(id):
		return Items.get_type(id)
	var it := Items.define(id, display)
	it.as_weapon(snappedf(dmg, 0.1), snappedf(speed, 0.01), elem)
	it.look(color, icon).describe(desc)
	it.worth(int((18 + 20 * tier) * (1 + rarity)), rarity)
	it.in_category(&"weapons").tag(&"weapon").tag(arch)
	it.tag(StringName("tier_%d" % tier))
	it.tool_tier = tier
	for t in tags:
		it.tag(StringName(t))
	if not extra.is_empty():
		it.flags(extra)
	return it


static func register_all() -> void:
	_ladder()
	_generator_bases()
	_uniques()
	_cutaway_weapons()
	_boss_drops()


# ============================================================== the ladder ====
static func _ladder() -> void:
	for m: Array in METALS:
		var key: StringName = m[0]
		var mdisplay: String = m[1]
		var color: Color = m[2]
		var tier: int = m[3]
		var rank: int = m[4]
		var rarity: int = m[5]
		# gentle early, steep once you leave the home planet
		var base := 6.0 + 4.4 * float(rank) + 0.36 * float(rank * rank)
		for row: Array in LADDER:
			var arch: StringName = row[2]
			var extra := {"knockback": 4.0 + 0.3 * float(rank)}
			match arch:
				&"bow":
					extra["projectile"] = &"bolt" if rank >= 9 else &"arrow"
					extra["two_handed"] = true
				&"gun":
					extra["projectile"] = &"plasma" if rank >= 9 else &"bullet"
					extra["energy_cost"] = 2.0 + 0.35 * float(rank)
				&"hammer":
					extra["knockback"] = 9.0 + 0.8 * float(rank)
					extra["two_handed"] = true
				&"spear":
					extra["two_handed"] = true
			# the top of the ladder starts carrying an element of its own
			var elem := Blocks.ELEM_PHYSICAL
			if key == &"ferozium":
				elem = Blocks.ELEM_POISON
			elif key == &"violium":
				elem = Blocks.ELEM_ELECTRIC
			elif key == &"solarium":
				elem = Blocks.ELEM_FIRE
			w(StringName("%s_%s" % [key, row[0]]), "%s %s" % [mdisplay, row[1]],
				arch, tier, base * float(row[3]), float(row[4]), elem, rarity,
				color, row[5], "%s\nForged from %s bars." % [row[6], mdisplay.to_lower()],
				extra, [&"craftable", &"ladder"])


# ==================================================== procedural base items ====
## One inert base per archetype. The weapon generator stamps its rolls into a
## stack's `data`, and `Stack.stat()` prefers those over these defaults — so
## these numbers only ever show if something generated a weapon wrong.
static func _generator_bases() -> void:
	var rows := [
		[&"broadsword", "Blade", 14.0, 1.0, &"sword", 0.0, &""],
		[&"shortsword", "Shortsword", 10.0, 1.7, &"sword", 0.0, &""],
		[&"spear", "Spear", 15.0, 0.95, &"spear", 0.0, &""],
		[&"hammer", "Hammer", 22.0, 0.62, &"hammer", 0.0, &""],
		[&"dagger", "Dagger", 7.0, 2.3, &"dagger", 0.0, &""],
		[&"whip", "Whip", 9.0, 1.1, &"whip", 0.0, &""],
		[&"shield", "Shield", 6.0, 1.2, &"shield", 0.0, &""],
		[&"bow", "Bow", 13.0, 1.0, &"bow", 0.0, &"arrow"],
		[&"gun", "Gun", 9.0, 1.6, &"gun", 3.0, &"bullet"],
		[&"shotgun", "Shotgun", 20.0, 0.8, &"gun", 6.0, &"pellet"],
		[&"rocket", "Launcher", 30.0, 0.55, &"gun", 18.0, &"rocket"],
		[&"flamethrower", "Flamethrower", 12.0, 2.0, &"gun", 1.2, &"flame_gout"],
		[&"staff", "Staff", 12.0, 1.0, &"staff", 9.0, &"star_bolt"],
		[&"boomerang", "Boomerang", 11.0, 1.1, &"boomerang", 0.0, &"boomerang"],
		[&"grenade", "Bombard", 24.0, 0.9, &"grenade", 6.0, &"grenade"],
	]
	for r: Array in rows:
		var extra := {}
		if float(r[5]) > 0.0:
			extra["energy_cost"] = float(r[5])
		if StringName(r[6]) != &"":
			extra["projectile"] = StringName(r[6])
		w(StringName("gen_" + String(r[0])), String(r[1]), r[0], 2,
			float(r[2]), float(r[3]), Blocks.ELEM_PHYSICAL, Items.RARITY_COMMON,
			Color(0.7, 0.7, 0.75), r[4],
			"An unremarkable %s, waiting for a story." % String(r[1]).to_lower(),
			extra, [&"generated", &"no_sell"])


# ================================================================= uniques ====
static func _uniques() -> void:
	w(&"starcleaver", "Starcleaver", &"broadsword", 5, 46.0, 0.95,
		Blocks.ELEM_COSMIC, Items.RARITY_LEGENDARY, Color(0.72, 0.62, 1.0), &"sword",
		"A blade of compressed starlight. It sings on the downswing and the note\n"
		+ "does not stop when the swing does.",
		{"knockback": 8.0, "two_handed": true}, [&"unique", &"special_spin_slash"])
	w(&"widowmaker", "Widowmaker", &"dagger", 4, 13.0, 2.6,
		Blocks.ELEM_POISON, Items.RARITY_RARE, Color(0.4, 0.75, 0.35), &"dagger",
		"Thin, black, and coated in something that never quite dries.\n"
		+ "Devastating when the target has not noticed you yet.",
		{"knockback": 1.0}, [&"unique", &"special_dash_strike"])
	w(&"thundercoil", "Thundercoil", &"whip", 5, 21.0, 1.1,
		Blocks.ELEM_ELECTRIC, Items.RARITY_RARE, Color(0.8, 0.85, 1.0), &"whip",
		"Superconducting cable on a dead man's switch. Every crack earths itself\n"
		+ "through whatever it touches.",
		{"knockback": 11.0}, [&"unique", &"special_chain_bolt"])
	w(&"mirror_aegis", "Mirror Aegis", &"shield", 6, 12.0, 1.4,
		Blocks.ELEM_COSMIC, Items.RARITY_LEGENDARY, Color(0.85, 0.9, 1.0), &"shield",
		"Perfectly reflective, perfectly cold. A well-timed parry sends the whole\n"
		+ "attack back where it came from.",
		{"knockback": 16.0}, [&"unique", &"special_nova"])
	w(&"glacier_spike", "Glacier Spike", &"spear", 5, 41.0, 0.8,
		Blocks.ELEM_ICE, Items.RARITY_RARE, Color(0.6, 0.88, 1.0), &"spear",
		"A single crystal grown over four hundred years in a cave that no longer\n"
		+ "exists. It does not melt.",
		{"knockback": 7.0, "two_handed": true}, [&"unique"])
	w(&"hunters_recurve", "Hunter's Recurve", &"bow", 3, 24.0, 1.15,
		Blocks.ELEM_PHYSICAL, Items.RARITY_UNCOMMON, Color(0.68, 0.5, 0.3), &"bow",
		"Light, quick, and honest. Draws faster than anything else that hits\n"
		+ "this hard.",
		{"projectile": &"arrow", "two_handed": true}, [&"unique"])
	w(&"plasma_repeater", "Plasma Repeater", &"gun", 5, 19.0, 2.1,
		Blocks.ELEM_ELECTRIC, Items.RARITY_RARE, Color(0.5, 0.9, 1.0), &"gun",
		"Vents heat through the grip, which you will notice. Fires until your\n"
		+ "energy runs out, which you will also notice.",
		{"projectile": &"plasma", "energy_cost": 3.5}, [&"unique"])
	w(&"scattercannon", "Scattercannon", &"shotgun", 4, 44.0, 0.75,
		Blocks.ELEM_PHYSICAL, Items.RARITY_RARE, Color(0.6, 0.55, 0.5), &"gun",
		"Seven pellets, one trigger, no subtlety whatsoever. Point it at the thing\n"
		+ "that is already touching you.",
		{"projectile": &"pellet", "energy_cost": 6.0, "two_handed": true}, [&"unique"])
	w(&"dragons_breath", "Dragon's Breath", &"flamethrower", 5, 26.0, 2.0,
		Blocks.ELEM_FIRE, Items.RARITY_RARE, Color(1.0, 0.55, 0.2), &"gun",
		"A cone of burning fuel, continuously. Sets the ground alight and keeps\n"
		+ "it that way.",
		{"projectile": &"flame_gout", "energy_cost": 1.4, "two_handed": true},
		[&"unique"])
	w(&"staff_of_embers", "Staff of Embers", &"staff", 3, 22.0, 1.0,
		Blocks.ELEM_FIRE, Items.RARITY_UNCOMMON, Color(1.0, 0.6, 0.25), &"staff",
		"A branch that burned once and decided to keep going.",
		{"projectile": &"fireball", "energy_cost": 10.0, "two_handed": true},
		[&"unique"])
	w(&"stormcaller", "Stormcaller", &"staff", 6, 38.0, 0.9,
		Blocks.ELEM_ELECTRIC, Items.RARITY_LEGENDARY, Color(0.85, 0.9, 1.0), &"staff",
		"The bolt jumps from body to body until it runs out of bodies.",
		{"projectile": &"lightning_arc", "energy_cost": 16.0, "two_handed": true},
		[&"unique", &"special_chain_bolt"])
	w(&"returning_chakram", "Returning Chakram", &"boomerang", 4, 24.0, 1.2,
		Blocks.ELEM_PHYSICAL, Items.RARITY_RARE, Color(0.85, 0.72, 0.35), &"disc",
		"Hits on the way out, hits on the way back, and refuses to be thrown\n"
		+ "again until it is home.",
		{"projectile": &"boomerang"}, [&"unique"])


# ====================================================== cutaway weapons ====
## The three weapons built entirely around the camera-obstruction system. These
## are the reason the cut predicate is shared between CPU and GPU: each of them
## asks it a question at the moment of the swing.
static func _cutaway_weapons() -> void:
	# 1. Ignores the cut entirely. The answer to "it is hiding inside the hill".
	w(&"phase_lance", "Phase Lance", &"gun", 6, 30.0, 0.85,
		Blocks.ELEM_COSMIC, Items.RARITY_LEGENDARY, Color(0.72, 0.5, 1.0), &"gun",
		"Fires a lance of phase-shifted light that does not acknowledge solid\n"
		+ "matter. It passes through the terrain the cutaway has not bothered to\n"
		+ "remove and lands on whatever was standing behind it.\n"
		+ "[Pierces terrain along the line of sight.]",
		{"projectile": &"phase_lance", "energy_cost": 14.0, "two_handed": true},
		[&"unique", &"cutaway_pierce", &"special_phase_pierce", &"perspective"])

	# 2. Hits ONLY what is currently sliced away. Useless in the open.
	w(&"revenant_edge", "Revenant Edge", &"broadsword", 6, 62.0, 1.05,
		Blocks.ELEM_COSMIC, Items.RARITY_LEGENDARY, Color(0.5, 0.42, 0.72), &"sword",
		"The blade is half a step out of phase with the world. It passes clean\n"
		+ "through anything standing in the open and lands with terrible weight\n"
		+ "on whatever the cross-section has opened up.\n"
		+ "[Strikes only through the cutaway. Harmless in the open.]",
		{"knockback": 7.0}, [&"unique", &"cutaway_occluded", &"perspective"])

	# 3. Detonates along the camera's line of sight rather than in a sphere.
	w(&"depth_charge_launcher", "Depth Charge Launcher", &"grenade", 6, 44.0, 0.7,
		Blocks.ELEM_ICE, Items.RARITY_LEGENDARY, Color(0.4, 0.7, 0.85), &"gun",
		"Lobs a charge that sinks into the screen before it goes off, and the\n"
		+ "blast propagates back along the lens axis instead of outward.\n"
		+ "Nothing between you and the camera is far enough away.\n"
		+ "[Blast runs down the camera's line of sight.]",
		{"projectile": &"depth_charge", "energy_cost": 16.0, "two_handed": true},
		[&"unique", &"cutaway_depth", &"special_depth_bomb", &"perspective"])


# ============================================================= boss drops ====
static func _boss_drops() -> void:
	w(&"magma_maul", "Magma Maul", &"hammer", 5, 96.0, 0.5,
		Blocks.ELEM_FIRE, Items.RARITY_LEGENDARY, Color(0.85, 0.35, 0.15), &"hammer",
		"Taken from the thing at the bottom of the shaft. Each landing cracks the\n"
		+ "stone and throws a ring of fire out of the crater.",
		{"knockback": 22.0, "two_handed": true}, [&"boss_drop", &"special_shockwave"])
	w(&"tidebreaker", "Tidebreaker", &"broadsword", 5, 58.0, 1.1,
		Blocks.ELEM_ICE, Items.RARITY_LEGENDARY, Color(0.4, 0.7, 0.95), &"sword",
		"Cut from the spine of something that lived under the ice shelf.\n"
		+ "Every swing drags the cold along with it.",
		{"knockback": 9.0, "two_handed": true}, [&"boss_drop", &"special_spin_slash"])
	w(&"hivemind_scepter", "Hivemind Scepter", &"staff", 6, 44.0, 0.85,
		Blocks.ELEM_POISON, Items.RARITY_LEGENDARY, Color(0.55, 0.9, 0.35), &"staff",
		"Still twitching. The bolts it fires know where everything is.",
		{"projectile": &"star_bolt", "energy_cost": 15.0, "two_handed": true},
		[&"boss_drop"])
	w(&"null_sequence", "Null Sequence", &"gun", 7, 52.0, 1.8,
		Blocks.ELEM_COSMIC, Items.RARITY_ESSENTIAL, Color(0.9, 0.85, 1.0), &"gun",
		"Recovered from the core of the last gate. It fires a number, and the\n"
		+ "number is subtracted from whatever it meets — through stone, through\n"
		+ "the cross-section, through everything on the line.",
		{"projectile": &"phase_lance", "energy_cost": 12.0, "two_handed": true},
		[&"boss_drop", &"cutaway_pierce", &"special_phase_pierce", &"perspective"])
	w(&"heart_of_the_forge", "Heart of the Forge", &"hammer", 7, 118.0, 0.48,
		Blocks.ELEM_FIRE, Items.RARITY_ESSENTIAL, Color(1.0, 0.72, 0.2), &"hammer",
		"The last hammer. It remembers being every other hammer.",
		{"knockback": 26.0, "two_handed": true}, [&"boss_drop", &"special_nova"])
