## Autoloaded as `Items`. Same discovery convention as `Blocks`: every
## `res://content/items/*.gd` with `static func register_all(reg)` is invoked.
##
## Additionally auto-generates a placer item for any block tagged &"placeable"
## that no content file gave an explicit item, so new blocks are immediately
## obtainable without boilerplate.
extends Node

var types: Dictionary = {}          ## StringName -> ItemType
var order: Array[StringName] = []   ## registration order, for deterministic UI

var _loaded := false


func _ready() -> void:
	# Blocks must exist first so block-placer items can be derived from them.
	if Blocks.count() <= 1:
		await get_tree().process_frame
	_load_content()
	_auto_block_items()
	print("[Items] %d item types registered" % order.size())


func _load_content() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in _scan("res://content/items"):
		var scr: Script = load(path)
		if scr != null and scr.has_method(&"register_all"):
			scr.call(&"register_all", self)


func _scan(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".gd.remap"):
			out.append(dir_path + "/" + f.trim_suffix(".remap"))
	out.sort()
	return out


func _auto_block_items() -> void:
	for bt: BlockType in Blocks.types:
		if bt.id == Const.AIR or not bt.breakable:
			continue
		if types.has(bt.name):
			continue
		var it := ItemType.new(bt.name, bt.display_name)
		it.places(bt.name)
		it.look(bt.color, &"cube")
		it.description = bt.description
		it.category = bt.category
		it.value = maxi(1, int(bt.hardness * 2.0))
		for t: StringName in bt.tags:
			it.tag(t)
		register(it)
		# Blocks with no explicit drop table drop themselves.
		if bt.drops.is_empty():
			bt.drop(bt.name)


# ------------------------------------------------------------------ registry
func register(it: ItemType) -> ItemType:
	if types.has(it.id):
		push_error("[Items] duplicate item id '%s'" % it.id)
		return types[it.id]
	types[it.id] = it
	order.append(it.id)
	return it


func define(p_id: StringName, display: String = "") -> ItemType:
	return register(ItemType.new(p_id, display))


func get_type(p_id: StringName) -> ItemType:
	return types.get(p_id)


func has(p_id: StringName) -> bool:
	return types.has(p_id)


func display_name(p_id: StringName) -> String:
	var t: ItemType = types.get(p_id)
	return t.display_name if t != null else String(p_id)


func make(p_id: StringName, count: int = 1) -> ItemStack:
	if not types.has(p_id):
		push_warning("[Items] make() on unknown item '%s'" % p_id)
		return ItemStack.empty()
	var st := ItemStack.new(p_id, count)
	var t: ItemType = types[p_id]
	if t.kind == ItemType.Kind.TOOL or t.kind == ItemType.Kind.WEAPON or t.kind == ItemType.Kind.ARMOR:
		var dur := 100 + t.tool_tier * 150
		st.data["durability"] = dur
		st.data["max_durability"] = dur
	return st


func all_of_kind(k: int) -> Array[ItemType]:
	var out: Array[ItemType] = []
	for i: StringName in order:
		var t: ItemType = types[i]
		if t.kind == k:
			out.append(t)
	return out


func all_with_tag(t: StringName) -> Array[ItemType]:
	var out: Array[ItemType] = []
	for i: StringName in order:
		var it: ItemType = types[i]
		if it.has_tag(t):
			out.append(it)
	return out


func all_in_category(c: StringName) -> Array[ItemType]:
	var out: Array[ItemType] = []
	for i: StringName in order:
		var it: ItemType = types[i]
		if it.category == c:
			out.append(it)
	return out


func count() -> int:
	return order.size()
