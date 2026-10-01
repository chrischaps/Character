-- Procedural Character Animation Explorer
-- Controls:
--   Left Click: Set destination (creature pathfinds to location)
--   Tab: Switch between creatures
--   D: Toggle debug visualization
--   N: Toggle nav graph visualization
--   S: Toggle smooth rendering (for worm)
--   R: Reset creature position

local vec2 = require('lib.vec2')
local Level = require('world.level')
local NavGraph = require('core.navgraph')
local Pathfinder = require('core.pathfinder')
local Controller = require('core.controller')
local Synth = require('core.synth')

-- Available creatures
local creature_classes = {
    require('creatures.worm'),
    require('creatures.blob'),
}

-- State
local creature
local current_creature_index = 1
local level
local navgraph
local pathfinder
local controller
local synth

local debug_mode = false
local show_navgraph = false
local smooth_mode = false
local gravity = vec2.new(0, 980)

-- Virtual resolution for scaling
local VIRTUAL_WIDTH = 800
local VIRTUAL_HEIGHT = 600
local scale = 1
local offset_x = 0
local offset_y = 0
local canvas

-- Calculate scale to fit virtual resolution in window (letterboxed)
local function update_scale()
    local window_width, window_height = love.graphics.getDimensions()

    -- Calculate scale to fit while maintaining aspect ratio
    local scale_x = window_width / VIRTUAL_WIDTH
    local scale_y = window_height / VIRTUAL_HEIGHT
    scale = math.min(scale_x, scale_y)

    -- Center the scaled canvas (letterboxing)
    offset_x = (window_width - VIRTUAL_WIDTH * scale) / 2
    offset_y = (window_height - VIRTUAL_HEIGHT * scale) / 2
end

-- Convert screen coordinates to virtual coordinates
local function screen_to_virtual(x, y)
    local vx = (x - offset_x) / scale
    local vy = (y - offset_y) / scale
    return vx, vy
end

function love.load()
    love.graphics.setBackgroundColor(0.1, 0.1, 0.12)  -- Letterbox color

    -- Create canvas for virtual resolution
    canvas = love.graphics.newCanvas(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    canvas:setFilter("linear", "linear")  -- Smooth scaling

    update_scale()

    -- Create level at virtual resolution
    level = Level.new()
    level:create_test_level(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)

    -- Build navigation graph
    navgraph = NavGraph.new()
    navgraph:build_from_level(level)

    -- Create pathfinder
    pathfinder = Pathfinder.new(navgraph)

    -- Create controller
    controller = Controller.new(pathfinder)

    -- Create sound system
    synth = Synth.new()

    -- Spawn creature
    spawn_creature()
end

function spawn_creature()
    local class = creature_classes[current_creature_index]
    -- Spawn at x=150 to avoid the left tower (which spans x=50 to x=110)
    -- Spawn AT ground level (accounting for creature's visual size)
    creature = class.new(150, level.ground_y - 5)
    creature.is_grounded = true
    creature.synth = synth  -- Attach sound system
    if creature.chain then
        creature.chain:get_head().pinned = true
    end
    controller:clear_path()
    -- Stop any playing sounds when switching creatures
    if synth then
        synth:stop_slide()
    end
    print("[SPAWN] Creature spawned at y=" .. (level.ground_y - 5) .. ", ground_y=" .. level.ground_y)
end

function love.update(dt)
    dt = math.min(dt, 1/30)

    local cx, cy = creature:get_position()
    local reached = false

    -- Get movement target from controller
    local target, action
    target, action, reached = controller:get_movement_target(cx, cy, dt)

    if target and not reached then
        -- Calculate movement
        local movement = controller:calculate_movement(
            vec2.new(cx, cy),
            target,
            action,
            creature.is_grounded,
            dt
        )

        -- Log movement type periodically
        if love.timer.getTime() % 1 < dt then
            print("[MAIN] action=" .. tostring(action) .. ", movement.type=" .. tostring(movement.type) .. ", is_grounded=" .. tostring(creature.is_grounded))
        end

        -- Apply movement to creature
        creature:apply_movement(movement, dt)
    end

    -- Update creature physics
    creature:update(dt, nil, gravity, level)

    -- Update sound system (handles fading)
    synth:update(dt)

    -- Stop slide sound when creature is idle (reached destination or no path)
    if not controller:has_path() or reached then
        synth:stop_slide()
    end
end

function love.draw()
    -- Render everything to the canvas at virtual resolution
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.15, 0.15, 0.2)

    -- Draw level
    if debug_mode or show_navgraph then
        level:draw_debug()
    else
        level:draw()
    end

    -- Draw nav graph
    if show_navgraph then
        navgraph:draw_debug()
    end

    -- Draw path
    if debug_mode and controller:has_path() then
        local cx, cy = creature:get_position()
        controller:draw_debug(cx, cy)
    end

    -- Draw creature
    if debug_mode then
        creature:draw_debug()
    end

    if smooth_mode and creature.draw_smooth then
        creature:draw_smooth()
    else
        creature:draw()
    end

    -- Draw click indicator
    if controller.target then
        love.graphics.setColor(1, 0.3, 0.3, 0.8)
        love.graphics.circle('line', controller.target.x, controller.target.y, 12)
        love.graphics.circle('line', controller.target.x, controller.target.y, 6)
    end

    -- Draw UI
    draw_ui()

    -- Switch back to screen and draw scaled canvas
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, offset_x, offset_y, 0, scale, scale)
end

