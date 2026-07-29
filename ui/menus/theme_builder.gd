## The entire visual language of Planeshift's UI, expressed in code.
##
## There are no binary assets in this project, so every colour, every panel
## bevel and every icon in the menus originates here. Call [method theme] once
## and assign the result to the root [Control] of a screen; Godot's theme
## inheritance takes care of the rest.
##
## Anything that needs a bitmap ([CheckBox] ticks, slider grabbers, item icons,
## the star field behind the main menu) is rasterised on demand by the
## `*_texture` helpers and cached forever in [member _tex_cache], keyed by its
## parameters. Textures are generated at their *final* display size because the
## project renders canvas items with nearest-neighbour filtering.
class_name MenuTheme
extends RefCounted

# --------------------------------------------------------------------- palette
## Deepest background — behind everything, used by full-screen scrims.
const BG_DEEP := Color(0.039, 0.051, 0.082)
## Standard window body.
const BG_PANEL := Color(0.086, 0.106, 0.157)
## Raised surface: title bars, selected rows, cards.
const BG_PANEL_HI := Color(0.118, 0.141, 0.212)
## Recessed surface: text fields, list wells, slot grids.
const BG_INSET := Color(0.055, 0.071, 0.110)
## An empty inventory slot.
const BG_SLOT := Color(0.078, 0.094, 0.141)
## Hairline borders.
const LINE := Color(0.173, 0.208, 0.286)
## Brighter hairline for hover / emphasis.
const LINE_HI := Color(0.239, 0.290, 0.400)

const TEXT := Color(0.843, 0.867, 0.914)
const TEXT_DIM := Color(0.533, 0.573, 0.651)
const TEXT_MUTE := Color(0.353, 0.388, 0.463)

## Primary brand colour — amber. Selection, focus, headings.
const ACCENT := Color(1.0, 0.702, 0.278)
const ACCENT_DIM := Color(0.620, 0.440, 0.180)
## Secondary — cyan. Energy, tech, space.
const CYAN := Color(0.282, 0.788, 0.910)
const VIOLET := Color(0.663, 0.478, 0.945)

const GOOD := Color(0.373, 0.816, 0.478)
const WARN := Color(1.0, 0.812, 0.302)
const BAD := Color(0.949, 0.373, 0.373)

const SHADOW := Color(0.0, 0.0, 0.0, 0.55)

# ----------------------------------------------------------------------- metrics
const RADIUS := 4
const RADIUS_SM := 3
const PAD := 10
const PAD_SM := 6
const GAP := 8
const SLOT_SIZE := 46
const ICON_SIZE := 34

const FS_TINY := 11
const FS_SMALL := 13
const FS_BODY := 15
const FS_HEAD := 19
const FS_TITLE := 30
const FS_HERO := 58

static var _theme: Theme = null
static var _tex_cache: Dictionary = {}


# ============================================================== public entry point
## The one shared [Theme]. Built lazily, then reused for the life of the process.
static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Assign the shared theme to `c` (and therefore every descendant of `c`).
static func apply(c: Control) -> void:
	if c != null:
		c.theme = theme()


## Colour for a rarity index (see `Const.RARITY_*`). Safe for any integer.
static func rarity_color(r: int) -> Color:
	return Const.RARITY_COLORS[clampi(r, 0, Const.RARITY_COLORS.size() - 1)]


## Human-readable rarity name. Safe for any integer.
static func rarity_name(r: int) -> String:
	return Const.RARITY_NAMES[clampi(r, 0, Const.RARITY_NAMES.size() - 1)]


## Colour used to draw a damage element (matches the combat module's palette).
static func element_color(element: String) -> Color:
	match element:
		Const.ELEM_FIRE: return Color(1.0, 0.45, 0.2)
		Const.ELEM_ICE: return Color(0.55, 0.85, 1.0)
		Const.ELEM_ELECTRIC: return Color(0.95, 0.9, 0.35)
		Const.ELEM_POISON: return Color(0.55, 0.9, 0.35)
		Const.ELEM_COSMIC: return VIOLET
		_: return TEXT_DIM


