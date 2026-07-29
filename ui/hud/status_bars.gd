## Health / energy / breath / hunger bars, top-left.
##
## Each bar is chunky and segmented, and carries a lighter "ghost" that drains a
## beat after the real value so the player can read *how much* they just lost at
## a glance. Low health pulses the bar and pushes a red vignette in from the
## screen edges; drowning does the same in blue.
##
## Consumes: `stat_changed`, `player_damaged`, `player_healed`, `player_died`,
## `player_respawned`, `player_spawned`. Falls back to reading
## `Game.player.health` / `max_health` directly while no survival module is
## emitting `stat_changed`, so the health bar is always live.
class_name HudStatusBars
extends Control

const ORIGIN := Vector2(16.0, 14.0)
const BAR_W := 208.0
const GAP := 5.0
const ICON_W := 18.0

const GHOST_DELAY := 0.32
const GHOST_RATE := 0.55          ## fraction of the bar per second

## `stat_changed` keys we recognise, mapped onto our four bars.
const ALIASES := {
	"health": "health", "hp": "health", "life": "health",
	"energy": "energy", "mana": "energy", "stamina": "energy",
	"breath": "breath", "oxygen": "breath", "air": "breath",
	"hunger": "hunger", "food": "hunger", "satiety": "hunger",
}


## One tracked stat plus all of its presentation state.
class Bar extends RefCounted:
	var key := ""
	var label := ""
	var color := Color.WHITE
	var height := 12.0
	var value := 0.0
	var maximum := 100.0
	var shown := 0.0
	var ghost := 0.0
	var ghost_hold := 0.0
	var flash := 0.0
	var active := false
	var hide_when_full := false

	func frac() -> float:
		return clampf(shown / maxf(0.001, maximum), 0.0, 1.0)

	func ghost_frac() -> float:
		return clampf(ghost / maxf(0.001, maximum), 0.0, 1.0)

	func visible_now() -> bool:
		if not active:
			return false
		if hide_when_full and value >= maximum - 0.01 and ghost <= value + 0.01:
			return false
		return true


var _bars: Dictionary = {}
var _order: Array[String] = ["health", "energy", "breath", "hunger"]
var _floaters: Array[Dictionary] = []
var _time := 0.0
var _hurt_flash := 0.0
var _dead := false
## True once something authoritative reported health; until then we poll the
## player node so the bar is never a lie.
var _health_reported := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make(&"health", "HEALTH", 14.0, false)
	_make(&"energy", "ENERGY", 10.0, false)
	_make(&"breath", "BREATH", 10.0, true)
	_make(&"hunger", "HUNGER", 10.0, false)
	var hp: Bar = _bars["health"]
	hp.active = true

	Events.stat_changed.connect(_on_stat_changed)
	Events.player_damaged.connect(_on_damaged)
	Events.player_healed.connect(_on_healed)
	Events.player_died.connect(_on_died)
	Events.player_respawned.connect(_on_respawned)
	Events.player_spawned.connect(func(_p: Node) -> void: _on_respawned())


func _make(key: StringName, label: String, h: float, hide_full: bool) -> void:
	var b := Bar.new()
	b.key = String(key)
	b.label = label
	b.height = h
	b.color = HudTheme.bar_color(b.key)
	b.hide_when_full = hide_full
	_bars[b.key] = b


# ------------------------------------------------------------------- signals
func _on_stat_changed(stat: String, value: float, maximum: float) -> void:
	var key: String = ALIASES.get(stat.to_lower(), "")
	if key.is_empty() or not _bars.has(key):
		return
	var b: Bar = _bars[key]
	b.active = true
	if maximum > 0.0:
		b.maximum = maximum
	if value < b.value - 0.01:
		b.ghost_hold = GHOST_DELAY
		b.flash = 0.35
	elif value > b.value + 0.01:
		b.flash = 0.2
	b.value = clampf(value, 0.0, b.maximum)
	if key == "health":
		_health_reported = true
		_dead = b.value <= 0.0


func _on_damaged(amount: float, element: String, _source: Node) -> void:
	if amount <= 0.0:
		return
	_hurt_flash = 1.0
	var b: Bar = _bars["health"]
	b.ghost_hold = GHOST_DELAY
	b.flash = 0.4
	_push_floater("-%s" % _fmt(amount), HudTheme.element_color(element))


func _on_healed(amount: float) -> void:
	if amount <= 0.0:
		return
	_push_floater("+%s" % _fmt(amount), HudTheme.GOOD)
	var b: Bar = _bars["health"]
	b.flash = 0.3


