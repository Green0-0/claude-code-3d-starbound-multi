## Coherent settlements: a paved plaza, 4-10 themed buildings sited on the real
## terrain, paths that join them, lamp posts, farm plots and NPC spawn markers.
##
## ## Layout
##
## The plaza sits at the anchor. Building plots are dealt onto a loose ring
## around it; each plot is re-grounded with `gen.height_at()` so a village drapes
## over a hillside instead of floating. Paths are drawn as an L (X leg then Z
## leg) from the plaza to every door — which also means every village has a main
## street readable from the North/South planes and side streets readable from
## West/East, so the settlement never looks like a single flat facade.
##
## One building per village is given a **cellar whose stair is one layer behind
## the back wall**: from the street plane it is a solid wall, and only a `PgDn`
## shift reveals the opening. That is the tutorialising, low-stakes version of
## the perspective puzzles in `perspective_structs.gd`.
##
## ## NPC hand-off (no hard dependency)
##
## Villagers are never spawned here. Every building writes an
## `npc_spawn` tile-data payload (see `StructMarkers`) at its bed / counter /
## post. The entities agent scans loaded chunks for `kind == "npc_spawn"` and
## instantiates whatever it likes. Payload:
##
## ```
## {"kind":"npc_spawn", "role":"villager"|"merchant"|"guard"|"questgiver",
##  "species":"<theme>", "job":"farmer"|"smith"|"innkeeper"|..., "faction":"village",
##  "home":[x,y,z], "work":null, "wander":8.0, "village_id":<int>,
##  "dialogue":"", "shop":"<shop id or empty>", "seed":<int>}
## ```
##
## `village_id` is stable for a given settlement, so every NPC of one village can
## be grouped without any extra bookkeeping.
class_name StructVillageGen
extends RefCounted

const PLAZA_R := 6
const PAD := 40
const RING_MIN := 11
const RING_MAX := 26

## Building kinds and the jobs / loot they imply.
const KINDS := [
	{"kind": "house", "job": "villager", "role": "villager", "table": "village_house", "w": 7, "d": 7, "h": 5, "weight": 4.0},
	{"kind": "cottage", "job": "villager", "role": "villager", "table": "village_house", "w": 6, "d": 5, "h": 4, "weight": 3.0},
	{"kind": "store", "job": "merchant", "role": "merchant", "table": "village_store", "w": 9, "d": 7, "h": 5, "weight": 2.0, "unique": true},
	{"kind": "inn", "job": "innkeeper", "role": "merchant", "table": "village_store", "w": 9, "d": 9, "h": 7, "weight": 1.5, "unique": true},
	{"kind": "smithy", "job": "smith", "role": "merchant", "table": "forge", "w": 7, "d": 7, "h": 5, "weight": 1.5, "unique": true},
	{"kind": "guard_post", "job": "guard", "role": "guard", "table": "outpost", "w": 5, "d": 5, "h": 9, "weight": 1.5},
	{"kind": "farmhouse", "job": "farmer", "role": "villager", "table": "farm", "w": 7, "d": 6, "h": 4, "weight": 2.5},
	{"kind": "workshop", "job": "artisan", "role": "villager", "table": "village_house", "w": 7, "d": 6, "h": 5, "weight": 2.0},
]


# =================================================================== front door
static func build(canvas: StructCanvas, ctx: Dictionary) -> void:
	var layout := plan(ctx)
	render(canvas, layout, ctx)


