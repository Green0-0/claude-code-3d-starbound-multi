## Food, drink and medicine.
##
## ## Layout
##
## 1. **Raw produce** — generated straight from `SrvFarming.crop_table()`, so a
##    new crop needs no edit here. Ids are the row's `produce` (usually the crop
##    name itself: `wheat`, `tomato`, `neonmelon`).
## 2. **Foraged staples** — meat, fish, eggs, milk, honey. Registered defensively
##    in case the monster/fishing agents got there first.
## 3. **Cooked dishes** — the `kitchen` station's output.
## 4. **Drinks** — tagged `drink`, they fill thirst rather than hunger.
## 5. **Preserved goods** — long shelf life, lower nutrition. The answer to
##    spoilage.
## 6. **Perfect meals** — six multi-ingredient dishes tagged `perfect_meal`.
##    Eating one grants `feast` on top of its own effects. These are the payoff
##    for the crafting agent's high-tier `kitchen` recipes.
## 7. **Medicine** — bandages, medkits, antidotes, stims and the panacea. They
##    live here because they are consumables and share the same use plumbing.
##
## ## Conventions
##
## * every consumable's `on_use` goes through `Status.cooking.consume()` (or
##   `Status.medical` for medicine), so the eating gate, spoilage and buff
##   application are all in one place;
## * anything that rots carries the `perishable` tag and a `shelf_life` bonus in
##   seconds of world time — `survival/cooking.gd` reads both;
## * `category` is `food`, `drink`, `ingredient` or `medical`;
## * status effects are attached with `.with_effect(id, duration)` using the ids
##   from `survival/effects/`.
extends RefCounted

## Shelf lives, in seconds of world time (a day is ~480s).
const SHELF_RAW := 900.0
const SHELF_COOKED := 1500.0
const SHELF_PRESERVED := 12000.0


static func register_all(reg) -> void:
	_raw_produce(reg)
	_foraged(reg)
	_ingredients(reg)
	_cooked(reg)
	_drinks(reg)
	_preserved(reg)
	_perfect_meals(reg)
	_medicine(reg)


# =================================================================== builders
## Route a consumable through the cooking runtime. Guarded so the item still
## works (as a no-op) if the survival module is ever swapped out.
static func _eat_hook(id: StringName) -> Callable:
	return func(player: Node, ctx: Dictionary) -> bool:
		if Status != null and Status.cooking != null:
			return Status.cooking.consume(id, player, ctx)
		return false


static func _food(reg, id: StringName, display: String, food: float, heal: float,
		col: Color, desc: String, extra: Dictionary = {}) -> ItemType:
	if reg.has(id):
		var existing: ItemType = reg.get_type(id)
		return existing
	var it: ItemType = reg.define(id, display)
	it.as_food(food, heal)
	it.look(col, StringName(extra.get("shape", &"round")))
	it.describe(desc)
	it.worth(int(extra.get("value", maxi(2, int(food)))), int(extra.get("rarity", Const.RARITY_COMMON)))
	it.in_category(StringName(extra.get("category", &"food")))
	it.stacks(int(extra.get("stack", 50)))
	it.tag(&"food")
	for t in extra.get("tags", []):
		it.tag(StringName(t))
	var shelf := float(extra.get("shelf", SHELF_COOKED))
	if shelf > 0.0:
		it.tag(&"perishable")
		it.bonus("shelf_life", shelf)
	for e in extra.get("effects", []):
		var pair: Array = e
		it.with_effect(StringName(pair[0]), float(pair[1]))
	it.on_use = _eat_hook(id)
	return it


static func _drink(reg, id: StringName, display: String, hydration: float, heal: float,
		col: Color, desc: String, extra: Dictionary = {}) -> ItemType:
	var e := extra.duplicate()
	e["category"] = e.get("category", &"drink")
	e["shape"] = e.get("shape", &"flask")
	var tags: Array = e.get("tags", []).duplicate()
	tags.append(&"drink")
	e["tags"] = tags
	e["stack"] = e.get("stack", 20)
	return _food(reg, id, display, hydration, heal, col, desc, e)


