## User settings, backed by `user://settings.cfg` (`ConfigFile`).
##
## Access
## ------
## There is no `Settings` autoload slot in `project.godot` (frozen), so this
## node is parented to the scene-tree root as `/root/Settings` by `SaveManager`
## at boot. Three equivalent ways in:
## ```gdscript
## SavSettings.get_setting("audio", "master", 0.8)      # static, always safe
## SaveManager.settings.get_value("audio", "master", 0.8)
## get_node("/root/Settings").get_value("audio", "master", 0.8)
## ```
## Writes emit `changed(section, key, value)` so live UI can react, and are
## debounced onto disk so a slider drag does not hammer the filesystem.
##
## The menus agent owns the `keybinds` section: store one entry per input
## action, value = `Array` of serialised `InputEvent`s (see `apply_keybinds`).
class_name SavSettings
extends Node

const PATH := "user://settings.cfg"
## Seconds to wait after the last write before saving to disk.
const SAVE_DEBOUNCE := 0.75

signal changed(section: String, key: String, value: Variant)
signal reloaded()

## The full default table. Anything not listed here still works — this is the
## documented, discoverable surface the other agents can rely on.
const DEFAULTS := {
	"video": {
		"fullscreen": false,
		"borderless": false,
		"vsync": true,
		"max_fps": 0,                 ## 0 = uncapped
		"resolution_scale": 1.0,      ## 0.5 .. 1.0 render scale
		"msaa": 0,                    ## 0 off, 1 2x, 2 4x, 3 8x
		"bloom": true,
		"screen_shake": 1.0,          ## multiplier, 0 disables
		"flash_effects": true,
		"show_fps": false,
		"ui_scale": 1.0,
		"pixel_perfect": true,
		"brightness": 1.0,
	},
	"audio": {
		"master": 0.8,
		"music": 0.7,
		"sfx": 0.9,
		"ambient": 0.6,
		"ui": 0.8,
		"mute": false,
	},
	"gameplay": {
		"autosave_enabled": true,
		"autosave_interval": 300.0,   ## seconds; 0 disables the periodic timer
		"save_on_travel": true,
		"save_on_quit": true,
		"save_on_death": true,
		"hardcore_delete": true,      ## hardcore death wipes the slot
		"difficulty": 1,              ## 0 casual, 1 survival, 2 hardcore
		"auto_pickup": true,
		"hold_to_mine": true,
		"damage_numbers": true,
		"tooltips": true,
		"flip_hints": true,
		"camera_smoothing": 0.85,
		"invert_flip": false,
	},
	"interface": {
		"hud_opacity": 1.0,
		"minimap": true,
		"hotbar_scale": 1.0,
		"language": "en",
		"subtitles": false,
	},
	"world": {
		"view_distance": 5,           ## chunks; advisory, World owns the real box
		"particle_density": 1.0,
		"liquid_quality": 1,
	},
	"debug": {
		"json_saves": false,          ## SavCodec writes readable JSON saves
		"verbose_saves": false,
		"show_chunk_borders": false,
		"self_test_on_boot": false,
	},
}

var _cfg := ConfigFile.new()
var _dirty := false
var _timer := 0.0
var _loaded := false
var _mirroring := false
## Keys removed since the last flush, so a merge-save does not resurrect them.
var _erased: Dictionary = {}


func _init() -> void:
	name = "Settings"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 200
	if not _loaded:
		load_settings()
	_bridge_ui.call_deferred()


## `UI` keeps a parallel flat settings store ("section/key" -> value) in the
## same file. Mirroring its change signal into this node means an options-menu
## slider immediately reaches everything reading `/root/Settings` — the camera
## rig, the autosave scheduler, the codec's debug flag.
func _bridge_ui() -> void:
	if UI == null or not is_instance_valid(UI):
		return
	if not UI.has_signal(&"setting_changed"):
		return
	if UI.is_connected(&"setting_changed", _on_ui_setting_changed):
		return
	UI.connect(&"setting_changed", _on_ui_setting_changed)


func _on_ui_setting_changed(key: String, value: Variant) -> void:
	if _mirroring:
		return
	var parts := key.split("/", true, 1)
	if parts.size() != 2:
		return
	_mirroring = true
	set_value(parts[0], parts[1], value)
	_mirroring = false


func _process(delta: float) -> void:
	if not _dirty:
		return
	_timer -= delta
	if _timer <= 0.0:
		save_settings()


