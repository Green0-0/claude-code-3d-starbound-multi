## Crafting bench. Categories on the left, a searchable recipe list in the
## middle, the ingredient breakdown and craft queue on the right.
##
## Recipe data belongs to the crafting agent, and this panel speaks its language
## when it is present:
##   `CraftQuery.category_tree(station, inv, tier, opts)` for the category tabs,
##   `CraftQuery.list_for(station, inv, tier, opts)` for the filtered list,
##   `CraftQuery.preview(recipe, inv)` for everything shown on the right,
##   `Recipes.craft(id, inv, times)` to actually perform the transaction.
##
## When `crafting/craft_query.gd` is absent it falls back to `Recipes.for_station`
## / `Recipes.all`, and finally to a small synthesised preview set — so the
## window is always explorable. Both paths produce the same entry shape:
## [codeblock]
## { id, name, description, category, category_label, time, known, craftable,
##   max_crafts,
##   inputs: [{ id, name, color, shape, need, have, enough }],
##   result:  { id, name, color, shape, count } }
## [/codeblock]
extends MenuPanel

const QUERY_PATH := "res://crafting/craft_query.gd"

var _station: StringName = &"hand"
var _tier: int = 99
var _query: Script = null
var _entries: Array[Dictionary] = []
var _categories: Array[Dictionary] = []      ## [{id, label, count}]
var _category: StringName = &""              ## &"" == all
var _search: String = ""
var _selected: Dictionary = {}
var _quantity: int = 1
var _preview_data: bool = false

var _inv: MenuInventoryAdapter = null
var _category_box: VBoxContainer = null
var _list_box: VBoxContainer = null
var _detail_box: VBoxContainer = null
var _queue_box: VBoxContainer = null
var _queue: Array[Dictionary] = []
var _queue_bars: Array[ProgressBar] = []


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.35
	placement = "center"
	anim = "scale"
	group = "gameplay"


## `Events.station_opened` sends `station_id`; `objects/types/stations.gd`
## sends `station` plus a `tier`. Accept either.
static func _station_of(context: Dictionary, fallback: StringName) -> StringName:
	if context.has("station_id"):
		return StringName(context["station_id"])
	if context.has("station"):
		return StringName(context["station"])
	return fallback


func _on_open(context: Dictionary) -> void:
	var incoming := _station_of(context, _station)
	_tier = int(context.get("tier", _tier))
	if incoming != _station and _list_box != null:
		_station = incoming
		_category = &""
		_reload()


func _build() -> void:
	_inv = MenuInventoryAdapter.player()
	_station = _station_of(ctx, &"hand")
	_tier = int(ctx.get("tier", 99))
	_query = _load_query()

	var body := frame(_station_label(), Vector2(960, 580))

	var columns := MenuWidgets.row(MenuTheme.GAP + 2)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	_category_box = MenuWidgets.col(2)
	var cat_scroll := MenuWidgets.scroll(_category_box)
	cat_scroll.custom_minimum_size = Vector2(180, 0)
	cat_scroll.size_flags_horizontal = Control.SIZE_FILL
	columns.add_child(MenuWidgets.well(cat_scroll))

	var mid := MenuWidgets.col(4)
	mid.custom_minimum_size = Vector2(280, 0)
	columns.add_child(mid)
	var search_field := MenuWidgets.line_edit("", "search recipes…")
	search_field.text_changed.connect(func(t: String) -> void:
		_search = t.strip_edges().to_lower()
		_reload())
	mid.add_child(search_field)
	_list_box = MenuWidgets.col(2)
	mid.add_child(MenuWidgets.well(MenuWidgets.scroll(_list_box)))

	var right := MenuWidgets.col()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_detail_box = MenuWidgets.col()
	_detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(MenuWidgets.scroll(_detail_box))
	right.add_child(MenuWidgets.rule())
	right.add_child(MenuWidgets.label("Queue", &"TinyLabel"))
	_queue_box = MenuWidgets.col(4)
	_queue_box.custom_minimum_size = Vector2(0, 90)
	right.add_child(_queue_box)

	_reload()
	_fill_queue()
	if not Events.inventory_changed.is_connected(_on_inventory_changed):
		Events.inventory_changed.connect(_on_inventory_changed)
	if Events.has_signal(&"recipe_learned"):
		Events.recipe_learned.connect(func(_id: String) -> void: _reload())


