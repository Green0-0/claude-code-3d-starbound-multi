## "Why is it black?" — the diagnostic the other nineteen agents will need.
##
## Gated entirely on `Game.debug_overlay` (toggled by the `debug_toggle`
## action in `core/main.gd`); costs nothing while it is off. When on it draws a
## slice of the light grid around the player *in plane space*, so it reads the
## same way in all four views, plus the manager's queue depths.
##
## Legend
##   digit      combined level 0..F after the daylight blend
##   colour     white = skylight is winning, orange = block light is winning
##   `#`        opaque voxel (light stops here)
##   `~`        chunk not loaded  ·  `?` chunk loaded but not lit yet
##
## Also useful from anywhere:
## [codeblock]
## Lighting.debug.dump(Vector3i(x, y, z))      # one voxel, to stdout
## Lighting.debug.probe_column(x, z)           # the whole vertical column
## [/codeblock]
class_name LitDebug
extends Node

const HEX := "0123456789ABCDEF"

## Half-width / half-height of the sampled slice, in voxels.
var half_width := 14
var half_height := 8
## Seconds between refreshes.
var interval := 0.2

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _timer := 0.0
var _built := false


func _ready() -> void:
	process_priority = 90


func _process(delta: float) -> void:
	if not Game.debug_overlay:
		if _layer != null and _layer.visible:
			_layer.visible = false
		return
	if not _built:
		_build()
	_layer.visible = true
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	_label.text = _compose()


func _build() -> void:
	_built = true
	_layer = CanvasLayer.new()
	_layer.layer = 3
	add_child(_layer)
	_panel = PanelContainer.new()
	# Pinned to the top-right corner and grown from its own minimum size, so
	# the panel is exactly as tall as the text it holds.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -8.0
	_panel.offset_right = -8.0
	_panel.offset_top = 8.0
	_panel.offset_bottom = 8.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.62)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override(&"panel", style)
	_layer.add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(410, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"normal_font_size", 11)
	_label.add_theme_font_size_override(&"mono_font_size", 11)
	_panel.add_child(_label)


# ------------------------------------------------------------------ rendering
func _compose() -> String:
	var st: Dictionary = Lighting.stats()
	var out := "[b]LIGHT[/b]  %s  day %.2f  view %s  layer %d\n" % [
		Game.time_string(), float(st["daylight"]), View.view_name(), View.layer]
	out += "chunks lit %d  queued %d  relight %d  nodes %d  ops %d\n" % [
		int(st["chunks_lit"]), int(st["queued_chunks"]), int(st["relight"]),
		int(st["pending_nodes"]), int(st["ops_last_frame"])]
	if Lighting.day_night != null:
		out += "sun %+.2f  %s  stars %.2f  dyn %d\n" % [
			Lighting.day_night.sun_elevation, Lighting.day_night.moon_phase_name(),
			Lighting.day_night.star_amount, LitDynamic.active()]
	if Lighting.planet != null:
		out += "planet '%s'  weather '%s' x%.2f\n" % [
			String(Lighting.planet.palette().key),
			String(Lighting.weather.current_weather) if Lighting.weather != null else "-",
			Lighting.weather.light_scale if Lighting.weather != null else 1.0]

	var p := Game.player
	if p == null or not World.ready_flag:
		return out + "[i]no player / world[/i]"
	var here := Const.floor_v(p.global_position)
	var view := View.view
	var lat0 := int(floor(Const.lateral_of(p.global_position, view)))
	var up0 := here.y
	var depth: float = float(View.layer)

	out += "[code]"
	for dy in range(half_height, -half_height - 1, -1):
		var row := ""
		for dx in range(-half_width, half_width + 1):
			row += _cell(Const.floor_v(
				Const.from_plane(float(lat0 + dx), float(up0 + dy), depth, view)), dx == 0 and dy == 0)
		out += row + "\n"
	out += "[/code]"
	out += "\n@%s  sky %d  blk %d  f %.2f" % [
		str(here), Lighting.sky_level_at(here), Lighting.block_level_at(here),
		Lighting.factor_at(here)]
	return out


func _cell(pos: Vector3i, is_player: bool) -> String:
	var n := World.normalize(pos)
	var c: Chunk = World.chunk_at_block(n)
	if c == null:
		return "[color=#334]~[/color]"
	if not c.lit:
		return "[color=#556]?[/color]"
	var i := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	if Blocks.is_opaque(c.blocks[i]) and not is_player:
		var lvl_op := Lighting.level_at(n)
		return "[color=#%s]#[/color]" % _shade(lvl_op)
	var byte: int = c.light[i]
	var sky: int = byte >> 4
	var blk: int = byte & 15
	var lvl: int = Lighting.level_at(n)
	var ch := HEX[clampi(lvl, 0, 15)]
	if is_player:
		return "[color=#ff4de0]@[/color]"
	if blk > int(round(float(sky) * Lighting.daylight())):
		return "[color=#ffb040]%s[/color]" % ch
	return "[color=#%s]%s[/color]" % [_shade(lvl), ch]


func _shade(level: int) -> String:
	var v := clampi(40 + level * 14, 0, 255)
	return "%02x%02x%02x" % [v, v, mini(255, v + 12)]


# ------------------------------------------------------------------- probes
## Print everything known about one voxel.
func dump(pos: Vector3i) -> void:
	var n := World.normalize(pos)
	var c: Chunk = World.chunk_at_block(n)
	if c == null:
		print("[Lighting] %s: chunk not loaded" % str(n))
		return
	var i := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
	var id: int = c.blocks[i]
	var bt := Blocks.get_type(id)
	print("[Lighting] %s block=%s(%d) opacity=%d emit=%d sky=%d blk=%d combined=%d factor=%.3f lit=%s" % [
		str(n), String(bt.name), id,
		Lighting.flood.opacity[id] if id < Lighting.flood.opacity.size() else -1,
		Lighting.flood.emission[id] if id < Lighting.flood.emission.size() else -1,
		c.light[i] >> 4, c.light[i] & 15, Lighting.level_at(n), Lighting.factor_at(n),
		str(c.lit)])


## Print the skylight profile of a whole column — the fastest way to find out
## why a cave is dark or why the surface never got lit.
func probe_column(x: int, z: int) -> void:
	var lines := PackedStringArray()
	for y in range(Const.WORLD_HEIGHT - 1, -1, -1):
		var p := World.normalize(Vector3i(x, y, z))
		var c: Chunk = World.chunk_at_block(p)
		if c == null:
			continue
		var i := ((p.y & 15) << 8) | ((p.z & 15) << 4) | (p.x & 15)
		var byte: int = c.light[i]
		if byte == 0 and c.blocks[i] == Const.AIR:
			continue
		lines.append("y=%3d %-14s sky=%2d blk=%2d" % [
			y, String(Blocks.get_type(c.blocks[i]).name), byte >> 4, byte & 15])
	print("[Lighting] column (%d, %d)\n%s" % [x, z, "\n".join(lines)])


## Force the whole loaded world to re-flood. Bound to nothing; call it from the
## remote inspector when something looks wrong.
func relight_world() -> void:
	Lighting.relight_all()
	Events.toast("Lighting: re-flooding %d chunks" % World.chunks.size(), "info")
