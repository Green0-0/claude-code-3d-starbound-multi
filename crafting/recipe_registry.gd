## Autoloaded as `Recipes`. The crafting brain: the recipe book, its indices,
## and the discovery/unlock system.
##
## [b]Registering[/b] — content lives in `res://crafting/recipes/*.gd`, each a
## `RefCounted` with `static func register_all(reg) -> void`, loaded in filename
## order at `_ready()`. Other modules may also register at runtime:
## [codeblock]
## Recipes.register({"station": "workbench", "inputs": {"wood": 4},
##                   "output": {"id": "plank", "count": 8}})   # dictionary form
## Recipes.add(CraftRecipe.make("x", &"anvil").takes(...).gives(...))  # object form
## [/codeblock]
##
## [b]Indices[/b] — by station, by output item ("who makes this?"), by input item
## ("what can I make with this?"), and by category.
##
## [b]Discovery[/b] — four independent channels, any of which can teach a recipe:
## picking a material up for the first time, consuming a blueprint item,
## completing a quest, and crossing a progression tier. Every unlock emits
## `Events.recipe_learned(recipe_id)`.
extends Node

# ------------------------------------------------------------------- storage
## Every registered recipe, in registration order. Kept public and named `all`
## for compatibility with the original stub.
var all: Array[CraftRecipe] = []

## Current player progression tier. Drives tier unlocks and gates high-tier
## recipes; the tech/quest agents move it with [method set_tier].
var player_tier: int = 0

## Set true to hand the player every recipe (debug / creative).
var reveal_everything: bool = false

## The recipe book names items the content agents are still writing. While an
## item id has no `ItemType`, its recipes stay registered (so they light up the
## moment the content lands) but are hidden from station listings. Set false to
## see them anyway when debugging content coverage.
var hide_unknown_items: bool = true

var _by_id: Dictionary = {}          ## String -> CraftRecipe
var _by_station: Dictionary = {}     ## StringName -> Array[CraftRecipe]
var _by_output: Dictionary = {}      ## StringName -> Array[CraftRecipe]
var _by_input: Dictionary = {}       ## StringName -> Array[CraftRecipe]
var _by_category: Dictionary = {}    ## StringName -> Array[CraftRecipe]
var _by_group: Dictionary = {}       ## StringName -> Array[CraftRecipe]

var _known: Dictionary = {}          ## String recipe_id -> true
var _seen_materials: Dictionary = {} ## StringName item_id -> true

var _unlock_by_material: Dictionary = {}   ## StringName -> Array[String]
var _unlock_by_blueprint: Dictionary = {}  ## StringName -> Array[String]
var _unlock_by_quest: Dictionary = {}      ## StringName -> Array[String]
var _unlock_by_tier: Dictionary = {}       ## int -> Array[String]

## Furnace fuels: item id -> burn seconds.
var _fuels: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _loaded := false

const RECIPE_DIR := "res://crafting/recipes"


func _ready() -> void:
	_rng.randomize()
	# Items must exist before recipes can validate ids against them.
	if Items.count() <= 0:
		await get_tree().process_frame
	_load_content()
	_grant_starting_recipes()
	Events.item_picked_up.connect(_on_item_picked_up)
	if Events.has_signal(&"quest_completed"):
		Events.quest_completed.connect(_on_quest_completed)
	var v := validate()
	print("[Recipes] %d recipes registered, %d known, %d fully backed by items" %
		[all.size(), _known.size(), int(v["playable"])])
	if not (v["missing_items"] as PackedStringArray).is_empty():
		print("[Recipes] %d item ids not defined yet (recipes hidden until they are)"
			% (v["missing_items"] as PackedStringArray).size())


func _load_content() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in _scan(RECIPE_DIR):
		var scr: Script = load(path)
		if scr != null and scr.has_method(&"register_all"):
			scr.call(&"register_all", self)


func _scan(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".gd.remap"):
			out.append(dir_path + "/" + f.trim_suffix(".remap"))
	out.sort()
	return out


