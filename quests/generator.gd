## Procedural side quests, Starbound style: pick a template, find a target that
## actually exists on the planet you are standing on, scale the reward by the
## planet's threat level, and dress the whole thing in flavour text pulled from
## a phrase bank so two "kill six things" quests never read the same.
##
## Everything is driven by a seeded RNG (world seed + npc id + a counter), so the
## same villager offers the same board of quests across a save/load.
class_name QuestGenerator
extends RefCounted

enum Template { BOUNTY, GATHER, MINE, DELIVERY, EXPLORE, OBSERVE, SURVIVE, CRAFT, BUILD }

## Bumped every time a quest is minted; part of the seed so a giver's board
## rotates instead of repeating.
var counter: int = 0

var _rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------- phrase bank
const TITLE_BOUNTY: Array[String] = [
	"Culling the %s", "%s Trouble", "A Matter of %s", "Too Many %s",
	"The %s Problem", "Thinning the %s", "Bad Blood: %s",
]
const TITLE_GATHER: Array[String] = [
	"A Crate of %s", "%s, and Plenty of It", "Short on %s",
	"The %s Requisition", "Fetching %s", "%s for the Store",
]
const TITLE_MINE: Array[String] = [
	"Cut Deep for %s", "The %s Seam", "Pickaxe Work: %s", "Down After %s",
]
const TITLE_DELIVERY: Array[String] = [
	"Run This to %s", "A Parcel for %s", "%s Is Waiting", "The %s Errand",
]
const TITLE_EXPLORE: Array[String] = [
	"Chart the %s", "Nobody Goes to the %s", "Beyond the %s", "The %s Survey",
]
const TITLE_OBSERVE: Array[String] = [
	"Look Sideways", "The Wall That Isn't", "A Trick of the Plane",
	"Seen From the %s", "What the %s Hides", "Turn and Look Again",
]
const TITLE_SURVIVE: Array[String] = [
	"Hold the Line", "Nightwatch", "Stand Your Ground", "Weather It Out",
]
const TITLE_CRAFT: Array[String] = [
	"Bench Work: %s", "Make Me a %s", "The %s Order", "Hands and Hammer",
]
const TITLE_BUILD: Array[String] = [
	"Raise a Wall of %s", "Masonry: %s", "Build It in %s",
]

const OPENERS: Array[String] = [
	"Look, I'll be straight with you.",
	"You've the look of someone who can handle themselves.",
	"Don't suppose you're for hire?",
	"Everyone else here has an excuse. You don't, yet.",
	"I'd do it myself, but my knees are older than this colony.",
	"You're new. New is useful.",
	"Word travels. You're the one who dropped out of the sky, aren't you?",
	"I'll keep it short, I've bread in the oven.",
]
const CLOSERS: Array[String] = [
	"Do that and I'll see you paid.",
	"There's pixels in it, and my goodwill, which is worth more.",
	"Come back whole and we'll settle up.",
	"I'm good for the money. Ask anyone. Don't ask %s.",
	"Bring it back and the drinks are on the house.",
	"Simple as that. Simple isn't easy, mind.",
]
const GRATITUDE: Array[String] = [
	"That's the one. You've a knack for this.",
	"Faster than I'd have managed. Take your cut.",
	"Well. I'll stop doubting off-worlders.",
	"You made that look tidy. Here.",
	"I'd shake your hand but mine's covered in grease. Payment instead.",
]
const HAZARD_WORDS: Array[String] = [
	"nasty", "vicious", "twitchy", "unpleasant", "hungry", "territorial",
]
const PLACE_WORDS: Array[String] = [
	"hollow", "reach", "flats", "shelf", "cut", "drift", "verge", "bowl",
]


# =========================================================================
## Rolls one quest for [param npc]. Returns null when the planet offers nothing
## the templates can key off.
func generate(npc: Node, quest_seed: int = 0) -> QuestDef:
	counter += 1
	var giver_id := StringName(npc.get("npc_id")) if npc != null else &"anonymous"
	var base := quest_seed if quest_seed != 0 else (Game.run_seed ^ hash(giver_id) ^ (counter * 2654435761))
	_rng.seed = base
	var threat := _threat()
	var order := _templates_for(npc)
	order.shuffle()
	for t: Template in order:
		var q := _build(t, npc, giver_id, threat)
		if q != null:
			return q
	return null


