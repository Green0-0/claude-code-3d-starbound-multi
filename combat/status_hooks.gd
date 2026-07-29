## On-hit status application.
##
## Combat never talks to the survival module directly — it goes through here,
## and every call is guarded so the game runs identically before the survival
## agent's `Status` autoload replaces its stub. Until then, statuses simply do
## nothing and the rest of the pipeline is unaffected.
##
## The five combat statuses and their canonical ids:
##
## | id | element | what it does |
## |---|---|---|
## | `burning`  | fire     | damage over time, ignites grass, cured by water |
## | `frozen`   | ice      | heavy slow, brittle (extra crit taken) |
## | `shocked`  | electric | chains to nearby targets, interrupts charging |
## | `poisoned` | poison   | damage over time, blocks regeneration |
## | `bleeding` | physical | damage over time scaled by the victim's movement |
##
## Entries in a `status_on_hit` array look like:
## `{"id": &"burning", "chance": 0.35, "duration": 5.0, "stacks": 1}`.
class_name CbtStatusHooks
extends RefCounted

const BURNING := &"burning"
const FROZEN := &"frozen"
const SHOCKED := &"shocked"
const POISONED := &"poisoned"
const BLEEDING := &"bleeding"

const ALL := [BURNING, FROZEN, SHOCKED, POISONED, BLEEDING]

## Which status an element applies by default when a weapon does not say.
const ELEMENT_STATUS := {
	Const.ELEM_FIRE: BURNING,
	Const.ELEM_ICE: FROZEN,
	Const.ELEM_ELECTRIC: SHOCKED,
	Const.ELEM_POISON: POISONED,
	Const.ELEM_PHYSICAL: BLEEDING,
	Const.ELEM_COSMIC: SHOCKED,
}

## Default duration in seconds, before weapon rolls.
const DEFAULT_DURATION := {
	BURNING: 5.0, FROZEN: 3.0, SHOCKED: 2.5, POISONED: 8.0, BLEEDING: 6.0,
}

## Base chance an *elemental* weapon procs its element's status, per hit.
const BASE_ELEMENT_CHANCE := 0.22

static var _rng := RandomNumberGenerator.new()
static var _seeded := false


## The status an element naturally inflicts, or `&""` for none.
static func status_for_element(element: String) -> StringName:
	return ELEMENT_STATUS.get(element, &"")


## Apply an array of `status_on_hit` entries to `target`, rolling each chance.
## Returns the ids that actually landed.
static func apply_on_hit(target: Node, entries: Array, source: Node = null,
		rng: RandomNumberGenerator = null) -> Array[StringName]:
	var out: Array[StringName] = []
	if target == null or entries.is_empty():
		return out
	var r := rng if rng != null else _shared_rng()
	for raw: Variant in entries:
		var e: Dictionary = {}
		if raw is Dictionary:
			e = raw as Dictionary
		elif raw is StringName or raw is String:
			e = {"id": StringName(raw)}
		else:
			continue
		var id := StringName(e.get("id", &""))
		if id == &"":
			continue
		var chance := clampf(float(e.get("chance", 1.0)), 0.0, 1.0)
		if chance < 1.0 and r.randf() >= chance:
			continue
		var dur := float(e.get("duration", DEFAULT_DURATION.get(id, 4.0)))
		var stacks := int(e.get("stacks", 1))
		if apply(id, target, dur, stacks, source):
			out.append(id)
	return out


## Apply one status. Returns true when the `Status` autoload accepted it.
## Safe to call before the survival module exists.
static func apply(id: StringName, target: Node, duration: float = -1.0,
		stacks: int = 1, source: Node = null) -> bool:
	if target == null or id == &"":
		return false
	var ve := target as VoxelEntity
	if ve != null and (ve.dead or ve.invulnerable):
		return false
	if is_immune(target, id):
		return false
	var dur := duration
	if dur < 0.0:
		dur = float(DEFAULT_DURATION.get(id, 4.0))
	dur *= _resist_scale(target, id)
	if dur <= 0.05:
		return false
	if source != null and source.has_method(&"on_status_inflicted"):
		source.call(&"on_status_inflicted", id, target)
	if Status != null and Status.has_method(&"apply"):
		Status.apply(id, target, dur, stacks)
		Events.status_applied.emit(String(id), dur)
		Events.spawn_particles.emit(_particle_for(id), _center(target), 6)
		return true
	return false


