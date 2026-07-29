## Procedural combat visuals: swing trails, impact flashes, beams, muzzle
## flashes and shockwave rings — all built from [ImmediateMesh] triangles at
## runtime. There are no binary assets in this project and none may be added,
## so every effect here is generated from maths and thrown away when it ages
## out.
##
## Everything is drawn **in the view plane**: the quads are built in plane
## space and lifted to world space through `View.to_world`, so a swing trail
## reads identically in all four camera planes and re-orients itself for free
## when the player flips.
##
## Also the home of *hit-stop*: a very short freeze of the game clock on a
## heavy connect, requested through `Events.screen_shake` plus a scaled
## `Engine.time_scale` dip, which is what makes a hammer feel heavy.
class_name CbtMeleeFx
extends Node3D

## Effect kinds.
const KIND_ARC := 0
const KIND_SLASH := 1
const KIND_IMPACT := 2
const KIND_BEAM := 3
const KIND_RING := 4
const KIND_MUZZLE := 5
const KIND_TRAIL := 6

var kind: int = KIND_ARC
var life: float = 0.22
var age: float = 0.0
var color: Color = Color(1.0, 0.95, 0.8, 0.9)
var color_end: Color = Color(1.0, 0.6, 0.2, 0.0)

## Plane-space parameters. Meaning depends on `kind`.
var origin: Vector2 = Vector2.ZERO
var radius: float = 2.4
var inner: float = 0.6
var angle_from: float = -40.0
var angle_to: float = 50.0
var direction: Vector2 = Vector2.RIGHT
var length: float = 4.0
var width: float = 0.25
## Depth (world) the effect is drawn at.
var depth: float = 0.0
## Extra depth thickness: an effect that spans layers is drawn as a slab so the
## player can *see* that it reaches behind them.
var depth_span: float = 0.0
## Sampled points for KIND_TRAIL, plane space.
var points: PackedVector2Array = PackedVector2Array()

var _mesh: ImmediateMesh
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
## Triangles are accumulated here first: `ImmediateMesh` dislikes empty
## surfaces, and several effects legitimately draw nothing on some frames.
var _verts := PackedVector3Array()
var _cols := PackedColorArray()

static var _hitstop_left := 0.0
static var _hitstop_node: Node = null


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	_mat.disable_receive_shadows = true
	_mat.no_depth_test = false
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.layers = Const.RL_EFFECTS
	add_child(_mi)
	_rebuild(0.0)


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	_rebuild(clampf(age / maxf(0.001, life), 0.0, 1.0))


# =============================================================== spawn helpers
## Attach an effect node under the FX root (falling back to the scene root).
static func _attach(fx: CbtMeleeFx) -> CbtMeleeFx:
	var parent: Node = Game.fx_root if Game.fx_root != null else Game.main
	if parent == null:
		var tree := Engine.get_main_loop() as SceneTree
		parent = tree.current_scene if tree != null else null
	if parent == null:
		return fx
	parent.add_child(fx)
	return fx


## A sweeping crescent — the bread-and-butter melee swing trail.
## `from_deg`/`to_deg` are absolute plane-space angles (0 = screen-right).
static func swing_arc(p_origin: Vector2, p_radius: float, from_deg: float, to_deg: float,
		p_color: Color = Color(1, 0.95, 0.8), p_life: float = 0.2,
		p_depth: float = NAN) -> CbtMeleeFx:
	var fx := CbtMeleeFx.new()
	fx.kind = KIND_ARC
	fx.origin = p_origin
	fx.radius = p_radius
	fx.inner = p_radius * 0.42
	fx.angle_from = from_deg
	fx.angle_to = to_deg
	fx.color = p_color
	fx.color_end = Color(p_color.r, p_color.g, p_color.b, 0.0)
	fx.life = p_life
	fx.depth = _resolve_depth(p_depth)
	return _attach(fx)


## A straight tapered streak — thrusts, dagger stabs, dash attacks.
static func slash(p_origin: Vector2, dir: Vector2, p_length: float, p_width: float = 0.3,
		p_color: Color = Color(1, 1, 0.9), p_life: float = 0.14,
		p_depth: float = NAN) -> CbtMeleeFx:
	var fx := CbtMeleeFx.new()
	fx.kind = KIND_SLASH
	fx.origin = p_origin
	fx.direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	fx.length = p_length
	fx.width = p_width
	fx.color = p_color
	fx.color_end = Color(p_color.r, p_color.g, p_color.b, 0.0)
	fx.life = p_life
	fx.depth = _resolve_depth(p_depth)
	return _attach(fx)


