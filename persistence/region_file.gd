## A Minecraft-style region container: 16x16x16 chunks (4096 slots) in one file.
##
## Layout
## ------
## ```
## 0      "PSRG"                              4 bytes
## 4      version                             u32
## 8      live entry count (informational)    u32
## 12     flags (reserved)                    u32
## 16     slot table: 4096 x 6 x u32          98304 bytes
## 98320  payload heap
## ```
## Each table row is `[offset, length, capacity, raw_size, checksum, flags]`.
## `offset == 0` means the slot is empty. `capacity` is the byte block reserved
## for the slot (length rounded up to `ALIGN`), which is what lets a chunk that
## shrinks or grows slightly be rewritten **in place** instead of leaking heap.
##
## Payloads are `var_to_bytes(Chunk.to_dict())` run through zstd. `to_dict()`
## already zstd-compresses the block array, so the outer pass mostly squeezes
## the tile-data dictionary; it is kept because it is nearly free and makes
## sparsely-edited chunks tiny.
##
## Every read is defensive. A slot whose offset, length or checksum does not
## validate is cleared and reported as missing, which makes the world regenerate
## that chunk from the seed rather than crash. A file whose header is unreadable
## is renamed to `.corrupt` and recreated empty.
##
## Not thread-safe on its own — `SaveManager` owns the mutex.
class_name SavRegion
extends RefCounted

## ASCII "PSRG".
static var MAGIC := PackedByteArray([80, 83, 82, 71])
const VERSION := 1

## Chunks per region edge. 16 => 4096 chunks per file.
const REGION_BITS := 4
const REGION_SIZE := 16
const REGION_MASK := 15
const SLOTS := 4096

const FIELDS := 6
const F_OFF := 0
const F_LEN := 1
const F_CAP := 2
const F_RAW := 3
const F_SUM := 4
const F_FLG := 5

const ENTRY_SIZE := FIELDS * 4          ## 24
const TABLE_BYTES := SLOTS * ENTRY_SIZE ## 98304
const HEADER_SIZE := 16 + TABLE_BYTES   ## 98320

## Heap allocations are rounded up to this, so small edits rewrite in place.
const ALIGN := 256

const PFLAG_ZSTD := 1

## Trigger compaction once dead heap exceeds this share of the file.
const COMPACT_WASTE_RATIO := 0.35
const COMPACT_MIN_WASTE := 256 * 1024

var path: String = ""
var error: String = ""
## Slots dropped because they failed validation this session.
var corrupt_entries := 0

var _file: FileAccess = null
var _table := PackedInt32Array()
var _free: Array[Vector2i] = []     ## (offset, capacity) blocks available for reuse
var _end := HEADER_SIZE             ## append point / logical file length
var _dirty := false
var _live_bytes := 0
var _alloc_bytes := 0


# =================================================================== addressing
## Which region file a chunk position belongs to.
static func region_of(cpos: Vector3i) -> Vector3i:
	return Vector3i(cpos.x >> REGION_BITS, cpos.y >> REGION_BITS, cpos.z >> REGION_BITS)


## Slot index of a chunk inside its region. Same bit layout as `Chunk.index`.
static func slot_of(cpos: Vector3i) -> int:
	return ((cpos.y & REGION_MASK) << 8) | ((cpos.z & REGION_MASK) << 4) | (cpos.x & REGION_MASK)


## Canonical filename for a region, relative to the planet directory.
static func file_name(rpos: Vector3i) -> String:
	return "r.%d.%d.%d.psr" % [rpos.x, rpos.y, rpos.z]


# ==================================================================== lifecycle
## Open (or create) the region file at `p_path`. Returns false only when the
## filesystem refuses us entirely; a corrupt file is repaired, not fatal.
func open_file(p_path: String) -> bool:
	path = p_path
	error = ""
	_table = PackedInt32Array()
	_table.resize(SLOTS * FIELDS)
	var exists := FileAccess.file_exists(path)
	if not exists:
		var dir := path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE_READ)
	if _file == null:
		error = "open failed: %s" % error_string(FileAccess.get_open_error())
		push_error("[SavRegion] %s: %s" % [path, error])
		return false
	if exists and _file.get_length() >= HEADER_SIZE:
		if not _read_header():
			if not _quarantine():
				return false
	else:
		if exists:
			# Existed but is shorter than a header: a half-written file.
			if not _quarantine():
				return false
		else:
			_init_header()
	_rebuild_free_list()
	return true


func is_open() -> bool:
	return _file != null


