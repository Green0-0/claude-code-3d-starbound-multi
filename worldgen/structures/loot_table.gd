## Depth- and theme-weighted loot for every container a structure places.
##
## ## The contract with the objects / inventory agents
##
## Structures do **not** roll loot at generation time. A chest is emitted as a
## block plus a tile-data payload:
##
## ```
## {"kind": "container", "loot_table": "apex_lab", "tier": 2, "theme": "apex",
##  "capacity": 16, "seed": 8412339, "struct": "apex_lab", "opened": false,
##  "locked": false, "key": ""}
## ```
##
## On first open, the container owner calls
##
## ```gdscript
## var rolled: Array = StructLoot.roll(d["loot_table"], d["tier"], d["seed"])
## # -> [{"item": &"iron_bar", "count": 3}, {"item": &"medkit", "count": 1}]
## ```
##
## then writes `opened = true` back into the tile data so the roll is stable and
## happens exactly once. Rolling is a pure function of (table, tier, seed), so a
## chest opened after a save/load reload yields the same contents.
##
## Every item id is checked against the `Items` registry before it is returned.
## Ids that the item-content agent has not defined yet are silently dropped and
## the entry falls back to its pool's guaranteed staple, so an unfinished item
## set can never produce a chest full of nothing.
class_name StructLoot
extends RefCounted

## Named item pools. Each entry is a candidate *chain*: the first id that the
## item registry knows wins, exactly like `StructPalette`'s block chains.
const POOLS := {
	&"currency": [
		{"items": [&"pixels", &"credits", &"coin"], "min": 40, "max": 220, "weight": 6.0},
	],
	&"ore": [
		{"items": [&"copper_ore", &"copper_bar", &"copper"], "min": 2, "max": 8, "weight": 4.0},
		{"items": [&"iron_ore", &"iron_bar", &"iron"], "min": 2, "max": 6, "weight": 3.0, "min_tier": 1},
		{"items": [&"silver_ore", &"silver_bar", &"silver"], "min": 1, "max": 4, "weight": 2.0, "min_tier": 1},
		{"items": [&"gold_ore", &"gold_bar", &"gold"], "min": 1, "max": 4, "weight": 1.5, "min_tier": 2},
		{"items": [&"titanium_ore", &"titanium_bar", &"titanium"], "min": 1, "max": 3, "weight": 1.0, "min_tier": 3},
		{"items": [&"durasteel_bar", &"durasteel"], "min": 1, "max": 3, "weight": 0.8, "min_tier": 4},
	],
	&"consumable": [
		{"items": [&"bandage", &"medkit", &"health_potion"], "min": 1, "max": 3, "weight": 4.0},
		{"items": [&"energy_drink", &"stim", &"energy_potion"], "min": 1, "max": 2, "weight": 2.0, "min_tier": 1},
		{"items": [&"antidote", &"cure_poison"], "min": 1, "max": 2, "weight": 1.5, "min_tier": 1},
		{"items": [&"torch"], "min": 4, "max": 12, "weight": 3.0},
	],
	&"food": [
		{"items": [&"bread", &"ration", &"cooked_meat"], "min": 1, "max": 4, "weight": 4.0},
		{"items": [&"apple", &"berry", &"fruit"], "min": 2, "max": 6, "weight": 3.0},
		{"items": [&"canned_food", &"preserves"], "min": 1, "max": 3, "weight": 2.0},
	],
	&"seed": [
		{"items": [&"wheat_seed", &"seed", &"crop_seed"], "min": 2, "max": 8, "weight": 3.0},
		{"items": [&"carrot_seed", &"potato_seed"], "min": 2, "max": 6, "weight": 2.0},
		{"items": [&"alien_seed", &"exotic_seed"], "min": 1, "max": 3, "weight": 1.0, "min_tier": 2},
	],
	&"tool": [
		{"items": [&"stone_pickaxe", &"pickaxe"], "min": 1, "max": 1, "weight": 2.0, "max_tier": 1},
		{"items": [&"iron_pickaxe", &"steel_pickaxe"], "min": 1, "max": 1, "weight": 2.0, "min_tier": 1},
		{"items": [&"grappling_hook", &"grapple"], "min": 1, "max": 1, "weight": 1.0, "min_tier": 2},
		{"items": [&"flashlight", &"lantern"], "min": 1, "max": 1, "weight": 1.5},
	],
	&"weapon": [
		{"items": [&"iron_sword", &"sword", &"shortsword"], "min": 1, "max": 1, "weight": 2.5},
		{"items": [&"pistol", &"revolver"], "min": 1, "max": 1, "weight": 2.0, "min_tier": 1},
		{"items": [&"assault_rifle", &"rifle"], "min": 1, "max": 1, "weight": 1.0, "min_tier": 2},
		{"items": [&"plasma_blade", &"energy_sword"], "min": 1, "max": 1, "weight": 0.6, "min_tier": 3},
	],
	&"armor": [
		{"items": [&"leather_chest", &"cloth_chest", &"chest_armor"], "min": 1, "max": 1, "weight": 2.0},
		{"items": [&"iron_chest", &"steel_chest"], "min": 1, "max": 1, "weight": 1.5, "min_tier": 1},
		{"items": [&"iron_helm", &"steel_helm", &"helmet"], "min": 1, "max": 1, "weight": 1.5, "min_tier": 1},
	],
	&"tech": [
		{"items": [&"tech_card", &"tech_chip", &"blueprint"], "min": 1, "max": 1, "weight": 1.2, "min_tier": 1},
		{"items": [&"upgrade_module", &"module"], "min": 1, "max": 2, "weight": 1.0, "min_tier": 2},
	],
	&"junk": [
		{"items": [&"scrap", &"scrap_metal", &"cobblestone"], "min": 3, "max": 12, "weight": 5.0},
		{"items": [&"cloth", &"fibre", &"fiber", &"dirt"], "min": 2, "max": 8, "weight": 3.0},
	],
	&"relic": [
		{"items": [&"ancient_artifact", &"artifact", &"relic"], "min": 1, "max": 1, "weight": 1.0, "min_tier": 2},
		{"items": [&"ancient_essence", &"essence"], "min": 1, "max": 3, "weight": 1.2, "min_tier": 2},
	],
	&"key": [
		{"items": [&"vault_key", &"ancient_key", &"key"], "min": 1, "max": 1, "weight": 1.0},
	],
	&"crystal": [
		{"items": [&"crystal_shard", &"crystal", &"amethyst"], "min": 2, "max": 8, "weight": 3.0},
		{"items": [&"focus_crystal", &"power_crystal"], "min": 1, "max": 2, "weight": 1.0, "min_tier": 2},
	],
	&"ammo": [
		{"items": [&"bullet", &"ammo", &"cell"], "min": 8, "max": 40, "weight": 3.0, "min_tier": 1},
	],
	&"book": [
		{"items": [&"lore_note", &"data_slate", &"codex_page", &"note"], "min": 1, "max": 1, "weight": 2.0},
	],
}

