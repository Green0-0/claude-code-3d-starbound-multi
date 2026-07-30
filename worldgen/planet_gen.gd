## Autoloaded as `PlanetGen`. The terrain orchestrator: it owns the noise bank,
## the biome table and the four generation stages, and it is the single entry
## point every other module uses to ask "what is the world like here?".
##
## Generation is a fixed pipeline, run per chunk:
##
##   1. `TerrainShaper.fill_chunk`  heightfield, strata, overhangs, sky islands
##   2. `CaveGen.carve`             worms, chambers, shafts, ravines, lava tubes,
##                                  hidden axis-aligned passages
##   3. `CaveGen.place_ores`        veins and blobs, depth-gated by tier
##   4. `CaveGen.place_geodes`      hollow gem chambers
##   5. `WorldDecorator.decorate`   trees, plants, scatter, snow/ash cover
##   6. `WorldDecorator.fill_liquids`  oceans, rivers, the deep lava sea —
##                                  last, so it flows around kelp and coral
##                                  instead of drowning the decoration pass
##   7. `structures/structure_placer.gd` (optional, owned by another agent)
##
## **Determinism.** Every stage is a pure function of (seed, world coordinate).
## Nothing reads a neighbouring chunk, nothing mutates shared state, and every
## feature that can cross a chunk border is generated from a *cell grid* around
## the chunk rather than from the chunk itself. Chunks may therefore be built
## in any order, on any frame, and unloaded and rebuilt identically.
##
## ---
##
## ### Planet `meta` keys consumed
##
## These are the keys `space/universe.gd` documents, plus a few private
## overrides. Every one is optional — sensible values are derived from `type`.
##
## | key | type | meaning |
## |---|---|---|
## | `seed` | int | per-planet seed (World passes it separately too) |
## | `type` | String | planet archetype, see `BiomeTable.planet_profile()` |
## | `generator` | String | `planet`; `flat`/`void` produce empty chunks |
## | `threat` | int | 1..6, raises radioactive ore rates |
## | `size_x`, `size_z` | int | planet extent; wraps on both |
## | `surface_level` | int | mean altitude of dry land |
## | `sea_level` | int | waterline; open space below it floods |
## | `ocean_level` | float | 0..1 fraction of surface below the waterline |
## | `liquid` | String | ocean fluid: `water`, `toxic_water`, `lava` |
## | `temperature` | float | -1 frozen .. +1 scorching, biases the climate field |
## | `biome_weights` | Dictionary | biome key -> weight; keys go through `BiomeTable.alias()` |
## | `primary_biome` | String | guaranteed-present headline biome |
## | `cave_density` | float | 0.4..1.8 cave volume multiplier (0 disables) |
## | `vegetation` | float | 0..1 flora density multiplier |
## | `ore_bias` | Dictionary | ore block name -> multiplier |
## | `gravity` | float | forwarded to gameplay, not used by terrain |
##
## Private overrides, useful for debugging or hand-authored worlds:
## `base`, `roughness`, `mountains`, `caves`, `overhangs`, `islands`,
## `lava_level`, `lava_tubes`, `mantle_y`, `core_y`.
extends Node

const STRUCTURE_PLACER := "res://worldgen/structures/structure_placer.gd"

var noise: NoiseBank
var shaper: TerrainShaper
var caves: CaveGen
var decor: WorldDecorator

var meta: Dictionary = {}
var profile: Dictionary = {}
var planet_type: StringName = &"forest"
## `planet` (generate terrain), or `flat` / `void` (leave empty — the space
## agent stamps those worlds itself).
var generator: StringName = &"planet"
var threat: int = 1
var gravity: float = 1.0
var seed_value: int = 0
var sea_level: int = 96
var size_x: int = Const.PLANET_SIZE_DEFAULT
var size_z: int = Const.PLANET_SIZE_DEFAULT
var ready_flag := false

var _placer: Script = null
var _placer_obj: Object = null
var _placer_checked := false


