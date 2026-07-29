## Stone family: the rock the whole planet is carved out of.
##
## Three groups live here:
##   * **Common rock** — granite, basalt, slate … cosmetic variety that the
##     terrain agent can band or blotch freely. All drop themselves.
##   * **Strata rock** — `crust_stone` → `mantle_stone` → `deepstone` →
##     `corestone`. These carry the `stratum_*` tags and are the *hosts* the
##     ore agent should embed ores into at each depth; hardness and tool tier
##     climb with depth so digging deep genuinely needs better picks.
##   * **Planet rock** — moonstone, ferrozium rock, hellstone … tagged with the
##     `biome_*` the planet agent generates them on.
##
## Loose material (gravel, ash) sets `falls` so the liquid/falling-block sim
## picks it up via `World.set_block`.
extends RefCounted


static func register_all(reg) -> void:
	_common(reg)
	_strata(reg)
	_loose(reg)
	_planetary(reg)


# ------------------------------------------------------------- common bedrock
static func _common(reg) -> void:
	PsBlocks.rock(reg, &"granite", "Granite", Color(0.63, 0.45, 0.42),
		Color(0.50, 0.34, 0.32), BlockType.Pattern.SPECKLE, 2.0, 0) \
		.tag(&"stratum_upper")
	PsBlocks.rock(reg, &"diorite", "Diorite", Color(0.80, 0.79, 0.78),
		Color(0.55, 0.55, 0.58), BlockType.Pattern.SPECKLE, 1.9, 0) \
		.tag(&"stratum_upper")
	PsBlocks.rock(reg, &"andesite", "Andesite", Color(0.52, 0.53, 0.55),
		Color(0.40, 0.41, 0.44), BlockType.Pattern.SPECKLE, 1.8, 0) \
		.tag(&"stratum_upper")
	PsBlocks.rock(reg, &"basalt", "Basalt", Color(0.24, 0.24, 0.27),
		Color(0.16, 0.16, 0.19), BlockType.Pattern.STRATA, 2.4, 1) \
		.tag(&"stratum_mid").tag(&"biome_magma")
	PsBlocks.rock(reg, &"slate", "Slate", Color(0.34, 0.36, 0.42),
		Color(0.25, 0.27, 0.33), BlockType.Pattern.STRATA, 1.7, 0) \
		.tag(&"stratum_mid")
	PsBlocks.rock(reg, &"shale", "Shale", Color(0.38, 0.37, 0.34),
		Color(0.28, 0.27, 0.25), BlockType.Pattern.STRATA, 1.3, 0) \
		.tag(&"stratum_upper")
	PsBlocks.rock(reg, &"limestone", "Limestone", Color(0.80, 0.77, 0.66),
		Color(0.66, 0.63, 0.53), BlockType.Pattern.NOISE, 1.4, 0) \
		.tag(&"stratum_upper").tag(&"cave_decor")
	PsBlocks.rock(reg, &"chalk", "Chalk", Color(0.92, 0.91, 0.87),
		Color(0.80, 0.79, 0.75), BlockType.Pattern.NOISE, 0.9, 0) \
		.tag(&"stratum_surface")
	PsBlocks.rock(reg, &"marble", "Marble", Color(0.90, 0.89, 0.91),
		Color(0.68, 0.68, 0.74), BlockType.Pattern.STRATA, 2.1, 1) \
		.tag(&"stratum_mid")
	PsBlocks.rock(reg, &"quartzite", "Quartzite", Color(0.86, 0.84, 0.80),
		Color(0.70, 0.70, 0.72), BlockType.Pattern.CRYSTAL, 2.3, 1) \
		.tag(&"stratum_deep")
	PsBlocks.rock(reg, &"schist", "Schist", Color(0.45, 0.47, 0.43),
		Color(0.33, 0.35, 0.32), BlockType.Pattern.STRATA, 2.0, 1) \
		.tag(&"stratum_deep")
	PsBlocks.rock(reg, &"gneiss", "Gneiss", Color(0.58, 0.53, 0.50),
		Color(0.40, 0.36, 0.34), BlockType.Pattern.STRATA, 2.2, 1) \
		.tag(&"stratum_deep")
	PsBlocks.rock(reg, &"tuff", "Tuff", Color(0.42, 0.40, 0.36),
		Color(0.31, 0.30, 0.27), BlockType.Pattern.NOISE, 1.2, 0) \
		.tag(&"stratum_upper").tag(&"biome_magma")
	PsBlocks.rock(reg, &"pumice", "Pumice", Color(0.72, 0.69, 0.64),
		Color(0.56, 0.54, 0.50), BlockType.Pattern.SPECKLE, 0.7, 0) \
		.tag(&"biome_magma").flags({"blast_resistance": 0.3})
	PsBlocks.rock(reg, &"mossy_stone", "Mossy Stone", Color(0.40, 0.48, 0.36),
		Color(0.30, 0.36, 0.28), BlockType.Pattern.NOISE, 1.5, 0, &"cobblestone") \
		.tag(&"cave_decor").tag(&"biome_forest")
	PsBlocks.rock(reg, &"bone_block", "Bone Rock", Color(0.87, 0.84, 0.74),
		Color(0.63, 0.60, 0.52), BlockType.Pattern.ORGANIC, 1.8, 1) \
		.drop(&"bone_shard", 1, 3).tag(&"cave_decor").tag(&"biome_barren")


