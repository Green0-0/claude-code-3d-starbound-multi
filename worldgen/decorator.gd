## Pass 5 and 6: liquids, then everything that grows on or scatters over the
## surface. Trees are built procedurally per species — trunk, branching,
## canopy, hanging vines — never stamped from a template.
##
## Two rules keep this deterministic across chunk borders:
##
## 1. Nothing reads the chunk it is writing into to decide *whether* to place a
##    feature; the decision comes from `hash(cell)` and the cached heightfield.
## 2. Features are generated from a padded ring of cells around the chunk and
##    clipped to it, so a tree rooted in the neighbouring chunk still drops its
##    canopy here, whichever chunk is built first.
class_name WorldDecorator
extends RefCounted

const SALT_TREE := 0x77EE
const SALT_SCATTER := 0x5CA7
const SALT_PLANT := 0x91A7
const TREE_CELL := 4
const SCATTER_CELL := 8
## Padding, in columns, around the chunk that may still reach into it.
const PAD := 8
## Tallest feature we ever build — how far below the chunk a trunk may start.
const MAX_FEATURE_H := 34
## The four horizontal neighbours, as parallel constant arrays (indexing an
## inline array literal would give GDScript a Variant it cannot infer).
const DIR4_X: Array[int] = [1, -1, 0, 0]
const DIR4_Z: Array[int] = [0, 0, 1, -1]

var noise: NoiseBank
var shaper: TerrainShaper
var sea_level := 96
var lava_level := 26
var sea_liquid: StringName = &"water"
## Global flora multiplier from the planet meta; 0 means a lifeless surface.
var vegetation := 1.0

var _id_water := 0
var _id_lava := 0
var _id_sea := 0
var _id_vine := 0
var _id_snow := 0
var _id_ash := 0
var _id_boulder := 0
var _id_bones := 0

## species key -> {kind, log, leaf, min_h, max_h, vines}
var _species: Dictionary = {}

## The chunk's voxel array while a pass is running. Kept as a member on purpose:
## GDScript's packed arrays are copy-on-write, so handing one to `_put()` would
## clone 16 KB per voxel. Writing through a member keeps every write in place.
var _buf: PackedInt32Array = PackedInt32Array()


func configure(p_noise: NoiseBank, p_shaper: TerrainShaper, meta: Dictionary, profile: Dictionary) -> void:
	noise = p_noise
	shaper = p_shaper
	sea_level = p_shaper.sea_level
	lava_level = clampi(int(meta.get("lava_level", 26)), 4, 80)
	sea_liquid = StringName(meta.get("liquid", profile.get("liquid", &"water")))
	# `vegetation` (0..1) is the planet's global flora multiplier.
	vegetation = clampf(float(meta.get("vegetation", 1.0)), 0.0, 2.0)
	_id_water = _opt([&"water"])
	_id_lava = _opt([&"lava"])
	_id_sea = _opt([sea_liquid, &"water"])
	_id_vine = _opt([&"vine", &"glow_vine", &"vine_rope"])
	_id_snow = _opt([&"snow_cover", &"snow"])
	_id_ash = _opt([&"cinder", &"ash", &"gravel"])
	_id_boulder = _opt([&"mossy_stone", &"cobblestone", &"stone"])
	_id_bones = _opt([&"bone_block", &"floran_bone", &"gravel"])
	_build_species()


## First registered name, or `Const.AIR` when the block agent has none of them.
## Decoration silently skips features whose blocks do not exist yet — it must
## never substitute stone for a flower.
func _opt(names: Array) -> int:
	for n in names:
		var sn := StringName(n)
		if Blocks.has(sn):
			return Blocks.id(sn)
	return Const.AIR


