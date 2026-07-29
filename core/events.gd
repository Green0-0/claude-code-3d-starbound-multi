## Global signal bus. Autoloaded as `Events`.
##
## Every subsystem talks through here instead of holding direct references to
## each other; that is what lets twenty independently authored modules compose.
## NEVER add state to this file — signals only.
extends Node

# ------------------------------------------------------------------ world
signal chunk_loaded(cpos: Vector3i)
signal chunk_unloaded(cpos: Vector3i)
signal chunk_dirty(cpos: Vector3i)
signal block_changed(pos: Vector3i, old_id: int, new_id: int)
signal world_ready(planet_id: String)
signal world_unloaded()
signal time_changed(tick: int, day_fraction: float)
signal weather_changed(weather: String, intensity: float)

# ------------------------------------------------------------- perspective
## Fired the instant a flip begins. `dir` is -1 or +1.
signal view_flip_started(from_view: int, to_view: int, dir: int)
## Fired when the camera has finished settling into the new plane.
signal view_flip_finished(view: int)
## Fired when the player changes which depth layer they occupy.
signal layer_changed(layer: int, view: int)
signal flip_blocked(reason: String)

# ------------------------------------------------------------------ player
signal player_spawned(player: Node)
signal player_died(cause: String)
signal player_respawned()
signal player_damaged(amount: float, element: String, source: Node)
signal player_healed(amount: float)
signal stat_changed(stat: String, value: float, maximum: float)
signal player_moved_chunk(cpos: Vector3i)

# --------------------------------------------------------------- inventory
signal inventory_changed()
signal hotbar_selection_changed(index: int)
signal item_picked_up(item_id: String, count: int)
signal item_used(item_id: String)
signal currency_changed(amount: int)

# ---------------------------------------------------------------- crafting
signal recipe_learned(recipe_id: String)
signal item_crafted(item_id: String, count: int)
signal station_opened(station_id: String, node: Node)

# ------------------------------------------------------------------ combat
signal entity_damaged(entity: Node, amount: float, element: String, source: Node)
signal entity_died(entity: Node)
signal projectile_spawned(projectile: Node)
signal damage_number(world_pos: Vector3, amount: float, element: String, crit: bool)

# ------------------------------------------------------------------- quests
signal quest_offered(quest_id: String, giver: Node)
signal quest_started(quest_id: String)
signal quest_objective_updated(quest_id: String, index: int, progress: int, goal: int)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal dialogue_started(npc: Node, tree_id: String)
signal dialogue_ended()

# ----------------------------------------------------------------- survival
signal status_applied(id: String, duration: float)
signal status_removed(id: String)
signal environment_changed(temperature: float, radiation: float, breathable: bool)

# -------------------------------------------------------------------- space
signal ship_boarded()
signal ship_left()
signal planet_selected(planet_id: String)
signal travel_started(from_id: String, to_id: String)
signal travel_finished(planet_id: String)
signal system_scanned(system_id: String)

# ---------------------------------------------------------------------- tech
signal tech_equipped(slot: String, tech_id: String)
signal tech_activated(tech_id: String)
signal upgrade_purchased(upgrade_id: String)

# ------------------------------------------------------------------ ui / fx
signal ui_panel_opened(panel: String)
signal ui_panel_closed(panel: String)
signal notify(text: String, kind: String)
signal tooltip_requested(text: String, screen_pos: Vector2)
signal screen_shake(strength: float, duration: float)
signal play_sound(sound_id: String, world_pos: Vector3)
signal spawn_particles(effect_id: String, world_pos: Vector3, amount: int)

# ------------------------------------------------------------ persistence
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_requested(slot: int)
signal load_requested(slot: int)


## Convenience so callers do not have to remember the argument order.
func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)