# ==================================================================== stylebox kit
## Flat fill + hairline border + rounded corners, the base of everything here.
static func box(fill: Color, border: Color = LINE, border_w: int = 1,
		radius: int = RADIUS, pad: int = PAD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_border_width_all(border_w)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(2, pad - 4)
	s.content_margin_bottom = maxi(2, pad - 4)
	return s


## A [method box] with a one-pixel light edge along the top — the subtle bevel
## that makes every surface in the game read as physical rather than flat.
static func bevel(fill: Color, border: Color = LINE, radius: int = RADIUS,
		pad: int = PAD, lit: float = 0.13) -> StyleBoxFlat:
	var s := box(fill, border, 1, radius, pad)
	s.border_width_top = 2
	s.border_color = border.lerp(Color(1, 1, 1, border.a), lit)
	s.bg_color = fill
	# Fake a vertical gradient: Godot's StyleBoxFlat has no gradient, so the
	# top highlight border plus a shadow underneath sells the same idea.
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	return s


## Recessed well — dark fill, dark top border, light bottom border.
static func inset(fill: Color = BG_INSET, radius: int = RADIUS_SM, pad: int = PAD_SM) -> StyleBoxFlat:
	var s := box(fill, LINE.darkened(0.35), 1, radius, pad)
	s.border_width_bottom = 2
	return s


static func flat(fill: Color, radius: int = RADIUS, pad: int = PAD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(2, pad - 4)
	s.content_margin_bottom = maxi(2, pad - 4)
	return s


static func empty(pad: int = 0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


## The outline drawn around a focused control. Deliberately loud: gamepad and
## keyboard users must never lose track of where they are.
static func focus_box(tint: Color = ACCENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(tint.r, tint.g, tint.b, 0.10)
	s.set_border_width_all(2)
	s.border_color = tint
	s.set_corner_radius_all(RADIUS)
	s.content_margin_left = PAD
	s.content_margin_right = PAD
	s.content_margin_top = PAD - 4
	s.content_margin_bottom = PAD - 4
	return s


## Slot background, tinted by rarity when the slot holds something notable.
static func slot_box(rarity: int = -1, hovered: bool = false) -> StyleBoxFlat:
	var border := LINE_HI if hovered else LINE
	var fill := BG_SLOT.lightened(0.06) if hovered else BG_SLOT
	if rarity > Const.RARITY_COMMON:
		var rc := rarity_color(rarity)
		border = rc.lerp(LINE, 0.25)
		fill = fill.lerp(rc, 0.09)
	var s := box(fill, border, 1, RADIUS_SM, 2)
	s.border_width_bottom = 2
	return s


# ======================================================================== builder
static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FS_BODY

	_build_panels(t)
	_build_labels(t)
	_build_buttons(t)
	_build_inputs(t)
	_build_ranges(t)
	_build_tabs(t)
	_build_lists(t)
	_build_misc(t)
	return t


static func _build_panels(t: Theme) -> void:
	var window := bevel(BG_PANEL, LINE_HI, RADIUS + 2, PAD)
	window.shadow_size = 12
	window.shadow_offset = Vector2(0, 6)
	t.set_stylebox(&"panel", &"Panel", window)
	t.set_stylebox(&"panel", &"PanelContainer", window)

	t.set_type_variation(&"WindowPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"WindowPanel", window)

	t.set_type_variation(&"CardPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"CardPanel", bevel(BG_PANEL_HI, LINE, RADIUS, PAD, 0.10))

	t.set_type_variation(&"InsetPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"InsetPanel", inset(BG_INSET, RADIUS, PAD_SM))

	t.set_type_variation(&"HeaderPanel", &"PanelContainer")
	var head := flat(BG_PANEL_HI, RADIUS + 2, PAD)
	head.corner_radius_bottom_left = 0
	head.corner_radius_bottom_right = 0
	head.border_width_bottom = 1
	head.border_color = LINE_HI
	t.set_stylebox(&"panel", &"HeaderPanel", head)

	t.set_type_variation(&"GhostPanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"GhostPanel", empty(0))

	t.set_type_variation(&"TooltipPanelBox", &"PanelContainer")
	var tip := box(Color(0.043, 0.055, 0.086, 0.97), ACCENT_DIM, 1, RADIUS, PAD_SM + 2)
	tip.shadow_color = Color(0, 0, 0, 0.6)
	tip.shadow_size = 8
	t.set_stylebox(&"panel", &"TooltipPanelBox", tip)
	t.set_stylebox(&"panel", &"TooltipPanel", tip)
	t.set_color(&"font_color", &"TooltipLabel", TEXT)


static func _build_labels(t: Theme) -> void:
	t.set_color(&"font_color", &"Label", TEXT)
	t.set_color(&"font_shadow_color", &"Label", Color(0, 0, 0, 0.45))
	t.set_constant(&"shadow_offset_x", &"Label", 1)
	t.set_constant(&"shadow_offset_y", &"Label", 1)
	t.set_stylebox(&"normal", &"Label", empty(0))

	for variation: Array in [
		[&"HeroLabel", FS_HERO, ACCENT],
		[&"TitleLabel", FS_TITLE, TEXT],
		[&"HeadLabel", FS_HEAD, ACCENT],
		[&"SmallLabel", FS_SMALL, TEXT_DIM],
		[&"TinyLabel", FS_TINY, TEXT_MUTE],
		[&"DimLabel", FS_BODY, TEXT_DIM],
		[&"GoodLabel", FS_BODY, GOOD],
		[&"BadLabel", FS_BODY, BAD],
		[&"AccentLabel", FS_BODY, ACCENT],
	]:
		var name: StringName = variation[0]
		var tint: Color = variation[2]
		t.set_type_variation(name, &"Label")
		t.set_font_size(&"font_size", name, int(variation[1]))
		t.set_color(&"font_color", name, tint)

	t.set_color(&"default_color", &"RichTextLabel", TEXT)
	t.set_stylebox(&"normal", &"RichTextLabel", empty(0))
	t.set_stylebox(&"focus", &"RichTextLabel", empty(0))


static func _build_buttons(t: Theme) -> void:
	_button_set(t, &"Button", BG_PANEL_HI, LINE, TEXT, ACCENT)
	t.set_constant(&"h_separation", &"Button", GAP)

	t.set_type_variation(&"AccentButton", &"Button")
	_button_set(t, &"AccentButton", ACCENT_DIM.darkened(0.15), ACCENT, Color(1, 0.95, 0.86), ACCENT)

	t.set_type_variation(&"DangerButton", &"Button")
	_button_set(t, &"DangerButton", Color(0.28, 0.10, 0.11), BAD.darkened(0.2), Color(1, 0.86, 0.86), BAD)

	t.set_type_variation(&"GhostButton", &"Button")
	_button_set(t, &"GhostButton", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), TEXT_DIM, ACCENT)

	t.set_type_variation(&"MenuEntryButton", &"Button")
	_button_set(t, &"MenuEntryButton", Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), TEXT, ACCENT)
	t.set_font_size(&"font_size", &"MenuEntryButton", FS_HEAD)

	t.set_type_variation(&"ListRowButton", &"Button")
	_button_set(t, &"ListRowButton", Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.05), TEXT, ACCENT)
	t.set_font_size(&"font_size", &"ListRowButton", FS_SMALL)

	t.set_type_variation(&"TinyButton", &"Button")
	_button_set(t, &"TinyButton", BG_PANEL_HI, LINE, TEXT_DIM, ACCENT)
	t.set_font_size(&"font_size", &"TinyButton", FS_TINY)

	# Close "X" in every window title bar.
	t.set_type_variation(&"CloseButton", &"Button")
	_button_set(t, &"CloseButton", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), TEXT_DIM, BAD)
	t.set_font_size(&"font_size", &"CloseButton", FS_HEAD)

	# CheckBox / CheckButton reuse Button colours but need generated icons.
	for type: StringName in [&"CheckBox", &"CheckButton"]:
		t.set_stylebox(&"normal", type, empty(PAD_SM))
		t.set_stylebox(&"hover", type, flat(Color(1, 1, 1, 0.04), RADIUS_SM, PAD_SM))
		t.set_stylebox(&"pressed", type, flat(Color(1, 1, 1, 0.06), RADIUS_SM, PAD_SM))
		t.set_stylebox(&"focus", type, focus_box())
		t.set_stylebox(&"disabled", type, empty(PAD_SM))
		t.set_color(&"font_color", type, TEXT)
		t.set_color(&"font_hover_color", type, TEXT)
		t.set_color(&"font_pressed_color", type, ACCENT)
		t.set_color(&"font_disabled_color", type, TEXT_MUTE)
		t.set_constant(&"h_separation", type, GAP)
	t.set_icon(&"checked", &"CheckBox", check_texture(true))
	t.set_icon(&"unchecked", &"CheckBox", check_texture(false))
	t.set_icon(&"checked_disabled", &"CheckBox", check_texture(true, true))
	t.set_icon(&"unchecked_disabled", &"CheckBox", check_texture(false, true))


static func _button_set(t: Theme, type: StringName, fill: Color, border: Color,
		fg: Color, hi: Color) -> void:
	var normal := box(fill, border, 1, RADIUS, PAD + 2)
	normal.border_width_top = 2
	normal.border_color = border.lerp(Color(1, 1, 1, border.a), 0.16)
	t.set_stylebox(&"normal", type, normal)

	var hover := box(fill.lerp(hi, 0.16), hi.lerp(border, 0.35), 1, RADIUS, PAD + 2)
	hover.border_width_top = 2
	t.set_stylebox(&"hover", type, hover)

	var pressed := box(fill.darkened(0.25), hi, 1, RADIUS, PAD + 2)
	pressed.border_width_top = 1
	pressed.border_width_bottom = 2
	pressed.content_margin_top += 1
	pressed.content_margin_bottom -= 1
	t.set_stylebox(&"pressed", type, pressed)

	var disabled := box(fill.darkened(0.45), border.darkened(0.5), 1, RADIUS, PAD + 2)
	t.set_stylebox(&"disabled", type, disabled)
	t.set_stylebox(&"focus", type, focus_box(hi))

	t.set_color(&"font_color", type, fg)
	t.set_color(&"font_hover_color", type, fg.lerp(Color.WHITE, 0.35))
	t.set_color(&"font_pressed_color", type, hi)
	t.set_color(&"font_focus_color", type, fg.lerp(Color.WHITE, 0.25))
	t.set_color(&"font_disabled_color", type, TEXT_MUTE)
	t.set_color(&"font_outline_color", type, Color(0, 0, 0, 0.6))


static func _build_inputs(t: Theme) -> void:
	t.set_stylebox(&"normal", &"LineEdit", inset(BG_INSET, RADIUS_SM, PAD_SM + 2))
	var le_focus := inset(BG_INSET.lightened(0.04), RADIUS_SM, PAD_SM + 2)
	le_focus.border_color = ACCENT
	le_focus.set_border_width_all(1)
	le_focus.border_width_bottom = 2
	t.set_stylebox(&"focus", &"LineEdit", le_focus)
	t.set_stylebox(&"read_only", &"LineEdit", inset(BG_INSET.darkened(0.2), RADIUS_SM, PAD_SM + 2))
	t.set_color(&"font_color", &"LineEdit", TEXT)
	t.set_color(&"font_placeholder_color", &"LineEdit", TEXT_MUTE)
	t.set_color(&"font_uneditable_color", &"LineEdit", TEXT_MUTE)
	t.set_color(&"caret_color", &"LineEdit", ACCENT)
	t.set_color(&"selection_color", &"LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.30))

	t.set_stylebox(&"panel", &"PopupMenu", box(BG_PANEL_HI, LINE_HI, 1, RADIUS, PAD_SM))
	t.set_stylebox(&"hover", &"PopupMenu", flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18), RADIUS_SM, PAD_SM))
	t.set_color(&"font_color", &"PopupMenu", TEXT)
	t.set_color(&"font_hover_color", &"PopupMenu", ACCENT)
	t.set_color(&"font_separator_color", &"PopupMenu", TEXT_MUTE)

	# OptionButton/MenuButton already inherit Button's entries through the class
	# hierarchy; only the dropdown arrow needs replacing.
	t.set_icon(&"arrow", &"OptionButton", arrow_texture())


static func _build_ranges(t: Theme) -> void:
	for type: StringName in [&"HSlider", &"VSlider"]:
		t.set_stylebox(&"slider", type, _track())
		t.set_stylebox(&"grabber_area", type, flat(ACCENT_DIM, 3, 0))
		t.set_stylebox(&"grabber_area_highlight", type, flat(ACCENT, 3, 0))
		t.set_icon(&"grabber", type, grabber_texture(14, ACCENT))
		t.set_icon(&"grabber_highlight", type, grabber_texture(16, Color(1, 0.85, 0.55)))
		t.set_icon(&"grabber_disabled", type, grabber_texture(14, TEXT_MUTE))
		t.set_constant(&"center_grabber", type, 1)

	for type: StringName in [&"HScrollBar", &"VScrollBar"]:
		t.set_stylebox(&"scroll", type, flat(Color(0, 0, 0, 0.25), 3, 0))
		t.set_stylebox(&"scroll_focus", type, flat(Color(0, 0, 0, 0.25), 3, 0))
		t.set_stylebox(&"grabber", type, flat(LINE_HI, 3, 0))
		t.set_stylebox(&"grabber_highlight", type, flat(ACCENT_DIM, 3, 0))
		t.set_stylebox(&"grabber_pressed", type, flat(ACCENT, 3, 0))

	var pb_bg := flat(BG_INSET, RADIUS_SM, 0)
	pb_bg.set_border_width_all(1)
	pb_bg.border_color = LINE.darkened(0.3)
	t.set_stylebox(&"background", &"ProgressBar", pb_bg)
	t.set_stylebox(&"fill", &"ProgressBar", flat(ACCENT_DIM, RADIUS_SM, 0))
	t.set_color(&"font_color", &"ProgressBar", TEXT)
	t.set_font_size(&"font_size", &"ProgressBar", FS_TINY)


static func _track() -> StyleBoxFlat:
	var s := flat(BG_INSET, 3, 0)
	s.set_border_width_all(1)
	s.border_color = LINE.darkened(0.25)
	return s


static func _build_tabs(t: Theme) -> void:
	var sel := flat(BG_PANEL, RADIUS, PAD)
	sel.corner_radius_bottom_left = 0
	sel.corner_radius_bottom_right = 0
	sel.border_width_top = 2
	sel.border_color = ACCENT
	var unsel := flat(Color(1, 1, 1, 0.03), RADIUS, PAD)
	unsel.corner_radius_bottom_left = 0
	unsel.corner_radius_bottom_right = 0
	var hover := flat(Color(1, 1, 1, 0.08), RADIUS, PAD)
	hover.corner_radius_bottom_left = 0
	hover.corner_radius_bottom_right = 0

	for type: StringName in [&"TabBar", &"TabContainer"]:
		t.set_stylebox(&"tab_selected", type, sel)
		t.set_stylebox(&"tab_unselected", type, unsel)
		t.set_stylebox(&"tab_hovered", type, hover)
		t.set_stylebox(&"tab_disabled", type, unsel)
		t.set_stylebox(&"tab_focus", type, focus_box())
		t.set_color(&"font_selected_color", type, ACCENT)
		t.set_color(&"font_unselected_color", type, TEXT_DIM)
		t.set_color(&"font_hovered_color", type, TEXT)
		t.set_constant(&"h_separation", type, 2)
	var body := box(BG_PANEL, LINE, 1, RADIUS, PAD)
	body.corner_radius_top_left = 0
	t.set_stylebox(&"panel", &"TabContainer", body)
	t.set_stylebox(&"tabbar_background", &"TabContainer", empty(0))


static func _build_lists(t: Theme) -> void:
	t.set_stylebox(&"panel", &"ItemList", inset(BG_INSET, RADIUS_SM, PAD_SM))
	t.set_stylebox(&"focus", &"ItemList", focus_box())
	t.set_stylebox(&"selected", &"ItemList", flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), RADIUS_SM, 2))
	t.set_stylebox(&"selected_focus", &"ItemList", flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.24), RADIUS_SM, 2))
	t.set_stylebox(&"hovered", &"ItemList", flat(Color(1, 1, 1, 0.05), RADIUS_SM, 2))
	t.set_stylebox(&"cursor", &"ItemList", focus_box())
	t.set_stylebox(&"cursor_unfocused", &"ItemList", empty(0))
	t.set_color(&"font_color", &"ItemList", TEXT)
	t.set_color(&"font_selected_color", &"ItemList", ACCENT)
	t.set_color(&"guide_color", &"ItemList", Color(1, 1, 1, 0.04))

	t.set_stylebox(&"panel", &"Tree", inset(BG_INSET, RADIUS_SM, PAD_SM))
	t.set_stylebox(&"focus", &"Tree", empty(0))
	t.set_stylebox(&"selected", &"Tree", flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14), RADIUS_SM, 2))
	t.set_stylebox(&"selected_focus", &"Tree", flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22), RADIUS_SM, 2))
	t.set_stylebox(&"cursor", &"Tree", focus_box())
	t.set_stylebox(&"cursor_unfocused", &"Tree", empty(0))
	t.set_color(&"font_color", &"Tree", TEXT_DIM)
	t.set_color(&"font_selected_color", &"Tree", ACCENT)
	t.set_color(&"guide_color", &"Tree", Color(1, 1, 1, 0.04))
	t.set_color(&"relationship_line_color", &"Tree", LINE)
	t.set_constant(&"draw_relationship_lines", &"Tree", 1)
	t.set_constant(&"v_separation", &"Tree", 6)
	t.set_constant(&"item_margin", &"Tree", 14)

	t.set_stylebox(&"panel", &"ScrollContainer", empty(0))