# -------------------------------------------------------------- depth strata
static func _strata(reg) -> void:
	# The four ore-host rocks, one per depth band. Worldgen should fill:
	#   y 128..255 crust · 64..127 mantle · 24..63 deep · 1..23 core
	PsBlocks.rock(reg, &"crust_stone", "Crust Stone", Color(0.55, 0.52, 0.48),
		Color(0.42, 0.40, 0.37), BlockType.Pattern.NOISE, 1.4, 0, &"cobblestone") \
		.tag(&"stratum_surface")
	PsBlocks.rock(reg, &"mantle_stone", "Mantle Stone", Color(0.44, 0.40, 0.44),
		Color(0.32, 0.29, 0.33), BlockType.Pattern.NOISE, 2.2, 1, &"cobblestone") \
		.tag(&"stratum_mid")
	PsBlocks.rock(reg, &"deepstone", "Deepstone", Color(0.27, 0.27, 0.33),
		Color(0.18, 0.18, 0.23), BlockType.Pattern.STRATA, 3.4, 2, &"deepstone") \
		.tag(&"stratum_deep")
	PsBlocks.rock(reg, &"corestone", "Corestone", Color(0.20, 0.14, 0.16),
		Color(0.34, 0.14, 0.10), BlockType.Pattern.STRATA, 5.0, 4, &"corestone") \
		.tag(&"stratum_core").flags({"blast_resistance": 24.0})
	PsBlocks.rock(reg, &"magmarock", "Magmarock", Color(0.32, 0.16, 0.13),
		Color(0.85, 0.32, 0.10), BlockType.Pattern.NOISE, 3.0, 3) \
		.glows(5, 0.5).tag(&"stratum_core").tag(&"biome_magma")
	PsBlocks.rock(reg, &"obsidian", "Obsidian", Color(0.11, 0.09, 0.16),
		Color(0.20, 0.16, 0.28), BlockType.Pattern.CRYSTAL, 12.0, 3) \
		.tag(&"stratum_core").tag(&"biome_magma").flags({"blast_resistance": 400.0})
	PsBlocks.rock(reg, &"geode_shell", "Geode Shell", Color(0.46, 0.44, 0.52),
		Color(0.66, 0.55, 0.82), BlockType.Pattern.CRYSTAL, 2.6, 2, &"cobblestone") \
		.drop(&"crystal_shard", 1, 2, 0.4).tag(&"cave_decor").tag(&"stratum_deep")


