-- Worm Creature: Verlet chain-based flowing creature
local vec2 = require('lib.vec2')
local VerletChain = require('core.verlet_chain')

local Worm = {}
Worm.__index = Worm

function Worm.new(x, y, options)
    options = options or {}
    local self = setmetatable({}, Worm)

    self.segment_count = options.segment_count or 12
    self.segment_length = options.segment_length or 12
    self.move_speed = options.move_speed or 300

    -- Create the body chain
    self.chain = VerletChain.new(x, y, self.segment_count, self.segment_length, {
        friction = 0.99,
        constraint_iterations = 3
    })

    -- Head is driven by movement logic
    self.chain:get_head().pinned = true

    -- Segment sizes (decreasing from head to tail)
    self.segment_sizes = {}
    local head_size = options.head_size or 14
    local tail_size = options.tail_size or 4
    for i = 1, self.segment_count do
        local t = (i - 1) / (self.segment_count - 1)
        self.segment_sizes[i] = head_size + (tail_size - head_size) * t
    end

    -- Visual options
    self.body_color = options.body_color or {0.6, 0.8, 0.4}
    self.outline_color = options.outline_color or {0.3, 0.5, 0.2}
    self.eye_color = options.eye_color or {0.1, 0.1, 0.1}

    -- Movement state
    self.target = vec2.new(x, y)
    self.velocity = vec2.new(0, 0)
    self.is_grounded = false
    self.is_climbing = false
    self.facing_angle = 0

    -- Sound system reference (set externally)
    self.synth = nil
    self.last_y_velocity = 0  -- Track for landing impact
    self.jump_start_x = nil  -- Track horizontal position at jump start
    self.min_jump_distance = 30  -- Must move this far horizontally before landing
    self.air_time = 0  -- Track time spent in air

    return self
end

-- Get position (head position)
function Worm:get_position()
    local head = self.chain:get_head()
    return head.pos.x, head.pos.y
end

-- Get all points for collision
function Worm:get_points()
    return self.chain.points
end

-- Apply movement from controller
function Worm:apply_movement(movement, dt)
    local head = self.chain:get_head()

    if movement.type == 'walk' then
        -- Only walk if grounded, otherwise ignore (let physics handle it)
        if self.is_grounded then
            local speed = self.move_speed
            local move = vec2.mul(movement.direction, speed * dt)
            head.pos = vec2.add(head.pos, move)
            self.is_climbing = false
            self.velocity = vec2.new(0, 0)
            head.pinned = true
            -- Play sliding sound while moving
            if self.synth then
                self.synth:start_slide()
                self.synth:update_slide(dt, speed)
            end
        end
        -- If not grounded, don't pin - let physics continue

    elseif movement.type == 'jump' then
        -- Apply jump velocity - only if grounded and not already jumping
        print("[WORM] Jump requested, is_grounded=" .. tostring(self.is_grounded) .. ", head.pinned=" .. tostring(head.pinned))
        if self.is_grounded then
            self.velocity = vec2.clone(movement.velocity)
            self.is_grounded = false
            self.is_climbing = false
            head.pinned = false  -- Unpin for physics
            self.jump_start_x = head.pos.x  -- Record start position for landing check
            print("[WORM] JUMPING! velocity=" .. tostring(self.velocity))
            -- Play jump sound
            if self.synth then
                local intensity = math.min(math.abs(self.velocity.y) / 500, 1)
                self.synth:play_jump(intensity)
                self.synth:stop_slide()
            end
        else
            print("[WORM] Cannot jump - not grounded!")
        end

    elseif movement.type == 'air_control' then
        -- Gentle steering while in air (limited control)
        if not self.is_grounded then
            local air_control = 50  -- Much less than ground speed
            self.velocity.x = self.velocity.x + movement.direction.x * air_control * dt
        end

    elseif movement.type == 'climb' then
        local speed = self.move_speed * 0.6  -- Climbing is slower
        local move = vec2.mul(movement.direction, speed * dt)
        head.pos = vec2.add(head.pos, move)
        self.is_climbing = true
        self.velocity = vec2.new(0, 0)
        head.pinned = true
    end

    -- Update target for eye tracking
    if movement.target then
        self.target = movement.target
    end

    -- Stop slide sound if not walking
    if movement.type ~= 'walk' and self.synth then
        self.synth:stop_slide()
    end
