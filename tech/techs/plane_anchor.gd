## Plane Anchor — drive a pin through the world's depth axis so hostiles cannot
## follow you across a flip.
##
## ---------------------------------------------------------------------------
## HOW THE ANCHOR ACTUALLY WORKS
## ---------------------------------------------------------------------------
## Naively "freezing the plane" would mean freezing `View`, which would take the
## flip away from the player — the opposite of what the tech is for. Instead the
## anchor pins *entities* to a world coordinate:
##
##   On activate we record the depth axis of the current view (`anchor_axis`,
##   0 for X or 2 for Z) and, for every hostile inside `RADIUS`, that entity's
##   coordinate **on that axis**. Every frame we write the coordinate back and
##   zero the matching velocity component.
##
## Because the pin is a world coordinate and not a layer index, it survives a
## flip untouched. The player flips; the axis the monsters are pinned to becomes
## the *lateral* axis of the new view; they are now frozen along the direction
## they would need to travel to reach you. They can still walk and fight inside
## their own frozen slice, so it reads as a wall, not as a stun.
##
## ---------------------------------------------------------------------------
## VIEW STATE
## ---------------------------------------------------------------------------
## Mutated: `Tech.plane_anchor_active` -> true, `Tech.anchor_axis` -> 0 or 2.
## `View` itself is only *read*. Restored: `release_view()` clears both fields
## (they are `Tech` overrides, always default-off) and the pin table is dropped,
## so every anchored entity resumes normal movement from wherever it stands —
## no teleport, no stuck monsters.
class_name TchPlaneAnchor
extends TchBase

const RADIUS := 26.0
const RESCAN := 0.4

## instance id -> {"e": VoxelEntity, "coord": float}
var _pinned: Dictionary = {}
var _rescan: float = 0.0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead or View.flipping:
		return false
	claim_view()
	if manager != null:
		manager.set("plane_anchor_active", true)
		manager.set("anchor_axis", View.depth_axis())
	_pinned.clear()
	_rescan = 0.0
	_scan()
	Events.spawn_particles.emit(&"tech_anchor", p.aabb_center(), 26)
	Events.play_sound.emit(&"tech_anchor", p.global_position)
	Events.toast("Plane anchored — %d pinned." % _pinned.size(), "tech")
	return true


func on_update(delta: float) -> void:
	if not active:
		return
	_rescan -= delta
	if _rescan <= 0.0:
		_rescan = RESCAN
		_scan()
	_enforce()


func _axis() -> int:
	return int(manager.get("anchor_axis")) if manager != null else View.depth_axis()


func _scan() -> void:
	var p := player()
	if p == null:
		return
	var axis := _axis()
	if axis < 0:
		return
	for e: VoxelEntity in Game.entities_in_radius(p.global_position, RADIUS):
		if e == p or e.dead or e.faction == &"player" or e.is_in_group(&"drops"):
			continue
		var key := e.get_instance_id()
		if _pinned.has(key):
			continue
		_pinned[key] = {"e": e, "coord": e.global_position[axis]}


func _enforce() -> void:
	var axis := _axis()
	if axis < 0:
		return
	for key: int in _pinned.keys():
		var rec: Dictionary = _pinned[key]
		var e: VoxelEntity = rec["e"]
		if e == null or not is_instance_valid(e) or e.dead:
			_pinned.erase(key)
			continue
		var pos := e.global_position
		var want := float(rec["coord"])
		if absf(pos[axis] - want) > 0.001:
			pos[axis] = want
			e.global_position = pos
			Events.spawn_particles.emit(&"tech_anchor_spark", e.aabb_center(), 1)
		var v := e.velocity
		v[axis] = 0.0
		e.velocity = v


func on_deactivate() -> void:
	_pinned.clear()
	if manager != null:
		manager.set("plane_anchor_active", false)
		manager.set("anchor_axis", -1)
	release_view()
	var p := player()
	if p != null:
		Events.spawn_particles.emit(&"tech_anchor", p.aabb_center(), 12)


func on_unequip() -> void:
	_pinned.clear()


## How many entities the anchor is currently holding — for the HUD.
func pinned_count() -> int:
	return _pinned.size()


func hud_state() -> Dictionary:
	var d := super.hud_state()
	d["pinned"] = _pinned.size()
	return d
