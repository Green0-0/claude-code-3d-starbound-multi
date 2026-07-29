## Theme -> block resolution for every structure in the game.
##
## The block-content agent owns `content/blocks/`, so we can never be sure which
## StringNames exist at the moment a structure is built. Every role therefore
## resolves through an ordered *candidate chain*: the first registered name wins,
## and the chain always ends in a block guaranteed by `content/blocks/00_core.gd`
## (stone, cobblestone, dirt, grass, sand, bedrock, water, lava).
##
## Roles are the vocabulary templates and generators speak in:
##   wall wall_alt trim floor ceiling pillar accent light glass door platform
##   ladder bars rubble roof fence path soil liquid crop treasure banner
class_name StructPalette
extends RefCounted

const THEME_APEX := &"apex"
const THEME_AVIAN := &"avian"
const THEME_FLORAN := &"floran"
const THEME_GLITCH := &"glitch"
const THEME_HYLOTL := &"hylotl"
const THEME_HUMAN := &"human"
const THEME_ANCIENT := &"ancient"
const THEME_NATURAL := &"natural"

const ALL_THEMES: Array[StringName] = [
	THEME_APEX, THEME_AVIAN, THEME_FLORAN, THEME_GLITCH,
	THEME_HYLOTL, THEME_HUMAN, THEME_ANCIENT, THEME_NATURAL,
]

## Human-facing names, handy for signs, quests and log lines.
const THEME_LABELS := {
	THEME_APEX: "Apex", THEME_AVIAN: "Avian", THEME_FLORAN: "Floran",
	THEME_GLITCH: "Glitch", THEME_HYLOTL: "Hylotl", THEME_HUMAN: "Human",
	THEME_ANCIENT: "Ancient", THEME_NATURAL: "Wild",
}

## Fallbacks that exist in the frozen core block set, per role.
const CORE_FALLBACK := {
	&"wall": &"cobblestone", &"wall_alt": &"stone", &"trim": &"stone",
	&"floor": &"stone", &"ceiling": &"cobblestone", &"pillar": &"cobblestone",
	&"accent": &"sand", &"light": &"", &"glass": &"", &"door": &"",
	&"platform": &"", &"ladder": &"", &"bars": &"", &"rubble": &"cobblestone",
	&"roof": &"cobblestone", &"fence": &"", &"path": &"cobblestone",
	&"soil": &"dirt", &"liquid": &"water", &"crop": &"", &"treasure": &"stone",
	&"banner": &"", &"core": &"bedrock",
}

