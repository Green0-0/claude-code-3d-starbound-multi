## A pooled projectile. One script drives every arrow, bullet, fireball,
## grenade, boomerang and beam in the game; behaviour comes entirely from a
## [CbtProjectileTypes] definition plus per-shot overrides.
##
## ## Why the position is world-space and the aiming is plane-space
##
## Projectiles are launched with a **plane-space direction** — that is how the
## player aims, and it is view-independent by construction. The moment it is
## launched the direction becomes a real world vector, so a projectile in
## flight is a genuine 3D object: if you flip the camera mid-shot you see the
## arrow from the side, still going where it was going. Only *hit resolution*
## re-reads the current view, because "can this hit me" is a question about the
## plane you are standing in right now.
##
## ## Pooling
##
## Nodes are recycled through a static free-list. [method spawn] is the only
## entry point; a projectile returns itself to the pool when it dies. Never
## `queue_free()` one yourself.
##
## ```gdscript
## CbtProjectile.spawn(&"arrow", muzzle_world_pos, aim_plane_dir, player, {
##     "damage": 14.0, "crit_chance": 0.2, "weapon": stack,
## })
## ```
class_name CbtProjectile
extends Node3D

## Emitted when this projectile damages something.
signal struck(entity: VoxelEntity, damage: float)
## Emitted just before it returns to the pool.
signal finished(projectile: CbtProjectile)

const MAX_LIVE := 220
const TRAIL_POINTS := 10

## Free-list of despawned projectiles. Deliberately untyped: a static var whose
## element type is the class currently being defined is a load-order hazard.
static var _pool: Array = []
static var _live: int = 0
static var _rng := RandomNumberGenerator.new()
static var _seeded := false

var def: Dictionary = {}
var type_id: StringName = &""
var shooter: Node = null
var packet: Dictionary = {}

var velocity: Vector3 = Vector3.ZERO
var alive: bool = false
var age: float = 0.0
var life: float = 3.0
var pierce_left: int = 0
var bounce_left: int = 0
var radius: float = 0.3
var gravity: float = 0.0
var drag: float = 0.0
var homing: float = 0.0
var homing_range: float = 0.0
var returning: bool = false
var return_after: float = 0.5
var spin: float = 0.0
var ghost: bool = false
var stick: bool = false
var stuck: bool = false
var mining_tier: int = -1

var _hit_ids: Dictionary = {}
var _homing_target: VoxelEntity = null
var _trail: PackedVector3Array = PackedVector3Array()
var _mi: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _trail_mi: MeshInstance3D = null
var _trail_mesh: ImmediateMesh = null
var _trail_mat: StandardMaterial3D = null
var _tverts := PackedVector3Array()
var _tcols := PackedColorArray()
var _spin_angle: float = 0.0
var _origin_layer: int = 0
var _particle_timer: float = 0.0


# ==================================================================== spawning
## Fire a projectile. `dir_plane` is `(lateral, up)` in the current view; it is
## converted to a world vector immediately. `overrides` are merged over the
## type definition, and additionally understand the damage-packet keys
## `weapon`, `damage_mult`, `scale`, `crit_chance`, `crit_mult`, `pierce`
## (armour piercing, a float) and `status_on_hit`.
static func spawn(type_id_p: StringName, world_pos: Vector3, dir_plane: Vector2,
		shooter_p: Node = null, overrides: Dictionary = {}) -> CbtProjectile:
	if not _seeded:
		_rng.randomize()
		_seeded = true
	if _live >= MAX_LIVE:
		return null
	var d := CbtProjectileTypes.get_def(type_id_p)
	for k: String in overrides:
		d[k] = overrides[k]

	var p := _take()
	if p == null:
		return null
	p.type_id = type_id_p
	p.shooter = shooter_p
	p._configure(d)
	p.global_position = world_pos
	var dir := dir_plane
	if dir.length_squared() < 0.000001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var speed := float(d.get("speed", 22.0))
	p.velocity = View.plane_dir_to_world(dir) * speed
	var depth_speed := float(d.get("depth_speed", 0.0))
	if absf(depth_speed) > 0.001:
		p.velocity += Vector3(View.depth_step()) * depth_speed
	p._launch()
	Events.projectile_spawned.emit(p)
	var snd := StringName(d.get("fire_sound", &"shoot"))
	if snd != &"":
		Events.play_sound.emit(String(snd), world_pos)
	return p


