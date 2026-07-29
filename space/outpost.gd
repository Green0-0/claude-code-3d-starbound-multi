## The Outpost: a fixed, hand-authored settlement world with the id `"outpost"`.
##
## Lives at `Universe.outpost`.
##
## ===========================================================================
##  HOW IT IS LOADED
## ===========================================================================
## Exactly like the ship: a real `World` world (64x64) whose meta carries
## `generator = "flat"`, registered with `Universe.register_void_world()` so
## nothing outside the authored chunk box can grow terrain. Entering it is
## `Game.travel_to_planet("outpost")`; `Events.world_ready` triggers the stamp.
##
## ---------------------------------------------------------------------------
##  THE PLAN — another plus sign, for the same reason as the ship
## ---------------------------------------------------------------------------
##      +Z   the Ark gateway (the endgame door)
##   -X      market plaza (centre)      +X   vendor row
##      -Z   teleporter hub & landing pad
##
## The market plaza sits at the crossing. The east/west wings read as one
## corridor in views 0 and 2; the north/south wings only open up after a flip.
## Every NPC that matters is placed on a *different depth layer* inside its wing,
## so shopping is a shift as well as a walk.
##
## ---------------------------------------------------------------------------
##  TILE DATA emitted
##   `{"kind":"npc",     "role":<see NPC_ROLES>, "faction":"outpost"}`
##   `{"kind":"station", "role":"printer"|"research"|"crafting"}`
##   `{"kind":"terminal","role":"ark_gateway"|"quest_board"}`
##   `{"kind":"teleporter","role":"outpost","network":"outpost","label":String}`
##   `{"kind":"outpost_root","version":int}`   (build bookkeeping)
## ===========================================================================
class_name SpcOutpost
extends Node

const WORLD_ID := "outpost"
const WORLD_SIZE := 64
## Feet height of the settlement's ground plane.
const GROUND_Y := 64
## Bump this when the layout changes so existing saves re-stamp.
const LAYOUT_VERSION := 1

const REGION_MIN := Vector3i(0, 48, 0)
const REGION_MAX := Vector3i(63, 111, 63)
const CHUNK_MIN := Vector3i(0, 3, 0)
const CHUNK_MAX := Vector3i(3, 6, 3)

const ROOT_MARKER := Vector3i(32, 52, 32)
const ARRIVAL := Vector3(32.5, 64.0, 32.5)
## The plane the settlement is authored to be read in.
const ARRIVAL_VIEW := 0

## Roles the NPC agent should know how to spawn. Anything it does not recognise
## should simply be skipped.
const NPC_ROLES := [
	"quest_giver", "guard", "merchant_general", "merchant_weapons",
	"merchant_blocks", "merchant_seeds", "scientist", "engineer",
	"ark_keeper", "penguin_pilot", "bartender",
]

signal built()

var _stamped := false


func _ready() -> void:
	Events.world_ready.connect(_on_world_ready)


## Destination dictionary for the teleporter network.
static func arrival_destination() -> Dictionary:
	return {
		"id": "outpost", "world": WORLD_ID, "pos": ARRIVAL,
		"view": ARRIVAL_VIEW, "label": "The Outpost", "network": "outpost",
	}


## Travel to the outpost. Uses the teleporter when the player already knows it,
## otherwise loads it directly (the opening beam-in of a new run).
func enter() -> bool:
	if World.planet_id == WORLD_ID:
		return false
	Universe.discover(WORLD_ID)
	Game.travel_to_planet(WORLD_ID)
	return true


func _on_world_ready(planet_id: String) -> void:
	if planet_id != WORLD_ID:
		return
	build()
	_stamped = true
	Universe.discover(WORLD_ID)
	# Make both outpost pads part of the teleporter network the moment the
	# player first sets foot here.
	for d: Dictionary in pads():
		Universe.teleporter.register_destination(d)
	built.emit()


static func _built_version() -> int:
	var d := SpcStamp.tile_at(ROOT_MARKER)
	if String(d.get("kind", "")) != "outpost_root":
		return -1
	return int(d.get("version", -1))


# ==================================================================== markers
## Every NPC spawn point in the settlement, as
## `{"pos": Vector3i, "role": String, "kind": "npc", "faction": "outpost"}`.
## Positions are the voxel the NPC stands in; feet height is `GROUND_Y`.
## The same payload is written into chunk tile data, so the NPC agent can either
## call this or scan `Chunk.tile_data` — whichever suits it.
static func npc_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spec := [
		# plaza — always on the play layer, so the player meets someone at once
		[Vector3i(29, GROUND_Y, 32), "quest_giver"],
		[Vector3i(35, GROUND_Y, 30), "guard"],
		[Vector3i(35, GROUND_Y, 34), "bartender"],
		# east wing: the market. Two of the three are off the centre layer.
		[Vector3i(43, GROUND_Y, 32), "merchant_general"],
		[Vector3i(47, GROUND_Y, 30), "merchant_weapons"],
		[Vector3i(51, GROUND_Y, 34), "merchant_blocks"],
		[Vector3i(45, GROUND_Y, 35), "merchant_seeds"],
		# west wing: the workshop
		[Vector3i(20, GROUND_Y, 32), "scientist"],
		[Vector3i(16, GROUND_Y, 29), "engineer"],
		# north wing: the Ark
		[Vector3i(32, GROUND_Y, 46), "ark_keeper"],
		# south wing: the landing pad
		[Vector3i(32, GROUND_Y, 16), "penguin_pilot"],
	]
	for e in spec:
		var at: Vector3i = e[0]
		out.append({
			"kind": "npc", "role": String(e[1]),
			"faction": "outpost", "pos": at,
		})
	return out


