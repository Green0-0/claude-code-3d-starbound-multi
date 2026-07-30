class_name PlayerStats
extends RefCounted

## The player's survival needs and their status effects.
##
## Four needs run down over time — food, water, air and warmth — and each one
## expresses itself by applying an ordinary status effect rather than by
## reaching into the player. That means there is exactly one place where a
## number becomes a consequence, and a well-fed buff and a starving debuff are
## the same kind of object.
##
## Air is the only need that also refills, quickly, whenever you surface.

signal effects_changed()
signal needs_changed()

const MAX_FOOD := 100.0
const MAX_WATER := 100.0
const MAX_AIR := 100.0

## Seconds of world time to run a full bar down while walking about.
const FOOD_DRAIN := 100.0 / 900.0
const WATER_DRAIN := 100.0 / 700.0
const AIR_DRAIN := 100.0 / 26.0
const AIR_REFILL := 100.0 / 3.0

const WARMTH_NEUTRAL := 0.0

var player: Node = null

var food := MAX_FOOD
var water := MAX_WATER
var air := MAX_AIR
## -1 freezing .. 0 comfortable .. +1 baking; driven by biome, depth and gear.
var warmth := 0.0
var needs_enabled := true

## effect id -> {"left": seconds, "stacks": int}
var active := {}

var _tick := 0.0


func _init() -> void:
	EffectLib.boot()


# =============================================================================
# per-frame
# =============================================================================

func tick(delta: float) -> void:
	_tick_effects(delta)
	if needs_enabled:
		_tick_needs(delta)


func _tick_effects(delta: float) -> void:
	if active.is_empty():
		return
	var expired: Array[StringName] = []
	var heal := 0.0
	var dps_total := 0.0
	var dps_element: StringName = Blocks.ELEM_PHYSICAL
	var energy := 0.0
	for id: StringName in active:
		var e: Dictionary = active[id]
		e["left"] = float(e["left"]) - delta
		if float(e["left"]) <= 0.0:
			expired.append(id)
			continue
		var d := EffectLib.get_def(id)
		if d == null:
			continue
		var stacks := float(e["stacks"])
		heal += d.heal_ps * stacks * delta
		energy += d.energy_ps * stacks * delta
		if d.dps > 0.0:
			dps_total += d.dps * stacks * delta
			dps_element = d.element
	for id: StringName in expired:
		active.erase(id)
	if not expired.is_empty():
		effects_changed.emit()

	if player == null:
		return
	if heal > 0.0:
		player.heal(heal)
	elif heal < 0.0:
		player.hurt(-heal)
	if dps_total > 0.0:
		player.hurt(dps_total, dps_element)
	if energy != 0.0:
		player.energy = clampf(player.energy + energy, 0.0,
			player.effective_max_energy())


func _tick_needs(delta: float) -> void:
	_tick += delta
	var was_food := food
	var was_water := water

	# --- air
	var drowning: bool = player != null and bool(player.submerged) \
		and not has_effect(&"water_breathing")
	if drowning:
		air = maxf(air - AIR_DRAIN * delta, 0.0)
		if air <= 0.0:
			apply_effect(&"drowning", 1.5)
	else:
		air = minf(air + AIR_REFILL * delta, MAX_AIR)

	# --- food and water, spent faster while sprinting
	var effort := 1.0
	if player != null and Vector2(player.velocity.x, player.velocity.z).length() > 6.0:
		effort = 1.7
	food = maxf(food - FOOD_DRAIN * effort * delta, 0.0)
	water = maxf(water - WATER_DRAIN * effort * delta, 0.0)

	if food <= 0.0:
		apply_effect(&"starving", 2.0)
	elif food < 22.0:
		apply_effect(&"peckish", 2.0)
	if water <= 0.0:
		apply_effect(&"dehydrated", 2.0)

	# --- temperature: a gear-adjusted band around the ambient value
	var insulation := 0.0
	if player != null:
		insulation = player.inventory.bonus("warmth")
	var effective := warmth - insulation * 0.02
	if effective < -0.55:
		apply_effect(&"freezing", 2.0)
	elif effective > 0.55 and not has_effect(&"fire_resistance"):
		apply_effect(&"overheating", 2.0)

	if absf(food - was_food) > 0.5 or absf(water - was_water) > 0.5:
		needs_changed.emit()


