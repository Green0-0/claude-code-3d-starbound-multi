## NPC conversation box: procedural portrait, typewriter text, branching
## choices, and the quest offer / accept / turn-in verbs.
##
## Opened by [UI] from `Events.dialogue_started(npc, tree_id)`. The tree itself
## belongs to the quests agent; this panel asks, in order:
##   `npc.dialogue_tree(tree_id)` -> `Quests.dialogue_tree(tree_id)` ->
##   `Quests.get_dialogue(tree_id)` -> a short built-in fallback conversation.
##
## Normalised tree shape:
## [codeblock]
## {
##   "name": "Nel",  "start": "root",
##   "nodes": {
##     "root": {
##       "text": "...",
##       "choices": [
##         {"text": "Tell me more", "goto": "more"},
##         {"text": "I'll do it",   "action": "accept",  "quest": "q_ore"},
##         {"text": "Here you go",  "action": "turn_in", "quest": "q_ore"},
##         {"text": "Goodbye",      "action": "end"},
##       ]}}}
## [/codeblock]
extends MenuPanel

const CHARS_PER_SECOND := 55.0

var _npc: Node = null
var _tree_id: String = ""
var _tree: Dictionary = {}
var _node_id: String = ""
var _speaker: String = "Stranger"

var _text_label: RichTextLabel = null
var _choice_box: VBoxContainer = null
var _portrait: Control = null
var _typed: float = 0.0
var _full_text: String = ""
var _first_open: bool = true


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.12
	placement = "bottom"
	anim = "slide_up"
	esc_closes = true


## Re-opening while already on screen (a second NPC interrupts) rebuilds the
## box around the new tree. The first call is a no-op because `_build()` has
## just done exactly that.
func _on_open(context: Dictionary) -> void:
	if _first_open:
		_first_open = false
		return
	ctx = context
	rebuild()


func _resolve_from_ctx() -> void:
	_npc = ctx.get("npc") as Node
	_tree_id = String(ctx.get("tree_id", ""))
	_tree = _resolve_tree()
	_speaker = String(_tree.get("name", _npc_name()))


