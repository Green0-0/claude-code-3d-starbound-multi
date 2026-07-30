## Planetary hazards: temperature, radiation, breathable atmosphere and
## pressure. This is the module that makes a planet feel like a *place* rather
## than a texture swap — you cannot walk onto a frozen moon in a t-shirt.
##
## ## Where the numbers come from
##
## `World.planet` is the metadata dictionary `Universe` hands to
## `World.create_world()`. Three keys matter here, all optional:
##
## | key | meaning |
## |---|---|
## | `temperature` | ambient warmth, -1 (frozen) .. 0 (temperate) .. +1 (scorching). Values above 1 are read as degrees Celsius. |
## | `radiation` | 0 .. 1 ambient dose rate |
## | `breathable` | `false` for vacuum / toxic atmospheres |
## | `sea_level` | y of the ocean surface, for pressure |
##
## Anything missing defaults to "an ordinary garden world", so a planet
## generator that has not filled the fields in yet is simply hospitable.
##
## ## What protects you
##
## * **Cold / heat** — `insulation` / `cooling` from worn armour, plus nearby
##   heat sources (torches, campfires, lava) sampled from the voxel grid, plus
##   the `fire_resistance` / `ice_resistance` statuses.
## * **Radiation** — `radiation_shield` gear or the `radiation_shielding` status.
## * **Vacuum** — an EPP (`oxygen` gear stat) or the `breathing` status; without
##   one the breath meter empties and `suffocating` sets in.
## * **Pressure** — `pressure` gear below the crush depth of an ocean world.
##
## Gear stats are read defensively through whichever aggregate method the
## inventory agent ended up exposing; a missing inventory simply means
## "unprotected", never a crash.
class_name SrvEnvironment
extends Node

const BREATH_MAX := 100.0
## Seconds of held breath at full lungs, before gear.
const BREATH_SECONDS := 42.0
## Radiation dose bar, 0..100. Crossing thresholds applies `irradiated` stacks.
const DOSE_MAX := 100.0

## Comfort band: |body| below this and nothing bad happens.
## Half-width of the comfortable band, in the -1..+1 temperature scale.
##
## Must be wide enough that an ordinary temperate planet at noon is comfortable:
## `Universe` hands out ~0.2-0.3 for forest worlds and midday adds a further
## +0.16, so a band of 0.35 declared heatstroke on a pleasant afternoon.
const COMFORT := 0.55
## How much one adjacent torch-grade light source warms you.
const HEAT_PER_SOURCE := 0.55
const HEAT_SAMPLE_RADIUS := 5

## How far below `sea_level` an ocean world starts crushing you.
const CRUSH_DEPTH := 26.0

## Ambient planetary values, refreshed on `world_ready`.
var ambient_temperature := 0.0
var ambient_radiation := 0.0
var breathable := true
var sea_level := float(Const.WORLD_HEIGHT) * 0.5

## Live player-facing values.
var body_temperature := 0.0     ## -1 freezing .. +1 overheating
var local_heat := 0.0           ## warmth contributed by nearby blocks
var breath := BREATH_MAX
var dose := 0.0

var enabled := true

var _sample_timer := 0.0
var _emit_timer := 0.0
var _last_reported := Vector3(9999, 9999, 9999)
## Block ids that radiate warmth, resolved once per world.
var _warm_ids: Dictionary = {}
var _cold_ids: Dictionary = {}
var _offsets: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	process_priority = -7
	_build_offsets()
	Events.world_ready.connect(_on_world_ready)


# Precomputed sparse sphere: the neighbourhood we sample for heat sources. ~70
# points instead of the 1300 a full radius-5 box would cost.
func _build_offsets() -> void:
	var pts: Array[Vector3] = []
	var r := HEAT_SAMPLE_RADIUS
	for dy in range(-3, 4):
		for dl in range(-r, r + 1):
			for dd in range(-1, 2):
				if (dl + dy + dd) % 2 != 0:
					continue          # half-density lattice
				var v := Vector3(dl, dy, dd)
				if v.length() <= float(r):
					pts.append(v)
	_offsets = PackedVector3Array(pts)