# ==================================================================== load/save
## Read `user://settings.cfg`, filling in any missing key from `DEFAULTS`.
## Safe to call before `_ready` — `SaveManager` does exactly that so settings
## are available to every other module from the first frame.
func load_settings() -> void:
	_loaded = true
	var err := _cfg.load(PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("[SavSettings] %s unreadable (%s) — using defaults" % [PATH, error_string(err)])
		_cfg = ConfigFile.new()
	var wrote := false
	for section: String in DEFAULTS:
		var keys: Dictionary = DEFAULTS[section]
		for key: String in keys:
			if not _cfg.has_section_key(section, key):
				_cfg.set_value(section, key, keys[key])
				wrote = true
	if wrote:
		save_settings()
	SavCodec.debug_json = bool(get_value("debug", "json_saves", false)) or _cmdline_json()
	reloaded.emit()


## Flush to disk immediately.
##
## `ui/ui_manager.gd` writes the same file from its own flat settings store, so
## this **merges** rather than overwrites: the file on disk is re-read, our keys
## are layered on top, and the result is written back. Neither store can delete
## the other's keys, whichever saves last.
func save_settings() -> bool:
	_dirty = false
	_timer = 0.0
	var disk := ConfigFile.new()
	disk.load(PATH)          ## missing file is fine; we start from nothing
	for section: String in _cfg.get_sections():
		for key: String in _cfg.get_section_keys(section):
			disk.set_value(section, key, _cfg.get_value(section, key))
	for flat: String in _erased:
		var parts := flat.split("/", true, 1)
		if parts.size() == 2 and disk.has_section_key(parts[0], parts[1]):
			disk.erase_section_key(parts[0], parts[1])
	_erased.clear()
	var err := disk.save(PATH)
	if err != OK:
		push_error("[SavSettings] cannot write %s: %s" % [PATH, error_string(err)])
		return false
	_cfg = disk
	return true


## Restore one section (or everything when `section` is empty) to `DEFAULTS`.
func reset_to_defaults(section: String = "") -> void:
	for s: String in DEFAULTS:
		if section != "" and s != section:
			continue
		var keys: Dictionary = DEFAULTS[s]
		for key: String in keys:
			_cfg.set_value(s, key, keys[key])
			changed.emit(s, key, keys[key])
	save_settings()
	apply_all()


# ====================================================================== access
## Read a setting. `default` wins only when the key is absent *and* has no
## entry in `DEFAULTS`.
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	var fallback: Variant = default
	if default == null and DEFAULTS.has(section):
		var d: Dictionary = DEFAULTS[section]
		if d.has(key):
			fallback = d[key]
	return _cfg.get_value(section, key, fallback)


## Write a setting, emit `changed`, and schedule a debounced disk write.
func set_value(section: String, key: String, value: Variant, apply: bool = true) -> void:
	var old: Variant = _cfg.get_value(section, key, null)
	if old != null and typeof(old) == typeof(value) and old == value:
		return
	_cfg.set_value(section, key, value)
	_erased.erase("%s/%s" % [section, key])
	_dirty = true
	_timer = SAVE_DEBOUNCE
	changed.emit(section, key, value)
	if apply:
		_apply_one(section, key, value)


func has(section: String, key: String) -> bool:
	return _cfg.has_section_key(section, key)


func erase(section: String, key: String) -> void:
	if _cfg.has_section_key(section, key):
		_cfg.erase_section_key(section, key)
	_erased["%s/%s" % [section, key]] = true
	_dirty = true
	_timer = SAVE_DEBOUNCE


## Every key/value of a section, defaults included. Handy for building a
## settings menu generically.
func section_values(section: String) -> Dictionary:
	var out := {}
	if DEFAULTS.has(section):
		out = (DEFAULTS[section] as Dictionary).duplicate()
	if _cfg.has_section(section):
		for key: String in _cfg.get_section_keys(section):
			out[key] = _cfg.get_value(section, key)
	return out


func sections() -> Array:
	var out: Array = DEFAULTS.keys()
	for s: String in _cfg.get_sections():
		if not out.has(s):
			out.append(s)
	return out


# =============================================================== static helpers
## Static access for modules that do not want to reach through `SaveManager`.
## Returns `default` when settings have not been created yet.
static func instance() -> SavSettings:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root := (loop as SceneTree).root
		if root != null and root.has_node(^"Settings"):
			return root.get_node(^"Settings") as SavSettings
	return null


static func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	var s := instance()
	if s != null:
		return s.get_value(section, key, default)
	if default != null:
		return default
	if DEFAULTS.has(section):
		var d: Dictionary = DEFAULTS[section]
		if d.has(key):
			return d[key]
	return null


static func set_setting(section: String, key: String, value: Variant) -> void:
	var s := instance()
	if s != null:
		s.set_value(section, key, value)


# ================================================================== application
## Push every setting into the engine. Called on boot and after a bulk reset.
func apply_all() -> void:
	for section: String in DEFAULTS:
		var keys: Dictionary = DEFAULTS[section]
		for key: String in keys:
			_apply_one(section, key, get_value(section, key))
	apply_keybinds()


func _apply_one(section: String, key: String, value: Variant) -> void:
	match section:
		"video": _apply_video(key, value)
		"audio": _apply_audio(key, value)
		"debug":
			if key == "json_saves":
				SavCodec.debug_json = bool(value) or _cmdline_json()
		_:
			pass


func _apply_video(key: String, value: Variant) -> void:
	var win: Window = get_window() if is_inside_tree() else null
	# The menus agent drives the window through its own `video/window_mode` key.
	# When that exists, stand down rather than fight it every frame.
	var menus_own_window := _cfg.has_section_key("video", "window_mode")
	match key:
		"fullscreen":
			if win != null and not menus_own_window:
				win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if bool(value) else Window.MODE_WINDOWED
		"borderless":
			if win != null and not menus_own_window:
				win.borderless = bool(value)
		"vsync":
			# The menus agent stores this as a DisplayServer mode (0..3); we
			# default to a plain bool. Accept either.
			if value is int:
				DisplayServer.window_set_vsync_mode(clampi(int(value), 0, 3))
			else:
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = maxi(0, int(value))
		_:
			pass   ## resolution_scale / msaa / bloom are read by the render agent


func _apply_audio(key: String, value: Variant) -> void:
	if key == "mute":
		AudioServer.set_bus_mute(0, bool(value))
		return
	var idx := _bus_index(key)
	if idx < 0:
		return
	var v := clampf(float(value), 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, -80.0 if v <= 0.001 else linear_to_db(v))


## Match an audio settings key to a bus by name, case-insensitively. Buses are
## owned by the fx agent and may not exist yet, hence the guard.
func _bus_index(key: String) -> int:
	if key == "master":
		return 0
	var want := key.to_lower()
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).to_lower() == want:
			return i
	return -1


