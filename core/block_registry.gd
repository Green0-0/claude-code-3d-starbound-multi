## Autoloaded as `Blocks`. Owns every BlockType and the fast lookup arrays the
## mesher / physics / lighting hot loops read.
##
## Numeric ids are assigned in registration order and are NOT stable across
## builds — always refer to blocks by their StringName through `Blocks.id()`.
extends Node

var types: Array[BlockType] = []
var by_name: Dictionary = {}          ## StringName -> BlockType

# Flat mirrors of the hot fields, indexed by block id. Reading a PackedArray is
# an order of magnitude cheaper than an object property in GDScript.
var solid_lut: PackedByteArray = PackedByteArray()
var opaque_lut: PackedByteArray = PackedByteArray()
var light_lut: PackedByteArray = PackedByteArray()
var liquid_lut: PackedByteArray = PackedByteArray()
var render_lut: PackedByteArray = PackedByteArray()
var platform_lut: PackedByteArray = PackedByteArray()
var climb_lut: PackedByteArray = PackedByteArray()
var replaceable_lut: PackedByteArray = PackedByteArray()

var _content_loaded := false


func _ready() -> void:
	_register_air()
	_load_content()


func _register_air() -> void:
	var air := BlockType.new(&"air", "Air")
	air.mode(BlockType.Render.NONE)
	air.solid = false
	air.opaque = false
	air.replaceable = true
	air.breakable = false
	air.hardness = 0.0
	register(air)
	assert(air.id == Const.AIR)


## Content modules are discovered by convention: any `res://content/blocks/*.gd`
## exposing `static func register_all(reg) -> void` is invoked once at boot.
func _load_content() -> void:
	if _content_loaded:
		return
	_content_loaded = true
	for path: String in _scan("res://content/blocks"):
		var scr: Script = load(path)
		if scr == null:
			continue
		if scr.has_method(&"register_all"):
			scr.call(&"register_all", self)
	print("[Blocks] %d block types registered" % types.size())


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


# ------------------------------------------------------------------ registry
func register(bt: BlockType) -> BlockType:
	if by_name.has(bt.name):
		push_error("[Blocks] duplicate block name '%s'" % bt.name)
		return by_name[bt.name]
	bt.id = types.size()
	types.append(bt)
	by_name[bt.name] = bt
	solid_lut.append(1 if bt.solid else 0)
	opaque_lut.append(1 if bt.opaque else 0)
	light_lut.append(bt.light)
	liquid_lut.append(1 if bt.liquid else 0)
	render_lut.append(bt.render)
	platform_lut.append(1 if bt.platform else 0)
	climb_lut.append(1 if bt.climbable else 0)
	replaceable_lut.append(1 if bt.replaceable else 0)
	return bt


## Shorthand: `Blocks.define(&"stone", "Stone").look(...).mining(...)`.
func define(p_name: StringName, display: String = "") -> BlockType:
	return register(BlockType.new(p_name, display))


func id(p_name: StringName) -> int:
	var bt: BlockType = by_name.get(p_name)
	if bt == null:
		push_warning("[Blocks] unknown block '%s'" % p_name)
		return Const.AIR
	return bt.id


func has(p_name: StringName) -> bool:
	return by_name.has(p_name)


func get_type(block_id: int) -> BlockType:
	if block_id < 0 or block_id >= types.size():
		return types[0]
	return types[block_id]


func get_by_name(p_name: StringName) -> BlockType:
	return by_name.get(p_name)


func count() -> int:
	return types.size()


func all_with_tag(t: StringName) -> Array[BlockType]:
	var out: Array[BlockType] = []
	for bt: BlockType in types:
		if bt.has_tag(t):
			out.append(bt)
	return out


func all_in_category(c: StringName) -> Array[BlockType]:
	var out: Array[BlockType] = []
	for bt: BlockType in types:
		if bt.category == c:
			out.append(bt)
	return out


# ------------------------------------------------------------- hot accessors
func is_solid(block_id: int) -> bool:
	return block_id < solid_lut.size() and solid_lut[block_id] == 1


func is_opaque(block_id: int) -> bool:
	return block_id < opaque_lut.size() and opaque_lut[block_id] == 1


func is_liquid(block_id: int) -> bool:
	return block_id < liquid_lut.size() and liquid_lut[block_id] == 1


func is_platform(block_id: int) -> bool:
	return block_id < platform_lut.size() and platform_lut[block_id] == 1


func is_climbable(block_id: int) -> bool:
	return block_id < climb_lut.size() and climb_lut[block_id] == 1


func is_replaceable(block_id: int) -> bool:
	return block_id < replaceable_lut.size() and replaceable_lut[block_id] == 1


func light_of(block_id: int) -> int:
	return light_lut[block_id] if block_id < light_lut.size() else 0
