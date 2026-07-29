## Autoloaded as `Quests`. The quest runtime: registry, offer/accept/track,
## objective progress, rewards, branching, failure and save/load.
##
## [b]The one thing other agents need to know[/b] is the funnel:
## [codeblock]
## Quests.report(kind: StringName, key: Variant, amount: int = 1)
## [/codeblock]
## Everything else is derived from it. The vocabulary:
##
## | kind        | key                        | emitted by |
## |-------------|----------------------------|------------|
## | &"kill"     | monster species id         | auto, via Events.entity_died |
## | &"collect"  | item id                    | auto, via Events.item_picked_up |
## | &"craft"    | item id                    | auto, via Events.item_crafted |
## | &"build"    | block name                 | auto, via Events.block_changed |
## | &"mine"     | block name                 | auto, via Events.block_changed |
## | &"visit"    | planet id / landmark id    | auto, via Events.travel_finished |
## | &"talk"     | npc id                     | auto, via Events.dialogue_started |
## | &"flip"     | new view index (0..3)      | auto, via Events.view_flip_finished |
## | &"shift"    | new depth layer            | auto, via Events.layer_changed |
## | &"deliver"  | item id, or "item@npc_id"  | call it yourself when handing over |
## | &"explore"  | region / biome / structure | call it when the player enters one |
## | &"escort"   | npc id                     | call it when an escortee is safe |
## | &"observe"  | observation id             | call it for bespoke sightings |
## | &"survive"  | flavour tag                | auto, ticked in seconds |
##
## So: if you are the worldgen agent and the player walks into a mine you built,
## `Quests.report(&"explore", &"abandoned_mine")` and every quest that cared just
## advanced. You never need to know which quests exist.
##
## OBSERVE objectives (the perspective ones) are evaluated here on a slow tick
## against the player's position, [code]View.view[/code] and [code]View.layer[/code];
## nobody has to report them.
extends Node

const CAMPAIGN_DIR := "res://quests/campaign"
## Seconds between the housekeeping pass (timers, proximity, observation checks).
const TICK_INTERVAL := 0.25
## Seconds between inventory rescans for COLLECT objectives.
const RESCAN_INTERVAL := 1.0

## Registered templates: id -> QuestDef.
var defs: Dictionary = {}
## Live quests: id -> QuestDef (a deep copy carrying live objective progress).
var active: Dictionary = {}
## id -> {"day": int, "branch": String}
var completed: Dictionary = {}
## id -> reason String
var failed: Dictionary = {}
## id -> giver npc id String
var offered: Dictionary = {}
## Arbitrary world state the campaign and dialogue trees gate on.
var flags: Dictionary = {}
## Quest currently pinned to the HUD tracker.
var tracked: String = ""

## Ids whose definition was made at runtime and must be saved in full.
var _generated: Dictionary = {}
## id -> seconds remaining, for time-limited quests.
var _timers: Dictionary = {}
## Quests that have met every objective and are waiting for a turn-in visit.
var _ready_to_hand_in: Dictionary = {}

var generator: QuestGenerator = null
var spawner: Node = null

var _tick_accum := 0.0
var _rescan_accum := 0.0
var _last_talked: StringName = &""
var _booted := false


func _ready() -> void:
	process_priority = 50
	generator = QuestGenerator.new()
	_connect_events()
	# Content registration waits one frame so Blocks/Items are fully populated.
	_boot.call_deferred()


func _boot() -> void:
	if _booted:
		return
	_booted = true
	_register_campaign()
	QuestDialogue.ensure_loaded()
	_attach_spawner()
	_register_panels()
	Events.world_ready.connect(func(_p: String) -> void: _begin_campaign())
	if World.ready_flag:
		_begin_campaign()


## `ui/ui_manager.gd` lists "shop" as belonging to this module, so we hand it the
## script rather than editing their file.
func _register_panels() -> void:
	if not UI.has_method(&"register_panel"):
		return
	var PANEL := "res://entities/npc/shop_panel.gd"
	if ResourceLoader.exists(PANEL):
		UI.call(&"register_panel", "shop", PANEL, false)
		UI.call(&"register_panel", "upgrade", PANEL, false)


func _attach_spawner() -> void:
	if spawner != null:
		return
	var scr := load("res://entities/npc/spawn.gd") as Script
	if scr == null:
		return
	var n := scr.new() as Node
	if n == null:
		return
	n.name = "NpcSpawner"
	add_child(n)
	spawner = n


