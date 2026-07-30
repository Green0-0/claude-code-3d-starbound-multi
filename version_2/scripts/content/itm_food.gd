extends RefCounted

## Food, drink and medicine.
##
##   1. **Raw produce** — generated straight from `CropTable`, so a new crop
##      needs no edit here.
##   2. **Foraged staples** — meat, fish, eggs, honey.
##   3. **Cooked dishes** — what the kitchen station turns the above into.
##   4. **Drinks** — tagged `drink`; they fill thirst rather than hunger.
##   5. **Preserved goods** — long shelf life, lower nutrition.
##   6. **Perfect meals** — multi-ingredient dishes tagged `perfect_meal`, which
##      grant `feast` on top of their own effects.
##   7. **Medicine** — bandages, medkits, antidotes and stims.
##
## Anything that rots carries `perishable` and a `shelf_life` bonus in seconds
## of world time; the survival module reads both.

const SHELF_RAW := 900.0
const SHELF_COOKED := 1500.0
const SHELF_PRESERVED := 12000.0


static func food(id: StringName, display: String, nutrition: float, heal: float,
		col: Color, desc: String, extra := {}) -> Items.Type:
	if Items.has(id):
		return Items.get_type(id)
	var it := Items.define(id, display)
	it.as_food(nutrition, heal)
	it.look(col, StringName(extra.get("shape", &"round")))
	it.describe(desc)
	it.worth(int(extra.get("value", maxi(2, int(nutrition)))),
		int(extra.get("rarity", Items.RARITY_COMMON)))
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
	return it


static func drink(id: StringName, display: String, hydration: float, heal: float,
		col: Color, desc: String, extra := {}) -> Items.Type:
	var e := extra.duplicate()
	e["category"] = e.get("category", &"drink")
	e["shape"] = e.get("shape", &"flask")
	var tags: Array = (e.get("tags", []) as Array).duplicate()
	tags.append(&"drink")
	e["tags"] = tags
	e["stack"] = e.get("stack", 20)
	return food(id, display, hydration, heal, col, desc, e)


static func register_all() -> void:
	_raw_produce()
	_seeds()
	_foraged()
	_cooked()
	_drinks()
	_preserved()
	_perfect_meals()
	_medicine()


# =============================================================== raw produce
static func _raw_produce() -> void:
	for row: Dictionary in CropTable.all():
		var id: StringName = row["produce"]
		if Items.has(id):
			continue
		var col: Color = row["ripe"]
		if bool(row["material"]):
			Items.define(id, String(row["produce_name"])) \
				.of_kind(Items.Kind.MATERIAL).look(col, &"round") \
				.describe("Harvested %s." % String(row["name"]).to_lower()) \
				.worth(int(row["value"]), int(row["rarity"])).stacks(200) \
				.in_category(&"ingredient").tag(&"produce").tag(&"ingredient") \
				.tag(StringName("crop_" + String(row["id"])))
			continue
		var effects: Array = []
		for e in row["effects"]:
			effects.append(e)
		food(id, String(row["produce_name"]), float(row["food"]), float(row["heal"]),
			col, "Freshly picked %s." % String(row["name"]).to_lower(),
			{"value": int(row["value"]), "rarity": int(row["rarity"]),
				"shelf": SHELF_RAW, "effects": effects,
				"tags": [&"produce", &"raw", StringName("crop_" + String(row["id"]))]})


## One seed per crop, named `<crop>_seed`. Using one plants it on tilled soil.
static func _seeds() -> void:
	for row: Dictionary in CropTable.all():
		var crop: StringName = row["id"]
		var id := CropTable.seed_item_name(crop)
		if Items.has(id):
			continue
		var ripe: Color = row["ripe"]
		var it := Items.define(id, "%s Seed" % row["name"])
		it.of_kind(Items.Kind.SEED)
		it.look(ripe.lerp(Color(0.42, 0.32, 0.20), 0.45), &"seed")
		it.describe(_seed_blurb(row))
		it.worth(maxi(2, int(row["value"]) / 2), int(row["rarity"]))
		it.stacks(200).in_category(&"seeds")
		it.tag(&"seed").tag(StringName(row["biome"]))
		it.tag(StringName("crop_" + String(crop)))
		if bool(row["perennial"]):
			it.tag(&"perennial")
		it.seed_crop = crop