func _on_died(_cause: String) -> void:
	_dead = true


func _on_respawned() -> void:
	_dead = false
	_hurt_flash = 0.0
	for k: String in _bars:
		var b: Bar = _bars[k]
		b.ghost = b.value
		b.shown = b.value


func _push_floater(txt: String, col: Color) -> void:
	if _floaters.size() > 12:
		_floaters.pop_front()
	# Stagger vertically so a burst of hits does not draw one on top of another.
	var lane := 0
	for f: Dictionary in _floaters:
		if float(f["t"]) < 0.22:
			lane += 1
	_floaters.append({"text": txt, "col": col, "t": 0.0, "lane": lane})


static func _fmt(v: float) -> String:
	return str(roundi(v)) if v >= 1.0 else "%.1f" % v


# ------------------------------------------------------------------ updating
func _process(delta: float) -> void:
	_time += delta
	_poll_player()

	for k: String in _bars:
		var b: Bar = _bars[k]
		b.shown = move_toward(b.shown, b.value, maxf(b.maximum * 1.6, 24.0) * delta)
		if b.ghost_hold > 0.0:
			b.ghost_hold -= delta
		elif b.ghost > b.shown:
			b.ghost = maxf(b.shown, b.ghost - b.maximum * GHOST_RATE * delta)
		if b.ghost < b.shown:
			b.ghost = b.shown
		b.flash = maxf(0.0, b.flash - delta * 2.2)

	_hurt_flash = maxf(0.0, _hurt_flash - delta * 1.6)

	var i := _floaters.size() - 1
	while i >= 0:
		_floaters[i]["t"] = float(_floaters[i]["t"]) + delta
		if float(_floaters[i]["t"]) > 1.5:
			_floaters.remove_at(i)
		i -= 1

	queue_redraw()


## Keeps the health bar honest before the survival/player agents emit stats.
func _poll_player() -> void:
	if _health_reported:
		return
	var p := Game.player
	if p == null:
		return
	var b: Bar = _bars["health"]
	b.maximum = maxf(1.0, p.max_health)
	if p.health < b.value - 0.01:
		b.ghost_hold = GHOST_DELAY
	b.value = clampf(p.health, 0.0, b.maximum)
	b.active = true
	_dead = p.dead


# ------------------------------------------------------------------- drawing
func _draw() -> void:
	_draw_vignette()

	var pos := ORIGIN
	for key: String in _order:
		var b: Bar = _bars[key]
		if not b.visible_now():
			continue
		_draw_bar(b, Rect2(pos, Vector2(BAR_W, b.height)))
		pos.y += b.height + GAP

	_draw_floaters(Vector2(ORIGIN.x + BAR_W + 14.0, ORIGIN.y + 10.0))


func _draw_vignette() -> void:
	var hp: Bar = _bars["health"]
	var frac := hp.frac()
	var tint := Color(0, 0, 0, 0)
	if frac < 0.34:
		var t := 1.0 - frac / 0.34
		var pulse := 0.72 + 0.28 * sin(_time * (4.0 + 4.0 * t))
		tint = Color(0.85, 0.06, 0.08, t * 0.55 * pulse)
	if _dead:
		tint = Color(0.6, 0.0, 0.0, 0.7)
	var br: Bar = _bars["breath"]
	if br.active and br.frac() < 0.5:
		var t2 := 1.0 - br.frac() / 0.5
		var blue := Color(0.10, 0.35, 0.85, t2 * 0.5 * (0.7 + 0.3 * sin(_time * 3.0)))
		tint = _over(tint, blue)
	if _hurt_flash > 0.01:
		tint = _over(tint, Color(1.0, 0.25, 0.2, _hurt_flash * 0.4))
	if tint.a <= 0.004:
		return
	draw_texture_rect(HudTheme.vignette(), Rect2(Vector2.ZERO, size), false, tint)


static func _over(a: Color, b: Color) -> Color:
	# Cheap "screen the two vignettes together" so red + blue never cancels out.
	if a.a <= 0.001:
		return b
	if b.a <= 0.001:
		return a
	var w := b.a / (a.a + b.a)
	return Color(lerpf(a.r, b.r, w), lerpf(a.g, b.g, w), lerpf(a.b, b.b, w), maxf(a.a, b.a))


