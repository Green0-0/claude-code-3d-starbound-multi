## One trackable step of a quest.
##
## Objectives never poll the world themselves: every other module funnels facts
## into [code]Quests.report(kind, key, amount)[/code] and the manager fans them
## out to the objectives that care. The only exceptions are the spatial kinds
## (VISIT / EXPLORE / OBSERVE / ESCORT), which the manager evaluates against the
## player's position on a slow tick, and SURVIVE, which counts seconds.
##
## The [b]OBSERVE[/b] kind is unique to Planeshift: it is satisfied by *looking*
## at the world from the right plane. An observe objective can require any
## combination of "stand near here", "be flipped to this viewing plane", "be on
## this depth layer" and "have this block visible from that plane" — which is
## how the campaign teaches the player that a wall in one plane is a corridor in
## another.
class_name QuestObjective
extends RefCounted

## Report vocabulary. The StringName in [method Quests.report] maps 1:1 onto
## these except for &"flip", &"shift" and &"reach", which only feed OBSERVE.
enum Kind {
	KILL,     ## slay N of a monster species        key = species id
	COLLECT,  ## hold / pick up N of an item        key = item id
	DELIVER,  ## hand N of an item to an NPC        key = item id, deliver_to = npc
	VISIT,    ## set foot on a planet or landmark   key = planet id / landmark id
	BUILD,    ## place N of a block                 key = block name
	CRAFT,    ## craft N of an item                 key = item id
	TALK,     ## speak to an NPC                    key = npc id
	SURVIVE,  ## stay alive / hold out N seconds    key = flavour tag
	ESCORT,   ## keep an NPC alive to a location    key = npc id
	EXPLORE,  ## enter a region / biome / structure key = region id
	OBSERVE,  ## the perspective objective          key = observation id
}

const KIND_NAMES: Array[StringName] = [
	&"kill", &"collect", &"deliver", &"visit", &"build",
	&"craft", &"talk", &"survive", &"escort", &"explore", &"observe",
]

## No layer requirement. Chosen far outside any legal world coordinate.
const ANY_LAYER := -2147483648

var kind: Kind = Kind.KILL
var key: StringName = &""
var goal: int = 1
var progress: int = 0

var optional: bool = false
## Hidden objectives are tracked but not listed until they first tick.
var hidden: bool = false
## Free text that overrides the generated description.
var text: String = ""
## Listen for a different [method Quests.report] kind than this objective's own
## name — e.g. a BUILD-shaped objective that counts &"mine" reports instead.
## Also the escape hatch for report kinds invented after this file was written.
var custom_kind: StringName = &""

# --- spatial (VISIT / EXPLORE / OBSERVE / ESCORT) -----------------------------
var location: Vector3 = Vector3.INF
var radius: float = 6.0
var planet_id: String = ""

# --- OBSERVE -----------------------------------------------------------------
## Required viewing plane 0..3, or -1 for "any plane".
var view_index: int = -1
## Required depth layer, or [constant ANY_LAYER].
var layer: int = ANY_LAYER
## A block that must be visible along the camera ray from [member location]
## when standing in [member view_index]. Empty = no block requirement.
var observe_block: StringName = &""
## How far the sight-line probe reaches, in voxels.
var observe_range: float = 48.0

# --- DELIVER -----------------------------------------------------------------
var deliver_to: StringName = &""

# --- SURVIVE -----------------------------------------------------------------
## Seconds. Mirrored into [member goal] on construction.
var duration: float = 0.0

# --- runtime -----------------------------------------------------------------
var done: bool = false
var failed: bool = false
## Set by the manager the first time this objective ticks; the HUD uses it to
## reveal hidden objectives.
var revealed: bool = false


# ------------------------------------------------------------ constructors
static func kill(species: StringName, count: int = 1) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.KILL
	o.key = species
	o.goal = maxi(1, count)
	return o


static func collect(item: StringName, count: int = 1) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.COLLECT
	o.key = item
	o.goal = maxi(1, count)
	return o


static func deliver(item: StringName, count: int, to_npc: StringName) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.DELIVER
	o.key = item
	o.goal = maxi(1, count)
	o.deliver_to = to_npc
	return o


static func visit(planet_or_landmark: StringName) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.VISIT
	o.key = planet_or_landmark
	o.goal = 1
	return o


static func visit_place(id: StringName, where: Vector3, r: float = 8.0) -> QuestObjective:
	var o := visit(id)
	o.location = where
	o.radius = r
	return o


static func build(block: StringName, count: int = 1) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.BUILD
	o.key = block
	o.goal = maxi(1, count)
	return o


