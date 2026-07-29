## Per-liquid parameters and the liquid/liquid + liquid/block reaction matrix.
##
## Everything here is **data**. The solver never branches on a liquid's name; it
## looks up a parameter dictionary and a reaction rule and applies whatever it
## finds. Adding a new liquid therefore means adding one row to [member TABLE]
## (naming the `Render.LIQUID` block in `content/blocks/` that carries it) and,
## optionally, rows to [member REACTIONS] / [member BLOCK_REACTIONS].
##
## The liquid key and its block name are allowed to differ — the block-content
## agent calls poison `toxic_water` — so [method canonical] accepts either
## vocabulary and every other entry point funnels through it.
##
## Blocks referenced by name are always *optional*: every lookup goes through
## [method resolve_block], which walks a preference list and falls back to a
## block that is guaranteed to exist. A liquid whose block is not registered is
## simply inert — nothing crashes.
class_name LiqType
extends RefCounted

## Levels are 0..Const.MAX_LIQUID (8). A "full" cell is 8.
const FULL := Const.MAX_LIQUID

## Pressure is tracked in quarter-blocks of head so lateral loss can be
## fractional without floats. 4 units == 1 block of climb.
const PRESSURE_UNIT := 4

## Every field a liquid can define. Rows in [member TABLE] override a subset.
const DEFAULTS := {
	# ---- identity
	"name": &"water",
	"block": &"water",              ## block StringName carrying this liquid
	## Reaction fallback: an unlisted pairing is retried as if this liquid were
	## `like`. Salt water burns like water; molten core freezes like lava.
	"like": &"",
	"display": "Liquid",
	"color": Color(0.18, 0.42, 0.85, 0.62),
	"fog": Color(0.10, 0.28, 0.55, 0.75),   ## camera tint while submerged

	# ---- flow / viscosity
	"density": 1.0,                 ## relative to water; heavier sinks
	"flow_interval": 1,             ## sim ticks between updates of one cell
	"flow_rate": 8,                 ## max units leaving a cell per update
	"min_lateral": 1,               ## level needed before it spreads sideways
	"pressure_loss": 1,             ## quarter-blocks of head lost per lateral step
	"max_head": 12,                 ## blocks of column scanned for pressure
	"evaporate": 0.0,               ## chance/update an unsupported thin cell dies
	"evaporate_at": 1,              ## level at or below which that may happen

	# ---- entity effects
	"damage": 0.0,                  ## damage per second while submerged
	"element": Const.ELEM_PHYSICAL,
	"heal": 0.0,                    ## health per second while submerged
	"status": &"",                  ## Status effect id applied while submerged
	"status_time": 3.0,
	"buoyancy": 1.0,                ## upward force multiplier (1 = neutral)
	"drag": 3.5,                    ## velocity damping per second
	"swim_speed": 0.65,             ## multiplier on plane movement while swimming
	"current": 1.0,                 ## how hard the flow pushes entities
	"breathable": false,            ## false -> drains breath

	# ---- world effects
	"light": 0,                     ## 0..15 emitted (mirrors the block's glow)
	"burns": false,                 ## ignites flammable blocks it touches
	"flammable": false,             ## can itself be ignited by fire/lava
	"freezes": false,               ## turns water into ice
	"dissolve": 0.0,                ## block hardness dissolved per second
	"dissolve_max": 3.0,            ## hardest block this liquid can eat
	"extinguishes": false,          ## puts out fire blocks / burning status

	# ---- presentation
	"splash": &"splash_water",
	"ambient": &"",
	"enter_sound": &"splash",
	"bucket": &"water_bucket",      ## item granted by scooping (optional)
}

