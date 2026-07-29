## Owns every live placed object: builds them from `tile_data` as chunks stream
## in, frees them as chunks stream out, spawns and frees their visual nodes as
## the visible slab moves, ticks machines on a budget, and runs the wiring.
##
## Created and parented by `Tech` (autoload) as `Tech.objects` — this agent owns
## exactly one autoload, so the object subsystem hangs off it rather than
## claiming a second slot in `project.godot`.
##
## ===========================================================================
##  ENTRY POINTS FOR OTHER AGENTS  (all guarded-callable)
## ===========================================================================
##   Tech.objects.get_at(pos)                -> ObjBase or null
##   Tech.objects.place(pos, id, rot)        -> bool
##   Tech.objects.interact(pos, player)      -> bool
##   Tech.objects.on_block_removed(pos)      -> void   (call before the voxel goes)
##   Tech.objects.heat_at(world_pos)         -> float  (survival: campfires)
##   Tech.objects.objects_in_radius(p, r)    -> Array[ObjBase]
##   Tech.objects.set_wire_debug(true)       -> void
##   Tech.objects.debug_info()               -> Dictionary
##
## ===========================================================================
##  STRUCTURE MARKERS
## ===========================================================================
## `worldgen/structures/` writes payloads with its own `kind` (see
## `struct_markers.gd`). On chunk load we adopt the kinds this agent owns —
## `container`, `door`, `lever`, `light`, `teleporter` — converting them into
## real objects while keeping every original key inside `state`, so a chest's
## `loot_table` / `tier` / `seed` survive to be rolled on first open. Kinds we
## do not own are left completely untouched.
class_name ObjManager
extends Node

## Machines ticked per physics frame. The rest wait their turn; `on_tick`
## receives the real elapsed time, so a machine ticked half as often still runs
## at the same rate.
const TICK_BUDGET := 24
## Objects whose visual state is re-checked per frame.
const VISUAL_BUDGET := 48
## Structure `container` tier -> chest object id.
const CHEST_BY_TIER: Array[StringName] = [
	&"chest_wood", &"chest_wood", &"chest_iron", &"chest_titanium",
	&"chest_durasteel", &"storage_pod", &"storage_pod",
]
## Guarded dependency: the inventory agent's loot roller.
const LOOT_ROLLER_PATHS := [
	"res://inventory/loot_roller.gd",
	"res://worldgen/structures/struct_loot.gd",
]

# --------------------------------------------------------------------- state
## Vector3i -> ObjBase
var objects: Dictionary = {}
## cpos -> {Vector3i -> true}
var by_chunk: Dictionary = {}
## Objects with `needs_tick`, in a stable order for round-robin.
var tick_list: Array[ObjBase] = []
## Objects that currently have a visual node.
var visual_list: Array[ObjBase] = []

var wiring: ObjWiring = null

var _tick_cursor: int = 0
var _visual_cursor: int = 0
var _last_tick_ms: Dictionary = {}     ## Vector3i -> msec
var _visual_root: Node3D = null
var _debug_mesh: ImmediateMesh = null
var _debug_node: MeshInstance3D = null
var _loot_script: Script = null
var _loot_probed: bool = false
var _placing: bool = false


func _ready() -> void:
	process_priority = -10
	wiring = ObjWiring.new(self)
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.chunk_unloaded.connect(_on_chunk_unloaded)
	Events.block_changed.connect(_on_block_changed)
	Events.world_unloaded.connect(_on_world_unloaded)
	Events.layer_changed.connect(func(_l: int, _v: int) -> void: _visual_cursor = 0)
	Events.view_flip_finished.connect(func(_v: int) -> void: _visual_cursor = 0)
	call_deferred(&"_make_roots")


func _make_roots() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "ObjectVisuals"
	var parent: Node = Game.main if Game.main != null else self
	parent.add_child(_visual_root)

	_debug_mesh = ImmediateMesh.new()
	_debug_node = MeshInstance3D.new()
	_debug_node.name = "WireDebug"
	_debug_node.mesh = _debug_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_debug_node.material_override = mat
	_debug_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_node.layers = Const.RL_EFFECTS
	_debug_node.visible = false
	_visual_root.add_child(_debug_node)


