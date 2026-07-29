## Procedurally generated weapons — the Starbound signature.
##
## Every chest, every boss, every merchant can hand you a weapon that has never
## existed before: its own name, archetype, element, stat spread, special
## ability and rarity. Everything is written into [member ItemStack.data], so
## `ItemStack.stat()` transparently prefers the roll over the base item's
## defaults and the rest of the combat code needs to know nothing about it.
##
## Generation is **deterministic from a seed**. The same seed and tier always
## produce byte-identical loot, which is what lets the world generator place a
## specific weapon in a specific chest without storing it.
##
## ```gdscript
## var w := CbtWeaponGen.generate(chest_seed, planet_tier)
## Game.spawn_item_drop(pos, w.id, 1, w.data)
## ```
##
## ## What lands in `data`
##
## `name description archetype element tier rarity damage attack_speed knockback
## crit_chance crit_mult armor_pierce energy_cost reach_mult projectile special
## special_cost status_on_hit lifesteal durability max_durability value color
## seed layer_rule layer_min layer_max layer_falloff`
##
## ## Planar affixes
##
## Roughly one weapon in twelve rolls a **planar affix**, which rewrites the
## weapon's depth rule and is by far the most interesting thing that can happen
## to a drop:
##
## * *Phasing* — hits every layer at once, for less damage per hit.
## * *Echoing* — hits **only** the layer behind you, for a great deal more.
## * *Deepstriking* — reaches several layers back, fading with distance.
class_name CbtWeaponGen
extends RefCounted

## Base item ids the generator writes onto. Defined in
## `content/items/30_weapons.gd` as `gen_<archetype>`.
const BASE_PREFIX := "gen_"

const ARCHETYPE_WEIGHTS := {
	CbtWeapon.BROADSWORD: 12.0,
	CbtWeapon.SHORTSWORD: 12.0,
	CbtWeapon.SPEAR: 8.0,
	CbtWeapon.HAMMER: 7.0,
	CbtWeapon.DAGGER: 8.0,
	CbtWeapon.WHIP: 4.0,
	CbtWeapon.SHIELD: 5.0,
	CbtWeapon.BOW: 8.0,
	CbtWeapon.GUN: 12.0,
	CbtWeapon.SHOTGUN: 7.0,
	CbtWeapon.ROCKET: 3.0,
	CbtWeapon.FLAMETHROWER: 3.0,
	CbtWeapon.STAFF: 7.0,
	CbtWeapon.BOOMERANG: 3.0,
	CbtWeapon.GRENADE: 3.0,
	CbtWeapon.BEAMDRILL: 2.0,
}

## Nouns by archetype. The generator picks one and dresses it.
const NOUNS := {
	CbtWeapon.BROADSWORD: ["Blade", "Claymore", "Greatsword", "Cleaver", "Sabre",
		"Falchion", "Broadsword", "Warblade", "Edge", "Zweihander"],
	CbtWeapon.SHORTSWORD: ["Shortsword", "Gladius", "Cutlass", "Rapier", "Sword",
		"Sabre", "Tine", "Sting", "Fang"],
	CbtWeapon.SPEAR: ["Spear", "Lance", "Pike", "Halberd", "Glaive", "Trident",
		"Impaler", "Skewer", "Partisan"],
	CbtWeapon.HAMMER: ["Hammer", "Maul", "Sledge", "Warhammer", "Mace", "Breaker",
		"Crusher", "Anvil", "Basher"],
	CbtWeapon.DAGGER: ["Dagger", "Knife", "Shiv", "Dirk", "Stiletto", "Kris",
		"Fang", "Needle", "Thorn"],
	CbtWeapon.WHIP: ["Whip", "Lash", "Scourge", "Flail", "Coil", "Tendril", "Flogger"],
	CbtWeapon.SHIELD: ["Shield", "Bulwark", "Aegis", "Buckler", "Guard", "Wall",
		"Barrier", "Rampart"],
	CbtWeapon.BOW: ["Bow", "Longbow", "Recurve", "Shortbow", "Arc", "Warbow", "Hunter"],
	CbtWeapon.GUN: ["Pistol", "Rifle", "Repeater", "Carbine", "Blaster", "Sidearm",
		"Magnum", "Needler", "SMG"],
	CbtWeapon.SHOTGUN: ["Shotgun", "Scattergun", "Boomstick", "Blunderbuss",
		"Spreader", "Flakgun"],
	CbtWeapon.ROCKET: ["Launcher", "Bazooka", "Rocketeer", "Barrage", "Siegepiece",
		"Missile Rack"],
	CbtWeapon.FLAMETHROWER: ["Flamethrower", "Torch", "Immolator", "Burner",
		"Pyre", "Scorcher"],
	CbtWeapon.STAFF: ["Staff", "Wand", "Scepter", "Rod", "Focus", "Cane", "Branch"],
	CbtWeapon.BOOMERANG: ["Boomerang", "Chakram", "Discus", "Returner", "Crescent"],
	CbtWeapon.GRENADE: ["Bombard", "Mortar", "Grenadier", "Lobber", "Tosser"],
	CbtWeapon.BEAMDRILL: ["Drill", "Borer", "Lance Drill", "Excavator", "Auger"],
}

