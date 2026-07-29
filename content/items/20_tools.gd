## Tools: the Matter Manipulator and its upgrade modules, the pickaxe / axe /
## shovel / drill / hoe ladders, the specialist tools, and one tech card per
## tech in `TchCatalog`.
##
## ---------------------------------------------------------------------------
## TOOL TIER LADDER — mirrors `content/blocks/11_ores.gd` exactly
## ---------------------------------------------------------------------------
##   0 stone / copper   1 iron   2 tungsten   3 titanium
##   4 durasteel        5 aegisalt-class      6 solarium-class
##
## A tool below a block's `tool_tier` still breaks it but yields no drops —
## `BlockType.roll_drops` gates on the tier before it rolls, so there is no
## special-casing anywhere in the mining code.
##
## `tool_kind` vocabulary (read by `tech/interaction.gd` when it decides whether
## the primary button belongs to mining or to combat):
##   `beam` `pickaxe` `axe` `shovel` `drill` `hoe` `paint` `wire` `scanner`
##   `grapple` `light`
extends RefCounted

## Metal ladder: id prefix, display name, tier, power, colour.
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

## Which metals get which tool. Not every metal makes every tool — the ladders
## are staggered so each tier has one obvious upgrade rather than five.
const PICKAXE_TIERS := [0, 1, 2, 3, 4, 5, 6, 7]
const AXE_TIERS := [0, 1, 2, 4, 5, 7]
const SHOVEL_TIERS := [1, 2, 4, 5]
const DRILL_TIERS := [2, 4, 5, 7]


static func register_all(reg) -> void:
	_manipulator(reg)
	_ladders(reg)
	_specialists(reg)
	_tech_cards(reg)


# ===========================================================================
#  The Matter Manipulator and its modules
# ===========================================================================
static func _manipulator(reg) -> void:
	reg.define(&"matter_manipulator", "Matter Manipulator") \
		.of_kind(ItemType.Kind.TOOL) \
		.as_tool(&"beam", 0, 1.0, 5.0) \
		.look(Color(0.55, 0.95, 0.85), &"beam") \
		.worth(0, Const.RARITY_ESSENTIAL) \
		.in_category(&"tools") \
		.tag(&"tool").tag(&"essential").tag(&"beam") \
		.describe("The universal tool. Mines, places, drains liquid, edits wiring and paints — every one of those bought separately with manipulator modules.") \
		.flags({"stack_size": 1})

	reg.define(&"manipulator_module", "Manipulator Module") \
		.look(Color(0.65, 0.9, 1.0), &"chip") \
		.worth(600, Const.RARITY_RARE) \
		.stacks(200) \
		.in_category(&"tools") \
		.tag(&"upgrade").tag(&"module") \
		.describe("Currency for Matter Manipulator upgrades. Spend it at a Manipulator Bench.")

	# Named chips: cosmetic wrappers that make each upgrade track legible in
	# loot tables and shops. Using one is equivalent to spending its modules.
	_chip(reg, &"mm_aperture_chip", "Aperture Chip", "radius", 3,
		Color(0.6, 1.0, 0.8), "Widens the beam: 1x1 -> 2x2 -> 3x3.")
	_chip(reg, &"mm_resolver_chip", "Resolver Chip", "tier", 2,
		Color(0.9, 0.8, 0.4), "Raises the ore tier the beam can recover.")
	_chip(reg, &"mm_cycle_chip", "Cycle Chip", "speed", 2,
		Color(1.0, 0.6, 0.35), "Faster extraction.")
	_chip(reg, &"mm_focus_lens", "Focus Lens", "range", 2,
		Color(0.7, 0.85, 1.0), "Longer reach.")
	_chip(reg, &"mm_fluid_intake", "Fluid Intake Module", "liquid", 5,
		Color(0.35, 0.7, 1.0), "Unlocks liquid collection mode.")
	_chip(reg, &"mm_signal_probe", "Signal Probe Module", "wire", 4,
		Color(1.0, 0.85, 0.3), "Unlocks wire editing mode.")
	_chip(reg, &"mm_chroma_head", "Chroma Head Module", "paint", 4,
		Color(0.9, 0.4, 0.6), "Unlocks paint mode.")


