class_name Crafting
extends RefCounted

## Recipes, stations, and the one function that turns ingredients into output.
##
## A recipe belongs to exactly one station. `hand` recipes are always available;
## everything else needs you to be standing at the right placed object, and the
## object's tier gates which of its recipes it can actually run — so a stone
## furnace and a forge share the `smelting` group but not the whole book.
##
## Recipes are *known* or not. Most of the early book is known from the start,
## because being unable to make a torch because a discovery did not fire is not
## a puzzle. Everything else is learned by picking up an ingredient for the
## first time, which means the game teaches itself as you mine.

enum Unlock { START, MATERIAL, BLUEPRINT, QUEST, TIER }

const STATIONS: Array[StringName] = [
	&"hand", &"workbench", &"furnace", &"anvil", &"forge",
	&"kitchen", &"chemistry", &"assembler", &"replicator", &"manipulator", &"tech",
]

## The highest `tier` each station can run.
const STATION_TIER := {
	&"hand": 0, &"workbench": 1, &"furnace": 2, &"anvil": 2, &"forge": 4,
	&"kitchen": 2, &"chemistry": 4, &"assembler": 5, &"replicator": 6,
	&"manipulator": 3, &"tech": 3,
}

const STATION_LABELS := {
	&"hand": "Hand Crafting", &"workbench": "Workbench", &"furnace": "Furnace",
	&"anvil": "Anvil", &"forge": "Forge", &"kitchen": "Kitchen",
	&"chemistry": "Chemistry Lab", &"assembler": "Assembler",
	&"replicator": "Replicator", &"manipulator": "Manipulator Bench",
	&"tech": "Tech Console",
}


class Recipe extends RefCounted:
	var id := ""
	var station: StringName = &"hand"
	var category: StringName = &"materials"
	var group: StringName = &"general"
	var order := 0
	var tier := 0
	var seconds := 0.0                ## 0 = instant
	var description := ""
	var inputs: Array = []            ## [[item_id, count], ...]
	var outputs: Array = []           ## [[item_id, count], ...]
	var byproducts: Array = []        ## [[item_id, count, chance], ...]
	var unlock: int = Crafting.Unlock.MATERIAL
	var unlock_materials: Array[StringName] = []
	var unlock_tier := 0

	func takes(item_id: StringName, count := 1) -> Recipe:
		inputs.append([item_id, count])
		return self

	func gives(item_id: StringName, count := 1) -> Recipe:
		outputs.append([item_id, count])
		return self

	func byproduct(item_id: StringName, count := 1, chance := 1.0) -> Recipe:
		byproducts.append([item_id, count, chance])
		return self

	func in_category(c: StringName) -> Recipe:
		category = c
		return self

	func in_group(g: StringName) -> Recipe:
		group = g
		return self

	func ordered(n: int) -> Recipe:
		order = n
		return self

	func at_tier(n: int) -> Recipe:
		tier = n
		return self

	func takes_time(s: float) -> Recipe:
		seconds = s
		return self

	func describe(text: String) -> Recipe:
		description = text
		return self

	func known_at_start() -> Recipe:
		unlock = Crafting.Unlock.START
		return self

	func learned_from_material(item_id: StringName) -> Recipe:
		unlock = Crafting.Unlock.MATERIAL
		unlock_materials.append(item_id)
		return self

	func learned_from_quest() -> Recipe:
		unlock = Crafting.Unlock.QUEST
		return self

	## The first output, which is what the UI shows as "the thing you get".
	func result_id() -> StringName:
		return outputs[0][0] if not outputs.is_empty() else &""

	func result_count() -> int:
		return int(outputs[0][1]) if not outputs.is_empty() else 0

	func display_name() -> String:
		var t := Items.get_type(result_id())
		return t.display if t != null else id


static var recipes: Array[Recipe] = []
static var by_id := {}
## item id -> Array[Recipe] that it teaches
static var _teaches := {}
static var _booted := false


static func boot() -> void:
	if _booted:
		return
	_booted = true
	Items.boot()
	var script: GDScript = load("res://scripts/content/recipes.gd")
	script.register_all()
	for r: Recipe in recipes:
		for m: StringName in r.unlock_materials:
			if not _teaches.has(m):
				_teaches[m] = []
			_teaches[m].append(r)


static func make(id: String, station: StringName) -> Recipe:
	var r := Recipe.new()
	r.id = id
	r.station = station
	r.tier = int(STATION_TIER.get(station, 0))
	return r


