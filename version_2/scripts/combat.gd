class_name Combat
extends RefCounted

## The damage pipeline, the projectile catalogue and the weapon generator.
##
## Melee resolves as a cone in front of the player's billboard, which is what
## makes the camera facing a combat decision: turn the camera and the arc turns
## with it.
##
## Three weapons ask the cutaway a question instead of the world:
##   * `cutaway_pierce` — passes through terrain along the line of sight;
##   * `cutaway_occluded` — hits *only* targets standing inside the cut volume,
##     which means it is useless in the open and devastating down a tunnel;
##   * `cutaway_depth` — its blast travels along the camera axis rather than
##     spherically.

const PROJECTILES := {
	&"arrow": {"speed": 34.0, "gravity": 12.0, "life": 3.0, "size": 0.16,
		"color": Color(0.82, 0.76, 0.58), "trail": false, "pierce": 0},
	&"bolt": {"speed": 48.0, "gravity": 6.0, "life": 3.0, "size": 0.16,
		"color": Color(0.66, 0.90, 0.98), "trail": true, "pierce": 1},
	&"bullet": {"speed": 60.0, "gravity": 0.0, "life": 1.6, "size": 0.12,
		"color": Color(1.0, 0.86, 0.42), "trail": true, "pierce": 0},
	&"plasma": {"speed": 52.0, "gravity": 0.0, "life": 2.0, "size": 0.24,
		"color": Color(0.46, 0.94, 1.0), "trail": true, "pierce": 1, "light": 1.4},
	&"pellet": {"speed": 44.0, "gravity": 9.0, "life": 0.7, "size": 0.10,
		"color": Color(0.86, 0.80, 0.66), "trail": false, "pierce": 0},
	&"rocket": {"speed": 26.0, "gravity": 0.0, "life": 4.0, "size": 0.32,
		"color": Color(1.0, 0.52, 0.22), "trail": true, "blast": 3.4, "light": 1.8},
	&"grenade": {"speed": 18.0, "gravity": 22.0, "life": 2.0, "size": 0.26,
		"color": Color(0.42, 0.48, 0.36), "trail": false, "blast": 3.0, "fuse": true},
	&"fireball": {"speed": 24.0, "gravity": 3.0, "life": 3.0, "size": 0.3,
		"color": Color(1.0, 0.58, 0.18), "trail": true, "blast": 2.2, "light": 2.0},
	&"ice_shard": {"speed": 36.0, "gravity": 4.0, "life": 2.5, "size": 0.2,
		"color": Color(0.68, 0.92, 1.0), "trail": true, "pierce": 1, "light": 0.8},
	&"lightning_arc": {"speed": 70.0, "gravity": 0.0, "life": 1.2, "size": 0.18,
		"color": Color(0.86, 0.92, 1.0), "trail": true, "pierce": 3, "light": 2.0},
	&"star_bolt": {"speed": 30.0, "gravity": 0.0, "life": 3.0, "size": 0.26,
		"color": Color(0.86, 0.72, 1.0), "trail": true, "homing": 2.6, "light": 1.4},
	&"flame_gout": {"speed": 16.0, "gravity": -1.0, "life": 0.5, "size": 0.42,
		"color": Color(1.0, 0.64, 0.22), "trail": false, "pierce": 9, "light": 1.2},
	&"boomerang": {"speed": 26.0, "gravity": 0.0, "life": 2.4, "size": 0.24,
		"color": Color(0.88, 0.76, 0.38), "trail": false, "pierce": 9,
		"returns": true},
	# --- monster ammunition
	&"acid_glob": {"speed": 20.0, "gravity": 10.0, "life": 3.0, "size": 0.24,
		"color": Color(0.62, 0.90, 0.28), "trail": false, "light": 0.6},
	&"spore_burst": {"speed": 14.0, "gravity": 2.0, "life": 3.0, "size": 0.3,
		"color": Color(0.72, 0.86, 0.38), "trail": false},
	&"mortar_shell": {"speed": 17.0, "gravity": 20.0, "life": 4.0, "size": 0.3,
		"color": Color(0.46, 0.42, 0.34), "trail": false, "blast": 2.8},
	# --- the cutaway weapons
	&"phase_lance": {"speed": 58.0, "gravity": 0.0, "life": 2.2, "size": 0.3,
		"color": Color(0.78, 0.56, 1.0), "trail": true, "pierce": 99,
		"through_terrain": true, "light": 2.4},
	&"depth_charge": {"speed": 22.0, "gravity": 14.0, "life": 2.2, "size": 0.3,
		"color": Color(0.46, 0.76, 0.92), "trail": true, "blast": 2.0,
		"depth_blast": 12.0, "light": 1.6},
}

