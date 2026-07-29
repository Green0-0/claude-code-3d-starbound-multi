## Underground structure content: the seven themed dungeons plus the standalone
## chambers you stumble into while mining.
##
## Everything here assumes it is being carved *out of solid rock*, so each
## generator writes its own air. Depth drives tier, which drives loot and
## monsters; `StructPlacer` supplies that automatically.
extends RefCounted


static func register_all(out: Array) -> void:
	# ------------------------------------------------------- the seven dungeons
	_register_dungeon(out, "apex_lab", "Apex Laboratory", StructPalette.THEME_APEX,
		{"boss": "apex_overseer", "key_item": "apex_keycard"}, 24, 64,
		["any"], 1.4)
	_register_dungeon(out, "avian_tomb", "Avian Tomb", StructPalette.THEME_AVIAN,
		{"boss": "avian_tomb_king", "key_item": "avian_key"}, 20, 60,
		["desert", "savanna", "mesa", "badlands", "dune"], 1.2)
	_register_dungeon(out, "floran_warren", "Floran Warren", StructPalette.THEME_FLORAN,
		{"boss": "floran_matriarch", "key_item": "floran_thorn"}, 14, 44,
		["jungle", "forest", "swamp"], 1.2)
	_register_dungeon(out, "glitch_castle", "Glitch Undercastle", StructPalette.THEME_GLITCH,
		{"boss": "glitch_knight_errant", "key_item": "iron_key"}, 18, 56,
		["any"], 1.3)
	_register_dungeon(out, "hylotl_city", "Sunken Hylotl City", StructPalette.THEME_HYLOTL,
		{"boss": "hylotl_leviathan", "key_item": "pearl_key"}, 16, 48,
		["ocean", "beach", "reef", "lake", "swamp"], 1.2)
	_register_dungeon(out, "human_bunker", "Human Bunker", StructPalette.THEME_HUMAN,
		{"boss": "bunker_warden", "key_item": "security_card"}, 16, 52,
		["any"], 1.4)
	_register_dungeon(out, "ancient_vault_dungeon", "Ancient Vault Complex",
		StructPalette.THEME_ANCIENT,
		{"boss": "ancient_guardian", "key_item": "ancient_key", "rooms": 15}, 48, 110,
		["any"], 0.8)

	# --------------------------------------------------- standalone underground
	out.append(StructDef.make("sealed_vault", "Sealed Vault", &"underground",
		sealed_vault, {"weight": 1.4, "pad": 16, "up": 14, "down": 10, "tier": 2,
			"y_mode": "buried", "y_min": 30, "y_max": 90,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_APEX,
				StructPalette.THEME_HUMAN]}))
	out.append(StructDef.make("lava_forge", "Lava Forge", &"underground",
		lava_forge, {"weight": 1.3, "pad": 18, "up": 16, "down": 14, "tier": 2,
			"y_mode": "buried", "y_min": 50, "y_max": 100,
			"themes": [StructPalette.THEME_APEX, StructPalette.THEME_GLITCH,
				StructPalette.THEME_HUMAN]}))
	out.append(StructDef.make("crystal_cathedral", "Crystal Cathedral", &"underground",
		crystal_cathedral, {"weight": 1.1, "pad": 22, "up": 26, "down": 12, "tier": 3,
			"y_mode": "buried", "y_min": 40, "y_max": 95,
			"themes": [StructPalette.THEME_ANCIENT, StructPalette.THEME_HYLOTL]}))
	out.append(StructDef.make("flooded_cistern", "Flooded Cistern", &"underground",
		flooded_cistern, {"weight": 1.4, "pad": 18, "up": 14, "down": 12, "tier": 1,
			"y_mode": "buried", "y_min": 18, "y_max": 55,
			"themes": [StructPalette.THEME_HYLOTL, StructPalette.THEME_GLITCH,
				StructPalette.THEME_HUMAN]}))
	out.append(StructDef.make("prison_block", "Prison Block", &"underground",
		prison_block, {"weight": 1.2, "pad": 18, "up": 12, "down": 10, "tier": 2,
			"y_mode": "buried", "y_min": 25, "y_max": 70,
			"themes": [StructPalette.THEME_APEX, StructPalette.THEME_GLITCH,
				StructPalette.THEME_HUMAN]}))
	out.append(StructDef.make("ancient_gateway", "Ancient Gateway", &"underground",
		ancient_gateway, {"weight": 0.8, "pad": 16, "up": 18, "down": 10, "tier": 3,
			"y_mode": "buried", "y_min": 45, "y_max": 100,
			"themes": [StructPalette.THEME_ANCIENT]}))
	out.append(StructDef.make("abandoned_mineshaft", "Abandoned Mineshaft", &"underground",
		abandoned_mineshaft, {"weight": 1.8, "pad": 30, "up": 10, "down": 12, "tier": 1,
			"y_mode": "buried", "y_min": 20, "y_max": 75}))

	# ------------------------------------------------------------------- minis
	out.append(StructDef.make("monster_den", "Monster Den", &"mini",
		StructMiniDungeon.den, {"weight": 2.5, "pad": 9, "up": 10, "down": 4,
			"y_mode": "buried", "y_min": 12, "y_max": 80}))
	out.append(StructDef.make("treasure_alcove", "Treasure Alcove", &"mini",
		StructMiniDungeon.alcove, {"weight": 1.6, "pad": 8, "up": 8, "down": 4, "tier": 1,
			"y_mode": "buried", "y_min": 16, "y_max": 95}))
	out.append(StructDef.make("crystal_pocket", "Crystal Pocket", &"mini",
		StructMiniDungeon.crystal_pocket, {"weight": 1.6, "pad": 8, "up": 10, "down": 4,
			"tier": 1, "y_mode": "buried", "y_min": 25, "y_max": 100}))
	out.append(StructDef.make("fossil_pit", "Fossil Pit", &"mini",
		StructMiniDungeon.fossil_pit, {"weight": 1.3, "pad": 8, "up": 8, "down": 4,
			"y_mode": "buried", "y_min": 14, "y_max": 60}))
	out.append(StructDef.make("flooded_pocket", "Flooded Pocket", &"mini",
		StructMiniDungeon.flooded_pocket, {"weight": 1.3, "pad": 8, "up": 10, "down": 4,
			"y_mode": "buried", "y_min": 12, "y_max": 55}))
	out.append(StructDef.make("mushroom_pocket", "Mushroom Grotto", &"mini",
		StructMiniDungeon.mushroom_pocket, {"weight": 1.5, "pad": 10, "up": 12, "down": 4,
			"y_mode": "buried", "y_min": 12, "y_max": 65}))
	out.append(StructDef.make("shrine_niche", "Wall Shrine", &"mini",
		StructMiniDungeon.shrine_niche, {"weight": 1.4, "pad": 7, "up": 8, "down": 3,
			"tier": 1, "y_mode": "buried", "y_min": 15, "y_max": 90}))


