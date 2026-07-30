class_name SpeciesDB
extends RefCounted

## The bestiary.
##
## A species is pure data; the monster actor copies what it needs on spawn and
## scales it by the planet's threat level. `behaviour` names a routine in
## `monster.gd` — `melee`, `charger`, `pack_hunter`, `ranged`, `flyer`,
## `hopper`, `turret`, `burrower`, `ambusher` — and `look` drives the procedural
## sprite, so a new species needs no art and no code.
##
## Two of them are built around the camera: the **stalker** hunts you from
## inside solid rock and only becomes visible when the cutaway slices it open,
## and the **mimic** is indistinguishable from a chest until the moment it is
## not.

const FAM_GROUND := &"ground"
const FAM_FLYING := &"flying"
const FAM_AQUATIC := &"aquatic"
const FAM_RANGED := &"ranged"
const FAM_SPECIAL := &"special"
const FAM_CRITTER := &"critter"
const FAM_BOSS := &"boss"


class Def extends RefCounted:
	var id: StringName = &""
	var display := ""
	var description := ""
	var family: StringName = SpeciesDB.FAM_GROUND
	var behaviour: StringName = &"melee"
	var threat := 0
	var biomes: Array[StringName] = []

	var health := 30.0
	var damage := 5.0
	var speed := 3.0
	var jump := 9.0
	var size := Vector3(0.8, 0.8, 0.8)
	var aggro := 12.0
	var leash := 26.0
	var attack_cd := 1.2
	var knockback := 6.0
	var element: StringName = Blocks.ELEM_PHYSICAL
	var resists := {}
	var worth := 5
	var pack_min := 1
	var pack_max := 1
	var flags := {}

	var color := Color(0.6, 0.6, 0.6)
	var alt := Color(0.4, 0.4, 0.4)
	var shape: StringName = &"blob"
	var features := {}

	var drops: Array = []            ## [[item, lo, hi, chance], ...]

	# --- builders ------------------------------------------------------------

	func kind(fam: StringName, behave: StringName) -> Def:
		family = fam
		behaviour = behave
		return self

	func acts(behave: StringName) -> Def:
		behaviour = behave
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

	func senses(agg: float, lsh := 26.0) -> Def:
		aggro = agg
		leash = lsh
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

	func look(c: Color, a: Color, s: StringName, f := {}) -> Def:
		color = c
		alt = a
		shape = s
		features = f
		return self

	func drop(item: StringName, lo := 1, hi := 1, chance := 1.0) -> Def:
		drops.append([item, lo, hi, chance])
		return self

	func packs(lo: int, hi: int) -> Def:
		pack_min = lo
		pack_max = hi
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

	## Loot for one kill, already rolled.
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
	_critters()
	_ground()
	_flying()
	_ranged()
	_special()
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
		if d.biomes.is_empty() or d.biomes.has(biome):
			out.append(d)
	return out


static func bosses() -> Array[Def]:
	var out: Array[Def] = []
	for d: Def in defs:
		if d.family == FAM_BOSS:
			out.append(d)
	return out


# ================================================================== critters
static func _critters() -> void:
	define(&"pebble_grub", "Pebble Grub") \
		.kind(FAM_CRITTER, &"melee").rank(0) \
		.at([&"forest", &"garden", &"mushroom"]) \
		.stats(24.0, 4.0, 2.6, 8.0).body(Vector3(0.7, 0.6, 0.7)) \
		.senses(9.0, 18.0).melee(1.4, 3.0) \
		.look(Color(0.55, 0.62, 0.35), Color(0.36, 0.42, 0.22), &"worm",
			{"eyes": 2, "limbs": 0, "pattern": &"plates"}) \
		.drop(&"slime_glob", 1, 2, 0.7).drop(&"raw_meat", 1, 1, 0.25).value(3) \
		.describe("A slow ring of chewing muscle. Mostly harmless, rarely alone.") \
		.packs(2, 4)

	define(&"hopper", "Meadow Hopper") \
		.kind(FAM_CRITTER, &"hopper").rank(0) \
		.at([&"forest", &"savannah", &"garden"]) \
		.stats(18.0, 2.0, 3.4, 11.0).body(Vector3(0.6, 0.6, 0.6)) \
		.senses(7.0, 14.0).melee(1.6, 2.0) \
		.look(Color(0.78, 0.68, 0.34), Color(0.52, 0.44, 0.22), &"blob",
			{"eyes": 2, "limbs": 2}) \
		.drop(&"raw_meat", 1, 1, 0.5).drop(&"hide", 1, 1, 0.3).value(2) \
		.describe("Startles easily, and startles you back when it does.") \
		.packs(3, 5)


