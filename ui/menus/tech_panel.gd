## Techs: the equip slots on the left, the unlock tree on the right.
##
## Data comes from `tech/tech_catalog.gd` (`ALL`, `SLOTS`) read through the
## script's constant map, so this panel never hard-depends on that file existing.
## State comes from the `Tech` autoload — `equipped`, `is_unlocked(id)`,
## `requirements_met(id)`, `unlock(id)`, `equip(slot, id)` — each guarded.
## With none of it present, a clearly-labelled preview tree is shown instead.
##
## The tree is grouped by slot and laid out in prerequisite depth order, so a
## tech always appears to the right of everything it needs.
extends MenuPanel

const CATALOG_PATH := "res://tech/tech_catalog.gd"
const FALLBACK_SLOTS: Array[StringName] = [&"head", &"body", &"legs"]

var _techs: Array[Dictionary] = []
var _preview: bool = false
var _slots_box: VBoxContainer = null
var _tree_box: VBoxContainer = null
var _selected: Dictionary = {}
var _catalog: Script = null


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.45
	placement = "center"
	anim = "scale"
	group = "gameplay"


func _build() -> void:
	_catalog = _load_catalog()
	_load_techs()

	var body := frame("Tech", Vector2(900, 560))
	if _preview:
		body.add_child(MenuWidgets.label(
			"Preview tree — the tech module has not registered anything yet.",
			&"TinyLabel"))

	var columns := MenuWidgets.row(MenuTheme.GAP + 4)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	_slots_box = MenuWidgets.col()
	_slots_box.custom_minimum_size = Vector2(250, 0)
	columns.add_child(MenuWidgets.card(_slots_box))

	_tree_box = MenuWidgets.col()
	var sc := MenuWidgets.scroll(_tree_box)
	columns.add_child(MenuWidgets.well(sc))

	_fill_slots()
	_fill_tree()
	if Events.has_signal(&"tech_equipped"):
		Events.tech_equipped.connect(func(_s: String, _t: String) -> void: _fill_slots())


# ------------------------------------------------------------------ sourcing
static func _load_catalog() -> Script:
	if not (ResourceLoader.exists(CATALOG_PATH) or FileAccess.file_exists(CATALOG_PATH)):
		return null
	return load(CATALOG_PATH) as Script


## Script constants (`const ALL`, `const SLOTS`) are not reachable through
## `Object.get()`; the constant map is.
func _catalog_const(name: StringName) -> Variant:
	if _catalog == null:
		return null
	return _catalog.get_script_constant_map().get(name)


func _load_techs() -> void:
	_techs.clear()
	_preview = false
	var entries: Array = []
	var all: Variant = _catalog_const(&"ALL")
	if all is Array:
		entries = all as Array
	if entries.is_empty() and Tech != null:
		for getter: StringName in [&"list_all", &"all_techs"]:
			if Tech.has_method(getter):
				var r: Variant = Tech.call(getter)
				if r is Array:
					entries = r as Array
					break
	if entries.is_empty():
		entries = _preview_techs()
		_preview = not entries.is_empty()

	for e: Variant in entries:
		if e is Dictionary:
			_techs.append(_normalise(e as Dictionary))
	# Prerequisite depth decides the column a tech sits in.
	for t: Dictionary in _techs:
		t["depth"] = _depth_of(StringName(t["id"]), 0)


func _normalise(d: Dictionary) -> Dictionary:
	var requires: Array[StringName] = []
	var raw: Variant = d.get("requires", [])
	if raw is Array:
		for r: Variant in (raw as Array):
			requires.append(StringName(r))
	return {
		"id": StringName(d.get("id", &"")),
		"name": String(d.get("name",
			String(d.get("id", "tech")).capitalize().replace("_", " "))),
		"description": String(d.get("desc", d.get("description", ""))),
		"slot": StringName(d.get("slot", &"body")),
		"requires": requires,
		"price": int(d.get("price", 0)),
		"energy": float(d.get("energy", 0.0)),
		"mode": String(d.get("mode", "")),
		"color": d.get("color", MenuTheme.CYAN),
		"depth": 0,
	}


func _depth_of(id: StringName, guard: int) -> int:
	if guard > 8:
		return guard
	var t := _find(id)
	if t.is_empty():
		return 0
	var best := 0
	for r: Variant in (t["requires"] as Array):
		best = maxi(best, _depth_of(StringName(r), guard + 1) + 1)
	return best


