## Liquids and things that hurt.
##
## `BlockType.friction` is documented as *multiplying ground movement speed*, so
## every low-grip and high-drag surface sits **below** 1.0. The two cases are
## told apart by tag, and the player controller should read the tag, not the
## number:
##   * `slippery` — low grip: accelerate slowly, keep momentum (ice).
##   * `sticky`   — high drag: accelerate normally, lose momentum fast (tar,
##                  mud, slime).
##
## Damage is declarative wherever possible — `VoxelEntity._apply_touch_damage`
## already applies `damage_on_touch * delta` with `damage_element` for any block
## overlapping the entity box, so a hazard usually needs no code at all. The two
## exceptions here (healing water, burning out fire) use hooks.
class_name PsHazards
extends RefCounted


static func register_all(reg) -> void:
	_liquids(reg)
	_burning(reg)
	_spikes(reg)
	_surfaces(reg)


# ------------------------------------------------------------------- liquids
static func _liquid(reg, p_name: StringName, display: String, col: Color,
		damage: float = 0.0, element: String = Const.ELEM_PHYSICAL) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, BlockType.Pattern.FLAT, col.darkened(0.2))
	bt.mode(BlockType.Render.LIQUID)
	bt.sounds(&"step_liquid")
	bt.mining(0.0, &"any", 0)
	bt.in_category(&"liquid").tag(&"liquid")
	if damage > 0.0:
		bt.flags({"damage_on_touch": damage, "damage_element": element})
		bt.tag(&"hazard")
	return bt


static func _liquids(reg) -> void:
	_liquid(reg, &"swamp_water", "Swamp Water", Color(0.24, 0.34, 0.24, 0.68)) \
		.tag(&"biome_jungle")
	_liquid(reg, &"salt_water", "Salt Water", Color(0.14, 0.38, 0.62, 0.64)) \
		.tag(&"biome_ocean")
	_liquid(reg, &"healing_water", "Healing Water", Color(0.42, 0.92, 0.78, 0.60)) \
		.glows(6, 0.6).tag(&"biome_alien")
	_liquid(reg, &"toxic_water", "Poison", Color(0.42, 0.78, 0.20, 0.70), 4.0, Const.ELEM_POISON) \
		.glows(3, 0.4).tag(&"biome_toxic")
	_liquid(reg, &"acid", "Acid", Color(0.78, 0.90, 0.24, 0.66), 9.0, Const.ELEM_POISON) \
		.glows(4, 0.5).tag(&"biome_toxic")
	_liquid(reg, &"slime_liquid", "Slime", Color(0.36, 0.82, 0.40, 0.72)) \
		.tag(&"sticky").tag(&"biome_toxic").flags({"friction": 0.35, "bounce": 0.4})
	_liquid(reg, &"tar", "Tar", Color(0.09, 0.08, 0.10, 0.92)) \
		.tag(&"sticky").tag(&"fuel").tag(&"biome_barren").flags({"friction": 0.22, "flammable": true})
	_liquid(reg, &"liquid_fuel", "Liquid Fuel", Color(0.62, 0.44, 0.90, 0.72)) \
		.glows(5, 0.7).tag(&"fuel").tag(&"biome_moon")
	_liquid(reg, &"molten_core", "Molten Core", Color(1.00, 0.72, 0.20, 0.95), 32.0, Const.ELEM_FIRE) \
		.glows(15, 1.0).tag(&"biome_magma").tag(&"stratum_core")
	_liquid(reg, &"liquid_nitrogen", "Liquid Nitrogen", Color(0.68, 0.90, 0.98, 0.58), 6.0, Const.ELEM_ICE) \
		.tag(&"biome_tundra")

	# Healing water is the one liquid that gives instead of takes.
	var hw: BlockType = reg.get_by_name(&"healing_water")
	if hw != null:
		hw.on_entity_inside = Callable(PsHazards, "on_healing_water")


