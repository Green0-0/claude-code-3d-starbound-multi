## Versioned container format used by every byte Planeshift writes to disk.
##
## A payload is always a `Dictionary`. `encode()` wraps it in a fixed 24-byte
## header (magic, version, flags, sizes, checksum) and either a compact binary
## body (`var_to_bytes` + zstd) or a human-readable JSON body behind a debug
## flag. `decode()` validates the header and checksum, then runs the migration
## chain so a save written by an older build still loads.
##
## Nothing here touches the scene tree, so it is safe to call from a
## `WorkerThreadPool` task.
class_name SavCodec
extends RefCounted

## ASCII "PSAV".
static var MAGIC := PackedByteArray([80, 83, 65, 86])

## Bump this whenever the *shape* of the save dictionary changes, and add a
## matching `migrate_vN_to_vN1` static below.
const SAVE_VERSION := 3

const HEADER_SIZE := 24

## Body is UTF-8 JSON rather than `var_to_bytes`.
const FLAG_JSON := 1
## Body is zstd-compressed.
const FLAG_ZSTD := 2

## Do not bother compressing tiny payloads.
const COMPRESS_THRESHOLD := 512

## When true every save is written as indented JSON instead of packed binary.
## Invaluable while nineteen other modules are still finding their own state
## shape. Driven by `SavSettings` (`debug/json_saves`) or `--save-json`.
static var debug_json := false

## Set by `decode()` so callers can report *why* a load failed.
static var last_error := ""


# ============================================================ public interface
## Encode `data` into a self-describing byte buffer.
## `as_json`: -1 follow `debug_json`, 0 force binary, 1 force JSON.
static func encode(data: Dictionary, as_json: int = -1) -> PackedByteArray:
	var use_json := debug_json if as_json < 0 else (as_json == 1)
	var payload: Dictionary = data.duplicate()
	payload["version"] = SAVE_VERSION

	var body: PackedByteArray
	var flags := 0
	if use_json:
		body = JSON.stringify(to_json_safe(payload), "\t").to_utf8_buffer()
		flags |= FLAG_JSON
	else:
		body = var_to_bytes(payload)

	var raw_len := body.size()
	if raw_len >= COMPRESS_THRESHOLD and not use_json:
		var comp := body.compress(FileAccess.COMPRESSION_ZSTD)
		if not comp.is_empty() and comp.size() < raw_len:
			body = comp
			flags |= FLAG_ZSTD

	var out := PackedByteArray()
	out.resize(HEADER_SIZE)
	for i in 4:
		out[i] = MAGIC[i]
	out.encode_u16(4, SAVE_VERSION)
	out.encode_u16(6, flags)
	out.encode_u32(8, raw_len)
	out.encode_u32(12, body.size())
	out.encode_u32(16, checksum(body))
	out.encode_u32(20, 0)
	out.append_array(body)
	return out


## Decode a buffer produced by `encode()`.
## Returns `{ok, error, version, json, data}`; `data` is empty when `ok` is
## false. Never throws — a corrupt file is a reported failure, not a crash.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE:
		return _fail("truncated: %d bytes, need at least %d" % [bytes.size(), HEADER_SIZE])
	for i in 4:
		if bytes[i] != MAGIC[i]:
			return _fail("bad magic (not a Planeshift save)")

	var version := bytes.decode_u16(4)
	var flags := bytes.decode_u16(6)
	var raw_len := bytes.decode_u32(8)
	var body_len := bytes.decode_u32(12)
	var want_sum := bytes.decode_u32(16)

	if bytes.size() < HEADER_SIZE + body_len:
		return _fail("truncated body: header claims %d bytes, file holds %d"
			% [body_len, bytes.size() - HEADER_SIZE])

	var body := bytes.slice(HEADER_SIZE, HEADER_SIZE + body_len)
	if checksum(body) != want_sum:
		return _fail("checksum mismatch — the file is damaged")

	if flags & FLAG_ZSTD:
		var dec := body.decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
		if dec.size() != raw_len:
			return _fail("decompression failed (expected %d bytes, got %d)" % [raw_len, dec.size()])
		body = dec

	var parsed: Variant = null
	if flags & FLAG_JSON:
		var text := body.get_string_from_utf8()
		var j: Variant = JSON.parse_string(text)
		if j == null:
			return _fail("JSON body did not parse")
		parsed = from_json_safe(j)
	else:
		parsed = bytes_to_var(body)

	if not (parsed is Dictionary):
		return _fail("payload is not a Dictionary")

	var data: Dictionary = parsed
	if version > SAVE_VERSION:
		return _fail("save version %d is newer than this build (%d)" % [version, SAVE_VERSION])
	var migrated := migrate(data, version)
	last_error = ""
	return {
		"ok": true, "error": "", "version": version,
		"json": bool(flags & FLAG_JSON), "data": migrated,
	}


