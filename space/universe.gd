## Autoloaded as `Universe`. The procedural galaxy, the star-map data model, and
## the owner of every other `space/` subsystem.
##
## ===========================================================================
##  WHAT THIS FILE PROMISES TO OTHER AGENTS
## ===========================================================================
##
## `Game` calls exactly five things (do not change these signatures):
##   `generate(seed)` · `starting_planet_id() -> String` ·
##   `planet_meta(id) -> Dictionary` · `save_state()` · `load_state(d)`
##
## ---------------------------------------------------------------------------
##  THE PLANET `meta` DICTIONARY — read by `PlanetGen.begin_planet()` and by the
##  lighting agent. Every key below is always present.
## ---------------------------------------------------------------------------
##
##  IDENTITY
##   `id`            String   unique body id; also the `World.planet_id`
##   `name`          String   display name
##   `seed`          int      per-body deterministic seed (>=0)
##   `kind`          String   planet | moon | gas_giant | asteroid_field |
##                            station | ship | outpost
##   `type`          String   biome archetype, one of TYPE_ORDER below
##   `type_name`     String   display form of `type`
##   `threat`        int      1..6 danger tier
##   `tier_name`     String   display form of `threat`
##
##  GEOMETRY  (sizes are always multiples of 16 — chunk aligned)
##   `size_x`        int      planet width in blocks, wraps
##   `size_z`        int      planet depth in blocks, wraps
##   `surface_level` int      nominal average surface Y
##   `sea_level`     int      Y below which `liquid` fills open space
##   `gravity`       float    multiplier on `Const.GRAVITY` (0.25 .. 1.6)
##   `day_length`    float    multiplier on `Const.TICKS_PER_DAY` (0.5 .. 2.0)
##   `orbit_index`   int      1-based orbital slot, 0 for fixed worlds
##
##  ENVIRONMENT  (survival agent + lighting agent)
##   `breathable`    bool     false -> oxygen drains
##   `temperature`   float    -1 frozen .. 0 temperate .. +1 scorching
##   `radiation`     float    0..1
##   `atmosphere`    String   none | thin | normal | dense | toxic
##   `hazard`        String   matches `Biome.HAZARD_*` keys
##   `hazard_strength` float  0..1
##   `weather_set`   Array[String]  weather ids allowed here (see WEATHER below)
##   `weather_bias`  float    0..1 chance the weather is *not* clear
##
##  GENERATION  (terrain agent)
##   `generator`     String   planet | flat | void
##                            `flat`/`void` mean "produce empty chunks, this
##                            world is stamped in code" — see `space/stamp.gd`
##   `flat_height`   int      ground Y when `generator == "flat"`
##   `biome_weights` Dictionary  biome key -> float weight, sums to 1.0. Keys are
##                            *requests*; fall back if you have no such biome.
##   `primary_biome` String   the highest-weighted key, guaranteed non-empty
##   `liquid`        String   block name of the dominant surface liquid
##   `ocean_level`   float    0..1 fraction of the surface below `sea_level`
##   `cave_density`  float    0.4 .. 1.8 multiplier on cave volume
##   `vegetation`    float    0..1 multiplier on flora density
##   `ore_bias`      Dictionary  ore block name -> multiplier (missing = 1.0)
##   `dungeon`       String   "" or a `theme_*` tag from `PsBlocks.THEMES`
##   `dungeon_count` int      how many dungeon sites to place
##   `structures`    Array[String]  extra structure keys requested
##
##  SKY / LIGHTING  (lighting agent). `sky_palette` always has all nine keys.
##   `sky_palette`   Dictionary {
##                      `zenith`: Color, `horizon`: Color, `sun`: Color,
##                      `fog`: Color, `ambient`: Color,
##                      `night_zenith`: Color, `night_horizon`: Color,
##                      `sun_energy`: float,      # 0..2 directional strength
##                      `ambient_energy`: float,  # 0..1 flat fill
##                      `star_density`: float,    # 0..1 stars visible at night
##                      `cloud`: Color, `cloud_cover`: float }
##   `light_tint`    Color    multiplied into voxel light
##   `ambient_light` float    0..1 baseline glow even underground
##   `sky_type`      String   day_night | eternal_night | airless | nebula
##   `moons`         Array[Dictionary] [{name, size, phase, color}] for the
##                            lighting agent to draw in the sky
##
##  STAR CONTEXT
##   `system_id` `system_name` `sector_id` `sector_name` String
##   `star_class` String · `star_color` Color
##
## ---------------------------------------------------------------------------
##  WEATHER vocabulary used in `weather_set`
##   clear rain storm snow blizzard sandstorm ash_fall acid_rain meteor_shower
##   fog wind ember_fall spore_fall aurora radiation_storm
## ---------------------------------------------------------------------------
##  BIOME keys used in `biome_weights`
##   plains forest taiga tundra desert savannah jungle swamp ocean beach
##   mountains badlands toxic magma ash moon barren crystal mushroom alien
##   midnight garden ruins
## ---------------------------------------------------------------------------
##  STAR MAP READ API for `ui/menus/star_map_panel.gd` — see the block marked
##  "STAR MAP READ API" near the bottom of this file.
## ===========================================================================
extends Node

# --------------------------------------------------------------------- signals
## The galaxy was rebuilt; every cached id the UI holds is now stale.
signal galaxy_generated(galaxy_seed: int)
signal body_discovered(body_id: String)
signal body_visited(body_id: String)
signal body_scanned(body_id: String, level: int)
signal selection_changed(body_id: String)
## Fuel / hull / FTL changed — the star map should re-evaluate reachability.
signal capabilities_changed()

# ------------------------------------------------------------------ constants
## World id of the player's ship. See `space/ship.gd`.
const SHIP_ID := "ship"
## World id of the social hub. See `space/outpost.gd`.
const OUTPOST_ID := "outpost"
## World id of the flat testing world. Always present, always in the home
## system, always reachable for free, and always free of hostiles.
const SUPERFLAT_ID := "superflat"
## Y level of the superflat grass course.
const SUPERFLAT_GROUND := 64

const SECTOR_COUNT := 6
const SYSTEMS_MIN := 6
const SYSTEMS_MAX := 11
const BODIES_MIN := 2
const BODIES_MAX := 6

## The terrain agent's planet-type vocabulary, in progression order.
const TYPE_ORDER := [
	"garden", "forest", "moon", "barren", "desert", "tundra", "ocean",
	"mushroom", "jungle", "crystal", "toxic", "midnight", "alien",
	"volcanic", "scorched", "ruins",
]

const THREAT_NAMES := [
	"Unknown", "Gentle", "Moderate", "Risky", "Dangerous", "Extreme", "Inconceivable",
]
const THREAT_COLORS := [
	Color(0.6, 0.6, 0.6), Color(0.45, 0.85, 0.45), Color(0.75, 0.88, 0.35),
	Color(0.95, 0.82, 0.30), Color(0.96, 0.58, 0.25), Color(0.93, 0.32, 0.28),
	Color(0.78, 0.30, 0.90),
]

# ------------------------------------------------------------------- galaxy
var galaxy_seed: int = 0

var sectors: Dictionary = {}            ## String -> sector record
var sector_order: Array[String] = []
var systems: Dictionary = {}            ## String -> system record
var system_order: Array[String] = []
var bodies: Dictionary = {}             ## String -> star-map body record
var body_order: Array[String] = []
## Landable bodies only: id -> the full `meta` dictionary documented above.
var planets: Dictionary = {}

# ---------------------------------------------------------------- run state
var discovered: Dictionary = {}         ## body id -> true
var visited: Dictionary = {}            ## body id -> true
var scan_level: Dictionary = {}         ## body id -> 0..2
var scan_reports: Dictionary = {}       ## body id -> Dictionary (see scanning.gd)

var start_body: String = ""
var home_system: String = ""
var current_body: String = ""
var selected_body: String = ""

