## Short-lived marks on the world: scorch rings, blood splatter, footprints and
## projectile chips.
##
## These are not Godot `Decal` nodes — a projected decal costs a whole clipping
## volume per mark, and a voxel world does not need one. Each mark is a single
## unshaded quad snapped flat onto the voxel face it hit, nudged 12 mm along the
## normal to beat z-fighting, and faded out over its lifetime. The pool is small
## and recycles oldest-first, so the marks read as "recent activity" rather than
## permanent graffiti.
class_name FxDecals
extends Node3D

const POOL := 28
const OFFSET := 0.012

## kind -> {life, size, color, tex}
const KINDS := {
	&"scorch": {"life": 22.0, "size": 1.5, "color": Color(0.08, 0.06, 0.05, 0.85), "tex": &"scorch"},
	&"blood": {"life": 16.0, "size": 0.8, "color": Color(0.55, 0.05, 0.06, 0.85), "tex": &"splat"},
	&"footprint": {"life": 12.0, "size": 0.42, "color": Color(0.35, 0.37, 0.42, 0.55), "tex": &"foot"},
	&"chip": {"life": 9.0, "size": 0.34, "color": Color(0.12, 0.12, 0.14, 0.7), "tex": &"chip"},
	&"burn": {"life": 14.0, "size": 0.7, "color": Color(0.12, 0.07, 0.04, 0.8), "tex": &"scorch"},
	&"slime": {"life": 14.0, "size": 0.7, "color": Color(0.35, 0.75, 0.3, 0.7), "tex": &"splat"},
}

var enabled := true

var _pool: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _born: PackedFloat64Array = PackedFloat64Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _base_a: PackedFloat32Array = PackedFloat32Array()
var _quad: QuadMesh = null
var _tex: Dictionary = {}
var _next := 0


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_born.resize(POOL)
	_life.resize(POOL)
	_base_a.resize(POOL)
	for i in POOL:
		var mi := MeshInstance3D.new()
		mi.name = "Decal%d" % i
		mi.mesh = _quad
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = Const.RL_EFFECTS
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.no_depth_test = false
		m.render_priority = 2
		mi.material_override = m
		add_child(mi)
		_pool.append(mi)
		_mats.append(m)
		_born[i] = 0.0
		_life[i] = 0.0


func _process(_delta: float) -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	for i in _pool.size():
		if _life[i] <= 0.0:
			continue
		var t := (now - _born[i]) / _life[i]
		if t >= 1.0:
			_life[i] = 0.0
			_pool[i].visible = false
			continue
		# Hold, then fade over the last third of the life.
		var a := _base_a[i] * clampf((1.0 - t) * 3.0, 0.0, 1.0)
		var c := _mats[i].albedo_color
		_mats[i].albedo_color = Color(c.r, c.g, c.b, a)


# ======================================================================== API
## Place a mark on the voxel face at `pos` whose outward normal is `normal`.
## `size_scale` and `tint` override the kind's defaults.
func add(kind: StringName, pos: Vector3, normal: Vector3,
		size_scale: float = 1.0, tint: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	if not enabled or not KINDS.has(kind):
		return null
	if normal.length_squared() < 0.001:
		normal = Vector3.UP
	normal = normal.normalized()
	if _out_of_slab(pos):
		return null
	var spec: Dictionary = KINDS[kind]
	var idx := _take()
	var mi := _pool[idx]
	var mat := _mats[idx]
	var col: Color = tint if tint.a > 0.0 else spec["color"]
	mat.albedo_texture = _texture(spec.get("tex", &"splat"))
	mat.albedo_color = col
	var size: float = float(spec["size"]) * maxf(0.05, size_scale)

	# Snap onto the plane of the face without losing the tangential position.
	var voxel := Const.floor_v(pos - normal * 0.05)
	var centre := Vector3(voxel) + Vector3(0.5, 0.5, 0.5)
	var along := (pos - centre).dot(normal)
	var p := pos - normal * (along - 0.5 - OFFSET)

	var up := Vector3.UP if absf(normal.y) < 0.9 else Vector3.FORWARD
	var xb := up.cross(normal).normalized()
	var yb := normal.cross(xb).normalized()
	var spin := randf() * TAU
	var xr := xb * cos(spin) + yb * sin(spin)
	var yr := yb * cos(spin) - xb * sin(spin)
	mi.global_transform = Transform3D(Basis(xr * size, yr * size, normal), p)
	mi.visible = true
	_born[idx] = float(Time.get_ticks_msec()) * 0.001
	_life[idx] = float(spec["life"])
	_base_a[idx] = col.a
	return mi


## Scorch a sphere of faces around an explosion centre.
func scorch_burst(centre: Vector3, radius: float, count: int = 5) -> void:
	if not enabled:
		return
	var world := get_node_or_null(^"/root/World")
	if world == null:
		return
	for i in count:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 0.2),
				randf_range(-1.0, 1.0)).normalized()
		var hit: Dictionary = world.call(&"raycast", centre, dir, radius * 1.4)
		if not bool(hit.get("hit", false)):
			continue
		var n := Vector3(hit.get("normal", Vector3i.UP))
		var p := Vector3(hit.get("pos", Vector3i.ZERO)) + Vector3(0.5, 0.5, 0.5) + n * 0.5
		add(&"scorch", p, n, randf_range(0.6, 1.2))


