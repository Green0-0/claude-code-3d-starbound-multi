## Surface structure content: everything the player can walk into without
## digging. Registered into `StructPlacer` through `register_all()`.
##
## Two authoring styles live side by side here:
##   * **hand-authored templates** (`StructTemplate`) for small, exact rooms —
##     see `_shrine_template()` and `_tomb_template()`;
##   * **generators** for anything that has to adapt to terrain or scale.
##
## Everything is written so it stays legible when the camera flattens it: strong
## silhouettes, doors on named axes, and at least one feature per structure that
## only resolves from a particular plane.
extends RefCounted

static var _shrine_tpl: StructTemplate = null
static var _tomb_tpl: StructTemplate = null


static func register_all(out: Array) -> void:
	# ---------------------------------------------------------------- villages
	out.append(StructDef.make("village", "Village", &"surface_major",
		StructVillageGen.build, {
			"weight": 3.0, "pad": StructVillageGen.PAD, "up": 24, "down": 14,
			"flatness": 7, "avoid_biomes": ["ocean", "lava", "volcan"],
		}))
	out.append(StructDef.make("floran_village", "Floran Warren-Village", &"surface_major",
		StructVillageGen.build, {
			"weight": 1.2, "pad": StructVillageGen.PAD, "up": 24, "down": 14,
			"flatness": 8, "biomes": ["jungle", "forest", "swamp"],
			"themes": [StructPalette.THEME_FLORAN],
		}))
	out.append(StructDef.make("hylotl_village", "Hylotl Shore Village", &"surface_major",
		StructVillageGen.build, {
			"weight": 1.2, "pad": StructVillageGen.PAD, "up": 24, "down": 14,
			"flatness": 6, "biomes": ["beach", "ocean", "reef", "lake"],
			"themes": [StructPalette.THEME_HYLOTL],
		}))

	# ------------------------------------------------------------ big set pieces
	out.append(StructDef.make("avian_temple", "Avian Sky Temple", &"surface_major",
		avian_temple, {
			"weight": 1.5, "pad": 22, "up": 34, "down": 20, "flatness": 8, "tier": 2,
			"biomes": ["desert", "savanna", "dune", "mesa", "badlands"],
			"themes": [StructPalette.THEME_AVIAN],
		}))
	out.append(StructDef.make("giant_treehouse", "Great Tree Settlement", &"surface_major",
		giant_treehouse, {
			"weight": 1.5, "pad": 20, "up": 46, "down": 12, "flatness": 10, "tier": 1,
			"biomes": ["forest", "jungle", "grove"],
			"themes": [StructPalette.THEME_FLORAN, StructPalette.THEME_NATURAL],
		}))
	out.append(StructDef.make("floran_camp", "Floran Hunting Camp", &"surface_major",
		floran_camp, {
			"weight": 1.4, "pad": 18, "up": 18, "down": 10, "flatness": 8, "tier": 1,
			"biomes": ["jungle", "forest", "swamp", "savanna"],
			"themes": [StructPalette.THEME_FLORAN],
		}))

	# ------------------------------------------------------------------- minor
	out.append(StructDef.make("abandoned_outpost", "Abandoned Outpost", &"surface_minor",
		abandoned_outpost, {"weight": 2.5, "pad": 13, "up": 14, "down": 10, "flatness": 5,
			"themes": [StructPalette.THEME_HUMAN, StructPalette.THEME_APEX]}))
	out.append(StructDef.make("crashed_shuttle", "Crashed Shuttle", &"surface_minor",
		crashed_shuttle, {"weight": 2.0, "pad": 14, "up": 12, "down": 10, "flatness": 9,
			"themes": [StructPalette.THEME_HUMAN, StructPalette.THEME_APEX]}))
	out.append(StructDef.make("bandit_camp", "Bandit Camp", &"surface_minor",
		bandit_camp, {"weight": 2.0, "pad": 13, "up": 12, "down": 8, "flatness": 6, "tier": 1,
			"avoid_biomes": ["ocean"]}))
	out.append(StructDef.make("observatory", "Observatory", &"surface_minor",
		observatory, {"weight": 1.2, "pad": 12, "up": 24, "down": 12, "flatness": 5, "tier": 1,
			"themes": [StructPalette.THEME_HUMAN, StructPalette.THEME_APEX, StructPalette.THEME_HYLOTL]}))
	out.append(StructDef.make("wayside_shrine", "Wayside Shrine", &"surface_minor",
		wayside_shrine, {"weight": 3.0, "pad": 8, "up": 10, "down": 8, "flatness": 4}))
	out.append(StructDef.make("old_well", "Old Well", &"surface_minor",
		old_well, {"weight": 2.5, "pad": 8, "up": 8, "down": 40, "flatness": 4}))
	out.append(StructDef.make("ruined_tower", "Ruined Tower", &"surface_minor",
		ruined_tower, {"weight": 2.2, "pad": 10, "up": 30, "down": 12, "flatness": 6,
			"themes": [StructPalette.THEME_GLITCH, StructPalette.THEME_HUMAN, StructPalette.THEME_ANCIENT]}))
	out.append(StructDef.make("mine_entrance", "Mine Head", &"surface_minor",
		mine_entrance, {"weight": 2.0, "pad": 14, "up": 16, "down": 56, "flatness": 6,
			"avoid_biomes": ["ocean"]}))
	out.append(StructDef.make("watchtower", "Watchtower", &"surface_minor",
		watchtower, {"weight": 2.0, "pad": 9, "up": 22, "down": 10, "flatness": 5,
			"themes": [StructPalette.THEME_GLITCH, StructPalette.THEME_HUMAN, StructPalette.THEME_APEX]}))
	out.append(StructDef.make("standing_stones", "Standing Stones", &"surface_minor",
		standing_stones, {"weight": 2.0, "pad": 14, "up": 12, "down": 8, "flatness": 6,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_NATURAL]}))
	out.append(StructDef.make("graveyard", "Graveyard", &"surface_minor",
		graveyard, {"weight": 1.8, "pad": 13, "up": 10, "down": 18, "flatness": 5,
			"avoid_biomes": ["ocean", "lava"]}))
	out.append(StructDef.make("hylotl_pagoda", "Hylotl Pagoda", &"surface_minor",
		hylotl_pagoda, {"weight": 1.6, "pad": 11, "up": 26, "down": 12, "flatness": 5,
			"biomes": ["beach", "ocean", "reef", "lake", "swamp"],
			"themes": [StructPalette.THEME_HYLOTL]}))
	out.append(StructDef.make("beacon_pylon", "Gate Beacon", &"surface_minor",
		beacon_pylon, {"weight": 0.9, "pad": 9, "up": 20, "down": 10, "flatness": 5, "tier": 2,
			"themes": [StructPalette.THEME_ANCIENT]}))
	out.append(StructDef.make("sky_ruin", "Floating Ruin", &"surface_minor",
		sky_ruin, {"weight": 0.8, "pad": 14, "up": 18, "down": 14, "flatness": 0, "tier": 2,
			"y_mode": "sky", "y_min": 26, "y_max": 54,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_AVIAN]}))

	# --------------------------------------------------------------- mini scatter
	out.append(StructDef.make("hermit_hut", "Hermit's Hut", &"mini",
		StructMiniDungeon.hermit_hut, {"weight": 1.2, "pad": 9, "up": 10, "down": 10, "flatness": 4,
			"avoid_biomes": ["ocean", "lava"]}))
	out.append(StructDef.make("bandit_stash", "Bandit Stash", &"mini",
		StructMiniDungeon.bandit_stash, {"weight": 1.5, "pad": 7, "up": 8, "down": 6, "flatness": 5,
			"avoid_biomes": ["ocean"]}))
	out.append(StructDef.make("geothermal_vent", "Geothermal Vent", &"mini",
		StructMiniDungeon.geothermal_vent, {"weight": 1.2, "pad": 10, "up": 8, "down": 20,
			"flatness": 6, "tier": 1,
			"biomes": ["volcan", "ash", "magma", "barren", "tundra", "desert"]}))


