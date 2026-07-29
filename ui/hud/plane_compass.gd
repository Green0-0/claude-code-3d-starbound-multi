## THE signature widget: a live diagram of the four viewing planes plus a strip
## of the voxel layers ahead of and behind the one the player stands in.
##
## Nothing else in the HUD has to teach a mechanic the player has never met
## before, so this widget is deliberately literal:
##
##   * The **world grid spins, the camera does not.** During a `Q`/`E` flip the
##     square rotates under a fixed camera icon, which is exactly what happens
##     on screen: the player never moves, the world re-reveals itself.
##   * The **layer strip** samples the voxels straight ahead of and behind the
##     player at their own height, so "PgDn goes into that wall / PgUp steps out
##     into open air" is readable at a glance, before the player tries it.
##   * The shaded wedge from the camera is the slab that is actually rendered
##     (`Const.SLAB_BEHIND` layers deep), so "the background *is* the layers
##     behind me" stops being an abstraction.
##
## Consumes: `view_flip_started`, `view_flip_finished`, `layer_changed`,
## `flip_blocked`, `block_changed`, `world_ready`.
class_name HudPlaneCompass
extends Control

const STRIP_FRONT := 4                 ## layers shown in front of the player
const STRIP_BEHIND := 10               ## layers shown behind the player
const HINT_USES := 4                   ## uses after which a key hint fades out

var _yaw_now := 0.0
var _blocked_t := 0.0
var _blocked_reason := ""
var _slide := 0.0                      ## 0..1 layer-strip slide animation
var _slide_dir := 1
var _last_layer := 0
var _flash := 0.0                      ## flip highlight
var _shake := 0.0
var _time := 0.0

var _flip_uses := 0
var _shift_uses := 0
var _flip_hint := 1.0
var _shift_hint := 1.0

## Cached voxel samples for the strip: layer offset -> {solid, color, free}.
var _samples: Array[Dictionary] = []
var _sample_age := 999.0
var _sample_key := Vector3i(9999, 9999, 9999)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_last_layer = View.layer
	_yaw_now = _yaw_of(View.view)
	Events.view_flip_started.connect(_on_flip_started)
	Events.view_flip_finished.connect(_on_flip_finished)
	Events.layer_changed.connect(_on_layer_changed)
	Events.flip_blocked.connect(_on_flip_blocked)
	Events.block_changed.connect(func(_p: Vector3i, _o: int, _n: int) -> void: _sample_age = 999.0)
	Events.world_ready.connect(func(_id: String) -> void: _sample_age = 999.0)


func _on_flip_started(_from: int, _to: int, _dir: int) -> void:
	_flip_uses += 1
	_flash = 1.0
	_sample_age = 999.0


func _on_flip_finished(_view: int) -> void:
	_sample_age = 999.0


func _on_layer_changed(layer: int, _view: int) -> void:
	_shift_uses += 1
	_slide = 1.0
	# Sliding the strip the same way the player moved keeps the diagram honest.
	_slide_dir = 1 if (layer - _last_layer) * View.depth_sign() > 0 else -1
	_last_layer = layer
	_sample_age = 999.0


func _on_flip_blocked(reason: String) -> void:
	_blocked_t = 1.0
	_blocked_reason = "BLOCKED" if reason == "occupied" else reason.to_upper()
	_shake = 1.0


# ------------------------------------------------------------------- updating
func _process(delta: float) -> void:
	_time += delta
	_yaw_now = _target_yaw()
	_blocked_t = maxf(0.0, _blocked_t - delta * 1.4)
	_flash = maxf(0.0, _flash - delta * 1.8)
	_shake = maxf(0.0, _shake - delta * 3.5)
	_slide = move_toward(_slide, 0.0, delta * 5.0)
	_flip_hint = move_toward(_flip_hint, 0.12 if _flip_uses >= HINT_USES else 1.0, delta * 0.7)
	_shift_hint = move_toward(_shift_hint, 0.12 if _shift_uses >= HINT_USES else 1.0, delta * 0.7)
	_sample_age += delta
	if _sample_age > 0.2:
		_resample()
	queue_redraw()


func _yaw_of(v: int) -> float:
	return deg_to_rad(90.0 * float(v))


## Eased yaw so the diagram snaps into the new plane exactly like the camera.
func _target_yaw() -> float:
	if View.flipping:
		return _yaw_of(View.flip_from) + deg_to_rad(90.0 * float(View.flip_dir)) * View.flip_eased()
	return _yaw_of(View.view)


