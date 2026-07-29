## Context-sensitive reticle drawn over the block the player is aiming at.
##
## States: idle, mine (with a filling progress ring), interact (key glyph over
## interactable blocks and NPCs), attack (hostile entity), out-of-range, and —
## the one this game needs — **wrong layer**, shown when the thing under the
## cursor is real but sits behind the play layer. That state names the fix
## ("PgDn x3"), which is how the player learns that depth is traversable.
##
## Projection: asks the camera agent's `CamProject` (`camera/screen_to_world.gd`)
## when that file exists, otherwise falls back to the viewport `Camera3D`'s own
## `project_ray_origin` / `unproject_position`, which is always available.
class_name HudCrosshair
extends Control

const PROJ_PATH := "res://camera/screen_to_world.gd"
const DEFAULT_REACH := 5.0

enum State { IDLE, MINE, INTERACT, ATTACK, OUT_OF_RANGE, WRONG_LAYER, PLACE }

var _state: State = State.IDLE
var _target := Vector3i.ZERO
var _has_target := false
var _layer_offset := 0
var _screen := Vector2.ZERO
var _box := Rect2()
var _progress := 0.0
var _time := 0.0
var _spin := 0.0
var _entity: Node = null

## `CamProject` may be an autoload, a script with static helpers, or absent.
var _proj_node: Node = null
var _proj_script: GDScript = null

## Local mining estimate, used only when nothing authoritative reports progress.
var _estimate := 0.0
var _estimating := false
var _estimate_target := Vector3i(9999, 9999, 9999)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_proj_node = get_node_or_null(^"/root/CamProject")
	if _proj_node == null and ResourceLoader.exists(PROJ_PATH):
		var res := load(PROJ_PATH)
		_proj_script = res as GDScript
	Events.block_changed.connect(_on_block_changed)


func _on_block_changed(pos: Vector3i, _old: int, _new: int) -> void:
	if pos == _estimate_target:
		_estimate = 0.0


# ------------------------------------------------------------------ plumbing
func _camera() -> Camera3D:
	var vp := get_viewport()
	if vp != null:
		var c := vp.get_camera_3d()
		if c != null:
			return c
	var rig := Game.camera_rig
	if rig != null:
		for ch: Node in rig.get_children():
			var cc := ch as Camera3D
			if cc != null:
				return cc
	return null


## Call a `CamProject` helper if it exists under any of `names`; `null` means
## "not available, use the fallback".
func _proj_call(names: Array, args: Array) -> Variant:
	for n: StringName in names:
		if _proj_node != null and _proj_node.has_method(n):
			return _proj_node.callv(n, args)
		if _proj_script != null and _proj_script.has_method(n):
			return _proj_script.callv(n, args)
	return null


## World position the cursor points at, snapped into the play layer.
func _aim_point(mouse: Vector2) -> Variant:
	var v: Variant = _proj_call([&"screen_to_play_layer", &"screen_to_world", &"to_world"], [mouse])
	if v is Vector3:
		return View.with_depth(v, float(View.layer) + 0.5)
	var cam := _camera()
	if cam == null:
		return null
	# Orthographic: the ray origin already carries the correct lateral/up
	# components, so pinning the depth axis gives the in-plane aim point.
	return View.with_depth(cam.project_ray_origin(mouse), float(View.layer) + 0.5)


func _to_screen(world: Vector3) -> Variant:
	var v: Variant = _proj_call([&"world_to_screen", &"to_screen"], [world])
	if v is Vector2:
		return v
	var cam := _camera()
	if cam == null:
		return null
	if cam.is_position_behind(world):
		return null
	return cam.unproject_position(world)


# ------------------------------------------------------------------ updating
func _process(delta: float) -> void:
	_time += delta
	_spin += delta * 0.6
	visible = _should_show()
	if not visible:
		return
	_evaluate(delta)
	queue_redraw()


func _should_show() -> bool:
	if Game.paused or Game.player == null or View.flipping:
		return false
	if UI != null and UI.has_method(&"captures_input") and UI.captures_input():
		return false
	return true


