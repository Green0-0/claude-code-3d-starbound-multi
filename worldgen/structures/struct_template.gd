## Compact authoring format for hand-built rooms.
##
## A template is an array of **Z-slices**. Each slice is an array of strings, one
## string per Y row written *top row first* (so the ASCII art reads the way the
## room looks from the side), one character per X column:
##
## ```gdscript
## StructTemplate.make(&"shrine", {
##     "#": {"role": &"wall"},
##     ".": {"keep": true},      # leave terrain alone
##     " ": {"air": true},       # force air
##     "L": {"role": &"light"},
##     "C": {"generic": &"chest", "marker": {"kind": "container", "table": "shrine"}},
## }, [
##     ["#####",     # slice z = 0
##      "#   #",
##      "##C##"],
##     ["#L L#",     # slice z = 1
##      "     ",
##      "#####"],
## ])
## ```
##
## Legend entry forms (String key = one character):
##   `{"role": &"wall"}`      resolve through `StructPalette` with the stamp theme
##   `{"generic": &"chest"}`  resolve through `StructPalette.generic`
##   `{"block": &"stone"}`    a literal block name, or an Array candidate chain
##   `{"air": true}`          force air (carves through terrain)
##   `{"keep": true}`         write nothing — terrain shows through
##   `{"liquid": 8}`          also set the liquid level
##   `{"marker": {...}}`      emit a tile-data payload (see `StructMarkers`)
##   `{"chance": 0.4}`        only place this voxel some of the time
##   A bare StringName / String value is shorthand for `{"block": value}`.
##
## Default characters when the legend does not override them:
##   `.` and `?`  keep,  ` ` and `_` force air.
##
## Because the same room must be encounterable from any of the four viewing
## planes, every template supports rotation about Y into all four orientations
## plus an X mirror. `stamp()` maps template coordinates through the transform,
## so nothing is duplicated in memory.
class_name StructTemplate
extends RefCounted

var id: StringName = &""
var legend: Dictionary = {}
## slices[z] -> Array[String]; row 0 is the *top* (highest Y).
var slices: Array = []
var size_x: int = 0
var size_y: int = 0
var size_z: int = 0
## Subtracted from `origin` at stamp time. Set it to the doorway voxel so the
## placer can align a template to a path instead of to its corner.
var anchor: Vector3i = Vector3i.ZERO
## Default theme when the caller does not pass one.
var theme: StringName = StructPalette.THEME_NATURAL
## Free-form authoring notes: entrance axes, tier hints, puzzle role.
var meta: Dictionary = {}


static func make(p_id: StringName, p_legend: Dictionary, p_slices: Array,
		p_meta: Dictionary = {}) -> StructTemplate:
	var t := StructTemplate.new()
	t.id = p_id
	t.legend = p_legend
	t.slices = p_slices
	t.meta = p_meta
	t.theme = p_meta.get("theme", StructPalette.THEME_NATURAL)
	t.anchor = p_meta.get("anchor", Vector3i.ZERO)
	t._measure()
	return t


func _measure() -> void:
	size_z = slices.size()
	size_y = 0
	size_x = 0
	for s: Array in slices:
		size_y = maxi(size_y, s.size())
		for row: String in s:
			size_x = maxi(size_x, row.length())


func size() -> Vector3i:
	return Vector3i(size_x, size_y, size_z)


## Footprint after rotation — X and Z swap for odd rotations.
func rotated_size(rot: int) -> Vector3i:
	return Vector3i(size_z, size_y, size_x) if (rot & 1) == 1 else Vector3i(size_x, size_y, size_z)


## Inclusive world bounds this template would occupy.
func bounds(origin: Vector3i, rot: int = 0) -> Array:
	var s := rotated_size(rot)
	var lo := origin - _rotate_anchor(rot)
	return [lo, lo + s - Vector3i(1, 1, 1)]


func _rotate_anchor(rot: int) -> Vector3i:
	var p := _xform(anchor, rot, false)
	return p


## Template coords -> rotated-box coords. Mirror is applied first, on X.
func _xform(p: Vector3i, rot: int, mirror: bool) -> Vector3i:
	var x := p.x
	var z := p.z
	if mirror:
		x = size_x - 1 - x
	match rot & 3:
		1: return Vector3i(size_z - 1 - z, p.y, x)
		2: return Vector3i(size_x - 1 - x, p.y, size_z - 1 - z)
		3: return Vector3i(z, p.y, size_x - 1 - x)
		_: return Vector3i(x, p.y, z)


## Rotate a world axis label ("x"/"z") by the same amount as the geometry.
static func rotate_axis(axis: String, rot: int) -> String:
	if (rot & 1) == 0:
		return axis
	return "z" if axis == "x" else "x"


# ==================================================================== stamping
## Required entry point: draw this template into `chunk`, anchored at `origin`,
## rotated `rotation` * 90 degrees about Y.
##
## `opts`: theme, tier, mirror(bool), seed(int), rng, struct_id(String),
## village_id(int), loot_table(String), foundation(int block id).
func stamp(chunk: Chunk, origin: Vector3i, rotation: int = 0, opts: Dictionary = {}) -> void:
	stamp_on(StructCanvas.new(chunk), origin, rotation, opts)


