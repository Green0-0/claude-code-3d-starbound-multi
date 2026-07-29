## Shared palette, procedural glyphs and drawing helpers for every HUD widget.
##
## The project ships no binary assets, so everything the HUD shows is either a
## `_draw()` primitive, a cached `StyleBoxFlat` or a procedurally generated
## `ImageTexture`. This file is the single place those are defined so the whole
## overlay reads as one designed object instead of ten unrelated widgets.
class_name HudTheme
extends RefCounted

# ------------------------------------------------------------------- palette
const BG := Color(0.055, 0.065, 0.095, 0.72)
const BG_DEEP := Color(0.025, 0.03, 0.05, 0.88)
const BG_SLOT := Color(0.10, 0.12, 0.17, 0.85)
const EDGE := Color(0.44, 0.55, 0.72, 0.9)
const EDGE_DIM := Color(0.26, 0.32, 0.44, 0.75)
const TEXT := Color(0.90, 0.93, 1.0)
const TEXT_DIM := Color(0.60, 0.66, 0.79)
const TEXT_FAINT := Color(0.45, 0.50, 0.62)
const ACCENT := Color(0.36, 0.86, 1.0)         ## the "perspective" colour
const ACCENT_WARM := Color(1.0, 0.76, 0.32)
const GOOD := Color(0.40, 0.92, 0.50)
const BAD := Color(1.0, 0.36, 0.34)
const WARN := Color(1.0, 0.72, 0.25)
const QUEST := Color(0.78, 0.60, 1.0)

## Bar colours, indexed by the stat key the HUD understands.
const BAR_COLORS := {
	"health": Color(0.93, 0.26, 0.33),
	"energy": Color(0.98, 0.82, 0.25),
	"breath": Color(0.35, 0.72, 1.0),
	"hunger": Color(0.85, 0.55, 0.25),
}

const ELEMENT_COLORS := {
	"physical": Color(0.94, 0.94, 0.97),
	"fire": Color(1.0, 0.50, 0.16),
	"ice": Color(0.55, 0.85, 1.0),
	"electric": Color(0.98, 0.90, 0.35),
	"poison": Color(0.62, 0.90, 0.32),
	"cosmic": Color(0.78, 0.50, 1.0),
}

const KIND_COLORS := {
	"info": Color(0.55, 0.72, 0.95),
	"hint": Color(0.36, 0.86, 1.0),
	"warning": Color(1.0, 0.72, 0.25),
	"error": Color(1.0, 0.36, 0.34),
	"success": Color(0.40, 0.92, 0.50),
	"quest": Color(0.78, 0.60, 1.0),
	"loot": Color(1.0, 0.84, 0.42),
}

static var _style_cache: Dictionary = {}
static var _vignette: ImageTexture = null
static var _soft_dot: ImageTexture = null


# --------------------------------------------------------------------- text
## The engine's built-in font — the project may not add any font assets.
static func font() -> Font:
	return ThemeDB.fallback_font


## Left/centre/right aligned string with an optional dark outline for contrast
## against a bright world. `pos` is the top-left of the text box.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int = 13,
		col: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0, outline: int = 0) -> void:
	var f := font()
	if f == null or s.is_empty():
		return
	var baseline := pos + Vector2(0.0, f.get_ascent(size))
	if outline > 0:
		ci.draw_string_outline(f, baseline, s, align, width, size, outline,
			Color(0.0, 0.0, 0.0, col.a * 0.75))
	ci.draw_string(f, baseline, s, align, width, size, col)


static func text_size(s: String, size: int = 13) -> Vector2:
	var f := font()
	if f == null:
		return Vector2.ZERO
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)


# -------------------------------------------------------------------- panels
## Cached rounded panel box. Widgets call this every frame; the StyleBoxFlat is
## only built once per distinct look.
static func panel_style(bg: Color = BG, border: Color = EDGE_DIM,
		radius: int = 5, border_width: int = 1) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d" % [bg.to_html(true), border.to_html(true), radius, border_width]
	var cached: StyleBoxFlat = _style_cache.get(key)
	if cached != null:
		return cached
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	_style_cache[key] = sb
	return sb


static func panel(ci: CanvasItem, r: Rect2, bg: Color = BG,
		border: Color = EDGE_DIM, radius: int = 5, border_width: int = 1) -> void:
	ci.draw_style_box(panel_style(bg, border, radius, border_width), r)


## A titled panel: header strip + body. Returns the inner content rect.
static func framed_panel(ci: CanvasItem, r: Rect2, title: String,
		accent: Color = ACCENT, alpha: float = 1.0) -> Rect2:
	var bg := BG
	bg.a *= alpha
	var edge := accent
	edge.a = 0.5 * alpha
	panel(ci, r, bg, edge, 5, 1)
	if not title.is_empty():
		var head := Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 15))
		var hc := accent
		hc.a = 0.16 * alpha
		ci.draw_rect(head, hc, true)
		var tc := accent
		tc.a = alpha
		text(ci, r.position + Vector2(7, 2), title, 10, tc)
		return Rect2(r.position + Vector2(6, 19), r.size - Vector2(12, 25))
	return r.grow(-6.0)


