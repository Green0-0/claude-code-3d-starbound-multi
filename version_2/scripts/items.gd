class_name Items
extends RefCounted

## The item registry, and the stack type that moves items around.
##
## Every block automatically gets a placer item with the same StringName unless
## a content file claimed the id first, so `Blocks` and `Items` share one
## namespace and a block can always be picked up, carried and put back down.
##
## Icons are synthesised on demand from `(shape, colour)` and cached, so 400
## items cost 400 tiny textures only if you actually look at all of them.

enum Kind {
	MATERIAL, BLOCK, TOOL, WEAPON, ARMOR, CONSUMABLE,
	OBJECT, TECH, SEED, AUGMENT, QUEST, CURRENCY,
}

const RARITY_COMMON := 0
const RARITY_UNCOMMON := 1
const RARITY_RARE := 2
const RARITY_LEGENDARY := 3
const RARITY_ESSENTIAL := 4

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Legendary", "Essential"]
const RARITY_COLORS := [
	Color(0.80, 0.80, 0.84),
	Color(0.44, 0.86, 0.48),
	Color(0.40, 0.66, 0.98),
	Color(0.88, 0.60, 0.24),
	Color(0.94, 0.42, 0.86),
]

const SLOT_HEAD := &"head"
const SLOT_CHEST := &"chest"
const SLOT_LEGS := &"legs"
const ARMOR_SLOTS := [SLOT_HEAD, SLOT_CHEST, SLOT_LEGS]


# =============================================================================
# one item type
# =============================================================================

class Type extends RefCounted:
	var id: StringName = &""
	var display := ""
	var description := ""
	var kind: int = Items.Kind.MATERIAL

	var color := Color(0.7, 0.7, 0.75)
	var shape: StringName = &"chunk"
	var value := 1
	var rarity := Items.RARITY_COMMON
	var stack_size := 100
	var category: StringName = &"materials"
	var tags := {}

	var place_block: StringName = &""     ## block placed on right-click

	# tools
	var tool_kind: StringName = &""
	var tool_tier := 0
	var tool_power := 1.0
	var tool_range := 5.0
	var durability := 0                   ## 0 = indestructible

	# weapons
	var damage := 0.0
	var attack_speed := 1.0
	var element: StringName = Blocks.ELEM_PHYSICAL
	var projectile: StringName = &""
	var energy_cost := 0.0
	var knockback := 4.0
	var two_handed := false

	# armour
	var armor_slot: StringName = &""
	var defense := 0.0

	# consumables
	var food := 0.0
	var heal := 0.0
	var effects: Array = []               ## [[effect_id, seconds], ...]

	var stat_bonuses := {}
	var tech_id: StringName = &""
	var seed_crop: StringName = &""

	var _icon: ImageTexture = null

	# --- fluent builders -----------------------------------------------------

	func of_kind(k: int) -> Type:
		kind = k
		if k == Items.Kind.TOOL or k == Items.Kind.WEAPON or k == Items.Kind.ARMOR:
			stack_size = 1
		return self

	func look(c: Color, s: StringName) -> Type:
		color = c
		shape = s
		return self

	func describe(text: String) -> Type:
		description = text
		return self

	func worth(v: int, r := Items.RARITY_COMMON) -> Type:
		value = v
		rarity = r
		return self

	func stacks(n: int) -> Type:
		stack_size = n
		return self

	func places(block: StringName) -> Type:
		place_block = block
		kind = Items.Kind.BLOCK
		return self

	func as_tool(kind_name: StringName, tier: int, power: float, reach: float) -> Type:
		of_kind(Items.Kind.TOOL)
		tool_kind = kind_name
		tool_tier = tier
		tool_power = power
		tool_range = reach
		return self

	func as_weapon(dmg: float, speed: float, elem: StringName = Blocks.ELEM_PHYSICAL) -> Type:
		of_kind(Items.Kind.WEAPON)
		damage = dmg
		attack_speed = speed
		element = elem
		return self

	func as_armor(slot: StringName, def: float) -> Type:
		of_kind(Items.Kind.ARMOR)
		armor_slot = slot
		defense = def
		return self

	func as_food(f: float, h: float) -> Type:
		of_kind(Items.Kind.CONSUMABLE)
		food = f
		heal = h
		return self

	func with_effect(effect_id: StringName, seconds: float) -> Type:
		effects.append([effect_id, seconds])
		return self

	func bonus(stat: String, amount: float) -> Type:
		stat_bonuses[stat] = float(stat_bonuses.get(stat, 0.0)) + amount
		return self

	func lasts(hits: int) -> Type:
		durability = hits
		return self

	func in_category(c: StringName) -> Type:
		category = c
		return self

	func tag(t: StringName) -> Type:
		tags[t] = true
		return self

	func has_tag(t: StringName) -> bool:
		return tags.has(t)

	func flags(d: Dictionary) -> Type:
		for k: String in d:
			match k:
				"projectile": projectile = StringName(d[k])
				"energy_cost": energy_cost = float(d[k])
				"knockback": knockback = float(d[k])
				"two_handed": two_handed = bool(d[k])
				"tool_tier": tool_tier = int(d[k])
				"stack_size": stack_size = int(d[k])
				"durability": durability = int(d[k])
				_: push_warning("Items: unknown flag '%s' on %s" % [k, id])
		return self

	func rarity_color() -> Color:
		return Items.RARITY_COLORS[clampi(rarity, 0, 4)]

	## Lazily synthesised 16px icon, cached for the life of the run.
	func icon() -> ImageTexture:
		if _icon == null:
			_icon = TexGen.build_item_icon(shape, color)
		return _icon


