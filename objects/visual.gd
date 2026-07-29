## Procedural visual parts for placed objects.
##
## The voxel itself is drawn by the chunk mesher — these are only the pieces a
## static cube cannot express: a lamp's halo, a machine's rotor, a door leaf, a
## wire's spark. Everything is built in code from primitive meshes and unshaded
## materials; the project has no binary assets and none may be added.
##
## `ObjManager` owns the lifetime: it calls `ObjBase.build_visual()` when the
## object enters the visible slab and frees the node when it leaves.
class_name ObjVisual
extends RefCounted


static func _material(col: Color, additive: bool, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, col.a)
	m.disable_receive_shadows = true
	return m


static func _mesh_node(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = Const.RL_EFFECTS
	mi.position = at
	return mi


## A soft additive halo — lamps, powered machines, active stations.
static func glow(at: Vector3, col: Color, size: float = 0.6, energy: float = 1.0) -> Node3D:
	var s := SphereMesh.new()
	s.radius = size * 0.5
	s.height = size
	s.radial_segments = 8
	s.rings = 4
	var c := col
	c.a = 0.45
	return _mesh_node(s, _material(c, true, energy), at)


## A flat, camera-facing plate — control panels, screens, signs.
static func panel(at: Vector3, col: Color, size: float = 0.5) -> Node3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var n := _mesh_node(q, _material(col, false), at)
	# Face the camera in whichever plane the player is currently viewing from.
	n.basis = View.camera_basis()
	return n


## A small box that `ObjBase.update_visual` can spin — rotors, centrifuges.
static func rotor(at: Vector3, col: Color, size: float = 0.35) -> Node3D:
	var b := BoxMesh.new()
	b.size = Vector3(size, size * 0.28, size)
	return _mesh_node(b, _material(col, false), at)


## A thin slab used for door leaves and pressure plates.
static func slab(at: Vector3, col: Color, extent: Vector3) -> Node3D:
	var b := BoxMesh.new()
	b.size = extent
	return _mesh_node(b, _material(col, false), at)


## A translucent field — teleporter pads, shield emitters, fold seams.
static func field(at: Vector3, col: Color, radius: float, height: float) -> Node3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius * 0.8
	c.height = height
	c.radial_segments = 10
	var tint := col
	tint.a = 0.30
	return _mesh_node(c, _material(tint, true), at + Vector3(0.0, height * 0.5, 0.0))


## Rotates a visual around +Y. Call from `ObjBase.update_visual`.
static func spin(node: Node3D, delta: float, speed: float) -> void:
	if node != null:
		node.rotate_y(delta * speed)


## Gentle sine pulse on a node's scale, for "this machine is running".
static func pulse(node: Node3D, t: float, amount: float = 0.15) -> void:
	if node == null:
		return
	var s := 1.0 + sin(t * 6.0) * amount
	node.scale = Vector3(s, s, s)