func _templates_for(npc: Node) -> Array[Template]:
	var role := String(npc.get("role_id")) if npc != null else ""
	match role:
		"merchant", "trader":
			return [Template.GATHER, Template.DELIVERY, Template.MINE, Template.EXPLORE]
		"blacksmith":
			return [Template.MINE, Template.CRAFT, Template.GATHER, Template.BUILD]
		"guard":
			return [Template.BOUNTY, Template.SURVIVE, Template.EXPLORE]
		"doctor":
			return [Template.GATHER, Template.BOUNTY, Template.DELIVERY]
		"scientist":
			return [Template.OBSERVE, Template.EXPLORE, Template.GATHER, Template.MINE]
		"innkeeper":
			return [Template.GATHER, Template.DELIVERY, Template.SURVIVE]
	return [Template.BOUNTY, Template.GATHER, Template.MINE, Template.DELIVERY,
		Template.EXPLORE, Template.OBSERVE, Template.SURVIVE, Template.CRAFT, Template.BUILD]


func _build(t: Template, npc: Node, giver_id: StringName, threat: int) -> QuestDef:
	match t:
		Template.BOUNTY:
			return _bounty(npc, giver_id, threat)
		Template.GATHER:
			return _gather(npc, giver_id, threat)
		Template.MINE:
			return _mine(npc, giver_id, threat)
		Template.DELIVERY:
			return _delivery(npc, giver_id, threat)
		Template.EXPLORE:
			return _explore(npc, giver_id, threat)
		Template.OBSERVE:
			return _observe(npc, giver_id, threat)
		Template.SURVIVE:
			return _survive(npc, giver_id, threat)
		Template.CRAFT:
			return _craft(npc, giver_id, threat)
		Template.BUILD:
			return _build_quest(npc, giver_id, threat)
	return null


