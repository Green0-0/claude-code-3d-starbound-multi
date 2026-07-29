## Turns an [ItemStack] into the BBCode shown in its hover tooltip.
##
## Everything is read through [method ItemStack.stat] so procedurally rolled
## weapons (whose numbers live in `data` rather than on the [ItemType]) display
## their real values, and every lookup falls back gracefully when the item
## registry has not been populated by the content agents yet.
class_name MenuTooltip
extends RefCounted

const KIND_NAMES := {
	ItemType.Kind.MATERIAL: "Material",
	ItemType.Kind.BLOCK: "Block",
	ItemType.Kind.TOOL: "Tool",
	ItemType.Kind.WEAPON: "Weapon",
	ItemType.Kind.ARMOR: "Armor",
	ItemType.Kind.CONSUMABLE: "Consumable",
	ItemType.Kind.OBJECT: "Object",
	ItemType.Kind.TECH: "Tech",
	ItemType.Kind.SEED: "Seed",
	ItemType.Kind.AUGMENT: "Augment",
	ItemType.Kind.QUEST: "Quest Item",
	ItemType.Kind.CURRENCY: "Currency",
}


## Full item card: name, rarity/kind line, stats, description, value.
static func for_stack(stack: ItemStack) -> String:
	if stack == null or stack.is_empty():
		return ""
	var ty := stack.type()
	var rarity := stack.rarity()
	var rc := MenuTheme.rarity_color(rarity)
	var out := PackedStringArray()

	out.append("[b][color=#%s]%s[/color][/b]" % [rc.to_html(false), stack.display_name()])

	var sub := MenuTheme.rarity_name(rarity)
	if ty != null:
		sub += "  ·  " + String(KIND_NAMES.get(ty.kind, "Item"))
	if stack.count > 1:
		sub += "  ·  x%d" % stack.count
	out.append("[color=#%s][font_size=12]%s[/font_size][/color]" % [MenuTheme.TEXT_MUTE.to_html(false), sub])

	var stats := stat_lines(stack)
	if not stats.is_empty():
		out.append("")
		for line: String in stats:
			out.append(line)

	if ty != null and ty.description != "":
		out.append("")
		out.append("[color=#%s][i]%s[/i][/color]" % [MenuTheme.TEXT_DIM.to_html(false), ty.description])

	var footer := PackedStringArray()
	var dur := stack.durability()
	if dur >= 0 and stack.max_durability() > 0:
		footer.append("Durability %d / %d" % [dur, stack.max_durability()])
	if ty != null and ty.value > 0:
		footer.append("%s px" % MenuWidgets.short_number(ty.value))
	if ty != null and ty.stack_size > 1:
		footer.append("Stacks to %d" % ty.stack_size)
	if not footer.is_empty():
		out.append("")
		out.append("[color=#%s][font_size=11]%s[/font_size][/color]"
			% [MenuTheme.TEXT_MUTE.to_html(false), "   ".join(footer)])

	return "\n".join(out)


## Just the numeric block, so panels can reuse it inline (crafting previews,
## the equipment paper-doll, quest reward lists).
static func stat_lines(stack: ItemStack) -> PackedStringArray:
	var out := PackedStringArray()
	if stack == null or stack.is_empty():
		return out
	var ty := stack.type()
	var kind: int = ty.kind if ty != null else ItemType.Kind.MATERIAL

	match kind:
		ItemType.Kind.WEAPON:
			var dmg := float(stack.stat("damage", 0.0))
			var spd := float(stack.stat("attack_speed", 1.0))
			var elem := String(stack.stat("element", Const.ELEM_PHYSICAL))
			out.append(_num("Damage", "%.1f" % dmg, MenuTheme.TEXT))
			out.append(_num("Speed", "%.2f/s" % spd, MenuTheme.TEXT_DIM))
			out.append(_num("DPS", "%.1f" % (dmg * spd), MenuTheme.ACCENT))
			if elem != Const.ELEM_PHYSICAL:
				out.append(_num("Element", elem.capitalize(), MenuTheme.element_color(elem)))
			var kb := float(stack.stat("knockback", 0.0))
			if kb > 0.0:
				out.append(_num("Knockback", "%.1f" % kb, MenuTheme.TEXT_DIM))
		ItemType.Kind.TOOL:
			out.append(_num("Tool", String(stack.stat("tool_kind", &"tool")).capitalize(), MenuTheme.TEXT))
			out.append(_num("Tier", str(int(stack.stat("tool_tier", 0))), MenuTheme.TEXT_DIM))
			out.append(_num("Power", "%.2fx" % float(stack.stat("tool_power", 1.0)), MenuTheme.ACCENT))
			out.append(_num("Range", "%.1f m" % float(stack.stat("tool_range", 5.0)), MenuTheme.TEXT_DIM))
		ItemType.Kind.ARMOR:
			out.append(_num("Slot", String(stack.stat("armor_slot", &"")).capitalize(), MenuTheme.TEXT_DIM))
			out.append(_num("Defense", "%.1f" % float(stack.stat("defense", 0.0)), MenuTheme.CYAN))
		ItemType.Kind.CONSUMABLE:
			var food := float(stack.stat("food", 0.0))
			var heal := float(stack.stat("heal", 0.0))
			if food > 0.0:
				out.append(_num("Food", "+%.0f" % food, MenuTheme.GOOD))
			if heal > 0.0:
				out.append(_num("Heals", "+%.0f" % heal, MenuTheme.GOOD))
		ItemType.Kind.BLOCK:
			out.append(_num("Places", String(stack.stat("places_block", &"—")).capitalize(), MenuTheme.TEXT_DIM))

	var bonuses: Variant = stack.stat("stat_bonuses", {})
	if bonuses is Dictionary:
		for k: String in (bonuses as Dictionary):
			var v := float((bonuses as Dictionary)[k])
			out.append(_num(k.capitalize().replace("_", " "),
				("+%.0f" % v) if v >= 0.0 else ("%.0f" % v),
				MenuTheme.GOOD if v >= 0.0 else MenuTheme.BAD))

	var effects: Variant = stack.stat("effects", [])
	if effects is Array:
		for e: Variant in (effects as Array):
			if e is Dictionary:
				out.append(_num("Effect", "%s (%.0fs)"
					% [String((e as Dictionary).get("id", "?")).capitalize(),
						float((e as Dictionary).get("duration", 0.0))], MenuTheme.VIOLET))
	return out


static func _num(name: String, value: String, tint: Color) -> String:
	return "[color=#%s]%s[/color]  [color=#%s]%s[/color]" % [
		MenuTheme.TEXT_MUTE.to_html(false), name, tint.to_html(false), value]


## One-line summary used by lists that cannot afford a full card.
static func brief(stack: ItemStack) -> String:
	if stack == null or stack.is_empty():
		return ""
	var rc := MenuTheme.rarity_color(stack.rarity())
	return "[color=#%s]%s[/color]%s" % [
		rc.to_html(false), stack.display_name(),
		("  x%d" % stack.count) if stack.count > 1 else ""]
