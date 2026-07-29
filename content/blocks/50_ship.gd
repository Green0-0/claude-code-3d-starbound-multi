## Ship, station and outpost construction blocks.
##
## Owned by the space agent. Everything here is prefixed `ship_` so it can never
## collide with another content file, even the pieces that end up standing in
## the Outpost rather than on a hull.
##
## Categories used: `building` for structure, `light` for emitters, `special`
## for the invisible spawn marker. Tags follow the `00_core.gd` vocabulary and
## add one of our own, `ship_set`, so the crafting agent can offer the whole
## family from a single query: `Blocks.all_with_tag(&"ship_set")`.
##
## Interactive blocks install `on_interact` hooks that route straight into the
## `space/` singletons — opening the star map, the fuel hatch, the teleporter
## menu and so on. All of those calls are guarded, so a missing UI panel
## degrades to a toast rather than an error.
class_name SpcShipBlocks
extends RefCounted

const HULL := Color(0.62, 0.66, 0.72)
const HULL_DARK := Color(0.40, 0.44, 0.50)
const TRIM := Color(0.85, 0.62, 0.24)
const GLASS := Color(0.55, 0.78, 0.92, 0.40)
const GLOW := Color(0.45, 0.88, 1.0)


static func register_all(reg) -> void:
	# ------------------------------------------------------------- structure
	_part(reg, &"ship_hull", "Ship Hull", HULL, HULL_DARK,
		BlockType.Pattern.METAL, 2.4, 1)
	_part(reg, &"ship_hull_heavy", "Reinforced Hull", HULL.darkened(0.25),
		Color(0.30, 0.33, 0.38), BlockType.Pattern.METAL, 4.5, 2)
	_part(reg, &"ship_wall", "Ship Wall Panel", Color(0.70, 0.73, 0.78),
		Color(0.52, 0.56, 0.62), BlockType.Pattern.BRICK, 2.0, 1)
	_part(reg, &"ship_floor", "Ship Deck Plate", Color(0.48, 0.52, 0.58),
		Color(0.34, 0.37, 0.42), BlockType.Pattern.METAL, 2.2, 1)
	_part(reg, &"ship_floor_grate", "Deck Grating", Color(0.40, 0.44, 0.48),
		Color(0.24, 0.26, 0.30), BlockType.Pattern.CIRCUIT, 2.0, 1)
	_part(reg, &"ship_pipe", "Conduit", Color(0.55, 0.50, 0.40),
		Color(0.36, 0.32, 0.26), BlockType.Pattern.METAL, 1.8, 1)
	_part(reg, &"ship_door_frame", "Bulkhead Frame", TRIM, HULL_DARK,
		BlockType.Pattern.METAL, 3.0, 1)
	_part(reg, &"ship_banner", "Ship Banner", Color(0.72, 0.28, 0.34),
		Color(0.45, 0.16, 0.22), BlockType.Pattern.CLOTH, 0.4, 0)

	# ----------------------------------------------------------------- glass
	reg.define(&"ship_window", "Viewport").look(GLASS, BlockType.Pattern.GLASS,
			Color(0.78, 0.90, 1.0, 0.5)) \
		.mode(BlockType.Render.TRANSPARENT).mining(1.6, &"pickaxe", 1) \
		.sounds(&"step_glass").in_category(&"building") \
		.tag(&"glass").tag(&"ship_set")

	# ---------------------------------------------------------------- lights
	reg.define(&"ship_light", "Cabin Light").look(Color(0.92, 0.96, 1.0),
			BlockType.Pattern.FLAT, GLOW) \
		.glows(14, 0.95).mining(0.8, &"pickaxe", 0).sounds(&"step_glass") \
		.in_category(&"light").tag(&"light_source").tag(&"ship_set")
	reg.define(&"ship_engine", "Drive Core").look(Color(0.30, 0.36, 0.46),
			BlockType.Pattern.CIRCUIT, Color(0.35, 0.85, 1.0)) \
		.glows(13, 1.0).mining(6.0, &"pickaxe", 2).sounds(&"step_metal") \
		.in_category(&"light").tag(&"metal").tag(&"ship_set") \
		.flags({"blast_resistance": 60.0})

	# ------------------------------------------------------------ furniture
	_fixture(reg, &"ship_locker", "Storage Locker", Color(0.46, 0.50, 0.56),
		TRIM, BlockType.Pattern.METAL, 2.0)
	_fixture(reg, &"ship_crate", "Cargo Crate", Color(0.52, 0.44, 0.30),
		Color(0.34, 0.28, 0.18), BlockType.Pattern.PLANK, 1.4)
	_fixture(reg, &"ship_bed", "Crew Bunk", Color(0.30, 0.40, 0.62),
		Color(0.78, 0.80, 0.86), BlockType.Pattern.CLOTH, 1.0)
	_fixture(reg, &"ship_planter", "Hydroponic Planter", Color(0.34, 0.52, 0.36),
		Color(0.24, 0.30, 0.34), BlockType.Pattern.ORGANIC, 1.2)
	_fixture(reg, &"ship_vendor_stall", "Vendor Counter", Color(0.58, 0.46, 0.32),
		TRIM, BlockType.Pattern.PLANK, 1.6)

	# ------------------------------------------------------------- terminals
	_terminal(reg, &"ship_console", "Ship Console", Color(0.26, 0.30, 0.38), GLOW)
	_terminal(reg, &"ship_fuel_hatch", "Fuel Hatch", Color(0.34, 0.30, 0.20),
		Color(0.95, 0.72, 0.30))
	_terminal(reg, &"ship_printer", "3D Printer", Color(0.30, 0.34, 0.40),
		Color(0.55, 0.95, 0.70))
	_terminal(reg, &"ship_research", "Research Terminal", Color(0.28, 0.26, 0.40),
		Color(0.80, 0.60, 1.0))

	# ------------------------------------------------------------ mechanics
	reg.define(&"ship_ladder", "Ship Ladder").look(Color(0.66, 0.68, 0.72),
			BlockType.Pattern.METAL, HULL_DARK) \
		.mode(BlockType.Render.CROSS).mining(0.8, &"pickaxe", 0) \
		.sounds(&"step_metal").in_category(&"building") \
		.flags({"climbable": true, "solid": false}) \
		.tag(&"ladder").tag(&"climbable").tag(&"ship_set")

	reg.define(&"ship_teleporter_pad", "Teleporter Pad").look(Color(0.22, 0.30, 0.42),
			BlockType.Pattern.CIRCUIT, GLOW) \
		.glows(10, 0.8).mining(3.0, &"pickaxe", 1).sounds(&"step_metal") \
		.in_category(&"building").tag(&"teleporter").tag(&"ship_set")

	reg.define(&"ship_ark_gate", "Ark Gateway").look(Color(0.72, 0.66, 0.48),
			BlockType.Pattern.STRATA, Color(0.94, 0.86, 0.52)) \
		.glows(8, 0.6).mining(999.0, &"pickaxe", 99).sounds(&"step_stone") \
		.in_category(&"special").tag(&"unbreakable").tag(&"ship_set") \
		.flags({"breakable": false, "blast_resistance": 9999.0})

	## Invisible spawn / bookkeeping marker. Never solid, never breakable, never
	## replaceable — so the player cannot destroy or build over a spawn point.
	reg.define(&"ship_marker", "Marker").look(Color(1, 1, 1, 0), BlockType.Pattern.FLAT) \
		.mode(BlockType.Render.NONE).mining(999.0, &"any", 99) \
		.in_category(&"special").tag(&"marker").tag(&"spawner") \
		.flags({"breakable": false, "replaceable": false, "solid": false,
			"opaque": false, "blast_resistance": 9999.0})

	_install_hooks(reg)


