## Tiny always-processing node that owns the hit-stop time dilation.
##
## Created on demand by [CbtMeleeFx.hit_stop]; it dips `Engine.time_scale` for a
## few dozen milliseconds when a heavy blow lands and puts it straight back. It
## remembers whatever value it found so it never fights another system that is
## also slowing time (a boss intro, a menu, a tech).
extends Node

const STOP_SCALE := 0.06
## Anything at or below this is somebody else's hit-stop, not a real base rate.
## Capturing it as our restore value would latch the game into slow motion once
## the two overlap, so we fall back to 1.0 instead. Deliberate slow-mo (0.5x
## boss intros, menu ramps) sits above the threshold and is preserved.
const MIN_RESTORE := 0.5

var _restore := 1.0
var _stopping := false


## The value to return `Engine.time_scale` to once this dip finishes.
func _capture_restore() -> float:
	var current := Engine.time_scale
	return current if current > MIN_RESTORE else 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -50


func _process(delta: float) -> void:
	# Hit-stop must age in real time, not in dilated time.
	var real_delta := delta / maxf(0.0001, Engine.time_scale)
	var still := CbtMeleeFx._tick_hitstop(real_delta)
	if still and not _stopping:
		_restore = _capture_restore()
		Engine.time_scale = STOP_SCALE
		_stopping = true
	elif not still and _stopping:
		Engine.time_scale = _restore
		_stopping = false


func _exit_tree() -> void:
	if _stopping:
		Engine.time_scale = _restore
		_stopping = false
