## Procedural multi-room dungeons: a 3D room lattice joined by a spanning tree of
## corridors and shafts, themed with any of the seven culture block sets.
##
## ## Why the lattice is 3D and why that matters here
##
## Rooms sit on a 3D grid. An edge along **X** becomes a corridor you can simply
## walk in views 0/2; an edge along **Z** becomes a corridor you can only walk in
## views 1/3; an edge along **Y** becomes a shaft. A dungeon is therefore never
## solvable from one plane — the spanning tree deliberately alternates axis at
## every branch, so progress means flipping. Roughly a third of corridors are
## also given a **depth jog**: the corridor reads as a dead end from the plane
## you entered on, and continues one voxel layer behind, so you must `PgDn` one
## layer to carry on. Some rooms get their only doorway on a single axis, which
## makes them invisible until you flip.
##
## ## Progression
##
## The tree is walked from the entrance; the room farthest from it becomes the
## **boss chamber**. An edge about two thirds of the way along that path becomes
## a **locked gate** (door tile-data with `locked = true` and a `key` item). The
## key is placed in a chest in the deepest room *outside* the locked subtree, so
## the dungeon always has a there-and-back-again shape. Treasure rooms hang off
## leaves, trap corridors are sprinkled through the middle band.
class_name StructDungeonGen
extends RefCounted

## Cell pitch. Rooms are centred in their cell so opposite walls always line up.
const PITCH_X := 14
const PITCH_Y := 10
const PITCH_Z := 14
const GRID_X := 4
const GRID_Y := 3
const GRID_Z := 4

## Bounding pad a dungeon definition should declare.
const PAD := GRID_X * PITCH_X / 2 + 8
const DOWN := GRID_Y * PITCH_Y + 6
const UP := 48


# =================================================================== front door
## Structure `build` entry point. `ctx` comes from `StructPlacer`.
## Extra ctx keys honoured: `rooms` (target room count), `surface_entrance`,
## `boss` (monster id), `key_item`.
static func build(canvas: StructCanvas, ctx: Dictionary) -> void:
	var layout := plan(ctx)
	render(canvas, layout, ctx)