static func _register_dungeon(out: Array, id: String, display: String, theme: StringName,
		extra: Dictionary, y_min: int, y_max: int, biomes: Array, weight: float) -> void:
	out.append(StructDef.make(id, display, &"dungeon", StructDungeonGen.build, {
		"weight": weight, "pad": StructDungeonGen.PAD,
		"up": StructDungeonGen.UP, "down": StructDungeonGen.DOWN,
		"tier": 2, "themes": [theme], "biomes": biomes,
		"y_mode": "buried", "y_min": y_min, "y_max": y_max,
		"ctx": extra,
	}))


# ==============================================================================
#  Shared helpers
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


static func _anchor(canvas: StructCanvas, ctx: Dictionary, size: Vector3i) -> void:
	var o: Vector3i = ctx["origin"]
	canvas.tile(o, StructMarkers.anchor(String(ctx.get("id", "structure")),
		ctx.get("theme", StructPalette.THEME_ANCIENT), int(ctx.get("tier", 0)),
		o, size, int(ctx.get("seed", 0)), String(ctx.get("display", "Structure"))))


## Dig an access adit from a chamber out into the surrounding rock, on ONE axis.
static func _adit(canvas: StructCanvas, from: Vector3i, axis: int, sign_dir: int,
		length: int, kit: Dictionary) -> void:
	var dir := Vector3i(sign_dir, 0, 0) if axis == 0 else Vector3i(0, 0, sign_dir)
	canvas.tunnel(from, from + dir * length, 1, 3, kit[&"wall"], kit[&"floor"])


