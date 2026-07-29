## The wiring system: signals travel from emitters to consumers along wire
## voxels, or along explicit point-to-point links.
##
## ===========================================================================
##  WIRES ROUTE THROUGH LAYERS — this is the interesting part
## ===========================================================================
## Propagation uses all six voxel neighbours, and two of those run along the
## **depth axis**. A wire can therefore leave the plane the player is looking
## at, cross behind a wall, and come back — so a circuit is a genuinely 3D
## object that the player may have to flip the world to read. A lever in the
## North plane can drive a door that is only visible from the West.
##
## Two consequences worth designing around:
##   * the debug view (below) colours depth-crossing segments differently,
##     because "where does this wire go?" is otherwise unanswerable from a
##     single plane;
##   * `ObjManager` only ticks objects in loaded chunks, so a circuit whose
##     middle has streamed out simply holds its last state rather than
##     half-evaluating. Signals are latched, not lost.
##
## ===========================================================================
##  THE TICK
## ===========================================================================
## Fixed 10 Hz, **synchronous two-phase**:
##
##   phase 1  solve every network's power from the outputs objects published
##            *last* tick, flooding out from each emitter
##   phase 2  hand each consumer its new input level; objects compute their new
##            output, which will not be visible until the next tick
##
## That ordering is the loop protection. A NOT gate wired back into itself
## oscillates at 5 Hz instead of recursing forever, and no evaluation order can
## make the result depend on dictionary iteration order. The BFS additionally
## carries a visited set and a hard node budget (`MAX_NODES`) so a pathological
## wire sculpture cannot stall a frame.
class_name ObjWiring
extends RefCounted

## Signal tick rate.
const TICK_HZ := 10.0
const TICK_DT := 1.0 / TICK_HZ
## Hard ceiling on voxels visited per network flood.
const MAX_NODES := 4096
## Hard ceiling on total voxels visited per evaluation.
const MAX_TOTAL := 20000
const CHANNELS := 4

## Block tag that marks a voxel as a conductor. The channel comes from the
## companion tags `wire_ch0` .. `wire_ch3`.
const WIRE_TAG := &"wire"

## Back-reference to `ObjManager`.
var manager: Node = null
## Set true whenever anything changed; the next tick will re-solve.
var dirty: bool = true
## Draw the wire network. `ObjManager` owns the mesh node.
var debug_enabled: bool = false

## channel -> {Vector3i -> level 0..15}
var _power: Array[Dictionary] = [{}, {}, {}, {}]
## channel -> {Vector3i -> true} — every conductor discovered, powered or not.
var _seen: Array[Dictionary] = [{}, {}, {}, {}]
## block id -> channel, or -1. Built on first use.
var _wire_lut: Dictionary = {}
var _lut_built: bool = false

var _accum: float = 0.0
## Pending wire-tool connection: the object that will drive the next target.
var _link_from: Vector3i = Vector3i.ZERO
var _has_link_from: bool = false

## Counters surfaced by `debug_info()`.
var stats := {"nodes": 0, "networks": 0, "emitters": 0, "consumers": 0, "evals": 0}


func _init(p_manager: Node = null) -> void:
	manager = p_manager


# ===========================================================================
#  Conductors
# ===========================================================================
func _build_lut() -> void:
	if _lut_built:
		return
	_lut_built = true
	for bt: BlockType in Blocks.all_with_tag(WIRE_TAG):
		var ch := 0
		for c in CHANNELS:
			if bt.has_tag(StringName("wire_ch%d" % c)):
				ch = c
				break
		_wire_lut[bt.id] = ch


## Channel of the conductor at `p`, or -1 when it is not a wire.
func wire_channel_at(p: Vector3i) -> int:
	_build_lut()
	var id := World.get_block(p)
	return int(_wire_lut.get(id, -1))


func is_wire(p: Vector3i) -> bool:
	return wire_channel_at(p) >= 0


# ===========================================================================
#  Tick
# ===========================================================================
## Called every physics frame by `ObjManager`.
func tick(delta: float) -> void:
	_accum += delta
	if _accum < TICK_DT:
		return
	_accum = 0.0
	if not dirty and not _has_volatile():
		return
	evaluate()


## Sensors and timers change on their own schedule, so the evaluator cannot go
## fully idle while any of them are live.
func _has_volatile() -> bool:
	return manager != null and bool(manager.call(&"has_volatile_wired"))


