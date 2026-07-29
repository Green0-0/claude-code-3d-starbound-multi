## Star map. The `space/` module owns the universe; this panel draws it and
## asks `Game.travel_to_planet(id)` to move.
##
## Preferred data path (all optional, all guarded):
## [codeblock]
##   Universe.known_systems()            -> Array[String]
##   Universe.system_info(id)            -> {id,name,star_color,pos,threat,bodies}
##   Universe.system_body_ids(id)        -> Array[String]
##   Universe.body_info(id)              -> {name,type,type_name,threat,landable,
##                                           orbit_radius,orbit_angle,color,
##                                           size_px,moons,description}
##   Universe.moon_ids(body_id)          -> Array[String]
##   Universe.planet_meta(id)            -> landing metadata
##   Universe.scan_of(id) / scan_report(id)
##   Universe.can_travel_to(id)          -> {ok,reason,fuel,have,threat,ftl,...}
##   Universe.fuel_cost_to(id)           -> int
##   Universe.star_map_snapshot()        -> {fuel,fuel_capacity,ftl_tier,...}
##   Universe.select(id) / current_body_id() / current_system_id()
## [/codeblock]
##
## Fallback path: `Universe.systems` / `Universe.planets` as plain dictionaries,
## then a single synthetic system holding whatever planets exist. With the
## shipped stub that is one system with one planet, drawn correctly.
extends MenuPanel

const ORBIT_BASE := 52.0
const ORBIT_STEP := 32.0

var _systems: Array[Dictionary] = []       ## [{id, name, star_color, bodies}]
var _system_index: int = 0
var _selected: Dictionary = {}
var _canvas: Control = null
var _card: VBoxContainer = null
var _spin: float = 0.0
var _system_label: Label = null
var _fuel_label: Label = null
var _rich: bool = false                    ## true when the real space API is up


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.72
	placement = "fill"
	anim = "fade"
	group = "gameplay"


func _build() -> void:
	_load_universe()
	var body := frame("Star Map", Vector2(0, 0))

	var columns := MenuWidgets.row(MenuTheme.GAP + 4)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)

	var map_holder := PanelContainer.new()
	map_holder.theme_type_variation = &"InsetPanel"
	map_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_holder.clip_contents = true
	columns.add_child(map_holder)

	var stars := TextureRect.new()
	stars.texture = MenuTheme.starfield_texture(512, 288, 771)
	stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stars.stretch_mode = TextureRect.STRETCH_SCALE
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_holder.add_child(stars)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_map_input)
	map_holder.add_child(_canvas)

	var side := MenuWidgets.col()
	side.custom_minimum_size = Vector2(330, 0)
	columns.add_child(side)

	var nav := MenuWidgets.row(4)
	nav.add_child(MenuWidgets.small_button("‹", func() -> void: _cycle_system(-1)))
	_system_label = MenuWidgets.label("", &"SmallLabel")
	_system_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_system_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_system_label)
	nav.add_child(MenuWidgets.small_button("›", func() -> void: _cycle_system(1)))
	side.add_child(nav)

	_fuel_label = MenuWidgets.label("", &"TinyLabel")
	_fuel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(_fuel_label)
	side.add_child(MenuWidgets.rule())

	_card = MenuWidgets.col()
	side.add_child(MenuWidgets.scroll(_card))

	_focus_current_system()
	_update_header()
	_fill_card()


func _process(delta: float) -> void:
	_spin += delta * 0.12
	if _canvas != null:
		_canvas.queue_redraw()


# =============================================================== universe data
func _has(method: StringName) -> bool:
	return Universe != null and Universe.has_method(method)


func _load_universe() -> void:
	_systems.clear()
	_rich = _has(&"known_systems") and _has(&"body_info") and _has(&"system_body_ids")
	if _rich:
		_load_rich()
		if not _systems.is_empty():
			return
		_rich = false
	_load_plain()


func _load_rich() -> void:
	var ids: Variant = Universe.call(&"known_systems")
	if not (ids is Array):
		return
	for sid: Variant in (ids as Array):
		var system_id := String(sid)
		var info: Dictionary = Universe.call(&"system_info", system_id) \
			if _has(&"system_info") else {}
		var bodies: Array[Dictionary] = []
		var body_ids: Variant = Universe.call(&"system_body_ids", system_id)
		if body_ids is Array:
			for bid: Variant in (body_ids as Array):
				bodies.append(_body(String(bid)))
				if _has(&"moon_ids"):
					var moons: Variant = Universe.call(&"moon_ids", String(bid))
					if moons is Array:
						for mid: Variant in (moons as Array):
							var moon := _body(String(mid))
							moon["is_moon"] = true
							bodies.append(moon)
		_systems.append({
			"id": system_id,
			"name": String(info.get("name", system_id.capitalize())),
			"star_color": info.get("star_color", Color(1.0, 0.92, 0.72)),
			"threat": int(info.get("threat", 1)),
			"bodies": bodies,
		})


