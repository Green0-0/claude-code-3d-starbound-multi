class_name Universe
extends RefCounted

## The star map: sectors, systems, planets and the fuel it costs to reach them.
##
## Everything is derived from one seed, so the whole chart exists as data long
## before any of it is generated as terrain. A planet is a seed plus a biome
## weighting plus a threat level; travelling to one is "reseed the world and
## stream it in again", which is why the voxel world takes its parameters from
## a dictionary rather than from constants.

const SECTORS := ["Aegis", "Bellows", "Cinder Reach", "Dolmen", "Everdark"]
const STAR_CLASSES := [
	{"name": "yellow dwarf", "color": Color(1.0, 0.92, 0.66), "heat": 0.5},
	{"name": "red giant", "color": Color(1.0, 0.52, 0.36), "heat": 0.85},
	{"name": "blue supergiant", "color": Color(0.66, 0.80, 1.0), "heat": 1.0},
	{"name": "white dwarf", "color": Color(0.92, 0.96, 1.0), "heat": 0.3},
	{"name": "dying ember", "color": Color(0.72, 0.36, 0.28), "heat": 0.15},
]

## key, display, dominant biome, threat bias, sky tint, fuel multiplier
const PLANET_TYPES := [
	{"key": &"garden", "name": "Garden", "biome": &"forest", "threat": 0,
		"sky": Color(0.44, 0.66, 0.92), "ground": Color(0.36, 0.58, 0.30)},
	{"key": &"forest", "name": "Forest", "biome": &"forest", "threat": 1,
		"sky": Color(0.40, 0.60, 0.86), "ground": Color(0.26, 0.48, 0.24)},
	{"key": &"desert", "name": "Desert", "biome": &"desert", "threat": 1,
		"sky": Color(0.86, 0.74, 0.52), "ground": Color(0.80, 0.68, 0.42)},
	{"key": &"savannah", "name": "Savannah", "biome": &"savannah", "threat": 1,
		"sky": Color(0.78, 0.72, 0.50), "ground": Color(0.62, 0.56, 0.28)},
	{"key": &"tundra", "name": "Tundra", "biome": &"tundra", "threat": 2,
		"sky": Color(0.72, 0.82, 0.92), "ground": Color(0.86, 0.90, 0.96)},
	{"key": &"jungle", "name": "Jungle", "biome": &"jungle", "threat": 2,
		"sky": Color(0.42, 0.62, 0.60), "ground": Color(0.18, 0.46, 0.20)},
	{"key": &"ocean", "name": "Ocean", "biome": &"ocean", "threat": 2,
		"sky": Color(0.36, 0.60, 0.86), "ground": Color(0.24, 0.44, 0.52)},
	{"key": &"toxic", "name": "Toxic", "biome": &"toxic", "threat": 3,
		"sky": Color(0.56, 0.68, 0.34), "ground": Color(0.42, 0.54, 0.24)},
	{"key": &"volcanic", "name": "Volcanic", "biome": &"volcanic", "threat": 4,
		"sky": Color(0.48, 0.24, 0.18), "ground": Color(0.30, 0.16, 0.12)},
	{"key": &"moon", "name": "Moon", "biome": &"moon", "threat": 3,
		"sky": Color(0.10, 0.10, 0.14), "ground": Color(0.64, 0.64, 0.62)},
	{"key": &"barren", "name": "Barren", "biome": &"barren", "threat": 2,
		"sky": Color(0.42, 0.38, 0.36), "ground": Color(0.48, 0.44, 0.40)},
	{"key": &"alien", "name": "Alien", "biome": &"alien", "threat": 4,
		"sky": Color(0.44, 0.26, 0.56), "ground": Color(0.40, 0.24, 0.50)},
	{"key": &"crystal", "name": "Crystalline", "biome": &"crystal", "threat": 4,
		"sky": Color(0.52, 0.66, 0.86), "ground": Color(0.56, 0.70, 0.86)},
	{"key": &"ancient", "name": "Ruined", "biome": &"ancient_ruins", "threat": 5,
		"sky": Color(0.34, 0.30, 0.40), "ground": Color(0.60, 0.56, 0.46)},
]

