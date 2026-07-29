## The branching dialogue runtime. Data in, read-model out — this file owns no
## pixels. The menus agent draws the window; it drives it entirely through the
## small API in the "PUBLIC API" section below.
##
## [b]For the menus agent[/b] — everything is static, so no node lookup is
## needed. Give yourself a short name at the top of your script:
## [codeblock]
## const Dialogue := preload("res://quests/dialogue.gd")
##
## Dialogue.begin(npc, "merchant_default")     # opens; emits Events.dialogue_started
## var n := Dialogue.current_node()            # {speaker, text, page, page_count, ...}
## for c in Dialogue.choices():                # [{index, text, enabled, hint}]
##     ...
## Dialogue.choose(i)                          # take a choice
## Dialogue.advance()                          # no choices: next page / next node
## Dialogue.is_finished()                      # true once the tree ended
## Dialogue.end()                              # player closed the window
## [/codeblock]
## [member current_node] never returns null — when nothing is running it returns
## an empty Dictionary, so [code]n.is_empty()[/code] is the "no dialogue" test.
## Text is returned as plain UTF-8 with no markup, one page at a time, so a
## typewriter can simply slice it: [code]n.text.substr(0, chars)[/code].
##
## [b]Tree format[/b] (see `quests/dialogue_trees/` for real examples):
## [codeblock]
## {
##   "id": "blacksmith_default",
##   "speaker": "{npc}",                # {npc} expands to the NPC's name
##   "start": "root",
##   "nodes": {
##     "root": {
##       "text": ["Line one.", "Line two is a second page."],
##       "when": [{"type": "reputation", "min": 10}],   # gate; else -> "cold"
##       "else": "cold",
##       "do":   [{"type": "report", "kind": "talk", "key": "{npc_id}"}],
##       "choices": [
##         {"text": "Show me your wares.", "do": [{"type": "open_shop"}], "next": "root"},
##         {"text": "Goodbye.", "next": "#end"},
##       ],
##     },
##   },
## }
## [/codeblock]
## `next` may be a node id, `"#end"` to close, or omitted (falls through to the
## node's own `next`, then to `#end`).
class_name QuestDialogue
extends RefCounted

const TREE_DIR := "res://quests/dialogue_trees"
const END := "#end"

# ------------------------------------------------------------- static state
static var _trees: Dictionary = {}          ## id -> tree Dictionary
static var _loaded := false

static var _npc: Node = null
static var _tree_id: String = ""
static var _node_id: String = ""
static var _page: int = 0
static var _pages: PackedStringArray = PackedStringArray()
static var _finished: bool = true
static var _visible: Array[Dictionary] = []  ## resolved choices for _node_id
static var _taken: Dictionary = {}           ## "tree/node/idx" -> true (once-only)
static var _vars: Dictionary = {}            ## conversation-scoped scratch
static var _rng := RandomNumberGenerator.new()
static var _closing := false


# =========================================================================
#  PUBLIC API — the menus agent only needs these eight calls.
# =========================================================================

## Opens [param tree_id] on [param npc]. When [param tree_id] is empty the NPC is
## asked for its own tree (role default, quest override, campaign override).
## Returns false when there is nothing to say. Emits [signal Events.dialogue_started].
static func begin(npc: Node, tree_id: String = "") -> bool:
	ensure_loaded()
	var tid := tree_id
	if tid == "" and npc != null and npc.has_method(&"dialogue_tree_id"):
		tid = String(npc.call(&"dialogue_tree_id"))
	if tid == "" or not _trees.has(tid):
		tid = _fallback_tree(npc, tid)
	if tid == "":
		return false
	_npc = npc
	_tree_id = tid
	_vars.clear()
	_finished = false
	_rng.seed = hash(tid) ^ Time.get_ticks_msec()
	var start := String((_trees[tid] as Dictionary).get("start", "root"))
	_goto(start)
	Events.dialogue_started.emit(npc, tid)
	return not _finished


