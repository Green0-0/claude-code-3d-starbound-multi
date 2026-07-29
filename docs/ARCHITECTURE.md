# Planeshift — Architecture Contract

**Read this file completely before writing any code.** Twenty agents build this
project in parallel. The core below is already written, tested and frozen. Your
job is to fill in *your* directory without touching anyone else's.

---

## 1. The concept

Starbound's gameplay (procedural planets, mining, crafting, combat, quests,
space travel) on a **Minecraft-style 3D voxel world**.

The twist: the player always sees a **2D orthographic side view**, like Paper
Mario — a flat sprite in a 3D world, camera locked to one of four horizontal
planes. Two distinct player actions manipulate this:

| Action | Key | What it does |
|---|---|---|
| **Flip** | `Q` / `E` | Rotate the camera 90° to another of the four viewing planes. The player does **not** move; the world re-reveals itself along a new axis. What was a wall is now a corridor. |
| **Shift** | `PgUp` / `PgDn` | Step one voxel layer deeper into / out of the screen along the current depth axis. This is real traversal and **can be blocked** by solid voxels. |

Because the world is genuinely 3D, Starbound's foreground/background tile duality
becomes literal: the "background" is simply the layers behind you, rendered
dimmer, and you can walk into them.

## 2. Coordinate model — learn this first

The world is a right-handed 3D voxel grid. `+Y` is up, always.

Four views, indexed `0..3`, each a 90° yaw step:

| view | camera looks along | screen-right axis | depth axis | name |
|---|---|---|---|---|
| 0 | `(0,0,-1)` | `+X` | Z | North |
| 1 | `(-1,0,0)` | `-Z` | X | West |
| 2 | `(0,0,+1)` | `-X` | Z | South |
| 3 | `(+1,0,0)` | `+Z` | X | East |

Two coordinate spaces:

- **World space** — real `Vector3`. Voxels, physics, rendering.
- **Plane space** — `Vector2(lateral, up)`. `lateral` is screen-right,
  `up` is world `+Y`. **All gameplay logic that would be "horizontal" in a 2D
  platformer must be written in plane space** so it works identically in all
  four views.

Convert with `View.to_plane(world_pos)` / `View.to_world(plane_pos, depth)`,
or the pure helpers `Const.lateral_of()` / `Const.from_plane()`.

Never hard-code `.x` as "horizontal". That is the single most common way to
break this project.

## 3. Directory ownership

**You may only create or edit files inside your assigned directory.** If you
need something from another module, call it through the documented API or the
`Events` signal bus. Never edit `core/`, `project.godot`, or `main.tscn`.

```
core/          FROZEN — read it, never write it
docs/          FROZEN
render/        chunk meshing, texture atlas, voxel shader
worldgen/      terrain, biomes, caves, ores, structures
player/        player actor, animation, paper-doll rendering
camera/        orthographic rig, flip animation, screen effects
inventory/     inventory model, hotbar, item drops, containers
crafting/      recipes, stations, crafting UI logic
combat/        weapons, projectiles, damage pipeline
entities/      monsters, AI, NPCs, spawning
quests/        quest definitions, dialogue trees
sim/liquids/   water/lava flow, falling blocks
sim/lighting/  light propagation, day/night
space/         universe generation, ship, star map, teleporters
fx/            audio synthesis, particles, screen shake
persistence/   save/load, chunk paging
survival/      hunger, temperature, oxygen, status effects, farming
tech/          techs, tools, matter manipulator, interaction
objects/       placeable machines, furniture, containers, doors
ui/hud/        in-game HUD
ui/menus/      menus, dialogs, star map UI, inventory windows
content/blocks block definitions
content/items  item definitions
```

## 4. Frozen core API

