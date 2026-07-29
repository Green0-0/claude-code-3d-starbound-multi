## The single damage pipeline. *Every* source of damage in Planeshift — a sword
## swing, an arrow, an explosion, a burning status tick, a monster's contact
## attack — funnels through [method CbtDamage.apply].
##
## Pipeline order (do not reorder; content is balanced against it):
##
## 1. **Gate**   — dead / invulnerable / i-frames / **layer rule**.
## 2. **Base**   — `amount`.
## 3. **Scaling**— `scale`, weapon `damage_mult`, random variance, the
##                 attacker's outgoing `damage_dealt` status modifier.
## 4. **Crit**   — `crit_chance` roll -> multiply by `crit_mult`.
## 5. **Element**— target resistance to `element` (0..1 fraction removed).
## 6. **Armour** — `inventory.total_defense()` (guarded), reduced by `pierce`.
## 7. **Status** — the target's incoming `damage_taken` modifier, then the
##                 entity's own `modify_incoming_damage()` override.
## 8. **Apply**  — health, knockback, i-frames, `status_on_hit`, lifesteal.
## 9. **Emit**   — `Events.entity_damaged`, `Events.damage_number`, and
##                 `Events.screen_shake` when the packet asks for it.
##
## ## Packet schema
##
## All keys optional except `amount`.
##
## ```
## {
##   "amount":        float,     # base damage before any scaling. REQUIRED.
##   "element":       String,    # one of Const.ELEMENTS. default physical.
##   "source":        Node,      # the attacker (used for facing/knockback/lifesteal)
##   "weapon":        ItemStack, # the held stack, read for damage_mult / crit rolls
##   "scale":         float,     # flat multiplier applied before the crit roll (1.0)
##   "variance":      float,     # +/- randomisation fraction (0.08)
##   "crit_chance":   float,     # 0..1 probability (0.05)
##   "crit_mult":     float,     # multiplier on a crit (1.75)
##   "can_crit":      bool,      # false forces no crit (true)
##   "knockback":     float,     # impulse strength in m/s (0.0)
##   "knockback_dir": Vector2,   # PLANE-SPACE (lateral, up). omit to auto-derive
##   "pierce":        float,     # 0..1 fraction of the target's armour ignored
##   "true_damage":   bool,      # skip resistance AND armour entirely (false)
##   "force_armor":   bool,      # apply stage 6 even to self-mitigating targets
##   "status_on_hit": Array,     # [{ "id": &"burning", "chance": 0.4,
##                               #    "duration": 4.0, "stacks": 1 }, ...]
##   "layer_rule":    int,       # LAYER_SAME (default) / LAYER_ALL / LAYER_RANGE
##   "layer_min":     int,       # RANGE only: nearest offset, relative, inclusive
##   "layer_max":     int,       # RANGE only: furthest offset, relative, inclusive
##   "origin_layer":  int,       # layer the attack was launched from (View.layer)
##   "layer_falloff": float,     # damage kept per layer of separation (1.0)
##   "iframes":       float,     # i-frames granted on hit (DEFAULT_IFRAMES)
##   "ignore_iframes":bool,      # bypass the target's i-frame gate (false)
##   "lifesteal":     float,     # 0..1 of dealt damage healed back to `source`
##   "shake":         float,     # screen shake strength on hit (0.0)
##   "silent":        bool,      # suppress Events emission (false)
##   "tag":           String,    # free-form label for logs / achievements
## }
## ```
##
## ## The layer rule — the tactical heart of combat
##
## Combat happens **in the view plane**. A monster one voxel behind you is
## visible, lit, animated — and completely untouchable by a normal swing. That
## is deliberate. `layer_rule` is how a weapon buys its way out of that
## restriction, and it is the axis most of the interesting weapons play on.
class_name CbtDamage
extends RefCounted