# ==============================================================================
#  Sealed vault
# ==============================================================================
## A strongroom with no door. The wall is opened by a wheel in a service shaft
## that runs *perpendicular* to the vault's own axis: standing in front of the
## vault you can see the seam but not the mechanism, and the shaft that holds it
## is only walkable from the other plane pair.
static func sealed_vault(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 18):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 2))
	var lock_id := absi(StructRng.hash2(int(ctx.get("seed", 0)), 0x5EA1)) % 999999

	# Antechamber (entered along X).
	canvas.room(o - Vector3i(6, 0, 3), o + Vector3i(-1, 5, 3),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	_adit(canvas, o + Vector3i(-6, 1, 0), 0, -1, 10, kit)

	# The vault proper.
	canvas.room(o + Vector3i(1, 0, -4), o + Vector3i(8, 6, 4),
			kit[&"wall_alt"], kit[&"floor"], kit[&"ceiling"])
	# The door slab: a solid wall carrying the lock payload.
	var door_cells: Array = []
	for y in range(o.y + 1, o.y + 4):
		for z in range(o.z - 1, o.z + 2):
			door_cells.append(Vector3i(o.x + 1, y, z))
			canvas.put(Vector3i(o.x + 1, y, z), kit[&"trim"])
	canvas.tile(Vector3i(o.x + 1, o.y + 2, o.z), StructMarkers.door(
		"%s_vault" % theme, "x", true, "", lock_id, 3, 3))

	# Service shaft along Z, behind the antechamber's north wall.
	var sz := o.z - 6
	canvas.tunnel(Vector3i(o.x - 3, o.y + 1, sz), Vector3i(o.x - 3, o.y + 1, sz - 10),
			1, 3, kit[&"wall"], kit[&"floor"])
	canvas.carve_box(Vector3i(o.x - 3, o.y + 1, o.z - 3), Vector3i(o.x - 3, o.y + 3, sz))
	var lever := StructPalette.generic(&"lever", &"accent")
	var lp := Vector3i(o.x - 3, o.y + 2, sz - 8)
	canvas.put_tile(lp, lever if lever != Const.AIR else kit[&"accent"],
		StructMarkers.lever(lock_id, "sealed_vault", door_cells,
			"The wheel turns the slab three rooms away."))
	if kit[&"light"] != Const.AIR:
		canvas.put(lp + Vector3i(0, 1, 0), kit[&"light"])

	# Contents.
	for i in range(3):
		_chest(canvas, o + Vector3i(3 + i, 1, -2 + i * 2), "vault", ctx, 1)
	canvas.tile(o + Vector3i(5, 1, 0), StructMarkers.spawner("%s_sentinel" % theme,
		tier + 1, 2, 8.0, theme, int(ctx.get("seed", 0))))
	canvas.tile(o + Vector3i(-4, 1, 0), StructMarkers.sign("",
		"No hinge, no handle. Look sideways."))
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(5, 5, 0), kit[&"light"])
	canvas.scatter(o - Vector3i(6, 0, 3), o + Vector3i(-2, 0, 3), kit[&"rubble"], 0.06, r)
	_anchor(canvas, ctx, Vector3i(20, 8, 16))