# ------------------------------------------------------------------- shapes
## Filled rounded rectangle without needing a StyleBox (used inside bars).
static func round_rect(ci: CanvasItem, r: Rect2, col: Color, radius: float = 3.0) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	if rad <= 0.5:
		ci.draw_rect(r, col, true)
		return
	ci.draw_rect(Rect2(r.position + Vector2(rad, 0), Vector2(r.size.x - rad * 2.0, r.size.y)), col, true)
	ci.draw_rect(Rect2(r.position + Vector2(0, rad), Vector2(rad, r.size.y - rad * 2.0)), col, true)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - rad, rad), Vector2(rad, r.size.y - rad * 2.0)), col, true)
	ci.draw_circle(r.position + Vector2(rad, rad), rad, col)
	ci.draw_circle(r.position + Vector2(r.size.x - rad, rad), rad, col)
	ci.draw_circle(r.position + Vector2(rad, r.size.y - rad), rad, col)
	ci.draw_circle(r.position + Vector2(r.size.x - rad, r.size.y - rad), rad, col)


## Pie wedge starting at 12 o'clock, sweeping clockwise. `frac` is 0..1.
static func wedge(ci: CanvasItem, centre: Vector2, radius: float, frac: float,
		col: Color, steps: int = 28) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.001:
		return
	var pts := PackedVector2Array()
	pts.append(centre)
	var n := maxi(2, int(ceil(steps * frac)))
	for i in range(n + 1):
		var a := -PI * 0.5 + TAU * frac * (float(i) / float(n))
		pts.append(centre + Vector2(cos(a), sin(a)) * radius)
	ci.draw_colored_polygon(pts, col)


## Regular polygon outline/fill; `sides` 3 = triangle, 4 = diamond, 6 = hex.
static func ngon(ci: CanvasItem, centre: Vector2, radius: float, sides: int,
		col: Color, rot: float = 0.0, filled: bool = true, width: float = 1.5) -> void:
	var pts := PackedVector2Array()
	for i in range(sides):
		var a := rot - PI * 0.5 + TAU * float(i) / float(sides)
		pts.append(centre + Vector2(cos(a), sin(a)) * radius)
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, width, true)


## Corner brackets — used by the crosshair and by "selected" highlights.
static func brackets(ci: CanvasItem, r: Rect2, col: Color, arm: float = 6.0,
		width: float = 2.0) -> void:
	var p := r.position
	var s := r.size
	ci.draw_line(p, p + Vector2(arm, 0), col, width)
	ci.draw_line(p, p + Vector2(0, arm), col, width)
	ci.draw_line(p + Vector2(s.x, 0), p + Vector2(s.x - arm, 0), col, width)
	ci.draw_line(p + Vector2(s.x, 0), p + Vector2(s.x, arm), col, width)
	ci.draw_line(p + Vector2(0, s.y), p + Vector2(arm, s.y), col, width)
	ci.draw_line(p + Vector2(0, s.y), p + Vector2(0, s.y - arm), col, width)
	ci.draw_line(p + s, p + s - Vector2(arm, 0), col, width)
	ci.draw_line(p + s, p + s - Vector2(0, arm), col, width)


# ----------------------------------------------------------------- textures
## Radial darkening used for the low-health / drowning vignette. Generated once.
static func vignette() -> ImageTexture:
	if _vignette != null:
		return _vignette
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n - 1, n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c) / (float(n) * 0.5)
			var a := clampf(smoothstep(0.42, 1.05, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_vignette = ImageTexture.create_from_image(img)
	return _vignette


## Soft round blob, used for glows behind markers and pickups.
static func soft_dot() -> ImageTexture:
	if _soft_dot != null:
		return _soft_dot
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n - 1, n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c) / (float(n) * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2.0))
	_soft_dot = ImageTexture.create_from_image(img)
	return _soft_dot


static func glow(ci: CanvasItem, centre: Vector2, radius: float, col: Color) -> void:
	ci.draw_texture_rect(soft_dot(),
		Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, col)


# ------------------------------------------------------------------ colours
static func element_color(element: String) -> Color:
	var c: Color = ELEMENT_COLORS.get(element, ELEMENT_COLORS["physical"])
	return c


static func kind_color(kind: String) -> Color:
	var c: Color = KIND_COLORS.get(kind, KIND_COLORS["info"])
	return c


static func bar_color(stat: String) -> Color:
	var c: Color = BAR_COLORS.get(stat, ACCENT)
	return c


static func rarity_color(rarity: int) -> Color:
	var i := clampi(rarity, 0, Const.RARITY_COLORS.size() - 1)
	var c: Color = Const.RARITY_COLORS[i]
	return c


# --------------------------------------------------------------- key prompts
## Human-readable label for the first key bound to `action`, so on-screen
## prompts always match the real `InputMap` instead of a hard-coded guess.
static func key_label(action: StringName, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	for e: InputEvent in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null:
			var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
			var s := OS.get_keycode_string(code)
			if not s.is_empty():
				return s
		var mb := e as InputEventMouseButton
		if mb != null:
			match mb.button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
	return fallback


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)


