## Measures the cost of one chunk generation so `World.MAX_GEN_PER_FRAME` can be
## set from data rather than guessed at.
##
##   godot --headless --path . tools/perf_probe.tscn
extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	for i in 240:
		await get_tree().process_frame

	# A new run starts aboard the ship, whose generator is "void" and early-outs.
	# Measuring that would be meaningless, so switch to a real landable world.
	var target := ""
	for id: String in Universe.planets.keys() if Universe.get("planets") != null else []:
		var m: Dictionary = Universe.planet_meta(id)
		if String(m.get("generator", "planet")) == "planet":
			target = id
			break
	if target == "":
		for sid: String in Universe.system_ids():
			for bid: String in Universe.system_body_ids(sid):
				var m2: Dictionary = Universe.planet_meta(bid)
				if String(m2.get("generator", "planet")) == "planet":
					target = bid
					break
			if target != "":
				break
	if target == "":
		print("no landable planet found")
		get_tree().quit(1)
		return
	var meta: Dictionary = Universe.planet_meta(target)
	print("probing planet '%s' (type=%s, generator=%s)" % [
		target, meta.get("type", "?"), meta.get("generator", "?")])
	PlanetGen.begin_planet(int(meta.get("seed", 12345)), meta)

	# Generate a batch of fresh chunks well away from anything already streamed.
	var samples: Array[float] = []
	var base := Vector3i(40, 0, 40)
	for i in 24:
		var cp := base + Vector3i(i % 6, 3 + (i / 6) % 4, i / 6)
		if World.has_chunk(cp):
			continue
		var c := Chunk.new(cp)
		var t0 := Time.get_ticks_usec()
		PlanetGen.generate_chunk(c)
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)

	samples.sort()
	if samples.is_empty():
		print("no samples")
		get_tree().quit(1)
		return
	var total := 0.0
	for s: float in samples:
		total += s
	var mean := total / float(samples.size())
	var p50: float = samples[samples.size() / 2]
	var p95: float = samples[mini(samples.size() - 1, int(samples.size() * 0.95))]

	print("\n=== CHUNK GENERATION COST (n=%d) ===" % samples.size())
	print("  mean   %.2f ms" % mean)
	print("  median %.2f ms" % p50)
	print("  p95    %.2f ms" % p95)
	print("  max    %.2f ms" % samples[samples.size() - 1])
	print("\n  budget at MAX_GEN_PER_FRAME=%d:" % World.MAX_GEN_PER_FRAME)
	print("    typical frame cost  %.2f ms" % (p50 * World.MAX_GEN_PER_FRAME))
	print("    worst  frame cost   %.2f ms" % (samples[samples.size() - 1] * World.MAX_GEN_PER_FRAME))
	print("  (16.67 ms = one frame at 60fps)\n")
	get_tree().quit(0)
