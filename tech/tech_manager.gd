## Autoloaded as `Tech`. Owns the player's three tech slots, the unlock tree,
## the energy pool, the Matter Manipulator and the world-interaction router,
## and it bootstraps the object/wiring subsystem (`Tech.objects`).
##
## ---------------------------------------------------------------------------
## WHAT OTHER AGENTS NEED FROM THIS FILE
## ---------------------------------------------------------------------------
##
## [b]Player agent[/b] — one call per physics frame is all that is required:
## [codeblock]
## func _physics_process(delta: float) -> void:
##     ...
##     if Tech.has_method(&"drive"):
##         Tech.drive(delta)                # tools + mouse interaction + techs
## [/codeblock]
## and, for movement, multiply your own numbers by
## `Tech.modifier("move_speed")` / `Tech.modifier("jump_speed")`.
##
## [b]HUD agent[/b] — `Tech.hud_state()` returns everything drawable.
##
## [b]Render / camera agents[/b] — the perspective techs publish their effect
## as plain fields on this node (all default to "off"):
##   `depth_sight_layers:int`   layers behind the play layer to render and
##                              interact with as if they were the play layer
##   `fold_layers:int`          layers collapsed into the play layer
##   `plane_anchor_active:bool` + `anchor_axis:int` (0 = X, 2 = Z, -1 = none)
##   `phase_ghost:bool`         the player is mid-phase; draw them translucent
##   `nightvision_strength:f`   0..1 light amplification
##   `morph_active:bool`        the player is a ball; swap the sprite
## Read them defensively (`Tech.get("depth_sight_layers")`) and never write them.
##
## [b]Survival agent[/b] — `Tech.oxygen_immune` is true while Water Breathing
## is carrying the player. `Tech.modifier("fall_damage")` is honoured too.
##
## ---------------------------------------------------------------------------
## THE VIEW RESTORE GUARANTEE
## ---------------------------------------------------------------------------
## Techs mutate `View.flips_enabled`, `View.flip_duration`, `View.shift_duration`
## and the override fields above. Every such tech calls `claim_view()` first and
## `release_view()` in `on_deactivate`; the outermost claim snapshots those
## fields and the unwind puts the snapshot back, whatever order the techs
## release in. `_watchdog()` runs every physics frame and drops claims held by
## techs that are no longer live, so a tech that dies mid-effect still unwinds.
## `Tech` never stamps a default over `View.flips_enabled` on its own — that
## field also belongs to cutscenes, menus and the star map — it only ever
## restores a value it saw itself. Nothing a tech does can leave the world
## unflippable.
extends Node

const SLOTS: Array[StringName] = [&"head", &"body", &"legs"]

## The `View` fields a tech is allowed to mutate, with the engine defaults. The
## keys are what `snapshot_view()` records; the values are only used as a
## sanity reference. Keep in sync with `core/perspective.gd`.
const VIEW_DEFAULTS := {
	"flips_enabled": true,
	"flip_duration": 0.45,
	"shift_duration": 0.22,
}

# ------------------------------------------------------------------- contents
## slot -> tech id. Kept as a plain String->String map for save compatibility.
var equipped: Dictionary = {}
## tech id (String) -> true
var unlocked: Dictionary = {}
## tech id (StringName) -> TchBase instance. Only equipped techs are live.
var instances: Dictionary = {}

## Which slot the `tech_action` key fires. Cycled with `cycle_primary_slot()`.
var primary_slot: StringName = &"legs"

# --------------------------------------------------------------------- energy
## Fallback pool used only when the player actor has no `energy` property of
## its own. The moment the player agent adds one, this becomes a mirror.
var _energy: float = 100.0
var _max_energy: float = 100.0
var energy_regen: float = 18.0
var _regen_delay: float = 0.0

# ------------------------------------------------- perspective override state
var depth_sight_layers: int = 0
var fold_layers: int = 0
var plane_anchor_active: bool = false
var anchor_axis: int = -1
var phase_ghost: bool = false
var nightvision_strength: float = 0.0
var morph_active: bool = false
var oxygen_immune: bool = false

# ----------------------------------------------------------------- subsystems
## The Matter Manipulator. Created on the first frame; see `tech/tool_beam.gd`.
var beam: TchToolBeam = null
## The mouse -> voxel -> action router. See `tech/interaction.gd`.
var interaction: TchInteraction = null
## The placed-object / wiring subsystem. See `objects/object_manager.gd`.
var objects: Node = null

