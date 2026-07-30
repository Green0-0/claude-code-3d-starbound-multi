extends RefCounted

## The player's construction palette: everything you craft rather than dig.
##
## Two families need care because the physics reads them directly:
##   * **platforms** — collide **and** `platform`, but never opaque. The player
##     controller only stops a *downward* move onto them, giving Starbound's
##     one-way floors.
##   * **ladders** — `climbable`, never collide.
##
## Glass is `Render.TRANSPARENT`: still solid, but it does not cull the faces
## behind it, which matters enormously with a cutaway camera — a glass wall
## keeps the sliced-open interior behind it readable.


static func brick(p_name: StringName, display: String, col: Color, alt: Color,
		hard: float, tier := 0, pat := Blocks.Pattern.BRICK) -> Blocks.Def:
	return Blocks.define(p_name, display).look(col, pat, alt) \
		.mining(hard, &"pickaxe", tier).sounds(&"step_stone").drop(p_name) \
		.in_category(&"building").tag(&"brick").tag(&"stone") \
		.flags({"blast_resistance": hard * 3.0})


static func plating(p_name: StringName, display: String, col: Color, alt: Color,
		hard: float, tier: int, pat := Blocks.Pattern.METAL) -> Blocks.Def:
	return Blocks.define(p_name, display).look(col, pat, alt) \
		.mining(hard, &"pickaxe", tier).sounds(&"step_metal").drop(p_name) \
		.in_category(&"building").tag(&"metal") \
		.flags({"blast_resistance": hard * 4.0})


static func pane(p_name: StringName, display: String, col: Color, hard: float,
		tier := 0) -> Blocks.Def:
	return Blocks.define(p_name, display) \
		.look(col, Blocks.Pattern.GLASS, col.lightened(0.3)) \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.mining(hard, &"pickaxe", tier).sounds(&"step_glass").drop(p_name) \
		.in_category(&"building").tag(&"glass")


static func platform(p_name: StringName, display: String, col: Color, alt: Color,
		pat: int, hard: float, step: StringName) -> Blocks.Def:
	return Blocks.define(p_name, display).look(col, pat, alt) \
		.mode(Blocks.Render.TRANSPARENT).mining(hard, &"any", 0).sounds(step) \
		.drop(p_name).in_category(&"building").tag(&"platform") \
		.flags({"solid": true, "platform": true, "opaque": false})


static func ladder(p_name: StringName, display: String, col: Color, alt: Color,
		hard: float, step: StringName) -> Blocks.Def:
	return Blocks.define(p_name, display).look(col, Blocks.Pattern.PLANK, alt) \
		.mode(Blocks.Render.TRANSPARENT).mining(hard, &"any", 0).sounds(step) \
		.drop(p_name).in_category(&"building").tag(&"ladder").tag(&"climbable") \
		.flags({"solid": false, "opaque": false, "climbable": true})


static func register_all() -> void:
	_masonry()
	_industrial()
	_glass()
	_soft()
	_platforms()
	_ladders()


static func _masonry() -> void:
	brick(&"clay_brick", "Clay Brick", Color(0.72, 0.38, 0.30), Color(0.56, 0.28, 0.22), 0.85)
	brick(&"sandstone_brick", "Sandstone Brick", Color(0.84, 0.74, 0.50), Color(0.68, 0.60, 0.40), 0.75) \
		.sounds(&"step_sand").tag(&"sand")
	brick(&"marble_tile", "Marble Tile", Color(0.92, 0.91, 0.93), Color(0.74, 0.74, 0.78), 1.1, 1)
	brick(&"basalt_brick", "Basalt Brick", Color(0.26, 0.26, 0.29), Color(0.18, 0.18, 0.21), 1.3, 1)
	brick(&"obsidian_brick", "Obsidian Brick", Color(0.14, 0.12, 0.20), Color(0.09, 0.08, 0.14), 4.5, 3) \
		.flags({"blast_resistance": 300.0})
	brick(&"ice_brick", "Ice Brick", Color(0.66, 0.82, 0.94), Color(0.52, 0.70, 0.86), 0.6, 0, Blocks.Pattern.ICE) \
		.sounds(&"step_snow").tag(&"ice").tag(&"slippery").flags({"friction": 0.45})
	brick(&"concrete", "Concrete", Color(0.66, 0.66, 0.64), Color(0.54, 0.54, 0.52), 1.2, 1, Blocks.Pattern.NOISE)


