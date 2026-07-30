class_name HUD
extends CanvasLayer

## Starbound-flavoured interface: vitals and needs top-left, a nine-slot hotbar
## along the bottom, the quest tracker down the right, and a compass telling you
## which of the four planes you are viewing the world from.
##
## Everything that is not already in `main.tscn` is built here in code, so the
## scene file only has to describe the fixed frame and the panels can change
## shape without touching it.

const SLOTS := 9

@onready var root: Control = $Root
@onready var health_bar: ProgressBar = $Root/Vitals/HealthRow/HealthBar
@onready var energy_bar: ProgressBar = $Root/Vitals/EnergyRow/EnergyBar
@onready var hotbar_box: HBoxContainer = $Root/HotbarPanel/Margin/Hotbar
@onready var info_label: Label = $Root/InfoPanel/Margin/Info
@onready var compass_label: Label = $Root/CompassPanel/Margin/Compass
@onready var item_label: Label = $Root/ItemName
@onready var help_panel: PanelContainer = $Root/HelpPanel
@onready var help_text: Label = $Root/HelpPanel/Margin/Text
@onready var loading_panel: PanelContainer = $Root/LoadingPanel
@onready var loading_bar: ProgressBar = $Root/LoadingPanel/Margin/VBox/Bar
@onready var loading_text: Label = $Root/LoadingPanel/Margin/VBox/Status
@onready var death_panel: PanelContainer = $Root/DeathPanel

var player: Player
var rig: CameraRig
var world: VoxelWorld
var game: Node

var _slots: Array[Control] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _shown_id: Array[StringName] = []
var _shown_n: Array[int] = []
var _shown_sel: Array[bool] = []
var _reticle: Control
var _mine_bar: ProgressBar
var _item_fade := 0.0

var _needs: VBoxContainer
var _food_bar: ProgressBar
var _water_bar: ProgressBar
var _air_bar: ProgressBar
var _effect_strip: HBoxContainer
var _notice_box: VBoxContainer
var _tracker: VBoxContainer
var _damage_layer: Control
var _hurt_flash: ColorRect
var _hurt := 0.0

const HELP_TEXT := """VOXELBOUND

WASD    move (relative to the camera)      LMB   mine (hold)
Space   jump — auto-steps single blocks     RMB   place / use held item
Shift   sprint (burns energy)               F     swing at what you are aiming at
Ctrl    crouch · climb down ladders         R     interact (talk, open, sit)
Q / E   rotate the world 90°                G     activate equipped tech
Wheel   zoom · Ctrl+Wheel change slot       X     drop the held stack
1-9     hotbar slot                         V     toggle the cutaway system

I / Tab inventory      K crafting      J quests      M star map      T techs
F5      quick save     F1 this panel   Esc close / quit

The camera cannot be blocked: anything between the lens and you is sliced away,
and the exposed cross-section is rebuilt as real geometry. Turning the camera is
a real action — some weapons, techs and creatures only work through the cut."""


func _ready() -> void:
	_build_hotbar()
	_build_reticle()
	_build_needs()
	_build_notices()
	_build_tracker()
	_build_damage_layer()
	help_panel.visible = false
	death_panel.visible = false
	item_label.modulate.a = 0.0
	help_text.text = HELP_TEXT


func _build_hotbar() -> void:
	for i in SLOTS:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(58, 58)
		slot.add_theme_stylebox_override("panel", _slot_style(false))

		var stack := Control.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(stack)

		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 7
		icon.offset_top = 7
		icon.offset_right = -7
		icon.offset_bottom = -7
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon)

		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 11)
		num.add_theme_color_override("font_color", Color(0.66, 0.62, 0.58))
		num.position = Vector2(4, 0)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(num)

		var cnt := Label.new()
		cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt.offset_left = -34
		cnt.offset_top = -20
		cnt.offset_right = -4
		cnt.offset_bottom = -2
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.add_theme_font_size_override("font_size", 13)
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		cnt.add_theme_constant_override("outline_size", 4)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(cnt)

		hotbar_box.add_child(slot)
		_shown_id.append(&"")
		_shown_n.append(-1)
		_shown_sel.append(false)
		_slots.append(slot)
		_icons.append(icon)
		_counts.append(cnt)


