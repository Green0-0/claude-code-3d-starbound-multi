## Placeable objects: furniture, containers, lighting, machines and teleporters.
##
## Light sources and the perspective blocks are real block ids from
## `content/blocks/16_light.gd` and `18_special.gd`. Furniture, containers and
## machines are `Kind.OBJECT` items owned by the objects agent; the ids here are
## the convention it should follow.
extends RefCounted

static func register_all(reg) -> void:
	_furniture(reg)
	_containers(reg)
	_lights(reg)
	_machines(reg)
	_perspective(reg)
	_teleporters(reg)


static func _furniture(reg) -> void:
	var furn: Array[Dictionary] = [
		{"id": &"wooden_chair", "cost": {&"plank": 5}, "start": true},
		{"id": &"wooden_table", "cost": {&"plank": 8}, "start": true},
		{"id": &"bookshelf", "cost": {&"plank": 6, &"plant_matter": 9}},
		{"id": &"wooden_barrel", "cost": {&"plank": 8, &"iron_nail": 6}},
		{"id": &"rug", "cost": {&"cloth": 6, &"straw": 2}},
		{"id": &"curtain", "cost": {&"cloth": 6, &"rope": 1}},
		{"id": &"painting", "cost": {&"plank": 4, &"cloth": 2, &"ruby": 1}, "tier": 2},
		{"id": &"flower_pot", "cost": {&"clay_lump": 4, &"dirt": 1}},
		{"id": &"stone_bench", "cost": {&"stone_brick": 8}},
		{"id": &"metal_table", "cost": {&"steel_plate": 4}, "tier": 1, "station": &"anvil"},
		{"id": &"metal_chair", "cost": {&"steel_plate": 3}, "tier": 1, "station": &"anvil"},
		{"id": &"aquarium", "cost": {&"glass": 12, &"iron_bar": 2}, "tier": 2},
		{"id": &"sleeping_pod", "cost": {&"durasteel_bar": 8, &"cloth": 6, &"glass": 4},
		"tier": 4, "station": &"assembler", "desc": "Sleep, in a box, in space."},
		{"id": &"trophy_stand", "cost": {&"plank": 6, &"gold_bar": 1}, "tier": 2},
	]
	for f: Dictionary in furn:
		_simple(reg, f, &"furniture", &"furnishing", &"workbench")


static func _containers(reg) -> void:
	var boxes: Array[Dictionary] = [
		{"id": &"stone_chest", "cost": {&"stone_brick": 12}},
		{"id": &"iron_chest", "cost": {&"iron_bar": 8, &"plank": 4}, "tier": 1,
		"station": &"anvil", "desc": "More slots, less flammable."},
		{"id": &"steel_locker", "cost": {&"steel_plate": 8, &"iron_nail": 8}, "tier": 1,
		"station": &"anvil"},
		{"id": &"storage_pod", "cost": {&"durasteel_bar": 10, &"circuit_board": 2},
		"tier": 4, "station": &"assembler"},
		{"id": &"refrigerator", "cost": {&"steel_plate": 6, &"ice_crystal": 4, &"copper_wire": 6},
		"tier": 3, "station": &"assembler", "desc": "Food keeps. Meals stay warm longer."},
		{"id": &"item_sorter", "cost": {&"iron_bar": 6, &"circuit_board": 2, &"iron_gear": 2},
		"tier": 4, "station": &"assembler"},
		{"id": &"shipping_crate", "cost": {&"plank": 12, &"iron_nail": 8}},
		{"id": &"safe", "cost": {&"steel_plate": 10, &"iron_gear": 2, &"gold_bar": 1}, "tier": 2,
		"station": &"anvil"},
	]
	for b: Dictionary in boxes:
		_simple(reg, b, &"furniture", &"furnishing", &"workbench")


