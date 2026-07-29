## **Signature content.** Seven set pieces designed from the ground up around the
## flip (`Q`/`E`, rotate the camera 90 degrees) and the shift (`PgUp`/`PgDn`,
## step one voxel layer along the current depth axis).
##
## The grammar every one of them is built from:
##
## * A corridor along **X** can be walked in views 0 (North) and 2 (South).
##   A corridor along **Z** can be walked in views 1 (West) and 3 (East).
##   Therefore an L-bend is a *flip gate*: you cannot run it without rotating.
## * Anything one voxel off the play layer is visible-but-unreachable: the slab
##   renderer dims the layers behind you, so a solution can be *shown* long
##   before it can be *taken*. Shifting is the only way to reach it, and shifts
##   are blocked by solid voxels.
## * A one-voxel-thick slab of air is a perfectly walkable room in the plane it
##   faces, and completely invisible from the perpendicular plane. Two such
##   slabs crossing at right angles are two different rooms occupying the same
##   space — the trick `impossible_chamber` is built on.
##
## | structure | the idea |
## |---|---|
## | `plane_lock_vault` | four wards, one per viewing plane; all four must be thrown |
## | `phantom_corridor` | a corridor that dead-ends five times and continues one layer back each time |
## | `impossible_chamber` | one volume that reads as a library from N/S and a chapel from W/E |
## | `four_faced_shrine` | four doors, four different rooms, one prize |
## | `depth_labyrinth` | a 3D maze whose passages alternate axis at every junction |
## | `ghost_bridge` | a chasm whose only crossing is three layers behind you |
## | `blind_treasury` | a sealed block of masonry with one slot, visible from one plane |
extends RefCounted


static func register_all(out: Array) -> void:
	out.append(StructDef.make("plane_lock_vault", "The Fourfold Lock", &"underground",
		plane_lock_vault, {"weight": 1.0, "pad": 22, "up": 18, "down": 12, "tier": 3,
			"y_mode": "buried", "y_min": 35, "y_max": 95,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_APEX,
				StructPalette.THEME_GLITCH]}))
	out.append(StructDef.make("phantom_corridor", "The Winding Fault", &"underground",
		phantom_corridor, {"weight": 1.3, "pad": 30, "up": 12, "down": 8, "tier": 2,
			"y_mode": "buried", "y_min": 22, "y_max": 85,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_GLITCH,
				StructPalette.THEME_HUMAN]}))
	out.append(StructDef.make("impossible_chamber", "The Chamber of Two Rooms", &"underground",
		impossible_chamber, {"weight": 0.9, "pad": 20, "up": 18, "down": 10, "tier": 3,
			"y_mode": "buried", "y_min": 30, "y_max": 90,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_HYLOTL]}))
	out.append(StructDef.make("four_faced_shrine", "The Fourfold Shrine", &"surface_minor",
		four_faced_shrine, {"weight": 1.2, "pad": 18, "up": 14, "down": 12, "tier": 2,
			"flatness": 6,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_AVIAN,
				StructPalette.THEME_HYLOTL]}))
	out.append(StructDef.make("depth_labyrinth", "The Lattice", &"dungeon",
		depth_labyrinth, {"weight": 0.9, "pad": 34, "up": 16, "down": 26, "tier": 3,
			"y_mode": "buried", "y_min": 40, "y_max": 100,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_GLITCH,
				StructPalette.THEME_APEX]}))
	out.append(StructDef.make("ghost_bridge", "The Ghost Bridge", &"underground",
		ghost_bridge, {"weight": 1.2, "pad": 24, "up": 16, "down": 20, "tier": 2,
			"y_mode": "buried", "y_min": 25, "y_max": 85,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_GLITCH,
				StructPalette.THEME_HYLOTL]}))
	out.append(StructDef.make("blind_treasury", "The Unseen Door", &"underground",
		blind_treasury, {"weight": 1.4, "pad": 14, "up": 12, "down": 8, "tier": 2,
			"y_mode": "buried", "y_min": 20, "y_max": 90, "themes": []}))


# ==============================================================================
#  helpers
# ==============================================================================
static func _kit(ctx: Dictionary) -> Dictionary:
	return StructPalette.kit(ctx.get("theme", StructPalette.THEME_ANCIENT))


static func _chest(canvas: StructCanvas, p: Vector3i, table: String, ctx: Dictionary,
		bonus: int = 0) -> void:
	var c := StructPalette.generic(&"chest", &"accent")
	canvas.put_tile(p, c if c != Const.AIR else _kit(ctx)[&"accent"],
		StructLoot.chest(table, int(ctx.get("tier", 0)) + bonus,
			ctx.get("theme", StructPalette.THEME_ANCIENT),
			StructRng.hash4(int(ctx.get("seed", 0)), p.x, p.y, p.z),
			String(ctx.get("id", ""))))