# ==================================================================== ground
static func _ground() -> void:
	define(&"thorn_creeper", "Thorn Creeper") \
		.kind(FAM_GROUND, &"melee").rank(1) \
		.at([&"forest", &"jungle", &"garden", &"swamp"]) \
		.stats(38.0, 7.0, 3.6, 10.0).body(Vector3(0.8, 0.8, 0.8)) \
		.senses(12.0, 24.0).melee(1.2, 4.0) \
		.look(Color(0.32, 0.5, 0.24), Color(0.5, 0.42, 0.2), &"insect",
			{"eyes": 4, "limbs": 4, "spikes": 3, "pattern": &"stripes"}) \
		.drop(&"raw_meat", 1, 2, 0.6).drop(&"chitin", 1, 2, 0.5).value(6) \
		.describe("Barbed and territorial. It does not stop at the tree line.")

	define(&"crystal_skitter", "Crystal Skitter") \
		.kind(FAM_GROUND, &"melee").rank(3) \
		.at([&"crystal", &"moon", &"barren"]) \
		.stats(70.0, 14.0, 5.4, 13.0).body(Vector3(0.8, 0.9, 0.8)) \
		.senses(15.0, 30.0).melee(0.9) \
		.elemental(Blocks.ELEM_ELECTRIC) \
		.resist({Blocks.ELEM_ELECTRIC: 0.2, Blocks.ELEM_PHYSICAL: 0.8}) \
		.look(Color(0.55, 0.8, 0.95), Color(0.3, 0.45, 0.75), &"insect",
			{"eyes": 6, "limbs": 4, "spikes": 4, "glow": 0.25}) \
		.drop(&"crystal_shard", 1, 3, 0.8).drop(&"chitin", 1, 2, 0.4).value(18) \
		.describe("Facets for eyes. It hears footsteps through the stone.") \
		.packs(2, 3)

	define(&"magma_crawler", "Magma Crawler") \
		.kind(FAM_GROUND, &"melee").rank(3).at([&"volcanic", &"scorched"]) \
		.stats(95.0, 17.0, 3.4, 10.0).body(Vector3(1.0, 0.8, 1.0)) \
		.senses(14.0, 26.0).melee(1.3, 8.0) \
		.elemental(Blocks.ELEM_FIRE) \
		.resist({Blocks.ELEM_FIRE: 0.0, Blocks.ELEM_ICE: 1.8}) \
		.look(Color(0.85, 0.32, 0.12), Color(0.25, 0.12, 0.1), &"worm",
			{"eyes": 2, "limbs": 4, "glow": 0.35, "pattern": &"plates"}) \
		.drop(&"sulphur", 1, 2, 0.5).drop(&"chitin", 1, 2, 0.5).value(22) \
		.describe("Molten under a crust of slag. Douse it, then hit it.")

	define(&"dune_charger", "Dune Charger") \
		.kind(FAM_GROUND, &"melee").acts(&"charger").rank(2) \
		.at([&"desert", &"savannah", &"barren", &"scorched"]) \
		.stats(80.0, 15.0, 4.2, 11.0).body(Vector3(1.1, 1.0, 1.1)) \
		.senses(18.0, 34.0).melee(1.4, 12.0) \
		.look(Color(0.78, 0.62, 0.34), Color(0.5, 0.36, 0.2), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true, "spikes": 2, "pattern": &"stripes"}) \
		.with_flags({&"charge_range": 13.0, &"charge_speed": 2.6}) \
		.drop(&"raw_meat", 2, 3, 0.9).drop(&"hide", 1, 2, 0.6).value(14) \
		.describe("Lowers its head, and then the horizon comes to you.")

	define(&"frost_hound", "Frost Hound") \
		.kind(FAM_GROUND, &"melee").acts(&"pack_hunter").rank(2) \
		.at([&"snow", &"tundra", &"midnight"]) \
		.stats(62.0, 12.0, 5.6, 12.5).body(Vector3(0.9, 0.9, 0.9)) \
		.senses(20.0, 40.0).melee(0.9, 5.0) \
		.elemental(Blocks.ELEM_ICE).resist({Blocks.ELEM_ICE: 0.2}) \
		.look(Color(0.78, 0.86, 0.94), Color(0.42, 0.56, 0.70), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true}) \
		.drop(&"raw_meat", 1, 2, 0.8).drop(&"monster_fur", 1, 2, 0.7) \
		.drop(&"fang", 1, 1, 0.3).value(16) \
		.describe("Never alone, and never the one you are looking at.") \
		.packs(3, 5)

	define(&"boulder_beetle", "Boulder Beetle") \
		.kind(FAM_GROUND, &"melee").rank(3).at([&"barren", &"crystal", &"volcanic"]) \
		.stats(150.0, 16.0, 2.2, 7.0).body(Vector3(1.2, 1.0, 1.2)) \
		.senses(11.0, 20.0).melee(1.6, 10.0) \
		.resist({Blocks.ELEM_PHYSICAL: 0.45}) \
		.look(Color(0.42, 0.40, 0.44), Color(0.28, 0.27, 0.30), &"insect",
			{"eyes": 2, "limbs": 6, "pattern": &"plates"}) \
		.drop(&"chitin_plate", 1, 2, 0.7).drop(&"cobblestone", 2, 4, 0.5).value(26) \
		.describe("An armoured wedge that has to be levered open, not hit.")

	define(&"bone_stalker", "Bone Stalker") \
		.kind(FAM_GROUND, &"melee").acts(&"ambusher").rank(4) \
		.at([&"barren", &"midnight", &"ancient_ruins"]) \
		.stats(110.0, 22.0, 6.0, 12.0).body(Vector3(0.8, 1.3, 0.8)) \
		.senses(22.0, 44.0).melee(0.85, 7.0) \
		.look(Color(0.88, 0.86, 0.78), Color(0.34, 0.32, 0.30), &"biped",
			{"eyes": 2, "limbs": 4, "spikes": 5}) \
		.drop(&"bone", 2, 4, 0.9).drop(&"sharp_claw", 1, 2, 0.4).value(34) \
		.describe("Waits inside the wall. The cross-section is the only warning "
			+ "you get, and it is not much of one.") \
		.with_flags({&"phases_terrain": true})


