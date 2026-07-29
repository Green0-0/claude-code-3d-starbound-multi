## Capture pods.
##
## Beat a monster down to a sliver, lob a pod at it, and it becomes a pet that
## follows you — across depth layers, which matters here more than it does in a
## flat game: your pet re-syncs to the play layer every time you shift, so it is
## never left stranded behind a wall.
##
## Flow:
##   `throw_pod(from, dir, owner)`            empty pod, arcs, tries to capture
##   `throw_pod(from, dir, owner, pod_data)`  filled pod, releases the pet
##   `capture(mob)` / `release(data, pos, owner)` are the direct entry points
##   for other modules (a quest handing you a pet, for instance).
class_name MobCapture
extends RefCounted

## Pods only stick below this fraction of maximum health.
const CAPTURE_THRESHOLD := 0.4
const POD_ITEM := &"capture_pod"
const FILLED_POD_ITEM := &"filled_capture_pod"
const MAX_ACTIVE_PETS := 2
const POD_SPEED := 17.0


# ================================================================== queries
static func can_capture(mob) -> bool:
	if mob == null or not is_instance_valid(mob) or not (mob is MobBase):
		return false
	var m: MobBase = mob
	return m.is_capturable() and m.health_fraction() <= CAPTURE_THRESHOLD


## 0..1. Weaker monster, lower tier and easier species all help.
static func capture_chance(mob) -> float:
	if not (mob is MobBase):
		return 0.0
	var m: MobBase = mob
	if not m.is_capturable():
		return 0.0
	var frac := m.health_fraction()
	if frac > CAPTURE_THRESHOLD:
		return 0.0
	var base: float = 1.0 - frac / CAPTURE_THRESHOLD          # 0 at the cap, 1 at death's door
	base = 0.25 + base * 0.75
	base /= maxf(0.5, m.species.capture_difficulty)
	base /= 1.0 + 0.12 * float(m.species.tier)
	return clampf(base, 0.02, 0.98)


static func active_pets(owner: Node3D) -> Array:
	var out: Array = []
	var tree := owner.get_tree() if owner != null else null
	if tree == null:
		return out
	for n: Node in tree.get_nodes_in_group(&"pets"):
		var m := n as MobBase
		if m != null and not m.dead and m.escort_of == owner:
			out.append(m)
	return out


# ================================================================== capturing
## Attempt an immediate capture. Returns the pod payload on success, `{}` on
## failure (which is a legitimate outcome — the pod is consumed either way).
static func capture(mob, owner: Node3D = null) -> Dictionary:
	if not can_capture(mob):
		Events.toast("It is not weak enough yet.", "warning")
		Events.play_sound.emit(&"denied", (mob as Node3D).global_position if mob is Node3D else Vector3.ZERO)
		return {}
	var m: MobBase = mob
	var chance := capture_chance(m)
	Events.spawn_particles.emit(&"capture", m.aabb_center(), 24)
	if randf() > chance:
		Events.toast("%s broke free!" % m.species.display_name, "warning")
		Events.play_sound.emit(&"capture_fail", m.global_position)
		m.set_target(owner if owner != null else Game.player)
		return {}
	var data := pod_data_for(m)
	Events.toast("Captured: %s" % m.species.display_name, "success")
	Events.play_sound.emit(&"capture_success", m.global_position)
	Events.spawn_particles.emit(&"capture_success", m.aabb_center(), 32)
	m.queue_free()
	return data


## Serialise a monster into a pod payload.
static func pod_data_for(mob) -> Dictionary:
	var m: MobBase = mob
	return {
		"species": String(m.species_id),
		"name": m.species.display_name,
		"threat": m.planet_threat,
		"scale": m.size_scale,
		"level": 1,
		"xp": 0.0,
	}


## Recall a pet back into a pod payload.
static func recall(pet) -> Dictionary:
	if not (pet is MobBase):
		return {}
	var m: MobBase = pet
	var data := pod_data_for(m)
	data["level"] = int(m.spawn_opts.get("level", 1))
	Events.spawn_particles.emit(&"capture", m.aabb_center(), 16)
	Events.toast("%s returns to its pod." % m.species.display_name, "info")
	m.queue_free()
	return data


# =================================================================== release
## Bring a stored creature out as a pet belonging to `owner`.
static func release(data: Dictionary, pos: Vector3, owner: Node3D = null) -> MobBase:
	var em: Node3D = Game.entities_root
	if em == null or not em.has_method(&"spawn_species"):
		return null
	var host: Node3D = owner if owner != null else Game.player
	if host != null:
		var existing := active_pets(host)
		while existing.size() >= MAX_ACTIVE_PETS:
			var oldest: MobBase = existing.pop_front()
			if oldest != null and is_instance_valid(oldest):
				oldest.queue_free()
	var sid := StringName(data.get("species", ""))
	if not MobSpeciesDB.has(sid):
		push_warning("[Mobs] pod holds unknown species '%s'" % sid)
		return null
	var level: int = int(data.get("level", 1))
	var m = em.call(&"spawn_species", sid, pos, {
		"threat": int(data.get("threat", 1)) + level - 1,
		"scale": float(data.get("scale", 1.0)),
		"faction": &"ally",
		"no_loot": true,
		"level": level,
		"persistent": true,
	})
	var pet := m as MobBase
	if pet == null:
		return null
	pet.become_pet(host)
	Events.spawn_particles.emit(&"capture_release", pet.aabb_center(), 26)
	Events.play_sound.emit(&"pod_release", pos)
	Events.toast("%s joins you." % pet.species.display_name, "success")
	return pet


