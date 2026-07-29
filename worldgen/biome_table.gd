## The biome database and the climate lookup that picks one for a column.
##
## Twenty biomes cover the Starbound palette. Every other system keys off the
## `StringName` in the first column below, so these names are a contract:
##
##   forest  savannah  desert  tundra  snow  jungle  swamp  ocean  alien
##   toxic   volcanic  midnight  garden  moon  barren  scorched
##   bioluminescent   crystal_caverns   mushroom_fields   ancient_ruins
##
## Selection is `(temperature, humidity, elevation)` -> nearest climate box,
## filtered by the planet type's allowed set. Both temperature and humidity are
## 0..1 fields; elevation is measured in "sea levels" (-1 deep ocean, 0 shore,
## +1 peaks).
class_name BiomeTable
extends RefCounted

static var _table: Array[Biome] = []
static var _index: Dictionary = {}


## Every biome, built once per process.
static func all() -> Array[Biome]:
	if _table.is_empty():
		_build()
	return _table


static func get_biome(key: StringName) -> Biome:
	if _table.is_empty():
		_build()
	var i: int = _index.get(key, -1)
	return _table[i] if i >= 0 else _table[0]


static func index_of(key: StringName) -> int:
	if _table.is_empty():
		_build()
	return int(_index.get(key, 0))


static func by_index(i: int) -> Biome:
	if _table.is_empty():
		_build()
	return _table[clampi(i, 0, _table.size() - 1)]


static func count() -> int:
	return all().size()


## Pick the best biome index for a climate sample. `allowed` is a list of table
## indices (usually the planet's palette); empty means "anything". `bonus`, if
## given, is one weight per table index — the planet's `biome_weights` — which
## nudges the climate match without overriding it.
static func select(temp: float, hum: float, elev: float,
		allowed: PackedInt32Array = PackedInt32Array(),
		bonus: PackedFloat32Array = PackedFloat32Array()) -> int:
	if _table.is_empty():
		_build()
	var best := 0
	var best_score := INF
	var use_bonus := bonus.size() == _table.size()
	if allowed.is_empty():
		for i in _table.size():
			var s: float = _table[i].score(temp, hum, elev)
			if use_bonus:
				s -= bonus[i] * 0.35
			if s < best_score:
				best_score = s
				best = i
		return best
	for i: int in allowed:
		var s: float = _table[i].score(temp, hum, elev)
		if use_bonus:
			s -= bonus[i] * 0.35
		if s < best_score:
			best_score = s
			best = i
	if best_score == INF:
		# Every allowed biome rejected the elevation band (e.g. an ocean trench
		# on a desert planet); fall back to the whole table.
		return select(temp, hum, elev)
	return best


## Map another module's biome vocabulary onto ours. `space/universe.gd` ships
## `biome_weights` using its own names (plains, taiga, magma, ruins, ...); this
## is where they become one of our twenty keys. Returns `&""` if unrecognised.
static func alias(key: StringName) -> StringName:
	if _table.is_empty():
		_build()
	if _index.has(key):
		return key
	match key:
		&"plains", &"meadow", &"grassland": return &"forest"
		&"taiga", &"arctic", &"ice", &"snowfield": return &"snow"
		&"beach", &"shore", &"reef", &"deep_ocean", &"sea": return &"ocean"
		&"mountains", &"highlands", &"rocky": return &"barren"
		&"badlands", &"wasteland", &"dunes": return &"desert"
		&"magma", &"lava", &"inferno": return &"volcanic"
		&"ash", &"cinder", &"burnt": return &"scorched"
		&"crystal", &"crystalline", &"geode": return &"crystal_caverns"
		&"mushroom", &"fungal", &"spore": return &"mushroom_fields"
		&"ruins", &"ancient", &"temple": return &"ancient_ruins"
		&"glow", &"luminous", &"biolume": return &"bioluminescent"
		&"dark", &"night", &"gloom": return &"midnight"
		&"marsh", &"bog", &"wetland": return &"swamp"
		&"radioactive", &"acid": return &"toxic"
	return &""


