## Autoloaded as `UI`. The window manager for the whole game.
##
## Responsibilities, in the order they matter:
##
## 1. **Panel registry & stack.** Every window has a short string id (see
##    [constant PANELS]). `UI.open(id, ctx)` instantiates it on demand into the
##    `Menus` canvas layer, pushes it on a stack and animates it in.
## 2. **Input arbitration.** While any open panel declares `captures = true`,
##    [method captures_input] returns true and every gameplay reader
##    (`core/main.gd`, `player/player.gd`, tools, combat) must stand down. Modal
##    panels additionally swallow mouse events with a full-screen scrim, and
##    `ESC` pops exactly one level off the stack instead of reaching the game.
## 3. **Tooltip service.** `Events.tooltip_requested(text, pos)` or the richer
##    [method show_item_tooltip] draw into an always-topmost overlay layer.
## 4. **Drag & drop service.** A single cursor-held [ItemStack] shared by the
##    inventory, crafting, container and trash windows. See [method begin_drag]
##    for the payload contract — it is the one piece of this file other agents
##    have to understand.
## 5. **Modal helpers.** `await UI.confirm(...)`, `await UI.prompt(...)`,
##    `await UI.choose(...)`.
## 6. **Settings store.** Video/audio/gameplay options and key rebinds,
##    persisted to `user://settings.cfg`. Other modules may read them with
##    [method get_setting] — e.g. the camera reads `gameplay/camera_shake`.
extends Node

# ============================================================ panel vocabulary
## Canonical panel ids. Anything may call `UI.open()` with one of these.
const PANELS := {
	"main_menu": "res://ui/menus/main_menu.gd",
	"pause": "res://ui/menus/pause_menu.gd",
	"options": "res://ui/menus/options_menu.gd",
	"inventory": "res://ui/menus/inventory_panel.gd",
	"crafting": "res://ui/menus/crafting_panel.gd",
	"container": "res://ui/menus/container_panel.gd",
	"dialogue": "res://ui/menus/dialogue_panel.gd",
	"quests": "res://ui/menus/quest_log.gd",
	"starmap": "res://ui/menus/star_map_panel.gd",
	"tech": "res://ui/menus/tech_panel.gd",
	"death": "res://ui/menus/death_screen.gd",
	"saves": "res://ui/menus/save_slots.gd",
	"tutorial": "res://ui/menus/tutorial_prompts.gd",
	"credits": "res://ui/menus/credits_panel.gd",
	"confirm": "res://ui/menus/confirm_dialog.gd",
}
## Spellings other modules already use, mapped onto the canonical id above.
## Keeping this table means a caller is never punished for guessing.
const PANEL_ALIASES := {
	"star_map": "starmap", "starmap_panel": "starmap",
	"quest_log": "quests", "journal": "quests",
	"title": "main_menu", "titlescreen": "main_menu",
	"settings": "options",
	"save": "saves", "load": "saves", "save_slots": "saves",
	"bag": "inventory", "backpack": "inventory",
	"chest": "container", "storage": "container",
	"craft": "crafting", "crafting_bench": "crafting",
	"techs": "tech", "tech_tree": "tech",
	"dialog": "dialogue",
}

## Windows other agents open that this module does not implement. Listing them
## turns "unknown panel" into an honest "not built yet" screen.
const FUTURE_PANELS := {
	"ship_status": "The ship status console belongs to the space module.",
	"fuel_hatch": "The fuel hatch belongs to the space module.",
	"teleporter": "The teleporter bookmark list belongs to the space module.",
	"ark": "The Ark gate belongs to the quest campaign.",
	"printer": "The pixel printer belongs to the objects module.",
	"research": "The research tree belongs to the tech module.",
	"machine": "Machine consoles belong to the objects module.",
	"manipulator": "The matter-manipulator upgrade panel belongs to the tech module.",
	"shop": "Trading belongs to the NPC module.",
}

## Panels that may exist more than once at a time (nested dialogs).
const MULTI_PANELS := ["confirm"]
const PLACEHOLDER_SCRIPT := "res://ui/menus/placeholder_panel.gd"

const SETTINGS_PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const DEFAULT_SETTINGS := {
	"video/window_mode": 0,
	"video/resolution": 0,
	"video/vsync": 1,
	"video/msaa": 0,
	"video/flip_effect": true,
	"video/dof": false,
	"video/ui_scale": 1.0,
	"audio/master": 0.9,
	"audio/music": 0.65,
	"audio/sfx": 0.9,
	"audio/ambient": 0.7,
	"gameplay/camera_shake": 1.0,
	"gameplay/flip_assist": true,
	"gameplay/tooltips": true,
	"gameplay/tutorials": true,
	"gameplay/show_title": true,
	"gameplay/autosave": true,
}

