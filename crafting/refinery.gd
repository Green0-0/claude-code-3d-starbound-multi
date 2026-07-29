## Continuous-process machines: the separator family.
##
## Unlike `CraftStation`, a refinery has no recipe list the player picks from.
## You feed it a stack, it grinds away at a fixed rate and spits out whatever
## that input yields. Three modes:
##
## [b]PIXELS[/b]     — ore and gear in, currency out. The universal sink.[br]
## [b]EXTRACTION[/b] — one item in, its component parts out (with chances).[br]
## [b]CENTRIFUGE[/b] — a liquid or mixture in, separated fractions out.
##
## The objects agent owns the machine node; it holds a `CraftRefinery`, calls
## [method insert] when the player drops something in the input slot, and
## [method tick] from `_physics_process`:
##
## [codeblock]
## extends Node3D
## var refinery := CraftRefinery.new(CraftRefinery.Mode.PIXELS, 1)
##
## func _ready() -> void:
##     refinery.output_sink = func(id: StringName, n: int) -> void:
##         Game.spawn_item_drop(global_position + Vector3.UP, id, n)
##     refinery.produced.connect(func(id: String, n: int) -> void:
##         Events.toast("Refined %d %s" % [n, id], "craft"))
##
## func _physics_process(delta: float) -> void:
##     refinery.tick(delta)
## [/codeblock]
class_name CraftRefinery
extends RefCounted

enum Mode { PIXELS, EXTRACTION, CENTRIFUGE }

## One batch finished. `outputs` is `[{id, count}]`.
signal produced(item_id: String, count: int)
## Emitted every tick while working; `t` is 0..1 through the current item.
signal progress_changed(t: float)
## The machine started or stopped having work to do.
signal busy_changed(busy: bool)
## The input buffer changed.
signal buffer_changed(item_id: String, count: int)

# ------------------------------------------------------------------ settings
var mode: int = Mode.PIXELS
## Higher-tier machines process faster and unlock richer yields.
var tier: int = 1
## Seconds per item at tier 1; scaled down by tier.
var seconds_per_item: float = 2.0
## How many items may sit in the input buffer.
var buffer_limit: int = 200
var enabled: bool = true
## Energy drawn per processed item; the power agent may read this.
var energy_per_item: float = 1.0

## Where output goes. Defaults to the player's inventory; the objects agent
## normally replaces it with a callable that fills the machine's output slots
## or drops items in the world. Signature: `func(id: StringName, count: int)`.
var output_sink: Callable = Callable()

# --------------------------------------------------------------------- state
var input_id: StringName = &""
var input_count: int = 0
var _elapsed: float = 0.0
var _rng := RandomNumberGenerator.new()

# ------------------------------------------------------------------- recipes
## `item_id -> pixels each`. Anything not listed falls back to the item's
## `ItemType.value`, so new content works without touching this table.
const PIXEL_BONUS := {
	&"raw_copper": 6, &"raw_tin": 7, &"raw_lead": 8, &"raw_iron": 10,
	&"raw_silver": 18, &"raw_gold": 30, &"raw_tungsten": 36,
	&"raw_titanium": 48, &"raw_platinum": 66, &"raw_durasteel": 84,
	&"raw_aegisalt": 108, &"raw_ferozium": 144, &"raw_violium": 168,
	&"raw_rubium": 180, &"raw_solarium": 240,
	&"copper_bar": 17, &"iron_bar": 26, &"silver_bar": 48, &"gold_bar": 78,
	&"titanium_bar": 132, &"durasteel_bar": 216, &"aegisalt_bar": 288,
	&"ferozium_bar": 384, &"violium_bar": 456, &"solarium_bar": 660,
	&"crystal_shard": 17, &"quartz": 22, &"diamond": 192, &"prism_shard": 114,
	&"ancient_fragment": 240, &"ancient_relic": 600, &"scrap_metal": 5,
	&"slag": 1,
}

