## Every hand-authored weapon in the game.
##
## [b]Naming contract[/b] — the crafting agent's recipes key off these ids, so
## they do not change:
## [br]• The per-tier ladder is `<metal>_<archetype>`, using exactly the metal
##   ladder `content/items/10_materials.gd` established:
##   `copper iron silver gold titanium durasteel aegisalt ferozium violium
##   solarium`. Archetypes on the ladder: `sword bow gun spear hammer`.
##   So: `copper_sword`, `iron_bow`, `durasteel_hammer`, `solarium_spear`, ...
##   Every one of them is crafted from `<metal>_bar`.
## [br]• Procedurally generated weapons are written onto the base items
##   `gen_<archetype>` (`gen_broadsword`, `gen_gun`, `gen_staff`, ...). Never
##   craft or sell these directly; [CbtWeaponGen] fills in their name and stats.
## [br]• Uniques and boss drops have bespoke ids and carry `&"unique"` or
##   `&"boss_drop"`.
##
## [b]Tags[/b] every weapon carries `weapon`, its archetype tag (`broadsword`
## `shortsword` `spear` `hammer` `dagger` `whip` `shield` `bow` `gun` `shotgun`
## `rocket` `flamethrower` `staff` `boomerang` `grenade` `beamdrill` — this is
## what [CbtWeapon] reads to pick its behaviour), a `tier_<n>` tag, and
## optionally:
## [br]• `special_<id>` — grants that special on the secondary button, e.g.
##   `special_phase_pierce`, `special_spin_slash`, `special_depth_bomb`.
## [br]• `planar_all` / `planar_behind` / `planar_deep` — rewrites the weapon's
##   **depth rule**. This is the perspective mechanic in item form:
##   [br]  `planar_all` hits every layer at once;
##   [br]  `planar_behind` hits *only* the layer behind you and nothing on your
##         own plane;
##   [br]  `planar_deep` reaches a slab of layers back, fading with distance.
extends RefCounted

## The metal ladder, matching `10_materials.gd` exactly.
## key, display, colour, mining/tool tier, rank (1..10), rarity
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

## The five ladder archetypes.
## suffix, display noun, archetype tag, damage mult, speed, icon, extra flags
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


static func register_all(reg) -> void:
	_ladder(reg)
	_generator_bases(reg)
	_uniques(reg)
	_perspective_weapons(reg)
	_boss_drops(reg)


# ============================================================ shared builder
## Register one weapon. `extra` is passed straight to `ItemType.flags`, so it
## may set `projectile`, `energy_cost`, `knockback`, `two_handed`, `tool_tier`.
static func _w(reg, id: StringName, display: String, arch: StringName, tier: int,
		dmg: float, speed: float, elem: String, rarity: int, color: Color,
		icon: StringName, desc: String, extra: Dictionary = {},
		tags: Array = []) -> ItemType:
	if reg.has(id):
		return reg.get_type(id)
	var it: ItemType = reg.define(id, display)
	it.of_kind(ItemType.Kind.WEAPON)
	it.as_weapon(snappedf(dmg, 0.1), snappedf(speed, 0.01), elem)
	it.look(color, icon)
	it.describe(desc)
	it.worth(int((18 + 20 * tier) * (1 + rarity)), rarity)
	it.in_category(&"weapons")
	it.tag(&"weapon")
	it.tag(arch)
	it.tag(StringName("tier_%d" % tier))
	it.tool_tier = tier
	for t: Variant in tags:
		it.tag(StringName(t))
	if not extra.is_empty():
		it.flags(extra)
	return it


# ============================================================== the tier ladder
static func _ladder(reg) -> void:
	for m: Array in METALS:
		var key: StringName = m[0]
		var mdisplay: String = m[1]
		var color: Color = m[2]
		var tier: int = m[3]
		var rank: int = m[4]
		var rarity: int = m[5]
		# Base damage curve: gentle early, steep once you leave the home planet.
		var base := 6.0 + 4.4 * float(rank) + 0.36 * float(rank * rank)
		for row: Array in LADDER:
			var suffix: StringName = row[0]
			var noun: String = row[1]
			var arch: StringName = row[2]
			var dmg_mult: float = row[3]
			var speed: float = row[4]
			var icon: StringName = row[5]
			var desc: String = row[6]
			var extra := {"knockback": 4.0 + 0.3 * float(rank)}
			match arch:
				&"bow":
					extra["projectile"] = _ladder_arrow(rank)
					extra["two_handed"] = true
				&"gun":
					extra["projectile"] = _ladder_bullet(rank)
					extra["energy_cost"] = 2.0 + 0.35 * float(rank)
				&"hammer":
					extra["knockback"] = 9.0 + 0.8 * float(rank)
					extra["two_handed"] = true
				&"spear":
					extra["two_handed"] = true
			# The top of the ladder starts carrying an element of its own.
			var elem := Const.ELEM_PHYSICAL
			if key == &"ferozium":
				elem = Const.ELEM_POISON
			elif key == &"violium":
				elem = Const.ELEM_ELECTRIC
			elif key == &"solarium":
				elem = Const.ELEM_FIRE
			_w(reg, StringName("%s_%s" % [key, suffix]),
				"%s %s" % [mdisplay, noun], arch, tier,
				base * dmg_mult, speed, elem, rarity, color, icon,
				"%s\nForged from %s bars." % [desc, mdisplay.to_lower()], extra,
				[&"craftable", &"ladder"])


