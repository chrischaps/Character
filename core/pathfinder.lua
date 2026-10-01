-- A* Pathfinder for navigation graph
local vec2 = require('lib.vec2')

local Pathfinder = {}
Pathfinder.__index = Pathfinder

function Pathfinder.new(navgraph)
    local self = setmetatable({}, Pathfinder)
    self.navgraph = navgraph
    return self
end

-- Heuristic: straight-line distance
local function heuristic(node_a, node_b)
    local dx = node_b.x - node_a.x
    local dy = node_b.y - node_a.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Find path from start position to goal position
-- Returns a list of waypoints: {x, y, action}
function Pathfinder:find_path(start_x, start_y, goal_x, goal_y)
    local navgraph = self.navgraph

    -- Find nearest nodes
    local start_node = navgraph:find_nearest_node(start_x, start_y)
    local goal_node = navgraph:find_nearest_node(goal_x, goal_y)

    if not start_node or not goal_node then
        return nil
    end

    if start_node.id == goal_node.id then
        -- Already at goal node, just go to exact position
        return {{x = goal_x, y = goal_y, action = 'walk'}}
    end

    -- A* algorithm
    local open_set = {start_node.id}
    local came_from = {}
    local connection_used = {}

    local g_score = {}
    local f_score = {}

    for _, node in ipairs(navgraph.nodes) do
        g_score[node.id] = math.huge
        f_score[node.id] = math.huge
    end

    g_score[start_node.id] = 0
    f_score[start_node.id] = heuristic(start_node, goal_node)

    while #open_set > 0 do
        -- Find node with lowest f_score
        local current_idx = 1
        local current_id = open_set[1]
        for i, id in ipairs(open_set) do
            if f_score[id] < f_score[current_id] then
                current_idx = i
                current_id = id
            end
        end

        local current = navgraph.nodes[current_id]

        -- Reached goal?
        if current_id == goal_node.id then
            return self:reconstruct_path(came_from, connection_used, current_id, goal_x, goal_y)
        end

        -- Remove from open set
        table.remove(open_set, current_idx)

        -- Check neighbors
        for _, conn in ipairs(current.connections) do
            local neighbor_id = conn.target
            local neighbor = navgraph.nodes[neighbor_id]

            local tentative_g = g_score[current_id] + conn.cost

            if tentative_g < g_score[neighbor_id] then
                came_from[neighbor_id] = current_id
                connection_used[neighbor_id] = conn.type
                g_score[neighbor_id] = tentative_g
                f_score[neighbor_id] = tentative_g + heuristic(neighbor, goal_node)

                -- Add to open set if not already there
                local in_open = false
                for _, id in ipairs(open_set) do
                    if id == neighbor_id then
                        in_open = true
                        break
                    end
                end
                if not in_open then
                    table.insert(open_set, neighbor_id)
                end
            end
        end
    end

    -- No path found
    return nil
end

-- Reconstruct path from A* result
function Pathfinder:reconstruct_path(came_from, connection_used, goal_id, goal_x, goal_y)
    local path = {}
    local current_id = goal_id

    -- Build path backwards
    local node_path = {current_id}
    while came_from[current_id] do
        current_id = came_from[current_id]
        table.insert(node_path, 1, current_id)
    end

    -- Convert to waypoints
    for i, node_id in ipairs(node_path) do
        local node = self.navgraph.nodes[node_id]
        local action = 'walk'

        if i > 1 then
            local conn_type = connection_used[node_id]
            if conn_type == 'jump' then
                action = 'jump'
            elseif conn_type == 'climb' then
                action = 'climb'
            elseif conn_type == 'fall' then
                action = 'fall'
            end
        end

        table.insert(path, {
            x = node.x,
            y = node.y,
            action = action,
            node_id = node_id
        })
    end

    -- Add final destination
    table.insert(path, {
        x = goal_x,
        y = goal_y,
        action = 'walk'
    })

    return path
end

-- Draw the current path for debugging
function Pathfinder:draw_path(path)
    if not path or #path < 2 then
        return
    end

    love.graphics.setLineWidth(3)

    for i = 1, #path - 1 do
        local wp1 = path[i]
        local wp2 = path[i + 1]

        if wp2.action == 'walk' then
            love.graphics.setColor(0, 1, 0, 0.8)
        elseif wp2.action == 'jump' then
            love.graphics.setColor(1, 1, 0, 0.8)
        elseif wp2.action == 'climb' then
            love.graphics.setColor(0, 0.7, 1, 0.8)
        elseif wp2.action == 'fall' then
            love.graphics.setColor(1, 0.5, 0, 0.8)
        end

        love.graphics.line(wp1.x, wp1.y, wp2.x, wp2.y)
    end

    -- Draw waypoints
    for i, wp in ipairs(path) do
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle('fill', wp.x, wp.y, 6)
        love.graphics.setColor(0, 0, 0)
        love.graphics.circle('line', wp.x, wp.y, 6)

        -- Draw index
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(i, wp.x + 8, wp.y - 8)
    end

    love.graphics.setLineWidth(1)
end

return Pathfinder
