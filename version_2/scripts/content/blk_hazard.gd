extends RefCounted

## Liquids and things that hurt.
##
## Damage is declarative wherever possible: any block overlapping an entity's box
## applies `touch_damage * delta` with `touch_element`, so a hazard usually needs
## no code at all. `friction` multiplies ground acceleration, so every low-grip
## and high-drag surface sits below 1.0 — the two cases are told apart by tag:
##   * `slippery` — low grip: accelerate slowly, keep momentum (ice, black ice).
##   * `sticky`   — high drag: accelerate normally, lose momentum fast (tar, mud).


static func liquid(p_name: StringName, display: String, col: Color,
		damage := 0.0, element: StringName = Blocks.ELEM_PHYSICAL) -> Blocks.Def:
	var b := Blocks.define(p_name, display)
	b.look(col, Blocks.Pattern.FLAT, col.darkened(0.2)).mode(Blocks.Render.LIQUID) \
		.sounds(&"step_liquid").mining(0.0, &"any", 0) \
		.in_category(&"liquid").tag(&"liquid")
	if damage > 0.0:
		b.flags({"damage_on_touch": damage, "damage_element": element})
		b.tag(&"hazard")
	return b


static func register_all() -> void:
	_liquids()
	_burning()
	_spikes()
	_surfaces()


static func _liquids() -> void:
	liquid(&"water", "Water", Color(0.18, 0.42, 0.85, 0.62)).tag(&"biome_ocean")
	liquid(&"lava", "Lava", Color(0.95, 0.42, 0.10, 0.90), 18.0, Blocks.ELEM_FIRE) \
		.glows(14, 1.0).tag(&"biome_magma").tag(&"fuel")
	liquid(&"swamp_water", "Swamp Water", Color(0.24, 0.34, 0.24, 0.68)).tag(&"biome_jungle")
	liquid(&"healing_water", "Healing Water", Color(0.42, 0.92, 0.78, 0.60)) \
		.glows(6, 0.6).tag(&"biome_alien").tag(&"healing")
	liquid(&"toxic_water", "Poison", Color(0.42, 0.78, 0.20, 0.70), 4.0, Blocks.ELEM_POISON) \
		.glows(3, 0.4).tag(&"biome_toxic")
	liquid(&"tar", "Tar", Color(0.09, 0.08, 0.10, 0.92)) \
		.tag(&"sticky").tag(&"fuel").tag(&"biome_barren") \
		.flags({"friction": 0.22, "flammable": true})
	liquid(&"liquid_fuel", "Liquid Fuel", Color(0.62, 0.44, 0.90, 0.72)) \
		.glows(5, 0.7).tag(&"fuel").tag(&"biome_moon")
	liquid(&"liquid_nitrogen", "Liquid Nitrogen", Color(0.68, 0.90, 0.98, 0.58),
		6.0, Blocks.ELEM_ICE).tag(&"biome_tundra")


static func _burning() -> void:
	Blocks.define(&"fire", "Fire") \
		.look(Color(1.0, 0.58, 0.14, 0.9), Blocks.Pattern.ORGANIC, Color(1.0, 0.86, 0.30)) \
		.mode(Blocks.Render.CROSS).mining(0.0, &"any", 0).glows(14, 1.0) \
		.in_category(&"hazard").tag(&"hazard").tag(&"light_source").tag(&"fire") \
		.flags({"replaceable": true, "damage_on_touch": 12.0,
			"damage_element": Blocks.ELEM_FIRE, "blast_resistance": 0.0})
	Blocks.define(&"magma_block", "Magma Block") \
		.look(Color(0.42, 0.16, 0.10), Blocks.Pattern.NOISE, Color(1.0, 0.48, 0.12)) \
		.mining(1.2, &"pickaxe", 2).sounds(&"step_stone").glows(9, 1.0) \
		.drop(&"magma_block").in_category(&"hazard").tag(&"hazard").tag(&"stone") \
		.tag(&"biome_magma").tag(&"light_source") \
		.flags({"damage_on_touch": 6.0, "damage_element": Blocks.ELEM_FIRE})
	Blocks.define(&"radioactive_waste", "Radioactive Waste") \
		.look(Color(0.26, 0.36, 0.24), Blocks.Pattern.SPECKLE, Color(0.52, 1.00, 0.36)) \
		.mining(1.5, &"pickaxe", 3).sounds(&"step_stone").glows(8, 1.0) \
		.drop(&"radioactive_waste").in_category(&"hazard").tag(&"hazard") \
		.tag(&"radioactive").tag(&"biome_toxic") \
		.flags({"damage_on_touch": 5.0, "damage_element": Blocks.ELEM_POISON})