static func _sign(canvas: StructCanvas, p: Vector3i, lore: String, text: String = "") -> void:
	canvas.tile(p, StructMarkers.sign(text, lore))


static func _anchor(canvas: StructCanvas, ctx: Dictionary, size: Vector3i) -> void:
	var o: Vector3i = ctx["origin"]
	canvas.tile(o, StructMarkers.anchor(String(ctx.get("id", "puzzle")),
		ctx.get("theme", StructPalette.THEME_ANCIENT), int(ctx.get("tier", 0)),
		o, size, int(ctx.get("seed", 0)), String(ctx.get("display", "Puzzle"))))


# ==============================================================================
#  1. The Fourfold Lock
# ==============================================================================
## A strongroom with four wards. Each ward is a lever at the end of a spur that
## only exists on one of the four bearings: +X, -X, +Z, -Z. Two of them can be
## walked in views 0/2 and two only in views 1/3, so opening the vault is
## literally "stand on all four sides of the problem". The vault slab carries a
## `door` payload whose `lock_id` matches all four `lever` payloads; the objects
## agent should only clear the slab once every lever with that id is thrown.
static func plane_lock_vault(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 24):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 3))
	var lock_id := absi(StructRng.hash2(int(ctx.get("seed", 0)), 0xF04D)) % 999999

	# Hub you arrive in.
	canvas.room(o - Vector3i(5, 0, 5), o + Vector3i(5, 7, 5),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	canvas.tunnel(o + Vector3i(-5, 1, 0), o + Vector3i(-16, 1, 0), 1, 3, kit[&"wall"], kit[&"floor"])

	# The vault: sealed above the hub, its slab is the ceiling's centre.
	var vy := o.y + 8
	canvas.room(o + Vector3i(-4, vy - o.y, -4), o + Vector3i(4, vy - o.y + 6, 4),
			kit[&"wall_alt"], kit[&"floor"], kit[&"ceiling"])
	var slab: Array = []
	for x in range(o.x - 1, o.x + 2):
		for z in range(o.z - 1, o.z + 2):
			var p := Vector3i(x, vy, z)
			canvas.put(p, kit[&"trim"])
			slab.append(p)
	canvas.tile(Vector3i(o.x, vy, o.z), StructMarkers.door("%s_vault" % theme, "any",
		true, "", lock_id, 3, 1))

	# Four spurs, one per bearing. Each ends in a ward chamber with a lever.
	var bearings: Array = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var names := ["East ward", "West ward", "South ward", "North ward"]
	for i in range(4):
		var d: Vector3i = bearings[i]
		var axis := 0 if d.x != 0 else 2
		var end := o + d * 14
		canvas.tunnel(o + d * 5 + Vector3i(0, 1, 0), end + Vector3i(0, 1, 0), 1, 3,
				kit[&"wall"], kit[&"floor"])
		canvas.room(end - Vector3i(3, 0, 3), end + Vector3i(3, 5, 3),
				kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
		canvas.doorway(end - d * 3 + Vector3i(0, 1, 0), axis, 1, 2, 1)
		var lever := StructPalette.generic(&"lever", &"accent")
		var lp := end + d * 2 + Vector3i(0, 2, 0)
		canvas.put_tile(lp, lever if lever != Const.AIR else kit[&"accent"],
			StructMarkers.lever(lock_id, "plane_lock_vault", slab,
				"%s of four. The slab lifts only when all are turned." % names[i]))
		if kit[&"light"] != Const.AIR:
			canvas.put(end + Vector3i(0, 5, 0), kit[&"light"])
		canvas.tile(end + Vector3i(0, 1, 0), StructMarkers.spawner("%s_ward" % theme,
			tier, 2, 6.0, theme, StructRng.hash3(int(ctx.get("seed", 0)), i, 0x1EE)))
		if r.randf() < 0.5:
			_chest(canvas, end + Vector3i(d.z, 1, d.x), "puzzle", ctx)

	# The prize.
	for i in range(3):
		_chest(canvas, o + Vector3i(i * 2 - 2, vy - o.y + 1, 2), "vault", ctx, 2)
	canvas.tile(Vector3i(o.x, vy + 1, o.z), StructMarkers.boss_spawn(
		"%s_vault_keeper" % theme, tier + 1, o + Vector3i(-4, vy - o.y, -4),
		o + Vector3i(4, vy - o.y + 6, 4), "boss",
		StructRng.hash2(int(ctx.get("seed", 0)), 0xB055)))
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 6, 0), kit[&"light"])
	_sign(canvas, o + Vector3i(0, 1, -4),
		"Four wards, four faces. You have only ever seen two at a time.")
	_anchor(canvas, ctx, Vector3i(36, 18, 36))


