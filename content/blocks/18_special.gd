## Marker blocks, unbreakable shells — and the **perspective-aware blocks**,
## which are the signature of this game.
##
## A perspective block is one whose behaviour is a function of `View.view`
## (which of the four planes you are looking from) or `View.layer` /
## `View.is_play_layer(pos)` (which depth slice you are standing in). They turn
## the camera from a presentation detail into a puzzle verb: the same wall is a
## wall or a doorway depending on where you stand.
##
## Three implementation techniques are used, all cheap:
##
##  1. **Parity blocks** (`phase_block`, `phase_block_inverse`,
##     `parallax_glass`, `phase_ladder`) rewrite their own entry in the
##     registry's hot lookup arrays once per flip, in `_refresh_parity`. The
##     cost is a handful of byte writes per *flip*, never per frame, and
##     `VoxelPhysics` picks the change up immediately because it reads
##     `Blocks.is_solid(id)` from those arrays. Opacity is deliberately left
##     alone so no chunk ever needs remeshing.
##  2. **Contact hooks** (`on_entity_inside`) for anything that reacts to the
##     player being in the block: anchor rune, layer gate, shift pads, depth
##     rail, facing spike. These run only while an entity overlaps the voxel.
##  3. **Random ticks** for the sightline lamp, which swaps itself between a
##     lit and an unlit twin depending on whether it shares the play layer.
##
## `on_interact` blocks (compass stone, perspective prism, teleporter pad)
## return `true` to say they consumed the interaction.
class_name PsPerspective
extends RefCounted

## name -> true if the block is "active" on EVEN view indices (0 = North,
## 2 = South). Odd views are 1 = West, 3 = East.
const PARITY_SOLID := {
	&"phase_block": true,
	&"phase_block_inverse": false,
	&"parallax_glass": false,
}
const PARITY_CLIMB := {
	&"phase_ladder": true,
}

## Physics frame on which the anchor rune last held the player. -1 = idle.
static var _anchor_frame: int = -1
## True when *we* were the ones who cleared `View.flips_enabled`, so a cutscene
## disabling flips for its own reasons is never stomped on.
static var _anchor_owned: bool = false
## Re-entrancy guard for the echo block's mirrored writes.
static var _echo_busy: bool = false


static func register_all(reg) -> void:
	_markers(reg)
	_parity(reg)
	_contact(reg)
	_interactive(reg)
	_connect_runtime()


