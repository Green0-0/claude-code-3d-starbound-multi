class_name SpeciesDB
extends RefCounted

## The bestiary: Starbound's hand-made unique monsters, rebuilt with a real
## behaviour model underneath them.
##
## Every creature here is a *character* rather than a stat block. A Poptop
## wanders whistling to itself until you get close; a Yokat grazes and bolts;
## a Hypnare will not touch you unless you touch it first; a Crustoise has to be
## cracked open before it can be hurt properly; a Fennix hunts.
##
## The fields that make that work:
##
## | field | what it drives |
## |---|---|
## | `temperament` | passive / skittish / defensive / aggressive / ambush |
## | `activity` | diurnal, nocturnal or always — creatures sleep on schedule |
## | `diet` | what it eats, and therefore what tames it |
## | `social` | solitary, herd (stay together, flee together) or pack (flank) |
## | `territory` | how far from home it will defend, or 0 for nomads |
## | `courage` | the health fraction below which it breaks and runs |
## | `senses` | sight range and cone, plus hearing — which is what makes crouching work |
## | `armour` | a shell that has to be broken before real damage lands |
##
## Nothing here is procedurally generated and there are no farm animals: these
## are the named creatures, and the starting planet is stocked from them.

## Re-exported from `CreatureTraits` so `SpeciesDB.TEMPER_PASSIVE` still reads
## naturally at call sites. The definitions live there rather than here because
## the inner `Def` class below needs them, and an inner class that reaches back
## out to its own outer `class_name` is a self-dependency the editor's analyser
## refuses to resolve.
const FAM_GROUND := CreatureTraits.FAM_GROUND
const FAM_FLYING := CreatureTraits.FAM_FLYING
const FAM_AQUATIC := CreatureTraits.FAM_AQUATIC
const FAM_SPECIAL := CreatureTraits.FAM_SPECIAL
const FAM_BOSS := CreatureTraits.FAM_BOSS

const TEMPER_PASSIVE := CreatureTraits.TEMPER_PASSIVE
const TEMPER_SKITTISH := CreatureTraits.TEMPER_SKITTISH
const TEMPER_DEFENSIVE := CreatureTraits.TEMPER_DEFENSIVE
const TEMPER_AGGRESSIVE := CreatureTraits.TEMPER_AGGRESSIVE
const TEMPER_AMBUSH := CreatureTraits.TEMPER_AMBUSH

const ACTIVE_DAY := CreatureTraits.ACTIVE_DAY
const ACTIVE_NIGHT := CreatureTraits.ACTIVE_NIGHT
const ACTIVE_ALWAYS := CreatureTraits.ACTIVE_ALWAYS

const SOCIAL_ALONE := CreatureTraits.SOCIAL_ALONE
const SOCIAL_HERD := CreatureTraits.SOCIAL_HERD
const SOCIAL_PACK := CreatureTraits.SOCIAL_PACK


