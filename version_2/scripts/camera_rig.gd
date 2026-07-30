class_name CameraRig
extends Node3D

## Don't-Starve-style rotatable 2.5D camera.
##
## The yaw is quantised to the four cardinal directions, which is what lets the
## cutaway resolve to a clean, axis-aligned Starbound cross-section. Pitch is
## fixed and shallow so you read the world side-on but still see the tops of
## blocks — the "tilted side view" the reference frame is shot at.

signal facing_changed(facing: int)

## camera horizontal forward, indexed by facing
const FACINGS := [
	Vector3i(0, 0, -1),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(1, 0, 0),
]
## camera horizontal right = cross(forward, up)
const LATERALS := [
	Vector3i(1, 0, 0),
	Vector3i(0, 0, -1),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
]
const FACING_NAMES := ["North", "West", "South", "East"]

@export var pitch_degrees := 34.0
@export var distance := 27.0
@export var min_distance := 15.0
@export var max_distance := 46.0
@export var height_offset := -13.35
@export var follow_smoothing := 9.0
@export var turn_time := 0.34

var facing := 0
var target: Node3D

var _yaw := 0.0
var _yaw_from := 0.0
var _yaw_to := 0.0
var _turn_t := 1.0
var _turn_from := 0
var _pending_facing := 0
var _target_distance := 27.0

@onready var pitch_node: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Camera3D


func _ready() -> void:
	_target_distance = distance
	# rotation.y = θ gives forward -basis.z = (-sin θ, 0, -cos θ), which matches
	# FACINGS[] at θ = facing * 90°
	_yaw = float(facing) * PI * 0.5
	_yaw_to = _yaw
	_yaw_from = _yaw
	_pending_facing = facing
	pitch_node.rotation.x = -deg_to_rad(pitch_degrees)
	camera.position = Vector3(0, 0, distance)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"rotate_ccw"):
		rotate_view(1)
	elif event.is_action_pressed(&"rotate_cw"):
		rotate_view(-1)
	elif event is InputEventMouseButton and event.pressed and not event.ctrl_pressed:
		# ctrl+wheel belongs to the hotbar
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - 2.0, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + 2.0, min_distance, max_distance)


func rotate_view(dir: int) -> void:
	if _turn_t < 1.0:
		return
	_turn_from = facing
	_pending_facing = wrapi(facing + dir, 0, 4)
	_yaw_from = _yaw
	# always take the short way round: exactly a quarter turn, never wrapped
	_yaw_to = _yaw + float(dir) * PI * 0.5
	_turn_t = 0.0


func _process(delta: float) -> void:
	# --- follow
	if target != null:
		var want := target.global_position + Vector3(0, height_offset, 0)
		var dist := global_position.distance_to(want)
		
		if dist > 24.0:
			global_position = want
		else:
			# Get the camera rig's local horizontal axes. 
			# Since pitch is applied on a child node, this node's basis is purely yaw (flat on the ground).
			var right_dir := global_transform.basis.x
			var fwd_dir := global_transform.basis.z # Points backwards, away from the target
			
			# Project current and target positions onto local axes to get screen-space X and Y (depth)
			var cur_side := global_position.dot(right_dir)
			var cur_depth := global_position.dot(fwd_dir)
			var tgt_side := want.dot(right_dir)
			var tgt_depth := want.dot(fwd_dir)
			
			var side_dist := absf(tgt_side - cur_side)
			var depth_dist := absf(tgt_depth - cur_depth)
			
			# --- 1. SIDEWAYS (Local X - Left/Right on screen): Very Fast ---
			# Using your original curve but with higher multipliers
			var side_factor := clampf((side_dist / 9.0) * side_dist / 24.0, 0.0, 1.0)
			var side_base := follow_smoothing * 1.5  # Faster base speed
			var side_max := follow_smoothing * 5.0   # Much faster max speed
			var side_smoothing := lerpf(side_base, side_max, side_factor * 5.0)
			var side_alpha := 1.0 - exp(-side_smoothing * delta / 30.0)
			
			# --- 2. DEPTH (Local Z - Holding S / moving toward camera): Almost none until high distances ---
			# Normalize depth distance, then apply an exponent to delay the curve heavily
			var depth_factor := clampf(depth_dist / 24.0, 0.0, 1.0)
			# Cubic curve: stays near 0 until distance gets significantly high
			depth_factor = pow(depth_factor, 3.0) 
			
			var depth_base := follow_smoothing * 0.0 # Effectively zero tracking when close
			var depth_max := follow_smoothing * 1.5  # Ramps up to moderate speed when far
			var depth_smoothing := lerpf(depth_base, depth_max, depth_factor)
			var depth_alpha := 1.0 - exp(-depth_smoothing * delta / 30.0)
			
			# --- 3. VERTICAL (Global Y - Up/Down height): Preserving your original logic ---
			# Uses overall distance so vertical height tracking behaves exactly as it did before
			var y_factor := clampf((dist / 9.0) * dist / 24.0, 0.0, 1.0)
			var y_base := follow_smoothing * 0.5
			var y_max := follow_smoothing * 3.0
			var y_smoothing := lerpf(y_base, y_max, y_factor * 5.0)
			var y_alpha := 1.0 - exp(-y_smoothing * delta / 30.0)
			
			# Apply independent lerping
			var new_side := lerpf(cur_side, tgt_side, side_alpha)
			var new_depth := lerpf(cur_depth, tgt_depth, depth_alpha)
			var new_y := lerpf(global_position.y, want.y, y_alpha)
			
			# Reconstruct the new global position
			global_position = right_dir * new_side + fwd_dir * new_depth + Vector3(0, new_y, 0)

	# --- turn
	if _turn_t < 1.0:
		_turn_t = minf(_turn_t + delta / maxf(turn_time, 0.001), 1.0)
		var e := _ease_in_out(_turn_t)
		_yaw = lerpf(_yaw_from, _yaw_to, e)
		if _turn_t >= 0.5 and facing != _pending_facing:
			facing = _pending_facing
			facing_changed.emit(facing)
		if _turn_t >= 1.0:
			_yaw = _yaw_to
	rotation.y = _yaw

	# --- zoom
	distance = lerpf(distance, _target_distance, 1.0 - exp(-9.0 * delta))
	camera.position = Vector3(0, 0, distance)
	pitch_node.rotation.x = -deg_to_rad(pitch_degrees)

static func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func axis() -> Vector3i:
	return FACINGS[facing]


func lateral() -> Vector3i:
	return LATERALS[facing]


func slope() -> float:
	return tan(deg_to_rad(pitch_degrees))


func facing_name() -> String:
	return FACING_NAMES[facing]