## Damage multipliers when an element meets a resistance-free target, used to
## give each element a personality rather than a number.
const ELEMENT_EFFECTS := {
	Blocks.ELEM_FIRE: [&"burning", 5.0],
	Blocks.ELEM_ICE: [&"chilled", 5.0],
	Blocks.ELEM_ELECTRIC: [&"shocked", 3.0],
	Blocks.ELEM_POISON: [&"poisoned", 8.0],
}


static func projectile_def(kind: StringName) -> Dictionary:
	return PROJECTILES.get(kind, PROJECTILES[&"bullet"])


## Roll a critical. Returns [damage, was_crit].
static func roll_damage(base: float, crit_chance: float,
		rng: RandomNumberGenerator) -> Array:
	var variance := rng.randf_range(0.92, 1.10)
	if rng.randf() < crit_chance:
		return [base * variance * 1.9, true]
	return [base * variance, false]


# =============================================================================
# procedural weapons
# =============================================================================

const PREFIXES := [
	["Rusted", 0.72, 0], ["Chipped", 0.82, 0], ["Plain", 1.0, 0],
	["Keen", 1.12, 1], ["Balanced", 1.15, 1], ["Tempered", 1.22, 1],
	["Masterwork", 1.4, 2], ["Ancient", 1.55, 2], ["Starforged", 1.8, 3],
]
const SUFFIXES := [
	["", Blocks.ELEM_PHYSICAL, 1.0],
	["of Embers", Blocks.ELEM_FIRE, 1.05],
	["of Frost", Blocks.ELEM_ICE, 1.05],
	["of the Storm", Blocks.ELEM_ELECTRIC, 1.08],
	["of Blight", Blocks.ELEM_POISON, 1.06],
	["of the Void", Blocks.ELEM_COSMIC, 1.18],
]
const ARCHETYPES := [
	&"broadsword", &"shortsword", &"spear", &"hammer", &"dagger", &"whip",
	&"bow", &"gun", &"shotgun", &"staff", &"boomerang",
]


## Generate a random weapon appropriate to `tier`, as an ItemStack whose `data`
## overrides the base item's stats. This is where loot variety comes from.
static func generate_weapon(tier: int, rng: RandomNumberGenerator) -> Items.Stack:
	var arch: StringName = ARCHETYPES[rng.randi() % ARCHETYPES.size()]
	var base_id := StringName("gen_" + String(arch))
	if not Items.has(base_id):
		base_id = &"gen_broadsword"
	var base := Items.get_type(base_id)

	# prefix quality is biased upward by tier, so deep loot is better loot
	var pick := clampi(int(rng.randf_range(0.0, 4.0) + float(tier) * 0.6), 0,
		PREFIXES.size() - 1)
	var prefix: Array = PREFIXES[pick]
	var suffix: Array = SUFFIXES[rng.randi() % SUFFIXES.size()]

	var scale := (1.0 + float(tier) * 0.55) * float(prefix[1]) * float(suffix[2])
	var name := "%s %s %s" % [prefix[0], base.display, suffix[0]]
	var stack := Items.make(base_id, 1)
	stack.data = {
		"name": name.strip_edges().replace("  ", " "),
		"damage": snappedf(base.damage * scale, 0.1),
		"attack_speed": snappedf(base.attack_speed * rng.randf_range(0.9, 1.12), 0.01),
		"element": String(suffix[1]),
		"rarity": clampi(int(prefix[2]) + (1 if suffix[0] != "" else 0), 0, 4),
		"knockback": snappedf(base.knockback * rng.randf_range(0.8, 1.3), 0.1),
		"generated": true,
	}
	if base.durability > 0:
		stack.data["durability"] = base.durability
	return stack
