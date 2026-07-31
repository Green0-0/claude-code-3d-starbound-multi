class_name Projectile
extends Node3D

## A shot in flight.
##
## Traversal is a short raycast per frame against the voxel field rather than a
## physics body, which keeps a 60 m/s bullet from tunnelling and lets one flag —
## `through_terrain` — turn the whole test off. That flag is what makes the
## Phase Lance work: it asks the cutaway what is real instead of asking the
## terrain.

var world: VoxelWorld
var game: Node
var kind: StringName = &"bullet"
var damage := 10.0
## Sedative carried by the round, delivered separately from the damage.
var torpor := 0.0
var element: StringName = Blocks.ELEM_PHYSICAL
var source: Node = null
var hostile := false           ## true when fired by a monster at the player

var velocity := Vector3.ZERO
var _life := 2.0
var _def := {}
var _pierced := 0
var _hit: Array[int] = []
var _origin := Vector3.ZERO
var _mesh: MeshInstance3D
var _light: OmniLight3D


static func fire(parent: Node, w: VoxelWorld, g: Node, kind_id: StringName,
		from: Vector3, dir: Vector3, dmg: float, elem: StringName,
		src: Node, is_hostile := false, tor := 0.0) -> Projectile:
	var p := Projectile.new()
	p.world = w
	p.game = g
	p.kind = kind_id
	p.damage = dmg
	p.torpor = tor
	p.element = elem
	p.source = src
	p.hostile = is_hostile
	p._def = Combat.projectile_def(kind_id)
	p.velocity = dir.normalized() * float(p._def.get("speed", 30.0))
	p._life = float(p._def.get("life", 2.0))
	parent.add_child(p)
	p.global_position = from
	p._origin = from
	return p


func _ready() -> void:
	add_to_group(&"projectiles")
	var size := float(_def.get("size", 0.2))
	var col: Color = _def.get("color", Color(1, 1, 1))

	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	_mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	mat.disable_receive_shadows = true
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	var light_energy := float(_def.get("light", 0.0))
	if light_energy > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = col
		_light.light_energy = light_energy
		_light.omni_range = 5.0
		add_child(_light)


func _physics_process(delta: float) -> void:
	if world == null:
		queue_free()
		return
	_life -= delta
	if _life <= 0.0:
		_expire()
		return

	var g := float(_def.get("gravity", 0.0))
	velocity.y -= g * delta

	# star bolts steer toward whatever they were fired at
	var homing := float(_def.get("homing", 0.0))
	if homing > 0.0:
		var t := _homing_target()
		if t != null:
			var want: Vector3 = (t.global_position + Vector3(0, 0.8, 0) - global_position)
			velocity = velocity.lerp(want.normalized() * velocity.length(),
				clampf(homing * delta, 0.0, 1.0))

	# a boomerang turns around halfway through its life
	if bool(_def.get("returns", false)) and _life < float(_def.get("life", 2.0)) * 0.45:
		var back := _origin - global_position
		if source is Node3D:
			back = (source as Node3D).global_position + Vector3(0, 0.9, 0) - global_position
		velocity = velocity.lerp(back.normalized() * velocity.length(), 3.0 * delta)

	var step := velocity * delta
	var dist := step.length()
	if dist <= 0.0:
		return

	# --- terrain
	if not bool(_def.get("through_terrain", false)):
		var hit := world.raycast(global_position, step / dist, dist, true)
		if hit.get("hit", false):
			global_position = hit["point"]
			_impact(null)
			return

	global_position += step
	_mesh.rotate_y(delta * 9.0)
	_check_bodies()


func _homing_target() -> Node3D:
	var best: Node3D = null
	var best_d := 30.0
	var group := &"player" if hostile else &"monsters"
	for n in get_tree().get_nodes_in_group(group):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d := n3.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n3
	return best


func _check_bodies() -> void:
	var radius := float(_def.get("size", 0.2)) + 0.5
	if hostile:
		var players := get_tree().get_nodes_in_group(&"player")
		for n in players:
			var p := n as Player
			if p == null or not p.is_alive():
				continue
			if (p.global_position + Vector3(0, 0.9, 0)).distance_to(global_position) < radius + 0.3:
				p.hurt(damage, element)
				_apply_element_to_player(p)
				_impact(p)
				return
		return
	for n in get_tree().get_nodes_in_group(&"monsters"):
		var m := n as Monster
		if m == null:
			continue
		var id := int(m.get_instance_id())
		if _hit.has(id):
			continue
		if m.global_position.distance_to(global_position) > radius + m.species.size.y * 0.5:
			continue
		_hit.append(id)
		m.hurt(damage, element, velocity.normalized() * 4.0, source)
		if torpor > 0.0:
			m.apply_torpor(torpor)
		if game != null:
			game.on_element_applied(m, element)
		_pierced += 1
		if _pierced > int(_def.get("pierce", 0)):
			_impact(m)
			return


func _apply_element_to_player(p: Player) -> void:
	var eff: Variant = Combat.ELEMENT_EFFECTS.get(element)
	if eff != null and p.stats != null:
		p.stats.apply_effect(StringName(eff[0]), float(eff[1]))


func _impact(_what: Node) -> void:
	var blast := float(_def.get("blast", 0.0))
	if blast > 0.0 and game != null:
		var depth := float(_def.get("depth_blast", 0.0))
		if depth > 0.0:
			game.depth_blast(global_position, blast, depth, damage, element, source)
		else:
			game.explode(global_position, blast, damage, element, source)
	elif game != null:
		game.spawn_impact(global_position, _def.get("color", Color(1, 1, 1)))
	queue_free()


func _expire() -> void:
	if bool(_def.get("fuse", false)):
		_impact(null)
		return
	queue_free()
