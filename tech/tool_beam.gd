## The **Matter Manipulator** — the starting universal tool, and the one the
## player holds more than anything else.
##
## Owned by `Tech` (`Tech.beam`) and driven by `tech/interaction.gd`, which
## decides *what* is under the cursor; this file decides what the beam does to
## it and draws the beam.
##
## ---------------------------------------------------------------------------
## PROGRESSION — bought with `manipulator_module` items
## ---------------------------------------------------------------------------
## Six independent tracks, each legible on its own line in the upgrade UI:
##
##   radius   1x1 -> 2x2 -> 3x3 area, in plane space (lateral x up)
##   tier     0 -> 6, which ores yield drops (mirrors the pickaxe ladder)
##   speed    mining power multiplier, 1.0 -> 2.6
##   range    reach in blocks, 5 -> 11
##   liquid   unlocks LIQUID mode: drain and re-place fluids
##   wire     unlocks WIRE mode: connect and cut object wiring
##   paint    unlocks PAINT mode: recolour placed blocks
##
## `upgrade_cost(track)` and `describe()` exist so the UI never has to hard-code
## the table.
##
## ---------------------------------------------------------------------------
## THE BEAM MESH
## ---------------------------------------------------------------------------
## An `ImmediateMesh` rebuilt each frame while firing: a tapered ribbon from the
## muzzle to the impact point, oriented so its width axis is perpendicular to
## both the beam and `View.forward()` (which is why it reads as a flat 2D beam
## from the orthographic camera in every one of the four planes), plus an
## impact flare that pulses with mining progress. Unshaded, additive, vertex
## coloured — no textures, no assets.
class_name TchToolBeam
extends Node3D

enum Mode { MINE, LIQUID, WIRE, PAINT }

const MODE_NAMES := ["Mine", "Liquid", "Wire", "Paint"]

## Per-track upgrade tables. `values[i]` is the effect at level `i`;
## `costs[i]` is the module price of moving from level `i-1` to level `i`
## (so `costs[0]` is always 0 — level 0 is what you start with).
const TRACKS := {
	"radius": {
		"name": "Beam Aperture", "values": [1, 2, 3], "costs": [0, 3, 8],
		"blurb": "Widens the mining footprint in the view plane.",
	},
	"tier": {
		"name": "Matter Resolver", "values": [0, 1, 2, 3, 4, 5, 6],
		"costs": [0, 2, 4, 7, 11, 16, 24],
		"blurb": "Raises the ore tier the beam can actually recover.",
	},
	"speed": {
		"name": "Cycle Rate", "values": [1.0, 1.35, 1.7, 2.1, 2.6],
		"costs": [0, 2, 4, 7, 12],
		"blurb": "Faster extraction. Compounds with the mining_speed stat.",
	},
	"range": {
		"name": "Focus Lens", "values": [5.0, 7.0, 9.0, 11.0], "costs": [0, 2, 5, 9],
		"blurb": "Reach, in blocks.",
	},
	"liquid": {
		"name": "Fluid Intake", "values": [false, true], "costs": [0, 5],
		"blurb": "Unlocks liquid collection mode.",
	},
	"wire": {
		"name": "Signal Probe", "values": [false, true], "costs": [0, 4],
		"blurb": "Unlocks wire editing mode.",
	},
	"paint": {
		"name": "Chroma Head", "values": [false, true], "costs": [0, 4],
		"blurb": "Unlocks paint mode.",
	},
}

## The item spent on upgrades.
const MODULE_ITEM := &"manipulator_module"
## Tank capacity, in liquid units (8 = one full voxel).
const TANK_CAPACITY := 400

# ------------------------------------------------------------------ progression
var levels: Dictionary = {
	"radius": 0, "tier": 0, "speed": 0, "range": 0,
	"liquid": 0, "wire": 0, "paint": 0,
}
var modules_spent: int = 0

# ------------------------------------------------------------------- live state
var mode: int = Mode.MINE
var firing: bool = false
var paint_color: Color = Color(0.85, 0.3, 0.3)
## {"id": StringName, "amount": int}
var tank: Dictionary = {"id": &"", "amount": 0}