class Def extends RefCounted:
	var id: StringName = &""
	var display := ""
	var description := ""
	var family: StringName = CreatureTraits.FAM_GROUND
	var locomotion: StringName = &"walk"        ## walk, hop, fly, float, swim, root, climb
	var threat := 0
	var biomes: Array[StringName] = []

	# --- body and numbers
	var health := 30.0
	var damage := 5.0
	var speed := 3.0
	var jump := 9.0
	var size := Vector3(0.8, 0.8, 0.8)
	var attack_cd := 1.2
	var knockback := 6.0
	var element: StringName = Blocks.ELEM_PHYSICAL
	var resists := {}
	## Flat damage soaked until the shell is broken; 0 for anything soft.
	var armour := 0.0
	var armour_hp := 0.0

	# --- character
	var temperament: StringName = CreatureTraits.TEMPER_DEFENSIVE
	var activity: StringName = CreatureTraits.ACTIVE_ALWAYS
	var social: StringName = CreatureTraits.SOCIAL_ALONE
	var pack_min := 1
	var pack_max := 1
	## How far from where it woke up it will go before turning back. 0 = nomad.
	var territory := 0.0
	## Health fraction below which it breaks and runs. 0 = fights to the death.
	var courage := 0.0
	## Seconds of hesitation between noticing you and committing.
	var wariness := 0.4

	# --- senses
	var sight := 14.0
	var sight_cone := 0.35        ## dot threshold; lower is a wider cone
	var hearing := 12.0
	var leash := 30.0

	# --- appetite, which is also how it is tamed
	var diet: Array[StringName] = []
	var grazes := false           ## eats the ground cover it stands on

	# --- ranged and specials
	var flags := {}

	# --- look
	var color := Color(0.6, 0.6, 0.6)
	var alt := Color(0.4, 0.4, 0.4)
	var shape: StringName = &"blob"
	var features := {}

	var drops: Array = []
	var worth := 5

	# --- builders ------------------------------------------------------------

	func kind(fam: StringName, loco: StringName) -> Def:
		family = fam
		locomotion = loco
		return self

	func at(list: Array) -> Def:
		for b in list:
			biomes.append(StringName(b))
		return self

	func rank(t: int) -> Def:
		threat = t
		return self

	func stats(hp: float, dmg: float, spd: float, jmp := 9.0) -> Def:
		health = hp
		damage = dmg
		speed = spd
		jump = jmp
		return self

	func body(s: Vector3) -> Def:
		size = s
		return self

	func acts(temper: StringName, when := CreatureTraits.ACTIVE_ALWAYS) -> Def:
		temperament = temper
		activity = when
		return self

	func group(kind_name: StringName, lo := 1, hi := 1) -> Def:
		social = kind_name
		pack_min = lo
		pack_max = hi
		return self

	func holds(radius: float) -> Def:
		territory = radius
		return self

	func breaks_at(fraction: float) -> Def:
		courage = fraction
		return self

	func senses(p_sight: float, p_hearing: float, cone := 0.35, p_leash := 30.0) -> Def:
		sight = p_sight
		hearing = p_hearing
		sight_cone = cone
		leash = p_leash
		return self

	func waits(seconds: float) -> Def:
		wariness = seconds
		return self

	func melee(cooldown: float, knock := 6.0) -> Def:
		attack_cd = cooldown
		knockback = knock
		return self

	func elemental(e: StringName) -> Def:
		element = e
		return self

	func resist(d: Dictionary) -> Def:
		resists = d
		return self

	func shelled(soak: float, shell_hp: float) -> Def:
		armour = soak
		armour_hp = shell_hp
		return self

	func eats(list: Array, graze := false) -> Def:
		for i in list:
			diet.append(StringName(i))
		grazes = graze
		return self

	func look(c: Color, a: Color, s: StringName, f := {}) -> Def:
		color = c
		alt = a
		shape = s
		features = f
		return self

	func drop(item: StringName, lo := 1, hi := 1, chance := 1.0) -> Def:
		drops.append([item, lo, hi, chance])
		return self

	func with_flags(d: Dictionary) -> Def:
		for k in d:
			flags[k] = d[k]
		return self

	func value(v: int) -> Def:
		worth = v
		return self

	func describe(text: String) -> Def:
		description = text
		return self

	# --- queries -------------------------------------------------------------

	## Matching on a constant that lives in another script forces that script to
	## be fully resolved at parse time. Delegating instead keeps the dependency
	## to a plain function call, which nothing has to resolve early.
	func is_awake(night: bool) -> bool:
		return CreatureTraits.awake_now(activity, night)

	func hunts() -> bool:
		return CreatureTraits.hunts(temperament)

	func will_fight() -> bool:
		return CreatureTraits.will_fight(temperament)

	func likes(item: StringName) -> bool:
		return diet.has(item)

	func roll_drops(rng: RandomNumberGenerator, luck := 0.0) -> Array:
		var out: Array = []
		for d: Array in drops:
			if rng.randf() > minf(float(d[3]) + luck, 1.0):
				continue
			var n := rng.randi_range(int(d[1]), int(d[2]))
			if n > 0:
				out.append([d[0], n])
		return out


static var defs: Array[Def] = []
static var by_id := {}
static var _booted := false


static func boot() -> void:
	if _booted:
		return
	_booted = true
	_gentle()
	_wary()
	_hunters()
	_caves()
	_bosses()


static func define(id: StringName, display: String) -> Def:
	var d := Def.new()
	d.id = id
	d.display = display
	defs.append(d)
	by_id[id] = d
	return d


static func get_def(id: StringName) -> Def:
	return by_id.get(id)


## Everything that can spawn in `biome` at or below `threat`, boss-free.
static func pool_for(biome: StringName, threat: int) -> Array[Def]:
	var out: Array[Def] = []
	for d: Def in defs:
		if d.family == FAM_BOSS or d.threat > threat:
			continue
		if d.flags.has(&"summon_only"):
			continue
		if d.biomes.is_empty() or d.biomes.has(biome):
			out.append(d)
	return out


static func bosses() -> Array[Def]:
	var out: Array[Def] = []
	for d: Def in defs:
		if d.family == FAM_BOSS:
			out.append(d)
	return out


# =============================================================================
# the gentle end of the roster — the creatures a starting planet is made of
# =============================================================================