## The shipped liquids — the nine the design calls for, plus the three variants
## the block-content agent registered. Only fields that differ from DEFAULTS.
const TABLE := {
	&"water": {
		"display": "Water",
		"bucket": &"water_bucket",
		"extinguishes": true,
		"evaporate": 0.015,
		"status": &"wet",
		"status_time": 6.0,
	},
	&"lava": {
		"display": "Lava",
		"block": &"lava",
		"color": Color(0.95, 0.42, 0.1, 0.9),
		"fog": Color(0.7, 0.2, 0.02, 0.92),
		"density": 3.0,
		"flow_interval": 4,          ## thick: one update every 0.4 s
		"flow_rate": 1,
		"min_lateral": 4,            ## thin tongues do not creep any further
		"pressure_loss": 99,         ## never climbs
		"evaporate": 0.05,
		"evaporate_at": 2,
		"damage": 18.0,
		"element": Const.ELEM_FIRE,
		"status": &"burning",
		"status_time": 6.0,
		"buoyancy": 1.9,
		"drag": 9.0,
		"swim_speed": 0.2,
		"current": 0.4,
		"light": 14,
		"burns": true,
		"splash": &"splash_lava",
		"enter_sound": &"lava_burn",
		"ambient": &"lava_bubble",
		"bucket": &"lava_bucket",
	},
	&"healing_water": {
		"display": "Healing Water",
		"block": &"healing_water",
		"like": &"water",
		"color": Color(0.45, 0.95, 0.75, 0.6),
		"fog": Color(0.2, 0.7, 0.55, 0.7),
		"heal": 7.0,
		"light": 6,
		"extinguishes": true,
		"evaporate": 0.01,
		"splash": &"splash_heal",
		"bucket": &"healing_water_bucket",
	},
	&"poison": {
		"display": "Poison",
		"block": &"toxic_water",
		"color": Color(0.45, 0.85, 0.2, 0.7),
		"fog": Color(0.25, 0.5, 0.1, 0.8),
		"density": 1.1,
		"flow_interval": 2,
		"flow_rate": 4,
		"damage": 4.0,
		"element": Const.ELEM_POISON,
		"status": &"poisoned",
		"status_time": 8.0,
		"drag": 4.5,
		"evaporate": 0.01,
		"splash": &"splash_poison",
		"bucket": &"poison_bucket",
	},
	&"acid": {
		"display": "Acid",
		"block": &"acid",
		"color": Color(0.85, 0.95, 0.25, 0.7),
		"fog": Color(0.6, 0.7, 0.1, 0.8),
		"density": 1.2,
		"flow_interval": 2,
		"flow_rate": 4,
		"damage": 9.0,
		"element": Const.ELEM_POISON,
		"status": &"corroded",
		"status_time": 5.0,
		"drag": 4.0,
		"dissolve": 1.4,
		"dissolve_max": 3.0,
		"evaporate": 0.03,
		"evaporate_at": 2,
		"splash": &"splash_acid",
		"bucket": &"acid_bucket",
	},
	&"slime": {
		"display": "Slime",
		"block": &"slime_liquid",
		"color": Color(0.4, 0.8, 0.45, 0.75),
		"fog": Color(0.2, 0.5, 0.25, 0.85),
		"density": 1.6,
		"status": &"slimed",
		"status_time": 4.0,
		"flow_interval": 5,
		"flow_rate": 1,
		"min_lateral": 3,
		"pressure_loss": 8,
		"buoyancy": 1.7,
		"drag": 11.0,
		"swim_speed": 0.35,
		"current": 0.5,
		"evaporate": 0.0,
		"splash": &"splash_slime",
		"bucket": &"slime_bucket",
	},
	&"tar": {
		"display": "Tar",
		"block": &"tar",
		"color": Color(0.09, 0.08, 0.11, 0.95),
		"fog": Color(0.03, 0.03, 0.04, 0.98),
		"density": 1.4,
		"flow_interval": 7,
		"flow_rate": 1,
		"min_lateral": 4,
		"pressure_loss": 16,
		"buoyancy": 1.4,
		"drag": 14.0,
		"swim_speed": 0.18,
		"current": 0.25,
		"flammable": true,
		"evaporate": 0.0,
		"splash": &"splash_tar",
		"bucket": &"tar_bucket",
	},
	&"liquid_nitrogen": {
		"display": "Liquid Nitrogen",
		"block": &"liquid_nitrogen",
		"color": Color(0.75, 0.92, 1.0, 0.5),
		"fog": Color(0.6, 0.85, 1.0, 0.7),
		"density": 0.8,
		"flow_interval": 1,
		"flow_rate": 8,
		"damage": 10.0,
		"element": Const.ELEM_ICE,
		"status": &"chilled",
		"status_time": 5.0,
		"buoyancy": 0.85,
		"drag": 3.0,
		"freezes": true,
		"extinguishes": true,
		"evaporate": 0.18,          ## boils off fast in the open
		"evaporate_at": 3,
		"splash": &"splash_frost",
		"enter_sound": &"freeze",
		"bucket": &"nitrogen_canister",
	},
	&"fuel": {
		"display": "Liquid Fuel",
		"block": &"liquid_fuel",
		"color": Color(0.62, 0.44, 0.90, 0.72),
		"fog": Color(0.4, 0.3, 0.55, 0.7),
		"light": 5,
		"density": 0.85,
		"flow_interval": 1,
		"flow_rate": 8,
		"damage": 1.0,
		"element": Const.ELEM_POISON,
		"buoyancy": 0.9,
		"drag": 3.0,
		"flammable": true,
		"evaporate": 0.06,
		"evaporate_at": 2,
		"splash": &"splash_fuel",
		"bucket": &"fuel_canister",
	},

	# ---- variants of the above, registered by the block-content agent -------
	&"salt_water": {
		"display": "Salt Water",
		"block": &"salt_water",
		"like": &"water",
		"color": Color(0.14, 0.38, 0.62, 0.64),
		"fog": Color(0.08, 0.24, 0.42, 0.78),
		"density": 1.05,
		"buoyancy": 1.08,          ## you float a little better in the sea
		"evaporate": 0.02,
		"bucket": &"salt_water_bucket",
	},
	&"swamp_water": {
		"display": "Swamp Water",
		"block": &"swamp_water",
		"like": &"water",
		"color": Color(0.24, 0.34, 0.24, 0.68),
		"fog": Color(0.14, 0.22, 0.14, 0.85),
		"flow_interval": 2,
		"drag": 5.0,
		"swim_speed": 0.5,
		"evaporate": 0.01,
		"bucket": &"swamp_water_bucket",
	},
	&"molten_core": {
		"display": "Molten Core",
		"block": &"molten_core",
		"like": &"lava",
		"color": Color(1.0, 0.72, 0.2, 0.95),
		"fog": Color(0.85, 0.45, 0.05, 0.95),
		"density": 4.0,
		"flow_interval": 5,
		"flow_rate": 1,
		"min_lateral": 5,
		"pressure_loss": 99,
		"evaporate": 0.03,
		"evaporate_at": 2,
		"damage": 32.0,
		"element": Const.ELEM_FIRE,
		"status": &"burning",
		"status_time": 8.0,
		"buoyancy": 2.2,
		"drag": 10.0,
		"swim_speed": 0.15,
		"current": 0.3,
		"light": 15,
		"burns": true,
		"splash": &"splash_lava",
		"enter_sound": &"lava_burn",
		"ambient": &"lava_bubble",
		"bucket": &"molten_core_bucket",
	},
}

