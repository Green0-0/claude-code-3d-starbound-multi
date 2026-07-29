## Quest journal — Active / Completed / Failed, objectives with progress bars,
## reward previews and a Track button that feeds the HUD.
##
## Reads whatever the quests agent exposes, in this order:
##   `Quests.list(state)` -> `Quests.active` / `Quests.completed` / `Quests.failed`
## and enriches each id with `Quests.quest_def(id)` / `Quests.objectives(id)`
## when those exist. Everything is optional; a missing quest module shows an
## honest empty state.
##
## Tracking writes `UI.tracked_quest` and emits `UI.quest_tracked(id)`, which is
## the contract the HUD agent should read.
extends MenuPanel

const STATES := ["Active", "Completed", "Failed"]

var _tab: int = 0
var _list_box: VBoxContainer = null
var _detail_box: VBoxContainer = null
var _selected: Dictionary = {}


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.4
	placement = "center"
	anim = "scale"
	group = "gameplay"


func _build() -> void:
	var body := frame("Quest Log", Vector2(820, 520))

	var strip := MenuWidgets.tab_strip(PackedStringArray(STATES), func(i: int) -> void:
		_tab = i
		_selected = {}
		_fill_list()
		_fill_detail())
	body.add_child(strip)
	body.add_child(MenuWidgets.rule())

	var columns := MenuWidgets.row(MenuTheme.GAP + 2)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	_list_box = MenuWidgets.col(3)
	var list_scroll := MenuWidgets.scroll(_list_box)
	list_scroll.custom_minimum_size = Vector2(280, 0)
	list_scroll.size_flags_horizontal = Control.SIZE_FILL
	columns.add_child(MenuWidgets.well(list_scroll))

	_detail_box = MenuWidgets.col()
	var detail_scroll := MenuWidgets.scroll(_detail_box)
	columns.add_child(detail_scroll)

	for sig: Signal in [Events.quest_started, Events.quest_completed, Events.quest_failed]:
		sig.connect(func(_id: String) -> void: _fill_list())
	Events.quest_objective_updated.connect(
		func(_q: String, _i: int, _p: int, _g: int) -> void: _fill_detail())

	_fill_list()
	_fill_detail()