## Break N of a block. Shares BUILD's block-name key space but listens for the
## &"mine" report instead of &"build".
static func mine(block: StringName, count: int = 1) -> QuestObjective:
	var o := build(block, count)
	o.custom_kind = &"mine"
	return o


static func craft(item: StringName, count: int = 1) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.CRAFT
	o.key = item
	o.goal = maxi(1, count)
	return o


static func talk(npc_id: StringName) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.TALK
	o.key = npc_id
	o.goal = 1
	return o


static func survive(seconds: float, tag: StringName = &"holdout") -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.SURVIVE
	o.key = tag
	o.duration = maxf(1.0, seconds)
	o.goal = int(o.duration)
	return o


static func escort(npc_id: StringName, to: Vector3, r: float = 6.0) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.ESCORT
	o.key = npc_id
	o.goal = 1
	o.location = to
	o.radius = r
	return o


static func explore(region: StringName, where: Vector3 = Vector3.INF, r: float = 12.0) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.EXPLORE
	o.key = region
	o.goal = 1
	o.location = where
	o.radius = r
	return o


## The signature Planeshift objective. Stand within [param r] of [param where]
## and be looking along plane [param plane] (-1 = any). Optionally the block
## [param must_see] has to be visible along the camera ray from there, which is
## how "a thing only visible from one plane" is expressed.
static func observe(id: StringName, where: Vector3, plane: int = -1,
		must_see: StringName = &"", r: float = 6.0) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.OBSERVE
	o.key = id
	o.goal = 1
	o.location = where
	o.radius = r
	o.view_index = plane
	o.observe_block = must_see
	return o


## Observe variant that only demands the player be flipped to a plane, wherever
## they are — used by the tutorial shrine.
static func observe_plane(id: StringName, plane: int) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.OBSERVE
	o.key = id
	o.goal = 1
	o.view_index = plane
	return o


## Count flips. [param plane] restricts the count to landings on one plane.
## Report-driven (&"flip"), so it never ticks from merely standing somewhere.
static func flips(count: int, plane: int = -1) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.OBSERVE
	o.custom_kind = &"flip"
	o.key = StringName(str(plane)) if plane >= 0 else &""
	o.goal = maxi(1, count)
	o.view_index = plane
	return o


## Count depth shifts (PgUp / PgDn), the traversal half of the mechanic.
static func shifts(count: int) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = Kind.OBSERVE
	o.custom_kind = &"shift"
	o.goal = maxi(1, count)
	return o


# ------------------------------------------------------------------ fluent
func described(t: String) -> QuestObjective:
	text = t
	return self


func as_optional() -> QuestObjective:
	optional = true
	return self


func as_hidden() -> QuestObjective:
	hidden = true
	return self


func on_planet(p: String) -> QuestObjective:
	planet_id = p
	return self


func on_layer(l: int) -> QuestObjective:
	layer = l
	return self


func within(r: float) -> QuestObjective:
	radius = r
	return self


# ------------------------------------------------------------------- logic
func kind_name() -> StringName:
	return KIND_NAMES[int(kind)]


## The report kind this objective actually listens for.
func listens_for() -> StringName:
	return custom_kind if custom_kind != &"" else kind_name()


## Does a [method Quests.report] of (kind, key) apply to this objective?
## An empty [member key] is a wildcard — `kill anything`, `craft anything`.
func matches(report_kind: StringName, report_key: Variant) -> bool:
	if done or failed:
		return false
	if report_kind != listens_for():
		return false
	if key == &"":
		return true
	return StringName(str(report_key)) == key


## Adds progress, clamping at the goal. Returns true when this call finished it.
func add(amount: int) -> bool:
	if done or failed or amount == 0:
		return false
	revealed = true
	progress = clampi(progress + amount, 0, goal)
	if progress >= goal:
		done = true
		return true
	return false


## Hard-sets progress (used by COLLECT inventory rescans). Returns true when
## this call finished it.
func set_progress(value: int) -> bool:
	if done or failed:
		return false
	var v := clampi(value, 0, goal)
	if v != progress:
		revealed = true
	progress = v
	if progress >= goal:
		done = true
		return true
	return false


func reset() -> void:
	progress = 0
	done = false
	failed = false
	revealed = false


func ratio() -> float:
	return 1.0 if done else clampf(float(progress) / float(maxi(1, goal)), 0.0, 1.0)


func has_location() -> bool:
	return location != Vector3.INF