## Adjectives, keyed by element. `""` is the elementless pool.
const ADJECTIVES := {
	"": ["Rusted", "Sturdy", "Keen", "Balanced", "Heavy", "Swift", "Grim",
		"Honed", "Battered", "Trusty", "Vicious", "Brutal", "Refined",
		"Serrated", "Weighted", "Precise", "Restless", "Wicked"],
	Const.ELEM_FIRE: ["Blazing", "Smouldering", "Ashen", "Molten", "Scorching",
		"Cinderous", "Solar", "Kindled", "Emberlit", "Charring"],
	Const.ELEM_ICE: ["Frigid", "Glacial", "Rimed", "Frostbound", "Hoarfrost",
		"Chilling", "Permafrost", "Sleetborn", "Wintering"],
	Const.ELEM_ELECTRIC: ["Arcing", "Galvanic", "Stormlit", "Voltaic", "Crackling",
		"Ionised", "Tesla-Wound", "Static", "Thunderous"],
	Const.ELEM_POISON: ["Venomous", "Septic", "Blighted", "Fetid", "Corroding",
		"Acidic", "Miasmic", "Tainted", "Verdant"],
	Const.ELEM_COSMIC: ["Void-Touched", "Starlit", "Nullbound", "Eventide",
		"Singular", "Astral", "Nebular", "Quantum"],
}

## Suffix phrases. Higher rarities get grander ones.
const SUFFIXES := [
	["of the Drifter", "of the Ditch", "of Scrap", "of Habit", "of the Long Road"],
	["of the Prospector", "of Deep Rock", "of the Pale Moon", "of Second Wind",
		"of the Quiet Hour"],
	["of the Shattered Ring", "of Nine Winters", "of the Hollow Star",
		"of the Last Colony", "of Sundered Orbit"],
	["of the Unmade", "of the Devouring Dark", "of the First Light",
		"of the Terminal Sky", "of the Thousandth Layer"],
	["of the Origin", "of the Founder's Grave", "of Everything That Was"],
]

## Syllables for invented proper names — "Vorak", "Zhenithra", "Kesswold".
const SYL_HEAD := ["Vor", "Kes", "Zhen", "Bral", "Nyx", "Tor", "Ques", "Mal",
	"Ryn", "Drav", "Sol", "Ith", "Ael", "Grum", "Vash", "Ovi", "Ker", "Xan",
	"Pyr", "Lun", "Tesh", "Ord", "Vel", "Umb", "Hask"]
const SYL_MID = ["a", "i", "o", "en", "ar", "ul", "esh", "ith", "or", "ae",
	"un", "ys", "el", "ov", "ur"]
const SYL_TAIL := ["ok", "ra", "thra", "wold", "gan", "ix", "mar", "dus", "ven",
	"tir", "quel", "zim", "nar", "os", "eth", "kar", "ul", "ang"]

