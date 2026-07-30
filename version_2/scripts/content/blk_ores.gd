extends RefCounted

## The mining progression.
##
## Every ore is `Pattern.ORE` — host rock speckled with the metal colour — and is
## gated by tool tier, so a copper pickaxe returns nothing at all from a titanium
## vein (`Def.roll_drops` checks the tier before it rolls a single drop).
##
##   | tier | pickaxe        | unlocks                                        |
##   |------|----------------|------------------------------------------------|
##   | 0    | stone / copper | coal copper iron tin salt                      |
##   | 1    | iron           | lead silver gold silicon sulphur amethyst topaz|
##   | 2    | tungsten       | tungsten titanium platinum cerulium erchius    |
##   | 3    | titanium       | durasteel uranium ruby sapphire emerald diamond|
##   | 4    | durasteel      | plutonium aegisalt ferozium violium            |
##   | 5    | aegisalt-class | rubium solarium prisilite                      |
##   | 6    | solarium-class | core fragment                                  |
##
## Exotic ores from tier 4 up are faintly emissive, so a deep cave glitters
## before your torch reaches it.

const HOST := Color(0.50, 0.50, 0.53)


static func ore(p_name: StringName, display: String, host: Color, metal: Color,
		hard: float, tier: int, drop_item: StringName, lo := 1, hi := 1,
		light := 0, emis := 0.0) -> Blocks.Def:
	var b := Blocks.define(p_name, display)
	b.look(host, Blocks.Pattern.ORE, metal).mining(hard, &"pickaxe", tier) \
		.drop(drop_item, lo, hi).sounds(&"step_stone") \
		.in_category(&"ore").tag(&"ore").tag(&"stone")
	if light > 0:
		b.glows(light, emis)
	return b


static func register_all() -> void:
	_mundane()
	_industrial()
	_exotic()
	_gems()


static func _mundane() -> void:
	ore(&"copper_ore", "Copper Ore", HOST, Color(0.85, 0.48, 0.24),
		1.0, 0, &"raw_copper", 1, 2).tag(&"stratum_surface")
	ore(&"tin_ore", "Tin Ore", HOST, Color(0.78, 0.80, 0.84),
		1.0, 0, &"raw_tin", 1, 2).tag(&"stratum_upper")
	ore(&"salt_deposit", "Salt Deposit", Color(0.72, 0.70, 0.68), Color(0.96, 0.95, 0.92),
		0.5, 0, &"salt", 2, 3).tag(&"stratum_surface").tag(&"biome_desert")
	ore(&"lead_ore", "Lead Ore", Color(0.46, 0.46, 0.50), Color(0.42, 0.42, 0.52),
		1.4, 1, &"raw_lead", 1, 2).tag(&"stratum_upper")
	ore(&"silver_ore", "Silver Ore", HOST, Color(0.88, 0.90, 0.94),
		1.5, 1, &"raw_silver", 1, 2).tag(&"stratum_mid")
	ore(&"gold_ore", "Gold Ore", HOST, Color(0.96, 0.80, 0.26),
		1.6, 1, &"raw_gold", 1, 2).tag(&"stratum_mid")
	ore(&"silicon_ore", "Silicon Ore", Color(0.52, 0.52, 0.56), Color(0.60, 0.66, 0.72),
		1.3, 1, &"raw_silicon", 1, 2).tag(&"stratum_mid")
	ore(&"sulphur_ore", "Sulphur Ore", Color(0.46, 0.44, 0.38), Color(0.94, 0.88, 0.24),
		1.1, 1, &"sulphur", 1, 3, 2, 0.25).tag(&"biome_magma").tag(&"stratum_mid")


static func _industrial() -> void:
	ore(&"tungsten_ore", "Tungsten Ore", Color(0.44, 0.44, 0.48), Color(0.50, 0.52, 0.48),
		2.0, 2, &"raw_tungsten", 1, 2).tag(&"stratum_mid")
	ore(&"titanium_ore", "Titanium Ore", Color(0.40, 0.40, 0.46), Color(0.74, 0.80, 0.86),
		2.3, 2, &"raw_titanium", 1, 2).tag(&"stratum_deep")
	ore(&"platinum_ore", "Platinum Ore", Color(0.42, 0.42, 0.46), Color(0.86, 0.88, 0.90),
		2.2, 2, &"raw_platinum", 1, 2).tag(&"stratum_deep")
	ore(&"cerulium_ore", "Cerulium Ore", Color(0.36, 0.42, 0.52), Color(0.28, 0.76, 0.96),
		2.1, 2, &"raw_cerulium", 1, 2, 4, 0.6) \
		.tag(&"stratum_mid").tag(&"biome_ocean").tag(&"biome_tundra")
	ore(&"erchius_crystal", "Erchius Crystal", Color(0.40, 0.44, 0.58), Color(0.62, 0.80, 1.00),
		1.7, 2, &"erchius_fuel", 1, 3, 9, 1.0) \
		.look(Color(0.40, 0.44, 0.58), Blocks.Pattern.CRYSTAL, Color(0.62, 0.80, 1.00)) \
		.tag(&"crystal").tag(&"biome_moon").tag(&"fuel")
	ore(&"durasteel_ore", "Durasteel Ore", Color(0.34, 0.34, 0.40), Color(0.56, 0.62, 0.70),
		2.7, 3, &"raw_durasteel", 1, 2).tag(&"stratum_deep")
	ore(&"uranium_ore", "Uranium Ore", Color(0.34, 0.38, 0.32), Color(0.52, 0.96, 0.34),
		2.5, 3, &"raw_uranium", 1, 2, 6, 0.8) \
		.tag(&"radioactive").tag(&"stratum_deep").tag(&"hazard") \
		.flags({"damage_on_touch": 1.0, "damage_element": Blocks.ELEM_POISON})


