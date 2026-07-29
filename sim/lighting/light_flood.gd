## The light propagation kernels — the hot core of `sim/lighting/`.
##
## Two independent 4-bit channels live packed in `Chunk.light`
## (high nibble = skylight, low nibble = block light). This class owns every
## write to that byte; `Lighting` only schedules the work.
##
## Design notes that matter for speed:
##
## * **Packed queues.** BFS frontiers are `PackedInt64Array`s of bit-packed
##   nodes (`x<<32 | z<<12 | y<<4 | level`), never `Array[Vector3i]` — no
##   Variant boxing, no per-node allocation. Each queue keeps a *head* index
##   instead of `pop_front()`, so popping is O(1); the tail is compacted only
##   when the head runs far ahead.
## * **Bound-chunk cache.** A flood is spatially coherent, so the kernel keeps
##   one chunk bound at a time and works on a local `PackedByteArray` copy of
##   its light. GDScript packed arrays are copy-on-write, so the copy is only
##   materialised on the first write and is handed back to the chunk on
##   `_flush()`. That turns "property get + index" per voxel into a plain local
##   array index.
## * **Column short-circuit.** Skylight in a column can only ever decrease
##   downward, so the seeding pass `break`s the instant a column reaches 0.
##   Underground chunks therefore cost ~256 iterations instead of 4096.
## * **Bounded work slices.** Nothing here loops until it is done; every entry
##   point takes an operation budget and returns how much it spent, so the
##   manager can keep the frame time flat.
##
## Opacity model (`opacity[block_id]`, 0..15):
##   0  = free (air, glass, ice, cross-quads) — skylight falls through a
##        vertical column of these at full strength
##   1  = cheap translucency (leaves, generic transparent blocks)
##   2  = liquids (water, lava): a visible underwater gradient
##   15 = opaque, light stops dead
class_name LitFlood
extends RefCounted

const OPAQUE_COST := 15
const VOL := Const.CHUNK_VOL
const WORLD_H := Const.WORLD_HEIGHT
const MAX_LIGHT := Const.MAX_LIGHT

## Neighbour offsets. Index 3 is "straight down", which skylight treats
## specially (a full-strength column does not decay).
const DX := [1, -1, 0, 0, 0, 0]
const DY := [0, 0, 1, -1, 0, 0]
const DZ := [0, 0, 0, 0, 1, -1]
const DOWN := 3

## For direction `d`, the face of the *neighbour* chunk that touches us,
## expressed as a local-index base plus two strides. Lets `_seed_borders` walk
## a 16x16 face with pure integer maths and no branching in the inner loop.
const FACE_BASE := [0, 15, 0, 3840, 0, 240]
const FACE_SA := [256, 256, 1, 1, 1, 1]
const FACE_SB := [16, 16, 16, 16, 256, 256]

## Head index past which a queue is compacted rather than left to grow.
const COMPACT_AFTER := 4096

# ------------------------------------------------------------------ block LUTs
var opacity := PackedByteArray()
var emission := PackedByteArray()
var _lut_types := -1

# ------------------------------------------------------------------ world view
var size_x := Const.PLANET_SIZE_DEFAULT
var size_z := Const.PLANET_SIZE_DEFAULT
var chunks: Dictionary = {}

## Chunks whose light bytes changed since the manager last drained this.
var touched: Dictionary = {}
## cpos -> PackedByteArray(256): the skylight that arrived through this chunk's
## ceiling the last time it was seeded. See `roof_changed()`.
var roof: Dictionary = {}

# ---------------------------------------------------------------------- queues
var _q_sa := PackedInt64Array()   ## sky additions
var _h_sa := 0
var _q_sr := PackedInt64Array()   ## sky removals   (level = level being erased)
var _h_sr := 0
var _q_ba := PackedInt64Array()   ## block-light additions
var _h_ba := 0
var _q_br := PackedInt64Array()   ## block-light removals
var _h_br := 0

