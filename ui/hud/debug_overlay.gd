## Developer readout, gated on `Game.debug_overlay` (toggled by the
## `debug_toggle` action in `main.gd`).
##
## Shows frame timing with a rolling graph, the player's world/plane/depth
## coordinates, the perspective state machine, chunk and entity counts, the
## biome under the player, and the time of day. Everything optional is probed
## defensively — `PlanetGen` is another agent's module and may expose no biome
## query at all, in which case the row reads "n/a" instead of erroring.
class_name HudDebugOverlay
extends Control

const GRAPH_SAMPLES := 96
const REFRESH := 0.2

var _fps_history: PackedFloat32Array = PackedFloat32Array()
var _lines: Array[Dictionary] = []
var _accum := 999.0
var _biome := "n/a"
var _biome_chunk := Vector3i(9999, 9999, 9999)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_history.resize(GRAPH_SAMPLES)
	for i in GRAPH_SAMPLES:
		_fps_history[i] = 60.0


func _process(delta: float) -> void:
	visible = Game.debug_overlay
	if not visible:
		return
	for i in range(GRAPH_SAMPLES - 1):
		_fps_history[i] = _fps_history[i + 1]
	_fps_history[GRAPH_SAMPLES - 1] = 1.0 / maxf(0.0001, delta)
	_accum += delta
	if _accum >= REFRESH:
		_accum = 0.0
		_collect()
	queue_redraw()


