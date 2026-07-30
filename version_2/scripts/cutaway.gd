class_name Cutaway
extends RefCounted

## ---------------------------------------------------------------------------
## Camera Obstruction System
##
## One predicate, evaluated identically on the CPU and the GPU. Three modes
## share a common core, and every one of them is subject to the same two rules
## that come before anything else:
##
##   1. **The keep shell.** Blocks immediately around the player are *never*
##      cut, unless they lie toward the camera. The floor you are standing on,
##      the wall beside you and the tree you walked up to stay put — otherwise
##      the thing you are trying to mine disappears at exactly the moment you
##      get close enough to mine it.
##
##   2. **Everything else is cut by mode**:
##
##      * `CYLINDER` — a drill from the lens to the player. Punches straight
##        through the roof when you fall down a hole, without gouging out the
##        rest of the hillside.
##      * `FILL` — cast to the first air along the sightline, flood-fill the
##        pocket the player is standing in, and cut everything between that
##        whole pocket and the lens. A tunnel or a room reads in its entirety
##        rather than as a cone around you. The fill is *added* range: the cut
##        still runs all the way to the camera as it always did.
##      * `PLANAR` — when the player is genuinely occluded, cut a slab of voxel
##        coordinates in front of them: the classic side-on cross-section.
##
## Cut blocks are either discarded outright (`opacity == 0`) or rendered as
## ghosts that fade to nothing with distance from the player, the way distant
## props fade in Don't Starve. `selectable` decides whether they can still be
## mined.
## ---------------------------------------------------------------------------

enum Mode { CYLINDER, FILL, PLANAR }

const MODE_NAMES := ["Cylinder", "Fill", "Planar"]

# ------------------------------------------------------------------- geometry
var camera_position := Vector3.ZERO
var target_position := Vector3.ZERO
var radius := 1.5
var target_padding := 1.0
var enabled := true
var mode: int = Mode.CYLINDER

## The shell of blocks around the player that survives whatever the mode says.
var keep_radius := 2.75
## How far toward the camera the shell stops protecting, as a cosine. Blocks
## below and beside the player are kept; blocks on the lens side are not.
var keep_bias := 0.35

# ------------------------------------------------------------------- planar
var planar_depth := 34.0
var planar_half_width := 5.5
var planar_below := 1.5
var planar_above := 4.0
## Set by the world each update: is the player actually behind something?
var occluded := false

# --------------------------------------------------------------------- fill
## Cut cells produced by the flood fill, as a dense byte mask over a box.
var fill_origin := Vector3i.ZERO
var fill_size := Vector3i.ZERO
## Stored in the same packed layout the shader samples — a grid of z-slices —
## so the mask can be handed to the GPU with no repacking pass.
var fill_mask := PackedByteArray()
var fill_cols := 1                ## z-slices per row
var fill_width := 0               ## fill_cols * fill_size.x

# ------------------------------------------------------------- presentation
## 0 discards cut blocks outright. Above 0 they are dithered ghosts at this
## alpha next to the player, fading to nothing over `fade_distance`.
var opacity := 0.0
var fade_distance := 16.0
## Can cut blocks still be aimed at and mined?
var selectable := true


func copy_from(o: Cutaway) -> void:
	camera_position = o.camera_position
	target_position = o.target_position
	radius = o.radius
	target_padding = o.target_padding
	enabled = o.enabled
	mode = o.mode
	keep_radius = o.keep_radius
	keep_bias = o.keep_bias
	opacity = o.opacity
	fade_distance = o.fade_distance
	selectable = o.selectable


# =============================================================================
# the predicate
# =============================================================================