## Only entities sharing the attack's depth layer can be hit. The default.
const LAYER_SAME := 0
## Depth is ignored entirely — a piercing beam, an omni-directional shockwave.
const LAYER_ALL := 1
## Hits `layer_min`..`layer_max` layers away from `origin_layer`, where positive
## offsets are *further from the camera* (behind the player).
const LAYER_RANGE := 2

## Default i-frames granted by a physical hit, in seconds.
const DEFAULT_IFRAMES := 0.28
## Armour constant: mitigation = ARMOR_K / (ARMOR_K + effective_defense).
const ARMOR_K := 100.0

## Amount fed to the self-mitigation probe. Large enough that a percentage
## override moves it well past `is_equal_approx`.
const PROBE_AMOUNT := 1000.0

static var _rng := RandomNumberGenerator.new()
static var _rng_seeded := false
## script path -> "this class mitigates its own incoming damage".
static var _mitigate_cache: Dictionary = {}


# ============================================================ packet building
## A fresh packet with every documented key at its default. Prefer
## [method packet] for one-liners.
static func default_packet() -> Dictionary:
	return {
		"amount": 0.0,
		"element": Const.ELEM_PHYSICAL,
		"source": null,
		"weapon": null,
		"scale": 1.0,
		"variance": 0.08,
		"crit_chance": 0.05,
		"crit_mult": 1.75,
		"can_crit": true,
		"knockback": 0.0,
		"pierce": 0.0,
		"true_damage": false,
		"status_on_hit": [],
		"layer_rule": LAYER_SAME,
		"layer_min": 0,
		"layer_max": 0,
		"layer_falloff": 1.0,
		"iframes": DEFAULT_IFRAMES,
		"ignore_iframes": false,
		"lifesteal": 0.0,
		"shake": 0.0,
		"silent": false,
		"tag": "",
	}


## Shorthand: `CbtDamage.packet(12.0, Const.ELEM_FIRE, self, {"knockback": 6.0})`.
static func packet(amount: float, element: String = Const.ELEM_PHYSICAL,
		source: Node = null, extra: Dictionary = {}) -> Dictionary:
	var p := default_packet()
	p["amount"] = amount
	p["element"] = element
	p["source"] = source
	for k: String in extra:
		p[k] = extra[k]
	return p


## Build a packet straight from a held weapon stack, reading every roll the
## weapon generator wrote into `ItemStack.data`.
static func packet_from_weapon(stack: ItemStack, source: Node = null,
		extra: Dictionary = {}) -> Dictionary:
	var p := default_packet()
	if stack != null and not stack.is_empty():
		p["amount"] = float(stack.stat("damage", 1.0))
		p["element"] = String(stack.stat("element", Const.ELEM_PHYSICAL))
		p["weapon"] = stack
		p["crit_chance"] = float(stack.stat("crit_chance", 0.05))
		p["crit_mult"] = float(stack.stat("crit_mult", 1.75))
		p["knockback"] = float(stack.stat("knockback", 4.0))
		p["pierce"] = float(stack.stat("armor_pierce", 0.0))
		p["lifesteal"] = float(stack.stat("lifesteal", 0.0))
		var planar := planar_rule(stack)
		for k2: String in planar:
			p[k2] = planar[k2]
		var sh: Variant = stack.stat("status_on_hit", [])
		if sh is Array:
			p["status_on_hit"] = (sh as Array).duplicate(true)
	p["source"] = source
	for k: String in extra:
		p[k] = extra[k]
	return p


