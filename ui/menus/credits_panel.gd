## Credits. A slow auto-scroll that the player can grab and drag; ESC or the
## close button ends it.
extends MenuPanel

const SCROLL_SPEED := 26.0

const SECTIONS := [
	["PLANESHIFT", ""],
	["Concept", "A Starbound-shaped sandbox on a Minecraft-shaped world,\nplayed from four side-on planes."],
	["Core", "Coordinate model, voxel world, physics, event bus"],
	["World", "Terrain, biomes, caves, ores, structures"],
	["Rendering", "Chunk meshing, procedural atlas, slab shader"],
	["Perspective", "Orthographic rig, flip animation, screen effects"],
	["Player", "Paper-doll actor, plane-space movement"],
	["Items", "Inventory, hotbar, drops, containers"],
	["Crafting", "Recipes, stations, queues"],
	["Combat", "Weapons, projectiles, damage pipeline"],
	["Life", "Monsters, AI, NPCs, spawning"],
	["Stories", "Quests and dialogue trees"],
	["Simulation", "Liquids, falling blocks, light propagation, day and night"],
	["Space", "Universe generation, ships, star maps, teleporters"],
	["Feel", "Synthesised audio, particles, screen shake"],
	["Memory", "Save, load, chunk paging"],
	["Survival", "Hunger, temperature, oxygen, status effects, farming"],
	["Tech", "Techs, tools, the matter manipulator"],
	["Objects", "Machines, furniture, containers, doors"],
	["Interface", "HUD, menus, windows, the drag-and-drop service"],
	["", ""],
	["No binary assets", "Every texture, sound and mesh in this game is generated\nby the code that ships with it."],
	["Built with", "Godot Engine"],
	["", "Thanks for turning the world."],
]

var _scroll: ScrollContainer = null
var _auto: bool = true
var _scroll_pos: float = 0.0


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.75
	placement = "center"
	anim = "fade"


func _build() -> void:
	var body := frame("Credits", Vector2(560, 460))
	var col := MenuWidgets.col(MenuTheme.GAP + 6)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN

	col.add_child(MenuWidgets.spacer(90, false))
	for entry: Array in SECTIONS:
		var heading := String(entry[0])
		var text := String(entry[1])
		if heading != "":
			var h := MenuWidgets.label(heading.to_upper(), &"HeadLabel",
				HORIZONTAL_ALIGNMENT_CENTER)
			col.add_child(h)
		if text != "":
			var p := MenuWidgets.paragraph(text, &"SmallLabel")
			p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(p)
	col.add_child(MenuWidgets.spacer(120, false))

	_scroll = MenuWidgets.scroll(col)
	_scroll.custom_minimum_size = Vector2(0, 330)
	body.add_child(_scroll)

	var f := footer()
	f.add_child(MenuWidgets.toggle("Auto-scroll", true,
		func(v: bool) -> void: _auto = v))
	f.add_child(MenuWidgets.spacer())
	f.add_child(MenuWidgets.button("Close", close_self, &"AccentButton"))
	body.add_child(f)


func _process(delta: float) -> void:
	if not _auto or _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return
	var maximum := maxf(0.0, bar.max_value - bar.page)
	if maximum <= 0.0:
		return
	# Accumulate in a float: at 26 px/s an int would truncate to zero every frame.
	_scroll_pos += SCROLL_SPEED * delta
	if _scroll_pos >= maximum:
		_scroll_pos = 0.0
	_scroll.scroll_vertical = int(_scroll_pos)
