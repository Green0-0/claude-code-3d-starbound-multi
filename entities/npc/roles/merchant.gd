## Buys and sells against the inventory agent's currency. Stock rotates daily and
## deepens with the planet's tier, so a tier-1 forest merchant sells rope and a
## tier-6 merchant sells things that hum.
class_name NpcRoleMerchant
extends NpcRole

const STOCK_KINDS: Array[int] = [
	ItemType.Kind.MATERIAL, ItemType.Kind.CONSUMABLE, ItemType.Kind.BLOCK,
	ItemType.Kind.OBJECT, ItemType.Kind.SEED,
]


func id() -> StringName:
	return &"merchant"


func display() -> String:
	return "Merchant"


func configure(npc: Node) -> void:
	npc.set(&"shop_kinds", STOCK_KINDS)
	npc.set(&"shop_size", 10)
	npc.set(&"max_health", 90.0)
	npc.set(&"can_offer_quests", true)


func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.90, "to": 0.28, "activity": ACT_SLEEP},
		{"from": 0.28, "to": 0.34, "activity": ACT_WANDER},
		{"from": 0.34, "to": 0.78, "activity": ACT_WORK},      # minding the stall
		{"from": 0.78, "to": 0.90, "activity": ACT_SOCIALISE},
	]


func dialogue_tree(_npc: Node) -> String:
	return "merchant_default"


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Fresh stock, and honest prices.",
		"Everything you see, I carried up that hill myself.",
		"Buying, selling — I'm easy either way.",
		"Pixels talk. Come and have a look.",
		"That's not for sale. Everything else is.",
	])
