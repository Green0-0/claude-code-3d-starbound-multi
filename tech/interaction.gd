## The world-interaction router: mouse -> voxel -> mine / place / interact /
## open. Owned by `Tech` as `Tech.interaction`.
##
## ===========================================================================
##  ENTRY POINT FOR THE PLAYER AGENT
## ===========================================================================
## One call, once per physics frame, after the player has moved:
##
## [codeblock]
## func _physics_process(delta: float) -> void:
##     ...
##     integrate(delta)
##     if Tech.has_method(&"drive"):
##         Tech.drive(delta)      # -> Tech.interaction.poll(delta) + beam.update()
## [/codeblock]
##
## `drive()` is the only call required. Everything below is available if the
## player agent wants finer control:
##
##   `Tech.interaction.acquire_target()   -> Dictionary` (see SCHEMA below)
##   `Tech.interaction.try_interact()     -> bool`   the `interact` key
##   `Tech.interaction.try_place(stack)   -> bool`   secondary with a stack
##   `Tech.interaction.mine_hold(delta)   -> bool`   primary held
##   `Tech.interaction.cancel()`                     let go of everything
##   `Tech.interaction.enabled = false`              cutscenes, menus, dialogue
##
## `poll()` deliberately does **not** consume the primary button while a weapon
## is held — that input belongs to the combat agent. It only mines when the held
## item is the Matter Manipulator, a mining tool, or nothing at all.
##
## ===========================================================================
##  TARGET SCHEMA — the Dictionary returned by `acquire_target()`
## ===========================================================================
##   valid        bool      false when the cursor is out of reach or off-world
##   point        Vector3   exact aim point on the play-layer plane
##   voxel        Vector3i  the solid voxel under the cursor
##   has_voxel    bool
##   place        Vector3i  where a placed block would land
##   can_place    bool
##   layer_offset int       0 = play layer, 1..3 = behind (Depth Sight / Fold)
##   distance     float     from the player's chest to `point`
##   in_range     bool
##   entity       Node      nearest entity under the cursor, or null
##
## ===========================================================================
##  THE PLAY-LAYER VISIBILITY RULE
## ===========================================================================
## The player may only touch what they can see. Layers *in front* of the play
## layer are dissolved by the slab shader, so acting on them would mean mining
## an invisible wall — those are skipped entirely. Layers *behind* are visible
## but dimmed, and are out of reach unless a tech says otherwise:
## `Tech.interact_layer_tolerance()` returns 0 normally, 3 under Depth Sight and
## 1 under Fold. This file never hard-codes that number.
##
## Because the camera is orthographic and looks straight down the depth axis, we
## do not need a general voxel raycast: the cursor names a *column*. We find
## where the mouse ray crosses the play-layer plane and then walk backwards, one
## layer at a time, up to the tolerance. That is exactly the visibility rule,
## costs a handful of `World.get_block` calls, and is identical in all four
## views because every step is expressed through `View`.
class_name TchInteraction
extends RefCounted

## Guarded dependency: the camera agent's screen->world helper. If it is absent
## (or does not expose a shape we recognise) we fall back to the viewport's own
## `Camera3D`, which always works.
const CAM_PROJECT_PATH := "res://camera/screen_to_world.gd"

## Extra reach granted to the `interact` key over the tool beam, so doors and
## chests can be opened from a comfortable distance.
const INTERACT_RANGE := 6.0
## Radius around the aim point searched for an entity.
const ENTITY_PICK_RADIUS := 1.4

## Set false by cutscenes, menus and dialogue.
var enabled: bool = true
## Last target computed by `poll`, for the HUD's block outline.
var last_target: Dictionary = {}

var _cam_project: Script = null
var _cam_project_fn: String = ""
var _cam_project_argc: int = 0
var _cam_probed: bool = false
var _mining: bool = false
var _place_cooldown: float = 0.0


# ===========================================================================
#  Per-frame driver
# ===========================================================================
## Called once per physics frame by `Tech.drive()`.
func poll(delta: float) -> void:
	if _place_cooldown > 0.0:
		_place_cooldown = maxf(0.0, _place_cooldown - delta)
	if not enabled or Game.paused or Game.player == null or not World.ready_flag:
		cancel()
		return
	if UI.captures_input():
		cancel()
		return
	var p := Game.player
	if p.dead or p.is_shifting():
		cancel()
		return

	last_target = acquire_target()
	var stack := held_stack()

	if Input.is_action_just_pressed(&"interact"):
		try_interact()
		return

	if Input.is_action_pressed(&"primary") and _primary_is_ours(stack):
		mine_hold(delta)
	elif _mining:
		cancel()

	if Input.is_action_pressed(&"secondary") and _place_cooldown <= 0.0:
		if try_secondary(stack):
			_place_cooldown = 0.14


