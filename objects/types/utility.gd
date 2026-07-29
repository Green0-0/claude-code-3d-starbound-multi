## Utility objects: teleporter pads, waypoints, campfires, sprinklers, the
## capture-pod healing station, and the two consoles that front this agent's
## own systems (tech loadout and Matter Manipulator upgrades).
class_name ObjUtility
extends RefCounted


# ===========================================================================
#  Teleporter pad
# ===========================================================================
class TeleporterPad extends ObjMachines.Wired:
	func on_create() -> void:
		super.on_create()
		if not state.has("network"):
			state["network"] = "personal"
		if not state.has("label"):
			state["label"] = ""

	func on_interact(_player: Node) -> bool:
		# Hand off to the space agent when it exists; otherwise act as a local
		# two-pad shuttle using the stored target.
		if Universe.has_method(&"open_teleport_menu"):
			Universe.call(&"open_teleport_menu", pos, String(st("network", "personal")))
			return true
		var t: Variant = st("target", null)
		if t is Array and (t as Array).size() == 3:
			var dest := Vector3(t[0], t[1], t[2]) + Vector3(0.5, 1.0, 0.5)
			var p := Game.player
			if p != null:
				p.teleport(dest)
				View.set_layer(floori(View.depth_of(dest)))
				particles(&"teleport", 20)
				sound(&"teleport")
			return true
		UI.open("teleporter", {"object": self, "pos": [pos.x, pos.y, pos.z],
			"network": String(st("network", "personal"))})
		Events.toast("No destination linked. Wire two pads together.", "info")
		return true

	## Called by the wire tool when two pads are linked.
	func link_to(target: Vector3i) -> void:
		state["target"] = [target.x, target.y, target.z]
		write()
		Events.toast("Teleporter linked.", "info")

	func build_visual() -> Node3D:
		return ObjVisual.field(center() + Vector3(0.0, 0.45, 0.0),
			Color(0.45, 0.85, 1.0), 0.42, 1.6)

	func update_visual(delta: float) -> void:
		if visual != null:
			ObjVisual.spin(visual, delta, 1.4)


# ===========================================================================
#  Waypoint flag
# ===========================================================================
class Waypoint extends ObjBase:
	func on_placed(_player: Node) -> void:
		state["label"] = "Waypoint %d" % (Game.tick % 1000)
		write()
		Events.toast("Waypoint planted.", "info")

	func on_interact(_player: Node) -> bool:
		Events.toast("Waypoint: %s  (%d, %d, %d)" % [String(st("label", "Waypoint")),
			pos.x, pos.y, pos.z], "info")
		if Quests.has_method(&"note_waypoint"):
			Quests.call(&"note_waypoint", pos, String(st("label", "")))
		return true

	func build_visual() -> Node3D:
		return ObjVisual.panel(center() + Vector3(0.0, 0.5, 0.0),
			def.get("color", Color.WHITE), 0.5)

	func update_visual(_delta: float) -> void:
		if visual != null:
			visual.basis = View.camera_basis()


# ===========================================================================
#  Campfire — a heat source the survival agent can read
# ===========================================================================
class Campfire extends ObjBase:
	func on_create() -> void:
		if not state.has("fuel"):
			state["fuel"] = 240.0
		if not state.has("lit"):
			state["lit"] = true

	## Survival agents: query `Tech.objects.heat_at(world_pos)`; this is what
	## feeds it.
	func heat() -> float:
		return float(def.get("heat", 18.0)) if bool(st("lit", false)) else 0.0

	func radius() -> float:
		return float(def.get("radius", 6.0))

	func on_tick(delta: float) -> void:
		if not bool(st("lit", false)):
			return
		var fuel := float(st("fuel", 0.0)) - delta
		state["fuel"] = maxf(0.0, fuel)
		if fuel <= 0.0:
			state["lit"] = false
			swap_block(StringName(String(id) + "_off"))
			write()
			particles(&"smoke", 6)
			return
		if fmod(fuel, 1.0) < delta:
			particles(&"fire", 2)
			var p := Game.player
			if p != null and p.global_position.distance_to(center()) < radius():
				if Status.has_method(&"apply"):
					Status.apply(&"warm", p, 2.0)

	func on_interact(_player: Node) -> bool:
		var stack: ItemStack = Tech.interaction.held_stack() if Tech.interaction != null else null
		if stack != null and not stack.is_empty():
			var burn := 0.0
			if Recipes.has_method(&"fuel_value"):
				burn = float(Recipes.fuel_value(stack.id))
			if burn > 0.0:
				state["fuel"] = minf(1200.0, float(st("fuel", 0.0)) + burn)
				if not bool(st("lit", false)):
					state["lit"] = true
					swap_block(id)
				write()
				if Tech.interaction != null:
					Tech.interaction._consume(stack)
				sound(&"fire_feed")
				return true
		Events.toast("%s — %.0fs of fuel left." % [display_name, float(st("fuel", 0.0))], "info")
		return true

	func build_visual() -> Node3D:
		return ObjVisual.glow(center() + Vector3(0.0, 0.2, 0.0), Color(1.0, 0.55, 0.18), 0.8, 1.4)

	func update_visual(_delta: float) -> void:
		if visual == null:
			return
		visual.visible = bool(st("lit", false))
		ObjVisual.pulse(visual, float(Game.tick) * 0.05, 0.12)


