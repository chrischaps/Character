-- Level: Collection of platforms with collision and navigation
local vec2 = require('lib.vec2')
local Platform = require('world.platform')

local Level = {}
Level.__index = Level

function Level.new()
    local self = setmetatable({}, Level)
    self.platforms = {}
    self.ground_y = 550
    return self
end

-- Add a platform to the level
function Level:add_platform(x, y, width, height, options)
    local platform = Platform.new(x, y, width, height, options)
    table.insert(self.platforms, platform)
    return platform
end

-- Create a test level with varied platforms
function Level:create_test_level(screen_width, screen_height)
    self.platforms = {}
    self.ground_y = screen_height - 50

    -- Ground
    self:add_platform(0, self.ground_y, screen_width, 50, {
        climbable = false,
        color = {0.3, 0.3, 0.35}
    })

    -- Left tower (tall, climbable)
    self:add_platform(50, 350, 60, 200, {
        color = {0.4, 0.35, 0.35}
    })

    -- Left tower top
    self:add_platform(30, 330, 100, 20, {
        color = {0.45, 0.4, 0.4}
    })

    -- Middle low platform
    self:add_platform(200, 480, 120, 20, {
        color = {0.35, 0.4, 0.35}
    })

    -- Stepping stones (ascending right)
    self:add_platform(350, 450, 80, 20, {
        color = {0.35, 0.35, 0.4}
    })
    self:add_platform(460, 390, 80, 20, {
        color = {0.35, 0.35, 0.4}
    })
    self:add_platform(570, 330, 80, 20, {
        color = {0.35, 0.35, 0.4}
    })

    -- Right tower (tall, climbable)
    self:add_platform(700, 280, 60, 270, {
        color = {0.4, 0.35, 0.35}
    })

    -- High bridge connecting towers
    self:add_platform(110, 250, 200, 15, {
        color = {0.4, 0.4, 0.45}
    })

    -- Floating island (top right)
    self:add_platform(550, 200, 100, 25, {
        color = {0.45, 0.4, 0.4}
    })

    -- Small stepping stone to high areas
    self:add_platform(420, 270, 50, 15, {
        color = {0.35, 0.4, 0.4}
    })

    -- Highest platform
    self:add_platform(250, 150, 150, 20, {
        color = {0.5, 0.45, 0.4}
    })

    return self
end

-- Constrain all points of a creature to level geometry
function Level:constrain_points(points)
    local contacts = {}

    for _, point in ipairs(points) do
        -- Check ground first
        if point.pos.y > self.ground_y - point.radius then
            point.pos.y = self.ground_y - point.radius
            local vel = point:get_velocity()
            point.old_pos.y = point.pos.y + vel.y * 0.3
            point.old_pos.x = point.pos.x - vel.x * 0.9
            table.insert(contacts, {point = point, surface = 'ground'})
        end

        -- Check platforms
        for _, platform in ipairs(self.platforms) do
            local surface = platform:constrain_point(point)
            if surface then
                table.insert(contacts, {point = point, surface = surface, platform = platform})
            end
        end
    end

    return contacts
end

-- Check if a point is on any surface (for pathfinding)
function Level:get_surface_at(x, y, tolerance)
    tolerance = tolerance or 10

    -- Check ground
    if math.abs(y - self.ground_y) <= tolerance then
        return {surface = 'ground', y = self.ground_y}
    end

    -- Check platforms
    for _, platform in ipairs(self.platforms) do
        if platform:is_on_top(x, y, tolerance) then
            return {surface = 'top', platform = platform, y = platform.y}
        end
        if platform:is_on_left_wall(x, y, tolerance) then
            return {surface = 'left', platform = platform, x = platform.x}
        end
        if platform:is_on_right_wall(x, y, tolerance) then
            return {surface = 'right', platform = platform, x = platform.x + platform.width}
        end
    end

    return nil
end

-- Find the nearest walkable surface below a point
function Level:find_ground_below(x, y)
    local best_y = self.ground_y
    local best_platform = nil

    for _, platform in ipairs(self.platforms) do
        if x >= platform.x and x <= platform.x + platform.width then
            if platform.y >= y and platform.y < best_y then
                best_y = platform.y
                best_platform = platform
            end
        end
    end

    return best_y, best_platform
end

-- Check if a point is on or near a walkable surface (for grounded detection)
function Level:is_point_on_surface(x, y, tolerance)
    tolerance = tolerance or 20  -- Increased default tolerance

    -- Check ground (within tolerance above ground level)
    if y >= self.ground_y - tolerance then
        return true, 'ground'
    end

    -- Check platform tops (within tolerance of platform surface)
    for _, platform in ipairs(self.platforms) do
        if x >= platform.x - 5 and x <= platform.x + platform.width + 5 then
            if y >= platform.y - tolerance and y <= platform.y + tolerance then
                return true, 'top'
            end
        end
    end

    return false, nil
end

-- Get all navigation points in the level
function Level:get_all_nav_points()
    local points = {}

    -- Ground nav points (denser spacing for better pathfinding)
    local ground_step = 60
    for x = 30, 770, ground_step do
        table.insert(points, {
            x = x,
            y = self.ground_y,
            surface = 'ground',
            platform = nil
        })
    end

    -- Platform nav points
    for _, platform in ipairs(self.platforms) do
        local platform_points = platform:get_nav_points()
        for _, p in ipairs(platform_points) do
            table.insert(points, p)
        end
    end

    return points
end

function Level:draw()
    for _, platform in ipairs(self.platforms) do
        platform:draw()
    end
end

function Level:draw_debug()
    for _, platform in ipairs(self.platforms) do
        platform:draw_debug()
    end

    -- Draw ground line
    love.graphics.setColor(0.5, 0.5, 0.55)
    love.graphics.line(0, self.ground_y, 800, self.ground_y)
end

return Level