static func _fail(msg: String) -> Dictionary:
	last_error = msg
	return {"ok": false, "error": msg, "version": 0, "json": false, "data": {}}


## Peek at the version of a buffer without decoding the body.
static func peek_version(bytes: PackedByteArray) -> int:
	if bytes.size() < HEADER_SIZE:
		return 0
	for i in 4:
		if bytes[i] != MAGIC[i]:
			return 0
	return bytes.decode_u16(4)


## Stable 32-bit content checksum. Uses the engine's native buffer hash so it
## stays O(1) in GDScript terms — a hand-rolled FNV loop over a multi-megabyte
## save would cost seconds.
static func checksum(b: PackedByteArray) -> int:
	return hash(b) & 0xFFFFFFFF


# ================================================================= migrations
## Walk `data` forward from `from_version` to `SAVE_VERSION`.
static func migrate(data: Dictionary, from_version: int) -> Dictionary:
	var d := data
	var v := maxi(from_version, 1)
	while v < SAVE_VERSION:
		match v:
			1: d = migrate_v1_to_v2(d)
			2: d = migrate_v2_to_v3(d)
			_:
				push_warning("[SavCodec] no migration from v%d — loading as-is" % v)
				break
		v += 1
	d["version"] = SAVE_VERSION
	return d


## v1 kept every module's state as a flat top-level key and called the player
## section `player_state`. v2 nests them under `sections`.
static func migrate_v1_to_v2(d: Dictionary) -> Dictionary:
	if d.has("sections"):
		return d
	var sections := {}
	for k: String in ["game", "view", "universe", "quests", "status", "tech", "inv"]:
		if d.has(k):
			sections[k] = d[k]
			d.erase(k)
	if d.has("player_state"):
		sections["player"] = d["player_state"]
		d.erase("player_state")
	d["sections"] = sections
	return d


## v2 called the inventory section `inv` and had no entity/object registries.
static func migrate_v2_to_v3(d: Dictionary) -> Dictionary:
	var sections: Dictionary = d.get("sections", {})
	if sections.has("inv") and not sections.has("inventory"):
		sections["inventory"] = sections["inv"]
		sections.erase("inv")
	for k: String in ["objects", "entities"]:
		if not sections.has(k):
			sections[k] = {}
	d["sections"] = sections
	if not d.has("meta"):
		d["meta"] = {}
	return d