# =============================================================================
# effects
# =============================================================================

## Apply (or refresh) an effect. Cures resolve immediately and are never stored.
func apply_effect(id: StringName, seconds: float) -> void:
	var d := EffectLib.get_def(id)
	if d == null:
		return
	if not d.cures.is_empty() or id == &"cure_all":
		_resolve_cure(d)
		return
	var e: Dictionary = active.get(id, {"left": 0.0, "stacks": 0})
	e["left"] = maxf(float(e["left"]), seconds)
	e["stacks"] = mini(int(e["stacks"]) + 1, d.max_stacks)
	active[id] = e
	effects_changed.emit()


func _resolve_cure(d: EffectLib.Def) -> void:
	if d.id == &"cure_all":
		var gone: Array[StringName] = []
		for id: StringName in active:
			var e := EffectLib.get_def(id)
			if e != null and e.debuff:
				gone.append(id)
		for id: StringName in gone:
			active.erase(id)
	else:
		for id: StringName in d.cures:
			active.erase(id)
	effects_changed.emit()


func remove_effect(id: StringName) -> void:
	if active.erase(id):
		effects_changed.emit()


func has_effect(id: StringName) -> bool:
	return active.has(id)


func effect_time(id: StringName) -> float:
	var e: Variant = active.get(id)
	return float(e["left"]) if e != null else 0.0


func clear_effects() -> void:
	active.clear()
	effects_changed.emit()


func reset_needs() -> void:
	food = MAX_FOOD
	water = MAX_WATER
	air = MAX_AIR
	needs_changed.emit()


## Every active effect, sorted debuffs-last, for the HUD strip.
func listed() -> Array:
	var out: Array = []
	for id: StringName in active:
		var d := EffectLib.get_def(id)
		if d == null:
			continue
		out.append({"def": d, "left": float(active[id]["left"]),
			"stacks": int(active[id]["stacks"])})
	out.sort_custom(func(a, b):
		return int(a["def"].debuff) < int(b["def"].debuff))
	return out


# =============================================================================
# aggregate modifiers
# =============================================================================

func _product(field: String) -> float:
	var v := 1.0
	for id: StringName in active:
		var d := EffectLib.get_def(id)
		if d != null:
			v *= float(d.get(field))
	return v


func move_multiplier() -> float:
	return _product("move_mult")


func mining_multiplier() -> float:
	return _product("mine_mult")


func damage_multiplier() -> float:
	return _product("damage_mult")


func modify_incoming(amount: float, _element: StringName) -> float:
	return amount * _product("taken_mult")


func light_bonus() -> float:
	var v := 0.0
	for id: StringName in active:
		var d := EffectLib.get_def(id)
		if d != null:
			v += d.light
	return v


# =============================================================================
# eating
# =============================================================================

## Consume a food or medicine stack. Returns true when one was used up.
func consume(stack: Items.Stack) -> bool:
	var t := stack.type()
	if t == null:
		return false
	if t.kind != Items.Kind.CONSUMABLE:
		return false
	var is_drink := t.has_tag(&"drink")
	if is_drink:
		if water >= MAX_WATER - 0.5 and t.heal <= 0.0:
			return false
		water = minf(water + t.food, MAX_WATER)
	else:
		if t.food > 0.0:
			if food >= MAX_FOOD - 0.5 and t.heal <= 0.0 and t.effects.is_empty():
				return false
			food = minf(food + t.food, MAX_FOOD)
	if t.heal > 0.0 and player != null:
		player.heal(t.heal)
	for pair in t.effects:
		apply_effect(StringName(pair[0]), float(pair[1]))
	needs_changed.emit()
	return true


# =============================================================================
# persistence
# =============================================================================

func save_state() -> Dictionary:
	var eff := {}
	for id: StringName in active:
		eff[String(id)] = active[id]
	return {"food": food, "water": water, "air": air, "warmth": warmth,
		"effects": eff}


func load_state(d: Dictionary) -> void:
	food = float(d.get("food", MAX_FOOD))
	water = float(d.get("water", MAX_WATER))
	air = float(d.get("air", MAX_AIR))
	warmth = float(d.get("warmth", 0.0))
	active.clear()
	var eff: Dictionary = d.get("effects", {})
	for k: String in eff:
		active[StringName(k)] = eff[k]
	effects_changed.emit()
	needs_changed.emit()