# ------------------------------------------------------------- subsystems
var upgrades: SpcShipUpgrades = null
var ship: SpcShip = null
var travel: SpcTravel = null
var teleporter: SpcTeleporter = null
var outpost: SpcOutpost = null
var scanning: SpcScanning = null

## World id -> {"min": Vector3i, "max": Vector3i} chunk box that is
## hand-authored. Any chunk of that world outside the box is force-blanked as it
## loads, so a code-built world never grows accidental terrain.
var _void_worlds: Dictionary = {}

var _types: Dictionary = {}
var _star_classes: Array[Dictionary] = []


# ============================================================== lifecycle
func _ready() -> void:
	process_priority = -20
	_build_type_table()
	_build_star_classes()
	upgrades = SpcShipUpgrades.new()
	upgrades.name = "ShipUpgrades"
	add_child(upgrades)
	ship = SpcShip.new()
	ship.name = "Ship"
	add_child(ship)
	teleporter = SpcTeleporter.new()
	teleporter.name = "Teleporter"
	add_child(teleporter)
	outpost = SpcOutpost.new()
	outpost.name = "Outpost"
	add_child(outpost)
	scanning = SpcScanning.new()
	scanning.name = "Scanning"
	add_child(scanning)
	travel = SpcTravel.new()
	travel.name = "Travel"
	add_child(travel)
	register_void_world(SHIP_ID, SpcShipInterior.CHUNK_MIN, SpcShipInterior.CHUNK_MAX)
	register_void_world(OUTPOST_ID, SpcOutpost.CHUNK_MIN, SpcOutpost.CHUNK_MAX)
	Events.chunk_loaded.connect(_on_chunk_loaded)
	Events.travel_finished.connect(_on_travel_finished)


## Register a world whose voxels are authored in code. `cmin`/`cmax` are
## inclusive chunk coordinates; everything outside is kept empty.
func register_void_world(world_id: String, cmin: Vector3i, cmax: Vector3i) -> void:
	_void_worlds[world_id] = {"min": cmin, "max": cmax}


func is_void_world(world_id: String) -> bool:
	return _void_worlds.has(world_id)


func _on_chunk_loaded(cp: Vector3i) -> void:
	var g: Dictionary = _void_worlds.get(World.planet_id, {})
	if g.is_empty():
		return
	var lo: Vector3i = g["min"]
	var hi: Vector3i = g["max"]
	if cp.x >= lo.x and cp.x <= hi.x and cp.y >= lo.y and cp.y <= hi.y \
			and cp.z >= lo.z and cp.z <= hi.z:
		return
	var c := World.get_chunk(cp)
	if c == null:
		return
	SpcStamp.blank_chunk(c)
	World.mark_dirty(cp)
	if Lighting.has_method(&"on_chunk_loaded"):
		Lighting.call(&"on_chunk_loaded", cp)


func _on_travel_finished(planet_id: String) -> void:
	current_body = planet_id
	if planets.has(planet_id):
		mark_visited(planet_id)


# ============================================================ generation
## Rebuild the whole galaxy from `p_seed`. Called by `Game.start_new_game()`.
func generate(p_seed: int) -> void:
	galaxy_seed = p_seed if p_seed != 0 else 1
	sectors.clear()
	sector_order.clear()
	systems.clear()
	system_order.clear()
	bodies.clear()
	body_order.clear()
	planets.clear()
	discovered.clear()
	visited.clear()
	scan_level.clear()
	scan_reports.clear()
	if _types.is_empty():
		_build_type_table()
		_build_star_classes()

	for si in SECTOR_COUNT:
		_gen_sector(si)
	_gen_fixed_worlds()

	if upgrades != null:
		upgrades.reset()
	if travel != null:
		travel.reset_orbit(start_body)
	current_body = ""
	selected_body = start_body
	# The home system, the outpost and the ship are known from the first minute.
	discover(SHIP_ID)
	discover(OUTPOST_ID)
	discover(SUPERFLAT_ID)
	for bid: String in system_body_ids(home_system):
		discover(bid)
	# The homeworld is already fully surveyed — that is why you are heading there.
	if scanning != null:
		scanning.grant_scan(start_body, 2)
	else:
		set_scan_level(start_body, 2)
	galaxy_generated.emit(galaxy_seed)


## A new run begins **aboard the ship**, parked in orbit above `start_body`.
## The ship is the tutorial space for flipping and shifting, and the player
## beams down from the teleporter pad in the hub when they are ready.
func starting_planet_id() -> String:
	if planets.has(SHIP_ID):
		return SHIP_ID
	return start_body if planets.has(start_body) else OUTPOST_ID


# --------------------------------------------------------------------- sectors
func _gen_sector(index: int) -> void:
	var rng := SpcNaming.rng_for(galaxy_seed, "sector:%d" % index)
	var sid := "sec_%d" % index
	var threat_min := index + 1
	var threat_max := mini(6, index + 2)
	var rec := {
		"id": sid,
		"index": index,
		"name": SpcNaming.sector_name(rng, index),
		"threat_min": threat_min,
		"threat_max": threat_max,
		"ring": 1.0 + float(index) * 1.15,
		"color": _threat_color_of(threat_min),
		"systems": [],
	}
	sectors[sid] = rec
	sector_order.append(sid)

	var count := (SYSTEMS_MIN + index) if index > 0 else (SYSTEMS_MIN + 2)
	count = clampi(count, SYSTEMS_MIN, SYSTEMS_MAX)
	var arc := TAU / float(count)
	for i in count:
		var is_home := index == 0 and i == 0
		var sys_id := _gen_system(rec, i, arc * float(i) + rng.randf_range(-0.18, 0.18), rng, is_home)
		rec["systems"].append(sys_id)


# --------------------------------------------------------------------- systems
func _gen_system(sector: Dictionary, index: int, angle: float,
		_sector_rng: RandomNumberGenerator, is_home: bool) -> String:
	var sec_index: int = sector["index"]
	var sys_id := "sys_%d_%d" % [sec_index, index]
	var rng := SpcNaming.rng_for(galaxy_seed, "system:%s" % sys_id)
	var radius: float = float(sector["ring"]) + rng.randf_range(-0.28, 0.28)
	var star: Dictionary = _pick_star_class(sec_index, rng, is_home)
	var star_display := "Sol" if is_home else SpcNaming.star_name(rng)

	var rec := {
		"id": sys_id,
		"name": star_display,
		"sector_id": sector["id"],
		"sector_name": sector["name"],
		"index": index,
		"star_class": star["key"],
		"star_name": star["name"],
		"star_color": star["color"],
		"star_heat": star["heat"],
		"pos": Vector2(cos(angle), sin(angle)) * radius,
		"bodies": [],
		"threat": int(sector["threat_min"]),
	}
	systems[sys_id] = rec
	system_order.append(sys_id)
	if is_home:
		home_system = sys_id

	var n := rng.randi_range(BODIES_MIN, BODIES_MAX)
	if is_home:
		n = maxi(n, 4)
	var highest := 0
	for orbit in range(1, n + 1):
		var body_id := _gen_body(rec, sector, orbit, rng, is_home and orbit == 1)
		if body_id == "":
			continue
		rec["bodies"].append(body_id)
		highest = maxi(highest, int(bodies[body_id]["threat"]))
	rec["threat"] = maxi(1, highest)
	return sys_id


func _pick_star_class(sector_index: int, rng: RandomNumberGenerator, is_home: bool) -> Dictionary:
	if is_home:
		return _star_classes[2]
	var pool: Array[Dictionary] = []
	for sc: Dictionary in _star_classes:
		if bool(sc.get("exotic", false)) and sector_index < 3:
			continue
		pool.append(sc)
	var total := 0.0
	for sc: Dictionary in pool:
		total += float(sc["weight"])
	var roll := rng.randf() * total
	for sc: Dictionary in pool:
		roll -= float(sc["weight"])
		if roll <= 0.0:
			return sc
	return pool[pool.size() - 1]