static func _slot_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.078, 0.071, 0.098, 0.82) if not active else Color(0.204, 0.153, 0.118, 0.94)
	sb.border_color = Color(0.31, 0.28, 0.30, 0.85) if not active else Color(1.0, 0.68, 0.32, 1.0)
	sb.set_border_width_all(2 if not active else 3)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


static func _bar_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	return sb


func _thin_bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(140, 9)
	b.max_value = 100.0
	b.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.07, 0.75)
	bg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", _bar_style(col))
	return b


## Needs sit directly under the vitals, so the whole "am I about to die" story
## is in one column.
func _build_needs() -> void:
	_needs = VBoxContainer.new()
	_needs.add_theme_constant_override("separation", 3)
	_needs.position = Vector2(18, 92)
	root.add_child(_needs)

	_food_bar = _thin_bar(Color(0.86, 0.62, 0.28))
	_water_bar = _thin_bar(Color(0.34, 0.66, 0.94))
	_air_bar = _thin_bar(Color(0.62, 0.88, 0.96))
	_needs.add_child(_food_bar)
	_needs.add_child(_water_bar)
	_needs.add_child(_air_bar)

	_effect_strip = HBoxContainer.new()
	_effect_strip.add_theme_constant_override("separation", 3)
	_needs.add_child(_effect_strip)


func _build_notices() -> void:
	_notice_box = VBoxContainer.new()
	_notice_box.add_theme_constant_override("separation", 3)
	_notice_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice_box.position = Vector2(-220, 28)
	_notice_box.custom_minimum_size = Vector2(440, 0)
	_notice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notice_box)


func _build_tracker() -> void:
	_tracker = VBoxContainer.new()
	_tracker.add_theme_constant_override("separation", 1)
	_tracker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tracker.position = Vector2(-300, 176)
	_tracker.custom_minimum_size = Vector2(284, 0)
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tracker)


func _build_damage_layer() -> void:
	_damage_layer = Control.new()
	_damage_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_damage_layer)

	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.62, 0.08, 0.10, 0.0)
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_flash)


func _build_reticle() -> void:
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.size = Vector2(34, 34)
	root.add_child(_reticle)

	var col := Color(1.0, 0.86, 0.66, 0.9)
	var arms := [
		Rect2(15, 0, 4, 10), Rect2(15, 24, 4, 10),
		Rect2(0, 15, 10, 4), Rect2(24, 15, 10, 4),
	]
	for r in arms:
		var c := ColorRect.new()
		c.color = col
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reticle.add_child(c)

	_mine_bar = ProgressBar.new()
	_mine_bar.show_percentage = false
	_mine_bar.custom_minimum_size = Vector2(44, 6)
	_mine_bar.size = Vector2(44, 6)
	_mine_bar.position = Vector2(-5, 40)
	_mine_bar.max_value = 1.0
	_mine_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(3)
	_mine_bar.add_theme_stylebox_override("background", bg)
	_mine_bar.add_theme_stylebox_override("fill", _bar_style(Color(1.0, 0.72, 0.30)))
	_reticle.add_child(_mine_bar)


# =============================================================================
# frame
# =============================================================================

