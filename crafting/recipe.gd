## One crafting recipe, as a real object rather than a loose Dictionary.
##
## Recipes are built with a fluent builder and handed to the `Recipes` autoload:
## [codeblock]
## reg.add(CraftRecipe.make("iron_pickaxe", &"anvil")
##     .takes(&"iron_bar", 5).takes(&"stick", 2)
##     .gives(&"iron_pickaxe", 1)
##     .lasts(1.5).needs_tier(2)
##     .in_category(&"tools").in_group(&"toolsmith")
##     .learned_from_material(&"iron_bar"))
## [/codeblock]
##
## Other agents who do not want to depend on this class may keep passing plain
## dictionaries to `Recipes.register()`; see [method from_dict] for the schema.
class_name CraftRecipe
extends RefCounted

# ------------------------------------------------------------------- vocabulary
## The complete, closed set of station ids. A recipe naming anything else is
## still registered but warns, because no station will ever surface it.
##
## [b]hand[/b]       — no station at all; the player's own crafting panel.[br]
## [b]workbench[/b]  — the first placeable station; planks, simple objects.[br]
## [b]furnace[/b]    — burns fuel; ore to bar, sand to glass, cooking meat.[br]
## [b]anvil[/b]      — shapes bars into tools and low-tier gear.[br]
## [b]forge[/b]      — tier 3+ metalwork: alloys, high-tier weapons/armour.[br]
## [b]kitchen[/b]    — multi-ingredient meals with buffs.[br]
## [b]chemistry[/b]  — reagents, augments, fuels, medicine.[br]
## [b]assembler[/b]  — electronics, wiring, machines, tech cards.[br]
## [b]replicator[/b] — end-game universal fabricator (tier 5+).[br]
## [b]separator[/b]  — continuous refining: pixels, extraction, centrifuge.
const STATIONS: Array[StringName] = [
	&"hand", &"workbench", &"furnace", &"anvil", &"forge",
	&"kitchen", &"chemistry", &"assembler", &"replicator", &"separator",
]

## Default tier of each station — the highest `required_tier` it can run when
## the objects agent does not override it. `CraftStation.new()` reads this, so
## a plain `CraftStation.new(&"forge")` is already a tier-4 forge.
##
## Tiers match the ore ladder in `content/items/10_materials.gd`:
## 0 copper · 1 iron/silver · 2 gold/titanium · 3 durasteel · 4 aegisalt ·
## 5 ferozium/violium · 6 solarium.
const STATION_TIER := {
	&"hand": 0, &"workbench": 1, &"furnace": 2, &"anvil": 2, &"forge": 4,
	&"kitchen": 2, &"chemistry": 4, &"assembler": 5, &"replicator": 6,
	&"separator": 4,
}

## Human labels for the UI. `CraftQuery.station_label()` reads this.
const STATION_LABELS := {
	&"hand": "Hand Crafting", &"workbench": "Workbench", &"furnace": "Furnace",
	&"anvil": "Anvil", &"forge": "Forge", &"kitchen": "Kitchen",
	&"chemistry": "Chemistry Lab", &"assembler": "Assembler",
	&"replicator": "Replicator", &"separator": "Separator",
}

## How a recipe becomes known. A recipe may carry several triggers at once;
## the first one that fires teaches it.
enum Unlock {
	START,      ## known from the moment a new game begins
	MATERIAL,   ## learned the first time one of `unlock_materials` is picked up
	BLUEPRINT,  ## learned by consuming a blueprint item
	QUEST,      ## learned as a quest reward
	TIER,       ## learned when the player's progression tier reaches a value
}

# ------------------------------------------------------------------- identity
var id: String = ""
var station: StringName = &"hand"
var category: StringName = &"materials"
## Sub-list within a station's window ("smelting", "toolsmith"...). Stations
## expose a set of groups; see `CraftStation.groups`.
var group: StringName = &"general"
var display_name: String = ""     ## blank = derive from the primary output
var description: String = ""

