## The player's world-facing verbs: aim, mine, place, interact, swing.
##
## ## Aiming
## The mouse is projected through the (orthographic) camera onto the plane
## `depth == View.layer + 0.5`, giving a cursor in **plane space**
## (lateral, up). Everything downstream works from that 2D cursor, so aiming
## behaves identically in all four views. The cursor is clamped to the held
## tool's `tool_range` measured in plane space from the player's chest.
##
## ## What may be targeted — the slab rule
## Mining and placing may only touch voxels the player can actually *see*.
## The renderer dissolves everything in front of the play layer
## ([constant Const.SLAB_FRONT] == 0) and tints [constant Const.SLAB_BEHIND]
## layers behind it. So a candidate voxel is legal only when
## `0 <= View.layer_offset(pos) <= Const.SLAB_BEHIND`, and the interactive
## reach is tightened further to [constant DEPTH_REACH] layers.
##
## Concretely: starting at the play layer, we march *away from the camera*
## along [method View.depth_step] and take the **first non-air voxel** in that
## column. That voxel is by construction the one drawn at the pixel under the
## cursor — you can never mine a block hidden behind another, and you can never
## mine one of the invisible layers between you and the camera.
class_name PlayerInteraction
extends Node

signal mining_started(pos: Vector3i, block_id: int)
signal mining_progress(pos: Vector3i, t: float)
signal mining_cancelled()
signal mining_finished(pos: Vector3i, block_id: int)

## Reach when the player has no tool in hand.
const DEFAULT_REACH := 4.5
## How many layers *behind* the play layer the cursor may reach into.
const DEPTH_REACH := 3
## Bare-hand mining power, as a fraction of a tier-0 tool.
const HAND_POWER := 0.42
## Multiplier when the tool kind does not match the block's required tool.
const WRONG_TOOL := 0.3
## Multiplier when the tool tier is below the block's required tier.
const LOW_TIER := 0.25
## Seconds between block placements while the button is held.
const PLACE_COOLDOWN := 0.12
## Energy per second drained by a `beam`-kind tool (the matter manipulator).
const BEAM_ENERGY := 6.0

## The owning [PlayerActor]; untyped to avoid a cyclic class dependency.
var player = null                                               # noqa: type

# --- live mining state, polled by the HUD to draw the crack overlay ----------
var mine_active := false
var mine_target := Vector3i.ZERO
var mine_progress := 0.0          ## 0..1
var mine_block := Const.AIR

var _place_cd := 0.0
var _attack_cd := 0.0
var _cursor := Vector3.ZERO


func setup(p) -> void:                                          # noqa: type
	player = p
	_cursor = p.global_position