func _connect_events() -> void:
	Events.entity_died.connect(_on_entity_died)
	Events.item_picked_up.connect(_on_item_picked_up)
	Events.item_crafted.connect(_on_item_crafted)
	Events.block_changed.connect(_on_block_changed)
	Events.view_flip_finished.connect(_on_flip_finished)
	Events.layer_changed.connect(_on_layer_changed)
	Events.travel_finished.connect(_on_travel_finished)
	Events.travel_started.connect(_on_travel_started)
	Events.dialogue_started.connect(_on_dialogue_started)
	Events.dialogue_ended.connect(_on_dialogue_ended)
	Events.player_died.connect(_on_player_died)


func _register_campaign() -> void:
	var d := DirAccess.open(CAMPAIGN_DIR)
	if d == null:
		return
	var files := PackedStringArray()
	for f: String in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".gd.remap"):
			files.append(f.trim_suffix(".remap"))
	files.sort()
	for f: String in files:
		var scr: Script = load(CAMPAIGN_DIR + "/" + f)
		if scr != null and scr.has_method(&"register_all"):
			scr.call(&"register_all", self)


# =========================================================================
#  Registry
# =========================================================================
## Creates, registers and returns a new definition for fluent building.
func define(quest_id: String, title: String = "") -> QuestDef:
	var q := QuestDef.new(quest_id, title)
	register(q)
	return q


func register(q: QuestDef, generated: bool = false) -> QuestDef:
	if q == null or q.id == "":
		return q
	defs[q.id] = q
	if generated:
		_generated[q.id] = true
	return q


func get_def(quest_id: String) -> QuestDef:
	return defs.get(quest_id)


func has_def(quest_id: String) -> bool:
	return defs.has(quest_id)


## The live copy while active, otherwise the template. Never null-checks for you.
func quest_of(quest_id: String) -> QuestDef:
	if active.has(quest_id):
		return active[quest_id]
	return defs.get(quest_id)


# =========================================================================
#  Flags
# =========================================================================
func set_flag(flag: String, value: bool = true) -> void:
	if flag == "":
		return
	if value:
		flags[flag] = true
	else:
		flags.erase(flag)


func get_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


# =========================================================================
#  Offer / start / finish
# =========================================================================
## Marks a quest as available from [param giver] and announces it. The menus
## agent listens to [signal Events.quest_offered] to raise the accept window.
func offer(quest_id: String, giver: Node) -> void:
	# The menus panel routes baked dialogue effects back through here; see
	# QuestDialogue.EFFECT_TOKEN.
	if QuestDialogue.is_effect_token(quest_id):
		QuestDialogue.apply_effect_token(quest_id, giver)
		return
	var q := get_def(quest_id)
	if q == null and quest_id.begins_with("distress_"):
		# An item or beacon offered a quest we have never heard of: mint one.
		q = _mint_for_unknown(quest_id, giver)
	if q == null:
		push_warning("[Quests] offer() on unknown quest '%s'" % quest_id)
		return
	if is_active(quest_id) or (is_completed(quest_id) and not q.repeatable):
		return
	var giver_id := ""
	if giver != null:
		var gv: Variant = giver.get("npc_id")
		giver_id = String(gv) if gv != null else giver.name
	offered[quest_id] = giver_id
	Events.quest_offered.emit(quest_id, giver)
	Events.toast("New quest: %s" % q.title, "quest")


## Builds a real quest behind an id somebody invented at runtime — the distress
## beacon item does this — so the offer is never a dead link.
func _mint_for_unknown(quest_id: String, giver: Node) -> QuestDef:
	if generator == null:
		return null
	var q := generator.generate(giver, hash(quest_id))
	if q == null:
		return null
	q.id = quest_id
	q.title = "Distress Signal"
	q.summary = "Someone on %s is broadcasting for help. Answer it." % \
		String(Universe.planet_meta(World.planet_id).get("name", World.planet_id))
	register(q, true)
	return q


func is_offered(quest_id: String) -> bool:
	return offered.has(quest_id)


func withdraw(quest_id: String) -> void:
	offered.erase(quest_id)


