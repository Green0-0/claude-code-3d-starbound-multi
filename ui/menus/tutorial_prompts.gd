## Contextual first-time hints. The only panel that is neither modal nor
## input-capturing: it sits at the bottom of the screen, watches the event bus,
## and never takes a key away from the game.
##
## Its real job is the two-step teach for the game's signature mechanic —
## flipping (Q / E) and layer shifting (PgUp / PgDn) — which it drives
## interactively: the hint stays up until the player actually performs the
## move, then congratulates them and hands over the next one.
##
## "Seen" flags persist through `UI.set_setting("tutorial/<key>", true)`, so
## hints never reappear on a second run. "Show all hints again" in the options
## menu clears them.
extends MenuPanel

## key -> {title, body, done_when}. Order matters: the first unseen entry whose
## trigger has fired is shown.
const HINTS := {
	"flip": {
		"title": "Turn the world",
		"body": "You are looking at one of four planes. Press [b]Q[/b] or [b]E[/b] "
			+ "to rotate the camera 90°. You do not move — the world re-reveals "
			+ "itself along a new axis.",
	},
	"shift": {
		"title": "Step into the page",
		"body": "Press [b]PgUp[/b] / [b]PgDn[/b] to move one voxel layer deeper "
			+ "or shallower. Unlike flipping, this is real travel — solid rock "
			+ "will stop you.",
	},
	"blocked": {
		"title": "That way is solid",
		"body": "A layer shift can be blocked. Flip to another plane with "
			+ "[b]Q[/b] / [b]E[/b] and look for a gap the old view was hiding.",
	},
	"inventory": {
		"title": "You picked something up",
		"body": "Press [b]I[/b] for your inventory, [b]C[/b] to craft, "
			+ "[b]J[/b] for quests and [b]M[/b] for the star map.",
	},
}

var _active: String = ""
var _card: PanelContainer = null
var _title: Label = null
var _body: RichTextLabel = null
var _progress: Label = null
var _flips_seen: int = 0
var _shifts_seen: int = 0


func _configure() -> void:
	modal = false
	captures = false        ## never steals input — that is the whole point
	pauses = false
	dim = 0.0
	placement = "bottom"
	anim = "slide_up"
	esc_closes = false


func _build() -> void:
	var root := bare(Vector2(560, 0))
	_card = PanelContainer.new()
	_card.theme_type_variation = &"WindowPanel"
	_card.custom_minimum_size = Vector2(560, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	root.add_child(_card)

	var col := MenuWidgets.col(3)
	_card.add_child(col)

	var head := MenuWidgets.row(6)
	var badge := MenuWidgets.badge("hint", MenuTheme.ACCENT)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	_title = MenuWidgets.label("", &"SmallLabel")
	_title.add_theme_color_override(&"font_color", MenuTheme.ACCENT)
	head.add_child(_title)
	head.add_child(MenuWidgets.spacer())
	_progress = MenuWidgets.label("", &"TinyLabel")
	head.add_child(_progress)
	head.add_child(MenuWidgets.small_button("✕", func() -> void: _dismiss(true)))
	col.add_child(head)

	_body = MenuWidgets.rich("")
	col.add_child(_body)

	Events.player_spawned.connect(_on_player_spawned)
	Events.world_ready.connect(func(_p: String) -> void: _queue("flip"))
	Events.view_flip_finished.connect(_on_flipped)
	Events.layer_changed.connect(_on_layer_changed)
	Events.flip_blocked.connect(_on_flip_blocked)
	Events.item_picked_up.connect(func(_id: String, _n: int) -> void: _queue("inventory"))

	if Game != null and Game.player != null:
		_queue("flip")


# ------------------------------------------------------------------ triggers
func _on_player_spawned(_p: Node) -> void:
	_queue("flip")


func _on_flipped(_view: int) -> void:
	if _active != "flip":
		return
	_flips_seen += 1
	_update_progress()
	if _flips_seen >= 2:
		_complete("flip", "Good. Two planes down, two to go.")
		_queue("shift")


func _on_layer_changed(_layer: int, _view: int) -> void:
	if _active != "shift":
		return
	_shifts_seen += 1
	_update_progress()
	if _shifts_seen >= 2:
		_complete("shift", "That is how you get past a wall that has no door.")


func _on_flip_blocked(reason: String) -> void:
	if reason == "occupied":
		_queue("blocked")


# -------------------------------------------------------------------- engine
func _seen(key: String) -> bool:
	return bool(UI.get_setting("tutorial/%s" % key, false))


func _queue(key: String) -> void:
	if not bool(UI.get_setting("gameplay/tutorials", true)):
		return
	if _seen(key) or _active == key or not HINTS.has(key):
		return
	# Never interrupt the flip teach with something less important.
	if _active == "flip" and key != "blocked":
		return
	_show(key)


func _show(key: String) -> void:
	_active = key
	var h: Dictionary = HINTS[key]
	_title.text = String(h["title"])
	_body.text = String(h["body"])
	_update_progress()
	_card.visible = true
	_card.modulate = Color(1, 1, 1, 0)
	var t := create_tween()
	t.tween_property(_card, ^"modulate:a", 1.0, 0.2)
	Events.play_sound.emit(&"ui_hint", Vector3.ZERO)
	# Purely informational hints time out; interactive ones wait for the player.
	if key == "blocked" or key == "inventory":
		get_tree().create_timer(7.0, true, false, true).timeout.connect(func() -> void:
			if _active == key:
				_complete(key, ""))


func _update_progress() -> void:
	match _active:
		"flip": _progress.text = "%d / 2 flips" % _flips_seen
		"shift": _progress.text = "%d / 2 shifts" % _shifts_seen
		_: _progress.text = ""


func _complete(key: String, praise: String) -> void:
	UI.set_setting("tutorial/%s" % key, true)
	if praise != "":
		Events.toast(praise, "hint")
	if _active == key:
		_dismiss(false)


func _dismiss(permanently: bool) -> void:
	if permanently and _active != "":
		UI.set_setting("tutorial/%s" % _active, true)
	_active = ""
	if _card == null:
		return
	var t := create_tween()
	t.tween_property(_card, ^"modulate:a", 0.0, 0.15)
	t.tween_callback(func() -> void:
		if _card != null and _active == "":
			_card.visible = false)


func _on_close() -> void:
	for sig: Signal in [Events.player_spawned, Events.view_flip_finished,
			Events.layer_changed, Events.flip_blocked]:
		for c: Dictionary in sig.get_connections():
			if (c["callable"] as Callable).get_object() == self:
				sig.disconnect(c["callable"])
