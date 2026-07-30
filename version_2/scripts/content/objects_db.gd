class_name ObjectDB
extends RefCounted

## Placeable objects: containers, crafting stations, machines, furniture, doors
## and utilities.
##
## These are entities rather than voxels. That is deliberate — the voxel field
## is one byte per cell with no room for per-cell state, and a chest needs an
## inventory, a furnace needs a burn timer and a door needs to know whether it
## is open. Keeping them out of the block registry also keeps 30-odd ids free
## for actual terrain.
##
## Every object is a box of coloured panels built in code, so the game still
## ships with no binary assets. `kind` decides what interacting with it does.

enum Kind { CONTAINER, STATION, MACHINE, FURNITURE, LIGHT, DOOR, UTILITY }


class Def extends RefCounted:
	var id: StringName = &""
	var display := ""
	var description := ""
	var kind: int = ObjectDB.Kind.FURNITURE
	var color := Color(0.6, 0.5, 0.4)
	var accent := Color(0.3, 0.25, 0.2)
	var size := Vector3(0.9, 0.9, 0.9)     ## in blocks
	var station: StringName = &""          ## for Kind.STATION
	var capacity := 0                      ## for Kind.CONTAINER
	var light := 0
	var value := 20
	var rarity := 0
	var solid := true                      ## blocks movement while placed
	var tags := {}

	func tag(t: StringName) -> Def:
		tags[t] = true
		return self

	func has_tag(t: StringName) -> bool:
		return tags.has(t)


static var defs: Array[Def] = []
static var by_id := {}
static var _booted := false


static func boot() -> void:
	if _booted:
		return
	_booted = true
	_containers()
	_stations()
	_machines()
	_furniture()
	_lights()
	_doors()
	_utilities()


static func define(id: StringName, display: String, kind: int) -> Def:
	var d := Def.new()
	d.id = id
	d.display = display
	d.kind = kind
	defs.append(d)
	by_id[id] = d
	return d


static func get_def(id: StringName) -> Def:
	return by_id.get(id)


static func has(id: StringName) -> bool:
	return by_id.has(id)


static func all_of_kind(k: int) -> Array[Def]:
	var out: Array[Def] = []
	for d: Def in defs:
		if d.kind == k:
			out.append(d)
	return out


# ------------------------------------------------------------------ containers
static func _containers() -> void:
	var c := define(&"chest", "Chest", Kind.CONTAINER)
	c.color = Color(0.58, 0.40, 0.22)
	c.accent = Color(0.72, 0.58, 0.26)
	c.capacity = 24
	c.value = 30
	c.size = Vector3(0.9, 0.7, 0.9)
	c.description = "Twenty-four slots of somewhere else to put things."
	c.tag(&"storage")

	var b := define(&"barrel", "Barrel", Kind.CONTAINER)
	b.color = Color(0.50, 0.36, 0.22)
	b.accent = Color(0.40, 0.42, 0.46)
	b.capacity = 12
	b.value = 18
	b.size = Vector3(0.75, 0.95, 0.75)
	b.description = "Half a chest, and it rolls if you are careless."
	b.tag(&"storage")

	var s := define(&"safe", "Safe", Kind.CONTAINER)
	s.color = Color(0.34, 0.36, 0.40)
	s.accent = Color(0.86, 0.72, 0.28)
	s.capacity = 36
	s.value = 220
	s.rarity = 1
	s.description = "Heavy, dull and utterly uninteresting to look at. Ideal."
	s.tag(&"storage")

	var f := define(&"mini_fridge", "Mini Fridge", Kind.CONTAINER)
	f.color = Color(0.84, 0.86, 0.90)
	f.accent = Color(0.44, 0.70, 0.86)
	f.capacity = 18
	f.value = 140
	f.size = Vector3(0.85, 1.3, 0.85)
	f.description = "Chilled storage. Food inside it keeps four times as long."
	f.tag(&"storage").tag(&"preserves")


# ------------------------------------------------------------------- stations
static func _station(id: StringName, display: String, station: StringName,
		col: Color, accent: Color, value: int, desc: String) -> Def:
	var d := define(id, display, Kind.STATION)
	d.station = station
	d.color = col
	d.accent = accent
	d.value = value
	d.description = desc
	d.tag(&"crafting")
	return d