## The line currently on screen. Empty Dictionary when no dialogue is running.
## Keys: `tree`, `node`, `speaker`, `text`, `page`, `page_count`, `last_page`,
## `portrait` (Color), `npc`, `has_choices`, `is_end`, `mood`.
static func current_node() -> Dictionary:
	if _finished and _pages.is_empty():
		return {}
	var nd := _node()
	var speaker := _speaker_for(nd)
	return {
		"tree": _tree_id,
		"node": _node_id,
		"speaker": speaker,
		"text": _pages[_page] if _page < _pages.size() else "",
		"page": _page,
		"page_count": _pages.size(),
		"last_page": _page >= _pages.size() - 1,
		"portrait": _portrait_color(),
		"mood": String(nd.get("mood", "neutral")),
		"npc": _npc,
		"has_choices": not _visible.is_empty() and _page >= _pages.size() - 1,
		"is_end": _finished,
	}


## Choices for the current node, already condition-filtered.
## Each entry: `{index:int, text:String, enabled:bool, hint:String}`.
## Disabled entries are shown greyed out (e.g. "[need 200 pixels]").
## Empty while earlier pages of a multi-page line are still showing.
static func choices() -> Array[Dictionary]:
	if _finished or _page < _pages.size() - 1:
		return []
	return _visible.duplicate()


## Takes choice [param index] from [method choices].
static func choose(index: int) -> void:
	if _finished or index < 0 or index >= _visible.size():
		return
	var c := _visible[index]
	if not bool(c.get("enabled", true)):
		return
	var src := c.get("_src", {}) as Dictionary
	if bool(src.get("once", false)):
		_taken["%s/%s/%d" % [_tree_id, _node_id, int(c.get("_i", index))]] = true
	_run_effects(src.get("do", []) as Array)
	if bool(src.get("closes", false)):
		end()
		return
	var nxt := String(src.get("next", ""))
	if nxt == "":
		nxt = String(_node().get("next", END))
	_goto(nxt)


## Advances a multi-page line, or follows the node's `next` when the node has no
## choices. Safe to call on a choice node — it does nothing there.
static func advance() -> void:
	if _finished:
		return
	if _page < _pages.size() - 1:
		_page += 1
		return
	if not _visible.is_empty():
		return
	_goto(String(_node().get("next", END)))


static func is_finished() -> bool:
	return _finished


## Closes the conversation. Emits [signal Events.dialogue_ended] exactly once.
static func end() -> void:
	if _finished and _npc == null:
		return
	if _closing:
		return
	_closing = true
	_teardown()
	Events.dialogue_ended.emit()
	_closing = false


## Called when something *else* closed the conversation — the window's own close
## button, a pause, a scene change. Tears the runtime down without re-emitting
## [signal Events.dialogue_ended] (which is what woke us).
static func notify_closed() -> void:
	if _closing:
		return
	_teardown()


static func _teardown() -> void:
	var was := _npc
	_finished = true
	_visible.clear()
	_pages = PackedStringArray()
	_npc = null
	_node_id = ""
	if was != null and is_instance_valid(was) and was.has_method(&"on_dialogue_ended"):
		was.call(&"on_dialogue_ended")


## Whichever NPC is being talked to, or null.
static func speaker_node() -> Node:
	return _npc


## Convenience for a bare typewriter: the visible text of the current page.
static func text() -> String:
	var n := current_node()
	return String(n.get("text", ""))


# =========================================================================
#  Tree registry
# =========================================================================

## Registers (or replaces) one tree. `tree.id` is the key.
static func register_tree(tree: Dictionary) -> void:
	var id := String(tree.get("id", ""))
	if id == "":
		push_warning("[Dialogue] tree with no id ignored")
		return
	_trees[id] = tree


