## A rectangle of [MenuItemSlot]s bound to a [MenuInventoryAdapter].
##
## This is where the drag-and-drop contract is actually implemented for
## ordinary storage, and it is shared verbatim by the inventory window, both
## halves of the container window and any future bag/vault UI. Equipment slots
## and the crafting output use [MenuItemSlot] directly with their own callables.
##
## Take / put semantics:
## [codeblock]
##   take(slot, -1) -> the whole stack leaves the model
##   take(slot,  n) -> n items leave, the remainder is written back
##   put(slot, s)   -> empty slot : as much as one stack allows
##                     same item  : merge, `s` keeps the overflow
##                     other item : swap — `s` is rewritten to hold the
##                                  displaced stack, which the drag service
##                                  then keeps on the cursor
## [/codeblock]
class_name MenuSlotGrid
extends GridContainer

var adapter: MenuInventoryAdapter = null
## Half-open slot range this grid displays.
var first: int = 0
var last: int = 0
## Adapter that shift-click sends items to. Null => the adapter's own
## quick_move (hotbar <-> backpack).
var transfer_to: MenuInventoryAdapter = null

var _slots: Array[MenuItemSlot] = []

signal slot_used(index: int)


## Build (or rebuild) the grid. `to` is exclusive.
func setup(p_adapter: MenuInventoryAdapter, from: int, to: int, cols: int = 10,
		slot_kind: String = "grid") -> void:
	adapter = p_adapter
	first = from
	last = to
	columns = maxi(1, cols)
	add_theme_constant_override(&"h_separation", 4)
	add_theme_constant_override(&"v_separation", 4)
	for c: Node in get_children():
		c.queue_free()
	_slots.clear()
	for i in range(from, to):
		var s := MenuItemSlot.new(i, adapter.source_id)
		s.slot_kind = slot_kind
		s.take = _take
		s.put = _put
		s.activate = _activate
		add_child(s)
		_slots.append(s)
	refresh()


func refresh() -> void:
	if adapter == null:
		return
	for s: MenuItemSlot in _slots:
		s.set_stack(adapter.at(s.index))


func slot_at(index: int) -> MenuItemSlot:
	for s: MenuItemSlot in _slots:
		if s.index == index:
			return s
	return null


# ------------------------------------------------------------ drag callbacks
func _take(slot: MenuItemSlot, amount: int) -> ItemStack:
	var current := adapter.at(slot.index)
	if current.is_empty():
		return null
	var copy := current.duplicate_stack()
	if amount < 0 or amount >= copy.count:
		adapter.put_at(slot.index, ItemStack.empty())
		refresh()
		return copy
	var part := copy.split(amount)
	adapter.put_at(slot.index, copy)
	refresh()
	return part


func _put(slot: MenuItemSlot, incoming: ItemStack) -> bool:
	if incoming == null or incoming.is_empty():
		return false
	var current := adapter.at(slot.index).duplicate_stack()

	if current.is_empty():
		var room := mini(incoming.count, incoming.max_stack())
		adapter.put_at(slot.index, incoming.split(room))
		refresh()
		slot_used.emit(slot.index)
		return true

	if current.can_merge_with(incoming):
		var moved := current.merge_from(incoming)
		if moved <= 0:
			return false
		adapter.put_at(slot.index, current)
		refresh()
		slot_used.emit(slot.index)
		return true

	# Different item: swap. The displaced stack is written back into `incoming`
	# so the drag service keeps holding it — exactly like picking it up.
	if incoming.count > incoming.max_stack():
		return false
	adapter.put_at(slot.index, incoming.duplicate_stack())
	incoming.id = current.id
	incoming.count = current.count
	incoming.data = current.data.duplicate(true)
	refresh()
	slot_used.emit(slot.index)
	return true


func _activate(slot: MenuItemSlot, kind: String) -> void:
	match kind:
		"quick":
			_quick_move(slot.index)
		"use", "context":
			slot_used.emit(slot.index)


func _quick_move(index: int) -> void:
	var s := adapter.at(index)
	if s.is_empty():
		return
	if transfer_to != null:
		var moving := s.duplicate_stack()
		var moved := transfer_to.add(moving)
		if moved > 0:
			adapter.put_at(index, moving if not moving.is_empty() else ItemStack.empty())
			refresh()
		return
	if adapter.quick_move(index):
		refresh()
