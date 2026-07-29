## Soils, biome ground cover, sand, snow and ice.
##
## Conventions the terrain agent relies on:
##   * every `surface_cover` block drops the *soil* underneath it, never itself
##     (grass drops dirt), exactly like the core `grass` block;
##   * anything granular sets `falls` **and** carries the `falls` tag, so the
##     falling-block sim can be driven off either the flag or a tag query;
##   * ice is low-`friction` (slide) and snow is slightly high-`friction`
##     (trudge). Movement code multiplies ground speed by `friction`.
extends RefCounted


static func register_all(reg) -> void:
	_soils(reg)
	_covers(reg)
	_sands(reg)
	_cold(reg)


# --------------------------------------------------------------------- soils
static func _soil(reg, p_name: StringName, display: String, col: Color, alt: Color,
		biome: StringName, hardness: float = 0.5, drop_item: StringName = &"") -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, BlockType.Pattern.NOISE, alt)
	bt.mining(hardness, &"shovel", 0)
	bt.sounds(&"step_dirt")
	bt.in_category(&"natural").tag(&"soil").tag(&"terrain_fill")
	if biome != &"":
		bt.tag(biome)
	if drop_item != &"":
		bt.drop(drop_item)
	return bt


static func _soils(reg) -> void:
	_soil(reg, &"loam", "Loam", Color(0.38, 0.27, 0.17), Color(0.29, 0.20, 0.12), &"biome_forest", 0.45)
	_soil(reg, &"rich_soil", "Rich Soil", Color(0.28, 0.20, 0.13), Color(0.20, 0.14, 0.09), &"biome_jungle", 0.5)
	_soil(reg, &"silt", "Silt", Color(0.52, 0.46, 0.36), Color(0.41, 0.36, 0.28), &"biome_ocean", 0.4)
	_soil(reg, &"peat", "Peat", Color(0.22, 0.17, 0.12), Color(0.15, 0.12, 0.08), &"biome_forest", 0.5) \
		.tag(&"fuel").flags({"flammable": true})
	_soil(reg, &"ashen_soil", "Ashen Soil", Color(0.32, 0.29, 0.27), Color(0.24, 0.22, 0.20), &"biome_magma", 0.5)
	_soil(reg, &"charred_dirt", "Scorched Earth", Color(0.30, 0.19, 0.14), Color(0.22, 0.13, 0.10), &"biome_magma", 0.6)
	_soil(reg, &"alien_dirt", "Alien Soil", Color(0.32, 0.22, 0.38), Color(0.24, 0.16, 0.29), &"biome_alien", 0.6)
	_soil(reg, &"toxic_dirt", "Toxic Soil", Color(0.28, 0.32, 0.18), Color(0.20, 0.24, 0.13), &"biome_toxic", 0.55) \
		.tag(&"hazard").flags({"damage_on_touch": 0.5, "damage_element": Const.ELEM_POISON})
	_soil(reg, &"frozen_dirt", "Frozen Dirt", Color(0.44, 0.42, 0.44), Color(0.34, 0.33, 0.36), &"biome_tundra", 1.1) \
		.sounds(&"step_snow").drop(&"dirt")
	_soil(reg, &"desert_soil", "Desert Soil", Color(0.63, 0.49, 0.32), Color(0.50, 0.39, 0.25), &"biome_desert", 0.45)
	_soil(reg, &"savannah_soil", "Savannah Soil", Color(0.55, 0.44, 0.24), Color(0.43, 0.34, 0.19), &"biome_savannah", 0.45)
	_soil(reg, &"seabed_ooze", "Seabed Ooze", Color(0.24, 0.32, 0.32), Color(0.17, 0.24, 0.24), &"biome_ocean", 0.4) \
		.flags({"friction": 0.7})
	_soil(reg, &"mycelium", "Mycelium", Color(0.44, 0.38, 0.44), Color(0.60, 0.55, 0.62), &"biome_forest", 0.5) \
		.with_top(Color(0.62, 0.56, 0.64)).drop(&"dirt").tag(&"fungus")
	_soil(reg, &"moon_dust", "Lunar Dust", Color(0.58, 0.57, 0.55), Color(0.46, 0.45, 0.44), &"biome_moon", 0.35) \
		.sounds(&"step_sand").tag(&"falls").flags({"falls": true})


