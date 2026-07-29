## Depth Sight — the three layers behind you resolve into focus and become as
## solid to your tools as the one you stand in.
##
## ---------------------------------------------------------------------------
## VIEW STATE
## ---------------------------------------------------------------------------
## Mutated under `claim_view()`:
##   `Tech.depth_sight_layers` -> `LAYERS` (3)
## That single integer is the whole effect, and it is read by three consumers:
##   * the render agent, which promotes those layers out of the dimmed slab and
##     draws them at play-layer brightness (`View.shader_params()` still drives
##     the rest of the falloff);
##   * `Tech.interact_layer_tolerance()`, which `tech/interaction.gd` and the
##     Matter Manipulator consult before allowing a mine / place / interact;
##   * `Tech.combat_layer_tolerance()`, so the combat agent's reach follows.
##
## `View` itself is never written, which is what makes this tech trivially safe:
## `release_view()` sets the override back to 0 and the world snaps back to the
## normal one-layer rule. Even if this script were to fail mid-update, `Tech`'s
## watchdog zeroes the field the moment the claim is gone.
##
## While active the tech also pulses a marker particle on ore it can see behind
## the play layer, which is what makes "look through the wall" legible.
class_name TchDepthSight
extends TchBase

const LAYERS := 3
const SCAN_INTERVAL := 0.6
const SCAN_LATERAL := 10
const SCAN_VERTICAL := 6

var _scan: float = 0.0


func on_activate() -> bool:
	var p := player()
	if p == null or p.dead:
		return false
	claim_view()
	if manager != null:
		manager.set("depth_sight_layers", LAYERS)
	_scan = 0.0
	Events.spawn_particles.emit(&"tech_depth_sight", p.aabb_center(), 20)
	Events.play_sound.emit(&"tech_depth_sight", p.global_position)
	Events.toast("Depth Sight: %d layers in reach." % LAYERS, "tech")
	return true


func on_update(delta: float) -> void:
	if not active:
		return
	# Re-assert every frame: a save load or another tech's reset must not be
	# able to silently strip the effect while the timer is still running.
	if manager != null and int(manager.get("depth_sight_layers")) != LAYERS:
		manager.set("depth_sight_layers", LAYERS)
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		_highlight_ore()


## Marks ore voxels sitting in the newly reachable layers. Sampled sparsely —
## this runs six times a second at most and touches a few hundred voxels.
func _highlight_ore() -> void:
	var p := player()
	if p == null or not World.ready_flag:
		return
	var origin := Const.floor_v(p.aabb_center())
	var step := View.depth_step()
	var right := View.right()
	var found := 0
	for d in range(1, LAYERS + 1):
		for l in range(-SCAN_LATERAL, SCAN_LATERAL + 1, 2):
			for y in range(-SCAN_VERTICAL, SCAN_VERTICAL + 1, 2):
				var q := origin + step * d + right * l + Vector3i(0, y, 0)
				var bt := World.block_type_at(q)
				if bt.category != &"ore":
					continue
				Events.spawn_particles.emit(&"tech_ore_ping", Vector3(q) + Vector3(0.5, 0.5, 0.5), 1)
				found += 1
				if found >= 12:
					return


func on_deactivate() -> void:
	if manager != null:
		manager.set("depth_sight_layers", 0)
	release_view()
	var p := player()
	if p != null:
		Events.spawn_particles.emit(&"tech_depth_sight", p.aabb_center(), 10)


func modifier(stat: String) -> float:
	# Mining at arm's length through three layers is slower, not free.
	return 0.8 if (active and stat == "mining_speed") else 1.0


func hud_state() -> Dictionary:
	var d := super.hud_state()
	d["layers"] = LAYERS if active else 0
	return d