func _draw_bar(b: Bar, r: Rect2) -> void:
	var dead_tint := 0.35 if _dead else 1.0
	var col := HudTheme.shade(b.color, dead_tint)

	# Track.
	HudTheme.round_rect(self, r.grow(2.0), Color(0.03, 0.035, 0.055, 0.80), 4.0)
	HudTheme.round_rect(self, r, Color(0.13, 0.14, 0.19, 0.9), 3.0)

	# Ghost (damage lag) sits under the real fill.
	var gf := b.ghost_frac()
	if gf > b.frac() + 0.001:
		var gr := Rect2(r.position, Vector2(r.size.x * gf, r.size.y))
		HudTheme.round_rect(self, gr, HudTheme.with_alpha(col.lightened(0.55), 0.65), 3.0)

	# Fill, with a low-health pulse on health only.
	var f := b.frac()
	if f > 0.0:
		var fill := col
		if b.key == "health" and f < 0.34 and not _dead:
			fill = col.lerp(Color(1, 1, 1, 1), 0.25 + 0.25 * sin(_time * 8.0))
		if b.flash > 0.0:
			fill = fill.lerp(Color.WHITE, b.flash * 0.7)
		var fr := Rect2(r.position, Vector2(r.size.x * f, r.size.y))
		HudTheme.round_rect(self, fr, fill, 3.0)
		# Top highlight gives the bar its chunky, lit look.
		HudTheme.round_rect(self, Rect2(fr.position + Vector2(2, 2),
			Vector2(maxf(0.0, fr.size.x - 4.0), maxf(1.0, fr.size.y * 0.30))),
			HudTheme.with_alpha(fill.lightened(0.45), 0.55), 2.0)

	# Segment notches — one per 10 points, clamped to something readable.
	var segs := clampi(roundi(b.maximum / 10.0), 4, 20)
	for i in range(1, segs):
		var x := r.position.x + r.size.x * float(i) / float(segs)
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y),
			Color(0.03, 0.04, 0.06, 0.75), 1.0)

	# Frame.
	draw_rect(r.grow(2.0), HudTheme.with_alpha(HudTheme.EDGE_DIM, 0.85), false, 1.0)

	_draw_icon(b, Vector2(r.position.x - ICON_W + 2.0, r.position.y + r.size.y * 0.5), col)

	if b.height >= 12.0:
		HudTheme.text(self, r.position + Vector2(6.0, -1.0), b.label, 9,
			HudTheme.with_alpha(Color.WHITE, 0.5))
	var txt := "%d/%d" % [roundi(b.shown), roundi(b.maximum)]
	HudTheme.text(self, Vector2(r.position.x, r.position.y + (r.size.y - 11.0) * 0.5),
		txt, 10, HudTheme.with_alpha(Color.WHITE, 0.92),
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5.0, 1)


## Tiny procedural glyph to the left of each bar.
func _draw_icon(b: Bar, c: Vector2, col: Color) -> void:
	var s := 5.0
	match b.key:
		"health":
			draw_circle(c + Vector2(-s * 0.45, -s * 0.25), s * 0.55, col)
			draw_circle(c + Vector2(s * 0.45, -s * 0.25), s * 0.55, col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, -s * 0.1), c + Vector2(s, -s * 0.1), c + Vector2(0, s)]), col)
		"energy":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.6, s * 0.15),
				c + Vector2(-s * 0.05, s * 0.15), c + Vector2(-s * 0.2, s),
				c + Vector2(s * 0.6, -s * 0.15), c + Vector2(0.0, -s * 0.15)]), col)
		"breath":
			draw_arc(c, s * 0.8, 0.0, TAU, 14, col, 1.6, true)
			draw_circle(c + Vector2(-s * 0.25, -s * 0.25), s * 0.2, col)
		"hunger":
			draw_circle(c + Vector2(0, s * 0.2), s * 0.7, col)
			draw_line(c + Vector2(0, -s * 0.4), c + Vector2(0, -s), HudTheme.shade(col, 0.6), 2.0)


func _draw_floaters(anchor: Vector2) -> void:
	for f: Dictionary in _floaters:
		var t := float(f["t"])
		var a := clampf(1.0 - (t - 0.9) / 0.6, 0.0, 1.0)
		var pop := HudTheme.out_back(minf(1.0, t / 0.18))
		var col: Color = f["col"]
		var p := anchor + Vector2(0.0, float(f["lane"]) * 13.0 - t * 26.0)
		var fs := int(round(lerpf(9.0, 15.0, pop)))
		HudTheme.text(self, p, String(f["text"]), fs, HudTheme.with_alpha(col, a),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 1)