function draw_ui()
    love.graphics.setColor(1, 1, 1, 0.8)

    local y = 10
    love.graphics.print("Creature: " .. creature:get_name(), 10, y)
    y = y + 20
    love.graphics.print(creature:get_description(), 10, y)

    y = y + 30
    love.graphics.setColor(0.7, 0.7, 0.7, 0.8)
    love.graphics.print("Controls:", 10, y)
    y = y + 18
    love.graphics.print("  Left Click - Set destination", 10, y)
    y = y + 15
    love.graphics.print("  Tab - Switch creature (" .. current_creature_index .. "/" .. #creature_classes .. ")", 10, y)
    y = y + 15
    love.graphics.print("  D - Debug: " .. (debug_mode and "ON" or "OFF"), 10, y)
    y = y + 15
    love.graphics.print("  N - Nav graph: " .. (show_navgraph and "ON" or "OFF"), 10, y)
    y = y + 15
    love.graphics.print("  S - Smooth: " .. (smooth_mode and "ON" or "OFF"), 10, y)
    y = y + 15
    love.graphics.print("  R - Reset", 10, y)

    -- Path info
    if controller:has_path() then
        y = y + 20
        love.graphics.setColor(0.5, 1, 0.5, 0.8)
        love.graphics.print("Path: waypoint " .. controller.current_waypoint .. "/" .. #controller.path, 10, y)
    end

    -- FPS (use virtual width)
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.print("FPS: " .. love.timer.getFPS(), VIRTUAL_WIDTH - 70, 10)
end

function love.mousepressed(x, y, button)
    if button == 1 then
        -- Convert screen coordinates to virtual coordinates
        local vx, vy = screen_to_virtual(x, y)

        -- Clamp to virtual bounds
        vx = math.max(0, math.min(VIRTUAL_WIDTH, vx))
        vy = math.max(0, math.min(VIRTUAL_HEIGHT, vy))

        -- Left click: set destination
        local cx, cy = creature:get_position()
        local success = controller:set_destination(vx, vy, cx, cy)

        if not success then
            -- No path found, flash or something
            print("No path to destination")
        end
    end
end

function love.keypressed(key)
    if key == 'tab' then
        current_creature_index = (current_creature_index % #creature_classes) + 1
        spawn_creature()
    elseif key == 'd' then
        debug_mode = not debug_mode
    elseif key == 'n' then
        show_navgraph = not show_navgraph
    elseif key == 's' then
        smooth_mode = not smooth_mode
    elseif key == 'r' then
        creature:reset(150, level.ground_y - 5)
        controller:clear_path()
    elseif key == 'escape' then
        love.event.quit()
    end
end

function love.resize(w, h)
    -- Just update the scale - level stays at virtual resolution
    update_scale()
end
