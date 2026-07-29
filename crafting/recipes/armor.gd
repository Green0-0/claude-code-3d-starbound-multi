## The armour ladder, the four environment suits and the vanity wardrobe.
##
## [b]Naming convention, shared with the combat agent's
## `content/items/31_armor.gd`[/b] — `<metal>_helm`, `<metal>_chest`,
## `<metal>_greaves` over the ten ladder metals, and `<suit>_helm` /
## `<suit>_chest` / `<suit>_greaves` for the four suits
## `firewalker frostwalker hazmat vacuum`.
##
## Suits are blueprint unlocks rather than tier unlocks: they gate which planets
## you can survive, so finding the schematic should be the event.
extends RefCounted

## Bar cost per piece, before the tier curve, and how long it takes.
const PIECE_COST := {&"helm": 4, &"chest": 7, &"greaves": 5}
const PIECE_TIME := {&"helm": 1.0, &"chest": 1.6, &"greaves": 1.3}


static func register_all(reg) -> void:
	_metal_sets(reg)
	_suits(reg)
	_vanity(reg)


## Thirty recipes: three pieces across ten metals.
static func _metal_sets(reg) -> void:
	for name_str: String in CraftLadder.GEAR_METALS:
		var mname := StringName(name_str)
		var bar := CraftLadder.bar_of(mname)
		var tier := CraftLadder.tier_of(mname)
		var station := CraftLadder.station_of(mname)
		for piece: StringName in PIECE_COST:
			var r := CraftRecipe.make("craft_%s_%s" % [mname, piece], station) \
				.takes(bar, CraftLadder.metal_cost(tier, int(PIECE_COST[piece]))) \
				.gives(StringName("%s_%s" % [mname, piece]), 1) \
				.lasts(float(PIECE_TIME[piece]) + float(tier) * 0.5) \
				.needs_tier(tier) \
				.in_category(&"armor").in_group(&"armorsmith") \
				.ordered(tier * 10) \
				.describe("%s plate, shaped and riveted." % name_str.capitalize()) \
				.learned_from_material(bar)
			if tier >= 1:
				r.takes(&"leather", 2)
			if tier >= 3:
				r.takes(&"rubber", 2)
			if tier >= 5:
				r.takes(&"energy_cell", 1)
			reg.add(r)


static func _suits(reg) -> void:
	var suits: Array[Dictionary] = [
		{"prefix": &"firewalker", "tier": 3, "station": &"forge",
		"blueprint": &"blueprint_firewalker",
		"cost": {&"tungsten_bar": 3, &"clay_lump": 3, &"tough_leather": 2},
		"desc": "Ceramic scale over a heat-shedding weave. Lava becomes scenery."},
		{"prefix": &"frostwalker", "tier": 3, "station": &"chemistry",
		"blueprint": &"blueprint_frostwalker",
		"cost": {&"monster_fur": 4, &"cloth": 4, &"copper_wire": 3},
		"desc": "Insulated, sealed and heated at the seams."},
		{"prefix": &"hazmat", "tier": 4, "station": &"chemistry",
		"blueprint": &"blueprint_hazmat",
		"cost": {&"lead_bar": 3, &"rubber": 4, &"polymer": 2},
		"desc": "Lead-lined and positively pressurised."},
		{"prefix": &"vacuum", "tier": 5, "station": &"assembler",
		"blueprint": &"blueprint_vacuum",
		"cost": {&"durasteel_bar": 4, &"glass": 3, &"polymer": 3, &"energy_cell": 2},
		"desc": "Holds one atmosphere in, and the rest of the universe out."},
	]
	for s: Dictionary in suits:
		for piece: StringName in PIECE_COST:
			var r := CraftRecipe.make("craft_%s_%s" % [s["prefix"], piece], StringName(s["station"])) \
				.gives(StringName("%s_%s" % [s["prefix"], piece]), 1) \
				.lasts(float(PIECE_TIME[piece]) + 2.0) \
				.needs_tier(int(s["tier"])) \
				.in_category(&"armor").in_group(&"armorsmith") \
				.ordered(int(s["tier"]) * 10 + 5) \
				.describe(String(s["desc"])) \
				.learned_from_blueprint(StringName(s["blueprint"]))
			var cost: Dictionary = s["cost"]
			for k: StringName in cost:
				r.takes(k, maxi(1, int(cost[k]) * int(PIECE_COST[piece]) / 4))
			reg.add(r)


## Cosmetics. Cheap, cheerful, zero defence — and the only recipes in the book
## whose entire point is that you wanted to look like that.
static func _vanity(reg) -> void:
	var vanity: Array[Dictionary] = [
		{"id": &"straw_hat", "tier": 0, "station": &"workbench",
		"cost": {&"straw": 8, &"string": 2}, "start": true},
		{"id": &"tinfoil_crown", "tier": 0, "station": &"workbench",
		"cost": {&"tin_bar": 3}, "desc": "They cannot read your mind now."},
		{"id": &"poncho", "tier": 0, "station": &"workbench",
		"cost": {&"cloth": 8, &"string": 3}},
		{"id": &"work_trousers", "tier": 0, "station": &"workbench",
		"cost": {&"cloth": 6, &"leather": 2}},
		{"id": &"lab_coat", "tier": 2, "station": &"workbench",
		"cost": {&"cloth": 10, &"polymer": 1}},
		{"id": &"welding_goggles", "tier": 1, "station": &"anvil",
		"cost": {&"glass": 2, &"leather": 2, &"iron_bar": 1}},
		{"id": &"flight_jacket", "tier": 2, "station": &"workbench",
		"cost": {&"tough_leather": 6, &"cloth": 4}},
		{"id": &"captains_cap", "tier": 3, "station": &"workbench",
		"cost": {&"cloth": 6, &"gold_bar": 1, &"silk_thread": 2}},
		{"id": &"gala_skirt", "tier": 3, "station": &"workbench",
		"cost": {&"silk_thread": 8, &"prism_shard": 1}},
		{"id": &"survey_leggings", "tier": 2, "station": &"workbench",
		"cost": {&"tough_leather": 5, &"copper_wire": 2}},
	]
	for v: Dictionary in vanity:
		var tier := int(v["tier"])
		var r := CraftRecipe.make("craft_%s" % v["id"], StringName(v["station"])) \
			.gives(StringName(v["id"]), 1) \
			.lasts(1.5) \
			.needs_tier(tier) \
			.in_category(&"armor").in_group(&"armorsmith") \
			.ordered(tier * 10 + 9) \
			.describe(String(v.get("desc", "")))
		var cost: Dictionary = v["cost"]
		var first: StringName = &""
		for k: StringName in cost:
			r.takes(k, int(cost[k]))
			if first == &"":
				first = k
		if bool(v.get("start", false)):
			r.known_at_start()
		else:
			r.learned_from_material(first)
		reg.add(r)
