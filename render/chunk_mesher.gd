## Turns one 16^3 `Chunk` into up to three `ArrayMesh` surfaces: opaque cubes,
## alpha-blended cubes/plants, and liquids.
##
## The work is split into two halves so it can be moved onto a worker thread:
##
##   `snapshot(cpos)`      main thread only. Copies the chunk and its one-voxel
##                         border into flat packed arrays, together with the
##                         immutable registry/atlas tables. Touches `World`.
##   `build_arrays(snap)`  pure function of that snapshot. Safe on any thread —
##                         it never reads a singleton or the scene tree.
##
## `build(cpos)` runs both plus `arrays_to_mesh()` for callers that just want a
## mesh on the spot. `render/mesh_worker.gd` uses the split form.
##
## Meshing notes
## -------------
## * Faces are culled against neighbours, reading across chunk borders through
##   the padded snapshot (which itself was filled from the neighbour chunks).
## * Coplanar faces of the same block with identical per-corner lighting are
##   merged greedily into one quad. The visible slab is very wide in this game,
##   so long horizontal runs of stone are the common case and the win is large.
## * Ambient occlusion comes from the three neighbours at each face corner, and
##   per-corner light is the average of the non-opaque cells around that corner.
##   Both are folded into the vertex colour; see the shader header for the
##   exact contract.
class_name ChunkMesher
extends RefCounted

const S := 16
## Padded working grid: the chunk plus a one-voxel shell on every side.
const PS := 18
const PS_SQ := 324          ## PS * PS
const PAD_VOL := 5832       ## PS ^ 3
## Padded index of local (0,0,0).
const ORIGIN_I := 343       ## (1 * PS + 1) * PS + 1

## Step in the padded array for +1 along X, Y and Z respectively.
const STRIDE := [1, PS_SQ, PS]
const AXIS := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
## Vertex brightness for ambient occlusion levels 0 (most occluded) .. 3 (open).
const AO_FACTOR := [0.42, 0.62, 0.80, 1.0]
## How far cross quads are pulled in from the voxel edges, to avoid z-fighting.
const CROSS_INSET := 0.05

# Bucket layout: [verts, normals, uv, uv2, color, index].
const B_VERT := 0
const B_NORM := 1
const B_UV := 2
const B_UV2 := 3
const B_COL := 4
const B_IDX := 5

## Per-corner ambient occlusion. Disable for a cheaper (flatter) mesh.
static var ao_enabled := true
## Prefer the packed per-voxel light bytes the lighting module writes into
## `Chunk.light`. When a chunk has no light data we fall back to a single
## `Lighting.factor_at()` sample so the world is never rendered pitch black.
static var prefer_packed_light := true

static var _zero_i16 := PackedInt32Array()
static var _zero_b16 := PackedByteArray()
static var _zero_i18 := PackedInt32Array()
static var _zero_b18 := PackedByteArray()


# ================================================================== convenience
## Build every surface for `cpos`. Returns
## `{opaque: ArrayMesh, transparent: ArrayMesh, liquid: ArrayMesh}`; any surface
## with no geometry is `null`. Main thread only.
static func build(cpos: Vector3i) -> Dictionary:
	var snap := snapshot(cpos)
	if snap.is_empty():
		return {"opaque": null, "transparent": null, "liquid": null}
	var built := build_arrays(snap)
	return {
		"opaque": arrays_to_mesh(built["opaque"]),
		"transparent": arrays_to_mesh(built["transparent"]),
		"liquid": arrays_to_mesh(built["liquid"]),
	}


