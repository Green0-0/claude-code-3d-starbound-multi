## Medicine: bandages, stims, antidotes, cures — and the bleeding/infection
## model that gives the doctor NPC something to do.
##
## ## The wound model
##
## A big physical hit can open a wound (`bleeding`, stacking). Bleeding does
## damage, suppresses natural regeneration, and — this is the important part —
## if it is *left untreated* it accumulates toward an `infected` roll. Infection
## is not curable by a field bandage: it needs a real antibiotic or a doctor.
##
## That gives the loop three tiers, which is exactly the shape a settlement NPC
## needs to be worth walking to:
##
## | tier | tool | clears |
## |---|---|---|
## | field | `bandage` | bleeding |
## | pack | `medkit`, `antidote`, `antirad` | bleeding, poison, radiation |
## | clinic | doctor NPC, `panacea` | everything, including infection |
##
## ## Applying medicine from anywhere
##
## Items call [method apply_medicine] with a keyword. `SrvStatusEffect.cures`
## declares which effects each keyword clears, so adding a new medicine is a
## data change, not a code change.
class_name SrvMedical
extends Node

## Keywords understood by [method apply_medicine]. They match the `curable()`
## lists in `survival/effects/`.
const KEYWORDS: Array[StringName] = [
	&"bandage", &"antidote", &"antirad", &"cure", &"warmth", &"cooling",
]

## A physical hit at least this large can open a wound.
const BLEED_THRESHOLD := 12.0
## Base chance a qualifying hit causes bleeding, before difficulty scaling.
const BLEED_CHANCE := 0.18
## Seconds of untreated bleeding before an infection roll.
const INFECTION_DELAY := 45.0
const INFECTION_CHANCE := 0.35

var enabled := true

## instance id -> seconds of untreated bleeding accumulated.
var _untreated: Dictionary = {}
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = -3
	_rng.randomize()
	Events.entity_damaged.connect(_on_entity_damaged)
	Events.entity_died.connect(func(e: Node) -> void:
		if e != null:
			_untreated.erase(e.get_instance_id()))


# ================================================================== wounding
func _on_entity_damaged(entity: Node, amount: float, element: String, _source: Node) -> void:
	if not enabled or entity == null or Game.difficulty <= 0:
		return
	if element != Const.ELEM_PHYSICAL or amount < BLEED_THRESHOLD:
		return
	var chance := BLEED_CHANCE * (1.0 + 0.6 * float(Game.difficulty - 1))
	chance *= clampf(amount / (BLEED_THRESHOLD * 2.0), 0.5, 2.0)
	if _rng.randf() > chance:
		return
	Status.apply(&"bleeding", entity, 15.0, 1)
	if entity == Game.player:
		Events.toast("You are bleeding.", "warn")


func _physics_process(delta: float) -> void:
	if not enabled or Game.paused:
		return
	_timer += delta
	if _timer < 1.0:
		return
	var step := _timer
	_timer = 0.0
	_tick_infection(step)


## Track how long each bleeding entity has gone without treatment, and roll for
## infection once the clock runs out.
##
## Driven off `Status.holders_with(&"bleeding")` rather than the `entities`
## group: the set of bleeding things is tiny, the set of entities is not.
func _tick_infection(step: float) -> void:
	var bleeding := Status.holders_with(&"bleeding")
	var still: Dictionary = {}
	for n: Node in bleeding:
		var ve := n as VoxelEntity
		if ve == null or ve.dead:
			continue
		var key := ve.get_instance_id()
		still[key] = true
		var t := float(_untreated.get(key, 0.0)) + step * float(Status.stacks(&"bleeding", ve))
		if t < INFECTION_DELAY:
			_untreated[key] = t
			continue
		_untreated[key] = 0.0
		if Status.has(&"infected", ve):
			Status.apply(&"infected", ve, SrvStatusEffect.PERMANENT, 1)
		elif _rng.randf() < INFECTION_CHANCE:
			Status.apply(&"infected", ve, SrvStatusEffect.PERMANENT)
			if ve == Game.player:
				Events.toast("The wound has gone septic. Find a doctor.", "danger")
	# Anything that stopped bleeding since last tick had its wound closed.
	for key: int in _untreated.keys():
		if not still.has(key):
			_untreated.erase(key)


## 0 healthy, 1 scratched, 2 bleeding badly, 3 infected. The doctor NPC's
## dialogue tree branches on this.
func wound_severity(target: Node) -> int:
	var subject := target if target != null else Game.player
	if subject == null:
		return 0
	if Status.has(&"infected", subject):
		return 3
	var bleed := Status.stacks(&"bleeding", subject)
	if bleed >= 3:
		return 2
	if bleed > 0:
		return 1
	return 0


func is_wounded(target: Node) -> bool:
	return wound_severity(target) > 0


