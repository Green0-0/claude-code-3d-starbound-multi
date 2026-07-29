## Moving liquid around by hand and by machine.
##
## This is the **only** API other modules should use to add or remove liquid:
## it keeps the block id, the fill level and the solver's active set in step,
## and it works the same whether the caller is a bucket, a canister, a pump, a
## pipe segment, a sprinkler or a boss's acid-spitting mouth.
##
## Everything here is static and side-effect-free apart from the world edit, so
## it can be called from a tool script, an object's `_process`, or a callable
## installed on a `BlockType`.
##
## ```gdscript
## # tech agent, right-click with a bucket:
## var hit := World.raycast(from, dir, 5.0, true)
## if hit["hit"]:
##     var got := LiqBucket.scoop(hit["pos"])          # -> &"water" or &""
##     if got != &"":
##         inventory.swap_selected(LiqBucket.bucket_item_for(got))
##
## # objects agent, a pump running once a second:
## var moved := LiqBucket.pump(intake_pos, outlet_pos, 4)
## ```
class_name LiqBucket
extends RefCounted

const FULL := Const.MAX_LIQUID
## Item id of an empty container. Registered by the item-content agent; every
## lookup here is guarded, so an absent item just means "no item swap".
const EMPTY_BUCKET: StringName = &"bucket"
const EMPTY_CANISTER: StringName = &"canister"

## How far a pump may reach for a source when its exact intake voxel is dry.
const PUMP_SEARCH := 3


# =============================================================== hand tools
## Take a bucketful out of the world.
##
## Returns the liquid's StringName (`&"water"`, `&"lava"`, ...) or `&""` when
## there was nothing worth scooping. Ocean source cells never run dry.
##
## With `require_full` (the default) only a brim-full cell can be picked up, so
## the player cannot farm infinite water out of a puddle; pass `false` for
## machines that are happy with a partial draw.
static func scoop(pos: Vector3i, require_full: bool = true) -> StringName:
	var id := World.get_block(pos)
	if id == Const.AIR or not Blocks.is_liquid(id):
		return &""
	var liquid := LiqType.name_of_block(id)
	if liquid == &"":
		return &""
	var level := Liquids.level_at(pos)
	if require_full and level < FULL and not Liquids.ocean.is_source(pos, id):
		return &""
	if Liquids.remove_liquid(pos, FULL) <= 0:
		return &""
	var centre := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	Events.play_sound.emit(&"scoop", centre)
	Events.spawn_particles.emit(StringName(LiqType.of(liquid).get("splash", &"splash_water")), centre, 5)
	return liquid


## Pour liquid into the world. Returns the units actually placed (0..8).
##
## `pos` is normally the *empty* voxel the player aimed at; if it will not take
## the liquid the voxel above is tried, which is what makes pouring against a
## wall feel right.
static func pour(pos: Vector3i, liquid_id: StringName, amount: int = FULL) -> int:
	if amount <= 0 or LiqType.block_id(liquid_id) == Const.AIR:
		return 0
	var placed := Liquids.add_liquid(pos, liquid_id, amount)
	if placed <= 0:
		placed = Liquids.add_liquid(pos + Vector3i(0, 1, 0), liquid_id, amount)
		if placed > 0:
			pos += Vector3i(0, 1, 0)
	if placed <= 0:
		return 0
	var centre := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	var params := LiqType.of(liquid_id)
	Events.play_sound.emit(StringName(params.get("enter_sound", &"splash")), centre)
	Events.spawn_particles.emit(StringName(params.get("splash", &"splash_water")), centre, 6)
	return placed


## Would [method scoop] succeed here?
static func can_scoop(pos: Vector3i, require_full: bool = true) -> bool:
	var id := World.get_block(pos)
	if id == Const.AIR or not Blocks.is_liquid(id):
		return false
	if not require_full:
		return Liquids.level_at(pos) > 0
	return Liquids.level_at(pos) >= FULL or Liquids.ocean.is_source(pos, id)


## Free space at a voxel, in units, for the liquid `liquid_id`.
static func capacity_at(pos: Vector3i, liquid_id: StringName) -> int:
	var want := LiqType.block_id(liquid_id)
	if want == Const.AIR:
		return 0
	var id := World.get_block(pos)
	if id == want:
		return FULL - Liquids.level_at(pos)
	if id == Const.AIR:
		return FULL
	if Blocks.is_solid(id) or Blocks.is_liquid(id):
		return 0
	return FULL if Blocks.is_replaceable(id) else 0