## Every quest [param npc_id] can currently hand out.
func offers_of(npc_id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for k: Variant in defs:
		var q: QuestDef = defs[k]
		if q.giver == npc_id and can_start(q.id):
			out.append(q.id)
	return out


## True when every gate (prerequisites, exclusions, flags, reputation) passes.
func can_start(quest_id: String) -> bool:
	var q := get_def(quest_id)
	if q == null:
		return false
	if active.has(quest_id):
		return false
	if completed.has(quest_id) and not q.repeatable:
		return false
	for p: String in q.prerequisites:
		if not completed.has(p):
			return false
	for e: String in q.excludes:
		if active.has(e) or completed.has(e):
			return false
	for f: String in q.required_flags:
		if not get_flag(f):
			return false
	if q.required_reputation != 0:
		if NpcReputation.value_of(q.reputation_faction) < float(q.required_reputation):
			return false
	return true


## Accepts a quest. Returns false when it is gated or unknown.
func start(quest_id: String) -> bool:
	if not can_start(quest_id):
		return false
	var q: QuestDef = (defs[quest_id] as QuestDef).instantiate()
	active[quest_id] = q
	offered.erase(quest_id)
	failed.erase(quest_id)
	if q.time_limit > 0.0:
		_timers[quest_id] = q.time_limit
	var current: QuestDef = quest_of(tracked) if tracked != "" else null
	if current == null or (q.is_main and not current.is_main):
		tracked = quest_id
	Events.quest_started.emit(quest_id)
	Events.toast("Quest started: %s" % q.title, "quest")
	Events.play_sound.emit(&"quest_start", _player_pos())
	# Objectives that are already satisfied (items in the bag, planet underfoot).
	_rescan_collect()
	_housekeeping(0.0)
	return true


func is_active(quest_id: String) -> bool:
	return active.has(quest_id)


func is_completed(quest_id: String) -> bool:
	return completed.has(quest_id)


func is_failed(quest_id: String) -> bool:
	return failed.has(quest_id)


## All required objectives met; waiting only on the turn-in conversation.
func is_ready_to_turn_in(quest_id: String) -> bool:
	return _ready_to_hand_in.has(quest_id)


## Finishes a quest and pays out. Called automatically for quests with no
## turn-in NPC, and by dialogue effects for the rest.
func complete(quest_id: String) -> bool:
	if not active.has(quest_id):
		return false
	var q: QuestDef = active[quest_id]
	var branch_id := _apply_branches(q)
	_grant_rewards(q)
	active.erase(quest_id)
	_timers.erase(quest_id)
	_ready_to_hand_in.erase(quest_id)
	completed[quest_id] = {"day": Game.day, "branch": branch_id}
	for f: String in q.sets_flags:
		set_flag(f)
	if tracked == quest_id:
		tracked = ""
		_retrack()
	Events.quest_completed.emit(quest_id)
	Events.play_sound.emit(&"quest_complete", _player_pos())
	Events.toast("Quest complete: %s" % q.title, "good")
	Game.bump_stat("quests_completed", 1.0)
	for u: String in q.unlocks:
		if can_start(u):
			offer(u, _npc_named(get_def(u).giver))
	return true


func fail(quest_id: String, reason: String = "failed") -> bool:
	if not active.has(quest_id):
		return false
	var q: QuestDef = active[quest_id]
	active.erase(quest_id)
	_timers.erase(quest_id)
	_ready_to_hand_in.erase(quest_id)
	failed[quest_id] = reason
	if tracked == quest_id:
		tracked = ""
		_retrack()
	Events.quest_failed.emit(quest_id)
	Events.toast("Quest failed: %s" % q.title, "bad")
	return true


## Player-initiated cancel. Repeatable and generated quests can be retaken.
func abandon(quest_id: String) -> bool:
	if not active.has(quest_id):
		return false
	var q: QuestDef = active[quest_id]
	active.erase(quest_id)
	_timers.erase(quest_id)
	_ready_to_hand_in.erase(quest_id)
	if tracked == quest_id:
		tracked = ""
		_retrack()
	if q.giver != &"":
		NpcReputation.adjust_npc(q.giver, -4.0)
	Events.quest_failed.emit(quest_id)
	Events.toast("Abandoned: %s" % q.title, "warn")
	return true


func track(quest_id: String) -> void:
	if active.has(quest_id) or quest_id == "":
		tracked = quest_id


func _retrack() -> void:
	for k: Variant in active:
		var q: QuestDef = active[k]
		if q.is_main:
			tracked = String(k)
			return
	for k: Variant in active:
		tracked = String(k)
		return


# =========================================================================
#  The funnel
# =========================================================================
## Every fact about the world that a quest could care about comes through here.
## See the table at the top of this file for the vocabulary.
func report(kind: StringName, key: Variant, amount: int = 1) -> void:
	# Perspective reports also re-evaluate every spatial/OBSERVE objective, since
	# the player's plane or layer is exactly what those are watching.
	var spatial := kind == &"flip" or kind == &"shift" or kind == &"reach"
	if amount == 0 or active.is_empty():
		if spatial:
			_evaluate_spatial()
		return
	var item_key: Variant = key
	var to_npc := &""
	if kind == &"deliver":
		var s := str(key)
		if s.contains("@"):
			var parts := s.split("@", false, 1)
			item_key = parts[0]
			to_npc = StringName(parts[1])
		elif _last_talked != &"":
			to_npc = _last_talked
	for qid: Variant in active.keys():
		var q: QuestDef = active[qid]
		var touched := false
		for i in q.objectives.size():
			var o: QuestObjective = q.objectives[i]
			if not o.matches(kind, item_key):
				continue
			if o.kind == QuestObjective.Kind.DELIVER and o.deliver_to != &"" \
					and to_npc != &"" and o.deliver_to != to_npc:
				continue
			if o.planet_id != "" and o.planet_id != World.planet_id:
				continue
			o.add(amount)
			Events.quest_objective_updated.emit(String(qid), i, o.progress, o.goal)
			touched = true
		if touched:
			_check_completion(String(qid))
	if spatial:
		_evaluate_spatial()


## Convenience wrapper for handing goods to an NPC.
func deliver(npc_id: StringName, item_id: StringName, count: int = 1) -> void:
	report(&"deliver", "%s@%s" % [item_id, npc_id], count)


# =========================================================================
#  Housekeeping tick
# =========================================================================
func _process(delta: float) -> void:
	if Game.paused or active.is_empty():
		return
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL:
		_housekeeping(_tick_accum)
		_tick_accum = 0.0
	_rescan_accum += delta
	if _rescan_accum >= RESCAN_INTERVAL:
		_rescan_accum = 0.0
		_rescan_collect()


func _housekeeping(delta: float) -> void:
	_advance_timers(delta)
	_advance_survive(delta)
	_evaluate_spatial()


func _advance_timers(delta: float) -> void:
	if delta <= 0.0 or _timers.is_empty():
		return
	for qid: Variant in _timers.keys():
		_timers[qid] = float(_timers[qid]) - delta
		if float(_timers[qid]) <= 0.0:
			var q: QuestDef = active.get(qid)
			fail(String(qid), q.fail_text if q != null and q.fail_text != "" else "out of time")


func _advance_survive(delta: float) -> void:
	if delta <= 0.0:
		return
	for qid: Variant in active.keys():
		var q: QuestDef = active[qid]
		var touched := false
		for i in q.objectives.size():
			var o: QuestObjective = q.objectives[i]
			if o.kind != QuestObjective.Kind.SURVIVE or o.done:
				continue
			var before := o.progress
			# `duration` doubles as the live countdown; `goal` stays the total.
			o.duration = maxf(0.0, o.duration - delta)
			o.set_progress(int(float(o.goal) - o.duration))
			if o.progress != before:
				Events.quest_objective_updated.emit(String(qid), i, o.progress, o.goal)
				touched = true
		if touched:
			_check_completion(String(qid))


## Proximity, escort and OBSERVE evaluation. This is where the perspective
## objectives live: an observe objective ticks the instant the player is in the
## right place, in the right plane, on the right layer, seeing the right thing.
func _evaluate_spatial() -> void:
	var p := Game.player
	if p == null or active.is_empty():
		return
	var pos := p.global_position
	for qid: Variant in active.keys():
		var q: QuestDef = active[qid]
		var touched := false
		for i in q.objectives.size():
			var o: QuestObjective = q.objectives[i]
			if o.done or o.failed or o.custom_kind != &"":
				continue     # custom-kind objectives are report-driven only
			var hit := false
			match o.kind:
				QuestObjective.Kind.VISIT:
					hit = _near(o, pos)
				QuestObjective.Kind.EXPLORE:
					# With coordinates it is proximity; without, it is a biome
					# name. Named landmarks arrive through report(&"explore", id)
					# from the structure-anchor watcher in entities/npc/spawn.gd.
					if o.has_location():
						hit = _near(o, pos)
					elif _planet_ok(o) and o.key != &"":
						hit = PlanetGen.biome_at(int(pos.x), int(pos.z)) == o.key
				QuestObjective.Kind.OBSERVE:
					hit = _observation_met(o, pos)
				QuestObjective.Kind.ESCORT:
					hit = _escort_met(o, q, String(qid))
				_:
					continue
			if hit:
				o.add(1)
				Events.quest_objective_updated.emit(String(qid), i, o.progress, o.goal)
				touched = true
		if touched:
			_check_completion(String(qid))


func _planet_ok(o: QuestObjective) -> bool:
	return o.planet_id == "" or o.planet_id == World.planet_id


func _near(o: QuestObjective, pos: Vector3) -> bool:
	if not _planet_ok(o):
		return false
	if not o.has_location():
		# A VISIT with no coordinates is satisfied by the planet id alone.
		return o.kind == QuestObjective.Kind.VISIT and String(o.key) == World.planet_id
	return pos.distance_to(o.location) <= o.radius


## The heart of the OBSERVE objective.
func _observation_met(o: QuestObjective, pos: Vector3) -> bool:
	if not _planet_ok(o):
		return false
	# A wholly unconstrained observation would tick instantly; treat it as a bug
	# in the quest data rather than free progress.
	if not o.has_location() and o.view_index < 0 and o.layer == QuestObjective.ANY_LAYER \
			and o.observe_block == &"":
		return false
	if o.has_location() and pos.distance_to(o.location) > o.radius:
		return false
	if o.view_index >= 0 and View.view != o.view_index:
		return false
	if View.flipping:
		return false
	if o.layer != QuestObjective.ANY_LAYER and View.layer != o.layer:
		return false
	if o.observe_block == &"":
		return true
	return _sees_block(pos, o.observe_block, o.observe_range)


## Casts along the camera axis (and back along it) from the player's eyeline and
## reports whether the named block is the first thing hit — i.e. whether it is
## genuinely visible from this plane rather than buried behind a wall.
func _sees_block(from: Vector3, block_name: StringName, max_dist: float) -> bool:
	var want := Blocks.id(block_name)
	if want == Const.AIR:
		return false
	var eye := from + Vector3(0, 1.4, 0)
	for dir: Vector3 in [Vector3(View.forward()), -Vector3(View.forward())]:
		var r := World.raycast(eye, dir, max_dist)
		if bool(r.get("hit", false)) and World.get_block(r["pos"]) == want:
			return true
	# Also accept the block simply being on the player's own layer nearby: a
	# shrine glyph the player is standing inside counts as seen.
	var base := Const.floor_v(eye)
	for d in range(-2, 3):
		var probe := base + Vector3i(View.right()) * d
		if World.get_block(World.normalize(probe)) == want:
			return true
	return false


func _escort_met(o: QuestObjective, q: QuestDef, qid: String) -> bool:
	var npc := _npc_named(o.key)
	if npc == null:
		return false
	var e := npc as VoxelEntity
	if e != null and e.dead:
		o.failed = true
		if q.fail_conditions.has(QuestDef.Fail.ESCORT_DIED):
			fail(qid, "%s did not survive" % String(o.key))
		return false
	if not o.has_location():
		return false
	return (npc as Node3D).global_position.distance_to(o.location) <= o.radius


func _rescan_collect() -> void:
	if active.is_empty():
		return
	for qid: Variant in active.keys():
		var q: QuestDef = active[qid]
		var touched := false
		for i in q.objectives.size():
			var o: QuestObjective = q.objectives[i]
			if o.kind != QuestObjective.Kind.COLLECT or o.done or o.key == &"":
				continue
			var held := NpcInventoryBridge.count_of(o.key)
			if held > o.progress:
				o.set_progress(held)
				Events.quest_objective_updated.emit(String(qid), i, o.progress, o.goal)
				touched = true
		if touched:
			_check_completion(String(qid))


func _check_completion(quest_id: String) -> void:
	var q: QuestDef = active.get(quest_id)
	if q == null:
		return
	for o: QuestObjective in q.objectives:
		if not o.optional and not o.done:
			return
	if q.turn_in == &"":
		complete(quest_id)
		return
	if not _ready_to_hand_in.has(quest_id):
		_ready_to_hand_in[quest_id] = true
		var who := q.giver_name if q.giver_name != "" else String(q.turn_in).capitalize()
		Events.toast("Return to %s: %s" % [who, q.title], "quest")
		Events.play_sound.emit(&"quest_step", _player_pos())


# =========================================================================
#  Rewards & branching
# =========================================================================
func _apply_branches(q: QuestDef) -> String:
	for b: Dictionary in q.branches:
		var when: Variant = b.get("when", null)
		var passed := false
		if when is Callable:
			var c := when as Callable
			passed = c.is_valid() and bool(c.call())
		elif when is Dictionary:
			passed = QuestDialogue.check(when as Dictionary, _npc_named(q.giver))
		elif when == null:
			passed = true
		if passed:
			q.reward_pixels += int(b.get("pixels", 0))
			for f: Variant in b.get("flags", []):
				set_flag(String(f))
			var nxt := String(b.get("next", ""))
			if nxt != "" and has_def(nxt):
				q.unlocks.append(nxt)
			var txt := String(b.get("text", ""))
			if txt != "":
				Events.toast(txt, "quest")
			return String(b.get("id", ""))
	return ""


func _grant_rewards(q: QuestDef) -> void:
	if q.reward_pixels > 0:
		NpcInventoryBridge.add_pixels(q.reward_pixels)
	for r: Dictionary in q.reward_items:
		NpcInventoryBridge.give(StringName(r.get("id", "")), int(r.get("count", 1)))
	for r: StringName in q.reward_recipes:
		NpcInventoryBridge.learn_recipe(r)
	for t: StringName in q.reward_techs:
		NpcInventoryBridge.unlock_tech(t)
	for f: Variant in q.reward_reputation:
		NpcReputation.adjust(StringName(f), float(q.reward_reputation[f]))
	if q.giver != &"":
		NpcReputation.adjust_npc(q.giver, 6.0)


# =========================================================================
#  Event wiring
# =========================================================================
func _on_entity_died(e: Node) -> void:
	if e == null or e == Game.player:
		return
	var id := _species_of(e)
	var ve := e as VoxelEntity
	if ve != null and ve.faction == &"hostile":
		report(&"kill", id, 1)
	elif e.is_in_group(&"npc"):
		_on_npc_died(id)
	else:
		report(&"kill", id, 1)


func _on_npc_died(npc_id: StringName) -> void:
	NpcCrew.dismiss(npc_id)
	for qid: Variant in active.keys():
		var q: QuestDef = active[qid]
		if q.giver == npc_id and q.fail_conditions.has(QuestDef.Fail.GIVER_DIED):
			fail(String(qid), "the client is dead")
			continue
		for o: QuestObjective in q.objectives:
			if o.kind == QuestObjective.Kind.ESCORT and o.key == npc_id and not o.done:
				o.failed = true
				if q.fail_conditions.has(QuestDef.Fail.ESCORT_DIED):
					fail(String(qid), "%s did not survive" % String(npc_id))


func _on_item_picked_up(item_id: String, count: int) -> void:
	report(&"collect", StringName(item_id), count)


func _on_item_crafted(item_id: String, count: int) -> void:
	report(&"craft", StringName(item_id), count)
	report(&"collect", StringName(item_id), count)


func _on_block_changed(_pos: Vector3i, old_id: int, new_id: int) -> void:
	if new_id != Const.AIR:
		var bt := Blocks.get_type(new_id)
		if bt != null:
			report(&"build", bt.name, 1)
	elif old_id != Const.AIR:
		var bt := Blocks.get_type(old_id)
		if bt != null:
			report(&"mine", bt.name, 1)


func _on_flip_finished(view: int) -> void:
	report(&"flip", view, 1)


func _on_layer_changed(layer: int, _view: int) -> void:
	report(&"shift", layer, 1)


func _on_travel_finished(planet_id: String) -> void:
	report(&"visit", StringName(planet_id), 1)
	_evaluate_spatial()
	_begin_campaign()


## Chapter one is the crash landing, so it starts itself: there is nobody left
## alive to hand it to you. Every later chapter is unlocked by the previous one.
func _begin_campaign() -> void:
	if completed.has("main_01_crash") or active.has("main_01_crash"):
		return
	if has_def("main_01_crash"):
		start("main_01_crash")


func _on_travel_started(_from_id: String, _to_id: String) -> void:
	for qid: Variant in active.keys():
		var q: QuestDef = active[qid]
		if q.fail_conditions.has(QuestDef.Fail.LEFT_PLANET):
			fail(String(qid), "you left the planet")


func _on_dialogue_started(npc: Node, _tree_id: String) -> void:
	if npc == null:
		return
	var id := StringName(npc.get("npc_id"))
	if id == &"":
		return
	_last_talked = id
	report(&"talk", id, 1)


## The dialogue window can be closed by the player rather than by the runtime;
## this keeps [QuestDialogue] and the NPC's `in_conversation` flag honest.
func _on_dialogue_ended() -> void:
	QuestDialogue.notify_closed()


func _on_player_died(_cause: String) -> void:
	for qid: Variant in active.keys():
		var q: QuestDef = active[qid]
		if q.fail_conditions.has(QuestDef.Fail.PLAYER_DEATH):
			fail(String(qid), "you died")


# =========================================================================
#  Read API for the HUD / quest log
# =========================================================================
## [{id, title, summary, tracked, main, ready, objectives:[{text, progress,
##   goal, done, optional, hidden}], rewards:[String], timer:float}]
func log_entries(include_completed: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for qid: Variant in active:
		out.append(entry_of(String(qid)))
	if include_completed:
		for qid: Variant in completed:
			var q := get_def(String(qid))
			if q == null:
				continue
			out.append({
				"id": String(qid), "title": q.title, "summary": q.summary,
				"tracked": false, "main": q.is_main, "ready": false,
				"done": true, "objectives": [], "rewards": q.reward_lines(),
				"timer": 0.0,
			})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("main", false)) > int(b.get("main", false)))
	return out


