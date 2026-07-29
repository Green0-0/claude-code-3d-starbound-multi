## The projectile catalogue. Pure data: [CbtProjectile] reads a definition from
## here and configures itself, which keeps the flight code generic and lets a
## procedurally generated weapon pick an existing projectile by id.
##
## ## Definition schema
##
## ```
## {
##   "name":          String,      # display name, used by tooltips
##   "speed":         float,       # launch speed, blocks/second, plane space
##   "gravity":       float,       # multiple of Const.GRAVITY (0 = straight)
##   "drag":          float,       # velocity lost per second, fraction
##   "damage":        float,       # base damage before weapon scaling
##   "element":       String,      # Const.ELEMENTS
##   "radius":        float,       # hit radius in plane space
##   "lifetime":      float,       # seconds before it expires
##   "pierce":        int,         # extra ENTITIES it passes through (0 = stops)
##   "bounce":        int,         # voxel bounces before it dies
##   "bounciness":    float,       # velocity kept per bounce
##   "homing":        float,       # turn rate, radians/second (0 = dumb)
##   "homing_range":  float,       # plane-space acquisition radius
##   "knockback":     float,
##   "crit_chance":   float, "crit_mult": float,
##   "break_blocks":  int,         # mining tier, -1 = never breaks voxels
##   "break_radius":  float,       # voxels carved on impact
##   "explode_radius":float, "explode_power": float,
##   "stick":         bool,        # embeds in the terrain instead of dying
##   "ghost":         bool,        # ignores voxels entirely
##   "layer_rule":    int,         # CbtDamage.LAYER_*
##   "layer_min":     int, "layer_max": int, "layer_falloff": float,
##   "depth_speed":   float,       # velocity ALONG THE DEPTH AXIS (into screen)
##   "layer_step":    float,       # seconds between depth-layer advances
##   "color":         Color, "glow": float, "size": Vector2,
##   "trail":         float,       # trail ribbon width, 0 = none
##   "particles":     StringName,  # per-tick particle effect id
##   "hit_sound":     StringName, "fire_sound": StringName,
##   "status_on_hit": Array,       # see CbtStatusHooks
##   "children":      Dictionary,  # {"type": &"id", "count": int,
##                                 #  "spread": deg, "on": "hit"|"expire"|"both",
##                                 #  "speed": float, "inherit": bool}
##   "chain":         Dictionary,  # {"count": int, "range": float, "falloff": f}
##   "spin":          float,       # visual roll, radians/second
##   "returns":       bool,        # boomerang: flies back to the thrower
##   "return_after":  float,       # seconds before it turns around
##   "tags":          Array[StringName],
## }
## ```
##
## ## The perspective projectiles
##
## Four entries exist purely to play with the depth axis, and they are the most
## interesting things in this file:
##
## * `phase_lance`  — `layer_rule = LAYER_ALL`. A beam that ignores depth and
##   spears every enemy at that screen position, in every layer at once.
## * `depth_charge` — explodes across `layer_min..layer_max`, damaging a slab of
##   layers behind the play plane. The answer to something hiding one step back.
## * `oblique_shot` — `depth_speed > 0`. It flies *into the screen*, walking one
##   layer deeper at a time. On screen it just sits there getting dimmer.
## * `echo_dart`    — `layer_range(1, 1)`. Hits **only** the layer behind you and
##   passes harmlessly through anything on your own plane.
class_name CbtProjectileTypes
extends RefCounted

const DEFAULT := {
	"name": "Projectile",
	"speed": 22.0,
	"gravity": 0.0,
	"drag": 0.0,
	"damage": 6.0,
	"element": Const.ELEM_PHYSICAL,
	"radius": 0.32,
	"lifetime": 3.0,
	"pierce": 0,
	"bounce": 0,
	"bounciness": 0.55,
	"homing": 0.0,
	"homing_range": 12.0,
	"knockback": 3.0,
	"crit_chance": 0.05,
	"crit_mult": 1.75,
	"break_blocks": -1,
	"break_radius": 0.0,
	"explode_radius": 0.0,
	"explode_power": 0.0,
	"stick": false,
	"ghost": false,
	"layer_rule": CbtDamage.LAYER_SAME,
	"layer_min": 0,
	"layer_max": 0,
	"layer_falloff": 1.0,
	"depth_speed": 0.0,
	"color": Color(0.9, 0.9, 0.9),
	"glow": 1.0,
	"size": Vector2(0.5, 0.14),
	"trail": 0.0,
	"particles": &"",
	"hit_sound": &"hit",
	"fire_sound": &"shoot",
	"status_on_hit": [],
	"children": {},
	"chain": {},
	"spin": 0.0,
	"returns": false,
	"return_after": 0.5,
	"tags": [],
}

