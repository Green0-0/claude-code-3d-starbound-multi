## The mining progression. Every ore is `Pattern.ORE` — host rock speckled with
## the metal colour — and is gated by `tool_tier`, so a copper pickaxe simply
## returns nothing from a titanium vein (`BlockType.roll_drops` checks the tier
## before rolling).
##
## Tier ladder, mirrored by the tool agent:
##
##   | tier | pickaxe          | unlocks                                  |
##   |------|------------------|------------------------------------------|
##   | 0    | stone / copper   | coal copper iron tin salt                |
##   | 1    | iron             | lead silver gold silicon sulphur         |
##   | 2    | tungsten         | tungsten titanium platinum amethyst topaz erchius |
##   | 3    | titanium         | durasteel uranium diamond ruby sapphire emerald |
##   | 4    | durasteel        | plutonium aegisalt ferozium violium      |
##   | 5    | aegisalt-class   | rubium solarium prisilite                |
##   | 6    | solarium-class   | core fragment                            |
##
## Every ore drops a `raw_*` (or gem) item id — the smelting agent turns those
## into bars. Exotic ores from tier 4 up are faintly emissive so deep caves
## glitter before your torch reaches them.
extends RefCounted


static func register_all(reg) -> void:
	_mundane(reg)
	_industrial(reg)
	_exotic(reg)
	_gems(reg)


# ------------------------------------------------------------------- tier 0-1
static func _mundane(reg) -> void:
	PsBlocks.ore(reg, &"coal_ore", "Coal Ore", Color(0.50, 0.50, 0.53),
		Color(0.10, 0.10, 0.12), 1.8, 0, &"raw_coal", 1, 2) \
		.tag(&"fuel").tag(&"stratum_surface").flags({"flammable": true})
	PsBlocks.ore(reg, &"copper_ore", "Copper Ore", Color(0.50, 0.50, 0.53),
		Color(0.85, 0.48, 0.24), 2.0, 0, &"raw_copper", 1, 2) \
		.tag(&"stratum_surface")
	PsBlocks.ore(reg, &"iron_ore", "Iron Ore", Color(0.50, 0.50, 0.53),
		Color(0.76, 0.62, 0.54), 2.4, 0, &"raw_iron", 1, 2) \
		.tag(&"stratum_upper")
	PsBlocks.ore(reg, &"tin_ore", "Tin Ore", Color(0.50, 0.50, 0.53),
		Color(0.78, 0.80, 0.84), 2.0, 0, &"raw_tin", 1, 2) \
		.tag(&"stratum_upper")
	PsBlocks.ore(reg, &"salt_deposit", "Salt Deposit", Color(0.72, 0.70, 0.68),
		Color(0.96, 0.95, 0.92), 1.0, 0, &"salt", 2, 3) \
		.tag(&"stratum_surface").tag(&"biome_desert").sounds(&"step_stone")
	PsBlocks.ore(reg, &"lead_ore", "Lead Ore", Color(0.46, 0.46, 0.50),
		Color(0.42, 0.42, 0.52), 2.8, 1, &"raw_lead", 1, 2) \
		.tag(&"stratum_upper")
	PsBlocks.ore(reg, &"silver_ore", "Silver Ore", Color(0.48, 0.48, 0.52),
		Color(0.88, 0.90, 0.94), 3.0, 1, &"raw_silver", 1, 2) \
		.tag(&"stratum_mid")
	PsBlocks.ore(reg, &"gold_ore", "Gold Ore", Color(0.48, 0.48, 0.52),
		Color(0.96, 0.80, 0.26), 3.2, 1, &"raw_gold", 1, 2) \
		.tag(&"stratum_mid")
	PsBlocks.ore(reg, &"silicon_ore", "Silicon Ore", Color(0.52, 0.52, 0.56),
		Color(0.60, 0.66, 0.72), 2.6, 1, &"raw_silicon", 1, 2) \
		.tag(&"stratum_mid")
	PsBlocks.ore(reg, &"sulphur_ore", "Sulphur Ore", Color(0.46, 0.44, 0.38),
		Color(0.94, 0.88, 0.24), 2.2, 1, &"sulphur", 1, 3) \
		.tag(&"biome_magma").tag(&"stratum_mid").glows(2, 0.25)