## tech id (String) -> true. Non-empty means some tech holds guarded state.
var _view_claims: Dictionary = {}
## `View` fields as they were before the outermost claim. Restored on unwind.
var _base_snapshot: Dictionary = {}
var _hold_down: bool = false
var _booted: bool = false
var _driven_frame: int = -1


func _ready() -> void:
	process_priority = -20
	interaction = TchInteraction.new()
	Events.player_died.connect(_on_player_died)
	Events.world_unloaded.connect(_on_world_unloaded)
	Events.view_flip_finished.connect(_on_flip_finished)
	Events.layer_changed.connect(_on_layer_changed)
	call_deferred(&"_boot")


func _boot() -> void:
	if _booted:
		return
	_booted = true
	beam = TchToolBeam.new()
	beam.name = "MatterManipulator"
	add_child(beam)
	objects = ObjManager.new()
	objects.name = "ObjectManager"
	add_child(objects)
	# Double Jump is the starting tech, exactly as in Starbound.
	unlock(&"double_jump")
	equip("legs", &"double_jump")


# ===========================================================================
#  Unlock tree
# ===========================================================================
## Marks a tech as owned. Silently ignores unknown ids and re-unlocks.
func unlock(tech_id: StringName) -> void:
	if tech_id == &"" or not TchCatalog.has(tech_id):
		return
	if unlocked.has(String(tech_id)):
		return
	unlocked[String(tech_id)] = true
	var def := TchCatalog.get_def(tech_id)
	Events.upgrade_purchased.emit("tech:" + String(tech_id))
	Events.toast("Tech acquired: %s" % String(def.get("name", tech_id)), "tech")


func is_unlocked(tech_id: StringName) -> bool:
	return unlocked.has(String(tech_id))


## True when every prerequisite in the tech's `requires` list is already owned.
func requirements_met(tech_id: StringName) -> bool:
	var def := TchCatalog.get_def(tech_id)
	if def.is_empty():
		return false
	for r: Variant in def.get("requires", []):
		if not is_unlocked(StringName(r)):
			return false
	return true