static func _exotic() -> void:
	ore(&"plutonium_ore", "Plutonium Ore", Color(0.30, 0.34, 0.30), Color(0.36, 1.00, 0.62),
		3.0, 4, &"raw_plutonium", 1, 2, 8, 1.0) \
		.tag(&"radioactive").tag(&"stratum_core").tag(&"hazard") \
		.flags({"damage_on_touch": 2.0, "damage_element": Blocks.ELEM_POISON})
	ore(&"aegisalt_ore", "Aegisalt Ore", Color(0.30, 0.32, 0.38), Color(0.42, 0.72, 0.82),
		3.3, 4, &"raw_aegisalt", 1, 2, 5, 0.7).tag(&"stratum_deep").tag(&"biome_alien")
	ore(&"ferozium_ore", "Ferozium Ore", Color(0.28, 0.34, 0.34), Color(0.30, 0.96, 0.80),
		3.4, 4, &"raw_ferozium", 1, 2, 6, 0.85).tag(&"stratum_core").tag(&"biome_alien")
	ore(&"violium_ore", "Violium Ore", Color(0.30, 0.26, 0.36), Color(0.72, 0.34, 0.96),
		3.4, 4, &"raw_violium", 1, 2, 6, 0.85).tag(&"stratum_core").tag(&"biome_alien")
	ore(&"rubium_ore", "Rubium Ore", Color(0.32, 0.22, 0.22), Color(1.00, 0.26, 0.30),
		3.8, 5, &"raw_rubium", 1, 2, 8, 1.0).tag(&"stratum_core")
	ore(&"solarium_ore", "Solarium Ore", Color(0.30, 0.28, 0.20), Color(1.00, 0.92, 0.34),
		4.2, 5, &"raw_solarium", 1, 2, 11, 1.0).tag(&"stratum_core")
	ore(&"prisilite_ore", "Prisilite Ore", Color(0.26, 0.30, 0.36), Color(0.60, 0.94, 1.00),
		3.6, 5, &"prisilite", 1, 2, 9, 1.0) \
		.look(Color(0.26, 0.30, 0.36), Blocks.Pattern.CRYSTAL, Color(0.60, 0.94, 1.00)) \
		.tag(&"crystal").tag(&"biome_alien")
	ore(&"core_fragment_ore", "Core Fragment Ore", Color(0.22, 0.12, 0.10), Color(1.00, 0.56, 0.14),
		4.8, 6, &"core_fragment", 1, 3, 13, 1.0) \
		.tag(&"stratum_core").tag(&"biome_magma").tag(&"fuel") \
		.flags({"blast_resistance": 120.0, "damage_on_touch": 2.0,
			"damage_element": Blocks.ELEM_FIRE})


static func _gems() -> void:
	ore(&"amethyst_ore", "Amethyst Ore", Color(0.46, 0.46, 0.50), Color(0.66, 0.38, 0.90),
		1.8, 1, &"amethyst", 1, 2, 2, 0.3).tag(&"gem").tag(&"stratum_mid")
	ore(&"topaz_ore", "Topaz Ore", Color(0.46, 0.46, 0.50), Color(0.96, 0.72, 0.24),
		1.8, 1, &"topaz", 1, 2, 2, 0.3).tag(&"gem").tag(&"stratum_mid")
	ore(&"ruby_ore", "Ruby Ore", Color(0.44, 0.44, 0.48), Color(0.92, 0.18, 0.28),
		2.4, 3, &"ruby", 1, 2, 3, 0.4).tag(&"gem").tag(&"stratum_deep")
	ore(&"sapphire_ore", "Sapphire Ore", Color(0.44, 0.44, 0.48), Color(0.22, 0.42, 0.96),
		2.4, 3, &"sapphire", 1, 2, 3, 0.4).tag(&"gem").tag(&"stratum_deep")
	ore(&"emerald_ore", "Emerald Ore", Color(0.44, 0.44, 0.48), Color(0.22, 0.86, 0.44),
		2.4, 3, &"emerald", 1, 2, 3, 0.4).tag(&"gem").tag(&"stratum_deep")
	ore(&"diamond_ore", "Diamond Ore", Color(0.42, 0.42, 0.48), Color(0.80, 0.96, 1.00),
		2.8, 3, &"diamond", 1, 1, 4, 0.5).tag(&"gem").tag(&"stratum_core")