## Fire `count` projectiles in a fan of `spread_deg` total. Shotguns, flak,
## fragment bursts.
static func spawn_spread(type_id_p: StringName, world_pos: Vector3, dir_plane: Vector2,
		count: int, spread_deg: float, shooter_p: Node = null,
		overrides: Dictionary = {}) -> Array[CbtProjectile]:
	var out: Array[CbtProjectile] = []
	if count <= 0:
		return out
	if not _seeded:
		_rng.randomize()
		_seeded = true
	var base := rad_to_deg(atan2(dir_plane.y, dir_plane.x))
	for i in count:
		var f := 0.0 if count == 1 else (float(i) / float(count - 1)) - 0.5
		var jitter := _rng.randf_range(-0.12, 0.12) * spread_deg
		var a := deg_to_rad(base + f * spread_deg + jitter)
		var o := overrides.duplicate(true)
		# Vary speed slightly so the cluster spreads out over distance.
		o["speed"] = float(o.get("speed", CbtProjectileTypes.get_def(type_id_p)["speed"])) \
			* _rng.randf_range(0.88, 1.12)
		var p := spawn(type_id_p, world_pos, Vector2(cos(a), sin(a)), shooter_p, o)
		if p != null:
			out.append(p)
	return out


## Cross-module entry point, used by `Game.spawn_entity("res://combat/
## projectile.tscn", pos, setup)` — this is the contract the monster module
## already calls against.
##
## `setup` keys: `projectile` (a [CbtProjectileTypes] id), `direction`
## (world `Vector3` **or** plane `Vector2`), `damage`, `element`, `speed`,
## `source`/`shooter`, `pierce_layers` (bool -> hits every depth layer), plus
## any other definition key, which overrides the type.
func configure(setup: Dictionary) -> void:
	var id := StringName(setup.get("projectile", &"bullet"))
	if not CbtProjectileTypes.has(id):
		id = &"bullet"
	var d := CbtProjectileTypes.get_def(id)
	const SKIP := ["projectile", "direction", "source", "shooter", "faction", "pierce_layers"]
	for k: String in setup:
		if not SKIP.has(k):
			d[k] = setup[k]
	if bool(setup.get("pierce_layers", false)):
		d["layer_rule"] = CbtDamage.LAYER_ALL
	type_id = id
	var src: Variant = setup.get("source", setup.get("shooter", null))
	shooter = src as Node
	_configure(d)

	var dir_world := Vector3.ZERO
	var dv: Variant = setup.get("direction", null)
	if dv is Vector3:
		dir_world = dv
	elif dv is Vector2:
		dir_world = View.plane_dir_to_world((dv as Vector2).normalized())
	if dir_world.length_squared() < 0.000001:
		dir_world = View.plane_dir_to_world(Vector2.RIGHT)
	velocity = dir_world.normalized() * float(d.get("speed", 22.0))
	var ds := float(d.get("depth_speed", 0.0))
	if absf(ds) > 0.001:
		velocity += Vector3(View.depth_step()) * ds
	_launch()
	Events.projectile_spawned.emit(self)


## Number of projectiles currently in flight.
static func live_count() -> int:
	return _live


## Kill everything in flight — used on planet travel and world unload.
static func clear_all() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for n: Node in tree.get_nodes_in_group(&"projectiles"):
		var p := n as CbtProjectile
		if p != null and p.alive:
			p._despawn(false)


static func _take() -> CbtProjectile:
	while not _pool.is_empty():
		var p: CbtProjectile = _pool.pop_back()
		if is_instance_valid(p) and p.is_inside_tree():
			return p
	var np := CbtProjectile.new()
	var parent: Node = Game.fx_root
	if parent == null:
		parent = Game.entities_root
	if parent == null:
		parent = Game.main
	if parent == null:
		var tree := Engine.get_main_loop() as SceneTree
		parent = tree.current_scene if tree != null else null
	if parent == null:
		return null
	parent.add_child(np)
	return np