# ---------------------------------------------------------------- builders
static func _part(reg, name: StringName, display: String, col: Color, alt: Color,
		pat: BlockType.Pattern, hardness: float, tier: int) -> BlockType:
	var bt: BlockType = reg.define(name, display)
	bt.look(col, pat, alt)
	bt.mining(hardness, &"pickaxe", tier)
	bt.sounds(&"step_metal")
	bt.in_category(&"building")
	bt.tag(&"metal").tag(&"ship_set")
	return bt


static func _fixture(reg, name: StringName, display: String, col: Color, alt: Color,
		pat: BlockType.Pattern, hardness: float) -> BlockType:
	var bt: BlockType = reg.define(name, display)
	bt.look(col, pat, alt)
	bt.mining(hardness, &"any", 0)
	bt.sounds(&"step_metal")
	bt.in_category(&"building")
	bt.tag(&"decor").tag(&"ship_set")
	return bt


static func _terminal(reg, name: StringName, display: String, col: Color, glow: Color) -> BlockType:
	var bt: BlockType = reg.define(name, display)
	bt.look(col, BlockType.Pattern.CIRCUIT, glow)
	bt.glows(7, 0.7)
	bt.mining(3.2, &"pickaxe", 1)
	bt.sounds(&"step_metal")
	bt.in_category(&"building")
	bt.tag(&"metal").tag(&"decor").tag(&"ship_set")
	return bt