## Ids the player owns and whose prerequisites are satisfied — i.e. everything
## that may legally be equipped right now.
func available(slot: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	for tid: StringName in TchCatalog.ids():
		if not is_unlocked(tid) or not requirements_met(tid):
			continue
		if slot != &"" and TchCatalog.get_def(tid)["slot"] != slot:
			continue
		out.append(tid)
	return out


## Consumes a tech card item id (`tech_double_jump`) and unlocks its tech.
## Returns false when the item is not a card or the tree is not satisfied yet.
func unlock_from_item(item_id: StringName) -> bool:
	var tid := TchCatalog.tech_of_card(item_id)
	if tid == &"":
		return false
	if is_unlocked(tid):
		Events.toast("You already know that tech.", "warn")
		return false
	if not requirements_met(tid):
		Events.toast("Missing prerequisite tech.", "warn")
		return false
	unlock(tid)
	return true


# ===========================================================================
#  Slots
# ===========================================================================
## Puts `tech_id` into `slot`. Passing `&""` clears the slot. The tech must be
## unlocked, its prerequisites met, and its declared slot must match.
func equip(slot: String, tech_id: StringName) -> void:
	var s := StringName(slot)
	if not SLOTS.has(s):
		push_warning("[Tech] unknown slot '%s'" % slot)
		return
	var old: StringName = StringName(equipped.get(slot, ""))
	if old == tech_id:
		return
	if old != &"":
		_teardown(old)
	equipped.erase(slot)

	if tech_id == &"":
		Events.tech_equipped.emit(slot, "")
		return
	var def := TchCatalog.get_def(tech_id)
	if def.is_empty():
		push_warning("[Tech] unknown tech '%s'" % tech_id)
		return
	if StringName(def["slot"]) != s:
		Events.toast("%s is a %s tech." % [def["name"], def["slot"]], "warn")
		return
	if not is_unlocked(tech_id) or not requirements_met(tech_id):
		Events.toast("Tech not unlocked.", "warn")
		return

	var inst := _instantiate(tech_id)
	if inst == null:
		return
	instances[tech_id] = inst
	equipped[slot] = String(tech_id)
	inst.equipped = true
	inst.on_equip()
	Events.tech_equipped.emit(slot, String(tech_id))


func unequip(slot: String) -> void:
	equip(slot, &"")


func equipped_id(slot: String) -> StringName:
	return StringName(equipped.get(slot, ""))


func tech_in(slot: String) -> TchBase:
	var tid := equipped_id(slot)
	return instances.get(tid) if tid != &"" else null


func _instantiate(tech_id: StringName) -> TchBase:
	var path := TchCatalog.script_path(tech_id)
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[Tech] missing script for '%s' (%s)" % [tech_id, path])
		return null
	var scr: Script = load(path)
	if scr == null:
		return null
	var inst := scr.new() as TchBase
	if inst == null:
		push_warning("[Tech] '%s' is not a TchBase" % tech_id)
		return null
	inst.manager = self
	inst.configure(TchCatalog.get_def(tech_id))
	return inst


func _teardown(tech_id: StringName) -> void:
	var inst: TchBase = instances.get(tech_id)
	if inst == null:
		return
	if inst.active:
		_deactivate_instance(inst)
	inst.equipped = false
	inst.on_unequip()
	inst.release_view()
	instances.erase(tech_id)


# ===========================================================================
#  Activation
# ===========================================================================
## Fires the tech in `slot`. Bound to the `tech_action` input for
## `primary_slot`; UI and hotkeys may call it for any slot.
func activate(slot: String) -> void:
	var inst := tech_in(slot)
	if inst == null or inst.is_passive():
		return
	if inst.active:
		# A second press cancels a toggle; hold techs are released by input.
		if inst.mode == "toggle":
			_deactivate_instance(inst)
		return
	if not inst.is_ready():
		Events.play_sound.emit(&"denied", _player_pos())
		return
	if energy() < inst.energy_cost:
		Events.toast("Not enough energy.", "warn")
		Events.play_sound.emit(&"denied", _player_pos())
		return
	if not inst.on_activate():
		return

	spend(inst.energy_cost)
	inst.cooldown_left = inst.cooldown
	Events.tech_activated.emit(String(inst.id))

	if inst.duration <= 0.0 and inst.mode == "instant":
		# Symmetric restore contract: an instant tech's deactivate runs now.
		inst.on_deactivate()
		inst.release_view()
		return
	inst.active = true
	inst.time_left = inst.duration


## Stops the tech in `slot` if it is running.
func deactivate(slot: String) -> void:
	var inst := tech_in(slot)
	if inst != null and inst.active:
		_deactivate_instance(inst)


func deactivate_all() -> void:
	for tid: StringName in instances.keys():
		var inst: TchBase = instances[tid]
		if inst.active:
			_deactivate_instance(inst)


func _deactivate_instance(inst: TchBase) -> void:
	inst.active = false
	inst.time_left = 0.0
	inst.on_deactivate()
	inst.release_view()


func cycle_primary_slot() -> void:
	var i := SLOTS.find(primary_slot)
	primary_slot = SLOTS[(i + 1) % SLOTS.size()]
	Events.toast("Tech key: %s slot" % String(primary_slot), "info")


# ===========================================================================
#  Per-frame
# ===========================================================================
func _physics_process(delta: float) -> void:
	if Game.paused:
		return
	_tick_energy(delta)
	_tick_techs(delta)
	_watchdog()
	# Fallback: if the player agent did not call `drive()` this frame, do it
	# here so tools still work. Calling `drive()` from the player is preferred —
	# it runs after the player has moved, so the beam muzzle is not a frame late.
	if _driven_frame != Engine.get_physics_frames():
		drive(delta)


## The player agent should call this once per physics frame, *after* its own
## movement integration. Drives the tool beam and the interaction router.
func drive(delta: float) -> void:
	_driven_frame = Engine.get_physics_frames()
	if interaction != null:
		interaction.poll(delta)
	if beam != null:
		beam.update(delta)


func _tick_techs(delta: float) -> void:
	for tid: StringName in instances.keys():
		var inst: TchBase = instances[tid]
		if inst == null:
			continue
		if inst.cooldown_left > 0.0:
			inst.cooldown_left = maxf(0.0, inst.cooldown_left - delta)
		if inst.active:
			if inst.drain > 0.0 and not spend(inst.drain * delta):
				_deactivate_instance(inst)
				Events.toast("%s ran dry." % inst.display_name, "warn")
				continue
			if inst.duration > 0.0:
				inst.time_left -= delta
				if inst.time_left <= 0.0:
					_deactivate_instance(inst)
					continue
		inst.on_update(delta)


## Runs every physics frame. Two jobs, and it is deliberately conservative
## about which one it does when.
##
##  * A claim held by a tech that is no longer live (freed, unequipped, crashed
##    mid-update) is dropped, which restores the snapshot taken before the
##    first tech touched anything.
##  * When nothing holds a claim, the `Tech` override fields are forced off.
##
## It does **not** stamp defaults over `View.flips_enabled` when no tech is
## involved: that field also belongs to cutscenes, menus and the star map, and
## overwriting it every frame would fight them. `View` state is only ever
## restored from a snapshot this module itself took.
func _watchdog() -> void:
	if _view_claims.is_empty():
		if _overrides_active():
			_clear_overrides()
		return
	for tid: Variant in _view_claims.keys():
		var inst: TchBase = instances.get(StringName(tid))
		if inst == null or not inst.holds_view():
			_release_claim(StringName(tid))


## Emergency restore. Releases every outstanding claim — putting `View` back to
## the state it was in before the first tech ran — and clears every override.
## Called on death, on world unload and after loading a save.
func force_reset() -> void:
	for tid: Variant in _view_claims.keys():
		_view_claims.erase(tid)
	_restore_base()


func _restore_base() -> void:
	for k: String in _base_snapshot:
		View.set(k, _base_snapshot[k])
	_base_snapshot = {}
	_clear_overrides()


func _overrides_active() -> bool:
	return depth_sight_layers != 0 or fold_layers != 0 or plane_anchor_active \
		or anchor_axis != -1 or phase_ghost or morph_active or oxygen_immune \
		or nightvision_strength != 0.0


## The perspective override fields are always "off" when unclaimed, so they
## need no snapshot — only a reset.
func _clear_overrides() -> void:
	depth_sight_layers = 0
	fold_layers = 0
	plane_anchor_active = false
	anchor_axis = -1
	phase_ghost = false
	morph_active = false
	oxygen_immune = false
	nightvision_strength = 0.0


# ===========================================================================
#  Guarded View state
# ===========================================================================
## Snapshot of every guarded field, taken before a tech mutates them.
func snapshot_view() -> Dictionary:
	var d: Dictionary = {}
	for k: String in VIEW_DEFAULTS:
		d[k] = View.get(k)
	return d


## Called by `TchBase.claim_view`. The *first* claim takes the snapshot;
## nested claims share it, so unwinding always lands on the state that existed
## before the outermost tech ran, whatever order the techs release in.
func claim_view(t: TchBase) -> void:
	if _view_claims.is_empty():
		_base_snapshot = snapshot_view()
	_view_claims[String(t.id)] = true


## Called by `TchBase.release_view`.
func release_view(t: TchBase) -> void:
	_release_claim(t.id)


func _release_claim(tech_id: StringName) -> void:
	if not _view_claims.has(String(tech_id)):
		return
	_view_claims.erase(String(tech_id))
	if _view_claims.is_empty():
		_restore_base()


# ===========================================================================
#  Energy
# ===========================================================================
## The live energy value. Mirrors the player actor's own `energy` property
## when it exists so the survival/HUD agents keep a single source of truth.
func energy() -> float:
	var p := Game.player
	if p != null and "energy" in p:
		return float(p.get("energy"))
	return _energy


func max_energy() -> float:
	var p := Game.player
	if p != null and "max_energy" in p:
		return maxf(1.0, float(p.get("max_energy")))
	return _max_energy


func set_energy(v: float) -> void:
	var m := max_energy()
	var clamped := clampf(v, 0.0, m)
	var p := Game.player
	if p != null and "energy" in p:
		p.set("energy", clamped)
	else:
		_energy = clamped
	Events.stat_changed.emit("energy", clamped, m)


## Spends energy if it is there. Returns false and spends nothing otherwise.
func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	var e := energy()
	if e < amount:
		return false
	set_energy(e - amount)
	_regen_delay = 0.85
	return true


func add_energy(amount: float) -> void:
	set_energy(energy() + amount)


func energy_fraction() -> float:
	return clampf(energy() / max_energy(), 0.0, 1.0)


func _tick_energy(delta: float) -> void:
	if _regen_delay > 0.0:
		_regen_delay = maxf(0.0, _regen_delay - delta)
		return
	var e := energy()
	var m := max_energy()
	if e >= m:
		return
	set_energy(e + energy_regen * modifier("energy_regen") * delta)


# ===========================================================================
#  Stat modifiers
# ===========================================================================
## Product of every equipped tech's contribution to `stat`. Always returns a
## usable multiplier, so callers can write `speed * Tech.modifier("move_speed")`
## unconditionally.
func modifier(stat: String) -> float:
	var m := 1.0
	for tid: StringName in instances:
		var inst: TchBase = instances[tid]
		if inst != null:
			m *= inst.modifier(stat)
	return m


# ===========================================================================
#  Perspective queries — used by interaction, combat, entities, render
# ===========================================================================
## How many layers behind the play layer the player may currently mine, place
## into and interact with. 0 normally; 3 under Depth Sight; 1 under Fold.
func interact_layer_tolerance() -> int:
	return maxi(depth_sight_layers, fold_layers)


## How many layers behind the play layer count as "in melee reach". The combat
## agent should widen its own same-layer test by this much.
func combat_layer_tolerance() -> int:
	return maxi(fold_layers, depth_sight_layers)


## True when `pos` is close enough to the play layer for the player to act on
## it right now. Replaces a bare `View.is_play_layer()` in tool code.
func voxel_in_reach(pos: Vector3i) -> bool:
	if View.is_play_layer(pos):
		return true
	var off := View.layer_offset(pos)
	return off > 0 and off <= interact_layer_tolerance()


## Same test for an entity node.
func node_in_reach(n: Node3D) -> bool:
	if n == null:
		return false
	var d := floori(View.depth_of(n.global_position))
	var off := (d - View.layer) * View.depth_sign()
	return off == 0 or (off > 0 and off <= combat_layer_tolerance())


# ===========================================================================
#  Input
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if Game.paused or UI.captures_input():
		return
	if event.is_action_pressed(&"tech_action"):
		_hold_down = true
		activate(String(primary_slot))
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"tech_action"):
		_hold_down = false
		var inst := tech_in(String(primary_slot))
		if inst != null and inst.active and inst.mode == "hold":
			_deactivate_instance(inst)


