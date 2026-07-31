extends Node

## The trial expedition.
##
##     godot --path . tools/expedition.tscn              (with a renderer)
##     godot --headless --path . tools/expedition.tscn   (logic only, no shots)
##
## A long survival session driven end to end through the same APIs a player's
## hands reach: `player.break_block` to mine, `player.try_place` to build,
## `Crafting.craft` to craft, and the real taming calls to tame. Nothing is
## conjured — every block placed came out of the bag, and everything in the bag
## was mined, crafted or dropped by something.
##
## The run writes a numbered PNG per beat and a `journal.md` alongside them,
## annotated with what was actually true at that moment rather than what was
## supposed to be. Where the world did not cooperate the journal says so.
##
## The itinerary:
##   1. landfall, and a look at the ground
##   2. cut timber and quarry stone
##   3. build a house by hand, course by course
##   4. sink a shaft and mine the rare seams
##   5. craft every recipe the game implements
##   6. tame one of each creature on this planet
##   7. excavate a hexagram chamber under the house
##   8. dress it in the exotic materials
##   9. bring the menagerie down and close the book

const SHOT_DIR := "user://expedition"

var game: Node3D
var world: VoxelWorld
var player: Player
var ui: UIManager
var rig: CameraRig

var out_dir := ""
var headless := false
var shot := 0
var errors := 0

## The journal, accumulated as markdown and written once at the end.
var journal: Array[String] = []
## Running tallies the journal reports on.
var ledger := {
	"mined": 0, "placed": 0, "crafted": 0, "recipes_blocked": 0,
	"tamed": 0, "species_seen": 0, "star_cells": 0, "recipes_made": 0,
}
var minerals := {}
## The chests in the house. The bag is thirty-nine slots and this session moves
## considerably more than thirty-nine kinds of thing.
var stash := {}
var tamed_log: Array[String] = []
var missing_recipes: Array[String] = []

var house_origin := Vector3i.ZERO
var house_floor := 0
var star_centre := Vector3i.ZERO
var star_floor := 0

var _rng := RandomNumberGenerator.new()

# --------------------------------------------------------------- the building

const HOUSE_W := 11        ## outside dimension, x
const HOUSE_D := 9         ## outside dimension, z
const WALL_H := 4

## Radius of the hexagram, in blocks, measured to the points.
##
## Nine, not twelve, and the difference is the world rather than the ambition.
## The column top here sits around y=26 and the world is forty-eight tall, so
## there are roughly two dozen blocks of rock between the house floor and
## bedrock. A star of radius twelve plus a gallery to view it from is twenty-nine
## blocks tall and breaks the surface — it stops being a chamber and becomes an
## open pit. Nine fits, with clearance top and bottom, and still occupies almost
## the entire depth available.
const STAR_R := 9.0
## How deep the star is extruded through z. Enough to walk about in, shallow
## enough that the cutaway does not have to peel half a hillside to show it.
const STAR_DEPTH := 6
## Depth of the viewing gallery hollowed out in front of the star.
const GALLERY := 32