## One body, normalised. Merges `body_info` with `planet_meta` and whatever the
## current scan level has revealed.
func _body(id: String) -> Dictionary:
	var b: Dictionary = Universe.call(&"body_info", id) if _has(&"body_info") else {}
	var meta: Dictionary = Universe.call(&"planet_meta", id) if _has(&"planet_meta") else {}
	var scan := int(Universe.call(&"scan_of", id)) if _has(&"scan_of") else 2
	var report: Dictionary = Universe.call(&"scan_report", id) \
		if _has(&"scan_report") and scan > 0 else {}

	var resources: Array = report.get("resources", meta.get("resources", []))
	var biomes: Array = report.get("biomes", [])
	var biome_names := PackedStringArray()
	for e: Variant in biomes:
		if e is Dictionary:
			biome_names.append(String((e as Dictionary).get("key", "")))
		else:
			biome_names.append(String(e))

	return {
		"id": id,
		"name": String(b.get("name", meta.get("name", id.capitalize()))),
		"kind": String(b.get("kind", "planet")),
		"type": String(b.get("type", meta.get("type", "barren"))),
		"type_name": String(b.get("type_name", String(b.get("type", "barren")).capitalize())),
		"threat": int(b.get("threat", meta.get("threat", 1))),
		"landable": bool(b.get("landable", not meta.is_empty())),
		"description": String(b.get("description", "")),
		"orbit_index": int(b.get("orbit_index", 1)),
		"orbit_radius": float(b.get("orbit_radius", 0.0)),
		"orbit_angle": float(b.get("orbit_angle", 0.0)),
		"color": b.get("color", _type_color(String(b.get("type", "barren")))),
		"size_px": float(b.get("size_px", 1.0)),
		"gravity": float(meta.get("gravity", 1.0)),
		"day_length": float(meta.get("day_length", 1.0)),
		"breathable": bool(meta.get("breathable", true)),
		"size_x": int(meta.get("size_x", Const.PLANET_SIZE_DEFAULT)),
		"size_z": int(meta.get("size_z", Const.PLANET_SIZE_DEFAULT)),
		"resources": resources,
		"biomes": biome_names,
		"scan": scan,
		"visited": bool(Universe.call(&"is_visited", id)) if _has(&"is_visited") else false,
		"is_moon": false,
	}


## Stub-friendly path: read the plain `systems` / `planets` dictionaries.
func _load_plain() -> void:
	var planets: Array[Dictionary] = []
	if Universe != null:
		var p: Variant = Universe.get(&"planets")
		if p is Dictionary:
			for k: Variant in (p as Dictionary):
				planets.append(_plain_body(String(k), (p as Dictionary)[k]))
		elif p is Array:
			for e: Variant in (p as Array):
				planets.append(_plain_body("", e))
	_systems.append({
		"id": "local", "name": "Local Cluster",
		"star_color": Color(1.0, 0.92, 0.72), "threat": 1, "bodies": planets,
	})


func _plain_body(id: String, entry: Variant) -> Dictionary:
	var src: Dictionary = entry if entry is Dictionary else {}
	var body_id := String(src.get("id", id))
	var kind := String(src.get("type", src.get("biome", "barren")))
	return {
		"id": body_id,
		"name": String(src.get("name", body_id.capitalize())),
		"kind": "planet",
		"type": kind,
		"type_name": kind.capitalize(),
		"threat": int(src.get("threat", 1)),
		"landable": true,
		"description": "",
		"orbit_index": _systems.size() + 1,
		"orbit_radius": 0.0,
		"orbit_angle": 0.0,
		"color": _type_color(kind),
		"size_px": 1.0,
		"gravity": float(src.get("gravity", 1.0)),
		"day_length": float(src.get("day_length", 1.0)),
		"breathable": bool(src.get("breathable", true)),
		"size_x": int(src.get("size_x", Const.PLANET_SIZE_DEFAULT)),
		"size_z": int(src.get("size_z", Const.PLANET_SIZE_DEFAULT)),
		"resources": src.get("resources", []),
		"biomes": PackedStringArray(),
		"scan": 2,
		"visited": false,
		"is_moon": false,
	}


