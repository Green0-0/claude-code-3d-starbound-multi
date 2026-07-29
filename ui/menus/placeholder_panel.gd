## Shown instead of crashing when a panel's script is missing or does not
## extend [MenuPanel]. Twenty agents build this game in parallel, so "the module
## that owns this window has not landed yet" is a normal, expected state and
## deserves a real screen rather than a stack trace.
extends MenuPanel


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.5
	placement = "center"
	anim = "scale"


func _build() -> void:
	var title := String(ctx.get("title", "Panel"))
	var reason := String(ctx.get("reason", "This window is not available yet."))

	var body := frame(title, Vector2(480, 0))
	var icon := MenuWidgets.label("⌗", &"TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	icon.add_theme_color_override(&"font_color", MenuTheme.TEXT_MUTE)
	body.add_child(icon)

	var msg := MenuWidgets.paragraph(reason, &"DimLabel")
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(msg)

	body.add_child(MenuWidgets.rule())
	var hint := MenuWidgets.paragraph(
		"Everything else keeps working — this placeholder only stands in for the "
		+ "missing window.", &"TinyLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)

	var f := footer()
	f.add_child(MenuWidgets.button("Close", close_self))
	body.add_child(f)
