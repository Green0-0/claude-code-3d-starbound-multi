## Base class for every tech. One subclass per `res://tech/techs/*.gd`.
##
## A tech is a plain RefCounted, not a Node: `Tech` owns the instances, feeds
## them `on_update` from its own `_physics_process`, and guarantees that
## `on_deactivate` runs exactly once for every successful `on_activate` — on
## expiry, on cancel, on unequip, on death, on world unload and on load.
##
## [b]The restore contract.[/b] Anything a tech mutates outside itself
## (`View.flips_enabled`, `View.flip_duration`, `View.shift_duration`, the
## player's `gravity_scale` / `box_size`, or one of `Tech`'s perspective
## override fields) must be taken under [method claim_view] and given back in
## [method on_deactivate]. `Tech` keeps a watchdog that force-restores every
## guarded field whenever no tech holds a claim, so a crashed or half-written
## tech still cannot leave the game wedged in a plane it cannot flip out of.
##
## [codeblock]
## class_name TchMyTech
## extends TchBase
##
## var _saved := 1.0
##
## func on_activate() -> bool:
##     var p := player()
##     if p == null:
##         return false          # refuse: no energy is spent
##     claim_view()
##     _saved = p.gravity_scale
##     p.gravity_scale = 0.0
##     return true
##
## func on_deactivate() -> void:
##     var p := player()
##     if p != null:
##         p.gravity_scale = _saved
##     release_view()
## [/codeblock]
class_name TchBase
extends RefCounted

# ------------------------------------------------------------------ metadata
## Copied verbatim out of `TchCatalog`; never edited at runtime.
var id: StringName = &""
var display_name: String = "Tech"
var description: String = ""
var slot: StringName = TchCatalog.SLOT_LEGS
## instant | hold | toggle | passive — see `TchCatalog`.
var mode: String = "instant"
var energy_cost: float = 0.0
var drain: float = 0.0
var cooldown: float = 0.0
## Seconds the tech stays active. 0 means "instant" (or "until cancelled" for
## `toggle`/`hold`).
var duration: float = 0.0
var color: Color = Color(0.6, 0.8, 1.0)
var rarity: int = Const.RARITY_UNCOMMON
var price: int = 0
var requires: Array = []

# --------------------------------------------------------------------- state
var equipped: bool = false
var active: bool = false
var time_left: float = 0.0
var cooldown_left: float = 0.0
## Set by `Tech` so techs never have to reach for the autoload by name.
var manager: Node = null

var _holds_view: bool = false


## Fills the metadata from a `TchCatalog` entry. Called once by `Tech`.
func configure(def: Dictionary) -> TchBase:
	id = def.get("id", id)
	display_name = String(def.get("name", display_name))
	description = String(def.get("desc", ""))
	slot = StringName(def.get("slot", slot))
	mode = String(def.get("mode", mode))
	energy_cost = float(def.get("energy", 0.0))
	drain = float(def.get("drain", 0.0))
	cooldown = float(def.get("cooldown", 0.0))
	duration = float(def.get("duration", 0.0))
	color = def.get("color", color)
	rarity = int(def.get("rarity", rarity))
	price = int(def.get("price", 0))
	requires = (def.get("requires", []) as Array).duplicate()
	return self


# ------------------------------------------------------------------- helpers
func player() -> VoxelEntity:
	return Game.player


func is_passive() -> bool:
	return mode == "passive"


func is_ready() -> bool:
	return cooldown_left <= 0.0


## Fraction of the cooldown still to run, 1 -> 0. Drives the HUD dial.
func cooldown_fraction() -> float:
	return 0.0 if cooldown <= 0.0 else clampf(cooldown_left / cooldown, 0.0, 1.0)


## Take the guarded-state lock. Idempotent.
func claim_view() -> void:
	if _holds_view:
		return
	_holds_view = true
	if manager != null and manager.has_method(&"claim_view"):
		manager.call(&"claim_view", self)


## Give the guarded state back. Idempotent, and safe to call when not held.
func release_view() -> void:
	if not _holds_view:
		return
	_holds_view = false
	if manager != null and manager.has_method(&"release_view"):
		manager.call(&"release_view", self)


func holds_view() -> bool:
	return _holds_view


func _fx(effect: StringName, amount: int = 8) -> void:
	var p := player()
	if p != null:
		Events.spawn_particles.emit(effect, p.aabb_center(), amount)


func _sound(sound_id: StringName) -> void:
	var p := player()
	Events.play_sound.emit(sound_id, p.global_position if p != null else Vector3.ZERO)


# ------------------------------------------------------------------- overrides
## Called when the tech enters a slot. Set up passive state here.
func on_equip() -> void:
	pass


## Return false to refuse activation — no energy is spent and no cooldown runs.
func on_activate() -> bool:
	return true


## Every physics frame while the tech is equipped. `active` tells you whether
## the tech is currently firing; passive techs only ever see `active == false`.
func on_update(_delta: float) -> void:
	pass


## Runs exactly once for every successful `on_activate`. Restore everything.
func on_deactivate() -> void:
	pass


## Called when the tech leaves its slot. `on_deactivate` has already run if the
## tech was active.
func on_unequip() -> void:
	pass


## Passive multiplicative stat modifiers. Recognised keys are a convention, not
## a contract: "move_speed", "jump_speed", "mining_speed", "energy_regen",
## "defense", "fall_damage", "swim_speed", "flip_cost".
func modifier(_stat: String) -> float:
	return 1.0


## Optional hook for techs that care about world events. `Tech` forwards
## &"landed", &"damaged", &"flip", &"layer" with a small payload.
func on_event(_what: StringName, _data: Dictionary) -> void:
	pass


# --------------------------------------------------------------- presentation
## Everything the HUD needs to draw one tech chip.
func hud_state() -> Dictionary:
	return {
		"id": String(id), "name": display_name, "slot": String(slot),
		"color": color, "active": active, "ready": is_ready(),
		"cooldown": cooldown_fraction(),
		"time": (time_left / duration) if duration > 0.0 and active else 0.0,
		"cost": energy_cost, "drain": drain, "mode": mode,
	}


## Per-tech persistent data. Most techs have none; override when they do.
func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