# =============================================================== raw produce
## One item per crop row. Crops flagged `material` become ingredients rather
## than food, but they are still registered here so the whole harvest chain is
## defined in one file.
static func _raw_produce(reg) -> void:
	for row: Dictionary in SrvFarming.crop_table():
		var id: StringName = row["produce"]
		if reg.has(id):
			continue
		var col: Color = row["ripe"]
		if bool(row["material"]):
			var mat: ItemType = reg.define(id, String(row["produce_name"]))
			mat.of_kind(ItemType.Kind.MATERIAL).look(col, &"round")
			mat.describe("Harvested %s." % String(row["name"]).to_lower())
			mat.worth(int(row["value"]), int(row["rarity"]))
			mat.in_category(&"ingredient").tag(&"produce").tag(&"ingredient")
			mat.tag(StringName("crop_" + String(row["id"])))
			continue
		var effects: Array = []
		for e in row["effects"]:
			effects.append(e)
		_food(reg, id, String(row["produce_name"]), float(row["food"]), float(row["heal"]),
			col, "Freshly picked %s." % String(row["name"]).to_lower(),
			{"value": int(row["value"]), "rarity": int(row["rarity"]),
				"shelf": SHELF_RAW, "effects": effects,
				"tags": [&"produce", &"raw", StringName("crop_" + String(row["id"]))]})


# ============================================================ foraged staples
static func _foraged(reg) -> void:
	_food(reg, &"raw_meat", "Raw Meat", 8.0, 0.0, Color(0.82, 0.36, 0.36),
		"Better cooked. Much better cooked.", {"shelf": 600.0,
			"tags": [&"meat", &"raw"], "effects": [[&"poisoned", 6.0]], "value": 5})
	_food(reg, &"raw_alien_meat", "Alien Flesh", 9.0, 0.0, Color(0.62, 0.38, 0.72),
		"It is still faintly warm and you did not cook it.", {"shelf": 600.0,
			"tags": [&"meat", &"raw"], "effects": [[&"poisoned", 10.0]], "value": 7})
	_food(reg, &"raw_fish", "Raw Fish", 7.0, 0.0, Color(0.62, 0.74, 0.82),
		"Slippery and staring at you.", {"shelf": 600.0,
			"tags": [&"fish", &"raw"], "value": 5})
	_food(reg, &"egg", "Egg", 6.0, 1.0, Color(0.96, 0.93, 0.84),
		"Somebody's breakfast.", {"shelf": 1200.0, "tags": [&"ingredient"], "value": 4})
	_food(reg, &"honey", "Honey", 10.0, 2.0, Color(0.92, 0.70, 0.18),
		"Sweet, sticky and keeps almost forever.", {"shelf": SHELF_PRESERVED,
			"tags": [&"ingredient", &"sweet"], "value": 8})
	_food(reg, &"wild_berries", "Wild Berries", 6.0, 1.0, Color(0.72, 0.20, 0.42),
		"Foraged from a hedge. Probably fine.", {"shelf": SHELF_RAW,
			"tags": [&"produce", &"raw"], "value": 3})
	_food(reg, &"cave_mushroom", "Cave Mushroom", 5.0, 0.0, Color(0.72, 0.66, 0.56),
		"Grew somewhere dark and damp.", {"shelf": SHELF_RAW,
			"tags": [&"produce", &"fungus"], "effects": [[&"night_vision", 30.0]], "value": 4})


