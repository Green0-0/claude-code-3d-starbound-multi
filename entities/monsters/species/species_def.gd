## One monster species — a pure data definition, built with a fluent builder so
## the content files in this directory read like a bestiary rather than code.
##
## A species never holds runtime state; `MobBase` copies what it needs on spawn
## and scales the numbers by the planet's threat level.
class_name MobSpecies
extends RefCounted

# --------------------------------------------------------------- locomotion
const LOCO_WALK := &"walk"        ## gravity, jumps, uses ground A*
const LOCO_FLY := &"fly"          ## free 2D flight in the plane
const LOCO_HOVER := &"hover"      ## floats, bobs, drifts slowly
const LOCO_SWIM := &"swim"        ## needs liquid, flounders on land
const LOCO_AMPHIBIOUS := &"amphibious"
const LOCO_STATIC := &"static"    ## rooted (turret plants, mimics)
const LOCO_BURROW := &"burrow"    ## travels inside solid ground

# ------------------------------------------------------------------ families
const FAM_GROUND := &"ground"
const FAM_FLYING := &"flying"
const FAM_AQUATIC := &"aquatic"
const FAM_RANGED := &"ranged"
const FAM_SPECIAL := &"special"
const FAM_CRITTER := &"critter"
const FAM_BOSS := &"boss"

## Every biome StringName the terrain agent generates. Species declare a subset.
const ALL_BIOMES: Array[StringName] = [
	&"forest", &"savannah", &"desert", &"tundra", &"snow", &"jungle", &"swamp",
	&"ocean", &"alien", &"toxic", &"volcanic", &"midnight", &"garden", &"moon",
	&"barren", &"scorched", &"bioluminescent", &"crystal_caverns",
	&"mushroom_fields", &"ancient_ruins",
]

## The short spellings this bestiary was written with, plus the aliases
## `worldgen/biome_table.gd` folds down, mapped onto the canonical keys. Every
## biome that crosses a module boundary goes through `canon_biome` so a rename
## on either side degrades to "wrong biome" rather than "no monsters at all".
const BIOME_ALIASES: Dictionary = {
	&"crystal": &"crystal_caverns",
	&"crystals": &"crystal_caverns",
	&"mushroom": &"mushroom_fields",
	&"fungal": &"mushroom_fields",
	&"ruins": &"ancient_ruins",
	&"ancient": &"ancient_ruins",
	&"plains": &"forest",
	&"meadow": &"forest",
	&"grassland": &"forest",
	&"magma": &"volcanic",
	&"lunar": &"moon",
	&"sea": &"ocean",
}


## Normalise any biome spelling to a canonical key.
static func canon_biome(b: StringName) -> StringName:
	return BIOME_ALIASES.get(b, b)


## The bestiary names its drops for readability; the item registry is owned by
## another agent and may spell them differently (or not have them yet). Each
## logical drop maps to a preference list, and `resolve_item` returns the first
## one that actually exists — so a loot table degrades gracefully instead of
## silently dropping nothing.
const LOOT_ALIASES: Dictionary = {
	&"monster_hide": [&"hide", &"leather", &"monster_fur"],
	&"slime": [&"slime_glob", &"adhesive"],
	&"venom_sac": [&"venom_gland"],
	&"bone_fragment": [&"bone_shard", &"bone"],
	&"ice_shard": [&"ice_crystal", &"crystal_shard"],
	&"ember_core": [&"sulphur", &"core_fragment", &"coal"],
	&"spore_sac": [&"plant_matter", &"cave_mushroom", &"plant_fibre"],
	&"void_dust": [&"void_residue", &"cosmic_dust", &"ectoplasm"],
	&"circuit": [&"circuit_board", &"copper_wire"],
	&"crystal_shard": [&"crystal_shard", &"quartz"],
	&"glow_gland": [&"glow_gland", &"glow_dust"],
	&"chitin": [&"chitin"],
	&"feather": [&"feather"],
	&"raw_meat": [&"raw_meat", &"raw_alien_meat"],
	&"ancient_relic": [&"ancient_relic", &"ancient_artifact", &"ancient_fragment"],
	&"pixels": [&"pixels", &"pixel", &"currency"],
}


## First registered item id for a logical drop name, or `&""` if none exists.
static func resolve_item(logical: StringName) -> StringName:
	if Items.has(logical):
		return logical
	for alt: StringName in LOOT_ALIASES.get(logical, []):
		if Items.has(alt):
			return alt
	return &""

