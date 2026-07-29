## Settings. Four tabs — Video, Audio, Gameplay, Controls.
##
## Every control writes straight through [method UI.set_setting], which applies
## the change immediately and persists it to `user://settings.cfg`. There is no
## "Apply" button on purpose: players should hear a volume change while they
## drag the slider.
##
## Other modules read the same store, e.g. the camera rig can honour
## `UI.get_setting("gameplay/camera_shake", 1.0)` and
## `UI.get_setting("video/flip_effect", true)`.
extends MenuPanel

const TABS := ["Video", "Audio", "Gameplay", "Controls"]
const VSYNC_MODES := ["Off", "On", "Adaptive", "Mailbox"]
const MSAA_MODES := ["Off", "2x", "4x", "8x"]
const WINDOW_MODES := ["Windowed", "Borderless", "Fullscreen"]

var _tab: int = 0
var _content: VBoxContainer = null
var _listening: StringName = &""
var _listen_button: Button = null


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.55
	placement = "center"
	anim = "scale"


func _build() -> void:
	var body := frame("Options", Vector2(680, 470))

	var strip := MenuWidgets.tab_strip(PackedStringArray(TABS), func(i: int) -> void:
		_tab = i
		_fill())
	body.add_child(strip)
	body.add_child(MenuWidgets.rule())

	_content = MenuWidgets.col()
	var sc := MenuWidgets.scroll(_content)
	sc.custom_minimum_size = Vector2(0, 320)
	body.add_child(sc)

	body.add_child(MenuWidgets.rule())
	var f := footer()
	f.add_child(MenuWidgets.button("Restore Defaults", _restore_defaults))
	f.add_child(MenuWidgets.spacer())
	f.add_child(MenuWidgets.button("Done", close_self, &"AccentButton"))
	body.add_child(f)

	MenuWidgets.select_tab(strip, _tab)
	_fill()


func _fill() -> void:
	if _content == null:
		return
	MenuWidgets.clear(_content)
	match _tab:
		0: _video()
		1: _audio()
		2: _gameplay()
		3: _controls()


func _section(title_text: String) -> void:
	var l := MenuWidgets.label(title_text.to_upper(), &"TinyLabel")
	l.add_theme_color_override(&"font_color", MenuTheme.ACCENT_DIM)
	_content.add_child(l)


# ---------------------------------------------------------------------- video
func _video() -> void:
	_section("Display")
	_content.add_child(MenuWidgets.field("Window mode",
		MenuWidgets.options(PackedStringArray(WINDOW_MODES),
			int(UI.get_setting("video/window_mode", 0)),
			func(i: int) -> void: UI.set_setting("video/window_mode", i))))

	var res_names := PackedStringArray()
	for r: Vector2i in UI.RESOLUTIONS:
		res_names.append("%d x %d" % [r.x, r.y])
	_content.add_child(MenuWidgets.field("Resolution",
		MenuWidgets.options(res_names, int(UI.get_setting("video/resolution", 0)),
			func(i: int) -> void: UI.set_setting("video/resolution", i))))

	_content.add_child(MenuWidgets.field("V-Sync",
		MenuWidgets.options(PackedStringArray(VSYNC_MODES),
			int(UI.get_setting("video/vsync", 1)),
			func(i: int) -> void: UI.set_setting("video/vsync", i))))

	_content.add_child(MenuWidgets.field("Anti-aliasing",
		MenuWidgets.options(PackedStringArray(MSAA_MODES),
			int(UI.get_setting("video/msaa", 0)),
			func(i: int) -> void: UI.set_setting("video/msaa", i))))

	_content.add_child(MenuWidgets.field("UI scale",
		MenuWidgets.slider(0.75, 1.5, 0.05, float(UI.get_setting("video/ui_scale", 1.0)),
			func(v: float) -> void: UI.set_setting("video/ui_scale", v), "x")))

	_content.add_child(MenuWidgets.rule())
	_section("Perspective")
	_content.add_child(MenuWidgets.toggle("Flip transition effect",
		bool(UI.get_setting("video/flip_effect", true)),
		func(v: bool) -> void: UI.set_setting("video/flip_effect", v)))
	_content.add_child(MenuWidgets.paragraph(
		"The world smears and re-forms as the camera swings to the next plane. "
		+ "Turn it off for an instant cut.", &"TinyLabel"))

	_content.add_child(MenuWidgets.toggle("Depth of field",
		bool(UI.get_setting("video/dof", false)),
		func(v: bool) -> void: UI.set_setting("video/dof", v)))
	_content.add_child(MenuWidgets.paragraph(
		"Blurs the layers behind the play plane. Costs a little performance.",
		&"TinyLabel"))


# ---------------------------------------------------------------------- audio
func _audio() -> void:
	_section("Levels")
	for entry: Array in [["Master", "master"], ["Music", "music"],
			["Sound effects", "sfx"], ["Ambience", "ambient"]]:
		var key := "audio/%s" % entry[1]
		_content.add_child(MenuWidgets.field(String(entry[0]),
			MenuWidgets.slider(0.0, 1.0, 0.01, float(UI.get_setting(key, 0.8)),
				func(v: float) -> void: UI.set_setting(key, v))))
	_content.add_child(MenuWidgets.rule())
	_content.add_child(MenuWidgets.paragraph(
		"Every sound in Planeshift is synthesised at runtime — there is not a "
		+ "single audio file in the build.", &"TinyLabel"))