func _on_close() -> void:
	if Events.inventory_changed.is_connected(_on_inventory_changed):
		Events.inventory_changed.disconnect(_on_inventory_changed)


func _on_inventory_changed() -> void:
	_reload()


func _station_label() -> String:
	if _script_has(_query, &"station_label"):
		return String(_query.call(&"station_label", _station))
	return "Crafting" if _station == &"hand" else String(_station).capitalize()


# ============================================================== recipe sourcing
## `Object.has_method` is not reliable for a [Script]'s *static* functions, so
## fall back to the declared method list. Everything this panel calls on
## `CraftQuery` is static.
static func _script_has(scr: Script, method: StringName) -> bool:
	if scr == null:
		return false
	if scr.has_method(method):
		return true
	for m: Dictionary in scr.get_script_method_list():
		if StringName(m.get("name", &"")) == method:
			return true
	return false


func _load_query() -> Script:
	if not (ResourceLoader.exists(QUERY_PATH) or FileAccess.file_exists(QUERY_PATH)):
		return null
	var scr := load(QUERY_PATH) as Script
	if not _script_has(scr, &"list_for"):
		return null
	return scr


## Refresh categories, list and detail from the current filters.
func _reload() -> void:
	_gather()
	_fill_categories()
	_fill_list()
	if not _selected.is_empty():
		# Re-read the selected recipe so have/need counts stay live.
		var id := String(_selected["id"])
		_selected = {}
		for e: Dictionary in _entries:
			if String(e["id"]) == id:
				_selected = e
				break
	_fill_detail()


func _gather() -> void:
	_entries.clear()
	_categories.clear()
	_preview_data = false

	if _query != null:
		_gather_from_query()
		if not _entries.is_empty():
			return
	_gather_fallback()


func _gather_from_query() -> void:
	var inv: Variant = _inv.model
	var opts := {"include_locked": true}
	if _search != "":
		opts["search"] = _search

	var tree: Variant = null
	if _script_has(_query, &"category_tree"):
		tree = _query.call(&"category_tree", _station, inv, _tier, opts)
	if tree is Dictionary:
		var order: Variant = (tree as Dictionary).get("order", [])
		var nodes: Dictionary = (tree as Dictionary).get("nodes", {})
		if order is Array:
			for c: Variant in (order as Array):
				var node: Dictionary = nodes.get(c, {})
				_categories.append({
					"id": StringName(c),
					"label": String(node.get("label", String(c).capitalize())),
					"count": int(node.get("total", 0)),
					"craftable": int(node.get("craftable", 0)),
				})

	if _category != &"":
		opts["category"] = _category
	var list: Variant = _query.call(&"list_for", _station, inv, _tier, opts)
	if not (list is Array):
		return
	for r: Variant in (list as Array):
		var p: Variant = _query.call(&"preview", r, inv)
		if p is Dictionary and not (p as Dictionary).is_empty():
			_entries.append(_from_preview(p as Dictionary))


## `CraftQuery.preview` is already almost the shape this panel wants; this only
## flattens the parts that differ (outputs -> single result).
func _from_preview(p: Dictionary) -> Dictionary:
	var result: Dictionary = p.get("result", {})
	if result.is_empty():
		var outs: Variant = p.get("outputs", [])
		if outs is Array and not (outs as Array).is_empty():
			result = (outs as Array)[0]
	var inputs: Array[Dictionary] = []
	var raw: Variant = p.get("inputs", [])
	if raw is Array:
		for e: Variant in (raw as Array):
			if e is Dictionary:
				inputs.append(e as Dictionary)
	return {
		"id": String(p.get("id", "")),
		"name": String(p.get("name", "Recipe")),
		"description": String(p.get("description", "")),
		"category": StringName(p.get("category", &"misc")),
		"category_label": String(p.get("category_label", "Misc")),
		"time": maxf(0.15, float(p.get("time", 0.6))),
		"known": bool(p.get("known", true)),
		"craftable": bool(p.get("craftable", false)),
		"max_crafts": int(p.get("max_crafts", 0)),
		"missing_text": String(p.get("missing_text", "")),
		"inputs": inputs,
		"result": result,
	}