# ==================================================================== flying
static func _flying() -> void:
	define(&"dusk_moth", "Dusk Moth") \
		.kind(FAM_FLYING, &"flyer").rank(0) \
		.at([&"forest", &"garden", &"jungle", &"mushroom"]) \
		.stats(20.0, 4.0, 4.0).body(Vector3(0.7, 0.6, 0.7)) \
		.senses(13.0, 26.0).melee(1.1, 3.0) \
		.look(Color(0.72, 0.64, 0.86), Color(0.44, 0.38, 0.58), &"winged",
			{"eyes": 2, "wings": 4, "glow": 0.15}) \
		.drop(&"plant_fibre", 1, 2, 0.4).drop(&"glow_dust", 1, 1, 0.2).value(6) \
		.describe("Drifts, then commits, badly.")

	define(&"talon_diver", "Talon Diver") \
		.kind(FAM_FLYING, &"flyer").rank(2) \
		.at([&"savannah", &"desert", &"barren", &"tundra"]) \
		.stats(48.0, 13.0, 6.6).body(Vector3(0.9, 0.8, 0.9)) \
		.senses(24.0, 44.0).melee(1.5, 9.0) \
		.look(Color(0.66, 0.48, 0.30), Color(0.90, 0.86, 0.74), &"winged",
			{"eyes": 2, "wings": 2, "beak": true}) \
		.drop(&"feather", 2, 4, 0.9).drop(&"sharp_claw", 1, 1, 0.35) \
		.drop(&"raw_meat", 1, 2, 0.5).value(15) \
		.describe("Circles once for range, then arrives all at once.")

	define(&"gasbag_floater", "Gasbag Floater") \
		.kind(FAM_FLYING, &"flyer").rank(1).at([&"toxic", &"swamp", &"alien"]) \
		.stats(34.0, 9.0, 2.0).body(Vector3(1.0, 1.0, 1.0)) \
		.senses(14.0, 24.0).melee(1.8, 4.0) \
		.elemental(Blocks.ELEM_POISON) \
		.look(Color(0.62, 0.78, 0.36), Color(0.40, 0.52, 0.22), &"blob",
			{"eyes": 3, "wings": 0, "glow": 0.2}) \
		.with_flags({&"explodes": 22.0}) \
		.drop(&"venom_gland", 1, 1, 0.5).drop(&"slime_glob", 1, 2, 0.6).value(12) \
		.describe("Bobs gently. Do not let it get close, and do not pop it near you.")

	define(&"ember_wisp", "Ember Wisp") \
		.kind(FAM_FLYING, &"flyer").rank(3).at([&"volcanic", &"scorched"]) \
		.stats(40.0, 15.0, 5.4).body(Vector3(0.6, 0.6, 0.6)) \
		.senses(18.0, 32.0).melee(1.0, 3.0) \
		.elemental(Blocks.ELEM_FIRE).resist({Blocks.ELEM_FIRE: 0.0}) \
		.look(Color(1.0, 0.62, 0.22), Color(0.86, 0.24, 0.10), &"blob",
			{"eyes": 1, "glow": 0.9}) \
		.drop(&"sulphur", 1, 2, 0.6).drop(&"cinder", 1, 2, 0.4).value(20) \
		.describe("A knot of fire that has decided you are fuel.")