# =================================================================== snapshot
## Copy everything `build_arrays()` needs out of the live world. Main thread only.
## Returns `{}` when the chunk is missing or entirely air.
static func snapshot(cpos: Vector3i) -> Dictionary:
	var chunk: Chunk = World.get_chunk(cpos)
	if chunk == null or chunk.empty:
		return {}
	_ensure_zero()

	var tables: Dictionary = Atlas.mesh_tables()
	var origin := cpos * S

	# 3x3x3 neighbourhood, resolved once; every row copy below is then pure
	# array indexing. Index = (dy * 3 + dz) * 3 + dx, each in 0..2.
	var grid: Array = []
	grid.resize(27)
	var wx := maxi(1, World.size_x >> 4)
	var wz := maxi(1, World.size_z >> 4)
	for dy in 3:
		var cy := cpos.y + dy - 1
		for dz in 3:
			var cz := posmod(cpos.z + dz - 1, wz)
			for dx in 3:
				var cx := posmod(cpos.x + dx - 1, wx)
				var idx := (dy * 3 + dz) * 3 + dx
				if cy < 0 or cy >= Const.WORLD_HEIGHT_CHUNKS:
					grid[idx] = null
				else:
					grid[idx] = World.chunks.get(Vector3i(cx, cy, cz))

	var pb := PackedInt32Array()
	var pl := PackedByteArray()
	var pq := PackedByteArray()
	for py in PS:
		var dyi := 0 if py == 0 else (1 if py <= S else 2)
		var ly := 15 if py == 0 else (0 if py == PS - 1 else py - 1)
		var wy := origin.y + py - 1
		var y_ok := wy >= 0 and wy < Const.WORLD_HEIGHT
		for pz in PS:
			if not y_ok:
				pb.append_array(_zero_i18)
				pl.append_array(_zero_b18)
				pq.append_array(_zero_b18)
				continue
			var dzi := 0 if pz == 0 else (1 if pz <= S else 2)
			var lz := 15 if pz == 0 else (0 if pz == PS - 1 else pz - 1)
			var g := (dyi * 3 + dzi) * 3
			var cl: Chunk = grid[g]
			var cm: Chunk = grid[g + 1]
			var cr: Chunk = grid[g + 2]
			var base := (ly << 8) | (lz << 4)
			# -X shell column (last column of the left neighbour).
			if cl != null:
				pb.append(cl.blocks[base | 15])
				pl.append(cl.light[base | 15])
				pq.append(cl.liquid[base | 15])
			else:
				pb.append(0)
				pl.append(0)
				pq.append(0)
			# The 16 interior voxels are contiguous in the chunk arrays.
			if cm != null:
				pb.append_array(cm.blocks.slice(base, base + S))
				pl.append_array(cm.light.slice(base, base + S))
				pq.append_array(cm.liquid.slice(base, base + S))
			else:
				pb.append_array(_zero_i16)
				pl.append_array(_zero_b16)
				pq.append_array(_zero_b16)
			# +X shell column (first column of the right neighbour).
			if cr != null:
				pb.append(cr.blocks[base])
				pl.append(cr.light[base])
				pq.append(cr.liquid[base])
			else:
				pb.append(0)
				pl.append(0)
				pq.append(0)

	return {
		"cpos": cpos,
		"blocks": pb,
		"light": pl,
		"liquid": pq,
		"light_map": _light_map(chunk),
		# Duplicated, not shared: these tables are rebuilt in place whenever a
		# block is registered, and a worker thread must never read one mid-resize.
		"opaque_lut": Blocks.opaque_lut.duplicate(),
		"render_lut": Blocks.render_lut.duplicate(),
		"layer_base": (tables["layer_base"] as PackedInt32Array).duplicate(),
		"emission": (tables["emission"] as PackedFloat32Array).duplicate(),
		"tint": (tables["tint"] as PackedColorArray).duplicate(),
	}


