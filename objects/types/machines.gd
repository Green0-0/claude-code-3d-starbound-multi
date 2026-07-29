## Machines and the wiring node zoo: processors, doors, switches, timers, logic
## gates, sensors — and the **plane sensor**, which fires on the player's
## viewing plane rather than on anything physical.
##
## ===========================================================================
##  HOW WIRED OBJECTS TICK
## ===========================================================================
## `ObjWiring` runs a synchronous two-phase tick:
##   phase 1  every wire network's power is solved from last tick's outputs
##   phase 2  every wired object reads `wiring.power_at()` and sets a new output
## Nothing a gate emits can affect its own inputs within a tick, which is why
## feedback loops (a NOT gate wired to itself) oscillate at 1 Hz instead of
## hanging the game. Objects therefore see a one-tick propagation delay, exactly
## like real redstone.
class_name ObjMachines
extends RefCounted

const OFF := 0
const ON := 15


# ===========================================================================
#  Shared base for anything with a wire input, an output or both
# ===========================================================================
class Wired extends ObjBase:
	func on_create() -> void:
		if not state.has("out"):
			state["out"] = OFF
		if not state.has("in"):
			state["in"] = OFF
		if not state.has("ch"):
			state["ch"] = int(def.get("channel", 0))

	func channel() -> int:
		return int(st("ch", 0)) & 3

	## Set this object's emitted level. Returns true when it actually changed.
	func set_output(level: int) -> bool:
		var l := clampi(level, 0, 15)
		if int(st("out", 0)) == l:
			return false
		state["out"] = l
		write()
		if manager != null and manager.has_method(&"wiring_dirty"):
			manager.call(&"wiring_dirty")
		return true

	func powered() -> bool:
		return int(st("in", 0)) > 0

	func on_signal_changed(level: int) -> void:
		var was := powered()
		state["in"] = clampi(level, 0, 15)
		write()
		if was != powered():
			on_power_edge(powered())

	## Override: called only when the input crosses the 0 boundary.
	func on_power_edge(_now_on: bool) -> void:
		pass

	## Reads the wire power on each of the six neighbouring voxels. Gates use
	## this to see their inputs individually rather than as one aggregate.
	func neighbour_levels() -> Array[int]:
		var out: Array[int] = []
		if manager == null or manager.get("wiring") == null:
			return out
		var w: Variant = manager.get("wiring")
		for nrm: Vector3i in Const.FACE_NORMALS:
			var l := int(w.call(&"power_at", World.normalize(pos + nrm), channel()))
			if l > 0:
				out.append(l)
		return out

	func save_extra() -> Dictionary:
		return {"wire": {
			"ch": channel(), "out": int(st("out", 0)), "in": int(st("in", 0)),
			"links": st("links", []),
		}}

	func load_extra(d: Dictionary) -> void:
		var w: Variant = d.get("wire", null)
		if w is Dictionary:
			var wd: Dictionary = w
			state["ch"] = int(wd.get("ch", 0))
			state["out"] = int(wd.get("out", 0))
			state["in"] = int(wd.get("in", 0))
			state["links"] = wd.get("links", [])

	## Absolute positions this object drives directly (Starbound-style links).
	func links() -> Array:
		var l: Variant = st("links", [])
		return l if l is Array else []

	func add_link(target: Vector3i) -> void:
		var l: Array = links().duplicate()
		var enc := [target.x, target.y, target.z]
		if l.has(enc):
			return
		l.append(enc)
		state["links"] = l
		write()
		if manager != null and manager.has_method(&"wiring_dirty"):
			manager.call(&"wiring_dirty")

	func clear_links() -> void:
		state["links"] = []
		write()
		if manager != null and manager.has_method(&"wiring_dirty"):
			manager.call(&"wiring_dirty")

	func build_visual() -> Node3D:
		return ObjVisual.glow(center() + Vector3(0.0, 0.34, 0.0),
			Color(0.35, 1.0, 0.45), 0.22, 1.4)

	func update_visual(_delta: float) -> void:
		if visual != null:
			visual.visible = int(st("out", 0)) > 0