# ===========================================================================
#  Plain special blocks
# ===========================================================================
static func _markers(reg) -> void:
	reg.define(&"bedrock_shell", "Bedrock Shell").look(Color(0.14, 0.13, 0.18), BlockType.Pattern.STRATA, Color(0.09, 0.08, 0.12)) \
		.mining(999.0, &"pickaxe", 99).sounds(&"step_stone").in_category(&"special") \
		.tag(&"unbreakable").tag(&"marker") \
		.flags({"breakable": false, "blast_resistance": 9999.0})
	reg.define(&"sky_ceiling", "Sky Ceiling").look(Color(0.30, 0.44, 0.68, 0.10), BlockType.Pattern.FLAT) \
		.mode(BlockType.Render.NONE).mining(999.0, &"any", 99).sounds(&"step_stone") \
		.in_category(&"special").tag(&"unbreakable").tag(&"marker") \
		.flags({"solid": true, "breakable": false, "blast_resistance": 9999.0})
	reg.define(&"barrier", "Barrier").look(Color(0.90, 0.20, 0.90, 0.12), BlockType.Pattern.FLAT) \
		.mode(BlockType.Render.NONE).mining(999.0, &"any", 99).sounds(&"step_stone") \
		.in_category(&"special").tag(&"unbreakable").tag(&"marker") \
		.flags({"solid": true, "breakable": false, "blast_resistance": 9999.0})
	reg.define(&"structure_marker", "Structure Marker").look(Color(0.20, 0.90, 0.40, 0.20), BlockType.Pattern.FLAT) \
		.mode(BlockType.Render.NONE).mining(0.0, &"any", 0).sounds(&"step_stone") \
		.in_category(&"special").tag(&"marker") \
		.flags({"solid": false, "replaceable": true, "breakable": false})
	# The entities agent should attach `on_random_tick` to this one; the block
	# itself only declares the contract (`spawner` tag + tile_data storage).
	reg.define(&"monster_spawner", "Monster Spawner").look(Color(0.18, 0.16, 0.22), BlockType.Pattern.CIRCUIT, Color(0.72, 0.24, 0.86)) \
		.mining(6.0, &"pickaxe", 2).sounds(&"step_stone").glows(5, 0.8) \
		.in_category(&"special").tag(&"spawner").tag(&"marker").tag(&"light_source") \
		.flags({"blast_resistance": 40.0})
	# Likewise the objects agent owns what a tech chest actually contains.
	reg.define(&"tech_chest_block", "Tech Chest").look(Color(0.34, 0.38, 0.44), BlockType.Pattern.METAL, Color(0.40, 0.86, 1.00)) \
		.mining(4.0, &"pickaxe", 2).sounds(&"step_metal").glows(4, 0.6) \
		.in_category(&"special").tag(&"container").tag(&"metal").tag(&"quest_locked")
	reg.define(&"quest_seal", "Quest Seal").look(Color(0.24, 0.20, 0.34), BlockType.Pattern.CRYSTAL, Color(0.96, 0.78, 0.34)) \
		.mining(999.0, &"pickaxe", 99).sounds(&"step_stone").glows(7, 1.0) \
		.in_category(&"special").tag(&"quest_locked").tag(&"unbreakable").tag(&"marker") \
		.flags({"breakable": false, "blast_resistance": 9999.0})
	reg.define(&"void_stone", "Void Stone").look(Color(0.05, 0.04, 0.09), BlockType.Pattern.NOISE, Color(0.26, 0.14, 0.42)) \
		.mining(14.0, &"pickaxe", 5).sounds(&"step_stone").in_category(&"special") \
		.tag(&"stone").tag(&"stratum_core") \
		.flags({"blast_resistance": 2000.0, "damage_element": Const.ELEM_COSMIC})


# ===========================================================================
#  Perspective: parity blocks
# ===========================================================================
static func _parity(reg) -> void:
	# Solid from North/South, thin air from West/East. Registered in its
	# view-0 (even) state because a new game always starts on view 0.
	reg.define(&"phase_block", "Phase Block").look(Color(0.42, 0.56, 0.86, 0.75), BlockType.Pattern.CRYSTAL, Color(0.70, 0.86, 1.00)) \
		.mode(BlockType.Render.TRANSPARENT).mining(2.5, &"pickaxe", 1).sounds(&"step_glass") \
		.glows(4, 0.6).in_category(&"special").tag(&"perspective").tag(&"phase") \
		.flags({"solid": true})
	reg.define(&"phase_block_inverse", "Inverted Phase Block").look(Color(0.86, 0.52, 0.42, 0.75), BlockType.Pattern.CRYSTAL, Color(1.00, 0.80, 0.66)) \
		.mode(BlockType.Render.TRANSPARENT).mining(2.5, &"pickaxe", 1).sounds(&"step_glass") \
		.glows(4, 0.6).in_category(&"special").tag(&"perspective").tag(&"phase") \
		.flags({"solid": false})
	reg.define(&"parallax_glass", "Parallax Glass").look(Color(0.72, 0.92, 0.88, 0.35), BlockType.Pattern.GLASS, Color(0.44, 0.78, 0.74)) \
		.mode(BlockType.Render.TRANSPARENT).mining(1.4, &"pickaxe", 1).sounds(&"step_glass") \
		.in_category(&"special").tag(&"perspective").tag(&"phase").tag(&"glass") \
		.flags({"solid": false})
	reg.define(&"phase_ladder", "Phase Ladder").look(Color(0.60, 0.70, 0.98, 0.60), BlockType.Pattern.PLANK, Color(0.36, 0.46, 0.76)) \
		.mode(BlockType.Render.TRANSPARENT).mining(0.8, &"any", 0).sounds(&"step_glass") \
		.glows(3, 0.5).in_category(&"special").tag(&"perspective").tag(&"phase") \
		.tag(&"ladder").tag(&"climbable").flags({"solid": false, "climbable": true})

	for bt: BlockType in [reg.get_by_name(&"phase_block"), reg.get_by_name(&"phase_block_inverse"),
			reg.get_by_name(&"parallax_glass"), reg.get_by_name(&"phase_ladder")]:
		if bt != null:
			bt.description = "Its substance depends on which way you are looking."