## Lighting. Every id here is a real light block.
static func _lights(reg) -> void:
	var lights: Array[Dictionary] = [
		{"id": &"candle", "cost": {&"resin": 2, &"plant_fibre": 1}, "count": 4, "start": true},
		{"id": &"lantern", "cost": {&"iron_bar": 2, &"glass": 2, &"torch": 1}, "tier": 1,
		"station": &"anvil"},
		{"id": &"paper_lantern", "cost": {&"plant_matter": 4, &"candle": 1}, "count": 2},
		{"id": &"glowbulb", "cost": {&"glass": 2, &"luminous_powder": 2}, "count": 4, "tier": 1},
		{"id": &"glowstone", "cost": {&"stone": 4, &"luminous_powder": 4}, "count": 4, "tier": 1,
		"desc": "A block that will not stop glowing. Ever."},
		{"id": &"sea_lantern", "cost": {&"prism_shard": 1, &"glass": 4, &"luminous_powder": 2},
		"tier": 4, "station": &"assembler"},
		{"id": &"star_lamp", "cost": {&"gold_bar": 2, &"starlight_essence": 1, &"glass": 4},
		"tier": 5, "station": &"replicator", "desc": "It keeps a little daylight in a jar."},
		{"id": &"ember_lamp", "cost": {&"obsidian": 2, &"magma_block": 1, &"iron_bar": 2},
		"tier": 3, "station": &"forge"},
		{"id": &"floodlight", "cost": {&"steel_plate": 4, &"glass": 4, &"energy_cell": 2},
		"tier": 3, "station": &"assembler", "desc": "Turns a cave into a room."},
		{"id": &"panel_light", "cost": {&"glass": 4, &"copper_wire": 4, &"energy_cell": 1},
		"count": 2, "tier": 3, "station": &"assembler"},
		{"id": &"fluorescent", "cost": {&"glass": 3, &"copper_wire": 3, &"sulphur": 1},
		"count": 2, "tier": 2, "station": &"assembler"},
		{"id": &"neon_strip_cyan", "cost": {&"glass": 3, &"copper_wire": 3, &"sapphire": 1},
		"count": 4, "tier": 3, "station": &"assembler"},
		{"id": &"neon_strip_magenta", "cost": {&"glass": 3, &"copper_wire": 3, &"amethyst": 1},
		"count": 4, "tier": 3, "station": &"assembler"},
		{"id": &"neon_strip_lime", "cost": {&"glass": 3, &"copper_wire": 3, &"emerald": 1},
		"count": 4, "tier": 3, "station": &"assembler"},
		{"id": &"neon_strip_amber", "cost": {&"glass": 3, &"copper_wire": 3, &"topaz": 1},
		"count": 4, "tier": 3, "station": &"assembler"},
	]
	for l: Dictionary in lights:
		_simple(reg, l, &"light", &"furnishing", &"workbench")


