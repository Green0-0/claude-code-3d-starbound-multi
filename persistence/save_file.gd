## The top-level save document: a metadata header plus one optional section per
## module.
##
## ```
## {
##   "version": 3,
##   "meta":     { name, slot, created, saved, playtime, planet, planet_name,
##                 day, time, level, seed, difficulty, hardcore, thumb },
##   "sections": {
##       "game":      Game.save_state(),
##       "view":      View.save_state(),
##       "player":    Game.player.save_state(),
##       "inventory": Game.player.inventory.to_dict(),
##       "universe":  Universe.save_state(),
##       "quests":    Quests.save_state(),
##       "status":    Status.save_state(),
##       "tech":      Tech.save_state(),
##       "entities":  SavEntityPersistence.to_dict(),
##       "objects":   placed-object registry,
##   }
## }
## ```
##
## **Every section is optional.** Nineteen of these modules are being written in
## parallel and most are still stubs returning `{}`; collecting and applying a
## section is always guarded, and a section that throws away its contents cannot
## stop the rest of the save from loading.
##
## The thumbnail is a tiny procedural colour strip rather than a screenshot —
## the project has no binary assets, and a strip derived from the planet's own
## palette identifies a save at a glance for a few dozen bytes.
class_name SavSaveFile
extends RefCounted

## Sections and the module that owns each. Kept as data so `list_sections()`
## and the self-test stay honest when a module lands.
const SECTIONS := {
	"game":      "core/game.gd (Game)",
	"view":      "core/perspective.gd (View)",
	"player":    "player/ (Game.player)",
	"inventory": "inventory/ (Game.player.inventory)",
	"universe":  "space/universe.gd (Universe)",
	"quests":    "quests/quest_manager.gd (Quests)",
	"status":    "survival/status_manager.gd (Status)",
	"tech":      "tech/tech_manager.gd (Tech)",
	"entities":  "persistence/entity_persistence.gd",
	"objects":   "objects/ (via Chunk.tile_data)",
}

## Number of colour bands in the procedural thumbnail.
const THUMB_BANDS := 24


# ==================================================================== collect
## Build the save document from the live game. Main thread only — it touches
## the scene tree. The result is a plain Dictionary, so the encode + write can
## then happen on a worker.
static func collect(slot: int, save_name: String, playtime: float, created_unix: int = 0) -> Dictionary:
	var sections := {}
	_put(sections, "game", _call_state(Game))
	_put(sections, "view", _call_state(View))
	_put(sections, "universe", _call_state(Universe))
	_put(sections, "quests", _call_state(Quests))
	_put(sections, "status", _call_state(Status))
	_put(sections, "tech", _call_state(Tech))

	var player: Node = Game.player
	if player != null and is_instance_valid(player):
		_put(sections, "player", _call_state(player))
		var inv: Variant = player.get(&"inventory")
		if inv != null and inv is Object and (inv as Object).has_method(&"to_dict"):
			var idict: Variant = (inv as Object).call(&"to_dict")
			if idict is Dictionary:
				_put(sections, "inventory", idict)

	if SaveManager.entities != null:
		SaveManager.entities.capture_all(World.planet_id)
		_put(sections, "entities", SaveManager.entities.to_dict())

	var objects := SavEntityPersistence.scan_loaded_objects()
	if not objects.is_empty():
		sections["objects"] = {"planet": World.planet_id, "tiles": objects}

	return {
		"version": SavCodec.SAVE_VERSION,
		"meta": build_meta(slot, save_name, playtime, created_unix),
		"sections": sections,
	}


## The small header written verbatim to `meta.json` for fast save-list rendering.
static func build_meta(slot: int, save_name: String, playtime: float, created_unix: int = 0) -> Dictionary:
	var planet_id := World.planet_id
	var pmeta: Dictionary = {}
	if Universe != null and Universe.has_method(&"planet_meta") and planet_id != "":
		var m: Variant = Universe.planet_meta(planet_id)
		if m is Dictionary:
			pmeta = m
	var now := int(Time.get_unix_time_from_system())
	return {
		"name": save_name if save_name != "" else _default_name(pmeta),
		"slot": slot,
		"version": SavCodec.SAVE_VERSION,
		"created": created_unix if created_unix > 0 else now,
		"saved": now,
		"saved_text": Time.get_datetime_string_from_system(false, true),
		"playtime": playtime,
		"planet": planet_id,
		"planet_name": String(pmeta.get("name", planet_id)),
		"planet_type": String(pmeta.get("type", "unknown")),
		"day": Game.day,
		"time": Game.time_string(),
		"level": _player_level(),
		"seed": Game.run_seed,
		"difficulty": Game.difficulty,
		"hardcore": Game.difficulty >= 2,
		"stats": (Game.stats as Dictionary).duplicate(),
		"thumb": Marshalls.raw_to_base64(thumbnail_bytes(pmeta)),
	}


