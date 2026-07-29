## Deterministic name, race and village-name generation.
##
## Every villager's identity is a pure function of (world seed, world position),
## so the same planet always produces the same Greenhollow with the same baker
## in it — no state to save, and two clients generating the same world agree.
class_name NpcNames
extends RefCounted

## The seven playable races, which are also the seven NPC silhouettes.
const RACES: Array[StringName] = [
	&"human", &"apex", &"avian", &"floran", &"glitch", &"hylotl", &"novakid",
]

const _GIVEN := {
	&"human": ["Mara", "Ferro", "Cass", "Elin", "Tobin", "Wren", "Dov", "Salla",
		"Ivo", "Petra", "Hale", "Nessa", "Corin", "Juno", "Brack", "Alma"],
	&"apex": ["Vex", "Grath", "Umber", "Skoll", "Barra", "Krell", "Orsa",
		"Thane", "Muri", "Zharn", "Bek", "Ollo"],
	&"avian": ["Kiri", "Solen", "Nazu", "Aetha", "Piyo", "Reth", "Ovan",
		"Sil", "Tama", "Kess", "Aviel", "Ruka"],
	&"floran": ["Thornsap", "Bloomss", "Rootly", "Petalsss", "Vinn", "Sappho",
		"Husk", "Greensss", "Bramble", "Nettla", "Podd", "Fernsss"],
	&"glitch": ["Curator", "Sir Alder", "Dame Vole", "Cog", "Reeve", "Marshal",
		"Ovid", "Squire Penn", "Abbot Kell", "Herald Vim", "Warden Bit"],
	&"hylotl": ["Sennet", "Kaimo", "Ryu", "Oshi", "Tenno", "Umi", "Sable",
		"Nagi", "Kuro", "Isen", "Mizu", "Hara"],
	&"novakid": ["Ember", "Colt", "Dusty", "Quill", "Slate", "Rowan", "Boone",
		"Cinder", "Ash", "Vega", "Flint", "Marigold"],
}

const _FAMILY := {
	&"human": ["Fen", "Kade", "Oro", "Villiers", "Stane", "Ashworth", "Vane",
		"Cray", "Bellamy", "Roke"],
	&"apex": ["of Nine Fists", "Ironbrow", "Cragg", "the Unbanned", "Molt",
		"Stonepalm"],
	&"avian": ["Skyward", "of the Third Nest", "Featherfall", "Sunwing",
		"Highspire", "Windmoult"],
	&"floran": ["of the Wet Grove", "Greenblade", "Thicket", "of Rot Hollow",
		"Sunchaser", "Chewsss-Bone"],
	&"glitch": ["the Archivist", "of Waypoint Six", "the Dutiful", "Errant",
		"of the Quiet Forge", "the Recompiled"],
	&"hylotl": ["Rho", "Isezaki", "of the Low Tide", "Kanmuri", "Deepmoor",
		"Shallowbrook"],
	&"novakid": ["Nine-Star", "Brandmark", "of the Long Burn", "Quickdraw",
		"Emberline", "Two-Suns"],
}

## Village name halves. Combined into "Greenhollow", "Ashreach", "Fenmoor"...
const _VILLAGE_A := ["Green", "Ash", "Fen", "Stone", "Salt", "Bright", "Rust",
	"Amber", "Quiet", "Long", "Deep", "Iron", "Pale", "Copper", "Wither", "Glass"]
const _VILLAGE_B := ["hollow", "reach", "moor", "ford", "watch", "barrow",
	"cross", "gate", "rest", "fall", "stead", "mere", "shelf", "wick"]

## Crew members get a specialisation title.
const CREW_SKILLS: Array[StringName] = [
	&"engineer", &"medic", &"gunner", &"chemist", &"janitor", &"navigator",
	&"tailor", &"mechanic", &"cook", &"surveyor",
]


## A stable 64-bit hash for a (seed, position, salt) triple.
static func hash_at(world_seed: int, pos: Vector3i, salt: int = 0) -> int:
	var h := world_seed * 6364136223846793005
	h = (h ^ (pos.x * 73856093)) * 1099511628211
	h = (h ^ (pos.y * 19349663)) * 1099511628211
	h = (h ^ (pos.z * 83492791)) * 1099511628211
	h = (h ^ (salt * 2654435761)) * 1099511628211
	return absi(h)


static func rng_at(world_seed: int, pos: Vector3i, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash_at(world_seed, pos, salt)
	return r


## Picks a race, weighted so a village mostly shares a species with a minority
## of visitors — which is what makes Starbound settlements read as places.
static func race_for(rng: RandomNumberGenerator, village_race: StringName = &"") -> StringName:
	if village_race != &"" and rng.randf() < 0.72:
		return village_race
	return RACES[rng.randi_range(0, RACES.size() - 1)]


static func full_name(rng: RandomNumberGenerator, race: StringName) -> String:
	var given := _pick(rng, _GIVEN.get(race, _GIVEN[&"human"]) as Array)
	if rng.randf() < 0.55:
		var family := _pick(rng, _FAMILY.get(race, _FAMILY[&"human"]) as Array)
		if family.begins_with("of ") or family.begins_with("the "):
			return "%s %s" % [given, family]
		return "%s %s" % [given, family]
	return given


static func village_name(rng: RandomNumberGenerator) -> String:
	return "%s%s" % [_pick(rng, _VILLAGE_A), _pick(rng, _VILLAGE_B)]


static func village_id(rng: RandomNumberGenerator) -> StringName:
	return StringName(village_name(rng).to_snake_case())


static func crew_skill(rng: RandomNumberGenerator) -> StringName:
	return CREW_SKILLS[rng.randi_range(0, CREW_SKILLS.size() - 1)]


## Unique, stable id: "npc_<race>_<hash36>". Used as the dialogue/reputation key.
static func npc_id(world_seed: int, pos: Vector3i, race: StringName) -> StringName:
	var h := hash_at(world_seed, pos, 977)
	return StringName("npc_%s_%s" % [race, String.num_int64(h % 2821109907456, 36)])


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	if list.is_empty():
		return "Someone"
	return String(list[rng.randi_range(0, list.size() - 1)])
