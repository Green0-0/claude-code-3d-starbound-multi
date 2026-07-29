## Buff / debuff row under the status bars: one procedurally drawn icon per
## active effect with a radial timer sweeping away as it expires.
##
## Consumes: `status_applied(id, duration)`, `status_removed(id)`.
## The `Status` singleton is a stub until the survival agent lands, so the row
## is driven purely by those two signals: durations are counted down locally and
## an effect whose duration is <= 0 is treated as permanent (no radial, pulsing
## ring instead).
class_name HudStatusEffects
extends Control

const ICON := 32.0
const GAP := 6.0

## keyword -> [colour, glyph, is_buff]
const TABLE := {
	"burn": [Color(1.0, 0.5, 0.16), "flame", false],
	"fire": [Color(1.0, 0.5, 0.16), "flame", false],
	"poison": [Color(0.62, 0.90, 0.32), "drops", false],
	"venom": [Color(0.62, 0.90, 0.32), "drops", false],
	"toxic": [Color(0.62, 0.90, 0.32), "drops", false],
	"freeze": [Color(0.55, 0.85, 1.0), "snow", false],
	"cold": [Color(0.55, 0.85, 1.0), "snow", false],
	"chill": [Color(0.55, 0.85, 1.0), "snow", false],
	"shock": [Color(0.98, 0.90, 0.35), "bolt", false],
	"electric": [Color(0.98, 0.90, 0.35), "bolt", false],
	"stun": [Color(0.98, 0.90, 0.35), "bolt", false],
	"bleed": [Color(0.90, 0.20, 0.24), "drops", false],
	"radiation": [Color(0.70, 1.0, 0.35), "rad", false],
	"wet": [Color(0.40, 0.70, 1.0), "drops", false],
	"regen": [Color(0.40, 0.92, 0.50), "cross", true],
	"heal": [Color(0.40, 0.92, 0.50), "cross", true],
	"well_fed": [Color(0.85, 0.55, 0.25), "apple", true],
	"food": [Color(0.85, 0.55, 0.25), "apple", true],
	"speed": [Color(0.45, 0.95, 0.85), "chevron", true],
	"haste": [Color(0.45, 0.95, 0.85), "chevron", true],
	"jump": [Color(0.45, 0.95, 0.85), "chevron", true],
	"shield": [Color(0.55, 0.75, 1.0), "shield", true],
	"defense": [Color(0.55, 0.75, 1.0), "shield", true],
	"armor": [Color(0.55, 0.75, 1.0), "shield", true],
	"strength": [Color(1.0, 0.72, 0.25), "star", true],
	"power": [Color(1.0, 0.72, 0.25), "star", true],
	"oxygen": [Color(0.35, 0.72, 1.0), "bubble", true],
	"breath": [Color(0.35, 0.72, 1.0), "bubble", true],
	"light": [Color(1.0, 0.92, 0.60), "sun", true],
	"glow": [Color(1.0, 0.92, 0.60), "sun", true],
}


class Effect extends RefCounted:
	var id := ""
	var label := ""
	var duration := 0.0
	var remaining := 0.0
	var pop := 1.0
	var out := 0.0                ## >0 while shrinking away
	var color := Color.WHITE
	var glyph := "dot"
	var buff := true


var _effects: Array[Effect] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.status_applied.connect(_on_applied)
	Events.status_removed.connect(_on_removed)


func _on_applied(id: String, duration: float) -> void:
	for e: Effect in _effects:
		if e.id == id:
			e.duration = maxf(duration, 0.0)
			e.remaining = e.duration
			e.pop = 1.0
			e.out = 0.0
			return
	var fx := Effect.new()
	fx.id = id
	fx.label = id.replace("_", " ").capitalize()
	fx.duration = maxf(duration, 0.0)
	fx.remaining = fx.duration
	var key := _match_key(id)
	if key.is_empty():
		fx.color = HudTheme.ACCENT
		fx.glyph = "letter"
	else:
		var row: Array = TABLE[key]
		fx.color = row[0]
		fx.glyph = String(row[1])
		fx.buff = bool(row[2])
	_effects.append(fx)
	while _effects.size() > 10:
		_effects.pop_front()


