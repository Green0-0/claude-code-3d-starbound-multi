## Light sources, spread across the whole 0..15 range so the lighting agent has
## a real gradient to test propagation with and the player has a genuine
## progression from "a stick that is on fire" to "a bottled star".
##
##   1-3   lichen, dim moss            — barely reads, cave ambience
##   4-7   candle, ember lamp, fungus  — a pool of light around you
##   8-11  torch, paper lantern, crystals
##  12-14  lantern, campfire, neon
##     15  glowstone, star lamp        — full-brightness, no falloff at all
##
## Everything here also carries the `light_source` tag; `Blocks.light_of(id)` is
## the hot path the lighting sim actually reads.
extends RefCounted


static func register_all(reg) -> void:
	_flames(reg)
	_crystals(reg)
	_organic(reg)
	_technological(reg)


static func _lamp(reg, p_name: StringName, display: String, col: Color, alt: Color,
		pat: BlockType.Pattern, level: int, emission: float, hardness: float,
		step: StringName, tool: StringName = &"any") -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, pat, alt)
	bt.mining(hardness, tool, 0)
	bt.glows(level, emission)
	bt.sounds(step)
	bt.in_category(&"light").tag(&"light_source")
	return bt


# -------------------------------------------------------------------- flame
static func _flames(reg) -> void:
	_lamp(reg, &"torch", "Torch", Color(1.00, 0.72, 0.32), Color(0.48, 0.34, 0.20),
		BlockType.Pattern.ORGANIC, 13, 1.0, 0.05, &"step_wood") \
		.mode(BlockType.Render.CROSS).tag(&"wood").flags({"flammable": false})
	_lamp(reg, &"candle", "Candle", Color(0.98, 0.94, 0.78), Color(0.86, 0.78, 0.54),
		BlockType.Pattern.ORGANIC, 8, 0.9, 0.05, &"step_wood") \
		.mode(BlockType.Render.CROSS).tag(&"decor")
	_lamp(reg, &"campfire", "Campfire", Color(1.00, 0.56, 0.18), Color(0.40, 0.26, 0.16),
		BlockType.Pattern.ORGANIC, 14, 1.0, 0.6, &"step_wood", &"axe") \
		.tag(&"wood").tag(&"hazard") \
		.flags({"opaque": false, "damage_on_touch": 5.0, "damage_element": Const.ELEM_FIRE})
	_lamp(reg, &"lantern", "Lantern", Color(1.00, 0.86, 0.52), Color(0.36, 0.32, 0.26),
		BlockType.Pattern.METAL, 15, 1.0, 0.8, &"step_metal") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}).tag(&"metal")
	_lamp(reg, &"paper_lantern", "Paper Lantern", Color(0.98, 0.62, 0.52), Color(0.80, 0.42, 0.34),
		BlockType.Pattern.CLOTH, 11, 1.0, 0.2, &"step_wood") \
		.tag(&"cloth").tag(&"decor").flags({"flammable": true, "opaque": false})
	_lamp(reg, &"ember_lamp", "Ember Lamp", Color(0.86, 0.36, 0.16), Color(0.30, 0.16, 0.12),
		BlockType.Pattern.SPECKLE, 6, 0.8, 1.4, &"step_stone", &"pickaxe") \
		.tag(&"stone").tag(&"biome_magma")


# ------------------------------------------------------------------ crystal
static func _crystals(reg) -> void:
	_lamp(reg, &"glowstone", "Glowstone", Color(0.98, 0.92, 0.60), Color(0.82, 0.72, 0.34),
		BlockType.Pattern.CRYSTAL, 15, 1.0, 1.2, &"step_stone", &"pickaxe") \
		.drop(&"glow_dust", 2, 4).tag(&"crystal").tag(&"stratum_deep")
	_lamp(reg, &"crystal_block", "White Crystal", Color(0.92, 0.96, 1.00), Color(0.70, 0.80, 0.92),
		BlockType.Pattern.CRYSTAL, 12, 1.0, 1.6, &"step_glass", &"pickaxe") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}) \
		.drop(&"crystal_shard", 1, 3).tag(&"crystal").tag(&"cave_decor")
	_lamp(reg, &"crystal_blue", "Blue Crystal", Color(0.40, 0.68, 1.00), Color(0.22, 0.44, 0.80),
		BlockType.Pattern.CRYSTAL, 10, 1.0, 1.6, &"step_glass", &"pickaxe") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}) \
		.drop(&"crystal_shard", 1, 3).tag(&"crystal").tag(&"cave_decor")
	_lamp(reg, &"crystal_violet", "Violet Crystal", Color(0.76, 0.42, 1.00), Color(0.52, 0.24, 0.78),
		BlockType.Pattern.CRYSTAL, 11, 1.0, 1.8, &"step_glass", &"pickaxe") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}) \
		.drop(&"crystal_shard", 1, 3).tag(&"crystal").tag(&"biome_alien")
	_lamp(reg, &"crystal_ember", "Ember Crystal", Color(1.00, 0.50, 0.24), Color(0.72, 0.28, 0.12),
		BlockType.Pattern.CRYSTAL, 9, 1.0, 2.0, &"step_glass", &"pickaxe") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}) \
		.drop(&"crystal_shard", 1, 3).tag(&"crystal").tag(&"biome_magma")


