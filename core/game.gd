## Autoloaded as `Game`. Holds the live scene references, the clock, and the
## small handful of cross-cutting helpers every module needs. Loaded last so it
## can safely reference every other singleton.
extends Node

var main: Node3D = null
var player: VoxelEntity = null
var entities_root: Node3D = null
var fx_root: Node3D = null
var world_renderer: Node3D = null
var camera_rig: Node3D = null

var paused := false
var in_menu := false
var debug_overlay := false
var difficulty := 1                 ## 0 casual, 1 survival, 2 hardcore
var run_seed := 0

## Time of day: `tick` counts physics frames, wrapping every TICKS_PER_DAY.
## Start mid-morning, not at midnight. `day_fraction` is derived from this
## on the first frame, so a zero here means a new game opens in pitch dark.
var tick := int(Const.TICKS_PER_DAY * 0.30)
var day := 0
var day_fraction := 0.30            ## 0 = midnight, 0.5 = noon
var daylight := 1.0                 ## 0..1 sun strength, drives lighting
var time_scale := 1.0

var stats := {
	"blocks_mined": 0, "blocks_placed": 0, "monsters_killed": 0,
	"deaths": 0, "distance": 0.0, "flips": 0, "planets_visited": 0,
	"items_crafted": 0, "pixels_earned": 0,
}

const ITEM_DROP_SCENE := "res://entities/item_drop.tscn"
var _drop_scene: PackedScene = null


func _ready() -> void:
	process_priority = 100
	run_seed = randi()
	Events.view_flip_finished.connect(func(_v: int) -> void: stats["flips"] += 1)
	Events.entity_died.connect(_on_entity_died)


func _process(delta: float) -> void:
	if paused:
		return
	_advance_clock(delta)


func _advance_clock(delta: float) -> void:
	tick += int(maxf(1.0, 60.0 * delta * time_scale))
	if tick >= Const.TICKS_PER_DAY:
		tick -= Const.TICKS_PER_DAY
		day += 1
	day_fraction = float(tick) / float(Const.TICKS_PER_DAY)
	# Smooth sunrise/sunset: full dark 0.0-0.2, full light 0.3-0.7.
	var solar := sin(day_fraction * TAU - PI * 0.5) * 0.5 + 0.5
	daylight = clampf(remap(solar, 0.28, 0.55, 0.0, 1.0), 0.0, 1.0)
	if tick % 30 == 0:
		Events.time_changed.emit(tick, day_fraction)


func is_night() -> bool:
	return daylight < 0.25


