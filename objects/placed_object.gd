## Base class for anything placed in the world that has behaviour and state:
## chests, crafting stations, machines, doors, furniture, wiring nodes.
##
## ===========================================================================
##  THE tile_data SCHEMA — persistence and structures agents both read this
## ===========================================================================
## A placed object is **a voxel plus a `Chunk.tile_data` payload**. There is no
## node to save and no scene to instance: because `Chunk.to_dict()` already
## serialises `tile_data`, an object saves and loads with its chunk for free.
##
## `chunk.tile_data[Chunk.index(lx, ly, lz)]` =
## [codeblock]
## {
##   "kind":  "object",      # discriminator. Ours is exactly "object".
##   "obj":   "chest_wood",  # ObjRegistry id. Also the block and item name.
##   "rot":   0,             # View index (0..3) the object was placed from.
##   "state": {},            # object-specific, always var_to_bytes-safe:
##                           #   int / float / bool / String / Array / Dict
##   "inv":   [              # containers only; ItemStack.to_dict() entries
##              {"id": "iron_bar", "count": 8, "data": {}}, ...
##            ],
##   "wire":  {              # present only on wired objects
##              "ch":    0,          # wire channel 0..3
##              "out":   0,          # last emitted level 0..15
##              "in":    0,          # last received level 0..15
##              "links": [[x,y,z]]   # absolute targets of direct links
##            },
##   "paint": [r, g, b],     # optional; written by the Matter Manipulator
##   "v":     1              # schema version
## }
## [/codeblock]
##
## **Rules for anyone touching this payload**
##
##  1. `World.set_block()` erases the tile_data at that index. Always write the
##     block first and the payload second. `ObjManager.place()` does this.
##  2. Tolerate unknown keys and unknown `kind`s — several agents share the
##     dictionary. `"paint"` in particular may appear on a plain voxel with no
##     object at all.
##  3. Keys not listed here are reserved for the agent that owns that `kind`.
##     See `worldgen/structures/struct_markers.gd` for the generator's kinds
##     ("container", "door", "lever", "light", "sign", "teleporter", ...);
##     `ObjManager` adapts those into objects lazily on first load or open.
##  4. Everything in `state` must survive a `var_to_bytes` round trip. Store
##     `Vector3i` as a 3-element int Array, `Color` as a 3-element float Array.
##
## ===========================================================================
##  THE VISUAL NODE
## ===========================================================================
## The voxel itself is drawn by the chunk mesher. `build_visual()` is only for
## the parts a static mesh cannot express: a lamp's glow, a door's moving leaf,
## a machine's spinning rotor. `ObjManager` calls it when the object's chunk
## enters the visible slab and frees the node when it leaves, so an object that
## returns `null` costs nothing at all.
class_name ObjBase
extends RefCounted

const SCHEMA_VERSION := 1

# ------------------------------------------------------------------ identity
var id: StringName = &""
var display_name: String = "Object"
## Absolute world voxel this object occupies.
var pos: Vector3i = Vector3i.ZERO
## The `View` index the player faced when placing it, 0..3.
var rot: int = 0
## `container` | `station` | `machine` | `furniture` | `utility`
var family: StringName = &"machine"

# ---------------------------------------------------------------- definition
## Cached `ObjRegistry` definition. Read-only.
var def: Dictionary = {}
## Does this object need `on_tick`? Machines yes, a chair no.
var needs_tick: bool = false
## Number of wire inputs / outputs. Zero means "not a wiring node".
var wire_in: int = 0
var wire_out: int = 0

# --------------------------------------------------------------------- state
## Free-form, persisted verbatim. Use `st()` / `set_st()` for typed access.
var state: Dictionary = {}
## Live visual node, or null. Owned by `ObjManager`.
var visual: Node3D = null
## Back-reference to `ObjManager`.
var manager: Node = null


# ===========================================================================
#  Lifecycle — override these
# ===========================================================================
## Called once, immediately after the registry stamps `id`/`def` on a fresh
## instance and before any state is loaded. Set defaults here.
func on_create() -> void:
	pass


## Called when the player places the object. `state` is at its defaults.
func on_placed(_player: Node) -> void:
	pass


## Called when the object is rebuilt from tile_data (chunk load, save load).
func on_load() -> void:
	pass


## Called before the voxel disappears. Return extra item drops as
## `[{"item": StringName, "count": int}]` — a container returns its contents.
func on_removed() -> Array:
	return []


## Machines only (`needs_tick`). `delta` is real seconds since this object's
## last tick, which is **not** the frame time: `ObjManager` ticks objects on a
## budget, so a busy world simply ticks each machine less often.
func on_tick(_delta: float) -> void:
	pass


## The player pressed `interact` (or the manipulator's secondary) on this
## object. Return true when the input was consumed.
func on_interact(_player: Node) -> bool:
	return false


## Wire input changed. `level` is 0..15.
func on_signal_changed(_level: int) -> void:
	pass


