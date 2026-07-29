## Root of the in-game HUD. Instanced by `main.tscn` as the `HUD` CanvasLayer.
##
## This node owns nothing but layout: every widget is an independent `Control`
## that drives itself from the `Events` bus, so a widget whose backing module
## has not landed yet simply shows nothing instead of breaking the HUD.
##
## Layout is recomputed whenever the viewport resizes. Anchors in `hud.tscn`
## give a sane 1280x720 default; `_relayout()` then stacks the right-hand column
## (compass / minimap / quest tracker) and drops widgets that no longer fit, so
## the HUD survives a 640x360 window and a 4K one alike.
class_name HudRoot
extends CanvasLayer

const MARGIN := 14.0
const GAP := 10.0

const COMPASS_SIZE := Vector2(224.0, 246.0)
const MINIMAP_SIZE := Vector2(196.0, 200.0)
const QUEST_SIZE := Vector2(268.0, 210.0)
const HOTBAR_SIZE := Vector2(556.0, 84.0)
const EFFECTS_SIZE := Vector2(420.0, 52.0)
const DEBUG_SIZE := Vector2(346.0, 330.0)

@onready var root: Control = get_node_or_null(^"Root")

var status_bars: Control = null
var hotbar: Control = null
var plane_compass: Control = null
var crosshair: Control = null
var damage_numbers: Control = null
var notifications: Control = null
var minimap: Control = null
var quest_tracker: Control = null
var status_effects: Control = null
var debug_overlay: Control = null

## Widgets that fade out while a modal menu is up. Toasts and the debug overlay
## deliberately stay readable over menus.
var _dimmable: Array[Control] = []
var _dim := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if root == null:
		# Defensive: allow the HUD to work even if the scene was edited down.
		root = Control.new()
		root.name = "Root"
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

	status_bars = _grab(^"StatusBars")
	minimap = _grab(^"Minimap")
	plane_compass = _grab(^"PlaneCompass")
	quest_tracker = _grab(^"QuestTracker")
	status_effects = _grab(^"StatusEffects")
	hotbar = _grab(^"Hotbar")
	crosshair = _grab(^"Crosshair")
	damage_numbers = _grab(^"DamageNumbers")
	notifications = _grab(^"Notifications")
	debug_overlay = _grab(^"DebugOverlay")

	for w: Control in [status_bars, minimap, plane_compass, quest_tracker,
			status_effects, hotbar, crosshair]:
		if w != null:
			_dimmable.append(w)

	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_relayout)
	_relayout()


func _grab(path: NodePath) -> Control:
	var n: Node = root.get_node_or_null(path)
	var c := n as Control
	if c != null:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _process(delta: float) -> void:
	# Menus take the foreground; the gameplay HUD steps back but never vanishes
	# so the player keeps their health and hotbar context while trading/crafting.
	var want := 0.32 if _menu_open() else 1.0
	if absf(want - _dim) > 0.001:
		_dim = move_toward(_dim, want, delta * 4.0)
		for w: Control in _dimmable:
			if is_instance_valid(w):
				w.modulate.a = _dim


func _menu_open() -> bool:
	if UI == null or not UI.has_method(&"captures_input"):
		return false
	return UI.captures_input()


# --------------------------------------------------------------------- layout
## Absolute-position a widget. Anchors are pinned to the top-left so the rect we
## compute here is exactly what the widget gets; we re-run on every resize.
func _place(w: Control, r: Rect2) -> void:
	if w == null:
		return
	w.anchor_left = 0.0
	w.anchor_top = 0.0
	w.anchor_right = 0.0
	w.anchor_bottom = 0.0
	w.offset_left = r.position.x
	w.offset_top = r.position.y
	w.offset_right = r.position.x + r.size.x
	w.offset_bottom = r.position.y + r.size.y


func _place_full(w: Control) -> void:
	if w == null:
		return
	w.anchor_left = 0.0
	w.anchor_top = 0.0
	w.anchor_right = 1.0
	w.anchor_bottom = 1.0
	w.offset_left = 0.0
	w.offset_top = 0.0
	w.offset_right = 0.0
	w.offset_bottom = 0.0


func _relayout() -> void:
	var vp := get_viewport()
	if vp == null or root == null:
		return
	var vs := Vector2(vp.get_visible_rect().size)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Overlays that own the whole screen and position themselves internally.
	_place_full(status_bars)
	_place_full(crosshair)
	_place_full(damage_numbers)
	_place_full(notifications)

	# Bottom-centre hotbar, shrunk on narrow windows.
	var hb := HOTBAR_SIZE
	if hb.x > vs.x - MARGIN * 2.0:
		hb.x = maxf(220.0, vs.x - MARGIN * 2.0)
	_place(hotbar, Rect2(Vector2((vs.x - hb.x) * 0.5, vs.y - hb.y - MARGIN * 0.5), hb))

	# Right-hand column: compass first — it is the widget that teaches the game.
	var col_bottom := vs.y - hb.y - MARGIN * 2.0
	var y := MARGIN
	var compass := COMPASS_SIZE
	if compass.x > vs.x * 0.42:
		compass *= clampf(vs.x * 0.42 / compass.x, 0.62, 1.0)
	_place(plane_compass, Rect2(Vector2(vs.x - compass.x - MARGIN, y), compass))
	y += compass.y + GAP

	if minimap != null:
		minimap.visible = y + MINIMAP_SIZE.y <= col_bottom
		if minimap.visible:
			_place(minimap, Rect2(Vector2(vs.x - MINIMAP_SIZE.x - MARGIN, y), MINIMAP_SIZE))
			y += MINIMAP_SIZE.y + GAP

	if quest_tracker != null:
		var qh := minf(QUEST_SIZE.y, col_bottom - y)
		if qh >= 70.0:
			_place(quest_tracker,
				Rect2(Vector2(vs.x - QUEST_SIZE.x - MARGIN, y), Vector2(QUEST_SIZE.x, qh)))
		else:
			quest_tracker.visible = false

	# Left column below the status bars.
	_place(status_effects, Rect2(Vector2(MARGIN, 128.0),
		Vector2(minf(EFFECTS_SIZE.x, vs.x * 0.5), EFFECTS_SIZE.y)))
	_place(debug_overlay, Rect2(Vector2(MARGIN, 190.0),
		Vector2(DEBUG_SIZE.x, minf(DEBUG_SIZE.y, vs.y - 220.0))))


# ---------------------------------------------------------------- public API
## Hide/show the whole overlay (cutscenes, screenshots).
func set_hud_visible(v: bool) -> void:
	if root != null:
		root.visible = v