## The depth rule an item carries, or an empty dictionary for "the default".
##
## Checked in order:
## 1. instance data (`layer_rule` / `layer_min` / `layer_max` / `layer_falloff`)
##    — this is what [CbtWeaponGen]'s planar affixes write;
## 2. the item type's **planar tags**, which is how hand-authored uniques in
##    `content/items/30_weapons.gd` declare themselves:
##    * `&"planar_all"`    — hits every layer (Phase Lance).
##    * `&"planar_behind"` — hits *only* the layer behind (Revenant Edge).
##    * `&"planar_deep"`   — hits a slab of layers behind (Depth Charge).
static func planar_rule(stack: ItemStack) -> Dictionary:
	if stack == null or stack.is_empty():
		return {}
	if stack.data.has("layer_rule"):
		return {
			"layer_rule": int(stack.data.get("layer_rule", LAYER_SAME)),
			"layer_min": int(stack.data.get("layer_min", 0)),
			"layer_max": int(stack.data.get("layer_max", 0)),
			"layer_falloff": float(stack.data.get("layer_falloff", 1.0)),
		}
	var t := stack.type()
	if t == null:
		return {}
	if t.has_tag(&"planar_all"):
		return {"layer_rule": LAYER_ALL, "layer_min": 0, "layer_max": 0, "layer_falloff": 1.0}
	if t.has_tag(&"planar_behind"):
		return {"layer_rule": LAYER_RANGE, "layer_min": 1, "layer_max": 1, "layer_falloff": 1.0}
	if t.has_tag(&"planar_deep"):
		return {"layer_rule": LAYER_RANGE, "layer_min": 0, "layer_max": 4, "layer_falloff": 0.82}
	return {}


# ================================================================ entry point
## Run the full pipeline against `target`. Returns the damage actually dealt
## (0.0 when the hit was rejected — wrong layer, i-frames, immune, dead).
static func apply(target: Node, p_packet: Dictionary) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	if not _rng_seeded:
		_rng.randomize()
		_rng_seeded = true

	var element := String(p_packet.get("element", Const.ELEM_PHYSICAL))
	var source := p_packet.get("source", null) as Node
	var ve := target as VoxelEntity

	# --------------------------------------------------------------- 1. gates
	if ve != null:
		if ve.dead or ve.invulnerable:
			return 0.0
		if ve.iframes > 0.0 and not bool(p_packet.get("ignore_iframes", false)) \
				and element == Const.ELEM_PHYSICAL:
			return 0.0
	if not layer_allows(target, p_packet):
		return 0.0

	# ---------------------------------------------------------------- 2. base
	var amount := float(p_packet.get("amount", 0.0))
	if amount <= 0.0:
		return 0.0

	# ------------------------------------------------------- 3. weapon scaling
	amount *= maxf(0.0, float(p_packet.get("scale", 1.0)))
	var weapon: Variant = p_packet.get("weapon", null)
	if weapon is ItemStack:
		amount *= float((weapon as ItemStack).stat("damage_mult", 1.0))
	var variance := float(p_packet.get("variance", 0.08))
	if variance > 0.0:
		amount *= 1.0 + _rng.randf_range(-variance, variance)
	if source != null:
		amount *= _status_mod("damage_dealt", source)
	amount *= _layer_falloff(target, p_packet)

	# ------------------------------------------------------------ 4. crit roll
	var crit := false
	if bool(p_packet.get("can_crit", true)):
		var chance := clampf(float(p_packet.get("crit_chance", 0.05)), 0.0, 1.0)
		if source != null:
			chance *= _status_mod("crit_chance", source)
		if chance > 0.0 and _rng.randf() < chance:
			crit = true
			amount *= maxf(1.0, float(p_packet.get("crit_mult", 1.75)))

	var raw := amount
	var true_damage := bool(p_packet.get("true_damage", false))
	# Entities that mitigate inside their own `modify_incoming_damage` (the
	# player and every monster do) must not be mitigated twice — see
	# [method self_mitigates].
	var own := false if bool(p_packet.get("force_armor", false)) else self_mitigates(target)

	# ---------------------------------------- 5. element vs resistance
	if not true_damage:
		if own:
			# Their override handles innate resistance; it does not read worn
			# gear, so elemental armour is still applied here.
			amount *= 1.0 - clampf(gear_resistance(target, element), -2.0, 0.95)
		else:
			amount *= 1.0 - clampf(resistance_of(target, element), -2.0, 0.95)

	# ------------------------------------------------- 6. armour mitigation
	if not true_damage and not own:
		var pierce := clampf(float(p_packet.get("pierce", 0.0)), 0.0, 1.0)
		var def := defense_of(target) * (1.0 - pierce)
		amount *= ARMOR_K / (ARMOR_K + maxf(0.0, def))

	# --------------------------------------------------- 7. status modifiers
	if not own:
		amount *= _status_mod("damage_taken", target)
	amount *= _status_mod("resist_" + element, target)
	if ve != null:
		amount = ve.modify_incoming_damage(amount, element, source)
	elif target.has_method(&"modify_incoming_damage"):
		amount = float(target.call(&"modify_incoming_damage", amount, element, source))

	amount = maxf(0.0, amount)
	if amount <= 0.0:
		if not bool(p_packet.get("silent", false)):
			Events.damage_number.emit(_center_of(target), 0.0, element, false)
		return 0.0
	# A hit that connects always registers for at least a chip of damage.
	amount = maxf(amount, minf(1.0, raw * 0.05))

	# -------------------------------------------------------------- 8. apply
	var dealt := _deliver(target, amount, element, source, crit,
		bool(p_packet.get("silent", false)))
	if dealt <= 0.0:
		return 0.0

	# An entity whose own `damaged` handler already knocked itself back (the
	# player does) has set `knockback_lock`; do not launch it a second time.
	if ve == null or ve.knockback_lock <= 0.0:
		_apply_knockback(target, p_packet, source)

	if ve != null and not ve.dead:
		var ifr := float(p_packet.get("iframes", DEFAULT_IFRAMES))
		if ifr > 0.0:
			ve.iframes = maxf(ve.iframes, ifr)

	var statuses: Variant = p_packet.get("status_on_hit", [])
	if statuses is Array and not (statuses as Array).is_empty():
		if ResourceLoader.exists("res://combat/status_hooks.gd"):
			CbtStatusHooks.apply_on_hit(target, statuses as Array, source, _rng)

	var steal := float(p_packet.get("lifesteal", 0.0))
	if steal > 0.0 and source != null and source.has_method(&"heal"):
		source.call(&"heal", dealt * steal)

	# --------------------------------------------------------------- 9. emit
	if not bool(p_packet.get("silent", false)):
		var shake := float(p_packet.get("shake", 0.0))
		if crit:
			shake = maxf(shake, 0.35)
		if shake > 0.0:
			Events.screen_shake.emit(shake, 0.12)
	return dealt


