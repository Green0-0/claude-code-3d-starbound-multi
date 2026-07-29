## Themed structure sets for the dungeon / worldgen agents.
##
## Seven cultures, each a matched quartet with an identical shape so a structure
## template can be written **once** against roles and re-skinned per theme:
##
##   role `wall`   the bulk material (opaque, tough)
##   role `floor`  walkable surface, slightly softer, different step sound
##   role `accent` the decorative / emissive piece — screens, idols, banners
##   role `locked` `breakable = false`, blast-proof: the boss door and the
##                 outer shell that stops players tunnelling into loot rooms
##
## Fetch a theme with `Blocks.all_with_tag(&"theme_glitch")` and pick the member
## you want with `has_tag(&"floor")`. `PsBlocks.THEMES` lists them in intended
## difficulty order.
extends RefCounted


static func register_all(reg) -> void:
	_human(reg)
	_apex(reg)
	_avian(reg)
	_floran(reg)
	_glitch(reg)
	_hylotl(reg)
	_ancient(reg)


# ---------------------------------------------------------------- human bunker
static func _human(reg) -> void:
	PsBlocks.themed(reg, &"bunker_wall", "Bunker Wall", Color(0.52, 0.54, 0.52),
		Color(0.38, 0.40, 0.38), BlockType.Pattern.METAL, 4.0, 1, &"theme_human", &"wall", &"step_metal") \
		.tag(&"metal")
	PsBlocks.themed(reg, &"steel_floor", "Bunker Floor", Color(0.44, 0.46, 0.46),
		Color(0.32, 0.34, 0.34), BlockType.Pattern.BRICK, 3.2, 1, &"theme_human", &"floor", &"step_metal") \
		.tag(&"metal")
	PsBlocks.themed(reg, &"terminal", "Bunker Console", Color(0.22, 0.26, 0.28),
		Color(0.36, 0.92, 0.52), BlockType.Pattern.CIRCUIT, 3.0, 1, &"theme_human", &"accent", &"step_metal") \
		.glows(7, 0.9).tag(&"decor").tag(&"light_source")
	PsBlocks.themed(reg, &"fluorescent", "Fluorescent Strip", Color(0.90, 0.94, 0.98),
		Color(0.36, 0.40, 0.44), BlockType.Pattern.FLAT, 2.0, 1, &"theme_human", &"accent", &"step_metal") \
		.glows(13, 1.0).tag(&"light_source").tag(&"metal")
	PsBlocks.themed(reg, &"bunker_seal", "Bunker Vault Door", Color(0.36, 0.38, 0.42),
		Color(0.66, 0.58, 0.24), BlockType.Pattern.METAL, 60.0, 99, &"theme_human", &"locked", &"step_metal") \
		.tag(&"metal").tag(&"door_frame")


# -------------------------------------------------------------------- apex lab
static func _apex(reg) -> void:
	PsBlocks.themed(reg, &"apex_panel", "Apex Lab Wall", Color(0.90, 0.90, 0.88),
		Color(0.74, 0.74, 0.72), BlockType.Pattern.FLAT, 3.6, 1, &"theme_apex", &"wall", &"step_metal")
	PsBlocks.themed(reg, &"apex_floor", "Apex Lab Floor", Color(0.80, 0.80, 0.82),
		Color(0.62, 0.62, 0.64), BlockType.Pattern.BRICK, 3.0, 1, &"theme_apex", &"floor", &"step_metal")
	PsBlocks.themed(reg, &"apex_console", "Apex Monitor Bank", Color(0.16, 0.18, 0.22),
		Color(0.94, 0.24, 0.26), BlockType.Pattern.CIRCUIT, 2.6, 1, &"theme_apex", &"accent", &"step_glass") \
		.glows(8, 1.0).tag(&"decor").tag(&"light_source")
	PsBlocks.themed(reg, &"apex_light", "Apex Ceiling Light", Color(0.96, 0.98, 1.00),
		Color(0.72, 0.74, 0.78), BlockType.Pattern.FLAT, 2.0, 1, &"theme_apex", &"accent", &"step_glass") \
		.glows(14, 1.0).tag(&"light_source")
	PsBlocks.themed(reg, &"apex_seal", "Apex Containment Seal", Color(0.86, 0.20, 0.22),
		Color(0.62, 0.62, 0.66), BlockType.Pattern.METAL, 60.0, 99, &"theme_apex", &"locked", &"step_metal") \
		.tag(&"metal").tag(&"door_frame")