## Level this object emits, 0..15. Only meaningful when `wire_out > 0`.
func output_level() -> int:
	return int(state.get("out", 0))


## Optional per-object visual. Return null for objects the mesher already
## draws completely. Never add it to the tree yourself.
func build_visual() -> Node3D:
	return null


## Called every frame the visual exists, for animation. Keep it cheap.
func update_visual(_delta: float) -> void:
	pass


# ===========================================================================
#  Helpers
# ===========================================================================
func center() -> Vector3:
	return Vector3(pos) + Vector3(0.5, 0.5, 0.5)


func chunk() -> Chunk:
	return World.chunk_at_block(pos)


## Local `Chunk.index` of this object's voxel.
func tile_index() -> int:
	var n := World.normalize(pos)
	return Chunk.index(n.x & 15, n.y & 15, n.z & 15)


func chunk_pos() -> Vector3i:
	var n := World.normalize(pos)
	return Vector3i(n.x >> 4, n.y >> 4, n.z >> 4)


## Typed read out of `state`.
func st(key: String, fallback: Variant = null) -> Variant:
	return state.get(key, fallback)


## Typed write into `state`. Persists immediately unless `defer` is true.
func set_st(key: String, value: Variant, defer: bool = false) -> void:
	state[key] = value
	if not defer:
		write()


## How many layers behind the play layer this object sits. Negative = in front.
func layer_offset() -> int:
	return View.layer_offset(pos)


## True when the player could act on this object right now.
func in_reach() -> bool:
	return Tech.voxel_in_reach(pos)


## Is the object inside the currently rendered slab?
func in_slab() -> bool:
	var off := layer_offset()
	return off >= -Const.SLAB_FRONT and off <= Const.SLAB_BEHIND


## Direction this object faces, as a world unit vector, from its `rot`.
func facing_world() -> Vector3:
	return Vector3(Const.VIEW_RIGHT[rot & 3])


## Swaps the voxel under this object for another block **without losing the
## object**. `World.set_block()` erases `tile_data` at the index, so the payload
## is lifted out first and written straight back. Doors, lamps and anything else
## with an on/off block variant use this.
func swap_block(block_name: StringName) -> bool:
	if not Blocks.has(block_name):
		return false
	var c := chunk()
	if c == null:
		return false
	var i := tile_index()
	var payload: Dictionary = c.get_tile_data(i).duplicate(true)
	if not World.set_block(pos, Blocks.id(block_name)):
		return false
	c.set_tile_data(i, payload)
	return true


func notify_changed() -> void:
	World.mark_dirty(chunk_pos())
	if manager != null and manager.has_method(&"on_object_changed"):
		manager.call(&"on_object_changed", self)


func sound(sound_id: StringName) -> void:
	Events.play_sound.emit(sound_id, center())


func particles(effect: StringName, amount: int = 6) -> void:
	Events.spawn_particles.emit(effect, center(), amount)


# ===========================================================================
#  Persistence
# ===========================================================================
## Serialise into the tile_data payload documented at the top of this file.
## Existing foreign keys (`paint`, and anything a future agent adds) are kept.
func to_tile_data(existing: Dictionary = {}) -> Dictionary:
	var d: Dictionary = existing.duplicate(true)
	# `save_extra` may fold data back into `state` (a station stashes its craft
	# queue there), so it has to run *before* the snapshot is taken.
	var extra := save_extra()
	d["kind"] = "object"
	d["obj"] = String(id)
	d["rot"] = rot
	d["state"] = state.duplicate(true)
	d["v"] = SCHEMA_VERSION
	for k: String in extra:
		d[k] = extra[k]
	return d


func from_tile_data(d: Dictionary) -> void:
	rot = int(d.get("rot", 0)) & 3
	var s: Variant = d.get("state", {})
	state = (s as Dictionary).duplicate(true) if s is Dictionary else {}
	load_extra(d)


## Subclass hook for top-level keys beyond `state` — containers write `"inv"`,
## wired objects write `"wire"`.
func save_extra() -> Dictionary:
	return {}


func load_extra(_d: Dictionary) -> void:
	pass


## Writes this object back into its chunk's tile_data. Cheap; call it whenever
## something meaningful changes rather than every frame.
func write() -> void:
	var c := chunk()
	if c == null:
		return
	var i := tile_index()
	c.set_tile_data(i, to_tile_data(c.get_tile_data(i)))


## Removes this object's payload from tile_data without touching the voxel.
func erase() -> void:
	var c := chunk()
	if c == null:
		return
	var i := tile_index()
	var d: Dictionary = c.get_tile_data(i).duplicate()
	# Leave foreign keys (paint) behind; only strip what we own.
	for k: String in ["kind", "obj", "rot", "state", "inv", "wire", "v"]:
		d.erase(k)
	c.set_tile_data(i, d)


func debug_line() -> String:
	return "%s @ %v  fam=%s  wire(in %d/out %d)  state=%s" % [
		String(id), pos, String(family), wire_in, wire_out, state]