func _current_system() -> Dictionary:
	if _systems.is_empty():
		return {}
	return _systems[clampi(_system_index, 0, _systems.size() - 1)]


## Open on the system the player is actually in.
func _focus_current_system() -> void:
	if not _has(&"current_system_id"):
		return
	var here := String(Universe.call(&"current_system_id"))
	for i in _systems.size():
		if String(_systems[i]["id"]) == here:
			_system_index = i
			return


func _cycle_system(dir: int) -> void:
	if _systems.size() <= 1:
		return
	_system_index = wrapi(_system_index + dir, 0, _systems.size())
	_selected = {}
	_update_header()
	_fill_card()
	Events.system_scanned.emit(String(_current_system().get("id", "")))


func _update_header() -> void:
	if _system_label != null:
		var sys := _current_system()
		_system_label.text = "%s   (%d/%d)" % [
			String(sys.get("name", "—")), _system_index + 1, maxi(1, _systems.size())]
	if _fuel_label == null:
		return
	if _has(&"star_map_snapshot"):
		var snap: Dictionary = Universe.call(&"star_map_snapshot")
		_fuel_label.text = "fuel %d / %d   ·   FTL tier %d" % [
			int(snap.get("fuel", 0)), int(snap.get("fuel_capacity", 0)),
			int(snap.get("ftl_tier", 0))]
	else:
		_fuel_label.text = ""


# ==================================================================== drawing
func _planet_positions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _canvas == null:
		return out
	var centre := _canvas.size * 0.5
	var span := minf(_canvas.size.x, _canvas.size.y * 1.9) * 0.5 - 30.0
	var bodies: Array = _current_system().get("bodies", [])
	for i in bodies.size():
		var b: Dictionary = bodies[i]
		var norm := float(b.get("orbit_radius", 0.0))
		var radius := norm * span if norm > 0.0 else ORBIT_BASE + i * ORBIT_STEP
		radius = minf(radius, maxf(40.0, span))
		var angle: float = float(b.get("orbit_angle", 0.0)) \
			+ _spin / (1.0 + float(b.get("orbit_index", i + 1)) * 0.4)
		if bool(b.get("is_moon", false)):
			radius += 14.0
			angle += 1.1
		out.append({
			"planet": b,
			"pos": centre + Vector2(cos(angle) * radius, sin(angle) * radius * 0.52),
			"radius": radius,
			"size": clampf(6.0 + float(b.get("size_px", 1.0)) * 4.0, 5.0, 16.0),
		})
	return out


func _draw_map() -> void:
	if _canvas.size.x < 40.0:
		return
	var centre := _canvas.size * 0.5
	var entries := _planet_positions()

	for e: Dictionary in entries:
		var r: float = e["radius"]
		_draw_ellipse(centre, r, r * 0.52, Color(1, 1, 1, 0.09))

	var star_tint: Color = _current_system().get("star_color", Color(1.0, 0.92, 0.72))
	_canvas.draw_texture_rect(MenuTheme.glow_texture(112, star_tint, 2.6),
		Rect2(centre - Vector2(56, 56), Vector2(112, 112)), false)
	_canvas.draw_circle(centre, 11.0, star_tint)

	var current_id := _current_body_id()
	var font := _canvas.get_theme_default_font()

	for e: Dictionary in entries:
		var p: Dictionary = e["planet"]
		var pos: Vector2 = e["pos"]
		var size: float = e["size"]
		var col: Color = p.get("color", MenuTheme.TEXT_DIM)
		if not bool(p.get("landable", true)):
			col = col.lerp(MenuTheme.TEXT_MUTE, 0.45)
		_canvas.draw_circle(pos, size + 1.0, Color(0, 0, 0, 0.6))
		_canvas.draw_circle(pos, size, col)
		_canvas.draw_circle(pos - Vector2(size * 0.3, size * 0.3), size * 0.34,
			Color(1, 1, 1, 0.20))
		if int(p.get("scan", 2)) <= 0:
			_canvas.draw_arc(pos, size + 3.0, 0.0, TAU, 20, Color(1, 1, 1, 0.25), 1.0)

		if String(p["id"]) == current_id:
			_canvas.draw_arc(pos, size + 6.0, 0.0, TAU, 24, MenuTheme.GOOD, 2.0)
		if String(_selected.get("id", "")) == String(p["id"]):
			_canvas.draw_arc(pos, size + 9.0, 0.0, TAU, 28, MenuTheme.ACCENT, 2.0)

		if font != null:
			_canvas.draw_string(font, pos + Vector2(-48, size + 16), String(p["name"]),
				HORIZONTAL_ALIGNMENT_CENTER, 96, MenuTheme.FS_TINY,
				MenuTheme.TEXT if String(p["id"]) == current_id else MenuTheme.TEXT_DIM)


