-- Platform: Solid rectangle that creatures can stand on, collide with, and climb
local vec2 = require('lib.vec2')

local Platform = {}
Platform.__index = Platform

function Platform.new(x, y, width, height, options)
    options = options or {}
    local self = setmetatable({}, Platform)

    self.x = x
    self.y = y
    self.width = width
    self.height = height

    -- Collision properties
    self.solid = options.solid ~= false  -- Can collide with sides
    self.climbable = options.climbable ~= false  -- Can climb walls

    -- Visual
    self.color = options.color or {0.35, 0.35, 0.4}
    self.outline_color = options.outline_color or {0.5, 0.5, 0.55}

    return self
end

-- Get platform bounds
function Platform:get_bounds()
    return self.x, self.y, self.x + self.width, self.y + self.height
end

-- Check if a point is inside the platform
function Platform:contains_point(px, py)
    return px >= self.x and px <= self.x + self.width and
           py >= self.y and py <= self.y + self.height
end

-- Check if a point is on top surface (within tolerance)
function Platform:is_on_top(px, py, tolerance)
    tolerance = tolerance or 5
    return px >= self.x and px <= self.x + self.width and
           math.abs(py - self.y) <= tolerance
end

-- Check if a point is on left wall
function Platform:is_on_left_wall(px, py, tolerance)
    tolerance = tolerance or 5
    return py >= self.y and py <= self.y + self.height and
           math.abs(px - self.x) <= tolerance
end

-- Check if a point is on right wall
function Platform:is_on_right_wall(px, py, tolerance)
    tolerance = tolerance or 5
    return py >= self.y and py <= self.y + self.height and
           math.abs(px - (self.x + self.width)) <= tolerance
end

-- Check if a point is on bottom surface
function Platform:is_on_bottom(px, py, tolerance)
    tolerance = tolerance or 5
    return px >= self.x and px <= self.x + self.width and
           math.abs(py - (self.y + self.height)) <= tolerance
end

-- Constrain a verlet point to not penetrate the platform
-- Returns: surface type if constrained ('top', 'left', 'right', 'bottom'), nil otherwise
function Platform:constrain_point(point, bounce, friction)
    bounce = bounce or 0.3
    friction = friction or 0.9

    local px, py = point.pos.x, point.pos.y
    local radius = point.radius or 5

    -- Check if point is inside or overlapping
    local left = self.x - radius
    local right = self.x + self.width + radius
    local top = self.y - radius
    local bottom = self.y + self.height + radius

    if px < left or px > right or py < top or py > bottom then
        return nil  -- Not touching
    end

    -- Find closest edge
    local dist_left = px - left
    local dist_right = right - px
    local dist_top = py - top
    local dist_bottom = bottom - py

    local min_dist = math.min(dist_left, dist_right, dist_top, dist_bottom)
    local vel = point:get_velocity()

    if min_dist == dist_top and self.solid then
        -- Push up (landing on top)
        point.pos.y = top
        point.old_pos.y = point.pos.y + vel.y * bounce
        point.old_pos.x = point.pos.x - vel.x * friction
        return 'top'
    elseif min_dist == dist_bottom and self.solid then
        -- Push down (hitting bottom)
        point.pos.y = bottom
        point.old_pos.y = point.pos.y + vel.y * bounce
        return 'bottom'
    elseif min_dist == dist_left and self.solid then
        -- Push left
        point.pos.x = left
        point.old_pos.x = point.pos.x + vel.x * bounce
        if self.climbable then
            point.old_pos.y = point.pos.y - vel.y * friction
        end
        return 'left'
    elseif min_dist == dist_right and self.solid then
        -- Push right
        point.pos.x = right
        point.old_pos.x = point.pos.x + vel.x * bounce
        if self.climbable then
            point.old_pos.y = point.pos.y - vel.y * friction
        end
        return 'right'
    end

    return nil
end

-- Get navigation points for this platform (for pathfinding)
function Platform:get_nav_points(margin)
    margin = margin or 10
    local points = {}

    -- Top surface: left edge, center, right edge
    table.insert(points, {
        x = self.x + margin,
        y = self.y,
        surface = 'top',
        platform = self
    })
    table.insert(points, {
        x = self.x + self.width / 2,
        y = self.y,
        surface = 'top',
        platform = self
    })
    table.insert(points, {
        x = self.x + self.width - margin,
        y = self.y,
        surface = 'top',
        platform = self
    })

    -- Wall climbing disabled for now - was causing issues
    return points
end

function Platform:draw()
    -- Fill
    love.graphics.setColor(self.color)
    love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

    -- Outline
    love.graphics.setColor(self.outline_color)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle('line', self.x, self.y, self.width, self.height)
    love.graphics.setLineWidth(1)

    -- Climb indicator (subtle lines on walls)
    if self.climbable then
        love.graphics.setColor(0.6, 0.6, 0.65, 0.3)
        local step = 15
        for y = self.y + step, self.y + self.height - 5, step do
            love.graphics.line(self.x + 2, y, self.x + 6, y)
            love.graphics.line(self.x + self.width - 6, y, self.x + self.width - 2, y)
        end
    end
end

function Platform:draw_debug()
    self:draw()

    -- Draw nav points
    local nav_points = self:get_nav_points()
    for _, np in ipairs(nav_points) do
        if np.surface == 'top' then
            love.graphics.setColor(0, 1, 0, 0.8)
        else
            love.graphics.setColor(0, 0.7, 1, 0.8)
        end
        love.graphics.circle('fill', np.x, np.y, 4)
    end
end

return Platform