# ---------------------------------------------------------------- avian temple
static func _avian(reg) -> void:
	PsBlocks.themed(reg, &"avian_stone", "Avian Temple Wall", Color(0.86, 0.76, 0.52),
		Color(0.68, 0.58, 0.38), BlockType.Pattern.BRICK, 3.4, 1, &"theme_avian", &"wall") \
		.tag(&"stone")
	PsBlocks.themed(reg, &"avian_tile", "Avian Temple Floor", Color(0.78, 0.68, 0.46),
		Color(0.60, 0.52, 0.34), BlockType.Pattern.STRATA, 2.8, 1, &"theme_avian", &"floor") \
		.tag(&"stone")
	PsBlocks.themed(reg, &"avian_idol", "Avian Sun Idol", Color(0.96, 0.80, 0.28),
		Color(0.52, 0.30, 0.58), BlockType.Pattern.METAL, 4.0, 2, &"theme_avian", &"accent", &"step_metal") \
		.glows(6, 0.8).tag(&"decor").tag(&"light_source")
	PsBlocks.themed(reg, &"avian_brazier", "Avian Brazier", Color(0.86, 0.62, 0.24),
		Color(1.00, 0.56, 0.18), BlockType.Pattern.METAL, 2.4, 1, &"theme_avian", &"accent", &"step_metal") \
		.glows(13, 1.0).tag(&"light_source").tag(&"metal")
	PsBlocks.themed(reg, &"avian_seal", "Avian Sanctum Seal", Color(0.70, 0.56, 0.30),
		Color(0.94, 0.82, 0.34), BlockType.Pattern.CRYSTAL, 60.0, 99, &"theme_avian", &"locked") \
		.glows(3, 0.5).tag(&"quest_locked")


# ------------------------------------------------------------------ floran hut
static func _floran(reg) -> void:
	PsBlocks.themed(reg, &"floran_wood", "Floran Hut Wall", Color(0.42, 0.44, 0.24),
		Color(0.30, 0.32, 0.16), BlockType.Pattern.ORGANIC, 2.0, 0, &"theme_floran", &"wall", &"step_wood") \
		.tag(&"organic").flags({"flammable": true})
	PsBlocks.themed(reg, &"floran_floor", "Floran Hut Floor", Color(0.50, 0.38, 0.22),
		Color(0.36, 0.27, 0.15), BlockType.Pattern.PLANK, 1.6, 0, &"theme_floran", &"floor", &"step_wood") \
		.tag(&"wood").flags({"flammable": true})
	PsBlocks.themed(reg, &"floran_totem", "Floran Bone Totem", Color(0.88, 0.84, 0.72),
		Color(0.68, 0.22, 0.26), BlockType.Pattern.ORGANIC, 2.4, 1, &"theme_floran", &"accent", &"step_wood") \
		.tag(&"decor").tag(&"organic")
	PsBlocks.themed(reg, &"floran_bone", "Floran Bonework", Color(0.86, 0.82, 0.70),
		Color(0.60, 0.56, 0.46), BlockType.Pattern.ORGANIC, 2.2, 1, &"theme_floran", &"wall", &"step_wood") \
		.tag(&"organic")
	PsBlocks.themed(reg, &"floran_ward", "Floran Blood Ward", Color(0.34, 0.16, 0.18),
		Color(0.72, 0.86, 0.28), BlockType.Pattern.ORGANIC, 60.0, 99, &"theme_floran", &"locked", &"step_wood") \
		.glows(4, 0.7).tag(&"quest_locked")


# --------------------------------------------------------------- glitch castle
static func _glitch(reg) -> void:
	PsBlocks.themed(reg, &"glitch_stone", "Glitch Castle Wall", Color(0.44, 0.44, 0.48),
		Color(0.30, 0.30, 0.34), BlockType.Pattern.BRICK, 4.4, 2, &"theme_glitch", &"wall") \
		.tag(&"stone")
	PsBlocks.themed(reg, &"glitch_stone_mossy", "Glitch Castle Floor", Color(0.36, 0.36, 0.40),
		Color(0.25, 0.25, 0.29), BlockType.Pattern.STRATA, 3.6, 2, &"theme_glitch", &"floor") \
		.tag(&"stone")
	PsBlocks.themed(reg, &"glitch_banner", "Glitch Banner", Color(0.24, 0.30, 0.62),
		Color(0.88, 0.76, 0.30), BlockType.Pattern.CLOTH, 1.0, 0, &"theme_glitch", &"accent", &"step_wood") \
		.tag(&"cloth").tag(&"decor").flags({"flammable": true, "opaque": false})
	PsBlocks.themed(reg, &"glitch_circuit", "Glitch Arcane Circuit", Color(0.22, 0.24, 0.32),
		Color(0.46, 0.86, 0.96), BlockType.Pattern.CIRCUIT, 3.8, 2, &"theme_glitch", &"accent") \
		.glows(6, 0.9).tag(&"light_source")
	PsBlocks.themed(reg, &"glitch_gate", "Glitch Portcullis", Color(0.30, 0.32, 0.36),
		Color(0.52, 0.54, 0.58), BlockType.Pattern.METAL, 60.0, 99, &"theme_glitch", &"locked", &"step_metal") \
		.tag(&"metal").tag(&"door_frame")


