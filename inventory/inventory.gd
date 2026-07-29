## The item model every actor and container in Planeshift is built on.
##
## An `Inventory` is a fixed-size array of [ItemStack] plus a set of named
## equipment slots. It is a pure model object — no nodes, no scene tree, no
## input. UI draws it, gameplay mutates it, persistence serialises it.
##
## [b]Three rules that keep callers out of trouble:[/b]
## [br]1. `slot(i)` NEVER returns null. Empty slots hold an empty [ItemStack];
##    test with `slot(i).is_empty()`. This means you can always call
##    `inv.slot(i).display_name()` without a null check.
## [br]2. `slot(i)` returns the [b]live[/b] stack. Read it freely; if you mutate
##    it directly you must call [method mark_changed] afterwards. Prefer
##    [method take_from_slot] / [method remove] / [method set_slot], which
##    signal for you.
## [br]3. [method add] [b]consumes the stack you pass in[/b] — its `count` is
##    decremented by the amount that fitted, and the return value is exactly
##    the leftover (`stack.count` after the call). `0` means "all of it went in".
##
## [b]Change notification.[/b] Every mutation marks the inventory dirty and a
## single [signal changed] + `Events.inventory_changed` pair is emitted at the
## end of the frame, no matter how many mutations happened. Wrap large edits in
## [method begin_batch] / [method end_batch] to coalesce across frames, or call
## [method flush_now] when you need the signal immediately (e.g. before saving).
## Non-player inventories should set [member emit_global] to `false` so they do
## not spam the global bus; [ItemContainer] does this for you.
##
## [codeblock]
## var inv := Inventory.new()                  # 40 slots, 10-slot hotbar
## inv.add_id(&"raw_copper", 30)               # -> 0 leftover
## inv.has_all({&"raw_copper": 20, &"coal": 2}) # -> false
## if inv.consume({&"raw_copper": 20}):        # atomic: all or nothing
##     inv.add_id(&"copper_bar", 10)
## [/codeblock]
class_name Inventory
extends RefCounted

## Emitted (coalesced, once per frame) after any mutation of this inventory.
signal changed()
## Emitted when the hotbar cursor moves.
signal selection_changed(index: int)
## Emitted when a named equipment slot's contents change.
signal equipment_changed(slot_name: StringName)

const DEFAULT_SIZE := 40
const DEFAULT_HOTBAR := 10

# ------------------------------------------------------------- equipment slots
const SLOT_HEAD := &"head"
const SLOT_CHEST := &"chest"
const SLOT_LEGS := &"legs"
const SLOT_BACK := &"back"
const SLOT_PRIMARY := &"primary"      ## main hand — tool / weapon actually swung
const SLOT_SECONDARY := &"secondary"  ## off hand — shield, second weapon, torch
const SLOT_AUGMENT_1 := &"augment_1"
const SLOT_AUGMENT_2 := &"augment_2"
const SLOT_AUGMENT_3 := &"augment_3"

## Armour slots, in paper-doll order. Matches `ItemType.armor_slot`.
const ARMOR_SLOTS := [SLOT_HEAD, SLOT_CHEST, SLOT_LEGS, SLOT_BACK]
## The two hand slots. `SLOT_PRIMARY` is what the tech/combat modules swing.
const HAND_SLOTS := [SLOT_PRIMARY, SLOT_SECONDARY]
## Slots that accept `ItemType.Kind.AUGMENT` items.
const AUGMENT_SLOTS := [SLOT_AUGMENT_1, SLOT_AUGMENT_2, SLOT_AUGMENT_3]
## Every named equipment slot, in a stable order.
const EQUIP_SLOTS := [
	SLOT_HEAD, SLOT_CHEST, SLOT_LEGS, SLOT_BACK,
	SLOT_PRIMARY, SLOT_SECONDARY,
	SLOT_AUGMENT_1, SLOT_AUGMENT_2, SLOT_AUGMENT_3,
]