# ------------------------------------------------------------ bound-chunk cache
var _b_valid := false
var _b_cx := 0
var _b_cy := 0
var _b_cz := 0
var _b_cpos := Vector3i.ZERO
var _b_chunk: Chunk = null
var _b_light := PackedByteArray()
var _b_blocks := PackedInt32Array()
var _b_wrote := false

## Working light buffer for `seed_chunk` and its helpers. A member rather than
## a parameter because packed arrays are copy-on-write *values*: a copy handed
## to a helper would silently diverge from the caller's.
var _slt := PackedByteArray()

# ------------------------------------------------------------------- telemetry
var ops_last_slice := 0


# =============================================================== configuration
## Point the kernel at the live world. Called whenever a planet is created.
func set_world(p_size_x: int, p_size_z: int, p_chunks: Dictionary) -> void:
	size_x = maxi(16, p_size_x)
	size_z = maxi(16, p_size_z)
	chunks = p_chunks
	roof.clear()
	touched.clear()
	clear_queues()


## Rebuild the per-block-id opacity / emission tables from the registry.
## Cheap and idempotent; `Lighting` calls it whenever `Blocks.count()` moves.
func rebuild_luts() -> void:
	var n: int = Blocks.count()
	opacity.resize(n)
	emission.resize(n)
	for i in n:
		var bt: BlockType = Blocks.get_type(i)
		opacity[i] = opacity_of(bt)
		emission[i] = clampi(bt.light, 0, MAX_LIGHT)
	_lut_types = n


func luts_stale() -> bool:
	return Blocks.count() != _lut_types


## How much light one voxel of this block type eats. See the class docs.
static func opacity_of(bt: BlockType) -> int:
	if bt == null or bt.id == Const.AIR:
		return 0
	if bt.opaque:
		return OPAQUE_COST
	match bt.render:
		BlockType.Render.NONE, BlockType.Render.CROSS:
			return 0
		BlockType.Render.LIQUID:
			return 2
	if bt.liquid:
		return 2
	if bt.has_tag(&"glass") or bt.pattern == BlockType.Pattern.GLASS \
			or bt.pattern == BlockType.Pattern.ICE:
		return 0
	if bt.has_tag(&"leaves"):
		return 1
	return 1


func clear_queues() -> void:
	_q_sa.clear(); _h_sa = 0
	_q_sr.clear(); _h_sr = 0
	_q_ba.clear(); _h_ba = 0
	_q_br.clear(); _h_br = 0
	_b_valid = false
	_b_chunk = null
	_b_wrote = false


# ==================================================================== packing
static func pack(x: int, y: int, z: int, level: int) -> int:
	return (x << 32) | (z << 12) | (y << 4) | level


# ============================================================== chunk binding
func _bind(cx: int, cy: int, cz: int) -> bool:
	if _b_valid and cx == _b_cx and cy == _b_cy and cz == _b_cz:
		return _b_chunk != null
	_flush()
	_b_cx = cx
	_b_cy = cy
	_b_cz = cz
	_b_valid = true
	if cy < 0 or cy >= Const.WORLD_HEIGHT_CHUNKS:
		_b_chunk = null
		return false
	_b_cpos = Vector3i(cx, cy, cz)
	var c: Chunk = chunks.get(_b_cpos)
	_b_chunk = c
	if c == null:
		return false
	_b_blocks = c.blocks
	_b_light = c.light
	return true


## Hand the working copy back to its chunk. Must run before anything outside
## this class reads `Chunk.light` again — every public entry point does it.
func _flush() -> void:
	if _b_chunk != null and _b_wrote:
		_b_chunk.light = _b_light
		touched[_b_cpos] = true
	_b_chunk = null
	_b_wrote = false
	_b_valid = false


## Public flush, for the manager to call before meshing / reading light.
func end_slice() -> void:
	_flush()


# ============================================================ queue management
func queue_sky_add(x: int, y: int, z: int, level: int) -> void:
	if level > 1:
		_q_sa.append((x << 32) | (z << 12) | (y << 4) | level)


func queue_sky_remove(x: int, y: int, z: int, level: int) -> void:
	if level > 0:
		_q_sr.append((x << 32) | (z << 12) | (y << 4) | level)


