## The structure-definition record. Content files build these; `StructPlacer`
## consumes them. Kept in its own file so content modules never have to import
## the placer (which imports them).
##
## ### Fields
## | key | meaning |
## |---|---|
## | `id` | stable string key, e.g. `"crashed_shuttle"` |
## | `display` | human name for signs, quests, the map |
## | `class` | placement class: `surface_major`, `dungeon`, `surface_minor`, `underground`, `mini` |
## | `build` | `func(canvas: StructCanvas, ctx: Dictionary) -> void` |
## | `weight` | rarity inside its class (relative weight of the cell roll) |
## | `pad` | max horizontal half-extent, in blocks — drives chunk overlap tests |
## | `up` / `down` | vertical extent above / below the anchor |
## | `biomes` | biome-name substrings that allow this structure (empty = any) |
## | `avoid_biomes` | biome-name substrings that forbid it |
## | `themes` | allowed themes (empty = derive from biome) |
## | `y_mode` | `surface`, `buried`, `absolute`, `sky` |
## | `y_offset` | for `surface`: blocks above ground level |
## | `y_min`/`y_max` | depth below ground (`buried`), world Y (`absolute`), height above ground (`sky`) |
## | `flatness` | max terrain height spread across the footprint (0 = don't care) |
## | `tier` | base loot / monster tier before the depth bonus |
class_name StructDef
extends RefCounted


## Build a definition with every field defaulted, then overridden by `opts`.
static func make(id: String, display: String, klass: StringName, build: Callable,
		opts: Dictionary = {}) -> Dictionary:
	var d := {
		"id": id, "display": display, "class": klass, "build": build,
		"weight": 1.0, "pad": 12, "up": 16, "down": 8,
		"biomes": [], "avoid_biomes": [], "themes": [],
		"y_mode": "surface", "y_offset": 1, "y_min": 0, "y_max": 0,
		"flatness": 4, "tier": 0,
	}
	for k: String in opts:
		d[k] = opts[k]
	return d
