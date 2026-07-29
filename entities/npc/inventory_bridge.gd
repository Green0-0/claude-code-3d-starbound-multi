## Defensive adapter between this module and whatever the inventory agent ships.
##
## Quests, dialogue effects and merchants all need to add/remove items and move
## pixels, but the inventory API is authored by a different agent and may not
## exist yet. Every call here probes a list of plausible method names, falls back
## to something harmless, and never crashes. If the real API lands with different
## names, only this file needs a line added.
class_name NpcInventoryBridge
extends RefCounted

## Item id used for pixels when the inventory has no dedicated currency field.
const PIXEL_ITEM: StringName = &"pixels"
## The inventory agent's static currency class, when it exists.
const CURRENCY_SCRIPT := "res://inventory/currency.gd"

static var _currency: Object = null
static var _currency_probed := false


## `Pixels` (inventory/currency.gd), or null if that module has not landed.
static func currency() -> Object:
	if not _currency_probed:
		_currency_probed = true
		if ResourceLoader.exists(CURRENCY_SCRIPT):
			var scr := load(CURRENCY_SCRIPT) as Script
			if scr != null and scr.has_method(&"balance"):
				_currency = scr
	return _currency


static func player() -> Node:
	return Game.player


static func inventory() -> Object:
	var p := Game.player
	if p == null:
		return null
	var inv: Variant = p.get("inventory")
	return inv as Object


# ------------------------------------------------------------------- items
## How many of [param item_id] the player holds. -1 is never returned; an
## unavailable inventory reads as 0.
static func count_of(item_id: StringName) -> int:
	var inv := inventory()
	if inv == null:
		return 0
	for m: StringName in [&"count_of", &"count", &"item_count", &"amount_of"]:
		if inv.has_method(m):
			return int(inv.call(m, item_id))
	if inv.has_method(&"has_item"):
		return 1 if bool(inv.call(&"has_item", item_id, 1)) else 0
	return 0


static func has_item(item_id: StringName, count: int = 1) -> bool:
	return count_of(item_id) >= count


## Gives the player [param count] of [param item_id]. Anything that will not fit
## is dropped at their feet. Returns the number actually delivered.
static func give(item_id: StringName, count: int = 1, data: Dictionary = {}) -> int:
	if count <= 0 or not Items.has(item_id):
		return 0
	var inv := inventory()
	if inv != null:
		var stack := ItemStack.new(item_id, count, data)
		for m: StringName in [&"add_stack", &"add", &"insert", &"give"]:
			if inv.has_method(m):
				var left: Variant = inv.call(m, stack)
				var remaining := count
				if left is int:
					remaining = int(left)
				elif left is bool:
					remaining = 0 if bool(left) else count
				elif left is ItemStack:
					remaining = (left as ItemStack).count
				elif stack.count != count:
					remaining = stack.count
				if remaining > 0:
					_drop(item_id, remaining, data)
				return count - remaining
		if inv.has_method(&"add_item"):
			inv.call(&"add_item", item_id, count)
			return count
	var p := player()
	if p != null and p.has_method(&"give_item"):
		if bool(p.call(&"give_item", item_id, count)):
			return count
	_drop(item_id, count, data)
	return count


## Removes up to [param count]. Returns how many were actually removed.
static func take(item_id: StringName, count: int = 1) -> int:
	if count <= 0:
		return 0
	var inv := inventory()
	if inv == null:
		return 0
	for m: StringName in [&"remove", &"remove_item", &"take", &"consume"]:
		if inv.has_method(m):
			var r: Variant = inv.call(m, item_id, count)
			if r is int:
				return int(r)
			if r is bool:
				return count if bool(r) else 0
			return count
	return 0


static func _drop(item_id: StringName, count: int, data: Dictionary) -> void:
	var p := player() as Node3D
	var at := Vector3.ZERO
	if p != null:
		at = p.global_position + Vector3(0, 0.6, 0)
	Game.spawn_item_drop(at, item_id, count, data)


# ---------------------------------------------------------------- currency
## The player's pixel balance.
static func pixels() -> int:
	var cur := currency()
	if cur != null:
		return int(cur.call(&"balance"))
	var inv := inventory()
	if inv != null:
		for m: StringName in [&"get_currency", &"get_pixels", &"currency_amount"]:
			if inv.has_method(m):
				return int(inv.call(m))
		for f: String in ["pixels", "currency", "money"]:
			var v: Variant = inv.get(f)
			if v is int or v is float:
				return int(v)
	return count_of(PIXEL_ITEM)


static func add_pixels(amount: int) -> void:
	if amount == 0:
		return
	var cur := currency()
	if cur != null:
		cur.call(&"reward", amount)
		return
	var inv := inventory()
	if inv != null:
		for m: StringName in [&"add_currency", &"add_pixels", &"earn"]:
			if inv.has_method(m):
				inv.call(m, amount)
				_pixel_signal()
				return
		for f: String in ["pixels", "currency", "money"]:
			var v: Variant = inv.get(f)
			if v is int or v is float:
				inv.set(f, maxi(0, int(v) + amount))
				_pixel_signal()
				return
	if Items.has(PIXEL_ITEM) and amount > 0:
		give(PIXEL_ITEM, amount)
	if amount > 0:
		Game.bump_stat("pixels_earned", float(amount))
	_pixel_signal()


## Returns false (and spends nothing) when the player cannot afford it.
static func spend_pixels(amount: int) -> bool:
	if amount <= 0:
		return true
	var cur := currency()
	if cur != null:
		return bool(cur.call(&"spend", amount, "trade"))
	var inv := inventory()
	if inv != null:
		for m: StringName in [&"spend_currency", &"spend_pixels", &"pay"]:
			if inv.has_method(m):
				return bool(inv.call(m, amount))
	if pixels() < amount:
		return false
	var inv2 := inventory()
	if inv2 != null:
		for f: String in ["pixels", "currency", "money"]:
			var v: Variant = inv2.get(f)
			if v is int or v is float:
				inv2.set(f, maxi(0, int(v) - amount))
				_pixel_signal()
				return true
	if Items.has(PIXEL_ITEM):
		return take(PIXEL_ITEM, amount) >= amount
	return false


static func _pixel_signal() -> void:
	Events.currency_changed.emit(pixels())


# -------------------------------------------------------------- learning
static func learn_recipe(recipe: StringName) -> void:
	if Recipes.has_method(&"unlock"):
		Recipes.call(&"unlock", recipe)
	elif Recipes.has_method(&"learn"):
		Recipes.call(&"learn", recipe)
	Events.recipe_learned.emit(String(recipe))


static func unlock_tech(tech: StringName) -> void:
	if Tech.has_method(&"unlock"):
		Tech.unlock(tech)


static func heal_player(amount: float) -> void:
	var p := Game.player
	if p != null:
		p.heal(amount)
		Events.player_healed.emit(amount)


## Strips every debuff the survival agent understands. Safe when it is a stub.
static func cure_player(ids: Array = []) -> void:
	var p := Game.player
	if p == null:
		return
	var list := ids
	if list.is_empty():
		list = [&"poison", &"burning", &"bleeding", &"frozen", &"radiation",
			&"starving", &"infected", &"cursed"]
	for id: Variant in list:
		Status.remove(StringName(id), p)
