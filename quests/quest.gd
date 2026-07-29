## The static definition of one quest: what it asks, what gates it, what it pays
## and where it branches. Instances are immutable templates — the live progress
## lives on the [QuestObjective]s of the *runtime copy* the manager clones when
## the quest starts.
##
## Built fluently:
## [codeblock]
## Quests.define("bounty_crawler", "Crawlers in the Grain")
##     .from_npc(&"mara", "Mara Fen")
##     .needs(QuestObjective.kill(&"crawler", 6))
##     .needs(QuestObjective.observe("silo_west", silo_pos, 1))
##     .after("main_02_repair")
##     .expires_in(600.0)
##     .pays(180).pays_item(&"iron_bar", 4).pays_reputation(&"greenhollow", 5)
##     .says("They're in the silo again...", "That's the last of them. Thank you.")
## [/codeblock]
class_name QuestDef
extends RefCounted

## What ends the quest when it goes wrong.
enum Fail {
	NONE,
	PLAYER_DEATH,     ## dying cancels the quest
	TIMER,            ## the time limit ran out
	ESCORT_DIED,      ## an escorted NPC was killed
	GIVER_DIED,       ## the quest giver was killed
	LEFT_PLANET,      ## the player travelled away mid-quest
}

var id: String = ""
var title: String = "Quest"
var summary: String = ""
## Longer flavour shown on the quest board / log detail pane.
var flavour: String = ""

var giver: StringName = &""
var giver_name: String = ""
## Who to hand the quest in to. Defaults to [member giver]; set to &"" for a
## quest that completes the instant its last objective ticks.
var turn_in: StringName = &""
var auto_complete: bool = true

var objectives: Array[QuestObjective] = []

## Quest ids that must be completed before this one may be offered.
var prerequisites: PackedStringArray = PackedStringArray()
## Quest ids that may not be active or completed for this one to be offered.
var excludes: PackedStringArray = PackedStringArray()
## Arbitrary world flags that must be set (see [method Quests.set_flag]).
var required_flags: PackedStringArray = PackedStringArray()
## Minimum reputation with [member reputation_faction] to be offered this.
var required_reputation: int = 0
var reputation_faction: StringName = &"world"

## Seconds; 0 = untimed.
var time_limit: float = 0.0
## [enum Fail] values. Stored as ints so the array type stays portable.
var fail_conditions: Array[int] = []

var is_main: bool = false
var chapter: int = 0
## Rough difficulty 1..10; the generator scales rewards off it.
var threat: int = 1
var repeatable: bool = false
var planet_id: String = ""

# --- rewards -----------------------------------------------------------------
var reward_pixels: int = 0
## [{"id": StringName, "count": int}]
var reward_items: Array[Dictionary] = []
var reward_recipes: Array[StringName] = []
var reward_techs: Array[StringName] = []
## faction/npc id -> delta
var reward_reputation: Dictionary = {}
## Quest ids offered automatically when this one completes.
var unlocks: PackedStringArray = PackedStringArray()
## World flags set on completion.
var sets_flags: PackedStringArray = PackedStringArray()

# --- branching ---------------------------------------------------------------
## [{"id": String, "text": String, "when": Callable|Dictionary, "next": String,
##   "pixels": int, "flags": PackedStringArray}]
## The first branch whose condition passes is applied on completion, on top of
## the flat rewards. `when` may be a Callable(taking no args) or a dialogue-style
## condition Dictionary understood by [QuestDialogue].
var branches: Array[Dictionary] = []

# --- text --------------------------------------------------------------------
var offer_text: String = ""
var progress_text: String = ""
var complete_text: String = ""
var fail_text: String = ""
## Dialogue tree opened when the giver is talked to while this quest is offered.
var dialogue_tree: String = ""


func _init(p_id: String = "", p_title: String = "") -> void:
	id = p_id
	title = p_title if p_title != "" else p_id.replace("_", " ").capitalize()


# ------------------------------------------------------------------- fluent
func from_npc(npc_id: StringName, npc_name: String = "") -> QuestDef:
	giver = npc_id
	giver_name = npc_name if npc_name != "" else String(npc_id).capitalize()
	if turn_in == &"":
		turn_in = npc_id
	return self


func hand_in_to(npc_id: StringName) -> QuestDef:
	turn_in = npc_id
	auto_complete = npc_id == &""
	return self


## Complete the moment the last objective ticks, without a turn-in visit.
func completes_instantly() -> QuestDef:
	turn_in = &""
	auto_complete = true
	return self


