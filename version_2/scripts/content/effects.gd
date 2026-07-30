class_name EffectLib
extends RefCounted

## The status effect library.
##
## Effects are pure data: a per-second damage or heal, a set of multipliers, and
## a colour for the HUD strip. `survival.gd` applies them; nothing here has any
## behaviour of its own, which is what makes them safe to stack.
##
## `cure_*` are not effects at all but instructions — applying one strips a
## family of debuffs and expires immediately. That keeps every antidote in the
## game a one-line item definition.


class Def extends RefCounted:
	var id: StringName = &""
	var display := ""
	var description := ""
	var color := Color(0.8, 0.8, 0.8)
	var debuff := false
	var dps := 0.0                       ## damage per second
	var element: StringName = Blocks.ELEM_PHYSICAL
	var heal_ps := 0.0
	var energy_ps := 0.0
	var move_mult := 1.0
	var mine_mult := 1.0
	var damage_mult := 1.0               ## outgoing
	var taken_mult := 1.0                ## incoming
	var light := 0.0
	var max_stacks := 1
	var cures: Array[StringName] = []


static var defs: Array[Def] = []
static var by_id := {}
static var _booted := false


static func boot() -> void:
	if _booted:
		return
	_booted = true
	_buffs()
	_elemental()
	_survival()
	_cures()


static func define(id: StringName, display: String) -> Def:
	var d := Def.new()
	d.id = id
	d.display = display
	defs.append(d)
	by_id[id] = d
	return d


static func get_def(id: StringName) -> Def:
	return by_id.get(id)


static func has(id: StringName) -> bool:
	return by_id.has(id)


# ------------------------------------------------------------------- buffs
static func _buffs() -> void:
	var d := define(&"regeneration", "Regeneration")
	d.color = Color(0.44, 0.92, 0.52)
	d.heal_ps = 2.2
	d.description = "Closing up, steadily."

	d = define(&"haste", "Haste")
	d.color = Color(0.98, 0.82, 0.34)
	d.move_mult = 1.28
	d.description = "Everything is happening slightly faster than you are used to."

	d = define(&"mining_haste", "Quarryhand")
	d.color = Color(0.86, 0.72, 0.40)
	d.mine_mult = 1.5
	d.description = "Rock comes apart under the tool like it wants to."

	d = define(&"energised", "Energised")
	d.color = Color(0.52, 0.92, 1.0)
	d.energy_ps = 4.0
	d.description = "Energy comes back faster than you can spend it. Nearly."

	d = define(&"strength", "Strength")
	d.color = Color(0.94, 0.42, 0.32)
	d.damage_mult = 1.35
	d.description = "Every swing lands like the one before it should have."

	d = define(&"defense_up", "Ironhide")
	d.color = Color(0.66, 0.72, 0.82)
	d.taken_mult = 0.75
	d.description = "Blows land, and matter less."

	d = define(&"fortified", "Fortified")
	d.color = Color(0.82, 0.86, 0.94)
	d.taken_mult = 0.6
	d.description = "Braced against everything at once."

	d = define(&"lucky", "Lucky")
	d.color = Color(0.94, 0.86, 0.42)
	d.description = "Loot rolls are kinder while this lasts."

	d = define(&"night_vision", "Night Vision")
	d.color = Color(0.56, 0.94, 0.56)
	d.light = 12.0
	d.description = "The dark stops being an obstacle."

	d = define(&"glowing", "Glowing")
	d.color = Color(0.86, 0.98, 0.62)
	d.light = 6.0
	d.description = "You are the light source. Everything can see you."

	d = define(&"well_fed", "Well Fed")
	d.color = Color(0.86, 0.66, 0.36)
	d.heal_ps = 0.4
	d.description = "A proper meal, still doing its work."

	d = define(&"feast", "Feasted")
	d.color = Color(0.96, 0.74, 0.34)
	d.heal_ps = 1.0
	d.taken_mult = 0.85
	d.damage_mult = 1.15
	d.description = "That was a real meal, and you can feel it."

	d = define(&"warm", "Warmed")
	d.color = Color(0.98, 0.62, 0.30)
	d.description = "Insulated against the cold for a while."

	d = define(&"rested", "Rested")
	d.color = Color(0.72, 0.82, 0.96)
	d.energy_ps = 1.5
	d.description = "Slept properly. It shows."

	d = define(&"fire_resistance", "Fire Resistance")
	d.color = Color(0.98, 0.54, 0.24)
	d.description = "Heat washes over rather than through."

	d = define(&"phase_sight", "Phase Sight")
	d.color = Color(0.78, 0.56, 1.0)
	d.description = "Everything the cutaway is hiding is outlined for you."


