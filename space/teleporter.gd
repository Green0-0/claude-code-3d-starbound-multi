## Two-way teleportation: ship <-> planet beaming, player-placed pads, outpost
## hubs and bookmarks.
##
## Lives at `Universe.teleporter`.
##
## ===========================================================================
##  THE VIEW / LAYER RULE  — the one thing every other agent needs to know
## ===========================================================================
## A destination is a full 3D point, but the player experiences the world as one
## plane. Arriving must therefore answer two questions: *which of the four views
## am I in* and *which depth layer do I occupy*. The rule is:
##
##  1. **The layer is always re-derived from the destination position**, never
##     carried over: `View.set_layer(floori(View.depth_of(dest)))`. Carrying a
##     stale layer is how you materialise inside a wall.
##
##  2. **A same-world teleport keeps the current view.** Pads you place yourself
##     are read in whatever plane you were reading the room in; rotating the
##     world under the player for a two-metre hop would be disorienting.
##
##  3. **A cross-world teleport adopts the destination's authored view.** The
##     ship and the outpost are hand-built to be read in view 0, and a
##     bookmarked pad remembers the view it was created in. If a destination
##     carries no `view`, rule 2 applies instead.
##
##  4. **The view change is snapped, not animated.** `snap_view()` sets the
##     plane instantly and emits `view_flip_finished`, because the flip happens
##     behind the beam-out fade — the player never sees a half-rotated world.
##
##  5. Flips and shifts are disabled for the duration of the beam and restored
##     afterwards, so a teleport can never interleave with a flip animation.
##
## ---------------------------------------------------------------------------
##  DESTINATION DICTIONARY (the currency of this whole file)
##   `world`  String   `World.planet_id` to be in
##   `pos`    Vector3  world-space feet position to stand at
##   `view`   int      optional 0..3, see rule 3; omit or -1 to keep the current
##   `label`  String   what the UI shows
##   `id`     String   stable key, used by bookmarks
##   `network` String  "ship" | "outpost" | "pad" | "bookmark"
## ===========================================================================
class_name SpcTeleporter
extends Node

signal teleport_started(dest: Dictionary)
signal teleport_finished(dest: Dictionary)
signal bookmarks_changed()
signal pads_changed()

const BEAM_OUT := 0.45
const BEAM_IN := 0.35

## Player-placed / discovered pads: world id -> Array of destination dicts.
var pads: Dictionary = {}
## Saved destinations the player named. Array of destination dicts.
var bookmarks: Array[Dictionary] = []

var beaming := false


# ============================================================ the view/layer rule
## Snap the world to plane `v` with no animation and no gameplay consequences.
## Used only while the screen is covered by a beam effect.
func snap_view(v: int) -> void:
	if v < 0:
		return
	v = wrapi(v, 0, Const.VIEW_COUNT)
	if View.view == v and not View.flipping:
		return
	View.flipping = false
	View.shifting = false
	View.flip_t = 0.0
	View.view = v
	Events.view_flip_finished.emit(v)


## Apply rules 1-4 for `dest`. Called after the player has been moved.
func apply_view_and_layer(dest: Dictionary, cross_world: bool) -> void:
	var want := int(dest.get("view", -1))
	if cross_world and want >= 0:
		snap_view(want)
	var pos: Vector3 = dest.get("pos", Vector3.ZERO)
	View.set_layer(floori(View.depth_of(pos)))


# ==================================================================== beaming
# The public entry points validate synchronously and return a bool, then kick
# off a `void` coroutine for the animation — so callers never have to `await`.

## Beam anywhere. Handles the world swap when `dest.world` differs from the one
## the player is standing in. Returns false if the request was rejected outright.
func teleport_to(dest: Dictionary) -> bool:
	if beaming or not dest.has("pos"):
		return false
	_run_teleport(dest)
	return true


func _run_teleport(dest: Dictionary) -> void:
	var world_id := String(dest.get("world", World.planet_id))
	beaming = true
	teleport_started.emit(dest)
	await _beam_out()

	var cross := world_id != World.planet_id
	if cross:
		if world_id == SpcShip.WORLD_ID:
			Universe.ship.board()
		else:
			Game.travel_to_planet(world_id)
	_settle(dest, cross)

	await _beam_in()
	beaming = false
	teleport_finished.emit(dest)
	Events.toast("Materialised at %s." % String(dest.get("label", "destination")), "info")


