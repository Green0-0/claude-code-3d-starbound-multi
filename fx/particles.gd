## Pooled GPU particle factory. Every material, gradient and sprite is built in
## code — the project contains no image files.
##
## A fixed pool of `GPUParticles3D` emitters is recycled by expiry time. Process
## materials are shared per effect id (they only describe motion); the *look* is
## a per-emitter `StandardMaterial3D` set as `material_override`, which is what
## lets `block_break` be tinted with the colour of the block that just died
## without duplicating the whole effect.
##
## Emissions outside the visible slab are dropped before anything is allocated:
## a particle twenty layers behind the play plane is invisible by construction.
class_name FxParticles
extends Node3D

const POOL := 26
const MAX_DIST := 64.0

## Generated sprite atlas keys.
const TEX_DOT := &"dot"
const TEX_SPARK := &"spark"
const TEX_CHIP := &"chip"
const TEX_SMOKE := &"smoke"
const TEX_STAR := &"star"

## The effect vocabulary. Anything not listed falls back to `dust`.
##   tex/size    sprite and quad size
##   amount/life particle count and lifetime
##   vel/spread  initial speed range and cone angle around `dir`
##   grav        constant acceleration
##   c0/c1       colour ramp start -> end (alpha included)
##   tint        true = `emit()`'s tint colour multiplies the sprite
const EFFECTS := {
	&"block_break": {
		"tex": TEX_CHIP, "size": Vector2(0.16, 0.16), "amount": 14, "life": 0.85,
		"vel": Vector2(1.6, 4.2), "spread": 75.0, "dir": Vector3.UP,
		"grav": Vector3(0, -14.0, 0), "damp": 1.2, "scale": Vector2(0.6, 1.3),
		"angular": 420.0, "c0": Color(1, 1, 1, 1), "c1": Color(1, 1, 1, 0),
		"tint": true, "emit_shape": "box", "extents": Vector3(0.45, 0.45, 0.45),
	},
	&"dust": {
		"tex": TEX_SMOKE, "size": Vector2(0.5, 0.5), "amount": 8, "life": 1.1,
		"vel": Vector2(0.3, 1.2), "spread": 60.0, "dir": Vector3.UP,
		"grav": Vector3(0, -1.2, 0), "damp": 1.6, "scale": Vector2(0.6, 1.6),
		"c0": Color(0.72, 0.66, 0.55, 0.55), "c1": Color(0.72, 0.66, 0.55, 0.0),
		"tint": true, "emit_shape": "sphere", "radius": 0.35,
	},
	&"sparks": {
		"tex": TEX_SPARK, "size": Vector2(0.05, 0.32), "amount": 16, "life": 0.55,
		"vel": Vector2(4.0, 11.0), "spread": 180.0, "dir": Vector3.UP,
		"grav": Vector3(0, -22.0, 0), "damp": 0.6, "scale": Vector2(0.5, 1.1),
		"c0": Color(1.0, 0.92, 0.55, 1.0), "c1": Color(1.0, 0.35, 0.05, 0.0),
		"blend": "add", "align": true,
	},
	&"blood": {
		"tex": TEX_DOT, "size": Vector2(0.14, 0.14), "amount": 12, "life": 0.7,
		"vel": Vector2(2.0, 6.0), "spread": 120.0, "dir": Vector3.UP,
		"grav": Vector3(0, -26.0, 0), "damp": 0.4, "scale": Vector2(0.6, 1.4),
		"c0": Color(0.65, 0.06, 0.08, 1.0), "c1": Color(0.32, 0.02, 0.03, 0.0),
		"tint": true,
	},
	&"smoke": {
		"tex": TEX_SMOKE, "size": Vector2(0.8, 0.8), "amount": 10, "life": 2.2,
		"vel": Vector2(0.4, 1.4), "spread": 30.0, "dir": Vector3.UP,
		"grav": Vector3(0, 0.9, 0), "damp": 0.9, "scale": Vector2(0.8, 2.8),
		"angular": 40.0, "c0": Color(0.24, 0.23, 0.22, 0.6),
		"c1": Color(0.4, 0.4, 0.4, 0.0), "emit_shape": "sphere", "radius": 0.3,
	},
	&"steam": {
		"tex": TEX_SMOKE, "size": Vector2(0.6, 0.6), "amount": 12, "life": 1.6,
		"vel": Vector2(1.0, 2.6), "spread": 22.0, "dir": Vector3.UP,
		"grav": Vector3(0, 1.8, 0), "damp": 1.1, "scale": Vector2(0.5, 2.4),
		"c0": Color(0.92, 0.95, 1.0, 0.5), "c1": Color(1, 1, 1, 0.0),
	},
	&"fire": {
		"tex": TEX_SMOKE, "size": Vector2(0.45, 0.45), "amount": 14, "life": 0.75,
		"vel": Vector2(0.8, 2.4), "spread": 18.0, "dir": Vector3.UP,
		"grav": Vector3(0, 3.5, 0), "damp": 1.0, "scale": Vector2(0.7, 1.6),
		"c0": Color(1.0, 0.85, 0.3, 1.0), "c1": Color(0.9, 0.15, 0.02, 0.0),
		"blend": "add",
	},
	&"explosion": {
		"tex": TEX_SMOKE, "size": Vector2(1.1, 1.1), "amount": 34, "life": 1.5,
		"vel": Vector2(5.0, 16.0), "spread": 180.0, "dir": Vector3.UP,
		"grav": Vector3(0, -4.0, 0), "damp": 2.4, "scale": Vector2(0.9, 3.2),
		"angular": 160.0, "c0": Color(1.0, 0.9, 0.5, 1.0),
		"c1": Color(0.18, 0.16, 0.15, 0.0), "blend": "add",
		"emit_shape": "sphere", "radius": 0.6, "explosive": 1.0,
	},
	&"ice_shards": {
		"tex": TEX_CHIP, "size": Vector2(0.13, 0.13), "amount": 14, "life": 0.9,
		"vel": Vector2(2.5, 7.0), "spread": 150.0, "dir": Vector3.UP,
		"grav": Vector3(0, -18.0, 0), "damp": 0.5, "scale": Vector2(0.5, 1.2),
		"angular": 500.0, "c0": Color(0.75, 0.93, 1.0, 1.0),
		"c1": Color(0.55, 0.8, 1.0, 0.0), "blend": "add",
	},
	&"electricity": {
		"tex": TEX_SPARK, "size": Vector2(0.06, 0.4), "amount": 18, "life": 0.35,
		"vel": Vector2(3.0, 9.0), "spread": 180.0, "dir": Vector3.UP,
		"grav": Vector3.ZERO, "damp": 5.0, "scale": Vector2(0.6, 1.4),
		"c0": Color(0.7, 0.9, 1.0, 1.0), "c1": Color(0.3, 0.5, 1.0, 0.0),
		"blend": "add", "align": true, "explosive": 1.0,
	},
	&"heal": {
		"tex": TEX_STAR, "size": Vector2(0.26, 0.26), "amount": 12, "life": 1.3,
		"vel": Vector2(0.8, 2.0), "spread": 25.0, "dir": Vector3.UP,
		"grav": Vector3(0, 1.6, 0), "damp": 0.8, "scale": Vector2(0.5, 1.2),
		"angular": 90.0, "c0": Color(0.5, 1.0, 0.6, 1.0),
		"c1": Color(0.9, 1.0, 0.75, 0.0), "blend": "add",
		"emit_shape": "sphere", "radius": 0.5,
	},
	&"teleport": {
		"tex": TEX_STAR, "size": Vector2(0.3, 0.3), "amount": 26, "life": 1.0,
		"vel": Vector2(1.0, 3.0), "spread": 180.0, "dir": Vector3.UP,
		"grav": Vector3(0, 2.6, 0), "damp": 1.4, "scale": Vector2(0.4, 1.5),
		"angular": 260.0, "c0": Color(0.75, 0.55, 1.0, 1.0),
		"c1": Color(0.35, 0.85, 1.0, 0.0), "blend": "add",
		"emit_shape": "ring", "radius": 0.55, "height": 1.9, "explosive": 0.85,
	},
	&"levelup": {
		"tex": TEX_STAR, "size": Vector2(0.34, 0.34), "amount": 30, "life": 1.5,
		"vel": Vector2(2.5, 6.5), "spread": 12.0, "dir": Vector3.UP,
		"grav": Vector3(0, -2.2, 0), "damp": 1.0, "scale": Vector2(0.5, 1.6),
		"angular": 200.0, "c0": Color(1.0, 0.92, 0.45, 1.0),
		"c1": Color(1.0, 0.65, 0.2, 0.0), "blend": "add",
		"emit_shape": "ring", "radius": 0.7, "height": 0.4, "explosive": 1.0,
	},
	&"splash": {
		"tex": TEX_DOT, "size": Vector2(0.12, 0.12), "amount": 20, "life": 0.8,
		"vel": Vector2(2.0, 6.5), "spread": 55.0, "dir": Vector3.UP,
		"grav": Vector3(0, -24.0, 0), "damp": 0.3, "scale": Vector2(0.5, 1.3),
		"c0": Color(0.6, 0.82, 1.0, 0.9), "c1": Color(0.45, 0.7, 1.0, 0.0),
		"tint": true, "emit_shape": "box", "extents": Vector3(0.4, 0.05, 0.4),
	},
	&"leaves": {
		"tex": TEX_CHIP, "size": Vector2(0.2, 0.2), "amount": 8, "life": 3.4,
		"vel": Vector2(0.3, 1.0), "spread": 90.0, "dir": Vector3.DOWN,
		"grav": Vector3(0, -1.1, 0), "damp": 0.6, "scale": Vector2(0.7, 1.2),
		"angular": 150.0, "c0": Color(0.42, 0.68, 0.28, 1.0),
		"c1": Color(0.38, 0.5, 0.22, 0.0), "tint": true,
		"emit_shape": "box", "extents": Vector3(0.5, 0.3, 0.5),
	},
	&"flip_wake": {
		"tex": TEX_SPARK, "size": Vector2(0.09, 1.5), "amount": 40, "life": 0.6,
		"vel": Vector2(1.5, 5.0), "spread": 8.0, "dir": Vector3.UP,
		"grav": Vector3(0, -1.0, 0), "damp": 1.4, "scale": Vector2(0.6, 1.8),
		"c0": Color(0.72, 0.86, 1.0, 0.85), "c1": Color(0.5, 0.7, 1.0, 0.0),
		"blend": "add", "align": true, "explosive": 0.9,
		"emit_shape": "ring", "radius": 3.2, "inner": 2.2, "height": 5.0,
	},
}