# ================================================================ ingredients
## Non-edible cooking inputs. The kitchen recipes consume these.
static func _ingredients(reg) -> void:
	for spec in [
		[&"flour", "Flour", Color(0.94, 0.90, 0.80), "Milled grain."],
		[&"dough", "Dough", Color(0.90, 0.84, 0.68), "Flour, water, patience."],
		[&"sugar", "Sugar", Color(0.97, 0.96, 0.94), "Refined from sugarcane."],
		[&"salt", "Salt", Color(0.95, 0.95, 0.97), "Preserves almost anything."],
		[&"oil", "Cooking Oil", Color(0.88, 0.78, 0.30), "Pressed from seeds."],
		[&"butter", "Butter", Color(0.96, 0.88, 0.52), "Churned from milk."],
		[&"cheese", "Cheese", Color(0.94, 0.82, 0.36), "Aged, and all the better for it."],
		[&"rotten_food", "Rotten Food", Color(0.42, 0.44, 0.28), "It got away from you."],
	]:
		var id: StringName = spec[0]
		if reg.has(id):
			continue
		var col: Color = spec[2]
		var it: ItemType = reg.define(id, String(spec[1]))
		it.of_kind(ItemType.Kind.MATERIAL).look(col, &"square")
		it.describe(String(spec[3])).worth(3)
		it.in_category(&"ingredient").tag(&"ingredient")
	# Rotten food is edible, in the sense that you can put it in your mouth.
	var rot: ItemType = reg.get_type(&"rotten_food")
	if rot != null:
		rot.as_food(3.0, 0.0)
		rot.with_effect(&"poisoned", 14.0)
		rot.in_category(&"food").tag(&"food")
		rot.on_use = _eat_hook(&"rotten_food")
	# Cheese and butter spoil like everything else dairy.
	for dairy: StringName in [&"cheese", &"butter"]:
		var d: ItemType = reg.get_type(dairy)
		if d != null:
			d.tag(&"perishable").bonus("shelf_life", SHELF_PRESERVED * 0.4)


