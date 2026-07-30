extends RefCounted

## Light sources, spread across the whole 0..15 range so the block-light sim has
## a real gradient to propagate and the player has a genuine progression from "a
## stick that is on fire" to "a bottled star".
##
##    2-4   lichen, dim moss            — barely reads, cave ambience
##    6-8   candle, ember lamp, fungus  — a pool of light around you
##   9-11   torch, paper lantern, crystals
##  12-14   lantern, campfire, neon
##     15   glowstone, star lamp        — full brightness, no falloff at all


static func lamp(p_name: StringName, display: String, col: Color, alt: Color,
		pat: int, level: int, emis: float, hard: float, step: StringName,
		tool: StringName = &"any") -> Blocks.Def:
	return Blocks.define(p_name, display).look(col, pat, alt) \
		.mining(hard, tool, 0).glows(level, emis).sounds(step).drop(p_name) \
		.in_category(&"light").tag(&"light_source")


static func neon(p_name: StringName, display: String, col: Color) -> Blocks.Def:
	return lamp(p_name, display, col, col.darkened(0.55), Blocks.Pattern.CIRCUIT,
			12, 1.0, 0.5, &"step_metal", &"pickaxe") \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.tag(&"metal").tag(&"decor").tag(&"trim")


static func register_all() -> void:
	_flames()
	_crystals()
	_organic()
	_technological()


static func _flames() -> void:
	lamp(&"torch", "Torch", Color(1.00, 0.72, 0.32), Color(0.48, 0.34, 0.20),
			Blocks.Pattern.ORGANIC, 13, 1.0, 0.03, &"step_wood") \
		.mode(Blocks.Render.CROSS).tag(&"wood")
	lamp(&"candle", "Candle", Color(0.98, 0.94, 0.78), Color(0.86, 0.78, 0.54),
			Blocks.Pattern.ORGANIC, 8, 0.9, 0.03, &"step_wood") \
		.mode(Blocks.Render.CROSS).tag(&"decor")
	lamp(&"campfire", "Campfire", Color(1.00, 0.56, 0.18), Color(0.40, 0.26, 0.16),
			Blocks.Pattern.ORGANIC, 14, 1.0, 0.3, &"step_wood", &"axe") \
		.tag(&"wood").tag(&"hazard").tag(&"station_kitchen") \
		.flags({"opaque": false, "damage_on_touch": 5.0,
			"damage_element": Blocks.ELEM_FIRE})
	lamp(&"lantern", "Lantern", Color(1.00, 0.86, 0.52), Color(0.36, 0.32, 0.26),
			Blocks.Pattern.METAL, 15, 1.0, 0.4, &"step_metal") \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}).tag(&"metal")
	lamp(&"paper_lantern", "Paper Lantern", Color(0.98, 0.62, 0.52), Color(0.80, 0.42, 0.34),
			Blocks.Pattern.CLOTH, 11, 1.0, 0.1, &"step_wood") \
		.tag(&"cloth").tag(&"decor").flags({"flammable": true, "opaque": false})
	lamp(&"ember_lamp", "Ember Lamp", Color(0.86, 0.36, 0.16), Color(0.30, 0.16, 0.12),
			Blocks.Pattern.SPECKLE, 6, 0.8, 0.7, &"step_stone", &"pickaxe") \
		.tag(&"stone").tag(&"biome_magma")


static func _crystals() -> void:
	lamp(&"glowstone", "Glowstone", Color(0.98, 0.92, 0.60), Color(0.82, 0.72, 0.34),
			Blocks.Pattern.CRYSTAL, 15, 1.0, 0.6, &"step_stone", &"pickaxe") \
		.drop(&"glow_dust", 2, 4).tag(&"crystal").tag(&"stratum_deep")
	lamp(&"crystal_blue", "Blue Crystal", Color(0.40, 0.68, 1.00), Color(0.22, 0.44, 0.80),
			Blocks.Pattern.CRYSTAL, 10, 1.0, 0.8, &"step_glass", &"pickaxe") \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.drop(&"crystal_shard", 1, 3).tag(&"crystal").tag(&"cave_decor")
	lamp(&"crystal_violet", "Violet Crystal", Color(0.76, 0.42, 1.00), Color(0.52, 0.24, 0.78),
			Blocks.Pattern.CRYSTAL, 11, 1.0, 0.9, &"step_glass", &"pickaxe") \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.drop(&"crystal_shard", 1, 3).tag(&"crystal").tag(&"biome_alien")
	lamp(&"crystal_ember", "Ember Crystal", Color(1.00, 0.50, 0.24), Color(0.72, 0.28, 0.12),
			Blocks.Pattern.CRYSTAL, 9, 1.0, 1.0, &"step_glass", &"pickaxe") \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.drop(&"crystal_shard", 1, 3).tag(&"crystal").tag(&"biome_magma")


static func _organic() -> void:
	lamp(&"glow_fungus", "Glowcap", Color(0.44, 0.94, 0.78), Color(0.24, 0.62, 0.52),
			Blocks.Pattern.ORGANIC, 9, 1.0, 0.05, &"step_leaves") \
		.mode(Blocks.Render.CROSS).tag(&"fungus").tag(&"mushroom").tag(&"biome_forest")
	lamp(&"dim_moss", "Dim Moss", Color(0.34, 0.60, 0.44), Color(0.22, 0.40, 0.30),
			Blocks.Pattern.ORGANIC, 4, 0.6, 0.05, &"step_grass") \
		.mode(Blocks.Render.CROSS).tag(&"organic").tag(&"cave_decor") \
		.flags({"replaceable": true})
	lamp(&"faint_lichen", "Faint Lichen", Color(0.56, 0.66, 0.52), Color(0.38, 0.46, 0.36),
			Blocks.Pattern.ORGANIC, 2, 0.4, 0.05, &"step_grass") \
		.mode(Blocks.Render.CROSS).tag(&"organic").tag(&"cave_decor") \
		.flags({"replaceable": true})
	lamp(&"deepglow_algae", "Deepglow Algae", Color(0.30, 0.80, 0.86), Color(0.18, 0.52, 0.58),
			Blocks.Pattern.ORGANIC, 7, 0.9, 0.1, &"step_liquid") \
		.mode(Blocks.Render.CROSS).tag(&"organic").tag(&"biome_ocean")


static func _technological() -> void:
	neon(&"neon_strip_cyan", "Cyan Neon Strip", Color(0.30, 0.96, 1.00))
	neon(&"neon_strip_magenta", "Magenta Neon Strip", Color(1.00, 0.28, 0.78))
	neon(&"neon_strip_amber", "Amber Neon Strip", Color(1.00, 0.70, 0.20))
	lamp(&"floodlight", "Floodlight", Color(0.96, 0.98, 1.00), Color(0.34, 0.36, 0.40),
			Blocks.Pattern.METAL, 15, 1.0, 1.1, &"step_metal", &"pickaxe").tag(&"metal")
	lamp(&"star_lamp", "Star Lamp", Color(1.00, 0.96, 0.82), Color(0.52, 0.46, 0.72),
			Blocks.Pattern.CRYSTAL, 15, 1.0, 1.5, &"step_glass", &"pickaxe") \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.tag(&"crystal").tag(&"decor")
	lamp(&"panel_light", "Panel Light", Color(0.86, 0.92, 1.00), Color(0.40, 0.44, 0.52),
			Blocks.Pattern.FLAT, 13, 1.0, 0.8, &"step_metal", &"pickaxe") \
		.tag(&"metal").tag(&"decor")