## Ids that mean the same thing as an entry above. Other modules invent effect
## names freely; every one of them lands on a real emitter through this table
## rather than falling through to generic dust.
const ALIASES := {
	# generic
	&"break": &"block_break", &"hit": &"blood", &"impact": &"dust",
	&"spark": &"sparks", &"magic": &"teleport", &"portal": &"teleport",
	&"water_splash": &"splash", &"leaf_fall": &"leaves", &"heal_motes": &"heal",
	&"level_up": &"levelup", &"zap": &"electricity", &"flame": &"fire",
	&"lava_pop": &"fire", &"muzzle": &"sparks", &"debris": &"block_break",
	# mining / building
	&"block_dust": &"dust", &"block_spark": &"sparks", &"dig": &"block_break",
	&"mining": &"block_break", &"mine_chip": &"block_break",
	&"mine_burst": &"block_break", &"dirt_puff": &"dust",
	&"drill_sparks": &"sparks", &"paint_puff": &"dust",
	&"eat_crumb": &"block_break", &"grow": &"heal", &"leaf": &"leaves",
	&"snow_settle": &"dust", &"quake": &"dust",
	# liquids and gas
	&"bubble": &"splash", &"acid_bubble": &"splash",
	&"splash_water": &"splash", &"rain_splash": &"splash",
	&"water_drip": &"splash", &"liquid_drain": &"splash",
	&"liquid_seep": &"splash", &"evaporate": &"steam", &"fizzle": &"steam",
	&"gas_pop": &"smoke", &"miasma": &"smoke", &"unravel": &"smoke",
	# combat
	&"hit_spark": &"sparks", &"splat": &"blood", &"tracer": &"sparks",
	&"death_burst": &"smoke", &"monster_death": &"smoke",
	&"shockwave": &"explosion", &"boss_phase": &"explosion",
	&"eruption": &"explosion", &"meteor": &"fire", &"firewave": &"fire",
	&"engine_burn": &"fire", &"tech_rocket_exhaust": &"fire",
	&"shock": &"electricity", &"lightning": &"electricity",
	&"summon": &"teleport", &"capture": &"teleport",
	&"capture_release": &"teleport", &"capture_success": &"teleport",
	&"beacon_flare": &"sparks", &"heal_mote": &"heal",
	# perspective and tech — anything that bends the plane gets the flip wake
	&"flip_slip": &"flip_wake", &"plane_rip": &"flip_wake",
	&"warp_streaks": &"flip_wake", &"tech_fold": &"flip_wake",
	&"tech_fold_pull": &"flip_wake", &"tech_fold_seam": &"flip_wake",
	&"tech_perspective_dash": &"flip_wake",
	&"tech_perspective_flip": &"flip_wake",
	&"layer_shift": &"dust", &"phase": &"teleport", &"blink": &"teleport",
	&"tech_blink_in": &"teleport", &"tech_blink_out": &"teleport",
	&"tech_phase": &"teleport", &"tech_phase_trail": &"smoke",
	&"tech_depth_sight": &"teleport", &"tech_distortion": &"teleport",
	&"teleport_beam": &"teleport", &"warp_bloom": &"teleport",
	&"tech_anchor": &"electricity", &"tech_anchor_spark": &"sparks",
	&"tech_ore_ping": &"sparks", &"tech_spike_hit": &"sparks",
	&"tech_cling_dust": &"dust", &"tech_sprint_dust": &"dust",
	&"double_jump": &"dust", &"wall_kick": &"dust",
}