func _process(delta: float) -> void:
	if player == null:
		return

	health_bar.value = player.health
	health_bar.max_value = player.effective_max_health()
	energy_bar.value = player.energy
	energy_bar.max_value = player.effective_max_energy()

	if player.stats != null:
		_food_bar.value = player.stats.food
		_water_bar.value = player.stats.water
		_air_bar.value = player.stats.air
		_air_bar.visible = player.stats.air < 99.0
		_sync_effects()

	_sync_hotbar()

	var mp := root.get_viewport().get_mouse_position()
	_reticle.position = mp - Vector2(17, 17)
	var mining: bool = player.mine_progress > 0.0
	_mine_bar.visible = mining
	if mining:
		_mine_bar.value = clampf(player.mine_progress / maxf(player.mine_needed, 0.001), 0.0, 1.0)
	var aimed: bool = player.aim_hit.get("hit", false)
	_reticle.modulate = Color(1, 1, 1, 1.0) if aimed else Color(0.6, 0.6, 0.65, 0.5)

	if _item_fade > 0.0:
		_item_fade -= delta
		item_label.modulate.a = clampf(_item_fade, 0.0, 1.0)

	if _hurt > 0.0:
		_hurt = maxf(_hurt - delta * 2.2, 0.0)
		_hurt_flash.color.a = _hurt * 0.35

	compass_label.text = "  %s  " % rig.facing_name().to_upper()
	_sync_info()
	_sync_tracker()
	_age_damage_numbers(delta)


func _sync_hotbar() -> void:
	for i in SLOTS:
		var stack := player.inventory.get_slot(i)
		if _shown_id[i] != stack.id or _shown_n[i] != stack.count:
			_shown_id[i] = stack.id
			_shown_n[i] = stack.count
			var t := stack.type()
			_icons[i].texture = t.icon() if t != null else null
			_counts[i].text = str(stack.count) if stack.count > 1 else ""
			_icons[i].modulate = Color(1, 1, 1, 1.0 if not stack.is_empty() else 0.28)
		var sel := i == player.inventory.selected
		if _shown_sel[i] != sel:
			_shown_sel[i] = sel
			_slots[i].add_theme_stylebox_override("panel", _slot_style(sel))


func _sync_effects() -> void:
	var listed := player.stats.listed()
	while _effect_strip.get_child_count() > listed.size():
		_effect_strip.get_child(_effect_strip.get_child_count() - 1).queue_free()
		_effect_strip.remove_child(_effect_strip.get_child(_effect_strip.get_child_count() - 1))
	for i in listed.size():
		var entry: Dictionary = listed[i]
		var d: EffectLib.Def = entry["def"]
		var pip: Label
		if i < _effect_strip.get_child_count():
			pip = _effect_strip.get_child(i) as Label
		else:
			pip = Label.new()
			pip.add_theme_font_size_override("font_size", 11)
			pip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			pip.add_theme_constant_override("outline_size", 4)
			_effect_strip.add_child(pip)
		pip.text = "%s %ds" % [d.display, int(entry["left"])]
		pip.add_theme_color_override("font_color", d.color)


func _sync_info() -> void:
	var b := player.feet_block()
	var cut_state := "cross-section" if world.has_cutaway_geometry() else "clear"
	if not world.cutaway.enabled:
		cut_state = "cutaway off"
	var extra := ""
	if game != null:
		extra = "\n%s  day %d  %s   fuel %d" % [
			_planet_name(), game.sky.day, game.sky.time_string(), game.ship_fuel]
	info_label.text = "%d FPS   x %d  y %d  z %d\nview: %s   camera: %s%s" % [
		Engine.get_frames_per_second(), b.x, b.y, b.z,
		cut_state, rig.facing_name(), extra]


func _planet_name() -> String:
	if game == null:
		return ""
	var p = game.universe.get_planet(game.current_planet_id)
	return p.display if p != null else ""


func _sync_tracker() -> void:
	if game == null:
		return
	var q = game.quests.current_story()
	if q == null and not game.quests.active.is_empty():
		q = game.quests.active[0]
	var wanted := 0
	if q != null:
		wanted = 1 + q.objectives.size()
	while _tracker.get_child_count() > wanted:
		var last := _tracker.get_child(_tracker.get_child_count() - 1)
		_tracker.remove_child(last)
		last.queue_free()
	if q == null:
		return
	for i in wanted:
		var l: Label
		if i < _tracker.get_child_count():
			l = _tracker.get_child(i) as Label
		else:
			l = Label.new()
			l.add_theme_font_size_override("font_size", 13 if i > 0 else 15)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			l.add_theme_constant_override("outline_size", 5)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size = Vector2(284, 0)
			_tracker.add_child(l)
		if i == 0:
			l.text = q.title
			l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.52))
		else:
			var o: Quests.Objective = q.objectives[i - 1]
			l.text = o.label()
			l.add_theme_color_override("font_color",
				Color(0.56, 0.90, 0.58) if o.is_done() else Color(0.84, 0.82, 0.80))