func queue_block_add(x: int, y: int, z: int, level: int) -> void:
	if level > 1:
		_q_ba.append((x << 32) | (z << 12) | (y << 4) | level)


func queue_block_remove(x: int, y: int, z: int, level: int) -> void:
	if level > 0:
		_q_br.append((x << 32) | (z << 12) | (y << 4) | level)


func pending() -> int:
	return (_q_sa.size() - _h_sa) + (_q_sr.size() - _h_sr) \
		+ (_q_ba.size() - _h_ba) + (_q_br.size() - _h_br)


func has_removals() -> bool:
	return _h_sr < _q_sr.size() or _h_br < _q_br.size()


# =============================================================== the work slice
## Spend at most `budget` node-pops. Removals always run to completion before
## additions: the two-queue algorithm is only correct in that order.
## Returns the number of pops actually spent.
func run_slice(budget: int) -> int:
	var used := 0
	if _h_br < _q_br.size():
		used += _run_block_remove(budget - used)
	if used < budget and _h_sr < _q_sr.size():
		used += _run_sky_remove(budget - used)
	if used < budget and not has_removals():
		used += _run_block_add(budget - used)
		if used < budget:
			used += _run_sky_add(budget - used)
	_flush()
	_compact()
	ops_last_slice = used
	return used


func _compact() -> void:
	if _h_sa >= _q_sa.size():
		_q_sa.clear(); _h_sa = 0
	elif _h_sa > COMPACT_AFTER:
		_q_sa = _q_sa.slice(_h_sa); _h_sa = 0
	if _h_sr >= _q_sr.size():
		_q_sr.clear(); _h_sr = 0
	elif _h_sr > COMPACT_AFTER:
		_q_sr = _q_sr.slice(_h_sr); _h_sr = 0
	if _h_ba >= _q_ba.size():
		_q_ba.clear(); _h_ba = 0
	elif _h_ba > COMPACT_AFTER:
		_q_ba = _q_ba.slice(_h_ba); _h_ba = 0
	if _h_br >= _q_br.size():
		_q_br.clear(); _h_br = 0
	elif _h_br > COMPACT_AFTER:
		_q_br = _q_br.slice(_h_br); _h_br = 0


# ===================================================== skylight — addition BFS
func _run_sky_add(budget: int) -> int:
	var ops := 0
	var n_end := _q_sa.size()
	while _h_sa < n_end and ops < budget:
		var node: int = _q_sa[_h_sa]
		_h_sa += 1
		ops += 1
		var lvl: int = node & 15
		if lvl <= 1:
			continue
		var y: int = (node >> 4) & 255
		var z: int = (node >> 12) & 0xFFFFF
		var x: int = node >> 32
		for d in 6:
			var ny: int = y + int(DY[d])
			if ny < 0 or ny >= WORLD_H:
				continue
			var nx: int = x + int(DX[d])
			if nx < 0:
				nx = size_x - 1
			elif nx >= size_x:
				nx = 0
			var nz: int = z + int(DZ[d])
			if nz < 0:
				nz = size_z - 1
			elif nz >= size_z:
				nz = 0
			if not _bind(nx >> 4, ny >> 4, nz >> 4):
				continue
			var i: int = ((ny & 15) << 8) | ((nz & 15) << 4) | (nx & 15)
			var op: int = opacity[_b_blocks[i]]
			if op >= OPAQUE_COST:
				continue
			var nl: int = 15 if (d == DOWN and lvl == 15 and op == 0) else lvl - maxi(op, 1)
			if nl <= 0:
				continue
			var cur: int = _b_light[i] >> 4
			if cur >= nl:
				continue
			_b_light[i] = (_b_light[i] & 15) | (nl << 4)
			_b_wrote = true
			if nl > 1:
				_q_sa.append((nx << 32) | (nz << 12) | (ny << 4) | nl)
				n_end = _q_sa.size()
	return ops


