## Role registry. One shared, stateless instance per role id.
##
## Add a role by writing a [NpcRole] subclass beside this file and listing it in
## [constant SCRIPTS] — nothing else in the codebase needs to change.
class_name NpcRoles
extends RefCounted

const SCRIPTS := {
	&"villager":   "res://entities/npc/roles/villager.gd",
	&"merchant":   "res://entities/npc/roles/merchant.gd",
	&"innkeeper":  "res://entities/npc/roles/innkeeper.gd",
	&"blacksmith": "res://entities/npc/roles/blacksmith.gd",
	&"doctor":     "res://entities/npc/roles/doctor.gd",
	&"guard":      "res://entities/npc/roles/guard.gd",
	&"scientist":  "res://entities/npc/roles/scientist.gd",
	&"crew":       "res://entities/npc/roles/crew_recruit.gd",
	&"trader":     "res://entities/npc/roles/trader.gd",
}

## Aliases the structure agent's markers might use instead of the canonical ids.
const ALIASES := {
	&"shopkeeper": &"merchant", &"trader_stall": &"merchant", &"vendor": &"merchant",
	&"shop": &"merchant", &"store": &"merchant",
	&"barkeep": &"innkeeper", &"innkeep": &"innkeeper", &"tavern": &"innkeeper",
	&"bartender": &"innkeeper", &"inn": &"innkeeper",
	&"smith": &"blacksmith", &"forge": &"blacksmith", &"weaponsmith": &"blacksmith",
	&"armorer": &"blacksmith", &"armourer": &"blacksmith",
	&"medic": &"doctor", &"healer": &"doctor", &"nurse": &"doctor",
	&"apothecary": &"doctor", &"clinic": &"doctor",
	&"soldier": &"guard", &"sentry": &"guard", &"watchman": &"guard",
	&"warrior": &"guard", &"defender": &"guard",
	&"researcher": &"scientist", &"scholar": &"scientist", &"sage": &"scientist",
	&"engineer": &"scientist", &"lab": &"scientist",
	&"recruit": &"crew", &"crewmate": &"crew", &"hireling": &"crew",
	&"companion": &"crew", &"follower": &"crew",
	&"wanderer": &"trader", &"peddler": &"trader", &"caravan": &"trader",
	&"farmer": &"villager", &"peasant": &"villager", &"child": &"villager",
	&"citizen": &"villager", &"npc": &"villager", &"none": &"villager",
	# Roles named by worldgen/structures/struct_markers.gd.
	&"questgiver": &"villager", &"hermit": &"villager", &"prisoner": &"villager",
	&"boss_npc": &"guard", &"npc_spawn": &"villager", &"villager_spawn": &"villager",
	&"tinker": &"blacksmith", &"cook": &"innkeeper", &"brewer": &"innkeeper",
	&"herbalist": &"doctor", &"astronomer": &"scientist", &"archivist": &"scientist",
}

## Weighted composition of a village, in the order roles are assigned. Index 0
## is the first NPC placed, and the tail repeats.
const VILLAGE_COMPOSITION: Array[StringName] = [
	&"merchant", &"guard", &"innkeeper", &"villager", &"blacksmith",
	&"villager", &"doctor", &"guard", &"villager", &"scientist",
	&"crew", &"villager", &"villager", &"guard", &"villager",
]

static var _instances: Dictionary = {}


static func get_role(role_id: StringName) -> NpcRole:
	var key := canonical(role_id)
	if _instances.has(key):
		return _instances[key]
	var path := String(SCRIPTS.get(key, SCRIPTS[&"villager"]))
	var scr := load(path) as Script
	var inst: NpcRole = null
	if scr != null:
		inst = scr.new() as NpcRole
	if inst == null:
		inst = NpcRole.new()
	_instances[key] = inst
	return inst


## Maps aliases and unknown ids onto a real role.
static func canonical(role_id: StringName) -> StringName:
	if SCRIPTS.has(role_id):
		return role_id
	var lower := StringName(String(role_id).to_lower().strip_edges().replace(" ", "_"))
	if SCRIPTS.has(lower):
		return lower
	if ALIASES.has(lower):
		return ALIASES[lower]
	return &"villager"


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in SCRIPTS:
		out.append(StringName(k))
	return out


static func exists(role_id: StringName) -> bool:
	return SCRIPTS.has(role_id) or ALIASES.has(role_id)


## Deterministic role for the Nth villager of a settlement. Higher-tier planets
## get their specialists sooner; a hamlet of three is a merchant, a guard and an
## innkeeper, which is exactly the trio a player wants to find.
static func for_index(index: int, tier: int, rng: RandomNumberGenerator) -> StringName:
	if index < VILLAGE_COMPOSITION.size():
		var role := VILLAGE_COMPOSITION[index]
		# Scientists only staff settlements on planets worth studying.
		if role == &"scientist" and tier < 2 and rng.randf() < 0.6:
			return &"villager"
		return role
	return &"guard" if rng.randf() < 0.25 else &"villager"
