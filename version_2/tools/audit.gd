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

	# --- taming. Every creature must be tameable and every food it wants must
	# be an item that exists, or a profile is a dead end the player cannot see.
	TameDB.boot()
	var untameable: Array[String] = []
	var dangling: Array[String] = []
	var knockouts := 0
	for d: SpeciesDB.Def in SpeciesDB.defs:
		var p: TameDB.Profile = TameDB.get_profile(d.id)
		if p == null:
			untameable.append(String(d.id))
			continue
		if p.method != TameDB.METHOD_PASSIVE:
			knockouts += 1
		if p.foods.is_empty():
			dangling.append("%s has nothing it will eat" % d.id)
		for f: Array in p.foods:
			if not Items.has(StringName(f[0])):
				dangling.append("%s wants missing item '%s'" % [d.id, f[0]])
		for c: StringName in p.conditions:
			if not TameDB.COND_TEXT.has(c):
				dangling.append("%s needs unknown condition '%s'" % [d.id, c])
	for f: StringName in TameDB.UNIVERSAL_FOOD:
		if not Items.has(f):
			dangling.append("universal feed '%s' does not exist" % f)
	print("taming:       %d profiles (%d knockout or harder)" % [
		TameDB.profiles.size(), knockouts])
	if not untameable.is_empty():
		printerr("no taming profile for: %s" % ", ".join(untameable))
		fail += 1
	if not dangling.is_empty():
		for line: String in dangling:
			printerr("taming: %s" % line)
		fail += 1

	quit(1 if fail > 0 else 0)
