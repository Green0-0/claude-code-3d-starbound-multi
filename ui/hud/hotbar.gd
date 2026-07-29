## Ten-slot hotbar, bottom-centre. Everything is drawn: no textures required.
##
## Slots show the item icon (`Atlas.item_icon()` when the renderer provides one,
## a procedural coloured shape otherwise), the stack count, a durability arc, a
## rarity-coloured border from `Const.RARITY_COLORS`, an animated selection
## highlight and a cooldown sweep.
##
## Consumes: `inventory_changed`, `hotbar_selection_changed`, `item_used`.
## The inventory model is owned by another agent, so every read goes through
## `_read_slots()`, which probes a list of plausible method names and property
## names and quietly yields ten empty slots when none of them exist.
class_name HudHotbar
extends Control

const SLOTS := 10
const SLOT_MAX := 52.0
const SLOT_GAP := 4.0
const NAME_LIFE := 2.6

## Method names we will accept on the inventory for reading one hotbar slot.
const SLOT_GETTERS: Array[StringName] = [
	&"hotbar_stack", &"get_hotbar_stack", &"hotbar_slot", &"get_hotbar_slot",
	&"stack_at", &"get_stack", &"get_slot", &"slot_at",
]
## ...and for reading the whole hotbar in one go.
const ARRAY_GETTERS: Array[StringName] = [&"hotbar_stacks", &"get_hotbar", &"hotbar_slots"]
## ...and for pushing the selection back into the model.
const SELECT_SETTERS: Array[StringName] = [
	&"select_hotbar", &"set_hotbar_index", &"set_selected_slot", &"set_selected", &"select",
]

var _selected := 0
var _sel_t := 1.0                       ## 0..1 pop animation on the selection
var _sel_x := -1.0                      ## eased x of the highlight, for the slide
var _poll_accum := 0.0
var _name_t := 999.0                    ## age of the "item name" label
var _stacks: Array = []                 ## Array[ItemStack|null], length SLOTS
var _cooldowns: Array[float] = []
var _cooldown_len: Array[float] = []
var _pop: Array[float] = []             ## per-slot pop when its contents change
var _last_ids: Array[StringName] = []
var _last_counts: Array[int] = []
var _time := 0.0
var _dirty := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stacks.resize(SLOTS)
	_cooldowns.resize(SLOTS)
	_cooldown_len.resize(SLOTS)
	_pop.resize(SLOTS)
	_last_ids.resize(SLOTS)
	_last_counts.resize(SLOTS)
	for i in SLOTS:
		_cooldowns[i] = 0.0
		_cooldown_len[i] = 1.0
		_pop[i] = 0.0
		_last_ids[i] = &""
		_last_counts[i] = 0
	Events.inventory_changed.connect(func() -> void: _dirty = true)
	Events.hotbar_selection_changed.connect(_on_selection_changed)
	Events.item_used.connect(_on_item_used)


# ------------------------------------------------------------- inventory read
func _inventory() -> Object:
	var p := Game.player
	if p == null:
		return null
	var inv: Variant = p.get(&"inventory")
	return inv as Object


## Ten stacks or nulls. Never throws, whatever the inventory turns out to be.
func _read_slots() -> void:
	for i in SLOTS:
		_stacks[i] = null
	var inv := _inventory()
	if inv == null:
		return

	for m: StringName in ARRAY_GETTERS:
		if inv.has_method(m):
			var arr: Variant = inv.call(m)
			if arr is Array:
				var a: Array = arr
				for i in mini(SLOTS, a.size()):
					_stacks[i] = _coerce(a[i])
				return

	var per_slot := &""
	for m: StringName in SLOT_GETTERS:
		if inv.has_method(m):
			per_slot = m
			break
	if per_slot != &"":
		for i in SLOTS:
			_stacks[i] = _coerce(inv.call(per_slot, i))
		return

	# Last resort: a plain array property.
	for prop: StringName in [&"hotbar", &"slots", &"items"]:
		var v: Variant = inv.get(prop)
		if v is Array:
			var a2: Array = v
			for i in mini(SLOTS, a2.size()):
				_stacks[i] = _coerce(a2[i])
			return


## Accept an ItemStack, a serialised dictionary, or nothing at all.
func _coerce(v: Variant) -> ItemStack:
	if v is ItemStack:
		var st: ItemStack = v
		return null if st.is_empty() else st
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("id"):
			var st2 := ItemStack.from_dict(d)
			return null if st2.is_empty() else st2
	return null