func time_string() -> String:
	var minutes := int(day_fraction * 1440.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func set_paused(v: bool) -> void:
	paused = v
	get_tree().paused = v


# ------------------------------------------------------------------- helpers
## Does any live entity's box overlap this voxel? Stops the player sealing
## themselves or a monster inside a wall.
func entity_occupies(p: Vector3i) -> bool:
	var block_box := AABB(Vector3(p), Vector3.ONE)
	for n: Node in get_tree().get_nodes_in_group(&"entities"):
		var e := n as VoxelEntity
		if e == null or e.dead or not e.blocks_placement:
			continue
		var s := e.get_aabb_size()
		var b := AABB(e.global_position - Vector3(s.x * 0.5, 0, s.z * 0.5), s)
		if b.intersects(block_box):
			return true
	return false


func spawn_item_drop(pos: Vector3, item_id: StringName, count: int = 1, data: Dictionary = {}) -> Node:
	if count <= 0 or not Items.has(item_id):
		return null
	if _drop_scene == null and ResourceLoader.exists(ITEM_DROP_SCENE):
		_drop_scene = load(ITEM_DROP_SCENE)
	if _drop_scene == null:
		# Fallback: no drop entity available yet — hand it straight to the player.
		if player != null and player.has_method(&"give_item"):
			player.call(&"give_item", item_id, count)
		return null
	var d := _drop_scene.instantiate()
	if d.has_method(&"setup"):
		d.call(&"setup", ItemStack.new(item_id, count, data))
	# Attach first: `global_position` on a node outside the tree resolves against
	# an identity transform and logs an error.
	_attach_entity(d)
	if d is Node3D:
		(d as Node3D).global_position = pos
	return d


func spawn_entity(scene_path: String, pos: Vector3, setup: Dictionary = {}) -> Node:
	if not ResourceLoader.exists(scene_path):
		push_warning("[Game] missing entity scene %s" % scene_path)
		return null
	var e = load(scene_path).instantiate()
	_attach_entity(e)
	if e is Node3D:
		e.global_position = pos
	if not setup.is_empty() and e.has_method(&"configure"):
		e.call(&"configure", setup)
	return e


func _attach_entity(e: Node) -> void:
	var parent: Node = entities_root if entities_root != null else main
	if parent == null:
		parent = get_tree().current_scene
	if parent != null:
		parent.add_child(e)


func nearest_entity(pos: Vector3, max_dist: float, group: StringName = &"entities", same_layer := true) -> VoxelEntity:
	var best: VoxelEntity = null
	var best_d := max_dist * max_dist
	for n: Node in get_tree().get_nodes_in_group(group):
		var e := n as VoxelEntity
		if e == null or e.dead:
			continue
		if same_layer and floori(View.depth_of(e.global_position)) != View.layer:
			continue
		var d := pos.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func entities_in_radius(pos: Vector3, radius: float, group: StringName = &"entities") -> Array[VoxelEntity]:
	var out: Array[VoxelEntity] = []
	var r2 := radius * radius
	for n: Node in get_tree().get_nodes_in_group(group):
		var e := n as VoxelEntity
		if e != null and not e.dead and pos.distance_squared_to(e.global_position) <= r2:
			out.append(e)
	return out


func _on_entity_died(e: Node) -> void:
	if e != player and e is VoxelEntity and (e as VoxelEntity).faction == &"hostile":
		stats["monsters_killed"] += 1


func bump_stat(key: String, amount: float = 1.0) -> void:
	if stats.has(key):
		stats[key] += amount


# ---------------------------------------------------------- run / world flow
func start_new_game(p_seed: int = 0) -> void:
	run_seed = p_seed if p_seed != 0 else randi()
	stats["planets_visited"] = 0
	Universe.generate(run_seed)
	var start_id: String = Universe.starting_planet_id()
	travel_to_planet(start_id)


func travel_to_planet(planet_id: String) -> void:
	Events.travel_started.emit(World.planet_id, planet_id)
	SaveManager.flush_world(World.planet_id)
	var meta: Dictionary = Universe.planet_meta(planet_id)
	World.create_world(planet_id, int(meta.get("seed", run_seed)), meta)
	stats["planets_visited"] += 1
	_place_player_on_surface()
	Events.travel_finished.emit(planet_id)


func _place_player_on_surface() -> void:
	if player == null:
		return
	var x := World.size_x >> 1
	var z := World.size_z >> 1
	# Force the spawn column to exist before probing it.
	for cy in range(Const.WORLD_HEIGHT_CHUNKS - 1, -1, -1):
		World.request_chunk(Vector3i(x >> 4, cy, z >> 4))
	World._pump_generation_all()
	var y := World.surface_y(x, z)
	if y < 0:
		y = Const.WORLD_HEIGHT / 2
	player.teleport(Vector3(x + 0.5, y + 1.2, z + 0.5))
	View.set_layer(z if View.depth_axis() == 2 else x)
	World.update_streaming(player.global_position)


func save_state() -> Dictionary:
	return {
		"tick": tick, "day": day, "difficulty": difficulty,
		"run_seed": run_seed, "stats": stats.duplicate(),
		"planet": World.planet_id,
	}


func load_state(d: Dictionary) -> void:
	tick = int(d.get("tick", 0))
	day = int(d.get("day", 0))
	difficulty = int(d.get("difficulty", 1))
	run_seed = int(d.get("run_seed", randi()))
	var s: Dictionary = d.get("stats", {})
	for k: String in s:
		stats[k] = s[k]