static func _ladder_arrow(rank: int) -> StringName:
	if rank >= 9:
		return &"bolt"
	return &"arrow"


static func _ladder_bullet(rank: int) -> StringName:
	if rank >= 9:
		return &"plasma"
	if rank >= 6:
		return &"bullet"
	return &"bullet"


# ==================================================== procedural base items
## One inert base item per archetype. [CbtWeaponGen] stamps its rolls into an
## `ItemStack`'s `data`, which `ItemStack.stat()` prefers over these defaults —
## so these numbers only ever show if something generated a weapon wrong.
static func _generator_bases(reg) -> void:
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
		[&"beamdrill", "Beam Drill", 8.0, 2.2, &"drill", 1.6, &"drill_beam"],
	]
	for r: Array in rows:
		var arch: StringName = r[0]
		var extra := {}
		if float(r[5]) > 0.0:
			extra["energy_cost"] = float(r[5])
		if StringName(r[6]) != &"":
			extra["projectile"] = StringName(r[6])
		_w(reg, StringName("gen_" + String(arch)), String(r[1]), arch, 2,
			float(r[2]), float(r[3]), Const.ELEM_PHYSICAL, Const.RARITY_COMMON,
			Color(0.7, 0.7, 0.75), StringName(r[4]),
			"An unremarkable %s, waiting for a story." % String(r[1]).to_lower(),
			extra, [&"generated", &"no_sell"])


