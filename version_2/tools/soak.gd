extends Node

## The long session.
##
##     godot --headless --path . tools/soak.tscn
##     SOAK_LAPS=8 godot --headless --path . tools/soak.tscn
##
## Everything else in the suite answers "is this correct" over a few seconds.
## This answers the two questions a survival game actually lives or dies by:
##
##   1. **Does it stutter?** Not "what is the average frame time" — an average
##      hides exactly the thing players report. Frame times are kept whole, and
##      what gets printed is the tail: p99, the worst frame, and how many frames
##      blew past a 30 Hz and a 20 Hz deadline.
##   2. **Does it still not stutter an hour in?** The session is split into laps
##      over the same ground, and every counter that could grow without bound —
##      nodes, queues, deferred writes, resident chunks, memory — is sampled
##      once per lap and printed as a column. A leak is a column that climbs.
##
## The route is deliberately the expensive one: it walks far enough to stream
## constantly, doubles back so chunks unload and reload, digs, spills water,
## and cycles every cut mode. Anything that only misbehaves after the fifth
## visit to the same village shows up here and nowhere else.
##
## Exits non-zero when a budget is missed, so it can gate a release.

## A frame over this is a visible hitch.
const HITCH_MS := 33.0
## A frame over this is a stall the player will call a freeze.
const STALL_MS := 50.0
## Ceilings the run is held to. Generous — this is a regression gate, not a
## benchmark score, and it runs headless on whatever machine CI happens to be.
## Ceilings the run is held to, as fractions of the session rather than as
## absolute counts. Zero stalls would be the nicer number to write down and a
## useless gate to own: this runs headless on whatever machine is free, and one
## frame in twenty thousand landing on the wrong side of a scheduler decision is
## not a regression. What these do catch is the shape of every problem this tool
## was written to find — a stall rate that climbs, which is what a leak, an
## unbudgeted rebuild or an unbounded queue all eventually look like.
const MAX_STALL_FRACTION := 0.0005
const MAX_HITCH_FRACTION := 0.02

## Populations the game unloads, and what "unloaded" has to mean in numbers.
## Every one of these is bounded by a rule in the code rather than by how long
## the session has run; these are those rules, restated where they can fail.
const CEILINGS := {
	"npcs": 40,          # culled past Game.DESPAWN_RANGE
	"monsters": 30,      # MAX_MONSTERS plus the camp-spawn overshoot
	"drops": 190,        # MAX_DROPS plus a tick of slack
	"structures": 80,    # specs waiting on a chunk, dropped once it unloads
	"pending": 60,       # deferred structure blocks, pruned with their chunk
	"chunks": 260,       # the streaming window, and nothing else
}

var game: Node3D
var world: VoxelWorld
var player: Player
var laps := 4
var failures: Array[String] = []

## every frame time in the measured window, in usec
var _frames: PackedInt32Array = PackedInt32Array()
var _samples: Array = []
var _last_usec := 0


func _ready() -> void:
	var env := OS.get_environment("SOAK_LAPS")
	if env != "":
		laps = maxi(int(env), 1)
	var packed: PackedScene = load("res://main.tscn")
	game = packed.instantiate()
	add_child(game)
	world = game.get_node("World")
	player = game.get_node("Player")
	_run()


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## One frame, timed. Everything the session does goes through here, so no work
## can be done outside the measurement.
func _step() -> void:
	await get_tree().process_frame
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_frames.append(now - _last_usec)
	_last_usec = now
	if _frames.size() % 500 == 0:
		print("[soak]   %d frames, %.1f s, %d nodes, %d npcs, %d chunks" % [
			_frames.size(), float(Time.get_ticks_msec()) / 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			game.npcs_root.get_child_count(), world._chunks.size()])


## Cover the distance at the speed a sprinting player actually covers it.
##
## This is not a detail. Stepping the player a chunk-width per frame saturates
## the streaming queue permanently, and then *every* frame is slow and the
## intermittent spikes — the thing being hunted — are invisible underneath a
## flat wall of loading. At running pace the queue keeps up, the game reaches a
## steady state, and a spike is once again a spike.
func _walk(from: Vector3, to: Vector3) -> void:
	var span := from.distance_to(to)
	var steps := maxi(int(span / (Player.RUN_SPEED / 60.0)), 1)
	for i in range(1, steps + 1):
		var at := from.lerp(to, float(i) / float(steps))
		at.y = float(world.surface_height(int(at.x), int(at.z))) + 1.05
		player.teleport(at)
		await _step()


