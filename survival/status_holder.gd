## Everything one entity currently suffers or enjoys, plus the flattened stat
## modifier cache that makes `Status.modifier()` a two-dictionary lookup.
##
## The cache is invalidated (`dirty = true`) whenever an effect is added,
## removed, or changes stack count — never rebuilt speculatively. The damage
## pipeline calls `modifier()` several times per hit, so the rebuild must be the
## rare path.
class_name SrvStatusHolder
extends RefCounted


## One live application of an effect on one entity.
class Active extends RefCounted:
	var def: SrvStatusEffect
	## Seconds left; negative means permanent.
	var remaining: float = 0.0
	## Duration the effect was (re)applied with, for HUD progress rings.
	var duration: float = 0.0
	var stacks: int = 1
	var tick_timer: float = 0.0
	var fx_timer: float = 0.0
	## Free-form scratch space for hooks (source node, accumulated dose, ...).
	var data: Dictionary = {}

	func _init(p_def: SrvStatusEffect, p_duration: float, p_stacks: int) -> void:
		def = p_def
		duration = p_duration
		remaining = p_duration
		stacks = clampi(p_stacks, 1, p_def.max_stacks)

	func id() -> StringName:
		return def.id

	func is_permanent() -> bool:
		return duration < 0.0

	## 1.0 when freshly applied, 0.0 as it expires. Permanent effects read 1.0.
	func fraction() -> float:
		if is_permanent() or duration <= 0.0:
			return 1.0
		return clampf(remaining / duration, 0.0, 1.0)

	func to_dict() -> Dictionary:
		return {"id": String(def.id), "remaining": remaining,
			"duration": duration, "stacks": stacks}


## The entity these effects sit on. May become invalid; always guard.
var target: Node = null
var target_id: int = 0
var is_player: bool = false

## StringName -> Active
var effects: Dictionary = {}

## Flattened `stat -> multiplier`, valid only while `dirty` is false.
var mods: Dictionary = {}
var dirty: bool = true

## Cached blended sprite tint, recomputed with the mods.
var tint: Color = Color(0, 0, 0, 0)
## Cached sum of every active effect's `light_radius`.
var light_radius: float = 0.0


func _init(p_target: Node) -> void:
	target = p_target
	target_id = p_target.get_instance_id() if p_target != null else 0
	is_player = p_target != null and p_target.is_in_group(&"player")


func alive() -> bool:
	return target != null and is_instance_valid(target)


func is_empty() -> bool:
	return effects.is_empty()


func get_active(id: StringName) -> Active:
	return effects.get(id)


## Rebuild the flattened modifier table. Called lazily from `Status.modifier()`.
func rebuild() -> void:
	mods.clear()
	light_radius = 0.0
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var a := 0.0
	for key: StringName in effects:
		var act: Active = effects[key]
		var def := act.def
		if not def.mods.is_empty():
			for stat: String in def.mods:
				var m := def.mod_for(stat, act.stacks)
				mods[stat] = float(mods.get(stat, 1.0)) * m
		light_radius += def.light_radius
		if def.tint.a > 0.0:
			var w := def.tint.a
			r += def.tint.r * w
			g += def.tint.g * w
			b += def.tint.b * w
			a += w
	if a > 0.0:
		tint = Color(r / a, g / a, b / a, minf(0.85, a))
	else:
		tint = Color(0, 0, 0, 0)
	dirty = false


## HUD-facing snapshot: one dictionary per visible effect, worst first.
func snapshot(include_hidden: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: StringName in effects:
		var act: Active = effects[key]
		if act.def.hidden and not include_hidden:
			continue
		out.append({
			"id": act.def.id,
			"name": act.def.display_name,
			"description": act.def.description,
			"category": act.def.category,
			"beneficial": act.def.beneficial,
			"remaining": act.remaining,
			"duration": act.duration,
			"fraction": act.fraction(),
			"stacks": act.stacks,
			"color": act.def.icon_color,
			"shape": act.def.icon_shape,
		})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["beneficial"] != y["beneficial"]:
			return not bool(x["beneficial"])
		return float(x["remaining"]) < float(y["remaining"]))
	return out


func save_state() -> Array:
	var out: Array = []
	for key: StringName in effects:
		var act: Active = effects[key]
		if act.def.persist:
			out.append(act.to_dict())
	return out