end

-- Main update - now takes level for collision
function Worm:update(dt, target_pos, gravity, level)
    gravity = gravity or vec2.new(0, 980)

    local head = self.chain:get_head()

    -- Direct control mode (if no controller/level)
    if not level then
        if target_pos then
            self.target = target_pos
        end

        local direction = vec2.sub(self.target, head.pos)
        local distance = vec2.length(direction)

        if distance > 1 then
            local move = vec2.mul(vec2.normalize(direction),
                                  math.min(distance, self.move_speed * dt))
            head.pos = vec2.add(head.pos, move)
            self.facing_angle = vec2.angle(direction)
        end

        self.chain:update(dt, gravity)
        self.chain:constrain_to_ground(550, 0.3, 0.9)
        return
    end

    -- Physics mode (when jumping/falling - head is unpinned)
    if not head.pinned then
        -- Track time in air
        self.air_time = self.air_time + dt

        -- Apply gravity to velocity (proper physics: v = v + g*dt)
        self.velocity = vec2.add(self.velocity, vec2.mul(gravity, dt))

        -- Clamp velocity to terminal velocity
        local terminal_velocity = 600
        if self.velocity.y > terminal_velocity then
            self.velocity.y = terminal_velocity
        end

        -- Update position (proper physics: p = p + v*dt)
        head.pos = vec2.add(head.pos, vec2.mul(self.velocity, dt))

        -- Check for landing using surface detection (more reliable than collision)
        level:constrain_points({head})  -- Still apply collision constraints
        local on_surface = level:is_point_on_surface(head.pos.x, head.pos.y, 10)

        -- Only allow landing after moving minimum distance from jump start
        -- This prevents re-landing on the same platform we jumped from
        local can_land = true
        if self.jump_start_x then
            local dist_from_start = math.abs(head.pos.x - self.jump_start_x)
            can_land = dist_from_start >= self.min_jump_distance

            -- Time-based fallback: if in air too long, force landing
            -- This prevents getting permanently stuck
            if self.air_time > 0.5 and on_surface then
                can_land = true
            end
        end

        if on_surface and self.velocity.y >= 0 and can_land then  -- Landing (moving down or stationary)
            -- Play landing sound based on impact velocity
            if self.synth and self.last_y_velocity > 50 then
                local impact = math.min(self.last_y_velocity / 400, 1)
                self.synth:play_land(impact)
            end
            self.is_grounded = true
            self.is_climbing = false
            head.pinned = true
            self.velocity = vec2.new(0, 0)
            self.jump_start_x = nil  -- Clear jump tracking
            self.air_time = 0  -- Reset air time
            print("[WORM] Landed! is_grounded=true")
        end
        -- Track velocity for landing impact calculation
        self.last_y_velocity = self.velocity.y
    else
        -- Head is pinned - check if we should start falling (walked off edge)
        -- Use proper surface detection with tolerance
        local on_surface = level:is_point_on_surface(head.pos.x, head.pos.y, 15)

        local was_grounded = self.is_grounded
        if on_surface then
            self.is_grounded = true
        elseif self.is_grounded then
            -- Walked off edge, start falling
            self.is_grounded = false
            head.pinned = false
            self.velocity = vec2.new(0, 0)
            print("[WORM] Walked off edge, falling")
            -- Stop slide sound when falling
            if self.synth then
                self.synth:stop_slide()
            end
        end

        -- Log state changes
        if was_grounded ~= self.is_grounded then
            print("[WORM] Grounded changed: " .. tostring(was_grounded) .. " -> " .. tostring(self.is_grounded) .. " (on_surface=" .. tostring(on_surface) .. ")")
        end
    end

    -- Update physics for body segments
    local body_gravity = self.is_climbing and vec2.mul(gravity, 0.1) or gravity
    self.chain:update(dt, body_gravity)

    -- Constrain body segments to level
    level:constrain_points(self.chain.points)

    -- Update facing angle based on body direction
    local second = self.chain.points[2]
    if second then
        local dir = vec2.sub(head.pos, second.pos)
        if vec2.length(dir) > 0.1 then
            self.facing_angle = vec2.angle(dir)
        end
    end