# ------------------------------------------------------------------- gameplay
func _gameplay() -> void:
	_section("Feel")
	_content.add_child(MenuWidgets.field("Camera shake",
		MenuWidgets.slider(0.0, 1.5, 0.05, float(UI.get_setting("gameplay/camera_shake", 1.0)),
			func(v: float) -> void: UI.set_setting("gameplay/camera_shake", v), "x")))

	_content.add_child(MenuWidgets.toggle("Auto flip-assist",
		bool(UI.get_setting("gameplay/flip_assist", true)),
		func(v: bool) -> void: UI.set_setting("gameplay/flip_assist", v)))
	_content.add_child(MenuWidgets.paragraph(
		"When a path is blocked, briefly highlight the plane that opens it.",
		&"TinyLabel"))

	_content.add_child(MenuWidgets.rule())
	_section("Interface")
	_content.add_child(MenuWidgets.toggle("Item tooltips",
		bool(UI.get_setting("gameplay/tooltips", true)),
		func(v: bool) -> void: UI.set_setting("gameplay/tooltips", v)))
	_content.add_child(MenuWidgets.toggle("Tutorial hints",
		bool(UI.get_setting("gameplay/tutorials", true)),
		func(v: bool) -> void:
			UI.set_setting("gameplay/tutorials", v)
			if v:
				UI.open("tutorial")
			else:
				UI.close("tutorial")))
	_content.add_child(MenuWidgets.toggle("Show title screen on launch",
		bool(UI.get_setting("gameplay/show_title", true)),
		func(v: bool) -> void: UI.set_setting("gameplay/show_title", v)))
	_content.add_child(MenuWidgets.toggle("Autosave before travelling",
		bool(UI.get_setting("gameplay/autosave", true)),
		func(v: bool) -> void: UI.set_setting("gameplay/autosave", v)))

	_content.add_child(MenuWidgets.rule())
	_section("Reset tutorials")
	_content.add_child(MenuWidgets.button("Show all hints again", func() -> void:
		for k: String in UI.settings.keys():
			if k.begins_with("tutorial/"):
				UI.settings.erase(k)
		UI.save_settings()
		Events.toast("Tutorial hints reset.", "info")))


# ------------------------------------------------------------------- controls
func _controls() -> void:
	_section("Click a binding, then press a key")
	var actions := UI.rebindable_actions()
	for action: StringName in actions:
		var r := MenuWidgets.row(4)
		var name_label := MenuWidgets.label(
			String(action).capitalize().replace("_", " "), &"DimLabel")
		name_label.custom_minimum_size = Vector2(200, 0)
		r.add_child(name_label)

		var b := MenuWidgets.button(MenuWidgets.action_key_name(action))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _begin_listen(action, b))
		r.add_child(b)

		var reset := MenuWidgets.small_button("⟲", func() -> void:
			UI.reset_binding(action)
			b.text = MenuWidgets.action_key_name(action))
		MenuWidgets.tip(reset, "Restore the default binding")
		r.add_child(reset)
		_content.add_child(r)

	_content.add_child(MenuWidgets.rule())
	_content.add_child(MenuWidgets.button("Restore all default bindings", func() -> void:
		UI.reset_binding()
		_fill()))


func _begin_listen(action: StringName, b: Button) -> void:
	if _listening != &"":
		_cancel_listen()
	_listening = action
	_listen_button = b
	b.text = "press a key…"
	b.add_theme_color_override(&"font_color", MenuTheme.ACCENT)
	set_process_input(true)


func _cancel_listen() -> void:
	if _listen_button != null:
		_listen_button.remove_theme_color_override(&"font_color")
		_listen_button.text = MenuWidgets.action_key_name(_listening)
	_listening = &""
	_listen_button = null


func _input(event: InputEvent) -> void:
	if _listening == &"":
		return
	var usable := (event is InputEventKey and (event as InputEventKey).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if not usable:
		return
	get_viewport().set_input_as_handled()

	var key := event as InputEventKey
	if key != null and key.keycode == KEY_ESCAPE:
		_cancel_listen()
		return

	var action := _listening
	_release_conflicts(action, event)
	UI.rebind(action, event)
	_cancel_listen()
	# The label of every row may have changed if a conflict was cleared.
	call_deferred(&"_fill")


## A key can only mean one thing. Strip it from any other action first.
func _release_conflicts(keep: StringName, event: InputEvent) -> void:
	for a: StringName in UI.rebindable_actions():
		if a == keep:
			continue
		for e: InputEvent in InputMap.action_get_events(a):
			if e.is_match(event, false):
				InputMap.action_erase_event(a, e)
				Events.toast("Unbound %s from %s"
					% [MenuWidgets.action_key_name(keep),
						String(a).capitalize().replace("_", " ")], "warn")


func _restore_defaults() -> void:
	var yes: bool = await UI.confirm("Restore defaults",
		"Every video, audio, gameplay and control setting returns to its shipped value.",
		"Restore", "Cancel", true)
	if not yes:
		return
	for k: String in UI.DEFAULT_SETTINGS:
		UI.settings[k] = UI.DEFAULT_SETTINGS[k]
	UI.reset_binding()
	UI.apply_all_settings()
	UI.save_settings()
	_fill()
	Events.toast("Settings restored.", "info")


func _on_close() -> void:
	_cancel_listen()
