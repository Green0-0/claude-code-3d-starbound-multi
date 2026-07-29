## Nightvision — amplifies whatever light there is.
##
## Publishes `Tech.nightvision_strength` (0..1). The render agent multiplies its
## ambient floor by it; if nothing reads the field the tech is harmless.
class_name TchNightvision
extends TchBase

const STRENGTH := 0.72

var _fade: float = 0.0


func on_activate() -> bool:
	claim_view()
	_sound(&"tech_nightvision")
	return true


func on_update(delta: float) -> void:
	var target := STRENGTH if active else 0.0
	_fade = move_toward(_fade, target, delta * 2.5)
	if manager != null:
		manager.set("nightvision_strength", _fade)


func on_deactivate() -> void:
	_fade = 0.0
	if manager != null:
		manager.set("nightvision_strength", 0.0)
	release_view()
