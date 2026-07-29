## The trading window, and the blacksmith's upgrade bench.
##
## `ui/ui_manager.gd` lists "shop" under FUTURE_PANELS with the note *"Trading
## belongs to the NPC module"*, so this panel lives here and registers itself
## through [method UI.register_panel] (see `quests/quest_manager.gd::_boot`). It
## borrows the menus agent's [MenuPanel] chrome and [MenuWidgets] so it looks
## like every other window in the game.
##
## Opened by the dialogue effects `{"type": "open_shop"}` and
## `{"type": "open_upgrade"}`; context is
## `{"npc": NpcBase, "mode": "shop"|"upgrade", "stock": Array}`.
extends MenuPanel

const MODE_SHOP := "shop"
const MODE_UPGRADE := "upgrade"

var _npc: Node = null
var _mode: String = MODE_SHOP
var _balance_label: Label = null
var _list: VBoxContainer = null
var _tab: int = 0     ## 0 = buy, 1 = sell


func _configure() -> void:
	modal = true
	captures = true
	pauses = false
	dim = 0.25
	placement = "center"
	anim = "scale"
	esc_closes = true


func _on_open(context: Dictionary) -> void:
	ctx = context
	rebuild()


func _build() -> void:
	_npc = ctx.get("npc") as Node
	_mode = String(ctx.get("mode", panel_id if panel_id != "" else MODE_SHOP))
	if _mode != MODE_UPGRADE:
		_mode = MODE_SHOP

	var body := frame(_title(), Vector2(660, 460))

	var head := MenuWidgets.row()
	_balance_label = MenuWidgets.label("", &"HeadLabel")
	head.add_child(_balance_label)
	head.add_child(MenuWidgets.spacer())
	if _mode == MODE_SHOP:
		head.add_child(MenuWidgets.tab_strip(PackedStringArray(["Buy", "Sell"]),
			Callable(self, "_on_tab")))
	body.add_child(head)
	body.add_child(MenuWidgets.rule())

	_list = MenuWidgets.col(3)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(MenuWidgets.scroll(_list))

	if not Events.currency_changed.is_connected(_on_currency):
		Events.currency_changed.connect(_on_currency)
	if not Events.inventory_changed.is_connected(_on_inventory):
		Events.inventory_changed.connect(_on_inventory)
	_fill()


func _title() -> String:
	var what := "Upgrade Bench" if _mode == MODE_UPGRADE else "Trade"
	if _npc != null:
		var n: Variant = _npc.get("display_name")
		if n != null and String(n) != "":
			return "%s — %s" % [String(n), what]
	return what


func _on_close() -> void:
	if Events.currency_changed.is_connected(_on_currency):
		Events.currency_changed.disconnect(_on_currency)
	if Events.inventory_changed.is_connected(_on_inventory):
		Events.inventory_changed.disconnect(_on_inventory)


func _on_tab(index: int) -> void:
	_tab = index
	_fill()


func _on_currency(_amount: int) -> void:
	_refresh_balance()


func _on_inventory() -> void:
	if is_inside_tree():
		_fill()


func _refresh_balance() -> void:
	if _balance_label != null:
		_balance_label.text = "%d px" % NpcInventoryBridge.pixels()


# =========================================================================
func _fill() -> void:
	if _list == null:
		return
	MenuWidgets.clear(_list)
	_refresh_balance()
	if _mode == MODE_UPGRADE:
		_fill_upgrade()
	elif _tab == 0:
		_fill_buy()
	else:
		_fill_sell()


func _fill_buy() -> void:
	var stock: Array = ctx.get("stock", []) as Array
	if stock.is_empty() and _npc != null and _npc.has_method(&"shop_stock"):
		stock = _npc.call(&"shop_stock") as Array
	var npc_id := _npc_id()
	var any := false
	for entry: Variant in stock:
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		var id := StringName(row.get("id", ""))
		var left := int(row.get("count", 0))
		if left <= 0 or not Items.has(id):
			continue
		any = true
		var price := int(row.get("price", NpcShop.price_to_buy(npc_id, id)))
		_list.add_child(_trade_row(Items.display_name(id),
			"%d px   (%d in stock)" % [price, left], "Buy",
			NpcInventoryBridge.pixels() >= price,
			Callable(self, "_do_buy").bind(id)))
	if not any:
		_list.add_child(MenuWidgets.placeholder("Nothing for sale today."))