# ==============================================================================
#  2. The Winding Fault
# ==============================================================================
## A corridor that ends. Five times.
##
## Each leg runs along X and terminates in a blank wall; the continuation is one
## voxel deeper in Z, so from the plane you are walking the run genuinely stops.
## The tell is deliberately quiet: a scuff of rubble on the floor at the dead end
## and the dim shape of the next leg showing through as a background layer. One
## `PgDn` and the road goes on.
static func phantom_corridor(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects(o - Vector3i(34, 6, 12), o + Vector3i(34, 12, 12)):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 2))

	var legs := r.randi_range(5, 7)
	var leg_len := 9
	var x := o.x - (legs * leg_len) / 2
	var z := o.z
	var y := o.y

	# Entry stub so the player arrives walking, not falling.
	canvas.tunnel(Vector3i(x - 8, y, z), Vector3i(x, y, z), 1, 3, kit[&"wall"], kit[&"floor"])
	_sign(canvas, Vector3i(x - 7, y + 1, z), "The road does not end. It steps back.")

	for i in range(legs):
		var x1 := x + leg_len
		canvas.tunnel(Vector3i(x, y, z), Vector3i(x1, y, z), 1, 3, kit[&"wall"], kit[&"floor"])
		# The false end: solid masonry, dressed like the rest of the wall.
		canvas.box(Vector3i(x1 + 1, y - 1, z - 1), Vector3i(x1 + 1, y + 4, z + 1), kit[&"wall"])
		# The continuation, one layer behind.
		var nz := z + 1
		canvas.carve_box(Vector3i(x1, y, nz), Vector3i(x1, y + 2, nz))
		canvas.put(Vector3i(x1, y - 1, nz), kit[&"floor"])
		# A scuff of rubble at the dead end: the only diegetic hint.
		if kit[&"rubble"] != Const.AIR:
			canvas.put(Vector3i(x1, y, z), kit[&"rubble"])
		# Occasional reward for reading the room.
		if r.randf() < 0.4:
			var alc := Vector3i(x + leg_len / 2, y, z - 2)
			canvas.carve_box(alc, alc + Vector3i(0, 2, 1))
			_chest(canvas, alc, "puzzle", ctx)
		if r.randf() < 0.35:
			canvas.tile(Vector3i(x + leg_len / 2, y, z), StructMarkers.trap("dart", tier, 7.0))
		if i % 2 == 1:
			# Every other step also drops a level, so the fault reads as a stair
			# in the *side* view as well as the depth view.
			canvas.carve_box(Vector3i(x1, y - 3, nz), Vector3i(x1, y, nz))
			y -= 3
			canvas.put(Vector3i(x1, y - 1, nz), kit[&"floor"])
		if kit[&"light"] != Const.AIR and i % 2 == 0:
			canvas.put(Vector3i(x + 2, y + 3, z), kit[&"light"])
		x = x1
		z = nz

	# The payoff chamber, at the far end and several layers deep.
	canvas.room(Vector3i(x - 1, y - 1, z - 4), Vector3i(x + 9, y + 6, z + 4),
			kit[&"wall_alt"], kit[&"floor"], kit[&"ceiling"])
	canvas.carve_box(Vector3i(x, y, z), Vector3i(x + 1, y + 2, z))
	for i in range(3):
		_chest(canvas, Vector3i(x + 3 + i * 2, y, z + 2), "treasure", ctx, 2)
	canvas.tile(Vector3i(x + 4, y, z), StructMarkers.spawner("%s_stalker" % theme,
		tier + 1, 3, 9.0, theme, int(ctx.get("seed", 0))))
	if kit[&"light"] != Const.AIR:
		canvas.put(Vector3i(x + 4, y + 5, z), kit[&"light"])
	_anchor(canvas, ctx, Vector3i(legs * leg_len + 20, 20, 16))