# ====================================================================== set-up
func _ready() -> void:
	add_to_group(&"projectiles")
	_build_visual()
	visible = false
	set_physics_process(false)
	set_process(false)


func _build_visual() -> void:
	if _mi != null:
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.14, 0.14)
	_mi = MeshInstance3D.new()
	_mi.mesh = box
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.layers = Const.RL_EFFECTS
	add_child(_mi)

	_trail_mesh = ImmediateMesh.new()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mi = MeshInstance3D.new()
	_trail_mi.mesh = _trail_mesh
	_trail_mi.material_override = _trail_mat
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mi.layers = Const.RL_EFFECTS
	_trail_mi.top_level = true
	add_child(_trail_mi)


func _configure(d: Dictionary) -> void:
	_build_visual()   # pooled nodes already have one; a brand new one may not
	def = d
	life = float(d.get("lifetime", 3.0))
	radius = float(d.get("radius", 0.3))
	gravity = float(d.get("gravity", 0.0))
	drag = float(d.get("drag", 0.0))
	pierce_left = int(d.get("pierce", 0))
	bounce_left = int(d.get("bounce", 0))
	homing = float(d.get("homing", 0.0))
	homing_range = float(d.get("homing_range", 12.0))
	returning = bool(d.get("returns", false))
	return_after = float(d.get("return_after", 0.5))
	spin = float(d.get("spin", 0.0))
	ghost = bool(d.get("ghost", false))
	stick = bool(d.get("stick", false))
	mining_tier = int(d.get("break_blocks", -1))
	_origin_layer = int(d.get("origin_layer", View.layer))

	packet = CbtDamage.default_packet()
	packet["amount"] = float(d.get("damage", 6.0))
	packet["element"] = String(d.get("element", Const.ELEM_PHYSICAL))
	packet["source"] = shooter
	packet["weapon"] = d.get("weapon", null)
	packet["scale"] = float(d.get("scale", 1.0))
	packet["crit_chance"] = float(d.get("crit_chance", 0.05))
	packet["crit_mult"] = float(d.get("crit_mult", 1.75))
	packet["knockback"] = float(d.get("knockback", 3.0))
	packet["pierce"] = float(d.get("armor_pierce", 0.0))
	packet["layer_rule"] = int(d.get("layer_rule", CbtDamage.LAYER_SAME))
	packet["layer_min"] = int(d.get("layer_min", 0))
	packet["layer_max"] = int(d.get("layer_max", 0))
	packet["layer_falloff"] = float(d.get("layer_falloff", 1.0))
	packet["origin_layer"] = _origin_layer
	var st: Variant = d.get("status_on_hit", [])
	packet["status_on_hit"] = (st as Array).duplicate(true) if st is Array else []

	var col: Color = d.get("color", Color.WHITE)
	var glow := float(d.get("glow", 1.0))
	_mat.albedo_color = col
	_mat.emission_enabled = glow > 0.01
	_mat.emission = col
	_mat.emission_energy_multiplier = glow
	var size: Vector2 = d.get("size", Vector2(0.5, 0.14))
	(_mi.mesh as BoxMesh).size = Vector3(size.x, size.y, size.y)
	_trail_mat.albedo_color = col


func _launch() -> void:
	alive = true
	stuck = false
	age = 0.0
	_spin_angle = 0.0
	_particle_timer = 0.0
	_hit_ids.clear()
	_homing_target = null
	_trail.clear()
	visible = true
	_trail_mi.visible = float(def.get("trail", 0.0)) > 0.001
	set_physics_process(true)
	set_process(true)
	_live += 1
	_orient()


