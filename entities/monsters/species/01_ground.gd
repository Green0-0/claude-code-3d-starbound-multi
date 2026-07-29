## Ground family: crawlers, chargers, armoured beetles, spitters, leapers,
## burrowers and the three perspective predators that hunt you sideways through
## the depth axis.
extends RefCounted


static func register_all(_db) -> void:
	# ---------------------------------------------------------------- crawlers
	MobSpeciesDB.define(&"pebble_grub", "Pebble Grub") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee") \
		.threat(0).at([&"forest", &"garden", &"mushroom", &"bioluminescent"]) \
		.stats(24.0, 4.0, 2.6, 8.0).body(Vector3(0.7, 0.6, 0.7)) \
		.senses(9.0, 18.0, 2, 12.0).melee(1.3, 1.4, 0.3) \
		.look(Color(0.55, 0.62, 0.35), Color(0.36, 0.42, 0.22), &"worm",
			{"eyes": 2, "limbs": 0, "tail": false, "pattern": &"plates"}) \
		.drop(&"slime", 1, 2, 0.7).drop(&"raw_meat", 1, 1, 0.25).worth(3) \
		.describe("A slow ring of chewing muscle. Mostly harmless, rarely alone.") \
		.packs(2, 4)

	MobSpeciesDB.define(&"thorn_creeper", "Thorn Creeper") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee") \
		.threat(1).at([&"forest", &"jungle", &"garden", &"swamp"]) \
		.stats(38.0, 7.0, 3.6, 10.0).body(Vector3(0.8, 0.8, 0.8)) \
		.senses(12.0, 24.0, 2).melee(1.5, 1.2, 0.32, 2.0) \
		.look(Color(0.32, 0.5, 0.24), Color(0.5, 0.42, 0.2), &"insect",
			{"eyes": 4, "limbs": 4, "spikes": 3, "pattern": &"stripes"}) \
		.drop(&"raw_meat", 1, 2, 0.6).drop(&"chitin", 1, 2, 0.5).worth(6) \
		.describe("Barbed and territorial. It will follow you between layers.")

	MobSpeciesDB.define(&"crystal_skitter", "Crystal Skitter") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee") \
		.threat(3).at([&"crystal", &"moon", &"barren"]) \
		.stats(70.0, 14.0, 5.4, 13.0).body(Vector3(0.8, 0.9, 0.8)) \
		.senses(15.0, 30.0, 3).melee(1.6, 0.9, 0.3) \
		.elemental(Const.ELEM_ELECTRIC).resist({Const.ELEM_ELECTRIC: 0.2, Const.ELEM_PHYSICAL: 0.8}) \
		.look(Color(0.55, 0.8, 0.95), Color(0.3, 0.45, 0.75), &"insect",
			{"eyes": 6, "limbs": 4, "spikes": 4, "glow": 0.25, "pattern": &"speckle"}) \
		.drop(&"crystal_shard", 1, 3, 0.8).drop(&"chitin", 1, 2, 0.4).worth(18) \
		.describe("Facets for eyes. It hears footsteps through the stone.") \
		.packs(2, 3)

	MobSpeciesDB.define(&"magma_crawler", "Magma Crawler") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee") \
		.threat(3).at([&"volcanic", &"scorched"]) \
		.stats(95.0, 17.0, 3.4, 10.0).body(Vector3(1.0, 0.8, 1.0), 0.3) \
		.senses(14.0, 26.0, 2).melee(1.7, 1.3, 0.4, 4.0) \
		.elemental(Const.ELEM_FIRE).resist({Const.ELEM_FIRE: 0.0, Const.ELEM_ICE: 1.8}) \
		.look(Color(0.85, 0.32, 0.12), Color(0.25, 0.12, 0.1), &"worm",
			{"eyes": 2, "limbs": 4, "glow": 0.35, "pattern": &"plates"}) \
		.drop(&"ember_core", 1, 2, 0.5).drop(&"chitin", 1, 2, 0.5).worth(22) \
		.describe("Molten under a crust of slag. Douse it, then hit it.")

	# ---------------------------------------------------------------- chargers
	MobSpeciesDB.define(&"dune_charger", "Dune Charger") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee").acts(&"charger") \
		.threat(2).at([&"desert", &"savannah", &"barren", &"scorched"]) \
		.stats(80.0, 15.0, 4.2, 11.0).body(Vector3(1.2, 1.1, 1.2), 0.45) \
		.senses(18.0, 34.0, 2).melee(1.8, 1.4, 0.4) \
		.look(Color(0.78, 0.62, 0.34), Color(0.5, 0.36, 0.2), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true, "spikes": 2, "pattern": &"stripes"}) \
		.with_flags({&"charge_range": 13.0, &"charge_speed": 2.6, &"charge_time": 1.5,
			&"charge_cooldown": 3.2, &"reckless": true}) \
		.drop(&"raw_meat", 2, 3, 0.9).drop(&"monster_hide", 1, 2, 0.6).worth(14) \
		.describe("Lowers its head, and then the horizon comes to you.")

	MobSpeciesDB.define(&"frost_hound", "Frost Hound") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"pack").acts(&"pack_hunter") \
		.threat(2).at([&"snow", &"tundra", &"midnight"]) \
		.stats(62.0, 12.0, 5.6, 12.5).body(Vector3(0.9, 0.9, 0.9)) \
		.senses(20.0, 40.0, 3, 26.0).melee(1.6, 0.9, 0.28) \
		.elemental(Const.ELEM_ICE).resist({Const.ELEM_ICE: 0.15, Const.ELEM_FIRE: 1.5}) \
		.look(Color(0.78, 0.86, 0.95), Color(0.42, 0.55, 0.72), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true, "pattern": &"spots"}) \
		.packs(3, 5).drop(&"raw_meat", 1, 2, 0.8).drop(&"monster_hide", 1, 2, 0.7) \
		.drop(&"ice_shard", 1, 1, 0.3).worth(15) \
		.describe("Hunts in fives. One howl and the whole slope wakes up.")

	# --------------------------------------------------------- armoured beetles
	MobSpeciesDB.define(&"boulder_beetle", "Boulder Beetle") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee").acts(&"armoured") \
		.threat(2).at([&"barren", &"moon", &"crystal", &"desert", &"ruins"]) \
		.stats(120.0, 11.0, 2.4, 8.0).body(Vector3(1.1, 0.8, 1.1), 0.8) \
		.senses(11.0, 22.0, 2).melee(1.5, 1.6, 0.5).plated(4.0) \
		.resist({Const.ELEM_PHYSICAL: 0.55, Const.ELEM_ELECTRIC: 1.6}) \
		.look(Color(0.45, 0.42, 0.4), Color(0.28, 0.26, 0.25), &"beetle",
			{"eyes": 2, "limbs": 4, "spikes": 3, "pattern": &"plates"}) \
		.with_flags({&"jump_blocks": 1}) \
		.drop(&"chitin", 2, 4, 0.9).drop(&"cobblestone", 1, 3, 0.4).worth(16) \
		.describe("Curls up when struck hard. Wait it out or hit it with lightning.")

	MobSpeciesDB.define(&"rust_tick", "Rust Tick") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee").acts(&"armoured") \
		.threat(3).at([&"ruins", &"barren", &"toxic"]) \
		.stats(105.0, 16.0, 3.8, 9.5).body(Vector3(0.9, 0.7, 0.9), 0.6) \
		.senses(14.0, 26.0, 3).melee(1.5, 1.1, 0.35).plated(3.0) \
		.resist({Const.ELEM_PHYSICAL: 0.6, Const.ELEM_POISON: 0.4}) \
		.look(Color(0.6, 0.38, 0.22), Color(0.32, 0.24, 0.18), &"beetle",
			{"eyes": 4, "limbs": 4, "pattern": &"speckle"}) \
		.drop(&"chitin", 2, 3, 0.8).drop(&"circuit", 1, 1, 0.15).worth(20) \
		.describe("Eats metal. Found wherever a structure is losing an argument with time.")

	# ----------------------------------------------------------------- spitters
	MobSpeciesDB.define(&"acid_spitter", "Acid Spitter") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"ranged") \
		.threat(2).at([&"toxic", &"swamp", &"jungle"]) \
		.stats(52.0, 11.0, 3.2, 10.0).body(Vector3(0.9, 0.9, 0.9)) \
		.senses(18.0, 30.0, 3).shoots(&"poison_glob", 13.0, 1.9, 15.0) \
		.elemental(Const.ELEM_POISON).resist({Const.ELEM_POISON: 0.0}) \
		.look(Color(0.5, 0.72, 0.28), Color(0.28, 0.42, 0.16), &"blob",
			{"eyes": 3, "limbs": 2, "glow": 0.12, "pattern": &"spots"}) \
		.with_flags({&"min_range": 5.0}) \
		.drop(&"venom_sac", 1, 2, 0.6).drop(&"slime", 1, 3, 0.7).worth(13) \
		.describe("Keeps its distance and dissolves yours.")

	MobSpeciesDB.define(&"tar_spitter", "Tar Spitter") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"ranged") \
		.threat(3).at([&"swamp", &"volcanic", &"scorched"]) \
		.stats(74.0, 14.0, 3.0, 9.0).body(Vector3(1.0, 1.0, 1.0), 0.25) \
		.senses(19.0, 32.0, 3).shoots(&"poison_glob", 15.0, 2.2, 13.0) \
		.resist({Const.ELEM_FIRE: 0.5}) \
		.look(Color(0.2, 0.19, 0.22), Color(0.4, 0.34, 0.2), &"blob",
			{"eyes": 2, "limbs": 2, "pattern": &"none"}) \
		.with_flags({&"min_range": 6.0}) \
		.drop(&"slime", 2, 3, 0.8).worth(17) \
		.describe("Gums your boots to the floor, then takes its time.")

	# ------------------------------------------------------------------ leapers
	MobSpeciesDB.define(&"chasm_leaper", "Chasm Leaper") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"melee").acts(&"leaper") \
		.threat(3).at([&"ruins", &"tundra", &"midnight", &"barren", &"moon"]) \
		.stats(78.0, 16.0, 4.6, 15.0).body(Vector3(0.9, 1.1, 0.9)) \
		.senses(20.0, 36.0, 4).melee(1.6, 1.1, 0.3) \
		.look(Color(0.38, 0.34, 0.5), Color(0.22, 0.2, 0.32), &"quadruped",
			{"eyes": 4, "limbs": 4, "tail": true, "spikes": 2}) \
		.with_flags({&"leap_cooldown": 2.2, &"jump_blocks": 3, &"max_fall": 12,
			&"reckless": true}) \
		.drop(&"raw_meat", 1, 2, 0.7).drop(&"bone_fragment", 1, 2, 0.5).worth(21) \
		.describe("Crosses a gap you cannot — and changes layer at the top of the arc.")

	# ---------------------------------------------------------------- burrowers
	## Perspective monster: it waits under the sand and surfaces in whichever
	## plane you flip to.
	MobSpeciesDB.define(&"sand_burrower", "Sand Burrower") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_BURROW, &"melee").acts(&"burrower") \
		.threat(2).at([&"desert", &"scorched", &"barren", &"savannah"]) \
		.stats(86.0, 18.0, 4.0, 10.0).body(Vector3(1.0, 1.2, 1.0), 0.5) \
		.senses(24.0, 44.0, 5, 34.0).melee(2.0, 1.3, 0.45) \
		.look(Color(0.72, 0.58, 0.36), Color(0.86, 0.4, 0.35), &"worm",
			{"eyes": 0, "limbs": 0, "spikes": 5, "pattern": &"plates"}) \
		.with_flags({&"layer_cooldown": 0.2}) \
		.drop(&"raw_meat", 2, 3, 0.8).drop(&"chitin", 1, 2, 0.5).worth(19) \
		.hard_to_catch(1.4) \
		.describe("Blind, deaf to everything but footfalls, and it knows where you turned.")

	## Perspective monster: it only moves while it is *not* on screen.
	MobSpeciesDB.define(&"bone_stalker", "Bone Stalker") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"stalker").acts(&"stalker") \
		.threat(4).at([&"midnight", &"ruins", &"moon", &"barren"]) \
		.stats(130.0, 26.0, 7.5, 12.0).body(Vector3(0.9, 1.7, 0.9), 0.7) \
		.senses(30.0, 90.0, 6, 40.0).melee(2.0, 1.0, 0.25) \
		.resist({Const.ELEM_PHYSICAL: 0.75, Const.ELEM_COSMIC: 1.4}) \
		.look(Color(0.86, 0.85, 0.8), Color(0.35, 0.34, 0.4), &"humanoid",
			{"eyes": 2, "limbs": 4, "spikes": 3, "glow": 0.1}) \
		.with_flags({&"layer_cooldown": 0.15, &"no_layer_shift": false}) \
		.only_at_night() \
		.drop(&"bone_fragment", 2, 4, 0.9).drop(&"void_dust", 1, 1, 0.25).worth(40) \
		.hard_to_catch(2.5) \
		.describe("Keep it in your plane and it will not move. Blink, flip, and it is closer.")

	## Perspective monster: sits one layer back until you walk past it.
	MobSpeciesDB.define(&"mire_lurker", "Mire Lurker") \
		.kind(MobSpecies.FAM_GROUND, MobSpecies.LOCO_WALK, &"ambusher").acts(&"ambusher") \
		.threat(2).at([&"swamp", &"jungle", &"toxic", &"mushroom"]) \
		.stats(72.0, 20.0, 4.4, 12.0).body(Vector3(1.0, 1.0, 1.0)) \
		.senses(16.0, 30.0, 3).melee(2.0, 1.5, 0.2) \
		.elemental(Const.ELEM_POISON) \
		.look(Color(0.28, 0.36, 0.26), Color(0.16, 0.22, 0.18), &"blob",
			{"eyes": 6, "limbs": 2, "spikes": 4, "pattern": &"spots"}) \
		.with_flags({&"layer_cooldown": 0.1}) \
		.drop(&"venom_sac", 1, 2, 0.55).drop(&"slime", 1, 3, 0.7).worth(16) \
		.describe("Perfectly still, one layer behind the reeds, for as long as it takes.")
