## Studies the perspective mechanic and pays you to do the fieldwork. Scientists
## are the main source of OBSERVE quests and the only villagers who hand out tech.
##
## They are also the in-world voice explaining what flipping actually *is*, so
## their dialogue does a lot of teaching.
class_name NpcRoleScientist
extends NpcRole

## Techs a scientist may award, best-effort — unknown ids are ignored by Tech.
const TECH_POOL: Array[StringName] = [
	&"phase_step", &"plane_sense", &"depth_dash", &"glide", &"sprint",
]


func id() -> StringName:
	return &"scientist"


func display() -> String:
	return "Scientist"


func configure(npc: Node) -> void:
	npc.set(&"max_health", 80.0)
	npc.set(&"can_offer_quests", true)
	npc.set(&"quest_bias", &"observe")


func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.05, "to": 0.20, "activity": ACT_SLEEP},
		{"from": 0.20, "to": 0.75, "activity": ACT_WORK},
		{"from": 0.75, "to": 0.88, "activity": ACT_SOCIALISE},
		{"from": 0.88, "to": 0.05, "activity": ACT_WORK},   # night observations
	]


func dialogue_tree(_npc: Node) -> String:
	return "scientist_default"


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Don't touch the array.",
		"Have you ever flipped and felt the ground disagree?",
		"Four planes. Four. Not three, whatever the Protectorate taught you.",
		"I've a theory and I need someone expendable. No offence.",
		"The rock doesn't move. You do. That's the whole trick.",
	])


static func random_tech(rng: RandomNumberGenerator) -> StringName:
	return TECH_POOL[rng.randi_range(0, TECH_POOL.size() - 1)]
