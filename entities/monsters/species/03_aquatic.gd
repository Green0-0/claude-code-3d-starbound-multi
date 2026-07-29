## Aquatic family: swimmers, jellies, and the Abyss Eel — which uses the water
## behind the plane you are swimming in as cover.
extends RefCounted


static func register_all(_db) -> void:
	MobSpeciesDB.define(&"reef_darter", "Reef Darter") \
		.kind(MobSpecies.FAM_AQUATIC, MobSpecies.LOCO_SWIM, &"aquatic") \
		.threat(1).at([&"ocean", &"bioluminescent"]).aquatic() \
		.stats(30.0, 7.0, 5.5, 0.0).body(Vector3(0.8, 0.6, 0.8)) \
		.senses(14.0, 26.0, 3).melee(1.4, 1.0, 0.25) \
		.look(Color(0.35, 0.62, 0.7), Color(0.85, 0.75, 0.4), &"serpent",
			{"eyes": 2, "limbs": 0, "tail": true, "pattern": &"stripes"}) \
		.packs(3, 6).drop(&"raw_meat", 1, 2, 0.7).worth(6) \
		.describe("Schools tight. Bites in numbers.")

	MobSpeciesDB.define(&"brine_crab", "Brine Crab") \
		.kind(MobSpecies.FAM_AQUATIC, MobSpecies.LOCO_AMPHIBIOUS, &"melee").acts(&"armoured") \
		.threat(2).at([&"ocean", &"barren", &"swamp"]).aquatic() \
		.stats(96.0, 13.0, 3.0, 8.0).body(Vector3(1.1, 0.7, 1.1), 0.7) \
		.senses(12.0, 22.0, 2).melee(1.6, 1.4, 0.4).plated(3.0) \
		.resist({Const.ELEM_PHYSICAL: 0.5, Const.ELEM_ICE: 0.6}) \
		.look(Color(0.72, 0.35, 0.3), Color(0.45, 0.2, 0.18), &"crab",
			{"eyes": 2, "limbs": 4, "spikes": 2, "pattern": &"plates"}) \
		.drop(&"raw_meat", 1, 3, 0.85).drop(&"chitin", 1, 2, 0.6).worth(14) \
		.describe("Armoured sideways. Claw first, question never.")

	MobSpeciesDB.define(&"glow_jelly", "Glow Jelly") \
		.kind(MobSpecies.FAM_AQUATIC, MobSpecies.LOCO_SWIM, &"aquatic").acts(&"shocker") \
		.threat(2).at([&"ocean", &"bioluminescent", &"alien"]).aquatic() \
		.stats(48.0, 11.0, 2.2, 0.0).body(Vector3(0.9, 1.1, 0.9), 0.5) \
		.senses(11.0, 20.0, 3).melee(2.0, 1.5, 0.3, 2.0) \
		.elemental(Const.ELEM_ELECTRIC).resist({Const.ELEM_ELECTRIC: 0.0, Const.ELEM_PHYSICAL: 0.7}) \
		.look(Color(0.55, 0.85, 0.9), Color(0.75, 0.5, 0.95), &"jelly",
			{"eyes": 0, "limbs": 0, "glow": 0.55}) \
		.drop(&"glow_gland", 1, 2, 0.8).worth(15) \
		.describe("Pulses. Everything within the pulse regrets it.")

	MobSpeciesDB.define(&"bog_serpent", "Bog Serpent") \
		.kind(MobSpecies.FAM_AQUATIC, MobSpecies.LOCO_AMPHIBIOUS, &"aquatic") \
		.threat(3).at([&"swamp", &"jungle", &"ocean", &"toxic"]).aquatic() \
		.stats(110.0, 20.0, 5.0, 10.0).body(Vector3(1.4, 0.8, 1.4), 0.4) \
		.senses(20.0, 38.0, 4).melee(2.2, 1.2, 0.35) \
		.elemental(Const.ELEM_POISON).resist({Const.ELEM_POISON: 0.2}) \
		.look(Color(0.3, 0.45, 0.3), Color(0.6, 0.62, 0.28), &"serpent",
			{"eyes": 2, "limbs": 0, "tail": true, "spikes": 3, "pattern": &"spots"}) \
		.drop(&"raw_meat", 2, 3, 0.8).drop(&"monster_hide", 1, 2, 0.6) \
		.drop(&"venom_sac", 1, 1, 0.4).worth(27) \
		.describe("Longer than the pool it lives in should allow.")

	MobSpeciesDB.define(&"drift_medusa", "Drift Medusa") \
		.kind(MobSpecies.FAM_AQUATIC, MobSpecies.LOCO_SWIM, &"ranged") \
		.threat(3).at([&"ocean", &"midnight", &"alien"]).aquatic() \
		.stats(84.0, 14.0, 2.6, 0.0).body(Vector3(1.2, 1.4, 1.2), 0.6) \
		.senses(20.0, 36.0, 4).shoots(&"frost_splinter", 14.0, 2.1, 12.0) \
		.elemental(Const.ELEM_ICE).resist({Const.ELEM_ICE: 0.2}) \
		.look(Color(0.42, 0.4, 0.68), Color(0.7, 0.75, 0.9), &"jelly",
			{"eyes": 4, "limbs": 0, "glow": 0.3}) \
		.with_flags({&"min_range": 6.0}) \
		.drop(&"glow_gland", 1, 2, 0.6).drop(&"ice_shard", 1, 2, 0.4).worth(25) \
		.describe("Deep-water bell that spits cold at anything with a heartbeat.")

	## Perspective monster: hangs in the water one layer behind you and strikes
	## sideways out of the murk.
	MobSpeciesDB.define(&"abyss_eel", "Abyss Eel") \
		.kind(MobSpecies.FAM_AQUATIC, MobSpecies.LOCO_SWIM, &"ambusher").acts(&"eel_ambush") \
		.threat(3).at([&"ocean", &"midnight"]).aquatic() \
		.stats(98.0, 28.0, 6.5, 0.0).body(Vector3(1.3, 0.7, 1.3), 0.5) \
		.senses(22.0, 44.0, 4).melee(2.2, 1.6, 0.2) \
		.resist({Const.ELEM_PHYSICAL: 0.8}) \
		.look(Color(0.16, 0.2, 0.3), Color(0.5, 0.85, 0.75), &"serpent",
			{"eyes": 2, "limbs": 0, "tail": true, "glow": 0.25}) \
		.with_flags({&"layer_cooldown": 0.1}) \
		.subterranean() \
		.drop(&"raw_meat", 2, 3, 0.8).drop(&"glow_gland", 1, 1, 0.35).worth(30) \
		.hard_to_catch(1.8) \
		.describe("You will see the layer it came from only once.")
