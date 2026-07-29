## Chest / machine window: the container's slots on top, the player's backpack
## underneath, and the four transfer verbs every sandbox needs.
##
## Opened automatically by [UI] when `Events.station_opened` fires with a node
## that looks like storage. The node itself is wrapped by
## [MenuInventoryAdapter], so a container that exposes nothing but
## `slot`/`set_slot` works, and one that has not been written yet still opens
## as an empty (local) chest instead of crashing.
extends MenuPanel

const COLUMNS := 10

var _store: MenuInventoryAdapter = null
var _bag: MenuInventoryAdapter = null
var _store_grid: MenuSlotGrid = null
var _bag_hotbar: MenuSlotGrid = null
var _bag_grid: MenuSlotGrid = null
var _node: Node = null


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.35
	placement = "center"
	anim = "scale"
	group = "gameplay"


## Accepts two calling conventions:
##   * `UI.open("container", {"container": ItemContainer, "title": ..,
##      "capacity": ..})` — what `objects/types/containers.gd` sends;
##   * `{"station_id": .., "node": ..}` — what `Events.station_opened` produces.
func _build() -> void:
	var source: Object = ctx.get("container")
	if source == null:
		source = ctx.get("node")
	if source == null:
		source = ctx.get("object")
	_node = source as Node
	var station := String(ctx.get("station_id", "container"))
	var title := String(ctx.get("title", ""))
	if title == "":
		title = _title_for(station)
	var capacity := int(ctx.get("capacity", ctx.get("slots", ctx.get("size", 24))))

	_store = MenuInventoryAdapter.wrap(source, capacity, title, "container")
	_bag = MenuInventoryAdapter.player()

	var body := frame(title, Vector2(780, 560))

	body.add_child(MenuWidgets.label(title.to_upper(), &"TinyLabel"))
	_store_grid = MenuSlotGrid.new()
	_store_grid.setup(_store, 0, _store.count(), COLUMNS, "grid")
	_store_grid.transfer_to = _bag
	var store_scroll := MenuWidgets.scroll(_store_grid)
	store_scroll.custom_minimum_size = Vector2(0, 160)
	body.add_child(MenuWidgets.well(store_scroll))

	body.add_child(_toolbar())
	body.add_child(MenuWidgets.rule())

	body.add_child(MenuWidgets.label("INVENTORY", &"TinyLabel"))
	_bag_hotbar = MenuSlotGrid.new()
	_bag_hotbar.setup(_bag, 0, mini(10, _bag.count()), COLUMNS, "hotbar")
	_bag_hotbar.transfer_to = _store
	body.add_child(_bag_hotbar)

	_bag_grid = MenuSlotGrid.new()
	_bag_grid.setup(_bag, mini(10, _bag.count()), _bag.count(), COLUMNS, "grid")
	_bag_grid.transfer_to = _store
	var bag_scroll := MenuWidgets.scroll(_bag_grid)
	bag_scroll.custom_minimum_size = Vector2(0, 170)
	body.add_child(bag_scroll)

	body.add_child(MenuWidgets.label(
		"Shift-click moves a stack across. Drag to place it exactly.", &"TinyLabel"))

	if not Events.inventory_changed.is_connected(_refresh):
		Events.inventory_changed.connect(_refresh)


func _on_close() -> void:
	if Events.inventory_changed.is_connected(_refresh):
		Events.inventory_changed.disconnect(_refresh)
	if _node != null and _node.has_method(&"on_container_closed"):
		_node.call(&"on_container_closed")


func _title_for(station: String) -> String:
	if _node != null:
		for getter: StringName in [&"display_name", &"container_name"]:
			if _node.has_method(getter):
				return String(_node.call(getter))
		var n: Variant = _node.get(&"display_name")
		if n != null and String(n) != "":
			return String(n)
	return station.capitalize() if station != "" else "Container"


func _toolbar() -> Control:
	var r := MenuWidgets.row()
	var take_all := MenuWidgets.button("Take All", _take_all)
	MenuWidgets.tip(take_all, "Move everything here into your backpack.")
	r.add_child(take_all)

	var quick := MenuWidgets.button("Quick Stack", _quick_stack)
	MenuWidgets.tip(quick, "Top up stacks the container already holds.")
	r.add_child(quick)

	var deposit := MenuWidgets.button("Deposit All", _deposit_all)
	MenuWidgets.tip(deposit, "Move your whole backpack in, except the hotbar.")
	r.add_child(deposit)

	r.add_child(MenuWidgets.spacer())
	r.add_child(MenuWidgets.button("Sort", func() -> void:
		_store.sort()
		_refresh()))
	return r


# -------------------------------------------------------------------- verbs
func _take_all() -> void:
	var moved := 0
	for i in _store.count():
		var s := _store.at(i).duplicate_stack()
		if s.is_empty():
			continue
		moved += _bag.add(s)
		_store.put_at(i, s if not s.is_empty() else ItemStack.empty())
	_refresh()
	Events.toast("Took %d items." % moved if moved > 0 else "Nothing to take.", "info")


func _deposit_all() -> void:
	var moved := 0
	for i in range(mini(10, _bag.count()), _bag.count()):
		var s := _bag.at(i).duplicate_stack()
		if s.is_empty():
			continue
		moved += _store.add(s)
		_bag.put_at(i, s if not s.is_empty() else ItemStack.empty())
	_refresh()
	Events.toast("Stored %d items." % moved if moved > 0 else "Container is full.", "info")


## Only move items the container already has some of — the classic "tidy up
## without losing my tools" verb.
func _quick_stack() -> void:
	var wanted := {}
	for i in _store.count():
		var s := _store.at(i)
		if not s.is_empty():
			wanted[s.id] = true
	var moved := 0
	for i in range(mini(10, _bag.count()), _bag.count()):
		var s := _bag.at(i).duplicate_stack()
		if s.is_empty() or not wanted.has(s.id):
			continue
		moved += _store.add(s)
		_bag.put_at(i, s if not s.is_empty() else ItemStack.empty())
	_refresh()
	Events.toast("Quick-stacked %d items." % moved, "info")


func _refresh() -> void:
	if _store_grid != null:
		_store_grid.refresh()
	if _bag_hotbar != null:
		_bag_hotbar.refresh()
	if _bag_grid != null:
		_bag_grid.refresh()


func _default_focus() -> Control:
	return _store_grid.slot_at(0) if _store_grid != null else null