## Special abilities available to each archetype family.
const SPECIALS := {
	"melee": [&"spin_slash", &"dash_strike", &"shockwave", &"nova", &"phase_pierce"],
	"ranged": [&"volley", &"chain_bolt", &"depth_bomb", &"phase_pierce", &"nova"],
}

## Rarity thresholds by roll, and the multipliers each rarity grants.
const RARITY_DAMAGE := [1.0, 1.12, 1.3, 1.58, 1.95]
const RARITY_VALUE := [1.0, 1.8, 3.4, 7.0, 14.0]

const PLANAR_AFFIX_CHANCE := 0.085


# =================================================================== entry point
## Roll a complete weapon.
##
## `opts` may pin any roll: `archetype`, `element`, `rarity`, `rarity_bonus`
## (float, shifts the rarity roll), `allow_planar` (bool), `name`.
static func generate(p_seed: int, tier: int = 1, opts: Dictionary = {}) -> ItemStack:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	tier = clampi(tier, 1, 12)

	# ---- archetype
	var arch: StringName = StringName(opts.get("archetype", &""))
	if arch == &"" or not CbtWeapon.ARCHETYPES.has(arch):
		arch = _weighted_archetype(rng)
	var cfg: Dictionary = CbtWeapon.config_of(arch)

	# ---- rarity
	var rarity := int(opts.get("rarity", -1))
	if rarity < 0:
		rarity = _roll_rarity(rng, tier, float(opts.get("rarity_bonus", 0.0)))

	# ---- element
	var element := String(opts.get("element", ""))
	if element == "":
		element = _roll_element(rng, tier, rarity)

	# ---- stats
	var quality := rng.randf_range(0.86, 1.16) * RARITY_DAMAGE[rarity]
	var dmg_base := (5.0 + 4.6 * float(tier) + 0.42 * float(tier * tier)) * quality
	var speed := clampf(float(_archetype_speed(arch)) * rng.randf_range(0.82, 1.22), 0.3, 4.0)
	# Faster weapons hit softer; total DPS stays inside a sane band.
	dmg_base *= clampf(1.0 / sqrt(maxf(0.2, speed)), 0.55, 1.7)
	if bool(cfg.get("ranged", false)):
		dmg_base *= 0.9

	var data := {
		"archetype": arch,
		"element": element,
		"tier": tier,
		"rarity": rarity,
		"generated": true,
		"seed": p_seed,
		"damage": snappedf(dmg_base, 0.1),
		"attack_speed": snappedf(speed, 0.01),
		"knockback": snappedf(4.0 * float(cfg.get("knockback_mult", 1.0)) * rng.randf_range(0.8, 1.3), 0.1),
		"crit_chance": snappedf(clampf(0.04 + 0.012 * float(tier) + rng.randf_range(0.0, 0.09)
			+ 0.02 * float(rarity), 0.0, 0.6), 0.001),
		"crit_mult": snappedf(1.55 + 0.06 * float(rarity) + rng.randf_range(0.0, 0.45), 0.01),
		"armor_pierce": snappedf(clampf(rng.randf_range(-0.05, 0.28) + 0.03 * float(rarity), 0.0, 0.6), 0.01),
		"reach_mult": snappedf(rng.randf_range(0.9, 1.18), 0.01),
		"energy_cost": snappedf(float(cfg.get("energy", 0.0)) * rng.randf_range(0.75, 1.3)
			* (1.0 + 0.06 * float(tier)), 0.1),
	}

	# ---- ranged weapons need a projectile
	if bool(cfg.get("ranged", false)):
		data["projectile"] = _roll_projectile(rng, arch, element)

	# ---- status on hit
	var rolls := CbtStatusHooks.rolls_for_element(element, float(tier) * 0.35 + float(rarity) * 0.3)
	if not rolls.is_empty():
		data["status_on_hit"] = rolls

	# ---- lifesteal is a rare treat
	if rarity >= Const.RARITY_RARE and rng.randf() < 0.22:
		data["lifesteal"] = snappedf(rng.randf_range(0.03, 0.09), 0.01)

	# ---- special ability
	if rarity >= Const.RARITY_UNCOMMON or rng.randf() < 0.3:
		var family := "ranged" if bool(cfg.get("ranged", false)) else "melee"
		var pool: Array = SPECIALS[family]
		data["special"] = pool[rng.randi_range(0, pool.size() - 1)]
		data["special_cost"] = snappedf(10.0 + 3.0 * float(tier) * rng.randf_range(0.7, 1.3), 0.5)

	# ---- planar affix
	var affix_name := ""
	if bool(opts.get("allow_planar", true)) and rng.randf() < PLANAR_AFFIX_CHANCE + 0.02 * float(rarity):
		affix_name = _apply_planar_affix(rng, data)

	# ---- durability, value, colour
	var dur := 140 + tier * 130 + rarity * 90
	data["durability"] = dur
	data["max_durability"] = dur
	data["value"] = int((22.0 + 16.0 * float(tier)) * RARITY_VALUE[rarity] * rng.randf_range(0.85, 1.2))
	data["color"] = _roll_color(rng, element, rarity)

	# ---- name and flavour
	var name_str := String(opts.get("name", ""))
	if name_str == "":
		name_str = roll_name(rng, arch, element, rarity, affix_name)
	data["name"] = name_str
	data["description"] = _roll_description(rng, arch, element, rarity, affix_name, data)

	var base_id := base_item_for(arch)
	return ItemStack.new(base_id, 1, data)