## Whole-settlement layout. Pure in (ctx.seed, terrain heights).
static func plan(ctx: Dictionary) -> Dictionary:
	var seed_value: int = int(ctx.get("seed", 0))
	var origin: Vector3i = ctx.get("origin", Vector3i.ZERO)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)
	var gen: Variant = ctx.get("gen", null)
	var r := StructRng.rng(seed_value, 0x1EEE, 0, 0)
	var village_id: int = absi(StructRng.hash3(seed_value, origin.x, origin.z)) % 100000000

	var count := r.randi_range(4, 10)
	var used: Array = []
	var plots: Array = []
	var angle_step := TAU / float(count)
	var angle := r.randf() * TAU

	for i in range(count):
		var kind := _pick_kind(r, used)
		var dist := float(r.randi_range(RING_MIN, RING_MAX))
		var a := angle + angle_step * float(i) + r.randf_range(-0.25, 0.25)
		var px := origin.x + int(round(cos(a) * dist))
		var pz := origin.z + int(round(sin(a) * dist))
		# Face the plaza: rot 0 puts the door on -Z, so pick by dominant offset.
		var dx := px - origin.x
		var dz := pz - origin.z
		var rot := 0
		if absi(dx) > absi(dz):
			rot = 1 if dx > 0 else 3
		else:
			rot = 0 if dz > 0 else 2
		plots.append({
			"pos": Vector3i(px, _ground(gen, px, pz, origin.y), pz),
			"kind": kind, "rot": rot, "index": i,
			"seed": StructRng.hash4(seed_value, px, i, pz),
		})

	# One building gets the hidden cellar.
	if not plots.is_empty():
		plots[r.randi_range(0, plots.size() - 1)]["cellar"] = true

	var farms: Array = []
	for i in range(r.randi_range(1, 3)):
		var a := r.randf() * TAU
		var dist := float(r.randi_range(RING_MAX - 6, RING_MAX + 6))
		var fx := origin.x + int(round(cos(a) * dist))
		var fz := origin.z + int(round(sin(a) * dist))
		farms.append({
			"pos": Vector3i(fx, _ground(gen, fx, fz, origin.y), fz),
			"w": r.randi_range(5, 9), "d": r.randi_range(5, 9),
			"seed": StructRng.hash4(seed_value, fx, 77, fz),
		})

	return {
		"centre": origin, "theme": theme, "village_id": village_id,
		"plots": plots, "farms": farms, "seed": seed_value,
		"name": _village_name(theme, village_id),
	}


static func _pick_kind(r: RandomNumberGenerator, used: Array) -> Dictionary:
	var pool: Array = []
	for k: Dictionary in KINDS:
		if bool(k.get("unique", false)) and used.has(k["kind"]):
			continue
		pool.append([k, float(k["weight"])])
	if pool.is_empty():
		return KINDS[0]
	var picked: Variant = StructRng.weighted_pick(r.randi(), pool)
	var out: Dictionary = picked if picked is Dictionary else KINDS[0]
	used.append(out["kind"])
	return out


static func _ground(gen: Variant, x: int, z: int, fallback: int) -> int:
	if gen != null and gen.has_method(&"height_at"):
		return clampi(int(gen.height_at(posmod(x, maxi(1, World.size_x)),
				posmod(z, maxi(1, World.size_z)))), 4, Const.WORLD_HEIGHT - 20) + 1
	return fallback


static func _village_name(theme: StringName, vid: int) -> String:
	const FIRST := ["Green", "Stone", "Iron", "Red", "Long", "Far", "Salt", "Wind",
			"Ash", "Bright", "Old", "Deep"]
	const SECOND := ["hollow", "reach", "ford", "bank", "wick", "gate", "rest",
			"march", "haven", "cross", "barrow", "watch"]
	return "%s%s" % [FIRST[vid % FIRST.size()], SECOND[(vid / 13) % SECOND.size()]]


# ===================================================================== drawing
static func render(canvas: StructCanvas, layout: Dictionary, ctx: Dictionary) -> void:
	var theme: StringName = layout["theme"]
	var kit := StructPalette.kit(theme)
	var tier: int = int(ctx.get("tier", 0))
	var centre: Vector3i = layout["centre"]
	var vid: int = layout["village_id"]
	var seed_value: int = int(layout["seed"])

	_draw_plaza(canvas, layout, kit, tier)
	for plot: Dictionary in layout["plots"]:
		_draw_path(canvas, centre, plot["pos"], kit, seed_value)
	for plot: Dictionary in layout["plots"]:
		_draw_building(canvas, layout, plot, kit, tier)
	for farm: Dictionary in layout["farms"]:
		_draw_farm(canvas, layout, farm, kit, tier)

	canvas.tile(centre, StructMarkers.anchor("village", theme, tier, centre,
		Vector3i(PAD * 2, 24, PAD * 2), seed_value, layout["name"]))


