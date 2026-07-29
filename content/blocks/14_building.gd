## The player's construction palette: everything you craft rather than dig.
##
## Two families need care because the physics and player code read them
## directly:
##   * **platforms** — `solid = true` *and* `platform = true`, `opaque = false`.
##     `VoxelPhysics` only stops a *downward* move onto them, and honours
##     `opts.drop_through`, giving Starbound's one-way floors.
##   * **ladders** — `climbable = true`, `solid = false`. Anything the player
##     should be able to climb also carries the `climbable` tag.
##
## Glass is `Render.TRANSPARENT`: still solid, but it does not cull the faces
## behind it, which matters enormously in this game — you look *through* the
## depth slab, so a glass wall keeps the layers behind it readable.
extends RefCounted


static func register_all(reg) -> void:
	_masonry(reg)
	_industrial(reg)
	_glass(reg)
	_soft(reg)
	_platforms(reg)
	_ladders(reg)
	_trim(reg)


# ------------------------------------------------------------------ masonry
static func _brick(reg, p_name: StringName, display: String, col: Color, alt: Color,
		hardness: float, tier: int = 0, pat: BlockType.Pattern = BlockType.Pattern.BRICK) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, pat, alt)
	bt.mining(hardness, &"pickaxe", tier)
	bt.sounds(&"step_stone")
	bt.in_category(&"building").tag(&"brick").tag(&"stone")
	bt.blast_resistance = hardness * 3.0
	return bt


static func _masonry(reg) -> void:
	_brick(reg, &"stone_brick", "Stone Brick", Color(0.55, 0.55, 0.58), Color(0.42, 0.42, 0.45), 2.0)
	_brick(reg, &"cracked_stone_brick", "Cracked Stone Brick", Color(0.50, 0.50, 0.52), Color(0.36, 0.36, 0.39), 1.7)
	_brick(reg, &"mossy_stone_brick", "Mossy Stone Brick", Color(0.44, 0.52, 0.42), Color(0.32, 0.40, 0.30), 1.9)
	_brick(reg, &"clay_brick", "Clay Brick", Color(0.72, 0.38, 0.30), Color(0.56, 0.28, 0.22), 1.8)
	_brick(reg, &"sandstone_brick", "Sandstone Brick", Color(0.84, 0.74, 0.50), Color(0.68, 0.60, 0.40), 1.6) \
		.sounds(&"step_sand").tag(&"sand")
	_brick(reg, &"marble_tile", "Marble Tile", Color(0.92, 0.91, 0.93), Color(0.74, 0.74, 0.78), 2.2, 1)
	_brick(reg, &"basalt_brick", "Basalt Brick", Color(0.26, 0.26, 0.29), Color(0.18, 0.18, 0.21), 2.6, 1)
	_brick(reg, &"obsidian_brick", "Obsidian Brick", Color(0.14, 0.12, 0.20), Color(0.09, 0.08, 0.14), 9.0, 3) \
		.flags({"blast_resistance": 300.0})
	_brick(reg, &"ice_brick", "Ice Brick", Color(0.66, 0.82, 0.94), Color(0.52, 0.70, 0.86), 1.2, 0, BlockType.Pattern.ICE) \
		.sounds(&"step_snow").tag(&"ice").tag(&"slippery").flags({"friction": 0.45})
	_brick(reg, &"snow_brick", "Snow Brick", Color(0.94, 0.95, 0.99), Color(0.82, 0.85, 0.92), 0.7, 0) \
		.sounds(&"step_snow").tag(&"snow")
	_brick(reg, &"ceramic_tile", "Ceramic Tile", Color(0.90, 0.90, 0.86), Color(0.76, 0.76, 0.72), 1.5, 0, BlockType.Pattern.FLAT)
	_brick(reg, &"slate_tile", "Slate Tile", Color(0.32, 0.34, 0.40), Color(0.24, 0.26, 0.31), 1.8, 0, BlockType.Pattern.FLAT)
	_brick(reg, &"concrete", "Concrete", Color(0.66, 0.66, 0.64), Color(0.54, 0.54, 0.52), 2.4, 1, BlockType.Pattern.NOISE)
	_brick(reg, &"reinforced_concrete", "Reinforced Concrete", Color(0.58, 0.58, 0.58), Color(0.42, 0.44, 0.48), 5.0, 2, BlockType.Pattern.NOISE) \
		.flags({"blast_resistance": 250.0})
	_brick(reg, &"clay_tile", "Clay Roof Tile", Color(0.70, 0.34, 0.26), Color(0.54, 0.25, 0.19), 1.5)
	_brick(reg, &"stone_pillar", "Stone Pillar", Color(0.72, 0.71, 0.68), Color(0.54, 0.53, 0.50), 2.2, 1, BlockType.Pattern.STRATA) \
		.tag(&"trim")