# ==================================================================== ranged
static func _ranged() -> void:
	define(&"acid_spitter", "Acid Spitter") \
		.kind(FAM_RANGED, &"ranged").rank(2).at([&"toxic", &"swamp", &"jungle"]) \
		.stats(52.0, 11.0, 2.6, 9.0).body(Vector3(0.9, 0.8, 0.9)) \
		.senses(20.0, 34.0).melee(2.0, 3.0) \
		.elemental(Blocks.ELEM_POISON) \
		.look(Color(0.48, 0.66, 0.28), Color(0.72, 0.88, 0.24), &"insect",
			{"eyes": 4, "limbs": 4, "glow": 0.2}) \
		.with_flags({&"projectile": &"acid_glob", &"range": 16.0}) \
		.drop(&"venom_gland", 1, 2, 0.7).drop(&"chitin", 1, 2, 0.4).value(18) \
		.describe("Ranged, patient, and it leads its shots.")

	define(&"spore_turret", "Spore Pod") \
		.kind(FAM_RANGED, &"turret").rank(1) \
		.at([&"jungle", &"mushroom", &"toxic", &"swamp"]) \
		.stats(46.0, 8.0, 0.0, 0.0).body(Vector3(0.8, 1.0, 0.8)) \
		.senses(15.0, 15.0).melee(2.4, 0.0) \
		.elemental(Blocks.ELEM_POISON) \
		.look(Color(0.54, 0.72, 0.24), Color(0.34, 0.46, 0.16), &"plant",
			{"eyes": 0, "glow": 0.25}) \
		.with_flags({&"projectile": &"spore_burst", &"range": 14.0}) \
		.drop(&"plant_matter", 1, 3, 0.8).drop(&"venom_gland", 1, 1, 0.2).value(9) \
		.describe("Rooted, and it does not need to move to be a problem.")

	define(&"ice_lancer", "Ice Lancer") \
		.kind(FAM_RANGED, &"ranged").rank(4).at([&"tundra", &"snow", &"midnight"]) \
		.stats(88.0, 20.0, 3.8, 10.0).body(Vector3(0.8, 1.2, 0.8)) \
		.senses(26.0, 44.0).melee(1.8, 6.0) \
		.elemental(Blocks.ELEM_ICE).resist({Blocks.ELEM_ICE: 0.0}) \
		.look(Color(0.68, 0.88, 1.0), Color(0.30, 0.52, 0.78), &"biped",
			{"eyes": 2, "limbs": 2, "spikes": 4, "glow": 0.3}) \
		.with_flags({&"projectile": &"ice_shard", &"range": 20.0}) \
		.drop(&"ice_crystal", 1, 2, 0.7).drop(&"crystal_shard", 1, 3, 0.5).value(38) \
		.describe("Grows its ammunition as it walks.")

	define(&"mortar_bug", "Mortar Bug") \
		.kind(FAM_RANGED, &"ranged").rank(3).at([&"barren", &"volcanic", &"moon"]) \
		.stats(74.0, 24.0, 2.4, 8.0).body(Vector3(1.0, 0.9, 1.0)) \
		.senses(24.0, 40.0).melee(2.6, 10.0) \
		.look(Color(0.52, 0.46, 0.36), Color(0.34, 0.30, 0.24), &"insect",
			{"eyes": 2, "limbs": 6, "pattern": &"plates"}) \
		.with_flags({&"projectile": &"mortar_shell", &"range": 22.0, &"arcs": true}) \
		.drop(&"chitin_plate", 1, 1, 0.5).drop(&"gunpowder", 1, 2, 0.4).value(30) \
		.describe("Lobs. Mind where you are standing in a second's time.")