static func _draw_plaza(canvas: StructCanvas, layout: Dictionary, kit: Dictionary,
		tier: int) -> void:
	var c: Vector3i = layout["centre"]
	if not canvas.intersects_radius(c, PLAZA_R + 4):
		return
	var theme: StringName = layout["theme"]
	var r := StructRng.rng(int(layout["seed"]), c.x, c.y, c.z)

	# Paving, one block below walking level, and clear headroom above it.
	canvas.cylinder(Vector3i(c.x, c.y - 1, c.z), PLAZA_R, 1, kit[&"path"])
	for dy in range(0, 4):
		canvas.cylinder(Vector3i(c.x, c.y + dy, c.z), PLAZA_R, 1, Const.AIR)

	# Monument / well in the middle — the village's visual anchor from all four
	# planes, so it is deliberately radially symmetric.
	canvas.cylinder(Vector3i(c.x, c.y, c.z), 2, 1, kit[&"trim"])
	canvas.box(Vector3i(c.x, c.y + 1, c.z), Vector3i(c.x, c.y + 3, c.z), kit[&"pillar"])
	if kit[&"light"] != Const.AIR:
		canvas.put(Vector3i(c.x, c.y + 4, c.z), kit[&"light"])

	# Notice board + the village questgiver.
	var board := Vector3i(c.x + 3, c.y + 1, c.z + 3)
	canvas.put_tile(board, StructPalette.generic(&"sign", &"accent"),
		StructMarkers.sign(layout["name"], "Village notice board."))
	canvas.tile(board + Vector3i(0, 0, 1), StructMarkers.npc(
		"questgiver", theme, board + Vector3i(0, 0, 1), "elder",
		int(layout["village_id"]), 10.0, StructRng.hash2(int(layout["seed"]), 0x9E5)))

	# Lamp posts on the four cardinal points — one is always facing the camera
	# whichever plane the player is on.
	for d: Vector3i in [Vector3i(PLAZA_R - 1, 0, 0), Vector3i(-(PLAZA_R - 1), 0, 0),
			Vector3i(0, 0, PLAZA_R - 1), Vector3i(0, 0, -(PLAZA_R - 1))]:
		_lamp_post(canvas, c + d, kit)
	canvas.scatter(Vector3i(c.x - PLAZA_R, c.y, c.z - PLAZA_R),
			Vector3i(c.x + PLAZA_R, c.y, c.z + PLAZA_R), kit[&"rubble"], 0.02, r)


static func _lamp_post(canvas: StructCanvas, base: Vector3i, kit: Dictionary) -> void:
	canvas.box(base, base + Vector3i(0, 3, 0), kit[&"pillar"])
	var lid: int = kit[&"light"]
	if lid != Const.AIR:
		canvas.put(base + Vector3i(0, 4, 0), lid)
		canvas.tile(base + Vector3i(0, 4, 0), StructMarkers.light("lamp_post", 13))


## L-shaped street: X leg then Z leg. Terrain-following, one block wide plus
## verges, so it stays walkable in whichever plane you approach from.
static func _draw_path(canvas: StructCanvas, from: Vector3i, to: Vector3i,
		kit: Dictionary, seed_value: int) -> void:
	var path_id: int = kit[&"path"]
	var lo := Vector3i(mini(from.x, to.x) - 2, mini(from.y, to.y) - 3, mini(from.z, to.z) - 2)
	var hi := Vector3i(maxi(from.x, to.x) + 2, maxi(from.y, to.y) + 4, maxi(from.z, to.z) + 2)
	if not canvas.intersects(lo, hi):
		return
	var steps_x := absi(to.x - from.x)
	var steps_z := absi(to.z - from.z)
	var sx := signi(to.x - from.x)
	var sz := signi(to.z - from.z)
	var total := maxi(1, steps_x + steps_z)
	var lamp_every := 7
	var walked := 0
	var p := from
	for i in range(steps_x):
		p = Vector3i(from.x + sx * (i + 1), 0, from.z)
		_pave(canvas, p, from, to, total, walked, path_id, kit, lamp_every)
		walked += 1
	for i in range(steps_z):
		p = Vector3i(to.x, 0, from.z + sz * (i + 1))
		_pave(canvas, p, from, to, total, walked, path_id, kit, lamp_every)
		walked += 1