# --------------------------------------------------------------- ingredients
## `{StringName item_id: int count}`.
var inputs: Dictionary = {}
## `[{ "id": StringName, "count": int, "chance": float }]`. The first entry is
## the primary output; later ones with `chance < 1.0` are by-products.
var outputs: Array[Dictionary] = []

# ------------------------------------------------------------------ gameplay
var time: float = 0.5             ## seconds on a timed station; 0 = instant
var required_tier: int = 0        ## station tier needed to run it
var fuel_cost: float = 0.0        ## furnace burn-seconds consumed, 0 = default
var experience: int = 0           ## hook for a future skill system
var sort_order: int = 0           ## manual tiebreak inside a category

# -------------------------------------------------------------------- unlock
var known_from_start: bool = false
var unlock_materials: Array[StringName] = []
var unlock_blueprint: StringName = &""
var unlock_quest: StringName = &""
var unlock_tier: int = -1         ## -1 = never unlocked by tier


func _init(p_id: String = "", p_station: StringName = &"hand") -> void:
	id = p_id
	station = p_station


## Canonical entry point for the builder chain.
static func make(p_id: String, p_station: StringName = &"hand") -> CraftRecipe:
	return CraftRecipe.new(p_id, p_station)


# ------------------------------------------------------------------- builder
## Adds (or tops up) an ingredient requirement.
func takes(item_id: StringName, count: int = 1) -> CraftRecipe:
	if count <= 0:
		return self
	inputs[item_id] = int(inputs.get(item_id, 0)) + count
	return self


## Adds a guaranteed output. The first `gives()` call is the primary output.
func gives(item_id: StringName, count: int = 1) -> CraftRecipe:
	outputs.append({"id": item_id, "count": count, "chance": 1.0})
	return self


## Adds a chance-rolled by-product (slag, offcuts, rare crystals...).
func byproduct(item_id: StringName, count: int = 1, chance: float = 0.25) -> CraftRecipe:
	outputs.append({"id": item_id, "count": count, "chance": clampf(chance, 0.0, 1.0)})
	return self


## Seconds the craft takes on a timed station. `0.0` means instant.
func lasts(seconds: float) -> CraftRecipe:
	time = maxf(0.0, seconds)
	return self


## Minimum station tier. A tier-2 anvil cannot run a tier-4 recipe.
func needs_tier(t: int) -> CraftRecipe:
	required_tier = t
	return self


## Furnace burn-seconds this recipe consumes. Defaults to `time` when left at 0.
func burns(seconds: float) -> CraftRecipe:
	fuel_cost = maxf(0.0, seconds)
	return self


func in_category(c: StringName) -> CraftRecipe:
	category = c
	return self


func in_group(g: StringName) -> CraftRecipe:
	group = g
	return self


func named(n: String) -> CraftRecipe:
	display_name = n
	return self


func describe(text: String) -> CraftRecipe:
	description = text
	return self


func ordered(n: int) -> CraftRecipe:
	sort_order = n
	return self


func worth_xp(n: int) -> CraftRecipe:
	experience = n
	return self


# -------------------------------------------------------------- unlock rules
## Known immediately in a fresh save.
func known_at_start() -> CraftRecipe:
	known_from_start = true
	return self


## Learned the first time this material enters the player's inventory.
func learned_from_material(item_id: StringName) -> CraftRecipe:
	if not unlock_materials.has(item_id):
		unlock_materials.append(item_id)
	return self


## Learned by using a blueprint item (`Kind.QUEST`/`MATERIAL` item id).
func learned_from_blueprint(item_id: StringName) -> CraftRecipe:
	unlock_blueprint = item_id
	return self


## Learned when the named quest completes.
func learned_from_quest(quest_id: StringName) -> CraftRecipe:
	unlock_quest = quest_id
	return self


## Learned when the player's progression tier reaches `t`.
func learned_at_tier(t: int) -> CraftRecipe:
	unlock_tier = t
	return self


