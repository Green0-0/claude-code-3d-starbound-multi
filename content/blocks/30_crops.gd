## Crops, farm soil and greenhouse blocks.
##
## Every crop in `SrvFarming.crop_table()` expands into one block per growth
## stage, named `<crop>_stage_<n>` with `n` running `0 .. stages-1`. Stage 0 is
## the seedling; the last stage is ripe and is the only one that harvests.
## `survival/farming.gd` installs the `on_random_tick` / `on_interact` hooks on
## these at boot — the definitions here stay pure data.
##
## ## Why every crop is `Render.CROSS`
##
## Two quads crossed at 90° are the same silhouette from all four viewing
## planes. That matters more here than in a normal voxel game: the player flips
## the camera constantly, and a billboard or a single quad would turn a field of
## wheat into a field of invisible edges the moment the view rotated. A cross
## plant is legible from North, West, South and East, so a farm plot laid out
## along X reads exactly the same after a flip makes Z the lateral axis.
##
## ## Naming contract (other agents key off these)
##
## | thing | id |
## |---|---|
## | growth stage | `<crop>_stage_<n>` |
## | produce item | `<crop>` (or the row's `produce`) |
## | seed item | `<crop>_seed` |
## | tags | `crop`, `crop_stage`, `crop_<crop>`, `crop_mature` on the last stage |
extends RefCounted

## Suffix shown in the block's display name per stage, longest crop first.
const STAGE_NAMES := ["Seedling", "Sprout", "Growing", "Budding", "Ripening"]


static func register_all(reg) -> void:
	_soils(reg)
	_infrastructure(reg)
	for row: Dictionary in SrvFarming.crop_table():
		_crop(reg, row)


# ==================================================================== farm soil
static func _soils(reg) -> void:
	reg.define(&"tilled_soil", "Tilled Soil") \
		.look(Color(0.36, 0.25, 0.16), BlockType.Pattern.STRATA, Color(0.28, 0.19, 0.12)) \
		.with_top(Color(0.40, 0.28, 0.18)) \
		.mining(0.4, &"shovel", 0).sounds(&"step_dirt").drop(&"dirt") \
		.in_category(&"natural").tag(&"soil").tag(&"farm").tag(&"tilled") \
		.flags({"friction": 0.96})

	reg.define(&"watered_soil", "Watered Soil") \
		.look(Color(0.24, 0.16, 0.10), BlockType.Pattern.STRATA, Color(0.18, 0.12, 0.07)) \
		.with_top(Color(0.27, 0.19, 0.12)) \
		.mining(0.4, &"shovel", 0).sounds(&"step_dirt").drop(&"dirt") \
		.in_category(&"natural").tag(&"soil").tag(&"farm").tag(&"tilled") \
		.tag(&"watered").flags({"friction": 0.94})

	reg.define(&"fertilised_soil", "Fertilised Soil") \
		.look(Color(0.22, 0.17, 0.09), BlockType.Pattern.SPECKLE, Color(0.34, 0.28, 0.14)) \
		.with_top(Color(0.30, 0.24, 0.13)) \
		.mining(0.4, &"shovel", 0).sounds(&"step_dirt").drop(&"dirt") \
		.in_category(&"natural").tag(&"soil").tag(&"farm").tag(&"tilled") \
		.tag(&"watered").tag(&"fertilised").flags({"friction": 0.94})