## `item_id -> [{id, count, chance}]`. Extraction breaks an item into parts.
const EXTRACTION := {
	&"plank": [{"id": &"sawdust", "count": 2, "chance": 1.0},
		{"id": &"stick", "count": 2, "chance": 0.5}],
	&"wood": [{"id": &"plank", "count": 2, "chance": 1.0},
		{"id": &"bark_strip", "count": 1, "chance": 0.4},
		{"id": &"tree_sap", "count": 1, "chance": 0.25}],
	&"hide": [{"id": &"leather", "count": 1, "chance": 0.6},
		{"id": &"tallow", "count": 1, "chance": 0.5}],
	&"cloth": [{"id": &"string", "count": 3, "chance": 1.0}],
	&"rope": [{"id": &"plant_fibre", "count": 4, "chance": 1.0}],
	&"coal": [{"id": &"sulphur", "count": 1, "chance": 0.5},
		{"id": &"tar", "count": 1, "chance": 0.4}],
	&"glow_gland": [{"id": &"luminous_powder", "count": 2, "chance": 1.0}],
	&"glow_fungus": [{"id": &"luminous_powder", "count": 1, "chance": 1.0},
		{"id": &"glow_sap", "count": 1, "chance": 0.3}],
	&"crystal": [{"id": &"crystal_shard", "count": 3, "chance": 1.0}],
	&"scrap_metal": [{"id": &"iron_bar", "count": 1, "chance": 0.5},
		{"id": &"copper_wire", "count": 2, "chance": 0.6}],
	&"circuit_board": [{"id": &"copper_wire", "count": 3, "chance": 1.0},
		{"id": &"silicon_wafer", "count": 1, "chance": 0.5}],
	&"advanced_circuit": [{"id": &"circuit_board", "count": 2, "chance": 1.0},
		{"id": &"gold_bar", "count": 1, "chance": 0.5}],
	&"energy_cell": [{"id": &"copper_bar", "count": 2, "chance": 0.8},
		{"id": &"crystal_shard", "count": 1, "chance": 0.4}],
	&"iron_gear": [{"id": &"iron_bar", "count": 1, "chance": 0.8}],
	&"bone": [{"id": &"bone_meal", "count": 3, "chance": 1.0},
		{"id": &"bone_shard", "count": 1, "chance": 0.4}],
	&"slag": [{"id": &"gravel", "count": 1, "chance": 0.7},
		{"id": &"ash", "count": 1, "chance": 0.5}],
	&"venom_gland": [{"id": &"sulphur", "count": 1, "chance": 0.6},
		{"id": &"alien_compound", "count": 1, "chance": 0.2}],
	&"chitin_plate": [{"id": &"chitin", "count": 3, "chance": 1.0}],
	&"wild_berries": [{"id": &"plant_matter", "count": 2, "chance": 1.0}],
	&"rusted_metal": [{"id": &"scrap_metal", "count": 2, "chance": 1.0}],
	&"ancient_fragment": [{"id": &"quartz", "count": 2, "chance": 0.6},
		{"id": &"cosmic_dust", "count": 1, "chance": 0.2},
		{"id": &"ancient_essence", "count": 1, "chance": 0.03}],
}

