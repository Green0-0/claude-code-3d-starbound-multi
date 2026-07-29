## What being *in* a liquid does to an entity.
##
## `VoxelEntity.integrate` already computes `submersion` and applies a generic
## gravity cut and drag, so this module only adds the parts that depend on
## *which* liquid it is: buoyancy from the liquid's density, extra viscous drag,
## the push of a current, damage / healing / status effects, drowning, and the
## splash you get for breaking the surface.
##
## Ticked at the liquid sim's 10 Hz from `Liquids._step`, over entities near the
## player only — a monster drowning two kilometres away is not worth a frame.
class_name LiqInteraction
extends RefCounted

## Entities further than this from the player are ignored entirely.
const RANGE := 72.0
## Seconds of breath a fresh entity has.
const MAX_BREATH := 12.0
## Damage per second once breath runs out.
const DROWN_DAMAGE := 6.0
## Submersion at which the surface is considered "broken" for splash purposes.
const SPLASH_AT := 0.15
const SPLASH_SPEED := 3.0
## The generic drag VoxelEntity already applies; per-liquid drag is on top.
const BASE_DRAG := 3.5
## Seconds between refreshes of the submerged status effect, so the status
## system and the HUD are not spammed ten times a second.
const STATUS_REFRESH := 0.5
## Fraction of gravity VoxelEntity leaves on while submerged.
const SUBMERGED_GRAVITY := 0.32


var _state: Dictionary = {}     ## entity instance id -> Dictionary
var _rng := RandomNumberGenerator.new()
var _survival_breath := false   ## refreshed each tick, see _survival_owns_breath


func tick(dt: float) -> void:
	if Game.main == null:
		return
	var tree := Game.get_tree()
	if tree == null:
		return
	var env: Variant = Status.get(&"environment")
	_survival_breath = env is Object and (env as Object).has_method(&"breath_fraction")
	var player_pos := Game.player.global_position if Game.player != null else Vector3.ZERO
	var r2 := RANGE * RANGE
	var seen: Dictionary = {}
	for n: Node in tree.get_nodes_in_group(&"entities"):
		var e := n as VoxelEntity
		if e == null or e.dead or not e.affected_by_liquid:
			continue
		if e != Game.player and e.global_position.distance_squared_to(player_pos) > r2:
			continue
		seen[e.get_instance_id()] = true
		_apply(e, dt)
	# Drop state for entities that died, despawned or wandered out of range.
	if _state.size() > seen.size():
		for k: int in _state.keys():
			if not seen.has(k):
				_state.erase(k)