# ===========================================================================
#  Processors — refinery, extractor, centrifuge
# ===========================================================================
class Processor extends Wired:
	func on_create() -> void:
		super.on_create()
		if not state.has("queue"):
			state["queue"] = []
		if not state.has("t"):
			state["t"] = 0.0

	## Right-clicking with a valid input feeds the machine directly; empty hands
	## open its panel.
	func on_interact(_player: Node) -> bool:
		var stack: ItemStack = Tech.interaction.held_stack() if Tech.interaction != null else null
		if stack != null and not stack.is_empty() and _accepts(stack.id):
			_enqueue(stack.id, 1)
			if Tech.interaction != null:
				Tech.interaction._consume(stack)
			sound(&"machine_feed")
			return true
		UI.open("machine", {
			"title": display_name, "object": self, "pos": [pos.x, pos.y, pos.z],
			"queue": st("queue", []), "powered": powered(),
		})
		Events.ui_panel_opened.emit("machine")
		return true

	func _accepts(item_id: StringName) -> bool:
		var want := StringName(def.get("accepts", &"ore"))
		var t := Items.get_type(item_id)
		return t != null and (t.has_tag(want) or t.category == want)

	func _enqueue(item_id: StringName, count: int) -> void:
		var q: Array = (st("queue", []) as Array).duplicate()
		if q.size() >= 12:
			Events.toast("%s is full." % display_name, "warn")
			return
		q.append({"id": String(item_id), "n": count})
		state["queue"] = q
		write()

	func on_tick(delta: float) -> void:
		var q: Array = st("queue", [])
		if q.is_empty():
			return
		# Wired processors need power; unwired ones just run.
		if wire_in > 0 and not powered() and bool(def.get("needs_power", false)):
			return
		var t := float(st("t", 0.0)) + delta * float(def.get("speed", 1.0))
		var need := float(def.get("process_time", 2.0))
		if t < need:
			state["t"] = t
			particles(&"machine_work", 1)
			return
		state["t"] = 0.0
		var job: Dictionary = q[0]
		q = q.duplicate()
		q.remove_at(0)
		state["queue"] = q
		write()
		_produce(StringName(job.get("id", "")), int(job.get("n", 1)))

	func _produce(item_id: StringName, count: int) -> void:
		var out := StringName(def.get("output", &""))
		if out == &"pixels":
			# The refinery pays out in currency rather than items.
			var t := Items.get_type(item_id)
			var worth := maxi(1, int((t.value if t != null else 1) * float(def.get("ratio", 1.5))))
			Events.currency_changed.emit(worth * count)
			Game.bump_stat("pixels_earned", float(worth * count))
			Events.toast("Refined %s -> %d px" % [Items.display_name(item_id), worth * count], "info")
		elif out != &"" and Items.has(out):
			Game.spawn_item_drop(center() + Vector3(0, 0.7, 0), out,
				count * maxi(1, int(def.get("ratio", 1))))
		else:
			Game.spawn_item_drop(center() + Vector3(0, 0.7, 0), item_id, count)
		particles(&"machine_output", 6)
		sound(&"machine_done")

	func on_removed() -> Array:
		var out: Array = []
		for job: Dictionary in st("queue", []):
			out.append({"item": StringName(job.get("id", "")), "count": int(job.get("n", 1))})
		return out

	func build_visual() -> Node3D:
		return ObjVisual.rotor(center() + Vector3(0.0, 0.30, 0.0),
			def.get("color", Color.WHITE).lightened(0.3), 0.34)

	func update_visual(delta: float) -> void:
		if visual == null:
			return
		var busy := not (st("queue", []) as Array).is_empty()
		visual.visible = busy
		if busy:
			ObjVisual.spin(visual, delta, 7.0)


# ===========================================================================
#  Pump — lifts liquid one voxel when powered
# ===========================================================================
class Pump extends Wired:
	func on_tick(_delta: float) -> void:
		if not powered():
			return
		var below := pos + Vector3i(0, -1, 0)
		var above := pos + Vector3i(0, 1, 0)
		var id := World.get_block(below)
		if not Blocks.is_liquid(id):
			return
		if World.get_block(above) != Const.AIR:
			return
		World.set_block(below, Const.AIR)
		World.set_block(above, id)
		if Liquids.has_method(&"queue_liquid"):
			Liquids.queue_liquid(above)
		particles(&"pump_splash", 3)


