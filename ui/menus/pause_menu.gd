## The ESC menu. The only panel that stops the world: `pauses = true` makes
## [UI] call `Game.set_paused(true)` while it is on the stack, and release it
## again the moment it leaves.
extends MenuPanel


func _configure() -> void:
	modal = true
	captures = true
	pauses = true
	dim = 0.62
	placement = "center"
	anim = "scale"
	group = "fullscreen"


func _build() -> void:
	var body := frame("Paused", Vector2(380, 0), false)

	body.add_child(_status_block())
	body.add_child(MenuWidgets.rule())

	body.add_child(MenuWidgets.menu_entry("Resume", close_self))
	body.add_child(MenuWidgets.menu_entry("Inventory", func() -> void: UI.open("inventory")))
	body.add_child(MenuWidgets.menu_entry("Quest Log", func() -> void: UI.open("quests")))
	body.add_child(MenuWidgets.menu_entry("Star Map", func() -> void: UI.open("starmap")))
	body.add_child(MenuWidgets.rule())
	body.add_child(MenuWidgets.menu_entry("Save Game", _save))
	body.add_child(MenuWidgets.menu_entry("Options", func() -> void: UI.open("options")))
	body.add_child(MenuWidgets.menu_entry("Return to Title", _to_title))
	body.add_child(MenuWidgets.menu_entry("Quit to Desktop", _quit))


## A quick "where am I" readout, because the pause screen is where players look
## when they have lost track of the world.
func _status_block() -> Control:
	var c := MenuWidgets.col(2)
	var planet: String = World.planet_id if World != null else ""
	c.add_child(MenuWidgets.stat_row("Planet",
		planet.capitalize() if planet != "" else "—", MenuTheme.ACCENT))
	c.add_child(MenuWidgets.stat_row("Plane",
		"%s (%d)" % [View.view_name(), View.view], MenuTheme.CYAN))
	c.add_child(MenuWidgets.stat_row("Layer", str(View.layer)))
	c.add_child(MenuWidgets.stat_row("Day", "%d · %s" % [Game.day, Game.time_string()]))
	c.add_child(MenuWidgets.stat_row("Blocks mined",
		MenuWidgets.short_number(float(Game.stats.get("blocks_mined", 0)))))
	c.add_child(MenuWidgets.stat_row("Flips",
		MenuWidgets.short_number(float(Game.stats.get("flips", 0)))))
	return c


func _save() -> void:
	Events.save_requested.emit(0)
	Events.toast("Saving...", "info")


func _to_title() -> void:
	var yes: bool = await UI.confirm("Return to title",
		"Any progress since the last save will be lost.", "Return", "Stay", true)
	if not yes:
		return
	if bool(UI.get_setting("gameplay/autosave", true)):
		Events.save_requested.emit(0)
	UI.close_all()
	UI.open("main_menu")


func _quit() -> void:
	var yes: bool = await UI.confirm("Quit Planeshift",
		"Any progress since the last save will be lost.", "Quit", "Stay", true)
	if yes:
		get_tree().quit()