var _target: Vector3i = Vector3i.ZERO
var _target_point: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _progress: float = 0.0
var _required: float = 1.0
var _muzzle: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _mesh: ImmediateMesh = null
var _mi: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _reparented: bool = false


func _ready() -> void:
	_build_visual()


# ===========================================================================
#  Derived stats
# ===========================================================================
## Edge length of the mining footprint: 1, 2 or 3.
func radius() -> int:
	return int(TRACKS["radius"]["values"][levels["radius"]])


func tier() -> int:
	return int(TRACKS["tier"]["values"][levels["tier"]])


func speed() -> float:
	return float(TRACKS["speed"]["values"][levels["speed"]])


func reach() -> float:
	return float(TRACKS["range"]["values"][levels["range"]])


func has_liquid_mode() -> bool:
	return levels["liquid"] > 0


func has_wire_mode() -> bool:
	return levels["wire"] > 0


func has_paint_mode() -> bool:
	return levels["paint"] > 0


## Effective mining power: upgrades times whatever techs and buffs contribute.
func power() -> float:
	var m := 1.0
	if Tech.has_method(&"modifier"):
		m = Tech.modifier("mining_speed")
	return speed() * maxf(0.0, m)


# ===========================================================================
#  Upgrades
# ===========================================================================
## Modules required for the next level of `track`, or -1 when maxed / unknown.
func upgrade_cost(track: String) -> int:
	if not TRACKS.has(track):
		return -1
	var next: int = int(levels.get(track, 0)) + 1
	var costs: Array = TRACKS[track]["costs"]
	return -1 if next >= costs.size() else int(costs[next])


func is_maxed(track: String) -> bool:
	return upgrade_cost(track) < 0


## Buys one level of `track`, paying `manipulator_module` out of the player's
## inventory. Returns false (and spends nothing) when unaffordable or maxed.
func upgrade(track: String) -> bool:
	var cost := upgrade_cost(track)
	if cost < 0:
		Events.toast("%s is already at maximum." % TRACKS.get(track, {}).get("name", track), "warn")
		return false
	if not _take_modules(cost):
		Events.toast("Need %d manipulator modules." % cost, "warn")
		return false
	levels[track] = int(levels[track]) + 1
	modules_spent += cost
	var label: String = String(TRACKS[track]["name"])
	Events.upgrade_purchased.emit("manipulator:" + track)
	Events.toast("%s upgraded — %s" % [label, _track_summary(track)], "upgrade")
	Events.play_sound.emit(&"upgrade", global_position)
	return true


func _take_modules(n: int) -> bool:
	if n <= 0:
		return true
	var inv: Variant = Game.player.get("inventory") if Game.player != null else null
	if inv == null:
		return false
	if inv.has_method(&"count_of") and int(inv.call(&"count_of", MODULE_ITEM)) < n:
		return false
	# The crafting agent's helper handles every inventory shape; fall back to
	# the plain remove call when it is not there yet.
	if Recipes.has_method(&"take_from"):
		return bool(Recipes.take_from(inv, {MODULE_ITEM: n}))
	if inv.has_method(&"remove_item"):
		return bool(inv.call(&"remove_item", MODULE_ITEM, n))
	return false


func _track_summary(track: String) -> String:
	var v: Variant = TRACKS[track]["values"][levels[track]]
	match track:
		"radius":
			return "%dx%d" % [int(v), int(v)]
		"tier":
			return "tier %d" % int(v)
		"speed":
			return "x%.2f" % float(v)
		"range":
			return "%.0f blocks" % float(v)
	return "unlocked" if bool(v) else "locked"


## One human-readable line per track, for the upgrade panel.
func describe() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for track: String in TRACKS:
		out.append({
			"track": track,
			"name": String(TRACKS[track]["name"]),
			"blurb": String(TRACKS[track]["blurb"]),
			"level": int(levels[track]),
			"max_level": (TRACKS[track]["values"] as Array).size() - 1,
			"summary": _track_summary(track),
			"cost": upgrade_cost(track),
		})
	return out


# ===========================================================================
#  Modes
# ===========================================================================
func available_modes() -> Array[int]:
	var out: Array[int] = [Mode.MINE]
	if has_liquid_mode():
		out.append(Mode.LIQUID)
	if has_wire_mode():
		out.append(Mode.WIRE)
	if has_paint_mode():
		out.append(Mode.PAINT)
	return out


