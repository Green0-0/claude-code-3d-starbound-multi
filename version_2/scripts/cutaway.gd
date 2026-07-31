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
##      * `FILL` — the enclosed air pocket you are standing in, and only what
##        occludes it. Reveals a whole tunnel or a whole room, and nothing else.
##      * `PLANAR` — an axis-aligned box of voxels in front of you, while you
##        are genuinely covered.
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
## The slab, in whole blocks, measured from the player's own cell.
var planar_depth := 34
var planar_half_width := 5
var planar_below := 1
var planar_above := 4

# ----------------------------------------------------------------------- fill
var fill_origin := Vector3i.ZERO
var fill_size := Vector3i.ZERO
## Packed as a grid of z-slices, the same layout the shader samples, so the mask
## goes to the GPU without a repacking pass.
var fill_mask := PackedByteArray()
var fill_cols := 1
var fill_width := 0
## Every marked cell, packed, so the cap builder can walk the set instead of the
## volume that contains it.
var fill_cells := PackedInt32Array()
## True when the player is in open air and the fill found nothing to work with.
var fill_empty := true

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
		# The slab already only removes what lies toward the lens, so the keep
		# shell has nothing left to protect — and leaving it out is what makes
		# the cut a solid box, which is what makes the caps cheap.
		return occluded and in_slab(bx, by, bz)
	var bc := Vector3(bx + 0.5, by + 0.5, bz + 0.5)
	if is_protected(bc):
		return false
	if mode == Mode.FILL and not fill_empty:
		return in_fill(bx, by, bz)
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


## An axis-aligned box of whole blocks in front of the player. Pure integer
## arithmetic — no square roots, no normalising, no per-cell vector maths.
func in_slab(bx: int, by: int, bz: int) -> bool:
	var t := toward_camera()
	var l := lateral_axis()
	var dx := bx - anchor.x
	var dy := by - anchor.y
	var dz := bz - anchor.z
	var toward := dx * t.x + dz * t.z
	if toward < 1 or toward > planar_depth:
		return false
	var lat := dx * l.x + dz * l.z
	if lat < -planar_half_width or lat > planar_half_width:
		return false
	return dy >= -planar_below and dy <= planar_above


## The slab as an integer AABB, which is all the cap builder needs.
func slab_bounds() -> AABB:
	var t := toward_camera()
	var l := lateral_axis()
	var lo := anchor
	var hi := anchor
	for corner_t: int in [1, planar_depth]:
		for corner_l: int in [-planar_half_width, planar_half_width]:
			var c := anchor + t * corner_t + l * corner_l
			lo = Vector3i(mini(lo.x, c.x), lo.y, mini(lo.z, c.z))
			hi = Vector3i(maxi(hi.x, c.x), hi.y, maxi(hi.z, c.z))
	lo.y = anchor.y - planar_below
	hi.y = anchor.y + planar_above
	return AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE))


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
func signature(world_version: int) -> String:
	return "%d|%d,%d,%d|%d,%d,%d|%d|%d|%d|%d|%d" % [
		mode, anchor.x, anchor.y, anchor.z, cam_cell.x, cam_cell.y, cam_cell.z,
		facing, int(occluded), int(enabled), int(opacity > 0.0), world_version]


func get_int_bounds() -> AABB:
	if mode == Mode.PLANAR:
		return slab_bounds()
	var pad := radius + target_padding + keep_radius
	var min_pos := camera_position.min(target_position) - Vector3(pad, pad, pad)
	var max_pos := camera_position.max(target_position) + Vector3(pad, pad, pad)
	if mode == Mode.FILL and fill_size.x > 0:
		min_pos = min_pos.min(Vector3(fill_origin))
		max_pos = max_pos.max(Vector3(fill_origin + fill_size))
	var min_i := Vector3i(floori(min_pos.x), floori(min_pos.y), floori(min_pos.z))
	var max_i := Vector3i(ceili(max_pos.x), ceili(max_pos.y), ceili(max_pos.z))
	return AABB(min_i, max_i - min_i)


func clear_fill() -> void:
	fill_mask = PackedByteArray()
	fill_cells = PackedInt32Array()
	fill_size = Vector3i.ZERO
	fill_origin = Vector3i.ZERO
	fill_cols = 1
	fill_width = 0
	fill_empty = true


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
	RenderingServer.global_shader_parameter_set(&"cut_planar_depth", float(planar_depth))
	RenderingServer.global_shader_parameter_set(&"cut_planar_width", float(planar_half_width))
	RenderingServer.global_shader_parameter_set(&"cut_planar_below", float(planar_below))
	RenderingServer.global_shader_parameter_set(&"cut_planar_above", float(planar_above))
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
