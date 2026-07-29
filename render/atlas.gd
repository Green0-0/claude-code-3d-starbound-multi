## Autoloaded as `Atlas`. The project's entire texture supply.
##
## At boot every registered `BlockType` is turned into three 16x16 tiles (side,
## +Y and -Y) by `AtlasPainter`, and those tiles are packed into a
## `Texture2DArray` plus a matching emission array. Chunk meshes address a tile
## by writing its array layer into `UV2.x`, so the whole world draws from a
## single material with no atlas-bleed and no UV padding maths.
##
## Item icons are painted on demand by `IconPainter` and cached.
##
## Nothing here reads a file from disk: the game ships with no binary assets.
extends Node

const TILE := 16
## Tiles reserved per block: 0 = side faces, 1 = +Y, 2 = -Y.
const GROUPS := 3
const GROUP_SIDE := 0
const GROUP_TOP := 1
const GROUP_BOTTOM := 2

const SHADER_OPAQUE := "res://render/voxel.gdshader"
const SHADER_TRANSPARENT := "res://render/voxel_transparent.gdshader"
const SHADER_LIQUID := "res://render/liquid.gdshader"

## The array texture every chunk material samples for albedo.
var texture: Texture2DArray = null
## Matching array of self-illumination tiles (black for non-glowing blocks).
var emission_texture: Texture2DArray = null

var material: ShaderMaterial = null
var material_transparent: ShaderMaterial = null
var material_liquid: ShaderMaterial = null

## block_id -> {"side": int, "top": int, "bottom": int} array layers.
## Kept for compatibility with the original stub API.
var uv_of_block: Dictionary = {}

var _layer_base: PackedInt32Array = PackedInt32Array()
var _emission: PackedFloat32Array = PackedFloat32Array()
var _tint: PackedColorArray = PackedColorArray()
var _built_count := -1
var _icons: Dictionary = {}
var _icon_rng := RandomNumberGenerator.new()


func _ready() -> void:
	build()


# ================================================================== atlas build
## Rebuild the atlas from the current block registry. Safe to call again after
## new blocks are registered; `layer_for()` does so automatically.
func build() -> void:
	var count: int = maxi(1, Blocks.count())
	_built_count = count

	var images: Array[Image] = []
	var emissive: Array[Image] = []
	_layer_base.resize(count)
	_emission.resize(count)
	_tint.resize(count)
	uv_of_block.clear()

	var rng := RandomNumberGenerator.new()
	for id in count:
		var bt: BlockType = Blocks.get_type(id)
		_layer_base[id] = id * GROUPS
		_emission[id] = bt.emission
		_tint[id] = Color(bt.color.r, bt.color.g, bt.color.b, 1.0)
		uv_of_block[id] = {
			"side": id * GROUPS + GROUP_SIDE,
			"top": id * GROUPS + GROUP_TOP,
			"bottom": id * GROUPS + GROUP_BOTTOM,
		}
		for group in GROUPS:
			# Seeded on the block name so a texture never changes between runs,
			# and per group so the three faces are not identical.
			rng.seed = hash(String(bt.name)) * 1000003 + group * 7919 + 11
			var img := _tile_for(bt, group, rng)
			images.append(img)
			emissive.append(_emission_tile(img, bt))

	texture = Texture2DArray.new()
	var err := texture.create_from_images(images)
	if err != OK:
		push_error("[Atlas] could not build the albedo array (%d)" % err)
	emission_texture = Texture2DArray.new()
	emission_texture.create_from_images(emissive)

	_build_materials()
	print("[Atlas] %d block tiles across %d array layers" % [count, images.size()])


func _tile_for(bt: BlockType, group: int, rng: RandomNumberGenerator) -> Image:
	var buf := AtlasPainter.paint(bt.pattern, bt.color, bt.color_alt, bt.top_color, group, rng)
	if bt.render == BlockType.Render.CROSS:
		AtlasPainter.mask_plant(buf, rng)
	# Insurance for the one failure that would blank the entire world: if a
	# generator produced nothing at all, fall back to the block's flat colour so
	# the voxel is still visible and still the right hue.
	if bt.render != BlockType.Render.NONE and _is_blank(buf):
		buf = _flat_buffer(bt.color)
	var img := Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGBA8, buf)
	img.generate_mipmaps()
	return img


func _is_blank(buf: PackedByteArray) -> bool:
	if buf.size() != TILE * TILE * 4:
		return true
	for i in range(3, buf.size(), 4):
		if buf[i] != 0:
			return false
	return true


func _flat_buffer(c: Color) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(TILE * TILE * 4)
	var r := int(clampf(c.r, 0.0, 1.0) * 255.0)
	var g := int(clampf(c.g, 0.0, 1.0) * 255.0)
	var b := int(clampf(c.b, 0.0, 1.0) * 255.0)
	var a := int(clampf(maxf(c.a, 0.35), 0.0, 1.0) * 255.0)
	for i in TILE * TILE:
		var o := i * 4
		buf[o] = r
		buf[o + 1] = g
		buf[o + 2] = b
		buf[o + 3] = a
	return buf