# ------------------------------------------------------------- metal & tech
static func _plating(reg, p_name: StringName, display: String, col: Color, alt: Color,
		hardness: float, tier: int, pat: BlockType.Pattern = BlockType.Pattern.METAL) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, pat, alt)
	bt.mining(hardness, &"pickaxe", tier)
	bt.sounds(&"step_metal")
	bt.in_category(&"building").tag(&"metal")
	bt.blast_resistance = hardness * 4.0
	return bt


static func _industrial(reg) -> void:
	_plating(reg, &"iron_plating", "Iron Plating", Color(0.62, 0.62, 0.66), Color(0.48, 0.48, 0.52), 3.0, 1)
	_plating(reg, &"rusted_metal", "Rusted Plating", Color(0.60, 0.38, 0.24), Color(0.44, 0.27, 0.17), 2.2, 1)
	_plating(reg, &"steel_plate", "Steel Plating", Color(0.70, 0.72, 0.76), Color(0.54, 0.56, 0.60), 4.0, 2)
	_plating(reg, &"titanium_plating", "Titanium Plating", Color(0.76, 0.80, 0.86), Color(0.58, 0.62, 0.70), 5.5, 2)
	_plating(reg, &"durasteel_plating", "Durasteel Plating", Color(0.54, 0.60, 0.68), Color(0.38, 0.44, 0.52), 7.0, 3) \
		.flags({"blast_resistance": 400.0})
	_plating(reg, &"aegisalt_plating", "Aegisalt Plating", Color(0.44, 0.72, 0.80), Color(0.30, 0.54, 0.62), 8.5, 4) \
		.glows(3, 0.4).flags({"blast_resistance": 600.0})
	_plating(reg, &"circuit_panel", "Circuit Panel", Color(0.18, 0.26, 0.24), Color(0.30, 0.92, 0.60), 2.6, 1, BlockType.Pattern.CIRCUIT) \
		.glows(4, 0.7).tag(&"decor")
	_plating(reg, &"metal_grate", "Metal Grate", Color(0.44, 0.46, 0.50), Color(0.28, 0.30, 0.34), 2.4, 1) \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}).tag(&"decor")
	_plating(reg, &"scaffold", "Scaffold", Color(0.66, 0.56, 0.34), Color(0.48, 0.40, 0.24), 1.0, 0) \
		.mode(BlockType.Render.TRANSPARENT).sounds(&"step_wood").flags({"solid": true}) \
		.tag(&"wood").tag(&"decor")
	_plating(reg, &"iron_bars", "Iron Bars", Color(0.40, 0.41, 0.45), Color(0.26, 0.27, 0.30), 3.0, 1) \
		.mode(BlockType.Render.TRANSPARENT).flags({"solid": true}).tag(&"decor").tag(&"trim")
	_plating(reg, &"hazard_stripe", "Hazard Stripe", Color(0.92, 0.78, 0.14), Color(0.14, 0.13, 0.13), 2.6, 1) \
		.tag(&"decor").tag(&"trim")
	_plating(reg, &"metal_trim", "Metal Trim", Color(0.74, 0.76, 0.80), Color(0.50, 0.52, 0.56), 2.8, 1) \
		.tag(&"trim").tag(&"decor")
	_plating(reg, &"metal_pillar", "Metal Pillar", Color(0.56, 0.58, 0.62), Color(0.38, 0.40, 0.44), 3.4, 1) \
		.tag(&"trim")
	# Refined-metal storage blocks: the crafting sink for surplus bars, and the
	# blocks the dungeon palette reaches for as `accent` / `pillar` / `trim`.
	_plating(reg, &"copper_block", "Copper Block", Color(0.84, 0.48, 0.24), Color(0.62, 0.34, 0.16), 3.0, 1)
	_plating(reg, &"iron_block", "Iron Block", Color(0.74, 0.74, 0.78), Color(0.54, 0.54, 0.58), 3.6, 1)
	_plating(reg, &"silver_block", "Silver Block", Color(0.88, 0.90, 0.94), Color(0.66, 0.68, 0.72), 4.0, 2)
	_plating(reg, &"gold_block", "Gold Block", Color(0.96, 0.80, 0.26), Color(0.72, 0.58, 0.16), 4.0, 2) \
		.glows(1, 0.2)


# -------------------------------------------------------------------- glass
static func _pane(reg, p_name: StringName, display: String, col: Color,
		hardness: float, tier: int = 0) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, BlockType.Pattern.GLASS, col.lightened(0.3))
	bt.mode(BlockType.Render.TRANSPARENT)
	bt.solid = true
	bt.mining(hardness, &"pickaxe", tier)
	bt.sounds(&"step_glass")
	bt.in_category(&"building").tag(&"glass")
	return bt


