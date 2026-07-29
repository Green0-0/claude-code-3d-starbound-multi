## The procedural paper doll.
##
## The player is a *sheet of paper standing in a voxel world*: a rig of flat
## [QuadMesh] limbs, each wearing a runtime-generated [ImageTexture], all
## billboarded toward the camera on the Y axis only. There are no binary
## assets — every pixel below is drawn in code.
##
## Rig (built by [method _build_rig], all children of this node):
## [codeblock]
##   PlayerVisual        billboard yaw, paper-turn scale, global fade
##     Root              facing mirror, bob / squash / death spin
##       Cape  Pack      behind the body
##       ArmBack LegBack LegFront Torso ArmFront Head
##       ArmFront/Hand/Item
##       <part>/Armor_*  overlay quads driven by the equipped slots
## [/codeblock]
##
## Depth ordering uses millimetre Z offsets in rig space. Because the rig
## always faces the camera, "further along +Z" is always "closer to the
## viewer", so the painter's order is stable in every one of the four views.
class_name PlayerVisual
extends Node3D

## Vertex-curl + hurt-flash + fade shader, shared by every limb.
const SHADER_SRC := """
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float curl = 0.0;
uniform float flash = 0.0;
uniform float fade = 1.0;
uniform float lightness = 1.0;

void vertex() {
	float u = UV.x - 0.5;
	// The sheet bows out of plane as it turns edge-on: a real paper curl.
	VERTEX.z += curl * (0.25 - u * u) * 1.5;
	VERTEX.x *= 1.0 - abs(curl) * 0.10;
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.35) discard;
	ALBEDO = mix(c.rgb * tint.rgb * lightness, vec3(1.0), clamp(flash, 0.0, 1.0));
	ALPHA = c.a * tint.a * fade;
}
"""

# ------------------------------------------------------------------- palette
const SKIN := Color(0.93, 0.75, 0.58)
const HAIR := Color(0.30, 0.19, 0.13)
const SHIRT := Color(0.25, 0.55, 0.78)
const SHIRT_DARK := Color(0.17, 0.38, 0.58)
const PANTS := Color(0.28, 0.30, 0.40)
const BOOT := Color(0.22, 0.16, 0.14)
const GLOVE := Color(0.80, 0.78, 0.72)
const CAPE := Color(0.72, 0.24, 0.28)
const PACK := Color(0.40, 0.36, 0.30)
const EYE := Color(0.10, 0.10, 0.14)
const OUTLINE := Color(0.08, 0.07, 0.10, 1.0)

## Reference top speed; only used to normalise animation rates.
const SPEED_REF := 10.2

## Resting local heights of the parts that bob.
const TORSO_Y := 0.62
const HEAD_Y := 1.20
const ARM_Y := 1.16
const CAPE_Y := 1.24

## The owning [PlayerActor]. Untyped on purpose: typing it would create a
## cyclic `class_name` dependency between this script and `player.gd`.
var player = null                                               # noqa: type

var _root: Node3D = null
var _hand: Node3D = null
var _parts: Dictionary = {}        ## StringName -> MeshInstance3D
var _mats: Dictionary = {}         ## StringName -> ShaderMaterial
var _armor: Dictionary = {}        ## armour slot -> MeshInstance3D
var _shader: Shader = null
var _tex_cache: Dictionary = {}

var _pose: StringName = &"idle"
var _phase := 0.0
var _face_sign := 1.0
var _fade := 1.0
var _curl := 0.0
var _flash := 0.0
var _lightness := 1.0

# --- one-shot animation timers (-1 == inactive) ------------------------------
var _flip_t := -1.0
var _flip_dir := 1
var _flip_face_from := 1.0
var _shift_t := -1.0
var _shift_dir := 1
var _land_t := 0.0
var _pop_t := 0.0
var _swing_t := -1.0
var _death_t := -1.0
var _spawn_t := 0.0
var _held_id: StringName = &""


func setup(p) -> void:                                          # noqa: type
	player = p
	_face_sign = float(p.facing)
	_build_rig()
	refresh_equipment()


