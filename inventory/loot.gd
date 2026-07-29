## Weighted loot tables with tiers, rarity biasing and guaranteed drops.
##
## Register once (at `_ready`, from any module), roll many times:
##
## [codeblock]
## LootRoller.register(&"monster_small", [
##     {"item": &"monster_fur", "min": 1, "max": 2, "weight": 30},
##     {"item": &"chitin",      "min": 1, "max": 3, "weight": 20, "min_tier": 1},
##     {"item": &"venom_gland",   "min": 1, "max": 1, "weight": 4, "rarity": 2},
##     {"item": &"bone", "guaranteed": true, "min": 1, "max": 1, "chance": 0.5},
##     {"pixels": [5, 15]},
## ], {"rolls": 1, "tier_bonus_rolls": 0.5})
##
## for st in LootRoller.roll(&"monster_small", planet_tier, player_luck):
##     Game.spawn_item_drop(pos, st.id, st.count, st.data)
## # ...or in one call:
## LootRoller.drop_at(pos, &"monster_small", planet_tier, player_luck)
## [/codeblock]
##
## [b]Entry keys[/b] (all optional except one of `item` / `items` / `pixels`):
## [br]`item: StringName` — what drops.
## [br]`items: Array[StringName]` — pick one of these at random instead.
## [br]`min`, `max: int` — count range (default 1..1).
## [br]`weight: float` — share of the weighted pick (default 1.0).
## [br]`chance: float` — 0..1 independent gate applied after selection.
## [br]`guaranteed: bool` — rolled every time, outside the weighted pick.
## [br]`min_tier`, `max_tier: int` — the entry only exists inside this band.
## [br]`rarity: int` — `Const.RARITY_*`; drives the luck bias. Defaults to the
##     item type's own rarity.
## [br]`tier_scale: float` — extra count per tier above `min_tier`.
## [br]`data: Dictionary` — instance data copied onto the produced stack.
## [br]`pixels: [min, max]` — credits currency instead of producing an item.
##
## [b]Table options[/b]: `rolls` (weighted picks, default 1), `rolls_max`
## (upper bound for a random roll count), `tier_bonus_rolls` (extra picks per
## tier), `luck_weight` (how hard `luck` biases rarity, default 1.0),
## `nothing_weight` (a share of the pick that yields nothing), `guaranteed_only`.
class_name LootRoller
extends RefCounted

## StringName -> {"entries": Array[Dictionary], "opts": Dictionary}
static var _tables: Dictionary = {}
static var _rng := RandomNumberGenerator.new()
static var _defaults_ready := false


# ================================================================ registration ==
## Register (or replace) a table. Returns the table id for chaining.
static func register(table_id: StringName, entries: Array, opts: Dictionary = {}) -> StringName:
	var clean: Array[Dictionary] = []
	for e: Variant in entries:
		if e is Dictionary:
			clean.append(e)
		else:
			push_warning("[LootRoller] table '%s' has a non-Dictionary entry" % table_id)
	_tables[table_id] = {"entries": clean, "opts": opts.duplicate()}
	return table_id


## Append entries to an existing table (or create it). Lets the biome agent add
## planet-specific drops to a table the monster agent owns.
static func extend(table_id: StringName, entries: Array) -> void:
	if not _tables.has(table_id):
		register(table_id, entries)
		return
	var t: Dictionary = _tables[table_id]
	var list: Array[Dictionary] = t["entries"]
	for e: Variant in entries:
		if e is Dictionary:
			list.append(e)


static func has_table(table_id: StringName) -> bool:
	_ensure_defaults()
	return _tables.has(table_id)


static func table_ids() -> Array[StringName]:
	_ensure_defaults()
	var out: Array[StringName] = []
	for k: StringName in _tables:
		out.append(k)
	out.sort()
	return out


static func table_entries(table_id: StringName) -> Array:
	_ensure_defaults()
	var t: Dictionary = _tables.get(table_id, {})
	return t.get("entries", [])


static func clear_tables() -> void:
	_tables.clear()
	_defaults_ready = false


## Make rolls reproducible (world seed, quest-fixed chests).
static func seed_rng(value: int) -> void:
	_rng.seed = value


