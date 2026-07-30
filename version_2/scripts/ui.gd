class_name UIManager
extends CanvasLayer

## Every full-screen panel: inventory, crafting, quest log, star map, tech,
## dialogue and containers.
##
## Built entirely in code, like the rest of the interface, so there is no scene
## file to drift out of step with the scripts. One panel is open at a time and
## opening any of them pauses input to the world, which is what `input_locked`
## on the game hub reads.

signal panel_opened(name: StringName)
signal panel_closed()

const SLOT := 54
const PAD := 6

var game: Node
var player: Player

var current: StringName = &""
var _root: Control
var _dim: ColorRect
var _panels := {}
var _tooltip: PanelContainer
var _tooltip_label: RichTextLabel
var _held := Items.Stack.new()      ## the stack on the cursor while dragging
var _held_icon: TextureRect
var _held_from := -1

# per-panel state
var _craft_station: Crafting.Station = null
var _craft_object: PlacedObject = null
var _craft_filter: StringName = &""
var _container: PlacedObject = null
var _npc: Npc = null
var _shop_mode := false
var _selected_quest := ""
var _selected_system := ""


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.04, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_build_tooltip()
	_held_icon = TextureRect.new()
	_held_icon.custom_minimum_size = Vector2(40, 40)
	_held_icon.size = Vector2(40, 40)
	_held_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_icon.visible = false
	_root.add_child(_held_icon)


func _process(_delta: float) -> void:
	if _held_icon.visible:
		_held_icon.position = _root.get_global_mouse_position() - Vector2(20, 20)


# =============================================================================
# chrome
# =============================================================================

