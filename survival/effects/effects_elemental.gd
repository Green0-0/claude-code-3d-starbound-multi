## Elemental and wound status effects — the ones weapons, monsters and hazards
## inflict. Registered into `Status` at boot by `SrvEffectLibrary`.
##
## Design rules kept consistent across the whole family:
##   * every damage-over-time effect names its element so armour resistances
##     apply through the normal `combat/damage.gd` pipeline;
##   * fire and ice cancel each other, wetness beats fire and feeds electricity;
##   * anything that should be *treatable* declares a `curable()` keyword so
##     `survival/medical.gd` can clear it with the right item.
class_name SrvEffectsElemental
extends RefCounted


static func register_all(reg) -> void:
	_fire(reg)
	_cold(reg)
	_shock(reg)
	_poison(reg)
	_wounds(reg)
	_grime(reg)


# ---------------------------------------------------------------------- fire
static func _fire(reg) -> void:
	reg.define(&"burning", "Burning") \
		.describe("On fire. Take fire damage until it burns out — or get wet.") \
		.debuff().lasts(6.0).ticks(0.5).deals(3.0, Const.ELEM_FIRE) \
		.stacking(SrvStatusEffect.Stack.REFRESH, 1) \
		.modifies("resist_ice", 0.75) \
		.visual(Color(1.0, 0.45, 0.12, 0.55), &"flame", 14.0).glows(4.0) \
		.sounds(&"ignite").clears([&"frozen", &"chilled", &"wet"]) \
		.curable([&"cooling"])

	reg.define(&"overheating", "Overheating") \
		.describe("The air itself is cooking you. Find shade, water or cooling gear.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(1.0) \
		.deals(2.0, Const.ELEM_FIRE) \
		.modifies_all({"move_speed": 0.85, "regen": 0.0, "thirst_rate": 2.2}) \
		.visual(Color(1.0, 0.62, 0.3, 0.30), &"heat_haze", 3.0) \
		.clears([&"freezing"]).curable([&"cooling"])


# ---------------------------------------------------------------------- cold
static func _cold(reg) -> void:
	reg.define(&"frozen", "Frozen") \
		.describe("Encased in ice. You cannot move until it cracks.") \
		.debuff().lasts(2.5).ticks(0.5).deals(1.0, Const.ELEM_ICE) \
		.modifies_all({"move_speed": 0.0, "jump_speed": 0.0, "attack_speed": 0.0,
			"mining_speed": 0.25, "damage_taken": 1.25}) \
		.visual(Color(0.62, 0.86, 1.0, 0.6), &"frost", 6.0) \
		.sounds(&"freeze").clears([&"burning"]).curable([&"warmth"])

	reg.define(&"chilled", "Chilled") \
		.describe("Cold-slowed. Movement and attacks are sluggish.") \
		.debuff().lasts(6.0).stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"move_speed": 0.82, "attack_speed": 0.9, "jump_speed": 0.94}) \
		.visual(Color(0.66, 0.84, 0.98, 0.28), &"frost", 2.0) \
		.clears([&"burning"]).curable([&"warmth"])

	reg.define(&"freezing", "Freezing") \
		.describe("Killing cold. Wear insulated armour or stand by a fire.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(1.0) \
		.deals(2.5, Const.ELEM_ICE) \
		.modifies_all({"move_speed": 0.8, "regen": 0.0, "hunger_rate": 1.6}) \
		.visual(Color(0.55, 0.78, 1.0, 0.35), &"frost", 4.0) \
		.clears([&"overheating"]).curable([&"warmth"])


# ------------------------------------------------------------------ electric
static func _shock(reg) -> void:
	reg.define(&"shocked", "Shocked") \
		.describe("Arcing with current. Nerves misfire and damage lands harder.") \
		.debuff().lasts(4.0).ticks(0.4).deals(1.6, Const.ELEM_ELECTRIC) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"damage_taken": 1.12, "attack_speed": 0.88, "energy_regen": 0.0}) \
		.visual(Color(0.55, 0.85, 1.0, 0.45), &"spark", 12.0).glows(3.0) \
		.sounds(&"zap")