# ====================================================================== apply
## Restore a decoded save document. Order matters: the universe has to exist
## before we can travel, and travel resets the player, so the player is restored
## last. Every step is guarded; a stub module simply does nothing.
static func apply(doc: Dictionary) -> bool:
	var sections: Dictionary = doc.get("sections", {})
	var meta: Dictionary = doc.get("meta", {})

	_apply_state(Universe, sections.get("universe", null))
	_apply_state(Game, sections.get("game", null))

	# Travel rebuilds the world for the saved planet. `Game.travel_to_planet`
	# flushes the (empty) previous world and generates the new one.
	var planet := String(meta.get("planet", ""))
	if planet == "":
		var gs: Dictionary = sections.get("game", {})
		planet = String(gs.get("planet", ""))
	if planet == "":
		planet = Universe.starting_planet_id()
	Game.travel_to_planet(planet)

	_apply_state(View, sections.get("view", null))

	var player: Node = Game.player
	if player != null and is_instance_valid(player):
		var ps: Variant = sections.get("player", null)
		if ps is Dictionary and player.has_method(&"load_state"):
			player.call(&"load_state", ps)
		var inv: Variant = player.get(&"inventory")
		var idict: Variant = sections.get("inventory", null)
		if inv != null and inv is Object and idict is Dictionary and (inv as Object).has_method(&"from_dict"):
			(inv as Object).call(&"from_dict", idict)
			Events.inventory_changed.emit()

	_apply_state(Quests, sections.get("quests", null))
	_apply_state(Status, sections.get("status", null))
	_apply_state(Tech, sections.get("tech", null))

	var ent: Variant = sections.get("entities", null)
	if ent is Dictionary and SaveManager.entities != null:
		SaveManager.entities.from_dict(ent)

	# Placed objects live in the chunks themselves; the registry in the save is
	# a redundant safety net for tiles whose chunk was never written (a chunk
	# can be discarded as "unmodified" while an object sits on top of it if a
	# module forgot to mark it — restoring here makes that failure invisible).
	var objs: Variant = sections.get("objects", null)
	if objs is Dictionary:
		_restore_tiles(objs)

	return true


static func _restore_tiles(objs: Dictionary) -> void:
	if String(objs.get("planet", "")) != World.planet_id:
		return
	var tiles: Dictionary = objs.get("tiles", {})
	for k: Variant in tiles:
		var parts := str(k).split(",")
		if parts.size() != 3:
			continue
		var p := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var data: Variant = tiles[k]
		if data is Dictionary and not (data as Dictionary).is_empty():
			SavEntityPersistence.set_object_data(p, data)


# ================================================================== thumbnail
## A deterministic colour strip standing in for a screenshot. Derived from the
## planet seed, type and time of day, so two saves on different worlds look
## obviously different in the load menu.
static func thumbnail_bytes(pmeta: Dictionary) -> PackedByteArray:
	var cols := thumbnail_colors(pmeta)
	var out := PackedByteArray()
	out.resize(cols.size() * 3)
	for i in cols.size():
		out[i * 3 + 0] = int(clampf(cols[i].r, 0.0, 1.0) * 255.0)
		out[i * 3 + 1] = int(clampf(cols[i].g, 0.0, 1.0) * 255.0)
		out[i * 3 + 2] = int(clampf(cols[i].b, 0.0, 1.0) * 255.0)
	return out