static func _industrial() -> void:
	plating(&"iron_plating", "Iron Plating", Color(0.62, 0.62, 0.66), Color(0.48, 0.48, 0.52), 1.5, 1)
	plating(&"steel_plate", "Steel Plating", Color(0.70, 0.72, 0.76), Color(0.54, 0.56, 0.60), 2.0, 2)
	plating(&"titanium_plating", "Titanium Plating", Color(0.76, 0.80, 0.86), Color(0.58, 0.62, 0.70), 2.7, 2)
	plating(&"durasteel_plating", "Durasteel Plating", Color(0.54, 0.60, 0.68), Color(0.38, 0.44, 0.52), 3.5, 3) \
		.flags({"blast_resistance": 400.0})
	plating(&"aegisalt_plating", "Aegisalt Plating", Color(0.44, 0.72, 0.80), Color(0.30, 0.54, 0.62), 4.2, 4) \
		.glows(3, 0.4).flags({"blast_resistance": 600.0})
	plating(&"circuit_panel", "Circuit Panel", Color(0.18, 0.26, 0.24), Color(0.30, 0.92, 0.60), 1.3, 1, Blocks.Pattern.CIRCUIT) \
		.glows(4, 0.7).tag(&"decor")
	plating(&"metal_grate", "Metal Grate", Color(0.44, 0.46, 0.50), Color(0.28, 0.30, 0.34), 1.2, 1) \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}).tag(&"decor")
	plating(&"iron_bars", "Iron Bars", Color(0.40, 0.41, 0.45), Color(0.26, 0.27, 0.30), 1.5, 1) \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}).tag(&"decor").tag(&"trim")
	plating(&"copper_block", "Copper Block", Color(0.84, 0.48, 0.24), Color(0.62, 0.34, 0.16), 1.5, 1)
	plating(&"iron_block", "Iron Block", Color(0.74, 0.74, 0.78), Color(0.54, 0.54, 0.58), 1.8, 1)
	plating(&"gold_block", "Gold Block", Color(0.96, 0.80, 0.26), Color(0.72, 0.58, 0.16), 2.0, 2).glows(1, 0.2)


static func _glass() -> void:
	pane(&"tinted_glass", "Tinted Glass", Color(0.24, 0.26, 0.30, 0.62), 0.35)
	pane(&"stained_glass_red", "Red Stained Glass", Color(0.86, 0.24, 0.26, 0.45), 0.3)
	pane(&"stained_glass_blue", "Blue Stained Glass", Color(0.26, 0.42, 0.90, 0.45), 0.3)
	pane(&"stained_glass_green", "Green Stained Glass", Color(0.28, 0.80, 0.36, 0.45), 0.3)
	pane(&"reinforced_glass", "Reinforced Glass", Color(0.70, 0.84, 0.90, 0.42), 2.0, 2) \
		.flags({"blast_resistance": 120.0})


