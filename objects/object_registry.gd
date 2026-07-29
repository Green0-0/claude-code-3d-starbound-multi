## The catalogue of every placeable object, and the factory that builds them.
##
## One definition drives three things, which is why the block, the item and the
## behaviour can never drift apart:
##
##   * `content/blocks/40_objects.gd` turns each entry into a `BlockType`
##   * `content/items/50_objects.gd`  turns each entry into a placer `ItemType`
##     with `places_block = <id>` and `places_object = "obj://<id>"`
##   * `ObjManager` instantiates `def["class"]` when the object is placed or
##     loaded from `tile_data`
##
## The id is the same StringName in all three registries. That is the contract.
##
## Definitions are declared by the family files in `objects/types/`, each of
## which exposes `static func register_all() -> void`.
class_name ObjRegistry
extends RefCounted

## id -> definition Dictionary
static var _defs: Dictionary = {}
static var _order: Array[StringName] = []
static var _loaded: bool = false


## Declares one object. `cls` is the `ObjBase` subclass (usually an inner class
## of the calling family file). Recognised `opts` keys, all optional:
##
##   block   color:Color  alt:Color  top:Color  pattern:int  render:int
##           hardness:float  tool:StringName  tier:int  light:int
##           emission:float  step:StringName  solid:bool  opaque:bool
##           flags:Dictionary
##   item    value:int  rarity:int  stack:int  category:StringName
##           desc:String  tags:Array[StringName]
##   logic   tick:bool  wire_in:int  wire_out:int  channel:int
##           capacity:int  station:StringName  station_tier:int
##           heat:float  light_color:Array
static func define(p_id: StringName, display: String, family: StringName,
		cls: Variant, opts: Dictionary = {}) -> Dictionary:
	if _defs.has(p_id):
		push_error("[ObjRegistry] duplicate object id '%s'" % p_id)
		return _defs[p_id]
	var d: Dictionary = {
		"id": p_id, "name": display, "family": family, "class": cls,
		"color": Color(0.55, 0.5, 0.45),
		"alt": Color(0, 0, 0, 0),
		"top": Color(0, 0, 0, 0),
		"pattern": BlockType.Pattern.METAL,
		"render": BlockType.Render.CUBE,
		"hardness": 1.4, "tool": &"any", "tier": 0,
		"light": 0, "emission": 0.0, "step": &"step_metal",
		"solid": true, "opaque": true, "flags": {},
		"value": 12, "rarity": Const.RARITY_COMMON, "stack": 100,
		"category": &"objects", "desc": "", "tags": [],
		"tick": false, "wire_in": 0, "wire_out": 0, "channel": 0,
		"capacity": 0, "station": &"", "station_tier": 0,
	}
	for k: String in opts:
		d[k] = opts[k]
	if not (d["alt"] as Color).a > 0.0:
		d["alt"] = (d["color"] as Color).darkened(0.25)
	_defs[p_id] = d
	_order.append(p_id)
	return d


## Family files, in registration order. They are loaded **by path** rather than
## by `class_name`: each family calls `ObjRegistry.define`, so naming them here
## as globals would make the dependency cyclic and GDScript would refuse to
## resolve either side.
const FAMILY_SCRIPTS := [
	"res://objects/types/containers.gd",
	"res://objects/types/stations.gd",
	"res://objects/types/machines.gd",
	"res://objects/types/furniture.gd",
	"res://objects/types/utility.gd",
]


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in FAMILY_SCRIPTS:
		if not ResourceLoader.exists(path):
			push_warning("[ObjRegistry] missing family file %s" % path)
			continue
		var scr: Script = load(path) as Script
		if scr != null:
			scr.call(&"register_all")


static func all() -> Array[StringName]:
	_ensure_loaded()
	return _order.duplicate()


static func get_def(p_id: StringName) -> Dictionary:
	_ensure_loaded()
	return _defs.get(p_id, {})


static func has(p_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(p_id)


static func count() -> int:
	_ensure_loaded()
	return _order.size()


static func in_family(family: StringName) -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for i: StringName in _order:
		if _defs[i]["family"] == family:
			out.append(i)
	return out


## Builds a live object of type `p_id` at `p_pos`. Returns null for unknown ids.
static func create(p_id: StringName, p_pos: Vector3i, p_rot: int = 0) -> ObjBase:
	var d := get_def(p_id)
	if d.is_empty():
		return null
	var cls: Variant = d["class"]
	if cls == null:
		return null
	var inst: Variant = cls.new()
	var o := inst as ObjBase
	if o == null:
		push_error("[ObjRegistry] '%s' class is not an ObjBase" % p_id)
		return null
	o.id = p_id
	o.display_name = String(d["name"])
	o.family = d["family"]
	o.def = d
	o.pos = World.normalize(p_pos)
	o.rot = p_rot & 3
	o.needs_tick = bool(d["tick"])
	o.wire_in = int(d["wire_in"])
	o.wire_out = int(d["wire_out"])
	o.on_create()
	return o