# ------------------------------------------------------------------- tier 2-3
static func _industrial(reg) -> void:
	PsBlocks.ore(reg, &"tungsten_ore", "Tungsten Ore", Color(0.44, 0.44, 0.48),
		Color(0.50, 0.52, 0.48), 4.0, 2, &"raw_tungsten", 1, 2) \
		.tag(&"stratum_mid")
	PsBlocks.ore(reg, &"titanium_ore", "Titanium Ore", Color(0.40, 0.40, 0.46),
		Color(0.74, 0.80, 0.86), 4.6, 2, &"raw_titanium", 1, 2) \
		.tag(&"stratum_deep")
	PsBlocks.ore(reg, &"platinum_ore", "Platinum Ore", Color(0.42, 0.42, 0.46),
		Color(0.86, 0.88, 0.90), 4.4, 2, &"raw_platinum", 1, 2) \
		.tag(&"stratum_deep")
	PsBlocks.ore(reg, &"cerulium_ore", "Cerulium Ore", Color(0.36, 0.42, 0.52),
		Color(0.28, 0.76, 0.96), 4.2, 2, &"raw_cerulium", 1, 2, 4, 0.6) \
		.tag(&"stratum_mid").tag(&"biome_ocean").tag(&"biome_tundra")
	PsBlocks.ore(reg, &"durasteel_ore", "Durasteel Ore", Color(0.34, 0.34, 0.40),
		Color(0.56, 0.62, 0.70), 5.4, 3, &"raw_durasteel", 1, 2) \
		.tag(&"stratum_deep")
	PsBlocks.ore(reg, &"uranium_ore", "Uranium Ore", Color(0.34, 0.38, 0.32),
		Color(0.52, 0.96, 0.34), 5.0, 3, &"raw_uranium", 1, 2, 6, 0.8) \
		.tag(&"radioactive").tag(&"stratum_deep").tag(&"hazard") \
		.flags({"damage_on_touch": 1.0, "damage_element": Const.ELEM_POISON})
	PsBlocks.ore(reg, &"erchius_crystal", "Erchius Crystal", Color(0.40, 0.44, 0.58),
		Color(0.62, 0.80, 1.00), 3.4, 2, &"erchius_fuel", 1, 3, 9, 1.0) \
		.tag(&"crystal").tag(&"biome_moon").tag(&"fuel") \
		.look(Color(0.40, 0.44, 0.58), BlockType.Pattern.CRYSTAL, Color(0.62, 0.80, 1.00))


