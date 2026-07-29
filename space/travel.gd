## The travel flow: pick a destination on the star map, burn fuel, watch the
## warp, then beam down.
##
## Lives at `Universe.travel`.
##
## ===========================================================================
##  THE MODEL
## ===========================================================================
## Two separate movements, exactly like Starbound:
##
##   **Warp** — the *ship* moves. `orbiting` changes, the player stays inside the
##   hull the whole time, no world is loaded or unloaded. Costs fuel and is
##   gated by the FTL tier (`Universe.can_travel_to`).
##
##   **Beam** — the *player* moves between the ship and the surface of whatever
##   the ship is orbiting. Free, handled by `space/teleporter.gd`.
##
## `travel_to()` chains the two for the star map's one-click "Travel" button.
##
## ---------------------------------------------------------------------------
##  THE WARP SPECTACLE
## ---------------------------------------------------------------------------
## The warp reuses the game's own camera language rather than inventing a new
## one: the ship *rolls*. Takeoff spins the world through two 90-degree flips at
## double speed, the warp phase holds the world sideways under a streak of
## particles and a heavy shake, and arrival completes the barrel roll with two
## more flips back into the plane you started in. The player is never moved, so
## the roll is always geometrically legal — the same guarantee that makes an
## ordinary flip safe.
##
## The camera and fx agents can drive their own effects from `warp_progress()`
## or the `warp_phase_changed` signal; nothing here touches the camera directly.
## ===========================================================================
class_name SpcTravel
extends Node

signal warp_phase_changed(phase: String, from_id: String, to_id: String)
signal orbit_changed(body_id: String)

const PHASE_IDLE := "idle"
const PHASE_TAKEOFF := "takeoff"
const PHASE_WARP := "warp"
const PHASE_ARRIVAL := "arrival"

const TAKEOFF_TIME := 1.1
const WARP_TIME := 1.5
const ARRIVAL_TIME := 0.9
## Flip speed used during the barrel roll; the normal value is restored after.
const ROLL_FLIP_DURATION := 0.22
const ROLL_STEP := 0.26

## Body id the ship is currently parked at. "" before the galaxy is generated.
var orbiting: String = ""
var warping := false
var phase: String = PHASE_IDLE
var warp_from: String = ""
var warp_to: String = ""

var _phase_started_ms: int = 0
var _phase_length: float = 0.0


# ------------------------------------------------------------------- queries
## `{phase, t, from, to, warping}` — `t` is 0..1 inside the current phase.
## Poll this from the camera rig or a screen-effect shader.
func warp_progress() -> Dictionary:
	return {
		"phase": phase,
		"t": phase_t(),
		"from": warp_from,
		"to": warp_to,
		"warping": warping,
	}


func phase_t() -> float:
	if _phase_length <= 0.0:
		return 0.0
	var elapsed := float(Time.get_ticks_msec() - _phase_started_ms) / 1000.0
	return clampf(elapsed / _phase_length, 0.0, 1.0)


## Display name of whatever the ship is orbiting.
func orbit_name() -> String:
	return Universe.body_name(orbiting) if orbiting != "" else "open space"


## Called by `Universe.generate()` — park the ship above the starting world.
func reset_orbit(body_id: String) -> void:
	orbiting = body_id
	warping = false
	_set_phase(PHASE_IDLE, 0.0)
	orbit_changed.emit(orbiting)


# ==================================================================== warping
## Move the ship to a new orbit. Validates fuel and FTL tier, deducts the fuel,
## then plays the warp. Returns false (with a toast) when the jump is refused.
func warp_to_body(body_id: String) -> bool:
	if warping:
		return false
	if body_id == orbiting:
		Events.toast("Already orbiting %s." % Universe.body_name(body_id), "info")
		return false
	var check := Universe.can_travel_to(body_id)
	if not bool(check["ok"]):
		Events.toast(String(check["reason"]), "warn")
		Events.play_sound.emit(&"denied", _player_pos())
		return false
	if not Universe.upgrades.consume_fuel(int(check["fuel"])):
		Events.toast("Not enough fuel.", "warn")
		return false
	if String(check["armour_advice"]) != "":
		Events.toast(String(check["armour_advice"]), "warn")
	_run_warp(body_id)
	return true


## Warp *and* beam down in one action — what the star map's "Travel" button does.
func travel_to(body_id: String) -> bool:
	if warping:
		return false
	# Already parked above it? Then this is just a landing.
	if body_id == orbiting:
		return Universe.teleporter.beam_down()
	if not warp_to_body(body_id):
		return false
	_beam_down_after_warp()
	return true