# ----------------------------------------------------------- hylotl ocean city
static func _hylotl(reg) -> void:
	PsBlocks.themed(reg, &"hylotl_stone", "Hylotl City Wall", Color(0.86, 0.90, 0.90),
		Color(0.34, 0.62, 0.62), BlockType.Pattern.FLAT, 3.2, 1, &"theme_hylotl", &"wall", &"step_glass")
	PsBlocks.themed(reg, &"hylotl_tile", "Hylotl City Floor", Color(0.30, 0.54, 0.58),
		Color(0.20, 0.40, 0.44), BlockType.Pattern.BRICK, 2.8, 1, &"theme_hylotl", &"floor", &"step_stone")
	PsBlocks.themed(reg, &"sea_lantern", "Hylotl Reef Lantern", Color(0.38, 0.86, 0.86),
		Color(0.90, 0.42, 0.56), BlockType.Pattern.CRYSTAL, 2.0, 1, &"theme_hylotl", &"accent", &"step_glass") \
		.glows(11, 1.0).tag(&"decor").tag(&"light_source").tag(&"biome_ocean")
	PsBlocks.themed(reg, &"hylotl_paper", "Hylotl Paper Screen", Color(0.94, 0.92, 0.84),
		Color(0.40, 0.34, 0.28), BlockType.Pattern.CLOTH, 0.8, 0, &"theme_hylotl", &"wall", &"step_wood") \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true, "flammable": true}).tag(&"cloth")
	PsBlocks.themed(reg, &"hylotl_seal", "Hylotl Pressure Seal", Color(0.22, 0.42, 0.50),
		Color(0.66, 0.90, 0.92), BlockType.Pattern.METAL, 60.0, 99, &"theme_hylotl", &"locked", &"step_metal") \
		.tag(&"metal").tag(&"door_frame")


# ---------------------------------------------------------------- ancient vault
static func _ancient(reg) -> void:
	PsBlocks.themed(reg, &"ancient_stone", "Ancient Vault Wall", Color(0.16, 0.14, 0.22),
		Color(0.72, 0.60, 0.28), BlockType.Pattern.STRATA, 7.0, 4, &"theme_ancient", &"wall") \
		.tag(&"stone").flags({"blast_resistance": 800.0})
	PsBlocks.themed(reg, &"ancient_tile", "Ancient Vault Floor", Color(0.13, 0.12, 0.18),
		Color(0.50, 0.42, 0.22), BlockType.Pattern.BRICK, 6.2, 4, &"theme_ancient", &"floor") \
		.tag(&"stone").flags({"blast_resistance": 700.0})
	PsBlocks.themed(reg, &"ancient_glyph", "Ancient Glyph", Color(0.18, 0.16, 0.26),
		Color(0.94, 0.82, 0.36), BlockType.Pattern.CIRCUIT, 6.0, 4, &"theme_ancient", &"accent") \
		.glows(9, 1.0).tag(&"decor").tag(&"light_source") \
		.flags({"damage_element": Const.ELEM_COSMIC})
	PsBlocks.themed(reg, &"ancient_light", "Ancient Rune Light", Color(0.16, 0.14, 0.22),
		Color(1.00, 0.88, 0.44), BlockType.Pattern.CRYSTAL, 5.0, 4, &"theme_ancient", &"accent") \
		.glows(14, 1.0).tag(&"light_source")
	PsBlocks.themed(reg, &"ancient_seal", "Ancient Vault Seal", Color(0.10, 0.09, 0.16),
		Color(1.00, 0.86, 0.40), BlockType.Pattern.CRYSTAL, 60.0, 99, &"theme_ancient", &"locked") \
		.glows(6, 1.0).tag(&"quest_locked").tag(&"marker")