## One full solve. Safe to call directly (the debug view and the wire tool do).
func evaluate() -> void:
	dirty = false
	stats["evals"] += 1
	stats["nodes"] = 0
	stats["networks"] = 0
	for c in CHANNELS:
		_power[c] = {}
		_seen[c] = {}
	if manager == null:
		return

	var wired: Array = manager.call(&"wired_objects")
	stats["emitters"] = 0
	stats["consumers"] = 0

	# ---- phase 1: solve the networks from last tick's outputs --------------
	for o: ObjBase in wired:
		var ch: int = int(o.call(&"channel")) if o.has_method(&"channel") else 0
		if o.wire_out > 0:
			stats["emitters"] += 1
			var lvl := o.output_level()
			_mark(ch, o.pos, lvl)
			if lvl > 0:
				_flood(o.pos, ch, lvl)
			else:
				_flood(o.pos, ch, 0)      ## discovery only, keeps the debug view honest
			_drive_links(o, ch, lvl)
		if o.wire_in > 0:
			stats["consumers"] += 1
			if o.wire_out <= 0:
				_flood(o.pos, ch, 0)

	# ---- phase 2: deliver ---------------------------------------------------
	for o: ObjBase in wired:
		if o.wire_in <= 0:
			continue
		var ch: int = int(o.call(&"channel")) if o.has_method(&"channel") else 0
		var lvl := input_level_for(o, ch)
		if lvl != int(o.state.get("in", 0)):
			o.on_signal_changed(lvl)


## BFS over conductors, starting from the six neighbours of `from`.
## `level` 0 performs discovery without powering anything.
func _flood(from: Vector3i, channel: int, level: int) -> void:
	var seen: Dictionary = _seen[channel]
	var queue: Array[Vector3i] = []
	for nrm: Vector3i in Const.FACE_NORMALS:
		var q := World.normalize(from + nrm)
		if wire_channel_at(q) == channel:
			queue.append(q)
	if queue.is_empty():
		return
	stats["networks"] += 1
	var visited: Dictionary = {}
	var budget := MAX_NODES
	while not queue.is_empty() and budget > 0 and stats["nodes"] < MAX_TOTAL:
		var p: Vector3i = queue.pop_back()
		if visited.has(p):
			continue
		visited[p] = true
		seen[p] = true
		budget -= 1
		stats["nodes"] += 1
		if level > 0:
			_mark(channel, p, level)
		# All six directions — two of them run along the depth axis, which is
		# what lets a circuit pass behind a wall the player has to flip to see.
		for nrm: Vector3i in Const.FACE_NORMALS:
			var q := World.normalize(p + nrm)
			if not visited.has(q) and wire_channel_at(q) == channel:
				queue.append(q)


func _mark(channel: int, p: Vector3i, level: int) -> void:
	var d: Dictionary = _power[channel]
	if int(d.get(p, 0)) < level:
		d[p] = level


## Direct point-to-point links (the wire tool's Starbound-style connections)
## power their target voxel regardless of whether any conductor connects them.
func _drive_links(o: ObjBase, channel: int, level: int) -> void:
	if not o.has_method(&"links"):
		return
	for enc: Variant in o.call(&"links"):
		if enc is Array and (enc as Array).size() == 3:
			_mark(channel, World.normalize(Vector3i(enc[0], enc[1], enc[2])), level)


# ===========================================================================
#  Queries
# ===========================================================================
## Signal level at a voxel on `channel`, 0..15.
func power_at(p: Vector3i, channel: int = 0) -> int:
	if channel < 0 or channel >= CHANNELS:
		return 0
	return int(_power[channel].get(World.normalize(p), 0))


## The level a consumer object should see: its own voxel, or any conductor
## touching it.
func input_level_for(o: ObjBase, channel: int = 0) -> int:
	var best := power_at(o.pos, channel)
	for nrm: Vector3i in Const.FACE_NORMALS:
		best = maxi(best, power_at(o.pos + nrm, channel))
	return best


func mark_dirty() -> void:
	dirty = true