## Generate several weapons from one seed, each independently reproducible.
static func generate_batch(p_seed: int, tier: int, count: int,
		opts: Dictionary = {}) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for i in count:
		out.append(generate(p_seed + i * 7919, tier, opts))
	return out


## The base item id a generated weapon of this archetype is written onto.
static func base_item_for(arch: StringName) -> StringName:
	var id := StringName(BASE_PREFIX + String(arch))
	if Items != null and Items.has(id):
		return id
	# Fall back to any registered weapon so a drop is never a dead id.
	if Items != null and Items.has(&"gen_broadsword"):
		return &"gen_broadsword"
	return &"copper_sword"


# ======================================================================= naming
## Roll a weapon name. Five sentence shapes, weighted by rarity so common junk
## gets "Rusted Cleaver" and legendaries get "Zhenithra, of the Unmade".
static func roll_name(rng: RandomNumberGenerator, arch: StringName, element: String,
		rarity: int, affix: String = "") -> String:
	var nouns: Array = NOUNS.get(arch, ["Weapon"])
	var noun: String = nouns[rng.randi_range(0, nouns.size() - 1)]
	var adjectives: Array = ADJECTIVES.get(element, ADJECTIVES[""])
	if element != "" and rng.randf() < 0.25:
		adjectives = ADJECTIVES[""]
	var adj: String = adjectives[rng.randi_range(0, adjectives.size() - 1)]
	var proper := _proper_name(rng)
	var suffix_pool: Array = SUFFIXES[clampi(rarity, 0, SUFFIXES.size() - 1)]
	var suffix: String = suffix_pool[rng.randi_range(0, suffix_pool.size() - 1)]

	var shape := rng.randi_range(0, 99)
	var base := ""
	if rarity >= Const.RARITY_LEGENDARY:
		if shape < 40:
			base = "%s, %s" % [proper, suffix]
		elif shape < 70:
			base = "%s %s %s" % [adj, noun, suffix]
		else:
			base = "%s's %s" % [proper, noun]
	elif rarity >= Const.RARITY_RARE:
		if shape < 30:
			base = "%s %s" % [adj, noun]
		elif shape < 55:
			base = "%s %s" % [proper, noun]
		elif shape < 80:
			base = "%s %s" % [noun, suffix]
		else:
			base = "%s's %s" % [proper, noun]
	else:
		if shape < 55:
			base = "%s %s" % [adj, noun]
		elif shape < 78:
			base = "%s %s" % [proper, noun]
		elif shape < 90:
			base = "%s %s" % [noun, _mark(rng)]
		else:
			base = "%s %s" % [noun, suffix]

	if affix != "":
		base = "%s %s" % [affix, base]
	return base