func _current_body_id() -> String:
	if _has(&"current_body_id"):
		return String(Universe.call(&"current_body_id"))
	return World.planet_id if World != null else ""


func _draw_ellipse(centre: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * float(i) / 48.0
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	_canvas.draw_polyline(pts, col, 1.0)


func _type_color(kind: String) -> Color:
	match kind:
		"forest", "jungle", "garden": return Color(0.36, 0.70, 0.35)
		"desert", "arid": return Color(0.83, 0.72, 0.42)
		"ocean", "water": return Color(0.30, 0.55, 0.85)
		"tundra", "ice", "arctic": return Color(0.72, 0.86, 0.95)
		"volcanic", "magma": return Color(0.85, 0.35, 0.20)
		"toxic", "swamp": return Color(0.55, 0.75, 0.25)
		"barren", "moon", "rock": return Color(0.60, 0.58, 0.55)
		"alien", "gas": return Color(0.80, 0.60, 0.85)
		"ruins": return Color(0.70, 0.65, 0.50)
		_: return Color(0.62, 0.66, 0.75)


func _on_map_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var best: Dictionary = {}
	var best_d := 24.0
	for e: Dictionary in _planet_positions():
		var epos: Vector2 = e["pos"]
		var d := epos.distance_to(mb.position)
		if d < best_d:
			best_d = d
			best = e["planet"]
	if best.is_empty():
		return
	_selected = best
	if _has(&"select"):
		Universe.call(&"select", String(best["id"]))
	Events.planet_selected.emit(String(best["id"]))
	_fill_card()


# ================================================================= planet card
func _fill_card() -> void:
	if _card == null:
		return
	MenuWidgets.clear(_card)
	if _selected.is_empty():
		_card.add_child(MenuWidgets.placeholder(
			"Click a world to inspect it.\n\nOrbits are drawn to scale of interest,\nnot of physics."))
		return

	var p := _selected
	var here: bool = _current_body_id() == String(p["id"])

	_card.add_child(MenuWidgets.label(String(p["name"]), &"HeadLabel"))
	var badges := MenuWidgets.row(4)
	badges.add_child(MenuWidgets.badge(String(p["type_name"]),
		p.get("color", MenuTheme.TEXT_DIM)))
	badges.add_child(MenuWidgets.badge(_threat_label(int(p["threat"])),
		_threat_color(int(p["threat"]))))
	if here:
		badges.add_child(MenuWidgets.badge("you are here", MenuTheme.GOOD))
	elif bool(p.get("visited", false)):
		badges.add_child(MenuWidgets.badge("visited", MenuTheme.CYAN))
	badges.add_child(MenuWidgets.spacer())
	_card.add_child(badges)

	if String(p.get("description", "")) != "":
		_card.add_child(MenuWidgets.paragraph(String(p["description"]), &"TinyLabel"))

	_card.add_child(MenuWidgets.rule())
	if not bool(p.get("landable", true)):
		_card.add_child(MenuWidgets.paragraph(
			"No landing site — this body can only be observed from orbit.",
			&"BadLabel"))
	else:
		_card.add_child(MenuWidgets.stat_row("Gravity", "%.2f g" % float(p["gravity"])))
		_card.add_child(MenuWidgets.stat_row("Day length", "%.2f x" % float(p["day_length"])))
		_card.add_child(MenuWidgets.stat_row("Atmosphere",
			"breathable" if bool(p["breathable"]) else "hostile",
			MenuTheme.GOOD if bool(p["breathable"]) else MenuTheme.BAD))
		_card.add_child(MenuWidgets.stat_row("Circumference",
			"%d x %d" % [int(p["size_x"]), int(p["size_z"])]))

	var biomes: PackedStringArray = p.get("biomes", PackedStringArray())
	if not biomes.is_empty():
		_card.add_child(MenuWidgets.rule())
		_card.add_child(MenuWidgets.label("Biomes", &"TinyLabel"))
		var brow := MenuWidgets.row(4)
		for b: String in biomes:
			brow.add_child(MenuWidgets.badge(b.capitalize(), MenuTheme.GOOD))
		_card.add_child(brow)

	_card.add_child(MenuWidgets.rule())
	_card.add_child(MenuWidgets.label("Known resources", &"TinyLabel"))
	var res: Variant = p.get("resources", [])
	if res is Array and not (res as Array).is_empty():
		var wrap := MenuWidgets.row(4)
		for r: Variant in (res as Array):
			wrap.add_child(MenuWidgets.badge(String(r).capitalize().replace("_", " "),
				MenuTheme.CYAN))
		_card.add_child(wrap)
	elif int(p.get("scan", 2)) < 2:
		_card.add_child(MenuWidgets.label(
			"Deep scan required (scan level %d/2)." % int(p.get("scan", 0)), &"TinyLabel"))
	else:
		_card.add_child(MenuWidgets.label("Unsurveyed — land and find out.", &"TinyLabel"))

	_card.add_child(MenuWidgets.rule())
	_card.add_child(_travel_block(String(p["id"]), String(p["name"]), here))
	_card.add_child(MenuWidgets.spacer())


func _travel_block(planet_id: String, planet_name: String, here: bool) -> Control:
	var c := MenuWidgets.col(4)
	var verdict := _travel_check(planet_id)
	c.add_child(MenuWidgets.stat_row("Fuel cost", "%d" % int(verdict.get("fuel", 0)),
		MenuTheme.WARN))
	if verdict.has("have"):
		c.add_child(MenuWidgets.stat_row("In tank", "%d" % int(verdict["have"])))

	var button := MenuWidgets.button("Already here" if here else "Travel",
		func() -> void: _travel(planet_id, planet_name), &"AccentButton")
	button.disabled = here or not bool(verdict.get("ok", true))
	button.custom_minimum_size = Vector2(0, 38)
	c.add_child(button)

	var reason := String(verdict.get("reason", ""))
	if not here and reason != "":
		var l := MenuWidgets.paragraph(reason, &"TinyLabel")
		l.add_theme_color_override(&"font_color", MenuTheme.BAD)
		c.add_child(l)
	var advice := String(verdict.get("armour_advice", ""))
	if advice != "":
		c.add_child(MenuWidgets.paragraph(advice, &"TinyLabel"))
	c.add_child(MenuWidgets.label(
		"Travelling saves and unloads the world you are on.", &"TinyLabel"))
	return c


func _travel_check(planet_id: String) -> Dictionary:
	if _has(&"can_travel_to"):
		var v: Variant = Universe.call(&"can_travel_to", planet_id)
		if v is Dictionary:
			return v as Dictionary
	var cost := 0
	if _has(&"fuel_cost_to"):
		cost = int(Universe.call(&"fuel_cost_to", planet_id))
	else:
		var from := World.planet_id if World != null else ""
		cost = 0 if from == planet_id else 5 + absi((from + planet_id).hash()) % 20
	return {"ok": true, "reason": "", "fuel": cost}


func _threat_label(threat: int) -> String:
	if _has(&"threat_name"):
		return "%s (%d)" % [String(Universe.call(&"threat_name", threat)), threat]
	return "Threat %d" % threat


func _threat_color(threat: int) -> Color:
	if _has(&"threat_color"):
		return Universe.call(&"threat_color", threat)
	if threat <= 1:
		return MenuTheme.GOOD
	if threat <= 3:
		return MenuTheme.WARN
	return MenuTheme.BAD


func _travel(planet_id: String, planet_name: String) -> void:
	var verdict := _travel_check(planet_id)
	if not bool(verdict.get("ok", true)):
		Events.toast(String(verdict.get("reason", "Cannot travel there.")), "warn")
		return
	var yes: bool = await UI.confirm("Travel to %s" % planet_name,
		"Your ship burns %d fuel. The planet you are on is saved and unloaded."
		% int(verdict.get("fuel", 0)), "Launch", "Stay")
	if not yes:
		return
	if bool(UI.get_setting("gameplay/autosave", true)):
		Events.save_requested.emit(0)
	UI.close_all()
	if Game != null and Game.has_method(&"travel_to_planet"):
		Game.travel_to_planet(planet_id)
	else:
		Events.toast("Travel is not available yet.", "warn")
