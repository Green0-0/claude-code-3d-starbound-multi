## Buffs, debuffs and elemental resistances — the effects food, drugs, techs,
## armour set bonuses and monster attacks hand out.
##
## Resistances are expressed as `resist_<element>` multipliers on *incoming*
## damage, because that is exactly how `combat/damage.gd` consumes them:
## `amount *= Status.modifier("resist_" + element, target)`. A value of 0.5
## therefore halves that element; 1.5 makes you vulnerable to it.
class_name SrvEffectsBuffs
extends RefCounted


static func register_all(reg) -> void:
	_body(reg)
	_combat(reg)
	_resistances(reg)
	_utility(reg)


# ---------------------------------------------------------------------- body
static func _body(reg) -> void:
	reg.define(&"regeneration", "Regeneration") \
		.describe("Flesh knitting itself back together.") \
		.lasts(20.0).ticks(1.0).restores(2.5) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies("regen", 1.5) \
		.visual(Color(0.45, 0.95, 0.55, 0.25), &"heal_mote", 6.0) \
		.icon(Color(0.4, 0.95, 0.5), &"heart")

	reg.define(&"haste", "Haste") \
		.describe("Everything about you moves faster.") \
		.lasts(30.0) \
		.stacking(SrvStatusEffect.Stack.STACK, 2) \
		.modifies_all({"move_speed": 1.28, "attack_speed": 1.18, "jump_speed": 1.06}) \
		.visual(Color(0.95, 0.85, 0.35, 0.22), &"speed_line", 8.0) \
		.icon(Color(0.95, 0.85, 0.3), &"arrow")

	reg.define(&"slow", "Slowed") \
		.describe("Every step is through treacle.") \
		.debuff().lasts(8.0) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"move_speed": 0.72, "attack_speed": 0.85, "jump_speed": 0.9}) \
		.visual(Color(0.45, 0.42, 0.52, 0.28), &"", 0.0) \
		.icon(Color(0.5, 0.48, 0.6), &"arrow")

	reg.define(&"mining_haste", "Quarryhand") \
		.describe("Rock gives way like wet sand.") \
		.lasts(120.0) \
		.modifies_all({"mining_speed": 1.45, "energy_regen": 1.1}) \
		.visual(Color(0.8, 0.7, 0.45, 0.16), &"", 0.0) \
		.icon(Color(0.85, 0.7, 0.4), &"square")

	reg.define(&"energised", "Energised") \
		.describe("Your energy pool refills noticeably faster.") \
		.lasts(120.0) \
		.modifies_all({"energy_regen": 1.6, "attack_speed": 1.05}) \
		.visual(Color(0.4, 0.9, 1.0, 0.20), &"spark", 3.0) \
		.icon(Color(0.4, 0.9, 1.0), &"bolt")


# -------------------------------------------------------------------- combat
static func _combat(reg) -> void:
	reg.define(&"strength", "Strength") \
		.describe("Blows land noticeably harder.") \
		.lasts(60.0) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"damage_dealt": 1.25, "knockback_taken": 0.9}) \
		.visual(Color(0.95, 0.35, 0.25, 0.22), &"rage", 3.0) \
		.icon(Color(0.95, 0.35, 0.25), &"sword")

	reg.define(&"weakness", "Weakened") \
		.describe("You cannot put any force behind a swing.") \
		.debuff().lasts(15.0) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"damage_dealt": 0.72, "knockback_taken": 1.2}) \
		.visual(Color(0.45, 0.35, 0.45, 0.25), &"", 0.0) \
		.icon(Color(0.5, 0.4, 0.5), &"sword")

	reg.define(&"defense_up", "Ironhide") \
		.describe("Armour rating raised.") \
		.lasts(60.0) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"defense": 1.35, "damage_taken": 0.92, "knockback_taken": 0.8}) \
		.visual(Color(0.65, 0.7, 0.85, 0.22), &"shield_glint", 2.0) \
		.icon(Color(0.65, 0.72, 0.88), &"shield")

	reg.define(&"defense_down", "Sundered") \
		.describe("Your guard has been broken open.") \
		.debuff().lasts(12.0) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"defense": 0.7, "damage_taken": 1.12}) \
		.visual(Color(0.6, 0.3, 0.3, 0.25), &"", 0.0) \
		.icon(Color(0.7, 0.35, 0.35), &"shield")

	reg.define(&"lucky", "Lucky") \
		.describe("Better drops, better crits. Enjoy it while it lasts.") \
		.lasts(180.0) \
		.modifies_all({"luck": 1.35, "crit_chance": 1.2}) \
		.visual(Color(0.5, 0.95, 0.6, 0.18), &"sparkle", 2.0) \
		.icon(Color(0.5, 0.95, 0.6), &"star")


