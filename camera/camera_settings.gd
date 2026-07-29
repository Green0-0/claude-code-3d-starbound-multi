## Runtime feature switches for everything under `camera/`.
##
## Pure static class — never instantiated, never autoloaded. Any module may
## read or write these; the camera nodes poll them every frame, so a change
## takes effect immediately and nothing needs to be re-created.
##
## Example (this is how the HUD agent turns the compass rose on):
## [codeblock]
## CamSettings.plane_indicator_enabled = true    # or CamSettings.set_flag(&"plane_indicator", true)
## [/codeblock]
class_name CamSettings
extends RefCounted

## Full-screen radial wipe / chromatic shear during a flip.
static var flip_transition_enabled := true
## The (slightly more expensive) directional motion-blur streaks inside it.
static var flip_streaks_enabled := true
## Strength multiplier for the flip post effect, 0..2.
static var flip_transition_strength := 1.0

## Cheap far-field depth of field that softens the layers behind the play plane.
static var depth_of_field_enabled := true

## The four-plane compass rose drawn by `CamPlaneIndicator`.
## OFF by default: `ui/hud/` owns 2D HUD widgets and will normally draw its own.
## The HUD agent enables this only if it decides not to.
static var plane_indicator_enabled := false

## Global scale on every screen shake, 0 disables. Accessibility setting.
static var screen_shake_scale := 1.0
## Hit-stop / time-freeze on big impacts.
static var hit_stop_enabled := true
## The very small breathing sway applied while the player stands still.
static var idle_sway_enabled := true

## Master accessibility switch. When true the camera drops shake, sway, the
## flip post effect and the dolly bulge, and keeps only the plain rotation.
static var reduce_motion := false

## Bumped by `set_flag`. Nodes that cache derived state can watch this instead
## of recomputing every frame.
static var revision := 0


## Generic setter so options menus can drive these from a table.
## Known keys: `flip_transition`, `flip_streaks`, `flip_strength`,
## `depth_of_field`, `plane_indicator`, `screen_shake`, `hit_stop`,
## `idle_sway`, `reduce_motion`.
static func set_flag(key: StringName, value: Variant) -> void:
	match key:
		&"flip_transition": flip_transition_enabled = bool(value)
		&"flip_streaks": flip_streaks_enabled = bool(value)
		&"flip_strength": flip_transition_strength = clampf(float(value), 0.0, 2.0)
		&"depth_of_field": depth_of_field_enabled = bool(value)
		&"plane_indicator": plane_indicator_enabled = bool(value)
		&"screen_shake": screen_shake_scale = clampf(float(value), 0.0, 2.0)
		&"hit_stop": hit_stop_enabled = bool(value)
		&"idle_sway": idle_sway_enabled = bool(value)
		&"reduce_motion": reduce_motion = bool(value)
		_:
			push_warning("[CamSettings] unknown flag %s" % key)
			return
	revision += 1


## True when shake/sway/post effects should be suppressed entirely.
static func motion_reduced() -> bool:
	return reduce_motion


## Effective shake multiplier, already accounting for `reduce_motion`.
static func shake_scale() -> float:
	return 0.0 if reduce_motion else maxf(0.0, screen_shake_scale)


static func to_dict() -> Dictionary:
	return {
		"flip_transition": flip_transition_enabled,
		"flip_streaks": flip_streaks_enabled,
		"flip_strength": flip_transition_strength,
		"depth_of_field": depth_of_field_enabled,
		"plane_indicator": plane_indicator_enabled,
		"screen_shake": screen_shake_scale,
		"hit_stop": hit_stop_enabled,
		"idle_sway": idle_sway_enabled,
		"reduce_motion": reduce_motion,
	}


static func from_dict(d: Dictionary) -> void:
	for k: String in d:
		set_flag(StringName(k), d[k])