# ----------------------------------------------------------------------- bodies
func _gen_body(system: Dictionary, sector: Dictionary, orbit: int,
		_sys_rng: RandomNumberGenerator, force_home: bool) -> String:
	var body_id := "%s_b%d" % [system["id"], orbit]
	var rng := SpcNaming.rng_for(galaxy_seed, "body:%s" % body_id)
	var kind := "planet"
	if not force_home:
		var roll := rng.randf()
		if roll < 0.11:
			kind = "gas_giant"
		elif roll < 0.24:
			kind = "asteroid_field"
		elif roll < 0.34:
			kind = "station"

	var threat := _roll_threat(sector, orbit, rng)
	var type_key := "forest"
	var star_name: String = system["name"]
	var display := ""
	var landable := true
	var size := 512

	match kind:
		"gas_giant":
			type_key = "alien"
			landable = false
			display = SpcNaming.gas_giant_name(star_name, orbit, rng)
			size = 0
		"asteroid_field":
			type_key = "barren"
			display = SpcNaming.asteroid_name(star_name, rng)
			size = 256
		"station":
			type_key = "ruins"
			display = SpcNaming.station_name(rng)
			size = 256
			threat = maxi(threat, 2)
		_:
			type_key = _pick_type(threat, float(system["star_heat"]), orbit, rng, force_home)
			display = SpcNaming.planet_name(star_name, orbit, rng,
				0.4 if type_key == "garden" else 0.16)
			size = _size_for(type_key, rng)
	if force_home:
		type_key = "forest"
		threat = 1
		landable = true
		display = SpcNaming.planet_name(star_name, orbit, rng, 1.0)

	var t: Dictionary = _types[type_key]
	var rec := {
		"id": body_id,
		"name": display,
		"kind": kind,
		"type": type_key,
		"type_name": String(t["display"]),
		"threat": threat,
		"landable": landable,
		"system_id": system["id"],
		"sector_id": sector["id"],
		"parent_id": "",
		"orbit_index": orbit,
		"orbit_radius": 0.28 + 0.16 * float(orbit),
		"orbit_angle": rng.randf() * TAU,
		"color": _body_color(type_key, kind, rng),
		"size_px": _body_scale(kind, rng),
		"moons": [],
		"description": SpcNaming.flavour(kind, String(t["display"]), threat, rng),
	}
	bodies[body_id] = rec
	body_order.append(body_id)
	if landable:
		planets[body_id] = _build_meta(rec, system, sector, size, rng)

	# Moons hang off planets and gas giants.
	var moon_count := 0
	if kind == "planet":
		moon_count = rng.randi_range(0, 2)
	elif kind == "gas_giant":
		moon_count = rng.randi_range(1, 3)
	for m in moon_count:
		var mid := _gen_moon(rec, system, sector, m, rng)
		rec["moons"].append(mid)

	if force_home:
		start_body = body_id
	return body_id


func _gen_moon(parent: Dictionary, system: Dictionary, sector: Dictionary,
		index: int, _parent_rng: RandomNumberGenerator) -> String:
	var mid := "%s_m%d" % [parent["id"], index]
	var rng := SpcNaming.rng_for(galaxy_seed, "moon:%s" % mid)
	var threat: int = maxi(1, int(parent["threat"]) - (0 if rng.randf() < 0.35 else 1))
	var type_key := "moon"
	var roll := rng.randf()
	if roll < 0.16:
		type_key = "barren"
	elif roll < 0.26:
		type_key = "crystal"
	elif roll < 0.34 and threat >= 3:
		type_key = "toxic"
	var t: Dictionary = _types[type_key]
	var rec := {
		"id": mid,
		"name": SpcNaming.moon_name(String(parent["name"]), index, rng),
		"kind": "moon",
		"type": type_key,
		"type_name": String(t["display"]),
		"threat": threat,
		"landable": true,
		"system_id": system["id"],
		"sector_id": sector["id"],
		"parent_id": parent["id"],
		"orbit_index": index + 1,
		"orbit_radius": 0.06 + 0.035 * float(index),
		"orbit_angle": rng.randf() * TAU,
		"color": _body_color(type_key, "moon", rng),
		"size_px": 0.45,
		"moons": [],
		"description": SpcNaming.flavour("moon", String(t["display"]), threat, rng),
	}
	bodies[mid] = rec
	body_order.append(mid)
	planets[mid] = _build_meta(rec, system, sector, _size_for(type_key, rng) / 2, rng)
	return mid


func _roll_threat(sector: Dictionary, orbit: int, rng: RandomNumberGenerator) -> int:
	var lo: int = sector["threat_min"]
	var hi: int = sector["threat_max"]
	var t := rng.randi_range(lo, hi)
	# Outer orbits skew slightly nastier so a system reads as a difficulty ramp.
	if orbit >= 4 and rng.randf() < 0.4:
		t += 1
	return clampi(t, 1, 6)


func _pick_type(threat: int, star_heat: float, orbit: int,
		rng: RandomNumberGenerator, force_home: bool) -> String:
	if force_home:
		return "forest"
	var best: Array[String] = []
	var weights: Array[float] = []
	for key: String in TYPE_ORDER:
		var t: Dictionary = _types[key]
		if key == "moon":
			continue
		var band: Array = t["threat"]
		if threat < int(band[0]) or threat > int(band[1]):
			continue
		# Hot stars push scorched/volcanic inward, cold stars favour ice.
		var want_temp: float = (float(t["temp"][0]) + float(t["temp"][1])) * 0.5
		var orbit_temp := clampf(star_heat + 0.6 - 0.22 * float(orbit), -1.0, 1.0)
		var affinity := 1.0 - absf(want_temp - orbit_temp) * 0.6
		best.append(key)
		weights.append(maxf(0.05, affinity) * float(t.get("weight", 1.0)))
	if best.is_empty():
		return "barren"
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in best.size():
		roll -= weights[i]
		if roll <= 0.0:
			return best[i]
	return best[best.size() - 1]


func _size_for(type_key: String, rng: RandomNumberGenerator) -> int:
	var band: Array = _types[type_key].get("size", [512, 768])
	var v := rng.randi_range(int(band[0]), int(band[1]))
	return maxi(128, (v / 64) * 64)


func _body_color(type_key: String, kind: String, rng: RandomNumberGenerator) -> Color:
	var base: Color = _types[type_key]["icon"]
	if kind == "gas_giant":
		base = base.lerp(Color(0.85, 0.72, 0.5), 0.5)
	elif kind == "station":
		base = Color(0.65, 0.68, 0.75)
	elif kind == "asteroid_field":
		base = Color(0.48, 0.45, 0.42)
	return base.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.10)


func _body_scale(kind: String, rng: RandomNumberGenerator) -> float:
	match kind:
		"gas_giant":
			return rng.randf_range(1.5, 2.1)
		"asteroid_field":
			return rng.randf_range(0.5, 0.75)
		"station":
			return 0.5
		_:
			return rng.randf_range(0.8, 1.2)


