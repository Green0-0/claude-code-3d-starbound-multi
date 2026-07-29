## Immediate-mode 3D line drawing, for anything that needs to point at a place
## in the world: block selection outlines, chunk borders, AI paths, hitboxes.
##
## Every entry point is static, so any module can call it without holding a
## reference:
##
## ```gdscript
## DebugDraw.block(hit_pos, Color.WHITE, 0.0, true)   # always-on selection box
## DebugDraw.path(monster_path, Color.ORANGE)          # debug overlay only
## ```
##
## Shapes queued with `duration == 0` live exactly one frame, which is what makes
## the API safe to call from `_process`. Anything with a longer duration expires
## on its own. Unless `always` is set, drawing is gated on `Game.debug_overlay`.
class_name DebugDraw
extends Node3D

## Colours the rest of the game should reuse so the overlay stays legible.
const COL_SELECT := Color(1.0, 1.0, 1.0, 0.95)
const COL_CHUNK := Color(0.35, 0.75, 1.0, 0.35)
const COL_PATH := Color(1.0, 0.65, 0.15, 0.9)
const COL_HIT := Color(1.0, 0.25, 0.3, 0.8)

## Hard cap so a runaway caller cannot stall the frame.
const MAX_COMMANDS := 4096

static var _inst: DebugDraw = null
static var _cmds: Array = []
static var _spawning := false

var _mesh := ImmediateMesh.new()
var _mat_depth: StandardMaterial3D = null
var _mat_overlay: StandardMaterial3D = null


# ==================================================================== statics
## Axis-aligned wireframe box.
static func box(aabb: AABB, color: Color = COL_SELECT, duration: float = 0.0,
		always: bool = false) -> void:
	if not _accept(always):
		return
	_cmds.append({"k": "box", "a": aabb, "c": color, "t": duration, "o": always})


## Wireframe around a single voxel.
static func block(pos: Vector3i, color: Color = COL_SELECT, duration: float = 0.0,
		always: bool = false) -> void:
	box(AABB(Vector3(pos), Vector3.ONE), color, duration, always)


## Slightly inflated voxel outline — what a "currently targeted block" wants, so
## it never z-fights with the face it is hugging.
static func selection(pos: Vector3i, color: Color = COL_SELECT) -> void:
	box(AABB(Vector3(pos) - Vector3(0.004, 0.004, 0.004), Vector3.ONE * 1.008),
		color, 0.0, true)


## Border of one chunk, in chunk coordinates.
static func chunk_border(cpos: Vector3i, color: Color = COL_CHUNK,
		duration: float = 0.0) -> void:
	box(AABB(Vector3(cpos * Const.CHUNK_SIZE), Vector3.ONE * float(Const.CHUNK_SIZE)),
		color, duration, false)


static func line(a: Vector3, b: Vector3, color: Color = COL_SELECT,
		duration: float = 0.0, always: bool = false) -> void:
	if not _accept(always):
		return
	_cmds.append({"k": "line", "a": a, "b": b, "c": color, "t": duration, "o": always})


## Polyline through `points`, with a small cross at every waypoint.
static func path(points: PackedVector3Array, color: Color = COL_PATH,
		duration: float = 0.0) -> void:
	if points.size() < 1 or not _accept(false):
		return
	_cmds.append({"k": "path", "p": points, "c": color, "t": duration, "o": false})


## Small three-axis cross, for marking a point of interest.
static func point(at: Vector3, color: Color = COL_HIT, size: float = 0.25,
		duration: float = 0.0, always: bool = false) -> void:
	if not _accept(always):
		return
	_cmds.append({"k": "point", "a": at, "s": size, "c": color, "t": duration, "o": always})


## Ray from `from` along `dir`, with an arrowhead at the far end.
static func ray(from: Vector3, dir: Vector3, color: Color = COL_HIT,
		duration: float = 0.0, always: bool = false) -> void:
	line(from, from + dir, color, duration, always)
	point(from + dir, color, 0.12, duration, always)


