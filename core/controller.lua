-- Controller: Handles autonomous creature movement along paths
local vec2 = require('lib.vec2')

local Controller = {}
Controller.__index = Controller

function Controller.new(pathfinder)
    local self = setmetatable({}, Controller)

    self.pathfinder = pathfinder
    self.path = nil
    self.current_waypoint = 1
    self.target = nil

    -- Movement parameters (can be overridden per creature)
    self.walk_speed = 200
    self.climb_speed = 150
    self.waypoint_threshold = 40  -- How close to get before moving to next waypoint
    self.jump_threshold = 50  -- How close before initiating jump

    -- Jump constraints (tuned for precision)
    self.max_jump_velocity = 280  -- Max initial upward velocity
    self.max_horizontal_jump_speed = 90  -- Max horizontal speed during jump

    -- State
    self.state = 'idle'  -- idle, walking, jumping, climbing, falling
    self.jump_cooldown = 0
    self.is_grounded = false

    return self
end

-- Set a new destination and calculate path
function Controller:set_destination(x, y, from_x, from_y)
    self.path = self.pathfinder:find_path(from_x, from_y, x, y)
    self.current_waypoint = 1
    self.target = {x = x, y = y}

    if self.path and #self.path > 0 then
        -- Skip first waypoint if we're already close to it
        local first = self.path[1]
        local dx = first.x - from_x
        local dy = first.y - from_y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < self.waypoint_threshold and #self.path > 1 then
            self.current_waypoint = 2
        end

        self.state = 'walking'
        return true
    else
        self.state = 'idle'
        return false
    end
end

-- Clear current path
function Controller:clear_path()
    self.path = nil
    self.current_waypoint = 1
    self.target = nil
    self.state = 'idle'
end

