## The hand-authored voxel layout of the player's ship.
##
## ===========================================================================
##  WHY THE SHIP IS SHAPED LIKE A PLUS SIGN
## ===========================================================================
## The ship is deliberately the game's flip/shift tutorial.
##
##   * Two arms run along **X** (cockpit forward, engine room aft). In views 0
##     and 2 — where X is the screen-lateral axis — those two rooms read as one
##     long side-scrolling corridor.
##   * Two arms run along **Z** (crew quarters, teleporter bay). They are
##     *invisible as corridors* until the player presses Q or E; then the world
##     re-reveals itself and what was a dead end becomes the way on.
##   * Every arm is **7 layers deep**, and the useful fixtures are pushed to the
##     front and back layers. The captain's locker sits three shifts away from
##     the pilot's seat, so PgUp/PgDn is taught by wanting something.
##   * Hull tiers 4 and 5 add a deck **above** and a hold **below**, connected by
##     ladders, so the ship eventually teaches all three axes.
##
## ---------------------------------------------------------------------------
##  COORDINATES  (world id `"ship"`, a 64x64 void world)
##   y = 63..70   cargo hold      (hull tier 5)   feet at y 64
##   y = 71..78   main deck       (hull tier 1)   feet at y 72
##   y = 78..85   upper deck      (hull tier 4)   feet at y 79
##  Everything is centred on (32, ·, 32).
## ---------------------------------------------------------------------------
##  TILE DATA emitted (read by the objects / UI / NPC agents):
##   `{"kind":"terminal",  "role":"star_map"|"ship_status"|"fuel_hatch"}`
##   `{"kind":"container", "role":"captain_locker"|"cargo", "slots":int}`
##   `{"kind":"teleporter","role":"ship", "network":"ship", "label":String}`
##   `{"kind":"crew_bunk", "index":int}`
##   `{"kind":"ship_root", "tier":int}`      (build bookkeeping, do not touch)
## ===========================================================================
class_name SpcShipInterior
extends RefCounted

const WORLD_SIZE := 64
const CENTRE := 32

## Decks. `*_Y0` is the floor slab, `*_Y1` the ceiling slab.
const HOLD_Y0 := 63
const HOLD_Y1 := 71
const MAIN_Y0 := 71
const MAIN_Y1 := 78
const UPPER_Y0 := 78
const UPPER_Y1 := 85

## Feet height of the main deck — the value `SpcShip.DECK_Y` mirrors.
const DECK_FEET := MAIN_Y0 + 1

## Inclusive block box the builder owns. Everything outside is kept void.
const REGION_MIN := Vector3i(8, 48, 8)
const REGION_MAX := Vector3i(56, 111, 56)
## The same box in chunk coordinates, handed to `Universe.register_void_world()`.
const CHUNK_MIN := Vector3i(0, 3, 0)
const CHUNK_MAX := Vector3i(3, 6, 3)

## Invisible bookkeeping voxel: stores which hull tier is currently stamped.
const ROOT_MARKER := Vector3i(32, 56, 32)

## Where the player materialises when boarding — the pad in the middle of the hub.
const SPAWN := Vector3(32.5, 72.0, 32.5)
## The view the ship is authored to be read in: X lateral, cockpit to the right.
const SPAWN_VIEW := 0


# --------------------------------------------------------------------- lookup
static func _ids() -> Dictionary:
	return {
		"hull": SpcStamp.bid(&"ship_hull", &"stone"),
		"heavy": SpcStamp.bid(&"ship_hull_heavy", &"ship_hull"),
		"floor": SpcStamp.bid(&"ship_floor", &"ship_hull"),
		"grate": SpcStamp.bid(&"ship_floor_grate", &"ship_floor"),
		"wall": SpcStamp.bid(&"ship_wall", &"ship_hull"),
		"window": SpcStamp.bid(&"ship_window", &"ship_hull"),
		"door": SpcStamp.bid(&"ship_door_frame", &"ship_hull"),
		"engine": SpcStamp.bid(&"ship_engine", &"ship_hull"),
		"console": SpcStamp.bid(&"ship_console", &"ship_hull"),
		"pad": SpcStamp.bid(&"ship_teleporter_pad", &"ship_floor"),
		"light": SpcStamp.bid(&"ship_light", &"ship_hull"),
		"pipe": SpcStamp.bid(&"ship_pipe", &"ship_hull"),
		"locker": SpcStamp.bid(&"ship_locker", &"ship_hull"),
		"bed": SpcStamp.bid(&"ship_bed", &"ship_floor"),
		"hatch": SpcStamp.bid(&"ship_fuel_hatch", &"ship_console"),
		"ladder": SpcStamp.bid(&"ship_ladder", &"ship_hull"),
		"marker": SpcStamp.bid(&"ship_marker", &"air"),
		"planter": SpcStamp.bid(&"ship_planter", &"ship_floor"),
		"crate": SpcStamp.bid(&"ship_crate", &"ship_locker"),
	}