# ====================================================== skylight — removal BFS
func _run_sky_remove(budget: int) -> int:
	var ops := 0
	while _h_sr < _q_sr.size() and ops < budget:
		var node: int = _q_sr[_h_sr]
		_h_sr += 1
		ops += 1
		var old: int = node & 15
		var y: int = (node >> 4) & 255
		var z: int = (node >> 12) & 0xFFFFF
		var x: int = node >> 32
		for d in 6:
			var ny: int = y + int(DY[d])
			if ny < 0 or ny >= WORLD_H:
				continue
			var nx: int = x + int(DX[d])
			if nx < 0:
				nx = size_x - 1
			elif nx >= size_x:
				nx = 0
			var nz: int = z + int(DZ[d])
			if nz < 0:
				nz = size_z - 1
			elif nz >= size_z:
				nz = 0
			if not _bind(nx >> 4, ny >> 4, nz >> 4):
				continue
			var i: int = ((ny & 15) << 8) | ((nz & 15) << 4) | (nx & 15)
			var nl: int = _b_light[i] >> 4
			if nl == 0:
				continue
			# A full-strength column propagates downward without decay, so a
			# 15 directly below a removed 15 also came from us.
			if nl < old or (d == DOWN and old == 15 and nl == 15):
				_b_light[i] = _b_light[i] & 15
				_b_wrote = true
				if nl > 1:
					_q_sr.append((nx << 32) | (nz << 12) | (ny << 4) | nl)
			else:
				# Brighter than what we erased: it is a legitimate source that
				# must refill the hole once the removal wave has passed.
				if nl > 1:
					_q_sa.append((nx << 32) | (nz << 12) | (ny << 4) | nl)
	return ops


# =================================================== block light — addition BFS
func _run_block_add(budget: int) -> int:
	var ops := 0
	var n_end := _q_ba.size()
	while _h_ba < n_end and ops < budget:
		var node: int = _q_ba[_h_ba]
		_h_ba += 1
		ops += 1
		var lvl: int = node & 15
		if lvl <= 1:
			continue
		var y: int = (node >> 4) & 255
		var z: int = (node >> 12) & 0xFFFFF
		var x: int = node >> 32
		for d in 6:
			var ny: int = y + int(DY[d])
			if ny < 0 or ny >= WORLD_H:
				continue
			var nx: int = x + int(DX[d])
			if nx < 0:
				nx = size_x - 1
			elif nx >= size_x:
				nx = 0
			var nz: int = z + int(DZ[d])
			if nz < 0:
				nz = size_z - 1
			elif nz >= size_z:
				nz = 0
			if not _bind(nx >> 4, ny >> 4, nz >> 4):
				continue
			var i: int = ((ny & 15) << 8) | ((nz & 15) << 4) | (nx & 15)
			var op: int = opacity[_b_blocks[i]]
			if op >= OPAQUE_COST:
				continue
			var nl: int = lvl - maxi(op, 1)
			if nl <= 0:
				continue
			if (_b_light[i] & 15) >= nl:
				continue
			_b_light[i] = (_b_light[i] & 240) | nl
			_b_wrote = true
			if nl > 1:
				_q_ba.append((nx << 32) | (nz << 12) | (ny << 4) | nl)
				n_end = _q_ba.size()
	return ops


# ==================================================== block light — removal BFS
func _run_block_remove(budget: int) -> int:
	var ops := 0
	while _h_br < _q_br.size() and ops < budget:
		var node: int = _q_br[_h_br]
		_h_br += 1
		ops += 1
		var old: int = node & 15
		var y: int = (node >> 4) & 255
		var z: int = (node >> 12) & 0xFFFFF
		var x: int = node >> 32
		for d in 6:
			var ny: int = y + int(DY[d])
			if ny < 0 or ny >= WORLD_H:
				continue
			var nx: int = x + int(DX[d])
			if nx < 0:
				nx = size_x - 1
			elif nx >= size_x:
				nx = 0
			var nz: int = z + int(DZ[d])
			if nz < 0:
				nz = size_z - 1
			elif nz >= size_z:
				nz = 0
			if not _bind(nx >> 4, ny >> 4, nz >> 4):
				continue
			var i: int = ((ny & 15) << 8) | ((nz & 15) << 4) | (nx & 15)
			var nl: int = _b_light[i] & 15
			if nl == 0:
				continue
			if nl < old:
				_b_light[i] = _b_light[i] & 240
				_b_wrote = true
				if nl > 1:
					_q_br.append((nx << 32) | (nz << 12) | (ny << 4) | nl)
			elif nl > 1:
				_q_ba.append((nx << 32) | (nz << 12) | (ny << 4) | nl)
	return ops