func _build_species() -> void:
	_species = {}
	_add_species(&"oak", &"broadleaf", [&"oak_log", &"wood_log"], [&"oak_leaves", &"leaves"], 5, 8)
	_add_species(&"birch", &"broadleaf", [&"birch_log", &"wood_log"], [&"birch_leaves", &"leaves"], 6, 10)
	_add_species(&"cherry", &"broadleaf", [&"cherry_log", &"oak_log", &"wood_log"], [&"cherry_leaves", &"pink_leaves", &"leaves"], 5, 8)
	_add_species(&"gnarled_oak", &"broadleaf", [&"dark_wood", &"oak_log", &"wood_log"], [&"leaves"], 6, 10, true)
	_add_species(&"acacia", &"broadleaf", [&"acacia_log", &"wood_log"], [&"acacia_leaves", &"leaves"], 5, 7)
	_add_species(&"pine", &"conifer", [&"pine_log", &"wood_log"], [&"pine_leaves", &"leaves"], 8, 14)
	_add_species(&"snow_pine", &"conifer", [&"pine_log", &"wood_log"], [&"pine_leaves", &"leaves"], 7, 13)
	_add_species(&"frost_pine", &"conifer", [&"frost_log", &"pine_log", &"wood_log"], [&"frost_leaves", &"pine_leaves", &"leaves"], 9, 16)
	_add_species(&"palm", &"palm", [&"palm_log", &"wood_log"], [&"palm_leaves", &"leaves"], 7, 11)
	_add_species(&"jungle_palm", &"palm", [&"palm_log", &"jungle_log", &"wood_log"], [&"palm_leaves", &"jungle_leaves", &"leaves"], 8, 13)
	_add_species(&"jungle_giant", &"giant", [&"jungle_log", &"wood_log"], [&"jungle_leaves", &"leaves"], 14, 24, true)
	_add_species(&"baobab", &"giant", [&"acacia_log", &"wood_log"], [&"acacia_leaves", &"leaves"], 10, 16)
	_add_species(&"vine_tree", &"broadleaf", [&"jungle_log", &"wood_log"], [&"jungle_leaves", &"leaves"], 7, 12, true)
	_add_species(&"willow", &"willow", [&"willow_log", &"wood_log"], [&"willow_leaves", &"leaves"], 7, 11, true)
	_add_species(&"swamp_cypress", &"willow", [&"cypress_log", &"willow_log", &"wood_log"], [&"cypress_leaves", &"willow_leaves", &"leaves"], 8, 13, true)
	_add_species(&"glow_tree", &"broadleaf", [&"glow_log", &"wood_log"], [&"glow_leaves", &"glowing_leaves", &"leaves"], 6, 10)
	_add_species(&"lantern_tree", &"willow", [&"glow_log", &"wood_log"], [&"glow_leaves", &"leaves"], 7, 12, true)
	_add_species(&"alien_bulb", &"alien", [&"alien_log", &"wood_log"], [&"alien_leaves", &"leaves"], 5, 9)
	_add_species(&"tentacle_tree", &"alien", [&"flesh_log", &"alien_log", &"wood_log"], [&"flesh_leaves", &"alien_leaves", &"leaves"], 6, 11, true)
	_add_species(&"toxic_tree", &"alien", [&"toxic_log", &"alien_log", &"wood_log"], [&"toxic_leaves", &"alien_leaves", &"leaves"], 5, 9)
	_add_species(&"ash_tree", &"dead", [&"charred_log", &"ash_log", &"wood_log"], [&"ash_leaves", &"leaves"], 5, 9)
	_add_species(&"burnt_tree", &"dead", [&"charred_log", &"ash_log", &"wood_log"], [], 4, 8)
	_add_species(&"dead_tree", &"dead", [&"dead_log", &"charred_log", &"wood_log"], [], 4, 8)
	_add_species(&"bone_tree", &"dead", [&"bone_block", &"floran_bone", &"dead_log"], [], 5, 10)
	_add_species(&"giant_mushroom", &"mushroom", [&"mushroom_stem", &"wood_log"], [&"mushroom_cap", &"leaves"], 4, 9)
	_add_species(&"glow_mushroom_tree", &"mushroom", [&"glow_mushroom_stem", &"mushroom_stem", &"wood_log"], [&"glow_mushroom_cap", &"mushroom_cap", &"leaves"], 5, 11)
	_add_species(&"cactus_tall", &"cactus", [&"cactus"], [], 3, 6)
	_add_species(&"crystal_spire", &"crystal", [&"crystal_block", &"crystal_blue", &"ice"], [], 4, 11)


func _add_species(key: StringName, kind: StringName, logs: Array, leaves: Array,
		min_h: int, max_h: int, vines: bool = false) -> void:
	_species[key] = {
		"kind": kind,
		"log": _opt(logs),
		"leaf": _opt(leaves),
		"min_h": min_h, "max_h": max_h, "vines": vines,
	}