## Hull tier currently stamped into the world, or -1 when the ship is not built.
static func built_tier() -> int:
	var d := SpcStamp.tile_at(ROOT_MARKER)
	if String(d.get("kind", "")) != "ship_root":
		return -1
	return int(d.get("tier", -1))


## Named fixture positions, so `ship.gd` / `teleporter.gd` never hard-code them.
## Keys: star_map, ship_status, captain_locker, fuel_hatch, teleporter,
## teleporter_bay, printer, bunks (Array[Vector3i]).
static func fixtures(tier: int) -> Dictionary:
	var f := {
		"star_map": Vector3i(48, 73, 32),
		"ship_status": Vector3i(48, 73, 34),
		"captain_locker": Vector3i(48, 73, 29),
		"teleporter": Vector3i(32, MAIN_Y0, 32),
		"bunks": [],
	}
	var bunks: Array = f["bunks"]
	var far := 49 if tier >= 2 else 45
	for z in range(39, far - 2, 2):
		bunks.append(Vector3i(29, DECK_FEET, z))
		bunks.append(Vector3i(35, DECK_FEET, z))
	if tier >= 2:
		f["fuel_hatch"] = Vector3i(18, 73, 32)
	if tier >= 3:
		f["teleporter_bay"] = Vector3i(32, MAIN_Y0, 18)
	return f


# ==================================================================== building
## Bring the hull up to `tier`. Returns true when it actually stamped.
##
## The ship volume is forced resident first, because `built_tier()` reads a tile
## payload out of a chunk and there are no chunks at `world_ready` time. If the
## stamped tier already matches, nothing is written and the player's own
## decoration survives; otherwise the whole volume is blanked and rebuilt, which
## is what makes a hull upgrade a visible refit.
static func build(tier: int, force: bool = false) -> bool:
	var t := clampi(tier, 1, SpcShipUpgrades.MAX_HULL)
	var s := SpcStamp.new()
	s.ensure_region(REGION_MIN, REGION_MAX)
	if not force and built_tier() >= t:
		return false
	var ids := _ids()
	s.blank_region(REGION_MIN, REGION_MAX)

	if t >= 5:
		_hold(s, ids)
	_hub(s, ids)
	_cockpit(s, ids)
	_quarters(s, ids, t)
	if t >= 2:
		_engine(s, ids)
	if t >= 3:
		_teleport_bay(s, ids)
	if t >= 4:
		_upper(s, ids)
	_ladders(s, ids, t)
	_lights(s, ids, t)
	_root(s, ids, t)
	s.commit()
	return true