# ==============================================================================
#  Hand-authored templates
# ==============================================================================
## A five-by-five wayside shrine. Read the slices as four side-on pictures
## stacked front to back: `#` masonry, `L` lantern, `P` plinth, `C` offering
## box, `S` the sign the lore lives on.
static func _shrine_template() -> StructTemplate:
	if _shrine_tpl != null:
		return _shrine_tpl
	_shrine_tpl = StructTemplate.make(&"wayside_shrine", {
		"#": {"role": &"wall"},
		"=": {"role": &"floor"},
		"^": {"role": &"roof"},
		"P": {"role": &"trim"},
		"L": {"role": &"light", "marker": {"kind": "light", "fixture": "shrine", "level": 13}},
		"S": {"generic": &"sign", "marker": {"kind": "sign", "text": "", "lore": "Turn, and turn again."}},
		"C": {"generic": &"chest", "marker": {"kind": "container", "table": "shrine", "tier_bonus": 1}},
	}, [
		# z = 0  (the face you meet walking North)
		["^^^^^",
		 "#   #",
		 "#   #",
		 "#   #",
		 "====="],
		# z = 1
		["^^^^^",
		 "#L L#",
		 "#   #",
		 "# P #",
		 "====="],
		# z = 2  — the offering box hides behind the plinth
		["^^^^^",
		 "#####",
		 "##C##",
		 "##S##",
		 "====="],
	], {"anchor": Vector3i(2, 0, 0)})
	return _shrine_tpl


## A sealed roadside tomb: solid from three sides, one slot on +X.
static func _tomb_template() -> StructTemplate:
	if _tomb_tpl != null:
		return _tomb_tpl
	_tomb_tpl = StructTemplate.make(&"roadside_tomb", {
		"#": {"role": &"wall"},
		"=": {"role": &"floor"},
		"b": {"generic": &"bone", "chance": 0.7},
		"C": {"generic": &"chest", "marker": {"kind": "container", "table": "grave"}},
		"T": {"marker": {"kind": "trap", "trap": "gas"}, "air": true},
	}, [
		["#####",
		 "#####",
		 "====="],
		["#####",
		 "#b C#",
		 "====="],
		["#####",
		 "#T  #",
		 "====="],
		["#####",
		 "#####",
		 "====="],
	], {"anchor": Vector3i(4, 0, 1)})
	return _tomb_tpl


# ==============================================================================
#  Generators
# ==============================================================================
static func _kit(ctx: Dictionary) -> Dictionary:
	return StructPalette.kit(ctx.get("theme", StructPalette.THEME_NATURAL))


static func _anchor(canvas: StructCanvas, ctx: Dictionary, size: Vector3i) -> void:
	var o: Vector3i = ctx["origin"]
	canvas.tile(o, StructMarkers.anchor(String(ctx.get("id", "structure")),
		ctx.get("theme", StructPalette.THEME_NATURAL), int(ctx.get("tier", 0)),
		o, size, int(ctx.get("seed", 0)), String(ctx.get("display", "Structure"))))


static func _chest(canvas: StructCanvas, p: Vector3i, table: String, ctx: Dictionary,
		bonus: int = 0) -> void:
	var c := StructPalette.generic(&"chest", &"accent")
	canvas.put_tile(p, c if c != Const.AIR else _kit(ctx)[&"accent"],
		StructLoot.chest(table, int(ctx.get("tier", 0)) + bonus,
			ctx.get("theme", StructPalette.THEME_NATURAL),
			StructRng.hash4(int(ctx.get("seed", 0)), p.x, p.y, p.z),
			String(ctx.get("id", ""))))


## Sink a slab under a footprint so nothing floats over a slope.
static func _footing(canvas: StructCanvas, lo: Vector3i, hi: Vector3i, id: int,
		depth: int = 10) -> void:
	canvas.box_soft(Vector3i(lo.x, lo.y - depth, lo.z), Vector3i(hi.x, lo.y - 1, hi.z), id)


# ------------------------------------------------------------------- outpost
## Prefab hut, comms mast, fence and a supply cache. The bunkroom door faces X;
## the generator room behind it opens on Z only, so the outpost cannot be
## cleared without one flip.
static func abandoned_outpost(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 15):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)

	var lo := o + Vector3i(-5, 0, -4)
	var hi := o + Vector3i(3, 5, 4)
	_footing(canvas, lo, hi, kit[&"wall"])
	canvas.room(lo, hi, kit[&"wall"], kit[&"floor"], kit[&"roof"])
	canvas.doorway(Vector3i(hi.x, o.y + 1, o.z), 0, 1, 2, 1)
	canvas.tile(Vector3i(hi.x, o.y + 1, o.z), StructMarkers.door(
		"%s_door" % theme, "x", false, "", 0, 1, 2))

	# Generator annex: only opening is on Z.
	var glo := o + Vector3i(4, 0, -3)
	var ghi := o + Vector3i(9, 4, 2)
	_footing(canvas, glo, ghi, kit[&"wall"])
	canvas.room(glo, ghi, kit[&"wall_alt"], kit[&"floor"], kit[&"roof"])
	canvas.doorway(Vector3i(o.x + 6, o.y + 1, ghi.z), 2, 1, 2, 1)
	canvas.put(Vector3i(o.x + 6, o.y + 1, o.z), kit[&"accent"])
	canvas.tile(Vector3i(o.x + 6, o.y + 1, o.z), StructMarkers.sign("",
		"Generator hall. Access from the south face only."))

	if kit[&"light"] != Const.AIR:
		canvas.put(Vector3i(o.x - 1, hi.y - 1, o.z), kit[&"light"])
	_chest(canvas, o + Vector3i(-4, 1, 3), "outpost", ctx)
	_chest(canvas, o + Vector3i(-4, 1, -3), "outpost", ctx)
	var bed := StructPalette.generic(&"bed", &"cloth")
	if bed != Const.AIR:
		canvas.box(o + Vector3i(-4, 1, 0), o + Vector3i(-4, 1, 1), bed)

	# Comms mast — a vertical line that stays visible from every plane.
	canvas.box(o + Vector3i(-6, 0, -6), o + Vector3i(-6, 12, -6), kit[&"pillar"])
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(-6, 13, -6), kit[&"light"])
	var fence: int = kit[&"fence"]
	if fence != Const.AIR:
		canvas.rect_xz(o + Vector3i(-8, 0, -7), o + Vector3i(11, 0, 7), o.y + 1, fence)
	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.spawner("scavenger",
		int(ctx.get("tier", 0)), 2, 10.0, theme, int(ctx.get("seed", 0))))
	canvas.scatter(o + Vector3i(-8, 0, -7), o + Vector3i(11, 0, 7), kit[&"rubble"], 0.03, r)
	_anchor(canvas, ctx, Vector3i(20, 14, 15))


