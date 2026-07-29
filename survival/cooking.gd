## The runtime behind food: the eating gate, spoilage, and turning an
## `ItemType`'s declared effects into real buffs.
##
## Every consumable registered in `content/items/40_food.gd` routes its
## `on_use` here, so the rules live in exactly one place:
##
## 1. **Gate** — you cannot start a second bite while the first is chewing.
##    `eat_time` scales with how filling the item is, which is what stops the
##    player inhaling forty apples mid-fight.
## 2. **Spoilage** — perishable stacks carry the world time they were made in
##    `stack.data.packed`. Past their shelf life they feed less and can make
##    you ill; well past it they are simply rotten.
## 3. **Buffs** — `ItemType.effects` (built with `.with_effect()`) are applied
##    through `Status`, plus `well_fed` for a real meal and `feast` for the
##    hand-made "perfect meals" the kitchen recipes produce.
class_name SrvCooking
extends Node

## Seconds to eat, before the size scaling.
const BASE_EAT_TIME := 0.9
const MAX_EAT_TIME := 2.4

## Default shelf life for anything tagged `perishable` that does not declare
## its own `shelf_life` bonus, in seconds of world time.
const DEFAULT_SHELF_LIFE := 1800.0
## Below this freshness the food starts to be risky.
const STALE_AT := 0.35

var eating := false
var eat_progress := 0.0
var eat_time := 0.0
var _eating_item: StringName = &""
var _eater: Node = null
var _spoil_timer := 0.0
## Freshness of the mouthful currently being chewed, sampled when it started.
var _pending_freshness := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = -4
	_rng.randomize()


func _physics_process(delta: float) -> void:
	if Game.paused:
		return
	if eating:
		eat_progress += delta
		if eat_progress >= eat_time:
			_finish_eating()
	_spoil_timer += delta
	if _spoil_timer >= 5.0:
		_spoil_timer = 0.0
		_sweep_inventory()


# ================================================================ world clock
## Monotonic seconds since the run started, from `Game`'s day/tick clock.
static func world_seconds() -> float:
	return (float(Game.day) * float(Const.TICKS_PER_DAY) + float(Game.tick)) / 60.0


# ==================================================================== eating
## The entry point every food item's `on_use` calls.
##
## `ctx` may carry `{"stack": ItemStack}`; when it does, spoilage is read from
## the stack rather than assumed fresh. Returns true when the item was
## consumed, which is the contract `ItemType.on_use` documents.
func consume(item_id: StringName, user: Node, ctx: Dictionary = {}) -> bool:
	var t := Items.get_type(item_id)
	if t == null:
		return false
	var eater := user if user != null else Game.player
	if eater == null:
		return false
	if eating:
		return false

	var stack: ItemStack = ctx.get("stack") as ItemStack
	var fresh := freshness(item_id, stack)

	# Refusing a meal you have no room for stops the player wasting a feast.
	if t.food > 0.0 and Status.needs != null and Status.needs.hunger >= SrvNeeds.MAX_VALUE - 0.5 \
			and t.heal <= 0.0 and t.effects.is_empty():
		Events.toast("You are too full.", "warn")
		return false

	eating = true
	eat_progress = 0.0
	eat_time = clampf(BASE_EAT_TIME + t.food * 0.035, BASE_EAT_TIME, MAX_EAT_TIME)
	if t.has_tag(&"drink"):
		eat_time *= 0.6
	_eating_item = item_id
	_eater = eater
	var sfx: StringName = &"drink" if t.has_tag(&"drink") else &"eat"
	Events.play_sound.emit(sfx, _pos_of(eater))
	# Effects land when the last bite goes down, not on the first.
	_pending_freshness = fresh
	return true


func _finish_eating() -> void:
	eating = false
	var t := Items.get_type(_eating_item)
	var eater := _eater
	_eater = null
	if t == null or eater == null or not is_instance_valid(eater):
		return
	var fresh := _pending_freshness
	_apply_nutrition(t, eater, fresh)
	Events.item_used.emit(String(t.id))
	Events.spawn_particles.emit(&"eat_crumb", _pos_of(eater), 5)