static func _pave(canvas: StructCanvas, p: Vector3i, from: Vector3i, to: Vector3i,
		total: int, walked: int, path_id: int, kit: Dictionary, lamp_every: int) -> void:
	var t := float(walked) / float(total)
	var y := int(round(lerpf(float(from.y), float(to.y), t)))
	canvas.put(Vector3i(p.x, y - 1, p.z), path_id)
	canvas.carve_box(Vector3i(p.x, y, p.z), Vector3i(p.x, y + 2, p.z))
	if walked > 0 and walked % lamp_every == 0:
		_lamp_post(canvas, Vector3i(p.x + 1, y, p.z + 1), kit)


# ---------------------------------------------------------------- buildings
static func _draw_building(canvas: StructCanvas, layout: Dictionary, plot: Dictionary,
		kit: Dictionary, tier: int) -> void:
	var spec: Dictionary = plot["kind"]
	var pos: Vector3i = plot["pos"]
	var rot: int = plot["rot"]
	var w: int = spec["w"]
	var d: int = spec["d"]
	var h: int = spec["h"]
	if (rot & 1) == 1:
		var t := w
		w = d
		d = t
	var hw := w / 2
	var hd := d / 2
	var lo := Vector3i(pos.x - hw, pos.y, pos.z - hd)
	var hi := Vector3i(pos.x + hw, pos.y + h, pos.z + hd)
	if not canvas.intersects(lo - Vector3i(1, 8, 1), hi + Vector3i(1, 3, 1)):
		return

	var theme: StringName = layout["theme"]
	var r := StructRng.rng(int(plot["seed"]), pos.x, pos.y, pos.z)

	# Foundation down to whatever terrain is under us.
	canvas.box_soft(Vector3i(lo.x, lo.y - 8, lo.z), Vector3i(hi.x, lo.y - 1, hi.z), kit[&"wall"])
	canvas.room(lo, hi, kit[&"wall"], kit[&"floor"], kit[&"roof"])

	# Door faces the plaza. `rot` 0/2 -> door on the Z faces (walk it in views
	# 1/3), 1/3 -> door on the X faces (walk it in views 0/2).
	var door_axis := "z" if (rot & 1) == 0 else "x"
	var dpos: Vector3i
	match rot:
		0: dpos = Vector3i(pos.x, pos.y + 1, lo.z)
		2: dpos = Vector3i(pos.x, pos.y + 1, hi.z)
		1: dpos = Vector3i(lo.x, pos.y + 1, pos.z)
		_: dpos = Vector3i(hi.x, pos.y + 1, pos.z)
	canvas.carve_box(dpos, dpos + Vector3i(0, 1, 0))
	canvas.put_tile(dpos, kit[&"door"] if kit[&"door"] != Const.AIR else Const.AIR,
		StructMarkers.door("%s_door" % theme, door_axis, false, "", 0, 1, 2))

	# Windows on every wall so the building reads from all four planes.
	var glass: int = kit[&"glass"]
	if glass != Const.AIR:
		for off in [-1, 1]:
			canvas.put(Vector3i(pos.x + off * (hw / 2 + 1), pos.y + 2, lo.z), glass)
			canvas.put(Vector3i(pos.x + off * (hw / 2 + 1), pos.y + 2, hi.z), glass)
			canvas.put(Vector3i(lo.x, pos.y + 2, pos.z + off * (hd / 2 + 1)), glass)
			canvas.put(Vector3i(hi.x, pos.y + 2, pos.z + off * (hd / 2 + 1)), glass)

	# Roof: a simple overhang ridge, still legible as a silhouette from a flat
	# side view (the only way the player ever sees it).
	canvas.box(Vector3i(lo.x - 1, hi.y, lo.z - 1), Vector3i(hi.x + 1, hi.y, hi.z + 1), kit[&"roof"])
	canvas.box(Vector3i(lo.x, hi.y + 1, pos.z), Vector3i(hi.x, hi.y + 1, pos.z), kit[&"roof"])

	if kit[&"light"] != Const.AIR:
		canvas.put(Vector3i(pos.x, hi.y - 1, pos.z), kit[&"light"])

	_furnish_building(canvas, layout, plot, spec, kit, tier, lo, hi, r)

	if bool(plot.get("cellar", false)):
		_draw_hidden_cellar(canvas, layout, pos, kit, tier, r)