## 256-entry table turning a packed light byte into a 0..1 vertex shade, so the
## mesher never has to branch on daylight in its inner loops.
static func _light_map(chunk: Chunk) -> PackedFloat32Array:
	var map := PackedFloat32Array()
	map.resize(256)
	var has_data := false
	if prefer_packed_light:
		# Sparse probe: cheap, and a chunk with light almost always has plenty.
		for i in range(0, Const.CHUNK_VOL, 13):
			if chunk.light[i] != 0:
				has_data = true
				break
	if has_data:
		# Prefer the lighting module's own table: same shape, but it already
		# folds in the planet's daylight curve, weather dimming and ambient
		# floor. Ours bottoms out at pure black and knows none of that.
		if Lighting.has_method(&"light_map"):
			var lit: PackedFloat32Array = Lighting.light_map()
			if lit.size() == 256:
				return lit
		var daylight: float = clampf(Game.daylight, 0.0, 1.0)
		for b in 256:
			var block_l := b & 15
			var sky_l := int(float(b >> 4) * daylight)
			map[b] = float(maxi(block_l, sky_l)) / float(Const.MAX_LIGHT)
		return map
	# No light data yet (or the lighting module keeps it elsewhere): ask the
	# lighting singleton for one representative value for the whole chunk.
	var uniform := 1.0
	if Lighting.has_method(&"factor_at"):
		uniform = clampf(Lighting.factor_at(chunk.origin() + Vector3i(8, 8, 8)), 0.0, 1.0)
	map.fill(uniform)
	return map


static func _ensure_zero() -> void:
	if _zero_i16.size() == S:
		return
	_zero_i16.resize(S)
	_zero_b16.resize(S)
	_zero_i18.resize(PS)
	_zero_b18.resize(PS)


# =============================================================== mesh building
## Pure, thread-safe. Returns `{cpos, opaque, transparent, liquid}` where each
## surface is a bucket array (see `arrays_to_mesh`).
static func build_arrays(snap: Dictionary) -> Dictionary:
	var opq := _new_bucket()
	var trn := _new_bucket()
	var liq := _new_bucket()
	if snap.is_empty():
		return {"cpos": Vector3i.ZERO, "opaque": opq, "transparent": trn, "liquid": liq}

	var pb: PackedInt32Array = snap["blocks"]
	var pl: PackedByteArray = snap["light"]
	var pq: PackedByteArray = snap["liquid"]
	var lm: PackedFloat32Array = snap["light_map"]
	var ol: PackedByteArray = snap["opaque_lut"]
	var rl: PackedByteArray = snap["render_lut"]
	var layer_base: PackedInt32Array = snap["layer_base"]
	var emit: PackedFloat32Array = snap["emission"]
	var tint: PackedColorArray = snap["tint"]

	_greedy_pass(pb, pl, ol, rl, lm, layer_base, emit, tint, opq, trn)
	_special_pass(pb, pl, pq, ol, rl, lm, layer_base, emit, tint, trn, liq)

	return {"cpos": snap["cpos"], "opaque": opq, "transparent": trn, "liquid": liq}


static func _new_bucket() -> Array:
	return [
		PackedVector3Array(), PackedVector3Array(), PackedVector2Array(),
		PackedVector2Array(), PackedColorArray(), PackedInt32Array(),
	]


## Turn a bucket into an `ArrayMesh`, or `null` when it holds no geometry.
## Must run on the main thread.
static func arrays_to_mesh(bucket: Array) -> ArrayMesh:
	var verts: PackedVector3Array = bucket[B_VERT]
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = bucket[B_NORM]
	arrays[Mesh.ARRAY_TEX_UV] = bucket[B_UV]
	arrays[Mesh.ARRAY_TEX_UV2] = bucket[B_UV2]
	arrays[Mesh.ARRAY_COLOR] = bucket[B_COL]
	arrays[Mesh.ARRAY_INDEX] = bucket[B_IDX]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ================================================================ greedy faces