func entry_of(quest_id: String) -> Dictionary:
	var q: QuestDef = quest_of(quest_id)
	if q == null:
		return {}
	var objs: Array[Dictionary] = []
	for o: QuestObjective in q.objectives:
		if o.hidden and not o.revealed:
			continue
		objs.append({
			"text": o.describe(), "progress": o.progress, "goal": o.goal,
			"done": o.done, "failed": o.failed, "optional": o.optional,
			"kind": String(o.kind_name()), "ratio": o.ratio(),
			"location": o.location, "view": o.view_index,
		})
	return {
		"id": quest_id, "title": q.title, "summary": q.summary,
		"flavour": q.flavour, "giver": q.giver_name,
		"tracked": tracked == quest_id, "main": q.is_main, "chapter": q.chapter,
		"ready": is_ready_to_turn_in(quest_id), "done": completed.has(quest_id),
		"objectives": objs, "rewards": q.reward_lines(),
		"timer": float(_timers.get(quest_id, 0.0)),
	}


## Objectives of a live quest, for anyone who wants the objects themselves.
func objectives_of(quest_id: String) -> Array[QuestObjective]:
	var q: QuestDef = quest_of(quest_id)
	if q == null:
		var empty: Array[QuestObjective] = []
		return empty
	return q.objectives


