# Voxelbound

Starbound, rebuilt in Godot 4 on a Minecraft-style voxel world, shot like an
Octopath-Traveler HD-2D game, and viewed through a Don't-Starve-style rotatable
2.5D camera that **cannot be blocked** — anything between the lens and you is
sliced away, and the exposed cross-section is rebuilt as real geometry.

Open `project.godot` in Godot **4.7** and press Play. There are no binary assets:
every texture, icon, character, villager and monster is synthesised at boot.

```
WASD      move (relative to the camera)      LMB   mine (hold)
Space     jump — auto-steps single blocks    RMB   place / use the held item
Shift     sprint (burns energy)              F     swing at what you are aiming at
Ctrl      crouch · climb down ladders        R     interact (talk, open, sit)
Q / E     rotate the world 90°               G     activate the equipped tech
Wheel     zoom · Ctrl+Wheel change slot      X     drop the held stack
1-9       hotbar slot                        V     toggle the cutaway system

I / Tab   inventory     K crafting     J quests     M star map     T techs
F5        quick save    F1 help        Esc close panel / quit
```

---

## The camera-obstruction system

This is the piece everything else is built around. It is **one predicate**,
evaluated identically on the CPU and the GPU. There is no special case for
tunnels, none for house interiors, none for overhangs — those are all the same
situation as far as the rule is concerned.

The system casts a cylindrical "drill" from the camera lens to the player: any
block intersecting that cylinder is cut. The volume is a cylinder of `radius`
around the camera→player segment, plus a spherical cap of `target_padding` at
the player end so your immediate surroundings stay visible even when you are
pressed against a wall.

That handles the awkward cases for free. Fall down a hole and the cylinder
punches straight through the roof above you, exposing the shaft all the way
down without gouging out the rest of the hillside. Walk into a house and the
front wall and the near half of the roof happen to lie on the line of sight, so
you see the interior — nothing knows it is a house. Turn the camera and the
whole thing re-resolves along the new axis.

### Making it look like a cut, not a hole

Deleting blocks in a fragment shader would normally leave you staring *into* the
terrain — voxel meshers only emit faces where solid meets air, so the inside of a
hill has no geometry at all.

So the cut is done twice:

- **GPU** (`shaders/voxel.gdshader`, `voxel_glass`, `voxel_cross`) discards the
  fragments. Each pass recovers the owning block per-fragment and runs a
  line-for-line transcription of `Cutaway.is_cut()`, which is what keeps it
  bit-for-bit in step with the CPU predicate.
- **CPU** (`VoxelWorld._rebuild_caps`) walks the *boundary* of the cut volume and
  emits exactly the faces the discard just exposed — every solid block that
  survived but has a cut solid neighbour. Those go into a separate material
  (`shaders/cut_cap.gdshader`) styled as a sliced-open diagram: desaturated
  strata, a faint survey grid, and a warm glow falling off with distance from
  the player. That glow is what "highlights the tunnel" you just walked into.

The caps are rebuilt only when the player or the camera moves, and the scan is
restricted to the bounding box of the cut volume, so it costs a few thousand
cell tests rather than a re-mesh.

### Things that are only playable because of it

The cut is a gameplay verb, not just a camera trick. Turning the camera is an
action with consequences:

- the **Phase Lance** fires through terrain along the line of sight and hits
  whatever the cutaway is hiding;
- the **Revenant Edge** hits *only* targets standing inside the cut volume — it
  is inert in the open and devastating down a corridor;
- the **Depth Charge Launcher**'s blast runs back along the lens axis instead of
  spherically, clearing exactly the shaft the cutaway has opened;
- **Wraiths** phase through solid rock and only become visible where the cut
  covers them, so finding one means turning the camera rather than digging;
- **Phase Step** walks you into the volume between you and the lens, and **Fold**
  re-anchors the cut to something you are aiming at instead of to yourself;
- an **ancient vault** has exactly one door, on a seed-chosen wall — you find it
  by looking from a different side, not by mining.

---

## The game on top of it

A full Starbound-style loop: mine, smelt, craft, build, farm, fight, trade, take
quests and leave the planet.

| | |
|---|---|
| **246 blocks** | four depth strata (crust → mantle → deepstone → corestone), 29 ores gated by tool tier, 14 biome palettes, liquids, hazards, ladders, one-way platforms, cross-quad foliage and crops |
| **662 items** | the copper→solarium metal ladder, tools, weapons, armour sets with set bonuses, food, medicine, seeds, tech cards, placeable objects |
| **270 recipes** | across eleven stations, mostly *learned by picking up the ingredient* rather than unlocked by a menu |
| **25 species** | ground, flying, ranged, aquatic and special, plus four bosses, all drawn procedurally from a shape and a feature dictionary |
| **21 quests** | a ten-beat campaign that teaches the game in order, plus a pool of repeatable side quests the village roles hand out |
| **37 effects** | buffs, elemental debuffs and the four survival needs, all expressed as the same kind of object |
| **17 techs** | one per slot across legs / body / head |
| **31 objects** | chests, stations, machines, doors, lights and utilities, each with its own state |

Progression is the descent. Ore tiers are banded by depth and gated by tool
tier, so a copper pickaxe returns *nothing* from a titanium vein — the ladder is
not a suggestion. Digging deeper is the difficulty curve.

### The Proving Ground

Every run has a superflat, hostile-free world parked in the home system,
discovered from the first minute and free to travel to. It exists so building,
physics and the cutaway can be exercised against terrain with no confounding
variables — and so there is always somewhere safe to experiment. It is part of
the shipped game rather than a debug flag, because a testing world you have to
enable is a testing world nobody uses.

---

## Layout