## Everything a UI or a machine might want to know about one voxel.
static func sample(pos: Vector3i) -> Dictionary:
	var id := World.get_block(pos)
	var liquid := LiqType.name_of_block(id)
	return {
		"liquid": liquid,
		"level": Liquids.level_at(pos),
		"fill": Liquids.fill_at(pos),
		"source": Liquids.ocean.is_source(pos, id),
		"display": String(LiqType.of(liquid).get("display", "")) if liquid != &"" else "",
	}


# ============================================================= item plumbing
## Item id of a container full of `liquid`, or `&""` when no such item exists.
static func bucket_item_for(liquid: StringName) -> StringName:
	var item := StringName(LiqType.of(liquid).get("bucket", &""))
	if item != &"" and Items.has(item):
		return item
	return &""


## Liquid held by a container item, or `&""`.
static func liquid_for_item(item_id: StringName) -> StringName:
	for liquid: StringName in LiqType.all_names():
		if StringName(LiqType.of(liquid).get("bucket", &"")) == item_id:
			return liquid
	return &""


## One-call "the player used a container on this voxel".
##
## Returns `{"ok": bool, "liquid": StringName, "consumed": StringName,
## "produced": StringName}` — `consumed`/`produced` are the item ids the caller
## should swap in the hotbar, either of which may be `&""`.
static func use_container(item_id: StringName, pos: Vector3i) -> Dictionary:
	var out := {"ok": false, "liquid": &"", "consumed": &"", "produced": &""}
	var held := liquid_for_item(item_id)
	if held != &"":
		if pour(pos, held) <= 0:
			return out
		out["ok"] = true
		out["liquid"] = held
		out["consumed"] = item_id
		out["produced"] = EMPTY_BUCKET if Items.has(EMPTY_BUCKET) else &""
		return out
	if item_id != EMPTY_BUCKET and item_id != EMPTY_CANISTER:
		return out
	var got := scoop(pos)
	if got == &"":
		return out
	out["ok"] = true
	out["liquid"] = got
	out["consumed"] = item_id
	out["produced"] = bucket_item_for(got)
	return out


# =================================================================== machines
## Move up to `rate` units from one voxel to another, wherever they are. Pipes
## and pumps are *not* simulated as fluid networks — a pipe run is just a
## machine that calls this with its two endpoints, which costs nothing and can
## never leak volume.
##
## Returns the units actually moved.
static func pump(from: Vector3i, to: Vector3i, rate: int = 2) -> int:
	if rate <= 0:
		return 0
	var src := from
	var id := World.get_block(src)
	if id == Const.AIR or not Blocks.is_liquid(id):
		var found := find_source(from, PUMP_SEARCH)
		if found.y < 0:
			return 0
		src = found
		id = World.get_block(src)
	var liquid := LiqType.name_of_block(id)
	if liquid == &"":
		return 0
	var room := capacity_at(to, liquid)
	if room <= 0:
		return 0
	var want := mini(rate, room)
	var taken := Liquids.remove_liquid(src, want)
	if taken <= 0:
		return 0
	var placed := Liquids.add_liquid(to, liquid, taken)
	if placed < taken:
		# The destination filled up mid-transfer; put the remainder back rather
		# than deleting it.
		Liquids.add_liquid(src, liquid, taken - placed)
	return placed


## Pull liquid out of the world into a machine's internal tank.
## Returns `{"liquid": StringName, "amount": int}`.
static func drain(pos: Vector3i, amount: int = FULL) -> Dictionary:
	var id := World.get_block(pos)
	if id == Const.AIR or not Blocks.is_liquid(id):
		return {"liquid": &"", "amount": 0}
	var liquid := LiqType.name_of_block(id)
	return {"liquid": liquid, "amount": Liquids.remove_liquid(pos, amount)}


## Push liquid from a machine's tank into the world. Alias of [method pour] with
## a machine-friendly name.
static func fill(pos: Vector3i, liquid_id: StringName, amount: int = FULL) -> int:
	return Liquids.add_liquid(pos, liquid_id, amount)


## Nearest liquid voxel to `centre` within `radius`, or `Vector3i(0, -1, 0)`
## when there is none. Used by pump intakes so they tolerate the water level
## dropping a block or two.
static func find_source(centre: Vector3i, radius: int = PUMP_SEARCH) -> Vector3i:
	var best := Vector3i(0, -1, 0)
	var best_d := 1 << 30
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var q := centre + Vector3i(dx, dy, dz)
				if q.y < 0 or q.y >= Const.WORLD_HEIGHT:
					continue
				if not Blocks.is_liquid(World.get_block(q)):
					continue
				var d := dx * dx + dy * dy + dz * dz
				if d < best_d:
					best_d = d
					best = q
	return best


## Rain, sprinklers and leaky pipes: add a trickle without any of the ceremony.
static func trickle(pos: Vector3i, liquid_id: StringName, units: int = 1) -> int:
	return Liquids.add_liquid(pos, liquid_id, units)