func _on_removed(id: String) -> void:
	for e: Effect in _effects:
		if e.id == id and e.out <= 0.0:
			e.out = 0.001


static func _match_key(id: String) -> String:
	var low := id.to_lower()
	for k: String in TABLE:
		if low.contains(k):
			return k
	return ""


# ------------------------------------------------------------------- updating
func _process(delta: float) -> void:
	_time += delta
	var i := _effects.size() - 1
	while i >= 0:
		var e := _effects[i]
		e.pop = maxf(0.0, e.pop - delta * 3.0)
		if e.out > 0.0:
			e.out += delta * 4.0
			if e.out >= 1.0:
				_effects.remove_at(i)
		elif e.duration > 0.0:
			e.remaining -= delta
			if e.remaining <= 0.0:
				e.out = 0.001
		i -= 1
	visible = not _effects.is_empty()
	if visible:
		queue_redraw()


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	var x := 0.0
	for e: Effect in _effects:
		var shrink := 1.0 - clampf(e.out, 0.0, 1.0)
		var scale := lerpf(0.7, 1.0, HudTheme.out_back(1.0 - e.pop)) * shrink
		var s := ICON * scale
		var r := Rect2(Vector2(x + (ICON - s) * 0.5, (ICON - s) * 0.5), Vector2(s, s))
		_draw_effect(e, r, shrink)
		x += ICON + GAP
		if x > size.x - ICON:
			return


func _draw_effect(e: Effect, r: Rect2, alpha: float) -> void:
	var expiring := e.duration > 0.0 and e.remaining < 3.0
	var blink := 1.0
	if expiring:
		blink = 0.55 + 0.45 * sin(_time * 12.0)
	var col := HudTheme.with_alpha(e.color, alpha * blink)

	HudTheme.panel(self, r, HudTheme.with_alpha(HudTheme.BG_DEEP, 0.85 * alpha),
		HudTheme.with_alpha(e.color, 0.85 * alpha * blink), 4, 1)
	# Buffs get a warm underline, debuffs a cold one — readable at a glance.
	draw_rect(Rect2(r.position + Vector2(2.0, r.size.y - 3.0), Vector2(r.size.x - 4.0, 2.0)),
		HudTheme.with_alpha(HudTheme.GOOD if e.buff else HudTheme.BAD, 0.7 * alpha), true)

	_glyph(e, Rect2(r.position + Vector2(6, 5), r.size - Vector2(12, 13)), col)

	if e.duration > 0.0:
		var elapsed := clampf(1.0 - e.remaining / maxf(0.001, e.duration), 0.0, 1.0)
		HudTheme.wedge(self, r.position + r.size * 0.5, r.size.x * 0.72, elapsed,
			Color(0.02, 0.03, 0.05, 0.55 * alpha))
		draw_arc(r.position + r.size * 0.5, r.size.x * 0.52, -PI * 0.5,
			-PI * 0.5 + TAU * (1.0 - elapsed), 24, HudTheme.with_alpha(e.color, 0.9 * alpha),
			1.6, true)
		if e.remaining < 10.0:
			var t := "%.0f" % maxf(0.0, e.remaining)
			var sz := HudTheme.text_size(t, 9)
			HudTheme.text(self, Vector2(r.position.x + (r.size.x - sz.x) * 0.5,
				r.position.y + r.size.y + 1.0), t, 9,
				HudTheme.with_alpha(HudTheme.TEXT, alpha), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 1)
	else:
		# Permanent: a slow pulse instead of a countdown.
		draw_arc(r.position + r.size * 0.5, r.size.x * 0.55 + sin(_time * 2.0) * 1.2,
			0.0, TAU, 24, HudTheme.with_alpha(e.color, 0.35 * alpha), 1.2, true)