func _beam_down_after_warp() -> void:
	while warping:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	Universe.teleporter.beam_down()


func _run_warp(body_id: String) -> void:
	warping = true
	warp_from = orbiting
	warp_to = body_id
	var pos := _player_pos()
	var saved_view := View.view
	var saved_duration := View.flip_duration
	View.flip_duration = ROLL_FLIP_DURATION
	Events.travel_started.emit(World.planet_id, body_id)
	Events.notify.emit("Engaging %s…" % Universe.upgrades.ftl_name(), "info")

	# --- takeoff: engines light, the world begins to roll -------------------
	_set_phase(PHASE_TAKEOFF, TAKEOFF_TIME)
	Events.play_sound.emit(&"ship_takeoff", pos)
	Events.spawn_particles.emit(&"engine_burn", pos, 40)
	Events.screen_shake.emit(1.2, TAKEOFF_TIME)
	await _roll(2)
	await get_tree().create_timer(maxf(0.0, TAKEOFF_TIME - ROLL_STEP * 2.0)).timeout

	# --- warp: held sideways, streaks, the jump itself ----------------------
	_set_phase(PHASE_WARP, WARP_TIME)
	View.flips_enabled = false
	Events.play_sound.emit(&"warp_enter", pos)
	Events.spawn_particles.emit(&"warp_streaks", pos, 140)
	Events.screen_shake.emit(2.2, WARP_TIME)
	await get_tree().create_timer(WARP_TIME * 0.5).timeout
	orbiting = body_id
	Universe.discover(body_id)
	Universe.discover_system(String(Universe.body_info(body_id).get("system_id", "")))
	Universe.select(body_id)
	orbit_changed.emit(orbiting)
	Events.system_scanned.emit(String(Universe.body_info(body_id).get("system_id", "")))
	await get_tree().create_timer(WARP_TIME * 0.5).timeout

	# --- arrival: complete the barrel roll, settle back into the start plane --
	_set_phase(PHASE_ARRIVAL, ARRIVAL_TIME)
	View.flips_enabled = true
	Events.play_sound.emit(&"warp_exit", pos)
	Events.spawn_particles.emit(&"warp_bloom", pos, 60)
	await _roll(2)
	Universe.teleporter.snap_view(saved_view)
	View.flip_duration = saved_duration
	await get_tree().create_timer(maxf(0.0, ARRIVAL_TIME - ROLL_STEP * 2.0)).timeout

	_set_phase(PHASE_IDLE, 0.0)
	warping = false
	Events.travel_finished.emit(World.planet_id)
	Events.toast("Now orbiting %s. Fuel %d/%d."
		% [Universe.body_name(body_id), Universe.fuel(), Universe.fuel_capacity()], "good")


## Spin the world `count` quarter turns, using the ordinary flip machinery so
## the camera rig, the slab shader and the renderer all follow for free.
func _roll(count: int) -> void:
	for i in count:
		View.request_flip(1)
		await get_tree().create_timer(ROLL_STEP).timeout


func _set_phase(p: String, length: float) -> void:
	phase = p
	_phase_length = length
	_phase_started_ms = Time.get_ticks_msec()
	warp_phase_changed.emit(phase, warp_from, warp_to)


func _player_pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO


# ------------------------------------------------------------ beaming shortcuts
## Land on the body the ship is orbiting.
func beam_down() -> bool:
	return Universe.teleporter.beam_down()


## Return to the ship from a planet, an outpost, anywhere.
func return_to_ship() -> bool:
	if Universe.ship.is_aboard():
		Events.toast("You are already aboard.", "info")
		return false
	return Universe.teleporter.beam_up()


## Go back down to the world the player was last standing on.
func return_to_planet() -> bool:
	if not Universe.ship.is_aboard():
		return false
	var target := Universe.ship.last_planet
	if target != "" and target != orbiting and Universe.planets.has(target):
		# The ship drifted since; ask for the jump rather than teleporting there.
		return travel_to(target)
	return Universe.teleporter.beam_down()


# ------------------------------------------------------------------- save/load
func save_state() -> Dictionary:
	return {"orbiting": orbiting}


func load_state(d: Dictionary) -> void:
	orbiting = String(d.get("orbiting", orbiting))
	orbit_changed.emit(orbiting)