# ============================================================== cooked dishes
static func _cooked(reg) -> void:
	_food(reg, &"bread", "Bread", 22.0, 3.0, Color(0.84, 0.66, 0.36),
		"A whole loaf. The backbone of every expedition.",
		{"value": 12, "shelf": SHELF_COOKED, "tags": [&"cooked", &"baked"]})
	_food(reg, &"toast", "Toast", 12.0, 1.0, Color(0.80, 0.60, 0.32),
		"Bread, but braver.", {"value": 7, "tags": [&"cooked", &"baked"]})
	_food(reg, &"cooked_meat", "Cooked Meat", 24.0, 6.0, Color(0.66, 0.34, 0.20),
		"Charred outside, perfect inside.",
		{"value": 14, "tags": [&"cooked", &"meat"], "effects": [[&"strength", 60.0]]})
	_food(reg, &"cooked_alien_meat", "Seared Alien Flesh", 26.0, 6.0, Color(0.56, 0.30, 0.60),
		"Whatever it was, heat fixed it.",
		{"value": 18, "tags": [&"cooked", &"meat"], "effects": [[&"strength", 45.0]]})
	_food(reg, &"grilled_fish", "Grilled Fish", 20.0, 5.0, Color(0.74, 0.72, 0.56),
		"Crisp skin, flaking flesh.",
		{"value": 13, "tags": [&"cooked", &"fish"], "effects": [[&"breathing", 45.0]]})
	_food(reg, &"fried_egg", "Fried Egg", 13.0, 2.0, Color(0.98, 0.88, 0.42),
		"Sunny side, obviously.", {"value": 8, "tags": [&"cooked"]})
	_food(reg, &"boiled_egg", "Boiled Egg", 11.0, 1.0, Color(0.96, 0.94, 0.88),
		"Portable protein.", {"value": 7, "tags": [&"cooked"], "shelf": SHELF_PRESERVED * 0.3})
	_food(reg, &"baked_potato", "Baked Potato", 20.0, 3.0, Color(0.80, 0.66, 0.40),
		"Split it and put butter in it.", {"value": 10, "tags": [&"cooked"]})
	_food(reg, &"chips", "Fried Potato", 17.0, 2.0, Color(0.92, 0.78, 0.36),
		"Salt-scattered and dangerously moreish.",
		{"value": 11, "tags": [&"cooked"], "effects": [[&"haste", 45.0]]})
	_food(reg, &"corn_cob", "Corn On The Cob", 18.0, 2.0, Color(0.96, 0.84, 0.28),
		"Grilled until the kernels pop.", {"value": 10, "tags": [&"cooked"]})
	_food(reg, &"popcorn", "Popcorn", 9.0, 0.0, Color(0.97, 0.94, 0.84),
		"Somehow always half air.", {"value": 6, "tags": [&"cooked"], "shelf": SHELF_PRESERVED * 0.4})
	_food(reg, &"tomato_soup", "Tomato Soup", 21.0, 8.0, Color(0.84, 0.26, 0.20),
		"Hot enough to hold off the cold.",
		{"value": 15, "tags": [&"cooked", &"soup"], "effects": [[&"ice_resistance", 120.0]]})
	_food(reg, &"carrot_soup", "Carrot Soup", 19.0, 6.0, Color(0.92, 0.56, 0.22),
		"Sweet, thick and good for the eyes.",
		{"value": 14, "tags": [&"cooked", &"soup"], "effects": [[&"night_vision", 180.0]]})
	_food(reg, &"reef_chowder", "Reef Chowder", 25.0, 9.0, Color(0.52, 0.76, 0.72),
		"Reefpod and fish in a thick broth.",
		{"value": 22, "tags": [&"cooked", &"soup"], "effects": [[&"breathing", 150.0]]})
	_food(reg, &"veggie_stew", "Vegetable Stew", 26.0, 7.0, Color(0.62, 0.52, 0.26),
		"Whatever the plot gave you, in one pot.",
		{"value": 18, "tags": [&"cooked", &"soup"]})
	_food(reg, &"meat_stew", "Meat Stew", 32.0, 12.0, Color(0.56, 0.32, 0.20),
		"Slow-cooked until it gives up.",
		{"value": 26, "tags": [&"cooked", &"soup"],
			"effects": [[&"strength", 120.0], [&"defense_up", 90.0]]})
	_food(reg, &"rice_bowl", "Rice Bowl", 20.0, 3.0, Color(0.92, 0.90, 0.78),
		"Plain, filling, reliable.", {"value": 11, "tags": [&"cooked"]})
	_food(reg, &"risotto", "Risotto", 28.0, 6.0, Color(0.90, 0.84, 0.58),
		"Stirred with more attention than the situation warranted.",
		{"value": 22, "tags": [&"cooked"], "effects": [[&"regeneration", 40.0]]})
	_food(reg, &"sushi", "Sushi", 24.0, 8.0, Color(0.86, 0.62, 0.60),
		"Rice, raw fish, steady hands.",
		{"value": 24, "tags": [&"cooked", &"fish"], "shelf": 700.0,
			"effects": [[&"haste", 90.0]]})
	_food(reg, &"pancakes", "Pancakes", 23.0, 4.0, Color(0.92, 0.78, 0.46),
		"Stacked, buttered, drowned in honey.",
		{"value": 17, "tags": [&"cooked", &"baked", &"sweet"]})
	_food(reg, &"banana_bread", "Banana Bread", 27.0, 5.0, Color(0.84, 0.72, 0.40),
		"Dense, sweet, keeps for days.",
		{"value": 20, "tags": [&"cooked", &"baked", &"sweet"], "shelf": SHELF_PRESERVED * 0.5})
	_food(reg, &"fruit_salad", "Fruit Salad", 21.0, 6.0, Color(0.88, 0.52, 0.62),
		"Everything sweet the plot produced, diced.",
		{"value": 19, "tags": [&"cooked", &"sweet"], "shelf": SHELF_RAW,
			"effects": [[&"regeneration", 30.0]]})
	_food(reg, &"pineapple_cake", "Pineapple Cake", 30.0, 8.0, Color(0.94, 0.80, 0.36),
		"Upside down, on purpose.",
		{"value": 28, "tags": [&"cooked", &"baked", &"sweet"],
			"effects": [[&"well_fed", 300.0], [&"lucky", 120.0]]})
	_food(reg, &"neon_sorbet", "Neon Sorbet", 18.0, 4.0, Color(0.42, 1.0, 0.62),
		"Glows faintly. Tastes like limes and static.",
		{"value": 26, "rarity": Const.RARITY_UNCOMMON, "tags": [&"cooked", &"sweet"],
			"effects": [[&"night_vision", 240.0], [&"glowing", 120.0]]})
	_food(reg, &"chili_bowl", "Bowl Of Chili", 26.0, 6.0, Color(0.78, 0.20, 0.14),
		"Three kinds of heat and one kind of regret.",
		{"value": 21, "tags": [&"cooked", &"soup"],
			"effects": [[&"fire_resistance", 180.0], [&"strength", 60.0]]})
	_food(reg, &"toxic_skewer", "Toxictop Skewer", 22.0, 0.0, Color(0.66, 0.86, 0.26),
		"Roasting burns off most of the poison. Most.",
		{"value": 18, "tags": [&"cooked"],
			"effects": [[&"poison_resistance", 150.0]]})
	_food(reg, &"boneboo_broth", "Boneboo Broth", 24.0, 14.0, Color(0.86, 0.84, 0.74),
		"Marrow-rich and faintly chalky. Sets you up.",
		{"value": 26, "rarity": Const.RARITY_UNCOMMON, "tags": [&"cooked", &"soup"],
			"effects": [[&"defense_up", 180.0], [&"fortified", 30.0]]})
	_food(reg, &"feather_omelette", "Feathercrown Omelette", 25.0, 5.0, Color(0.94, 0.92, 0.86),
		"Impossibly light. So are you, briefly.",
		{"value": 25, "rarity": Const.RARITY_UNCOMMON, "tags": [&"cooked"],
			"effects": [[&"gravity_reduced", 120.0]]})
	_food(reg, &"currentcorn_fritters", "Currentcorn Fritters", 23.0, 4.0, Color(0.52, 0.86, 0.98),
		"They crackle on the way down.",
		{"value": 24, "rarity": Const.RARITY_UNCOMMON, "tags": [&"cooked"],
			"effects": [[&"energised", 180.0], [&"electric_resistance", 120.0]]})