# ============================================================ initial chunk fill
## Seed one chunk from scratch: skylight column descent + block-light emitter
## scan + border hand-off with already-lit neighbours. Everything it discovers
## goes into the BFS queues, so the *spread* is still budgeted.
##
## Returns a rough op count so the manager can charge it against the frame.
func seed_chunk(c: Chunk, relight: bool) -> int:
	_flush()
	var cp := c.cpos
	# NOTE: packed arrays are copy-on-write *values* in GDScript, so a local
	# copy handed to a helper would diverge silently. The working buffer is a
	# member for exactly that reason, and is written back once at the end.
	if relight:
		# A fresh zero-filled buffer beats clearing 4096 bytes one at a time.
		_slt = PackedByteArray()
		_slt.resize(VOL)
	else:
		_slt = c.light
	var ops := 0
	ops += _seed_sky(c, cp)
	ops += _seed_block(c, cp)
	c.light = _slt
	_slt = PackedByteArray()
	touched[cp] = true
	ops += _seed_borders(cp)
	return ops


func _seed_sky(c: Chunk, cp: Vector3i) -> int:
	var lt := _slt
	var blk := c.blocks
	var ox: int = cp.x << 4
	var oy: int = cp.y << 4
	var oz: int = cp.z << 4
	var above: Chunk = chunks.get(Vector3i(cp.x, cp.y + 1, cp.z))
	# No chunk above means "unloaded / off the top of the world"; `World`
	# reports AIR there, so open sky is the consistent assumption.
	var ops := 0
	var any_lit := false
	var all_full := true
	var ymin := 15
	var ymax := 0
	# The 16x16 skylight values arriving through the ceiling. Remembered so
	# `roof_changed()` can tell exactly when a chunk that loaded *above* this
	# one has invalidated it — no heuristics, no relight churn.
	var sig := PackedByteArray()
	sig.resize(256)
	for lz in 16:
		var zb: int = lz << 4
		for lx in 16:
			var v := 15
			if above != null:
				v = above.light[zb | lx] >> 4
			sig[zb | lx] = v
			if v <= 0:
				all_full = false
				continue
			for ly in range(15, -1, -1):
				ops += 1
				var i: int = (ly << 8) | zb | lx
				var op: int = opacity[blk[i]]
				if op >= OPAQUE_COST:
					all_full = false
					break
				if op > 0 or v < 15:
					v -= maxi(op, 1)
					if v <= 0:
						all_full = false
						break
				lt[i] = (lt[i] & 15) | (v << 4)
				any_lit = true
				if v < 15:
					all_full = false
				if ly < ymin:
					ymin = ly
				if ly > ymax:
					ymax = ly
	roof[cp] = sig
	if not any_lit:
		_slt = lt
		return ops
	# Frontier scan: only voxels that can actually brighten a neighbour become
	# BFS seeds. Border voxels always seed (their neighbour lives in another
	# chunk); interior voxels seed only where they sit next to something
	# darker. A uniformly-lit air chunk therefore costs almost nothing.
	for ly in range(ymin, ymax + 1):
		var yb: int = ly << 8
		var edge_y: bool = ly == 0 or ly == 15
		for lz in 16:
			var zb: int = lz << 4
			var edge_z: bool = edge_y or lz == 0 or lz == 15
			for lx in 16:
				var i: int = yb | zb | lx
				var s: int = lt[i] >> 4
				if s <= 1:
					continue
				ops += 1
				if edge_z or lx == 0 or lx == 15:
					_q_sa.append(((ox + lx) << 32) | ((oz + lz) << 12) | ((oy + ly) << 4) | s)
					continue
				if all_full:
					continue
				var lim: int = s - 1
				if (lt[i - 1] >> 4) < lim or (lt[i + 1] >> 4) < lim \
						or (lt[i - 16] >> 4) < lim or (lt[i + 16] >> 4) < lim \
						or (lt[i - 256] >> 4) < lim or (lt[i + 256] >> 4) < lim:
					_q_sa.append(((ox + lx) << 32) | ((oz + lz) << 12) | ((oy + ly) << 4) | s)
	_slt = lt
	return ops


