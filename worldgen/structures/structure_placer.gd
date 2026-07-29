## The structure dispatcher — the single entry point the terrain agent calls.
##
##     StructPlacer.populate(chunk, PlanetGen)
##
## Call it once per chunk, after terrain/caves/ores have been written and before
## the chunk is handed to lighting. It is safe to call in any order, from any
## thread-free context, and safe to call twice (it is idempotent for a given
## seed, though re-running wastes work).
##
## ## How placement stays deterministic
##
## The world is tiled by coarse **placement cells** — one grid per placement
## class (villages on a 128-block grid, mini-encounters on a 32-block grid, and
## so on). For every cell we hash `(world seed, class, wrapped cell coords, slot)`
## and that hash alone decides:
##   * whether the cell is occupied at all (`fill` density),
##   * where inside the cell the structure is anchored (jitter),
##   * which registered structure wins the weighted roll,
##   * its theme, tier and per-structure RNG seed.
##
## Nothing depends on which chunk asked. A structure that spans eight chunks is
## therefore generated eight times — but each run is handed a `StructCanvas`
## clipped to one chunk, so each run writes only its own slice and the pieces
## line up exactly. Cells are hashed on *wrapped* coordinates but positioned on
## *un-wrapped* ones, which makes the planet's X/Z seam invisible.
##
## Structures never overlap across classes: a candidate is rejected if a
## higher-priority class already claimed overlapping ground at a similar height.
## That test also depends only on position, never on the asking chunk.
class_name StructPlacer
extends RefCounted

const CONTENT_SURFACE := preload("res://worldgen/structures/structures/surface_structs.gd")
const CONTENT_UNDERGROUND := preload("res://worldgen/structures/structures/underground_structs.gd")
const CONTENT_PERSPECTIVE := preload("res://worldgen/structures/structures/perspective_structs.gd")

## Placement classes, coarsest first. `cell` must be a power of two so the grid
## tiles a wrapping planet without a seam. `slots` gives a class more than one
## structure per column (used underground, where depth gives room for several).
const CLASSES := {
	&"surface_major": {"cell": 128, "fill": 0.55, "slots": 1, "priority": 0, "margin": 24},
	&"dungeon": {"cell": 128, "fill": 0.55, "slots": 1, "priority": 1, "margin": 24},
	&"surface_minor": {"cell": 64, "fill": 0.60, "slots": 1, "priority": 2, "margin": 12},
	&"underground": {"cell": 64, "fill": 0.62, "slots": 2, "priority": 3, "margin": 10},
	&"mini": {"cell": 32, "fill": 0.52, "slots": 3, "priority": 4, "margin": 5},
}

## Vertical slack for the cross-class exclusion test. Two structures may share
## ground plan as long as they are further apart than this in Y. Fill rates
## above are set *after* exclusion thinning, which is why the lower-priority
## classes look generous: most of their rolls are eaten by the classes above.
const EXCLUSION_Y := 18

static var _defs: Array = []
static var _by_class: Dictionary = {}
static var _class_pad: Dictionary = {}
static var _ready := false
static var _last_seed: int = 0x7FFFFFFF


# ================================================================== entry point
## Populate `chunk` with every structure that overlaps it.
## `gen` is the `PlanetGen` autoload — only `height_at(x,z)` and `biome_at(x,z)`
## are used, and both are probed with `has_method` so a stub generator is fine.
static func populate(chunk: Chunk, gen) -> void:
	if chunk == null:
		return
	if Blocks.count() <= 1:
		return
	_ensure_registry()
	var world_seed := World.seed_value
	if world_seed != _last_seed:
		_last_seed = world_seed
		StructPalette.invalidate()
	var canvas := StructCanvas.new(chunk)
	var cache: Dictionary = {}
	var accepted: Array = []

	for class_id: StringName in _ordered_classes():
		var list: Array = _by_class.get(class_id, [])
		if list.is_empty():
			continue
		for p: Dictionary in _candidates_near(class_id, canvas, world_seed, gen, cache):
			if not canvas.intersects(p["lo"], p["hi"]):
				continue
			if _is_blocked(p, world_seed, gen, cache):
				continue
			accepted.append(p)

	for p: Dictionary in accepted:
		_build(canvas, p, gen)
	chunk.populated = true


