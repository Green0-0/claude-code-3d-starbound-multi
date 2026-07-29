## A shared, savable box of items: chests, ship lockers, machine input/output
## buffers, vendor stock, hopper buffers.
##
## A container wraps an [Inventory] (`inv`) instead of subclassing it, so every
## API you already know still applies — the container adds the things a *world*
## object needs and a bare model does not: a stable id, an ownership lock,
## an accept-filter, a viewer count and transfer helpers.
##
## [b]Ownership.[/b] Containers register themselves in a static table keyed by
## [member id], so an object node only has to remember its id string; the
## persistence agent saves and restores every registered container in one call
## ([method save_all] / [method load_all]).
##
## [codeblock]
## # A chest node in objects/:
## var box := ItemContainer.get_or_create(&"chest_%d_%d_%d" % [p.x, p.y, p.z], 27, "Chest")
## box.add_id(&"iron_bar", 4)
##
## # A refinery that only accepts ore:
## var hopper := ItemContainer.new(&"refinery_in", 6, "Refinery")
## hopper.accept_tags = [&"ore"]
## hopper.accepts(Items.make(&"raw_iron", 1))   # true
## hopper.accepts(Items.make(&"iron_bar", 1))   # false
## [/codeblock]
class_name ItemContainer
extends RefCounted

## Emitted (coalesced) whenever the contents change.
signal changed()
## Emitted when a viewer opens or closes the container.
signal viewers_changed(count: int)

const DEFAULT_CAPACITY := 27

static var _registry: Dictionary = {}   ## StringName -> ItemContainer

## Stable key. Must be unique; world containers usually encode their position.
var id: StringName = &""
## Shown in the container window's title bar.
var display_name: String = "Container"
## The model. Every storage method here forwards to it; use it directly for
## anything this class does not wrap (`inv.slot(i)`, `inv.sort()`, ...).
var inv: Inventory = null

# ------------------------------------------------------------------ ownership
## While locked only [member owner_id] may open the container.
var locked: bool = false
## Free-form owner key — a player name, a faction, a quest id.
var owner_id: String = ""
## Number of UI windows currently showing this container.
var viewers: int = 0
## When false, [method save_all] skips this container (scratch buffers).
var persistent: bool = true

# --------------------------------------------------------------------- filter
## When non-empty, a stack is accepted only if its item carries one of these
## tags. Feeds hoppers, refineries and fuel slots.
var accept_tags: Array[StringName] = []
## Stacks whose item carries any of these tags are always refused.
var reject_tags: Array[StringName] = []
## When non-empty, only these exact item ids are accepted.
var accept_ids: Array[StringName] = []
## When non-empty, only these `ItemType.Kind` values are accepted.
var accept_kinds: Array[int] = []
## Final say: `func(stack: ItemStack) -> bool`. Checked after the lists.
var custom_filter: Callable = Callable()


func _init(p_id: StringName = &"", p_capacity: int = DEFAULT_CAPACITY, p_display: String = "") -> void:
	id = p_id
	display_name = p_display if p_display != "" else String(p_id).capitalize()
	inv = Inventory.new(maxi(1, p_capacity), 0)
	inv.emit_global = false
	inv.accept_filter = Callable(self, &"accepts")
	inv.changed.connect(func() -> void: changed.emit())
	if id != &"":
		_registry[id] = self


