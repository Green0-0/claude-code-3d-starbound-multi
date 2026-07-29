## Moving light sources: the held torch, glowing projectiles, a monster's
## bioluminescence, a lava splash.
##
## These deliberately do **not** touch the voxel light grid. Re-flooding a BFS
## every time the player takes a step would cost more than the rest of the
## frame put together, and the removal wave would thrash every chunk the player
## walks past. Instead each request is a real `OmniLight3D` from a small pool,
## placed in the 3D scene and *added* on top of the baked vertex light by the
## renderer. Static emitters (lava blocks, glowing ore, a placed torch) stay in
## the baked grid where they belong — never register those here, or they will
## be lit twice.
##
## The pool is budgeted (`max_lights`) and distance-culled, and lights are
## scored so that when more sources exist than slots, the ones that matter win.
## Sources sitting far behind the play layer are scored down and dimmed, so a
## torch twelve layers back does not out-shout the one in the player's hand.
##
## Usage:
## [codeblock]
## var h := LitDynamic.request(torch_node, Color(1.0, 0.72, 0.36), 1.6, 9.0)
## LitDynamic.update(h, color, energy, radius)   # optional, any time
## LitDynamic.release(h)                          # or just free the node
## [/codeblock]
class_name LitDynamic
extends Node

## Set by `_ready`; the static façade forwards through it.
static var instance: LitDynamic = null

## Hard cap on live `OmniLight3D`s. Real-time lights are the single most
## expensive thing this module can do, so this stays small.
var max_lights := 12
## Sources further than this from the camera focus are culled outright.
var cull_distance := 46.0
## Extra fade applied to sources this many layers or more behind the player.
var layer_falloff := float(Const.SLAB_BEHIND)
## Global multiplier, so a bright planet can calm every torch down at once.
var energy_scale := 1.0
## Shadow-casting is off by default: with a dozen omnis it is not affordable.
var allow_shadows := false

var _records: Dictionary = {}          ## handle -> Dictionary
var _pool: Array[OmniLight3D] = []
var _container: Node3D = null
var _next_handle := 1
var _pulses: Array[Dictionary] = []
var _active_count := 0


func _ready() -> void:
	instance = self
	process_priority = 70
	Events.world_unloaded.connect(_release_all)


func _exit_tree() -> void:
	if instance == self:
		instance = null


# ================================================================ static façade
## Register a moving light. `node` is followed every frame; when it leaves the
## tree the light releases itself. Returns a handle, or 0 if lighting is down.
static func request(node: Node, color: Color, energy: float, radius: float) -> int:
	if instance == null:
		return 0
	return instance.add_source(node, color, energy, radius)


## Drop a light. Safe to call twice, or with 0.
static func release(handle: int) -> void:
	if instance != null:
		instance.remove_source(handle)


## Change a live light in place. Any argument may be left at its default to
## keep the current value (`energy < 0` / `radius < 0`).
static func update(handle: int, color: Color = Color(0, 0, 0, 0),
		energy: float = -1.0, radius: float = -1.0) -> void:
	if instance != null:
		instance.set_source(handle, color, energy, radius)


## Move a light that is not attached to a node.
static func move(handle: int, world_pos: Vector3) -> void:
	if instance != null:
		instance.set_source_position(handle, world_pos)


## A one-shot flash at a fixed point — muzzle flare, explosion, spell impact.
## Fire and forget; it releases itself.
static func pulse(world_pos: Vector3, color: Color, energy: float,
		radius: float, duration: float = 0.22) -> void:
	if instance != null:
		instance.add_pulse(world_pos, color, energy, radius, duration)


## How many pool lights are actually switched on right now.
static func active() -> int:
	return instance._active_count if instance != null else 0


# ==================================================================== instance
func add_source(node: Node, color: Color, energy: float, radius: float) -> int:
	var h := _next_handle
	_next_handle += 1
	_records[h] = {
		"node": node,
		"pos": (node as Node3D).global_position if node is Node3D else Vector3.ZERO,
		"color": color,
		"energy": maxf(0.0, energy),
		"radius": maxf(0.5, radius),
		"light": null,
		"score": 0.0,
	}
	return h


func remove_source(handle: int) -> void:
	var rec: Dictionary = _records.get(handle, {})
	if rec.is_empty():
		return
	var l: OmniLight3D = rec.get("light")
	if l != null and is_instance_valid(l):
		l.visible = false
	_records.erase(handle)


func set_source(handle: int, color: Color, energy: float, radius: float) -> void:
	var rec: Dictionary = _records.get(handle, {})
	if rec.is_empty():
		return
	if color.a > 0.0:
		rec["color"] = color
	if energy >= 0.0:
		rec["energy"] = energy
	if radius >= 0.0:
		rec["radius"] = maxf(0.5, radius)