## id -> partial definition. Anything absent falls back to [constant DEFAULT].
const DEFS := {
	# ------------------------------------------------------- basic munitions
	&"arrow": {
		"name": "Arrow", "speed": 30.0, "gravity": 0.42, "damage": 9.0,
		"radius": 0.28, "lifetime": 4.0, "knockback": 3.0, "stick": true,
		"color": Color(0.78, 0.66, 0.45), "size": Vector2(0.72, 0.09),
		"trail": 0.05, "glow": 0.2, "crit_chance": 0.12,
		"tags": [&"ammo", &"physical"],
	},
	&"bolt": {
		"name": "Bolt", "speed": 46.0, "gravity": 0.16, "damage": 13.0,
		"radius": 0.26, "lifetime": 3.0, "pierce": 1, "stick": true,
		"color": Color(0.62, 0.64, 0.7), "size": Vector2(0.6, 0.09),
		"trail": 0.05, "crit_chance": 0.15, "tags": [&"ammo", &"physical"],
	},
	&"bullet": {
		"name": "Bullet", "speed": 78.0, "gravity": 0.0, "damage": 8.0,
		"radius": 0.22, "lifetime": 1.1, "knockback": 1.6,
		"color": Color(1.0, 0.92, 0.6), "size": Vector2(0.42, 0.07),
		"trail": 0.045, "glow": 1.6, "break_blocks": -1,
		"tags": [&"ammo", &"hitscanish"],
	},
	&"pellet": {
		"name": "Pellet", "speed": 54.0, "gravity": 0.24, "damage": 4.2,
		"radius": 0.2, "lifetime": 0.42, "knockback": 1.1,
		"color": Color(1.0, 0.85, 0.55), "size": Vector2(0.26, 0.07),
		"trail": 0.03, "glow": 1.2, "tags": [&"ammo", &"spread"],
	},
	&"needle": {
		"name": "Thorn Needle", "speed": 38.0, "gravity": 0.2, "damage": 5.0,
		"radius": 0.2, "lifetime": 2.2, "pierce": 2, "element": Const.ELEM_POISON,
		"color": Color(0.6, 0.85, 0.4), "size": Vector2(0.4, 0.06),
		"status_on_hit": [{"id": &"poisoned", "chance": 0.5, "duration": 5.0}],
		"tags": [&"ammo", &"organic"],
	},

	# --------------------------------------------------------------- energy
	&"plasma": {
		"name": "Plasma Bolt", "speed": 34.0, "gravity": 0.0, "damage": 14.0,
		"element": Const.ELEM_ELECTRIC, "radius": 0.36, "lifetime": 2.4,
		"pierce": 1, "color": Color(0.5, 0.95, 1.0), "size": Vector2(0.55, 0.24),
		"trail": 0.14, "glow": 3.0, "particles": &"plasma_spark",
		"status_on_hit": [{"id": &"shocked", "chance": 0.2, "duration": 2.0}],
		"tags": [&"energy"],
	},
	&"void_orb": {
		"name": "Void Orb", "speed": 12.0, "gravity": 0.0, "damage": 22.0,
		"element": Const.ELEM_COSMIC, "radius": 0.62, "lifetime": 5.0,
		"pierce": 6, "knockback": 1.0, "drag": 0.15,
		"color": Color(0.7, 0.35, 1.0), "size": Vector2(0.7, 0.7),
		"trail": 0.3, "glow": 3.5, "spin": 2.4, "particles": &"void_motes",
		"tags": [&"energy", &"cosmic"],
	},
	&"star_bolt": {
		"name": "Star Bolt", "speed": 18.0, "gravity": 0.0, "damage": 11.0,
		"element": Const.ELEM_COSMIC, "radius": 0.34, "lifetime": 4.5,
		"homing": 5.2, "homing_range": 18.0, "drag": 0.05,
		"color": Color(1.0, 0.85, 0.45), "size": Vector2(0.4, 0.4),
		"trail": 0.16, "glow": 3.0, "spin": 6.0, "tags": [&"energy", &"homing"],
	},
	&"sonic_wave": {
		"name": "Sonic Wave", "speed": 26.0, "gravity": 0.0, "damage": 7.0,
		"radius": 1.1, "lifetime": 1.2, "pierce": 20, "knockback": 9.0,
		"ghost": true, "color": Color(0.85, 0.9, 1.0), "size": Vector2(0.25, 2.4),
		"glow": 2.0, "trail": 0.0, "crit_chance": 0.0,
		"tags": [&"energy", &"wave"],
	},

	# ------------------------------------------------------------- elemental
	&"fireball": {
		"name": "Fireball", "speed": 20.0, "gravity": 0.18, "damage": 16.0,
		"element": Const.ELEM_FIRE, "radius": 0.5, "lifetime": 3.2,
		"explode_radius": 2.2, "explode_power": 1.5, "break_blocks": 1,
		"color": Color(1.0, 0.55, 0.15), "size": Vector2(0.55, 0.55),
		"trail": 0.22, "glow": 3.2, "particles": &"fire_trail", "spin": 3.0,
		"status_on_hit": [{"id": &"burning", "chance": 0.75, "duration": 6.0}],
		"tags": [&"magic", &"fire"],
	},
	&"flame_gout": {
		"name": "Flame", "speed": 15.0, "gravity": -0.06, "damage": 3.4,
		"element": Const.ELEM_FIRE, "radius": 0.66, "lifetime": 0.55,
		"pierce": 8, "drag": 1.5, "knockback": 0.4, "ghost": false,
		"color": Color(1.0, 0.65, 0.2), "size": Vector2(0.7, 0.7),
		"glow": 2.6, "spin": 8.0, "crit_chance": 0.0,
		"status_on_hit": [{"id": &"burning", "chance": 0.35, "duration": 4.0}],
		"tags": [&"fire", &"stream"],
	},
	&"ice_shard": {
		"name": "Ice Shard", "speed": 32.0, "gravity": 0.25, "damage": 12.0,
		"element": Const.ELEM_ICE, "radius": 0.3, "lifetime": 3.0, "pierce": 1,
		"color": Color(0.6, 0.9, 1.0), "size": Vector2(0.6, 0.16),
		"trail": 0.08, "glow": 1.8, "crit_chance": 0.1,
		"status_on_hit": [{"id": &"frozen", "chance": 0.4, "duration": 2.5}],
		"children": {"type": &"frost_splinter", "count": 3, "spread": 120.0,
			"on": "hit", "speed": 14.0},
		"tags": [&"magic", &"ice"],
	},
	&"frost_splinter": {
		"name": "Frost Splinter", "speed": 14.0, "gravity": 0.6, "damage": 3.0,
		"element": Const.ELEM_ICE, "radius": 0.18, "lifetime": 0.8,
		"color": Color(0.75, 0.95, 1.0), "size": Vector2(0.25, 0.08),
		"glow": 1.2, "crit_chance": 0.0, "tags": [&"ice", &"fragment"],
	},
	&"poison_glob": {
		"name": "Poison Glob", "speed": 17.0, "gravity": 0.7, "damage": 9.0,
		"element": Const.ELEM_POISON, "radius": 0.42, "lifetime": 4.0,
		"bounce": 2, "bounciness": 0.42, "explode_radius": 1.6,
		"explode_power": 0.0, "color": Color(0.55, 0.95, 0.3),
		"size": Vector2(0.5, 0.5), "trail": 0.16, "glow": 1.6, "spin": 4.0,
		"status_on_hit": [{"id": &"poisoned", "chance": 0.85, "duration": 9.0}],
		"tags": [&"organic", &"poison"],
	},
	&"lightning_arc": {
		"name": "Lightning Arc", "speed": 62.0, "gravity": 0.0, "damage": 15.0,
		"element": Const.ELEM_ELECTRIC, "radius": 0.4, "lifetime": 1.0,
		"pierce": 2, "ghost": false, "color": Color(0.9, 0.9, 1.0),
		"size": Vector2(1.1, 0.12), "trail": 0.12, "glow": 4.0,
		"chain": {"count": 3, "range": 7.0, "falloff": 0.68},
		"status_on_hit": [{"id": &"shocked", "chance": 0.6, "duration": 3.0}],
		"tags": [&"magic", &"electric", &"chain"],
	},

	# ------------------------------------------------------------ explosives
	&"rocket": {
		"name": "Rocket", "speed": 26.0, "gravity": 0.04, "damage": 34.0,
		"element": Const.ELEM_FIRE, "radius": 0.5, "lifetime": 4.5,
		"explode_radius": 4.0, "explode_power": 5.0, "break_blocks": 3,
		"break_radius": 2.6, "knockback": 14.0,
		"color": Color(0.9, 0.85, 0.8), "size": Vector2(0.85, 0.3),
		"trail": 0.2, "glow": 2.2, "particles": &"rocket_smoke",
		"status_on_hit": [{"id": &"burning", "chance": 0.5, "duration": 4.0}],
		"tags": [&"explosive"],
	},
	&"seeker": {
		"name": "Seeker Missile", "speed": 16.0, "gravity": 0.0, "damage": 24.0,
		"element": Const.ELEM_FIRE, "radius": 0.42, "lifetime": 6.0,
		"homing": 3.4, "homing_range": 22.0, "explode_radius": 3.0,
		"explode_power": 3.0, "break_blocks": 2, "break_radius": 1.6,
		"knockback": 8.0, "color": Color(1.0, 0.5, 0.4),
		"size": Vector2(0.7, 0.26), "trail": 0.18, "glow": 2.4,
		"particles": &"rocket_smoke", "tags": [&"explosive", &"homing"],
	},
	&"grenade": {
		"name": "Grenade", "speed": 18.0, "gravity": 1.0, "damage": 30.0,
		"radius": 0.34, "lifetime": 1.9, "bounce": 4, "bounciness": 0.4,
		"drag": 0.25, "explode_radius": 3.6, "explode_power": 4.0,
		"break_blocks": 3, "break_radius": 2.2, "knockback": 12.0,
		"color": Color(0.35, 0.42, 0.3), "size": Vector2(0.34, 0.34),
		"glow": 0.4, "spin": 9.0,
		"children": {"type": &"frag", "count": 6, "spread": 360.0,
			"on": "expire", "speed": 16.0},
		"tags": [&"explosive", &"thrown"],
	},
	&"frag": {
		"name": "Fragment", "speed": 16.0, "gravity": 0.9, "damage": 5.0,
		"radius": 0.16, "lifetime": 0.9, "bounce": 1,
		"color": Color(0.8, 0.75, 0.6), "size": Vector2(0.2, 0.08),
		"glow": 0.6, "crit_chance": 0.0, "tags": [&"fragment"],
	},

	# ---------------------------------------------------------------- exotic
	&"boomerang": {
		"name": "Boomerang", "speed": 24.0, "gravity": 0.0, "damage": 13.0,
		"radius": 0.42, "lifetime": 3.0, "pierce": 30, "bounce": 3,
		"bounciness": 0.9, "returns": true, "return_after": 0.45,
		"knockback": 4.0, "color": Color(0.85, 0.7, 0.35),
		"size": Vector2(0.6, 0.6), "trail": 0.1, "glow": 0.8, "spin": 22.0,
		"tags": [&"thrown", &"returning"],
	},
	&"drill_beam": {
		"name": "Drill Beam", "speed": 44.0, "gravity": 0.0, "damage": 7.0,
		"element": Const.ELEM_ELECTRIC, "radius": 0.3, "lifetime": 0.35,
		"pierce": 3, "break_blocks": 4, "break_radius": 0.0,
		"knockback": 0.5, "crit_chance": 0.02,
		"color": Color(1.0, 0.75, 0.35), "size": Vector2(0.9, 0.16),
		"trail": 0.1, "glow": 3.4, "tags": [&"beam", &"mining"],
	},
	&"spark_chain": {
		"name": "Spark", "speed": 40.0, "gravity": 0.0, "damage": 6.0,
		"element": Const.ELEM_ELECTRIC, "radius": 0.3, "lifetime": 0.8,
		"color": Color(0.8, 0.95, 1.0), "size": Vector2(0.3, 0.3),
		"glow": 3.0, "chain": {"count": 2, "range": 5.0, "falloff": 0.6},
		"crit_chance": 0.0, "tags": [&"electric", &"fragment"],
	},

	# ================================================== perspective specials
	## Ignores depth completely: everything at that screen position dies,
	## however many layers deep it is standing.
	&"phase_lance": {
		"name": "Phase Lance", "speed": 60.0, "gravity": 0.0, "damage": 18.0,
		"element": Const.ELEM_COSMIC, "radius": 0.45, "lifetime": 0.9,
		"pierce": 99, "ghost": false, "knockback": 2.0,
		"layer_rule": CbtDamage.LAYER_ALL,
		"color": Color(0.75, 0.5, 1.0), "size": Vector2(1.6, 0.2),
		"trail": 0.16, "glow": 4.0, "particles": &"phase_motes",
		"tags": [&"beam", &"perspective"],
	},
	## Sinks into the screen and detonates through a slab of layers.
	&"depth_charge": {
		"name": "Depth Charge", "speed": 14.0, "gravity": 0.85, "damage": 26.0,
		"radius": 0.4, "lifetime": 1.6, "bounce": 2, "bounciness": 0.35,
		"explode_radius": 3.2, "explode_power": 3.5, "break_blocks": 3,
		"break_radius": 2.0, "knockback": 9.0,
		"layer_rule": CbtDamage.LAYER_RANGE, "layer_min": 0, "layer_max": 4,
		"layer_falloff": 0.82, "depth_speed": 1.6,
		"color": Color(0.4, 0.7, 0.85), "size": Vector2(0.42, 0.42),
		"trail": 0.1, "glow": 1.4, "spin": 5.0, "particles": &"depth_bubbles",
		"tags": [&"explosive", &"perspective"],
	},
	## Fires straight into the screen, one layer at a time. On screen it barely
	## moves — it just fades as it recedes, and it hits whatever it reaches.
	&"oblique_shot": {
		"name": "Oblique Shot", "speed": 2.0, "gravity": 0.0, "damage": 20.0,
		"element": Const.ELEM_ELECTRIC, "radius": 0.55, "lifetime": 2.2,
		"pierce": 99, "ghost": false, "depth_speed": 9.0,
		"layer_rule": CbtDamage.LAYER_RANGE, "layer_min": -2, "layer_max": 24,
		"knockback": 1.0, "color": Color(0.5, 1.0, 0.85),
		"size": Vector2(0.4, 0.4), "trail": 0.0, "glow": 3.0,
		"tags": [&"perspective", &"energy"],
	},
	## Passes harmlessly through your own plane and detonates one layer back.
	&"echo_dart": {
		"name": "Echo Dart", "speed": 34.0, "gravity": 0.12, "damage": 21.0,
		"element": Const.ELEM_COSMIC, "radius": 0.4, "lifetime": 2.4,
		"pierce": 4, "ghost": true,
		"layer_rule": CbtDamage.LAYER_RANGE, "layer_min": 1, "layer_max": 1,
		"knockback": 5.0, "crit_chance": 0.25, "crit_mult": 2.1,
		"color": Color(0.55, 0.45, 0.9), "size": Vector2(0.7, 0.12),
		"trail": 0.12, "glow": 2.2, "tags": [&"perspective", &"stealth"],
	},
}