## Footprint under an entity, oriented flat on the floor.
func footprint(pos: Vector3, tint: Color = Color(0, 0, 0, 0)) -> void:
	add(&"footprint", pos + Vector3(0, 0.02, 0), Vector3.UP, 1.0, tint)


func clear() -> void:
	for i in _pool.size():
		_life[i] = 0.0
		_pool[i].visible = false


func _out_of_slab(pos: Vector3) -> bool:
	var off := int(roundf((View.depth_of(pos) - float(View.layer)) * float(View.depth_sign())))
	return off > Const.SLAB_BEHIND or off < -2


func _take() -> int:
	for i in _pool.size():
		var j := (_next + i) % _pool.size()
		if _life[j] <= 0.0:
			_next = (j + 1) % _pool.size()
			return j
	var best := 0
	var oldest := INF
	for i in _pool.size():
		if _born[i] < oldest:
			oldest = _born[i]
			best = i
	_next = (best + 1) % _pool.size()
	return best


# =================================================================== textures
func _texture(key: StringName) -> ImageTexture:
	if _tex.has(key):
		return _tex[key]
	var img: Image
	match String(key):
		"scorch": img = _img_scorch()
		"foot": img = _img_foot()
		"chip": img = _img_chip()
		_: img = _img_splat()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


func _new_image(n: int) -> Image:
	return Image.create_empty(n, n, false, Image.FORMAT_RGBA8)


func _img_scorch() -> Image:
	var n := 32
	var img := _new_image(n)
	var c := float(n - 1) * 0.5
	var rng := FxSynth.seeded(&"decal_scorch", 0)
	var wob := PackedFloat32Array()
	wob.resize(16)
	for i in 16:
		wob[i] = rng.randf_range(0.72, 1.0)
	for y in n:
		for x in n:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var a_i := int((atan2(dy, dx) + PI) / TAU * 16.0) % 16
			var edge: float = wob[a_i]
			var a := clampf(1.0 - r / maxf(0.05, edge), 0.0, 1.0)
			a = pow(a, 0.75) * (0.8 + 0.2 * rng.randf())
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


func _img_splat() -> Image:
	var n := 32
	var img := _new_image(n)
	var rng := FxSynth.seeded(&"decal_splat", 0)
	var blobs := []
	for i in 7:
		blobs.append(Vector3(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8),
				rng.randf_range(0.06, 0.22)))
	for y in n:
		for x in n:
			var u := float(x) / float(n - 1)
			var v := float(y) / float(n - 1)
			var a := 0.0
			for b: Vector3 in blobs:
				var d := Vector2(u - b.x, v - b.y).length()
				a = maxf(a, clampf(1.0 - d / b.z, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * 1.4, 0.0, 1.0)))
	return img


func _img_foot() -> Image:
	var n := 32
	var img := _new_image(n)
	for y in n:
		for x in n:
			var u := (float(x) / float(n - 1) - 0.5) * 2.0
			var v := (float(y) / float(n - 1) - 0.5) * 2.0
			# Sole (large ellipse) plus heel (small one behind it).
			var sole := Vector2(u / 0.42, (v + 0.22) / 0.62).length()
			var heel := Vector2(u / 0.34, (v - 0.58) / 0.30).length()
			var a := maxf(clampf(1.0 - sole, 0.0, 1.0), clampf(1.0 - heel, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * 2.4, 0.0, 1.0)))
	return img


func _img_chip() -> Image:
	var n := 32
	var img := _new_image(n)
	var c := float(n - 1) * 0.5
	var rng := FxSynth.seeded(&"decal_chip", 0)
	for y in n:
		for x in n:
			img.set_pixel(x, y, Color(1, 1, 1, 0.0))
	# A few radial cracks from the centre.
	for k in 5:
		var ang := rng.randf() * TAU
		var len_px := rng.randf_range(6.0, 13.0)
		var steps := int(len_px * 2.0)
		var jitter := 0.0
		for s in steps:
			jitter += rng.randf_range(-0.12, 0.12)
			var d := float(s) * 0.5
			var px := int(c + cos(ang + jitter) * d)
			var py := int(c + sin(ang + jitter) * d)
			if px < 0 or py < 0 or px >= n or py >= n:
				break
			var a := clampf(1.0 - d / len_px, 0.0, 1.0)
			img.set_pixel(px, py, Color(1, 1, 1, maxf(img.get_pixel(px, py).a, a)))
	return img