# ======================================================================= roll ==
## Roll `table_id` at `tier` (0 = starter planet, rises with progression) with
## `luck` (0 = none; 0.5 is a strong charm; negative is a curse). Returns the
## produced stacks — never null, possibly empty. Unknown tables return empty
## and warn once.
static func roll(table_id: StringName, tier: int = 0, luck: float = 0.0) -> Array[ItemStack]:
	_ensure_defaults()
	var out: Array[ItemStack] = []
	if not _tables.has(table_id):
		push_warning("[LootRoller] unknown table '%s'" % table_id)
		return out
	var t: Dictionary = _tables[table_id]
	var entries: Array = t["entries"]
	var opts: Dictionary = t["opts"]

	# --- guaranteed entries -------------------------------------------------
	var pool: Array[Dictionary] = []
	for e: Dictionary in entries:
		if not _tier_ok(e, tier):
			continue
		if bool(e.get("guaranteed", false)):
			_emit(e, tier, luck, out)
		else:
			pool.append(e)
	if bool(opts.get("guaranteed_only", false)) or pool.is_empty():
		return _compact(out)

	# --- weighted picks -----------------------------------------------------
	var rolls := int(opts.get("rolls", 1))
	var rolls_max := int(opts.get("rolls_max", rolls))
	if rolls_max > rolls:
		rolls = _rng.randi_range(rolls, rolls_max)
	rolls += int(floor(float(tier) * float(opts.get("tier_bonus_rolls", 0.0))))
	rolls += int(floor(maxf(0.0, luck) * 1.5))
	rolls = clampi(rolls, 0, 32)

	var luck_weight := float(opts.get("luck_weight", 1.0))
	var nothing := maxf(0.0, float(opts.get("nothing_weight", 0.0)))
	for _i in rolls:
		var total := nothing
		var weights: Array[float] = []
		weights.resize(pool.size())
		for j in pool.size():
			var w := _weight_of(pool[j], tier, luck, luck_weight)
			weights[j] = w
			total += w
		if total <= 0.0:
			break
		var pick := _rng.randf() * total
		var acc := nothing
		if pick < acc:
			continue
		for j in pool.size():
			acc += weights[j]
			if pick <= acc:
				_emit(pool[j], tier, luck, out)
				break
	return _compact(out)


## Roll and push straight into an inventory/container. Returns what did not
## fit, so the caller can spill it into the world.
static func roll_into(target: Variant, table_id: StringName, tier: int = 0, luck: float = 0.0) -> Array[ItemStack]:
	var inv := ItemContainer.as_inventory(target)
	var left: Array[ItemStack] = []
	var rolled := roll(table_id, tier, luck)
	if inv == null:
		return rolled
	inv.begin_batch()
	for st: ItemStack in rolled:
		if inv.add(st) > 0:
			left.append(st)
	inv.end_batch()
	return left


## Roll and spawn the result as physical drops at `world_pos`. Returns the
## number of stacks spawned. This is what monsters and breakables call.
static func drop_at(world_pos: Vector3, table_id: StringName, tier: int = 0, luck: float = 0.0) -> int:
	var n := 0
	for st: ItemStack in roll(table_id, tier, luck):
		if Game.spawn_item_drop(world_pos, st.id, st.count, st.data) != null:
			n += 1
	return n


# ==================================================================== internals ==
static func _tier_ok(e: Dictionary, tier: int) -> bool:
	return tier >= int(e.get("min_tier", 0)) and tier <= int(e.get("max_tier", 999))


static func _rarity_of(e: Dictionary) -> int:
	if e.has("rarity"):
		return int(e["rarity"])
	var id := _entry_id(e)
	if id == &"":
		return Const.RARITY_COMMON
	var t := Items.get_type(id)
	return t.rarity if t != null else Const.RARITY_COMMON


static func _entry_id(e: Dictionary) -> StringName:
	if e.has("item"):
		return StringName(e["item"])
	var list: Array = e.get("items", [])
	return StringName(list[0]) if not list.is_empty() else &""


## Luck raises the weight of rare entries and slightly suppresses common ones,
## so a lucky roll shifts the *shape* of the table rather than just adding rolls.
static func _weight_of(e: Dictionary, tier: int, luck: float, luck_weight: float) -> float:
	var w := maxf(0.0, float(e.get("weight", 1.0)))
	if w <= 0.0:
		return 0.0
	var rarity := _rarity_of(e)
	if rarity > 0:
		w *= pow(1.0 + clampf(luck, -0.9, 4.0) * luck_weight, float(rarity))
	elif luck > 0.0:
		w /= 1.0 + luck * luck_weight * 0.25
	# Entries gated behind a tier become more likely the deeper past it you are.
	var band := tier - int(e.get("min_tier", 0))
	if band > 0:
		w *= 1.0 + minf(float(band), 4.0) * 0.15
	return w