# --------------------------------------------------------------- elemental
static func _elemental() -> void:
	var d := define(&"burning", "Burning")
	d.color = Color(1.0, 0.48, 0.16)
	d.debuff = true
	d.dps = 4.0
	d.element = Blocks.ELEM_FIRE
	d.max_stacks = 3
	d.light = 3.0
	d.description = "On fire. Water helps; panic does not."

	d = define(&"chilled", "Chilled")
	d.color = Color(0.62, 0.86, 1.0)
	d.debuff = true
	d.move_mult = 0.75
	d.max_stacks = 3
	d.description = "Slow, stiff and getting slower."

	d = define(&"frozen", "Frozen")
	d.color = Color(0.72, 0.92, 1.0)
	d.debuff = true
	d.move_mult = 0.25
	d.taken_mult = 1.3
	d.description = "Barely able to move, and easy to hit."

	d = define(&"shocked", "Shocked")
	d.color = Color(0.72, 0.86, 1.0)
	d.debuff = true
	d.dps = 3.0
	d.element = Blocks.ELEM_ELECTRIC
	d.energy_ps = -3.0
	d.description = "Current is going somewhere it should not be."

	d = define(&"poisoned", "Poisoned")
	d.color = Color(0.52, 0.86, 0.34)
	d.debuff = true
	d.dps = 2.0
	d.element = Blocks.ELEM_POISON
	d.max_stacks = 5
	d.description = "It will not kill you quickly. That is the problem."

	d = define(&"irradiated", "Irradiated")
	d.color = Color(0.66, 0.98, 0.36)
	d.debuff = true
	d.dps = 2.6
	d.element = Blocks.ELEM_POISON
	d.heal_ps = -0.5
	d.description = "The dosimeter is not green any more."

	d = define(&"bleeding", "Bleeding")
	d.color = Color(0.86, 0.20, 0.24)
	d.debuff = true
	d.dps = 3.2
	d.max_stacks = 4
	d.description = "Losing more than you can afford to."

	d = define(&"weakness", "Weakened")
	d.color = Color(0.62, 0.56, 0.62)
	d.debuff = true
	d.damage_mult = 0.65
	d.description = "Nothing you hit seems to notice."

	d = define(&"slow", "Slowed")
	d.color = Color(0.56, 0.60, 0.68)
	d.debuff = true
	d.move_mult = 0.6
	d.description = "Wading, on dry land."

	d = define(&"blinded", "Blinded")
	d.color = Color(0.30, 0.30, 0.34)
	d.debuff = true
	d.light = -6.0
	d.description = "You cannot see past your own hands."


# ---------------------------------------------------------------- survival
static func _survival() -> void:
	var d := define(&"peckish", "Peckish")
	d.color = Color(0.78, 0.66, 0.40)
	d.debuff = true
	d.description = "Hungry enough to notice."

	d = define(&"starving", "Starving")
	d.color = Color(0.82, 0.44, 0.28)
	d.debuff = true
	d.dps = 1.2
	d.move_mult = 0.8
	d.damage_mult = 0.75
	d.description = "Running on nothing, and it is costing you."

	d = define(&"dehydrated", "Dehydrated")
	d.color = Color(0.48, 0.68, 0.92)
	d.debuff = true
	d.dps = 1.6
	d.move_mult = 0.85
	d.description = "Water. Soon."

	d = define(&"drowning", "Drowning")
	d.color = Color(0.22, 0.42, 0.78)
	d.debuff = true
	d.dps = 8.0
	d.description = "Out of air, and out of time."

	d = define(&"freezing", "Freezing")
	d.color = Color(0.60, 0.84, 1.0)
	d.debuff = true
	d.dps = 2.2
	d.element = Blocks.ELEM_ICE
	d.move_mult = 0.8
	d.description = "The cold has stopped being uncomfortable and started counting."

	d = define(&"overheating", "Overheating")
	d.color = Color(1.0, 0.56, 0.24)
	d.debuff = true
	d.dps = 2.2
	d.element = Blocks.ELEM_FIRE
	d.description = "Too hot to keep working, and nowhere shaded."

	d = define(&"exhausted", "Exhausted")
	d.color = Color(0.56, 0.52, 0.60)
	d.debuff = true
	d.move_mult = 0.85
	d.energy_ps = -1.0
	d.description = "You have been awake far too long."

	d = define(&"wet", "Soaked")
	d.color = Color(0.44, 0.66, 0.88)
	d.debuff = true
	d.description = "Cold gets in faster while you are wet, and fire does not."


# ------------------------------------------------------------------- cures
static func _cure(id: StringName, display: String, col: Color,
		removes: Array[StringName]) -> void:
	var d := define(id, display)
	d.color = col
	d.cures = removes
	d.description = "Strips whatever it is aimed at."


static func _cures() -> void:
	_cure(&"cure_poison", "Antidote", Color(0.44, 0.86, 0.40),
		[&"poisoned", &"irradiated"] as Array[StringName])
	_cure(&"cure_radiation", "Purge", Color(0.72, 0.94, 0.36),
		[&"irradiated"] as Array[StringName])
	_cure(&"cure_all", "Panacea", Color(0.96, 0.94, 0.98), [] as Array[StringName])
