## Hand and workbench recipes: the first ten minutes of the game.
## Almost everything here is `known_at_start()` — the player must never be stuck
## because a discovery did not fire.
##
## Ingredient ids come from `content/items/10_materials.gd`; outputs that are
## blocks (`torch`, `campfire`, `wooden_ladder`, `wood_platform`, `thatch`) come
## from `content/blocks/`, which auto-generates their placer items.
extends RefCounted

static func register_all(reg) -> void:
	_hand(reg)
	_fibre(reg)
	_workbench(reg)


static func _hand(reg) -> void:
	reg.add(CraftRecipe.make("planks_from_wood", &"hand")
		.takes(&"wood", 1).gives(&"plank", 4)
		.byproduct(&"sawdust", 1, 0.5)
		.in_category(&"materials").in_group(&"hand").ordered(-100)
		.describe("Split a log into rough boards.").known_at_start())

	reg.add(CraftRecipe.make("planks_from_log_block", &"hand")
		.takes(&"wood_log", 1).gives(&"plank", 4)
		.in_category(&"materials").in_group(&"hand").ordered(-99)
		.describe("The same log, still in its placeable form.")
		.known_at_start())

	reg.add(CraftRecipe.make("sticks", &"hand")
		.takes(&"plank", 1).gives(&"stick", 4)
		.in_category(&"materials").in_group(&"hand").ordered(-98)
		.describe("Four handles out of one board.").known_at_start())

	reg.add(CraftRecipe.make("torch", &"hand")
		.takes(&"stick", 1).takes(&"coal", 1).gives(&"torch", 4)
		.in_category(&"light").in_group(&"hand").ordered(-98)
		.describe("Light is the difference between mining and dying.")
		.known_at_start())

	reg.add(CraftRecipe.make("torch_charcoal", &"hand")
		.takes(&"stick", 1).takes(&"charcoal", 1).gives(&"torch", 4)
		.in_category(&"light").in_group(&"hand").ordered(-97)
		.learned_from_material(&"charcoal"))

	reg.add(CraftRecipe.make("torch_glow", &"hand")
		.takes(&"stick", 1).takes(&"luminous_powder", 1).gives(&"torch", 6)
		.in_category(&"light").in_group(&"hand")
		.describe("Cold light. Will not set the forest alight.")
		.learned_from_material(&"luminous_powder"))

	reg.add(CraftRecipe.make("workbench", &"hand")
		.takes(&"plank", 8).gives(&"workbench", 1)
		.in_category(&"machines").in_group(&"hand").ordered(-96)
		.describe("A flat surface and a vice. Everything starts here.")
		.known_at_start())

	reg.add(CraftRecipe.make("campfire", &"hand")
		.takes(&"plank", 4).takes(&"wood", 2).takes(&"cobblestone", 3)
		.gives(&"campfire", 1)
		.in_category(&"machines").in_group(&"hand").ordered(-95)
		.describe("Cooks, warms, and keeps the dark at arm's length.")
		.known_at_start())

	reg.add(CraftRecipe.make("stone_furnace", &"hand")
		.takes(&"cobblestone", 12).gives(&"furnace", 1)
		.in_category(&"machines").in_group(&"hand").ordered(-94)
		.describe("A stone box that holds a fire in one place.")
		.known_at_start())

	reg.add(CraftRecipe.make("stone_spear", &"hand")
		.takes(&"stick", 3).takes(&"flint", 3).takes(&"plant_fibre", 2)
		.gives(&"copper_spear", 1)
		.in_category(&"weapons").in_group(&"hand")
		.describe("Pointy end goes in the monster.").known_at_start())

	reg.add(CraftRecipe.make("flint_knife", &"hand")
		.takes(&"flint", 2).takes(&"stick", 1).takes(&"plant_fibre", 1)
		.gives(&"flint_knife", 1)
		.in_category(&"tools").in_group(&"hand")
		.describe("Skins, whittles and cuts cordage.")
		.learned_from_material(&"flint"))


## Fibres, cordage and cloth — the parallel non-metal chain.
static func _fibre(reg) -> void:
	reg.add(CraftRecipe.make("rope_from_fibre", &"hand")
		.takes(&"plant_fibre", 6).gives(&"rope", 1)
		.in_category(&"materials").in_group(&"hand")
		.describe("Twist, double back, twist again.")
		.learned_from_material(&"plant_fibre"))

	reg.add(CraftRecipe.make("rope_from_vine", &"hand")
		.takes(&"vine_cord", 3).gives(&"rope", 2)
		.in_category(&"materials").in_group(&"hand")
		.learned_from_material(&"vine_cord"))

	reg.add(CraftRecipe.make("fabric_from_fibre", &"workbench")
		.takes(&"plant_fibre", 8).gives(&"cloth", 1)
		.lasts(0.6)
		.in_category(&"materials").in_group(&"general")
		.learned_from_material(&"plant_fibre"))

	reg.add(CraftRecipe.make("fabric_from_cotton", &"workbench")
		.takes(&"cotton_wool", 3).gives(&"cloth", 2)
		.lasts(0.6)
		.in_category(&"materials").in_group(&"general")
		.learned_from_material(&"cotton_wool"))

	reg.add(CraftRecipe.make("fabric_from_silk", &"workbench")
		.takes(&"silk_thread", 2).gives(&"cloth", 3)
		.lasts(0.6)
		.in_category(&"materials").in_group(&"general")
		.describe("Silk goes further than cotton, and feels better doing it.")
		.learned_from_material(&"silk_thread"))

	reg.add(CraftRecipe.make("leather_tanning", &"workbench")
		.takes(&"hide", 2).takes(&"tree_sap", 1).gives(&"leather", 1)
		.lasts(2.0)
		.in_category(&"materials").in_group(&"general")
		.describe("Cure it before it turns.")
		.learned_from_material(&"hide"))

	reg.add(CraftRecipe.make("tough_leather", &"workbench")
		.takes(&"leather", 3).takes(&"resin", 1).gives(&"tough_leather", 1)
		.lasts(2.5).needs_tier(1)
		.in_category(&"materials").in_group(&"general")
		.describe("Boiled and layered until it turns a claw.")
		.learned_from_material(&"resin"))

	reg.add(CraftRecipe.make("straw_bundle", &"workbench")
		.takes(&"plant_matter", 3).gives(&"straw", 2)
		.in_category(&"materials").in_group(&"general")
		.learned_from_material(&"plant_matter"))