# ---------------------------------------------------------------- registering
## Dictionary form kept for other modules. See `CraftRecipe.from_dict()` for the
## full schema.
func register(recipe: Dictionary) -> void:
	add(CraftRecipe.from_dict(recipe))


## Object form. Returns the recipe so builders can chain off it.
func add(r: CraftRecipe) -> CraftRecipe:
	if r == null or not r.is_valid():
		push_warning("[Recipes] rejected invalid recipe '%s'" % (r.id if r != null else "<null>"))
		return r
	if _by_id.has(r.id):
		push_warning("[Recipes] duplicate recipe id '%s' ignored" % r.id)
		return _by_id[r.id]
	if not CraftRecipe.STATIONS.has(r.station):
		push_warning("[Recipes] recipe '%s' names unknown station '%s'" % [r.id, r.station])

	_by_id[r.id] = r
	all.append(r)
	_push(_by_station, r.station, r)
	_push(_by_category, r.category, r)
	_push(_by_group, r.group, r)
	for o: Dictionary in r.outputs:
		_push(_by_output, StringName(o["id"]), r)
	for i: StringName in r.inputs:
		_push(_by_input, i, r)

	for m: StringName in r.unlock_materials:
		_push_id(_unlock_by_material, m, r.id)
	if r.unlock_blueprint != &"":
		_push_id(_unlock_by_blueprint, r.unlock_blueprint, r.id)
	if r.unlock_quest != &"":
		_push_id(_unlock_by_quest, r.unlock_quest, r.id)
	if r.unlock_tier >= 0:
		_push_id(_unlock_by_tier, r.unlock_tier, r.id)
	if r.known_from_start:
		_known[r.id] = true
	return r


## Convenience for content files: register many at once.
func add_many(list: Array) -> void:
	for r: Variant in list:
		if r is CraftRecipe:
			add(r)
		elif r is Dictionary:
			register(r)


func _push(dict: Dictionary, key: Variant, r: CraftRecipe) -> void:
	if not dict.has(key):
		var fresh: Array[CraftRecipe] = []
		dict[key] = fresh
	var bucket: Array[CraftRecipe] = dict[key]
	bucket.append(r)


func _push_id(dict: Dictionary, key: Variant, rid: String) -> void:
	if not dict.has(key):
		dict[key] = PackedStringArray()
	var arr: PackedStringArray = dict[key]
	arr.append(rid)
	dict[key] = arr


# -------------------------------------------------------------- registry fuel
## Declares an item as furnace fuel worth `seconds` of burn time.
func register_fuel(item_id: StringName, seconds: float) -> void:
	_fuels[item_id] = maxf(0.0, seconds)


func is_fuel(item_id: StringName) -> bool:
	return _fuels.has(item_id)


## Burn seconds for one unit of `item_id`; 0.0 when it is not a fuel.
func fuel_value(item_id: StringName) -> float:
	return float(_fuels.get(item_id, 0.0))


func all_fuels() -> Dictionary:
	return _fuels.duplicate()


# -------------------------------------------------------------------- lookup
func get_recipe(recipe_id: String) -> CraftRecipe:
	return _by_id.get(recipe_id)


func has_recipe(recipe_id: String) -> bool:
	return _by_id.has(recipe_id)


## Every recipe a station can run, ignoring knowledge and materials.
func for_station(station: StringName) -> Array:
	return _bucket(_by_station, station).duplicate()


func _bucket(dict: Dictionary, key: Variant) -> Array[CraftRecipe]:
	var out: Array[CraftRecipe] = []
	if dict.has(key):
		out.assign(dict[key])
	return out


## Recipes that produce `item_id` (including as a by-product).
func recipes_making(item_id: StringName) -> Array[CraftRecipe]:
	return _bucket(_by_output, item_id)


## "What can I make with this?" — recipes that consume `item_id`.
func recipes_using(item_id: StringName) -> Array[CraftRecipe]:
	return _bucket(_by_input, item_id)


func in_category(c: StringName) -> Array[CraftRecipe]:
	return _bucket(_by_category, c)