## Persist the slot table and flush to the OS. Cheap enough to call once per
## write batch; the table is a single 98 KB buffer store.
func commit() -> void:
	if _file == null or not _dirty:
		return
	_file.seek(0)
	_file.store_buffer(MAGIC)
	_file.store_32(VERSION)
	_file.store_32(stored_count())
	_file.store_32(0)
	_file.store_buffer(_table.to_byte_array())
	_file.flush()
	_dirty = false


func close() -> void:
	commit()
	if _file != null:
		_file.close()
		_file = null


# ======================================================================== reads
## Is a chunk stored here? Pure in-memory table lookup, no I/O.
func has_chunk(cpos: Vector3i) -> bool:
	return _table[slot_of(cpos) * FIELDS + F_OFF] != 0


## Every chunk position stored in this region, as local slot indices.
func stored_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in SLOTS:
		if _table[s * FIELDS + F_OFF] != 0:
			out.append(s)
	return out


## Read a chunk payload dictionary. Returns `{}` when absent **or** unreadable —
## the caller regenerates from the seed either way.
func read_chunk(cpos: Vector3i) -> Dictionary:
	if _file == null:
		return {}
	var s := slot_of(cpos)
	var b := s * FIELDS
	var off := _table[b + F_OFF]
	if off == 0:
		return {}
	var ln := _table[b + F_LEN]
	var raw_size := _table[b + F_RAW]
	if off < HEADER_SIZE or ln <= 0 or off + ln > _file.get_length():
		return _drop_slot(s, "entry points outside the file")
	_file.seek(off)
	var store := _file.get_buffer(ln)
	if store.size() != ln:
		return _drop_slot(s, "short read")
	if (SavCodec.checksum(store) & 0x7FFFFFFF) != _table[b + F_SUM]:
		return _drop_slot(s, "checksum mismatch")
	var raw := store
	if _table[b + F_FLG] & PFLAG_ZSTD:
		if raw_size <= 0 or raw_size > 64 * 1024 * 1024:
			return _drop_slot(s, "implausible uncompressed size")
		raw = store.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != raw_size:
			return _drop_slot(s, "zstd decompression failed")
	var v: Variant = bytes_to_var(raw)
	if not (v is Dictionary):
		return _drop_slot(s, "payload is not a Dictionary")
	var d: Dictionary = v
	if not d.has("b") or not d.has("c"):
		return _drop_slot(s, "payload is missing block data")
	return d


# ======================================================================= writes
## Store a chunk payload, reusing the slot's existing heap block when it fits.
func write_chunk(cpos: Vector3i, payload: Dictionary) -> bool:
	if _file == null:
		return false
	var raw := var_to_bytes(payload)
	var store := raw
	var flags := 0
	var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if not comp.is_empty() and comp.size() < raw.size():
		store = comp
		flags = PFLAG_ZSTD
	var need := store.size()
	if need <= 0:
		return false

	var s := slot_of(cpos)
	var b := s * FIELDS
	var off := _table[b + F_OFF]
	var cap := _table[b + F_CAP]
	if off == 0 or cap < need:
		if off != 0:
			_release(off, cap)
			_live_bytes -= _table[b + F_LEN]
		var block := _allocate(need)
		off = block.x
		cap = block.y
	else:
		_live_bytes -= _table[b + F_LEN]

	_file.seek(off)
	_file.store_buffer(store)
	_table[b + F_OFF] = off
	_table[b + F_LEN] = need
	_table[b + F_CAP] = cap
	_table[b + F_RAW] = raw.size()
	_table[b + F_SUM] = SavCodec.checksum(store) & 0x7FFFFFFF
	_table[b + F_FLG] = flags
	_live_bytes += need
	_dirty = true
	return true


## Forget a chunk, returning its heap block to the free list.
func erase_chunk(cpos: Vector3i) -> void:
	var s := slot_of(cpos)
	var b := s * FIELDS
	if _table[b + F_OFF] == 0:
		return
	_release(_table[b + F_OFF], _table[b + F_CAP])
	_live_bytes -= _table[b + F_LEN]
	_clear_slot(s)
	_dirty = true


# =================================================================== compaction
func stored_count() -> int:
	var n := 0
	for s in SLOTS:
		if _table[s * FIELDS + F_OFF] != 0:
			n += 1
	return n


## Bytes of heap that are allocated but hold no live payload.
func wasted_bytes() -> int:
	return maxi(0, (_end - HEADER_SIZE) - _live_bytes)


