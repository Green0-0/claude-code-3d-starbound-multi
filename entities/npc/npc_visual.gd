## Procedural paper-doll billboard for an NPC.
##
## Same treatment as the player: a flat, unshaded, layered sprite standing in a
## 3D voxel world. Nothing is loaded from disk — every limb is a [QuadMesh] with
## its own [StandardMaterial3D], assembled into one of seven race silhouettes and
## then dressed in a clothing layer chosen by role.
##
## The whole rig is yawed to the camera each frame rather than billboarding each
## quad individually, so limb offsets stay geometrically exact through a flip.
## Mirroring for [code]facing[/code] is a scale on an inner node, which keeps
## asymmetric details (a smith's hammer arm, a novakid's brand) on the right side.
class_name NpcVisual
extends Node3D

## Depth spacing between paper-doll layers, in metres. Small enough to read as
## flat, large enough to never z-fight.
const LAYER_STEP := 0.012

## Per-race body proportions: [height, torso_w, head_w, head_h, limb_w].
const PROPORTIONS := {
	&"human":   [1.75, 0.42, 0.34, 0.32, 0.13],
	&"apex":    [1.82, 0.50, 0.36, 0.34, 0.16],
	&"avian":   [1.70, 0.36, 0.30, 0.30, 0.11],
	&"floran":  [1.72, 0.40, 0.32, 0.32, 0.12],
	&"glitch":  [1.78, 0.46, 0.36, 0.36, 0.15],
	&"hylotl":  [1.68, 0.38, 0.33, 0.31, 0.12],
	&"novakid": [1.74, 0.40, 0.32, 0.32, 0.12],
}

## Base skin/plating hues per race; each NPC jitters them deterministically.
const SKIN = {
	&"human": [Color(0.94, 0.78, 0.64), Color(0.78, 0.58, 0.42), Color(0.48, 0.33, 0.24)],
	&"apex": [Color(0.42, 0.31, 0.22), Color(0.28, 0.22, 0.18), Color(0.62, 0.50, 0.36)],
	&"avian": [Color(0.86, 0.84, 0.78), Color(0.62, 0.74, 0.86), Color(0.88, 0.62, 0.42)],
	&"floran": [Color(0.45, 0.72, 0.36), Color(0.32, 0.58, 0.30), Color(0.66, 0.78, 0.34)],
	&"glitch": [Color(0.66, 0.68, 0.72), Color(0.54, 0.56, 0.62), Color(0.78, 0.74, 0.58)],
	&"hylotl": [Color(0.36, 0.62, 0.68), Color(0.28, 0.46, 0.62), Color(0.52, 0.72, 0.60)],
	&"novakid": [Color(1.0, 0.78, 0.45), Color(0.98, 0.55, 0.42), Color(0.72, 0.82, 1.0)],
}

## Hair / crest / frond colours.
const HAIR = {
	&"human": [Color(0.18, 0.12, 0.08), Color(0.44, 0.28, 0.12), Color(0.82, 0.72, 0.46), Color(0.6, 0.6, 0.62)],
	&"apex": [Color(0.2, 0.15, 0.1), Color(0.35, 0.24, 0.14)],
	&"avian": [Color(0.9, 0.35, 0.25), Color(0.95, 0.72, 0.2), Color(0.3, 0.55, 0.85)],
	&"floran": [Color(0.85, 0.35, 0.45), Color(0.55, 0.78, 0.3), Color(0.9, 0.75, 0.25)],
	&"glitch": [Color(0.3, 0.85, 0.55), Color(0.9, 0.7, 0.2)],
	&"hylotl": [Color(0.2, 0.35, 0.5), Color(0.5, 0.25, 0.45)],
	&"novakid": [Color(1.0, 0.9, 0.6), Color(0.7, 0.9, 1.0)],
}

## Clothing palettes indexed by role id.
const OUTFIT = {
	&"villager":   [Color(0.55, 0.44, 0.32), Color(0.42, 0.36, 0.30)],
	&"merchant":   [Color(0.42, 0.22, 0.36), Color(0.86, 0.72, 0.30)],
	&"innkeeper":  [Color(0.72, 0.62, 0.44), Color(0.90, 0.88, 0.82)],
	&"blacksmith": [Color(0.26, 0.22, 0.20), Color(0.55, 0.30, 0.16)],
	&"doctor":     [Color(0.92, 0.94, 0.96), Color(0.30, 0.62, 0.68)],
	&"guard":      [Color(0.42, 0.46, 0.55), Color(0.72, 0.76, 0.82)],
	&"scientist":  [Color(0.88, 0.90, 0.94), Color(0.35, 0.70, 0.85)],
	&"crew":       [Color(0.24, 0.34, 0.48), Color(0.90, 0.62, 0.22)],
	&"trader":     [Color(0.30, 0.26, 0.40), Color(0.80, 0.66, 0.34)],
}

