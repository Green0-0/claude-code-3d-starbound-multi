## Placer items for every object in `ObjRegistry`, plus the wire spools.
##
## ---------------------------------------------------------------------------
## HOW `places_block` AND `places_object` RESOLVE
## ---------------------------------------------------------------------------
## An object is a voxel *plus* a `tile_data` payload, so its item has to name
## both halves:
##
##   `places_block  = &"chest_wood"`        the voxel `World.place_block` writes
##   `places_object = "obj://chest_wood"`   the `ObjRegistry` id to wake there
##
## `tech/interaction.gd::_place_object` reads `places_object`: a value starting
## with `obj://` is an `ObjRegistry` id and goes to `ObjManager.place()`, which
## sets the block and then writes the payload (in that order — `set_block`
## erases `tile_data`). A value starting with `res://` is treated as a scene
## path and handed to `Game.spawn_entity` instead, so the convention other
## agents may already have in mind still works.
##
## The item id, the block name and the object id are deliberately the same
## StringName. That is what keeps three registries in sync with no lookup table.
##
## This file runs after `20_tools.gd` and before `ItemRegistry._auto_block_items`,
## so these explicit definitions win over the automatic placer items — including
## for the hidden `_open` / `_off` block variants, which are given items that
## place the *real* object rather than their own variant.
extends RefCounted

## Human-readable labels for the object families, used in tooltips.
const FAMILY_LABEL := {
	&"container": "Storage",
	&"station": "Crafting Station",
	&"machine": "Machine",
	&"furniture": "Furniture",
	&"utility": "Utility",
}


static func register_all(reg) -> void:
	_wire_spools(reg)
	for oid: StringName in ObjRegistry.all():
		_object_item(reg, ObjRegistry.get_def(oid))
	_variant_items(reg)


# ===========================================================================
#  Objects
# ===========================================================================
static func _object_item(reg, d: Dictionary) -> void:
	if d.is_empty() or reg.has(d["id"]):
		return
	var oid: StringName = d["id"]
	var it: ItemType = reg.define(oid, String(d["name"]))
	it.of_kind(ItemType.Kind.OBJECT)
	# Both halves of the object: the voxel and the behaviour.
	it.places_block = oid
	it.places_object = "obj://" + String(oid)
	it.look(d["color"], &"cube")
	it.worth(int(d["value"]), int(d["rarity"]))
	it.stacks(int(d.get("stack", 100)))
	it.in_category(StringName(d.get("category", &"objects")))
	it.tag(&"object").tag(StringName(d["family"]))
	for t: Variant in d.get("tags", []):
		it.tag(StringName(t))

	var bits: Array[String] = [String(FAMILY_LABEL.get(d["family"], "Object"))]
	if int(d.get("wire_in", 0)) > 0:
		bits.append("wire input")
	if int(d.get("wire_out", 0)) > 0:
		bits.append("wire output")
	if int(d.get("light", 0)) > 0:
		bits.append("light %d" % int(d["light"]))
	if int(d.get("capacity", 0)) > 0:
		bits.append("%d slots" % int(d["capacity"]))
	if d.has("heat"):
		bits.append("heat source")
	it.describe("%s  [%s]" % [String(d.get("desc", "")), ", ".join(bits)])


# ===========================================================================
#  Hidden block variants
# ===========================================================================
## The `_open` and `_off` variants exist so doors and lamps can swap their voxel
## without losing their object. They should never show up in a crafting menu or
## a shop, so they are tagged `hidden` and their item places the real object.
static func _variant_items(reg) -> void:
	for oid: StringName in ObjRegistry.all():
		var d := ObjRegistry.get_def(oid)
		for key: String in ["open_block", "off_block"]:
			var variant := StringName(d.get(key, &""))
			if variant == &"" or reg.has(variant) or not Blocks.has(variant):
				continue
			_hidden_variant(reg, variant, oid, d)
		if d.has("heat"):
			var unlit := StringName(String(oid) + "_off")
			if not reg.has(unlit) and Blocks.has(unlit):
				_hidden_variant(reg, unlit, oid, d)


static func _hidden_variant(reg, variant: StringName, oid: StringName, d: Dictionary) -> void:
	var it: ItemType = reg.define(variant, String(d["name"]))
	it.of_kind(ItemType.Kind.OBJECT)
	it.places_block = oid            ## place the real thing, not the variant
	it.places_object = "obj://" + String(oid)
	it.look(d["color"], &"cube")
	it.worth(int(d["value"]), int(d["rarity"]))
	it.in_category(StringName(d.get("category", &"objects")))
	it.tag(&"object").tag(&"hidden")
	it.describe(String(d.get("desc", "")))


# ===========================================================================
#  Wire
# ===========================================================================
## Wire is a plain block item — it has no behaviour of its own, only
## conductivity, which `ObjWiring` reads straight off the block tags.
static func _wire_spools(reg) -> void:
	var spools := [
		{"id": &"wire", "name": "Wire", "color": Color(0.85, 0.80, 0.35), "ch": 0},
		{"id": &"wire_red", "name": "Red Wire", "color": Color(0.86, 0.32, 0.30), "ch": 1},
		{"id": &"wire_green", "name": "Green Wire", "color": Color(0.34, 0.82, 0.42), "ch": 2},
		{"id": &"wire_blue", "name": "Blue Wire", "color": Color(0.35, 0.55, 0.92), "ch": 3},
	]
	for s: Dictionary in spools:
		if reg.has(s["id"]):
			continue
		var it: ItemType = reg.define(s["id"], String(s["name"]))
		it.places(s["id"])
		it.look(s["color"], &"wire")
		it.worth(4)
		it.stacks(500)
		it.in_category(&"objects")
		it.tag(&"wire").tag(&"object")
		it.describe("Channel %d conductor. Carries a signal through all six directions — including into the layers behind you, so a circuit can hide in a plane you have to flip to see." % int(s["ch"]))