# ================================================================== medicine
## Apply one medicine. `keyword` selects what it clears (see [constant
## KEYWORDS]); `heal` is instant health; `effects` is the
## `[{"id":..., "duration":...}]` shape `ItemType.effects` uses.
##
## Returns false when the medicine would do nothing at all, so a consumable can
## refuse to be wasted.
func apply_medicine(keyword: StringName, target: Node, heal: float = 0.0,
		effects: Array = [], quiet: bool = false) -> bool:
	var subject := target if target != null else Game.player
	if subject == null:
		return false
	var cleared := 0
	if keyword != &"":
		cleared = Status.cure(subject, keyword)
	if keyword == &"bandage" and cleared > 0:
		_untreated.erase(subject.get_instance_id())
	if keyword == &"antirad" and Status.environment != null:
		Status.environment.flush_dose(60.0)
		cleared += 1

	var healed := 0.0
	if heal > 0.0 and subject.has_method(&"heal"):
		var ve := subject as VoxelEntity
		var before := ve.health if ve != null else 0.0
		subject.call(&"heal", heal)
		healed = (ve.health - before) if ve != null else heal

	if cleared == 0 and healed <= 0.0 and effects.is_empty():
		if not quiet and subject == Game.player:
			Events.toast("Nothing to treat.", "warn")
		return false

	Status.apply_list(effects, subject)
	Events.spawn_particles.emit(&"heal_mote", _pos_of(subject), 10)
	Events.play_sound.emit(&"medicine", _pos_of(subject))
	if not quiet and subject == Game.player and cleared > 0:
		Events.toast("Treated.", "good")
	return true


## A bandage: stops bleeding, a little instant healing, resets the infection
## clock. Fails on someone who is not bleeding.
func bandage(target: Node = null, potency: float = 1.0) -> bool:
	return apply_medicine(&"bandage", target, 8.0 * potency,
		[{"id": &"regeneration", "duration": 10.0 * potency}])


## A stim: no cures, pure short-term performance.
func stim(target: Node = null, kind: StringName = &"combat") -> bool:
	var subject := target if target != null else Game.player
	if subject == null:
		return false
	match kind:
		&"combat":
			Status.apply(&"strength", subject, 45.0)
			Status.apply(&"haste", subject, 45.0)
		&"guard":
			Status.apply(&"defense_up", subject, 60.0)
			Status.apply(&"fortified", subject, 12.0)
		&"focus":
			Status.apply(&"energised", subject, 90.0)
			Status.apply(&"mining_haste", subject, 90.0)
		_:
			Status.apply(&"regeneration", subject, 20.0)
	if Status.needs != null and subject == Game.player:
		Status.needs.restore_energy(25.0)
	Events.play_sound.emit(&"stim", _pos_of(subject))
	return true


## Everything a field kit can do at once.
func medkit(target: Node = null) -> bool:
	var subject := target if target != null else Game.player
	if subject == null:
		return false
	apply_medicine(&"bandage", subject, 30.0, [], true)
	apply_medicine(&"antidote", subject, 0.0, [], true)
	Status.apply(&"regeneration", subject, 25.0)
	_untreated.erase(subject.get_instance_id())
	return true


## The doctor NPC's service. `level` 0 field aid, 1 clinic, 2 surgery.
## Returns a short line the dialogue tree can echo back at the player.
func treat(patient: Node = null, level: int = 1) -> String:
	var subject := patient if patient != null else Game.player
	if subject == null:
		return "There is nobody to treat."
	var severity := wound_severity(subject)
	Status.cure(subject, &"bandage")
	if level >= 1:
		Status.cure(subject, &"antidote")
		Status.cure(subject, &"antirad")
		if Status.environment != null:
			Status.environment.flush_dose(100.0)
	if level >= 2:
		Status.cure(subject, &"cure")
		Status.clear_debuffs(subject)
	_untreated.erase(subject.get_instance_id())
	var ve := subject as VoxelEntity
	if ve != null:
		ve.heal(ve.max_health * (0.35 + 0.35 * float(level)))
	Status.apply(&"regeneration", subject, 30.0 + 30.0 * float(level))
	Events.spawn_particles.emit(&"heal_mote", _pos_of(subject), 18)
	match severity:
		0: return "Nothing wrong with you. Come back when there is."
		1: return "A scratch. Cleaned and dressed."
		2: return "You were losing a lot of blood. Sit still next time."
		_: return "That was infected. Another day and I could not have helped."
	return ""


## Cost in pixels the doctor should charge, so the NPC agent does not have to
## invent a price list.
func treatment_cost(patient: Node = null, level: int = 1) -> int:
	var severity := wound_severity(patient)
	return 25 + severity * 40 + level * 30


func _pos_of(n: Node) -> Vector3:
	var ve := n as VoxelEntity
	if ve != null and is_instance_valid(ve):
		return ve.aabb_center()
	var n3 := n as Node3D
	return n3.global_position if n3 != null else Vector3.ZERO


func save_state() -> Dictionary:
	var untreated := 0.0
	if Game.player != null:
		untreated = float(_untreated.get(Game.player.get_instance_id(), 0.0))
	return {"untreated": untreated, "enabled": enabled}


func load_state(d: Dictionary) -> void:
	_untreated.clear()
	enabled = bool(d.get("enabled", true))
	if Game.player != null:
		_untreated[Game.player.get_instance_id()] = float(d.get("untreated", 0.0))
