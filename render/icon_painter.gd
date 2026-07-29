## Procedural 32x32 inventory icons for `Atlas.item_icon()`.
##
## Shapes are described analytically (`_inside()` returns true for pixels inside
## the silhouette), then a shared post-pass adds the outline, the top-left key
## light and the bottom-right shade. That keeps every icon in the game visually
## consistent without a single image file.
class_name IconPainter
extends RefCounted

const SIZE := 32


## Draw the icon for `shape` in `tint`. Returns a 32x32 RGBA8 `Image`.
static func draw(shape: StringName, tint: Color, rng: RandomNumberGenerator) -> Image:
	var buf := PackedByteArray()
	buf.resize(SIZE * SIZE * 4)
	var mask := PackedByteArray()
	mask.resize(SIZE * SIZE)

	var accent := _accent_for(shape, tint)
	for y in SIZE:
		for x in SIZE:
			var u := (float(x) + 0.5) / float(SIZE)
			var v := (float(y) + 0.5) / float(SIZE)
			var hit := _inside(shape, u, v)
			if hit == 0:
				continue
			mask[y * SIZE + x] = hit
			# Key light from the top-left, shade toward the bottom-right.
			var lit := clampf(0.60 + (1.0 - u) * 0.28 + (1.0 - v) * 0.30, 0.0, 1.35)
			var c := (accent if hit == 2 else tint)
			c = Color(c.r * lit, c.g * lit, c.b * lit, 1.0)
			_put(buf, x, y, c)

	_outline(buf, mask, tint.darkened(0.65))
	_speck(buf, mask, tint, shape, rng)

	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, buf)
	return img