var race: StringName = &"human"
var role_id: StringName = &"villager"
var palette_seed: int = 0
var height: float = 1.75

## The colours this NPC was rolled with; the dialogue portrait reuses them.
var skin_color := Color.WHITE
var hair_color := Color.BLACK
var cloth_color := Color.GRAY
var trim_color := Color.WHITE

var _yaw_root: Node3D = null      ## rotated to face the camera
var _flip_root: Node3D = null     ## scale.x = facing
var _hip_l: Node3D = null
var _hip_r: Node3D = null
var _shoulder_l: Node3D = null
var _shoulder_r: Node3D = null
var _head_pivot: Node3D = null
var _body_root: Node3D = null
var _bubble: Label3D = null

var _cycle := 0.0
var _bob := 0.0
var _speed := 0.0
var _airborne := false
var _activity: StringName = &"idle"
var _talk_t := 0.0
var _bubble_t := 0.0
var _layer := 0


## Builds the whole rig. Safe to call again to re-dress an NPC.
func setup(p_race: StringName, p_role: StringName, p_seed: int) -> void:
	race = p_race if PROPORTIONS.has(p_race) else &"human"
	role_id = p_role
	palette_seed = p_seed
	for c: Node in get_children():
		c.queue_free()
	_layer = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	var prop: Array = PROPORTIONS[race]
	height = float(prop[0]) * rng.randf_range(0.94, 1.06)
	var torso_w := float(prop[1])
	var head_w := float(prop[2])
	var head_h := float(prop[3])
	var limb_w := float(prop[4])

	skin_color = _jitter(_pick_color(SKIN, race, rng), rng, 0.06)
	hair_color = _jitter(_pick_color(HAIR, race, rng), rng, 0.08)
	var outfit: Array = OUTFIT.get(role_id, OUTFIT[&"villager"])
	cloth_color = _jitter(outfit[0], rng, 0.07)
	trim_color = _jitter(outfit[1], rng, 0.07)

	_yaw_root = Node3D.new()
	_yaw_root.name = "Yaw"
	add_child(_yaw_root)
	_flip_root = Node3D.new()
	_flip_root.name = "Flip"
	_yaw_root.add_child(_flip_root)
	_body_root = Node3D.new()
	_body_root.name = "Body"
	_flip_root.add_child(_body_root)

	var scale_f := height / 1.75
	_body_root.scale = Vector3(scale_f, scale_f, 1.0)

	var leg_len := 0.62
	var torso_y := leg_len
	var torso_h := 0.56
	var head_y := torso_y + torso_h

	# --- legs ---------------------------------------------------------------
	_hip_l = _pivot("HipL", Vector3(-limb_w * 0.55, leg_len, 0.0))
	_quad(_hip_l, "LegL", limb_w * 0.9, leg_len, cloth_color.darkened(0.25), Vector3(0, -leg_len * 0.5, 0))
	_hip_r = _pivot("HipR", Vector3(limb_w * 0.55, leg_len, 0.0))
	_quad(_hip_r, "LegR", limb_w * 0.9, leg_len, cloth_color.darkened(0.18), Vector3(0, -leg_len * 0.5, 0))
	_quad(_hip_l, "BootL", limb_w * 1.1, 0.13, trim_color.darkened(0.45), Vector3(0, -leg_len + 0.06, 0))
	_quad(_hip_r, "BootR", limb_w * 1.1, 0.13, trim_color.darkened(0.45), Vector3(0, -leg_len + 0.06, 0))

	# --- torso --------------------------------------------------------------
	_quad(_body_root, "Torso", torso_w, torso_h, cloth_color, Vector3(0, torso_y + torso_h * 0.5, 0))
	_quad(_body_root, "Collar", torso_w * 0.9, 0.09, trim_color, Vector3(0, head_y - 0.05, 0))

	# --- arms ---------------------------------------------------------------
	var arm_x := torso_w * 0.5 + limb_w * 0.35
	_shoulder_l = _pivot("ShoulderL", Vector3(-arm_x, head_y - 0.08, 0.0))
	_quad(_shoulder_l, "ArmL", limb_w * 0.75, 0.52, cloth_color.lightened(0.06), Vector3(0, -0.26, 0))
	_quad(_shoulder_l, "HandL", limb_w * 0.8, 0.12, skin_color, Vector3(0, -0.52, 0))
	_shoulder_r = _pivot("ShoulderR", Vector3(arm_x, head_y - 0.08, 0.0))
	_quad(_shoulder_r, "ArmR", limb_w * 0.75, 0.52, cloth_color.lightened(0.02), Vector3(0, -0.26, 0))
	_quad(_shoulder_r, "HandR", limb_w * 0.8, 0.12, skin_color, Vector3(0, -0.52, 0))

	# --- head ---------------------------------------------------------------
	_head_pivot = _pivot("Head", Vector3(0, head_y, 0))
	_quad(_head_pivot, "Skull", head_w, head_h, skin_color, Vector3(0, head_h * 0.5, 0))
	_build_race_features(_head_pivot, head_w, head_h, rng)
	_build_outfit(head_w, head_h, torso_w, torso_h, torso_y, rng)

	set_facing(1)