## Structures whose bounds touch this chunk, for one class.
static func _candidates_near(class_id: StringName, canvas: StructCanvas,
		world_seed: int, gen, cache: Dictionary) -> Array:
	var cfg: Dictionary = CLASSES[class_id]
	var cell: int = cfg["cell"]
	var pad: int = _class_pad.get(class_id, 16)
	var out: Array = []
	var i0 := floori(float(canvas.cmin.x - pad) / float(cell))
	var i1 := floori(float(canvas.cmax.x + pad) / float(cell))
	var j0 := floori(float(canvas.cmin.z - pad) / float(cell))
	var j1 := floori(float(canvas.cmax.z + pad) / float(cell))
	var reach := pad + Const.CHUNK_SIZE
	for ci in range(i0, i1 + 1):
		for cj in range(j0, j1 + 1):
			for slot in range(int(cfg["slots"])):
				# Cheap pre-filter: the anchor is a pure hash, so reject cells
				# that cannot possibly reach this chunk before touching the
				# terrain generator at all.
				var roll := _cell_roll(class_id, ci, cj, slot, world_seed)
				if roll.is_empty():
					continue
				if absi(_wrap_delta(int(roll["ax"]) - canvas.cmin.x, World.size_x)) > reach:
					continue
				if absi(_wrap_delta(int(roll["az"]) - canvas.cmin.z, World.size_z)) > reach:
					continue
				var p := _placement(class_id, ci, cj, slot, world_seed, gen, cache)
				if not p.is_empty():
					out.append(p)
	return out


## Shortest signed distance on a wrapping axis.
static func _wrap_delta(d: int, period: int) -> int:
	if period <= 0:
		return d
	return wrapi(d, -(period >> 1), period >> 1)


## The pure-hash half of a placement: is the cell occupied, and where in it does
## the structure stand? No terrain sampling, no registry lookup.
static func _cell_roll(class_id: StringName, ci: int, cj: int, slot: int,
		world_seed: int) -> Dictionary:
	var cfg: Dictionary = CLASSES[class_id]
	var cell: int = cfg["cell"]
	var margin: int = cfg["margin"]
	var class_salt := int(cfg["priority"]) * 7919 + 13
	var nx: int = maxi(1, World.size_x / cell)
	var nz: int = maxi(1, World.size_z / cell)
	var h := StructRng.hash4(world_seed ^ class_salt, posmod(ci, nx), posmod(cj, nz), slot * 31 + 5)
	if StructRng.to_unit(h) > float(cfg["fill"]):
		return {}
	var span: int = maxi(1, cell - margin * 2)
	return {
		"h": h,
		"ax": ci * cell + margin + int(absi(StructRng.mix(h ^ 0x51ED)) % span),
		"az": cj * cell + margin + int(absi(StructRng.mix(h ^ 0x9E37)) % span),
	}


# ============================================================ cell -> placement
## Deterministic answer to "what, if anything, stands in this cell?".
## Memoised per `populate()` call because the exclusion test re-asks a lot.
static func _placement(class_id: StringName, ci: int, cj: int, slot: int,
		world_seed: int, gen, cache: Dictionary) -> Dictionary:
	var key := "%s:%d:%d:%d" % [class_id, ci, cj, slot]
	if cache.has(key):
		return cache[key]
	var result: Dictionary = {}
	cache[key] = result

	# Hash on wrapped cell indices so the planet seam has no discontinuity, but
	# keep the geometric origin un-wrapped so bounds maths stays simple.
	var roll := _cell_roll(class_id, ci, cj, slot, world_seed)
	if roll.is_empty():
		return result
	var h: int = roll["h"]
	var ax: int = roll["ax"]
	var az: int = roll["az"]
	var wx := posmod(ax, maxi(1, World.size_x))
	var wz := posmod(az, maxi(1, World.size_z))

	var biome := _biome_at(gen, wx, wz)
	var ground := _ground_at(gen, wx, wz)
	var sdef := _choose_def(class_id, biome, ground, StructRng.mix(h ^ 0x1234567))
	if sdef.is_empty():
		return result

	var y := _resolve_y(sdef, ground, StructRng.mix(h ^ 0xABCDEF))
	if y < 4 or y > Const.WORLD_HEIGHT - 8:
		return result
	if String(sdef.get("y_mode", "surface")) == "surface" and int(sdef.get("flatness", 0)) > 0:
		if not _is_flat_enough(gen, ax, az, int(sdef["pad"]), int(sdef["flatness"])):
			return result

	var theme := _resolve_theme(sdef, biome, StructRng.mix(h ^ 0x600D))
	var pad: int = int(sdef["pad"])
	var origin := Vector3i(ax, y, az)
	var tier: int = clampi(int(sdef.get("tier", 0)) + _depth_tier(y, ground), 0, 5)
	result = {
		"class": class_id, "def": sdef, "id": String(sdef["id"]),
		"ci": ci, "cj": cj, "slot": slot,
		"origin": origin, "pad": pad, "theme": theme, "tier": tier,
		"biome": biome, "ground": ground,
		"seed": StructRng.hash4(world_seed, ax, y, az),
		"lo": Vector3i(ax - pad, maxi(0, y - int(sdef.get("down", 8))), az - pad),
		"hi": Vector3i(ax + pad, mini(Const.WORLD_HEIGHT - 1, y + int(sdef.get("up", 16))), az + pad),
	}
	cache[key] = result
	return result