func set_mode(m: int) -> void:
	if not available_modes().has(m):
		Events.toast("That manipulator mode is not installed.", "warn")
		return
	if mode == m:
		return
	mode = m
	stop()
	Events.toast("Manipulator: %s mode" % MODE_NAMES[m], "info")
	Events.play_sound.emit(&"tool_mode", global_position)


func cycle_mode() -> void:
	var modes := available_modes()
	var i := modes.find(mode)
	set_mode(modes[(i + 1) % modes.size()])


# ===========================================================================
#  Targeting and firing — called by tech/interaction.gd
# ===========================================================================
## Point the beam at a voxel. `muzzle` is where the beam leaves the player.
func aim(pos: Vector3i, hit_point: Vector3, muzzle: Vector3) -> void:
	if _has_target and pos != _target:
		_progress = 0.0     ## sliding off a block resets its mining progress
	_target = pos
	_target_point = hit_point
	_muzzle = muzzle
	_has_target = true


func clear_target() -> void:
	_has_target = false
	_progress = 0.0
	firing = false


## Hold the trigger. Returns true on the frame the action completes.
func fire(delta: float) -> bool:
	if not _has_target:
		firing = false
		return false
	firing = true
	match mode:
		Mode.MINE:
			return _tick_mine(delta)
		Mode.LIQUID:
			return _tick_liquid(delta)
		Mode.WIRE:
			return _tick_wire()
		Mode.PAINT:
			return _tick_paint()
	return false


func stop() -> void:
	firing = false
	_progress = 0.0


func progress_fraction() -> float:
	return 0.0 if _required <= 0.0 else clampf(_progress / _required, 0.0, 1.0)


# --------------------------------------------------------------------- mining
func _tick_mine(delta: float) -> bool:
	var id := World.get_block(_target)
	if id == Const.AIR:
		_progress = 0.0
		return false
	var bt := Blocks.get_type(id)
	if not bt.breakable:
		_progress = 0.0
		return false
	_required = maxf(0.05, bt.hardness / maxf(0.05, power()))
	_progress += delta
	if _progress < _required:
		if fmod(_progress, 0.2) < delta:
			Events.spawn_particles.emit(&"mine_chip", Vector3(_target) + Vector3(0.5, 0.5, 0.5), 2)
		return false
	_progress = 0.0
	_break_pattern()
	return true


## Breaks the NxN footprint in plane space, centred on the target, all at the
## target's own depth so the beam never reaches through a layer by accident.
func _break_pattern() -> void:
	var n := radius()
	var lo := -((n - 1) / 2)
	var hi := lo + n - 1
	var right := View.right()
	var broken := 0
	for l in range(lo, hi + 1):
		for y in range(lo, hi + 1):
			var q := World.normalize(_target + right * l + Vector3i(0, y, 0))
			var id := World.get_block(q)
			if id == Const.AIR:
				continue
			var bt := Blocks.get_type(id)
			if not bt.breakable:
				continue
			# The centre voxel always goes; the halo respects the tier gate so a
			# wide beam cannot strip an ore vein the player has not earned.
			if q != _target and bt.tool_tier > tier():
				continue
			_release_object(q)
			World.break_block(q, tier(), true)
			broken += 1
	if broken > 0:
		Game.bump_stat("blocks_mined", float(broken))
		Events.play_sound.emit(&"tool_beam_break", Vector3(_target) + Vector3(0.5, 0.5, 0.5))
		Events.spawn_particles.emit(&"mine_burst", Vector3(_target) + Vector3(0.5, 0.5, 0.5), 10)


## Gives the object subsystem a chance to drop a placed machine's contents
## before the voxel (and with it, its tile_data) disappears.
func _release_object(q: Vector3i) -> void:
	if Tech.objects != null and Tech.objects.has_method(&"on_block_removed"):
		Tech.objects.call(&"on_block_removed", q)