# ------------------------------------------------------------ surface covers
static func _cover(reg, p_name: StringName, display: String, soil: Color, top: Color,
		biome: StringName, drop_item: StringName = &"dirt") -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(soil, BlockType.Pattern.GRASS_TOP, soil.darkened(0.2))
	bt.with_top(top)
	bt.mining(0.6, &"shovel", 0)
	bt.sounds(&"step_grass")
	bt.drop(drop_item)
	bt.flags({"flammable": true})
	bt.in_category(&"natural").tag(&"soil").tag(&"surface_cover").tag(biome)
	return bt


static func _covers(reg) -> void:
	_cover(reg, &"forest_grass", "Forest Grass", Color(0.40, 0.28, 0.17), Color(0.30, 0.60, 0.24), &"biome_forest")
	_cover(reg, &"jungle_grass", "Jungle Grass", Color(0.26, 0.19, 0.12), Color(0.18, 0.56, 0.20), &"biome_jungle", &"rich_soil")
	_cover(reg, &"savannah_grass", "Savannah Grass", Color(0.52, 0.42, 0.23), Color(0.72, 0.68, 0.26), &"biome_savannah", &"savannah_soil")
	_cover(reg, &"tundra_grass", "Tundra Grass", Color(0.42, 0.40, 0.40), Color(0.46, 0.58, 0.44), &"biome_tundra", &"frozen_dirt")
	_cover(reg, &"alien_grass", "Alien Grass", Color(0.31, 0.21, 0.36), Color(0.62, 0.30, 0.82), &"biome_alien", &"alien_dirt") \
		.glows(2, 0.3)
	_cover(reg, &"toxic_grass", "Toxic Grass", Color(0.27, 0.31, 0.18), Color(0.56, 0.78, 0.20), &"biome_toxic", &"toxic_dirt")
	_cover(reg, &"ash_grass", "Ashen Grass", Color(0.31, 0.28, 0.26), Color(0.44, 0.40, 0.30), &"biome_magma", &"ashen_soil")
	_cover(reg, &"ocean_grass", "Seagrass Bed", Color(0.24, 0.31, 0.31), Color(0.24, 0.56, 0.44), &"biome_ocean", &"seabed_ooze") \
		.sounds(&"step_grass").flags({"flammable": false})
	_cover(reg, &"desert_grass", "Desert Scrub", Color(0.62, 0.48, 0.31), Color(0.60, 0.60, 0.32), &"biome_desert", &"desert_soil")
	_cover(reg, &"midnight_grass", "Midnight Grass", Color(0.20, 0.18, 0.24), Color(0.32, 0.26, 0.50), &"biome_alien") \
		.glows(1, 0.25)
	_cover(reg, &"glow_grass", "Glowgrass", Color(0.20, 0.26, 0.30), Color(0.30, 0.90, 0.78), &"biome_alien") \
		.glows(5, 0.8).tag(&"light_source")


# ---------------------------------------------------------------------- sand
static func _sand(reg, p_name: StringName, display: String, col: Color, alt: Color,
		biome: StringName) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, BlockType.Pattern.SAND, alt)
	bt.mining(0.4, &"shovel", 0)
	bt.sounds(&"step_sand")
	bt.flags({"falls": true})
	bt.in_category(&"natural").tag(&"sand").tag(&"falls").tag(&"terrain_fill").tag(biome)
	return bt