# -------------------------------------------------------------------- poison
static func _poison(reg) -> void:
	reg.define(&"poisoned", "Poisoned") \
		.describe("Venom in the blood. Damage over time and no natural healing.") \
		.debuff().lasts(10.0).ticks(1.0).deals(2.0, Const.ELEM_POISON) \
		.stacking(SrvStatusEffect.Stack.STACK, 5) \
		.modifies_all({"regen": 0.0, "move_speed": 0.95}) \
		.visual(Color(0.45, 0.85, 0.30, 0.42), &"poison_bubble", 5.0) \
		.curable([&"antidote", &"cure"])

	reg.define(&"irradiated", "Irradiated") \
		.describe("Absorbing a dangerous dose. Shielded armour or an EPP stops it.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(1.0) \
		.deals(1.8, Const.ELEM_COSMIC) \
		.stacking(SrvStatusEffect.Stack.STACK, 4) \
		.modifies_all({"regen": 0.0, "max_health": 0.94, "luck": 0.9}) \
		.visual(Color(0.62, 1.0, 0.35, 0.36), &"rad_mote", 6.0).glows(2.0) \
		.curable([&"antirad", &"cure"])

	reg.define(&"corroded", "Corroded") \
		.describe("Acid is eating through your armour.") \
		.debuff().lasts(12.0).ticks(1.0).deals(0.8, Const.ELEM_POISON) \
		.stacking(SrvStatusEffect.Stack.STACK, 4) \
		.modifies_all({"defense": 0.85, "damage_taken": 1.06}) \
		.visual(Color(0.72, 0.86, 0.28, 0.34), &"acid_drip", 4.0) \
		.curable([&"antidote", &"cure"])


# -------------------------------------------------------------------- wounds
static func _wounds(reg) -> void:
	reg.define(&"bleeding", "Bleeding") \
		.describe("An open wound. Bandage it before it goes septic.") \
		.debuff(&"medical").lasts(15.0).ticks(1.0).deals(1.5, Const.ELEM_PHYSICAL) \
		.stacking(SrvStatusEffect.Stack.STACK, 5) \
		.modifies_all({"regen": 0.35, "max_health": 0.98}) \
		.visual(Color(0.72, 0.10, 0.12, 0.40), &"blood_drop", 6.0) \
		.curable([&"bandage", &"cure"])

	reg.define(&"infected", "Infected") \
		.describe("The wound turned. Only real medicine clears an infection.") \
		.debuff(&"medical").lasts(SrvStatusEffect.PERMANENT).ticks(2.0) \
		.deals(1.2, Const.ELEM_POISON) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"regen": 0.0, "max_health": 0.9, "damage_dealt": 0.9,
			"fatigue_rate": 1.5}) \
		.visual(Color(0.55, 0.62, 0.35, 0.38), &"poison_bubble", 2.0) \
		.curable([&"cure"])

	reg.define(&"fortified", "Fortified") \
		.describe("Braced against the next blow.") \
		.lasts(8.0).modifies_all({"damage_taken": 0.75, "knockback_taken": 0.5,
			"defense": 1.25}) \
		.visual(Color(0.85, 0.78, 0.45, 0.30), &"shield_glint", 2.0)


# --------------------------------------------------------------------- grime
static func _grime(reg) -> void:
	reg.define(&"wet", "Soaked") \
		.describe("Dripping. Fire slides off you; lightning does not.") \
		.debuff(&"environment").lasts(20.0) \
		.modifies_all({"resist_fire": 0.6, "resist_electric": 1.45, "friction": 0.9}) \
		.visual(Color(0.42, 0.66, 0.95, 0.25), &"water_drip", 3.0) \
		.clears([&"burning"])

	reg.define(&"slimed", "Slimed") \
		.describe("Coated in something that does not want to let go.") \
		.debuff().lasts(8.0) \
		.modifies_all({"move_speed": 0.7, "jump_speed": 0.8}) \
		.visual(Color(0.55, 0.78, 0.42, 0.35), &"slime_drip", 3.0)

	reg.define(&"blinded", "Blinded") \
		.describe("You can barely see through it.") \
		.debuff(&"environment").lasts(6.0) \
		.modifies_all({"crit_chance": 0.5, "damage_dealt": 0.9, "light_radius": 0.5}) \
		.visual(Color(0.35, 0.33, 0.30, 0.45), &"dust", 2.0)
