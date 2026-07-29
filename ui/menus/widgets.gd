## Small factory functions for the controls every Planeshift menu is built from.
##
## Nothing here holds state — each function returns a fresh, fully configured
## node styled by [MenuTheme]. Panels stay readable because they describe
## *layout*, not the twelve property assignments each widget needs.
class_name MenuWidgets
extends RefCounted


# ------------------------------------------------------------------ containers
static func col(sep: int = MenuTheme.GAP) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", sep)
	return v


static func row(sep: int = MenuTheme.GAP) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", sep)
	return h


static func grid(columns: int, sep: int = 4) -> GridContainer:
	var g := GridContainer.new()
	g.columns = maxi(1, columns)
	g.add_theme_constant_override(&"h_separation", sep)
	g.add_theme_constant_override(&"v_separation", sep)
	return g


## Wrap `child` in a [MarginContainer] with uniform padding.
static func pad(child: Control, amount: int = MenuTheme.PAD) -> MarginContainer:
	var m := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		m.add_theme_constant_override(side, amount)
	m.add_child(child)
	return m


## Card surface (raised panel) around `child`.
static func card(child: Control) -> PanelContainer:
	return _sleeve(child, &"CardPanel")


## Recessed well around `child` — use for lists, grids and text bodies.
static func well(child: Control) -> PanelContainer:
	return _sleeve(child, &"InsetPanel")


## Wrapping a control in a PanelContainer otherwise loses its size flags, and
## the wrapper collapses to its minimum size inside a box container. Inheriting
## the child's flags keeps "scroll fills the rest of the window" working.
static func _sleeve(child: Control, variation: StringName) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.size_flags_horizontal = child.size_flags_horizontal
	p.size_flags_vertical = child.size_flags_vertical
	p.add_child(child)
	return p


static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal \
		else ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Empty a container *now*. `queue_free()` alone defers the removal by a frame,
## during which the old and new contents overlap — very visible when a panel
## re-fills a list on every click.
static func clear(container: Node) -> void:
	if container == null:
		return
	for c: Node in container.get_children():
		container.remove_child(c)
		c.queue_free()