# ==================================================================== signals
signal panel_opened(id: String)
signal panel_closed(id: String)
## Fired when a cursor-held stack starts moving. See [method begin_drag].
signal drag_started(payload: Dictionary)
## `accepted` is false when the stack was returned to its source or spilled.
signal drag_ended(payload: Dictionary, accepted: bool)
signal setting_changed(key: String, value: Variant)
## The quest log asks the HUD to pin a quest. `""` means "stop tracking".
signal quest_tracked(quest_id: String)

# ===================================================================== state
## Kept for the frozen stub API: ids of everything currently on the stack,
## bottom to top.
var open_panels: Array[String] = []
## Live settings, flat "section/key" -> value.
var settings: Dictionary = {}
## Quest id the HUD should pin, or "". Written by the quest log; read by the
## HUD agent, together with [signal quest_tracked].
var tracked_quest: String = ""

var _registry: Dictionary = {}
var _stack: Array[Dictionary] = []
var _uid: int = 0

var _host: CanvasLayer = null           ## the Menus layer from main.tscn
var _panel_layer: Control = null        ## panels are children of this
var _overlay: CanvasLayer = null        ## tooltip + drag ghost, always on top
var _fallback_host: CanvasLayer = null

var _captures: bool = false
var _pauses: bool = false
var _pause_owned: bool = false
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

# --- tooltip ---------------------------------------------------------------
var _tip_panel: PanelContainer = null
var _tip_text: RichTextLabel = null
var _tip_anchor: Vector2 = Vector2.ZERO

# --- drag ------------------------------------------------------------------
var _drag: Dictionary = {}
var _drag_ghost: Control = null
var _ghost_icon: TextureRect = null
var _ghost_count: Label = null
var _targets: Array[Dictionary] = []
var _drag_press_origin: Control = null

# --- input -----------------------------------------------------------------
var _default_binds: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id: String in PANELS:
		_registry[id] = {"script": PANELS[id], "multi": MULTI_PANELS.has(id)}
	_snapshot_default_binds()
	_load_settings()
	_build_overlay()
	Events.tooltip_requested.connect(_on_tooltip_requested)
	Events.station_opened.connect(_on_station_opened)
	Events.dialogue_started.connect(_on_dialogue_started)
	Events.dialogue_ended.connect(_on_dialogue_ended)
	Events.player_died.connect(_on_player_died)
	call_deferred(&"_post_boot")


func _post_boot() -> void:
	apply_all_settings()
	if bool(get_setting("gameplay/tutorials", true)):
		open("tutorial")
	# Never take over a CI / headless run: those exist to prove the *game* boots.
	if bool(get_setting("gameplay/show_title", true)) and DisplayServer.get_name() != "headless":
		open("main_menu")


# ======================================================================= host
## Called by `ui/menus/menu_root.gd` when the `Menus` CanvasLayer enters the
## tree. Panels created before that point live in a private fallback layer and
## are migrated across here.
func attach_host(layer: CanvasLayer, panel_parent: Control) -> void:
	_host = layer
	_panel_layer = panel_parent
	if _fallback_host != null:
		for e: Dictionary in _stack:
			var n: Node = e["node"]
			if is_instance_valid(n) and n.get_parent() != null:
				n.get_parent().remove_child(n)
				_panel_layer.add_child(n)
		_fallback_host.queue_free()
		_fallback_host = null


