## The weapon ladder plus the explosives chain.
##
## [b]Naming convention, shared with the combat agent's
## `content/items/30_weapons.gd`[/b] — `<metal>_<archetype>` over exactly the
## ten ladder metals (`copper iron silver gold titanium durasteel aegisalt
## ferozium violium solarium`) and the five archetypes `sword spear hammer bow
## gun`. Fifty craftable weapons, each from `<metal>_bar`.
##
## Uniques, boss drops and the `gen_*` procedural bases are deliberately
## [i]not[/i] craftable: they are loot, and `CbtWeaponGen` owns their rolls.
extends RefCounted

static func register_all(reg) -> void:
	_ladder(reg)
	_explosives(reg)


## Fifty recipes: five archetypes across ten metals.
static func _ladder(reg) -> void:
	for name_str: String in CraftLadder.GEAR_METALS:
		var mname := StringName(name_str)
		var bar := CraftLadder.bar_of(mname)
		var tier := CraftLadder.tier_of(mname)
		var station := CraftLadder.station_of(mname)
		for shape: Dictionary in CraftLadder.WEAPON_SHAPES:
			var suffix := StringName(shape["suffix"])
			var r := CraftRecipe.make("craft_%s_%s" % [mname, suffix], station) \
				.takes(bar, CraftLadder.metal_cost(tier, int(shape["metal"]))) \
				.takes(CraftLadder.HANDLE, int(shape["handle"])) \
				.gives(StringName("%s_%s" % [mname, suffix]), 1) \
				.lasts(1.0 + float(tier) * 0.5) \
				.needs_tier(tier) \
				.in_category(&"weapons").in_group(&"weaponsmith") \
				.ordered(tier * 10) \
				.describe(String(shape["desc"])) \
				.learned_from_material(bar)
			# Bows want a string; guns want a power cell and a lens.
			if suffix == &"bow":
				r.takes(&"string", 3)
			elif suffix == &"gun":
				r.takes(&"energy_cell", maxi(1, tier))
				if tier >= 3:
					r.takes(&"sensor_lens", 1)
			elif tier >= 1:
				r.takes(CraftLadder.binder_for(tier), 2)
			reg.add(r)


static func _explosives(reg) -> void:
	reg.add(CraftRecipe.make("gunpowder", &"chemistry")
		.takes(&"sulphur", 2).takes(&"charcoal", 2).takes(&"saltpetre", 2)
		.gives(&"gunpowder", 4)
		.lasts(2.0).needs_tier(2)
		.in_category(&"materials").in_group(&"chemistry")
		.describe("Three cheap powders that are only dangerous together.")
		.learned_from_material(&"saltpetre"))

	reg.add(CraftRecipe.make("gunpowder_from_ore", &"chemistry")
		.takes(&"sulphur", 3).takes(&"coal", 2).takes(&"salt", 2)
		.gives(&"gunpowder", 2)
		.lasts(2.5).needs_tier(2)
		.in_category(&"materials").in_group(&"chemistry")
		.describe("The crude route, for when you have no saltpetre.")
		.learned_from_material(&"sulphur"))

	reg.add(CraftRecipe.make("scanner_charge", &"assembler")
		.takes(&"quartz", 2).takes(&"energy_cell", 1).gives(&"scanner_charge", 4)
		.lasts(1.5).needs_tier(3)
		.in_category(&"tech").in_group(&"electronics")
		.describe("One planetary scan, in a tube.")
		.learned_from_material(&"quartz"))