# ------------------------------------------------------------------ queries
## The item this recipe is "for", used for indexing and the UI's headline icon.
func primary_output() -> StringName:
	return StringName(outputs[0].get("id", &"")) if not outputs.is_empty() else &""


func primary_count() -> int:
	return int(outputs[0].get("count", 1)) if not outputs.is_empty() else 0


## Display name, falling back to the primary output's item name.
func label() -> String:
	if display_name != "":
		return display_name
	var out := primary_output()
	if out != &"" and Items.has(out):
		var n := Items.display_name(out)
		var c := primary_count()
		return "%s x%d" % [n, c] if c > 1 else n
	return id.capitalize()


func is_instant() -> bool:
	return time <= 0.0


## Burn-seconds a furnace should charge for one run of this recipe.
func effective_fuel_cost() -> float:
	return fuel_cost if fuel_cost > 0.0 else maxf(0.25, time)


## True when any unlock trigger other than START exists — i.e. the recipe is
## meant to be discovered rather than granted.
func is_discoverable() -> bool:
	return not known_from_start


## One-line "how do I get this?" string for a locked entry in the UI.
func unlock_summary() -> String:
	if known_from_start:
		return "Known"
	var parts: PackedStringArray = []
	if not unlock_materials.is_empty():
		var names: PackedStringArray = []
		for m: StringName in unlock_materials:
			names.append(Items.display_name(m) if Items.has(m) else String(m).capitalize())
		parts.append("Obtain " + " or ".join(names))
	if unlock_blueprint != &"":
		parts.append("Use the %s" % (Items.display_name(unlock_blueprint) if Items.has(unlock_blueprint) else String(unlock_blueprint).capitalize()))
	if unlock_quest != &"":
		parts.append("Complete a quest")
	if unlock_tier >= 0:
		parts.append("Reach tier %d" % unlock_tier)
	return " / ".join(parts) if not parts.is_empty() else "Unknown"