# ====================================================================== drinks
static func _drinks(reg) -> void:
	_drink(reg, &"water_flask", "Flask Of Water", 30.0, 0.0, Color(0.36, 0.66, 0.95),
		"Clean, cold and the single most underrated item you own.",
		{"value": 4, "shelf": 0.0})
	_drink(reg, &"coffee", "Coffee", 18.0, 0.0, Color(0.36, 0.22, 0.14),
		"Bitter, black and load-bearing.",
		{"value": 14, "tags": [&"stimulant"],
			"effects": [[&"energised", 240.0], [&"haste", 90.0]]})
	_drink(reg, &"tea", "Herbal Tea", 22.0, 4.0, Color(0.72, 0.62, 0.30),
		"Steeped wartweed. Calming, and it settles a stomach.",
		{"value": 12, "effects": [[&"poison_resistance", 120.0], [&"regeneration", 20.0]]})
	_drink(reg, &"milk", "Milk", 24.0, 3.0, Color(0.96, 0.95, 0.92),
		"Cuts through anything spicy.",
		{"value": 8, "shelf": 900.0, "tags": [&"ingredient"]})
	_drink(reg, &"grape_juice", "Grape Juice", 26.0, 2.0, Color(0.56, 0.24, 0.62),
		"Pressed this morning.", {"value": 12, "shelf": SHELF_COOKED})
	_drink(reg, &"kiwi_juice", "Kiwi Juice", 25.0, 3.0, Color(0.60, 0.72, 0.34),
		"Sharp enough to wake you up.", {"value": 12, "shelf": SHELF_COOKED})
	_drink(reg, &"pineapple_juice", "Pineapple Juice", 27.0, 3.0, Color(0.94, 0.78, 0.28),
		"Tropical, in the middle of nowhere.", {"value": 13, "shelf": SHELF_COOKED})
	_drink(reg, &"avesmingo_juice", "Avesmingo Juice", 28.0, 5.0, Color(0.99, 0.62, 0.30),
		"Tastes like running downhill.",
		{"value": 20, "rarity": Const.RARITY_UNCOMMON, "shelf": SHELF_COOKED,
			"effects": [[&"haste", 180.0]]})
	_drink(reg, &"neon_soda", "Neonmelon Soda", 30.0, 2.0, Color(0.36, 1.0, 0.60),
		"Fizzes with something that is probably not carbonation.",
		{"value": 22, "rarity": Const.RARITY_UNCOMMON,
			"effects": [[&"night_vision", 180.0], [&"energised", 120.0]]})
	_drink(reg, &"milkshake", "Milkshake", 32.0, 6.0, Color(0.94, 0.84, 0.78),
		"Thick enough to stand a spoon in.",
		{"value": 20, "shelf": 900.0, "effects": [[&"well_fed", 240.0]]})
	_drink(reg, &"wine", "Wine", 20.0, 4.0, Color(0.52, 0.14, 0.24),
		"Aged in a cellar you dug yourself.",
		{"value": 30, "rarity": Const.RARITY_UNCOMMON, "shelf": 0.0,
			"effects": [[&"strength", 120.0], [&"weakness", 40.0]]})
	_drink(reg, &"reef_tonic", "Reef Tonic", 24.0, 4.0, Color(0.34, 0.80, 0.76),
		"Reefpod extract. You will not need to surface for a while.",
		{"value": 28, "rarity": Const.RARITY_UNCOMMON, "shelf": 0.0,
			"effects": [[&"breathing", 240.0]]})
	_drink(reg, &"ash_cordial", "Ash Cordial", 22.0, 4.0, Color(0.86, 0.44, 0.22),
		"Distilled on a volcano. Tastes of smoke and confidence.",
		{"value": 26, "rarity": Const.RARITY_UNCOMMON, "shelf": 0.0,
			"effects": [[&"fire_resistance", 240.0]]})


