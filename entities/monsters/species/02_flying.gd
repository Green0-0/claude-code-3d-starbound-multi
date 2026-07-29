## Flying family: drifters, divers, swarms and floaters — plus the Void Flitter,
## which refuses to hold still in a single depth layer.
extends RefCounted


static func register_all(_db) -> void:
	MobSpeciesDB.define(&"dusk_moth", "Dusk Moth") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_FLY, &"flier") \
		.threat(1).at([&"forest", &"garden", &"bioluminescent", &"mushroom", &"jungle"]) \
		.stats(28.0, 6.0, 4.4, 0.0).body(Vector3(0.8, 0.7, 0.8)) \
		.senses(13.0, 26.0, 3).melee(1.4, 1.3, 0.3) \
		.look(Color(0.72, 0.62, 0.82), Color(0.42, 0.34, 0.55), &"bird",
			{"eyes": 2, "limbs": 2, "wings": 2, "glow": 0.12, "pattern": &"spots"}) \
		.drop(&"monster_hide", 1, 1, 0.4).drop(&"glow_gland", 1, 1, 0.25).worth(7) \
		.describe("Drawn to lantern light. Less charming in a swarm.")

	MobSpeciesDB.define(&"talon_diver", "Talon Diver") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_FLY, &"flier").acts(&"diver") \
		.threat(3).at([&"savannah", &"barren", &"ruins", &"tundra", &"moon"]) \
		.stats(66.0, 19.0, 6.5, 0.0).body(Vector3(1.0, 0.9, 1.0)) \
		.senses(26.0, 48.0, 4).melee(1.5, 1.6, 0.25) \
		.look(Color(0.6, 0.5, 0.42), Color(0.28, 0.24, 0.22), &"bird",
			{"eyes": 2, "limbs": 2, "wings": 2, "tail": true, "pattern": &"stripes"}) \
		.with_flags({&"dive_height": 8.0, &"dive_cooldown": 2.4}) \
		.drop(&"feather", 1, 3, 0.8).drop(&"raw_meat", 1, 2, 0.5).worth(23) \
		.describe("Circles until you stop looking up.")

	MobSpeciesDB.define(&"bitegnat_swarm", "Bitegnat Swarm") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_FLY, &"flier").acts(&"swarm") \
		.threat(1).at([&"jungle", &"swamp", &"mushroom", &"toxic"]) \
		.stats(34.0, 5.0, 5.2, 0.0).body(Vector3(1.1, 1.0, 1.1)) \
		.senses(15.0, 28.0, 3).melee(1.6, 0.55, 0.15) \
		.look(Color(0.3, 0.28, 0.2), Color(0.5, 0.46, 0.2), &"insect",
			{"eyes": 6, "limbs": 4, "wings": 2, "pattern": &"speckle"}) \
		.with_flags({&"child": &"bitegnat_mote"}) \
		.drop(&"chitin", 1, 2, 0.5).worth(9) \
		.describe("A cloud with opinions. Splits when you hurt it.")

	MobSpeciesDB.define(&"bitegnat_mote", "Bitegnat") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_FLY, &"flier") \
		.threat(0).at([&"jungle", &"swamp", &"mushroom"]) \
		.stats(10.0, 3.0, 6.0, 0.0).body(Vector3(0.5, 0.5, 0.5)) \
		.senses(12.0, 22.0, 2).melee(1.2, 0.5, 0.12) \
		.look(Color(0.3, 0.28, 0.2), Color(0.5, 0.46, 0.2), &"insect",
			{"eyes": 4, "limbs": 2, "wings": 2, "scale": 0.6}) \
		.weight(0.15).worth(1) \
		.describe("One angry mote of the whole.")

	MobSpeciesDB.define(&"gasbag_floater", "Gasbag Floater") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_HOVER, &"flier").acts(&"floater") \
		.threat(2).at([&"alien", &"toxic", &"swamp", &"bioluminescent"]) \
		.stats(44.0, 9.0, 2.0, 0.0).body(Vector3(1.1, 1.2, 1.1), 0.2) \
		.senses(14.0, 26.0, 3).melee(1.6, 1.8, 0.4) \
		.elemental(Const.ELEM_POISON).resist({Const.ELEM_POISON: 0.0, Const.ELEM_FIRE: 2.2}) \
		.look(Color(0.66, 0.78, 0.44), Color(0.4, 0.55, 0.3), &"orb",
			{"eyes": 1, "limbs": 2, "glow": 0.2, "pattern": &"spots"}) \
		.with_flags({&"pop_radius": 3.6}) \
		.drop(&"venom_sac", 1, 1, 0.5).drop(&"slime", 1, 2, 0.5).worth(12) \
		.describe("Buoyant, patient, and full of something you do not want to breathe.")

	MobSpeciesDB.define(&"ember_wisp", "Ember Wisp") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_HOVER, &"flier") \
		.threat(3).at([&"volcanic", &"scorched", &"midnight"]) \
		.stats(52.0, 16.0, 5.0, 0.0).body(Vector3(0.7, 0.7, 0.7), 0.4) \
		.senses(18.0, 34.0, 4).melee(1.5, 1.0, 0.2, 3.0) \
		.elemental(Const.ELEM_FIRE).resist({Const.ELEM_FIRE: 0.0, Const.ELEM_ICE: 2.0}) \
		.look(Color(1.0, 0.62, 0.2), Color(0.75, 0.2, 0.08), &"orb",
			{"eyes": 0, "limbs": 0, "glow": 0.7, "spikes": 4}) \
		.drop(&"ember_core", 1, 2, 0.7).worth(24) \
		.describe("A hot idea with nowhere to be.")

	MobSpeciesDB.define(&"sky_ray", "Sky Ray") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_FLY, &"ranged") \
		.threat(3).at([&"alien", &"garden", &"savannah", &"bioluminescent"]) \
		.stats(88.0, 15.0, 4.6, 0.0).body(Vector3(1.4, 0.8, 1.4), 0.3) \
		.senses(24.0, 42.0, 4).shoots(&"lightning_arc", 16.0, 2.0, 20.0) \
		.elemental(Const.ELEM_ELECTRIC).resist({Const.ELEM_ELECTRIC: 0.1}) \
		.look(Color(0.5, 0.68, 0.85), Color(0.28, 0.4, 0.62), &"bird",
			{"eyes": 2, "limbs": 0, "wings": 2, "tail": true, "glow": 0.2, "pattern": &"stripes"}) \
		.with_flags({&"min_range": 7.0}) \
		.drop(&"monster_hide", 1, 2, 0.6).drop(&"circuit", 1, 1, 0.2).worth(26) \
		.describe("Glides on a charge it keeps building the whole time.")

	## Perspective monster: it phases across depth layers on a fixed beat, so
	## half your swings pass through empty air where it just was.
	MobSpeciesDB.define(&"void_flitter", "Void Flitter") \
		.kind(MobSpecies.FAM_FLYING, MobSpecies.LOCO_FLY, &"flier").acts(&"phaser") \
		.threat(4).at([&"midnight", &"moon", &"alien", &"ruins"]) \
		.stats(76.0, 22.0, 7.0, 0.0).body(Vector3(0.8, 0.9, 0.8), 0.6) \
		.senses(26.0, 60.0, 6).melee(1.6, 0.9, 0.2) \
		.elemental(Const.ELEM_COSMIC).resist({Const.ELEM_COSMIC: 0.2, Const.ELEM_PHYSICAL: 0.7}) \
		.look(Color(0.35, 0.22, 0.5), Color(0.65, 0.4, 0.95), &"bird",
			{"eyes": 3, "limbs": 2, "wings": 2, "tail": true, "glow": 0.4}) \
		.with_flags({&"phase_interval": 1.5, &"layer_cooldown": 0.1}) \
		.only_at_night() \
		.drop(&"void_dust", 1, 2, 0.6).worth(34).hard_to_catch(2.0) \
		.describe("Never in one plane long enough to be hit twice.")
