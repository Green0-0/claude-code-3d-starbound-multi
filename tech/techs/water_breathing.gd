## Water Breathing — passive. Electrolyses breathable air out of liquid.
##
## Publishes `Tech.oxygen_immune` for the survival agent and, where the status
## system exists, keeps a `water_breathing` status topped up so drowning logic
## written against `Status` also sees it.
class_name TchWaterBreathing
extends TchBase

var supplying: bool = false
var _refresh: float = 0.0


func on_update(delta: float) -> void:
	var p := player()
	if p == null or p.dead:
		_stop()
		return
	if p.submersion < 0.45:
		_stop()
		return
	if manager != null and not bool(manager.call(&"spend", drain * delta)):
		_stop()
		return

	if not supplying:
		supplying = true
		_sound(&"tech_breathe")
	if manager != null:
		manager.set("oxygen_immune", true)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.5
		if Status.has_method(&"apply"):
			Status.apply(&"water_breathing", p, 1.0)
		Events.spawn_particles.emit(&"bubble", p.aabb_center(), 1)


func _stop() -> void:
	if not supplying:
		return
	supplying = false
	if manager != null:
		manager.set("oxygen_immune", false)
	var p := player()
	if p != null and Status.has_method(&"remove"):
		Status.remove(&"water_breathing", p)


func on_unequip() -> void:
	_stop()


func modifier(stat: String) -> float:
	return 1.25 if (supplying and stat == "swim_speed") else 1.0
