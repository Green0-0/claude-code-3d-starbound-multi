## The late game: refining, matter-manipulator cores, FTL fuel and the
## ancient-artefact chain that ends the progression.
##
## Refining beats smelting: the replicator pulls four bars out of four ore with
## a catalyst, where a forge manages two. That is the reward for building one.
extends RefCounted

static func register_all(reg) -> void:
	_refining(reg)
	_manipulator_cores(reg)
	_ftl(reg)
	_artefacts(reg)


static func _refining(reg) -> void:
	var refined: Array[Dictionary] = [
		{"out": &"aegisalt_bar", "ore": &"raw_aegisalt", "cat": &"cement_mix", "tier": 4},
		{"out": &"ferozium_bar", "ore": &"raw_ferozium", "cat": &"erchius_crystal", "tier": 5},
		{"out": &"violium_bar", "ore": &"raw_violium", "cat": &"erchius_crystal", "tier": 5},
		{"out": &"solarium_bar", "ore": &"raw_solarium", "cat": &"starlight_essence", "tier": 6},
	]
	for rd: Dictionary in refined:
		var tier := int(rd["tier"])
		reg.add(CraftRecipe.make("refine_%s" % rd["out"], &"replicator")
			.takes(StringName(rd["ore"]), 4).takes(StringName(rd["cat"]), 1)
			.gives(StringName(rd["out"]), 6)
			.byproduct(&"ash", 2, 0.3)
			.lasts(6.0 + float(tier)).needs_tier(tier)
			.in_category(&"materials").in_group(&"refining").ordered(tier)
			.describe("Refining pulls more from the same ore than a forge ever will.")
			.learned_at_tier(tier))

	reg.add(CraftRecipe.make("crystal_growing", &"chemistry")
		.takes(&"crystal_shard", 4).takes(&"water_flask", 2)
		.gives(&"quartz", 2)
		.byproduct(&"amethyst", 1, 0.15)
		.lasts(8.0).needs_tier(4)
		.in_category(&"materials").in_group(&"chemistry")
		.describe("Seed a shard and wait. Occasionally you get something better.")
		.learned_from_material(&"crystal_shard"))

	reg.add(CraftRecipe.make("gem_synthesis", &"replicator")
		.takes(&"quartz", 6).takes(&"carbon_powder", 4).takes(&"power_core", 1)
		.gives(&"diamond", 1)
		.byproduct(&"prism_shard", 1, 0.2)
		.lasts(12.0).needs_tier(5)
		.in_category(&"materials").in_group(&"refining")
		.describe("Carbon, squeezed until it agrees to be a diamond.")
		.learned_at_tier(5))

	reg.add(CraftRecipe.make("prism_shard_cut", &"replicator")
		.takes(&"diamond", 1).takes(&"aether_dust", 1).gives(&"prism_shard", 2)
		.lasts(8.0).needs_tier(5)
		.in_category(&"materials").in_group(&"refining")
		.describe("Splits light into colours that have no business existing.")
		.learned_from_material(&"aether_dust"))

	reg.add(CraftRecipe.make("cosmic_dust_condense", &"replicator")
		.takes(&"aether_dust", 3).takes(&"void_residue", 1).gives(&"cosmic_dust", 4)
		.lasts(10.0).needs_tier(6)
		.in_category(&"materials").in_group(&"refining")
		.learned_at_tier(6))

	reg.add(CraftRecipe.make("quantum_fluid_synth", &"replicator")
		.takes(&"plasmic_gel", 2).takes(&"cosmic_dust", 2).takes(&"quantum_processor", 1)
		.gives(&"quantum_fluid", 2)
		.lasts(14.0).needs_tier(6)
		.in_category(&"materials").in_group(&"refining")
		.describe("It is in the flask. It is also, measurably, not.")
		.learned_at_tier(6))

	reg.add(CraftRecipe.make("starlight_distil", &"replicator")
		.takes(&"erchius_crystal", 3).takes(&"prism_shard", 2).takes(&"power_core", 1)
		.gives(&"starlight_essence", 1)
		.lasts(16.0).needs_tier(6)
		.in_category(&"materials").in_group(&"refining")
		.describe("Bottled photons that have not yet agreed to be photons.")
		.learned_at_tier(6))