## Per-planet-type profile: climate bias, the biome palette that type may use,
## and the coarse terrain knobs the shaper reads.
##
## Keys: `temp`, `hum` (additive bias 0-centred), `temp_var`, `hum_var`
## (multiplies the climate noise contrast), `sea` (sea level in blocks), `base`
## (mean land altitude; 0 = auto, meaning `sea + 8`), `roughness`, `mountains`,
## `cave`, `liquid`, `sky`, `biomes`.
static func planet_profile(type: StringName) -> Dictionary:
	var p := {
		"temp": 0.0, "hum": 0.0, "temp_var": 1.0, "hum_var": 1.0,
		"sea": 96, "base": 0, "roughness": 1.0, "mountains": 1.0, "cave": 1.0,
		"liquid": &"water", "sky": Color(0.42, 0.62, 0.92),
		"biomes": [&"forest", &"garden", &"savannah", &"swamp", &"ocean"],
	}
	match type:
		&"forest":
			p["biomes"] = [&"forest", &"garden", &"swamp", &"savannah", &"ocean", &"mushroom_fields"]
		&"garden":
			p["temp"] = 0.05
			p["hum"] = 0.1
			p["biomes"] = [&"garden", &"forest", &"jungle", &"ocean", &"mushroom_fields"]
		&"desert":
			p["temp"] = 0.34
			p["hum"] = -0.32
			p["sea"] = 80
			p["mountains"] = 0.8
			p["biomes"] = [&"desert", &"savannah", &"scorched", &"barren", &"ancient_ruins"]
		&"savannah":
			p["temp"] = 0.2
			p["hum"] = -0.12
			p["biomes"] = [&"savannah", &"desert", &"forest", &"ocean"]
		&"snow", &"arctic":
			p["temp"] = -0.38
			p["hum"] = 0.08
			p["sea"] = 92
			p["mountains"] = 1.25
			p["biomes"] = [&"snow", &"tundra", &"crystal_caverns", &"ocean", &"barren"]
		&"tundra":
			p["temp"] = -0.24
			p["biomes"] = [&"tundra", &"snow", &"forest", &"ocean"]
		&"jungle":
			p["temp"] = 0.22
			p["hum"] = 0.34
			p["roughness"] = 1.15
			p["biomes"] = [&"jungle", &"swamp", &"forest", &"bioluminescent", &"ocean"]
		&"swamp":
			p["hum"] = 0.3
			p["sea"] = 100
			p["base"] = 99
			p["mountains"] = 0.55
			p["biomes"] = [&"swamp", &"jungle", &"mushroom_fields", &"ocean"]
		&"ocean":
			p["sea"] = 132
			p["base"] = 112
			p["mountains"] = 0.6
			p["biomes"] = [&"ocean", &"forest", &"jungle", &"bioluminescent"]
		&"toxic":
			p["hum"] = 0.2
			p["temp"] = 0.08
			p["liquid"] = &"toxic_water"
			p["sky"] = Color(0.45, 0.62, 0.28)
			p["biomes"] = [&"toxic", &"swamp", &"mushroom_fields", &"alien"]
		&"volcanic", &"magma":
			p["temp"] = 0.55
			p["hum"] = -0.28
			p["sea"] = 40
			p["base"] = 58
			p["mountains"] = 1.35
			p["roughness"] = 1.2
			p["cave"] = 1.3
			p["liquid"] = &"lava"
			p["sky"] = Color(0.45, 0.16, 0.12)
			p["biomes"] = [&"volcanic", &"scorched", &"barren", &"crystal_caverns"]
		&"scorched":
			p["temp"] = 0.62
			p["hum"] = -0.45
			p["sea"] = 30
			p["base"] = 70
			p["sky"] = Color(0.58, 0.36, 0.2)
			p["biomes"] = [&"scorched", &"volcanic", &"desert", &"barren"]
		&"barren":
			p["hum"] = -0.4
			p["sea"] = 20
			p["base"] = 72
			p["mountains"] = 0.9
			p["sky"] = Color(0.36, 0.36, 0.4)
			p["biomes"] = [&"barren", &"desert", &"moon", &"ancient_ruins"]
		&"moon":
			p["temp"] = -0.2
			p["hum"] = -0.5
			p["sea"] = 0
			p["base"] = 80
			p["mountains"] = 1.1
			p["cave"] = 1.35
			p["sky"] = Color(0.05, 0.05, 0.09)
			p["biomes"] = [&"moon", &"barren", &"crystal_caverns", &"ancient_ruins"]
		&"midnight":
			p["temp"] = -0.1
			p["hum"] = 0.15
			p["sky"] = Color(0.1, 0.08, 0.18)
			p["biomes"] = [&"midnight", &"mushroom_fields", &"bioluminescent", &"forest"]
		&"alien":
			p["roughness"] = 1.3
			p["mountains"] = 1.2
			p["sky"] = Color(0.5, 0.3, 0.62)
			p["biomes"] = [&"alien", &"bioluminescent", &"crystal_caverns", &"toxic", &"ocean"]
		&"bioluminescent":
			p["hum"] = 0.22
			p["sky"] = Color(0.12, 0.2, 0.35)
			p["biomes"] = [&"bioluminescent", &"mushroom_fields", &"jungle", &"midnight"]
		&"crystal":
			p["temp"] = -0.15
			p["hum"] = -0.2
			p["roughness"] = 1.25
			p["mountains"] = 1.3
			p["sky"] = Color(0.3, 0.42, 0.62)
			p["biomes"] = [&"crystal_caverns", &"barren", &"moon", &"snow"]
		&"mushroom":
			p["hum"] = 0.35
			p["biomes"] = [&"mushroom_fields", &"swamp", &"bioluminescent", &"forest"]
		&"ancient", &"ruins":
			p["hum"] = -0.15
			p["mountains"] = 0.85
			p["sky"] = Color(0.5, 0.46, 0.55)
			p["biomes"] = [&"ancient_ruins", &"barren", &"desert", &"forest"]
	return p