## A four-pointed star flash where a hit landed.
static func impact(world_pos: Vector3, p_radius: float = 0.7,
		p_color: Color = Color(1, 0.9, 0.5), p_life: float = 0.16) -> CbtMeleeFx:
	var fx := CbtMeleeFx.new()
	fx.kind = KIND_IMPACT
	fx.origin = View.to_plane(world_pos)
	fx.radius = p_radius
	fx.color = p_color
	fx.color_end = Color(p_color.r, p_color.g, p_color.b, 0.0)
	fx.life = p_life
	fx.depth = View.depth_of(world_pos)
	return _attach(fx)


## A hard-edged beam quad between two plane points. `p_depth_span` > 0 draws it
## as a slab reaching into the screen — that is how a layer-piercing weapon
## shows the player that it went *through* the wall of layers.
static func beam(a: Vector2, b: Vector2, p_width: float = 0.3,
		p_color: Color = Color(0.6, 0.9, 1.0), p_life: float = 0.18,
		p_depth: float = NAN, p_depth_span: float = 0.0) -> CbtMeleeFx:
	var fx := CbtMeleeFx.new()
	fx.kind = KIND_BEAM
	fx.origin = a
	fx.capsule_target(b)
	fx.width = p_width
	fx.color = p_color
	fx.color_end = Color(p_color.r, p_color.g, p_color.b, 0.0)
	fx.life = p_life
	fx.depth = _resolve_depth(p_depth)
	fx.depth_span = p_depth_span
	return _attach(fx)


## An expanding ring — explosions, shockwaves, parries.
static func ring(world_pos: Vector3, p_radius: float = 3.0,
		p_color: Color = Color(1, 0.7, 0.3), p_life: float = 0.3,
		p_depth_span: float = 0.0) -> CbtMeleeFx:
	var fx := CbtMeleeFx.new()
	fx.kind = KIND_RING
	fx.origin = View.to_plane(world_pos)
	fx.radius = p_radius
	fx.color = p_color
	fx.color_end = Color(p_color.r, p_color.g, p_color.b, 0.0)
	fx.life = p_life
	fx.depth = View.depth_of(world_pos)
	fx.depth_span = p_depth_span
	return _attach(fx)


## Short cone flash at a gun barrel.
static func muzzle(p_origin: Vector2, dir: Vector2, p_radius: float = 0.7,
		p_color: Color = Color(1, 0.85, 0.4), p_life: float = 0.07) -> CbtMeleeFx:
	var fx := CbtMeleeFx.new()
	fx.kind = KIND_MUZZLE
	fx.origin = p_origin
	fx.direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	fx.radius = p_radius
	fx.color = p_color
	fx.color_end = Color(p_color.r, p_color.g, p_color.b, 0.0)
	fx.life = p_life
	fx.depth = _resolve_depth(NAN)
	return _attach(fx)


## A ribbon through a list of plane-space points — projectile trails, whips.
static func ribbon(p_points: PackedVector2Array, p_width: float = 0.18,
		p_color: Color = Color(0.9, 0.9, 1.0), p_life: float = 0.25,
		p_depth: float = NAN) -> CbtMeleeFx:
	var fx := CbtMeleeFx.new()
	fx.kind = KIND_TRAIL
	fx.points = p_points
	fx.width = p_width
	fx.color = p_color
	fx.color_end = Color(p_color.r, p_color.g, p_color.b, 0.0)
	fx.life = p_life
	fx.depth = _resolve_depth(p_depth)
	return _attach(fx)


## Stores a beam's far end without needing a second field name.
func capsule_target(b: Vector2) -> void:
	direction = (b - origin).normalized() if (b - origin).length_squared() > 0.0001 else Vector2.RIGHT
	length = origin.distance_to(b)


# =================================================================== hit-stop
## Freeze the world for a few frames on a heavy connect. `strength` 0..1 maps to
## roughly 0..90 ms of stop. Also fires `Events.screen_shake`, which the fx
## agent's camera listener turns into an actual shake.
static func hit_stop(strength: float, shake: float = -1.0) -> void:
	var s := clampf(strength, 0.0, 1.0)
	if s <= 0.001:
		return
	var shake_amt := shake if shake >= 0.0 else s * 0.8
	if shake_amt > 0.0:
		Events.screen_shake.emit(shake_amt, 0.1 + s * 0.15)
	var stop := s * 0.09
	_hitstop_left = maxf(_hitstop_left, stop)
	_ensure_hitstop_driver()