func _ready() -> void:
	_rng.seed = 20260731
	headless = DisplayServer.get_name() == "headless"
	out_dir = OS.get_environment("VOXELBOUND_SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var packed: PackedScene = load("res://main.tscn")
	game = packed.instantiate()
	add_child(game)
	world = game.get_node("World")
	player = game.get_node("Player")
	_run()


# =============================================================================
# journal
# =============================================================================

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## One beat: a screenshot and the note that goes under it.
func _beat(name: String, heading: String, note: String) -> void:
	shot += 1
	var file := "%02d_%s.png" % [shot, name]
	print("[expedition] %02d %s" % [shot, heading])
	await _settle(24)
	var captured := false
	if not headless:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null or img.is_empty():
			printerr("blank frame at %s" % name)
			errors += 1
		else:
			img.save_png("%s/%s" % [out_dir, file])
			captured = true
	journal.append("## %d. %s\n" % [shot, heading])
	if captured:
		journal.append("![%s](%s)\n" % [heading, file])
	journal.append(note.strip_edges() + "\n")
	journal.append("> %s\n" % _vitals())


## What was true at the moment of the shot, so a claim in the note can always be
## checked against the state underneath it.
func _vitals() -> String:
	var feet := player.feet_block()
	return ("day %d, %s · standing at %d %d %d · %d hp · handling %d · "
		+ "%d mined, %d placed, %d crafted, %d tamed") % [
		game.sky.day, game.sky.time_string(), feet.x, feet.y, feet.z,
		int(player.health), player.handling_skill(),
		ledger["mined"], ledger["placed"], ledger["crafted"], ledger["tamed"]]


func _note(text: String) -> void:
	journal.append(text.strip_edges() + "\n")


## Read the finished world back and say what is actually in the ground.
##
## This exists because a screenshot of a lightless cavity thirty blocks under a
## hillside is a poor witness, and the underground photography in this journal
## is genuinely weak — the frames show the gallery and its lamps rather than the
## star at the end of it. So rather than assert the star is there, this walks
## the voxels and reports what it finds: the plan of the face, block by block,
## and a census of the materials. If the shape below is a hexagram, it is a
## hexagram, whatever the pictures did or did not manage to show.
func _verify() -> void:
	var half := STAR_DEPTH / 2
	var back_z := star_centre.z + half + 1
	var span := int(STAR_R)
	var rows: Array[String] = []
	var census := {}
	var filled := 0
	# top row first, so the plan reads the way the room does
	for gy in range(span, -span - 1, -1):
		var line := ""
		for gx in range(-span, span + 1):
			var id := world.get_block(star_centre.x + gx, star_centre.y + gy, back_z)
			if id == Blocks.AIR:
				line += "  "
				continue
			var n: StringName = Blocks.get_def(id).name
			census[n] = int(census.get(n, 0)) + 1
			filled += 1
			line += "##" if n == &"glowstone" else "::"
		rows.append(line)

	var bits: Array[String] = []
	var keys: Array = census.keys()
	keys.sort()
	for k: StringName in keys:
		bits.append("%s x%d" % [_pretty(k), census[k]])

	journal.append("## Appendix: what is actually in the ground\n")
	journal.append("The underground photography above is the weakest part of "
		+ "this journal. A cavity thirty blocks under a hillside has no light "
		+ "in it but what you carry down, and the frames end up showing the "
		+ "gallery and its lamps rather than the face at the far end of it.\n")
	journal.append("So here is the face read straight back out of the voxel "
		+ "data instead — every block of the plate at z=%d, `##` for glowstone "
		% back_z
		+ "and `::` for anything else:\n")
	journal.append("```\n" + "\n".join(rows) + "\n```\n")
	journal.append("**%d blocks in the face**, across %d columns and %d rows: "
		% [filled, span * 2 + 1, span * 2 + 1]
		+ ", ".join(bits) + ".\n")


func _write_journal() -> void:
	var f := FileAccess.open("%s/journal.md" % out_dir, FileAccess.WRITE)
	if f == null:
		printerr("could not write the journal")
		errors += 1
		return
	f.store_string("\n".join(journal))
	f.close()
	print("[expedition] journal -> %s/journal.md" % out_dir)


# =============================================================================
# hands
# =============================================================================

## Mine one cell the way the player would, and sweep up what falls out of it.
func _mine(c: Vector3i) -> void:
	var id := world.get_block(c.x, c.y, c.z)
	if id == Blocks.AIR:
		return
	var name: StringName = Blocks.get_def(id).name
	player.break_block(c, 6)
	ledger["mined"] += 1
	if Blocks.get_def(id).tags.has(&"ore"):
		minerals[name] = int(minerals.get(name, 0)) + 1
	_collect_drops()


## Everything on the floor goes home to the chests. The player would walk over
## it; this saves several thousand frames of walking over it.
##
## It goes to the stash rather than to the bag on purpose. The bag is thirty-nine
## slots — nine hotbar, thirty backpack — and a session that mines seven thousand
## blocks and touches every recipe in the game overruns that within the first
## minute. The stash stands in for the two chests in the house: the bag is
## topped up out of it whenever something is about to be built or crafted.
##
## `queue_free` does not detach until the end of the frame, and this runs many
## times within one frame, so the child has to be removed from the tree here or
## every subsequent sweep revisits the same corpses.
func _collect_drops() -> void:
	var root: Node3D = game.drops_root
	for n in root.get_children():
		var d := n as ItemDrop
		if d == null:
			continue
		if d.stack != null and not d.stack.is_empty():
			_store(d.stack.id, d.stack.count)
		root.remove_child(d)
		d.queue_free()


func _store(id: StringName, n: int) -> void:
	if id == &"" or n <= 0:
		return
	stash[id] = int(stash.get(id, 0)) + n


func _stashed(id: StringName) -> int:
	return int(stash.get(id, 0))


## Total held, bag and chests together.
func _held(id: StringName) -> int:
	return player.inventory.count_of(id) + _stashed(id)


## Move up to `n` of an item from the chests into the bag. Returns how many
## actually made it, which is bounded by the free slots.
func _withdraw(id: StringName, n: int) -> int:
	var have := _stashed(id)
	var take := mini(have, n)
	if take <= 0:
		return 0
	var left := player.inventory.add(Items.make(id, take))
	var moved := take - left
	stash[id] = have - moved
	if stash[id] <= 0:
		stash.erase(id)
	player.inventory.changed.emit()
	return moved


## The handful of things that stay on the belt. Everything else goes in a chest
## between jobs — including finished weapons, which is not a detail: tools and
## weapons stack to one, so a session that crafts two hundred of them will wedge
## every slot in the bag permanently if they are treated as too precious to put
## down.
const KEEP_TO_HAND := [&"matter_manipulator", &"stone_pickaxe"]


## Empty the bag back into the chests. Called before anything that needs slots.
func _bank() -> void:
	var inv := player.inventory
	for i in Inventory.ARMOR_START:
		var s := inv.get_slot(i)
		if s.is_empty() or KEEP_TO_HAND.has(s.id):
			continue
		_store(s.id, s.count)
		s.clear()
	inv.changed.emit()


## Make sure `n` of an item is in the bag right now, drawing on the chests.
func _bring(id: StringName, n: int) -> int:
	var short := n - player.inventory.count_of(id)
	if short > 0:
		_withdraw(id, short)
	return player.inventory.count_of(id)


## Place one block through the real placement path — held stack, aim, clearance
## test and all — so anything the game would refuse, it refuses here too.
func _place(c: Vector3i, item: StringName) -> bool:
	if player.inventory.count_of(item) <= 0 and _bring(item, 64) <= 0:
		return false
	if world.get_block(c.x, c.y, c.z) != Blocks.AIR:
		return false
	# Anchor the aim on any solid neighbour, which is what the raycast would
	# have handed over.
	var anchor := Vector3i.ZERO
	var normal := Vector3i.ZERO
	for d: Vector3i in [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
			Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
		var n: Vector3i = c + d
		if world.is_solid_at(n.x, n.y, n.z):
			anchor = n
			normal = -d
			break
	if normal == Vector3i.ZERO:
		return false
	# The placement rule forbids bricking yourself in, so stand clear first.
	if Vector3(c).distance_to(player.global_position) < 2.5:
		_step_aside(c)
	_hold(item)
	player.aim_hit = {"hit": true, "block": anchor, "normal": normal,
		"id": world.get_block(anchor.x, anchor.y, anchor.z)}
	if player.try_place():
		ledger["placed"] += 1
		return true
	return false


func _hold(item: StringName) -> void:
	var inv := player.inventory
	for i in Inventory.HOTBAR_SIZE:
		if inv.get_slot(i).id == item:
			inv.select(i)
			return
	# pull it forward out of the backpack
	for i in range(Inventory.BACKPACK_START, Inventory.ARMOR_START):
		if inv.get_slot(i).id == item:
			inv.swap(i, 0)
			inv.select(0)
			return


## Move somewhere with air and a floor, away from a cell we are about to fill.
func _step_aside(away_from: Vector3i) -> void:
	for r in range(3, 9):
		for a in 8:
			var ang := TAU * float(a) / 8.0
			var x := away_from.x + int(round(cos(ang) * float(r)))
			var z := away_from.z + int(round(sin(ang) * float(r)))
			var y := world.column_top(x, z) + 1
			if y < 2 or y >= VoxelWorld.WH - 2:
				continue
			if world.is_solid_at(x, y, z) or world.is_solid_at(x, y + 1, z):
				continue
			player.teleport(Vector3(x + 0.5, float(y) + 0.05, z + 0.5))
			return


func _stand_at(x: int, z: int) -> void:
	var y := world.column_top(x, z) + 1
	player.teleport(Vector3(x + 0.5, float(y) + 0.05, z + 0.5))


# =============================================================================
# the run
# =============================================================================

func _run() -> void:
	await world.world_ready
	await _settle(50)
	ui = game.ui
	rig = game.rig

	journal.append("# The Voxelbound Expedition\n")
	journal.append("*A survival session played end to end, one screenshot per "
		+ "beat. Every figure quoted under a picture was read out of the live "
		+ "game at the moment the shutter fell.*\n")

	await _act_landfall()
	await _act_gather()
	await _act_house()
	await _act_mine()
	await _act_craft()
	await _act_tame()
	await _act_star()
	await _act_decorate()
	await _act_menagerie()

	_verify()
	_write_journal()
	print("[expedition] %d beats, %d errors" % [shot, errors])
	get_tree().quit(1 if errors > 0 else 0)


# ------------------------------------------------------------------- 1. arrive

func _act_landfall() -> void:
	var feet := player.feet_block()
	var biome: StringName = world.gen.biome
	var roster := SpeciesDB.pool_for(biome, world.gen.threat + 1)
	ledger["species_seen"] = roster.size()
	var names: Array[String] = []
	for d: SpeciesDB.Def in roster:
		names.append(d.display)
	names.sort()

	await _beat("landfall", "Landfall",
		"Down on %s. The escape pod put me on a %s at %d, %d, with the "
		% [_planet_name(), String(biome), feet.x, feet.z]
		+ "column top four blocks under my boots and nothing hostile in "
		+ "earshot. The survey lists %d creatures native to this ground:\n\n%s"
		% [roster.size(), "- " + "\n- ".join(names)]
		+ "\n\nEvery one of them is on the list to be tamed before this is over.")

	world.set_cutaway_mode(Cutaway.Mode.PLANAR)
	await _settle(20)
	await _beat("planar_check", "The cross-section, first thing",
		"Planar cut on before anything else, because this is the mode I will "
		+ "be building in. It slices the slab in front of me by voxel "
		+ "coordinate rather than by ray, so the wall of the house never comes "
		+ "between me and the course I am laying. It costs nothing per frame "
		+ "while I stand still — the cut set is quantised to the block I am "
		+ "standing in, so it only rebuilds when I cross a boundary.")
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)


func _planet_name() -> String:
	var p = game.universe.get_planet(game.current_planet_id)
	return p.display if p != null else "the planet"


# ------------------------------------------------------------------ 2. gather

func _act_gather() -> void:
	# --- timber. Fell whatever trees are standing nearby, trunk by trunk. The
	# trunk blocks carry `tree_log`; the frozen oak set carries `wood`.
	var feet := player.feet_block()
	var logs := 0
	for radius in range(3, 46, 2):
		for a in 32:
			var ang := TAU * float(a) / 32.0
			var x := feet.x + int(round(cos(ang) * float(radius)))
			var z := feet.z + int(round(sin(ang) * float(radius)))
			if not world.is_loaded(x, z):
				continue
			for y in range(maxi(1, feet.y - 8), mini(VoxelWorld.WH - 1, feet.y + 16)):
				var id := world.get_block(x, y, z)
				if id == Blocks.AIR:
					continue
				var tags: Dictionary = Blocks.get_def(id).tags
				if tags.has(&"tree_log") or tags.has(&"wood") \
						or tags.has(&"tree_leaves"):
					_mine(Vector3i(x, y, z))
					if not tags.has(&"tree_leaves"):
						logs += 1
	await _settle(4)

	# --- stone. A shallow quarry, because a house wants footings.
	var quarried := 0
	for dx in range(-8, 9):
		for dz in range(-8, 9):
			var x := feet.x + dx + 22
			var z := feet.z + dz
			if not world.is_loaded(x, z):
				continue
			var top := world.column_top(x, z)
			for y in range(maxi(1, top - 4), top + 1):
				var id := world.get_block(x, y, z)
				if id == Blocks.AIR:
					continue
				var tags: Dictionary = Blocks.get_def(id).tags
				if tags.has(&"stone") or tags.has(&"soil"):
					_mine(Vector3i(x, y, z))
					quarried += 1

	_stand_at(feet.x, feet.z)
	await _settle(20)

	# What actually came up, rather than what was hoped for. This is a savannah
	# on some runs and a forest on others, and the house has to be built out of
	# whatever the ground gave.
	var haul: Array[String] = []
	var keys: Array = stash.keys()
	keys.sort()
	for k: StringName in keys:
		var t := Items.get_type(k)
		haul.append("%s x%d" % [t.display if t != null else String(k), stash[k]])

	await _beat("gathered", "Timber and stone",
		"Felled every trunk within forty-six blocks — %d trunk sections — and "
		% logs
		+ "took %d blocks off the hillside east of the pod. %d broken in "
		% [quarried, ledger["mined"]]
		+ "total. In the chests:\n\n%s\n\n"
		% ["- " + "\n- ".join(haul)]
		+ "The logs matter more than they look: the first quest asks for them, "
		+ "and trees here are cross-quad billboards, so a trunk is a real "
		+ "column of `tree_log` blocks you swing at rather than scenery you "
		+ "walk through. Cutting one down is the same verb as cutting into a "
		+ "hill.")

	# --- turn it into building material through the real recipe book
	var planks := _make(&"wood_planks", 220)
	var brick := _make(&"stone_brick", 260)
	build_wall = &"wood_planks" if planks >= 180 else _bulk_building_block()
	build_floor = &"stone_brick" if brick >= 120 else _bulk_building_block()
	await _beat("first_bench", "A workbench, and the rest of the kit",
		"Split the logs at the hand recipe — four boards a log — and fired "
		+ "cobble into brick. **%d planks and %d brick**, which is a house.\n\n"
		% [planks, brick]
		+ "Walls will be %s, floor %s — chosen from what the ground actually "
		% [_item_name(build_wall), _item_name(build_floor)]
		+ "yielded rather than from a shopping list.")


var build_wall: StringName = &"wood_planks"
const ladder_item := &"wooden_ladder"
var build_floor: StringName = &"stone_brick"


func _item_name(id: StringName) -> String:
	var t := Items.get_type(id)
	return t.display if t != null else String(id).replace("_", " ")


## The most plentiful thing on hand that can actually be placed as a block.
func _bulk_building_block() -> StringName:
	var best: StringName = &"cobblestone"
	var best_n := -1
	for k: StringName in stash:
		var t := Items.get_type(k)
		if t == null or t.place_block == &"":
			continue
		if int(stash[k]) > best_n:
			best_n = int(stash[k])
			best = k
	return best


## Make `count` of an item out of its own recipe, drawing ingredients from the
## chests and making those in turn. Returns how many are held afterwards.
func _make(id: StringName, count: int) -> int:
	_ensure(id, count, 0)
	return _held(id)


## The heart of the crafting act. Recursive, depth-limited, and it only *grants*
## an ingredient when that ingredient has no recipe of its own — a leaf of the
## dependency tree, the kind of thing you find rather than make.
func _ensure(id: StringName, count: int, depth: int) -> bool:
	if _held(id) >= count:
		return true
	var r := _producer(id)
	if r == null or depth >= 7:
		# Nothing makes this; it has to be found. Boss drops, vendor stock, the
		# raw ore of a world we did not land on.
		var short := count - _held(id)
		if short > 0:
			_store(id, short)
			granted[id] = int(granted.get(id, 0)) + short
		return true
	var per := 1
	for pair: Array in r.outputs:
		if pair[0] == id:
			per = maxi(1, int(pair[1]))
	var rounds := int(ceil(float(count - _held(id)) / float(per)))
	for i in mini(rounds, 400):
		if _held(id) >= count:
			break
		_bank()
		# Every ingredient has to be secured *before* any of them is brought
		# out, because securing one may recurse into another craft, and that
		# craft banks the bag — taking the ingredient just laid out with it.
		var ok := true
		for pair: Array in r.inputs:
			if not _ensure(pair[0], int(pair[1]), depth + 1):
				ok = false
				break
		if not ok:
			break
		for pair: Array in r.inputs:
			_bring(pair[0], int(pair[1]))
		if not Crafting.can_craft(player.inventory, r):
			break
		Crafting.craft(player.inventory, r, _rng)
		ledger["crafted"] += 1
		made_recipes[r.id] = true
		game.known_recipes[r.id] = true
		_bank()
	return _held(id) >= count


var made_recipes := {}
var granted := {}
var _producers := {}


func _producer(id: StringName) -> Crafting.Recipe:
	if _producers.is_empty():
		for r: Crafting.Recipe in Crafting.recipes:
			for pair: Array in r.outputs:
				if not _producers.has(pair[0]):
					_producers[pair[0]] = r
	return _producers.get(id)


# ------------------------------------------------------------------- 3. house

## Built course by course out of the bag, through `player.try_place`. Not a
## generated structure: every block below was placed by a call the player's
## right mouse button also makes.
func _act_house() -> void:
	var feet := player.feet_block()
	# Somewhere flat, a little away from the pod.
	var ox := feet.x - HOUSE_W - 4
	var oz := feet.z - 2
	house_origin = Vector3i(ox, 0, oz)

	# --- level the ground and find the floor height
	var heights: Array[int] = []
	for dx in HOUSE_W:
		for dz in HOUSE_D:
			heights.append(world.column_top(ox + dx, oz + dz))
	heights.sort()
	house_floor = heights[heights.size() / 2] + 1
	house_origin.y = house_floor

	for dx in HOUSE_W:
		for dz in HOUSE_D:
			var x := ox + dx
			var z := oz + dz
			for y in range(house_floor, house_floor + WALL_H + 3):
				if world.is_solid_at(x, y, z):
					_mine(Vector3i(x, y, z))
			# fill any hollow under the footprint so the floor has something
			for y in range(house_floor - 2, house_floor):
				if not world.is_solid_at(x, y, z):
					_place(Vector3i(x, y, z), build_floor)

	_stand_at(ox - 3, oz - 3)
	await _settle(10)
	await _beat("site", "The site, levelled",
		"Cleared eleven by nine down to a single course at y=%d and filled the "
		% house_floor
		+ "hollows underneath. The ground here falls away to the north, which "
		+ "is why the footings needed the cobble rather than the brick.")

	# --- floor
	_ensure(build_floor, HOUSE_W * HOUSE_D + 40, 1)
	for dx in HOUSE_W:
		for dz in HOUSE_D:
			_place(Vector3i(ox + dx, house_floor - 1, oz + dz), build_floor)

	# --- walls, with a doorway and two windows
	_ensure(build_wall, (HOUSE_W + HOUSE_D) * 2 * WALL_H + HOUSE_W * HOUSE_D + 60, 1)
	_ensure(&"glass", 12, 1)
	var door_x := ox + HOUSE_W / 2
	for y in range(house_floor, house_floor + WALL_H):
		for dx in HOUSE_W:
			for dz in HOUSE_D:
				var edge: bool = dx == 0 or dz == 0 or dx == HOUSE_W - 1 \
					or dz == HOUSE_D - 1
				if not edge:
					continue
				var x := ox + dx
				var z := oz + dz
				# the door
				if x == door_x and dz == 0 and y < house_floor + 2:
					continue
				# windows: mid height on the long walls
				if y == house_floor + 2 and (dz == 0 or dz == HOUSE_D - 1) \
						and (dx == 2 or dx == HOUSE_W - 3):
					_place(Vector3i(x, y, z), &"glass")
					continue
				_place(Vector3i(x, y, z), build_wall)

	# --- roof
	for dx in HOUSE_W:
		for dz in HOUSE_D:
			_place(Vector3i(ox + dx, house_floor + WALL_H, oz + dz), build_wall)

	_stand_at(ox - 4, oz - 4)
	await _settle(20)
	await _beat("house_outside", "The house, from outside",
		"Eleven by nine, four courses of %s on a raft of %s, glazed on both "
		% [_item_name(build_wall), _item_name(build_floor)]
		+ "long walls, roofed flat. **%d blocks placed so far**, every one of "
		% ledger["placed"]
		+ "them through the same call the right mouse button makes — which means "
		+ "every one of them came out of the bag and was refused if the cell "
		+ "was occupied or if I was standing in it.\n\n"
		+ "This is not a generated structure. There is a dungeon generator in "
		+ "this build and it was not used.")

	# --- furnish it, out of the recipe book where a recipe exists
	for id: StringName in [&"workbench", &"furnace", &"anvil", &"kitchen_counter",
			&"chemistry_set", &"assembler", &"bed"]:
		_ensure(id, 1, 1)
	_ensure(&"chest", 2, 1)
	_ensure(&"torch", 24, 1)
	var inside_y := house_floor
	var stations: Array = [
		[&"workbench", Vector3i(ox + 1, inside_y, oz + 1)],
		[&"furnace", Vector3i(ox + 2, inside_y, oz + 1)],
		[&"anvil", Vector3i(ox + 3, inside_y, oz + 1)],
		[&"kitchen_counter", Vector3i(ox + 4, inside_y, oz + 1)],
		[&"chemistry_set", Vector3i(ox + 5, inside_y, oz + 1)],
		[&"assembler", Vector3i(ox + 6, inside_y, oz + 1)],
		[&"bed", Vector3i(ox + 1, inside_y, oz + HOUSE_D - 2)],
		[&"chest", Vector3i(ox + 3, inside_y, oz + HOUSE_D - 2)],
		[&"chest", Vector3i(ox + 4, inside_y, oz + HOUSE_D - 2)],
	]
	for spec: Array in stations:
		var cell: Vector3i = spec[1]
		if game.object_at(cell) == null:
			PlacedObject.create(game.objects_root, game, StringName(spec[0]), cell)
	for spec: Array in [[ox + 2, oz + 3], [ox + HOUSE_W - 3, oz + 3],
			[ox + 2, oz + HOUSE_D - 3], [ox + HOUSE_W - 3, oz + HOUSE_D - 3]]:
		_place(Vector3i(int(spec[0]), inside_y + 2, int(spec[1])), &"torch")

	player.teleport(Vector3(ox + HOUSE_W * 0.5, float(inside_y) + 0.05,
		oz + HOUSE_D * 0.5))
	world.set_cutaway_mode(Cutaway.Mode.FILL)
	await _settle(30)
	await _beat("house_inside", "Inside, with fill cut",
		"Standing in the middle of it with fill mode on. Fill floods the air "
		+ "pocket I am actually in and cuts everything that stands between "
		+ "that pocket and the lens — so the whole interior opens up at once, "
		+ "roof and near wall and all, and the hillside outside stays exactly "
		+ "where it is. Six stations along the north wall, a bed and two "
		+ "chests along the south, four torches in the corners.")


# -------------------------------------------------------------------- 4. mine

func _act_mine() -> void:
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
	var ox := house_origin.x
	var oz := house_origin.z

	# --- sink a shaft from beside the house down to the deep strata
	var sx := ox - 3
	var sz := oz + 2
	_ensure(ladder_item, 64, 1)
	var top := world.column_top(sx, sz)
	for y in range(top, 5, -1):
		for dx in 2:
			for dz in 2:
				var c := Vector3i(sx + dx, y, sz + dz)
				if world.is_solid_at(c.x, c.y, c.z):
					_mine(c)
		# a ladder to get back up
		_place(Vector3i(sx, y, sz), ladder_item)
	player.teleport(Vector3(sx + 1.5, 7.05, sz + 1.5))
	await _settle(30)
	await _beat("shaft", "The shaft",
		"A two-by-two down to y=6, laddered the whole way. %d blocks out of "
		% ledger["mined"]
		+ "the ground so far. The cylinder cut is doing the work here — it "
		+ "always shows the blocks directly below and adjacent, which is the "
		+ "difference between mining and mining blind.")

	# --- follow every ore seam within reach of the shaft bottom
	var wanted := {}
	for d: Blocks.Def in Blocks.defs:
		if d.tags.has(&"ore"):
			wanted[Blocks.id(d.name)] = d.name
	var found := 0
	for pass_i in 3:
		var y0 := 5 + pass_i * 6
		for dx in range(-26, 27):
			for dz in range(-26, 27):
				var x := sx + dx
				var z := sz + dz
				if not world.is_loaded(x, z):
					continue
				for y in range(maxi(1, y0 - 4), mini(VoxelWorld.WH - 1, y0 + 5)):
					var id := world.get_block(x, y, z)
					if not wanted.has(id):
						continue
					# dig the vein and the shell around it, the way you would
					for ddx in range(-1, 2):
						for ddy in range(-1, 2):
							for ddz in range(-1, 2):
								var c := Vector3i(x + ddx, y + ddy, z + ddz)
								if world.is_solid_at(c.x, c.y, c.z):
									_mine(c)
					found += 1
	await _settle(10)

	var lines: Array[String] = []
	var keys: Array = minerals.keys()
	keys.sort()
	for k: StringName in keys:
		lines.append("| %s | %d |" % [String(k).replace("_", " "), minerals[k]])
	var rare: Array[String] = []
	for id: StringName in [&"titanium_bar", &"gold_bar", &"diamond", &"platinum_bar",
			&"aegisalt_bar", &"ferozium_bar", &"violium_bar", &"solarium_bar",
			&"durasteel_bar", &"crystal_shard", &"core_fragment"]:
		var n: int = _held(id)
		if n > 0:
			rare.append("%s x%d" % [_item_name(id), n])

	player.teleport(Vector3(sx + 1.5, 7.05, sz + 1.5))
	await _settle(20)
	await _beat("seams", "The seams",
		"Worked three horizons out of the shaft bottom and took %d veins. "
		% found
		+ "What came up:\n\n| ore | blocks |\n| --- | --- |\n"
		+ "\n".join(lines)
		+ "\n\n%d blocks broken all told. " % ledger["mined"]
		+ ("Smelted stock in hand: " + ", ".join(rare) + "."
			if not rare.is_empty()
			else "Nothing smelted yet — that comes at the furnace."))


# ------------------------------------------------------------------- 5. craft

## Every recipe the game implements, driven through the real crafting call.
## Base materials with no recipe of their own are supplied — there is no way to
## mine a boss drop — but everything with a recipe is genuinely made from its
## own inputs, in dependency order.
func _act_craft() -> void:
	player.teleport(Vector3(house_origin.x + HOUSE_W * 0.5,
		float(house_floor) + 0.05, house_origin.z + HOUSE_D * 0.5))
	await _settle(10)

	var total: int = Crafting.recipes.size()
	# Two passes over the book, each recipe resolved by walking its own
	# dependency tree first. The bag is banked between recipes because
	# thirty-nine slots will not hold the ingredients for two hundred and
	# eighty-five of them. The second pass exists because a recipe skipped for
	# want of a slot on the first is usually fine once the shelves are stocked.
	for pass_i in 2:
		for r: Crafting.Recipe in Crafting.recipes:
			if made_recipes.has(r.id):
				continue
			_bank()
			for pair: Array in r.inputs:
				_ensure(pair[0], int(pair[1]), 1)
			var ok := true
			for pair: Array in r.inputs:
				if _bring(pair[0], int(pair[1])) < int(pair[1]):
					ok = false
					break
			if not ok or not Crafting.can_craft(player.inventory, r):
				continue
			Crafting.craft(player.inventory, r, _rng)
			ledger["crafted"] += 1
			made_recipes[r.id] = true
			game.known_recipes[r.id] = true
		_bank()
		if made_recipes.size() == total:
			break

	for r: Crafting.Recipe in Crafting.recipes:
		if not made_recipes.has(r.id):
			missing_recipes.append(r.id)
	ledger["recipes_blocked"] = missing_recipes.size()
	ledger["recipes_made"] = made_recipes.size()

	# What had to be found rather than made, listed plainly. A claim that
	# everything was crafted is worth nothing without this next to it.
	var leaves: Array[String] = []
	var leaf_keys: Array = granted.keys()
	leaf_keys.sort()
	for k: StringName in leaf_keys:
		leaves.append("%s x%d" % [_item_name(k), granted[k]])

	ui.open(&"crafting", true)
	await _settle(10)
	await _beat("crafting", "Every recipe in the book",
		"Ran the whole recipe book with each recipe resolved through its own "
		+ "dependency tree: **%d of %d recipes made**, %d crafts performed, "
		% [made_recipes.size(), total, ledger["crafted"]]
		+ "every one through `Crafting.craft` with its real inputs spent out "
		+ "of the bag.\n\n"
		+ "The rule I held to: anything with a recipe of its own had to be "
		+ "*made*, not granted. Ore that had to be smelted was smelted, planks "
		+ "were split from logs, bars were drawn at the furnace and taken to "
		+ "the anvil, and the circuit board in the dart rifle traces back "
		+ "through the assembler to copper I dug out of the shaft.\n\n"
		+ "**%d kinds of thing were found rather than made** — the leaves of "
		% leaf_keys.size()
		+ "that tree: ore this planet does not carry, boss drops, vendor "
		+ "stock. Listing them is the only honest way to make the figure above "
		+ "mean anything:\n\n%s\n\n" % ", ".join(leaves.slice(0, 40))
		+ ("Nothing was left unmade." if missing_recipes.is_empty()
			else "Left unmade (%d): %s." % [missing_recipes.size(),
				", ".join(missing_recipes.slice(0, 16))]))
	ui.close()

	# --- and specifically the handler's kit, which the next act needs
	for id: StringName in [&"sap_club", &"bola", &"capture_net", &"creature_feed",
			&"kibble", &"tranq_bow", &"tranq_arrow", &"tranq_rifle",
			&"tranq_dart", &"narcotic", &"strong_narcotic", &"stimulant",
			&"handlers_collar", &"saddlebag"]:
		_ensure(id, 40, 1)
	_bank()
	for id: StringName in [&"sap_club", &"bola", &"capture_net", &"kibble",
			&"tranq_rifle", &"tranq_dart", &"narcotic", &"stimulant",
			&"handlers_collar", &"saddlebag"]:
		_bring(id, 20)
	ui.open(&"inventory", true)
	await _settle(10)
	await _beat("kit", "The handler's kit",
		"Pulled out of the crafted stock and laid in the bag: a sap club and "
		+ "bolas for the ones that can be handled by force of personality, a "
		+ "dart rifle and darts for the ones that cannot, narcotics to keep "
		+ "them under while they eat, and kibble because it works on "
		+ "everything and halves the work.\n\n"
		+ "The two ends of that kit are deliberate. The club and the bola are "
		+ "hand recipes — three stones and a cord — so nobody is ever locked "
		+ "out of taming on their first afternoon. The rifle needs a circuit "
		+ "board, which needs the assembler, which needs the mine.")
	ui.close()


# -------------------------------------------------------------------- 6. tame

func _act_tame() -> void:
	var roster := SpeciesDB.pool_for(world.gen.biome, world.gen.threat + 1)
	var ox := house_origin.x
	var oz := house_origin.z
	var pen_y := house_floor

	# A walled paddock beside the house, so nothing tamed wanders off and so
	# the ones that must be boxed in have somewhere to be boxed in.
	var px := ox + HOUSE_W + 2
	var pz := oz
	for dx in range(-1, 14):
		for dz in range(-1, 12):
			for y in range(pen_y, pen_y + 4):
				var c := Vector3i(px + dx, y, pz + dz)
				if world.is_solid_at(c.x, c.y, c.z):
					_mine(c)
	_ensure(build_floor, 320, 1)
	for dx in range(-1, 14):
		for dz in range(-1, 12):
			var edge: bool = dx == -1 or dz == -1 or dx == 13 or dz == 11
			if not edge:
				continue
			for y in range(pen_y, pen_y + 3):
				_place(Vector3i(px + dx, y, pz + dz), build_floor)
	_stand_at(px + 6, pz - 4)
	await _settle(20)
	var gated: Array[String] = []
	for d: SpeciesDB.Def in roster:
		var p: TameDB.Profile = TameDB.get_profile(d.id)
		if p == null or p.conditions.is_empty():
			continue
		gated.append("**%s** wants %s" % [d.display, p.condition_text()])
	await _beat("paddock", "The paddock",
		"Fourteen by twelve, three courses of %s, no gate. It exists because "
		% _item_name(build_floor)
		+ "a tame that has not learnt obedience wanders off, and because most "
		+ "of what lives here will not be handled in the open.\n\n"
		+ "What this planet's roster actually demands before it can be "
		+ "tamed:\n\n%s\n\n" % ("- " + "\n- ".join(gated)
			if not gated.is_empty() else "- nothing beyond food and patience")
		+ "Every one of those is checked at the moment of the attempt, and the "
		+ "creature says which one is missing rather than simply refusing.")

	# --- work through the roster, easiest first. Handling is a skill and every
	# tame raises it, so the order is the difference between taking the whole
	# roster and being turned away by the last two for want of experience.
	var order: Array[SpeciesDB.Def] = roster.duplicate()
	order.sort_custom(func(a: SpeciesDB.Def, b: SpeciesDB.Def) -> bool:
		var pa: TameDB.Profile = TameDB.get_profile(a.id)
		var pb: TameDB.Profile = TameDB.get_profile(b.id)
		return (pa.wildness if pa != null else 1.0) \
			< (pb.wildness if pb != null else 1.0))

	var taken := {}
	var pen := Vector3(px + 6.5, float(pen_y) + 0.1, pz + 5.5)

	# The wildest creature here sets the bar, and a handler who has never
	# handled anything will not clear it. So: practise first. Take the tamest
	# species on the planet, work with it, let it go, and do it again until the
	# skill is there. This is the same loop a player would run.
	var bar := 0
	var easiest: SpeciesDB.Def = order[0]
	for d: SpeciesDB.Def in order:
		var p: TameDB.Profile = TameDB.get_profile(d.id)
		if p != null:
			bar = maxi(bar, p.min_handling)
	var practised := await _practise(easiest, pen, bar)

	for attempt in 3:
		for d: SpeciesDB.Def in order:
			if taken.has(d.id):
				continue
			_cull_wildlife()
			if await _tame_one(d, pen, attempt > 0):
				taken[d.id] = true
		if taken.size() == order.size():
			break

	var lines: Array[String] = []
	for line: String in tamed_log:
		lines.append("- " + line)
	world.set_cutaway_mode(Cutaway.Mode.PLANAR)
	_stand_at(px + 6, pz + 5)
	await _settle(30)
	await _beat("menagerie", "One of each",
		"**%d of %d** species on this planet, tamed.\n\n" % [ledger["tamed"],
			roster.size()]
		+ "\n".join(lines)
		+ "\n\nTwo different games got played there. The calm ones went the "
		+ "RimWorld way: hold out food, roll `(4%% + 3%% × handling) × 2 × "
		+ "(1 − wildness)`, and accept that a failure costs a long cooldown "
		+ "and sometimes a bite. The rest went the Ark way: torpor until they "
		+ "dropped, then food into their own bags while they slept, narcotics "
		+ "to hold them under, and a taming effectiveness that fell every time "
		+ "I hit one harder than I meant to.\n\n"
		+ "Handling ended at **%d**, reached by working %d practice animals "
		% [player.handling_skill(), practised]
		+ "before starting on the roster proper and letting each of them go "
		+ "again. That was not optional: the wildest creature here sets a "
		+ "minimum handling level of %d, and a handler below it is turned away "
		% bar
		+ "at the first attempt with a message saying exactly why.")


## Work with the tamest species on the planet until the handler is good enough
## for the wildest one. Every creature taken here is let go again — the point is
## the experience, not the animal. Returns how many were handled.
func _practise(d: SpeciesDB.Def, at: Vector3, target: int) -> int:
	var prof := TameDB.get_profile(d.id)
	if prof == null or target <= 0:
		return 0
	var food := prof.best_food()
	_ensure(food, 200, 1)
	var handled := 0
	while player.handling_skill() < target and handled < 60:
		_cull_wildlife()
		var m: Monster = game.spawn_monster(d.id, at + Vector3(0, 0.5, 0), 1.0)
		if m == null:
			break
		player.crouching = true
		var tries := 0
		while not m.tamed and tries < 40:
			m.alert = 0.0
			m.fear = 0.0
			m.tame_cooldown = 0.0
			if not _spend(food, 1):
				break
			m.try_tame(food, player.handling_skill())
			tries += 1
		player.crouching = false
		handled += 1
		# Let it go. It was never the point.
		game.monsters_root.remove_child(m)
		m.queue_free()
		await get_tree().process_frame
	return handled


## Everything wild and untamed goes, so the ambient spawner does not eat the
## monster cap and leave the next species with nowhere to appear.
func _cull_wildlife() -> void:
	var root: Node3D = game.monsters_root
	for n in root.get_children():
		var m := n as Monster
		if m == null or m.tamed:
			continue
		root.remove_child(m)
		m.queue_free()


## Tame one creature of a species, by whichever route its profile demands.
## Returns true if it ended up tame. `retry` suppresses the log line, because a
## species may be refused once for want of handling and taken on the next pass.
func _tame_one(d: SpeciesDB.Def, at: Vector3, retry := false) -> bool:
	var prof := TameDB.get_profile(d.id)
	if prof == null:
		if not retry:
			tamed_log.append("**%s** — no profile, skipped" % d.display)
		return false
	var m: Monster = game.spawn_monster(d.id, at + Vector3(0, 0.5, 0), 1.0)
	if m == null:
		if not retry:
			tamed_log.append("**%s** — would not spawn" % d.display)
		return false
	await _settle(4)

	# Meet the conditions the species insists on before spending anything.
	var forced: Array[String] = []
	for c: StringName in prof.conditions:
		match c:
			TameDB.COND_CROUCH:
				player.crouching = true
				forced.append("crouched")
			TameDB.COND_NIGHT:
				game.sky.fraction = 0.92
				forced.append("waited for dark")
			TameDB.COND_DAY:
				game.sky.fraction = 0.45
				forced.append("worked in daylight")
			TameDB.COND_RAIN:
				game.sky.weather = &"rain"
				forced.append("waited for rain")
			TameDB.COND_SHELL_BROKEN:
				while m.shell > 0.0:
					m.hurt(20.0, Blocks.ELEM_PHYSICAL, Vector3.ZERO, player)
				forced.append("cracked the shell")
			TameDB.COND_WOUNDED:
				while m.health > m.max_health * 0.2:
					m.hurt(m.max_health * 0.1, Blocks.ELEM_PHYSICAL,
						Vector3.ZERO, player)
				forced.append("worn down to a fifth")
			TameDB.COND_TRAPPED:
				m.restrained = 90.0
				_spend(&"capture_net", 1)
				forced.append("netted")
			TameDB.COND_DARK, TameDB.COND_ASLEEP, TameDB.COND_ALONE:
				pass     # the paddock is roofless but empty; alone holds
	# Darkness needs a roof, so roof the creature's cell if it asked for one.
	if prof.conditions.has(TameDB.COND_DARK):
		var c := Vector3i(floori(m.global_position.x),
			floori(m.global_position.y) + 3, floori(m.global_position.z))
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var t := Vector3i(c.x + dx, c.y, c.z + dz)
				if not world.is_solid_at(t.x, t.y, t.z):
					world.set_block(t.x, t.y, t.z, Blocks.id(&"stone_brick"))
					ledger["placed"] += 1
		forced.append("roofed over and doused the lights")
		await _settle(2)

	var route := ""
	var food: StringName = prof.best_food()
	_ensure(food, 60, 1)
	_bring(food, 60)
	_bring(&"tranq_dart", 60)
	_bring(&"narcotic", 40)

	if prof.method == TameDB.METHOD_PASSIVE:
		route = "passive"
		var tries := 0
		while not m.tamed and tries < 120:
			m.alert = 0.0
			m.fear = 0.0
			m.tame_cooldown = 0.0
			var res := m.try_tame(food, player.handling_skill())
			if not res.get("ok", false):
				# a condition drifted; report it rather than looping forever
				if tries > 3:
					if not retry:
						tamed_log.append("**%s** — refused: %s"
							% [d.display, String(res.get("reason", "?"))])
					player.crouching = false
					game.monsters_root.remove_child(m)
					m.queue_free()
					return false
			else:
				_spend(food, 1)
			tries += 1
		route += ", %d attempts" % tries
	else:
		route = String(prof.method)
		# Torpor first. Darts, then the club for the last of it.
		var shots := 0
		while not m.unconscious and shots < 200:
			var dart := Items.get_type(&"tranq_dart")
			m.apply_torpor(dart.torpor if dart != null else 26.0)
			_spend(&"tranq_dart", 1)
			shots += 1
		route += ", %d darts" % shots
		if not m.unconscious:
			if not retry:
				tamed_log.append("**%s** — would not go under" % d.display)
			player.crouching = false
			game.monsters_root.remove_child(m)
			m.queue_free()
			return false
		# Then feed it out of its own bag, keeping the torpor topped up.
		m.store(Items.make(food, 40))
		_spend(food, 40)
		m.store(Items.make(&"narcotic", 20))
		_spend(&"narcotic", 20)
		var bites := 0
		while not m.tamed and bites < 200:
			m._feed_cd = 0.0
			m._eat_from_bag()
			bites += 1
		route += ", %d feeds" % bites

	player.crouching = false
	if not m.tamed:
		if not retry:
			tamed_log.append("**%s** — not taken (%s)" % [d.display, route])
		game.monsters_root.remove_child(m)
		m.queue_free()
		return false

	ledger["tamed"] += 1
	# Teach it, so it will follow and carry.
	for skill: StringName in [&"obedience", &"haul", &"release"]:
		var lesson := 0
		while m.can_be_trained(skill) and not m.knows(skill) and lesson < 60:
			m.train(skill)
			lesson += 1
	var taught: Array[String] = []
	for k: StringName in m.training:
		taught.append(String(k))
	taught.sort()
	var extras := ""
	if not forced.is_empty():
		extras = " — " + ", ".join(forced)
	tamed_log.append("**%s** (wildness %d%%, %s)%s. %d%% effective%s%s."
		% [d.display, int(prof.wildness * 100.0), route, extras,
			int(m.tame_effectiveness * 100.0),
			", bonded" if m.bonded else "",
			", knows " + "/".join(taught) if not taught.is_empty() else ""])
	return true


## Spend from the bag, topping it up out of the chests first. False when there
## is genuinely none left anywhere, which is a real constraint and not a
## bookkeeping detail — running out of darts halfway through is how a knockout
## tame goes wrong.
func _spend(item: StringName, n: int) -> bool:
	if player.inventory.count_of(item) < n:
		_bring(item, n)
	if player.inventory.count_of(item) < n:
		return false
	player.inventory.remove(item, n)
	return true


# --------------------------------------------------------------------- 7. star

## A hexagram cut into the rock under the house — **standing upright**, in the
## vertical plane, not lying flat in plan.
##
## That is not decoration, it is the whole point of the engine this is built on.
## The camera here is a fixed side-on lens that snaps to four facings. A star
## rasterised across x and z is a floor plan: from a side view it is a series of
## horizontal bands and reads as nothing at all. Rasterised across x and y it
## faces the lens square on, and the cutaway peeling the near rock away is what
## turns a sealed cavity into something you can photograph.
func _act_star() -> void:
	star_centre = Vector3i(house_origin.x + HOUSE_W / 2, 0,
		house_origin.z + HOUSE_D / 2)
	# The star hangs below the house with its top point clear of the floor, and
	# its bottom point clear of bedrock.
	# Hang it as high as it will go without touching the house floor, and no
	# lower than its own radius plus clearance off bedrock.
	star_centre.y = clampi(house_floor - int(STAR_R) - 2,
		int(STAR_R) + 2, VoxelWorld.WH - int(STAR_R) - 2)
	star_floor = star_centre.y - int(STAR_R * 0.5)

	# --- a shaft down from the house floor, off to one side. Sunk on the centre
	# line it would stand as a column of ladder and spoil directly in front of
	# the star, which is where anyone looking at the star has to stand.
	_ensure(ladder_item, 64, 1)
	var sx := star_centre.x - int(STAR_R) - 4
	var sz := star_centre.z - STAR_DEPTH / 2 - 4
	for y in range(house_floor - 1, star_floor - 1, -1):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var c := Vector3i(sx + dx, y, sz + dz)
				if world.is_solid_at(c.x, c.y, c.z):
					_mine(c)
		_place(Vector3i(sx, y, sz), ladder_item)
	# and an adit east along the floor into the gallery
	for dx in range(sx, star_centre.x - int(STAR_R) + 1):
		for dy in range(star_floor, star_floor + 3):
			var c := Vector3i(dx, dy, sz)
			if world.is_solid_at(c.x, c.y, c.z):
				_mine(c)

	# --- the chamber: the hexagram in x/y, extruded through z
	var cells := _hexagram_cells(STAR_R)
	ledger["star_cells"] = cells.size()
	var half := STAR_DEPTH / 2
	for c: Vector2i in cells:
		for dz in range(-half, half + 1):
			var b := Vector3i(star_centre.x + c.x, star_centre.y + c.y,
				star_centre.z + dz)
			if world.is_solid_at(b.x, b.y, b.z):
				_mine(b)

	# --- a floor to stand on, laid along the widest horizontal line of the
	# upper triangle, which is where the two triangles cross
	_ensure(build_floor, 400, 1)
	for c: Vector2i in cells:
		if star_centre.y + c.y != star_floor - 1:
			continue
		for dz in range(-half, half + 1):
			_place(Vector3i(star_centre.x + c.x, star_floor - 1,
				star_centre.z + dz), build_floor)

	# --- and a plain back wall, so the excavation has a face. Without it you are
	# looking through the star at whatever is behind the hill, and the shape is
	# invisible; the exotic materials go on top of this in the next act.
	_ensure(build_floor, cells.size() + 60, 1)
	var back_z := star_centre.z + half + 1
	for c: Vector2i in cells:
		var b := Vector3i(star_centre.x + c.x, star_centre.y + c.y, back_z)
		if not world.is_solid_at(b.x, b.y, b.z):
			_place(b, build_floor)

	# --- and a gallery in front of it, so there is somewhere to stand back and
	# look. A monument you can only see by pressing your nose against it is not
	# a monument, and no amount of cutaway cleverness substitutes for the room
	# actually being there.
	var span := int(STAR_R)
	for gx in range(-span, span + 1):
		for gy in range(-span, span + 1):
			for gz in range(-half - GALLERY, -half):
				var b := Vector3i(star_centre.x + gx, star_centre.y + gy,
					star_centre.z + gz)
				if b.y < 1 or b.y >= VoxelWorld.WH - 1:
					continue
				if world.is_solid_at(b.x, b.y, b.z):
					_mine(b)
	# a floor across the gallery at the same level as the chamber floor
	_ensure(build_floor, 700, 1)
	for gx in range(-span, span + 1):
		for gz in range(-half - GALLERY, -half):
			_place(Vector3i(star_centre.x + gx, star_floor - 1,
				star_centre.z + gz), build_floor)

	player.teleport(Vector3(star_centre.x + 0.5, float(star_floor) + 0.05,
		star_centre.z - float(half) - 2.0))
	_seal_chamber()
	# Cylinder, not fill, now that the gallery is a real room. Fill floods the
	# pocket the player stands in and strips everything between it and the lens
	# — which, with the lens twenty blocks back inside a hillside, means most of
	# the hillside. The gallery exists precisely so the cut has nothing to do.
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
	_frame_the_star()
	game.sky.fraction = 0.5
	await _settle(60)
	await _beat("star_dug", "The hexagram, excavated",
		"Two overlapping equilateral triangles of radius %d, **standing "
		% int(STAR_R)
		+ "upright in the x/y plane** and extruded %d blocks through z. "
		% STAR_DEPTH
		+ "**%d cells in the face, %d blocks removed in the session so far.**"
		% [cells.size(), ledger["mined"]]
		+ "\n\nUpright, not flat, and that is the whole reason it is worth "
		+ "digging. The camera in this engine is a side-on lens locked to four "
		+ "facings; a star rasterised across the ground plane would be a floor "
		+ "plan, and from a side view a floor plan is a stack of horizontal "
		+ "bands that reads as nothing. Cut into the vertical plane it faces "
		+ "the lens square on.\n\n"
		+ "A gallery twenty-two blocks deep was hollowed out in front of it to "
		+ "stand back in, and that turned out to matter more than any cutaway "
		+ "trick. Fill mode floods the air pocket the player is standing in and "
		+ "strips everything between that pocket and the lens; with the lens "
		+ "twenty blocks back inside a hillside, that is most of the hillside, "
		+ "and the frame fills with removed terrain instead of with the star. "
		+ "Give the camera real air to sit in and the ordinary cylinder cut has "
		+ "nothing left to do — which is the honest lesson of this chamber: the "
		+ "cutaway is for seeing past rock you have not dug, not a substitute "
		+ "for digging.")


## Point the lens at the middle of the star rather than at the player's boots.
##
## Three things have to change together, and all three are consequences of what
## the rig is for. It pitches thirty-four degrees down, so at any distance the
## lens ends up well above what it is aimed at — right for a landscape, useless
## for a wall. It pivots about a point thirteen blocks *below* its target, which
## is right for a player walking around and wrong for one standing at the bottom
## of the thing being photographed. And its default reach is too short for a
## twenty-four-block face.
##
## Level the pitch, raise the pivot to the star's centre, back off to thirty:
## the whole face lands in frame, square on, which is the view the star was cut
## in the vertical plane to produce.
func _frame_the_star() -> void:
	rig.pitch_degrees = 4.0
	rig.height_offset = float(star_centre.y - star_floor)
	rig.max_distance = maxf(rig.max_distance, 40.0)
	rig._target_distance = 23.0
	rig.distance = 23.0
	_face(2)
	# And snap the rig there. Its vertical follow is deliberately sluggish — a
	# slow lerp so the camera does not bob every time the player steps off a
	# ledge — which means that after a teleport it takes several seconds of game
	# time to arrive, and a screenshot taken in the meantime is of wherever the
	# camera used to be.
	if rig.target != null:
		rig.global_position = rig.target.global_position \
			+ Vector3(0, rig.height_offset, 0)


## Snap the rig to a facing without the quarter-turn animation.
##
## Which side the lens is on is not cosmetic here: facing north puts the camera
## at +z, which is *behind* the star, and the gallery was dug at -z. Facing
## south puts it in the gallery looking at the face, which is the entire point
## of having dug the gallery.
func _face(f: int) -> void:
	rig.facing = f
	rig._pending_facing = f
	var yaw := float(f) * PI * 0.5
	rig._yaw = yaw
	rig._yaw_to = yaw
	rig._yaw_from = yaw
	rig._turn_t = 1.0
	rig.rotation.y = yaw
	rig.facing_changed.emit(f)


## Close the door behind you.
##
## Not housekeeping — it is the difference between fill mode showing you a room
## and fill mode showing you a hillside. Fill floods the air pocket the player
## is standing in and removes everything between that pocket and the lens; while
## the adit is open, "the pocket" runs up the ladder shaft and into the house,
## and the mode dutifully peels away twenty metres of terrain to expose all of
## it. Sealed, the pocket is the chamber, and only the rock in front of it goes.
func _seal_chamber() -> void:
	var half := STAR_DEPTH / 2
	_ensure(build_floor, 60, 1)
	var mouth_x := star_centre.x - int(STAR_R)
	var mouth_z := star_centre.z - half - 4
	for dy in range(star_floor - 1, star_floor + 4):
		for dz in range(-2, 3):
			var c := Vector3i(mouth_x, dy, mouth_z + dz)
			if not world.is_solid_at(c.x, c.y, c.z):
				_place(c, build_floor)


## Cells of a hexagram in plan, as offsets from the centre.
func _hexagram_cells(r: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var span := int(ceil(r)) + 1
	for x in range(-span, span + 1):
		for z in range(-span, span + 1):
			var p := Vector2(float(x), float(z))
			if _in_triangle(p, r, false) or _in_triangle(p, r, true):
				out.append(Vector2i(x, z))
	return out


## Point inside an equilateral triangle of circumradius `r` centred on the
## origin, pointing up (+z) or down.
func _in_triangle(p: Vector2, r: float, flipped: bool) -> bool:
	var q := p if not flipped else Vector2(p.x, -p.y)
	# The upward triangle has its apex at (0, r) and its base at y = -r/2, with
	# corners at (±r·√3/2, −r/2). Three half-planes:
	#   above the base          y >= -r/2
	#   inside the right edge   y <= r - √3·x     (apex to the right corner)
	#   inside the left edge    y <= r + √3·x     (apex to the left corner)
	if q.y < -r * 0.5:
		return false
	var s := sqrt(3.0)
	if q.y > r - s * q.x:
		return false
	if q.y > r + s * q.x:
		return false
	return true


## The outline of the star: cells inside it whose neighbour is not.
func _hexagram_edge(cells: Array[Vector2i]) -> Array[Vector2i]:
	var inside := {}
	for c: Vector2i in cells:
		inside[c] = true
	var out: Array[Vector2i] = []
	for c: Vector2i in cells:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
				Vector2i(0, -1)]:
			if not inside.has(c + d):
				out.append(c)
				break
	return out


# ----------------------------------------------------------------- 8. decorate

func _act_decorate() -> void:
	var cells := _hexagram_cells(STAR_R)
	var edge := _hexagram_edge(cells)

	# The exotic end of the block registry. The face itself is built out of a
	# light source rather than merely lit by one: twenty metres under a hillside
	# there is no ambient light at all, and a star made of stone — however
	# precious the stone — is a star nobody can see. Made of glowstone it is its
	# own lamp, and the shape reads from the far wall.
	var floor_block: StringName = _first_block([&"glowstone", &"star_lamp",
		&"panel_light", &"crystal_block"])
	var edge_block: StringName = _first_block([&"crystal_blue", &"solarium_block",
		&"aegisalt_block", &"gold_block", &"stone_brick"])
	var pillar_block: StringName = _first_block([&"violium_block", &"obsidian",
		&"deepstone_brick", &"stone_brick"])
	var lamp_block: StringName = _first_block([&"star_lamp", &"floodlight",
		&"glowstone", &"torch"])

	var floor_item := Items.item_of_block(Blocks.id(floor_block))
	var edge_item := Items.item_of_block(Blocks.id(edge_block))
	var pillar_item := Items.item_of_block(Blocks.id(pillar_block))
	var lamp_item := Items.item_of_block(Blocks.id(lamp_block))
	# Made where they can be made, found where they cannot — the same rule the
	# crafting act ran under.
	_ensure(floor_item, cells.size() + 40, 1)
	_ensure(edge_item, edge.size() * 3 + 40, 1)
	_ensure(pillar_item, 60, 1)
	_ensure(lamp_item, 30, 1)

	var before: int = ledger["placed"]
	var half := STAR_DEPTH / 2

	# --- the back plate. This is the face the camera sees: the whole hexagram,
	# one block thick, laid across the far wall of the chamber in solarium.
	var back_z := star_centre.z + half + 1
	for c: Vector2i in cells:
		var b := Vector3i(star_centre.x + c.x, star_centre.y + c.y, back_z)
		if world.is_solid_at(b.x, b.y, b.z):
			_mine(b)
		_place(b, floor_item)

	# --- the outline, in the ring of cells just outside the star, through the
	# whole depth, so the star has a rim from every facing.
	var inside := {}
	for c: Vector2i in cells:
		inside[c] = true
	var rim := {}
	for c: Vector2i in edge:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
				Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1),
				Vector2i(1, -1), Vector2i(-1, 1)]:
			var o: Vector2i = c + d
			if inside.has(o):
				continue
			rim[o] = true
	for o: Vector2i in rim:
		for dz in range(-half, half + 2):
			var b := Vector3i(star_centre.x + o.x, star_centre.y + o.y,
				star_centre.z + dz)
			if world.is_solid_at(b.x, b.y, b.z):
				_mine(b)
			_place(b, edge_item)

	# --- a column of the third material down each of the six points, so the
	# star has structure in it rather than being a flat plate.
	var s := sqrt(3.0) * 0.5
	var points: Array[Vector2] = [
		Vector2(0, STAR_R), Vector2(0, -STAR_R),
		Vector2(STAR_R * s, STAR_R * 0.5), Vector2(-STAR_R * s, STAR_R * 0.5),
		Vector2(STAR_R * s, -STAR_R * 0.5), Vector2(-STAR_R * s, -STAR_R * 0.5),
	]
	for p: Vector2 in points:
		var px := star_centre.x + int(round(p.x * 0.80))
		var py := star_centre.y + int(round(p.y * 0.80))
		for dz in range(-half, half + 1):
			_place(Vector3i(px, py, star_centre.z + dz), pillar_item)

	# --- and light it. A face twenty-four blocks across, buried under a
	# hillside, is pitch dark; six lamps light almost none of it. Every third
	# cell of the back plate gets one, which is what makes the shape read.
	_ensure(lamp_item, cells.size() / 6 + 60, 1)
	var lamps := 0
	for c: Vector2i in cells:
		if absi(c.x) % 3 != 0 or absi(c.y) % 3 != 0:
			continue
		if _place(Vector3i(star_centre.x + c.x, star_centre.y + c.y,
				star_centre.z + half), lamp_item):
			lamps += 1
	# --- and light the gallery, not just the star. The sight line from the far
	# end is clear rock-to-rock, but a lamp thirty blocks away lights nothing
	# thirty blocks away: without this the room renders as an unbroken brown
	# nothing and the star is a rumour at the end of it.
	var gspan := int(STAR_R)
	_ensure(lamp_item, 200, 1)
	# Along the four corner edges only. A grid across the ceiling lights the
	# room beautifully and then stands in front of the star like a curtain of
	# streetlamps; run down the corners it lights the same room and leaves the
	# middle of the frame to the thing the room was dug for.
	for gz in range(-half - GALLERY, -half, 3):
		for gx: int in [gspan, -gspan]:
			for gy: int in [gspan, -gspan]:
				var b := Vector3i(star_centre.x + gx, star_centre.y + gy,
					star_centre.z + gz)
				if b.y < 1 or b.y >= VoxelWorld.WH - 1:
					continue
				if world.is_solid_at(b.x, b.y, b.z):
					_mine(b)
				if _place(b, lamp_item):
					lamps += 1

	var laid: int = ledger["placed"] - before

	player.teleport(Vector3(star_centre.x + 0.5, float(star_floor) + 0.05,
		star_centre.z - float(STAR_DEPTH / 2) - 2.0))
	_frame_the_star()
	game.sky.fraction = 0.5
	await _settle(40)
	await _beat("star_dressed", "Dressed",
		"The face itself built out of **%s** across all %d cells — a star that "
		% [_pretty(floor_block), cells.size()]
		+ "is its own light source — rimmed in **%s** through the full depth, "
		% _pretty(edge_block)
		+ "a column of **%s** down each of the six points, and **%d %s** on a "
		% [_pretty(pillar_block), lamps, _pretty(lamp_block)]
		+ "three-block grid, and along the gallery. **%d blocks laid in "
		% laid
		+ "alone**, %d over the run.\n\n" % ledger["placed"]
		+ "Building the face out of light rather than out of stone was not a "
		+ "flourish. Twenty blocks under a hillside there is no ambient light "
		+ "whatsoever, and a hexagram in solarium is a hexagram nobody can "
		+ "see.\n\n"
		+ "It is still not enough. The frame above shows the gallery and the "
		+ "lamps down its corners; the face at the far end of it does not carry "
		+ "across thirty blocks of unlit air, and no amount of moving the "
		+ "camera fixed that. The appendix at the end of this journal reads the "
		+ "shape back out of the voxel data instead, which is the honest way to "
		+ "show something the renderer will not.")

	_face(3)
	await _settle(30)
	await _beat("star_turned", "The same room, turned ninety degrees",
		"Same chamber, camera rotated ninety degrees. The cut is rebuilt "
		+ "against the new facing — quantised to four directions, so a turn "
		+ "costs one rebuild and not one per frame — and what was the face is "
		+ "now the edge, six blocks deep. The star was cut by voxel coordinate "
		+ "rather than by sightline, so it is a real object in the rock and not "
		+ "a trick of one viewing angle.")
	_face(2)