# ==============================================================================
#  3. The Chamber of Two Rooms
# ==============================================================================
## One volume of rock, two rooms, and they are the same rock.
##
## A one-voxel-thick slab of air facing the X axis is a complete, walkable,
## perfectly legible room in views 0 and 2 — and is edge-on and invisible from
## views 1 and 3. Carve a second such slab facing the Z axis, crossing the first,
## and you have two coherent rooms sharing one column of space: a library when
## you look north, a chapel when you look west. Each has its own floor, its own
## furniture, its own door, and its own chest. Neither can see the other. The
## intersection column is left open so the two readings agree exactly where they
## must, and a single grand chest sits in it — the only object that exists in
## both rooms at once.
static func impossible_chamber(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 22):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 3))
	var half := 11
	var h := 9

	# Solid block of dressed stone to carve out of.
	canvas.box(o - Vector3i(half + 1, 2, half + 1), o + Vector3i(half + 1, h + 2, half + 1),
			kit[&"wall"])

	# ---- Room A: the library. Faces X, lives at z = o.z, walkable in views 0/2.
	canvas.carve_box(Vector3i(o.x - half, o.y, o.z), Vector3i(o.x + half, o.y + h, o.z))
	canvas.box(Vector3i(o.x - half, o.y - 1, o.z), Vector3i(o.x + half, o.y - 1, o.z), kit[&"floor"])
	# Shelving: piers with gaps, a classic library elevation.
	for x in range(o.x - half + 2, o.x + half - 1, 3):
		if absi(x - o.x) <= 1:
			continue
		canvas.box(Vector3i(x, o.y, o.z), Vector3i(x, o.y + 4, o.z), kit[&"trim"])
		canvas.carve_box(Vector3i(x, o.y + 2, o.z), Vector3i(x, o.y + 2, o.z))
	# A mezzanine and a stair, both flat in the same plane.
	canvas.box(Vector3i(o.x + 2, o.y + 5, o.z), Vector3i(o.x + half - 1, o.y + 5, o.z), kit[&"platform"] if kit[&"platform"] != Const.AIR else kit[&"trim"])
	for i in range(5):
		canvas.put(Vector3i(o.x + 2 - i, o.y + 5 - i, o.z), kit[&"trim"])
	if kit[&"light"] != Const.AIR:
		canvas.put(Vector3i(o.x - half + 2, o.y + h - 1, o.z), kit[&"light"])
		canvas.put(Vector3i(o.x + half - 2, o.y + h - 1, o.z), kit[&"light"])
	_chest(canvas, Vector3i(o.x - half + 2, o.y, o.z), "puzzle", ctx, 1)
	# Door on the X axis.
	canvas.tunnel(Vector3i(o.x - half - 1, o.y, o.z), Vector3i(o.x - half - 8, o.y, o.z),
			1, 3, kit[&"wall"], kit[&"floor"])

	# ---- Room B: the chapel. Faces Z, lives at x = o.x, walkable in views 1/3.
	canvas.carve_box(Vector3i(o.x, o.y, o.z - half), Vector3i(o.x, o.y + h, o.z + half))
	canvas.box(Vector3i(o.x, o.y - 1, o.z - half), Vector3i(o.x, o.y - 1, o.z + half), kit[&"floor"])
	# Nave arcade: arches rather than shelves, so the silhouette is different.
	for z in range(o.z - half + 2, o.z + half - 1, 4):
		if absi(z - o.z) <= 1:
			continue
		canvas.box(Vector3i(o.x, o.y, z), Vector3i(o.x, o.y + 5, z), kit[&"pillar"])
		canvas.carve_box(Vector3i(o.x, o.y, z), Vector3i(o.x, o.y + 3, z))
	# Apse steps at the far end.
	for i in range(4):
		canvas.box(Vector3i(o.x, o.y + i, o.z + half - 1 - i), Vector3i(o.x, o.y + i, o.z + half - 1), kit[&"trim"])
	canvas.box(Vector3i(o.x, o.y + 4, o.z + half - 2), Vector3i(o.x, o.y + 6, o.z + half - 2), kit[&"accent"])
	if kit[&"light"] != Const.AIR:
		canvas.put(Vector3i(o.x, o.y + h - 1, o.z - half + 2), kit[&"light"])
		canvas.put(Vector3i(o.x, o.y + 7, o.z + half - 2), kit[&"light"])
	_chest(canvas, Vector3i(o.x, o.y, o.z - half + 2), "puzzle", ctx, 1)
	# Door on the Z axis.
	canvas.tunnel(Vector3i(o.x, o.y, o.z - half - 1), Vector3i(o.x, o.y, o.z - half - 8),
			1, 3, kit[&"wall"], kit[&"floor"])

	# ---- The shared column: open floor to ceiling so both readings agree.
	canvas.carve_box(Vector3i(o.x, o.y, o.z), Vector3i(o.x, o.y + h, o.z))
	canvas.put(Vector3i(o.x, o.y - 1, o.z), kit[&"trim"])
	var c := StructPalette.generic(&"chest", &"accent")
	var payload := StructLoot.chest("vault", tier + 1, theme,
		StructRng.hash2(int(ctx.get("seed", 0)), 0x2400), "impossible_chamber")
	canvas.put_tile(Vector3i(o.x, o.y, o.z), c if c != Const.AIR else kit[&"accent"], payload)
	_sign(canvas, Vector3i(o.x, o.y + 1, o.z),
		"Two rooms, one stone. Whichever you are standing in, the other is also true.")
	canvas.tile(Vector3i(o.x, o.y + 2, o.z), StructMarkers.spawner("%s_echo" % theme,
		tier, 2, 10.0, theme, int(ctx.get("seed", 0))))
	_anchor(canvas, ctx, Vector3i(half * 2 + 2, h + 4, half * 2 + 2))