static func _proper_name(rng: RandomNumberGenerator) -> String:
	var s: String = SYL_HEAD[rng.randi_range(0, SYL_HEAD.size() - 1)]
	if rng.randf() < 0.55:
		s += SYL_MID[rng.randi_range(0, SYL_MID.size() - 1)]
	s += SYL_TAIL[rng.randi_range(0, SYL_TAIL.size() - 1)]
	return s


static func _mark(rng: RandomNumberGenerator) -> String:
	const ROMAN := ["II", "III", "IV", "V", "VII", "IX", "X", "XII"]
	if rng.randf() < 0.5:
		return "Mk %s" % ROMAN[rng.randi_range(0, ROMAN.size() - 1)]
	return "Model %d%s" % [rng.randi_range(2, 89),
		["-A", "-B", "-S", "-X", ""][rng.randi_range(0, 4)]]


static func _roll_description(rng: RandomNumberGenerator, arch: StringName,
		element: String, rarity: int, affix: String, data: Dictionary) -> String:
	const OPENERS := [
		"Salvaged from something that stopped needing it.",
		"Somebody carved a tally into the grip. They ran out of room.",
		"Standard issue, for a standard that no longer exists.",
		"Balanced beautifully. Someone cared about this once.",
		"It hums when you are not looking at it.",
		"Warranty void if used in atmosphere.",
		"The maker's mark has been filed off, badly.",
		"Cold to the touch, whatever the weather.",
		"Field-tested. The field did not survive.",
	]
	var lines: Array[String] = []
	lines.append(OPENERS[rng.randi_range(0, OPENERS.size() - 1)])
	if element != Const.ELEM_PHYSICAL and element != "":
		lines.append("Deals %s damage." % element)
	if affix != "":
		match affix:
			"Phasing":
				lines.append("Strikes every depth layer at once — nothing hides behind you.")
			"Echoing":
				lines.append("Passes through your own plane. Only bites the layer behind.")
			"Deepstriking":
				lines.append("Reaches several layers back, weakening with distance.")
	if data.has("special"):
		lines.append("Special: %s." % String(data["special"]).capitalize())
	if data.has("lifesteal"):
		lines.append("Returns %d%% of damage as health." % int(float(data["lifesteal"]) * 100.0))
	lines.append("Tier %d %s." % [int(data.get("tier", 1)),
		Const.RARITY_NAMES[clampi(rarity, 0, 4)].to_lower()])
	return "\n".join(lines)