# ===========================================================================
#  Event relays
# ===========================================================================
func _on_player_died(_cause: String) -> void:
	deactivate_all()
	force_reset()


func _on_world_unloaded() -> void:
	deactivate_all()
	force_reset()


func _on_flip_finished(v: int) -> void:
	for tid: StringName in instances:
		(instances[tid] as TchBase).on_event(&"flip", {"view": v})


func _on_layer_changed(l: int, v: int) -> void:
	for tid: StringName in instances:
		(instances[tid] as TchBase).on_event(&"layer", {"layer": l, "view": v})


func _player_pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO


# ===========================================================================
#  Presentation
# ===========================================================================
## Everything the HUD needs, in one call.
func hud_state() -> Dictionary:
	var slots: Dictionary = {}
	for s: StringName in SLOTS:
		var inst := tech_in(String(s))
		slots[String(s)] = inst.hud_state() if inst != null else {}
	return {
		"slots": slots,
		"primary": String(primary_slot),
		"energy": energy(), "max_energy": max_energy(),
		"beam": beam.hud_state() if beam != null else {},
		"overrides": {
			"depth_sight": depth_sight_layers, "fold": fold_layers,
			"anchor": plane_anchor_active, "phase": phase_ghost,
			"nightvision": nightvision_strength, "morph": morph_active,
		},
	}


