## Scene glue between the player node and the [Inventory] model.
##
## `player.gd` looks for `res://inventory/inventory.tscn` on `_ready` and, if it
## finds it, adds it as a child and calls `set_inventory(<this node>)`. This
## node therefore does two things:
##
## [br]1. It hands the player the [b]real[/b] model one idle frame later, so
##    `Game.player.inventory` ends up being an actual [Inventory] — which is
##    what `docs/ARCHITECTURE.md` promises and what every other module casts to.
## [br]2. Until (and in case) that swap does not happen, it forwards the whole
##    inventory API itself, so a caller holding this node still works. Property
##    reads (`selected_slot`, `size`, ...) are forwarded through [method _get].
##
## It also carries the [PickupMagnet] tuning node, so item magnetism is live
## as soon as the player exists.
extends Node

## The model. This is the object that ends up at `Game.player.inventory`.
var model: Inventory = Inventory.new()


func _ready() -> void:
	name = "PlayerInventory"
	add_to_group(&"inventory")
	# player.set_inventory(self) runs immediately after add_child(); swap the
	# real model in afterwards.
	_install.call_deferred()


func _install() -> void:
	var p := Game.player
	if p == null or not p.has_method(&"set_inventory"):
		return
	if p.get(&"inventory") != model:
		p.call(&"set_inventory", model)


## Forward property reads the HUD and menus perform on the inventory.
func _get(property: StringName) -> Variant:
	match property:
		&"selected_slot", &"selected", &"hotbar_index", &"active_slot":
			return model.selected_slot
		&"size":
			return model.size
		&"hotbar_size":
			return model.hotbar_size
		&"hotbar", &"slots":
			return model.hotbar_stacks()
	return null


# ------------------------------------------------------------------ forwards
func add(stack: ItemStack) -> int: return model.add(stack)
func add_stack(stack: ItemStack) -> int: return model.add(stack)
func add_id(id: StringName, count: int = 1, data: Dictionary = {}) -> int: return model.add_id(id, count, data)
func add_item(id: StringName, count: int = 1, data: Dictionary = {}) -> bool: return model.add_item(id, count, data)
func remove(id: StringName, count: int = 1) -> int: return model.remove(id, count)
func remove_id(id: StringName, count: int = 1) -> int: return model.remove(id, count)
func remove_item(id: StringName, count: int = 1) -> bool: return model.remove_item(id, count)
func remove_stack(id: StringName, count: int = 1) -> int: return model.remove(id, count)
func count_of(id: StringName) -> int: return model.count_of(id)
func has(id: StringName, count: int = 1) -> bool: return model.has(id, count)
func has_item(id: StringName, count: int = 1) -> bool: return model.has(id, count)
func has_all(req: Dictionary) -> bool: return model.has_all(req)
func consume(req: Dictionary) -> bool: return model.consume(req)
func consume_selected(n: int = 1) -> bool: return model.consume_selected(n)
func contents() -> Dictionary: return model.contents()
func slot(i: int) -> ItemStack: return model.slot(i)
func get_slot(i: int) -> ItemStack: return model.slot(i)
func set_slot(i: int, stack: ItemStack) -> void: model.set_slot(i, stack)
func take_from_slot(i: int, count: int = -1) -> ItemStack: return model.take_from_slot(i, count)
func swap(a: int, b: int) -> void: model.swap(a, b)
func split_to(from: int, to: int, n: int = 0) -> int: return model.split_to(from, to, n)
func quick_move(i: int) -> int: return model.quick_move(i)
func first_empty() -> int: return model.first_empty()
func all_stacks() -> Array[ItemStack]: return model.all_stacks()
func sort(include_hotbar: bool = false) -> void: model.sort(include_hotbar)
func clear() -> void: model.clear()
func hotbar_stacks() -> Array: return model.hotbar_stacks()
func selected() -> ItemStack: return model.selected()
func selected_stack() -> ItemStack: return model.selected()
func select(i: int) -> void: model.select(i)
func equipped(slot_name: StringName) -> ItemStack: return model.equipped(slot_name)
func equip(slot_name: StringName, stack: ItemStack) -> ItemStack: return model.equip(slot_name, stack)
func total_defense() -> float: return model.total_defense()
func total_resistance(element: String) -> float: return model.total_resistance(element)
func stat_bonus(stat_name: String) -> float: return model.stat_bonus(stat_name)
func drop_on_death(fraction: float, world_pos: Vector3) -> int: return model.drop_on_death(fraction, world_pos)
func get_currency() -> int: return Pixels.balance()
func add_currency(amount: int) -> void: Pixels.add(amount, "reward")
func spend_currency(amount: int) -> bool: return Pixels.spend(amount)
func to_dict() -> Dictionary: return model.to_dict()
func from_dict(d: Dictionary) -> void: model.from_dict(d)
