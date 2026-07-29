## The two status effects that only make sense in Planeshift, because they act
## directly on the perspective mechanic.
##
## ## `plane_locked`
##
## Some monsters (the Planestalker, the Anchor Wretch) and some blocks
## (`plane_anchor`, certain Ancient dungeon floors) *pin you to your plane*.
## While locked you cannot flip and cannot shift — `View.flips_enabled` is the
## single gate for both, so clearing it does the whole job. That turns a fight
## into a genuine 2D platformer fight: no escaping into the layer behind.
##
## Locks are **reference counted** (`Status.push_flip_lock` /
## `Status.pop_flip_lock`), so two monsters locking you at once still resolves
## correctly, and a menu or cutscene that also disables flips is never stomped.
##
## ## `phase_sight`
##
## The counterpart. It widens the *interaction rule* by one depth layer: while
## it is active you can mine, place, interact with and be hit by things one
## voxel further into the screen than usual. Consumers read it via
## `Status.interaction_layer_slack()` or `Status.can_interact_with_layer(pos)`;
## renderers read `View.get_meta(&"phase_sight", 0)` to brighten that extra
## slab. Stacking it (a perfect meal plus a tech) reaches two layers.
class_name SrvEffectsSignature
extends RefCounted


static func register_all(reg) -> void:
	var lock: SrvStatusEffect = reg.define(&"plane_locked", "Plane-Locked")
	lock.describe("Pinned to this plane. You cannot flip or shift until it lifts.")
	lock.debuff(&"signature").lasts(6.0).ticks(1.0)
	lock.stacking(SrvStatusEffect.Stack.REFRESH, 1)
	lock.modifies_all({"move_speed": 0.94, "knockback_taken": 1.15})
	lock.visual(Color(0.85, 0.25, 0.55, 0.38), &"plane_lock", 5.0)
	lock.icon(Color(0.9, 0.3, 0.55), &"lock")
	lock.sounds(&"denied")
	lock.on_apply = func(t: Node, a: SrvStatusHolder.Active) -> void: _lock_apply(t, a)
	lock.on_remove = func(t: Node, a: SrvStatusHolder.Active) -> void: _lock_remove(t, a)
	lock.on_tick = func(t: Node, a: SrvStatusHolder.Active, d: float) -> void: _lock_tick(t, a, d)

	var phase: SrvStatusEffect = reg.define(&"phase_sight", "Phase Sight")
	phase.describe("See and reach one depth layer further into the world.")
	phase.in_category(&"signature").lasts(45.0)
	phase.stacking(SrvStatusEffect.Stack.STACK, 2)
	phase.modifies_all({"reach_layers": 2.0, "light_radius": 1.3})
	phase.visual(Color(0.45, 0.85, 1.0, 0.26), &"phase_shimmer", 4.0)
	phase.icon(Color(0.45, 0.85, 1.0), &"eye")
	phase.sounds(&"phase")
	phase.on_apply = func(t: Node, a: SrvStatusHolder.Active) -> void: _phase_apply(t, a)
	phase.on_remove = func(t: Node, a: SrvStatusHolder.Active) -> void: _phase_remove(t, a)


# --------------------------------------------------------------- plane_locked
static func _lock_apply(target: Node, act: SrvStatusHolder.Active) -> void:
	if not _is_player(target):
		# Monsters get the same book-keeping so AI can query it, but only the
		# player's lock touches the global View gate.
		return
	act.data["held"] = true
	Status.push_flip_lock()
	Events.flip_blocked.emit("plane_locked")
	Events.toast("Plane-locked!", "warn")
	Events.screen_shake.emit(0.25, 0.2)


## Keyed off `act.data.held`, not off the target: if the holder was freed while
## locked we must still give the reference count back.
static func _lock_remove(_target: Node, act: SrvStatusHolder.Active) -> void:
	if not bool(act.data.get("held", false)):
		return
	act.data["held"] = false
	Status.pop_flip_lock()
	if Status.flip_locks() == 0:
		Events.toast("Plane lock released.", "info")


## Re-assert the gate every second: another system may have re-enabled flips
## between our apply and now, and the lock must win while it is running.
static func _lock_tick(target: Node, _act: SrvStatusHolder.Active, _delta: float) -> void:
	if _is_player(target) and View.flips_enabled and Status.flip_locks() > 0:
		View.flips_enabled = false


# ---------------------------------------------------------------- phase_sight
static func _phase_apply(target: Node, _act: SrvStatusHolder.Active) -> void:
	if _is_player(target):
		Status.refresh_phase_sight()
		Events.toast("Phase sight — the layer behind opens up.", "good")


static func _phase_remove(_target: Node, _act: SrvStatusHolder.Active) -> void:
	Status.refresh_phase_sight()


static func _is_player(target: Node) -> bool:
	return target != null and is_instance_valid(target) \
		and (target == Game.player or target.is_in_group(&"player"))