## Liquid + liquid reactions. Symmetric: a rule is found whichever way round the
## pair is queried, and [method reaction] re-orients it for the caller.
##
##   consume_a/b : units removed from that cell (8 == the whole cell)
##   block_at    : "a", "b" or "" — which cell turns into a solid block
##   block       : preference list for that solid; first registered one wins
##   weak_block  : used instead when the `block_at` cell was not full
##   explode     : blast radius, 0 for none
const REACTIONS := [
	{
		"a": &"water", "b": &"lava",
		"consume_a": 4, "consume_b": 8,
		"block_at": "b", "block": [&"obsidian", &"basalt", &"stone"],
		"weak_block": [&"cobblestone", &"stone"],
		"particles": &"steam", "amount": 22, "sound": &"hiss", "shake": 0.25,
	},
	{
		"a": &"water", "b": &"liquid_nitrogen",
		"consume_a": 8, "consume_b": 4,
		"block_at": "a", "block": [&"ice", &"packed_ice", &"snow"],
		"particles": &"frost", "amount": 16, "sound": &"freeze", "shake": 0.0,
	},
	{
		"a": &"lava", "b": &"liquid_nitrogen",
		"consume_a": 8, "consume_b": 8,
		"block_at": "a", "block": [&"obsidian", &"basalt", &"stone"],
		"particles": &"steam", "amount": 30, "sound": &"hiss", "shake": 0.45,
	},
	{
		"a": &"lava", "b": &"fuel",
		"consume_a": 8, "consume_b": 8,
		"block_at": "", "explode": 3.0,
		"particles": &"explosion", "amount": 32, "sound": &"explosion", "shake": 1.1,
	},
	{
		"a": &"lava", "b": &"tar",
		"consume_a": 0, "consume_b": 8, "convert_b": &"lava",
		"particles": &"smoke", "amount": 14, "sound": &"fire_crackle",
	},
	{
		"a": &"lava", "b": &"slime",
		"consume_a": 0, "consume_b": 8,
		"particles": &"smoke", "amount": 10, "sound": &"hiss",
	},
	{
		"a": &"lava", "b": &"poison",
		"consume_a": 0, "consume_b": 8,
		"particles": &"smoke", "amount": 10, "sound": &"hiss",
	},
	{
		"a": &"acid", "b": &"water",
		"consume_a": 2, "consume_b": 1,
		"particles": &"bubble", "amount": 5, "sound": &"hiss",
	},
	{
		"a": &"acid", "b": &"healing_water",
		"consume_a": 8, "consume_b": 2,
		"particles": &"bubble", "amount": 8, "sound": &"hiss",
	},
	{
		"a": &"poison", "b": &"healing_water",
		"consume_a": 8, "consume_b": 1,
		"particles": &"sparkle", "amount": 8, "sound": &"chime",
	},
	{
		"a": &"fuel", "b": &"liquid_nitrogen",
		"consume_a": 4, "consume_b": 4,
		"particles": &"frost", "amount": 6,
	},
]