## Reject a candidate that another structure already claimed. Higher-priority
## classes always win; inside one class the lexicographically smallest cell wins.
## Depends only on the candidate's own position, so every chunk that overlaps it
## reaches the same verdict regardless of scan order.
static func _is_blocked(p: Dictionary, world_seed: int, gen, cache: Dictionary) -> bool:
	var my_priority: int = int(CLASSES[p["class"]]["priority"])
	var o: Vector3i = p["origin"]
	for class_id: StringName in _ordered_classes():
		var cfg: Dictionary = CLASSES[class_id]
		var same_class: bool = class_id == StringName(p["class"])
		if int(cfg["priority"]) > my_priority:
			break
		var cell: int = cfg["cell"]
		var reach: int = int(p["pad"]) + int(_class_pad.get(class_id, 16))
		var i0 := floori(float(o.x - reach) / float(cell))
		var i1 := floori(float(o.x + reach) / float(cell))
		var j0 := floori(float(o.z - reach) / float(cell))
		var j1 := floori(float(o.z + reach) / float(cell))
		for ci in range(i0, i1 + 1):
			for cj in range(j0, j1 + 1):
				for slot in range(int(cfg["slots"])):
					var q := _placement(class_id, ci, cj, slot, world_seed, gen, cache)
					if q.is_empty():
						continue
					if same_class and not _cell_precedes(q, p):
						continue
					var qo: Vector3i = q["origin"]
					if absi(qo.y - o.y) > EXCLUSION_Y:
						continue
					var clearance: int = int(p["pad"]) + int(q["pad"]) + 4
					if absi(qo.x - o.x) < clearance and absi(qo.z - o.z) < clearance:
						return true
	return false


## Total order on cells of one class, used to break same-class collisions.
static func _cell_precedes(q: Dictionary, p: Dictionary) -> bool:
	if int(q["ci"]) != int(p["ci"]):
		return int(q["ci"]) < int(p["ci"])
	if int(q["cj"]) != int(p["cj"]):
		return int(q["cj"]) < int(p["cj"])
	return int(q["slot"]) < int(p["slot"])


static func _build(canvas: StructCanvas, p: Dictionary, gen) -> void:
	var sdef: Dictionary = p["def"]
	var cb: Callable = sdef.get("build", Callable())
	if not cb.is_valid():
		return
	var ctx := {
		"origin": p["origin"], "theme": p["theme"], "tier": p["tier"],
		"biome": p["biome"], "ground": p["ground"], "seed": p["seed"],
		"id": p["id"], "display": String(sdef.get("display", p["id"])),
		"pad": p["pad"], "lo": p["lo"], "hi": p["hi"], "gen": gen,
		"rng": StructRng.rng(p["seed"], 0x51D, 0, 0),
	}
	# Per-definition constants (boss name, room count, loot table overrides...).
	for k: String in sdef.get("ctx", {}):
		ctx[k] = sdef["ctx"][k]
	cb.call(canvas, ctx)


# =================================================================== selection
static func _choose_def(class_id: StringName, biome: StringName, ground: int, h: int) -> Dictionary:
	var pool: Array = []
	var b := String(biome)
	for sdef: Dictionary in _by_class.get(class_id, []):
		if not _biome_ok(sdef, b):
			continue
		pool.append([sdef, float(sdef.get("weight", 1.0))])
	if pool.is_empty():
		return {}
	var picked: Variant = StructRng.weighted_pick(h, pool)
	return picked if picked is Dictionary else {}


static func _biome_ok(sdef: Dictionary, biome: String) -> bool:
	for bad: String in sdef.get("avoid_biomes", []):
		if biome.contains(bad):
			return false
	var want: Array = sdef.get("biomes", [])
	if want.is_empty():
		return true
	for w: String in want:
		if w == "any" or biome.contains(w):
			return true
	return false


static func _resolve_theme(sdef: Dictionary, biome: StringName, h: int) -> StringName:
	var themes: Array = sdef.get("themes", [])
	if themes.is_empty():
		return StructPalette.theme_for_biome(biome, h)
	return themes[absi(h) % themes.size()]