## The strip as colours, for the menus agent to draw directly.
static func thumbnail_colors(pmeta: Dictionary) -> PackedColorArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pmeta.get("seed", Game.run_seed)) ^ hash(String(pmeta.get("id", World.planet_id)))
	var base := _palette_for(String(pmeta.get("type", "forest")), rng)
	var sky: Color = base[0]
	var ground: Color = base[1]
	var accent: Color = base[2]
	var night := clampf(1.0 - Game.daylight, 0.0, 1.0)
	sky = sky.lerp(Color(0.03, 0.04, 0.12), night * 0.85)
	ground = ground.lerp(Color(0.05, 0.05, 0.09), night * 0.6)

	var out := PackedColorArray()
	out.resize(THUMB_BANDS)
	# A horizon roughly one third down, with a jagged procedural skyline.
	var horizon := int(THUMB_BANDS * 0.38)
	for i in THUMB_BANDS:
		var t := float(i) / float(THUMB_BANDS - 1)
		var c: Color
		if i < horizon:
			c = sky.lerp(sky.lightened(0.25), t * 2.0)
		else:
			var g := float(i - horizon) / float(maxi(1, THUMB_BANDS - horizon))
			c = ground.lerp(ground.darkened(0.55), g)
			if rng.randf() < 0.18:
				c = c.lerp(accent, 0.55)
		out[i] = c
	return out


## Decode a stored thumbnail back into colours (for the load menu).
static func thumbnail_from_base64(b64: String) -> PackedColorArray:
	var raw := Marshalls.base64_to_raw(b64)
	var out := PackedColorArray()
	var n := raw.size() / 3
	out.resize(n)
	for i in n:
		out[i] = Color8(raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2])
	return out


static func _palette_for(kind: String, rng: RandomNumberGenerator) -> Array:
	var jitter := func(c: Color) -> Color:
		return Color(
			clampf(c.r + rng.randf_range(-0.05, 0.05), 0.0, 1.0),
			clampf(c.g + rng.randf_range(-0.05, 0.05), 0.0, 1.0),
			clampf(c.b + rng.randf_range(-0.05, 0.05), 0.0, 1.0))
	match kind:
		"desert":
			return [jitter.call(Color(0.72, 0.78, 0.9)), jitter.call(Color(0.85, 0.72, 0.45)), Color(0.6, 0.45, 0.3)]
		"tundra", "ice", "snow":
			return [jitter.call(Color(0.68, 0.78, 0.88)), jitter.call(Color(0.86, 0.9, 0.94)), Color(0.5, 0.68, 0.8)]
		"volcanic", "magma":
			return [jitter.call(Color(0.24, 0.12, 0.12)), jitter.call(Color(0.28, 0.18, 0.16)), Color(0.9, 0.35, 0.1)]
		"ocean":
			return [jitter.call(Color(0.55, 0.75, 0.9)), jitter.call(Color(0.12, 0.32, 0.5)), Color(0.3, 0.65, 0.7)]
		"toxic", "swamp":
			return [jitter.call(Color(0.5, 0.6, 0.42)), jitter.call(Color(0.28, 0.34, 0.2)), Color(0.6, 0.85, 0.3)]
		"barren", "moon", "rock":
			return [jitter.call(Color(0.1, 0.11, 0.16)), jitter.call(Color(0.42, 0.42, 0.45)), Color(0.6, 0.6, 0.65)]
		"alien", "cosmic":
			return [jitter.call(Color(0.22, 0.12, 0.32)), jitter.call(Color(0.36, 0.22, 0.45)), Color(0.8, 0.4, 0.95)]
		_:
			return [jitter.call(Color(0.45, 0.68, 0.92)), jitter.call(Color(0.28, 0.55, 0.25)), Color(0.55, 0.4, 0.24)]


# ==================================================================== helpers
static func list_sections() -> Dictionary:
	return SECTIONS.duplicate()


static func _put(sections: Dictionary, key: String, value: Variant) -> void:
	if value is Dictionary and not (value as Dictionary).is_empty():
		sections[key] = value


static func _call_state(obj: Object) -> Dictionary:
	if obj == null or not is_instance_valid(obj):
		return {}
	if not obj.has_method(&"save_state"):
		return {}
	var v: Variant = obj.call(&"save_state")
	if v is Dictionary:
		return v
	return {}


static func _apply_state(obj: Object, data: Variant) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		return
	if not obj.has_method(&"load_state"):
		return
	obj.call(&"load_state", data)


static func _player_level() -> int:
	var p: Node = Game.player
	if p == null or not is_instance_valid(p):
		return 1
	var lv: Variant = p.get(&"level")
	if lv != null and (lv is int or lv is float):
		return int(lv)
	return 1


static func _default_name(pmeta: Dictionary) -> String:
	var pn := String(pmeta.get("name", ""))
	if pn == "":
		pn = "Unknown Space"
	return "%s — day %d" % [pn, Game.day]