## The `biomes` list of a profile as table indices, ready for `select()`.
static func palette_indices(profile: Dictionary) -> PackedInt32Array:
	if _table.is_empty():
		_build()
	var out := PackedInt32Array()
	for k in profile.get("biomes", []):
		var sn := StringName(k)
		if _index.has(sn):
			out.append(int(_index[sn]))
	if out.is_empty():
		out.append(0)
	return out


# ============================================================== the table
static func _register(b: Biome) -> Biome:
	_index[b.key] = _table.size()
	_table.append(b)
	return b


static func _build() -> void:
	_table = []
	_index = {}

	# ---------------------------------------------------------------- forest
	_register(Biome.new(&"forest", "Forest")
		.climate(0.38, 0.68, 0.35, 0.72, -0.05, 0.55, 1.2)
		.ground(&"grass", &"loam", &"stone", &"granite", &"sand", 4)
		.flora([&"oak", &"birch", &"pine"], 0.30, [&"grass_tuft", &"tall_grass", &"fern"],
			[&"flower_red", &"flower_yellow", &"flower_white"], 0.34, 0.07)
		.decorate({"boulder": 0.05, "log": 0.05, "mushroom": 0.04})
		.shape(1.0, 1.0, 0.05, 1.0, 1.0)
		.ores({&"copper_ore": 1.2, &"iron_ore": 1.0, &"coal_ore": 1.2, &"silver_ore": 0.9})
		.palette(Color(0.45, 0.66, 0.94), Color(1.0, 1.0, 0.97))
		.life([&"hopper", &"crawler", &"tree_lurker"], [&"stalker", &"wisp"], 1.0, [&"glow_moth"])
		.audio(&"music_forest", &"amb_forest"))

	# -------------------------------------------------------------- savannah
	_register(Biome.new(&"savannah", "Savannah")
		.climate(0.6, 0.82, 0.18, 0.45, -0.05, 0.45, 1.0)
		.ground(&"savannah_grass", &"savannah_soil", &"savannah_stone", &"limestone", &"sand", 3)
		.flora([&"acacia", &"baobab"], 0.10, [&"grass_tuft", &"savannah_shrub", &"dry_grass"],
			[&"flower_yellow", &"flower_orange"], 0.42, 0.05)
		.decorate({"boulder": 0.06, "log": 0.02, "bones": 0.02})
		.shape(0.7, 0.8, 0.25, 0.9, 0.9)
		.ores({&"copper_ore": 1.3, &"iron_ore": 1.0, &"gold_ore": 1.1})
		.palette(Color(0.62, 0.72, 0.9), Color(1.0, 0.98, 0.86))
		.life([&"savannah_runner", &"hopper", &"spitter"], [&"stalker"], 1.0, [&"glow_moth"])
		.audio(&"music_savannah", &"amb_wind"))

	# ---------------------------------------------------------------- desert
	_register(Biome.new(&"desert", "Desert")
		.climate(0.75, 1.0, 0.0, 0.25, -0.1, 0.6, 1.1)
		.ground(&"sand", &"desert_soil", &"sandstone", &"desert_stone", &"sand", 7)
		.water(&"water", &"sand")
		.flora([&"cactus_tall", &"dead_tree"], 0.06, [&"dead_bush", &"desert_shrub"],
			[&"flower_cactus"], 0.10, 0.02)
		.decorate({"boulder": 0.04, "bones": 0.03, "cactus": 0.09})
		.shape(0.65, 0.9, 0.35, 1.0, 0.8)
		.ores({&"copper_ore": 1.0, &"gold_ore": 1.4, &"titanium_ore": 1.1, &"salt_deposit": 1.8})
		.palette(Color(0.68, 0.78, 0.95), Color(1.0, 0.96, 0.82))
		.life([&"sand_worm", &"scorch_hound", &"spitter"], [&"husk"], 0.85)
		.audio(&"music_desert", &"amb_wind")
		.danger(Biome.HAZARD_HEAT, 0.4))

	# ---------------------------------------------------------------- tundra
	_register(Biome.new(&"tundra", "Tundra")
		.climate(0.12, 0.32, 0.25, 0.6, -0.05, 0.5, 1.0)
		.ground(&"tundra_grass", &"frozen_dirt", &"slate", &"schist", &"gravel", 4)
		.flora([&"snow_pine", &"dead_tree"], 0.12, [&"snow_shrub", &"grass_tuft"],
			[&"flower_blue"], 0.20, 0.03)
		.decorate({"boulder": 0.07, "log": 0.03}, &"snow")
		.shape(0.85, 0.85, 0.15, 1.0, 0.9)
		.ores({&"iron_ore": 1.2, &"silver_ore": 1.2, &"coal_ore": 1.0})
		.palette(Color(0.6, 0.72, 0.88), Color(0.94, 0.97, 1.0))
		.life([&"ice_stalker", &"hopper"], [&"ice_stalker", &"wisp"], 0.8, [&"tundra_elk"])
		.audio(&"music_tundra", &"amb_wind")
		.danger(Biome.HAZARD_COLD, 0.3))

	# ------------------------------------------------------------------ snow
	_register(Biome.new(&"snow", "Snowfield")
		.climate(0.0, 0.18, 0.3, 0.85, 0.0, 1.0, 1.1)
		.ground(&"snow", &"frozen_dirt", &"ice_stone", &"packed_ice", &"gravel", 5)
		.water(&"water", &"ice")
		.flora([&"snow_pine", &"frost_pine"], 0.22, [&"snow_shrub"], [], 0.12, 0.01)
		.decorate({"boulder": 0.06, "log": 0.02, "crystal": 0.02}, &"snow")
		.shape(1.3, 1.0, 0.1, 1.0, 1.1)
		.ores({&"iron_ore": 1.1, &"silver_ore": 1.3, &"cerulium_ore": 1.2, &"sapphire_ore": 1.3})
		.palette(Color(0.66, 0.78, 0.94), Color(0.9, 0.95, 1.0))
		.life([&"ice_stalker", &"frost_golem"], [&"ice_stalker", &"wisp"], 0.9)
		.audio(&"music_snow", &"amb_wind")
		.danger(Biome.HAZARD_COLD, 0.7))

	# ---------------------------------------------------------------- jungle
	_register(Biome.new(&"jungle", "Jungle")
		.climate(0.68, 0.95, 0.7, 1.0, -0.05, 0.6, 1.2)
		.ground(&"jungle_grass", &"rich_soil", &"limestone", &"granite", &"sand", 5)
		.flora([&"jungle_giant", &"jungle_palm", &"vine_tree"], 0.48,
			[&"jungle_fern", &"tall_grass", &"fern"],
			[&"flower_pink", &"flower_orange", &"fungal_bloom"], 0.55, 0.12)
		.decorate({"boulder": 0.03, "log": 0.06, "mushroom": 0.05, "vine": 0.3})
		.shape(1.05, 1.2, 0.0, 1.1, 1.3)
		.ores({&"copper_ore": 1.2, &"gold_ore": 1.2, &"emerald_ore": 1.4})
		.palette(Color(0.38, 0.62, 0.86), Color(0.92, 1.0, 0.9))
		.life([&"tree_lurker", &"spitter", &"swinger"], [&"stalker", &"venom_bat"], 1.3)
		.audio(&"music_jungle", &"amb_forest"))

	# ----------------------------------------------------------------- swamp
	_register(Biome.new(&"swamp", "Swamp")
		.climate(0.5, 0.75, 0.75, 1.0, -0.25, 0.15, 1.1)
		.ground(&"mud", &"peat", &"slate", &"schist", &"silt", 6)
		.water(&"swamp_water", &"mud")
		.flora([&"willow", &"swamp_cypress", &"dead_tree"], 0.26,
			[&"reed", &"tall_grass", &"fern"], [&"flower_purple"], 0.4, 0.05)
		.decorate({"log": 0.08, "mushroom": 0.09, "vine": 0.2, "boulder": 0.02})
		.shape(0.4, 0.7, 0.3, 1.0, 0.8)
		.ores({&"coal_ore": 1.4, &"iron_ore": 1.0, &"sulphur_ore": 1.4})
		.palette(Color(0.46, 0.54, 0.5), Color(0.9, 0.96, 0.86))
		.life([&"swamp_leech", &"crawler", &"spitter"], [&"wisp", &"husk"], 1.1)
		.audio(&"music_swamp", &"amb_swamp")
		.danger(Biome.HAZARD_TOXIC, 0.15))

	# ----------------------------------------------------------------- ocean
	_register(Biome.new(&"ocean", "Ocean")
		.climate(0.25, 0.85, 0.4, 1.0, -1.0, -0.12, 1.4)
		.ground(&"sand", &"silt", &"seafloor_rock", &"slate", &"sand", 5)
		.water(&"water", &"seabed_ooze")
		.flora([], 0.0, [&"kelp", &"sea_grass", &"ocean_grass"], [&"sea_anemone"], 0.35, 0.06)
		.decorate({"coral": 0.22, "boulder": 0.04})
		.shape(0.35, 0.6, 0.0, 0.7, 0.5)
		.ores({&"copper_ore": 0.8, &"iron_ore": 0.9, &"cerulium_ore": 1.4, &"salt_deposit": 1.5})
		.palette(Color(0.32, 0.56, 0.9), Color(0.8, 0.92, 1.0))
		.life([&"deep_one", &"drifter"], [&"deep_one"], 0.7, [&"glow_fish"])
		.audio(&"music_ocean", &"amb_ocean"))

	# ------------------------------------------------------------------ alien
	_register(Biome.new(&"alien", "Alien Wastes")
		.climate(0.3, 0.7, 0.2, 0.7, -0.05, 0.75, 0.9)
		.ground(&"alien_grass", &"alien_dirt", &"alien_rock", &"alien_rock", &"alien_sand", 4)
		.flora([&"alien_bulb", &"tentacle_tree"], 0.24, [&"alien_shoot", &"glowbulb"],
			[&"alien_flower"], 0.3, 0.09)
		.decorate({"boulder": 0.05, "crystal": 0.05, "mushroom": 0.03})
		.shape(1.2, 1.35, 0.0, 1.2, 1.4)
		.ores({&"violium_ore": 1.3, &"aegisalt_ore": 1.2, &"platinum_ore": 1.1})
		.palette(Color(0.52, 0.3, 0.66), Color(0.94, 0.86, 1.0), Color(0.5, 0.34, 0.6), 0.08)
		.life([&"lurcher", &"floater", &"spitter"], [&"void_wraith"], 1.2)
		.audio(&"music_alien", &"amb_hum"))

	# ------------------------------------------------------------------ toxic
	_register(Biome.new(&"toxic", "Toxic Marsh")
		.climate(0.45, 0.8, 0.6, 1.0, -0.2, 0.4, 0.9)
		.ground(&"toxic_grass", &"toxic_dirt", &"toxic_stone", &"stone", &"toxic_sand", 4)
		.water(&"toxic_water", &"toxic_dirt")
		.flora([&"toxic_tree", &"dead_tree"], 0.18, [&"toxic_fungus", &"reed"],
			[&"toxic_flower"], 0.32, 0.08)
		.decorate({"mushroom": 0.1, "log": 0.03, "boulder": 0.03})
		.shape(0.6, 0.9, 0.15, 1.15, 0.9)
		.ores({&"uranium_ore": 1.6, &"plutonium_ore": 1.2, &"sulphur_ore": 1.5})
		.palette(Color(0.44, 0.6, 0.26), Color(0.86, 1.0, 0.7), Color(0.4, 0.52, 0.24), 0.05)
		.life([&"toxic_spitter", &"swamp_leech", &"husk"], [&"void_wraith", &"husk"], 1.2)
		.audio(&"music_toxic", &"amb_swamp")
		.danger(Biome.HAZARD_TOXIC, 1.0))

	# --------------------------------------------------------------- volcanic
	_register(Biome.new(&"volcanic", "Volcanic")
		.climate(0.88, 1.0, 0.0, 0.4, 0.05, 1.0, 1.2)
		.ground(&"magmarock", &"ashen_soil", &"basalt", &"obsidian", &"ash", 3)
		.water(&"lava", &"basalt")
		.flora([&"ash_tree"], 0.05, [&"ember_shrub"], [], 0.08, 0.0)
		.decorate({"boulder": 0.08, "crystal": 0.03}, &"ash")
		.shape(1.5, 1.3, 0.0, 1.35, 1.3)
		.ores({&"iron_ore": 1.3, &"titanium_ore": 1.3, &"ferozium_ore": 1.4, &"ruby_ore": 1.4})
		.palette(Color(0.42, 0.16, 0.12), Color(1.0, 0.78, 0.6), Color(0.35, 0.14, 0.1), 0.12)
		.life([&"magma_slug", &"scorch_hound", &"fire_elemental"], [&"magma_slug"], 1.3)
		.audio(&"music_volcanic", &"amb_lava")
		.danger(Biome.HAZARD_HEAT, 1.0))

	# --------------------------------------------------------------- midnight
	_register(Biome.new(&"midnight", "Midnight")
		.climate(0.25, 0.6, 0.4, 0.85, -0.05, 0.7, 0.9)
		.ground(&"midnight_grass", &"dirt", &"slate", &"void_stone", &"gravel", 4)
		.flora([&"gnarled_oak", &"bone_tree"], 0.3, [&"grass_tuft", &"glowbulb", &"dim_moss"],
			[&"flower_purple", &"glow_flower"], 0.3, 0.1)
		.decorate({"boulder": 0.05, "log": 0.05, "mushroom": 0.06, "bones": 0.04})
		.shape(1.0, 1.1, 0.05, 1.15, 1.1)
		.ores({&"silver_ore": 1.2, &"violium_ore": 1.3, &"uranium_ore": 1.1})
		.palette(Color(0.1, 0.09, 0.18), Color(0.72, 0.7, 0.92), Color(0.08, 0.07, 0.14), 0.1)
		.life([&"husk", &"stalker", &"void_wraith"], [&"void_wraith", &"husk"], 1.5)
		.audio(&"music_midnight", &"amb_night")
		.danger(Biome.HAZARD_DARK, 0.5))

	# ---------------------------------------------------------------- garden
	_register(Biome.new(&"garden", "Garden")
		.climate(0.45, 0.65, 0.5, 0.8, 0.0, 0.4, 1.0)
		.ground(&"grass", &"rich_soil", &"limestone", &"marble", &"sand", 5)
		.flora([&"cherry", &"oak", &"birch"], 0.34, [&"tall_grass", &"grass_tuft", &"fern"],
			[&"flower_pink", &"flower_white", &"flower_red", &"flower_blue"], 0.5, 0.22)
		.decorate({"boulder": 0.03, "log": 0.03, "mushroom": 0.03})
		.shape(0.75, 0.85, 0.1, 0.9, 0.9)
		.ores({&"copper_ore": 1.2, &"iron_ore": 1.0, &"gold_ore": 0.9})
		.palette(Color(0.5, 0.72, 0.98), Color(1.0, 1.0, 0.95))
		.life([&"hopper", &"critter_swarm"], [&"stalker"], 0.6, [&"glow_moth"])
		.audio(&"music_garden", &"amb_forest"))

	# ------------------------------------------------------------------ moon
	_register(Biome.new(&"moon", "Lunar Surface")
		.climate(0.0, 0.35, 0.0, 0.2, -0.2, 1.0, 1.0)
		.ground(&"moon_dust", &"regolith", &"moon_rock", &"moon_rock", &"moon_dust", 5)
		.water(&"water", &"moon_dust")
		.flora([], 0.0, [], [], 0.0, 0.0)
		.decorate({"boulder": 0.12, "crystal": 0.04})
		.shape(1.05, 1.1, 0.2, 1.4, 0.7)
		.ores({&"erchius_crystal": 2.0, &"titanium_ore": 1.2, &"solarium_ore": 1.1})
		.palette(Color(0.04, 0.04, 0.08), Color(0.78, 0.8, 0.92), Color(0.05, 0.05, 0.09), 0.02)
		.life([&"moon_husk", &"floater"], [&"moon_husk", &"void_wraith"], 0.8)
		.audio(&"music_moon", &"amb_hum")
		.danger(Biome.HAZARD_AIRLESS, 1.0))

	# ---------------------------------------------------------------- barren
	_register(Biome.new(&"barren", "Barren Flats")
		.climate(0.3, 0.7, 0.0, 0.3, -0.15, 0.7, 0.8)
		.ground(&"gravel", &"dirt", &"stone", &"granite", &"sand", 3)
		.flora([&"dead_tree"], 0.03, [&"dead_bush"], [], 0.07, 0.0)
		.decorate({"boulder": 0.1, "bones": 0.02})
		.shape(0.6, 0.75, 0.4, 1.1, 0.8)
		.ores({&"iron_ore": 1.2, &"copper_ore": 1.1, &"tin_ore": 1.3})
		.palette(Color(0.4, 0.42, 0.48), Color(0.94, 0.94, 0.94))
		.life([&"rock_crab", &"crawler"], [&"husk"], 0.7)
		.audio(&"music_barren", &"amb_wind"))

	# -------------------------------------------------------------- scorched
	_register(Biome.new(&"scorched", "Scorched Waste")
		.climate(0.82, 1.0, 0.0, 0.35, -0.1, 0.8, 0.9)
		.ground(&"charred_dirt", &"ashen_soil", &"basalt", &"scoria", &"ash", 3)
		.water(&"lava", &"basalt")
		.flora([&"burnt_tree", &"dead_tree"], 0.08, [&"ember_shrub", &"dead_bush"], [], 0.12, 0.0)
		.decorate({"boulder": 0.07, "bones": 0.05, "log": 0.03}, &"ash")
		.shape(0.9, 1.05, 0.2, 1.2, 1.0)
		.ores({&"titanium_ore": 1.2, &"ferozium_ore": 1.2, &"sulphur_ore": 1.3})
		.palette(Color(0.56, 0.34, 0.2), Color(1.0, 0.9, 0.76), Color(0.5, 0.3, 0.18), 0.05)
		.life([&"scorch_hound", &"husk", &"fire_elemental"], [&"husk"], 1.1)
		.audio(&"music_scorched", &"amb_wind")
		.danger(Biome.HAZARD_HEAT, 0.8))

	# -------------------------------------------------------- bioluminescent
	_register(Biome.new(&"bioluminescent", "Bioluminescent")
		.climate(0.4, 0.75, 0.55, 1.0, -0.1, 0.6, 1.0)
		.ground(&"glow_grass", &"loam", &"slate", &"schist", &"sand", 4)
		.flora([&"glow_tree", &"lantern_tree"], 0.3,
			[&"glowbulb", &"glow_fungus", &"deepglow_algae"],
			[&"glow_flower", &"flower_blue"], 0.42, 0.2)
		.decorate({"mushroom": 0.09, "crystal": 0.05, "log": 0.03, "vine": 0.12})
		.shape(1.0, 1.1, 0.0, 1.15, 1.2)
		.ores({&"cerulium_ore": 1.4, &"violium_ore": 1.2, &"amethyst_ore": 1.3})
		.palette(Color(0.1, 0.18, 0.32), Color(0.72, 0.9, 1.0), Color(0.08, 0.16, 0.3), 0.2)
		.life([&"glow_moth", &"floater", &"lurcher"], [&"floater", &"wisp"], 1.0, [&"glow_moth"])
		.audio(&"music_biolume", &"amb_hum"))

	# ------------------------------------------------------- crystal caverns
	_register(Biome.new(&"crystal_caverns", "Crystal Fields")
		.climate(0.15, 0.5, 0.0, 0.45, 0.1, 1.0, 0.9)
		.ground(&"crystal_sand", &"gravel", &"crystal_stone", &"prismatic_rock", &"crystal_sand", 3)
		.flora([&"crystal_spire"], 0.2, [&"crystal_blue", &"crystal_violet"], [], 0.18, 0.0)
		.decorate({"crystal": 0.22, "boulder": 0.06})
		.shape(1.35, 1.25, 0.1, 1.3, 1.2)
		.ores({&"amethyst_ore": 1.8, &"topaz_ore": 1.5, &"solarium_ore": 1.3, &"platinum_ore": 1.2})
		.palette(Color(0.3, 0.44, 0.66), Color(0.86, 0.94, 1.0), Color(0.26, 0.4, 0.6), 0.15)
		.life([&"crystal_lurker", &"rock_crab"], [&"crystal_lurker"], 0.9)
		.audio(&"music_crystal", &"amb_hum"))

	# ------------------------------------------------------- mushroom fields
	_register(Biome.new(&"mushroom_fields", "Mushroom Fields")
		.climate(0.35, 0.65, 0.7, 1.0, -0.1, 0.45, 0.9)
		.ground(&"mycelium", &"dirt", &"limestone", &"marble", &"sand", 4)
		.flora([&"giant_mushroom", &"glow_mushroom_tree"], 0.36,
			[&"mushroom_red", &"mushroom_brown", &"mushroom_blue", &"glow_mushroom"],
			[&"fungal_bloom", &"spore_pod"], 0.5, 0.1)
		.decorate({"mushroom": 0.25, "log": 0.05, "boulder": 0.02})
		.shape(0.7, 0.9, 0.2, 1.1, 1.0)
		.ores({&"copper_ore": 1.1, &"uranium_ore": 1.1, &"violium_ore": 1.1})
		.palette(Color(0.34, 0.36, 0.5), Color(0.9, 0.86, 1.0), Color(0.3, 0.32, 0.46), 0.12)
		.life([&"shroom_hopper", &"spore_floater"], [&"shroom_hopper", &"wisp"], 1.0)
		.audio(&"music_mushroom", &"amb_hum"))

	# --------------------------------------------------------- ancient ruins
	_register(Biome.new(&"ancient_ruins", "Ancient Ruins")
		.climate(0.35, 0.75, 0.15, 0.55, 0.05, 0.8, 0.7)
		.ground(&"cracked_sandstone", &"dirt", &"ancient_stone", &"marble", &"sand", 3)
		.flora([&"dead_tree", &"gnarled_oak"], 0.08, [&"dead_bush", &"grass_tuft", &"faint_lichen"],
			[&"flower_white"], 0.16, 0.02)
		.decorate({"boulder": 0.09, "bones": 0.05, "log": 0.02})
		.shape(0.8, 0.9, 0.45, 1.0, 0.9)
		.ores({&"gold_ore": 1.4, &"platinum_ore": 1.3, &"aegisalt_ore": 1.2, &"solarium_ore": 1.2})
		.palette(Color(0.52, 0.5, 0.58), Color(0.96, 0.94, 0.9), Color(0.48, 0.46, 0.52), 0.04)
		.life([&"guardian", &"husk", &"stalker"], [&"guardian", &"void_wraith"], 1.2)
		.audio(&"music_ruins", &"amb_hum"))
