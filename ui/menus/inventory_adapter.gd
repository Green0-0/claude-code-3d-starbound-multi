## A thin, defensive shim over "something that holds [ItemStack]s".
##
## The inventory model itself belongs to another agent (`inventory/`, class
## `Inventory`), and containers belong to a third (`objects/`). Neither may
## exist yet, and neither is guaranteed to expose exactly the method names the
## architecture document lists. Every menu that shows items therefore goes
## through this adapter, which:
##
## * calls the real object when it can (`slot`, `set_slot`, `swap`, `split_to`,
##   `quick_move`, `equipped`, `equip`, `sort`),
## * falls back to an in-memory array of stacks otherwise, so the inventory,
##   crafting and container windows are fully interactive during development,
## * and never, ever crashes because a method was missing.
##
## [method is_real] tells the UI which of the two it got, so it can show an
## honest "preview data" banner instead of pretending.
class_name MenuInventoryAdapter
extends RefCounted

const DEFAULT_SIZE := 40
const EQUIP_SLOTS: Array[StringName] = [
	ItemType.SLOT_HEAD, ItemType.SLOT_CHEST, ItemType.SLOT_LEGS, ItemType.SLOT_BACK,
]

## The wrapped model, or null when running on the local fallback.
var model: Object = null
## Human name for the window title ("Backpack", "Storage Locker"...).
var title: String = "Inventory"
## Logical id copied into every drag payload that starts here.
var source_id: String = "player"

var _local: Array[ItemStack] = []
var _local_equip: Dictionary = {}
var _size: int = DEFAULT_SIZE

static var _player_preview: MenuInventoryAdapter = null


## Adapter for the player's backpack. Reuses one preview instance so the fake
## contents survive closing and reopening the window.
static func player() -> MenuInventoryAdapter:
	var g := Engine.get_main_loop() as SceneTree
	var inv: Object = null
	if g != null and g.root != null:
		var game := g.root.get_node_or_null(^"Game")
		var p := (game.get(&"player") if game != null else null) as Node
		if p != null:
			inv = p.get(&"inventory")
	if inv != null:
		var a := MenuInventoryAdapter.new()
		a.model = inv
		a.source_id = "player"
		a.title = "Inventory"
		return a
	if _player_preview == null:
		_player_preview = MenuInventoryAdapter.new()
		_player_preview.source_id = "player"
		_player_preview.title = "Inventory"
		_player_preview._seed_preview()
	return _player_preview


## Adapter for an arbitrary container node. Accepts either a node that *is* the
## storage (has `slot`/`set_slot`) or one that owns an `inventory` property.
static func wrap(node: Object, fallback_size: int = 24,
		p_title: String = "Container", p_source: String = "container") -> MenuInventoryAdapter:
	var a := MenuInventoryAdapter.new()
	a._size = fallback_size
	a.title = p_title
	a.source_id = p_source
	if node != null:
		if node.has_method(&"slot") and node.has_method(&"set_slot"):
			a.model = node
		else:
			var inner: Object = node.get(&"inventory")
			if inner != null and inner.has_method(&"slot"):
				a.model = inner
	if a.model == null:
		a._local.resize(fallback_size)
	return a


func is_real() -> bool:
	return model != null


# ------------------------------------------------------------------- capacity
func count() -> int:
	if model != null:
		# `Inventory` exposes `size` as a property; `ItemContainer` exposes
		# `capacity()` / `container_size()` as methods. Try both shapes.
		for getter: StringName in [&"capacity", &"container_size", &"slot_count"]:
			if model.has_method(getter):
				return maxi(0, int(model.call(getter)))
		for prop: StringName in [&"size", &"slot_count", &"capacity"]:
			var v: Variant = model.get(prop)
			if v != null and (v is int or v is float):
				return maxi(0, int(v))
		var slots: Variant = model.get(&"slots")
		if slots is Array:
			return (slots as Array).size()
		return DEFAULT_SIZE
	if _local.size() != _size:
		_local.resize(_size)
	return _size


# ---------------------------------------------------------------------- slots
## Never returns null: an empty slot reads back as an empty [ItemStack].
func at(i: int) -> ItemStack:
	if i < 0:
		return ItemStack.empty()
	if model != null and model.has_method(&"slot"):
		var s: Variant = model.call(&"slot", i)
		return s as ItemStack if s is ItemStack else ItemStack.empty()
	if i >= _local.size():
		_local.resize(maxi(_size, i + 1))
	var l := _local[i]
	return l if l != null else ItemStack.empty()