static func spacer(minimum: int = 0, expand: bool = true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(minimum, minimum)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func rule() -> HSeparator:
	return HSeparator.new()


# ---------------------------------------------------------------------- labels
static func label(text: String, variation: StringName = &"", align: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if align >= 0:
		l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String) -> Label:
	return label(text, &"TitleLabel")


static func heading(text: String) -> Label:
	return label(text, &"HeadLabel")


static func dim(text: String) -> Label:
	return label(text, &"SmallLabel")


## Multi-line body copy that wraps to the container width.
static func paragraph(text: String, variation: StringName = &"") -> Label:
	var l := label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func rich(bbcode: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


# --------------------------------------------------------------------- buttons
static func button(text: String, on_press: Callable = Callable(),
		variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## Full-width entry used on the title screen and the pause menu.
static func menu_entry(text: String, on_press: Callable = Callable()) -> Button:
	var b := button(text, on_press, &"MenuEntryButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(300, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


static func small_button(text: String, on_press: Callable = Callable()) -> Button:
	return button(text, on_press, &"TinyButton")


static func toggle(text: String, value: bool, on_change: Callable = Callable()) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_ALL
	if on_change.is_valid():
		c.toggled.connect(on_change)
	return c


# ------------------------------------------------------------------ option rows
## `label : [control]` row with the label at a fixed width so a column of rows
## lines up. Used all over the options menu.
static func field(text: String, control: Control, label_width: int = 210) -> HBoxContainer:
	var h := row()
	var l := label(text, &"DimLabel")
	l.custom_minimum_size = Vector2(label_width, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


## Slider with a live numeric readout. `on_change` receives the raw float.
static func slider(min_v: float, max_v: float, step: float, value: float,
		on_change: Callable = Callable(), suffix: String = "") -> HBoxContainer:
	var h := row(MenuTheme.GAP)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(160, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var read := label("", &"SmallLabel")
	read.custom_minimum_size = Vector2(58, 0)
	read.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := func(v: float) -> void:
		read.text = ("%d%s" % [roundi(v), suffix]) if step >= 1.0 else ("%.2f%s" % [v, suffix])
	fmt.call(value)
	s.value_changed.connect(func(v: float) -> void:
		fmt.call(v)
		if on_change.is_valid():
			on_change.call(v))
	h.add_child(s)
	h.add_child(read)
	return h


static func options(items: PackedStringArray, selected: int,
		on_change: Callable = Callable()) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(items[i], i)
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	o.focus_mode = Control.FOCUS_ALL
	if on_change.is_valid():
		o.item_selected.connect(on_change)
	return o


static func line_edit(text: String, placeholder: String = "",
		on_submit: Callable = Callable()) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if on_submit.is_valid():
		e.text_submitted.connect(on_submit)
	return e


# ----------------------------------------------------------------------- misc
## `name .......... value` row, the workhorse of every stats readout.
static func stat_row(name: String, value: String, value_color: Color = MenuTheme.TEXT) -> HBoxContainer:
	var h := row(4)
	h.add_child(label(name, &"SmallLabel"))
	h.add_child(spacer())
	var v := label(value, &"SmallLabel")
	v.add_theme_color_override(&"font_color", value_color)
	h.add_child(v)
	return h


## Thin labelled bar. Returns the container; the bar is its second child.
static func meter(value: float, maximum: float, tint: Color, height: int = 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = maxf(0.0001, maximum)
	p.value = clampf(value, 0.0, maximum)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.add_theme_stylebox_override(&"fill", MenuTheme.flat(tint, MenuTheme.RADIUS_SM, 0))
	return p


## Coloured pill, e.g. "Rare", "Threat 3", "Hardcore".
static func badge(text: String, tint: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := MenuTheme.flat(Color(tint.r, tint.g, tint.b, 0.18), 999, 8)
	sb.set_border_width_all(1)
	sb.border_color = Color(tint.r, tint.g, tint.b, 0.55)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override(&"panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, &"TinyLabel")
	l.add_theme_color_override(&"font_color", tint)
	p.add_child(l)
	return p


## Empty-state message for a list that has nothing in it yet.
static func placeholder(text: String) -> Control:
	var v := col()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var l := paragraph(text, &"TinyLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


## Tab strip built from plain buttons so tabs can carry counts and colours that
## [TabBar] cannot express. `on_change` receives the tab index.
static func tab_strip(names: PackedStringArray, on_change: Callable) -> HBoxContainer:
	var h := row(2)
	var buttons: Array[Button] = []
	for i in names.size():
		var b := button(names[i], Callable(), &"GhostButton")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.append(b)
		h.add_child(b)
	for i in buttons.size():
		var idx := i
		buttons[i].pressed.connect(func() -> void:
			for j in buttons.size():
				buttons[j].button_pressed = (j == idx)
				buttons[j].add_theme_color_override(&"font_color",
					MenuTheme.ACCENT if j == idx else MenuTheme.TEXT_DIM)
			on_change.call(idx))
	if not buttons.is_empty():
		buttons[0].button_pressed = true
		buttons[0].add_theme_color_override(&"font_color", MenuTheme.ACCENT)
	h.set_meta(&"buttons", buttons)
	return h


## Select a tab on a strip built by [method tab_strip], firing its callback.
static func select_tab(strip: HBoxContainer, index: int) -> void:
	var buttons: Array = strip.get_meta(&"buttons", [])
	if index >= 0 and index < buttons.size():
		(buttons[index] as Button).emit_signal(&"pressed")


## Attach a hover tooltip driven by the global tooltip service. Works for any
## control, and is safe if `UI` has not finished booting.
static func tip(c: Control, text: String) -> void:
	if text == "":
		return
	c.mouse_entered.connect(func() -> void:
		Events.tooltip_requested.emit(text, c.get_global_rect().position + Vector2(0, c.size.y + 6)))
	c.mouse_exited.connect(func() -> void:
		Events.tooltip_requested.emit("", Vector2.ZERO))


## Make `node` and everything under it transparent to the mouse. Call it *after*
## the subtree is fully built — later children are not covered.
static func ignore_mouse(node: Node) -> void:
	var c := node as Control
	if c != null:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		ignore_mouse(child)


## Lay rich content over a plain [Button] without stealing its clicks. Godot's
## containers default to MOUSE_FILTER_STOP, so a naive HBox inside a Button
## silently swallows every press — this is the fix, applied consistently.
static func button_overlay(b: Button, content: Control, margin: Vector4 = Vector4(8, 4, 8, 4)) -> void:
	b.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = margin.x
	content.offset_top = margin.y
	content.offset_right = -margin.z
	content.offset_bottom = -margin.w
	ignore_mouse(content)


## Focus the first control in `parent` that can take focus, depth first.
## Returns true when something was focused.
static func focus_first(parent: Node) -> bool:
	for child: Node in parent.get_children():
		var c := child as Control
		# `is_inside_tree` matters: panels build their widget trees before the
		# panel itself is attached, and grab_focus on a detached Control errors.
		if c != null and c.visible and c.focus_mode == Control.FOCUS_ALL \
				and c.is_inside_tree() \
				and not (c is BaseButton and (c as BaseButton).disabled):
			c.grab_focus()
			return true
		if child.get_child_count() > 0 and focus_first(child):
			return true
	return false


## Human-friendly name for the first event bound to `action`.
static func action_key_name(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "-"
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code)) \
				if k.physical_keycode != 0 else OS.get_keycode_string(code)
		if e is InputEventMouseButton:
			match (e as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "Mouse 1"
				MOUSE_BUTTON_RIGHT: return "Mouse 2"
				MOUSE_BUTTON_MIDDLE: return "Mouse 3"
				_: return "Mouse %d" % (e as InputEventMouseButton).button_index
		if e is InputEventJoypadButton:
			return "Pad %d" % (e as InputEventJoypadButton).button_index
	return "-"


## Compact number formatting for counts and currency: 1234 -> "1.2k".
static func short_number(n: float) -> String:
	var a := absf(n)
	if a >= 1_000_000.0:
		return "%.1fM" % (n / 1_000_000.0)
	if a >= 10_000.0:
		return "%.0fk" % (n / 1000.0)
	if a >= 1000.0:
		return "%.1fk" % (n / 1000.0)
	return str(roundi(n))


## "3h 12m" style playtime.
static func duration_string(seconds: float) -> String:
	var s := int(maxf(0.0, seconds))
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, s % 60]