### `Const` (static, `core/constants.gd`)
```
CHUNK_SIZE=16  CHUNK_VOL=4096  WORLD_HEIGHT=256  AIR=0  MAX_LIGHT=15
GRAVITY=34.0   TICKS_PER_DAY=28800  MAX_LIQUID=8
VIEW_FORWARD[4] VIEW_RIGHT[4] VIEW_DEPTH_AXIS[4] VIEW_DEPTH_SIGN[4] VIEW_NAMES[4]
SLAB_BEHIND=12 SLAB_FRONT=0
ELEM_PHYSICAL/FIRE/ICE/ELECTRIC/POISON/COSMIC, ELEMENTS[]
RARITY_COMMON..ESSENTIAL, RARITY_COLORS[], RARITY_NAMES[]
FACE_PX..FACE_NZ (0..5), FACE_NORMALS[6]
static chunk_of(p) local_of(p) local_index(x,y,z) floor_v(v)
static depth_of(v,view) lateral_of(v,view) from_plane(lat,up,depth,view)
```

### `View` (autoload, `core/perspective.gd`) — the mechanic
```
view:int  layer:int  flipping:bool  shifting:bool  flip_t:float  flips_enabled:bool
forward() right() depth_axis() depth_sign() view_name()
current_yaw() camera_basis() flip_eased()
to_plane(world)->Vector2   to_world(plane, depth)->Vector3
depth_of(world)->float     lateral_of(world)->float
with_depth(v, d)->Vector3  plane_dir_to_world(Vector2)->Vector3  depth_step()->Vector3i
request_flip(dir)->bool    flip_to_view(v)->bool
request_shift(dir)->bool   set_layer(l)
is_play_layer(Vector3i)->bool   layer_offset(Vector3i)->int
shader_params()->Dictionary     save_state()/load_state()
```
`main.gd` already calls `advance_flip`/`advance_shift` every frame. Do not.

### `World` (autoload, `core/voxel_world.gd`)
```
planet_id size_x size_z seed_value ready_flag chunks:Dictionary
create_world(id, seed, meta)   unload_world()
get_block(Vector3i)->int       get_block_xyz(x,y,z)->int
set_block(Vector3i, id, notify=true)->bool
is_solid/is_air/is_opaque(Vector3i)->bool   block_type_at(p)->BlockType
break_block(p, tier=99, drops=true)->Array  place_block(p, id)->bool
get_chunk(cpos)->Chunk  has_chunk(cpos)  chunk_at_block(p)  mark_dirty(cpos)
request_chunk(cpos)     loaded_chunk_positions()->Array
normalize(p) wrap_x(x) wrap_z(z) in_bounds_y(y)
surface_y(x,z,from_y)->int
raycast(from, dir, max_dist, want_liquid=false)
    -> {hit, pos:Vector3i, normal:Vector3i, distance}
explode(center, radius, power)
```
Planets **wrap** on X and Z. Always go through `World.normalize()`.

### `Chunk` (`core/chunk.gd`)
```
cpos  blocks:PackedInt32Array(4096)  light:PackedByteArray  liquid:PackedByteArray
generated populated lit dirty empty solid_count  tile_data:Dictionary(index->Dict)
static index(lx,ly,lz)->int   # (y<<8)|(z<<4)|x   -- used EVERYWHERE
static index_of(Vector3i)  static from_index(i)->Vector3i
origin()->Vector3i  get_local/set_local  get_at(i)/set_at(i,id)  recount()
sky_light(i) block_light(i) set_sky_light(i,v) set_block_light(i,v)
combined_light(i, daylight)  liquid_at(i) set_liquid(i,v)
get_tile_data(i)/set_tile_data(i,d)   to_dict()/from_dict()
```

### `VoxelPhysics` (static, `core/voxel_physics.gd`)
```
aabb_is_free(pos, size, ignore_platforms=true)->bool
overlapping_blocks(pos, size)->Array[Vector3i]
move(pos, size, motion, opts)->{position, on_floor, on_ceiling, on_wall,
                                hit_x, hit_y, hit_z, stepped, floor_block}
    opts: {drop_through:bool, auto_step:bool}
unstick(pos, size, max_push=4)->Vector3
ground_below(pos, max_drop)->float      liquid_submersion(pos, size)->float
```
Entity position is the **bottom-centre** of the AABB (`position.y` = feet).