# ===================================================================== flight
func _physics_process(delta: float) -> void:
	if not alive:
		return
	age += delta
	if age >= life:
		_expire()
		return
	if stuck:
		return

	if homing > 0.0:
		_steer_homing(delta)
	if returning and age >= return_after:
		_steer_return(delta)

	if absf(gravity) > 0.0001:
		velocity.y -= Const.GRAVITY * gravity * delta
	if drag > 0.0:
		velocity *= maxf(0.0, 1.0 - drag * delta)

	var step := velocity * delta
	var dist := step.length()
	if dist < 0.00001:
		return
	var from := global_position
	var dir := step / dist

	# ---- voxel collision, unless the projectile is a ghost.
	var travelled := dist
	if not ghost:
		var hit := World.raycast(from, dir, dist + radius * 0.5)
		if bool(hit.get("hit", false)):
			travelled = minf(dist, maxf(0.0, float(hit.get("distance", dist)) - 0.02))
			global_position = from + dir * travelled
			_sweep_entities(from, global_position)
			_on_block_hit(hit, dir)
			return
	global_position = from + dir * travelled

	_sweep_entities(from, global_position)
	if not alive:
		return

	# ---- fell out of the world?
	if global_position.y < -4.0 or global_position.y > float(Const.WORLD_HEIGHT) + 64.0:
		_despawn(false)
		return

	_push_trail()
	_orient()
	_emit_particles(delta)


func _process(delta: float) -> void:
	if not alive:
		return
	if spin > 0.0:
		_spin_angle += spin * delta
	if _trail_mi.visible:
		_rebuild_trail()


func _steer_homing(delta: float) -> void:
	if _homing_target == null or not is_instance_valid(_homing_target) or _homing_target.dead:
		_homing_target = _acquire_target()
	if _homing_target == null:
		return
	var want := _homing_target.aabb_center() - global_position
	if want.length_squared() < 0.0001:
		return
	var speed := velocity.length()
	var cur := velocity / maxf(0.0001, speed)
	var goal := want.normalized()
	var turn := homing * delta
	var new_dir := cur.slerp(goal, clampf(turn, 0.0, 1.0)) if cur.dot(goal) > -0.999 else goal
	velocity = new_dir.normalized() * speed


func _acquire_target() -> VoxelEntity:
	var o := CbtTargeting.default_opts()
	o["layer_rule"] = int(packet.get("layer_rule", CbtDamage.LAYER_SAME))
	o["layer_min"] = int(packet.get("layer_min", 0))
	o["layer_max"] = int(packet.get("layer_max", 0))
	o["origin_layer"] = _origin_layer
	o["exclude"] = shooter
	if shooter is VoxelEntity:
		o["hostile_to"] = shooter
	return CbtTargeting.nearest(View.to_plane(global_position), homing_range, o)


func _steer_return(delta: float) -> void:
	var home: Node3D = shooter as Node3D
	if home == null or not is_instance_valid(home):
		_expire()
		return
	var want := home.global_position + Vector3(0, 0.9, 0) - global_position
	var d := want.length()
	if d < 1.1:
		# Caught. Boomerangs never explode on the thrower.
		_despawn(false)
		return
	var speed := velocity.length()
	velocity = velocity.lerp(want.normalized() * speed, clampf(6.0 * delta, 0.0, 1.0))
	# Re-arm so it can hit things again on the way back.
	if absf(age - return_after) < delta * 1.5:
		_hit_ids.clear()


