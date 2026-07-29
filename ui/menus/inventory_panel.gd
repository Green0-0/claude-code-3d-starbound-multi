## The backpack: hotbar row, main grid, equipment paper-doll, a live character
## summary and a trash slot.
##
## All item movement goes through [MenuSlotGrid] and the [UI] drag service, so
## the exact same gestures work here, in a chest, and in the crafting window.
## The data itself is read through [MenuInventoryAdapter], which degrades to a
## local preview when `Game.player.inventory` does not exist yet.
extends MenuPanel

const COLUMNS := 10
const HOTBAR := 10

var _inv: MenuInventoryAdapter = null
var _hotbar_grid: MenuSlotGrid = null
var _main_grid: MenuSlotGrid = null
var _equip_slots: Dictionary = {}      ## StringName -> MenuItemSlot
var _stats_box: VBoxContainer = null


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.35
	placement = "center"
	anim = "scale"
	group = "gameplay"


func _build() -> void:
	_inv = MenuInventoryAdapter.player()
	var body := frame("Inventory", Vector2(900, 560))

	if not _inv.is_real():
		body.add_child(_preview_banner())

	var columns := MenuWidgets.row(MenuTheme.GAP + 4)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	var left := MenuWidgets.col()
	left.custom_minimum_size = Vector2(268, 0)
	columns.add_child(left)
	left.add_child(MenuWidgets.card(_paper_doll()))
	_stats_box = MenuWidgets.col(2)
	left.add_child(MenuWidgets.card(_stats_box))
	left.add_child(MenuWidgets.spacer())

	var right := MenuWidgets.col()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_toolbar())
	right.add_child(_labelled("Hotbar", _make_hotbar()))
	right.add_child(MenuWidgets.rule())
	right.add_child(_labelled("Backpack", _make_main_grid()))
	right.add_child(MenuWidgets.spacer())
	right.add_child(_bottom_row())

	if not Events.inventory_changed.is_connected(_refresh):
		Events.inventory_changed.connect(_refresh)
	_refresh()


func _on_close() -> void:
	if Events.inventory_changed.is_connected(_refresh):
		Events.inventory_changed.disconnect(_refresh)


func _preview_banner() -> Control:
	var p := PanelContainer.new()
	var sb := MenuTheme.flat(Color(MenuTheme.WARN.r, MenuTheme.WARN.g, MenuTheme.WARN.b, 0.10),
		MenuTheme.RADIUS_SM, MenuTheme.PAD_SM)
	sb.set_border_width_all(1)
	sb.border_color = Color(MenuTheme.WARN.r, MenuTheme.WARN.g, MenuTheme.WARN.b, 0.45)
	p.add_theme_stylebox_override(&"panel", sb)
	p.add_child(MenuWidgets.label(
		"Preview data — the inventory module has not attached to the player yet.",
		&"TinyLabel"))
	return p


func _labelled(text: String, child: Control) -> Control:
	var c := MenuWidgets.col(4)
	c.add_child(MenuWidgets.label(text.to_upper(), &"TinyLabel"))
	c.add_child(child)
	return c


# ------------------------------------------------------------------- toolbar
func _toolbar() -> Control:
	var r := MenuWidgets.row()
	var sort := MenuWidgets.button("Sort", func() -> void:
		_inv.sort()
		_refresh()
		Events.toast("Inventory sorted.", "info"))
	MenuWidgets.tip(sort, "Group by kind, then merge partial stacks.")
	r.add_child(sort)

	var stack_up := MenuWidgets.button("Merge Stacks", func() -> void:
		_merge_partials()
		_refresh())
	MenuWidgets.tip(stack_up, "Combine partial stacks of the same item.")
	r.add_child(stack_up)

	r.add_child(MenuWidgets.spacer())
	var hint := MenuWidgets.label(
		"drag · right-click splits · shift-click quick-moves", &"TinyLabel")
	r.add_child(hint)
	return r


func _make_hotbar() -> Control:
	_hotbar_grid = MenuSlotGrid.new()
	var n := _inv.count()
	_hotbar_grid.setup(_inv, 0, mini(HOTBAR, n), COLUMNS, "hotbar")
	_hotbar_grid.slot_used.connect(func(_i: int) -> void: _refresh_stats())
	return _hotbar_grid


func _make_main_grid() -> Control:
	_main_grid = MenuSlotGrid.new()
	var n := _inv.count()
	_main_grid.setup(_inv, mini(HOTBAR, n), n, COLUMNS, "grid")
	_main_grid.slot_used.connect(func(_i: int) -> void: _refresh_stats())
	var sc := MenuWidgets.scroll(_main_grid)
	sc.custom_minimum_size = Vector2(0, 220)
	return sc