static func _build_misc(t: Theme) -> void:
	t.set_constant(&"separation", &"HBoxContainer", GAP)
	t.set_constant(&"separation", &"VBoxContainer", GAP)
	t.set_constant(&"h_separation", &"GridContainer", 4)
	t.set_constant(&"v_separation", &"GridContainer", 4)
	t.set_stylebox(&"separator", &"HSeparator", _rule())
	t.set_stylebox(&"separator", &"VSeparator", _rule())
	t.set_constant(&"separation", &"HSeparator", 6)
	t.set_constant(&"separation", &"VSeparator", 6)
	t.set_stylebox(&"grabber", &"HSplitContainer", flat(LINE, 2, 0))
	t.set_stylebox(&"grabber", &"VSplitContainer", flat(LINE, 2, 0))


static func _rule() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = LINE
	s.thickness = 1
	return s


# ==================================================================== textures
## Cache-aware texture factory. `key` must fully describe the pixels.
static func _cached(key: String, maker: Callable) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: ImageTexture = maker.call()
	_tex_cache[key] = tex
	return tex


static func _new_image(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## Filled circle used as a slider grabber.
static func grabber_texture(size: int, c: Color) -> ImageTexture:
	return _cached("grab:%d:%s" % [size, c.to_html(true)], func() -> ImageTexture:
		var img := _new_image(size, size)
		var r := float(size) * 0.5
		for y in size:
			for x in size:
				var d := Vector2(x - r + 0.5, y - r + 0.5).length()
				if d <= r - 0.5:
					var lit: float = clampf(1.15 - (y / float(size)) * 0.4, 0.6, 1.2)
					img.set_pixel(x, y, Color(c.r * lit, c.g * lit, c.b * lit, 1.0))
				elif d <= r:
					img.set_pixel(x, y, Color(0, 0, 0, 0.55))
		return ImageTexture.create_from_image(img))


## Small downward triangle for [OptionButton].
static func arrow_texture(size: int = 12, c: Color = TEXT_DIM) -> ImageTexture:
	return _cached("arrow:%d:%s" % [size, c.to_html(true)], func() -> ImageTexture:
		var img := _new_image(size, size)
		for y in size:
			var inset_x := int(round(float(y) * 0.5))
			if y * 2 > size:
				continue
			for x in range(inset_x + 1, size - inset_x - 1):
				img.set_pixel(x, y + int(size * 0.25), c)
		return ImageTexture.create_from_image(img))


## Checkbox tick / empty box.
static func check_texture(checked: bool, disabled: bool = false, size: int = 18) -> ImageTexture:
	var key := "check:%s:%s:%d" % [checked, disabled, size]
	return _cached(key, func() -> ImageTexture:
		var img := _new_image(size, size)
		var frame := LINE_HI if not disabled else LINE.darkened(0.4)
		var fill := BG_INSET
		for y in size:
			for x in size:
				var edge: bool = x < 2 or y < 2 or x >= size - 2 or y >= size - 2
				img.set_pixel(x, y, frame if edge else fill)
		if checked:
			var tick := ACCENT if not disabled else TEXT_MUTE
			# Two strokes forming a check mark.
			for i in range(4, 8):
				for w in 2:
					img.set_pixel(i + w, size - 5 - abs(i - 7), tick)
			for i in range(0, 7):
				for w in 2:
					img.set_pixel(7 + i + w, size - 6 - i, tick)
		return ImageTexture.create_from_image(img))


## A 1x1 white pixel — handy for tinted [TextureRect] fills.
static func white_texture() -> ImageTexture:
	return _cached("white", func() -> ImageTexture:
		var img := _new_image(1, 1)
		img.set_pixel(0, 0, Color.WHITE)
		return ImageTexture.create_from_image(img))


## Radial glow sprite, used for stars and planet halos on the star map.
static func glow_texture(size: int = 64, c: Color = Color.WHITE, power: float = 2.2) -> ImageTexture:
	return _cached("glow:%d:%s:%.2f" % [size, c.to_html(true), power], func() -> ImageTexture:
		var img := _new_image(size, size)
		var r := float(size) * 0.5
		for y in size:
			for x in size:
				var d := Vector2(x - r + 0.5, y - r + 0.5).length() / r
				if d >= 1.0:
					continue
				var a := pow(1.0 - d, power)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
		return ImageTexture.create_from_image(img))


## Deterministic star field. Reused by the main menu and the star map so the
## two screens feel like the same sky.
static func starfield_texture(w: int = 512, h: int = 288, star_seed: int = 1337) -> ImageTexture:
	return _cached("stars:%d:%d:%d" % [w, h, star_seed], func() -> ImageTexture:
		var img := _new_image(w, h)
		var rng := RandomNumberGenerator.new()
		rng.seed = star_seed
		# Faint nebula wash first.
		for y in h:
			for x in w:
				var n := sin(x * 0.021 + star_seed * 0.31) * cos(y * 0.017 - star_seed * 0.11)
				var a: float = clampf(n * 0.5 + 0.5, 0.0, 1.0)
				a = pow(a, 4.0) * 0.22
				img.set_pixel(x, y, Color(0.24, 0.20, 0.45, a))
		var count := int(w * h / 420.0)
		for i in count:
			var x := rng.randi_range(0, w - 1)
			var y := rng.randi_range(0, h - 1)
			var b := rng.randf_range(0.35, 1.0)
			var tint := Color(1, 1, 1).lerp(
				Color(0.7, 0.8, 1.0) if rng.randf() < 0.5 else Color(1.0, 0.85, 0.7),
				rng.randf() * 0.7)
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, b))
			if b > 0.85:
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var px := x + o.x
					var py := y + o.y
					if px >= 0 and py >= 0 and px < w and py < h:
						img.set_pixel(px, py, Color(tint.r, tint.g, tint.b, b * 0.35))
		return ImageTexture.create_from_image(img))