# ===========================================================================
#  Persistence
# ===========================================================================
func save_state() -> Dictionary:
	var per_tech: Dictionary = {}
	for tid: StringName in instances:
		var d: Dictionary = (instances[tid] as TchBase).save_state()
		if not d.is_empty():
			per_tech[String(tid)] = d
	return {
		"unlocked": unlocked.keys(),
		"equipped": equipped.duplicate(),
		"primary": String(primary_slot),
		"energy": energy(),
		"tech_state": per_tech,
		"beam": beam.save_state() if beam != null else {},
		"objects": objects.save_state() if objects != null and objects.has_method(&"save_state") else {},
	}


func load_state(d: Dictionary) -> void:
	deactivate_all()
	force_reset()
	for slot: String in equipped.keys():
		_teardown(StringName(equipped[slot]))
	equipped.clear()
	instances.clear()
	unlocked.clear()

	for u: Variant in d.get("unlocked", []):
		var tid := StringName(u)
		if TchCatalog.has(tid):
			unlocked[String(tid)] = true
	var eq: Dictionary = d.get("equipped", {})
	for slot: Variant in eq:
		equip(String(slot), StringName(eq[slot]))
	primary_slot = StringName(d.get("primary", "legs"))
	if not SLOTS.has(primary_slot):
		primary_slot = &"legs"
	set_energy(float(d.get("energy", max_energy())))

	var per_tech: Dictionary = d.get("tech_state", {})
	for tid: Variant in per_tech:
		var inst: TchBase = instances.get(StringName(tid))
		if inst != null:
			inst.load_state(per_tech[tid])
	if beam != null:
		beam.load_state(d.get("beam", {}))
	if objects != null and objects.has_method(&"load_state"):
		objects.call(&"load_state", d.get("objects", {}))