func active_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: Variant in active:
		out.append(String(k))
	return out


## Waypoint the HUD compass should point at, or Vector3.INF.
func tracked_waypoint() -> Vector3:
	if tracked == "" or not active.has(tracked):
		return Vector3.INF
	var q: QuestDef = active[tracked]
	for o: QuestObjective in q.objectives:
		if not o.done and o.has_location():
			return o.location
	return Vector3.INF


## Which viewing plane the tracked objective wants, or -1. The HUD uses this to
## nudge the player toward a flip.
func tracked_view_hint() -> int:
	if tracked == "" or not active.has(tracked):
		return -1
	var q: QuestDef = active[tracked]
	for o: QuestObjective in q.objectives:
		if not o.done and o.kind == QuestObjective.Kind.OBSERVE and o.view_index >= 0:
			return o.view_index
	return -1


# =========================================================================
#  Compatibility shims for the menus / HUD agents
#
#  `ui/menus/quest_log.gd`, `ui/hud/quest_tracker.gd` and
#  `ui/menus/dialogue_panel.gd` probe this autoload for a handful of method
#  names before falling back to raw dictionaries. These are those names, mapped
#  onto the real API above so those panels light up with no changes.
# =========================================================================
## `state` is "active", "completed", "failed" or "all".
func list(state: String = "active") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match state.to_lower():
		"active", "current", "in_progress":
			for k: Variant in active:
				out.append(entry_of(String(k)))
		"completed", "complete", "done":
			for k: Variant in completed:
				out.append(entry_of(String(k)))
		"failed", "abandoned":
			for k: Variant in failed:
				out.append(entry_of(String(k)))
		_:
			out = log_entries(true)
	return out