## Liquid / mixture separation. Slower per item, richer output.
const CENTRIFUGE := {
	&"salt_water": [{"id": &"salt", "count": 2, "chance": 1.0},
		{"id": &"water_flask", "count": 1, "chance": 0.4}],
	&"milk": [{"id": &"butter", "count": 1, "chance": 0.6},
		{"id": &"cheese", "count": 1, "chance": 0.25}],
	&"crude_oil": [{"id": &"ftl_fuel", "count": 1, "chance": 0.7},
		{"id": &"tar", "count": 1, "chance": 0.5},
		{"id": &"polymer", "count": 1, "chance": 0.25}],
	&"tar": [{"id": &"rubber", "count": 1, "chance": 0.5},
		{"id": &"sulphur", "count": 1, "chance": 0.4},
		{"id": &"carbon_powder", "count": 1, "chance": 0.3}],
	&"gravel": [{"id": &"sand", "count": 1, "chance": 0.7},
		{"id": &"flint", "count": 1, "chance": 0.25},
		{"id": &"raw_iron", "count": 1, "chance": 0.05}],
	&"sand": [{"id": &"raw_gold", "count": 1, "chance": 0.03},
		{"id": &"flint", "count": 1, "chance": 0.1},
		{"id": &"quartz", "count": 1, "chance": 0.06}],
	&"mud": [{"id": &"clay_lump", "count": 1, "chance": 0.6},
		{"id": &"plant_matter", "count": 1, "chance": 0.3}],
	&"ash": [{"id": &"saltpetre", "count": 1, "chance": 0.25},
		{"id": &"carbon_powder", "count": 1, "chance": 0.2}],
	&"slime_glob": [{"id": &"adhesive", "count": 1, "chance": 0.5},
		{"id": &"plant_matter", "count": 1, "chance": 0.4}],
	&"ectoplasm": [{"id": &"aether_dust", "count": 1, "chance": 0.3},
		{"id": &"luminous_powder", "count": 2, "chance": 0.6}],
	&"erchius_fuel": [{"id": &"quartz", "count": 2, "chance": 0.6},
		{"id": &"refined_ftl_fuel", "count": 2, "chance": 1.0}],
	&"plasmic_gel": [{"id": &"ftl_fuel", "count": 3, "chance": 1.0},
		{"id": &"sulphur", "count": 2, "chance": 0.4}],
	&"protocite": [{"id": &"alien_compound", "count": 2, "chance": 0.8},
		{"id": &"cosmic_dust", "count": 1, "chance": 0.3}],
}


func _init(p_mode: int = Mode.PIXELS, p_tier: int = 1) -> void:
	mode = p_mode
	tier = p_tier
	_rng.randomize()
	match p_mode:
		Mode.PIXELS: seconds_per_item = 1.0
		Mode.EXTRACTION: seconds_per_item = 2.0
		Mode.CENTRIFUGE: seconds_per_item = 3.0


func configure(d: Dictionary) -> CraftRefinery:
	mode = int(d.get("mode", mode))
	tier = int(d.get("tier", tier))
	seconds_per_item = maxf(0.05, float(d.get("seconds_per_item", seconds_per_item)))
	buffer_limit = int(d.get("buffer_limit", buffer_limit))
	energy_per_item = float(d.get("energy_per_item", energy_per_item))
	return self


# ------------------------------------------------------------------- queries
## Effective time for one item, after the tier speed bonus.
func item_time() -> float:
	return maxf(0.05, seconds_per_item / (1.0 + float(maxi(0, tier - 1)) * 0.35))


## The table this mode reads.
func table() -> Dictionary:
	if mode == Mode.EXTRACTION:
		return EXTRACTION
	if mode == Mode.CENTRIFUGE:
		return CENTRIFUGE
	return {}


## Can this machine do anything with `item_id`?
func accepts(item_id: StringName) -> bool:
	if mode == Mode.PIXELS:
		return pixel_value(item_id) > 0
	return table().has(item_id)


## Pixels one unit of `item_id` is worth, including the tier efficiency bonus.
func pixel_value(item_id: StringName) -> int:
	var base := int(PIXEL_BONUS.get(item_id, 0))
	if base == 0:
		var t := Items.get_type(item_id)
		if t == null:
			return 0
		# Refining is worth less than selling, but always available.
		base = maxi(1, int(float(t.value) * 0.6))
	return maxi(1, int(round(float(base) * efficiency())))


## Yield multiplier from the machine tier: 1.0 at tier 1, 1.6 at tier 4.
func efficiency() -> float:
	return 1.0 + float(maxi(0, tier - 1)) * 0.2


