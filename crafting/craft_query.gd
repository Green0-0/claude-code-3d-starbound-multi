## The read-only façade the crafting window is written against.
##
## Everything here is `static`, side-effect free and safe to call every frame
## (it allocates, so cache per open/refresh rather than per `_process`). Nothing
## in this file mutates the inventory or the recipe book — to actually craft,
## call `CraftStation.enqueue()` or `Recipes.craft()`.
##
## [b]Conventions used throughout[/b][br]
## • `inv` is any object with the `Inventory` API, or `null` to mean the
##   player's inventory.[br]
## • `station` is one of `CraftRecipe.STATIONS`.[br]
## • `tier` is the station's tier; pass 99 for "no gate".[br]
## • Every returned Dictionary is a fresh copy; mutate it freely.
##
## [b]Typical crafting window flow[/b]
## [codeblock]
## var tree := CraftQuery.category_tree(&"workbench", inv, station.tier)
## for cat_id: StringName in tree["order"]:
##     var cat: Dictionary = tree["nodes"][cat_id]
##     # cat = {id, label, total, craftable, recipes:Array[CraftRecipe]}
##
## var rows := CraftQuery.list_for(&"workbench", inv, station.tier,
##                                 {"category": &"tools", "search": text,
##                                  "sort": CraftQuery.SORT_CRAFTABLE})
## for r: CraftRecipe in rows:
##     var p := CraftQuery.preview(r, inv)   # everything the row + tooltip needs
## [/codeblock]
class_name CraftQuery
extends RefCounted

## Sort modes for [method sort] and the `"sort"` option of [method list_for].
enum {
	SORT_CRAFTABLE,  ## craftable first, then category, then name
	SORT_NAME,       ## A-Z by display name
	SORT_TIER,       ## cheapest / earliest tier first
	SORT_CATEGORY,   ## grouped by category, name within
	SORT_TIME,       ## fastest first
	SORT_RARITY,     ## rarest output first
}

## Display order and labels for the category tabs. Categories not listed here
## are appended alphabetically, so new content never disappears.
const CATEGORY_ORDER: Array[StringName] = [
	&"materials", &"blocks", &"tools", &"weapons", &"armor",
	&"furniture", &"light", &"machines", &"wiring", &"food",
	&"tech", &"advanced",
]

const CATEGORY_LABELS := {
	&"materials": "Materials", &"blocks": "Blocks", &"tools": "Tools",
	&"weapons": "Weapons", &"armor": "Armour", &"furniture": "Furniture",
	&"light": "Lighting", &"machines": "Machines", &"wiring": "Wiring",
	&"food": "Food", &"tech": "Tech", &"advanced": "Advanced",
}


# ------------------------------------------------------------------- station
## Human label for a station id ("Chemistry Lab").
static func station_label(station: StringName) -> String:
	return String(CraftRecipe.STATION_LABELS.get(station, String(station).capitalize()))


## Every station that has at least one recipe, in vocabulary order.
static func stations() -> Array[StringName]:
	return Recipes.stations()


## `{ found, total, percent }` completion for a station's recipe book.
static func completion(station: StringName, tier: int = 99) -> Dictionary:
	var c := Recipes.catalogue_for(station, tier)
	var total := int(c["total"])
	return {
		"found": int(c["found"]), "total": total,
		"percent": 0.0 if total == 0 else float(c["found"]) / float(total),
	}


# ------------------------------------------------------------------ listings
## The main list call. `opts` keys, all optional:[br]
## • `category: StringName` — filter to one category[br]
## • `group: StringName` — filter to one station group[br]
## • `search: String` — fuzzy name/ingredient match (see [method search])[br]
## • `sort: int` — one of the `SORT_*` constants, default `SORT_CRAFTABLE`[br]
## • `craftable_only: bool` — hide entries missing materials[br]
## • `include_locked: bool` — also return undiscovered recipes as ghosts
static func list_for(station: StringName, inv: Variant = null, tier: int = 99,
		opts: Dictionary = {}) -> Array[CraftRecipe]:
	var list: Array[CraftRecipe] = Recipes.available_for(station, inv, tier)
	if bool(opts.get("include_locked", false)):
		for r: CraftRecipe in (Recipes.catalogue_for(station, tier)["locked"] as Array):
			list.append(r)

	var cat := StringName(opts.get("category", &""))
	var grp := StringName(opts.get("group", &""))
	var text := String(opts.get("search", "")).strip_edges().to_lower()
	var only := bool(opts.get("craftable_only", false))

	var out: Array[CraftRecipe] = []
	for r: CraftRecipe in list:
		if cat != &"" and r.category != cat:
			continue
		if grp != &"" and r.group != grp:
			continue
		if text != "" and not _matches(r, text):
			continue
		if only and not Recipes.missing_for(r, inv).is_empty():
			continue
		out.append(r)
	return sort(out, int(opts.get("sort", SORT_CRAFTABLE)), inv)