func set_source_position(handle: int, world_pos: Vector3) -> void:
	var rec: Dictionary = _records.get(handle, {})
	if not rec.is_empty():
		rec["pos"] = world_pos


func add_pulse(world_pos: Vector3, color: Color, energy: float,
		radius: float, duration: float) -> void:
	var h := add_source(null, color, energy, radius)
	set_source_position(h, world_pos)
	_pulses.append({"handle": h, "t": 0.0, "dur": maxf(0.03, duration), "energy": energy})


func _release_all() -> void:
	for h: int in _records.keys():
		remove_source(h)
	_pulses.clear()


# ======================================================================= frame
func _process(delta: float) -> void:
	_advance_pulses(delta)
	if _records.is_empty():
		if _active_count > 0:
			_darken_all()
		return
	_ensure_container()
	if _container == null:
		return

	var focus := _focus()
	var cull2 := cull_distance * cull_distance
	var depth_axis := View.depth_axis()
	var depth_sign := View.depth_sign()
	var play_layer := View.layer

	# ---- score every source ----------------------------------------------
	var ranked: Array = []
	var dead: Array[int] = []
	for h: int in _records:
		var rec: Dictionary = _records[h]
		var node: Variant = rec["node"]
		if node != null:
			if not is_instance_valid(node):
				dead.append(h)
				continue
			if node is Node3D:
				rec["pos"] = (node as Node3D).global_position
		var pos: Vector3 = rec["pos"]
		var d2 := focus.distance_squared_to(pos)
		if d2 > cull2:
			rec["score"] = -1.0
			continue
		var depth: float = pos.x if depth_axis == 0 else pos.z
		var offset: float = (depth - float(play_layer)) * float(depth_sign)
		var layer_fade := 1.0
		if offset > 0.0:
			layer_fade = clampf(1.0 - 0.75 * (offset / maxf(1.0, layer_falloff)), 0.12, 1.0)
		elif offset < -1.0:
			# In front of the player: the slab dissolves it, so should we.
			layer_fade = clampf(1.0 + offset * 0.35, 0.0, 1.0)
		rec["fade"] = layer_fade
		var e: float = rec["energy"]
		var r: float = rec["radius"]
		rec["score"] = (e * r * layer_fade) / (4.0 + d2)
		if rec["score"] > 0.0001:
			ranked.append(h)
	for h: int in dead:
		remove_source(h)

	ranked.sort_custom(func(a: int, b: int) -> bool:
		return float(_records[a]["score"]) > float(_records[b]["score"]))

	# ---- bind the winners to pool slots ----------------------------------
	var n: int = mini(ranked.size(), max_lights)
	_ensure_pool(n)
	for i in n:
		var rec: Dictionary = _records[ranked[i]]
		var l: OmniLight3D = _pool[i]
		l.global_position = rec["pos"]
		l.light_color = rec["color"]
		l.omni_range = rec["radius"]
		l.light_energy = float(rec["energy"]) * float(rec.get("fade", 1.0)) * energy_scale
		l.shadow_enabled = allow_shadows and i < 2
		l.visible = l.light_energy > 0.01
		rec["light"] = l
	for i in range(n, _pool.size()):
		_pool[i].visible = false
	_active_count = n


func _advance_pulses(delta: float) -> void:
	if _pulses.is_empty():
		return
	var keep: Array[Dictionary] = []
	for p: Dictionary in _pulses:
		p["t"] = float(p["t"]) + delta
		var k: float = clampf(1.0 - float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		if k <= 0.0:
			remove_source(int(p["handle"]))
			continue
		set_source(int(p["handle"]), Color(0, 0, 0, 0), float(p["energy"]) * k * k, -1.0)
		keep.append(p)
	_pulses = keep


func _darken_all() -> void:
	for l: OmniLight3D in _pool:
		l.visible = false
	_active_count = 0


func _ensure_container() -> void:
	if _container != null and is_instance_valid(_container):
		return
	var parent: Node = Game.fx_root
	if parent == null:
		parent = Game.main
	if parent == null:
		return
	_container = Node3D.new()
	_container.name = "LitDynamicLights"
	parent.add_child(_container)
	_pool.clear()


func _ensure_pool(n: int) -> void:
	while _pool.size() < n and _pool.size() < max_lights:
		var l := OmniLight3D.new()
		l.name = "LitOmni%d" % _pool.size()
		l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		l.shadow_enabled = false
		l.light_specular = 0.15
		l.light_bake_mode = Light3D.BAKE_DISABLED
		l.visible = false
		_container.add_child(l)
		_pool.append(l)


func _focus() -> Vector3:
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3.ZERO