static func _greedy_pass(pb: PackedInt32Array, pl: PackedByteArray, ol: PackedByteArray,
		rl: PackedByteArray, lm: PackedFloat32Array, layer_base: PackedInt32Array,
		emit: PackedFloat32Array, tint: PackedColorArray, opq: Array, trn: Array) -> void:
	var mask_p := PackedInt64Array()
	var mask_n := PackedInt64Array()
	mask_p.resize(256)
	mask_n.resize(256)

	for d in 3:
		var u: int = (d + 1) % 3
		var v: int = (d + 2) % 3
		var sd: int = STRIDE[d]
		var su: int = STRIDE[u]
		var sv: int = STRIDE[v]
		# Plane `i` separates the voxel at local d == i-1 from the one at d == i.
		for i in S + 1:
			mask_p.fill(0)
			mask_n.fill(0)
			var any := false
			var slice_base := ORIGIN_I + i * sd
			for b in S:
				var row := slice_base + b * sv
				for a in S:
					var ib := row + a * su
					var ia := ib - sd
					var bid := pb[ib]
					var aid := pb[ia]
					# Identical voxels never produce a face between them; this
					# fast path covers almost every cell in a real chunk.
					if aid == bid:
						continue
					var a_op: bool = ol[aid] != 0
					var b_op: bool = ol[bid] != 0
					if a_op and b_op:
						continue
					var mi := b * S + a
					if i >= 1 and aid != 0 and not b_op and rl[aid] <= 1:
						mask_p[mi] = _face_key(pb, pl, ol, lm, ib, su, sv, aid)
						any = true
					if i <= S - 1 and bid != 0 and not a_op and rl[bid] <= 1:
						mask_n[mi] = _face_key(pb, pl, ol, lm, ia, su, sv, bid)
						any = true
			if not any:
				continue
			_emit_mask(mask_p, 1, d, u, v, i, rl, layer_base, emit, tint, opq, trn)
			_emit_mask(mask_n, -1, d, u, v, i, rl, layer_base, emit, tint, opq, trn)


## Pack (block id, four AO levels, four quantised light levels) into one 64-bit
## key. Two mask cells merge only when their keys match exactly, which makes the
## merged quad's corner values provably correct.
static func _face_key(pb: PackedInt32Array, pl: PackedByteArray, ol: PackedByteArray,
		lm: PackedFloat32Array, front: int, su: int, sv: int, bid: int) -> int:
	var lf: float = lm[pl[front]]
	if not ao_enabled:
		var q := int(clampf(lf, 0.0, 1.0) * 15.0 + 0.5)
		return bid | (3 << 16) | (3 << 18) | (3 << 20) | (3 << 22) \
			| (q << 24) | (q << 28) | (q << 32) | (q << 36)
	var c0 := _corner(pb, pl, ol, lm, front, -su, -sv, lf)
	var c1 := _corner(pb, pl, ol, lm, front, -su, sv, lf)
	var c2 := _corner(pb, pl, ol, lm, front, su, sv, lf)
	var c3 := _corner(pb, pl, ol, lm, front, su, -sv, lf)
	return bid \
		| ((c0 >> 4) << 16) | ((c1 >> 4) << 18) | ((c2 >> 4) << 20) | ((c3 >> 4) << 22) \
		| ((c0 & 15) << 24) | ((c1 & 15) << 28) | ((c2 & 15) << 32) | ((c3 & 15) << 36)


## Ambient occlusion + smooth light for one face corner. `o_u` / `o_v` are the
## signed padded-array offsets toward that corner. Returns `(ao << 4) | light`.
static func _corner(pb: PackedInt32Array, pl: PackedByteArray, ol: PackedByteArray,
		lm: PackedFloat32Array, front: int, o_u: int, o_v: int, lf: float) -> int:
	var i1 := front + o_u
	var i2 := front + o_v
	var i3 := i1 + o_v
	var s1: int = ol[pb[i1]]
	var s2: int = ol[pb[i2]]
	var s3: int = ol[pb[i3]]
	# The classic voxel AO rule: two blocking sides fully close the corner.
	var ao := 0 if (s1 == 1 and s2 == 1) else 3 - (s1 + s2 + s3)
	var total := lf
	var count := 1
	if s1 == 0:
		total += lm[pl[i1]]
		count += 1
	if s2 == 0:
		total += lm[pl[i2]]
		count += 1
	if s3 == 0:
		total += lm[pl[i3]]
		count += 1
	return (ao << 4) | int(clampf(total / float(count), 0.0, 1.0) * 15.0 + 0.5)


