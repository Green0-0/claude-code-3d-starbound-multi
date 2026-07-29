## Kitchen and chemistry recipes.
##
## Every output id here is a real consumable from `content/items/40_food.gd`,
## and every crop input is a `produce` id from `SrvFarming.crop_table()`
## (`wheat corn rice potato carrot tomato chili grapes banana pineapple kiwi
## cotton sugarcane coffee_beans avesmingo boneboo currentcorn feathercrown
## neonmelon toxictop reefpod` …). Buffs and spoilage are the survival agent's
## business — this file only decides what combines into what.
##
## Meals are deliberately expensive in ingredient [i]variety[/i] rather than
## volume, so farming several crops is worthwhile.
extends RefCounted

static func register_all(reg) -> void:
	_ingredients(reg)
	_cooked(reg)
	_drinks(reg)
	_preserved(reg)
	_perfect_meals(reg)
	_medicine(reg)
	_farming(reg)


static func _ingredients(reg) -> void:
	var rows: Array[Dictionary] = [
		{"id": &"flour", "cost": {&"wheat": 3}, "count": 2, "time": 1.0,
		"desc": "Milled fine. Half the kitchen depends on it."},
		{"id": &"dough", "cost": {&"flour": 2, &"water_flask": 1}, "count": 2, "time": 1.0},
		{"id": &"butter", "cost": {&"milk": 2}, "time": 2.0},
		{"id": &"cheese", "cost": {&"milk": 3, &"salt": 1}, "count": 2, "time": 4.0},
		{"id": &"sugar", "cost": {&"sugarcane": 3}, "count": 2, "time": 1.0},
		{"id": &"oil", "cost": {&"pearlpea": 4}, "count": 2, "time": 2.0,
		"desc": "Pressed, strained and bottled."},
	]
	for d: Dictionary in rows:
		_kitchen(reg, d, 0)


static func _cooked(reg) -> void:
	var meals: Array[Dictionary] = [
		{"id": &"toast", "tier": 0, "time": 1.0, "cost": {&"bread": 1}},
		{"id": &"chips", "tier": 0, "time": 2.0, "cost": {&"potato": 2, &"oil": 1}},
		{"id": &"popcorn", "tier": 0, "time": 1.5, "cost": {&"corn": 2, &"oil": 1}},
		{"id": &"corn_cob", "tier": 0, "time": 1.5, "cost": {&"corn": 1, &"butter": 1}},
		{"id": &"tomato_soup", "tier": 0, "time": 2.5, "cost": {&"tomato": 3, &"salt": 1}},
		{"id": &"carrot_soup", "tier": 0, "time": 2.5, "cost": {&"carrot": 3, &"butter": 1}},
		{"id": &"veggie_stew", "tier": 0, "time": 3.0,
		"cost": {&"potato": 2, &"carrot": 2, &"tomato": 1},
		"desc": "Slow-burning. Regenerates health while it lasts."},
		{"id": &"meat_stew", "tier": 1, "time": 3.5,
		"cost": {&"cooked_meat": 2, &"potato": 2, &"salt": 1},
		"desc": "Restores a lot, slowly."},
		{"id": &"rice_bowl", "tier": 0, "time": 2.0, "cost": {&"rice": 3, &"salt": 1}},
		{"id": &"risotto", "tier": 1, "time": 3.5,
		"cost": {&"rice": 3, &"cheese": 1, &"butter": 1, &"cave_mushroom": 2}},
		{"id": &"sushi", "tier": 1, "time": 3.0,
		"cost": {&"rice": 2, &"raw_fish": 2, &"kelp": 1}},
		{"id": &"reef_chowder", "tier": 2, "time": 3.5,
		"cost": {&"grilled_fish": 2, &"reefpod": 2, &"milk": 1}},
		{"id": &"chili_bowl", "tier": 1, "time": 3.0,
		"cost": {&"chili": 2, &"pearlpea": 2, &"tomato": 1},
		"desc": "Grants temporary cold resistance. Aggressively."},
		{"id": &"pancakes", "tier": 1, "time": 2.5,
		"cost": {&"flour": 2, &"egg": 2, &"milk": 1, &"honey": 1}},
		{"id": &"banana_bread", "tier": 1, "time": 4.0,
		"cost": {&"banana": 3, &"flour": 2, &"sugar": 1}},
		{"id": &"pineapple_cake", "tier": 2, "time": 5.0,
		"cost": {&"pineapple": 2, &"flour": 3, &"sugar": 3, &"egg": 2},
		"desc": "A whole cake. You have earned it."},
		{"id": &"fruit_salad", "tier": 0, "time": 1.5,
		"cost": {&"wild_berries": 2, &"kiwi": 1, &"banana": 1}},
		{"id": &"neon_sorbet", "tier": 3, "time": 3.0,
		"cost": {&"neonmelon": 2, &"ice_crystal": 2, &"sugar": 2},
		"desc": "Grants temporary heat resistance."},
		{"id": &"toxic_skewer", "tier": 3, "time": 3.5,
		"cost": {&"toxictop": 2, &"cooked_alien_meat": 1, &"stick": 1},
		"desc": "Unfamiliar protein. Surprising buffs."},
		{"id": &"boneboo_broth", "tier": 3, "time": 4.0,
		"cost": {&"boneboo": 3, &"bone_meal": 1, &"salt": 1}},
		{"id": &"feather_omelette", "tier": 2, "time": 2.5,
		"cost": {&"feathercrown": 2, &"egg": 3, &"butter": 1}},
		{"id": &"currentcorn_fritters", "tier": 3, "time": 3.0,
		"cost": {&"currentcorn": 3, &"flour": 2, &"oil": 1}},
		{"id": &"deepstone_roast", "tier": 4, "time": 5.0,
		"cost": {&"cooked_meat": 3, &"dirturchin": 2, &"cave_mushroom": 2, &"salt": 2}},
		{"id": &"emberheart_curry", "tier": 4, "time": 5.0,
		"cost": {&"chili": 3, &"cooked_alien_meat": 2, &"rice": 2, &"oil": 1}},
	]
	for m: Dictionary in meals:
		_kitchen(reg, m, 10)