func _glyph(e: Effect, r: Rect2, col: Color) -> void:
	var c := r.position + r.size * 0.5
	var s := minf(r.size.x, r.size.y)
	match e.glyph:
		"flame":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.5), c + Vector2(s * 0.36, s * 0.12),
				c + Vector2(s * 0.18, s * 0.45), c + Vector2(-s * 0.18, s * 0.45),
				c + Vector2(-s * 0.36, s * 0.12)]), col)
		"drops":
			draw_circle(c + Vector2(-s * 0.18, s * 0.06), s * 0.20, col)
			draw_circle(c + Vector2(s * 0.18, -s * 0.10), s * 0.16, col)
			draw_circle(c + Vector2(s * 0.02, s * 0.30), s * 0.12, col)
		"snow":
			for i in 3:
				var a := PI * float(i) / 3.0
				var d := Vector2(cos(a), sin(a)) * s * 0.45
				draw_line(c - d, c + d, col, 2.0)
		"bolt":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.10, -s * 0.48), c + Vector2(-s * 0.30, s * 0.08),
				c + Vector2(-s * 0.02, s * 0.08), c + Vector2(-s * 0.12, s * 0.48),
				c + Vector2(s * 0.30, -s * 0.08), c + Vector2(0.0, -s * 0.08)]), col)
		"cross":
			draw_rect(Rect2(c - Vector2(s * 0.12, s * 0.42), Vector2(s * 0.24, s * 0.84)), col, true)
			draw_rect(Rect2(c - Vector2(s * 0.42, s * 0.12), Vector2(s * 0.84, s * 0.24)), col, true)
		"apple":
			draw_circle(c + Vector2(0, s * 0.08), s * 0.36, col)
			draw_line(c + Vector2(0, -s * 0.24), c + Vector2(s * 0.08, -s * 0.48),
				HudTheme.shade(col, 0.6), 2.0)
		"chevron":
			for i in 2:
				var y := c.y - s * 0.22 + float(i) * s * 0.30
				draw_line(Vector2(c.x - s * 0.34, y + s * 0.14), Vector2(c.x, y - s * 0.14), col, 2.2)
				draw_line(Vector2(c.x, y - s * 0.14), Vector2(c.x + s * 0.34, y + s * 0.14), col, 2.2)
		"shield":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.46), c + Vector2(s * 0.36, -s * 0.24),
				c + Vector2(s * 0.28, s * 0.28), c + Vector2(0, s * 0.48),
				c + Vector2(-s * 0.28, s * 0.28), c + Vector2(-s * 0.36, -s * 0.24)]), col)
		"star":
			HudTheme._star(self, c, s * 0.48, s * 0.20, 5, col)
		"bubble":
			draw_arc(c, s * 0.40, 0.0, TAU, 18, col, 2.0, true)
			draw_circle(c + Vector2(-s * 0.14, -s * 0.14), s * 0.10, col)
		"rad":
			draw_circle(c, s * 0.12, col)
			for i in 3:
				var a2 := -PI * 0.5 + TAU * float(i) / 3.0
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(cos(a2 - 0.35), sin(a2 - 0.35)) * s * 0.46,
					c + Vector2(cos(a2 + 0.35), sin(a2 + 0.35)) * s * 0.46,
					c]), col)
		"sun":
			draw_circle(c, s * 0.24, col)
			for i in 8:
				var a3 := TAU * float(i) / 8.0
				var d3 := Vector2(cos(a3), sin(a3))
				draw_line(c + d3 * s * 0.32, c + d3 * s * 0.48, col, 1.6)
		_:
			var letter := e.label.substr(0, 1).to_upper()
			var sz := HudTheme.text_size(letter, 14)
			HudTheme.text(self, c - sz * 0.5, letter, 14, col)