func _settle(dest: Dictionary, cross_world: bool) -> void:
	var pos: Vector3 = dest.get("pos", Vector3.ZERO)
	if Game.player != null:
		Game.player.teleport(pos)
		World.update_streaming(Game.player.global_position)
	apply_view_and_layer(dest, cross_world)


func _beam_out() -> void:
	var was := View.flips_enabled
	View.flips_enabled = false
	var pos := _player_pos()
	Events.play_sound.emit(&"teleport_out", pos)
	Events.spawn_particles.emit(&"teleport_beam", pos, 30)
	Events.screen_shake.emit(0.6, BEAM_OUT)
	await get_tree().create_timer(BEAM_OUT).timeout
	View.flips_enabled = was


func _beam_in() -> void:
	var pos := _player_pos()
	Events.play_sound.emit(&"teleport_in", pos)
	Events.spawn_particles.emit(&"teleport_beam", pos, 30)
	await get_tree().create_timer(BEAM_IN).timeout


func _player_pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO


# ------------------------------------------------------------- ship <-> planet
## Beam from the ship down to the body it is orbiting.
func beam_down() -> bool:
	if beaming:
		return false
	if not Universe.ship.is_aboard():
		Events.toast("You are not aboard the ship.", "warn")
		return false
	var target := Universe.travel.orbiting
	if target == "":
		Events.toast("Set a destination on the star map first.", "warn")
		return false
	if not Universe.planets.has(target):
		Events.toast("Nowhere to land here.", "warn")
		return false
	_run_beam_down(target)
	return true


func _run_beam_down(target: String) -> void:
	beaming = true
	teleport_started.emit({"world": target, "label": Universe.body_name(target)})
	await _beam_out()
	# The landing site itself is chosen by `Game._place_player_on_surface()`;
	# rule 1 still applies, so the layer is re-derived from where we ended up.
	Game.travel_to_planet(target)
	if Game.player != null:
		View.set_layer(floori(View.depth_of(Game.player.global_position)))
	await _beam_in()
	beaming = false
	Universe.mark_visited(target)
	Events.toast("Beamed down to %s." % Universe.body_name(target), "good")
	teleport_finished.emit({"world": target, "label": Universe.body_name(target)})


## Beam back up to the ship from wherever the player is standing.
func beam_up() -> bool:
	if Universe.ship.is_aboard():
		return false
	return teleport_to({
		"world": SpcShip.WORLD_ID,
		"pos": SpcShipInterior.SPAWN,
		"view": SpcShipInterior.SPAWN_VIEW,
		"label": "your ship",
		"network": "ship",
		"id": "ship",
	})


## Beam to the outpost from anywhere — the Ark gateway is always reachable once
## the player has found it.
func beam_to_outpost() -> bool:
	if World.planet_id == Universe.OUTPOST_ID:
		return false
	if not Universe.is_discovered(Universe.OUTPOST_ID):
		Events.toast("The Outpost is not in your teleporter's memory yet.", "warn")
		return false
	return teleport_to(SpcOutpost.arrival_destination())


# ------------------------------------------------------------------- pad registry
## Add a fully specified destination to the network. Authored pads (ship,
## outpost) use this because they already know which plane they are read in.
## Duplicate ids are ignored, so calling it every time a world loads is safe.
func register_destination(dest: Dictionary) -> bool:
	var world_id := String(dest.get("world", World.planet_id))
	var list: Array = pads.get(world_id, [])
	var id := String(dest.get("id", ""))
	for existing in list:
		if String((existing as Dictionary).get("id", "")) == id:
			return false
	list.append(dest.duplicate())
	pads[world_id] = list
	pads_changed.emit()
	return true