# -------------------------------------------------------------------- liquids
func _tick_liquid(delta: float) -> bool:
	_required = 0.12
	_progress += delta
	if _progress < _required:
		return false
	_progress = 0.0
	var id := World.get_block(_target)
	if Blocks.is_liquid(id):
		if int(tank["amount"]) >= TANK_CAPACITY:
			Events.toast("Tank full.", "warn")
			return false
		var bt := Blocks.get_type(id)
		if tank["id"] != &"" and tank["id"] != bt.name:
			Events.toast("Tank already holds %s." % Items.display_name(tank["id"]), "warn")
			return false
		var amount := maxi(1, Liquids.level_at(_target))
		World.set_block(_target, Const.AIR)
		tank["id"] = bt.name
		tank["amount"] = mini(TANK_CAPACITY, int(tank["amount"]) + amount)
		Events.play_sound.emit(&"tool_slurp", _target_point)
		Events.spawn_particles.emit(&"liquid_drain", _target_point, 6)
		return true
	return false


## Secondary fire in LIQUID mode: pour the tank back out.
func pour(pos: Vector3i) -> bool:
	if int(tank["amount"]) <= 0 or tank["id"] == &"":
		return false
	if World.get_block(pos) != Const.AIR:
		return false
	if not World.set_block(pos, Blocks.id(tank["id"])):
		return false
	tank["amount"] = int(tank["amount"]) - mini(Const.MAX_LIQUID, int(tank["amount"]))
	if int(tank["amount"]) <= 0:
		tank["id"] = &""
		tank["amount"] = 0
	if Liquids.has_method(&"queue_liquid"):
		Liquids.queue_liquid(pos)
	Events.play_sound.emit(&"tool_pour", Vector3(pos))
	return true


# ----------------------------------------------------------------------- wire
func _tick_wire() -> bool:
	if Tech.objects == null or not Tech.objects.has_method(&"wire_click"):
		return false
	var done := bool(Tech.objects.call(&"wire_click", _target, false))
	stop()
	return done


## Secondary fire in WIRE mode cuts instead of connecting.
func wire_cut(pos: Vector3i) -> bool:
	if Tech.objects == null or not Tech.objects.has_method(&"wire_click"):
		return false
	return bool(Tech.objects.call(&"wire_click", pos, true))


# ---------------------------------------------------------------------- paint
func _tick_paint() -> bool:
	var id := World.get_block(_target)
	if id == Const.AIR:
		return false
	var c: Chunk = World.chunk_at_block(_target)
	if c == null:
		return false
	var n := World.normalize(_target)
	var i := Chunk.index(n.x & 15, n.y & 15, n.z & 15)
	var d: Dictionary = c.get_tile_data(i).duplicate()
	d["paint"] = [paint_color.r, paint_color.g, paint_color.b]
	c.set_tile_data(i, d)
	World.mark_dirty(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))
	Events.spawn_particles.emit(&"paint_puff", _target_point, 4)
	Events.play_sound.emit(&"tool_paint", _target_point)
	stop()
	return true


## Secondary fire in PAINT mode strips the paint back off.
func strip_paint(pos: Vector3i) -> bool:
	var c: Chunk = World.chunk_at_block(pos)
	if c == null:
		return false
	var n := World.normalize(pos)
	var i := Chunk.index(n.x & 15, n.y & 15, n.z & 15)
	var d: Dictionary = c.get_tile_data(i).duplicate()
	if not d.has("paint"):
		return false
	d.erase("paint")
	c.set_tile_data(i, d)
	World.mark_dirty(Vector3i(n.x >> 4, n.y >> 4, n.z >> 4))
	return true


# ===========================================================================
#  Presentation
# ===========================================================================
func _build_visual() -> void:
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.name = "BeamMesh"
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.layers = Const.RL_EFFECTS
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	_mat.disable_receive_shadows = true
	_mi.material_override = _mat
	add_child(_mi)
	_mi.visible = false


## Per-frame presentation. Driven from `Tech.drive()`.
func update(delta: float) -> void:
	_time += delta
	_ensure_parent()
	if _mi == null:
		return
	if not firing or not _has_target:
		_mi.visible = false
		return
	_mi.visible = true
	_draw_beam()