static func _infrastructure(reg) -> void:
	reg.define(&"greenhouse_panel", "Greenhouse Panel") \
		.look(Color(0.72, 0.90, 0.80, 0.42), BlockType.Pattern.GLASS, Color(0.55, 0.78, 0.66)) \
		.mode(BlockType.Render.TRANSPARENT) \
		.mining(0.6, &"pickaxe", 0).sounds(&"step_glass") \
		.in_category(&"building").tag(&"glass").tag(&"farm").tag(&"greenhouse") \
		.flags({"solid": true})

	reg.define(&"irrigation_pipe", "Irrigation Pipe") \
		.look(Color(0.52, 0.62, 0.68), BlockType.Pattern.METAL, Color(0.38, 0.48, 0.54)) \
		.mode(BlockType.Render.TRANSPARENT) \
		.mining(0.9, &"pickaxe", 0).sounds(&"step_metal") \
		.in_category(&"building").tag(&"metal").tag(&"farm").tag(&"irrigation") \
		.flags({"solid": true})

	reg.define(&"compost_heap", "Compost Heap") \
		.look(Color(0.30, 0.24, 0.14), BlockType.Pattern.ORGANIC, Color(0.22, 0.18, 0.10)) \
		.mining(0.5, &"shovel", 0).sounds(&"step_dirt").drop(&"fertiliser", 1, 3) \
		.in_category(&"natural").tag(&"farm").tag(&"organic") \
		.flags({"flammable": true})


# ======================================================================= crops
static func _crop(reg, row: Dictionary) -> void:
	var crop: StringName = row["id"]
	var display: String = row["name"]
	var stages: int = row["stages"]
	var young: Color = row["young"]
	var ripe: Color = row["ripe"]
	var biome: StringName = row["biome"]
	var glow: int = row["glow"]
	var produce: StringName = row["produce"]
	var seed_item := StringName(String(crop) + "_seed")

	for stage in stages:
		var last := stage == stages - 1
		var t := float(stage) / float(maxi(1, stages - 1))
		var col := young.lerp(ripe, t)
		var alt := col.darkened(0.3).lerp(young.darkened(0.15), 0.5)
		var bname := SrvFarming.stage_block_name(crop, stage)
		var label := display if last else "%s (%s)" % [display, _stage_label(stage, stages)]

		var bt: BlockType = reg.define(bname, label)
		bt.look(col, BlockType.Pattern.ORGANIC, alt)
		bt.mode(BlockType.Render.CROSS)
		bt.mining(0.05, &"any", 0)
		bt.sounds(&"step_grass")
		bt.in_category(&"plant")
		bt.tag(&"crop").tag(&"crop_stage").tag(StringName("crop_" + String(crop)))
		bt.tag(&"organic").tag(biome)
		bt.flags({"flammable": true, "replaceable": false})
		bt.description = _describe(row, stage, stages)

		# Ripe plants glow for the bioluminescent alien crops; young ones do not.
		if glow > 0:
			bt.glows(maxi(1, int(round(float(glow) * lerpf(0.25, 1.0, t)))), 0.6 * t + 0.2)

		if last:
			bt.tag(&"crop_mature").tag(&"harvestable")
			var span: Array = row["yield"]
			bt.drop(produce, int(span[0]), int(span[1]))
			var seeds: Array = row["seeds"]
			bt.drop(seed_item, int(seeds[0]), int(seeds[1]))
		else:
			# Breaking an unripe plant gets the seed back and nothing else.
			bt.drop(seed_item, 1, 1, 0.85)

		if bool(row["aquatic"]):
			bt.tag(&"aquatic")
		if bool(row["perennial"]):
			bt.tag(&"perennial")


static func _stage_label(stage: int, stages: int) -> String:
	if stages <= 2:
		return STAGE_NAMES[0]
	# Spread the available words across however many stages this crop has.
	var i := int(round(float(stage) / float(stages - 1) * float(STAGE_NAMES.size() - 1)))
	return STAGE_NAMES[clampi(i, 0, STAGE_NAMES.size() - 1)]


static func _describe(row: Dictionary, stage: int, stages: int) -> String:
	if stage < stages - 1:
		return "%s, still growing." % row["name"]
	var bits := PackedStringArray()
	bits.append("Ripe %s, ready to harvest." % String(row["name"]).to_lower())
	if bool(row["perennial"]):
		bits.append("Regrows after picking.")
	if bool(row["aquatic"]):
		bits.append("Grows underwater.")
	if int(row["light"]) <= 0:
		bits.append("Needs no light.")
	return " ".join(bits)