func needs(o: QuestObjective) -> QuestDef:
	objectives.append(o)
	return self


func described(p_summary: String, p_flavour: String = "") -> QuestDef:
	summary = p_summary
	if p_flavour != "":
		flavour = p_flavour
	return self


func after(quest_id: String) -> QuestDef:
	prerequisites.append(quest_id)
	return self


func not_with(quest_id: String) -> QuestDef:
	excludes.append(quest_id)
	return self


func needs_flag(flag: String) -> QuestDef:
	required_flags.append(flag)
	return self


func needs_reputation(amount: int, faction: StringName = &"world") -> QuestDef:
	required_reputation = amount
	reputation_faction = faction
	return self


func expires_in(seconds: float) -> QuestDef:
	time_limit = seconds
	if not fail_conditions.has(Fail.TIMER):
		fail_conditions.append(Fail.TIMER)
	return self


func fails_on(c: Fail) -> QuestDef:
	if not fail_conditions.has(c):
		fail_conditions.append(c)
	return self


func as_main(p_chapter: int) -> QuestDef:
	is_main = true
	chapter = p_chapter
	return self


func at_threat(t: int) -> QuestDef:
	threat = maxi(1, t)
	return self


func on_planet(p: String) -> QuestDef:
	planet_id = p
	return self


func repeats() -> QuestDef:
	repeatable = true
	return self


func pays(pixels: int) -> QuestDef:
	reward_pixels = pixels
	return self


func pays_item(item: StringName, count: int = 1) -> QuestDef:
	reward_items.append({"id": item, "count": maxi(1, count)})
	return self


func pays_recipe(recipe: StringName) -> QuestDef:
	reward_recipes.append(recipe)
	return self


func pays_tech(tech: StringName) -> QuestDef:
	reward_techs.append(tech)
	return self


func pays_reputation(faction: StringName, amount: int) -> QuestDef:
	reward_reputation[faction] = int(reward_reputation.get(faction, 0)) + amount
	return self


func unlocks_quest(quest_id: String) -> QuestDef:
	unlocks.append(quest_id)
	return self


func sets_flag(flag: String) -> QuestDef:
	sets_flags.append(flag)
	return self


## Adds an outcome branch. [param when] is either a Callable returning bool or a
## dialogue condition Dictionary. Branches are tested in insertion order.
func branch(branch_id: String, when: Variant, text: String = "",
		extra_pixels: int = 0, next_quest: String = "") -> QuestDef:
	branches.append({
		"id": branch_id, "when": when, "text": text,
		"pixels": extra_pixels, "next": next_quest,
	})
	return self


func says(p_offer: String, p_complete: String = "", p_progress: String = "", p_fail: String = "") -> QuestDef:
	offer_text = p_offer
	complete_text = p_complete
	progress_text = p_progress
	fail_text = p_fail
	return self


func with_dialogue(tree_id: String) -> QuestDef:
	dialogue_tree = tree_id
	return self


# -------------------------------------------------------------------- query
func objective_count() -> int:
	return objectives.size()


func required_objectives() -> Array[QuestObjective]:
	var out: Array[QuestObjective] = []
	for o: QuestObjective in objectives:
		if not o.optional:
			out.append(o)
	return out


## Deep copy with fresh, zeroed objectives — this is what the manager tracks.
func instantiate() -> QuestDef:
	var q := QuestDef.new(id, title)
	q.summary = summary
	q.flavour = flavour
	q.giver = giver
	q.giver_name = giver_name
	q.turn_in = turn_in
	q.auto_complete = auto_complete
	q.prerequisites = prerequisites.duplicate()
	q.excludes = excludes.duplicate()
	q.required_flags = required_flags.duplicate()
	q.required_reputation = required_reputation
	q.reputation_faction = reputation_faction
	q.time_limit = time_limit
	q.fail_conditions = fail_conditions.duplicate()
	q.is_main = is_main
	q.chapter = chapter
	q.threat = threat
	q.repeatable = repeatable
	q.planet_id = planet_id
	q.reward_pixels = reward_pixels
	q.reward_items = reward_items.duplicate(true)
	q.reward_recipes = reward_recipes.duplicate()
	q.reward_techs = reward_techs.duplicate()
	q.reward_reputation = reward_reputation.duplicate()
	q.unlocks = unlocks.duplicate()
	q.sets_flags = sets_flags.duplicate()
	q.branches = branches.duplicate()
	q.offer_text = offer_text
	q.progress_text = progress_text
	q.complete_text = complete_text
	q.fail_text = fail_text
	q.dialogue_tree = dialogue_tree
	for o: QuestObjective in objectives:
		q.objectives.append(o.duplicate_objective())
	return q


