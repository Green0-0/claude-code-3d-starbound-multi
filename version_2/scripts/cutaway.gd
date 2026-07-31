class_name Cutaway
extends RefCounted

## ---------------------------------------------------------------------------
## Camera Obstruction System
##
## One predicate, evaluated identically on the CPU and the GPU.
##
## **Everything here is quantised to voxel coordinates.** The cut is anchored to
## the block the player stands in and to one of the camera's four facings, never
## to their continuous positions. That is not an approximation — the thing being
## cut is a grid of blocks, so a cut that slides smoothly between them has
## nothing to express. What it buys is that the cut set only changes when the
## player crosses a block boundary or the camera turns, which is what lets the
## cross-section geometry be cached instead of rebuilt every frame.
##
## Two rules come before the mode:
##
##   1. **The keep shell.** Blocks immediately around the player survive unless
##      they lie toward the lens, so the floor under your feet and the tree you
##      just walked up to do not evaporate as you approach them.
##   2. **The mode**:
##      * `CYLINDER` — a drill from the lens to the player.
##      * `FILL` — the air pocket you are standing in, with everything between
##        that pocket and the lens removed. No drill, no cone, no rays.
##      * `PLANAR` — a half-space: nothing past a coordinate plane just in front
##        of you is drawn at all, while you are genuinely covered.
##
## The keep shell and the cylinder belong to `CYLINDER` alone. The other two
## modes answer a question about the world — "what room am I in", "what is on
## the near side of this plane" — and a drill mixed into either of them only
## makes the answer wrong.
##
## Cut blocks are deleted, or drawn as ghosts that fade with distance.
## ---------------------------------------------------------------------------

enum Mode { CYLINDER, FILL, PLANAR }

const MODE_NAMES := ["Cylinder", "Fill", "Planar"]

## Camera forward per facing, matching CameraRig.FACINGS exactly.
const FACING_FORWARD := [
	Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0),
]
const FACING_LATERAL := [
	Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
]

# ------------------------------------------------------------------ quantised
## The block the player is standing in. Everything anchors to this.
var anchor := Vector3i.ZERO
## The block the lens sits in.
var cam_cell := Vector3i.ZERO
## 0..3, the camera's settled facing.
var facing := 0
## Is the player actually behind something? Only planar cares.
var occluded := false

## Derived from the quantised state, and what the shader is given.
var camera_position := Vector3.ZERO
var target_position := Vector3.ZERO

# ------------------------------------------------------------------- geometry
var radius := 1.5
var target_padding := 1.0
var enabled := true
var mode: int = Mode.CYLINDER

var keep_radius := 2.75
var keep_bias := 0.35

# --------------------------------------------------------------------- planar
## How far in front of the player's own cell the plane sits. One block: the cut
## begins at the first cell between you and the lens.
var planar_offset := 1
## How wide a window of the plane the cross-section is built for, either side of
## the player. Only the cap cares; the predicate itself is unbounded.
var planar_cap_reach := 56

# ----------------------------------------------------------------------- fill
##
## The pocket is described by a *depth mask* rather than by a marked volume:
## one entry per column of the plane perpendicular to the view axis, holding how
## far toward the lens that column's air pocket reaches. A block is hidden when
## it stands in front of that. One comparison, no marching, and the mask is two
## dimensional instead of three.
var fill_origin := Vector3i.ZERO      ## world corner of the mask window
var fill_size := Vector2i.ZERO        ## across, up
## depth + 1 for each column, 0 where the pocket does not reach.
var fill_depth := PackedByteArray()
## Which world axis the view runs along (0 = x, 2 = z) and which way the lens is.
var fill_axis := 2
var fill_toward := 1
## Where the mask's depth values are measured from.
var fill_base := 0
## How far the sight line climbs per block of depth toward the lens.
##
## Without this the mask is wrong in the one way that matters. The lens looks
## *down* at thirty-odd degrees, so a block that hides the room is not in the
## room's own row — it is fifteen rows above it and twenty blocks nearer. Shear
## the mask by the slope and the occluder and the thing it occludes land in the
## same column again, which is the whole premise of a depth mask.
var fill_slope := 0.0
## True when no enclosed pocket was found; the mode then does nothing at all.
var fill_empty := true
## Every hidden cell, so the cap builder can walk the set rather than a volume.
var fill_cells := PackedInt32Array()

# ------------------------------------------------------------- presentation
var opacity := 0.0
var fade_distance := 16.0
var selectable := true


func copy_from(o: Cutaway) -> void:
	anchor = o.anchor
	cam_cell = o.cam_cell
	facing = o.facing
	radius = o.radius
	target_padding = o.target_padding
	enabled = o.enabled
	mode = o.mode
	keep_radius = o.keep_radius
	keep_bias = o.keep_bias
	opacity = o.opacity
	fade_distance = o.fade_distance
	selectable = o.selectable
	refresh_points()