## Probe the voxel column the player occupies in every nearby layer. Cheap:
## ~30 `get_block` calls, five times a second, and only when something moved.
func _resample() -> void:
	_sample_age = 0.0
	_samples.clear()
	var p := Game.player
	if p == null or not World.ready_flag:
		return
	var pos := p.global_position
	var key := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	_sample_key = key
	for off in range(-STRIP_FRONT, STRIP_BEHIND + 1):
		var depth := View.layer + off * View.depth_sign()
		var feet := Const.floor_v(View.with_depth(pos + Vector3(0, 0.3, 0), float(depth) + 0.5))
		var head := Const.floor_v(View.with_depth(pos + Vector3(0, 1.4, 0), float(depth) + 0.5))
		var b_feet := World.get_block(feet)
		var b_head := World.get_block(head)
		var floor_id := World.get_block(feet - Vector3i(0, 1, 0))
		var solid := Blocks.is_solid(b_feet) or Blocks.is_solid(b_head)
		var col := Color(0.10, 0.11, 0.15)
		var id := b_feet if b_feet != Const.AIR else b_head
		if id != Const.AIR:
			var bt := Blocks.get_type(id)
			if bt != null:
				col = bt.color
		_samples.append({
			"off": off, "layer": depth, "solid": solid, "color": col,
			"standable": (not solid) and Blocks.is_solid(floor_id),
		})


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	var shake := Vector2(sin(_time * 60.0) * _shake * 3.0, 0.0)
	var r := Rect2(shake, size)
	var body := HudTheme.framed_panel(self, r, "PERSPECTIVE", HudTheme.ACCENT)

	var strip_h := 40.0
	var hint_h := 30.0
	var diag := Rect2(body.position, Vector2(body.size.x, body.size.y - strip_h - hint_h - 6.0))
	_draw_diagram(diag)
	_draw_strip(Rect2(Vector2(body.position.x, diag.position.y + diag.size.y + 3.0),
		Vector2(body.size.x, strip_h)))
	_draw_hints(Rect2(Vector2(body.position.x, body.position.y + body.size.y - hint_h),
		Vector2(body.size.x, hint_h)))


# ------------------------------------------------------------ plane diagram
func _plan(centre: Vector2, x: float, z: float, ax: float, az: float) -> Vector2:
	var s := sin(_yaw_now)
	var c := cos(_yaw_now)
	return centre + Vector2((x * c - z * s) * ax, (x * s + z * c) * az)