# ------------------------------------------------------------ crashed shuttle
## A hull ploughed into the ground along a random axis, a debris trail, and a
## cockpit you enter from the torn-open end.
static func crashed_shuttle(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 16):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)
	var hull: int = kit[&"wall"]
	var along_x := r.randf() < 0.5
	var dir := Vector3i(1, 0, 0) if along_x else Vector3i(0, 0, 1)
	var side := Vector3i(0, 0, 1) if along_x else Vector3i(1, 0, 0)
	var hull_len := r.randi_range(10, 14)

	# Furrow: the ship dug in, so the ground behind it is scarred.
	for i in range(-hull_len - 6, 1):
		var w := 3 - absi(i) / 6
		canvas.carve_box(o + dir * i - side * w + Vector3i(0, -1, 0),
				o + dir * i + side * w + Vector3i(0, 2, 0))
		canvas.box(o + dir * i - side * w + Vector3i(0, -2, 0),
				o + dir * i + side * w + Vector3i(0, -2, 0), kit[&"rubble"])

	# Fuselage.
	for i in range(0, hull_len):
		var rad := 3 if i < hull_len - 3 else 2
		canvas.cylinder(o + dir * i - Vector3i(0, 0, 0), rad, 1, hull, true)
	canvas.carve_box(o + dir * 1 - side * 2 + Vector3i(0, 1, 0),
			o + dir * (hull_len - 2) + side * 2 + Vector3i(0, 3, 0))
	canvas.box(o + dir * 1 - side * 2, o + dir * (hull_len - 2) + side * 2, kit[&"floor"])

	# Torn nose = the only way in, and it faces one axis.
	canvas.carve_box(o - side * 2 + Vector3i(0, 1, 0), o + side * 2 + Vector3i(0, 3, 0))
	# Wings: flat plates that vanish edge-on, which is a nice flip reveal.
	canvas.box(o + dir * 4 - side * 7, o + dir * 6 + side * 7, hull)

	if kit[&"light"] != Const.AIR:
		for i in [3, 7]:
			canvas.put(o + dir * i + Vector3i(0, 4, 0), kit[&"light"])
	_chest(canvas, o + dir * 3 + side, "shuttle", ctx)
	_chest(canvas, o + dir * (hull_len - 3), "shuttle", ctx, 1)
	canvas.put(o + dir * (hull_len - 2) + Vector3i(0, 1, 0), kit[&"accent"])
	canvas.tile(o + dir * (hull_len - 2) + Vector3i(0, 1, 0), StructMarkers.sign(
		"Flight recorder", "Cabin pressure lost at 4000m. We are going in."))
	canvas.tile(o + dir * 5 + Vector3i(0, 1, 0), StructMarkers.spawner("scavenger",
		int(ctx.get("tier", 0)), 3, 12.0, theme, int(ctx.get("seed", 0))))
	canvas.scatter(o - dir * (hull_len + 6) - side * 8, o + dir * hull_len + side * 8,
			kit[&"rubble"], 0.04, r)
	_anchor(canvas, ctx, Vector3i(hull_len + 12, 8, 16))


# ---------------------------------------------------------------- bandit camp
static func bandit_camp(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 14):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)

	# Palisade with a gate on each horizontal axis, so the camp can be stormed
	# from any plane — the ambush spawner sits where the two lines cross.
	var fence: int = kit[&"fence"] if kit[&"fence"] != Const.AIR else kit[&"wall"]
	canvas.rect_xz(o + Vector3i(-10, 0, -10), o + Vector3i(10, 0, 10), o.y + 1, fence)
	canvas.rect_xz(o + Vector3i(-10, 0, -10), o + Vector3i(10, 0, 10), o.y + 2, fence)
	canvas.carve_box(o + Vector3i(-10, 1, -1), o + Vector3i(-10, 2, 1))
	canvas.carve_box(o + Vector3i(-1, 1, 10), o + Vector3i(1, 2, 10))

	# Campfire.
	canvas.cylinder(Vector3i(o.x, o.y, o.z), 2, 1, kit[&"path"])
	var fire := StructPalette.named([&"campfire", &"fire", &"torch"], &"")
	if fire != Const.AIR:
		canvas.put(o + Vector3i(0, 1, 0), fire)
	elif kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 1, 0), kit[&"light"])

	# Tents on the diagonals.
	for d: Vector3i in [Vector3i(-6, 0, -6), Vector3i(6, 0, -6), Vector3i(-6, 0, 6), Vector3i(6, 0, 6)]:
		if r.randf() < 0.25:
			continue
		var c := o + d
		var cloth := StructPalette.generic(&"cloth", &"roof")
		canvas.box(c + Vector3i(-2, 0, -2), c + Vector3i(2, 0, 2), kit[&"floor"])
		for i in range(3):
			canvas.box(c + Vector3i(-2 + i, i + 1, -2), c + Vector3i(-2 + i, i + 1, 2), cloth)
			canvas.box(c + Vector3i(2 - i, i + 1, -2), c + Vector3i(2 - i, i + 1, 2), cloth)
		canvas.carve_box(c + Vector3i(-1, 1, -1), c + Vector3i(1, 2, 1))
		_chest(canvas, c + Vector3i(0, 1, 0), "bandit", ctx)

	# Prisoner cage — the reason to come here.
	var bars: int = kit[&"bars"] if kit[&"bars"] != Const.AIR else kit[&"pillar"]
	var cage := o + Vector3i(0, 0, -7)
	canvas.walls(cage + Vector3i(-2, 0, -2), cage + Vector3i(2, 3, 2), bars)
	canvas.carve_box(cage + Vector3i(-1, 1, -1), cage + Vector3i(1, 2, 1))
	canvas.tile(cage + Vector3i(0, 1, 0), StructMarkers.npc("prisoner", theme,
		cage + Vector3i(0, 1, 0), "captive", 0, 0.0, int(ctx.get("seed", 0)), "",
		"rescue_me"))
	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.spawner("bandit",
		int(ctx.get("tier", 0)) + 1, r.randi_range(3, 6), 14.0, theme,
		int(ctx.get("seed", 0))))
	_anchor(canvas, ctx, Vector3i(21, 6, 21))


