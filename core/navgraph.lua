-- Navigation Graph: Network of points and connections for pathfinding
local vec2 = require('lib.vec2')

local NavGraph = {}
NavGraph.__index = NavGraph

-- Connection types
NavGraph.WALK = 'walk'
NavGraph.JUMP = 'jump'
NavGraph.CLIMB = 'climb'
NavGraph.FALL = 'fall'

function NavGraph.new()
    local self = setmetatable({}, NavGraph)
    self.nodes = {}  -- {x, y, surface, platform, connections}
    self.jump_height = 120  -- Max jump height
    self.jump_distance = 150  -- Max horizontal jump distance
    self.walk_distance = 100  -- Max walk connection distance
    self.climb_speed = 0.7  -- Climbing is slower
    return self
end

-- Build navigation graph from a level
function NavGraph:build_from_level(level)
    self.nodes = {}

    -- Get all nav points from level
    local nav_points = level:get_all_nav_points()

    -- Create nodes
    for i, np in ipairs(nav_points) do
        self.nodes[i] = {
            id = i,
            x = np.x,
            y = np.y,
            surface = np.surface,
            platform = np.platform,
            connections = {}
        }
    end

    -- Build connections
    for i, node_a in ipairs(self.nodes) do
        for j, node_b in ipairs(self.nodes) do
            if i ~= j then
                local connection = self:can_connect(node_a, node_b, level)
                if connection then
                    table.insert(node_a.connections, {
                        target = j,
                        type = connection.type,
                        cost = connection.cost
                    })
                end
            end
        end
    end

    return self
end

-- Check if two nodes can be connected and how
function NavGraph:can_connect(node_a, node_b, level)
    local dx = node_b.x - node_a.x
    local dy = node_b.y - node_a.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Same platform walking (climbing disabled for now)
    if node_a.platform == node_b.platform and node_a.platform ~= nil then
        if node_a.surface == 'top' and node_b.surface == 'top' then
            -- Walk along top
            return {type = NavGraph.WALK, cost = dist}
        end
        -- Climbing disabled - was causing creatures to get stuck
    end

    -- Ground walking
    if node_a.surface == 'ground' and node_b.surface == 'ground' then
        if dist <= self.walk_distance then
            -- Check for obstacles
            if not self:path_blocked(node_a.x, node_a.y, node_b.x, node_b.y, level) then
                return {type = NavGraph.WALK, cost = dist}
            end
        end
    end

    -- Walking between ground and low platforms
    if (node_a.surface == 'ground' or node_a.surface == 'top') and
       (node_b.surface == 'ground' or node_b.surface == 'top') then
        if dist <= self.walk_distance and math.abs(dy) < 30 then
            if not self:path_blocked(node_a.x, node_a.y, node_b.x, node_b.y, level) then
                return {type = NavGraph.WALK, cost = dist}
            end
        end
    end

    -- Jumping (going up or across)
    if (node_a.surface == 'ground' or node_a.surface == 'top') and
       (node_b.surface == 'ground' or node_b.surface == 'top') then
        local height_diff = node_a.y - node_b.y  -- Positive means jumping up
        if height_diff >= 0 and height_diff <= self.jump_height then
            if math.abs(dx) <= self.jump_distance then
                -- Can jump here
                return {type = NavGraph.JUMP, cost = dist * 1.5}
            end
        end
    end

    -- Falling (going down)
    if (node_a.surface == 'ground' or node_a.surface == 'top') and
       (node_b.surface == 'ground' or node_b.surface == 'top') then
        local height_diff = node_b.y - node_a.y  -- Positive means going down
        if height_diff > 30 and height_diff <= 200 then
            if math.abs(dx) <= self.jump_distance then
                return {type = NavGraph.FALL, cost = dist * 0.8}
            end
        end
    end

    -- Wall jumps disabled for now
    return nil
end

-- Check if walking path is blocked by a platform
function NavGraph:path_blocked(x1, y1, x2, y2, level)
    local steps = 5
    for i = 1, steps - 1 do
        local t = i / steps
        local x = x1 + (x2 - x1) * t
        local y = y1 + (y2 - y1) * t

        for _, platform in ipairs(level.platforms) do
            -- Skip ground platform
            if platform.y < level.ground_y - 10 then
                if platform:contains_point(x, y) then
                    return true
                end
            end
        end
    end
    return false
end

-- Find the nearest node to a position
-- Prefers nodes at similar or lower height (reachable by walking/falling)
function NavGraph:find_nearest_node(x, y)
    local best_node = nil
    local best_score = math.huge

    for _, node in ipairs(self.nodes) do
        local dx = node.x - x
        local dy = node.y - y
        local dist = math.sqrt(dx * dx + dy * dy)

        -- Penalize nodes that are above us (harder to reach)
        local height_penalty = 0
        if node.y < y - 20 then  -- Node is above us
            height_penalty = (y - node.y) * 2  -- Strong penalty for height
        end

        local score = dist + height_penalty

        if score < best_score then
            best_score = score
            best_node = node
        end
    end

    return best_node
end

-- Find nearest node on a walkable surface
function NavGraph:find_nearest_walkable_node(x, y)
    local best_node = nil
    local best_dist = math.huge

    for _, node in ipairs(self.nodes) do
        if node.surface == 'ground' or node.surface == 'top' then
            local dx = node.x - x
            local dy = node.y - y
            local dist = dx * dx + dy * dy

            if dist < best_dist then
                best_dist = dist
                best_node = node
            end
        end
    end

    return best_node
end

function NavGraph:draw_debug()
    -- Draw connections
    for _, node in ipairs(self.nodes) do
        for _, conn in ipairs(node.connections) do
            local target = self.nodes[conn.target]

            if conn.type == NavGraph.WALK then
                love.graphics.setColor(0, 1, 0, 0.3)
            elseif conn.type == NavGraph.JUMP then
                love.graphics.setColor(1, 1, 0, 0.3)
            elseif conn.type == NavGraph.CLIMB then
                love.graphics.setColor(0, 0.7, 1, 0.3)
            elseif conn.type == NavGraph.FALL then
                love.graphics.setColor(1, 0.5, 0, 0.3)
            end

            love.graphics.line(node.x, node.y, target.x, target.y)
        end
    end

    -- Draw nodes
    for _, node in ipairs(self.nodes) do
        if node.surface == 'ground' or node.surface == 'top' then
            love.graphics.setColor(0, 1, 0, 0.8)
        else
            love.graphics.setColor(0, 0.7, 1, 0.8)
        end
        love.graphics.circle('fill', node.x, node.y, 5)

        -- Draw node ID
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print(node.id, node.x + 6, node.y - 6)
    end
end

return NavGraph
