class_name Prof
extends Object

## Opt-in frame profiler.
##
## Frame *spikes* are not the same problem as a slow average, and an average is
## all a frame counter can show you. This attributes each frame's time to the
## subsystem that spent it, keeps the worst single frame per subsystem, and so
## answers the only question that matters about a stutter: which one of them did
## it, and how bad does it get over a long session rather than over ten seconds.
##
## It is off unless a harness turns it on. While off, `mark()` returns 0 and
## `add()` returns on the first line, so the cost is two static calls per scope
## and no timer reads at all. Scopes go at subsystem boundaries only — never
## inside a loop, where the measurement would cost more than the work.
##
##     var t := Prof.mark()
##     liquids.tick(delta)
##     Prof.add(&"liquids", t)

## A frame in which one subsystem alone spent this long is a spike of its own.
const SPIKE_US := 8000

static var enabled := false

## usec accumulated by each key within the frame being measured
static var frame := {}
## worst single frame each key has ever been responsible for
static var worst := {}
## how many frames each key spent more than SPIKE_US in
##
## The honest headline. A single `worst` is one sample and picks up every
## scheduler hiccup the process suffered — a subsystem that does nothing can
## post a sixty millisecond worst frame simply by being descheduled during it.
## A count of spikes over a whole session is a thing that has to be earned.
static var spikes := {}
## usec accumulated by each key over the whole run
static var total := {}
static var frames := 0


static func mark() -> int:
	return Time.get_ticks_usec() if enabled else 0


## `t0` of zero means the profiler was off when the scope opened, so the scope
## is skipped rather than charged a bogus duration.
static func add(key: StringName, t0: int) -> void:
	if t0 == 0:
		return
	frame[key] = frame.get(key, 0) + (Time.get_ticks_usec() - t0)


## Roll the current frame into the totals. Called once from the end of the
## frame, by whoever owns the frame.
static func end_frame() -> void:
	if not enabled:
		return
	frames += 1
	for k: StringName in frame:
		var v: int = frame[k]
		total[k] = total.get(k, 0) + v
		if v > int(worst.get(k, 0)):
			worst[k] = v
		if v >= SPIKE_US:
			spikes[k] = int(spikes.get(k, 0)) + 1
	frame.clear()


static func reset() -> void:
	frame.clear()
	worst.clear()
	spikes.clear()
	total.clear()
	frames = 0


## Spikiest first, then heaviest. A subsystem that costs 0.1 ms every frame is
## not the one making the game stutter, and sorting by total would put it top.
static func report() -> Array:
	var keys: Array = total.keys()
	keys.sort_custom(func(a, b):
		var sa := int(spikes.get(a, 0))
		var sb := int(spikes.get(b, 0))
		if sa != sb:
			return sa > sb
		return int(total[a]) > int(total[b]))
	var rows: Array = []
	for k: StringName in keys:
		rows.append("%-20s spikes %5d   mean %7.3f ms   total %8.1f ms   worst %7.2f ms" % [
			k, int(spikes.get(k, 0)),
			float(total[k]) / 1000.0 / maxf(float(frames), 1.0),
			float(total[k]) / 1000.0, float(worst.get(k, 0)) / 1000.0])
	return rows
