## Runs `ChunkMesher.build_arrays()` on `WorkerThreadPool` and hands the results
## back to the main thread through a mutex-guarded queue.
##
## Only the *pure* half of meshing is threaded. The snapshot (which reads
## `World`) always happens on the main thread, so no worker ever touches the
## voxel dictionary while the streamer is mutating it.
##
## Every failure mode degrades to synchronous meshing instead of crashing:
##   * a single-core machine, or a pool that refuses the task, disables
##     threading immediately;
##   * if submitted work stops coming back at all, the watchdog disables
##     threading and reports the stranded chunks so the renderer can redo them
##     on the main thread.
class_name MeshWorker
extends RefCounted

## Never keep more than this many chunks in flight; beyond it the queue is just
## latency, and each snapshot holds ~40 KB alive.
const MAX_IN_FLIGHT := 8
## If nothing at all comes back within this window while work is outstanding,
## assume the pool is wedged and fall back to synchronous meshing.
const WATCHDOG_SEC := 6.0

## False once threading has been ruled out; the renderer then meshes inline.
var threaded := true

var _mutex := Mutex.new()
var _results: Array = []
var _tasks: PackedInt64Array = PackedInt64Array()
var _in_flight: Dictionary = {}          ## cpos -> true
var _last_progress_usec := 0
var _shutting_down := false


func _init() -> void:
	if OS.get_processor_count() < 2:
		threaded = false
	_last_progress_usec = Time.get_ticks_usec()


## True when another chunk may be submitted right now.
func can_accept() -> bool:
	return threaded and not _shutting_down and _in_flight.size() < MAX_IN_FLIGHT


func in_flight(cpos: Vector3i) -> bool:
	return _in_flight.has(cpos)


func pending() -> int:
	return _in_flight.size()


## Queue a snapshot for meshing. Returns false when the caller must mesh it
## itself (threading disabled, queue full, or the pool rejected the task).
func submit(snap: Dictionary) -> bool:
	if not can_accept() or snap.is_empty():
		return false
	var cpos: Vector3i = snap.get("cpos", Vector3i.ZERO)
	if _in_flight.has(cpos):
		return false
	var id := WorkerThreadPool.add_task(_run.bind(snap), false, "planeshift_chunk_mesh")
	if id < 0:
		push_warning("[MeshWorker] thread pool refused the task; meshing synchronously")
		threaded = false
		return false
	_tasks.append(id)
	_in_flight[cpos] = true
	return true


## Worker-thread body. Must not touch the scene tree or any singleton.
func _run(snap: Dictionary) -> void:
	var built := ChunkMesher.build_arrays(snap)
	_mutex.lock()
	_results.append(built)
	_mutex.unlock()


## Collect up to `limit` finished chunks. Main thread only.
func drain(limit: int = 4) -> Array:
	_reap()
	var out: Array = []
	_mutex.lock()
	while out.size() < limit and not _results.is_empty():
		out.append(_results.pop_front())
	_mutex.unlock()
	for built: Dictionary in out:
		_in_flight.erase(built.get("cpos", Vector3i.ZERO))
	if not out.is_empty():
		_last_progress_usec = Time.get_ticks_usec()
	return out


## Release the pool's handle on tasks that have finished. Godot requires exactly
## one `wait_for_task_completion` per `add_task`.
func _reap() -> void:
	if _tasks.is_empty():
		return
	var keep := PackedInt64Array()
	for id: int in _tasks:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			keep.append(id)
	_tasks = keep


## Call once per frame. Returns the chunks that must be re-meshed on the main
## thread because threading has just been given up on (usually empty).
func watchdog() -> Array:
	if not threaded or _in_flight.is_empty():
		_last_progress_usec = Time.get_ticks_usec()
		return []
	var idle := float(Time.get_ticks_usec() - _last_progress_usec) / 1_000_000.0
	if idle < WATCHDOG_SEC:
		return []
	push_warning("[MeshWorker] no results for %.1fs; falling back to synchronous meshing" % idle)
	threaded = false
	var stranded := _in_flight.keys()
	_in_flight.clear()
	return stranded


## Block until every outstanding task has finished, then drop the queue. Call
## before the renderer is freed or the pool may run `_run` on a dead object.
func shutdown() -> void:
	_shutting_down = true
	for id: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks = PackedInt64Array()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()
	_in_flight.clear()