# ===========================================================================
#  Doors
# ===========================================================================
class WiredDoor extends Wired:
	func on_create() -> void:
		super.on_create()
		if not state.has("open"):
			state["open"] = false

	func on_power_edge(now_on: bool) -> void:
		_set_open(now_on)

	func on_interact(_player: Node) -> bool:
		if bool(st("locked", false)):
			Events.toast("The door is locked.", "warn")
			sound(&"locked")
			return true
		_set_open(not bool(st("open", false)))
		return true

	## The block is swapped between the solid and the open variant. `swap_block`
	## preserves the tile_data payload, so the door object survives the change.
	func _set_open(open: bool) -> void:
		if bool(st("open", false)) == open:
			return
		state["open"] = open
		var target: StringName = StringName(def.get("open_block", &"")) if open else id
		if target == &"" or not Blocks.has(target):
			target = id
		if swap_block(target):
			write()
		sound(&"door_open" if open else &"door_close")
		particles(&"door", 3)

	func on_removed() -> Array:
		# Make sure a door mined while open leaves nothing weird behind.
		state["open"] = false
		return []


# ===========================================================================
#  Switches
# ===========================================================================
class Lever extends Wired:
	func on_interact(_player: Node) -> bool:
		var on := int(st("out", 0)) > 0
		set_output(OFF if on else ON)
		_drive_links(not on)
		_run_structure_puzzle(not on)
		sound(&"lever")
		particles(&"spark", 4)
		return true

	func _drive_links(on: bool) -> void:
		for enc: Variant in links():
			if enc is Array and (enc as Array).size() == 3:
				var target := Vector3i(enc[0], enc[1], enc[2])
				if manager != null and manager.has_method(&"drive_link"):
					manager.call(&"drive_link", target, ON if on else OFF)

	## Adapter for the structures agent's `lever` marker: flipping it clears
	## every voxel listed in `controls`.
	func _run_structure_puzzle(on: bool) -> void:
		if not on:
			return
		for enc: Variant in st("controls", []):
			if enc is Array and (enc as Array).size() == 3:
				World.set_block(Vector3i(enc[0], enc[1], enc[2]), Const.AIR)


class ObjButton extends Wired:
	const HOLD := 1.2

	func on_interact(_player: Node) -> bool:
		set_output(ON)
		state["t"] = HOLD
		write()
		sound(&"button")
		particles(&"spark", 3)
		return true

	func on_tick(delta: float) -> void:
		var t := float(st("t", 0.0))
		if t <= 0.0:
			return
		t -= delta
		state["t"] = maxf(0.0, t)
		if t <= 0.0:
			set_output(OFF)
		else:
			write()


class PressurePlate extends Wired:
	func on_tick(_delta: float) -> void:
		var hit := false
		for e: VoxelEntity in Game.entities_in_radius(center(), 0.9):
			if not e.dead:
				hit = true
				break
		if set_output(ON if hit else OFF):
			sound(&"plate")


class ObjTimer extends Wired:
	func on_create() -> void:
		super.on_create()
		if not state.has("period"):
			state["period"] = float(def.get("period", 2.0))

	func on_interact(_player: Node) -> bool:
		# Cycle 0.5 / 1 / 2 / 4 / 8 second periods.
		const STEPS := [0.5, 1.0, 2.0, 4.0, 8.0]
		var p := float(st("period", 2.0))
		var i := STEPS.find(p)
		state["period"] = STEPS[(i + 1) % STEPS.size()] if i >= 0 else 1.0
		write()
		Events.toast("Timer: %.1fs" % float(st("period", 1.0)), "info")
		return true

	func on_tick(delta: float) -> void:
		var t := float(st("t", 0.0)) + delta
		var half := maxf(0.1, float(st("period", 2.0))) * 0.5
		if t < half:
			state["t"] = t
			return
		state["t"] = 0.0
		set_output(OFF if int(st("out", 0)) > 0 else ON)


class Counter extends Wired:
	func on_power_edge(now_on: bool) -> void:
		if not now_on:
			return
		var n := int(st("n", 0)) + 1
		var target := int(st("target", 4))
		if n >= target:
			n = 0
			set_output(ON if int(st("out", 0)) == 0 else OFF)
		state["n"] = n
		write()

	func on_interact(_player: Node) -> bool:
		state["target"] = wrapi(int(st("target", 4)) + 1, 2, 17)
		write()
		Events.toast("Counter: every %d pulses" % int(st("target", 4)), "info")
		return true