# --------------------------------------------------------------- data probing
func _collect() -> void:
	_lines.clear()
	var fps := Engine.get_frames_per_second()
	_row("fps", "%d  (%.1f ms)" % [fps, 1000.0 / maxf(1.0, float(fps))],
		HudTheme.GOOD if fps >= 55 else (HudTheme.WARN if fps >= 30 else HudTheme.BAD))

	var p := Game.player
	if p != null:
		var w := p.global_position
		var b := Const.floor_v(w)
		_row("pos", "%.2f %.2f %.2f" % [w.x, w.y, w.z])
		_row("block", "%d %d %d" % [b.x, b.y, b.z])
		var pl := View.to_plane(w)
		_row("plane", "lat %.2f  up %.2f  depth %.2f" % [pl.x, pl.y, View.depth_of(w)])
		_row("vel", "%.2f %.2f %.2f  %s" % [p.velocity.x, p.velocity.y, p.velocity.z,
			"floor" if p.on_floor else "air"])
		_row("health", "%.0f / %.0f" % [p.health, p.max_health])
	else:
		_row("player", "none", HudTheme.BAD)

	var vstate := "settled"
	if View.flipping:
		vstate = "flipping %.0f%%" % (View.flip_t * 100.0)
	elif View.shifting:
		vstate = "shifting %.0f%%" % (View.shift_t * 100.0)
	_row("view", "%d %s  ·  %s" % [View.view, View.view_name(), vstate], HudTheme.ACCENT)
	_row("layer", "%d  (axis %s, sign %+d)" % [View.layer,
		"X" if View.depth_axis() == 0 else "Z", View.depth_sign()], HudTheme.ACCENT)

	var planet := World.planet_id if not World.planet_id.is_empty() else "-"
	_row("world", "%s  %dx%d  seed %d" % [planet, World.size_x, World.size_z, World.seed_value])
	_row("chunks", "%d loaded" % World.chunks.size())
	_row("entities", "%d" % get_tree().get_nodes_in_group(&"entities").size())
	_row("biome", _probe_biome())
	_row("time", "%s  day %d  daylight %.2f%s" % [Game.time_string(), Game.day, Game.daylight,
		"  (night)" if Game.is_night() else ""])
	_row("stats", "mined %d  placed %d  kills %d  flips %d" % [
		int(Game.stats.get("blocks_mined", 0)), int(Game.stats.get("blocks_placed", 0)),
		int(Game.stats.get("monsters_killed", 0)), int(Game.stats.get("flips", 0))])
	_row("render", "%d draw calls  %d nodes" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	_row("memory", "%.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))


func _row(key: String, value: String, col: Color = HudTheme.TEXT) -> void:
	_lines.append({"k": key, "v": value, "c": col})


## `PlanetGen` belongs to the worldgen agent; we do not know whether it exposes
## a biome query, nor its arity, so both are discovered from the method list.
func _probe_biome() -> String:
	var p := Game.player
	if p == null:
		return "n/a"
	var cpos := Const.chunk_of(Const.floor_v(p.global_position))
	if cpos == _biome_chunk:
		return _biome
	_biome_chunk = cpos
	_biome = "n/a"
	var bp := Const.floor_v(p.global_position)
	for m: StringName in [&"biome_at", &"biome_for", &"get_biome", &"biome"]:
		var argc := _argc(PlanetGen, m)
		var v: Variant = null
		if argc == 2:
			v = PlanetGen.call(m, bp.x, bp.z)
		elif argc == 1:
			v = PlanetGen.call(m, bp)
		else:
			continue
		if v is String and not String(v).is_empty():
			_biome = String(v)
			return _biome
		var o := v as Object
		if o != null:
			for prop: StringName in [&"display_name", &"name", &"id"]:
				var nv: Variant = o.get(prop)
				if nv is String and not String(nv).is_empty():
					_biome = String(nv)
					return _biome
	var meta: Variant = World.planet.get("biome")
	if meta is String:
		_biome = String(meta)
	return _biome


static func _argc(o: Object, m: StringName) -> int:
	if o == null or not o.has_method(m):
		return -1
	for d: Dictionary in o.get_method_list():
		if String(d.get("name", "")) == String(m):
			var args: Array = d.get("args", [])
			return args.size()
	return -1


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	var h := 26.0 + float(_lines.size()) * 13.0 + 34.0
	var r := Rect2(Vector2.ZERO, Vector2(size.x, minf(size.y, h)))
	var title := "DEBUG  ·  %s" % HudTheme.key_label(&"debug_toggle", "F3")
	var body := HudTheme.framed_panel(self, r, title, HudTheme.GOOD, 0.95)

	var y := body.position.y
	for l: Dictionary in _lines:
		if y > body.position.y + body.size.y - 12.0:
			break
		HudTheme.text(self, Vector2(body.position.x, y), String(l["k"]), 10, HudTheme.TEXT_FAINT)
		var col: Color = l["c"]
		HudTheme.text(self, Vector2(body.position.x + 58.0, y), String(l["v"]), 10, col)
		y += 13.0

	_draw_graph(Rect2(Vector2(body.position.x, y + 4.0), Vector2(body.size.x, 26.0)))


func _draw_graph(r: Rect2) -> void:
	if r.size.y < 8.0 or r.position.y + r.size.y > size.y:
		return
	draw_rect(r, Color(0.02, 0.03, 0.05, 0.6), true)
	var pts := PackedVector2Array()
	for i in GRAPH_SAMPLES:
		var f := clampf(_fps_history[i] / 120.0, 0.0, 1.0)
		pts.append(Vector2(r.position.x + r.size.x * float(i) / float(GRAPH_SAMPLES - 1),
			r.position.y + r.size.y * (1.0 - f)))
	draw_polyline(pts, HudTheme.with_alpha(HudTheme.GOOD, 0.9), 1.0, true)
	# 60 fps reference line.
	var y60 := r.position.y + r.size.y * 0.5
	draw_line(Vector2(r.position.x, y60), Vector2(r.end.x, y60),
		HudTheme.with_alpha(HudTheme.EDGE_DIM, 0.7), 1.0)
	HudTheme.text(self, Vector2(r.position.x + 2.0, r.position.y), "120", 8, HudTheme.TEXT_FAINT)
	HudTheme.text(self, Vector2(r.position.x + 2.0, y60 - 9.0), "60", 8, HudTheme.TEXT_FAINT)