var _pool: Array[GPUParticles3D] = []
var _mats: Array[StandardMaterial3D] = []
var _expiry: PackedFloat64Array = PackedFloat64Array()
var _proc: Dictionary = {}          ## effect id -> ParticleProcessMaterial
var _tex: Dictionary = {}           ## texture key -> ImageTexture
var _meshes: Dictionary = {}        ## "wxh" -> QuadMesh
var _next := 0


func _ready() -> void:
	_expiry.resize(POOL)
	for i in POOL:
		var p := GPUParticles3D.new()
		p.name = "Emitter%d" % i
		p.emitting = false
		p.one_shot = true
		# Born with no process material and no draw pass. Godot still tries to
		# draw an emitter in that state and the uniform set comes back null, so
		# stay hidden until `emit()` has configured us.
		p.visible = false
		p.local_coords = false
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		p.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
		p.layers = Const.RL_EFFECTS
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.disable_receive_shadows = true
		p.material_override = m
		# Give every emitter a complete, valid pipeline from the moment it
		# enters the tree. `emit()` only ever swaps these for the effect's own
		# versions; it must never be possible to draw a half-configured emitter.
		p.process_material = _default_process()
		p.draw_pass_1 = _quad(Vector2(0.2, 0.2))
		add_child(p)
		_pool.append(p)
		_mats.append(m)
		_expiry[i] = 0.0


