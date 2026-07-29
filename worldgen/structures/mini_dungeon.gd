## Small 1-3 room encounters, cheap enough to scatter densely on the 32-block
## mini grid. Every one of these is a *single screen* of content: something you
## can take in from one plane, resolve, and leave.
##
## Several deliberately hide their payoff behind a flip or a one-layer shift —
## at this size that reads as a pleasant surprise rather than a puzzle, and it
## teaches the vocabulary the big perspective set pieces use later.
class_name StructMiniDungeon
extends RefCounted


# ------------------------------------------------------------------- helpers
static func _kit(ctx: Dictionary) -> Dictionary:
	return StructPalette.kit(ctx.get("theme", StructPalette.THEME_NATURAL))


static func _chest_at(canvas: StructCanvas, p: Vector3i, table: String, ctx: Dictionary,
		bonus: int = 0, struct_id: String = "mini") -> void:
	var chest := StructPalette.generic(&"chest", &"accent")
	var theme: StringName = ctx.get("theme", StructPalette.THEME_NATURAL)
	canvas.put_tile(p, chest if chest != Const.AIR else _kit(ctx)[&"accent"],
		StructLoot.chest(table, int(ctx.get("tier", 0)) + bonus, theme,
			StructRng.hash4(int(ctx.get("seed", 0)), p.x, p.y, p.z), struct_id))


static func _anchor(canvas: StructCanvas, ctx: Dictionary, size: Vector3i) -> void:
	var o: Vector3i = ctx["origin"]
	canvas.tile(o, StructMarkers.anchor(String(ctx.get("id", "mini")),
		ctx.get("theme", StructPalette.THEME_NATURAL), int(ctx.get("tier", 0)),
		o, size, int(ctx.get("seed", 0)), String(ctx.get("display", "Encounter"))))


# ==================================================================== monster den
## A gnawed-out cave with a nest, bones and a spawner. The only entrance is a
## crawl-hole on one horizontal axis, so from the other pair of planes the den
## is a sealed bubble in the rock.
static func den(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 8):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_NATURAL)
	var rad := r.randi_range(4, 6)
	canvas.sphere(o + Vector3i(0, rad - 1, 0), rad, Const.AIR)
	canvas.box(Vector3i(o.x - rad, o.y - 1, o.z - rad), Vector3i(o.x + rad, o.y - 1, o.z + rad), kit[&"floor"])

	var bone := StructPalette.generic(&"bone", &"rubble")
	canvas.scatter(Vector3i(o.x - rad + 1, o.y, o.z - rad + 1),
			Vector3i(o.x + rad - 1, o.y, o.z + rad - 1), bone, 0.12, r)
	var web := StructPalette.generic(&"web", &"")
	if web != Const.AIR:
		canvas.scatter(Vector3i(o.x - rad + 1, o.y + rad - 2, o.z - rad + 1),
				Vector3i(o.x + rad - 1, o.y + rad - 1, o.z + rad - 1), web, 0.1, r)

	# The crawl-hole: one axis only.
	var axis := 0 if r.randf() < 0.5 else 2
	var dir := Vector3i(1, 0, 0) if axis == 0 else Vector3i(0, 0, 1)
	for i in range(rad, rad + 5):
		canvas.carve_box(o + dir * i, o + dir * i + Vector3i(0, 1, 0))

	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.spawner(
		"%s_beast" % theme, int(ctx.get("tier", 0)), r.randi_range(2, 4), 7.0,
		theme, int(ctx.get("seed", 0)), false))
	if r.randf() < 0.6:
		_chest_at(canvas, o + Vector3i(1, 0, 1), "den", ctx, 0, "monster_den")
	_anchor(canvas, ctx, Vector3i(rad * 2, rad * 2, rad * 2))