static func _chip(reg, p_id: StringName, display: String, track: String,
		modules: int, col: Color, desc: String) -> void:
	var it: ItemType = reg.define(p_id, display)
	it.of_kind(ItemType.Kind.AUGMENT)
	it.look(col, &"chip")
	it.worth(modules * 600, Const.RARITY_RARE)
	it.stacks(20)
	it.in_category(&"tools")
	it.tag(&"upgrade").tag(&"manipulator")
	it.describe("%s Worth %d manipulator modules." % [desc, modules])
	# Using the chip buys the upgrade outright, without a bench.
	it.on_use = func(_player: Node, _ctx: Dictionary) -> bool:
		if Tech.beam == null:
			return false
		if Tech.beam.is_maxed(track):
			Events.toast("That track is already at maximum.", "warn")
			return false
		Tech.beam.levels[track] = int(Tech.beam.levels[track]) + 1
		Events.upgrade_purchased.emit("manipulator:" + track)
		Events.toast("Matter Manipulator upgraded.", "upgrade")
		return true


# ===========================================================================
#  Mining ladders
# ===========================================================================
static func _ladders(reg) -> void:
	for i: int in PICKAXE_TIERS:
		if i >= METALS.size():
			continue
		_tool(reg, METALS[i], &"pickaxe", "Pickaxe", 1.0, 5.0, 1.0)
	for i: int in AXE_TIERS:
		if i >= METALS.size():
			continue
		_tool(reg, METALS[i], &"axe", "Axe", 1.15, 4.5, 1.3)
	for i: int in SHOVEL_TIERS:
		if i >= METALS.size():
			continue
		_tool(reg, METALS[i], &"shovel", "Shovel", 1.4, 4.5, 0.7)
	for i: int in DRILL_TIERS:
		if i >= METALS.size():
			continue
		_drill(reg, METALS[i])

	_tool(reg, {"id": &"wood", "name": "Wooden", "tier": 0, "power": 0.9,
		"color": Color(0.55, 0.40, 0.24)}, &"hoe", "Hoe", 1.0, 4.0, 0.4)
	_tool(reg, METALS[2], &"hoe", "Hoe", 1.5, 4.5, 0.6)


static func _tool(reg, metal: Dictionary, kind: StringName, label: String,
		power_scale: float, reach: float, dmg_scale: float) -> void:
	var p_id := StringName("%s_%s" % [metal["id"], kind])
	if reg.has(p_id):
		return
	var tier := int(metal["tier"])
	var power := float(metal["power"]) * power_scale
	var it: ItemType = reg.define(p_id, "%s %s" % [metal["name"], label])
	it.of_kind(ItemType.Kind.TOOL)
	it.as_tool(kind, tier, power, reach)
	it.look(metal["color"], kind)
	it.worth(30 + tier * 90, _rarity(tier))
	it.in_category(&"tools")
	it.tag(&"tool").tag(kind).tag(StringName("tier_%d" % tier))
	it.damage = 3.0 + float(tier) * 2.2 * dmg_scale
	it.attack_speed = 0.85
	it.describe("%s %s. Mines tier %d and below at x%.2f speed."
		% [metal["name"], label.to_lower(), tier, power])


## Drills trade reach for a 2x2 footprint and raw speed.
static func _drill(reg, metal: Dictionary) -> void:
	var p_id := StringName("%s_drill" % metal["id"])
	if reg.has(p_id):
		return
	var tier := int(metal["tier"])
	var it: ItemType = reg.define(p_id, "%s Drill" % metal["name"])
	it.of_kind(ItemType.Kind.TOOL)
	it.as_tool(&"drill", tier, float(metal["power"]) * 1.8, 3.8)
	it.look((metal["color"] as Color).lightened(0.1), &"drill")
	it.worth(180 + tier * 160, _rarity(tier + 1))
	it.in_category(&"tools")
	it.tag(&"tool").tag(&"drill").tag(StringName("tier_%d" % tier))
	it.damage = 6.0 + float(tier) * 2.0
	it.attack_speed = 1.4
	it.describe("Chews through a 2x2 face. Short reach, very fast.")
	it.flags({"two_handed": true})


static func _rarity(tier: int) -> int:
	if tier >= 6:
		return Const.RARITY_LEGENDARY
	if tier >= 4:
		return Const.RARITY_RARE
	if tier >= 2:
		return Const.RARITY_UNCOMMON
	return Const.RARITY_COMMON


