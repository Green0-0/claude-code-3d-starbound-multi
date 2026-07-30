## Turns raw Godot actions into the small, buffered, gate-able intent struct
## that [PlayerActor] consumes.
##
## Nothing here knows about the world: `move_axis` is already **plane space**
## (-1 = screen left, +1 = screen right) so the actor never has to think about
## which world axis "right" currently means.
##
## Gating: all intent collapses to zero while [method UI.captures_input] is
## true, while `Game.paused` is set, or while the actor has frozen input (flip
## animation, cutscenes). Buffers are flushed on the transition so a keypress
## swallowed by a menu never leaks into gameplay a second later.
##
## `flip_left` / `flip_right` / `depth_in` / `depth_out` / `pause` are owned by
## `core/main.gd`; they are deliberately *not* handled here so a keypress can
## never fire twice. The panel toggles (inventory/crafting/quests/starmap) have
## no other owner, so they are routed to `UI.toggle()` from this node.
class_name PlayerInput
extends Node

## How long a jump press survives before it is discarded (jump buffering).
const JUMP_BUFFER := 0.14
## Buffer for the "verb" actions so a click during a flip still registers.
const ACTION_BUFFER := 0.18
## Two taps of the same direction inside this window start a sprint.
const DOUBLE_TAP_WINDOW := 0.26

var player: VoxelEntity = null
## Set false to hand control to a scripted sequence.
var enabled := true
## True while something else is eating input this frame.
var captured := false

# --- continuous intent -------------------------------------------------------
var move_axis := 0.0        ## plane-space lateral, -1..1
var vert_axis := 0.0        ## -1 down .. +1 up (ladders, swimming)
var jump_held := false
var sprint_held := false
var crouch_held := false
var primary_held := false
var secondary_held := false

# --- edges -------------------------------------------------------------------
var jump_pressed := false
var jump_released := false
var primary_pressed := false
var secondary_pressed := false
var interact_pressed := false
var tech_pressed := false

var mouse_position := Vector2.ZERO

var _jump_buffer := 0.0
var _interact_buffer := 0.0
var _tech_buffer := 0.0
var _tap_dir := 0
var _tap_timer := 0.0
var _sprint_latch := false
var _was_captured := false


func setup(p: VoxelEntity) -> void:
	player = p


## Called once per physics frame by [PlayerActor], before any movement logic.
func poll(delta: float) -> void:
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_interact_buffer = maxf(0.0, _interact_buffer - delta)
	_tech_buffer = maxf(0.0, _tech_buffer - delta)
	_tap_timer = maxf(0.0, _tap_timer - delta)

	captured = not enabled or Game.paused or UI.captures_input() \
		or (player != null and bool(player.get("input_frozen")))

	if captured:
		if not _was_captured:
			flush()
		_was_captured = true
		_zero()
		return
	_was_captured = false

	mouse_position = get_viewport().get_mouse_position()

	var raw := Input.get_axis(&"move_left", &"move_right")
	move_axis = 0.0 if absf(raw) < 0.2 else signf(raw) * minf(1.0, absf(raw))
	vert_axis = Input.get_axis(&"move_down", &"move_up")

	jump_held = Input.is_action_pressed(&"jump")
	jump_pressed = Input.is_action_just_pressed(&"jump")
	jump_released = Input.is_action_just_released(&"jump")
	if jump_pressed:
		_jump_buffer = JUMP_BUFFER

	# Crouch has its own binding (PageDown). It used to piggyback on
	# `move_down`, but W/S now traverse the depth axis.
	crouch_held = Input.is_action_pressed(&"crouch")

	primary_held = Input.is_action_pressed(&"primary")
	primary_pressed = Input.is_action_just_pressed(&"primary")
	secondary_held = Input.is_action_pressed(&"secondary")
	secondary_pressed = Input.is_action_just_pressed(&"secondary")

	interact_pressed = Input.is_action_just_pressed(&"interact")
	if interact_pressed:
		_interact_buffer = ACTION_BUFFER
	tech_pressed = Input.is_action_just_pressed(&"tech_action")
	if tech_pressed:
		_tech_buffer = ACTION_BUFFER

	_update_sprint()


## Sprint has no dedicated action in `project.godot`, so it is derived: hold
## either Shift key, or double-tap a movement direction (classic platformer).
func _update_sprint() -> void:
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var dir := 0
	if Input.is_action_just_pressed(&"move_right"):
		dir = 1
	elif Input.is_action_just_pressed(&"move_left"):
		dir = -1
	if dir != 0:
		if dir == _tap_dir and _tap_timer > 0.0:
			_sprint_latch = true
		_tap_dir = dir
		_tap_timer = DOUBLE_TAP_WINDOW
	if absf(move_axis) < 0.2 or (_sprint_latch and signf(move_axis) != float(_tap_dir)):
		_sprint_latch = false
	sprint_held = shift or _sprint_latch


func _zero() -> void:
	move_axis = 0.0
	vert_axis = 0.0
	jump_held = false
	sprint_held = false
	crouch_held = false
	primary_held = false
	secondary_held = false
	jump_pressed = false
	jump_released = false
	primary_pressed = false
	secondary_pressed = false
	interact_pressed = false
	tech_pressed = false


## Drop every buffered action. Called on flips, menu opens and teleports.
func flush() -> void:
	_jump_buffer = 0.0
	_interact_buffer = 0.0
	_tech_buffer = 0.0
	_sprint_latch = false
	_tap_timer = 0.0
	_zero()


# ------------------------------------------------------------------- buffers
func has_buffered_jump() -> bool:
	return _jump_buffer > 0.0


func consume_jump() -> bool:
	if _jump_buffer <= 0.0:
		return false
	_jump_buffer = 0.0
	return true


func consume_interact() -> bool:
	if _interact_buffer <= 0.0:
		return false
	_interact_buffer = 0.0
	return true


func consume_tech() -> bool:
	if _tech_buffer <= 0.0:
		return false
	_tech_buffer = 0.0
	return true


# ------------------------------------------------------------- panel toggles
func _unhandled_input(event: InputEvent) -> void:
	if Game.paused:
		return
	var panel := ""
	if event.is_action_pressed(&"inventory"):
		panel = "inventory"
	elif event.is_action_pressed(&"crafting"):
		panel = "crafting"
	elif event.is_action_pressed(&"quests"):
		panel = "quests"
	elif event.is_action_pressed(&"starmap"):
		panel = "starmap"
	if panel == "":
		return
	UI.toggle(panel)
	flush()
	get_viewport().set_input_as_handled()
