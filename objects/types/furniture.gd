## Furniture: beds, seating, tables, lamps, banners, storage displays.
##
## Mostly light behaviour, but two of these matter mechanically — the bed sets
## the respawn point and can skip the night, and the lamp is a wired light.
class_name ObjFurniture
extends RefCounted


# ===========================================================================
#  Bed — respawn point, and sleep to skip the night
# ===========================================================================
class Bed extends ObjBase:
	func on_interact(player: Node) -> bool:
		_set_respawn(player)
		if Game.is_night():
			_sleep()
		else:
			Events.toast("Respawn point set. Come back after dark to sleep.", "info")
		sound(&"bed")
		return true

	func _set_respawn(player: Node) -> void:
		var spot := center() + Vector3(0.0, 0.6, 0.0)
		state["respawn"] = [spot.x, spot.y, spot.z]
		write()
		# The player agent owns the respawn point; hand it over if it will take it.
		if player != null and player.has_method(&"set_respawn_point"):
			player.call(&"set_respawn_point", spot)
		elif player != null and "respawn_point" in player:
			player.set("respawn_point", spot)

	## Fast-forwards the clock to dawn. `Game.tick` is the single source of
	## time, so nudging it here keeps lighting, weather and crops in step.
	func _sleep() -> void:
		var dawn := int(Const.TICKS_PER_DAY * 0.25)
		if Game.tick > dawn:
			Game.day += 1
		Game.tick = dawn
		Events.time_changed.emit(Game.tick, float(Game.tick) / float(Const.TICKS_PER_DAY))
		var p := Game.player
		if p != null:
			p.heal(p.max_health * 0.35)
		Events.toast("You slept until dawn.", "info")
		Events.screen_shake.emit(0.2, 0.3)
		particles(&"sleep", 8)


# ===========================================================================
#  Seating — sit to regenerate a little faster
# ===========================================================================
class Chair extends ObjBase:
	func on_interact(player: Node) -> bool:
		var seated := not bool(st("seated", false))
		state["seated"] = seated
		write()
		if player != null and player.has_method(&"set_seated"):
			player.call(&"set_seated", seated, center() + Vector3(0.0, 0.35, 0.0))
		elif seated and player is VoxelEntity:
			(player as VoxelEntity).teleport(center() + Vector3(0.0, 0.1, 0.0))
		Events.toast("Sat down." if seated else "Stood up.", "info")
		sound(&"chair")
		return true


# ===========================================================================
#  Surfaces — a table is a place to put one item on show
# ===========================================================================
class Surface extends ObjBase:
	func on_interact(_player: Node) -> bool:
		var shown := String(st("item", ""))
		var stack: ItemStack = Tech.interaction.held_stack() if Tech.interaction != null else null
		if shown == "" and stack != null and not stack.is_empty():
			state["item"] = String(stack.id)
			write()
			if Tech.interaction != null:
				Tech.interaction._consume(stack)
			Events.toast("Placed %s." % stack.display_name(), "info")
			return true
		if shown != "":
			Game.spawn_item_drop(center() + Vector3(0.0, 0.9, 0.0), StringName(shown), 1)
			state["item"] = ""
			write()
			return true
		return false

	func on_removed() -> Array:
		var shown := String(st("item", ""))
		return [{"item": StringName(shown), "count": 1}] if shown != "" else []

	func build_visual() -> Node3D:
		var shown := String(st("item", ""))
		if shown == "":
			return null
		var t := Items.get_type(StringName(shown))
		return ObjVisual.panel(center() + Vector3(0.0, 0.62, 0.0),
			t.icon_color if t != null else Color.WHITE, 0.34)

	func update_visual(_delta: float) -> void:
		if visual != null:
			visual.basis = View.camera_basis()


# ===========================================================================
#  Lamp — a light that can be wired
# ===========================================================================
class Lamp extends ObjMachines.Wired:
	func on_create() -> void:
		super.on_create()
		if not state.has("on"):
			state["on"] = true

	func on_interact(_player: Node) -> bool:
		_set_on(not bool(st("on", true)))
		return true

	func on_power_edge(now_on: bool) -> void:
		_set_on(now_on)

	## Swaps between the lit and unlit block variants, keeping the object.
	func _set_on(on: bool) -> void:
		if bool(st("on", true)) == on:
			return
		state["on"] = on
		var off_block := StringName(def.get("off_block", &""))
		if off_block != &"" and Blocks.has(off_block):
			swap_block(id if on else off_block)
		write()
		sound(&"lamp")

	func build_visual() -> Node3D:
		return ObjVisual.glow(center(), def.get("color", Color.WHITE), 0.7,
			float(def.get("emission", 1.0)))

	func update_visual(_delta: float) -> void:
		if visual != null:
			visual.visible = bool(st("on", true))


# ===========================================================================
#  Banner — a decorative panel that always turns to face the camera
# ===========================================================================
class Banner extends ObjBase:
	func on_interact(_player: Node) -> bool:
		state["rot"] = (int(st("rot", 0)) + 1) & 3
		rot = int(st("rot", 0))
		write()
		Events.toast("Rotated.", "info")
		return true

	func build_visual() -> Node3D:
		return ObjVisual.panel(center(), def.get("color", Color.WHITE), 0.85)

	func update_visual(_delta: float) -> void:
		if visual != null:
			visual.basis = View.camera_basis()