# ===========================================================================
#  Logic gates
# ===========================================================================
class Gate extends Wired:
	func on_tick(_delta: float) -> void:
		var inputs := neighbour_levels()
		var op := String(def.get("op", "and"))
		var out := OFF
		match op:
			"and":
				out = ON if inputs.size() >= 2 else OFF
			"or":
				out = ON if inputs.size() >= 1 else OFF
			"not":
				out = OFF if inputs.size() >= 1 else ON
			"xor":
				out = ON if inputs.size() == 1 else OFF
			"latch":
				# Set on any input; cleared only by interacting with it.
				out = ON if (inputs.size() >= 1 or int(st("out", 0)) > 0) else OFF
		set_output(out)

	func on_interact(_player: Node) -> bool:
		if String(def.get("op", "and")) == "latch":
			set_output(OFF)
			Events.toast("Latch reset.", "info")
			return true
		return false

	func build_visual() -> Node3D:
		return ObjVisual.glow(center() + Vector3(0.0, 0.32, 0.0),
			Color(1.0, 0.85, 0.35), 0.20, 1.6)


# ===========================================================================
#  Sensors
# ===========================================================================
class Sensor extends Wired:
	func on_tick(_delta: float) -> void:
		var mode := String(def.get("sense", "proximity"))
		var fire := false
		match mode:
			"proximity":
				var p := Game.player
				fire = p != null and not p.dead \
					and p.global_position.distance_to(center()) <= float(def.get("radius", 6.0)) \
					and Tech.node_in_reach(p)
			"day":
				fire = not Game.is_night()
			"night":
				fire = Game.is_night()
			"light":
				fire = Lighting.level_at(pos + Vector3i(0, 1, 0)) >= int(def.get("threshold", 8))
		if bool(st("inv", false)):
			fire = not fire
		if set_output(ON if fire else OFF):
			particles(&"sensor_ping", 2)

	func on_interact(_player: Node) -> bool:
		state["inv"] = not bool(st("inv", false))
		write()
		Events.toast("%s %s" % [display_name, "inverted" if bool(st("inv", false)) else "normal"], "info")
		return true


## ===========================================================================
##  PLANE SENSOR — the one that only makes sense in this game
## ===========================================================================
## Fires when the player is *looking at the world from a particular plane*.
## It senses the camera, not the world: nothing physical has to move for its
## output to change, so a circuit can be gated on "the player is viewing from
## the North plane" and a door will open the instant they flip to it.
##
## Configuration (cycled by interacting):
##   `state["view"]`   0..3, the plane it listens for, or -1 for "any"
##   `state["layer"]`  when true, additionally requires the player to be in the
##                     same depth layer as the sensor
##   `state["inv"]`    invert the result
##
## The output changes on `Events.view_flip_started` (the destination plane is
## authoritative immediately), so the door is already moving while the camera
## is still rotating. That is deliberate — the feedback has to land inside the
## flip animation or the mechanic reads as laggy.
class PlaneSensor extends Wired:
	func on_create() -> void:
		super.on_create()
		if not state.has("view"):
			state["view"] = rot & 3
		if not state.has("layer"):
			state["layer"] = false

	func on_tick(_delta: float) -> void:
		var want := int(st("view", 0))
		var fire := want < 0 or View.view == want
		if fire and bool(st("layer", false)):
			fire = View.is_play_layer(pos)
		if bool(st("inv", false)):
			fire = not fire
		if set_output(ON if fire else OFF):
			particles(&"plane_sensor", 5)
			sound(&"plane_sensor")

	func on_interact(_player: Node) -> bool:
		var v := int(st("view", 0)) + 1
		if v > 3:
			v = -1
		state["view"] = v
		write()
		var label: String = "any plane" if v < 0 else Const.VIEW_NAMES[v]
		Events.toast("%s listens for: %s" % [display_name, label], "info")
		sound(&"lever")
		return true

	func build_visual() -> Node3D:
		var v := int(st("view", 0))
		var col := Color(0.5, 1.0, 0.9) if v < 0 else Color(0.4, 0.8, 1.0).lerp(Color(1.0, 0.6, 0.9), float(v) / 3.0)
		return ObjVisual.panel(center() + Vector3(0.0, 0.1, 0.0), col, 0.55)

	func update_visual(_delta: float) -> void:
		if visual == null:
			return
		# The face always turns to whichever plane the player is watching from.
		visual.basis = View.camera_basis()
		visual.visible = int(st("out", 0)) > 0 or View.view == int(st("view", 0))