# ===========================================================================
#  The wire tool
# ===========================================================================
## One click of the Matter Manipulator's WIRE mode.
##
## First click on an emitter arms a connection; the second click on any object
## completes it. `cut` (secondary fire) drops a pending connection, removes a
## wire voxel, or clears an object's links.
func click(p: Vector3i, cut: bool) -> bool:
	var o: ObjBase = manager.call(&"get_at", p) if manager != null else null

	if cut:
		if _has_link_from:
			_has_link_from = false
			Events.toast("Connection cancelled.", "info")
			return true
		if o != null and o.has_method(&"clear_links"):
			o.call(&"clear_links")
			Events.toast("Links cleared.", "info")
			mark_dirty()
			return true
		if is_wire(p):
			World.break_block(p, 99, true)
			mark_dirty()
			return true
		return false

	if o == null:
		if is_wire(p):
			Events.toast("Wire (channel %d) — power %d" % [wire_channel_at(p), power_at(p, wire_channel_at(p))], "info")
			return true
		return false

	if not _has_link_from:
		if o.wire_out <= 0:
			Events.toast("%s has no output to connect." % o.display_name, "warn")
			return false
		_link_from = p
		_has_link_from = true
		Events.toast("Connect %s to..." % o.display_name, "info")
		Events.play_sound.emit(&"wire_arm", o.center())
		return true

	_has_link_from = false
	var src: ObjBase = manager.call(&"get_at", _link_from)
	if src == null or src == o:
		return false
	if src.has_method(&"add_link"):
		src.call(&"add_link", p)
	# Teleporter pads pair up symmetrically.
	if src.has_method(&"link_to") and o.has_method(&"link_to"):
		src.call(&"link_to", p)
		o.call(&"link_to", _link_from)
	Events.toast("%s -> %s" % [src.display_name, o.display_name], "info")
	Events.play_sound.emit(&"wire_connect", o.center())
	mark_dirty()
	return true


func pending_link() -> Variant:
	return _link_from if _has_link_from else null


# ===========================================================================
#  Debug view
# ===========================================================================
## Rebuilds `mesh` with one coloured segment per conductor link.
##
##   green  powered, inside the play plane
##   grey   unpowered, inside the play plane
##   cyan   the segment crosses the depth axis — this wire leaves the plane
##   amber  a direct object-to-object link
##
## `ObjManager.set_wire_debug(true)` turns it on; it is off by default and
## costs nothing when off.
func rebuild_debug(mesh: ImmediateMesh) -> void:
	mesh.clear_surfaces()
	if not debug_enabled or manager == null:
		return
	var axis := View.depth_axis()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var drawn := 0
	for c in CHANNELS:
		for p: Vector3i in _seen[c]:
			var lvl := power_at(p, c)
			for nrm: Vector3i in Const.FACE_NORMALS:
				var q := World.normalize(p + nrm)
				if not _seen[c].has(q):
					continue
				# Draw each pair once.
				if q.x < p.x or (q.x == p.x and (q.y < p.y or (q.y == p.y and q.z < p.z))):
					continue
				var crosses := (nrm.x != 0 and axis == 0) or (nrm.z != 0 and axis == 2)
				var col := Color(0.55, 0.55, 0.6)
				if crosses:
					col = Color(0.3, 0.95, 1.0) if lvl > 0 else Color(0.2, 0.45, 0.55)
				elif lvl > 0:
					col = Color(0.35, 1.0, 0.4)
				_line(mesh, Vector3(p) + Vector3(0.5, 0.5, 0.5), Vector3(q) + Vector3(0.5, 0.5, 0.5), col)
				drawn += 1
				if drawn > 6000:
					mesh.surface_end()
					return
	for o: ObjBase in manager.call(&"wired_objects"):
		if not o.has_method(&"links"):
			continue
		for enc: Variant in o.call(&"links"):
			if enc is Array and (enc as Array).size() == 3:
				_line(mesh, o.center(),
					Vector3(enc[0], enc[1], enc[2]) + Vector3(0.5, 0.5, 0.5),
					Color(1.0, 0.75, 0.25))
	mesh.surface_end()


func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, col: Color) -> void:
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(col)
	mesh.surface_add_vertex(b)


func debug_info() -> Dictionary:
	var d := stats.duplicate()
	d["dirty"] = dirty
	d["pending_link"] = _has_link_from
	var totals: Array[int] = []
	for c in CHANNELS:
		totals.append(_seen[c].size())
	d["conductors_per_channel"] = totals
	return d