## Apply the same packet to a list of targets, sharing one roll of the dice per
## target. Returns total damage dealt.
static func apply_all(targets: Array, p_packet: Dictionary) -> float:
	var total := 0.0
	for t: Variant in targets:
		if t is Node:
			total += apply(t as Node, p_packet)
	return total


## Radial damage in **plane space** — the falloff is measured on screen, not in
## 3D, so an explosion looks and behaves like a 2D blast. Respects `layer_rule`
## exactly like a direct hit, which is what makes a "depth bomb" meaningful.
static func apply_radial(center: Vector3, radius: float, p_packet: Dictionary,
		exclude: Node = null) -> float:
	var total := 0.0
	var c := View.to_plane(center)
	# Iterated inline rather than through CbtTargeting so that this file has no
	# dependency on anything that depends back on it.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0.0
	for n: Node in tree.get_nodes_in_group(&"entities"):
		var e := n as VoxelEntity
		if e == null or e == exclude or e.dead:
			continue
		var d := c.distance_to(View.to_plane(e.aabb_center()))
		if d > radius:
			continue
		var falloff := 1.0 - clampf(d / maxf(0.001, radius), 0.0, 1.0) * 0.7
		var sub := p_packet.duplicate(true)
		sub["scale"] = float(p_packet.get("scale", 1.0)) * falloff
		if not sub.has("knockback_dir"):
			var away := View.to_plane(e.aabb_center()) - c
			sub["knockback_dir"] = away.normalized() if away.length() > 0.01 else Vector2.UP
		total += apply(e, sub)
	return total