## Stops mining and hides the beam. Safe to call every frame.
func cancel() -> void:
	_mining = false
	if Tech.beam != null:
		Tech.beam.stop()
		Tech.beam.clear_target()


## True when the primary button belongs to this router rather than to combat.
func _primary_is_ours(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return true                      ## bare hands = the manipulator
	var t := stack.type()
	if t == null:
		return true
	if t.kind == ItemType.Kind.WEAPON:
		return false                     ## the combat agent owns this swing
	if t.kind == ItemType.Kind.TOOL:
		return t.tool_kind in [&"beam", &"pickaxe", &"axe", &"shovel", &"drill", &"hoe"]
	return t.kind != ItemType.Kind.CONSUMABLE


# ===========================================================================
#  Targeting
# ===========================================================================
## Resolves the mouse into a voxel target. See the SCHEMA in the file header.
func acquire_target() -> Dictionary:
	var out := {
		"valid": false, "point": Vector3.ZERO, "voxel": Vector3i.ZERO,
		"has_voxel": false, "place": Vector3i.ZERO, "can_place": false,
		"layer_offset": 0, "distance": 0.0, "in_range": false, "entity": null,
	}
	var p := Game.player
	if p == null:
		return out

	var point := aim_point()
	out["point"] = point
	var chest := p.aabb_center()
	var dist := Vector2(View.lateral_of(point - chest), point.y - chest.y).length()
	out["distance"] = dist
	out["in_range"] = dist <= maxf(reach(), INTERACT_RANGE)
	out["entity"] = _entity_at(point)

	var tol: int = Tech.interact_layer_tolerance()
	var step := View.depth_step()
	var base := Const.floor_v(point)
	var first_air := Vector3i.ZERO
	var have_air := false

	for d in range(0, tol + 1):
		var q := World.normalize(base + step * d)
		if not World.in_bounds_y(q.y):
			break
		var id := World.get_block(q)
		if id == Const.AIR or Blocks.is_replaceable(id):
			if not have_air:
				first_air = q
				have_air = true
			continue
		out["voxel"] = q
		out["has_voxel"] = true
		out["layer_offset"] = d
		out["valid"] = true
		# A block goes into the free voxel we walked through on the way here.
		# If there was none — the play-layer voxel itself is solid — there is
		# nowhere legal to build: the only free space left is *in front* of the
		# play layer, which the slab shader dissolves, so the player would be
		# stacking blocks they cannot see. Refuse instead.
		if have_air:
			out["place"] = first_air
			out["can_place"] = true
		return out

	if have_air:
		out["place"] = first_air
		out["can_place"] = true
		out["valid"] = true
	return out


## The world point on the play-layer plane directly under the mouse.
func aim_point() -> Vector3:
	var ray := mouse_ray()
	var origin: Vector3 = ray["origin"]
	var dir: Vector3 = ray["dir"]
	var axis := View.depth_axis()
	var plane_d := float(View.layer) + 0.5
	var denom: float = dir[axis]
	if absf(denom) > 0.001:
		var t: float = (plane_d - origin[axis]) / denom
		if t > -1000.0:
			return View.with_depth(origin + dir * t, plane_d)
	# Degenerate (the camera is not looking along the depth axis): fall back to
	# a plain voxel raycast and use its hit point.
	var hit := World.raycast(origin, dir, 128.0)
	if hit["hit"]:
		return View.with_depth(Vector3(hit["pos"]) + Vector3(0.5, 0.5, 0.5), plane_d)
	return View.with_depth(origin + dir * 24.0, plane_d)


## Mouse ray in world space: `{"origin": Vector3, "dir": Vector3}`.
## Tries the camera agent's `CamProject` helper first, then the live `Camera3D`.
func mouse_ray() -> Dictionary:
	var screen := _mouse_position()
	var via := _cam_project_ray(screen)
	if not via.is_empty():
		return via
	var cam := _camera()
	if cam != null:
		return {
			"origin": cam.project_ray_origin(screen),
			"dir": cam.project_ray_normal(screen),
		}
	# No camera at all (headless boot): aim straight ahead of the player.
	var p := Game.player
	var o: Vector3 = p.aabb_center() if p != null else Vector3.ZERO
	return {"origin": o - Vector3(View.forward()) * 32.0, "dir": Vector3(View.forward())}


func _mouse_position() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return Vector2.ZERO
	return tree.root.get_mouse_position()


func _camera() -> Camera3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var c := tree.root.get_camera_3d()
		if c != null:
			return c
	if Game.camera_rig != null:
		for child: Node in Game.camera_rig.get_children():
			if child is Camera3D:
				return child as Camera3D
	return null


## Probe `res://camera/screen_to_world.gd` once and remember which entry point
## it exposes. Any of these shapes is accepted:
##   `<fn>(screen) -> {"origin"/"from": Vector3, "dir"/"direction": Vector3}`
##   `<fn>(screen) -> Vector3`   (a point; we synthesise the camera direction)
func _cam_project_ray(screen: Vector2) -> Dictionary:
	if not _cam_probed:
		_cam_probed = true
		if ResourceLoader.exists(CAM_PROJECT_PATH):
			_cam_project = load(CAM_PROJECT_PATH) as Script
			if _cam_project != null:
				var wanted := ["mouse_ray", "ray_from_mouse", "screen_ray",
					"screen_to_world_ray", "project_ray", "screen_to_world",
					"mouse_world_point", "world_point"]
				var have: Dictionary = {}
				for m: Dictionary in _cam_project.get_script_method_list():
					have[String(m.get("name", ""))] = (m.get("args", []) as Array).size()
				for w: String in wanted:
					if have.has(w):
						_cam_project_fn = w
						_cam_project_argc = int(have[w])
						break
	if _cam_project == null or _cam_project_fn == "":
		return {}
	# Match the helper's arity exactly; calling with the wrong count would spam
	# engine errors every frame.
	var res: Variant = _cam_project.call(_cam_project_fn, screen) if _cam_project_argc >= 1 \
		else _cam_project.call(_cam_project_fn)
	if res is Dictionary:
		var d: Dictionary = res
		var o: Variant = d.get("origin", d.get("from", null))
		var v: Variant = d.get("dir", d.get("direction", null))
		if o is Vector3 and v is Vector3:
			return {"origin": o, "dir": (v as Vector3).normalized()}
	elif res is Vector3:
		var fwd := Vector3(View.forward())
		return {"origin": (res as Vector3) - fwd * 64.0, "dir": fwd}
	return {}


func _entity_at(point: Vector3) -> Node:
	var best: Node = null
	var best_d := ENTITY_PICK_RADIUS * ENTITY_PICK_RADIUS
	for e: VoxelEntity in Game.entities_in_radius(point, ENTITY_PICK_RADIUS):
		if e == Game.player or e.dead:
			continue
		if not Tech.node_in_reach(e):
			continue
		var d := e.aabb_center().distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = e
	return best


## Current tool reach, in blocks: the held tool's range, or the beam's.
func reach() -> float:
	var stack := held_stack()
	if stack != null and not stack.is_empty():
		var t := stack.type()
		if t != null and t.kind == ItemType.Kind.TOOL and t.tool_kind != &"beam":
			return t.tool_range
	return Tech.beam.reach() if Tech.beam != null else 5.0


# ===========================================================================
#  Actions
# ===========================================================================
## Primary held. Returns true on the frame a block actually breaks.
func mine_hold(delta: float) -> bool:
	var beam := Tech.beam
	var p := Game.player
	if beam == null or p == null:
		return false
	if not bool(last_target.get("has_voxel", false)) or not bool(last_target.get("in_range", false)):
		cancel()
		return false
	if Tech.modifier("mining_speed") <= 0.0:
		cancel()      ## morphed into a ball, or otherwise handless
		return false
	_mining = true
	beam.aim(last_target["voxel"], last_target["point"], _muzzle(p))
	return beam.fire(delta)


func _muzzle(p: VoxelEntity) -> Vector3:
	var forward := View.plane_dir_to_world(Vector2(float(p.facing), 0.0))
	return p.global_position + Vector3(0.0, p.box_size.y * 0.62, 0.0) + forward * 0.35


## Secondary button. Places whatever is held, or runs the beam's secondary for
## the current manipulator mode.
func try_secondary(stack: ItemStack) -> bool:
	var beam := Tech.beam
	if beam != null and (stack == null or stack.is_empty() or _is_manipulator(stack)):
		match beam.mode:
			TchToolBeam.Mode.LIQUID:
				return beam.pour(last_target.get("place", Vector3i.ZERO))
			TchToolBeam.Mode.WIRE:
				return beam.wire_cut(last_target.get("voxel", Vector3i.ZERO))
			TchToolBeam.Mode.PAINT:
				return beam.strip_paint(last_target.get("voxel", Vector3i.ZERO))
		return try_interact()
	return try_place(stack)


func _is_manipulator(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return true
	var t := stack.type()
	return t != null and t.kind == ItemType.Kind.TOOL and t.tool_kind == &"beam"


## Places the held stack's block or object at the cursor. Consumes one item on
## success (through the inventory, guarded).
func try_place(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false
	var t := stack.type()
	if t == null:
		return false
	if not bool(last_target.get("can_place", false)) or not bool(last_target.get("in_range", false)):
		return false
	var pos: Vector3i = last_target["place"]
	# Never place into a layer the player cannot see.
	if not Tech.voxel_in_reach(pos):
		return false

	match t.kind:
		ItemType.Kind.BLOCK:
			if t.places_block == &"" or not Blocks.has(t.places_block):
				return false
			if not World.place_block(pos, Blocks.id(t.places_block)):
				return false
			_consume(stack)
			Game.bump_stat("blocks_placed")
			return true
		ItemType.Kind.OBJECT:
			if not _place_object(t, pos):
				return false
			_consume(stack)
			Game.bump_stat("blocks_placed")
			return true
		ItemType.Kind.CONSUMABLE, ItemType.Kind.TECH:
			return use_held(stack)
	return false


## Objects are voxels plus a `tile_data` payload. The item names the object with
## `places_object = "obj://<id>"` and the matching block with
## `places_block = &"<id>"`; scene-path objects (`res://...`) are handed to
## `Game.spawn_entity` instead, so both conventions work.
func _place_object(t: ItemType, pos: Vector3i) -> bool:
	var spec := t.places_object
	if spec.begins_with("res://"):
		return Game.spawn_entity(spec, Vector3(pos) + Vector3(0.5, 0.0, 0.5)) != null
	var obj_id := StringName(spec.trim_prefix("obj://")) if spec != "" else t.places_block
	if obj_id == &"":
		return false
	if Tech.objects == null or not Tech.objects.has_method(&"place"):
		# Object subsystem missing: at least put the block down.
		return Blocks.has(obj_id) and World.place_block(pos, Blocks.id(obj_id))
	return bool(Tech.objects.call(&"place", pos, obj_id, View.view))


## The `interact` key (F) and the manipulator's secondary. Dispatch order:
##   1. a placed object at the cursor (chests, stations, doors, levers)
##   2. the block type's own `on_interact` hook
##   3. a placed object directly in front of the player, so the key still works
##      when the mouse is nowhere near
func try_interact() -> bool:
	var p := Game.player
	if p == null:
		return false
	if bool(last_target.get("has_voxel", false)) and bool(last_target.get("in_range", false)):
		var pos: Vector3i = last_target["voxel"]
		if _interact_at(pos, p):
			return true
	# Fall back to whatever the player is standing next to.
	var forward := View.plane_dir_to_world(Vector2(float(p.facing), 0.0))
	var probe := Const.floor_v(p.aabb_center() + forward)
	if _interact_at(probe, p):
		return true
	return _interact_at(Const.floor_v(p.aabb_center()), p)


func _interact_at(pos: Vector3i, p: Node) -> bool:
	if not Tech.voxel_in_reach(pos):
		return false
	if Tech.objects != null and Tech.objects.has_method(&"interact"):
		if bool(Tech.objects.call(&"interact", pos, p)):
			return true
	var bt := World.block_type_at(pos)
	if bt.on_interact.is_valid():
		return bool(bt.on_interact.call(pos, p))
	return false


## Uses a consumable / tech card in hand. Returns true when it was consumed.
func use_held(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false
	var t := stack.type()
	if t == null:
		return false
	if t.on_use.is_valid():
		if bool(t.on_use.call(Game.player, {"target": last_target})):
			_consume(stack)
			Events.item_used.emit(String(stack.id))
			return true
		return false
	if t.kind == ItemType.Kind.TECH and t.tech_id != &"":
		if Tech.is_unlocked(t.tech_id):
			Events.toast("You already know that tech.", "warn")
			return false
		if not Tech.requirements_met(t.tech_id):
			Events.toast("Missing prerequisite tech.", "warn")
			return false
		Tech.unlock(t.tech_id)
		_consume(stack)
		Events.item_used.emit(String(stack.id))
		return true
	return false


## Removes one item from the held stack, through the inventory when it exists.
func _consume(stack: ItemStack) -> void:
	var inv: Variant = Game.player.get("inventory") if Game.player != null else null
	if inv != null and inv.has_method(&"consume_selected"):
		inv.call(&"consume_selected", 1)
	elif inv != null and inv.has_method(&"remove_item"):
		inv.call(&"remove_item", stack.id, 1)
	else:
		stack.count = maxi(0, stack.count - 1)
		if stack.count == 0:
			stack.clear()
	Events.inventory_changed.emit()


## The stack in the player's selected hotbar slot, or null. Probes the several
## names an `Inventory` might reasonably expose.
func held_stack() -> ItemStack:
	var p := Game.player
	if p == null:
		return null
	var inv: Variant = p.get("inventory")
	if inv == null:
		return null
	for m: StringName in [&"held_stack", &"selected_stack", &"get_selected", &"hotbar_stack"]:
		if inv.has_method(m):
			var s: Variant = inv.call(m)
			if s is ItemStack:
				return s
			return null
	return null