# =========================================================================
#  Race silhouettes
# =========================================================================
func _build_race_features(head: Node3D, hw: float, hh: float, rng: RandomNumberGenerator) -> void:
	var eye := Color(0.08, 0.09, 0.12)
	match race:
		&"human":
			_quad(head, "Hair", hw * 1.06, hh * 0.42, hair_color, Vector3(0, hh * 0.82, 0))
			_quad(head, "Fringe", hw * 0.5, hh * 0.22, hair_color, Vector3(-hw * 0.22, hh * 0.6, 0))
			_eyes(head, hw, hh, eye, 0.11)
		&"apex":
			# Heavy brow, fur ruff, two ear tufts.
			_quad(head, "Ruff", hw * 1.25, hh * 0.30, hair_color.darkened(0.1), Vector3(0, hh * 0.08, 0))
			_quad(head, "Brow", hw * 0.95, hh * 0.14, hair_color.darkened(0.35), Vector3(0, hh * 0.60, 0))
			_quad(head, "EarL", hw * 0.26, hh * 0.34, skin_color.darkened(0.18), Vector3(-hw * 0.52, hh * 0.92, 0), -22.0)
			_quad(head, "EarR", hw * 0.26, hh * 0.34, skin_color.darkened(0.18), Vector3(hw * 0.52, hh * 0.92, 0), 22.0)
			_eyes(head, hw, hh, Color(0.9, 0.78, 0.3), 0.10)
		&"avian":
			# Crest of three feathers and a forward beak.
			for i in 3:
				var t := float(i) - 1.0
				_quad(head, "Crest%d" % i, hw * 0.16, hh * (0.5 + 0.18 * (1.0 - absf(t))),
					hair_color, Vector3(t * hw * 0.20, hh * 1.05, 0.0), t * 26.0)
			_quad(head, "Beak", hw * 0.34, hh * 0.20, Color(0.94, 0.72, 0.26),
				Vector3(-hw * 0.52, hh * 0.44, LAYER_STEP), 8.0)
			_quad(head, "Wattle", hw * 0.14, hh * 0.16, Color(0.86, 0.34, 0.30),
				Vector3(-hw * 0.40, hh * 0.24, 0))
			_eyes(head, hw, hh, Color(0.1, 0.1, 0.12), 0.13)
		&"floran":
			# Petal crown, leaf shoulders, pointed jaw.
			for i in 5:
				var a := lerpf(-70.0, 70.0, float(i) / 4.0)
				_quad(head, "Frond%d" % i, hw * 0.14, hh * 0.62, hair_color,
					Vector3(sin(deg_to_rad(a)) * hw * 0.34, hh * 0.98, 0.0), a)
			_quad(head, "Jaw", hw * 0.6, hh * 0.22, skin_color.darkened(0.2), Vector3(0, hh * 0.06, LAYER_STEP), 45.0)
			_eyes(head, hw, hh, Color(0.95, 0.85, 0.25), 0.12)
		&"glitch":
			# Square plating, rivets, antenna with a pilot light.
			_quad(head, "Plate", hw * 1.04, hh * 0.98, skin_color.darkened(0.12), Vector3(0, hh * 0.5, -LAYER_STEP))
			_quad(head, "Antenna", hw * 0.06, hh * 0.44, skin_color.darkened(0.3), Vector3(hw * 0.22, hh * 1.16, 0))
			_quad(head, "Pilot", hw * 0.13, hh * 0.13, hair_color, Vector3(hw * 0.22, hh * 1.42, 0), 45.0, 1.0)
			_quad(head, "Visor", hw * 0.86, hh * 0.20, Color(0.10, 0.12, 0.16), Vector3(0, hh * 0.56, LAYER_STEP))
			_quad(head, "EyeGlow", hw * 0.5, hh * 0.08, hair_color, Vector3(0, hh * 0.56, LAYER_STEP * 2.0), 0.0, 0.9)
		&"hylotl":
			# Head fins, wide eyes, throat gills.
			_quad(head, "FinL", hw * 0.30, hh * 0.52, hair_color, Vector3(-hw * 0.56, hh * 0.62, -LAYER_STEP), -34.0)
			_quad(head, "FinR", hw * 0.30, hh * 0.52, hair_color, Vector3(hw * 0.56, hh * 0.62, -LAYER_STEP), 34.0)
			_quad(head, "Crown", hw * 0.9, hh * 0.22, skin_color.lightened(0.16), Vector3(0, hh * 0.86, 0))
			_quad(head, "Gills", hw * 0.36, hh * 0.10, skin_color.darkened(0.25), Vector3(0, hh * 0.10, LAYER_STEP))
			_eyes(head, hw, hh, Color(0.95, 0.95, 0.98), 0.17, Color(0.06, 0.08, 0.1))
		&"novakid":
			# No hair: a gas silhouette with a glowing brand.
			_quad(head, "Halo", hw * 1.25, hh * 1.20, skin_color, Vector3(0, hh * 0.52, -LAYER_STEP), 0.0, 0.55)
			var brands: Array[String] = ["+", "x", "o", "t"]
			var b: String = brands[rng.randi_range(0, brands.size() - 1)]
			_brand(head, b, hw, hh)
			_quad(head, "EyeGlow", hw * 0.46, hh * 0.09, Color(1, 1, 1, 0.85),
				Vector3(0, hh * 0.55, LAYER_STEP), 0.0, 0.8)


