# Planeshift

A Starbound-style sandbox adventure built in Godot 4 — mining, crafting,
procedural planets, combat, quests and interstellar travel — set on a
**Minecraft-esque 3D voxel world**.

The twist: you never see that world in 3D.

## The perspective mechanic

The camera is locked to an orthographic **side view**, and the player is a flat
Paper-Mario-style billboard. It plays like a 2D platformer. But the world is
genuinely three-dimensional, and you have two ways to move through the third
axis:

**Flip** (`Q` / `E`) rotates the camera 90° to one of four viewing planes.
You do not move — the world re-reveals itself along a new axis. A wall becomes
a corridor. A sealed vault turns out to have had a door all along, facing a
direction you had not looked from.

**Shift** (`PgUp` / `PgDn`) steps you one voxel layer into or out of the screen.
This is real traversal, and it can be blocked.

Starbound's foreground/background tile duality becomes literal here: the
"background" is simply the layers behind you, rendered dimmer by the slab
shader — and you can walk into them.

## Running it

```
godot --path .              # or open project.godot in the Godot 4.4+ editor
```

Requires Godot 4.4 or newer (developed against 4.7). There are **no binary
assets** in this repository by design — every texture, sound, mesh and icon is
generated procedurally at runtime.

## Controls

| | |
|---|---|
| `A` / `D` | move (screen-left / screen-right, in the current plane) |
| `Space` | jump · `Shift` sprint |
| `Q` / `E` | flip the view plane 90° |
| `PgUp` / `PgDn` | shift one layer deeper / shallower |
| Left / Right mouse | mine / place |
| `F` | interact · `G` activate tech |
| `I` `C` `J` `M` | inventory, crafting, quest log, star map |
| `F5` | quick save · `F3` debug overlay · `Esc` pause |

Every binding is rebindable in Options → Controls, and the HUD reads its own
key prompts from the live `InputMap`, so they stay correct after a rebind.

## Verifying a build

```
godot --headless --import --path .               # compile everything
godot --headless --path . tools/smoke_test.tscn  # 20 integration assertions
godot --headless --path . tools/save_test.tscn   # 12 persistence round-trips
godot --path .              tools/playthrough.tscn # scripted play + screenshots
godot --headless --path . tools/perf_probe.tscn  # chunk generation cost
```

All four exit non-zero on failure, so any of them can gate a build.

`tools/smoke_test.tscn` boots the real `main.tscn`, streams the world in, and
asserts the things that must hold for the game to be playable: registries
filled, terrain generated, the player standing in free space on solid ground,
and both halves of the perspective mechanic actually changing state (the flip
advances the view index and swaps the depth axis without moving the player
vertically; the shift advances the layer and leaves the player somewhere legal).

`tools/playthrough.tscn` needs a real renderer (it will not work headless). It
drives a full session — walk, flip through all four planes, shift a layer, open
every panel, travel to a planet, mine, build, fight, cycle day/night, save and
reload — and writes a numbered PNG per beat into `screenshots/`, checking each
frame actually contains rendered content rather than a blank buffer. Several
bugs only reproduce under a live renderer, so this is the suite that matters
most before shipping a change.

`tools/save_test.tscn` runs the persistence module's own harness: codec round
trips, corruption and truncation recovery, migration, region file reuse and
compaction, and the atomic-write-plus-backup path.

### Known limitation

Full terrain generation costs **~68 ms mean, ~200 ms worst** per 16³ chunk
(measure it yourself with `tools/perf_probe.tscn`). Chunk generation is
synchronous, so streaming a new region can visibly hitch. `World` mitigates
this — one chunk per frame, then a short amortisation pause — and entities
suspend gravity over not-yet-loaded chunks rather than falling out of the
world, but the underlying per-chunk cost is real. The fix is to move
`PlanetGen.generate_chunk` onto a worker thread; it is not thread-safe today
because the cave and decoration passes share a member scratch buffer.

## Layout

```
core/          frozen engine layer: voxel world, physics, perspective, registries
render/        procedural atlas, greedy mesher, slab shader
worldgen/      terrain, biomes, caves, ores + structures/ dungeons and villages
player/ camera/ the paper doll and the orthographic plane rig
inventory/ crafting/ combat/  item economy and fighting
entities/      monsters, AI, NPCs, item drops
quests/        campaign, dialogue, procedural side quests
sim/           liquid flow and voxel lighting
space/         universe, ship, star map, teleporters
survival/ tech/ objects/  needs, status effects, farming, techs, machines
ui/ fx/ persistence/  interface, procedural audio and particles, saves
content/       block and item definitions
docs/          ARCHITECTURE.md — the contract every module is written against
```

`docs/ARCHITECTURE.md` is the file to read first if you want to extend the
project; it documents the coordinate model, the frozen core API, and the rules
that let the modules compose.

## Coordinate model in one paragraph

The world is a right-handed voxel grid, `+Y` up, wrapping on X and Z. Four
views map to 90° yaw steps; each has a **lateral** axis (screen-right) and a
**depth** axis (into the screen). Gameplay logic is written in *plane space* —
`Vector2(lateral, up)` — so a single implementation of running, jumping,
pathfinding or aiming behaves identically no matter which way you are facing.
Anything that hard-codes `.x` as "horizontal" is a bug.
# claude-code-3d-starbound-multi