func _bottom_row() -> Control:
	var r := MenuWidgets.row()
	r.add_child(MenuWidgets.label("Drop anything outside the window to throw it away.",
		&"TinyLabel"))
	r.add_child(MenuWidgets.spacer())
	r.add_child(MenuWidgets.label("Trash", &"TinyLabel"))
	r.add_child(_trash_slot())
	return r


func _trash_slot() -> MenuItemSlot:
	var t := MenuItemSlot.new(-1, "trash")
	t.slot_kind = "trash"
	t.empty_hint = "✕"
	t.put = func(_slot: MenuItemSlot, incoming: ItemStack) -> bool:
		var name := incoming.display_name()
		var n := incoming.count
		incoming.clear()
		Events.toast("Destroyed %s x%d" % [name, n], "warn")
		return true
	MenuWidgets.tip(t, "Destroys whatever you drop here. There is no undo.")
	return t


# ---------------------------------------------------------------- paper doll
const ARMOUR_ORDER: Array[StringName] = [&"head", &"chest", &"legs", &"back"]
const SLOT_LABELS := {
	&"head": "Head", &"chest": "Chest", &"legs": "Legs", &"back": "Back",
	&"primary": "Main", &"secondary": "Off", &"augment_1": "Aug 1",
	&"augment_2": "Aug 2", &"augment_3": "Aug 3",
}


