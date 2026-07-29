## Standing with individuals and with groups.
##
## Two independent ledgers:
## [b]personal[/b] — keyed by `npc_id`, how one specific villager feels about you.
## [b]faction[/b]  — keyed by village id, species id or &"world", how a whole
##                   group feels. Personal standing drifts toward the faction
##                   value it belongs to, so being loved in Greenhollow makes new
##                   Greenhollow villagers start friendly.
##
## Pure static state so dialogue conditions, quest rewards and NPC AI can all
## reach it without a node reference. Persisted through [code]Quests.save_state()[/code].
class_name NpcReputation
extends RefCounted

const MIN := -100.0
const MAX := 100.0

## Named bands, used for dialogue gating and greeting selection.
const BAND_HOSTILE := 0
const BAND_COLD := 1
const BAND_NEUTRAL := 2
const BAND_WARM := 3
const BAND_TRUSTED := 4
const BAND_NAMES: Array[String] = ["Hostile", "Wary", "Neutral", "Friendly", "Trusted"]
const BAND_THRESHOLDS: Array[float] = [-100.0, -40.0, -10.0, 25.0, 65.0]

static var _personal: Dictionary = {}   ## StringName -> float
static var _faction: Dictionary = {}    ## StringName -> float
## npc_id -> faction id, so personal values can inherit a group baseline.
static var _membership: Dictionary = {}


# ---------------------------------------------------------------- personal
static func of_npc(npc_id: StringName) -> float:
	if _personal.has(npc_id):
		return float(_personal[npc_id])
	return of_faction(StringName(_membership.get(npc_id, &"world"))) * 0.5


static func set_npc(npc_id: StringName, value: float) -> void:
	_personal[npc_id] = clampf(value, MIN, MAX)


## Returns the new value. Also bleeds a tenth of the change into the NPC's
## faction — treating one villager well is noticed by the village.
static func adjust_npc(npc_id: StringName, delta: float) -> float:
	var v := clampf(of_npc(npc_id) + delta, MIN, MAX)
	_personal[npc_id] = v
	var fac := StringName(_membership.get(npc_id, &""))
	if fac != &"" and absf(delta) >= 1.0:
		adjust_faction(fac, delta * 0.1)
	return v


static func register_member(npc_id: StringName, faction: StringName) -> void:
	if faction != &"":
		_membership[npc_id] = faction


# ----------------------------------------------------------------- faction
static func of_faction(faction: StringName) -> float:
	return float(_faction.get(faction, 0.0))


static func set_faction(faction: StringName, value: float) -> void:
	_faction[faction] = clampf(value, MIN, MAX)


static func adjust_faction(faction: StringName, delta: float) -> float:
	var v := clampf(of_faction(faction) + delta, MIN, MAX)
	_faction[faction] = v
	return v


## Convenience used by quest rewards: applies to whichever ledger already knows
## the key, defaulting to faction.
static func adjust(key: StringName, delta: float) -> float:
	if _personal.has(key) or _membership.has(key):
		return adjust_npc(key, delta)
	return adjust_faction(key, delta)


static func value_of(key: StringName) -> float:
	if _personal.has(key) or _membership.has(key):
		return of_npc(key)
	return of_faction(key)


# ------------------------------------------------------------------- bands
static func band_of(value: float) -> int:
	var b := BAND_HOSTILE
	for i in BAND_THRESHOLDS.size():
		if value >= BAND_THRESHOLDS[i]:
			b = i
	return b


static func band_name(value: float) -> String:
	return BAND_NAMES[band_of(value)]


static func is_hostile(npc_id: StringName) -> bool:
	return of_npc(npc_id) <= BAND_THRESHOLDS[BAND_COLD]


static func will_trade(npc_id: StringName) -> bool:
	return of_npc(npc_id) > BAND_THRESHOLDS[BAND_COLD]


## Merchants shade their prices by standing: 1.25x when wary, 0.85x when trusted.
static func price_multiplier(npc_id: StringName) -> float:
	return clampf(1.05 - of_npc(npc_id) * 0.002, 0.85, 1.25)


static func clear() -> void:
	_personal.clear()
	_faction.clear()
	_membership.clear()


# ------------------------------------------------------------ serialisation
static func save_state() -> Dictionary:
	var p := {}
	for k: Variant in _personal:
		p[String(k)] = _personal[k]
	var f := {}
	for k: Variant in _faction:
		f[String(k)] = _faction[k]
	var m := {}
	for k: Variant in _membership:
		m[String(k)] = String(_membership[k])
	return {"personal": p, "faction": f, "member": m}


static func load_state(d: Dictionary) -> void:
	clear()
	for k: Variant in d.get("personal", {}):
		_personal[StringName(k)] = float(d["personal"][k])
	for k: Variant in d.get("faction", {}):
		_faction[StringName(k)] = float(d["faction"][k])
	for k: Variant in d.get("member", {}):
		_membership[StringName(k)] = StringName(d["member"][k])
