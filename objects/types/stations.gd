## Crafting stations. Each hosts one of the crafting agent's `CraftStation`
## objects (guarded — the file is probed with `ResourceLoader.exists`, so these
## still place, save and open if crafting has not landed) and announces itself
## through `Events.station_opened(station_id, node)`.
##
## Timed stations (furnace, chemistry lab, refinery-likes) set `tick: true` in
## their definition, which puts them on `ObjManager`'s machine budget.
class_name ObjStations
extends RefCounted

const CRAFT_STATION_PATH := "res://crafting/crafting_station.gd"


class Station extends ObjBase:
	## The crafting agent's `CraftStation`, or null.
	var station: Variant = null

	func on_create() -> void:
		_build_station()

	func on_load() -> void:
		if station != null and station.has_method(&"load_state") and state.has("cs"):
			station.call(&"load_state", state["cs"])

	func _build_station() -> void:
		if station != null or not ResourceLoader.exists(ObjStations.CRAFT_STATION_PATH):
			return
		var scr: Script = load(ObjStations.CRAFT_STATION_PATH) as Script
		if scr == null:
			return
		station = scr.new(StringName(def.get("station", id)), int(def.get("station_tier", 0)))
		if station == null:
			return
		if station.has_method(&"configure"):
			station.call(&"configure", {
				"station": String(def.get("station", id)),
				"tier": int(def.get("station_tier", 0)),
				"name": display_name,
				"speed": float(def.get("speed", 1.0)),
			})
		if station.has_method(&"set") and "owner_node" in station:
			station.set("owner_node", null)
		if station.has_signal(&"craft_finished"):
			station.connect(&"craft_finished", _on_craft_finished)

	func _on_craft_finished(_recipe_id: String, _count: int) -> void:
		particles(&"craft_done", 6)
		sound(&"craft_done")
		set_st("busy", false)

	func on_interact(_player: Node) -> bool:
		var sid := String(def.get("station", id))
		Events.station_opened.emit(sid, null)
		UI.open("crafting", {
			"station": sid, "tier": int(def.get("station_tier", 0)),
			"title": display_name, "object": self, "handle": station,
			"pos": [pos.x, pos.y, pos.z],
		})
		Events.ui_panel_opened.emit("crafting")
		sound(&"station_open")
		return true

	func on_tick(delta: float) -> void:
		if station == null:
			return
		if station.has_method(&"tick"):
			station.call(&"tick", delta)
		var busy := bool(station.call(&"is_busy")) if station.has_method(&"is_busy") else false
		if busy != bool(st("busy", false)):
			state["busy"] = busy
			write()
		if busy:
			particles(&"station_work", 1)

	func save_extra() -> Dictionary:
		if station != null and station.has_method(&"save_state"):
			state["cs"] = station.call(&"save_state")
		return {}

	func build_visual() -> Node3D:
		if int(def.get("light", 0)) <= 0:
			return null
		return ObjVisual.glow(center(), def.get("color", Color.WHITE),
			0.55, float(def.get("emission", 1.0)))

	func update_visual(_delta: float) -> void:
		if visual != null:
			visual.visible = bool(st("busy", false)) or int(def.get("light", 0)) > 6


static func register_all() -> void:
	_station(&"workbench", "Workbench", &"workbench", 0, Color(0.55, 0.40, 0.24),
		BlockType.Pattern.PLANK, 1.2, 0, false, 0, 40, &"step_wood",
		"Basic assembly. Everything starts here.")
	_station(&"furnace", "Furnace", &"furnace", 0, Color(0.42, 0.40, 0.38),
		BlockType.Pattern.BRICK, 2.4, 0, true, 8, 60, &"step_stone",
		"Smelts ore into bars. Needs fuel.")
	_station(&"blast_furnace", "Blast Furnace", &"furnace", 2, Color(0.36, 0.34, 0.34),
		BlockType.Pattern.BRICK, 4.0, 2, true, 10, 320, &"step_stone",
		"A hotter furnace: faster smelts and higher-tier alloys.")
	_station(&"anvil", "Anvil", &"anvil", 0, Color(0.36, 0.37, 0.40),
		BlockType.Pattern.METAL, 3.2, 0, false, 0, 90, &"step_metal",
		"Shapes bars into tools and armour.")
	_station(&"forge", "Forge", &"forge", 2, Color(0.48, 0.30, 0.22),
		BlockType.Pattern.METAL, 4.2, 1, true, 9, 380, &"step_metal",
		"Alloy work and tier-3 gear.")
	_station(&"kitchen", "Kitchen Counter", &"kitchen", 0, Color(0.72, 0.68, 0.58),
		BlockType.Pattern.CLOTH, 1.6, 0, true, 0, 70, &"step_wood",
		"Turns raw ingredients into food worth eating.")
	_station(&"chemistry_lab", "Chemistry Lab", &"chemistry", 2, Color(0.36, 0.60, 0.55),
		BlockType.Pattern.GLASS, 3.0, 1, true, 5, 420, &"step_glass",
		"Reagents, fuels and augments.")
	_station(&"assembler", "Assembler", &"assembler", 3, Color(0.42, 0.46, 0.56),
		BlockType.Pattern.CIRCUIT, 3.6, 2, true, 6, 620, &"step_metal",
		"Automated fabrication of complex parts.")
	_station(&"replicator", "Replicator", &"replicator", 4, Color(0.50, 0.42, 0.68),
		BlockType.Pattern.CIRCUIT, 4.4, 3, true, 9, 1500, &"step_metal",
		"Prints high-tier equipment from raw matter.")
	_station(&"separator", "Separator", &"separator", 3, Color(0.58, 0.54, 0.40),
		BlockType.Pattern.METAL, 3.4, 2, true, 4, 560, &"step_metal",
		"Breaks compounds back down into their components.")
	_station(&"loom", "Loom", &"loom", 0, Color(0.66, 0.56, 0.44),
		BlockType.Pattern.CLOTH, 1.4, 0, false, 0, 55, &"step_wood",
		"Weaves fibre into cloth and clothing.")


static func _station(p_id: StringName, display: String, station_id: StringName, tier: int,
		col: Color, pat: int, hardness: float, tool_tier: int, ticks: bool,
		light: int, value: int, step: StringName, desc: String) -> void:
	var tool_name: StringName = &"pickaxe" if tool_tier > 0 else &"any"
	var emission := 0.8 if light > 0 else 0.0
	var rarity := Const.RARITY_UNCOMMON if tier >= 2 else Const.RARITY_COMMON
	ObjRegistry.define(p_id, display, &"station", Station, {
		"color": col, "pattern": pat, "hardness": hardness,
		"tool": tool_name, "tier": tool_tier,
		"step": step, "light": light, "emission": emission,
		"station": station_id, "station_tier": tier, "tick": ticks,
		"value": value, "category": &"objects", "rarity": rarity,
		"tags": [&"station", &"crafting"], "desc": desc,
	})