static func _furnish_building(canvas: StructCanvas, layout: Dictionary, plot: Dictionary,
		spec: Dictionary, kit: Dictionary, tier: int, lo: Vector3i, hi: Vector3i,
		r: RandomNumberGenerator) -> void:
	var theme: StringName = layout["theme"]
	var vid: int = layout["village_id"]
	var pos: Vector3i = plot["pos"]
	var inner_lo := lo + Vector3i(1, 1, 1)
	var inner_hi := hi - Vector3i(1, 1, 1)
	var kind := String(spec["kind"])

	# Bed / post: also the NPC's home marker.
	var home := Vector3i(inner_lo.x, pos.y + 1, inner_lo.z)
	var bed := StructPalette.generic(&"bed", &"cloth")
	if bed != Const.AIR:
		canvas.box(home, home + Vector3i(0, 0, 1), bed)
	canvas.tile(home, StructMarkers.npc(String(spec["role"]), theme, home,
		String(spec["job"]), vid, 9.0, int(plot["seed"]),
		("%s_%s" % [theme, kind]) if String(spec["role"]) == "merchant" else ""))

	# Storage.
	var chest := StructPalette.generic(&"chest", &"accent")
	var cp := Vector3i(inner_hi.x, pos.y + 1, inner_hi.z)
	canvas.put_tile(cp, chest if chest != Const.AIR else kit[&"accent"],
		StructLoot.chest(String(spec["table"]), tier, theme,
			StructRng.hash4(int(plot["seed"]), cp.x, cp.y, cp.z), "village_" + kind))

	var table := StructPalette.generic(&"table", &"trim")
	if table != Const.AIR:
		canvas.put(Vector3i(pos.x, pos.y + 1, pos.z), table)

	match kind:
		"smithy":
			var furnace := StructPalette.generic(&"furnace", &"accent")
			var anvil := StructPalette.generic(&"anvil", &"trim")
			canvas.put(Vector3i(inner_hi.x, pos.y + 1, inner_lo.z), furnace)
			canvas.put(Vector3i(inner_hi.x - 1, pos.y + 1, inner_lo.z), anvil)
		"guard_post":
			# Watch platform on the roof with a guard marker: a landmark from
			# every plane and a sniper's nest in two of them.
			canvas.carve_box(Vector3i(lo.x + 1, hi.y, lo.z + 1), Vector3i(hi.x - 1, hi.y, hi.z - 1))
			canvas.walls(Vector3i(lo.x, hi.y + 1, lo.z), Vector3i(hi.x, hi.y + 2, hi.z), kit[&"wall"])
			canvas.tile(Vector3i(pos.x, hi.y + 1, pos.z), StructMarkers.npc(
				"guard", theme, Vector3i(pos.x, hi.y + 1, pos.z), "watch", vid, 4.0,
				int(plot["seed"]) ^ 0x6A1D))
		"inn":
			for i in range(2):
				var b := Vector3i(inner_hi.x - i * 2, pos.y + 1, inner_lo.z)
				if bed != Const.AIR:
					canvas.box(b, b + Vector3i(0, 0, 1), bed)
				canvas.tile(b, StructMarkers.npc("villager", theme, b, "guest", vid,
					12.0, StructRng.hash3(int(plot["seed"]), i, 0x1EE)))
		"farmhouse":
			canvas.tile(Vector3i(pos.x, pos.y + 1, inner_hi.z), StructMarkers.npc(
				"villager", theme, Vector3i(pos.x, pos.y + 1, inner_hi.z), "farmhand",
				vid, 14.0, int(plot["seed"]) ^ 0x5A11))
		"store":
			canvas.tile(Vector3i(pos.x, pos.y + 1, pos.z + 1), StructMarkers.npc(
				"merchant", theme, Vector3i(pos.x, pos.y + 1, pos.z + 1), "shopkeeper",
				vid, 3.0, int(plot["seed"]) ^ 0x570E, "%s_general" % theme))