static func _seed_blurb(row: Dictionary) -> String:
	var bits := PackedStringArray(["Plant on tilled soil."])
	if bool(row["needs_water"]):
		bits.append("Wants a water source nearby.")
	if int(row["light"]) <= 0:
		bits.append("Grows in the dark.")
	if bool(row["perennial"]):
		bits.append("Keeps producing once grown.")
	return " ".join(bits)


# ============================================================ foraged staples
static func _foraged() -> void:
	food(&"raw_meat", "Raw Meat", 8.0, 0.0, Color(0.82, 0.36, 0.36),
		"Better cooked. Much better cooked.",
		{"shelf": 600.0, "tags": [&"meat", &"raw"], "effects": [[&"poisoned", 6.0]],
			"value": 5})
	food(&"raw_alien_meat", "Alien Cut", 9.0, 0.0, Color(0.62, 0.38, 0.72),
		"It is still faintly warm and you did not cook it.",
		{"shelf": 600.0, "tags": [&"meat", &"raw"], "effects": [[&"poisoned", 10.0]],
			"value": 7})
	food(&"raw_fish", "Raw Fish", 7.0, 0.0, Color(0.62, 0.74, 0.82),
		"Slippery and staring at you.",
		{"shelf": 600.0, "tags": [&"fish", &"raw"], "value": 5})
	food(&"egg", "Egg", 6.0, 1.0, Color(0.96, 0.93, 0.84), "Somebody's breakfast.",
		{"shelf": 1200.0, "tags": [&"ingredient"], "value": 4})
	food(&"honey", "Honey", 10.0, 2.0, Color(0.92, 0.70, 0.18),
		"Sweet, sticky and keeps almost forever.",
		{"shelf": SHELF_PRESERVED, "tags": [&"ingredient", &"sweet"], "value": 8})
	food(&"mushroom_brown", "Brown Mushroom", 4.0, 0.0, Color(0.60, 0.44, 0.30),
		"Earthy, safe, and improves anything it is thrown into.",
		{"shelf": SHELF_RAW, "tags": [&"ingredient", &"fungus"], "value": 3})
	food(&"mushroom_red", "Red Mushroom", 3.0, 0.0, Color(0.82, 0.20, 0.18),
		"Edible. Barely. Cook it first, and not for a guest.",
		{"shelf": SHELF_RAW, "tags": [&"ingredient", &"fungus"], "value": 3,
			"effects": [[&"poisoned", 5.0]]})
	food(&"mushroom_blue", "Azure Cap", 5.0, 2.0, Color(0.52, 0.72, 1.00),
		"Faintly luminous even after chewing.",
		{"shelf": SHELF_RAW, "tags": [&"ingredient", &"fungus"], "value": 9,
			"effects": [[&"night_vision", 60.0]]})


static func _ingredient(id: StringName, display: String, col: Color, value: int,
		desc: String) -> void:
	if Items.has(id):
		return
	Items.define(id, display).of_kind(Items.Kind.MATERIAL).look(col, &"round") \
		.describe(desc).worth(value).stacks(200).in_category(&"ingredient") \
		.tag(&"ingredient")


