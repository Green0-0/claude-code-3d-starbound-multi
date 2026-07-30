extends RefCounted

## Tools: the Matter Manipulator, the pickaxe / axe / shovel / drill ladders,
## and the specialists.
##
## The tier ladder mirrors `blk_ores.gd` exactly:
##   0 stone / copper · 1 iron · 2 tungsten · 3 titanium · 4 durasteel
##   5 aegisalt-class · 6 solarium-class
##
## A tool below a block's tier still breaks it but yields nothing —
## `Blocks.Def.roll_drops` gates on the tier before it rolls, so there is no
## special-casing anywhere in the mining code.
##
## `tool_kind` also decides what the primary mouse button does: `beam`,
## `pickaxe`, `axe`, `shovel` and `drill` mine, everything else acts.

## id prefix, display, tier, mining power multiplier, colour
const METALS := [
	{"id": &"stone", "name": "Stone", "tier": 0, "power": 0.8, "color": Color(0.52, 0.52, 0.55)},
	{"id": &"copper", "name": "Copper", "tier": 0, "power": 1.0, "color": Color(0.85, 0.48, 0.24)},
	{"id": &"iron", "name": "Iron", "tier": 1, "power": 1.35, "color": Color(0.76, 0.62, 0.54)},
	{"id": &"tungsten", "name": "Tungsten", "tier": 2, "power": 1.7, "color": Color(0.58, 0.60, 0.64)},
	{"id": &"titanium", "name": "Titanium", "tier": 3, "power": 2.1, "color": Color(0.74, 0.78, 0.82)},
	{"id": &"durasteel", "name": "Durasteel", "tier": 4, "power": 2.6, "color": Color(0.55, 0.60, 0.68)},
	{"id": &"aegisalt", "name": "Aegisalt", "tier": 5, "power": 3.2, "color": Color(0.42, 0.72, 0.68)},
	{"id": &"solarium", "name": "Solarium", "tier": 6, "power": 4.0, "color": Color(0.96, 0.88, 0.42)},
]

## Not every metal makes every tool — the ladders are staggered so each tier has
## one obvious upgrade rather than five.
const PICKAXE_TIERS := [0, 1, 2, 3, 4, 5, 6, 7]
const AXE_TIERS := [0, 1, 2, 4, 5, 7]
const SHOVEL_TIERS := [1, 2, 4, 5]
const DRILL_TIERS := [2, 4, 5, 7]


static func register_all() -> void:
	_manipulator()
	_ladders()
	_specialists()


static func rarity_for(tier: int) -> int:
	if tier >= 6:
		return Items.RARITY_LEGENDARY
	if tier >= 4:
		return Items.RARITY_RARE
	if tier >= 2:
		return Items.RARITY_UNCOMMON
	return Items.RARITY_COMMON


# ===========================================================================
#  The Matter Manipulator
# ===========================================================================
static func _manipulator() -> void:
	Items.define(&"matter_manipulator", "Matter Manipulator") \
		.as_tool(&"beam", 0, 1.0, 60.0) \
		.look(Color(0.55, 0.95, 0.85), &"probe") \
		.worth(0, Items.RARITY_ESSENTIAL).in_category(&"tools") \
		.tag(&"tool").tag(&"essential").tag(&"beam").tag(&"no_sell") \
		.describe("The universal tool. Mines anything at tier 0, never wears out, "
			+ "and is the one thing you are never allowed to lose.")

	Items.define(&"manipulator_module", "Manipulator Module") \
		.look(Color(0.65, 0.9, 1.0), &"chip").worth(600, Items.RARITY_RARE) \
		.stacks(200).in_category(&"tools").tag(&"upgrade").tag(&"module") \
		.describe("Currency for Matter Manipulator upgrades. Spend it at a "
			+ "Manipulator Bench to widen the beam or raise the tier it recovers.")