func _draw_diagram(r: Rect2) -> void:
	var centre := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.46)
	var ax := minf(r.size.x * 0.34, 62.0)
	var az := ax * 0.5

	# The slab that is actually rendered: from the play layer away from the
	# camera. In diagram space "away from camera" is up.
	var slab := PackedVector2Array([
		centre + Vector2(-ax * 1.02, 0.0), centre + Vector2(ax * 1.02, 0.0),
		centre + Vector2(ax * 1.02, -az * 1.06), centre + Vector2(-ax * 1.02, -az * 1.06)])
	draw_colored_polygon(slab, HudTheme.with_alpha(HudTheme.ACCENT, 0.07))

	# Rotating world grid.
	var grid := HudTheme.with_alpha(HudTheme.EDGE_DIM, 0.55)
	for i in range(-2, 3):
		var f := float(i) * 0.5
		draw_line(_plan(centre, f, -1.0, ax, az), _plan(centre, f, 1.0, ax, az), grid, 1.0)
		draw_line(_plan(centre, -1.0, f, ax, az), _plan(centre, 1.0, f, ax, az), grid, 1.0)
	var corners := PackedVector2Array([
		_plan(centre, -1, -1, ax, az), _plan(centre, 1, -1, ax, az),
		_plan(centre, 1, 1, ax, az), _plan(centre, -1, 1, ax, az),
		_plan(centre, -1, -1, ax, az)])
	draw_polyline(corners, HudTheme.with_alpha(HudTheme.EDGE, 0.9), 1.5, true)

	# Cardinal letters ride the grid so the rotation is unmistakable.
	var view_name: String = Const.VIEW_NAMES[View.view]
	var letters := [["N", 0.0, -1.28], ["E", 1.28, 0.0], ["S", 0.0, 1.28], ["W", -1.28, 0.0]]
	for l: Array in letters:
		var glyph := String(l[0])
		var p := _plan(centre, float(l[1]), float(l[2]), ax, az)
		var col := HudTheme.ACCENT if glyph == view_name.substr(0, 1) else HudTheme.TEXT_FAINT
		var sz := HudTheme.text_size(glyph, 10)
		HudTheme.text(self, p - sz * 0.5, glyph, 10, col)

	# Fixed camera at the bottom, with its viewing cone. It never moves: the
	# player never moves during a flip either.
	var cam := centre + Vector2(0.0, az * 1.75)
	var cone := PackedVector2Array([cam,
		centre + Vector2(-ax * 1.05, -az * 1.05), centre + Vector2(ax * 1.05, -az * 1.05)])
	draw_colored_polygon(cone, HudTheme.with_alpha(HudTheme.ACCENT, 0.06 + 0.10 * _flash))
	draw_line(cam, centre + Vector2(-ax * 1.05, -az * 1.05),
		HudTheme.with_alpha(HudTheme.ACCENT, 0.35), 1.0)
	draw_line(cam, centre + Vector2(ax * 1.05, -az * 1.05),
		HudTheme.with_alpha(HudTheme.ACCENT, 0.35), 1.0)
	draw_colored_polygon(PackedVector2Array([
		cam + Vector2(-7, 4), cam + Vector2(7, 4), cam + Vector2(5, -4), cam + Vector2(-5, -4)]),
		HudTheme.ACCENT)
	draw_colored_polygon(PackedVector2Array([
		cam + Vector2(-4, -4), cam + Vector2(4, -4), cam + Vector2(0, -9)]), HudTheme.ACCENT)

	# Player, dead centre, and the depth axis running away from the camera.
	draw_line(centre, centre + Vector2(0, -az * 1.1),
		HudTheme.with_alpha(HudTheme.ACCENT_WARM, 0.55), 1.0)
	for i in range(1, 5):
		var y := centre.y - az * 0.22 * float(i)
		draw_line(Vector2(centre.x - 3, y), Vector2(centre.x + 3, y),
			HudTheme.with_alpha(HudTheme.ACCENT_WARM, 0.35), 1.0)
	HudTheme.glow(self, centre, 9.0, HudTheme.with_alpha(Color.WHITE, 0.35))
	draw_circle(centre, 3.2, Color.WHITE)
	draw_arc(centre, 6.0 + sin(_time * 3.0) * 0.8, 0.0, TAU, 18,
		HudTheme.with_alpha(HudTheme.ACCENT_WARM, 0.8), 1.4, true)

	# Plane name + index dots.
	var label := "%s  ·  view %d/4" % [View.view_name(), View.view + 1]
	var lsz := HudTheme.text_size(label, 11)
	HudTheme.text(self, Vector2(centre.x - lsz.x * 0.5, r.position.y + r.size.y - 13.0),
		label, 11, HudTheme.with_alpha(HudTheme.TEXT, 0.95), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 1)
	for v in 4:
		var dot := Vector2(centre.x - 15.0 + float(v) * 10.0, r.position.y + 4.0)
		var on := v == View.view
		draw_circle(dot, 3.0 if on else 2.0, HudTheme.ACCENT if on else HudTheme.EDGE_DIM)