## Every theme's candidate chains. Names the content agent is likely to use come
## first; generic names follow; the core fallback closes the chain.
const THEMES := {
	THEME_APEX: {
		&"wall": [&"apex_panel", &"apex_wall", &"steel_panel", &"metal_panel", &"iron_block", &"steel_block"],
		&"wall_alt": [&"apex_panel_dark", &"apex_plating", &"steel_plate", &"metal_block", &"iron_block"],
		&"trim": [&"apex_trim", &"apex_stripe", &"steel_trim", &"metal_trim"],
		&"floor": [&"apex_floor", &"steel_floor", &"metal_floor", &"steel_block", &"iron_block"],
		&"ceiling": [&"apex_ceiling", &"apex_panel", &"steel_panel", &"metal_panel"],
		&"pillar": [&"apex_pillar", &"steel_column", &"metal_pillar", &"iron_block"],
		&"accent": [&"apex_console", &"circuit_block", &"machine_block", &"copper_block"],
		&"light": [&"apex_light", &"ceiling_light", &"light_panel", &"lamp", &"glowstone", &"lumen"],
		&"glass": [&"reinforced_glass", &"lab_glass", &"glass"],
		&"door": [&"apex_door", &"metal_door", &"door"],
		&"platform": [&"metal_platform", &"steel_platform", &"platform"],
		&"ladder": [&"metal_ladder", &"ladder"],
		&"bars": [&"steel_bars", &"iron_bars", &"bars", &"cage_bars"],
		&"rubble": [&"scrap", &"rubble", &"gravel", &"cobblestone"],
		&"roof": [&"apex_panel", &"steel_panel", &"metal_panel"],
		&"fence": [&"metal_fence", &"steel_bars", &"iron_bars"],
		&"path": [&"concrete", &"steel_floor", &"cobblestone"],
		&"banner": [&"apex_banner", &"banner", &"propaganda_poster"],
	},
	THEME_AVIAN: {
		&"wall": [&"avian_stone", &"avian_brick", &"sandstone_brick", &"sandstone", &"stone_brick"],
		&"wall_alt": [&"avian_stone_carved", &"carved_sandstone", &"sandstone_carved", &"sandstone"],
		&"trim": [&"avian_gold", &"gold_block", &"brass_block", &"sandstone"],
		&"floor": [&"avian_tile", &"sandstone_tile", &"sandstone", &"stone_brick"],
		&"ceiling": [&"avian_stone", &"sandstone_brick", &"sandstone"],
		&"pillar": [&"avian_pillar", &"sandstone_pillar", &"stone_pillar", &"sandstone"],
		&"accent": [&"avian_idol", &"gold_block", &"lapis_block"],
		&"light": [&"avian_brazier", &"brazier", &"torch", &"glowstone", &"lantern"],
		&"glass": [&"stained_glass", &"glass"],
		&"door": [&"avian_door", &"wooden_door", &"door"],
		&"platform": [&"stone_platform", &"platform"],
		&"ladder": [&"vine", &"rope_ladder", &"ladder"],
		&"bars": [&"stone_bars", &"iron_bars", &"bars"],
		&"rubble": [&"sandstone_rubble", &"gravel", &"sand"],
		&"roof": [&"avian_roof", &"clay_tile", &"sandstone"],
		&"fence": [&"stone_fence", &"fence"],
		&"path": [&"sandstone", &"gravel"],
		&"banner": [&"avian_banner", &"banner"],
	},
	THEME_FLORAN: {
		&"wall": [&"floran_wood", &"living_wood", &"thatch", &"wood_planks", &"planks", &"log", &"oak_log"],
		&"wall_alt": [&"floran_bone", &"bone_block", &"thatch", &"log"],
		&"trim": [&"vine_block", &"leaves", &"thatch"],
		&"floor": [&"floran_floor", &"thatch", &"wood_planks", &"planks", &"dirt"],
		&"ceiling": [&"leaves", &"thatch", &"wood_planks", &"planks"],
		&"pillar": [&"log", &"oak_log", &"living_wood", &"wood_planks"],
		&"accent": [&"floran_totem", &"bone_block", &"skull_block", &"mushroom_block"],
		&"light": [&"glow_fungus", &"glowing_fungus", &"bioluminescent", &"torch", &"glowstone"],
		&"glass": [&"amber", &"resin", &"glass"],
		&"door": [&"floran_door", &"wooden_door", &"door"],
		&"platform": [&"wood_platform", &"platform"],
		&"ladder": [&"vine", &"ladder"],
		&"bars": [&"bone_bars", &"wood_bars", &"bars"],
		&"rubble": [&"leaves", &"dirt"],
		&"roof": [&"thatch", &"leaves", &"wood_planks"],
		&"fence": [&"spike_fence", &"wood_fence", &"fence"],
		&"path": [&"dirt", &"grass"],
		&"crop": [&"floran_crop", &"wheat", &"crop"],
		&"banner": [&"floran_banner", &"banner"],
	},
	THEME_GLITCH: {
		&"wall": [&"glitch_stone", &"castle_brick", &"stone_brick", &"cobblestone"],
		&"wall_alt": [&"glitch_stone_mossy", &"mossy_stone_brick", &"mossy_cobblestone", &"cobblestone"],
		&"trim": [&"glitch_trim", &"chiseled_stone", &"stone_brick"],
		&"floor": [&"stone_brick", &"flagstone", &"cobblestone"],
		&"ceiling": [&"stone_brick", &"cobblestone"],
		&"pillar": [&"stone_pillar", &"stone_brick", &"cobblestone"],
		&"accent": [&"glitch_circuit", &"circuit_block", &"copper_block"],
		&"light": [&"iron_sconce", &"torch", &"chandelier", &"glowstone", &"lantern"],
		&"glass": [&"stained_glass", &"glass"],
		&"door": [&"iron_door", &"wooden_door", &"door"],
		&"platform": [&"stone_platform", &"wood_platform", &"platform"],
		&"ladder": [&"ladder", &"rope_ladder"],
		&"bars": [&"iron_bars", &"bars", &"portcullis"],
		&"rubble": [&"cobblestone", &"gravel"],
		&"roof": [&"slate", &"dark_stone", &"stone_brick"],
		&"fence": [&"iron_fence", &"fence"],
		&"path": [&"cobblestone", &"gravel"],
		&"banner": [&"glitch_banner", &"banner"],
	},
	THEME_HYLOTL: {
		&"wall": [&"hylotl_stone", &"coral_brick", &"ocean_brick", &"prismarine", &"stone_brick"],
		&"wall_alt": [&"hylotl_paper", &"paper_wall", &"coral_block", &"prismarine"],
		&"trim": [&"hylotl_trim", &"dark_wood", &"wood_planks"],
		&"floor": [&"hylotl_tile", &"tatami", &"prismarine", &"stone_brick"],
		&"ceiling": [&"hylotl_stone", &"prismarine", &"stone_brick"],
		&"pillar": [&"hylotl_pillar", &"dark_wood", &"log", &"prismarine"],
		&"accent": [&"coral", &"sea_lantern_frame", &"pearl_block"],
		&"light": [&"sea_lantern", &"paper_lantern", &"glow_coral", &"glowstone", &"lantern"],
		&"glass": [&"aquarium_glass", &"glass"],
		&"door": [&"hylotl_door", &"paper_door", &"door"],
		&"platform": [&"wood_platform", &"platform"],
		&"ladder": [&"ladder", &"kelp"],
		&"bars": [&"coral_bars", &"iron_bars", &"bars"],
		&"rubble": [&"gravel", &"sand"],
		&"roof": [&"clay_tile", &"hylotl_roof", &"prismarine"],
		&"fence": [&"bamboo_fence", &"fence"],
		&"path": [&"gravel", &"sand"],
		&"liquid": [&"water"],
		&"banner": [&"hylotl_banner", &"banner"],
	},
	THEME_HUMAN: {
		&"wall": [&"concrete", &"bunker_wall", &"steel_plate", &"metal_panel", &"stone_brick"],
		&"wall_alt": [&"rusted_metal", &"rusty_plate", &"concrete_cracked", &"cobblestone"],
		&"trim": [&"hazard_stripe", &"warning_block", &"steel_trim"],
		&"floor": [&"metal_grate", &"steel_floor", &"concrete", &"stone"],
		&"ceiling": [&"concrete", &"steel_panel", &"cobblestone"],
		&"pillar": [&"steel_column", &"concrete_pillar", &"cobblestone"],
		&"accent": [&"terminal", &"console", &"machine_block", &"copper_block"],
		&"light": [&"fluorescent", &"ceiling_light", &"lamp", &"glowstone", &"torch"],
		&"glass": [&"reinforced_glass", &"glass"],
		&"door": [&"blast_door", &"metal_door", &"door"],
		&"platform": [&"metal_platform", &"platform"],
		&"ladder": [&"metal_ladder", &"ladder"],
		&"bars": [&"iron_bars", &"bars"],
		&"rubble": [&"scrap", &"gravel", &"cobblestone"],
		&"roof": [&"corrugated_metal", &"steel_panel", &"cobblestone"],
		&"fence": [&"chain_link", &"iron_fence", &"fence"],
		&"path": [&"concrete", &"gravel", &"cobblestone"],
		&"banner": [&"flag", &"banner"],
	},
	THEME_ANCIENT: {
		&"wall": [&"ancient_stone", &"obsidian_brick", &"ancient_brick", &"dark_stone", &"stone_brick"],
		&"wall_alt": [&"ancient_glyph", &"rune_stone", &"carved_obsidian", &"obsidian", &"stone_brick"],
		&"trim": [&"ancient_gold", &"gold_block", &"rune_stone"],
		&"floor": [&"ancient_tile", &"obsidian", &"dark_stone", &"stone_brick"],
		&"ceiling": [&"ancient_stone", &"dark_stone", &"stone_brick"],
		&"pillar": [&"ancient_pillar", &"obsidian_pillar", &"stone_pillar", &"obsidian"],
		&"accent": [&"ancient_core", &"rune_stone", &"crystal_block", &"amethyst_block"],
		&"light": [&"ancient_light", &"rune_light", &"glowstone", &"crystal_glow", &"torch"],
		&"glass": [&"ancient_glass", &"crystal_glass", &"glass"],
		&"door": [&"ancient_door", &"vault_door", &"stone_door", &"door"],
		&"platform": [&"ancient_platform", &"stone_platform", &"platform"],
		&"ladder": [&"ancient_ladder", &"ladder"],
		&"bars": [&"ancient_bars", &"iron_bars", &"bars"],
		&"rubble": [&"gravel", &"cobblestone"],
		&"roof": [&"ancient_stone", &"dark_stone"],
		&"fence": [&"ancient_fence", &"fence"],
		&"path": [&"ancient_tile", &"cobblestone"],
		&"core": [&"ancient_core", &"bedrock"],
		&"banner": [&"ancient_banner", &"banner"],
	},
	THEME_NATURAL: {
		&"wall": [&"stone", &"cobblestone"],
		&"wall_alt": [&"mossy_cobblestone", &"cobblestone"],
		&"trim": [&"gravel", &"stone"],
		&"floor": [&"stone", &"dirt"],
		&"ceiling": [&"stone"],
		&"pillar": [&"log", &"oak_log", &"stone"],
		&"accent": [&"mushroom_block", &"crystal_block", &"stone"],
		&"light": [&"glow_fungus", &"glowstone", &"torch"],
		&"glass": [&"ice", &"glass"],
		&"door": [&"wooden_door", &"door"],
		&"platform": [&"wood_platform", &"platform"],
		&"ladder": [&"vine", &"ladder"],
		&"bars": [&"root", &"bars"],
		&"rubble": [&"gravel", &"cobblestone"],
		&"roof": [&"leaves", &"stone"],
		&"fence": [&"wood_fence", &"fence"],
		&"path": [&"gravel", &"dirt"],
		&"soil": [&"dirt"],
	},
}