# ----------------------------------------------------------------- observatory
## A drum with a domed roof and a telescope shaft. The shaft is open to the sky
## on one axis only: from the other plane pair the dome looks sealed.
static func observatory(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 14):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)
	_footing(canvas, o - Vector3i(7, 0, 7), o + Vector3i(7, 0, 7), kit[&"wall"])

	canvas.cylinder(o, 7, 9, kit[&"wall"], true)
	canvas.cylinder(o, 6, 9, Const.AIR)
	canvas.cylinder(Vector3i(o.x, o.y - 1, o.z), 7, 1, kit[&"floor"])
	canvas.sphere(Vector3i(o.x, o.y + 9, o.z), 7, kit[&"roof"], true, 0)
	canvas.sphere(Vector3i(o.x, o.y + 9, o.z), 6, Const.AIR, false, 0)

	# Observation slit, along X.
	canvas.carve_box(o + Vector3i(-7, 9, 0), o + Vector3i(7, 15, 0))
	canvas.doorway(o + Vector3i(-7, 1, 0), 0, 1, 3, 2)

	# The instrument: a tilted barrel that only lines up with the slit.
	canvas.line(o + Vector3i(-3, 2, 0), o + Vector3i(3, 9, 0), kit[&"pillar"])
	canvas.box(o + Vector3i(-1, 1, -1), o + Vector3i(1, 1, 1), kit[&"trim"])

	var mezz := StructPalette.generic(&"scaffold", &"platform")
	if mezz != Const.AIR:
		canvas.cylinder(Vector3i(o.x, o.y + 5, o.z), 6, 1, mezz, true)
	if kit[&"light"] != Const.AIR:
		for a in range(4):
			var ang := TAU * float(a) / 4.0
			canvas.put(o + Vector3i(int(round(cos(ang) * 5.0)), 6, int(round(sin(ang) * 5.0))),
					kit[&"light"])
	_chest(canvas, o + Vector3i(4, 1, 3), "observatory", ctx, 1)
	canvas.put(o + Vector3i(-4, 1, 3), kit[&"accent"])
	canvas.tile(o + Vector3i(-4, 1, 3), StructMarkers.sign("Star ledger",
		"The gate-lights rise in the east on the ninetieth day."))
	canvas.tile(o + Vector3i(0, 6, 0), StructMarkers.npc("questgiver", theme,
		o + Vector3i(0, 6, 0), "astronomer", 0, 5.0, int(ctx.get("seed", 0)), "",
		"star_charts"))
	_anchor(canvas, ctx, Vector3i(15, 18, 15))