# ================================================================== cooked
static func _cooked() -> void:
	_ingredient(&"flour", "Flour", Color(0.94, 0.90, 0.80), 6,
		"Milled grain. One step from bread and two from a disappointment.")
	_ingredient(&"dough", "Dough", Color(0.92, 0.86, 0.72), 8,
		"Flour, water, patience. Mostly patience.")

	food(&"bread", "Bread", 22.0, 3.0, Color(0.82, 0.66, 0.38),
		"A whole loaf. The reason anybody grows wheat.",
		{"value": 14, "tags": [&"cooked", &"staple"], "shelf": SHELF_COOKED,
			"effects": [[&"well_fed", 180.0]]})
	food(&"cooked_meat", "Roast", 26.0, 6.0, Color(0.68, 0.40, 0.24),
		"Seared through. No longer trying to poison you.",
		{"value": 16, "tags": [&"cooked", &"meat"], "shelf": SHELF_COOKED,
			"effects": [[&"well_fed", 180.0]]})
	food(&"cooked_fish", "Grilled Fish", 22.0, 5.0, Color(0.82, 0.76, 0.62),
		"Crisp skin, no bones left in it. Mostly.",
		{"value": 15, "tags": [&"cooked", &"fish"], "shelf": SHELF_COOKED,
			"effects": [[&"well_fed", 150.0]]})
	food(&"vegetable_stew", "Vegetable Stew", 30.0, 8.0, Color(0.74, 0.48, 0.24),
		"Whatever the plot gave you, simmered until it agrees with itself.",
		{"value": 22, "tags": [&"cooked", &"stew"], "shelf": SHELF_COOKED,
			"effects": [[&"well_fed", 240.0], [&"warm", 120.0]]})
	food(&"mushroom_soup", "Mushroom Soup", 26.0, 10.0, Color(0.66, 0.56, 0.42),
		"Thick, earthy and improbably restorative.",
		{"value": 24, "tags": [&"cooked", &"stew"], "shelf": SHELF_COOKED,
			"effects": [[&"regeneration", 60.0]]})
	food(&"roast_vegetables", "Roast Vegetables", 24.0, 4.0, Color(0.86, 0.58, 0.24),
		"Caramelised at the edges, which is the entire point.",
		{"value": 18, "tags": [&"cooked"], "shelf": SHELF_COOKED,
			"effects": [[&"well_fed", 200.0]]})
	food(&"alien_skewer", "Alien Skewer", 34.0, 6.0, Color(0.78, 0.44, 0.86),
		"Charred, unidentifiable, and unexpectedly excellent.",
		{"value": 34, "rarity": Items.RARITY_UNCOMMON, "tags": [&"cooked", &"alien"],
			"shelf": SHELF_COOKED, "effects": [[&"haste", 90.0], [&"well_fed", 240.0]]})


# =================================================================== drinks
static func _drinks() -> void:
	drink(&"water_flask", "Flask of Water", 28.0, 0.0, Color(0.34, 0.62, 0.92),
		"Clean, cold and the difference between a hike and a rescue.",
		{"value": 6, "shelf": 0.0})
	drink(&"coffee", "Coffee", 14.0, 0.0, Color(0.36, 0.22, 0.14),
		"Bitter, black, and the only reason the night shift exists.",
		{"value": 26, "effects": [[&"haste", 120.0], [&"energised", 120.0]],
			"shelf": SHELF_COOKED})
	drink(&"herbal_tea", "Herbal Tea", 22.0, 6.0, Color(0.62, 0.78, 0.42),
		"Steeped from whatever was growing near the camp.",
		{"value": 18, "effects": [[&"regeneration", 45.0], [&"warm", 180.0]],
			"shelf": SHELF_COOKED})
	drink(&"glow_tonic", "Glow Tonic", 16.0, 4.0, Color(0.60, 0.98, 0.72),
		"Lights you from the inside. Wears off. Eventually.",
		{"value": 48, "rarity": Items.RARITY_UNCOMMON,
			"effects": [[&"glowing", 240.0], [&"night_vision", 180.0]],
			"shelf": SHELF_PRESERVED})


