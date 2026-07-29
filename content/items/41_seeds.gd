## Seeds and the farming tools.
##
## One seed per row of `SrvFarming.crop_table()`, named `<crop>_seed`, plus
## fertiliser, a watering can and (only if no other agent has claimed the id) a
## basic hoe so the loop is playable end to end.
##
## ## How a seed knows where to plant
##
## `ItemType.on_use(player, ctx)` is called by whatever module is driving
## interaction. Different agents build `ctx` differently, so [method _target]
## accepts every reasonable spelling of "the block you are pointing at"
## (`block_pos`, `pos`, `target`, `block`) and a `normal`/`face` to offset by.
## With no context at all it falls back to the block under the player's feet,
## which makes seeds usable from a bare hotbar press.
##
## Everything is expressed in world voxel coordinates, never plane coordinates,
## so planting behaves identically in all four views.
extends RefCounted

## Sentinel returned by [method _target] when no plot could be resolved.
const NO_TARGET := Vector3i(-2147483, -2147483, -2147483)


static func register_all(reg) -> void:
	_seeds(reg)
	_tools(reg)


# ======================================================================= seeds
static func _seeds(reg) -> void:
	for row: Dictionary in SrvFarming.crop_table():
		var crop: StringName = row["id"]
		var id := SrvFarming.seed_item_name(crop)
		if reg.has(id):
			continue
		var ripe: Color = row["ripe"]
		var it: ItemType = reg.define(id, "%s Seed" % row["name"])
		it.of_kind(ItemType.Kind.SEED)
		it.look(ripe.lerp(Color(0.42, 0.32, 0.20), 0.45), &"seed")
		it.describe(_seed_blurb(row))
		it.worth(maxi(2, int(row["value"]) / 2), int(row["rarity"]))
		it.stacks(200)
		it.in_category(&"seeds")
		it.tag(&"seed").tag(StringName(row["biome"])).tag(StringName("crop_" + String(crop)))
		if bool(row["aquatic"]):
			it.tag(&"aquatic")
		if bool(row["perennial"]):
			it.tag(&"perennial")
		it.seed_crop = crop
		it.on_use = _plant_hook(crop)


static func _seed_blurb(row: Dictionary) -> String:
	var bits := PackedStringArray()
	bits.append("Plant on tilled soil.")
	if bool(row["aquatic"]):
		bits.append("Needs to be underwater.")
	elif bool(row["needs_water"]):
		bits.append("Wants a water source nearby.")
	if int(row["light"]) <= 0:
		bits.append("Grows in the dark.")
	if bool(row["perennial"]):
		bits.append("Keeps producing once grown.")
	return " ".join(bits)


static func _plant_hook(crop: StringName) -> Callable:
	return func(player: Node, ctx: Dictionary) -> bool:
		if Status == null or Status.farming == null:
			return false
		var soil := _target(player, ctx)
		if soil == NO_TARGET:
			return false
		return Status.farming.plant(crop, soil, player)


# ======================================================================= tools
static func _tools(reg) -> void:
	if not reg.has(&"fertiliser"):
		var f: ItemType = reg.define(&"fertiliser", "Fertiliser")
		f.of_kind(ItemType.Kind.CONSUMABLE)
		f.look(Color(0.42, 0.32, 0.16), &"square")
		f.describe("Spread on a plot to speed up the next few growth stages. Six uses per plot.")
		f.worth(8).stacks(200).in_category(&"seeds").tag(&"farm").tag(&"fertiliser")
		f.on_use = _fertilise_hook()

	if not reg.has(&"watering_can"):
		var w: ItemType = reg.define(&"watering_can", "Watering Can")
		w.of_kind(ItemType.Kind.TOOL)
		w.as_tool(&"watering_can", 0, 1.0, 5.0)
		w.look(Color(0.46, 0.66, 0.82), &"flask")
		w.describe("Turns tilled soil into watered soil. Crops will not grow without moisture.")
		w.worth(45).in_category(&"tools").tag(&"farm").tag(&"tool")
		w.on_use = _water_hook()

	# The tools agent may own the hoe; only fill the gap if nobody has.
	if not reg.has(&"hoe"):
		var h: ItemType = reg.define(&"hoe", "Hoe")
		h.of_kind(ItemType.Kind.TOOL)
		h.as_tool(&"hoe", 0, 1.0, 5.0)
		h.look(Color(0.62, 0.48, 0.28), &"pick")
		h.describe("Breaks soil into a plot you can plant in.")
		h.worth(40).in_category(&"tools").tag(&"farm").tag(&"tool")
		h.on_use = _till_hook()

	if not reg.has(&"greenhouse_kit"):
		var g: ItemType = reg.define(&"greenhouse_kit", "Greenhouse Blueprint")
		g.of_kind(ItemType.Kind.MATERIAL)
		g.look(Color(0.72, 0.92, 0.82), &"square")
		g.describe("Panels placed above a plot shelter it from the weather and the dark, and speed growth by a third.")
		g.worth(60, Const.RARITY_UNCOMMON).stacks(20)
		g.in_category(&"seeds").tag(&"farm").tag(&"blueprint")


static func _till_hook() -> Callable:
	return func(player: Node, ctx: Dictionary) -> bool:
		if Status == null or Status.farming == null:
			return false
		var soil := _target(player, ctx)
		if soil == NO_TARGET:
			return false
		# Tools are not consumed, so always report "not used up".
		Status.farming.till(soil, player)
		return false


static func _water_hook() -> Callable:
	return func(player: Node, ctx: Dictionary) -> bool:
		if Status == null or Status.farming == null:
			return false
		var soil := _target(player, ctx)
		if soil == NO_TARGET:
			return false
		Status.farming.water(soil, player)
		return false


static func _fertilise_hook() -> Callable:
	return func(player: Node, ctx: Dictionary) -> bool:
		if Status == null or Status.farming == null:
			return false
		var soil := _target(player, ctx)
		if soil == NO_TARGET:
			return false
		return Status.farming.fertilise(soil, player)


# ===================================================================== context
## Resolve "the soil block the player means" out of whatever `ctx` the
## interaction module handed us. Returns [constant NO_TARGET] when there is
## nothing sensible to act on.
static func _target(player: Node, ctx: Dictionary) -> Vector3i:
	var cell := NO_TARGET
	for key: String in ["block_pos", "pos", "target", "block", "hit"]:
		var v: Variant = ctx.get(key)
		if v is Vector3i:
			cell = v
			break
		if v is Vector3:
			cell = Const.floor_v(v as Vector3)
			break
	if cell == NO_TARGET:
		var p3 := player as Node3D
		if p3 == null:
			return NO_TARGET
		# Bare use: the block the player is standing on.
		cell = Const.floor_v(p3.global_position + Vector3(0.0, -0.35, 0.0))

	# Some callers pass the face normal of the block they hit; a top-face hit
	# means "the block itself", anything else means "step back along the normal".
	var nrm: Variant = ctx.get("normal", ctx.get("face"))
	if nrm is Vector3i and (nrm as Vector3i) != Vector3i(0, 1, 0):
		cell += (nrm as Vector3i)
	# If we were handed the air above a plot, drop to the plot itself.
	if World.get_block(cell) == Const.AIR:
		cell += Vector3i(0, -1, 0)
	return World.normalize(cell)