# ------------------------------------------------------------ loose material
static func _loose(reg) -> void:
	reg.define(&"gravel", "Gravel").look(Color(0.46, 0.45, 0.44), BlockType.Pattern.SPECKLE, Color(0.34, 0.33, 0.32)) \
		.mining(0.6, &"shovel", 0).sounds(&"step_sand").drop(&"gravel") \
		.drop(&"flint", 1, 1, 0.12).in_category(&"natural") \
		.tag(&"stone").tag(&"falls").tag(&"terrain_fill").flags({"falls": true})
	reg.define(&"clay", "Clay").look(Color(0.62, 0.60, 0.64), BlockType.Pattern.NOISE, Color(0.50, 0.48, 0.53)) \
		.mining(0.7, &"shovel", 0).sounds(&"step_dirt").drop(&"clay_lump", 3, 4) \
		.in_category(&"natural").tag(&"soil").tag(&"biome_ocean")
	reg.define(&"mud", "Mud").look(Color(0.29, 0.22, 0.16), BlockType.Pattern.NOISE, Color(0.21, 0.16, 0.11)) \
		.mining(0.6, &"shovel", 0).sounds(&"step_dirt").in_category(&"natural") \
		.tag(&"soil").tag(&"sticky").tag(&"biome_jungle").flags({"friction": 0.55})
	reg.define(&"ash", "Ash").look(Color(0.36, 0.35, 0.34), BlockType.Pattern.SAND, Color(0.26, 0.25, 0.24)) \
		.mining(0.35, &"shovel", 0).sounds(&"step_sand").in_category(&"natural") \
		.tag(&"ash").tag(&"falls").tag(&"biome_magma").flags({"falls": true})
	reg.define(&"cinder", "Cinder").look(Color(0.22, 0.19, 0.18), BlockType.Pattern.SPECKLE, Color(0.55, 0.24, 0.08)) \
		.mining(0.5, &"shovel", 0).sounds(&"step_sand").glows(3, 0.35) \
		.in_category(&"natural").tag(&"ash").tag(&"falls").tag(&"biome_magma") \
		.flags({"falls": true, "damage_on_touch": 1.0, "damage_element": Const.ELEM_FIRE})
	reg.define(&"scoria", "Scoria").look(Color(0.30, 0.20, 0.19), BlockType.Pattern.SPECKLE, Color(0.19, 0.12, 0.12)) \
		.mining(1.6, &"pickaxe", 1).sounds(&"step_stone").in_category(&"natural") \
		.tag(&"stone").tag(&"biome_magma").tag(&"terrain_fill")
	reg.define(&"flint_nodule", "Flint Nodule").look(Color(0.44, 0.43, 0.46), BlockType.Pattern.ORE, Color(0.22, 0.22, 0.26)) \
		.mining(1.7, &"pickaxe", 0).sounds(&"step_stone").drop(&"flint", 2, 4) \
		.in_category(&"natural").tag(&"stone").tag(&"cave_decor")


