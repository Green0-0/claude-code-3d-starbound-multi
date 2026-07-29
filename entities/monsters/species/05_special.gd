## Special family: exploders, splitters, support monsters, hazards, the Chest
## Mimic and the Plane Wraith — a creature that is wherever you are looking.
extends RefCounted


static func register_all(_db) -> void:
	# ---------------------------------------------------------------- exploders
	MobSpeciesDB.define(&"blast_pod", "Blast Pod") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_WALK, &"suicide").acts(&"exploder") \
		.threat(2).at([&"volcanic", &"scorched", &"toxic", &"barren", &"ruins"]) \
		.stats(34.0, 16.0, 4.8, 11.0).body(Vector3(0.8, 0.9, 0.8), 0.2) \
		.senses(18.0, 34.0, 3).melee(1.6, 1.0, 0.2) \
		.elemental(Const.ELEM_FIRE).resist({Const.ELEM_FIRE: 0.0}) \
		.look(Color(0.85, 0.5, 0.2), Color(0.3, 0.2, 0.15), &"orb",
			{"eyes": 2, "limbs": 2, "glow": 0.3, "spikes": 3}) \
		.with_flags({&"blast_radius": 4.2, &"fuse_range": 2.8, &"reckless": true}) \
		.drop(&"ember_core", 1, 1, 0.4).worth(14) \
		.describe("Runs at you with obvious intent and a very short attention span.")

	MobSpeciesDB.define(&"sapper_pod", "Sapper Pod") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_WALK, &"suicide").acts(&"exploder") \
		.threat(4).at([&"ruins", &"moon", &"crystal"]) \
		.stats(66.0, 26.0, 5.4, 12.0).body(Vector3(0.9, 1.0, 0.9), 0.3) \
		.senses(22.0, 40.0, 4).melee(1.8, 1.0, 0.2) \
		.elemental(Const.ELEM_ELECTRIC) \
		.look(Color(0.55, 0.6, 0.68), Color(0.9, 0.85, 0.3), &"orb",
			{"eyes": 1, "limbs": 4, "glow": 0.4, "spikes": 4, "pattern": &"plates"}) \
		.with_flags({&"blast_radius": 5.5, &"fuse_range": 3.2, &"terrain_damage": true,
			&"reckless": true}) \
		.drop(&"circuit", 1, 2, 0.5).worth(30) \
		.describe("Blows a hole through the wall — and, helpfully, the layer behind it.")

	# ---------------------------------------------------------------- splitters
	MobSpeciesDB.define(&"ooze_mother", "Ooze Mother") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_WALK, &"melee").acts(&"splitter") \
		.threat(3).at([&"swamp", &"toxic", &"mushroom", &"jungle", &"alien"]) \
		.stats(120.0, 14.0, 2.8, 9.0).body(Vector3(1.3, 1.2, 1.3), 0.5) \
		.senses(16.0, 30.0, 3).melee(1.8, 1.3, 0.35) \
		.elemental(Const.ELEM_POISON).resist({Const.ELEM_POISON: 0.0, Const.ELEM_PHYSICAL: 0.75}) \
		.look(Color(0.45, 0.7, 0.4), Color(0.25, 0.42, 0.28), &"blob",
			{"eyes": 3, "limbs": 0, "glow": 0.15, "pattern": &"spots"}) \
		.with_flags({&"split_count": 3, &"generations": 2, &"split_scale": 0.6,
			&"child": &"ooze_mother"}) \
		.drop(&"slime", 2, 4, 0.9).drop(&"venom_sac", 1, 1, 0.4).worth(24) \
		.describe("Killing it is a compounding problem.")

	# ------------------------------------------------------------------ support
	MobSpeciesDB.define(&"mender_mote", "Mender Mote") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_HOVER, &"support").acts(&"healer") \
		.threat(3).at([&"alien", &"ruins", &"crystal", &"bioluminescent", &"moon"]) \
		.stats(58.0, 6.0, 5.0, 0.0).body(Vector3(0.7, 0.7, 0.7), 0.3) \
		.senses(22.0, 36.0, 4).melee(1.4, 2.2, 0.4) \
		.resist({Const.ELEM_COSMIC: 0.4}) \
		.look(Color(0.6, 0.95, 0.75), Color(0.9, 0.98, 0.85), &"orb",
			{"eyes": 1, "limbs": 0, "wings": 2, "glow": 0.55}) \
		.with_flags({&"heal_radius": 12.0, &"heal_amount": 16.0, &"timid": 1.0,
			&"flee_range": 7.0}) \
		.drop(&"glow_gland", 1, 2, 0.7).worth(22) \
		.describe("Kill it first. You will be told this twice.")

	MobSpeciesDB.define(&"bulwark_drone", "Bulwark Drone") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_HOVER, &"support").acts(&"shielder") \
		.threat(4).at([&"ruins", &"moon", &"crystal", &"barren"]) \
		.stats(140.0, 12.0, 3.4, 0.0).body(Vector3(1.0, 1.0, 1.0), 0.7) \
		.senses(24.0, 40.0, 4).melee(1.6, 1.8, 0.4).plated(5.0) \
		.elemental(Const.ELEM_ELECTRIC).resist({Const.ELEM_PHYSICAL: 0.55, Const.ELEM_ELECTRIC: 0.2}) \
		.look(Color(0.62, 0.66, 0.72), Color(0.35, 0.7, 0.9), &"orb",
			{"eyes": 1, "limbs": 4, "glow": 0.35, "pattern": &"plates"}) \
		.with_flags({&"shield_radius": 10.0, &"shield_strength": 0.45, &"self_shield": 0.35}) \
		.drop(&"circuit", 1, 3, 0.7).drop(&"ancient_relic", 1, 1, 0.06).worth(38) \
		.describe("Everything near it is harder to kill, including it.")

	# ------------------------------------------------------------------ hazards
	MobSpeciesDB.define(&"miasma_cloud", "Miasma Cloud") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_HOVER, &"melee").acts(&"poison_cloud") \
		.threat(2).at([&"toxic", &"swamp", &"midnight", &"mushroom"]) \
		.stats(70.0, 8.0, 1.8, 0.0).body(Vector3(1.6, 1.6, 1.6), 1.0) \
		.senses(14.0, 26.0, 3).melee(2.6, 1.0, 0.3) \
		.elemental(Const.ELEM_POISON).resist({Const.ELEM_POISON: 0.0, Const.ELEM_PHYSICAL: 0.25,
			Const.ELEM_FIRE: 1.6}) \
		.look(Color(0.5, 0.62, 0.35), Color(0.3, 0.4, 0.25), &"jelly",
			{"eyes": 0, "limbs": 0, "glow": 0.18, "scale": 1.3}) \
		.with_flags({&"cloud_radius": 3.4, &"uncapturable": true}) \
		.drop(&"venom_sac", 1, 2, 0.6).worth(15) \
		.describe("Burn it. Nothing else touches it properly.")

	# ------------------------------------------------------------------- mimics
	## Perspective monster: sits inert in a layer you have not visited, wearing
	## the shape of loot, until you flip or shift onto it.
	MobSpeciesDB.define(&"chest_mimic", "Chest Mimic") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_WALK, &"ambusher").acts(&"mimic") \
		.threat(3).at([&"ruins", &"midnight", &"moon"]) \
		.stats(110.0, 26.0, 4.6, 12.0).body(Vector3(1.0, 0.9, 1.0), 0.6) \
		.senses(10.0, 26.0, 2).melee(1.7, 1.1, 0.25) \
		.resist({Const.ELEM_PHYSICAL: 0.7}) \
		.look(Color(0.55, 0.38, 0.2), Color(0.85, 0.72, 0.3), &"beetle",
			{"eyes": 4, "limbs": 4, "spikes": 5, "pattern": &"plates"}) \
		.subterranean() \
		.drop(&"bone_fragment", 1, 2, 0.6).drop(&"ancient_relic", 1, 1, 0.12).worth(35) \
		.describe("Treasure never sits one layer off the corridor by accident.")

	## Perspective monster: a projection that re-forms in whichever plane the
	## player is currently looking through.
	MobSpeciesDB.define(&"plane_wraith", "Plane Wraith") \
		.kind(MobSpecies.FAM_SPECIAL, MobSpecies.LOCO_HOVER, &"melee").acts(&"projection") \
		.threat(5).at([&"midnight", &"alien", &"ruins", &"moon"]) \
		.stats(180.0, 34.0, 4.4, 0.0).body(Vector3(1.0, 1.8, 1.0), 1.0) \
		.senses(40.0, 200.0, 8, 60.0).melee(2.0, 1.2, 0.4) \
		.elemental(Const.ELEM_COSMIC) \
		.resist({Const.ELEM_COSMIC: 0.0, Const.ELEM_PHYSICAL: 0.6, Const.ELEM_ELECTRIC: 1.4}) \
		.look(Color(0.28, 0.2, 0.42), Color(0.7, 0.45, 1.0), &"humanoid",
			{"eyes": 4, "limbs": 2, "tail": true, "glow": 0.6, "spikes": 4}) \
		.with_flags({&"uncapturable": true, &"layer_cooldown": 0.05}) \
		.only_at_night().weight(0.4) \
		.drop(&"void_dust", 2, 4, 0.9).drop(&"ancient_relic", 1, 1, 0.2).worth(80) \
		.describe("There is no plane to retreat into. It is standing in all of them.")