static func _stations() -> void:
	_station(&"workbench", "Workbench", &"workbench",
		Color(0.60, 0.44, 0.26), Color(0.42, 0.44, 0.48), 40,
		"A flat surface and a vice. Everything starts here.")
	_station(&"anvil", "Anvil", &"anvil",
		Color(0.36, 0.38, 0.42), Color(0.24, 0.25, 0.28), 160,
		"For anything that has to be hit into shape rather than assembled.") \
		.size = Vector3(0.9, 0.7, 0.6)
	_station(&"forge", "Forge", &"forge",
		Color(0.42, 0.30, 0.26), Color(1.0, 0.52, 0.16), 520,
		"Hot enough for the alloys that will not melt in a furnace.").light = 9
	_station(&"kitchen", "Kitchen Counter", &"kitchen",
		Color(0.80, 0.76, 0.68), Color(0.52, 0.30, 0.24), 120,
		"Turns things that will make you ill into things that will not.")
	_station(&"chemistry_lab", "Chemistry Lab", &"chemistry",
		Color(0.72, 0.78, 0.82), Color(0.36, 0.86, 0.72), 640,
		"Glassware, a fume hood, and a great many warning labels.").light = 4
	_station(&"assembler", "Assembler", &"assembler",
		Color(0.40, 0.44, 0.50), Color(0.34, 0.86, 0.94), 1400,
		"Fabricates the components no hand is steady enough to make.").light = 6
	_station(&"replicator", "Replicator", &"replicator",
		Color(0.32, 0.34, 0.42), Color(0.86, 0.70, 1.0), 3200,
		"Prints matter from a pattern. Nobody is entirely sure how.").light = 8
	_station(&"manipulator_bench", "Manipulator Bench", &"manipulator",
		Color(0.30, 0.44, 0.44), Color(0.55, 0.95, 0.85), 900,
		"Where manipulator modules are spent on beam upgrades.").light = 5
	_station(&"tech_console", "Tech Console", &"tech",
		Color(0.26, 0.30, 0.38), Color(0.62, 0.86, 1.0), 800,
		"Slots tech cards, and swaps which of them you are wearing.").light = 6


# ------------------------------------------------------------------- machines
static func _machines() -> void:
	var fu := define(&"furnace", "Furnace", Kind.MACHINE)
	fu.color = Color(0.44, 0.44, 0.47)
	fu.accent = Color(1.0, 0.56, 0.18)
	fu.station = &"furnace"
	fu.value = 90
	fu.light = 7
	fu.description = "Burns fuel to turn ore into bars. Slow, and it never stops."
	fu.tag(&"crafting").tag(&"fuelled")

	var rf := define(&"refinery", "Refinery", Kind.MACHINE)
	rf.color = Color(0.46, 0.50, 0.54)
	rf.accent = Color(0.96, 0.80, 0.26)
	rf.value = 480
	rf.size = Vector3(1.2, 1.2, 1.0)
	rf.description = "Grinds ore and bars back down into pixels, at a loss."
	rf.tag(&"machine")

	var ex := define(&"extractor", "Extractor", Kind.MACHINE)
	ex.color = Color(0.38, 0.42, 0.46)
	ex.accent = Color(0.44, 0.90, 0.56)
	ex.value = 720
	ex.light = 3
	ex.description = "Pulls the useful fraction out of organics and alien matter."
	ex.tag(&"machine")

	var ce := define(&"centrifuge", "Centrifuge", Kind.MACHINE)
	ce.color = Color(0.72, 0.74, 0.78)
	ce.accent = Color(0.36, 0.68, 0.94)
	ce.value = 860
	ce.light = 3
	ce.description = "Separates liquids into the things that were dissolved in them."
	ce.tag(&"machine")


# ------------------------------------------------------------------ furniture
static func _furniture() -> void:
	var bd := define(&"bed", "Bed", Kind.FURNITURE)
	bd.color = Color(0.66, 0.28, 0.30)
	bd.accent = Color(0.92, 0.90, 0.84)
	bd.size = Vector3(0.9, 0.5, 1.9)
	bd.value = 80
	bd.description = "Sleep through the night, and wake up rested."
	bd.tag(&"sleep")

	var ch := define(&"chair", "Chair", Kind.FURNITURE)
	ch.color = Color(0.56, 0.40, 0.24)
	ch.accent = Color(0.40, 0.28, 0.18)
	ch.size = Vector3(0.7, 1.0, 0.7)
	ch.value = 24
	ch.description = "Sit down. Energy comes back faster when you do."
	ch.tag(&"sit")

	var tb := define(&"table", "Table", Kind.FURNITURE)
	tb.color = Color(0.62, 0.46, 0.28)
	tb.accent = Color(0.44, 0.32, 0.20)
	tb.size = Vector3(1.2, 0.8, 1.2)
	tb.value = 30
	tb.description = "A surface at the right height for putting things down on."

	var bn := define(&"banner", "Banner", Kind.FURNITURE)
	bn.color = Color(0.30, 0.36, 0.66)
	bn.accent = Color(0.90, 0.80, 0.34)
	bn.size = Vector3(0.9, 1.6, 0.15)
	bn.solid = false
	bn.value = 45
	bn.description = "Hangs. Says something, to somebody."

	var jb := define(&"jukebox", "Jukebox", Kind.FURNITURE)
	jb.color = Color(0.52, 0.28, 0.34)
	jb.accent = Color(0.98, 0.78, 0.34)
	jb.size = Vector3(0.9, 1.4, 0.7)
	jb.light = 5
	jb.value = 260
	jb.description = "Plays whatever is loaded, loudly, until told otherwise."