## Emission tiles glow where the albedo is bright, scaled by `BlockType.emission`.
func _emission_tile(albedo: Image, bt: BlockType) -> Image:
	var buf := AtlasPainter.new_buffer()
	if bt.emission > 0.0:
		for y in TILE:
			for x in TILE:
				var c := albedo.get_pixel(x, y)
				var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				# Bias toward the bright parts so ore veins and circuit traces
				# glow rather than the whole face.
				var k := pow(clampf(lum, 0.0, 1.0), 1.6)
				AtlasPainter.put(buf, x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	var img := Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGBA8, buf)
	img.generate_mipmaps()
	return img


func _build_materials() -> void:
	material = _make_material(SHADER_OPAQUE)
	material_transparent = _make_material(SHADER_TRANSPARENT)
	material_liquid = _make_material(SHADER_LIQUID)


func _make_material(path: String) -> ShaderMaterial:
	if not ResourceLoader.exists(path):
		push_error("[Atlas] missing shader %s" % path)
		return null
	var sh: Shader = load(path)
	if sh == null:
		push_error("[Atlas] could not load shader %s" % path)
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo_tex", texture)
	m.set_shader_parameter("emission_tex", emission_texture)
	return m


## Fallback used when a shader failed to load: vertex colours already carry
## `block_colour * light * ao`, so the world still renders, just untextured.
func _fallback_material(transparent: bool) -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# =================================================================== public API
## Material used by every chunk mesh. Exposes the slab uniforms listed in
## `View.shader_params()`; see `set_view_params()`.
func get_material(transparent: bool = false) -> Material:
	var m: ShaderMaterial = material_transparent if transparent else material
	if m == null:
		return _fallback_material(transparent)
	return m


## Material for `Render.LIQUID` surfaces (alpha blended, gently waving).
func get_liquid_material() -> Material:
	if material_liquid == null:
		return get_material(true)
	return material_liquid


## Layer index in the texture array for (block_id, face). `face` uses the
## `Const.FACE_*` numbering.
func layer_for(block_id: int, face: int) -> int:
	if block_id < 0 or block_id >= _layer_base.size():
		# A block registered after the atlas was built: rebuild once.
		if Blocks.count() != _built_count:
			build()
		if block_id < 0 or block_id >= _layer_base.size():
			return 0
	var group := GROUP_SIDE
	if face == Const.FACE_PY:
		group = GROUP_TOP
	elif face == Const.FACE_NY:
		group = GROUP_BOTTOM
	return _layer_base[block_id] + group


## Rebuild the atlas if blocks were registered after boot. Cheap when current.
func ensure_built() -> void:
	if _built_count != Blocks.count() or texture == null:
		build()


## Flat 32x32 icon for inventory UI, generated on demand and cached.
func item_icon(item_id: StringName) -> Texture2D:
	var cached: Texture2D = _icons.get(item_id)
	if cached != null:
		return cached
	var it: ItemType = Items.get_type(item_id)
	var tint := Color(0.7, 0.7, 0.72)
	var shape := &"square"
	if it != null:
		tint = it.icon_color
		shape = it.icon_shape
	_icon_rng.seed = hash(String(item_id)) * 2654435761
	var tex := ImageTexture.create_from_image(IconPainter.draw(shape, tint, _icon_rng))
	# Do not cache a placeholder drawn before the item registry finished loading.
	if it != null:
		_icons[item_id] = tex
	return tex


## Drop every cached icon (call after items are re-registered).
func clear_icon_cache() -> void:
	_icons.clear()


# ============================================================ shader plumbing
## Push `View.shader_params()` (plus the renderer's fog colour) into all three
## chunk materials. Called every frame by `WorldRenderer`.
func set_view_params(params: Dictionary, fog: Color = Color(0.09, 0.11, 0.16)) -> void:
	for m: ShaderMaterial in [material, material_transparent, material_liquid]:
		if m == null:
			continue
		m.set_shader_parameter("depth_axis", params.get("depth_axis", 2.0))
		m.set_shader_parameter("depth_sign", params.get("depth_sign", -1.0))
		m.set_shader_parameter("play_layer", params.get("play_layer", 0.0))
		m.set_shader_parameter("slab_behind", params.get("slab_behind", float(Const.SLAB_BEHIND)))
		m.set_shader_parameter("slab_front", params.get("slab_front", float(Const.SLAB_FRONT)))
		m.set_shader_parameter("flip_blend", params.get("flip_blend", 0.0))
		m.set_shader_parameter("fog_color", fog)


## Immutable per-block tables handed to the mesher so meshing threads never
## touch the registry or this node. See `ChunkMesher.snapshot()`.
func mesh_tables() -> Dictionary:
	ensure_built()
	return {
		"layer_base": _layer_base,
		"emission": _emission,
		"tint": _tint,
	}