# --------------------------------------------------------------- tier 4-6
static func _exotic(reg) -> void:
	PsBlocks.ore(reg, &"plutonium_ore", "Plutonium Ore", Color(0.30, 0.34, 0.30),
		Color(0.36, 1.00, 0.62), 6.0, 4, &"raw_plutonium", 1, 2, 8, 1.0) \
		.tag(&"radioactive").tag(&"stratum_core").tag(&"hazard") \
		.flags({"damage_on_touch": 2.0, "damage_element": Const.ELEM_POISON})
	PsBlocks.ore(reg, &"aegisalt_ore", "Aegisalt Ore", Color(0.30, 0.32, 0.38),
		Color(0.42, 0.72, 0.82), 6.6, 4, &"raw_aegisalt", 1, 2, 5, 0.7) \
		.tag(&"stratum_deep").tag(&"biome_alien")
	PsBlocks.ore(reg, &"ferozium_ore", "Ferozium Ore", Color(0.28, 0.34, 0.34),
		Color(0.30, 0.96, 0.80), 6.8, 4, &"raw_ferozium", 1, 2, 6, 0.85) \
		.tag(&"stratum_core").tag(&"biome_alien")
	PsBlocks.ore(reg, &"violium_ore", "Violium Ore", Color(0.30, 0.26, 0.36),
		Color(0.72, 0.34, 0.96), 6.8, 4, &"raw_violium", 1, 2, 6, 0.85) \
		.tag(&"stratum_core").tag(&"biome_alien")
	PsBlocks.ore(reg, &"rubium_ore", "Rubium Ore", Color(0.32, 0.22, 0.22),
		Color(1.00, 0.26, 0.30), 7.6, 5, &"raw_rubium", 1, 2, 8, 1.0) \
		.tag(&"stratum_core")
	PsBlocks.ore(reg, &"solarium_ore", "Solarium Ore", Color(0.30, 0.28, 0.20),
		Color(1.00, 0.92, 0.34), 8.4, 5, &"raw_solarium", 1, 2, 11, 1.0) \
		.tag(&"stratum_core")
	PsBlocks.ore(reg, &"prisilite_ore", "Prisilite Ore", Color(0.26, 0.30, 0.36),
		Color(0.60, 0.94, 1.00), 7.2, 5, &"prisilite", 1, 2, 9, 1.0) \
		.tag(&"crystal").tag(&"biome_alien") \
		.look(Color(0.26, 0.30, 0.36), BlockType.Pattern.CRYSTAL, Color(0.60, 0.94, 1.00))
	PsBlocks.ore(reg, &"core_fragment_ore", "Core Fragment Ore", Color(0.22, 0.12, 0.10),
		Color(1.00, 0.56, 0.14), 9.5, 6, &"core_fragment", 1, 3, 13, 1.0) \
		.tag(&"stratum_core").tag(&"biome_magma").tag(&"fuel") \
		.flags({"blast_resistance": 120.0, "damage_on_touch": 2.0,
			"damage_element": Const.ELEM_FIRE})


# ---------------------------------------------------------------------- gems
static func _gems(reg) -> void:
	PsBlocks.ore(reg, &"amethyst_ore", "Amethyst Ore", Color(0.46, 0.46, 0.50),
		Color(0.66, 0.38, 0.90), 3.6, 2, &"amethyst", 1, 2, 2, 0.3) \
		.tag(&"gem").tag(&"stratum_mid")
	PsBlocks.ore(reg, &"topaz_ore", "Topaz Ore", Color(0.46, 0.46, 0.50),
		Color(0.96, 0.72, 0.24), 3.6, 2, &"topaz", 1, 2, 2, 0.3) \
		.tag(&"gem").tag(&"stratum_mid")
	PsBlocks.ore(reg, &"ruby_ore", "Ruby Ore", Color(0.44, 0.44, 0.48),
		Color(0.92, 0.18, 0.28), 4.8, 3, &"ruby", 1, 2, 3, 0.4) \
		.tag(&"gem").tag(&"stratum_deep")
	PsBlocks.ore(reg, &"sapphire_ore", "Sapphire Ore", Color(0.44, 0.44, 0.48),
		Color(0.22, 0.42, 0.96), 4.8, 3, &"sapphire", 1, 2, 3, 0.4) \
		.tag(&"gem").tag(&"stratum_deep")
	PsBlocks.ore(reg, &"emerald_ore", "Emerald Ore", Color(0.44, 0.44, 0.48),
		Color(0.22, 0.86, 0.44), 4.8, 3, &"emerald", 1, 2, 3, 0.4) \
		.tag(&"gem").tag(&"stratum_deep")
	PsBlocks.ore(reg, &"diamond_ore", "Diamond Ore", Color(0.42, 0.42, 0.48),
		Color(0.80, 0.96, 1.00), 5.6, 3, &"diamond", 1, 1, 4, 0.5) \
		.tag(&"gem").tag(&"stratum_core")