## Rolls the outputs once, honouring by-product chances.
## Returns `[{ "id": StringName, "count": int }]`.
func roll_outputs(rng: RandomNumberGenerator = null, multiplier: int = 1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in outputs:
		var chance := float(o.get("chance", 1.0))
		var count := int(o.get("count", 1)) * maxi(1, multiplier)
		if chance >= 1.0:
			out.append({"id": StringName(o["id"]), "count": count})
			continue
		var got := 0
		for i in maxi(1, multiplier):
			var roll := rng.randf() if rng != null else randf()
			if roll < chance:
				got += int(o.get("count", 1))
		if got > 0:
			out.append({"id": StringName(o["id"]), "count": got})
	return out


## Total input cost scaled by `n` crafts.
func scaled_inputs(n: int) -> Dictionary:
	if n <= 1:
		return inputs.duplicate()
	var out: Dictionary = {}
	for k: StringName in inputs:
		out[k] = int(inputs[k]) * n
	return out


func is_valid() -> bool:
	return id != "" and not inputs.is_empty() and not outputs.is_empty()


# ------------------------------------------------------------ dict adapters
## Builds a recipe from the legacy Dictionary schema used by
## `Recipes.register()`. Every key is optional except `inputs` plus one of
## `output` / `outputs` / `result`.
##
## [codeblock]
## {
##   "id":       String,                      # defaults to "<output>_<station>"
##   "station":  String|StringName,           # default &"hand"
##   "inputs":   { "iron_bar": 5, ... },      # required
##   "output":   { "id": "x", "count": 1 },   # or "outputs": [ {...}, ... ]
##   "result":   "item_id", "count": 1,       # shorthand alternative
##   "time":     float,   "tier": int,
##   "category": String,  "group": String,
##   "name":     String,  "description": String,
##   "fuel":     float,   "order": int, "xp": int,
##   "unlocked_by": "start" | "material" | "blueprint" | "quest" | "tier",
##   "unlock_material":  "id" or ["id", ...],
##   "unlock_blueprint": "id",
##   "unlock_quest":     "quest_id",
##   "unlock_tier":      int,
## }
## [/codeblock]
static func from_dict(d: Dictionary) -> CraftRecipe:
	var r := CraftRecipe.new()
	r.station = StringName(d.get("station", &"hand"))
	for k: Variant in d.get("inputs", {}):
		r.takes(StringName(k), int(d["inputs"][k]))

	if d.has("outputs"):
		for o: Variant in d["outputs"]:
			if o is Dictionary:
				var od: Dictionary = o
				r.outputs.append({
					"id": StringName(od.get("id", &"")),
					"count": int(od.get("count", 1)),
					"chance": clampf(float(od.get("chance", 1.0)), 0.0, 1.0),
				})
			else:
				r.gives(StringName(o), 1)
	elif d.has("output"):
		var o: Variant = d["output"]
		if o is Dictionary:
			var od: Dictionary = o
			r.gives(StringName(od.get("id", &"")), int(od.get("count", 1)))
		else:
			r.gives(StringName(o), int(d.get("count", 1)))
	elif d.has("result"):
		r.gives(StringName(d["result"]), int(d.get("count", 1)))

	r.id = String(d.get("id", ""))
	if r.id == "":
		r.id = "%s_%s" % [String(r.primary_output()), String(r.station)]
	r.time = float(d.get("time", 0.5))
	r.required_tier = int(d.get("tier", d.get("required_tier", 0)))
	r.category = StringName(d.get("category", &"materials"))
	r.group = StringName(d.get("group", &"general"))
	r.display_name = String(d.get("name", ""))
	r.description = String(d.get("description", ""))
	r.fuel_cost = float(d.get("fuel", 0.0))
	r.sort_order = int(d.get("order", 0))
	r.experience = int(d.get("xp", 0))

	var mode := String(d.get("unlocked_by", "start"))
	match mode:
		"material": pass
		"blueprint": pass
		"quest": pass
		"tier": pass
		_: r.known_from_start = true
	var mat: Variant = d.get("unlock_material", null)
	if mat is Array:
		for m: Variant in mat:
			r.learned_from_material(StringName(m))
	elif mat != null:
		r.learned_from_material(StringName(mat))
	if d.has("unlock_blueprint"):
		r.unlock_blueprint = StringName(d["unlock_blueprint"])
	if d.has("unlock_quest"):
		r.unlock_quest = StringName(d["unlock_quest"])
	if d.has("unlock_tier"):
		r.unlock_tier = int(d["unlock_tier"])
	# A recipe with no trigger at all must still be reachable.
	if not r.known_from_start and r.unlock_materials.is_empty() \
			and r.unlock_blueprint == &"" and r.unlock_quest == &"" and r.unlock_tier < 0:
		r.known_from_start = true
	return r


## Mirror of [method from_dict] — handy for save files and debug dumps.
func to_dict() -> Dictionary:
	var outs: Array = []
	for o: Dictionary in outputs:
		outs.append({"id": String(o["id"]), "count": int(o["count"]), "chance": float(o["chance"])})
	var ins: Dictionary = {}
	for k: StringName in inputs:
		ins[String(k)] = int(inputs[k])
	return {
		"id": id, "station": String(station), "inputs": ins, "outputs": outs,
		"time": time, "tier": required_tier, "category": String(category),
		"group": String(group), "name": display_name, "description": description,
		"fuel": fuel_cost, "order": sort_order, "xp": experience,
		"unlock_material": unlock_materials.map(func(m: StringName) -> String: return String(m)),
		"unlock_blueprint": String(unlock_blueprint),
		"unlock_quest": String(unlock_quest),
		"unlock_tier": unlock_tier,
		"known_from_start": known_from_start,
	}


func _to_string() -> String:
	return "[CraftRecipe %s @%s]" % [id, station]
