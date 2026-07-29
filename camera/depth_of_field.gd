## Cheap far-field depth of field that softens the layers behind the play plane.
##
## The 2.5D read of this game depends on the player instantly knowing which
## layer is "here" and which are "back there". The slab shader already tints
## and dissolves by layer; a *very* slight far blur adds the one depth cue a
## flat orthographic view otherwise lacks, at almost no cost (one blur pass,
## no near-field blur, no bokeh shape work).
##
## Distances are measured from the camera, which sits `orbit_radius` behind the
## focus, so the blur ramp is recomputed whenever the rig dollies.
class_name CamDepthOfField
extends Node

## Local master switch. `CamSettings.depth_of_field_enabled` is the global one;
## both must be true.
@export var enabled := true
## Blur strength. Keep this small — this is a depth cue, not an effect.
@export var blur_amount := 0.06
## Blocks behind the play plane at which the blur starts.
@export var start_behind := 3.0
## Blocks over which the blur ramps to full.
@export var transition := 16.0
## Recompute interval in seconds. Nothing here needs to be per-frame.
@export var refresh_interval := 0.2

var _attrs: CameraAttributesPractical = null
var _camera: Camera3D = null
var _accum := 0.0
var _last_distance := -1.0
var _last_state := false


func _ready() -> void:
	process_priority = 12
	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = false
	_attrs.dof_blur_near_enabled = false
	_attrs.dof_blur_amount = blur_amount
	_attrs.dof_blur_far_transition = transition
	_find_camera()
	_apply(true)


func _find_camera() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var c: Variant = parent.get(&"camera")
	if c is Camera3D:
		_camera = c as Camera3D
	else:
		_camera = parent.get_node_or_null(^"Camera3D") as Camera3D
	if _camera != null:
		_camera.attributes = _attrs


func _process(delta: float) -> void:
	_accum += delta
	if _accum < refresh_interval:
		return
	_accum = 0.0
	_apply(false)


func _apply(force: bool) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_find_camera()
		if _camera == null:
			return
	var on := enabled and CamSettings.depth_of_field_enabled
	# The camera hangs at +Z * radius in the rig's local space; the play plane
	# is at the rig origin, so its distance is exactly that local Z.
	var distance := _camera.position.z + start_behind
	if not force and on == _last_state and absf(distance - _last_distance) < 0.25:
		return
	_last_state = on
	_last_distance = distance
	_attrs.dof_blur_far_enabled = on
	if not on:
		return
	_attrs.dof_blur_far_distance = maxf(0.1, distance)
	_attrs.dof_blur_far_transition = maxf(0.1, transition)
	_attrs.dof_blur_amount = clampf(blur_amount, 0.0, 1.0)


## Turn the effect on or off at runtime (settings menus, cutscenes, photo mode).
func set_enabled(v: bool) -> void:
	enabled = v
	_apply(true)


## Live camera attributes resource, in case another module wants to layer
## exposure settings on top. Do not replace `Camera3D.attributes` — extend this.
func attributes() -> CameraAttributesPractical:
	return _attrs
