## Static bridge between `BlockType`'s Callable hooks and `ObjManager`.
##
## Block hooks are installed by `content/blocks/40_objects.gd`, which runs
## inside `Blocks._ready()` — autoload #2, long before `Tech` (#14) exists. A
## Callable bound to `Tech.objects.interact` could not be built that early, so
## the content file binds these static functions instead and they resolve the
## manager lazily, at call time.
##
## Every function here is null-safe: if the object subsystem is missing or the
## world is mid-teardown they return quietly rather than erroring.
class_name ObjHooks
extends RefCounted


static func _mgr() -> Node:
	# `Tech` is an autoload, so the identifier resolves at parse time; the
	# *node* only has to exist by the time one of these hooks actually fires.
	return Tech.objects if Tech != null else null


## `BlockType.on_interact(pos, player) -> bool`
static func interact(pos: Vector3i, player: Node) -> bool:
	var m := _mgr()
	if m == null or not m.has_method(&"interact"):
		return false
	return bool(m.call(&"interact", pos, player))


## `BlockType.on_entity_inside(pos, entity, delta)` — pressure plates and
## anything else that reacts to being stood on.
static func entity_inside(pos: Vector3i, entity: Node, _delta: float) -> void:
	var m := _mgr()
	if m == null or not m.has_method(&"get_at"):
		return
	var o: Variant = m.call(&"get_at", pos)
	if o != null and (o as ObjBase).has_method(&"on_entity_inside"):
		(o as ObjBase).call(&"on_entity_inside", entity)


## `BlockType.on_neighbour_changed(pos, from)` — wired objects re-solve.
static func neighbour_changed(_pos: Vector3i, _from: Vector3i) -> void:
	var m := _mgr()
	if m != null and m.has_method(&"wiring_dirty"):
		m.call(&"wiring_dirty")