# ================================================================ treasure alcove
## A 3x3 pocket of nothing but a chest, walled on every side but one. The open
## side is picked from the seed, so half the time you walk straight past it and
## only a flip reveals the gap.
static func alcove(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 6):
		return
	var kit := _kit(ctx)
	canvas.room(o - Vector3i(2, 0, 2), o + Vector3i(2, 4, 2),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	var axis := 0 if r.randf() < 0.5 else 2
	var sign_dir := 1 if r.randf() < 0.5 else -1
	var dir := Vector3i(sign_dir, 0, 0) if axis == 0 else Vector3i(0, 0, sign_dir)
	# Approach shaft on one axis only.
	for i in range(2, 7):
		canvas.carve_box(o + dir * i + Vector3i(0, 1, 0), o + dir * i + Vector3i(0, 2, 0))
	_chest_at(canvas, o + Vector3i(0, 1, 0), "treasure", ctx, 1, "treasure_alcove")
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 3, 0), kit[&"light"])
	if r.randf() < 0.4:
		canvas.tile(o + Vector3i(0, 1, 0) + dir, StructMarkers.trap("dart",
				int(ctx.get("tier", 0)), 8.0))
	_anchor(canvas, ctx, Vector3i(5, 5, 5))


# =================================================================== hermit hut
## A surface shack with a hermit NPC, a bed, a tiny garden and a rumour to sell.
static func hermit_hut(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 9):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_NATURAL)
	var lo := o - Vector3i(3, 0, 3)
	var hi := o + Vector3i(3, 4, 3)
	canvas.box_soft(Vector3i(lo.x, lo.y - 6, lo.z), Vector3i(hi.x, lo.y - 1, hi.z), kit[&"wall"])
	canvas.room(lo, hi, kit[&"wall"], kit[&"floor"], kit[&"roof"])
	canvas.box(Vector3i(lo.x - 1, hi.y, lo.z - 1), Vector3i(hi.x + 1, hi.y, hi.z + 1), kit[&"roof"])
	canvas.carve_box(Vector3i(o.x, o.y + 1, lo.z), Vector3i(o.x, o.y + 2, lo.z))

	var bed := StructPalette.generic(&"bed", &"cloth")
	if bed != Const.AIR:
		canvas.box(o + Vector3i(-2, 1, 1), o + Vector3i(-2, 1, 2), bed)
	canvas.tile(o + Vector3i(-2, 1, 1), StructMarkers.npc("hermit", theme,
		o + Vector3i(-2, 1, 1), "hermit", 0, 6.0, int(ctx.get("seed", 0)), "",
		"hermit_rumours"))
	_chest_at(canvas, o + Vector3i(2, 1, 2), "hermit", ctx, 0, "hermit_hut")
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 3, 0), kit[&"light"])

	# Garden patch outside, always on the opposite side to the door.
	var soil := StructPalette.named([&"farmland", &"tilled_soil"], &"dirt")
	canvas.box(Vector3i(o.x - 2, o.y - 1, hi.z + 2), Vector3i(o.x + 2, o.y - 1, hi.z + 4), soil)
	var crop := StructPalette.named([&"wheat", &"crop"], &"")
	if crop != Const.AIR:
		canvas.box(Vector3i(o.x - 2, o.y, hi.z + 2), Vector3i(o.x + 2, o.y, hi.z + 4), crop)
	_anchor(canvas, ctx, Vector3i(7, 5, 7))


# ============================================================= geothermal vent
## A lava throat with a scalded rim. Loud from any plane, which is the point:
## it is a landmark that survives being seen edge-on.
static func geothermal_vent(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 10):
		return
	var theme: StringName = ctx.get("theme", StructPalette.THEME_NATURAL)
	var rim := StructPalette.named([&"obsidian", &"basalt", &"volcanic_rock"], &"cobblestone")
	var lava := Blocks.id(&"lava")
	var depth := r.randi_range(8, 16)

	canvas.cylinder(Vector3i(o.x, o.y - depth, o.z), 4, depth + 3, rim, true)
	canvas.cylinder(Vector3i(o.x, o.y - depth, o.z), 3, depth + 4, Const.AIR)
	canvas.cylinder(Vector3i(o.x, o.y - depth, o.z), 3, depth - 2, lava)
	for y in range(o.y - depth, o.y - 2):
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				if dx * dx + dz * dz <= 9:
					canvas.set_liquid(Vector3i(o.x + dx, y, o.z + dz), Const.MAX_LIQUID)
	# Cracked apron so the vent reads as a crater, not a hole.
	canvas.cylinder(Vector3i(o.x, o.y - 1, o.z), 6, 1, rim)
	canvas.cylinder(Vector3i(o.x, o.y, o.z), 6, 3, Const.AIR)
	canvas.scatter(Vector3i(o.x - 6, o.y, o.z - 6), Vector3i(o.x + 6, o.y, o.z + 6),
			rim, 0.1, r)
	canvas.tile(o + Vector3i(4, 1, 0), StructMarkers.spawner("fire_elemental",
		int(ctx.get("tier", 0)) + 1, 2, 9.0, theme, int(ctx.get("seed", 0))))
	_anchor(canvas, ctx, Vector3i(13, depth + 4, 13))