# ================================================================ layer rules
## Does `target` sit in a depth layer this attack is allowed to reach?
static func layer_allows(target: Node, p_packet: Dictionary) -> bool:
	var rule := int(p_packet.get("layer_rule", LAYER_SAME))
	if rule == LAYER_ALL:
		return true
	var n3 := target as Node3D
	if n3 == null:
		return true
	var origin := int(p_packet.get("origin_layer", View.layer))
	var target_layer := floori(View.depth_of(n3.global_position))
	if rule == LAYER_SAME:
		return target_layer == origin
	# LAYER_RANGE — offsets are signed *away from the camera*.
	var off := (target_layer - origin) * View.depth_sign()
	return off >= int(p_packet.get("layer_min", 0)) and off <= int(p_packet.get("layer_max", 0))


## How many layers behind the attack origin `target` sits (negative = in front).
static func layer_offset_of(target: Node, p_packet: Dictionary) -> int:
	var n3 := target as Node3D
	if n3 == null:
		return 0
	var origin := int(p_packet.get("origin_layer", View.layer))
	return (floori(View.depth_of(n3.global_position)) - origin) * View.depth_sign()


static func _layer_falloff(target: Node, p_packet: Dictionary) -> float:
	var f := float(p_packet.get("layer_falloff", 1.0))
	if is_equal_approx(f, 1.0):
		return 1.0
	var off := absi(layer_offset_of(target, p_packet))
	return pow(clampf(f, 0.0, 1.0), float(off))


# ================================================================== defences
## Total armour value protecting `target`: worn armour via the inventory module
## (guarded — the inventory agent may not have landed), plus any `defense`
## field the entity itself exposes, plus the survival module's `defense`
## modifier.
static func defense_of(target: Node) -> float:
	var def := 0.0
	var inv: Variant = target.get(&"inventory") if target != null else null
	if inv != null and inv is Object and (inv as Object).has_method(&"total_defense"):
		def += float((inv as Object).call(&"total_defense"))
	var own: Variant = target.get(&"defense") if target != null else null
	if own != null and (own is float or own is int):
		def += float(own)
	def *= _status_mod("defense", target)
	return maxf(0.0, def)


## Fraction of `element` damage removed, 0..1 (negative = vulnerable).
##
## Sources, summed then clamped:
## * `target.resistances` — `Dictionary[String, float]`
## * `target.resistance_to(element)` — method override
## * `inventory.total_resistance(element)` — worn elemental armour (guarded)
static func resistance_of(target: Node, element: String) -> float:
	if target == null:
		return 0.0
	var r := 0.0
	var table: Variant = target.get(&"resistances")
	if table is Dictionary:
		r += float((table as Dictionary).get(element, 0.0))
	if target.has_method(&"resistance_to"):
		r += float(target.call(&"resistance_to", element))
	var inv: Variant = target.get(&"inventory")
	if inv != null and inv is Object and (inv as Object).has_method(&"total_resistance"):
		r += float((inv as Object).call(&"total_resistance", element))
	return clampf(r, -2.0, 0.95)


## Resistance from **worn gear only** — `inventory.total_resistance(element)`,
## which is how the elemental armour suits in `content/items/31_armor.gd` reach
## the pipeline. Entity overrides never read this, so it is always safe to add.
static func gear_resistance(target: Node, element: String) -> float:
	if target == null:
		return 0.0
	var inv: Variant = target.get(&"inventory")
	if inv != null and inv is Object and (inv as Object).has_method(&"total_resistance"):
		return clampf(float((inv as Object).call(&"total_resistance", element)), -2.0, 0.95)
	return 0.0