# ===========================================================================
#  Sprinkler — waters farmland in a radius
# ===========================================================================
class Sprinkler extends ObjMachines.Wired:
	func on_tick(_delta: float) -> void:
		if wire_in > 0 and not powered():
			return
		var r := int(def.get("radius", 4))
		var right := View.right()
		# Sprays across the plane and one layer either side, so a farm laid out
		# in depth is watered too.
		for l in range(-r, r + 1):
			for d in range(-1, 2):
				var q := World.normalize(pos + right * l + View.depth_step() * d)
				var bt := World.block_type_at(q)
				if bt.on_random_tick.is_valid() and bt.has_tag(&"crop"):
					bt.on_random_tick.call(q)
		particles(&"water_spray", 3)


# ===========================================================================
#  Healing station — restores captured creatures and the player
# ===========================================================================
class HealingStation extends ObjMachines.Wired:
	func on_interact(player: Node) -> bool:
		var p := player as VoxelEntity
		if p != null:
			p.heal(p.max_health)
			Events.player_healed.emit(p.max_health)
		# Refill capture pods in the inventory, if the entities agent supports it.
		var inv: Variant = player.get("inventory") if player != null else null
		if inv != null and inv.has_method(&"heal_capture_pods"):
			inv.call(&"heal_capture_pods")
		particles(&"heal", 14)
		sound(&"heal_station")
		Events.toast("Healed.", "info")
		return true

	func build_visual() -> Node3D:
		return ObjVisual.field(center() + Vector3(0.0, 0.4, 0.0), Color(0.4, 1.0, 0.6), 0.4, 1.2)

	func update_visual(delta: float) -> void:
		if visual != null:
			ObjVisual.spin(visual, delta, 0.9)


# ===========================================================================
#  Consoles — the front ends for this agent's own systems
# ===========================================================================
class TechConsole extends ObjBase:
	func on_interact(_player: Node) -> bool:
		UI.open("tech", {"object": self, "slots": Tech.SLOTS,
			"available": Tech.available(), "state": Tech.hud_state()})
		Events.ui_panel_opened.emit("tech")
		sound(&"station_open")
		Events.toast("Tech console: %d techs unlocked." % Tech.unlocked.size(), "info")
		return true

	func build_visual() -> Node3D:
		return ObjVisual.panel(center() + Vector3(0.0, 0.2, 0.0), Color(0.5, 0.85, 1.0), 0.6)

	func update_visual(_delta: float) -> void:
		if visual != null:
			visual.basis = View.camera_basis()


class ManipulatorBench extends ObjBase:
	func on_interact(_player: Node) -> bool:
		UI.open("manipulator", {"object": self,
			"tracks": Tech.beam.describe() if Tech.beam != null else []})
		Events.ui_panel_opened.emit("manipulator")
		sound(&"station_open")
		if Tech.beam != null:
			Events.toast("Manipulator: %dx%d, tier %d, x%.2f speed" % [
				Tech.beam.radius(), Tech.beam.radius(), Tech.beam.tier(),
				Tech.beam.speed()], "info")
		return true

	func build_visual() -> Node3D:
		return ObjVisual.glow(center() + Vector3(0.0, 0.35, 0.0), Color(0.55, 0.95, 0.85), 0.4, 1.2)


class Jukebox extends ObjMachines.Wired:
	func on_interact(_player: Node) -> bool:
		var playing := not bool(st("playing", false))
		state["playing"] = playing
		write()
		if playing and Audio.has_method(&"play_music"):
			Audio.call(&"play_music", &"jukebox")
		else:
			sound(&"jukebox")
		Events.toast("Jukebox %s." % ("playing" if playing else "stopped"), "info")
		return true

	func on_power_edge(now_on: bool) -> void:
		state["playing"] = now_on
		write()


class Mailbox extends ObjBase:
	func on_interact(_player: Node) -> bool:
		Events.toast("The mailbox is empty.", "info")
		sound(&"mailbox")
		return true


