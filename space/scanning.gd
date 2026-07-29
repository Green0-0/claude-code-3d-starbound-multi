## Orbital scanning: spend a scanner charge (or fuel) to learn what a world
## actually holds before committing to a landing.
##
## Lives at `Universe.scanning`.
##
## ===========================================================================
##  SCAN LEVELS
##   0  unscanned — the star map shows only the name, kind and star colour
##   1  orbital sweep — threat, gravity, atmosphere, biome distribution, weather
##   2  deep scan — resources, dungeon presence, day length, ore richness
## ===========================================================================
##  THE REPORT DICTIONARY returned by `scan()` and cached in
##  `Universe.scan_report(id)`:
##   `id` `name` `level` `threat` `type` `type_name` `gravity` `day_length`
##   `breathable` `atmosphere` `temperature` `radiation` `hazard`
##   `weather` Array[String]
##   `biomes`  Array[{"key":String, "share":float}] sorted, biggest first
##   `resources` Array[String]   ore/material item names, "" until level 2
##   `dungeon` String            "" when none, theme tag otherwise
##   `dungeon_known` bool        false until level 2
##   `notes` Array[String]       one-line advisories for the UI
## ===========================================================================
class_name SpcScanning
extends Node

signal scan_completed(body_id: String, report: Dictionary)

## Fuel burnt when the player has no scanner charge to spend.
const FUEL_PER_SCAN := 2
const FUEL_PER_DEEP_SCAN := 5


## Can this body be scanned right now? `{ok, reason, cost_charges, cost_fuel, level}`.
func scan_quote(body_id: String, deep: bool = false) -> Dictionary:
	var out := {
		"ok": false, "reason": "", "cost_charges": 1,
		"cost_fuel": FUEL_PER_DEEP_SCAN if deep else FUEL_PER_SCAN,
		"level": 2 if deep else 1,
	}
	if not Universe.planets.has(body_id) and not Universe.bodies.has(body_id):
		out["reason"] = "Nothing to scan."
		return out
	if Universe.scan_of(body_id) >= int(out["level"]):
		out["reason"] = "Already scanned."
		return out
	if deep and Universe.scan_of(body_id) < 1:
		out["reason"] = "Run an orbital sweep first."
		return out
	var charges := Universe.upgrades.count_item(&"scanner_charge")
	if charges <= 0 and Universe.fuel() < int(out["cost_fuel"]):
		out["reason"] = "Needs a scanner charge or %d fuel." % int(out["cost_fuel"])
		return out
	out["ok"] = true
	return out


## Scan `body_id`. Consumes a `scanner_charge` if the player has one, otherwise
## burns fuel. Returns the report (empty on failure) and caches it in `Universe`.
func scan(body_id: String, deep: bool = false) -> Dictionary:
	var q := scan_quote(body_id, deep)
	if not bool(q["ok"]):
		Events.toast(String(q["reason"]), "warn")
		return {}
	if Universe.upgrades.count_item(&"scanner_charge") > 0:
		Universe.upgrades.take_item(&"scanner_charge", 1)
	elif not Universe.upgrades.consume_fuel(int(q["cost_fuel"])):
		Events.toast("Not enough fuel to scan.", "warn")
		return {}

	var level := int(q["level"])
	var report := build_report(body_id, level)
	Universe.set_scan_level(body_id, level)
	Universe.store_scan_report(body_id, report)
	Events.system_scanned.emit(String(Universe.body_info(body_id).get("system_id", "")))
	Events.play_sound.emit(&"scanner", _player_pos())
	Events.toast("%s scan complete: %s." %
		["Deep" if deep else "Orbital", String(report.get("name", body_id))], "good")
	scan_completed.emit(body_id, report)
	return report


## A star chart or a quest can hand the player a free scan.
func grant_scan(body_id: String, level: int = 1) -> Dictionary:
	var report := build_report(body_id, level)
	Universe.set_scan_level(body_id, level)
	Universe.store_scan_report(body_id, report)
	scan_completed.emit(body_id, report)
	return report


## Build the report without spending anything. The star map calls this directly
## for bodies that are already scanned.
func build_report(body_id: String, level: int) -> Dictionary:
	var meta: Dictionary = Universe.planets.get(body_id, {})
	var info: Dictionary = Universe.bodies.get(body_id, {})
	if meta.is_empty() and info.is_empty():
		return {}
	var display := String(info.get("name", meta.get("name", body_id)))
	var threat := int(info.get("threat", meta.get("threat", 1)))
	var report := {
		"id": body_id, "name": display, "level": level, "threat": threat,
		"type": String(info.get("type", meta.get("type", "barren"))),
		"type_name": String(info.get("type_name", meta.get("type_name", "World"))),
		"gravity": float(meta.get("gravity", 1.0)),
		"day_length": float(meta.get("day_length", 1.0)) if level >= 2 else 0.0,
		"breathable": bool(meta.get("breathable", true)),
		"atmosphere": String(meta.get("atmosphere", "unknown")),
		"temperature": float(meta.get("temperature", 0.0)),
		"radiation": float(meta.get("radiation", 0.0)),
		"hazard": String(meta.get("hazard", "none")),
		"weather": _string_list(meta.get("weather_set", [])),
		"biomes": _biome_list(meta),
		"resources": _resources(meta) if level >= 2 else [],
		"dungeon": String(meta.get("dungeon", "")) if level >= 2 else "",
		"dungeon_known": level >= 2,
		"notes": [],
	}
	report["notes"] = _notes(report, meta, threat)
	return report


func _string_list(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for e in (v as Array):
			out.append(String(e))
	return out


func _biome_list(meta: Dictionary) -> Array:
	var weights: Dictionary = meta.get("biome_weights", {})
	var out: Array = []
	for k: String in weights:
		out.append({"key": k, "share": float(weights[k])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["share"]) > float(b["share"]))
	return out


func _resources(meta: Dictionary) -> Array:
	var out: Array = []
	var bias: Dictionary = meta.get("ore_bias", {})
	var ranked: Array = bias.keys()
	ranked.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(bias[a]) > float(bias[b]))
	for k in ranked:
		out.append(String(k))
	return out


func _notes(report: Dictionary, meta: Dictionary, threat: int) -> Array:
	var notes: Array = []
	if not bool(report["breathable"]):
		notes.append("No breathable atmosphere — bring an EPP.")
	if float(report["temperature"]) > 0.6:
		notes.append("Extreme heat.")
	elif float(report["temperature"]) < -0.5:
		notes.append("Extreme cold.")
	if float(report["radiation"]) > 0.25:
		notes.append("Elevated radiation.")
	if int(report["level"]) >= 2 and String(report["dungeon"]) != "":
		notes.append("Structure detected: %s." % String(report["dungeon"]).replace("theme_", "").capitalize())
	if threat > Universe.ftl_tier():
		notes.append("Beyond your current FTL range.")
	elif threat > Universe.armour_tier() + 2:
		notes.append("Threat exceeds your armour by a wide margin.")
	if float(meta.get("ocean_level", 0.0)) > 0.5:
		notes.append("Predominantly ocean.")
	return notes


func _player_pos() -> Vector3:
	return Game.player.global_position if Game.player != null else Vector3.ZERO