# ================================================================== filtering ==
## True when `stack` is allowed in. Also used as the [Inventory] accept filter,
## so no code path can sneak a rejected item in.
func accepts(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false
	var t := stack.type()
	if not accept_ids.is_empty() and not accept_ids.has(stack.id):
		return false
	if t != null:
		if not accept_kinds.is_empty() and not accept_kinds.has(int(t.kind)):
			return false
		for tag: StringName in reject_tags:
			if t.has_tag(tag):
				return false
		if not accept_tags.is_empty():
			var ok := false
			for tag: StringName in accept_tags:
				if t.has_tag(tag):
					ok = true
					break
			if not ok:
				return false
	elif not accept_tags.is_empty() or not accept_kinds.is_empty():
		return false
	if custom_filter.is_valid():
		return bool(custom_filter.call(stack))
	return true


## Restrict this container to items carrying any of `tags`. Fluent.
func only_tags(tags: Array[StringName]) -> ItemContainer:
	accept_tags = tags.duplicate()
	return self


## Restrict this container to an explicit id whitelist. Fluent.
func only_ids(ids: Array[StringName]) -> ItemContainer:
	accept_ids = ids.duplicate()
	return self


# ================================================================== storage ====
func capacity() -> int:
	return inv.size


## Alias of [method capacity] — the name `UI` probes to recognise a container.
func container_size() -> int:
	return inv.size


## Fill from a rolled loot list. Accepts [ItemStack]s or the
## `[{"item": StringName, "count": int}, ...]` dictionaries that
## `StructLoot.roll()` and quest rewards produce. Returns the number of items
## that did not fit.
func fill_from(rolled: Array) -> int:
	var left := 0
	inv.begin_batch()
	for e: Variant in rolled:
		if e is ItemStack:
			left += inv.add((e as ItemStack).duplicate_stack())
		elif e is Dictionary:
			var d: Dictionary = e
			var id := StringName(d.get("item", d.get("id", &"")))
			var n := int(d.get("count", 1))
			if id != &"" and n > 0 and Items.has(id):
				left += inv.add_id(id, n, d.get("data", {}))
	inv.end_batch()
	return left


## Grow or shrink the container. Shrinking returns the stacks that no longer
## fit so the caller can spill them into the world.
func resize(n: int) -> Array[ItemStack]:
	var spill: Array[ItemStack] = []
	n = maxi(1, n)
	if n >= inv.size:
		var d := inv.to_dict()
		d["size"] = n
		inv.from_dict(d)
		return spill
	for i in range(n, inv.size):
		var s := inv.slot(i)
		if not s.is_empty():
			spill.append(s.duplicate_stack())
	var dd := inv.to_dict()
	var slots: Array = dd["slots"]
	slots.resize(n)
	dd["slots"] = slots
	dd["size"] = n
	inv.from_dict(dd)
	return spill


## Insert a stack. `stack` is consumed in place; returns the leftover count.
func add(stack: ItemStack) -> int:
	return inv.add(stack)


func add_id(item_id: StringName, count: int = 1, data: Dictionary = {}) -> int:
	if not accepts(ItemStack.new(item_id, maxi(1, count))):
		return count
	return inv.add_id(item_id, count, data)


func remove(item_id: StringName, count: int = 1) -> int:
	return inv.remove(item_id, count)


func count_of(item_id: StringName) -> int:
	return inv.count_of(item_id)


func has(item_id: StringName, count: int = 1) -> bool:
	return inv.has(item_id, count)


func has_all(req: Dictionary) -> bool:
	return inv.has_all(req)


func consume(req: Dictionary) -> bool:
	return inv.consume(req)


func slot(i: int) -> ItemStack:
	return inv.slot(i)


func set_slot(i: int, stack: ItemStack) -> void:
	inv.set_slot(i, stack)


func take_from_slot(i: int, count: int = -1) -> ItemStack:
	return inv.take_from_slot(i, count)


func first_empty() -> int:
	return inv.first_empty()


func is_full() -> bool:
	return inv.is_full()


func is_empty() -> bool:
	return inv.is_empty()


func contents() -> Dictionary:
	return inv.contents()


func sort() -> void:
	inv.sort(true)


func clear() -> void:
	inv.clear()


# ================================================================ access gate ==
## True when `who` may open this container. `who` is matched against
## [member owner_id]; pass the player's id, or "" for anonymous access.
func can_open(who: String = "") -> bool:
	return not locked or owner_id == "" or owner_id == who


## Register a viewer. Returns false when the container is locked to someone
## else — show the "locked" toast and do not open the window.
func open(who: String = "") -> bool:
	if not can_open(who):
		Events.toast("%s is locked." % display_name, "warn")
		Events.play_sound.emit(&"denied", Vector3.ZERO)
		return false
	viewers += 1
	viewers_changed.emit(viewers)
	Events.play_sound.emit(&"container_open", Vector3.ZERO)
	return true


func close(_who: String = "") -> void:
	viewers = maxi(0, viewers - 1)
	viewers_changed.emit(viewers)


## Lock the container to an owner key. Empty `who` locks it to nobody, which
## means "locked but openable" — use it for display-only cases.
func lock_to(who: String) -> void:
	locked = true
	owner_id = who


## Unlock. Only the owner (or an empty owner) may do so; returns success.
func unlock(who: String = "") -> bool:
	if owner_id != "" and owner_id != who:
		return false
	locked = false
	owner_id = ""
	return true


# ================================================================= transfers ==
## Accepts an [Inventory], an [ItemContainer], or any object exposing `inv`.
static func as_inventory(v: Variant) -> Inventory:
	if v is Inventory:
		return v
	if v is ItemContainer:
		return (v as ItemContainer).inv
	if v is Object and (v as Object).get(&"inv") is Inventory:
		return (v as Object).get(&"inv")
	return null


## Push the stack in `slot_index` of this container into `other`. `amount < 0`
## moves the whole stack. Returns the number of items that actually moved;
## anything the target refuses stays put.
func transfer_to(other: Variant, slot_index: int, amount: int = -1) -> int:
	var dst := as_inventory(other)
	if dst == null:
		return 0
	var src := inv.slot(slot_index)
	if src.is_empty():
		return 0
	var take := src.count if amount < 0 else mini(amount, src.count)
	var moving := inv.take_from_slot(slot_index, take)
	var offered := moving.count
	var left := dst.add(moving)
	if left > 0:
		# Refused: put the remainder back where it came from.
		if inv.slot(slot_index).is_empty():
			inv.set_slot(slot_index, moving)
		else:
			inv.add(moving)
	return offered - left


## Move everything this container holds into `other`. Returns items moved.
func transfer_all_to(other: Variant) -> int:
	return move_all(self, other, false)


## Push every stack `other` will accept (per its filters) from here into it.
## This is the "dump my ore into the refinery" button.
func deposit_all_matching(other: Variant) -> int:
	return move_all(self, other, false)


## Classic quick-stack: move only items that `other` [b]already contains[/b],
## topping its stacks off and leaving anything new behind.
func quick_stack_into(other: Variant) -> int:
	return move_all(self, other, true)


## Pull everything from `other` into this container ("take all" button).
func take_all_from(other: Variant) -> int:
	return move_all(other, self, false)


## Bulk move helper that works between any two of Inventory / ItemContainer.
## With `only_existing`, a stack is moved only when the destination already
## holds that item id. Returns the number of items moved.
static func move_all(from: Variant, to: Variant, only_existing: bool = false) -> int:
	var src := as_inventory(from)
	var dst := as_inventory(to)
	if src == null or dst == null or src == dst:
		return 0
	var moved := 0
	src.begin_batch()
	dst.begin_batch()
	for i in src.size:
		var s := src.slot(i)
		if s.is_empty():
			continue
		if only_existing and dst.count_of(s.id) <= 0:
			continue
		if not dst.accepts(s):
			continue
		var before := s.count
		dst.add(s)
		moved += before - s.count
		if s.is_empty():
			src.set_slot(i, null)
	src.end_batch()
	dst.end_batch()
	if moved > 0:
		Events.play_sound.emit(&"item_transfer", Vector3.ZERO)
	return moved


# ============================================================ serialisation ====
func to_dict() -> Dictionary:
	return {
		"id": String(id), "name": display_name,
		"locked": locked, "owner": owner_id,
		"inv": inv.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	id = StringName(d.get("id", id))
	display_name = String(d.get("name", display_name))
	locked = bool(d.get("locked", false))
	owner_id = String(d.get("owner", ""))
	inv.from_dict(d.get("inv", {}))
	if id != &"":
		_registry[id] = self


# ================================================================= registry ====
## Look up a live container by id, or null.
static func find(p_id: StringName) -> ItemContainer:
	return _registry.get(p_id)


## Look up a container, creating it on first use. The canonical way for an
## object node to get its storage back after a chunk reload.
static func get_or_create(p_id: StringName, p_capacity: int = DEFAULT_CAPACITY, p_display: String = "") -> ItemContainer:
	var c: ItemContainer = _registry.get(p_id)
	if c != null:
		return c
	return ItemContainer.new(p_id, p_capacity, p_display)


static func has_container(p_id: StringName) -> bool:
	return _registry.has(p_id)


## Forget a container (the chest was mined). Does not spill its contents —
## call `transfer_all_to` or spawn drops first.
static func release(p_id: StringName) -> void:
	_registry.erase(p_id)


static func all_containers() -> Array[ItemContainer]:
	var out: Array[ItemContainer] = []
	for k: StringName in _registry:
		out.append(_registry[k])
	return out


## Every persistent container, keyed by id. For the save system.
static func save_all() -> Dictionary:
	var out: Dictionary = {}
	for k: StringName in _registry:
		var c: ItemContainer = _registry[k]
		if c.persistent:
			out[String(k)] = c.to_dict()
	return out


static func load_all(d: Dictionary) -> void:
	for k: Variant in d:
		var entry: Dictionary = d[k]
		var c := get_or_create(StringName(k))
		c.from_dict(entry)


## Wipe the registry — called when leaving a planet / starting a new run.
static func clear_all() -> void:
	_registry.clear()