## Liquid touching a *solid* block. Checked once per cell update, gated by
## `chance` so it reads as a gradual process rather than a pop.
##
##   match_block : explicit block names
##   match_tag   : any block carrying this tag
##   match_flag  : any block whose BlockType boolean field is true
##   result      : preference list for the replacement block (&"air" allowed)
const BLOCK_REACTIONS := [
	{
		"liquid": &"lava", "match_flag": "flammable",
		"result": [&"fire", &"air"], "chance": 0.12,
		"particles": &"flame", "amount": 6, "sound": &"fire_crackle",
	},
	{
		"liquid": &"lava", "match_block": [&"ice", &"packed_ice", &"snow", &"snow_block"],
		"result": [&"water"], "chance": 0.5,
		"particles": &"steam", "amount": 8, "sound": &"hiss",
	},
	{
		"liquid": &"water", "match_block": [&"fire", &"ember"],
		"result": [&"air"], "chance": 1.0, "consume": 1,
		"particles": &"steam", "amount": 10, "sound": &"hiss",
	},
	{
		"liquid": &"liquid_nitrogen", "match_block": [&"fire", &"ember"],
		"result": [&"air"], "chance": 1.0, "consume": 1,
		"particles": &"frost", "amount": 8, "sound": &"freeze",
	},
	{
		"liquid": &"liquid_nitrogen", "match_block": [&"grass", &"dirt"],
		"result": [&"permafrost", &"snow_block", &"ice"], "chance": 0.05,
		"particles": &"frost", "amount": 4,
	},
	{
		"liquid": &"healing_water", "match_block": [&"dirt"],
		"result": [&"grass"], "chance": 0.02,
		"particles": &"sparkle", "amount": 3,
	},
]

# ---------------------------------------------------------------- lazy caches
static var _merged: Dictionary = {}       ## StringName -> full parameter dict
static var _by_block: Dictionary = {}     ## block id -> full parameter dict
static var _by_block_name: Dictionary = {}## block StringName -> liquid StringName
static var _block_ids: Dictionary = {}    ## StringName -> block id (or AIR)
static var _pairs: Dictionary = {}        ## "a|b" -> rule (both orders stored)
static var _block_rules: Dictionary = {}  ## liquid name -> Array of rules
static var _built := false


## Drop every cached block-id lookup. Call after the block registry changes.
static func invalidate() -> void:
	_merged.clear()
	_by_block.clear()
	_by_block_name.clear()
	_block_ids.clear()
	_pairs.clear()
	_block_rules.clear()
	_built = false


