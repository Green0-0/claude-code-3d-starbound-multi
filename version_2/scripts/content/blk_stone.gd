extends RefCounted

## Stone family: the rock the planet is carved out of.
##
## Three groups: cosmetic **common rock** the terrain shaper bands freely, the
## four **strata hosts** (`crust_stone` -> `mantle_stone` -> `deepstone` ->
## `corestone`) that ores are embedded into at each depth, and **planet rock**
## tagged with the biome that generates it. Hardness and tool tier climb with
## depth, so digging deep genuinely needs a better pick.


static func rock(p_name: StringName, display: String, col: Color, alt: Color,
		pat: int, hard: float, tier := 0, drop_item: StringName = &"") -> Blocks.Def:
	var b := Blocks.define(p_name, display)
	b.look(col, pat, alt).mining(hard, &"pickaxe", tier).sounds(&"step_stone") \
		.in_category(&"natural").tag(&"stone").tag(&"terrain_fill")
	b.drop(drop_item if drop_item != &"" else p_name)
	return b


static func register_all() -> void:
	_common()
	_strata()
	_loose()
	_planetary()


static func _common() -> void:
	rock(&"granite", "Granite", Color(0.63, 0.45, 0.42), Color(0.50, 0.34, 0.32),
		Blocks.Pattern.SPECKLE, 1.0, 0).tag(&"stratum_upper")
	rock(&"basalt", "Basalt", Color(0.24, 0.24, 0.27), Color(0.16, 0.16, 0.19),
		Blocks.Pattern.STRATA, 1.2, 1).tag(&"stratum_mid").tag(&"biome_magma")
	rock(&"slate", "Slate", Color(0.34, 0.36, 0.42), Color(0.25, 0.27, 0.33),
		Blocks.Pattern.STRATA, 0.85, 0).tag(&"stratum_mid")
	rock(&"limestone", "Limestone", Color(0.80, 0.77, 0.66), Color(0.66, 0.63, 0.53),
		Blocks.Pattern.NOISE, 0.7, 0).tag(&"stratum_upper").tag(&"cave_decor")
	rock(&"bone_block", "Bone Rock", Color(0.87, 0.84, 0.74), Color(0.63, 0.60, 0.52),
		Blocks.Pattern.ORGANIC, 0.9, 1, &"bone_shard") \
		.drop(&"bone_shard", 1, 2).tag(&"cave_decor").tag(&"biome_barren")


static func _strata() -> void:
	rock(&"crust_stone", "Crust Stone", Color(0.55, 0.52, 0.48), Color(0.42, 0.40, 0.37),
		Blocks.Pattern.NOISE, 0.7, 0, &"cobblestone").tag(&"stratum_surface")
	rock(&"mantle_stone", "Mantle Stone", Color(0.44, 0.40, 0.44), Color(0.32, 0.29, 0.33),
		Blocks.Pattern.NOISE, 1.1, 1, &"cobblestone").tag(&"stratum_mid")
	rock(&"deepstone", "Deepstone", Color(0.27, 0.27, 0.33), Color(0.18, 0.18, 0.23),
		Blocks.Pattern.STRATA, 1.7, 2).tag(&"stratum_deep")
	rock(&"corestone", "Corestone", Color(0.20, 0.14, 0.16), Color(0.34, 0.14, 0.10),
		Blocks.Pattern.STRATA, 2.5, 4).tag(&"stratum_core") \
		.flags({"blast_resistance": 24.0})
	rock(&"magmarock", "Magmarock", Color(0.32, 0.16, 0.13), Color(0.85, 0.32, 0.10),
		Blocks.Pattern.NOISE, 1.5, 3).glows(5, 0.5) \
		.tag(&"stratum_core").tag(&"biome_magma")
	rock(&"geode_shell", "Geode Shell", Color(0.46, 0.44, 0.52), Color(0.66, 0.55, 0.82),
		Blocks.Pattern.CRYSTAL, 1.3, 2, &"cobblestone") \
		.drop(&"crystal_shard", 1, 2, 0.4).tag(&"cave_decor").tag(&"stratum_deep")


static func _loose() -> void:
	Blocks.define(&"ash", "Ash") \
		.look(Color(0.36, 0.35, 0.34), Blocks.Pattern.SAND, Color(0.26, 0.25, 0.24)) \
		.mining(0.2, &"shovel", 0).sounds(&"step_sand").drop(&"ash") \
		.in_category(&"natural").tag(&"ash").tag(&"falls").tag(&"biome_magma") \
		.tag(&"terrain_fill").flags({"falls": true})
	Blocks.define(&"cinder", "Cinder") \
		.look(Color(0.22, 0.19, 0.18), Blocks.Pattern.SPECKLE, Color(0.55, 0.24, 0.08)) \
		.mining(0.25, &"shovel", 0).sounds(&"step_sand").glows(3, 0.35).drop(&"cinder") \
		.in_category(&"natural").tag(&"ash").tag(&"falls").tag(&"biome_magma") \
		.flags({"falls": true, "damage_on_touch": 1.0, "damage_element": Blocks.ELEM_FIRE})
	Blocks.define(&"flint_nodule", "Flint Nodule") \
		.look(Color(0.44, 0.43, 0.46), Blocks.Pattern.ORE, Color(0.22, 0.22, 0.26)) \
		.mining(0.85, &"pickaxe", 0).sounds(&"step_stone").drop(&"flint", 2, 4) \
		.in_category(&"natural").tag(&"stone").tag(&"cave_decor")


static func _planetary() -> void:
	rock(&"moon_rock", "Moonstone", Color(0.72, 0.74, 0.80), Color(0.55, 0.58, 0.66),
		Blocks.Pattern.NOISE, 1.0, 1).tag(&"biome_moon")
	rock(&"hellstone", "Hellstone", Color(0.44, 0.13, 0.10), Color(0.98, 0.48, 0.12),
		Blocks.Pattern.NOISE, 2.1, 3).glows(8, 0.9) \
		.tag(&"biome_magma").tag(&"stratum_core").tag(&"hazard") \
		.flags({"damage_on_touch": 3.0, "damage_element": Blocks.ELEM_FIRE})
	rock(&"toxic_stone", "Toxic Stone", Color(0.34, 0.42, 0.24), Color(0.52, 0.72, 0.24),
		Blocks.Pattern.SPECKLE, 0.9, 1).tag(&"biome_toxic")
	rock(&"sandstone", "Sandstone", Color(0.82, 0.73, 0.50), Color(0.68, 0.60, 0.40),
		Blocks.Pattern.STRATA, 0.65, 0).sounds(&"step_sand") \
		.tag(&"biome_desert").tag(&"sand")
	rock(&"alien_rock", "Alien Stone", Color(0.36, 0.26, 0.46), Color(0.56, 0.36, 0.72),
		Blocks.Pattern.ORGANIC, 1.2, 2).tag(&"biome_alien")
	rock(&"ice_stone", "Permafrost Rock", Color(0.62, 0.72, 0.80), Color(0.46, 0.56, 0.66),
		Blocks.Pattern.ICE, 1.1, 1).sounds(&"step_snow") \
		.tag(&"biome_tundra").tag(&"ice")
	rock(&"meteorite", "Meteorite", Color(0.24, 0.21, 0.20), Color(0.70, 0.55, 0.32),
		Blocks.Pattern.ORE, 3.0, 3, &"raw_iron") \
		.drop(&"star_dust", 1, 2, 0.5).tag(&"biome_barren").tag(&"cave_decor") \
		.flags({"blast_resistance": 60.0})