# --------------------------------------------------------------- resistances
static func _resist(reg, id: StringName, display: String, element: String,
		col: Color, blurb: String) -> SrvStatusEffect:
	var e: SrvStatusEffect = reg.define(id, display)
	e.describe(blurb).lasts(180.0)
	e.modifies("resist_" + element, 0.45)
	e.visual(Color(col.r, col.g, col.b, 0.18), &"", 0.0)
	e.icon(col, &"shield")
	return e


static func _resistances(reg) -> void:
	_resist(reg, &"fire_resistance", "Fire Resistance", Const.ELEM_FIRE,
		Color(1.0, 0.5, 0.2), "Flame and lava do far less to you.") \
		.modifies("resist_fire", 0.35).clears([&"burning"])
	_resist(reg, &"ice_resistance", "Ice Resistance", Const.ELEM_ICE,
		Color(0.6, 0.85, 1.0), "The cold cannot get its hooks in.") \
		.clears([&"frozen"])
	_resist(reg, &"electric_resistance", "Shock Resistance", Const.ELEM_ELECTRIC,
		Color(0.55, 0.85, 1.0), "Current earths out harmlessly.")
	_resist(reg, &"poison_resistance", "Poison Resistance", Const.ELEM_POISON,
		Color(0.5, 0.9, 0.35), "Toxins metabolise before they bite.") \
		.clears([&"poisoned"])
	_resist(reg, &"radiation_shielding", "Radiation Shielding", Const.ELEM_COSMIC,
		Color(0.65, 1.0, 0.4), "Hard radiation passes straight through you.") \
		.clears([&"irradiated"]).modifies("radiation_rate", 0.0)


# ------------------------------------------------------------------- utility
static func _utility(reg) -> void:
	reg.define(&"night_vision", "Night Vision") \
		.describe("Caves and midnight read as clearly as noon.") \
		.lasts(180.0) \
		.modifies("light_radius", 2.2) \
		.visual(Color(0.55, 0.95, 0.75, 0.12), &"", 0.0) \
		.icon(Color(0.55, 0.95, 0.75), &"eye")

	reg.define(&"glowing", "Glowing") \
		.describe("You are a walking lantern — and very easy to spot.") \
		.lasts(300.0).glows(9.0) \
		.modifies("light_radius", 1.8) \
		.visual(Color(1.0, 0.95, 0.7, 0.30), &"glow_mote", 3.0) \
		.icon(Color(1.0, 0.95, 0.7), &"circle")

	reg.define(&"invisible", "Invisible") \
		.describe("Monsters lose track of you — until you swing at one.") \
		.lasts(30.0) \
		.modifies_all({"aggro_range": 0.25, "crit_chance": 1.3}) \
		.visual(Color(0.75, 0.80, 0.95, 0.55), &"shimmer", 2.0) \
		.icon(Color(0.8, 0.85, 0.95), &"eye")

	reg.define(&"gravity_reduced", "Low Gravity") \
		.describe("You fall slowly and jump like the moon owes you a favour.") \
		.lasts(60.0) \
		.modifies_all({"gravity": 0.45, "jump_speed": 1.3, "fall_damage": 0.3}) \
		.visual(Color(0.7, 0.7, 1.0, 0.20), &"float_mote", 3.0) \
		.icon(Color(0.7, 0.72, 1.0), &"arrow")

	reg.define(&"levitation", "Levitation") \
		.describe("Gravity has been talked out of it entirely.") \
		.lasts(12.0) \
		.modifies_all({"gravity": -0.18, "fall_damage": 0.0, "move_speed": 0.9}) \
		.visual(Color(0.85, 0.75, 1.0, 0.30), &"float_mote", 6.0) \
		.icon(Color(0.85, 0.75, 1.0), &"arrow")