func _eyes(head: Node3D, hw: float, hh: float, col: Color, size: float,
		pupil: Color = Color(0, 0, 0, 0)) -> void:
	_quad(head, "EyeL", hw * size, hh * size * 1.1, col, Vector3(-hw * 0.20, hh * 0.56, LAYER_STEP))
	_quad(head, "EyeR", hw * size, hh * size * 1.1, col, Vector3(hw * 0.20, hh * 0.56, LAYER_STEP))
	if pupil.a > 0.0:
		_quad(head, "PupL", hw * size * 0.5, hh * size * 0.5, pupil, Vector3(-hw * 0.20, hh * 0.56, LAYER_STEP * 2.0))
		_quad(head, "PupR", hw * size * 0.5, hh * size * 0.5, pupil, Vector3(hw * 0.20, hh * 0.56, LAYER_STEP * 2.0))


## Novakid brands are drawn as two or three crossed bars.
func _brand(head: Node3D, shape: String, hw: float, hh: float) -> void:
	var c := hair_color
	var at := Vector3(0, hh * 0.72, LAYER_STEP * 2.0)
	match shape:
		"+":
			_quad(head, "Brand0", hw * 0.42, hh * 0.07, c, at, 0.0, 1.0)
			_quad(head, "Brand1", hw * 0.07, hh * 0.42, c, at, 0.0, 1.0)
		"x":
			_quad(head, "Brand0", hw * 0.42, hh * 0.07, c, at, 45.0, 1.0)
			_quad(head, "Brand1", hw * 0.42, hh * 0.07, c, at, -45.0, 1.0)
		"o":
			for i in 6:
				var a := 60.0 * float(i)
				_quad(head, "Brand%d" % i, hw * 0.16, hh * 0.06, c,
					at + Vector3(cos(deg_to_rad(a)) * hw * 0.16, sin(deg_to_rad(a)) * hh * 0.16, 0.0), a + 90.0, 1.0)
		_:
			_quad(head, "Brand0", hw * 0.42, hh * 0.07, c, at + Vector3(0, hh * 0.14, 0), 0.0, 1.0)
			_quad(head, "Brand1", hw * 0.07, hh * 0.40, c, at, 0.0, 1.0)