# ------------------------------------------------------------------ internals
static func _put(buf: PackedByteArray, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	var o := (y * SIZE + x) * 4
	buf[o] = int(clampf(c.r, 0.0, 1.0) * 255.0)
	buf[o + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
	buf[o + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
	buf[o + 3] = int(clampf(c.a, 0.0, 1.0) * 255.0)


## One-pixel dark border drawn just outside the silhouette.
static func _outline(buf: PackedByteArray, mask: PackedByteArray, line: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			if mask[y * SIZE + x] != 0:
				continue
			var near := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and mask[ny * SIZE + nx] != 0:
					near = true
					break
			if near:
				_put(buf, x, y, Color(line.r, line.g, line.b, 1.0))


## A small specular highlight so round items do not read as flat blobs.
static func _speck(buf: PackedByteArray, mask: PackedByteArray, tint: Color,
		shape: StringName, _rng: RandomNumberGenerator) -> void:
	if shape in [&"tool", &"pickaxe", &"axe", &"shovel", &"sword", &"blade", &"bow"]:
		return
	var hi := tint.lightened(0.55)
	for p: Vector2i in [Vector2i(11, 10), Vector2i(12, 10), Vector2i(11, 11)]:
		if mask[p.y * SIZE + p.x] != 0:
			_put(buf, p.x, p.y, Color(hi.r, hi.g, hi.b, 1.0))


## Secondary colour used for the "detail" parts of a shape (return 2 from
## `_inside` to select it).
static func _accent_for(shape: StringName, tint: Color) -> Color:
	match shape:
		&"pickaxe", &"axe", &"shovel", &"sword", &"blade", &"staff", &"wand", &"torch", &"arrow":
			return Color(0.45, 0.31, 0.19)   # wooden handle
		&"potion", &"flask", &"bottle":
			return Color(0.80, 0.84, 0.88)   # glass neck
		&"coin", &"currency", &"pixel":
			return tint.darkened(0.35)
		&"gun", &"chip", &"tech":
			return tint.darkened(0.45)
		&"cube", &"block":
			return tint.lightened(0.28)
		_:
			return tint.lightened(0.30)


## Distance from a point to a segment, in normalised icon space.
static func _seg(u: float, v: float, ax: float, ay: float, bx: float, by: float) -> float:
	var abx := bx - ax
	var aby := by - ay
	var l2 := abx * abx + aby * aby
	var t := 0.0
	if l2 > 0.000001:
		t = clampf(((u - ax) * abx + (v - ay) * aby) / l2, 0.0, 1.0)
	var px := ax + abx * t - u
	var py := ay + aby * t - v
	return sqrt(px * px + py * py)


## 0 = outside, 1 = body colour, 2 = accent colour.
static func _inside(shape: StringName, u: float, v: float) -> int:
	var cx := u - 0.5
	var cy := v - 0.5
	var r := sqrt(cx * cx + cy * cy)
	match shape:
		&"square":
			return 1 if (u > 0.16 and u < 0.84 and v > 0.16 and v < 0.84) else 0
		&"cube", &"block":
			# Flat-ish block: body plus a lighter top slab.
			if u < 0.16 or u > 0.84 or v < 0.18 or v > 0.86:
				return 0
			return 2 if v < 0.36 else 1
		&"circle", &"sphere", &"orb", &"ball":
			return 1 if r < 0.34 else 0
		&"ingot", &"bar":
			if v < 0.38 or v > 0.70:
				return 0
			var hw := lerpf(0.22, 0.34, (v - 0.38) / 0.32)
			return 1 if absf(cx) < hw else 0
		&"gem", &"crystal", &"shard":
			return 1 if (absf(cx) / 0.30 + absf(cy) / 0.42) < 1.0 else 0
		&"ore", &"nugget", &"rock":
			var ang := atan2(cy, cx)
			return 1 if r < 0.30 + 0.06 * sin(ang * 5.0) else 0
		&"pickaxe":
			if _seg(u, v, 0.30, 0.86, 0.66, 0.34) < 0.052:
				return 2
			# Curved head sweeping across the top.
			if v < 0.40 and v > 0.14:
				var arc := absf(sqrt((u - 0.5) * (u - 0.5) + (v - 0.62) * (v - 0.62)) - 0.40)
				if arc < 0.055 and u > 0.16 and u < 0.86:
					return 1
			return 0
		&"axe":
			if _seg(u, v, 0.32, 0.88, 0.62, 0.26) < 0.052:
				return 2
			if u > 0.52 and u < 0.90 and v > 0.12 and v < 0.52:
				var t := (v - 0.12) / 0.40
				if u < 0.90 - absf(t - 0.5) * 0.42:
					return 1
			return 0
		&"shovel", &"spade":
			if _seg(u, v, 0.36, 0.88, 0.62, 0.38) < 0.050:
				return 2
			if v < 0.40 and v > 0.10:
				var s := (v - 0.10) / 0.30
				if absf(u - 0.66) < 0.20 * (0.35 + s * 0.65):
					return 1
			return 0
		&"sword", &"blade", &"dagger":
			if _seg(u, v, 0.30, 0.86, 0.72, 0.16) < 0.052:
				return 1
			if _seg(u, v, 0.22, 0.78, 0.42, 0.94) < 0.045:
				return 2   # crossguard
			return 0
		&"bow":
			var d := absf(sqrt((u - 0.78) * (u - 0.78) + cy * cy) - 0.46)
			if d < 0.05 and u < 0.62:
				return 1
			if absf(u - 0.60) < 0.022 and v > 0.14 and v < 0.86:
				return 2   # string
			return 0
		&"gun", &"pistol", &"rifle":
			if v > 0.34 and v < 0.52 and u > 0.14 and u < 0.88:
				return 1
			if u > 0.24 and u < 0.42 and v >= 0.52 and v < 0.82:
				return 2   # grip
			return 0
		&"staff", &"wand":
			if _seg(u, v, 0.34, 0.90, 0.58, 0.34) < 0.045:
				return 2
			return 1 if sqrt((u - 0.62) * (u - 0.62) + (v - 0.24) * (v - 0.24)) < 0.17 else 0
		&"potion", &"flask", &"bottle":
			if v > 0.44 and r < 0.34:
				return 1
			if v > 0.44 and sqrt((u - 0.5) * (u - 0.5) + (v - 0.66) * (v - 0.66)) < 0.26:
				return 1
			if absf(cx) < 0.09 and v > 0.16 and v <= 0.46:
				return 2
			if absf(cx) < 0.14 and v > 0.13 and v < 0.21:
				return 2
			return 0
		&"food", &"meat":
			if sqrt(cx * cx * 1.6 + (v - 0.46) * (v - 0.46)) < 0.30:
				return 1
			if v > 0.66 and absf(cx) < 0.07:
				return 2   # bone
			return 0
		&"fruit", &"berry":
			if sqrt(cx * cx + (v - 0.56) * (v - 0.56)) < 0.30:
				return 1
			if absf(u - 0.52) < 0.035 and v > 0.14 and v < 0.30:
				return 2
			return 0
		&"seed", &"grain":
			return 1 if sqrt(cx * cx * 2.2 + cy * cy * 0.8) < 0.30 else 0
		&"coin", &"currency", &"pixel":
			if r > 0.32:
				return 0
			return 2 if r > 0.22 else 1
		&"star":
			var a2 := atan2(cy, cx) + PI * 0.5
			var rr := 0.20 + 0.16 * cos(a2 * 5.0)
			return 1 if r < rr else 0
		&"chip", &"tech", &"circuit":
			if u > 0.26 and u < 0.74 and v > 0.26 and v < 0.74:
				return 1
			# Pins on all four sides.
			if (u > 0.10 and u < 0.90 and v > 0.10 and v < 0.90):
				if (u <= 0.26 or u >= 0.74) and absf(sin(v * 22.0)) > 0.6 and v > 0.28 and v < 0.72:
					return 2
				if (v <= 0.26 or v >= 0.74) and absf(sin(u * 22.0)) > 0.6 and u > 0.28 and u < 0.72:
					return 2
			return 0
		&"helmet", &"head":
			if r < 0.34 and v < 0.56:
				return 1
			if v >= 0.44 and v < 0.62 and absf(cx) < 0.30:
				return 2 if v < 0.54 else 1
			return 0
		&"armor", &"chest", &"chestplate":
			if v < 0.24 or v > 0.84:
				return 0
			var w := 0.34 - absf(v - 0.44) * 0.18
			return 1 if absf(cx) < w else 0
		&"legs", &"boots":
			if v < 0.30 or v > 0.84:
				return 0
			if absf(cx) < 0.30 and v < 0.62:
				return 1
			return 1 if (v >= 0.62 and (absf(u - 0.34) < 0.13 or absf(u - 0.66) < 0.13)) else 0
		&"ring", &"band":
			return 1 if (r < 0.32 and r > 0.19) else 0
		&"key":
			if sqrt((u - 0.30) * (u - 0.30) + (v - 0.34) * (v - 0.34)) < 0.17:
				return 1 if sqrt((u - 0.30) * (u - 0.30) + (v - 0.34) * (v - 0.34)) > 0.08 else 0
			if _seg(u, v, 0.36, 0.44, 0.78, 0.82) < 0.040:
				return 1
			if _seg(u, v, 0.62, 0.66, 0.52, 0.80) < 0.035:
				return 2
			return 0
		&"book", &"scroll", &"note":
			if u < 0.18 or u > 0.82 or v < 0.20 or v > 0.80:
				return 0
			return 2 if absf(u - 0.5) < 0.035 else 1
		&"leaf", &"plant", &"herb":
			var lv := sqrt((u - 0.52) * (u - 0.52) * 2.4 + (v - 0.44) * (v - 0.44) * 0.9)
			if lv < 0.30:
				return 2 if absf((u - 0.52) * 1.5 + (v - 0.44)) < 0.03 else 1
			if absf(u - 0.46) < 0.035 and v > 0.56 and v < 0.86:
				return 2
			return 0
		&"dust", &"powder":
			for c: Vector3 in [Vector3(0.36, 0.40, 0.15), Vector3(0.64, 0.52, 0.13), Vector3(0.46, 0.70, 0.12)]:
				if sqrt((u - c.x) * (u - c.x) + (v - c.y) * (v - c.y)) < c.z:
					return 1
			return 0
		&"bomb", &"explosive":
			if sqrt(cx * cx + (v - 0.60) * (v - 0.60)) < 0.30:
				return 1
			if _seg(u, v, 0.56, 0.32, 0.70, 0.14) < 0.035:
				return 2
			return 0
		&"torch", &"light", &"lamp":
			if absf(u - 0.48) < 0.075 and v > 0.42:
				return 2
			return 1 if sqrt((u - 0.48) * (u - 0.48) * 1.4 + (v - 0.28) * (v - 0.28)) < 0.19 else 0
		&"arrow", &"bolt":
			if _seg(u, v, 0.28, 0.82, 0.70, 0.28) < 0.032:
				return 2
			if (u - 0.56) + (0.42 - v) > 0.0 and _seg(u, v, 0.60, 0.36, 0.82, 0.14) < 0.10:
				return 1
			return 0
		&"tool":
			if _seg(u, v, 0.28, 0.86, 0.66, 0.30) < 0.055:
				return 2
			return 1 if sqrt((u - 0.70) * (u - 0.70) + (v - 0.26) * (v - 0.26)) < 0.17 else 0
		_:
			# Rounded square fallback.
			var q := Vector2(maxf(absf(cx) - 0.24, 0.0), maxf(absf(cy) - 0.24, 0.0))
			return 1 if q.length() < 0.10 else 0