## Compute the whole dungeon graph. Pure in `ctx.seed` — every chunk that
## overlaps the dungeon runs this and gets the identical answer.
static func plan(ctx: Dictionary) -> Dictionary:
	var seed_value: int = int(ctx.get("seed", 0))
	var r := StructRng.rng(seed_value, 0xD0176, 0, 0)
	var origin: Vector3i = ctx.get("origin", Vector3i.ZERO)
	var theme: StringName = ctx.get("theme", StructPalette.THEME_ANCIENT)
	var target: int = int(ctx.get("rooms", r.randi_range(9, 15)))

	# Grid origin: the entrance level sits at the anchor, the rest hangs below.
	var base := origin - Vector3i(GRID_X * PITCH_X / 2, 0, GRID_Z * PITCH_Z / 2)

	var rooms: Array = []
	var edges: Array = []
	var visited: Dictionary = {}

	var start := Vector3i(r.randi_range(0, GRID_X - 1), 0, r.randi_range(0, GRID_Z - 1))
	rooms.append(_make_room(base, start, r, 0, -1))
	visited[start] = 0
	var stack: Array = [0]
	var last_axis := -1

	while not stack.is_empty() and rooms.size() < target:
		var idx: int = stack[stack.size() - 1]
		var cell: Vector3i = rooms[idx]["cell"]
		var dirs := _dirs_preferring_other_axis(last_axis, r)
		var advanced := false
		for d: Vector3i in dirs:
			var nc: Vector3i = cell + d
			if nc.x < 0 or nc.x >= GRID_X or nc.z < 0 or nc.z >= GRID_Z:
				continue
			if nc.y < 0 or nc.y >= GRID_Y:
				continue
			if visited.has(nc):
				continue
			var ni := rooms.size()
			rooms.append(_make_room(base, nc, r, int(rooms[idx]["depth"]) + 1, idx))
			visited[nc] = ni
			var axis := 0 if d.x != 0 else (1 if d.y != 0 else 2)
			edges.append({
				"a": idx, "b": ni, "axis": axis, "locked": false,
				"jog": axis != 1 and r.randf() < 0.34,
				"trap": axis != 1 and r.randf() < 0.22,
				"lock_id": 0,
			})
			last_axis = axis
			stack.append(ni)
			advanced = true
			break
		if not advanced:
			stack.pop_back()

	# ------------------------------------------------------------- progression
	var boss_idx := 0
	var best := -1
	for i in range(rooms.size()):
		var score: int = int(rooms[i]["depth"]) * 3 + int(rooms[i]["cell"].y) * 2
		if score > best:
			best = score
			boss_idx = i
	rooms[boss_idx]["type"] = "boss"

	var key_item := String(ctx.get("key_item", "%s_key" % theme))
	var lock_id := absi(StructRng.hash2(seed_value, 0x10CC)) % 1000000
	var gate_child := -1
	var path: Array = _path_to(rooms, boss_idx)
	if path.size() >= 3:
		var gate_at := clampi(int(float(path.size()) * 0.62), 1, path.size() - 1)
		gate_child = path[gate_at]
		for e: Dictionary in edges:
			if int(e["b"]) == gate_child:
				e["locked"] = true
				e["lock_id"] = lock_id
				e["jog"] = false
				e["trap"] = false

	# Key goes in the deepest room that is NOT behind the gate.
	var key_idx := -1
	var key_best := -1
	for i in range(rooms.size()):
		if i == 0 or i == boss_idx:
			continue
		if gate_child >= 0 and _is_behind(rooms, i, gate_child):
			continue
		if int(rooms[i]["depth"]) > key_best:
			key_best = int(rooms[i]["depth"])
			key_idx = i
	if key_idx >= 0:
		rooms[key_idx]["type"] = "key"

	# ---------------------------------------------------------------- flavour
	var child_count: Dictionary = {}
	for e: Dictionary in edges:
		child_count[e["a"]] = int(child_count.get(e["a"], 0)) + 1
	for i in range(1, rooms.size()):
		if rooms[i]["type"] != "room":
			continue
		var leaf: bool = not child_count.has(i)
		if leaf and r.randf() < 0.65:
			rooms[i]["type"] = "treasure"
		elif r.randf() < 0.18:
			rooms[i]["type"] = "shrine"
		elif r.randf() < 0.30:
			rooms[i]["type"] = "trap"
		elif r.randf() < 0.45:
			rooms[i]["type"] = "barracks"
		else:
			rooms[i]["type"] = "hall"
	rooms[0]["type"] = "entrance"

	# One room per dungeon is a "blind vault": its only doorway faces a single
	# axis, so it cannot even be seen until the player flips to that plane.
	for i in range(rooms.size() - 1, 0, -1):
		if rooms[i]["type"] == "treasure":
			rooms[i]["blind"] = true
			break

	return {
		"base": base, "rooms": rooms, "edges": edges, "theme": theme,
		"boss": boss_idx, "key_room": key_idx, "key_item": key_item,
		"lock_id": lock_id, "gate_child": gate_child, "seed": seed_value,
	}


static func _make_room(base: Vector3i, cell: Vector3i, r: RandomNumberGenerator,
		depth: int, parent: int) -> Dictionary:
	var centre := base + Vector3i(
		cell.x * PITCH_X + PITCH_X / 2, -cell.y * PITCH_Y, cell.z * PITCH_Z + PITCH_Z / 2)
	return {
		"cell": cell, "centre": centre, "depth": depth, "parent": parent,
		"hx": r.randi_range(3, PITCH_X / 2 - 2),
		"hz": r.randi_range(3, PITCH_Z / 2 - 2),
		"h": r.randi_range(5, PITCH_Y - 3),
		"type": "room", "blind": false,
	}