## The category tab strip.
## Returns `{ "order": Array[StringName], "nodes": { id: node } }` where each
## node is `{ id, label, total, craftable, recipes: Array[CraftRecipe] }`.
## Categories with no recipes are omitted entirely.
static func category_tree(station: StringName, inv: Variant = null,
		tier: int = 99, opts: Dictionary = {}) -> Dictionary:
	var list := list_for(station, inv, tier, opts)
	var nodes: Dictionary = {}
	for r: CraftRecipe in list:
		if not nodes.has(r.category):
			var fresh: Array[CraftRecipe] = []
			nodes[r.category] = {
				"id": r.category, "label": category_label(r.category),
				"total": 0, "craftable": 0, "recipes": fresh,
			}
		var node: Dictionary = nodes[r.category]
		var bucket: Array[CraftRecipe] = node["recipes"]
		bucket.append(r)
		node["total"] = int(node["total"]) + 1
		if Recipes.missing_for(r, inv).is_empty():
			node["craftable"] = int(node["craftable"]) + 1

	var order: Array[StringName] = []
	for c: StringName in CATEGORY_ORDER:
		if nodes.has(c):
			order.append(c)
	var extras: Array[StringName] = []
	for c: StringName in nodes:
		if not CATEGORY_ORDER.has(c):
			extras.append(c)
	extras.sort()
	order.append_array(extras)
	return {"order": order, "nodes": nodes}


static func category_label(c: StringName) -> String:
	return String(CATEGORY_LABELS.get(c, String(c).capitalize()))


## Free-text search across every recipe the player knows, at any station.
## Matches the recipe name, the output item name, the ingredient names and the
## description. Pass `station` to restrict it.
static func search(text: String, station: StringName = &"",
		inv: Variant = null, limit: int = 200) -> Array[CraftRecipe]:
	var needle := text.strip_edges().to_lower()
	var pool: Array[CraftRecipe] = Recipes.all_known()
	if station != &"":
		pool = Recipes.available_for(station, inv, 99)
	if needle == "":
		return sort(pool, SORT_CRAFTABLE, inv)
	var out: Array[CraftRecipe] = []
	for r: CraftRecipe in pool:
		if _matches(r, needle):
			out.append(r)
			if out.size() >= limit:
				break
	return sort(out, SORT_CRAFTABLE, inv)


static func _matches(r: CraftRecipe, needle: String) -> bool:
	if r.label().to_lower().contains(needle):
		return true
	if r.id.to_lower().contains(needle):
		return true
	if r.description.to_lower().contains(needle):
		return true
	for o: Dictionary in r.outputs:
		if _name_of(StringName(o["id"])).to_lower().contains(needle):
			return true
	for i: StringName in r.inputs:
		if _name_of(i).to_lower().contains(needle):
			return true
	return false


## "What can I make with this?" — every known recipe consuming `item_id`.
static func uses_of(item_id: StringName, inv: Variant = null) -> Array[CraftRecipe]:
	var out: Array[CraftRecipe] = []
	for r: CraftRecipe in Recipes.recipes_using(item_id):
		if Recipes.is_known(r.id):
			out.append(r)
	return sort(out, SORT_CRAFTABLE, inv)


## "How do I get this?" — every known recipe producing `item_id`.
static func sources_of(item_id: StringName, inv: Variant = null) -> Array[CraftRecipe]:
	var out: Array[CraftRecipe] = []
	for r: CraftRecipe in Recipes.recipes_making(item_id):
		if Recipes.is_known(r.id):
			out.append(r)
	return sort(out, SORT_CRAFTABLE, inv)