## Does this entity do its own armour / resistance / `damage_taken` maths inside
## `modify_incoming_damage`?
##
## `VoxelEntity`'s base implementation is the identity function, so anything
## that changes the number is mitigating itself and this pipeline must not
## mitigate it a second time — `PlayerActor` (which reads `defense_total()` and
## `Status.modifier("damage_taken")`) and every monster (`species.armour`,
## `species.resistance_to`) both do.
##
## Detected by probing the override once per **script class** and caching the
## answer, so the cost is one extra call per entity type per run, and any
## override with side effects is only disturbed once.
static func self_mitigates(target: Node) -> bool:
	if target == null or not target.has_method(&"modify_incoming_damage"):
		return false
	var scr: Variant = target.get_script()
	var key := "" if scr == null else String((scr as Resource).resource_path)
	if key == "":
		key = target.get_class()
	if _mitigate_cache.has(key):
		return bool(_mitigate_cache[key])
	var probe := float(target.call(&"modify_incoming_damage", PROBE_AMOUNT,
		Const.ELEM_PHYSICAL, null))
	var v := not is_equal_approx(probe, PROBE_AMOUNT)
	_mitigate_cache[key] = v
	return v


## Forget the self-mitigation probe results. Call after hot-reloading scripts.
static func clear_caches() -> void:
	_mitigate_cache.clear()


static func _status_mod(stat: String, target: Node) -> float:
	if target == null:
		return 1.0
	if Status != null and Status.has_method(&"modifier"):
		var m := float(Status.modifier(stat, target))
		# A stub returning 0.0 must never zero out combat.
		return m if m > 0.0 else 1.0
	return 1.0


# =================================================================== delivery
static func _deliver(target: Node, amount: float, element: String,
		source: Node, crit: bool, silent: bool) -> float:
	var ve := target as VoxelEntity
	if ve == null:
		# Non-VoxelEntity (destructible object, vehicle...): use its own hook.
		if target.has_method(&"apply_damage"):
			return float(target.call(&"apply_damage", amount, element, source))
		return 0.0

	# We deliberately do NOT call VoxelEntity.apply_damage(): it would re-run
	# modify_incoming_damage and re-emit the events without the crit flag.
	ve.health = maxf(0.0, ve.health - amount)
	ve.damaged.emit(amount, element, source)
	if not silent:
		Events.entity_damaged.emit(ve, amount, element, source)
		Events.damage_number.emit(ve.aabb_center(), amount, element, crit)
		# `player_damaged` is deliberately NOT emitted here: PlayerActor emits it
		# from its own `damaged` handler, which the line above already fired.
	if ve.health <= 0.0:
		ve.die(source)
	return amount


static func _apply_knockback(target: Node, p_packet: Dictionary, source: Node) -> void:
	var strength := float(p_packet.get("knockback", 0.0))
	if strength <= 0.0:
		return
	var ve := target as VoxelEntity
	if ve == null or ve.dead:
		return
	strength *= _status_mod("knockback_taken", target)
	var dir_plane: Vector2 = p_packet.get("knockback_dir", Vector2.ZERO)
	if dir_plane.length_squared() < 0.0001:
		if source is Node3D:
			var d := View.to_plane(ve.aabb_center()) - View.to_plane((source as Node3D).global_position)
			dir_plane = Vector2(signf(d.x) if absf(d.x) > 0.01 else 1.0, 0.0)
		else:
			dir_plane = Vector2(float(ve.facing), 0.0)
	# Knockback always has a little lift so it reads on screen.
	dir_plane = Vector2(dir_plane.x, maxf(dir_plane.y, 0.35)).normalized()
	ve.knockback(View.plane_dir_to_world(dir_plane), strength)


static func _center_of(target: Node) -> Vector3:
	var ve := target as VoxelEntity
	if ve != null:
		return ve.aabb_center()
	var n3 := target as Node3D
	return n3.global_position if n3 != null else Vector3.ZERO
