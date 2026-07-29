## One inventory cell. Shared verbatim by the inventory grid, the equipment
## paper-doll, container windows, the crafting output and the trash can.
##
## The slot never owns the item — it renders whatever [member stack] currently
## points at and asks its owning panel to mutate the real model through the
## [member take] / [member put] callables. That keeps the drag-and-drop
## protocol identical no matter which module supplies the data.
##
## Interaction model (Starbound / Minecraft style):
## [codeblock]
##   left click  on a filled slot  -> pick up the whole stack (held by cursor)
##   right click on a filled slot  -> pick up half
##   left click  while holding     -> place all / merge / swap
##   right click while holding     -> place exactly one
##   drag + release on another slot-> same as click-then-click
##   shift + left click            -> quick-move (no cursor stack involved)
##   release over the world        -> spill the held stack as an item drop
## [/codeblock]
class_name MenuItemSlot
extends Control

const SIZE := MenuTheme.SLOT_SIZE

## Rendered contents. May be null or empty.
var stack: ItemStack = null
## Index of this slot inside [member source]. -1 for unindexed slots.
var index: int = -1
## Logical container id, copied into every drag payload originating here.
var source: String = "player"
## "grid" | "equip" | "hotbar" | "output" | "trash" | "recipe"
var slot_kind: String = "grid"
## Equipment slot name when `slot_kind == "equip"`.
var equip_slot: StringName = &""
## Free-form label drawn under an empty equipment slot ("Head", "Chest"...).
var empty_hint: String = ""
## Extra data merged into the drag payload (recipe id, station node, ...).
var meta_data: Dictionary = {}

## `func(slot: MenuItemSlot, amount: int) -> ItemStack`
## Remove up to `amount` items (-1 = all) and hand them over. Return null or an
## empty stack to refuse. Not set => the slot cannot be picked up from.
var take: Callable = Callable()
## `func(slot: MenuItemSlot, incoming: ItemStack) -> bool`
## Insert what fits, decrementing `incoming.count` by whatever was consumed.
## Return true if anything was taken. Not set => the slot rejects drops.
var put: Callable = Callable()
## `func(slot: MenuItemSlot, kind: String) -> void`
## kind is "use" (double click), "quick" (shift click) or "context".
var activate: Callable = Callable()
## `func(payload: Dictionary) -> bool` — extra filter on top of [member put].
var accepts: Callable = Callable()

var _hovered: bool = false
var _flash: float = 0.0

signal changed(slot: MenuItemSlot)


func _init(p_index: int = -1, p_source: String = "player") -> void:
	index = p_index
	source = p_source


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	if UI.has_method(&"register_drop_target"):
		UI.drag_started.connect(_on_drag_state)
		UI.drag_ended.connect(_on_drag_ended)


## Registration lives here rather than in `_ready` so a slot survives being
## reparented (which happens once, when the Menus layer attaches and [UI]
## migrates panels out of its private fallback canvas).
func _enter_tree() -> void:
	if UI.has_method(&"register_drop_target"):
		UI.register_drop_target(self, _can_accept, _accept)


func _exit_tree() -> void:
	if UI.has_method(&"unregister_drop_target"):
		UI.unregister_drop_target(self)


## Replace the rendered contents. Call this after mutating the backing model.
func set_stack(s: ItemStack) -> void:
	stack = s
	queue_redraw()
	changed.emit(self)


func is_empty() -> bool:
	return stack == null or stack.is_empty()