# ------------------------------------------------------------------ per-entity
func _apply(e: VoxelEntity, dt: float) -> void:
	var id := e.get_instance_id()
	var st: Dictionary = _state.get(id, {})
	if st.is_empty():
		st = {"breath": MAX_BREATH, "sub": 0.0, "liquid": &"", "splash": 0.0, "status_cd": 0.0}
		_state[id] = st

	var sub: float = e.submersion
	var prev: float = float(st["sub"])
	st["sub"] = sub
	st["splash"] = maxf(0.0, float(st["splash"]) - dt)

	var body := _liquid_voxel(e)
	var params := LiqType.for_block(World.get_block(body))

	# ---- surface crossing ------------------------------------------------
	if (prev < SPLASH_AT) != (sub < SPLASH_AT) and float(st["splash"]) <= 0.0:
		st["splash"] = 0.35
		_splash(e, params, absf(e.velocity.y))

	if sub <= 0.0 or params.is_empty():
		st["liquid"] = &""
		_recover_breath(e, st, dt)
		return

	st["liquid"] = StringName(params.get("name", &""))

	# ---- buoyancy ---------------------------------------------------------
	# A buoyancy of 1.0 exactly cancels the gravity VoxelEntity leaves on while
	# submerged, so a neutral swimmer hangs where they are; lava (1.9) shoves
	# you to the surface, liquid nitrogen (0.85) lets you sink.
	var buoy := float(params.get("buoyancy", 1.0))
	if sub > 0.05:
		e.velocity.y += buoy * SUBMERGED_GRAVITY * Const.GRAVITY * sub * dt

	# ---- viscous drag on top of the generic one --------------------------
	var extra := maxf(0.0, float(params.get("drag", BASE_DRAG)) - BASE_DRAG)
	if extra > 0.0:
		e.velocity *= 1.0 - minf(0.85, extra * dt * sub)

	# ---- current ----------------------------------------------------------
	var current := float(params.get("current", 1.0))
	if current > 0.0:
		var dir := Liquids.flow_dir_at(body)
		if dir != Vector3.ZERO:
			e.velocity += dir * current * 5.0 * sub * dt

	# ---- damage / healing / status ---------------------------------------
	# `VoxelEntity._apply_touch_damage` already applies the block's own
	# `damage_on_touch`, and the block-content agent installs `on_entity_inside`
	# hooks for things like healing water. Only the *surplus* is ours, or the
	# player would take lava damage twice.
	var bt := Blocks.get_type(World.get_block(body))
	var dmg := maxf(0.0, float(params.get("damage", 0.0)) - bt.damage_on_touch) * sub
	if dmg > 0.0:
		e.apply_damage(dmg * dt, String(params.get("element", Const.ELEM_PHYSICAL)), null)
	if not bt.on_entity_inside.is_valid():
		var heal := float(params.get("heal", 0.0)) * sub
		if heal > 0.0:
			e.heal(heal * dt)

	var status := StringName(params.get("status", &""))
	st["status_cd"] = float(st.get("status_cd", 0.0)) - dt
	if status != &"" and sub > 0.25 and float(st["status_cd"]) <= 0.0 and Status.has_method(&"apply"):
		st["status_cd"] = STATUS_REFRESH
		Status.apply(status, e, float(params.get("status_time", 3.0)))

	# ---- breathing --------------------------------------------------------
	if bool(params.get("breathable", false)) or not _head_submerged(e):
		_recover_breath(e, st, dt)
	else:
		_drain_breath(e, st, dt)

	# ---- ambience ---------------------------------------------------------
	if e == Game.player and _rng.randf() < dt * 0.5:
		var amb := StringName(params.get("ambient", &""))
		if amb != &"":
			Events.play_sound.emit(amb, e.global_position)


## Does the survival agent's environment module already run the player's breath?
## Re-probed once per tick rather than per entity — the module can appear at any
## time, but not twice in a hundred milliseconds.
func _survival_owns_breath() -> bool:
	return _survival_breath


## Voxel used to sample "which liquid am I in" — the middle of the box.
func _liquid_voxel(e: VoxelEntity) -> Vector3i:
	var c := e.aabb_center()
	var p := Vector3i(floori(c.x), floori(c.y), floori(c.z))
	if Blocks.is_liquid(World.get_block(p)):
		return World.normalize(p)
	var feet := e.global_position + Vector3(0.0, 0.2, 0.0)
	return World.normalize(Vector3i(floori(feet.x), floori(feet.y), floori(feet.z)))


func _head_submerged(e: VoxelEntity) -> bool:
	var head := e.global_position + Vector3(0.0, e.box_size.y * 0.9, 0.0)
	return Blocks.is_liquid(World.get_block(Const.floor_v(head)))