func _process(_delta: float) -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	for i in _pool.size():
		if _expiry[i] > 0.0 and now >= _expiry[i]:
			_expiry[i] = 0.0
			_pool[i].emitting = false
			_pool[i].visible = false


# ==================================================================== emitting
## Every effect id this factory understands, aliases included.
func effect_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in EFFECTS:
		out.append(k)
	return out


func canonical(effect_id: StringName) -> StringName:
	if EFFECTS.has(effect_id):
		return effect_id
	return ALIASES.get(effect_id, &"dust")


## Fire one burst. `amount < 0` uses the effect's default count; `tint` with
## alpha > 0 recolours tintable effects (block debris, splashes, leaves).
func emit(effect_id: StringName, pos: Vector3, amount: int = -1,
		tint: Color = Color(0, 0, 0, 0)) -> GPUParticles3D:
	var key := canonical(effect_id)
	if _culled(pos):
		return null
	var spec: Dictionary = EFFECTS[key]
	var e := _take()
	if e == null:
		return null
	var idx := _pool.find(e)
	var life: float = float(spec.get("life", 1.0))
	var count: int = amount if amount > 0 else int(spec.get("amount", 10))
	count = clampi(count, 1, 96)

	var mat := _mats[idx]
	mat.albedo_texture = _texture(StringName(spec.get("tex", TEX_DOT)))
	var additive: bool = String(spec.get("blend", "mix")) == "add"
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	if bool(spec.get("tint", false)) and tint.a > 0.0:
		mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	else:
		mat.albedo_color = Color.WHITE

	e.process_material = _process_material(key)
	e.draw_pass_1 = _quad(spec.get("size", Vector2(0.2, 0.2)))
	# `amount` reallocates the GPU buffer, so quantise it: mining a wall must
	# not thrash the particle allocator twice a second.
	var bucket := clampi(int(ceilf(float(count) / 8.0)) * 8, 8, 96)
	if e.amount != bucket:
		e.amount = bucket
	e.lifetime = maxf(0.05, life)
	e.explosiveness = float(spec.get("explosive", 0.75))
	e.randomness = 0.4
	e.speed_scale = 1.0
	e.global_position = pos
	var reach: float = 2.0 + life * float(spec.get("vel", Vector2(1, 3)).y)
	e.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * (reach * 2.0))
	e.visible = true
	e.restart()
	e.emitting = true
	_expiry[idx] = float(Time.get_ticks_msec()) * 0.001 + life * 1.6 + 0.25
	return e


