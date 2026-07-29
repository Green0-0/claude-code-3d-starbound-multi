## Components, power, tech cards and augments — the branch that turns metal into
## capability rather than into gear.
##
## Component ids are the real ones from `content/items/10_materials.gd`:
## `copper_wire`, `silicon_wafer`, `circuit_board`, `advanced_circuit`,
## `quantum_processor`, `energy_cell`, `dense_energy_cell`, `power_core`,
## `fusion_core`, `iron_gear`, `electric_motor`, `sensor_lens`, `nanowire`,
## `hydraulic_piston`, `polymer`, `adhesive`, `rubber`, `luminous_powder`.
##
## Tech cards (`Kind.TECH`) are consumed by the `Tech` manager. Augments
## (`Kind.AUGMENT`) are slotted into gear by `crafting/upgrade.gd`.
extends RefCounted

static func register_all(reg) -> void:
	_chemistry_basics(reg)
	_components(reg)
	_power(reg)
	_tech_cards(reg)
	_augments(reg)


## The chemistry lab's feedstock chain.
static func _chemistry_basics(reg) -> void:
	reg.add(CraftRecipe.make("rubber", &"chemistry")
		.takes(&"tree_sap", 3).takes(&"sulphur", 1).gives(&"rubber", 2)
		.lasts(2.0).needs_tier(2)
		.in_category(&"materials").in_group(&"chemistry")
		.describe("Vulcanised sap. Grips, seals and refuses to conduct.")
		.learned_from_material(&"tree_sap"))

	reg.add(CraftRecipe.make("adhesive", &"chemistry")
		.takes(&"resin", 2).takes(&"tree_sap", 2).gives(&"adhesive", 3)
		.lasts(1.5).needs_tier(2)
		.in_category(&"materials").in_group(&"chemistry")
		.learned_from_material(&"resin"))

	reg.add(CraftRecipe.make("polymer", &"chemistry")
		.takes(&"crude_oil", 2).takes(&"carbon_powder", 1).gives(&"polymer", 3)
		.lasts(3.0).needs_tier(3)
		.in_category(&"materials").in_group(&"chemistry")
		.describe("Long-chain plastic sheet. Light, tough, entirely artificial.")
		.learned_from_material(&"crude_oil"))

	reg.add(CraftRecipe.make("refined_fuel", &"chemistry")
		.takes(&"crude_oil", 3).takes(&"salt", 1).gives(&"ftl_fuel", 2)
		.byproduct(&"tar", 1, 0.4)
		.lasts(4.0).needs_tier(3)
		.in_category(&"tech").in_group(&"chemistry")
		.describe("Cracked, filtered and stabilised. What gets a ship moving.")
		.learned_from_material(&"crude_oil"))

	reg.add(CraftRecipe.make("luminous_dust", &"chemistry")
		.takes(&"glow_gland", 2).gives(&"luminous_powder", 3)
		.lasts(1.5).needs_tier(2)
		.in_category(&"materials").in_group(&"chemistry")
		.learned_from_material(&"glow_gland"))

	reg.add(CraftRecipe.make("luminous_dust_fungus", &"chemistry")
		.takes(&"glow_fungus", 4).gives(&"luminous_powder", 2)
		.lasts(1.5).needs_tier(2)
		.in_category(&"materials").in_group(&"chemistry")
		.learned_from_material(&"glow_fungus"))

	reg.add(CraftRecipe.make("saltpeter_leach", &"chemistry")
		.takes(&"dirt", 6).takes(&"ash", 2).takes(&"water_flask", 1)
		.gives(&"saltpetre", 2)
		.lasts(4.0).needs_tier(2)
		.in_category(&"materials").in_group(&"chemistry")
		.describe("Leached out of old soil. Slow, tedious, necessary.")
		.learned_from_material(&"ash"))