static func _sands(reg) -> void:
	_sand(reg, &"red_sand", "Red Sand", Color(0.78, 0.44, 0.26), Color(0.64, 0.35, 0.20), &"biome_desert")
	_sand(reg, &"white_sand", "White Sand", Color(0.94, 0.92, 0.86), Color(0.82, 0.80, 0.74), &"biome_ocean")
	_sand(reg, &"black_sand", "Black Sand", Color(0.22, 0.21, 0.22), Color(0.15, 0.15, 0.16), &"biome_magma")
	_sand(reg, &"alien_sand", "Alien Sand", Color(0.66, 0.50, 0.78), Color(0.53, 0.39, 0.64), &"biome_alien")
	_sand(reg, &"toxic_sand", "Toxic Sand", Color(0.66, 0.72, 0.34), Color(0.53, 0.58, 0.26), &"biome_toxic") \
		.tag(&"hazard").flags({"damage_on_touch": 0.5, "damage_element": Const.ELEM_POISON})
	_sand(reg, &"quicksand", "Quicksand", Color(0.70, 0.63, 0.44), Color(0.56, 0.50, 0.35), &"biome_desert") \
		.tag(&"sticky").drop(&"sand").flags({"friction": 0.25, "hardness": 0.3})
	_sand(reg, &"crystal_sand", "Crystal Sand", Color(0.80, 0.88, 0.96), Color(0.60, 0.74, 0.90), &"biome_tundra") \
		.glows(1, 0.25).tag(&"crystal")


# ---------------------------------------------------------------- snow & ice
static func _cold(reg) -> void:
	reg.define(&"snow", "Snow").look(Color(0.95, 0.96, 0.99), BlockType.Pattern.SAND, Color(0.84, 0.87, 0.94)) \
		.mining(0.3, &"shovel", 0).sounds(&"step_snow").drop(&"snowball", 2, 4) \
		.in_category(&"natural").tag(&"snow").tag(&"falls").tag(&"biome_tundra") \
		.tag(&"terrain_fill").flags({"falls": true, "friction": 0.88})
	reg.define(&"packed_snow", "Packed Snow").look(Color(0.90, 0.93, 0.98), BlockType.Pattern.NOISE, Color(0.78, 0.83, 0.92)) \
		.mining(0.8, &"shovel", 0).sounds(&"step_snow").in_category(&"natural") \
		.tag(&"snow").tag(&"biome_tundra").tag(&"terrain_fill").flags({"friction": 0.9})
	reg.define(&"snow_cover", "Snow Cover").look(Color(0.94, 0.95, 0.99), BlockType.Pattern.GRASS_TOP, Color(0.44, 0.42, 0.44)) \
		.with_top(Color(0.97, 0.98, 1.0)).mining(0.5, &"shovel", 0).sounds(&"step_snow") \
		.drop(&"frozen_dirt").in_category(&"natural").tag(&"snow").tag(&"surface_cover") \
		.tag(&"biome_tundra")
	reg.define(&"ice", "Ice").look(Color(0.70, 0.85, 0.96, 0.86), BlockType.Pattern.ICE, Color(0.56, 0.74, 0.92)) \
		.mode(BlockType.Render.TRANSPARENT).mining(0.9, &"pickaxe", 0).sounds(&"step_snow") \
		.drop(&"ice").in_category(&"natural").tag(&"ice").tag(&"slippery") \
		.tag(&"biome_tundra").tag(&"terrain_fill").flags({"friction": 0.35, "solid": true})
	reg.define(&"packed_ice", "Packed Ice").look(Color(0.62, 0.80, 0.94), BlockType.Pattern.ICE, Color(0.48, 0.68, 0.88)) \
		.mining(1.6, &"pickaxe", 1).sounds(&"step_snow").in_category(&"natural") \
		.tag(&"ice").tag(&"slippery").tag(&"biome_tundra").flags({"friction": 0.28})
	reg.define(&"blue_ice", "Blue Ice").look(Color(0.36, 0.62, 0.92), BlockType.Pattern.ICE, Color(0.26, 0.48, 0.80)) \
		.mining(2.6, &"pickaxe", 2).sounds(&"step_snow").glows(2, 0.25) \
		.in_category(&"natural").tag(&"ice").tag(&"slippery").tag(&"biome_tundra") \
		.flags({"friction": 0.18})
	reg.define(&"hail_gravel", "Hail Gravel").look(Color(0.78, 0.84, 0.90), BlockType.Pattern.SPECKLE, Color(0.62, 0.70, 0.80)) \
		.mining(0.45, &"shovel", 0).sounds(&"step_snow").drop(&"snowball", 1, 3) \
		.in_category(&"natural").tag(&"snow").tag(&"falls").tag(&"biome_tundra") \
		.flags({"falls": true})
