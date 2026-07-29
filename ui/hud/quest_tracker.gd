## Compact active-objective list on the right edge. Invisible until the player
## actually has a quest, so an empty save shows a clean screen.
##
## Consumes: `quest_started`, `quest_objective_updated`, `quest_completed`,
## `quest_failed`. Titles and objective text are pulled from the `Quests`
## singleton when it exposes them; it is a stub until the quest agent lands, so
## every lookup is probed by name and falls back to a prettified quest id and
## "Objective N" rows built purely from the signal payload.
class_name HudQuestTracker
extends Control

const ROW_H := 15.0
const TITLE_H := 18.0
const HOLD_AFTER_END := 3.5


class QuestRow extends RefCounted:
	var id := ""
	var title := ""
	var objectives: Array[Dictionary] = []
	var appear := 0.0
	var state := 0                    ## 0 active, 1 complete, 2 failed
	var end_t := 0.0
	var flash := 0.0


var _rows: Array[QuestRow] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.quest_started.connect(_on_started)
	Events.quest_objective_updated.connect(_on_objective)
	Events.quest_completed.connect(_on_completed)
	Events.quest_failed.connect(_on_failed)


# -------------------------------------------------------------------- signals
func _on_started(quest_id: String) -> void:
	var row := _row(quest_id, true)
	row.appear = 0.0
	row.flash = 1.0


func _on_objective(quest_id: String, index: int, progress: int, goal: int) -> void:
	var row := _row(quest_id, true)
	while row.objectives.size() <= index:
		row.objectives.append({
			"text": _objective_text(quest_id, row.objectives.size()),
			"progress": 0, "goal": 1, "flash": 0.0, "shown": 0.0,
		})
	var o: Dictionary = row.objectives[index]
	o["progress"] = progress
	o["goal"] = maxi(1, goal)
	o["flash"] = 1.0


func _on_completed(quest_id: String) -> void:
	var row := _row(quest_id, false)
	if row == null:
		return
	row.state = 1
	row.end_t = _time
	row.flash = 1.0
	for o: Dictionary in row.objectives:
		o["progress"] = int(o["goal"])


func _on_failed(quest_id: String) -> void:
	var row := _row(quest_id, false)
	if row == null:
		return
	row.state = 2
	row.end_t = _time
	row.flash = 1.0


func _row(quest_id: String, create: bool) -> QuestRow:
	for r: QuestRow in _rows:
		if r.id == quest_id:
			return r
	if not create:
		return null
	var row := QuestRow.new()
	row.id = quest_id
	row.title = _quest_title(quest_id)
	for od: Dictionary in _quest_objectives(quest_id):
		row.objectives.append(od)
	_rows.append(row)
	while _rows.size() > 5:
		_rows.pop_front()
	return row


# --------------------------------------------------- defensive Quests lookups
func _quest_dict(quest_id: String) -> Dictionary:
	for m: StringName in [&"quest_data", &"get_quest", &"definition", &"info"]:
		if Quests.has_method(m):
			var v: Variant = Quests.call(m, quest_id)
			if v is Dictionary:
				return v
	var active: Variant = Quests.get(&"active")
	if active is Dictionary:
		var a: Dictionary = active
		if a.has(quest_id) and a[quest_id] is Dictionary:
			return a[quest_id]
	return {}


func _quest_title(quest_id: String) -> String:
	var d := _quest_dict(quest_id)
	for k: String in ["title", "name", "display_name"]:
		if d.has(k) and d[k] is String and not String(d[k]).is_empty():
			return String(d[k])
	if Quests.has_method(&"quest_title"):
		var v: Variant = Quests.call(&"quest_title", quest_id)
		if v is String and not String(v).is_empty():
			return String(v)
	return quest_id.replace("_", " ").capitalize()