const THREAT_NAMES := ["Placid", "Gentle", "Moderate", "Dangerous", "Hostile",
	"Extreme", "Lethal"]

const SYLLABLES_A := ["Ker", "Vas", "Tan", "Ori", "Zel", "Mir", "Hal", "Dro",
	"Ny", "Cal", "Ser", "Uth", "Pra", "Ix", "Bel", "Rho"]
const SYLLABLES_B := ["ath", "ion", "usk", "aris", "eth", "ora", "un", "iel",
	"ax", "orn", "essa", "ir", "ul", "ane"]

const SHIP_ID := "ship"
const PROVING_ID := "proving_ground"


class Planet extends RefCounted:
	var id := ""
	var display := ""
	var system := ""
	var sector := ""
	var type_key: StringName = &"garden"
	var type_name := "Garden"
	var biome: StringName = &"forest"
	var threat := 0
	var seed_value := 0
	var orbit := 1
	var sky := Color(0.4, 0.6, 0.9)
	var ground := Color(0.3, 0.5, 0.3)
	var star_color := Color(1, 1, 1)
	var fuel_cost := 1
	var gravity := 1.0
	var discovered := false
	var visited := false
	var hostiles := true
	var flat := false                  ## the proving ground

	func threat_name() -> String:
		return Universe.THREAT_NAMES[clampi(threat, 0, 6)]

	## The dictionary the voxel world reads to configure its generator.
	func world_config() -> Dictionary:
		return {
			"seed": seed_value, "biome": biome, "threat": threat,
			"sky": sky, "ground": ground, "star": star_color,
			"flat": flat, "hostiles": hostiles, "gravity": gravity,
			"type": type_key,
		}


class System extends RefCounted:
	var id := ""
	var display := ""
	var sector := ""
	var star_name := ""
	var star_color := Color(1, 1, 1)
	var position := Vector2.ZERO      ## chart coordinates
	var planets: Array[Planet] = []
	var discovered := false


var systems: Array[System] = []
var planets := {}                     ## id -> Planet
var by_system := {}
var home_system := ""
var _rng := RandomNumberGenerator.new()


func generate(seed_value: int) -> void:
	systems.clear()
	planets.clear()
	by_system.clear()
	_rng.seed = seed_value

	var index := 0
	for s in SECTORS.size():
		var count := _rng.randi_range(3, 5)
		for i in count:
			var sys := _make_system(SECTORS[s], index, s, i)
			systems.append(sys)
			by_system[sys.id] = sys
			index += 1

	home_system = systems[0].id
	systems[0].discovered = true
	for p: Planet in systems[0].planets:
		p.discovered = true

	_add_proving_ground()


func _make_system(sector: String, index: int, ring: int, slot: int) -> System:
	var sys := System.new()
	sys.id = "sys_%d" % index
	sys.sector = sector
	sys.display = _name()
	var star: Dictionary = STAR_CLASSES[_rng.randi() % STAR_CLASSES.size()]
	sys.star_name = String(star["name"])
	sys.star_color = star["color"]
	# chart layout: sectors are rings, systems sit around them
	var angle := float(slot) / 5.0 * TAU + float(ring) * 0.7
	var radius := 0.22 + float(ring) * 0.17
	sys.position = Vector2(cos(angle), sin(angle)) * radius

	var bodies := _rng.randi_range(2, 4)
	for orbit in range(1, bodies + 1):
		var p := _make_planet(sys, orbit, ring, float(star["heat"]))
		sys.planets.append(p)
		planets[p.id] = p
	return sys