## Number of general storage slots. Slots `[0, hotbar_size)` are the hotbar.
var size: int = DEFAULT_SIZE
## How many leading slots the hotbar shows. May be 0 (containers).
var hotbar_size: int = DEFAULT_HOTBAR
## Index into the hotbar of the currently selected slot.
var selected_slot: int = 0
## When true, mutations also emit the global `Events.inventory_changed`.
## The player's inventory keeps this on; containers turn it off.
var emit_global: bool = true
## Optional gate: `func(stack: ItemStack) -> bool`. When valid, stacks it
## rejects can never enter this inventory. Used by [ItemContainer] filters.
var accept_filter: Callable = Callable()

var _slots: Array[ItemStack] = []
var _equipment: Dictionary = {}      ## StringName -> ItemStack (never null)
var _dirty := false
var _batch := 0
var _flush_queued := false


func _init(p_size: int = DEFAULT_SIZE, p_hotbar: int = DEFAULT_HOTBAR) -> void:
	size = maxi(1, p_size)
	hotbar_size = clampi(p_hotbar, 0, size)
	_slots.resize(size)
	for i in size:
		_slots[i] = ItemStack.new()
	for s: StringName in EQUIP_SLOTS:
		_equipment[s] = ItemStack.new()


# =============================================================== slot access ==
## The live stack in slot `i`. Never null; may be empty. Out-of-range returns a
## throwaway empty stack so UI code cannot crash on a stale index.
func slot(i: int) -> ItemStack:
	if i < 0 or i >= _slots.size():
		return ItemStack.new()
	return _slots[i]


## Overwrite slot `i`. Passing `null` empties the slot. The stack is stored by
## reference — hand over ownership, or pass `stack.duplicate_stack()`.
func set_slot(i: int, stack: ItemStack) -> void:
	if i < 0 or i >= _slots.size():
		return
	_slots[i] = ItemStack.new() if stack == null else stack
	mark_changed()


## Exchange two slots. Safe with equal or out-of-range indices (does nothing).
func swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= _slots.size() or b >= _slots.size():
		return
	var tmp := _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = tmp
	mark_changed()


## Move `n` items from slot `from` into slot `to`. `to` must be empty or hold a
## mergeable stack. `n <= 0` means "half of the source", the usual right-click
## split. Returns the number actually moved.
func split_to(from: int, to: int, n: int = 0) -> int:
	if from == to or from < 0 or to < 0 or from >= _slots.size() or to >= _slots.size():
		return 0
	var src := _slots[from]
	if src.is_empty():
		return 0
	var want := n if n > 0 else maxi(1, src.count / 2)
	want = mini(want, src.count)
	var dst := _slots[to]
	if dst.is_empty():
		var moved := src.split(want)
		_slots[to] = moved
		mark_changed()
		return moved.count
	if not dst.can_merge_with(src):
		return 0
	var space := dst.max_stack() - dst.count
	var amount := mini(space, want)
	if amount <= 0:
		return 0
	dst.count += amount
	src.count -= amount
	if src.count <= 0:
		src.clear()
	mark_changed()
	return amount


## Remove up to `count` items from slot `i` and return them as a new stack.
## `count < 0` takes the whole stack. Returns an empty stack if there is
## nothing to take.
func take_from_slot(i: int, count: int = -1) -> ItemStack:
	if i < 0 or i >= _slots.size():
		return ItemStack.new()
	var s := _slots[i]
	if s.is_empty():
		return ItemStack.new()
	var take := s.count if count < 0 else mini(count, s.count)
	var out := s.split(take)
	mark_changed()
	return out


## Index of the first empty slot, or -1 when the inventory is full.
func first_empty() -> int:
	for i in _slots.size():
		if _slots[i].is_empty():
			return i
	return -1


## Index of the first slot holding `id`, or -1.
func find(id: StringName) -> int:
	for i in _slots.size():
		if _slots[i].id == id and not _slots[i].is_empty():
			return i
	return -1