# --------------------------------------------------------------------- shrine
static func wayside_shrine(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	var tpl := _shrine_template()
	var rot := r.randi_range(0, 3)
	var kit := _kit(ctx)
	_footing(canvas, o - Vector3i(3, 0, 3), o + Vector3i(3, 0, 3), kit[&"wall"], 8)
	tpl.stamp_on(canvas, o, rot, {
		"theme": ctx.get("theme", StructPalette.THEME_NATURAL),
		"tier": int(ctx.get("tier", 0)), "seed": int(ctx.get("seed", 0)),
		"struct_id": "wayside_shrine", "rng": r,
		"mirror": r.randf() < 0.5,
	})
	# A second, sealed tomb behind it half the time — same anchor, other axis.
	if r.randf() < 0.45:
		_tomb_template().stamp_on(canvas, o + Vector3i(0, 0, 6), (rot + 1) & 3, {
			"theme": ctx.get("theme", StructPalette.THEME_NATURAL),
			"tier": int(ctx.get("tier", 0)) + 1, "seed": int(ctx.get("seed", 0)) ^ 0x70B,
			"struct_id": "roadside_tomb", "rng": r, "foundation": kit[&"wall"],
		})
	_anchor(canvas, ctx, Vector3i(5, 5, 12))


# ----------------------------------------------------------------------- well
## A stone ring over a shaft that drops into whatever cave it can find. Climbing
## out again needs the rungs, which spiral round the shaft so exactly one of
## them is reachable from any given plane.
static func old_well(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects(o - Vector3i(5, 42, 5), o + Vector3i(5, 8, 5)):
		return
	var kit := _kit(ctx)
	var depth := r.randi_range(18, 36)

	canvas.cylinder(Vector3i(o.x, o.y - depth, o.z), 3, depth + 3, kit[&"wall"], true)
	canvas.cylinder(Vector3i(o.x, o.y - depth, o.z), 2, depth + 3, Const.AIR)
	canvas.rect_xz(o - Vector3i(2, 0, 2), o + Vector3i(2, 0, 2), o.y + 3, kit[&"roof"])
	for d: Vector3i in [Vector3i(-2, 0, -2), Vector3i(2, 0, -2), Vector3i(-2, 0, 2), Vector3i(2, 0, 2)]:
		canvas.box(o + d, o + d + Vector3i(0, 2, 0), kit[&"pillar"])

	# Water at the bottom.
	var water := Blocks.id(&"water")
	canvas.cylinder(Vector3i(o.x, o.y - depth, o.z), 2, 3, water)
	for y in range(o.y - depth, o.y - depth + 3):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				canvas.set_liquid(Vector3i(o.x + dx, y, o.z + dz), Const.MAX_LIQUID)

	# Rungs, rotating a quarter turn every three blocks.
	var rung: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else kit[&"trim"]
	var offsets := [Vector3i(2, 0, 0), Vector3i(0, 0, 2), Vector3i(-2, 0, 0), Vector3i(0, 0, -2)]
	var k := 0
	for y in range(o.y - depth + 3, o.y + 1, 3):
		canvas.put(Vector3i(o.x, y, o.z) + offsets[k % 4], rung)
		k += 1
	_chest(canvas, Vector3i(o.x + 1, o.y - depth + 1, o.z), "cistern", ctx, 1)
	_anchor(canvas, ctx, Vector3i(7, depth + 4, 7))


# --------------------------------------------------------------- ruined tower
static func ruined_tower(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 16):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_GLITCH)
	var h := r.randi_range(14, 24)
	_footing(canvas, o - Vector3i(5, 0, 5), o + Vector3i(5, 0, 5), kit[&"wall"])
	canvas.cylinder(o, 5, h, kit[&"wall"], true)
	canvas.cylinder(o, 4, h, Const.AIR)

	# Floors every four blocks, each with a hatch on a different axis: the climb
	# forces a flip at every storey.
	var storey := 0
	for y in range(o.y + 4, o.y + h - 2, 4):
		canvas.cylinder(Vector3i(o.x, y, o.z), 4, 1, kit[&"floor"])
		var d: Vector3i = [Vector3i(2, 0, 0), Vector3i(0, 0, 2), Vector3i(-2, 0, 0), Vector3i(0, 0, -2)][storey % 4]
		canvas.carve_box(Vector3i(o.x + d.x, y, o.z + d.z), Vector3i(o.x + d.x, y, o.z + d.z))
		var lad: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else kit[&"platform"]
		if lad != Const.AIR:
			canvas.box(Vector3i(o.x + d.x, y - 3, o.z + d.z), Vector3i(o.x + d.x, y, o.z + d.z), lad)
		if kit[&"light"] != Const.AIR:
			canvas.put(Vector3i(o.x, y + 3, o.z), kit[&"light"])
		if r.randf() < 0.5:
			_chest(canvas, Vector3i(o.x - 2, y + 1, o.z + 2), "ruins", ctx)
		if r.randf() < 0.5:
			canvas.tile(Vector3i(o.x, y + 1, o.z), StructMarkers.spawner(
				"%s_sentry" % theme, int(ctx.get("tier", 0)), 2, 6.0, theme,
				StructRng.hash2(int(ctx.get("seed", 0)), y)))
		storey += 1

	# Ruin the crown: bite chunks out so the silhouette is jagged.
	for i in range(r.randi_range(10, 22)):
		var ang := r.randf() * TAU
		var y := o.y + h - r.randi_range(0, 4)
		canvas.carve_box(
			Vector3i(o.x + int(round(cos(ang) * 5.0)), y, o.z + int(round(sin(ang) * 5.0))),
			Vector3i(o.x + int(round(cos(ang) * 5.0)), y + 2, o.z + int(round(sin(ang) * 5.0))))
	canvas.doorway(o + Vector3i(-5, 1, 0), 0, 1, 3, 2)
	_anchor(canvas, ctx, Vector3i(11, h + 4, 11))


# --------------------------------------------------------------- mine entrance
## Headframe, a shaft, and a rail drift that runs a long way on ONE axis. The
## drift has cross-cuts every so often that only exist one layer over, so the
## seam of ore is found by shifting, not walking.
static func mine_entrance(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	var depth := r.randi_range(24, 44)
	if not canvas.intersects(o - Vector3i(34, depth + 4, 34), o + Vector3i(34, 16, 34)):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)
	var beam := StructPalette.generic(&"support", &"pillar")
	var rail := StructPalette.generic(&"rail", &"platform")

	# Headframe: four legs and a crown, a strong silhouette from every plane.
	for d: Vector3i in [Vector3i(-3, 0, -3), Vector3i(3, 0, -3), Vector3i(-3, 0, 3), Vector3i(3, 0, 3)]:
		canvas.box(o + d, o + d + Vector3i(0, 9, 0), beam)
	canvas.rect_xz(o - Vector3i(3, 0, 3), o + Vector3i(3, 0, 3), o.y + 10, beam)
	canvas.box(o + Vector3i(-1, 10, -1), o + Vector3i(1, 11, 1), kit[&"trim"])

	# The shaft.
	canvas.box(o - Vector3i(3, depth, 3), o + Vector3i(3, 0, 3), kit[&"wall"])
	canvas.carve_box(o - Vector3i(2, depth, 2), o + Vector3i(2, 1, 2))
	var lad: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else beam
	canvas.box(o + Vector3i(2, -depth, 2), o + Vector3i(2, 1, 2), lad)

	# Drift along one axis with timbering.
	var along_x := r.randf() < 0.5
	var dir := Vector3i(1, 0, 0) if along_x else Vector3i(0, 0, 1)
	var side := Vector3i(0, 0, 1) if along_x else Vector3i(1, 0, 0)
	var base := o + Vector3i(0, -depth + 1, 0)
	var run := r.randi_range(18, 30)
	canvas.tunnel(base, base + dir * run, 3, 4, kit[&"wall"], kit[&"floor"])
	for i in range(0, run, 4):
		canvas.box(base + dir * i - side * 2 + Vector3i(0, 0, 0),
				base + dir * i - side * 2 + Vector3i(0, 3, 0), beam)
		canvas.box(base + dir * i + side * 2, base + dir * i + side * 2 + Vector3i(0, 3, 0), beam)
	if rail != Const.AIR:
		canvas.box(base, base + dir * run, rail)

	# Cross-cuts hidden one layer behind the drift wall.
	for i in range(6, run - 2, 7):
		var off := side * (2 if ((i / 7) % 2) == 0 else -2)
		canvas.carve_box(base + dir * i + off, base + dir * i + off * 3 + Vector3i(0, 2, 0))
		_chest(canvas, base + dir * i + off * 3, "mine", ctx, 1)
		if r.randf() < 0.5:
			canvas.tile(base + dir * i + off * 2, StructMarkers.spawner("cave_crawler",
				int(ctx.get("tier", 0)) + 1, 2, 6.0, theme,
				StructRng.hash2(int(ctx.get("seed", 0)), i)))
	canvas.put(o + Vector3i(-3, 1, 0), StructPalette.generic(&"sign", &"accent"))
	canvas.tile(o + Vector3i(-3, 1, 0), StructMarkers.sign("Shaft 4",
		"Seam runs sideways. Look behind the timbering."))
	_anchor(canvas, ctx, Vector3i(run + 8, depth + 12, run + 8))


# ------------------------------------------------------------------ watchtower
static func watchtower(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 12):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_GLITCH)
	var h := r.randi_range(11, 16)
	var lo := o - Vector3i(3, 0, 3)
	var hi := o + Vector3i(3, h, 3)
	_footing(canvas, lo, hi, kit[&"wall"])
	canvas.room(lo, hi, kit[&"wall"], kit[&"floor"], Const.AIR)
	canvas.doorway(Vector3i(lo.x, o.y + 1, o.z), 0, 1, 2, 1)

	var lad: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else kit[&"platform"]
	if lad != Const.AIR:
		canvas.box(o + Vector3i(2, 1, 2), o + Vector3i(2, h - 1, 2), lad)
	canvas.box(Vector3i(lo.x, o.y + h, lo.z), Vector3i(hi.x, o.y + h, hi.z), kit[&"floor"])
	canvas.carve_box(o + Vector3i(2, h, 2), o + Vector3i(2, h, 2))
	# Crenellations: alternating merlons read as a dashed line from every plane.
	for x in range(lo.x, hi.x + 1, 2):
		canvas.box(Vector3i(x, o.y + h + 1, lo.z), Vector3i(x, o.y + h + 2, lo.z), kit[&"wall"])
		canvas.box(Vector3i(x, o.y + h + 1, hi.z), Vector3i(x, o.y + h + 2, hi.z), kit[&"wall"])
	for z in range(lo.z, hi.z + 1, 2):
		canvas.box(Vector3i(lo.x, o.y + h + 1, z), Vector3i(lo.x, o.y + h + 2, z), kit[&"wall"])
		canvas.box(Vector3i(hi.x, o.y + h + 1, z), Vector3i(hi.x, o.y + h + 2, z), kit[&"wall"])
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, h + 1, 0), kit[&"light"])
	canvas.tile(o + Vector3i(0, h + 1, 0), StructMarkers.npc("guard", theme,
		o + Vector3i(0, h + 1, 0), "lookout", 0, 3.0, int(ctx.get("seed", 0))))
	_chest(canvas, o + Vector3i(-2, 1, -2), "outpost", ctx)
	_anchor(canvas, ctx, Vector3i(7, h + 4, 7))