## Read-model of one quest. Aliased under every name the UI probes for.
func quest_def(quest_id: String) -> Dictionary:
	var d := entry_of(quest_id)
	if not d.is_empty():
		d["name"] = d["title"]
		d["description"] = d["summary"]
	return d


func quest_data(quest_id: String) -> Dictionary:
	return quest_def(quest_id)


func definition(quest_id: String) -> Dictionary:
	return quest_def(quest_id)


func get_quest(quest_id: String) -> Dictionary:
	return quest_def(quest_id)


func info(quest_id: String) -> Dictionary:
	return quest_def(quest_id)


func objectives(quest_id: String) -> Array:
	return entry_of(quest_id).get("objectives", [])


func quest_title(quest_id: String) -> String:
	var q := quest_of(quest_id)
	return q.title if q != null else ""


func set_tracked(quest_id: String) -> void:
	track(quest_id)


## Dialogue tree in the panel's shape. See [method QuestDialogue.to_panel_tree].
func dialogue_tree(tree_id: String) -> Dictionary:
	return QuestDialogue.to_panel_tree(tree_id, QuestDialogue.speaker_node())


func get_dialogue(tree_id: String) -> Dictionary:
	return dialogue_tree(tree_id)


# =========================================================================
#  Procedural side quests
# =========================================================================
## Rolls a fresh side quest for [param npc] against the current planet and
## registers it. Returns the new quest id, or "" when nothing suitable existed.
func generate_for(npc: Node, quest_seed: int = 0) -> String:
	if generator == null:
		return ""
	var q := generator.generate(npc, quest_seed)
	if q == null:
		return ""
	register(q, true)
	return q.id


