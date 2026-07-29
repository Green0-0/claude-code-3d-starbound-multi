## The player's ship as a place you live in.
##
## Lives at `Universe.ship`.
##
## ===========================================================================
##  HOW THE SHIP WORLD IS LOADED
## ===========================================================================
## The ship is a **normal `World` world with the id `"ship"`** — not a scene, not
## a sub-viewport. `Universe.planet_meta("ship")` returns a 64x64 meta whose
## `generator` key is `"void"`, and `Universe.register_void_world()` marks the
## chunk box `(0,3,0)..(3,6,3)` as hand-authored; every other chunk of that world
## is force-blanked as it streams in, so no terrain can ever appear around the
## hull whatever `PlanetGen` does with the meta.
##
## Boarding is therefore just `Game.travel_to_planet("ship")`:
##   1. `World.create_world("ship", …)` fires `Events.world_ready`
##   2. this node hears it and stamps the hull (`SpcShipInterior.build()`)
##   3. `Game` places the player, then fires `Events.travel_finished`
##   4. this node hears *that* and moves the player onto the boarding pad in the
##      hub, snapping the view to the plane the ship was authored for.
##
## Because it is a real world, the ship saves, streams, lights and flips exactly
## like a planet — and the player can mine, build and decorate inside it.
##
## The hull is only re-stamped when `SpcShipInterior.built_tier()` is behind the
## hull tier the player has paid for, so ordinary decoration survives; a hull
## upgrade is an explicit refit and does replace the interior.
## ===========================================================================
class_name SpcShip
extends Node

## The `World.planet_id` of the ship. Also `Universe.SHIP_ID`.
const WORLD_ID := "ship"
const WORLD_SIZE := SpcShipInterior.WORLD_SIZE
## Feet height of the main deck; mirrored into the ship meta's `surface_level`.
const DECK_Y := SpcShipInterior.DECK_FEET

signal boarded()
signal left()
signal refitted(tier: int)

## Body id the player last stood on, so "return to planet" knows where to go.
var last_planet: String = ""

var _leaving_ship := false
## Set when the ship world is (re)created, consumed by the next travel_finished.
var _needs_placement := false


func _ready() -> void:
	Events.world_ready.connect(_on_world_ready)
	Events.travel_started.connect(_on_travel_started)
	Events.travel_finished.connect(_on_travel_finished)


## True while the player is inside the hull.
func is_aboard() -> bool:
	return World.planet_id == WORLD_ID


## Board the ship. Safe to call from anywhere; a no-op if already aboard.
func board() -> bool:
	if is_aboard():
		return false
	if World.planet_id != "":
		last_planet = World.planet_id
	Game.travel_to_planet(WORLD_ID)
	return true


## Re-stamp the hull after a hull-tier purchase. Only rebuilds when the player is
## actually aboard; otherwise the next boarding picks the new tier up.
func refit() -> void:
	if not is_aboard():
		return
	SpcShipInterior.build(Universe.hull_tier(), true)
	_place_player()
	refitted.emit(Universe.hull_tier())
	Events.toast("Refit complete — new compartments pressurised.", "good")


func spawn_point() -> Vector3:
	return SpcShipInterior.SPAWN


## World position of a named fixture, or `Vector3i.ZERO` when this hull tier does
## not have one. Keys: star_map, ship_status, captain_locker, fuel_hatch,
## teleporter, teleporter_bay.
func fixture(role: String) -> Vector3i:
	var f := SpcShipInterior.fixtures(Universe.hull_tier())
	return f.get(role, Vector3i.ZERO)


## Every teleporter pad built into the hull, as teleport destinations.
func pads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := SpcShipInterior.fixtures(Universe.hull_tier())
	out.append({
		"world": WORLD_ID, "label": "Ship",
		"pos": SpcShipInterior.SPAWN, "view": SpcShipInterior.SPAWN_VIEW,
	})
	if f.has("teleporter_bay"):
		var p: Vector3i = f["teleporter_bay"]
		out.append({
			"world": WORLD_ID, "label": "Ship — Teleporter Bay",
			"pos": Vector3(p) + Vector3(0.5, 1.0, 0.5), "view": SpcShipInterior.SPAWN_VIEW,
		})
	return out


# ------------------------------------------------------------------- lifecycle
func _on_world_ready(planet_id: String) -> void:
	if planet_id != WORLD_ID:
		return
	SpcShipInterior.build(Universe.hull_tier())
	_needs_placement = true


func _on_travel_started(from_id: String, _to_id: String) -> void:
	_leaving_ship = from_id == WORLD_ID


func _on_travel_finished(planet_id: String) -> void:
	if planet_id != WORLD_ID:
		if planet_id != Universe.OUTPOST_ID:
			last_planet = planet_id
		if _leaving_ship:
			_leaving_ship = false
			left.emit()
			Events.ship_left.emit()
		return
	if not _needs_placement:
		# A warp finished; the player is already aboard and should stay put.
		return
	_needs_placement = false
	_place_player()
	boarded.emit()
	Events.ship_boarded.emit()
	Events.toast("Aboard the %s. The cockpit is to your right."
		% Universe.upgrades.hull_name(), "info")


## Drop the player onto the boarding pad and orient the world the way the ship
## was authored: view 0 (X lateral) with the play layer on the hull's centreline.
func _place_player() -> void:
	if Game.player == null:
		return
	Universe.teleporter.snap_view(SpcShipInterior.SPAWN_VIEW)
	Game.player.teleport(SpcShipInterior.SPAWN)
	View.set_layer(floori(View.depth_of(SpcShipInterior.SPAWN)))
	World.update_streaming(Game.player.global_position)
	# `teleport()` unsticks against the world as it stands *now*, but the hull is
	# stamped in the same frame and the cockpit console sits directly above the
	# boarding pad. Re-resolve once the fixtures actually exist, or the player
	# starts the game embedded in the console.
	call_deferred(&"_resolve_spawn_overlap")


## The boarding marker only reserves the voxel the player's feet occupy, so a
## fixture placed directly above it (the cockpit console is one) leaves no
## headroom for a 1.75-block-tall body. Search outward along the view plane for
## the nearest spot that both fits the player and has something to stand on.
func _resolve_spawn_overlap() -> void:
	var p: VoxelEntity = Game.player
	if p == null:
		return
	var size := p.get_aabb_size()
	var origin := p.global_position
	if VoxelPhysics.aabb_is_free(origin, size):
		return
	var right := Vector3(View.right())
	for radius in range(1, 9):
		for dir in [1, -1]:
			for dy in [0, 1, -1, 2]:
				var cand := origin + right * float(radius * dir) + Vector3(0, dy, 0)
				if not VoxelPhysics.aabb_is_free(cand, size):
					continue
				if VoxelPhysics.ground_below(cand, 6.0) < 0.0:
					continue
				p.global_position = cand
				p.velocity = Vector3.ZERO
				return
	# Nothing suitable in the plane — fall back to lifting clear of the fixture.
	p.global_position = VoxelPhysics.unstick(origin, size, 8)
	p.velocity = Vector3.ZERO


# ------------------------------------------------------------------ save/load
func save_state() -> Dictionary:
	return {"last_planet": last_planet}


func load_state(d: Dictionary) -> void:
	last_planet = String(d.get("last_planet", ""))