# ===========================================================================
#  Registration
# ===========================================================================
static func register_all() -> void:
	# -- processors ---------------------------------------------------------
	ObjRegistry.define(&"refinery", "Refinery", &"machine", Processor, {
		"color": Color(0.58, 0.50, 0.34), "pattern": BlockType.Pattern.METAL,
		"hardness": 3.4, "tool": &"pickaxe", "tier": 1, "tick": true,
		"wire_in": 1, "light": 4, "emission": 0.6,
		"accepts": &"ore", "output": &"pixels", "ratio": 1.6,
		"process_time": 1.6, "value": 480, "rarity": Const.RARITY_UNCOMMON,
		"tags": [&"machine", &"wired"],
		"desc": "Converts ore straight into pixels. Feed it by right-clicking.",
	})
	ObjRegistry.define(&"extractor", "Extractor", &"machine", Processor, {
		"color": Color(0.40, 0.56, 0.42), "pattern": BlockType.Pattern.CIRCUIT,
		"hardness": 3.2, "tool": &"pickaxe", "tier": 1, "tick": true,
		"wire_in": 1, "needs_power": true, "light": 3,
		"accepts": &"plant", "output": &"", "ratio": 2,
		"process_time": 2.4, "value": 420, "tags": [&"machine", &"wired"],
		"desc": "Breaks organic matter down into usable components. Needs power.",
	})
	ObjRegistry.define(&"centrifuge", "Centrifuge", &"machine", Processor, {
		"color": Color(0.46, 0.50, 0.60), "pattern": BlockType.Pattern.METAL,
		"hardness": 3.6, "tool": &"pickaxe", "tier": 2, "tick": true,
		"wire_in": 1, "needs_power": true, "light": 3,
		"accepts": &"liquid", "output": &"", "ratio": 1,
		"process_time": 3.0, "value": 540, "tags": [&"machine", &"wired"],
		"desc": "Spins mixtures apart. Needs power.",
	})
	ObjRegistry.define(&"pump", "Pump", &"machine", Pump, {
		"color": Color(0.38, 0.52, 0.64), "pattern": BlockType.Pattern.METAL,
		"hardness": 2.6, "tool": &"pickaxe", "tier": 1, "tick": true,
		"wire_in": 1, "value": 260, "tags": [&"machine", &"wired"],
		"desc": "Lifts liquid one voxel per tick while powered.",
	})

	# -- doors --------------------------------------------------------------
	ObjRegistry.define(&"wired_door", "Wired Door", &"machine", WiredDoor, {
		"color": Color(0.52, 0.55, 0.60), "pattern": BlockType.Pattern.METAL,
		"hardness": 2.4, "tool": &"pickaxe", "tier": 0, "wire_in": 1,
		"open_block": &"wired_door_open", "value": 120,
		"tags": [&"machine", &"wired", &"door"],
		"desc": "Opens on a wire signal, or by hand. Swaps to a walk-through variant.",
	})
	ObjRegistry.define(&"blast_door", "Blast Door", &"machine", WiredDoor, {
		"color": Color(0.44, 0.40, 0.36), "pattern": BlockType.Pattern.METAL,
		"hardness": 6.0, "tool": &"pickaxe", "tier": 2, "wire_in": 1,
		"open_block": &"blast_door_open", "value": 380,
		"rarity": Const.RARITY_UNCOMMON, "tags": [&"machine", &"wired", &"door"],
		"desc": "A door that means it. Wire only, unless you have the key.",
	})

	# -- switches -----------------------------------------------------------
	ObjRegistry.define(&"lever", "Lever", &"machine", Lever, {
		"color": Color(0.62, 0.52, 0.34), "pattern": BlockType.Pattern.PLANK,
		"hardness": 0.6, "step": &"step_wood", "wire_out": 1,
		"solid": false, "opaque": false, "render": BlockType.Render.TRANSPARENT,
		"value": 30, "tags": [&"machine", &"wired", &"switch"],
		"desc": "Latching switch. Also drives any voxels a structure told it to clear.",
	})
	ObjRegistry.define(&"button", "Button", &"machine", ObjButton, {
		"color": Color(0.78, 0.34, 0.30), "pattern": BlockType.Pattern.METAL,
		"hardness": 0.5, "wire_out": 1, "tick": true,
		"solid": false, "opaque": false, "render": BlockType.Render.TRANSPARENT,
		"value": 30, "tags": [&"machine", &"wired", &"switch"],
		"desc": "Momentary. Holds its signal for about a second.",
	})
	ObjRegistry.define(&"pressure_plate", "Pressure Plate", &"machine", PressurePlate, {
		"color": Color(0.58, 0.58, 0.62), "pattern": BlockType.Pattern.METAL,
		"hardness": 0.8, "wire_out": 1, "tick": true,
		"solid": false, "opaque": false, "render": BlockType.Render.TRANSPARENT,
		"value": 45, "tags": [&"machine", &"wired", &"switch"],
		"desc": "Fires while anything is standing on it.",
	})
	ObjRegistry.define(&"timer", "Timer", &"machine", ObjTimer, {
		"color": Color(0.50, 0.46, 0.70), "pattern": BlockType.Pattern.CIRCUIT,
		"hardness": 1.2, "wire_out": 1, "tick": true, "period": 2.0,
		"value": 110, "tags": [&"machine", &"wired", &"logic"],
		"desc": "Square wave. Interact to cycle the period.",
	})
	ObjRegistry.define(&"counter", "Counter", &"machine", Counter, {
		"color": Color(0.44, 0.48, 0.70), "pattern": BlockType.Pattern.CIRCUIT,
		"hardness": 1.2, "wire_in": 1, "wire_out": 1,
		"value": 140, "tags": [&"machine", &"wired", &"logic"],
		"desc": "Emits once every N input pulses.",
	})

	# -- logic gates --------------------------------------------------------
	_gate(&"gate_and", "AND Gate", "and", Color(0.36, 0.62, 0.86))
	_gate(&"gate_or", "OR Gate", "or", Color(0.42, 0.78, 0.52))
	_gate(&"gate_not", "NOT Gate", "not", Color(0.86, 0.44, 0.40))
	_gate(&"gate_xor", "XOR Gate", "xor", Color(0.82, 0.66, 0.34))
	_gate(&"gate_latch", "SR Latch", "latch", Color(0.66, 0.44, 0.84))

	# -- sensors ------------------------------------------------------------
	ObjRegistry.define(&"sensor", "Proximity Sensor", &"machine", Sensor, {
		"color": Color(0.40, 0.70, 0.74), "pattern": BlockType.Pattern.CIRCUIT,
		"hardness": 1.4, "wire_out": 1, "tick": true, "light": 3,
		"sense": "proximity", "radius": 6.0,
		"value": 180, "tags": [&"machine", &"wired", &"sensor"],
		"desc": "Fires while the player is nearby and in reach.",
	})
	ObjRegistry.define(&"day_sensor", "Daylight Sensor", &"machine", Sensor, {
		"color": Color(0.86, 0.78, 0.40), "pattern": BlockType.Pattern.GLASS,
		"hardness": 1.2, "wire_out": 1, "tick": true, "light": 2,
		"sense": "day", "step": &"step_glass",
		"value": 160, "tags": [&"machine", &"wired", &"sensor"],
		"desc": "On during the day. Interact to invert it into a night sensor.",
	})
	ObjRegistry.define(&"light_sensor", "Light Sensor", &"machine", Sensor, {
		"color": Color(0.74, 0.82, 0.88), "pattern": BlockType.Pattern.GLASS,
		"hardness": 1.2, "wire_out": 1, "tick": true, "sense": "light",
		"threshold": 8, "step": &"step_glass",
		"value": 170, "tags": [&"machine", &"wired", &"sensor"],
		"desc": "Fires above a light threshold at the voxel above it.",
	})
	ObjRegistry.define(&"plane_sensor", "Plane Sensor", &"machine", PlaneSensor, {
		"color": Color(0.52, 0.86, 0.95), "pattern": BlockType.Pattern.CRYSTAL,
		"hardness": 2.2, "tool": &"pickaxe", "tier": 1, "wire_out": 1,
		"tick": true, "light": 7, "emission": 1.0,
		"value": 900, "rarity": Const.RARITY_RARE,
		"tags": [&"machine", &"wired", &"sensor", &"perspective"],
		"desc": "Fires while the world is being viewed from one particular plane. Interact to choose which.",
	})


static func _gate(p_id: StringName, display: String, op: String, col: Color) -> void:
	ObjRegistry.define(p_id, display, &"machine", Gate, {
		"color": col, "pattern": BlockType.Pattern.CIRCUIT, "hardness": 1.3,
		"wire_in": 2, "wire_out": 1, "tick": true, "op": op,
		"value": 120, "tags": [&"machine", &"wired", &"logic"],
		"desc": "Logic: %s. Reads each neighbouring wire as a separate input." % op.to_upper(),
	})