# ------------------------------------------------------------------- fallback
func _gather_fallback() -> void:
	var raw: Array = []
	if Recipes != null:
		if Recipes.has_method(&"for_station"):
			var r: Variant = Recipes.call(&"for_station", _station)
			if r is Array:
				raw = r as Array
		if raw.is_empty():
			var all: Variant = Recipes.get(&"all")
			if all is Array:
				raw = all as Array
	if raw.is_empty():
		raw = _stub_recipes()
		_preview_data = not raw.is_empty()

	var seen: Dictionary = {}
	for entry: Variant in raw:
		var e := _normalise(entry)
		if e.is_empty():
			continue
		if _category != &"" and StringName(e["category"]) != _category:
			continue
		if _search != "" and not String(e["name"]).to_lower().contains(_search):
			continue
		_entries.append(e)
		seen[StringName(e["category"])] = String(e["category_label"])
	for c: Variant in seen:
		_categories.append({"id": c, "label": String(seen[c]), "count": 0, "craftable": 0})


## Turn a plain recipe Dictionary (or a `CraftRecipe`-like object) into the
## panel's entry shape, resolving have/need counts ourselves.
func _normalise(entry: Variant) -> Dictionary:
	var d: Dictionary = {}
	if entry is Dictionary:
		d = entry as Dictionary
	elif entry is Object:
		var o := entry as Object
		d = {
			"id": String(o.get(&"id")) if o.get(&"id") != null else "",
			"inputs": o.get(&"inputs"),
			"outputs": o.get(&"outputs"),
			"category": o.get(&"category"),
			"time": o.get(&"time"),
			"description": o.get(&"description"),
		}
	else:
		return {}

	var out_id := &""
	var out_count := 1
	var out_spec: Variant = d.get("output", d.get("outputs", {}))
	if out_spec is Array and not (out_spec as Array).is_empty():
		out_spec = (out_spec as Array)[0]
	if out_spec is Dictionary:
		out_id = StringName((out_spec as Dictionary).get("id", ""))
		out_count = int((out_spec as Dictionary).get("count", 1))
	elif out_spec is String or out_spec is StringName:
		out_id = StringName(out_spec)
	if out_id == &"":
		return {}

	var inputs: Array[Dictionary] = []
	var raw_inputs: Variant = d.get("inputs", {})
	if raw_inputs is Dictionary:
		for k: Variant in (raw_inputs as Dictionary):
			inputs.append(_input_entry(StringName(k),
				int((raw_inputs as Dictionary)[k])))
	elif raw_inputs is Array:
		for e: Variant in (raw_inputs as Array):
			if e is Dictionary:
				inputs.append(_input_entry(StringName((e as Dictionary).get("id", "")),
					int((e as Dictionary).get("count", 1))))

	var ty := Items.get_type(out_id)
	var category := StringName(d.get("category",
		ty.category if ty != null else &"misc"))
	var possible := 999
	for e: Dictionary in inputs:
		possible = mini(possible, floori(float(e["have"]) / maxf(1.0, float(e["need"]))))
	if inputs.is_empty():
		possible = 0

	return {
		"id": String(d.get("id", out_id)),
		"name": String(d.get("name", ty.display_name if ty != null else String(out_id))),
		"description": String(d.get("description", ty.description if ty != null else "")),
		"category": category,
		"category_label": String(category).capitalize(),
		"time": maxf(0.15, float(d.get("time", 0.6))),
		"known": bool(d.get("known", true)),
		"craftable": possible > 0,
		"max_crafts": possible,
		"missing_text": "",
		"inputs": inputs,
		"result": _icon_entry(out_id, out_count),
	}