end

function Worm:draw()
    -- Draw body segments from tail to head (so head is on top)
    for i = #self.chain.points, 1, -1 do
        local point = self.chain.points[i]
        local size = self.segment_sizes[i]

        -- Outline
        love.graphics.setColor(self.outline_color)
        love.graphics.circle('fill', point.pos.x, point.pos.y, size + 2)

        -- Body
        love.graphics.setColor(self.body_color)
        love.graphics.circle('fill', point.pos.x, point.pos.y, size)
    end

    -- Draw eyes on head
    self:draw_eyes()
end

function Worm:draw_eyes()
    local head = self.chain:get_head()
    local second = self.chain.points[2]

    -- Calculate head direction
    local dir = vec2.normalize(vec2.sub(head.pos, second.pos))
    local perp = vec2.perpendicular(dir)

    local eye_offset = 5
    local eye_size = 4
    local pupil_size = 2

    -- Eye positions
    local eye1 = vec2.add(head.pos, vec2.add(vec2.mul(dir, 3), vec2.mul(perp, eye_offset)))
    local eye2 = vec2.add(head.pos, vec2.sub(vec2.mul(dir, 3), vec2.mul(perp, eye_offset)))

    -- Look toward movement target
    local look_dir = vec2.normalize(vec2.sub(self.target, head.pos))
    local pupil_offset = vec2.mul(look_dir, 1.5)

    -- Draw eyes (white)
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle('fill', eye1.x, eye1.y, eye_size)
    love.graphics.circle('fill', eye2.x, eye2.y, eye_size)

    -- Draw pupils
    love.graphics.setColor(self.eye_color)
    love.graphics.circle('fill', eye1.x + pupil_offset.x, eye1.y + pupil_offset.y, pupil_size)
    love.graphics.circle('fill', eye2.x + pupil_offset.x, eye2.y + pupil_offset.y, pupil_size)
end

function Worm:draw_smooth()
    -- Alternative drawing using smooth curves
    love.graphics.setColor(self.outline_color)
    self.chain:draw_smooth(self.segment_sizes[1] * 2 + 4)

    love.graphics.setColor(self.body_color)
    self.chain:draw_smooth(self.segment_sizes[1] * 2)

    self:draw_eyes()
end

function Worm:draw_debug()
    self.chain:draw_debug()

    -- Draw target
    love.graphics.setColor(1, 0, 0, 0.5)
    love.graphics.circle('line', self.target.x, self.target.y, 10)
    love.graphics.line(self.target.x - 5, self.target.y, self.target.x + 5, self.target.y)
    love.graphics.line(self.target.x, self.target.y - 5, self.target.x, self.target.y + 5)

    -- Draw state
    local x, y = self:get_position()
    love.graphics.setColor(1, 1, 1, 0.8)
    local state = self.is_grounded and "grounded" or (self.is_climbing and "climbing" or "air")
    love.graphics.print("State: " .. state, x + 20, y - 50)
end

function Worm:reset(x, y)
    x = x or 400
    y = y or 300

    for i, point in ipairs(self.chain.points) do
        point:set_position(x, y + (i - 1) * self.segment_length)
    end

    self.chain:get_head().pinned = true
    self.velocity = vec2.new(0, 0)
    self.is_grounded = false
    self.is_climbing = false
    self.target = vec2.new(x, y)
end

function Worm:get_name()
    return "Verlet Worm"
end

function Worm:get_description()
    return "Chain of verlet-integrated points with distance constraints"
end

return Worm