# ============================================================== crystal pocket
static func crystal_pocket(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 8):
		return
	var crystal := StructPalette.generic(&"crystal", &"accent")
	var rad := r.randi_range(4, 6)
	canvas.sphere(o + Vector3i(0, rad - 2, 0), rad, Const.AIR)
	for i in range(r.randi_range(8, 18)):
		var p := o + Vector3i(r.randi_range(-rad + 1, rad - 1), 0,
				r.randi_range(-rad + 1, rad - 1))
		var hgt := r.randi_range(1, 4)
		canvas.box(p, p + Vector3i(0, hgt, 0), crystal)
	for i in range(r.randi_range(4, 10)):
		var p := o + Vector3i(r.randi_range(-rad + 1, rad - 1), rad,
				r.randi_range(-rad + 1, rad - 1))
		canvas.box(p, p - Vector3i(0, r.randi_range(1, 3), 0), crystal)
	if r.randf() < 0.5:
		_chest_at(canvas, o + Vector3i(0, 0, 0), "cathedral", ctx, 1, "crystal_pocket")
	_anchor(canvas, ctx, Vector3i(rad * 2, rad * 2, rad * 2))


# ================================================================== fossil pit
static func fossil_pit(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 8):
		return
	var bone := StructPalette.generic(&"bone", &"rubble")
	canvas.carve_box(o - Vector3i(5, 0, 2), o + Vector3i(5, 4, 2))
	# A ribcage: arcs in the XY plane, so it is a picture from views 0/2 and a
	# row of stubs from views 1/3 — a small joke about flat projection.
	for i in range(-4, 5, 2):
		for t in range(0, 5):
			var a := float(t) / 4.0 * PI
			canvas.put(o + Vector3i(i, int(round(sin(a) * 4.0)), int(round(cos(a) * 2.0))), bone)
	canvas.box(o + Vector3i(-5, 0, 0), o + Vector3i(5, 0, 0), bone)
	if r.randf() < 0.7:
		_chest_at(canvas, o + Vector3i(0, 1, 0), "grave", ctx, 0, "fossil_pit")
	_anchor(canvas, ctx, Vector3i(11, 5, 5))


# ============================================================== flooded pocket
static func flooded_pocket(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 8):
		return
	var kit := _kit(ctx)
	var rad := r.randi_range(4, 6)
	var water := Blocks.id(&"water")
	canvas.sphere(o + Vector3i(0, rad - 1, 0), rad, Const.AIR)
	canvas.cylinder(Vector3i(o.x, o.y, o.z), rad - 1, 3, water)
	for y in range(o.y, o.y + 3):
		for dx in range(-rad, rad + 1):
			for dz in range(-rad, rad + 1):
				if dx * dx + dz * dz < (rad - 1) * (rad - 1):
					canvas.set_liquid(Vector3i(o.x + dx, y, o.z + dz), Const.MAX_LIQUID)
	var kelp := StructPalette.named([&"kelp", &"seagrass", &"vine"], &"")
	if kelp != Const.AIR:
		canvas.scatter(Vector3i(o.x - rad + 1, o.y + 1, o.z - rad + 1),
				Vector3i(o.x + rad - 1, o.y + 2, o.z + rad - 1), kelp, 0.2, r)
	_chest_at(canvas, o + Vector3i(rad - 2, 3, 0), "cistern", ctx, 0, "flooded_pocket")
	_anchor(canvas, ctx, Vector3i(rad * 2, rad * 2, rad * 2))


