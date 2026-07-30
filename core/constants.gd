## Global compile-time constants and the perspective lookup tables.
## Pure static class — never instantiated, never autoloaded. Use `Const.X`.
class_name Const
extends RefCounted

# ---------------------------------------------------------------- world scale
const CHUNK_BITS := 4
const CHUNK_SIZE := 16
const CHUNK_MASK := 15
const CHUNK_AREA := 256
const CHUNK_VOL := 4096

## Vertical extent of a planet, in blocks (16 chunks tall).
const WORLD_HEIGHT := 256
const WORLD_HEIGHT_CHUNKS := 16

## Planets are finite boxes that wrap horizontally on both X and Z.
const PLANET_SIZE_DEFAULT := 512

# ------------------------------------------------------------------- voxel id
const AIR := 0

# --------------------------------------------------------------- perspectives
## Four side-on viewing planes. The camera always looks horizontally; +Y is up.
## FORWARD = direction the camera looks. RIGHT = world axis that maps to
## screen-right. DEPTH_AXIS = index (0=X, 2=Z) of the axis pointing "into" the
## screen; that coordinate is the player's frozen "layer".
const VIEW_COUNT := 4
const VIEW_FORWARD := [
	Vector3i(0, 0, -1),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(1, 0, 0),
]
const VIEW_RIGHT := [
	Vector3i(1, 0, 0),
	Vector3i(0, 0, -1),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
]
## 0 -> depth runs along Z, 1 -> along X, 2 -> along Z, 3 -> along X.
const VIEW_DEPTH_AXIS := [2, 0, 2, 0]
## Sign such that (depth increasing) == (further from camera).
const VIEW_DEPTH_SIGN := [-1, -1, 1, 1]
const VIEW_NAMES := ["North", "West", "South", "East"]

## How many layers behind the play layer stay visible (tinted), and how many
## layers in front of it are dissolved so they never occlude the player.
const SLAB_BEHIND := 5
const SLAB_FRONT := 0

# ----------------------------------------------------------------- block faces
const FACE_PX := 0
const FACE_NX := 1
const FACE_PY := 2
const FACE_NY := 3
const FACE_PZ := 4
const FACE_NZ := 5
const FACE_NORMALS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

# ---------------------------------------------------------------- render layers
const RL_WORLD := 1
const RL_ENTITIES := 2
const RL_EFFECTS := 4

# ------------------------------------------------------------------- gameplay
const GRAVITY := 34.0
const TERMINAL_VELOCITY := 48.0
const TICKS_PER_DAY := 28800  ## 8 real minutes at 60 fps
const MAX_LIGHT := 15
const MAX_LIQUID := 8

## Damage / element types shared by combat, monsters and status effects.
const ELEM_PHYSICAL := "physical"
const ELEM_FIRE := "fire"
const ELEM_ICE := "ice"
const ELEM_ELECTRIC := "electric"
const ELEM_POISON := "poison"
const ELEM_COSMIC := "cosmic"
const ELEMENTS := [ELEM_PHYSICAL, ELEM_FIRE, ELEM_ICE, ELEM_ELECTRIC, ELEM_POISON, ELEM_COSMIC]

## Rarity tiers used by items, weapons and loot tables.
const RARITY_COMMON := 0
const RARITY_UNCOMMON := 1
const RARITY_RARE := 2
const RARITY_LEGENDARY := 3
const RARITY_ESSENTIAL := 4
const RARITY_COLORS := [
	Color(0.85, 0.85, 0.85), Color(0.4, 0.9, 0.4),
	Color(0.4, 0.6, 1.0), Color(0.9, 0.5, 1.0), Color(1.0, 0.8, 0.3),
]
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Legendary", "Essential"]


# ---------------------------------------------------------------- helper maths
static func chunk_of(p: Vector3i) -> Vector3i:
	return Vector3i(p.x >> CHUNK_BITS, p.y >> CHUNK_BITS, p.z >> CHUNK_BITS)


static func local_of(p: Vector3i) -> Vector3i:
	return Vector3i(p.x & CHUNK_MASK, p.y & CHUNK_MASK, p.z & CHUNK_MASK)


static func local_index(lx: int, ly: int, lz: int) -> int:
	return (ly << 8) | (lz << 4) | lx


static func floor_v(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))


## Component of `v` along the depth axis of `view`.
static func depth_of(v: Vector3, view: int) -> float:
	return v.x if VIEW_DEPTH_AXIS[view] == 0 else v.z


## Component of `v` along the screen-right axis of `view`.
static func lateral_of(v: Vector3, view: int) -> float:
	var r: Vector3i = VIEW_RIGHT[view]
	return v.x * r.x + v.z * r.z


## Rebuild a world vector from screen-space (lateral, up) plus a depth value.
static func from_plane(lateral: float, up: float, depth: float, view: int) -> Vector3:
	var r: Vector3i = VIEW_RIGHT[view]
	var out := Vector3(0.0, up, 0.0)
	out.x = lateral * r.x
	out.z = lateral * r.z
	if VIEW_DEPTH_AXIS[view] == 0:
		out.x = depth
	else:
		out.z = depth
	return out
