## Shown by [UI] when `Events.player_died(cause)` fires. Closes every other
## panel first, so there is nothing to hide behind.
##
## Respawn is offered on Casual and Survival. On Hardcore the run is over and
## the only ways out are the last save or the title screen.
extends MenuPanel

var _cause: String = ""


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.82
	placement = "center"
	anim = "fade"
	esc_closes = false        ## death is not a window you dismiss
	group = "fullscreen"


func _build() -> void:
	_cause = String(ctx.get("cause", "unknown"))
	var hardcore: bool = Game != null and Game.difficulty >= 2

	var root := bare(Vector2(520, 0))
	var card := PanelContainer.new()
	card.theme_type_variation = &"WindowPanel"
	root.add_child(card)
	var body := MenuWidgets.col()
	card.add_child(body)

	var title := MenuWidgets.label("YOU DIED", &"TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override(&"font_color", MenuTheme.BAD)
	body.add_child(title)

	var reason := MenuWidgets.paragraph(_cause_text(), &"DimLabel")
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(reason)

	body.add_child(MenuWidgets.rule())
	body.add_child(_run_stats())
	body.add_child(MenuWidgets.rule())

	if hardcore:
		var warn := MenuWidgets.paragraph(
			"Hardcore: this run is over. The save has been retired.", &"BadLabel")
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(warn)
	else:
		body.add_child(MenuWidgets.button("Respawn", _respawn, &"AccentButton"))

	body.add_child(MenuWidgets.button("Load Last Save", _load_last))
	body.add_child(MenuWidgets.button("Return to Title", _to_title))


func _cause_text() -> String:
	match _cause:
		"fall": return "The ground arrived faster than expected."
		"drown": return "There was no air in that layer."
		"lava", "fire": return "Burned away."
		"freeze", "cold": return "The cold got there first."
		"starve", "hunger": return "Starved."
		"suffocate": return "Sealed inside solid rock. Flip earlier next time."
		"void": return "Fell out of the world."
		"unknown", "": return "Something in the dark."
		_: return "Killed by %s." % _cause.replace("_", " ")


func _run_stats() -> Control:
	var c := MenuWidgets.col(2)
	c.add_child(MenuWidgets.label("This run", &"TinyLabel"))
	if Game == null:
		return c
	var stats: Dictionary = Game.stats
	c.add_child(MenuWidgets.stat_row("Days survived", str(Game.day), MenuTheme.ACCENT))
	c.add_child(MenuWidgets.stat_row("Planet",
		World.planet_id.capitalize() if World != null and World.planet_id != "" else "—"))
	for pair: Array in [
			["Blocks mined", "blocks_mined"], ["Blocks placed", "blocks_placed"],
			["Monsters killed", "monsters_killed"], ["Items crafted", "items_crafted"],
			["Planes flipped", "flips"], ["Planets visited", "planets_visited"],
			["Deaths", "deaths"]]:
		c.add_child(MenuWidgets.stat_row(String(pair[0]),
			MenuWidgets.short_number(float(stats.get(String(pair[1]), 0)))))
	return c


# ------------------------------------------------------------------- actions
func _respawn() -> void:
	close_self()
	var player := Game.player if Game != null else null
	if player != null and player.has_method(&"respawn"):
		player.call(&"respawn")
	elif player != null:
		# Minimal fallback so death is never a dead end: heal and put the player
		# back on the surface of the current world.
		player.set(&"dead", false)
		player.set(&"health", player.get(&"max_health"))
		if Game != null and Game.has_method(&"_place_player_on_surface"):
			Game.call(&"_place_player_on_surface")
	Events.player_respawned.emit()


func _load_last() -> void:
	if SaveManager != null and SaveManager.has_method(&"has_save") and SaveManager.has_save(0):
		close_self()
		SaveManager.load_game(0)
	else:
		Events.toast("No save to fall back on.", "warn")


func _to_title() -> void:
	UI.close_all()
	UI.open("main_menu")