# =================================================================== special
static func _special() -> void:
	define(&"glow_jelly", "Glow Jelly") \
		.kind(FAM_AQUATIC, &"flyer").rank(1).at([&"ocean", &"bioluminescent"]) \
		.stats(42.0, 8.0, 2.4).body(Vector3(0.8, 0.9, 0.8)) \
		.senses(12.0, 22.0).melee(1.4, 3.0) \
		.elemental(Blocks.ELEM_ELECTRIC) \
		.look(Color(0.44, 0.86, 0.92), Color(0.22, 0.48, 0.62), &"blob",
			{"eyes": 0, "glow": 0.8, "tendrils": 5}) \
		.drop(&"glow_gland", 1, 1, 0.5).drop(&"slime_glob", 1, 2, 0.7).value(14) \
		.describe("Drifts through the water, gently electrocuting things.")

	define(&"chest_mimic", "Mimic") \
		.kind(FAM_SPECIAL, &"ambusher").rank(4) \
		.at([&"ancient_ruins", &"barren", &"midnight"]) \
		.stats(130.0, 26.0, 4.4, 11.0).body(Vector3(0.9, 0.8, 0.9)) \
		.senses(3.5, 22.0).melee(1.0, 9.0) \
		.look(Color(0.58, 0.40, 0.22), Color(0.72, 0.58, 0.26), &"chest",
			{"eyes": 4, "teeth": 8}) \
		.with_flags({&"disguised": true}) \
		.drop(&"pixels", 40, 120, 1.0).drop(&"sharp_claw", 1, 2, 0.6) \
		.drop(&"ancient_fragment", 1, 1, 0.2).value(60) \
		.describe("There is one way to tell it from a real chest, and it is to "
			+ "have already opened it.")

	define(&"plane_wraith", "Wraith") \
		.kind(FAM_SPECIAL, &"melee").acts(&"ambusher").rank(5) \
		.at([&"midnight", &"ancient_ruins", &"alien"]) \
		.stats(120.0, 30.0, 5.2, 10.0).body(Vector3(0.8, 1.4, 0.8)) \
		.senses(28.0, 60.0).melee(1.1, 4.0) \
		.elemental(Blocks.ELEM_COSMIC) \
		.resist({Blocks.ELEM_PHYSICAL: 0.5, Blocks.ELEM_COSMIC: 0.0}) \
		.look(Color(0.52, 0.44, 0.72), Color(0.24, 0.20, 0.36), &"wraith",
			{"eyes": 3, "glow": 0.5}) \
		.with_flags({&"phases_terrain": true, &"only_visible_in_cut": true}) \
		.drop(&"ectoplasm", 1, 2, 0.8).drop(&"void_residue", 1, 1, 0.25).value(70) \
		.describe("It is always in the room with you. Whether you can see it "
			+ "depends entirely on where the camera happens to be.")

	define(&"ooze_mother", "Ooze Mother") \
		.kind(FAM_SPECIAL, &"melee").rank(3).at([&"toxic", &"swamp", &"mushroom"]) \
		.stats(140.0, 14.0, 2.0, 8.0).body(Vector3(1.3, 1.1, 1.3)) \
		.senses(16.0, 28.0).melee(1.5, 5.0) \
		.elemental(Blocks.ELEM_POISON).resist({Blocks.ELEM_PHYSICAL: 0.7}) \
		.look(Color(0.46, 0.82, 0.44), Color(0.26, 0.52, 0.26), &"blob",
			{"eyes": 4, "glow": 0.2}) \
		.with_flags({&"splits": &"pebble_grub", &"split_count": 3}) \
		.drop(&"slime_glob", 3, 6, 1.0).drop(&"venom_gland", 1, 1, 0.4).value(32) \
		.describe("Hitting it makes more of it. Hit it anyway.")