# ===========================================================================
#  Perspective: contact blocks
# ===========================================================================
static func _contact(reg) -> void:
	var anchor: BlockType = reg.define(&"anchor_rune", "Anchor Rune")
	anchor.look(Color(0.94, 0.72, 0.24), BlockType.Pattern.CIRCUIT, Color(0.36, 0.24, 0.10))
	anchor.mode(BlockType.Render.CROSS)
	anchor.mining(1.5, &"pickaxe", 1)
	anchor.glows(6, 0.9)
	anchor.sounds(&"step_stone")
	anchor.description = "Stand on it and the world refuses to turn."
	anchor.in_category(&"special").tag(&"perspective").tag(&"marker").tag(&"light_source")
	anchor.on_entity_inside = Callable(PsPerspective, "on_anchor_rune")

	var gate: BlockType = reg.define(&"layer_gate", "Layer Gate")
	gate.look(Color(0.56, 0.36, 0.86, 0.40), BlockType.Pattern.GLASS, Color(0.86, 0.66, 1.00))
	gate.mode(BlockType.Render.TRANSPARENT)
	gate.mining(2.0, &"pickaxe", 1)
	gate.glows(5, 0.8)
	gate.sounds(&"step_glass")
	gate.description = "Walk into it and it pushes back. Shift into it and it lets you through."
	gate.in_category(&"special").tag(&"perspective").tag(&"marker")
	gate.flags({"solid": false})
	gate.on_entity_inside = Callable(PsPerspective, "on_layer_gate")

	var pad_in: BlockType = reg.define(&"shift_pad_deeper", "Deepening Pad")
	pad_in.look(Color(0.24, 0.62, 0.86), BlockType.Pattern.CIRCUIT, Color(0.60, 0.94, 1.00))
	pad_in.mode(BlockType.Render.TRANSPARENT)
	pad_in.mining(2.0, &"pickaxe", 1)
	pad_in.glows(8, 1.0)
	pad_in.sounds(&"step_metal")
	pad_in.description = "Steps you one layer away from the camera."
	pad_in.in_category(&"special").tag(&"perspective").tag(&"light_source")
	pad_in.flags({"solid": false})
	pad_in.on_entity_inside = Callable(PsPerspective, "on_shift_pad_deeper")

	var pad_out: BlockType = reg.define(&"shift_pad_nearer", "Surfacing Pad")
	pad_out.look(Color(0.86, 0.56, 0.24), BlockType.Pattern.CIRCUIT, Color(1.00, 0.86, 0.60))
	pad_out.mode(BlockType.Render.TRANSPARENT)
	pad_out.mining(2.0, &"pickaxe", 1)
	pad_out.glows(8, 1.0)
	pad_out.sounds(&"step_metal")
	pad_out.description = "Steps you one layer toward the camera."
	pad_out.in_category(&"special").tag(&"perspective").tag(&"light_source")
	pad_out.flags({"solid": false})
	pad_out.on_entity_inside = Callable(PsPerspective, "on_shift_pad_nearer")

	var rail: BlockType = reg.define(&"depth_rail", "Drift Rail")
	rail.look(Color(0.30, 0.86, 0.72, 0.45), BlockType.Pattern.CIRCUIT, Color(0.70, 1.00, 0.92))
	rail.mode(BlockType.Render.TRANSPARENT)
	rail.mining(1.8, &"pickaxe", 1)
	rail.glows(6, 0.9)
	rail.sounds(&"step_metal")
	rail.description = "Sweeps you along screen-right — whichever world axis that is right now."
	rail.in_category(&"special").tag(&"perspective").tag(&"light_source")
	rail.flags({"solid": false})
	rail.on_entity_inside = Callable(PsPerspective, "on_depth_rail")

	var spike: BlockType = reg.define(&"facing_spike", "Facing Spike")
	spike.look(Color(0.72, 0.24, 0.36, 0.80), BlockType.Pattern.CRYSTAL, Color(0.98, 0.62, 0.68))
	spike.mode(BlockType.Render.TRANSPARENT)
	spike.mining(2.2, &"pickaxe", 1)
	spike.sounds(&"step_stone")
	spike.description = "The blades only point at you from East and West."
	spike.in_category(&"special").tag(&"perspective").tag(&"hazard")
	spike.flags({"solid": false})
	spike.on_entity_inside = Callable(PsPerspective, "on_facing_spike")

	# Sightline lamp + its unlit twin. Only lights the layer you are standing
	# in; step one layer away and it goes dark.
	var lamp: BlockType = reg.define(&"sightline_lamp", "Sightline Lamp")
	lamp.look(Color(1.00, 0.94, 0.72), BlockType.Pattern.CRYSTAL, Color(0.44, 0.40, 0.30))
	lamp.mining(2.0, &"pickaxe", 1)
	lamp.glows(14, 1.0)
	lamp.sounds(&"step_glass")
	lamp.description = "Burns only for the layer it shares with you."
	lamp.drop(&"sightline_lamp")
	lamp.in_category(&"special").tag(&"perspective").tag(&"light_source")
	lamp.on_random_tick = Callable(PsPerspective, "on_sightline_tick")

	var lamp_dim: BlockType = reg.define(&"sightline_lamp_dim", "Sightline Lamp (Dark)")
	lamp_dim.look(Color(0.40, 0.38, 0.32), BlockType.Pattern.CRYSTAL, Color(0.26, 0.25, 0.22))
	lamp_dim.mining(2.0, &"pickaxe", 1)
	lamp_dim.sounds(&"step_glass")
	lamp_dim.description = "Dormant. It is watching a layer you are not in."
	lamp_dim.drop(&"sightline_lamp")
	lamp_dim.in_category(&"special").tag(&"perspective")
	lamp_dim.on_random_tick = Callable(PsPerspective, "on_sightline_tick")

	var echo: BlockType = reg.define(&"echo_block", "Echo Block")
	echo.look(Color(0.52, 0.48, 0.72), BlockType.Pattern.STRATA, Color(0.80, 0.76, 0.96))
	echo.mining(3.0, &"pickaxe", 2)
	echo.glows(2, 0.4)
	echo.sounds(&"step_stone")
	echo.description = "Whatever is built against one face appears on the other."
	echo.in_category(&"special").tag(&"perspective")
	echo.on_neighbour_changed = Callable(PsPerspective, "on_echo_neighbour")