## Names used by generic (theme-independent) roles.
const GENERIC := {
	&"wood": [&"wood_planks", &"planks", &"oak_planks", &"wood", &"log"],
	&"log": [&"log", &"oak_log", &"wood_log", &"living_wood", &"wood_planks"],
	&"leaves": [&"leaves", &"oak_leaves", &"foliage"],
	&"glass": [&"glass", &"reinforced_glass"],
	&"torch": [&"torch", &"lantern", &"glowstone"],
	&"chest": [&"chest", &"crate", &"container", &"storage_locker"],
	&"crate": [&"crate", &"barrel", &"chest"],
	&"spawner": [&"monster_spawner", &"spawner", &"nest"],
	&"teleporter": [&"teleporter", &"gate_core", &"warp_pad", &"ancient_gate"],
	&"gravel": [&"gravel", &"cobblestone"],
	&"ice": [&"ice", &"packed_ice", &"glass"],
	&"snow": [&"snow", &"snow_block", &"sand"],
	&"rail": [&"rail", &"track", &"minecart_rail", &"metal_platform"],
	&"support": [&"wood_beam", &"log", &"wood_planks", &"cobblestone"],
	&"crystal": [&"crystal_block", &"amethyst_block", &"quartz_block", &"glass"],
	&"bone": [&"bone_block", &"bone", &"cobblestone"],
	&"web": [&"cobweb", &"web", &"vine"],
	&"vine": [&"vine", &"hanging_root", &"leaves"],
	&"hay": [&"hay", &"thatch", &"wheat_bale", &"sand"],
	&"cloth": [&"cloth", &"wool", &"carpet", &"sand"],
	&"anvil": [&"anvil", &"forge", &"furnace"],
	&"furnace": [&"furnace", &"smelter", &"forge"],
	&"table": [&"table", &"workbench", &"crafting_table", &"wood_planks"],
	&"bed": [&"bed", &"bunk", &"cloth", &"wool"],
	&"sign": [&"sign", &"signpost"],
	&"pressure_plate": [&"pressure_plate", &"trigger_plate", &"plate"],
	&"lever": [&"lever", &"switch", &"button"],
	&"spike": [&"spike", &"spikes", &"spike_trap", &"cactus"],
	&"scaffold": [&"scaffold", &"metal_platform", &"platform", &"wood_planks"],
}