# ==============================================================================
#  4. The Fourfold Shrine
# ==============================================================================
## A hub with a door on each of the four faces. Two of the four arms run along X
## and two along Z, so you cannot even *try* all the doors without flipping
## twice. Three arms end in decoy chambers (a trap, an empty reliquary, a
## monster nest); the fourth holds the relic. Which one is real is a pure
## function of the seed, so it is different on every planet and consistent for
## every player on the same one.
static func four_faced_shrine(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 20):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 2))
	var true_arm := absi(StructRng.hash2(int(ctx.get("seed", 0)), 0x7A00)) % 4

	# Hub: a stepped plinth under a dome, so it reads as a monument from all four.
	canvas.box_soft(o - Vector3i(6, 10, 6), o + Vector3i(6, -1, 6), kit[&"wall"])
	canvas.room(o - Vector3i(5, 0, 5), o + Vector3i(5, 7, 5),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	canvas.sphere(o + Vector3i(0, 7, 0), 5, kit[&"roof"], true, 0)
	canvas.sphere(o + Vector3i(0, 7, 0), 4, Const.AIR, false, 0)
	canvas.box(o + Vector3i(-1, 1, -1), o + Vector3i(1, 1, 1), kit[&"trim"])
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 9, 0), kit[&"light"])
	_sign(canvas, o + Vector3i(0, 2, 0),
		"Four doors. Three are courtesies. Turn until you find the fourth.")

	var bearings: Array = [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]
	for i in range(4):
		var d: Vector3i = bearings[i]
		var axis := 0 if d.x != 0 else 2
		canvas.doorway(o + d * 5 + Vector3i(0, 1, 0), axis, 1, 2, 1)
		canvas.tile(o + d * 5 + Vector3i(0, 1, 0), StructMarkers.door(
			"%s_door" % theme, "x" if axis == 0 else "z", false, "", 0, 1, 2))
		var end := o + d * 13
		canvas.tunnel(o + d * 6 + Vector3i(0, 1, 0), end + Vector3i(0, 1, 0), 1, 3,
				kit[&"wall"], kit[&"floor"])
		canvas.room(end - Vector3i(4, 0, 4), end + Vector3i(4, 6, 4),
				kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
		canvas.doorway(end - d * 4 + Vector3i(0, 1, 0), axis, 1, 2, 1)
		if kit[&"light"] != Const.AIR:
			canvas.put(end + Vector3i(0, 6, 0), kit[&"light"])

		if i == true_arm:
			# The relic.
			canvas.box(end + Vector3i(-1, 1, -1), end + Vector3i(1, 1, 1), kit[&"trim"])
			canvas.put(end + Vector3i(0, 2, 0), kit[&"accent"])
			var c := StructPalette.generic(&"chest", &"accent")
			var payload := StructLoot.chest("shrine", tier + 2, theme,
				StructRng.hash2(int(ctx.get("seed", 0)), 0x5E1F), "four_faced_shrine")
			payload["guaranteed"] = ["ancient_artifact"]
			canvas.put_tile(end + Vector3i(0, 3, 0), c if c != Const.AIR else kit[&"accent"], payload)
			canvas.tile(end + Vector3i(0, 1, 2), StructMarkers.spawner("%s_ward" % theme,
				tier + 1, 3, 8.0, theme, int(ctx.get("seed", 0))))
		else:
			match i % 3:
				0:
					# Trap room: floor plates over a spike pit.
					canvas.carve_box(end + Vector3i(-3, -3, -3), end + Vector3i(3, 0, 3))
					var spike := StructPalette.generic(&"spike", &"trim")
					if spike != Const.AIR:
						canvas.box(end + Vector3i(-3, -3, -3), end + Vector3i(3, -3, 3), spike)
					canvas.tile(end + Vector3i(0, 1, 0), StructMarkers.trap("collapse", tier, 14.0))
					_sign(canvas, end + Vector3i(0, 2, -3), "A courtesy.")
				1:
					# Empty reliquary — plinths, no relic. Deliberately handsome.
					for sx in [-2, 2]:
						for sz in [-2, 2]:
							canvas.box(end + Vector3i(sx, 1, sz), end + Vector3i(sx, 2, sz), kit[&"pillar"])
					_sign(canvas, end + Vector3i(0, 2, 0), "Taken, long ago.")
				_:
					# Nest.
					canvas.tile(end + Vector3i(0, 1, 0), StructMarkers.spawner(
						"%s_beast" % theme, tier, 4, 8.0, theme,
						StructRng.hash3(int(ctx.get("seed", 0)), i, 0xBEE)))
					_chest(canvas, end + Vector3i(2, 1, 2), "den", ctx)
	_anchor(canvas, ctx, Vector3i(36, 14, 36))


# ==============================================================================
#  5. The Lattice
# ==============================================================================
## A 3D maze on a 5 x 3 x 5 lattice of small chambers. The spanning tree that
## carves it strictly alternates axis wherever it can, so the shortest path
## through is a sequence of flips: run east, flip, run south, flip, drop a
## level, run west. Junction chambers are lit; dead ends are not, which gives
## the player a cheap read on progress from any plane.
static func depth_labyrinth(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	if not canvas.intersects_radius(o, 36):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 3))
	var seed_value: int = int(ctx.get("seed", 0))
	var r := StructRng.rng(seed_value, 0x1A77, 0, 0)

	const NX := 5
	const NY := 3
	const NZ := 5
	const PITCH := 6

	var base := o - Vector3i(NX * PITCH / 2, (NY - 1) * PITCH, NZ * PITCH / 2)
	var cell_pos := func(c: Vector3i) -> Vector3i:
		return base + Vector3i(c.x * PITCH, c.y * PITCH, c.z * PITCH)

	# ---- carve the whole lattice as sealed cells first
	for cx in range(NX):
		for cy in range(NY):
			for cz in range(NZ):
				var p: Vector3i = cell_pos.call(Vector3i(cx, cy, cz))
				if not canvas.intersects(p - Vector3i(2, 0, 2), p + Vector3i(2, 4, 2)):
					continue
				canvas.room(p - Vector3i(2, 0, 2), p + Vector3i(2, 4, 2),
						kit[&"wall"], kit[&"floor"], kit[&"ceiling"])

	# ---- spanning tree with axis alternation
	var visited: Dictionary = {}
	var start := Vector3i(0, NY - 1, 0)
	visited[start] = true
	var stack: Array = [start]
	var edges: Array = []
	var last_axis := -1
	var order: Array = [start]
	while not stack.is_empty():
		var cur: Vector3i = stack[stack.size() - 1]
		var dirs: Array = _lattice_dirs(last_axis, r)
		var moved := false
		for d: Vector3i in dirs:
			var nc: Vector3i = cur + d
			if nc.x < 0 or nc.x >= NX or nc.y < 0 or nc.y >= NY or nc.z < 0 or nc.z >= NZ:
				continue
			if visited.has(nc):
				continue
			visited[nc] = true
			edges.append([cur, nc])
			last_axis = 0 if d.x != 0 else (1 if d.y != 0 else 2)
			stack.append(nc)
			order.append(nc)
			moved = true
			break
		if not moved:
			stack.pop_back()

	# ---- open the doors
	var degree: Dictionary = {}
	for e: Array in edges:
		var a: Vector3i = e[0]
		var b: Vector3i = e[1]
		degree[a] = int(degree.get(a, 0)) + 1
		degree[b] = int(degree.get(b, 0)) + 1
		var pa: Vector3i = cell_pos.call(a)
		var pb: Vector3i = cell_pos.call(b)
		if a.y != b.y:
			var lo: Vector3i = pa if pa.y < pb.y else pb
			var hi: Vector3i = pb if pa.y < pb.y else pa
			canvas.carve_box(Vector3i(lo.x + 1, lo.y + 4, lo.z + 1), Vector3i(lo.x + 1, hi.y, lo.z + 1))
			var lad: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else kit[&"platform"]
			if lad != Const.AIR:
				canvas.box(Vector3i(lo.x + 1, lo.y + 1, lo.z + 1), Vector3i(lo.x + 1, hi.y, lo.z + 1), lad)
		else:
			canvas.tunnel(pa + Vector3i(0, 1, 0), pb + Vector3i(0, 1, 0), 1, 3, -1, kit[&"floor"])

	# ---- dress the cells
	var far: Vector3i = order[order.size() - 1] if not order.is_empty() else start
	for c: Vector3i in visited:
		var p: Vector3i = cell_pos.call(c)
		if not canvas.intersects(p - Vector3i(2, 0, 2), p + Vector3i(2, 4, 2)):
			continue
		var deg: int = int(degree.get(c, 0))
		if deg >= 3 and kit[&"light"] != Const.AIR:
			canvas.put(p + Vector3i(0, 4, 0), kit[&"light"])
		elif deg == 1 and c != start:
			# Dead end: half of them pay out, half of them bite.
			var h := StructRng.hash4(seed_value, c.x, c.y, c.z)
			if StructRng.to_unit(h) < 0.45:
				_chest(canvas, p + Vector3i(0, 1, 0), "puzzle", ctx, 1)
			else:
				canvas.tile(p + Vector3i(0, 1, 0), StructMarkers.spawner(
					"%s_wanderer" % theme, tier, 2, 6.0, theme, h))

	# ---- entrance and prize
	var sp: Vector3i = cell_pos.call(start)
	canvas.tunnel(sp + Vector3i(0, 1, 0), sp + Vector3i(-12, 1, 0), 1, 3, kit[&"wall"], kit[&"floor"])
	_sign(canvas, sp + Vector3i(-10, 2, 0), "Every turning is a turn of the head.")
	var fp: Vector3i = cell_pos.call(far)
	canvas.room(fp - Vector3i(4, 0, 4), fp + Vector3i(4, 6, 4),
			kit[&"wall_alt"], kit[&"floor"], kit[&"ceiling"])
	canvas.carve_box(fp - Vector3i(2, 0, 2) + Vector3i(0, 1, 0), fp + Vector3i(2, 3, 2))
	for i in range(3):
		_chest(canvas, fp + Vector3i(i * 2 - 2, 1, 2), "treasure", ctx, 2)
	canvas.tile(fp + Vector3i(0, 1, 0), StructMarkers.boss_spawn("%s_minotaur" % theme,
		tier + 1, fp - Vector3i(4, 0, 4), fp + Vector3i(4, 6, 4), "boss",
		StructRng.hash2(seed_value, 0xB055)))
	_anchor(canvas, ctx, Vector3i(NX * PITCH, NY * PITCH, NZ * PITCH))


