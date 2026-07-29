## Host for every window in the game. Instanced by `main.tscn` as the `Menus`
## CanvasLayer, it owns nothing except a full-rect [Control] that [UI] parents
## panels into, and it registers itself with [UI] on entering the tree.
##
## Keeping the host this thin means the panel stack survives scene reloads: if
## `Menus` disappears, [UI] falls back to a private canvas layer and migrates
## the panels back the next time a host attaches.
extends CanvasLayer

## Draw order. The HUD lives on layer 1; menus must always sit above it, and
## the tooltip/drag overlay owned by [UI] sits above both on layer 128.
const MENU_LAYER := 10

var panels: Control = null


func _ready() -> void:
	layer = MENU_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	follow_viewport_enabled = false

	panels = Control.new()
	panels.name = "Panels"
	panels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE, not STOP: an empty menu layer must not eat clicks meant for the
	# world. Individual modal panels raise their own scrim to block input.
	panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panels.process_mode = Node.PROCESS_MODE_ALWAYS
	MenuTheme.apply(panels)
	add_child(panels)

	if UI.has_method(&"attach_host"):
		UI.attach_host(self, panels)


func _exit_tree() -> void:
	if UI.has_method(&"attach_host") and UI.get(&"_panel_layer") == panels:
		UI.set(&"_panel_layer", null)
		UI.set(&"_host", null)
