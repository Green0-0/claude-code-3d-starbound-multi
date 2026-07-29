## Two separate feeds:
##
##   * a **toast stack** at the top of the screen for `Events.notify`, one card
##     per message with a kind-coloured glyph (info / hint / warning / success /
##     quest / loot), sliding in and reflowing as older cards expire;
##   * an **item ticker** above the hotbar for `Events.item_picked_up`, which
##     groups repeats into one growing line ("+37 Iron Ore") instead of
##     spamming thirty identical rows while the player mines a vein.
class_name HudNotifications
extends Control

const TOAST_W := 360.0
const TOAST_MAX := 6
const TOAST_TOP := 22.0
const TICKER_MAX := 8
const TICKER_LIFE := 4.5
const HOTBAR_CLEARANCE := 108.0


class Toast extends RefCounted:
	var text := ""
	var kind := "info"
	var color := Color.WHITE
	var t := 0.0
	var life := 4.0
	var h := 30.0
	var y := -40.0
	var target_y := 0.0
	var placed := false


class Pickup extends RefCounted:
	var id: StringName = &""
	var label := ""
	var count := 0
	var t := 0.0
	var pop := 1.0
	var color := Color.WHITE


var _toasts: Array[Toast] = []
var _pickups: Array[Pickup] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.notify.connect(_on_notify)
	Events.item_picked_up.connect(_on_item_picked_up)


# -------------------------------------------------------------------- signals
func _on_notify(text: String, kind: String) -> void:
	if text.is_empty():
		return
	var t := Toast.new()
	t.text = text
	t.kind = kind
	t.color = HudTheme.kind_color(kind)
	t.life = clampf(2.8 + float(text.length()) * 0.035, 3.0, 8.0)
	t.h = _measure(text).y + 14.0
	_toasts.append(t)
	while _toasts.size() > TOAST_MAX:
		_toasts.pop_front()


func _on_item_picked_up(item_id: String, count: int) -> void:
	if count == 0:
		return
	var id := StringName(item_id)
	for p: Pickup in _pickups:
		if p.id == id and p.t < TICKER_LIFE - 0.6:
			p.count += count
			p.t = minf(p.t, 1.2)
			p.pop = 1.0
			return
	var np := Pickup.new()
	np.id = id
	np.count = count
	np.label = Items.display_name(id) if Items.has(id) else String(id).capitalize()
	var it: ItemType = Items.get_type(id) if Items.has(id) else null
	np.color = HudTheme.rarity_color(it.rarity) if it != null else HudTheme.TEXT
	_pickups.append(np)
	while _pickups.size() > TICKER_MAX:
		_pickups.pop_front()


func _measure(text: String) -> Vector2:
	var f := HudTheme.font()
	if f == null:
		return Vector2(TOAST_W, 16.0)
	return f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, TOAST_W - 46.0, 12)


# ------------------------------------------------------------------- updating
func _process(delta: float) -> void:
	_time += delta

	var y := TOAST_TOP
	var i := _toasts.size() - 1
	while i >= 0:
		var t := _toasts[i]
		t.t += delta
		if t.t >= t.life:
			_toasts.remove_at(i)
		i -= 1
	for t2: Toast in _toasts:
		t2.target_y = y
		if not t2.placed:
			t2.placed = true
			t2.y = y - 26.0
		t2.y = lerpf(t2.y, t2.target_y, clampf(delta * 12.0, 0.0, 1.0))
		y += t2.h + 6.0

	var j := _pickups.size() - 1
	while j >= 0:
		var p := _pickups[j]
		p.t += delta
		p.pop = maxf(0.0, p.pop - delta * 3.0)
		if p.t >= TICKER_LIFE:
			_pickups.remove_at(j)
		j -= 1

	queue_redraw()


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	_draw_toasts()
	_draw_ticker()


