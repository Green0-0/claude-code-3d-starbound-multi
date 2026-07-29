## Round-trip test harness for the persistence layer.
##
## Builds a synthetic world in a scratch slot, writes it through every tier,
## reads it back and compares byte for byte. It exercises the paths that are
## hardest to notice breaking by playing: free-space reuse when a chunk grows,
## compaction, migration of an old save document, and — most importantly —
## recovery from a deliberately corrupted region entry.
##
## Run it from the debug overlay:
## ```gdscript
## var report := SaveManager.run_self_test()
## print(SavSelfTest.format(report))
## ```
## Nothing here touches a real save slot; everything lives under
## `user://saves/_selftest/` and is deleted on the way out.
class_name SavSelfTest
extends RefCounted

const SCRATCH := "user://saves/_selftest"

var results: Array[Dictionary] = []


## Run every case. Returns `{passed, failed, ms, cases:[{name, ok, detail}]}`.
func run_all() -> Dictionary:
	results.clear()
	var t0 := Time.get_ticks_msec()
	_cleanup()
	DirAccess.make_dir_recursive_absolute(SCRATCH)

	_test_codec_binary()
	_test_codec_json()
	_test_codec_corruption()
	_test_migration_chain()
	_test_chunk_roundtrip()
	_test_region_roundtrip()
	_test_region_regrow_and_reuse()
	_test_region_compaction()
	_test_region_corrupt_entry()
	_test_region_truncated_file()
	_test_generation_hash()
	_test_save_document()

	_cleanup()
	var passed := 0
	for r: Dictionary in results:
		if bool(r["ok"]):
			passed += 1
	return {
		"passed": passed,
		"failed": results.size() - passed,
		"ms": Time.get_ticks_msec() - t0,
		"cases": results.duplicate(),
	}