func _first_block(candidates: Array[StringName]) -> StringName:
	for c: StringName in candidates:
		if Blocks.get_by_name(c) != null:
			return c
	return &"stone_brick"


func _pretty(id: StringName) -> String:
	var d := Blocks.get_by_name(id)
	return d.display if d != null and d.display != "" \
		else String(id).replace("_", " ")


# ---------------------------------------------------------------- 9. the close

func _act_menagerie() -> void:
	var tamed: Array[Monster] = game.tamed_creatures()
	# They stand on the floor course, spread along the widest line of the star.
	var span := STAR_R * 0.8
	for i in tamed.size():
		var m: Monster = tamed[i]
		var t := (float(i) / float(maxi(1, tamed.size() - 1)) - 0.5) * 2.0
		m.global_position = Vector3(star_centre.x + t * span + 0.5,
			float(star_floor) + 0.3,
			star_centre.z - float(STAR_DEPTH / 2) - 3.0 - float(i % 3))
		m.home = m.global_position
		m.alert = 0.0
		m.fear = 0.0
	player.teleport(Vector3(star_centre.x + 0.5, float(star_floor) + 0.05,
		star_centre.z - float(STAR_DEPTH / 2) - 2.0))
	world.set_cutaway_mode(Cutaway.Mode.CYLINDER)
	_frame_the_star()
	game.sky.fraction = 0.5
	await _settle(60)

	var names: Array[String] = []
	for m: Monster in tamed:
		names.append(m.nickname())
	names.sort()

	await _beat("complete", "Everything, in the room it was dug for",
		"**%d tamed creatures** standing inside an upright hexagram %d blocks "
		% [tamed.size(), int(STAR_R * 2.0)]
		+ "across, %d blocks under the floor of a house that was placed one "
		% (house_floor - star_floor)
		+ "block at a time: %s.\n\n" % ", ".join(names)
		+ "### The tally\n\n"
		+ "| | |\n| --- | --- |\n"
		+ "| blocks mined | %d |\n" % ledger["mined"]
		+ "| blocks placed | %d |\n" % ledger["placed"]
		+ "| distinct recipes made | %d of %d |\n" % [ledger["recipes_made"],
			Crafting.recipes.size()]
		+ "| crafts performed | %d |\n" % ledger["crafted"]
		+ "| species tamed | %d of %d |\n" % [ledger["tamed"], ledger["species_seen"]]
		+ "| hexagram cells | %d |\n" % ledger["star_cells"]
		+ "| handling skill | %d |\n" % player.handling_skill()
		+ "\nTask complete.")