## The doll shows whatever equipment slots the model actually has: the four
## armour slots framing the silhouette, everything else (hands, augments) in a
## wrapped row underneath. That way a richer `Inventory` needs no change here.
func _paper_doll() -> Control:
	var c := MenuWidgets.col(4)
	c.add_child(MenuWidgets.label("Equipment", &"TinyLabel"))

	var available := _inv.equip_slots()
	var armour: Array[StringName] = []
	var extras: Array[StringName] = []
	for slot_name: StringName in available:
		if ARMOUR_ORDER.has(slot_name):
			armour.append(slot_name)
		else:
			extras.append(slot_name)
	if armour.is_empty():
		armour.assign(ARMOUR_ORDER)

	var row := MenuWidgets.row(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var left := MenuWidgets.col(4)
	var right := MenuWidgets.col(4)
	var split := int(ceil(armour.size() * 0.5))
	for i in armour.size():
		var target := left if i < split else right
		target.add_child(_equip(armour[i]))
	row.add_child(left)
	row.add_child(_silhouette())
	row.add_child(right)
	c.add_child(row)

	if not extras.is_empty():
		c.add_child(MenuWidgets.rule())
		c.add_child(MenuWidgets.label("Hands & augments", &"TinyLabel"))
		var grid := MenuWidgets.grid(mini(5, extras.size()))
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for slot_name: StringName in extras:
			grid.add_child(_equip(slot_name))
		c.add_child(grid)
	return c


func _equip(slot_name: StringName) -> MenuItemSlot:
	var s := MenuItemSlot.new(-1, "equip")
	s.slot_kind = "equip"
	s.equip_slot = slot_name
	s.empty_hint = String(SLOT_LABELS.get(slot_name,
		String(slot_name).capitalize().replace("_", " ")))
	s.take = func(_slot: MenuItemSlot, _amount: int) -> ItemStack:
		var old := _inv.equip_swap(slot_name, ItemStack.empty())
		if old == null or old.is_empty():
			return null
		_refresh()
		return old
	s.accepts = func(payload: Dictionary) -> bool:
		var incoming: ItemStack = payload.get("stack")
		return incoming != null and not incoming.is_empty() \
			and _inv.can_equip(slot_name, incoming)
	s.put = func(_slot: MenuItemSlot, incoming: ItemStack) -> bool:
		if not _inv.can_equip(slot_name, incoming):
			return false
		var old := _inv.equip_swap(slot_name, incoming.duplicate_stack())
		if old == null:
			return false                      # the model refused the item
		if old.is_empty():
			incoming.clear()
		else:
			# Hand the displaced item back to the cursor — the same swap
			# semantics MenuSlotGrid uses for storage slots.
			incoming.id = old.id
			incoming.count = old.count
			incoming.data = old.data.duplicate(true)
		_refresh()
		return true
	_equip_slots[slot_name] = s
	return s


## A crude Paper-Mario silhouette. Procedural, like everything else here.
func _silhouette() -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"InsetPanel"
	p.custom_minimum_size = Vector2(74, 118)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(holder)
	for piece: Array in [
			[Rect2(26, 8, 22, 22), Color(0.86, 0.72, 0.55)],     # head
			[Rect2(22, 32, 30, 40), MenuTheme.CYAN.darkened(0.35)],  # torso
			[Rect2(14, 34, 8, 30), Color(0.86, 0.72, 0.55)],     # arm
			[Rect2(52, 34, 8, 30), Color(0.86, 0.72, 0.55)],     # arm
			[Rect2(24, 74, 11, 30), MenuTheme.LINE_HI],          # leg
			[Rect2(39, 74, 11, 30), MenuTheme.LINE_HI],          # leg
		]:
		var box: Rect2 = piece[0]
		var tint: Color = piece[1]
		var r := ColorRect.new()
		r.color = tint
		r.position = box.position
		r.size = box.size
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(r)
	return p


# --------------------------------------------------------------------- stats
func _refresh() -> void:
	if _hotbar_grid != null:
		_hotbar_grid.refresh()
	if _main_grid != null:
		_main_grid.refresh()
	for slot_name: StringName in _equip_slots:
		(_equip_slots[slot_name] as MenuItemSlot).set_stack(_inv.equipped(slot_name))
	_refresh_stats()


func _refresh_stats() -> void:
	if _stats_box == null:
		return
	MenuWidgets.clear(_stats_box)
	_stats_box.add_child(MenuWidgets.label("Character", &"TinyLabel"))

	var player := Game.player
	var hp := float(player.health) if player != null else 0.0
	var hp_max := float(player.max_health) if player != null else 0.0
	if hp_max > 0.0:
		_stats_box.add_child(MenuWidgets.stat_row("Health",
			"%d / %d" % [roundi(hp), roundi(hp_max)],
			MenuTheme.GOOD if hp > hp_max * 0.4 else MenuTheme.BAD))
		_stats_box.add_child(MenuWidgets.meter(hp, hp_max, MenuTheme.BAD))

	var energy: Variant = player.get(&"energy") if player != null else null
	var energy_max: Variant = player.get(&"max_energy") if player != null else null
	if energy != null and energy_max != null and float(energy_max) > 0.0:
		_stats_box.add_child(MenuWidgets.stat_row("Energy",
			"%d / %d" % [roundi(float(energy)), roundi(float(energy_max))], MenuTheme.CYAN))
		_stats_box.add_child(MenuWidgets.meter(float(energy), float(energy_max), MenuTheme.CYAN))

	var defense := 0.0
	var bonuses := {}
	for slot_name: StringName in _inv.equip_slots():
		var s := _inv.equipped(slot_name)
		if s.is_empty():
			continue
		defense += float(s.stat("defense", 0.0))
		var b: Variant = s.stat("stat_bonuses", {})
		if b is Dictionary:
			for k: String in (b as Dictionary):
				bonuses[k] = float(bonuses.get(k, 0.0)) + float((b as Dictionary)[k])

	_stats_box.add_child(MenuWidgets.stat_row("Defense", "%.0f" % defense, MenuTheme.CYAN))

	var weapon := _best_weapon()
	_stats_box.add_child(MenuWidgets.stat_row("Attack",
		("%.1f" % float(weapon.stat("damage", 0.0))) if weapon != null else "—",
		MenuTheme.ACCENT))

	for k: String in bonuses:
		_stats_box.add_child(MenuWidgets.stat_row(k.capitalize().replace("_", " "),
			"+%.0f" % float(bonuses[k]), MenuTheme.GOOD))

	_stats_box.add_child(MenuWidgets.rule())
	_stats_box.add_child(MenuWidgets.stat_row("Plane",
		"%s (%d)" % [View.view_name(), View.view], MenuTheme.VIOLET))
	_stats_box.add_child(MenuWidgets.stat_row("Layer", str(View.layer)))
	_stats_box.add_child(MenuWidgets.stat_row("Pixels",
		MenuWidgets.short_number(float(Game.stats.get("pixels_earned", 0))), MenuTheme.WARN))


## What the player would actually swing: the main-hand slot when the model has
## one, otherwise the strongest weapon lying in the pack.
func _best_weapon() -> ItemStack:
	var hand := _inv.equipped(&"primary")
	if not hand.is_empty() and float(hand.stat("damage", 0.0)) > 0.0:
		return hand
	var best: ItemStack = null
	var best_dmg := -1.0
	for i in _inv.count():
		var s := _inv.at(i)
		if s.is_empty():
			continue
		var t := s.type()
		if t == null or t.kind != ItemType.Kind.WEAPON:
			continue
		var d := float(s.stat("damage", 0.0))
		if d > best_dmg:
			best_dmg = d
			best = s
	return best


func _merge_partials() -> void:
	var n := _inv.count()
	for i in n:
		var a := _inv.at(i).duplicate_stack()
		if a.is_empty() or a.count >= a.max_stack():
			continue
		for j in range(i + 1, n):
			var b := _inv.at(j).duplicate_stack()
			if b.is_empty() or not a.can_merge_with(b):
				continue
			a.merge_from(b)
			_inv.put_at(j, b)
			if a.count >= a.max_stack():
				break
		_inv.put_at(i, a)


func _default_focus() -> Control:
	return _hotbar_grid.slot_at(0) if _hotbar_grid != null else null