static func _ensure_hitstop_driver() -> void:
	if _hitstop_node != null and is_instance_valid(_hitstop_node):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		_hitstop_left = 0.0
		return
	const DRIVER := "res://combat/hit_stop_driver.gd"
	if not ResourceLoader.exists(DRIVER):
		_hitstop_left = 0.0
		return
	var n := Node.new()
	n.name = "CbtHitStop"
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	# `load` rather than `preload`: the driver refers back to this class, and a
	# preload would make that a compile-time cycle.
	n.set_script(load(DRIVER))
	tree.root.add_child(n)
	_hitstop_node = n


## Consumed by the tiny driver node; returns true while a stop is running.
static func _tick_hitstop(delta: float) -> bool:
	if _hitstop_left <= 0.0:
		return false
	_hitstop_left = maxf(0.0, _hitstop_left - delta)
	return _hitstop_left > 0.0


# ============================================================== mesh building
static func _resolve_depth(p_depth: float) -> float:
	if is_nan(p_depth):
		return float(View.layer) + 0.5
	return p_depth


func _world(p: Vector2, d: float) -> Vector3:
	return View.to_world(p, d)


func _rebuild(t: float) -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	_verts.clear()
	_cols.clear()
	var c := color.lerp(color_end, t)
	match kind:
		KIND_ARC:
			_build_arc(t, c)
		KIND_SLASH:
			_build_slash(t, c)
		KIND_IMPACT:
			_build_impact(t, c)
		KIND_BEAM:
			_build_beam(t, c)
		KIND_RING:
			_build_ring(t, c)
		KIND_MUZZLE:
			_build_muzzle(t, c)
		KIND_TRAIL:
			_build_trail(t, c)
	if _verts.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _verts.size():
		_mesh.surface_set_color(_cols[i])
		_mesh.surface_add_vertex(_verts[i])
	_mesh.surface_end()


func _quad(a: Vector2, b: Vector2, c2: Vector2, d: Vector2, col_a: Color, col_b: Color) -> void:
	var slabs := 1
	var step := 0.0
	if depth_span > 0.01:
		slabs = maxi(2, ceili(depth_span))
		step = depth_span / float(slabs - 1)
	for i in slabs:
		var dz := depth + step * float(i) * float(View.depth_sign())
		var fade := 1.0 if slabs == 1 else 1.0 - 0.55 * float(i) / float(slabs - 1)
		var ca := Color(col_a.r, col_a.g, col_a.b, col_a.a * fade)
		var cb := Color(col_b.r, col_b.g, col_b.b, col_b.a * fade)
		_tri(_world(a, dz), _world(b, dz), _world(c2, dz), ca, cb, cb)
		_tri(_world(a, dz), _world(c2, dz), _world(d, dz), ca, cb, ca)


func _tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_verts.push_back(a)
	_cols.push_back(ca)
	_verts.push_back(b)
	_cols.push_back(cb)
	_verts.push_back(c)
	_cols.push_back(cc)


func _build_arc(t: float, c: Color) -> void:
	# The crescent wipes along its own sweep, so the leading edge draws first.
	var steps := 14
	var sweep := angle_to - angle_from
	var lead := clampf(t * 1.6, 0.0, 1.0)
	var tail := clampf(t * 1.6 - 0.55, 0.0, 1.0)
	var r_out := radius * (0.85 + 0.15 * (1.0 - t))
	var r_in := inner * (0.9 + 0.2 * t)
	for i in steps:
		var f0 := float(i) / float(steps)
		var f1 := float(i + 1) / float(steps)
		if f1 < tail or f0 > lead:
			continue
		var a0 := deg_to_rad(angle_from + sweep * f0)
		var a1 := deg_to_rad(angle_from + sweep * f1)
		var p0 := origin + Vector2(cos(a0), sin(a0)) * r_out
		var p1 := origin + Vector2(cos(a1), sin(a1)) * r_out
		var q0 := origin + Vector2(cos(a0), sin(a0)) * r_in
		var q1 := origin + Vector2(cos(a1), sin(a1)) * r_in
		var fade_a := Color(c.r, c.g, c.b, c.a * clampf(1.0 - (lead - f0) * 1.4, 0.05, 1.0))
		var fade_b := Color(c.r, c.g, c.b, c.a * clampf(1.0 - (lead - f1) * 1.4, 0.05, 1.0))
		_quad(q0, p0, p1, q1, fade_a, fade_b)