static func _machines(reg) -> void:
	var machines: Array[Dictionary] = [
		{"id": &"forge", "cost": {&"iron_bar": 20, &"clay_brick": 20, &"coal": 10},
		"tier": 1, "station": &"anvil", "time": 4.0,
		"desc": "A furnace that takes the work seriously."},
		{"id": &"chemistry", "cost": {&"glass": 16, &"iron_bar": 10, &"copper_wire": 8},
		"tier": 2, "station": &"anvil", "time": 4.0, "name": "Chemistry Lab"},
		{"id": &"assembler", "cost": {&"steel_plate": 12, &"circuit_board": 6, &"iron_gear": 8},
		"tier": 3, "station": &"forge", "time": 6.0},
		{"id": &"replicator", "cost": {&"durasteel_bar": 24, &"quantum_processor": 4,
		&"dense_energy_cell": 4, &"ancient_essence": 1},
		"tier": 5, "station": &"assembler", "time": 12.0,
		"desc": "Prints matter from a pattern. Do not stand inside."},
		{"id": &"separator", "cost": {&"steel_plate": 10, &"electric_motor": 2, &"glass": 8},
		"tier": 3, "station": &"assembler", "time": 5.0,
		"desc": "Grinds ore into pixels, and things into their parts."},
		{"id": &"centrifuge", "cost": {&"steel_plate": 8, &"electric_motor": 2, &"rubber": 6},
		"tier": 3, "station": &"assembler", "time": 5.0,
		"desc": "Spins a mixture until it gives up its fractions."},
		{"id": &"extractor", "cost": {&"steel_plate": 8, &"circuit_board": 2, &"glass": 6},
		"tier": 4, "station": &"assembler", "time": 5.0},
		{"id": &"generator_coal", "cost": {&"iron_bar": 12, &"copper_wire": 10, &"clay_brick": 8},
		"tier": 1, "station": &"anvil", "time": 3.0},
		{"id": &"generator_solar", "cost": {&"silicon_wafer": 6, &"glass": 12, &"circuit_board": 2},
		"tier": 3, "station": &"assembler", "time": 4.0},
		{"id": &"generator_fusion", "cost": {&"ferozium_bar": 12, &"fusion_core": 1,
		&"quantum_processor": 2},
		"tier": 5, "station": &"replicator", "time": 10.0},
		{"id": &"battery_bank", "cost": {&"dense_energy_cell": 4, &"copper_wire": 12,
		&"steel_plate": 6},
		"tier": 3, "station": &"assembler", "time": 3.0},
		{"id": &"auto_farm", "cost": {&"iron_bar": 10, &"copper_wire": 8, &"watering_can": 1},
		"tier": 3, "station": &"assembler", "time": 4.0},
		{"id": &"medical_station", "cost": {&"steel_plate": 8, &"glass": 8, &"sensor_lens": 1},
		"tier": 4, "station": &"assembler", "time": 5.0},
		{"id": &"upgrade_bench", "cost": {&"durasteel_bar": 12, &"advanced_circuit": 2, &"anvil": 1},
		"tier": 4, "station": &"assembler", "time": 6.0,
		"desc": "Where a good weapon becomes a better one."},
		{"id": &"augment_station", "cost": {&"titanium_bar": 10, &"sensor_lens": 2, &"quartz": 8},
		"tier": 4, "station": &"assembler", "time": 5.0,
		"desc": "Seats an augment into a slot without ruining either."},
		{"id": &"loom", "cost": {&"plank": 12, &"rope": 4, &"iron_gear": 1}, "tier": 1,
		"station": &"workbench", "time": 2.0},
	]
	for m: Dictionary in machines:
		_simple(reg, m, &"machines", &"general", &"workbench")


## The blocks that play with the flip/shift mechanic. Late-game, expensive, and
## the most interesting things in the book.
static func _perspective(reg) -> void:
	var special: Array[Dictionary] = [
		{"id": &"phase_block", "cost": {&"glass": 4, &"aether_dust": 1}, "count": 4,
		"tier": 5, "station": &"replicator",
		"desc": "Solid from one view, air from another."},
		{"id": &"phase_block_inverse", "cost": {&"phase_block": 2, &"void_residue": 1},
		"count": 2, "tier": 5, "station": &"replicator"},
		{"id": &"phase_ladder", "cost": {&"phase_block": 1, &"metal_ladder": 4}, "count": 4,
		"tier": 5, "station": &"replicator"},
		{"id": &"anchor_rune", "cost": {&"ancient_stone": 4, &"prism_shard": 1}, "count": 2,
		"tier": 5, "station": &"replicator", "desc": "Refuses to let the camera turn away."},
		{"id": &"layer_gate", "cost": {&"aegisalt_bar": 4, &"quantum_processor": 1, &"quartz": 8},
		"tier": 5, "station": &"replicator",
		"desc": "Only lets a body through on the layer it was tuned to."},
		{"id": &"shift_pad_deeper", "cost": {&"titanium_bar": 4, &"energy_cell": 2, &"quartz": 4},
		"count": 2, "tier": 4, "station": &"assembler",
		"desc": "Steps whatever stands on it one layer into the screen."},
		{"id": &"shift_pad_nearer", "cost": {&"titanium_bar": 4, &"energy_cell": 2, &"quartz": 4},
		"count": 2, "tier": 4, "station": &"assembler"},
		{"id": &"depth_rail", "cost": {&"steel_plate": 2, &"copper_wire": 4}, "count": 8,
		"tier": 3, "station": &"assembler", "desc": "Carries you along the depth axis."},
		{"id": &"perspective_prism", "cost": {&"prism_shard": 2, &"reinforced_glass": 4},
		"count": 2, "tier": 5, "station": &"replicator",
		"desc": "Bends the sightline around a corner you cannot see."},
		{"id": &"compass_stone", "cost": {&"stone_brick": 8, &"iron_bar": 2, &"quartz": 2},
		"tier": 2, "station": &"workbench",
		"desc": "Always reads the same facing, whichever way you flipped."},
		{"id": &"echo_block", "cost": {&"stone_brick": 4, &"crystal_shard": 2}, "count": 2,
		"tier": 2, "station": &"workbench",
		"desc": "Repeats a sound from the layer behind it."},
		{"id": &"sightline_lamp", "cost": {&"glowstone": 2, &"prism_shard": 1}, "count": 2,
		"tier": 4, "station": &"assembler",
		"desc": "Lights only what the current view can actually see."},
	]
	for s: Dictionary in special:
		_simple(reg, s, &"blocks", &"construction", &"assembler")