func _ensure_host() -> Control:
	if _panel_layer != null and is_instance_valid(_panel_layer):
		return _panel_layer
	if _fallback_host == null:
		_fallback_host = CanvasLayer.new()
		_fallback_host.layer = 10
		_fallback_host.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_fallback_host)
		var c := Control.new()
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.process_mode = Node.PROCESS_MODE_ALWAYS
		MenuTheme.apply(c)
		_fallback_host.add_child(c)
		_panel_layer = c
	return _panel_layer


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 128
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.apply(root)
	_overlay.add_child(root)

	_tip_panel = PanelContainer.new()
	_tip_panel.theme_type_variation = &"TooltipPanelBox"
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.visible = false
	_tip_panel.custom_minimum_size = Vector2(120, 0)
	root.add_child(_tip_panel)
	_tip_text = RichTextLabel.new()
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.scroll_active = false
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_text.custom_minimum_size = Vector2(240, 0)
	_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_text)

	_drag_ghost = Control.new()
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.visible = false
	_drag_ghost.custom_minimum_size = Vector2(MenuTheme.SLOT_SIZE, MenuTheme.SLOT_SIZE)
	_drag_ghost.size = Vector2(MenuTheme.SLOT_SIZE, MenuTheme.SLOT_SIZE)
	root.add_child(_drag_ghost)
	_ghost_icon = TextureRect.new()
	_ghost_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ghost_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.add_child(_ghost_icon)
	_ghost_count = Label.new()
	_ghost_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ghost_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ghost_count.add_theme_font_size_override(&"font_size", MenuTheme.FS_SMALL)
	_ghost_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.add_child(_ghost_count)


# =============================================================== public panel API
## Open (or re-focus) a panel. `ctx` is handed to the panel's `_on_open()`.
## Unknown ids degrade to a labelled placeholder window rather than crashing.
func open(panel: String, ctx: Dictionary = {}) -> MenuPanel:
	panel = resolve_id(panel)
	if panel == "":
		return null
	var def: Dictionary = _registry.get(panel, {})
	if not bool(def.get("multi", false)):
		var existing := _entry_of(panel)
		if not existing.is_empty():
			var node: MenuPanel = existing["node"]
			node.ctx = ctx
			node._on_open(ctx)
			_raise(existing)
			return node

	var script_path: String = def.get("script", "")
	var reason := ""
	var scr: Script = null
	if script_path == "":
		reason = String(FUTURE_PANELS.get(panel,
			"No panel is registered under the id \"%s\"." % panel))
	elif not _res_exists(script_path):
		reason = "The module that owns \"%s\" has not landed yet.\n(%s is missing.)" % [panel, script_path]
	else:
		scr = load(script_path) as Script
		if scr == null:
			reason = "\"%s\" failed to load its script." % panel

	var inst: MenuPanel = null
	if scr != null:
		var made: Variant = scr.new()
		inst = made as MenuPanel
		if inst == null:
			if made is Node:
				(made as Node).free()
			reason = "\"%s\" does not extend MenuPanel." % panel
	if inst == null:
		inst = _make_placeholder(panel, reason)
	if inst == null:
		push_warning("[UI] cannot open panel '%s': %s" % [panel, reason])
		return null

	inst.panel_id = panel
	inst.ctx = ctx
	_close_group_siblings(inst.group, panel)

	_uid += 1
	var entry := {"id": panel, "uid": _uid, "node": inst, "ctx": ctx}
	_stack.append(entry)
	_ensure_host().add_child(inst)
	inst.animate_in()
	_sync_state()
	panel_opened.emit(panel)
	Events.ui_panel_opened.emit(panel)
	return inst


## Close the topmost instance of `panel`. Safe to call for panels that are not
## open.
func close(panel: String) -> void:
	var e := _entry_of(resolve_id(panel))
	if e.is_empty():
		return
	_close_entry(e)


## Map an alias onto its canonical panel id. Safe for ids that are already
## canonical, and for ids nobody has implemented.
func resolve_id(panel: String) -> String:
	return String(PANEL_ALIASES.get(panel, panel))


## Close one specific panel node — used by [method MenuPanel.close_self] so
## nested dialogs always close themselves rather than a sibling.
func close_node(node: MenuPanel) -> void:
	for e: Dictionary in _stack:
		if e["node"] == node:
			_close_entry(e)
			return


func toggle(panel: String) -> MenuPanel:
	if is_open(panel):
		close(panel)
		return null
	return open(panel)


## Close everything, top first.
func close_all() -> void:
	for e: Dictionary in _stack.duplicate():
		_close_entry(e, false)
	_stack.clear()
	_sync_state()


## Pop exactly one level, honouring [member MenuPanel.esc_closes]. This is what
## ESC does; returns true when something was closed.
func back() -> bool:
	for i in range(_stack.size() - 1, -1, -1):
		var node: MenuPanel = _stack[i]["node"]
		if is_instance_valid(node) and node.esc_closes:
			_close_entry(_stack[i])
			return true
	return false


func is_open(panel: String) -> bool:
	return not _entry_of(resolve_id(panel)).is_empty()


## The live node for an open panel, or null.
func panel(panel_id: String) -> MenuPanel:
	var e := _entry_of(resolve_id(panel_id))
	return e["node"] if not e.is_empty() else null