# ==============================================================================
#  Lava forge
# ==============================================================================
static func lava_forge(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 20):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_APEX)
	var tier: int = int(ctx.get("tier", 2))
	var lava := Blocks.id(&"lava")

	# The hall.
	canvas.room(o - Vector3i(11, 0, 8), o + Vector3i(11, 10, 8),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	# Lava channel down the middle of the X axis: a bright ribbon in views 0/2
	# and an impassable pool that must be crossed by gantry in views 1/3.
	canvas.carve_box(o + Vector3i(-9, -2, -1), o + Vector3i(9, 0, 1))
	canvas.box(o + Vector3i(-9, -2, -1), o + Vector3i(9, -1, 1), lava)
	for x in range(o.x - 9, o.x + 10):
		for z in range(o.z - 1, o.z + 2):
			canvas.set_liquid(Vector3i(x, o.y - 1, z), Const.MAX_LIQUID)

	# Gantries crossing the channel, spaced so only some line up per plane.
	var plat: int = kit[&"platform"] if kit[&"platform"] != Const.AIR else kit[&"trim"]
	for x in range(o.x - 8, o.x + 9, 5):
		canvas.box(Vector3i(x, o.y + 1, o.z - 2), Vector3i(x, o.y + 1, o.z + 2), plat)

	# Furnace bank on the north wall, anvils on the south.
	var furnace := StructPalette.generic(&"furnace", &"accent")
	var anvil := StructPalette.generic(&"anvil", &"trim")
	for i in range(-3, 4):
		if furnace != Const.AIR:
			canvas.put(o + Vector3i(i * 3, o.y + 1 - o.y, -7), furnace)
		if anvil != Const.AIR and i % 2 == 0:
			canvas.put(o + Vector3i(i * 3, 1, 7), anvil)
	canvas.box(o + Vector3i(-11, 1, -8), o + Vector3i(11, 1, -8), kit[&"trim"])

	# Chimneys punched through the ceiling — vertical light shafts.
	for x in [-6, 0, 6]:
		canvas.carve_box(o + Vector3i(x, 10, 0), o + Vector3i(x, 18, 0))
	if kit[&"light"] != Const.AIR:
		for x in range(-9, 10, 4):
			canvas.put(o + Vector3i(x, 9, -7), kit[&"light"])
			canvas.put(o + Vector3i(x, 9, 7), kit[&"light"])

	for i in range(3):
		_chest(canvas, o + Vector3i(-8 + i * 8, 1, 6), "forge", ctx, 1)
	canvas.tile(o + Vector3i(0, 1, 5), StructMarkers.spawner("%s_forgeworker" % theme,
		tier, 4, 12.0, theme, int(ctx.get("seed", 0))))
	canvas.tile(o + Vector3i(0, 1, -6), StructMarkers.sign("Foundry",
		"Mind the channel. It is only shallow from one side."))
	_adit(canvas, o + Vector3i(-11, 1, 4), 0, -1, 12, kit)
	_adit(canvas, o + Vector3i(4, 1, 8), 2, 1, 12, kit)
	_anchor(canvas, ctx, Vector3i(23, 20, 17))


# ==============================================================================
#  Crystal cathedral
# ==============================================================================
static func crystal_cathedral(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 24):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var tier: int = int(ctx.get("tier", 3))
	var crystal := StructPalette.generic(&"crystal", &"accent")

	# A great cavern: nave along X, transept along Z, so the plan is a cross and
	# each arm is only walkable from one plane pair.
	canvas.carve_box(o - Vector3i(18, 0, 5), o + Vector3i(18, 16, 5))
	canvas.carve_box(o - Vector3i(5, 0, 18), o + Vector3i(5, 16, 18))
	canvas.box(o - Vector3i(18, 1, 5), o + Vector3i(18, 1, 5), kit[&"floor"])
	canvas.box(o - Vector3i(5, 1, 18), o + Vector3i(5, 1, 18), kit[&"floor"])

	# Columns of crystal, alternating so they interleave rather than align.
	for i in range(-16, 17, 4):
		var h := 8 + (absi(i) % 3) * 3
		canvas.box(o + Vector3i(i, 0, -4), o + Vector3i(i, h, -4), crystal)
		canvas.box(o + Vector3i(i, 0, 4), o + Vector3i(i, h, 4), crystal)
	for i in range(-16, 17, 4):
		var h := 7 + (absi(i) % 4) * 2
		canvas.box(o + Vector3i(-4, 0, i), o + Vector3i(-4, h, i), crystal)
		canvas.box(o + Vector3i(4, 0, i), o + Vector3i(4, h, i), crystal)

	# Crossing: a raised altar under a hanging crystal chandelier.
	canvas.box(o - Vector3i(3, 0, 3), o + Vector3i(3, 0, 3), kit[&"trim"])
	canvas.box(o + Vector3i(0, 14, 0), o + Vector3i(0, 10, 0), crystal)
	canvas.sphere(o + Vector3i(0, 9, 0), 2, crystal)
	if kit[&"light"] != Const.AIR:
		canvas.put(o + Vector3i(0, 8, 0), kit[&"light"])
		for d: Vector3i in [Vector3i(-12, 0, 0), Vector3i(12, 0, 0), Vector3i(0, 0, -12), Vector3i(0, 0, 12)]:
			canvas.put(o + d + Vector3i(0, 6, 0), kit[&"light"])

	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.boss_spawn("crystal_seraph",
		tier, o - Vector3i(18, 0, 18), o + Vector3i(18, 16, 18), "boss",
		StructRng.hash2(int(ctx.get("seed", 0)), 0xC0DE)))
	for d: Vector3i in [Vector3i(-15, 1, 0), Vector3i(15, 1, 0), Vector3i(0, 1, -15), Vector3i(0, 1, 15)]:
		_chest(canvas, o + d, "cathedral", ctx, 1)
	canvas.tile(o + Vector3i(2, 1, 0), StructMarkers.sign("",
		"Four arms. You may only ever stand in two."))
	canvas.scatter(o - Vector3i(18, 1, 5), o + Vector3i(18, 1, 5), crystal, 0.03, r)
	_anchor(canvas, ctx, Vector3i(37, 18, 37))