# ============================================================ hit resolution
func _sweep_entities(from: Vector3, to: Vector3) -> void:
	var a := View.to_plane(from)
	var b := View.to_plane(to)
	var o := CbtTargeting.default_opts()
	o["layer_rule"] = int(packet.get("layer_rule", CbtDamage.LAYER_SAME))
	o["layer_min"] = int(packet.get("layer_min", 0))
	o["layer_max"] = int(packet.get("layer_max", 0))
	# The rule is measured from where the shot *is*, so a depth-travelling
	# projectile keeps hitting new layers as it recedes.
	o["origin_layer"] = _origin_layer if float(def.get("depth_speed", 0.0)) == 0.0 \
		else floori(View.depth_of(global_position))
	o["exclude"] = shooter
	if shooter is VoxelEntity:
		o["hostile_to"] = shooter
	var found := CbtTargeting.in_capsule(a, b, radius, o)
	for e: VoxelEntity in found:
		if not alive:
			return
		var key := e.get_instance_id()
		if _hit_ids.has(key):
			continue
		_hit_ids[key] = true
		var p := packet.duplicate(true)
		p["origin_layer"] = o["origin_layer"]
		p["knockback_dir"] = Vector2(View.lateral_of(velocity), maxf(0.0, velocity.y)).normalized()
		var dealt := CbtDamage.apply(e, p)
		if dealt <= 0.0:
			continue
		struck.emit(e, dealt)
		CbtMeleeFx.hit_feedback(e.aabb_center(), String(packet.get("element", Const.ELEM_PHYSICAL)),
			clampf(dealt / 30.0, 0.15, 1.2), false)
		_do_chain(e, dealt)
		pierce_left -= 1
		if pierce_left < 0:
			_impact(global_position, Vector3i.ZERO)
			return


func _do_chain(from_entity: VoxelEntity, dealt: float) -> void:
	var chain: Variant = def.get("chain", {})
	if not (chain is Dictionary) or (chain as Dictionary).is_empty():
		return
	var c := chain as Dictionary
	var count := int(c.get("count", 0))
	var reach := float(c.get("range", 6.0))
	var falloff := float(c.get("falloff", 0.65))
	if count <= 0:
		return
	var current := from_entity
	var amount := dealt
	var seen := {from_entity.get_instance_id(): true}
	for i in count:
		var o := CbtTargeting.default_opts()
		o["origin_layer"] = floori(View.depth_of(current.global_position))
		o["exclude"] = shooter
		if shooter is VoxelEntity:
			o["hostile_to"] = shooter
		var near := CbtTargeting.in_circle(CbtTargeting.plane_center(current), reach, o)
		var next: VoxelEntity = null
		for e: VoxelEntity in near:
			if seen.has(e.get_instance_id()):
				continue
			next = e
			break
		if next == null:
			return
		seen[next.get_instance_id()] = true
		amount *= falloff
		var p := packet.duplicate(true)
		p["amount"] = amount
		p["scale"] = 1.0
		p["variance"] = 0.0
		p["can_crit"] = false
		p["origin_layer"] = floori(View.depth_of(next.global_position))
		p["layer_rule"] = CbtDamage.LAYER_SAME
		CbtDamage.apply(next, p)
		CbtMeleeFx.beam(CbtTargeting.plane_center(current), CbtTargeting.plane_center(next),
			0.12, CbtMeleeFx.element_color(String(packet.get("element", Const.ELEM_ELECTRIC))), 0.14)
		current = next


func _on_block_hit(hit: Dictionary, dir: Vector3) -> void:
	var pos: Vector3i = hit.get("pos", Vector3i.ZERO)
	var normal: Vector3i = hit.get("normal", Vector3i.ZERO)

	# ---- mining projectiles chew straight through.
	if mining_tier >= 0:
		var br := float(def.get("break_radius", 0.0))
		if br > 0.01:
			_carve(Vector3(pos) + Vector3(0.5, 0.5, 0.5), br)
		else:
			World.break_block(pos, mining_tier, true)
			Game.bump_stat("blocks_mined", 1.0)
		if float(def.get("explode_radius", 0.0)) <= 0.0:
			# Keep flying through the hole it just made.
			global_position += dir * 0.35
			return

	# ---- bounce.
	if bounce_left > 0 and float(def.get("explode_radius", 0.0)) <= 0.0:
		bounce_left -= 1
		var n := Vector3(normal)
		if n.length_squared() > 0.0:
			velocity = velocity.bounce(n.normalized()) * float(def.get("bounciness", 0.55))
		else:
			velocity = -velocity * float(def.get("bounciness", 0.55))
		global_position += Vector3(normal) * 0.06
		Events.play_sound.emit(&"bounce", global_position)
		# Bouncing re-arms the hit set: a ricochet can hit the same target twice.
		_hit_ids.clear()
		return

	if stick and float(def.get("explode_radius", 0.0)) <= 0.0:
		stuck = true
		velocity = Vector3.ZERO
		life = minf(life, age + 8.0)
		return

	_impact(global_position, normal)


