## Base class for every window in Planeshift.
##
## A panel is a full-screen [Control] that owns an optional dimming scrim and a
## single "window" node. [UI] instantiates it, pushes it onto the panel stack,
## and animates it in; the subclass only implements [method _build] plus
## whichever lifecycle hooks it needs.
##
## Subclass contract:
## [codeblock]
## extends MenuPanel
##
## func _configure() -> void:
##     modal = true          # blocks gameplay input while open
##     pauses = false        # does not stop the world
##     dim = 0.35            # scrim alpha behind the window
##     placement = "center"
##
## func _build() -> void:
##     var body := frame("Title", Vector2(640, 460))
##     body.add_child(MenuWidgets.label("hello"))
##
## func _on_open(ctx: Dictionary) -> void: pass   # also called on re-open
## func _on_close() -> void: pass
## [/codeblock]
class_name MenuPanel
extends Control

## Registry id this panel was opened under, e.g. "inventory".
var panel_id: String = ""
## Arbitrary open-time arguments supplied by the caller of `UI.open()`.
var ctx: Dictionary = {}

# --- behaviour flags, read by UI immediately after construction --------------
## Modal panels stop mouse events reaching anything underneath them.
var modal: bool = true
## When true, `UI.captures_input()` reports true while this panel is open, and
## the player script / main.gd stop reading gameplay input.
var captures: bool = true
## When true the whole SceneTree is paused while this panel is open.
var pauses: bool = false
## Alpha of the full-screen scrim. 0 disables the scrim entirely.
var dim: float = 0.0
## Where the window sits: "center", "fill", "bottom", "top", "left", "right".
var placement: String = "center"
## Entry/exit animation: "scale", "fade", "slide_up", "slide_down", "none".
var anim: String = "scale"
## ESC (or `ui_cancel`) pops this panel off the stack.
var esc_closes: bool = true
## Clicking the scrim closes the panel.
var click_outside_closes: bool = false
## Opening this panel closes any other open panel sharing the same group.
var group: String = ""

var _scrim: ColorRect = null
var _window: Control = null
var _anim_target: Control = null
var _tween: Tween = null
var _built: bool = false

signal closed(id: String)


func _init() -> void:
	_configure()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
	MenuTheme.apply(self)
	if dim > 0.0:
		_scrim = ColorRect.new()
		_scrim.color = Color(MenuTheme.BG_DEEP.r, MenuTheme.BG_DEEP.g, MenuTheme.BG_DEEP.b, dim)
		_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scrim.mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
		_scrim.gui_input.connect(_on_scrim_input)
		add_child(_scrim)
	_build()
	_built = true
	if _anim_target == null:
		_anim_target = _window if _window != null else self
	_on_open(ctx)
	call_deferred(&"_focus_default")


# ------------------------------------------------------------------- overrides
## Set the behaviour flags. Runs in `_init()`, before the node enters the tree.
func _configure() -> void:
	pass


## Construct the panel contents. Runs once, in `_ready()`.
func _build() -> void:
	pass


## Called after `_build()` and again every time `UI.open()` targets an already
## open panel, so a panel can react to new context without being rebuilt.
func _on_open(_context: Dictionary) -> void:
	pass


## Called just before the panel leaves the stack.
func _on_close() -> void:
	pass


## Which control should take keyboard/gamepad focus when the panel opens.
## Return null to fall back to "first focusable child".
func _default_focus() -> Control:
	return null


# ---------------------------------------------------------------------- chrome
## Build the standard window: title bar, close button, separator, content area.
## Returns the [VBoxContainer] subclasses should fill.
func frame(title_text: String, min_size: Vector2 = Vector2(620, 440),
		show_close: bool = true) -> VBoxContainer:
	var holder := _make_holder()
	add_child(_holder_root(holder))

	var win := PanelContainer.new()
	win.theme_type_variation = &"WindowPanel"
	win.custom_minimum_size = min_size
	if placement == "fill":
		win.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		win.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(win)
	_window = win
	_anim_target = win

	var outer := MenuWidgets.col(MenuTheme.PAD_SM)
	win.add_child(outer)

	if title_text != "":
		var head := MenuWidgets.row()
		var t := MenuWidgets.label(title_text.to_upper(), &"HeadLabel")
		t.add_theme_constant_override(&"outline_size", 0)
		head.add_child(t)
		head.add_child(MenuWidgets.spacer())
		if show_close:
			var x := MenuWidgets.button("×", close_self, &"CloseButton")
			x.custom_minimum_size = Vector2(30, 26)
			x.focus_mode = Control.FOCUS_NONE
			head.add_child(x)
		outer.add_child(head)
		outer.add_child(MenuWidgets.rule())

	var body := MenuWidgets.col()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	return body