static func _glass(reg) -> void:
	_pane(reg, &"glass", "Glass", Color(0.82, 0.90, 0.94, 0.30), 0.6)
	_pane(reg, &"tinted_glass", "Tinted Glass", Color(0.24, 0.26, 0.30, 0.62), 0.7)
	_pane(reg, &"frosted_glass", "Frosted Glass", Color(0.88, 0.92, 0.95, 0.70), 0.6)
	_pane(reg, &"stained_glass_red", "Red Stained Glass", Color(0.86, 0.24, 0.26, 0.45), 0.6)
	_pane(reg, &"stained_glass_blue", "Blue Stained Glass", Color(0.26, 0.42, 0.90, 0.45), 0.6)
	_pane(reg, &"stained_glass_green", "Green Stained Glass", Color(0.28, 0.80, 0.36, 0.45), 0.6)
	_pane(reg, &"reinforced_glass", "Reinforced Glass", Color(0.70, 0.84, 0.90, 0.42), 4.0, 2) \
		.flags({"blast_resistance": 120.0})


# ------------------------------------------------------- cloth, paper, floor
static func _soft(reg) -> void:
	reg.define(&"wallpaper", "Wallpaper").look(Color(0.82, 0.76, 0.66), BlockType.Pattern.CLOTH, Color(0.70, 0.64, 0.54)) \
		.mining(0.3, &"any", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"cloth").tag(&"decor").flags({"flammable": true})
	reg.define(&"wallpaper_striped", "Striped Wallpaper").look(Color(0.74, 0.66, 0.78), BlockType.Pattern.CLOTH, Color(0.56, 0.48, 0.62)) \
		.mining(0.3, &"any", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"cloth").tag(&"decor").flags({"flammable": true})
	reg.define(&"carpet_red", "Red Carpet").look(Color(0.66, 0.18, 0.20), BlockType.Pattern.CLOTH, Color(0.50, 0.13, 0.15)) \
		.mining(0.3, &"any", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"cloth").tag(&"decor").flags({"flammable": true, "friction": 1.05})
	reg.define(&"carpet_blue", "Blue Carpet").look(Color(0.20, 0.30, 0.62), BlockType.Pattern.CLOTH, Color(0.15, 0.22, 0.47)) \
		.mining(0.3, &"any", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"cloth").tag(&"decor").flags({"flammable": true, "friction": 1.05})
	reg.define(&"thatch", "Thatch").look(Color(0.76, 0.64, 0.32), BlockType.Pattern.ORGANIC, Color(0.60, 0.50, 0.24)) \
		.mining(0.5, &"axe", 0).sounds(&"step_leaves").in_category(&"building") \
		.tag(&"organic").flags({"flammable": true})
	# Generic wood, the species-agnostic fallback every structure palette and
	# recipe chain ends in.
	reg.define(&"wood_planks", "Wood Planks").look(Color(0.68, 0.52, 0.32), BlockType.Pattern.PLANK, Color(0.52, 0.40, 0.24)) \
		.mining(1.1, &"axe", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"wood").flags({"flammable": true})
	reg.define(&"dark_wood", "Dark Wood").look(Color(0.31, 0.22, 0.18), BlockType.Pattern.PLANK, Color(0.22, 0.15, 0.12)) \
		.mining(1.3, &"axe", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"wood").tag(&"trim").flags({"flammable": true})
	reg.define(&"wood_bars", "Wooden Bars").look(Color(0.54, 0.40, 0.24), BlockType.Pattern.PLANK, Color(0.38, 0.28, 0.17)) \
		.mode(BlockType.Render.TRANSPARENT).mining(1.0, &"axe", 0).sounds(&"step_wood") \
		.in_category(&"building").tag(&"wood").tag(&"decor") \
		.flags({"solid": true, "flammable": true})


# ---------------------------------------------------------------- platforms
static func _platform(reg, p_name: StringName, display: String, col: Color, alt: Color,
		pat: BlockType.Pattern, hardness: float, step: StringName) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, pat, alt)
	bt.mode(BlockType.Render.TRANSPARENT)
	bt.mining(hardness, &"any", 0)
	bt.sounds(step)
	bt.flags({"solid": true, "platform": true, "opaque": false})
	bt.in_category(&"building").tag(&"platform")
	return bt


