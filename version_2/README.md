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
Shift     sprint (loud)                      F     swing at what you are aiming at
Ctrl      crouch — quiet, short, sure-footed R     interact · talk · offer food
Q / E     rotate the world 90°               G     activate the equipped tech
Wheel     zoom · Ctrl+Wheel change slot      X     drop the held stack
1-9       hotbar slot

CUTAWAY   V on/off   B mode (drill / fill / planar)   N ghost opacity
          H mine through the cut

I / Tab   inventory     K crafting     J quests     M star map     T techs
F5        quick save    F1 help        Esc close panel / quit
```

---

## The camera-obstruction system

This is the piece everything else is built around. It is **one predicate**,
evaluated identically on the CPU and the GPU. There is no special case for
tunnels, none for house interiors, none for overhangs — those are all the same
situation as far as the rule is concerned.

Two rules come before anything else.

**The keep shell.** Blocks immediately around the player are never cut *unless
they lie toward the lens*. The floor under your feet, the wall beside you and
the tree you just walked up to all stay exactly where they are. This is not a
nicety: without it the thing you are trying to mine vanishes at precisely the
moment you get close enough to mine it, and the opening quest — fell six logs —
is unfinishable. The test suite asserts it in both directions: a trunk beside
you survives and is still aimable, and a block genuinely between you and the
lens is still removed.

**Then one of three shapes**, cycled with `B`:

| mode | what it removes |
|---|---|
| **Drill** | a cylinder from the lens to the player, with a spherical cap at your end so you stay visible pressed against a wall |
| **Fill** | cast to the first air along the sightline, flood-fill the pocket you are standing in, and cut everything between *that whole pocket* and the lens |
| **Planar** | when you are genuinely occluded, a slab of voxel coordinates directly in front of you: the flat side-on cross-section |

Drill handles the awkward cases for free — fall down a hole and it punches
straight through the roof, exposing the shaft without gouging the hillside.

Fill is the one for tunnels. A drill shows you a cone around yourself; fill
shows you the *gallery*, lanterns receding into the distance and all. The flood
only travels through **covered** air, which is what confines it: a doorway does
not leak it into the open sky, so it works indoors as well as underground, and
standing in a field it does nothing at all.

Planar is the classic Starbound slab, and it stays dormant until something is
actually in the way.

### Ghosts instead of holes

Cut blocks are deleted outright by default. Press `N` and they become dithered
ghosts instead, at an opacity that **fades to nothing with distance from you**,
the way distant props fade in Don't Starve — desaturated and cooled so they read
as a blueprint of the block rather than the block. The dither is an ordered
screen-door pattern in the opaque pass, so there is no sorting and no second
draw call.

`H` decides whether cut blocks can still be mined. When ghosts are visible they
are targetable directly; when blocks are deleted the raycast prefers what you
can see and only falls back to the hidden geometry if there was nothing else, so
a cutaway can never leave you unable to reach something that is really there.

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
- **crouching** (`Ctrl`) drops your hitbox low enough to crawl a one-block gap,
  stops you walking off a ledge, and cuts your noise radius from twenty-six
  metres to three — which is the difference between walking past a Fennix and
  meeting one;
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
| **19 creatures** | Starbound's hand-made unique monsters — no procedural generation, no farm animals — each with its own temperament, hours, diet and social habits |
| **21 quests** | a ten-beat campaign that teaches the game in order, plus a pool of repeatable side quests the village roles hand out |
| **37 effects** | buffs, elemental debuffs and the four survival needs, all expressed as the same kind of object |
| **17 techs** | one per slot across legs / body / head |
| **31 objects** | chests, stations, machines, doors, lights and utilities, each with its own state |

Progression is the descent. Ore tiers are banded by depth and gated by tool
tier, so a copper pickaxe returns *nothing* from a titanium vein — the ladder is
not a suggestion. Digging deeper is the difficulty curve.

### The bestiary

The creatures are characters rather than stat blocks. Each runs a small state
machine over three drives — **hunger**, **fear** and **alertness** — and the
states are `sleep`, `graze`, `wander`, `alert`, `stalk`, `chase`, `attack`,
`flee` and `return`. A glyph over the head tells you which one you are looking
at, because knowing that a thing has *decided about you* is the whole game.

Perception is sight **and** hearing. Sight is a cone, blocked by terrain, and
halved at night for anything diurnal. Hearing reads what you are actually
doing — sprinting carries twenty-six metres, crouching barely three — so
sneaking is a tactic rather than a pose.

What that buys, per creature:

- a **Poptop** grazes in loose herds by day and is entirely harmless until you
  are inside its patch, at which point it leaps;
- a **Yokat** herd bolts as one animal and only fights when there is nowhere
  left to run;
- a **Hypnare** will not start anything ever — hit it once and it retaliates,
  and whatever it touches goes slow;
- a **Mandraflora** is indistinguishable from undergrowth until you are close;
- a **Crustoise** walks up walls and has a shell that must be cracked before
  damage means anything;
- a **Batong** is blind, hunts entirely by ear, and does not care how dark it is;
- a **Scandroid** has a narrow sight cone and an alarm that tells everything
  within thirty metres exactly where you are;
- a **Fennix** hunts in threes and will kill an unprepared player;
- **packs** converge on a wounded member, **herds** scatter, and anything below
  its courage threshold breaks and runs.

Offer a creature something it eats (`R` while holding it) and, if it is calm
enough to take it, it will start to come round to you.

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
  cutaway.gd              THE predicate — three modes, keep shell, ghosting
  camera_rig.gd           quantised 4-way yaw, pitch, follow, zoom
  player.gd               billboard actor, voxel AABB physics, mining/building
  monster.gd              drives, senses, states — the creature brain
  npc.gd                  villagers, on the same physics
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
  cutaway.gdshaderinc     the predicate again, in GLSL, included by every pass
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
runs 124 assertions covering everything that has to hold for the game to be
playable: registries filled and cross-referentially sound (no recipe, drop or
quest reward naming an item that does not exist), terrain generated with ore and
plants in it, the player standing in free space on solid ground, mining dropping
and tier-gating correctly, placing consuming, crafting resolving, monsters
taking damage, quests advancing and chaining, a save round-tripping — and the
rules that were added because they had been got wrong once already: the keep
shell protects the floor and the trunk beside you but not the block in the way,
the fill never escapes into the open sky, planar stays dormant in the open,
crouching genuinely changes the swept box, and a shelled creature soaks damage
until its shell is gone.

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