## Every non-empty stack, in slot order. Live references.
func all_stacks() -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for s: ItemStack in _slots:
		if not s.is_empty():
			out.append(s)
	return out


func is_full() -> bool:
	return first_empty() < 0


func is_empty() -> bool:
	for s: ItemStack in _slots:
		if not s.is_empty():
			return false
	return true


## Number of occupied slots.
func used_slots() -> int:
	var n := 0
	for s: ItemStack in _slots:
		if not s.is_empty():
			n += 1
	return n


# ==================================================================== adding ==
## True when this inventory's filter (if any) allows `stack` in at all.
func accepts(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false
	if accept_filter.is_valid():
		return bool(accept_filter.call(stack))
	return true


## Insert `stack`, topping off existing stacks first, then filling empty slots.
## [b]`stack` is mutated:[/b] on return its `count` is the leftover. The return
## value is that same leftover, so `0` means everything fitted.
func add(stack: ItemStack) -> int:
	if stack == null or stack.is_empty():
		return 0
	if not accepts(stack):
		return stack.count
	var before := stack.count
	# Pass 1 — top off compatible stacks so items clump instead of fragmenting.
	for i in _slots.size():
		if stack.is_empty():
			break
		var s := _slots[i]
		if not s.is_empty() and s.can_merge_with(stack):
			s.merge_from(stack)
	# Pass 2 — spill into empty slots.
	if not stack.is_empty():
		var cap := _stack_cap(stack.id)
		for i in _slots.size():
			if stack.is_empty():
				break
			if _slots[i].is_empty():
				_slots[i] = stack.split(mini(stack.count, cap))
	if stack.count != before:
		mark_changed()
	return stack.count


## Convenience wrapper: build `count` of `id` (with tool/weapon durability
## filled in by `Items.make`) and insert it. Returns the leftover count.
func add_id(id: StringName, count: int = 1, data: Dictionary = {}) -> int:
	if count <= 0 or not Items.has(id):
		return maxi(0, count)
	var st := Items.make(id, count)
	if not data.is_empty():
		for k: Variant in data:
			st.data[k] = data[k]
	return add(st)


## Insert several stacks. Returns the stacks that did not fit (possibly empty).
func add_all(stacks: Array) -> Array[ItemStack]:
	var left: Array[ItemStack] = []
	begin_batch()
	for s: Variant in stacks:
		var st := s as ItemStack
		if st == null:
			continue
		if add(st) > 0:
			left.append(st)
	end_batch()
	return left


## How many more of `id` would fit right now, counting partial stacks and
## empty slots. Use this before a craft/purchase to avoid spilling loot.
func room_for(id: StringName) -> int:
	var cap := _stack_cap(id)
	var room := 0
	for s: ItemStack in _slots:
		if s.is_empty():
			room += cap
		elif s.id == id:
			room += maxi(0, s.max_stack() - s.count)
	return room


## True when [method add] of `count` × `id` would leave nothing over.
func can_accept(id: StringName, count: int = 1) -> bool:
	return room_for(id) >= count


# ================================================================== removing ==
## Total number of `id` held across every storage slot (equipment excluded).
func count_of(id: StringName) -> int:
	var n := 0
	for s: ItemStack in _slots:
		if s.id == id:
			n += s.count
	return n


func has(id: StringName, count: int = 1) -> bool:
	return count_of(id) >= count


## `req` maps item id -> required count. Keys may be String or StringName.
func has_all(req: Dictionary) -> bool:
	for k: Variant in req:
		if count_of(StringName(k)) < int(req[k]):
			return false
	return true


## Remove up to `count` of `id`, lowest slot first. Returns how many were
## actually removed (may be less than `count`).
func remove(id: StringName, count: int = 1) -> int:
	if count <= 0:
		return 0
	var left := count
	for i in _slots.size():
		if left <= 0:
			break
		var s := _slots[i]
		if s.id != id or s.is_empty():
			continue
		var take := mini(left, s.count)
		s.count -= take
		left -= take
		if s.count <= 0:
			s.clear()
	if left < count:
		mark_changed()
	return count - left


## Atomic multi-remove used by crafting and vendors: removes nothing unless
## [b]every[/b] requirement can be met. `req` maps item id -> count.
func consume(req: Dictionary) -> bool:
	if not has_all(req):
		return false
	begin_batch()
	for k: Variant in req:
		remove(StringName(k), int(req[k]))
	end_batch()
	return true


## Empty every storage slot. Equipment is untouched unless `with_equipment`.
func clear(with_equipment: bool = false) -> void:
	for i in _slots.size():
		_slots[i] = ItemStack.new()
	if with_equipment:
		for s: StringName in EQUIP_SLOTS:
			_equipment[s] = ItemStack.new()
	mark_changed()


## id -> total count for everything held in storage. Handy for quest checks and
## vendor screens; the returned dictionary is a snapshot, not a live view.
func contents() -> Dictionary:
	var out: Dictionary = {}
	for s: ItemStack in _slots:
		if s.is_empty():
			continue
		out[s.id] = int(out.get(s.id, 0)) + s.count
	return out


# ==================================================================== moving ==
## Shift-click. With no `target`, moves the stack between the hotbar and the
## backpack (hotbar slot -> storage, storage slot -> hotbar), auto-equipping
## armour and augments into a free matching slot first. With a `target`
## inventory, pushes the stack into that inventory instead — the chest/machine
## transfer path. Returns the number of items moved.
func quick_move(i: int, target: Inventory = null) -> int:
	if i < 0 or i >= _slots.size():
		return 0
	var s := _slots[i]
	if s.is_empty():
		return 0
	if target != null and target != self:
		var before := s.count
		target.add(s)
		if s.is_empty():
			_slots[i] = ItemStack.new()
		var moved := before - s.count
		if moved > 0:
			mark_changed()
		return moved
	# Auto-equip when there is an obvious empty home for it.
	var eq := _auto_equip_slot(s)
	if eq != &"":
		var taken := take_from_slot(i, _stack_cap(s.id))
		var displaced := equip(eq, taken)
		if not displaced.is_empty():
			if add(displaced) > 0:
				set_slot(i, displaced)
		return 1
	if hotbar_size > 0 and i < hotbar_size:
		return _move_into_range(i, hotbar_size, _slots.size())
	return _move_into_range(i, 0, hotbar_size if hotbar_size > 0 else 0)


## Move slot `i` into the half-open slot range `[lo, hi)`. Internal helper for
## [method quick_move]; exposed because container UIs want the same behaviour.
func _move_into_range(i: int, lo: int, hi: int) -> int:
	if lo >= hi:
		return 0
	var s := _slots[i]
	var before := s.count
	for j in range(lo, hi):
		if s.is_empty():
			break
		if j == i:
			continue
		var d := _slots[j]
		if not d.is_empty() and d.can_merge_with(s):
			d.merge_from(s)
	if not s.is_empty():
		for j in range(lo, hi):
			if j == i:
				continue
			if _slots[j].is_empty():
				_slots[j] = s
				_slots[i] = ItemStack.new()
				break
	var remaining := s.count if _slots[i] == s else 0
	var moved := before - remaining
	if moved > 0:
		mark_changed()
	return moved


## Tidy the backpack: merge partial stacks and order them by kind, then
## category, then id. The hotbar keeps its layout unless `include_hotbar`.
func sort(include_hotbar: bool = false) -> void:
	var lo := 0 if include_hotbar else hotbar_size
	if lo >= _slots.size():
		return
	var picked: Array[ItemStack] = []
	for i in range(lo, _slots.size()):
		if not _slots[i].is_empty():
			picked.append(_slots[i])
		_slots[i] = ItemStack.new()
	# Merge equal stacks together before ordering.
	var merged: Array[ItemStack] = []
	for s: ItemStack in picked:
		var done := false
		for m: ItemStack in merged:
			if m.can_merge_with(s):
				m.merge_from(s)
				if s.is_empty():
					done = true
					break
		if not done and not s.is_empty():
			merged.append(s)
	merged.sort_custom(func(a: ItemStack, b: ItemStack) -> bool: return _sort_key(a) < _sort_key(b))
	var at := lo
	for s: ItemStack in merged:
		if at >= _slots.size():
			break
		_slots[at] = s
		at += 1
	mark_changed()


func _sort_key(s: ItemStack) -> String:
	var t := s.type()
	if t == null:
		return "99|zzz|%s" % s.id
	return "%02d|%s|%s" % [int(t.kind), t.category, s.id]


## Throw slot `i` into the world at `world_pos` as a physical drop. `count < 0`
## drops the whole stack. Returns the number dropped. The spawned drop gets a
## pickup delay so the player does not instantly vacuum it back up.
func drop_slot(i: int, world_pos: Vector3, count: int = -1) -> int:
	var st := take_from_slot(i, count)
	if st.is_empty():
		return 0
	var n := st.count
	var node := Game.spawn_item_drop(world_pos, st.id, st.count, st.data)
	if node != null and node.has_method(&"mark_player_dropped"):
		node.call(&"mark_player_dropped")
	return n


# ================================================================== hotbar ====
## The hotbar slots as live stacks, `[0, hotbar_size)`.
func hotbar() -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for i in mini(hotbar_size, _slots.size()):
		out.append(_slots[i])
	return out


## The stack under the hotbar cursor. Never null; may be empty.
func selected() -> ItemStack:
	if hotbar_size <= 0:
		return ItemStack.new()
	return slot(clampi(selected_slot, 0, hotbar_size - 1))


## Move the hotbar cursor. Emits `Events.hotbar_selection_changed`.
func select(i: int) -> void:
	if hotbar_size <= 0:
		return
	var n := clampi(i, 0, hotbar_size - 1)
	if n == selected_slot:
		return
	selected_slot = n
	selection_changed.emit(n)
	Events.hotbar_selection_changed.emit(n)


## Mouse-wheel style cursor step; wraps around the hotbar.
func cycle_selection(dir: int) -> void:
	if hotbar_size <= 0:
		return
	select(wrapi(selected_slot + signi(dir), 0, hotbar_size))


## Damage the durability of the selected hotbar item (tools/weapons). Returns
## true when the item broke and was removed.
func damage_selected(amount: int = 1) -> bool:
	var s := selected()
	if s.is_empty() or s.durability() < 0:
		return false
	var broke := s.damage_durability(amount)
	if broke:
		Events.play_sound.emit(&"item_break", Vector3.ZERO)
		s.clear()
	mark_changed()
	return broke


# =============================================================== equipment ====
## Contents of a named equipment slot. Never null; may be empty. Unknown slot
## names return an empty stack rather than erroring.
func equipped(slot_name: StringName) -> ItemStack:
	var s: ItemStack = _equipment.get(slot_name)
	return s if s != null else ItemStack.new()


## True when `stack` is legal in `slot_name`. Hand slots take anything, armour
## slots require a matching `ItemType.armor_slot`, augment slots require
## `Kind.AUGMENT`.
func can_equip(slot_name: StringName, stack: ItemStack) -> bool:
	if not _equipment.has(slot_name):
		return false
	if stack == null or stack.is_empty():
		return true
	var t := stack.type()
	if t == null:
		return false
	if AUGMENT_SLOTS.has(slot_name):
		return t.kind == ItemType.Kind.AUGMENT
	if ARMOR_SLOTS.has(slot_name):
		return t.kind == ItemType.Kind.ARMOR and t.armor_slot == slot_name
	return true  # hands hold tools, weapons, torches, blocks...


## Put `stack` into `slot_name` and return whatever was displaced (an empty
## stack when the slot was free). [b]On failure the passed stack is returned
## unchanged[/b] — compare identity, or call [method can_equip] first.
func equip(slot_name: StringName, stack: ItemStack) -> ItemStack:
	if not can_equip(slot_name, stack):
		return stack
	var old: ItemStack = _equipment[slot_name]
	_equipment[slot_name] = ItemStack.new() if stack == null else stack
	equipment_changed.emit(slot_name)
	mark_changed()
	return old if old != null else ItemStack.new()


## Take whatever is in `slot_name` out and return it. Empty stack if free.
func unequip(slot_name: StringName) -> ItemStack:
	if not _equipment.has(slot_name):
		return ItemStack.new()
	var old: ItemStack = _equipment[slot_name]
	_equipment[slot_name] = ItemStack.new()
	if old != null and not old.is_empty():
		equipment_changed.emit(slot_name)
		mark_changed()
	return old if old != null else ItemStack.new()


## Equip the item in storage slot `i` into `slot_name`, putting anything that
## was equipped back into slot `i`. Returns true when the swap happened.
func equip_from_slot(i: int, slot_name: StringName) -> bool:
	var s := slot(i)
	if not can_equip(slot_name, s):
		return false
	var taken := take_from_slot(i, _stack_cap(s.id))
	var old := equip(slot_name, taken)
	if not old.is_empty():
		if add(old) > 0:
			set_slot(i, old)
	return true


## Swap the two hand slots (Starbound's `Z`).
func swap_hands() -> void:
	var a: ItemStack = _equipment[SLOT_PRIMARY]
	_equipment[SLOT_PRIMARY] = _equipment[SLOT_SECONDARY]
	_equipment[SLOT_SECONDARY] = a
	equipment_changed.emit(SLOT_PRIMARY)
	equipment_changed.emit(SLOT_SECONDARY)
	mark_changed()


## Every equipped stack, keyed by slot name. Snapshot of live references.
func equipment() -> Dictionary:
	return _equipment.duplicate()


func _auto_equip_slot(stack: ItemStack) -> StringName:
	var t := stack.type()
	if t == null:
		return &""
	if t.kind == ItemType.Kind.ARMOR and ARMOR_SLOTS.has(t.armor_slot):
		if equipped(t.armor_slot).is_empty():
			return t.armor_slot
	elif t.kind == ItemType.Kind.AUGMENT:
		for s: StringName in AUGMENT_SLOTS:
			if equipped(s).is_empty():
				return s
	return &""


# ================================================================== derived ====
## Sum of the `defense` of everything equipped (armour, back, augments). The
## combat agent divides incoming damage by this via its own curve.
func total_defense() -> float:
	var total := 0.0
	for s: StringName in EQUIP_SLOTS:
		var st := equipped(s)
		if st.is_empty():
			continue
		total += float(st.stat("defense", 0.0))
	return total


## Sum of one named stat bonus across everything equipped, e.g.
## `stat_bonus("max_health")`, `stat_bonus("jump_speed")`,
## `stat_bonus("mining_speed")`. Instance data (`data["stat_bonuses"]`) is
## added on top of the item type's own `stat_bonuses`.
func stat_bonus(stat_name: String) -> float:
	var total := 0.0
	for s: StringName in EQUIP_SLOTS:
		var st := equipped(s)
		if st.is_empty():
			continue
		var t := st.type()
		if t != null and t.stat_bonuses.has(stat_name):
			total += float(t.stat_bonuses[stat_name])
		var extra: Dictionary = st.data.get("stat_bonuses", {})
		if extra.has(stat_name):
			total += float(extra[stat_name])
	return total


## Highest `tool_tier` among equipped hands — what the mining code should use
## when the player has no explicit tool selected.
func best_tool_tier(tool_kind: StringName = &"") -> int:
	var best := -1
	var candidates: Array[ItemStack] = [equipped(SLOT_PRIMARY), equipped(SLOT_SECONDARY), selected()]
	for st: ItemStack in candidates:
		if st.is_empty():
			continue
		var t := st.type()
		if t == null or t.kind != ItemType.Kind.TOOL:
			continue
		if tool_kind != &"" and t.tool_kind != tool_kind:
			continue
		best = maxi(best, t.tool_tier)
	return best


# ============================================================== change flow ====
## Mark the inventory dirty. Call this yourself only after mutating a stack
## returned by [method slot] in place.
func mark_changed() -> void:
	_dirty = true
	if _batch > 0 or _flush_queued:
		return
	_flush_queued = true
	_flush.call_deferred()


## Suspend change signals. Nestable — every `begin_batch` needs an `end_batch`.
func begin_batch() -> void:
	_batch += 1


func end_batch() -> void:
	_batch = maxi(0, _batch - 1)
	if _batch == 0 and _dirty:
		_flush()


## Emit the pending change signal right now instead of at end of frame.
func flush_now() -> void:
	if _dirty:
		_flush()


func _flush() -> void:
	_flush_queued = false
	if not _dirty or _batch > 0:
		return
	_dirty = false
	changed.emit()
	if emit_global:
		Events.inventory_changed.emit()


func _stack_cap(id: StringName) -> int:
	var t := Items.get_type(id)
	return t.stack_size if t != null else 1


# ================================================================ interop ====
# Aliases with the exact names the player, HUD, crafting, combat and NPC
# modules probe for with `has_method()`. They are thin wrappers over the API
# above — prefer the canonical names in new code.

## Alias of [method slot] (HUD slot getter probe).
func get_slot(i: int) -> ItemStack:
	return slot(i)


## The hotbar as a plain array (HUD array-getter probe).
func hotbar_stacks() -> Array:
	var out: Array = []
	for i in mini(hotbar_size, _slots.size()):
		out.append(_slots[i])
	return out


## Alias of [method selected] (player `held_stack`, crosshair).
func selected_stack() -> ItemStack:
	return selected()


## Alias of [method add] returning the leftover count (NPC bridge probe).
func add_stack(stack: ItemStack) -> int:
	return add(stack)


## Add by id; true when at least one item fitted (player `give_item` probe).
func add_item(id: StringName, count: int = 1, data: Dictionary = {}) -> bool:
	return add_id(id, count, data) < count


## Alias of [method has].
func has_item(id: StringName, count: int = 1) -> bool:
	return has(id, count)


## Remove by id; true when the full amount was removed (player `take_items`).
func remove_item(id: StringName, count: int = 1) -> bool:
	return remove(id, count) >= count


## Alias of [method remove] (player death scatter, crafting fallback).
func remove_stack(id: StringName, count: int = 1) -> int:
	return remove(id, count)


## Alias of [method remove] (crafting fallback path).
func remove_id(id: StringName, count: int = 1) -> int:
	return remove(id, count)


## Spend `n` of the selected hotbar item — placing a block, eating, throwing.
## Returns true when something was actually spent.
func consume_selected(n: int = 1) -> bool:
	if hotbar_size <= 0:
		return false
	var i := clampi(selected_slot, 0, hotbar_size - 1)
	var s := _slots[i]
	if s.is_empty():
		return false
	s.count = maxi(0, s.count - n)
	if s.count <= 0:
		s.clear()
	mark_changed()
	return true


## Scatter `fraction` (0..1) of every stack on the ground at `world_pos` — the
## death penalty. Returns the number of items dropped. Quest items are never
## dropped.
func drop_on_death(fraction: float, world_pos: Vector3) -> int:
	fraction = clampf(fraction, 0.0, 1.0)
	if fraction <= 0.0:
		return 0
	var dropped := 0
	begin_batch()
	for i in _slots.size():
		var s := _slots[i]
		if s.is_empty():
			continue
		var t := s.type()
		if t != null and (t.kind == ItemType.Kind.QUEST or t.has_tag(&"no_drop")):
			continue
		var n := int(ceilf(float(s.count) * fraction))
		if n <= 0:
			continue
		var data := s.data.duplicate(true)
		var id := s.id
		s.count -= n
		if s.count <= 0:
			s.clear()
		Game.spawn_item_drop(world_pos, id, n, data)
		dropped += n
	if dropped > 0:
		mark_changed()
	end_batch()
	return dropped


## Fraction (0..1) of `element` damage removed by worn gear. Summed from
## `stat_bonuses["resist_<element>"]` and per-stack
## `data["resistances"][element]`, then clamped.
func total_resistance(element: String) -> float:
	var key := "resist_" + element
	var total := 0.0
	for s: StringName in EQUIP_SLOTS:
		var st := equipped(s)
		if st.is_empty():
			continue
		var t := st.type()
		if t != null and t.stat_bonuses.has(key):
			total += float(t.stat_bonuses[key])
		var res: Dictionary = st.data.get("resistances", {})
		if res.has(element):
			total += float(res[element])
	return clampf(total, -2.0, 0.95)


# ---- currency bridge: the balance itself lives in `Pixels` ------------------
## Player's pixel balance (NPC/vendor bridge probe).
func get_currency() -> int:
	return Pixels.balance()


func add_currency(amount: int) -> void:
	Pixels.add(amount, "reward")


func spend_currency(amount: int) -> bool:
	return Pixels.spend(amount)


# ============================================================ serialisation ====
## Compact save form. Empty slots serialise as `{}`.
func to_dict() -> Dictionary:
	var slots: Array = []
	slots.resize(_slots.size())
	for i in _slots.size():
		slots[i] = {} if _slots[i].is_empty() else _slots[i].to_dict()
	var eq: Dictionary = {}
	for s: StringName in EQUIP_SLOTS:
		var st := equipped(s)
		if not st.is_empty():
			eq[String(s)] = st.to_dict()
	return {
		"size": size, "hotbar": hotbar_size, "selected": selected_slot,
		"slots": slots, "equipment": eq,
	}


## Restore from [method to_dict]. Resizes to the saved size; unknown item ids
## are dropped with a warning rather than aborting the load.
func from_dict(d: Dictionary) -> void:
	begin_batch()
	size = maxi(1, int(d.get("size", DEFAULT_SIZE)))
	hotbar_size = clampi(int(d.get("hotbar", DEFAULT_HOTBAR)), 0, size)
	_slots.clear()
	_slots.resize(size)
	for i in size:
		_slots[i] = ItemStack.new()
	var slots: Array = d.get("slots", [])
	for i in mini(size, slots.size()):
		var e: Dictionary = slots[i]
		if e.is_empty():
			continue
		var st := ItemStack.from_dict(e)
		if st.is_empty():
			continue
		if not Items.has(st.id):
			push_warning("[Inventory] dropping unknown item '%s' on load" % st.id)
			continue
		_slots[i] = st
	for s: StringName in EQUIP_SLOTS:
		_equipment[s] = ItemStack.new()
	var eq: Dictionary = d.get("equipment", {})
	for k: Variant in eq:
		var name_sn := StringName(k)
		if not _equipment.has(name_sn):
			continue
		var st := ItemStack.from_dict(eq[k])
		if not st.is_empty() and Items.has(st.id):
			_equipment[name_sn] = st
	selected_slot = clampi(int(d.get("selected", 0)), 0, maxi(0, hotbar_size - 1))
	mark_changed()
	end_batch()


## Deep copy, including equipment. The copy does not emit on the global bus.
func duplicate_inventory() -> Inventory:
	var inv := Inventory.new(size, hotbar_size)
	inv.emit_global = false
	inv.from_dict(to_dict())
	return inv