func _fill_sell() -> void:
	var inv := NpcInventoryBridge.inventory()
	if inv == null or not inv.has_method(&"contents"):
		_list.add_child(MenuWidgets.placeholder("Nothing in your pack they want."))
		return
	var npc_id := _npc_id()
	var contents: Dictionary = inv.call(&"contents")
	var any := false
	for k: Variant in contents:
		var id := StringName(k)
		var held := int(contents[k])
		var it := Items.get_type(id)
		if it == null or held <= 0 or it.value <= 0:
			continue
		any = true
		var price := NpcShop.price_to_sell(npc_id, id)
		_list.add_child(_trade_row(it.display_name,
			"%d px each   (you have %d)" % [price, held], "Sell", true,
			Callable(self, "_do_sell").bind(id)))
	if not any:
		_list.add_child(MenuWidgets.placeholder("Nothing in your pack they want."))


func _fill_upgrade() -> void:
	var inv := NpcInventoryBridge.inventory()
	if inv == null or not inv.has_method(&"all_stacks"):
		_list.add_child(MenuWidgets.placeholder("Nothing on the anvil."))
		return
	var mat := NpcRoleBlacksmith.upgrade_material()
	var mat_name := Items.display_name(mat) if mat != &"" else "scrap"
	_list.add_child(MenuWidgets.dim(
		"Paid in pixels and %s. Five improvements per piece." % mat_name))
	var any := false
	for s: Variant in inv.call(&"all_stacks"):
		var stack := s as ItemStack
		if stack == null or stack.is_empty():
			continue
		var t := stack.type()
		if t == null:
			continue
		if t.kind != ItemType.Kind.WEAPON and t.kind != ItemType.Kind.TOOL \
				and t.kind != ItemType.Kind.ARMOR:
			continue
		any = true
		var level := NpcRoleBlacksmith.level_of(stack)
		var cost := NpcRoleBlacksmith.upgrade_cost(level)
		var mat_cost := NpcRoleBlacksmith.upgrade_material_cost(level)
		var detail := "Maxed out"
		var affordable := false
		if level < 5:
			detail = "+%d → +%d    %d px" % [level, level + 1, cost]
			if mat != &"":
				detail += " + %d %s" % [mat_cost, mat_name]
			affordable = NpcInventoryBridge.pixels() >= cost \
				and (mat == &"" or NpcInventoryBridge.count_of(mat) >= mat_cost)
		_list.add_child(_trade_row(stack.display_name(), detail, "Forge", affordable,
			Callable(self, "_do_upgrade").bind(stack)))
	if not any:
		_list.add_child(MenuWidgets.placeholder("Bring me a tool, a blade or a plate."))


# ------------------------------------------------------------------ actions
func _do_buy(id: StringName) -> void:
	if NpcShop.buy(_npc, id, 1):
		_fill()


func _do_sell(id: StringName) -> void:
	if NpcShop.sell(_npc, id, 1):
		_fill()


func _do_upgrade(stack: ItemStack) -> void:
	if NpcRoleBlacksmith.upgrade(_npc, stack):
		_fill()


# =========================================================================
func _trade_row(name_text: String, detail: String, verb: String,
		enabled: bool, on_press: Callable) -> Control:
	var row := MenuWidgets.row()
	var col := MenuWidgets.col(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(MenuWidgets.label(name_text))
	col.add_child(MenuWidgets.dim(detail))
	row.add_child(col)
	var b := MenuWidgets.small_button(verb, on_press)
	b.disabled = not enabled
	row.add_child(b)
	return MenuWidgets.well(row)


func _npc_id() -> StringName:
	if _npc == null:
		return &""
	return StringName(_npc.get("npc_id"))