# ============================================================ planet lifecycle
## Bind the generator to a planet. Called by `World.create_world()`.
func begin_planet(p_seed: int, p_meta: Dictionary) -> void:
	seed_value = p_seed
	meta = p_meta.duplicate(true)
	planet_type = StringName(meta.get("type", &"forest"))
	generator = StringName(meta.get("generator", &"planet"))
	threat = int(meta.get("threat", 1))
	gravity = float(meta.get("gravity", 1.0))
	size_x = int(meta.get("size_x", Const.PLANET_SIZE_DEFAULT))
	size_z = int(meta.get("size_z", Const.PLANET_SIZE_DEFAULT))
	profile = BiomeTable.planet_profile(planet_type)

	noise = NoiseBank.new(p_seed, size_x, size_z,
		float(meta.get("roughness", profile.get("roughness", 1.0))))
	shaper = TerrainShaper.new()
	shaper.configure(noise, meta, profile)
	sea_level = shaper.sea_level
	caves = CaveGen.new()
	caves.configure(noise, shaper, meta, profile)
	decor = WorldDecorator.new()
	decor.configure(noise, shaper, meta, profile)

	_placer = null
	_placer_obj = null
	_placer_checked = false
	ready_flag = true
	print("[PlanetGen] %s planet, seed %d, %dx%d, sea %d" % [planet_type, p_seed, size_x, size_z, sea_level])


## Safety net: if anything asks for terrain before `begin_planet` ran (a tool
## script, a test, a reloaded save), configure from whatever `World` knows.
## The world is reached through the tree rather than by its autoload name —
## `World` is what calls this file, and naming it here would be a cycle.
func _ensure() -> void:
	if ready_flag:
		return
	var w := get_node_or_null(^"/root/World")
	var m: Dictionary = {}
	var s := 0
	if w != null:
		var pm = w.get(&"planet")
		if pm is Dictionary:
			m = pm
		var sv = w.get(&"seed_value")
		if sv != null:
			s = int(sv)
	begin_planet(s, m)


# ================================================================== generation
## Fill `chunk`. Deterministic in (seed, chunk position).
func generate_chunk(chunk: Chunk) -> void:
	_ensure()
	if generator == &"superflat":
		_fill_superflat(chunk)
		return
	if generator != &"planet":
		# `flat` and `void` worlds (the ship, the outpost) are stamped in code by
		# the space agent — see `space/stamp.gd`. We must leave them empty.
		chunk.recount()
		chunk.populated = true
		return
	shaper.fill_chunk(chunk)
	caves.carve(chunk)
	caves.place_ores(chunk)
	caves.place_geodes(chunk)
	decor.decorate(chunk)
	decor.fill_liquids(chunk)
	chunk.recount()
	_place_structures(chunk)
	chunk.populated = true


## Minecraft-style superflat: bedrock, stone, soil, grass, nothing else.
##
## This is the testing world. It is deliberately featureless — no caves, ores,
## structures, liquids or decoration — so that building, physics, the flip and
## the layer shift can be exercised against terrain with no confounding
## variables. `flat_height` is the Y of the grass course.
func _fill_superflat(chunk: Chunk) -> void:
	var top: int = clampi(int(meta.get("flat_height", 64)), 4, Const.WORLD_HEIGHT - 2)
	var o := chunk.origin()
	# Chunks entirely above the surface stay empty; entirely below, solid stone.
	if o.y > top:
		chunk.recount()
		chunk.populated = true
		return
	var id_bedrock := _block_id(&"bedrock", &"stone")
	var id_stone := _block_id(&"stone", &"cobblestone")
	var id_soil := _block_id(&"dirt", &"loam")
	var id_grass := _block_id(&"grass", &"dirt")
	for ly in Const.CHUNK_SIZE:
		var y := o.y + ly
		if y > top:
			break
		var id := id_stone
		if y == 0:
			id = id_bedrock
		elif y == top:
			id = id_grass
		elif y > top - 4:
			id = id_soil
		for lz in Const.CHUNK_SIZE:
			for lx in Const.CHUNK_SIZE:
				chunk.blocks[Chunk.index(lx, ly, lz)] = id
	chunk.recount()
	chunk.populated = true


## Resolve a block name with a fallback, so a missing content pack degrades to
## something solid rather than to air.
func _block_id(name: StringName, fallback: StringName) -> int:
	if Blocks.has(name):
		return Blocks.id(name)
	if Blocks.has(fallback):
		return Blocks.id(fallback)
	return Const.AIR


