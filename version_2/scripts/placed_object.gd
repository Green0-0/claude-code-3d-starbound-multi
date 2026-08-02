class_name PlacedObject
extends Node3D

## A placed object in the world: a chest, a station, a machine, a door, a lamp.
##
## Objects sit outside the voxel field because the voxel field is one byte per
## cell with no room for state, and every interesting object has state — a
## chest has an inventory, a furnace has a burn timer, a door knows whether it
## is open. They are built from coloured boxes at spawn, so the game still ships
## with no binary assets.

signal used(who: Node)

var def: ObjectDB.Def
var cell := Vector3i.ZERO
var game: Node

var storage: Array[Items.Stack] = []      ## Kind.CONTAINER
var station: Crafting.Station = null      ## Kind.STATION / MACHINE
var open := false                         ## Kind.DOOR
var state := {}                           ## anything a subtype wants persisted

var _light: OmniLight3D
var _body: Node3D
var _anim := 0.0


## Build one, unless that cell is already taken.
##
## Nothing may stack two objects in a cell, and the rule lives here because the
## case that needed it is not the obvious one. Structures queue themselves again
## every time their chunk regenerates, which is how a village comes back when
## the player returns to it — but objects, unlike villagers, are saved and are
## never unloaded, because a chest may have the player's things in it. So each
## return trip laid a fresh chest inside the old one. Refusing here keeps the
## first one, contents and all, and keeps the count bounded by the world rather
## than by how often it has been walked across.
static func create(parent: Node, g: Node, id: StringName, at: Vector3i) -> PlacedObject:
	var d := ObjectDB.get_def(id)
	if d == null:
		return null
	for n in parent.get_children():
		var existing := n as PlacedObject
		if existing != null and existing.cell == at:
			return null
	var o := PlacedObject.new()
	o.def = d
	o.cell = at
	o.game = g
	parent.add_child(o)
	o.global_position = Vector3(at) + Vector3(0.5, 0.0, 0.5)
	return o


func _ready() -> void:
	add_to_group(&"placed_objects")
	if def == null:
		queue_free()
		return
	if def.kind == ObjectDB.Kind.CONTAINER:
		storage.resize(def.capacity)
		for i in def.capacity:
			storage[i] = Items.Stack.new()
	elif def.station != &"":
		station = Crafting.Station.new(def.station)
	elif def.kind == ObjectDB.Kind.MACHINE and def.station != &"":
		station = Crafting.Station.new(def.station)

	_build_body()
	if def.light > 0:
		_light = OmniLight3D.new()
		_light.light_color = def.accent
		_light.light_energy = float(def.light) / 9.0
		_light.omni_range = 3.0 + float(def.light) * 0.7
		_light.position = Vector3(0, def.size.y * 0.7, 0)
		add_child(_light)


## Objects are boxes: a body in the base colour and a band of accent, which is
## enough to tell a furnace from a chest at HD-2D distance.
func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)

	var main := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = def.size
	main.mesh = box
	main.material_override = _mat(def.color)
	main.position = Vector3(0, def.size.y * 0.5, 0)
	_body.add_child(main)

	var band := MeshInstance3D.new()
	var b2 := BoxMesh.new()
	b2.size = Vector3(def.size.x * 1.02, def.size.y * 0.22, def.size.z * 1.02)
	band.mesh = b2
	band.material_override = _mat(def.accent, def.light > 0)
	band.position = Vector3(0, def.size.y * 0.66, 0)
	_body.add_child(band)

	# feet, so furniture does not read as floating
	if def.kind == ObjectDB.Kind.FURNITURE or def.kind == ObjectDB.Kind.STATION:
		var legs := MeshInstance3D.new()
		var b3 := BoxMesh.new()
		b3.size = Vector3(def.size.x * 0.82, def.size.y * 0.18, def.size.z * 0.82)
		legs.mesh = b3
		legs.material_override = _mat(def.color.darkened(0.45))
		legs.position = Vector3(0, def.size.y * 0.09, 0)
		_body.add_child(legs)


static func _mat(col: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.6
	return m


func _process(delta: float) -> void:
	if station != null and not station.instant:
		var done := station.tick(delta)
		for r in done:
			if game != null:
				game.on_station_finished(self, r)
	if def.kind == ObjectDB.Kind.DOOR:
		_anim = lerpf(_anim, 1.0 if open else 0.0, 1.0 - exp(-10.0 * delta))
		_body.position.y = _anim * def.size.y * 0.95
	elif def.light > 0 and _light != null:
		# a flicker on anything with a flame in it
		_anim += delta
		_light.light_energy = float(def.light) / 9.0 \
			* (0.92 + sin(_anim * 7.0) * 0.05 + sin(_anim * 13.0) * 0.03)


## Does this object stop a moving entity from entering `c`?
func blocks(c: Vector3i) -> bool:
	if not def.solid or (def.kind == ObjectDB.Kind.DOOR and open):
		return false
	return occupies(c)


func occupies(c: Vector3i) -> bool:
	var h := int(ceil(def.size.y)) - 1
	if c.x != cell.x or c.z != cell.z:
		return false
	return c.y >= cell.y and c.y <= cell.y + h


func interact(who: Node) -> bool:
	match def.kind:
		ObjectDB.Kind.DOOR:
			open = not open
			used.emit(who)
			return true
		_:
			used.emit(who)
			return true


## Put a stack into a container. Returns the remainder.
func store(stack: Items.Stack) -> int:
	if def.kind != ObjectDB.Kind.CONTAINER:
		return stack.count
	for s: Items.Stack in storage:
		if stack.is_empty():
			break
		if not s.is_empty() and s.id == stack.id and s.data == stack.data:
			s.merge_from(stack)
	for s: Items.Stack in storage:
		if stack.is_empty():
			break
		if s.is_empty():
			s.merge_from(stack)
	return stack.count


## Everything a broken object gives back: itself, plus whatever it held.
func salvage() -> Array:
	var out: Array = [[def.id, 1]]
	for s: Items.Stack in storage:
		if not s.is_empty():
			out.append([s.id, s.count])
	return out


func save_state() -> Dictionary:
	var items: Array = []
	for s: Items.Stack in storage:
		items.append(s.to_dict())
	return {
		"id": String(def.id),
		"cell": [cell.x, cell.y, cell.z],
		"open": open,
		"storage": items,
		"fuel": station.fuel if station != null else 0.0,
		"state": state,
	}


func load_state(d: Dictionary) -> void:
	open = bool(d.get("open", false))
	state = d.get("state", {})
	var items: Array = d.get("storage", [])
	for i in mini(items.size(), storage.size()):
		storage[i] = Items.Stack.from_dict(items[i])
	if station != null:
		station.fuel = float(d.get("fuel", 0.0))
