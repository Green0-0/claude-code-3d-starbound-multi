class_name Quests
extends RefCounted

## Quests, their objectives, and the manager that watches the game for progress.
##
## An objective is a counter with a predicate. The manager subscribes to four
## events — an item entered the bag, a monster died, a block was placed, a
## location was reached — and every objective kind is expressed in terms of one
## of them. That is deliberately small: it means a procedurally generated quest
## and a hand-written campaign beat are the same object, and the quest log only
## ever has to render one shape.

enum Kind { GATHER, KILL, PLACE, CRAFT, VISIT, TALK, DEPTH }


class Objective extends RefCounted:
	var kind: int = Quests.Kind.GATHER
	var target: StringName = &""
	var count := 1
	var progress := 0
	var text := ""

	func is_done() -> bool:
		return progress >= count

	func label() -> String:
		if text != "":
			return "%s  (%d/%d)" % [text, mini(progress, count), count]
		return "%s  (%d/%d)" % [String(target), mini(progress, count), count]


class Quest extends RefCounted:
	var id := ""
	var title := ""
	var summary := ""
	var giver: StringName = &""          ## role that hands it out
	var objectives: Array[Objective] = []
	var reward_items: Array = []         ## [[item_id, count], ...]
	var reward_pixels := 0
	var reward_recipes: Array[String] = []
	var next_quest := ""
	var main_story := false
	var repeatable := false
	var turn_in := true                  ## must be handed back to the giver

	func add(kind: int, target: StringName, count: int, text := "") -> Quest:
		var o := Objective.new()
		o.kind = kind
		o.target = target
		o.count = count
		o.text = text
		objectives.append(o)
		return self

	func rewards(pixels: int, items := []) -> Quest:
		reward_pixels = pixels
		for i in items:
			reward_items.append(i)
		return self

	func teaches(recipe_id: String) -> Quest:
		reward_recipes.append(recipe_id)
		return self

	func then(quest_id: String) -> Quest:
		next_quest = quest_id
		return self

	func is_complete() -> bool:
		for o: Objective in objectives:
			if not o.is_done():
				return false
		return true

	func duplicate_quest() -> Quest:
		var q := Quest.new()
		q.id = id
		q.title = title
		q.summary = summary
		q.giver = giver
		q.reward_items = reward_items.duplicate(true)
		q.reward_pixels = reward_pixels
		q.reward_recipes = reward_recipes.duplicate()
		q.next_quest = next_quest
		q.main_story = main_story
		q.repeatable = repeatable
		q.turn_in = turn_in
		for o: Objective in objectives:
			var c := Objective.new()
			c.kind = o.kind
			c.target = o.target
			c.count = o.count
			c.text = o.text
			q.objectives.append(c)
		return q


# =============================================================================
# the catalogue
# =============================================================================

static var catalogue: Array[Quest] = []
static var by_id := {}
static var _booted := false


static func boot() -> void:
	if _booted:
		return
	_booted = true
	Items.boot()
	var script: GDScript = load("res://scripts/content/quest_book.gd")
	script.register_all()


static func make(id: String, title: String) -> Quest:
	var q := Quest.new()
	q.id = id
	q.title = title
	catalogue.append(q)
	by_id[id] = q
	return q


static func get_quest(id: String) -> Quest:
	return by_id.get(id)


## Every quest a role can hand out that is not already taken or finished.
static func offers_from(role: StringName, taken: Dictionary,
		done: Dictionary) -> Array[Quest]:
	var out: Array[Quest] = []
	for q: Quest in catalogue:
		if q.giver != role or q.main_story:
			continue
		if taken.has(q.id):
			continue
		if done.has(q.id) and not q.repeatable:
			continue
		out.append(q)
	return out


# =============================================================================
# the manager
# =============================================================================