func _evaluate(delta: float) -> void:
	_has_target = false
	_entity = null
	_state = State.IDLE
	_layer_offset = 0

	var vp := get_viewport()
	if vp == null:
		return
	var mouse := vp.get_mouse_position()
	var aim_v: Variant = _aim_point(mouse)
	if not (aim_v is Vector3):
		return
	var aim: Vector3 = aim_v
	# Kept un-wrapped: `World.get_block()` normalises for us, and the raw value
	# projects correctly even when the aim crosses the planet's wrap seam.
	_target = Const.floor_v(aim)
	_has_target = true

	var player := Game.player
	var centre := Vector3(_target) + Vector3(0.5, 0.5, 0.5)
	var scr: Variant = _to_screen(centre)
	if scr is Vector2:
		_screen = scr
	else:
		_screen = size * 0.5
	_box = _project_box(_target)

	var reach := _reach()
	var to_player := player.aabb_center() - centre
	var in_range := Vector2(View.lateral_of(to_player), to_player.y).length() <= reach

	# Entities first: an NPC or monster under the cursor beats the block behind.
	var ent := Game.nearest_entity(centre, 1.3, &"entities", true)
	if ent != null and ent != player:
		_entity = ent
		var scr2: Variant = _to_screen(ent.aabb_center())
		if scr2 is Vector2:
			_screen = scr2
		_state = State.ATTACK if ent.faction == &"hostile" else State.INTERACT
		if not in_range:
			_state = State.OUT_OF_RANGE
		return

	var id := World.get_block(_target)
	if id != Const.AIR:
		if not in_range:
			_state = State.OUT_OF_RANGE
			return
		var bt := Blocks.get_type(id)
		if bt != null and bt.on_interact.is_valid():
			_state = State.INTERACT
			return
		_state = State.MINE
		_progress = _mine_progress(delta, bt)
		return

	# Air in the play layer — is the player looking at something that lives in
	# another layer? That is the game's most confusing moment; name it.
	var behind := _scan_depth(_target)
	if behind != 0:
		_layer_offset = behind
		_state = State.WRONG_LAYER
		var probe := _target + View.depth_step() * behind
		var scr3: Variant = _to_screen(Vector3(probe) + Vector3(0.5, 0.5, 0.5))
		if scr3 is Vector2:
			_screen = scr3
		_box = _project_box(probe)
		return

	if in_range and _adjacent_solid(_target):
		_state = State.PLACE
	else:
		_state = State.IDLE


## Nearest layer offset (in `depth_step` units) that holds a solid block.
func _scan_depth(from: Vector3i) -> int:
	var step := View.depth_step()
	for k in range(1, Const.SLAB_BEHIND + 1):
		if Blocks.is_solid(World.get_block(from + step * k)):
			return k
	for k in range(1, 4):
		if Blocks.is_solid(World.get_block(from - step * k)):
			return -k
	return 0


func _adjacent_solid(p: Vector3i) -> bool:
	for n: Vector3i in [Vector3i.UP, Vector3i.DOWN, View.right(), -View.right()]:
		if Blocks.is_solid(World.get_block(p + n)):
			return true
	return false


func _project_box(p: Vector3i) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var any := false
	for i in 8:
		var c := Vector3(p) + Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
		var s: Variant = _to_screen(c)
		if s is Vector2:
			var v: Vector2 = s
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
			any = true
	if not any:
		return Rect2(_screen - Vector2(12, 12), Vector2(24, 24))
	return Rect2(lo, hi - lo)


func _reach() -> float:
	var p := Game.player
	if p == null:
		return DEFAULT_REACH
	var v: Variant = p.get(&"reach")
	if v is float or v is int:
		return maxf(1.0, float(v))
	var held := _held_stack()
	if held != null:
		var t := held.type()
		if t != null and t.tool_range > 0.0:
			return t.tool_range
	return DEFAULT_REACH


func _held_stack() -> ItemStack:
	var p := Game.player
	if p == null:
		return null
	for m: StringName in [&"held_stack", &"selected_stack", &"held_item"]:
		if p.has_method(m):
			var v: Variant = p.call(m)
			if v is ItemStack:
				return v
	var inv: Variant = p.get(&"inventory")
	var obj := inv as Object
	if obj != null and obj.has_method(&"selected_stack"):
		var v2: Variant = obj.call(&"selected_stack")
		if v2 is ItemStack:
			return v2
	return null


