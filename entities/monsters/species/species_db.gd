## The bestiary. A static registry of every `MobSpecies`, loaded once on first
## access from the content files in this directory.
##
## Content files follow the same convention as `content/blocks`: each exposes
## `static func register_all(db) -> void` and calls `db.add(...)`. They are
## listed explicitly (rather than scanned) so load order is deterministic and
## exported builds cannot lose one.
class_name MobSpeciesDB
extends RefCounted

const CONTENT_FILES: Array[String] = [
	"res://entities/monsters/species/01_ground.gd",
	"res://entities/monsters/species/02_flying.gd",
	"res://entities/monsters/species/03_aquatic.gd",
	"res://entities/monsters/species/04_ranged.gd",
	"res://entities/monsters/species/05_special.gd",
	"res://entities/monsters/species/06_critters.gd",
	"res://entities/monsters/boss/boss_species.gd",
]

static var _by_id: Dictionary = {}                ## StringName -> MobSpecies
static var _order: Array[StringName] = []
static var _by_biome: Dictionary = {}             ## StringName -> Array[MobSpecies]
static var _loaded := false


## Idempotent. Every public entry point calls this first.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in CONTENT_FILES:
		if not ResourceLoader.exists(path):
			push_warning("[Mobs] missing species file %s" % path)
			continue
		var scr: Script = load(path)
		if scr != null and scr.has_method(&"register_all"):
			scr.call(&"register_all", MobSpeciesDB)
	_index_biomes()
	print("[Mobs] %d species registered" % _order.size())


static func _index_biomes() -> void:
	_by_biome.clear()
	for b: StringName in MobSpecies.ALL_BIOMES:
		_by_biome[b] = []
	for sid: StringName in _order:
		var sp: MobSpecies = _by_id[sid]
		var list: Array = sp.biomes if not sp.biomes.is_empty() else MobSpecies.ALL_BIOMES
		for b: StringName in list:
			if not _by_biome.has(b):
				_by_biome[b] = []
			(_by_biome[b] as Array).append(sp)


# ================================================================== registry
## Register a species. Called by the content files; returns it for chaining.
static func add(sp: MobSpecies) -> MobSpecies:
	if sp == null or sp.id == &"":
		push_error("[Mobs] tried to register a nameless species")
		return sp
	if _by_id.has(sp.id):
		push_error("[Mobs] duplicate species id '%s'" % sp.id)
		return _by_id[sp.id]
	_by_id[sp.id] = sp
	_order.append(sp.id)
	return sp


## Shorthand used by content files: `db.define(&"grub", "Pebble Grub")`.
static func define(p_id: StringName, display: String = "") -> MobSpecies:
	return add(MobSpecies.new(p_id, display))


static func get_species(p_id: StringName) -> MobSpecies:
	ensure_loaded()
	return _by_id.get(p_id)


static func has(p_id: StringName) -> bool:
	ensure_loaded()
	return _by_id.has(p_id)


static func ids() -> Array[StringName]:
	ensure_loaded()
	return _order.duplicate()


static func count() -> int:
	ensure_loaded()
	return _order.size()


static func all() -> Array:
	ensure_loaded()
	var out: Array = []
	for sid: StringName in _order:
		out.append(_by_id[sid])
	return out


# =================================================================== queries
## Every species that can live in `biome`, ignoring time and tier. Accepts any
## of the biome spellings in `MobSpecies.BIOME_ALIASES`.
static func in_biome(biome: StringName) -> Array:
	ensure_loaded()
	return (_by_biome.get(MobSpecies.canon_biome(biome), []) as Array).duplicate()


static func of_family(fam: StringName) -> Array:
	ensure_loaded()
	var out: Array = []
	for sid: StringName in _order:
		var sp: MobSpecies = _by_id[sid]
		if sp.family == fam:
			out.append(sp)
	return out


## The spawn filter the director uses.
##
## `ctx` keys (all optional):
##   biome:StringName  threat:int  night:bool  light:int  underwater:bool
##   underground:bool  family:StringName  max_tier:int  hostile_only:bool
static func candidates(ctx: Dictionary) -> Array:
	ensure_loaded()
	var biome: StringName = ctx.get("biome", &"")
	var pool: Array = in_biome(biome) if biome != &"" else all()
	var threat: int = int(ctx.get("threat", 1))
	var max_tier: int = int(ctx.get("max_tier", threat + 2))
	var night: bool = bool(ctx.get("night", false))
	var light: int = int(ctx.get("light", 15))
	var underwater: bool = bool(ctx.get("underwater", false))
	var underground: bool = bool(ctx.get("underground", false))
	var want_family: StringName = ctx.get("family", &"")
	var hostile_only: bool = bool(ctx.get("hostile_only", false))
	var out: Array = []
	for sp: MobSpecies in pool:
		if sp.family == MobSpecies.FAM_BOSS:
			continue
		if sp.tier > max_tier:
			continue
		if want_family != &"" and sp.family != want_family:
			continue
		if hostile_only and not sp.is_hostile():
			continue
		if sp.night_only and not night:
			continue
		if sp.day_only and night:
			continue
		if sp.needs_water != underwater:
			continue
		if sp.needs_dark and not (underground or light <= 5):
			continue
		out.append(sp)
	return out


## Weighted pick from `candidates`. Species close to the planet threat tier are
## favoured so a tier-5 world is not carpeted in tier-0 grubs.
static func pick(ctx: Dictionary, rng: RandomNumberGenerator) -> MobSpecies:
	var pool: Array = candidates(ctx)
	if pool.is_empty():
		return null
	var threat: int = int(ctx.get("threat", 1))
	var total := 0.0
	var weights: Array[float] = []
	for sp: MobSpecies in pool:
		var closeness := 1.0 / (1.0 + absf(float(sp.tier) - float(threat)) * 0.55)
		var w: float = maxf(0.01, sp.spawn_weight * closeness)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


## Bestiary line used by the HUD / codex.
static func summary(p_id: StringName) -> String:
	var sp := get_species(p_id)
	if sp == null:
		return "Unknown creature"
	return "%s — %s, tier %d (%s)" % [sp.display_name, sp.family, sp.tier, sp.description]