### `VoxelEntity` (`core/voxel_entity.gd`, extends `Node3D`)
Base for player, monsters, NPCs, drops.
```
exports: box_size max_health gravity_scale move_speed jump_speed faction
         invulnerable affected_by_liquid
state:   health velocity on_floor on_ceiling on_wall facing dead submersion
         iframes knockback_lock drop_through
integrate(delta)          # call from _physics_process, after setting velocity
plane_velocity()->float   set_plane_velocity(lateral)
plane_position()->Vector2 face_toward(world_pos)  in_same_layer(node)->bool
jump(strength=-1)  teleport(dest)  begin_layer_shift(dest)  is_shifting()
apply_damage(amount, element, source)->float      modify_incoming_damage(...)  # override
heal(a)  knockback(dir, strength)  die(source)  on_death(source)  # override
save_state()/load_state()
signals: died(entity) damaged(amount, element, source) landed(fall_distance)
```

### `Blocks` (autoload) / `BlockType` (`core/block_type.gd`)
```
Blocks.define(&"name","Display")->BlockType     # register + return
Blocks.id(&"name")->int    Blocks.has(&"name")  Blocks.get_type(id)->BlockType
Blocks.get_by_name(&"n")   Blocks.count()
Blocks.all_with_tag(&"t")  Blocks.all_in_category(&"c")
hot LUTs: is_solid(id) is_opaque(id) is_liquid(id) is_platform(id)
          is_climbable(id) is_replaceable(id) light_of(id)
```
`BlockType` fluent builders: `.look(color, Pattern, alt)` `.with_top(c)`
`.mode(Render)` `.mining(hardness, tool, tier)` `.glows(level, emission)`
`.drop(item, min, max, chance)` `.sounds(step, brk, place)` `.flags({...})`
`.tag(&"t")` `.in_category(&"c")` ; `roll_drops(tier, rng)->Array`.
Fields: solid opaque replaceable climbable platform liquid falls flammable
breakable light hardness tool tool_tier blast_resistance friction bounce
damage_on_touch damage_element color color_alt top_color emission pattern render.
Hooks (Callable, default invalid): `on_interact(pos, player)->bool`,
`on_random_tick(pos)`, `on_neighbour_changed(pos, from)`,
`on_entity_inside(pos, entity, delta)`.
`Render`: CUBE TRANSPARENT CROSS LIQUID NONE.
`Pattern`: FLAT NOISE SPECKLE STRATA BRICK PLANK ORE CRYSTAL GRASS_TOP METAL
CIRCUIT ORGANIC CLOTH GLASS SAND ICE LEAF LOG.

Content files: `res://content/blocks/NN_name.gd`, `extends RefCounted`, with
`static func register_all(reg) -> void`. Loaded automatically in filename order.

### `Items` (autoload) / `ItemType` / `ItemStack`
```
Items.define(&"id","Display")->ItemType   Items.get_type(&"id")  Items.has(&"id")
Items.make(&"id", count)->ItemStack       # adds durability for tools/weapons
Items.all_of_kind(ItemType.Kind.X)  Items.all_with_tag(&"t")  Items.all_in_category(&"c")
```
Any block without an explicit item automatically gets a placer item with the
same StringName. `ItemType.Kind`: MATERIAL BLOCK TOOL WEAPON ARMOR CONSUMABLE
OBJECT TECH SEED AUGMENT QUEST CURRENCY.
Builders: `.of_kind()` `.look(color, shape)` `.describe()` `.worth(v, rarity)`
`.stacks(n)` `.places(&"block")` `.as_tool(kind, tier, power, range)`
`.as_weapon(dmg, speed, elem)` `.as_armor(slot, def)` `.as_food(f, heal)`
`.with_effect(id, dur)` `.bonus(stat, amt)` `.tag()` `.in_category()` `.flags({})`.
`ItemStack`: `id count data` ; `is_empty() type() max_stack() can_merge_with()
merge_from() split(n) clear() duplicate_stack() display_name() rarity()
stat(key, fallback) durability() damage_durability(n)->bool to_dict()/from_dict()`.

Item content files: `res://content/items/NN_name.gd` with
`static func register_all(reg) -> void`.

### `Game` (autoload, `core/game.gd`)
```
main player entities_root fx_root world_renderer camera_rig
paused in_menu debug_overlay difficulty run_seed
tick day day_fraction daylight time_scale   is_night() time_string()
stats:Dictionary  bump_stat(key, amount)
entity_occupies(Vector3i)->bool
spawn_item_drop(pos, item_id, count, data)->Node
spawn_entity(scene_path, pos, setup)->Node
nearest_entity(pos, max_dist, group, same_layer)->VoxelEntity
entities_in_radius(pos, radius, group)->Array[VoxelEntity]
start_new_game(seed)  travel_to_planet(id)  set_paused(v)
save_state()/load_state()
```