## Register a teleporter pad the player placed. The pad remembers the plane it
## was placed in, which is what rule 3 reads back on arrival.
func register_pad(world_id: String, block_pos: Vector3i, label: String = "") -> Dictionary:
	var dest := {
		"id": "%s:%d,%d,%d" % [world_id, block_pos.x, block_pos.y, block_pos.z],
		"world": world_id,
		"pos": Vector3(block_pos) + Vector3(0.5, 1.0, 0.5),
		"view": View.view,
		"label": label if label != "" else "Pad %d,%d" % [block_pos.x, block_pos.z],
		"network": "pad",
	}
	if register_destination(dest):
		Events.toast("Teleporter pad linked.", "good")
	return dest


func unregister_pad(world_id: String, block_pos: Vector3i) -> void:
	var list: Array = pads.get(world_id, [])
	var key := "%s:%d,%d,%d" % [world_id, block_pos.x, block_pos.y, block_pos.z]
	for i in range(list.size() - 1, -1, -1):
		if String((list[i] as Dictionary)["id"]) == key:
			list.remove_at(i)
	pads[world_id] = list
	pads_changed.emit()


func pads_in(world_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in (pads.get(world_id, []) as Array):
		out.append(d as Dictionary)
	return out


## Everything the player can currently beam to, ready to list in a UI.
## Ship pads first, then the outpost, then this world's pads, then bookmarks.
func destinations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var pools: Array = [Universe.ship.pads()]
	if Universe.is_discovered(Universe.OUTPOST_ID):
		pools.append([SpcOutpost.arrival_destination()])
	for w: String in pads:
		pools.append(pads_in(w))
	pools.append(bookmarks)
	for pool in pools:
		for d in (pool as Array):
			var e: Dictionary = d
			var key := "%s|%s" % [String(e.get("id", "")), String(e.get("label", ""))]
			if seen.has(key):
				continue
			seen[key] = true
			out.append(e)
	return out


# --------------------------------------------------------------------- bookmarks
## Bookmark the spot the player is standing in, remembering the plane they were
## reading it in (rule 3).
func bookmark_here(label: String) -> Dictionary:
	var pos := _player_pos()
	var dest := {
		"id": "bm_%d" % (bookmarks.size() + Time.get_ticks_msec()),
		"world": World.planet_id,
		"pos": pos,
		"view": View.view,
		"label": label if label != "" else "Bookmark %d" % (bookmarks.size() + 1),
		"network": "bookmark",
	}
	bookmarks.append(dest)
	bookmarks_changed.emit()
	Events.toast("Bookmarked \"%s\"." % String(dest["label"]), "good")
	return dest


func remove_bookmark(id: String) -> void:
	for i in range(bookmarks.size() - 1, -1, -1):
		if String(bookmarks[i]["id"]) == id:
			bookmarks.remove_at(i)
	bookmarks_changed.emit()


func bookmark_by_id(id: String) -> Dictionary:
	for b: Dictionary in bookmarks:
		if String(b["id"]) == id:
			return b
	return {}


# ------------------------------------------------------------------- save/load
func save_state() -> Dictionary:
	return {
		"pads": _serialise(pads),
		"bookmarks": _serialise_list(bookmarks),
	}


func load_state(d: Dictionary) -> void:
	pads.clear()
	var raw: Dictionary = d.get("pads", {})
	for w in raw:
		pads[String(w)] = _deserialise_list(raw[w] as Array)
	bookmarks.clear()
	for b in _deserialise_list(d.get("bookmarks", []) as Array):
		bookmarks.append(b)
	bookmarks_changed.emit()
	pads_changed.emit()


func _serialise(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src:
		out[String(k)] = _serialise_list(src[k] as Array)
	return out


func _serialise_list(src: Array) -> Array:
	var out: Array = []
	for d in src:
		var e: Dictionary = (d as Dictionary).duplicate()
		var p: Vector3 = e.get("pos", Vector3.ZERO)
		e["pos"] = [p.x, p.y, p.z]
		out.append(e)
	return out


func _deserialise_list(src: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in src:
		var e: Dictionary = (d as Dictionary).duplicate()
		var p: Variant = e.get("pos", null)
		if p is Array and (p as Array).size() == 3:
			e["pos"] = Vector3(float(p[0]), float(p[1]), float(p[2]))
		out.append(e)
	return out