# ==================================================================== uniques
static func _uniques(reg) -> void:
	# ---- melee
	_w(reg, &"starcleaver", "Starcleaver", &"broadsword", 5, 46.0, 0.95,
		Const.ELEM_COSMIC, Const.RARITY_LEGENDARY, Color(0.72, 0.62, 1.0), &"sword",
		"A blade of compressed starlight. It sings on the downswing and\n"
		+ "the note does not stop when the swing does.",
		{"knockback": 8.0, "two_handed": true},
		[&"unique", &"special_spin_slash"])
	_w(reg, &"widowmaker", "Widowmaker", &"dagger", 4, 13.0, 2.6,
		Const.ELEM_POISON, Const.RARITY_RARE, Color(0.4, 0.75, 0.35), &"dagger",
		"Thin, black, and coated in something that never quite dries.\n"
		+ "Devastating when the target has not noticed you yet.",
		{"knockback": 1.0}, [&"unique", &"special_dash_strike"])
	_w(reg, &"mantis_claw", "Mantis Claw", &"dagger", 3, 11.0, 3.0,
		Const.ELEM_PHYSICAL, Const.RARITY_RARE, Color(0.55, 0.85, 0.45), &"dagger",
		"Harvested from something that was very fast and is now very dead.\n"
		+ "Four strikes before a normal blade finishes one.",
		{"knockback": 0.8}, [&"unique"])
	_w(reg, &"serpent_lash", "Serpent Lash", &"whip", 4, 17.0, 1.15,
		Const.ELEM_POISON, Const.RARITY_RARE, Color(0.45, 0.8, 0.3), &"whip",
		"Six metres of braided sinew that has not entirely accepted death.\n"
		+ "Cracks repeatedly across its whole reach.",
		{"knockback": 9.0}, [&"unique"])
	_w(reg, &"thundercoil", "Thundercoil", &"whip", 5, 21.0, 1.1,
		Const.ELEM_ELECTRIC, Const.RARITY_RARE, Color(0.8, 0.85, 1.0), &"whip",
		"Superconducting cable on a dead man's switch. Every crack earths\n"
		+ "itself through whatever it touches.",
		{"knockback": 11.0}, [&"unique", &"special_chain_bolt"])
	_w(reg, &"bulwark_of_ash", "Bulwark of Ash", &"shield", 4, 9.0, 1.1,
		Const.ELEM_FIRE, Const.RARITY_RARE, Color(0.6, 0.3, 0.22), &"shield",
		"Volcanic glass laminated over steel. Blocks most of a blow and\n"
		+ "returns the rest as heat.",
		{"knockback": 12.0}, [&"unique"])
	_w(reg, &"mirror_aegis", "Mirror Aegis", &"shield", 6, 12.0, 1.4,
		Const.ELEM_COSMIC, Const.RARITY_LEGENDARY, Color(0.85, 0.9, 1.0), &"shield",
		"Perfectly reflective, perfectly cold. A well-timed parry sends the\n"
		+ "whole attack back where it came from.",
		{"knockback": 16.0}, [&"unique", &"special_nova"])
	_w(reg, &"glacier_spike", "Glacier Spike", &"spear", 5, 41.0, 0.8,
		Const.ELEM_ICE, Const.RARITY_RARE, Color(0.6, 0.88, 1.0), &"spear",
		"A single crystal grown over four hundred years in a cave that no\n"
		+ "longer exists. It does not melt.",
		{"knockback": 7.0, "two_handed": true}, [&"unique"])
	_w(reg, &"warden_pike", "Warden's Pike", &"spear", 6, 52.0, 0.78,
		Const.ELEM_PHYSICAL, Const.RARITY_LEGENDARY, Color(0.8, 0.78, 0.62), &"spear",
		"Standard issue for a garrison that held its gate for nine years.\n"
		+ "Reach enough to keep anything at arm's length.",
		{"knockback": 9.0, "two_handed": true}, [&"unique", &"special_shockwave"])

	# ---- ranged
	_w(reg, &"hunters_recurve", "Hunter's Recurve", &"bow", 3, 24.0, 1.15,
		Const.ELEM_PHYSICAL, Const.RARITY_UNCOMMON, Color(0.68, 0.5, 0.3), &"bow",
		"Light, quick, and honest. Draws faster than anything else that\n"
		+ "hits this hard.",
		{"projectile": &"arrow", "two_handed": true}, [&"unique"])
	_w(reg, &"void_bow", "Void Recurve", &"bow", 6, 44.0, 0.9,
		Const.ELEM_COSMIC, Const.RARITY_LEGENDARY, Color(0.6, 0.4, 0.85), &"bow",
		"Draws on nothing and fires it anyway. The arrow arrives before\n"
		+ "the sound of the string.",
		{"projectile": &"void_orb", "two_handed": true},
		[&"unique", &"special_volley"])
	_w(reg, &"plasma_repeater", "Plasma Repeater", &"gun", 5, 19.0, 2.1,
		Const.ELEM_ELECTRIC, Const.RARITY_RARE, Color(0.5, 0.9, 1.0), &"gun",
		"Vents heat through the grip, which you will notice. Fires until\n"
		+ "your energy runs out, which you will also notice.",
		{"projectile": &"plasma", "energy_cost": 3.5}, [&"unique"])
	_w(reg, &"swarm_needler", "Swarm Needler", &"gun", 4, 12.0, 2.6,
		Const.ELEM_POISON, Const.RARITY_RARE, Color(0.6, 0.9, 0.4), &"gun",
		"Fires organic needles that keep working long after they land.",
		{"projectile": &"needle", "energy_cost": 2.0}, [&"unique"])
	_w(reg, &"scattercannon", "Scattercannon", &"shotgun", 4, 44.0, 0.75,
		Const.ELEM_PHYSICAL, Const.RARITY_RARE, Color(0.6, 0.55, 0.5), &"gun",
		"Seven pellets, one trigger, no subtlety whatsoever. Point at the\n"
		+ "thing that is already touching you.",
		{"projectile": &"pellet", "energy_cost": 6.0, "two_handed": true},
		[&"unique"])
	_w(reg, &"siege_bazooka", "Siege Bazooka", &"rocket", 6, 62.0, 0.5,
		Const.ELEM_FIRE, Const.RARITY_LEGENDARY, Color(0.55, 0.5, 0.45), &"gun",
		"Rewrites the terrain and everything standing on it. Check what is\n"
		+ "behind you before you check what is in front.",
		{"projectile": &"rocket", "energy_cost": 22.0, "two_handed": true},
		[&"unique", &"boss_drop"])
	_w(reg, &"dragons_breath", "Dragon's Breath", &"flamethrower", 5, 26.0, 2.0,
		Const.ELEM_FIRE, Const.RARITY_RARE, Color(1.0, 0.55, 0.2), &"gun",
		"A cone of burning fuel, continuously. Sets the ground alight and\n"
		+ "keeps it that way.",
		{"projectile": &"flame_gout", "energy_cost": 1.4, "two_handed": true},
		[&"unique"])
	_w(reg, &"staff_of_embers", "Staff of Embers", &"staff", 3, 22.0, 1.0,
		Const.ELEM_FIRE, Const.RARITY_UNCOMMON, Color(1.0, 0.6, 0.25), &"staff",
		"A branch that burned once and decided to keep going.",
		{"projectile": &"fireball", "energy_cost": 10.0, "two_handed": true},
		[&"unique"])
	_w(reg, &"frostwarden_staff", "Frostwarden Staff", &"staff", 5, 30.0, 0.95,
		Const.ELEM_ICE, Const.RARITY_RARE, Color(0.6, 0.9, 1.0), &"staff",
		"Fires shards that shatter into more shards. Freezes what it does\n"
		+ "not kill.",
		{"projectile": &"ice_shard", "energy_cost": 12.0, "two_handed": true},
		[&"unique"])
	_w(reg, &"stormcaller", "Stormcaller", &"staff", 6, 38.0, 0.9,
		Const.ELEM_ELECTRIC, Const.RARITY_LEGENDARY, Color(0.85, 0.9, 1.0), &"staff",
		"The bolt jumps from body to body until it runs out of bodies.",
		{"projectile": &"lightning_arc", "energy_cost": 16.0, "two_handed": true},
		[&"unique", &"special_chain_bolt"])
	_w(reg, &"returning_chakram", "Returning Chakram", &"boomerang", 4, 24.0, 1.2,
		Const.ELEM_PHYSICAL, Const.RARITY_RARE, Color(0.85, 0.72, 0.35), &"disc",
		"Hits on the way out, hits on the way back, and refuses to be\n"
		+ "thrown again until it is home.",
		{"projectile": &"boomerang"}, [&"unique"])
	_w(reg, &"fragmentation_bombard", "Fragmentation Bombard", &"grenade", 5, 40.0, 0.85,
		Const.ELEM_PHYSICAL, Const.RARITY_RARE, Color(0.4, 0.46, 0.34), &"gun",
		"Lobs a grenade on a two-second fuse that bursts into six more.\n"
		+ "Mind the arc.",
		{"projectile": &"grenade", "energy_cost": 7.0, "two_handed": true},
		[&"unique"])
	_w(reg, &"prospectors_beam", "Prospector's Beam", &"beamdrill", 4, 14.0, 2.2,
		Const.ELEM_ELECTRIC, Const.RARITY_UNCOMMON, Color(1.0, 0.78, 0.35), &"drill",
		"A mining beam that has never been told it is not a weapon.\n"
		+ "Chews through stone and through whatever is standing in it.",
		{"projectile": &"drill_beam", "energy_cost": 1.8, "two_handed": true},
		[&"unique", &"tool_like"])