func _apply_nutrition(t: ItemType, eater: Node, fresh: float) -> void:
	var quality := clampf(fresh, 0.25, 1.0)

	if Status.needs != null:
		if t.has_tag(&"drink"):
			Status.needs.drink(maxf(t.food, 12.0) * quality)
			if t.food > 0.0:
				Status.needs.feed(t.food * 0.4 * quality)
		else:
			Status.needs.feed(t.food * quality)
		if t.has_tag(&"stimulant"):
			Status.needs.restore_energy(30.0)

	if t.heal > 0.0 and eater.has_method(&"heal"):
		eater.call(&"heal", t.heal * quality)
		if eater == Game.player:
			Events.player_healed.emit(t.heal * quality)

	# Spoiled food is a gamble, and a bad one.
	if fresh < STALE_AT:
		var risk := (STALE_AT - fresh) / STALE_AT
		if _rng.randf() < risk * 0.8:
			Status.apply(&"poisoned", eater, 8.0 + 8.0 * risk)
			Events.toast("That was well past its best.", "warn")
		return

	Status.apply_list(t.effects, eater)

	if t.has_tag(&"perfect_meal"):
		Status.apply(&"feast", eater)
	elif t.food >= 18.0 or (Status.needs != null and Status.needs.is_well_fed()):
		Status.apply(&"well_fed", eater)


## Abort the current bite (took a hit, opened a menu).
func interrupt() -> void:
	if not eating:
		return
	eating = false
	_eater = null
	Events.toast("Interrupted.", "warn")


func is_eating() -> bool:
	return eating


## 0..1 for a HUD progress ring.
func eat_fraction() -> float:
	return clampf(eat_progress / maxf(0.01, eat_time), 0.0, 1.0)


# =================================================================== spoilage
## 1.0 = fresh, 0.0 = rotten. Non-perishable items are always 1.0.
func freshness(item_id: StringName, stack: ItemStack = null) -> float:
	var t := Items.get_type(item_id)
	if t == null or not t.has_tag(&"perishable"):
		return 1.0
	var life := float(t.stat_bonuses.get("shelf_life", DEFAULT_SHELF_LIFE))
	if life <= 0.0:
		return 1.0
	var packed := world_seconds()
	if stack != null:
		if stack.data.has("packed"):
			packed = float(stack.data["packed"])
		else:
			# First time we have seen this stack: date-stamp it now.
			stack.data["packed"] = packed
	var age := maxf(0.0, world_seconds() - packed)
	return clampf(1.0 - age / life, 0.0, 1.0)


## Stamp a freshly crafted or harvested stack. The crafting agent can call this
## on kitchen output; harvesting does it implicitly through `Items.make`.
func date_stamp(stack: ItemStack) -> void:
	if stack != null and not stack.is_empty():
		var t := stack.type()
		if t != null and t.has_tag(&"perishable"):
			stack.data["packed"] = world_seconds()


## Walk the player's inventory and convert anything completely rotten. Written
## defensively: the inventory agent may expose slots under several names, and a
## shape we do not recognise simply means no sweep (eating still checks).
func _sweep_inventory() -> void:
	if Game.player == null:
		return
	var inv: Variant = Game.player.get(&"inventory")
	if inv == null or not (inv is Object):
		return
	var obj := inv as Object
	var slots: Variant = null
	for field: StringName in [&"slots", &"items", &"stacks"]:
		var v: Variant = obj.get(field)
		if v is Array:
			slots = v
			break
	if slots == null:
		return
	var changed := false
	for entry in (slots as Array):
		var st := entry as ItemStack
		if st == null or st.is_empty():
			continue
		var t := st.type()
		if t == null or not t.has_tag(&"perishable"):
			continue
		if not st.data.has("packed"):
			st.data["packed"] = world_seconds()
			continue
		if freshness(st.id, st) > 0.0:
			continue
		if Items.has(&"rotten_food"):
			st.id = &"rotten_food"
			st.data.erase("packed")
			changed = true
	if changed:
		Events.inventory_changed.emit()
		Events.toast("Something in your pack has gone off.", "warn")


func _pos_of(n: Node) -> Vector3:
	var ve := n as VoxelEntity
	if ve != null and is_instance_valid(ve):
		return ve.aabb_center()
	var n3 := n as Node3D
	return n3.global_position if n3 != null else Vector3.ZERO


func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	eating = false
	_eater = null