static func _build() -> void:
	if _built:
		return
	_built = true
	for a: StringName in TABLE:
		var row: Dictionary = TABLE[a]
		var full := {}
		for k: String in DEFAULTS:
			full[k] = DEFAULTS[k]
		for k2: String in row:
			full[k2] = row[k2]
		full["name"] = a
		if not row.has("block"):
			full["block"] = a
		_merged[a] = full
		_by_block_name[StringName(full["block"])] = a
	for rule: Dictionary in REACTIONS:
		_pairs[_key(rule["a"], rule["b"])] = rule
		_pairs[_key(rule["b"], rule["a"])] = rule
	for rule2: Dictionary in BLOCK_REACTIONS:
		var ln: StringName = rule2["liquid"]
		if not _block_rules.has(ln):
			_block_rules[ln] = []
		(_block_rules[ln] as Array).append(rule2)


static func _key(a: StringName, b: StringName) -> String:
	return String(a) + "|" + String(b)


# ------------------------------------------------------------------- lookups
## Every liquid StringName this module knows about, in table order.
static func all_names() -> Array:
	_build()
	return _merged.keys()


static func is_known(liquid: StringName) -> bool:
	_build()
	return _merged.has(liquid) or _by_block_name.has(liquid)


## Canonical liquid name: accepts either the liquid key (`&"poison"`) or the
## block name that carries it (`&"toxic_water"`), so callers never have to know
## which vocabulary they are holding.
static func canonical(liquid: StringName) -> StringName:
	_build()
	if _merged.has(liquid):
		return liquid
	return StringName(_by_block_name.get(liquid, liquid))


## Full parameter dictionary for a liquid. Never empty: unknown liquids get the
## defaults so the solver can keep running.
static func of(liquid: StringName) -> Dictionary:
	_build()
	var d: Dictionary = _merged.get(canonical(liquid), {})
	return d if not d.is_empty() else DEFAULTS


## The liquid this one falls back to for reactions, or `&""`.
static func like_of(liquid: StringName) -> StringName:
	return StringName(of(liquid).get("like", &""))


## Parameters for whatever liquid a block id carries, or `{}` when the block is
## not a liquid this module manages.
static func for_block(block_id: int) -> Dictionary:
	if block_id == Const.AIR:
		return {}
	if _by_block.has(block_id):
		return _by_block[block_id]
	_build()
	var bt := Blocks.get_type(block_id)
	var found: Dictionary = {}
	if bt != null and bt.liquid:
		for a: StringName in _merged:
			if StringName((_merged[a] as Dictionary)["block"]) == bt.name:
				found = _merged[a]
				break
		if found.is_empty():
			# A liquid block from another content pack: give it water physics so
			# it still flows instead of sitting there as a solid-looking blob.
			found = of(&"water")
	_by_block[block_id] = found
	return found


## Block id backing a liquid, or `Const.AIR` when that block does not exist.
static func block_id(liquid: StringName) -> int:
	if _block_ids.has(liquid):
		return _block_ids[liquid]
	_build()
	var id := Const.AIR
	if is_known(liquid):
		var bn := StringName(of(liquid).get("block", liquid))
		if Blocks.has(bn):
			id = Blocks.id(bn)
	elif Blocks.has(liquid) and Blocks.is_liquid(Blocks.id(liquid)):
		id = Blocks.id(liquid)      ## a liquid block from another content pack
	_block_ids[liquid] = id
	return id


## Liquid name for a block id, or `&""`.
static func name_of_block(block_id: int) -> StringName:
	var p := for_block(block_id)
	return StringName(p.get("name", &"")) if not p.is_empty() else &""


## First registered block from `names`; `Const.AIR` when none exist.
## `&"air"` in the list always resolves.
static func resolve_block(names: Array, fallback: StringName = &"") -> int:
	for n: StringName in names:
		if n == &"air":
			return Const.AIR
		if Blocks.has(n):
			return Blocks.id(n)
	if fallback != &"" and Blocks.has(fallback):
		return Blocks.id(fallback)
	return -1