# ============================================================ interaction hooks
## Wire the interactive blocks to the `space/` singletons. Everything is looked
## up through the tile-data payload stamped by `ship_interior.gd` /
## `outpost.gd`, so the same block can be a star map here and a fuel hatch there.
static func _install_hooks(reg) -> void:
	_hook(reg, &"ship_console", SpcShipBlocks._on_terminal)
	_hook(reg, &"ship_fuel_hatch", SpcShipBlocks._on_terminal)
	_hook(reg, &"ship_printer", SpcShipBlocks._on_terminal)
	_hook(reg, &"ship_research", SpcShipBlocks._on_terminal)
	_hook(reg, &"ship_ark_gate", SpcShipBlocks._on_terminal)
	_hook(reg, &"ship_locker", SpcShipBlocks._on_terminal)
	_hook(reg, &"ship_crate", SpcShipBlocks._on_terminal)
	_hook(reg, &"ship_teleporter_pad", SpcShipBlocks._on_pad)
	_hook(reg, &"ship_vendor_stall", SpcShipBlocks._on_terminal)


static func _hook(reg, name: StringName, fn: Callable) -> void:
	var bt: BlockType = reg.get_by_name(name)
	if bt != null:
		bt.on_interact = fn


## Role dispatch for every fixed terminal in the game.
static func _on_terminal(pos: Vector3i, _player: Node) -> bool:
	var data := SpcStamp.tile_at(pos)
	var role := String(data.get("role", ""))
	match role:
		"star_map":
			UI.open("star_map", {"origin": pos})
			Events.ui_panel_opened.emit("star_map")
			return true
		"ship_status":
			UI.open("ship_status", {"origin": pos})
			Events.toast("%s — hull %s, FTL %s, fuel %d/%d." % [
				"Ship status", Universe.upgrades.hull_name(),
				Universe.upgrades.ftl_name(), Universe.fuel(),
				Universe.fuel_capacity()], "info")
			return true
		"fuel_hatch":
			UI.open("fuel_hatch", {"origin": pos})
			Universe.upgrades.refuel_from_inventory()
			return true
		"teleporter":
			UI.open("teleporter", {"origin": pos})
			return true
		"ark_gateway":
			UI.open("ark", {"origin": pos})
			Events.toast("The Ark hums, waiting for something you do not have yet.", "info")
			return true
		"quest_board":
			UI.open("quests", {"origin": pos})
			return true
		"printer":
			UI.open("printer", {"origin": pos})
			Events.station_opened.emit("printer", null)
			return true
		"research":
			UI.open("research", {"origin": pos})
			Events.station_opened.emit("research", null)
			return true
		"crafting":
			Events.station_opened.emit("crafting", null)
			return true
		"shop":
			Events.station_opened.emit("shop_" + String(data.get("vendor", "general")), null)
			return true
		"captain_locker", "cargo":
			UI.open("container", {"origin": pos, "slots": int(data.get("slots", 16))})
			return true
	return false


## Standing on a pad and pressing interact opens the teleporter network.
static func _on_pad(pos: Vector3i, _player: Node) -> bool:
	var data := SpcStamp.tile_at(pos)
	if data.is_empty():
		# A pad the player placed themselves: register it the first time it is used.
		Universe.teleporter.register_pad(World.planet_id, pos)
	UI.open("teleporter", {"origin": pos})
	Events.toast("Teleporter online.", "info")
	return true