static func _emit(e: Dictionary, tier: int, luck: float, out: Array[ItemStack]) -> void:
	if e.has("pixels"):
		var pr: Array = e["pixels"]
		var lo := int(pr[0]) if pr.size() > 0 else 0
		var hi := int(pr[1]) if pr.size() > 1 else lo
		var amount := _rng.randi_range(lo, maxi(lo, hi))
		amount = int(round(float(amount) * (1.0 + float(tier) * 0.35) * (1.0 + maxf(0.0, luck) * 0.5)))
		if amount > 0:
			Pixels.reward(amount)
		return
	var chance := float(e.get("chance", 1.0))
	if chance < 1.0 and _rng.randf() > clampf(chance + luck * 0.1, 0.0, 1.0):
		return
	var id := _entry_id(e)
	if e.has("items"):
		var list: Array = e["items"]
		if not list.is_empty():
			id = StringName(list[_rng.randi_range(0, list.size() - 1)])
	if id == &"" or not Items.has(id):
		if id != &"":
			push_warning("[LootRoller] entry drops unknown item '%s'" % id)
		return
	var lo_c := int(e.get("min", 1))
	var hi_c := int(e.get("max", lo_c))
	var count := _rng.randi_range(mini(lo_c, hi_c), maxi(lo_c, hi_c))
	var scale := float(e.get("tier_scale", 0.0))
	if scale > 0.0:
		count += int(floor(float(maxi(0, tier - int(e.get("min_tier", 0)))) * scale))
	if count <= 0:
		return
	var st := Items.make(id, count)
	var data: Dictionary = e.get("data", {})
	for k: Variant in data:
		st.data[k] = data[k]
	out.append(st)


## Merge duplicate ids so a table that hit the same entry twice yields one
## stack instead of two.
static func _compact(list: Array[ItemStack]) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for s: ItemStack in list:
		var merged := false
		for o: ItemStack in out:
			if o.can_merge_with(s) and o.count + s.count <= o.max_stack():
				o.count += s.count
				merged = true
				break
		if not merged:
			out.append(s)
	return out


