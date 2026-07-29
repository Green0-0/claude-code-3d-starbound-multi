## Ranged family: rooted turret plants, artillery bugs and casters — including
## the Hex Caster, which fights you from the layer behind the wall.
extends RefCounted


static func register_all(_db) -> void:
	MobSpeciesDB.define(&"spore_turret", "Spore Pod") \
		.kind(MobSpecies.FAM_RANGED, MobSpecies.LOCO_STATIC, &"turret").acts(&"turret") \
		.threat(1).at([&"mushroom", &"jungle", &"garden", &"swamp", &"bioluminescent"]) \
		.stats(40.0, 8.0, 0.0, 0.0).body(Vector3(0.9, 1.2, 0.9), 1.0) \
		.senses(15.0, 15.0, 3).shoots(&"poison_glob", 12.0, 1.7, 12.0) \
		.elemental(Const.ELEM_POISON).resist({Const.ELEM_POISON: 0.0, Const.ELEM_FIRE: 2.0}) \
		.look(Color(0.75, 0.4, 0.55), Color(0.35, 0.5, 0.3), &"plant",
			{"eyes": 1, "limbs": 0, "glow": 0.15, "pattern": &"spots"}) \
		.drop(&"spore_sac", 1, 3, 0.85).worth(8) \
		.with_flags({&"uncapturable": true}) \
		.describe("It cannot chase you. It does not need to.")

	MobSpeciesDB.define(&"flak_bloom", "Flak Bloom") \
		.kind(MobSpecies.FAM_RANGED, MobSpecies.LOCO_STATIC, &"turret").acts(&"turret") \
		.threat(2).at([&"toxic", &"alien", &"crystal", &"volcanic"]) \
		.stats(64.0, 12.0, 0.0, 0.0).body(Vector3(1.0, 1.4, 1.0), 1.0) \
		.senses(18.0, 18.0, 4).shoots(&"pellet", 15.0, 2.4, 16.0) \
		.resist({Const.ELEM_PHYSICAL: 0.7}) \
		.look(Color(0.85, 0.75, 0.3), Color(0.35, 0.45, 0.25), &"plant",
			{"eyes": 3, "limbs": 0, "spikes": 5, "glow": 0.2}) \
		.drop(&"spore_sac", 1, 2, 0.6).drop(&"venom_sac", 1, 1, 0.3).worth(16) \
		.with_flags({&"uncapturable": true}) \
		.describe("Fires a spread wide enough to cover two layers.")

	MobSpeciesDB.define(&"mortar_bug", "Mortar Bug") \
		.kind(MobSpecies.FAM_RANGED, MobSpecies.LOCO_WALK, &"artillery").acts(&"artillery") \
		.threat(3).at([&"barren", &"scorched", &"volcanic", &"moon", &"ruins"]) \
		.stats(86.0, 22.0, 2.8, 8.0).body(Vector3(1.1, 0.9, 1.1), 0.35) \
		.senses(30.0, 46.0, 4).shoots(&"grenade", 26.0, 3.0, 15.0) \
		.elemental(Const.ELEM_FIRE).resist({Const.ELEM_FIRE: 0.4}) \
		.look(Color(0.5, 0.42, 0.3), Color(0.72, 0.35, 0.15), &"beetle",
			{"eyes": 4, "limbs": 4, "spikes": 3, "pattern": &"plates"}) \
		.with_flags({&"min_range": 8.0}) \
		.drop(&"chitin", 2, 3, 0.7).drop(&"ember_core", 1, 1, 0.3).worth(28) \
		.describe("Lobs over the terrain between you. Terrain is not cover.")

	MobSpeciesDB.define(&"ice_lancer", "Ice Lancer") \
		.kind(MobSpecies.FAM_RANGED, MobSpecies.LOCO_WALK, &"ranged") \
		.threat(3).at([&"snow", &"tundra", &"crystal"]) \
		.stats(78.0, 18.0, 3.6, 10.0).body(Vector3(0.9, 1.5, 0.9)) \
		.senses(24.0, 40.0, 4).shoots(&"ice_shard", 18.0, 1.8, 24.0) \
		.elemental(Const.ELEM_ICE).resist({Const.ELEM_ICE: 0.0, Const.ELEM_FIRE: 1.8}) \
		.look(Color(0.72, 0.88, 0.98), Color(0.34, 0.5, 0.72), &"humanoid",
			{"eyes": 2, "limbs": 4, "spikes": 4, "glow": 0.2}) \
		.with_flags({&"min_range": 6.0}) \
		.drop(&"ice_shard", 2, 4, 0.85).worth(26) \
		.describe("Grows its ammunition out of its own arm.")

	## Perspective monster: blinks a layer sideways whenever you get close, and
	## shoots through the gap.
	MobSpeciesDB.define(&"hex_caster", "Hex Caster") \
		.kind(MobSpecies.FAM_RANGED, MobSpecies.LOCO_WALK, &"ranged").acts(&"blinker") \
		.threat(4).at([&"ruins", &"midnight", &"alien", &"moon"]) \
		.stats(102.0, 24.0, 3.4, 10.0).body(Vector3(0.9, 1.7, 0.9), 0.5) \
		.senses(28.0, 48.0, 5).shoots(&"echo_dart", 20.0, 1.6, 22.0) \
		.elemental(Const.ELEM_COSMIC).resist({Const.ELEM_COSMIC: 0.1, Const.ELEM_PHYSICAL: 0.85}) \
		.look(Color(0.32, 0.24, 0.45), Color(0.8, 0.55, 1.0), &"humanoid",
			{"eyes": 3, "limbs": 2, "tail": false, "glow": 0.4, "spikes": 3}) \
		.with_flags({&"blink_cooldown": 2.4, &"layer_cooldown": 0.12, &"min_range": 7.0}) \
		.drop(&"void_dust", 1, 2, 0.6).drop(&"ancient_relic", 1, 1, 0.08).worth(42) \
		.hard_to_catch(2.2) \
		.describe("Duck behind a wall and it simply steps behind it with you.")
