class_name CropTable
extends RefCounted

## The single source of truth for every crop in the game.
##
## `blk_crops.gd` builds the `<crop>_stage_N` blocks from it, `itm_food.gd`
## builds the produce and the seeds from it, and `survival.gd` grows it. Adding
## a crop means adding one row here and nothing else.


## id, display, stages, seconds per stage, young colour, ripe colour,
## nutrition, and a dictionary of options.
static func _row(id: StringName, name: String, family: StringName, stages: int,
		seconds: float, young: Color, ripe: Color, food: float,
		opts := {}) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"family": family,
		"stages": stages,
		"seconds": seconds,
		"young": young,
		"ripe": ripe,
		"food": food,
		"heal": float(opts.get("heal", 0.0)),
		"biome": StringName(opts.get("biome", &"biome_forest")),
		"yield": opts.get("yield", [1, 2]),
		"seeds": opts.get("seeds", [1, 2]),
		"value": int(opts.get("value", 4)),
		"rarity": int(opts.get("rarity", 0)),
		"glow": int(opts.get("glow", 0)),
		"light": int(opts.get("light", 6)),
		"needs_water": bool(opts.get("needs_water", false)),
		"perennial": bool(opts.get("perennial", false)),
		"material": bool(opts.get("material", false)),
		"produce": StringName(opts.get("produce", id)),
		"produce_name": String(opts.get("produce_name", name)),
		"effects": opts.get("effects", []),
	}


static var _cache: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if not _cache.is_empty():
		return _cache
	var t: Array[Dictionary] = []
	# ----------------------------------------------------------- staples
	t.append(_row(&"wheat", "Wheat", &"grain", 3, 46.0,
		Color(0.55, 0.72, 0.32), Color(0.87, 0.75, 0.34), 7.0,
		{"biome": &"biome_forest", "yield": [1, 3], "value": 3}))
	t.append(_row(&"corn", "Corn", &"grain", 3, 62.0,
		Color(0.42, 0.68, 0.28), Color(0.96, 0.82, 0.28), 13.0,
		{"biome": &"biome_savannah", "value": 5}))
	# ------------------------------------------------------------- roots
	t.append(_row(&"potato", "Potato", &"root", 3, 52.0,
		Color(0.36, 0.60, 0.28), Color(0.79, 0.66, 0.42), 12.0,
		{"biome": &"biome_forest", "yield": [2, 4], "value": 4}))
	t.append(_row(&"carrot", "Carrot", &"root", 3, 46.0,
		Color(0.40, 0.66, 0.26), Color(0.93, 0.55, 0.18), 10.0,
		{"biome": &"biome_forest", "yield": [1, 3], "value": 4,
			"effects": [[&"night_vision", 45.0]]}))
	# -------------------------------------------------------- vegetables
	t.append(_row(&"tomato", "Tomato", &"vegetable", 3, 54.0,
		Color(0.36, 0.62, 0.28), Color(0.87, 0.20, 0.16), 11.0,
		{"biome": &"biome_forest", "yield": [1, 3], "value": 5}))
	# ------------------------------------------------------------- fibre
	t.append(_row(&"cotton", "Cotton", &"fibre", 3, 64.0,
		Color(0.42, 0.62, 0.32), Color(0.96, 0.96, 0.93), 0.0,
		{"biome": &"biome_desert", "material": true, "yield": [1, 3], "value": 6,
			"produce": &"cotton_wool", "produce_name": "Cotton Wool"}))
	# --------------------------------------------- alien and signature
	t.append(_row(&"currentcorn", "Currentcorn", &"alien", 3, 72.0,
		Color(0.34, 0.62, 0.66), Color(0.44, 0.86, 1.0), 12.0,
		{"biome": &"biome_alien", "glow": 6, "value": 13,
			"effects": [[&"energised", 90.0]]}))
	_cache = t
	return _cache


static func row_of(crop: StringName) -> Dictionary:
	for r: Dictionary in all():
		if r["id"] == crop:
			return r
	return {}


static func stage_block_name(crop: StringName, stage: int) -> StringName:
	return StringName("%s_stage_%d" % [crop, stage])


static func seed_item_name(crop: StringName) -> StringName:
	return StringName(String(crop) + "_seed")
