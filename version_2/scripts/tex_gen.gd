class_name TexGen
extends RefCounted

## Every texture in the game is synthesised here at boot, so the project has no
## binary art dependencies. Everything is authored at 16px so it reads as chunky
## pixel art under the HD-2D lighting.

const TILE := 16
## The first 28 slots are the hand-painted originals; the rest are synthesised
## from each block's (pattern, colour, alt colour) at boot, so a content file can
## add a block without anyone hand-drawing a texture for it.
const ATLAS_COLS := 20
const ATLAS_ROWS := 20
const ATLAS_W := TILE * ATLAS_COLS   # 320
const ATLAS_H := TILE * ATLAS_ROWS   # 320
const ATLAS_CAPACITY := ATLAS_COLS * ATLAS_ROWS


static func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


# ---------------------------------------------------------------- tile painters

static func _speckle(img: Image, ox: int, oy: int, base: Color, amount: float, seed_v: int, density := 1.0) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			var f := 1.0
			if r.randf() < density:
				f = 1.0 + r.randf_range(-amount, amount)
			img.set_pixel(ox + x, oy + y, _shade(base, f))


static func _blotches(img: Image, ox: int, oy: int, c: Color, count: int, radius: float, seed_v: int) -> void:
	var r := _rng(seed_v)
	for i in count:
		var cx := r.randf_range(1.0, TILE - 2.0)
		var cy := r.randf_range(1.0, TILE - 2.0)
		var rad := radius * r.randf_range(0.7, 1.3)
		for y in TILE:
			for x in TILE:
				var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
				if d < rad:
					var f := 1.0 + r.randf_range(-0.1, 0.1)
					img.set_pixel(ox + x, oy + y, _shade(c, f))


static func _bricks(img: Image, ox: int, oy: int, base: Color, mortar: Color, rows: int, seed_v: int) -> void:
	var r := _rng(seed_v)
	var rh := TILE / rows
	for y in TILE:
		for x in TILE:
			var row := y / rh
			var offset := (row % 2) * (TILE / 2)
			var lx := (x + offset) % TILE
			var is_mortar := (y % rh == 0) or (lx % (TILE / 2) == 0)
			var c := mortar if is_mortar else _shade(base, 1.0 + r.randf_range(-0.09, 0.09))
			# fake bevel
			if not is_mortar and (y % rh == 1):
				c = _shade(c, 1.16)
			if not is_mortar and (y % rh == rh - 1):
				c = _shade(c, 0.84)
			img.set_pixel(ox + x, oy + y, c)