# =========================================================================
#  Clothing layers
# =========================================================================
func _build_outfit(hw: float, hh: float, tw: float, th: float, ty: float, rng: RandomNumberGenerator) -> void:
	var head := _head_pivot
	var body := _body_root
	var chest := Vector3(0, ty + th * 0.5, LAYER_STEP)
	match role_id:
		&"merchant":
			_quad(body, "Coat", tw * 1.16, th * 1.20, cloth_color.darkened(0.1), chest)
			_quad(body, "Sash", tw * 1.18, th * 0.16, trim_color, Vector3(0, ty + th * 0.28, LAYER_STEP * 2.0), 12.0)
			_quad(head, "HatBrim", hw * 1.45, hh * 0.12, cloth_color.darkened(0.25), Vector3(0, hh * 0.98, LAYER_STEP))
			_quad(head, "HatCrown", hw * 0.78, hh * 0.40, cloth_color.darkened(0.2), Vector3(0, hh * 1.18, 0))
			_quad(head, "HatBand", hw * 0.80, hh * 0.09, trim_color, Vector3(0, hh * 1.02, LAYER_STEP * 2.0))
		&"innkeeper":
			_quad(body, "Apron", tw * 0.92, th * 0.86, trim_color, Vector3(0, ty + th * 0.38, LAYER_STEP))
			_quad(body, "ApronTie", tw * 1.0, th * 0.10, cloth_color.darkened(0.3), Vector3(0, ty + th * 0.62, LAYER_STEP * 2.0))
			_quad(body, "Towel", tw * 0.22, th * 0.40, Color(0.92, 0.90, 0.84), Vector3(tw * 0.60, ty + th * 0.55, LAYER_STEP), 8.0)
		&"blacksmith":
			_quad(body, "Apron", tw * 1.0, th * 1.05, trim_color.darkened(0.25), Vector3(0, ty + th * 0.42, LAYER_STEP))
			_quad(body, "Scorch", tw * 0.30, th * 0.18, Color(0.15, 0.12, 0.10), Vector3(-tw * 0.18, ty + th * 0.30, LAYER_STEP * 2.0), 20.0)
			_quad(head, "Goggles", hw * 1.05, hh * 0.18, Color(0.20, 0.18, 0.16), Vector3(0, hh * 0.92, LAYER_STEP))
			_quad(head, "LensL", hw * 0.22, hh * 0.16, Color(0.85, 0.65, 0.25), Vector3(-hw * 0.22, hh * 0.92, LAYER_STEP * 2.0), 0.0, 0.5)
			_quad(head, "LensR", hw * 0.22, hh * 0.16, Color(0.85, 0.65, 0.25), Vector3(hw * 0.22, hh * 0.92, LAYER_STEP * 2.0), 0.0, 0.5)
		&"doctor":
			_quad(body, "Coat", tw * 1.20, th * 1.35, cloth_color, Vector3(0, ty + th * 0.40, LAYER_STEP))
			_quad(body, "Cross0", tw * 0.20, th * 0.06, Color(0.85, 0.25, 0.25), Vector3(tw * 0.34, ty + th * 0.78, LAYER_STEP * 2.0))
			_quad(body, "Cross1", tw * 0.06, th * 0.20, Color(0.85, 0.25, 0.25), Vector3(tw * 0.34, ty + th * 0.78, LAYER_STEP * 2.0))
			_quad(head, "Mask", hw * 0.86, hh * 0.30, Color(0.90, 0.94, 0.96), Vector3(0, hh * 0.30, LAYER_STEP * 2.0))
		&"guard":
			_quad(body, "Plate", tw * 1.10, th * 0.90, trim_color, Vector3(0, ty + th * 0.55, LAYER_STEP))
			_quad(body, "Belt", tw * 1.12, th * 0.13, cloth_color.darkened(0.3), Vector3(0, ty + th * 0.10, LAYER_STEP * 2.0))
			_quad(_shoulder_l, "PauldronL", 0.20, 0.14, trim_color, Vector3(0, -0.02, LAYER_STEP))
			_quad(_shoulder_r, "PauldronR", 0.20, 0.14, trim_color, Vector3(0, -0.02, LAYER_STEP))
			_quad(head, "Helm", hw * 1.12, hh * 0.72, trim_color, Vector3(0, hh * 0.72, LAYER_STEP))
			_quad(head, "Slit", hw * 0.80, hh * 0.10, Color(0.08, 0.09, 0.12), Vector3(0, hh * 0.56, LAYER_STEP * 2.0))
			_quad(head, "Plume", hw * 0.12, hh * 0.46, Color(0.78, 0.22, 0.22), Vector3(0, hh * 1.24, 0))
		&"scientist":
			_quad(body, "Coat", tw * 1.18, th * 1.30, cloth_color, Vector3(0, ty + th * 0.42, LAYER_STEP))
			_quad(body, "Pocket", tw * 0.24, th * 0.16, cloth_color.darkened(0.12), Vector3(-tw * 0.34, ty + th * 0.30, LAYER_STEP * 2.0))
			_quad(body, "Pen", tw * 0.04, th * 0.14, trim_color, Vector3(-tw * 0.34, ty + th * 0.36, LAYER_STEP * 3.0))
			_quad(head, "Visor", hw * 1.10, hh * 0.22, trim_color, Vector3(0, hh * 0.60, LAYER_STEP * 2.0), 0.0, 0.35)
		&"crew":
			_quad(body, "Suit", tw * 1.08, th * 1.10, cloth_color, Vector3(0, ty + th * 0.48, LAYER_STEP))
			_quad(body, "Stripe", tw * 0.10, th * 1.05, trim_color, Vector3(-tw * 0.36, ty + th * 0.48, LAYER_STEP * 2.0))
			_quad(body, "Badge", tw * 0.16, th * 0.16, trim_color, Vector3(tw * 0.30, ty + th * 0.80, LAYER_STEP * 2.0), 45.0)
		&"trader":
			_quad(body, "Longcoat", tw * 1.24, th * 1.60, cloth_color.darkened(0.08), Vector3(0, ty + th * 0.24, LAYER_STEP))
			_quad(body, "Lapel", tw * 0.26, th * 0.60, trim_color.darkened(0.15), Vector3(-tw * 0.30, ty + th * 0.55, LAYER_STEP * 2.0), 10.0)
			_quad(body, "Pack", tw * 0.55, th * 0.60, trim_color.darkened(0.35), Vector3(tw * 0.55, ty + th * 0.70, -LAYER_STEP * 3.0), -8.0)
			_quad(head, "WideBrim", hw * 1.85, hh * 0.11, cloth_color.darkened(0.3), Vector3(0, hh * 0.96, LAYER_STEP))
			_quad(head, "Crown", hw * 0.72, hh * 0.34, cloth_color.darkened(0.24), Vector3(0, hh * 1.14, 0))
		_:
			_quad(body, "Tunic", tw * 1.06, th * 0.96, cloth_color, Vector3(0, ty + th * 0.48, LAYER_STEP))
			if rng.randf() < 0.4:
				_quad(head, "Cap", hw * 1.10, hh * 0.28, trim_color, Vector3(0, hh * 0.92, LAYER_STEP))