# ---------------------------------------------------------------- fire & heat
static func _burning(reg) -> void:
	var fire: BlockType = reg.define(&"fire", "Fire")
	fire.look(Color(1.0, 0.58, 0.14, 0.9), BlockType.Pattern.ORGANIC, Color(1.0, 0.86, 0.30))
	fire.mode(BlockType.Render.CROSS)
	fire.mining(0.0, &"any", 0)
	fire.glows(14, 1.0)
	fire.sounds(&"step_stone")
	fire.in_category(&"hazard").tag(&"hazard").tag(&"light_source")
	fire.flags({"replaceable": true, "damage_on_touch": 12.0,
		"damage_element": Const.ELEM_FIRE, "blast_resistance": 0.0})
	fire.on_random_tick = Callable(PsHazards, "on_fire_tick")

	reg.define(&"magma_block", "Magma Block").look(Color(0.42, 0.16, 0.10), BlockType.Pattern.NOISE, Color(1.0, 0.48, 0.12)) \
		.mining(2.4, &"pickaxe", 2).sounds(&"step_stone").glows(9, 1.0) \
		.in_category(&"hazard").tag(&"hazard").tag(&"stone").tag(&"biome_magma") \
		.tag(&"light_source").flags({"damage_on_touch": 6.0, "damage_element": Const.ELEM_FIRE})
	reg.define(&"ember_block", "Ember Block").look(Color(0.28, 0.16, 0.14), BlockType.Pattern.SPECKLE, Color(0.98, 0.40, 0.10)) \
		.mining(1.6, &"pickaxe", 1).sounds(&"step_stone").glows(6, 0.8) \
		.in_category(&"hazard").tag(&"hazard").tag(&"biome_magma").tag(&"light_source") \
		.flags({"damage_on_touch": 2.5, "damage_element": Const.ELEM_FIRE})
	reg.define(&"radioactive_waste", "Radioactive Waste").look(Color(0.26, 0.36, 0.24), BlockType.Pattern.SPECKLE, Color(0.52, 1.00, 0.36)) \
		.mining(3.0, &"pickaxe", 3).sounds(&"step_stone").glows(8, 1.0) \
		.in_category(&"hazard").tag(&"hazard").tag(&"radioactive").tag(&"biome_toxic") \
		.flags({"damage_on_touch": 5.0, "damage_element": Const.ELEM_POISON})
	reg.define(&"unstable_core", "Unstable Core").look(Color(0.18, 0.20, 0.30), BlockType.Pattern.CIRCUIT, Color(0.40, 0.90, 1.00)) \
		.mining(4.0, &"pickaxe", 3).sounds(&"step_metal").glows(10, 1.0) \
		.in_category(&"hazard").tag(&"hazard").tag(&"radioactive").tag(&"metal") \
		.flags({"damage_on_touch": 7.0, "damage_element": Const.ELEM_ELECTRIC,
			"blast_resistance": 0.2})


