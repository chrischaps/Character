# Character v2: The Dusk Cave (LÖVE 2D)

Procedural creature animation in the spirit of Rain World. Three creatures live in one overgrown cave at dusk. You guide one with clicks, and the other two wander on their own. Each creature shows a different technique:

| Creature | Technique |
|----------|-----------|
| **Earthworm** (`creatures/worm.lua`) | A verlet chain that crawls by peristalsis. It has bending stiffness, ground grip, and a tapered mesh. |
| **Jelly Blob** (`creatures/blob.lua`) | A position-based pressure soft body. It uses edge and area constraints, rolls, and squashes for real when it lands. |
| **Cave Spider** (`creatures/spider.lua`) | Eight FABRIK legs that step to raycast footholds in alternating groups. It walks on floors, walls and ceilings. |

![v2](docs/v2-dusk-cave.png)

v1 (tag `v1`) was two creatures on grey platforms. See git history for the v2 rebuild plan's rationale.

## Running

```bash
cd C:\Users\chris\dev\Character
love .
```

## Controls

| Key | Action |
|-----|--------|
| Left click | Guide the selected creature. The click snaps to the surface below; the spider can also go to walls and ceilings. |
| 1 / 2 / 3, Tab | Select a creature |
| H | Help card |
| N | Navigation graph |
| X | X-ray: creatures drawn as the simulation sees them (points, constraints, bones), over a faint graph |
| D | Debug view: physics points, foot targets, LoveLibs debug overlay, verbose logs |
| W | Toggle wandering for unselected creatures |
| P | Pause |
| M | Mute |
| R | Reset |
| F | Fullscreen |
| F1–F4 | PostFX: bypass, distortion, bloom, colour grade |
| Esc | Quit |

## Dev modes (`dev.lua`): verify without a human at the mouse

```bash
lovec . --selftest        # graph integrity, reachability, 117 trips, determinism, audio smoke test
lovec . --snap <worm|blob|spider> <sec> <file.png> [--goal x y] [--zoom cx cy z]
        [--frames n every] [--debug] [--nav] [--help] [--nolight] [--nopost] [--nowander]
lovec . --bench <sec>     # 1920x1080 uncapped, prints avg/worst frame time
lovec . --script sitecap/<file>.lua   # capture script (save dir first): offscreen, frame-exact renders
lovec . --navdump <who> <solid_id>
lovec . --seed <n>
```

- Snapshots go to the save dir: `%APPDATA%/LOVE/character/`.
- The `--script` API (`script_api` in `main.lua`) offers `step(sec)`, `render(w, h, {zoom, hud, xray, show_nav, hide_marker})`, `save` and `click`. Renders are offscreen at any size; PostFX's final `setCanvas()` is redirected into the target.
- The chaps.dev showcase capture kit lives in the save dir, not the repo: `sitecap/` holds `cap.lua`, `stills.lua`, `cover.lua`, `videos.lua` and `compose_cover.py`.
- The sim is deterministic: fixed step and seeded `rng.sim`. The selftest proves the same result at 30, 60 and 240 fps.
- Baseline at the end of v2: 20/20 checks, and about 3.9 ms per frame at 1080p.

## Architecture

```
main.lua            fixed-step loop (1/120 s) + render interpolation, input, LoveLibs scaling/postfx/music
dev.lua             selftest / snap / bench / navdump
libs/LoveLibs/      git subtree (branch master): scaling, postfx, music, debug overlay, verlet (vines)
core/
  ballistics.lua    THE jump model: solve_jump, solve_fall, sample_arc, arc_clear
  navgraph.lua      per-creature graph: walk/crawl/jump/fall edges, built from that creature's profile
  pathfinder.lua    A* with a binary heap
  controller.lua    path -> walk / crawl / launch / steer; repaths on bad landings, stalls, blocks
  fabrik.lua        2D FABRIK with a pole hint
  synth.lua         procedural audio: creature voices, movement loops, drips with baked echo, chimes
  log.lua, rng.lua  category logging (quiet unless D), seeded sim/look RNG streams
creatures/
  base.lua          Mover (the exact kinematic anchor) + Face (blink, gaze, eye drawing)
  worm.lua, blob.lua, spider.lua
world/
  levels/cave.lua   solids (AABBs) + decor hints: vines, mushrooms, stalactites, spawns, mouth
  level.lua         spatial queries: solid_at, raycast, surface_below, top_spans
  collision.lua     swept point-vs-AABB resolution (entry-time face choice), raycast
  world.lua         creatures, graphs, controllers, wandering, event bus, interpolation snapshots
  flora.lua         verlet vines, spring grass, squashable glow mushrooms (all react to creatures)
  ambience.lua      fireflies, drips, dust motes in the light shafts
  render/           palette, backdrop (sky + baked back wall), rock (baked stone), lighting, scene
fx/                 particles (dust, pebbles, spores, splashes), marker (goal ring)
ui/hud.lua          fading title card, roster, help card
```

## Key design decisions

- **Anchor plus soft body.** Every creature rides an exact kinematic anchor (`base.lua` Mover). It uses closed-form gravity integration, the same model `ballistics` assumes. The expressive physics (verlet, PBD, IK) hangs off the anchor. Navigation is exact, and the bodies can stay loose.
- **One jump model.** The navgraph creates a JUMP/FALL edge only if `ballistics.solve_jump` finds a velocity within the creature's limits and `arc_clear` confirms the arc misses all geometry. The controller launches with the same solver. In v1 the graph promised 120px jumps that the controller capped at about 40px.
- **Per-creature graphs.** They are built from `profile = {radius, height, step, jump_vx, jump_vy, climbs}`. The spider's graph covers every exposed perimeter, corners included, plus concave joins between solids.
- **Fixed timestep (120 Hz).** Verlet friction and PBD are per step, so physics no longer depends on frame rate. Rendering interpolates between the last two steps through `World:snapshot/interpolate/restore`.
- **Lighting.** The scene is multiplied by a light map: violet ambient, the mouth pool, the shafts, mushrooms, fireflies, the blob, and a lantern around the selected creature. Emissives and additive shafts are drawn after the multiply. LoveLibs PostFX adds bloom and a colour grade.
- **Gameplay rewards are visual and audible, never numeric.** Clicks bloom a ring and play a pentatonic chime. Unreachable clicks shrug.

## Gotchas learned

- **PostFX tint:** LoveLibs `PostFX.endScene` draws its canvases with the current colour. Call `setColor(1,1,1,1)` first, or the whole frame is tinted by whatever the scene drew last. It showed up as a dark, green-tinted frame.
- **Offset outlines fold:** an offset polyline around a sharply bent spine folds into spikes. Draw the outline as a union of discs, and add bending stiffness to the chain.
- **Level design can trap creatures:** a level can leave pits where nothing is reachable. The selftest's reachability check, "every top surface reachable from spawn and back", caught one immediately.
- **`ellipse` has no rotation argument:** `love.graphics.ellipse` doesn't rotate. Use push/translate/rotate, as the spider does.
- **LoveLibs subtree branch:** the LoveLibs subtree is on branch `master`, not `main`.

## Wishlist

- The Rain World-style slugcat (verlet body + IK limbs) as a fourth creature.
- Water pools that the blob floats in, and ripples.
- Creatures noticing each other: the worm retreats from the spider, the blob follows the worm.