## Greedily merge equal-keyed mask cells into quads and emit them.
static func _emit_mask(mask: PackedInt64Array, sgn: int, d: int, u: int, v: int, plane: int,
		rl: PackedByteArray, layer_base: PackedInt32Array, emit: PackedFloat32Array,
		tint: PackedColorArray, opq: Array, trn: Array) -> void:
	var axis_d: Vector3 = AXIS[d]
	var axis_u: Vector3 = AXIS[u]
	var axis_v: Vector3 = AXIS[v]
	var group := 0
	if d == 1:
		group = 1 if sgn > 0 else 2
	var shades := PackedFloat32Array()
	shades.resize(4)

	for j in S:
		var a := 0
		while a < S:
			var key: int = mask[j * S + a]
			if key == 0:
				a += 1
				continue
			# Extend along U while the key is identical...
			var w := 1
			while a + w < S and mask[j * S + a + w] == key:
				w += 1
			# ...then along V, one full row at a time.
			var h := 1
			var growing := true
			while j + h < S and growing:
				var rb := (j + h) * S + a
				for q in w:
					if mask[rb + q] != key:
						growing = false
						break
				if growing:
					h += 1
			for hh in h:
				var rb2 := (j + hh) * S + a
				for ww in w:
					mask[rb2 + ww] = 0

			var bid := key & 0xFFFF
			for c in 4:
				var ao: int = (key >> (16 + c * 2)) & 3
				var lq: int = (key >> (24 + c * 4)) & 15
				shades[c] = float(AO_FACTOR[ao]) * (float(lq) / 15.0)
			var bucket: Array = opq if rl[bid] == 0 else trn
			_add_quad(bucket, axis_d, axis_u, axis_v, d, sgn,
				axis_d * float(plane) + axis_u * float(a) + axis_v * float(j),
				float(w), float(h),
				float(layer_base[bid] + group), emit[bid], tint[bid], shades)
			a += w


# ============================================== cross quads and liquid volumes
static func _special_pass(pb: PackedInt32Array, pl: PackedByteArray, pq: PackedByteArray,
		ol: PackedByteArray, rl: PackedByteArray, lm: PackedFloat32Array,
		layer_base: PackedInt32Array, emit: PackedFloat32Array, tint: PackedColorArray,
		trn: Array, liq: Array) -> void:
	for ly in S:
		for lz in S:
			var row := ORIGIN_I + ly * PS_SQ + lz * PS
			for lx in S:
				var pi := row + lx
				var id := pb[pi]
				if id == 0:
					continue
				var mode: int = rl[id]
				if mode == 2:
					_add_cross(trn, lx, ly, lz, pi, id, pl, lm, layer_base, emit, tint)
				elif mode == 3:
					_add_liquid(liq, lx, ly, lz, pi, id, pb, pl, pq, ol, lm,
						layer_base, emit, tint)


static func _add_cross(bucket: Array, lx: int, ly: int, lz: int, pi: int, id: int,
		pl: PackedByteArray, lm: PackedFloat32Array, layer_base: PackedInt32Array,
		emit: PackedFloat32Array, tint: PackedColorArray) -> void:
	var sh: float = lm[pl[pi]]
	var layer := float(layer_base[id])
	var e := CROSS_INSET
	var x := float(lx)
	var y := float(ly)
	var z := float(lz)
	# Two quads on the voxel's diagonals, each emitted front and back so plants
	# read from every one of the four viewing planes.
	_cross_quad(bucket, Vector3(x + e, y, z + e), Vector3(x + 1.0 - e, y, z + 1.0 - e),
		layer, emit[id], tint[id], sh)
	_cross_quad(bucket, Vector3(x + 1.0 - e, y, z + e), Vector3(x + e, y, z + 1.0 - e),
		layer, emit[id], tint[id], sh)