func _selected_from_model() -> int:
	var inv := _inventory()
	if inv == null:
		return -1
	for prop: StringName in [&"selected", &"selected_slot", &"hotbar_index", &"active_slot"]:
		var v: Variant = inv.get(prop)
		if v is int:
			return int(v)
	return -1


# -------------------------------------------------------------------- signals
func _on_selection_changed(index: int) -> void:
	_apply_selection(index, true)


func _on_item_used(item_id: String) -> void:
	for i in SLOTS:
		var st: ItemStack = _stacks[i]
		if st != null and String(st.id) == item_id:
			var speed := 1.0
			var t := st.type()
			if t != null and t.attack_speed > 0.0:
				speed = t.attack_speed
			_cooldown_len[i] = clampf(1.0 / speed, 0.05, 8.0)
			_cooldowns[i] = _cooldown_len[i]
			_pop[i] = 1.0
			return


func _apply_selection(index: int, from_model: bool) -> void:
	var i := wrapi(index, 0, SLOTS)
	if i == _selected and from_model:
		return
	_selected = i
	_sel_t = 0.0
	_name_t = 0.0
	if from_model:
		return
	var inv := _inventory()
	if inv != null:
		for m: StringName in SELECT_SETTERS:
			if inv.has_method(m):
				inv.call(m, i)
				return
	# Nothing owns the selection yet — be the source of truth ourselves.
	Events.hotbar_selection_changed.emit(i)


# ---------------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if Game.paused or _captured():
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_selection(_selected + 1, false)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_selection(_selected - 1, false)
			get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
	if code >= KEY_1 and code <= KEY_9:
		_apply_selection(code - KEY_1, false)
		get_viewport().set_input_as_handled()
	elif code == KEY_0:
		_apply_selection(9, false)
		get_viewport().set_input_as_handled()


func _captured() -> bool:
	return UI != null and UI.has_method(&"captures_input") and UI.captures_input()


# -------------------------------------------------------------------- updating
func _process(delta: float) -> void:
	_time += delta
	_poll_accum += delta
	if _dirty or _poll_accum > 0.5:
		# The poll is a cheap safety net for inventories that mutate silently.
		_dirty = false
		_poll_accum = 0.0
		_read_slots()
		_detect_changes()

	var model_sel := _selected_from_model()
	if model_sel >= 0 and model_sel != _selected:
		_apply_selection(model_sel, true)

	_sel_t = minf(1.0, _sel_t + delta * 4.5)
	_name_t += delta
	for i in SLOTS:
		if _cooldowns[i] > 0.0:
			_cooldowns[i] = maxf(0.0, _cooldowns[i] - delta)
		_pop[i] = maxf(0.0, _pop[i] - delta * 3.0)
	queue_redraw()


func _detect_changes() -> void:
	for i in SLOTS:
		var st: ItemStack = _stacks[i]
		var id: StringName = st.id if st != null else &""
		var n: int = st.count if st != null else 0
		if id != _last_ids[i] or n != _last_counts[i]:
			if id != &"":
				_pop[i] = 1.0
			_last_ids[i] = id
			_last_counts[i] = n


# --------------------------------------------------------------------- layout
func _slot_size() -> float:
	var avail := size.x - SLOT_GAP * float(SLOTS - 1)
	return clampf(avail / float(SLOTS), 24.0, SLOT_MAX)


func _slot_rect(i: int) -> Rect2:
	var s := _slot_size()
	var total := s * SLOTS + SLOT_GAP * (SLOTS - 1)
	var x := (size.x - total) * 0.5 + float(i) * (s + SLOT_GAP)
	return Rect2(Vector2(x, size.y - s - 4.0), Vector2(s, s))


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	var s := _slot_size()
	var first := _slot_rect(0)
	var last := _slot_rect(SLOTS - 1)
	var frame := Rect2(first.position - Vector2(6, 6),
		Vector2(last.position.x + last.size.x - first.position.x + 12.0, s + 12.0))
	HudTheme.panel(self, frame, HudTheme.BG_DEEP, HudTheme.with_alpha(HudTheme.EDGE_DIM, 0.6), 7, 1)

	# Selection highlight slides between slots instead of teleporting.
	var target := _slot_rect(_selected)
	_sel_x = target.position.x if _sel_x < 0.0 else lerpf(_sel_x, target.position.x, 0.4)
	var hl := Rect2(Vector2(_sel_x, target.position.y), target.size)
	_draw_selection(hl)

	for i in SLOTS:
		_draw_slot(i, _slot_rect(i))

	_draw_name_label(frame)