# =============================================================================
# one stack of items
# =============================================================================

class Stack extends RefCounted:
	var id: StringName = &""
	var count := 0
	var data := {}      ## per-stack state: durability, generated weapon rolls

	func _init(p_id: StringName = &"", p_count := 0, p_data := {}) -> void:
		id = p_id
		count = p_count
		data = p_data.duplicate(true)

	func is_empty() -> bool:
		return id == &"" or count <= 0

	func type() -> Type:
		return Items.get_type(id)

	func max_stack() -> int:
		var t := type()
		return t.stack_size if t != null else 1

	func display_name() -> String:
		if data.has("name"):
			return String(data["name"])
		var t := type()
		return t.display if t != null else String(id)

	func rarity() -> int:
		if data.has("rarity"):
			return int(data["rarity"])
		var t := type()
		return t.rarity if t != null else 0

	## Prefer a per-stack roll over the item type's default.
	func stat(key: String, fallback: Variant = 0.0) -> Variant:
		if data.has(key):
			return data[key]
		var t := type()
		if t == null:
			return fallback
		match key:
			"damage": return t.damage
			"attack_speed": return t.attack_speed
			"element": return t.element
			"defense": return t.defense
			"tool_power": return t.tool_power
			"tool_tier": return t.tool_tier
			"knockback": return t.knockback
			"energy_cost": return t.energy_cost
			"projectile": return t.projectile
		return t.stat_bonuses.get(key, fallback)

	func can_merge_with(other: Stack) -> bool:
		if is_empty() or other.is_empty():
			return true
		return id == other.id and data == other.data and count < max_stack()

	## Pour `other` into this stack; returns how many actually moved.
	func merge_from(other: Stack) -> int:
		if other.is_empty():
			return 0
		if is_empty():
			id = other.id
			data = other.data.duplicate(true)
			count = 0
		elif id != other.id or data != other.data:
			return 0
		var room := max_stack() - count
		var moved := mini(room, other.count)
		count += moved
		other.count -= moved
		if other.count <= 0:
			other.clear()
		return moved

	func split(n: int) -> Stack:
		var taken := mini(n, count)
		count -= taken
		var out := Stack.new(id, taken, data)
		if count <= 0:
			clear()
		return out

	func clear() -> void:
		id = &""
		count = 0
		data = {}

	func duplicate_stack() -> Stack:
		return Stack.new(id, count, data)

	func durability() -> int:
		if data.has("durability"):
			return int(data["durability"])
		var t := type()
		return t.durability if t != null else 0

	## Wear the tool by `n`. Returns true when it broke.
	func damage_durability(n: int) -> bool:
		var t := type()
		if t == null or t.durability <= 0:
			return false
		var left := durability() - n
		data["durability"] = maxi(left, 0)
		if left <= 0:
			clear()
			return true
		return false

	func to_dict() -> Dictionary:
		return {"id": String(id), "n": count, "d": data}

	static func from_dict(d: Dictionary) -> Stack:
		return Stack.new(StringName(d.get("id", "")), int(d.get("n", 0)), d.get("d", {}))


