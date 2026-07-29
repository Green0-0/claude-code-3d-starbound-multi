## Container objects: chests, safes, lockers, crates.
##
## Storage is delegated to the inventory agent's `ItemContainer` when that file
## exists (`res://inventory/item_container.gd`, probed with `ResourceLoader`).
## Until it lands, the same slots live in a plain Array of `ItemStack` dicts, so
## containers work, save and load with or without it — and the payload format is
## identical either way, which means no migration when it arrives.
class_name ObjContainers
extends RefCounted

const ITEM_CONTAINER_PATH := "res://inventory/item_container.gd"


# ===========================================================================
#  Chest — the generic container
# ===========================================================================
class Chest extends ObjBase:
	var capacity: int = 16
	## Canonical storage when the inventory agent's container is unavailable:
	## an Array of `ItemStack.to_dict()` payloads.
	var slots: Array = []
	## The inventory agent's `ItemContainer`, when present.
	var box: Variant = null

	func on_create() -> void:
		capacity = maxi(1, int(def.get("capacity", 16)))
		_ensure_box()

	func _ensure_box() -> void:
		if box != null:
			return
		if not ResourceLoader.exists(ObjContainers.ITEM_CONTAINER_PATH):
			return
		var scr: Script = load(ObjContainers.ITEM_CONTAINER_PATH) as Script
		if scr == null:
			return
		box = scr.new()
		if box == null:
			return
		if box.has_method(&"configure"):
			box.call(&"configure", {"size": capacity, "title": display_name})
		elif box.has_method(&"resize"):
			box.call(&"resize", capacity)

	## Container UIs and loot rollers both go through this.
	func add_item(item_id: StringName, count: int, data: Dictionary = {}) -> bool:
		if count <= 0:
			return false
		if box != null:
			for m: StringName in [&"add", &"add_item", &"insert"]:
				if box.has_method(m):
					box.call(m, ItemStack.new(item_id, count, data))
					write()
					return true
		if slots.size() >= capacity:
			return false
		slots.append(ItemStack.new(item_id, count, data).to_dict())
		write()
		return true

	## Everything inside, as `[{"item": StringName, "count": int}]`.
	func contents() -> Array:
		var out: Array = []
		if box != null and box.has_method(&"all_stacks"):
			for s: Variant in box.call(&"all_stacks"):
				if s is ItemStack and not (s as ItemStack).is_empty():
					out.append({"item": (s as ItemStack).id, "count": (s as ItemStack).count})
			return out
		for d: Dictionary in slots:
			if int(d.get("count", 0)) > 0:
				out.append({"item": StringName(d.get("id", "")), "count": int(d.get("count", 0))})
		return out

	func is_empty() -> bool:
		return contents().is_empty()

	func on_interact(player: Node) -> bool:
		if not _unlock_check(player):
			return true
		# Structure chests roll their loot the first time they are opened.
		if manager != null and manager.has_method(&"fill_loot"):
			manager.call(&"fill_loot", self)
		set_st("open", true, true)
		write()
		sound(&"chest_open")
		particles(&"chest_open", 4)
		UI.open("container", {
			"title": display_name, "object": self, "container": box,
			"capacity": capacity, "pos": [pos.x, pos.y, pos.z],
		})
		Events.ui_panel_opened.emit("container")
		return true

	## Overridden by `Safe`.
	func _unlock_check(_player: Node) -> bool:
		return true

	func on_removed() -> Array:
		return contents()

	func save_extra() -> Dictionary:
		if box != null and box.has_method(&"save_state"):
			return {"inv": box.call(&"save_state")}
		return {"inv": slots.duplicate(true)}

	func load_extra(d: Dictionary) -> void:
		var inv: Variant = d.get("inv", [])
		if box != null and box.has_method(&"load_state") and inv is Dictionary:
			box.call(&"load_state", inv)
		elif inv is Array:
			slots = (inv as Array).duplicate(true)

	func build_visual() -> Node3D:
		return null