# =========================================================================
#  Helpers
# =========================================================================
func _npc_named(npc_id: StringName) -> Node:
	if npc_id == &"":
		return null
	for n: Node in get_tree().get_nodes_in_group(&"npc"):
		if StringName(n.get("npc_id")) == npc_id:
			return n
	return null


static func _species_of(e: Node) -> StringName:
	for f: String in ["species", "monster_id", "npc_id", "entity_id", "type_id"]:
		var v: Variant = e.get(f)
		if v != null and str(v) != "":
			return StringName(str(v))
	if e.has_meta(&"species"):
		return StringName(str(e.get_meta(&"species")))
	return StringName(String(e.name).to_snake_case())


func _player_pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO


# =========================================================================
#  Persistence
# =========================================================================
func save_state() -> Dictionary:
	var act := {}
	for k: Variant in active:
		var q: QuestDef = active[k]
		act[String(k)] = q.to_dict(_generated.has(String(k)))
	var comp := {}
	for k: Variant in completed:
		comp[String(k)] = completed[k]
	var fl := {}
	for k: Variant in failed:
		fl[String(k)] = String(failed[k])
	var off := {}
	for k: Variant in offered:
		off[String(k)] = String(offered[k])
	var tm := {}
	for k: Variant in _timers:
		tm[String(k)] = float(_timers[k])
	var gen := {}
	for k: Variant in _generated:
		var q: QuestDef = defs.get(String(k))
		if q != null:
			gen[String(k)] = q.to_dict(true)
	return {
		"active": act, "completed": comp, "failed": fl, "offered": off,
		"flags": flags.duplicate(), "tracked": tracked, "timers": tm,
		"ready": _ready_to_hand_in.duplicate(), "generated": gen,
		"reputation": NpcReputation.save_state(),
		"crew": NpcCrew.save_state(),
		"dialogue": QuestDialogue.save_state(),
		"gen_counter": generator.counter if generator != null else 0,
	}