# ------------------------------------------------------------------ sourcing
func _quests_for_state(state: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = null
	if Quests != null:
		if Quests.has_method(&"list"):
			raw = Quests.call(&"list", STATES[state].to_lower())
		if raw == null:
			raw = Quests.get(StringName(["active", "completed", "failed"][state]))
	if raw is Array:
		for e: Variant in (raw as Array):
			var d := _normalise(e)
			if not d.is_empty():
				out.append(d)
	elif raw is Dictionary:
		for k: Variant in (raw as Dictionary):
			var d := _normalise((raw as Dictionary)[k], String(k))
			if not d.is_empty():
				out.append(d)
	return out


func _normalise(entry: Variant, fallback_id: String = "") -> Dictionary:
	var id := fallback_id
	var src: Dictionary = {}
	if entry is Dictionary:
		src = entry as Dictionary
		id = String(src.get("id", fallback_id))
	elif entry is String or entry is StringName:
		id = String(entry)
	if id == "":
		return {}

	# Enrich from the definition table when one exists.
	if Quests != null:
		for getter: StringName in [&"quest_def", &"definition", &"get_quest"]:
			if Quests.has_method(getter):
				var d: Variant = Quests.call(getter, id)
				if d is Dictionary:
					for k: Variant in (d as Dictionary):
						if not src.has(k):
							src[k] = (d as Dictionary)[k]
					break

	var objectives: Array = []
	var raw_obj: Variant = src.get("objectives", null)
	if raw_obj == null and Quests != null and Quests.has_method(&"objectives"):
		raw_obj = Quests.call(&"objectives", id)
	if raw_obj is Array:
		for o: Variant in (raw_obj as Array):
			if o is Dictionary:
				objectives.append({
					"text": String((o as Dictionary).get("text",
						(o as Dictionary).get("description", "Objective"))),
					"progress": int((o as Dictionary).get("progress", 0)),
					"goal": maxi(1, int((o as Dictionary).get("goal",
						(o as Dictionary).get("count", 1)))),
				})
			else:
				objectives.append({"text": String(o), "progress": 0, "goal": 1})

	return {
		"id": id,
		"name": String(src.get("name", src.get("title", id.capitalize().replace("_", " ")))),
		"description": String(src.get("description", "")),
		"giver": String(src.get("giver", "")),
		"objectives": objectives,
		"rewards": src.get("rewards", {}),
	}


# -------------------------------------------------------------------- filling
func _fill_list() -> void:
	if _list_box == null:
		return
	MenuWidgets.clear(_list_box)
	var quests := _quests_for_state(_tab)
	if quests.is_empty():
		_list_box.add_child(MenuWidgets.placeholder(
			"No %s quests.\n\nTalk to the people you meet — they know things the\n"
			% STATES[_tab].to_lower()
			+ "world will not tell you."))
		return
	for q: Dictionary in quests:
		var quest := q
		var b := MenuWidgets.button("", func() -> void:
			_selected = quest
			_fill_detail()
			_fill_list(), &"ListRowButton")
		b.custom_minimum_size = Vector2(0, 44)

		var inner := MenuWidgets.col(1)
		var head := MenuWidgets.row(4)
		var tracked := _is_tracked(String(quest["id"]))
		var name_label := MenuWidgets.label(String(quest["name"]), &"SmallLabel")
		name_label.add_theme_color_override(&"font_color",
			MenuTheme.ACCENT if tracked else MenuTheme.TEXT)
		head.add_child(name_label)
		head.add_child(MenuWidgets.spacer())
		if tracked:
			head.add_child(MenuWidgets.badge("tracked", MenuTheme.ACCENT))
		inner.add_child(head)
		inner.add_child(MenuWidgets.label(_progress_summary(quest), &"TinyLabel"))
		MenuWidgets.button_overlay(b, inner)
		_list_box.add_child(b)


func _progress_summary(q: Dictionary) -> String:
	var objectives: Array = q.get("objectives", [])
	if objectives.is_empty():
		return String(q.get("giver", "")) if q.get("giver", "") != "" else "no objectives"
	var done := 0
	for o: Variant in objectives:
		if int((o as Dictionary)["progress"]) >= int((o as Dictionary)["goal"]):
			done += 1
	return "%d / %d objectives" % [done, objectives.size()]


func _fill_detail() -> void:
	if _detail_box == null:
		return
	MenuWidgets.clear(_detail_box)
	if _selected.is_empty():
		_detail_box.add_child(MenuWidgets.placeholder("Select a quest."))
		return

	var q := _selected
	_detail_box.add_child(MenuWidgets.label(String(q["name"]), &"HeadLabel"))
	if String(q.get("giver", "")) != "":
		_detail_box.add_child(MenuWidgets.label("from %s" % String(q["giver"]), &"TinyLabel"))
	if String(q.get("description", "")) != "":
		_detail_box.add_child(MenuWidgets.paragraph(String(q["description"]), &"DimLabel"))

	_detail_box.add_child(MenuWidgets.rule())
	_detail_box.add_child(MenuWidgets.label("Objectives", &"TinyLabel"))
	var objectives: Array = q.get("objectives", [])
	if objectives.is_empty():
		_detail_box.add_child(MenuWidgets.label("—", &"SmallLabel"))
	for o: Variant in objectives:
		var obj: Dictionary = o
		var progress := int(obj["progress"])
		var goal := int(obj["goal"])
		var done := progress >= goal
		var row := MenuWidgets.col(1)
		row.add_child(MenuWidgets.stat_row(
			("✔ " if done else "○ ") + String(obj["text"]),
			"%d / %d" % [progress, goal],
			MenuTheme.GOOD if done else MenuTheme.TEXT_DIM))
		if goal > 1:
			row.add_child(MenuWidgets.meter(float(progress), float(goal),
				MenuTheme.GOOD if done else MenuTheme.ACCENT, 5))
		_detail_box.add_child(row)

	_detail_box.add_child(MenuWidgets.rule())
	_detail_box.add_child(MenuWidgets.label("Rewards", &"TinyLabel"))
	_detail_box.add_child(_rewards(q.get("rewards", {})))

	_detail_box.add_child(MenuWidgets.spacer())
	if _tab == 0:
		var f := MenuWidgets.row()
		var tracked := _is_tracked(String(q["id"]))
		f.add_child(MenuWidgets.button("Untrack" if tracked else "Track on HUD",
			func() -> void: _track(String(q["id"]), not tracked),
			&"AccentButton" if not tracked else &"GhostButton"))
		f.add_child(MenuWidgets.spacer())
		f.add_child(MenuWidgets.button("Abandon", func() -> void: _abandon(String(q["id"])),
			&"DangerButton"))
		_detail_box.add_child(f)


func _rewards(raw: Variant) -> Control:
	var c := MenuWidgets.col(2)
	var any := false
	# `QuestDef.reward_lines()` hands back plain strings — the quest module has
	# already resolved item names and counts, so just show them.
	if raw is PackedStringArray or (raw is Array and _all_strings(raw as Array)):
		for line: Variant in raw:
			if String(line) == "":
				continue
			var l := MenuWidgets.label("• " + String(line), &"SmallLabel")
			l.add_theme_color_override(&"font_color", MenuTheme.WARN)
			c.add_child(l)
			any = true
	elif raw is Dictionary:
		var d: Dictionary = raw
		if d.has("pixels") and int(d["pixels"]) > 0:
			c.add_child(MenuWidgets.stat_row("Pixels", str(int(d["pixels"])), MenuTheme.WARN))
			any = true
		var items: Variant = d.get("items", d)
		if items is Dictionary:
			for k: Variant in (items as Dictionary):
				if String(k) == "pixels":
					continue
				var stack := ItemStack.new(StringName(k), int((items as Dictionary)[k]))
				c.add_child(_reward_row(stack))
				any = true
	elif raw is Array:
		for e: Variant in (raw as Array):
			if e is Dictionary:
				c.add_child(_reward_row(ItemStack.new(
					StringName((e as Dictionary).get("id", "")),
					int((e as Dictionary).get("count", 1)))))
				any = true
	if not any:
		c.add_child(MenuWidgets.label("—", &"SmallLabel"))
	return c


static func _all_strings(a: Array) -> bool:
	if a.is_empty():
		return false
	for e: Variant in a:
		if not (e is String or e is StringName):
			return false
	return true


func _reward_row(stack: ItemStack) -> Control:
	var r := MenuWidgets.row(6)
	var icon := TextureRect.new()
	icon.texture = MenuTheme.stack_icon(stack, 20)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(icon)
	var l := MenuWidgets.label(stack.display_name(), &"SmallLabel")
	l.add_theme_color_override(&"font_color", MenuTheme.rarity_color(stack.rarity()))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	r.add_child(MenuWidgets.label("x%d" % stack.count, &"SmallLabel"))
	return r


# ------------------------------------------------------------------- actions
## The quest module owns the truth when it is present; UI mirrors it so the HUD
## has a single place to read from either way.
func _is_tracked(quest_id: String) -> bool:
	if Quests != null:
		var t: Variant = Quests.get(&"tracked")
		if t != null:
			return String(t) == quest_id
	return UI.tracked_quest == quest_id


func _track(quest_id: String, on: bool) -> void:
	var value := quest_id if on else ""
	UI.tracked_quest = value
	UI.quest_tracked.emit(value)
	for setter: StringName in [&"set_tracked", &"track"]:
		if Quests != null and Quests.has_method(setter):
			Quests.call(setter, value)
			break
	Events.toast("Tracking %s" % quest_id.capitalize().replace("_", " ") if on
		else "Stopped tracking.", "quest")
	_fill_list()
	_fill_detail()


func _abandon(quest_id: String) -> void:
	var yes: bool = await UI.confirm("Abandon quest",
		"Progress on this quest is lost. You may be able to take it again.",
		"Abandon", "Keep", true)
	if not yes:
		return
	if Quests != null and Quests.has_method(&"abandon"):
		Quests.call(&"abandon", quest_id)
	Events.quest_failed.emit(quest_id)
	_selected = {}
	_fill_list()
	_fill_detail()
