## Sells food and drink, and rents a bed: paying to rest skips the clock to dawn
## and heals you. The one NPC who is reliably awake at night.
class_name NpcRoleInnkeeper
extends NpcRole

const STOCK_KINDS: Array[int] = [ItemType.Kind.CONSUMABLE, ItemType.Kind.SEED]
## Pixels charged for a night's sleep, before reputation discounts.
const ROOM_RATE := 40


func id() -> StringName:
	return &"innkeeper"


func display() -> String:
	return "Innkeeper"


func configure(npc: Node) -> void:
	npc.set(&"shop_kinds", STOCK_KINDS)
	npc.set(&"shop_size", 7)
	npc.set(&"max_health", 95.0)
	npc.set(&"can_offer_quests", true)


## Innkeepers keep the opposite hours to everyone else.
func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.40, "to": 0.62, "activity": ACT_SLEEP},
		{"from": 0.62, "to": 0.72, "activity": ACT_WANDER},
		{"from": 0.72, "to": 0.36, "activity": ACT_WORK},
		{"from": 0.36, "to": 0.40, "activity": ACT_SOCIALISE},
	]


func dialogue_tree(_npc: Node) -> String:
	return "innkeeper_default"


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Room's clean, the stew's cleaner.",
		"Sit down before you fall down.",
		"First drink's on the house. The second is not.",
		"You look like a bed would fix most of that.",
		"Mind the floran in the corner. He bites in his sleep.",
	])


static func room_rate(npc_id: StringName) -> int:
	return maxi(5, int(float(ROOM_RATE) * NpcReputation.price_multiplier(npc_id)))