## Id of the topmost panel, "" when nothing is open.
func top() -> String:
	return String(_stack[-1]["id"]) if not _stack.is_empty() else ""


## True while any open panel wants the keyboard/mouse. **Every gameplay input
## reader in the project must consult this before acting.**
func captures_input() -> bool:
	return _captures


## True while the stack forces the SceneTree paused.
func pauses_game() -> bool:
	return _pauses


## Register an extra panel at runtime. Other agents may use this to add their
## own windows without editing this file.
func register_panel(id: String, script_path: String, multi: bool = false) -> void:
	_registry[id] = {"script": script_path, "multi": multi}


# ------------------------------------------------------------------ internals
func _entry_of(panel: String) -> Dictionary:
	for i in range(_stack.size() - 1, -1, -1):
		if _stack[i]["id"] == panel and is_instance_valid(_stack[i]["node"]):
			return _stack[i]
	return {}


func _close_entry(e: Dictionary, resync: bool = true) -> void:
	_stack.erase(e)
	var node: MenuPanel = e["node"]
	var id: String = e["id"]
	if is_instance_valid(node):
		node.dismiss()
		var wait := node.animate_out()
		if wait > 0.0:
			get_tree().create_timer(wait, true, false, true).timeout.connect(
				func() -> void:
					if is_instance_valid(node):
						node.queue_free())
		else:
			node.queue_free()
	if resync:
		_sync_state()
	panel_closed.emit(id)
	Events.ui_panel_closed.emit(id)


func _raise(e: Dictionary) -> void:
	_stack.erase(e)
	_stack.append(e)
	var node: MenuPanel = e["node"]
	if is_instance_valid(node) and node.get_parent() != null:
		node.get_parent().move_child(node, -1)
	_sync_state()


func _close_group_siblings(group: String, _incoming: String) -> void:
	if group == "":
		return
	for e: Dictionary in _stack.duplicate():
		var n: MenuPanel = e["node"]
		if is_instance_valid(n) and n.group == group:
			_close_entry(e, false)


## Recompute everything derived from the stack: capture flag, pause state,
## mouse mode, `open_panels`, focus. Single choke point, so the "gameplay input
## is suppressed exactly when a modal is open" guarantee has one implementation.
func _sync_state() -> void:
	open_panels.clear()
	var caps := false
	var pause := false
	for e: Dictionary in _stack:
		var n: MenuPanel = e["node"]
		if not is_instance_valid(n):
			continue
		open_panels.append(String(e["id"]))
		caps = caps or n.captures
		pause = pause or n.pauses

	var was := _captures
	_captures = caps
	_pauses = pause

	if _captures != was:
		if _captures:
			_saved_mouse_mode = Input.mouse_mode
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			if Input.mouse_mode != _saved_mouse_mode:
				Input.mouse_mode = _saved_mouse_mode
			hide_tooltip()
			if is_dragging():
				cancel_drag()

	var g := _game()
	if g != null:
		g.set(&"in_menu", _captures)
		if pause and not _pause_owned:
			_pause_owned = true
			if g.has_method(&"set_paused"):
				g.call(&"set_paused", true)
		elif not pause and _pause_owned:
			_pause_owned = false
			if g.has_method(&"set_paused"):
				g.call(&"set_paused", false)

	# Hand focus to the new top panel so gamepad users are never stranded.
	if not _stack.is_empty():
		var top_node: MenuPanel = _stack[-1]["node"]
		if is_instance_valid(top_node) and top_node.captures:
			top_node.call_deferred(&"_focus_default")


func _game() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(^"Game")


static func _res_exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


func _make_placeholder(id: String, reason: String) -> MenuPanel:
	if not _res_exists(PLACEHOLDER_SCRIPT):
		return null
	var scr := load(PLACEHOLDER_SCRIPT) as Script
	if scr == null:
		return null
	var p := scr.new() as MenuPanel
	if p == null:
		return null
	p.ctx = {"title": id.capitalize(), "reason": reason}
	return p


# =================================================================== input
func _input(event: InputEvent) -> void:
	if is_dragging() and _handle_drag_input(event):
		get_viewport().set_input_as_handled()
		return
	if _stack.is_empty():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		# ESC belongs to the top window, never to the game, while menus are up.
		if back():
			get_viewport().set_input_as_handled()