# =========================================================================
#  Templates
# =========================================================================
func _bounty(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var species := _pick_monster()
	if species == &"":
		return null
	var count := _rng.randi_range(4, 6 + threat)
	var pretty := _pretty(species)
	var q := _new_quest(npc, giver, threat, _pick(TITLE_BOUNTY) % _plural(pretty))
	q.needs(QuestObjective.kill(species, count))
	q.described("Cull %d %s near %s." % [count, _plural(pretty).to_lower(), _place()])
	q.says(
		"%s The %s have got %s again — %d of them at least, and %s with it. Clear them out. %s"
			% [_pick(OPENERS), _plural(pretty).to_lower(), _place(), count,
				_pick(HAZARD_WORDS), _pick(CLOSERS) % "Ferro"],
		_pick(GRATITUDE))
	_pay(q, threat, count * 14, 0.35)
	return q


func _gather(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var item := _pick_material()
	if item == &"":
		return null
	var count := _rng.randi_range(6, 10 + threat * 3)
	var pretty := _pretty(item)
	var q := _new_quest(npc, giver, threat, _pick(TITLE_GATHER) % pretty)
	q.needs(QuestObjective.collect(item, count))
	q.described("Bring %d %s back to %s." % [count, _plural(pretty).to_lower(), _giver_name(npc)])
	q.says(
		"%s I'm %d short on %s and the season won't wait. Anything you can spare, I'll buy. %s"
			% [_pick(OPENERS), count, _plural(pretty).to_lower(), _pick(CLOSERS) % "the innkeep"],
		_pick(GRATITUDE))
	_pay(q, threat, count * 6, 0.25)
	return q


func _mine(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var block := _pick_ore_block()
	if block == &"":
		return null
	var count := _rng.randi_range(8, 14 + threat * 2)
	var pretty := _pretty(block)
	var q := _new_quest(npc, giver, threat, _pick(TITLE_MINE) % pretty)
	q.needs(_mine_objective(block, count))
	q.described("Break %d %s underground." % [count, _plural(pretty).to_lower()])
	q.says(
		"%s There's a seam of %s under the %s. I need %d loads and I need them before the smelter cools. %s"
			% [_pick(OPENERS), pretty.to_lower(), _place(), count, _pick(CLOSERS) % "Vell"],
		_pick(GRATITUDE))
	_pay(q, threat, count * 8, 0.3)
	return q


func _mine_objective(block: StringName, count: int) -> QuestObjective:
	return QuestObjective.mine(block, count)


func _delivery(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var target := _pick_other_npc(giver)
	if target == &"":
		return null
	var item := _pick_material()
	if item == &"":
		item = &"cobblestone"
	var count := _rng.randi_range(1, 4)
	var to_name := _pretty(target)
	var q := _new_quest(npc, giver, threat, _pick(TITLE_DELIVERY) % to_name)
	q.needs(QuestObjective.deliver(item, count, target))
	q.hand_in_to(target)
	q.described("Carry %d %s to %s." % [count, _plural(_pretty(item)).to_lower(), to_name])
	q.says(
		"%s %s has been asking after %s for a week and I've no legs left in me. Take %d and don't dawdle. %s"
			% [_pick(OPENERS), to_name, _plural(_pretty(item)).to_lower(), count,
				_pick(CLOSERS) % to_name],
		"Ah — from %s? About time. Here, for the walk." % _giver_name(npc))
	_pay(q, threat, 60 + count * 10, 0.2)
	q.expires_in(600.0)
	return q


func _explore(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var spot := _remote_point(_rng.randi_range(60, 140))
	if spot == Vector3.INF:
		return null
	var region := StringName("%s_%s" % [_place().replace(" ", "_"), str(_rng.randi() % 997)])
	var q := _new_quest(npc, giver, threat, _pick(TITLE_EXPLORE) % _place().capitalize())
	q.needs(QuestObjective.explore(region, spot, 10.0).described("Reach the unmapped site"))
	q.described("Set foot on the site %d blocks from here." % int(spot.length()))
	q.says(
		"%s Nobody's walked the %s since the survey drone went quiet. Stand where it fell and I'll call the map honest. %s"
			% [_pick(OPENERS), _place(), _pick(CLOSERS) % "the cartographers"],
		"You actually went. Here — I've been saving this for someone with nerve.")
	_pay(q, threat, 90, 0.4)
	return q


## The perspective side quest. Always asks the player to *flip*, which is what
## makes an ordinary fetch board feel like this game and not another one.
func _observe(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var spot := _remote_point(_rng.randi_range(24, 70))
	if spot == Vector3.INF:
		return null
	var plane := _rng.randi_range(0, 3)
	if plane == View.view:
		plane = wrapi(plane + 1 + _rng.randi_range(0, 2), 0, 4)
	var plane_name: String = Const.VIEW_NAMES[plane]
	var title_src := _pick(TITLE_OBSERVE)
	var title := title_src % plane_name if title_src.contains("%s") else title_src
	var q := _new_quest(npc, giver, threat, title)
	q.needs(QuestObjective.observe(StringName("survey_%d" % (_rng.randi() % 9973)), spot, plane)
		.described("Stand at the marker and flip to the %s plane" % plane_name))
	q.described("Reach the marker and view it from the %s plane." % plane_name)
	q.says(
		"%s Here's the thing nobody off-world believes: the ground lies to you. There's a shape out past the %s that only resolves if you're standing square to %s. Go and look. Properly look. Then come back and tell me I'm not mad. %s"
			% [_pick(OPENERS), _place(), plane_name, _pick(CLOSERS) % "the surveyors"],
		"You saw it. I can tell from your face. Everybody's face does that.")
	_pay(q, threat, 120, 0.5)
	q.pays_reputation(StringName(String(giver)), 4)
	return q


func _survive(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var seconds := float(_rng.randi_range(60, 90 + threat * 20))
	var q := _new_quest(npc, giver, threat, _pick(TITLE_SURVIVE))
	q.needs(QuestObjective.survive(seconds, &"holdout")
		.described("Survive %d seconds after nightfall" % int(seconds)))
	q.fails_on(QuestDef.Fail.PLAYER_DEATH)
	q.described("Stay alive for %d seconds." % int(seconds))
	q.says(
		"%s When the light goes, things come up out of the %s. Stand at the perimeter and don't die for %d seconds. That's the whole job. %s"
			% [_pick(OPENERS), _place(), int(seconds), _pick(CLOSERS) % "the watch"],
		"Still breathing. The perimeter held. Take it.")
	_pay(q, threat, int(seconds) * 3, 0.45)
	return q


func _craft(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var item := _pick_craftable()
	if item == &"":
		return null
	var count := _rng.randi_range(1, 3)
	var pretty := _pretty(item)
	var q := _new_quest(npc, giver, threat, _pick(TITLE_CRAFT) % pretty)
	q.needs(QuestObjective.craft(item, count))
	q.described("Craft %d %s." % [count, _plural(pretty).to_lower()])
	q.says(
		"%s My bench is cracked clean through and I've an order due. Make me %d %s — properly made, not lashed together. %s"
			% [_pick(OPENERS), count, _plural(pretty).to_lower(), _pick(CLOSERS) % "the guild"],
		_pick(GRATITUDE))
	_pay(q, threat, count * 40, 0.3)
	return q


func _build_quest(npc: Node, giver: StringName, threat: int) -> QuestDef:
	var block := _pick_building_block()
	if block == &"":
		return null
	var count := _rng.randi_range(15, 30)
	var pretty := _pretty(block)
	var q := _new_quest(npc, giver, threat, _pick(TITLE_BUILD) % pretty)
	q.needs(QuestObjective.build(block, count))
	q.described("Place %d %s." % [count, _plural(pretty).to_lower()])
	q.says(
		"%s The east wall came down in the storm. %d blocks of %s and we can sleep again. %s"
			% [_pick(OPENERS), count, pretty.to_lower(), _pick(CLOSERS) % "the mason"],
		"Solid work. The wall will outlive us both.")
	_pay(q, threat, count * 5, 0.2)
	return q


# =========================================================================
#  Shared construction
# =========================================================================
func _new_quest(npc: Node, giver: StringName, threat: int, title: String) -> QuestDef:
	var id := "gen_%s_%d" % [String(giver), counter]
	var q := QuestDef.new(id, title)
	q.from_npc(giver, _giver_name(npc))
	q.at_threat(threat)
	q.on_planet(World.planet_id)
	q.repeats()
	return q


## Rewards scale with the planet's threat rating and a per-template weight, then
## get a small random garnish so no two boards pay the same.
func _pay(q: QuestDef, threat: int, base: int, weight: float) -> void:
	var mult := 1.0 + float(threat - 1) * 0.55
	var pixels := int(float(base) * mult * _rng.randf_range(0.85, 1.2))
	q.pays(maxi(20, pixels))
	q.pays_reputation(StringName(String(q.giver)), 3)
	if _rng.randf() < weight:
		var bonus := _pick_material()
		if bonus != &"":
			q.pays_item(bonus, _rng.randi_range(1, 2 + threat))
	if _rng.randf() < 0.12 * mult:
		var t := _pick_treasure()
		if t != &"":
			q.pays_item(t, 1)


func _threat() -> int:
	var meta: Dictionary = Universe.planet_meta(World.planet_id)
	return clampi(int(meta.get("threat", 1)), 1, 10)


# =========================================================================
#  Target discovery — everything here reads the live world
# =========================================================================
## A hostile species that is actually walking around this planet right now.
func _pick_monster() -> StringName:
	var seen: Dictionary = {}
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null:
		for n: Node in loop.get_nodes_in_group(&"entities"):
			var e := n as VoxelEntity
			if e == null or e.dead or e.faction != &"hostile":
				continue
			var s := _species_of(e)
			if s != &"":
				seen[s] = true
	if seen.is_empty():
		# The monster agent may not have spawned anything yet; fall back to the
		# biome's implied fauna so the board is never empty.
		var biome := PlanetGen.biome_at(0, 0)
		return StringName("%s_prowler" % String(biome))
	var keys := seen.keys()
	return StringName(keys[_rng.randi_range(0, keys.size() - 1)])


## A material item that exists in the registry, biased toward things the planet
## can actually yield (ore drops and plant matter).
func _pick_material() -> StringName:
	var pool: Array[StringName] = []
	for bt: BlockType in Blocks.all_with_tag(&"ore"):
		for d: Variant in bt.drops:
			var item := StringName((d as Dictionary).get("item", ""))
			if item != &"" and Items.has(item):
				pool.append(item)
	for bt: BlockType in Blocks.all_with_tag(&"tree_log"):
		if Items.has(bt.name):
			pool.append(bt.name)
	if pool.is_empty():
		for it: ItemType in Items.all_of_kind(ItemType.Kind.MATERIAL):
			pool.append(it.id)
	if pool.is_empty():
		for bt: BlockType in Blocks.all_in_category(&"natural"):
			if Items.has(bt.name):
				pool.append(bt.name)
	if pool.is_empty():
		return &""
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _pick_ore_block() -> StringName:
	var pool: Array[StringName] = []
	for bt: BlockType in Blocks.all_with_tag(&"ore"):
		pool.append(bt.name)
	if pool.is_empty():
		for bt: BlockType in Blocks.all_in_category(&"natural"):
			pool.append(bt.name)
	if pool.is_empty():
		return &""
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _pick_building_block() -> StringName:
	var pool: Array[StringName] = []
	for bt: BlockType in Blocks.all_in_category(&"building"):
		if Items.has(bt.name):
			pool.append(bt.name)
	if pool.is_empty():
		return &"cobblestone" if Blocks.has(&"cobblestone") else &""
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _pick_craftable() -> StringName:
	var pool: Array[StringName] = []
	for k: int in [ItemType.Kind.TOOL, ItemType.Kind.WEAPON, ItemType.Kind.ARMOR, ItemType.Kind.OBJECT]:
		for it: ItemType in Items.all_of_kind(k):
			if it.rarity <= Const.RARITY_UNCOMMON:
				pool.append(it.id)
	if pool.is_empty():
		return &""
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _pick_treasure() -> StringName:
	var pool: Array[StringName] = []
	for id: StringName in Items.order:
		var it := Items.get_type(id)
		if it != null and it.rarity >= Const.RARITY_RARE and it.rarity < Const.RARITY_ESSENTIAL:
			pool.append(id)
	if pool.is_empty():
		return &""
	return pool[_rng.randi_range(0, pool.size() - 1)]


## Another live NPC to deliver to.
func _pick_other_npc(exclude: StringName) -> StringName:
	var pool: Array[StringName] = []
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return &""
	for n: Node in loop.get_nodes_in_group(&"npc"):
		var id := StringName(n.get("npc_id"))
		if id != &"" and id != exclude:
			pool.append(id)
	if pool.is_empty():
		return &""
	return pool[_rng.randi_range(0, pool.size() - 1)]


## A surface point some distance away in plane space, snapped to the terrain.
func _remote_point(distance: int) -> Vector3:
	var p := Game.player
	if p == null:
		return Vector3.INF
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var offset := View.plane_dir_to_world(Vector2(dir * float(distance), 0.0))
	var target: Vector3 = p.global_position + offset
	var bx := int(floor(target.x))
	var bz := int(floor(target.z))
	var y := PlanetGen.height_at(World.wrap_x(bx), World.wrap_z(bz))
	if y <= 0:
		y = int(p.global_position.y)
	return Vector3(World.wrap_x(bx) + 0.5, float(y) + 1.0, World.wrap_z(bz) + 0.5)


# =========================================================================
#  Text helpers
# =========================================================================
func _pick(bank: Array[String]) -> String:
	return bank[_rng.randi_range(0, bank.size() - 1)]


func _place() -> String:
	var word := PLACE_WORDS[_rng.randi_range(0, PLACE_WORDS.size() - 1)]
	if _rng.randf() < 0.35:
		return "%s %s" % [PLACE_WORDS[_rng.randi_range(0, PLACE_WORDS.size() - 1)], word]
	return word


func _giver_name(npc: Node) -> String:
	if npc == null:
		return "the client"
	var n: Variant = npc.get("display_name")
	return String(n) if n != null and String(n) != "" else "the client"


## Same probing order the manager uses, so generated bounties key off exactly
## the id that [signal Events.entity_died] will report.
static func _species_of(e: Node) -> StringName:
	for f: String in ["species", "monster_id", "npc_id", "entity_id", "type_id"]:
		var v: Variant = e.get(f)
		if v != null and String(v) != "":
			return StringName(v)
	if e.has_meta(&"species"):
		return StringName(e.get_meta(&"species"))
	return StringName(String(e.name).to_snake_case())


static func _pretty(n: StringName) -> String:
	return QuestObjective._pretty(n)


static func _plural(s: String) -> String:
	return QuestObjective._plural(s)
