# Procedural Character Animation - LÖVE 2D

A project exploring programmatic/procedural 2D character animation inspired by Rain World's physics-based creature movement.

## Project Overview

This project implements multiple approaches to procedural character animation:
1. **Verlet Chain (Worm)** - Segmented body with distance constraints
2. **Spring-Damper (Blob)** - Soft body with spring physics

Both creatures can autonomously pathfind and navigate a platformer level using A* pathfinding.

## Running

```bash
cd C:\Users\chris\dev\Character
love .
```

## Controls

- **Left Click** - Set destination (creature pathfinds automatically)
- **Tab** - Switch between creatures (Worm/Blob)
- **D** - Toggle debug visualization
- **N** - Toggle navigation graph visualization
- **S** - Toggle smooth rendering (worm only)
- **R** - Reset creature position
- **Escape** - Quit

## Architecture

### Core Physics (`core/`)

- **vec2.lua** - 2D vector math library with metamethods
- **verlet_point.lua** - Position-based physics point (verlet integration)
- **verlet_chain.lua** - Chain of connected points with distance constraints + Catmull-Rom curve rendering
- **spring.lua** - Spring-damper force connections (Hooke's law)

### Pathfinding (`core/`)

- **navgraph.lua** - Navigation graph built from level geometry. Creates walk/jump/fall connections between nav points
- **pathfinder.lua** - A* pathfinding over the nav graph
- **controller.lua** - Converts paths into movement commands (walk, jump, air_control). Handles waypoint progression

### World (`world/`)

- **platform.lua** - Solid rectangle platforms with collision detection
- **level.lua** - Collection of platforms forming the test level. Provides `is_point_on_surface()` for grounded detection

### Creatures (`creatures/`)

- **worm.lua** - Verlet chain creature. Head is controlled, body follows with physics
- **blob.lua** - Spring-based soft body. Center point surrounded by outer points connected with springs

## Key Design Decisions

### Physics

- **Verlet integration** for position-based physics (stable, no velocity explosions)
- **Gravity**: 980 pixels/sec² (roughly Earth-like)
- **Terminal velocity**: 600 pixels/sec
- **Max jump velocity**: 500 vertical, 300 horizontal

### Grounded Detection

The `Level:is_point_on_surface(x, y, tolerance)` function checks if a point is near a walkable surface. This is more reliable than collision-based detection for determining if a creature can jump.

**Important**: Creatures must be within tolerance of a surface to be considered "grounded". The worm's head being "pinned" vs "unpinned" determines whether it uses direct movement (pinned) or physics simulation (unpinned/jumping).

### Movement States

- **Grounded + Pinned**: Direct position control, can walk and jump
- **Not Grounded + Unpinned**: Physics simulation (gravity, velocity), air control only
- **Climbing**: Currently disabled (was causing stuck issues)

### Pathfinding

- Nav points placed on ground and platform tops
- Connections: WALK (horizontal), JUMP (up/across), FALL (down)
- Wall climbing connections disabled for now
- Waypoint threshold: 40px (advance to next waypoint when within this distance)

## Known Issues / Future Work

1. **Climbing disabled** - Wall climbing caused creatures to get stuck. Could be re-enabled with better wall detection
2. **Jump arc** - Jumps use constrained max velocities rather than calculating exact trajectories
3. **Only 2 creatures** - Plan included FABRIK Spider and Hybrid Slugcat (Rain World style) which aren't implemented yet

## Debug Logging

The worm has debug prints for:
- `[SPAWN]` - Creature spawn position
- `[WORM] Jump requested` - When jump command received
- `[WORM] JUMPING!` - When jump actually fires with velocity
- `[WORM] Landed!` - When landing detected
- `[WORM] Walked off edge` - When falling begins
- `[MAIN]` - Periodic action/movement type logging

## File Structure

```
Character/
├── main.lua              # Entry point, game loop, input handling
├── conf.lua              # LÖVE configuration
├── CLAUDE.md             # This file
├── lib/                  # REUSABLE LIBRARIES (copy to other projects)
│   ├── vec2.lua          # 2D vector math
│   ├── verlet.lua        # Verlet physics (points + chains)
│   ├── spring.lua        # Spring-damper physics
│   └── synth.lua         # Procedural audio synthesizer
├── core/                 # Game-specific code
│   ├── navgraph.lua      # Navigation graph
│   ├── pathfinder.lua    # A* pathfinding
│   ├── controller.lua    # Movement controller
│   └── synth.lua         # Game-specific sound effects
├── creatures/
│   ├── worm.lua          # Verlet worm
│   └── blob.lua          # Spring blob
└── world/
    ├── platform.lua      # Platform collision
    └── level.lua         # Level geometry
```

## Reusable Libraries (`lib/`)

These libraries are designed to be dropped into any LÖVE project:

### vec2.lua - 2D Vector Math
```lua
local vec2 = require('lib.vec2')
local a = vec2.new(10, 20)
local b = vec2.new(5, 5)
local c = vec2.add(a, b)       -- or a + b with metamethods
local len = vec2.length(c)
local norm = vec2.normalize(c)
```

### verlet.lua - Verlet Physics
Position-based physics for ropes, chains, tentacles, and soft bodies.
```lua
local Verlet = require('lib.verlet')

-- Single physics point
local point = Verlet.Point(100, 200, {mass = 1, friction = 0.99})
point:update(dt, {x = 0, y = 980})  -- Apply gravity

-- Chain of connected points (rope/tentacle)
local chain = Verlet.Chain(100, 50, 10, 15)  -- x, y, segments, segment_length
chain:update(dt, gravity)
chain:draw_smooth(4)  -- Draw as smooth curve
```

### spring.lua - Spring Physics
Hooke's law spring-damper connections for soft bodies and bouncy physics.
```lua
local Spring = require('lib.spring')
local Verlet = require('lib.verlet')

local p1 = Verlet.Point(100, 100)
local p2 = Verlet.Point(200, 100)
local spring = Spring.new(p1, p2, {stiffness = 200, damping = 10})

-- In update:
spring:apply_forces()
p1:update(dt, gravity)
p2:update(dt, gravity)
spring:draw()  -- Color-coded by stretch
```

### synth.lua - Procedural Audio
Generate sound effects without audio files.
```lua
local Synth = require('lib.synth')
local synth = Synth.new()

-- Use presets
local jump_sound = synth:create_sound('jump')
local hit_sound = synth:create_sound('hit')
jump_sound:play()

-- Or generate custom sounds
local custom = synth:generate({
    duration = 0.2,
    frequency = {start = 440, finish = 880},
    waveform = 'sine',  -- sine, saw, square, triangle, noise
    envelope = {attack = 0.01, decay = 0.1, sustain = 0.5, release = 0.09},
    volume = 0.5
})

-- Available presets: jump, land, hit, pickup, coin, laser, explosion, powerup, hurt, blip
```

## Original Plan

See `C:\Users\chris\.claude\plans\merry-jumping-blanket.md` for the original implementation plan which includes the not-yet-implemented FABRIK Spider and Hybrid Slugcat creatures.
