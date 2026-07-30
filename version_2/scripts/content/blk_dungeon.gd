extends RefCounted

## Themed structure sets and the handful of special blocks worldgen needs.
##
## A dungeon theme is a `wall` / `floor` / `accent` / `locked` quartet; the
## structure placer asks for a theme by tag and gets a consistent palette back.
## `locked` members are unbreakable, which is what makes a vault a vault until
## you find the door — and, with a cutaway camera, finding the door means
## turning the camera rather than digging.


static func themed(p_name: StringName, display: String, col: Color, alt: Color,
		pat: int, hard: float, tier: int, theme: StringName,
		role: StringName) -> Blocks.Def:
	var b := Blocks.define(p_name, display)
	b.look(col, pat, alt).mining(hard, &"pickaxe", tier).sounds(&"step_stone") \
		.in_category(&"dungeon").tag(theme).tag(role)
	if role == &"locked":
		b.flags({"breakable": false, "blast_resistance": 9999.0}).tag(&"unbreakable")
	else:
		b.drop(p_name)
	return b


static func register_all() -> void:
	# --- human outpost: rusted steel and hazard paint
	themed(&"human_wall", "Outpost Plating", Color(0.52, 0.54, 0.58),
		Color(0.36, 0.38, 0.42), Blocks.Pattern.METAL, 1.6, 1, &"theme_human", &"wall")
	themed(&"human_floor", "Outpost Decking", Color(0.44, 0.46, 0.50),
		Color(0.30, 0.32, 0.36), Blocks.Pattern.PLANK, 1.4, 1, &"theme_human", &"floor")
	themed(&"human_accent", "Outpost Console", Color(0.20, 0.28, 0.30),
		Color(0.35, 0.90, 0.86), Blocks.Pattern.CIRCUIT, 1.6, 1, &"theme_human", &"accent") \
		.glows(5, 0.7)
	themed(&"human_vault", "Sealed Bulkhead", Color(0.60, 0.62, 0.66),
		Color(0.90, 0.76, 0.16), Blocks.Pattern.METAL, 99.0, 99, &"theme_human", &"locked")

	# --- ancient: pale worked stone shot through with gold
	themed(&"ancient_wall", "Ancient Masonry", Color(0.74, 0.70, 0.58),
		Color(0.56, 0.52, 0.42), Blocks.Pattern.BRICK, 2.0, 2, &"theme_ancient", &"wall")
	themed(&"ancient_floor", "Ancient Flagstone", Color(0.66, 0.63, 0.53),
		Color(0.50, 0.47, 0.39), Blocks.Pattern.STRATA, 1.8, 2, &"theme_ancient", &"floor")
	themed(&"ancient_accent", "Glyph Stone", Color(0.68, 0.62, 0.46),
		Color(0.98, 0.84, 0.34), Blocks.Pattern.CIRCUIT, 2.4, 2, &"theme_ancient", &"accent") \
		.glows(6, 0.8)
	themed(&"ancient_seal", "Ancient Seal", Color(0.58, 0.52, 0.40),
		Color(1.00, 0.86, 0.40), Blocks.Pattern.CRYSTAL, 99.0, 99, &"theme_ancient", &"locked") \
		.glows(8, 1.0)

	# --- special: the two markers worldgen writes and the game reads back
	Blocks.define(&"monster_spawner", "Monster Spawner") \
		.look(Color(0.18, 0.16, 0.22), Blocks.Pattern.CRYSTAL, Color(0.72, 0.26, 0.32)) \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.mining(2.5, &"pickaxe", 1).glows(4, 0.6).sounds(&"step_stone") \
		.in_category(&"special").tag(&"spawner")
	Blocks.define(&"treasure_marker", "Cache Marker") \
		.look(Color(0.30, 0.26, 0.20), Blocks.Pattern.ORE, Color(0.94, 0.78, 0.30)) \
		.mining(0.5, &"any", 0).sounds(&"step_wood").in_category(&"special") \
		.tag(&"marker")