## Teleporter pads built into the settlement.
static func pads() -> Array[Dictionary]:
	return [
		arrival_destination(),
		{
			"id": "outpost_hub", "world": WORLD_ID,
			"pos": Vector3(32.5, GROUND_Y, 20.5), "view": ARRIVAL_VIEW,
			"label": "Outpost — Teleporter Hub", "network": "outpost",
		},
	]


# =================================================================== building
static func _ids() -> Dictionary:
	return {
		"stone": SpcStamp.bid(&"stone", &"stone"),
		"dirt": SpcStamp.bid(&"dirt", &"stone"),
		"grass": SpcStamp.bid(&"grass", &"dirt"),
		"bedrock": SpcStamp.bid(&"bedrock", &"stone"),
		"hull": SpcStamp.bid(&"ship_hull", &"stone"),
		"heavy": SpcStamp.bid(&"ship_hull_heavy", &"ship_hull"),
		"floor": SpcStamp.bid(&"ship_floor", &"ship_hull"),
		"wall": SpcStamp.bid(&"ship_wall", &"ship_hull"),
		"window": SpcStamp.bid(&"ship_window", &"ship_hull"),
		"door": SpcStamp.bid(&"ship_door_frame", &"ship_hull"),
		"light": SpcStamp.bid(&"ship_light", &"ship_hull"),
		"console": SpcStamp.bid(&"ship_console", &"ship_hull"),
		"pad": SpcStamp.bid(&"ship_teleporter_pad", &"ship_floor"),
		"stall": SpcStamp.bid(&"ship_vendor_stall", &"ship_console"),
		"printer": SpcStamp.bid(&"ship_printer", &"ship_console"),
		"research": SpcStamp.bid(&"ship_research", &"ship_console"),
		"ark": SpcStamp.bid(&"ship_ark_gate", &"ship_hull"),
		"banner": SpcStamp.bid(&"ship_banner", &"ship_wall"),
		"marker": SpcStamp.bid(&"ship_marker", &"air"),
		"planter": SpcStamp.bid(&"ship_planter", &"ship_floor"),
	}


## Force the settlement volume resident and stamp it if the layout the world
## carries is older than `LAYOUT_VERSION`. Returns true when it wrote anything.
static func build(force: bool = false) -> bool:
	var s := SpcStamp.new()
	s.ensure_region(REGION_MIN, REGION_MAX)
	if not force and _built_version() >= LAYOUT_VERSION:
		return false
	var ids := _ids()
	s.blank_region(REGION_MIN, REGION_MAX)
	_ground(s, ids)
	_plaza(s, ids)
	_market_wing(s, ids)
	_workshop_wing(s, ids)
	_ark_wing(s, ids)
	_landing_wing(s, ids)
	_markers(s, ids)
	s.set_block(ROOT_MARKER, int(ids["marker"]))
	s.tile(ROOT_MARKER, {"kind": "outpost_root", "version": LAYOUT_VERSION})
	s.commit()
	return true


static func _ground(s: SpcStamp, ids: Dictionary) -> void:
	var last := WORLD_SIZE - 1
	s.fill(Vector3i(0, 58, 0), Vector3i(last, 58, last), int(ids["bedrock"]))
	s.fill(Vector3i(0, 59, 0), Vector3i(last, 60, last), int(ids["stone"]))
	s.fill(Vector3i(0, 61, 0), Vector3i(last, 62, last), int(ids["dirt"]))
	s.fill(Vector3i(0, 63, 0), Vector3i(last, 63, last), int(ids["grass"]))


static func _plaza(s: SpcStamp, ids: Dictionary) -> void:
	s.fill(Vector3i(26, 63, 26), Vector3i(38, 63, 38), int(ids["floor"]))
	# Lamp posts on the four corners of the plaza.
	for p in [Vector3i(27, 63, 27), Vector3i(37, 63, 27),
			Vector3i(27, 63, 37), Vector3i(37, 63, 37)]:
		var post: Vector3i = p
		s.fill(post + Vector3i(0, 1, 0), post + Vector3i(0, 3, 0), int(ids["wall"]))
		s.set_block(post + Vector3i(0, 4, 0), int(ids["light"]))
	# Quest board, right where the player lands.
	s.set_block(Vector3i(30, GROUND_Y, 35), int(ids["console"]))
	s.tile(Vector3i(30, GROUND_Y, 35), {"kind": "terminal", "role": "quest_board"})
	s.fill(Vector3i(28, 63, 28), Vector3i(28, 63, 28), int(ids["planter"]))
	s.fill(Vector3i(36, 63, 36), Vector3i(36, 63, 36), int(ids["planter"]))