func _build_slash(t: float, c: Color) -> void:
	var n := Vector2(-direction.y, direction.x)
	var reach := length * (0.55 + 0.45 * clampf(t * 2.2, 0.0, 1.0))
	var w := width * (1.0 - t * 0.7)
	var tip := origin + direction * reach
	var faded := Color(c.r, c.g, c.b, 0.0)
	_quad(origin - n * w, origin + n * w, tip + n * w * 0.15, tip - n * w * 0.15, c, faded)


func _build_impact(t: float, c: Color) -> void:
	var r := radius * (0.4 + 1.6 * t)
	var w := radius * 0.22 * (1.0 - t)
	for k in 4:
		var a := deg_to_rad(45.0 + 90.0 * float(k))
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x)
		_quad(origin - n * w, origin + n * w,
			origin + d * r + n * w * 0.1, origin + d * r - n * w * 0.1,
			c, Color(c.r, c.g, c.b, 0.0))


func _build_beam(t: float, c: Color) -> void:
	var n := Vector2(-direction.y, direction.x)
	var w := width * (1.0 - t * 0.85)
	var tip := origin + direction * length
	var core := Color(minf(1.0, c.r + 0.4), minf(1.0, c.g + 0.4), minf(1.0, c.b + 0.4), c.a)
	_quad(origin - n * w, origin + n * w, tip + n * w, tip - n * w, c, c)
	_quad(origin - n * w * 0.35, origin + n * w * 0.35,
		tip + n * w * 0.35, tip - n * w * 0.35, core, core)


func _build_ring(t: float, c: Color) -> void:
	var steps := 20
	var r_out := radius * (0.15 + 0.95 * t)
	var r_in := maxf(0.0, r_out - radius * 0.22 * (1.0 - t * 0.6))
	for i in steps:
		var a0 := TAU * float(i) / float(steps)
		var a1 := TAU * float(i + 1) / float(steps)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		_quad(origin + d0 * r_in, origin + d0 * r_out,
			origin + d1 * r_out, origin + d1 * r_in, c, c)


func _build_muzzle(t: float, c: Color) -> void:
	var r := radius * (1.0 - t * 0.5)
	var n := Vector2(-direction.y, direction.x)
	var spread := r * 0.55
	_quad(origin - n * r * 0.12, origin + n * r * 0.12,
		origin + direction * r + n * spread, origin + direction * r - n * spread,
		c, Color(c.r, c.g, c.b, 0.0))


func _build_trail(t: float, c: Color) -> void:
	if points.size() < 2:
		return
	var count := points.size()
	for i in count - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := b - a
		if seg.length_squared() < 0.000001:
			continue
		var n := Vector2(-seg.y, seg.x).normalized()
		var f0 := float(i) / float(count - 1)
		var f1 := float(i + 1) / float(count - 1)
		var w0 := width * f0 * (1.0 - t)
		var w1 := width * f1 * (1.0 - t)
		var ca := Color(c.r, c.g, c.b, c.a * f0)
		var cb := Color(c.r, c.g, c.b, c.a * f1)
		_quad(a - n * w0, a + n * w0, b + n * w1, b - n * w1, ca, cb)


# ================================================================= presets
## Element -> trail colour, so every weapon looks like what it does.
static func element_color(element: String) -> Color:
	match element:
		Const.ELEM_FIRE: return Color(1.0, 0.55, 0.18)
		Const.ELEM_ICE: return Color(0.55, 0.85, 1.0)
		Const.ELEM_ELECTRIC: return Color(0.85, 0.85, 1.0)
		Const.ELEM_POISON: return Color(0.55, 0.95, 0.35)
		Const.ELEM_COSMIC: return Color(0.85, 0.5, 1.0)
	return Color(0.95, 0.95, 0.9)


## The full "something got hit" package: flash, sparks, shake, hit-stop.
static func hit_feedback(world_pos: Vector3, element: String, power: float,
		crit: bool = false) -> void:
	var col := element_color(element)
	impact(world_pos, 0.5 + 0.5 * clampf(power, 0.0, 2.0), col, 0.14 + 0.06 * clampf(power, 0.0, 1.0))
	Events.spawn_particles.emit(&"hit_spark", world_pos, 4 + int(6.0 * clampf(power, 0.0, 2.0)))
	if crit:
		ring(world_pos, 1.4, col, 0.22)
	hit_stop(clampf(power * (1.6 if crit else 1.0) * 0.35, 0.0, 1.0))
