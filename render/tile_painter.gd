## Procedural 16x16 tile painting for `Atlas`.
##
## Every `BlockType.Pattern` has its own generator here, so the project ships
## with no binary image assets: the whole texture atlas is synthesised at boot
## from each block's `color` / `color_alt` / `top_color` and a seeded RNG keyed
## on the block name, which makes the result stable across runs.
##
## All generators write into a flat RGBA8 byte buffer (`TILE*TILE*4`) that the
## atlas turns into an `Image`.
class_name AtlasPainter
extends RefCounted

const TILE := 16

## Which face of the cube a tile is being painted for.
const G_SIDE := 0
const G_TOP := 1
const G_BOTTOM := 2

## AO-free bevel strength used by the framed patterns (metal, brick, glass).
const BEVEL := 0.22


# ============================================================== buffer helpers
## A fresh, fully transparent 16x16 RGBA8 buffer.
static func new_buffer() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(TILE * TILE * 4)
	return b


## Write one pixel. Out-of-range coordinates are ignored.
static func put(buf: PackedByteArray, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return
	var o := (y * TILE + x) * 4
	buf[o] = int(clampf(c.r, 0.0, 1.0) * 255.0)
	buf[o + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
	buf[o + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
	buf[o + 3] = int(clampf(c.a, 0.0, 1.0) * 255.0)


## Write one pixel with wrapping coordinates, so patterns stay tileable.
static func put_wrap(buf: PackedByteArray, x: int, y: int, c: Color) -> void:
	put(buf, posmod(x, TILE), posmod(y, TILE), c)


## Read one pixel back.
static func get_px(buf: PackedByteArray, x: int, y: int) -> Color:
	var o := (posmod(y, TILE) * TILE + posmod(x, TILE)) * 4
	return Color(buf[o] / 255.0, buf[o + 1] / 255.0, buf[o + 2] / 255.0, buf[o + 3] / 255.0)


## Flood the whole tile with one colour.
static func fill(buf: PackedByteArray, c: Color) -> void:
	for y in TILE:
		for x in TILE:
			put(buf, x, y, c)


# =============================================================== noise helpers
## Tileable value-noise lattice of `cells` x `cells` random values.
static func noise_field(rng: RandomNumberGenerator, cells: int) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(cells * cells)
	for i in cells * cells:
		f[i] = rng.randf()
	return f


## Smoothed bilinear sample of a lattice built by `noise_field`, in tile pixels.
static func noise_at(f: PackedFloat32Array, cells: int, x: float, y: float) -> float:
	var scale := float(cells) / float(TILE)
	var fx := x * scale
	var fy := y * scale
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var x1 := posmod(x0 + 1, cells)
	var y1 := posmod(y0 + 1, cells)
	x0 = posmod(x0, cells)
	y0 = posmod(y0, cells)
	var a: float = f[y0 * cells + x0]
	var b: float = f[y0 * cells + x1]
	var c: float = f[y1 * cells + x0]
	var d: float = f[y1 * cells + x1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## Shortest wrapped distance between two tile coordinates on one axis.
static func wrap_delta(a: float, b: float) -> float:
	var d := a - b
	if d > TILE * 0.5:
		d -= TILE
	elif d < -TILE * 0.5:
		d += TILE
	return d


## Wrapped euclidean distance inside the tile.
static func wrap_dist(x: float, y: float, cx: float, cy: float) -> float:
	var dx := wrap_delta(x, cx)
	var dy := wrap_delta(y, cy)
	return sqrt(dx * dx + dy * dy)


# ================================================================ entry point
## Paint one tile. `base`/`alt` are the block's two colours, `top` is
## `BlockType.top_color` (alpha 0 when unset) and `group` is G_SIDE/G_TOP/G_BOTTOM.
static func paint(pattern: int, base: Color, alt: Color, top: Color, group: int,
		rng: RandomNumberGenerator) -> PackedByteArray:
	var buf := new_buffer()
	# The +Y face uses `top_color` when the author supplied one, except for the
	# patterns that define their own top face (grass, log).
	var b := base
	var a := alt
	if group == G_TOP and top.a > 0.0 \
			and pattern != BlockType.Pattern.GRASS_TOP and pattern != BlockType.Pattern.LOG:
		b = top
		a = top.darkened(0.28)
	match pattern:
		BlockType.Pattern.FLAT:
			_flat(buf, b, a, rng)
		BlockType.Pattern.NOISE:
			_noise(buf, b, a, rng)
		BlockType.Pattern.SPECKLE:
			_speckle(buf, b, a, rng)
		BlockType.Pattern.STRATA:
			_strata(buf, b, a, group, rng)
		BlockType.Pattern.BRICK:
			_brick(buf, b, a, rng)
		BlockType.Pattern.PLANK:
			_plank(buf, b, a, rng)
		BlockType.Pattern.ORE:
			_ore(buf, b, a, rng)
		BlockType.Pattern.CRYSTAL:
			_crystal(buf, b, a, rng)
		BlockType.Pattern.GRASS_TOP:
			_grass(buf, b, a, top, group, rng)
		BlockType.Pattern.METAL:
			_metal(buf, b, a, rng)
		BlockType.Pattern.CIRCUIT:
			_circuit(buf, b, a, rng)
		BlockType.Pattern.ORGANIC:
			_organic(buf, b, a, rng)
		BlockType.Pattern.CLOTH:
			_cloth(buf, b, a, rng)
		BlockType.Pattern.GLASS:
			_glass(buf, b, a, rng)
		BlockType.Pattern.SAND:
			_sand(buf, b, a, rng)
		BlockType.Pattern.ICE:
			_ice(buf, b, a, rng)
		BlockType.Pattern.LEAF:
			_leaf(buf, b, a, rng)
		BlockType.Pattern.LOG:
			_log(buf, b, a, top, group, rng)
		_:
			_noise(buf, b, a, rng)
	return buf


## Punch a plant silhouette into a tile so `Render.CROSS` blocks read as tufts
## and flowers instead of floating squares.
static func mask_plant(buf: PackedByteArray, rng: RandomNumberGenerator) -> void:
	# Four to six blades rising from the bottom of the tile, plus a bud.
	var keep := PackedByteArray()
	keep.resize(TILE * TILE)
	var blades := rng.randi_range(4, 6)
	for _b in blades:
		var root := rng.randf_range(2.0, 13.0)
		var lean := rng.randf_range(-3.5, 3.5)
		var height := rng.randi_range(8, 15)
		var thick := rng.randf_range(0.9, 1.7)
		for y in height:
			var t := float(y) / float(maxi(1, height - 1))
			var cx := root + lean * t * t
			var w := thick * (1.0 - t * 0.55)
			var py := TILE - 1 - y
			var x0 := floori(cx - w)
			var x1 := ceili(cx + w)
			for x in range(x0, x1 + 1):
				if x >= 0 and x < TILE and py >= 0:
					keep[py * TILE + x] = 1
	# A small bloom at the top of one blade.
	if rng.randf() < 0.55:
		var bx := rng.randi_range(4, 11)
		var by := rng.randi_range(1, 5)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy <= 4:
					var px := bx + dx
					var py := by + dy
					if px >= 0 and px < TILE and py >= 0 and py < TILE:
						keep[py * TILE + px] = 1
	for y in TILE:
		for x in TILE:
			if keep[y * TILE + x] == 0:
				put(buf, x, y, Color(0, 0, 0, 0))


# =================================================================== patterns
static func _flat(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var f := noise_field(rng, 4)
	for y in TILE:
		for x in TILE:
			var n := noise_at(f, 4, x, y) * 0.10 - 0.05
			put(buf, x, y, Color(base.r + n, base.g + n, base.b + n, base.a))
	# A whisper of the alt colour in the corners keeps large flat walls readable.
	for i in TILE:
		put(buf, i, 0, get_px(buf, i, 0).lerp(alt, 0.10))
		put(buf, 0, i, get_px(buf, 0, i).lerp(alt, 0.10))


static func _noise(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var coarse := noise_field(rng, 4)
	var fine := noise_field(rng, 8)
	for y in TILE:
		for x in TILE:
			var n := noise_at(coarse, 4, x, y) * 0.65 + noise_at(fine, 8, x, y) * 0.35
			n = clampf(n * 1.25 - 0.12, 0.0, 1.0)
			var c := base.lerp(alt, n)
			var grain := rng.randf() * 0.07 - 0.035
			put(buf, x, y, Color(c.r + grain, c.g + grain, c.b + grain, base.a))


static func _speckle(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var mid := base.lerp(alt, 0.3)
	var dark := alt.darkened(0.18)
	var light := base.lightened(0.16)
	for y in TILE:
		for x in TILE:
			var r := rng.randf()
			var c := mid
			if r < 0.20:
				c = dark
			elif r < 0.40:
				c = light
			elif r < 0.62:
				c = base
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
	# Chunky 2x2 clusters so it reads as rubble rather than TV static.
	for _i in 7:
		var cx := rng.randi_range(0, TILE - 1)
		var cy := rng.randi_range(0, TILE - 1)
		var c := dark if rng.randf() < 0.5 else light
		for dy in 2:
			for dx in 2:
				put_wrap(buf, cx + dx, cy + dy, Color(c.r, c.g, c.b, base.a))


static func _strata(buf: PackedByteArray, base: Color, alt: Color, group: int,
		rng: RandomNumberGenerator) -> void:
	# Sedimentary bands. On the +Y/-Y faces the bands become swirls instead of
	# stripes, otherwise the top of a cliff looks like a barcode.
	var f := noise_field(rng, 8)
	if group != G_SIDE:
		for y in TILE:
			for x in TILE:
				var n := noise_at(f, 8, x, y)
				var c := base.lerp(alt, clampf(n * 1.4 - 0.2, 0.0, 1.0))
				put(buf, x, y, Color(c.r, c.g, c.b, base.a))
		return
	var band_h := PackedInt32Array()
	var total := 0
	while total < TILE:
		var h: int = rng.randi_range(2, 4)
		band_h.append(h)
		total += h
	var y_at := 0
	for h: int in band_h:
		var shade := rng.randf()
		for dy in h:
			var yy := y_at + dy
			if yy >= TILE:
				break
			for x in TILE:
				var jitter := noise_at(f, 8, x, yy) * 0.22 - 0.11
				var c := base.lerp(alt, clampf(shade + jitter, 0.0, 1.0))
				# Darken the seam line, wobbling it a pixel for a natural edge.
				if dy == 0 and noise_at(f, 8, x * 1.7, yy) > 0.35:
					c = c.darkened(0.22)
				put(buf, x, yy, Color(c.r, c.g, c.b, base.a))
		y_at += h


static func _brick(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var mortar := alt.darkened(0.30).lerp(Color(0.72, 0.72, 0.70), 0.25)
	var f := noise_field(rng, 8)
	# Two 8px courses, offset by half a brick; mortar sits on the last row/column
	# of each course so the pattern tiles seamlessly in both axes.
	var tints := PackedFloat32Array()
	for _i in 4:
		tints.append(rng.randf_range(-0.10, 0.10))
	for y in TILE:
		var course := y >> 3
		for x in TILE:
			var vx := (x + course * 8) % TILE
			if (y & 7) == 7 or vx == 15:
				put(buf, x, y, Color(mortar.r, mortar.g, mortar.b, base.a))
				continue
			var brick := course * 2 + (vx >> 3)
			var t: float = tints[brick & 3] + noise_at(f, 8, x, y) * 0.16 - 0.08
			var c := base.lerp(alt, clampf(0.25 + t, 0.0, 1.0))
			# Tiny bevel inside each brick.
			if (y & 7) == 0 or vx % 8 == 0:
				c = c.lightened(BEVEL * 0.5)
			elif (y & 7) == 6:
				c = c.darkened(BEVEL * 0.4)
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))


static func _plank(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var seam := alt.darkened(0.42)
	var grain := noise_field(rng, 8)
	var tints := PackedFloat32Array()
	for _i in 4:
		tints.append(rng.randf_range(-0.12, 0.12))
	for y in TILE:
		var plank := y >> 2
		if (y & 3) == 3:
			for x in TILE:
				put(buf, x, y, Color(seam.r, seam.g, seam.b, base.a))
			continue
		for x in TILE:
			# Grain streaks run along X and barely vary in Y within one plank.
			var g := noise_at(grain, 8, x, float(plank) * 5.0 + float(y & 3) * 0.35)
			var t: float = tints[plank & 3] + (g - 0.5) * 0.45
			var c := base.lerp(alt, clampf(0.28 + t, 0.0, 1.0))
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
	# Knots and nails.
	for _i in 2:
		var kx := rng.randi_range(1, TILE - 2)
		var ky := (rng.randi_range(0, 3) << 2) + rng.randi_range(0, 2)
		var kc := alt.darkened(0.3)
		put_wrap(buf, kx, ky, Color(kc.r, kc.g, kc.b, base.a))
		put_wrap(buf, kx + 1, ky, Color(kc.r, kc.g, kc.b, base.a))


static func _ore(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	# `alt` is the host rock, `base` the ore itself. Authors usually only set
	# `color`, in which case the default alt is a darker shade, which still
	# reads as a matrix once desaturated.
	var rock := alt
	rock.s *= 0.45
	rock = rock.darkened(0.12)
	var f := noise_field(rng, 4)
	var g := noise_field(rng, 8)
	for y in TILE:
		for x in TILE:
			var n := noise_at(f, 4, x, y) * 0.6 + noise_at(g, 8, x, y) * 0.4
			var c := rock.lerp(rock.darkened(0.35), clampf(n, 0.0, 1.0))
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
	var blobs := rng.randi_range(3, 5)
	for _b in blobs:
		var cx := rng.randf_range(0.0, TILE)
		var cy := rng.randf_range(0.0, TILE)
		var r := rng.randf_range(1.9, 3.2)
		for y in TILE:
			for x in TILE:
				var d := wrap_dist(float(x) + 0.5, float(y) + 0.5, cx, cy)
				if d > r:
					continue
				var t := d / r
				var c := base.lightened(0.28 * (1.0 - t)) if t < 0.55 else base.darkened(0.18)
				put(buf, x, y, Color(c.r, c.g, c.b, base.a))


static func _crystal(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var seeds := 5
	var sx := PackedFloat32Array()
	var sy := PackedFloat32Array()
	var sv := PackedFloat32Array()
	for _i in seeds:
		sx.append(rng.randf_range(0.0, TILE))
		sy.append(rng.randf_range(0.0, TILE))
		sv.append(rng.randf_range(0.0, 1.0))
	var deep := base.darkened(0.55)
	for y in TILE:
		for x in TILE:
			var best := 1e9
			var second := 1e9
			var bi := 0
			for i in seeds:
				var d := wrap_dist(float(x) + 0.5, float(y) + 0.5, sx[i], sy[i])
				if d < best:
					second = best
					best = d
					bi = i
				elif d < second:
					second = d
			# Facet body brightens toward the seed; the cell edge is a bright
			# refractive rim, which is what sells "crystal" at 16 pixels.
			var facet: float = sv[bi]
			var c := deep.lerp(base, clampf(0.25 + facet * 0.75 - best * 0.055, 0.0, 1.0))
			var edge := second - best
			if edge < 0.9:
				c = c.lerp(base.lightened(0.75), 1.0 - edge / 0.9)
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
	# Specular sparkle.
	var px := rng.randi_range(2, TILE - 4)
	var py := rng.randi_range(2, TILE - 4)
	var spark := base.lightened(0.9)
	put_wrap(buf, px, py, Color(spark.r, spark.g, spark.b, base.a))
	put_wrap(buf, px + 1, py, Color(spark.r, spark.g, spark.b, base.a))
	put_wrap(buf, px, py + 1, Color(spark.r, spark.g, spark.b, base.a))


static func _grass(buf: PackedByteArray, base: Color, alt: Color, top: Color, group: int,
		rng: RandomNumberGenerator) -> void:
	# `base` is the soil, `top` is the living surface.
	var grass := top if top.a > 0.0 else base.lerp(Color(0.32, 0.62, 0.24), 0.85)
	if group == G_TOP:
		var f := noise_field(rng, 6)
		var g := noise_field(rng, 12)
		for y in TILE:
			for x in TILE:
				var n := noise_at(f, 6, x, y) * 0.6 + noise_at(g, 12, x, y) * 0.4
				var c := grass.darkened(0.22).lerp(grass.lightened(0.14), clampf(n * 1.3 - 0.15, 0.0, 1.0))
				put(buf, x, y, Color(c.r, c.g, c.b, 1.0))
		return
	# Soil for the side and bottom faces.
	_noise(buf, base, alt, rng)
	if group == G_BOTTOM:
		return
	# Ragged fringe of grass hanging over the top of the side faces.
	for x in TILE:
		var h := rng.randi_range(3, 6)
		for y in h:
			var t := float(y) / float(h)
			var c := grass.lightened(0.10 * (1.0 - t)).darkened(0.20 * t)
			put(buf, x, y, Color(c.r, c.g, c.b, 1.0))
		# One extra straggler pixel for a broken edge.
		if rng.randf() < 0.45:
			var c2 := grass.darkened(0.3)
			put(buf, x, h, Color(c2.r, c2.g, c2.b, 1.0))


static func _metal(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var brush := noise_field(rng, 16)
	for y in TILE:
		for x in TILE:
			# Stretch the noise along X so it reads as a brushed finish.
			var n := noise_at(brush, 16, float(x) * 0.25, float(y) * 3.0)
			var c := base.lerp(alt, clampf(0.2 + (n - 0.5) * 0.7, 0.0, 1.0))
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
	# Plate bevel: lit top/left, shaded bottom/right.
	for i in TILE:
		put(buf, i, 0, get_px(buf, i, 0).lightened(BEVEL))
		put(buf, 0, i, get_px(buf, 0, i).lightened(BEVEL * 0.7))
		put(buf, i, TILE - 1, get_px(buf, i, TILE - 1).darkened(BEVEL))
		put(buf, TILE - 1, i, get_px(buf, TILE - 1, i).darkened(BEVEL * 0.7))
	# Rivets.
	for p: Vector2i in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
		var hi := base.lightened(0.35)
		var lo := base.darkened(0.35)
		put(buf, p.x, p.y, Color(hi.r, hi.g, hi.b, base.a))
		put(buf, p.x + 1, p.y, Color(hi.r, hi.g, hi.b, base.a))
		put(buf, p.x, p.y + 1, Color(lo.r, lo.g, lo.b, base.a))
		put(buf, p.x + 1, p.y + 1, Color(lo.r, lo.g, lo.b, base.a))


static func _circuit(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var board := base.darkened(0.5)
	var f := noise_field(rng, 8)
	for y in TILE:
		for x in TILE:
			var n := noise_at(f, 8, x, y) * 0.08 - 0.04
			put(buf, x, y, Color(board.r + n, board.g + n, board.b + n, base.a))
	var trace := alt.lightened(0.35)
	var node := base.lightened(0.75)
	var lanes := [3, 8, 12]
	for lane: int in lanes:
		# Horizontal run, broken into segments so it looks routed, not ruled.
		var x := rng.randi_range(0, 5)
		while x < TILE:
			var seg := rng.randi_range(3, 7)
			for i in seg:
				if x + i < TILE:
					put(buf, x + i, lane, Color(trace.r, trace.g, trace.b, base.a))
			x += seg + rng.randi_range(1, 3)
		# Vertical stub dropping off the lane.
		var vx := rng.randi_range(1, TILE - 2)
		var vlen := rng.randi_range(2, 5)
		var dir := 1 if rng.randf() < 0.5 else -1
		for i in vlen:
			put_wrap(buf, vx, lane + dir * i, Color(trace.r, trace.g, trace.b, base.a))
		# Pad at the end of the stub.
		put_wrap(buf, vx, lane + dir * vlen, Color(node.r, node.g, node.b, base.a))
		put_wrap(buf, vx + 1, lane + dir * vlen, Color(node.r, node.g, node.b, base.a))
	# Two glowing vias.
	for _i in 2:
		var cx := rng.randi_range(1, TILE - 2)
		var cy := rng.randi_range(1, TILE - 2)
		for dy in 2:
			for dx in 2:
				put_wrap(buf, cx + dx, cy + dy, Color(node.r, node.g, node.b, base.a))


static func _organic(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var seeds := 7
	var sx := PackedFloat32Array()
	var sy := PackedFloat32Array()
	var sv := PackedFloat32Array()
	for _i in seeds:
		sx.append(rng.randf_range(0.0, TILE))
		sy.append(rng.randf_range(0.0, TILE))
		sv.append(rng.randf_range(0.0, 1.0))
	var wall := alt.darkened(0.35)
	for y in TILE:
		for x in TILE:
			var best := 1e9
			var second := 1e9
			var bi := 0
			for i in seeds:
				var d := wrap_dist(float(x) + 0.5, float(y) + 0.5, sx[i], sy[i])
				if d < best:
					second = best
					best = d
					bi = i
				elif d < second:
					second = d
			var c := base.lerp(alt, sv[bi] * 0.8)
			c = c.lightened(0.14 * clampf(1.0 - best * 0.28, 0.0, 1.0))
			if second - best < 0.8:
				c = wall
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
	# Darker pores.
	for _i in 5:
		var px := rng.randi_range(0, TILE - 1)
		var py := rng.randi_range(0, TILE - 1)
		var c2 := alt.darkened(0.45)
		put_wrap(buf, px, py, Color(c2.r, c2.g, c2.b, base.a))


static func _cloth(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var f := noise_field(rng, 16)
	for y in TILE:
		for x in TILE:
			var warp := (x >> 1) & 1
			var weft := (y >> 1) & 1
			var c := base if warp == weft else base.lerp(alt, 0.55)
			# Thread shading inside each 2px strand.
			if warp == weft:
				if (y & 1) == 0:
					c = c.lightened(0.10)
				else:
					c = c.darkened(0.08)
			else:
				if (x & 1) == 0:
					c = c.lightened(0.08)
				else:
					c = c.darkened(0.10)
			var n := noise_at(f, 16, x, y) * 0.06 - 0.03
			put(buf, x, y, Color(c.r + n, c.g + n, c.b + n, base.a))
	# A darker hem every 8 pixels keeps large cloth walls from moiring.
	for i in TILE:
		put(buf, i, 7, get_px(buf, i, 7).darkened(0.16))
		put(buf, 7, i, get_px(buf, 7, i).darkened(0.10))


static func _glass(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	# Glass authored with an opaque colour still has to be see-through.
	var body_a: float = base.a if base.a < 0.95 else 0.30
	var frame_a: float = clampf(body_a + 0.45, 0.0, 1.0)
	var f := noise_field(rng, 4)
	for y in TILE:
		for x in TILE:
			var n := noise_at(f, 4, x, y) * 0.05 - 0.025
			put(buf, x, y, Color(base.r + n, base.g + n, base.b + n, body_a))
	var frame := base.lightened(0.35)
	for i in TILE:
		put(buf, i, 0, Color(frame.r, frame.g, frame.b, frame_a))
		put(buf, i, TILE - 1, Color(frame.r, frame.g, frame.b, frame_a))
		put(buf, 0, i, Color(frame.r, frame.g, frame.b, frame_a))
		put(buf, TILE - 1, i, Color(frame.r, frame.g, frame.b, frame_a))
	# Diagonal reflection streak.
	var sheen := base.lightened(0.8)
	for i in range(2, 12):
		put(buf, i, 13 - i, Color(sheen.r, sheen.g, sheen.b, clampf(body_a + 0.28, 0.0, 1.0)))
		put(buf, i + 1, 13 - i, Color(sheen.r, sheen.g, sheen.b, clampf(body_a + 0.14, 0.0, 1.0)))
	# A couple of hairline scratches in the alt colour.
	var sc := alt.lightened(0.2)
	for _i in 2:
		var x0 := rng.randi_range(2, TILE - 5)
		var y0 := rng.randi_range(2, TILE - 5)
		for i in 3:
			put(buf, x0 + i, y0 + i, Color(sc.r, sc.g, sc.b, clampf(body_a + 0.12, 0.0, 1.0)))


static func _sand(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var f := noise_field(rng, 8)
	for y in TILE:
		for x in TILE:
			# Gentle ripples plus a fine dithered grain.
			var ripple := sin((float(y) + noise_at(f, 8, x, y) * 3.0) * 1.25) * 0.5 + 0.5
			var n := clampf(ripple * 0.45 + rng.randf() * 0.55, 0.0, 1.0)
			var c := base.lerp(alt, n * 0.55)
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
	# Scattered coarse grains.
	for _i in 12:
		var px := rng.randi_range(0, TILE - 1)
		var py := rng.randi_range(0, TILE - 1)
		var c2 := alt.darkened(0.22)
		put(buf, px, py, Color(c2.r, c2.g, c2.b, base.a))


static func _ice(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var body_a: float = base.a if base.a < 0.95 else 0.78
	var f := noise_field(rng, 4)
	for y in TILE:
		for x in TILE:
			var n := noise_at(f, 4, x, y)
			var c := base.lerp(base.lightened(0.35), n)
			put(buf, x, y, Color(c.r, c.g, c.b, body_a))
	# Cracks: short random walks in a brighter tint.
	var crack := alt.lightened(0.55)
	for _i in 3:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		var steps := rng.randi_range(5, 11)
		for _s in steps:
			put_wrap(buf, x, y, Color(crack.r, crack.g, crack.b, clampf(body_a + 0.15, 0.0, 1.0)))
			if rng.randf() < 0.5:
				x += 1 if rng.randf() < 0.5 else -1
			else:
				y += 1 if rng.randf() < 0.5 else -1
	# Corner sheen.
	for y in 4:
		for x in 4 - y:
			var c3 := base.lightened(0.55)
			put(buf, x, y, Color(c3.r, c3.g, c3.b, clampf(body_a + 0.1, 0.0, 1.0)))


static func _leaf(buf: PackedByteArray, base: Color, alt: Color, rng: RandomNumberGenerator) -> void:
	var f := noise_field(rng, 6)
	var g := noise_field(rng, 12)
	for y in TILE:
		for x in TILE:
			var n := noise_at(f, 6, x, y) * 0.55 + noise_at(g, 12, x, y) * 0.45
			var c := alt.darkened(0.15).lerp(base.lightened(0.12), clampf(n * 1.35 - 0.18, 0.0, 1.0))
			# Punch gaps so canopies read as foliage rather than green stone.
			var a: float = base.a if n > 0.24 else 0.0
			put(buf, x, y, Color(c.r, c.g, c.b, a))
	# Darker veins.
	for _i in 3:
		var x0 := rng.randi_range(0, TILE - 1)
		var y0 := rng.randi_range(0, TILE - 1)
		var vein := rng.randi_range(3, 6)
		var dx := 1 if rng.randf() < 0.5 else -1
		for i in vein:
			var px := x0 + dx * i
			var py := y0 + i
			if get_px(buf, px, py).a > 0.0:
				var c2 := alt.darkened(0.4)
				put_wrap(buf, px, py, Color(c2.r, c2.g, c2.b, base.a))


static func _log(buf: PackedByteArray, base: Color, alt: Color, top: Color, group: int,
		rng: RandomNumberGenerator) -> void:
	if group == G_SIDE:
		# Bark: vertical grooves.
		var f := noise_field(rng, 16)
		for x in TILE:
			var groove := noise_at(f, 16, float(x) * 2.0, 0.0)
			for y in TILE:
				var n := noise_at(f, 16, float(x) * 2.0, float(y) * 0.3)
				var t := clampf(groove * 0.6 + n * 0.4, 0.0, 1.0)
				var c := base.lerp(alt, t)
				put(buf, x, y, Color(c.r, c.g, c.b, base.a))
		var deep := alt.darkened(0.4)
		for _i in 3:
			var cx := rng.randi_range(0, TILE - 1)
			for y in TILE:
				put_wrap(buf, cx + (1 if (y & 7) > 4 else 0), y, Color(deep.r, deep.g, deep.b, base.a))
		return
	# End grain: concentric rings around the centre of the tile.
	var core := top if top.a > 0.0 else base.lightened(0.25)
	var bark := alt.darkened(0.25)
	var jitter := noise_field(rng, 8)
	for y in TILE:
		for x in TILE:
			var d := wrap_dist(float(x) + 0.5, float(y) + 0.5, 8.0, 8.0)
			d += noise_at(jitter, 8, x, y) * 0.9 - 0.45
			if d > 6.6:
				put(buf, x, y, Color(bark.r, bark.g, bark.b, base.a))
				continue
			var ring := sin(d * 2.35) * 0.5 + 0.5
			var c := core.lerp(base.darkened(0.18), clampf(ring, 0.0, 1.0))
			put(buf, x, y, Color(c.r, c.g, c.b, base.a))