## Gameplay action -> panel id. These hotkeys live here rather than in main.gd
## because only the panel stack knows whether a text field is eating keys.
const HOTKEYS := {
	&"inventory": "inventory", &"crafting": "crafting",
	&"quests": "quests", &"starmap": "starmap",
}


func _unhandled_input(event: InputEvent) -> void:
	for action: StringName in HOTKEYS:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			toggle(String(HOTKEYS[action]))
			get_viewport().set_input_as_handled()
			return


func _process(_delta: float) -> void:
	if _drag_ghost != null and _drag_ghost.visible:
		var m := _drag_ghost.get_global_mouse_position()
		_drag_ghost.global_position = m - _drag_ghost.size * 0.5
	if _tip_panel != null and _tip_panel.visible:
		_place_tooltip()


# ================================================================== tooltips
func _on_tooltip_requested(text: String, screen_pos: Vector2) -> void:
	if text == "":
		hide_tooltip()
	else:
		show_tooltip(text, screen_pos)


## Plain (BBCode-capable) tooltip anchored at `screen_pos`.
func show_tooltip(text: String, screen_pos: Vector2) -> void:
	if not bool(get_setting("gameplay/tooltips", true)) or _tip_panel == null:
		return
	if text == "":
		hide_tooltip()
		return
	_tip_text.text = text
	_tip_anchor = screen_pos
	_tip_panel.visible = true
	_tip_panel.size = Vector2.ZERO
	_place_tooltip()


## The full item card built by [MenuTooltip].
func show_item_tooltip(stack: ItemStack, screen_pos: Vector2) -> void:
	if stack == null or stack.is_empty():
		hide_tooltip()
		return
	show_tooltip(MenuTooltip.for_stack(stack), screen_pos)


func hide_tooltip() -> void:
	if _tip_panel != null:
		_tip_panel.visible = false


func _place_tooltip() -> void:
	var vp := _tip_panel.get_viewport_rect().size
	var s := _tip_panel.size
	var p := _tip_anchor
	if p.x + s.x > vp.x - 8.0:
		p.x = maxf(8.0, vp.x - s.x - 8.0)
	if p.y + s.y > vp.y - 8.0:
		p.y = maxf(8.0, vp.y - s.y - 8.0)
	_tip_panel.global_position = p


# ============================================================ drag and drop
#
#  THE PAYLOAD CONTRACT
#  --------------------
#  A drag payload is a plain Dictionary. The drag service owns the ItemStack
#  inside it for the whole gesture; the source has already removed those items
#  from its model, so the cursor is the single authoritative owner.
#
#    "stack"      : ItemStack  REQUIRED. Mutated in place as targets consume it.
#    "source"     : String     REQUIRED. Logical container id: "player",
#                              "equip", "hotbar", "container", "craft_output".
#    "index"      : int        Slot index inside `source`, or -1.
#    "slot_kind"  : String     "grid" | "equip" | "hotbar" | "output" | "trash".
#    "equip_slot" : StringName Only meaningful when slot_kind == "equip".
#    "mode"       : String     "move" (default) or "copy" (crafting preview).
#    "origin"     : Control    The slot the gesture began on. Used to tell a
#                              click apart from a drag, and to animate reverts.
#    "meta"       : Dictionary Free-form extras (recipe id, station node...).
#    "return"     : Callable   func(remainder: ItemStack) -> bool. Called with
#                              whatever no target accepted. MUST tolerate its
#                              panel having been closed mid-drag and return
#                              false if it could not take the items back — the
#                              service then spills them into the world.
#
#  A drop target registers two callables:
#    can_accept(payload) -> bool     cheap filter, may be called every frame
#    accept(payload)     -> bool     consume from payload.stack, in place
#
#  After `accept`, the service inspects `payload.stack`:
#    empty            -> gesture finished, accepted
#    changed contents -> a swap happened; keep dragging the displaced stack
#    unchanged        -> nothing was taken; keep dragging
#
func is_dragging() -> bool:
	return not _drag.is_empty()


## The live payload, or `{}`.
func drag_payload() -> Dictionary:
	return _drag


## The cursor-held stack, or null.
func drag_stack() -> ItemStack:
	return _drag.get("stack") as ItemStack if not _drag.is_empty() else null


## Take ownership of a stack and attach it to the cursor. Returns false when a
## drag is already in progress or the payload is malformed.
func begin_drag(payload: Dictionary) -> bool:
	if is_dragging():
		return false
	var s: ItemStack = payload.get("stack") as ItemStack
	if s == null or s.is_empty():
		return false
	_drag = payload
	_drag_press_origin = payload.get("origin") as Control
	hide_tooltip()
	_refresh_ghost()
	_drag_ghost.visible = true
	drag_started.emit(_drag)
	return true