# =============================================================================
# feedback
# =============================================================================

func flash_stack(stack: Items.Stack) -> void:
	if stack == null or stack.is_empty():
		return
	item_label.text = stack.display_name()
	item_label.add_theme_color_override("font_color",
		Items.RARITY_COLORS[clampi(stack.rarity(), 0, 4)])
	_item_fade = 2.0
	item_label.modulate.a = 1.0


func flash_pickup(item_id: StringName, count: int) -> void:
	var t := Items.get_type(item_id)
	if t == null:
		return
	notify("+%d %s" % [count, t.display], &"pickup")


func flash_hurt() -> void:
	_hurt = 1.0


## Floating combat text. Positions are world-space and projected each frame
## until the number expires.
func pop_damage(at: Vector3, amount: float, element: StringName, crit: bool) -> void:
	if amount <= 0.0:
		return
	var l := Label.new()
	l.text = ("%d!" % int(round(amount))) if crit else str(int(round(amount)))
	l.add_theme_font_size_override("font_size", 20 if crit else 15)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_color", _element_color(element))
	l.set_meta("world", at)
	l.set_meta("age", 0.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_layer.add_child(l)


static func _element_color(element: StringName) -> Color:
	match element:
		Blocks.ELEM_FIRE: return Color(1.0, 0.56, 0.22)
		Blocks.ELEM_ICE: return Color(0.66, 0.90, 1.0)
		Blocks.ELEM_ELECTRIC: return Color(0.86, 0.92, 1.0)
		Blocks.ELEM_POISON: return Color(0.58, 0.92, 0.40)
		Blocks.ELEM_COSMIC: return Color(0.82, 0.62, 1.0)
	return Color(1.0, 0.92, 0.80)


func _age_damage_numbers(delta: float) -> void:
	if rig == null:
		return
	var cam := rig.camera
	for n in _damage_layer.get_children():
		var l := n as Label
		if l == null:
			continue
		var age := float(l.get_meta("age")) + delta
		l.set_meta("age", age)
		if age > 0.9:
			l.queue_free()
			continue
		var world_pos: Vector3 = l.get_meta("world") + Vector3(0, age * 1.4, 0)
		if cam.is_position_behind(world_pos):
			l.visible = false
			continue
		l.visible = true
		l.position = cam.unproject_position(world_pos) - Vector2(10, 10)
		l.modulate.a = clampf(1.0 - age / 0.9, 0.0, 1.0)


const NOTICE_COLORS := {
	&"info": Color(0.86, 0.86, 0.90),
	&"warn": Color(0.98, 0.62, 0.36),
	&"quest": Color(1.0, 0.86, 0.42),
	&"craft": Color(0.64, 0.90, 0.72),
	&"pickup": Color(0.76, 0.86, 0.96),
}


func notify(text: String, kind: StringName = &"info") -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color",
		NOTICE_COLORS.get(kind, NOTICE_COLORS[&"info"]))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_box.add_child(l)
	while _notice_box.get_child_count() > 6:
		var first := _notice_box.get_child(0)
		_notice_box.remove_child(first)
		first.queue_free()
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(l, "modulate:a", 0.0, 0.7)
	tween.tween_callback(l.queue_free)


func set_loading(done: int, total: int) -> void:
	loading_panel.visible = true
	loading_bar.max_value = maxi(total, 1)
	loading_bar.value = done
	loading_text.text = "Terraforming  %d / %d chunks" % [done, total]


func finish_loading() -> void:
	loading_panel.visible = false


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func show_death(v: bool) -> void:
	death_panel.visible = v