static func _components(reg) -> void:
	reg.add(CraftRecipe.make("gear", &"anvil")
		.takes(&"iron_bar", 2).gives(&"iron_gear", 2)
		.lasts(1.0).needs_tier(1)
		.in_category(&"tech").in_group(&"metalwork")
		.describe("Cut steel teeth. Turns one kind of effort into another.")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("circuit_board", &"assembler")
		.takes(&"silicon_wafer", 1).takes(&"copper_wire", 6).takes(&"adhesive", 1)
		.gives(&"circuit_board", 2)
		.lasts(2.5).needs_tier(3)
		.in_category(&"tech").in_group(&"electronics")
		.describe("Etched traces on a doped wafer.")
		.learned_from_material(&"silicon_wafer"))

	reg.add(CraftRecipe.make("advanced_circuit", &"assembler")
		.takes(&"circuit_board", 3).takes(&"gold_bar", 2).takes(&"nanowire", 1)
		.gives(&"advanced_circuit", 1)
		.lasts(4.0).needs_tier(4)
		.in_category(&"tech").in_group(&"electronics")
		.describe("Twelve layers of it. Do not attempt a field repair.")
		.learned_from_material(&"nanowire"))

	reg.add(CraftRecipe.make("processor_chip", &"replicator")
		.takes(&"advanced_circuit", 2).takes(&"prism_shard", 2).takes(&"nanowire", 4)
		.gives(&"quantum_processor", 1)
		.lasts(8.0).needs_tier(5)
		.in_category(&"tech").in_group(&"electronics")
		.describe("Enough compute to fly a ship, in the size of a thumbnail.")
		.learned_at_tier(5))

	reg.add(CraftRecipe.make("servo_motor", &"assembler")
		.takes(&"copper_wire", 10).takes(&"iron_gear", 2).takes(&"iron_bar", 2)
		.gives(&"electric_motor", 1)
		.lasts(3.0).needs_tier(3)
		.in_category(&"tech").in_group(&"electronics")
		.learned_from_material(&"iron_gear"))

	reg.add(CraftRecipe.make("hydraulic_piston", &"assembler")
		.takes(&"steel_plate", 3).takes(&"rubber", 3).takes(&"iron_gear", 1)
		.gives(&"hydraulic_piston", 1)
		.lasts(3.0).needs_tier(3)
		.in_category(&"tech").in_group(&"electronics")
		.describe("Shoves harder than anything its size has a right to.")
		.learned_from_material(&"rubber"))

	reg.add(CraftRecipe.make("sensor_lens", &"assembler")
		.takes(&"quartz", 3).takes(&"silver_bar", 1).gives(&"sensor_lens", 1)
		.lasts(2.5).needs_tier(3)
		.in_category(&"tech").in_group(&"electronics")
		.describe("Ground to a tolerance you cannot see and cannot afford to ruin.")
		.learned_from_material(&"quartz"))

	reg.add(CraftRecipe.make("nanowire", &"replicator")
		.takes(&"carbon_powder", 6).takes(&"aegisalt_bar", 1).takes(&"quantum_fluid", 1)
		.gives(&"nanowire", 4)
		.lasts(6.0).needs_tier(5)
		.in_category(&"tech").in_group(&"electronics")
		.describe("One molecule thick, and it will still hold your weight.")
		.learned_at_tier(5))


static func _power(reg) -> void:
	reg.add(CraftRecipe.make("battery", &"assembler")
		.takes(&"copper_bar", 3).takes(&"crystal_shard", 2).takes(&"rubber", 1)
		.gives(&"energy_cell", 2)
		.lasts(2.0).needs_tier(3)
		.in_category(&"tech").in_group(&"electronics")
		.describe("Charged, sealed, and only mildly prone to venting.")
		.learned_from_material(&"crystal_shard"))

	reg.add(CraftRecipe.make("high_capacity_battery", &"assembler")
		.takes(&"energy_cell", 4).takes(&"silver_bar", 2).takes(&"polymer", 2)
		.gives(&"dense_energy_cell", 1)
		.lasts(4.0).needs_tier(4)
		.in_category(&"tech").in_group(&"electronics")
		.describe("Holds a day of tool charge. Or half a second of a mistake.")
		.learned_from_material(&"energy_cell"))

	reg.add(CraftRecipe.make("power_core", &"replicator")
		.takes(&"dense_energy_cell", 3).takes(&"ferozium_bar", 2).takes(&"prism_shard", 2)
		.gives(&"power_core", 1)
		.lasts(8.0).needs_tier(5)
		.in_category(&"tech").in_group(&"electronics")
		.describe("A humming lattice that gives back more than it was fed.")
		.learned_at_tier(5))

	reg.add(CraftRecipe.make("fusion_core", &"replicator")
		.takes(&"power_core", 2).takes(&"erchius_crystal", 4).takes(&"quantum_processor", 1)
		.gives(&"fusion_core", 1)
		.lasts(14.0).needs_tier(6)
		.in_category(&"tech").in_group(&"electronics")
		.describe("A star, penned in and made to work shifts.")
		.learned_at_tier(6))