# =================================================================== liquids
## Fill oceans, rivers and the deep lava sea. Only air *above* the heightfield
## is flooded, so caves stay dry and the seabed does not drain into them.
## Runs after `decorate()`: coral and kelp are already standing there, and the
## water simply flows around them.
func fill_liquids(chunk: Chunk) -> void:
	var o := chunk.origin()
	if o.y > sea_level and o.y > lava_level:
		return
	_buf = chunk.blocks
	var fills: Array[int] = []
	for lz in Const.CHUNK_SIZE:
		var wz := o.z + lz
		for lx in Const.CHUNK_SIZE:
			var wx := o.x + lx
			var h := shaper.height_at(wx, wz)
			var b := BiomeTable.by_index(shaper.biome_index_at(wx, wz))
			var surf_liquid: int = int(b.ids()["liquid"])
			if surf_liquid == Const.AIR:
				surf_liquid = _id_sea
			for ly in Const.CHUNK_SIZE:
				var y := o.y + ly
				var i := (ly << 8) | (lz << 4) | lx
				if _buf[i] != Const.AIR:
					continue
				if y <= sea_level and y > h:
					if surf_liquid != Const.AIR:
						_buf[i] = surf_liquid
						fills.append(i)
				elif y <= lava_level and y < h - 4 and _id_lava != Const.AIR:
					# The lava sea at the bottom of the cave system.
					_buf[i] = _id_lava
					fills.append(i)
	chunk.blocks = _buf
	_buf = PackedInt32Array()
	for i: int in fills:
		chunk.set_liquid(i, Const.MAX_LIQUID)


# ================================================================ decoration
## Surface pass: cover, plants, trees, boulders, logs, coral, spires.
func decorate(chunk: Chunk) -> void:
	var o := chunk.origin()
	var min_h := Const.WORLD_HEIGHT
	var max_h := 0
	for lz in range(-PAD, Const.CHUNK_SIZE + PAD):
		for lx in range(-PAD, Const.CHUNK_SIZE + PAD):
			var h := shaper.height_at(o.x + lx, o.z + lz)
			min_h = mini(min_h, h)
			max_h = maxi(max_h, h)
	if o.y > max_h + MAX_FEATURE_H or o.y + Const.CHUNK_SIZE < min_h:
		return
	_buf = chunk.blocks
	# Features first, ground cover second: the cover pass only fills voxels that
	# are still air, so trunks and boulders are never buried under snow.
	_features(o)
	_ground_layer(o)
	chunk.blocks = _buf
	_buf = PackedInt32Array()


## Per-column work: snow/ash blankets, grass tufts, flowers, seabed weeds.
func _ground_layer(o: Vector3i) -> void:
	for lz in Const.CHUNK_SIZE:
		var wz := o.z + lz
		for lx in Const.CHUNK_SIZE:
			var wx := o.x + lx
			var h := shaper.height_at(wx, wz)
			var ly := h + 1 - o.y
			if ly < 0 or ly > 15:
				continue
			var i := (ly << 8) | (lz << 4) | lx
			if _buf[i] != Const.AIR:
				continue
			var b := BiomeTable.by_index(shaper.biome_index_at(wx, wz))
			var ids: Dictionary = b.ids()
			var r := NoiseBank.rand01(wx, h, wz, SALT_PLANT)
			if h < sea_level:
				# Underwater: kelp and sea grass, planted into the water column.
				var weeds: PackedInt32Array = ids["plants"]
				if not weeds.is_empty() and r < b.plant_density * 0.5 * vegetation:
					var pick := absi(NoiseBank.hash_i(wx, h, wz, SALT_PLANT + 1)) % weeds.size()
					var tall := 1 + absi(NoiseBank.hash_i(wx, h, wz, SALT_PLANT + 2)) % 3
					for k in tall:
						_put(o, wx, h + 1 + k, wz, weeds[pick], false)
				continue
			var plants: PackedInt32Array = ids["plants"]
			var flowers: PackedInt32Array = ids["flowers"]
			if not flowers.is_empty() and r < b.flower_density * vegetation:
				_buf[i] = flowers[absi(NoiseBank.hash_i(wx, h, wz, SALT_PLANT + 3)) % flowers.size()]
			elif not plants.is_empty() and r < (b.flower_density + b.plant_density) * vegetation:
				_buf[i] = plants[absi(NoiseBank.hash_i(wx, h, wz, SALT_PLANT + 4)) % plants.size()]
			elif b.cover != &"":
				var cov := _id_snow if b.cover == &"snow" else _id_ash
				if cov != Const.AIR and NoiseBank.rand01(wx, h, wz, SALT_PLANT + 5) < 0.85:
					_buf[i] = cov
	return


