## Finds a landing site a player can actually stand up in.
##
## The hard requirement is peculiar to this game: the camera can be locked to
## any of four horizontal planes, and the player can only walk *laterally*
## within the current one. A ledge that is generous along X but one voxel wide
## along Z is a perfectly good spawn in two views and a prison in the other
## two. So the test is run on **both** horizontal axes, symmetrically:
##
## * flat ground for `RUN` blocks in +X, -X, +Z and -Z;
## * dry land, comfortably above sea level;
## * no hazardous biome (lava seas, airless moons) if anything better exists;
## * clear headroom, and no liquid in the standing column.
##
## Everything is answered from the generator's analytic heightfield, so it works
## before a single chunk has been built.
class_name SpawnFinder
extends RefCounted

## How far the ground must stay walkable on each of the four lateral runs.
const RUN := 6
## Largest step the player can be expected to cross while walking out.
const MAX_STEP := 2
## Candidate grid spacing, in blocks.
const STRIDE := 12
## Rings of the search spiral to try before settling for the best so far.
const MAX_RINGS := 20
## Score at which a site is good enough to stop looking.
const GOOD_ENOUGH := 110.0

static var _gen_cache: Node = null
static var _world_cache: Node = null


## Best spawn position for the current planet, as a world-space *feet*
## position. Falls back to the middle of the map at surface height.
static func find_spawn(size_x: int, size_z: int) -> Vector3:
	var cx := size_x >> 1
	var cz := size_z >> 1
	var sea := _sea_level()
	var best_x := cx
	var best_z := cz
	var best_score := -INF
	for ring in MAX_RINGS:
		for step in maxi(1, ring * 8):
			var p := _ring_point(cx, cz, ring, step, size_x, size_z)
			var score := _score(p.x, p.y, sea)
			if score > best_score:
				best_score = score
				best_x = p.x
				best_z = p.y
			if score >= GOOD_ENOUGH:
				return Vector3(float(best_x) + 0.5, float(_height(best_x, best_z)) + 1.0, float(best_z) + 0.5)
	return Vector3(float(best_x) + 0.5, float(_height(best_x, best_z)) + 1.0, float(best_z) + 0.5)


## Point `step` of a square ring `ring` strides out from the centre.
static func _ring_point(cx: int, cz: int, ring: int, step: int, size_x: int, size_z: int) -> Vector2i:
	if ring == 0:
		return Vector2i(cx, cz)
	var side := ring * 2
	var d := step % maxi(side * 4, 1)
	var ox := 0
	var oz := 0
	if d < side:
		ox = -ring + d
		oz = -ring
	elif d < side * 2:
		ox = ring
		oz = -ring + (d - side)
	elif d < side * 3:
		ox = ring - (d - side * 2)
		oz = ring
	else:
		ox = -ring
		oz = ring - (d - side * 3)
	return Vector2i(posmod(cx + ox * STRIDE, size_x), posmod(cz + oz * STRIDE, size_z))


## Negative rejects the site; ~110+ is a textbook meadow ledge.
static func _score(x: int, z: int, sea: int) -> float:
	var h := _height(x, z)
	if h <= sea + 2:
		return -1000.0                      # underwater or on the tideline
	if h > Const.WORLD_HEIGHT - 40:
		return -500.0                       # a peak with nothing to build on
	var score := 100.0
	# Flatness along both horizontal axes — this is the four-view guarantee.
	for axis in 2:
		for sign_i in 2:
			var dir := 1 if sign_i == 0 else -1
			var prev := h
			for d in range(1, RUN + 1):
				var hh := _height(
					x + (d * dir if axis == 0 else 0),
					z + (0 if axis == 0 else d * dir))
				var st := absi(hh - prev)
				if st > MAX_STEP:
					return -100.0 + float(RUN - d)
				score -= float(st) * 3.0
				prev = hh
				if hh <= sea:
					score -= 12.0           # walking out leads straight into water
	var b := _biome(x, z)
	if b != null:
		if b.key == &"ocean":
			return -200.0
		match b.hazard:
			Biome.HAZARD_NONE:
				score += 20.0
			Biome.HAZARD_COLD, Biome.HAZARD_DARK:
				score -= 10.0
			Biome.HAZARD_HEAT, Biome.HAZARD_TOXIC, Biome.HAZARD_RADIATION:
				score -= 30.0
			Biome.HAZARD_AIRLESS:
				score -= 15.0
		if not b.trees.is_empty():
			score += 8.0                    # somewhere with wood to start from
	# If chunks happen to be loaded already, insist the standing space is clear.
	var w := _world()
	if w != null and bool(w.get(&"ready_flag")):
		for dy in range(1, 4):
			var id := int(w.call(&"get_block", Vector3i(x, h + dy, z)))
			if id != Const.AIR and Blocks.is_solid(id):
				return -50.0
			if Blocks.is_liquid(id):
				return -80.0
	return score


# ---------------------------------------------------------------------------
# The generator and the world are reached through the scene tree rather than by
# their autoload names: `PlanetGen` is what *calls* this file, and a
# compile-time reference back to it would be a cyclic dependency.
static func _node(path: NodePath) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(path)


static func _gen() -> Node:
	if _gen_cache == null or not is_instance_valid(_gen_cache):
		_gen_cache = _node(^"/root/PlanetGen")
	return _gen_cache


static func _world() -> Node:
	if _world_cache == null or not is_instance_valid(_world_cache):
		_world_cache = _node(^"/root/World")
	return _world_cache


static func _height(x: int, z: int) -> int:
	var g := _gen()
	if g != null and g.has_method(&"height_at"):
		return int(g.call(&"height_at", x, z))
	return Const.WORLD_HEIGHT / 2


static func _biome(x: int, z: int) -> Biome:
	var g := _gen()
	if g != null and g.has_method(&"biome_of"):
		return g.call(&"biome_of", x, z) as Biome
	return null


static func _sea_level() -> int:
	var g := _gen()
	if g != null and g.get(&"sea_level") != null:
		return int(g.get(&"sea_level"))
	return 96