## Convenience wrappers, so weapon and monster code reads like prose.
static func burn(target: Node, duration: float = 5.0, source: Node = null) -> bool:
	return apply(BURNING, target, duration, 1, source)


static func freeze(target: Node, duration: float = 3.0, source: Node = null) -> bool:
	return apply(FROZEN, target, duration, 1, source)


static func shock(target: Node, duration: float = 2.5, source: Node = null) -> bool:
	return apply(SHOCKED, target, duration, 1, source)


static func poison(target: Node, duration: float = 8.0, source: Node = null) -> bool:
	return apply(POISONED, target, duration, 1, source)


static func bleed(target: Node, duration: float = 6.0, source: Node = null) -> bool:
	return apply(BLEEDING, target, duration, 1, source)


## Remove a status, guarded.
static func cleanse(id: StringName, target: Node) -> void:
	if target != null and Status != null and Status.has_method(&"remove"):
		Status.remove(id, target)


## Is the status already on this target?
static func active_on(id: StringName, target: Node) -> bool:
	if target == null or Status == null or not Status.has_method(&"has"):
		return false
	return bool(Status.has(id, target))


## Immunity: an entity may declare `status_immunity: Array[StringName]`, or a
## resistance of 0.9+ to the matching element makes it immune outright.
static func is_immune(target: Node, id: StringName) -> bool:
	if target == null:
		return true
	var imm: Variant = target.get(&"status_immunity")
	if imm is Array and (imm as Array).has(id):
		return true
	var elem := _element_of(id)
	if elem != "" and _resistance(target, elem) >= 0.9:
		return true
	return false


## Build the `status_on_hit` array a weapon of this element should carry.
## `power` scales both chance and duration (roughly the weapon's tier).
static func rolls_for_element(element: String, power: float = 1.0) -> Array:
	var id := status_for_element(element)
	if id == &"" or element == Const.ELEM_PHYSICAL:
		return []
	return [{
		"id": id,
		"chance": clampf(BASE_ELEMENT_CHANCE * (0.7 + 0.3 * power), 0.05, 0.85),
		"duration": float(DEFAULT_DURATION.get(id, 4.0)) * (0.7 + 0.3 * power),
		"stacks": 1,
	}]


# ================================================================= internals
static func _element_of(id: StringName) -> String:
	for e: String in ELEMENT_STATUS:
		if ELEMENT_STATUS[e] == id:
			return e
	return ""


static func _resist_scale(target: Node, id: StringName) -> float:
	var elem := _element_of(id)
	if elem == "":
		return 1.0
	return clampf(1.0 - _resistance(target, elem), 0.0, 2.0)


## Local copy of the resistance lookup. Deliberately duplicated instead of
## calling [CbtDamage.resistance_of]: keeping this file free of any dependency
## on the damage pipeline avoids a cyclic script reference, since the damage
## pipeline calls *into* here on every hit.
static func _resistance(target: Node, element: String) -> float:
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


static func _particle_for(id: StringName) -> StringName:
	match id:
		BURNING: return &"status_burn"
		FROZEN: return &"status_freeze"
		SHOCKED: return &"status_shock"
		POISONED: return &"status_poison"
		BLEEDING: return &"status_bleed"
	return &"status_generic"


static func _center(target: Node) -> Vector3:
	var ve := target as VoxelEntity
	if ve != null:
		return ve.aabb_center()
	var n3 := target as Node3D
	return n3.global_position if n3 != null else Vector3.ZERO


static func _shared_rng() -> RandomNumberGenerator:
	if not _seeded:
		_rng.randomize()
		_seeded = true
	return _rng