## The big, expensive, one-per-run purchases that raise the tier of block you
## can break at all. The tech agent applies the core; we only build it.
static func _manipulator_cores(reg) -> void:
	var cores: Array[Dictionary] = [
		{"id": &"mm_core_2", "tier": 1, "name": "Manipulator Core Mk.II", "station": &"anvil",
		"cost": {&"iron_bar": 20, &"crystal_shard": 8, &"silver_bar": 6},
		"desc": "Breaks tier-2 rock. Everything below opens up."},
		{"id": &"mm_core_3", "tier": 2, "name": "Manipulator Core Mk.III", "station": &"forge",
		"cost": {&"titanium_bar": 20, &"circuit_board": 4, &"quartz": 16}},
		{"id": &"mm_core_4", "tier": 3, "name": "Manipulator Core Mk.IV", "station": &"forge",
		"cost": {&"durasteel_bar": 24, &"advanced_circuit": 2, &"energy_cell": 12}},
		{"id": &"mm_core_5", "tier": 5, "name": "Manipulator Core Mk.V", "station": &"replicator",
		"cost": {&"ferozium_bar": 24, &"quantum_processor": 3, &"power_core": 2}},
		{"id": &"mm_core_6", "tier": 6, "name": "Manipulator Core Mk.VI", "station": &"replicator",
		"cost": {&"solarium_bar": 16, &"ancient_essence": 2, &"fusion_core": 1,
		&"quantum_processor": 4},
		"desc": "Bedrock is still bedrock. Everything else is negotiable."},
	]
	for c: Dictionary in cores:
		var tier := int(c["tier"])
		var r := CraftRecipe.make("core_%s" % c["id"], StringName(c["station"])) \
			.gives(StringName(c["id"]), 1) \
			.named(String(c["name"])) \
			.lasts(10.0 + float(tier) * 2.0) \
			.needs_tier(tier) \
			.in_category(&"tech").in_group(&"refining") \
			.ordered(tier * 10) \
			.describe(String(c.get("desc", ""))) \
			.learned_at_tier(tier)
		var cost: Dictionary = c["cost"]
		for k: StringName in cost:
			r.takes(k, int(cost[k]))
		reg.add(r)


## Ship fuel and hull parts. Fuel is cheap and repeatable — a running cost, not
## a wall.
static func _ftl(reg) -> void:
	reg.add(CraftRecipe.make("ftl_fuel_erchius", &"chemistry")
		.takes(&"erchius_crystal", 1).takes(&"water_flask", 2)
		.gives(&"ftl_fuel", 8)
		.lasts(4.0).needs_tier(4)
		.in_category(&"advanced").in_group(&"starship")
		.describe("Burns cold, and moves a ship between stars.")
		.learned_from_material(&"erchius_crystal"))

	reg.add(CraftRecipe.make("ftl_fuel_dense", &"replicator")
		.takes(&"erchius_crystal", 2).takes(&"solarium_bar", 1).takes(&"quantum_fluid", 1)
		.gives(&"ftl_fuel", 40)
		.lasts(10.0).needs_tier(6)
		.in_category(&"advanced").in_group(&"starship")
		.describe("Longer jumps, fewer stops.")
		.learned_at_tier(6))

	reg.add(CraftRecipe.make("ftl_drive", &"replicator")
		.takes(&"durasteel_bar", 16).takes(&"fusion_core", 1).takes(&"quantum_processor", 4)
		.takes(&"ancient_essence", 1)
		.gives(&"ftl_drive", 1)
		.lasts(30.0).needs_tier(6)
		.in_category(&"advanced").in_group(&"starship")
		.describe("The upgrade that opens the outer systems.")
		.learned_from_quest(&"quest_orbital_wreck"))

	reg.add(CraftRecipe.make("ship_hull_plate", &"replicator")
		.takes(&"durasteel_bar", 8).takes(&"aegisalt_bar", 2).takes(&"polymer", 4)
		.gives(&"ship_hull_plate", 4)
		.lasts(8.0).needs_tier(5)
		.in_category(&"advanced").in_group(&"starship")
		.learned_at_tier(5))

	reg.add(CraftRecipe.make("ship_thruster", &"replicator")
		.takes(&"ship_hull_plate", 4).takes(&"hydraulic_piston", 2).takes(&"power_core", 1)
		.gives(&"ship_thruster", 1)
		.lasts(14.0).needs_tier(5)
		.in_category(&"advanced").in_group(&"starship")
		.describe("Each one buys another jump of range.")
		.learned_at_tier(5))

	reg.add(CraftRecipe.make("emergency_beacon", &"assembler")
		.takes(&"circuit_board", 4).takes(&"energy_cell", 4).takes(&"iron_bar", 6)
		.gives(&"emergency_beacon", 1)
		.lasts(5.0).needs_tier(4)
		.in_category(&"advanced").in_group(&"starship")
		.describe("Summons something. You will not know what until it arrives.")
		.learned_at_tier(4))

	reg.add(CraftRecipe.make("star_chart", &"assembler")
		.takes(&"star_map_fragment", 3).takes(&"sensor_lens", 1).takes(&"plant_matter", 4)
		.gives(&"star_chart", 1)
		.lasts(6.0).needs_tier(4)
		.in_category(&"advanced").in_group(&"starship")
		.describe("Three torn slices, aligned into one usable chart.")
		.learned_from_material(&"star_map_fragment"))