func in_group(g: StringName) -> Array[CraftRecipe]:
	return _bucket(_by_group, g)


func stations() -> Array[StringName]:
	var out: Array[StringName] = []
	for s: StringName in CraftRecipe.STATIONS:
		if _by_station.has(s):
			out.append(s)
	return out


func count() -> int:
	return all.size()


# ------------------------------------------------------------------ knowledge
func is_known(recipe_id: String) -> bool:
	return reveal_everything or _known.has(recipe_id)


func known_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _known:
		out.append(k)
	return out


## Teaches one recipe. Returns true when it was genuinely new.
## `source` is free text used for the toast ("material", "blueprint", ...).
func learn(recipe_id: String, source: String = "discovery", quiet: bool = false) -> bool:
	if _known.has(recipe_id) or not _by_id.has(recipe_id):
		return false
	_known[recipe_id] = true
	var r: CraftRecipe = _by_id[recipe_id]
	Events.recipe_learned.emit(recipe_id)
	if not quiet:
		Events.toast("Recipe learned: %s" % r.label(), "craft")
	return true


func learn_many(ids: Variant, source: String = "discovery") -> int:
	var n := 0
	for rid: Variant in ids:
		if learn(String(rid), source, true):
			n += 1
	if n == 1:
		var only := String(ids[0])
		var r: CraftRecipe = _by_id.get(only)
		if r != null:
			Events.toast("Recipe learned: %s" % r.label(), "craft")
	elif n > 1:
		Events.toast("%d new recipes learned" % n, "craft")
	return n


func forget(recipe_id: String) -> void:
	_known.erase(recipe_id)


func _grant_starting_recipes() -> void:
	for r: CraftRecipe in all:
		if r.known_from_start:
			_known[r.id] = true


# ------------------------------------------------------- unlock channel 1: pickup
## Call when an item first enters the player's possession. Wired automatically
## to `Events.item_picked_up`, but safe to call by hand (containers, quest
## rewards, creative give).
func note_material(item_id: StringName) -> int:
	if _seen_materials.has(item_id):
		return 0
	_seen_materials[item_id] = true
	if not _unlock_by_material.has(item_id):
		return 0
	return learn_many(_unlock_by_material[item_id], "material")


func has_seen(item_id: StringName) -> bool:
	return _seen_materials.has(item_id)


func _on_item_picked_up(item_id: String, _count: int) -> void:
	note_material(StringName(item_id))


# ---------------------------------------------------- unlock channel 2: blueprint
## Consumes a blueprint item's knowledge. Returns how many recipes it taught;
## 0 means the blueprint was already fully known (the caller should not consume
## the item in that case, or should refund it).
func apply_blueprint(blueprint_item: StringName) -> int:
	if not _unlock_by_blueprint.has(blueprint_item):
		return 0
	return learn_many(_unlock_by_blueprint[blueprint_item], "blueprint")


## Recipe ids a given blueprint item would teach (whether known or not).
func blueprint_contents(blueprint_item: StringName) -> PackedStringArray:
	return _unlock_by_blueprint.get(blueprint_item, PackedStringArray())


## True when the blueprint still has something to give.
func blueprint_is_useful(blueprint_item: StringName) -> bool:
	for rid: String in blueprint_contents(blueprint_item):
		if not _known.has(rid):
			return true
	return false


# -------------------------------------------------------- unlock channel 3: quest
## Call from the quest agent on completion, or let the `Events.quest_completed`
## connection do it.
func grant_quest_recipes(quest_id: StringName) -> int:
	if not _unlock_by_quest.has(quest_id):
		return 0
	return learn_many(_unlock_by_quest[quest_id], "quest")


func _on_quest_completed(quest_id: String) -> void:
	grant_quest_recipes(StringName(quest_id))