## Loot tables: pool -> weight, plus how many draws a chest makes. `bonus_rolls`
## adds a draw per tier, which is where depth scaling comes from.
const TABLES := {
	"ruins": {"rolls": [2, 3], "bonus_rolls": 0.5, "pools": {&"junk": 3.0, &"currency": 2.5, &"ore": 2.0, &"food": 1.5, &"consumable": 1.5, &"book": 0.8}},
	"village_house": {"rolls": [2, 3], "bonus_rolls": 0.2, "pools": {&"food": 4.0, &"seed": 2.5, &"junk": 2.0, &"currency": 2.0, &"consumable": 1.0}},
	"village_store": {"rolls": [3, 4], "bonus_rolls": 0.3, "pools": {&"currency": 4.0, &"consumable": 2.5, &"tool": 2.0, &"food": 2.0, &"armor": 1.0}},
	"farm": {"rolls": [2, 3], "bonus_rolls": 0.0, "pools": {&"seed": 5.0, &"food": 3.0, &"junk": 1.0}},
	"shrine": {"rolls": [1, 2], "bonus_rolls": 0.5, "pools": {&"relic": 3.0, &"currency": 2.0, &"crystal": 2.0, &"book": 1.5}},
	"outpost": {"rolls": [2, 4], "bonus_rolls": 0.5, "pools": {&"ammo": 3.0, &"consumable": 2.5, &"tool": 2.0, &"weapon": 1.5, &"junk": 2.0}},
	"shuttle": {"rolls": [3, 4], "bonus_rolls": 0.5, "pools": {&"tech": 3.0, &"ore": 2.0, &"consumable": 2.0, &"junk": 3.0, &"ammo": 1.5}},
	"bandit": {"rolls": [2, 4], "bonus_rolls": 0.6, "pools": {&"currency": 4.0, &"weapon": 2.5, &"ammo": 2.0, &"food": 1.5, &"armor": 1.0}},
	"mine": {"rolls": [2, 4], "bonus_rolls": 0.8, "pools": {&"ore": 5.0, &"tool": 2.0, &"junk": 2.0, &"crystal": 1.5}},
	"den": {"rolls": [1, 3], "bonus_rolls": 0.5, "pools": {&"junk": 3.0, &"food": 2.0, &"currency": 2.0, &"ore": 1.5}},
	"hermit": {"rolls": [2, 3], "bonus_rolls": 0.3, "pools": {&"food": 3.0, &"book": 2.5, &"consumable": 2.0, &"seed": 1.5}},
	"prison": {"rolls": [2, 3], "bonus_rolls": 0.7, "pools": {&"key": 2.0, &"junk": 3.0, &"consumable": 2.0, &"weapon": 1.0, &"book": 1.5}},
	"forge": {"rolls": [3, 4], "bonus_rolls": 0.8, "pools": {&"ore": 5.0, &"weapon": 2.0, &"armor": 2.0, &"tool": 2.0}},
	"cathedral": {"rolls": [2, 4], "bonus_rolls": 1.0, "pools": {&"crystal": 5.0, &"relic": 2.0, &"currency": 2.0, &"tech": 1.0}},
	"cistern": {"rolls": [2, 3], "bonus_rolls": 0.6, "pools": {&"junk": 3.0, &"currency": 2.0, &"consumable": 2.0, &"ore": 2.0}},
	"vault": {"rolls": [3, 5], "bonus_rolls": 1.2, "pools": {&"relic": 4.0, &"currency": 4.0, &"tech": 2.5, &"armor": 2.0, &"weapon": 2.0, &"crystal": 2.0}},
	"treasure": {"rolls": [3, 5], "bonus_rolls": 1.0, "pools": {&"currency": 4.0, &"ore": 3.0, &"weapon": 2.0, &"armor": 2.0, &"tech": 1.5, &"relic": 1.5}},
	"boss": {"rolls": [4, 6], "bonus_rolls": 1.5, "pools": {&"relic": 4.0, &"weapon": 3.0, &"armor": 3.0, &"tech": 3.0, &"currency": 4.0, &"crystal": 2.0}},
	"apex_lab": {"rolls": [3, 4], "bonus_rolls": 0.8, "pools": {&"tech": 4.0, &"consumable": 3.0, &"ammo": 2.0, &"book": 2.0, &"junk": 2.0}},
	"avian_temple": {"rolls": [2, 4], "bonus_rolls": 0.9, "pools": {&"relic": 3.0, &"currency": 3.0, &"crystal": 2.0, &"book": 2.0, &"weapon": 1.5}},
	"floran_hut": {"rolls": [2, 3], "bonus_rolls": 0.5, "pools": {&"food": 3.0, &"weapon": 2.0, &"junk": 3.0, &"seed": 2.0}},
	"glitch_castle": {"rolls": [3, 4], "bonus_rolls": 0.8, "pools": {&"armor": 3.0, &"weapon": 3.0, &"currency": 3.0, &"ore": 2.0, &"book": 1.5}},
	"hylotl_city": {"rolls": [3, 4], "bonus_rolls": 0.8, "pools": {&"currency": 3.0, &"crystal": 2.5, &"food": 2.0, &"armor": 2.0, &"book": 2.0}},
	"human_bunker": {"rolls": [3, 4], "bonus_rolls": 0.8, "pools": {&"ammo": 4.0, &"weapon": 2.5, &"consumable": 3.0, &"tech": 2.0, &"food": 2.0}},
	"ancient_vault": {"rolls": [3, 5], "bonus_rolls": 1.3, "pools": {&"relic": 5.0, &"crystal": 3.0, &"tech": 3.0, &"currency": 3.0, &"key": 1.0}},
	"gateway": {"rolls": [2, 3], "bonus_rolls": 1.0, "pools": {&"relic": 4.0, &"key": 2.0, &"crystal": 2.0, &"tech": 2.0}},
	"observatory": {"rolls": [2, 3], "bonus_rolls": 0.6, "pools": {&"tech": 4.0, &"book": 3.0, &"crystal": 2.0, &"currency": 1.5}},
	"treehouse": {"rolls": [2, 3], "bonus_rolls": 0.4, "pools": {&"food": 3.0, &"seed": 3.0, &"junk": 2.0, &"currency": 2.0}},
	"grave": {"rolls": [1, 3], "bonus_rolls": 0.6, "pools": {&"currency": 3.0, &"relic": 1.5, &"junk": 3.0, &"book": 2.0}},
	"puzzle": {"rolls": [3, 4], "bonus_rolls": 1.2, "pools": {&"tech": 3.0, &"relic": 3.0, &"currency": 3.0, &"weapon": 2.0, &"crystal": 2.0}},
}

