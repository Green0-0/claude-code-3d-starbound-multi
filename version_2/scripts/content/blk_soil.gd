extends RefCounted

## Soils, biome ground cover, sand, snow and ice.
##
## Conventions the terrain shaper relies on:
##   * every `surface_cover` block drops the soil underneath it, never itself;
##   * anything granular sets `falls` **and** carries the `falls` tag, so the
##     falling-block sim can be driven off either;
##   * `friction` multiplies ground acceleration — ice is low (slide), snow is
##     high (trudge). The player controller reads the number, the tags
##     `slippery` / `sticky` tell you which case it is.


static func soil(p_name: StringName, display: String, col: Color, alt: Color,
		biome: StringName, hard := 0.28, drop_item: StringName = &"") -> Blocks.Def:
	var b := Blocks.define(p_name, display)
	b.look(col, Blocks.Pattern.NOISE, alt).mining(hard, &"shovel", 0) \
		.sounds(&"step_dirt").drop(drop_item if drop_item != &"" else p_name) \
		.in_category(&"natural").tag(&"soil").tag(&"terrain_fill")
	if biome != &"":
		b.tag(biome)
	return b


static func cover(p_name: StringName, display: String, dirt: Color, top: Color,
		biome: StringName, drop_item: StringName = &"dirt") -> Blocks.Def:
	return Blocks.define(p_name, display) \
		.look(dirt, Blocks.Pattern.GRASS_TOP, dirt.darkened(0.2)).with_top(top) \
		.mining(0.32, &"shovel", 0).sounds(&"step_grass").drop(drop_item) \
		.in_category(&"natural").tag(&"soil").tag(&"surface_cover").tag(biome) \
		.flags({"flammable": true})


static func sand_like(p_name: StringName, display: String, col: Color, alt: Color,
		biome: StringName) -> Blocks.Def:
	return Blocks.define(p_name, display) \
		.look(col, Blocks.Pattern.SAND, alt).mining(0.24, &"shovel", 0) \
		.sounds(&"step_sand").drop(p_name).in_category(&"natural") \
		.tag(&"sand").tag(&"falls").tag(&"terrain_fill").tag(biome) \
		.flags({"falls": true})


static func register_all() -> void:
	_soils()
	_covers()
	_sands()
	_cold()


static func _soils() -> void:
	soil(&"loam", "Loam", Color(0.38, 0.27, 0.17), Color(0.29, 0.20, 0.12), &"biome_forest")
	soil(&"rich_soil", "Rich Soil", Color(0.28, 0.20, 0.13), Color(0.20, 0.14, 0.09), &"biome_jungle")
	soil(&"silt", "Silt", Color(0.52, 0.46, 0.36), Color(0.41, 0.36, 0.28), &"biome_ocean")
	soil(&"alien_dirt", "Alien Soil", Color(0.32, 0.22, 0.38), Color(0.24, 0.16, 0.29), &"biome_alien", 0.34)
	soil(&"toxic_dirt", "Toxic Soil", Color(0.28, 0.32, 0.18), Color(0.20, 0.24, 0.13), &"biome_toxic", 0.32) \
		.tag(&"hazard").flags({"damage_on_touch": 0.5, "damage_element": Blocks.ELEM_POISON})
	soil(&"frozen_dirt", "Frozen Dirt", Color(0.44, 0.42, 0.44), Color(0.34, 0.33, 0.36), &"biome_tundra", 0.6, &"dirt") \
		.sounds(&"step_snow")
	soil(&"desert_soil", "Desert Soil", Color(0.63, 0.49, 0.32), Color(0.50, 0.39, 0.25), &"biome_desert")
	soil(&"savannah_soil", "Savannah Soil", Color(0.55, 0.44, 0.24), Color(0.43, 0.34, 0.19), &"biome_savannah")
	soil(&"moon_dust", "Lunar Dust", Color(0.58, 0.57, 0.55), Color(0.46, 0.45, 0.44), &"biome_moon", 0.2) \
		.sounds(&"step_sand").tag(&"falls").flags({"falls": true})