static func _drinks(reg) -> void:
	var drinks: Array[Dictionary] = [
		{"id": &"water_flask", "tier": 0, "time": 0.5, "cost": {&"glass": 1, &"ice": 2},
		"desc": "Melted, filtered, drinkable."},
		{"id": &"coffee", "tier": 1, "time": 2.0, "cost": {&"coffee_beans": 2, &"water_flask": 1},
		"desc": "Move faster. Regret it later."},
		{"id": &"tea", "tier": 1, "time": 2.0, "cost": {&"wartweed": 2, &"water_flask": 1}},
		{"id": &"grape_juice", "tier": 0, "time": 1.5, "cost": {&"grapes": 4, &"water_flask": 1}},
		{"id": &"kiwi_juice", "tier": 0, "time": 1.5, "cost": {&"kiwi": 4, &"water_flask": 1}},
		{"id": &"pineapple_juice", "tier": 0, "time": 1.5, "cost": {&"pineapple": 2, &"water_flask": 1}},
		{"id": &"avesmingo_juice", "tier": 2, "time": 2.0, "cost": {&"avesmingo": 3, &"sugar": 1}},
		{"id": &"neon_soda", "tier": 3, "time": 2.0,
		"cost": {&"neonmelon": 2, &"sugar": 2, &"water_flask": 1}},
		{"id": &"milkshake", "tier": 1, "time": 2.0, "cost": {&"milk": 2, &"wild_berries": 2, &"sugar": 1}},
		{"id": &"wine", "tier": 2, "time": 8.0, "cost": {&"grapes": 6, &"sugar": 2},
		"desc": "Time does most of the work. You provide the grapes."},
		{"id": &"reef_tonic", "tier": 3, "time": 3.0, "cost": {&"coralcreep": 2, &"reefpod": 1, &"water_flask": 1}},
		{"id": &"ash_cordial", "tier": 3, "time": 3.0, "cost": {&"ash": 2, &"wild_berries": 3, &"sugar": 2}},
	]
	for d: Dictionary in drinks:
		_kitchen(reg, d, 20)