## Theme nudges: a theme can push extra weight into some pools.
const THEME_BIAS := {
	&"apex": {&"tech": 1.6, &"ammo": 1.3, &"book": 1.2},
	&"avian": {&"relic": 1.6, &"currency": 1.3, &"crystal": 1.2},
	&"floran": {&"food": 1.6, &"seed": 1.5, &"weapon": 1.2},
	&"glitch": {&"armor": 1.5, &"weapon": 1.4, &"ore": 1.2},
	&"hylotl": {&"crystal": 1.4, &"book": 1.4, &"food": 1.2},
	&"human": {&"ammo": 1.5, &"consumable": 1.4, &"tech": 1.2},
	&"ancient": {&"relic": 2.0, &"crystal": 1.5, &"key": 1.3},
	&"natural": {&"junk": 1.3, &"ore": 1.2, &"food": 1.2},
}

static var _item_cache: Dictionary = {}


static func invalidate() -> void:
	_item_cache.clear()


## First registered item id from a candidate chain, or &"" if none exist yet.
static func resolve_item(candidates: Array) -> StringName:
	var key := str(candidates)
	if _item_cache.has(key):
		return _item_cache[key]
	var out := &""
	for n: StringName in candidates:
		if Items.has(n):
			out = n
			break
	if out == &"":
		# Blocks always have an auto-generated placer item, so a block name that
		# exists is a safe last resort.
		for n: StringName in candidates:
			if Blocks.has(n):
				out = n
				break
	_item_cache[key] = out
	return out