## Convenience: block debris coloured by the block type that was destroyed.
func emit_block_break(pos: Vector3, block_id: int, amount: int = 12) -> void:
	var c := Color(0.6, 0.6, 0.6)
	var bt: BlockType = Blocks.get_type(block_id)
	if bt != null:
		c = bt.color
	emit(&"block_break", pos, amount, c)


## True when a burst here would be invisible: outside the drawn slab, or too
## far from the player to be worth an emitter.
func _culled(pos: Vector3) -> bool:
	var off := (View.depth_of(pos) - float(View.layer)) * float(View.depth_sign())
	if off > float(Const.SLAB_BEHIND) + 2.0 or off < -3.0:
		return true
	var game := get_node_or_null(^"/root/Game")
	if game == null:
		return false
	var pl = game.get("player")
	if pl is Node3D:
		return pos.distance_squared_to((pl as Node3D).global_position) > MAX_DIST * MAX_DIST
	return false


## Hide any live emitter that has ended up outside the visible slab — behind
## the back of the drawn layers, or in front of the play plane where the slab
## shader has dissolved the world away. Called a few times a second by `FxRoot`.
func cull_outside_slab() -> void:
	var sign_d := float(View.depth_sign())
	var layer := float(View.layer)
	for i in _pool.size():
		if _expiry[i] <= 0.0:
			continue
		var e := _pool[i]
		var off := (View.depth_of(e.global_position) - layer) * sign_d
		e.visible = off <= float(Const.SLAB_BEHIND) + 2.0 and off >= -3.0


## Shared generated sprite, so weather and decals do not build their own.
## Keys: `dot`, `spark`, `chip`, `smoke`, `star`.
func sprite(key: StringName) -> ImageTexture:
	return _texture(key)


func _take() -> GPUParticles3D:
	var now := float(Time.get_ticks_msec()) * 0.001
	for i in _pool.size():
		var j := (_next + i) % _pool.size()
		if _expiry[j] <= 0.0 or now >= _expiry[j]:
			_next = (j + 1) % _pool.size()
			return _pool[j]
	# All busy: steal the one that will expire first.
	var best := 0
	var best_t := INF
	for i in _pool.size():
		if _expiry[i] < best_t:
			best_t = _expiry[i]
			best = i
	_next = (best + 1) % _pool.size()
	return _pool[best]


# ================================================================== materials
## A minimal always-valid process material, used as the pool's resting state.
static var _default_proc: ParticleProcessMaterial = null


func _default_process() -> ParticleProcessMaterial:
	if _default_proc == null:
		_default_proc = ParticleProcessMaterial.new()
		_default_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		_default_proc.direction = Vector3(0, 1, 0)
		_default_proc.spread = 25.0
		_default_proc.initial_velocity_min = 0.5
		_default_proc.initial_velocity_max = 1.5
		_default_proc.gravity = Vector3(0, -2.0, 0)
		_default_proc.scale_min = 0.5
		_default_proc.scale_max = 1.0
	return _default_proc


