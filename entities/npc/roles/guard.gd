## Stands watch over the village. Guards never flee: they charge the nearest
## hostile inside their patrol radius, and they patrol in plane space, so a flip
## does not scramble their beat.
##
## They also carry the village's opinion of you: attacking a villager makes every
## guard in that village hostile to the player.
class_name NpcRoleGuard
extends NpcRole

## How far from the defended home position a guard will chase.
const PATROL_RADIUS := 22.0
## Melee reach, in plane-space metres.
const REACH := 1.9
const SWING_COOLDOWN := 0.85
const DAMAGE := 16.0


func id() -> StringName:
	return &"guard"


func display() -> String:
	return "Guard"


func configure(npc: Node) -> void:
	npc.set(&"max_health", 180.0)
	npc.set(&"move_speed", 5.2)
	npc.set(&"defend_radius", PATROL_RADIUS)
	npc.set(&"flees", false)
	npc.set(&"can_offer_quests", true)
	npc.set(&"melee_damage", DAMAGE)
	npc.set(&"melee_reach", REACH)
	npc.set(&"swing_cooldown", SWING_COOLDOWN)


## Guards work in shifts: half of them are on the wall at night. The NPC's own
## deterministic seed decides which half, in [method NpcBase.build_schedule].
func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.86, "to": 0.25, "activity": ACT_WORK},
		{"from": 0.25, "to": 0.40, "activity": ACT_SLEEP},
		{"from": 0.40, "to": 0.52, "activity": ACT_SOCIALISE},
		{"from": 0.52, "to": 0.86, "activity": ACT_WORK},
	]


func dialogue_tree(_npc: Node) -> String:
	return "guard_default"


func defends() -> bool:
	return true


func toughness() -> float:
	return 1.9


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Move along.",
		"Keep your weapon holstered inside the palisade.",
		"Anything comes over that wall, it goes back over in pieces.",
		"You want trouble, the woods are that way.",
		"Quiet shift. Long may it last.",
	])


## The swing itself lives on [NpcBase]; the role only supplies the shouting.
func tick(npc: Node, _delta: float) -> void:
	var target: Variant = npc.get(&"threat_target")
	if target == null or float(npc.get(&"attack_cooldown")) < SWING_COOLDOWN - 0.05:
		return
	if randf() < 0.2 and npc.has_method(&"say"):
		npc.call(&"say", ["Back!", "For the wall!", "Down you go.", "Hold!"][randi() % 4], 1.4)