# ============================================================ JSON conversion
## JSON has no ints, no packed arrays and no non-string dictionary keys, so the
## debug path tags the types it cannot express natively.
static func to_json_safe(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var all_string := true
			for k: Variant in d:
				if not (k is String):
					all_string = false
					break
			if all_string:
				var out := {}
				for k: Variant in d:
					out[k] = to_json_safe(d[k])
				return out
			var pairs: Array = []
			for k: Variant in d:
				pairs.append([to_json_safe(k), to_json_safe(d[k])])
			return {"__d": pairs}
		TYPE_ARRAY:
			var arr: Array = []
			for e: Variant in (v as Array):
				arr.append(to_json_safe(e))
			return arr
		TYPE_PACKED_BYTE_ARRAY:
			return {"__b": Marshalls.raw_to_base64(v)}
		TYPE_PACKED_INT32_ARRAY:
			return {"__i32": Marshalls.raw_to_base64((v as PackedInt32Array).to_byte_array())}
		TYPE_PACKED_FLOAT32_ARRAY:
			return {"__f32": Marshalls.raw_to_base64((v as PackedFloat32Array).to_byte_array())}
		TYPE_STRING_NAME:
			return {"__sn": String(v)}
		TYPE_VECTOR2:
			return {"__v2": [(v as Vector2).x, (v as Vector2).y]}
		TYPE_VECTOR2I:
			return {"__v2i": [(v as Vector2i).x, (v as Vector2i).y]}
		TYPE_VECTOR3:
			return {"__v3": [(v as Vector3).x, (v as Vector3).y, (v as Vector3).z]}
		TYPE_VECTOR3I:
			return {"__v3i": [(v as Vector3i).x, (v as Vector3i).y, (v as Vector3i).z]}
		TYPE_COLOR:
			var c: Color = v
			return {"__col": [c.r, c.g, c.b, c.a]}
		_:
			return v


## Inverse of `to_json_safe`.
static func from_json_safe(v: Variant) -> Variant:
	if v is Array:
		var arr: Array = []
		for e: Variant in (v as Array):
			arr.append(from_json_safe(e))
		return arr
	if not (v is Dictionary):
		return v
	var d: Dictionary = v
	if d.size() == 1:
		if d.has("__b"):
			return Marshalls.base64_to_raw(str(d["__b"]))
		if d.has("__i32"):
			return Marshalls.base64_to_raw(str(d["__i32"])).to_int32_array()
		if d.has("__f32"):
			return Marshalls.base64_to_raw(str(d["__f32"])).to_float32_array()
		if d.has("__sn"):
			return StringName(str(d["__sn"]))
		if d.has("__v2"):
			var a2: Array = d["__v2"]
			return Vector2(a2[0], a2[1])
		if d.has("__v2i"):
			var b2: Array = d["__v2i"]
			return Vector2i(int(b2[0]), int(b2[1]))
		if d.has("__v3"):
			var a3: Array = d["__v3"]
			return Vector3(a3[0], a3[1], a3[2])
		if d.has("__v3i"):
			var b3: Array = d["__v3i"]
			return Vector3i(int(b3[0]), int(b3[1]), int(b3[2]))
		if d.has("__col"):
			var c: Array = d["__col"]
			return Color(c[0], c[1], c[2], c[3])
		if d.has("__d"):
			var out := {}
			for pair: Variant in (d["__d"] as Array):
				var p: Array = pair
				out[from_json_safe(p[0])] = from_json_safe(p[1])
			return out
	var plain := {}
	for k: Variant in d:
		plain[k] = from_json_safe(d[k])
	return plain


# ================================================================ file helpers
## Write `data` to `path` through a temp file + atomic rename, keeping the
## previous good copy as `path + ".bak"`. An interrupted write can therefore
## never destroy a working save.
static func write_atomic(path: String, data: Dictionary, as_json: int = -1) -> bool:
	var bytes := encode(data, as_json)
	return write_bytes_atomic(path, bytes)


## As `write_atomic` but for an already-encoded buffer.
static func write_bytes_atomic(path: String, bytes: PackedByteArray) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			push_error("[SavCodec] cannot create %s: %s" % [dir, error_string(mk)])
			return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[SavCodec] cannot open %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_buffer(bytes)
	f.flush()
	f.close()
	# Verify the temp file before it is allowed to replace anything.
	var check := FileAccess.open(tmp, FileAccess.READ)
	if check == null or check.get_length() != bytes.size():
		if check != null:
			check.close()
		push_error("[SavCodec] temp write verification failed for %s" % tmp)
		DirAccess.remove_absolute(tmp)
		return false
	check.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[SavCodec] atomic rename failed: %s" % error_string(err))
		return false
	return true


## Read and decode `path`, silently falling back to `path + ".bak"` when the
## primary file is missing or damaged.
static func read_with_fallback(path: String) -> Dictionary:
	var r := _read_one(path)
	if r["ok"]:
		return r
	var bak := path + ".bak"
	if FileAccess.file_exists(bak):
		push_warning("[SavCodec] %s unusable (%s) — falling back to backup" % [path, r["error"]])
		var b := _read_one(bak)
		if b["ok"]:
			b["from_backup"] = true
			return b
	return r


static func _read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "no such file: %s" % path, "version": 0, "json": false, "data": {}}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": error_string(FileAccess.get_open_error()),
			"version": 0, "json": false, "data": {}}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return decode(bytes)