func _draw_selection(r: Rect2) -> void:
	# Grows out of the slot then settles — the "pop" that reads as a selection.
	var grow := lerpf(10.0, 4.0, HudTheme.out_cubic(_sel_t))
	var g := r.grow(grow)
	var pulse := 0.55 + 0.25 * sin(_time * 3.2)
	HudTheme.glow(self, g.position + g.size * 0.5, g.size.x * 0.95,
		HudTheme.with_alpha(HudTheme.ACCENT, 0.16 * pulse))
	HudTheme.panel(self, g, Color(0, 0, 0, 0), HudTheme.with_alpha(HudTheme.ACCENT, 0.95), 6, 2)
	# Little pointer under the selected slot.
	var c := Vector2(g.position.x + g.size.x * 0.5, g.position.y - 4.0)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-5, -5), c + Vector2(5, -5), c]), HudTheme.ACCENT)


func _draw_slot(i: int, r: Rect2) -> void:
	var st: ItemStack = _stacks[i]
	var pop: float = _pop[i]
	var rr := r.grow(pop * 2.0)

	var border := HudTheme.with_alpha(HudTheme.EDGE_DIM, 0.7)
	if st != null:
		border = HudTheme.with_alpha(HudTheme.rarity_color(st.rarity()), 0.9)
	HudTheme.panel(self, rr, HudTheme.BG_SLOT, border, 4, 1 if st == null else 2)

	# Slot number, always visible so "press 3" is discoverable.
	HudTheme.text(self, rr.position + Vector2(3, 1), str((i + 1) % 10), 9,
		HudTheme.with_alpha(HudTheme.TEXT_FAINT, 0.9 if st == null else 0.6))

	if st != null:
		var pad := rr.size.x * 0.18
		var icon_r := Rect2(rr.position + Vector2(pad, pad), rr.size - Vector2(pad, pad) * 2.0)
		HudTheme.item_icon(self, icon_r, st.id, Color(1, 1, 1, 1))

		if st.count > 1:
			HudTheme.text(self, Vector2(rr.position.x, rr.position.y + rr.size.y - 13.0),
				str(st.count), 11, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 3.0, 1)

		_draw_durability(rr, st)

	if _cooldowns[i] > 0.0:
		var f: float = _cooldowns[i] / maxf(0.001, _cooldown_len[i])
		HudTheme.wedge(self, rr.position + rr.size * 0.5, rr.size.x * 0.72, f,
			Color(0.05, 0.06, 0.10, 0.62))


func _draw_durability(r: Rect2, st: ItemStack) -> void:
	var dur := st.durability()
	if dur < 0:
		return
	var maxd := st.max_durability()
	if maxd <= 0:
		maxd = maxi(dur, 1)
	var f := clampf(float(dur) / float(maxd), 0.0, 1.0)
	var c := r.position + r.size * 0.5
	var rad := r.size.x * 0.40
	var a0 := PI * 0.16
	var a1 := PI * 0.84
	draw_arc(c, rad, a0, a1, 16, Color(0.02, 0.03, 0.05, 0.8), 4.0, true)
	var col := Color(0.9, 0.25, 0.2).lerp(Color(0.35, 0.9, 0.4), f)
	draw_arc(c, rad, a0, lerpf(a0, a1, f), 16, col, 3.0, true)


func _draw_name_label(frame: Rect2) -> void:
	if _name_t > NAME_LIFE:
		return
	var st: ItemStack = _stacks[_selected]
	if st == null:
		return
	var a := clampf((NAME_LIFE - _name_t) / 0.5, 0.0, 1.0)
	var name_text := st.display_name()
	var col := HudTheme.rarity_color(st.rarity())
	var sz := HudTheme.text_size(name_text, 13)
	var pos := Vector2(size.x * 0.5, frame.position.y - 24.0)
	var box := Rect2(pos - Vector2(sz.x * 0.5 + 8.0, 2.0), sz + Vector2(16.0, 5.0))
	HudTheme.panel(self, box, HudTheme.with_alpha(HudTheme.BG_DEEP, 0.8 * a),
		HudTheme.with_alpha(col, 0.6 * a), 4, 1)
	HudTheme.text(self, Vector2(pos.x - sz.x * 0.5, pos.y), name_text, 13,
		HudTheme.with_alpha(col, a))
	if st.rarity() > 0:
		var rname: String = Const.RARITY_NAMES[clampi(st.rarity(), 0, 4)]
		var rsz := HudTheme.text_size(rname, 9)
		HudTheme.text(self, Vector2(pos.x - rsz.x * 0.5, box.position.y - 13.0), rname, 9,
			HudTheme.with_alpha(col, a * 0.8))