# ============================================================= preserved goods
static func _preserved(reg) -> void:
	_food(reg, &"jerky", "Jerky", 18.0, 2.0, Color(0.52, 0.30, 0.20),
		"Dried, salted, indestructible.",
		{"value": 16, "shelf": SHELF_PRESERVED, "tags": [&"preserved", &"meat"]})
	_food(reg, &"dried_fruit", "Dried Fruit", 14.0, 2.0, Color(0.78, 0.46, 0.30),
		"Wrinkled and concentrated.",
		{"value": 12, "shelf": SHELF_PRESERVED, "tags": [&"preserved", &"sweet"]})
	_food(reg, &"pickles", "Pickled Vegetables", 15.0, 3.0, Color(0.60, 0.72, 0.32),
		"Sour, crunchy, and they last forever.",
		{"value": 12, "shelf": SHELF_PRESERVED, "tags": [&"preserved"],
			"effects": [[&"poison_resistance", 90.0]]})
	_food(reg, &"canned_stew", "Canned Stew", 24.0, 5.0, Color(0.62, 0.58, 0.50),
		"Ship rations. Nobody's favourite, everybody's backup.",
		{"value": 18, "shelf": 0.0, "tags": [&"preserved"]})
	_food(reg, &"salt_fish", "Salt Fish", 19.0, 3.0, Color(0.82, 0.80, 0.70),
		"Stiff as a plank and twice as savoury.",
		{"value": 14, "shelf": SHELF_PRESERVED, "tags": [&"preserved", &"fish"]})
	_food(reg, &"grape_jam", "Grape Jam", 16.0, 3.0, Color(0.50, 0.20, 0.50),
		"Sugar doing the preserving.",
		{"value": 14, "shelf": SHELF_PRESERVED, "tags": [&"preserved", &"sweet"]})
	_food(reg, &"hardtack", "Hardtack", 20.0, 0.0, Color(0.86, 0.80, 0.64),
		"Technically food. Legally a building material.",
		{"value": 9, "shelf": 0.0, "tags": [&"preserved", &"baked"]})
	_food(reg, &"trail_mix", "Trail Mix", 21.0, 3.0, Color(0.72, 0.58, 0.36),
		"Seeds, dried fruit and whatever else fit in the bag.",
		{"value": 16, "shelf": SHELF_PRESERVED, "tags": [&"preserved"],
			"effects": [[&"rested", 120.0]]})
	_food(reg, &"honeyed_nuts", "Honeyed Nuts", 19.0, 4.0, Color(0.88, 0.66, 0.28),
		"Sticky, sweet, endlessly snackable.",
		{"value": 15, "shelf": SHELF_PRESERVED, "tags": [&"preserved", &"sweet"]})
	_food(reg, &"ration_bar", "Ration Bar", 26.0, 2.0, Color(0.68, 0.66, 0.56),
		"Engineered for calories, not joy.",
		{"value": 20, "shelf": 0.0, "tags": [&"preserved"],
			"effects": [[&"well_fed", 180.0]]})