## Register `c` as a drop target for as long as it is alive.
func register_drop_target(c: Control, can_accept: Callable, accept: Callable) -> void:
	unregister_drop_target(c)
	_targets.append({"ctrl": c, "can": can_accept, "accept": accept})


func unregister_drop_target(c: Control) -> void:
	for t: Dictionary in _targets.duplicate():
		if t["ctrl"] == c or not is_instance_valid(t["ctrl"]):
			_targets.erase(t)


## Resolve the current drag onto an explicit control (keyboard / gamepad path).
## `amount` is -1 for "everything" or a positive count.
func resolve_drop_on(c: Control, amount: int = -1) -> void:
	for t: Dictionary in _targets:
		if t["ctrl"] == c:
			_apply_drop(t, amount)
			return


## Give the held stack back to its source; spill into the world if that fails.
func cancel_drag() -> void:
	if not is_dragging():
		return
	var payload := _drag
	var s: ItemStack = payload.get("stack")
	var ret: Callable = payload.get("return", Callable())
	var returned := false
	if ret.is_valid():
		var r: Variant = ret.call(s)
		returned = (r is bool and bool(r)) or (s != null and s.is_empty())
	if not returned and s != null and not s.is_empty():
		spill_to_world(s)
	_end_drag(false)


## Drop `s` on the floor next to the player. Last resort so items are never
## silently destroyed by a UI mistake.
func spill_to_world(s: ItemStack) -> void:
	if s == null or s.is_empty():
		return
	var g := _game()
	var player := (g.get(&"player") if g != null else null) as Node3D
	if g != null and player != null and g.has_method(&"spawn_item_drop"):
		g.call(&"spawn_item_drop", player.global_position + Vector3(0, 0.6, 0),
			s.id, s.count, s.data)
		Events.toast("Dropped %s x%d" % [s.display_name(), s.count], "info")
	else:
		Events.toast("Lost %s x%d" % [s.display_name(), s.count], "warn")
	s.clear()


func _end_drag(accepted: bool) -> void:
	var payload := _drag
	_drag = {}
	_drag_press_origin = null
	if _drag_ghost != null:
		_drag_ghost.visible = false
	drag_ended.emit(payload, accepted)


func _refresh_ghost() -> void:
	var s := drag_stack()
	if s == null or s.is_empty():
		_drag_ghost.visible = false
		return
	_ghost_icon.texture = MenuTheme.stack_icon(s, MenuTheme.ICON_SIZE)
	_ghost_count.text = MenuWidgets.short_number(s.count) if s.count > 1 else ""
	_ghost_count.add_theme_color_override(&"font_color", MenuTheme.rarity_color(s.rarity()))


func _handle_drag_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb == null:
		if event.is_action_pressed(&"ui_cancel"):
			cancel_drag()
			return true
		return false
	var pos := mb.position
	if mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_resolve_at(pos, -1)
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_resolve_at(pos, 1)
			return true
		return false
	# Release: only meaningful as the end of a genuine drag gesture, i.e. the
	# cursor has left the slot the stack was picked up from.
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var t := _target_at(pos)
		var over: Control = t.get("ctrl") if not t.is_empty() else null
		if over != null and over != _drag_press_origin:
			_resolve_at(pos, -1)
			return true
	return false


func _resolve_at(pos: Vector2, amount: int) -> void:
	var t := _target_at(pos)
	if t.is_empty():
		if not point_over_ui(pos):
			var s := drag_stack()
			spill_to_world(s)
			_end_drag(false)
		return
	_apply_drop(t, amount)


func _apply_drop(t: Dictionary, amount: int) -> void:
	var s := drag_stack()
	if s == null or s.is_empty():
		_end_drag(false)
		return
	var can: Callable = t["can"]
	if can.is_valid() and not bool(can.call(_drag)):
		return

	var accept: Callable = t["accept"]
	if not accept.is_valid():
		return

	if amount > 0 and amount < s.count:
		# "Place exactly N": hand the target a detached sub-stack so a refusal
		# cannot corrupt the held one.
		var sub := ItemStack.new(s.id, amount, s.data)
		var sub_payload := _drag.duplicate()
		sub_payload["stack"] = sub
		var took_before := sub.count
		accept.call(sub_payload)
		var moved := took_before - sub.count
		if moved > 0:
			s.count -= moved
			if s.count <= 0:
				s.clear()
		_after_drop()
		return

	var before_id := s.id
	var before_count := s.count
	accept.call(_drag)
	if s.id != before_id or s.count != before_count:
		_after_drop()


