## Passive critters. They flee, they drop food, and they are the reason a planet
## feels inhabited rather than merely hostile. Every one of them is capturable.
extends RefCounted


static func _critter(id: StringName, name: String) -> MobSpecies:
	return MobSpeciesDB.define(id, name) \
		.kind(MobSpecies.FAM_CRITTER, MobSpecies.LOCO_WALK, &"passive").acts(&"skittish") \
		.threat(0).stats(16.0, 0.0, 4.4, 10.0).body(Vector3(0.6, 0.6, 0.6)) \
		.senses(11.0, 22.0, 2, 16.0).melee(1.0, 2.0, 0.3) \
		.with_flags({&"timid": 1.0, &"flee_range": 7.0, &"reckless": false}) \
		.weight(1.6).worth(2)


static func register_all(_db) -> void:
	_critter(&"meadow_hopper", "Meadow Hopper") \
		.at([&"forest", &"garden", &"savannah", &"jungle"]) \
		.look(Color(0.72, 0.6, 0.4), Color(0.9, 0.86, 0.78), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true}) \
		.drop(&"raw_meat", 1, 2, 0.9).drop(&"monster_hide", 1, 1, 0.4) \
		.describe("Two bounds and a hedge, and it is gone.")

	_critter(&"snow_puffin", "Snow Puffin") \
		.at([&"snow", &"tundra"]) \
		.stats(18.0, 0.0, 3.8, 9.0) \
		.look(Color(0.94, 0.95, 0.98), Color(0.85, 0.55, 0.2), &"bird",
			{"eyes": 2, "limbs": 2, "wings": 2}) \
		.drop(&"raw_meat", 1, 2, 0.9).drop(&"feather", 1, 3, 0.7) \
		.describe("Round, indignant, delicious.")

	_critter(&"dune_scarab", "Dune Scarab") \
		.at([&"desert", &"barren", &"scorched", &"savannah"]) \
		.look(Color(0.68, 0.58, 0.3), Color(0.4, 0.33, 0.18), &"beetle",
			{"eyes": 2, "limbs": 4, "pattern": &"plates"}) \
		.drop(&"chitin", 1, 2, 0.8).drop(&"raw_meat", 1, 1, 0.3) \
		.describe("Rolls something it would rather you did not look at.")

	_critter(&"glowbug", "Glowbug") \
		.kind(MobSpecies.FAM_CRITTER, MobSpecies.LOCO_FLY, &"passive").acts(&"skittish") \
		.at([&"bioluminescent", &"mushroom", &"crystal", &"midnight", &"forest"]) \
		.stats(10.0, 0.0, 3.4, 0.0).body(Vector3(0.4, 0.4, 0.4)) \
		.look(Color(0.85, 0.95, 0.5), Color(0.5, 0.7, 0.3), &"insect",
			{"eyes": 2, "limbs": 2, "wings": 2, "glow": 0.7, "scale": 0.7}) \
		.drop(&"glow_gland", 1, 1, 0.85).only_at_night() \
		.describe("Free light, if you are quick.")

	_critter(&"moon_hare", "Moon Hare") \
		.at([&"moon", &"alien", &"tundra"]) \
		.stats(20.0, 0.0, 5.4, 14.0) \
		.with_flags({&"timid": 1.0, &"flee_range": 9.0, &"jump_blocks": 3}) \
		.look(Color(0.78, 0.8, 0.9), Color(0.5, 0.5, 0.68), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true, "glow": 0.1}) \
		.drop(&"raw_meat", 1, 2, 0.9).drop(&"monster_hide", 1, 2, 0.5) \
		.describe("Low gravity has made it insufferable.")

	_critter(&"reed_paddler", "Reed Paddler") \
		.kind(MobSpecies.FAM_CRITTER, MobSpecies.LOCO_AMPHIBIOUS, &"passive").acts(&"skittish") \
		.at([&"ocean", &"swamp", &"jungle"]).aquatic() \
		.look(Color(0.4, 0.55, 0.45), Color(0.75, 0.7, 0.35), &"blob",
			{"eyes": 2, "limbs": 2, "tail": true}) \
		.drop(&"raw_meat", 1, 2, 0.9) \
		.describe("Paddles. That is the whole strategy.")

	_critter(&"ash_vole", "Ash Vole") \
		.at([&"volcanic", &"scorched", &"barren"]) \
		.resist({Const.ELEM_FIRE: 0.3}) \
		.look(Color(0.35, 0.3, 0.3), Color(0.85, 0.4, 0.15), &"quadruped",
			{"eyes": 2, "limbs": 4, "tail": true, "glow": 0.12}) \
		.drop(&"raw_meat", 1, 1, 0.85).drop(&"ember_core", 1, 1, 0.12) \
		.describe("Nests in cooling slag and regrets nothing.")

	_critter(&"spore_shuffler", "Spore Shuffler") \
		.at([&"mushroom", &"toxic", &"swamp"]) \
		.look(Color(0.8, 0.6, 0.75), Color(0.45, 0.35, 0.45), &"plant",
			{"eyes": 2, "limbs": 2, "glow": 0.15, "pattern": &"spots"}) \
		.drop(&"spore_sac", 1, 2, 0.85) \
		.describe("Walks like a mushroom that learned about ambition.")

	_critter(&"crystal_mite", "Crystal Mite") \
		.at([&"crystal", &"moon", &"ruins"]) \
		.look(Color(0.7, 0.85, 0.95), Color(0.45, 0.6, 0.85), &"insect",
			{"eyes": 4, "limbs": 4, "glow": 0.35, "scale": 0.8}) \
		.drop(&"crystal_shard", 1, 2, 0.8) \
		.describe("Chimes when it runs. Worth catching for that alone.")

	_critter(&"garden_wisp", "Garden Wisp") \
		.kind(MobSpecies.FAM_CRITTER, MobSpecies.LOCO_HOVER, &"passive").acts(&"skittish") \
		.at([&"garden", &"forest", &"bioluminescent"]) \
		.stats(14.0, 0.0, 3.0, 0.0).body(Vector3(0.5, 0.5, 0.5)) \
		.look(Color(0.95, 0.9, 0.6), Color(0.7, 0.85, 0.5), &"orb",
			{"eyes": 0, "limbs": 0, "glow": 0.8, "scale": 0.7}) \
		.drop(&"glow_gland", 1, 1, 0.6) \
		.describe("Nobody has established what it eats.")