## Called once per physics frame by [PlayerActor] while the player has control.
func tick(delta: float) -> void:
	_place_cd = maxf(0.0, _place_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	var inp = player.input                                      # noqa: type
	_cursor = _compute_cursor()
	# Face the cursor while actually using something, otherwise let the run
	# direction win — a platformer that moon-walks feels wrong.
	if inp.primary_held or inp.secondary_held or absf(inp.move_axis) < 0.05:
		player.face_toward(_cursor)

	if inp.primary_held:
		_do_primary(delta)
	elif mine_active:
		cancel()

	if inp.secondary_held and _place_cd <= 0.0:
		_do_secondary()

	if inp.consume_interact():
		_do_interact()

	if inp.consume_tech():
		Tech.activate("primary")
		Events.tech_activated.emit(&"primary")


# ====================================================================== aiming
## World-space point the cursor currently rests on, inside the play plane.
func aim_point() -> Vector3:
	return _cursor


func _compute_cursor() -> Vector3:
	var depth := float(View.layer) + 0.5
	var eye: Vector3 = player.aabb_center()
	var fallback := View.with_depth(
		eye + Vector3(View.right()) * (float(player.facing) * 2.0), depth)

	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam == null:
		return fallback

	var mouse: Vector2 = player.input.mouse_position
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var axis := View.depth_axis()
	if absf(dir[axis]) < 0.0001:
		# Orthographic side view: the ray is parallel to the plane, so the
		# origin already carries the correct lateral/up components.
		return _clamp_to_reach(View.with_depth(origin, depth), eye)
	var t := (depth - origin[axis]) / dir[axis]
	var hit := origin + dir * t
	return _clamp_to_reach(View.with_depth(hit, depth), eye)


## Clamp the cursor to the current reach, measured in plane space.
func _clamp_to_reach(world: Vector3, eye: Vector3) -> Vector3:
	var reach := current_range()
	var from := View.to_plane(eye)
	var to := View.to_plane(world)
	var d := to - from
	if d.length() <= reach:
		return world
	to = from + d.normalized() * reach
	return View.to_world(to, float(View.layer) + 0.5)


## Reach of the held item, or [constant DEFAULT_REACH].
func current_range() -> float:
	var t: ItemType = player.held_type()
	var r := DEFAULT_REACH
	if t != null and (t.kind == ItemType.Kind.TOOL or t.kind == ItemType.Kind.WEAPON):
		r = maxf(1.5, t.tool_range)
	return r * Tech.modifier("reach")


## True when `pos` is inside the visible slab: on the play layer or behind it,
## never in the dissolved layers between the player and the camera.
func in_visible_slab(pos: Vector3i) -> bool:
	var off := View.layer_offset(pos)
	return off >= -Const.SLAB_FRONT and off <= Const.SLAB_BEHIND


## Resolve what the cursor is pointing at.
##
## Returns `{valid, pos, place_pos, can_place, block, depth_offset, distance}`.
func aim_target() -> Dictionary:
	var out := {
		"valid": false, "pos": Vector3i.ZERO, "place_pos": Vector3i.ZERO,
		"can_place": false, "block": Const.AIR, "depth_offset": 0,
		"distance": 0.0,
	}
	if player == null:
		return out
	var base := Const.floor_v(_cursor)
	var step := View.depth_step()
	var eye: Vector3 = player.aabb_center()
	out["distance"] = View.to_plane(eye).distance_to(View.to_plane(_cursor))

	# `k` is exactly `View.layer_offset()` of the probe, by construction.
	var found := false
	for k in range(0, DEPTH_REACH + 1):
		var p := base + step * k
		if not in_visible_slab(p):
			break
		if p.y < 0 or p.y >= Const.WORLD_HEIGHT:
			break
		var id := World.get_block(p)
		if id == Const.AIR or Blocks.is_replaceable(id):
			continue
		out["valid"] = true
		out["pos"] = p
		out["block"] = id
		out["depth_offset"] = k
		found = true
		break

	if not found:
		# Nothing solid in the column — offer the play-layer cell for placing.
		out["place_pos"] = base
		out["can_place"] = _can_place_at(base)
		return out

	var hit: Vector3i = out["pos"]
	var place := base
	if int(out["depth_offset"]) > 0:
		# Fill the background forward, one layer toward the camera.
		place = hit - step
	else:
		# In-plane placement: pick the face the cursor is nearest to.
		place = hit + _in_plane_face(hit)
	out["place_pos"] = place
	out["can_place"] = _can_place_at(place)
	return out


## Offset of the block face the cursor sits closest to, restricted to the two
## in-plane axes (lateral and up) so placement never leaves the view plane.
func _in_plane_face(block: Vector3i) -> Vector3i:
	var centre := Vector3(block) + Vector3(0.5, 0.5, 0.5)
	var d := View.to_plane(_cursor) - View.to_plane(centre)
	if absf(d.x) >= absf(d.y):
		var s := 1 if d.x >= 0.0 else -1
		return View.right() * s
	return Vector3i(0, 1 if d.y >= 0.0 else -1, 0)


func _can_place_at(p: Vector3i) -> bool:
	if p.y < 0 or p.y >= Const.WORLD_HEIGHT:
		return false
	if not in_visible_slab(p):
		return false
	var id := World.get_block(p)
	if id != Const.AIR and not Blocks.is_replaceable(id):
		return false
	# No floating blocks: something must be adjacent to build onto.
	for n: Vector3i in Const.FACE_NORMALS:
		if World.get_block(p + n) != Const.AIR:
			return true
	return false


# ====================================================================== mining
func _do_primary(delta: float) -> void:
	var t: ItemType = player.held_type()
	if t != null and t.kind == ItemType.Kind.WEAPON:
		_swing_weapon(t)
		return
	_mine(delta)


func _mine(delta: float) -> void:
	var target := aim_target()
	if not bool(target["valid"]):
		cancel()
		return
	var pos: Vector3i = target["pos"]
	var bt := Blocks.get_type(int(target["block"]))
	if not bt.breakable:
		cancel()
		return

	if not mine_active or pos != mine_target:
		mine_active = true
		mine_target = pos
		mine_block = int(target["block"])
		mine_progress = 0.0
		mining_started.emit(pos, mine_block)

	var st: ItemStack = player.held_stack()
	var tp := _tool_profile(bt)
	var power: float = tp["power"]
	if power <= 0.0:
		cancel()
		return

	# Beam tools (matter manipulator) burn energy while firing.
	if StringName(tp["kind"]) == &"beam":
		if not player.spend_energy(BEAM_ENERGY * delta):
			cancel()
			return

	mine_progress += delta * power / maxf(0.05, bt.hardness)
	mining_progress.emit(pos, minf(1.0, mine_progress))
	Events.stat_changed.emit("mine_progress", minf(1.0, mine_progress), 1.0)

	if randf() < delta * 8.0:
		Events.spawn_particles.emit(&"mining", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 2)

	if mine_progress < 1.0:
		return

	# --- break --------------------------------------------------------------
	var tier: int = tp["tier"]
	World.break_block(pos, tier, true)
	Game.bump_stat("blocks_mined")
	mining_finished.emit(pos, mine_block)
	Events.stat_changed.emit("mine_progress", 0.0, 1.0)
	if st != null and not st.is_empty() and st.damage_durability(1):
		Events.toast("%s broke!" % st.display_name(), "warn")
		st.clear()
		Events.inventory_changed.emit()
	mine_active = false
	mine_progress = 0.0


## Effective mining power / tier / kind for the held item against `bt`.
func _tool_profile(bt: BlockType) -> Dictionary:
	var t: ItemType = player.held_type()
	var power := HAND_POWER
	var kind: StringName = &""
	var tier := 0
	if t != null and t.kind == ItemType.Kind.TOOL:
		kind = t.tool_kind
		tier = t.tool_tier
		power = maxf(0.05, t.tool_power)
		if kind != &"beam" and bt.tool != &"any" and bt.tool != kind:
			power *= WRONG_TOOL
	elif t != null:
		power = HAND_POWER * 1.2
	if tier < bt.tool_tier:
		power *= LOW_TIER
	power *= Tech.modifier("mining_speed") * Status.modifier("mining_speed", player)
	return {"power": power, "tier": tier, "kind": kind}


## Abandon any in-progress mining (flip, menu, target lost).
func cancel() -> void:
	if not mine_active:
		return
	mine_active = false
	mine_progress = 0.0
	mining_cancelled.emit()
	Events.stat_changed.emit("mine_progress", 0.0, 1.0)


# ==================================================================== placing
func _do_secondary() -> void:
	var st: ItemStack = player.held_stack()
	var t: ItemType = player.held_type()
	if t == null:
		return
	match t.kind:
		ItemType.Kind.BLOCK:
			_place_block(t)
		ItemType.Kind.OBJECT:
			_place_object(t)
		_:
			_use_item(st, t)


func _place_block(t: ItemType) -> void:
	if t.places_block == &"" or not Blocks.has(t.places_block):
		return
	var target := aim_target()
	if not bool(target["can_place"]):
		return
	var p: Vector3i = target["place_pos"]
	if _overlaps_player(p):
		return
	if not World.place_block(p, Blocks.id(t.places_block)):
		return
	player.consume_held(1)
	Game.bump_stat("blocks_placed")
	_place_cd = PLACE_COOLDOWN


func _place_object(t: ItemType) -> void:
	if t.places_object == "":
		return
	var target := aim_target()
	if not bool(target["can_place"]):
		return
	var p: Vector3i = target["place_pos"]
	if _overlaps_player(p):
		return
	var node := Game.spawn_entity(t.places_object, Vector3(p) + Vector3(0.5, 0.0, 0.5))
	if node == null:
		return
	player.consume_held(1)
	_place_cd = PLACE_COOLDOWN * 3.0


func _use_item(st: ItemStack, t: ItemType) -> void:
	if not t.on_use.is_valid():
		# Default consumable behaviour until the survival agent installs its own.
		if t.kind == ItemType.Kind.CONSUMABLE:
			player.stats.feed(t.food)
			player.heal(t.heal)
			for e: Variant in t.effects:
				var ed := e as Dictionary
				Status.apply(StringName(ed.get("id", &"")), player, float(ed.get("duration", 5.0)))
			player.consume_held(1)
			Events.item_used.emit(String(t.id))
			Events.play_sound.emit(&"eat", player.global_position)
			_place_cd = 0.6
		return
	if t.energy_cost > 0.0 and not player.spend_energy(t.energy_cost):
		return
	var consumed: Variant = t.on_use.call(player, {"aim": _cursor, "stack": st})
	Events.item_used.emit(String(t.id))
	if consumed is bool and bool(consumed):
		player.consume_held(1)
	_place_cd = maxf(PLACE_COOLDOWN, 1.0 / maxf(0.1, t.attack_speed))


func _overlaps_player(p: Vector3i) -> bool:
	var s: Vector3 = player.box_size
	var lo: Vector3 = player.global_position - Vector3(s.x * 0.5, 0.0, s.z * 0.5)
	return AABB(lo, s).intersects(AABB(Vector3(p), Vector3.ONE))


# =================================================================== interact
func _do_interact() -> void:
	# 1. the block under the cursor
	var target := aim_target()
	if bool(target["valid"]):
		var pos: Vector3i = target["pos"]
		var bt := Blocks.get_type(int(target["block"]))
		if bt.on_interact.is_valid() and bool(bt.on_interact.call(pos, player)):
			Events.play_sound.emit(&"interact", Vector3(pos) + Vector3(0.5, 0.5, 0.5))
			return

	# 2. an object / NPC standing next to us, in our own layer
	var near := Game.nearest_entity(player.global_position, current_range(), &"interactable", true)
	if near != null and near.has_method(&"interact"):
		near.call(&"interact", player)
		return

	# 3. the block we are standing in front of (doors, chests, ladders)
	var front := Const.floor_v(player.global_position
		+ Vector3(View.right()) * (float(player.facing) * 0.8)
		+ Vector3(0.0, player.box_size.y * 0.5, 0.0))
	var fbt := Blocks.get_type(World.get_block(front))
	if fbt.on_interact.is_valid():
		fbt.on_interact.call(front, player)
		return
	Events.play_sound.emit(&"denied", player.global_position)


# ===================================================================== combat
## Minimal melee so the game is playable before the combat module lands. Any
## weapon whose [member ItemType.on_use] is set takes over completely.
func _swing_weapon(t: ItemType) -> void:
	if _attack_cd > 0.0:
		return
	_attack_cd = 1.0 / maxf(0.1, t.attack_speed)
	if t.energy_cost > 0.0 and not player.spend_energy(t.energy_cost):
		return
	player.visual.play_swing()
	Events.play_sound.emit(&"swing", player.global_position)
	if t.on_use.is_valid():
		t.on_use.call(player, {"aim": _cursor, "stack": player.held_stack()})
		Events.item_used.emit(String(t.id))
		return

	var reach := maxf(1.6, t.tool_range * 0.5)
	var dir: Vector3 = _cursor - Vector3(player.aabb_center())
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = Vector3(View.right()) * float(player.facing)
	dir = dir.normalized()
	for e: VoxelEntity in Game.entities_in_radius(player.aabb_center(), reach + 1.0):
		if e == player or e.dead or e.faction == &"player":
			continue
		if not player.in_same_layer(e):
			continue
		var to: Vector3 = e.aabb_center() - Vector3(player.aabb_center())
		if Const.lateral_of(to, View.view) * float(player.facing) < -0.4:
			continue
		e.apply_damage(t.damage, t.element, player)
		e.knockback(Vector3(dir.x, 0.45, dir.z), t.knockback)