## The one perspective beat every village gets: a cellar whose only stair is one
## voxel layer behind the back wall. From the street plane the wall is unbroken;
## shift a single layer and the stairwell is simply there.
static func _draw_hidden_cellar(canvas: StructCanvas, layout: Dictionary, pos: Vector3i,
		kit: Dictionary, tier: int, r: RandomNumberGenerator) -> void:
	var theme: StringName = layout["theme"]
	var top := pos.y
	var floor_y := top - 6
	var c := Vector3i(pos.x, floor_y, pos.z + 4)
	if not canvas.intersects(c - Vector3i(5, 1, 5), Vector3i(pos.x + 2, top + 1, pos.z + 8)):
		return
	canvas.room(c - Vector3i(4, 0, 4), c + Vector3i(4, 4, 4), kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	# Stair well: offset one layer in Z from the building's back wall line.
	var sx := pos.x
	var sz := pos.z + 1
	for i in range(6):
		canvas.carve_box(Vector3i(sx, top - i, sz + i), Vector3i(sx, top - i + 2, sz + i))
		canvas.put(Vector3i(sx, top - i - 1, sz + i), kit[&"floor"])
	# Seal the layer the street sits on so the stair is invisible from it.
	canvas.box(Vector3i(sx, top - 6, pos.z), Vector3i(sx, top, pos.z), kit[&"wall"])
	var chest := StructPalette.generic(&"chest", &"accent")
	canvas.put_tile(c + Vector3i(2, 1, 2), chest if chest != Const.AIR else kit[&"accent"],
		StructLoot.chest("treasure", tier + 1, theme,
			StructRng.hash2(int(layout["seed"]), 0xCE11), "village_cellar"))
	if kit[&"light"] != Const.AIR:
		canvas.put(c + Vector3i(0, 4, 0), kit[&"light"])


# -------------------------------------------------------------------- farms
static func _draw_farm(canvas: StructCanvas, layout: Dictionary, farm: Dictionary,
		kit: Dictionary, tier: int) -> void:
	var p: Vector3i = farm["pos"]
	var w: int = farm["w"]
	var d: int = farm["d"]
	var lo := Vector3i(p.x - w / 2, p.y - 1, p.z - d / 2)
	var hi := Vector3i(p.x + w / 2, p.y - 1, p.z + d / 2)
	if not canvas.intersects(lo - Vector3i(1, 2, 1), hi + Vector3i(1, 4, 1)):
		return
	var r := StructRng.rng(int(farm["seed"]), p.x, p.y, p.z)
	var soil: int = StructPalette.named([&"farmland", &"tilled_soil", &"soil"], &"dirt")
	canvas.box(lo, hi, soil)
	canvas.carve_box(lo + Vector3i(0, 1, 0), hi + Vector3i(0, 3, 0))

	var crop: int = StructPalette.named([&"wheat", &"crop", &"wheat_crop"], &"")
	if crop != Const.AIR:
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				if (x + z) % 2 == 0:
					canvas.put(Vector3i(x, lo.y + 1, z), crop)

	# Irrigation channel: also a readable dark line in the side view.
	var water := Blocks.id(&"water")
	for x in range(lo.x, hi.x + 1):
		canvas.put(Vector3i(x, lo.y, p.z), water)
		canvas.set_liquid(Vector3i(x, lo.y, p.z), Const.MAX_LIQUID)

	var fence: int = kit[&"fence"]
	if fence != Const.AIR:
		canvas.rect_xz(lo - Vector3i(1, 0, 1), hi + Vector3i(1, 0, 1), lo.y + 1, fence)

	# Scarecrow doubles as the farmhand's work marker.
	var sc := Vector3i(p.x, lo.y + 1, p.z + d / 2)
	canvas.box(sc, sc + Vector3i(0, 1, 0), kit[&"pillar"])
	canvas.tile(sc, StructMarkers.npc("villager", layout["theme"], sc, "farmer",
		int(layout["village_id"]), 12.0, int(farm["seed"])))
	canvas.scatter(lo, hi, kit[&"rubble"], 0.02, r)