# =============================================================================
# registry
# =============================================================================

static var types: Array[Type] = []
static var by_id := {}
static var _booted := false

const CONTENT := [
	"res://scripts/content/itm_materials.gd",
	"res://scripts/content/itm_tools.gd",
	"res://scripts/content/itm_weapons.gd",
	"res://scripts/content/itm_armor.gd",
	"res://scripts/content/itm_food.gd",
	"res://scripts/content/itm_misc.gd",
]


static func boot() -> void:
	if _booted:
		return
	_booted = true
	Blocks.boot()
	for path: String in CONTENT:
		var script: GDScript = load(path)
		script.register_all()
	_auto_block_items()


static func define(p_id: StringName, display: String) -> Type:
	var existing: Type = by_id.get(p_id)
	if existing != null:
		return existing
	var t := Type.new()
	t.id = p_id
	t.display = display
	types.append(t)
	by_id[p_id] = t
	return t


static func has(p_id: StringName) -> bool:
	return by_id.has(p_id)


static func get_type(p_id: StringName) -> Type:
	return by_id.get(p_id)


static func make(p_id: StringName, count := 1) -> Stack:
	var t: Type = by_id.get(p_id)
	if t == null:
		return Stack.new()
	var data := {}
	if t.durability > 0:
		data["durability"] = t.durability
	return Stack.new(p_id, count, data)


static func count() -> int:
	return types.size()


static func all_of_kind(k: int) -> Array[Type]:
	var out: Array[Type] = []
	for t: Type in types:
		if t.kind == k:
			out.append(t)
	return out


static func all_with_tag(tag: StringName) -> Array[Type]:
	var out: Array[Type] = []
	for t: Type in types:
		if t.tags.has(tag):
			out.append(t)
	return out


static func all_in_category(c: StringName) -> Array[Type]:
	var out: Array[Type] = []
	for t: Type in types:
		if t.category == c:
			out.append(t)
	return out


## The item a block yields when it has no explicit drop list — its own placer.
static func item_of_block(block_id: int) -> StringName:
	var want := Blocks.item_of(block_id)
	return want if by_id.has(want) else &""


## The block a stack would place, or AIR.
static func block_for(p_id: StringName) -> int:
	var t: Type = by_id.get(p_id)
	if t == null or t.place_block == &"":
		return Blocks.AIR
	return Blocks.id(t.place_block)


## Every block that no content file already claimed gets a placer item, so
## anything you can mine is automatically something you can carry and put back.
static func _auto_block_items() -> void:
	for d: Blocks.Def in Blocks.defs:
		if d.id == Blocks.AIR:
			continue
		var want: StringName = d.item if d.item != &"" else d.name
		if by_id.has(want):
			# A content item owns the name; still point it at the block if it is
			# a plain material with nowhere else to go.
			var existing: Type = by_id[want]
			if existing.place_block == &"" and existing.kind == Kind.MATERIAL:
				existing.place_block = d.name
				existing.kind = Kind.BLOCK
			continue
		var t := define(want, d.display)
		t.of_kind(Kind.BLOCK)
		t.place_block = d.name
		t.look(d.color, _shape_for_block(d))
		t.describe(d.description if d.description != "" else _auto_blurb(d))
		t.worth(maxi(1, int(d.hardness * 4.0) + 1))
		t.stacks(200)
		t.in_category(d.category)
		t.tag(&"block")
		for tg: StringName in d.tags:
			t.tag(tg)


static func _shape_for_block(d: Blocks.Def) -> StringName:
	match d.render:
		Blocks.Render.CROSS:
			return &"sprig"
		Blocks.Render.LIQUID:
			return &"flask"
		Blocks.Render.TRANSPARENT:
			return &"pane"
	if d.tags.has(&"ore"):
		return &"ore_cube"
	return &"cube"


static func _auto_blurb(d: Blocks.Def) -> String:
	if d.tags.has(&"ore"):
		return "%s, still in the rock. Mine it for what it holds." % d.display
	if d.category == &"building":
		return "A block of %s, ready to build with." % d.display.to_lower()
	if d.category == &"light":
		return "%s. Placed, it holds back the dark." % d.display
	return "A block of %s." % d.display.to_lower()