# --------------------------------------------------------------------- lights
static func _lights() -> void:
	var br := define(&"brazier", "Brazier", Kind.LIGHT)
	br.color = Color(0.38, 0.36, 0.34)
	br.accent = Color(1.0, 0.62, 0.20)
	br.size = Vector3(0.8, 1.2, 0.8)
	br.light = 13
	br.value = 60
	br.description = "A bowl of fire on a stand. Reads well from every angle."

	var sl := define(&"standing_lamp", "Standing Lamp", Kind.LIGHT)
	sl.color = Color(0.40, 0.42, 0.46)
	sl.accent = Color(1.0, 0.92, 0.72)
	sl.size = Vector3(0.5, 1.9, 0.5)
	sl.light = 14
	sl.value = 140
	sl.description = "Clean, even light. Costs a cell a week and never smokes."


# ---------------------------------------------------------------------- doors
static func _doors() -> void:
	var wd := define(&"wooden_door", "Wooden Door", Kind.DOOR)
	wd.color = Color(0.56, 0.40, 0.24)
	wd.accent = Color(0.72, 0.62, 0.30)
	wd.size = Vector3(0.9, 2.0, 0.25)
	wd.value = 50
	wd.description = "Opens when you interact with it. Closes behind you."

	var bl := define(&"blast_door", "Blast Door", Kind.DOOR)
	bl.color = Color(0.46, 0.48, 0.52)
	bl.accent = Color(0.92, 0.74, 0.16)
	bl.size = Vector3(1.0, 2.0, 0.35)
	bl.value = 340
	bl.rarity = 1
	bl.description = "Rated for a pressure loss you would rather not experience."


# ------------------------------------------------------------------ utilities
static func _utilities() -> void:
	var tp := define(&"teleporter_pad", "Teleporter Pad", Kind.UTILITY)
	tp.color = Color(0.28, 0.32, 0.40)
	tp.accent = Color(0.46, 0.90, 1.0)
	tp.size = Vector3(1.4, 0.25, 1.4)
	tp.solid = false
	tp.light = 8
	tp.value = 1200
	tp.rarity = 2
	tp.description = "Bookmarks this spot, and takes you back to your ship."
	tp.tag(&"teleport")

	var wf := define(&"waypoint_flag", "Waypoint Flag", Kind.UTILITY)
	wf.color = Color(0.70, 0.66, 0.58)
	wf.accent = Color(0.94, 0.34, 0.30)
	wf.size = Vector3(0.3, 1.8, 0.3)
	wf.solid = false
	wf.value = 25
	wf.description = "Shows up on the compass from a long way off."
	wf.tag(&"waypoint")

	var hs := define(&"healing_station", "Healing Station", Kind.UTILITY)
	hs.color = Color(0.88, 0.90, 0.94)
	hs.accent = Color(0.92, 0.30, 0.34)
	hs.size = Vector3(0.9, 1.6, 0.7)
	hs.light = 6
	hs.value = 900
	hs.rarity = 1
	hs.description = "Stand in it to be put back together, slowly and for free."
	hs.tag(&"heal")

	var bc := define(&"beacon", "Beacon", Kind.UTILITY)
	bc.color = Color(0.34, 0.36, 0.42)
	bc.accent = Color(1.0, 0.42, 0.34)
	bc.size = Vector3(0.7, 1.5, 0.7)
	bc.light = 12
	bc.value = 400
	bc.description = "Calls something down. What, exactly, depends on the planet."
	bc.tag(&"summon")

	var sp := define(&"sprinkler", "Sprinkler", Kind.UTILITY)
	sp.color = Color(0.52, 0.62, 0.68)
	sp.accent = Color(0.40, 0.76, 0.96)
	sp.size = Vector3(0.5, 0.6, 0.5)
	sp.solid = false
	sp.value = 180
	sp.description = "Keeps every tilled plot within four blocks watered."
	sp.tag(&"farm")