## Must stay bit-for-bit in step with `is_cut()` in voxel.gdshader,
## voxel_glass.gdshader and voxel_cross.gdshader.
func is_cut(bx: int, by: int, bz: int) -> bool:
	if not enabled:
		return false
	var bc := Vector3(bx + 0.5, by + 0.5, bz + 0.5)
	if is_protected(bc):
		return false
	if in_cylinder(bc):
		return true
	match mode:
		Mode.FILL:
			return in_fill(bx, by, bz)
		Mode.PLANAR:
			return occluded and in_slab(bc)
	return false


## The keep shell. A block within `keep_radius` of the player survives unless it
## sits toward the lens, which is the only direction that can actually be in the
## way. This is what keeps the ground under your feet and the block you are
## about to mine from evaporating as you approach them.
func is_protected(bc: Vector3) -> bool:
	var d := bc - target_position
	var dist_sq := d.length_squared()
	if dist_sq > keep_radius * keep_radius:
		return false
	if dist_sq < 0.0001:
		return true
	var toward_cam := camera_position - target_position
	var len_sq := toward_cam.length_squared()
	if len_sq < 0.0001:
		return true
	# normalised dot: how much of this block lies in the lens direction
	return d.dot(toward_cam) / sqrt(dist_sq * len_sq) < keep_bias


## The drill from the lens to the player: a cylinder around the segment with a
## spherical cap at the player end so you stay visible pressed against a wall.
func in_cylinder(bc: Vector3) -> bool:
	var seg := target_position - camera_position
	var rel := bc - camera_position
	var len_sq := seg.length_squared()
	if len_sq < 0.001:
		var rr := radius + target_padding
		return rel.length_squared() <= rr * rr
	# t = 0 at the lens, t = 1 at the player
	var t := rel.dot(seg) / len_sq
	var closest: Vector3
	var er := radius
	if t <= 0.0:
		closest = camera_position          # behind the lens
	elif t >= 1.0:
		closest = target_position          # past the player: widen the cap
		er += target_padding
	else:
		closest = camera_position + seg * t
	return bc.distance_squared_to(closest) <= er * er


## The flood-filled pocket and its shadow toward the lens. The mask is built by
## `VoxelWorld._rebuild_fill()`; this only reads it.
func in_fill(bx: int, by: int, bz: int) -> bool:
	if fill_mask.is_empty():
		return false
	var lx := bx - fill_origin.x
	var ly := by - fill_origin.y
	var lz := bz - fill_origin.z
	if lx < 0 or ly < 0 or lz < 0:
		return false
	if lx >= fill_size.x or ly >= fill_size.y or lz >= fill_size.z:
		return false
	return fill_mask[packed_index(lx, ly, lz)] != 0


## Index into the z-slice grid. Mirrored exactly in cutaway.gdshaderinc.
func packed_index(lx: int, ly: int, lz: int) -> int:
	var col := lz % fill_cols
	var row := lz / fill_cols
	return (row * fill_size.y + ly) * fill_width + (col * fill_size.x + lx)


## A slab of voxel coordinates directly in front of the player, measured along
## the camera's own axis. Only live while the player is occluded, so an open
## landscape is never sliced for no reason.
func in_slab(bc: Vector3) -> bool:
	var axis := camera_position - target_position
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		return false
	axis = axis.normalized()
	var d := bc - target_position
	var toward := d.dot(axis)             # positive = toward the lens
	if toward < 0.5 or toward > planar_depth:
		return false
	var lateral := Vector3(-axis.z, 0.0, axis.x)
	if absf(d.dot(lateral)) > planar_half_width:
		return false
	return d.y >= -planar_below and d.y <= planar_above


# =============================================================================
# presentation
# =============================================================================

## Ghost alpha for a cut block, 0 when it should be discarded outright. The
## falloff is from the player, not the camera, so the world opens up around you
## and closes again in the distance.
func ghost_alpha(bc: Vector3) -> float:
	if opacity <= 0.0:
		return 0.0
	var d := bc.distance_to(target_position)
	return clampf(opacity * (1.0 - d / maxf(fade_distance, 0.001)), 0.0, 1.0)


