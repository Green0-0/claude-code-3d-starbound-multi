## Shop maths shared by the merchant, blacksmith, doctor and wandering trader.
##
## Stock is a pure function of (world seed, npc id, planet tier, restock day), so
## it survives save/load without being serialised and rotates once a day. Prices
## key off [member ItemType.value] and are shaded by the player's standing with
## that specific NPC.
class_name NpcShop
extends RefCounted

## Multiplier applied to an item's base value when the shop sells it.
const MARKUP := 2.2
## Fraction of base value the shop pays when buying from the player.
const BUYBACK := 0.35
## Days between stock rotations.
const RESTOCK_DAYS := 1


## Builds the shop list. `kinds` filters by [enum ItemType.Kind]; empty = any.
## Returns `[{id, count, price}]` sorted for a stable UI.
static func build_stock(npc_id: StringName, tier: int, kinds: Array[int],
		size: int = 8, day: int = -1) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	var restock_day := day if day >= 0 else Game.day
	rng.seed = hash(npc_id) ^ (Game.run_seed * 31) ^ ((restock_day / RESTOCK_DAYS) * 7919)

	var max_rarity := clampi(tier / 2, Const.RARITY_COMMON, Const.RARITY_LEGENDARY)
	var pool: Array[ItemType] = []
	for iid: StringName in Items.order:
		var it := Items.get_type(iid)
		if it == null or it.rarity > max_rarity or it.value <= 0:
			continue
		if not kinds.is_empty() and not kinds.has(int(it.kind)):
			continue
		# Cheap filler blocks are boring stock; let a few through, not the lot.
		if it.kind == ItemType.Kind.BLOCK and rng.randf() > 0.12:
			continue
		pool.append(it)
	if pool.is_empty():
		return []

	var out: Array[Dictionary] = []
	var taken := {}
	var attempts := 0
	while out.size() < size and attempts < size * 12:
		attempts += 1
		var it := pool[rng.randi_range(0, pool.size() - 1)]
		if taken.has(it.id):
			continue
		taken[it.id] = true
		var count := 1
		if it.stack_size > 1:
			count = rng.randi_range(4, 12 + tier * 4)
		out.append({
			"id": it.id,
			"count": count,
			"price": price_to_buy(npc_id, it.id),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["price"]) < int(b["price"]))
	return out


## What the player pays for one unit.
static func price_to_buy(npc_id: StringName, item_id: StringName) -> int:
	var it := Items.get_type(item_id)
	if it == null:
		return 1
	var rarity_mult := 1.0 + float(it.rarity) * 0.45
	var p := float(it.value) * MARKUP * rarity_mult * NpcReputation.price_multiplier(npc_id)
	return maxi(1, int(round(p)))


## What the shop pays the player for one unit.
static func price_to_sell(npc_id: StringName, item_id: StringName) -> int:
	var it := Items.get_type(item_id)
	if it == null:
		return 0
	var rep := clampf(NpcReputation.of_npc(npc_id), -100.0, 100.0)
	var p := float(it.value) * BUYBACK * (1.0 + rep * 0.0025)
	return maxi(1, int(round(p)))


## Player buys [param count] of [param item_id] from [param npc]. Returns false
## when they cannot afford it or the shop is out.
static func buy(npc: Node, item_id: StringName, count: int = 1) -> bool:
	if npc == null or count <= 0:
		return false
	var npc_id := StringName(npc.get("npc_id"))
	var stock: Array = npc.call(&"shop_stock") if npc.has_method(&"shop_stock") else []
	var row: Dictionary = {}
	for r: Variant in stock:
		if StringName((r as Dictionary).get("id", "")) == item_id:
			row = r as Dictionary
			break
	if row.is_empty() or int(row.get("count", 0)) < count:
		Events.toast("They don't have that many.", "warn")
		return false
	var total := price_to_buy(npc_id, item_id) * count
	if not NpcInventoryBridge.spend_pixels(total):
		Events.toast("Not enough pixels.", "warn")
		Events.play_sound.emit(&"denied", _at(npc))
		return false
	row["count"] = int(row["count"]) - count
	NpcInventoryBridge.give(item_id, count)
	NpcReputation.adjust_npc(npc_id, 0.4)
	Events.play_sound.emit(&"coin", _at(npc))
	Events.toast("Bought %s x%d for %d px." % [Items.display_name(item_id), count, total], "info")
	return true


## Player sells to the shop.
static func sell(npc: Node, item_id: StringName, count: int = 1) -> bool:
	if npc == null or count <= 0:
		return false
	var npc_id := StringName(npc.get("npc_id"))
	if NpcInventoryBridge.take(item_id, count) < count:
		return false
	var total := price_to_sell(npc_id, item_id) * count
	NpcInventoryBridge.add_pixels(total)
	NpcReputation.adjust_npc(npc_id, 0.2)
	Events.play_sound.emit(&"coin", _at(npc))
	Events.toast("Sold %s x%d for %d px." % [Items.display_name(item_id), count, total], "info")
	return true


static func _at(npc: Node) -> Vector3:
	var n3 := npc as Node3D
	return n3.global_position if n3 != null else Vector3.ZERO