func _on_world_ready(_planet_id: String) -> void:
	var meta := World.planet
	ambient_temperature = _read_temperature(meta)
	ambient_radiation = clampf(float(meta.get("radiation", 0.0)), 0.0, 1.0)
	breathable = bool(meta.get("breathable", true))
	sea_level = float(meta.get("sea_level", float(Const.WORLD_HEIGHT) * 0.5))
	breath = BREATH_MAX
	body_temperature = ambient_temperature * 0.5
	_warm_ids.clear()
	_cold_ids.clear()
	_resolve_thermal_blocks()
	Events.environment_changed.emit(ambient_temperature, ambient_radiation, breathable)


## Accepts either the normalised -1..1 form or plain degrees Celsius.
static func _read_temperature(meta: Dictionary) -> float:
	var t := float(meta.get("temperature", 0.0))
	if t > 1.0 or t < -1.0:
		t = (t - 18.0) / 42.0
	return clampf(t, -1.0, 1.0)


## Blocks that warm or chill anything standing near them. Derived from the
## registry rather than a hard-coded list, so blocks other agents add later are
## picked up automatically.
func _resolve_thermal_blocks() -> void:
	for bt: BlockType in Blocks.types:
		if bt.id == Const.AIR:
			continue
		var warm := 0.0
		if bt.damage_element == Const.ELEM_FIRE and bt.damage_on_touch > 0.0:
			warm = 2.4                                   # lava and friends
		elif bt.light >= 10 and bt.emission >= 0.6:
			warm = 1.0                                   # campfire / furnace
		elif bt.light >= 6:
			warm = 0.6                                   # torch grade
		if bt.has_tag(&"heat_source"):
			warm = maxf(warm, 1.2)
		if warm > 0.0 and bt.color.b > bt.color.r:
			warm *= 0.35                                 # cold blue light
		if warm > 0.0:
			_warm_ids[bt.id] = warm
		elif bt.has_tag(&"ice") or bt.has_tag(&"snow"):
			_cold_ids[bt.id] = 0.35


# ==================================================================== ticking
func _physics_process(delta: float) -> void:
	if not enabled or Game.paused or Game.player == null or not World.ready_flag:
		return
	var player := Game.player
	if player.dead:
		return

	_sample_timer += delta
	if _sample_timer >= 0.5:
		_sample_timer = 0.0
		local_heat = _sample_local_heat(player)

	_tick_temperature(player, delta)
	_tick_breath(player, delta)
	_tick_radiation(player, delta)
	_tick_pressure(player)

	_emit_timer += delta
	if _emit_timer >= 0.35:
		_emit_timer = 0.0
		_publish()


# ------------------------------------------------------------- temperature
func _tick_temperature(player: VoxelEntity, delta: float) -> void:
	var target := ambient_temperature
	target += _biome_temperature_shift(player)
	target += Status.weather.temperature_shift() if Status.weather != null else 0.0
	# Night is colder, noon is hotter — only where the sky can reach you.
	if _sky_exposed(player.global_position):
		target += lerpf(-0.22, 0.16, Game.daylight)
	else:
		target *= 0.55                       # caves buffer the outside world

	# Heat sources fight the *cold*; they never cook you on their own. Adding
	# `local_heat` unconditionally would mean standing by a campfire in a
	# temperate wood gives you heatstroke, and subtracting it (as this did)
	# inverted the whole model: nearby ice reads as negative local heat, so
	# `target -= local_heat` pushed you toward *overheating* in a snowfield.
	target += minf(0.0, local_heat)          # ice and snow always chill
	var warmth := maxf(0.0, local_heat)
	# Campfires and heaters (`objects/`) apply `warm` directly rather than
	# relying on the voxel sample, so honour it here too.
	if Status.has(&"warm", player):
		warmth += 0.6
	if warmth > 0.0 and target < 0.0:
		target = minf(0.0, target + warmth)
	if player.submersion > 0.5:
		target -= 0.18

	# Gear and buffs pull the felt temperature back toward comfortable.
	var insulation := _gear_stat("insulation") + (0.5 if Status.has(&"ice_resistance", player) else 0.0)
	var cooling := _gear_stat("cooling") + (0.5 if Status.has(&"fire_resistance", player) else 0.0)
	if target < 0.0:
		target = minf(0.0, target + insulation * 0.5)
	else:
		target = maxf(0.0, target - cooling * 0.5)

	# Body temperature lags the environment, so stepping past a torch helps but
	# does not instantly reset a blizzard.
	body_temperature = lerpf(body_temperature, clampf(target, -1.5, 1.5),
		clampf(delta * 0.6, 0.0, 1.0))

	if Game.difficulty <= 0:
		Status.remove(&"freezing", player)
		Status.remove(&"overheating", player)
		return
	if body_temperature < -COMFORT:
		if not Status.has(&"freezing", player):
			Status.apply(&"freezing", player, SrvStatusEffect.PERMANENT)
			Events.toast("You are freezing.", "danger")
		if body_temperature < -0.75 and not Status.has(&"chilled", player):
			Status.apply(&"chilled", player, 6.0)
	elif body_temperature > COMFORT:
		if not Status.has(&"overheating", player):
			Status.apply(&"overheating", player, SrvStatusEffect.PERMANENT)
			Events.toast("You are overheating.", "danger")
	else:
		Status.remove(&"freezing", player)
		Status.remove(&"overheating", player)