## Preserved goods: the answer to spoilage. Cheap nutrition, long shelf life.
static func _preserved(reg) -> void:
	var rows: Array[Dictionary] = [
		{"id": &"jerky", "tier": 1, "time": 4.0, "cost": {&"raw_meat": 3, &"salt": 2},
		"desc": "Keeps for a season. Chews like a boot."},
		{"id": &"dried_fruit", "tier": 0, "time": 3.0, "cost": {&"wild_berries": 4, &"sugar": 1}},
		{"id": &"pickles", "tier": 0, "time": 3.0, "cost": {&"carrot": 2, &"salt": 2, &"water_flask": 1}},
		{"id": &"canned_stew", "tier": 2, "time": 4.0,
		"cost": {&"meat_stew": 1, &"tin_bar": 1, &"salt": 1}},
		{"id": &"salt_fish", "tier": 1, "time": 3.0, "cost": {&"raw_fish": 2, &"salt": 2}},
		{"id": &"grape_jam", "tier": 1, "time": 3.0, "cost": {&"grapes": 4, &"sugar": 2}},
		{"id": &"hardtack", "tier": 0, "time": 3.0, "cost": {&"flour": 3, &"salt": 1},
		"desc": "Immortal. Barely food."},
		{"id": &"trail_mix", "tier": 1, "time": 2.0,
		"cost": {&"dried_fruit": 1, &"pearlpea": 2, &"honey": 1}},
		{"id": &"honeyed_nuts", "tier": 1, "time": 2.0, "cost": {&"honey": 2, &"beakseed": 3}},
		{"id": &"ration_bar", "tier": 3, "time": 4.0,
		"cost": {&"hardtack": 1, &"jerky": 1, &"dried_fruit": 1, &"honey": 1},
		"desc": "Keeps forever. Tastes like it."},
	]
	for d: Dictionary in rows:
		_kitchen(reg, d, 30)


## The six payoff dishes. Expensive, slow, and worth building a kitchen for.
static func _perfect_meals(reg) -> void:
	var rows: Array[Dictionary] = [
		{"id": &"harvest_feast", "tier": 3, "time": 12.0,
		"cost": {&"veggie_stew": 1, &"pineapple_cake": 1, &"pancakes": 1, &"wine": 1},
		"desc": "Everything the farm gave you, on one table."},
		{"id": &"voidfarer_platter", "tier": 5, "time": 15.0,
		"cost": {&"cooked_alien_meat": 3, &"toxic_skewer": 1, &"neon_sorbet": 1,
		&"quantum_fluid": 1},
		"desc": "Food from four worlds that should not share a plate."},
		{"id": &"tidecaller_banquet", "tier": 4, "time": 14.0,
		"cost": {&"reef_chowder": 1, &"sushi": 1, &"reef_tonic": 1, &"kelp": 4}},
		{"id": &"planeshifter_supper", "tier": 6, "time": 20.0,
		"cost": {&"harvest_feast": 1, &"voidfarer_platter": 1, &"tidecaller_banquet": 1,
		&"prism_shard": 1},
		"desc": "Eat it before a flip. You will see why."},
	]
	for d: Dictionary in rows:
		_kitchen(reg, d, 40)