# =============================================================== perfect meals
## The kitchen's masterpieces. `perfect_meal` makes `survival/cooking.gd` grant
## `feast` on top of whatever the dish declares, which is a large, long,
## everything-buff. These are the reason to keep a farm running.
static func _perfect_meals(reg) -> void:
	_food(reg, &"harvest_feast", "Harvest Feast", 60.0, 25.0, Color(0.94, 0.72, 0.32),
		"Everything the plot produced this season, on one enormous board.",
		{"value": 140, "rarity": Const.RARITY_RARE, "stack": 10, "shelf": 900.0,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"regeneration", 120.0], [&"strength", 300.0],
				[&"defense_up", 300.0]]})
	_food(reg, &"voidfarer_platter", "Voidfarer Platter", 58.0, 22.0, Color(0.52, 0.80, 0.96),
		"Alien produce arranged with unnerving precision. Perfect for a long jump.",
		{"value": 180, "rarity": Const.RARITY_RARE, "stack": 10, "shelf": 900.0,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"breathing", 420.0], [&"radiation_shielding", 420.0],
				[&"energised", 300.0]]})
	_food(reg, &"deepstone_roast", "Deepstone Roast", 62.0, 30.0, Color(0.72, 0.56, 0.34),
		"Slow-roasted underground for a day. Miners swear by it.",
		{"value": 160, "rarity": Const.RARITY_RARE, "stack": 10, "shelf": 900.0,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"mining_haste", 420.0], [&"night_vision", 420.0],
				[&"defense_up", 300.0]]})
	_food(reg, &"emberheart_curry", "Emberheart Curry", 56.0, 20.0, Color(0.90, 0.34, 0.16),
		"Chili, ash cordial and something that was still moving this morning.",
		{"value": 165, "rarity": Const.RARITY_RARE, "stack": 10, "shelf": 900.0,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"fire_resistance", 420.0], [&"strength", 300.0],
				[&"haste", 240.0]]})
	_food(reg, &"tidecaller_banquet", "Tidecaller Banquet", 58.0, 24.0, Color(0.34, 0.76, 0.78),
		"Reef, coral and deep fish. Hylotl chefs would grudgingly approve.",
		{"value": 175, "rarity": Const.RARITY_RARE, "stack": 10, "shelf": 900.0,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"breathing", 480.0], [&"ice_resistance", 300.0],
				[&"regeneration", 120.0]]})
	_food(reg, &"planeshifter_supper", "Planeshifter's Supper", 55.0, 20.0, Color(0.62, 0.86, 1.0),
		"Oculemon, currentcorn and a great deal of nerve. You can see the layer behind.",
		{"value": 260, "rarity": Const.RARITY_LEGENDARY, "stack": 5, "shelf": 900.0,
			"tags": [&"cooked", &"perfect_meal", &"signature"],
			"effects": [[&"phase_sight", 300.0], [&"night_vision", 300.0],
				[&"lucky", 300.0]]})


# ==================================================================== medicine
static func _med_hook(keyword: StringName, heal: float, effects: Array) -> Callable:
	return func(player: Node, _ctx: Dictionary) -> bool:
		if Status == null or Status.medical == null:
			return false
		return Status.medical.apply_medicine(keyword, player, heal, effects)


static func _stim_hook(kind: StringName) -> Callable:
	return func(player: Node, _ctx: Dictionary) -> bool:
		if Status == null or Status.medical == null:
			return false
		return Status.medical.stim(player, kind)


static func _medkit_hook() -> Callable:
	return func(player: Node, _ctx: Dictionary) -> bool:
		if Status == null or Status.medical == null:
			return false
		return Status.medical.medkit(player)