# ------------------------------------------------------------ standing stones
## Twelve monoliths on a ring. Their heights are chosen so that from view 0 they
## spell a rising staircase and from view 1 they spell a falling one — the same
## stones, two different readings, which is the whole game in one prop.
static func standing_stones(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 14):
		return
	var kit := _kit(ctx)
	var rad := 9
	for i in range(12):
		var ang := TAU * float(i) / 12.0
		var px := o.x + int(round(cos(ang) * float(rad)))
		var pz := o.z + int(round(sin(ang) * float(rad)))
		# height rises with X, falls with Z
		var h := 4 + (px - o.x + rad) / 3 + (o.z + rad - pz) / 4
		canvas.box_soft(Vector3i(px, o.y - 6, pz), Vector3i(px, o.y - 1, pz), kit[&"wall"])
		canvas.box(Vector3i(px, o.y, pz), Vector3i(px, o.y + h, pz), kit[&"pillar"])
		if i % 3 == 0:
			canvas.box(Vector3i(px, o.y + h + 1, pz), Vector3i(px, o.y + h + 1, pz), kit[&"trim"])
	canvas.cylinder(Vector3i(o.x, o.y - 1, o.z), 3, 1, kit[&"floor"])
	canvas.put(o + Vector3i(0, 0, 0), kit[&"accent"])
	canvas.tile(o, StructMarkers.sign("", "Count them from the north. Then count again from the west."))
	if r.randf() < 0.5:
		_chest(canvas, o + Vector3i(0, -3, 0), "shrine", ctx, 1)
		canvas.carve_box(o + Vector3i(0, -3, 0), o + Vector3i(0, -1, 0))
	_anchor(canvas, ctx, Vector3i(rad * 2 + 2, 16, rad * 2 + 2))


# ------------------------------------------------------------------ graveyard
static func graveyard(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 14):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_NATURAL)
	var fence: int = kit[&"fence"] if kit[&"fence"] != Const.AIR else kit[&"trim"]
	canvas.rect_xz(o - Vector3i(9, 0, 9), o + Vector3i(9, 0, 9), o.y + 1, fence)
	canvas.carve_box(o + Vector3i(-1, 1, -9), o + Vector3i(1, 2, -9))

	# Rows of headstones, gridded so they line up in BOTH plane pairs.
	for gx in range(-6, 7, 3):
		for gz in range(-6, 7, 3):
			if r.randf() < 0.2:
				continue
			var p := o + Vector3i(gx, 1, gz)
			canvas.put(p, kit[&"wall"])
			if r.randf() < 0.3:
				canvas.put(p + Vector3i(0, 1, 0), kit[&"trim"])
	# Crypt below, entered through a slab that only opens on Z.
	var c := o + Vector3i(0, -8, 4)
	canvas.room(c - Vector3i(5, 0, 4), c + Vector3i(5, 4, 4), kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	canvas.carve_box(o + Vector3i(0, -4, 8), o + Vector3i(0, 1, 8))
	canvas.carve_box(c + Vector3i(0, 1, 4), c + Vector3i(0, 3, 4))
	for i in [-3, 0, 3]:
		var slot := c + Vector3i(i, 1, -2)
		canvas.carve_box(slot, slot + Vector3i(0, 1, 1))
		var bone := StructPalette.generic(&"bone", &"rubble")
		if bone != Const.AIR:
			canvas.put(slot, bone)
	_chest(canvas, c + Vector3i(0, 1, 0), "grave", ctx, 1)
	canvas.tile(c + Vector3i(0, 1, 1), StructMarkers.spawner("undead",
		int(ctx.get("tier", 0)) + 1, 3, 8.0, theme, int(ctx.get("seed", 0))))
	if kit[&"light"] != Const.AIR:
		canvas.put(c + Vector3i(0, 4, 0), kit[&"light"])
	_anchor(canvas, ctx, Vector3i(19, 16, 19))


# ---------------------------------------------------------------------- pagoda
static func hylotl_pagoda(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 13):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HYLOTL)
	var tiers := r.randi_range(3, 5)
	_footing(canvas, o - Vector3i(6, 0, 6), o + Vector3i(6, 0, 6), kit[&"wall"])
	var y := o.y
	for t in range(tiers):
		var w := 6 - t
		if w < 2:
			break
		canvas.room(Vector3i(o.x - w, y, o.z - w), Vector3i(o.x + w, y + 4, o.z + w),
				kit[&"wall_alt"], kit[&"floor"], kit[&"roof"])
		# Eaves: a wide flat plate that disappears when seen edge-on.
		canvas.box(Vector3i(o.x - w - 2, y + 4, o.z - w - 2),
				Vector3i(o.x + w + 2, y + 4, o.z + w + 2), kit[&"roof"])
		# Doors alternate axis storey by storey.
		if t % 2 == 0:
			canvas.doorway(Vector3i(o.x - w, y + 1, o.z), 0, 1, 2, 1)
			canvas.doorway(Vector3i(o.x + w, y + 1, o.z), 0, 1, 2, 1)
		else:
			canvas.doorway(Vector3i(o.x, y + 1, o.z - w), 2, 1, 2, 1)
			canvas.doorway(Vector3i(o.x, y + 1, o.z + w), 2, 1, 2, 1)
		canvas.carve_box(Vector3i(o.x + 1, y + 4, o.z + 1), Vector3i(o.x + 1, y + 4, o.z + 1))
		var lad: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else kit[&"platform"]
		if lad != Const.AIR:
			canvas.box(Vector3i(o.x + 1, y + 1, o.z + 1), Vector3i(o.x + 1, y + 4, o.z + 1), lad)
		if kit[&"light"] != Const.AIR:
			canvas.put(Vector3i(o.x, y + 3, o.z), kit[&"light"])
		if t == tiers - 1:
			_chest(canvas, Vector3i(o.x, y + 1, o.z), "hylotl_city", ctx, 1)
		y += 5
	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.npc("questgiver", theme,
		o + Vector3i(0, 1, 0), "monk", 0, 4.0, int(ctx.get("seed", 0)), "", "pagoda_koan"))
	_anchor(canvas, ctx, Vector3i(15, tiers * 5 + 4, 15))