func _build() -> void:
	_resolve_from_ctx()
	var root := bare(Vector2(880, 0))
	var card := PanelContainer.new()
	card.theme_type_variation = &"WindowPanel"
	card.custom_minimum_size = Vector2(880, 190)
	root.add_child(card)

	var row := MenuWidgets.row(MenuTheme.GAP + 4)
	card.add_child(row)

	_portrait = _make_portrait()
	row.add_child(_portrait)

	var right := MenuWidgets.col(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	var name_row := MenuWidgets.row(6)
	var name_label := MenuWidgets.label(_speaker, &"HeadLabel")
	name_label.name = "SpeakerName"
	name_row.add_child(name_label)
	name_row.add_child(MenuWidgets.spacer())
	name_row.add_child(MenuWidgets.small_button("End", _end))
	right.add_child(name_row)
	right.add_child(MenuWidgets.rule())

	_text_label = MenuWidgets.rich("")
	_text_label.custom_minimum_size = Vector2(0, 62)
	right.add_child(_text_label)

	_choice_box = MenuWidgets.col(3)
	right.add_child(_choice_box)

	_goto(String(_tree.get("start", "root")))


func _on_close() -> void:
	Events.dialogue_ended.emit()


# ------------------------------------------------------------------ the tree
func _resolve_tree() -> Dictionary:
	for provider: Object in [_npc, Quests]:
		if provider == null:
			continue
		for getter: StringName in [&"dialogue_tree", &"get_dialogue", &"dialogue"]:
			if provider.has_method(getter):
				var t: Variant = provider.call(getter, _tree_id)
				if t is Dictionary and not (t as Dictionary).is_empty():
					return t as Dictionary
	return _fallback_tree()


## Used until the quests agent lands. Deliberately short, and it teaches the
## flip mechanic rather than pretending to be real content.
func _fallback_tree() -> Dictionary:
	return {
		"name": _npc_name(),
		"start": "root",
		"nodes": {
			"root": {
				"text": "You came through the [color=#ffb347]east face[/color]? "
					+ "Most people never think to turn the world.",
				"choices": [
					{"text": "What is there to find?", "goto": "find"},
					{"text": "Turn the world?", "goto": "explain"},
					{"text": "Just passing through.", "action": "end"},
				]},
			"explain": {
				"text": "Four planes, same rock. Press [color=#48c9e8]Q[/color] or "
					+ "[color=#48c9e8]E[/color] and the walls become corridors. "
					+ "[color=#48c9e8]PgUp[/color] and [color=#48c9e8]PgDn[/color] "
					+ "step you deeper in.",
				"choices": [
					{"text": "Useful. Thanks.", "goto": "root"},
					{"text": "Goodbye.", "action": "end"},
				]},
			"find": {
				"text": "Ore, mostly. And things that were sealed away by people "
					+ "who only ever looked at one side of them.",
				"choices": [
					{"text": "Back up a moment.", "goto": "root"},
					{"text": "Goodbye.", "action": "end"},
				]},
		},
	}


func _npc_name() -> String:
	if _npc != null:
		for getter: StringName in [&"display_name", &"npc_name"]:
			if _npc.has_method(getter):
				return String(_npc.call(getter))
		var n: Variant = _npc.get(&"display_name")
		if n != null and String(n) != "":
			return String(n)
		return String(_npc.name)
	return "Stranger"


func _goto(id: String) -> void:
	var nodes: Dictionary = _tree.get("nodes", {})
	if not nodes.has(id):
		_end()
		return
	_node_id = id
	var node: Dictionary = nodes[id]
	_full_text = String(node.get("text", ""))
	_typed = 0.0
	if _text_label != null:
		_text_label.text = _full_text
		_text_label.visible_characters = 0
	_build_choices(node)
	var quest_id := String(node.get("quest", ""))
	if node.get("action", "") == "offer" and quest_id != "":
		_offer_quest(quest_id)


func _build_choices(node: Dictionary) -> void:
	if _choice_box == null:
		return
	MenuWidgets.clear(_choice_box)
	var choices: Variant = node.get("choices", [])
	if not (choices is Array) or (choices as Array).is_empty():
		_choice_box.add_child(MenuWidgets.button("Continue", _end, &"ListRowButton"))
		return
	for entry: Variant in (choices as Array):
		if not (entry is Dictionary):
			continue
		var choice: Dictionary = entry
		if not _choice_available(choice):
			continue
		var b := MenuWidgets.button("› " + String(choice.get("text", "...")),
			func() -> void: _pick(choice), &"ListRowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var action := String(choice.get("action", ""))
		if action == "accept":
			b.add_theme_color_override(&"font_color", MenuTheme.ACCENT)
		elif action == "turn_in":
			b.add_theme_color_override(&"font_color", MenuTheme.GOOD)
		_choice_box.add_child(b)


## Hide turn-in options for quests that are not actually complete.
func _choice_available(choice: Dictionary) -> bool:
	var need := String(choice.get("requires", ""))
	if need == "":
		return true
	if Quests != null and Quests.has_method(&"is_active"):
		return bool(Quests.call(&"is_active", need))
	return true


func _pick(choice: Dictionary) -> void:
	if _text_label != null and _text_label.visible_characters >= 0 \
			and _typed < float(_text_label.get_total_character_count()):
		# First click finishes the line rather than choosing blind.
		_typed = float(_text_label.get_total_character_count())
		_text_label.visible_characters = -1
		return
	var quest_id := String(choice.get("quest", ""))
	match String(choice.get("action", "")):
		"accept":
			_accept_quest(quest_id)
		"turn_in":
			_turn_in_quest(quest_id)
		"offer":
			_offer_quest(quest_id)
		"end":
			_end()
			return
	var goto := String(choice.get("goto", ""))
	if goto != "":
		_goto(goto)
	elif String(choice.get("action", "")) != "":
		_end()


# ------------------------------------------------------------------- quests
func _offer_quest(quest_id: String) -> void:
	if quest_id == "":
		return
	if Quests != null and Quests.has_method(&"offer"):
		Quests.call(&"offer", quest_id, _npc)
	Events.quest_offered.emit(quest_id, _npc)


func _accept_quest(quest_id: String) -> void:
	if quest_id == "":
		return
	var started := false
	if Quests != null and Quests.has_method(&"start"):
		started = bool(Quests.call(&"start", quest_id))
	Events.quest_started.emit(quest_id)
	Events.toast("Quest accepted: %s" % quest_id.capitalize().replace("_", " "), "quest")
	if not started:
		push_warning("[dialogue] Quests.start('%s') refused or is a stub." % quest_id)


func _turn_in_quest(quest_id: String) -> void:
	if quest_id == "":
		return
	if Quests != null and Quests.has_method(&"complete"):
		Quests.call(&"complete", quest_id)
	Events.quest_completed.emit(quest_id)
	Events.toast("Quest complete: %s" % quest_id.capitalize().replace("_", " "), "quest")


func _end() -> void:
	close_self()


# --------------------------------------------------------------- typewriter
func _process(delta: float) -> void:
	if _text_label == null or _full_text == "":
		return
	var total := float(_text_label.get_total_character_count())
	if _typed >= total:
		if _text_label.visible_characters != -1:
			_text_label.visible_characters = -1
		return
	_typed = minf(total, _typed + delta * CHARS_PER_SECOND)
	_text_label.visible_characters = int(_typed)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _text_label != null and _text_label.visible_characters != -1:
			_typed = float(_text_label.get_total_character_count())
			_text_label.visible_characters = -1
			accept_event()


# ------------------------------------------------------------------ portrait
## Deterministic pixel portrait derived from the speaker's name. No art assets,
## but two different NPCs always look different, and the same NPC always looks
## the same.
func _make_portrait() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"InsetPanel"
	p.custom_minimum_size = Vector2(132, 132)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	p.add_child(holder)

	var rng := RandomNumberGenerator.new()
	rng.seed = _speaker.hash()
	var skin := Color.from_hsv(rng.randf_range(0.03, 0.12), rng.randf_range(0.25, 0.5),
		rng.randf_range(0.55, 0.9))
	var hair := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.25, 0.7))
	var cloth := Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.7), rng.randf_range(0.3, 0.6))

	var pieces: Array = [
		[Rect2(0, 92, 120, 30), cloth],                  # shoulders
		[Rect2(34, 26, 52, 62), skin],                   # face
		[Rect2(30, 16, 60, 18), hair],                   # hair
		[Rect2(30, 16, 10, 44), hair],                   # side hair
		[Rect2(80, 16, 10, 44), hair],
		[Rect2(46, 50, 8, 8), Color(0.1, 0.1, 0.12)],    # eyes
		[Rect2(66, 50, 8, 8), Color(0.1, 0.1, 0.12)],
		[Rect2(52, 70, 16, 4), skin.darkened(0.35)],     # mouth
	]
	if rng.randf() < 0.4:
		pieces.append([Rect2(28, 10, 64, 10), cloth.lightened(0.2)])  # hat brim
	for piece: Array in pieces:
		var box: Rect2 = piece[0]
		var tint: Color = piece[1]
		var r := ColorRect.new()
		r.color = tint
		r.position = box.position
		r.size = box.size
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(r)
	return p