# ===========================================================================
#  Perspective: interaction blocks
# ===========================================================================
static func _interactive(reg) -> void:
	var compass: BlockType = reg.define(&"compass_stone", "Compass Stone")
	compass.look(Color(0.66, 0.62, 0.50), BlockType.Pattern.STRATA, Color(0.92, 0.82, 0.36))
	compass.mining(3.0, &"pickaxe", 1)
	compass.glows(3, 0.5)
	compass.sounds(&"step_stone")
	compass.description = "Turn it and the world turns a quarter with you."
	compass.in_category(&"special").tag(&"perspective").tag(&"decor")
	compass.on_interact = Callable(PsPerspective, "on_compass_stone")

	var prism: BlockType = reg.define(&"perspective_prism", "Perspective Prism")
	prism.look(Color(0.86, 0.72, 1.00, 0.60), BlockType.Pattern.CRYSTAL, Color(0.42, 0.30, 0.66))
	prism.mode(BlockType.Render.TRANSPARENT)
	prism.mining(4.0, &"pickaxe", 2)
	prism.glows(10, 1.0)
	prism.sounds(&"step_glass")
	prism.description = "Snaps the camera to the opposite plane in one step."
	prism.in_category(&"special").tag(&"perspective").tag(&"light_source")
	prism.flags({"solid": true})
	prism.on_interact = Callable(PsPerspective, "on_perspective_prism")

	var pad: BlockType = reg.define(&"warp_pad", "Teleporter Pad")
	pad.look(Color(0.26, 0.30, 0.44), BlockType.Pattern.CIRCUIT, Color(0.50, 0.92, 1.00))
	pad.mining(5.0, &"pickaxe", 2)
	pad.glows(11, 1.0)
	pad.sounds(&"step_metal")
	pad.description = "A beam-out point. Links to the ship once it is powered."
	pad.in_category(&"special").tag(&"teleporter").tag(&"metal").tag(&"light_source")
	pad.on_interact = Callable(PsPerspective, "on_teleporter_pad")