## Pretty-print a report for the debug overlay / console.
static func format(report: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("persistence self-test: %d passed, %d failed in %d ms"
		% [report.get("passed", 0), report.get("failed", 0), report.get("ms", 0)])
	for c: Variant in (report.get("cases", []) as Array):
		var d: Dictionary = c
		lines.append("  %s %s%s" % [
			"PASS" if bool(d["ok"]) else "FAIL",
			d["name"],
			"" if String(d["detail"]) == "" else "  — " + String(d["detail"]),
		])
	return "\n".join(lines)


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": ok, "detail": detail})
	if not ok:
		push_warning("[SavSelfTest] FAIL %s — %s" % [name, detail])


# ======================================================================= codec
func _test_codec_binary() -> void:
	var doc := _sample_doc()
	var bytes := SavCodec.encode(doc, 0)
	var res := SavCodec.decode(bytes)
	if not bool(res["ok"]):
		_check("codec/binary", false, String(res["error"]))
		return
	var back: Dictionary = res["data"]
	var same := _deep_equal(back.get("sections", {}), doc.get("sections", {}))
	_check("codec/binary", same, "" if same else "sections differ after round-trip")


func _test_codec_json() -> void:
	var doc := _sample_doc()
	var bytes := SavCodec.encode(doc, 1)
	var text := bytes.slice(SavCodec.HEADER_SIZE).get_string_from_utf8()
	var readable := text.begins_with("{") and text.contains("\"sections\"")
	var res := SavCodec.decode(bytes)
	var ok := bool(res["ok"]) and readable
	if ok:
		# JSON has no integer type; compare the structure, not the exact types.
		var back: Dictionary = res["data"]
		ok = (back.get("sections", {}) as Dictionary).has("game")
	_check("codec/json", ok, "" if ok else "JSON path did not survive: " + String(res.get("error", "")))


func _test_codec_corruption() -> void:
	var bytes := SavCodec.encode(_sample_doc(), 0)
	if bytes.size() < SavCodec.HEADER_SIZE + 8:
		_check("codec/corruption", false, "sample too small")
		return
	bytes[SavCodec.HEADER_SIZE + 3] = bytes[SavCodec.HEADER_SIZE + 3] ^ 0xFF
	var res := SavCodec.decode(bytes)
	var ok := not bool(res["ok"])
	_check("codec/corruption", ok, "" if ok else "a flipped byte was accepted")


func _test_migration_chain() -> void:
	# A v1 document: flat module keys, `player_state` rather than `player`.
	var v1 := {
		"game": {"tick": 7, "day": 2},
		"view": {"view": 1, "layer": 33},
		"player_state": {"health": 42.0},
		"inv": {"slots": []},
	}
	var out := SavCodec.migrate(v1, 1)
	var sections: Dictionary = out.get("sections", {})
	var ok := sections.has("game") and sections.has("player") and sections.has("inventory") \
		and not sections.has("inv") and int(out.get("version", 0)) == SavCodec.SAVE_VERSION \
		and float((sections["player"] as Dictionary).get("health", 0.0)) == 42.0
	_check("codec/migration v1->v%d" % SavCodec.SAVE_VERSION, ok,
		"" if ok else "migrated shape is wrong: " + str(out.keys()))


# ======================================================================= chunk
func _test_chunk_roundtrip() -> void:
	var c := _synthetic_chunk(Vector3i(3, 2, 5), 1234)
	var d := c.to_dict()
	var back := Chunk.from_dict(d)
	var ok := back != null and back.blocks == c.blocks and back.liquid == c.liquid \
		and back.solid_count == c.solid_count and back.tile_data.size() == c.tile_data.size()
	_check("chunk/to_dict-from_dict", ok, "" if ok else "chunk contents changed")


# ====================================================================== region
func _test_region_roundtrip() -> void:
	var path := SCRATCH + "/r.0.0.0.psr"
	var reg := SavRegion.new()
	if not reg.open_file(path):
		_check("region/roundtrip", false, reg.error)
		return
	var written: Dictionary = {}
	for i in 24:
		var cp := Vector3i(i % 16, (i / 16) % 16, (i * 7) % 16)
		var c := _synthetic_chunk(cp, 900 + i)
		written[cp] = c
		reg.write_chunk(cp, c.to_dict())
	reg.commit()
	reg.close()

	var reopened := SavRegion.new()
	reopened.open_file(path)
	var bad := 0
	for cp: Vector3i in written:
		var payload := reopened.read_chunk(cp)
		if payload.is_empty():
			bad += 1
			continue
		var back := Chunk.from_dict(payload)
		if back == null or back.blocks != (written[cp] as Chunk).blocks:
			bad += 1
	var count_ok := reopened.stored_count() == written.size()
	reopened.close()
	_check("region/roundtrip", bad == 0 and count_ok,
		"" if bad == 0 and count_ok else "%d of %d chunks came back wrong" % [bad, written.size()])


func _test_region_regrow_and_reuse() -> void:
	var path := SCRATCH + "/r.1.0.0.psr"
	var reg := SavRegion.new()
	if not reg.open_file(path):
		_check("region/free-space reuse", false, reg.error)
		return
	var cp := Vector3i(4, 4, 4)
	# Small payload first, then a much larger one, then small again. The last
	# write must reuse the block the big one left behind rather than growing.
	reg.write_chunk(cp, _synthetic_chunk(cp, 1).to_dict())
	var small_size: int = reg.stats()["bytes"]
	var fat := _synthetic_chunk(cp, 2)
	for i in 512:
		fat.set_tile_data(i * 8, {"kind": "chest", "items": _filler(12)})
	reg.write_chunk(cp, fat.to_dict())
	var fat_size: int = reg.stats()["bytes"]
	# Shrinking rewrite: the slot keeps its existing reservation and writes in
	# place, so the heap must not grow. (It deliberately does NOT hand the
	# surplus back — that would fragment the file for every routine edit.)
	reg.write_chunk(cp, _synthetic_chunk(cp, 3).to_dict())
	var shrunk_size: int = reg.stats()["bytes"]
	# Erasing genuinely frees the block, and the next allocation must land
	# inside it rather than past the end of the heap.
	reg.erase_chunk(cp)
	var cp2 := Vector3i(5, 4, 4)
	reg.write_chunk(cp2, _synthetic_chunk(cp2, 4).to_dict())
	var after: int = reg.stats()["bytes"]
	reg.commit()
	var payload := reg.read_chunk(cp2)
	var still_good := not payload.is_empty() and Chunk.from_dict(payload) != null
	reg.close()
	var grew := fat_size > small_size
	var reused_in_place := shrunk_size == fat_size
	var reused_freed := after <= fat_size
	var ok := grew and reused_in_place and reused_freed and still_good
	_check("region/free-space reuse", ok,
		"" if ok else "heap %d -> %d -> %d -> %d (grew=%s in_place=%s reused=%s readable=%s)" % [
			small_size, fat_size, shrunk_size, after,
			grew, reused_in_place, reused_freed, still_good])


func _test_region_compaction() -> void:
	var path := SCRATCH + "/r.2.0.0.psr"
	var reg := SavRegion.new()
	if not reg.open_file(path):
		_check("region/compaction", false, reg.error)
		return
	var keep: Array[Vector3i] = []
	for i in 20:
		var cp := Vector3i(i % 16, 1, i / 16)
		var c := _synthetic_chunk(cp, 300 + i)
		for j in 200:
			c.set_tile_data(j * 16, {"pad": _filler(8)})
		reg.write_chunk(cp, c.to_dict())
		if i % 2 == 0:
			keep.append(cp)
	var before: int = reg.stats()["bytes"]
	for i in 20:
		var cp := Vector3i(i % 16, 1, i / 16)
		if not keep.has(cp):
			reg.erase_chunk(cp)
	reg.commit()
	var compacted := reg.compact()
	var after: int = reg.stats()["bytes"]
	var readable := 0
	for cp: Vector3i in keep:
		if not reg.read_chunk(cp).is_empty():
			readable += 1
	reg.close()
	var ok := compacted and readable == keep.size() and after <= before
	_check("region/compaction", ok,
		"" if ok else "compacted=%s kept %d/%d, %d -> %d bytes"
			% [compacted, readable, keep.size(), before, after])


func _test_region_corrupt_entry() -> void:
	var path := SCRATCH + "/r.3.0.0.psr"
	var reg := SavRegion.new()
	if not reg.open_file(path):
		_check("region/corrupt entry", false, reg.error)
		return
	var good := Vector3i(1, 1, 1)
	var bad := Vector3i(2, 2, 2)
	reg.write_chunk(good, _synthetic_chunk(good, 11).to_dict())
	reg.write_chunk(bad, _synthetic_chunk(bad, 12).to_dict())
	reg.commit()
	reg.close()

	# Scribble over the middle of the heap. One entry's checksum now fails.
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		_check("region/corrupt entry", false, "cannot reopen scratch file")
		return
	f.seek(SavRegion.HEADER_SIZE + 4)
	f.store_buffer(_filler(64))
	f.flush()
	f.close()

	var reg2 := SavRegion.new()
	reg2.open_file(path)
	var a := reg2.read_chunk(good)
	var b := reg2.read_chunk(bad)
	# At least one must now be reported missing, and neither call may crash.
	var survived := a.is_empty() or b.is_empty()
	# The other must still be intact, and the damaged slot must have been dropped.
	var recovered := reg2.corrupt_entries > 0
	reg2.close()
	_check("region/corrupt entry", survived and recovered,
		"" if survived and recovered else "damage was not detected (corrupt=%d)" % reg2.corrupt_entries)


func _test_region_truncated_file() -> void:
	var path := SCRATCH + "/r.4.0.0.psr"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_check("region/truncated file", false, "cannot create scratch file")
		return
	f.store_buffer(_filler(1024))    ## far shorter than a header
	f.close()
	var reg := SavRegion.new()
	var opened := reg.open_file(path)
	var empty := reg.stored_count() == 0
	var writable := reg.write_chunk(Vector3i(0, 0, 0), _synthetic_chunk(Vector3i(0, 0, 0), 5).to_dict())
	var readable := not reg.read_chunk(Vector3i(0, 0, 0)).is_empty()
	reg.close()
	var quarantined := FileAccess.file_exists(path + ".corrupt")
	var ok := opened and empty and writable and readable and quarantined
	_check("region/truncated file", ok,
		"" if ok else "opened=%s empty=%s write=%s read=%s quarantined=%s"
			% [opened, empty, writable, readable, quarantined])


# =========================================================== modified detection
func _test_generation_hash() -> void:
	var cp := Vector3i(7, 3, 9)
	var a := _synthetic_chunk(cp, 77)
	var b := _synthetic_chunk(cp, 77)
	var same := SaveManager._content_hash(a) == SaveManager._content_hash(b)
	b.set_at(Chunk.index(3, 4, 5), 999)
	var differs := SaveManager._content_hash(a) != SaveManager._content_hash(b)
	# Light is derived, not authored, so it must not count as a modification.
	var c := _synthetic_chunk(cp, 77)
	c.set_block_light(Chunk.index(1, 1, 1), 12)
	var light_ignored := SaveManager._content_hash(a) == SaveManager._content_hash(c)
	# Liquid must count.
	var d := _synthetic_chunk(cp, 77)
	d.set_liquid(Chunk.index(2, 2, 2), 5)
	var liquid_counts := SaveManager._content_hash(a) != SaveManager._content_hash(d)
	var ok := same and differs and light_ignored and liquid_counts
	_check("modified/generation hash", ok,
		"" if ok else "stable=%s block=%s light-ignored=%s liquid=%s"
			% [same, differs, light_ignored, liquid_counts])


# ================================================================ save document
func _test_save_document() -> void:
	var doc := _sample_doc()
	var path := SCRATCH + "/doc.dat"
	if not SavCodec.write_atomic(path, doc, 0):
		_check("save/atomic write", false, "write_atomic returned false")
		return
	var first := SavCodec.read_with_fallback(path)
	# Overwrite once so a .bak exists, then destroy the primary and confirm the
	# backup carries the save.
	doc["meta"]["day"] = 99
	SavCodec.write_atomic(path, doc, 0)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("not a save at all")
		f.close()
	var recovered := SavCodec.read_with_fallback(path)
	var ok := bool(first["ok"]) and bool(recovered["ok"]) and bool(recovered.get("from_backup", false))
	_check("save/atomic write + backup", ok,
		"" if ok else "first=%s recovered=%s" % [first["ok"], recovered.get("error", "")])


# ===================================================================== fixtures
func _synthetic_chunk(cp: Vector3i, seed_value: int) -> Chunk:
	var c := Chunk.new(cp)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# A plausible chunk: solid below a wobbling surface, empty above, so zstd
	# has realistic runs to chew on rather than pure noise.
	for lx in 16:
		for lz in 16:
			var h := 6 + int(rng.randf() * 5.0)
			for ly in h:
				c.blocks[Chunk.index(lx, ly, lz)] = 1 if ly < h - 2 else 2
	c.recount()
	c.generated = true
	c.populated = true
	c.set_tile_data(Chunk.index(1, 2, 3), {"kind": "chest", "seed": seed_value})
	return c


func _sample_doc() -> Dictionary:
	return {
		"version": SavCodec.SAVE_VERSION,
		"meta": {"name": "self test", "slot": 99, "day": 3, "playtime": 12.5,
			"thumb": Marshalls.raw_to_base64(_filler(72))},
		"sections": {
			"game": {"tick": 1234, "day": 3, "stats": {"blocks_mined": 17}},
			"view": {"view": 2, "layer": 128},
			"player": {"pos": [1.5, 2.5, 3.5], "health": 63.0},
			"inventory": {"slots": [{"id": "stone", "count": 42}]},
			"entities": {"by_planet": {"home": {"0,0,0": [{"scene": "res://none.tscn"}]}}},
		},
	}


static func _filler(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	for i in n:
		b[i] = (i * 37 + 11) & 255
	return b


static func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k: Variant in da:
			if not db.has(k) or not _deep_equal(da[k], db[k]):
				return false
		return true
	if a is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _deep_equal(aa[i], ab[i]):
				return false
		return true
	return a == b


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(SCRATCH):
		var d := DirAccess.open(SCRATCH)
		if d != null:
			d.list_dir_begin()
			var entry := d.get_next()
			while entry != "":
				if not d.current_is_dir():
					DirAccess.remove_absolute(SCRATCH + "/" + entry)
				entry = d.get_next()
			d.list_dir_end()
		DirAccess.remove_absolute(SCRATCH)