## Every registered projectile id, sorted.
static func ids() -> Array:
	var out := DEFS.keys()
	out.sort()
	return out


static func has(id: StringName) -> bool:
	return DEFS.has(id)


## A complete definition: the type's entries merged over [constant DEFAULT].
## Always returns a fresh dictionary, safe to mutate.
static func get_def(id: StringName) -> Dictionary:
	var out := DEFAULT.duplicate(true)
	var d: Variant = DEFS.get(id, null)
	if d is Dictionary:
		for k: String in d:
			out[k] = (d as Dictionary)[k]
	out["id"] = id
	return out


## Ids carrying a tag, e.g. `&"perspective"` or `&"explosive"`.
static func with_tag(t: StringName) -> Array:
	var out: Array = []
	for id: StringName in DEFS:
		var tags: Variant = (DEFS[id] as Dictionary).get("tags", [])
		if tags is Array and (tags as Array).has(t):
			out.append(id)
	out.sort()
	return out


## A sensible projectile for an element, used by the weapon generator when a
## roll does not name one explicitly.
static func for_element(element: String, ranged_kind: StringName = &"gun") -> StringName:
	match ranged_kind:
		&"bow":
			match element:
				Const.ELEM_FIRE: return &"fireball"
				Const.ELEM_ICE: return &"ice_shard"
				Const.ELEM_POISON: return &"needle"
				Const.ELEM_ELECTRIC: return &"lightning_arc"
				Const.ELEM_COSMIC: return &"echo_dart"
			return &"arrow"
		&"staff":
			match element:
				Const.ELEM_FIRE: return &"fireball"
				Const.ELEM_ICE: return &"ice_shard"
				Const.ELEM_POISON: return &"poison_glob"
				Const.ELEM_ELECTRIC: return &"lightning_arc"
			return &"star_bolt"
		&"shotgun":
			return &"pellet"
		&"rocket":
			return &"rocket"
		&"flamethrower":
			return &"flame_gout"
	match element:
		Const.ELEM_FIRE: return &"fireball"
		Const.ELEM_ICE: return &"ice_shard"
		Const.ELEM_POISON: return &"needle"
		Const.ELEM_ELECTRIC: return &"plasma"
		Const.ELEM_COSMIC: return &"void_orb"
	return &"bullet"
