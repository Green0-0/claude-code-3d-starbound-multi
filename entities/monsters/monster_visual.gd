## Procedural creature sprites.
##
## Every monster is assembled at runtime from generated pixel shapes — body,
## head, limbs, eyes, wings, tail — drawn into `Image`s and wrapped in
## `ImageTexture`. A species seed drives the silhouette, palette and pattern so
## each species reads as distinct; a per-individual variant seed nudges hue,
## proportion and limb length so no two Pebble Grubs are quite the same.
##
## The parts are separate `Sprite3D`s under a pivot, so animation is real limb
## transforms plus body squash/stretch rather than a flipbook.
##
## Orientation: billboard modes throw away the model's roll, which would kill
## limb rotation, so instead the whole visual is yawed to the camera every frame
## (`View.current_yaw()`). Local +X is therefore screen-right and local +Z faces
## the camera in all four planes, mid-flip included.
class_name MobVisual
extends Node3D

const PPU := 16.0                 ## texture pixels per world unit at scale 1
const Z_STEP := 0.006             ## per-layer separation so parts never z-fight

const ST_IDLE := &"idle"
const ST_WALK := &"walk"
const ST_RUN := &"run"
const ST_WINDUP := &"windup"
const ST_ATTACK := &"attack"
const ST_HURT := &"hurt"
const ST_DEATH := &"death"

## species-variant key -> {part name: ImageTexture}
static var _tex_cache: Dictionary = {}

var spec: Dictionary = {}
var state: StringName = ST_IDLE
var facing: int = 1
var anim_speed := 1.0

var _pivot: Node3D = null
var _parts: Dictionary = {}       ## StringName -> Sprite3D
var _base_pos: Dictionary = {}    ## StringName -> Vector3
var _t := 0.0
var _flash := 0.0
var _hurt_timer := 0.0
var _attack_timer := 0.0
var _windup := 0.0
var _telegraph := 0.0
var _dim := 0.0
var _death_t := -1.0
var _squash := 1.0
var _frozen := false
var _unit := 1.0
var _tint := Color(1, 1, 1, 1)
var _glow := 0.0
var _yaw_cached := -99.0


func _ready() -> void:
	set_process(true)


# ================================================================== assembly
## `spec` is the species `visual` dictionary; `variant` is the individual seed.
func build(p_spec: Dictionary, variant: int = 0, box_height: float = 1.0) -> void:
	spec = p_spec.duplicate()
	_unit = maxf(0.25, box_height / 1.35) * float(spec.get("scale", 1.0))
	_glow = float(spec.get("glow", 0.0))
	for c: Node in get_children():
		c.queue_free()
	_parts.clear()
	_base_pos.clear()

	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	var shape: StringName = spec.get("shape", &"blob")
	var species_seed := int(spec.get("seed", 0))
	var vkey := "%s:%d:%d" % [String(shape), species_seed, variant & 3]
	var textures: Dictionary = _tex_cache.get(vkey, {})
	if textures.is_empty():
		textures = _generate_textures(shape, species_seed, variant & 3)
		_tex_cache[vkey] = textures

	var rng := RandomNumberGenerator.new()
	rng.seed = species_seed ^ (variant * 7919)
	var layout := _layout_for(shape, rng)
	for entry: Dictionary in layout:
		var pname: StringName = entry["name"]
		if not textures.has(pname):
			continue
		var spr := _make_sprite(textures[pname], int(entry["z"]))
		spr.name = String(pname)
		var off: Vector2 = entry["offset"]
		spr.offset = off
		var pos: Vector3 = Vector3(float(entry["pos"].x) * _unit, float(entry["pos"].y) * _unit,
			float(entry["z"]) * Z_STEP)
		spr.position = pos
		_pivot.add_child(spr)
		_parts[pname] = spr
		_base_pos[pname] = pos
	_apply_tint()


