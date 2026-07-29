## Procedural naming grammar for the galaxy.
##
## Pure static helper — never instantiated. Every generator in `space/` pulls
## its strings from here so the whole universe shares one voice: Greek-letter
## designations, dry catalogue numbers, and the occasional evocative name for
## worlds worth remembering.
##
## Determinism: every function takes a `RandomNumberGenerator` you own. Build
## one with `SpcNaming.rng_for(galaxy_seed, "some:salt")` and the same salt will
## always produce the same name for the same run seed.
class_name SpcNaming
extends RefCounted

## Greek letters, used for the primary star of a system and for sector rings.
const GREEK := [
	"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
	"Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi",
	"Rho", "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega",
]

## Invented constellation stems. Deliberately short and pronounceable.
const STEMS := [
	"Cygni", "Draconis", "Serpentis", "Corvi", "Lyrae", "Aquilae", "Ceti",
	"Hydrae", "Velorum", "Carinae", "Pavonis", "Tucanae", "Volantis",
	"Fornacis", "Reticuli", "Indi", "Gruis", "Leporis", "Monocerotis",
	"Vulpeculae", "Camelopardi", "Sculptoris", "Circini", "Octantis",
	"Erebi", "Thanae", "Vesh", "Oryx", "Kell", "Marrow", "Sable", "Umbra",
]

## Catalogue prefixes for the workaday majority of stars.
const CATALOGUES := [
	"HD", "HIP", "GJ", "NGC", "KX", "TYC", "LHS", "Ross", "Wolf", "Kepler",
	"Baryon", "Vex", "CDR",
]

## Adjectives for evocative planet names.
const ADJECTIVES := [
	"Verdant", "Silent", "Weeping", "Gilded", "Shattered", "Drowned", "Hollow",
	"Frozen", "Burning", "Whispering", "Forgotten", "Radiant", "Bitter",
	"Sundered", "Patient", "Restless", "Crimson", "Azure", "Ashen", "Emerald",
	"Obsidian", "Pale", "Wandering", "Sleeping", "Hungry", "Quiet", "Sunken",
	"Fractured", "Luminous", "Withered", "Storming", "Endless",
]

## Nouns for evocative planet names and sector names.
const NOUNS := [
	"Reach", "Expanse", "Verge", "Cradle", "Hollow", "Wake", "Shroud", "Bloom",
	"Spire", "Vault", "Grave", "Choir", "Bastion", "Threshold", "Furrow",
	"Meridian", "Anvil", "Lantern", "Harvest", "Tide", "Ember", "Wound",
	"Garden", "Coil", "Fen", "Drift", "Halo", "Maw", "Keel", "Rift",
]

## Single-word planet names for garden / signature worlds.
const WORLD_ROOTS := [
	"Verdance", "Elyra", "Toskan", "Mireth", "Oquay", "Vantal", "Sethric",
	"Ilmarin", "Corrah", "Duneth", "Kalvex", "Ossuar", "Peregrin", "Thalos",
	"Umberlin", "Yarrow", "Zephry", "Brackwater", "Cinderhold", "Dawnmoor",
	"Fennhollow", "Glimmerfen", "Halcyon", "Ivorel", "Junix", "Kestrel",
]

## Suffixes for derelict stations and orbital habitats.
const STATION_ROOTS := [
	"Anchorage", "Waystation", "Relay", "Drydock", "Foundry", "Silo",
	"Observatory", "Reliquary", "Terminus", "Refinery", "Beacon", "Hab",
]

const STATION_ADJ := [
	"Derelict", "Abandoned", "Dark", "Silent", "Drifting", "Ruined",
	"Sealed", "Cold", "Lost", "Unlisted",
]

const ASTEROID_ROOTS := [
	"Shoal", "Scatter", "Belt", "Swarm", "Debris Field", "Rubble", "Sieve",
	"Chaff", "Girdle",
]

const ROMAN_ONES := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]
const ROMAN_TENS := ["", "X", "XX", "XXX", "XL", "L", "LX", "LXX", "LXXX", "XC"]

## Letters used for moon designations: Ceres I a, b, c...
const MOON_LETTERS := "abcdefgh"


