## Phase Step — shift **two** layers at once, passing clean through the solid
## layer in between.
##
## ---------------------------------------------------------------------------
## VIEW STATE: WHAT IS MUTATED AND HOW IT COMES BACK
## ---------------------------------------------------------------------------
## Mutated on activate (all under `claim_view()`):
##   `View.flips_enabled` -> false      a flip mid-phase would swap the depth
##                                      axis out from under a half-finished
##                                      traversal and desync `View.layer`
##   `View.shift_duration` -> 0.30      two layers take longer than one
##   `View.shifting` -> true, `View.shift_t` -> 0
##                                      exactly what `View.request_shift` does;
##                                      `main.gd` owns clearing it again
##   `View.layer` += 2 * dir            via `View.set_layer`, the real traversal
##   `Tech.phase_ghost` -> true         cosmetic flag for the render agent
##
## Restored in `on_deactivate` (which `Tech` runs on expiry, cancel, unequip,
## death and world unload):
##   `release_view()` puts `flips_enabled` and `shift_duration` back to the
##   values snapshotted before activation, and clears every `Tech` override.
##   `phase_ghost` is cleared explicitly first.
##   `View.shifting` is force-cleared **only** if it is still set and the
##   animation window has already elapsed — normally `main.gd` has done it.
##   `View.layer` is deliberately *not* rolled back: the traversal succeeded,
##   the player really is two layers over.
##
## Failure path: if neither direction has a free destination the tech returns
## false from `on_activate`, which means no energy is spent, no cooldown runs
## and nothing was claimed in the first place.
class_name TchPhaseStep
extends TchBase

const SHIFT_TIME := 0.30

var _elapsed: float = 0.0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or View.flipping or View.shifting or p.is_shifting():
		return false

	# Deeper by default; the depth_out key (or holding it) reverses the intent.
	var dir := -1 if Input.is_action_pressed(&"depth_out") else 1
	var dest := _destination(p, dir)
	if dest == null:
		dir = -dir
		dest = _destination(p, dir)
	if dest == null:
		Events.flip_blocked.emit("phase_blocked")
		Events.play_sound.emit(&"denied", p.global_position)
		return false

	claim_view()
	View.flips_enabled = false
	View.shift_duration = SHIFT_TIME
	if manager != null:
		manager.set("phase_ghost", true)

	View.shift_from_layer = View.layer
	View.shifting = true
	View.shift_t = 0.0
	p.begin_layer_shift(dest)
	View.set_layer(View.layer + 2 * dir)

	_elapsed = 0.0
	Events.spawn_particles.emit(&"tech_phase", p.aabb_center(), 22)
	Events.play_sound.emit(&"tech_phase", p.global_position)
	Events.screen_shake.emit(0.6, 0.18)
	return true


## The world position two layers along `dir`, or null when it is occupied.
## The *intervening* layer is intentionally not tested — passing through it is
## the entire point of the tech.
func _destination(p: VoxelEntity, dir: int) -> Variant:
	var step := Vector3(View.depth_step() * dir)
	var dest: Vector3 = p.global_position + step * 2.0
	if not VoxelPhysics.aabb_is_free(dest, p.get_aabb_size()):
		return null
	return dest


func on_update(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	var p := player()
	if p != null:
		Events.spawn_particles.emit(&"tech_phase_trail", p.aabb_center(), 1)


func on_deactivate() -> void:
	if manager != null:
		manager.set("phase_ghost", false)
	# Belt and braces: main.gd normally clears this, but if the frame loop was
	# interrupted (death, world unload) a stuck `shifting` would block every
	# future flip and shift. Only clear it once the window has really passed.
	if View.shifting and _elapsed >= SHIFT_TIME:
		View.shifting = false
		View.shift_t = 0.0
	release_view()
	var p := player()
	if p != null:
		Events.spawn_particles.emit(&"tech_phase", p.aabb_center(), 14)


func modifier(stat: String) -> float:
	# Phasing bodies are briefly intangible.
	return 0.0 if (active and stat == "fall_damage") else 1.0
