## A villager who can be talked into signing on. Once hired they follow the
## player everywhere — across the surface, across depth layers when you shift,
## and across planets when you travel (see [NpcCrew]).
##
## Each recruit has a skill that grants a passive while they are aboard. The
## bonus is applied through whatever systems exist; unknown ones no-op.
class_name NpcRoleCrew
extends NpcRole

## Standing required before they will consider it.
const HIRE_STANDING := 25.0
## Signing bonus the player pays.
const SIGNING_FEE := 250

const SKILL_BLURB := {
	&"engineer": "keeps the drive from rattling itself apart",
	&"medic": "patches you up between planets",
	&"gunner": "mans the ship's guns, badly but loudly",
	&"chemist": "brews things that should not be brewed",
	&"janitor": "the most important job on any ship",
	&"navigator": "reads star charts upside down and is never wrong",
	&"tailor": "can make anything, provided it is a coat",
	&"mechanic": "talks to machines and, worryingly, is answered",
	&"cook": "turns alien meat into something edible",
	&"surveyor": "spots a seam of ore through solid rock",
}


func id() -> StringName:
	return &"crew"


func display() -> String:
	return "Recruit"


func configure(npc: Node) -> void:
	npc.set(&"max_health", 110.0)
	npc.set(&"move_speed", 5.6)
	npc.set(&"can_offer_quests", true)
	npc.set(&"melee_damage", 11.0)


func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.90, "to": 0.27, "activity": ACT_SLEEP},
		{"from": 0.27, "to": 0.45, "activity": ACT_WANDER},
		{"from": 0.45, "to": 0.66, "activity": ACT_WORK},
		{"from": 0.66, "to": 0.90, "activity": ACT_SOCIALISE},
	]


func dialogue_tree(_npc: Node) -> String:
	return "crew_default"


func recruitable() -> bool:
	return true


func toughness() -> float:
	return 1.25


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"This village is very... flat.",
		"I've never been off-world. Not once.",
		"You came down in that ship, didn't you?",
		"Is there room aboard? Hypothetically.",
		"I can fix anything with a lid on it.",
	])


static func blurb(skill: StringName) -> String:
	return String(SKILL_BLURB.get(skill, "makes themselves useful"))


static func hire_fee(npc_id: StringName) -> int:
	return maxi(50, int(float(SIGNING_FEE) * NpcReputation.price_multiplier(npc_id)))


## Gate used by the dialogue tree so the offer only appears when it can succeed.
static func can_hire(npc: Node) -> bool:
	if npc == null or not NpcCrew.has_room():
		return false
	return NpcReputation.of_npc(StringName(npc.get("npc_id"))) >= HIRE_STANDING