# ---------------------------------------------------------------------- rng
## Deterministic generator for one named thing. `salt` should identify the
## entity uniquely, e.g. `"system:2:5"`.
static func rng_for(base_seed: int, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|%s" % [base_seed, salt])
	return r


## Integer seed derived the same way, for handing to another subsystem.
static func seed_for(base_seed: int, salt: String) -> int:
	return absi(hash("%d|%s" % [base_seed, salt])) & 0x7FFFFFFF


static func pick(list: Array, rng: RandomNumberGenerator) -> String:
	if list.is_empty():
		return ""
	return String(list[rng.randi_range(0, list.size() - 1)])


# ------------------------------------------------------------------- numerals
## Roman numeral for 1..99; falls back to the decimal string beyond that.
static func roman(n: int) -> String:
	if n <= 0:
		return "0"
	if n >= 100:
		return str(n)
	return String(ROMAN_TENS[n / 10]) + String(ROMAN_ONES[n % 10])


## Moon designation letter: 0 -> "a", 1 -> "b", ... wraps with a numeric tail.
static func moon_letter(index: int) -> String:
	if index < MOON_LETTERS.length():
		return MOON_LETTERS.substr(index, 1)
	return "%s%d" % [MOON_LETTERS[index % MOON_LETTERS.length()], index / MOON_LETTERS.length()]


# -------------------------------------------------------------------- sectors
## Sector names read like frontier regions: "The Verdant Reach", "Sigma Drift".
static func sector_name(rng: RandomNumberGenerator, ring: int) -> String:
	match rng.randi_range(0, 3):
		0:
			return "The %s %s" % [pick(ADJECTIVES, rng), pick(NOUNS, rng)]
		1:
			return "%s %s" % [GREEK[ring % GREEK.size()], pick(NOUNS, rng)]
		2:
			return "%s's %s" % [pick(WORLD_ROOTS, rng), pick(NOUNS, rng)]
		_:
			return "%s %s" % [pick(ADJECTIVES, rng), pick(NOUNS, rng)]


# ---------------------------------------------------------------------- stars
## Star names: mostly Greek + stem or catalogue + number, rarely a proper name.
static func star_name(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.40:
		return "%s %s" % [pick(GREEK, rng), pick(STEMS, rng)]
	if roll < 0.72:
		return "%s %d" % [pick(CATALOGUES, rng), rng.randi_range(101, 9989)]
	if roll < 0.86:
		return "%s %d-%s" % [pick(CATALOGUES, rng), rng.randi_range(2, 88),
		String.chr(65 + rng.randi_range(0, 25))]
	return pick(WORLD_ROOTS, rng)


# -------------------------------------------------------------------- planets
## Planet name. Ordinary worlds take their star's name plus a Roman numeral;
## `evocative_chance` promotes lush or storied worlds to a proper name.
static func planet_name(star: String, orbit: int, rng: RandomNumberGenerator,
		evocative_chance: float = 0.18) -> String:
	if rng.randf() < evocative_chance:
		if rng.randf() < 0.45:
			return "%s %s" % [pick(ADJECTIVES, rng), pick(NOUNS, rng)]
		return pick(WORLD_ROOTS, rng)
	return "%s %s" % [star, roman(orbit)]


## Moons hang off their parent: "Kappa Cygni III a" or an occasional name.
static func moon_name(parent: String, index: int, rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.12:
		return pick(WORLD_ROOTS, rng)
	return "%s %s" % [parent, moon_letter(index)]


static func gas_giant_name(star: String, orbit: int, rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.25:
		return "%s the %s" % [pick(WORLD_ROOTS, rng), pick(NOUNS, rng)]
	return "%s %s" % [star, roman(orbit)]


static func asteroid_name(star: String, rng: RandomNumberGenerator) -> String:
	return "%s %s" % [star, pick(ASTEROID_ROOTS, rng)]


static func station_name(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.5:
		return "%s %s" % [pick(STATION_ADJ, rng), pick(STATION_ROOTS, rng)]
	return "%s %s %d" % [pick(STATION_ROOTS, rng),
		String.chr(65 + rng.randi_range(0, 25)), rng.randi_range(2, 97)]


# ------------------------------------------------------------------ flavour
## One-line description shown under a body on the star map.
static func flavour(kind: String, type_name: String, threat: int,
		rng: RandomNumberGenerator) -> String:
	var mood: Array = ["quiet", "unsurveyed", "well charted", "poorly charted",
		"hazard flagged", "under advisory", "of local interest"]
	match kind:
		"gas_giant":
			return "Gas giant. No landfall possible."
		"asteroid_field":
			return "Loose %s. Mineral rich, thin gravity." % pick(ASTEROID_ROOTS, rng).to_lower()
		"station":
			return "Orbital structure, %s." % pick(mood, rng)
		"moon":
			return "%s moon, threat %d." % [type_name, threat]
		_:
			return "%s world, threat %d, %s." % [type_name, threat, pick(mood, rng)]
