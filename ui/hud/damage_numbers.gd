## Floating combat text, pooled so a fight never allocates.
##
## Numbers are anchored to the world position they were emitted at (re-projected
## every frame) and travel along a screen-space arc, so they stay glued to the
## thing that got hit while the camera pans. Repeated hits on the same spot fan
## out instead of stacking into an unreadable blob.
##
## Consumes: `damage_number(world_pos, amount, element, crit)`, `entity_died`.
class_name HudDamageNumbers
extends Control

const POOL := 64
const LIFE := 1.05
const CRIT_LIFE := 1.45
const GRAVITY := 240.0
const STACK_RADIUS := 0.85


class DamagePopup extends RefCounted:
	var alive := false
	var world := Vector3.ZERO
	var vel := Vector2.ZERO
	var off := Vector2.ZERO
	var t := 0.0
	var life := 1.0
	var text := ""
	var color := Color.WHITE
	var crit := false
	var size_px := 14


var _pool: Array[DamagePopup] = []
var _kills: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in POOL:
		_pool.append(DamagePopup.new())
	Events.damage_number.connect(_on_damage_number)
	Events.entity_died.connect(_on_entity_died)


# -------------------------------------------------------------------- spawning
func _on_damage_number(world_pos: Vector3, amount: float, element: String, crit: bool) -> void:
	if amount <= 0.0:
		return
	var p := _free_popup()
	if p == null:
		return
	p.alive = true
	p.world = world_pos
	p.t = 0.0
	p.life = CRIT_LIFE if crit else LIFE
	p.crit = crit
	p.color = HudTheme.element_color(element)
	p.text = _format(amount)
	if crit:
		p.text += "!"
		p.color = p.color.lerp(Color(1.0, 0.95, 0.6), 0.35)
	p.size_px = 22 if crit else 15

	# Fan out from anything already floating at (roughly) the same spot.
	var near := 0
	for q: DamagePopup in _pool:
		if q.alive and q != p and q.world.distance_squared_to(world_pos) < STACK_RADIUS * STACK_RADIUS:
			near += 1
	var side := 1.0 if near % 2 == 0 else -1.0
	var tier := float((near + 1) / 2)
	p.off = Vector2(side * tier * 9.0, -tier * 6.0)
	p.vel = Vector2(side * (26.0 + tier * 8.0), -(150.0 + (30.0 if crit else 0.0)))


func _on_entity_died(entity: Node) -> void:
	if entity == null or entity == Game.player:
		return
	var n3 := entity as Node3D
	if n3 == null:
		return
	var pos := n3.global_position
	var e := entity as VoxelEntity
	if e != null:
		pos = e.aabb_center()
	var label := String(entity.name)
	var v: Variant = entity.get(&"display_name")
	if v is String and not String(v).is_empty():
		label = String(v)
	_kills.append({"world": pos, "t": 0.0, "label": label})
	if _kills.size() > 12:
		_kills.pop_front()


func _free_popup() -> DamagePopup:
	var oldest: DamagePopup = null
	for p: DamagePopup in _pool:
		if not p.alive:
			return p
		if oldest == null or p.t > oldest.t:
			oldest = p
	return oldest


static func _format(a: float) -> String:
	if a >= 1000.0:
		return "%.1fk" % (a / 1000.0)
	return str(roundi(a)) if a >= 1.0 else "%.1f" % a


# -------------------------------------------------------------------- updating
func _process(delta: float) -> void:
	_time += delta
	for p: DamagePopup in _pool:
		if not p.alive:
			continue
		p.t += delta
		p.off += p.vel * delta
		p.vel.y += GRAVITY * delta
		if p.t >= p.life:
			p.alive = false
	var i := _kills.size() - 1
	while i >= 0:
		_kills[i]["t"] = float(_kills[i]["t"]) + delta
		if float(_kills[i]["t"]) > 1.3:
			_kills.remove_at(i)
		i -= 1
	# Redraw unconditionally: the last frame after everything expires still has
	# to clear the canvas, and an empty draw list costs nothing.
	queue_redraw()


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _to_screen(cam: Camera3D, world: Vector3) -> Variant:
	if cam == null or cam.is_position_behind(world):
		return null
	return cam.unproject_position(world)


# --------------------------------------------------------------------- drawing
func _draw() -> void:
	var cam := _camera()
	if cam == null:
		return

	for p: DamagePopup in _pool:
		if not p.alive:
			continue
		var base: Variant = _to_screen(cam, p.world)
		if not (base is Vector2):
			continue
		var pos: Vector2 = base
		pos += p.off
		var k: float = p.t / p.life
		var a := clampf((1.0 - k) / 0.35, 0.0, 1.0)
		var pop := HudTheme.out_back(minf(1.0, p.t / 0.12), 2.4)
		var fs := int(round(float(p.size_px) * lerpf(0.55, 1.0, pop)))
		var sz := HudTheme.text_size(p.text, fs)
		var at := pos - Vector2(sz.x * 0.5, sz.y * 0.5)
		if p.crit:
			var burst := clampf(p.t / 0.25, 0.0, 1.0)
			if burst < 1.0:
				draw_arc(pos, 8.0 + burst * 26.0, 0.0, TAU, 22,
					HudTheme.with_alpha(p.color, (1.0 - burst) * 0.6), 2.0, true)
			HudTheme.glow(self, pos, 26.0, HudTheme.with_alpha(p.color, 0.22 * a))
		HudTheme.text(self, at, p.text, fs, HudTheme.with_alpha(p.color, a),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 2 if p.crit else 1)

	for k2: Dictionary in _kills:
		var w: Vector3 = k2["world"]
		var s: Variant = _to_screen(cam, w)
		if not (s is Vector2):
			continue
		var c: Vector2 = s
		var t := float(k2["t"])
		var a2 := clampf(1.0 - t / 1.3, 0.0, 1.0)
		var grow := HudTheme.out_cubic(minf(1.0, t / 0.4))
		var rad := 6.0 + grow * 20.0
		var col := HudTheme.with_alpha(HudTheme.BAD, a2)
		draw_arc(c, rad, 0.0, TAU, 24, HudTheme.with_alpha(HudTheme.BAD, a2 * 0.5), 2.0, true)
		var d := 7.0
		draw_line(c + Vector2(-d, -d), c + Vector2(d, d), col, 2.5)
		draw_line(c + Vector2(d, -d), c + Vector2(-d, d), col, 2.5)
		var label := String(k2["label"])
		var lsz := HudTheme.text_size(label, 11)
		HudTheme.text(self, c - Vector2(lsz.x * 0.5, 30.0 + t * 12.0), label, 11,
			HudTheme.with_alpha(HudTheme.TEXT, a2), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 1)