# ===========================================================================
#  Lookup
# ===========================================================================
func get_at(p: Vector3i) -> ObjBase:
	return objects.get(World.normalize(p))


func has_at(p: Vector3i) -> bool:
	return objects.has(World.normalize(p))


func objects_in_radius(centre: Vector3, radius: float) -> Array[ObjBase]:
	var out: Array[ObjBase] = []
	var r2 := radius * radius
	for p: Vector3i in objects:
		if (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_squared_to(centre) <= r2:
			out.append(objects[p])
	return out


func all_of_family(family: StringName) -> Array[ObjBase]:
	var out: Array[ObjBase] = []
	for p: Vector3i in objects:
		var o: ObjBase = objects[p]
		if o.family == family:
			out.append(o)
	return out


## Total heat from every lit heat source reaching `world_pos`. The survival
## agent's temperature model adds this to the ambient.
func heat_at(world_pos: Vector3) -> float:
	var total := 0.0
	for p: Vector3i in objects:
		var o: ObjBase = objects[p]
		if not o.has_method(&"heat"):
			continue
		var h := float(o.call(&"heat"))
		if h <= 0.0:
			continue
		var r := float(o.call(&"radius")) if o.has_method(&"radius") else 6.0
		var d := o.center().distance_to(world_pos)
		if d < r:
			total += h * (1.0 - d / r)
	return total


# ===========================================================================
#  Placement and removal
# ===========================================================================
## Places `obj_id` at `pos`: sets the voxel first, then writes the tile_data
## payload (because `World.set_block` erases it), then wakes the object.
func place(pos: Vector3i, obj_id: StringName, view_rot: int = 0, player: Node = null) -> bool:
	var p := World.normalize(pos)
	var d := ObjRegistry.get_def(obj_id)
	if d.is_empty():
		return false
	if not Blocks.has(obj_id):
		push_warning("[Objects] '%s' has no matching block" % obj_id)
		return false
	_placing = true
	var ok := World.place_block(p, Blocks.id(obj_id))
	_placing = false
	if not ok:
		return false
	var o := ObjRegistry.create(obj_id, p, view_rot)
	if o == null:
		return false
	o.manager = self
	_register(o)
	o.on_placed(player)
	o.write()
	wiring.mark_dirty()
	Events.play_sound.emit(&"place_object", o.center())
	return true


## Called by the tool beam (and by `_on_block_changed`) just before a voxel
## carrying an object disappears. Spills the object's contents.
func on_block_removed(pos: Vector3i) -> void:
	var p := World.normalize(pos)
	var o: ObjBase = objects.get(p)
	if o == null:
		return
	for drop: Dictionary in o.on_removed():
		var item: StringName = drop.get("item", &"")
		var n := int(drop.get("count", 0))
		if item != &"" and n > 0 and Items.has(item):
			Game.spawn_item_drop(o.center() + Vector3(0.0, 0.4, 0.0), item, n)
	_unregister(o)
	wiring.mark_dirty()


func _register(o: ObjBase) -> void:
	o.manager = self
	objects[o.pos] = o
	var cp := o.chunk_pos()
	if not by_chunk.has(cp):
		by_chunk[cp] = {}
	(by_chunk[cp] as Dictionary)[o.pos] = true
	if o.needs_tick:
		tick_list.append(o)
	_last_tick_ms[o.pos] = Time.get_ticks_msec()


func _unregister(o: ObjBase) -> void:
	_free_visual(o)
	objects.erase(o.pos)
	var cp := o.chunk_pos()
	if by_chunk.has(cp):
		(by_chunk[cp] as Dictionary).erase(o.pos)
	var i := tick_list.find(o)
	if i >= 0:
		tick_list.remove_at(i)
	_last_tick_ms.erase(o.pos)
	o.erase()


# ===========================================================================
#  Interaction
# ===========================================================================
## Routed here from `tech/interaction.gd` and from block `on_interact` hooks.
func interact(pos: Vector3i, player: Node) -> bool:
	var p := World.normalize(pos)
	var o: ObjBase = objects.get(p)
	if o == null:
		o = _adopt_marker(p)     ## a structure marker that has not woken yet
	if o == null:
		return false
	return o.on_interact(player)


## The Matter Manipulator's WIRE mode routes here.
func wire_click(pos: Vector3i, cut: bool) -> bool:
	return wiring.click(World.normalize(pos), cut)


func wiring_dirty() -> void:
	wiring.mark_dirty()


## Point-to-point drive used by `Lever` links.
func drive_link(target: Vector3i, level: int) -> void:
	var o: ObjBase = objects.get(World.normalize(target))
	if o != null and o.wire_in > 0:
		o.on_signal_changed(level)


## Every object that participates in wiring. Used by `ObjWiring`.
func wired_objects() -> Array:
	var out: Array = []
	for p: Vector3i in objects:
		var o: ObjBase = objects[p]
		if o.wire_in > 0 or o.wire_out > 0:
			out.append(o)
	return out


## True when any wired object changes state on its own (timers, sensors), so
## the evaluator must keep running even when nothing has been touched.
func has_volatile_wired() -> bool:
	for o: ObjBase in tick_list:
		if o.wire_out > 0:
			return true
	return false


# ===========================================================================
#  Loot
# ===========================================================================
## Rolls a structure chest's contents the first time it is opened, then marks
## it so it never rerolls. Uses the inventory agent's `LootRoller` when it
## exists, then the worldgen agent's `StructLoot`, then gives up quietly.
func fill_loot(chest: ObjBase) -> void:
	if chest == null or bool(chest.st("opened", false)):
		return
	var table := String(chest.st("loot_table", ""))
	chest.state["opened"] = true
	if table == "":
		chest.write()
		return
	var tier := int(chest.st("tier", 0))
	var seed_value := int(chest.st("seed", 0))
	var rolled := _roll_loot(table, tier, seed_value)
	for entry: Variant in rolled:
		var item := &""
		var n := 1
		if entry is ItemStack:
			item = (entry as ItemStack).id
			n = (entry as ItemStack).count
		elif entry is Dictionary:
			var e: Dictionary = entry
			item = StringName(e.get("item", e.get("id", "")))
			n = int(e.get("count", e.get("n", 1)))
		if item != &"" and n > 0 and Items.has(item) and chest.has_method(&"add_item"):
			chest.call(&"add_item", item, n, {})
	chest.write()
	if not rolled.is_empty():
		Events.toast("%s contained %d things." % [chest.display_name, rolled.size()], "loot")


func _roll_loot(table: String, tier: int, seed_value: int) -> Array:
	if not _loot_probed:
		_loot_probed = true
		for path: String in LOOT_ROLLER_PATHS:
			if ResourceLoader.exists(path):
				_loot_script = load(path) as Script
				if _loot_script != null:
					break
	if _loot_script == null:
		return []
	var names: Dictionary = {}
	for m: Dictionary in _loot_script.get_script_method_list():
		names[String(m.get("name", ""))] = (m.get("args", []) as Array).size()
	for fn: String in ["roll", "roll_table", "generate", "roll_loot"]:
		if int(names.get(fn, -1)) < 3:
			continue
		var res: Variant = _loot_script.call(fn, table, tier, seed_value)
		return res if res is Array else []
	return []


# ===========================================================================
#  Chunk streaming
# ===========================================================================
func _on_chunk_loaded(cpos: Vector3i) -> void:
	var c: Chunk = World.get_chunk(cpos)
	if c == null or c.tile_data.is_empty():
		return
	var origin := c.origin()
	for i: Variant in c.tile_data.keys():
		var idx := int(i)
		var local := Chunk.from_index(idx)
		_wake(origin + local, c.tile_data[idx])


func _on_chunk_unloaded(cpos: Vector3i) -> void:
	var entries: Dictionary = by_chunk.get(cpos, {})
	for p: Vector3i in entries.keys():
		var o: ObjBase = objects.get(p)
		if o == null:
			continue
		o.write()          ## flush state into tile_data before the chunk goes
		_free_visual(o)
		objects.erase(p)
		var i := tick_list.find(o)
		if i >= 0:
			tick_list.remove_at(i)
		_last_tick_ms.erase(p)
	by_chunk.erase(cpos)
	wiring.mark_dirty()


func _on_world_unloaded() -> void:
	for p: Vector3i in objects.keys():
		_free_visual(objects[p])
	objects.clear()
	by_chunk.clear()
	tick_list.clear()
	visual_list.clear()
	_last_tick_ms.clear()
	wiring.mark_dirty()


## Someone changed a voxel we might own. Placing goes through `place()`, so
## this only has to catch removals and third-party edits.
func _on_block_changed(pos: Vector3i, _old_id: int, new_id: int) -> void:
	if _placing:
		return
	var p := World.normalize(pos)
	var o: ObjBase = objects.get(p)
	if o == null:
		return
	# A block swap performed by the object itself (door, lamp) keeps the object.
	if Blocks.has(o.id) and new_id == Blocks.id(o.id):
		return
	var open_block := StringName(o.def.get("open_block", &""))
	var off_block := StringName(o.def.get("off_block", &""))
	if (open_block != &"" and Blocks.has(open_block) and new_id == Blocks.id(open_block)) \
			or (off_block != &"" and Blocks.has(off_block) and new_id == Blocks.id(off_block)) \
			or (Blocks.has(StringName(String(o.id) + "_off")) and new_id == Blocks.id(StringName(String(o.id) + "_off"))):
		return
	on_block_removed(p)


## Builds a live object from one tile_data payload.
func _wake(p: Vector3i, payload: Variant) -> ObjBase:
	if not (payload is Dictionary):
		return null
	var d: Dictionary = payload
	var kind := String(d.get("kind", ""))
	var pos := World.normalize(p)
	if objects.has(pos):
		return objects[pos]

	if kind == "object":
		var obj_id := StringName(d.get("obj", ""))
		if not ObjRegistry.has(obj_id):
			return null
		var o := ObjRegistry.create(obj_id, pos, int(d.get("rot", 0)))
		if o == null:
			return null
		o.manager = self
		o.from_tile_data(d)
		_register(o)
		o.on_load()
		wiring.mark_dirty()
		return o
	return _adopt(pos, d, kind)


## Lazily convert a structure marker we have not seen yet.
func _adopt_marker(p: Vector3i) -> ObjBase:
	var c := World.chunk_at_block(p)
	if c == null:
		return null
	var n := World.normalize(p)
	var d: Dictionary = c.get_tile_data(Chunk.index(n.x & 15, n.y & 15, n.z & 15))
	if d.is_empty():
		return null
	return _wake(n, d)


## Marker -> object adapters. Every original key is preserved inside `state`,
## so loot tables, lock ids and puzzle wiring survive the conversion.
func _adopt(pos: Vector3i, d: Dictionary, kind: String) -> ObjBase:
	var obj_id := &""
	match kind:
		"container":
			var tier := clampi(int(d.get("tier", 0)), 0, CHEST_BY_TIER.size() - 1)
			obj_id = &"safe" if bool(d.get("locked", false)) else CHEST_BY_TIER[tier]
		"door":
			obj_id = &"wired_door"
		"lever":
			obj_id = &"lever"
		"light":
			obj_id = &"lamp"
		"teleporter":
			obj_id = &"teleporter_pad"
		_:
			return null      ## not ours — leave the payload exactly as it is
	if not ObjRegistry.has(obj_id):
		return null
	var o := ObjRegistry.create(obj_id, pos, 0)
	if o == null:
		return null
	o.manager = self
	# Keep the marker verbatim so nothing is lost in translation.
	for k: Variant in d:
		if String(k) != "kind":
			o.state[String(k)] = d[k]
	_register(o)
	o.on_load()
	o.write()
	wiring.mark_dirty()
	return o


# ===========================================================================
#  Per-frame
# ===========================================================================
func _physics_process(delta: float) -> void:
	if Game.paused or not World.ready_flag:
		return
	_tick_machines()
	wiring.tick(delta)


func _process(delta: float) -> void:
	if not World.ready_flag:
		return
	_refresh_visuals()
	for o: ObjBase in visual_list:
		o.update_visual(delta)
	if wiring.debug_enabled:
		wiring.rebuild_debug(_debug_mesh)


## Round-robin over machines within a fixed per-frame budget. Each object is
## handed the real time since *it* last ticked, so the budget throttles CPU
## without changing how fast anything runs.
func _tick_machines() -> void:
	if tick_list.is_empty():
		return
	var now := Time.get_ticks_msec()
	var n := mini(TICK_BUDGET, tick_list.size())
	for _i in n:
		if _tick_cursor >= tick_list.size():
			_tick_cursor = 0
		var o: ObjBase = tick_list[_tick_cursor]
		_tick_cursor += 1
		if o == null:
			continue
		var last := int(_last_tick_ms.get(o.pos, now))
		_last_tick_ms[o.pos] = now
		var dt := float(now - last) * 0.001
		if dt > 0.0:
			o.on_tick(minf(dt, 1.0))


## Adds and removes visual nodes as the slab moves. Budgeted, cursor-based —
## a flip does not cost a frame even with thousands of objects loaded.
func _refresh_visuals() -> void:
	if _visual_root == null or objects.is_empty():
		return
	var keys: Array = objects.keys()
	var n := mini(VISUAL_BUDGET, keys.size())
	for _i in n:
		if _visual_cursor >= keys.size():
			_visual_cursor = 0
		var p: Vector3i = keys[_visual_cursor]
		_visual_cursor += 1
		var o: ObjBase = objects.get(p)
		if o == null:
			continue
		var want := o.in_slab()
		if want and o.visual == null:
			var v := o.build_visual()
			if v != null:
				o.visual = v
				_visual_root.add_child(v)
				visual_list.append(o)
		elif not want and o.visual != null:
			_free_visual(o)


func _free_visual(o: ObjBase) -> void:
	if o == null or o.visual == null:
		return
	var i := visual_list.find(o)
	if i >= 0:
		visual_list.remove_at(i)
	o.visual.queue_free()
	o.visual = null


# ===========================================================================
#  Debug
# ===========================================================================
## Turns the wire debug overlay on or off.
func set_wire_debug(on: bool) -> void:
	wiring.debug_enabled = on
	if _debug_node != null:
		_debug_node.visible = on
	if on:
		wiring.evaluate()
		wiring.rebuild_debug(_debug_mesh)
	else:
		_debug_mesh.clear_surfaces()
	Events.toast("Wire debug %s" % ("on" if on else "off"), "info")


func toggle_wire_debug() -> void:
	set_wire_debug(not wiring.debug_enabled)


func debug_info() -> Dictionary:
	return {
		"objects": objects.size(),
		"ticking": tick_list.size(),
		"visuals": visual_list.size(),
		"chunks": by_chunk.size(),
		"wiring": wiring.debug_info(),
	}


func debug_dump() -> Array[String]:
	var out: Array[String] = []
	for p: Vector3i in objects:
		out.append((objects[p] as ObjBase).debug_line())
	return out


# ===========================================================================
#  Persistence
# ===========================================================================
## Object state lives in `Chunk.tile_data` and is saved by the chunk, so this
## only has to flush anything still in memory and carry manager-level flags.
func save_state() -> Dictionary:
	for p: Vector3i in objects:
		(objects[p] as ObjBase).write()
	return {"wire_debug": wiring.debug_enabled}


func load_state(d: Dictionary) -> void:
	_on_world_unloaded()
	set_wire_debug(bool(d.get("wire_debug", false)))
	# Everything else rebuilds from tile_data as chunks stream back in.
	for cpos: Vector3i in World.loaded_chunk_positions():
		_on_chunk_loaded(cpos)