static func add(r: Recipe) -> Recipe:
	if by_id.has(r.id):
		push_warning("Crafting: duplicate recipe id '%s'" % r.id)
		return by_id[r.id]
	recipes.append(r)
	by_id[r.id] = r
	return r


static func get_recipe(id: String) -> Recipe:
	return by_id.get(id)


static func station_label(station: StringName) -> String:
	return String(STATION_LABELS.get(station, String(station).capitalize()))


## Recipes a station can offer at `tier`, filtered to the ones `known` contains.
static func available_for(station: StringName, tier: int, known: Dictionary) -> Array[Recipe]:
	var out: Array[Recipe] = []
	for r: Recipe in recipes:
		if r.station != station or r.tier > tier:
			continue
		if r.unlock != Unlock.START and not known.has(r.id):
			continue
		out.append(r)
	out.sort_custom(func(a: Recipe, b: Recipe) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.display_name() < b.display_name())
	return out


## Every recipe taught by picking `item_id` up for the first time.
static func taught_by(item_id: StringName) -> Array:
	return _teaches.get(item_id, [])


## Recipes known from the very first frame.
static func starting_knowledge() -> Dictionary:
	var out := {}
	for r: Recipe in recipes:
		if r.unlock == Unlock.START:
			out[r.id] = true
	return out


# =============================================================================
# resolving a craft
# =============================================================================

static func missing_for(inv: Inventory, r: Recipe) -> Array:
	var out: Array = []
	for pair: Array in r.inputs:
		var have := inv.count_of(pair[0])
		if have < int(pair[1]):
			out.append([pair[0], int(pair[1]) - have])
	return out


static func can_craft(inv: Inventory, r: Recipe) -> bool:
	return missing_for(inv, r).is_empty()


## Spend the inputs and hand back the outputs. Anything that will not fit in the
## bag is returned so the caller can drop it on the floor.
static func craft(inv: Inventory, r: Recipe, rng: RandomNumberGenerator) -> Array:
	if not can_craft(inv, r):
		return []
	for pair: Array in r.inputs:
		inv.remove(pair[0], int(pair[1]))
	var overflow: Array = []
	for pair: Array in r.outputs:
		var s := Items.make(pair[0], int(pair[1]))
		if inv.add(s) > 0:
			overflow.append(s)
	for trio: Array in r.byproducts:
		if rng.randf() > float(trio[2]):
			continue
		var s := Items.make(trio[0], int(trio[1]))
		if inv.add(s) > 0:
			overflow.append(s)
	return overflow


# =============================================================================
# a placed station's runtime state
# =============================================================================

class Station extends RefCounted:
	var station_id: StringName = &"workbench"
	var tier := 0
	var instant := true
	var needs_fuel := false
	var fuel := 0.0                  ## seconds of burn left
	var queue: Array = []            ## [[Recipe, seconds_left], ...]

	func _init(p_station: StringName = &"workbench", p_tier := -1) -> void:
		station_id = p_station
		tier = p_tier if p_tier >= 0 else int(Crafting.STATION_TIER.get(p_station, 0))
		instant = p_station in [&"hand", &"workbench", &"anvil", &"forge",
			&"manipulator", &"tech"]
		needs_fuel = p_station == &"furnace"

	func label() -> String:
		return Crafting.station_label(station_id)

	func available(known: Dictionary) -> Array[Recipe]:
		return Crafting.available_for(station_id, tier, known)

	## Feed the furnace. Returns false when the item is not a fuel.
	func add_fuel(item_id: StringName) -> bool:
		var t := Items.get_type(item_id)
		if t == null or not t.has_tag(&"fuel"):
			return false
		fuel += 8.0 + float(t.value) * 0.4
		return true

	func enqueue(r: Recipe) -> void:
		queue.append([r, maxf(r.seconds, 0.1)])

	## Advance timed jobs. Returns the recipes that finished this tick.
	func tick(delta: float) -> Array:
		var done: Array = []
		if queue.is_empty():
			return done
		if needs_fuel:
			if fuel <= 0.0:
				return done
			fuel = maxf(fuel - delta, 0.0)
		var job: Array = queue[0]
		job[1] = float(job[1]) - delta
		if float(job[1]) <= 0.0:
			done.append(job[0])
			queue.remove_at(0)
		return done
