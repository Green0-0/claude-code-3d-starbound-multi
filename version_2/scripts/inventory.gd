class_name Inventory
extends RefCounted

## The player's carried goods.
##
## One flat slot array with named ranges rather than three containers, because
## every UI operation is "move the stack in slot A to slot B" and a single index
## space makes that one function instead of nine.
##
##   0  .. 8   hotbar        (the row along the bottom of the screen)
##   9  .. 38  backpack
##   39 .. 41  armour        (head, chest, legs)
##
## Pixels are a counter rather than a stack: they are the currency, every vendor
## reads them, and nobody has ever wanted to drop them on the floor.

signal changed()
signal picked_up(item_id: StringName, count: int)

const HOTBAR_SIZE := 9
const BACKPACK_SIZE := 30
const ARMOR_SIZE := 3
const HOTBAR_START := 0
const BACKPACK_START := HOTBAR_SIZE
const ARMOR_START := HOTBAR_SIZE + BACKPACK_SIZE
const TOTAL := ARMOR_START + ARMOR_SIZE

var slots: Array[Items.Stack] = []
var selected := 0
var pixels := 0

## Cached sum of every equipped item's stat bonuses, including set bonuses.
var _bonuses := {}
var _bonuses_dirty := true


func _init() -> void:
	slots.resize(TOTAL)
	for i in TOTAL:
		slots[i] = Items.Stack.new()


# =============================================================================
# slot access
# =============================================================================

func get_slot(i: int) -> Items.Stack:
	if i < 0 or i >= TOTAL:
		return Items.Stack.new()
	return slots[i]


func set_slot(i: int, stack: Items.Stack) -> void:
	if i < 0 or i >= TOTAL:
		return
	slots[i] = stack
	_touch()


func selected_stack() -> Items.Stack:
	return slots[clampi(selected, 0, HOTBAR_SIZE - 1)]


func select(i: int) -> void:
	selected = clampi(i, 0, HOTBAR_SIZE - 1)
	changed.emit()


func cycle(delta: int) -> void:
	selected = wrapi(selected + delta, 0, HOTBAR_SIZE)
	changed.emit()


func is_armor_slot(i: int) -> bool:
	return i >= ARMOR_START and i < TOTAL


static func armor_index(slot: StringName) -> int:
	match slot:
		Items.SLOT_HEAD: return ARMOR_START
		Items.SLOT_CHEST: return ARMOR_START + 1
		Items.SLOT_LEGS: return ARMOR_START + 2
	return -1


func armor_at(slot: StringName) -> Items.Stack:
	var i := armor_index(slot)
	return slots[i] if i >= 0 else Items.Stack.new()


# =============================================================================
# adding and removing
# =============================================================================

## Put `stack` away. Returns how many items would not fit (0 on success), and
## mutates `stack` so the caller can leave the remainder on the floor.
func add(stack: Items.Stack) -> int:
	if stack.is_empty():
		return 0
	if stack.id == &"pixels":
		pixels += stack.count
		var n := stack.count
		stack.clear()
		picked_up.emit(&"pixels", n)
		_touch()
		return 0
	var wanted := stack.count
	# top up partial stacks of the same item first, hotbar before backpack
	for i in ARMOR_START:
		if stack.is_empty():
			break
		var s := slots[i]
		if s.is_empty() or s.id != stack.id or s.data != stack.data:
			continue
		s.merge_from(stack)
	# then spill into empty slots
	for i in ARMOR_START:
		if stack.is_empty():
			break
		if slots[i].is_empty():
			slots[i].merge_from(stack)
	var moved := wanted - stack.count
	if moved > 0:
		picked_up.emit(stack.id if not stack.is_empty() else &"", moved)
		_touch()
	return stack.count


## Convenience for code that just wants "give the player N of these".
func add_item(item_id: StringName, count := 1) -> int:
	return add(Items.make(item_id, count))


func count_of(item_id: StringName) -> int:
	if item_id == &"pixels":
		return pixels
	var n := 0
	for i in ARMOR_START:
		if slots[i].id == item_id:
			n += slots[i].count
	return n


func has(item_id: StringName, count := 1) -> bool:
	return count_of(item_id) >= count


## Take `count` of an item out of the bag. Returns false and changes nothing if
## there was not enough.
func remove(item_id: StringName, count := 1) -> bool:
	if item_id == &"pixels":
		if pixels < count:
			return false
		pixels -= count
		_touch()
		return true
	if count_of(item_id) < count:
		return false
	var left := count
	# spend the smallest stacks first so the bag consolidates as you play
	var order: Array[int] = []
	for i in ARMOR_START:
		if slots[i].id == item_id:
			order.append(i)
	order.sort_custom(func(a, b): return slots[a].count < slots[b].count)
	for i in order:
		if left <= 0:
			break
		var take: int = mini(left, slots[i].count)
		slots[i].count -= take
		left -= take
		if slots[i].count <= 0:
			slots[i].clear()
	_touch()
	return true