## Prefer whatever the player/tech module reports; otherwise estimate locally so
## the ring is still informative (documented as an estimate, never a promise).
func _mine_progress(delta: float, bt: BlockType) -> float:
	var p := Game.player
	if p != null:
		for prop: StringName in [&"mine_progress", &"mining_progress", &"break_progress"]:
			var v: Variant = p.get(prop)
			if v is float or v is int:
				_estimating = false
				return clampf(float(v), 0.0, 1.0)
		for m: StringName in [&"get_mine_progress", &"mining_fraction"]:
			if p.has_method(m):
				_estimating = false
				return clampf(float(p.call(m)), 0.0, 1.0)
	_estimating = true
	if _estimate_target != _target:
		_estimate_target = _target
		_estimate = 0.0
	if bt == null or not bt.breakable or not Input.is_action_pressed(&"primary"):
		_estimate = maxf(0.0, _estimate - delta * 2.0)
		return _estimate
	var power := 1.0
	var held := _held_stack()
	if held != null:
		var t := held.type()
		if t != null and t.tool_power > 0.0:
			power = t.tool_power
	_estimate = clampf(_estimate + delta * power / maxf(0.05, bt.hardness), 0.0, 1.0)
	return _estimate


# ------------------------------------------------------------------- drawing
func _draw() -> void:
	if not _has_target:
		return
	match _state:
		State.MINE:
			_draw_block_frame(HudTheme.with_alpha(Color.WHITE, 0.75))
			_draw_ring(_progress, HudTheme.ACCENT)
			_draw_ticks(HudTheme.with_alpha(Color.WHITE, 0.85), 7.0)
		State.INTERACT:
			_draw_block_frame(HudTheme.with_alpha(HudTheme.ACCENT_WARM, 0.9))
			_draw_interact()
		State.ATTACK:
			_draw_attack()
		State.OUT_OF_RANGE:
			_draw_dashed(11.0, HudTheme.with_alpha(HudTheme.TEXT_FAINT, 0.8))
			_caption("out of range", HudTheme.with_alpha(HudTheme.TEXT_FAINT, 0.9))
		State.WRONG_LAYER:
			_draw_wrong_layer()
		State.PLACE:
			_draw_block_frame(HudTheme.with_alpha(HudTheme.EDGE, 0.45))
			_draw_ticks(HudTheme.with_alpha(Color.WHITE, 0.5), 5.0)
		_:
			_draw_ticks(HudTheme.with_alpha(Color.WHITE, 0.35), 5.0)


func _draw_ticks(col: Color, arm: float) -> void:
	var g := 3.0
	draw_line(_screen + Vector2(-g - arm, 0), _screen + Vector2(-g, 0), col, 1.5)
	draw_line(_screen + Vector2(g, 0), _screen + Vector2(g + arm, 0), col, 1.5)
	draw_line(_screen + Vector2(0, -g - arm), _screen + Vector2(0, -g), col, 1.5)
	draw_line(_screen + Vector2(0, g), _screen + Vector2(0, g + arm), col, 1.5)
	draw_circle(_screen, 1.0, col)


func _draw_block_frame(col: Color) -> void:
	var b := _box.grow(1.0)
	if b.size.x < 4.0 or b.size.y < 4.0:
		return
	HudTheme.brackets(self, b, col, minf(9.0, b.size.x * 0.3), 2.0)


func _draw_ring(frac: float, col: Color) -> void:
	var rad := 15.0
	draw_arc(_screen, rad, 0.0, TAU, 32, HudTheme.with_alpha(Color.BLACK, 0.45), 4.0, true)
	if frac <= 0.001:
		return
	draw_arc(_screen, rad, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 32, col, 3.0, true)
	if frac > 0.98:
		HudTheme.glow(self, _screen, 26.0, HudTheme.with_alpha(col, 0.35))
	if _estimating and frac > 0.02:
		# Dotted inner ring marks the value as a local estimate.
		draw_arc(_screen, rad - 4.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 12,
			HudTheme.with_alpha(col, 0.25), 1.0, true)


