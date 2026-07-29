## Decides *when* the game saves. `SaveManager` decides how.
##
## Triggers
## --------
## | trigger | setting | notes |
## |---|---|---|
## | periodic | `gameplay/autosave_interval` (s, 0 = off) | skipped while paused, in a menu, mid-flip or in combat |
## | travel | `gameplay/save_on_travel` | fires on `Events.travel_started`, before the world is torn down |
## | quit | `gameplay/save_on_quit` | window close / tree exit, synchronous by necessity |
## | death | `gameplay/save_on_death` | on hardcore (`difficulty >= 2`) the slot is **deleted** instead |
## | manual | — | `Events.save_requested(slot)`, bound to F6 in `project.godot` |
##
## Safety
## ------
## Durability is `SavCodec.write_atomic`: write to `.tmp`, flush, verify the
## length, rotate the previous file to `.bak`, then rename. A crash at any point
## leaves either the old save or the new one intact — never a half-written file
## — and `SavCodec.read_with_fallback` reaches for `.bak` automatically if the
## primary ever fails its checksum.
##
## Nothing here blocks: the chunk tier is already draining on a worker, and the
## metadata document is a few kilobytes. The player gets an `Events.notify` cue
## so the HUD can show what happened.
class_name SavAutosave
extends Node

## Do not autosave more often than this even if something asks.
const MIN_GAP := 20.0
## Retry delay when a save is deferred because the moment was bad.
const RETRY_GAP := 8.0
## Seconds since the last damage that count as "in combat".
const COMBAT_WINDOW := 6.0

signal autosave_started()
signal autosave_finished(ok: bool)

var enabled := true
var interval := 300.0
var slot := 0

var _elapsed := 0.0
var _since_last := 1e9
var _saving := false
var _quit_saved := false
var _last_combat := -1e9


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 95
	_reload_settings()
	# `SaveManager` parents the settings node to `/root` with a deferred call,
	# so ours has to queue behind it.
	_connect_settings.call_deferred()

	Events.save_requested.connect(_on_save_requested)
	Events.load_requested.connect(_on_load_requested)
	Events.travel_started.connect(_on_travel_started)
	Events.player_died.connect(_on_player_died)
	Events.player_damaged.connect(_on_player_damaged)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_on_quit()


func _exit_tree() -> void:
	save_on_quit()


func _process(delta: float) -> void:
	if not enabled or interval <= 0.0:
		return
	if Game.paused or Game.in_menu:
		return
	if not World.ready_flag:
		return
	_elapsed += delta
	_since_last += delta
	if _elapsed < interval:
		return
	if not _is_good_moment():
		_elapsed = interval - RETRY_GAP     ## try again shortly
		return
	_elapsed = 0.0
	request_autosave("auto")


# ==================================================================== triggers
## Save now unless something already is. `reason` only affects the HUD cue.
func request_autosave(reason: String = "auto") -> bool:
	if _saving or SaveManager.loading:
		return false
	if _since_last < MIN_GAP and reason == "auto":
		return false
	_saving = true
	autosave_started.emit()
	Events.notify.emit(_cue_for(reason), "save")
	var ok := SaveManager.save_game(slot)
	_saving = false
	_since_last = 0.0
	_elapsed = 0.0
	autosave_finished.emit(ok)
	if not ok:
		Events.notify.emit("Autosave failed — %s" % SaveManager.last_error(), "error")
	return ok


## Called from `Events.travel_started`, i.e. before `World.create_world` wipes
## the old planet. `SaveManager.flush_world` has not run yet at this point, so
## the chunk tier is captured by the save itself.
func _on_travel_started(_from_id: String, _to_id: String) -> void:
	if SaveManager.loading:
		return      ## `SavSaveFile.apply` travels on our behalf; do not re-save
	if not bool(SavSettings.get_setting("gameplay", "save_on_travel", true)):
		return
	if not World.ready_flag or World.planet_id == "":
		return      ## first travel of a new game: nothing to preserve yet
	request_autosave("travel")


## Hardcore (`Game.difficulty >= 2`) deletes the slot outright; anything else
## records the death so the player restarts from the graveyard, not from an
## hour ago.
func _on_player_died(cause: String) -> void:
	var hardcore := Game.difficulty >= 2
	if hardcore and bool(SavSettings.get_setting("gameplay", "hardcore_delete", true)):
		Events.notify.emit("Hardcore run ended (%s). Save deleted." % cause, "error")
		SaveManager.delete_save(slot)
		return
	if bool(SavSettings.get_setting("gameplay", "save_on_death", true)):
		request_autosave("death")


## Best-effort synchronous save as the process goes down. Runs at most once.
func save_on_quit() -> void:
	if _quit_saved or _saving:
		return
	_quit_saved = true
	if not is_instance_valid(SaveManager) or SaveManager.loading:
		return
	if not bool(SavSettings.get_setting("gameplay", "save_on_quit", true)):
		return
	if not World.ready_flag or Game.player == null or not is_instance_valid(Game.player):
		return
	SaveManager.save_game(slot)


func _on_save_requested(p_slot: int) -> void:
	slot = p_slot
	if _saving:
		return
	_saving = true
	Events.notify.emit("Saving...", "save")
	var ok := SaveManager.save_game(p_slot)
	_saving = false
	_since_last = 0.0
	_elapsed = 0.0
	Events.notify.emit("Game saved." if ok else "Save failed.", "save" if ok else "error")


func _on_load_requested(p_slot: int) -> void:
	if _saving:
		return
	if SaveManager.load_game(p_slot):
		slot = p_slot
		Events.notify.emit("Game loaded.", "save")
	else:
		Events.notify.emit("Load failed — %s" % SaveManager.last_error(), "error")


func _on_player_damaged(_amount: float, _element: String, _source: Node) -> void:
	_last_combat = float(Time.get_ticks_msec()) * 0.001


# ===================================================================== helpers
## Autosaving mid-flip or mid-fight produces a save the player will resent.
func _is_good_moment() -> bool:
	if View.flipping or View.shifting:
		return false
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.dead:
		return false
	var now := float(Time.get_ticks_msec()) * 0.001
	if now - _last_combat < COMBAT_WINDOW:
		return false
	return true


func _cue_for(reason: String) -> String:
	match reason:
		"travel": return "Autosaving before travel..."
		"death": return "Recording your demise..."
		"quit": return "Saving before quit..."
		_: return "Autosaving..."


func _connect_settings() -> void:
	var s := SavSettings.instance()
	if s != null and not s.changed.is_connected(_on_setting_changed):
		s.changed.connect(_on_setting_changed)
		s.reloaded.connect(_reload_settings)
	_reload_settings()


func _reload_settings() -> void:
	enabled = bool(SavSettings.get_setting("gameplay", "autosave_enabled", true))
	interval = float(SavSettings.get_setting("gameplay", "autosave_interval", 300.0))


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "gameplay" and (key == "autosave_enabled" or key == "autosave_interval"):
		_reload_settings()
		_elapsed = 0.0
