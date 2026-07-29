## Pixels — the universal currency. Everything that dies, everything you sell
## and every ancient vault pays out in pixels; vendors, 3D-printers and fuel
## depots take them back.
##
## Pixels are a [b]balance, not an inventory item[/b]. They occupy no slot, they
## cannot be dropped by accident and they survive an inventory rearrange. The
## whole API is static so any module can reach it without a reference:
##
## [codeblock]
## if Pixels.can_afford(250):
##     Pixels.spend(250, "vendor")
## Pixels.reward(monster_value)                  # loot / quest payouts
## var n := Pixels.sell(inv, &"raw_copper", 10)  # -> pixels earned
## [/codeblock]
##
## Every change emits `Events.currency_changed(new_balance)`. Earnings also
## bump `Game.stats["pixels_earned"]`.
class_name Pixels
extends RefCounted

## Reserved item id. Nothing registers an item under this name by default; if a
## content file ever does, the pickup path still routes it to the balance.
const ITEM_ID := &"pixels"

## Vendors buy at this fraction of an item's `value`, and sell at `value`.
const SELL_RATE := 0.4
## Hard ceiling so a runaway loot table cannot overflow the save file.
const MAX_BALANCE := 999_999_999

static var _balance: int = 0
## Running total earned this run, for the stats screen.
static var _lifetime_earned: int = 0
## Running total spent this run.
static var _lifetime_spent: int = 0


## Current balance.
static func balance() -> int:
	return _balance


static func lifetime_earned() -> int:
	return _lifetime_earned


static func lifetime_spent() -> int:
	return _lifetime_spent


## Add pixels. `reason` is free-form and only used for the toast/telemetry.
## Negative amounts are ignored — use [method spend].
static func add(amount: int, reason: String = "") -> int:
	if amount <= 0:
		return _balance
	_balance = mini(MAX_BALANCE, _balance + amount)
	_lifetime_earned += amount
	Game.bump_stat("pixels_earned", amount)
	Events.currency_changed.emit(_balance)
	if reason == "reward":
		Events.toast("+%s pixels" % _format(amount), "good")
	return _balance


## Loot / quest payout: same as [method add] but always toasts.
static func reward(amount: int) -> int:
	return add(amount, "reward")


static func can_afford(amount: int) -> bool:
	return amount <= 0 or _balance >= amount


## Deduct pixels. Returns false and changes nothing when the player is short.
static func spend(amount: int, reason: String = "") -> bool:
	if amount <= 0:
		return true
	if _balance < amount:
		Events.toast("Not enough pixels", "warn")
		Events.play_sound.emit(&"denied", Vector3.ZERO)
		return false
	_balance -= amount
	_lifetime_spent += amount
	Events.currency_changed.emit(_balance)
	Events.play_sound.emit(&"pixels_spend", Vector3.ZERO)
	if reason != "":
		Events.toast("-%s pixels" % _format(amount), "info")
	return true


## Overwrite the balance outright (debug, cheats, new game).
static func set_balance(amount: int) -> void:
	_balance = clampi(amount, 0, MAX_BALANCE)
	Events.currency_changed.emit(_balance)


## Reset for a new run.
static func reset(starting: int = 0) -> void:
	_balance = clampi(starting, 0, MAX_BALANCE)
	_lifetime_earned = 0
	_lifetime_spent = 0
	Events.currency_changed.emit(_balance)


# ==================================================================== trade ====
## What a vendor pays for one unit of `id`, before any haggling multiplier.
static func sell_price(id: StringName, multiplier: float = 1.0) -> int:
	var t := Items.get_type(id)
	if t == null or t.has_tag(&"no_sell"):
		return 0
	return maxi(0, int(round(float(t.value) * SELL_RATE * multiplier)))


## What a vendor charges for one unit of `id`.
static func buy_price(id: StringName, multiplier: float = 1.0) -> int:
	var t := Items.get_type(id)
	if t == null:
		return 0
	return maxi(1, int(round(float(t.value) * multiplier)))


## Total sale value of a stack (its own `data["value"]` override wins).
static func stack_value(stack: ItemStack, multiplier: float = 1.0) -> int:
	if stack == null or stack.is_empty():
		return 0
	if stack.data.has("value"):
		return maxi(0, int(round(float(stack.data["value"]) * SELL_RATE * multiplier * stack.count)))
	return sell_price(stack.id, multiplier) * stack.count


## Sell `count` of `id` out of `inv`. Removes only what it can pay for and
## returns the pixels earned (0 when the item is worthless or absent).
##
## `inv` is any object exposing the [Inventory] API (an `Inventory` or an
## `ItemContainer`); it is duck-typed so this file stays independent of them.
static func sell(inv: Object, id: StringName, count: int = 1, multiplier: float = 1.0) -> int:
	if inv == null or count <= 0 or not inv.has_method(&"remove"):
		return 0
	var unit := sell_price(id, multiplier)
	if unit <= 0:
		Events.toast("%s cannot be sold." % Items.display_name(id), "warn")
		return 0
	var sold := int(inv.call(&"remove", id, count))
	if sold <= 0:
		return 0
	var earned := unit * sold
	add(earned, "sale")
	Events.play_sound.emit(&"vendor_sell", Vector3.ZERO)
	return earned


## Sell everything in `inv` carrying `tag` (the "sell all junk" button).
static func sell_all_tagged(inv: Object, tag: StringName, multiplier: float = 1.0) -> int:
	if inv == null or not inv.has_method(&"contents"):
		return 0
	var earned := 0
	var held: Dictionary = inv.call(&"contents")
	if inv.has_method(&"begin_batch"):
		inv.call(&"begin_batch")
	for k: Variant in held:
		var id := StringName(k)
		var t := Items.get_type(id)
		if t != null and t.has_tag(tag):
			earned += sell(inv, id, int(held[k]), multiplier)
	if inv.has_method(&"end_batch"):
		inv.call(&"end_batch")
	return earned


## Buy `count` of `id` into `inv`. Atomic: fails without spending when the
## player is short on pixels or on inventory room.
static func buy(inv: Object, id: StringName, count: int = 1, multiplier: float = 1.0) -> bool:
	if inv == null or count <= 0 or not Items.has(id) or not inv.has_method(&"add_id"):
		return false
	var price := buy_price(id, multiplier) * count
	if not can_afford(price):
		Events.toast("Not enough pixels", "warn")
		return false
	if inv.has_method(&"can_accept") and not bool(inv.call(&"can_accept", id, count)):
		Events.toast("No room for %s" % Items.display_name(id), "warn")
		return false
	if not spend(price, ""):
		return false
	inv.call(&"add_id", id, count)
	Events.play_sound.emit(&"vendor_buy", Vector3.ZERO)
	return true


## Thousands-separated display string, e.g. `12,480`.
static func format(amount: int) -> String:
	return _format(amount)


static func _format(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	var n := s.length()
	for i in n:
		if i > 0 and (n - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if amount < 0 else "") + out


# ============================================================ serialisation ====
static func to_dict() -> Dictionary:
	return {"balance": _balance, "earned": _lifetime_earned, "spent": _lifetime_spent}


static func from_dict(d: Dictionary) -> void:
	_balance = clampi(int(d.get("balance", 0)), 0, MAX_BALANCE)
	_lifetime_earned = int(d.get("earned", 0))
	_lifetime_spent = int(d.get("spent", 0))
	Events.currency_changed.emit(_balance)