static func _workbench(reg) -> void:
	reg.add(CraftRecipe.make("wooden_chest", &"workbench")
		.takes(&"plank", 8).gives(&"wooden_chest", 1)
		.lasts(0.8)
		.in_category(&"furniture").in_group(&"furnishing").known_at_start())

	reg.add(CraftRecipe.make("wooden_ladder", &"workbench")
		.takes(&"plank", 4).gives(&"wooden_ladder", 8)
		.in_category(&"blocks").in_group(&"construction").known_at_start())

	reg.add(CraftRecipe.make("rope_ladder", &"workbench")
		.takes(&"rope", 2).takes(&"plank", 2).gives(&"rope_ladder", 8)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"rope"))

	reg.add(CraftRecipe.make("vine_rope_block", &"workbench")
		.takes(&"vine_cord", 4).gives(&"vine_rope", 8)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"vine_cord"))

	reg.add(CraftRecipe.make("wood_platform", &"workbench")
		.takes(&"plank", 3).gives(&"wood_platform", 6)
		.in_category(&"blocks").in_group(&"construction")
		.describe("Stand on it, or hold down and drop through it.")
		.known_at_start())

	reg.add(CraftRecipe.make("thatch_block", &"workbench")
		.takes(&"straw", 4).gives(&"thatch", 4)
		.in_category(&"blocks").in_group(&"construction")
		.learned_from_material(&"straw"))

	reg.add(CraftRecipe.make("wooden_door", &"workbench")
		.takes(&"plank", 6).gives(&"wooden_door", 1)
		.lasts(0.8)
		.in_category(&"furniture").in_group(&"construction").known_at_start())

	reg.add(CraftRecipe.make("door_frame_wood", &"workbench")
		.takes(&"plank", 4).gives(&"door_frame_wood", 2)
		.in_category(&"blocks").in_group(&"construction").known_at_start())

	reg.add(CraftRecipe.make("bed_simple", &"workbench")
		.takes(&"plank", 5).takes(&"cloth", 3).takes(&"straw", 4)
		.gives(&"bed", 1).lasts(1.5)
		.in_category(&"furniture").in_group(&"furnishing")
		.describe("Sets your respawn point. Sleeping is optional.")
		.learned_from_material(&"cloth"))

	reg.add(CraftRecipe.make("sign_wooden", &"workbench")
		.takes(&"plank", 5).gives(&"sign", 1)
		.in_category(&"furniture").in_group(&"furnishing").known_at_start())

	reg.add(CraftRecipe.make("backpack", &"workbench")
		.takes(&"leather", 6).takes(&"cloth", 4).takes(&"rope", 2)
		.gives(&"backpack", 1).lasts(2.0)
		.in_category(&"armor").in_group(&"general")
		.describe("More slots. The only upgrade that never stops mattering.")
		.learned_from_material(&"leather"))

	reg.add(CraftRecipe.make("anvil", &"workbench")
		.takes(&"iron_bar", 8).takes(&"cobblestone", 10).gives(&"anvil", 1)
		.lasts(2.0).needs_tier(1)
		.in_category(&"machines").in_group(&"general")
		.describe("Hammer bars into things with edges.")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("kitchen_counter", &"workbench")
		.takes(&"plank", 12).takes(&"iron_bar", 2).takes(&"cobblestone", 6)
		.gives(&"kitchen", 1)
		.lasts(2.0).needs_tier(1)
		.in_category(&"machines").in_group(&"general")
		.describe("Somewhere to put a pot down.")
		.learned_from_material(&"iron_bar"))

	reg.add(CraftRecipe.make("clay_lump_from_block", &"workbench")
		.takes(&"clay", 1).gives(&"clay_lump", 2)
		.in_category(&"materials").in_group(&"general")
		.learned_from_material(&"clay"))

	reg.add(CraftRecipe.make("cement_mix", &"workbench")
		.takes(&"limestone", 2).takes(&"gravel", 1).gives(&"cement_mix", 2)
		.lasts(0.8)
		.in_category(&"materials").in_group(&"construction")
		.describe("Just add water, then hurry.")
		.learned_from_material(&"limestone"))