# ------------------------------------------------------------------- treehouse
static func giant_treehouse(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 22):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_FLORAN)
	var log_id := StructPalette.generic(&"log", &"pillar")
	var leaf := StructPalette.generic(&"leaves", &"roof")
	var plank := StructPalette.generic(&"wood", &"floor")
	var h := r.randi_range(28, 40)

	# Trunk + buttress roots.
	canvas.cylinder(Vector3i(o.x, o.y - 6, o.z), 4, h + 6, log_id)
	for a in range(6):
		var ang := TAU * float(a) / 6.0
		canvas.line(o + Vector3i(int(round(cos(ang) * 8.0)), -2, int(round(sin(ang) * 8.0))),
				o + Vector3i(0, 6, 0), log_id)
	canvas.sphere(Vector3i(o.x, o.y + h, o.z), 12, leaf, true)
	canvas.sphere(Vector3i(o.x, o.y + h, o.z), 10, Const.AIR)

	# Platforms, each on a different bearing so the climb is a spiral through
	# all four planes.
	var count := r.randi_range(4, 6)
	for i in range(count):
		var y := o.y + 8 + i * 5
		var ang := TAU * float(i) / float(count)
		var px := o.x + int(round(cos(ang) * 8.0))
		var pz := o.z + int(round(sin(ang) * 8.0))
		canvas.box(Vector3i(px - 3, y, pz - 3), Vector3i(px + 3, y, pz + 3), plank)
		canvas.room(Vector3i(px - 3, y, pz - 3), Vector3i(px + 3, y + 4, pz + 3),
				kit[&"wall"], plank, kit[&"roof"])
		var axis := 0 if (i % 2) == 0 else 2
		canvas.doorway(Vector3i(px + (3 if axis == 0 else 0), y + 1, pz + (0 if axis == 0 else 3)),
				axis, 1, 2, 1)
		# Rope bridge back to the trunk.
		canvas.box(Vector3i(mini(px, o.x), y, pz if axis == 0 else o.z),
				Vector3i(maxi(px, o.x), y, pz if axis == 0 else o.z), plank)
		canvas.carve_box(Vector3i(mini(px, o.x), y + 1, pz if axis == 0 else o.z),
				Vector3i(maxi(px, o.x), y + 2, pz if axis == 0 else o.z))
		if kit[&"light"] != Const.AIR:
			canvas.put(Vector3i(px, y + 3, pz), kit[&"light"])
		_chest(canvas, Vector3i(px, y + 1, pz), "treehouse", ctx)
		canvas.tile(Vector3i(px + 1, y + 1, pz), StructMarkers.npc("villager", theme,
			Vector3i(px + 1, y + 1, pz), "forager", 0, 6.0,
			StructRng.hash2(int(ctx.get("seed", 0)), i)))
	# Hollow trunk with a ladder, so there is a fast way down.
	canvas.cylinder(Vector3i(o.x, o.y, o.z), 2, h, Const.AIR)
	var lad: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else Const.AIR
	if lad != Const.AIR:
		canvas.box(o + Vector3i(1, 0, 0), o + Vector3i(1, h, 0), lad)
	canvas.doorway(o + Vector3i(-4, 1, 0), 0, 1, 2, 2)
	_anchor(canvas, ctx, Vector3i(24, h + 14, 24))


# ------------------------------------------------------------------ floran camp
static func floran_camp(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 20):
		return
	var kit := _kit(ctx)
	var theme: StringName = StructPalette.THEME_FLORAN
	var spike := StructPalette.generic(&"spike", &"fence")

	# Totem at the centre: tallest thing for a long way, a beacon in any plane.
	canvas.box(o, o + Vector3i(0, 9, 0), kit[&"pillar"])
	canvas.box(o + Vector3i(-2, 7, 0), o + Vector3i(2, 7, 0), kit[&"accent"])
	canvas.box(o + Vector3i(0, 5, -2), o + Vector3i(0, 5, 2), kit[&"accent"])
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 10, 0), kit[&"light"])

	for i in range(r.randi_range(4, 7)):
		var ang := TAU * float(i) / 6.0 + r.randf_range(-0.3, 0.3)
		var dist := float(r.randi_range(7, 14))
		var c := o + Vector3i(int(round(cos(ang) * dist)), 0, int(round(sin(ang) * dist)))
		var rad := r.randi_range(3, 4)
		canvas.cylinder(c, rad, 5, kit[&"wall"], true)
		canvas.cylinder(c, rad - 1, 5, Const.AIR)
		canvas.sphere(Vector3i(c.x, c.y + 5, c.z), rad, kit[&"roof"], true, 0)
		canvas.cylinder(Vector3i(c.x, c.y - 1, c.z), rad, 1, kit[&"floor"])
		var axis := 0 if (i % 2) == 0 else 2
		canvas.doorway(c + (Vector3i(rad, 1, 0) if axis == 0 else Vector3i(0, 1, rad)),
				axis, 1, 2, 1)
		_chest(canvas, c + Vector3i(0, 1, 0), "floran_hut", ctx)
		canvas.tile(c + Vector3i(1, 1, 0), StructMarkers.npc("villager", theme,
			c + Vector3i(1, 1, 0), "hunter", 0, 10.0,
			StructRng.hash2(int(ctx.get("seed", 0)), i)))
		if spike != Const.AIR:
			canvas.put(c + Vector3i(rad + 1, 1, rad + 1), spike)
	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.spawner("floran_hunter",
		int(ctx.get("tier", 0)), 3, 16.0, theme, int(ctx.get("seed", 0))))
	_anchor(canvas, ctx, Vector3i(30, 14, 30))


# ------------------------------------------------------------------- sky ruin
## A chunk of masonry that never came down. Reaching it is the puzzle: the only
## approach is a run of platforms that reads as a broken ladder from three
## planes and a continuous stair from the fourth.
static func sky_ruin(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 18):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var rad := r.randi_range(7, 10)

	# Island underside.
	for dy in range(0, 6):
		canvas.cylinder(Vector3i(o.x, o.y - dy, o.z), maxi(1, rad - dy), 1,
				StructPalette.named([&"stone"], &"stone"))
	canvas.cylinder(Vector3i(o.x, o.y, o.z), rad, 1, kit[&"floor"])

	# Ruin on top: three walls and a pillar row.
	canvas.walls(o + Vector3i(-4, 1, -4), o + Vector3i(4, 6, 4), kit[&"wall"])
	canvas.carve_box(o + Vector3i(-3, 1, 4), o + Vector3i(3, 4, 4))
	for x in [-4, 0, 4]:
		canvas.box(o + Vector3i(x, 1, -6), o + Vector3i(x, 5, -6), kit[&"pillar"])
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 6, 0), kit[&"light"])
	_chest(canvas, o + Vector3i(0, 2, 0), "ancient_vault", ctx, 1)
	canvas.tile(o + Vector3i(0, 2, 1), StructMarkers.spawner("sky_wraith",
		int(ctx.get("tier", 0)) + 1, 2, 12.0, theme, int(ctx.get("seed", 0))))

	# The stair: steps march out along +X while stepping one layer in Z each
	# time, so only the East/West planes see an unbroken run.
	var plat: int = kit[&"platform"] if kit[&"platform"] != Const.AIR else kit[&"trim"]
	var steps := 16
	for i in range(steps):
		var p := o + Vector3i(rad + 2 + i, -i * 2, i % 5 - 2)
		canvas.box(p, p + Vector3i(1, 0, 0), plat)
	canvas.tile(o + Vector3i(rad, 1, 0), StructMarkers.sign("",
		"The stair is whole only from the east."))
	_anchor(canvas, ctx, Vector3i(rad * 2 + 4, 14, rad * 2 + 4))