func _input_entry(id: StringName, need: int) -> Dictionary:
	var e := _icon_entry(id, need)
	var have := _inv.count_of(id)
	e["need"] = maxi(1, need)
	e["have"] = have
	e["enough"] = have >= need
	return e


func _icon_entry(id: StringName, count: int) -> Dictionary:
	var t := Items.get_type(id)
	return {
		"id": id,
		"name": t.display_name if t != null else String(id).capitalize(),
		"color": t.icon_color if t != null else MenuTheme.TEXT_MUTE,
		"shape": t.icon_shape if t != null else &"square",
		"count": maxi(1, count),
		"rarity": t.rarity if t != null else Const.RARITY_COMMON,
	}


## A few obviously-fake recipes derived from whatever items exist, so the
## window can be reviewed before any real recipe content lands.
func _stub_recipes() -> Array:
	var ids: Variant = Items.get(&"order") if Items != null else null
	if not (ids is Array) or (ids as Array).size() < 4:
		return []
	var list: Array = ids as Array
	var out: Array = []
	for i in mini(6, list.size() - 1):
		out.append({
			"id": "preview_%d" % i,
			"name": "%s (preview)" % String(list[i + 1]).capitalize(),
			"category": "preview",
			"inputs": {StringName(list[i]): 4},
			"output": {"id": String(list[i + 1]), "count": 1},
			"time": 0.8,
		})
	return out


