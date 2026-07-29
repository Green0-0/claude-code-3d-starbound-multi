## Fold — collapse the layer behind you into your own for a few seconds. Two
## rooms become one fight.
##
## ---------------------------------------------------------------------------
## WHAT "COLLAPSE" MEANS MECHANICALLY
## ---------------------------------------------------------------------------
## Two things happen, and only the first is cosmetic:
##
##  1. `Tech.fold_layers` -> 1. The renderer draws the layer behind at play-layer
##     brightness, and `Tech.combat_layer_tolerance()` / `interact_layer_tolerance()`
##     widen by one so weapons, tools and interaction all reach into it.
##
##  2. On activation, every hostile sitting exactly one layer behind is **pulled
##     into the play layer** — but only where `VoxelPhysics.aabb_is_free`
##     approves the destination. The move goes through `begin_layer_shift`, the
##     same animated traversal the player uses, so monsters slide in rather than
##     teleport. Anything whose mirrored position is solid simply stays put and
##     is fought at range through rule 1.
##
## Because the pull is gated on free space, nothing can ever be folded into a
## wall — which is why the fold is not undone when the tech expires. Those
## monsters legitimately walked into your layer; they stay there.
##
## ---------------------------------------------------------------------------
## VIEW STATE
## ---------------------------------------------------------------------------
## Mutated under `claim_view()`: `Tech.fold_layers` -> 1. `View` is only read.
## Restored in `on_deactivate`: `fold_layers` -> 0 via the explicit write and
## again via `release_view()`. `Tech`'s watchdog zeroes it if the claim vanishes
## for any other reason.
class_name TchFold
extends TchBase

const LAYERS := 1
const PULL_RADIUS := 18.0
const RESCAN := 0.75

var _pulled: int = 0
var _rescan: float = 0.0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or View.flipping or View.shifting:
		return false
	claim_view()
	if manager != null:
		manager.set("fold_layers", LAYERS)
	_pulled = 0
	_rescan = 0.0
	_collapse()
	Events.spawn_particles.emit(&"tech_fold", p.aabb_center(), 34)
	Events.play_sound.emit(&"tech_fold", p.global_position)
	Events.screen_shake.emit(1.8, 0.35)
	Events.toast("Fold — %d drawn through." % _pulled, "tech")
	return true


func on_update(delta: float) -> void:
	if not active:
		return
	if manager != null and int(manager.get("fold_layers")) != LAYERS:
		manager.set("fold_layers", LAYERS)
	_rescan -= delta
	if _rescan <= 0.0:
		_rescan = RESCAN
		_collapse()
	var p := player()
	if p != null:
		Events.spawn_particles.emit(&"tech_fold_seam", p.aabb_center(), 2)


## Pull every hostile exactly `LAYERS` behind into the play layer, where legal.
func _collapse() -> void:
	var p := player()
	if p == null:
		return
	var sign_ := View.depth_sign()
	for e: VoxelEntity in Game.entities_in_radius(p.global_position, PULL_RADIUS):
		if e == p or e.dead or e.faction == &"player" or e.is_in_group(&"drops"):
			continue
		if e.is_shifting():
			continue
		var d := floori(View.depth_of(e.global_position))
		var off := (d - View.layer) * sign_
		if off < 1 or off > LAYERS:
			continue
		var dest := View.with_depth(e.global_position, float(View.layer) + 0.5)
		if not VoxelPhysics.aabb_is_free(dest, e.get_aabb_size()):
			continue
		e.begin_layer_shift(dest)
		_pulled += 1
		Events.spawn_particles.emit(&"tech_fold_pull", e.aabb_center(), 10)


func on_deactivate() -> void:
	if manager != null:
		manager.set("fold_layers", 0)
	release_view()
	var p := player()
	if p != null:
		Events.spawn_particles.emit(&"tech_fold", p.aabb_center(), 18)
		Events.play_sound.emit(&"tech_fold_end", p.global_position)


func modifier(stat: String) -> float:
	if not active:
		return 1.0
	match stat:
		# Fighting two rooms at once is dangerous by design.
		"defense":
			return 0.85
		"flip_cost":
			return 2.0
	return 1.0


func hud_state() -> Dictionary:
	var d := super.hud_state()
	d["folded"] = _pulled
	return d