func _process_material(key: StringName) -> ParticleProcessMaterial:
	if _proc.has(key):
		return _proc[key]
	var spec: Dictionary = EFFECTS[key]
	var m := ParticleProcessMaterial.new()
	var vel: Vector2 = spec.get("vel", Vector2(1.0, 3.0))
	m.direction = spec.get("dir", Vector3.UP)
	m.spread = float(spec.get("spread", 45.0))
	m.initial_velocity_min = vel.x
	m.initial_velocity_max = vel.y
	m.gravity = spec.get("grav", Vector3(0, -9.0, 0))
	m.damping_min = 0.0
	m.damping_max = float(spec.get("damp", 0.0))
	var sc: Vector2 = spec.get("scale", Vector2(0.8, 1.2))
	m.scale_min = sc.x
	m.scale_max = sc.y
	var ang: float = float(spec.get("angular", 0.0))
	if ang > 0.0:
		m.angular_velocity_min = -ang
		m.angular_velocity_max = ang
		m.angle_min = -180.0
		m.angle_max = 180.0
	m.particle_flag_align_y = bool(spec.get("align", false))
	m.lifetime_randomness = 0.35
	m.color = Color.WHITE
	m.color_ramp = _ramp(spec.get("c0", Color.WHITE), spec.get("c1", Color(1, 1, 1, 0)))

	match String(spec.get("emit_shape", "point")):
		"sphere":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = float(spec.get("radius", 0.3))
		"box":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			m.emission_box_extents = spec.get("extents", Vector3(0.4, 0.4, 0.4))
		"ring":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			m.emission_ring_axis = Vector3.UP
			m.emission_ring_radius = float(spec.get("radius", 1.0))
			m.emission_ring_inner_radius = float(spec.get("inner", 0.0))
			m.emission_ring_height = float(spec.get("height", 0.5))
		_:
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	_proc[key] = m
	return m


func _ramp(c0: Color, c1: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	g.add_point(0.65, Color(lerpf(c0.r, c1.r, 0.65), lerpf(c0.g, c1.g, 0.65),
			lerpf(c0.b, c1.b, 0.65), lerpf(c0.a, c1.a, 0.35)))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


func _quad(size: Vector2) -> QuadMesh:
	var key := "%.2fx%.2f" % [size.x, size.y]
	if _meshes.has(key):
		return _meshes[key]
	var q := QuadMesh.new()
	q.size = size
	_meshes[key] = q
	return q


# =================================================================== textures
## All sprites are generated once, 32x32 or smaller, and shared.
func _texture(key: StringName) -> ImageTexture:
	if _tex.has(key):
		return _tex[key]
	var img: Image
	match String(key):
		"spark": img = _img_spark()
		"chip": img = _img_chip()
		"smoke": img = _img_smoke()
		"star": img = _img_star()
		_: img = _img_dot()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


func _new_image(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


func _img_dot() -> Image:
	var n := 32
	var img := _new_image(n, n)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(float(x) - c, float(y) - c).length() / (c + 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return img


func _img_smoke() -> Image:
	var n := 32
	var img := _new_image(n, n)
	var c := float(n - 1) * 0.5
	var rng := FxSynth.seeded(&"fx_smoke", 0)
	var lumps := []
	for i in 5:
		lumps.append(Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35),
				rng.randf_range(0.4, 0.75)))
	for y in n:
		for x in n:
			var p := Vector2((float(x) - c) / c, (float(y) - c) / c)
			var a := 0.0
			for l: Vector3 in lumps:
				var d := (p - Vector2(l.x, l.y)).length() / l.z
				a = maxf(a, clampf(1.0 - d, 0.0, 1.0))
			a *= clampf(1.3 - p.length(), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.95))
	return img


func _img_spark() -> Image:
	var w := 8
	var h := 32
	var img := _new_image(w, h)
	for y in h:
		var v := float(y) / float(h - 1)
		var along := sin(PI * v)
		for x in w:
			var u := absf(float(x) - float(w - 1) * 0.5) / (float(w) * 0.5)
			var a := clampf(1.0 - u, 0.0, 1.0) * along
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return img


func _img_chip() -> Image:
	var n := 8
	var img := _new_image(n, n)
	var rng := FxSynth.seeded(&"fx_chip", 0)
	for y in n:
		for x in n:
			var edge := (x == 0 or y == 0 or x == n - 1 or y == n - 1)
			var a := 1.0 if not edge else (1.0 if rng.randf() < 0.55 else 0.0)
			var shade := 1.0 - rng.randf() * 0.28
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return img


func _img_star() -> Image:
	var n := 32
	var img := _new_image(n, n)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var spike := 0.45 + 0.55 * pow(absf(cos(ang * 2.0)), 3.0)
			var a := clampf(1.0 - r / maxf(0.08, spike), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return img
