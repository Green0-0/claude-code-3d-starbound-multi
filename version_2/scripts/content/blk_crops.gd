extends RefCounted

## Crops, farm soil and greenhouse infrastructure.
##
## Every crop in `CropTable` expands into one block per growth stage, named
## `<crop>_stage_<n>` with `n` running `0 .. stages-1`. Stage 0 is the seedling;
## the last stage is ripe and is the only one that yields produce. `survival.gd`
## drives the growth; the definitions here stay pure data.
##
## Every crop is `Render.CROSS` — two quads crossed at 90°. That is deliberate:
## the camera in this game is rotated constantly, and a billboard or a single
## quad would turn a wheat field into a field of invisible edges the moment the
## view turned. A cross plant reads identically from all four facings, so a plot
## laid out along X looks the same after a turn makes Z the screen-lateral axis.

const STAGE_NAMES := ["Seedling", "Sprout", "Growing", "Budding", "Ripening"]


static func register_all() -> void:
	_soils()
	_infrastructure()
	for row: Dictionary in CropTable.all():
		_crop(row)


static func _soils() -> void:
	Blocks.define(&"tilled_soil", "Tilled Soil") \
		.look(Color(0.36, 0.25, 0.16), Blocks.Pattern.STRATA, Color(0.28, 0.19, 0.12)) \
		.with_top(Color(0.40, 0.28, 0.18)).mining(0.2, &"shovel", 0) \
		.sounds(&"step_dirt").drop(&"dirt").in_category(&"natural") \
		.tag(&"soil").tag(&"farm").tag(&"tilled").flags({"friction": 0.96})

	Blocks.define(&"watered_soil", "Watered Soil") \
		.look(Color(0.24, 0.16, 0.10), Blocks.Pattern.STRATA, Color(0.18, 0.12, 0.07)) \
		.with_top(Color(0.27, 0.19, 0.12)).mining(0.2, &"shovel", 0) \
		.sounds(&"step_dirt").drop(&"dirt").in_category(&"natural") \
		.tag(&"soil").tag(&"farm").tag(&"tilled").tag(&"watered") \
		.flags({"friction": 0.94})

	Blocks.define(&"fertilised_soil", "Fertilised Soil") \
		.look(Color(0.22, 0.17, 0.09), Blocks.Pattern.SPECKLE, Color(0.34, 0.28, 0.14)) \
		.with_top(Color(0.30, 0.24, 0.13)).mining(0.2, &"shovel", 0) \
		.sounds(&"step_dirt").drop(&"dirt").in_category(&"natural") \
		.tag(&"soil").tag(&"farm").tag(&"tilled").tag(&"watered").tag(&"fertilised") \
		.flags({"friction": 0.94})


static func _infrastructure() -> void:
	Blocks.define(&"greenhouse_panel", "Greenhouse Panel") \
		.look(Color(0.72, 0.90, 0.80, 0.42), Blocks.Pattern.GLASS, Color(0.55, 0.78, 0.66)) \
		.mode(Blocks.Render.TRANSPARENT).flags({"solid": true}) \
		.mining(0.3, &"pickaxe", 0).sounds(&"step_glass").drop(&"greenhouse_panel") \
		.in_category(&"building").tag(&"glass").tag(&"farm").tag(&"greenhouse")


static func _crop(row: Dictionary) -> void:
	var crop: StringName = row["id"]
	var display: String = row["name"]
	var stages: int = row["stages"]
	var young: Color = row["young"]
	var ripe: Color = row["ripe"]
	var biome: StringName = row["biome"]
	var glow: int = row["glow"]
	var produce: StringName = row["produce"]
	var seed_item := CropTable.seed_item_name(crop)

	for stage in stages:
		var last := stage == stages - 1
		var t := float(stage) / float(maxi(1, stages - 1))
		var col := young.lerp(ripe, t)
		var alt := col.darkened(0.3).lerp(young.darkened(0.15), 0.5)
		var label := display if last else "%s (%s)" % [display, _stage_label(stage, stages)]

		var b := Blocks.define(CropTable.stage_block_name(crop, stage), label)
		b.look(col, Blocks.Pattern.ORGANIC, alt).mode(Blocks.Render.CROSS) \
			.mining(0.04, &"any", 0).sounds(&"step_grass").in_category(&"plant") \
			.tag(&"crop").tag(&"crop_stage").tag(StringName("crop_" + String(crop))) \
			.tag(&"organic").tag(biome).flags({"flammable": true})

		# Only the bioluminescent alien crops glow, and only as they ripen.
		if glow > 0:
			b.glows(maxi(1, int(round(float(glow) * lerpf(0.25, 1.0, t)))), 0.6 * t + 0.2)

		if last:
			var span: Array = row["yield"]
			var seeds: Array = row["seeds"]
			b.tag(&"crop_mature").tag(&"harvestable")
			b.drop(produce, int(span[0]), int(span[1]))
			b.drop(seed_item, int(seeds[0]), int(seeds[1]))
		else:
			# Breaking an unripe plant gets the seed back and nothing else.
			b.drop(seed_item, 1, 1, 0.85)


static func _stage_label(stage: int, stages: int) -> String:
	if stages <= 2:
		return STAGE_NAMES[0]
	var i := int(round(float(stage) / float(stages - 1) * float(STAGE_NAMES.size() - 1)))
	return STAGE_NAMES[clampi(i, 0, STAGE_NAMES.size() - 1)]