static var _cache: Dictionary = {}


## Reset the resolution cache. The placer calls this once per planet, so a
## planet that registers different blocks never sees stale ids.
static func invalidate() -> void:
	_cache.clear()


## First registered block id from `candidates`, else `fallback_id`.
static func first_of(candidates: Array, fallback_id: int = Const.AIR) -> int:
	for n: StringName in candidates:
		if Blocks.has(n):
			return Blocks.id(n)
	return fallback_id


## Resolve `role` for `theme`. Returns `Const.AIR` when the role has no sensible
## core fallback (lights, doors, glass...), so callers must treat AIR as "skip".
static func block(theme: StringName, role: StringName) -> int:
	var key := "%s/%s" % [theme, role]
	if _cache.has(key):
		return _cache[key]
	var id := Const.AIR
	var t: Dictionary = THEMES.get(theme, THEMES[THEME_NATURAL])
	var chain: Array = t.get(role, [])
	if chain.is_empty():
		chain = THEMES[THEME_NATURAL].get(role, [])
	id = first_of(chain, Const.AIR)
	if id == Const.AIR:
		var fb: StringName = CORE_FALLBACK.get(role, &"")
		if fb != &"" and Blocks.has(fb):
			id = Blocks.id(fb)
	_cache[key] = id
	return id


