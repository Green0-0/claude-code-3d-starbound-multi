## Every placeable object's **block** counterpart, plus the wire conductors.
##
## This file does not hand-write sixty block definitions: it walks
## `ObjRegistry` — the single source of truth for objects — and derives one
## `BlockType` per entry. `content/items/50_objects.gd` walks the same list to
## derive the placer items, which is why the block name, the item id and the
## `ObjRegistry` id can never drift apart. They are all the same StringName.
##
## Three families of derived block are generated here:
##
##   `<id>`         the object itself, carrying the `on_interact` hook
##   `<id>_open`    walk-through variant for doors      (def key `open_block`)
##   `<id>_off`     unlit variant for lamps and fires   (def key `off_block`)
##
## Doors and lamps switch between variants with `ObjBase.swap_block()`, which
## preserves the tile_data payload across the `World.set_block` that would
## otherwise erase it.
##
## The interact hook is bound to `ObjHooks.interact`, a *static* function, not
## to `Tech.objects.interact`: this file runs inside `Blocks._ready()` (autoload
## #2) and the `Tech` node (#14) does not exist yet. `ObjHooks` resolves the
## manager lazily, when the hook actually fires.
extends RefCounted

## Wire channels. Four independent networks so two circuits can cross without
## touching — which matters far more here than in a 2D game, because wires also
## run through the depth axis.
const WIRE_COLORS := [
	{"id": &"wire", "name": "Wire", "color": Color(0.85, 0.80, 0.35)},
	{"id": &"wire_red", "name": "Red Wire", "color": Color(0.86, 0.32, 0.30)},
	{"id": &"wire_green", "name": "Green Wire", "color": Color(0.34, 0.82, 0.42)},
	{"id": &"wire_blue", "name": "Blue Wire", "color": Color(0.35, 0.55, 0.92)},
]


static func register_all(reg) -> void:
	_wires(reg)
	for oid: StringName in ObjRegistry.all():
		_object_block(reg, ObjRegistry.get_def(oid))


# ===========================================================================
#  Conductors
# ===========================================================================
static func _wires(reg) -> void:
	for i in WIRE_COLORS.size():
		var w: Dictionary = WIRE_COLORS[i]
		if reg.has(w["id"]):
			continue      ## another content file already claimed the name
		var bt: BlockType = reg.define(w["id"], String(w["name"]))
		bt.look(w["color"], BlockType.Pattern.CIRCUIT, (w["color"] as Color).darkened(0.45))
		bt.mode(BlockType.Render.CROSS)
		bt.mining(0.15, &"any", 0)
		bt.sounds(&"step_metal")
		bt.glows(2, 0.4)
		bt.drop(w["id"])
		bt.in_category(&"building")
		bt.tag(&"wire").tag(StringName("wire_ch%d" % i)).tag(&"object")
		bt.flags({"solid": false, "opaque": false, "replaceable": false})
		# Re-solving on every neighbour edit is what makes a cut wire go dark
		# immediately instead of on the next 10 Hz tick.
		bt.on_neighbour_changed = func(p: Vector3i, from: Vector3i) -> void:
			ObjHooks.neighbour_changed(p, from)


# ===========================================================================
#  Objects
# ===========================================================================
static func _object_block(reg, d: Dictionary) -> void:
	if d.is_empty() or reg.has(d["id"]):
		return
	var bt := _build(reg, d["id"], String(d["name"]), d)
	bt.drop(d["id"])
	bt.on_interact = func(p: Vector3i, player: Node) -> bool:
		return ObjHooks.interact(p, player)
	bt.on_neighbour_changed = func(p: Vector3i, from: Vector3i) -> void:
		ObjHooks.neighbour_changed(p, from)
	if int(d.get("wire_in", 0)) > 0 or int(d.get("wire_out", 0)) > 0:
		bt.tag(&"wired")
	if d.has("heat"):
		bt.on_entity_inside = func(p: Vector3i, e: Node, dt: float) -> void:
			ObjHooks.entity_inside(p, e, dt)

	# --- open variant (doors) ----------------------------------------------
	var open_block := StringName(d.get("open_block", &""))
	if open_block != &"" and not reg.has(open_block):
		var ov := _build(reg, open_block, String(d["name"]) + " (Open)", d)
		ov.flags({"solid": false, "opaque": false})
		ov.mode(BlockType.Render.TRANSPARENT)
		ov.look((d["color"] as Color).lightened(0.1), BlockType.Pattern.METAL)
		ov.drop(d["id"])
		ov.tag(&"hidden")
		ov.on_interact = func(p: Vector3i, player: Node) -> bool:
			return ObjHooks.interact(p, player)

	# --- unlit variant (lamps, fires) --------------------------------------
	var off_block := StringName(d.get("off_block", &""))
	if off_block == &"" and d.has("heat"):
		off_block = StringName(String(d["id"]) + "_off")
	if off_block != &"" and not reg.has(off_block):
		var ob := _build(reg, off_block, String(d["name"]) + " (Unlit)", d)
		ob.glows(0, 0.0)
		ob.look((d["color"] as Color).darkened(0.5), d["pattern"])
		ob.drop(d["id"])
		ob.tag(&"hidden")
		ob.on_interact = func(p: Vector3i, player: Node) -> bool:
			return ObjHooks.interact(p, player)


## Shared block construction from an `ObjRegistry` definition.
static func _build(reg, block_id: StringName, display: String, d: Dictionary) -> BlockType:
	var bt: BlockType = reg.define(block_id, display)
	bt.look(d["color"], d["pattern"], d["alt"])
	if (d["top"] as Color).a > 0.0:
		bt.with_top(d["top"])
	# `mode()` clears solid/opaque for some render modes, so it runs first and
	# the explicit flags below win.
	bt.mode(d["render"])
	bt.mining(float(d["hardness"]), StringName(d["tool"]), int(d["tier"]))
	bt.sounds(StringName(d["step"]))
	if int(d["light"]) > 0:
		bt.glows(int(d["light"]), float(d["emission"]))
	var cat: StringName = &"light" if int(d["light"]) > 0 else &"building"
	bt.in_category(cat)
	bt.tag(&"object").tag(d["family"])
	for t: Variant in d.get("tags", []):
		bt.tag(StringName(t))
	bt.description = String(d.get("desc", ""))
	bt.flags({"solid": bool(d["solid"]), "opaque": bool(d["opaque"])})
	for k: String in (d.get("flags", {}) as Dictionary):
		bt.flags({k: d["flags"][k]})
	return bt