# ===========================================================================
#  Mining ladders
# ===========================================================================
static func _ladders() -> void:
	for i: int in PICKAXE_TIERS:
		if i < METALS.size():
			_tool(METALS[i], &"pickaxe", "Pickaxe", 1.0, 5.5, 1.0)
	for i: int in AXE_TIERS:
		if i < METALS.size():
			_tool(METALS[i], &"axe", "Axe", 1.15, 5.0, 1.3)
	for i: int in SHOVEL_TIERS:
		if i < METALS.size():
			_tool(METALS[i], &"shovel", "Shovel", 1.4, 5.0, 0.7)
	for i: int in DRILL_TIERS:
		if i < METALS.size():
			_drill(METALS[i])

	_tool({"id": &"wood", "name": "Wooden", "tier": 0, "power": 0.9,
		"color": Color(0.55, 0.40, 0.24)}, &"hoe", "Hoe", 1.0, 4.5, 0.4)
	_tool(METALS[2], &"hoe", "Hoe", 1.5, 5.0, 0.6)


static func _tool(metal: Dictionary, kind: StringName, label: String,
		power_scale: float, reach: float, dmg_scale: float) -> void:
	var id := StringName("%s_%s" % [metal["id"], kind])
	if Items.has(id):
		return
	var tier := int(metal["tier"])
	var power := float(metal["power"]) * power_scale
	var it := Items.define(id, "%s %s" % [metal["name"], label])
	it.as_tool(kind, tier, power, reach)
	it.look(metal["color"], kind)
	it.worth(30 + tier * 90, rarity_for(tier))
	it.in_category(&"tools").tag(&"tool").tag(kind).tag(StringName("tier_%d" % tier))
	it.damage = 3.0 + float(tier) * 2.2 * dmg_scale
	it.attack_speed = 0.85
	it.lasts(180 + tier * 220)
	it.describe("%s %s. Recovers tier %d ore and below, and swings %.2fx as fast "
		% [metal["name"], label.to_lower(), tier, power]
		+ "through stone as bare hands.")


## Drills trade reach for raw speed.
static func _drill(metal: Dictionary) -> void:
	var id := StringName("%s_drill" % metal["id"])
	if Items.has(id):
		return
	var tier := int(metal["tier"])
	var it := Items.define(id, "%s Drill" % metal["name"])
	it.as_tool(&"drill", tier, float(metal["power"]) * 1.8, 4.2)
	it.look((metal["color"] as Color).lightened(0.1), &"drill")
	it.worth(180 + tier * 160, rarity_for(tier + 1))
	it.in_category(&"tools").tag(&"tool").tag(&"drill").tag(StringName("tier_%d" % tier))
	it.damage = 6.0 + float(tier) * 2.0
	it.attack_speed = 1.4
	it.lasts(320 + tier * 260)
	it.flags({"two_handed": true})
	it.describe("Chews straight through rock. Short reach, very fast, and it "
		+ "eats charge like it is being paid to.")


# ===========================================================================
#  Specialists
# ===========================================================================
static func _specialists() -> void:
	Items.define(&"scanner", "Scanner") \
		.as_tool(&"scanner", 0, 1.0, 16.0).look(Color(0.45, 0.9, 0.95), &"lens") \
		.worth(260, Items.RARITY_UNCOMMON).in_category(&"tools") \
		.tag(&"tool").tag(&"scanner") \
		.describe("Identifies blocks, creatures and structures — including the "
			+ "ones the cutaway has sliced open in front of you.")

	Items.define(&"flashlight", "Flashlight") \
		.as_tool(&"light", 0, 1.0, 0.0).look(Color(1.0, 0.95, 0.72), &"lamp") \
		.worth(120).in_category(&"tools").tag(&"tool").tag(&"light_source") \
		.bonus("light", 9.0) \
		.describe("A held light. Cheaper than a tech, and it never runs out.")

	Items.define(&"watering_can", "Watering Can") \
		.as_tool(&"watering_can", 0, 1.0, 5.0).look(Color(0.46, 0.66, 0.82), &"flask") \
		.worth(45).in_category(&"tools").tag(&"farm").tag(&"tool") \
		.describe("Turns tilled soil into watered soil. Crops will not grow dry.")

	Items.define(&"grappling_hook", "Grappling Hook") \
		.as_tool(&"grapple", 1, 1.0, 20.0).look(Color(0.62, 0.58, 0.48), &"hook") \
		.worth(900, Items.RARITY_RARE).in_category(&"tools") \
		.tag(&"tool").tag(&"grapple").flags({"energy_cost": 12.0}) \
		.describe("Fires at whatever you are aiming at and reels you in.")