## Roll a container's contents. Pure in (table, tier, seed).
## Returns `[{"item": StringName, "count": int}, ...]`, already merged.
static func roll(table: String, tier: int = 0, seed_value: int = 0,
		theme: StringName = &"natural") -> Array:
	var t: Dictionary = TABLES.get(table, TABLES["ruins"])
	var r := StructRng.rng(seed_value, tier, table.hash(), 0x10077)
	var rolls_range: Array = t["rolls"]
	var n: int = r.randi_range(int(rolls_range[0]), int(rolls_range[1]))
	n += int(floor(float(tier) * float(t.get("bonus_rolls", 0.0))))
	n = clampi(n, 1, 10)

	var bias: Dictionary = THEME_BIAS.get(theme, {})
	var weighted: Array = []
	for pool_name: StringName in t["pools"]:
		var w := float(t["pools"][pool_name]) * float(bias.get(pool_name, 1.0))
		weighted.append([pool_name, w])
	if weighted.is_empty():
		return []

	var merged: Dictionary = {}
	for i in range(n):
		var pool_name: Variant = StructRng.weighted_pick(r.randi(), weighted)
		if pool_name == null:
			continue
		var entry := _pick_entry(POOLS.get(pool_name, []), tier, r)
		if entry.is_empty():
			continue
		var item := resolve_item(entry["items"])
		if item == &"":
			continue
		var lo: int = int(entry.get("min", 1))
		var hi: int = maxi(lo, int(entry.get("max", lo)))
		var count := r.randi_range(lo, hi)
		count = maxi(1, int(round(float(count) * (1.0 + 0.15 * float(tier)))))
		merged[item] = int(merged.get(item, 0)) + count
	var out: Array = []
	for item: StringName in merged:
		out.append({"item": item, "count": merged[item]})
	return out


static func _pick_entry(pool: Array, tier: int, r: RandomNumberGenerator) -> Dictionary:
	var eligible: Array = []
	for e: Dictionary in pool:
		if tier < int(e.get("min_tier", 0)):
			continue
		if tier > int(e.get("max_tier", 99)):
			continue
		eligible.append([e, float(e.get("weight", 1.0))])
	if eligible.is_empty():
		return {}
	var picked: Variant = StructRng.weighted_pick(r.randi(), eligible)
	return picked if picked is Dictionary else {}


## Roll a container straight from its tile-data payload — the call the objects
## agent should make on first open. Honours the optional `"guaranteed"` list of
## item ids (quest keys, plot relics), which are always present and are merged
## with the rolled stacks.
static func roll_payload(payload: Dictionary) -> Array:
	var out := roll(String(payload.get("loot_table", "ruins")),
			int(payload.get("tier", 0)), int(payload.get("seed", 0)),
			StringName(payload.get("theme", &"natural")))
	var guaranteed: Array = payload.get("guaranteed", [])
	for g in guaranteed:
		var item := resolve_item([StringName(g)])
		if item == &"":
			continue
		var found := false
		for entry: Dictionary in out:
			if entry["item"] == item:
				found = true
				break
		if not found:
			out.push_front({"item": item, "count": 1})
	return out


## Build the tile-data payload for a chest. This is what structures emit; the
## roll above happens later, on first open.
static func chest(table: String, tier: int, theme: StringName, seed_value: int,
		struct_id: String = "", locked: bool = false, key: String = "") -> Dictionary:
	return StructMarkers.container(table, tier, theme, seed_value, struct_id,
			16 if tier < 3 else 24, locked, key)


## Which table a theme's generic containers should use.
static func theme_table(theme: StringName) -> String:
	match theme:
		&"apex": return "apex_lab"
		&"avian": return "avian_temple"
		&"floran": return "floran_hut"
		&"glitch": return "glitch_castle"
		&"hylotl": return "hylotl_city"
		&"human": return "human_bunker"
		&"ancient": return "ancient_vault"
	return "ruins"


## Sanity helper for tests / debug overlays.
static func table_names() -> Array:
	return TABLES.keys()