static func panel_style(bright := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.070, 0.095, 0.97) if not bright \
		else Color(0.12, 0.10, 0.13, 0.98)
	sb.border_color = Color(0.42, 0.36, 0.34, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func slot_style(active := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.042, 0.06, 0.9) if not active \
		else Color(0.204, 0.153, 0.118, 0.95)
	sb.border_color = Color(0.28, 0.25, 0.27, 0.9) if not active \
		else Color(1.0, 0.68, 0.32, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb


static func title(text: String, size := 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	return l


## Short labels must never wrap — a narrow container turns "120 px" into a
## column of single characters. Prose opts in with `wrap`.
static func body(text: String, size := 14, col := Color(0.84, 0.82, 0.80),
		wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, size := 15) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 30)
	return b


func _shell(name: StringName, width: float, height: float) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", panel_style())
	frame.custom_minimum_size = Vector2(width, height)
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.position = Vector2(-width * 0.5, -height * 0.5)
	frame.visible = false
	_root.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)
	_panels[name] = frame
	return col


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.add_theme_stylebox_override("panel", panel_style(true))
	_tooltip.custom_minimum_size = Vector2(280, 0)
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 20
	_root.add_child(_tooltip)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.custom_minimum_size = Vector2(256, 0)
	_tooltip_label.add_theme_font_size_override("normal_font_size", 13)
	_tooltip.add_child(_tooltip_label)


func show_tooltip(stack: Items.Stack, at: Vector2) -> void:
	if stack == null or stack.is_empty():
		hide_tooltip()
		return
	var t := stack.type()
	if t == null:
		hide_tooltip()
		return
	var rarity: int = stack.rarity()
	var col: String = Items.RARITY_COLORS[clampi(rarity, 0, 4)].to_html(false)
	var lines := PackedStringArray()
	lines.append("[color=#%s][b]%s[/b][/color]" % [col, stack.display_name()])
	lines.append("[color=#8a8590]%s · %s[/color]" % [
		Items.RARITY_NAMES[clampi(rarity, 0, 4)], _kind_name(t.kind)])
	if t.description != "":
		lines.append("")
		lines.append("[color=#b8b2ad]%s[/color]" % t.description.replace("\n", " "))
	var stats := PackedStringArray()
	if float(stack.stat("damage", 0.0)) > 0.0:
		stats.append("%.0f damage" % float(stack.stat("damage", 0.0)))
		stats.append("%.2f/s" % float(stack.stat("attack_speed", 1.0)))
		var elem := String(stack.stat("element", "physical"))
		if elem != "physical":
			stats.append(elem)
	if t.kind == Items.Kind.TOOL:
		stats.append("tier %d" % t.tool_tier)
		stats.append("x%.2f mining" % t.tool_power)
	if t.defense > 0.0:
		stats.append("%.0f defence" % t.defense)
	if t.food > 0.0:
		stats.append("%.0f nutrition" % t.food)
	if t.heal > 0.0:
		stats.append("%.0f healing" % t.heal)
	if stack.durability() > 0:
		stats.append("%d uses left" % stack.durability())
	if not stats.is_empty():
		lines.append("")
		lines.append("[color=#e0c48a]%s[/color]" % "  ·  ".join(stats))
	if not t.stat_bonuses.is_empty():
		var bonus := PackedStringArray()
		for k: String in t.stat_bonuses:
			if k == "shelf_life":
				continue
			bonus.append("%s %+.2f" % [k.replace("_", " "), float(t.stat_bonuses[k])])
		if not bonus.is_empty():
			lines.append("[color=#8fd0a0]%s[/color]" % "\n".join(bonus))
	if t.value > 0:
		lines.append("")
		lines.append("[color=#8a8590]worth %d px[/color]" % t.value)

	_tooltip_label.text = "\n".join(lines)
	_tooltip.visible = true
	_tooltip.reset_size()
	var size := _tooltip.size
	var vp := _root.size
	_tooltip.position = Vector2(
		clampf(at.x + 18, 0, maxf(vp.x - size.x - 4, 0)),
		clampf(at.y + 12, 0, maxf(vp.y - size.y - 4, 0)))


static func _kind_name(kind: int) -> String:
	match kind:
		Items.Kind.BLOCK: return "Block"
		Items.Kind.TOOL: return "Tool"
		Items.Kind.WEAPON: return "Weapon"
		Items.Kind.ARMOR: return "Armour"
		Items.Kind.CONSUMABLE: return "Consumable"
		Items.Kind.OBJECT: return "Object"
		Items.Kind.TECH: return "Tech"
		Items.Kind.SEED: return "Seed"
		Items.Kind.QUEST: return "Quest item"
		Items.Kind.CURRENCY: return "Currency"
	return "Material"


func hide_tooltip() -> void:
	_tooltip.visible = false


# =============================================================================
# open / close
# =============================================================================

func is_open() -> bool:
	return current != &""


## Toggling is what a keypress wants; `force` is what "open this container"
## wants, and getting that backwards silently closes the panel you asked for.
func open(name: StringName, force := false) -> void:
	if current == name and not force:
		close()
		return
	close()
	current = name
	_dim.visible = true
	match name:
		&"inventory": _build_inventory()
		&"crafting": _build_crafting()
		&"quests": _build_quests()
		&"starmap": _build_starmap()
		&"tech": _build_tech()
		&"dialogue": _build_dialogue()
		&"container": _build_container()
	var frame: Variant = _panels.get(name)
	if frame != null:
		frame.visible = true
	panel_opened.emit(name)


func close() -> void:
	if _held != null and not _held.is_empty() and player != null:
		player.inventory.add(_held)
		_held = Items.Stack.new()
		_held_icon.visible = false
	for k in _panels:
		_panels[k].visible = false
	_dim.visible = false
	hide_tooltip()
	if current != &"":
		current = &""
		panel_closed.emit()


func _rebuild() -> void:
	if current != &"":
		open(current, true)


func _clear(name: StringName) -> void:
	var frame: Variant = _panels.get(name)
	if frame != null:
		frame.queue_free()
		_panels.erase(name)


# =============================================================================
# inventory
# =============================================================================

func _build_inventory() -> void:
	_clear(&"inventory")
	var col := _shell(&"inventory", 760, 560)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(title("Inventory"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(body("%d px" % player.inventory.pixels, 18, Color(0.98, 0.84, 0.32)))
	col.add_child(head)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	col.add_child(main)

	# --- the bag
	var bag := VBoxContainer.new()
	bag.add_theme_constant_override("separation", 10)
	main.add_child(bag)
	bag.add_child(body("Hotbar", 13, Color(0.66, 0.62, 0.58)))
	bag.add_child(_slot_grid(Inventory.HOTBAR_START, Inventory.HOTBAR_SIZE, 9))
	bag.add_child(body("Backpack", 13, Color(0.66, 0.62, 0.58)))
	bag.add_child(_slot_grid(Inventory.BACKPACK_START, Inventory.BACKPACK_SIZE, 9))

	# --- equipment and the numbers it adds up to
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.custom_minimum_size = Vector2(190, 0)
	main.add_child(side)
	side.add_child(body("Equipped", 13, Color(0.66, 0.62, 0.58)))
	side.add_child(_slot_grid(Inventory.ARMOR_START, Inventory.ARMOR_SIZE, 1))

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	side.add_child(stats)
	stats.add_child(body("Defence  %.1f" % player.inventory.total_defense(), 13))
	stats.add_child(body("Health   %.0f" % player.effective_max_health(), 13))
	stats.add_child(body("Energy   %.0f" % player.effective_max_energy(), 13))
	for line in player.inventory.active_set_bonuses():
		stats.add_child(body(line, 12, Color(0.56, 0.86, 0.60), true))

	col.add_child(body("Left-click to pick up a stack, right-click to take one. "
		+ "Drop a stack outside the bag to throw it away.", 12,
		Color(0.60, 0.58, 0.56), true))


func _slot_grid(start: int, count: int, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", PAD)
	grid.add_theme_constant_override("v_separation", PAD)
	for i in count:
		grid.add_child(_make_slot(start + i))
	return grid


func _make_slot(index: int) -> Control:
	var stack := player.inventory.get_slot(index)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(SLOT, SLOT)
	var selected := index == player.inventory.selected \
		and index < Inventory.HOTBAR_SIZE
	pc.add_theme_stylebox_override("panel", slot_style(selected))
	pc.mouse_filter = Control.MOUSE_FILTER_STOP

	var stack_ctl := Control.new()
	stack_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(stack_ctl)

	if not stack.is_empty():
		var t := stack.type()
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 5
		icon.offset_top = 5
		icon.offset_right = -5
		icon.offset_bottom = -5
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = t.icon() if t != null else null
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack_ctl.add_child(icon)

		if stack.rarity() > 0:
			var pip := ColorRect.new()
			pip.color = Items.RARITY_COLORS[clampi(stack.rarity(), 0, 4)]
			pip.size = Vector2(SLOT - 12, 2)
			pip.position = Vector2(6, SLOT - 8)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stack_ctl.add_child(pip)

		if stack.count > 1:
			var n := Label.new()
			n.text = str(stack.count)
			n.add_theme_font_size_override("font_size", 12)
			n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			n.add_theme_constant_override("outline_size", 4)
			n.position = Vector2(SLOT - 22, SLOT - 22)
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stack_ctl.add_child(n)

	pc.gui_input.connect(_on_slot_input.bind(index))
	pc.mouse_entered.connect(func() -> void:
		show_tooltip(player.inventory.get_slot(index),
			_root.get_global_mouse_position()))
	pc.mouse_exited.connect(hide_tooltip)
	return pc


func _on_slot_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var inv := player.inventory
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if _held.is_empty():
			_held = inv.take_from(index)
			_held_from = index
		else:
			var target := inv.get_slot(index)
			if inv.is_armor_slot(index):
				var t := _held.type()
				if t == null or t.kind != Items.Kind.ARMOR \
						or Inventory.armor_index(t.armor_slot) != index:
					return
			if target.is_empty() or target.id != _held.id or target.data != _held.data:
				inv.set_slot(index, _held)
				_held = target
			else:
				target.merge_from(_held)
				inv.changed.emit()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if _held.is_empty():
			_held = inv.take_from(index, maxi(1, inv.get_slot(index).count / 2))
			_held_from = index
		else:
			var one := _held.split(1)
			if inv.add(one) > 0:
				_held.merge_from(one)
	_refresh_held()
	_rebuild()


func _refresh_held() -> void:
	if _held.is_empty():
		_held_icon.visible = false
		return
	var t := _held.type()
	_held_icon.texture = t.icon() if t != null else null
	_held_icon.visible = true


# =============================================================================
# crafting
# =============================================================================

func open_crafting(station: Crafting.Station, obj: PlacedObject = null) -> void:
	_craft_station = station
	_craft_object = obj
	_craft_filter = &""
	open(&"crafting", true)


func _build_crafting() -> void:
	_clear(&"crafting")
	if _craft_station == null:
		_craft_station = Crafting.Station.new(&"hand")
	var col := _shell(&"crafting", 820, 560)

	var head := HBoxContainer.new()
	head.add_child(title(_craft_station.label()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if _craft_station.needs_fuel:
		head.add_child(body("fuel %.0fs" % _craft_station.fuel, 14,
			Color(0.98, 0.72, 0.34)))
	col.add_child(head)

	var recipes := _craft_station.available(game.known_recipes)
	# --- category tabs
	var cats := {}
	for r: Crafting.Recipe in recipes:
		cats[r.category] = true
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	var all_btn := button("All", 13)
	all_btn.pressed.connect(func() -> void:
		_craft_filter = &""
		_rebuild())
	tabs.add_child(all_btn)
	for c: StringName in cats:
		var b := button(String(c).capitalize(), 13)
		b.pressed.connect(func() -> void:
			_craft_filter = c
			_rebuild())
		tabs.add_child(b)
	col.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var shown := 0
	for r: Crafting.Recipe in recipes:
		if _craft_filter != &"" and r.category != _craft_filter:
			continue
		list.add_child(_recipe_row(r))
		shown += 1
	if shown == 0:
		list.add_child(body("Nothing here yet. Recipes are learned by picking "
			+ "up the materials they need.", 14, Color(0.62, 0.60, 0.58), true))


func _recipe_row(r: Crafting.Recipe) -> Control:
	var can := Crafting.can_craft(player.inventory, r)
	var row := PanelContainer.new()
	var sb := slot_style(false)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)

	var out_type := Items.get_type(r.result_id())
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = out_type.icon() if out_type != null else null
	h.add_child(icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(280, 0)
	h.add_child(text)
	var label := "%s x%d" % [r.display_name(), r.result_count()]
	var name_row := body(label, 15,
		Color(0.94, 0.90, 0.86) if can else Color(0.56, 0.52, 0.52))
	name_row.clip_text = true
	text.add_child(name_row)

	var parts := PackedStringArray()
	for pair: Array in r.inputs:
		var have := player.inventory.count_of(pair[0])
		var it := Items.get_type(pair[0])
		var nm := it.display if it != null else String(pair[0])
		parts.append("%s %d/%d" % [nm, mini(have, int(pair[1])), int(pair[1])])
	text.add_child(body("  ".join(parts), 12,
		Color(0.72, 0.70, 0.66) if can else Color(0.72, 0.44, 0.42)))

	var b := button("Craft", 14)
	b.custom_minimum_size = Vector2(84, 30)
	b.disabled = not can
	b.pressed.connect(func() -> void:
		game.request_craft(r, _craft_station, _craft_object)
		_rebuild())
	h.add_child(b)

	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(func() -> void:
		if out_type != null:
			show_tooltip(Items.make(r.result_id(), r.result_count()),
				_root.get_global_mouse_position()))
	row.mouse_exited.connect(hide_tooltip)
	return row


# =============================================================================
# quest log
# =============================================================================

func _build_quests() -> void:
	_clear(&"quests")
	var col := _shell(&"quests", 760, 520)
	col.add_child(title("Quest Log"))

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)

	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(280, 420)
	main.add_child(left)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	left.add_child(list)

	var log_entries: Array = game.quests.active
	if log_entries.is_empty():
		list.add_child(body("Nothing on the books. Talk to somebody.", 14,
			Color(0.62, 0.60, 0.58), true))
	for q: Quests.Quest in log_entries:
		var b := button(("* " if q.main_story else "") + q.title, 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if q.is_complete():
			b.add_theme_color_override("font_color", Color(0.56, 0.90, 0.58))
		b.pressed.connect(func() -> void:
			_selected_quest = q.id
			_rebuild())
		list.add_child(b)
		if _selected_quest == "":
			_selected_quest = q.id

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)

	var sel: Quests.Quest = null
	for q: Quests.Quest in log_entries:
		if q.id == _selected_quest:
			sel = q
	if sel == null:
		return
	right.add_child(title(sel.title, 18))
	right.add_child(body(sel.summary, 13, Color(0.80, 0.78, 0.74), true))
	right.add_child(body("Objectives", 13, Color(0.66, 0.62, 0.58)))
	for o: Quests.Objective in sel.objectives:
		right.add_child(body(("[x] " if o.is_done() else "[ ] ") + o.label(), 13,
			Color(0.56, 0.90, 0.58) if o.is_done() else Color(0.86, 0.84, 0.80)))
	var rewards := PackedStringArray()
	if sel.reward_pixels > 0:
		rewards.append("%d px" % sel.reward_pixels)
	for pair: Array in sel.reward_items:
		var it := Items.get_type(pair[0])
		rewards.append("%s x%d" % [it.display if it != null else String(pair[0]),
			int(pair[1])])
	if not rewards.is_empty():
		right.add_child(body("Reward: " + ", ".join(rewards), 13,
			Color(0.98, 0.84, 0.42)))
	if sel.is_complete() and not sel.turn_in:
		var b := button("Claim", 15)
		b.pressed.connect(func() -> void:
			game.quests.complete(sel)
			_selected_quest = ""
			_rebuild())
		right.add_child(b)
	elif sel.is_complete():
		right.add_child(body("Return to the %s who asked."
			% String(sel.giver).capitalize(), 13, Color(0.56, 0.90, 0.58)))


# =============================================================================
# star map
# =============================================================================

func _build_starmap() -> void:
	_clear(&"starmap")
	var col := _shell(&"starmap", 820, 580)
	var head := HBoxContainer.new()
	head.add_child(title("Star Chart"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(body("fuel  %d" % game.ship_fuel, 16, Color(0.62, 0.86, 0.98)))
	col.add_child(head)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)

	# --- the chart itself, drawn as buttons laid out on their coordinates
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(440, 440)
	main.add_child(chart)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart.add_child(bg)

	for sys: Universe.System in (game.universe.systems as Array):
		if not sys.discovered:
			continue
		var b := Button.new()
		b.text = "*"
		b.tooltip_text = "%s  (%s)" % [sys.display, sys.sector]
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", sys.star_color)
		b.custom_minimum_size = Vector2(26, 26)
		b.flat = true
		b.position = Vector2(220, 220) + sys.position * 420.0 - Vector2(13, 13)
		b.pressed.connect(func() -> void:
			_selected_system = sys.id
			_rebuild())
		chart.add_child(b)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)

	if _selected_system == "":
		_selected_system = game.universe.home_system
	var sys: Universe.System = game.universe.get_system(_selected_system)
	if sys == null:
		return
	right.add_child(title(sys.display, 18))
	right.add_child(body("%s · %s" % [sys.sector, sys.star_name], 13,
		Color(0.72, 0.70, 0.68)))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 380)
	right.add_child(scroll)
	var plist := VBoxContainer.new()
	plist.add_theme_constant_override("separation", 4)
	scroll.add_child(plist)

	for p: Universe.Planet in sys.planets:
		if not p.discovered:
			plist.add_child(body("· unscanned body", 13, Color(0.44, 0.42, 0.44)))
			continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var here: bool = p.id == game.current_planet_id
		var title_row := body(p.display + ("  (here)" if here else ""), 15,
			Color(0.98, 0.86, 0.54) if here else Color(0.90, 0.88, 0.84))
		title_row.clip_text = true
		row.add_child(title_row)
		row.add_child(body("%s · %s · fuel %d"
			% [p.type_name, p.threat_name(), p.fuel_cost], 12,
			Color(0.68, 0.66, 0.64)))
		if not here:
			var b := button("Travel", 13)
			b.disabled = game.ship_fuel < p.fuel_cost
			b.pressed.connect(func() -> void:
				close()
				game.travel_to(p.id))
			row.add_child(b)
		plist.add_child(row)


# =============================================================================
# tech
# =============================================================================

func _build_tech() -> void:
	_clear(&"tech")
	var col := _shell(&"tech", 720, 520)
	col.add_child(title("Techs"))
	col.add_child(body("One per slot. G fires the legs or body tech you have "
		+ "equipped; head techs are passive.", 13, Color(0.72, 0.70, 0.68), true))

	for slot: StringName in TechCatalog.SLOTS:
		col.add_child(body(String(slot).capitalize(), 14, Color(0.98, 0.84, 0.42)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		var any := false
		for d: Dictionary in TechCatalog.in_slot(slot):
			if not game.tech.has(d["id"]):
				continue
			any = true
			var equipped: bool = game.tech.equipped_in(slot) == StringName(d["id"])
			var b := button(String(d["name"]), 13)
			b.custom_minimum_size = Vector2(150, 34)
			b.tooltip_text = String(d["desc"])
			if equipped:
				b.add_theme_color_override("font_color", Color(1.0, 0.78, 0.36))
			b.pressed.connect(func() -> void:
				if equipped:
					game.tech.unequip(slot)
				else:
					game.tech.equip(d["id"])
				_rebuild())
			row.add_child(b)
		if not any:
			row.add_child(body("nothing unlocked", 13, Color(0.52, 0.50, 0.52)))


# =============================================================================
# dialogue and shops
# =============================================================================

func open_dialogue(npc: Npc, shop := false) -> void:
	_npc = npc
	_shop_mode = shop
	open(&"dialogue", true)


func _build_dialogue() -> void:
	_clear(&"dialogue")
	if _npc == null:
		return
	var col := _shell(&"dialogue", 830, 540)
	col.add_child(title("%s — %s" % [_npc.npc_name, _npc.role.display]))

	if not _shop_mode:
		col.add_child(body("\"%s\"" % _npc.greeting(), 16, Color(0.92, 0.90, 0.86), true))
		col.add_child(body(" ", 8))
		# quests this NPC is waiting to be handed
		for q: Quests.Quest in (game.quests.ready_for(_npc.role.id) as Array):
			var b := button("Hand in: %s" % q.title, 15)
			b.add_theme_color_override("font_color", Color(0.56, 0.90, 0.58))
			b.pressed.connect(func() -> void:
				game.quests.complete(q)
				_rebuild())
			col.add_child(b)
		for label_action in _npc.options():
			var b := button(String(label_action[0]), 15)
			var action: StringName = label_action[1]
			b.pressed.connect(func() -> void: _dialogue_action(action))
			col.add_child(b)
		col.add_child(body("\"%s\"" % _npc.idle_line(), 13, Color(0.64, 0.62, 0.60)))
		return

	# --- shop
	var head := HBoxContainer.new()
	head.add_child(body("Stock", 14, Color(0.66, 0.62, 0.58)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(body("%d px" % player.inventory.pixels, 16,
		Color(0.98, 0.84, 0.32)))
	col.add_child(head)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)

	var buy := ScrollContainer.new()
	buy.custom_minimum_size = Vector2(376, 360)
	main.add_child(buy)
	var buy_list := VBoxContainer.new()
	buy_list.add_theme_constant_override("separation", 3)
	buy.add_child(buy_list)
	for s: Items.Stack in _npc.stock:
		if s.is_empty():
			continue
		buy_list.add_child(_trade_row(s, _npc.buy_price(s), true))

	var sell := ScrollContainer.new()
	sell.custom_minimum_size = Vector2(376, 360)
	main.add_child(sell)
	var sell_list := VBoxContainer.new()
	sell_list.add_theme_constant_override("separation", 3)
	sell.add_child(sell_list)
	for i in Inventory.ARMOR_START:
		var s := player.inventory.get_slot(i)
		if s.is_empty():
			continue
		var price := _npc.sell_price(s)
		if price <= 0:
			continue
		sell_list.add_child(_trade_row(s, price, false))

	var back := button("Done", 15)
	back.pressed.connect(func() -> void:
		_shop_mode = false
		_rebuild())
	col.add_child(back)


func _trade_row(stack: Items.Stack, price: int, buying: bool) -> Control:
	var row := PanelContainer.new()
	var sb := slot_style(false)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)

	var t := stack.type()
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = t.icon() if t != null else null
	h.add_child(icon)

	var name_label := body("%s x%d" % [stack.display_name(), stack.count], 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.clip_text = true
	h.add_child(name_label)
	h.add_child(body("%d px" % price, 13, Color(0.98, 0.84, 0.32)))

	var b := button("Buy" if buying else "Sell", 12)
	b.custom_minimum_size = Vector2(52, 26)
	if buying:
		b.disabled = player.inventory.pixels < price
		b.pressed.connect(func() -> void:
			game.buy_from(_npc, stack, price)
			_rebuild())
	else:
		b.pressed.connect(func() -> void:
			game.sell_to(_npc, stack, price)
			_rebuild())
	h.add_child(b)

	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(func() -> void:
		show_tooltip(stack, _root.get_global_mouse_position()))
	row.mouse_exited.connect(hide_tooltip)
	return row


func _dialogue_action(action: StringName) -> void:
	match action:
		&"shop":
			_shop_mode = true
			_rebuild()
		&"heal":
			game.npc_heal(_npc)
			_rebuild()
		&"repair":
			game.npc_repair(_npc)
			_rebuild()
		&"quest":
			game.npc_offer_quest(_npc)
			_rebuild()
		&"leave":
			close()


# =============================================================================
# containers
# =============================================================================

func open_container(obj: PlacedObject) -> void:
	_container = obj
	open(&"container", true)


func _build_container() -> void:
	_clear(&"container")
	if _container == null:
		return
	var col := _shell(&"container", 700, 520)
	col.add_child(title(_container.def.display))

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", PAD)
	grid.add_theme_constant_override("v_separation", PAD)
	for i in _container.storage.size():
		grid.add_child(_container_slot(i))
	col.add_child(grid)

	col.add_child(body("Your bag", 13, Color(0.66, 0.62, 0.58)))
	col.add_child(_slot_grid(Inventory.HOTBAR_START, Inventory.HOTBAR_SIZE, 9))
	col.add_child(_slot_grid(Inventory.BACKPACK_START, Inventory.BACKPACK_SIZE, 9))

	var deposit := button("Deposit everything that already matches", 14)
	deposit.pressed.connect(func() -> void:
		game.quick_deposit(_container)
		_rebuild())
	col.add_child(deposit)


func _container_slot(index: int) -> Control:
	var stack := _container.storage[index]
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(SLOT, SLOT)
	pc.add_theme_stylebox_override("panel", slot_style(false))
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	if not stack.is_empty():
		var t := stack.type()
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 5
		icon.offset_top = 5
		icon.offset_right = -5
		icon.offset_bottom = -5
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = t.icon() if t != null else null
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(icon)
		if stack.count > 1:
			var n := Label.new()
			n.text = str(stack.count)
			n.add_theme_font_size_override("font_size", 12)
			n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			n.add_theme_constant_override("outline_size", 4)
			n.position = Vector2(SLOT - 22, SLOT - 22)
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pc.add_child(n)
	pc.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if _held.is_empty():
			_held = _container.storage[index]
			_container.storage[index] = Items.Stack.new()
		else:
			var tmp := _container.storage[index]
			_container.storage[index] = _held
			_held = tmp
		_refresh_held()
		_rebuild())
	pc.mouse_entered.connect(func() -> void:
		show_tooltip(_container.storage[index], _root.get_global_mouse_position()))
	pc.mouse_exited.connect(hide_tooltip)
	return pc