# ------------------------------------------------------------------ identity
var id: StringName = &""
var display_name: String = "Creature"
var family: StringName = FAM_GROUND
var locomotion: StringName = LOCO_WALK
## Behaviour-tree profile name understood by `MobBrain.build`.
var brain: StringName = &"melee"
## Optional special-behaviour id understood by `MobBehaviour.create`.
var behaviour: StringName = &""
## 0 = harmless critter … 5 = end-game horror. Gates where it can spawn.
var tier: int = 1
var biomes: Array[StringName] = []
var faction: StringName = &"hostile"
var description: String = ""

# -------------------------------------------------------------------- combat
var base_health: float = 30.0
var base_damage: float = 6.0
var move_speed: float = 4.0
var run_multiplier: float = 1.7
var jump_speed: float = 11.0
var element: String = Const.ELEM_PHYSICAL
var knockback_resist: float = 0.0        ## 0 = full knockback, 1 = immovable
var armour: float = 0.0                  ## flat damage subtracted
var resistances: Dictionary = {}         ## element -> multiplier (1.0 = normal)
var touch_damage: float = 0.0            ## contact damage per hit, 0 = none
var attack_range: float = 1.6
var attack_cooldown: float = 1.1
var attack_windup: float = 0.35
var projectile: StringName = &""         ## combat agent's projectile id, if ranged
var projectile_speed: float = 18.0

# -------------------------------------------------------------------- senses
var box_size: Vector3 = Vector3(0.8, 0.9, 0.8)
var aggro_range: float = 14.0
var leash_range: float = 30.0
var sight_layers: int = 3                ## how many depth layers it can perceive
var hearing_range: float = 20.0

# ----------------------------------------------------------------- behaviour
## Extra tuning consumed by `MobBehaviour` subclasses and `MobBrain` profiles.
var flags: Dictionary = {}
var pack_min: int = 1
var pack_max: int = 1
var night_only: bool = false
var day_only: bool = false
var needs_water: bool = false
var needs_dark: bool = false             ## caves / low light
var spawn_weight: float = 1.0

# ---------------------------------------------------------------------- loot
var loot_table: StringName = &"generic"
var loot: Array[Dictionary] = []         ## {item, min, max, chance}
var pixels: int = 4
var capture_difficulty: float = 1.0      ## >1 = harder to pod

# -------------------------------------------------------------------- visual
## Consumed verbatim by `MobVisual.build`.
var visual: Dictionary = {
	"shape": &"blob", "primary": Color(0.6, 0.5, 0.4), "secondary": Color(0.35, 0.3, 0.25),
	"eyes": 2, "limbs": 2, "wings": 0, "tail": false, "scale": 1.0, "glow": 0.0,
	"spikes": 0, "pattern": &"none", "seed": 0,
}


func _init(p_id: StringName = &"", p_name: String = "") -> void:
	id = p_id
	display_name = p_name if p_name != "" else String(p_id).capitalize()
	visual = visual.duplicate()
	visual["seed"] = int(hash(String(p_id)))


# ============================================================ fluent builders
## Family + locomotion + brain profile in one call. Critters are implicitly
## passive; everything else defaults to hostile until `aligned()` says otherwise.
func kind(p_family: StringName, p_loco: StringName, p_brain: StringName) -> MobSpecies:
	family = p_family
	locomotion = p_loco
	brain = p_brain
	if p_family == FAM_CRITTER:
		faction = &"passive"
	return self


## Override the faction (`hostile` / `passive` / `neutral` / `ally`).
func aligned(f: StringName) -> MobSpecies:
	faction = f
	return self


## Attach a special behaviour module (see `entities/monsters/behaviours.gd`).
func acts(p_behaviour: StringName) -> MobSpecies:
	behaviour = p_behaviour
	return self


func threat(p_tier: int) -> MobSpecies:
	tier = clampi(p_tier, 0, 6)
	return self


func at(p_biomes: Array) -> MobSpecies:
	biomes.clear()
	for b: StringName in p_biomes:
		biomes.append(canon_biome(b))
	return self


func stats(hp: float, dmg: float, speed: float, jump: float = 11.0) -> MobSpecies:
	base_health = hp
	base_damage = dmg
	move_speed = speed
	jump_speed = jump
	return self


func body(size: Vector3, p_knockback_resist: float = 0.0) -> MobSpecies:
	box_size = size
	knockback_resist = p_knockback_resist
	return self


