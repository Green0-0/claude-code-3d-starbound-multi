## Survival-loop status effects: the consequences of hunger, thirst, fatigue,
## suffocation, pressure — and the rewards for managing them.
##
## `survival/needs.gd` and `survival/environment.gd` own the *meters*; this file
## owns what the meters do to you once they run out. Keeping the two apart means
## a modder can retune the pain without touching the simulation.
class_name SrvEffectsSurvival
extends RefCounted


static func register_all(reg) -> void:
	_air(reg)
	_food(reg)
	_rest(reg)
	_rewards(reg)


# ----------------------------------------------------------------------- air
static func _air(reg) -> void:
	reg.define(&"drowning", "Drowning") \
		.describe("Out of breath underwater. Surface, now.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(1.0) \
		.deals(6.0, Const.ELEM_PHYSICAL) \
		.modifies_all({"move_speed": 0.85, "regen": 0.0}) \
		.visual(Color(0.30, 0.52, 0.85, 0.45), &"bubble", 8.0) \
		.sounds(&"drown")

	reg.define(&"suffocating", "Suffocating") \
		.describe("Nothing to breathe. An EPP or a breathing tonic keeps you alive.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(1.0) \
		.deals(5.0, Const.ELEM_PHYSICAL) \
		.modifies_all({"move_speed": 0.8, "damage_dealt": 0.8, "regen": 0.0}) \
		.visual(Color(0.55, 0.55, 0.70, 0.45), &"gasp", 4.0)

	reg.define(&"breathing", "Breathing") \
		.describe("You can breathe anywhere — underwater, vacuum, poison fog.") \
		.in_category(&"environment").lasts(180.0) \
		.modifies("breath_rate", 0.0) \
		.visual(Color(0.55, 0.95, 0.90, 0.22), &"bubble", 1.0) \
		.icon(Color(0.5, 0.95, 0.9), &"circle")

	reg.define(&"crushing", "Crushing Pressure") \
		.describe("The deep is squeezing you. Pressure-rated gear required.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(1.0) \
		.deals(4.0, Const.ELEM_PHYSICAL) \
		.stacking(SrvStatusEffect.Stack.STACK, 3) \
		.modifies_all({"move_speed": 0.75, "jump_speed": 0.8, "regen": 0.0}) \
		.visual(Color(0.16, 0.28, 0.48, 0.45), &"pressure", 3.0)


# ---------------------------------------------------------------------- food
static func _food(reg) -> void:
	reg.define(&"starving", "Starving") \
		.describe("Running on nothing. Strength and healing are gone.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(2.0) \
		.deals(2.0, Const.ELEM_PHYSICAL) \
		.modifies_all({"damage_dealt": 0.6, "move_speed": 0.85, "regen": 0.0,
			"mining_speed": 0.75, "jump_speed": 0.9}) \
		.visual(Color(0.55, 0.48, 0.32, 0.35), &"", 0.0) \
		.icon(Color(0.75, 0.55, 0.25), &"drop")

	reg.define(&"peckish", "Peckish") \
		.describe("Hungry enough to notice.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT) \
		.modifies_all({"regen": 0.5, "damage_dealt": 0.92}) \
		.icon(Color(0.8, 0.68, 0.35), &"drop")

	reg.define(&"dehydrated", "Dehydrated") \
		.describe("Cracked lips, swimming head. Drink something.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT).ticks(2.0) \
		.deals(1.5, Const.ELEM_PHYSICAL) \
		.modifies_all({"move_speed": 0.8, "mining_speed": 0.7, "regen": 0.0,
			"crit_chance": 0.6}) \
		.visual(Color(0.72, 0.62, 0.35, 0.28), &"", 0.0) \
		.icon(Color(0.4, 0.7, 0.95), &"drop")


# ---------------------------------------------------------------------- rest
static func _rest(reg) -> void:
	reg.define(&"drowsy", "Drowsy") \
		.describe("You have been awake too long.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT) \
		.modifies_all({"crit_chance": 0.75, "mining_speed": 0.9, "energy_regen": 0.8}) \
		.visual(Color(0.32, 0.30, 0.42, 0.18), &"", 0.0) \
		.icon(Color(0.55, 0.5, 0.75), &"circle")

	reg.define(&"exhausted", "Exhausted") \
		.describe("Dead on your feet. Sleep in a bed before something eats you.") \
		.debuff(&"environment").lasts(SrvStatusEffect.PERMANENT) \
		.modifies_all({"move_speed": 0.72, "jump_speed": 0.85, "damage_dealt": 0.75,
			"mining_speed": 0.65, "energy_regen": 0.4, "crit_chance": 0.5}) \
		.visual(Color(0.26, 0.24, 0.36, 0.32), &"", 0.0) \
		.icon(Color(0.45, 0.40, 0.68), &"circle")


# ------------------------------------------------------------------- rewards
static func _rewards(reg) -> void:
	reg.define(&"well_fed", "Well Fed") \
		.describe("A full stomach. Wounds close faster.") \
		.lasts(240.0).ticks(2.0).restores(1.0) \
		.modifies_all({"regen": 1.6, "hunger_rate": 0.85, "max_health": 1.05}) \
		.visual(Color(0.95, 0.78, 0.35, 0.16), &"", 0.0) \
		.icon(Color(0.95, 0.72, 0.30), &"heart")

	reg.define(&"feast", "Feasted") \
		.describe("A perfect meal. Everything is easier for a while.") \
		.lasts(420.0).ticks(2.0).restores(2.0) \
		.modifies_all({"regen": 2.2, "max_health": 1.12, "damage_dealt": 1.15,
			"defense": 1.15, "move_speed": 1.06, "hunger_rate": 0.6, "luck": 1.2}) \
		.visual(Color(1.0, 0.85, 0.45, 0.24), &"sparkle", 3.0) \
		.icon(Color(1.0, 0.82, 0.35), &"star")

	# Applied by campfires, stoves and heaters (`objects/`) to anything standing
	# close by. It cancels the killing cold outright and warms the body reading,
	# which is what makes a fire worth building on an ice world.
	reg.define(&"warm", "Warmed") \
		.describe("A heat source nearby is keeping the cold off.") \
		.in_category(&"environment").lasts(8.0) \
		.modifies_all({"resist_ice": 0.7, "hunger_rate": 0.9}) \
		.visual(Color(1.0, 0.72, 0.38, 0.16), &"", 0.0) \
		.icon(Color(1.0, 0.72, 0.38), &"circle") \
		.clears([&"freezing", &"chilled"]).curable([&"warmth"])

	reg.define(&"rested", "Rested") \
		.describe("You actually slept. Stamina and focus are back.") \
		.lasts(360.0) \
		.modifies_all({"energy_regen": 1.4, "crit_chance": 1.15, "fatigue_rate": 0.7,
			"mining_speed": 1.1}) \
		.visual(Color(0.75, 0.85, 1.0, 0.14), &"", 0.0) \
		.icon(Color(0.7, 0.85, 1.0), &"circle")