func first_empty() -> int:
	for i in ARMOR_START:
		if slots[i].is_empty():
			return i
	return -1


func is_full() -> bool:
	return first_empty() < 0


## Swap two slots, merging instead when they hold the same thing. Armour slots
## reject anything that is not the right armour piece.
func swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= TOTAL or b >= TOTAL:
		return
	var sa := slots[a]
	var sb := slots[b]
	if is_armor_slot(b) and not _fits_armor(sa, b):
		return
	if is_armor_slot(a) and not _fits_armor(sb, a):
		return
	if not sa.is_empty() and not sb.is_empty() and sa.id == sb.id and sa.data == sb.data:
		sb.merge_from(sa)
		if sa.is_empty():
			_touch()
			return
	slots[a] = sb
	slots[b] = sa
	_touch()


func _fits_armor(stack: Items.Stack, index: int) -> bool:
	if stack.is_empty():
		return true
	var t := stack.type()
	if t == null or t.kind != Items.Kind.ARMOR:
		return false
	return armor_index(t.armor_slot) == index


## Drop half (or all) of a slot into a fresh stack the caller owns.
func take_from(index: int, count := -1) -> Items.Stack:
	var s := get_slot(index)
	if s.is_empty():
		return Items.Stack.new()
	var n := s.count if count < 0 else mini(count, s.count)
	var out := s.split(n)
	_touch()
	return out


# =============================================================================
# equipment stats
# =============================================================================

## Total of one stat across every equipped item, plus completed set bonuses.
func bonus(stat: String) -> float:
	if _bonuses_dirty:
		_rebuild_bonuses()
	return float(_bonuses.get(stat, 0.0))


func total_defense() -> float:
	if _bonuses_dirty:
		_rebuild_bonuses()
	return float(_bonuses.get("defense", 0.0))


## Fractional damage reduction against one element, clamped to something short
## of immunity so nothing is ever completely safe.
func resistance(element: StringName) -> float:
	return clampf(bonus("resist_" + String(element)), -1.0, 0.85)


func _rebuild_bonuses() -> void:
	_bonuses_dirty = false
	_bonuses = {}
	var worn: Array[StringName] = []
	for i in range(ARMOR_START, TOTAL):
		var s := slots[i]
		if s.is_empty():
			continue
		var t := s.type()
		if t == null:
			continue
		_bonuses["defense"] = float(_bonuses.get("defense", 0.0)) + t.defense
		for k: String in t.stat_bonuses:
			_bonuses[k] = float(_bonuses.get(k, 0.0)) + float(t.stat_bonuses[k])
		for tag: StringName in t.tags:
			if String(tag).begins_with("set_"):
				worn.append(tag)
	# a set bonus lands only when all three pieces carry the same set tag
	var counts := {}
	for tag: StringName in worn:
		counts[tag] = int(counts.get(tag, 0)) + 1
	var armor_script: GDScript = load("res://scripts/content/itm_armor.gd")
	for tag: StringName in counts:
		if int(counts[tag]) < 3:
			continue
		var set_id := StringName(String(tag).substr(4))
		var b: Dictionary = armor_script.set_bonus(set_id)
		for k: String in b:
			if k == "name" or k == "text":
				continue
			_bonuses[k] = float(_bonuses.get(k, 0.0)) + float(b[k])


## The names of every set bonus currently active, for the UI to display.
func active_set_bonuses() -> Array[String]:
	var out: Array[String] = []
	var counts := {}
	for i in range(ARMOR_START, TOTAL):
		var t := slots[i].type()
		if t == null:
			continue
		for tag: StringName in t.tags:
			if String(tag).begins_with("set_"):
				counts[tag] = int(counts.get(tag, 0)) + 1
	var armor_script: GDScript = load("res://scripts/content/itm_armor.gd")
	for tag: StringName in counts:
		if int(counts[tag]) >= 3:
			var b: Dictionary = armor_script.set_bonus(StringName(String(tag).substr(4)))
			if b.has("text"):
				out.append(String(b["text"]))
	return out


func _touch() -> void:
	_bonuses_dirty = true
	changed.emit()


# =============================================================================
# persistence
# =============================================================================

func to_dict() -> Dictionary:
	var out: Array = []
	for s: Items.Stack in slots:
		out.append(s.to_dict())
	return {"slots": out, "selected": selected, "pixels": pixels}


func from_dict(d: Dictionary) -> void:
	var arr: Array = d.get("slots", [])
	for i in TOTAL:
		slots[i] = Items.Stack.from_dict(arr[i]) if i < arr.size() else Items.Stack.new()
	selected = clampi(int(d.get("selected", 0)), 0, HOTBAR_SIZE - 1)
	pixels = int(d.get("pixels", 0))
	_touch()