## Standard ease used by nearly every HUD pop-in.
static func out_back(t: float, overshoot: float = 1.7) -> float:
	var u := clampf(t, 0.0, 1.0) - 1.0
	return u * u * ((overshoot + 1.0) * u + overshoot) + 1.0


static func out_cubic(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


# ------------------------------------------------------- procedural item art
## Fallback item icon: a coloured shape derived from `ItemType.icon_shape`.
## Used whenever `Atlas.item_icon()` has not been implemented yet (it is a stub
## until the rendering agent lands) or returns null for an unknown item.
static func item_shape(ci: CanvasItem, r: Rect2, shape: StringName, col: Color) -> void:
	var c := r.position + r.size * 0.5
	var s := minf(r.size.x, r.size.y)
	var dark := shade(col, 0.55)
	match String(shape):
		"circle", "orb", "ball":
			ci.draw_circle(c, s * 0.40, col)
			ci.draw_circle(c - Vector2(s * 0.11, s * 0.11), s * 0.13, col.lightened(0.45))
		"diamond", "gem", "crystal":
			ngon(ci, c, s * 0.44, 4, col)
			ci.draw_line(c - Vector2(0, s * 0.44), c + Vector2(0, s * 0.44), dark, 1.0)
		"triangle", "shard":
			ngon(ci, c, s * 0.44, 3, col)
		"star":
			_star(ci, c, s * 0.46, s * 0.20, 5, col)
		"bar", "ingot":
			var br := Rect2(c - Vector2(s * 0.38, s * 0.16), Vector2(s * 0.76, s * 0.32))
			round_rect(ci, br, col, 3.0)
			ci.draw_line(br.position + Vector2(3, 3), br.position + Vector2(br.size.x - 3, 3),
				col.lightened(0.4), 2.0)
		"blade", "sword", "weapon":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.28, -s * 0.42), c + Vector2(s * 0.38, -s * 0.32),
				c + Vector2(-s * 0.16, s * 0.24), c + Vector2(-s * 0.26, s * 0.14)]), col)
			ci.draw_line(c + Vector2(-s * 0.34, s * 0.06), c + Vector2(-s * 0.06, s * 0.34), dark, 3.0)
		"pick", "pickaxe", "tool", "axe", "shovel":
			ci.draw_line(c + Vector2(-s * 0.28, s * 0.34), c + Vector2(s * 0.20, -s * 0.26),
				Color(0.55, 0.40, 0.26), 3.0)
			ci.draw_arc(c + Vector2(s * 0.08, -s * 0.18), s * 0.30, PI * 0.15, PI * 0.95, 12, col, 3.5, true)
		"flask", "potion", "bottle":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.09, -s * 0.42), Vector2(s * 0.18, s * 0.18)), dark, true)
			ci.draw_circle(c + Vector2(0, s * 0.10), s * 0.30, col)
		"leaf", "seed", "plant":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.42), c + Vector2(s * 0.32, s * 0.06),
				c + Vector2(0, s * 0.40), c + Vector2(-s * 0.32, s * 0.06)]), col)
			ci.draw_line(c + Vector2(0, -s * 0.36), c + Vector2(0, s * 0.36), dark, 1.0)
		"ring", "augment", "chip":
			ci.draw_arc(c, s * 0.34, 0.0, TAU, 20, col, 4.0, true)
		"coin", "currency", "pixel":
			ci.draw_circle(c, s * 0.36, col)
			ci.draw_arc(c, s * 0.36, 0.0, TAU, 20, dark, 1.5, true)
		_:
			var q := Rect2(c - Vector2(s * 0.34, s * 0.34), Vector2(s * 0.68, s * 0.68))
			round_rect(ci, q, col, 3.0)
			ci.draw_rect(Rect2(q.position + Vector2(2, 2), Vector2(q.size.x - 4, 3.0)),
				col.lightened(0.35), true)


static func _star(ci: CanvasItem, c: Vector2, outer: float, inner: float,
		points: int, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(points * 2):
		var rad := outer if i % 2 == 0 else inner
		var a := -PI * 0.5 + PI * float(i) / float(points)
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, col)


## Draw an item's icon into `r`: real atlas texture when the renderer provides
## one, otherwise the procedural shape above.
static func item_icon(ci: CanvasItem, r: Rect2, id: StringName, tint: Color = Color.WHITE) -> void:
	# `Atlas` is an autoload but a stub until the rendering agent lands: its
	# `item_icon()` returns null, so every call site needs the shape fallback.
	var tex: Texture2D = null
	if Atlas != null and Atlas.has_method(&"item_icon"):
		tex = Atlas.call(&"item_icon", id) as Texture2D
	if tex != null:
		ci.draw_texture_rect(tex, r, false, tint)
		return
	var t: ItemType = Items.get_type(id) if Items.has(id) else null
	var col := (t.icon_color if t != null else Color(0.72, 0.74, 0.80))
	col = Color(col.r * tint.r, col.g * tint.g, col.b * tint.b, tint.a)
	item_shape(ci, r, t.icon_shape if t != null else &"square", col)