## Cell-anchored features: one tree candidate per 4x4 cell, one scatter
## candidate per 8x8 cell, both taken from a padded ring around the chunk.
## Cell sizes are powers of two so the grid tiles the wrapping planet exactly.
func _features(o: Vector3i) -> void:
	var tx0 := NoiseBank.fdiv(o.x - PAD, TREE_CELL)
	var tx1 := NoiseBank.fdiv(o.x + Const.CHUNK_SIZE + PAD, TREE_CELL)
	var tz0 := NoiseBank.fdiv(o.z - PAD, TREE_CELL)
	var tz1 := NoiseBank.fdiv(o.z + Const.CHUNK_SIZE + PAD, TREE_CELL)
	for cz in range(tz0, tz1 + 1):
		for cx in range(tx0, tx1 + 1):
			_tree_cell(o, cx, cz)
	var sx0 := NoiseBank.fdiv(o.x - PAD, SCATTER_CELL)
	var sx1 := NoiseBank.fdiv(o.x + Const.CHUNK_SIZE + PAD, SCATTER_CELL)
	var sz0 := NoiseBank.fdiv(o.z - PAD, SCATTER_CELL)
	var sz1 := NoiseBank.fdiv(o.z + Const.CHUNK_SIZE + PAD, SCATTER_CELL)
	for cz in range(sz0, sz1 + 1):
		for cx in range(sx0, sx1 + 1):
			_scatter_cell(o, cx, cz)
	return


func _tree_cell(o: Vector3i, cx: int, cz: int) -> void:
	var h := _cell_hash(cx * TREE_CELL, cz * TREE_CELL, SALT_TREE)
	var wx := cx * TREE_CELL + absi(h >> 3) % TREE_CELL
	var wz := cz * TREE_CELL + absi(h >> 9) % TREE_CELL
	var b := BiomeTable.by_index(shaper.biome_index_at(wx, wz))
	if b.trees.is_empty() or b.tree_density <= 0.0:
		return
	if float(absi(h >> 15) % 1000) * 0.001 > b.tree_density * vegetation:
		return
	var ground := shaper.height_at(wx, wz)
	if ground < sea_level or ground > Const.WORLD_HEIGHT - 40:
		return
	if shaper.slope_at(wx, wz) > 3.0:
		return        # trees do not grow on cliff faces
	var species: StringName = b.trees[absi(h >> 21) % b.trees.size()]
	_build_tree(o, species, wx, ground + 1, wz, h)
	return


func _scatter_cell(o: Vector3i, cx: int, cz: int) -> void:
	var h := _cell_hash(cx * SCATTER_CELL, cz * SCATTER_CELL, SALT_SCATTER)
	var wx := cx * SCATTER_CELL + absi(h >> 3) % SCATTER_CELL
	var wz := cz * SCATTER_CELL + absi(h >> 9) % SCATTER_CELL
	var b := BiomeTable.by_index(shaper.biome_index_at(wx, wz))
	if b.scatter.is_empty():
		return
	var ground := shaper.height_at(wx, wz)
	var roll := float(absi(h >> 15) % 1000) * 0.001
	var acc := 0.0
	for kind in b.scatter:
		acc += float(b.scatter[kind])
		if roll >= acc:
			continue
		match StringName(kind):
			&"boulder":
				if ground >= sea_level:
					_build_boulder(o, wx, ground, wz, h, b)
					return
			&"log":
				if ground >= sea_level:
					_build_fallen_log(o, wx, ground + 1, wz, h, b)
					return
			&"mushroom", &"cactus", &"bones":
				if ground >= sea_level:
					_build_clump(o, wx, ground + 1, wz, h, StringName(kind), b)
					return
			&"coral":
				if ground < sea_level - 2:
					_build_coral(o, wx, ground + 1, wz, h)
					return
			&"crystal":
				_build_crystal(o, wx, ground + 1, wz, h)
				return
			&"vine":
				pass   # vines are hung by the tree builders themselves
		return
	return