## Same, against an already-bound canvas (what the placer and generators use).
func stamp_on(canvas: StructCanvas, origin: Vector3i, rotation: int = 0,
		opts: Dictionary = {}) -> void:
	var rot := rotation & 3
	var mirror: bool = bool(opts.get("mirror", false))
	var base := origin - _rotate_anchor(rot)
	var rs := rotated_size(rot)
	if not canvas.intersects(base, base + rs - Vector3i(1, 1, 1)):
		return
	var th: StringName = opts.get("theme", theme)
	var tier: int = int(opts.get("tier", 0))
	var seed_value: int = int(opts.get("seed", 0))
	var r: RandomNumberGenerator = opts.get("rng", StructRng.rng(seed_value, base.x, base.y, base.z))
	var resolved := _resolve_legend(th)

	for z in range(slices.size()):
		var slice: Array = slices[z]
		for row_i in range(slice.size()):
			var row: String = slice[row_i]
			var y := size_y - 1 - row_i
			for x in range(row.length()):
				var ch := row[x]
				var e: Dictionary = resolved.get(ch, {})
				if e.is_empty() or e.get("keep", false):
					continue
				var chance: float = e.get("chance", 1.0)
				if chance < 1.0 and r.randf() > chance:
					continue
				var wp := base + _xform(Vector3i(x, y, z), rot, mirror)
				var bid: int = e.get("id", Const.AIR)
				var mk: Dictionary = e.get("marker", {})
				if mk.is_empty():
					canvas.put(wp, bid)
				else:
					var payload := _build_marker(mk, wp, rot, th, tier, seed_value, opts)
					if payload.is_empty():
						canvas.put(wp, bid)
					else:
						canvas.put_tile(wp, bid, payload)
				var lq: int = int(e.get("liquid", 0))
				if lq > 0:
					canvas.set_liquid(wp, lq)

	var foundation: int = int(opts.get("foundation", -1))
	if foundation >= 0:
		_pour_foundation(canvas, base, rs, foundation, int(opts.get("foundation_depth", 6)))


## Fill under the template's footprint so it never floats over a slope.
func _pour_foundation(canvas: StructCanvas, base: Vector3i, rs: Vector3i, id: int, depth: int) -> void:
	canvas.box_soft(Vector3i(base.x, base.y - depth, base.z),
			Vector3i(base.x + rs.x - 1, base.y - 1, base.z + rs.z - 1), id)


func _resolve_legend(th: StringName) -> Dictionary:
	var out := {}
	out["."] = {"keep": true}
	out["?"] = {"keep": true}
	out[" "] = {"id": Const.AIR}
	out["_"] = {"id": Const.AIR}
	for k in legend:
		var ch := String(k)
		var v: Variant = legend[k]
		var e := {}
		if v is Dictionary:
			e = (v as Dictionary).duplicate()
		else:
			e = {"block": v}
		if e.get("keep", false):
			out[ch] = {"keep": true}
			continue
		if e.get("air", false):
			e["id"] = Const.AIR
		elif e.has("role"):
			e["id"] = StructPalette.block(th, e["role"])
		elif e.has("generic"):
			e["id"] = StructPalette.generic(e["generic"], e.get("role_fallback", &"accent"))
		elif e.has("block"):
			var b: Variant = e["block"]
			if b is Array:
				e["id"] = StructPalette.named(b, e.get("fallback", &""))
			else:
				e["id"] = StructPalette.named([StringName(b)], e.get("fallback", &""))
		else:
			e["id"] = Const.AIR
		out[ch] = e
	return out


## Build a tile-data payload from a legend marker spec.
func _build_marker(spec: Dictionary, wp: Vector3i, rot: int, th: StringName,
		tier: int, seed_value: int, opts: Dictionary) -> Dictionary:
	var struct_id: String = opts.get("struct_id", String(id))
	var s := StructRng.hash4(seed_value, wp.x, wp.y, wp.z)
	match String(spec.get("kind", "")):
		"container":
			return StructMarkers.container(
				String(spec.get("table", opts.get("loot_table", "ruins"))),
				tier + int(spec.get("tier_bonus", 0)), th, s, struct_id,
				int(spec.get("capacity", 16)), bool(spec.get("locked", false)),
				String(spec.get("key", "")))
		"spawner":
			return StructMarkers.spawner(
				String(spec.get("pool", "generic")), tier,
				int(spec.get("count", 3)), float(spec.get("radius", 6.0)),
				th, s, bool(spec.get("once", false)),
				String(spec.get("trigger", "proximity")))
		"npc":
			return StructMarkers.npc(
				String(spec.get("role", "villager")), th, wp,
				String(spec.get("job", "")), int(opts.get("village_id", 0)),
				float(spec.get("wander", 8.0)), s,
				String(spec.get("shop", "")), String(spec.get("dialogue", "")))
		"teleporter":
			return StructMarkers.teleporter(
				String(spec.get("network", "ancient_gate")),
				int(spec.get("gate_id", s & 0xFFFFFF)),
				String(spec.get("requires_key", "")),
				bool(spec.get("active", true)))
		"door":
			var ax := String(spec.get("axis", "x"))
			if ax != "any":
				ax = rotate_axis(ax, rot)
			return StructMarkers.door(
				String(spec.get("door_type", String(th) + "_door")), ax,
				bool(spec.get("locked", false)), String(spec.get("key", "")),
				int(spec.get("lock_id", 0)), int(spec.get("width", 1)),
				int(spec.get("height", 2)))
		"lever":
			return StructMarkers.lever(int(spec.get("lock_id", 0)),
				String(spec.get("puzzle", struct_id)), [],
				String(spec.get("hint", "")))
		"trap":
			return StructMarkers.trap(String(spec.get("trap", "dart")), tier,
				float(spec.get("damage", 6.0 + 3.0 * tier)),
				String(spec.get("element", Const.ELEM_PHYSICAL)),
				float(spec.get("radius", 1.5)))
		"light":
			return StructMarkers.light(String(spec.get("fixture", "lamp")),
				int(spec.get("level", 12)))
		"sign":
			return StructMarkers.sign(String(spec.get("text", "")),
				String(spec.get("lore", "")))
	return {}