# ================================================================ preserved
static func _preserved() -> void:
	food(&"jerky", "Jerky", 16.0, 2.0, Color(0.52, 0.30, 0.20),
		"Salted, dried, and it will outlast the pack it is in.",
		{"value": 20, "tags": [&"preserved", &"meat"], "shelf": SHELF_PRESERVED})
	food(&"hardtack", "Hardtack", 14.0, 0.0, Color(0.86, 0.78, 0.60),
		"Structural. Soak it or lose a tooth.",
		{"value": 10, "tags": [&"preserved", &"staple"], "shelf": SHELF_PRESERVED})
	food(&"canned_stew", "Canned Stew", 28.0, 4.0, Color(0.68, 0.52, 0.34),
		"Sealed in a tin that predates you. Still perfectly fine.",
		{"value": 30, "tags": [&"preserved", &"stew"], "shelf": SHELF_PRESERVED,
			"effects": [[&"well_fed", 240.0]]})


# ============================================================ perfect meals
static func _perfect_meals() -> void:
	food(&"hearty_platter", "Hearty Platter", 48.0, 18.0, Color(0.88, 0.62, 0.30),
		"Meat, bread, roots and something green, arranged with real intent.",
		{"value": 90, "rarity": Items.RARITY_UNCOMMON, "shelf": SHELF_COOKED,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"feast", 420.0], [&"defense_up", 300.0]]})
	food(&"voyagers_feast", "Voyager's Feast", 56.0, 24.0, Color(0.72, 0.86, 0.98),
		"The meal you cook the night before a jump you might not come back from.",
		{"value": 160, "rarity": Items.RARITY_RARE, "shelf": SHELF_COOKED,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"feast", 480.0], [&"regeneration", 180.0],
				[&"energised", 300.0]]})
	food(&"starlit_confection", "Starlit Confection", 44.0, 16.0, Color(0.94, 0.86, 0.98),
		"Sugar, glow sap and one grain of star dust. Absurd, and it works.",
		{"value": 220, "rarity": Items.RARITY_RARE, "shelf": SHELF_COOKED,
			"tags": [&"cooked", &"perfect_meal"],
			"effects": [[&"feast", 480.0], [&"haste", 240.0], [&"lucky", 300.0]]})


# ================================================================= medicine
static func _med(id: StringName, display: String, col: Color, value: int,
		rarity: int, desc: String, heal: float, effects: Array) -> void:
	if Items.has(id):
		return
	var it := Items.define(id, display)
	it.of_kind(Items.Kind.CONSUMABLE)
	it.look(col, &"vial").describe(desc).worth(value, rarity).stacks(20)
	it.in_category(&"medical").tag(&"medical").tag(&"consumable")
	it.heal = heal
	for e in effects:
		var pair: Array = e
		it.with_effect(StringName(pair[0]), float(pair[1]))


static func _medicine() -> void:
	_med(&"bandage", "Bandage", Color(0.92, 0.90, 0.84), 18, 0,
		"Stops the bleeding and buys you the walk home.", 18.0,
		[[&"regeneration", 30.0]])
	_med(&"medkit", "Medkit", Color(0.92, 0.28, 0.30), 90, 1,
		"Sealed, sterile, and worth every pixel the moment you need it.", 60.0,
		[[&"regeneration", 60.0]])
	_med(&"antidote", "Antidote", Color(0.44, 0.86, 0.40), 60, 1,
		"Neutralises most of what a planet can put in you.", 6.0,
		[[&"cure_poison", 1.0]])
	_med(&"stim_pack", "Stim Pack", Color(0.98, 0.72, 0.24), 120, 1,
		"Three minutes of being the best version of yourself.", 10.0,
		[[&"strength", 180.0], [&"haste", 180.0]])
	_med(&"rad_purge", "Rad Purge", Color(0.72, 0.94, 0.36), 140, 2,
		"Chelation in a syringe. Unpleasant, and much better than the alternative.",
		8.0, [[&"cure_radiation", 1.0]])
	_med(&"panacea", "Panacea", Color(0.96, 0.94, 0.98), 480, 3,
		"Clears everything. Nobody will tell you what is in it.", 120.0,
		[[&"cure_all", 1.0], [&"regeneration", 120.0], [&"fortified", 240.0]])