func _after_drop() -> void:
	var s := drag_stack()
	if s == null or s.is_empty():
		_end_drag(true)
	else:
		_refresh_ghost()


## Topmost registered drop target under `pos`, respecting panel stacking order.
func _target_at(pos: Vector2) -> Dictionary:
	var best := {}
	var best_rank := -1
	for t: Dictionary in _targets.duplicate():
		var c: Control = t["ctrl"]
		if not is_instance_valid(c):
			_targets.erase(t)
			continue
		if not c.is_visible_in_tree() or not c.get_global_rect().has_point(pos):
			continue
		var rank := _panel_depth(c)
		if rank >= best_rank:
			best_rank = rank
			best = t
	return best


func _panel_depth(c: Node) -> int:
	var n: Node = c
	while n != null:
		if n is MenuPanel:
			for i in _stack.size():
				if _stack[i]["node"] == n:
					return i
			return 0
		n = n.get_parent()
	return 0


## True when `pos` lands on an open window's chrome (as opposed to the world).
func point_over_ui(pos: Vector2) -> bool:
	for e: Dictionary in _stack:
		var n: MenuPanel = e["node"]
		if is_instance_valid(n) and n.window_rect().has_point(pos):
			return true
	return false


# ============================================================== modal helpers
## `await UI.confirm("Delete save", "Slot 2 will be erased.")` -> bool.
func confirm(title: String, body: String, ok_text: String = "Confirm",
		cancel_text: String = "Cancel", danger: bool = false) -> bool:
	var p := open("confirm", {
		"mode": "confirm", "title": title, "body": body,
		"ok": ok_text, "cancel": cancel_text, "danger": danger,
	})
	if p == null or not p.has_signal(&"finished"):
		return false
	var r: Variant = await p.finished
	return r is bool and bool(r)


## Single-line text entry. Returns "" when cancelled.
func prompt(title: String, body: String, default_text: String = "",
		placeholder: String = "") -> String:
	var p := open("confirm", {
		"mode": "prompt", "title": title, "body": body,
		"text": default_text, "placeholder": placeholder,
		"ok": "OK", "cancel": "Cancel",
	})
	if p == null or not p.has_signal(&"finished"):
		return ""
	var r: Variant = await p.finished
	return String(r) if r is String else ""


## Vertical list of choices. Returns the chosen index, or -1.
func choose(title: String, body: String, choices: PackedStringArray) -> int:
	var p := open("confirm", {
		"mode": "choose", "title": title, "body": body, "choices": choices,
		"cancel": "Cancel",
	})
	if p == null or not p.has_signal(&"finished"):
		return -1
	var r: Variant = await p.finished
	return int(r) if r is int else -1


# ================================================================== settings
## Read a setting. Unknown keys fall back to `fallback`, then to the built-in
## default, so callers in other modules never have to special-case a fresh
## install.
func get_setting(key: String, fallback: Variant = null) -> Variant:
	if settings.has(key):
		return settings[key]
	if DEFAULT_SETTINGS.has(key):
		return DEFAULT_SETTINGS[key]
	return fallback


## Write a setting, apply its side effect and persist it.
func set_setting(key: String, value: Variant, persist: bool = true) -> void:
	settings[key] = value
	_apply_setting(key, value)
	setting_changed.emit(key, value)
	if persist:
		save_settings()


func _load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for section: String in cfg.get_sections():
		if section == "input":
			continue
		for k: String in cfg.get_section_keys(section):
			settings["%s/%s" % [section, k]] = cfg.get_value(section, k)
	if cfg.has_section("input"):
		for action: String in cfg.get_section_keys("input"):
			_apply_saved_binding(StringName(action), cfg.get_value("input", action, []))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in settings:
		var parts := key.split("/", true, 1)
		if parts.size() == 2:
			cfg.set_value(parts[0], parts[1], settings[key])
	for action: StringName in _default_binds:
		var current := _encode_events(InputMap.action_get_events(action))
		if current != _default_binds[action]:
			cfg.set_value("input", String(action), current)
	cfg.save(SETTINGS_PATH)


## Push every setting into the engine. Called once at boot and by the options
## menu after a "reset to defaults".
func apply_all_settings() -> void:
	for key: String in settings:
		_apply_setting(key, settings[key])