func put_at(i: int, s: ItemStack) -> void:
	if i < 0:
		return
	if s == null:
		s = ItemStack.empty()
	if model != null and model.has_method(&"set_slot"):
		model.call(&"set_slot", i, s)
		Events.inventory_changed.emit()
		return
	if i >= _local.size():
		_local.resize(maxi(_size, i + 1))
	_local[i] = s
	Events.inventory_changed.emit()


func swap(a: int, b: int) -> void:
	if model != null and model.has_method(&"swap"):
		model.call(&"swap", a, b)
		Events.inventory_changed.emit()
		return
	var sa := at(a)
	put_at(a, at(b))
	put_at(b, sa)


## Move `n` items from slot `from` into slot `to`.
func split_to(from: int, to: int, n: int) -> void:
	if model != null and model.has_method(&"split_to"):
		model.call(&"split_to", from, to, n)
		Events.inventory_changed.emit()
		return
	var src := at(from).duplicate_stack()
	var part := src.split(n)
	if part.is_empty():
		return
	put_at(from, src)
	var dst := at(to).duplicate_stack()
	if dst.is_empty():
		put_at(to, part)
	elif dst.can_merge_with(part):
		dst.merge_from(part)
		put_at(to, dst)
		if not part.is_empty():
			put_at(from, _merge_back(src, part))


func _merge_back(base: ItemStack, extra: ItemStack) -> ItemStack:
	if base.is_empty():
		return extra
	base.merge_from(extra)
	return base


## Shift-click behaviour: bounce the stack between backpack and hotbar, or into
## whichever other container the owning window has opened.
func quick_move(i: int) -> bool:
	if model != null and model.has_method(&"quick_move"):
		var r: Variant = model.call(&"quick_move", i)
		Events.inventory_changed.emit()
		return not (r is bool) or bool(r)
	var s := at(i).duplicate_stack()
	if s.is_empty():
		return false
	var n := count()
	var hotbar := mini(10, n)
	var lo := 0
	var hi := n
	if i < hotbar:
		lo = hotbar
	else:
		hi = hotbar
	for j in range(lo, hi):
		var dst := at(j).duplicate_stack()
		if dst.is_empty():
			put_at(i, ItemStack.empty())
			put_at(j, s)
			return true
		if dst.can_merge_with(s):
			dst.merge_from(s)
			put_at(j, dst)
			put_at(i, s if not s.is_empty() else ItemStack.empty())
			if s.is_empty():
				return true
	return false


func sort() -> void:
	if model != null and model.has_method(&"sort"):
		model.call(&"sort")
		Events.inventory_changed.emit()
		return
	var items: Array[ItemStack] = []
	for i in count():
		var s := at(i)
		if not s.is_empty():
			items.append(s.duplicate_stack())
	items.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		var ta := a.type()
		var tb := b.type()
		var ka: int = ta.kind if ta != null else 0
		var kb: int = tb.kind if tb != null else 0
		if ka != kb:
			return ka < kb
		if a.id != b.id:
			return String(a.id) < String(b.id)
		return a.count > b.count)
	# Compact equal stacks while writing back.
	var out: Array[ItemStack] = []
	for s: ItemStack in items:
		if not out.is_empty() and out[-1].can_merge_with(s):
			out[-1].merge_from(s)
			if s.is_empty():
				continue
		out.append(s)
	for i in count():
		put_at(i, out[i] if i < out.size() else ItemStack.empty())


# ----------------------------------------------------------------- equipment
## The slot names the model actually has, in its own order. `Inventory`
## publishes them through `equipment()`; anything else falls back to the four
## armour slots.
func equip_slots() -> Array[StringName]:
	var out: Array[StringName] = []
	if model != null and model.has_method(&"equipment"):
		var eq: Variant = model.call(&"equipment")
		if eq is Dictionary:
			for k: Variant in (eq as Dictionary):
				out.append(StringName(k))
	if out.is_empty() and model != null:
		var v: Variant = model.get(&"equip_slots")
		if v is Array:
			for e: Variant in (v as Array):
				out.append(StringName(e))
	if out.is_empty():
		out.assign(EQUIP_SLOTS)
	return out


func equipped(slot_name: StringName) -> ItemStack:
	if model != null and model.has_method(&"equipped"):
		var s: Variant = model.call(&"equipped", slot_name)
		return s as ItemStack if s is ItemStack else ItemStack.empty()
	var l: Variant = _local_equip.get(slot_name)
	return l as ItemStack if l is ItemStack else ItemStack.empty()