# --------------------------------------------------------- unlock channel 4: tier
## Raises (or lowers) the player's progression tier, granting every tier unlock
## at or below the new value. Returns how many recipes were learned.
func set_tier(t: int) -> int:
	var learned := 0
	var old := player_tier
	player_tier = t
	if t <= old:
		return 0
	for lvl: int in _unlock_by_tier:
		if lvl > old and lvl <= t:
			learned += learn_many(_unlock_by_tier[lvl], "tier")
	if learned > 0:
		Events.toast("Tier %d unlocked %d new recipes" % [t, learned], "craft")
	return learned


func advance_tier() -> int:
	return set_tier(player_tier + 1)


# ------------------------------------------------------------------ inventory
## Resolves the inventory to use: explicit, else the player's.
func _resolve_inv(inv: Variant) -> Variant:
	if inv != null:
		return inv
	if Game.player != null:
		return Game.player.get("inventory")
	return null


func _count_of(inv: Variant, item_id: StringName) -> int:
	if inv == null:
		return 0
	if inv.has_method(&"count_of"):
		return int(inv.call(&"count_of", item_id))
	return 0


## Does the inventory hold every ingredient? Uses the atomic `has_all` when the
## inventory offers it, otherwise falls back to per-item counting.
func _has_all(inv: Variant, needs: Dictionary) -> bool:
	if inv == null:
		return false
	if inv.has_method(&"has_all"):
		return bool(inv.call(&"has_all", needs))
	if not inv.has_method(&"count_of"):
		return false
	for k: StringName in needs:
		if _count_of(inv, k) < int(needs[k]):
			return false
	return true


func _consume(inv: Variant, needs: Dictionary) -> bool:
	if inv == null:
		return false
	if inv.has_method(&"consume"):
		return bool(inv.call(&"consume", needs))
	# No atomic consume: verify then remove item by item.
	if not _has_all(inv, needs):
		return false
	if inv.has_method(&"remove_id"):
		for k: StringName in needs:
			inv.call(&"remove_id", k, int(needs[k]))
		return true
	push_warning("[Recipes] inventory has no consume()/remove_id(); craft aborted")
	return false


## Adds `count` of `item_id`, returning the amount that did NOT fit. Robust to
## either `add_id` return convention because it measures the real delta.
func _give(inv: Variant, item_id: StringName, count: int, data: Dictionary = {}) -> int:
	if inv == null or count <= 0:
		return count
	var before := _count_of(inv, item_id)
	var measured: bool = inv.has_method(&"count_of")
	var ret := -1
	if not data.is_empty() and inv.has_method(&"add"):
		ret = int(inv.call(&"add", ItemStack.new(item_id, count, data)))
	elif inv.has_method(&"add_id"):
		ret = int(inv.call(&"add_id", item_id, count))
	elif inv.has_method(&"add"):
		ret = int(inv.call(&"add", ItemStack.new(item_id, count, data)))
	else:
		return count
	if measured:
		var stored := _count_of(inv, item_id) - before
		return maxi(0, count - stored)
	# Unmeasurable inventory: trust the return value as a leftover count.
	return clampi(ret, 0, count)


## Public wrapper: atomically remove `needs` (`{item_id: count}`) from an
## inventory. Stations use this to take payment when a job is queued.
func take_from(inv: Variant, needs: Dictionary) -> bool:
	return _consume(_resolve_inv(inv), needs)


## Public wrapper: put items into an inventory, returning the amount that did
## not fit. Pass `drop_overflow` to have the remainder spawned at the player.
func give_to(inv: Variant, item_id: StringName, count: int, drop_overflow: bool = false) -> int:
	var left := _give(_resolve_inv(inv), item_id, count)
	if left > 0 and drop_overflow and Game.player != null:
		Game.spawn_item_drop(Game.player.global_position, item_id, left)
		return 0
	return left


## Public wrapper: does this inventory satisfy `needs`?
func inventory_has(inv: Variant, needs: Dictionary) -> bool:
	return _has_all(_resolve_inv(inv), needs)