# =========================================================================
#  Primitive builders
# =========================================================================
func _pivot(p_name: String, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = p_name
	n.position = at
	_body_root.add_child(n)
	return n


func _quad(parent: Node3D, p_name: String, w: float, h: float, col: Color,
		at: Vector3, rot_deg: float = 0.0, emission: float = 0.0) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(maxf(0.01, w), maxf(0.01, h))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = false
	if col.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = emission * 2.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = p_name
	mi.mesh = mesh
	_layer += 1
	mi.position = at + Vector3(0, 0, float(_layer) * 0.0004)
	if rot_deg != 0.0:
		mi.rotation.z = deg_to_rad(rot_deg)
	mi.layers = Const.RL_ENTITIES
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _pick_color(table: Dictionary, key: StringName, rng: RandomNumberGenerator) -> Color:
	var list: Array = table.get(key, [Color.WHITE])
	return list[rng.randi_range(0, list.size() - 1)]


static func _jitter(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	return Color(
		clampf(c.r + rng.randf_range(-amount, amount), 0.0, 1.0),
		clampf(c.g + rng.randf_range(-amount, amount), 0.0, 1.0),
		clampf(c.b + rng.randf_range(-amount, amount), 0.0, 1.0),
		c.a)


# =========================================================================
#  Animation
# =========================================================================
## Drives the walk cycle. `speed` is plane-space metres/second.
func set_motion(speed: float, on_floor: bool) -> void:
	_speed = absf(speed)
	_airborne = not on_floor


## `idle` `walk` `work` `sleep` `socialise` `flee` `fight` `follow` `talk`.
func set_activity(a: StringName) -> void:
	_activity = a


func set_facing(f: int) -> void:
	if _flip_root != null:
		_flip_root.scale = Vector3(-1.0 if f < 0 else 1.0, 1.0, 1.0)


## Nod the head for a moment — called when a dialogue line advances.
func pulse_talk() -> void:
	_talk_t = 0.35


## Floating text above the head. Used for greetings and barks.
func show_bubble(msg: String, duration: float = 3.0) -> void:
	if msg == "":
		return
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.name = "Bubble"
		_bubble.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_bubble.no_depth_test = true
		_bubble.font_size = 44
		_bubble.pixel_size = 0.0032
		_bubble.outline_size = 12
		_bubble.outline_modulate = Color(0.05, 0.05, 0.08, 0.85)
		_bubble.modulate = Color(0.98, 0.98, 1.0)
		_bubble.layers = Const.RL_EFFECTS
		_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bubble.width = 340.0
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_bubble)
	_bubble.text = msg
	_bubble.position = Vector3(0, height + 0.42, 0)
	_bubble.visible = true
	_bubble_t = duration


func hide_bubble() -> void:
	_bubble_t = 0.0
	if _bubble != null:
		_bubble.visible = false


func _process(delta: float) -> void:
	if _yaw_root == null:
		return
	# Face the camera plane exactly, mid-flip included.
	_yaw_root.rotation.y = View.current_yaw()

	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false

	if _talk_t > 0.0:
		_talk_t = maxf(0.0, _talk_t - delta)

	match _activity:
		&"sleep":
			_animate_sleep(delta)
		&"work":
			_animate_work(delta)
		_:
			_animate_walk(delta)


func _animate_walk(delta: float) -> void:
	var moving := _speed > 0.4
	_cycle += (delta * (6.0 + _speed * 1.6)) if moving else (delta * 1.6)
	_body_root.rotation.z = 0.0
	_body_root.position.y = 0.0
	var swing := 0.0
	if moving:
		swing = sin(_cycle) * clampf(_speed * 0.11, 0.12, 0.55)
	elif _activity == &"socialise":
		swing = sin(_cycle * 0.8) * 0.04
	if _airborne:
		swing = 0.35
	_hip_l.rotation.z = swing
	_hip_r.rotation.z = -swing
	_shoulder_l.rotation.z = -swing * 0.75
	_shoulder_r.rotation.z = swing * 0.75
	_bob = sin(_cycle * 2.0) * (0.022 if moving else 0.008)
	_body_root.position.y = _bob
	var nod := sin(_cycle * 2.0) * 0.03
	if _talk_t > 0.0:
		nod += sin(_talk_t * 40.0) * 0.09
	_head_pivot.rotation.z = nod * 0.5


func _animate_work(delta: float) -> void:
	_cycle += delta * 5.0
	var hammer := absf(sin(_cycle)) * 1.15
	_shoulder_r.rotation.z = -hammer
	_shoulder_l.rotation.z = -hammer * 0.25
	_hip_l.rotation.z = 0.0
	_hip_r.rotation.z = 0.0
	_body_root.position.y = -absf(sin(_cycle)) * 0.02
	_body_root.rotation.z = sin(_cycle) * 0.03
	_head_pivot.rotation.z = -0.12


func _animate_sleep(delta: float) -> void:
	_cycle += delta * 1.2
	_body_root.rotation.z = deg_to_rad(-84.0)
	_body_root.position.y = 0.30 + sin(_cycle) * 0.012
	_hip_l.rotation.z = 0.18
	_hip_r.rotation.z = 0.10
	_shoulder_l.rotation.z = 0.5
	_shoulder_r.rotation.z = 0.4
	_head_pivot.rotation.z = 0.1
	if _bubble != null and _bubble.visible:
		_bubble.text = "z z z"


## Colour the dialogue window / quest log can key off.
func portrait_color() -> Color:
	return skin_color.lerp(cloth_color, 0.35)