### `Events` (autoload, `core/events.gd`)
The signal bus — read `core/events.gd` for the full list. Highlights:
`block_changed(pos, old, new)`, `chunk_loaded/unloaded/dirty(cpos)`,
`view_flip_started(from,to,dir)`, `view_flip_finished(view)`,
`layer_changed(layer,view)`, `flip_blocked(reason)`,
`player_spawned/died/damaged`, `stat_changed(stat,value,max)`,
`inventory_changed()`, `hotbar_selection_changed(i)`, `item_picked_up`,
`entity_damaged/died`, `damage_number(pos,amount,elem,crit)`,
`quest_*`, `dialogue_started/ended`, `travel_started/finished`,
`notify(text,kind)`, `screen_shake(strength,duration)`,
`play_sound(id, world_pos)`, `spawn_particles(effect_id, world_pos, amount)`,
`save_requested(slot)`, `load_requested(slot)`, `time_changed(tick, frac)`.
Emit freely; connect only to what you need. `Events.toast(text, kind)` is a
shorthand for `notify`.

## 5. Cross-module singletons (stubbed — each has exactly one owner)

| Autoload | File | Owner |
|---|---|---|
| `Atlas` | `render/atlas.gd` | rendering |
| `Lighting` | `sim/lighting/lighting.gd` | lighting |
| `Liquids` | `sim/liquids/liquid_sim.gd` | liquids |
| `PlanetGen` | `worldgen/planet_gen.gd` | terrain |
| `Recipes` | `crafting/recipe_registry.gd` | crafting |
| `Quests` | `quests/quest_manager.gd` | quests |
| `Status` | `survival/status_manager.gd` | survival |
| `Universe` | `space/universe.gd` | space |
| `Tech` | `tech/tech_manager.gd` | tech |
| `Audio` | `fx/audio.gd` | fx |
| `SaveManager` | `persistence/save_manager.gd` | persistence |
| `UI` | `ui/ui_manager.gd` | menus |

If you are the owner, **replace the stub entirely but keep every method
signature listed in it** — other modules already call them. If you are not the
owner, call the stub methods; they are safe no-ops until that agent lands.

The player inventory lives at `Game.player.inventory` (owned by the inventory
agent, class `Inventory`). Query it defensively:
```gdscript
var inv = Game.player.get("inventory") if Game.player else null
if inv and inv.has_method("count_of"): ...
```

## 6. Rules that keep twenty parallel agents from colliding

1. **Never edit files outside your directory.** Not even a one-line fix. If core
   is wrong, note it in your final report instead.
2. **Autoload order is fixed** (see `project.godot`). `Game` is last, so it may
   reference anything; `Blocks`/`Items` are early, so they may not reference
   gameplay singletons at `_ready()` time.
3. **Guard optional dependencies.** Another agent's module may not exist yet at
   the moment you are written, and must never crash the game if it fails:
   `if node.has_method(&"foo"): node.foo()`.
4. **Everything must be procedural.** There are no binary assets in this repo
   and none may be added — no `.png`, `.ogg`, `.glb`. Textures come from
   `Atlas`, audio is synthesised in `fx/`, meshes are built in code.
5. **Plane space, always.** Any "left/right" logic uses
   `View.lateral_of()` / `set_plane_velocity()`, never raw `.x`.
6. **Static typing.** Godot 4.4+ GDScript, typed vars and signatures. The
   project must import and run with zero script errors:
   `godot --headless --import --path .` then
   `godot --headless --path . --quit-after 300`.
7. **No `class_name` collisions.** Prefix yours with your domain
   (`MonsterAI`, `CraftingStation`, `LiquidCell`) and grep before you commit.
8. **Scene files you own must be committed as `.tscn` text**, built by hand or
   in code — do not rely on the editor.
9. **`_physics_process` for gameplay, `_process` for presentation.**
10. Write for a reader: doc-comment every public method with `##`.
