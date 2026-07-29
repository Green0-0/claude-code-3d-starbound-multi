## The one modal dialog: yes/no confirmation, single-line prompt, or a short
## list of choices. Driven entirely from [method UI.confirm],
## [method UI.prompt] and [method UI.choose], which `await` [signal finished].
##
## Registered as a "multi" panel, so a confirmation raised from inside another
## confirmation's handler stacks correctly instead of stealing the first one.
extends MenuPanel

## Emitted exactly once: `bool` for confirm, `String` for prompt, `int` for
## choose. Cancelling yields false / "" / -1 respectively.
signal finished(result: Variant)

var _mode: String = "confirm"
var _input: LineEdit = null
var _done: bool = false


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.5
	placement = "center"
	anim = "scale"
	esc_closes = true


func _build() -> void:
	_mode = String(ctx.get("mode", "confirm"))
	var body := frame(String(ctx.get("title", "Confirm")), Vector2(440, 0), false)

	var text := String(ctx.get("body", ""))
	if text != "":
		body.add_child(MenuWidgets.paragraph(text, &"DimLabel"))

	match _mode:
		"prompt":
			_input = MenuWidgets.line_edit(String(ctx.get("text", "")),
				String(ctx.get("placeholder", "")), func(_t: String) -> void: _resolve_ok())
			body.add_child(_input)
			body.add_child(_buttons())
		"choose":
			var choices: PackedStringArray = ctx.get("choices", PackedStringArray())
			var list := MenuWidgets.col(4)
			for i in choices.size():
				var idx := i
				list.add_child(MenuWidgets.button(choices[i],
					func() -> void: _finish(idx), &"MenuEntryButton"))
			body.add_child(list)
			var f := footer()
			f.add_child(MenuWidgets.button(String(ctx.get("cancel", "Cancel")),
				func() -> void: _finish(-1)))
			body.add_child(f)
		_:
			body.add_child(_buttons())


func _buttons() -> HBoxContainer:
	var f := footer()
	f.add_child(MenuWidgets.button(String(ctx.get("cancel", "Cancel")), _resolve_cancel))
	var ok := MenuWidgets.button(String(ctx.get("ok", "Confirm")), _resolve_ok,
		&"DangerButton" if bool(ctx.get("danger", false)) else &"AccentButton")
	f.add_child(ok)
	return f


func _default_focus() -> Control:
	return _input


func _resolve_ok() -> void:
	_finish(_input.text if _input != null else true)


func _resolve_cancel() -> void:
	_finish("" if _mode == "prompt" else false)


func _finish(result: Variant) -> void:
	if _done:
		return
	_done = true
	finished.emit(result)
	close_self()


## ESC / clicking away resolves as a cancel, so an `await` never hangs.
func _on_close() -> void:
	if not _done:
		_done = true
		match _mode:
			"prompt": finished.emit("")
			"choose": finished.emit(-1)
			_: finished.emit(false)