static func _spikes() -> void:
	Blocks.define(&"stone_spikes", "Stone Spikes") \
		.look(Color(0.50, 0.50, 0.54), Blocks.Pattern.CRYSTAL, Color(0.36, 0.36, 0.40)) \
		.mining(0.7, &"pickaxe", 0).sounds(&"step_stone").drop(&"stone_spikes") \
		.in_category(&"hazard").tag(&"hazard").tag(&"stone") \
		.flags({"opaque": false, "damage_on_touch": 6.0})
	Blocks.define(&"iron_spikes", "Iron Spikes") \
		.look(Color(0.58, 0.58, 0.62), Blocks.Pattern.METAL, Color(0.40, 0.40, 0.44)) \
		.mining(1.3, &"pickaxe", 1).sounds(&"step_metal").drop(&"iron_spikes") \
		.in_category(&"hazard").tag(&"hazard").tag(&"metal") \
		.flags({"opaque": false, "damage_on_touch": 11.0})
	Blocks.define(&"poison_spikes", "Poison Spikes") \
		.look(Color(0.42, 0.52, 0.26), Blocks.Pattern.CRYSTAL, Color(0.62, 0.86, 0.24)) \
		.mining(1.0, &"pickaxe", 1).sounds(&"step_metal").glows(2, 0.3) \
		.drop(&"poison_spikes").in_category(&"hazard").tag(&"hazard").tag(&"biome_toxic") \
		.flags({"opaque": false, "damage_on_touch": 8.0,
			"damage_element": Blocks.ELEM_POISON})
	Blocks.define(&"electrified_plate", "Electrified Plate") \
		.look(Color(0.24, 0.30, 0.40), Blocks.Pattern.CIRCUIT, Color(0.40, 0.86, 1.00)) \
		.mining(1.5, &"pickaxe", 2).sounds(&"step_metal").glows(5, 0.8) \
		.drop(&"electrified_plate").in_category(&"hazard").tag(&"hazard") \
		.tag(&"metal").tag(&"light_source") \
		.flags({"damage_on_touch": 9.0, "damage_element": Blocks.ELEM_ELECTRIC})


static func _surfaces() -> void:
	Blocks.define(&"black_ice", "Black Ice") \
		.look(Color(0.16, 0.20, 0.26, 0.80), Blocks.Pattern.ICE, Color(0.30, 0.40, 0.52)) \
		.mode(Blocks.Render.TRANSPARENT).mining(0.6, &"pickaxe", 1).sounds(&"step_snow") \
		.drop(&"black_ice").in_category(&"hazard").tag(&"ice").tag(&"slippery") \
		.tag(&"biome_tundra").flags({"solid": true, "friction": 0.08})
	Blocks.define(&"tar_crust", "Tar Crust") \
		.look(Color(0.12, 0.11, 0.12), Blocks.Pattern.NOISE, Color(0.06, 0.06, 0.07)) \
		.mining(0.45, &"shovel", 0).sounds(&"step_dirt").drop(&"tar_crust") \
		.in_category(&"hazard").tag(&"sticky").tag(&"fuel").tag(&"biome_barren") \
		.flags({"flammable": true, "friction": 0.25})
	Blocks.define(&"bounce_fungus", "Bounce Fungus") \
		.look(Color(0.86, 0.44, 0.72), Blocks.Pattern.ORGANIC, Color(0.66, 0.30, 0.54)) \
		.mining(0.25, &"any", 0).sounds(&"step_leaves").drop(&"bounce_fungus") \
		.in_category(&"hazard").tag(&"fungus").tag(&"organic").tag(&"biome_alien") \
		.flags({"bounce": 0.85, "friction": 0.9})