## Human-readable line for the quest log / HUD tracker.
func describe() -> String:
	if text != "":
		return text
	var n := _pretty(key)
	match kind:
		Kind.KILL:
			return "Defeat %s (%d/%d)" % [_plural(n), progress, goal] if key != &"" \
				else "Defeat %d creatures (%d/%d)" % [goal, progress, goal]
		Kind.COLLECT:
			return "Collect %d %s (%d/%d)" % [goal, _plural(n), progress, goal]
		Kind.DELIVER:
			return "Deliver %d %s to %s (%d/%d)" % [goal, _plural(n), _pretty(deliver_to), progress, goal]
		Kind.VISIT:
			return "Travel to %s" % n
		Kind.BUILD:
			var verb := "Mine" if custom_kind == &"mine" else "Place"
			return "%s %d %s (%d/%d)" % [verb, goal, _plural(n), progress, goal]
		Kind.CRAFT:
			return "Craft %d %s (%d/%d)" % [goal, _plural(n), progress, goal]
		Kind.TALK:
			return "Speak with %s" % n
		Kind.SURVIVE:
			return "Survive %ds (%d/%d)" % [goal, progress, goal]
		Kind.ESCORT:
			return "Escort %s to safety" % n
		Kind.EXPLORE:
			return "Explore %s" % n
		Kind.OBSERVE:
			return _describe_observe()
	return n


func _describe_observe() -> String:
	if custom_kind == &"flip":
		if view_index >= 0:
			return "Flip to the %s plane (%d/%d)" % [Const.VIEW_NAMES[view_index], progress, goal]
		return "Flip the world (%d/%d)" % [progress, goal]
	if custom_kind == &"shift":
		return "Step through the depth layers (%d/%d)" % [progress, goal]
	var parts := PackedStringArray()
	if has_location():
		parts.append("reach the marked spot")
	if view_index >= 0:
		parts.append("look from the %s plane" % Const.VIEW_NAMES[clampi(view_index, 0, 3)])
	if layer != ANY_LAYER:
		parts.append("stand on layer %d" % layer)
	if observe_block != &"":
		parts.append("find the %s" % _pretty(observe_block))
	if parts.is_empty():
		return "Observe %s" % _pretty(key)
	return "Observe: " + ", ".join(parts)


static func _pretty(n: StringName) -> String:
	if n == &"":
		return "something"
	if Items != null and Items.has(n):
		return Items.display_name(n)
	if Blocks != null and Blocks.has(n):
		var bt := Blocks.get_by_name(n)
		if bt != null:
			return bt.display_name
	return String(n).replace("_", " ").capitalize()


static func _plural(s: String) -> String:
	if s.ends_with("s") or s.ends_with("x") or s.ends_with("sh") or s.ends_with("ch"):
		return s
	return s + "s"


# ------------------------------------------------------------ serialisation
func to_dict() -> Dictionary:
	return {
		"k": int(kind), "key": String(key), "goal": goal, "prog": progress,
		"opt": optional, "hid": hidden, "txt": text, "ck": String(custom_kind),
		"loc": [location.x, location.y, location.z], "rad": radius,
		"planet": planet_id, "view": view_index, "layer": layer,
		"blk": String(observe_block), "orange": observe_range,
		"to": String(deliver_to), "dur": duration,
		"done": done, "fail": failed, "rev": revealed,
	}


static func from_dict(d: Dictionary) -> QuestObjective:
	var o := QuestObjective.new()
	o.kind = int(d.get("k", 0)) as Kind
	o.key = StringName(d.get("key", ""))
	o.goal = int(d.get("goal", 1))
	o.progress = int(d.get("prog", 0))
	o.optional = bool(d.get("opt", false))
	o.hidden = bool(d.get("hid", false))
	o.text = String(d.get("txt", ""))
	o.custom_kind = StringName(d.get("ck", ""))
	var l: Array = d.get("loc", [INF, INF, INF])
	o.location = Vector3(l[0], l[1], l[2])
	o.radius = float(d.get("rad", 6.0))
	o.planet_id = String(d.get("planet", ""))
	o.view_index = int(d.get("view", -1))
	o.layer = int(d.get("layer", ANY_LAYER))
	o.observe_block = StringName(d.get("blk", ""))
	o.observe_range = float(d.get("orange", 48.0))
	o.deliver_to = StringName(d.get("to", ""))
	o.duration = float(d.get("dur", 0.0))
	o.done = bool(d.get("done", false))
	o.failed = bool(d.get("fail", false))
	o.revealed = bool(d.get("rev", false))
	return o


func duplicate_objective() -> QuestObjective:
	return QuestObjective.from_dict(to_dict())