## Is `s` legal in `slot_name`? Delegates to the model when it knows better —
## `Inventory.can_equip` understands hand slots and augments, which a naive
## armor_slot comparison does not.
func can_equip(slot_name: StringName, s: ItemStack) -> bool:
	if model != null and model.has_method(&"can_equip"):
		return bool(model.call(&"can_equip", slot_name, s))
	if s == null or s.is_empty():
		return true
	var t := s.type()
	if t == null:
		return false
	if not EQUIP_SLOTS.has(slot_name):
		return true
	return t.kind == ItemType.Kind.ARMOR \
		and (t.armor_slot == &"" or t.armor_slot == slot_name)


## Put `s` in `slot_name` and return whatever it displaced (empty when the slot
## was free). `Inventory.equip` already works this way; the local fallback
## mimics it exactly so the drag service sees identical behaviour either way.
func equip_swap(slot_name: StringName, s: ItemStack) -> ItemStack:
	if s == null:
		s = ItemStack.empty()
	if model != null and model.has_method(&"equip"):
		var old: Variant = model.call(&"equip", slot_name, s)
		Events.inventory_changed.emit()
		if old is ItemStack:
			# A refusal returns the same object straight back.
			if old == s:
				return null
			return old as ItemStack
		return ItemStack.empty()
	var prev := equipped(slot_name)
	_local_equip[slot_name] = s
	Events.inventory_changed.emit()
	return prev


## Convenience wrapper for callers that do not care about the displaced stack.
func equip(slot_name: StringName, s: ItemStack) -> void:
	equip_swap(slot_name, s)


# ------------------------------------------------------------------- queries
func count_of(id: StringName) -> int:
	if model != null and model.has_method(&"count_of"):
		return int(model.call(&"count_of", id))
	var total := 0
	for i in count():
		var s := at(i)
		if s.id == id:
			total += s.count
	return total


## Insert as much of `s` as fits; `s` is decremented in place. Returns how many
## items were accepted.
func add(s: ItemStack) -> int:
	if s == null or s.is_empty():
		return 0
	var before := s.count
	if model != null:
		for adder: StringName in [&"add", &"add_item", &"insert"]:
			if model.has_method(adder):
				var r: Variant = model.call(adder, s)
				Events.inventory_changed.emit()
				if r is int:
					return int(r)
				return before - s.count
	var n := count()
	for i in n:                      # merge into partial stacks first
		var dst := at(i).duplicate_stack()
		if not dst.is_empty() and dst.can_merge_with(s):
			dst.merge_from(s)
			put_at(i, dst)
			if s.is_empty():
				return before
	for i in n:
		if at(i).is_empty():
			var moved := s.split(s.count)
			put_at(i, moved)
			return before - s.count
	return before - s.count


## Remove up to `n` of `id`. Returns how many were actually removed.
func remove(id: StringName, n: int) -> int:
	if model != null and model.has_method(&"remove"):
		return int(model.call(&"remove", id, n))
	var left := n
	for i in count():
		if left <= 0:
			break
		var s := at(i)
		if s.id != id or s.is_empty():
			continue
		var take := mini(left, s.count)
		var copy := s.duplicate_stack()
		copy.count -= take
		if copy.count <= 0:
			copy.clear()
		put_at(i, copy)
		left -= take
	return n - left


func first_empty() -> int:
	for i in count():
		if at(i).is_empty():
			return i
	return -1


# --------------------------------------------------------------------- preview
## Fill the fallback with a handful of genuinely registered items so the
## inventory window is explorable before the inventory module lands. Only ever
## touches local storage — the real game state is never invented.
func _seed_preview() -> void:
	_local.resize(_size)
	if Items == null:
		return
	var order: Variant = Items.get(&"order")
	if not (order is Array):
		return
	var ids: Array = order as Array
	if ids.is_empty():
		return
	var wanted := mini(14, ids.size())
	var stride := maxf(1.0, float(ids.size()) / float(wanted))
	for i in wanted:
		var id: StringName = StringName(ids[mini(ids.size() - 1, int(i * stride))])
		var t: ItemType = Items.get_type(id)
		if t == null:
			continue
		var n: int = mini(t.stack_size, 1 + (i * 7) % 40)
		_local[i] = Items.make(id, n) if Items.has_method(&"make") else ItemStack.new(id, n)