# =============================================================== bandit stash
## A camouflaged surface cache: crates under a tarp of foliage, a lookout, and a
## trap for anyone who opens the wrong one.
static func bandit_stash(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 7):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)
	canvas.carve_box(o - Vector3i(2, 0, 2), o + Vector3i(2, 3, 2))
	canvas.box(o - Vector3i(3, 1, 3), o + Vector3i(3, -1, 3), kit[&"floor"])
	var cover := StructPalette.generic(&"leaves", &"roof")
	canvas.box(o + Vector3i(-3, 4, -3), o + Vector3i(3, 4, 3), cover)
	var crate := StructPalette.generic(&"crate", &"accent")
	for i in range(r.randi_range(2, 4)):
		var p := o + Vector3i(r.randi_range(-2, 2), 0, r.randi_range(-2, 2))
		canvas.put_tile(p, crate if crate != Const.AIR else kit[&"accent"],
			StructLoot.chest("bandit", int(ctx.get("tier", 0)), theme,
				StructRng.hash4(int(ctx.get("seed", 0)), p.x, p.y, p.z), "bandit_stash"))
		if r.randf() < 0.3:
			canvas.tile(p + Vector3i(0, 1, 0), StructMarkers.trap("alarm",
					int(ctx.get("tier", 0)), 0.0))
	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.spawner("bandit",
		int(ctx.get("tier", 0)), 2, 10.0, theme, int(ctx.get("seed", 0)), true))
	_anchor(canvas, ctx, Vector3i(7, 5, 7))


# ============================================================ mushroom pocket
static func mushroom_pocket(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 9):
		return
	var rad := r.randi_range(5, 7)
	var cap := StructPalette.named([&"mushroom_cap", &"mushroom_block", &"red_mushroom_block"], &"")
	var stem := StructPalette.named([&"mushroom_stem", &"mushroom_block"], &"")
	var glow := StructPalette.named([&"glow_fungus", &"glowing_fungus", &"glowstone"], &"")
	canvas.sphere(o + Vector3i(0, rad - 2, 0), rad, Const.AIR)
	canvas.box(Vector3i(o.x - rad, o.y - 1, o.z - rad), Vector3i(o.x + rad, o.y - 1, o.z + rad),
			StructPalette.named([&"mycelium", &"grass"], &"dirt"))
	for i in range(r.randi_range(3, 6)):
		var p := o + Vector3i(r.randi_range(-rad + 2, rad - 2), 0, r.randi_range(-rad + 2, rad - 2))
		var hgt := r.randi_range(2, 4)
		if stem != Const.AIR:
			canvas.box(p, p + Vector3i(0, hgt, 0), stem)
		if cap != Const.AIR:
			canvas.cylinder(p + Vector3i(0, hgt + 1, 0), 2, 1, cap)
	if glow != Const.AIR:
		canvas.scatter(Vector3i(o.x - rad + 1, o.y, o.z - rad + 1),
				Vector3i(o.x + rad - 1, o.y + 1, o.z + rad - 1), glow, 0.08, r)
	_anchor(canvas, ctx, Vector3i(rad * 2, rad * 2, rad * 2))


# ================================================================ shrine niche
## A wayside shrine carved into rock. The offering bowl is one layer behind the
## statue, so the reward is only reachable after a shift.
static func shrine_niche(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 6):
		return
	var kit := _kit(ctx)
	canvas.room(o - Vector3i(2, 0, 1), o + Vector3i(2, 4, 1), kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	canvas.carve_box(o + Vector3i(-1, 1, -1), o + Vector3i(1, 3, 0))
	canvas.box(o + Vector3i(0, 1, 0), o + Vector3i(0, 2, 0), kit[&"accent"])
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 3, 0), kit[&"light"])
	# The bowl: one voxel deeper than the statue's plane.
	canvas.carve_box(o + Vector3i(-1, 1, 1), o + Vector3i(1, 2, 1))
	_chest_at(canvas, o + Vector3i(0, 1, 1), "shrine", ctx, 1, "shrine_niche")
	canvas.tile(o + Vector3i(0, 2, 0), StructMarkers.sign("",
		"The offering is left behind the idol, not before it."))
	_anchor(canvas, ctx, Vector3i(5, 5, 3))