# ------------------------------------------------------------------- spikes
static func _spikes(reg) -> void:
	reg.define(&"stone_spikes", "Stone Spikes").look(Color(0.50, 0.50, 0.54), BlockType.Pattern.CRYSTAL, Color(0.36, 0.36, 0.40)) \
		.mining(1.4, &"pickaxe", 0).sounds(&"step_stone").in_category(&"hazard") \
		.tag(&"hazard").tag(&"stone").flags({"opaque": false, "damage_on_touch": 6.0})
	reg.define(&"iron_spikes", "Iron Spikes").look(Color(0.58, 0.58, 0.62), BlockType.Pattern.METAL, Color(0.40, 0.40, 0.44)) \
		.mining(2.6, &"pickaxe", 1).sounds(&"step_metal").in_category(&"hazard") \
		.tag(&"hazard").tag(&"metal").flags({"opaque": false, "damage_on_touch": 11.0})
	reg.define(&"poison_spikes", "Poison Spikes").look(Color(0.42, 0.52, 0.26), BlockType.Pattern.CRYSTAL, Color(0.62, 0.86, 0.24)) \
		.mining(2.0, &"pickaxe", 1).sounds(&"step_metal").glows(2, 0.3) \
		.in_category(&"hazard").tag(&"hazard").tag(&"biome_toxic") \
		.flags({"opaque": false, "damage_on_touch": 8.0, "damage_element": Const.ELEM_POISON})
	reg.define(&"thorn_block", "Thornbrush").look(Color(0.32, 0.40, 0.22), BlockType.Pattern.ORGANIC, Color(0.66, 0.60, 0.28)) \
		.mining(0.6, &"axe", 0).sounds(&"step_leaves").drop(&"plant_fibre", 1, 2) \
		.in_category(&"hazard").tag(&"hazard").tag(&"organic").tag(&"biome_jungle") \
		.flags({"opaque": false, "flammable": true, "damage_on_touch": 4.0})
	reg.define(&"electrified_plate", "Electrified Plate").look(Color(0.24, 0.30, 0.40), BlockType.Pattern.CIRCUIT, Color(0.40, 0.86, 1.00)) \
		.mining(3.0, &"pickaxe", 2).sounds(&"step_metal").glows(5, 0.8) \
		.in_category(&"hazard").tag(&"hazard").tag(&"metal").tag(&"light_source") \
		.flags({"damage_on_touch": 9.0, "damage_element": Const.ELEM_ELECTRIC})


# ------------------------------------------------------------ slick surfaces
static func _surfaces(reg) -> void:
	reg.define(&"black_ice", "Black Ice").look(Color(0.16, 0.20, 0.26, 0.80), BlockType.Pattern.ICE, Color(0.30, 0.40, 0.52)) \
		.mode(BlockType.Render.TRANSPARENT).mining(1.2, &"pickaxe", 1).sounds(&"step_snow") \
		.in_category(&"hazard").tag(&"ice").tag(&"slippery").tag(&"biome_tundra") \
		.flags({"solid": true, "friction": 0.08})
	reg.define(&"frost_block", "Frost Block").look(Color(0.78, 0.90, 0.96), BlockType.Pattern.ICE, Color(0.60, 0.76, 0.88)) \
		.mining(1.0, &"pickaxe", 0).sounds(&"step_snow").in_category(&"hazard") \
		.tag(&"ice").tag(&"hazard").tag(&"slippery").tag(&"biome_tundra") \
		.flags({"friction": 0.3, "damage_on_touch": 2.0, "damage_element": Const.ELEM_ICE})
	reg.define(&"tar_crust", "Tar Crust").look(Color(0.12, 0.11, 0.12), BlockType.Pattern.NOISE, Color(0.06, 0.06, 0.07)) \
		.mining(0.9, &"shovel", 0).sounds(&"step_dirt").in_category(&"hazard") \
		.tag(&"sticky").tag(&"fuel").tag(&"biome_barren") \
		.flags({"flammable": true, "friction": 0.25})
	reg.define(&"bounce_fungus", "Bounce Fungus").look(Color(0.86, 0.44, 0.72), BlockType.Pattern.ORGANIC, Color(0.66, 0.30, 0.54)) \
		.mining(0.5, &"any", 0).sounds(&"step_leaves").in_category(&"hazard") \
		.tag(&"fungus").tag(&"organic").tag(&"biome_alien") \
		.flags({"bounce": 0.85, "friction": 0.9})


# ============================================================== block hooks
## Healing water tops the swimmer up while they are inside it.
static func on_healing_water(_pos: Vector3i, entity: Node, delta: float) -> void:
	if entity == null or not entity.has_method(&"heal"):
		return
	entity.call(&"heal", 6.0 * delta)


## Fire is transient: it burns whatever it stands on, then goes out.
static func on_fire_tick(pos: Vector3i) -> void:
	var below := pos + Vector3i(0, -1, 0)
	var fuel := Blocks.get_type(World.get_block(below))
	if fuel != null and fuel.flammable and randf() < 0.35:
		World.set_block(below, Blocks.id(&"fire"))
		return
	if randf() < 0.5:
		World.set_block(pos, Const.AIR)
