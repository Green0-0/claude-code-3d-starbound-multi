## Heals wounds, strips status effects and sells medicine. Charges by how hurt
## you are, so the free-clinic exploit of standing there at full health does not
## pay. Treats you free once your standing is high enough.
class_name NpcRoleDoctor
extends NpcRole

const STOCK_KINDS: Array[int] = [ItemType.Kind.CONSUMABLE]

## Pixels per point of missing health.
const HEAL_RATE := 1.2
## Flat fee to purge every debuff.
const CURE_FEE := 90
## Standing at which treatment becomes free.
const FREE_AT := 55.0


func id() -> StringName:
	return &"doctor"


func display() -> String:
	return "Doctor"


func configure(npc: Node) -> void:
	npc.set(&"shop_kinds", STOCK_KINDS)
	npc.set(&"shop_size", 6)
	npc.set(&"max_health", 85.0)
	npc.set(&"can_offer_quests", true)


func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.92, "to": 0.22, "activity": ACT_SLEEP},
		{"from": 0.22, "to": 0.80, "activity": ACT_WORK},
		{"from": 0.80, "to": 0.92, "activity": ACT_SOCIALISE},
	]


func dialogue_tree(_npc: Node) -> String:
	return "doctor_default"


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Sit. Let me see it.",
		"You're bleeding on my floor.",
		"Whatever bit you, don't let it do it twice.",
		"I can fix bones. I can't fix judgement.",
		"Drink water. That's free advice.",
	])


# =========================================================================
## Cost of patching the player up right now.
static func heal_cost(npc_id: StringName) -> int:
	var p := Game.player
	if p == null:
		return 0
	if NpcReputation.of_npc(npc_id) >= FREE_AT:
		return 0
	var missing := maxf(0.0, p.max_health - p.health)
	return int(round(missing * HEAL_RATE * NpcReputation.price_multiplier(npc_id)))


static func cure_cost(npc_id: StringName) -> int:
	if NpcReputation.of_npc(npc_id) >= FREE_AT:
		return 0
	return int(round(float(CURE_FEE) * NpcReputation.price_multiplier(npc_id)))


## Full heal. Returns false when the player cannot pay (or is already whole).
static func treat(npc: Node) -> bool:
	var p := Game.player
	if p == null:
		return false
	var npc_id := StringName(npc.get("npc_id")) if npc != null else &""
	if p.health >= p.max_health:
		Events.toast("There's nothing wrong with you that I can fix.", "info")
		return false
	var cost := heal_cost(npc_id)
	if cost > 0 and not NpcInventoryBridge.spend_pixels(cost):
		Events.toast("Treatment is %d pixels." % cost, "warn")
		return false
	NpcInventoryBridge.heal_player(p.max_health)
	NpcReputation.adjust_npc(npc_id, 1.0)
	var n3 := npc as Node3D
	Events.spawn_particles.emit(&"heal", n3.global_position if n3 != null else Vector3.ZERO, 20)
	Events.toast("Patched up.", "good")
	return true


## Strip every debuff.
static func cure(npc: Node) -> bool:
	var npc_id := StringName(npc.get("npc_id")) if npc != null else &""
	var cost := cure_cost(npc_id)
	if cost > 0 and not NpcInventoryBridge.spend_pixels(cost):
		Events.toast("A purge is %d pixels." % cost, "warn")
		return false
	NpcInventoryBridge.cure_player()
	NpcReputation.adjust_npc(npc_id, 1.0)
	Events.toast("The shaking stops.", "good")
	return true