# ======================================================================= rolls
static func _weighted_archetype(rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for k: StringName in ARCHETYPE_WEIGHTS:
		total += float(ARCHETYPE_WEIGHTS[k])
	var pick := rng.randf() * total
	for k: StringName in ARCHETYPE_WEIGHTS:
		pick -= float(ARCHETYPE_WEIGHTS[k])
		if pick <= 0.0:
			return k
	return CbtWeapon.BROADSWORD


static func _roll_rarity(rng: RandomNumberGenerator, tier: int, bonus: float) -> int:
	var r := rng.randf() + bonus + float(tier) * 0.018
	if r > 0.995:
		return Const.RARITY_ESSENTIAL
	if r > 0.955:
		return Const.RARITY_LEGENDARY
	if r > 0.85:
		return Const.RARITY_RARE
	if r > 0.58:
		return Const.RARITY_UNCOMMON
	return Const.RARITY_COMMON


static func _roll_element(rng: RandomNumberGenerator, tier: int, rarity: int) -> String:
	var chance := 0.2 + 0.03 * float(tier) + 0.08 * float(rarity)
	if rng.randf() > chance:
		return Const.ELEM_PHYSICAL
	var pool := [Const.ELEM_FIRE, Const.ELEM_ICE, Const.ELEM_ELECTRIC, Const.ELEM_POISON]
	if tier >= 6 and rng.randf() < 0.3:
		pool.append(Const.ELEM_COSMIC)
	return String(pool[rng.randi_range(0, pool.size() - 1)])


static func _archetype_speed(arch: StringName) -> float:
	match arch:
		CbtWeapon.DAGGER: return 2.3
		CbtWeapon.SHORTSWORD: return 1.7
		CbtWeapon.WHIP: return 1.1
		CbtWeapon.SPEAR: return 0.95
		CbtWeapon.BROADSWORD: return 1.0
		CbtWeapon.HAMMER: return 0.62
		CbtWeapon.SHIELD: return 1.2
		CbtWeapon.GUN: return 1.6
		CbtWeapon.SHOTGUN: return 0.8
		CbtWeapon.BOW: return 1.0
		CbtWeapon.ROCKET: return 0.55
		CbtWeapon.FLAMETHROWER: return 2.0
		CbtWeapon.STAFF: return 1.0
		CbtWeapon.BOOMERANG: return 1.1
		CbtWeapon.GRENADE: return 0.9
		CbtWeapon.BEAMDRILL: return 2.2
	return 1.0


static func _roll_projectile(rng: RandomNumberGenerator, arch: StringName,
		element: String) -> StringName:
	var kind := arch
	match arch:
		CbtWeapon.BOW: kind = &"bow"
		CbtWeapon.STAFF: kind = &"staff"
		CbtWeapon.SHOTGUN: kind = &"shotgun"
		CbtWeapon.ROCKET: kind = &"rocket"
		CbtWeapon.FLAMETHROWER: kind = &"flamethrower"
		_: kind = &"gun"
	var base := CbtProjectileTypes.for_element(element, kind)
	# A small chance of something exotic instead of the obvious pick.
	if rng.randf() < 0.1:
		var exotic := CbtProjectileTypes.with_tag(&"energy")
		if not exotic.is_empty():
			return StringName(exotic[rng.randi_range(0, exotic.size() - 1)])
	return base


static func _apply_planar_affix(rng: RandomNumberGenerator, data: Dictionary) -> String:
	var roll := rng.randf()
	if roll < 0.42:
		# Phasing — reaches every layer, at a cost.
		data["layer_rule"] = CbtDamage.LAYER_ALL
		data["damage"] = snappedf(float(data["damage"]) * 0.78, 0.1)
		data["energy_cost"] = snappedf(float(data.get("energy_cost", 0.0)) * 1.4 + 2.0, 0.1)
		return "Phasing"
	if roll < 0.74:
		# Echoing — useless on your own plane, brutal one step back.
		data["layer_rule"] = CbtDamage.LAYER_RANGE
		data["layer_min"] = 1
		data["layer_max"] = 1
		data["damage"] = snappedf(float(data["damage"]) * 1.65, 0.1)
		data["crit_chance"] = snappedf(clampf(float(data["crit_chance"]) + 0.12, 0.0, 0.8), 0.001)
		return "Echoing"
	# Deepstriking — a slab of layers, fading with depth.
	data["layer_rule"] = CbtDamage.LAYER_RANGE
	data["layer_min"] = 0
	data["layer_max"] = rng.randi_range(2, 4)
	data["layer_falloff"] = snappedf(rng.randf_range(0.7, 0.88), 0.01)
	data["damage"] = snappedf(float(data["damage"]) * 0.92, 0.1)
	return "Deepstriking"


static func _roll_color(rng: RandomNumberGenerator, element: String, rarity: int) -> Color:
	var base := CbtMeleeFx.element_color(element)
	var rc: Color = Const.RARITY_COLORS[clampi(rarity, 0, 4)]
	var c := base.lerp(rc, 0.4)
	c.r = clampf(c.r * rng.randf_range(0.88, 1.12), 0.0, 1.0)
	c.g = clampf(c.g * rng.randf_range(0.88, 1.12), 0.0, 1.0)
	c.b = clampf(c.b * rng.randf_range(0.88, 1.12), 0.0, 1.0)
	return c