## Chemistry-lab consumables.
static func _medicine(reg) -> void:
	var meds: Array[Dictionary] = [
		{"id": &"bandage", "tier": 0, "station": &"workbench", "time": 0.8,
		"cost": {&"cloth": 1, &"plant_fibre": 2}, "count": 2, "start": true,
		"desc": "Stops the bleeding. Does not stop the monster."},
		{"id": &"sterile_bandage", "tier": 2, "time": 1.5,
		"cost": {&"bandage": 2, &"antibiotics": 1}},
		{"id": &"medkit", "tier": 3, "time": 4.0,
		"cost": {&"sterile_bandage": 2, &"antibiotics": 1, &"cloth": 2}},
		{"id": &"antidote", "tier": 2, "time": 3.0,
		"cost": {&"wartweed": 2, &"charcoal": 2, &"water_flask": 1},
		"desc": "Charcoal takes the poison out of you the crude way."},
		{"id": &"antirad", "tier": 4, "time": 3.0,
		"cost": {&"wartweed": 2, &"lead_bar": 1, &"salt": 1}},
		{"id": &"antibiotics", "tier": 3, "time": 3.5,
		"cost": {&"cave_mushroom": 3, &"honey": 1, &"water_flask": 1}},
		{"id": &"panacea", "tier": 6, "time": 10.0,
		"cost": {&"medkit": 1, &"antidote": 1, &"antirad": 1, &"starlight_essence": 1},
		"desc": "Cures everything. Once."},
		{"id": &"combat_stim", "tier": 4, "time": 3.0,
		"cost": {&"venom_gland": 1, &"sugar": 2, &"water_flask": 1}},
		{"id": &"guard_stim", "tier": 4, "time": 3.0,
		"cost": {&"chitin": 2, &"sugar": 2, &"water_flask": 1}},
		{"id": &"focus_stim", "tier": 4, "time": 3.0,
		"cost": {&"luminous_powder": 1, &"coffee": 1, &"water_flask": 1}},
		{"id": &"warming_salve", "tier": 2, "time": 2.5,
		"cost": {&"chili": 2, &"tallow": 2}},
		{"id": &"cooling_gel", "tier": 2, "time": 2.5,
		"cost": {&"ice_crystal": 2, &"resin": 2}},
	]
	for m: Dictionary in meds:
		var station := StringName(m.get("station", &"chemistry"))
		var r := CraftRecipe.make("chem_%s" % m["id"], station) \
			.gives(StringName(m["id"]), int(m.get("count", 1))) \
			.lasts(float(m["time"])) \
			.needs_tier(int(m["tier"])) \
			.in_category(&"food").in_group(&"chemistry") \
			.ordered(int(m["tier"]) * 10 + 50) \
			.describe(String(m.get("desc", "")))
		var cost: Dictionary = m["cost"]
		var first: StringName = &""
		for k: StringName in cost:
			r.takes(k, int(cost[k]))
			if first == &"":
				first = k
		if bool(m.get("start", false)):
			r.known_at_start()
		else:
			r.learned_from_material(first)
		reg.add(r)


static func _farming(reg) -> void:
	reg.add(CraftRecipe.make("fertiliser", &"workbench")
		.takes(&"bone_meal", 2).takes(&"plant_matter", 3).takes(&"ash", 1)
		.gives(&"fertiliser", 3)
		.in_category(&"food").in_group(&"general")
		.describe("Crops adore it. So do the things that eat crops.")
		.learned_from_material(&"bone_meal"))

	reg.add(CraftRecipe.make("bone_meal_grind", &"workbench")
		.takes(&"bone", 1).gives(&"bone_meal", 3)
		.in_category(&"materials").in_group(&"general")
		.learned_from_material(&"bone"))

	reg.add(CraftRecipe.make("compost", &"workbench")
		.takes(&"plant_matter", 6).takes(&"dirt", 2).gives(&"rich_soil", 4)
		.lasts(2.0)
		.in_category(&"blocks").in_group(&"general")
		.learned_from_material(&"plant_matter"))

	reg.add(CraftRecipe.make("greenhouse_kit", &"assembler")
		.takes(&"glass", 16).takes(&"iron_bar", 8).takes(&"fertiliser", 4)
		.gives(&"greenhouse_kit", 1)
		.lasts(5.0).needs_tier(3)
		.in_category(&"machines").in_group(&"general")
		.describe("Crops grow whatever the sky is doing.")
		.learned_at_tier(3))


## Shared kitchen helper. `order_base` separates ingredients / dishes / drinks /
## preserves / feasts in the category list.
static func _kitchen(reg, d: Dictionary, order_base: int) -> void:
	var tier := int(d.get("tier", 0))
	var r := CraftRecipe.make("meal_%s" % d["id"], &"kitchen") \
		.gives(StringName(d["id"]), int(d.get("count", 1))) \
		.lasts(float(d.get("time", 2.0))) \
		.needs_tier(tier) \
		.in_category(&"food").in_group(&"cooking") \
		.ordered(order_base + tier) \
		.describe(String(d.get("desc", "")))
	var cost: Dictionary = d["cost"]
	var first: StringName = &""
	for k: StringName in cost:
		if int(cost[k]) <= 0:
			continue
		r.takes(k, int(cost[k]))
		if first == &"":
			first = k
	r.learned_from_material(first)
	reg.add(r)