# --------------------------------------------------------------- biological
static func _organic(reg) -> void:
	_lamp(reg, &"glow_fungus", "Glowcap", Color(0.44, 0.94, 0.78), Color(0.24, 0.62, 0.52),
		BlockType.Pattern.ORGANIC, 9, 1.0, 0.1, &"step_leaves") \
		.mode(BlockType.Render.CROSS).tag(&"fungus").tag(&"mushroom").tag(&"biome_forest") \
		.drop(&"glow_fungus")
	_lamp(reg, &"fungal_bloom", "Fungal Bloom", Color(0.62, 0.40, 0.94), Color(0.36, 0.22, 0.60),
		BlockType.Pattern.ORGANIC, 6, 0.9, 0.4, &"step_leaves") \
		.tag(&"fungus").tag(&"biome_alien").flags({"opaque": false})
	_lamp(reg, &"dim_moss", "Dim Moss", Color(0.34, 0.60, 0.44), Color(0.22, 0.40, 0.30),
		BlockType.Pattern.ORGANIC, 4, 0.6, 0.1, &"step_grass") \
		.mode(BlockType.Render.CROSS).tag(&"organic").tag(&"cave_decor") \
		.flags({"replaceable": true})
	_lamp(reg, &"faint_lichen", "Faint Lichen", Color(0.56, 0.66, 0.52), Color(0.38, 0.46, 0.36),
		BlockType.Pattern.ORGANIC, 2, 0.4, 0.1, &"step_grass") \
		.mode(BlockType.Render.CROSS).tag(&"organic").tag(&"cave_decor") \
		.flags({"replaceable": true})
	_lamp(reg, &"deepglow_algae", "Deepglow Algae", Color(0.30, 0.80, 0.86), Color(0.18, 0.52, 0.58),
		BlockType.Pattern.ORGANIC, 7, 0.9, 0.2, &"step_liquid") \
		.mode(BlockType.Render.CROSS).tag(&"organic").tag(&"biome_ocean")


# ------------------------------------------------------------------- neon
static func _neon(reg, p_name: StringName, display: String, col: Color) -> BlockType:
	return _lamp(reg, p_name, display, col, col.darkened(0.55),
		BlockType.Pattern.CIRCUIT, 12, 1.0, 1.0, &"step_metal", &"pickaxe") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}) \
		.tag(&"metal").tag(&"decor").tag(&"trim")


static func _technological(reg) -> void:
	_neon(reg, &"neon_strip_cyan", "Cyan Neon Strip", Color(0.30, 0.96, 1.00))
	_neon(reg, &"neon_strip_magenta", "Magenta Neon Strip", Color(1.00, 0.28, 0.78))
	_neon(reg, &"neon_strip_amber", "Amber Neon Strip", Color(1.00, 0.70, 0.20))
	_neon(reg, &"neon_strip_lime", "Lime Neon Strip", Color(0.60, 1.00, 0.28))
	_lamp(reg, &"floodlight", "Floodlight", Color(0.96, 0.98, 1.00), Color(0.34, 0.36, 0.40),
		BlockType.Pattern.METAL, 15, 1.0, 2.2, &"step_metal", &"pickaxe") \
		.tag(&"metal")
	_lamp(reg, &"star_lamp", "Star Lamp", Color(1.00, 0.96, 0.82), Color(0.52, 0.46, 0.72),
		BlockType.Pattern.CRYSTAL, 15, 1.0, 3.0, &"step_glass", &"pickaxe") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}) \
		.tag(&"crystal").tag(&"decor")
	_lamp(reg, &"panel_light", "Panel Light", Color(0.86, 0.92, 1.00), Color(0.40, 0.44, 0.52),
		BlockType.Pattern.FLAT, 13, 1.0, 1.6, &"step_metal", &"pickaxe") \
		.tag(&"metal").tag(&"decor")