func _impact(at: Vector3, _normal: Vector3i) -> void:
	if not alive:
		return
	var element := String(packet.get("element", Const.ELEM_PHYSICAL))
	var er := float(def.get("explode_radius", 0.0))
	if er > 0.01:
		var blast := packet.duplicate(true)
		blast["amount"] = float(packet.get("amount", 6.0)) * 1.0
		blast["knockback"] = float(packet.get("knockback", 3.0)) * 1.3
		blast["ignore_iframes"] = true
		blast["origin_layer"] = floori(View.depth_of(at))
		CbtDamage.apply_radial(at, er, blast, null)
		var br := float(def.get("break_radius", 0.0))
		if br > 0.01 and mining_tier >= 0:
			World.explode(at, br, float(def.get("explode_power", 3.0)))
		CbtMeleeFx.ring(at, er, CbtMeleeFx.element_color(element), 0.32,
			_depth_span())
		Events.spawn_particles.emit(&"explosion", at, 24)
		Events.play_sound.emit(&"explosion", at)
		CbtMeleeFx.hit_stop(0.5)
	else:
		CbtMeleeFx.impact(at, 0.5, CbtMeleeFx.element_color(element), 0.14)
		var snd := StringName(def.get("hit_sound", &"hit"))
		if snd != &"":
			Events.play_sound.emit(String(snd), at)
	_spawn_children("hit")
	_despawn(false)


func _expire() -> void:
	if not alive:
		return
	if float(def.get("explode_radius", 0.0)) > 0.01:
		# Timed explosives (grenades) detonate on the fuse, not on contact.
		_spawn_children("expire")
		var element := String(packet.get("element", Const.ELEM_PHYSICAL))
		var er := float(def.get("explode_radius", 0.0))
		var blast := packet.duplicate(true)
		blast["ignore_iframes"] = true
		blast["origin_layer"] = floori(View.depth_of(global_position))
		CbtDamage.apply_radial(global_position, er, blast, null)
		if mining_tier >= 0:
			World.explode(global_position, float(def.get("break_radius", er * 0.6)),
				float(def.get("explode_power", 3.0)))
		CbtMeleeFx.ring(global_position, er, CbtMeleeFx.element_color(element), 0.32, _depth_span())
		Events.spawn_particles.emit(&"explosion", global_position, 24)
		Events.play_sound.emit(&"explosion", global_position)
		CbtMeleeFx.hit_stop(0.5)
		_despawn(false)
		return
	_spawn_children("expire")
	_despawn(true)


func _spawn_children(phase: String) -> void:
	var c: Variant = def.get("children", {})
	if not (c is Dictionary) or (c as Dictionary).is_empty():
		return
	var cd := c as Dictionary
	var on := String(cd.get("on", "hit"))
	if on != phase and on != "both":
		return
	var child_id := StringName(cd.get("type", &""))
	if child_id == &"" or not CbtProjectileTypes.has(child_id):
		return
	var count := int(cd.get("count", 1))
	var spread := float(cd.get("spread", 60.0))
	var base := View.lateral_of(velocity)
	var dir := Vector2(base, velocity.y)
	if dir.length_squared() < 0.0001:
		dir = Vector2.UP
	var ov := {"origin_layer": floori(View.depth_of(global_position))}
	if cd.has("speed"):
		ov["speed"] = float(cd["speed"])
	if bool(cd.get("inherit", true)):
		ov["scale"] = float(packet.get("scale", 1.0))
		ov["weapon"] = packet.get("weapon", null)
	spawn_spread(child_id, global_position, dir.normalized(), count, spread, shooter, ov)


func _carve(center: Vector3, r: float) -> void:
	var ri := ceili(r)
	var c := Const.floor_v(center)
	for dx in range(-ri, ri + 1):
		for dy in range(-ri, ri + 1):
			for dz in range(-ri, ri + 1):
				var p := c + Vector3i(dx, dy, dz)
				if Vector3(dx, dy, dz).length() > r:
					continue
				if World.get_block(p) == Const.AIR:
					continue
				World.break_block(p, mining_tier, true)