static func _cross_quad(bucket: Array, a: Vector3, b: Vector3, layer: float, emit: float,
		tint: Color, sh: float) -> void:
	var p0 := a
	var p1 := a + Vector3.UP
	var p2 := b + Vector3.UP
	var p3 := b
	var nrm := (b - a).cross(Vector3.UP).normalized()
	if not nrm.is_finite():
		nrm = Vector3.BACK
	var col := Color(tint.r * sh, tint.g * sh, tint.b * sh, sh)
	var verts: PackedVector3Array = bucket[B_VERT]
	var norms: PackedVector3Array = bucket[B_NORM]
	var uvs: PackedVector2Array = bucket[B_UV]
	var uv2s: PackedVector2Array = bucket[B_UV2]
	var cols: PackedColorArray = bucket[B_COL]
	var idx: PackedInt32Array = bucket[B_IDX]
	for side in 2:
		var n := nrm if side == 0 else -nrm
		var base := verts.size()
		verts.append(p0); verts.append(p1); verts.append(p2); verts.append(p3)
		for _k in 4:
			norms.append(n)
			uv2s.append(Vector2(layer, emit))
			cols.append(col)
		uvs.append(Vector2(0.0, 1.0))
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(1.0, 1.0))
		if side == 0:
			idx.append(base); idx.append(base + 1); idx.append(base + 2)
			idx.append(base); idx.append(base + 2); idx.append(base + 3)
		else:
			idx.append(base); idx.append(base + 2); idx.append(base + 1)
			idx.append(base); idx.append(base + 3); idx.append(base + 2)


static func _add_liquid(bucket: Array, lx: int, ly: int, lz: int, pi: int, id: int,
		pb: PackedInt32Array, pl: PackedByteArray, pq: PackedByteArray, ol: PackedByteArray,
		lm: PackedFloat32Array, layer_base: PackedInt32Array, emit: PackedFloat32Array,
		tint: PackedColorArray) -> void:
	var above := pb[pi + PS_SQ]
	var height := 1.0
	if above != id:
		var level: int = pq[pi]
		if level <= 0:
			level = Const.MAX_LIQUID
		height = clampf(float(level) / float(Const.MAX_LIQUID), 0.125, 1.0)
	var sh: float = maxf(lm[pl[pi]], 0.25)
	var shades := PackedFloat32Array([sh, sh, sh, sh])
	var col := tint[id]
	var e: float = emit[id]
	var x := float(lx)
	var y := float(ly)
	var z := float(lz)
	var base_layer := layer_base[id]
	var ax: Vector3 = AXIS[0]
	var ay: Vector3 = AXIS[1]
	var az: Vector3 = AXIS[2]

	# Top surface, lowered to the fill level so shallow water reads as shallow.
	if above != id and ol[above] == 0:
		_add_quad(bucket, ay, az, ax, 1, 1, Vector3(x, y + height, z),
			1.0, 1.0, float(base_layer + 1), e, col, shades)
	var below := pb[pi - PS_SQ]
	if below != id and ol[below] == 0:
		_add_quad(bucket, ay, az, ax, 1, -1, Vector3(x, y, z),
			1.0, 1.0, float(base_layer + 2), e, col, shades)
	# Walls run from the voxel floor up to the fill level.
	var px := pb[pi + 1]
	if px != id and ol[px] == 0:
		_add_quad(bucket, ax, ay, az, 0, 1, Vector3(x + 1.0, y, z),
			height, 1.0, float(base_layer), e, col, shades)
	var nx := pb[pi - 1]
	if nx != id and ol[nx] == 0:
		_add_quad(bucket, ax, ay, az, 0, -1, Vector3(x, y, z),
			height, 1.0, float(base_layer), e, col, shades)
	var pz := pb[pi + PS]
	if pz != id and ol[pz] == 0:
		_add_quad(bucket, az, ax, ay, 2, 1, Vector3(x, y, z + 1.0),
			1.0, height, float(base_layer), e, col, shades)
	var nz := pb[pi - PS]
	if nz != id and ol[nz] == 0:
		_add_quad(bucket, az, ax, ay, 2, -1, Vector3(x, y, z),
			1.0, height, float(base_layer), e, col, shades)