# ==============================================================================
#  Flooded cistern
# ==============================================================================
static func flooded_cistern(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 20):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HYLOTL)
	var tier: int = int(ctx.get("tier", 1))
	var water := Blocks.id(&"water")

	canvas.room(o - Vector3i(14, 0, 14), o + Vector3i(14, 12, 14),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	# Grid of arched piers. Because they are on a lattice, every plane shows a
	# colonnade — but the walkable ledges only connect on one axis per level.
	for gx in range(-10, 11, 5):
		for gz in range(-10, 11, 5):
			canvas.box(o + Vector3i(gx, 1, gz), o + Vector3i(gx, 9, gz), kit[&"pillar"])
			canvas.box(o + Vector3i(gx - 1, 9, gz), o + Vector3i(gx + 1, 9, gz), kit[&"trim"])
			canvas.box(o + Vector3i(gx, 9, gz - 1), o + Vector3i(gx, 9, gz + 1), kit[&"trim"])
	# Water to knee height on the lower half.
	canvas.box(o + Vector3i(-13, 1, -13), o + Vector3i(13, 4, 13), water)
	for y in range(o.y + 1, o.y + 5):
		for x in range(o.x - 13, o.x + 14):
			for z in range(o.z - 13, o.z + 14):
				canvas.set_liquid(Vector3i(x, y, z), Const.MAX_LIQUID)
	# Dry ledges around the rim on alternating axes per height.
	var plat: int = kit[&"platform"] if kit[&"platform"] != Const.AIR else kit[&"trim"]
	canvas.box(o + Vector3i(-13, 5, -13), o + Vector3i(13, 5, -12), plat)
	canvas.box(o + Vector3i(-13, 7, 12), o + Vector3i(13, 7, 13), plat)
	canvas.box(o + Vector3i(-13, 6, -13), o + Vector3i(-12, 6, 13), plat)
	canvas.box(o + Vector3i(12, 8, -13), o + Vector3i(13, 8, 13), plat)

	if kit[&"light"] != Const.AIR:
		for gx in range(-10, 11, 10):
			for gz in range(-10, 11, 10):
				canvas.put(o + Vector3i(gx, 10, gz), kit[&"light"])
	for i in range(3):
		_chest(canvas, o + Vector3i(-12 + i * 12, 6, 12), "cistern", ctx)
	canvas.tile(o + Vector3i(0, 6, 0), StructMarkers.spawner("cistern_lurker",
		tier + 1, 3, 12.0, theme, int(ctx.get("seed", 0))))
	# Inlet tunnels, one per axis.
	_adit(canvas, o + Vector3i(-14, 6, 0), 0, -1, 12, kit)
	_adit(canvas, o + Vector3i(0, 8, 14), 2, 1, 12, kit)
	_anchor(canvas, ctx, Vector3i(29, 14, 29))


# ==============================================================================
#  Prison block
# ==============================================================================
## Two rows of cells facing a corridor, plus a warden's office whose key rack is
## in a maintenance crawl one layer behind the cell backs.
static func prison_block(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 20):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)
	var tier: int = int(ctx.get("tier", 2))
	var bars: int = kit[&"bars"] if kit[&"bars"] != Const.AIR else kit[&"trim"]
	var lock_id := absi(StructRng.hash2(int(ctx.get("seed", 0)), 0x9A11)) % 999999

	canvas.room(o - Vector3i(14, 0, 6), o + Vector3i(14, 6, 6),
			kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
	# Corridor down the middle (walkable in views 0/2).
	canvas.carve_box(o - Vector3i(13, 0, 1), o + Vector3i(13, 4, 1))

	var controls: Array = []
	for i in range(-4, 5):
		var cx := o.x + i * 3
		for sz in [-1, 1]:
			var cz: int = o.z + sz * 4
			canvas.room(Vector3i(cx - 1, o.y, cz - 2), Vector3i(cx + 1, o.y + 4, cz + 2),
					kit[&"wall"], kit[&"floor"], kit[&"ceiling"])
			# Cell fronts are bars, so you can see in from the corridor plane.
			for y in range(o.y + 1, o.y + 4):
				var bp := Vector3i(cx, y, cz - sz * 2)
				canvas.put(bp, bars)
				controls.append(bp)
			canvas.tile(Vector3i(cx, o.y + 2, cz - sz * 2), StructMarkers.door(
				"%s_cell" % theme, "z", true, "", lock_id, 1, 3))
			if r.randf() < 0.45:
				canvas.tile(Vector3i(cx, o.y + 1, cz), StructMarkers.npc("prisoner",
					theme, Vector3i(cx, o.y + 1, cz), "captive", 0, 0.0,
					StructRng.hash3(int(ctx.get("seed", 0)), cx, cz), "", "free_me"))
			elif r.randf() < 0.5:
				canvas.tile(Vector3i(cx, o.y + 1, cz), StructMarkers.spawner("%s_inmate" % theme,
					tier, 1, 4.0, theme, StructRng.hash3(int(ctx.get("seed", 0)), cx, cz)))
			if r.randf() < 0.3:
				_chest(canvas, Vector3i(cx, o.y + 1, cz + sz), "prison", ctx)

	# Warden's office at the east end.
	canvas.room(o + Vector3i(15, 0, -4), o + Vector3i(22, 6, 4),
			kit[&"wall_alt"], kit[&"floor"], kit[&"ceiling"])
	canvas.doorway(o + Vector3i(15, 1, 1), 0, 1, 2, 1)
	_chest(canvas, o + Vector3i(20, 1, 0), "prison", ctx, 1)

	# Maintenance crawl behind the north cell backs — the lever that opens every
	# cell at once lives here, one layer further into the rock.
	var cz2 := o.z - 8
	canvas.tunnel(Vector3i(o.x - 12, o.y + 1, cz2), Vector3i(o.x + 12, o.y + 1, cz2),
			1, 2, kit[&"wall"], kit[&"floor"])
	canvas.carve_box(Vector3i(o.x + 12, o.y + 1, cz2), Vector3i(o.x + 12, o.y + 2, o.z - 6))
	var lever := StructPalette.generic(&"lever", &"accent")
	var lp := Vector3i(o.x - 10, o.y + 2, cz2)
	canvas.put_tile(lp, lever if lever != Const.AIR else kit[&"accent"],
		StructMarkers.lever(lock_id, "prison_block", controls,
			"Every cell, at once — from the crawlway behind them."))
	canvas.tile(o + Vector3i(0, 1, 1), StructMarkers.sign("Block C",
		"Cell keys were never on this side of the wall."))
	_adit(canvas, o + Vector3i(-14, 1, 1), 0, -1, 12, kit)
	_anchor(canvas, ctx, Vector3i(38, 8, 18))


# ==============================================================================
#  Ancient gateway
# ==============================================================================
## The other half of the `beacon_pylon` network. A domed chamber holding a live
## teleporter, guarded, with the activation rune on a balcony reachable only
## from the plane at right angles to the entrance.
static func ancient_gateway(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 18):
		return
	var kit := StructPalette.kit(StructPalette.THEME_ANCIENT)
	var theme := StructPalette.THEME_ANCIENT
	var tier: int = int(ctx.get("tier", 3))
	var gate_id := absi(StructRng.hash2(int(ctx.get("seed", 0)), 0x6A7E)) % 1000000

	canvas.cylinder(Vector3i(o.x, o.y, o.z), 12, 14, kit[&"wall"], true)
	canvas.cylinder(Vector3i(o.x, o.y, o.z), 11, 14, Const.AIR)
	canvas.cylinder(Vector3i(o.x, o.y - 1, o.z), 12, 1, kit[&"floor"])
	canvas.sphere(Vector3i(o.x, o.y + 14, o.z), 12, kit[&"ceiling"], true, 0)
	canvas.sphere(Vector3i(o.x, o.y + 14, o.z), 11, Const.AIR, false, 0)

	# The gate itself: a ring of pillars with the pad at the centre.
	for a in range(8):
		var ang := TAU * float(a) / 8.0
		var p := o + Vector3i(int(round(cos(ang) * 4.0)), 0, int(round(sin(ang) * 4.0)))
		canvas.box(p, p + Vector3i(0, 6, 0), kit[&"pillar"])
		if kit[&"light"] != Const.AIR and a % 2 == 0:
			canvas.put(p + Vector3i(0, 7, 0), kit[&"light"])
	var pad := StructPalette.generic(&"teleporter", &"accent")
	canvas.put_tile(o, pad if pad != Const.AIR else kit[&"accent"],
		StructMarkers.teleporter("ancient_gate", gate_id, "ancient_key", true))

	# Balcony on the Z axis at half height, with the activation rune.
	canvas.box(o + Vector3i(-6, 7, 9), o + Vector3i(6, 7, 11), kit[&"platform"] if kit[&"platform"] != Const.AIR else kit[&"floor"])
	canvas.put_tile(o + Vector3i(0, 8, 10), kit[&"accent"],
		StructMarkers.lever(gate_id, "ancient_gateway", [o],
			"The rune faces the gate, not the door."))
	# Stair to the balcony hugs the wall on Z, so it only reads from views 1/3.
	canvas.stairs(o + Vector3i(6, 1, 11), Vector3i(0, 0, -1), 7, 2, kit[&"trim"], 3)

	canvas.tile(o + Vector3i(0, 1, -3), StructMarkers.spawner("ancient_guardian",
		tier, 3, 12.0, theme, int(ctx.get("seed", 0))))
	for d: Vector3i in [Vector3i(-8, 1, -8), Vector3i(8, 1, -8), Vector3i(-8, 1, 8), Vector3i(8, 1, 8)]:
		_chest(canvas, o + d, "gateway", ctx, 1)
	canvas.tile(o + Vector3i(0, 1, 3), StructMarkers.sign("",
		"It opens for those who have stood on every side of it."))
	_adit(canvas, o + Vector3i(-12, 1, 0), 0, -1, 14, kit)
	_anchor(canvas, ctx, Vector3i(25, 28, 25))


# ==============================================================================
#  Abandoned mineshaft
# ==============================================================================
## A sprawl of timbered drifts on a grid: long runs on X, cross-cuts on Z, and
## the ore pockets deliberately parked at the junctions, so the whole network is
## a lesson in alternating planes.
static func abandoned_mineshaft(canvas: StructCanvas, ctx: Dictionary) -> void:
	var o: Vector3i = ctx["origin"]
	var r: RandomNumberGenerator = ctx["rng"]
	if not canvas.intersects_radius(o, 32):
		return
	var kit := _kit(ctx)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_HUMAN)
	var tier: int = int(ctx.get("tier", 1))
	var beam := StructPalette.generic(&"support", &"pillar")
	var rail := StructPalette.generic(&"rail", &"platform")

	var levels := r.randi_range(2, 3)
	for lv in range(levels):
		var y := o.y - lv * 7
		var runs := r.randi_range(2, 3)
		for i in range(runs):
			var z := o.z + (i - runs / 2) * 9
			canvas.tunnel(Vector3i(o.x - 26, y, z), Vector3i(o.x + 26, y, z), 3, 4,
					kit[&"wall"], kit[&"floor"])
			if rail != Const.AIR:
				canvas.box(Vector3i(o.x - 26, y, z), Vector3i(o.x + 26, y, z), rail)
			for x in range(o.x - 24, o.x + 25, 6):
				canvas.box(Vector3i(x, y, z - 2), Vector3i(x, y + 3, z - 2), beam)
				canvas.box(Vector3i(x, y, z + 2), Vector3i(x, y + 3, z + 2), beam)
				canvas.box(Vector3i(x, y + 3, z - 2), Vector3i(x, y + 3, z + 2), beam)
		# Cross-cuts on Z linking the runs — only walkable from views 1/3.
		for cx in range(o.x - 20, o.x + 21, 13):
			canvas.tunnel(Vector3i(cx, y, o.z - 14), Vector3i(cx, y, o.z + 14), 3, 4,
					kit[&"wall"], kit[&"floor"])
			# Ore pocket at the junction.
			if r.randf() < 0.6:
				_chest(canvas, Vector3i(cx, y + 1, o.z), "mine", ctx)
			if r.randf() < 0.5:
				canvas.tile(Vector3i(cx, y + 1, o.z + 3), StructMarkers.spawner(
					"cave_crawler", tier, 2, 7.0, theme,
					StructRng.hash3(int(ctx.get("seed", 0)), cx, y)))
		# Winze down to the next level.
		if lv < levels - 1:
			var wx := o.x + r.randi_range(-18, 18)
			canvas.carve_box(Vector3i(wx, y - 7, o.z), Vector3i(wx + 1, y + 2, o.z + 1))
			var lad: int = kit[&"ladder"] if kit[&"ladder"] != Const.AIR else beam
			canvas.box(Vector3i(wx, y - 7, o.z), Vector3i(wx, y + 2, o.z), lad)
	# A collapsed section: rubble you have to shift around.
	canvas.box(o + Vector3i(6, -1, -2), o + Vector3i(10, 3, 2), kit[&"rubble"])
	canvas.tile(o + Vector3i(0, 1, 0), StructMarkers.sign("Deep workings",
		"Cave-in at the fourth post. Go round on the cross-cut."))
	_anchor(canvas, ctx, Vector3i(54, levels * 7 + 6, 30))