func _depth_span() -> float:
	if int(packet.get("layer_rule", CbtDamage.LAYER_SAME)) != CbtDamage.LAYER_RANGE:
		return 0.0
	return float(maxi(0, int(packet.get("layer_max", 0)) - int(packet.get("layer_min", 0))))


# ==================================================================== visuals
func _orient() -> void:
	var f := velocity
	if f.length_squared() < 0.0001:
		return
	f = f.normalized()
	var up := Vector3.UP
	if absf(f.dot(up)) > 0.995:
		up = Vector3(View.right())
	var z := f.cross(up)
	if z.length_squared() < 0.000001:
		return
	z = z.normalized()
	var y := z.cross(f)
	var b := Basis(f, y, z)
	if spin > 0.0:
		b = b.rotated(f, _spin_angle)
	global_transform = Transform3D(b, global_position)


func _push_trail() -> void:
	if float(def.get("trail", 0.0)) <= 0.001:
		return
	_trail.append(global_position)
	while _trail.size() > TRAIL_POINTS:
		_trail.remove_at(0)


func _rebuild_trail() -> void:
	if _trail_mesh == null:
		return
	_trail_mesh.clear_surfaces()
	if _trail.size() < 2:
		return
	_tverts.clear()
	_tcols.clear()
	var w := float(def.get("trail", 0.1))
	var col: Color = def.get("color", Color.WHITE)
	var n := _trail.size()
	for i in n - 1:
		var a := _trail[i]
		var b := _trail[i + 1]
		var seg := b - a
		if seg.length_squared() < 0.000001:
			continue
		var side := seg.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = seg.cross(Vector3(View.right()))
		side = side.normalized()
		var f0 := float(i) / float(n - 1)
		var f1 := float(i + 1) / float(n - 1)
		var ca := Color(col.r, col.g, col.b, f0 * 0.75)
		var cb := Color(col.r, col.g, col.b, f1 * 0.75)
		_tri(a - side * w * f0, a + side * w * f0, b + side * w * f1, ca, ca, cb)
		_tri(a - side * w * f0, b + side * w * f1, b - side * w * f1, ca, cb, cb)
	if _tverts.is_empty():
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _tverts.size():
		_trail_mesh.surface_set_color(_tcols[i])
		_trail_mesh.surface_add_vertex(_tverts[i])
	_trail_mesh.surface_end()


func _tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_tverts.push_back(a)
	_tcols.push_back(ca)
	_tverts.push_back(b)
	_tcols.push_back(cb)
	_tverts.push_back(c)
	_tcols.push_back(cc)


func _emit_particles(delta: float) -> void:
	var pid := StringName(def.get("particles", &""))
	if pid == &"":
		return
	_particle_timer -= delta
	if _particle_timer > 0.0:
		return
	_particle_timer = 0.06
	Events.spawn_particles.emit(String(pid), global_position, 2)


# =================================================================== teardown
## `fizzle` draws a small puff — used when a projectile simply runs out of
## lifetime rather than hitting something.
func _despawn(fizzle: bool) -> void:
	if not alive:
		return
	alive = false
	_live = maxi(0, _live - 1)
	if fizzle and float(def.get("glow", 0.0)) > 0.5:
		Events.spawn_particles.emit(&"fizzle", global_position, 3)
	visible = false
	_trail.clear()
	if _trail_mesh != null:
		_trail_mesh.clear_surfaces()
	set_physics_process(false)
	set_process(false)
	velocity = Vector3.ZERO
	shooter = null
	finished.emit(self)
	# Drop every listener from the previous shot so a pooled node never fires a
	# stale callback.
	for c: Dictionary in struck.get_connections():
		struck.disconnect(c["callable"])
	for c2: Dictionary in finished.get_connections():
		finished.disconnect(c2["callable"])
	if _pool.size() < MAX_LIVE:
		_pool.append(self)


func _exit_tree() -> void:
	_pool.erase(self)