# ----------------------------------------------------------------- reactions
## Reaction between two liquids, re-oriented so the keys read from `self`'s
## point of view. Returns `{}` when the pair is inert.
##
## Result keys: `consume_self`, `consume_other`, `block_side` ("self"/"other"/""),
## `block`, `weak_block`, `convert_self`, `convert_other`, `explode`,
## `particles`, `amount`, `sound`, `shake`.
static func reaction(self_liquid: StringName, other_liquid: StringName) -> Dictionary:
	_build()
	var a := canonical(self_liquid)
	var b := canonical(other_liquid)
	if a == b:
		return {}
	var rule: Dictionary = _pairs.get(_key(a, b), {})
	if rule.is_empty():
		# Retry through the `like` fallbacks: salt water reacts as water,
		# molten core as lava, without duplicating a single row.
		var la := like_of(a)
		var lb := like_of(b)
		if la != &"":
			rule = _pairs.get(_key(la, b), {})
			if not rule.is_empty():
				a = la
		if rule.is_empty() and lb != &"":
			rule = _pairs.get(_key(a, lb), {})
			if not rule.is_empty():
				b = lb
		if rule.is_empty() and la != &"" and lb != &"" and la != lb:
			rule = _pairs.get(_key(la, lb), {})
			if not rule.is_empty():
				a = la
				b = lb
		if rule.is_empty():
			return {}
	var self_is_a: bool = StringName(rule["a"]) == a
	var side: String = String(rule.get("block_at", ""))
	var block_side := ""
	if side == "a":
		block_side = "self" if self_is_a else "other"
	elif side == "b":
		block_side = "other" if self_is_a else "self"
	return {
		"consume_self": int(rule.get("consume_a" if self_is_a else "consume_b", 0)),
		"consume_other": int(rule.get("consume_b" if self_is_a else "consume_a", 0)),
		"block_side": block_side,
		"block": rule.get("block", []),
		"weak_block": rule.get("weak_block", rule.get("block", [])),
		"convert_self": StringName(rule.get("convert_a" if self_is_a else "convert_b", &"")),
		"convert_other": StringName(rule.get("convert_b" if self_is_a else "convert_a", &"")),
		"explode": float(rule.get("explode", 0.0)),
		"particles": StringName(rule.get("particles", &"")),
		"amount": int(rule.get("amount", 8)),
		"sound": StringName(rule.get("sound", &"")),
		"shake": float(rule.get("shake", 0.0)),
	}


## True when any liquid/liquid rule mentions this liquid — lets the solver skip
## the neighbour scan entirely for inert liquids.
static func is_reactive(liquid: StringName) -> bool:
	_build()
	var a := canonical(liquid)
	var la := like_of(a)
	for k: String in _pairs:
		if k.begins_with(String(a) + "|"):
			return true
		if la != &"" and k.begins_with(String(la) + "|"):
			return true
	return false


## Rule for `liquid` touching the solid block `block_id`, or `{}`.
static func block_reaction(liquid: StringName, block_id: int) -> Dictionary:
	_build()
	var a := canonical(liquid)
	var rules: Array = _block_rules.get(a, [])
	if rules.is_empty():
		rules = _block_rules.get(like_of(a), [])
	if rules.is_empty() or block_id == Const.AIR:
		return {}
	var bt := Blocks.get_type(block_id)
	if bt == null or not bt.breakable:
		return {}
	for rule: Dictionary in rules:
		if rule.has("match_block") and (rule["match_block"] as Array).has(bt.name):
			return rule
		if rule.has("match_tag") and bt.has_tag(StringName(rule["match_tag"])):
			return rule
		if rule.has("match_flag") and bool(bt.get(String(rule["match_flag"]))):
			return rule
	return {}


## True when `liquid` has at least one solid-block rule or dissolves blocks.
static func touches_blocks(liquid: StringName) -> bool:
	_build()
	var a := canonical(liquid)
	if _block_rules.has(a) or float(of(a).get("dissolve", 0.0)) > 0.0:
		return true
	var la := like_of(a)
	return la != &"" and _block_rules.has(la)


# ------------------------------------------------------------------ helpers
## Relative buoyancy of `liquid` for an entity of density 1.0.
static func buoyancy_of(block_id: int) -> float:
	var p := for_block(block_id)
	return float(p.get("buoyancy", 1.0)) if not p.is_empty() else 1.0


## Screen tint for a fully submerged camera.
static func fog_of(block_id: int) -> Color:
	var p := for_block(block_id)
	return p.get("fog", Color(0, 0, 0, 0)) if not p.is_empty() else Color(0, 0, 0, 0)