## Drowning. The survival agent owns the *player's* breath meter whenever it is
## installed — duplicating it would fight over the HUD bar and double the
## damage — so this only ever runs for monsters, NPCs and the survival-less
## fallback case.
func _drain_breath(e: VoxelEntity, st: Dictionary, dt: float) -> void:
	if e == Game.player and _survival_owns_breath():
		return
	var b := maxf(0.0, float(st["breath"]) - dt)
	st["breath"] = b
	if e == Game.player:
		Events.stat_changed.emit("breath", b, MAX_BREATH)
	if b > 0.0:
		if _rng.randf() < dt * 1.5:
			Events.spawn_particles.emit(&"bubble", e.aabb_center(), 2)
		return
	# Out of air. The survival agent owns drowning if it wants it.
	if Status.has_method(&"apply"):
		Status.apply(&"drowning", e, 2.0)
	e.apply_damage(DROWN_DAMAGE * dt, Const.ELEM_PHYSICAL, null)
	if e == Game.player and _rng.randf() < dt * 2.0:
		Events.play_sound.emit(&"drown", e.global_position)


func _recover_breath(e: VoxelEntity, st: Dictionary, dt: float) -> void:
	if e == Game.player and _survival_owns_breath():
		return
	var b := float(st["breath"])
	if b >= MAX_BREATH:
		return
	b = minf(MAX_BREATH, b + dt * 3.0)
	st["breath"] = b
	if e == Game.player:
		Events.stat_changed.emit("breath", b, MAX_BREATH)


func _splash(e: VoxelEntity, params: Dictionary, speed: float) -> void:
	if params.is_empty():
		return
	var amount := clampi(int(4.0 + speed * 2.0), 4, 26)
	var at := e.global_position + Vector3(0.0, e.box_size.y * 0.35, 0.0)
	Events.spawn_particles.emit(StringName(params.get("splash", &"splash_water")), at, amount)
	if speed > SPLASH_SPEED:
		Events.play_sound.emit(StringName(params.get("enter_sound", &"splash")), at)


# ================================================================ public API
## Breath remaining, 0..[constant MAX_BREATH]. The HUD and the survival agent
## can read this instead of tracking their own.
func breath_of(e: VoxelEntity) -> float:
	var st: Dictionary = _state.get(e.get_instance_id(), {})
	return float(st.get("breath", MAX_BREATH))


func set_breath(e: VoxelEntity, value: float) -> void:
	var st: Dictionary = _state.get(e.get_instance_id(), {})
	if not st.is_empty():
		st["breath"] = clampf(value, 0.0, MAX_BREATH)


## Liquid the entity is currently in, or `&""`.
func liquid_of(e: VoxelEntity) -> StringName:
	var st: Dictionary = _state.get(e.get_instance_id(), {})
	return StringName(st.get("liquid", &""))


## True when the entity is deep enough that walking becomes swimming.
func is_swimming(e: VoxelEntity) -> bool:
	return e.submersion > 0.55


## Swim control for the player / aquatic monsters, in **plane space** so it
## works identically in all four views.
##
## `plane_dir` is (screen-right, up) in -1..1; call this instead of the normal
## ground movement while [method is_swimming] is true.
func swim(e: VoxelEntity, plane_dir: Vector2, dt: float) -> void:
	var params := LiqType.for_block(World.get_block(_liquid_voxel(e)))
	if params.is_empty():
		return
	var mult := float(params.get("swim_speed", 0.65))
	var accel := e.move_speed * mult * 6.0 * dt
	var world := View.plane_dir_to_world(plane_dir)
	e.velocity.x += world.x * accel
	e.velocity.z += world.z * accel
	e.velocity.y += plane_dir.y * accel * 1.35
	var limit := e.move_speed * mult
	var lateral := Const.lateral_of(e.velocity, View.view)
	if absf(lateral) > limit:
		e.set_plane_velocity(signf(lateral) * limit)
	e.velocity.y = clampf(e.velocity.y, -limit * 1.6, limit * 1.6)


## Camera tint for a fully-submerged view, or a transparent colour. The camera
## agent can blend toward this using the player's `submersion`.
func camera_fog() -> Color:
	if Game.player == null:
		return Color(0, 0, 0, 0)
	if Game.player.submersion < 0.5:
		return Color(0, 0, 0, 0)
	return LiqType.fog_of(World.get_block(_liquid_voxel(Game.player)))