static func _covers() -> void:
	cover(&"forest_grass", "Forest Grass", Color(0.40, 0.28, 0.17), Color(0.30, 0.60, 0.24), &"biome_forest")
	cover(&"jungle_grass", "Jungle Grass", Color(0.26, 0.19, 0.12), Color(0.18, 0.56, 0.20), &"biome_jungle", &"rich_soil")
	cover(&"savannah_grass", "Savannah Grass", Color(0.52, 0.42, 0.23), Color(0.72, 0.68, 0.26), &"biome_savannah", &"savannah_soil")
	cover(&"tundra_grass", "Tundra Grass", Color(0.42, 0.40, 0.40), Color(0.46, 0.58, 0.44), &"biome_tundra", &"frozen_dirt")
	cover(&"alien_grass", "Alien Grass", Color(0.31, 0.21, 0.36), Color(0.62, 0.30, 0.82), &"biome_alien", &"alien_dirt") \
		.glows(2, 0.3)
	cover(&"toxic_grass", "Toxic Grass", Color(0.27, 0.31, 0.18), Color(0.56, 0.78, 0.20), &"biome_toxic", &"toxic_dirt")
	cover(&"desert_grass", "Desert Scrub", Color(0.62, 0.48, 0.31), Color(0.60, 0.60, 0.32), &"biome_desert", &"desert_soil")
	cover(&"glow_grass", "Glowgrass", Color(0.20, 0.26, 0.30), Color(0.30, 0.90, 0.78), &"biome_alien") \
		.glows(5, 0.8).tag(&"light_source")


static func _sands() -> void:
	sand_like(&"red_sand", "Red Sand", Color(0.78, 0.44, 0.26), Color(0.64, 0.35, 0.20), &"biome_desert")
	sand_like(&"white_sand", "White Sand", Color(0.94, 0.92, 0.86), Color(0.82, 0.80, 0.74), &"biome_ocean")
	sand_like(&"alien_sand", "Alien Sand", Color(0.66, 0.50, 0.78), Color(0.53, 0.39, 0.64), &"biome_alien")
	sand_like(&"toxic_sand", "Toxic Sand", Color(0.66, 0.72, 0.34), Color(0.53, 0.58, 0.26), &"biome_toxic") \
		.tag(&"hazard").flags({"damage_on_touch": 0.5, "damage_element": Blocks.ELEM_POISON})


static func _cold() -> void:
	Blocks.define(&"packed_snow", "Packed Snow") \
		.look(Color(0.90, 0.93, 0.98), Blocks.Pattern.NOISE, Color(0.78, 0.83, 0.92)) \
		.mining(0.4, &"shovel", 0).sounds(&"step_snow").drop(&"packed_snow") \
		.in_category(&"natural").tag(&"snow").tag(&"biome_tundra").tag(&"terrain_fill") \
		.flags({"friction": 0.9})
	Blocks.define(&"snow_cover", "Snow Cover") \
		.look(Color(0.66, 0.64, 0.64), Blocks.Pattern.GRASS_TOP, Color(0.44, 0.42, 0.44)) \
		.with_top(Color(0.97, 0.98, 1.0)).mining(0.26, &"shovel", 0) \
		.sounds(&"step_snow").drop(&"frozen_dirt").in_category(&"natural") \
		.tag(&"snow").tag(&"surface_cover").tag(&"biome_tundra")
	Blocks.define(&"packed_ice", "Packed Ice") \
		.look(Color(0.62, 0.80, 0.94), Blocks.Pattern.ICE, Color(0.48, 0.68, 0.88)) \
		.mining(0.8, &"pickaxe", 1).sounds(&"step_snow").drop(&"packed_ice") \
		.in_category(&"natural").tag(&"ice").tag(&"slippery").tag(&"biome_tundra") \
		.flags({"friction": 0.28})
	Blocks.define(&"blue_ice", "Blue Ice") \
		.look(Color(0.36, 0.62, 0.92), Blocks.Pattern.ICE, Color(0.26, 0.48, 0.80)) \
		.mining(1.3, &"pickaxe", 2).sounds(&"step_snow").glows(2, 0.25).drop(&"blue_ice") \
		.in_category(&"natural").tag(&"ice").tag(&"slippery").tag(&"biome_tundra") \
		.flags({"friction": 0.18})
