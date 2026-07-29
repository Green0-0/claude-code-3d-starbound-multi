## The default role: farmers, weavers, children, layabouts. No shop, no upgrades,
## but they carry the village's flavour and hand out the odd errand.
class_name NpcRoleVillager
extends NpcRole


func id() -> StringName:
	return &"villager"


func display() -> String:
	return "Villager"


func configure(npc: Node) -> void:
	npc.set(&"max_health", 70.0)
	npc.set(&"can_offer_quests", true)


func dialogue_tree(_npc: Node) -> String:
	return "villager_default"


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Morning. Or evening. I've lost track.",
		"Don't go past the third field after dark.",
		"You're the one who fell out of the sky.",
		"My grandmother said the ground used to face a different way.",
		"Rain's coming. My knee says so.",
		"Have you seen the standing stones? Nobody knows who cut them.",
		"Careful with that thing indoors.",
	])