## Bulk register: `{id: tree, ...}` or `[tree, tree, ...]`.
static func register_many(batch: Variant) -> void:
	if batch is Array:
		for t: Variant in batch:
			register_tree(t as Dictionary)
	elif batch is Dictionary:
		for k: Variant in batch:
			var t := (batch as Dictionary)[k] as Dictionary
			if not t.has("id"):
				t["id"] = String(k)
			register_tree(t)


static func has_tree(id: String) -> bool:
	ensure_loaded()
	return _trees.has(id)


static func tree_def(id: String) -> Dictionary:
	ensure_loaded()
	return _trees.get(id, {})


static func tree_ids() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for k: Variant in _trees:
		out.append(String(k))
	out.sort()
	return out


## Scans `quests/dialogue_trees/*.gd` for `static func register_all(d)` and runs
## each one. Idempotent; called lazily by every entry point.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var d := DirAccess.open(TREE_DIR)
	if d == null:
		return
	var files := PackedStringArray()
	for f: String in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".gd.remap"):
			files.append(f.trim_suffix(".remap"))
	files.sort()
	for f: String in files:
		var scr: Script = load(TREE_DIR + "/" + f)
		if scr != null and scr.has_method(&"register_all"):
			scr.call(&"register_all", QuestDialogue)


static func _fallback_tree(npc: Node, wanted: String) -> String:
	if wanted != "" and _trees.has(wanted):
		return wanted
	if npc != null:
		var role := String(npc.get("role_id"))
		if role != "" and _trees.has(role + "_default"):
			return role + "_default"
		var race := String(npc.get("race"))
		if race != "" and _trees.has("villager_" + race):
			return "villager_" + race
	if _trees.has("villager_default"):
		return "villager_default"
	return ""


# =========================================================================
#  Navigation
# =========================================================================
static func _node() -> Dictionary:
	var t := _trees.get(_tree_id, {}) as Dictionary
	var nodes := t.get("nodes", {}) as Dictionary
	return nodes.get(_node_id, {}) as Dictionary


static func _goto(node_id: String) -> void:
	var guard := 0
	var target := node_id
	while guard < 32:
		guard += 1
		if target == "" or target == END:
			end()
			return
		var t := _trees.get(_tree_id, {}) as Dictionary
		var nodes := t.get("nodes", {}) as Dictionary
		if not nodes.has(target):
			push_warning("[Dialogue] '%s' has no node '%s'" % [_tree_id, target])
			end()
			return
		var nd := nodes[target] as Dictionary
		# Node-level gate: jump to `else` (or end) when it fails.
		if nd.has("when") and not check_all(nd["when"] as Array, _npc):
			target = String(nd.get("else", END))
			continue
		_node_id = target
		_run_effects(nd.get("do", []) as Array)
		if _finished:
			return
		# `say` is a bank of interchangeable one-liners (one is picked at random);
		# `text` is the literal line, or an array of pages.
		if nd.has("say"):
			var bank := nd["say"] as Array
			_pages = PackedStringArray()
			if not bank.is_empty():
				_pages.append(substitute(String(bank[_rng.randi_range(0, bank.size() - 1)]), _npc))
		else:
			_pages = _expand_text(nd.get("text", ""))
		_page = 0
		_rebuild_choices(nd)
		if _pages.is_empty() and _visible.is_empty():
			target = String(nd.get("next", END))
			continue
		if bool(nd.get("end", false)) and _pages.is_empty():
			end()
		return
	end()