static func _lattice_dirs(last_axis: int, r: RandomNumberGenerator) -> Array:
	var xs: Array = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]
	var zs: Array = [Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var ys: Array = [Vector3i(0, -1, 0), Vector3i(0, 1, 0)]
	var groups: Array = []
	if last_axis == 0:
		groups = [zs, ys, xs]
	elif last_axis == 2:
		groups = [xs, ys, zs]
	else:
		groups = StructRng.shuffled([xs, zs], r)
		groups.append(ys)
	var out: Array = []
	for g: Array in groups:
		for d: Vector3i in StructRng.shuffled(g, r):
			out.append(d)
	return out


# ==============================================================================
#  6. The Ghost Bridge
# ==============================================================================
## A chasm cut along Z, so walking east you meet it as a sheer gap. There is a
## bridge — three layers behind you. The slab renderer shows it as a dim shape
## through the empty air, which is the whole design: the solution is *visible*
## from the moment you arrive and simply out of reach until you shift. Two decoy
## stubs jut from the near lip to make the first jump look survivable.
static func ghost_bridge(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 26):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 2))
	var gap := r.randi_range(11, 15)
	var back := r.randi_range(2, 4)   ## how many layers behind the real span is

	# Approach gallery on the near side, along X.
	canvas.tunnel(o + Vector3i(-20, 0, 0), o + Vector3i(-1, 0, 0), 3, 5, kit[&"wall"], kit[&"floor"])
	# The chasm: a trench running along Z, wide in X, very deep.
	canvas.carve_box(o + Vector3i(0, -26, -14), o + Vector3i(gap, 8, 14))
	canvas.box(o + Vector3i(0, -27, -14), o + Vector3i(gap, -27, 14), kit[&"wall"])
	# Far gallery.
	canvas.tunnel(o + Vector3i(gap + 1, 0, 0), o + Vector3i(gap + 20, 0, 0), 3, 5,
			kit[&"wall"], kit[&"floor"])

	# Decoy stubs on the near lip, at the player's own layer.
	canvas.box(o + Vector3i(0, -1, 0), o + Vector3i(2, -1, 0), kit[&"trim"])
	canvas.box(o + Vector3i(0, -1, -3), o + Vector3i(3, -1, -3), kit[&"trim"])

	# The real span, `back` layers deeper.
	var bz := o.z + back
	canvas.box(Vector3i(o.x, o.y - 1, bz - 1), Vector3i(o.x + gap, o.y - 1, bz + 1), kit[&"platform"] if kit[&"platform"] != Const.AIR else kit[&"trim"])
	# Handrails, so it reads as a bridge and not a ledge.
	canvas.box(Vector3i(o.x, o.y, bz - 1), Vector3i(o.x + gap, o.y, bz - 1), kit[&"fence"] if kit[&"fence"] != Const.AIR else kit[&"trim"])
	canvas.box(Vector3i(o.x, o.y, bz + 1), Vector3i(o.x + gap, o.y, bz + 1), kit[&"fence"] if kit[&"fence"] != Const.AIR else kit[&"trim"])
	# Carve the shift corridor from the near lip back to the span, and again on
	# the far side, so the manoeuvre is: shift back, cross, shift forward.
	canvas.carve_box(o + Vector3i(-1, 0, 0), o + Vector3i(-1, 2, bz - o.z))
	canvas.carve_box(o + Vector3i(gap + 1, 0, 0), o + Vector3i(gap + 1, 2, bz - o.z))
	if kit[&"light"] != Const.AIR:
		for x in range(o.x, o.x + gap + 1, 4):
			canvas.put(Vector3i(x, o.y + 3, bz), kit[&"light"])

	_sign(canvas, o + Vector3i(-3, 1, 0),
		"The bridge is behind you. It has always been behind you.")
	canvas.tile(Vector3i(o.x + gap / 2, o.y, bz), StructMarkers.spawner(
		"%s_wraith" % theme, tier, 2, 10.0, theme, int(ctx.get("seed", 0))))
	_chest(canvas, o + Vector3i(gap + 14, 0, 0), "treasure", ctx, 1)
	# A reward for the players who look down instead: a ledge in the chasm wall.
	var ly := o.y - r.randi_range(8, 16)
	canvas.carve_box(Vector3i(o.x + 1, ly, o.z - 2), Vector3i(o.x + 4, ly + 3, o.z + 2))
	canvas.box(Vector3i(o.x + 1, ly - 1, o.z - 2), Vector3i(o.x + 4, ly - 1, o.z + 2), kit[&"floor"])
	_chest(canvas, Vector3i(o.x + 3, ly, o.z), "vault", ctx, 2)
	_anchor(canvas, ctx, Vector3i(gap + 42, 36, 30))


