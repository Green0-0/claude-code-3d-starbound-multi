class_name CreatureTraits
extends RefCounted

## The vocabulary the bestiary is written in.
##
## This lives in its own script on purpose. `SpeciesDB.Def` is an inner class,
## and an inner class that reaches back out to its own outer `class_name` — as
## in `SpeciesDB.TEMPER_DEFENSIVE` — makes the script depend on itself while it
## is still being resolved. Godot's command-line parser tolerates that; the
## editor's analyser does not, and reports every member of the outer class as
## missing from any script that uses it.
##
## Holding the vocabulary somewhere with no dependencies of its own removes the
## cycle entirely. `SpeciesDB` re-exports these names, so call sites are free to
## use either spelling.

# ------------------------------------------------------------------ families
const FAM_GROUND := &"ground"
const FAM_FLYING := &"flying"
const FAM_AQUATIC := &"aquatic"
const FAM_SPECIAL := &"special"
const FAM_BOSS := &"boss"

# --------------------------------------------------------------- temperament
## Never fights, even when hit. Runs instead.
const TEMPER_PASSIVE := &"passive"
## Flees on sight, and only fights when cornered with nowhere to run.
const TEMPER_SKITTISH := &"skittish"
## Ignores you until you come too close or draw blood.
const TEMPER_DEFENSIVE := &"defensive"
## Hunts on sight.
const TEMPER_AGGRESSIVE := &"aggressive"
## Holds absolutely still until you are almost touching it.
const TEMPER_AMBUSH := &"ambush"

# ------------------------------------------------------------------ activity
const ACTIVE_DAY := &"diurnal"
const ACTIVE_NIGHT := &"nocturnal"
const ACTIVE_ALWAYS := &"always"

# -------------------------------------------------------------------- social
const SOCIAL_ALONE := &"solitary"
const SOCIAL_HERD := &"herd"
const SOCIAL_PACK := &"pack"

# ---------------------------------------------------------------- locomotion
const MOVE_WALK := &"walk"
const MOVE_HOP := &"hop"
const MOVE_FLY := &"fly"
const MOVE_FLOAT := &"float"
const MOVE_SWIM := &"swim"
const MOVE_CLIMB := &"climb"
const MOVE_ROOT := &"root"


## Is a creature with these hours awake right now?
static func awake_now(activity: StringName, night: bool) -> bool:
	if activity == ACTIVE_DAY:
		return not night
	if activity == ACTIVE_NIGHT:
		return night
	return true


## Does this temperament go looking for a fight?
static func hunts(temperament: StringName) -> bool:
	return temperament == TEMPER_AGGRESSIVE or temperament == TEMPER_AMBUSH


## Will it fight back at all?
static func will_fight(temperament: StringName) -> bool:
	return temperament != TEMPER_PASSIVE and temperament != TEMPER_SKITTISH