# ==================================================================== filling
func _fill_categories() -> void:
	if _category_box == null:
		return
	MenuWidgets.clear(_category_box)
	var all := MenuWidgets.button("All", func() -> void:
		_category = &""
		_reload(), &"ListRowButton")
	all.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _category == &"":
		all.add_theme_color_override(&"font_color", MenuTheme.ACCENT)
	_category_box.add_child(all)

	for c: Dictionary in _categories:
		var id := StringName(c["id"])
		var text := String(c["label"])
		if int(c.get("count", 0)) > 0:
			text += "   %d/%d" % [int(c.get("craftable", 0)), int(c["count"])]
		var b := MenuWidgets.button(text, func() -> void:
			_category = id
			_reload(), &"ListRowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == _category:
			b.add_theme_color_override(&"font_color", MenuTheme.ACCENT)
		_category_box.add_child(b)

	if _preview_data:
		_category_box.add_child(MenuWidgets.label(
			"preview recipes", &"TinyLabel"))


func _fill_list() -> void:
	if _list_box == null:
		return
	MenuWidgets.clear(_list_box)
	if _entries.is_empty():
		_list_box.add_child(MenuWidgets.placeholder(
			"Nothing to make here yet.\nGather materials, or try another station."))
		return
	for e: Dictionary in _entries:
		_list_box.add_child(_recipe_row(e))


func _recipe_row(r: Dictionary) -> Control:
	var known := bool(r["known"])
	var craftable := bool(r["craftable"])
	var result: Dictionary = r["result"]

	var b := MenuWidgets.button("", func() -> void:
		_selected = r
		_quantity = 1
		_fill_detail()
		_fill_list(), &"ListRowButton")
	b.custom_minimum_size = Vector2(0, 38)

	var inner := MenuWidgets.row(6)
	var icon := TextureRect.new()
	icon.texture = MenuTheme.item_icon(result.get("color", MenuTheme.TEXT_MUTE),
		StringName(result.get("shape", &"square")), 22)
	icon.custom_minimum_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(icon)

	var text := String(r["name"])
	if int(result.get("count", 1)) > 1:
		text += " x%d" % int(result["count"])
	var l := MenuWidgets.label(text if known else "??? locked", &"SmallLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override(&"font_color",
		MenuTheme.TEXT if (known and craftable) else MenuTheme.TEXT_MUTE)
	inner.add_child(l)

	if not known:
		inner.add_child(MenuWidgets.badge("locked", MenuTheme.VIOLET))
	elif not craftable:
		inner.add_child(MenuWidgets.badge("missing", MenuTheme.BAD))
	elif String(_selected.get("id", "")) == String(r["id"]):
		inner.add_child(MenuWidgets.badge("selected", MenuTheme.ACCENT))

	MenuWidgets.button_overlay(b, inner, Vector4(6, 2, 6, 2))
	return b


func _fill_detail() -> void:
	if _detail_box == null:
		return
	MenuWidgets.clear(_detail_box)
	if _selected.is_empty():
		_detail_box.add_child(MenuWidgets.placeholder(
			"Pick a recipe to see what it needs."))
		return

	var r := _selected
	var result: Dictionary = r["result"]
	var out_stack := ItemStack.new(StringName(result.get("id", &"")),
		int(result.get("count", 1)))

	var head := MenuWidgets.row()
	var out_slot := MenuItemSlot.new(-1, "craft_output")
	out_slot.slot_kind = "output"
	out_slot.set_stack(out_stack)
	head.add_child(out_slot)
	var titles := MenuWidgets.col(2)
	titles.add_child(MenuWidgets.label(String(r["name"]), &"HeadLabel"))
	titles.add_child(MenuWidgets.label(
		"%s · %.1fs" % [String(r["category_label"]), float(r["time"])], &"TinyLabel"))
	head.add_child(titles)
	_detail_box.add_child(head)

	if String(r["description"]) != "":
		_detail_box.add_child(MenuWidgets.paragraph(String(r["description"]), &"TinyLabel"))

	if not bool(r["known"]):
		_detail_box.add_child(MenuWidgets.rule())
		_detail_box.add_child(MenuWidgets.paragraph(
			"You have not learned this recipe yet.", &"BadLabel"))
		return

	_detail_box.add_child(MenuWidgets.rule())
	_detail_box.add_child(MenuWidgets.label("Ingredients", &"TinyLabel"))
	for e: Variant in (r["inputs"] as Array):
		_detail_box.add_child(_ingredient_row(e as Dictionary))

	_detail_box.add_child(MenuWidgets.rule())
	_detail_box.add_child(_quantity_row())

	var possible := _max_craftable(r)
	var craft := MenuWidgets.button("Craft", _do_craft, &"AccentButton")
	craft.disabled = possible < 1
	craft.custom_minimum_size = Vector2(0, 36)
	_detail_box.add_child(craft)
	_detail_box.add_child(MenuWidgets.label(
		"You can make %d right now." % possible, &"TinyLabel"))
	if String(r.get("missing_text", "")) != "":
		_detail_box.add_child(MenuWidgets.paragraph(
			"Missing: " + String(r["missing_text"]), &"TinyLabel"))
	_detail_box.add_child(MenuWidgets.spacer())


func _ingredient_row(e: Dictionary) -> Control:
	var need := int(e.get("need", 1)) * _quantity
	var have := int(e.get("have", 0))
	var r := MenuWidgets.row(6)

	var icon := TextureRect.new()
	icon.texture = MenuTheme.item_icon(e.get("color", MenuTheme.TEXT_MUTE),
		StringName(e.get("shape", &"square")), 20)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(icon)

	var l := MenuWidgets.label(String(e.get("name", "?")), &"SmallLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)

	var counts := MenuWidgets.label("%d / %d" % [have, need], &"SmallLabel")
	counts.add_theme_color_override(&"font_color",
		MenuTheme.GOOD if have >= need else MenuTheme.BAD)
	r.add_child(counts)
	return r


func _quantity_row() -> Control:
	var r := MenuWidgets.row(4)
	r.add_child(MenuWidgets.label("Quantity", &"DimLabel"))
	r.add_child(MenuWidgets.spacer())
	r.add_child(MenuWidgets.small_button("−", func() -> void:
		_quantity = maxi(1, _quantity - 1)
		_fill_detail()))
	var l := MenuWidgets.label(str(_quantity), &"AccentLabel")
	l.custom_minimum_size = Vector2(36, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(l)
	r.add_child(MenuWidgets.small_button("+", func() -> void:
		_quantity = mini(999, _quantity + 1)
		_fill_detail()))
	r.add_child(MenuWidgets.small_button("Max", func() -> void:
		_quantity = maxi(1, _max_craftable(_selected))
		_fill_detail()))
	return r


func _max_craftable(r: Dictionary) -> int:
	if r.is_empty() or not bool(r.get("known", true)):
		return 0
	if Recipes != null and Recipes.has_method(&"max_crafts") and _inv.is_real():
		return maxi(0, int(Recipes.call(&"max_crafts", String(r["id"]), _inv.model)))
	return maxi(0, int(r.get("max_crafts", 0)))


# ===================================================================== queue
func _do_craft() -> void:
	if _selected.is_empty():
		return
	var n := mini(_quantity, _max_craftable(_selected))
	if n <= 0:
		Events.toast("Not enough materials.", "warn")
		return
	_queue.append({
		"recipe": _selected, "remaining": n,
		"progress": 0.0, "time": float(_selected["time"]),
	})
	_fill_queue()


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	var job: Dictionary = _queue[0]
	job["progress"] = float(job["progress"]) + delta
	if float(job["progress"]) < float(job["time"]):
		if not _queue_bars.is_empty() and is_instance_valid(_queue_bars[0]):
			_queue_bars[0].value = float(job["progress"])
		return
	job["progress"] = 0.0
	if _craft_once(job["recipe"]):
		job["remaining"] = int(job["remaining"]) - 1
	else:
		Events.toast("Crafting interrupted — materials gone.", "warn")
		job["remaining"] = 0
	if int(job["remaining"]) <= 0:
		_queue.remove_at(0)
	_reload()
	_fill_queue()


func _craft_once(r: Dictionary) -> bool:
	if Recipes != null and Recipes.has_method(&"craft") and _inv.is_real():
		if bool(Recipes.call(&"craft", String(r["id"]), _inv.model, 1)):
			Game.bump_stat("items_crafted", 1.0)
			return true
		return false

	# Local path — used by the preview adapter and by any stubbed registry.
	if _max_craftable(r) <= 0:
		return false
	for e: Variant in (r["inputs"] as Array):
		var entry: Dictionary = e
		_inv.remove(StringName(entry["id"]), int(entry["need"]))
	var result: Dictionary = r["result"]
	var id := StringName(result.get("id", &""))
	var count := int(result.get("count", 1))
	var made := Items.make(id, count) if Items.has_method(&"make") \
		else ItemStack.new(id, count)
	_inv.add(made)
	if not made.is_empty():
		UI.spill_to_world(made)
	Events.item_crafted.emit(String(id), count)
	Game.bump_stat("items_crafted", 1.0)
	return true


func _fill_queue() -> void:
	if _queue_box == null:
		return
	MenuWidgets.clear(_queue_box)
	_queue_bars.clear()
	if _queue.is_empty():
		_queue_box.add_child(MenuWidgets.label("Nothing queued.", &"TinyLabel"))
		return
	for i in mini(3, _queue.size()):
		var job: Dictionary = _queue[i]
		var r: Dictionary = job["recipe"]
		var row := MenuWidgets.col(2)
		var head := MenuWidgets.row(4)
		head.add_child(MenuWidgets.label("%s x%d" % [String(r["name"]),
			int(job["remaining"])], &"SmallLabel"))
		head.add_child(MenuWidgets.spacer())
		var idx := i
		head.add_child(MenuWidgets.small_button("✕", func() -> void:
			if idx < _queue.size():
				_queue.remove_at(idx)
			_fill_queue()))
		row.add_child(head)
		var bar := MenuWidgets.meter(float(job["progress"]), float(job["time"]),
			MenuTheme.ACCENT, 6)
		_queue_bars.append(bar)
		row.add_child(bar)
		_queue_box.add_child(row)
