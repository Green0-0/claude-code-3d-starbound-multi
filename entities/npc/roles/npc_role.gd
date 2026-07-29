## Base class for what an NPC *does*. A role is a stateless strategy object —
## one shared instance per role id — so it never holds per-NPC data; anything
## mutable lives on the [NpcBase] it is handed.
##
## Subclasses live beside this file and are registered in `roles.gd`.
class_name NpcRole
extends RefCounted

## Schedule activity vocabulary. `sleep` and `work` send the NPC to their bed /
## workplace; `wander` and `socialise` keep them near home.
const ACT_SLEEP: StringName = &"sleep"
const ACT_WORK: StringName = &"work"
const ACT_WANDER: StringName = &"wander"
const ACT_SOCIALISE: StringName = &"socialise"
const ACT_IDLE: StringName = &"idle"


func id() -> StringName:
	return &"villager"


func display() -> String:
	return "Villager"


## Applied once, when the NPC is built. Set stats, faction, shop stock here.
func configure(_npc: Node) -> void:
	pass


## Daily routine as `[{from, to, activity}]` in [member Game.day_fraction] units.
## Entries are scanned in order; the first whose window contains `now` wins, so
## overlapping entries are allowed and earlier ones take priority.
func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.88, "to": 0.26, "activity": ACT_SLEEP},
		{"from": 0.26, "to": 0.36, "activity": ACT_WANDER},
		{"from": 0.36, "to": 0.62, "activity": ACT_WORK},
		{"from": 0.62, "to": 0.74, "activity": ACT_SOCIALISE},
		{"from": 0.74, "to": 0.88, "activity": ACT_WANDER},
	]


## Dialogue tree id for this role; the NPC may override it.
func dialogue_tree(_npc: Node) -> String:
	return "villager_default"


## Idle barks shown in the greeting bubble when the player walks past.
func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Morning.", "Mind the mud.", "You're not from around here.",
		"Weather's holding.", "Careful past the treeline.",
	])


## Called on interact *before* dialogue opens. Return true to suppress dialogue
## (a role that only opens a shop, say).
func on_interact(_npc: Node, _player: Node) -> bool:
	return false


## Per-frame hook for role behaviour that the generic AI does not cover.
func tick(_npc: Node, _delta: float) -> void:
	pass


## Can this role be recruited onto the ship?
func recruitable() -> bool:
	return false


## Does this role stand and fight instead of fleeing?
func defends() -> bool:
	return false


## Multiplier on the NPC's base health.
func toughness() -> float:
	return 1.0