## The beam lives under `Game.main` once the scene exists so it inherits the
## gameplay world; until then it renders from the autoload, which is harmless.
func _ensure_parent() -> void:
	if _reparented or Game.main == null:
		return
	_reparented = true
	var p := get_parent()
	if p != null:
		p.remove_child(self)
	Game.main.add_child(self)


func mode_color() -> Color:
	match mode:
		Mode.LIQUID:
			return Color(0.35, 0.7, 1.0)
		Mode.WIRE:
			return Color(1.0, 0.85, 0.3)
		Mode.PAINT:
			return paint_color
	return Color(0.55, 0.95, 0.85)


func _draw_beam() -> void:
	var from := _muzzle
	var to := _target_point
	var dir := to - from
	var len := dir.length()
	if len < 0.01:
		_mi.visible = false
		return
	dir /= len

	# Width axis: perpendicular to the beam *and* to the camera, so the ribbon
	# always presents its full face to the orthographic view, in all 4 planes.
	var cam := Vector3(View.forward())
	var side := dir.cross(cam)
	if side.length_squared() < 0.0001:
		side = dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()

	var base := mode_color()
	var t := progress_fraction()
	var pulse := 0.72 + 0.28 * sin(_time * 26.0)
	var w0 := 0.075 * pulse
	var w1 := (0.035 + 0.10 * t) * pulse

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tapered ribbon, split into segments so the colour can ramp along it.
	var segments := 6
	for s in segments:
		var a := float(s) / float(segments)
		var b := float(s + 1) / float(segments)
		var pa := from.lerp(to, a)
		var pb := from.lerp(to, b)
		var wa := lerpf(w0, w1, a)
		var wb := lerpf(w0, w1, b)
		var ca := base
		ca.a = lerpf(0.25, 0.95, a)
		var cb := base
		cb.a = lerpf(0.25, 0.95, b)
		_quad(pa - side * wa, pa + side * wa, pb + side * wb, pb - side * wb, ca, cb)

	# Impact flare: a camera-facing square that grows with mining progress.
	var up := cam.cross(side).normalized()
	var r := 0.10 + 0.22 * t * pulse
	var flare := base.lightened(0.35)
	flare.a = 0.35 + 0.5 * t
	_quad(to - side * r - up * r, to + side * r - up * r,
		to + side * r + up * r, to - side * r + up * r, flare, flare)

	_mesh.surface_end()
	_mat.albedo_color = Color(1, 1, 1, 1)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, c0: Color, c1: Color) -> void:
	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(c)

	_mesh.surface_set_color(c0)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(c)
	_mesh.surface_set_color(c1)
	_mesh.surface_add_vertex(d)


func hud_state() -> Dictionary:
	return {
		"mode": MODE_NAMES[mode],
		"mode_index": mode,
		"modes": available_modes(),
		"radius": radius(), "tier": tier(), "speed": speed(), "range": reach(),
		"firing": firing, "progress": progress_fraction(),
		"tank": {"id": String(tank["id"]), "amount": int(tank["amount"]),
				"capacity": TANK_CAPACITY},
		"paint": paint_color,
		"modules_spent": modules_spent,
	}


# ===========================================================================
#  Persistence
# ===========================================================================
func save_state() -> Dictionary:
	return {
		"levels": levels.duplicate(),
		"modules_spent": modules_spent,
		"mode": mode,
		"paint": [paint_color.r, paint_color.g, paint_color.b],
		"tank": {"id": String(tank["id"]), "amount": int(tank["amount"])},
	}


func load_state(d: Dictionary) -> void:
	var lv: Dictionary = d.get("levels", {})
	for k: String in levels:
		if lv.has(k):
			var max_l: int = (TRACKS[k]["values"] as Array).size() - 1
			levels[k] = clampi(int(lv[k]), 0, max_l)
	modules_spent = int(d.get("modules_spent", 0))
	var m := int(d.get("mode", 0))
	mode = m if available_modes().has(m) else Mode.MINE
	var pc: Array = d.get("paint", [0.85, 0.3, 0.3])
	if pc.size() >= 3:
		paint_color = Color(pc[0], pc[1], pc[2])
	var tk: Dictionary = d.get("tank", {})
	tank = {"id": StringName(tk.get("id", "")), "amount": int(tk.get("amount", 0))}
	stop()