## Compact reward description for the offer window.
func reward_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if reward_pixels > 0:
		out.append("%d pixels" % reward_pixels)
	for r: Dictionary in reward_items:
		var n := String(r.get("id", ""))
		var disp := Items.display_name(StringName(n)) if Items.has(StringName(n)) else n.capitalize()
		out.append("%s x%d" % [disp, int(r.get("count", 1))])
	for r: StringName in reward_recipes:
		out.append("Recipe: %s" % String(r).replace("_", " ").capitalize())
	for t: StringName in reward_techs:
		out.append("Tech: %s" % String(t).replace("_", " ").capitalize())
	for f: Variant in reward_reputation:
		var amt := int(reward_reputation[f])
		if amt != 0:
			out.append("%+d standing with %s" % [amt, String(f).replace("_", " ").capitalize()])
	return out


# ------------------------------------------------------------ serialisation
## Only the mutable half is saved; the immutable half is re-read from the
## registered definition on load. Procedurally generated quests save whole.
func to_dict(full: bool = false) -> Dictionary:
	var d := {"id": id}
	var objs: Array = []
	for o: QuestObjective in objectives:
		objs.append(o.to_dict())
	d["objectives"] = objs
	if not full:
		return d
	d["full"] = true
	d["title"] = title
	d["summary"] = summary
	d["flavour"] = flavour
	d["giver"] = String(giver)
	d["giver_name"] = giver_name
	d["turn_in"] = String(turn_in)
	d["auto"] = auto_complete
	d["prereq"] = prerequisites
	d["time_limit"] = time_limit
	d["fails"] = fail_conditions.duplicate()
	d["main"] = is_main
	d["chapter"] = chapter
	d["threat"] = threat
	d["planet"] = planet_id
	d["pixels"] = reward_pixels
	d["items"] = reward_items.duplicate(true)
	var rc: Array = []
	for r: StringName in reward_recipes:
		rc.append(String(r))
	d["recipes"] = rc
	var tc: Array = []
	for t: StringName in reward_techs:
		tc.append(String(t))
	d["techs"] = tc
	d["rep"] = reward_reputation.duplicate()
	d["unlocks"] = unlocks
	d["flags"] = sets_flags
	d["offer"] = offer_text
	d["progress"] = progress_text
	d["complete"] = complete_text
	d["fail_text"] = fail_text
	d["tree"] = dialogue_tree
	return d


static func from_dict(d: Dictionary) -> QuestDef:
	var q := QuestDef.new(String(d.get("id", "")))
	if bool(d.get("full", false)):
		q.title = String(d.get("title", q.title))
		q.summary = String(d.get("summary", ""))
		q.flavour = String(d.get("flavour", ""))
		q.giver = StringName(d.get("giver", ""))
		q.giver_name = String(d.get("giver_name", ""))
		q.turn_in = StringName(d.get("turn_in", ""))
		q.auto_complete = bool(d.get("auto", true))
		q.prerequisites = PackedStringArray(d.get("prereq", []))
		q.time_limit = float(d.get("time_limit", 0.0))
		for f: Variant in d.get("fails", []):
			q.fail_conditions.append(int(f))
		q.is_main = bool(d.get("main", false))
		q.chapter = int(d.get("chapter", 0))
		q.threat = int(d.get("threat", 1))
		q.planet_id = String(d.get("planet", ""))
		q.reward_pixels = int(d.get("pixels", 0))
		for it: Variant in d.get("items", []):
			q.reward_items.append(it as Dictionary)
		for r: Variant in d.get("recipes", []):
			q.reward_recipes.append(StringName(r))
		for t: Variant in d.get("techs", []):
			q.reward_techs.append(StringName(t))
		q.reward_reputation = d.get("rep", {})
		q.unlocks = PackedStringArray(d.get("unlocks", []))
		q.sets_flags = PackedStringArray(d.get("flags", []))
		q.offer_text = String(d.get("offer", ""))
		q.progress_text = String(d.get("progress", ""))
		q.complete_text = String(d.get("complete", ""))
		q.fail_text = String(d.get("fail_text", ""))
		q.dialogue_tree = String(d.get("tree", ""))
	for o: Variant in d.get("objectives", []):
		q.objectives.append(QuestObjective.from_dict(o as Dictionary))
	return q