# ================================================================ rig building
func _build_rig() -> void:
	_shader = Shader.new()
	_shader.code = SHADER_SRC

	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)

	# Drawn back-to-front; the Z offsets are what keep that order stable.
	_add_part(&"cape", "Cape", Vector2(0.62, 0.82), Vector3(0.0, CAPE_Y, -0.030), -1,
		_tex_cape(CAPE))
	_add_part(&"pack", "Pack", Vector2(0.34, 0.38), Vector3(0.0, 1.02, -0.022), 0,
		_tex_pack(PACK))
	_add_part(&"arm_back", "ArmBack", Vector2(0.155, 0.50), Vector3(-0.11, ARM_Y, -0.014), -1,
		_tex_limb(6, 18, SHIRT_DARK, GLOVE.darkened(0.25)))
	_add_part(&"leg_back", "LegBack", Vector2(0.19, 0.66), Vector3(-0.09, 0.66, -0.008), -1,
		_tex_limb(7, 22, PANTS.darkened(0.15), BOOT.darkened(0.15)))
	_add_part(&"leg_front", "LegFront", Vector2(0.19, 0.66), Vector3(0.09, 0.66, 0.008), -1,
		_tex_limb(7, 22, PANTS, BOOT))
	_add_part(&"torso", "Torso", Vector2(0.50, 0.62), Vector3(0.0, TORSO_Y, 0.0), 1,
		_tex_torso(SHIRT, SHIRT_DARK))
	_add_part(&"arm_front", "ArmFront", Vector2(0.155, 0.50), Vector3(0.12, ARM_Y, 0.016), -1,
		_tex_limb(6, 18, SHIRT, GLOVE))
	_add_part(&"head", "Head", Vector2(0.58, 0.54), Vector3(0.0, HEAD_Y, 0.010), 1,
		_tex_head(SKIN, HAIR, EYE))

	# The hand hangs off the end of the front arm so held items swing with it.
	_hand = Node3D.new()
	_hand.name = "Hand"
	_hand.position = Vector3(0.0, -0.46, 0.0)
	(_parts[&"arm_front"] as MeshInstance3D).add_child(_hand)
	var item := _make_quad(Vector2(0.34, 0.34), 0, _tex_item(Color(0.8, 0.8, 0.8), &"square"))
	item.name = "Item"
	item.position = Vector3(0.07, -0.02, 0.02)
	item.visible = false
	_hand.add_child(item)
	_parts[&"item"] = item
	_mats[&"item"] = item.material_override as ShaderMaterial

	# Armour overlays: same geometry, drawn a hair in front of the body part.
	_add_armor(ItemType.SLOT_HEAD, &"head", Vector2(0.60, 0.56), 1)
	_add_armor(ItemType.SLOT_CHEST, &"torso", Vector2(0.52, 0.64), 1)
	_add_armor(ItemType.SLOT_LEGS, &"leg_front", Vector2(0.21, 0.68), -1)
	_add_armor(ItemType.SLOT_BACK, &"cape", Vector2(0.64, 0.84), -1)


func _add_part(id: StringName, node_name: String, size: Vector2, pivot: Vector3,
		pivot_mode: int, tex: ImageTexture) -> void:
	var mi := _make_quad(size, pivot_mode, tex)
	mi.name = node_name
	mi.position = pivot
	_root.add_child(mi)
	_parts[id] = mi
	_mats[id] = mi.material_override as ShaderMaterial


func _add_armor(slot: StringName, parent_id: StringName, size: Vector2, pivot_mode: int) -> void:
	var parent := _parts.get(parent_id) as MeshInstance3D
	if parent == null:
		return
	var mi := _make_quad(size, pivot_mode, _tex_item(Color(0.7, 0.7, 0.75), &"square"))
	mi.name = "Armor_" + String(slot)
	mi.position = Vector3(0.0, 0.0, 0.004)
	mi.visible = false
	parent.add_child(mi)
	_armor[slot] = mi
	_mats[StringName("armor_" + String(slot))] = mi.material_override as ShaderMaterial