# ====================================================================== trees
## Dispatch to the per-species builder. `base` is the first air voxel above the
## ground; `h` is the cell hash, used to seed the feature's own RNG stream.
func _build_tree(o: Vector3i, species: StringName,
		x: int, base: int, z: int, h: int) -> void:
	var s: Dictionary = _species.get(species, {})
	if s.is_empty() or int(s["log"]) == Const.AIR:
		return
	var rng := NoiseBank.rng_at(x, base, z, SALT_TREE + 11)
	var height := int(s["min_h"]) + rng.randi_range(0, maxi(0, int(s["max_h"]) - int(s["min_h"])))
	var log_id: int = int(s["log"])
	var leaf_id: int = int(s["leaf"])
	var vines: bool = bool(s["vines"]) and _id_vine != Const.AIR
	match StringName(s["kind"]):
		&"broadleaf":
			_tree_broadleaf(o, x, base, z, height, log_id, leaf_id, vines, rng)
			return
		&"conifer":
			_tree_conifer(o, x, base, z, height, log_id, leaf_id, rng)
			return
		&"palm":
			_tree_palm(o, x, base, z, height, log_id, leaf_id, rng)
			return
		&"giant":
			_tree_giant(o, x, base, z, height, log_id, leaf_id, vines, rng)
			return
		&"willow":
			_tree_willow(o, x, base, z, height, log_id, leaf_id, rng)
			return
		&"alien":
			_tree_alien(o, x, base, z, height, log_id, leaf_id, vines, rng)
			return
		&"dead":
			_tree_dead(o, x, base, z, height, log_id, leaf_id, rng)
			return
		&"mushroom":
			_tree_mushroom(o, x, base, z, height, log_id, leaf_id, rng)
			return
		&"cactus":
			_tree_cactus(o, x, base, z, height, log_id, rng)
			return
		&"crystal":
			_tree_crystal(o, x, base, z, height, log_id, rng)
			return
	return


## Classic branching tree: straight trunk, two to four diagonal branches, a
## rounded canopy at the crown and a smaller one at each branch tip.
func _tree_broadleaf(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, vines: bool, rng: RandomNumberGenerator) -> void:
	for i in height:
		_put(o, x, base + i, z, log_id, true)
	var top := base + height - 1
	_leaf_ball(o, x, top, z, 2 + rng.randi_range(0, 1), leaf_id, vines, rng)
	var branches := 2 + rng.randi_range(0, 2)
	for bi in branches:
		var ang := rng.randf() * TAU
		var len_b := 2 + rng.randi_range(0, 2)
		var by := top - 1 - rng.randi_range(0, maxi(1, height / 3))
		var bx := x
		var bz := z
		for k in len_b:
			bx += signi(int(round(cos(ang) * 1.6)))
			bz += signi(int(round(sin(ang) * 1.6)))
			_put(o, bx, by + (1 if k % 2 == 1 else 0), bz, log_id, true)
			by += 1 if k % 2 == 1 else 0
		_leaf_ball(o, bx, by + 1, bz, 2, leaf_id, vines, rng)
	return


## Layered rings that shrink toward the tip — a fir silhouette that stays
## symmetric from every viewing plane.
func _tree_conifer(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, rng: RandomNumberGenerator) -> void:
	for i in height:
		_put(o, x, base + i, z, log_id, true)
	if leaf_id == Const.AIR:
		return
	var start := base + 2 + rng.randi_range(0, 1)
	var y := start
	var r := 3
	while y <= base + height:
		var rr := r if y < base + height - 2 else 1
		for dz in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if dx * dx + dz * dz > rr * rr + 1:
					continue
				_put(o, x + dx, y, z + dz, leaf_id, false)
		y += 2
		r = maxi(1, r - 1)
		if r == 1 and y < base + height - 3:
			r = 2
	_put(o, x, base + height + 1, z, leaf_id, false)
	return


## Curved trunk with fronds radiating from the crown.
func _tree_palm(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, rng: RandomNumberGenerator) -> void:
	var lean_x := rng.randi_range(-1, 1)
	var lean_z := rng.randi_range(-1, 1)
	var tx := x
	var tz := z
	for i in height:
		if i > height / 2 and i % 3 == 0:
			tx += lean_x
			tz += lean_z
		_put(o, tx, base + i, tz, log_id, true)
	if leaf_id == Const.AIR:
		return
	var top := base + height
	_put(o, tx, top, tz, leaf_id, false)
	for dir in 4:
		var dx: int = DIR4_X[dir]
		var dz: int = DIR4_Z[dir]
		for k in range(1, 4):
			var yy := top - (0 if k < 3 else 1)
			_put(o, tx + dx * k, yy, tz + dz * k, leaf_id, false)
			if k == 2:
				_put(o, tx + dx * k + dz, yy, tz + dz * k + dx, leaf_id, false)
				_put(o, tx + dx * k - dz, yy, tz + dz * k - dx, leaf_id, false)
	return


