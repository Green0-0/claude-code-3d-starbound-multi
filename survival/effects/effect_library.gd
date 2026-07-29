## The one place that knows every status effect id in the game.
##
## `Status._ready()` calls [method register_all] before anything can apply an
## effect. Splitting the table across four files keeps each readable; this file
## is the index, and [constant ALL_IDS] is the authoritative vocabulary other
## agents should key against.
class_name SrvEffectLibrary
extends RefCounted

## Every registered effect id, grouped the way the HUD groups them.
## Kept as a plain constant so other modules can validate ids at load time
## without instantiating anything.
const ALL_IDS := {
	"elemental": [
		"burning", "overheating", "frozen", "chilled", "freezing", "shocked",
		"poisoned", "irradiated", "corroded", "bleeding", "infected",
		"fortified", "wet", "slimed", "blinded",
	],
	"survival": [
		"drowning", "suffocating", "breathing", "crushing", "starving",
		"peckish", "dehydrated", "drowsy", "exhausted", "well_fed", "feast",
		"warm", "rested",
	],
	"buffs": [
		"regeneration", "haste", "slow", "mining_haste", "energised",
		"strength", "weakness", "defense_up", "defense_down", "lucky",
		"fire_resistance", "ice_resistance", "electric_resistance",
		"poison_resistance", "radiation_shielding", "night_vision", "glowing",
		"invisible", "gravity_reduced", "levitation",
	],
	"signature": ["plane_locked", "phase_sight"],
}


static func register_all(reg) -> void:
	SrvEffectsElemental.register_all(reg)
	SrvEffectsSurvival.register_all(reg)
	SrvEffectsBuffs.register_all(reg)
	SrvEffectsSignature.register_all(reg)


## Flat list of every id, for validation and debug UIs.
static func flat_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for group: String in ALL_IDS:
		for i in ALL_IDS[group]:
			out.append(StringName(i))
	return out