func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"video/window_mode":
			if DisplayServer.get_name() == "headless":
				return
			var mode := int(value)
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if mode == 2 else DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == 1)
		"video/resolution":
			var i := clampi(int(value), 0, RESOLUTIONS.size() - 1)
			if int(get_setting("video/window_mode", 0)) == 0 and DisplayServer.get_name() != "headless":
				DisplayServer.window_set_size(RESOLUTIONS[i])
		"video/vsync":
			DisplayServer.window_set_vsync_mode(clampi(int(value), 0, 3))
		"video/msaa":
			var vp := get_viewport()
			if vp != null:
				vp.msaa_3d = clampi(int(value), 0, 3)
		"video/ui_scale":
			var w := get_window()
			if w != null:
				w.content_scale_factor = clampf(float(value), 0.75, 2.0)
		"audio/master", "audio/music", "audio/sfx", "audio/ambient":
			_apply_bus(key.get_slice("/", 1), float(value))
		_:
			pass


func _apply_bus(bus: String, linear: float) -> void:
	var db := -80.0 if linear <= 0.001 else linear_to_db(clampf(linear, 0.0, 1.0))
	var audio := get_tree().root.get_node_or_null(^"Audio") if get_tree() != null else null
	if audio != null and audio.has_method(&"set_bus_volume"):
		audio.call(&"set_bus_volume", bus, db)
	var idx := AudioServer.get_bus_index(bus.capitalize())
	if idx < 0:
		idx = AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)


# ------------------------------------------------------------------ rebinding
func _snapshot_default_binds() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		_default_binds[action] = _encode_events(InputMap.action_get_events(action))


## Actions the controls tab offers, in display order.
func rebindable_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for a: StringName in [&"move_left", &"move_right", &"move_up", &"move_down",
			&"jump", &"flip_left", &"flip_right", &"depth_in", &"depth_out",
			&"primary", &"secondary", &"interact", &"inventory", &"crafting",
			&"quests", &"starmap", &"tech_action", &"pause", &"quick_save"]:
		if InputMap.has_action(a):
			out.append(a)
	return out


## Replace every binding of `action` with `event`, then persist.
func rebind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action) or event == null:
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	save_settings()


## Restore one action (or all, when `action` is empty) to the project default.
func reset_binding(action: StringName = &"") -> void:
	for a: StringName in _default_binds:
		if action != &"" and a != action:
			continue
		InputMap.action_erase_events(a)
		for e: InputEvent in _decode_events(_default_binds[a]):
			InputMap.action_add_event(a, e)
	save_settings()


func _apply_saved_binding(action: StringName, encoded: Variant) -> void:
	if not InputMap.has_action(action) or not (encoded is Array):
		return
	var events := _decode_events(encoded as Array)
	if events.is_empty():
		return
	InputMap.action_erase_events(action)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)


static func _encode_events(events: Array[InputEvent]) -> Array:
	var out: Array = []
	for e: InputEvent in events:
		if e is InputEventKey:
			var k := e as InputEventKey
			out.append("key:%d" % (k.physical_keycode if k.physical_keycode != 0 else k.keycode))
		elif e is InputEventMouseButton:
			out.append("mouse:%d" % (e as InputEventMouseButton).button_index)
		elif e is InputEventJoypadButton:
			out.append("pad:%d" % (e as InputEventJoypadButton).button_index)
		elif e is InputEventJoypadMotion:
			var m := e as InputEventJoypadMotion
			out.append("axis:%d:%d" % [m.axis, signi(int(m.axis_value))])
	return out


static func _decode_events(encoded: Array) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for raw: Variant in encoded:
		var parts := String(raw).split(":")
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


# ============================================================== event bridges
func _on_station_opened(station_id: String, node: Node) -> void:
	# Containers show two grids; every other station is a crafting bench.
	var is_container := false
	if node != null:
		is_container = node.has_method(&"slot") or node.has_method(&"container_size") \
			or node.get(&"inventory") != null or node.is_in_group(&"containers")
	if is_container:
		open("container", {"station_id": station_id, "node": node})
	else:
		open("crafting", {"station_id": station_id, "node": node})


func _on_dialogue_started(npc: Node, tree_id: String) -> void:
	open("dialogue", {"npc": npc, "tree_id": tree_id})


func _on_dialogue_ended() -> void:
	close("dialogue")


func _on_player_died(cause: String) -> void:
	close_all()
	open("death", {"cause": cause})