static func _gentle() -> void:
	define(&"poptop", "Poptop") \
		.kind(FAM_GROUND, &"hop").rank(0) \
		.at([&"forest", &"garden", &"jungle", &"savannah"]) \
		.stats(34.0, 6.0, 2.8, 9.5).body(Vector3(0.8, 0.8, 0.8)) \
		.acts(TEMPER_DEFENSIVE, ACTIVE_DAY).group(SOCIAL_HERD, 2, 4) \
		.senses(11.0, 9.0, 0.1, 22.0).waits(0.9).melee(1.3, 5.0) \
		.holds(9.0).breaks_at(0.25) \
		.eats([&"tall_grass", &"flower_red", &"flower_yellow", &"carrot"], true) \
		.look(Color(0.86, 0.42, 0.52), Color(0.36, 0.62, 0.30), &"bulb",
			{"eyes": 2, "limbs": 2, "bulb": true}) \
		.drop(&"raw_meat", 1, 2, 0.7).drop(&"plant_fibre", 1, 2, 0.4).value(6) \
		.describe("A tulip on legs. It wanders about whistling to itself and is "
			+ "perfectly harmless right up until you are inside its patch, at "
			+ "which point it leaps at your face.")

	define(&"gleap", "Gleap") \
		.kind(FAM_GROUND, &"hop").rank(1) \
		.at([&"forest", &"garden", &"jungle", &"ocean"]) \
		.stats(26.0, 5.0, 3.4, 12.0).body(Vector3(0.7, 0.6, 0.7)) \
		.acts(TEMPER_SKITTISH, ACTIVE_DAY).group(SOCIAL_HERD, 3, 5) \
		.senses(14.0, 13.0, 0.0, 20.0).waits(0.2).melee(1.4, 4.0) \
		.breaks_at(0.9) \
		.eats([&"tall_grass", &"fern", &"mushroom_brown"], true) \
		.look(Color(0.44, 0.76, 0.48), Color(0.24, 0.50, 0.30), &"blob",
			{"eyes": 2, "limbs": 2}) \
		.drop(&"raw_meat", 1, 1, 0.5).drop(&"slime_glob", 1, 2, 0.5).value(4) \
		.describe("Bolts the instant it sees you, in whichever direction it was "
			+ "already facing. Occasionally that is toward you.")

	define(&"yokat", "Yokat") \
		.kind(FAM_GROUND, &"walk").rank(1) \
		.at([&"savannah", &"desert", &"forest", &"barren"]) \
		.stats(40.0, 7.0, 4.6, 10.0).body(Vector3(0.9, 0.7, 0.9)) \
		.acts(TEMPER_SKITTISH, ACTIVE_DAY).group(SOCIAL_HERD, 3, 6) \
		.senses(18.0, 16.0, 0.0, 26.0).waits(0.15).melee(1.2, 6.0) \
		.breaks_at(1.0).holds(0.0) \
		.eats([&"tall_grass", &"dry_grass", &"wheat", &"carrot"], true) \
		.look(Color(0.82, 0.66, 0.34), Color(0.52, 0.38, 0.22), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true, "horns": 2}) \
		.drop(&"raw_meat", 1, 3, 0.9).drop(&"hide", 1, 2, 0.7) \
		.drop(&"monster_fur", 1, 2, 0.4).value(9) \
		.describe("Grazes in loose herds and runs as one animal. Cornered, it "
			+ "will put its head down and go through you rather than round.")

	define(&"hypnare", "Hypnare") \
		.kind(FAM_GROUND, &"hop").rank(2) \
		.at([&"jungle", &"garden", &"forest"]) \
		.stats(58.0, 11.0, 3.0, 11.0).body(Vector3(0.8, 1.0, 0.8)) \
		.acts(TEMPER_PASSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(10.0, 8.0, 0.2, 16.0).melee(1.5, 7.0) \
		.breaks_at(0.0).holds(6.0) \
		.elemental(Blocks.ELEM_POISON) \
		.eats([&"flower_purple", &"glow_flower", &"mushroom_red"]) \
		.with_flags({&"retaliates": true, &"inflicts": &"slow", &"inflict_time": 6.0}) \
		.look(Color(0.76, 0.44, 0.86), Color(0.34, 0.56, 0.30), &"plant",
			{"eyes": 3, "glow": 0.2, "petals": 5}) \
		.drop(&"plant_matter", 1, 3, 0.9).drop(&"venom_gland", 1, 1, 0.35) \
		.value(14) \
		.describe("The only thing on this world that genuinely will not start "
			+ "anything. Hit it once and it spins itself into a blur, and "
			+ "whatever it touches goes slow and stupid for a while.")

	define(&"mandraflora", "Mandraflora") \
		.kind(FAM_GROUND, &"walk").rank(2) \
		.at([&"jungle", &"garden", &"forest", &"toxic"]) \
		.stats(66.0, 12.0, 3.8, 8.0).body(Vector3(0.9, 1.1, 0.9)) \
		.acts(TEMPER_AMBUSH, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(6.0, 5.0, -1.0, 18.0).waits(0.35).melee(1.1, 9.0) \
		.holds(12.0).breaks_at(0.15) \
		.with_flags({&"charge_range": 11.0, &"charge_speed": 2.4,
			&"disguised": true}) \
		.look(Color(0.52, 0.70, 0.32), Color(0.86, 0.74, 0.36), &"plant",
			{"eyes": 2, "petals": 6, "roots": true}) \
		.drop(&"plant_matter", 2, 4, 1.0).drop(&"plant_fibre", 1, 3, 0.6) \
		.value(16) \
		.describe("Indistinguishable from the undergrowth until it pulls itself "
			+ "out of the soil and spins at you roots-first.")


# =============================================================================
# the wary middle — things that will hurt you if you are careless
# =============================================================================

static func _wary() -> void:
	define(&"crustoise", "Crustoise") \
		.kind(FAM_GROUND, &"climb").rank(3) \
		.at([&"desert", &"forest", &"jungle", &"savannah", &"volcanic"]) \
		.stats(90.0, 14.0, 3.2, 7.0).body(Vector3(1.1, 0.8, 1.1)) \
		.acts(TEMPER_DEFENSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(13.0, 10.0, 0.2, 24.0).waits(0.8).melee(1.5, 10.0) \
		.shelled(6.0, 45.0).holds(14.0).breaks_at(0.0) \
		.resist({Blocks.ELEM_FIRE: 0.4, Blocks.ELEM_POISON: 1.6}) \
		.with_flags({&"charge_range": 10.0, &"charge_speed": 2.2, &"wall_crawl": true}) \
		.eats([&"kelp", &"mushroom_brown"]) \
		.look(Color(0.46, 0.58, 0.44), Color(0.72, 0.60, 0.34), &"crab",
			{"eyes": 2, "limbs": 6, "shell": true}) \
		.drop(&"chitin_plate", 1, 2, 0.8).drop(&"raw_meat", 1, 2, 0.5) \
		.value(22) \
		.describe("Walks up walls and across ceilings without appearing to "
			+ "notice which way is down. The shell soaks almost everything — "
			+ "crack it first, or bring poison.")

	define(&"pteropod", "Pteropod") \
		.kind(FAM_FLYING, &"fly").rank(2) \
		.at([&"toxic", &"jungle", &"midnight", &"ocean"]) \
		.stats(44.0, 9.0, 4.4).body(Vector3(0.8, 0.7, 0.8)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_NIGHT).group(SOCIAL_ALONE) \
		.senses(19.0, 15.0, 0.1, 30.0).waits(0.5).melee(1.8, 4.0) \
		.breaks_at(0.2) \
		.elemental(Blocks.ELEM_POISON) \
		.resist({Blocks.ELEM_POISON: 0.0, Blocks.ELEM_FIRE: 1.7}) \
		.with_flags({&"projectile": &"acid_glob", &"range": 15.0}) \
		.look(Color(0.58, 0.76, 0.40), Color(0.34, 0.46, 0.24), &"winged",
			{"eyes": 2, "wings": 2, "glow": 0.15}) \
		.drop(&"venom_gland", 1, 1, 0.5).drop(&"raw_meat", 1, 1, 0.4) \
		.value(15) \
		.describe("Hangs in the air just out of reach and spits. Burns "
			+ "beautifully; poison does nothing at all.")

	define(&"narfin", "Narfin") \
		.kind(FAM_GROUND, &"walk").rank(2) \
		.at([&"tundra", &"snow", &"ocean", &"crystal"]) \
		.stats(54.0, 11.0, 4.8, 10.0).body(Vector3(0.9, 0.8, 0.9)) \
		.acts(TEMPER_DEFENSIVE, ACTIVE_ALWAYS).group(SOCIAL_PACK, 2, 3) \
		.senses(16.0, 14.0, 0.15, 28.0).waits(0.6).melee(1.2, 11.0) \
		.breaks_at(0.2).holds(11.0) \
		.elemental(Blocks.ELEM_ICE) \
		.resist({Blocks.ELEM_ICE: 0.0, Blocks.ELEM_FIRE: 1.8}) \
		.with_flags({&"charge_range": 12.0, &"charge_speed": 2.5}) \
		.eats([&"raw_fish"]) \
		.look(Color(0.78, 0.86, 0.94), Color(0.36, 0.54, 0.72), &"quadruped",
			{"eyes": 2, "limbs": 4, "tusk": true}) \
		.drop(&"raw_meat", 1, 2, 0.7).drop(&"ice_crystal", 1, 1, 0.3) \
		.drop(&"monster_fur", 1, 2, 0.5).value(18) \
		.describe("Provoke one and it lowers its tusks and comes at you in a "
			+ "straight line. Provoke one and you have provoked all of them.")

	define(&"voltip", "Voltip") \
		.kind(FAM_GROUND, &"walk").rank(2) \
		.at([&"forest", &"tundra", &"crystal", &"alien"]) \
		.stats(46.0, 10.0, 4.0, 10.0).body(Vector3(0.8, 0.7, 0.8)) \
		.acts(TEMPER_DEFENSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(15.0, 12.0, 0.2, 24.0).waits(0.7).melee(1.6, 5.0) \
		.breaks_at(0.3).holds(10.0) \
		.elemental(Blocks.ELEM_ELECTRIC) \
		.resist({Blocks.ELEM_ELECTRIC: 0.0}) \
		.with_flags({&"projectile": &"lightning_arc", &"range": 9.0,
			&"telegraph": 0.6}) \
		.eats([&"crystal_shard"]) \
		.look(Color(0.94, 0.88, 0.42), Color(0.38, 0.52, 0.78), &"quadruped",
			{"eyes": 2, "limbs": 4, "glow": 0.4, "tail": true}) \
		.drop(&"battery", 1, 1, 0.25).drop(&"raw_meat", 1, 1, 0.5) \
		.drop(&"crystal_shard", 1, 2, 0.4).value(20) \
		.describe("Puts its front paws together, and there is a moment where "
			+ "you can still get out of the way.")

	define(&"snaunt", "Snaunt") \
		.kind(FAM_GROUND, &"walk").rank(2) \
		.at([&"desert", &"barren", &"savannah", &"moon"]) \
		.stats(52.0, 10.0, 3.6, 9.0).body(Vector3(0.8, 1.1, 0.8)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_NIGHT).group(SOCIAL_ALONE) \
		.senses(20.0, 17.0, 0.25, 32.0).waits(0.5).melee(1.7, 6.0) \
		.breaks_at(0.15) \
		.with_flags({&"projectile": &"acid_glob", &"range": 13.0}) \
		.look(Color(0.66, 0.62, 0.50), Color(0.40, 0.36, 0.30), &"biped",
			{"eyes": 4, "limbs": 2, "spikes": 3}) \
		.drop(&"raw_meat", 1, 2, 0.6).drop(&"bone", 1, 2, 0.5).value(17) \
		.describe("Stalks at the edge of the torchlight and spits when it "
			+ "decides you have not noticed it.")

	define(&"skimbus", "Skimbus") \
		.kind(FAM_FLYING, &"float").rank(3) \
		.at([&"tundra", &"snow", &"alien", &"crystal"]) \
		.stats(62.0, 13.0, 3.4).body(Vector3(1.0, 1.0, 1.0)) \
		.acts(TEMPER_DEFENSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(17.0, 14.0, 0.0, 34.0).waits(1.1).melee(1.4, 12.0) \
		.breaks_at(0.0) \
		.elemental(Blocks.ELEM_ICE) \
		.resist({Blocks.ELEM_ICE: 0.0, Blocks.ELEM_FIRE: 1.8}) \
		.with_flags({&"phases_terrain": true, &"charge_range": 14.0,
			&"charge_speed": 2.8, &"telegraph": 0.9}) \
		.look(Color(0.82, 0.90, 0.96), Color(0.44, 0.64, 0.84), &"orb",
			{"eyes": 2, "glow": 0.3, "tendrils": 4}) \
		.drop(&"ice_crystal", 1, 2, 0.6).drop(&"ectoplasm", 1, 1, 0.2) \
		.value(24) \
		.describe("Drifts through solid rock as if it were not there. When it "
			+ "turns red you have about a second.")

	define(&"petricub", "Petricub") \
		.kind(FAM_GROUND, &"walk").rank(3) \
		.at([&"alien", &"midnight", &"barren", &"crystal"]) \
		.stats(84.0, 15.0, 4.4, 11.0).body(Vector3(1.0, 0.9, 1.0)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(18.0, 15.0, 0.2, 32.0).waits(0.6).melee(1.1, 9.0) \
		.breaks_at(0.1) \
		.resist({Blocks.ELEM_PHYSICAL: 0.55}) \
		.eats([&"raw_meat"]) \
		.look(Color(0.60, 0.58, 0.62), Color(0.86, 0.52, 0.30), &"quadruped",
			{"eyes": 2, "limbs": 4, "stone": true}) \
		.drop(&"cobblestone", 2, 4, 0.7).drop(&"raw_meat", 1, 2, 0.5) \
		.drop(&"crystal_shard", 1, 2, 0.3).value(26) \
		.describe("Skin like slate. Blunt weapons slide off it; bring "
			+ "something elemental, or a great deal of patience.")


# =============================================================================
# the hunters
# =============================================================================

static func _hunters() -> void:
	define(&"fennix", "Fennix") \
		.kind(FAM_GROUND, &"walk").rank(4) \
		.at([&"volcanic", &"desert", &"savannah", &"barren"]) \
		.stats(96.0, 18.0, 5.6, 12.0).body(Vector3(0.9, 0.8, 0.9)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_ALWAYS).group(SOCIAL_PACK, 1, 3) \
		.senses(24.0, 20.0, 0.25, 40.0).waits(0.35).melee(1.0, 7.0) \
		.breaks_at(0.12).holds(0.0) \
		.elemental(Blocks.ELEM_FIRE) \
		.resist({Blocks.ELEM_FIRE: 0.0, Blocks.ELEM_ICE: 1.6}) \
		.with_flags({&"projectile": &"flame_gout", &"range": 8.0, &"burst": 3,
			&"telegraph": 0.5}) \
		.eats([&"cooked_meat", &"raw_meat"]) \
		.look(Color(0.94, 0.52, 0.20), Color(0.98, 0.86, 0.52), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true, "glow": 0.5, "ears": true}) \
		.drop(&"raw_meat", 1, 2, 0.7).drop(&"monster_fur", 1, 2, 0.6) \
		.drop(&"sulphur", 1, 2, 0.4).value(42) \
		.describe("A fox that breathes fire, hunts in threes and does not "
			+ "particularly care how well armed you are. If you meet one early, "
			+ "the correct move is to leave.")

	define(&"ixoling", "Ixoling") \
		.kind(FAM_GROUND, &"hop").rank(2) \
		.at([&"jungle", &"midnight", &"ancient_ruins"]) \
		.stats(28.0, 8.0, 4.8, 11.5).body(Vector3(0.6, 0.5, 0.6)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_ALWAYS).group(SOCIAL_PACK, 3, 5) \
		.senses(16.0, 15.0, 0.0, 26.0).waits(0.1).melee(0.9, 4.0) \
		.breaks_at(0.0) \
		.with_flags({&"summon_only": true}) \
		.look(Color(0.72, 0.48, 0.34), Color(0.40, 0.24, 0.20), &"insect",
			{"eyes": 4, "limbs": 6}) \
		.drop(&"chitin", 1, 1, 0.5).value(6) \
		.describe("Hatches by the dozen and crawls straight at you. Individually "
			+ "trivial, which is not the point of them.")


# =============================================================================
# underground
# =============================================================================

static func _caves() -> void:
	define(&"lumoth", "Lumoth") \
		.kind(FAM_FLYING, &"float").rank(0) \
		.at([]) \
		.stats(20.0, 3.0, 2.2).body(Vector3(0.7, 0.6, 0.7)) \
		.acts(TEMPER_PASSIVE, ACTIVE_ALWAYS).group(SOCIAL_HERD, 2, 4) \
		.senses(12.0, 10.0, 0.0, 18.0).melee(2.0, 2.0) \
		.breaks_at(1.0) \
		.resist({Blocks.ELEM_ELECTRIC: 1.8, Blocks.ELEM_POISON: 0.0}) \
		.with_flags({&"phases_terrain": true, &"underground": true}) \
		.look(Color(0.96, 0.92, 0.56), Color(0.62, 0.72, 0.44), &"winged",
			{"eyes": 2, "wings": 4, "glow": 0.95}) \
		.drop(&"glow_dust", 1, 3, 0.9).drop(&"luminous_powder", 1, 1, 0.25) \
		.value(12) \
		.describe("Drifts through the rock giving off a soft yellow light and "
			+ "wants nothing from anybody. Following one is usually a good idea.")

	define(&"oculob", "Oculob") \
		.kind(FAM_GROUND, &"hop").rank(2) \
		.at([]) \
		.stats(38.0, 9.0, 3.0, 10.0).body(Vector3(0.8, 0.8, 0.8)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(20.0, 8.0, -1.0, 24.0).waits(0.4).melee(1.3, 5.0) \
		.breaks_at(0.0) \
		.with_flags({&"underground": true, &"death_burst": true}) \
		.look(Color(0.86, 0.86, 0.90), Color(0.62, 0.28, 0.34), &"eye",
			{"eyes": 1, "glow": 0.3}) \
		.drop(&"slime_glob", 1, 2, 0.8).drop(&"sensor_lens", 1, 1, 0.12) \
		.value(15) \
		.describe("One enormous eye, and it is always looking at you — there is "
			+ "no angle you can approach it from. Pops harmlessly when killed.")

	define(&"batong", "Batong") \
		.kind(FAM_FLYING, &"fly").rank(1) \
		.at([]) \
		.stats(22.0, 6.0, 5.6).body(Vector3(0.6, 0.5, 0.6)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_NIGHT).group(SOCIAL_PACK, 3, 6) \
		.senses(17.0, 22.0, -1.0, 28.0).waits(0.2).melee(1.0, 3.0) \
		.breaks_at(0.35) \
		.with_flags({&"underground": true, &"erratic": true}) \
		.look(Color(0.42, 0.34, 0.44), Color(0.70, 0.44, 0.52), &"winged",
			{"eyes": 2, "wings": 2, "ears": true}) \
		.drop(&"raw_meat", 1, 1, 0.4).drop(&"monster_fur", 1, 1, 0.3).value(7) \
		.describe("Blind, and it does not need to see you. Hearing is the only "
			+ "sense it has and the only one it needs.")

	define(&"anglure", "Anglure") \
		.kind(FAM_GROUND, &"walk").rank(3) \
		.at([]) \
		.stats(74.0, 16.0, 3.0, 8.0).body(Vector3(0.9, 0.9, 0.9)) \
		.acts(TEMPER_AMBUSH, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(5.0, 4.0, -1.0, 20.0).waits(0.15).melee(1.2, 8.0) \
		.breaks_at(0.0).holds(8.0) \
		.with_flags({&"underground": true, &"disguised": true, &"lure": true}) \
		.look(Color(0.30, 0.42, 0.48), Color(0.96, 0.92, 0.56), &"fish",
			{"eyes": 2, "glow": 0.8, "teeth": 10, "lure": true}) \
		.drop(&"raw_fish", 1, 2, 0.7).drop(&"glow_gland", 1, 1, 0.4).value(28) \
		.describe("The little light in the dark ahead of you is the bait. The "
			+ "rest of it does not light up at all.")

	define(&"scandroid", "Scandroid") \
		.kind(FAM_GROUND, &"walk").rank(3) \
		.at([&"barren", &"moon", &"ancient_ruins", &"crystal"]) \
		.stats(70.0, 12.0, 3.4, 8.0).body(Vector3(0.8, 1.0, 0.8)) \
		.acts(TEMPER_DEFENSIVE, ACTIVE_ALWAYS).group(SOCIAL_PACK, 1, 2) \
		.senses(26.0, 12.0, 0.45, 40.0).waits(1.0).melee(1.6, 5.0) \
		.breaks_at(0.0).holds(16.0) \
		.elemental(Blocks.ELEM_ELECTRIC) \
		.resist({Blocks.ELEM_ELECTRIC: 0.3, Blocks.ELEM_POISON: 0.0}) \
		.with_flags({&"projectile": &"bullet", &"range": 18.0, &"alarm": 30.0,
			&"telegraph": 0.4}) \
		.look(Color(0.66, 0.68, 0.72), Color(0.94, 0.36, 0.30), &"robot",
			{"eyes": 1, "limbs": 2, "glow": 0.6, "antenna": true}) \
		.drop(&"scrap_metal", 1, 3, 0.9).drop(&"copper_wire", 1, 2, 0.5) \
		.drop(&"circuit_board", 1, 1, 0.15).value(30) \
		.describe("A long narrow sight cone and nothing else worth speaking of "
			+ "— but the moment it does see you it tells everything within "
			+ "thirty metres exactly where you are standing.")


# =============================================================================
# bosses
# =============================================================================

static func _bosses() -> void:
	define(&"mother_poptop", "Mother Poptop") \
		.kind(FAM_BOSS, &"hop").rank(4) \
		.at([&"forest", &"garden", &"jungle"]) \
		.stats(620.0, 22.0, 3.2, 12.0).body(Vector3(2.0, 2.0, 2.0)) \
		.acts(TEMPER_DEFENSIVE, ACTIVE_ALWAYS).group(SOCIAL_HERD, 1, 1) \
		.senses(26.0, 24.0, 0.0, 200.0).waits(0.5).melee(1.4, 18.0) \
		.breaks_at(0.0).holds(0.0) \
		.eats([&"carrot", &"wheat"]) \
		.with_flags({&"summons": &"poptop", &"summon_count": 3,
			&"shockwave": 8.0}) \
		.look(Color(0.92, 0.34, 0.46), Color(0.30, 0.58, 0.28), &"bulb",
			{"eyes": 4, "limbs": 4, "bulb": true, "glow": 0.2}) \
		.drop(&"raw_meat", 4, 8, 1.0).drop(&"living_wood", 1, 3, 1.0) \
		.drop(&"pixels", 400, 800, 1.0).value(400) \
		.describe("The reason the little ones are so confident.")

	define(&"ixodoom", "Ixodoom") \
		.kind(FAM_BOSS, &"walk").rank(6) \
		.at([&"jungle", &"ancient_ruins", &"midnight"]) \
		.stats(1500.0, 34.0, 4.0, 9.0).body(Vector3(2.6, 2.0, 2.6)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(40.0, 36.0, -1.0, 200.0).waits(0.2).melee(1.2, 20.0) \
		.shelled(14.0, 400.0).breaks_at(0.0) \
		.elemental(Blocks.ELEM_POISON) \
		.resist({Blocks.ELEM_POISON: 0.0, Blocks.ELEM_PHYSICAL: 0.6}) \
		.with_flags({&"projectile": &"acid_glob", &"range": 22.0, &"burst": 5,
			&"summons": &"ixoling", &"summon_count": 4, &"charge_range": 18.0,
			&"charge_speed": 2.2}) \
		.look(Color(0.54, 0.30, 0.26), Color(0.86, 0.92, 0.34), &"crab",
			{"eyes": 6, "limbs": 8, "shell": true, "glow": 0.3}) \
		.drop(&"hivemind_scepter", 1, 1, 1.0).drop(&"chitin_plate", 4, 8, 1.0) \
		.drop(&"pixels", 1400, 2200, 1.0).value(1400) \
		.describe("Half crab, half spider, entirely armoured. Crack the shell "
			+ "before anything you do will matter, and mind the eggs.")

	define(&"boss_magma_heart", "The Magma Heart") \
		.kind(FAM_BOSS, &"root").rank(6).at([&"volcanic", &"scorched"]) \
		.stats(1800.0, 40.0, 0.0, 0.0).body(Vector3(2.6, 2.6, 2.6)) \
		.acts(TEMPER_AGGRESSIVE, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(50.0, 50.0, -1.0, 200.0).melee(1.4, 16.0) \
		.elemental(Blocks.ELEM_FIRE) \
		.resist({Blocks.ELEM_FIRE: 0.0, Blocks.ELEM_ICE: 2.0}) \
		.with_flags({&"projectile": &"fireball", &"range": 26.0, &"burst": 4,
			&"summons": &"fennix", &"summon_count": 2}) \
		.look(Color(1.0, 0.48, 0.14), Color(0.30, 0.10, 0.08), &"titan",
			{"eyes": 5, "glow": 1.0}) \
		.drop(&"heart_of_the_forge", 1, 1, 1.0).drop(&"core_fragment", 3, 6, 1.0) \
		.drop(&"pixels", 1600, 2600, 1.0).value(1800) \
		.describe("At the bottom of the shaft, and it has been waiting.")

	define(&"boss_fourfold", "The Fourfold") \
		.kind(FAM_BOSS, &"walk").rank(6).at([&"ancient_ruins", &"midnight"]) \
		.stats(1600.0, 38.0, 6.0, 13.0).body(Vector3(1.8, 2.6, 1.8)) \
		.acts(TEMPER_AMBUSH, ACTIVE_ALWAYS).group(SOCIAL_ALONE) \
		.senses(60.0, 60.0, -1.0, 200.0).waits(0.1).melee(0.9, 10.0) \
		.elemental(Blocks.ELEM_COSMIC) \
		.resist({Blocks.ELEM_PHYSICAL: 0.6, Blocks.ELEM_COSMIC: 0.0}) \
		.with_flags({&"phases_terrain": true, &"only_visible_in_cut": true,
			&"blinks": true}) \
		.look(Color(0.62, 0.50, 0.88), Color(0.20, 0.16, 0.30), &"wraith",
			{"eyes": 4, "glow": 0.8}) \
		.drop(&"null_sequence", 1, 1, 1.0).drop(&"ancient_essence", 2, 3, 1.0) \
		.drop(&"pixels", 1600, 2600, 1.0).value(1800) \
		.describe("One creature standing in four places. Turning the camera "
			+ "does not reveal it — it moves to wherever you are not looking.")