static func _expand_text(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if raw is String:
		if String(raw) != "":
			out.append(substitute(String(raw), _npc))
	elif raw is Array:
		for p: Variant in raw as Array:
			out.append(substitute(String(p), _npc))
	elif raw is PackedStringArray:
		for p: String in raw as PackedStringArray:
			out.append(substitute(p, _npc))
	return out


static func _rebuild_choices(nd: Dictionary) -> void:
	_visible.clear()
	var raw := nd.get("choices", []) as Array
	for i in raw.size():
		var c := raw[i] as Dictionary
		if bool(c.get("once", false)) and _taken.has("%s/%s/%d" % [_tree_id, _node_id, i]):
			continue
		if c.has("show_when") and not check_all(c["show_when"] as Array, _npc):
			continue
		var enabled := true
		var hint := String(c.get("hint", ""))
		if c.has("when"):
			enabled = check_all(c["when"] as Array, _npc)
			if not enabled and not bool(c.get("grey", true)):
				continue
		_visible.append({
			"index": _visible.size(),
			"text": substitute(String(c.get("text", "...")), _npc),
			"enabled": enabled,
			"hint": hint,
			"_src": c,
			"_i": i,
		})


static func _speaker_for(nd: Dictionary) -> String:
	var t := _trees.get(_tree_id, {}) as Dictionary
	var s := String(nd.get("speaker", t.get("speaker", "{npc}")))
	return substitute(s, _npc)


static func _portrait_color() -> Color:
	if _npc != null:
		var c: Variant = _npc.get("portrait_color")
		if c is Color:
			return c
	return Color(0.72, 0.78, 0.9)


# =========================================================================
#  Text substitution
# =========================================================================
## Expands `{npc}`, `{npc_id}`, `{player}`, `{planet}`, `{time}`, `{race}`,
## `{role}`, `{village}` and `{pixels}` inside a line.
static func substitute(s: String, npc: Node) -> String:
	if not s.contains("{"):
		return s
	var out := s
	var npc_name := "Stranger"
	var npc_id := ""
	var race := "human"
	var role := "villager"
	var village := "these parts"
	if npc != null:
		var v: Variant = npc.get("display_name")
		if v is String and String(v) != "":
			npc_name = String(v)
		npc_id = String(npc.get("npc_id"))
		var r: Variant = npc.get("race")
		if r != null and String(r) != "":
			race = String(r)
		var ro: Variant = npc.get("role_id")
		if ro != null and String(ro) != "":
			role = String(ro)
		var vg: Variant = npc.get("village_id")
		if vg != null and String(vg) != "":
			village = String(vg).replace("_", " ").capitalize()
	out = out.replace("{npc}", npc_name)
	out = out.replace("{npc_id}", npc_id)
	out = out.replace("{race}", race.capitalize())
	out = out.replace("{role}", role.capitalize())
	out = out.replace("{village}", village)
	out = out.replace("{player}", "Protector")
	out = out.replace("{planet}", _planet_name())
	out = out.replace("{time}", Game.time_string())
	out = out.replace("{pixels}", str(NpcInventoryBridge.pixels()))
	return out


static func _planet_name() -> String:
	var meta: Dictionary = Universe.planet_meta(World.planet_id)
	return String(meta.get("name", World.planet_id if World.planet_id != "" else "this rock"))


# =========================================================================
#  Conditions
# =========================================================================
## Evaluates every condition in [param list] (implicit AND). An empty list passes.
static func check_all(list: Array, npc: Node) -> bool:
	for c: Variant in list:
		if not check(c as Dictionary, npc):
			return false
	return true


## Evaluates one condition Dictionary. Unknown types pass, so a tree authored
## against a future module never soft-locks the conversation.
static func check(c: Dictionary, npc: Node) -> bool:
	match String(c.get("type", "")):
		"has_item":
			return NpcInventoryBridge.count_of(StringName(c.get("item", ""))) >= int(c.get("count", 1))
		"lacks_item":
			return NpcInventoryBridge.count_of(StringName(c.get("item", ""))) < int(c.get("count", 1))
		"pixels":
			return NpcInventoryBridge.pixels() >= int(c.get("min", 0))
		"quest":
			return _check_quest(c)
		"reputation":
			var key := StringName(c.get("key", ""))
			if key == &"" and npc != null:
				key = StringName(npc.get("npc_id"))
			var v := NpcReputation.value_of(key)
			return v >= float(c.get("min", -1000.0)) and v <= float(c.get("max", 1000.0))
		"race":
			if npc == null:
				return false
			return String(npc.get("race")) == String(c.get("race", ""))
		"role":
			if npc == null:
				return false
			return String(npc.get("role_id")) == String(c.get("role", ""))
		"village":
			if npc == null:
				return false
			return String(npc.get("village_id")) == String(c.get("village", ""))
		"time":
			if bool(c.get("night", false)):
				return Game.is_night()
			if bool(c.get("day", false)):
				return not Game.is_night()
			var f := Game.day_fraction
			var lo := float(c.get("from", 0.0))
			var hi := float(c.get("to", 1.0))
			if lo <= hi:
				return f >= lo and f <= hi
			return f >= lo or f <= hi   # window that wraps past midnight
		"flag":
			return Quests.get_flag(String(c.get("flag", ""))) == bool(c.get("value", true))
		"view":
			return View.view == int(c.get("view", 0))
		"planet":
			return World.planet_id == String(c.get("planet", ""))
		"stat":
			return float(Game.stats.get(String(c.get("stat", "")), 0.0)) >= float(c.get("min", 0.0))
		"crew":
			var who := StringName(c.get("npc", ""))
			if who == &"" and npc != null:
				who = StringName(npc.get("npc_id"))
			return NpcCrew.is_hired(who) == bool(c.get("hired", true))
		"crew_space":
			return NpcCrew.size() < NpcCrew.capacity()
		"can_hire":
			return NpcRoleCrew.can_hire(npc)
		"has_work":
			# True when this NPC has a quest ready to hand out.
			if npc == null or not npc.has_method(&"pending_quest_id"):
				return false
			return String(npc.call(&"pending_quest_id")) != ""
		"turn_in_ready":
			# True when a quest this NPC is owed is complete but unclaimed.
			if npc == null:
				return false
			for qid: String in Quests.active_ids():
				var q := Quests.quest_of(qid)
				if q != null and q.turn_in == StringName(npc.get("npc_id")) \
						and Quests.is_ready_to_turn_in(qid):
					return true
			return false
		"sells":
			return npc != null and npc.has_method(&"sells") and bool(npc.call(&"sells"))
		"hurt":
			var pl := Game.player
			if pl == null:
				return false
			return pl.health < pl.max_health * float(c.get("below", 0.999))
		"health":
			var p := Game.player
			if p == null:
				return false
			return (p.health / maxf(1.0, p.max_health)) <= float(c.get("below", 1.0))
		"chance":
			return randf() < float(c.get("p", 0.5))
		"not":
			return not check(c.get("of", {}) as Dictionary, npc)
		"all":
			return check_all(c.get("of", []) as Array, npc)
		"any":
			for sub: Variant in c.get("of", []) as Array:
				if check(sub as Dictionary, npc):
					return true
			return false
	return true


static func _check_quest(c: Dictionary) -> bool:
	var qid := String(c.get("quest", ""))
	match String(c.get("state", "completed")):
		"active":
			return Quests.is_active(qid)
		"completed":
			return Quests.is_completed(qid)
		"available":
			return Quests.can_start(qid)
		"offered":
			return Quests.is_offered(qid)
		"failed":
			return Quests.is_failed(qid)
		"ready":
			return Quests.is_ready_to_turn_in(qid)
		"untaken":
			return not Quests.is_active(qid) and not Quests.is_completed(qid)
	return false


# =========================================================================
#  Effects
# =========================================================================
static func _run_effects(list: Array) -> void:
	for e: Variant in list:
		apply_effect(e as Dictionary, _npc)


## Executes one effect Dictionary. Public so quest branches and NPC roles can
## reuse the same vocabulary.
static func apply_effect(e: Dictionary, npc: Node) -> void:
	var npc_id := StringName(npc.get("npc_id")) if npc != null else &""
	match String(e.get("type", "")):
		"give_item":
			NpcInventoryBridge.give(StringName(e.get("item", "")), int(e.get("count", 1)))
		"take_item":
			NpcInventoryBridge.take(StringName(e.get("item", "")), int(e.get("count", 1)))
		"give_pixels":
			NpcInventoryBridge.add_pixels(int(e.get("amount", 0)))
		"take_pixels":
			NpcInventoryBridge.spend_pixels(int(e.get("amount", 0)))
		"start_quest":
			Quests.start(String(e.get("quest", "")))
		"offer_quest":
			Quests.offer(String(e.get("quest", "")), npc)
		"complete_quest":
			Quests.complete(String(e.get("quest", "")))
		"fail_quest":
			Quests.fail(String(e.get("quest", "")), String(e.get("reason", "abandoned")))
		"report":
			Quests.report(StringName(e.get("kind", "talk")),
				e.get("key", String(npc_id)), int(e.get("amount", 1)))
		"reputation":
			var key := StringName(e.get("key", ""))
			if key == &"":
				key = npc_id
			NpcReputation.adjust(key, float(e.get("amount", 0.0)))
		"set_flag":
			Quests.set_flag(String(e.get("flag", "")), bool(e.get("value", true)))
		"open_shop":
			_open_panel("shop", {"npc": npc, "mode": "shop", "stock": _stock_of(npc)})
		"open_panel":
			_open_panel(String(e.get("panel", "")), e.get("ctx", {}) as Dictionary)
		"heal":
			NpcInventoryBridge.heal_player(float(e.get("amount", 9999.0)))
		"cure":
			NpcInventoryBridge.cure_player(e.get("ids", []) as Array)
		"learn_recipe":
			NpcInventoryBridge.learn_recipe(StringName(e.get("recipe", "")))
		"unlock_tech":
			NpcInventoryBridge.unlock_tech(StringName(e.get("tech", "")))
		"offer_work":
			if npc != null and npc.has_method(&"offer_pending_quest"):
				npc.call(&"offer_pending_quest")
		"accept_work":
			# Skips the offer window: take the NPC's pending quest immediately.
			if npc != null and npc.has_method(&"pending_quest_id"):
				var qid := String(npc.call(&"pending_quest_id"))
				if qid != "":
					Quests.start(qid)
		"turn_in":
			if npc != null:
				var who := StringName(npc.get("npc_id"))
				for qid: String in Quests.active_ids():
					var q := Quests.quest_of(qid)
					if q != null and q.turn_in == who and Quests.is_ready_to_turn_in(qid):
						Quests.complete(qid)
		"doctor_treat":
			NpcRoleDoctor.treat(npc)
		"doctor_cure":
			NpcRoleDoctor.cure(npc)
		"open_upgrade":
			_open_panel("upgrade", {"npc": npc, "mode": "upgrade",
				"material": NpcRoleBlacksmith.upgrade_material()})
		"hire_crew":
			if npc != null:
				var fee := NpcRoleCrew.hire_fee(StringName(npc.get("npc_id")))
				if NpcInventoryBridge.spend_pixels(fee):
					NpcCrew.hire(npc)
				else:
					Events.toast("You cannot cover the signing fee.", "warn")
		"dismiss_crew":
			if npc != null:
				NpcCrew.dismiss(npc_id)
		"rest":
			_rest(float(e.get("until", 0.27)))
		"teleport":
			_teleport(e.get("to", ""), npc)
		"notify":
			Events.toast(substitute(String(e.get("text", "")), npc), String(e.get("kind", "info")))
		"sound":
			var p := Game.player
			Events.play_sound.emit(StringName(e.get("id", "ui_click")),
				p.global_position if p != null else Vector3.ZERO)
		"shake":
			Events.screen_shake.emit(float(e.get("strength", 0.4)), float(e.get("duration", 0.4)))
		"end":
			end()


static func _open_panel(panel: String, ctx: Dictionary) -> void:
	if panel == "":
		return
	UI.open(panel, ctx)
	Events.ui_panel_opened.emit(panel)


static func _stock_of(npc: Node) -> Array:
	if npc != null and npc.has_method(&"shop_stock"):
		return npc.call(&"shop_stock") as Array
	return []


static func _rest(until_fraction: float) -> void:
	# Sleeping skips forward to dawn. Game.tick is public and the clock is
	# derived from it every frame, so nudging it is safe.
	var target := int(clampf(until_fraction, 0.0, 0.999) * float(Const.TICKS_PER_DAY))
	if target <= Game.tick:
		Game.day += 1
	Game.tick = target
	Game.day_fraction = float(target) / float(Const.TICKS_PER_DAY)
	NpcInventoryBridge.heal_player(9999.0)
	Events.toast("You wake rested.", "good")


static func _teleport(to: Variant, npc: Node) -> void:
	var p := Game.player
	if p == null:
		return
	if to is Array:
		var a := to as Array
		if a.size() >= 3:
			p.teleport(Vector3(a[0], a[1], a[2]))
		return
	match String(to):
		"home":
			if npc is Node3D:
				p.teleport((npc as Node3D).global_position + Vector3(1, 0, 0))
		"ship":
			Events.ship_boarded.emit()
		"surface":
			var b := Const.floor_v(p.global_position)
			var y := World.surface_y(b.x, b.z)
			if y > 0:
				p.teleport(Vector3(b.x + 0.5, y + 1.2, b.z + 0.5))


# =========================================================================
#  Adapter for the menus agent's `dialogue_panel.gd`
#
#  That panel walks a flat tree of its own shape and navigates by `goto`, so it
#  cannot see this file's conditions or run its effects. [method to_panel_tree]
#  bakes a snapshot for it: node gates are resolved, choices are filtered against
#  the live world, and any choice that *does* something carries an effect token
#  which [method Quests.offer] routes back into [method apply_effect_token].
#
#  It is a bridge, not the intended API. The richer path — pagination, greyed-out
#  choices with hints, live re-evaluation — is `begin/current_node/choices/choose`
#  at the top of this file.
# =========================================================================
const EFFECT_TOKEN := "@fx:"


## Snapshot of [param tree_id] in the panel's shape:
## `{name, start, nodes: {id: {text, choices: [{text, goto|action|quest}]}}}`.
static func to_panel_tree(tree_id: String, npc: Node) -> Dictionary:
	ensure_loaded()
	var t := _trees.get(tree_id, {}) as Dictionary
	if t.is_empty():
		return {}
	var nodes := t.get("nodes", {}) as Dictionary
	var out_nodes := {}
	for key: Variant in nodes:
		var id := String(key)
		var resolved_id := _resolve_gate(nodes, id, npc)
		if resolved_id == "":
			out_nodes[id] = {"text": "...", "choices": [{"text": "Goodbye.", "action": "end"}]}
			continue
		out_nodes[id] = _panel_node(tree_id, resolved_id, nodes, npc)
	return {
		"name": substitute(String(t.get("speaker", "{npc}")), npc),
		"start": String(t.get("start", "root")),
		"nodes": out_nodes,
	}


## Follows `when` / `else` until a node whose gate passes. Returns "" for a dead end.
static func _resolve_gate(nodes: Dictionary, id: String, npc: Node) -> String:
	var cur := id
	for _i in 16:
		if cur == "" or cur == END or not nodes.has(cur):
			return ""
		var nd := nodes[cur] as Dictionary
		if nd.has("when") and not check_all(nd["when"] as Array, npc):
			cur = String(nd.get("else", END))
			continue
		return cur
	return ""


static func _panel_node(tree_id: String, node_id: String, nodes: Dictionary, npc: Node) -> Dictionary:
	var nd := nodes[node_id] as Dictionary
	var pages := PackedStringArray()
	if nd.has("say"):
		var bank := nd["say"] as Array
		if not bank.is_empty():
			pages.append(substitute(String(bank[_rng.randi_range(0, bank.size() - 1)]), npc))
	else:
		var raw: Variant = nd.get("text", "")
		if raw is String:
			pages.append(substitute(String(raw), npc))
		elif raw is Array:
			for p: Variant in raw as Array:
				pages.append(substitute(String(p), npc))

	var out_choices: Array = []
	var raw_choices := nd.get("choices", []) as Array
	for i in raw_choices.size():
		var c := raw_choices[i] as Dictionary
		if bool(c.get("once", false)) and _taken.has("%s/%s/%d" % [tree_id, node_id, i]):
			continue
		if c.has("show_when") and not check_all(c["show_when"] as Array, npc):
			continue
		if c.has("when") and not check_all(c["when"] as Array, npc):
			continue
		var entry := {"text": substitute(String(c.get("text", "...")), npc)}
		var nxt := String(c.get("next", ""))
		if nxt == "":
			nxt = String(nd.get("next", END))
		var has_effects := not (c.get("do", []) as Array).is_empty()
		if not has_effects and nodes.has(nxt):
			# Entering the destination may itself do something.
			has_effects = not ((nodes[nxt] as Dictionary).get("do", []) as Array).is_empty()
		if has_effects:
			entry["action"] = "offer"
			entry["quest"] = "%s%s|%s|%d" % [EFFECT_TOKEN, tree_id, node_id, i]
		if nxt == END or nxt == "":
			if not entry.has("action"):
				entry["action"] = "end"
		else:
			entry["goto"] = nxt
		out_choices.append(entry)

	if out_choices.is_empty():
		var nxt := String(nd.get("next", END))
		if nxt != END and nxt != "":
			out_choices.append({"text": "Go on.", "goto": nxt})
		else:
			out_choices.append({"text": "Goodbye.", "action": "end"})

	return {"text": "\n\n".join(pages), "choices": out_choices}


static func is_effect_token(s: String) -> bool:
	return s.begins_with(EFFECT_TOKEN)


## Runs the effects a baked choice stood for. Called by [method Quests.offer]
## when it is handed an effect token instead of a quest id.
static func apply_effect_token(token: String, npc: Node) -> void:
	ensure_loaded()
	var parts := token.substr(EFFECT_TOKEN.length()).split("|")
	if parts.size() < 3:
		return
	var t := _trees.get(parts[0], {}) as Dictionary
	var nodes := t.get("nodes", {}) as Dictionary
	if not nodes.has(parts[1]):
		return
	var nd := nodes[parts[1]] as Dictionary
	var choices := nd.get("choices", []) as Array
	var i := int(parts[2])
	if i < 0 or i >= choices.size():
		return
	var c := choices[i] as Dictionary
	var who := npc if npc != null else _npc
	if bool(c.get("once", false)):
		_taken["%s/%s/%d" % [parts[0], parts[1], i]] = true
	for e: Variant in c.get("do", []) as Array:
		apply_effect(e as Dictionary, who)
	# The destination node's own `do` fires on arrival, as it would in-runtime.
	var nxt := String(c.get("next", nd.get("next", END)))
	if nxt != END and nodes.has(nxt):
		for e: Variant in (nodes[nxt] as Dictionary).get("do", []) as Array:
			apply_effect(e as Dictionary, who)


# =========================================================================
#  Persistence  (owned by Quests.save_state)
# =========================================================================
static func save_state() -> Dictionary:
	var t := {}
	for k: Variant in _taken:
		t[String(k)] = true
	return {"taken": t}


static func load_state(d: Dictionary) -> void:
	_taken.clear()
	for k: Variant in d.get("taken", {}):
		_taken[String(k)] = true
	end()