# ------------------------------------------------------- planet-specific rock
static func _planetary(reg) -> void:
	PsBlocks.rock(reg, &"moon_rock", "Moonstone", Color(0.72, 0.74, 0.80),
		Color(0.55, 0.58, 0.66), BlockType.Pattern.NOISE, 2.0, 1) \
		.tag(&"biome_moon").tag(&"terrain_fill")
	PsBlocks.rock(reg, &"regolith", "Regolith", Color(0.60, 0.59, 0.56),
		Color(0.46, 0.45, 0.43), BlockType.Pattern.SAND, 0.5, 0) \
		.sounds(&"step_sand").tag(&"biome_moon").tag(&"falls").flags({"falls": true})
	PsBlocks.rock(reg, &"ferrozium_rock", "Ferrozium Rock", Color(0.26, 0.40, 0.42),
		Color(0.30, 0.86, 0.78), BlockType.Pattern.SPECKLE, 3.6, 4) \
		.glows(4, 0.6).tag(&"biome_alien").tag(&"stratum_deep")
	PsBlocks.rock(reg, &"hellstone", "Hellstone", Color(0.44, 0.13, 0.10),
		Color(0.98, 0.48, 0.12), BlockType.Pattern.NOISE, 4.2, 3) \
		.glows(8, 0.9).tag(&"biome_magma").tag(&"stratum_core").tag(&"hazard") \
		.flags({"damage_on_touch": 3.0, "damage_element": Const.ELEM_FIRE})
	PsBlocks.rock(reg, &"ice_stone", "Permafrost Rock", Color(0.62, 0.72, 0.80),
		Color(0.46, 0.56, 0.66), BlockType.Pattern.ICE, 2.2, 1) \
		.sounds(&"step_snow").tag(&"biome_tundra").tag(&"ice").tag(&"terrain_fill")
	PsBlocks.rock(reg, &"toxic_stone", "Toxic Stone", Color(0.34, 0.42, 0.24),
		Color(0.52, 0.72, 0.24), BlockType.Pattern.SPECKLE, 1.8, 1) \
		.tag(&"biome_toxic").tag(&"terrain_fill")
	PsBlocks.rock(reg, &"desert_stone", "Desert Stone", Color(0.76, 0.62, 0.42),
		Color(0.60, 0.48, 0.32), BlockType.Pattern.STRATA, 1.5, 0) \
		.tag(&"biome_desert").tag(&"terrain_fill")
	PsBlocks.rock(reg, &"sandstone", "Sandstone", Color(0.82, 0.73, 0.50),
		Color(0.68, 0.60, 0.40), BlockType.Pattern.STRATA, 1.3, 0) \
		.sounds(&"step_sand").tag(&"biome_desert").tag(&"sand")
	PsBlocks.rock(reg, &"red_sandstone", "Red Sandstone", Color(0.72, 0.42, 0.26),
		Color(0.58, 0.33, 0.20), BlockType.Pattern.STRATA, 1.3, 0) \
		.sounds(&"step_sand").tag(&"biome_desert").tag(&"sand")
	PsBlocks.rock(reg, &"alien_rock", "Alien Stone", Color(0.36, 0.26, 0.46),
		Color(0.56, 0.36, 0.72), BlockType.Pattern.ORGANIC, 2.4, 2) \
		.tag(&"biome_alien").tag(&"terrain_fill")
	PsBlocks.rock(reg, &"prismatic_rock", "Prismatic Rock", Color(0.50, 0.62, 0.78),
		Color(0.86, 0.72, 0.96), BlockType.Pattern.CRYSTAL, 3.0, 3) \
		.glows(3, 0.4).drop(&"crystal_shard", 1, 3).tag(&"biome_alien").tag(&"crystal")
	PsBlocks.rock(reg, &"seafloor_rock", "Seafloor Rock", Color(0.30, 0.42, 0.46),
		Color(0.22, 0.32, 0.36), BlockType.Pattern.NOISE, 1.6, 0, &"cobblestone") \
		.tag(&"biome_ocean").tag(&"terrain_fill")
	PsBlocks.rock(reg, &"meteorite", "Meteorite", Color(0.24, 0.21, 0.20),
		Color(0.70, 0.55, 0.32), BlockType.Pattern.ORE, 6.0, 3) \
		.drop(&"raw_iron", 1, 2).drop(&"star_dust", 1, 2, 0.5) \
		.tag(&"biome_barren").tag(&"cave_decor").flags({"blast_resistance": 60.0})
	PsBlocks.rock(reg, &"savannah_stone", "Savannah Stone", Color(0.66, 0.55, 0.36),
		Color(0.52, 0.43, 0.28), BlockType.Pattern.NOISE, 1.5, 0, &"cobblestone") \
		.tag(&"biome_savannah").tag(&"terrain_fill")
	PsBlocks.rock(reg, &"crystal_stone", "Crystal Stone", Color(0.44, 0.54, 0.68),
		Color(0.74, 0.88, 1.00), BlockType.Pattern.CRYSTAL, 2.8, 2) \
		.glows(2, 0.3).drop(&"crystal_shard", 1, 2, 0.5).tag(&"crystal") \
		.tag(&"terrain_fill").tag(&"stratum_deep")
	PsBlocks.rock(reg, &"cracked_sandstone", "Cracked Sandstone", Color(0.74, 0.66, 0.46),
		Color(0.58, 0.52, 0.36), BlockType.Pattern.STRATA, 1.2, 0) \
		.sounds(&"step_sand").tag(&"sand").tag(&"biome_desert").tag(&"theme_ancient")