func _quest_objectives(quest_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := _quest_dict(quest_id)
	var raw: Variant = d.get("objectives")
	if raw is Array:
		var arr: Array = raw
		for i in arr.size():
			var e: Variant = arr[i]
			var txt := "Objective %d" % (i + 1)
			var goal := 1
			var prog := 0
			if e is String:
				txt = String(e)
			elif e is Dictionary:
				var ed: Dictionary = e
				txt = String(ed.get("text", ed.get("description", txt)))
				goal = maxi(1, int(ed.get("goal", ed.get("count", 1))))
				prog = int(ed.get("progress", 0))
			out.append({"text": txt, "progress": prog, "goal": goal, "flash": 0.0, "shown": 0.0})
	return out


func _objective_text(quest_id: String, index: int) -> String:
	var objs := _quest_objectives(quest_id)
	if index < objs.size():
		return String(objs[index]["text"])
	return "Objective %d" % (index + 1)


# ------------------------------------------------------------------- updating
func _process(delta: float) -> void:
	_time += delta
	var i := _rows.size() - 1
	var busy := false
	while i >= 0:
		var r := _rows[i]
		r.appear = minf(1.0, r.appear + delta * 3.0)
		r.flash = maxf(0.0, r.flash - delta * 1.6)
		for o: Dictionary in r.objectives:
			o["flash"] = maxf(0.0, float(o["flash"]) - delta * 1.6)
			o["shown"] = move_toward(float(o["shown"]),
				float(o["progress"]) / maxf(1.0, float(o["goal"])), delta * 1.5)
		if r.state != 0 and _time - r.end_t > HOLD_AFTER_END:
			_rows.remove_at(i)
		else:
			busy = true
		i -= 1
	visible = not _rows.is_empty()
	if busy:
		queue_redraw()


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	if _rows.is_empty():
		return
	var total := 10.0
	for r: QuestRow in _rows:
		total += _row_height(r)
	var panel_h := minf(size.y, total + 14.0)
	var body := HudTheme.framed_panel(self, Rect2(Vector2.ZERO, Vector2(size.x, panel_h)),
		"OBJECTIVES", HudTheme.QUEST)

	var y := body.position.y
	for r: QuestRow in _rows:
		var h := _row_height(r)
		if y + h > body.position.y + body.size.y:
			break
		_draw_row(r, Rect2(Vector2(body.position.x, y), Vector2(body.size.x, h)))
		y += h


## Inner classes cannot see the outer script's constants, so row metrics live
## here rather than on `QuestRow`.
func _row_height(r: QuestRow) -> float:
	return TITLE_H + float(r.objectives.size()) * ROW_H + 5.0


func _draw_row(r: QuestRow, rect: Rect2) -> void:
	var slide := (1.0 - HudTheme.out_cubic(r.appear)) * 26.0
	var a := clampf(r.appear * 1.4, 0.0, 1.0)
	if r.state != 0:
		a *= clampf(1.0 - (_time - r.end_t - HOLD_AFTER_END + 1.0), 0.0, 1.0)

	var title_col := HudTheme.QUEST
	if r.state == 1:
		title_col = HudTheme.GOOD
	elif r.state == 2:
		title_col = HudTheme.BAD
	title_col = title_col.lerp(Color.WHITE, r.flash * 0.6)

	var p := rect.position + Vector2(slide, 0.0)
	HudTheme.text(self, p, r.title, 12, HudTheme.with_alpha(title_col, a),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 1)
	if r.state == 1:
		var w := HudTheme.text_size(r.title, 12).x
		draw_line(p + Vector2(0, 8), p + Vector2(w, 8), HudTheme.with_alpha(title_col, a * 0.8), 1.0)

	var y := p.y + TITLE_H
	for o: Dictionary in r.objectives:
		var goal := int(o["goal"])
		var prog := int(o["progress"])
		var done := prog >= goal
		var col := HudTheme.GOOD if done else HudTheme.TEXT_DIM
		col = col.lerp(Color.WHITE, float(o["flash"]) * 0.7)
		# Bullet: filled when complete.
		var bc := Vector2(p.x + 4.0, y + 6.0)
		if done:
			draw_line(bc + Vector2(-3, 0), bc + Vector2(-1, 2), HudTheme.with_alpha(col, a), 1.6)
			draw_line(bc + Vector2(-1, 2), bc + Vector2(3, -3), HudTheme.with_alpha(col, a), 1.6)
		else:
			draw_rect(Rect2(bc - Vector2(2.5, 2.5), Vector2(5, 5)),
				HudTheme.with_alpha(col, a * 0.9), false, 1.0)
		var txt := String(o["text"])
		if goal > 1:
			txt += "   %d/%d" % [prog, goal]
		HudTheme.text(self, Vector2(p.x + 12.0, y), txt, 11, HudTheme.with_alpha(col, a))
		if goal > 1 and not done:
			var bar := Rect2(Vector2(p.x + 12.0, y + 12.0), Vector2(rect.size.x - 24.0, 2.0))
			draw_rect(bar, HudTheme.with_alpha(Color(0.15, 0.16, 0.22), a), true)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(o["shown"]), bar.size.y)),
				HudTheme.with_alpha(HudTheme.QUEST, a), true)
		y += ROW_H