## What one unit of `item_id` produces, as `[{id, count, chance}]`, purely for
## a tooltip. Chances are unrolled.
func preview(item_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode == Mode.PIXELS:
		var v := pixel_value(item_id)
		if v > 0:
			out.append({"id": &"pixels", "count": v, "chance": 1.0})
		return out
	for e: Dictionary in table().get(item_id, []):
		out.append({
			"id": StringName(e["id"]), "count": int(e["count"]),
			"chance": clampf(float(e["chance"]) * efficiency(), 0.0, 1.0),
		})
	return out


func is_busy() -> bool:
	return input_count > 0 and enabled


func progress() -> float:
	return 0.0 if input_count <= 0 else clampf(_elapsed / item_time(), 0.0, 1.0)


# --------------------------------------------------------------------- input
## Puts `count` of `item_id` into the buffer. Returns how many were accepted;
## the caller should only remove that many from the source inventory.
func insert(item_id: StringName, count: int) -> int:
	if count <= 0 or not accepts(item_id):
		return 0
	if input_count > 0 and input_id != item_id:
		return 0
	var was_busy := is_busy()
	var space := buffer_limit - input_count
	var taken := mini(space, count)
	if taken <= 0:
		return 0
	input_id = item_id
	input_count += taken
	buffer_changed.emit(String(input_id), input_count)
	if is_busy() != was_busy:
		busy_changed.emit(is_busy())
	return taken


## Pulls up to `count` acceptable items straight out of an inventory.
## Returns how many were moved in.
func pull_from(inv: Variant, item_id: StringName, count: int) -> int:
	if inv == null or not accepts(item_id):
		return 0
	var have := int(inv.call(&"count_of", item_id)) if inv.has_method(&"count_of") else 0
	var want := mini(count, have)
	if want <= 0:
		return 0
	want = mini(want, buffer_limit - input_count)
	if want <= 0:
		return 0
	if not Recipes.take_from(inv, {item_id: want}):
		return 0
	Events.inventory_changed.emit()
	return insert(item_id, want)


## Empties the buffer back out through the output sink. Returns the count.
func eject() -> int:
	var n := input_count
	if n > 0:
		_emit(input_id, n)
	input_id = &""
	input_count = 0
	_elapsed = 0.0
	buffer_changed.emit("", 0)
	busy_changed.emit(false)
	return n


# ---------------------------------------------------------------------- tick
## Processes the buffer. Call from the owning node's `_physics_process`.
## Returns the number of items consumed this tick (usually 0 or 1).
func tick(delta: float) -> int:
	if not enabled or input_count <= 0 or delta <= 0.0:
		return 0
	_elapsed += delta
	progress_changed.emit(progress())
	var t := item_time()
	var done := 0
	while _elapsed >= t and input_count > 0:
		_elapsed -= t
		_process_one()
		done += 1
	if input_count <= 0:
		_elapsed = 0.0
		busy_changed.emit(false)
	return done


func _process_one() -> void:
	var id := input_id
	input_count -= 1
	buffer_changed.emit(String(id), input_count)
	if mode == Mode.PIXELS:
		var v := pixel_value(id)
		if v > 0:
			# Pixels are a balance, not a stack — never route them through an
			# inventory or an output slot.
			Pixels.add(v, "refine")
			produced.emit("pixels", v)
		return
	for e: Dictionary in table().get(id, []):
		var chance := clampf(float(e["chance"]) * efficiency(), 0.0, 1.0)
		if _rng.randf() < chance:
			_emit(StringName(e["id"]), int(e["count"]))


func _emit(item_id: StringName, count: int) -> void:
	if count <= 0:
		return
	if output_sink.is_valid():
		output_sink.call(item_id, count)
	else:
		Recipes.give_to(null, item_id, count, true)
		Events.inventory_changed.emit()
	produced.emit(String(item_id), count)


# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	return {
		"mode": int(mode), "tier": tier, "input": String(input_id),
		"count": input_count, "elapsed": _elapsed, "enabled": enabled,
	}


func load_state(d: Dictionary) -> void:
	mode = int(d.get("mode", mode))
	tier = int(d.get("tier", tier))
	input_id = StringName(d.get("input", ""))
	input_count = int(d.get("count", 0))
	_elapsed = float(d.get("elapsed", 0.0))
	enabled = bool(d.get("enabled", true))
	buffer_changed.emit(String(input_id), input_count)