# ==============================================================================
#  7. The Unseen Door
# ==============================================================================
## A block of masonry with no visible way in. The entrance is a single voxel
## slot in one face, set behind a buttress so that it is occluded from three of
## the four planes and only lines up from the fourth. Inside is a small, very
## good treasury and a locked inner cell whose key is in the outer room — a
## reward for the player who realises "no door" means "wrong plane".
static func blind_treasury(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 16):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 2))
	var lock_id := absi(StructRng.hash2(int(ctx.get("seed", 0)), 0xB11D)) % 999999

	# The block, and the outer room inside it.
	canvas.box(o - Vector3i(9, 1, 9), o + Vector3i(9, 9, 9), kit[&"wall"])
	canvas.room(o - Vector3i(7, 0, 7), o + Vector3i(7, 7, 7),
			kit[&"wall_alt"], kit[&"floor"], kit[&"ceiling"])

	# The slot: pick a face from the seed. Buttresses either side of it hide the
	# opening from every bearing except the one that looks straight down it.
	var face := absi(StructRng.hash2(int(ctx.get("seed", 0)), 0x5107)) % 4
	var d: Vector3i = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)][face]
	var axis := 0 if d.x != 0 else 2
	var across := Vector3i(0, 0, 1) if axis == 0 else Vector3i(1, 0, 0)
	var mouth := o + d * 9
	# Slot itself: one wide, two tall, straight through the shell.
	for i in range(0, 3):
		canvas.carve_box(o + d * (7 + i) + Vector3i(0, 1, 0), o + d * (7 + i) + Vector3i(0, 2, 0))
	# Buttresses.
	for s in [-1, 1]:
		canvas.box(mouth + across * s * 2, mouth + across * s * 2 + d * 3 + Vector3i(0, 6, 0), kit[&"wall"])
	# Approach adit so the slot is findable at all.
	canvas.tunnel(mouth + d + Vector3i(0, 1, 0), mouth + d * 10 + Vector3i(0, 1, 0), 1, 3,
			kit[&"wall"], kit[&"floor"])
	_sign(canvas, mouth + d * 9 + Vector3i(0, 1, 0),
		"It has a door. You are simply not standing where the door is.")

	# Outer room contents, including the inner key.
	for i in range(3):
		_chest(canvas, o + Vector3i(-5 + i * 5, 1, -5), "vault", ctx, 1)
	var c := StructPalette.generic(&"chest", &"accent")
	var kp := StructLoot.chest("puzzle", tier + 1, theme,
		StructRng.hash2(int(ctx.get("seed", 0)), 0x4B45), "blind_treasury")
	kp["guaranteed"] = ["vault_key"]
	canvas.put_tile(o + Vector3i(0, 1, 5), c if c != Const.AIR else kit[&"accent"], kp)
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 7, 0), kit[&"light"])

	# Inner cell, its barred face pointing along the *other* axis.
	var inner_axis := 2 if axis == 0 else 0
	var idir := Vector3i(0, 0, 1) if inner_axis == 2 else Vector3i(1, 0, 0)
	canvas.room(o - idir * 5 - Vector3i(2, 0, 2), o - idir * 5 + Vector3i(2, 4, 2),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	var bars: int = kit[&"bars"] if kit[&"bars"] != Const.AIR else kit[&"trim"]
	var gate := o - idir * 3
	canvas.box(gate + Vector3i(0, 1, 0), gate + Vector3i(0, 3, 0), bars)
	canvas.tile(gate + Vector3i(0, 2, 0), StructMarkers.door("%s_cell" % theme,
		"z" if inner_axis == 2 else "x", true, "vault_key", lock_id, 1, 3))
	var boss_payload := StructLoot.chest("boss", tier + 2, theme,
		StructRng.hash2(int(ctx.get("seed", 0)), 0xB055), "blind_treasury")
	canvas.put_tile(o - idir * 5 + Vector3i(0, 1, 0),
			c if c != Const.AIR else kit[&"accent"], boss_payload)
	canvas.tile(o - idir * 5 + Vector3i(1, 1, 0), StructMarkers.spawner(
		"%s_sentinel" % theme, tier + 1, 2, 6.0, theme, int(ctx.get("seed", 0))))
	_anchor(canvas, ctx, Vector3i(19, 11, 19))