func _draw_toasts() -> void:
	var f := HudTheme.font()
	for t: Toast in _toasts:
		var appear := HudTheme.out_back(clampf(t.t / 0.28, 0.0, 1.0))
		var fade := clampf((t.life - t.t) / 0.45, 0.0, 1.0)
		var a := fade * clampf(t.t / 0.12, 0.0, 1.0)
		var w := TOAST_W * lerpf(0.86, 1.0, appear)
		var r := Rect2(Vector2((size.x - w) * 0.5, t.y), Vector2(w, t.h))

		HudTheme.panel(self, r, HudTheme.with_alpha(HudTheme.BG_DEEP, 0.86 * a),
			HudTheme.with_alpha(t.color, 0.65 * a), 5, 1)
		# Kind stripe down the left edge.
		HudTheme.round_rect(self, Rect2(r.position + Vector2(1, 1), Vector2(3.0, r.size.y - 2.0)),
			HudTheme.with_alpha(t.color, a), 1.5)
		_kind_glyph(t.kind, r.position + Vector2(22.0, r.size.y * 0.5),
			HudTheme.with_alpha(t.color, a))
		if f != null:
			draw_multiline_string(f, r.position + Vector2(38.0, 13.0), t.text,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 46.0, 12, 4,
				HudTheme.with_alpha(HudTheme.TEXT, a))
		# Life bar hairline so the player can see it is about to leave.
		var lf := clampf(1.0 - t.t / t.life, 0.0, 1.0)
		draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 1.0), Vector2(r.size.x * lf, 1.0)),
			HudTheme.with_alpha(t.color, 0.5 * a), true)


func _kind_glyph(kind: String, c: Vector2, col: Color) -> void:
	match kind:
		"warning", "error":
			HudTheme.ngon(self, c, 8.0, 3, col)
			HudTheme.text(self, c - Vector2(1.5, 2.0), "!", 9, Color(0, 0, 0, col.a))
		"success":
			draw_line(c + Vector2(-5, 0), c + Vector2(-1, 4), col, 2.2)
			draw_line(c + Vector2(-1, 4), c + Vector2(6, -5), col, 2.2)
		"quest":
			HudTheme._star(self, c, 8.0, 3.4, 5, col)
		"loot":
			HudTheme.round_rect(self, Rect2(c - Vector2(6, 4), Vector2(12, 9)), col, 2.0)
			draw_arc(c - Vector2(0, 4), 4.0, PI, TAU, 8, col, 1.6, true)
		"hint":
			draw_circle(c + Vector2(0, -2), 5.0, col)
			draw_rect(Rect2(c + Vector2(-2, 3), Vector2(4, 4)), col, true)
		_:
			draw_arc(c, 7.0, 0.0, TAU, 18, col, 1.6, true)
			draw_line(c + Vector2(0, -3), c + Vector2(0, 4), col, 2.0)
			draw_circle(c + Vector2(0, -5.5), 1.2, col)


func _draw_ticker() -> void:
	var right := size.x - 18.0
	var y := size.y - HOTBAR_CLEARANCE
	for k in range(_pickups.size() - 1, -1, -1):
		var p := _pickups[k]
		var a := clampf((TICKER_LIFE - p.t) / 0.7, 0.0, 1.0) * clampf(p.t / 0.1, 0.0, 1.0)
		var scale := 1.0 + p.pop * 0.12
		var label := "+%d  %s" % [p.count, p.label]
		var fs := int(round(12.0 * scale))
		var sz := HudTheme.text_size(label, fs)
		var w := sz.x + 34.0
		var r := Rect2(Vector2(right - w, y - 20.0), Vector2(w, 22.0))
		HudTheme.panel(self, r, HudTheme.with_alpha(HudTheme.BG_DEEP, 0.62 * a),
			HudTheme.with_alpha(p.color, 0.45 * a), 4, 1)
		HudTheme.item_icon(self, Rect2(r.position + Vector2(3, 3), Vector2(16, 16)), p.id,
			Color(1, 1, 1, a))
		HudTheme.text(self, r.position + Vector2(24.0, (22.0 - sz.y) * 0.5), label, fs,
			HudTheme.with_alpha(p.color.lerp(HudTheme.TEXT, 0.35), a))
		y -= 25.0
		if y < 60.0:
			return