func _biome_temperature_shift(player: VoxelEntity) -> float:
	if not PlanetGen.has_method(&"biome_at"):
		return 0.0
	var p := Const.floor_v(player.global_position)
	var biome: StringName = PlanetGen.biome_at(p.x, p.z)
	match biome:
		&"tundra", &"arctic", &"snow", &"glacier":
			return -0.45
		&"desert", &"savannah", &"volcanic", &"magma":
			return 0.45
		&"ocean", &"jungle":
			return 0.1
		_:
			return 0.0


## Sum of the warmth of nearby blocks, sampled from a sparse lattice in plane
## space so a torch to the player's left warms them in every view.
func _sample_local_heat(player: VoxelEntity) -> float:
	if _warm_ids.is_empty() and _cold_ids.is_empty():
		return 0.0
	var origin := Const.floor_v(player.aabb_center())
	var right := View.right()
	var depth := View.depth_step()
	var total := 0.0
	for o: Vector3 in _offsets:
		var p := origin
		p.x += int(o.x) * right.x + int(o.z) * depth.x
		p.z += int(o.x) * right.z + int(o.z) * depth.z
		p.y += int(o.y)
		var id := World.get_block(p)
		if id == Const.AIR:
			continue
		var w: float = _warm_ids.get(id, 0.0)
		if w > 0.0:
			var d := maxf(1.0, o.length())
			total += HEAT_PER_SOURCE * w / (d * 0.55)
		elif _cold_ids.has(id):
			total -= 0.02
	return clampf(total, -0.4, 1.4)


## Cheap "can the sky see me" probe: walk up until something opaque blocks it.
func _sky_exposed(pos: Vector3) -> bool:
	var p := Const.floor_v(pos)
	p.y += 2
	var top := mini(Const.WORLD_HEIGHT - 1, p.y + 48)
	while p.y < top:
		if World.is_opaque(p):
			return false
		p.y += 2
	return true


## True when the player is under open sky — used by the weather system too.
func is_sheltered() -> bool:
	if Game.player == null:
		return true
	return not _sky_exposed(Game.player.global_position)


# ------------------------------------------------------------------- breath
func _tick_breath(player: VoxelEntity, delta: float) -> void:
	var head := Const.floor_v(player.global_position + Vector3(0.0, player.box_size.y * 0.85, 0.0))
	var head_id := World.get_block(head)
	var underwater := Blocks.is_liquid(head_id) or player.submersion > 0.85
	var airless := not breathable
	var supplied := Status.has(&"breathing", player) or _gear_stat("oxygen") > 0.0

	if (underwater or airless) and not supplied:
		var rate := (BREATH_MAX / BREATH_SECONDS) * Status.modifier("breath_rate", player)
		if Game.difficulty >= 2:
			rate *= 1.4
		breath = maxf(0.0, breath - rate * delta)
		if breath <= 0.0:
			if underwater:
				if not Status.has(&"drowning", player):
					Status.apply(&"drowning", player, SrvStatusEffect.PERMANENT)
			elif not Status.has(&"suffocating", player):
				Status.apply(&"suffocating", player, SrvStatusEffect.PERMANENT)
				Events.toast("No atmosphere!", "danger")
	else:
		breath = minf(BREATH_MAX, breath + (BREATH_MAX / 6.0) * delta)
		Status.remove(&"drowning", player)
		Status.remove(&"suffocating", player)


## 0..1 for the HUD's breath bubble row. 1.0 means "no bar needed".
func breath_fraction() -> float:
	return breath / BREATH_MAX