func _run() -> void:
	await world.world_ready
	await _settle(60)

	# Warm-up is not part of the measurement: the first frames after boot are
	# streaming a whole view radius in and are nobody's idea of a steady state.
	Prof.enabled = true
	Prof.reset()
	_last_usec = Time.get_ticks_usec()

	var home := player.global_position
	for lap in laps:
		await _lap(lap, home)
		_sample("lap %d" % (lap + 1))
		print("[soak] lap %d done, %d frames, %.1f s elapsed" % [lap + 1,
			_frames.size(), float(Time.get_ticks_msec()) / 1000.0])

	Prof.enabled = false
	_report()


## One circuit: out, dig, spill, back, through every cut mode.
func _lap(lap: int, home: Vector3) -> void:
	var modes := [Cutaway.Mode.CYLINDER, Cutaway.Mode.FILL, Cutaway.Mode.PLANAR]
	world.set_cutaway_mode(modes[lap % 3])

	# Two bearings, alternating, so every other lap covers *identical* ground.
	# That is the case that matters: chunks unload and regenerate over the same
	# villages and mineshafts, and anything that re-registers itself on reload —
	# a structure queued twice, an NPC spawned twice — compounds here and only
	# here. A fresh bearing every lap would never revisit anything and would
	# quietly pass a world that duplicates its population on every return trip.
	var angle := float(lap % 2) * 1.7
	var far := home + Vector3(cos(angle), 0.0, sin(angle)) * 150.0
	print("[soak] lap %d out" % (lap + 1))
	await _walk(home, far)
	print("[soak] lap %d dig" % (lap + 1))

	# Dig in, which is where the cut modes and the edit path actually work.
	var feet := player.feet_block()
	var floor_y: int = maxi(feet.y - 12, 4)
	for dy in range(0, 13):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				world.set_block(feet.x + dx, floor_y + dy, feet.z + dz, Blocks.AIR)
		player.teleport(Vector3(feet.x + 0.5, float(floor_y + 12 - dy), feet.z + 0.5))
		await _step()
	await _settle(2)

	# A real flood, not a puddle. The liquid sim spreads on its own timer for as
	# long as it has anywhere to go, and it writes blocks the whole time — which
	# is precisely the traffic that used to drag the cross-section and the chunk
	# remesh along with it. A handful of cells would never have shown that.
	var water := Blocks.id(&"water")
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			world.set_block(feet.x + dx, floor_y + 11, feet.z + dz, water)
	for i in 120:
		if i % 30 == 0:
			for dx in range(-2, 3):
				world.set_block(feet.x + dx, floor_y + 11, feet.z, water)
		await _step()

	# Mine a gallery, one block per frame, the way a player actually does it.
	for i in 40:
		world.set_block(feet.x + 3 + i % 12, floor_y + 1 + (i / 12), feet.z,
			Blocks.AIR)
		await _step()

	player.teleport(Vector3(far.x, float(world.surface_height(
		int(far.x), int(far.z))) + 1.05, far.z))
	await _walk(far, home)


func _sample(label: String) -> void:
	var drops: Node = game.drops_root
	var objects: Node = game.objects_root
	var npcs: Node = game.npcs_root
	_samples.append({
		"label": label,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"chunks": world._chunks.size(),
		"pending": world._pending.size(),
		"structures": world.pending_structures.size(),
		"monsters": game.monsters_root.get_child_count(),
		"npcs": npcs.get_child_count(),
		"objs": objects.get_child_count(),
		"drops": drops.get_child_count(),
		"flow": game.liquids._flow.size(),
		"crops": game.liquids._crops.size(),
	})