# ====================================================== perspective weapons
## The three weapons built entirely around the depth axis, plus one more that
## fires *into* the screen. These are the reason the layer rules exist.
static func _perspective_weapons(reg) -> void:
	# 1. Hits EVERY layer at once. The answer to a crowd stacked in depth.
	_w(reg, &"phase_lance", "Phase Lance", &"gun", 6, 30.0, 0.85,
		Const.ELEM_COSMIC, Const.RARITY_LEGENDARY, Color(0.72, 0.5, 1.0), &"gun",
		"Fires a lance of phase-shifted light that exists in every depth\n"
		+ "layer simultaneously. It does not care which plane you are standing\n"
		+ "in, and neither does anything it passes through.\n"
		+ "[Ignores depth entirely.]",
		{"projectile": &"phase_lance", "energy_cost": 14.0, "two_handed": true},
		[&"unique", &"planar_all", &"special_phase_pierce", &"perspective"])

	# 2. Hits ONLY the layer behind you. Useless head-on; brutal on an ambush.
	_w(reg, &"revenant_edge", "Revenant Edge", &"broadsword", 6, 62.0, 1.05,
		Const.ELEM_COSMIC, Const.RARITY_LEGENDARY, Color(0.5, 0.42, 0.72), &"sword",
		"The blade is half a step out of phase with the world. It passes\n"
		+ "clean through anything on your own plane and lands with terrible\n"
		+ "weight on whatever is standing one layer behind it.\n"
		+ "[Strikes only the layer behind you. Hits nothing on your plane.]",
		{"knockback": 7.0}, [&"unique", &"planar_behind", &"perspective"])

	# 3. Detonates through a slab of layers behind the play plane.
	_w(reg, &"depth_charge_launcher", "Depth Charge Launcher", &"grenade", 6, 44.0, 0.7,
		Const.ELEM_ICE, Const.RARITY_LEGENDARY, Color(0.4, 0.7, 0.85), &"gun",
		"Lobs a charge that sinks into the screen before it goes off, and\n"
		+ "the blast propagates backwards through four depth layers at once.\n"
		+ "Nothing you can see is far enough away.\n"
		+ "[Damages a range of layers behind the blast.]",
		{"projectile": &"depth_charge", "energy_cost": 16.0, "two_handed": true},
		[&"unique", &"planar_deep", &"special_depth_bomb", &"perspective"])

	# 4. Bonus: fires straight into the screen, walking layer by layer.
	_w(reg, &"oblique_repeater", "Oblique Repeater", &"gun", 6, 34.0, 1.1,
		Const.ELEM_ELECTRIC, Const.RARITY_RARE, Color(0.45, 1.0, 0.8), &"gun",
		"The barrel points away from the camera. On screen the shot barely\n"
		+ "moves — it recedes, one layer at a time, killing everything stacked\n"
		+ "behind your target.\n"
		+ "[Travels along the depth axis.]",
		{"projectile": &"oblique_shot", "energy_cost": 8.0},
		[&"unique", &"planar_deep", &"perspective"])

	# 5. Bonus: a bow whose arrows land one layer back.
	_w(reg, &"echo_bow", "Echo Recurve", &"bow", 5, 33.0, 1.0,
		Const.ELEM_COSMIC, Const.RARITY_RARE, Color(0.58, 0.48, 0.9), &"bow",
		"Arrows leave the string in your plane and arrive in the next one.\n"
		+ "Absolutely no use against anything you are actually facing.\n"
		+ "[Hits only the layer behind.]",
		{"projectile": &"echo_dart", "two_handed": true},
		[&"unique", &"planar_behind", &"perspective"])