static func _panacea_hook() -> Callable:
	return func(player: Node, _ctx: Dictionary) -> bool:
		if Status == null:
			return false
		Status.clear_debuffs(player)
		if Status.environment != null:
			Status.environment.flush_dose(100.0)
		if player != null and player.has_method(&"heal"):
			player.call(&"heal", 60.0)
		Status.apply(&"regeneration", player, 60.0)
		return true


static func _medicine(reg) -> void:
	_med(reg, &"bandage", "Bandage", Color(0.94, 0.92, 0.88), 8,
		"Stops bleeding and buys you time to get somewhere safe.",
		_med_hook(&"bandage", 8.0, [{"id": &"regeneration", "duration": 10.0}]))
	_med(reg, &"sterile_bandage", "Sterile Bandage", Color(0.86, 0.94, 0.98), 22,
		"Clean dressing. Stops the bleed and heads off infection.",
		_med_hook(&"bandage", 18.0, [{"id": &"regeneration", "duration": 25.0}]),
		Const.RARITY_UNCOMMON)
	_med(reg, &"medkit", "Medkit", Color(0.92, 0.30, 0.30), 60,
		"Bandages, antiseptic and a needle you would rather not look at.",
		_medkit_hook(), Const.RARITY_UNCOMMON)
	_med(reg, &"antidote", "Antidote", Color(0.46, 0.86, 0.36), 30,
		"Neutralises venom and acid burns.",
		_med_hook(&"antidote", 5.0, []))
	_med(reg, &"antirad", "Anti-Radiation Shot", Color(0.62, 0.98, 0.38), 45,
		"Purges an accumulated dose. Tastes of pennies.",
		_med_hook(&"antirad", 5.0, [{"id": &"radiation_shielding", "duration": 120.0}]),
		Const.RARITY_UNCOMMON)
	_med(reg, &"antibiotics", "Antibiotics", Color(0.84, 0.86, 0.96), 70,
		"The only field cure for an infected wound.",
		_med_hook(&"cure", 10.0, [{"id": &"regeneration", "duration": 45.0}]),
		Const.RARITY_UNCOMMON)
	_med(reg, &"panacea", "Panacea", Color(0.98, 0.86, 0.42), 220,
		"Clears everything. Ancient, and nobody is entirely sure how it works.",
		_panacea_hook(), Const.RARITY_LEGENDARY)
	_med(reg, &"combat_stim", "Combat Stim", Color(0.94, 0.36, 0.28), 55,
		"Everything hurts less and hits harder for a while.",
		_stim_hook(&"combat"), Const.RARITY_UNCOMMON)
	_med(reg, &"guard_stim", "Guardian Stim", Color(0.60, 0.72, 0.94), 55,
		"Locks your guard up. Useful when you cannot flip away.",
		_stim_hook(&"guard"), Const.RARITY_UNCOMMON)
	_med(reg, &"focus_stim", "Focus Stim", Color(0.52, 0.92, 0.96), 55,
		"Sharpens the hands. Miners and surgeons both swear by it.",
		_stim_hook(&"focus"), Const.RARITY_UNCOMMON)
	_med(reg, &"warming_salve", "Warming Salve", Color(0.96, 0.62, 0.30), 35,
		"Thaws you out and keeps the cold off for a few minutes.",
		_med_hook(&"warmth", 5.0, [{"id": &"fire_resistance", "duration": 90.0}]))
	_med(reg, &"cooling_gel", "Cooling Gel", Color(0.44, 0.82, 0.98), 35,
		"Douses burns and holds off heatstroke.",
		_med_hook(&"cooling", 5.0, [{"id": &"ice_resistance", "duration": 90.0}]))


static func _med(reg, id: StringName, display: String, col: Color, value: int,
		desc: String, hook: Callable, rarity: int = Const.RARITY_COMMON) -> void:
	if reg.has(id):
		return
	var it: ItemType = reg.define(id, display)
	it.of_kind(ItemType.Kind.CONSUMABLE).look(col, &"vial")
	it.describe(desc).worth(value, rarity).stacks(20)
	it.in_category(&"medical").tag(&"medical").tag(&"consumable")
	it.on_use = hook
