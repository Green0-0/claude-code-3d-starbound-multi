## The animated backdrop of the title screen: a small voxel island seen through
## the game's own four viewing planes, cycling North -> West -> South -> East.
##
## It is not decoration for its own sake. It teaches the mechanic before the
## player has pressed a key: the island rotates, layers in front of the play
## plane dissolve, layers behind it dim, and what looked like a wall from one
## plane is obviously a corridor from the next.
##
## Pure [method Control._draw] — no meshes, no textures, nothing to import.
class_name MenuPlaneDiorama
extends Control

const GRID := 13                ## island is GRID x GRID columns
const DWELL := 2.4              ## seconds parked on one plane
const TURN := 0.62              ## seconds spent rotating to the next
const PITCH := 0.30             ## radians of downward tilt, for readability

var _heights: PackedInt32Array = PackedInt32Array()
var _kinds: PackedInt32Array = PackedInt32Array()
var _t: float = 0.0
var _view: int = 0
var _yaw: float = 0.0
var _turning: bool = false
var _cell: float = 26.0

const KIND_COLORS := [
	Color(0.34, 0.60, 0.29),   # grass
	Color(0.46, 0.34, 0.23),   # dirt
	Color(0.40, 0.42, 0.47),   # stone
	Color(0.62, 0.58, 0.40),   # sand
	Color(0.30, 0.55, 0.70),   # water / ice
]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_generate(20240729)