```
main.tscn                 the whole game: environment, sun, world, player,
                          camera rig, HUD, post-process stack
project.godot             input is built at runtime (game.gd); the cutaway's
                          shader globals are declared here
scripts/
  blocks.gd               block registry: one byte per voxel, so it is capped
  items.gd                item types and the stack that moves them around
  inventory.gd            hotbar + backpack + armour in one index space
  crafting.gd             recipes, stations, and the one function that crafts
  combat.gd               damage rolls, the projectile catalogue, weapon rolls
  quests.gd               objectives, the catalogue, and the event-driven manager
  universe.gd             sectors, systems, planets, fuel
  worldgen.gd             biomes, strata, ores, decoration, structures
  survival.gd             hunger, thirst, air, warmth and status effects
  tech_manager.gd         what is unlocked, what is worn, what the button does
  liquids.gd              flow, falling blocks and crop growth on one budget
  sky.gd                  day/night and weather, modulating the authored grade
  voxel_world.gd          storage, streaming, mesher, cutaway caps, raycast
  cutaway.gd              THE predicate + its shader-global bridge
  camera_rig.gd           quantised 4-way yaw, pitch, follow, zoom
  player.gd               billboard actor, voxel AABB physics, mining/building
  monster.gd  npc.gd      the other actors, on the same physics
  placed_object.gd        chests, stations, machines, doors
  item_drop.gd  projectile.gd
  ui.gd                   every full-screen panel
  hud.gd                  vitals, needs, hotbar, tracker, damage numbers
  game.gd                 boot sequence, the camera→cutaway hand-off, and the
                          hub every module talks through
  tex_gen.gd              every texture in the game, generated at boot
  content/                the data: blocks, items, recipes, species, quests,
                          crops, techs, objects, effects, NPC roles
shaders/
  voxel.gdshader          terrain, with the cutaway discard
  voxel_glass.gdshader    transparent pass (glass, ice, water), same discard
  voxel_cross.gdshader    crossed-quad foliage and crops, same discard
  cut_cap.gdshader        the cross-section surfaces
  post.gdshader           vignette, chromatic aberration, split-tone, grain
tools/
  audit.gd                registry sizes against their hard limits
  smoke_test.tscn         76 integration assertions
  playthrough.tscn        a scripted session through every system and panel
  dev_capture.gd          screenshot harness for the cutaway situations
```

## How the world is stored

Every `(x, z)` column of the world is a **single 64-bit bitmask** of "is there
something here", alongside a mask of what occludes, a mask of what collides, and
a flat byte array of block ids. Face culling then becomes a handful of bitwise
ops per column instead of a loop over every voxel:

```gdscript
var f_up = solid & ~(solid >> 1)      # every up-facing exposed face, at once
var f_px = solid & ~solid_neighbour   # every +X face, at once
```

Only the set bits — i.e. the faces that actually exist — are ever iterated, and
per-vertex ambient occlusion is read straight out of the 3×3 neighbourhood of
column masks that the mesher already has in hand. That is what lets a pure
GDScript mesher keep up with a streaming world.

The three masks are what let foliage and liquids exist at all: `any` is what the
mesher sees, `solid` is what occludes, and `coll` is what stops you — so you
walk through a meadow, swim through water and climb a ladder without any of them
needing a special case in the physics.

**Block ids are one byte.** That is a hard cap of 256 and the registry asserts on
it; `tools/audit.gd` reports the headroom. Cosmetic block variants were the thing
cut to stay inside it, because widening the id would double the cost of the
storage the whole mesher is built around.

World height is 48 (the bitmasks need to stay under 63 bits), chunks are 16×16,
and the streaming radius is 5 chunks with a 1-chunk generation margin so seams
are never baked and then thrown away.

## Rendering

Forward+, ACES tonemapping, SSAO, bloom, volumetric fog, tilt-shift-ish DOF, and
a full-screen grade pass. The character, the villagers, the monsters and dropped
loot are `Sprite3D` Y-billboards with alpha-scissor shadow casting — Paper Mario
cutouts standing in a lit 3D world, which is the HD-2D trick. The player's
lantern is repositioned each frame to sit between the lens and the sprite so a
billboard is always lit face-on however the camera is turned.

Plants and crops are two quads crossed at 90° rather than billboards, because
the camera turns constantly and a billboard field would flip through itself on
every rotation. A cross reads identically from all four facings.

The day/night cycle *modulates* the authored environment rather than replacing
it — the grade in `main.tscn` is the art direction, and a lighting system that
throws it away has broken the game.

## Verifying a build

```
godot --headless --import --path .                 # compile everything
godot --headless --path . --script tools/audit.gd  # registry sizes vs limits
godot --headless --path . tools/smoke_test.tscn    # 76 integration assertions
godot --path .              tools/playthrough.tscn # scripted play + screenshots
```

`tools/smoke_test.tscn` boots the real `main.tscn`, streams the world in, and
asserts the things that must hold for the game to be playable: registries filled
and cross-referentially sound (no recipe, drop or quest reward naming an item
that does not exist), terrain generated with ore and plants in it, the player
standing in free space on solid ground, mining dropping and tier-gating
correctly, placing consuming, crafting resolving, monsters taking damage,
quests advancing and chaining, the cutaway predicate agreeing with itself, and a
save round-tripping.

`tools/playthrough.tscn` needs a real renderer for the screenshots but runs
headless for the logic. It exists mainly for the **panels**: they are only built
when opened, so nothing else ever executes them.

## Development screenshots

```
godot --path . --disable-vsync --fixed-fps 60 --dev-shots
```

Drives the player through the surface, the mineshaft, the gallery (including two
camera rotations), a cutaway-on/off pair, and a house interior, writing a PNG of
each to `user://shots` (or `$VOXELBOUND_SHOT_DIR`). `--disable-vsync` matters:
without it the window will block on present under some compositors.
