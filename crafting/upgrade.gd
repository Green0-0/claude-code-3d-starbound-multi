## Item upgrading and augment slotting — the two ways a piece of gear improves
## without being replaced.
##
## [b]Upgrading[/b] spends bars of the next metal up the ladder to raise a
## weapon's or tool's `upgrade_level`, which multiplies its damage/power and
## re-rolls its variable stats inside bounds that widen with level. The rolled
## numbers are written into the `ItemStack.data`, which `ItemStack.stat()`
## already prefers over the `ItemType` defaults — so combat and mining pick the
## new values up with no changes on their side.
##
## [b]Augments[/b] are `ItemType.Kind.AUGMENT` items pushed into a slot on the
## gear. Slots are earned by upgrade level. Installed augments live in
## `stack.data["augments"]` as an array of item ids, and their effects are
## folded into the same `data` stat overrides.
##
## All entry points take a live `ItemStack` and mutate it in place, returning a
## bool. The UI agent should call [method preview_upgrade] for the tooltip.
class_name CraftUpgrade
extends RefCounted

## Maximum upgrade level. Level 0 is a freshly crafted item.
const MAX_LEVEL := 5

## Slots unlocked at each upgrade level.
const SLOTS_AT_LEVEL := [1, 1, 2, 2, 3, 4]

## Damage / power multiplier per upgrade level.
const POWER_CURVE := [1.0, 1.18, 1.40, 1.66, 1.96, 2.32]

## Stats that get re-rolled, and the fraction of the base value the roll spans.
## `{stat: [min_fraction, max_fraction]}` at level 0, widening with level.
const ROLL_BOUNDS := {
	"damage": [0.92, 1.08],
	"attack_speed": [0.94, 1.10],
	"knockback": [0.85, 1.20],
	"tool_power": [0.94, 1.12],
	"tool_range": [0.95, 1.10],
	"defense": [0.92, 1.10],
}

## What each augment does. `stat` is added multiplicatively unless `add` is set.
const AUGMENT_EFFECTS := {
	&"aug_sharpness":  {"stat": "damage", "mul": 1.15},
	&"aug_swiftness":  {"stat": "attack_speed", "mul": 1.15},
	&"aug_reach":      {"stat": "tool_range", "add": 1.5},
	&"aug_durability": {"stat": "max_durability", "mul": 1.35},
	&"aug_ember":      {"element": Const.ELEM_FIRE, "stat": "damage", "mul": 1.05},
	&"aug_frost":      {"element": Const.ELEM_ICE, "stat": "damage", "mul": 1.05},
	&"aug_shock":      {"element": Const.ELEM_ELECTRIC, "stat": "damage", "mul": 1.05},
	&"aug_venom":      {"element": Const.ELEM_POISON, "stat": "damage", "mul": 1.05},
	&"aug_cosmic":     {"element": Const.ELEM_COSMIC, "stat": "damage", "mul": 1.20},
	&"aug_ward":       {"stat": "defense", "mul": 1.25},
	&"aug_vitality":   {"bonus": "max_health", "add": 15.0},
	&"aug_lightfoot":  {"bonus": "move_speed", "add": 0.6},
}

## Upgrading uses the bar one step above the item's own tier.
const UPGRADE_BARS: PackedStringArray = [
	"copper_bar", "iron_bar", "steel_bar", "titanium_bar",
	"durasteel_bar", "aegisalt_bar", "ferozium_bar", "solarium_bar",
]

## Station required to upgrade at each level band.
const UPGRADE_STATION: Array[StringName] = [
	&"anvil", &"anvil", &"forge", &"forge", &"replicator", &"replicator",
]


# ------------------------------------------------------------------- queries
## Current upgrade level of a stack.
static func level_of(stack: ItemStack) -> int:
	return int(stack.data.get("upgrade_level", 0)) if stack != null else 0