## Heuristic used by `SaveManager` to schedule a background compaction.
func needs_compaction() -> bool:
	var waste := wasted_bytes()
	if waste < COMPACT_MIN_WASTE:
		return false
	var total := maxi(1, _end - HEADER_SIZE)
	return float(waste) / float(total) > COMPACT_WASTE_RATIO


## Rewrite the file with every live payload packed tightly at the front.
## Builds a fresh file next to the original and atomically swaps it in, so an
## interrupted compaction leaves the original untouched.
func compact() -> bool:
	if _file == null:
		return false
	commit()
	var live: Array = []          ## [slot, bytes, raw, sum, flags]
	for s in SLOTS:
		var b := s * FIELDS
		var off := _table[b + F_OFF]
		if off == 0:
			continue
		var ln := _table[b + F_LEN]
		if off < HEADER_SIZE or ln <= 0 or off + ln > _file.get_length():
			continue
		_file.seek(off)
		var buf := _file.get_buffer(ln)
		if buf.size() != ln:
			continue
		live.append([s, buf, _table[b + F_RAW], _table[b + F_SUM], _table[b + F_FLG]])

	var tmp := path + ".compact"
	var out := FileAccess.open(tmp, FileAccess.WRITE_READ)
	if out == null:
		push_warning("[SavRegion] compaction skipped, cannot open %s" % tmp)
		return false
	var table := PackedInt32Array()
	table.resize(SLOTS * FIELDS)
	var cursor := HEADER_SIZE
	for row: Array in live:
		var s: int = row[0]
		var buf: PackedByteArray = row[1]
		var cap := _align_up(buf.size())
		out.seek(cursor)
		out.store_buffer(buf)
		var b := s * FIELDS
		table[b + F_OFF] = cursor
		table[b + F_LEN] = buf.size()
		table[b + F_CAP] = cap
		table[b + F_RAW] = int(row[2])
		table[b + F_SUM] = int(row[3])
		table[b + F_FLG] = int(row[4])
		cursor += cap
	out.seek(0)
	out.store_buffer(MAGIC)
	out.store_32(VERSION)
	out.store_32(live.size())
	out.store_32(0)
	out.store_buffer(table.to_byte_array())
	out.flush()
	out.close()

	_file.close()
	_file = null
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[SavRegion] compaction rename failed: %s" % error_string(err))
		# Original was already removed; reopen whatever survived.
		open_file(path)
		return false
	_table = table
	_end = cursor
	_live_bytes = 0
	for row: Array in live:
		_live_bytes += int((row[1] as PackedByteArray).size())
	_file = FileAccess.open(path, FileAccess.READ_WRITE)
	if _file == null:
		error = "reopen after compaction failed"
		return false
	_dirty = false
	_rebuild_free_list()
	return true


## Diagnostics for the debug overlay.
func stats() -> Dictionary:
	return {
		"path": path, "slots": stored_count(), "bytes": _end,
		"live": _live_bytes, "wasted": wasted_bytes(),
		"free_blocks": _free.size(), "corrupt": corrupt_entries,
	}


# ====================================================================== internal
func _init_header() -> void:
	_file.seek(0)
	_file.store_buffer(MAGIC)
	_file.store_32(VERSION)
	_file.store_32(0)
	_file.store_32(0)
	_file.store_buffer(_table.to_byte_array())
	_file.flush()
	_end = HEADER_SIZE
	_live_bytes = 0
	_dirty = false


func _read_header() -> bool:
	_file.seek(0)
	var magic := _file.get_buffer(4)
	if magic != MAGIC:
		error = "bad magic"
		return false
	var ver := _file.get_32()
	_file.get_32()   # live count, informational
	_file.get_32()   # flags, reserved
	if ver != VERSION:
		error = "unsupported region version %d" % ver
		return false
	var raw := _file.get_buffer(TABLE_BYTES)
	if raw.size() != TABLE_BYTES:
		error = "truncated slot table"
		return false
	var t := raw.to_int32_array()
	if t.size() != SLOTS * FIELDS:
		error = "malformed slot table"
		return false
	_table = t

	# Validate every entry against the real file length before trusting it.
	var flen := _file.get_length()
	_end = HEADER_SIZE
	_live_bytes = 0
	for s in SLOTS:
		var b := s * FIELDS
		var off := _table[b + F_OFF]
		if off == 0:
			continue
		var ln := _table[b + F_LEN]
		var cap := _table[b + F_CAP]
		# Validate against `ln`, not `cap`. `cap` is the *aligned* reservation
		# used by the allocator for in-place rewrites; only `ln` bytes are ever
		# written. The final block in the file therefore ends at `off + ln`, and
		# checking `off + cap` would discard the most recently written chunk in
		# every region on reload.
		if off < HEADER_SIZE or ln <= 0 or cap < ln or off + ln > flen:
			_clear_slot(s)
			corrupt_entries += 1
			_dirty = true
			continue
		_live_bytes += ln
		_end = maxi(_end, off + cap)
	if corrupt_entries > 0:
		push_warning("[SavRegion] %s: dropped %d unreadable entries" % [path, corrupt_entries])
	return true