# --------------------------------------------------------------------- sorting
## Sorts a list in place and returns it.
static func sort(list: Array[CraftRecipe], mode: int = SORT_CRAFTABLE,
		inv: Variant = null) -> Array[CraftRecipe]:
	match mode:
		SORT_NAME:
			list.sort_custom(func(a: CraftRecipe, b: CraftRecipe) -> bool:
				return a.label().naturalnocasecmp_to(b.label()) < 0)
		SORT_TIER:
			list.sort_custom(func(a: CraftRecipe, b: CraftRecipe) -> bool:
				if a.required_tier != b.required_tier:
					return a.required_tier < b.required_tier
				return a.label() < b.label())
		SORT_CATEGORY:
			list.sort_custom(func(a: CraftRecipe, b: CraftRecipe) -> bool:
				if a.category != b.category:
					return _cat_rank(a.category) < _cat_rank(b.category)
				return a.label() < b.label())
		SORT_TIME:
			list.sort_custom(func(a: CraftRecipe, b: CraftRecipe) -> bool:
				if not is_equal_approx(a.time, b.time):
					return a.time < b.time
				return a.label() < b.label())
		SORT_RARITY:
			list.sort_custom(func(a: CraftRecipe, b: CraftRecipe) -> bool:
				var ra := _rarity_of(a.primary_output())
				var rb := _rarity_of(b.primary_output())
				if ra != rb:
					return ra > rb
				return a.label() < b.label())
		_:
			list.sort_custom(func(a: CraftRecipe, b: CraftRecipe) -> bool:
				var ca := Recipes.missing_for(a, inv).is_empty()
				var cb := Recipes.missing_for(b, inv).is_empty()
				if ca != cb:
					return ca
				if a.category != b.category:
					return _cat_rank(a.category) < _cat_rank(b.category)
				if a.sort_order != b.sort_order:
					return a.sort_order < b.sort_order
				return a.label() < b.label())
	return list


static func _cat_rank(c: StringName) -> int:
	var i := CATEGORY_ORDER.find(c)
	return i if i >= 0 else 100 + String(c).length()


# --------------------------------------------------------------------- preview
## Everything one recipe row and its tooltip need, in one Dictionary.
##
## [codeblock]
## {
##   "id": String,                 # recipe id, pass back to enqueue()/craft()
##   "name": String,               # "Iron Pickaxe"
##   "description": String,
##   "station": StringName,        "station_label": String,
##   "category": StringName,       "category_label": String,
##   "group": StringName,
##   "time": float,                # seconds, 0 = instant
##   "tier": int,                  # required station tier
##   "known": bool,                # discovered?
##   "craftable": bool,            # known AND materials present
##   "max_crafts": int,            # how many back-to-back runs are affordable
##   "locked_reason": String,      # "" when known; else "Obtain Iron Bar"
##   "inputs":  Array[Dictionary], # see below, in registration order
##   "outputs": Array[Dictionary],
##   "missing": Dictionary,        # {item_id: shortfall}, empty when craftable
##   "missing_text": String,       # "Need 3 Iron Bar, 2 Stick"
##   "result": Dictionary,         # == outputs[0], convenience for the row icon
##   "fuel_cost": float,           # furnace burn-seconds per run
## }
## [/codeblock]
##
## Each entry of `inputs` is:
## `{ id, name, need, have, enough, color, shape, rarity, rarity_color }`[br]
## Each entry of `outputs` is:
## `{ id, name, count, chance, primary, color, shape, rarity, rarity_color }`
static func preview(recipe: Variant, inv: Variant = null) -> Dictionary:
	var r: CraftRecipe = null
	if recipe is CraftRecipe:
		r = recipe as CraftRecipe
	else:
		r = Recipes.get_recipe(String(recipe))
	if r == null:
		return {}
	var missing := Recipes.missing_for(r, inv)
	var known := Recipes.is_known(r.id)

	var inputs: Array[Dictionary] = []
	for k: StringName in r.inputs:
		var need := int(r.inputs[k])
		var have := _count(inv, k)
		var e := _icon(k)
		e["need"] = need
		e["have"] = have
		e["enough"] = have >= need
		inputs.append(e)

	var outputs: Array[Dictionary] = []
	var first := true
	for o: Dictionary in r.outputs:
		var e := _icon(StringName(o["id"]))
		e["count"] = int(o.get("count", 1))
		e["chance"] = float(o.get("chance", 1.0))
		e["primary"] = first
		first = false
		outputs.append(e)

	return {
		"id": r.id,
		"name": r.label(),
		"description": r.description,
		"station": r.station,
		"station_label": station_label(r.station),
		"category": r.category,
		"category_label": category_label(r.category),
		"group": r.group,
		"time": r.time,
		"tier": r.required_tier,
		"known": known,
		"craftable": known and missing.is_empty(),
		"max_crafts": Recipes.max_crafts(r.id, inv),
		"locked_reason": "" if known else r.unlock_summary(),
		"inputs": inputs,
		"outputs": outputs,
		"missing": missing,
		"missing_text": missing_text(missing),
		"result": outputs[0] if not outputs.is_empty() else {},
		"fuel_cost": r.effective_fuel_cost(),
	}