## +X wing: the market. Long, shallow, read as a corridor in views 0 and 2.
static func _market_wing(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(38, 63, 28), Vector3i(55, 71, 36),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	_door(s, ids, Vector3i(38, GROUND_Y, 32), 0)
	s.fill(Vector3i(55, 66, 30), Vector3i(55, 68, 34), int(ids["window"]))
	# Counters. Each vendor gets one, on its own depth layer.
	var stalls := [
		[Vector3i(43, GROUND_Y, 31), "merchant_general"],
		[Vector3i(47, GROUND_Y, 29), "merchant_weapons"],
		[Vector3i(51, GROUND_Y, 33), "merchant_blocks"],
		[Vector3i(45, GROUND_Y, 34), "merchant_seeds"],
	]
	for e in stalls:
		var p: Vector3i = e[0]
		s.fill(p, p + Vector3i(2, 0, 0), int(ids["stall"]))
		s.tile(p, {"kind": "station", "role": "shop", "vendor": String(e[1])})
		s.set_block(p + Vector3i(1, 3, 0), int(ids["light"]))
	s.set_block(Vector3i(40, 70, 32), int(ids["banner"]))


## -X wing: the workshop — 3D printer, research terminal, crafting bench.
static func _workshop_wing(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(9, 63, 28), Vector3i(26, 71, 36),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	_door(s, ids, Vector3i(26, GROUND_Y, 32), 0)
	s.fill(Vector3i(9, 66, 30), Vector3i(9, 68, 34), int(ids["window"]))
	s.set_block(Vector3i(12, GROUND_Y, 32), int(ids["printer"]))
	s.tile(Vector3i(12, GROUND_Y, 32), {"kind": "station", "role": "printer"})
	s.set_block(Vector3i(12, GROUND_Y, 30), int(ids["research"]))
	s.tile(Vector3i(12, GROUND_Y, 30), {"kind": "station", "role": "research"})
	s.set_block(Vector3i(12, GROUND_Y, 34), int(ids["console"]))
	s.tile(Vector3i(12, GROUND_Y, 34), {"kind": "station", "role": "crafting"})
	for x in [15, 19, 23]:
		s.set_block(Vector3i(x, 70, 32), int(ids["light"]))


## +Z wing: the Ark. Only reachable after a flip, which is the point.
static func _ark_wing(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(28, 63, 38), Vector3i(36, 75, 55),
		int(ids["heavy"]), int(ids["floor"]), int(ids["heavy"]))
	_door(s, ids, Vector3i(32, GROUND_Y, 38), 1)
	# The gateway itself: a 5-wide, 7-tall arch of ancient plating.
	s.fill(Vector3i(30, GROUND_Y, 50), Vector3i(34, 70, 50), int(ids["ark"]))
	s.fill(Vector3i(31, GROUND_Y, 50), Vector3i(33, 69, 50), Const.AIR)
	# The control pillar, so walking through the arch is never blocked.
	s.tile(Vector3i(30, GROUND_Y, 50), {"kind": "terminal", "role": "ark_gateway"})
	for z in [42, 46]:
		s.set_block(Vector3i(29, 72, z), int(ids["light"]))
		s.set_block(Vector3i(35, 72, z), int(ids["light"]))
	s.fill(Vector3i(30, 74, 44), Vector3i(34, 74, 48), int(ids["window"]))


## -Z wing: the teleporter hub and the shuttle pad.
static func _landing_wing(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(28, 63, 9), Vector3i(36, 71, 26),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	_door(s, ids, Vector3i(32, GROUND_Y, 26), 1)
	s.fill(Vector3i(31, 63, 19), Vector3i(33, 63, 21), int(ids["pad"]))
	s.tile(Vector3i(32, 63, 20), {
		"kind": "teleporter", "role": "outpost", "network": "outpost",
		"label": "Outpost — Teleporter Hub",
	})
	s.fill(Vector3i(30, 70, 20), Vector3i(34, 70, 20), int(ids["light"]))
	s.set_block(Vector3i(29, GROUND_Y, 14), int(ids["console"]))
	s.tile(Vector3i(29, GROUND_Y, 14), {"kind": "terminal", "role": "teleporter"})
	s.fill(Vector3i(29, 66, 9), Vector3i(35, 68, 9), int(ids["window"]))


static func _markers(s: SpcStamp, ids: Dictionary) -> void:
	for m: Dictionary in npc_markers():
		var p: Vector3i = m["pos"]
		s.set_block(p, int(ids["marker"]))
		s.tile(p, {"kind": "npc", "role": String(m["role"]), "faction": "outpost"})


static func _door(s: SpcStamp, ids: Dictionary, foot: Vector3i, axis: int) -> void:
	var frame := int(ids["door"])
	for dy in range(0, 5):
		for d in range(-2, 3):
			var p := foot + Vector3i(0, dy, 0)
			if axis == 0:
				p.z += d
			else:
				p.x += d
			s.set_block(p, frame if (absi(d) == 2 or dy == 4) else Const.AIR)
