## The wandering trader who turns up on your ship. Not attached to any village:
## he appears after a jump, stays for a while, sells things no planet merchant
## carries, and is gone next time you look.
##
## Spawning is handled by [NpcSpawner.maybe_spawn_ship_trader], which listens for
## [signal Events.travel_finished] and rolls against [constant VISIT_CHANCE].
class_name NpcRoleTrader
extends NpcRole

## Odds of him showing up after any given jump.
const VISIT_CHANCE := 0.28
## How many in-game days he hangs around.
const STAY_DAYS := 1
## He deals in the strange: rarity floor is one band above a planet merchant.
const STOCK_KINDS: Array[int] = [
	ItemType.Kind.AUGMENT, ItemType.Kind.TECH, ItemType.Kind.WEAPON,
	ItemType.Kind.OBJECT, ItemType.Kind.CONSUMABLE, ItemType.Kind.MATERIAL,
]


func id() -> StringName:
	return &"trader"


func display() -> String:
	return "Wandering Trader"


func configure(npc: Node) -> void:
	npc.set(&"shop_kinds", STOCK_KINDS)
	npc.set(&"shop_size", 9)
	npc.set(&"shop_tier_bonus", 3)
	npc.set(&"max_health", 140.0)
	npc.set(&"invulnerable", true)
	npc.set(&"wander_radius", 3.0)
	npc.set(&"can_offer_quests", false)


## He never sleeps and never leaves the deck.
func schedule() -> Array[Dictionary]:
	return [{"from": 0.0, "to": 1.0, "activity": ACT_IDLE}]


func dialogue_tree(_npc: Node) -> String:
	return "trader_default"


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Docked without asking. Old habit.",
		"I have three of these left in the sector. Possibly two.",
		"No, I won't say where I got it.",
		"You've been to the shrines. I can smell the ozone.",
		"Everything's for sale. Even the questions.",
	])
