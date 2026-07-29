## Monster pools: the bridge between the structures agent's *logical* spawner
## keys and this bestiary's concrete species.
##
## `StructMarkers.spawner("cave_crawler", ...)` writes a pool name, not a
## species — deliberately, so structures never have to know what lives on this
## planet. Everything here is best-effort: an unrecognised pool falls back to
## suffix matching (`floran_ward`, `apex_sentinel`, ...) and finally to a
## plain biome-appropriate roll, so a new structure theme can never produce an
## empty room.
class_name MobPools
extends RefCounted

## Exact pool names the structure generators currently emit.
const POOLS: Dictionary = {
	&"cave_crawler": [&"pebble_grub", &"thorn_creeper", &"crystal_skitter", &"chasm_leaper", &"mire_lurker"],
	&"undead": [&"bone_stalker", &"chest_mimic", &"hex_caster", &"rust_tick"],
	&"bandit": [&"rust_tick", &"acid_spitter", &"blast_pod", &"thorn_creeper"],
	&"scavenger": [&"rust_tick", &"dune_scarab", &"boulder_beetle", &"mortar_bug"],
	&"floran_hunter": [&"thorn_creeper", &"mire_lurker", &"acid_spitter", &"spore_turret"],
	&"fire_elemental": [&"ember_wisp", &"magma_crawler", &"blast_pod"],
	&"sky_wraith": [&"void_flitter", &"plane_wraith", &"talon_diver"],
	&"avian_guardian": [&"talon_diver", &"sky_ray", &"ice_lancer"],
	&"cistern_lurker": [&"mire_lurker", &"bog_serpent", &"abyss_eel", &"miasma_cloud"],
	&"ancient_guardian": [&"bulwark_drone", &"sapper_pod", &"hex_caster"],
	&"crystal_guardian": [&"crystal_skitter", &"bulwark_drone", &"flak_bloom"],
	&"swarm": [&"bitegnat_swarm", &"dusk_moth", &"gasbag_floater"],
	&"critters": [&"meadow_hopper", &"glowbug", &"dune_scarab", &"moon_hare"],
}

## Theme-prefixed pools (`floran_ward`, `glitch_sentinel`, `apex_stalker`, ...)
## are matched on their suffix.
const SUFFIXES: Dictionary = {
	"_ward": [&"bulwark_drone", &"flak_bloom", &"hex_caster"],
	"_sentinel": [&"bulwark_drone", &"rust_tick", &"mortar_bug"],
	"_stalker": [&"bone_stalker", &"mire_lurker", &"chest_mimic"],
	"_echo": [&"plane_wraith", &"void_flitter"],
	"_guardian": [&"boulder_beetle", &"bulwark_drone", &"ice_lancer"],
	"_hunter": [&"frost_hound", &"talon_diver", &"thorn_creeper"],
	"_lurker": [&"mire_lurker", &"abyss_eel", &"chest_mimic"],
	"_crawler": [&"pebble_grub", &"magma_crawler", &"crystal_skitter"],
	"_elemental": [&"ember_wisp", &"ice_lancer", &"miasma_cloud"],
	"_priest": [&"hex_caster", &"mender_mote"],
	"_wraith": [&"plane_wraith", &"void_flitter"],
}

## Structure boss names mapped onto the four bosses this module implements.
const BOSS_MAP: Dictionary = {
	&"avian_sky_priest": &"boss_hive_queen",
	&"crystal_seraph": &"boss_fourfold",
}

const BOSS_KEYWORDS: Array = [
	["minotaur", &"boss_stone_titan"],
	["titan", &"boss_stone_titan"],
	["colossus", &"boss_stone_titan"],
	["golem", &"boss_stone_titan"],
	["queen", &"boss_hive_queen"],
	["hive", &"boss_hive_queen"],
	["brood", &"boss_hive_queen"],
	["sky", &"boss_hive_queen"],
	["magma", &"boss_magma_heart"],
	["fire", &"boss_magma_heart"],
	["forge", &"boss_magma_heart"],
	["heart", &"boss_magma_heart"],
	["seraph", &"boss_fourfold"],
	["wraith", &"boss_fourfold"],
	["ancient", &"boss_fourfold"],
	["void", &"boss_fourfold"],
	["mirror", &"boss_fourfold"],
]


## Resolve a pool key to one concrete species id, or `&""` when nothing fits.
##
## `ctx` is the same dictionary `MobSpeciesDB.pick` takes (biome, threat, night,
## light, underwater, underground).
static func resolve(pool: StringName, ctx: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var candidates: Array = _candidates_for(pool)
	# Prefer pool members that actually suit the tier we were asked for.
	var tier: int = int(ctx.get("threat", 1))
	var best: Array[StringName] = []
	var fallback: Array[StringName] = []
	for sid: StringName in candidates:
		var sp := MobSpeciesDB.get_species(sid)
		if sp == null:
			continue
		fallback.append(sid)
		if absi(sp.tier - tier) <= 2:
			best.append(sid)
	var pick_from: Array[StringName] = best if not best.is_empty() else fallback
	if not pick_from.is_empty():
		return pick_from[rng.randi() % pick_from.size()]
	var sp2: MobSpecies = MobSpeciesDB.pick(ctx, rng)
	return sp2.id if sp2 != null else &""


static func _candidates_for(pool: StringName) -> Array:
	if POOLS.has(pool):
		return POOLS[pool]
	var s := String(pool)
	for suffix: String in SUFFIXES:
		if s.ends_with(suffix):
			return SUFFIXES[suffix]
	# A pool named after a species outright is perfectly legal.
	if MobSpeciesDB.has(pool):
		return [pool]
	return []


## Map a structure's boss name onto one of the implemented boss fights.
static func resolve_boss(boss_id: StringName) -> StringName:
	if MobBoss.is_boss(boss_id):
		return boss_id
	if BOSS_MAP.has(boss_id):
		return BOSS_MAP[boss_id]
	var s := String(boss_id).to_lower()
	for entry: Array in BOSS_KEYWORDS:
		if s.contains(String(entry[0])):
			return entry[1]
	return &"boss_stone_titan"