## Can the player aim through the cut in the primary raycast pass? Only when the
## ghosts are actually visible — otherwise you would be mining an invisible
## hillside instead of the ground you can see behind it.
func selectable_in_primary() -> bool:
	return selectable and opacity > 0.0


func mode_name() -> String:
	return MODE_NAMES[clampi(mode, 0, MODE_NAMES.size() - 1)]


# =============================================================================
# bookkeeping
# =============================================================================

## The integer bounding box the cap builder has to scan. Cylinder and planar are
## analytic; fill hands back the box its mask already covers.
func get_int_bounds() -> AABB:
	var pad := radius + target_padding + keep_radius
	var min_pos := camera_position.min(target_position) - Vector3(pad, pad, pad)
	var max_pos := camera_position.max(target_position) + Vector3(pad, pad, pad)
	if mode == Mode.FILL and fill_size.x > 0:
		min_pos = min_pos.min(Vector3(fill_origin))
		max_pos = max_pos.max(Vector3(fill_origin + fill_size))
	if mode == Mode.PLANAR and occluded:
		var axis := camera_position - target_position
		axis.y = 0.0
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			var far := target_position + axis * planar_depth
			var w := Vector3(planar_half_width, 0, planar_half_width)
			min_pos = min_pos.min(far - w - Vector3(0, planar_below, 0))
			max_pos = max_pos.max(far + w + Vector3(0, planar_above, 0))
	var min_i := Vector3i(floori(min_pos.x), floori(min_pos.y), floori(min_pos.z))
	var max_i := Vector3i(ceili(max_pos.x), ceili(max_pos.y), ceili(max_pos.z))
	return AABB(min_i, max_i - min_i)


func clear_fill() -> void:
	fill_mask = PackedByteArray()
	fill_size = Vector3i.ZERO
	fill_origin = Vector3i.ZERO
	fill_cols = 1
	fill_width = 0


func push_to_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"cut_cam_pos", camera_position)
	RenderingServer.global_shader_parameter_set(&"cut_target_pos", target_position)
	RenderingServer.global_shader_parameter_set(&"cut_radius", float(radius))
	RenderingServer.global_shader_parameter_set(&"cut_target_padding", float(target_padding))
	RenderingServer.global_shader_parameter_set(&"cut_enabled", 1.0 if enabled else 0.0)
	RenderingServer.global_shader_parameter_set(&"cut_mode", float(mode))
	RenderingServer.global_shader_parameter_set(&"cut_keep_radius", float(keep_radius))
	RenderingServer.global_shader_parameter_set(&"cut_keep_bias", float(keep_bias))
	RenderingServer.global_shader_parameter_set(&"cut_opacity", float(opacity))
	RenderingServer.global_shader_parameter_set(&"cut_fade", float(fade_distance))
	RenderingServer.global_shader_parameter_set(&"cut_planar_depth", float(planar_depth))
	RenderingServer.global_shader_parameter_set(&"cut_planar_width", float(planar_half_width))
	RenderingServer.global_shader_parameter_set(&"cut_planar_below", float(planar_below))
	RenderingServer.global_shader_parameter_set(&"cut_planar_above", float(planar_above))
	RenderingServer.global_shader_parameter_set(&"cut_occluded", 1.0 if occluded else 0.0)


func save_state() -> Dictionary:
	return {
		"enabled": enabled, "mode": mode, "opacity": opacity,
		"fade": fade_distance, "selectable": selectable,
		"keep_radius": keep_radius, "radius": radius,
	}


func load_state(d: Dictionary) -> void:
	enabled = bool(d.get("enabled", true))
	mode = int(d.get("mode", Mode.CYLINDER))
	opacity = float(d.get("opacity", 0.0))
	fade_distance = float(d.get("fade", 16.0))
	selectable = bool(d.get("selectable", true))
	keep_radius = float(d.get("keep_radius", 2.75))
	radius = float(d.get("radius", 1.5))