static func _soft() -> void:
	Blocks.define(&"wallpaper", "Wallpaper") \
		.look(Color(0.82, 0.76, 0.66), Blocks.Pattern.CLOTH, Color(0.70, 0.64, 0.54)) \
		.mining(0.15, &"any", 0).sounds(&"step_wood").drop(&"wallpaper") \
		.in_category(&"building").tag(&"cloth").tag(&"decor").flags({"flammable": true})
	Blocks.define(&"carpet_red", "Red Carpet") \
		.look(Color(0.66, 0.18, 0.20), Blocks.Pattern.CLOTH, Color(0.50, 0.13, 0.15)) \
		.mining(0.15, &"any", 0).sounds(&"step_wood").drop(&"carpet_red") \
		.in_category(&"building").tag(&"cloth").tag(&"decor") \
		.flags({"flammable": true, "friction": 1.05})
	Blocks.define(&"carpet_blue", "Blue Carpet") \
		.look(Color(0.20, 0.30, 0.62), Blocks.Pattern.CLOTH, Color(0.15, 0.22, 0.47)) \
		.mining(0.15, &"any", 0).sounds(&"step_wood").drop(&"carpet_blue") \
		.in_category(&"building").tag(&"cloth").tag(&"decor") \
		.flags({"flammable": true, "friction": 1.05})
	Blocks.define(&"thatch", "Thatch") \
		.look(Color(0.76, 0.64, 0.32), Blocks.Pattern.ORGANIC, Color(0.60, 0.50, 0.24)) \
		.mining(0.25, &"axe", 0).sounds(&"step_leaves").drop(&"thatch") \
		.in_category(&"building").tag(&"organic").flags({"flammable": true})
	Blocks.define(&"door_frame_wood", "Wooden Door Frame") \
		.look(Color(0.56, 0.40, 0.24), Blocks.Pattern.PLANK, Color(0.40, 0.28, 0.17)) \
		.mining(0.55, &"axe", 0).sounds(&"step_wood").drop(&"door_frame_wood") \
		.in_category(&"building").tag(&"door_frame").tag(&"wood").flags({"flammable": true})
	Blocks.define(&"gilded_trim", "Gilded Trim") \
		.look(Color(0.94, 0.78, 0.28), Blocks.Pattern.METAL, Color(0.70, 0.56, 0.16)) \
		.mining(1.3, &"pickaxe", 1).sounds(&"step_metal").glows(1, 0.2).drop(&"gilded_trim") \
		.in_category(&"building").tag(&"trim").tag(&"metal").tag(&"decor")
	Blocks.define(&"carved_trim", "Carved Trim") \
		.look(Color(0.72, 0.68, 0.60), Blocks.Pattern.STRATA, Color(0.56, 0.52, 0.45)) \
		.mining(1.0, &"pickaxe", 0).sounds(&"step_stone").drop(&"carved_trim") \
		.in_category(&"building").tag(&"trim").tag(&"stone").tag(&"decor")


static func _platforms() -> void:
	platform(&"wood_platform", "Wood Platform", Color(0.68, 0.52, 0.32),
		Color(0.52, 0.40, 0.24), Blocks.Pattern.PLANK, 0.35, &"step_wood") \
		.tag(&"wood").flags({"flammable": true})
	platform(&"metal_platform", "Metal Platform", Color(0.62, 0.64, 0.68),
		Color(0.46, 0.48, 0.52), Blocks.Pattern.METAL, 0.8, &"step_metal").tag(&"metal")
	platform(&"stone_platform", "Stone Platform", Color(0.54, 0.54, 0.58),
		Color(0.40, 0.40, 0.44), Blocks.Pattern.BRICK, 0.75, &"step_stone").tag(&"stone")


static func _ladders() -> void:
	ladder(&"wooden_ladder", "Wooden Ladder", Color(0.66, 0.50, 0.30),
		Color(0.50, 0.38, 0.22), 0.25, &"step_wood").tag(&"wood").flags({"flammable": true})
	ladder(&"metal_ladder", "Metal Ladder", Color(0.60, 0.62, 0.66),
		Color(0.44, 0.46, 0.50), 0.7, &"step_metal").tag(&"metal")
	ladder(&"rope_ladder", "Rope Ladder", Color(0.72, 0.62, 0.42),
		Color(0.54, 0.46, 0.30), 0.15, &"step_leaves").tag(&"cloth").flags({"flammable": true})
