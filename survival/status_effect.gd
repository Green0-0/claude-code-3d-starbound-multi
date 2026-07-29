## Definition of one *kind* of status effect. Pure data plus optional hooks,
## built with the same fluent style as `BlockType` / `ItemType` so the effect
## library reads like a table.
##
## An effect never holds per-entity state — that lives in
## `SrvStatusHolder.Active`. One definition is shared by every entity that
## currently has the effect, which is what makes `Status.modifier()` cheap.
##
## ## Stat modifier contract
##
## `mods` maps a **stat key** to a **multiplier**. `Status.modifier(stat, e)`
## multiplies every active effect's entry together (raised to the stack count),
## so `1.0` is "no change", `0.5` is "halved", `1.3` is "+30%".
##
## The stat keys the rest of the game reads (see `combat/damage.gd`):
##
##   damage_dealt  crit_chance  damage_taken  defense  knockback_taken
##   resist_physical resist_fire resist_ice resist_electric resist_poison
##   resist_cosmic
##
## and the ones survival / movement / tools read:
##
##   move_speed  jump_speed  mining_speed  attack_speed  regen  energy_regen
##   hunger_rate  thirst_rate  fatigue_rate  breath_rate  gravity  fall_damage
##   light_radius  luck
class_name SrvStatusEffect
extends RefCounted

## What happens when an effect is applied to a target that already has it.
enum Stack {
	REFRESH,  ## keep the longer of the two remaining durations (the default)
	EXTEND,   ## add the new duration on top of what is left
	STACK,    ## add a stack (clamped to `max_stacks`) and refresh the timer
	IGNORE,   ## re-application is a no-op while the effect is running
}

## Pass as `duration` to mean "until something removes it".
const PERMANENT := -1.0

var id: StringName = &""
var display_name: String = "Effect"
var description: String = ""
## `buff`, `debuff`, `environment`, `medical` or `signature` — HUD grouping.
var category: StringName = &"buff"
## False for anything the player wants gone. Drives HUD colour and `cure()`.
var beneficial: bool = true

var default_duration: float = 10.0
var max_stacks: int = 1
var stack_mode: Stack = Stack.REFRESH

# ------------------------------------------------------------------- visuals
## Sprite tint blended over the entity while active (alpha 0 = no tint).
var tint: Color = Color(0, 0, 0, 0)
## Particle effect id emitted at `particle_rate` per second (see `fx/`).
var particle: StringName = &""
var particle_rate: float = 0.0
var apply_sound: StringName = &""
## HUD icon colour; the UI agent draws the icon procedurally.
var icon_color: Color = Color(0.8, 0.8, 0.8)
var icon_shape: StringName = &"circle"
## Extra light the holder emits, in blocks. Read by `sim/lighting`.
var light_radius: float = 0.0

# -------------------------------------------------------------------- effect
var mods: Dictionary = {}                    ## String stat -> float multiplier
var tick_interval: float = 1.0
var damage_per_tick: float = 0.0
var damage_element: String = Const.ELEM_PHYSICAL
var heal_per_tick: float = 0.0

## Effects removed from the target the moment this one lands (fire melts ice).
var cancels: Array[StringName] = []
## This effect refuses to apply while the target has any of these.
var blocked_by: Array[StringName] = []
## Medicine keywords that clear it: `antidote`, `bandage`, `cure`, `antirad`,
## `warmth`, `cooling`. Used by `survival/medical.gd`.
var cures: Array[StringName] = []

## Hidden effects still work but never show in the HUD (internal bookkeeping).
var hidden: bool = false
## False for effects that must not survive a save/load round trip.
var persist: bool = true

# --------------------------------------------------------------------- hooks
## on_apply(target: Node, act: SrvStatusHolder.Active) -> void
var on_apply: Callable = Callable()
## on_remove(target: Node, act: SrvStatusHolder.Active) -> void
var on_remove: Callable = Callable()
## on_tick(target: Node, act: SrvStatusHolder.Active, delta: float) -> void
var on_tick: Callable = Callable()


func _init(p_id: StringName, p_display: String = "") -> void:
	id = p_id
	display_name = p_display if p_display != "" else String(p_id).capitalize()


# ---------------------------------------------------------------- fluent API
## Default duration in seconds; `SrvStatusEffect.PERMANENT` for open-ended.
func lasts(seconds: float) -> SrvStatusEffect:
	default_duration = seconds
	return self


func describe(text: String) -> SrvStatusEffect:
	description = text
	return self


## Marks the effect as something the player wants rid of.
func debuff(cat: StringName = &"debuff") -> SrvStatusEffect:
	beneficial = false
	category = cat
	return self


func in_category(c: StringName) -> SrvStatusEffect:
	category = c
	return self


func stacking(mode: Stack, p_max: int = 1) -> SrvStatusEffect:
	stack_mode = mode
	max_stacks = maxi(1, p_max)
	return self


## One stat multiplier. Call repeatedly for several stats.
func modifies(stat: String, multiplier: float) -> SrvStatusEffect:
	mods[stat] = multiplier
	return self


## Bulk form of [method modifies].
func modifies_all(table: Dictionary) -> SrvStatusEffect:
	for k: String in table:
		mods[k] = float(table[k])
	return self


func visual(p_tint: Color, p_particle: StringName = &"", rate: float = 0.0) -> SrvStatusEffect:
	tint = p_tint
	particle = p_particle
	particle_rate = rate
	if icon_color == Color(0.8, 0.8, 0.8) and p_tint.a > 0.0:
		icon_color = Color(p_tint.r, p_tint.g, p_tint.b, 1.0)
	return self


func icon(c: Color, shape: StringName = &"circle") -> SrvStatusEffect:
	icon_color = c
	icon_shape = shape
	return self


func glows(radius: float) -> SrvStatusEffect:
	light_radius = radius
	return self


func ticks(interval: float) -> SrvStatusEffect:
	tick_interval = maxf(0.05, interval)
	return self


## Damage per tick interval (not per second) and its element.
func deals(amount: float, element: String = Const.ELEM_PHYSICAL) -> SrvStatusEffect:
	damage_per_tick = amount
	damage_element = element
	return self


func restores(amount: float) -> SrvStatusEffect:
	heal_per_tick = amount
	return self


func sounds(p_apply: StringName) -> SrvStatusEffect:
	apply_sound = p_apply
	return self


func clears(ids: Array) -> SrvStatusEffect:
	for i in ids:
		cancels.append(StringName(i))
	return self


func blocked(ids: Array) -> SrvStatusEffect:
	for i in ids:
		blocked_by.append(StringName(i))
	return self


func curable(keywords: Array) -> SrvStatusEffect:
	for k in keywords:
		cures.append(StringName(k))
	return self


func hide() -> SrvStatusEffect:
	hidden = true
	return self


func transient() -> SrvStatusEffect:
	persist = false
	return self


func hooks(p_apply: Callable = Callable(), p_remove: Callable = Callable(),
		p_tick: Callable = Callable()) -> SrvStatusEffect:
	on_apply = p_apply
	on_remove = p_remove
	on_tick = p_tick
	return self


# ------------------------------------------------------------------ queries
## Multiplier contributed by this effect for `stat` at `stacks` stacks.
func mod_for(stat: String, stacks: int) -> float:
	var m: float = mods.get(stat, 1.0)
	if stacks <= 1 or is_equal_approx(m, 1.0):
		return m
	return pow(m, float(stacks))


func is_cured_by(keyword: StringName) -> bool:
	return cures.has(keyword)