## Re-apply every keybinding override on disk.
##
## Two encodings are accepted, because two agents write bindings:
## * `[keybinds]` — `Array` of real `InputEvent`s (ConfigFile serialises them
##   natively). This is what `capture_keybind()` writes.
## * `[input]` — `Array` of compact strings `"key:65"`, `"mouse:1"`, `"pad:0"`,
##   `"axis:0:1"`. This is what `ui/ui_manager.gd` writes.
func apply_keybinds() -> void:
	for section: String in ["keybinds", "input"]:
		if not _cfg.has_section(section):
			continue
		for action: String in _cfg.get_section_keys(section):
			var raw: Variant = _cfg.get_value(section, action, null)
			if not (raw is Array):
				continue
			var events := _decode_binding(raw as Array)
			if events.is_empty():
				continue
			var an := StringName(action)
			if not InputMap.has_action(an):
				InputMap.add_action(an)
			InputMap.action_erase_events(an)
			for e: InputEvent in events:
				InputMap.action_add_event(an, e)


static func _decode_binding(raw: Array) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for item: Variant in raw:
		if item is InputEvent:
			out.append(item)
			continue
		if not (item is String):
			continue
		var parts := String(item).split(":")
		if parts.size() < 2:
			continue
		match parts[0]:
			"key":
				var k := InputEventKey.new()
				k.physical_keycode = int(parts[1])
				out.append(k)
			"mouse":
				var m := InputEventMouseButton.new()
				m.button_index = int(parts[1])
				out.append(m)
			"pad":
				var p := InputEventJoypadButton.new()
				p.button_index = int(parts[1])
				out.append(p)
			"axis":
				if parts.size() >= 3:
					var a := InputEventJoypadMotion.new()
					a.axis = int(parts[1])
					a.axis_value = float(int(parts[2]))
					out.append(a)
	return out


## Convenience for the menus agent: store the current InputMap events for an
## action as the override.
func capture_keybind(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	set_value("keybinds", String(action), InputMap.action_get_events(action), false)


## Drop an override and let `project.godot`'s default take over again.
## Requires a restart to fully revert, so we simply forget the override.
func clear_keybind(action: StringName) -> void:
	erase("keybinds", String(action))


static func _cmdline_json() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a == "--save-json":
			return true
	for a: String in OS.get_cmdline_args():
		if a == "--save-json":
			return true
	return false