# ------------------------------------------------------------------ meta build
func _build_meta(body: Dictionary, system: Dictionary, sector: Dictionary,
		size: int, rng: RandomNumberGenerator) -> Dictionary:
	var type_key: String = body["type"]
	var t: Dictionary = _types[type_key]
	var threat: int = body["threat"]
	var sx := maxi(128, (size / 64) * 64)
	var sz := maxi(128, ((size + rng.randi_range(-128, 128)) / 64) * 64)
	var surface := int(t.get("surface", 96))
	var gravity: float = rng.randf_range(float(t["gravity"][0]), float(t["gravity"][1]))
	if body["kind"] == "asteroid_field":
		gravity *= 0.45
	var temperature: float = rng.randf_range(float(t["temp"][0]), float(t["temp"][1]))
	var radiation: float = rng.randf_range(float(t["rad"][0]), float(t["rad"][1]))
	var biome_weights := _roll_biomes(t, rng)
	var star_color: Color = system["star_color"]

	var dungeon := ""
	var dungeon_count := 0
	var dungeons: Array = t.get("dungeons", [])
	if not dungeons.is_empty() and rng.randf() < clampf(0.22 + 0.08 * float(threat), 0.0, 0.85):
		dungeon = String(dungeons[rng.randi_range(0, dungeons.size() - 1)])
		dungeon_count = 1 if rng.randf() < 0.75 else 2

	# Decorative satellites drawn in the sky by the lighting agent. Independent
	# of the *landable* moon bodies generated by `_gen_moon()`.
	var moons: Array[Dictionary] = []
	var moon_ct := 0 if body["kind"] == "moon" else rng.randi_range(0, 2)
	for i in moon_ct:
		moons.append({
			"name": "%s %s" % [body["name"], SpcNaming.moon_letter(i)],
			"size": rng.randf_range(0.4, 1.1),
			"phase": rng.randf(),
			"color": Color(1, 1, 1).lerp(star_color, 0.35).lerp(
				Color(rng.randf_range(0.5, 1.0), rng.randf_range(0.5, 1.0), rng.randf_range(0.6, 1.0)), 0.3),
		})

	return {
		# identity
		"id": body["id"],
		"name": body["name"],
		"seed": SpcNaming.seed_for(galaxy_seed, "world:%s" % body["id"]),
		"kind": body["kind"],
		"type": type_key,
		"type_name": String(t["display"]),
		"threat": threat,
		"tier_name": threat_name(threat),
		# geometry
		"size_x": sx,
		"size_z": sz,
		"surface_level": surface,
		"sea_level": surface - int(t.get("sea_drop", 6)),
		"gravity": snappedf(gravity, 0.01),
		"day_length": snappedf(rng.randf_range(float(t["day"][0]), float(t["day"][1])), 0.01),
		"orbit_index": body["orbit_index"],
		# environment
		"breathable": bool(t["breathable"]),
		"temperature": snappedf(temperature, 0.01),
		"radiation": snappedf(radiation, 0.01),
		"atmosphere": String(t["atmosphere"]),
		"hazard": String(t["hazard"]),
		"hazard_strength": snappedf(clampf(float(t.get("hazard_strength", 0.0))
			+ 0.06 * float(threat), 0.0, 1.0), 0.01),
		"weather_set": (t["weather"] as Array).duplicate(),
		"weather_bias": snappedf(rng.randf_range(0.15, 0.55), 0.01),
		# generation
		"generator": "planet",
		"flat_height": 0,
		"biome_weights": biome_weights,
		"primary_biome": _dominant(biome_weights),
		"liquid": String(t.get("liquid", "water")),
		"ocean_level": snappedf(rng.randf_range(
			float(t["ocean"][0]), float(t["ocean"][1])), 0.01),
		"cave_density": snappedf(rng.randf_range(0.6, 1.6), 0.01),
		"vegetation": snappedf(float(t.get("vegetation", 0.5))
			* rng.randf_range(0.75, 1.25), 0.01),
		"ore_bias": _ore_bias(t, threat, rng),
		"dungeon": dungeon,
		"dungeon_count": dungeon_count,
		"structures": (t.get("structures", []) as Array).duplicate(),
		# sky / lighting
		"sky_palette": _sky_palette(t, star_color, rng),
		"light_tint": _tint_of(t).lerp(star_color, 0.25),
		"ambient_light": float(t.get("ambient", 0.0)),
		"sky_type": String(t.get("sky_type", "day_night")),
		"moons": moons,
		# star context
		"system_id": system["id"],
		"system_name": system["name"],
		"sector_id": sector["id"],
		"sector_name": sector["name"],
		"star_class": system["star_class"],
		"star_color": star_color,
	}