func _generate(island_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed
	_heights.resize(GRID * GRID)
	_kinds.resize(GRID * GRID)
	var mid := (GRID - 1) * 0.5
	for z in GRID:
		for x in GRID:
			var d := Vector2(x - mid, z - mid).length() / mid
			var wave := sin(x * 0.9 + island_seed * 0.01) * 0.8 + cos(z * 0.7) * 0.8
			var h := int(round(4.0 + wave - d * 4.2 + rng.randf_range(-0.4, 0.4)))
			var i := z * GRID + x
			_heights[i] = clampi(h, 0, 7)
			if _heights[i] <= 0:
				_kinds[i] = -1                  # hole: nothing drawn
			elif _heights[i] <= 1:
				_kinds[i] = 4
			elif d > 0.72:
				_kinds[i] = 3
			elif _heights[i] >= 5:
				_kinds[i] = 2
			else:
				_kinds[i] = 0
	# Carve a tunnel straight through the island along Z. From the North and
	# South planes it reads as a corridor; from West and East it is invisible.
	for z in GRID:
		var i := z * GRID + int(mid)
		if _heights[i] > 2:
			_heights[i] = 2
			_kinds[i] = 1


func _process(delta: float) -> void:
	_t += delta
	var cycle := DWELL + TURN
	var phase := fmod(_t, cycle)
	var step := int(_t / cycle)
	_view = step % 4
	if phase < DWELL:
		_turning = false
		_yaw = deg_to_rad(90.0 * _view)
	else:
		_turning = true
		var p: float = ease((phase - DWELL) / TURN, 0.35)
		_yaw = deg_to_rad(90.0 * (_view + p))
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	_cell = minf(rect.size.x / (GRID * 2.4), rect.size.y / (GRID * 1.9))
	var centre := rect.size * Vector2(0.5, 0.56)
	var mid := (GRID - 1) * 0.5

	# Which world axis is "depth" right now, and which slice the player is on.
	var axis_is_z: bool = (_view % 2) == 0
	var play := int(mid)

	var order: Array[int] = []
	for i in GRID * GRID:
		order.append(i)
	var depths := PackedFloat32Array()
	depths.resize(GRID * GRID)
	for i in GRID * GRID:
		var x := i % GRID
		var z := floori(float(i) / float(GRID))
		depths[i] = _depth(Vector3(x - mid, 0.0, z - mid))
	order.sort_custom(func(a: int, b: int) -> bool: return depths[a] > depths[b])

	_draw_plane_frames(centre, mid)

	for i: int in order:
		var kind := _kinds[i]
		if kind < 0:
			continue
		var x := i % GRID
		var z := floori(float(i) / float(GRID))
		var h := _heights[i]
		if h <= 0:
			continue
		# Slab rules, straight out of the real renderer.
		var slice := z if axis_is_z else x
		var offset := (slice - play) * (1 if _view >= 2 else -1)
		var alpha := 1.0
		if offset < 0:
			alpha = 0.0                       # in front of the play plane
		elif offset > 0:
			alpha = maxf(0.14, 1.0 - offset * 0.16)
		if alpha <= 0.02:
			continue
		_draw_column(centre, Vector3(x - mid, 0.0, z - mid), h,
			KIND_COLORS[kind], alpha)

	_draw_player(centre, mid, play, axis_is_z)
	_draw_caption(rect)


func _project(v: Vector3, centre: Vector2) -> Vector2:
	var cy := cos(_yaw)
	var sy := sin(_yaw)
	var rx := v.x * cy - v.z * sy
	var rz := v.x * sy + v.z * cy
	return centre + Vector2(rx, -(v.y * cos(PITCH) - rz * sin(PITCH))) * _cell


func _depth(v: Vector3) -> float:
	var rz := v.x * sin(_yaw) + v.z * cos(_yaw)
	return rz * cos(PITCH) + v.y * sin(PITCH)


func _draw_column(centre: Vector2, base: Vector3, h: int, col: Color, alpha: float) -> void:
	var top := float(h) * 0.55
	var c := Color(col.r, col.g, col.b, alpha)
	# Side faces, only the ones turned toward the camera.
	for n: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if n.x * sin(_yaw) + n.z * cos(_yaw) >= -0.05:
			continue
		var a := base + Vector3(0.5 + n.x * 0.5 - n.z * 0.5, 0.0, 0.5 + n.z * 0.5 + n.x * 0.5)
		var b := base + Vector3(0.5 + n.x * 0.5 + n.z * 0.5, 0.0, 0.5 + n.z * 0.5 - n.x * 0.5)
		var shade := 0.62 if absf(n.x) > 0.5 else 0.78
		var poly := PackedVector2Array([
			_project(Vector3(a.x, top, a.z), centre),
			_project(Vector3(b.x, top, b.z), centre),
			_project(Vector3(b.x, -1.2, b.z), centre),
			_project(Vector3(a.x, -1.2, a.z), centre),
		])
		draw_colored_polygon(poly, Color(c.r * shade, c.g * shade, c.b * shade, alpha))

	var quad := PackedVector2Array([
		_project(Vector3(base.x, top, base.z), centre),
		_project(Vector3(base.x + 1.0, top, base.z), centre),
		_project(Vector3(base.x + 1.0, top, base.z + 1.0), centre),
		_project(Vector3(base.x, top, base.z + 1.0), centre),
	])
	draw_colored_polygon(quad, c)
	draw_polyline(quad + PackedVector2Array([quad[0]]),
		Color(0, 0, 0, 0.20 * alpha), 1.0)


## The four viewing planes themselves, as glowing frames around the island.
func _draw_plane_frames(centre: Vector2, mid: float) -> void:
	var r := mid + 2.2
	for v in 4:
		var ang := deg_to_rad(90.0 * v)
		var nx := -sin(ang)
		var nz := -cos(ang)
		var tx := cos(ang)
		var tz := -sin(ang)
		var active := (v == _view) and not _turning
		var col := MenuTheme.ACCENT if active else MenuTheme.LINE_HI
		var a := 0.85 if active else 0.22
		var pts := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1.0, -1.2), Vector2(1.0, -1.2),
				Vector2(1.0, 4.6), Vector2(-1.0, 4.6)]:
			var w := Vector3(nx * r + tx * corner.x * r, corner.y, nz * r + tz * corner.x * r)
			pts.append(_project(w, centre))
		pts.append(pts[0])
		draw_polyline(pts, Color(col.r, col.g, col.b, a), 2.0 if active else 1.0)


func _draw_player(centre: Vector2, mid: float, play: int, axis_is_z: bool) -> void:
	var x := mid
	var z := float(play)
	if not axis_is_z:
		x = float(play)
		z = mid
	var i := int(z) * GRID + int(x)
	var h: int = _heights[i] if i >= 0 and i < _heights.size() else 3
	var foot := _project(Vector3(x - mid + 0.5, float(h) * 0.55, z - mid + 0.5), centre)
	var w := _cell * 0.42
	var tall := _cell * 1.05
	draw_rect(Rect2(foot - Vector2(w * 0.5, tall), Vector2(w, tall)),
		Color(0.95, 0.78, 0.45, 0.95), true)
	draw_rect(Rect2(foot - Vector2(w * 0.5, tall), Vector2(w, tall)),
		Color(0.15, 0.10, 0.05, 0.9), false, 1.0)


func _draw_caption(rect: Rect2) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var name: String = Const.VIEW_NAMES[_view]
	var y := rect.size.y - 26.0
	draw_string(font, Vector2(0, y), "PLANE %d — %s" % [_view, name.to_upper()],
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, MenuTheme.FS_SMALL,
		Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, 0.85))
	draw_string(font, Vector2(0, y + 16.0), "Q / E flips the world · PgUp / PgDn shifts layer",
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, MenuTheme.FS_TINY, MenuTheme.TEXT_MUTE)