func load_state(d: Dictionary) -> void:
	_boot()
	active.clear()
	completed.clear()
	failed.clear()
	offered.clear()
	_timers.clear()
	_ready_to_hand_in.clear()
	flags = (d.get("flags", {}) as Dictionary).duplicate()
	tracked = String(d.get("tracked", ""))

	# Generated definitions first: live quests may point at them.
	for k: Variant in d.get("generated", {}):
		var q := QuestDef.from_dict(d["generated"][k] as Dictionary)
		register(q, true)

	for k: Variant in d.get("active", {}):
		var saved := d["active"][k] as Dictionary
		var live: QuestDef
		if bool(saved.get("full", false)):
			live = QuestDef.from_dict(saved)
		else:
			var tmpl := get_def(String(k))
			if tmpl == null:
				continue
			live = tmpl.instantiate()
			live.objectives.clear()
			for od: Variant in saved.get("objectives", []):
				live.objectives.append(QuestObjective.from_dict(od as Dictionary))
			if live.objectives.is_empty():
				live = tmpl.instantiate()
		active[String(k)] = live
	for k: Variant in d.get("completed", {}):
		completed[String(k)] = d["completed"][k]
	for k: Variant in d.get("failed", {}):
		failed[String(k)] = String(d["failed"][k])
	for k: Variant in d.get("offered", {}):
		offered[String(k)] = String(d["offered"][k])
	for k: Variant in d.get("timers", {}):
		_timers[String(k)] = float(d["timers"][k])
	for k: Variant in d.get("ready", {}):
		_ready_to_hand_in[String(k)] = true

	NpcReputation.load_state(d.get("reputation", {}) as Dictionary)
	NpcCrew.load_state(d.get("crew", {}) as Dictionary)
	QuestDialogue.load_state(d.get("dialogue", {}) as Dictionary)
	if generator != null:
		generator.counter = int(d.get("gen_counter", 0))
