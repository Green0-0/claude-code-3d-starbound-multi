## Title screen. Opaque over whatever is running behind it, so it can appear at
## boot without touching `main.gd` or pausing the simulation (twenty agents
## share this project; a paused tree at boot would break everyone else's tests).
##
## Two pages live in the same window: the root menu and the New Game form.
extends MenuPanel

const DIFFICULTIES := ["Casual", "Survival", "Hardcore"]
const DIFFICULTY_BLURBS := [
	"Keep your items on death. Hunger and temperature are gentle. For building and exploring.",
	"The intended experience. Drop a few items on death, and the night has teeth.",
	"One life. Death ends the run and the save is retired.",
]

var _page: String = "root"
var _seed_field: LineEdit = null
var _difficulty: int = 1
var _blurb: Label = null
var _continue_button: Button = null


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 1.0            ## fully opaque: this *is* the screen
	placement = "fill"
	anim = "fade"
	esc_closes = false   ## the title screen is the bottom of the stack
	group = "fullscreen"


func _build() -> void:
	_backdrop()
	var root := bare() as VBoxContainer
	root.add_theme_constant_override(&"separation", 0)

	var columns := MenuWidgets.row(28)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	var left := MenuWidgets.col(MenuTheme.GAP)
	left.custom_minimum_size = Vector2(400, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(left)
	columns.add_child(MenuWidgets.spacer())

	_masthead(left)
	if _page == "root":
		_root_page(left)
	else:
		_new_game_page(left)

	var footer_row := MenuWidgets.row()
	footer_row.add_child(MenuWidgets.label(
		"%s · build %s" % [
			ProjectSettings.get_setting("application/config/name", "Planeshift"),
			Engine.get_version_info().get("string", "4.x")], &"TinyLabel"))
	footer_row.add_child(MenuWidgets.spacer())
	footer_row.add_child(MenuWidgets.label(
		"Four planes. One world. Turn it.", &"TinyLabel"))
	root.add_child(footer_row)


func _backdrop() -> void:
	var stars := TextureRect.new()
	stars.texture = MenuTheme.starfield_texture(640, 360, 20240729)
	stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stars.stretch_mode = TextureRect.STRETCH_SCALE
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.modulate = Color(1, 1, 1, 0.9)
	add_child(stars)

	var diorama := MenuPlaneDiorama.new()
	diorama.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diorama.offset_left = 380.0
	add_child(diorama)

	# A soft vignette so the menu column stays readable over the animation.
	var wash := ColorRect.new()
	wash.color = Color(MenuTheme.BG_DEEP.r, MenuTheme.BG_DEEP.g, MenuTheme.BG_DEEP.b, 0.55)
	wash.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	wash.offset_right = 430.0
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)


func _masthead(into: VBoxContainer) -> void:
	var t := MenuWidgets.label("PLANESHIFT", &"HeroLabel")
	t.add_theme_color_override(&"font_color", MenuTheme.ACCENT)
	into.add_child(t)
	var s := MenuWidgets.label("a sideways look at a solid world", &"SmallLabel")
	into.add_child(s)
	into.add_child(MenuWidgets.rule())


# --------------------------------------------------------------------- pages
func _root_page(into: VBoxContainer) -> void:
	into.add_child(MenuWidgets.menu_entry("New Game", func() -> void: _go("new")))

	_continue_button = MenuWidgets.menu_entry("Continue", _continue_game)
	_continue_button.disabled = not _has_save(0)
	if _continue_button.disabled:
		MenuWidgets.tip(_continue_button, "No save in slot 1 yet.")
	into.add_child(_continue_button)

	into.add_child(MenuWidgets.menu_entry("Load Game",
		func() -> void: UI.open("saves", {"mode": "load"})))
	into.add_child(MenuWidgets.menu_entry("Options", func() -> void: UI.open("options")))
	into.add_child(MenuWidgets.menu_entry("Credits", func() -> void: UI.open("credits")))
	into.add_child(MenuWidgets.menu_entry("Quit", _quit))


func _new_game_page(into: VBoxContainer) -> void:
	into.add_child(MenuWidgets.label("NEW GAME", &"HeadLabel"))

	_seed_field = MenuWidgets.line_edit(str(randi() % 100000000), "world seed")
	var seed_row := MenuWidgets.row(4)
	seed_row.add_child(_seed_field)
	seed_row.add_child(MenuWidgets.small_button("⟳", func() -> void:
		_seed_field.text = str(randi() % 100000000)))
	into.add_child(MenuWidgets.field("Seed", seed_row, 90))
	into.add_child(MenuWidgets.label(
		"Any text works — words are hashed into a seed.", &"TinyLabel"))

	var diff := MenuWidgets.options(PackedStringArray(DIFFICULTIES), _difficulty,
		func(i: int) -> void:
			_difficulty = i
			_blurb.text = DIFFICULTY_BLURBS[i])
	into.add_child(MenuWidgets.field("Difficulty", diff, 90))
	_blurb = MenuWidgets.paragraph(DIFFICULTY_BLURBS[_difficulty], &"TinyLabel")
	into.add_child(_blurb)

	into.add_child(MenuWidgets.rule())
	var row := MenuWidgets.row()
	row.add_child(MenuWidgets.button("Back", func() -> void: _go("root")))
	row.add_child(MenuWidgets.spacer())
	row.add_child(MenuWidgets.button("Begin", _start_new, &"AccentButton"))
	into.add_child(row)


func _go(page: String) -> void:
	_page = page
	rebuild()


# ------------------------------------------------------------------- actions
func _start_new() -> void:
	var text := _seed_field.text.strip_edges() if _seed_field != null else ""
	var world_seed := 0
	if text.is_valid_int():
		world_seed = int(text)
	elif text != "":
		world_seed = absi(text.hash())
	if world_seed == 0:
		world_seed = randi()

	if Game != null:
		Game.difficulty = _difficulty
		if Game.has_method(&"start_new_game"):
			Game.start_new_game(world_seed)
	Events.toast("New game — seed %d, %s" % [world_seed, DIFFICULTIES[_difficulty]], "info")
	UI.close_all()
	if bool(UI.get_setting("gameplay/tutorials", true)):
		UI.open("tutorial")


func _continue_game() -> void:
	if not _has_save(0):
		Events.toast("Nothing to continue.", "warn")
		return
	if SaveManager.has_method(&"load_game"):
		SaveManager.load_game(0)
	UI.close_all()


func _quit() -> void:
	var yes: bool = await UI.confirm("Quit Planeshift", "Unsaved progress will be lost.",
		"Quit", "Stay", true)
	if yes:
		get_tree().quit()


func _has_save(slot: int) -> bool:
	if SaveManager == null or not SaveManager.has_method(&"has_save"):
		return false
	return bool(SaveManager.has_save(slot))


func _default_focus() -> Control:
	return _seed_field if _page == "new" else null