## Resolve a generic (theme-independent) role such as &"wood" or &"chest".
static func generic(role: StringName, fallback_role: StringName = &"") -> int:
	var key := "*/%s" % role
	if _cache.has(key):
		return _cache[key]
	var id := first_of(GENERIC.get(role, []), Const.AIR)
	if id == Const.AIR and fallback_role != &"":
		id = block(THEME_NATURAL, fallback_role)
	_cache[key] = id
	return id


## Resolve a bare block name with a fallback chain, cached.
static func named(names: Array, fallback: StringName = &"") -> int:
	var key := "n/%s" % str(names)
	if _cache.has(key):
		return _cache[key]
	var id := first_of(names, Const.AIR)
	if id == Const.AIR and fallback != &"" and Blocks.has(fallback):
		id = Blocks.id(fallback)
	_cache[key] = id
	return id


## Whole role table for a theme, resolved once. Generators grab this and then
## index it, which keeps their inner loops free of string work.
static func kit(theme: StringName) -> Dictionary:
	var key := "kit/%s" % theme
	if _cache.has(key):
		return _cache[key]
	var out := {}
	for role: StringName in [
		&"wall", &"wall_alt", &"trim", &"floor", &"ceiling", &"pillar", &"accent",
		&"light", &"glass", &"door", &"platform", &"ladder", &"bars", &"rubble",
		&"roof", &"fence", &"path", &"soil", &"liquid", &"crop", &"treasure", &"banner",
	]:
		out[role] = block(theme, role)
	# Structural roles must never be air or the building would have holes.
	var solid_fb := block(theme, &"wall")
	if solid_fb == Const.AIR:
		solid_fb = Blocks.id(&"cobblestone")
	for role: StringName in [&"wall", &"wall_alt", &"floor", &"ceiling", &"pillar", &"roof", &"trim", &"path"]:
		if out[role] == Const.AIR:
			out[role] = solid_fb
	_cache[key] = out
	return out


## Deterministic theme choice for a biome, used when a def leaves theme unset.
static func theme_for_biome(biome: StringName, h: int) -> StringName:
	var b := String(biome)
	var pool: Array[StringName] = [THEME_HUMAN, THEME_GLITCH, THEME_APEX]
	if b.contains("desert") or b.contains("savanna") or b.contains("dune"):
		pool = [THEME_AVIAN, THEME_APEX, THEME_HUMAN]
	elif b.contains("jungle") or b.contains("forest") or b.contains("swamp"):
		pool = [THEME_FLORAN, THEME_GLITCH, THEME_HUMAN]
	elif b.contains("ocean") or b.contains("beach") or b.contains("reef"):
		pool = [THEME_HYLOTL, THEME_HUMAN, THEME_AVIAN]
	elif b.contains("tundra") or b.contains("snow") or b.contains("ice"):
		pool = [THEME_GLITCH, THEME_HUMAN, THEME_APEX]
	elif b.contains("volcan") or b.contains("ash") or b.contains("magma"):
		pool = [THEME_APEX, THEME_ANCIENT, THEME_HUMAN]
	elif b.contains("alien") or b.contains("toxic") or b.contains("barren"):
		pool = [THEME_ANCIENT, THEME_APEX, THEME_FLORAN]
	return pool[absi(h) % pool.size()]