func _make_sprite(tex: Texture2D, order: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = _unit / PPU
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.shaded = false
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.alpha_scissor_threshold = 0.5
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.render_priority = clampi(order, -8, 8)
	s.layers = Const.RL_ENTITIES
	return s


# ================================================================== layouts
## Where each part hangs, in `unit` multiples relative to the creature's feet.
## `z` orders parts front-to-back (higher = nearer the camera).
func _layout_for(shape: StringName, rng: RandomNumberGenerator) -> Array:
	var limbs: int = int(spec.get("limbs", 2))
	var wings: int = int(spec.get("wings", 0))
	var tail: bool = bool(spec.get("tail", false))
	var jitter := rng.randf_range(-0.04, 0.04)
	var out: Array = []

	var body_y := 0.62
	var head_x := 0.42
	var head_y := 0.95
	match shape:
		&"beetle", &"crab":
			body_y = 0.42
			head_x = 0.5
			head_y = 0.55
		&"quadruped":
			body_y = 0.66
			head_x = 0.55
			head_y = 0.9
		&"serpent", &"worm":
			body_y = 0.5
			head_x = 0.6
			head_y = 0.62
		&"jelly", &"orb":
			body_y = 0.75
			head_x = 0.0
			head_y = 0.75
		&"bird":
			body_y = 0.8
			head_x = 0.38
			head_y = 1.05
		&"plant":
			body_y = 0.7
			head_x = 0.0
			head_y = 0.95
		&"humanoid":
			body_y = 0.78
			head_x = 0.0
			head_y = 1.25

	if tail:
		out.append({"name": &"tail", "pos": Vector2(-0.55, body_y + jitter),
			"offset": Vector2(-6, 0), "z": -3})
	if wings > 0:
		out.append({"name": &"wing_back", "pos": Vector2(-0.15, body_y + 0.18),
			"offset": Vector2(-8, 0), "z": -2})
	if limbs >= 4:
		out.append({"name": &"limb_back", "pos": Vector2(-0.3, body_y - 0.18),
			"offset": Vector2(0, -7), "z": -1})
		out.append({"name": &"limb_back2", "pos": Vector2(0.28, body_y - 0.18),
			"offset": Vector2(0, -7), "z": -1})
	elif limbs >= 1:
		out.append({"name": &"limb_back", "pos": Vector2(-0.16, body_y - 0.2),
			"offset": Vector2(0, -7), "z": -1})

	out.append({"name": &"body", "pos": Vector2(0, body_y), "offset": Vector2.ZERO, "z": 0})

	if head_x != 0.0 or shape == &"jelly" or shape == &"orb" or shape == &"plant" or shape == &"humanoid":
		out.append({"name": &"head", "pos": Vector2(head_x, head_y + jitter),
			"offset": Vector2.ZERO, "z": 1})
	if wings > 0:
		out.append({"name": &"wing_front", "pos": Vector2(-0.1, body_y + 0.22),
			"offset": Vector2(-8, 0), "z": 2})
	if limbs >= 4:
		out.append({"name": &"limb_front", "pos": Vector2(-0.16, body_y - 0.16),
			"offset": Vector2(0, -7), "z": 3})
		out.append({"name": &"limb_front2", "pos": Vector2(0.42, body_y - 0.16),
			"offset": Vector2(0, -7), "z": 3})
	elif limbs >= 2:
		out.append({"name": &"limb_front", "pos": Vector2(0.18, body_y - 0.2),
			"offset": Vector2(0, -7), "z": 3})
	if int(spec.get("spikes", 0)) > 0:
		out.append({"name": &"crest", "pos": Vector2(-0.05, body_y + 0.34),
			"offset": Vector2.ZERO, "z": 4})
	return out


# =========================================================== texture factory
func _generate_textures(shape: StringName, species_seed: int, variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = species_seed + variant * 104729
	var primary: Color = spec.get("primary", Color(0.6, 0.5, 0.4))
	var secondary: Color = spec.get("secondary", primary.darkened(0.35))
	# Individual variation: a small hue/value drift, never enough to lose the
	# species read.
	primary = _shift(primary, rng.randf_range(-0.025, 0.025), rng.randf_range(-0.06, 0.06))
	secondary = _shift(secondary, rng.randf_range(-0.025, 0.025), rng.randf_range(-0.06, 0.06))
	var outline := primary.darkened(0.72)
	outline.a = 1.0
	var pattern: StringName = spec.get("pattern", &"none")
	var eyes: int = int(spec.get("eyes", 2))
	var out: Dictionary = {}

	out[&"body"] = _tex(_draw_body(shape, rng, primary, secondary, pattern, outline))
	var head := _draw_head(shape, rng, primary, secondary, eyes, outline)
	if head != null:
		out[&"head"] = _tex(head)
	if int(spec.get("limbs", 2)) > 0:
		var limb := _draw_limb(shape, rng, secondary, outline)
		out[&"limb_back"] = _tex(_tinted(limb, Color(0.72, 0.72, 0.78)))
		out[&"limb_back2"] = out[&"limb_back"]
		out[&"limb_front"] = _tex(limb)
		out[&"limb_front2"] = out[&"limb_front"]
	if int(spec.get("wings", 0)) > 0:
		var wing := _draw_wing(shape, rng, primary, outline)
		out[&"wing_front"] = _tex(wing)
		out[&"wing_back"] = _tex(_tinted(wing, Color(0.68, 0.68, 0.74)))
	if bool(spec.get("tail", false)):
		out[&"tail"] = _tex(_draw_tail(shape, rng, primary, secondary, outline))
	if int(spec.get("spikes", 0)) > 0:
		out[&"crest"] = _tex(_draw_crest(int(spec.get("spikes", 3)), rng, secondary, outline))
	return out


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _shift(c: Color, hue: float, val: float) -> Color:
	var h := c.h + hue
	return Color.from_hsv(fposmod(h, 1.0), clampf(c.s, 0.0, 1.0), clampf(c.v + val, 0.05, 1.0), c.a)


# ------------------------------------------------------------- image helpers
static func _img(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
		return
	var d := img.get_pixel(x, y)
	var a := c.a + d.a * (1.0 - c.a)
	if a <= 0.0001:
		return
	img.set_pixel(x, y, Color(
		(c.r * c.a + d.r * d.a * (1.0 - c.a)) / a,
		(c.g * c.a + d.g * d.a * (1.0 - c.a)) / a,
		(c.b * c.a + d.b * d.a * (1.0 - c.a)) / a, a))


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0 := maxi(0, floori(cx - rx))
	var x1 := mini(img.get_width() - 1, ceili(cx + rx))
	var y0 := maxi(0, floori(cy - ry))
	var y1 := mini(img.get_height() - 1, ceili(cy + ry))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var dx := (float(x) + 0.5 - cx) / rx
			var dy := (float(y) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_blend(img, x, y, c)


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for x in range(maxi(0, x0), mini(img.get_width(), x1 + 1)):
		for y in range(maxi(0, y0), mini(img.get_height(), y1 + 1)):
			_blend(img, x, y, c)


## Capsule from A to B whose radius lerps r0 -> r1. The workhorse for limbs,
## tails, tentacles and serpent bodies.
static func _taper(img: Image, a: Vector2, b: Vector2, r0: float, r1: float, c: Color) -> void:
	var steps := maxi(2, int(a.distance_to(b) * 2.0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var r: float = lerpf(r0, r1, t)
		_ellipse(img, p.x, p.y, r, r, c)


static func _triangle(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var minx := maxi(0, floori(minf(a.x, minf(b.x, c.x))))
	var maxx := mini(img.get_width() - 1, ceili(maxf(a.x, maxf(b.x, c.x))))
	var miny := maxi(0, floori(minf(a.y, minf(b.y, c.y))))
	var maxy := mini(img.get_height() - 1, ceili(maxf(a.y, maxf(b.y, c.y))))
	for x in range(minx, maxx + 1):
		for y in range(miny, maxy + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d1 := (p - a).cross(b - a)
			var d2 := (p - b).cross(c - b)
			var d3 := (p - c).cross(a - c)
			var neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
			var pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
			if not (neg and pos):
				_blend(img, x, y, col)


## Vertical light-to-dark shading so a flat blob reads as volume.
static func _shade(img: Image) -> void:
	var h := img.get_height()
	for y in h:
		var t := float(y) / maxf(1.0, float(h - 1))
		var f: float = lerpf(1.16, 0.72, t)
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			img.set_pixel(x, y, Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1),
				clampf(c.b * f, 0, 1), c.a))


static func _pattern(img: Image, kind: StringName, col: Color, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	match kind:
		&"stripes":
			var period := rng.randi_range(3, 5)
			for x in w:
				if x % period != 0:
					continue
				for y in h:
					if img.get_pixel(x, y).a > 0.5:
						_blend(img, x, y, col)
		&"spots":
			for _i in rng.randi_range(4, 8):
				var cx := rng.randf_range(2.0, float(w - 2))
				var cy := rng.randf_range(2.0, float(h - 2))
				var r := rng.randf_range(1.0, 2.4)
				for x in range(maxi(0, int(cx - r)), mini(w, int(cx + r) + 1)):
					for y in range(maxi(0, int(cy - r)), mini(h, int(cy + r) + 1)):
						if Vector2(x, y).distance_to(Vector2(cx, cy)) <= r and img.get_pixel(x, y).a > 0.5:
							_blend(img, x, y, col)
		&"plates":
			var n := rng.randi_range(3, 5)
			for i in range(1, n):
				var y := int(float(h) * float(i) / float(n))
				for x in w:
					if img.get_pixel(x, y).a > 0.5:
						_blend(img, x, y, col)
		&"speckle":
			for _i in int(w * h / 12):
				var x := rng.randi_range(0, w - 1)
				var y := rng.randi_range(0, h - 1)
				if img.get_pixel(x, y).a > 0.5:
					_blend(img, x, y, col)


## One-pixel outline grown outward, which is what makes small sprites legible.
static func _outline(img: Image, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			mask[y * w + x] = 1 if img.get_pixel(x, y).a > 0.5 else 0
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				continue
			var touching := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if mask[ny * w + nx] == 1:
					touching = true
					break
			if touching:
				img.set_pixel(x, y, col)


static func _tinted(src: Image, mul: Color) -> Image:
	var out := _img(src.get_width(), src.get_height())
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			out.set_pixel(x, y, Color(c.r * mul.r, c.g * mul.g, c.b * mul.b, c.a))
	return out


# --------------------------------------------------------------- part shapes
func _draw_body(shape: StringName, rng: RandomNumberGenerator, primary: Color,
		secondary: Color, pattern: StringName, outline: Color) -> Image:
	var w := 30
	var h := 24
	var img := _img(w, h)
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	match shape:
		&"beetle":
			_ellipse(img, cx, cy + 2.0, 12.0, 7.0, primary)
			_ellipse(img, cx, cy + 0.5, 11.0, 5.5, secondary)
			_rect(img, int(cx) - 1, int(cy) - 4, int(cx), h - 6, primary.darkened(0.35))
		&"crab":
			_ellipse(img, cx, cy + 2.0, 12.5, 6.0, primary)
			_taper(img, Vector2(cx - 9, cy + 1), Vector2(cx - 13, cy - 3), 2.0, 3.0, secondary)
			_taper(img, Vector2(cx + 9, cy + 1), Vector2(cx + 13, cy - 3), 2.0, 3.0, secondary)
		&"quadruped":
			_ellipse(img, cx - 1.0, cy + 1.0, 11.0, 6.0, primary)
			_ellipse(img, cx + 6.0, cy - 0.5, 5.0, 5.0, primary)
		&"insect":
			_ellipse(img, cx - 6.0, cy + 1.0, 5.0, 4.5, primary)
			_ellipse(img, cx + 0.5, cy + 1.0, 6.0, 5.0, primary)
			_ellipse(img, cx + 7.5, cy + 1.0, 4.5, 4.0, secondary)
		&"jelly":
			_ellipse(img, cx, cy - 2.0, 10.0, 8.0, primary)
			_rect(img, int(cx) - 10, int(cy) - 2, int(cx) + 10, int(cy) + 1, primary)
			for i in 5:
				var tx := cx - 8.0 + float(i) * 4.0
				_taper(img, Vector2(tx, cy), Vector2(tx + rng.randf_range(-2.0, 2.0), float(h) - 2.0),
					1.6, 0.7, secondary)
		&"orb":
			_ellipse(img, cx, cy, 9.0, 9.0, primary)
			_ellipse(img, cx - 2.5, cy - 2.5, 3.5, 3.5, primary.lightened(0.35))
		&"serpent":
			_taper(img, Vector2(3, cy + 5), Vector2(float(w) - 4.0, cy - 3.0), 3.0, 5.5, primary)
		&"worm":
			for i in 5:
				var t := float(i) / 4.0
				_ellipse(img, lerpf(4.0, float(w) - 5.0, t), cy + sin(t * PI) * 2.0,
					lerpf(3.5, 6.0, sin(t * PI)), lerpf(3.5, 6.0, sin(t * PI)),
					primary if i % 2 == 0 else secondary)
		&"bird":
			_ellipse(img, cx, cy + 1.0, 7.0, 8.5, primary)
			_ellipse(img, cx, cy + 4.0, 5.5, 5.0, secondary)
		&"plant":
			_taper(img, Vector2(cx, float(h) - 2.0), Vector2(cx, 6.0), 2.2, 1.4, secondary)
			_ellipse(img, cx, 7.0, 7.5, 6.0, primary)
		&"humanoid":
			_rect(img, int(cx) - 5, int(cy) - 8, int(cx) + 5, int(cy) + 7, primary)
			_ellipse(img, cx, cy - 7.0, 5.0, 4.0, primary)
			_ellipse(img, cx, cy + 6.0, 5.0, 4.0, secondary)
		_:
			# "blob" and anything unknown.
			_ellipse(img, cx, cy + 1.0, 10.0, 8.5, primary)
			_ellipse(img, cx, cy + 4.0, 8.0, 5.0, secondary)
	_shade(img)
	_pattern(img, pattern, secondary.darkened(0.2), rng)
	_outline(img, outline)
	return img


func _draw_head(shape: StringName, rng: RandomNumberGenerator, primary: Color,
		secondary: Color, eyes: int, outline: Color) -> Image:
	if shape == &"jelly" or shape == &"worm":
		return null
	var w := 18
	var h := 16
	var img := _img(w, h)
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	match shape:
		&"bird":
			_ellipse(img, cx - 1.0, cy, 5.0, 5.0, primary)
			_triangle(img, Vector2(cx + 3, cy - 1), Vector2(cx + 3, cy + 2),
				Vector2(float(w) - 1.0, cy + 0.5), secondary.lightened(0.2))
		&"beetle", &"crab", &"insect":
			_ellipse(img, cx, cy, 5.0, 4.0, secondary)
			_taper(img, Vector2(cx + 1, cy - 3), Vector2(cx + 5, cy - 6), 1.0, 0.6, secondary)
			_taper(img, Vector2(cx - 1, cy - 3), Vector2(cx - 5, cy - 6), 1.0, 0.6, secondary)
		&"serpent":
			_ellipse(img, cx, cy, 6.0, 4.0, primary)
		&"plant", &"orb":
			_ellipse(img, cx, cy, 6.5, 6.0, primary)
		&"humanoid":
			_ellipse(img, cx, cy, 5.5, 5.5, primary)
		_:
			_ellipse(img, cx, cy, 6.0, 5.5, primary)
	# Eyes: the single strongest readability cue, so they get a highlight.
	if eyes > 0:
		var spread: float = 2.2 if eyes <= 2 else 4.0
		for i in eyes:
			var t: float = 0.0 if eyes == 1 else (float(i) / float(eyes - 1) - 0.5) * 2.0
			var ex := cx + t * spread + 1.0
			var ey := cy - 1.0 + (0.0 if eyes <= 2 else float(i % 2) * 1.6)
			_ellipse(img, ex, ey, 1.8, 1.8, Color(0.06, 0.05, 0.09, 1.0))
			_ellipse(img, ex + 0.6, ey - 0.5, 0.8, 0.8, Color(1, 1, 1, 0.9))
	elif eyes == 0:
		# Eyeless species get a mouth slit instead so the head still has a front.
		_rect(img, int(cx), int(cy) + 1, int(cx) + 5, int(cy) + 2, Color(0.05, 0.04, 0.07, 1))
	_shade(img)
	_outline(img, outline)
	return img


func _draw_limb(shape: StringName, rng: RandomNumberGenerator, col: Color, outline: Color) -> Image:
	var w := 8
	var h := 16
	var img := _img(w, h)
	var thin: float = 1.5 if shape == &"insect" or shape == &"bird" else 2.2
	var length := rng.randf_range(float(h) - 5.0, float(h) - 2.0)
	_taper(img, Vector2(float(w) * 0.5, 2.0), Vector2(float(w) * 0.5 + rng.randf_range(-1.0, 1.0), length),
		thin + 0.6, thin, col)
	if shape == &"quadruped" or shape == &"humanoid":
		_ellipse(img, float(w) * 0.5, length, 2.6, 1.6, col.darkened(0.2))
	elif shape == &"crab":
		_triangle(img, Vector2(1, length - 3), Vector2(float(w) - 1.0, length - 3),
			Vector2(float(w) * 0.5, length + 2.0), col)
	_shade(img)
	_outline(img, outline)
	return img


func _draw_wing(shape: StringName, rng: RandomNumberGenerator, col: Color, outline: Color) -> Image:
	var w := 20
	var h := 14
	var img := _img(w, h)
	var membrane := Color(col.r, col.g, col.b, 0.82)
	if shape == &"bird":
		_triangle(img, Vector2(float(w) - 2.0, 2.0), Vector2(1, float(h) * 0.5),
			Vector2(float(w) - 3.0, float(h) - 2.0), membrane)
	else:
		_ellipse(img, float(w) * 0.55, float(h) * 0.45, 8.5, 5.0, membrane)
		_taper(img, Vector2(float(w) - 2.0, float(h) * 0.5), Vector2(3, float(h) * 0.35),
			1.0, 0.6, col.darkened(0.35))
	for i in rng.randi_range(2, 3):
		var y := 3.0 + float(i) * 3.0
		_taper(img, Vector2(float(w) - 3.0, float(h) * 0.5), Vector2(3.0, y), 0.6, 0.4,
			col.darkened(0.4))
	_outline(img, outline)
	return img


func _draw_tail(shape: StringName, rng: RandomNumberGenerator, primary: Color,
		secondary: Color, outline: Color) -> Image:
	var w := 20
	var h := 12
	var img := _img(w, h)
	_taper(img, Vector2(float(w) - 2.0, float(h) * 0.5), Vector2(3.0, float(h) * 0.5 - 2.0),
		3.2, 1.0, primary)
	if shape == &"serpent" or shape == &"quadruped":
		_triangle(img, Vector2(4, float(h) * 0.5 - 5.0), Vector2(4, float(h) * 0.5 + 1.0),
			Vector2(0, float(h) * 0.5 - 2.0), secondary)
	_shade(img)
	_outline(img, outline)
	return img


func _draw_crest(spikes: int, rng: RandomNumberGenerator, col: Color, outline: Color) -> Image:
	var w := 24
	var h := 12
	var img := _img(w, h)
	var n := clampi(spikes, 1, 6)
	for i in n:
		var x := lerpf(4.0, float(w) - 4.0, float(i) / maxf(1.0, float(n - 1)))
		var tall := rng.randf_range(5.0, float(h) - 2.0)
		_triangle(img, Vector2(x - 2.0, float(h) - 1.0), Vector2(x + 2.0, float(h) - 1.0),
			Vector2(x, float(h) - 1.0 - tall), col)
	_outline(img, outline)
	return img


# ================================================================ animation
func set_state(s: StringName) -> void:
	if state == s:
		return
	state = s
	if s == ST_WINDUP:
		_windup = 0.0
	elif s == ST_ATTACK:
		_attack_timer = 0.22


func set_facing(f: int) -> void:
	facing = 1 if f >= 0 else -1


func flash(duration: float = 0.16) -> void:
	_flash = duration
	_hurt_timer = maxf(_hurt_timer, 0.22)


## 0 = in the player's plane, 1 = deep behind it. Drives the off-plane dimming
## that tells the player "this thing cannot reach you yet".
func set_dim(t: float) -> void:
	_dim = clampf(t, 0.0, 1.0)


## Telegraph glow, 0..1, used by bosses and charge attacks.
func set_telegraph(t: float) -> void:
	_telegraph = clampf(t, 0.0, 1.0)


## Emissive-looking additive tint, for glowbugs, shielders and pets.
func set_glow(g: float) -> void:
	_glow = clampf(g, 0.0, 1.0)


## Vertical squash multiplier — armoured species curl into a ball with this.
func set_squash(s: float) -> void:
	_squash = clampf(s, 0.05, 2.0)


## Stop all animation (mimics pretending to be furniture).
func set_frozen(frozen: bool) -> void:
	_frozen = frozen


## Starts the dissolve. Returns how long the caller should wait before freeing.
func begin_death() -> float:
	_death_t = 0.0
	state = ST_DEATH
	return 0.75


func is_dissolving() -> bool:
	return _death_t >= 0.0


func _process(delta: float) -> void:
	# Face the camera. Cheap early-out: the yaw only changes during a flip.
	var yaw := View.current_yaw()
	if absf(yaw - _yaw_cached) > 0.0005:
		_yaw_cached = yaw
		rotation = Vector3(0.0, yaw, 0.0)
	if _pivot == null:
		return

	_t += delta * anim_speed
	if _flash > 0.0:
		_flash -= delta
	if _hurt_timer > 0.0:
		_hurt_timer -= delta
	if _attack_timer > 0.0:
		_attack_timer -= delta
	if _death_t >= 0.0:
		_death_t += delta
		_animate_death()
		return
	_pivot.scale = Vector3(float(facing), _squash, 1.0)
	if not _frozen:
		_animate_body(delta)
	_apply_tint()


func _animate_body(_delta: float) -> void:
	var rate := 2.0
	var squash := 0.05
	var swing := 0.1
	var lean := 0.0
	match state:
		ST_WALK:
			rate = 7.0
			squash = 0.09
			swing = 0.55
		ST_RUN:
			rate = 12.0
			squash = 0.14
			swing = 0.9
			lean = 0.12
		ST_WINDUP:
			rate = 3.0
			squash = 0.02
			swing = 0.15
			_windup = minf(1.0, _windup + 0.04)
			lean = -0.26 * _windup
		ST_ATTACK:
			rate = 3.0
			swing = 0.2
			lean = 0.42 * clampf(_attack_timer / 0.22, 0.0, 1.0)
		ST_HURT:
			rate = 18.0
			squash = 0.16
			swing = 0.2
	var phase := _t * rate
	var s := sin(phase)
	var body: Sprite3D = _parts.get(&"body")
	if body != null:
		var sq := s * squash
		body.scale = Vector3(1.0 - sq, 1.0 + sq, 1.0)
		body.position = _bp(&"body") + Vector3(0.0, maxf(0.0, s) * squash * 0.35 * _unit, 0.0)
		body.rotation.z = lean
	var head: Sprite3D = _parts.get(&"head")
	if head != null:
		head.position = _bp(&"head") + Vector3(lean * 0.25 * _unit,
			sin(phase + 0.7) * squash * 0.5 * _unit, 0.0)
		head.rotation.z = lean * 1.2 + sin(phase * 0.5) * 0.04
	_swing_limb(&"limb_front", phase, swing)
	_swing_limb(&"limb_front2", phase + PI * 0.5, swing)
	_swing_limb(&"limb_back", phase + PI, swing)
	_swing_limb(&"limb_back2", phase + PI * 1.5, swing)
	var flap: float = 1.0 if state == ST_IDLE else 2.2
	_flap(&"wing_front", _t * 11.0 * flap, 0.95)
	_flap(&"wing_back", _t * 11.0 * flap + PI, 0.95)
	var tail: Sprite3D = _parts.get(&"tail")
	if tail != null:
		tail.rotation.z = sin(_t * rate * 0.6) * 0.32
	if state == ST_HURT and _hurt_timer > 0.0:
		_pivot.position.x = sin(_t * 60.0) * 0.035 * _unit
	else:
		_pivot.position.x = 0.0


func _bp(n: StringName) -> Vector3:
	return _base_pos.get(n, Vector3.ZERO)


func _swing_limb(n: StringName, phase: float, amount: float) -> void:
	var s: Sprite3D = _parts.get(n)
	if s == null:
		return
	s.rotation.z = sin(phase) * amount
	s.position = _bp(n) + Vector3(0.0, absf(cos(phase)) * amount * 0.06 * _unit, 0.0)


func _flap(n: StringName, phase: float, amount: float) -> void:
	var s: Sprite3D = _parts.get(n)
	if s == null:
		return
	s.rotation.z = sin(phase) * amount
	s.scale.y = 1.0 - absf(sin(phase)) * 0.25


func _animate_death() -> void:
	var t := clampf(_death_t / 0.75, 0.0, 1.0)
	var fade := 1.0 - t
	_pivot.scale = Vector3(float(facing) * (1.0 + t * 0.35), maxf(0.02, 1.0 - t * 1.1), 1.0)
	_pivot.position.y = -t * 0.35 * _unit
	_pivot.rotation.z = t * 0.5 * float(facing)
	for k: StringName in _parts:
		var s: Sprite3D = _parts[k]
		s.modulate = Color(1.0 + t * 0.8, 1.0 - t * 0.3, 1.0 - t * 0.6, fade)


func _apply_tint() -> void:
	var c := Color(1, 1, 1, 1)
	if _dim > 0.0:
		# Behind the play plane: desaturated, darkened, slightly blue — matching
		# how the voxel slab shader treats layers behind the player.
		c = Color(1.0 - _dim * 0.55, 1.0 - _dim * 0.5, 1.0 - _dim * 0.25, 1.0 - _dim * 0.35)
	if _telegraph > 0.0:
		c = c.lerp(Color(2.4, 1.5, 0.8, c.a), _telegraph * 0.75)
	if _flash > 0.0:
		c = Color(3.0, 1.1, 1.1, c.a)
	if _glow > 0.0:
		c = c.lerp(Color(c.r + _glow, c.g + _glow * 0.8, c.b + _glow * 0.9, c.a), 0.6)
	if c == _tint:
		return
	_tint = c
	for k: StringName in _parts:
		(_parts[k] as Sprite3D).modulate = c