## Tech cards are the movement / utility unlocks. Each is a blueprint or a quest
## reward so that finding one is an event, not a shopping trip.
static func _tech_cards(reg) -> void:
	var cards: Array[Dictionary] = [
		{"id": &"tech_dash", "tier": 2, "blueprint": &"blueprint_tech_dash",
		"cost": {&"iron_bar": 8, &"energy_cell": 2, &"circuit_board": 1},
		"desc": "A short burst of speed along the plane."},
		{"id": &"tech_double_jump", "tier": 2, "blueprint": &"blueprint_tech_jump",
		"cost": {&"titanium_bar": 6, &"energy_cell": 2, &"rubber": 4}},
		{"id": &"tech_glide", "tier": 3, "blueprint": &"blueprint_tech_glide",
		"cost": {&"cloth": 12, &"titanium_bar": 4, &"circuit_board": 1}},
		{"id": &"tech_wall_cling", "tier": 3, "blueprint": &"blueprint_tech_cling",
		"cost": {&"rubber": 8, &"adhesive": 4, &"circuit_board": 1}},
		{"id": &"tech_sprint", "tier": 2, "blueprint": &"blueprint_tech_sprint",
		"cost": {&"tough_leather": 6, &"energy_cell": 1, &"iron_gear": 2}},
		{"id": &"tech_magnet_grip", "tier": 3, "blueprint": &"blueprint_tech_magnet",
		"cost": {&"iron_bar": 10, &"copper_wire": 12, &"energy_cell": 2},
		"desc": "Drops come to you."},
		{"id": &"tech_nightvision", "tier": 4, "blueprint": &"blueprint_tech_nightvision",
		"cost": {&"sensor_lens": 2, &"luminous_powder": 6, &"circuit_board": 2}},
		{"id": &"tech_morph_ball", "tier": 4, "blueprint": &"blueprint_tech_morphball",
		"cost": {&"durasteel_bar": 10, &"electric_motor": 2, &"advanced_circuit": 1},
		"desc": "Roll through a one-block gap. Any of the four views."},
		{"id": &"tech_phase_step", "tier": 4, "quest": &"quest_deep_ruin",
		"cost": {&"aegisalt_bar": 8, &"aether_dust": 4, &"quantum_processor": 1},
		"desc": "Shift a layer deeper even when the voxel is solid. Briefly."},
		{"id": &"tech_plane_anchor", "tier": 3, "blueprint": &"blueprint_tech_anchor",
		"cost": {&"titanium_bar": 6, &"prism_shard": 1, &"circuit_board": 2},
		"desc": "Flip the view while airborne without losing momentum."},
		{"id": &"tech_water_breathing", "tier": 3, "blueprint": &"blueprint_tech_gills",
		"cost": {&"kelp": 8, &"polymer": 3, &"sensor_lens": 1}},
		{"id": &"tech_rocket_boost", "tier": 5, "quest": &"quest_orbital_wreck",
		"cost": {&"ferozium_bar": 10, &"ftl_fuel": 8, &"hydraulic_piston": 2}},
		{"id": &"tech_fold", "tier": 6, "quest": &"quest_ancient_gate",
		"cost": {&"solarium_bar": 8, &"ancient_essence": 2, &"quantum_processor": 2},
		"desc": "Short-range teleport. Ignores the depth axis entirely."},
	]
	for c: Dictionary in cards:
		var tier := int(c["tier"])
		var station: StringName = &"assembler" if tier < 5 else &"replicator"
		var r := CraftRecipe.make("techcard_%s" % c["id"], station) \
			.gives(StringName(c["id"]), 1) \
			.lasts(4.0 + float(tier)) \
			.needs_tier(tier) \
			.in_category(&"tech").in_group(&"electronics") \
			.ordered(tier * 10) \
			.describe(String(c.get("desc", "")))
		var cost: Dictionary = c["cost"]
		for k: StringName in cost:
			r.takes(k, int(cost[k]))
		if c.has("blueprint"):
			r.learned_from_blueprint(StringName(c["blueprint"]))
		if c.has("quest"):
			r.learned_from_quest(StringName(c["quest"]))
		reg.add(r)


