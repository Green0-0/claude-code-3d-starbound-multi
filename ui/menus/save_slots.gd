## Save / load slot browser. Opened with `UI.open("saves", {"mode": "load"})`
## or `{"mode": "save"}`.
##
## `SaveManager` owns the files; this panel only asks it. It normalises whatever
## `SaveManager.list_saves()` returns (array of dicts, array of slot numbers, or
## nothing at all) and falls back to probing `has_save(slot)` per slot. Saving
## goes through `Events.save_requested` so the persistence agent stays the only
## thing that touches disk.
extends MenuPanel

const FALLBACK_SLOT_COUNT := 8

var _mode: String = "load"
var _list: VBoxContainer = null


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.55
	placement = "center"
	anim = "scale"


func _on_open(context: Dictionary) -> void:
	_mode = String(context.get("mode", _mode))
	if _list != null:
		_fill()


func _build() -> void:
	_mode = String(ctx.get("mode", "load"))
	var body := frame("Load Game" if _mode == "load" else "Save Game", Vector2(560, 460))
	_list = MenuWidgets.col(4)
	var sc := MenuWidgets.scroll(_list)
	sc.custom_minimum_size = Vector2(0, 330)
	body.add_child(MenuWidgets.well(sc))

	var f := footer()
	f.add_child(MenuWidgets.label(
		"Slot 1 is also the quick-save slot (F5).", &"TinyLabel"))
	f.add_child(MenuWidgets.spacer())
	f.add_child(MenuWidgets.button("Close", close_self))
	body.add_child(f)
	_fill()


# ------------------------------------------------------------------ metadata
func _all_meta() -> Dictionary:
	var out: Dictionary = {}
	if SaveManager == null:
		return out
	if SaveManager.has_method(&"list_saves"):
		var raw: Variant = SaveManager.call(&"list_saves")
		if raw is Array:
			for i in (raw as Array).size():
				var e: Variant = (raw as Array)[i]
				if e is Dictionary:
					var d: Dictionary = e
					out[int(d.get("slot", i))] = d
				elif e is int:
					out[int(e)] = {}
		elif raw is Dictionary:
			for k: Variant in (raw as Dictionary):
				out[int(k)] = (raw as Dictionary)[k]
	if out.is_empty() and SaveManager.has_method(&"has_save"):
		for slot in _slot_count():
			if bool(SaveManager.call(&"has_save", slot)):
				out[slot] = {}
	return out


## `SaveManager.SLOT_COUNT` is a script constant, so it is only reachable
## through the constant map — not `Object.get()`.
func _slot_count() -> int:
	if SaveManager != null and SaveManager.get_script() != null:
		var consts: Dictionary = (SaveManager.get_script() as Script).get_script_constant_map()
		if consts.has("SLOT_COUNT"):
			return clampi(int(consts["SLOT_COUNT"]), 1, 16)
	return FALLBACK_SLOT_COUNT


func _fill() -> void:
	if _list == null:
		return
	MenuWidgets.clear(_list)
	var meta := _all_meta()
	for slot in _slot_count():
		_list.add_child(_slot_row(slot, meta.get(slot, {}) if meta.has(slot) else {}))
	if SaveManager == null or not SaveManager.has_method(&"save_game"):
		_list.add_child(MenuWidgets.label(
			"The persistence module is still a stub — slots will stay empty.",
			&"TinyLabel"))


func _slot_row(slot: int, meta: Dictionary) -> Control:
	var used: bool = not meta.is_empty() or _has(slot)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var row := MenuWidgets.row()
	card.add_child(row)

	var info := MenuWidgets.col(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var head := MenuWidgets.row(6)
	var title := String(meta.get("name", "")) if used else ""
	head.add_child(MenuWidgets.label(
		title if title != "" else "Slot %d" % (slot + 1), &"SmallLabel"))
	if slot == 0:
		head.add_child(MenuWidgets.badge("quick", MenuTheme.CYAN))
	if bool(meta.get("hardcore", false)):
		head.add_child(MenuWidgets.badge("hardcore", MenuTheme.BAD))
	head.add_child(MenuWidgets.spacer())
	info.add_child(head)

	if used:
		var planet := String(meta.get("planet_name", meta.get("planet",
			meta.get("planet_id", "unknown"))))
		var day := int(meta.get("day", 0))
		var clock := String(meta.get("time", ""))
		var playtime := float(meta.get("playtime", meta.get("seconds", 0.0)))
		var stamp := String(meta.get("saved_text", meta.get("saved_at", "")))
		var line := "%s · day %d" % [planet.capitalize(), day]
		if clock != "":
			line += " " + clock
		line += " · " + MenuWidgets.duration_string(playtime)
		info.add_child(MenuWidgets.label(line, &"TinyLabel"))
		if stamp != "":
			info.add_child(MenuWidgets.label(stamp, &"TinyLabel"))
	else:
		info.add_child(MenuWidgets.label("empty", &"TinyLabel"))

	var buttons := MenuWidgets.row(4)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _mode == "load":
		var load_b := MenuWidgets.button("Load", func() -> void: _load(slot), &"AccentButton")
		load_b.disabled = not used
		buttons.add_child(load_b)
	else:
		buttons.add_child(MenuWidgets.button("Overwrite" if used else "Save",
			func() -> void: _save(slot, used), &"AccentButton"))
	var del := MenuWidgets.button("Delete", func() -> void: _delete(slot), &"DangerButton")
	del.disabled = not used
	buttons.add_child(del)
	row.add_child(buttons)
	return card


func _has(slot: int) -> bool:
	return SaveManager != null and SaveManager.has_method(&"has_save") \
		and bool(SaveManager.call(&"has_save", slot))


# ------------------------------------------------------------------- actions
func _load(slot: int) -> void:
	var yes: bool = await UI.confirm("Load slot %d" % (slot + 1),
		"Unsaved progress in the current run is lost.", "Load", "Cancel", true)
	if not yes:
		return
	UI.close_all()
	# `persistence/autosave.gd` listens for this and calls `load_game` itself;
	# only fall back to a direct call when nothing is listening.
	if Events.load_requested.get_connections().is_empty() \
			and SaveManager != null and SaveManager.has_method(&"load_game"):
		SaveManager.call(&"load_game", slot)
	else:
		Events.load_requested.emit(slot)


func _save(slot: int, overwrite: bool) -> void:
	if overwrite:
		var yes: bool = await UI.confirm("Overwrite slot %d" % (slot + 1),
			"The save currently in this slot is replaced.", "Overwrite", "Cancel", true)
		if not yes:
			return
	if Events.save_requested.get_connections().is_empty() \
			and SaveManager != null and SaveManager.has_method(&"save_game"):
		SaveManager.call(&"save_game", slot)
	else:
		Events.save_requested.emit(slot)
	Events.toast("Saved to slot %d." % (slot + 1), "info")
	_fill()


func _delete(slot: int) -> void:
	var yes: bool = await UI.confirm("Delete slot %d" % (slot + 1),
		"This cannot be undone.", "Delete", "Keep", true)
	if not yes:
		return
	if SaveManager != null and SaveManager.has_method(&"delete_save"):
		SaveManager.call(&"delete_save", slot)
	else:
		Events.toast("The persistence module cannot delete saves yet.", "warn")
	_fill()