# ===========================================================================
#  Runtime wiring
# ===========================================================================
static func _connect_runtime() -> void:
	var flip_cb := Callable(PsPerspective, "on_view_settled")
	if not Events.view_flip_finished.is_connected(flip_cb):
		Events.view_flip_finished.connect(flip_cb)
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree := loop as SceneTree
		var tick_cb := Callable(PsPerspective, "on_physics_frame")
		if not tree.physics_frame.is_connected(tick_cb):
			tree.physics_frame.connect(tick_cb)


## Rewrite the parity blocks' entries in the registry's hot arrays. Called once
## per completed flip — never per frame.
static func on_view_settled(view: int) -> void:
	var even := (view & 1) == 0
	for n: StringName in PARITY_SOLID:
		_set_lut(n, true, PARITY_SOLID[n] == even)
	for n: StringName in PARITY_CLIMB:
		_set_lut(n, false, PARITY_CLIMB[n] == even)


static func _set_lut(p_name: StringName, is_solid_field: bool, want: bool) -> void:
	if not Blocks.has(p_name):
		return
	var bt: BlockType = Blocks.get_by_name(p_name)
	var byte: int = 1 if want else 0
	if is_solid_field:
		bt.solid = want
		var lut: PackedByteArray = Blocks.solid_lut
		if bt.id >= 0 and bt.id < lut.size():
			lut[bt.id] = byte
			Blocks.solid_lut = lut
	else:
		bt.climbable = want
		var lut: PackedByteArray = Blocks.climb_lut
		if bt.id >= 0 and bt.id < lut.size():
			lut[bt.id] = byte
			Blocks.climb_lut = lut


## Releases the anchor rune the frame after the player steps off it.
static func on_physics_frame() -> void:
	if _anchor_frame < 0:
		return
	if Engine.get_physics_frames() - _anchor_frame <= 1:
		return
	_anchor_frame = -1
	if _anchor_owned:
		_anchor_owned = false
		View.flips_enabled = true


# ===========================================================================
#  Block hooks
# ===========================================================================
## Anchor rune: while the player overlaps it, flips are refused.
static func on_anchor_rune(_pos: Vector3i, entity: Node, _delta: float) -> void:
	if entity == null or entity != Game.player:
		return
	_anchor_frame = Engine.get_physics_frames()
	if View.flips_enabled:
		View.flips_enabled = false
		_anchor_owned = true
		Events.flip_blocked.emit("anchored")


