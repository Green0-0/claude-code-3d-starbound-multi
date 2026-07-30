extends RefCounted

## The last of the item registry: one placeable item per entry in `ObjectDB`,
## one card per entry in `TechCatalog`, ammunition, and the handful of oddities
## that belong nowhere else.


static func register_all() -> void:
	_object_items()
	_tech_cards()
	_ammo()
	_oddities()


## Every placeable object gets an item that places it. The object database is
## the single source of truth for the stats; this only wraps it.
static func _object_items() -> void:
	ObjectDB.boot()
	for d: ObjectDB.Def in ObjectDB.defs:
		if Items.has(d.id):
			continue
		var shape: StringName = &"cube"
		match d.kind:
			ObjectDB.Kind.CONTAINER: shape = &"cube"
			ObjectDB.Kind.STATION: shape = &"plate"
			ObjectDB.Kind.MACHINE: shape = &"gear"
			ObjectDB.Kind.LIGHT: shape = &"lamp"
			ObjectDB.Kind.DOOR: shape = &"pane"
			ObjectDB.Kind.UTILITY: shape = &"orb"
		var it := Items.define(d.id, d.display)
		it.of_kind(Items.Kind.OBJECT)
		it.look(d.color, shape)
		it.describe(d.description)
		it.worth(d.value, d.rarity)
		it.stacks(30)
		it.in_category(&"objects")
		it.tag(&"object").tag(&"placeable")
		for t: StringName in d.tags:
			it.tag(t)
		if d.station != &"":
			it.tag(&"station").tag(StringName("station_" + String(d.station)))


## One card per tech. Using a card unlocks its tech, provided its prerequisites
## are already owned.
static func _tech_cards() -> void:
	for d: Dictionary in TechCatalog.ALL:
		var tid: StringName = d["id"]
		var card := TechCatalog.card_id(tid)
		if Items.has(card):
			continue
		var it := Items.define(card, "%s Tech Card" % String(d["name"]))
		it.of_kind(Items.Kind.TECH)
		it.tech_id = tid
		it.look(d["color"], &"card")
		it.worth(int(d["price"]), int(d["rarity"]))
		it.stacks(1)
		it.in_category(&"tech")
		it.tag(&"tech").tag(&"card").tag(StringName("slot_" + String(d["slot"])))
		var reqs: Array = d.get("requires", [])
		var req_line := ""
		if not reqs.is_empty():
			var names: Array[String] = []
			for r in reqs:
				names.append(String(TechCatalog.get_def(StringName(r)).get("name", r)))
			req_line = "  Requires: %s." % ", ".join(names)
		var drain := float(d["drain"])
		var drain_line := (", %.0f/s while held" % drain) if drain > 0.0 else ""
		it.describe("%s  (%s slot, %.0f energy%s)%s" % [
			String(d["desc"]), String(d["slot"]), float(d["energy"]),
			drain_line, req_line])


## Ammunition for the bows. Guns run on energy and need none.
static func _ammo() -> void:
	var rows := [
		[&"arrow", "Arrow", Color(0.72, 0.62, 0.42), 2, 0,
			"Straight, fletched and cheap by the bundle."],
		[&"iron_arrow", "Iron Arrow", Color(0.70, 0.70, 0.74), 5, 0,
			"Heavier head, flatter flight, considerably ruder."],
		[&"bolt", "Bolt", Color(0.62, 0.86, 0.94), 12, 1,
			"Short, dense and fired hard enough to punch a plate."],
	]
	for r: Array in rows:
		if Items.has(r[0]):
			continue
		Items.define(r[0], String(r[1])).of_kind(Items.Kind.MATERIAL) \
			.look(r[2], &"rod").worth(int(r[3]), int(r[4])).stacks(500) \
			.in_category(&"ammo").tag(&"ammo").describe(String(r[5]))


static func _oddities() -> void:
	Items.define(&"empty_flask", "Empty Flask").of_kind(Items.Kind.MATERIAL) \
		.look(Color(0.78, 0.88, 0.92), &"flask").worth(6).stacks(50) \
		.in_category(&"crafting").tag(&"container") \
		.describe("Glass, stoppered, and waiting to be filled with something.")

	Items.define(&"map_chart", "Survey Chart").of_kind(Items.Kind.CONSUMABLE) \
		.look(Color(0.86, 0.80, 0.62), &"scroll").worth(160, Items.RARITY_UNCOMMON) \
		.stacks(10).in_category(&"tools").tag(&"chart") \
		.describe("Reveals the terrain and the caches for a good distance around "
			+ "wherever you unroll it.")

	Items.define(&"repair_kit", "Repair Kit").of_kind(Items.Kind.CONSUMABLE) \
		.look(Color(0.62, 0.66, 0.72), &"gear").worth(120).stacks(20) \
		.in_category(&"tools").tag(&"repair") \
		.describe("Restores a worn tool or weapon to full condition.")

	Items.define(&"monster_capture_pod", "Capture Pod").of_kind(Items.Kind.CONSUMABLE) \
		.look(Color(0.94, 0.52, 0.30), &"orb").worth(340, Items.RARITY_UNCOMMON) \
		.stacks(20).in_category(&"tools").tag(&"capture") \
		.describe("Thrown at a weakened creature, it takes the creature with it. "
			+ "It will fight for you afterwards, more or less.")