class Manager extends RefCounted:
	signal changed()
	signal quest_completed(quest: Quest)
	signal quest_started(quest: Quest)

	var active: Array[Quest] = []
	var completed := {}
	var flags := {}
	var game: Node = null

	func start(id: String) -> Quest:
		var template := Quests.get_quest(id)
		if template == null:
			return null
		for q: Quest in active:
			if q.id == id:
				return q
		if completed.has(id) and not template.repeatable:
			return null
		var q := template.duplicate_quest()
		active.append(q)
		quest_started.emit(q)
		changed.emit()
		return q

	func abandon(id: String) -> void:
		for i in active.size():
			if active[i].id == id:
				active.remove_at(i)
				changed.emit()
				return

	func has_active(id: String) -> bool:
		for q: Quest in active:
			if q.id == id:
				return true
		return false

	func is_done(id: String) -> bool:
		return completed.has(id)

	## The main-story quest the player should be doing right now.
	func current_story() -> Quest:
		for q: Quest in active:
			if q.main_story:
				return q
		return null

	# --- event hooks -------------------------------------------------------

	func on_item_gained(item_id: StringName, count: int) -> void:
		_advance(Quests.Kind.GATHER, item_id, count)

	func on_crafted(item_id: StringName, count: int) -> void:
		_advance(Quests.Kind.CRAFT, item_id, count)

	func on_kill(species_id: StringName) -> void:
		_advance(Quests.Kind.KILL, species_id, 1)
		_advance(Quests.Kind.KILL, &"any", 1)

	func on_block_placed(block_name: StringName) -> void:
		_advance(Quests.Kind.PLACE, block_name, 1)

	func on_talked(role: StringName) -> void:
		_advance(Quests.Kind.TALK, role, 1)

	func on_visited(place: StringName) -> void:
		_advance(Quests.Kind.VISIT, place, 1)

	func on_depth(y: int) -> void:
		for q: Quest in active:
			for o: Objective in q.objectives:
				if o.kind == Quests.Kind.DEPTH and o.progress < o.count and y <= o.count:
					o.progress = o.count
					changed.emit()

	func _advance(kind: int, target: StringName, count: int) -> void:
		var touched := false
		for q: Quest in active:
			for o: Objective in q.objectives:
				if o.kind != kind or o.is_done():
					continue
				if o.target != target and o.target != &"any":
					continue
				o.progress += count
				touched = true
		if touched:
			changed.emit()
			_auto_complete()

	## Quests with `turn_in = false` resolve the moment their last objective does.
	func _auto_complete() -> void:
		for q: Quest in active.duplicate():
			if not q.turn_in and q.is_complete():
				complete(q)

	## Hand a finished quest in. Returns false if it was not actually finished.
	func complete(q: Quest) -> bool:
		if not q.is_complete():
			return false
		active.erase(q)
		completed[q.id] = true
		if game != null:
			game.grant_quest_rewards(q)
		quest_completed.emit(q)
		changed.emit()
		if q.next_quest != "":
			start(q.next_quest)
		return true

	## Every finished-but-not-handed-in quest this role is waiting on.
	func ready_for(role: StringName) -> Array[Quest]:
		var out: Array[Quest] = []
		for q: Quest in active:
			if q.giver == role and q.is_complete():
				out.append(q)
		return out

	func set_flag(name: String, value := true) -> void:
		flags[name] = value

	func has_flag(name: String) -> bool:
		return bool(flags.get(name, false))

	# --- persistence -------------------------------------------------------

	func save_state() -> Dictionary:
		var rows: Array = []
		for q: Quest in active:
			var prog: Array = []
			for o: Objective in q.objectives:
				prog.append(o.progress)
			rows.append({"id": q.id, "progress": prog})
		return {"active": rows, "completed": completed.keys(), "flags": flags}

	func load_state(d: Dictionary) -> void:
		active.clear()
		completed.clear()
		for id in d.get("completed", []):
			completed[String(id)] = true
		flags = d.get("flags", {})
		for row in d.get("active", []):
			var q := start(String(row["id"]))
			if q == null:
				continue
			var prog: Array = row.get("progress", [])
			for i in mini(prog.size(), q.objectives.size()):
				q.objectives[i].progress = int(prog[i])
		changed.emit()