# ================================================================ quad writer
## Append one axis-aligned quad.
##
## `origin` is the (0,0) corner in the face's own (U, V) frame, chosen so that
## `U x V == +D`. Godot treats clockwise-as-seen-from-the-front as front-facing,
## so the +D winding walks 00 -> 01 -> 11 -> 10 and the -D winding reverses it.
## `shades[]` holds light*AO at the four corners in that same 00/01/11/10 order.
static func _add_quad(bucket: Array, axis_d: Vector3, axis_u: Vector3, axis_v: Vector3,
		d: int, sgn: int, origin: Vector3, wu: float, wv: float,
		layer: float, emit: float, tint: Color, shades: PackedFloat32Array) -> void:
	var pu := axis_u * wu
	var pv := axis_v * wv
	var c00 := origin
	var c01 := origin + pv
	var c11 := origin + pu + pv
	var c10 := origin + pu

	# Texture orientation: keep world +Y pointing up on the side faces. UVs are
	# in whole tiles, so a greedy quad repeats its tile instead of stretching it.
	var t00: Vector2
	var t01: Vector2
	var t11: Vector2
	var t10: Vector2
	if d == 0:
		# U = Y (screen up), V = Z (screen across).
		t00 = Vector2(0.0, 0.0); t01 = Vector2(wv, 0.0)
		t11 = Vector2(wv, -wu); t10 = Vector2(0.0, -wu)
	elif d == 1:
		# U = Z, V = X: the top face is textured in the world XZ plane.
		t00 = Vector2(0.0, 0.0); t01 = Vector2(wv, 0.0)
		t11 = Vector2(wv, wu); t10 = Vector2(0.0, wu)
	else:
		# U = X (screen across), V = Y (screen up).
		t00 = Vector2(0.0, 0.0); t01 = Vector2(0.0, -wv)
		t11 = Vector2(wu, -wv); t10 = Vector2(wu, 0.0)

	var nrm := axis_d * float(sgn)
	var verts: PackedVector3Array = bucket[B_VERT]
	var norms: PackedVector3Array = bucket[B_NORM]
	var uvs: PackedVector2Array = bucket[B_UV]
	var uv2s: PackedVector2Array = bucket[B_UV2]
	var cols: PackedColorArray = bucket[B_COL]
	var idx: PackedInt32Array = bucket[B_IDX]
	var base := verts.size()

	var s0: float = shades[0]
	var s1: float = shades[1]
	var s2: float = shades[2]
	var s3: float = shades[3]
	if sgn > 0:
		verts.append(c00); verts.append(c01); verts.append(c11); verts.append(c10)
		uvs.append(t00); uvs.append(t01); uvs.append(t11); uvs.append(t10)
	else:
		verts.append(c00); verts.append(c10); verts.append(c11); verts.append(c01)
		uvs.append(t00); uvs.append(t10); uvs.append(t11); uvs.append(t01)
		var tmp := s1
		s1 = s3
		s3 = tmp
	cols.append(Color(tint.r * s0, tint.g * s0, tint.b * s0, s0))
	cols.append(Color(tint.r * s1, tint.g * s1, tint.b * s1, s1))
	cols.append(Color(tint.r * s2, tint.g * s2, tint.b * s2, s2))
	cols.append(Color(tint.r * s3, tint.g * s3, tint.b * s3, s3))
	for _k in 4:
		norms.append(nrm)
		uv2s.append(Vector2(layer, emit))

	# Split along the brighter diagonal, otherwise strong AO produces a visible
	# seam running the wrong way across the quad.
	if s0 + s2 > s1 + s3:
		idx.append(base); idx.append(base + 1); idx.append(base + 3)
		idx.append(base + 1); idx.append(base + 2); idx.append(base + 3)
	else:
		idx.append(base); idx.append(base + 1); idx.append(base + 2)
		idx.append(base); idx.append(base + 2); idx.append(base + 3)