## Snap to a camera and a player position. Returns true when the quantised state
## actually changed, which is the only time anything downstream has work to do.
func place(cam: Vector3, target: Vector3) -> bool:
	var new_anchor := Vector3i(floori(target.x), floori(target.y), floori(target.z))
	var new_cam := Vector3i(floori(cam.x), floori(cam.y), floori(cam.z))
	var fwd := target - cam
	fwd.y = 0.0
	var new_facing := facing
	if fwd.length_squared() > 0.01:
		if absf(fwd.z) >= absf(fwd.x):
			new_facing = 0 if fwd.z < 0.0 else 2
		else:
			new_facing = 1 if fwd.x < 0.0 else 3
	if new_anchor == anchor and new_cam == cam_cell and new_facing == facing:
		return false
	anchor = new_anchor
	cam_cell = new_cam
	facing = new_facing
	refresh_points()
	return true


func refresh_points() -> void:
	# eye height inside the player's cell, so the drill lines up with the sprite
	target_position = Vector3(anchor) + Vector3(0.5, 0.9, 0.5)
	camera_position = Vector3(cam_cell) + Vector3(0.5, 0.5, 0.5)


func toward_camera() -> Vector3i:
	var f: Vector3i = FACING_FORWARD[facing]
	return -f


func lateral_axis() -> Vector3i:
	var l: Vector3i = FACING_LATERAL[facing]
	return l


# =============================================================================
# the predicate
# =============================================================================

## Must stay bit-for-bit in step with `cut_is_cut()` in cutaway.gdshaderinc.
func is_cut(bx: int, by: int, bz: int) -> bool:
	if not enabled:
		return false
	if mode == Mode.PLANAR:
		return occluded and past_plane(bx, by, bz)
	if mode == Mode.FILL:
		# No pocket means no cut. Falling back to the drill here is what made
		# this mode feel like the cylinder wearing a hat.
		return not fill_empty and in_front_of_pocket(bx, by, bz)
	var bc := Vector3(bx + 0.5, by + 0.5, bz + 0.5)
	if is_protected(bc):
		return false
	return in_cylinder(bc)


## The keep shell.
func is_protected(bc: Vector3) -> bool:
	var d := bc - target_position
	var dist_sq := d.length_squared()
	if dist_sq > keep_radius * keep_radius:
		return false
	if dist_sq < 0.0001:
		return true
	var toward := camera_position - target_position
	var len_sq := toward.length_squared()
	if len_sq < 0.0001:
		return true
	return d.dot(toward) / sqrt(dist_sq * len_sq) < keep_bias


## The drill from the lens to the player.
func in_cylinder(bc: Vector3) -> bool:
	var seg := target_position - camera_position
	var rel := bc - camera_position
	var len_sq := seg.length_squared()
	if len_sq < 0.001:
		var rr := radius + target_padding
		return rel.length_squared() <= rr * rr
	var t := rel.dot(seg) / len_sq
	var closest: Vector3
	var er := radius
	if t <= 0.0:
		closest = camera_position
	elif t >= 1.0:
		closest = target_position
		er += target_padding
	else:
		closest = camera_position + seg * t
	return bc.distance_squared_to(closest) <= er * er


## Is this block standing between the lens and the room the player is in?
##
## The mask holds, per column of the view plane, how far toward the lens that
## column's pocket reaches. Anything in the same column and further toward the
## lens than that is in the way. Two integer compares and one byte fetch.
func in_front_of_pocket(bx: int, by: int, bz: int) -> bool:
	if fill_depth.is_empty():
		return false
	var across := bz if fill_axis == 0 else bx
	var along := bx if fill_axis == 0 else bz
	var k := (along - fill_base) * fill_toward
	var u := across - fill_origin.x
	var v := fill_row(by, k) - fill_origin.y
	if u < 0 or v < 0 or u >= fill_size.x or v >= fill_size.y:
		return false
	var d: int = fill_depth[v * fill_size.x + u]
	if d == 0:
		return false
	return k > d - 1


## The sheared row a cell falls in: its height, less however far the sight line
## has climbed by that depth. Mirrored exactly in the shader.
func fill_row(by: int, k: int) -> int:
	return by - roundi(float(k) * fill_slope)


## Nothing past the plane, full stop.
##
## This is the whole of planar mode. It is a half-space bounded by one
## axis-aligned coordinate plane sitting `planar_offset` cells in front of the
## player's own cell, and it has no lateral, vertical or far bound whatsoever —
## which is both what "do not render anything past a coordinate plane" means and
## the reason the mode is now free. The cut set depends on one integer. Walking
## sideways or up and down does not change it, so nothing downstream rebuilds.
func past_plane(bx: int, by: int, bz: int) -> bool:
	var t := toward_camera()
	if t.x != 0:
		return (bx - anchor.x) * t.x >= planar_offset
	return (bz - anchor.z) * t.z >= planar_offset


## 0 when the view runs along x, 2 when it runs along z.
func plane_axis() -> int:
	return 0 if toward_camera().x != 0 else 2


## Which way the lens lies along that axis, as +1 or -1.
func plane_toward() -> int:
	var t := toward_camera()
	return t.x if t.x != 0 else t.z