## `y_mode`: "surface" (sits on the ground), "buried" (y_min..y_max *below*
## ground), "absolute" (world Y range), "sky" (y_min..y_max *above* ground).
static func _resolve_y(sdef: Dictionary, ground: int, h: int) -> int:
	var mode := String(sdef.get("y_mode", "surface"))
	var lo: int = int(sdef.get("y_min", 0))
	var hi: int = int(sdef.get("y_max", 0))
	match mode:
		"buried":
			var d := StructRng.to_range(h, maxi(1, lo), maxi(1, hi))
			return clampi(ground - d, 6, Const.WORLD_HEIGHT - 16)
		"absolute":
			return clampi(StructRng.to_range(h, lo, maxi(lo, hi)), 6, Const.WORLD_HEIGHT - 16)
		"sky":
			return clampi(ground + StructRng.to_range(h, lo, maxi(lo, hi)), 8, Const.WORLD_HEIGHT - 8)
		_:
			return ground + int(sdef.get("y_offset", 1))


## Deeper structures hold better loot and nastier monsters.
static func _depth_tier(y: int, ground: int) -> int:
	var below := ground - y
	if below < 12:
		return 0
	if below < 40:
		return 1
	if below < 72:
		return 2
	return 3


## Surface structures skip cliffsides. Samples the footprint corners + centre.
static func _is_flat_enough(gen, ax: int, az: int, pad: int, tolerance: int) -> bool:
	var lo := 9999
	var hi := -9999
	for o: Vector2i in [Vector2i(0, 0), Vector2i(-pad, -pad), Vector2i(pad, -pad),
			Vector2i(-pad, pad), Vector2i(pad, pad), Vector2i(0, -pad), Vector2i(0, pad),
			Vector2i(-pad, 0), Vector2i(pad, 0)]:
		var g := _ground_at(gen, posmod(ax + o.x, maxi(1, World.size_x)),
				posmod(az + o.y, maxi(1, World.size_z)))
		lo = mini(lo, g)
		hi = maxi(hi, g)
	return (hi - lo) <= tolerance


# ============================================================= generator probes
## Surface height, tolerant of a stub or missing PlanetGen.
static func _ground_at(gen, x: int, z: int) -> int:
	if gen != null and gen.has_method(&"height_at"):
		return clampi(int(gen.height_at(x, z)), 1, Const.WORLD_HEIGHT - 2)
	return 96


static func _biome_at(gen, x: int, z: int) -> StringName:
	if gen != null and gen.has_method(&"biome_at"):
		return StringName(gen.biome_at(x, z))
	return &"plains"


# ==================================================================== registry
static func _ordered_classes() -> Array:
	var ids: Array = CLASSES.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(CLASSES[a]["priority"]) < int(CLASSES[b]["priority"]))
	return ids


static func _ensure_registry() -> void:
	if _ready:
		return
	_ready = true
	_defs.clear()
	CONTENT_SURFACE.register_all(_defs)
	CONTENT_UNDERGROUND.register_all(_defs)
	CONTENT_PERSPECTIVE.register_all(_defs)
	_by_class.clear()
	_class_pad.clear()
	for sdef: Dictionary in _defs:
		var c: StringName = sdef.get("class", &"mini")
		if not CLASSES.has(c):
			push_warning("[StructPlacer] '%s' has unknown class '%s'" % [sdef.get("id", "?"), c])
			continue
		if not _by_class.has(c):
			_by_class[c] = []
		_by_class[c].append(sdef)
		_class_pad[c] = maxi(int(_class_pad.get(c, 0)), int(sdef.get("pad", 16)))


## Force a re-read of the structure registry. Only useful for tooling.
static func reload() -> void:
	_ready = false
	StructPalette.invalidate()
	_ensure_registry()


## Every registered structure definition. Read-only; handy for debug overlays,
## the quest agent ("find me a ruin") and tests.
static func all_defs() -> Array:
	_ensure_registry()
	return _defs


static func def_count() -> int:
	_ensure_registry()
	return _defs.size()


## Look up a definition by id.
static func find_def(id: String) -> Dictionary:
	_ensure_registry()
	for d: Dictionary in _defs:
		if String(d["id"]) == id:
			return d
	return {}


# ============================================================= authoring helper
## Build a structure definition dictionary with sane defaults. Content files use
## this so a typo in a key name shows up as a missing default, not a crash.
##
## `build` is `func(canvas: StructCanvas, ctx: Dictionary) -> void`, where ctx =
## {origin, theme, tier, biome, ground, seed, id, display, pad, lo, hi, gen, rng}.
static func make_def(id: String, display: String, klass: StringName, build: Callable,
		opts: Dictionary = {}) -> Dictionary:
	return StructDef.make(id, display, klass, build, opts)