static func _hub(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(27, MAIN_Y0, 27), Vector3i(37, MAIN_Y1, 37),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	# The boarding pad sits flush in the deck so arriving never means a step up.
	s.fill(Vector3i(31, MAIN_Y0, 31), Vector3i(33, MAIN_Y0, 33), int(ids["pad"]))
	s.tile(Vector3i(32, MAIN_Y0, 32), {
		"kind": "teleporter", "role": "ship", "network": "ship", "label": "Ship",
	})
	# A ring of grating marks the hub as the junction of the four arms.
	for d in range(28, 37):
		s.set_block(Vector3i(d, MAIN_Y0, 28), int(ids["grate"]))
		s.set_block(Vector3i(d, MAIN_Y0, 36), int(ids["grate"]))
		s.set_block(Vector3i(28, MAIN_Y0, d), int(ids["grate"]))
		s.set_block(Vector3i(36, MAIN_Y0, d), int(ids["grate"]))


static func _cockpit(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(37, MAIN_Y0, 28), Vector3i(49, MAIN_Y1, 36),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	_door(s, ids, Vector3i(37, DECK_FEET, 32), 0)
	# Forward viewport: the whole nose is glass.
	s.fill(Vector3i(49, 73, 30), Vector3i(49, 76, 34), int(ids["window"]))
	s.fill(Vector3i(38, MAIN_Y1, 30), Vector3i(46, MAIN_Y1, 34), int(ids["window"]))
	# Console bank along the nose bulkhead, chest height so the deck stays clear.
	s.fill(Vector3i(48, 73, 30), Vector3i(48, 73, 34), int(ids["console"]))
	s.tile(Vector3i(48, 73, 32), {"kind": "terminal", "role": "star_map"})
	s.tile(Vector3i(48, 73, 34), {"kind": "terminal", "role": "ship_status"})
	# Captain's locker, deliberately parked on the front-most layer: three
	# shifts away from the pilot's seat.
	s.set_block(Vector3i(48, 73, 29), int(ids["locker"]))
	s.tile(Vector3i(48, 73, 29), {"kind": "container", "role": "captain_locker", "slots": 16})
	s.set_block(Vector3i(48, 73, 35), int(ids["locker"]))
	s.tile(Vector3i(48, 73, 35), {"kind": "container", "role": "cargo", "slots": 16})
	# Side portholes, one per depth layer, so each layer reads differently.
	for z in [29, 31, 33, 35]:
		s.set_block(Vector3i(42, 74, z), int(ids["window"]))


static func _engine(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(15, MAIN_Y0, 28), Vector3i(27, MAIN_Y1, 36),
		int(ids["heavy"]), int(ids["grate"]), int(ids["heavy"]))
	_door(s, ids, Vector3i(27, DECK_FEET, 32), 0)
	# The drive block itself: a glowing mass filling the aft end.
	s.fill(Vector3i(16, DECK_FEET, 30), Vector3i(17, 76, 34), int(ids["engine"]))
	# Coolant runs
	for z in [29, 35]:
		s.fill(Vector3i(18, 77, z), Vector3i(26, 77, z), int(ids["pipe"]))
	s.set_block(Vector3i(18, 73, 32), int(ids["hatch"]))
	s.tile(Vector3i(18, 73, 32), {"kind": "terminal", "role": "fuel_hatch"})
	s.set_block(Vector3i(20, 73, 29), int(ids["locker"]))
	s.tile(Vector3i(20, 73, 29), {"kind": "container", "role": "cargo", "slots": 12})


static func _quarters(s: SpcStamp, ids: Dictionary, tier: int) -> void:
	var far := 49 if tier >= 2 else 45
	s.room(Vector3i(28, MAIN_Y0, 37), Vector3i(36, MAIN_Y1, far),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	_door(s, ids, Vector3i(32, DECK_FEET, 37), 1)
	# Bunks hug the two outer layers, so berthing crew means shifting.
	var index := 0
	for z in range(39, far - 2, 2):
		for x in [29, 35]:
			s.set_block(Vector3i(x, DECK_FEET, z), int(ids["bed"]))
			s.tile(Vector3i(x, DECK_FEET, z), {"kind": "crew_bunk", "index": index})
			index += 1
	s.set_block(Vector3i(29, DECK_FEET, 38), int(ids["locker"]))
	s.tile(Vector3i(29, DECK_FEET, 38), {"kind": "container", "role": "cargo", "slots": 12})
	s.fill(Vector3i(30, 74, far), Vector3i(34, 75, far), int(ids["window"]))


static func _teleport_bay(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(28, MAIN_Y0, 15), Vector3i(36, MAIN_Y1, 27),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	_door(s, ids, Vector3i(32, DECK_FEET, 27), 1)
	s.fill(Vector3i(31, MAIN_Y0, 17), Vector3i(33, MAIN_Y0, 19), int(ids["pad"]))
	s.tile(Vector3i(32, MAIN_Y0, 18), {
		"kind": "teleporter", "role": "ship", "network": "ship", "label": "Teleporter Bay",
	})
	s.fill(Vector3i(30, 76, 18), Vector3i(34, 76, 18), int(ids["light"]))
	s.set_block(Vector3i(29, 73, 22), int(ids["console"]))
	s.tile(Vector3i(29, 73, 22), {"kind": "terminal", "role": "teleporter"})


static func _upper(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(26, UPPER_Y0, 26), Vector3i(38, UPPER_Y1, 38),
		int(ids["hull"]), int(ids["floor"]), int(ids["hull"]))
	# Skylights, so the upper deck feels like the observation deck it is.
	s.fill(Vector3i(29, UPPER_Y1, 29), Vector3i(35, UPPER_Y1, 35), int(ids["window"]))
	# Greenhouse strip on the far layers.
	for z in [28, 36]:
		s.fill(Vector3i(28, UPPER_Y0 + 1, z), Vector3i(36, UPPER_Y0 + 1, z), int(ids["planter"]))
	s.set_block(Vector3i(30, UPPER_Y0 + 1, 32), int(ids["console"]))
	s.tile(Vector3i(30, UPPER_Y0 + 1, 32), {"kind": "terminal", "role": "ship_status"})


static func _hold(s: SpcStamp, ids: Dictionary) -> void:
	s.room(Vector3i(26, HOLD_Y0, 26), Vector3i(38, HOLD_Y1, 38),
		int(ids["heavy"]), int(ids["floor"]), int(ids["floor"]))
	var index := 0
	for z in [28, 30, 34, 36]:
		for x in [28, 36]:
			s.set_block(Vector3i(x, HOLD_Y0 + 1, z), int(ids["crate"]))
			s.tile(Vector3i(x, HOLD_Y0 + 1, z),
				{"kind": "container", "role": "cargo", "slots": 24, "index": index})
			index += 1


## Ladders are punched **after** every room so a later room's floor slab can
## never seal a shaft that an earlier room opened.
static func _ladders(s: SpcStamp, ids: Dictionary, tier: int) -> void:
	if tier >= 4:
		s.ladder(35, 32, DECK_FEET, UPPER_Y0 + 2, int(ids["ladder"]))
	if tier >= 5:
		s.ladder(29, 32, HOLD_Y0 + 1, DECK_FEET, int(ids["ladder"]))


static func _lights(s: SpcStamp, ids: Dictionary, tier: int) -> void:
	var strips: Array[Vector3i] = [
		Vector3i(32, MAIN_Y1 - 1, 32), Vector3i(40, MAIN_Y1 - 1, 32),
		Vector3i(46, MAIN_Y1 - 1, 32), Vector3i(32, MAIN_Y1 - 1, 40),
	]
	if tier >= 2:
		strips.append(Vector3i(22, MAIN_Y1 - 1, 32))
	if tier >= 3:
		strips.append(Vector3i(32, MAIN_Y1 - 1, 22))
	if tier >= 4:
		strips.append(Vector3i(32, UPPER_Y1 - 1, 32))
	if tier >= 5:
		strips.append(Vector3i(32, HOLD_Y1 - 1, 32))
	for p: Vector3i in strips:
		s.set_block(p, int(ids["light"]))


## Doorway plus its frame. `axis` 0 punches through an X-facing wall (the gap
## runs along Z), 1 punches through a Z-facing wall.
static func _door(s: SpcStamp, ids: Dictionary, foot: Vector3i, axis: int) -> void:
	var frame := int(ids["door"])
	for dy in range(-1, 5):
		for d in range(-2, 3):
			var p := foot + Vector3i(0, dy, 0)
			if axis == 0:
				p.z += d
			else:
				p.x += d
			var edge := absi(d) == 2 or dy == -1 or dy == 4
			s.set_block(p, frame if edge else Const.AIR)


static func _root(s: SpcStamp, ids: Dictionary, tier: int) -> void:
	s.set_block(ROOT_MARKER, int(ids["marker"]))
	s.tile(ROOT_MARKER, {"kind": "ship_root", "tier": tier})