# --------------------------------------------------------------- layer strip
func _draw_strip(r: Rect2) -> void:
	var count := STRIP_FRONT + STRIP_BEHIND + 1
	var cw := r.size.x / float(count)
	var ch := r.size.y - 13.0
	var top := r.position.y + 10.0

	HudTheme.text(self, r.position + Vector2(0, -2), "LAYERS", 8, HudTheme.TEXT_FAINT)
	var lbl := "depth %d" % View.layer
	var lsz := HudTheme.text_size(lbl, 8)
	HudTheme.text(self, Vector2(r.position.x + r.size.x - lsz.x, r.position.y - 2.0), lbl, 8,
		HudTheme.TEXT_FAINT)

	# The rendered slab behind the player, so "background = layers behind me".
	var slab_x := r.position.x + float(STRIP_FRONT) * cw
	var slab_w := minf(float(Const.SLAB_BEHIND + 1) * cw, r.size.x - float(STRIP_FRONT) * cw)
	draw_rect(Rect2(Vector2(slab_x, top - 3.0), Vector2(slab_w, ch + 6.0)),
		HudTheme.with_alpha(HudTheme.ACCENT, 0.06), true)

	# One-cell slide so a layer shift reads as motion, not a teleport.
	var slide := _slide * cw * float(_slide_dir)
	for s: Dictionary in _samples:
		var off: int = s["off"]
		var x := r.position.x + float(off + STRIP_FRONT) * cw + slide
		var cell := Rect2(Vector2(x + 1.0, top), Vector2(cw - 2.0, ch))
		var solid: bool = s["solid"]
		var col: Color = s["color"]
		if solid:
			# Distance fade mirrors the slab shader: further = dimmer.
			var fade := clampf(1.0 - float(maxi(0, off)) / float(Const.SLAB_BEHIND + 2), 0.25, 1.0)
			HudTheme.round_rect(self, cell, HudTheme.with_alpha(HudTheme.shade(col, fade), 0.95), 2.0)
		else:
			HudTheme.round_rect(self, cell, Color(0.06, 0.07, 0.10, 0.75), 2.0)
			var c := cell.position + cell.size * 0.5
			if bool(s["standable"]):
				draw_line(Vector2(cell.position.x + 2.0, c.y + cell.size.y * 0.28),
					Vector2(cell.position.x + cell.size.x - 2.0, c.y + cell.size.y * 0.28),
					HudTheme.with_alpha(HudTheme.GOOD, 0.55), 1.5)
			else:
				draw_circle(c, 1.2, HudTheme.with_alpha(HudTheme.TEXT_FAINT, 0.6))
		if off == 0:
			HudTheme.brackets(self, cell.grow(2.0), HudTheme.ACCENT_WARM, 4.0, 1.5)
			draw_circle(cell.position + cell.size * 0.5, 2.6, Color.WHITE)
		elif absi(off) == 1 and solid:
			# The move the player is about to try is blocked — say so early.
			var g := cell.grow(-2.0)
			draw_line(g.position, g.position + g.size, HudTheme.with_alpha(HudTheme.BAD, 0.9), 1.5)
			draw_line(g.position + Vector2(g.size.x, 0), g.position + Vector2(0, g.size.y),
				HudTheme.with_alpha(HudTheme.BAD, 0.9), 1.5)

	# Direction captions.
	HudTheme.text(self, Vector2(r.position.x, r.position.y + r.size.y - 3.0), "front", 8,
		HudTheme.with_alpha(HudTheme.TEXT_FAINT, 0.8))
	var bsz := HudTheme.text_size("behind", 8)
	HudTheme.text(self, Vector2(r.position.x + r.size.x - bsz.x, r.position.y + r.size.y - 3.0),
		"behind", 8, HudTheme.with_alpha(HudTheme.TEXT_FAINT, 0.8))

	if _blocked_t > 0.0:
		var t := HudTheme.with_alpha(HudTheme.BAD, clampf(_blocked_t, 0.0, 1.0))
		var tsz := HudTheme.text_size(_blocked_reason, 11)
		HudTheme.text(self, Vector2(r.position.x + (r.size.x - tsz.x) * 0.5, top + ch * 0.5 - 7.0),
			_blocked_reason, 11, t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 2)


# ---------------------------------------------------------------- key hints
## Key names come from the live `InputMap`, so the prompt never lies about the
## binding (the project ships `flip_left`/`flip_right` on Q/E and the depth
## actions on whatever `project.godot` has bound to `depth_in`/`depth_out`).
func _draw_hints(r: Rect2) -> void:
	var flip_keys := [HudTheme.key_label(&"flip_left", "Q"), HudTheme.key_label(&"flip_right", "E")]
	var shift_keys := [HudTheme.key_label(&"depth_out", "PgUp"), HudTheme.key_label(&"depth_in", "PgDn")]
	_key_hint(Vector2(r.position.x, r.position.y), flip_keys, "flip view", _flip_hint)
	_key_hint(Vector2(r.position.x, r.position.y + 15.0), shift_keys, "shift layer", _shift_hint)


func _key_hint(pos: Vector2, keys: Array, label: String, alpha: float) -> void:
	var pulse := 1.0
	if alpha > 0.5:
		pulse = 0.75 + 0.25 * sin(_time * 3.0)
	var a := alpha * pulse
	var x := pos.x
	for k: String in keys:
		var w := HudTheme.text_size(k, 9).x + 8.0
		var box := Rect2(Vector2(x, pos.y), Vector2(w, 13.0))
		HudTheme.panel(self, box, HudTheme.with_alpha(Color(0.16, 0.18, 0.24), a * 0.9),
			HudTheme.with_alpha(HudTheme.ACCENT, a * 0.8), 3, 1)
		HudTheme.text(self, Vector2(x + 4.0, pos.y + 1.0), k, 9,
			HudTheme.with_alpha(HudTheme.TEXT, a))
		x += w + 3.0
	HudTheme.text(self, Vector2(x + 2.0, pos.y + 1.0), label, 9,
		HudTheme.with_alpha(HudTheme.TEXT_DIM, a))