# ===========================================================================
#  Registration
# ===========================================================================
static func register_all() -> void:
	ObjRegistry.define(&"bed", "Bed", &"furniture", Bed, {
		"color": Color(0.72, 0.36, 0.36), "pattern": BlockType.Pattern.CLOTH,
		"hardness": 0.9, "step": &"step_wood", "solid": false, "opaque": false,
		"render": BlockType.Render.TRANSPARENT,
		"value": 90, "category": &"objects", "tags": [&"furniture", &"bed"],
		"desc": "Sets your respawn point. Sleep after dark to skip to dawn.",
	})
	ObjRegistry.define(&"bunk_bed", "Bunk Bed", &"furniture", Bed, {
		"color": Color(0.44, 0.48, 0.62), "pattern": BlockType.Pattern.CLOTH,
		"hardness": 1.1, "step": &"step_metal",
		"value": 140, "category": &"objects", "tags": [&"furniture", &"bed"],
		"desc": "Sleeps two. Sets your respawn point all the same.",
	})
	_seat(&"chair", "Chair", Color(0.56, 0.38, 0.22), BlockType.Pattern.PLANK, &"step_wood", 35)
	_seat(&"stool", "Stool", Color(0.50, 0.34, 0.20), BlockType.Pattern.PLANK, &"step_wood", 25)
	_seat(&"bench", "Bench", Color(0.46, 0.42, 0.36), BlockType.Pattern.PLANK, &"step_wood", 45)
	_seat(&"throne", "Throne", Color(0.70, 0.58, 0.24), BlockType.Pattern.METAL, &"step_metal", 900)

	_surface(&"table", "Table", Color(0.58, 0.42, 0.26), BlockType.Pattern.PLANK, &"step_wood", 50)
	_surface(&"round_table", "Round Table", Color(0.62, 0.46, 0.30), BlockType.Pattern.PLANK, &"step_wood", 60)
	_surface(&"storage_display", "Display Case", Color(0.75, 0.82, 0.86), BlockType.Pattern.GLASS, &"step_glass", 130)
	_surface(&"pedestal", "Pedestal", Color(0.66, 0.66, 0.70), BlockType.Pattern.BRICK, &"step_stone", 110)

	_lamp(&"lamp", "Lamp", Color(1.0, 0.88, 0.62), 12, 55)
	_lamp(&"floor_lamp", "Floor Lamp", Color(1.0, 0.84, 0.55), 13, 80)
	_lamp(&"ceiling_light", "Ceiling Light", Color(0.92, 0.96, 1.0), 14, 110)
	_lamp(&"paper_lantern", "Paper Lantern", Color(1.0, 0.62, 0.42), 10, 45)

	ObjRegistry.define(&"banner", "Banner", &"furniture", Banner, {
		"color": Color(0.68, 0.26, 0.30), "pattern": BlockType.Pattern.CLOTH,
		"hardness": 0.4, "step": &"step_leaves", "solid": false, "opaque": false,
		"render": BlockType.Render.TRANSPARENT,
		"value": 40, "category": &"objects", "tags": [&"furniture", &"decor"],
		"desc": "Hangs flat to whichever plane you are watching from.",
	})
	ObjRegistry.define(&"rug", "Rug", &"furniture", Banner, {
		"color": Color(0.52, 0.30, 0.42), "pattern": BlockType.Pattern.CLOTH,
		"hardness": 0.3, "step": &"step_leaves", "solid": false, "opaque": false,
		"render": BlockType.Render.TRANSPARENT,
		"value": 35, "category": &"objects", "tags": [&"furniture", &"decor"],
		"desc": "Soft underfoot. Purely decorative.",
	})
	ObjRegistry.define(&"wall_clock", "Wall Clock", &"furniture", Banner, {
		"color": Color(0.86, 0.84, 0.76), "pattern": BlockType.Pattern.METAL,
		"hardness": 0.6, "solid": false, "opaque": false,
		"render": BlockType.Render.TRANSPARENT,
		"value": 75, "category": &"objects", "tags": [&"furniture", &"decor"],
		"desc": "Tells you how long until dark.",
	})


static func _seat(p_id: StringName, display: String, col: Color, pat: int,
		step: StringName, value: int) -> void:
	ObjRegistry.define(p_id, display, &"furniture", Chair, {
		"color": col, "pattern": pat, "hardness": 0.7, "step": step,
		"solid": false, "opaque": false, "render": BlockType.Render.TRANSPARENT,
		"value": value, "category": &"objects", "tags": [&"furniture", &"seat"],
		"desc": "Sit down. You heal a little faster off your feet.",
	})


static func _surface(p_id: StringName, display: String, col: Color, pat: int,
		step: StringName, value: int) -> void:
	ObjRegistry.define(p_id, display, &"furniture", Surface, {
		"color": col, "pattern": pat, "hardness": 0.9, "step": step,
		"value": value, "category": &"objects", "tags": [&"furniture", &"display"],
		"desc": "Puts one item on show. Interact again to take it back.",
	})


static func _lamp(p_id: StringName, display: String, col: Color, light: int, value: int) -> void:
	ObjRegistry.define(p_id, display, &"furniture", Lamp, {
		"color": col, "pattern": BlockType.Pattern.GLASS, "hardness": 0.6,
		"step": &"step_glass", "light": light, "emission": 1.0,
		"solid": false, "opaque": false, "render": BlockType.Render.TRANSPARENT,
		"wire_in": 1, "off_block": StringName(String(p_id) + "_off"),
		"value": value, "category": &"objects",
		"tags": [&"furniture", &"light_source", &"wired"],
		"desc": "Light source. Wire it up to switch it remotely.",
	})
