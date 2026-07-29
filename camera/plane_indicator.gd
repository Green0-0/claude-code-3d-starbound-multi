## A small four-plane compass rose: which of North/West/South/East you are
## looking along, and which one Q and E will take you to.
##
## The rose is camera-relative — the plane you are in is always at the top — and
## it is driven by `View.current_yaw()`, so it rotates in exact lockstep with
## the camera during a flip instead of snapping at the end. That coupling is the
## point: it teaches the player that Q/E rotate the *world*, not the character.
##
## [b]Ownership note.[/b] `ui/hud/` owns 2D HUD widgets, so this one is OFF by
## default and never touches the HUD tree — it lives on its own CanvasLayer
## under the camera rig. The HUD agent enables it with:
## [codeblock]
## CamSettings.plane_indicator_enabled = true
## [/codeblock]
## and can reposition it via `Game.camera_rig.plane_indicator` (`corner`,
## `margin`, `radius`). Leaving it off costs one boolean test per frame.
class_name CamPlaneIndicator
extends CanvasLayer

## Which screen corner to hug: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
@export_enum("Top Left", "Top Right", "Bottom Left", "Bottom Right") var corner := 1
## Distance from that corner to the centre of the rose, in pixels.
@export var margin := Vector2(74.0, 74.0)
## Radius of the rose in pixels.
@export var radius := 30.0
@export var ring_color := Color(0.72, 0.80, 0.95, 0.35)
@export var idle_color := Color(0.72, 0.80, 0.95, 0.55)
@export var active_color := Color(1.0, 0.92, 0.55, 1.0)
@export var key_color := Color(0.62, 0.86, 1.0, 0.9)
@export var label_size := 12

var _rose: Control = null
var _last_yaw := INF


func _ready() -> void:
	process_priority = 11
	layer = 2
	follow_viewport_enabled = false
	_rose = Control.new()
	_rose.name = "Rose"
	_rose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rose.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rose.anchor_right = 1.0
	_rose.anchor_bottom = 1.0
	_rose.offset_right = 0.0
	_rose.offset_bottom = 0.0
	_rose.draw.connect(_draw_rose)
	add_child(_rose)
	_rose.visible = false


func _process(_delta: float) -> void:
	if _rose == null:
		return
	var on := CamSettings.plane_indicator_enabled
	if on != _rose.visible:
		_rose.visible = on
	if not on:
		return
	var yaw := View.current_yaw()
	if is_equal_approx(yaw, _last_yaw):
		return
	_last_yaw = yaw
	_rose.queue_redraw()


func _centre() -> Vector2:
	var s := _rose.size
	match corner:
		0: return Vector2(margin.x, margin.y)
		2: return Vector2(margin.x, s.y - margin.y)
		3: return Vector2(s.x - margin.x, s.y - margin.y)
		_: return Vector2(s.x - margin.x, margin.y)


func _draw_rose() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var c := _centre()
	var yaw := View.current_yaw()

	# Ring + the fixed "you are looking this way" caret at the top.
	_rose.draw_arc(c, radius, 0.0, TAU, 48, ring_color, 1.5, true)
	var caret := PackedVector2Array([
		c + Vector2(0.0, -radius - 9.0),
		c + Vector2(-5.0, -radius - 1.0),
		c + Vector2(5.0, -radius - 1.0)])
	_rose.draw_colored_polygon(caret, active_color)

	var view := View.view
	var cw := wrapi(view + 1, 0, Const.VIEW_COUNT)   # E / flip_right
	var ccw := wrapi(view - 1, 0, Const.VIEW_COUNT)  # Q / flip_left

	for v in Const.VIEW_COUNT:
		# Rotate the whole rose so the plane we are currently in sits at the top.
		# Using the interpolated yaw makes the rose sweep with the camera.
		var a := View.yaw_of(v) - yaw - PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var p := c + dir * radius
		var is_current := v == view and not View.flipping
		var col := active_color if is_current else idle_color
		if is_current:
			_rose.draw_circle(p, 4.5, col)
		else:
			_rose.draw_circle(p, 2.5, col)

		var vname: String = str(Const.VIEW_NAMES[v]).substr(0, 1)
		var label_pos := c + dir * (radius + 13.0) + Vector2(-8.0, 4.0)
		_rose.draw_string(font, label_pos, vname, HORIZONTAL_ALIGNMENT_CENTER, 16.0,
			label_size, col)

		# The two flip destinations get their key printed just outside them.
		var key := ""
		if v == ccw:
			key = "Q"
		elif v == cw:
			key = "E"
		if key != "":
			var key_pos := c + dir * (radius + 26.0) + Vector2(-8.0, 4.0)
			_rose.draw_string(font, key_pos, key, HORIZONTAL_ALIGNMENT_CENTER, 16.0,
				label_size, key_color)

	# Plane name under the rose.
	var title := str(Const.VIEW_NAMES[view])
	_rose.draw_string(font, c + Vector2(-40.0, radius + 42.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, 80.0, label_size, active_color)


## Force a redraw (call after changing `corner`, `margin` or `radius`).
func refresh() -> void:
	_last_yaw = INF
	if _rose != null:
		_rose.queue_redraw()