## Direction candidates, shuffled, with a strong bias away from `last_axis` so
## consecutive corridors keep changing which viewing plane can walk them.
static func _dirs_preferring_other_axis(last_axis: int, r: RandomNumberGenerator) -> Array:
	var x_dirs: Array = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]
	var z_dirs: Array = [Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var y_dirs: Array = [Vector3i(0, 1, 0)]
	var groups: Array = []
	if last_axis == 0:
		groups = [z_dirs, y_dirs, x_dirs]
	elif last_axis == 2:
		groups = [x_dirs, y_dirs, z_dirs]
	else:
		groups = StructRng.shuffled([x_dirs, z_dirs], r)
		groups.append(y_dirs)
	if r.randf() < 0.3:
		groups.insert(0, y_dirs)
	var out: Array = []
	for g: Array in groups:
		for d: Vector3i in StructRng.shuffled(g, r):
			if not out.has(d):
				out.append(d)
	return out


static func _path_to(rooms: Array, idx: int) -> Array:
	var out: Array = []
	var cur := idx
	var guard := 0
	while cur >= 0 and guard < 256:
		out.push_front(cur)
		cur = int(rooms[cur]["parent"])
		guard += 1
	return out


static func _is_behind(rooms: Array, idx: int, gate_child: int) -> bool:
	var cur := idx
	var guard := 0
	while cur >= 0 and guard < 256:
		if cur == gate_child:
			return true
		cur = int(rooms[cur]["parent"])
		guard += 1
	return false


# ===================================================================== drawing
static func render(canvas: StructCanvas, layout: Dictionary, ctx: Dictionary) -> void:
	var theme: StringName = layout["theme"]
	var kit := StructPalette.kit(theme)
	var tier: int = int(ctx.get("tier", 1))
	var seed_value: int = int(layout["seed"])
	var rooms: Array = layout["rooms"]

	# Anchor marker at the entrance so quests / the map can find the dungeon.
	var entrance: Dictionary = rooms[0]
	canvas.tile(entrance["centre"], StructMarkers.anchor(
		String(ctx.get("id", "dungeon")), theme, tier, entrance["centre"],
		Vector3i(GRID_X * PITCH_X, GRID_Y * PITCH_Y, GRID_Z * PITCH_Z), seed_value,
		String(ctx.get("display", "Dungeon"))))

	for e: Dictionary in layout["edges"]:
		_draw_edge(canvas, layout, e, kit, tier, seed_value)
	for i in range(rooms.size()):
		_draw_room(canvas, layout, i, kit, tier, seed_value, ctx)
	if bool(ctx.get("surface_entrance", true)):
		_draw_surface_entrance(canvas, layout, ctx, kit)


static func _room_box(room: Dictionary) -> Array:
	var c: Vector3i = room["centre"]
	var hx: int = room["hx"]
	var hz: int = room["hz"]
	var h: int = room["h"]
	return [Vector3i(c.x - hx, c.y, c.z - hz), Vector3i(c.x + hx, c.y + h, c.z + hz)]


static func _draw_room(canvas: StructCanvas, layout: Dictionary, idx: int,
		kit: Dictionary, tier: int, seed_value: int, ctx: Dictionary) -> void:
	var room: Dictionary = layout["rooms"][idx]
	var bx: Array = _room_box(room)
	var lo: Vector3i = bx[0]
	var hi: Vector3i = bx[1]
	if not canvas.intersects(lo - Vector3i(1, 1, 1), hi + Vector3i(1, 1, 1)):
		return
	var c: Vector3i = room["centre"]
	var r := StructRng.rng(seed_value, c.x, c.y, c.z)
	var theme: StringName = layout["theme"]

	canvas.room(lo, hi, kit[&"wall"], kit[&"floor"], kit[&"ceiling"])

	# Corner pillars read strongly in a flat side view and give the eye scale.
	if room["hx"] >= 4 and room["hz"] >= 4:
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				var p := Vector3i(c.x + sx * (int(room["hx"]) - 1), c.y + 1,
						c.z + sz * (int(room["hz"]) - 1))
				canvas.box(p, p + Vector3i(0, int(room["h"]) - 2, 0), kit[&"pillar"])

	_light_room(canvas, room, kit, r)

	match String(room["type"]):
		"entrance":
			_furnish_entrance(canvas, room, kit, theme, tier, seed_value, r)
		"boss":
			_furnish_boss(canvas, room, kit, theme, tier, seed_value, ctx, r)
		"treasure":
			_furnish_treasure(canvas, room, kit, theme, tier, seed_value, r, bool(room["blind"]))
		"key":
			_furnish_key(canvas, room, kit, theme, tier, seed_value, layout, r)
		"trap":
			_furnish_trap(canvas, room, kit, theme, tier, seed_value, r)
		"barracks":
			_furnish_barracks(canvas, room, kit, theme, tier, seed_value, r)
		"shrine":
			_furnish_shrine(canvas, room, kit, theme, tier, seed_value, r)
		_:
			_furnish_hall(canvas, room, kit, theme, tier, seed_value, r)


static func _light_room(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		r: RandomNumberGenerator) -> void:
	var lid: int = kit[&"light"]
	if lid == Const.AIR:
		return
	var c: Vector3i = room["centre"]
	var top: int = c.y + int(room["h"]) - 1
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			if r.randf() < 0.25:
				continue
			var p := Vector3i(c.x + sx * maxi(1, int(room["hx"]) - 2), top,
					c.z + sz * maxi(1, int(room["hz"]) - 2))
			canvas.put(p, lid)
			canvas.tile(p, StructMarkers.light("ceiling", 12))


# ------------------------------------------------------------------ furnishing
static func _furnish_entrance(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, r: RandomNumberGenerator) -> void:
	var c: Vector3i = room["centre"]
	canvas.put_tile(Vector3i(c.x, c.y + 1, c.z), StructPalette.generic(&"sign", &"accent"),
		StructMarkers.sign("%s Depths" % StructPalette.THEME_LABELS.get(theme, "Ancient"),
			"Four faces, one road."))
	var crate := StructPalette.generic(&"crate", &"accent")
	if crate != Const.AIR and r.randf() < 0.7:
		var p := Vector3i(c.x + int(room["hx"]) - 1, c.y + 1, c.z - int(room["hz"]) + 1)
		canvas.put_tile(p, crate, StructLoot.chest("ruins", tier, theme,
			StructRng.hash4(seed_value, p.x, p.y, p.z), "dungeon"))


static func _furnish_boss(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, ctx: Dictionary,
		r: RandomNumberGenerator) -> void:
	var c: Vector3i = room["centre"]
	var bx: Array = _room_box(room)
	# Raised dais, readable from every plane.
	canvas.box(Vector3i(c.x - 2, c.y, c.z - 2), Vector3i(c.x + 2, c.y, c.z + 2), kit[&"trim"])
	var boss := String(ctx.get("boss", "%s_warden" % theme))
	canvas.tile(Vector3i(c.x, c.y + 1, c.z), StructMarkers.boss_spawn(
		boss, tier + 1, bx[0], bx[1], "boss", StructRng.hash2(seed_value, 0xB055)))
	var chest := StructPalette.generic(&"chest", &"accent")
	if chest != Const.AIR:
		for sx in [-1, 1]:
			var p := Vector3i(c.x + sx * (int(room["hx"]) - 2), c.y + 1, c.z + int(room["hz"]) - 2)
			canvas.put_tile(p, chest, StructLoot.chest("boss", tier + 1, theme,
				StructRng.hash4(seed_value, p.x, p.y, p.z), "dungeon_boss"))
	var banner: int = kit[&"banner"]
	if banner != Const.AIR:
		for sz in [-1, 1]:
			canvas.box(Vector3i(c.x, c.y + 2, c.z + sz * int(room["hz"])),
					Vector3i(c.x, c.y + int(room["h"]) - 1, c.z + sz * int(room["hz"])), banner)


static func _furnish_treasure(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, r: RandomNumberGenerator,
		blind: bool) -> void:
	var c: Vector3i = room["centre"]
	var chest := StructPalette.generic(&"chest", &"accent")
	var n := r.randi_range(1, 3)
	for i in range(n):
		var p := Vector3i(
			c.x + r.randi_range(-int(room["hx"]) + 1, int(room["hx"]) - 1), c.y + 1,
			c.z + r.randi_range(-int(room["hz"]) + 1, int(room["hz"]) - 1))
		canvas.put_tile(p, chest if chest != Const.AIR else kit[&"accent"],
			StructLoot.chest("treasure", tier + 1, theme,
				StructRng.hash4(seed_value, p.x, p.y, p.z), "dungeon_treasure"))
	if blind:
		# Seal every wall, then reopen exactly one voxel-wide slot on the Z axis.
		# From views 0 and 2 this room is a solid block of masonry.
		var bx: Array = _room_box(room)
		canvas.walls(bx[0], bx[1], kit[&"wall"])
		canvas.doorway(Vector3i(c.x, c.y + 1, int(bx[0].z)), 2, 1, 2, 1)
		canvas.tile(Vector3i(c.x, c.y + 1, int(bx[0].z)),
			StructMarkers.sign("", "Only the West and East faces show the way in."))


static func _furnish_key(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, layout: Dictionary,
		r: RandomNumberGenerator) -> void:
	var c: Vector3i = room["centre"]
	canvas.box(Vector3i(c.x - 1, c.y, c.z - 1), Vector3i(c.x + 1, c.y + 1, c.z + 1), kit[&"trim"])
	var chest := StructPalette.generic(&"chest", &"accent")
	var payload := StructLoot.chest("vault", tier, theme,
		StructRng.hash2(seed_value, 0x4B45), "dungeon_key")
	# "guaranteed" is an optional extra on the container schema: item ids that
	# must be present in addition to the rolled loot.
	payload["guaranteed"] = [String(layout["key_item"])]
	canvas.put_tile(Vector3i(c.x, c.y + 2, c.z), chest if chest != Const.AIR else kit[&"accent"], payload)
	canvas.tile(Vector3i(c.x, c.y + 3, c.z), StructMarkers.light("pedestal", 13))
	canvas.put(Vector3i(c.x, c.y + 3, c.z), kit[&"light"])
	# Guarded.
	canvas.tile(Vector3i(c.x + 2, c.y + 1, c.z), StructMarkers.spawner(
		"%s_guard" % theme, tier, 2, 7.0, theme, StructRng.hash2(seed_value, 0x9A1)))


static func _furnish_trap(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, r: RandomNumberGenerator) -> void:
	var c: Vector3i = room["centre"]
	var spike := StructPalette.generic(&"spike", &"accent")
	for i in range(r.randi_range(3, 7)):
		var p := Vector3i(
			c.x + r.randi_range(-int(room["hx"]) + 1, int(room["hx"]) - 1), c.y + 1,
			c.z + r.randi_range(-int(room["hz"]) + 1, int(room["hz"]) - 1))
		if spike != Const.AIR:
			canvas.put(p, spike)
		canvas.tile(p, StructMarkers.trap("spike", tier, 6.0 + 3.0 * float(tier)))
	canvas.tile(Vector3i(c.x, c.y + 1, c.z), StructMarkers.spawner(
		"%s_lurker" % theme, tier, 2, 6.0, theme, StructRng.hash2(seed_value, 0x7A9)))


static func _furnish_barracks(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, r: RandomNumberGenerator) -> void:
	var c: Vector3i = room["centre"]
	var bed := StructPalette.generic(&"bed", &"cloth")
	for sx in [-1, 1]:
		var p := Vector3i(c.x + sx * (int(room["hx"]) - 1), c.y + 1, c.z - int(room["hz"]) + 2)
		if bed != Const.AIR:
			canvas.box(p, p + Vector3i(0, 0, 1), bed)
	canvas.tile(Vector3i(c.x, c.y + 1, c.z), StructMarkers.spawner(
		"%s_soldier" % theme, tier, r.randi_range(2, 4), 8.0, theme,
		StructRng.hash2(seed_value, 0xBA22)))
	var crate := StructPalette.generic(&"crate", &"accent")
	if crate != Const.AIR:
		var p := Vector3i(c.x - int(room["hx"]) + 1, c.y + 1, c.z + int(room["hz"]) - 1)
		canvas.put_tile(p, crate, StructLoot.chest("outpost", tier, theme,
			StructRng.hash4(seed_value, p.x, p.y, p.z), "dungeon"))


static func _furnish_shrine(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, r: RandomNumberGenerator) -> void:
	var c: Vector3i = room["centre"]
	canvas.box(Vector3i(c.x - 1, c.y + 1, c.z - 1), Vector3i(c.x + 1, c.y + 1, c.z + 1), kit[&"trim"])
	canvas.put(Vector3i(c.x, c.y + 2, c.z), kit[&"accent"])
	canvas.tile(Vector3i(c.x, c.y + 2, c.z), StructMarkers.sign(
		"", "A shrine of the %s." % StructPalette.THEME_LABELS.get(theme, "old ones")))
	var lid: int = kit[&"light"]
	if lid != Const.AIR:
		canvas.put(Vector3i(c.x, c.y + 3, c.z), lid)


static func _furnish_hall(canvas: StructCanvas, room: Dictionary, kit: Dictionary,
		theme: StringName, tier: int, seed_value: int, r: RandomNumberGenerator) -> void:
	var c: Vector3i = room["centre"]
	if r.randf() < 0.5:
		canvas.tile(Vector3i(c.x, c.y + 1, c.z), StructMarkers.spawner(
			"%s_dweller" % theme, tier, 2, 7.0, theme, StructRng.hash2(seed_value, c.x ^ c.z)))
	canvas.scatter(Vector3i(c.x - int(room["hx"]) + 1, c.y + 1, c.z - int(room["hz"]) + 1),
			Vector3i(c.x + int(room["hx"]) - 1, c.y + 1, c.z + int(room["hz"]) - 1),
			kit[&"rubble"], 0.06, r)


# -------------------------------------------------------------------- corridors
static func _draw_edge(canvas: StructCanvas, layout: Dictionary, e: Dictionary,
		kit: Dictionary, tier: int, seed_value: int) -> void:
	var rooms: Array = layout["rooms"]
	var a: Dictionary = rooms[int(e["a"])]
	var b: Dictionary = rooms[int(e["b"])]
	match int(e["axis"]):
		1: _draw_shaft(canvas, a, b, kit, layout, e, tier, seed_value)
		_: _draw_corridor(canvas, a, b, kit, layout, e, tier, seed_value)


static func _draw_corridor(canvas: StructCanvas, a: Dictionary, b: Dictionary,
		kit: Dictionary, layout: Dictionary, e: Dictionary, tier: int,
		seed_value: int) -> void:
	var ca: Vector3i = a["centre"]
	var cb: Vector3i = b["centre"]
	var along_x: bool = ca.z == cb.z
	var y := ca.y + 1
	var r := StructRng.rng(seed_value, ca.x + cb.x, y, ca.z + cb.z)

	var p0 := ca
	var p1 := cb
	# Start/end on the shared cell centre line so the openings always align.
	if along_x:
		var x0 := mini(ca.x, cb.x) + (int(a["hx"]) if ca.x < cb.x else int(b["hx"]))
		var x1 := maxi(ca.x, cb.x) - (int(b["hx"]) if ca.x < cb.x else int(a["hx"]))
		p0 = Vector3i(x0, y, ca.z)
		p1 = Vector3i(x1, y, ca.z)
	else:
		var z0 := mini(ca.z, cb.z) + (int(a["hz"]) if ca.z < cb.z else int(b["hz"]))
		var z1 := maxi(ca.z, cb.z) - (int(b["hz"]) if ca.z < cb.z else int(a["hz"]))
		p0 = Vector3i(ca.x, y, z0)
		p1 = Vector3i(ca.x, y, z1)
	if not canvas.intersects(p0 - Vector3i(3, 2, 3), p1 + Vector3i(3, 4, 3)):
		return

	if bool(e["jog"]):
		_draw_jogged_corridor(canvas, p0, p1, along_x, kit, tier, seed_value, r)
	else:
		canvas.tunnel(p0, p1, 1, 3, kit[&"wall"], kit[&"floor"])

	if bool(e["locked"]):
		_draw_gate(canvas, p0, along_x, kit, layout, e)
	elif bool(e["trap"]):
		_draw_trap_corridor(canvas, p0, p1, along_x, tier, r)


## A corridor that reads as a dead end and continues one voxel layer behind.
## The jog is placed on the *depth* axis of whichever plane walks this corridor,
## so the player must `PgUp`/`PgDn` a single layer to carry on.
static func _draw_jogged_corridor(canvas: StructCanvas, p0: Vector3i, p1: Vector3i,
		along_x: bool, kit: Dictionary, tier: int, seed_value: int,
		r: RandomNumberGenerator) -> void:
	var wall: int = kit[&"wall"]
	var flr: int = kit[&"floor"]
	var off := 1 if r.randf() < 0.5 else -1
	if along_x:
		var mid := (p0.x + p1.x) / 2
		canvas.tunnel(p0, Vector3i(mid, p0.y, p0.z), 1, 3, wall, flr)
		# the sidestep: one layer along Z
		canvas.tunnel(Vector3i(mid, p0.y, p0.z), Vector3i(mid, p0.y, p0.z + off), 1, 3, wall, flr)
		canvas.tunnel(Vector3i(mid, p0.y, p0.z + off), Vector3i(p1.x, p0.y, p0.z + off), 1, 3, wall, flr)
		# Cap the false continuation so it truly looks finished.
		canvas.box(Vector3i(mid + 1, p0.y, p0.z), Vector3i(mid + 1, p0.y + 2, p0.z), wall)
	else:
		var mid := (p0.z + p1.z) / 2
		canvas.tunnel(p0, Vector3i(p0.x, p0.y, mid), 1, 3, wall, flr)
		canvas.tunnel(Vector3i(p0.x, p0.y, mid), Vector3i(p0.x + off, p0.y, mid), 1, 3, wall, flr)
		canvas.tunnel(Vector3i(p0.x + off, p0.y, mid), Vector3i(p0.x + off, p0.y, p1.z), 1, 3, wall, flr)
		canvas.box(Vector3i(p0.x, p0.y, mid + 1), Vector3i(p0.x, p0.y + 2, mid + 1), wall)


static func _draw_trap_corridor(canvas: StructCanvas, p0: Vector3i, p1: Vector3i,
		along_x: bool, tier: int, r: RandomNumberGenerator) -> void:
	var steps := maxi(absi(p1.x - p0.x), absi(p1.z - p0.z))
	var plate := StructPalette.generic(&"pressure_plate", &"trim")
	for i in range(1, steps):
		if r.randf() > 0.3:
			continue
		var p := p0 + (Vector3i(i, 0, 0) if along_x else Vector3i(0, 0, i))
		if plate != Const.AIR:
			canvas.put(p, plate)
		canvas.tile(p, StructMarkers.trap(
			["dart", "flame", "collapse", "gas"][r.randi_range(0, 3)], tier,
			5.0 + 3.0 * float(tier)))


## The locked gate: bars across the corridor plus a `door` payload carrying the
## lock id and the key item name.
static func _draw_gate(canvas: StructCanvas, p0: Vector3i, along_x: bool,
		kit: Dictionary, layout: Dictionary, e: Dictionary) -> void:
	var bars: int = kit[&"bars"]
	if bars == Const.AIR:
		bars = kit[&"trim"]
	var g := p0 + (Vector3i(1, 0, 0) if along_x else Vector3i(0, 0, 1))
	canvas.box(g, g + Vector3i(0, 2, 0), bars)
	canvas.tile(g, StructMarkers.door("%s_gate" % layout["theme"],
		"x" if along_x else "z", true, String(layout["key_item"]),
		int(e["lock_id"]), 1, 3))


## Vertical link. Ladders when the block set has them, stepped platforms when it
## does not, so the shaft is always climbable in both directions.
static func _draw_shaft(canvas: StructCanvas, a: Dictionary, b: Dictionary,
		kit: Dictionary, layout: Dictionary, e: Dictionary, tier: int,
		seed_value: int) -> void:
	var upper: Dictionary = a if int(a["centre"].y) > int(b["centre"].y) else b
	var lower: Dictionary = b if upper == a else a
	var cu: Vector3i = upper["centre"]
	var cl: Vector3i = lower["centre"]
	var x := cu.x
	var z := cu.z
	var y0 := cl.y + int(lower["h"])
	var y1 := cu.y
	if y1 <= y0:
		return
	if not canvas.intersects(Vector3i(x - 2, y0 - 1, z - 2), Vector3i(x + 2, y1 + 1, z + 2)):
		return
	canvas.box(Vector3i(x - 2, y0 - 1, z - 2), Vector3i(x + 2, y1 + 1, z + 2), kit[&"wall"])
	canvas.carve_box(Vector3i(x - 1, y0 - 1, z - 1), Vector3i(x + 1, y1, z + 1))
	var ladder: int = kit[&"ladder"]
	if ladder != Const.AIR:
		canvas.box(Vector3i(x, y0 - 1, z + 1), Vector3i(x, y1, z + 1), ladder)
	else:
		var plat: int = kit[&"platform"]
		if plat == Const.AIR:
			plat = kit[&"trim"]
		var flip := true
		for y in range(y0, y1 + 1, 2):
			var px := x + (1 if flip else -1)
			canvas.box(Vector3i(px, y, z - 1), Vector3i(px, y, z + 1), plat)
			flip = not flip
	if bool(e["locked"]):
		var bars: int = kit[&"bars"] if kit[&"bars"] != Const.AIR else kit[&"trim"]
		canvas.box(Vector3i(x - 1, y0 + 1, z - 1), Vector3i(x + 1, y0 + 1, z + 1), bars)
		canvas.tile(Vector3i(x, y0 + 1, z), StructMarkers.door(
			"%s_hatch" % layout["theme"], "any", true, String(layout["key_item"]),
			int(e["lock_id"]), 3, 1))


## A shaft from the entrance room up to daylight, capped with a small arch so the
## dungeon is findable without digging.
static func _draw_surface_entrance(canvas: StructCanvas, layout: Dictionary,
		ctx: Dictionary, kit: Dictionary) -> void:
	var room: Dictionary = layout["rooms"][0]
	var c: Vector3i = room["centre"]
	var ground: int = int(ctx.get("ground", c.y + 20))
	var top := ground + 1
	if top <= c.y + int(room["h"]):
		return
	if not canvas.intersects(Vector3i(c.x - 3, c.y, c.z - 3), Vector3i(c.x + 3, top + 4, c.z + 3)):
		return
	canvas.box(Vector3i(c.x - 2, c.y, c.z - 2), Vector3i(c.x + 2, top, c.z + 2), kit[&"wall"])
	canvas.carve_box(Vector3i(c.x - 1, c.y + 1, c.z - 1), Vector3i(c.x + 1, top, c.z + 1))
	var ladder: int = kit[&"ladder"]
	if ladder != Const.AIR:
		canvas.box(Vector3i(c.x, c.y + 1, c.z + 1), Vector3i(c.x, top, c.z + 1), ladder)
	else:
		var plat: int = kit[&"platform"] if kit[&"platform"] != Const.AIR else kit[&"trim"]
		var flip := true
		for y in range(c.y + 2, top, 2):
			canvas.box(Vector3i(c.x + (1 if flip else -1), y, c.z - 1),
					Vector3i(c.x + (1 if flip else -1), y, c.z + 1), plat)
			flip = not flip
	# Arch on the surface: open on X only, so from the West/East planes the
	# entrance looks like a solid block of masonry.
	canvas.box(Vector3i(c.x - 2, top + 1, c.z - 2), Vector3i(c.x + 2, top + 4, c.z + 2), kit[&"wall"])
	canvas.carve_box(Vector3i(c.x - 1, top + 1, c.z - 1), Vector3i(c.x + 1, top + 3, c.z + 1))
	canvas.carve_box(Vector3i(c.x - 2, top + 1, c.z), Vector3i(c.x + 2, top + 2, c.z))