func _draw_interact() -> void:
	var col := HudTheme.ACCENT_WARM
	var pulse := 0.85 + 0.15 * sin(_time * 4.0)
	draw_arc(_screen, 12.0 * pulse, 0.0, TAU, 24, col, 1.8, true)
	var key := HudTheme.key_label(&"interact", "F")
	var sz := HudTheme.text_size(key, 11)
	var box := Rect2(_screen - Vector2(sz.x * 0.5 + 5.0, sz.y * 0.5 + 2.0), sz + Vector2(10.0, 4.0))
	HudTheme.panel(self, box, HudTheme.with_alpha(HudTheme.BG_DEEP, 0.9),
		HudTheme.with_alpha(col, 0.9), 3, 1)
	HudTheme.text(self, box.position + Vector2(5.0, 2.0), key, 11, col)
	if _entity != null:
		_caption(_entity_label(), HudTheme.with_alpha(col, 0.95))


func _draw_attack() -> void:
	var col := HudTheme.BAD
	var r := 13.0
	for i in 4:
		var a := PI * 0.25 + PI * 0.5 * float(i) + sin(_time * 2.0) * 0.05
		var d := Vector2(cos(a), sin(a))
		draw_line(_screen + d * (r - 5.0), _screen + d * r, col, 2.0)
	draw_arc(_screen, r, 0.0, TAU, 24, HudTheme.with_alpha(col, 0.45), 1.0, true)
	draw_circle(_screen, 1.6, col)
	if _entity != null:
		_caption(_entity_label(), HudTheme.with_alpha(col, 0.95))


func _entity_label() -> String:
	if _entity == null:
		return ""
	var v: Variant = _entity.get(&"display_name")
	if v is String and not String(v).is_empty():
		return String(v)
	var e := _entity as VoxelEntity
	if e != null and e.max_health > 0.0:
		return "%s  %d/%d" % [_entity.name, roundi(e.health), roundi(e.max_health)]
	return String(_entity.name)


func _draw_dashed(radius: float, col: Color) -> void:
	var segs := 10
	for i in segs:
		var a0 := TAU * float(i) / float(segs) + _spin
		draw_arc(_screen, radius, a0, a0 + TAU / float(segs) * 0.55, 4, col, 1.8, true)


func _draw_wrong_layer() -> void:
	var col := HudTheme.ACCENT
	_draw_dashed(12.0, HudTheme.with_alpha(col, 0.75))
	# Stacked-planes glyph: the target lives on one of the sheets behind you.
	var base := _screen + Vector2(0.0, -26.0)
	for i in 3:
		var y := base.y + float(i) * 4.0
		var w := 11.0 - float(i) * 1.5
		var a := 0.9 if i == mini(2, absi(_layer_offset) - 1) else 0.30
		draw_line(Vector2(base.x - w, y), Vector2(base.x + w, y), HudTheme.with_alpha(col, a), 2.0)
	var n := absi(_layer_offset)
	var key := HudTheme.key_label(&"depth_in" if _layer_offset > 0 else &"depth_out", "PgDn")
	_caption("%d layer%s %s  ·  %s x%d" % [n, "" if n == 1 else "s",
		"behind" if _layer_offset > 0 else "in front", key, n], HudTheme.with_alpha(col, 0.95))
	if _box.size.x > 4.0:
		HudTheme.brackets(self, _box.grow(1.0), HudTheme.with_alpha(col, 0.35), 6.0, 1.0)


func _caption(text: String, col: Color) -> void:
	var sz := HudTheme.text_size(text, 11)
	var pos := _screen + Vector2(-sz.x * 0.5, 20.0)
	HudTheme.panel(self, Rect2(pos - Vector2(5, 2), sz + Vector2(10, 4)),
		HudTheme.with_alpha(HudTheme.BG_DEEP, 0.75 * col.a), Color(0, 0, 0, 0), 3, 0)
	HudTheme.text(self, pos, text, 11, col)