# ------------------------------------------------------------------- crafting
## True when the recipe is known, the materials are present and the player's
## tier is high enough. `inv` may be null to mean the player's inventory.
func can_craft(recipe_id: String, inv: Variant = null) -> bool:
	var r: CraftRecipe = _by_id.get(recipe_id)
	if r == null or not is_known(recipe_id):
		return false
	if r.required_tier > maxi(player_tier, _station_tier_hint(r)):
		return false
	return _has_all(_resolve_inv(inv), r.inputs)


## Same, but ignoring knowledge — used by stations that were handed a recipe
## directly (a furnace does not care whether you "know" iron smelting).
func has_materials(recipe_id: String, inv: Variant = null) -> bool:
	var r: CraftRecipe = _by_id.get(recipe_id)
	return r != null and _has_all(_resolve_inv(inv), r.inputs)


func _station_tier_hint(r: CraftRecipe) -> int:
	return int(CraftRecipe.STATION_TIER.get(r.station, 0))


## What is still missing, as `{item_id: shortfall}`. Empty when craftable.
## Accepts a `CraftRecipe`, a recipe id String, or a raw inputs Dictionary.
func missing_for(recipe: Variant, inv: Variant = null) -> Dictionary:
	var needs: Dictionary = {}
	if recipe is CraftRecipe:
		needs = (recipe as CraftRecipe).inputs
	elif recipe is String:
		var r: CraftRecipe = _by_id.get(recipe)
		if r == null:
			return {}
		needs = r.inputs
	elif recipe is Dictionary:
		needs = recipe
	var real: Variant = _resolve_inv(inv)
	var out: Dictionary = {}
	for k: StringName in needs:
		var short := int(needs[k]) - _count_of(real, k)
		if short > 0:
			out[k] = short
	return out


## How many times this recipe could be run back-to-back with what is held.
func max_crafts(recipe_id: String, inv: Variant = null) -> int:
	var r: CraftRecipe = _by_id.get(recipe_id)
	if r == null or r.inputs.is_empty():
		return 0
	var real: Variant = _resolve_inv(inv)
	var best := 9999
	for k: StringName in r.inputs:
		best = mini(best, _count_of(real, k) / maxi(1, int(r.inputs[k])))
		if best <= 0:
			return 0
	return best


## Runs a recipe: consumes the inputs atomically, then grants the outputs.
## Overflow is dropped at the player's feet rather than lost.
## `times` runs the recipe several times in one transaction.
func craft(recipe_id: String, inv: Variant = null, times: int = 1) -> bool:
	var r: CraftRecipe = _by_id.get(recipe_id)
	if r == null:
		return false
	times = maxi(1, times)
	var real: Variant = _resolve_inv(inv)
	if real == null:
		return false
	if not is_known(recipe_id) and not reveal_everything:
		return false
	var needs := r.scaled_inputs(times)
	if not _consume(real, needs):
		return false
	_deliver(r, real, times)
	return true


## Grants a recipe's outputs without consuming anything. Stations that already
## took payment when the job was queued call this when the timer completes.
func deliver_outputs(recipe: Variant, inv: Variant = null, times: int = 1) -> void:
	var r: CraftRecipe = null
	if recipe is CraftRecipe:
		r = recipe as CraftRecipe
	else:
		r = _by_id.get(String(recipe))
	if r == null:
		return
	_deliver(r, _resolve_inv(inv), maxi(1, times))


func _deliver(r: CraftRecipe, inv: Variant, times: int) -> void:
	var rolled := r.roll_outputs(_rng, times)
	for o: Dictionary in rolled:
		var oid: StringName = o["id"]
		var n := int(o["count"])
		var leftover := _give(inv, oid, n)
		if leftover > 0 and Game.player != null:
			Game.spawn_item_drop(Game.player.global_position, oid, leftover)
		# Crafting a material counts as obtaining it for the first time, so the
		# discovery chain keeps running even for things you never pick up.
		note_material(oid)
		Events.item_crafted.emit(String(oid), n)
	Game.bump_stat("items_crafted", float(times))
	Events.inventory_changed.emit()
	Events.play_sound.emit("craft", Game.player.global_position if Game.player != null else Vector3.ZERO)


