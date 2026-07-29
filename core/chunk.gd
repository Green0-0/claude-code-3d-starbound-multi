## A 16x16x16 cube of voxels plus its per-voxel light and liquid data.
## Indexing is `(y << 8) | (z << 4) | x` everywhere in the project.
class_name Chunk
extends RefCounted

const SIZE := Const.CHUNK_SIZE
const VOL := Const.CHUNK_VOL

var cpos: Vector3i
var blocks: PackedInt32Array
## High nibble = skylight, low nibble = block light. One byte per voxel.
var light: PackedByteArray
## 0..8 fill level for liquid voxels; 0 elsewhere.
var liquid: PackedByteArray

var generated := false
var populated := false      ## structures / ores / decorations placed
var lit := false            ## initial light flood done
var dirty := true           ## needs a mesh rebuild
var empty := true           ## all air — cheap early-out for the mesher
var solid_count := 0

## Tile entities living in this chunk: local index -> Dictionary payload.
## Chests, machines, signs, crop growth timers, spawners.
var tile_data: Dictionary = {}


func _init(p_cpos: Vector3i) -> void:
	cpos = p_cpos
	blocks = PackedInt32Array()
	blocks.resize(VOL)
	light = PackedByteArray()
	light.resize(VOL)
	liquid = PackedByteArray()
	liquid.resize(VOL)


func origin() -> Vector3i:
	return cpos * SIZE


static func index(lx: int, ly: int, lz: int) -> int:
	return (ly << 8) | (lz << 4) | lx


static func index_of(local: Vector3i) -> int:
	return (local.y << 8) | (local.z << 4) | local.x


static func from_index(i: int) -> Vector3i:
	return Vector3i(i & 15, (i >> 8) & 15, (i >> 4) & 15)


func get_local(lx: int, ly: int, lz: int) -> int:
	return blocks[(ly << 8) | (lz << 4) | lx]


func set_local(lx: int, ly: int, lz: int, id: int) -> void:
	var i := (ly << 8) | (lz << 4) | lx
	var old := blocks[i]
	if old == id:
		return
	if old != Const.AIR:
		solid_count -= 1
	if id != Const.AIR:
		solid_count += 1
	blocks[i] = id
	empty = solid_count <= 0
	dirty = true


func get_at(i: int) -> int:
	return blocks[i]


func set_at(i: int, id: int) -> void:
	var old := blocks[i]
	if old == id:
		return
	if old != Const.AIR:
		solid_count -= 1
	if id != Const.AIR:
		solid_count += 1
	blocks[i] = id
	empty = solid_count <= 0
	dirty = true


## Bulk write used by the generator — skips per-voxel bookkeeping, then fixes
## the counters once at the end.
func fill_raw(data: PackedInt32Array) -> void:
	blocks = data
	recount()


func recount() -> void:
	solid_count = 0
	for i in VOL:
		if blocks[i] != Const.AIR:
			solid_count += 1
	empty = solid_count <= 0
	dirty = true


# ---------------------------------------------------------------------- light
func sky_light(i: int) -> int:
	return light[i] >> 4


func block_light(i: int) -> int:
	return light[i] & 15


func set_sky_light(i: int, v: int) -> void:
	light[i] = ((v & 15) << 4) | (light[i] & 15)


func set_block_light(i: int, v: int) -> void:
	light[i] = (light[i] & 240) | (v & 15)


## Combined 0..15 illumination given the current global daylight factor.
func combined_light(i: int, daylight: float) -> int:
	var b := light[i] & 15
	var s := int(float(light[i] >> 4) * daylight)
	return maxi(b, s)


# --------------------------------------------------------------------- liquid
func liquid_at(i: int) -> int:
	return liquid[i]


func set_liquid(i: int, v: int) -> void:
	liquid[i] = clampi(v, 0, Const.MAX_LIQUID)
	dirty = true


# ----------------------------------------------------------------- tile data
func get_tile_data(i: int) -> Dictionary:
	return tile_data.get(i, {})


func set_tile_data(i: int, d: Dictionary) -> void:
	if d.is_empty():
		tile_data.erase(i)
	else:
		tile_data[i] = d


# --------------------------------------------------------------- persistence
func to_dict() -> Dictionary:
	return {
		"c": [cpos.x, cpos.y, cpos.z],
		"b": var_to_bytes(blocks).compress(FileAccess.COMPRESSION_ZSTD),
		"bn": blocks.size(),
		"l": liquid.compress(FileAccess.COMPRESSION_ZSTD),
		"t": tile_data.duplicate(true),
		"g": generated, "p": populated,
	}


static func from_dict(d: Dictionary) -> Chunk:
	var c := Chunk.new(Vector3i(d["c"][0], d["c"][1], d["c"][2]))
	var raw: PackedByteArray = d["b"]
	var decomp := raw.decompress(int(d.get("bn", Const.CHUNK_VOL)) * 4 + 32, FileAccess.COMPRESSION_ZSTD)
	var arr = bytes_to_var(decomp)
	if arr is PackedInt32Array:
		c.blocks = arr
	var lq: PackedByteArray = d.get("l", PackedByteArray())
	if lq.size() > 0:
		var dl := lq.decompress(Const.CHUNK_VOL, FileAccess.COMPRESSION_ZSTD)
		if dl.size() == Const.CHUNK_VOL:
			c.liquid = dl
	c.tile_data = d.get("t", {})
	c.generated = bool(d.get("g", true))
	c.populated = bool(d.get("p", true))
	c.recount()
	return c