static func _planks(img: Image, ox: int, oy: int, base: Color, seam: Color, band: int, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		var row_tone := 1.0 + (0.07 * float((y / band) % 3 - 1))
		for x in TILE:
			var c := _shade(base, row_tone + r.randf_range(-0.05, 0.05))
			if y % band == 0:
				c = seam
			# knots / grain
			if (x * 7 + y * 3) % 23 == 0:
				c = _shade(c, 0.86)
			img.set_pixel(ox + x, oy + y, c)


static func _vertical_grain(img: Image, ox: int, oy: int, base: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for x in TILE:
		var tone := 1.0 + r.randf_range(-0.16, 0.16)
		for y in TILE:
			img.set_pixel(ox + x, oy + y, _shade(base, tone + r.randf_range(-0.04, 0.04)))


static func _rings(img: Image, ox: int, oy: int, base: Color, dark: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 7.5, y - 7.5).length()
			var band := int(d) % 3
			var c := base if band != 0 else dark
			img.set_pixel(ox + x, oy + y, _shade(c, 1.0 + r.randf_range(-0.06, 0.06)))


static func _grass_top_edge(img: Image, ox: int, oy: int, dirt: Color, grass: Color, seed_v: int) -> void:
	## dirt side with a ragged band of grass along the top edge
	var r := _rng(seed_v)
	_speckle(img, ox, oy, dirt, 0.14, seed_v)
	for x in TILE:
		var h := 3 + r.randi_range(0, 2)
		for y in h:
			img.set_pixel(ox + x, oy + y, _shade(grass, 1.0 + r.randf_range(-0.12, 0.12)))
		img.set_pixel(ox + x, oy + h, _shade(grass, 0.72))


static func _ore(img: Image, ox: int, oy: int, stone: Color, ore: Color, glow: Color, seed_v: int) -> void:
	_speckle(img, ox, oy, stone, 0.13, seed_v)
	var r := _rng(seed_v + 991)
	for i in 5:
		var cx := r.randi_range(2, TILE - 4)
		var cy := r.randi_range(2, TILE - 4)
		var w := r.randi_range(2, 3)
		var h := r.randi_range(2, 3)
		for y in h:
			for x in w:
				img.set_pixel(ox + cx + x, oy + cy + y, _shade(ore, 1.0 + r.randf_range(-0.1, 0.1)))
		img.set_pixel(ox + cx, oy + cy, glow)


static func _glass_tile(img: Image, ox: int, oy: int, frame: Color, pane: Color) -> void:
	for y in TILE:
		for x in TILE:
			var edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			var cross := x == TILE / 2 or y == TILE / 2
			var c := pane
			if cross:
				c = _shade(frame, 0.85)
			if edge:
				c = frame
			# diagonal highlight streak
			if not edge and not cross and absi(x - y) < 2:
				c = Color(c.r + 0.22, c.g + 0.24, c.b + 0.26, minf(c.a + 0.22, 1.0))
			img.set_pixel(ox + x, oy + y, c)


static func _lamp_tile(img: Image, ox: int, oy: int, frame: Color, core: Color) -> void:
	for y in TILE:
		for x in TILE:
			var d := maxi(absi(x - 8), absi(y - 8))
			var c: Color
			if d >= 7:
				c = frame
			elif d >= 5:
				c = _shade(frame, 1.35)
			else:
				var t := 1.0 - float(d) / 5.0
				c = core.lerp(Color(1.0, 0.98, 0.86), t * 0.7)
			img.set_pixel(ox + x, oy + y, c)


static func _crystal_tile(img: Image, ox: int, oy: int, dark: Color, bright: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			var v := absf(sin(float(x) * 0.9 + float(y) * 0.35)) * 0.5 + absf(cos(float(y) * 0.8)) * 0.5
			var c := dark.lerp(bright, clampf(v, 0.0, 1.0))
			img.set_pixel(ox + x, oy + y, _shade(c, 1.0 + r.randf_range(-0.06, 0.06)))


static func _roof_tile(img: Image, ox: int, oy: int, base: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			var row := y / 4
			var off := (row % 2) * 4
			var lx := (x + off) % 8
			var t := 1.0 - float(y % 4) * 0.12
			var c := _shade(base, t + r.randf_range(-0.05, 0.05))
			if lx == 0 or y % 4 == 0:
				c = _shade(base, 0.55)
			img.set_pixel(ox + x, oy + y, c)


static func _leaves_tile(img: Image, ox: int, oy: int, seed_v: int) -> void:
	var r := _rng(seed_v)
	var deep := Color(0.129, 0.259, 0.153)
	var mid := Color(0.212, 0.412, 0.216)
	var lit := Color(0.337, 0.561, 0.263)
	for y in TILE:
		for x in TILE:
			var v := r.randf()
			var c := mid
			if v < 0.30:
				c = deep
			elif v > 0.80:
				c = lit
			# clumping
			if (x / 3 + y / 3) % 2 == 0:
				c = _shade(c, 0.88)
			img.set_pixel(ox + x, oy + y, c)


# ---------------------------------------------------------------------- atlas

static func build_atlas() -> ImageTexture:
	var img := Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var slot := func(i: int) -> Vector2i:
		return Vector2i((i % ATLAS_COLS) * TILE, (i / ATLAS_COLS) * TILE)

	var p: Vector2i

	p = slot.call(Blocks.T_GRASS_TOP)
	_speckle(img, p.x, p.y, Color(0.294, 0.510, 0.239), 0.18, 11)
	_blotches(img, p.x, p.y, Color(0.365, 0.588, 0.278), 6, 2.2, 12)

	p = slot.call(Blocks.T_GRASS_SIDE)
	_grass_top_edge(img, p.x, p.y, Color(0.361, 0.259, 0.176), Color(0.310, 0.522, 0.243), 13)

	p = slot.call(Blocks.T_DIRT)
	_speckle(img, p.x, p.y, Color(0.361, 0.259, 0.176), 0.18, 14)
	_blotches(img, p.x, p.y, Color(0.302, 0.212, 0.141), 5, 2.0, 15)

	p = slot.call(Blocks.T_STONE)
	_speckle(img, p.x, p.y, Color(0.451, 0.443, 0.478), 0.13, 16)
	_blotches(img, p.x, p.y, Color(0.396, 0.388, 0.427), 5, 2.6, 17)

	p = slot.call(Blocks.T_COBBLE)
	_speckle(img, p.x, p.y, Color(0.412, 0.404, 0.439), 0.10, 18)
	_blotches(img, p.x, p.y, Color(0.510, 0.502, 0.541), 7, 2.4, 19)
	_blotches(img, p.x, p.y, Color(0.298, 0.290, 0.325), 6, 1.4, 20)

	p = slot.call(Blocks.T_SAND)
	_speckle(img, p.x, p.y, Color(0.808, 0.714, 0.510), 0.10, 21)

	p = slot.call(Blocks.T_LOG_SIDE)
	_vertical_grain(img, p.x, p.y, Color(0.365, 0.251, 0.153), 22)

	p = slot.call(Blocks.T_LOG_TOP)
	_rings(img, p.x, p.y, Color(0.545, 0.412, 0.267), Color(0.396, 0.286, 0.176), 23)

	p = slot.call(Blocks.T_LEAVES)
	_leaves_tile(img, p.x, p.y, 24)

	p = slot.call(Blocks.T_PLANKS)
	_planks(img, p.x, p.y, Color(0.596, 0.443, 0.278), Color(0.420, 0.298, 0.176), 4, 25)

	p = slot.call(Blocks.T_GLASS)
	_glass_tile(img, p.x, p.y, Color(0.780, 0.855, 0.898, 0.85), Color(0.573, 0.741, 0.816, 0.24))

	p = slot.call(Blocks.T_LAMP)
	_lamp_tile(img, p.x, p.y, Color(0.278, 0.196, 0.129), Color(1.0, 0.694, 0.290))

	p = slot.call(Blocks.T_COAL)
	_ore(img, p.x, p.y, Color(0.451, 0.443, 0.478), Color(0.114, 0.110, 0.129), Color(0.204, 0.196, 0.220), 26)

	p = slot.call(Blocks.T_IRON)
	_ore(img, p.x, p.y, Color(0.451, 0.443, 0.478), Color(0.741, 0.549, 0.400), Color(0.902, 0.741, 0.573), 27)

	p = slot.call(Blocks.T_CRYSTAL_ORE)
	_ore(img, p.x, p.y, Color(0.408, 0.400, 0.451), Color(0.400, 0.855, 0.898), Color(0.780, 0.988, 1.0), 28)

	p = slot.call(Blocks.T_SNOW)
	_speckle(img, p.x, p.y, Color(0.898, 0.925, 0.965), 0.05, 29)

	p = slot.call(Blocks.T_BRICK)
	_bricks(img, p.x, p.y, Color(0.545, 0.259, 0.208), Color(0.741, 0.694, 0.639), 4, 30)

	p = slot.call(Blocks.T_BEDROCK)
	_speckle(img, p.x, p.y, Color(0.180, 0.176, 0.200), 0.35, 31)

	p = slot.call(Blocks.T_MOSSY)
	_speckle(img, p.x, p.y, Color(0.353, 0.400, 0.322), 0.13, 32)
	_blotches(img, p.x, p.y, Color(0.235, 0.353, 0.212), 6, 2.2, 33)

	p = slot.call(Blocks.T_CRYSTAL)
	_crystal_tile(img, p.x, p.y, Color(0.153, 0.353, 0.478), Color(0.678, 0.949, 1.0), 34)

	p = slot.call(Blocks.T_DARK_PLANKS)
	_planks(img, p.x, p.y, Color(0.318, 0.216, 0.145), Color(0.212, 0.141, 0.094), 4, 35)

	p = slot.call(Blocks.T_ROOF)
	_roof_tile(img, p.x, p.y, Color(0.443, 0.212, 0.204), 36)

	p = slot.call(Blocks.T_STONE_BRICK)
	_bricks(img, p.x, p.y, Color(0.478, 0.467, 0.478), Color(0.318, 0.310, 0.325), 4, 37)

	p = slot.call(Blocks.T_ICE)
	_speckle(img, p.x, p.y, Color(0.667, 0.847, 0.925, 0.70), 0.08, 38)

	p = slot.call(Blocks.T_GRAVEL)
	_speckle(img, p.x, p.y, Color(0.463, 0.427, 0.400), 0.22, 39)
	_blotches(img, p.x, p.y, Color(0.353, 0.325, 0.302), 8, 1.6, 40)

	p = slot.call(Blocks.T_CLAY)
	_speckle(img, p.x, p.y, Color(0.639, 0.588, 0.573), 0.08, 41)

	p = slot.call(Blocks.T_OBSIDIAN)
	_speckle(img, p.x, p.y, Color(0.114, 0.086, 0.153), 0.22, 42)
	_blotches(img, p.x, p.y, Color(0.216, 0.145, 0.290), 4, 1.8, 43)

	p = slot.call(Blocks.T_MUD)
	_speckle(img, p.x, p.y, Color(0.275, 0.220, 0.180), 0.16, 44)

	# --- everything the content files added, painted from its pattern
	var salt := 700
	for spec: Dictionary in Blocks.synth_tiles():
		var index: int = spec["index"]
		if index >= ATLAS_CAPACITY:
			push_error("TexGen: atlas full at tile %d; raise ATLAS_ROWS." % index)
			break
		p = slot.call(index)
		paint_pattern(img, p.x, p.y, int(spec["pattern"]), spec["color"],
			spec["alt"], salt)
		salt += 37

	var tex := ImageTexture.create_from_image(img)
	return tex


# ------------------------------------------------------- synthesised patterns

## Paint one 16px tile in `pattern` using `base` and `alt`. This is the whole
## vocabulary the block content files draw from.
static func paint_pattern(img: Image, ox: int, oy: int, pattern: int,
		base: Color, alt: Color, seed_v: int) -> void:
	match pattern:
		Blocks.Pattern.FLAT:
			_flat(img, ox, oy, base, alt)
		Blocks.Pattern.NOISE:
			_speckle(img, ox, oy, base, 0.16, seed_v)
			_blotches(img, ox, oy, alt, 5, 2.2, seed_v + 1)
		Blocks.Pattern.SPECKLE:
			_speckle(img, ox, oy, base, 0.10, seed_v)
			_blotches(img, ox, oy, alt, 7, 1.5, seed_v + 2)
			_blotches(img, ox, oy, base.lightened(0.14), 5, 1.2, seed_v + 3)
		Blocks.Pattern.STRATA:
			_strata(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.BRICK:
			_bricks(img, ox, oy, base, alt, 4, seed_v)
		Blocks.Pattern.PLANK:
			_planks(img, ox, oy, base, alt, 4, seed_v)
		Blocks.Pattern.ORE:
			_ore(img, ox, oy, base, alt, alt.lightened(0.35), seed_v)
		Blocks.Pattern.CRYSTAL:
			_crystal_tile(img, ox, oy, base, alt.lightened(0.25), seed_v)
		Blocks.Pattern.GRASS_TOP:
			_grass_top_edge(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.METAL:
			_metal(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.CIRCUIT:
			_circuit(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.ORGANIC:
			_organic(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.CLOTH:
			_cloth(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.GLASS:
			_glass_tile(img, ox, oy, base.lightened(0.25), base)
		Blocks.Pattern.SAND:
			_speckle(img, ox, oy, base, 0.11, seed_v)
			_blotches(img, ox, oy, alt, 4, 1.1, seed_v + 4)
		Blocks.Pattern.ICE:
			_ice(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.LEAF:
			_leaf_tinted(img, ox, oy, base, alt, seed_v)
		Blocks.Pattern.LOG:
			_vertical_grain(img, ox, oy, base, seed_v)
		_:
			_speckle(img, ox, oy, base, 0.14, seed_v)


static func _flat(img: Image, ox: int, oy: int, base: Color, alt: Color) -> void:
	for y in TILE:
		for x in TILE:
			var edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			img.set_pixel(ox + x, oy + y, alt if edge else base)


## Sedimentary banding, which is what sells a cross-section wall.
static func _strata(img: Image, ox: int, oy: int, base: Color, alt: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	var bands := PackedFloat32Array()
	for i in TILE:
		bands.append(r.randf())
	for y in TILE:
		var t: float = bands[y]
		var c := base.lerp(alt, t * 0.75)
		for x in TILE:
			var j := 1.0 + r.randf_range(-0.05, 0.05)
			# a couple of pixels of horizontal wobble so the bands are not rulers
			if (x + int(bands[y] * 5.0)) % 7 == 0:
				j *= 0.92
			img.set_pixel(ox + x, oy + y, _shade(c, j))


static func _metal(img: Image, ox: int, oy: int, base: Color, alt: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			var c := base
			var edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			if edge:
				c = alt
			elif x == 1 or y == 1:
				c = base.lightened(0.16)
			elif x == TILE - 2 or y == TILE - 2:
				c = alt.lerp(base, 0.5)
			img.set_pixel(ox + x, oy + y, _shade(c, 1.0 + r.randf_range(-0.03, 0.03)))
	# rivets in the corners
	for pair in [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 12), Vector2i(12, 12)]:
		img.set_pixel(ox + pair.x, oy + pair.y, alt.darkened(0.3))
		img.set_pixel(ox + pair.x, oy + pair.y - 1, base.lightened(0.3))


static func _circuit(img: Image, ox: int, oy: int, base: Color, trace: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			img.set_pixel(ox + x, oy + y, _shade(base, 1.0 + r.randf_range(-0.07, 0.07)))
	# a few orthogonal traces with pads at the turns
	for i in 3:
		var y := 2 + i * 5 + r.randi_range(0, 1)
		var x0 := r.randi_range(0, 5)
		var x1 := r.randi_range(9, 15)
		for x in range(x0, x1 + 1):
			img.set_pixel(ox + x, oy + y, trace)
		var vx: int = x1
		var dir := 1 if i % 2 == 0 else -1
		for k in 3:
			var yy := y + dir * k
			if yy >= 0 and yy < TILE:
				img.set_pixel(ox + vx, oy + yy, trace)
		img.set_pixel(ox + x0, oy + y, trace.lightened(0.4))
		img.set_pixel(ox + vx, oy + y, trace.lightened(0.4))


static func _organic(img: Image, ox: int, oy: int, base: Color, alt: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			# lumpy cell structure: distance to the nearest of a few seed points
			var v := absf(sin(float(x) * 0.7 + float(y) * 0.4 + float(seed_v % 7)))
			v = v * 0.6 + r.randf() * 0.4
			var c := base.lerp(alt, clampf(v, 0.0, 1.0) * 0.8)
			img.set_pixel(ox + x, oy + y, c)


static func _cloth(img: Image, ox: int, oy: int, base: Color, alt: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			var weave := ((x / 2) + (y / 2)) % 2 == 0
			var c := base if weave else alt
			img.set_pixel(ox + x, oy + y, _shade(c, 1.0 + r.randf_range(-0.05, 0.05)))


static func _ice(img: Image, ox: int, oy: int, base: Color, alt: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	for y in TILE:
		for x in TILE:
			var c := base
			# long shallow fracture lines
			if (x * 3 + y * 5) % 19 < 2:
				c = alt.lightened(0.25)
			elif (x - y + 16) % 11 == 0:
				c = alt
			img.set_pixel(ox + x, oy + y, _shade(c, 1.0 + r.randf_range(-0.04, 0.04)))


static func _leaf_tinted(img: Image, ox: int, oy: int, base: Color, alt: Color, seed_v: int) -> void:
	var r := _rng(seed_v)
	var lit := base.lightened(0.22)
	for y in TILE:
		for x in TILE:
			var v := r.randf()
			var c := base
			if v < 0.30:
				c = alt
			elif v > 0.80:
				c = lit
			if (x / 3 + y / 3) % 2 == 0:
				c = _shade(c, 0.88)
			# punch a few holes so canopies read as foliage, not as a green cube
			if v > 0.965:
				c.a = 0.0
			img.set_pixel(ox + x, oy + y, c)


# ---------------------------------------------------------------- item icons

const ICON := 16

## Shape families. Every `shape` name a content file can use maps onto one of
## these silhouettes, so adding an item never needs new art.
const ICON_FAMILY := {
	# blocky
	&"cube": 0, &"ore_cube": 0, &"pane": 0, &"plate": 0, &"square": 0,
	&"chip": 0, &"card": 0, &"scroll": 0, &"paper": 0, &"cloth": 0, &"hide": 0,
	# round
	&"round": 1, &"orb": 1, &"gem": 1, &"blob": 1, &"lump": 1, &"cell": 1,
	&"seed": 1, &"puff": 1, &"disc": 1, &"chunk": 1, &"relic": 1, &"gear": 1,
	# bar / rod
	&"bar": 2, &"rod": 2, &"coil": 2, &"strand": 2, &"plank": 2, &"log": 2,
	&"beam": 2, &"stick": 2,
	# shard / claw
	&"shard": 3, &"claw": 3, &"fang": 3, &"bone": 3,
	# dust
	&"dust": 4,
	# vial
	&"vial": 5, &"flask": 5,
	# tools
	&"pick": 6, &"pickaxe": 6, &"axe": 6, &"shovel": 6, &"hoe": 6, &"drill": 6,
	&"brush": 6, &"probe": 6, &"lens": 6, &"hook": 6, &"lamp": 6, &"key": 6,
	# blades
	&"sword": 7, &"dagger": 7, &"spear": 7, &"staff": 7, &"whip": 7,
	# heavy / ranged
	&"hammer": 8, &"bow": 8, &"gun": 8, &"shield": 8,
	# armour
	&"helm": 9, &"chest": 9, &"greaves": 9,
	# foliage
	&"sprig": 10,
}


## A 16px item icon, drawn from a shape family and tinted by the item's colour.
static func build_item_icon(shape: StringName, col: Color) -> ImageTexture:
	var img := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := _shade(col, 0.55)
	var lit := _shade(col, 1.35)
	var family: int = ICON_FAMILY.get(shape, 1)
	match family:
		0: _ico_block(img, col, dark, lit, shape)
		1: _ico_round(img, col, dark, lit, shape)
		2: _ico_bar(img, col, dark, lit)
		3: _ico_shard(img, col, dark, lit)
		4: _ico_dust(img, col, dark, lit)
		5: _ico_vial(img, col, dark, lit)
		6: _ico_tool(img, col, dark, lit, shape)
		7: _ico_blade(img, col, dark, lit, shape)
		8: _ico_heavy(img, col, dark, lit, shape)
		9: _ico_armor(img, col, dark, lit, shape)
		_: _ico_sprig(img, col, dark, lit)
	return ImageTexture.create_from_image(img)


static func _ico_block(img: Image, col: Color, dark: Color, lit: Color, shape: StringName) -> void:
	# a flat cube face with a lit top edge and a shaded bottom
	_rect(img, 2, 3, 12, 11, col)
	_rect(img, 2, 3, 12, 2, lit)
	_rect(img, 2, 12, 12, 2, dark)
	_rect(img, 2, 3, 1, 11, lit)
	_rect(img, 13, 3, 1, 11, dark)
	if shape == &"ore_cube":
		for p in [Vector2i(5, 6), Vector2i(9, 7), Vector2i(6, 10), Vector2i(10, 11)]:
			_rect(img, p.x, p.y, 2, 2, lit)
			_px(img, p.x, p.y, Color(1, 1, 1, 0.85))
	elif shape == &"chip" or shape == &"card":
		for x in range(3, 13, 3):
			_rect(img, x, 6, 1, 5, dark)
	elif shape == &"scroll" or shape == &"paper":
		for y in range(5, 12, 2):
			_rect(img, 4, y, 8, 1, dark)


static func _ico_round(img: Image, col: Color, dark: Color, lit: Color, shape: StringName) -> void:
	var r := 5.6
	for y in ICON:
		for x in ICON:
			var d := Vector2(x - 7.5, y - 8.0).length()
			if d <= r:
				var c := col
				if d > r - 1.4:
					c = dark
				elif x - y < -3:
					c = lit
				_px(img, x, y, c)
	if shape == &"gem":
		# facet lines
		for i in 5:
			_px(img, 7 - i, 8 - i, lit)
			_px(img, 8 + i, 8 - i, lit)
	elif shape == &"gear":
		for p in [Vector2i(7, 1), Vector2i(7, 13), Vector2i(1, 7), Vector2i(13, 7)]:
			_rect(img, p.x, p.y, 2, 2, col)
		_rect(img, 6, 7, 3, 3, Color(0, 0, 0, 0))


static func _ico_bar(img: Image, col: Color, dark: Color, lit: Color) -> void:
	for i in 10:
		_rect(img, 2 + i, 10 - i, 4, 4, col)
	for i in 10:
		_px(img, 2 + i, 10 - i, lit)
		_px(img, 5 + i, 13 - i, dark)


static func _ico_shard(img: Image, col: Color, dark: Color, lit: Color) -> void:
	for y in range(2, 14):
		var half := int((y - 2) * 0.42) + 1
		for x in range(8 - half, 8 + half):
			_px(img, x, y, col if x < 8 else dark)
	for y in range(2, 14):
		_px(img, 8 - int((y - 2) * 0.42) - 1, y, lit)


static func _ico_dust(img: Image, col: Color, dark: Color, lit: Color) -> void:
	var r := _rng(col.to_rgba32())
	# a small conical pile
	for y in range(8, 14):
		var half := (y - 7) + 1
		for x in range(8 - half, 8 + half):
			_px(img, x, y, col if r.randf() > 0.3 else dark)
	for i in 12:
		_px(img, r.randi_range(3, 12), r.randi_range(3, 8), lit)


static func _ico_vial(img: Image, col: Color, dark: Color, lit: Color) -> void:
	var glass := Color(0.82, 0.90, 0.94, 0.55)
	_rect(img, 6, 1, 4, 3, glass)      # neck
	_rect(img, 5, 4, 6, 1, glass)
	for y in range(5, 14):
		for x in range(4, 12):
			var edge := x == 4 or x == 11 or y == 13
			_px(img, x, y, glass if edge else (col if y > 7 else glass))
	_rect(img, 5, 8, 6, 5, col)
	_rect(img, 5, 8, 6, 1, lit)
	_rect(img, 5, 12, 6, 1, dark)


static func _ico_tool(img: Image, col: Color, dark: Color, lit: Color, shape: StringName) -> void:
	var wood := Color(0.48, 0.34, 0.20)
	# handle, bottom-left to top-right
	for i in 11:
		_px(img, 3 + i, 13 - i, wood)
		_px(img, 4 + i, 13 - i, _shade(wood, 0.75))
	match shape:
		&"shovel":
			_rect(img, 10, 1, 5, 5, col)
			_rect(img, 10, 1, 5, 1, lit)
		&"axe":
			_rect(img, 10, 1, 4, 6, col)
			_rect(img, 9, 2, 1, 4, lit)
		&"drill":
			for i in 5:
				_rect(img, 9 + i, 1 + i, 5 - i, 2, col)
			_px(img, 14, 1, lit)
		&"lamp":
			_rect(img, 9, 1, 6, 6, col)
			_rect(img, 10, 2, 4, 4, Color(1, 0.96, 0.8))
		&"key":
			_rect(img, 9, 1, 5, 5, col)
			_rect(img, 10, 2, 3, 3, Color(0, 0, 0, 0))
			_rect(img, 6, 6, 2, 8, col)
			_rect(img, 4, 11, 2, 2, col)
		_:
			# pickaxe head: a shallow arc
			for i in 7:
				_px(img, 8 + i, 4 - int(i * 0.35), col)
				_px(img, 8 + i, 5 - int(i * 0.35), col)
			_rect(img, 7, 3, 2, 3, col)
			_px(img, 14, 2, lit)


static func _ico_blade(img: Image, col: Color, dark: Color, lit: Color, shape: StringName) -> void:
	var grip := Color(0.34, 0.24, 0.18)
	if shape == &"whip":
		for i in 13:
			var y := 2 + i
			var x := 3 + int(3.0 * sin(float(i) * 0.7)) + int(i * 0.5)
			_px(img, x, y, col)
			_px(img, x + 1, y, dark)
		_rect(img, 2, 1, 3, 3, grip)
		return
	if shape == &"staff":
		for i in 13:
			_px(img, 6 + int(i * 0.2), 14 - i, grip)
			_px(img, 7 + int(i * 0.2), 14 - i, _shade(grip, 0.7))
		for y in range(1, 5):
			for x in range(6, 12):
				if Vector2(x - 8.5, y - 2.5).length() < 2.6:
					_px(img, x, y, col if (x + y) % 2 == 0 else lit)
		return
	# sword / dagger / spear: a blade up the diagonal with a crossguard
	var length := 12 if shape != &"dagger" else 8
	for i in length:
		var x := 3 + i
		var y := 13 - i
		_px(img, x, y, lit)
		_px(img, x + 1, y, col)
		_px(img, x + 1, y + 1, dark)
	if shape == &"spear":
		_rect(img, 12, 1, 3, 3, col)
	_rect(img, 2, 12, 4, 2, grip)
	_px(img, 4, 10, Color(0.72, 0.66, 0.4))
	_px(img, 6, 12, Color(0.72, 0.66, 0.4))


static func _ico_heavy(img: Image, col: Color, dark: Color, lit: Color, shape: StringName) -> void:
	var grip := Color(0.34, 0.24, 0.18)
	match shape:
		&"bow":
			for y in range(1, 15):
				var t := (float(y) - 8.0) / 7.0
				var x := 4 + int(4.0 * (1.0 - t * t))
				_px(img, x, y, col)
				_px(img, x + 1, y, dark)
				_px(img, 4, y, Color(0.88, 0.86, 0.76, 0.85))
		&"gun":
			_rect(img, 2, 6, 12, 4, col)
			_rect(img, 2, 6, 12, 1, lit)
			_rect(img, 3, 10, 4, 5, dark)
			_rect(img, 12, 7, 3, 2, dark)
		&"shield":
			for y in range(1, 15):
				var w := 6 - int(maxf(0.0, float(y) - 9.0) * 1.4)
				for x in range(8 - w, 8 + w):
					var edge := x <= 8 - w + 1 or x >= 8 + w - 2 or y <= 2
					_px(img, x, y, dark if edge else col)
			_rect(img, 6, 5, 4, 5, lit)
		_:
			# hammer
			for i in 9:
				_px(img, 3 + i, 14 - i, grip)
				_px(img, 4 + i, 14 - i, _shade(grip, 0.72))
			_rect(img, 8, 1, 7, 6, col)
			_rect(img, 8, 1, 7, 1, lit)
			_rect(img, 8, 6, 7, 1, dark)


static func _ico_armor(img: Image, col: Color, dark: Color, lit: Color, shape: StringName) -> void:
	match shape:
		&"helm":
			for y in range(2, 12):
				for x in range(3, 13):
					var d := Vector2(x - 7.5, y - 8.0).length()
					if d < 5.2 and y < 10:
						_px(img, x, y, lit if y < 5 else col)
			_rect(img, 4, 8, 8, 2, Color(0.10, 0.10, 0.13))  # visor
			_rect(img, 3, 10, 10, 2, dark)
		&"greaves":
			_rect(img, 3, 2, 4, 12, col)
			_rect(img, 9, 2, 4, 12, col)
			_rect(img, 3, 2, 4, 2, lit)
			_rect(img, 9, 2, 4, 2, lit)
			_rect(img, 3, 12, 4, 2, dark)
			_rect(img, 9, 12, 4, 2, dark)
		_:
			_rect(img, 3, 3, 10, 10, col)
			_rect(img, 3, 3, 10, 2, lit)
			_rect(img, 2, 3, 3, 4, col)     # pauldrons
			_rect(img, 11, 3, 3, 4, col)
			_rect(img, 3, 11, 10, 2, dark)
			_rect(img, 7, 6, 2, 5, dark)


static func _ico_sprig(img: Image, col: Color, dark: Color, lit: Color) -> void:
	_rect(img, 7, 6, 2, 9, dark)
	for i in 4:
		var y := 5 + i * 2
		_rect(img, 3 + i, y, 4, 2, col if i % 2 == 0 else lit)
		_rect(img, 9 - i, y + 1, 4, 2, lit if i % 2 == 0 else col)
	_rect(img, 6, 2, 4, 4, lit)


static func atlas_region(tile: int) -> Rect2:
	var col := tile % ATLAS_COLS
	var row := tile / ATLAS_COLS
	return Rect2(col * TILE, row * TILE, TILE, TILE)


# ------------------------------------------------------------------- sprites

const CH_W := 20
const CH_H := 30
const CH_FRAMES := 6   # 0 idle, 1-4 walk cycle, 5 airborne


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for j in h:
		for i in w:
			_px(img, x + i, y + j, c)


## A chibi explorer: dark bob haircut, pale face, dark coat with a light sash,
## boots. Deliberately silhouette-first so it reads at HD-2D distances.
static func build_character() -> ImageTexture:
	var img := Image.create(CH_W * CH_FRAMES, CH_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var hair := Color(0.129, 0.106, 0.145)
	var hair_lit := Color(0.243, 0.204, 0.267)
	var skin := Color(0.949, 0.827, 0.749)
	var skin_sh := Color(0.847, 0.706, 0.639)
	var coat := Color(0.192, 0.176, 0.239)
	var coat_lit := Color(0.290, 0.267, 0.353)
	var sash := Color(0.878, 0.843, 0.792)
	var accent := Color(0.847, 0.408, 0.239)
	var boot := Color(0.212, 0.157, 0.145)
	var eye := Color(0.086, 0.078, 0.110)

	for f in CH_FRAMES:
		var ox := f * CH_W
		# per-frame animation offsets
		var bob := 0
		var larm := 0
		var rarm := 0
		var lleg := 0
		var rleg := 0
		match f:
			0:
				bob = 0
			1:
				bob = -1; lleg = 2; rleg = -1; larm = -1; rarm = 1
			2:
				bob = 0; lleg = 0; rleg = 0
			3:
				bob = -1; lleg = -1; rleg = 2; larm = 1; rarm = -1
			4:
				bob = 0; lleg = 0; rleg = 0
			5:
				bob = -2; lleg = 1; rleg = -2; larm = -2; rarm = -2

		var base_y := 4 + bob

		# --- legs (drawn first, behind coat)
		_rect(img, ox + 7, base_y + 20 + lleg, 3, 5 - lleg, coat)
		_rect(img, ox + 10, base_y + 20 + rleg, 3, 5 - rleg, coat)
		# boots
		_rect(img, ox + 6, base_y + 24 + lleg, 4, 2, boot)
		_rect(img, ox + 10, base_y + 24 + rleg, 4, 2, boot)

		# --- coat / torso
		_rect(img, ox + 6, base_y + 11, 8, 10, coat)
		_rect(img, ox + 6, base_y + 11, 8, 1, coat_lit)
		_rect(img, ox + 5, base_y + 19, 10, 3, coat)      # skirt flare
		# sash
		_rect(img, ox + 6, base_y + 15, 8, 2, sash)
		_px(img, ox + 9, base_y + 15, accent)
		_px(img, ox + 10, base_y + 16, accent)

		# --- arms
		_rect(img, ox + 4, base_y + 12 + larm, 2, 7, coat_lit)
		_rect(img, ox + 14, base_y + 12 + rarm, 2, 7, coat_lit)
		_rect(img, ox + 4, base_y + 19 + larm, 2, 2, skin_sh)
		_rect(img, ox + 14, base_y + 19 + rarm, 2, 2, skin_sh)

		# --- head
		_rect(img, ox + 5, base_y + 2, 10, 10, skin)
		_rect(img, ox + 5, base_y + 10, 10, 2, skin_sh)
		# hair: bob cut with fringe
		_rect(img, ox + 4, base_y + 0, 12, 5, hair)
		_rect(img, ox + 4, base_y + 5, 2, 7, hair)
		_rect(img, ox + 14, base_y + 5, 2, 7, hair)
		_rect(img, ox + 5, base_y + 4, 4, 2, hair)
		_rect(img, ox + 11, base_y + 4, 4, 2, hair)
		_rect(img, ox + 5, base_y + 0, 10, 1, hair_lit)
		# a little ribbon, matching the reference's silhouette accents
		_rect(img, ox + 2, base_y + 1, 3, 3, accent)
		_rect(img, ox + 15, base_y + 1, 3, 3, accent)
		# eyes
		_rect(img, ox + 7, base_y + 7, 2, 2, eye)
		_rect(img, ox + 11, base_y + 7, 2, 2, eye)
		_px(img, ox + 8, base_y + 7, Color(1, 1, 1, 0.9))
		_px(img, ox + 12, base_y + 7, Color(1, 1, 1, 0.9))

	return ImageTexture.create_from_image(img)


## A villager: the same chibi build as the player, recoloured per role and
## varied by seed, so a settlement reads as a crowd rather than as one clone.
static func build_npc(coat_col: Color, accent: Color, seed_v: int) -> ImageTexture:
	var img := Image.create(CH_W * CH_FRAMES, CH_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := _rng(seed_v)

	var skins := [Color(0.949, 0.827, 0.749), Color(0.78, 0.62, 0.49),
		Color(0.60, 0.44, 0.33), Color(0.42, 0.30, 0.24)]
	var hairs := [Color(0.129, 0.106, 0.145), Color(0.36, 0.22, 0.13),
		Color(0.70, 0.62, 0.42), Color(0.52, 0.52, 0.56)]
	var skin: Color = skins[r.randi() % skins.size()]
	var skin_sh := _shade(skin, 0.86)
	var hair: Color = hairs[r.randi() % hairs.size()]
	var coat := coat_col
	var coat_lit := _shade(coat, 1.35)
	var boot := _shade(coat, 0.62)
	var eye := Color(0.086, 0.078, 0.110)
	var tall := r.randi_range(0, 1)   # a pixel of height variation

	for f in CH_FRAMES:
		var ox := f * CH_W
		var bob := 0
		var lleg := 0
		var rleg := 0
		var larm := 0
		var rarm := 0
		match f:
			1: bob = -1; lleg = 2; rleg = -1; larm = -1; rarm = 1
			3: bob = -1; lleg = -1; rleg = 2; larm = 1; rarm = -1
			5: bob = -2; lleg = 1; rleg = -2; larm = -2; rarm = -2
		var base_y := 4 + bob + tall

		_rect(img, ox + 7, base_y + 20 + lleg, 3, 5 - lleg, coat)
		_rect(img, ox + 10, base_y + 20 + rleg, 3, 5 - rleg, coat)
		_rect(img, ox + 6, base_y + 24 + lleg, 4, 2, boot)
		_rect(img, ox + 10, base_y + 24 + rleg, 4, 2, boot)

		_rect(img, ox + 6, base_y + 11, 8, 10, coat)
		_rect(img, ox + 6, base_y + 11, 8, 1, coat_lit)
		_rect(img, ox + 5, base_y + 19, 10, 3, coat)
		_rect(img, ox + 6, base_y + 15, 8, 2, accent)

		_rect(img, ox + 4, base_y + 12 + larm, 2, 7, coat_lit)
		_rect(img, ox + 14, base_y + 12 + rarm, 2, 7, coat_lit)
		_rect(img, ox + 4, base_y + 19 + larm, 2, 2, skin_sh)
		_rect(img, ox + 14, base_y + 19 + rarm, 2, 2, skin_sh)

		_rect(img, ox + 5, base_y + 2, 10, 10, skin)
		_rect(img, ox + 5, base_y + 10, 10, 2, skin_sh)
		_rect(img, ox + 4, base_y + 0, 12, 4, hair)
		_rect(img, ox + 4, base_y + 4, 2, 6, hair)
		_rect(img, ox + 14, base_y + 4, 2, 6, hair)
		_rect(img, ox + 7, base_y + 7, 2, 2, eye)
		_rect(img, ox + 11, base_y + 7, 2, 2, eye)

	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ creatures

const MB_W := 28
const MB_H := 28
const MB_FRAMES := 4
## per-frame squash, which is the whole animation budget for a procedural mob
const MB_SQUASH := [0.0, 0.14, 0.0, -0.11]


## A monster sprite, synthesised from a species' shape and feature dictionary.
## Four frames of squash-and-stretch, drawn silhouette-first so it still reads
## at HD-2D distances and through a cross-section.
static func build_creature(shape: StringName, tint: Color, alt: Color,
		features: Dictionary) -> ImageTexture:
	var img := Image.create(MB_W * MB_FRAMES, MB_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := _shade(tint, 0.55)
	var lit := _shade(tint, 1.32)
	var eye_col := Color(0.06, 0.05, 0.08)
	var glow := float(features.get("glow", 0.0))
	if glow > 0.0:
		eye_col = alt.lightened(0.4)

	for f in MB_FRAMES:
		var ox := f * MB_W
		var squash: float = MB_SQUASH[f]
		match shape:
			&"worm": _mb_worm(img, ox, f, squash, tint, dark, lit, alt)
			&"insect": _mb_insect(img, ox, f, squash, tint, dark, lit, alt, features)
			&"quadruped": _mb_quadruped(img, ox, f, squash, tint, dark, lit, alt, features)
			&"biped": _mb_biped(img, ox, f, squash, tint, dark, lit, alt, features)
			&"winged": _mb_winged(img, ox, f, squash, tint, dark, lit, alt, features)
			&"plant": _mb_plant(img, ox, f, squash, tint, dark, lit, alt)
			&"chest": _mb_chest(img, ox, f, squash, tint, dark, lit, alt)
			&"wraith": _mb_wraith(img, ox, f, squash, tint, dark, lit, alt)
			&"titan": _mb_titan(img, ox, f, squash, tint, dark, lit, alt, features)
			&"bulb": _mb_bulb(img, ox, f, squash, tint, dark, lit, alt, features)
			&"crab": _mb_crab(img, ox, f, squash, tint, dark, lit, alt, features)
			&"eye": _mb_eye(img, ox, f, squash, tint, dark, lit, alt)
			&"orb": _mb_orb(img, ox, f, squash, tint, dark, lit, alt, features)
			&"fish": _mb_fish(img, ox, f, squash, tint, dark, lit, alt, features)
			&"robot": _mb_robot(img, ox, f, squash, tint, dark, lit, alt, features)
			_: _mb_blob(img, ox, f, squash, tint, dark, lit, alt, features)
		_mb_eyes(img, ox, shape, int(features.get("eyes", 2)), eye_col, f)
	return ImageTexture.create_from_image(img)


static func _ellipse(img: Image, ox: int, cx: float, cy: float, rx: float,
		ry: float, fill: Color, rim: Color) -> void:
	for y in MB_H:
		for x in MB_W:
			var dx := (float(x) - cx) / maxf(rx, 0.1)
			var dy := (float(y) - cy) / maxf(ry, 0.1)
			var d := dx * dx + dy * dy
			if d <= 1.0:
				_px(img, ox + x, y, rim if d > 0.66 else fill)


static func _mb_blob(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, _alt: Color, features: Dictionary) -> void:
	var rx := 9.0 * (1.0 + squash)
	var ry := 8.5 * (1.0 - squash * 0.8)
	var cy := 25.0 - ry
	_ellipse(img, ox, 14.0, cy, rx, ry, tint, dark)
	_ellipse(img, ox, 11.0, cy - ry * 0.4, rx * 0.35, ry * 0.3, lit, lit)
	var tendrils := int(features.get("tendrils", 0))
	for i in tendrils:
		var tx := 14 + int((float(i) - float(tendrils - 1) * 0.5) * 4.0)
		var sway := int(sin(float(f) * 1.6 + float(i)) * 1.5)
		for j in 6:
			_px(img, ox + tx + int(float(j) * 0.3) * sway, int(cy + ry) + j, dark)


static func _mb_worm(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color) -> void:
	for seg in 4:
		var t := float(seg) / 3.0
		var cx := 6.0 + t * 15.0
		var wob := sin(float(f) * 1.5 + t * 3.0) * 1.6
		var cy := 21.0 + wob
		var r := 5.6 - t * 1.6 + squash * 2.0
		_ellipse(img, ox, cx, cy, r, r * 0.9, tint if seg % 2 == 0 else alt, dark)
	_ellipse(img, ox, 6.0, 21.0, 5.0, 4.6, lit, dark)


static func _mb_insect(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	var cy := 18.0
	var limbs := int(features.get("limbs", 4))
	for i in limbs:
		var side := 1 if i % 2 == 0 else -1
		var lx := 14 + side * 8
		var ly := 18 + (i / 2) * 3
		var kick := int(sin(float(f) * 1.6 + float(i)) * 2.0)
		for j in 5:
			_px(img, ox + lx + side * j, ly + absi(kick) - j / 2, dark)
	_ellipse(img, ox, 14.0, cy, 8.0 * (1.0 + squash), 6.5, tint, dark)
	_ellipse(img, ox, 14.0, cy - 2.0, 5.0, 3.4, lit, alt)
	_ellipse(img, ox, 14.0, cy - 7.0, 4.4, 4.0, alt, dark)
	for i in int(features.get("spikes", 0)):
		var sx := 8 + i * 3
		_px(img, ox + sx, int(cy) - 7, lit)
		_px(img, ox + sx, int(cy) - 8, lit)


static func _mb_quadruped(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	for i in 4:
		var lx := 8 + (i % 2) * 11
		var swing := int(sin(float(f) * 1.6 + float(i) * 1.7) * 2.0)
		for j in 6:
			_px(img, ox + lx + (swing if j > 3 else 0), 20 + j, dark)
	_ellipse(img, ox, 14.0, 17.0, 9.5 * (1.0 + squash), 5.8, tint, dark)
	_ellipse(img, ox, 7.0, 13.0, 4.6, 4.4, lit, dark)      # head
	if bool(features.get("tail", false)):
		for j in 6:
			_px(img, ox + 23 + j / 2, 15 - j + int(sin(float(f)) * 1.5), alt)


static func _mb_biped(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	for i in 2:
		var lx := 11 + i * 6
		var swing := int(sin(float(f) * 1.7 + float(i) * 3.1) * 2.0)
		for j in 7:
			_px(img, ox + lx + (swing if j > 4 else 0), 20 + j, dark)
	_ellipse(img, ox, 14.0, 15.0, 5.5 * (1.0 + squash), 7.0, tint, dark)
	_ellipse(img, ox, 14.0, 7.0, 4.6, 4.4, lit, alt)
	for i in int(features.get("limbs", 2)):
		var side := 1 if i % 2 == 0 else -1
		var swing2 := int(sin(float(f) * 1.7 + float(i)) * 2.0)
		for j in 6:
			_px(img, ox + 14 + side * (5 + j / 2), 12 + j + swing2, alt)
	for i in int(features.get("spikes", 0)):
		_px(img, ox + 10 + i * 2, 8 - i % 2, lit)


static func _mb_winged(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	var flap: float = [0.0, 1.0, 0.0, -1.0][f]
	var wings := maxi(int(features.get("wings", 2)), 2)
	for w in wings:
		var side := 1 if w % 2 == 0 else -1
		var tier := w / 2
		for j in 9:
			var wy := 13 + tier * 3 - int(float(j) * flap * 0.55)
			_px(img, ox + 14 + side * (4 + j), wy, alt if j % 2 == 0 else lit)
			_px(img, ox + 14 + side * (4 + j), wy + 1, dark)
	_ellipse(img, ox, 14.0, 15.0, 4.6 * (1.0 + squash), 5.6, tint, dark)
	if bool(features.get("beak", false)):
		_px(img, ox + 14, 21, lit)
		_px(img, ox + 14, 22, lit)


static func _mb_plant(img: Image, ox: int, f: int, _squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color) -> void:
	for j in 10:
		_px(img, ox + 14, 17 + j, dark)
		_px(img, ox + 15, 17 + j, alt)
	var open: float = [0.0, 0.4, 1.0, 0.4][f]
	_ellipse(img, ox, 14.0, 12.0, 6.5 + open * 1.5, 6.0 - open * 1.5, tint, dark)
	_ellipse(img, ox, 14.0, 11.0, 3.0, 2.4, lit, lit)


static func _mb_chest(img: Image, ox: int, f: int, _squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color) -> void:
	var gape: int = [0, 0, 3, 1][f]
	_rect(img, ox + 5, 14, 18, 10, tint)
	_rect(img, ox + 5, 14, 18, 2, lit)
	_rect(img, ox + 5, 22, 18, 2, dark)
	# lid, hinged open by `gape`
	_rect(img, ox + 5, 8 - gape, 18, 6, alt)
	_rect(img, ox + 5, 8 - gape, 18, 1, lit)
	if gape > 0:
		_rect(img, ox + 6, 14 - gape, 16, gape + 1, Color(0.06, 0.04, 0.06))
		for i in 8:
			_px(img, ox + 7 + i * 2, 14 - gape, Color(0.95, 0.93, 0.86))
			_px(img, ox + 7 + i * 2, 13, Color(0.95, 0.93, 0.86))
	_rect(img, ox + 13, 12, 2, 4, dark)   # clasp


static func _mb_wraith(img: Image, ox: int, f: int, _squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color) -> void:
	var drift := sin(float(f) * 1.6) * 1.4
	_ellipse(img, ox, 14.0, 10.0 + drift, 6.4, 7.2, tint, alt)
	# a ragged, tapering skirt instead of legs
	for j in 12:
		var w := 6 - j / 3
		var sway := int(sin(float(f) * 1.4 + float(j) * 0.5) * 2.0)
		for x in range(-w, w + 1):
			var c := dark if absi(x) > w - 2 else tint
			if (j + x + f) % 5 == 0:
				continue                      # holes: it is not solid
			_px(img, ox + 14 + x + sway, 15 + j, c)
	_ellipse(img, ox, 14.0, 8.0 + drift, 3.0, 3.0, lit, lit)


static func _mb_titan(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	for i in mini(int(features.get("limbs", 2)), 4):
		var side := 1 if i % 2 == 0 else -1
		var tier := i / 2
		var swing := int(sin(float(f) * 1.3 + float(i) * 2.0) * 2.0)
		for j in 8:
			_rect(img, ox + 14 + side * (7 + tier * 2) - 1, 17 + j + tier * 2 + swing,
				3, 1, dark if j > 4 else alt)
	_rect(img, ox + 6, 10, 16, 14, tint)
	_rect(img, ox + 6, 10, 16, 2, lit)
	_rect(img, ox + 6, 22, 16, 2, dark)
	_ellipse(img, ox, 14.0, 7.0, 5.5 * (1.0 + squash), 5.0, alt, dark)
	if float(features.get("glow", 0.0)) > 0.0:
		_rect(img, ox + 10, 15, 8, 3, lit)


## Poptop and kin: a small body under an enormous flower bulb.
static func _mb_bulb(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	var bob: int = [0, -1, 0, 1][f]
	# legs
	for i in mini(int(features.get("limbs", 2)), 4):
		var lx := 11 + (i % 2) * 6
		var kick := int(sin(float(f) * 1.7 + float(i) * 2.0) * 2.0)
		for j in 4:
			_px(img, ox + lx + (kick if j > 2 else 0), 21 + j + bob, alt)
	# body
	_ellipse(img, ox, 14.0, 19.0 + float(bob), 5.4 * (1.0 + squash), 4.6, alt, dark)
	# the bulb itself, petal by petal
	var petals := int(features.get("petals", 5))
	for p in petals:
		var a := TAU * float(p) / float(petals) - PI * 0.5
		var px := 14.0 + cos(a) * 5.2
		var py := 10.0 + sin(a) * 4.2 + float(bob)
		_ellipse(img, ox, px, py, 3.4, 3.0, tint, dark)
	_ellipse(img, ox, 14.0, 11.0 + float(bob), 3.6, 3.2, lit, tint)


## Crustoise, Ixodoom: a wide shell with legs poking out from under it.
static func _mb_crab(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	var limbs := mini(int(features.get("limbs", 6)), 8)
	for i in limbs:
		var side := 1 if i % 2 == 0 else -1
		var tier := i / 2
		var kick := int(sin(float(f) * 1.8 + float(i) * 1.3) * 2.0)
		for j in 5:
			_px(img, ox + 14 + side * (7 + j), 17 + tier * 2 + kick - j / 3, dark)
	# claws
	for side in [-1, 1]:
		_ellipse(img, ox, 14.0 + float(side) * 11.0, 20.0, 2.6, 2.2, alt, dark)
	# shell
	_ellipse(img, ox, 14.0, 15.0, 9.5 * (1.0 + squash * 0.5), 6.6, tint, dark)
	if bool(features.get("shell", false)):
		for i in 4:
			_rect(img, ox + 6 + i * 4, 11, 1, 8, dark)
		_ellipse(img, ox, 14.0, 12.5, 6.0, 3.0, lit, tint)


## Oculob: one eye, and it is looking at you from every angle.
static func _mb_eye(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color) -> void:
	var r := 8.0 * (1.0 + squash * 0.6)
	_ellipse(img, ox, 14.0, 15.0, r, r * 0.94, tint, dark)
	var look: int = [0, 1, 0, -1][f]
	_ellipse(img, ox, 14.0 + float(look), 15.0, 4.4, 4.4, Color(0.98, 0.98, 1.0),
		Color(0.82, 0.84, 0.90))
	_ellipse(img, ox, 14.0 + float(look) * 1.6, 15.0, 2.2, 2.2, alt, alt)
	_ellipse(img, ox, 13.0 + float(look) * 1.6, 14.0, 0.8, 0.8, lit, lit)
	# a few veins, so it reads as flesh rather than a marble
	for i in 5:
		var a := TAU * float(i) / 5.0
		_px(img, ox + int(14.0 + cos(a) * 6.5), int(15.0 + sin(a) * 6.0), dark)


## Skimbus: a drifting sac with trailing feelers.
static func _mb_orb(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	var drift := sin(float(f) * 1.6) * 1.5
	_ellipse(img, ox, 14.0, 12.0 + drift, 7.6 * (1.0 + squash), 7.0, tint, dark)
	_ellipse(img, ox, 11.5, 9.5 + drift, 2.6, 2.0, lit, lit)
	var tendrils := int(features.get("tendrils", 4))
	for i in tendrils:
		var tx := 14 + int((float(i) - float(tendrils - 1) * 0.5) * 3.6)
		for j in 7:
			var sway := int(sin(float(f) * 1.4 + float(i) + float(j) * 0.5) * 1.6)
			_px(img, ox + tx + sway, int(18.0 + drift) + j, alt if j % 2 == 0 else dark)


## Anglure: mostly teeth, with a lantern out in front on a stalk.
static func _mb_fish(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	_ellipse(img, ox, 15.0, 16.0, 8.5 * (1.0 + squash), 6.4, tint, dark)
	# tail
	for j in 5:
		_rect(img, ox + 23 + j / 2, 14 - j / 2 + int(sin(float(f)) * 1.5), 2, 4 + j, dark)
	# jaw
	var gape: int = [1, 3, 1, 0][f]
	_rect(img, ox + 5, 18 + gape, 10, 2, dark)
	var teeth := mini(int(features.get("teeth", 8)), 10)
	for i in teeth:
		_px(img, ox + 5 + i, 17 + gape, Color(0.96, 0.94, 0.88))
		_px(img, ox + 5 + i, 20 + gape, Color(0.96, 0.94, 0.88))
	if bool(features.get("lure", false)):
		for j in 6:
			_px(img, ox + 10 - j / 2, 12 - j, alt)
		_ellipse(img, ox, 7.0, 5.0, 2.6, 2.6, lit, lit)


## Scandroid: a chassis, one lens, and an antenna it will use.
static func _mb_robot(img: Image, ox: int, f: int, squash: float, tint: Color,
		dark: Color, lit: Color, alt: Color, features: Dictionary) -> void:
	for i in 2:
		var lx := 11 + i * 6
		var swing := int(sin(float(f) * 1.7 + float(i) * 3.1) * 2.0)
		_rect(img, ox + lx, 20, 2, 7 + swing / 2, dark)
		_rect(img, ox + lx - 1, 26, 4, 2, alt)
	_rect(img, ox + 7, 11, 14, 10, tint)
	_rect(img, ox + 7, 11, 14, 2, lit)
	_rect(img, ox + 7, 19, 14, 2, dark)
	# a lens that sweeps
	var sweep: int = [0, 2, 0, -2][f]
	_ellipse(img, ox, 14.0 + float(sweep), 15.5, 3.4 * (1.0 + squash), 3.4, dark, dark)
	_ellipse(img, ox, 14.0 + float(sweep), 15.5, 2.0, 2.0, alt, alt)
	if bool(features.get("antenna", false)):
		_rect(img, ox + 14, 5, 1, 6, dark)
		_px(img, ox + 14, 4, alt)
		if f % 2 == 0:
			_px(img, ox + 13, 3, alt)
			_px(img, ox + 15, 3, alt)


static func _mb_eyes(img: Image, ox: int, shape: StringName, count: int,
		col: Color, f: int) -> void:
	if count <= 0:
		return
	var cy := 7
	match shape:
		&"worm": cy = 20
		&"blob": cy = 16
		&"quadruped": cy = 12
		&"insect": cy = 11
		&"plant": cy = 11
		&"chest": cy = 11
		&"titan": cy = 7
		&"wraith": cy = 8
		&"bulb": cy = 18
		&"crab": cy = 13
		&"orb": cy = 11
		&"fish": cy = 13
		&"robot": return          # its lens is drawn as part of the chassis
		&"eye": return            # it *is* the eye
	var blink := f == 2 and count <= 2
	for i in count:
		var row := i / 4
		var col_i := i % 4
		var spread := mini(count, 4)
		var x := 14 + int((float(col_i) - float(spread - 1) * 0.5) * 3.0)
		var y := cy + row * 3
		if blink:
			_rect(img, ox + x - 1, y + 1, 2, 1, col)
		else:
			_rect(img, ox + x - 1, y, 2, 2, col)
			_px(img, ox + x, y, Color(1, 1, 1, 0.9))


const CR_W := 18
const CR_H := 16
const CR_FRAMES := 4
const SQUASH := [0.0, 0.18, 0.0, -0.14]


## Blob critter — squashes and stretches across 4 frames.
static func build_critter(tint: Color) -> ImageTexture:
	var img := Image.create(CR_W * CR_FRAMES, CR_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := _shade(tint, 0.55)
	var lit := _shade(tint, 1.35)
	var eye := Color(0.078, 0.071, 0.098)

	for f in CR_FRAMES:
		var ox := f * CR_W
		var squash: float = SQUASH[f]
		var rw := 7.0 * (1.0 + squash)
		var rh := 6.0 * (1.0 - squash * 0.8)
		var cy := 15.0 - rh
		for y in CR_H:
			for x in CR_W:
				var dx := (float(x) - 9.0) / rw
				var dy := (float(y) - cy) / rh
				var d := dx * dx + dy * dy
				if d <= 1.0:
					var c := tint
					if d > 0.72:
						c = dark
					elif dy < -0.35 and absf(dx) < 0.55:
						c = lit
					_px(img, ox + x, y, c)
		# eyes
		var ey := int(cy - rh * 0.15)
		_rect(img, ox + 6, ey, 2, 2, eye)
		_rect(img, ox + 10, ey, 2, 2, eye)

	return ImageTexture.create_from_image(img)
