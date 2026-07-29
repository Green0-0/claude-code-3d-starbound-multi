## Definition of one kind of voxel. Built with the fluent setters so content
## files read like data, then handed to `Blocks.register()`.
class_name BlockType
extends RefCounted

enum Render {
	CUBE,        ## normal opaque cube
	TRANSPARENT, ## cube that renders with alpha and does not cull neighbours
	CROSS,       ## two crossed quads (grass tufts, saplings, flowers)
	LIQUID,      ## surface-shifted cube driven by the liquid sim
	NONE,        ## invisible (air, markers)
}

## Procedural texture patterns; the atlas builder turns these into pixels so the
## project needs no binary image assets.
enum Pattern {
	FLAT, NOISE, SPECKLE, STRATA, BRICK, PLANK, ORE, CRYSTAL, GRASS_TOP,
	METAL, CIRCUIT, ORGANIC, CLOTH, GLASS, SAND, ICE, LEAF, LOG,
}

var id: int = -1                       ## assigned by the registry
var name: StringName = &""             ## stable string key, e.g. &"stone"
var display_name: String = "Block"
var description: String = ""

var render: Render = Render.CUBE
var pattern: Pattern = Pattern.NOISE
var color: Color = Color(0.5, 0.5, 0.5)
var color_alt: Color = Color(0.4, 0.4, 0.4)   ## secondary pattern colour
var top_color: Color = Color(0, 0, 0, 0)      ## if alpha>0, used for +Y face
var emission: float = 0.0                     ## 0..1 self-illumination strength

var solid: bool = true          ## blocks movement
var opaque: bool = true         ## blocks light and culls neighbour faces
var replaceable: bool = false   ## placing another block overwrites it
var climbable: bool = false     ## ladders, vines
var platform: bool = false      ## one-way floor you can jump through
var liquid: bool = false
var falls: bool = false         ## sand-like gravity affected
var flammable: bool = false
var breakable: bool = true

var light: int = 0              ## 0..15 emitted light level
var hardness: float = 1.0       ## seconds of mining at tool power 1.0
var tool: StringName = &"any"   ## &"pickaxe", &"axe", &"shovel", &"any"
var tool_tier: int = 0          ## minimum tier required to yield drops
var blast_resistance: float = 1.0
var friction: float = 1.0       ## multiplies ground movement speed
var bounce: float = 0.0
var damage_on_touch: float = 0.0
var damage_element: String = Const.ELEM_PHYSICAL

var drops: Array = []           ## [{"item": StringName, "min": int, "max": int, "chance": float}]
var step_sound: StringName = &"step_stone"
var break_sound: StringName = &"break_stone"
var place_sound: StringName = &"place_stone"
var category: StringName = &"natural"
var tags: Array[StringName] = []

## Optional callables installed by gameplay modules; all are `null` by default.
## on_interact(pos: Vector3i, player: Node) -> bool
var on_interact: Callable = Callable()
## on_random_tick(pos: Vector3i) -> void  (crops, grass spread, fire)
var on_random_tick: Callable = Callable()
## on_neighbour_changed(pos: Vector3i, from: Vector3i) -> void
var on_neighbour_changed: Callable = Callable()
## on_entity_inside(pos: Vector3i, entity: Node, delta: float) -> void
var on_entity_inside: Callable = Callable()


func _init(p_name: StringName, p_display: String = "") -> void:
	name = p_name
	display_name = p_display if p_display != "" else String(p_name).capitalize()


# ---------------------------------------------------------------- fluent API
func look(p_color: Color, p_pattern: Pattern = Pattern.NOISE, p_alt: Color = Color(0, 0, 0, 0)) -> BlockType:
	color = p_color
	pattern = p_pattern
	color_alt = p_alt if p_alt.a > 0.0 else p_color.darkened(0.25)
	return self


func with_top(p_color: Color) -> BlockType:
	top_color = p_color
	return self


func mode(p_render: Render) -> BlockType:
	render = p_render
	if p_render == Render.TRANSPARENT or p_render == Render.CROSS or p_render == Render.NONE:
		opaque = false
	if p_render == Render.CROSS or p_render == Render.NONE:
		solid = false
	if p_render == Render.LIQUID:
		liquid = true
		solid = false
		opaque = false
	return self


func mining(p_hardness: float, p_tool: StringName = &"any", p_tier: int = 0) -> BlockType:
	hardness = p_hardness
	tool = p_tool
	tool_tier = p_tier
	blast_resistance = p_hardness
	return self


func glows(level: int, p_emission: float = 1.0) -> BlockType:
	light = clampi(level, 0, Const.MAX_LIGHT)
	emission = p_emission
	return self


func drop(item: StringName, min_count: int = 1, max_count: int = 1, chance: float = 1.0) -> BlockType:
	drops.append({"item": item, "min": min_count, "max": max_count, "chance": chance})
	return self


func sounds(step: StringName, brk: StringName = &"", place: StringName = &"") -> BlockType:
	step_sound = step
	break_sound = brk if brk != &"" else step
	place_sound = place if place != &"" else step
	return self


func flags(p: Dictionary) -> BlockType:
	for k: String in p:
		if k in self:
			set(k, p[k])
		else:
			push_warning("BlockType '%s': unknown flag '%s'" % [name, k])
	return self


func tag(t: StringName) -> BlockType:
	if not tags.has(t):
		tags.append(t)
	return self


func in_category(c: StringName) -> BlockType:
	category = c
	return self


func has_tag(t: StringName) -> bool:
	return tags.has(t)


## Items actually produced by breaking this block with `tier`.
func roll_drops(tier: int, rng: RandomNumberGenerator = null) -> Array:
	if tier < tool_tier:
		return []
	var out: Array = []
	for d: Dictionary in drops:
		var chance: float = d.get("chance", 1.0)
		var roll: float = rng.randf() if rng != null else randf()
		if roll > chance:
			continue
		var lo: int = d.get("min", 1)
		var hi: int = d.get("max", lo)
		var n: int = lo if hi <= lo else (rng.randi_range(lo, hi) if rng != null else randi_range(lo, hi))
		if n > 0:
			out.append({"item": d["item"], "count": n})
	return out