func _pct(sorted: PackedInt32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	var i := clampi(int(float(sorted.size() - 1) * q), 0, sorted.size() - 1)
	return float(sorted[i]) / 1000.0


func _check(name: String, ok: bool, detail := "") -> void:
	var tag := "ok  " if ok else "FAIL"
	print("  %s  %s%s" % [tag, name, "" if detail == "" else "  — " + detail])
	if not ok:
		failures.append(name)


func _report() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var hitches := 0
	var stalls := 0
	for f: int in _frames:
		if float(f) / 1000.0 >= STALL_MS:
			stalls += 1
		elif float(f) / 1000.0 >= HITCH_MS:
			hitches += 1

	print("")
	print("=== soak: %d laps, %d frames ===" % [laps, _frames.size()])
	print("frame ms   p50 %.2f   p95 %.2f   p99 %.2f   worst %.2f" % [
		_pct(sorted, 0.50), _pct(sorted, 0.95), _pct(sorted, 0.99),
		_pct(sorted, 1.0)])
	print("hitches >%.0fms: %d   stalls >%.0fms: %d   of %d frames" % [
		HITCH_MS, hitches, STALL_MS, stalls, _frames.size()])

	print("")
	print("=== where the time went (worst single frame first) ===")
	for row: String in Prof.report():
		print("  " + row)

	print("")
	print("=== growth over the session ===")
	var cols := ["nodes", "objects", "mem_mb", "chunks", "pending", "structures",
		"monsters", "npcs", "objs", "drops", "flow", "crops"]
	var head := "%-10s" % "lap"
	for c: String in cols:
		head += "%11s" % c
	print(head)
	for s: Dictionary in _samples:
		var line := "%-10s" % s["label"]
		for c: String in cols:
			var v = s[c]
			line += "%11.1f" % v if c == "mem_mb" else "%11d" % int(v)
		print(line)

	print("")
	# Two different questions, and conflating them makes a gate that either
	# cries wolf or never fires.
	#
	#   * Things the game *unloads* — creatures, villagers, queued specs — must
	#     stay under a ceiling. Their count at any instant depends on where the
	#     player happens to be standing, so demanding it never rise between two
	#     arbitrary samples is noise, not a leak test.
	#   * Things the game *keeps* — saved objects, and the node count that
	#     follows them — are allowed to accumulate as new ground is explored,
	#     but retreading old ground must not add to them. So what is checked is
	#     that growth decays: the back half of a session that covers exactly the
	#     same ground as the front half must add far less than the front half
	#     did. A steady climb is a leak however slow it is.
	for key: String in CEILINGS:
		var peak := 0
		for s: Dictionary in _samples:
			peak = maxi(peak, int(s[key]))
		_check("%s stays under %d" % [key, CEILINGS[key]], peak <= int(CEILINGS[key]),
			"peaked at %d" % peak)

	if _samples.size() >= 4:
		var mid: int = _samples.size() / 2
		var first: Dictionary = _samples[0]
		var middle: Dictionary = _samples[mid]
		var last: Dictionary = _samples[-1]
		for key: String in ["nodes", "objs"]:
			var front: int = int(middle[key]) - int(first[key])
			var back: int = int(last[key]) - int(middle[key])
			_check("%s growth decays over the session" % key,
				back <= maxi(2, front / 2),
				"%d over the front half, %d over the back" % [front, back])
		_check("memory does not grow across laps",
			float(last["mem_mb"]) - float(middle["mem_mb"]) < 8.0,
			"%.1f -> %.1f MB" % [middle["mem_mb"], last["mem_mb"]])

	var stall_frac := float(stalls) / maxf(float(_frames.size()), 1.0)
	_check("under %.2f%% of frames stall over %.0f ms"
		% [MAX_STALL_FRACTION * 100.0, STALL_MS],
		stall_frac <= MAX_STALL_FRACTION,
		"%d stalls, %.3f%%" % [stalls, stall_frac * 100.0])
	var frac := float(hitches + stalls) / maxf(float(_frames.size()), 1.0)
	_check("under %.0f%% of frames hitch" % (MAX_HITCH_FRACTION * 100.0),
		frac <= MAX_HITCH_FRACTION, "%.2f%% hitched" % (frac * 100.0))

	print("")
	if failures.is_empty():
		print("soak: clean over %d laps" % laps)
		get_tree().quit(0)
	else:
		print("soak: %d budget(s) missed" % failures.size())
		for f: String in failures:
			print("   - " + f)
		get_tree().quit(1)