## The ancient chain: essence, four keys, and the gate itself.
static func _artefacts(reg) -> void:
	reg.add(CraftRecipe.make("ancient_essence", &"replicator")
		.takes(&"ancient_fragment", 1).takes(&"prism_shard", 2).takes(&"power_core", 1)
		.gives(&"ancient_essence", 1)
		.byproduct(&"cosmic_dust", 2, 0.4)
		.lasts(12.0).needs_tier(5)
		.in_category(&"advanced").in_group(&"refining")
		.describe("A relic, coaxed back into whatever it used to be.")
		.learned_from_material(&"ancient_fragment"))

	reg.add(CraftRecipe.make("ancient_relic_reassemble", &"replicator")
		.takes(&"fossil_fragment", 8).takes(&"cosmic_dust", 2).takes(&"adhesive", 4)
		.gives(&"ancient_fragment", 1)
		.lasts(10.0).needs_tier(5)
		.in_category(&"advanced").in_group(&"refining")
		.describe("Eight fragments and a great deal of patience.")
		.learned_from_material(&"fossil_fragment"))

	var keys: Array[Dictionary] = [
		{"id": &"artefact_key_stone", "tier": 5, "quest": &"quest_stone_shrine",
		"cost": {&"ancient_essence": 1, &"marble": 12, &"quartz": 8}},
		{"id": &"artefact_key_flame", "tier": 5, "quest": &"quest_flame_shrine",
		"cost": {&"ancient_essence": 1, &"obsidian": 12, &"tar": 8}},
		{"id": &"artefact_key_frost", "tier": 5, "quest": &"quest_frost_shrine",
		"cost": {&"ancient_essence": 1, &"blue_ice": 12, &"silver_bar": 8}},
		{"id": &"artefact_key_void", "tier": 6, "quest": &"quest_void_shrine",
		"cost": {&"ancient_essence": 2, &"void_stone": 12, &"quantum_processor": 2}},
	]
	for kd: Dictionary in keys:
		var tier := int(kd["tier"])
		var r := CraftRecipe.make("artefact_%s" % kd["id"], &"replicator") \
			.gives(StringName(kd["id"]), 1) \
			.lasts(15.0).needs_tier(tier) \
			.in_category(&"advanced").in_group(&"refining") \
			.ordered(tier * 10) \
			.describe("One of four. The gate wants all of them.") \
			.learned_from_quest(StringName(kd["quest"]))
		var cost: Dictionary = kd["cost"]
		for c: StringName in cost:
			r.takes(c, int(cost[c]))
		reg.add(r)

	reg.add(CraftRecipe.make("artefact_gate_key", &"replicator")
		.takes(&"artefact_key_stone", 1).takes(&"artefact_key_flame", 1)
		.takes(&"artefact_key_frost", 1).takes(&"artefact_key_void", 1)
		.takes(&"ancient_essence", 2)
		.gives(&"gate_key", 1)
		.lasts(60.0).needs_tier(6)
		.in_category(&"advanced").in_group(&"refining").ordered(99)
		.describe("Four keys, one lock, and whatever is on the other side.")
		.learned_from_quest(&"quest_ancient_gate"))

	reg.add(CraftRecipe.make("artefact_ancient_gate", &"replicator")
		.takes(&"ancient_stone", 24).takes(&"ancient_essence", 6)
		.takes(&"ship_hull_plate", 8).takes(&"starlight_essence", 2)
		.gives(&"ancient_gate", 1)
		.lasts(90.0).needs_tier(6)
		.in_category(&"advanced").in_group(&"refining").ordered(100)
		.describe("Build the door. Then decide whether to open it.")
		.learned_from_quest(&"quest_ancient_gate"))

	reg.add(CraftRecipe.make("artefact_reroll_core", &"replicator")
		.takes(&"cosmic_dust", 2).takes(&"quartz", 6).takes(&"quantum_processor", 1)
		.gives(&"reroll_core", 1)
		.lasts(10.0).needs_tier(5)
		.in_category(&"advanced").in_group(&"refining")
		.describe("Rerolls a weapon's stats without spending its upgrade level.")
		.learned_at_tier(5))

	reg.add(CraftRecipe.make("artefact_augment_extractor", &"replicator")
		.takes(&"quantum_processor", 1).takes(&"aegisalt_bar", 4).takes(&"dense_energy_cell", 2)
		.gives(&"augment_extractor", 1)
		.lasts(10.0).needs_tier(5)
		.in_category(&"advanced").in_group(&"refining")
		.describe("Pulls an augment back out of a piece of gear, intact.")
		.learned_at_tier(5))

	reg.add(CraftRecipe.make("artefact_cipher_key", &"assembler")
		.takes(&"data_slate", 1).takes(&"quantum_processor", 1).takes(&"sensor_lens", 1)
		.gives(&"cipher_key", 1)
		.lasts(8.0).needs_tier(5)
		.in_category(&"advanced").in_group(&"refining")
		.describe("Decodes the glyphs. Does not explain them.")
		.learned_from_material(&"data_slate"))