## Drop every queued shape.
static func clear() -> void:
	_cmds.clear()


## How many shapes are currently queued (handy for the HUD's debug readout).
static func command_count() -> int:
	return _cmds.size()


static func _accept(always: bool) -> bool:
	if not always and not Game.debug_overlay:
		return false
	if _cmds.size() >= MAX_COMMANDS:
		return false
	_ensure()
	return true


## Lazily create the drawing node and park it in the scene tree. Deferred so a
## caller inside `_physics_process` cannot trip Godot's "busy setting up
## children" guard.
static func _ensure() -> void:
	if is_instance_valid(_inst) or _spawning:
		return
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	_spawning = true
	var node := DebugDraw.new()
	node.name = "DebugDraw"
	var parent: Node = Game.world_renderer
	if parent == null:
		parent = loop.current_scene
	if parent == null:
		parent = loop.root
	parent.add_child.call_deferred(node)
	_inst = node


# ==================================================================== instance
func _ready() -> void:
	_spawning = false
	# Draw after gameplay has queued its shapes for this frame.
	process_priority = 200
	top_level = true
	_mat_depth = _make_material(false)
	_mat_overlay = _make_material(true)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.layers = Const.RL_EFFECTS
	# Debug lines must never be culled by their (constantly changing) bounds.
	mi.extra_cull_margin = 16384.0
	add_child(mi)


func _make_material(overlay: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	m.no_depth_test = overlay
	m.render_priority = 1 if overlay else 0
	return m


func _process(delta: float) -> void:
	_mesh.clear_surfaces()
	if _cmds.is_empty():
		return
	_draw_pass(false, _mat_depth)
	_draw_pass(true, _mat_overlay)
	_expire(delta)


## One surface per depth mode, so the always-visible shapes can ignore the
## depth buffer without dragging the rest of the overlay through walls.
func _draw_pass(overlay: bool, mat: StandardMaterial3D) -> void:
	var wanted := false
	for c: Dictionary in _cmds:
		if bool(c["o"]) == overlay:
			wanted = true
			break
	if not wanted:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for c: Dictionary in _cmds:
		if bool(c["o"]) != overlay:
			continue
		match String(c["k"]):
			"box":
				_emit_box(c["a"], c["c"])
			"line":
				_emit_line(c["a"], c["b"], c["c"])
			"path":
				_emit_path(c["p"], c["c"])
			"point":
				_emit_point(c["a"], float(c["s"]), c["c"])
	_mesh.surface_end()


func _expire(delta: float) -> void:
	var keep: Array = []
	for c: Dictionary in _cmds:
		var t := float(c["t"]) - delta
		if t > 0.0:
			c["t"] = t
			keep.append(c)
	_cmds = keep


func _emit_line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)


func _emit_box(aabb: AABB, col: Color) -> void:
	var p := aabb.position
	var s := aabb.size
	var c := [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, 0, s.z),
		p + Vector3(0, s.y, 0),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, s.y, s.z),
		p + Vector3(0, s.y, s.z),
	]
	const EDGES := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	for i in range(0, EDGES.size(), 2):
		var a: Vector3 = c[EDGES[i]]
		var b: Vector3 = c[EDGES[i + 1]]
		_emit_line(a, b, col)


func _emit_path(points: PackedVector3Array, col: Color) -> void:
	for i in range(1, points.size()):
		_emit_line(points[i - 1], points[i], col)
	for p: Vector3 in points:
		_emit_point(p, 0.12, col)


func _emit_point(at: Vector3, size: float, col: Color) -> void:
	_emit_line(at - Vector3(size, 0, 0), at + Vector3(size, 0, 0), col)
	_emit_line(at - Vector3(0, size, 0), at + Vector3(0, size, 0), col)
	_emit_line(at - Vector3(0, 0, size), at + Vector3(0, 0, size), col)