func _seed_block(c: Chunk, cp: Vector3i) -> int:
	if c.empty:
		return 0
	var lt := _slt
	var blk := c.blocks
	var ox: int = cp.x << 4
	var oy: int = cp.y << 4
	var oz: int = cp.z << 4
	for i in VOL:
		var e: int = emission[blk[i]]
		if e == 0:
			continue
		if (lt[i] & 15) >= e:
			continue
		lt[i] = (lt[i] & 240) | e
		if e > 1:
			var lx: int = i & 15
			var lz: int = (i >> 4) & 15
			var ly: int = i >> 8
			_q_ba.append(((ox + lx) << 32) | ((oz + lz) << 12) | ((oy + ly) << 4) | e)
	_slt = lt
	return VOL


## Pull light in from the six neighbouring chunks that are already lit. The
## outward direction is covered by the frontier seeds above.
func _seed_borders(cp: Vector3i) -> int:
	var ops := 0
	var wx: int = maxi(1, size_x >> 4)
	var wz: int = maxi(1, size_z >> 4)
	for d in 6:
		var ncy: int = cp.y + int(DY[d])
		if ncy < 0 or ncy >= Const.WORLD_HEIGHT_CHUNKS:
			continue
		var np := Vector3i(posmod(cp.x + int(DX[d]), wx), ncy, posmod(cp.z + int(DZ[d]), wz))
		var nc: Chunk = chunks.get(np)
		if nc == null or not nc.lit:
			continue
		var nlt := nc.light
		var ox: int = np.x << 4
		var oy: int = np.y << 4
		var oz: int = np.z << 4
		var base: int = FACE_BASE[d]
		var sa: int = FACE_SA[d]
		var sb: int = FACE_SB[d]
		# Walk the 16x16 face of the neighbour that touches us. Branch-free:
		# the face is a base index plus two strides (see FACE_* above).
		for a in 16:
			var row: int = base + a * sa
			for b in 16:
				var i: int = row + b * sb
				var byte: int = nlt[i]
				if byte == 0:
					continue
				var s: int = byte >> 4
				var bl: int = byte & 15
				if s <= 1 and bl <= 1:
					continue
				var wxx: int = ox + (i & 15)
				var wzz: int = oz + ((i >> 4) & 15)
				var wyy: int = oy + (i >> 8)
				if s > 1:
					_q_sa.append((wxx << 32) | (wzz << 12) | (wyy << 4) | s)
				if bl > 1:
					_q_ba.append((wxx << 32) | (wzz << 12) | (wyy << 4) | bl)
				ops += 1
	return ops


## Has the ceiling the chunk *below* `cp` was lit under changed? Compares the
## roof signature captured when that chunk was seeded against the skylight
## `cp` is handing down now. Exact, so a downward cascade re-light happens
## once and then stops — no oscillation.
func roof_changed(cp: Vector3i) -> bool:
	var below_pos := Vector3i(cp.x, cp.y - 1, cp.z)
	var below: Chunk = chunks.get(below_pos)
	var c: Chunk = chunks.get(cp)
	if c == null or below == null or not below.lit:
		return false
	var sig: PackedByteArray = roof.get(below_pos, PackedByteArray())
	if sig.size() != 256:
		return true
	var a := c.light
	for k in 256:
		if sig[k] != (a[k] >> 4):
			return true
	return false


## Drop remembered state for a chunk that is being unloaded.
func forget_chunk(cp: Vector3i) -> void:
	roof.erase(cp)
	touched.erase(cp)