func _roll_biomes(t: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	var src: Dictionary = t["biomes"]
	for k: String in src:
		var w := float(src[k]) * rng.randf_range(0.7, 1.35)
		if w > 0.001:
			out[k] = w
	if out.is_empty():
		out["plains"] = 1.0
	var total := 0.0
	for k: String in out:
		total += float(out[k])
	for k: String in out:
		out[k] = snappedf(float(out[k]) / total, 0.001)
	return out


func _dominant(weights: Dictionary) -> String:
	var best := ""
	var best_w := -1.0
	for k: String in weights:
		if float(weights[k]) > best_w:
			best_w = float(weights[k])
			best = k
	return best if best != "" else "plains"


func _ore_bias(t: Dictionary, threat: int, rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	for o in (t.get("ores", []) as Array):
		out[String(o)] = snappedf(rng.randf_range(1.3, 2.4), 0.01)
	# Deep-tier ores only become common on nasty worlds.
	if threat >= 4:
		for o in ["titanium_ore", "durasteel_ore", "aegisalt_ore"]:
			out[o] = snappedf(rng.randf_range(1.1, 1.8), 0.01)
	if threat <= 2:
		out["copper_ore"] = snappedf(rng.randf_range(1.2, 1.8), 0.01)
	return out


func _sky_palette(t: Dictionary, star_color: Color, rng: RandomNumberGenerator) -> Dictionary:
	var sky: Array = t["sky"]
	var zenith: Color = sky[0]
	var horizon: Color = sky[1]
	var jitter := Color(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05),
		rng.randf_range(-0.05, 0.05), 0.0)
	zenith = Color(clampf(zenith.r + jitter.r, 0, 1), clampf(zenith.g + jitter.g, 0, 1),
		clampf(zenith.b + jitter.b, 0, 1))
	horizon = horizon.lerp(star_color, 0.22)
	var night_zenith := zenith.darkened(0.86)
	var eternal := String(t.get("sky_type", "day_night")) != "day_night"
	return {
		"zenith": zenith,
		"horizon": horizon,
		"sun": star_color,
		"fog": horizon.lerp(zenith, 0.4),
		"ambient": zenith.lerp(Color(1, 1, 1), 0.25),
		"night_zenith": night_zenith,
		"night_horizon": horizon.darkened(0.78),
		"sun_energy": snappedf(float(t.get("sun_energy", 1.0)) * rng.randf_range(0.9, 1.1), 0.01),
		"ambient_energy": snappedf(float(t.get("ambient_energy", 0.35)), 0.01),
		"star_density": snappedf(1.0 if eternal else rng.randf_range(0.3, 0.85), 0.01),
		"cloud": horizon.lerp(Color(1, 1, 1), 0.55),
		"cloud_cover": snappedf(rng.randf_range(0.0, float(t.get("clouds", 0.6))), 0.01),
	}


# ------------------------------------------------------- fixed, authored worlds
func _gen_fixed_worlds() -> void:
	var rng := SpcNaming.rng_for(galaxy_seed, "fixed")
	var sys: Dictionary = systems.get(home_system, {})
	var sec: Dictionary = sectors.get("sec_0", {})
	var sys_id: String = String(sys.get("id", ""))
	var sec_id: String = String(sec.get("id", "sec_0"))

	# --- the ship ---------------------------------------------------------
	var ship_meta := _fixed_meta(SHIP_ID, "Your Ship", "ship", 0, sys, sec)
	ship_meta["size_x"] = SpcShip.WORLD_SIZE
	ship_meta["size_z"] = SpcShip.WORLD_SIZE
	ship_meta["generator"] = "void"
	ship_meta["surface_level"] = SpcShip.DECK_Y
	ship_meta["sea_level"] = 0
	ship_meta["gravity"] = 1.0
	ship_meta["breathable"] = true
	ship_meta["sky_type"] = "nebula"
	ship_meta["ambient_light"] = 0.12
	ship_meta["weather_set"] = ["clear"]
	planets[SHIP_ID] = ship_meta

	# --- the outpost ------------------------------------------------------
	var out_meta := _fixed_meta(OUTPOST_ID, "The Outpost", "outpost", 0, sys, sec)
	out_meta["size_x"] = SpcOutpost.WORLD_SIZE
	out_meta["size_z"] = SpcOutpost.WORLD_SIZE
	out_meta["generator"] = "flat"
	out_meta["flat_height"] = SpcOutpost.GROUND_Y
	out_meta["surface_level"] = SpcOutpost.GROUND_Y
	out_meta["sea_level"] = 0
	out_meta["breathable"] = true
	out_meta["weather_set"] = ["clear", "wind"]
	planets[OUTPOST_ID] = out_meta

	# The outpost also shows on the star map, parked in the home system.
	if sys_id != "":
		var rec := {
			"id": OUTPOST_ID,
			"name": "The Outpost",
			"kind": "station",
			"type": "ruins",
			"type_name": "Outpost",
			"threat": 0,
			"landable": true,
			"system_id": sys_id,
			"sector_id": sec_id,
			"parent_id": "",
			"orbit_index": 0,
			"orbit_radius": 0.18,
			"orbit_angle": rng.randf() * TAU,
			"color": Color(0.55, 0.85, 0.95),
			"size_px": 0.6,
			"moons": [],
			"description": "Neutral trading post. The Ark gateway stands here.",
		}
		bodies[OUTPOST_ID] = rec
		body_order.append(OUTPOST_ID)
		(systems[sys_id]["bodies"] as Array).append(OUTPOST_ID)

	# --- the superflat proving ground -------------------------------------
	# A featureless flat world, parked in the home system, reachable for free
	# from the first minute and guaranteed hostile-free. It exists so building,
	# physics and the perspective mechanic can be tested against terrain with no
	# confounding variables, and so every run has somewhere safe to experiment.
	var flat_meta := _fixed_meta(SUPERFLAT_ID, "Proving Ground", "planet", 0, sys, sec)
	flat_meta["type"] = "plains"
	flat_meta["type_name"] = "Superflat"
	flat_meta["size_x"] = 256
	flat_meta["size_z"] = 256
	flat_meta["generator"] = "superflat"
	flat_meta["flat_height"] = SUPERFLAT_GROUND
	flat_meta["surface_level"] = SUPERFLAT_GROUND
	flat_meta["sea_level"] = 0
	flat_meta["breathable"] = true
	flat_meta["temperature"] = 0.0
	flat_meta["radiation"] = 0.0
	flat_meta["gravity"] = 1.0
	flat_meta["hazard"] = "none"
	flat_meta["hazard_strength"] = 0.0
	flat_meta["weather_set"] = ["clear"]
	flat_meta["weather_bias"] = 0.0
	flat_meta["cave_density"] = 0.0
	flat_meta["vegetation"] = 0.0
	flat_meta["dungeon"] = ""
	flat_meta["dungeon_count"] = 0
	flat_meta["structures"] = []
	flat_meta["biome_weights"] = {"plains": 1.0}
	flat_meta["primary_biome"] = "plains"
	flat_meta["sky_type"] = "day_night"
	flat_meta["ambient_light"] = 0.35
	# Read by `entities/entity_manager.gd`: nothing hostile ever spawns here.
	flat_meta["hostiles"] = false
	planets[SUPERFLAT_ID] = flat_meta
	if sys_id != "" and systems.has(sys_id):
		bodies[SUPERFLAT_ID] = {
			"id": SUPERFLAT_ID, "name": "Proving Ground",
			"kind": "planet", "type": "plains", "type_name": "Superflat",
			"threat": 0, "landable": true,
			"system_id": sys_id, "sector_id": sec_id,
			"parent_id": "", "orbit_index": 1, "orbit_radius": 0.30,
			"orbit_angle": rng.randf() * TAU,
			"color": Color(0.62, 0.82, 0.48), "size_px": 0.8, "moons": [],
			"description": "A featureless flat world. No weather, no hazards, "
				+ "nothing hostile. Kept for testing and for building in peace.",
		}
		body_order.append(SUPERFLAT_ID)
		(systems[sys_id]["bodies"] as Array).append(SUPERFLAT_ID)


func _fixed_meta(id: String, display: String, kind: String, threat: int,
		sys: Dictionary, sec: Dictionary) -> Dictionary:
	var star_color: Color = sys.get("star_color", Color(1.0, 0.93, 0.72))
	return {
		"id": id, "name": display,
		"seed": SpcNaming.seed_for(galaxy_seed, "world:%s" % id),
		"kind": kind, "type": "garden", "type_name": display,
		"threat": threat, "tier_name": threat_name(threat),
		"size_x": 64, "size_z": 64,
		"surface_level": 64, "sea_level": 0,
		"gravity": 1.0, "day_length": 1.0, "orbit_index": 0,
		"breathable": true, "temperature": 0.0, "radiation": 0.0,
		"atmosphere": "normal", "hazard": "none", "hazard_strength": 0.0,
		"weather_set": ["clear"], "weather_bias": 0.0,
		"generator": "void", "flat_height": 0,
		"biome_weights": {"plains": 1.0}, "primary_biome": "plains",
		"liquid": "water", "ocean_level": 0.0, "cave_density": 0.0,
		"vegetation": 0.0, "ore_bias": {}, "dungeon": "", "dungeon_count": 0,
		"structures": [],
		"sky_palette": {
			"zenith": Color(0.03, 0.04, 0.09), "horizon": Color(0.10, 0.08, 0.20),
			"sun": star_color, "fog": Color(0.06, 0.06, 0.14),
			"ambient": Color(0.30, 0.34, 0.48),
			"night_zenith": Color(0.02, 0.02, 0.06),
			"night_horizon": Color(0.05, 0.04, 0.12),
			"sun_energy": 0.55, "ambient_energy": 0.45, "star_density": 1.0,
			"cloud": Color(0.2, 0.2, 0.3), "cloud_cover": 0.0,
		},
		"light_tint": Color(1, 1, 1), "ambient_light": 0.1,
		"sky_type": "nebula", "moons": [],
		"system_id": String(sys.get("id", "")), "system_name": String(sys.get("name", "Sol")),
		"sector_id": String(sec.get("id", "sec_0")),
		"sector_name": String(sec.get("name", "Home")),
		"star_class": String(sys.get("star_class", "g")), "star_color": star_color,
	}


# ============================================================ STAR MAP READ API
# Everything below is what `ui/menus/star_map_panel.gd` should call. All of it is
# read-only except `select()`, `discover()` and the travel/scan entry points.

## Full planet metadata (the schema at the top of this file). Never fails: an
## unknown id falls back to the starting planet so `Game` cannot crash.
func planet_meta(id: String) -> Dictionary:
	if planets.has(id):
		return planets[id]
	if planets.has(start_body):
		return planets[start_body]
	return planets.values()[0] if not planets.is_empty() else {}


## Sector ids from the core outward. Index 0 is the safest.
func sector_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(sector_order)
	return out


## `{id, index, name, threat_min, threat_max, ring, color, systems:Array of String ids}`
func sector_info(id: String) -> Dictionary:
	return sectors.get(id, {})


## System ids, optionally restricted to one sector.
func system_ids(sector_id: String = "") -> Array[String]:
	if sector_id == "":
		var all: Array[String] = []
		all.assign(system_order)
		return all
	var out: Array[String] = []
	var sec: Dictionary = sectors.get(sector_id, {})
	for s in (sec.get("systems", []) as Array):
		out.append(String(s))
	return out


## `{id, name, sector_id, sector_name, index, star_class, star_name, star_color,
##   star_heat, pos:Vector2, bodies:Array of String ids, threat}`
## `pos` is in abstract galactic units (roughly -8..8); scale it to your canvas.
func system_info(id: String) -> Dictionary:
	return systems.get(id, {})


## Body ids orbiting a system, in orbital order. Moons are *not* included —
## fetch them with `moon_ids()`.
func system_body_ids(system_id: String) -> Array[String]:
	var out: Array[String] = []
	var sys: Dictionary = systems.get(system_id, {})
	for b in (sys.get("bodies", []) as Array):
		out.append(String(b))
	return out


## `{id, name, kind, type, type_name, threat, landable, system_id, sector_id,
##   parent_id, orbit_index, orbit_radius, orbit_angle, color, size_px,
##   moons:Array of String ids, description}`
func body_info(id: String) -> Dictionary:
	return bodies.get(id, {})


func moon_ids(body_id: String) -> Array[String]:
	var out: Array[String] = []
	var b: Dictionary = bodies.get(body_id, {})
	for m in (b.get("moons", []) as Array):
		out.append(String(m))
	return out


func body_name(id: String) -> String:
	var b: Dictionary = bodies.get(id, {})
	if not b.is_empty():
		return String(b["name"])
	var p: Dictionary = planets.get(id, {})
	return String(p.get("name", id))


func is_discovered(id: String) -> bool:
	return discovered.has(id)


func is_visited(id: String) -> bool:
	return visited.has(id)


## 0 = never scanned, 1 = orbital sweep, 2 = deep scan. See `space/scanning.gd`.
func scan_of(id: String) -> int:
	return int(scan_level.get(id, 0))


## The scan payload produced by `SpcScanning.scan()`; `{}` when unscanned.
func scan_report(id: String) -> Dictionary:
	return scan_reports.get(id, {})


## Every system the player has laid eyes on, for a "known space" filter.
func known_systems() -> Array[String]:
	var out: Array[String] = []
	for sid: String in system_order:
		for b in (systems[sid]["bodies"] as Array):
			if discovered.has(String(b)):
				out.append(sid)
				break
	return out


func current_body_id() -> String:
	return current_body


## The body the player is *effectively* at: the world they are standing in, or
## — while they are aboard the ship — whatever the ship is orbiting.
func reference_body_id() -> String:
	if current_body != "" and current_body != SHIP_ID and bodies.has(current_body):
		return current_body
	if travel != null and travel.orbiting != "":
		return travel.orbiting
	return start_body


func current_system_id() -> String:
	var b: Dictionary = bodies.get(reference_body_id(), {})
	return String(b.get("system_id", home_system))


func selection() -> String:
	return selected_body


## Highlight a body. Emits `selection_changed` and `Events.planet_selected`.
func select(id: String) -> void:
	if selected_body == id:
		return
	selected_body = id
	selection_changed.emit(id)
	Events.planet_selected.emit(id)


## Fuel needed to jump to `id` from where the ship currently is.
func fuel_cost_to(id: String) -> int:
	# The proving ground is a testing convenience, never a progression gate.
	if id == reference_body_id() or id == SHIP_ID or id == SUPERFLAT_ID:
		return 0
	var to_sys: String = String(bodies.get(id, {}).get("system_id", ""))
	var from_sys := current_system_id()
	if to_sys == "" or to_sys == from_sys:
		return 2
	var a: Vector2 = systems.get(from_sys, {}).get("pos", Vector2.ZERO)
	var b: Vector2 = systems.get(to_sys, {}).get("pos", Vector2.ZERO)
	var dist := a.distance_to(b)
	var threat := int(bodies.get(id, {}).get("threat", 1))
	return clampi(3 + int(round(dist * 4.0)) + threat, 2, 120)


## Can the ship make this jump right now?
## Returns `{ok:bool, reason:String, fuel:int, have:int, threat:int,
##            required_ftl:int, ftl:int, armour_advice:String}`.
func can_travel_to(id: String) -> Dictionary:
	var b: Dictionary = bodies.get(id, {})
	var meta: Dictionary = planets.get(id, {})
	var threat := int(b.get("threat", meta.get("threat", 1)))
	var cost := fuel_cost_to(id)
	var have := fuel()
	var ftl := ftl_tier()
	var out := {
		"ok": false, "reason": "", "fuel": cost, "have": have,
		"threat": threat, "required_ftl": threat, "ftl": ftl,
		"armour_advice": "",
	}
	if meta.is_empty():
		out["reason"] = "No landing site."
		return out
	if not bool(b.get("landable", true)) and not b.is_empty():
		out["reason"] = "No landing site."
		return out
	if id == reference_body_id():
		out["reason"] = "Already here."
		return out
	if threat > ftl:
		out["reason"] = "FTL drive tier %d required." % threat
		return out
	if have < cost:
		out["reason"] = "Needs %d fuel, you have %d." % [cost, have]
		return out
	var armour := armour_tier()
	if armour + 2 < threat:
		out["armour_advice"] = "Armour looks thin for threat %d." % threat
	out["ok"] = true
	return out


## Everything the star map panel needs for one frame, in one call.
func star_map_snapshot() -> Dictionary:
	return {
		"seed": galaxy_seed,
		"sectors": sector_order.duplicate(),
		"current_body": current_body,
		"orbiting": travel.orbiting if travel != null else "",
		"current_system": current_system_id(),
		"selected": selected_body,
		"fuel": fuel(),
		"fuel_capacity": fuel_capacity(),
		"ftl_tier": ftl_tier(),
		"hull_tier": hull_tier(),
		"max_threat": ftl_tier(),
	}


## Case-insensitive substring search over discovered body and system names.
func search(query: String) -> Array[String]:
	var q := query.strip_edges().to_lower()
	var out: Array[String] = []
	if q == "":
		return out
	for id: String in body_order:
		if not discovered.has(id):
			continue
		if String(bodies[id]["name"]).to_lower().contains(q):
			out.append(id)
	return out


func _threat_color_of(t: int) -> Color:
	var c: Color = THREAT_COLORS[clampi(t, 0, THREAT_COLORS.size() - 1)]
	return c


func _tint_of(t: Dictionary) -> Color:
	var c: Color = t["tint"]
	return c


func threat_name(t: int) -> String:
	return String(THREAT_NAMES[clampi(t, 0, THREAT_NAMES.size() - 1)])


func threat_color(t: int) -> Color:
	var c: Color = THREAT_COLORS[clampi(t, 0, THREAT_COLORS.size() - 1)]
	return c


# ------------------------------------------------------------ discovery state
func discover(id: String) -> void:
	if id == "" or discovered.has(id):
		return
	discovered[id] = true
	body_discovered.emit(id)


## Reveal every body of a system at once (star charts, deep scans).
func discover_system(system_id: String) -> void:
	for b in system_body_ids(system_id):
		discover(b)
		for m in moon_ids(b):
			discover(m)


## Reveal one random unknown system; used by the `star_chart` item.
## Returns the system id, or "" when everything is already known.
func reveal_random_system() -> String:
	var candidates: Array[String] = []
	for sid: String in system_order:
		var known := false
		for b in (systems[sid]["bodies"] as Array):
			if discovered.has(String(b)):
				known = true
				break
		if not known:
			candidates.append(sid)
	if candidates.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pickd: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	discover_system(pickd)
	return pickd


func mark_visited(id: String) -> void:
	discover(id)
	if visited.has(id):
		return
	visited[id] = true
	body_visited.emit(id)


func set_scan_level(id: String, level: int) -> void:
	var cur := scan_of(id)
	if level <= cur:
		return
	scan_level[id] = level
	discover(id)
	body_scanned.emit(id, level)


func store_scan_report(id: String, report: Dictionary) -> void:
	scan_reports[id] = report


# ---------------------------------------------------- ship capability shortcuts
func fuel() -> int:
	return upgrades.fuel if upgrades != null else 0


func fuel_capacity() -> int:
	return upgrades.fuel_capacity if upgrades != null else 0


func ftl_tier() -> int:
	return upgrades.ftl_tier if upgrades != null else 1


func hull_tier() -> int:
	return upgrades.hull_tier if upgrades != null else 1


## Best armour tier the player is wearing, queried defensively — the armour
## system may not exist yet.
func armour_tier() -> int:
	var p: Node = Game.player
	if p == null:
		return 0
	for m: StringName in [&"armour_tier", &"armor_tier"]:
		if p.has_method(m):
			return int(p.call(m))
	var v: Variant = p.get("armor_tier")
	if v != null:
		return int(v)
	v = p.get("armour_tier")
	if v != null:
		return int(v)
	return 0


func notify_capabilities_changed() -> void:
	capabilities_changed.emit()


# ============================================================== persistence
## Only volatile state is stored — the galaxy itself is a pure function of the
## seed, so a save is tiny and always regenerates identically.
func save_state() -> Dictionary:
	return {
		"seed": galaxy_seed,
		"discovered": discovered.keys(),
		"visited": visited.keys(),
		"scan_level": scan_level.duplicate(),
		"scan_reports": scan_reports.duplicate(true),
		"current": current_body,
		"selected": selected_body,
		"upgrades": upgrades.save_state() if upgrades != null else {},
		"teleporter": teleporter.save_state() if teleporter != null else {},
		"ship": ship.save_state() if ship != null else {},
		"travel": travel.save_state() if travel != null else {},
	}


func load_state(d: Dictionary) -> void:
	var s := int(d.get("seed", galaxy_seed))
	if s != galaxy_seed or planets.is_empty():
		generate(s)
	discovered.clear()
	for k in (d.get("discovered", []) as Array):
		discovered[String(k)] = true
	visited.clear()
	for k in (d.get("visited", []) as Array):
		visited[String(k)] = true
	scan_level = (d.get("scan_level", {}) as Dictionary).duplicate()
	scan_reports = (d.get("scan_reports", {}) as Dictionary).duplicate(true)
	current_body = String(d.get("current", start_body))
	selected_body = String(d.get("selected", start_body))
	if upgrades != null:
		upgrades.load_state(d.get("upgrades", {}))
	if teleporter != null:
		teleporter.load_state(d.get("teleporter", {}))
	if ship != null:
		ship.load_state(d.get("ship", {}))
	if travel != null:
		travel.load_state(d.get("travel", {}))
	galaxy_generated.emit(galaxy_seed)


# ============================================================== static tables
func _build_star_classes() -> void:
	_star_classes.assign([
		{"key": "m", "name": "Red Dwarf", "color": Color(0.98, 0.45, 0.34), "heat": -0.55, "weight": 3.0},
		{"key": "k", "name": "Orange Dwarf", "color": Color(1.0, 0.68, 0.38), "heat": -0.22, "weight": 2.4},
		{"key": "g", "name": "Yellow Star", "color": Color(1.0, 0.94, 0.74), "heat": 0.0, "weight": 2.0},
		{"key": "f", "name": "White Star", "color": Color(0.93, 0.96, 1.0), "heat": 0.2, "weight": 1.4},
		{"key": "a", "name": "Blue-White Star", "color": Color(0.74, 0.84, 1.0), "heat": 0.45, "weight": 1.0},
		{"key": "b", "name": "Blue Giant", "color": Color(0.56, 0.70, 1.0), "heat": 0.72, "weight": 0.6},
		{"key": "neutron", "name": "Neutron Star", "color": Color(0.88, 0.97, 1.0), "heat": 0.35,
			"weight": 0.35, "exotic": true},
		{"key": "binary", "name": "Binary Pair", "color": Color(1.0, 0.84, 0.58), "heat": 0.18,
			"weight": 0.45, "exotic": true},
		{"key": "blackhole", "name": "Black Hole", "color": Color(0.42, 0.24, 0.62), "heat": 0.0,
			"weight": 0.2, "exotic": true},
	])


## The planet archetype table. Keys match `TYPE_ORDER`; every field is consumed
## by `_build_meta()` above.
func _build_type_table() -> void:
	_types = {}
	_deftype("garden", "Garden", [1, 2], [0.05, 0.3], [0.0, 0.02], true, [0.9, 1.05],
		"normal", "none", ["clear", "rain", "fog", "wind"],
		{"garden": 0.4, "forest": 0.25, "plains": 0.2, "beach": 0.1, "ocean": 0.05},
		[0.15, 0.3], 0.95, Color(0.45, 0.78, 0.42),
		[Color(0.36, 0.60, 0.95), Color(0.72, 0.86, 0.95)], Color(1.0, 0.99, 0.94),
		["copper_ore", "coal"], ["theme_human"], [512, 768], 0.7, 1.0, 0.35)
	_deftype("forest", "Forest", [1, 3], [0.0, 0.35], [0.0, 0.05], true, [0.85, 1.15],
		"normal", "none", ["clear", "rain", "storm", "fog", "wind"],
		{"forest": 0.42, "plains": 0.24, "taiga": 0.12, "ocean": 0.12, "mountains": 0.1},
		[0.2, 0.35], 0.9, Color(0.35, 0.68, 0.36),
		[Color(0.34, 0.58, 0.94), Color(0.70, 0.84, 0.94)], Color(1.0, 0.98, 0.92),
		["copper_ore", "iron_ore", "coal"], ["theme_human", "theme_floran"],
		[512, 832], 0.7, 1.0, 0.4)
	_deftype("moon", "Moon", [1, 2], [-0.6, -0.1], [0.05, 0.2], false, [0.25, 0.45],
		"none", "airless", ["clear", "meteor_shower"],
		{"moon": 0.7, "barren": 0.3},
		[0.0, 0.0], 0.02, Color(0.72, 0.72, 0.75),
		[Color(0.02, 0.02, 0.05), Color(0.10, 0.10, 0.16)], Color(0.85, 0.88, 1.0),
		["iron_ore", "moonstone_ore"], ["theme_ancient"], [256, 384], 0.0, 0.6, 0.12,
		"eternal_night", 0.05, 1.0)
	_deftype("barren", "Barren", [1, 3], [-0.2, 0.35], [0.0, 0.15], false, [0.5, 0.9],
		"thin", "airless", ["clear", "wind", "meteor_shower"],
		{"barren": 0.55, "badlands": 0.25, "mountains": 0.2},
		[0.0, 0.05], 0.05, Color(0.62, 0.55, 0.45),
		[Color(0.16, 0.16, 0.22), Color(0.42, 0.38, 0.36)], Color(0.95, 0.92, 0.88),
		["iron_ore", "silver_ore"], ["theme_ancient", "theme_glitch"],
		[384, 640], 0.1, 0.9, 0.2)
	_deftype("desert", "Desert", [2, 4], [0.45, 0.85], [0.0, 0.1], true, [0.85, 1.1],
		"normal", "heat", ["clear", "sandstorm", "wind"],
		{"desert": 0.5, "savannah": 0.2, "badlands": 0.2, "beach": 0.1},
		[0.02, 0.12], 0.25, Color(0.90, 0.80, 0.48),
		[Color(0.42, 0.62, 0.92), Color(0.95, 0.83, 0.60)], Color(1.0, 0.96, 0.82),
		["copper_ore", "gold_ore", "silver_ore"], ["theme_apex", "theme_ancient"],
		[512, 832], 0.3, 1.05, 0.5)
	_deftype("tundra", "Tundra", [2, 4], [-0.85, -0.35], [0.0, 0.05], true, [0.85, 1.1],
		"normal", "cold", ["clear", "snow", "blizzard", "wind", "aurora"],
		{"tundra": 0.45, "taiga": 0.3, "mountains": 0.15, "ocean": 0.1},
		[0.1, 0.25], 0.4, Color(0.82, 0.90, 0.95),
		[Color(0.52, 0.70, 0.94), Color(0.86, 0.92, 0.98)], Color(0.92, 0.96, 1.0),
		["iron_ore", "silver_ore"], ["theme_avian", "theme_human"],
		[512, 768], 0.5, 0.95, 0.5)
	_deftype("ocean", "Ocean", [2, 4], [0.05, 0.45], [0.0, 0.05], true, [0.9, 1.15],
		"dense", "none", ["clear", "rain", "storm", "fog"],
		{"ocean": 0.6, "beach": 0.2, "jungle": 0.1, "plains": 0.1},
		[0.6, 0.85], 0.6, Color(0.30, 0.58, 0.85),
		[Color(0.26, 0.52, 0.92), Color(0.62, 0.82, 0.96)], Color(0.92, 0.98, 1.0),
		["coral_shard", "silver_ore"], ["theme_hylotl"], [640, 1024], 0.75, 1.0, 0.55)
	_deftype("mushroom", "Fungal", [2, 4], [-0.1, 0.3], [0.05, 0.2], true, [0.8, 1.05],
		"dense", "toxic", ["clear", "spore_fall", "fog"],
		{"mushroom": 0.55, "swamp": 0.25, "forest": 0.2},
		[0.2, 0.4], 0.85, Color(0.72, 0.45, 0.78),
		[Color(0.32, 0.24, 0.44), Color(0.62, 0.44, 0.66)], Color(0.90, 0.80, 1.0),
		["iron_ore", "titanium_ore"], ["theme_floran"], [448, 704], 0.5, 0.9, 0.45,
		"day_night", 0.08, 0.9, 0.2)
	_deftype("jungle", "Jungle", [3, 5], [0.4, 0.75], [0.0, 0.1], true, [0.9, 1.2],
		"dense", "none", ["clear", "rain", "storm", "fog"],
		{"jungle": 0.5, "swamp": 0.2, "forest": 0.2, "ocean": 0.1},
		[0.25, 0.4], 1.0, Color(0.24, 0.62, 0.30),
		[Color(0.30, 0.56, 0.86), Color(0.62, 0.84, 0.72)], Color(0.92, 1.0, 0.88),
		["titanium_ore", "gold_ore"], ["theme_floran", "theme_apex"],
		[576, 896], 0.8, 1.15, 0.6)
	_deftype("crystal", "Crystalline", [3, 5], [-0.4, 0.2], [0.1, 0.35], false, [0.6, 0.95],
		"thin", "radiation", ["clear", "aurora", "meteor_shower"],
		{"crystal": 0.6, "barren": 0.25, "mountains": 0.15},
		[0.0, 0.1], 0.2, Color(0.62, 0.82, 0.98),
		[Color(0.10, 0.12, 0.28), Color(0.42, 0.56, 0.86)], Color(0.80, 0.92, 1.0),
		["crystal_shard", "titanium_ore", "diamond_ore"], ["theme_ancient", "theme_glitch"],
		[384, 640], 0.2, 0.85, 0.3, "day_night", 0.18, 0.9, 0.25)
	_deftype("toxic", "Toxic", [3, 5], [0.1, 0.5], [0.15, 0.4], false, [0.85, 1.15],
		"toxic", "toxic", ["acid_rain", "fog", "storm", "spore_fall"],
		{"toxic": 0.55, "swamp": 0.25, "badlands": 0.2},
		[0.3, 0.5], 0.5, Color(0.55, 0.78, 0.28),
		[Color(0.30, 0.42, 0.16), Color(0.62, 0.74, 0.30)], Color(0.85, 1.0, 0.70),
		["titanium_ore", "uranium_ore"], ["theme_glitch", "theme_apex"],
		[512, 768], 0.6, 1.1, 0.5, "day_night", 0.05, 0.85, 0.7)
	_deftype("midnight", "Midnight", [4, 6], [-0.5, 0.0], [0.05, 0.25], true, [0.9, 1.25],
		"dense", "dark", ["fog", "storm", "clear"],
		{"midnight": 0.55, "forest": 0.2, "swamp": 0.15, "mountains": 0.1},
		[0.15, 0.3], 0.55, Color(0.40, 0.28, 0.52),
		[Color(0.06, 0.05, 0.14), Color(0.22, 0.16, 0.34)], Color(0.66, 0.60, 0.90),
		["titanium_ore", "durasteel_ore"], ["theme_ancient", "theme_glitch"],
		[512, 832], 0.4, 1.3, 0.4, "eternal_night", 0.06, 0.45, 0.5)
	_deftype("alien", "Alien", [4, 6], [-0.2, 0.5], [0.1, 0.45], false, [0.7, 1.35],
		"toxic", "radiation", ["clear", "radiation_storm", "storm", "aurora"],
		{"alien": 0.55, "crystal": 0.15, "toxic": 0.15, "badlands": 0.15},
		[0.1, 0.3], 0.65, Color(0.72, 0.34, 0.80),
		[Color(0.24, 0.10, 0.36), Color(0.62, 0.32, 0.72)], Color(0.92, 0.72, 1.0),
		["aegisalt_ore", "durasteel_ore", "uranium_ore"], ["theme_ancient"],
		[512, 896], 0.5, 1.2, 0.45, "nebula", 0.12, 0.9, 0.4)
	_deftype("volcanic", "Volcanic", [4, 6], [0.65, 0.95], [0.05, 0.2], false, [0.95, 1.4],
		"toxic", "heat", ["ash_fall", "ember_fall", "storm"],
		{"magma": 0.45, "ash": 0.3, "badlands": 0.15, "mountains": 0.1},
		[0.15, 0.35], 0.1, Color(0.85, 0.32, 0.18),
		[Color(0.28, 0.10, 0.08), Color(0.78, 0.34, 0.14)], Color(1.0, 0.72, 0.52),
		["durasteel_ore", "gold_ore", "uranium_ore"], ["theme_apex", "theme_ancient"],
		[448, 768], 0.3, 1.25, 0.5, "day_night", 0.14, 1.0, 0.6)
	_deftype("scorched", "Scorched", [5, 6], [0.85, 1.0], [0.2, 0.5], false, [0.9, 1.3],
		"none", "heat", ["clear", "ember_fall", "meteor_shower", "radiation_storm"],
		{"ash": 0.4, "magma": 0.3, "barren": 0.3},
		[0.0, 0.05], 0.02, Color(0.95, 0.58, 0.22),
		[Color(0.42, 0.16, 0.06), Color(0.94, 0.58, 0.22)], Color(1.0, 0.82, 0.60),
		["durasteel_ore", "aegisalt_ore", "solarium_ore"], ["theme_ancient"],
		[384, 640], 0.1, 1.15, 0.35, "day_night", 0.1, 1.35, 0.2)
	_deftype("ruins", "Ruined", [5, 6], [-0.3, 0.4], [0.2, 0.6], false, [0.6, 1.1],
		"thin", "radiation", ["clear", "radiation_storm", "fog", "ash_fall"],
		{"ruins": 0.5, "barren": 0.25, "badlands": 0.25},
		[0.05, 0.2], 0.15, Color(0.58, 0.56, 0.62),
		[Color(0.14, 0.14, 0.20), Color(0.46, 0.44, 0.50)], Color(0.86, 0.88, 0.94),
		["aegisalt_ore", "solarium_ore", "durasteel_ore"], ["theme_ancient", "theme_glitch"],
		[320, 576], 0.2, 0.8, 0.3, "nebula", 0.1, 0.8, 0.4)


func _deftype(key: String, display: String, threat: Array, temp: Array, rad: Array,
		breathable: bool, gravity: Array, atmosphere: String, hazard: String,
		weather: Array, biomes: Dictionary, ocean: Array, vegetation: float,
		icon: Color, sky: Array, tint: Color, ores: Array, dungeons: Array,
		size: Array, clouds: float, sun_energy: float, ambient_energy: float,
		sky_type: String = "day_night", ambient: float = 0.0,
		p_weight: float = 1.0, hazard_strength: float = 0.0) -> void:
	_types[key] = {
		"display": display, "threat": threat, "temp": temp, "rad": rad,
		"breathable": breathable, "gravity": gravity, "atmosphere": atmosphere,
		"hazard": hazard, "hazard_strength": hazard_strength,
		"weather": weather, "biomes": biomes, "ocean": ocean,
		"vegetation": vegetation, "icon": icon, "sky": sky, "tint": tint,
		"ores": ores, "dungeons": dungeons, "size": size, "clouds": clouds,
		"sun_energy": sun_energy, "ambient_energy": ambient_energy,
		"sky_type": sky_type, "ambient": ambient, "weight": p_weight,
		"day": [0.75, 1.4], "surface": 96, "sea_drop": 6,
		"liquid": "lava" if key == "volcanic" or key == "scorched" else "water",
		"structures": [],
	}