## The world coordinate of the last slice that is still drawn. The cross-section
## stands on this plane.
func plane_coord() -> int:
	var axis := plane_axis()
	var a := anchor.x if axis == 0 else anchor.z
	return a + (planar_offset - 1) * plane_toward()


## The player's coordinate across the plane, which is all the cap window follows.
func plane_across() -> int:
	return anchor.z if plane_axis() == 0 else anchor.x


# =============================================================================
# presentation
# =============================================================================

func ghost_alpha(bc: Vector3) -> float:
	if opacity <= 0.0:
		return 0.0
	var d := bc.distance_to(target_position)
	return clampf(opacity * (1.0 - d / maxf(fade_distance, 0.001)), 0.0, 1.0)


func selectable_in_primary() -> bool:
	return selectable and opacity > 0.0


func mode_name() -> String:
	return MODE_NAMES[clampi(mode, 0, MODE_NAMES.size() - 1)]


# =============================================================================
# bookkeeping
# =============================================================================

## Everything the cut set depends on, in one comparable value. While this has
## not changed, neither has the cross-section, and the cached mesh stands.
##
## Each mode gets only the terms it actually depends on, and that is the whole
## performance story of this system:
##
##   PLANAR depends on one integer — which plane. Walking across the plane or up
##     and down it changes nothing, so the great majority of ordinary movement
##     costs nothing at all. Only the cap *window* follows the player, and it is
##     quantised to a chunk so it moves once every sixteen blocks.
##   FILL depends on which room you are in, not where you stand in it, so the
##     flood is quantised to four blocks. The lens cell drops out entirely: the
##     mask is built along the facing axis and the facing is already a term.
##   CYLINDER genuinely is a line from the lens to the player, so it needs both.
func signature(world_version: int) -> String:
	var head := "%d|%d|%d|%d|%d|%d" % [mode, facing, int(occluded), int(enabled),
		int(opacity > 0.0), world_version]
	match mode:
		Mode.PLANAR:
			return "%s|P%d|%d,%d" % [head, plane_coord(),
				plane_across() >> 4, anchor.y >> 4]
		Mode.FILL:
			return "%s|F%d,%d,%d|%.3f" % [head, anchor.x >> 2, anchor.y >> 2,
				anchor.z >> 2, view_slope()]
	return "%s|C%d,%d,%d|%d,%d,%d" % [head, anchor.x, anchor.y, anchor.z,
		cam_cell.x, cam_cell.y, cam_cell.z]


func get_int_bounds() -> AABB:
	var pad := radius + target_padding + keep_radius
	var min_pos := camera_position.min(target_position) - Vector3(pad, pad, pad)
	var max_pos := camera_position.max(target_position) + Vector3(pad, pad, pad)
	var min_i := Vector3i(floori(min_pos.x), floori(min_pos.y), floori(min_pos.z))
	var max_i := Vector3i(ceili(max_pos.x), ceili(max_pos.y), ceili(max_pos.z))
	return AABB(min_i, max_i - min_i)


func clear_fill() -> void:
	fill_depth = PackedByteArray()
	fill_cells = PackedInt32Array()
	fill_size = Vector2i.ZERO
	fill_origin = Vector3i.ZERO
	fill_axis = 2
	fill_toward = 1
	fill_base = 0
	fill_slope = 0.0
	fill_empty = true


## The sight line's rise per block of depth, quantised so it does not churn the
## signature. The pitch is fixed, so in practice this is a constant.
func view_slope() -> float:
	var d := camera_position - target_position
	var horiz := absf(d.x if plane_axis() == 0 else d.z)
	return snappedf(d.y / maxf(horiz, 1.0), 0.125)


func push_to_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"cut_cam_pos", camera_position)
	RenderingServer.global_shader_parameter_set(&"cut_target_pos", target_position)
	RenderingServer.global_shader_parameter_set(&"cut_anchor", Vector3(anchor))
	RenderingServer.global_shader_parameter_set(&"cut_toward", Vector3(toward_camera()))
	RenderingServer.global_shader_parameter_set(&"cut_lateral", Vector3(lateral_axis()))
	RenderingServer.global_shader_parameter_set(&"cut_radius", float(radius))
	RenderingServer.global_shader_parameter_set(&"cut_target_padding", float(target_padding))
	RenderingServer.global_shader_parameter_set(&"cut_enabled", 1.0 if enabled else 0.0)
	RenderingServer.global_shader_parameter_set(&"cut_mode", float(mode))
	RenderingServer.global_shader_parameter_set(&"cut_keep_radius", float(keep_radius))
	RenderingServer.global_shader_parameter_set(&"cut_keep_bias", float(keep_bias))
	RenderingServer.global_shader_parameter_set(&"cut_opacity", float(opacity))
	RenderingServer.global_shader_parameter_set(&"cut_fade", float(fade_distance))
	RenderingServer.global_shader_parameter_set(&"cut_planar_depth", float(planar_offset))
	RenderingServer.global_shader_parameter_set(&"cut_occluded", 1.0 if occluded else 0.0)
	RenderingServer.global_shader_parameter_set(&"cut_fill_empty", 1.0 if fill_empty else 0.0)


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