# ------------------------------------------------------------------ drag logic
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		# While a drag is live, UI._input already resolved the click.
		if UI.is_dragging():
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			if mb.shift_pressed:
				_fire_activate("quick")
			elif mb.double_click:
				_fire_activate("use")
			else:
				_pick_up(-1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			grab_focus()
			if mb.shift_pressed:
				_fire_activate("context")
			else:
				_pick_up(_half())
			accept_event()
		return
	if event.is_action_pressed(&"ui_accept"):
		if UI.is_dragging():
			UI.resolve_drop_on(self, -1)
		else:
			_pick_up(-1)
		accept_event()


func _half() -> int:
	if is_empty():
		return 0
	return maxi(1, (stack.count + 1) / 2)


func _pick_up(amount: int) -> void:
	if is_empty() or not take.is_valid():
		return
	var got: ItemStack = take.call(self, amount)
	if got == null or got.is_empty():
		return
	var payload := {
		"stack": got,
		"source": source,
		"index": index,
		"slot_kind": slot_kind,
		"equip_slot": equip_slot,
		"mode": "copy" if slot_kind == "output" else "move",
		"origin": self,
		"meta": meta_data.duplicate(),
		"return": _return_to_self,
	}
	UI.begin_drag(payload)
	queue_redraw()


## Give unconsumed items back. Bound into every payload we create; must survive
## the panel being closed mid-drag, hence the `is_inside_tree` guard.
func _return_to_self(remainder: ItemStack) -> bool:
	if remainder == null or remainder.is_empty():
		return true
	if not is_inside_tree() or not put.is_valid():
		return false
	var ok: bool = put.call(self, remainder)
	queue_redraw()
	return ok and remainder.is_empty()


func _can_accept(payload: Dictionary) -> bool:
	if not put.is_valid():
		return false
	if accepts.is_valid() and not bool(accepts.call(payload)):
		return false
	return true


func _accept(payload: Dictionary) -> bool:
	var incoming: ItemStack = payload.get("stack")
	if incoming == null or incoming.is_empty():
		return false
	var before := incoming.count
	var ok: bool = put.call(self, incoming)
	_flash = 1.0
	queue_redraw()
	return ok or incoming.count < before


func _fire_activate(kind: String) -> void:
	if activate.is_valid():
		activate.call(self, kind)


# --------------------------------------------------------------------- hover
func _on_enter() -> void:
	_hovered = true
	queue_redraw()
	if not UI.is_dragging() and not is_empty():
		UI.show_item_tooltip(stack, get_global_rect().position + Vector2(size.x + 8, 0))


func _on_exit() -> void:
	_hovered = false
	queue_redraw()
	UI.hide_tooltip()


func _on_drag_state(_payload: Dictionary) -> void:
	queue_redraw()


func _on_drag_ended(_payload: Dictionary, _accepted: bool) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.5)
		queue_redraw()


# ---------------------------------------------------------------------- paint
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var rarity := stack.rarity() if not is_empty() else -1
	MenuTheme.slot_box(rarity, _hovered).draw(get_canvas_item(), rect)

	# Valid-target highlight while something is being dragged.
	if UI.is_dragging() and _can_accept(UI.drag_payload()):
		var tint := Color(MenuTheme.GOOD.r, MenuTheme.GOOD.g, MenuTheme.GOOD.b, 0.16)
		draw_rect(rect, tint, true)
		draw_rect(rect.grow(-1.0), Color(MenuTheme.GOOD.r, MenuTheme.GOOD.g, MenuTheme.GOOD.b, 0.55), false, 1.0)

	if _flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, 0.25 * _flash), true)

	if has_focus():
		draw_rect(rect.grow(1.0), MenuTheme.ACCENT, false, 2.0)

	var font := get_theme_default_font()

	if is_empty():
		if empty_hint != "" and font != null:
			draw_string(font, Vector2(0, size.y * 0.5 + 4), empty_hint,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, MenuTheme.FS_TINY,
				Color(MenuTheme.TEXT_MUTE.r, MenuTheme.TEXT_MUTE.g, MenuTheme.TEXT_MUTE.b, 0.7))
		return

	var icon := MenuTheme.stack_icon(stack, MenuTheme.ICON_SIZE)
	if icon != null:
		var isz := Vector2(MenuTheme.ICON_SIZE, MenuTheme.ICON_SIZE)
		draw_texture_rect(icon, Rect2((size - isz) * 0.5, isz), false)

	if stack.count > 1 and font != null:
		var txt := MenuWidgets.short_number(stack.count)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			MenuTheme.FS_TINY).x
		var pos := Vector2(size.x - 3.0 - w, size.y - 4.0)
		draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			MenuTheme.FS_TINY, Color(0, 0, 0, 0.85))
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			MenuTheme.FS_TINY, MenuTheme.TEXT)

	var dur := stack.durability()
	var maxdur := stack.max_durability()
	if dur >= 0 and maxdur > 0:
		var frac := clampf(float(dur) / float(maxdur), 0.0, 1.0)
		var bar := Rect2(3, size.y - 7, size.x - 6, 3)
		draw_rect(bar, Color(0, 0, 0, 0.6), true)
		bar.size.x *= frac
		draw_rect(bar, MenuTheme.BAD.lerp(MenuTheme.GOOD, frac), true)