# ================================================================ boss drops
static func _boss_drops(reg) -> void:
	_w(reg, &"magma_maul", "Magma Maul", &"hammer", 5, 96.0, 0.5,
		Const.ELEM_FIRE, Const.RARITY_LEGENDARY, Color(0.85, 0.35, 0.15), &"hammer",
		"Taken from the thing at the bottom of the shaft. Each landing\n"
		+ "cracks the stone and throws a ring of fire out of the crater.",
		{"knockback": 22.0, "two_handed": true},
		[&"boss_drop", &"special_shockwave"])
	_w(reg, &"tidebreaker", "Tidebreaker", &"broadsword", 5, 58.0, 1.1,
		Const.ELEM_ICE, Const.RARITY_LEGENDARY, Color(0.4, 0.7, 0.95), &"sword",
		"Cut from the spine of something that lived under the ice shelf.\n"
		+ "Every swing drags the cold along with it.",
		{"knockback": 9.0, "two_handed": true},
		[&"boss_drop", &"special_spin_slash"])
	_w(reg, &"hivemind_scepter", "Hivemind Scepter", &"staff", 6, 44.0, 0.85,
		Const.ELEM_POISON, Const.RARITY_LEGENDARY, Color(0.55, 0.9, 0.35), &"staff",
		"Still twitching. The bolts it fires know where everything is.",
		{"projectile": &"star_bolt", "energy_cost": 15.0, "two_handed": true},
		[&"boss_drop"])
	_w(reg, &"the_long_argument", "The Long Argument", &"spear", 6, 70.0, 0.72,
		Const.ELEM_PHYSICAL, Const.RARITY_LEGENDARY, Color(0.9, 0.88, 0.8), &"spear",
		"Six metres of tempered reasoning. Wins on reach.",
		{"knockback": 12.0, "two_handed": true},
		[&"boss_drop", &"special_dash_strike"])
	_w(reg, &"null_sequence", "Null Sequence", &"gun", 7, 52.0, 1.8,
		Const.ELEM_COSMIC, Const.RARITY_ESSENTIAL, Color(0.9, 0.85, 1.0), &"gun",
		"Recovered from the core of the last gate. It fires a number, and\n"
		+ "the number is subtracted from whatever it meets — in every layer,\n"
		+ "on every plane, all at once.",
		{"projectile": &"phase_lance", "energy_cost": 12.0, "two_handed": true},
		[&"boss_drop", &"planar_all", &"special_phase_pierce", &"perspective"])
	_w(reg, &"heart_of_the_forge", "Heart of the Forge", &"hammer", 7, 118.0, 0.48,
		Const.ELEM_FIRE, Const.RARITY_ESSENTIAL, Color(1.0, 0.72, 0.2), &"hammer",
		"The last hammer. It remembers being every other hammer.",
		{"knockback": 26.0, "two_handed": true},
		[&"boss_drop", &"special_nova"])