# ===========================================================================
#  Registration
# ===========================================================================
static func register_all() -> void:
	ObjRegistry.define(&"teleporter_pad", "Teleporter Pad", &"utility", TeleporterPad, {
		"color": Color(0.42, 0.62, 0.78), "pattern": BlockType.Pattern.CIRCUIT,
		"hardness": 4.0, "tool": &"pickaxe", "tier": 2, "light": 9,
		"emission": 1.0, "wire_in": 1, "value": 1400,
		"rarity": Const.RARITY_RARE, "category": &"objects",
		"tags": [&"utility", &"teleporter", &"wired"],
		"desc": "Links to another pad. Wire two together with the wire tool.",
	})
	ObjRegistry.define(&"waypoint_flag", "Waypoint Flag", &"utility", Waypoint, {
		"color": Color(0.90, 0.78, 0.30), "pattern": BlockType.Pattern.CLOTH,
		"hardness": 0.4, "solid": false, "opaque": false,
		"render": BlockType.Render.CROSS, "step": &"step_leaves",
		"value": 60, "category": &"objects", "tags": [&"utility", &"marker"],
		"desc": "Marks a spot on the map, and reads out its coordinates.",
	})
	ObjRegistry.define(&"campfire", "Campfire", &"utility", Campfire, {
		"color": Color(0.86, 0.44, 0.16), "pattern": BlockType.Pattern.ORGANIC,
		"hardness": 0.5, "solid": false, "opaque": false,
		"render": BlockType.Render.TRANSPARENT, "step": &"step_wood",
		"light": 13, "emission": 1.0, "tick": true,
		"heat": 18.0, "radius": 6.0, "value": 25,
		"category": &"objects", "tags": [&"utility", &"light_source", &"heat"],
		"desc": "Warmth and light. Feed it anything that burns.",
	})
	ObjRegistry.define(&"brazier", "Brazier", &"utility", Campfire, {
		"color": Color(0.80, 0.52, 0.22), "pattern": BlockType.Pattern.METAL,
		"hardness": 1.6, "light": 14, "emission": 1.0, "tick": true,
		"heat": 24.0, "radius": 8.0, "value": 120,
		"category": &"objects", "tags": [&"utility", &"light_source", &"heat"],
		"desc": "A longer-burning fire in a metal bowl.",
	})
	ObjRegistry.define(&"sprinkler", "Sprinkler", &"utility", Sprinkler, {
		"color": Color(0.46, 0.68, 0.80), "pattern": BlockType.Pattern.METAL,
		"hardness": 1.8, "tick": true, "wire_in": 1, "radius": 4,
		"value": 200, "category": &"objects", "tags": [&"utility", &"farming", &"wired"],
		"desc": "Waters crops across the plane and one layer either side.",
	})
	ObjRegistry.define(&"healing_station", "Healing Station", &"utility", HealingStation, {
		"color": Color(0.52, 0.86, 0.62), "pattern": BlockType.Pattern.CIRCUIT,
		"hardness": 3.0, "tool": &"pickaxe", "tier": 1, "light": 8,
		"emission": 0.9, "wire_in": 1, "value": 780,
		"rarity": Const.RARITY_UNCOMMON, "category": &"objects",
		"tags": [&"utility", &"healing", &"wired"],
		"desc": "Restores your health and revives captured creatures.",
	})
	ObjRegistry.define(&"beacon", "Beacon", &"utility", Waypoint, {
		"color": Color(0.60, 0.90, 1.0), "pattern": BlockType.Pattern.CRYSTAL,
		"hardness": 2.4, "tool": &"pickaxe", "tier": 1, "light": 15,
		"emission": 1.0, "value": 500, "rarity": Const.RARITY_UNCOMMON,
		"category": &"objects", "tags": [&"utility", &"marker", &"light_source"],
		"desc": "A waypoint you can see from across the plane.",
	})
	ObjRegistry.define(&"tech_console", "Tech Console", &"utility", TechConsole, {
		"color": Color(0.38, 0.60, 0.78), "pattern": BlockType.Pattern.CIRCUIT,
		"hardness": 3.2, "tool": &"pickaxe", "tier": 1, "light": 7,
		"emission": 0.9, "value": 850, "rarity": Const.RARITY_UNCOMMON,
		"category": &"objects", "tags": [&"utility", &"tech"],
		"desc": "Swap techs between your head, body and leg slots.",
	})
	ObjRegistry.define(&"manipulator_bench", "Manipulator Bench", &"utility", ManipulatorBench, {
		"color": Color(0.48, 0.72, 0.66), "pattern": BlockType.Pattern.METAL,
		"hardness": 3.0, "tool": &"pickaxe", "tier": 1, "light": 5,
		"emission": 0.7, "value": 640, "rarity": Const.RARITY_UNCOMMON,
		"category": &"objects", "tags": [&"utility", &"tech"],
		"desc": "Spends manipulator modules on beam upgrades.",
	})
	ObjRegistry.define(&"jukebox", "Jukebox", &"utility", Jukebox, {
		"color": Color(0.66, 0.42, 0.62), "pattern": BlockType.Pattern.METAL,
		"hardness": 2.0, "wire_in": 1, "light": 4, "value": 320,
		"category": &"objects", "tags": [&"utility", &"decor", &"wired"],
		"desc": "Plays music. Wire it to a plane sensor for a room that sings when you look at it.",
	})
	ObjRegistry.define(&"mailbox", "Mailbox", &"utility", Mailbox, {
		"color": Color(0.44, 0.50, 0.56), "pattern": BlockType.Pattern.METAL,
		"hardness": 1.4, "value": 90, "category": &"objects",
		"tags": [&"utility", &"decor"],
		"desc": "Somewhere for the post to arrive, one day.",
	})