## Two-by-two trunk, buttress roots, a wide crown and curtains of vines. Tall
## enough to be a landmark and to bridge to floating islands.
func _tree_giant(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, vines: bool, rng: RandomNumberGenerator) -> void:
	for i in height:
		for dz in 2:
			for dx in 2:
				_put(o, x + dx, base + i, z + dz, log_id, true)
	# Buttress roots.
	for dir in 4:
		var dx: int = DIR4_X[dir]
		var dz: int = DIR4_Z[dir]
		_put(o, x + (1 if dx > 0 else 0) + dx, base, z + (1 if dz > 0 else 0), log_id, true)
		_put(o, x + (1 if dx > 0 else 0), base, z + (1 if dz > 0 else 0) + dz, log_id, true)
	var top := base + height - 1
	if leaf_id != Const.AIR:
		for layer in 3:
			var r := 5 - layer
			var y := top + layer - 1
			for dz in range(-r, r + 2):
				for dx in range(-r, r + 2):
					var cx := dx if dx <= 0 else dx - 1
					var cz := dz if dz <= 0 else dz - 1
					if cx * cx + cz * cz > r * r + 1:
						continue
					_put(o, x + dx, y, z + dz, leaf_id, false)
		# Big lateral limbs so the crown reads from the side too.
		for bi in 4:
			var ang := TAU * float(bi) / 4.0 + rng.randf() * 0.5
			var bx := x + int(round(cos(ang) * 4.0))
			var bz := z + int(round(sin(ang) * 4.0))
			var by := top - 2 - rng.randi_range(0, 3)
			_line(o, x, by, z, bx, by + 1, bz, log_id)
			_leaf_ball(o, bx, by + 2, bz, 2, leaf_id, vines, rng)
	if vines:
		for vi in 14:
			var vx := x + rng.randi_range(-5, 6)
			var vz := z + rng.randi_range(-5, 6)
			var vl := 2 + rng.randi_range(0, 7)
			for k in vl:
				_put(o, vx, top - 1 - k, vz, _id_vine, false)
	return


## Broadleaf crown with weeping fronds down the outside.
func _tree_willow(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, rng: RandomNumberGenerator) -> void:
	_tree_broadleaf(o, x, base, z, height, log_id, leaf_id, false, rng)
	if leaf_id == Const.AIR:
		return
	var top := base + height - 1
	for i in 10:
		var ang := TAU * float(i) / 10.0
		var dx := int(round(cos(ang) * 3.0))
		var dz := int(round(sin(ang) * 3.0))
		var drop := 2 + rng.randi_range(0, 4)
		for k in drop:
			var id := _id_vine if (_id_vine != Const.AIR and k > 1) else leaf_id
			_put(o, x + dx, top - k, z + dz, id, false)
	return


## A stalk with a bulb of foliage and drooping tendrils — deliberately
## asymmetric, so alien planets do not read like Earth ones.
func _tree_alien(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, vines: bool, rng: RandomNumberGenerator) -> void:
	var tx := x
	var tz := z
	for i in height:
		if i > 1 and i % 3 == 0:
			tx += rng.randi_range(-1, 1)
			tz += rng.randi_range(-1, 1)
		_put(o, tx, base + i, tz, log_id, true)
	var top := base + height
	if leaf_id == Const.AIR:
		return
	var r := 2 + rng.randi_range(0, 1)
	for dy in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy + dz * dz > r * r + 1:
					continue
				_put(o, tx + dx, top + dy, tz + dz, leaf_id, false)
	for ti in 5:
		var ang := TAU * float(ti) / 5.0
		var ex := tx + int(round(cos(ang) * float(r)))
		var ez := tz + int(round(sin(ang) * float(r)))
		var drop := 2 + rng.randi_range(0, 4)
		for k in drop:
			var id := _id_vine if vines else leaf_id
			_put(o, ex, top - r - k, ez, id, false)
	return


## Bare trunk and a few crooked limbs. No canopy — these are silhouettes.
func _tree_dead(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, rng: RandomNumberGenerator) -> void:
	for i in height:
		_put(o, x, base + i, z, log_id, true)
	var limbs := 2 + rng.randi_range(0, 3)
	for li in limbs:
		var ang := rng.randf() * TAU
		var ly := base + height - 1 - rng.randi_range(0, maxi(1, height / 2))
		var lx := x + signi(int(round(cos(ang) * 2.0)))
		var lz := z + signi(int(round(sin(ang) * 2.0)))
		_put(o, lx, ly, lz, log_id, false)
		_put(o, lx, ly + 1, lz, log_id, false)
		if leaf_id != Const.AIR and rng.randf() < 0.4:
			_put(o, lx, ly + 2, lz, leaf_id, false)
	return