## Can this kind of item be upgraded at all?
static func is_upgradable(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false
	var t := stack.type()
	if t == null:
		return false
	return t.kind in [ItemType.Kind.WEAPON, ItemType.Kind.TOOL, ItemType.Kind.ARMOR]


## The station the next upgrade must happen at.
static func station_for(stack: ItemStack) -> StringName:
	var lvl := clampi(level_of(stack), 0, UPGRADE_STATION.size() - 1)
	return UPGRADE_STATION[lvl]


## Material cost of the next upgrade, as `{item_id: count}`. Empty at max level.
static func upgrade_cost(stack: ItemStack) -> Dictionary:
	if not is_upgradable(stack):
		return {}
	var lvl := level_of(stack)
	if lvl >= MAX_LEVEL:
		return {}
	var t := stack.type()
	var item_tier: int = maxi(0, int(t.tool_tier))
	var idx := clampi(item_tier + lvl, 0, UPGRADE_BARS.size() - 1)
	var bar := StringName(UPGRADE_BARS[idx])
	var cost: Dictionary = {bar: 4 + lvl * 3}
	if lvl >= 1:
		cost[&"crystal"] = 2 + lvl * 2
	if lvl >= 3:
		cost[&"quantum_processor"] = 1
	return cost


## Pixel cost of the next upgrade, charged through `Pixels` rather than the
## inventory (pixels are a balance, not a stack).
static func upgrade_pixel_cost(stack: ItemStack) -> int:
	if not is_upgradable(stack):
		return 0
	var lvl := level_of(stack)
	if lvl >= MAX_LEVEL:
		return 0
	var t := stack.type()
	return 250 * (lvl + 1) * (1 + maxi(0, int(t.tool_tier)) / 2)


## True when the player can pay for and perform the next upgrade.
static func can_upgrade(stack: ItemStack, inv: Variant = null, station: StringName = &"") -> bool:
	var cost := upgrade_cost(stack)
	if cost.is_empty():
		return false
	if station != &"" and station != station_for(stack):
		return false
	if not Pixels.can_afford(upgrade_pixel_cost(stack)):
		return false
	return Recipes.inventory_has(inv, cost)


## Everything a tooltip needs before committing to an upgrade.
## `{ level, next_level, max_level, cost, missing, affordable, station,
##    station_label, before:{stat:value}, after_min:{}, after_max:{},
##    slots, slots_next }`
static func preview_upgrade(stack: ItemStack, inv: Variant = null) -> Dictionary:
	var lvl := level_of(stack)
	var cost := upgrade_cost(stack)
	var out := {
		"level": lvl, "next_level": mini(lvl + 1, MAX_LEVEL), "max_level": MAX_LEVEL,
		"cost": cost, "missing": Recipes.missing_for(cost, inv),
		"affordable": not cost.is_empty() and Recipes.inventory_has(inv, cost)
			and Pixels.can_afford(upgrade_pixel_cost(stack)),
		"pixel_cost": upgrade_pixel_cost(stack),
		"station": station_for(stack),
		"station_label": String(CraftRecipe.STATION_LABELS.get(station_for(stack), "")),
		"slots": slot_count(stack), "slots_next": _slots_at(mini(lvl + 1, MAX_LEVEL)),
		"before": {}, "after_min": {}, "after_max": {},
	}
	if stack == null or stack.is_empty():
		return out
	var t := stack.type()
	var next := mini(lvl + 1, MAX_LEVEL)
	for key: String in ROLL_BOUNDS:
		if t == null or not (key in t):
			continue
		var base := float(t.get(key))
		if base <= 0.0:
			continue
		out["before"][key] = float(stack.stat(key, base))
		var b: Array = ROLL_BOUNDS[key]
		var spread := 1.0 + float(next) * 0.06
		out["after_min"][key] = base * POWER_CURVE[next] * (1.0 - (1.0 - float(b[0])) * spread)
		out["after_max"][key] = base * POWER_CURVE[next] * (1.0 + (float(b[1]) - 1.0) * spread)
	return out


# ----------------------------------------------------------------- upgrading
## Spends the materials and raises the item one level, re-rolling its stats.
## Returns true on success; the stack is mutated in place.
static func upgrade(stack: ItemStack, inv: Variant = null, rng: RandomNumberGenerator = null) -> bool:
	var cost := upgrade_cost(stack)
	if cost.is_empty():
		return false
	var pixels := upgrade_pixel_cost(stack)
	if not Pixels.can_afford(pixels):
		Events.toast("Not enough pixels to upgrade", "warn")
		return false
	if not Recipes.take_from(inv, cost):
		return false
	Pixels.spend(pixels, "upgrade")
	var lvl := mini(level_of(stack) + 1, MAX_LEVEL)
	stack.data["upgrade_level"] = lvl
	_reroll(stack, lvl, rng)
	_restore_durability(stack)
	apply_augments(stack)
	stack.data["name"] = "%s %s" % [_roman(lvl), stack.type().display_name if stack.type() != null else String(stack.id)]
	stack.data["rarity"] = mini(Const.RARITY_ESSENTIAL, stack.rarity() + (1 if lvl % 2 == 0 else 0))
	Events.toast("Upgraded to level %d" % lvl, "craft")
	Events.inventory_changed.emit()
	Events.play_sound.emit("upgrade", Game.player.global_position if Game.player != null else Vector3.ZERO)
	return true


## Re-rolls the stats without changing the level. Consumes a `reroll_core`.
static func reroll(stack: ItemStack, inv: Variant = null, rng: RandomNumberGenerator = null) -> bool:
	if not is_upgradable(stack):
		return false
	if not Recipes.take_from(inv, {&"reroll_core": 1}):
		return false
	_reroll(stack, level_of(stack), rng)
	apply_augments(stack)
	Events.toast("Stats re-rolled", "craft")
	Events.inventory_changed.emit()
	return true


static func _reroll(stack: ItemStack, level: int, rng: RandomNumberGenerator) -> void:
	var t := stack.type()
	if t == null:
		return
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var mult: float = POWER_CURVE[clampi(level, 0, POWER_CURVE.size() - 1)]
	var spread := 1.0 + float(level) * 0.06
	var rolls: Dictionary = {}
	for key: String in ROLL_BOUNDS:
		if not (key in t):
			continue
		var base := float(t.get(key))
		if base <= 0.0:
			continue
		var b: Array = ROLL_BOUNDS[key]
		var lo := 1.0 - (1.0 - float(b[0])) * spread
		var hi := 1.0 + (float(b[1]) - 1.0) * spread
		var rolled := base * mult * r.randf_range(lo, hi)
		rolls[key] = snappedf(rolled, 0.01)
	stack.data["base_rolls"] = rolls
	for key: String in rolls:
		stack.data[key] = rolls[key]


static func _restore_durability(stack: ItemStack) -> void:
	if not stack.data.has("max_durability"):
		return
	var lvl := level_of(stack)
	var t := stack.type()
	var base := 100 + (t.tool_tier if t != null else 0) * 150
	var maxd := int(float(base) * (1.0 + float(lvl) * 0.25))
	stack.data["max_durability"] = maxd
	stack.data["durability"] = maxd


# ------------------------------------------------------------------ augments
## How many augment slots this item currently has.
static func slot_count(stack: ItemStack) -> int:
	if not is_upgradable(stack):
		return 0
	return _slots_at(level_of(stack))


static func _slots_at(level: int) -> int:
	return int(SLOTS_AT_LEVEL[clampi(level, 0, SLOTS_AT_LEVEL.size() - 1)])


## Ids of the augments currently installed, in slot order.
static func installed_augments(stack: ItemStack) -> Array:
	if stack == null:
		return []
	return (stack.data.get("augments", []) as Array).duplicate()


## True when `augment_id` is a real augment, fits, and is not already in.
static func can_slot(stack: ItemStack, augment_id: StringName, inv: Variant = null) -> bool:
	if not is_upgradable(stack) or not AUGMENT_EFFECTS.has(augment_id):
		return false
	var cur := installed_augments(stack)
	if cur.size() >= slot_count(stack) or cur.has(String(augment_id)):
		return false
	return inv == null or Recipes.inventory_has(inv, {augment_id: 1})


## Why `can_slot` said no — a short string for the UI.
static func slot_blocker(stack: ItemStack, augment_id: StringName, inv: Variant = null) -> String:
	if not is_upgradable(stack):
		return "This item cannot take augments."
	if not AUGMENT_EFFECTS.has(augment_id):
		return "Unknown augment."
	var cur := installed_augments(stack)
	if cur.has(String(augment_id)):
		return "Already installed."
	if cur.size() >= slot_count(stack):
		return "No free slots — upgrade the item first."
	if inv != null and not Recipes.inventory_has(inv, {augment_id: 1}):
		return "You do not have that augment."
	return ""


## Consumes the augment item and installs it. Mutates `stack` in place.
static func slot_augment(stack: ItemStack, augment_id: StringName, inv: Variant = null) -> bool:
	if not can_slot(stack, augment_id, inv):
		return false
	if inv != null and not Recipes.take_from(inv, {augment_id: 1}):
		return false
	var cur := installed_augments(stack)
	cur.append(String(augment_id))
	stack.data["augments"] = cur
	apply_augments(stack)
	Events.toast("Augment installed: %s" % Items.display_name(augment_id), "craft")
	Events.inventory_changed.emit()
	return true


## Pulls an augment back out. Needs an `augment_extractor` unless `free`.
static func remove_augment(stack: ItemStack, index: int, inv: Variant = null,
		free: bool = false) -> bool:
	var cur := installed_augments(stack)
	if index < 0 or index >= cur.size():
		return false
	if not free and not Recipes.take_from(inv, {&"augment_extractor": 1}):
		return false
	var aug := StringName(cur[index])
	cur.remove_at(index)
	stack.data["augments"] = cur
	apply_augments(stack)
	Recipes.give_to(inv, aug, 1, true)
	Events.inventory_changed.emit()
	return true


## Recomputes every stat override from `base_rolls` plus the installed augments.
## Called automatically after any change; call it yourself after editing
## `stack.data["augments"]` by hand.
static func apply_augments(stack: ItemStack) -> void:
	if stack == null or stack.is_empty():
		return
	var t := stack.type()
	var rolls: Dictionary = stack.data.get("base_rolls", {})
	# Reset to the rolled baseline (or the type default when never rolled).
	for key: String in ROLL_BOUNDS:
		if rolls.has(key):
			stack.data[key] = rolls[key]
		elif t != null and (key in t):
			stack.data[key] = t.get(key)
	if t != null:
		stack.data["element"] = t.element
	var bonuses: Dictionary = {}
	for a: Variant in installed_augments(stack):
		var eff: Dictionary = AUGMENT_EFFECTS.get(StringName(a), {})
		if eff.is_empty():
			continue
		if eff.has("stat"):
			var key: String = eff["stat"]
			var cur := float(stack.data.get(key, t.get(key) if t != null and (key in t) else 0.0))
			if eff.has("mul"):
				cur *= float(eff["mul"])
			if eff.has("add"):
				cur += float(eff["add"])
			stack.data[key] = snappedf(cur, 0.01)
		if eff.has("element"):
			stack.data["element"] = eff["element"]
		if eff.has("bonus"):
			bonuses[eff["bonus"]] = float(bonuses.get(eff["bonus"], 0.0)) + float(eff.get("add", 0.0))
	if not bonuses.is_empty():
		stack.data["stat_bonuses"] = bonuses
	elif stack.data.has("stat_bonuses"):
		stack.data.erase("stat_bonuses")


## The final numbers, for a tooltip: `{stat: value}` plus `element` and
## `augments`. Reads only — never mutates.
static func effective_stats(stack: ItemStack) -> Dictionary:
	var out: Dictionary = {}
	if stack == null or stack.is_empty():
		return out
	var t := stack.type()
	for key: String in ROLL_BOUNDS:
		if t != null and (key in t):
			var base := float(t.get(key))
			if base > 0.0 or stack.data.has(key):
				out[key] = float(stack.stat(key, base))
	out["element"] = stack.stat("element", t.element if t != null else Const.ELEM_PHYSICAL)
	out["upgrade_level"] = level_of(stack)
	out["augments"] = installed_augments(stack)
	out["slots"] = slot_count(stack)
	return out


static func _roman(n: int) -> String:
	var numerals: PackedStringArray = ["", "I", "II", "III", "IV", "V", "VI"]
	return numerals[clampi(n, 0, numerals.size() - 1)]