# ==================================================================== bosses
static func _bosses() -> void:
	define(&"boss_stone_titan", "The Colossus of the Barrens") \
		.kind(FAM_BOSS, &"charger").rank(5).at([&"barren", &"desert", &"crystal"]) \
		.stats(1400.0, 34.0, 3.6, 12.0).body(Vector3(2.4, 3.2, 2.4)) \
		.senses(40.0, 200.0).melee(1.8, 22.0) \
		.resist({Blocks.ELEM_PHYSICAL: 0.5, Blocks.ELEM_ELECTRIC: 1.4}) \
		.look(Color(0.56, 0.52, 0.46), Color(0.90, 0.62, 0.22), &"titan",
			{"eyes": 1, "limbs": 4, "glow": 0.35, "pattern": &"plates"}) \
		.with_flags({&"charge_range": 22.0, &"charge_speed": 2.4,
			&"shockwave": 14.0}) \
		.drop(&"magma_maul", 1, 1, 1.0).drop(&"ancient_fragment", 2, 4, 1.0) \
		.drop(&"pixels", 900, 1500, 1.0).value(900) \
		.describe("It was part of the mountain until it decided otherwise.")

	define(&"boss_hive_queen", "The Hive Queen") \
		.kind(FAM_BOSS, &"ranged").rank(5).at([&"jungle", &"toxic", &"mushroom"]) \
		.stats(1100.0, 28.0, 4.6, 11.0).body(Vector3(2.0, 2.2, 2.0)) \
		.senses(44.0, 200.0).melee(1.2, 12.0) \
		.elemental(Blocks.ELEM_POISON).resist({Blocks.ELEM_POISON: 0.0}) \
		.look(Color(0.72, 0.86, 0.30), Color(0.32, 0.44, 0.16), &"insect",
			{"eyes": 8, "limbs": 6, "wings": 4, "glow": 0.3}) \
		.with_flags({&"projectile": &"spore_burst", &"range": 20.0,
			&"summons": &"acid_spitter", &"summon_count": 3}) \
		.drop(&"hivemind_scepter", 1, 1, 1.0).drop(&"venom_gland", 4, 8, 1.0) \
		.drop(&"pixels", 900, 1500, 1.0).value(900) \
		.describe("She does not fight you. The hive does that.")

	define(&"boss_magma_heart", "The Magma Heart") \
		.kind(FAM_BOSS, &"turret").rank(6).at([&"volcanic", &"scorched"]) \
		.stats(1800.0, 40.0, 0.0, 0.0).body(Vector3(2.6, 2.6, 2.6)) \
		.senses(50.0, 200.0).melee(1.4, 16.0) \
		.elemental(Blocks.ELEM_FIRE) \
		.resist({Blocks.ELEM_FIRE: 0.0, Blocks.ELEM_ICE: 2.0}) \
		.look(Color(1.0, 0.48, 0.14), Color(0.30, 0.10, 0.08), &"titan",
			{"eyes": 5, "glow": 1.0}) \
		.with_flags({&"projectile": &"fireball", &"range": 26.0, &"burst": 4}) \
		.drop(&"heart_of_the_forge", 1, 1, 1.0).drop(&"core_fragment", 3, 6, 1.0) \
		.drop(&"pixels", 1600, 2600, 1.0).value(1800) \
		.describe("At the bottom of the shaft, and it has been waiting.")

	define(&"boss_fourfold", "The Fourfold") \
		.kind(FAM_BOSS, &"ambusher").rank(6).at([&"ancient_ruins", &"midnight"]) \
		.stats(1600.0, 38.0, 6.0, 13.0).body(Vector3(1.8, 2.6, 1.8)) \
		.senses(60.0, 200.0).melee(0.9, 10.0) \
		.elemental(Blocks.ELEM_COSMIC) \
		.resist({Blocks.ELEM_PHYSICAL: 0.6, Blocks.ELEM_COSMIC: 0.0}) \
		.look(Color(0.62, 0.50, 0.88), Color(0.20, 0.16, 0.30), &"wraith",
			{"eyes": 4, "glow": 0.8}) \
		.with_flags({&"phases_terrain": true, &"only_visible_in_cut": true,
			&"blinks": true}) \
		.drop(&"null_sequence", 1, 1, 1.0).drop(&"ancient_essence", 2, 3, 1.0) \
		.drop(&"pixels", 1600, 2600, 1.0).value(1800) \
		.describe("One creature standing in four places. Turning the camera does "
			+ "not reveal it — it moves to wherever you are not looking.")