# ------------------------------------------------------------------ discovery
## The station window's data source. Returns every recipe the station could run
## that the player [b]knows[/b], craftable or not, so the UI can grey out the
## ones missing materials. Sorted craftable-first, then by category and name.
##
## `tier` is the station's own tier; recipes above it are excluded entirely
## (they belong to a better machine, not to a shopping list).
func available_for(station: StringName, inv: Variant = null, tier: int = 99) -> Array[CraftRecipe]:
	var real: Variant = _resolve_inv(inv)
	var out: Array[CraftRecipe] = []
	for r: CraftRecipe in _bucket(_by_station, station):
		if r.required_tier > tier:
			continue
		if not is_known(r.id):
			continue
		if not is_available(r):
			continue
		out.append(r)
	out.sort_custom(func(a: CraftRecipe, b: CraftRecipe) -> bool:
		var ca := _has_all(real, a.inputs)
		var cb := _has_all(real, b.inputs)
		if ca != cb:
			return ca
		if a.category != b.category:
			return String(a.category) < String(b.category)
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return a.label() < b.label())
	return out


## Like [method available_for] but also returns the recipes the station could
## run that are still [b]undiscovered[/b], as ghost entries. Useful for a
## "recipes: 34/58" completion counter.
func catalogue_for(station: StringName, tier: int = 99) -> Dictionary:
	var known: Array[CraftRecipe] = []
	var locked: Array[CraftRecipe] = []
	for r: CraftRecipe in _bucket(_by_station, station):
		if r.required_tier > tier or not is_available(r):
			continue
		if is_known(r.id):
			known.append(r)
		else:
			locked.append(r)
	return {"known": known, "locked": locked,
			"total": known.size() + locked.size(), "found": known.size()}


## Every known recipe across all stations, for a global search box.
func all_known() -> Array[CraftRecipe]:
	var out: Array[CraftRecipe] = []
	for r: CraftRecipe in all:
		if is_known(r.id) and is_available(r):
			out.append(r)
	return out


## True when every item this recipe names actually exists. Recipes that fail
## this are content the item agents have not written yet; see
## [member hide_unknown_items].
func is_available(r: CraftRecipe) -> bool:
	if not hide_unknown_items or r == null:
		return true
	if not Items.has(r.primary_output()):
		return false
	for i: StringName in r.inputs:
		if not Items.has(i):
			return false
	return true


## Content-coverage report, printed at startup and handy from the debug console.
## `{ total, playable, missing_items: PackedStringArray, by_station: {} }`
func validate() -> Dictionary:
	var missing: Dictionary = {}
	var playable := 0
	var by_station: Dictionary = {}
	for r: CraftRecipe in all:
		var ok := true
		for i: StringName in r.inputs:
			if not Items.has(i):
				missing[i] = true
				ok = false
		for o: Dictionary in r.outputs:
			var oid: StringName = o["id"]
			if not Items.has(oid):
				missing[oid] = true
				ok = false
		if ok:
			playable += 1
		by_station[r.station] = int(by_station.get(r.station, 0)) + 1
	var names := PackedStringArray()
	for k: StringName in missing:
		names.append(String(k))
	names.sort()
	return {"total": all.size(), "playable": playable,
			"missing_items": names, "by_station": by_station}


# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	return {
		"known": known_ids(),
		"seen": PackedStringArray(_seen_materials.keys().map(func(k: StringName) -> String: return String(k))),
		"tier": player_tier,
	}


func load_state(d: Dictionary) -> void:
	_known.clear()
	_seen_materials.clear()
	_grant_starting_recipes()
	for rid: String in d.get("known", PackedStringArray()):
		if _by_id.has(rid):
			_known[rid] = true
	for m: String in d.get("seen", PackedStringArray()):
		_seen_materials[StringName(m)] = true
	player_tier = int(d.get("tier", 0))


## Wipes discovery back to a fresh game (new run, not new planet).
func reset_progress() -> void:
	_known.clear()
	_seen_materials.clear()
	player_tier = 0
	_grant_starting_recipes()
