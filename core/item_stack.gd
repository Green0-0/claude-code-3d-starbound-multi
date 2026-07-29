## A quantity of one item plus its per-instance data (durability, augments,
## procedurally generated weapon rolls...). Value-like: always `duplicate()`
## before handing one to another owner.
class_name ItemStack
extends RefCounted

var id: StringName = &""
var count: int = 0
var data: Dictionary = {}


func _init(p_id: StringName = &"", p_count: int = 0, p_data: Dictionary = {}) -> void:
	id = p_id
	count = p_count
	data = p_data.duplicate(true)


static func empty() -> ItemStack:
	return ItemStack.new()


func is_empty() -> bool:
	return id == &"" or count <= 0


func type() -> ItemType:
	return Items.get_type(id)


func max_stack() -> int:
	var t := type()
	return t.stack_size if t != null else 1


## Two stacks merge only when the id and every piece of instance data matches.
func can_merge_with(other: ItemStack) -> bool:
	if other == null or other.is_empty() or is_empty():
		return false
	return id == other.id and data == other.data


## Moves as much as will fit from `other` into self; returns the amount moved.
func merge_from(other: ItemStack) -> int:
	if not can_merge_with(other):
		return 0
	var space := max_stack() - count
	var moved := mini(space, other.count)
	count += moved
	other.count -= moved
	if other.count <= 0:
		other.clear()
	return moved


func split(n: int) -> ItemStack:
	var take := mini(n, count)
	if take <= 0:
		return ItemStack.empty()
	count -= take
	var out := ItemStack.new(id, take, data)
	if count <= 0:
		clear()
	return out


func clear() -> void:
	id = &""
	count = 0
	data.clear()


func duplicate_stack() -> ItemStack:
	return ItemStack.new(id, count, data)


func display_name() -> String:
	if is_empty():
		return ""
	if data.has("name"):
		return String(data["name"])
	var t := type()
	return t.display_name if t != null else String(id)


func rarity() -> int:
	if data.has("rarity"):
		return int(data["rarity"])
	var t := type()
	return t.rarity if t != null else Const.RARITY_COMMON


## Effective stat lookup: instance data overrides the type default. Weapons
## generated with random rolls store their numbers in `data`.
func stat(key: String, fallback: Variant = 0.0) -> Variant:
	if data.has(key):
		return data[key]
	var t := type()
	if t != null and key in t:
		return t.get(key)
	return fallback


func durability() -> int:
	return int(data.get("durability", -1))


func max_durability() -> int:
	return int(data.get("max_durability", -1))


## Returns true when the item broke.
func damage_durability(amount: int = 1) -> bool:
	if not data.has("durability"):
		return false
	data["durability"] = maxi(0, int(data["durability"]) - amount)
	return int(data["durability"]) <= 0


func to_dict() -> Dictionary:
	return {"id": String(id), "count": count, "data": data.duplicate(true)}


static func from_dict(d: Dictionary) -> ItemStack:
	return ItemStack.new(StringName(d.get("id", "")), int(d.get("count", 0)), d.get("data", {}))
