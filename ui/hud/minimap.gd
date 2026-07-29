## Plane-slice minimap.
##
## The world is 3D but the player only ever reads one slice of it, so a top-down
## map would be a lie. This draws the *play layer* the way the camera sees it —
## a side elevation in plane space — with the layer immediately behind ghosted in
## underneath, which is exactly the foreground/background relationship the game
## is built on.
##
## Sampling is a coarse `World.get_block` sweep into a procedurally generated
## `ImageTexture`, rebuilt at most a few times a second and only when something
## actually changed (player crossed a cell, layer/view changed, or a nearby
## chunk went dirty).
##
## Consumes: `chunk_dirty`, `block_changed`, `layer_changed`,
## `view_flip_finished`, `world_ready`, `world_unloaded`.
class_name HudMinimap
extends Control

const CELLS_X := 64
const CELLS_Y := 48
const REBUILD_INTERVAL := 0.30
const BEHIND_SAMPLES := 3       ## how many layers back the ghost overlay probes

var _img: Image = null
var _tex: ImageTexture = null
var _accum := 0.0
var _dirty := true
var _last_cell := Vector2i(9999, 9999)
var _last_view := -1
var _last_layer := -99999
var _time := 0.0
var _blips: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_img = Image.create(CELLS_X, CELLS_Y, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	Events.chunk_dirty.connect(_on_chunk_dirty)
	Events.block_changed.connect(func(_p: Vector3i, _o: int, _n: int) -> void: _dirty = true)
	Events.layer_changed.connect(func(_l: int, _v: int) -> void: _dirty = true)
	Events.view_flip_finished.connect(func(_v: int) -> void: _dirty = true)
	Events.world_ready.connect(func(_id: String) -> void: _dirty = true)
	Events.world_unloaded.connect(_on_world_unloaded)


func _on_world_unloaded() -> void:
	if _img == null or _tex == null:
		return
	_img.fill(Color(0, 0, 0, 0))
	_tex.update(_img)
	_dirty = true


func _on_chunk_dirty(cpos: Vector3i) -> void:
	var p := Game.player
	if p == null:
		_dirty = true
		return
	# Only chunks anywhere near the visible window matter.
	var pc := Const.chunk_of(Const.floor_v(p.global_position))
	if absi(cpos.x - pc.x) <= 3 and absi(cpos.y - pc.y) <= 3 and absi(cpos.z - pc.z) <= 3:
		_dirty = true


# ------------------------------------------------------------------- updating
func _process(delta: float) -> void:
	_time += delta
	_accum += delta
	var p := Game.player
	if p != null:
		var lat := floori(View.lateral_of(p.global_position))
		var up := floori(p.global_position.y)
		var cell := Vector2i(lat, up)
		if cell != _last_cell or View.view != _last_view or View.layer != _last_layer:
			_last_cell = cell
			_last_view = View.view
			_last_layer = View.layer
			_dirty = true
	if _dirty and _accum >= REBUILD_INTERVAL:
		_accum = 0.0
		_dirty = false
		_rebuild()
		_collect_blips()
	queue_redraw()


func _rebuild() -> void:
	var p := Game.player
	if p == null or not World.ready_flag or _img == null:
		return
	var v := View.view
	var layer := View.layer
	var step := View.depth_sign()
	var lat0 := floori(View.lateral_of(p.global_position)) - CELLS_X / 2
	var up0 := floori(p.global_position.y) + CELLS_Y / 2

	for j in CELLS_Y:
		var up := up0 - j
		if up < 0 or up >= Const.WORLD_HEIGHT:
			for i in CELLS_X:
				_img.set_pixel(i, j, Color(0.02, 0.02, 0.04, 0.55))
			continue
		for i in CELLS_X:
			var lat := lat0 + i
			var pos := Const.floor_v(Const.from_plane(float(lat) + 0.5, float(up) + 0.5,
				float(layer) + 0.5, v))
			var id := World.get_block(pos)
			var col: Color
			if id != Const.AIR:
				col = _block_color(id, pos, up)
			else:
				col = _behind_color(pos, step)
			_img.set_pixel(i, j, col)
	_tex.update(_img)


## Play-layer block: its own colour, lit from above when open sky is adjacent.
func _block_color(id: int, pos: Vector3i, up: int) -> Color:
	var bt := Blocks.get_type(id)
	if bt == null:
		return Color(0.4, 0.4, 0.45, 1.0)
	var c := bt.color
	if bt.top_color.a > 0.0 and World.get_block(pos + Vector3i(0, 1, 0)) == Const.AIR:
		c = bt.top_color
	elif World.get_block(pos + Vector3i(0, 1, 0)) == Const.AIR:
		c = c.lightened(0.22)
	# A touch of vertical shading keeps large stone fields from turning to mush.
	var shade := 1.0 - float(absi(up % 8)) * 0.012
	if bt.emission > 0.0:
		c = c.lightened(0.35)
	return Color(c.r * shade, c.g * shade, c.b * shade, 1.0)


## Air in the play layer: ghost whatever sits in the layers behind it, which is
## precisely what the world renderer dims into the background.
func _behind_color(pos: Vector3i, step: int) -> Color:
	var axis := View.depth_axis()
	for k in range(1, BEHIND_SAMPLES + 1):
		var q := pos
		if axis == 0:
			q.x += step * k
		else:
			q.z += step * k
		var id := World.get_block(q)
		if id != Const.AIR:
			var bt := Blocks.get_type(id)
			var c := bt.color if bt != null else Color(0.4, 0.4, 0.45)
			var f := 0.34 - 0.07 * float(k - 1)
			return Color(c.r * f, c.g * f, c.b * f, 0.92)
	return Color(0.05, 0.07, 0.11, 0.55)


func _collect_blips() -> void:
	_blips.clear()
	var p := Game.player
	if p == null:
		return
	var half_lat := float(CELLS_X) * 0.5
	var half_up := float(CELLS_Y) * 0.5
	for e: VoxelEntity in Game.entities_in_radius(p.global_position, 48.0, &"entities"):
		if e == p or e.dead:
			continue
		if floori(View.depth_of(e.global_position)) != View.layer:
			continue
		var d_lat := View.lateral_of(e.global_position) - View.lateral_of(p.global_position)
		var d_up := e.global_position.y - p.global_position.y
		if absf(d_lat) > half_lat or absf(d_up) > half_up:
			continue
		var col := HudTheme.TEXT_DIM
		if e.faction == &"hostile":
			col = HudTheme.BAD
		elif e.faction == &"friendly" or e.faction == &"npc":
			col = HudTheme.GOOD
		_blips.append({"lat": d_lat, "up": d_up, "color": col})


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	var title := "LAYER %d · %s" % [View.layer, View.view_name()]
	var body := HudTheme.framed_panel(self, Rect2(Vector2.ZERO, size), title, HudTheme.ACCENT)
	if _tex == null:
		return

	var cell_w := body.size.x / float(CELLS_X)
	var cell_h := body.size.y / float(CELLS_Y)
	var scale := minf(cell_w, cell_h)
	var draw_size := Vector2(CELLS_X, CELLS_Y) * scale
	var origin := body.position + (body.size - draw_size) * 0.5
	var view_rect := Rect2(origin, draw_size)

	draw_rect(view_rect, Color(0.02, 0.025, 0.04, 0.9), true)
	draw_texture_rect(_tex, view_rect, false)

	# Horizon + centre guides.
	var centre := origin + draw_size * 0.5
	draw_line(Vector2(view_rect.position.x, centre.y),
		Vector2(view_rect.end.x, centre.y), HudTheme.with_alpha(HudTheme.ACCENT, 0.10), 1.0)
	draw_line(Vector2(centre.x, view_rect.position.y),
		Vector2(centre.x, view_rect.end.y), HudTheme.with_alpha(HudTheme.ACCENT, 0.10), 1.0)

	for b: Dictionary in _blips:
		var pos := centre + Vector2(float(b["lat"]) * scale, -float(b["up"]) * scale)
		if not view_rect.has_point(pos):
			continue
		var col: Color = b["color"]
		draw_circle(pos, 2.2, col)

	# The player: always dead centre, because the map follows the plane.
	var pulse := 0.55 + 0.45 * sin(_time * 3.2)
	HudTheme.glow(self, centre, 10.0, HudTheme.with_alpha(HudTheme.ACCENT_WARM, 0.25 * pulse))
	draw_circle(centre, 2.6, Color.WHITE)
	draw_arc(centre, 5.0, 0.0, TAU, 14, HudTheme.with_alpha(HudTheme.ACCENT_WARM, 0.9), 1.2, true)

	draw_rect(view_rect, HudTheme.with_alpha(HudTheme.EDGE_DIM, 0.8), false, 1.0)

	var p := Game.player
	if p != null:
		var pos_text := "%d, %d, %d" % [roundi(p.global_position.x), roundi(p.global_position.y),
			roundi(p.global_position.z)]
		var tsz := HudTheme.text_size(pos_text, 9)
		HudTheme.text(self, Vector2(view_rect.end.x - tsz.x - 2.0, view_rect.end.y - 12.0),
			pos_text, 9, HudTheme.with_alpha(HudTheme.TEXT_DIM, 0.9),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 1)