## A window with no chrome at all — for the title screen, the death screen and
## the dialogue box, which draw their own presentation.
func bare(min_size: Vector2 = Vector2.ZERO) -> Control:
	var holder := _make_holder()
	add_child(_holder_root(holder))
	var c := MenuWidgets.col()
	c.custom_minimum_size = min_size
	if placement == "fill":
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(c)
	_window = c
	_anim_target = c
	return c


## `_make_holder()` may return a container nested inside a wrapper (the
## "top"/"bottom" placements centre their content in an inner HBox). Adding the
## returned node directly would fail with "already has a parent" and orphan the
## wrapper, so always attach the outermost ancestor.
func _holder_root(holder: Node) -> Node:
	var root: Node = holder
	while root.get_parent() != null:
		root = root.get_parent()
	return root


func _make_holder() -> Container:
	match placement:
		"fill":
			var m := MarginContainer.new()
			m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
				m.add_theme_constant_override(side, 28)
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return m
		"bottom", "top":
			var v := VBoxContainer.new()
			v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			v.alignment = BoxContainer.ALIGNMENT_END if placement == "bottom" \
				else BoxContainer.ALIGNMENT_BEGIN
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.offset_bottom = -24.0
			v.offset_top = 24.0
			var h := HBoxContainer.new()
			h.alignment = BoxContainer.ALIGNMENT_CENTER
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(h)
			return h
		"left", "right":
			var hb := HBoxContainer.new()
			hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			hb.alignment = BoxContainer.ALIGNMENT_BEGIN if placement == "left" \
				else BoxContainer.ALIGNMENT_END
			hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return hb
		_:
			var cc := CenterContainer.new()
			cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return cc


## Standard footer: a right-aligned row of buttons, separated from the body.
func footer() -> HBoxContainer:
	var h := MenuWidgets.row()
	h.alignment = BoxContainer.ALIGNMENT_END
	return h


# ------------------------------------------------------------------ animation
func animate_in() -> void:
	if anim == "none":
		return
	var target := _anim_target
	if target == null:
		return
	_kill_tween()
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, ^"modulate:a", 1.0, 0.14)
	match anim:
		"scale":
			# The window has not been laid out yet, so its size is still zero;
			# fix the pivot once the container has sized it.
			call_deferred(&"_centre_pivot", target)
			target.scale = Vector2(0.94, 0.94)
			_tween.tween_property(target, ^"scale", Vector2.ONE, 0.18) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"slide_up":
			target.position.y += 40.0
			_tween.tween_property(target, ^"position:y", target.position.y - 40.0, 0.18) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		"slide_down":
			target.position.y -= 40.0
			_tween.tween_property(target, ^"position:y", target.position.y + 40.0, 0.18) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(false)


## Returns the number of seconds the caller should wait before freeing us.
func animate_out() -> float:
	if anim == "none" or not is_inside_tree():
		return 0.0
	_kill_tween()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, ^"modulate:a", 0.0, 0.11)
	if anim == "scale" and _anim_target != null:
		_tween.tween_property(_anim_target, ^"scale", Vector2(0.96, 0.96), 0.11)
	return 0.12


func _centre_pivot(target: Control) -> void:
	if is_instance_valid(target):
		target.pivot_offset = target.size * 0.5


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


# -------------------------------------------------------------------- helpers
## Close this panel through [UI] so the stack stays consistent. Targets *this*
## node rather than the id, so nested dialogs close themselves.
func close_self() -> void:
	if panel_id != "" and UI.has_method(&"close_node"):
		UI.close_node(self)
	elif panel_id != "":
		UI.close(panel_id)
	else:
		queue_free()


## Global rect of the window chrome. The drag service uses this to tell
## "dropped on the UI" apart from "dropped into the world".
func window_rect() -> Rect2:
	if _window != null and is_instance_valid(_window) and _window.is_inside_tree():
		return _window.get_global_rect()
	if modal:
		return get_global_rect()
	return Rect2()


## Rebuild the panel body in place. Cheap enough for menus; keeps refresh logic
## from having to diff node trees.
func rebuild() -> void:
	if not _built:
		return
	for c: Node in get_children():
		if c != _scrim:
			remove_child(c)
			c.queue_free()
	_window = null
	_anim_target = null
	_build()
	if _anim_target == null:
		_anim_target = _window if _window != null else self
	call_deferred(&"_focus_default")


func _focus_default() -> void:
	if not is_inside_tree():
		return
	var c := _default_focus()
	if c != null and c.is_inside_tree():
		c.grab_focus()
		return
	if _window != null:
		MenuWidgets.focus_first(_window)


func _on_scrim_input(event: InputEvent) -> void:
	if not click_outside_closes:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close_self()


## Called by [UI] as the panel leaves the stack.
func dismiss() -> void:
	_on_close()
	closed.emit(panel_id)