# ===========================================================================
#  Safe — a chest that wants a key
# ===========================================================================
class Safe extends Chest:
	func on_create() -> void:
		super.on_create()
		if not state.has("locked"):
			state["locked"] = false
		if not state.has("key"):
			state["key"] = ""

	func _unlock_check(player: Node) -> bool:
		if not bool(st("locked", false)):
			return true
		var key := String(st("key", ""))
		if key == "":
			state["locked"] = false
			write()
			return true
		var inv: Variant = player.get("inventory") if player != null else null
		var have := false
		if inv != null and inv.has_method(&"count_of"):
			have = int(inv.call(&"count_of", StringName(key))) > 0
		if not have:
			Events.toast("Locked. You need a %s." % Items.display_name(StringName(key)), "warn")
			sound(&"locked")
			return false
		state["locked"] = false
		write()
		Events.toast("Unlocked.", "info")
		sound(&"unlock")
		return true


# ===========================================================================
#  Refrigerated container — food inside does not spoil
# ===========================================================================
class Fridge extends Chest:
	func on_create() -> void:
		super.on_create()
		state["preserves"] = true

	func on_interact(player: Node) -> bool:
		var ok := super.on_interact(player)
		if ok:
			Events.toast("Contents preserved.", "info")
		return ok


# ===========================================================================
#  Registration
# ===========================================================================
static func register_all() -> void:
	var wood := Color(0.52, 0.36, 0.20)
	_chest(&"chest_wood", "Wooden Chest", wood, BlockType.Pattern.PLANK, 16, 1.0, 25, &"step_wood")
	_chest(&"chest_stone", "Stone Chest", Color(0.46, 0.46, 0.50), BlockType.Pattern.BRICK, 16, 1.8, 30, &"step_stone")
	_chest(&"chest_iron", "Iron Chest", Color(0.62, 0.63, 0.66), BlockType.Pattern.METAL, 24, 2.4, 90, &"step_metal")
	_chest(&"chest_titanium", "Titanium Chest", Color(0.72, 0.76, 0.80), BlockType.Pattern.METAL, 32, 3.2, 220, &"step_metal")
	_chest(&"chest_durasteel", "Durasteel Chest", Color(0.55, 0.60, 0.68), BlockType.Pattern.METAL, 40, 4.0, 420, &"step_metal")
	_chest(&"storage_pod", "Storage Pod", Color(0.40, 0.52, 0.62), BlockType.Pattern.CIRCUIT, 48, 4.5, 700, &"step_metal")
	_chest(&"locker", "Steel Locker", Color(0.50, 0.54, 0.58), BlockType.Pattern.METAL, 30, 2.6, 110, &"step_metal")
	_chest(&"shipping_crate", "Shipping Crate", Color(0.60, 0.48, 0.26), BlockType.Pattern.PLANK, 20, 1.4, 45, &"step_wood")
	_chest(&"barrel", "Barrel", Color(0.44, 0.31, 0.18), BlockType.Pattern.PLANK, 12, 1.0, 20, &"step_wood")

	ObjRegistry.define(&"safe", "Safe", &"container", Safe, {
		"color": Color(0.34, 0.36, 0.40), "pattern": BlockType.Pattern.METAL,
		"hardness": 6.0, "tool": &"pickaxe", "tier": 2, "step": &"step_metal",
		"capacity": 12, "value": 320, "rarity": Const.RARITY_UNCOMMON,
		"category": &"objects", "tags": [&"container", &"lockable"],
		"desc": "Reinforced storage. Structure safes need the matching key.",
	})
	ObjRegistry.define(&"mini_fridge", "Mini Fridge", &"container", Fridge, {
		"color": Color(0.80, 0.82, 0.84), "pattern": BlockType.Pattern.METAL,
		"hardness": 2.2, "step": &"step_metal", "capacity": 16,
		"value": 150, "category": &"objects", "tags": [&"container", &"food"],
		"desc": "Keeps perishables edible indefinitely.",
	})


static func _chest(p_id: StringName, display: String, col: Color, pat: int,
		cap: int, hardness: float, value: int, step: StringName) -> void:
	ObjRegistry.define(p_id, display, &"container", Chest, {
		"color": col, "pattern": pat, "hardness": hardness, "step": step,
		"capacity": cap, "value": value, "category": &"objects",
		"tags": [&"container"],
		"desc": "Stores %d stacks. Contents travel with the chunk." % cap,
	})
