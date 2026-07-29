## Data definitions for the four bosses. Registered into the same bestiary as
## everything else, but tagged `FAM_BOSS` so the random spawn director will
## never pick one — bosses are placed by structures, quests or `spawn_boss`.
extends RefCounted


static func register_all(_db) -> void:
	MobSpeciesDB.define(&"boss_stone_titan", "The Colossus of the Barrens") \
		.kind(MobSpecies.FAM_BOSS, MobSpecies.LOCO_WALK, &"boss") \
		.threat(3).at([&"barren", &"desert", &"moon", &"scorched"]) \
		.stats(1400.0, 30.0, 3.2, 12.0).body(Vector3(2.6, 4.2, 2.6), 1.0) \
		.senses(40.0, 200.0, 4, 60.0).melee(4.0, 2.0, 0.9).plated(8.0) \
		.resist({Const.ELEM_PHYSICAL: 0.7, Const.ELEM_ELECTRIC: 1.3}) \
		.look(Color(0.5, 0.47, 0.44), Color(0.9, 0.55, 0.2), &"humanoid",
			{"eyes": 2, "limbs": 4, "spikes": 5, "glow": 0.15, "pattern": &"plates",
			"scale": 2.6}) \
		.with_flags({&"uncapturable": true, &"jump_blocks": 2, &"arena_radius": 24.0}) \
		.drop(&"ancient_relic", 1, 2, 1.0).drop(&"crystal_shard", 3, 6, 0.9).worth(400) \
		.describe("A mountain that was told to stand up.")

	MobSpeciesDB.define(&"boss_hive_queen", "The Hive Queen") \
		.kind(MobSpecies.FAM_BOSS, MobSpecies.LOCO_FLY, &"boss") \
		.threat(3).at([&"jungle", &"mushroom", &"swamp", &"toxic"]) \
		.stats(1100.0, 26.0, 5.4, 0.0).body(Vector3(2.4, 2.6, 2.4), 0.8) \
		.senses(44.0, 200.0, 5, 60.0).shoots(&"poison_glob", 20.0, 1.5, 20.0) \
		.elemental(Const.ELEM_POISON).resist({Const.ELEM_POISON: 0.0, Const.ELEM_FIRE: 1.5}) \
		.look(Color(0.55, 0.35, 0.6), Color(0.85, 0.85, 0.35), &"insect",
			{"eyes": 6, "limbs": 4, "wings": 2, "tail": true, "spikes": 4,
			"glow": 0.25, "scale": 2.2}) \
		.with_flags({&"uncapturable": true, &"arena_radius": 26.0, &"min_range": 6.0}) \
		.drop(&"venom_sac", 4, 8, 1.0).drop(&"ancient_relic", 1, 1, 0.5).worth(380) \
		.describe("Every gnat on this planet is a limb of hers.")

	## The perspective boss. It does not live in the world so much as in one of
	## the four ways of looking at it.
	MobSpeciesDB.define(&"boss_fourfold", "The Fourfold") \
		.kind(MobSpecies.FAM_BOSS, MobSpecies.LOCO_HOVER, &"boss") \
		.threat(4).at([&"midnight", &"ruins", &"alien", &"moon"]) \
		.stats(1600.0, 34.0, 6.0, 0.0).body(Vector3(2.0, 3.4, 2.0), 1.0) \
		.senses(60.0, 400.0, 12, 90.0).shoots(&"echo_dart", 24.0, 1.2, 26.0) \
		.elemental(Const.ELEM_COSMIC) \
		.resist({Const.ELEM_COSMIC: 0.0, Const.ELEM_PHYSICAL: 0.6}) \
		.look(Color(0.24, 0.18, 0.4), Color(0.8, 0.5, 1.0), &"humanoid",
			{"eyes": 4, "limbs": 2, "wings": 2, "tail": true, "spikes": 6,
			"glow": 0.7, "scale": 2.4}) \
		.with_flags({&"uncapturable": true, &"arena_radius": 30.0, &"layer_cooldown": 0.05}) \
		.drop(&"void_dust", 6, 12, 1.0).drop(&"ancient_relic", 2, 3, 1.0).worth(600) \
		.describe("It is standing in the North. Turn, and it is standing in the West.")

	MobSpeciesDB.define(&"boss_magma_heart", "The Magma Heart") \
		.kind(MobSpecies.FAM_BOSS, MobSpecies.LOCO_STATIC, &"boss") \
		.threat(4).at([&"volcanic", &"scorched"]) \
		.stats(1900.0, 28.0, 0.0, 0.0).body(Vector3(3.0, 3.0, 3.0), 1.0) \
		.senses(50.0, 400.0, 6, 80.0).shoots(&"fireball", 22.0, 1.4, 18.0) \
		.elemental(Const.ELEM_FIRE) \
		.resist({Const.ELEM_FIRE: 0.0, Const.ELEM_ICE: 1.8, Const.ELEM_PHYSICAL: 0.65}) \
		.look(Color(0.9, 0.35, 0.1), Color(0.25, 0.12, 0.12), &"orb",
			{"eyes": 1, "limbs": 0, "spikes": 6, "glow": 0.85, "scale": 2.8}) \
		.with_flags({&"uncapturable": true, &"arena_radius": 22.0}) \
		.drop(&"ember_core", 6, 10, 1.0).drop(&"ancient_relic", 1, 2, 0.8).worth(520) \
		.describe("The planet's furnace, and it has noticed you.")