## Faint diagonal hatch used behind empty lists so they do not read as broken.
static func hatch_texture(size: int = 16, c: Color = Color(1, 1, 1, 0.028)) -> ImageTexture:
	return _cached("hatch:%d:%s" % [size, c.to_html(true)], func() -> ImageTexture:
		var img := _new_image(size, size)
		for y in size:
			for x in size:
				if (x + y) % 8 < 2:
					img.set_pixel(x, y, c)
		return ImageTexture.create_from_image(img))


# ------------------------------------------------------------------ item icons
## The icon for an [ItemStack]. Falls back through instance data -> [ItemType]
## -> a neutral grey square, so it renders something for every possible stack.
static func stack_icon(stack: ItemStack, size: int = ICON_SIZE) -> ImageTexture:
	if stack == null or stack.is_empty():
		return null
	var c := Color(0.7, 0.7, 0.7)
	var shape := &"square"
	if stack.data.has("icon_color"):
		c = stack.data["icon_color"]
	if stack.data.has("icon_shape"):
		shape = StringName(stack.data["icon_shape"])
	else:
		var ty := stack.type()
		if ty != null:
			c = ty.icon_color
			shape = ty.icon_shape
	return item_icon(c, shape, size)


## Rasterise one procedural item icon: a filled shape with a soft top-light
## bevel and a dark one-pixel outline.
static func item_icon(c: Color, shape: StringName, size: int = ICON_SIZE) -> ImageTexture:
	var key := "icon:%s:%s:%d" % [c.to_html(true), shape, size]
	return _cached(key, func() -> ImageTexture:
		var img := _new_image(size, size)
		var mask := PackedFloat32Array()
		mask.resize(size * size)
		for y in size:
			for x in size:
				var u := (x + 0.5) / size * 2.0 - 1.0
				var v := (y + 0.5) / size * 2.0 - 1.0
				mask[y * size + x] = 1.0 if _shape_hit(shape, u, v) else 0.0
		var outline := c.darkened(0.72)
		for y in size:
			for x in size:
				var i := y * size + x
				if mask[i] <= 0.0:
					continue
				if _is_edge(mask, size, x, y):
					img.set_pixel(x, y, Color(outline.r, outline.g, outline.b, 1.0))
					continue
				var v := (y + 0.5) / size
				var lit: float = clampf(1.30 - v * 0.62, 0.55, 1.35)
				img.set_pixel(x, y, Color(
					minf(c.r * lit, 1.0), minf(c.g * lit, 1.0), minf(c.b * lit, 1.0), 1.0))
		return ImageTexture.create_from_image(img))


