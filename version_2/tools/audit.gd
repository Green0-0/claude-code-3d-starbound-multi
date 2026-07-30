extends SceneTree

## Registry audit: run with
##   godot --headless --path . --script tools/audit.gd
## Exits non-zero if any registry overruns its hard limit or a drop dangles.

func _init() -> void:
	Blocks.boot()
	var fail := 0
	print("blocks:       %d / %d" % [Blocks.count(), Blocks.MAX_BLOCKS])
	print("atlas tiles:  %d / %d" % [
		Blocks.LEGACY_TILES + Blocks.tile_specs.size(), TexGen.ATLAS_CAPACITY])
	if Blocks.count() > Blocks.MAX_BLOCKS:
		printerr("block registry overran the one-byte voxel id")
		fail += 1
	if Blocks.LEGACY_TILES + Blocks.tile_specs.size() > TexGen.ATLAS_CAPACITY:
		printerr("atlas overflowed")
		fail += 1
	Items.boot()
	Crafting.boot()
	ObjectDB.boot()
	SpeciesDB.boot()
	Quests.boot()
	EffectLib.boot()
	print("items:        %d" % Items.count())
	print("recipes:      %d" % Crafting.recipes.size())
	print("species:      %d (%d bosses)" % [SpeciesDB.defs.size(),
		SpeciesDB.bosses().size()])
	print("objects:      %d" % ObjectDB.defs.size())
	print("quests:       %d" % Quests.catalogue.size())
	print("effects:      %d" % EffectLib.defs.size())
	print("techs:        %d" % TechCatalog.ALL.size())
	print("crops:        %d" % CropTable.all().size())
	quit(1 if fail > 0 else 0)