## Stem plus a domed cap, one voxel thick — the cap's underside is a ceiling
## you can shelter under, which reads well in side view.
func _tree_mushroom(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, leaf_id: int, rng: RandomNumberGenerator) -> void:
	for i in height:
		_put(o, x, base + i, z, log_id, true)
	if leaf_id == Const.AIR:
		return
	var top := base + height
	var r := 2 + rng.randi_range(0, 2)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d2 := dx * dx + dz * dz
			if d2 > r * r + 1:
				continue
			_put(o, x + dx, top, z + dz, leaf_id, false)
			if d2 > (r - 1) * (r - 1):
				_put(o, x + dx, top - 1, z + dz, leaf_id, false)
	_put(o, x, top + 1, z, leaf_id, false)
	return


func _tree_cactus(o: Vector3i, x: int, base: int, z: int,
		height: int, log_id: int, rng: RandomNumberGenerator) -> void:
	for i in height:
		_put(o, x, base + i, z, log_id, true)
	var arms := rng.randi_range(0, 2)
	for a in arms:
		var side := rng.randi_range(0, 3)
		var dx: int = DIR4_X[side]
		var dz: int = DIR4_Z[side]
		var ay := base + 1 + rng.randi_range(0, maxi(0, height - 3))
		_put(o, x + dx, ay, z + dz, log_id, false)
		_put(o, x + dx, ay + 1, z + dz, log_id, false)
		_put(o, x + dx, ay + 2, z + dz, log_id, false)
	return


## A tapering crystal column. Grows on any surface, including cave floors, and
## is one of the few features that also looks right upside down.
func _tree_crystal(o: Vector3i, x: int, base: int, z: int,
		height: int, id: int, rng: RandomNumberGenerator) -> void:
	var r := 1 if height < 7 else 2
	for i in height:
		var rr := r if i < height / 2 else 0
		for dz in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if absi(dx) + absi(dz) > rr:
					continue
				_put(o, x + dx, base + i, z + dz, id, true)
	for sat in rng.randi_range(0, 3):
		var sx := x + rng.randi_range(-2, 2)
		var sz := z + rng.randi_range(-2, 2)
		var sh := 1 + rng.randi_range(0, 3)
		for i in sh:
			_put(o, sx, base + i, sz, id, false)
	return


