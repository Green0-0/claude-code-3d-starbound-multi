## Root script of `main.tscn`. Wires the scene tree into `Game`, drives the
## perspective state machine, and owns the few truly global input actions.
extends Node3D

@onready var world_renderer: Node3D = $WorldRenderer
@onready var entities_root: Node3D = $Entities
@onready var fx_root: Node3D = $FX
@onready var camera_rig: Node3D = $CameraRig
@onready var player_node: VoxelEntity = $Player as VoxelEntity

var _boot_done := false


func _ready() -> void:
	Game.main = self
	Game.world_renderer = world_renderer
	Game.entities_root = entities_root
	Game.fx_root = fx_root
	Game.camera_rig = camera_rig
	Game.player = player_node
	if player_node != null:
		Events.player_spawned.emit(player_node)
	# Registries fill in over the first couple of frames; start the run after.
	call_deferred(&"_boot")


func _boot() -> void:
	if _boot_done:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_boot_done = true
	if SaveManager.has_method(&"has_save") and SaveManager.has_save(0) and _autoload_continue():
		SaveManager.load_game(0)
	else:
		Game.start_new_game()
	Events.toast("Press Q / E to flip the world, PgUp / PgDn to shift layer.", "hint")


func _autoload_continue() -> bool:
	return false  ## the main menu drives this once it exists


func _process(delta: float) -> void:
	# The perspective state machine ticks here rather than in the camera so a
	# missing or replaced camera rig can never wedge a flip half-finished.
	View.advance_flip(delta)
	View.advance_shift(delta)
	if Game.player != null and World.ready_flag:
		World.update_streaming(Game.player.global_position)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		UI.toggle("pause")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_toggle"):
		Game.debug_overlay = not Game.debug_overlay
		Events.toast("Debug overlay %s" % ("on" if Game.debug_overlay else "off"), "info")
	elif event.is_action_pressed(&"quick_save"):
		Events.save_requested.emit(0)
	elif event.is_action_pressed(&"flip_left"):
		if not UI.captures_input():
			View.request_flip(-1)
	elif event.is_action_pressed(&"flip_right"):
		if not UI.captures_input():
			View.request_flip(1)
	elif event.is_action_pressed(&"depth_in"):
		if _depth_input_allowed():
			View.request_shift(1)
	elif event.is_action_pressed(&"depth_out"):
		if _depth_input_allowed():
			View.request_shift(-1)

## W / S both traverse the depth axis and drive `move_up` / `move_down`, which
## is what climbs a ladder or swims. Ladders and water win: pressing W on a
## ladder should climb it, not shove the player into the next layer.
func _depth_input_allowed() -> bool:
	if UI.captures_input():
		return false
	var p: Node = Game.player
	if p != null:
		for probe: StringName in [&"is_climbing", &"is_swimming"]:
			if p.has_method(probe) and bool(p.call(probe)):
				return false
	return true