static func _platforms(reg) -> void:
	_platform(reg, &"wood_platform", "Wood Platform", Color(0.68, 0.52, 0.32),
		Color(0.52, 0.40, 0.24), BlockType.Pattern.PLANK, 0.8, &"step_wood") \
		.tag(&"wood").flags({"flammable": true})
	_platform(reg, &"metal_platform", "Metal Platform", Color(0.62, 0.64, 0.68),
		Color(0.46, 0.48, 0.52), BlockType.Pattern.METAL, 1.6, &"step_metal") \
		.tag(&"metal")
	_platform(reg, &"glass_platform", "Glass Platform", Color(0.80, 0.90, 0.96, 0.40),
		Color(0.66, 0.80, 0.90), BlockType.Pattern.GLASS, 0.7, &"step_glass") \
		.tag(&"glass")
	_platform(reg, &"stone_platform", "Stone Platform", Color(0.54, 0.54, 0.58),
		Color(0.40, 0.40, 0.44), BlockType.Pattern.BRICK, 1.5, &"step_stone") \
		.tag(&"stone")


# ------------------------------------------------------------------ ladders
static func _ladder(reg, p_name: StringName, display: String, col: Color, alt: Color,
		hardness: float, step: StringName) -> BlockType:
	var bt: BlockType = reg.define(p_name, display)
	bt.look(col, BlockType.Pattern.PLANK, alt)
	bt.mode(BlockType.Render.TRANSPARENT)
	bt.mining(hardness, &"any", 0)
	bt.sounds(step)
	bt.flags({"solid": false, "opaque": false, "climbable": true})
	bt.in_category(&"building").tag(&"ladder").tag(&"climbable")
	return bt


static func _ladders(reg) -> void:
	_ladder(reg, &"wooden_ladder", "Wooden Ladder", Color(0.66, 0.50, 0.30),
		Color(0.50, 0.38, 0.22), 0.5, &"step_wood").tag(&"wood").flags({"flammable": true})
	_ladder(reg, &"metal_ladder", "Metal Ladder", Color(0.60, 0.62, 0.66),
		Color(0.44, 0.46, 0.50), 1.4, &"step_metal").tag(&"metal")
	_ladder(reg, &"rope_ladder", "Rope Ladder", Color(0.72, 0.62, 0.42),
		Color(0.54, 0.46, 0.30), 0.3, &"step_leaves").tag(&"cloth").flags({"flammable": true})
	_ladder(reg, &"vine_rope", "Vine Rope", Color(0.34, 0.54, 0.28),
		Color(0.24, 0.40, 0.20), 0.3, &"step_leaves").tag(&"organic").flags({"flammable": true})
	# Generic `ladder`: the last link in every structure palette's ladder chain.
	_ladder(reg, &"ladder", "Ladder", Color(0.62, 0.47, 0.28),
		Color(0.46, 0.35, 0.20), 0.5, &"step_wood").tag(&"wood").flags({"flammable": true})


# ------------------------------------------------------ trim & door framing
static func _trim(reg) -> void:
	reg.define(&"door_frame_wood", "Wooden Door Frame").look(Color(0.56, 0.40, 0.24), BlockType.Pattern.PLANK, Color(0.40, 0.28, 0.17)) \
		.mining(1.2, &"axe", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"door_frame").tag(&"wood").flags({"flammable": true})
	reg.define(&"door_frame_metal", "Metal Door Frame").look(Color(0.52, 0.54, 0.60), BlockType.Pattern.METAL, Color(0.36, 0.38, 0.44)) \
		.mining(3.0, &"pickaxe", 1).sounds(&"step_metal").in_category(&"building") \
		.tag(&"door_frame").tag(&"metal")
	reg.define(&"gilded_trim", "Gilded Trim").look(Color(0.94, 0.78, 0.28), BlockType.Pattern.METAL, Color(0.70, 0.56, 0.16)) \
		.mining(2.8, &"pickaxe", 1).sounds(&"step_metal").glows(1, 0.2) \
		.in_category(&"building").tag(&"trim").tag(&"metal").tag(&"decor")
	reg.define(&"carved_trim", "Carved Trim").look(Color(0.72, 0.68, 0.60), BlockType.Pattern.STRATA, Color(0.56, 0.52, 0.45)) \
		.mining(2.0, &"pickaxe", 0).sounds(&"step_stone").in_category(&"building") \
		.tag(&"trim").tag(&"stone").tag(&"decor")
	reg.define(&"wood_trim", "Wood Trim").look(Color(0.60, 0.44, 0.26), BlockType.Pattern.PLANK, Color(0.44, 0.32, 0.19)) \
		.mining(1.1, &"axe", 0).sounds(&"step_wood").in_category(&"building") \
		.tag(&"trim").tag(&"wood").tag(&"decor").flags({"flammable": true})