## The header itself is unusable: preserve the file for forensics and start
## clean rather than taking the whole planet down with it.
func _quarantine() -> bool:
	push_warning("[SavRegion] %s is corrupt (%s) — quarantining" % [path, error])
	if _file != null:
		_file.close()
		_file = null
	var dead := path + ".corrupt"
	if FileAccess.file_exists(dead):
		DirAccess.remove_absolute(dead)
	DirAccess.rename_absolute(path, dead)
	_table = PackedInt32Array()
	_table.resize(SLOTS * FIELDS)
	corrupt_entries += 1
	_file = FileAccess.open(path, FileAccess.WRITE_READ)
	if _file == null:
		error = "cannot recreate after quarantine"
		return false
	error = ""
	_init_header()
	return true


func _drop_slot(s: int, why: String) -> Dictionary:
	var b := s * FIELDS
	push_warning("[SavRegion] %s slot %d unreadable (%s) — chunk will regenerate" % [path, s, why])
	_release(_table[b + F_OFF], _table[b + F_CAP])
	_live_bytes -= maxi(0, _table[b + F_LEN])
	_clear_slot(s)
	corrupt_entries += 1
	_dirty = true
	return {}


func _clear_slot(s: int) -> void:
	var b := s * FIELDS
	for i in FIELDS:
		_table[b + i] = 0


static func _align_up(n: int) -> int:
	return ((n + ALIGN - 1) / ALIGN) * ALIGN


func _release(off: int, cap: int) -> void:
	if off <= 0 or cap <= 0:
		return
	if off + cap >= _end:
		# Trailing block: just shrink the heap instead of fragmenting it.
		_end = off
		_coalesce_tail()
		return
	_free.append(Vector2i(off, cap))
	_merge_free()


## Best-fit allocation from the free list, falling back to appending.
func _allocate(need: int) -> Vector2i:
	var want := _align_up(need)
	var best := -1
	var best_cap := 0x7FFFFFFF
	for i in _free.size():
		var cap := _free[i].y
		if cap >= want and cap < best_cap:
			best = i
			best_cap = cap
	if best >= 0:
		var block := _free[best]
		_free.remove_at(best)
		# Split anything substantially larger than we need back onto the list.
		if block.y - want >= ALIGN * 2:
			_free.append(Vector2i(block.x + want, block.y - want))
			block.y = want
		_alloc_bytes += block.y
		return block
	var off := _end
	_end += want
	_alloc_bytes += want
	return Vector2i(off, want)


func _merge_free() -> void:
	if _free.size() < 2:
		return
	_free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var merged: Array[Vector2i] = []
	var cur := _free[0]
	for i in range(1, _free.size()):
		var nxt := _free[i]
		if cur.x + cur.y == nxt.x:
			cur.y += nxt.y
		else:
			merged.append(cur)
			cur = nxt
	merged.append(cur)
	_free = merged
	_coalesce_tail()


## Drop any free block that now sits at the very end of the heap.
func _coalesce_tail() -> void:
	var changed := true
	while changed:
		changed = false
		for i in _free.size():
			if _free[i].x + _free[i].y >= _end:
				_end = mini(_end, _free[i].x)
				_free.remove_at(i)
				changed = true
				break
	_end = maxi(_end, HEADER_SIZE)


func _rebuild_free_list() -> void:
	_free.clear()
	var live: Array[Vector2i] = []
	for s in SLOTS:
		var b := s * FIELDS
		if _table[b + F_OFF] != 0:
			live.append(Vector2i(_table[b + F_OFF], _table[b + F_CAP]))
	live.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var cursor := HEADER_SIZE
	for blk: Vector2i in live:
		if blk.x > cursor:
			_free.append(Vector2i(cursor, blk.x - cursor))
		cursor = maxi(cursor, blk.x + blk.y)
	_end = maxi(cursor, HEADER_SIZE)
	_alloc_bytes = _end - HEADER_SIZE
	_merge_free()