static func _is_edge(mask: PackedFloat32Array, size: int, x: int, y: int) -> bool:
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var px := x + o.x
		var py := y + o.y
		if px < 0 or py < 0 or px >= size or py >= size:
			return true
		if mask[py * size + px] <= 0.0:
			return true
	return false


## Membership test for a procedural icon silhouette. `u`,`v` are in -1..1 with
## `v` growing downward. Unknown shapes degrade to a rounded square.
static func _shape_hit(shape: StringName, u: float, v: float) -> bool:
	match shape:
		&"circle", &"orb", &"ball":
			return Vector2(u, v).length() < 0.80
		&"diamond", &"crystal":
			return absf(u) + absf(v) < 0.94
		&"triangle":
			var t := (v + 0.78) / 1.5
			return v > -0.78 and v < 0.72 and absf(u) < 0.82 * t
		&"star":
			var theta := atan2(v, u)
			var lim := 0.34 + 0.50 * absf(cos(2.5 * theta))
			return Vector2(u, v).length() < lim
		&"gem":
			return absf(v) < 0.80 and absf(u) < 0.72 - 0.30 * absf(v)
		&"ingot", &"bar":
			return absf(v) < 0.42 and absf(u) < 0.82 - 0.26 * (v + 0.42)
		&"sword", &"blade":
			if absf(u) < 0.14 and v > -0.88 and v < 0.34:
				return true
			if absf(v - 0.40) < 0.09 and absf(u) < 0.46:
				return true
			return absf(u) < 0.10 and v >= 0.40 and v < 0.84
		&"pickaxe", &"pick", &"tool":
			if absf(u) < 0.11 and v > -0.30 and v < 0.86:
				return true
			var d := Vector2(u, (v + 0.55) * 1.15).length()
			return d > 0.58 and d < 0.80 and v < -0.05
		&"leaf", &"plant", &"seed":
			var rot := Vector2(u, v).rotated(-PI * 0.25)
			return (rot.x * rot.x) / 0.16 + (rot.y * rot.y) / 0.72 < 1.0
		&"potion", &"flask":
			if absf(u) < 0.16 and v < -0.35 and v > -0.85:
				return true
			return Vector2(u, v - 0.22).length() < 0.58
		&"coin", &"currency":
			var r := Vector2(u, v).length()
			return r < 0.80 and r > 0.16
		&"cube", &"block":
			return absf(u) < 0.78 and absf(v) < 0.78
		&"bolt", &"tech", &"chip":
			return absf(u) < 0.68 and absf(v) < 0.68 and not (absf(u) > 0.34 and absf(v) > 0.34)
		_:
			# Rounded square, the neutral default.
			return absf(u) < 0.76 and absf(v) < 0.76 and (absf(u) - 0.56) + (absf(v) - 0.56) < 0.22