func _make_planet(sys: System, orbit: int, ring: int, heat: float) -> Planet:
	var p := Planet.new()
	p.id = "%s_p%d" % [sys.id, orbit]
	p.system = sys.id
	p.sector = sys.sector
	p.orbit = orbit
	p.seed_value = _rng.randi()
	p.star_color = sys.star_color

	# hot stars and inner orbits push toward volcanic; cold outer ones toward ice
	var warmth := heat + (0.5 - float(orbit) * 0.18)
	var candidates: Array = []
	for t: Dictionary in PLANET_TYPES:
		var want := 1.0
		match StringName(t["key"]):
			&"volcanic", &"desert", &"savannah": want = warmth
			&"tundra", &"moon", &"barren": want = 1.2 - warmth
			&"ocean", &"jungle", &"garden", &"forest": want = 1.0 - absf(warmth - 0.55)
			_: want = 0.5
		# deeper sectors unlock the nastier types
		if int(t["threat"]) > ring + 1:
			want *= 0.15
		if want > 0.0:
			for i in maxi(1, int(want * 6.0)):
				candidates.append(t)
	var chosen: Dictionary = candidates[_rng.randi() % candidates.size()]
	p.type_key = chosen["key"]
	p.type_name = String(chosen["name"])
	p.biome = chosen["biome"]
	p.sky = chosen["sky"]
	p.ground = chosen["ground"]
	p.threat = clampi(int(chosen["threat"]) + ring - 1 + _rng.randi_range(0, 1), 0, 6)
	p.display = "%s %s" % [sys.display, _roman(orbit)]
	p.fuel_cost = 1 + ring + (1 if p.threat >= 4 else 0)
	p.gravity = _rng.randf_range(0.85, 1.15)
	return p


## The Proving Ground: a flat, empty, hostile-free world parked in the home
## system, free to travel to, discovered from the first minute. It exists so the
## building, the physics and the cutaway can be exercised against terrain with
## no confounding variables — and so every run has somewhere safe to experiment.
## It ships as part of the game rather than behind a debug flag, because a
## testing world you have to enable is a testing world nobody uses.
func _add_proving_ground() -> void:
	var p := Planet.new()
	p.id = PROVING_ID
	p.display = "The Proving Ground"
	p.system = home_system
	p.sector = SECTORS[0]
	p.type_key = &"garden"
	p.type_name = "Superflat"
	p.biome = &"garden"
	p.threat = 0
	p.seed_value = 20260730
	p.sky = Color(0.52, 0.72, 0.94)
	p.ground = Color(0.36, 0.60, 0.30)
	p.fuel_cost = 0
	p.discovered = true
	p.hostiles = false
	p.flat = true
	p.orbit = 0
	planets[p.id] = p
	by_system[home_system].planets.push_front(p)


func get_planet(id: String) -> Planet:
	return planets.get(id)


func get_system(id: String) -> System:
	return by_system.get(id)


func starting_planet() -> Planet:
	var sys: System = by_system[home_system]
	for p: Planet in sys.planets:
		if not p.flat:
			return p
	return sys.planets[0]


func discover(id: String) -> void:
	var p: Planet = planets.get(id)
	if p == null:
		return
	p.discovered = true
	var sys: System = by_system.get(p.system)
	if sys != null:
		sys.discovered = true


## Discover everything in a system, which is what scanning a system does.
func scan_system(id: String) -> int:
	var sys: System = by_system.get(id)
	if sys == null:
		return 0
	var found := 0
	sys.discovered = true
	for p: Planet in sys.planets:
		if not p.discovered:
			p.discovered = true
			found += 1
	return found


func discovered_planets() -> Array[Planet]:
	var out: Array[Planet] = []
	for id in planets:
		var p: Planet = planets[id]
		if p.discovered:
			out.append(p)
	out.sort_custom(func(a: Planet, b: Planet) -> bool:
		if a.system != b.system:
			return a.system < b.system
		return a.orbit < b.orbit)
	return out


func _name() -> String:
	return "%s%s" % [SYLLABLES_A[_rng.randi() % SYLLABLES_A.size()],
		SYLLABLES_B[_rng.randi() % SYLLABLES_B.size()]]


static func _roman(n: int) -> String:
	const NUMERALS := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
	return NUMERALS[clampi(n, 0, NUMERALS.size() - 1)]


func save_state() -> Dictionary:
	var disc: Array = []
	var vis: Array = []
	for id in planets:
		var p: Planet = planets[id]
		if p.discovered:
			disc.append(id)
		if p.visited:
			vis.append(id)
	return {"discovered": disc, "visited": vis}


func load_state(d: Dictionary) -> void:
	for id in d.get("discovered", []):
		discover(String(id))
	for id in d.get("visited", []):
		var p: Planet = planets.get(String(id))
		if p != null:
			p.visited = true
			p.discovered = true