# ---------------------------------------------------------------- gate beacon
## Surface half of the ancient gate network: an arch with a teleporter pad. The
## pad is inert until the matching underground gateway is found.
static func beacon_pylon(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 11):
		return
	var kit := StructPalette.kit(StructPalette.THEME_ANCIENT)
	_footing(canvas, o - Vector3i(4, 0, 4), o + Vector3i(4, 0, 4), kit[&"wall"])
	canvas.box(o - Vector3i(4, 1, 4), o + Vector3i(4, -1, 4), kit[&"floor"])
	# A ring of four pylons: whichever plane you are on, two of them frame the
	# pad and the other two are hidden behind them.
	for d: Vector3i in [Vector3i(-3, 0, -3), Vector3i(3, 0, -3), Vector3i(-3, 0, 3), Vector3i(3, 0, 3)]:
		canvas.box(o + d, o + d + Vector3i(0, 7, 0), kit[&"pillar"])
		if kit[&"light"] != Const.AIR:
			canvas.put(o + d + Vector3i(0, 8, 0), kit[&"light"])
	canvas.box(o + Vector3i(-3, 8, -3), o + Vector3i(3, 8, -3), kit[&"trim"])
	canvas.box(o + Vector3i(-3, 8, 3), o + Vector3i(3, 8, 3), kit[&"trim"])
	var pad := StructPalette.generic(&"teleporter", &"accent")
	canvas.put_tile(o, pad if pad != Const.AIR else kit[&"accent"],
		StructMarkers.teleporter("ancient_gate",
			absi(StructRng.hash2(int(ctx.get("seed", 0)), 0x6A7E)) % 1000000,
			"ancient_key", false))
	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.sign("",
		"Sealed. The key sleeps below."))
	_anchor(canvas, ctx, Vector3i(9, 10, 9))


# ------------------------------------------------------------- avian temple
## A stepped pyramid. Each terrace is entered from a different bearing, so the
## climb rotates the player through all four planes; the sanctum on top is a
## sealed box whose only door faces Z, and the treasury *under* the sanctum is
## reached by dropping through a slot that is invisible until you flip.
static func avian_temple(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 24):
		return
	var kit := StructPalette.kit(StructPalette.THEME_AVIAN)
	var theme := StructPalette.THEME_AVIAN
	var tier: int = int(ctx.get("tier", 2))
	var steps := r.randi_range(4, 6)
	var base_r := 4 + steps * 3

	_footing(canvas, o - Vector3i(base_r, 0, base_r), o + Vector3i(base_r, 0, base_r),
			kit[&"wall"], 12)

	# Terraces.
	for s in range(steps):
		var rad := base_r - s * 3
		var y := o.y + s * 4
		canvas.box(Vector3i(o.x - rad, y, o.z - rad), Vector3i(o.x + rad, y + 3, o.z + rad), kit[&"wall"])
		canvas.box(Vector3i(o.x - rad + 1, y + 3, o.z - rad + 1),
				Vector3i(o.x + rad - 1, y + 3, o.z + rad - 1), kit[&"floor"])
		# Stair up this terrace, on a bearing that rotates every level.
		var d: Vector3i = [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)][s % 4]
		var start := o + Vector3i(d.x * rad, y, d.z * rad)
		canvas.stairs(start - d * 3, -d, 4, 3, kit[&"trim"], 3)
		if kit[&"light"] != Const.AIR and s % 2 == 0:
			canvas.put(o + Vector3i(d.z * (rad - 1), y + 4, d.x * (rad - 1)), kit[&"light"])

	# Sanctum on the summit: door on Z only.
	var top := o.y + steps * 4
	var lo := Vector3i(o.x - 4, top, o.z - 4)
	var hi := Vector3i(o.x + 4, top + 6, o.z + 4)
	canvas.room(lo, hi, kit[&"wall_alt"], kit[&"floor"], kit[&"roof"])
	canvas.doorway(Vector3i(o.x, top + 1, lo.z), 2, 1, 2, 1)
	canvas.tile(Vector3i(o.x, top + 1, lo.z), StructMarkers.door("avian_gate", "z",
		true, "avian_key", absi(StructRng.hash2(int(ctx.get("seed", 0)), 0xA71)) % 999999, 1, 2))
	for d: Vector3i in [Vector3i(-3, 0, -3), Vector3i(3, 0, -3), Vector3i(-3, 0, 3), Vector3i(3, 0, 3)]:
		canvas.box(Vector3i(o.x + d.x, top + 1, o.z + d.z), Vector3i(o.x + d.x, top + 5, o.z + d.z),
				kit[&"pillar"])
	canvas.box(Vector3i(o.x - 1, top + 1, o.z), Vector3i(o.x + 1, top + 2, o.z), kit[&"trim"])
	canvas.tile(Vector3i(o.x, top + 3, o.z), StructMarkers.boss_spawn("avian_sky_priest",
		tier + 1, lo, hi, "boss", StructRng.hash2(int(ctx.get("seed", 0)), 0xB055)))
	if kit[&"light"] != Const.AIR:
		canvas.put(Vector3i(o.x, top + 5, o.z), kit[&"light"])

	# Treasury: a sealed chamber inside the pyramid body, entered only by
	# dropping through a one-voxel slot in the sanctum floor that sits behind
	# the altar — you cannot see it until you flip to the East/West planes.
	var tre := Vector3i(o.x, o.y + (steps - 2) * 4, o.z)
	canvas.room(tre - Vector3i(4, 0, 4), tre + Vector3i(4, 4, 4),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	canvas.carve_box(Vector3i(o.x + 2, tre.y + 5, o.z), Vector3i(o.x + 2, top, o.z))
	for i in range(3):
		_chest(canvas, tre + Vector3i(i * 2 - 2, 1, 2), "avian_temple", ctx, 1)
	canvas.tile(tre + Vector3i(0, 1, 0), StructMarkers.spawner("avian_guardian",
		tier, 3, 8.0, theme, int(ctx.get("seed", 0))))
	canvas.tile(tre + Vector3i(0, 1, -2), StructMarkers.sign("",
		"Beneath the altar, one pace east. The eye must turn."))
	# Key to the sanctum lives in the treasury.
	var kc := StructLoot.chest("avian_temple", tier + 1, theme,
		StructRng.hash2(int(ctx.get("seed", 0)), 0x4B45), "avian_temple")
	kc["guaranteed"] = ["avian_key"]
	var chest_id := StructPalette.generic(&"chest", &"accent")
	canvas.put_tile(tre + Vector3i(0, 1, 3), chest_id if chest_id != Const.AIR else kit[&"accent"], kc)
	_anchor(canvas, ctx, Vector3i(base_r * 2, steps * 4 + 8, base_r * 2))