-- Get the current target position for the creature to move toward
-- Returns: target_pos (vec2), action (string), reached_destination (bool)
function Controller:get_movement_target(current_x, current_y, dt)
    if not self.path or self.current_waypoint > #self.path then
        return nil, 'idle', true
    end

    -- Update cooldowns
    if self.jump_cooldown > 0 then
        self.jump_cooldown = self.jump_cooldown - dt
    end

    local wp = self.path[self.current_waypoint]
    local dx = wp.x - current_x
    local dy = wp.y - current_y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Check if path has become invalid (e.g., fell off platform)
    -- If action is "walk" but waypoint is far above us, path is broken
    if wp.action == 'walk' and dy < -50 then  -- waypoint is 50+ pixels above us
        print("[CONTROLLER] Path invalid - walk waypoint too far above, attempting repath")
        -- Try to recalculate path to original destination
        if self.target then
            local new_path = self.pathfinder:find_path(current_x, current_y, self.target.x, self.target.y)
            if new_path and #new_path > 0 then
                self.path = new_path
                self.current_waypoint = 1
                print("[CONTROLLER] Repath successful, new path has " .. #new_path .. " waypoints")
                -- Get the new waypoint and continue
                wp = self.path[self.current_waypoint]
                dx = wp.x - current_x
                dy = wp.y - current_y
            else
                print("[CONTROLLER] Repath failed, clearing path")
                self:clear_path()
                return nil, 'idle', false
            end
        else
            self:clear_path()
            return nil, 'idle', false
        end
    end

    -- Check if we've reached the current waypoint
    local threshold = self.waypoint_threshold
    local vertical_threshold = 30  -- Must be within this vertical distance
    if wp.action == 'jump' then
        threshold = self.jump_threshold
        vertical_threshold = 60  -- More lenient for jumps (might be in air)
    elseif wp.action == 'fall' then
        vertical_threshold = 80  -- Most lenient for falls
    end

    -- Must be within BOTH horizontal threshold AND vertical threshold
    -- This prevents "reaching" waypoints by passing under/over them
    local horizontal_dist = math.abs(dx)
    local vertical_dist = math.abs(dy)
    local reached_waypoint = (horizontal_dist < threshold) and (vertical_dist < vertical_threshold)

    if reached_waypoint then
        -- Move to next waypoint
        self.current_waypoint = self.current_waypoint + 1

        if self.current_waypoint > #self.path then
            -- Reached destination
            self.state = 'idle'
            return vec2.new(wp.x, wp.y), 'idle', true
        end

        wp = self.path[self.current_waypoint]
    end

    -- Determine action
    local action = wp.action
    self.state = action

    return vec2.new(wp.x, wp.y), action, false
end

-- Calculate movement force/velocity for a creature based on action
-- Returns a table with movement instructions
function Controller:calculate_movement(current_pos, target_pos, action, is_grounded, dt)
    if not target_pos then
        return {
            type = 'none',
            direction = vec2.new(0, 0)
        }
    end

    local direction = vec2.sub(target_pos, current_pos)
    local dist = vec2.length(direction)

    if dist > 0 then
        direction = vec2.normalize(direction)
    end

    if action == 'walk' then
        -- Ensure we have horizontal movement even if target is mostly above/below
        local horiz_dir = direction.x
        if math.abs(horiz_dir) < 0.1 and dist > 5 then
            -- Target is almost directly above/below, pick a direction based on target x
            horiz_dir = target_pos.x > current_pos.x and 1 or -1
        end
        return {
            type = 'walk',
            direction = vec2.new(horiz_dir > 0 and 1 or (horiz_dir < 0 and -1 or 0), 0),
            speed = self.walk_speed,
            target = target_pos
        }
    elseif action == 'jump' then
        if is_grounded and self.jump_cooldown <= 0 then
            -- Calculate jump velocity needed
            local jump_vel = self:calculate_jump_velocity(current_pos, target_pos)
            self.jump_cooldown = 0.5
            return {
                type = 'jump',
                velocity = jump_vel,
                target = target_pos
            }
        else
            -- In air, steer toward target
            return {
                type = 'air_control',
                direction = vec2.new(direction.x, 0),
                speed = self.walk_speed * 0.5,
                target = target_pos
            }
        end
    elseif action == 'climb' then
        return {
            type = 'climb',
            direction = direction,
            speed = self.climb_speed,
            target = target_pos
        }
    elseif action == 'fall' then
        if is_grounded then
            -- Need to walk off the edge first before we can fall
            local horiz_dir = direction.x > 0 and 1 or -1
            return {
                type = 'walk',
                direction = vec2.new(horiz_dir, 0),
                speed = self.walk_speed,
                target = target_pos
            }
        else
            -- Already in air, steer horizontally while falling
            return {
                type = 'air_control',
                direction = vec2.new(direction.x, 0),
                speed = self.walk_speed * 0.3,
                target = target_pos
            }
        end
    end

    return {
        type = 'none',
        direction = vec2.new(0, 0)
    }
end

-- Calculate jump velocity to reach target (constrained by max force)
function Controller:calculate_jump_velocity(from_pos, to_pos)
    local dx = to_pos.x - from_pos.x
    local dy = to_pos.y - from_pos.y

    -- Determine jump direction
    local dir_x = dx > 0 and 1 or -1

    -- Calculate horizontal velocity - scale based on distance but don't overshoot
    -- Use a gentler multiplier and account for air time
    local horizontal_factor = 0.6  -- Halved for tighter landings
    local vx = math.min(math.abs(dx) * horizontal_factor, self.max_horizontal_jump_speed) * dir_x

    -- Calculate vertical velocity based on whether we need to go up or down
    local vy
    if dy < 0 then
        -- Need to jump up - use max jump velocity scaled by height needed
        local height_needed = math.abs(dy)
        local max_height = (self.max_jump_velocity * self.max_jump_velocity) / (2 * 980)  -- v²/2g
        local height_ratio = math.min(height_needed / max_height, 1)
        -- Scale more precisely - sqrt gives better feel for smaller jumps
        vy = -self.max_jump_velocity * math.max(math.sqrt(height_ratio), 0.3)
    else
        -- Jumping down/across - minimal hop, let gravity do the work
        vy = -self.max_jump_velocity * 0.15
    end

    return vec2.new(vx, vy)
end

-- Check if there's an active path
function Controller:has_path()
    return self.path ~= nil and self.current_waypoint <= #self.path
end

-- Get current path for drawing
function Controller:get_path()
    return self.path
end

-- Draw debug info
function Controller:draw_debug(current_x, current_y)
    if self.path then
        self.pathfinder:draw_path(self.path)

        -- Highlight current waypoint
        if self.current_waypoint <= #self.path then
            local wp = self.path[self.current_waypoint]
            love.graphics.setColor(1, 0, 1, 0.8)
            love.graphics.circle('line', wp.x, wp.y, 15)

            -- Draw line from creature to current waypoint
            love.graphics.setColor(1, 0, 1, 0.5)
            love.graphics.line(current_x, current_y, wp.x, wp.y)
        end
    end

    -- Draw state
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print("State: " .. self.state, current_x + 20, current_y - 30)
end

return Controller