# ===========================================================================
#  Specialist tools
# ===========================================================================
static func _specialists(reg) -> void:
	var paint: ItemType = reg.define(&"paint_tool", "Paint Tool")
	paint.of_kind(ItemType.Kind.TOOL).as_tool(&"paint", 0, 1.0, 6.0)
	paint.look(Color(0.9, 0.4, 0.6), &"brush").worth(320, Const.RARITY_UNCOMMON)
	paint.in_category(&"tools").tag(&"tool").tag(&"paint")
	paint.describe("Recolours placed blocks. Secondary fire strips paint back off.")
	paint.on_use = func(_player: Node, _ctx: Dictionary) -> bool:
		if Tech.beam != null:
			Tech.beam.set_mode(TchToolBeam.Mode.PAINT)
		return false

	var wire: ItemType = reg.define(&"wire_tool", "Wire Tool")
	wire.of_kind(ItemType.Kind.TOOL).as_tool(&"wire", 0, 1.0, 8.0)
	wire.look(Color(1.0, 0.85, 0.3), &"probe").worth(300, Const.RARITY_UNCOMMON)
	wire.in_category(&"tools").tag(&"tool").tag(&"wire")
	wire.describe("Connects emitters to consumers. Click a source, then its target. Wires route through layers, so check the other planes.")
	wire.on_use = func(_player: Node, _ctx: Dictionary) -> bool:
		if Tech.beam != null:
			Tech.beam.set_mode(TchToolBeam.Mode.WIRE)
		return false

	var scanner: ItemType = reg.define(&"scanner", "Scanner")
	scanner.of_kind(ItemType.Kind.TOOL).as_tool(&"scanner", 0, 1.0, 14.0)
	scanner.look(Color(0.45, 0.9, 0.95), &"lens").worth(260, Const.RARITY_UNCOMMON)
	scanner.in_category(&"tools").tag(&"tool").tag(&"scanner")
	scanner.describe("Identifies blocks, objects and creatures — including ones sitting behind the play layer.")

	var hook: ItemType = reg.define(&"grappling_hook", "Grappling Hook")
	hook.of_kind(ItemType.Kind.TOOL).as_tool(&"grapple", 1, 1.0, 18.0)
	hook.look(Color(0.62, 0.58, 0.48), &"hook").worth(900, Const.RARITY_RARE)
	hook.in_category(&"tools").tag(&"tool").tag(&"grapple")
	hook.energy_cost = 12.0
	hook.describe("Fires along the plane and reels you in. Will not cross layers — the line has to stay in your view.")

	var torch: ItemType = reg.define(&"flashlight", "Flashlight")
	torch.of_kind(ItemType.Kind.TOOL).as_tool(&"light", 0, 1.0, 0.0)
	torch.look(Color(1.0, 0.95, 0.72), &"lamp").worth(120)
	torch.in_category(&"tools").tag(&"tool").tag(&"light_source")
	torch.bonus("light", 9.0)
	torch.describe("A held light. Cheaper than a tech, and it never runs out of energy.")


# ===========================================================================
#  Tech cards
# ===========================================================================
## One card per entry in `TchCatalog`. Using a card unlocks its tech, provided
## the prerequisites are already owned — `tech/interaction.gd` handles the
## consumption path, so the card itself needs no `on_use`.
static func _tech_cards(reg) -> void:
	for d: Dictionary in TchCatalog.ALL:
		var tid: StringName = d["id"]
		var card := TchCatalog.card_id(tid)
		if reg.has(card):
			continue
		var it: ItemType = reg.define(card, "%s Tech Card" % String(d["name"]))
		it.of_kind(ItemType.Kind.TECH)
		it.tech_id = tid
		it.look(d["color"], &"card")
		it.worth(int(d["price"]), int(d["rarity"]))
		it.stacks(1)
		it.in_category(&"tech")
		it.tag(&"tech").tag(&"card").tag(StringName("slot_" + String(d["slot"])))
		var reqs: Array = d.get("requires", [])
		var req_line := ""
		if not reqs.is_empty():
			var names: Array[String] = []
			for r: Variant in reqs:
				names.append(String(TchCatalog.get_def(StringName(r)).get("name", r)))
			req_line = "  Requires: %s." % ", ".join(names)
		var drain := float(d["drain"])
		var drain_line := (", %.0f/s while active" % drain) if drain > 0.0 else ""
		it.describe("%s  (%s slot, %.0f energy%s)%s" % [
			String(d["desc"]), String(d["slot"]), float(d["energy"]),
			drain_line, req_line,
		])