## `pivot_mode`: -1 origin at the top edge (limbs swing from shoulder / hip),
## 0 centred, +1 origin at the bottom edge (torso and head sit on their base).
func _make_quad(size: Vector2, pivot_mode: int, tex: ImageTexture) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.subdivide_width = 6
	mesh.subdivide_depth = 1
	if pivot_mode < 0:
		mesh.center_offset = Vector3(0.0, -size.y * 0.5, 0.0)
	elif pivot_mode > 0:
		mesh.center_offset = Vector3(0.0, size.y * 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("tint", Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = Const.RL_ENTITIES
	return mi


# ============================================================ frame animation
func _process(delta: float) -> void:
	if player == null or _root == null:
		return
	_tick_timers(delta)

	# Billboard: yaw only, locked to the camera's current (possibly mid-flip)
	# heading, so the sprite is always a perfectly upright sheet facing us.
	rotation.y = View.current_yaw()

	var flip_scale := 1.0
	var extra_yaw := 0.0
	var rig_y := 0.0
	var squash := Vector2.ONE
	_curl = 0.0
	_fade = 1.0

	# --- the signature paper turn ------------------------------------------
	if _flip_t >= 0.0:
		var t := clampf(_flip_t, 0.0, 1.0)
		flip_scale = maxf(0.05, absf(cos(t * PI)))
		_curl = sin(t * TAU) * 0.9
		extra_yaw = sin(t * PI) * 0.5 * float(_flip_dir)
		rig_y = sin(t * PI) * 0.09
		# The far side of the sheet appears exactly at the edge-on instant.
		_face_sign = _flip_face_from if t < 0.5 else float(player.facing)
	else:
		_face_sign = float(player.facing)

	# --- "step into the page" ----------------------------------------------
	if _shift_t >= 0.0:
		var shift_s := sin((1.0 - clampf(_shift_t, 0.0, 1.0)) * PI)
		squash.x *= 1.0 - 0.42 * shift_s
		squash.y *= 1.0 + 0.16 * shift_s
		_curl += 0.55 * shift_s * float(_shift_dir)
		_fade *= 1.0 - 0.30 * shift_s
		# Local +Z faces the camera, so a positive (deeper) shift pushes back.
		_root.position.z = -0.26 * shift_s * float(_shift_dir)
	else:
		_root.position.z = 0.0

	# --- landing squash / jump pop -----------------------------------------
	if _land_t > 0.0:
		var land_s := _land_t / 0.22
		squash.y *= 1.0 - 0.26 * land_s
		squash.x *= 1.0 + 0.20 * land_s
	if _pop_t > 0.0:
		var pop_s := _pop_t / 0.18
		squash.y *= 1.0 + 0.16 * pop_s
		squash.x *= 1.0 - 0.12 * pop_s

	# --- death spin ---------------------------------------------------------
	if _death_t >= 0.0:
		rig_y += sin(minf(_death_t, 1.0) * PI) * 0.45
		flip_scale *= maxf(0.15, absf(cos(_death_t * PI * 1.3)))
		_fade *= clampf(1.0 - (_death_t - 0.7) / 1.3, 0.12, 1.0)

	# --- respawn fade-in ----------------------------------------------------
	if _spawn_t > 0.0:
		_fade *= clampf(1.2 - _spawn_t / 0.9, 0.15, 1.0)

	# --- hurt flash ---------------------------------------------------------
	_flash = 0.0
	if _death_t < 0.0 and float(player.iframes) > 0.0:
		_flash = 1.0 if fmod(Time.get_ticks_msec() / 60.0, 2.0) < 1.0 else 0.0
		_fade *= 0.85

	rotation.y += extra_yaw
	scale = Vector3(flip_scale, 1.0, 1.0)
	_root.scale = Vector3(_face_sign * squash.x, squash.y, 1.0)
	_root.position.y = rig_y

	_animate_pose(delta)
	_animate_held(delta)
	_push_uniforms()


func _tick_timers(delta: float) -> void:
	_land_t = maxf(0.0, _land_t - delta)
	_pop_t = maxf(0.0, _pop_t - delta)
	_spawn_t = maxf(0.0, _spawn_t - delta)
	if _flip_t >= 0.0:
		_flip_t += delta / maxf(0.05, View.flip_duration)
		if _flip_t >= 1.0:
			_flip_t = -1.0
	if _shift_t >= 0.0:
		_shift_t -= delta / maxf(0.05, View.shift_duration)
		if _shift_t <= 0.0:
			_shift_t = -1.0
	if _swing_t >= 0.0:
		_swing_t += delta / 0.26
		if _swing_t >= 1.0:
			_swing_t = -1.0
	if _death_t >= 0.0:
		_death_t += delta


func _push_uniforms() -> void:
	for k: StringName in _mats:
		var m := _mats[k] as ShaderMaterial
		m.set_shader_parameter("curl", _curl)
		m.set_shader_parameter("flash", _flash)
		m.set_shader_parameter("fade", _fade)
		m.set_shader_parameter("lightness", _lightness)


# ------------------------------------------------------------------- posing
## Poses are named, not enumerated, so no other script has to import an enum
## from `player.gd` (which would create a cyclic class dependency).
func set_pose(p: StringName) -> void:
	if p == _pose:
		return
	var was := _pose
	_pose = p
	if p != &"run" or was != &"run":
		_phase = 0.0


func _animate_pose(delta: float) -> void:
	var speed01 := clampf(absf(float(player.plane_velocity())) / SPEED_REF, 0.0, 1.6)
	var arm_f := _parts[&"arm_front"] as MeshInstance3D
	var arm_b := _parts[&"arm_back"] as MeshInstance3D
	var leg_f := _parts[&"leg_front"] as MeshInstance3D
	var leg_b := _parts[&"leg_back"] as MeshInstance3D
	var torso := _parts[&"torso"] as MeshInstance3D
	var head := _parts[&"head"] as MeshInstance3D
	var cape := _parts[&"cape"] as MeshInstance3D

	var bob := 0.0
	var lean := 0.0
	var roll := 0.0

	match _pose:
		&"run":
			_phase += delta * (7.0 + speed01 * 5.0)
			var sr := sin(_phase)
			leg_f.rotation.z = -sr * 0.78
			leg_b.rotation.z = sr * 0.78
			arm_f.rotation.z = sr * 0.95
			arm_b.rotation.z = -sr * 0.95
			bob = absf(sin(_phase * 2.0)) * 0.045
			lean = -0.10 - 0.06 * speed01
		&"crouch":
			leg_f.rotation.z = -0.85
			leg_b.rotation.z = 0.85
			arm_f.rotation.z = 0.35
			arm_b.rotation.z = -0.25
			bob = -0.30
			lean = -0.16
		&"jump":
			leg_f.rotation.z = -0.42
			leg_b.rotation.z = 0.18
			arm_f.rotation.z = -2.10
			arm_b.rotation.z = -1.70
			lean = -0.06
		&"fall":
			_phase += delta * 6.0
			leg_f.rotation.z = -0.25 + sin(_phase) * 0.08
			leg_b.rotation.z = 0.34
			arm_f.rotation.z = 1.25
			arm_b.rotation.z = 1.05
			lean = 0.05
		&"wall_slide":
			leg_f.rotation.z = -0.20
			leg_b.rotation.z = 0.40
			arm_f.rotation.z = -1.35
			arm_b.rotation.z = 0.95
			lean = 0.10
		&"ledge":
			_phase += delta * 2.4
			var sl := sin(_phase) * 0.08
			leg_f.rotation.z = -0.18 + sl
			leg_b.rotation.z = 0.22 - sl
			arm_f.rotation.z = -2.55
			arm_b.rotation.z = -2.55
			lean = -0.04
		&"swim":
			_phase += delta * 5.5
			var ss := sin(_phase)
			arm_f.rotation.z = -1.20 + ss * 1.30
			arm_b.rotation.z = -1.20 - ss * 1.30
			leg_f.rotation.z = -1.15 + ss * 0.35
			leg_b.rotation.z = -1.15 - ss * 0.35
			lean = -0.35
			roll = -0.85                    # the body goes horizontal
			bob = sin(_phase * 0.5) * 0.05
		&"climb":
			_phase += delta * 5.0
			var sc := sin(_phase)
			arm_f.rotation.z = -2.30 + sc * 0.55
			arm_b.rotation.z = -2.30 - sc * 0.55
			leg_f.rotation.z = sc * 0.45
			leg_b.rotation.z = -sc * 0.45
			bob = sc * 0.04
		&"hurt":
			_phase += delta * 30.0
			roll = sin(_phase) * 0.16
			arm_f.rotation.z = 1.50
			arm_b.rotation.z = -1.50
			leg_f.rotation.z = -0.40
			leg_b.rotation.z = 0.40
			lean = 0.22
		&"dead":
			arm_f.rotation.z = 2.30
			arm_b.rotation.z = -2.30
			leg_f.rotation.z = -0.35
			leg_b.rotation.z = 0.35
		_:      # idle
			_phase += delta * 2.1
			var si := sin(_phase)
			arm_f.rotation.z = 0.10 + si * 0.10
			arm_b.rotation.z = -0.10 - si * 0.10
			leg_f.rotation.z = 0.0
			leg_b.rotation.z = 0.0
			bob = si * 0.018

	torso.rotation.z = lean * 0.6
	torso.position.y = TORSO_Y + bob
	head.position.y = HEAD_Y + bob * 1.4
	head.rotation.z = lean * 0.35
	arm_f.position.y = ARM_Y + bob
	arm_b.position.y = ARM_Y + bob

	if _death_t >= 0.0:
		_root.rotation.z = _death_t * TAU * 1.3
	else:
		_root.rotation.z = lerpf(_root.rotation.z, lean + roll, minf(1.0, delta * 14.0))

	# The cape trails: it lags behind the body and lifts with speed.
	var trail := clampf(absf(float(player.plane_velocity())) * 0.10, 0.0, 0.75)
	if not bool(player.on_floor):
		trail += 0.35
	cape.rotation.z = lerpf(cape.rotation.z, -trail, minf(1.0, delta * 9.0))
	cape.position.y = CAPE_Y + bob * 0.6


# --------------------------------------------------------- held item / armour
func _animate_held(delta: float) -> void:
	var item := _parts[&"item"] as MeshInstance3D
	var st: ItemStack = player.held_stack()
	var id: StringName = st.id if st != null and not st.is_empty() else &""
	if id != _held_id:
		_held_id = id
		item.visible = id != &""
		if item.visible:
			(_mats[&"item"] as ShaderMaterial).set_shader_parameter("tex", _item_texture(id))
	if not item.visible:
		return
	if _swing_t >= 0.0:
		var t := clampf(_swing_t, 0.0, 1.0)
		var swing := sin(t * PI)
		(_parts[&"arm_front"] as MeshInstance3D).rotation.z = -2.4 * swing + 0.6 * t
		item.rotation.z = -2.0 * swing
	else:
		item.rotation.z = lerpf(item.rotation.z, -0.35, minf(1.0, delta * 10.0))


## Re-read the equipped slots and rebuild the armour overlays. Cheap enough to
## call straight from `Events.inventory_changed`.
func refresh_equipment() -> void:
	if player == null or _armor.is_empty():
		return
	for slot: StringName in _armor.keys():
		var mi := _armor[slot] as MeshInstance3D
		var st: ItemStack = player.equipped_stack(slot)
		if st == null or st.is_empty() or st.type() == null:
			mi.visible = false
			continue
		mi.visible = true
		(mi.material_override as ShaderMaterial).set_shader_parameter(
			"tex", _armor_texture(slot, st.type().icon_color))
	# The cape takes the colour of whatever sits in the back slot.
	var back: ItemStack = player.equipped_stack(ItemType.SLOT_BACK)
	var cape_mat := _mats[&"cape"] as ShaderMaterial
	if back != null and not back.is_empty() and back.type() != null:
		cape_mat.set_shader_parameter("tint", back.type().icon_color)
	else:
		cape_mat.set_shader_parameter("tint", Color.WHITE)


## Multiplied into every limb's albedo; the lighting agent may drive this.
func set_lightness(v: float) -> void:
	_lightness = clampf(v, 0.05, 2.0)


# ============================================================== one-shot anims
## The paper turn. `dir` is the flip direction (-1 / +1).
func play_flip(dir: int) -> void:
	_flip_t = 0.0
	_flip_dir = -1 if dir < 0 else 1
	_flip_face_from = float(player.facing)


func end_flip() -> void:
	_flip_t = -1.0
	scale = Vector3.ONE
	_face_sign = float(player.facing)


## "Step into the page": a layer shift. `dir` +1 deeper, -1 shallower.
func play_shift(dir: int) -> void:
	_shift_t = 1.0
	_shift_dir = -1 if dir < 0 else 1


func play_jump() -> void:
	_pop_t = 0.18


## A mid-air paper pirouette, reusing the flip curve.
func play_double_jump() -> void:
	_pop_t = 0.18
	_flip_t = 0.0
	_flip_dir = int(player.facing)
	_flip_face_from = float(player.facing)


func play_land(distance: float) -> void:
	_land_t = clampf(0.10 + distance * 0.02, 0.10, 0.22)


func play_hurt() -> void:
	_phase = 0.0


func play_swing() -> void:
	_swing_t = 0.0


func play_ledge() -> void:
	_pop_t = 0.10


func play_death() -> void:
	_death_t = 0.0


func play_respawn() -> void:
	_death_t = -1.0
	_root.rotation.z = 0.0
	scale = Vector3.ONE
	_spawn_t = 0.9
	_flip_t = -1.0
	_shift_t = -1.0


# =============================================================== texture bakery
func _cached(key: String, maker: Callable) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var t: ImageTexture = maker.call()
	_tex_cache[key] = t
	return t


func _blank(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(0, y0), mini(img.get_height(), y1 + 1)):
		for x in range(maxi(0, x0), mini(img.get_width(), x1 + 1)):
			img.set_pixel(x, y, c)


## Knock the corners off so limbs read as rounded paper cut-outs.
func _round_corners(img: Image, r: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if mini(x, w - 1 - x) + mini(y, h - 1 - y) < r:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


## Cheap directional shading: the screen-left edge catches the light.
func _shade(img: Image) -> void:
	var w := img.get_width()
	for y in img.get_height():
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var t := float(x) / maxf(1.0, float(w - 1))
			var lit := c.lerp(c.darkened(0.30), t)
			img.set_pixel(x, y, lit.lerp(c.lightened(0.25), maxf(0.0, 0.32 - t)))


## One-pixel ink outline drawn *outside* the silhouette, paper-cutout style.
func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var edges: Array[Vector2i] = []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				continue
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x + o.x, y + o.y)
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
					continue
				if img.get_pixel(q.x, q.y).a > 0.5:
					edges.append(Vector2i(x, y))
					break
	for e: Vector2i in edges:
		img.set_pixel(e.x, e.y, OUTLINE)


func _finish(img: Image) -> ImageTexture:
	_shade(img)
	_outline(img)
	return ImageTexture.create_from_image(img)


func _tex_head(skin: Color, hair: Color, eye: Color) -> ImageTexture:
	return _cached("head", func() -> ImageTexture:
		var img := _blank(20, 18)
		_rect(img, 1, 1, 18, 16, skin)
		_round_corners(img, 3)
		_rect(img, 1, 1, 18, 4, hair)                       # hair
		_rect(img, 1, 4, 6, 6, hair)                        # fringe
		_round_corners(img, 3)
		_rect(img, 5, 8, 6, 10, eye)                        # eyes
		_rect(img, 12, 8, 13, 10, eye)
		_rect(img, 8, 13, 12, 13, skin.darkened(0.42))      # mouth
		return _finish(img))


func _tex_torso(shirt: Color, dark: Color) -> ImageTexture:
	return _cached("torso", func() -> ImageTexture:
		var img := _blank(18, 22)
		_rect(img, 1, 0, 16, 21, shirt)
		_round_corners(img, 2)
		_rect(img, 1, 0, 16, 2, shirt.lightened(0.18))      # collar
		_rect(img, 8, 3, 9, 17, dark)                       # zip
		_rect(img, 1, 18, 16, 21, dark.darkened(0.25))      # belt
		_rect(img, 7, 19, 10, 20, Color(0.85, 0.72, 0.32))  # buckle
		return _finish(img))


func _tex_limb(w: int, h: int, upper: Color, lower: Color) -> ImageTexture:
	var key := "limb_%d_%d_%s_%s" % [w, h, upper.to_html(), lower.to_html()]
	return _cached(key, func() -> ImageTexture:
		var img := _blank(w, h)
		var split := int(float(h) * 0.62)
		_rect(img, 0, 0, w - 1, split, upper)
		_rect(img, 0, split + 1, w - 1, h - 1, lower)
		_round_corners(img, 1)
		return _finish(img))


func _tex_cape(c: Color) -> ImageTexture:
	return _cached("cape", func() -> ImageTexture:
		var img := _blank(22, 28)
		for y in 28:
			var inset := int(roundf(lerpf(6.0, 0.0, float(y) / 27.0)))
			_rect(img, inset, y, 21 - inset, y, c)
		_rect(img, 0, 25, 21, 27, c.lightened(0.20))        # hem
		return _finish(img))


func _tex_pack(c: Color) -> ImageTexture:
	return _cached("pack", func() -> ImageTexture:
		var img := _blank(12, 14)
		_rect(img, 0, 0, 11, 13, c)
		_round_corners(img, 2)
		_rect(img, 2, 4, 3, 13, c.darkened(0.35))
		_rect(img, 8, 4, 9, 13, c.darkened(0.35))
		_rect(img, 0, 2, 11, 3, c.lightened(0.15))
		return _finish(img))


func _armor_texture(slot: StringName, col: Color) -> ImageTexture:
	return _cached("armor_%s_%s" % [slot, col.to_html()], func() -> ImageTexture:
		var img: Image = null
		if slot == ItemType.SLOT_HEAD:
			img = _blank(20, 18)
			_rect(img, 0, 0, 19, 7, col)
			_rect(img, 0, 7, 3, 12, col)
			_rect(img, 16, 7, 19, 12, col)
			_round_corners(img, 3)
		elif slot == ItemType.SLOT_CHEST:
			img = _blank(18, 22)
			_rect(img, 0, 0, 17, 14, col)
			_rect(img, 6, 4, 11, 11, col.lightened(0.25))
			_round_corners(img, 2)
		elif slot == ItemType.SLOT_LEGS:
			img = _blank(8, 22)
			_rect(img, 0, 0, 7, 13, col)
			_round_corners(img, 1)
		else:
			img = _blank(22, 28)
			for y in 28:
				var inset := int(roundf(lerpf(6.0, 0.0, float(y) / 27.0)))
				_rect(img, inset, y, 21 - inset, y, col)
		return _finish(img))


func _item_texture(item_id: StringName) -> ImageTexture:
	var t := Items.get_type(item_id)
	if t == null:
		return _tex_item(Color(0.75, 0.75, 0.75), &"square")
	# Prefer the render agent's icon once the atlas is up.
	if Atlas.has_method(&"item_icon"):
		var ic: Variant = Atlas.call(&"item_icon", item_id)
		if ic is ImageTexture:
			return ic
	return _tex_item(t.icon_color, t.icon_shape)


func _tex_item(col: Color, shape: StringName) -> ImageTexture:
	return _cached("item_%s_%s" % [shape, col.to_html()], func() -> ImageTexture:
		var img := _blank(16, 16)
		if shape == &"circle" or shape == &"orb" or shape == &"gem":
			for y in 16:
				for x in 16:
					if Vector2(float(x) - 7.5, float(y) - 7.5).length() <= 6.6:
						img.set_pixel(x, y, col)
		elif shape == &"rod" or shape == &"wand" or shape == &"pickaxe" \
				or shape == &"axe" or shape == &"shovel":
			_rect(img, 6, 5, 9, 15, col.darkened(0.45))     # haft
			_rect(img, 2, 1, 13, 5, col)                    # head
		elif shape == &"sword" or shape == &"blade":
			_rect(img, 6, 0, 9, 11, col)                    # blade
			_rect(img, 3, 11, 12, 12, col.darkened(0.30))   # guard
			_rect(img, 6, 13, 9, 15, col.darkened(0.55))    # grip
		elif shape == &"bar" or shape == &"ingot":
			_rect(img, 1, 5, 14, 11, col)
		else:
			_rect(img, 2, 2, 13, 13, col)
			_round_corners(img, 1)
		return _finish(img))