## Augments are slotted into gear by `CraftUpgrade.slot_augment()`.
static func _augments(reg) -> void:
	var augs: Array[Dictionary] = [
		{"id": &"aug_sharpness", "tier": 1, "station": &"anvil",
		"cost": {&"iron_bar": 4, &"crystal_shard": 3}, "desc": "+ melee damage."},
		{"id": &"aug_swiftness", "tier": 1, "station": &"anvil",
		"cost": {&"silver_bar": 4, &"rubber": 2}, "desc": "+ attack speed."},
		{"id": &"aug_reach", "tier": 1, "station": &"anvil",
		"cost": {&"copper_bar": 6, &"quartz": 2}, "desc": "+ tool range."},
		{"id": &"aug_durability", "tier": 2, "station": &"forge",
		"cost": {&"titanium_bar": 4, &"tough_leather": 3}, "desc": "+ maximum durability."},
		{"id": &"aug_ember", "tier": 3, "station": &"chemistry",
		"cost": {&"tar": 4, &"ruby": 1}, "desc": "Adds fire damage."},
		{"id": &"aug_frost", "tier": 3, "station": &"chemistry",
		"cost": {&"ice_crystal": 4, &"sapphire": 1}, "desc": "Adds ice damage."},
		{"id": &"aug_shock", "tier": 4, "station": &"assembler",
		"cost": {&"copper_wire": 12, &"energy_cell": 2, &"topaz": 1}, "desc": "Adds electric damage."},
		{"id": &"aug_venom", "tier": 3, "station": &"chemistry",
		"cost": {&"venom_gland": 3, &"emerald": 1}, "desc": "Adds poison damage."},
		{"id": &"aug_ward", "tier": 4, "station": &"assembler",
		"cost": {&"aegisalt_bar": 4, &"energy_cell": 2}, "desc": "+ armour defence."},
		{"id": &"aug_vitality", "tier": 4, "station": &"chemistry",
		"cost": {&"wartweed": 6, &"gold_bar": 2}, "desc": "+ maximum health."},
		{"id": &"aug_lightfoot", "tier": 4, "station": &"assembler",
		"cost": {&"rubber": 6, &"violium_bar": 2}, "desc": "+ movement speed."},
		{"id": &"aug_cosmic", "tier": 6, "station": &"replicator",
		"cost": {&"solarium_bar": 4, &"void_residue": 2},
		"desc": "Adds cosmic damage. Nothing resists it."},
	]
	for a: Dictionary in augs:
		var tier := int(a["tier"])
		var r := CraftRecipe.make("augment_%s" % a["id"], StringName(a["station"])) \
			.gives(StringName(a["id"]), 1) \
			.lasts(3.0 + float(tier) * 0.5) \
			.needs_tier(tier) \
			.in_category(&"tech").in_group(&"chemistry") \
			.ordered(tier * 10 + 5) \
			.describe(String(a["desc"])) \
			.learned_at_tier(tier)
		var cost: Dictionary = a["cost"]
		for k: StringName in cost:
			r.takes(k, int(cost[k]))
		reg.add(r)