static func _teleporters(reg) -> void:
	reg.add(CraftRecipe.make("obj_teleporter_pad", &"assembler")
		.takes(&"durasteel_bar", 12).takes(&"quartz", 12).takes(&"advanced_circuit", 2)
		.takes(&"dense_energy_cell", 2)
		.gives(&"teleporter_pad", 1)
		.lasts(8.0).needs_tier(4)
		.in_category(&"machines").in_group(&"starship")
		.describe("Two-way, once you have linked it to another pad.")
		.learned_from_blueprint(&"blueprint_teleporter"))

	reg.add(CraftRecipe.make("obj_teleporter_beacon", &"assembler")
		.takes(&"iron_bar", 8).takes(&"beacon_shard", 1).takes(&"circuit_board", 2)
		.gives(&"teleporter_beacon", 2)
		.lasts(4.0).needs_tier(4)
		.in_category(&"machines").in_group(&"starship")
		.describe("A cheap one-way anchor you can beam down to.")
		.learned_from_material(&"beacon_shard"))

	reg.add(CraftRecipe.make("obj_ship_locker", &"assembler")
		.takes(&"durasteel_bar", 10).takes(&"circuit_board", 2)
		.gives(&"ship_locker", 1)
		.lasts(5.0).needs_tier(4)
		.in_category(&"furniture").in_group(&"starship")
		.describe("Shares its contents with your ship's hold.")
		.learned_at_tier(4))

	reg.add(CraftRecipe.make("obj_flag_beacon", &"workbench")
		.takes(&"cloth", 6).takes(&"plank", 4).gives(&"flag_beacon", 1)
		.in_category(&"furniture").in_group(&"furnishing")
		.describe("Marks a spot you will otherwise never find again.")
		.known_at_start())


## Shared helper: one "spend materials, get a placeable" recipe.
## Keys: id, cost (required), count, tier, station, time, name, desc, start.
static func _simple(reg, d: Dictionary, cat: StringName, group: StringName,
		default_station: StringName) -> void:
	var tier := int(d.get("tier", 0))
	var r := CraftRecipe.make("obj_%s" % d["id"], StringName(d.get("station", default_station))) \
		.gives(StringName(d["id"]), int(d.get("count", 1))) \
		.lasts(float(d.get("time", 1.0 + float(tier) * 0.5))) \
		.needs_tier(tier) \
		.in_category(cat).in_group(group) \
		.ordered(tier * 10) \
		.describe(String(d.get("desc", "")))
	if d.has("name"):
		r.named(String(d["name"]))
	var cost: Dictionary = d["cost"]
	var first: StringName = &""
	for k: StringName in cost:
		r.takes(k, int(cost[k]))
		if first == &"":
			first = k
	if bool(d.get("start", false)):
		r.known_at_start()
	elif tier >= 3:
		r.learned_at_tier(tier)
	else:
		r.learned_from_material(first)
	reg.add(r)