func _find(id: StringName) -> Dictionary:
	for t: Dictionary in _techs:
		if t["id"] == id:
			return t
	return {}


## Preview content built around this game's own mechanic, so an empty tech
## module still reads as a design sketch rather than filler.
func _preview_techs() -> Array:
	return [
		{"id": &"plane_dash", "name": "Plane Dash", "slot": &"legs",
			"desc": "Dash along the current plane, passing through one voxel of wall."},
		{"id": &"layer_blink", "name": "Layer Blink", "slot": &"body",
			"requires": [&"plane_dash"],
			"desc": "Shift two layers at once, even when the first is solid."},
		{"id": &"flip_glide", "name": "Flip Glide", "slot": &"body",
			"requires": [&"plane_dash"],
			"desc": "Hold the flip to hang in the air while the world turns."},
		{"id": &"depth_sight", "name": "Depth Sight", "slot": &"head",
			"requires": [&"layer_blink"],
			"desc": "Outline ores and cavities in the twelve layers behind you."},
	]


# -------------------------------------------------------------------- state
func _slots() -> Array[StringName]:
	for source: Variant in [ctx.get("slots"), _catalog_const(&"SLOTS")]:
		if source is Array and not (source as Array).is_empty():
			var out: Array[StringName] = []
			for e: Variant in (source as Array):
				out.append(StringName(e))
			return out
	if Tech != null:
		var s: Variant = Tech.get(&"slots")
		if s is Array and not (s as Array).is_empty():
			var out2: Array[StringName] = []
			for e: Variant in (s as Array):
				out2.append(StringName(e))
			return out2
	return FALLBACK_SLOTS


func _equipped(slot_name: StringName) -> StringName:
	if Tech != null:
		if Tech.has_method(&"equipped_id"):
			return StringName(Tech.call(&"equipped_id", String(slot_name)))
		var e: Variant = Tech.get(&"equipped")
		if e is Dictionary:
			var d: Dictionary = e
			return StringName(d.get(slot_name, d.get(String(slot_name), "")))
	return &""


func _is_unlocked(id: StringName) -> bool:
	if _preview:
		return true
	if Tech != null:
		if Tech.has_method(&"is_unlocked"):
			return bool(Tech.call(&"is_unlocked", id))
		var u: Variant = Tech.get(&"unlocked")
		if u is Dictionary:
			return (u as Dictionary).has(id) or (u as Dictionary).has(String(id))
	return false


func _requirements_met(id: StringName) -> bool:
	if Tech != null and Tech.has_method(&"requirements_met"):
		return bool(Tech.call(&"requirements_met", id))
	var t := _find(id)
	for r: Variant in (t.get("requires", []) as Array):
		if not _is_unlocked(StringName(r)):
			return false
	return true


# ------------------------------------------------------------------- filling
func _fill_slots() -> void:
	if _slots_box == null:
		return
	MenuWidgets.clear(_slots_box)
	_slots_box.add_child(MenuWidgets.label("Equipped", &"TinyLabel"))
	for slot_name: StringName in _slots():
		var equipped := _equipped(slot_name)
		var card := MenuWidgets.col(2)
		card.add_child(MenuWidgets.label(String(slot_name).capitalize(), &"TinyLabel"))
		var b := MenuWidgets.button(
			_name_of(equipped) if equipped != &"" else "— empty —",
			func() -> void: _equip_selected(slot_name))
		b.custom_minimum_size = Vector2(0, 40)
		if equipped != &"":
			b.add_theme_color_override(&"font_color", MenuTheme.CYAN)
		card.add_child(b)
		if equipped != &"":
			card.add_child(MenuWidgets.small_button("Unequip",
				func() -> void: _do_equip(slot_name, &"")))
		_slots_box.add_child(MenuWidgets.card(card))

	_slots_box.add_child(MenuWidgets.rule())
	_slots_box.add_child(MenuWidgets.paragraph(
		"Select a tech on the right, then click a slot to fit it. Each tech only "
		+ "works in the slot it was built for.", &"TinyLabel"))
	_slots_box.add_child(MenuWidgets.spacer())