# ================================================================ pod throwing
## Spawn a thrown pod. Empty `pod_data` means "try to catch something".
static func throw_pod(from: Vector3, dir: Vector3, owner: Node3D, pod_data: Dictionary = {}) -> Node:
	var pod := Pod.new()
	pod.owner_node = owner
	pod.payload = pod_data.duplicate()
	var parent: Node = Game.entities_root if Game.entities_root != null else Game.main
	if parent == null:
		return null
	parent.add_child(pod)
	pod.global_position = from
	# Pods obey the plane like everything else: no depth component.
	var d := dir.normalized()
	if View.depth_axis() == 0:
		d.x = 0.0
	else:
		d.z = 0.0
	pod.velocity = d.normalized() * POD_SPEED + Vector3(0, 2.5, 0)
	Events.play_sound.emit(&"pod_throw", from)
	return pod


## Convenience for the inventory/tech agent: use a pod item held by the player.
## Returns true when the pod was consumed.
static func use_pod_item(player: Node3D, item_id: StringName, item_data: Dictionary = {}) -> bool:
	if player == null:
		return false
	var facing := 1.0
	var f: Variant = player.get(&"facing")
	if f != null and (f is int or f is float):
		facing = signf(float(f))
		if facing == 0.0:
			facing = 1.0
	# Throw along screen-right, so the arc reads correctly in every view.
	var r := View.right()
	var aim := Vector3(float(r.x), 0.0, float(r.z)) * facing + Vector3(0, 0.35, 0)
	var from: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	if item_id == FILLED_POD_ITEM:
		throw_pod(from, aim, player, item_data)
		return true
	if item_id == POD_ITEM:
		throw_pod(from, aim, player, {})
		return true
	return false


# ====================================================================== pod
## The thrown pod itself: a tiny physics entity with a procedurally drawn
## sprite, because there are no binary assets in this project.
class Pod extends VoxelEntity:
	var owner_node: Node3D = null
	var payload: Dictionary = {}
	var life := 6.0
	var _spr: Sprite3D = null
	static var _tex: ImageTexture = null

	func _ready() -> void:
		box_size = Vector3(0.35, 0.35, 0.35)
		max_health = 1.0
		health = 1.0
		invulnerable = true
		faction = &"neutral"
		super._ready()
		_spr = Sprite3D.new()
		_spr.texture = _pod_texture()
		_spr.pixel_size = 0.022
		_spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_spr.shaded = false
		_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_spr)

	static func _pod_texture() -> ImageTexture:
		if _tex != null:
			return _tex
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var d := Vector2(float(x) - 7.5, float(y) - 7.5).length()
				if d > 7.0:
					continue
				var top := y < 8
				var c := Color(0.9, 0.35, 0.3) if top else Color(0.92, 0.92, 0.95)
				if d > 6.0:
					c = Color(0.1, 0.1, 0.12)
				elif absi(y - 8) <= 0:
					c = Color(0.15, 0.15, 0.18)
				img.set_pixel(x, y, c)
		_tex = ImageTexture.create_from_image(img)
		return _tex

	func _physics_process(delta: float) -> void:
		if dead:
			return
		life -= delta
		rotation.z += delta * 9.0
		integrate(delta)
		if life <= 0.0:
			_fizzle()
			return
		if on_floor or on_wall or on_ceiling:
			_land()
			return
		for e: VoxelEntity in Game.entities_in_radius(global_position, 1.1):
			if e == self or e == owner_node or e.dead:
				continue
			if e is MobBase:
				_hit_monster(e as MobBase)
				return

	func _hit_monster(m: MobBase) -> void:
		if not payload.is_empty():
			_land()
			return
		var data := MobCapture.capture(m, owner_node)
		if not data.is_empty():
			_store(data)
		queue_free()

	func _land() -> void:
		if not payload.is_empty():
			MobCapture.release(payload, global_position + Vector3(0, 0.4, 0), owner_node)
			queue_free()
			return
		# An empty pod that hits nothing looks for a weakened monster nearby.
		var best: MobBase = null
		var best_d := 3.0
		for e: VoxelEntity in Game.entities_in_radius(global_position, 3.0):
			var m := e as MobBase
			if m == null or not MobCapture.can_capture(m):
				continue
			var d := global_position.distance_to(m.global_position)
			if d < best_d:
				best_d = d
				best = m
		if best != null:
			var data := MobCapture.capture(best, owner_node)
			if not data.is_empty():
				_store(data)
		else:
			_fizzle()
			return
		queue_free()

	func _fizzle() -> void:
		# A wasted pod is returned rather than destroyed; it is expensive kit.
		if payload.is_empty() and Items.has(MobCapture.POD_ITEM):
			Game.spawn_item_drop(global_position, MobCapture.POD_ITEM, 1)
		queue_free()

	func _store(data: Dictionary) -> void:
		if Items.has(MobCapture.FILLED_POD_ITEM):
			Game.spawn_item_drop(global_position, MobCapture.FILLED_POD_ITEM, 1, data)
		elif owner_node != null and owner_node.has_method(&"give_item"):
			owner_node.call(&"give_item", MobCapture.FILLED_POD_ITEM, 1)
		else:
			# Nothing can hold the pod yet: let the pet straight out instead.
			MobCapture.release(data, global_position + Vector3(0, 0.5, 0), owner_node)