## Batch version — one preview per recipe, for filling a whole list at once.
static func preview_all(list: Array[CraftRecipe], inv: Variant = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: CraftRecipe in list:
		out.append(preview(r, inv))
	return out


## "Need 3 Iron Bar, 2 Stick" — or "" when nothing is missing.
static func missing_text(missing: Dictionary) -> String:
	if missing.is_empty():
		return ""
	var parts: PackedStringArray = []
	for k: StringName in missing:
		parts.append("%d %s" % [int(missing[k]), _name_of(k)])
	return "Need " + ", ".join(parts)


## Icon/label data for one item id, so the UI never has to touch `Items`:
## `{ id, name, color, shape, rarity, rarity_color, kind, description }`.
static func icon_of(item_id: StringName) -> Dictionary:
	return _icon(item_id)


static func _icon(item_id: StringName) -> Dictionary:
	var t := Items.get_type(item_id)
	if t == null:
		return {
			"id": item_id, "name": String(item_id).capitalize(),
			"color": Color(0.6, 0.6, 0.6), "shape": &"square",
			"rarity": Const.RARITY_COMMON,
			"rarity_color": Const.RARITY_COLORS[Const.RARITY_COMMON],
			"kind": ItemType.Kind.MATERIAL, "description": "",
		}
	return {
		"id": item_id, "name": t.display_name,
		"color": t.icon_color, "shape": t.icon_shape,
		"rarity": t.rarity, "rarity_color": t.rarity_color(),
		"kind": t.kind, "description": t.description,
	}


static func _name_of(item_id: StringName) -> String:
	return Items.display_name(item_id) if Items.has(item_id) else String(item_id).capitalize()


static func _rarity_of(item_id: StringName) -> int:
	var t := Items.get_type(item_id)
	return t.rarity if t != null else Const.RARITY_COMMON


static func _count(inv: Variant, item_id: StringName) -> int:
	var real: Variant = inv
	if real == null and Game.player != null:
		real = Game.player.get("inventory")
	if real == null or not real.has_method(&"count_of"):
		return 0
	return int(real.call(&"count_of", item_id))


# ------------------------------------------------------------------ refinery
## Tooltip data for a refinery input: `{ accepted, outputs, seconds }`.
## `outputs` is `[{id, name, count, chance, color, shape}]`.
static func refinery_preview(refinery: CraftRefinery, item_id: StringName) -> Dictionary:
	if refinery == null:
		return {"accepted": false, "outputs": [], "seconds": 0.0}
	var outs: Array[Dictionary] = []
	for e: Dictionary in refinery.preview(item_id):
		var d := _icon(StringName(e["id"]))
		d["count"] = int(e["count"])
		d["chance"] = float(e["chance"])
		outs.append(d)
	return {
		"accepted": refinery.accepts(item_id),
		"outputs": outs,
		"seconds": refinery.item_time(),
	}


# ------------------------------------------------------------------- upgrade
## Convenience passthrough so the UI only needs to know about `CraftQuery`.
static func upgrade_preview(stack: ItemStack, inv: Variant = null) -> Dictionary:
	return CraftUpgrade.preview_upgrade(stack, inv)


## Augment slot state for the gear panel:
## `{ slots, used, installed:[{id,name,color,shape,description}], level }`.
static func augment_panel(stack: ItemStack) -> Dictionary:
	var installed: Array[Dictionary] = []
	for a: Variant in CraftUpgrade.installed_augments(stack):
		installed.append(_icon(StringName(a)))
	return {
		"slots": CraftUpgrade.slot_count(stack),
		"used": installed.size(),
		"installed": installed,
		"level": CraftUpgrade.level_of(stack),
	}