## Hand the finished chunk to the structure agent, if it has landed yet.
##
## `populate(chunk: Chunk, gen: Node)` — static or instance, both are supported
## — may rely on:
##   * the chunk's terrain, caves, ores, liquids and decoration being complete;
##   * `gen.height_at(x, z)`, `gen.biome_at(x, z)`, `gen.biome_of(x, z)`,
##     `gen.column(x, z)`, `gen.sea_level`, `gen.planet_type`, `gen.threat`,
##     `gen.meta`, `gen.rng_at(...)`, `gen.block_id(...)` — all wrap-safe;
##   * nothing about generation order, and no neighbouring chunk being loaded.
func _place_structures(chunk: Chunk) -> void:
	if not _placer_checked:
		_placer_checked = true
		if ResourceLoader.exists(STRUCTURE_PLACER):
			var sp = load(STRUCTURE_PLACER)
			if sp and sp.has_method("populate"):
				_placer = sp
				# Support a non-static `populate` too: instantiate once and
				# keep the instance for the lifetime of the planet.
				if not _is_static(sp, "populate") and sp.can_instantiate():
					_placer_obj = sp.new()
	if _placer_obj != null:
		_placer_obj.call(&"populate", chunk, self)
	elif _placer != null:
		_placer.populate(chunk, self)


func _is_static(scr: Script, method: String) -> bool:
	for m: Dictionary in scr.get_script_method_list():
		if String(m.get("name", "")) == method:
			return (int(m.get("flags", 0)) & METHOD_FLAG_STATIC) != 0
	return true


# =================================================================== queries
## Biome key at a world column. Monsters, weather, music and NPCs key off this.
func biome_at(x: int, z: int) -> StringName:
	_ensure()
	return shaper.biome_at(x, z).key


## Surface height at a column, without loading the chunk.
##
## Must agree with whatever `generate_chunk` actually builds. A superflat world
## has no heightfield at all, and returning the noise height there spawned the
## player ~32 blocks above the ground, which killed them on arrival.
func height_at(x: int, z: int) -> int:
	_ensure()
	if generator != &"planet":
		return clampi(int(meta.get("flat_height", meta.get("surface_level", 64))),
			0, Const.WORLD_HEIGHT - 1)
	return shaper.height_at(x, z)


## The full `Biome` object for a column — palette, monsters, hazard, music.
func biome_of(x: int, z: int) -> Biome:
	_ensure()
	return shaper.biome_at(x, z)


## Look a biome up by key without needing a position.
func biome_data(key: StringName) -> Biome:
	return BiomeTable.get_biome(key)


## Every biome on this planet type, in table order.
func planet_biomes() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in profile.get("biomes", []):
		out.append(StringName(k))
	return out


## Everything about one column: height, biome, slope, beach/underwater flags.
func column(x: int, z: int) -> Dictionary:
	_ensure()
	return shaper.column(x, z)


## Height of the terrain surface — alias of `height_at`, kept for readers who
## expect `World.surface_y`-style naming.
func surface_y(x: int, z: int) -> int:
	return height_at(x, z)


## Sky tint for the current column, for the camera / weather agents.
func sky_color_at(x: int, z: int) -> Color:
	return biome_of(x, z).sky_color


## Music cue for a column.
func music_at(x: int, z: int) -> StringName:
	return biome_of(x, z).music


## Hazard key (`none`, `heat`, `cold`, `toxic`, `radiation`, `airless`, `dark`).
func hazard_at(x: int, z: int) -> StringName:
	return biome_of(x, z).hazard


## Monster spawn pool for a column. `night` swaps to the nocturnal list.
func monsters_at(x: int, z: int, night: bool = false) -> Array[StringName]:
	var b := biome_of(x, z)
	return b.night_monsters if night else b.monsters


## The planet's ore table as plain dictionaries, for crafting / progression.
func ore_table() -> Array[Dictionary]:
	_ensure()
	return caves.ore_table()


## Safe player spawn with clearance in all four viewing planes.
func find_spawn() -> Vector3:
	_ensure()
	return SpawnFinder.find_spawn(size_x, size_z)


# ==================================================================== helpers
## Resolve a block name with a fallback, so callers never hit an unknown id.
func block_id(name: StringName, fallback: StringName = &"stone") -> int:
	return Biome.block_id(name, fallback)


## A deterministic RNG stream for a world position. Use this instead of
## `randi()` anywhere a structure needs to look random but stay reproducible.
func rng_at(x: int, y: int, z: int, salt: int = 0) -> RandomNumberGenerator:
	return NoiseBank.rng_at(posmod(x, size_x), y, posmod(z, size_z), salt ^ seed_value)


## Deterministic 0..1 roll for a world position.
func chance_at(x: int, y: int, z: int, salt: int = 0) -> float:
	return NoiseBank.rand01(posmod(x, size_x), y, posmod(z, size_z), salt ^ seed_value)