## Layer gate: solid to lateral movement, open to a depth shift.
static func on_layer_gate(pos: Vector3i, entity: Node, _delta: float) -> void:
	var body := entity as Node3D
	if body == null:
		return
	if body.has_method(&"is_shifting") and bool(body.call(&"is_shifting")):
		return
	if not body.has_method(&"set_plane_velocity"):
		return
	var centre := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	var push := signf(View.lateral_of(body.global_position) - View.lateral_of(centre))
	body.call(&"set_plane_velocity", (push if push != 0.0 else 1.0) * 4.0)


## Deepening pad: carries the player one layer away from the camera.
static func on_shift_pad_deeper(pos: Vector3i, entity: Node, _delta: float) -> void:
	_pad_shift(pos, entity, 1)


## Surfacing pad: carries the player one layer toward the camera.
static func on_shift_pad_nearer(pos: Vector3i, entity: Node, _delta: float) -> void:
	_pad_shift(pos, entity, -1)


static func _pad_shift(pos: Vector3i, entity: Node, dir: int) -> void:
	if entity == null or entity != Game.player:
		return
	if View.shifting or View.flipping or not View.is_play_layer(pos):
		return
	View.request_shift(dir)


## Drift rail: a conveyor written in plane space, so it always pushes toward
## screen-right no matter which world axis that currently is.
static func on_depth_rail(_pos: Vector3i, entity: Node, delta: float) -> void:
	if entity == null or not entity.has_method(&"set_plane_velocity"):
		return
	var v: float = float(entity.call(&"plane_velocity")) if entity.has_method(&"plane_velocity") else 0.0
	entity.call(&"set_plane_velocity", clampf(v + 26.0 * delta, -9.0, 9.0))


## Facing spike: the blades only exist along the X axis, so they can only reach
## you from the West and East planes.
static func on_facing_spike(_pos: Vector3i, entity: Node, delta: float) -> void:
	if entity == null or (View.view & 1) == 0:
		return
	if entity.has_method(&"apply_damage"):
		entity.call(&"apply_damage", 16.0 * delta, Const.ELEM_PHYSICAL, null)


## Sightline lamp: swaps itself for its dark twin whenever the play layer moves
## off it, so its light genuinely only reaches the slice you occupy.
static func on_sightline_tick(pos: Vector3i) -> void:
	var lit := View.is_play_layer(pos)
	var wanted_name: StringName = &"sightline_lamp" if lit else &"sightline_lamp_dim"
	var want := Blocks.id(wanted_name)
	if World.get_block(pos) != want:
		World.set_block(pos, want)


## Echo block: a change against one face is mirrored to the opposite face.
static func on_echo_neighbour(pos: Vector3i, from: Vector3i) -> void:
	if _echo_busy:
		return
	var mirror := pos - (from - pos)
	if World.get_block(mirror) != Const.AIR:
		return
	var src := World.get_block(from)
	if src == Const.AIR or Blocks.is_liquid(src):
		return
	_echo_busy = true
	World.set_block(mirror, src)
	_echo_busy = false


## Compass stone: one quarter turn clockwise.
static func on_compass_stone(_pos: Vector3i, _player: Node) -> bool:
	if not View.request_flip(1):
		return false
	Events.toast("The compass stone drags the world a quarter turn.", "info")
	return true


## Perspective prism: jump straight to the opposite plane.
static func on_perspective_prism(_pos: Vector3i, _player: Node) -> bool:
	return View.flip_to_view(View.view + 2)


## Teleporter pad: hands off to whichever module owns travel, defensively.
static func on_teleporter_pad(pos: Vector3i, _player: Node) -> bool:
	Events.play_sound.emit(&"teleport", Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	if UI != null and UI.has_method(&"open"):
		UI.call(&"open", "star_map", {"source": "teleporter_pad"})
		return true
	Events.toast("The pad hums, but nothing answers yet.", "warn")
	return true
