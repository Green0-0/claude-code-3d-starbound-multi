## Sells tools and weapons, and — the reason to keep coming back — upgrades what
## you already carry. An upgrade raises an item's tier band by rewriting the
## instance data on the stack, so it works on procedurally generated weapons the
## combat agent invents later without this file knowing anything about them.
class_name NpcRoleBlacksmith
extends NpcRole

const STOCK_KINDS: Array[int] = [ItemType.Kind.TOOL, ItemType.Kind.WEAPON, ItemType.Kind.ARMOR]

## Ore/bar item ids the smith will accept as upgrade material, best first. The
## first one the registry actually knows about is used.
const MATERIAL_LADDER: Array[StringName] = [
	&"durasteel_bar", &"titanium_bar", &"tungsten_bar", &"silver_bar",
	&"gold_bar", &"iron_bar", &"copper_bar", &"cobblestone",
]


func id() -> StringName:
	return &"blacksmith"


func display() -> String:
	return "Blacksmith"


func configure(npc: Node) -> void:
	npc.set(&"shop_kinds", STOCK_KINDS)
	npc.set(&"shop_size", 8)
	npc.set(&"max_health", 130.0)
	npc.set(&"can_offer_quests", true)


func schedule() -> Array[Dictionary]:
	return [
		{"from": 0.89, "to": 0.24, "activity": ACT_SLEEP},
		{"from": 0.24, "to": 0.70, "activity": ACT_WORK},
		{"from": 0.70, "to": 0.82, "activity": ACT_SOCIALISE},
		{"from": 0.82, "to": 0.89, "activity": ACT_WANDER},
	]


func dialogue_tree(_npc: Node) -> String:
	return "blacksmith_default"


func toughness() -> float:
	return 1.4


func greetings() -> PackedStringArray:
	return PackedStringArray([
		"Bring me metal and I'll bring you murder.",
		"That blade of yours is crying out for attention.",
		"Hot work. Stand back from the quench.",
		"Anything can be improved. Anything.",
		"I don't do pretty. I do sharp.",
	])


# =========================================================================
#  Upgrades
# =========================================================================
## The material this smith wants for an upgrade, and how much.
static func upgrade_material() -> StringName:
	for m: StringName in MATERIAL_LADDER:
		if Items.has(m):
			return m
	return &""


static func upgrade_cost(level: int) -> int:
	return 120 + level * 180


static func upgrade_material_cost(level: int) -> int:
	return 2 + level * 2


## Reads the current upgrade level stamped on a stack.
static func level_of(stack: ItemStack) -> int:
	return int(stack.data.get("upgrade_level", 0)) if stack != null else 0


## Applies one upgrade to [param stack]: +18% damage, +12% mining power, +1 tool
## tier every second level, and a rarity bump at level 3. Returns false when the
## player cannot pay or the item cannot be improved.
static func upgrade(npc: Node, stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false
	var t := stack.type()
	if t == null or (t.kind != ItemType.Kind.WEAPON and t.kind != ItemType.Kind.TOOL
			and t.kind != ItemType.Kind.ARMOR):
		Events.toast("That isn't something I can work.", "warn")
		return false
	var level := level_of(stack)
	if level >= 5:
		Events.toast("That's as far as it goes. Any hotter and it cracks.", "warn")
		return false

	var mat := upgrade_material()
	var mat_count := upgrade_material_cost(level)
	if mat != &"" and NpcInventoryBridge.count_of(mat) < mat_count:
		Events.toast("Bring me %d %s first." % [mat_count, Items.display_name(mat)], "warn")
		return false
	var cost := upgrade_cost(level)
	if not NpcInventoryBridge.spend_pixels(cost):
		Events.toast("That's %d pixels. Come back when you have them." % cost, "warn")
		return false
	if mat != &"":
		NpcInventoryBridge.take(mat, mat_count)

	stack.data["upgrade_level"] = level + 1
	stack.data["name"] = "%s +%d" % [t.display_name, level + 1]
	if t.damage > 0.0:
		stack.data["damage"] = float(stack.stat("damage", t.damage)) * 1.18
	if t.tool_power > 0.0:
		stack.data["tool_power"] = float(stack.stat("tool_power", t.tool_power)) * 1.12
	if t.defense > 0.0:
		stack.data["defense"] = float(stack.stat("defense", t.defense)) * 1.15
	if (level + 1) % 2 == 0:
		stack.data["tool_tier"] = int(stack.stat("tool_tier", t.tool_tier)) + 1
	if stack.data.has("max_durability"):
		var md := int(stack.data["max_durability"]) + 60
		stack.data["max_durability"] = md
		stack.data["durability"] = md
	if level + 1 >= 3:
		stack.data["rarity"] = maxi(int(stack.rarity()), Const.RARITY_RARE)

	if npc != null:
		NpcReputation.adjust_npc(StringName(npc.get("npc_id")), 2.0)
		var n3 := npc as Node3D
		Events.play_sound.emit(&"forge", n3.global_position if n3 != null else Vector3.ZERO)
		Events.spawn_particles.emit(&"sparks", n3.global_position if n3 != null else Vector3.ZERO, 24)
	Events.inventory_changed.emit()
	Events.toast("%s upgraded to +%d." % [t.display_name, level + 1], "good")
	return true