# ---------------------------------------------------------------- radiation
func _tick_radiation(player: VoxelEntity, delta: float) -> void:
	var rate := ambient_radiation
	if _hazard_here() == &"radiation":
		rate = maxf(rate, 0.5)
	rate *= Status.modifier("radiation_rate", player)
	var shield := clampf(_gear_stat("radiation_shield"), 0.0, 1.0)
	if Status.has(&"radiation_shielding", player):
		shield = 1.0
	rate *= 1.0 - shield

	if rate > 0.0 and Game.difficulty > 0:
		dose = minf(DOSE_MAX, dose + rate * 4.0 * delta)
	else:
		dose = maxf(0.0, dose - 3.0 * delta)

	var want := 0
	if dose > 25.0:
		want = 1
	if dose > 55.0:
		want = 2
	if dose > 80.0:
		want = 3
	var have := Status.stacks(&"irradiated", player)
	if want > have:
		Status.apply(&"irradiated", player, SrvStatusEffect.PERMANENT, want - have)
		if have == 0:
			Events.toast("Radiation warning.", "danger")
	elif want == 0 and have > 0:
		Status.remove(&"irradiated", player)


## Purge accumulated dose — what an anti-radiation medicine actually does.
func flush_dose(amount: float) -> void:
	dose = maxf(0.0, dose - amount)


# ----------------------------------------------------------------- pressure
func _tick_pressure(player: VoxelEntity) -> void:
	if Game.difficulty <= 0:
		return
	var depth := sea_level - player.global_position.y
	var submerged := player.submersion > 0.6
	if not submerged or depth < CRUSH_DEPTH:
		Status.remove(&"crushing", player)
		return
	var rating := _gear_stat("pressure")
	var severity := (depth - CRUSH_DEPTH) / 40.0 - rating
	if severity <= 0.0:
		Status.remove(&"crushing", player)
		return
	var want := clampi(1 + int(severity), 1, 3)
	if Status.stacks(&"crushing", player) < want:
		Status.apply(&"crushing", player, SrvStatusEffect.PERMANENT, 1)


func _hazard_here() -> StringName:
	if Game.player == null or not PlanetGen.has_method(&"biome_at"):
		return &"none"
	return StringName(World.planet.get("hazard", &"none"))


# ================================================================= gear stats
## Sum of `key` across worn equipment. Tries every aggregate name the inventory
## agent might have chosen, then falls back to walking the equipment slots.
func _gear_stat(key: String) -> float:
	if Game.player == null:
		return 0.0
	var inv: Variant = Game.player.get(&"inventory")
	if inv == null or not (inv is Object):
		return 0.0
	var obj := inv as Object
	for method: StringName in [&"total_stat", &"total_bonus", &"stat_total", &"total_of"]:
		if obj.has_method(method):
			return float(obj.call(method, key))
	var equipment: Variant = obj.get(&"equipment")
	if equipment is Dictionary:
		var total := 0.0
		for slot in (equipment as Dictionary):
			var st: Variant = (equipment as Dictionary)[slot]
			if st is ItemStack and not (st as ItemStack).is_empty():
				var t := (st as ItemStack).type()
				if t != null:
					total += float(t.stat_bonuses.get(key, 0.0))
		return total
	return 0.0


# ================================================================= publishing
func _publish() -> void:
	Events.stat_changed.emit("breath", breath, BREATH_MAX)
	Events.stat_changed.emit("temperature", (body_temperature + 1.0) * 50.0, 100.0)
	Events.stat_changed.emit("radiation", dose, DOSE_MAX)
	var now := Vector3(body_temperature, dose / DOSE_MAX, 1.0 if breathable else 0.0)
	if now.distance_to(_last_reported) > 0.05:
		_last_reported = now
		Events.environment_changed.emit(body_temperature, dose / DOSE_MAX, breathable)


func save_state() -> Dictionary:
	return {"breath": breath, "dose": dose, "body": body_temperature}


func load_state(d: Dictionary) -> void:
	breath = clampf(float(d.get("breath", BREATH_MAX)), 0.0, BREATH_MAX)
	dose = clampf(float(d.get("dose", 0.0)), 0.0, DOSE_MAX)
	body_temperature = clampf(float(d.get("body", 0.0)), -1.5, 1.5)
	_publish()
