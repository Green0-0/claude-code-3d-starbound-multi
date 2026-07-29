## A block in mid-air: sand that lost its support, gravel knocked out of a
## ceiling, an ash drift collapsing into a shaft.
##
## Spawned by [LiqFalling] when the fall is close enough to the camera to be
## worth animating. It is a real [VoxelEntity], so it collides with the voxel
## grid, swims in liquid and rides through layer shifts like everything else;
## when it settles it writes itself back into the world as a block (or drops as
## an item if something is standing where it wanted to land).
class_name LiqFallingBlock
extends VoxelEntity

## Damage dealt to an entity the block lands on / passes through, scaled by
## impact speed.
const CRUSH_DAMAGE := 5.0
const CRUSH_SPEED := 6.0
## Failsafe: never live longer than this, even if physics goes strange.
const MAX_LIFETIME := 20.0

var block_id: int = Const.AIR
var block_name: StringName = &""
var _life := 0.0
var _landed := false
var _mesh: MeshInstance3D = null

static var _materials: Dictionary = {}


func _init() -> void:
	box_size = Vector3(0.96, 0.96, 0.96)
	max_health = 1.0
	gravity_scale = 1.0
	move_speed = 0.0
	jump_speed = 0.0
	invulnerable = true
	affected_by_liquid = true
	faction = &"neutral"


## Must be called before the node enters the tree.
func setup(p_block_id: int) -> void:
	block_id = p_block_id
	block_name = Blocks.get_type(p_block_id).name


func _ready() -> void:
	super()
	add_to_group(&"falling_blocks")
	_build_visual()


func _build_visual() -> void:
	var bt := Blocks.get_type(block_id)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.98, 0.98, 0.98)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.position = Vector3(0.0, 0.49, 0.0)   ## entity origin is the feet
	_mesh.layers = Const.RL_ENTITIES
	_mesh.material_override = _material_for(bt)
	add_child(_mesh)


static func _material_for(bt: BlockType) -> Material:
	if _materials.has(bt.id):
		return _materials[bt.id]
	var m := StandardMaterial3D.new()
	m.albedo_color = bt.color
	m.roughness = 1.0
	m.metallic = 0.0
	if bt.emission > 0.0:
		m.emission_enabled = true
		m.emission = bt.color
		m.emission_energy_multiplier = bt.emission
	_materials[bt.id] = m
	return m


func _physics_process(delta: float) -> void:
	if _landed:
		return
	_life += delta
	# Keep drifting straight down: falling blocks have no lateral momentum, and
	# letting them keep any would smear them across the plane.
	velocity.x = 0.0
	velocity.z = 0.0
	integrate(delta)
	_crush_entities(delta)
	if on_floor or _life > MAX_LIFETIME:
		_land()


## Anything sharing this voxel while the block is moving fast gets hurt.
func _crush_entities(_delta: float) -> void:
	if velocity.y > -CRUSH_SPEED:
		return
	var speed := absf(velocity.y)
	for e: VoxelEntity in Game.entities_in_radius(aabb_center(), 1.1):
		if e == self or e.dead or e is LiqFallingBlock:
			continue
		e.apply_damage(CRUSH_DAMAGE * (speed / CRUSH_SPEED), Const.ELEM_PHYSICAL, self)
		e.knockback(Vector3.DOWN, speed * 0.15)


func _land() -> void:
	if _landed:
		return
	_landed = true
	var target := Vector3i(floori(global_position.x), floori(global_position.y + 0.1), floori(global_position.z))
	target = World.normalize(target)
	Liquids.falling.settle(target, block_id, self)
	queue_free()
