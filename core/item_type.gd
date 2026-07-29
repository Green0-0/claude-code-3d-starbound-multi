## Definition of one kind of item. Mirrors BlockType's fluent style.
class_name ItemType
extends RefCounted

enum Kind {
	MATERIAL,   ## crafting ingredient / ore / bar
	BLOCK,      ## places a voxel
	TOOL,       ## pickaxe, axe, matter manipulator
	WEAPON,     ## melee or ranged
	ARMOR,      ## head / chest / legs
	CONSUMABLE, ## food, potion
	OBJECT,     ## placeable furniture / machine
	TECH,       ## grants a tech module
	SEED,
	AUGMENT,    ## slotted upgrade
	QUEST,
	CURRENCY,
}

const SLOT_HEAD := &"head"
const SLOT_CHEST := &"chest"
const SLOT_LEGS := &"legs"
const SLOT_BACK := &"back"

var id: StringName = &""
var display_name: String = "Item"
var description: String = ""
var kind: Kind = Kind.MATERIAL
var stack_size: int = 1000
var rarity: int = Const.RARITY_COMMON
var value: int = 1                    ## pixels (currency) when sold
var icon_color: Color = Color(0.7, 0.7, 0.7)
var icon_shape: StringName = &"square"  ## drawn procedurally by the UI
var category: StringName = &"materials"
var tags: Array[StringName] = []

# --- kind-specific -----------------------------------------------------------
var places_block: StringName = &""     ## Kind.BLOCK
var places_object: String = ""         ## Kind.OBJECT — scene path
var tool_kind: StringName = &""        ## &"pickaxe" / &"axe" / &"shovel" / &"beam"
var tool_tier: int = 0
var tool_power: float = 1.0            ## mining speed multiplier
var tool_range: float = 5.0
var damage: float = 0.0
var element: String = Const.ELEM_PHYSICAL
var attack_speed: float = 1.0
var knockback: float = 4.0
var two_handed: bool = false
var projectile: StringName = &""       ## Kind.WEAPON, ranged
var energy_cost: float = 0.0
var armor_slot: StringName = &""
var defense: float = 0.0
var stat_bonuses: Dictionary = {}      ## {"max_health": 10.0, ...}
var food: float = 0.0
var heal: float = 0.0
var effects: Array = []                ## [{"id": StringName, "duration": float}]
var seed_crop: StringName = &""
var tech_id: StringName = &""

## on_use(player: Node, ctx: Dictionary) -> bool ; return true if consumed.
var on_use: Callable = Callable()


func _init(p_id: StringName, p_display: String = "") -> void:
	id = p_id
	display_name = p_display if p_display != "" else String(p_id).capitalize()


func of_kind(k: Kind) -> ItemType:
	kind = k
	match k:
		Kind.TOOL, Kind.WEAPON, Kind.ARMOR:
			stack_size = 1
		Kind.OBJECT:
			stack_size = 100
	return self


func look(c: Color, shape: StringName = &"square") -> ItemType:
	icon_color = c
	icon_shape = shape
	return self


func describe(text: String) -> ItemType:
	description = text
	return self


func worth(v: int, r: int = -1) -> ItemType:
	value = v
	if r >= 0:
		rarity = r
	return self


func stacks(n: int) -> ItemType:
	stack_size = n
	return self


func places(block: StringName) -> ItemType:
	kind = Kind.BLOCK
	places_block = block
	stack_size = 1000
	return self


func as_tool(t_kind: StringName, tier: int, power: float, p_range: float = 5.0) -> ItemType:
	kind = Kind.TOOL
	tool_kind = t_kind
	tool_tier = tier
	tool_power = power
	tool_range = p_range
	stack_size = 1
	return self


func as_weapon(dmg: float, speed: float = 1.0, elem: String = Const.ELEM_PHYSICAL) -> ItemType:
	kind = Kind.WEAPON
	damage = dmg
	attack_speed = speed
	element = elem
	stack_size = 1
	return self


func as_armor(slot: StringName, def: float) -> ItemType:
	kind = Kind.ARMOR
	armor_slot = slot
	defense = def
	stack_size = 1
	return self


func as_food(f: float, h: float = 0.0) -> ItemType:
	kind = Kind.CONSUMABLE
	food = f
	heal = h
	stack_size = 50
	return self


func with_effect(eid: StringName, duration: float) -> ItemType:
	effects.append({"id": eid, "duration": duration})
	return self


func bonus(stat: String, amount: float) -> ItemType:
	stat_bonuses[stat] = amount
	return self


func in_category(c: StringName) -> ItemType:
	category = c
	return self


func tag(t: StringName) -> ItemType:
	if not tags.has(t):
		tags.append(t)
	return self


func has_tag(t: StringName) -> bool:
	return tags.has(t)


func flags(p: Dictionary) -> ItemType:
	for k: String in p:
		if k in self:
			set(k, p[k])
		else:
			push_warning("ItemType '%s': unknown flag '%s'" % [id, k])
	return self


func rarity_color() -> Color:
	return Const.RARITY_COLORS[clampi(rarity, 0, Const.RARITY_COLORS.size() - 1)]