func senses(p_aggro: float, p_leash: float, p_layers: int = 3, p_hearing: float = 20.0) -> MobSpecies:
	aggro_range = p_aggro
	leash_range = p_leash
	sight_layers = p_layers
	hearing_range = p_hearing
	return self


func melee(p_range: float, cooldown: float, windup: float = 0.35, p_touch: float = 0.0) -> MobSpecies:
	attack_range = p_range
	attack_cooldown = cooldown
	attack_windup = windup
	touch_damage = p_touch
	return self


func shoots(p_projectile: StringName, p_range: float, cooldown: float, speed: float = 18.0) -> MobSpecies:
	projectile = p_projectile
	attack_range = p_range
	attack_cooldown = cooldown
	projectile_speed = speed
	return self


func elemental(p_element: String) -> MobSpecies:
	element = p_element
	return self


## `{Const.ELEM_FIRE: 0.25}` means it takes a quarter damage from fire.
func resist(p_map: Dictionary) -> MobSpecies:
	for k: String in p_map:
		resistances[k] = float(p_map[k])
	return self


func plated(p_armour: float) -> MobSpecies:
	armour = p_armour
	return self


func packs(lo: int, hi: int) -> MobSpecies:
	pack_min = maxi(1, lo)
	pack_max = maxi(pack_min, hi)
	return self


func drop(item: StringName, lo: int = 1, hi: int = 1, chance: float = 1.0) -> MobSpecies:
	loot.append({"item": item, "min": lo, "max": hi, "chance": chance})
	return self


func worth(p_pixels: int, table: StringName = &"") -> MobSpecies:
	pixels = p_pixels
	if table != &"":
		loot_table = table
	return self


func look(primary: Color, secondary: Color, shape: StringName, extra: Dictionary = {}) -> MobSpecies:
	visual["primary"] = primary
	visual["secondary"] = secondary
	visual["shape"] = shape
	for k: StringName in extra:
		visual[k] = extra[k]
	return self


func with_flags(p_flags: Dictionary) -> MobSpecies:
	for k: StringName in p_flags:
		flags[k] = p_flags[k]
	return self


func only_at_night() -> MobSpecies:
	night_only = true
	return self


func only_by_day() -> MobSpecies:
	day_only = true
	return self


func aquatic() -> MobSpecies:
	needs_water = true
	return self


func subterranean() -> MobSpecies:
	needs_dark = true
	return self


func weight(w: float) -> MobSpecies:
	spawn_weight = w
	return self


func describe(text: String) -> MobSpecies:
	description = text
	return self


func hard_to_catch(d: float) -> MobSpecies:
	capture_difficulty = d
	return self


# ================================================================== queries
func lives_in(biome: StringName) -> bool:
	return biomes.is_empty() or biomes.has(canon_biome(biome))


func is_hostile() -> bool:
	return faction == &"hostile"


func is_passive() -> bool:
	return faction == &"passive" or family == FAM_CRITTER


func is_flying() -> bool:
	return locomotion == LOCO_FLY or locomotion == LOCO_HOVER


func is_rooted() -> bool:
	return locomotion == LOCO_STATIC


func is_ranged() -> bool:
	return projectile != &"" or brain == &"ranged" or brain == &"artillery" or brain == &"turret"


## Planet threat scaling. `planet_threat` is the star-system difficulty
## (roughly 0..5); a tier-1 crawler on a tier-5 planet is still a crawler, but
## a tougher one.
func scaled_health(planet_threat: int) -> float:
	var t := float(maxi(0, planet_threat))
	return base_health * (1.0 + 0.34 * t) * (1.0 + 0.12 * float(tier))


func scaled_damage(planet_threat: int) -> float:
	var t := float(maxi(0, planet_threat))
	return base_damage * (1.0 + 0.28 * t) * (1.0 + 0.1 * float(tier))


## Multiplier applied to an incoming hit of `element`.
func resistance_to(p_element: String) -> float:
	return float(resistances.get(p_element, 1.0))


func flag(key: StringName, fallback: Variant = null) -> Variant:
	return flags.get(key, fallback)


func flagf(key: StringName, fallback: float) -> float:
	return float(flags.get(key, fallback))


func flagb(key: StringName, fallback: bool = false) -> bool:
	return bool(flags.get(key, fallback))


func flagi(key: StringName, fallback: int) -> int:
	return int(flags.get(key, fallback))