# ============================================================= default tables ==
## A small starter set so monsters, chests and breakables have something to
## point at before the content agents land. Every entry references items from
## `content/items/10_materials.gd`, and unknown ids are skipped at roll time.
static func _ensure_defaults() -> void:
	if _defaults_ready:
		return
	_defaults_ready = true
	_rng.randomize()

	register(&"ore_common", [
		{"item": &"raw_copper", "min": 1, "max": 3, "weight": 30, "max_tier": 2},
		{"item": &"raw_iron", "min": 1, "max": 3, "weight": 24, "min_tier": 0},
		{"item": &"coal", "min": 1, "max": 4, "weight": 20},
		{"item": &"raw_silver", "min": 1, "max": 2, "weight": 10, "min_tier": 1},
		{"item": &"raw_gold", "min": 1, "max": 2, "weight": 7, "min_tier": 2},
		{"item": &"raw_titanium", "min": 1, "max": 2, "weight": 5, "min_tier": 3},
		{"item": &"crystal_shard", "min": 1, "max": 2, "weight": 4, "min_tier": 2},
	], {"rolls": 1, "tier_bonus_rolls": 0.3})

	register(&"ore_deep", [
		{"item": &"raw_aegisalt", "min": 1, "max": 2, "weight": 12, "min_tier": 4},
		{"item": &"raw_ferozium", "min": 1, "max": 2, "weight": 9, "min_tier": 5},
		{"item": &"raw_violium", "min": 1, "max": 2, "weight": 9, "min_tier": 5},
		{"item": &"raw_solarium", "min": 1, "max": 1, "weight": 3, "min_tier": 6},
		{"item": &"diamond", "min": 1, "max": 1, "weight": 4, "min_tier": 3},
		{"item": &"erchius_fuel", "min": 1, "max": 2, "weight": 6, "min_tier": 3},
	], {"rolls": 1, "tier_bonus_rolls": 0.4, "nothing_weight": 8.0})

	register(&"monster_small", [
		{"item": &"monster_fur", "min": 1, "max": 2, "weight": 30},
		{"item": &"chitin", "min": 1, "max": 3, "weight": 22},
		{"item": &"slime_glob", "min": 1, "max": 2, "weight": 18},
		{"item": &"bone", "min": 1, "max": 2, "weight": 14},
		{"item": &"venom_gland", "min": 1, "max": 1, "weight": 5, "rarity": 1},
		{"pixels": [4, 12]},
	], {"rolls": 1, "rolls_max": 2, "tier_bonus_rolls": 0.3})

	# `MobSpecies.loot_table` defaults to &"generic", so it must always exist.
	register(&"generic", [
		{"item": &"monster_fur", "min": 1, "max": 2, "weight": 20},
		{"item": &"chitin", "min": 1, "max": 2, "weight": 16},
		{"item": &"bone", "min": 1, "max": 2, "weight": 14},
		{"item": &"slime_glob", "min": 1, "max": 2, "weight": 12},
		{"pixels": [3, 9]},
	], {"rolls": 1, "nothing_weight": 6.0, "tier_bonus_rolls": 0.25})

	register(&"monster_large", [
		{"item": &"chitin_plate", "min": 1, "max": 3, "weight": 26},
		{"item": &"scale_plate", "min": 1, "max": 2, "weight": 20},
		{"item": &"sharp_claw", "min": 1, "max": 2, "weight": 16},
		{"item": &"fang", "min": 1, "max": 2, "weight": 14},
		{"item": &"glow_gland", "min": 1, "max": 1, "weight": 8, "rarity": 1},
		{"item": &"ectoplasm", "min": 1, "max": 1, "weight": 4, "rarity": 2, "min_tier": 2},
		{"item": &"bone", "guaranteed": true, "min": 1, "max": 3},
		{"pixels": [20, 45]},
	], {"rolls": 2, "rolls_max": 3, "tier_bonus_rolls": 0.4})

	register(&"chest_surface", [
		{"item": &"plant_fibre", "min": 2, "max": 6, "weight": 24},
		{"item": &"copper_bar", "min": 1, "max": 3, "weight": 18},
		{"item": &"iron_bar", "min": 1, "max": 3, "weight": 14, "min_tier": 1},
		{"item": &"battery", "min": 1, "max": 2, "weight": 10},
		{"item": &"circuit_board", "min": 1, "max": 2, "weight": 8},
		{"item": &"amethyst", "min": 1, "max": 1, "weight": 5, "rarity": 1},
		{"pixels": [15, 60]},
	], {"rolls": 2, "rolls_max": 4, "tier_bonus_rolls": 0.5})

	register(&"chest_vault", [
		{"item": &"aegisalt_bar", "min": 1, "max": 3, "weight": 12, "min_tier": 4},
		{"item": &"power_core", "min": 1, "max": 1, "weight": 10, "rarity": 2},
		{"item": &"ancient_relic", "min": 1, "max": 1, "weight": 6, "rarity": 3},
		{"item": &"diamond", "min": 1, "max": 2, "weight": 8, "rarity": 2},
		{"item": &"protocite", "min": 1, "max": 3, "weight": 10, "min_tier": 3},
		{"pixels": [150, 400]},
	], {"rolls": 3, "rolls_max": 5, "luck_weight": 1.5, "tier_bonus_rolls": 0.5})

	register(&"fossil_dig", [
		{"item": &"fossil_fragment", "guaranteed": true, "min": 1, "max": 3},
		{"item": &"trilobite_fossil", "min": 1, "max": 1, "weight": 10, "rarity": 1},
		{"item": &"amber_shard", "min": 1, "max": 2, "weight": 12, "rarity": 1},
		{"item": &"ancient_skull", "min": 1, "max": 1, "weight": 4, "rarity": 2},
		{"item": &"petrified_egg", "min": 1, "max": 1, "weight": 2, "rarity": 3},
	], {"rolls": 1, "nothing_weight": 6.0, "luck_weight": 1.4})

	register(&"foliage", [
		{"item": &"plant_fibre", "min": 1, "max": 3, "weight": 40},
		{"item": &"plant_matter", "min": 1, "max": 2, "weight": 30},
		{"item": &"vine_cord", "min": 1, "max": 2, "weight": 12},
		{"item": &"straw", "min": 1, "max": 2, "weight": 10},
	], {"rolls": 1, "nothing_weight": 10.0})