func _fill_tree() -> void:
	if _tree_box == null:
		return
	MenuWidgets.clear(_tree_box)
	if _techs.is_empty():
		_tree_box.add_child(MenuWidgets.placeholder("No techs exist yet."))
		return

	for slot_name: StringName in _slots():
		var in_slot: Array[Dictionary] = []
		for t: Dictionary in _techs:
			if StringName(t["slot"]) == slot_name:
				in_slot.append(t)
		if in_slot.is_empty():
			continue
		in_slot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["depth"]) != int(b["depth"]):
				return int(a["depth"]) < int(b["depth"])
			return String(a["name"]) < String(b["name"]))

		_tree_box.add_child(MenuWidgets.label(
			String(slot_name).to_upper(), &"TinyLabel"))
		var row := MenuWidgets.row(6)
		var scroller := MenuWidgets.scroll(row, true)
		scroller.custom_minimum_size = Vector2(0, 122)
		scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		for t: Dictionary in in_slot:
			row.add_child(_tech_card(t))
		_tree_box.add_child(scroller)
		_tree_box.add_child(MenuWidgets.rule())


func _tech_card(t: Dictionary) -> Control:
	var id := StringName(t["id"])
	var unlocked := _is_unlocked(id)
	var selected: bool = _selected.get("id", &"") == id
	var wrapper := MenuWidgets.col(2)
	wrapper.custom_minimum_size = Vector2(190, 0)

	var b := Button.new()
	b.custom_minimum_size = Vector2(190, 88)
	b.theme_type_variation = &"ListRowButton"
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void:
		_selected = t
		_fill_tree())
	wrapper.add_child(b)

	var inner := MenuWidgets.col(2)
	var head := MenuWidgets.row(4)
	var title := MenuWidgets.label(String(t["name"]), &"SmallLabel")
	var tint: Color = t.get("color", MenuTheme.CYAN)
	title.add_theme_color_override(&"font_color",
		MenuTheme.ACCENT if selected else (tint if unlocked else MenuTheme.TEXT_MUTE))
	head.add_child(title)
	head.add_child(MenuWidgets.spacer())
	if unlocked:
		head.add_child(MenuWidgets.badge("owned", MenuTheme.GOOD))
	inner.add_child(head)

	inner.add_child(MenuWidgets.paragraph(
		String(t["description"]) if unlocked else _locked_text(t), &"TinyLabel"))

	if unlocked and float(t.get("energy", 0.0)) > 0.0:
		inner.add_child(MenuWidgets.label("%.0f energy · %s"
			% [float(t["energy"]), String(t.get("mode", "instant"))], &"TinyLabel"))

	MenuWidgets.button_overlay(b, inner, Vector4(8, 6, 8, 6))
	if not unlocked:
		var can := _requirements_met(id)
		var unlock_button := MenuWidgets.small_button("Unlock", func() -> void: _unlock(t))
		unlock_button.disabled = not can
		wrapper.add_child(unlock_button)
	return wrapper


func _locked_text(t: Dictionary) -> String:
	var reqs: Array = t.get("requires", [])
	if reqs.is_empty():
		var price := int(t.get("price", 0))
		return "Locked. Found as a tech card." if price <= 0 \
			else "Locked. Worth about %d px." % price
	var names := PackedStringArray()
	for r: Variant in reqs:
		names.append(_name_of(StringName(r)))
	return "Needs " + ", ".join(names) + "."


func _name_of(id: StringName) -> String:
	var t := _find(id)
	if not t.is_empty():
		return String(t["name"])
	return String(id).capitalize().replace("_", " ")


# ------------------------------------------------------------------- actions
func _equip_selected(slot_name: StringName) -> void:
	if _selected.is_empty():
		Events.toast("Pick a tech first.", "warn")
		return
	var id := StringName(_selected["id"])
	if StringName(_selected["slot"]) != slot_name:
		Events.toast("%s fits the %s slot." % [String(_selected["name"]),
			String(_selected["slot"])], "warn")
		return
	if not _is_unlocked(id):
		Events.toast("That tech is still locked.", "warn")
		return
	_do_equip(slot_name, id)


func _do_equip(slot_name: StringName, id: StringName) -> void:
	if Tech != null and Tech.has_method(&"equip"):
		Tech.call(&"equip", String(slot_name), id)
	Events.tech_equipped.emit(String(slot_name), String(id))
	if id != &"":
		Events.toast("Equipped %s." % _name_of(id), "info")
	_fill_slots()


func _unlock(t: Dictionary) -> void:
	var id := StringName(t["id"])
	if not _requirements_met(id):
		Events.toast("Prerequisites not met.", "warn")
		return
	if Tech != null and Tech.has_method(&"unlock"):
		Tech.call(&"unlock", id)
	if not _is_unlocked(id):
		Events.toast("Techs are acquired from tech cards, not bought here.", "warn")
	_fill_tree()
	_fill_slots()