# ================================================================== scatter
func _build_boulder(o: Vector3i, x: int, ground: int, z: int,
		h: int, b: Biome) -> void:
	var id: int = int(b.ids()["stone"]) if _id_boulder == Const.AIR else _id_boulder
	var r := 1 + absi(h >> 25) % 2
	for dy in range(0, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy + dz * dz > r * r + 1:
					continue
				_put(o, x + dx, ground + dy, z + dz, id, dy == 0)
	return


## A fallen trunk lying along one horizontal axis. From the plane it runs along
## it is a low platform; from the perpendicular plane it is a single stump —
## a small, cheap lesson in what flipping does.
func _build_fallen_log(o: Vector3i, x: int, base: int, z: int,
		h: int, _b: Biome) -> void:
	var log_id := _opt([&"wood_log", &"oak_log", &"dead_log"])
	if log_id == Const.AIR:
		return
	var along_x := ((h >> 17) & 1) == 1
	var length := 3 + absi(h >> 19) % 4
	for k in length:
		var wx := x + (k if along_x else 0)
		var wz := z + (0 if along_x else k)
		_put(o, wx, base, wz, log_id, false)
	return


func _build_clump(o: Vector3i, x: int, base: int, z: int,
		h: int, kind: StringName, _b: Biome) -> void:
	var id := Const.AIR
	match kind:
		&"mushroom":
			id = _opt([&"mushroom_red", &"mushroom_brown", &"glow_mushroom"])
		&"cactus":
			id = _opt([&"cactus", &"barrel_cactus"])
		&"bones":
			id = _id_bones
	if id == Const.AIR:
		return
	var n := 1 + absi(h >> 23) % 4
	for k in n:
		var ox := (absi(NoiseBank.hash_i(x, base, z + k, SALT_SCATTER + 1)) % 3) - 1
		var oz := (absi(NoiseBank.hash_i(x + k, base, z, SALT_SCATTER + 2)) % 3) - 1
		var gy := shaper.height_at(x + ox, z + oz) + 1
		_put(o, x + ox, gy, z + oz, id, false)
		if kind == &"cactus":
			_put(o, x + ox, gy + 1, z + oz, id, false)
	return


## Branching coral on the seabed. Grows toward the surface but never breaks it.
func _build_coral(o: Vector3i, x: int, base: int, z: int, _h: int) -> void:
	var id := _opt([&"coral", &"coral_blue", &"coral_glow"])
	if id == Const.AIR:
		return
	var rng := NoiseBank.rng_at(x, base, z, SALT_SCATTER + 5)
	var height := 2 + rng.randi_range(0, 4)
	var cx := x
	var cz := z
	for i in height:
		if base + i >= sea_level:
			break
		_put(o, cx, base + i, cz, id, false)
		if i > 1 and rng.randf() < 0.5:
			var bx := cx + rng.randi_range(-1, 1)
			var bz := cz + rng.randi_range(-1, 1)
			_put(o, bx, base + i, bz, id, false)
			_put(o, bx, base + i + 1, bz, id, false)
		if rng.randf() < 0.35:
			cx += rng.randi_range(-1, 1)
			cz += rng.randi_range(-1, 1)
	return


func _build_crystal(o: Vector3i, x: int, base: int, z: int, _h: int) -> void:
	var id := _opt([&"crystal_block", &"crystal_blue", &"crystal_violet", &"ice"])
	if id == Const.AIR:
		return
	var rng := NoiseBank.rng_at(x, base, z, SALT_SCATTER + 7)
	_tree_crystal(o, x, base, z, 3 + rng.randi_range(0, 5), id, rng)
	return


# =================================================================== helpers
## Sphere of leaves, optionally trailing vines from its underside.
func _leaf_ball(o: Vector3i, x: int, y: int, z: int, r: int,
		leaf_id: int, vines: bool, rng: RandomNumberGenerator) -> void:
	if leaf_id == Const.AIR:
		return
	var r2 := r * r + 1
	for dy in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d2 := dx * dx + dy * dy + dz * dz
				if d2 > r2:
					continue
				if d2 == r2 and rng.randf() < 0.4:
					continue          # ragged edge
				_put(o, x + dx, y + dy, z + dz, leaf_id, false)
	if vines and _id_vine != Const.AIR:
		for vi in 5:
			var vx := x + rng.randi_range(-r, r)
			var vz := z + rng.randi_range(-r, r)
			var vl := 1 + rng.randi_range(0, 4)
			for k in vl:
				_put(o, vx, y - r - k, vz, _id_vine, false)
	return


## Voxel line (3D Bresenham-ish) used for tree limbs.
func _line(o: Vector3i, x0: int, y0: int, z0: int,
		x1: int, y1: int, z1: int, id: int) -> void:
	var steps := maxi(maxi(absi(x1 - x0), absi(y1 - y0)), absi(z1 - z0))
	if steps <= 0:
		_put(o, x0, y0, z0, id, true)
		return
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		_put(o,
			x0 + int(round(float(x1 - x0) * t)),
			y0 + int(round(float(y1 - y0) * t)),
			z0 + int(round(float(z1 - z0) * t)), id, true)
	return


## Write one voxel if it lands inside this chunk. `force` overwrites anything
## that is not solid rock; otherwise only air is replaced.
func _put(o: Vector3i, wx: int, wy: int, wz: int,
		id: int, force: bool) -> void:
	if id == Const.AIR or wy < 0 or wy >= Const.WORLD_HEIGHT:
		return
	var ly := wy - o.y
	if ly < 0 or ly > 15:
		return
	var lx := wrapi(wx - o.x, -(shaper.size_x >> 1), shaper.size_x >> 1)
	if lx < 0 or lx > 15:
		return
	var lz := wrapi(wz - o.z, -(shaper.size_z >> 1), shaper.size_z >> 1)
	if lz < 0 or lz > 15:
		return
	var i := (ly << 8) | (lz << 4) | lx
	var cur := _buf[i]
	if cur != Const.AIR and not force:
		return
	if cur != Const.AIR and force and Blocks.is_opaque(cur) and not Blocks.is_liquid(cur):
		# Never chew through terrain: only leaves, plants and liquids give way.
		if not Blocks.get_type(cur).has_tag(&"foliage"):
			return
	_buf[i] = id
	return


func _cell_hash(x: int, z: int, salt: int) -> int:
	return NoiseBank.hash_i(posmod(x, shaper.size_x), 0, posmod(z, shaper.size_z), salt)
