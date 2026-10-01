-- Blob Creature: Spring-damper based squishy creature
local vec2 = require('lib.vec2')
local VerletPoint = require('core.verlet_point')
local Spring = require('core.spring')

local Blob = {}
Blob.__index = Blob

function Blob.new(x, y, options)
    options = options or {}
    local self = setmetatable({}, Blob)

    self.outer_count = options.outer_count or 8
    self.radius = options.radius or 40
    self.stiffness = options.stiffness or 400
    self.damping = options.damping or 12
    self.move_speed = options.move_speed or 250

    -- Visual options
    self.body_color = options.body_color or {0.4, 0.6, 0.9}
    self.outline_color = options.outline_color or {0.2, 0.3, 0.6}
    self.eye_color = options.eye_color or {0.1, 0.1, 0.1}

    -- Create center point
    self.center = VerletPoint.new(x, y, {
        friction = 0.99,
        mass = 1,
        radius = 8
    })

    -- Create outer points in a circle
    self.outer_points = {}
    for i = 1, self.outer_count do
        local angle = (i - 1) * (2 * math.pi / self.outer_count)
        local px = x + math.cos(angle) * self.radius
        local py = y + math.sin(angle) * self.radius
        local point = VerletPoint.new(px, py, {
            friction = 0.99,
            mass = 0.3,
            radius = 6
        })
        table.insert(self.outer_points, point)
    end

    -- Create springs: center to outer
    self.radial_springs = {}
    for _, point in ipairs(self.outer_points) do
        local spring = Spring.new(self.center, point, {
            stiffness = self.stiffness,
            damping = self.damping,
            rest_length = self.radius
        })
        table.insert(self.radial_springs, spring)
    end

    -- Create springs: outer to outer (structural)
    self.structural_springs = {}
    for i = 1, self.outer_count do
        local next_i = (i % self.outer_count) + 1
        local point_a = self.outer_points[i]
        local point_b = self.outer_points[next_i]

        local angle_diff = 2 * math.pi / self.outer_count
        local rest_len = 2 * self.radius * math.sin(angle_diff / 2)

        local spring = Spring.new(point_a, point_b, {
            stiffness = self.stiffness * 0.8,
            damping = self.damping * 0.8,
            rest_length = rest_len
        })
        table.insert(self.structural_springs, spring)
    end

    -- Create cross springs for more stability
    self.cross_springs = {}
    if self.outer_count >= 6 then
        for i = 1, self.outer_count do
            local skip_i = ((i + 1) % self.outer_count) + 1
            local point_a = self.outer_points[i]
            local point_b = self.outer_points[skip_i]

            local spring = Spring.new(point_a, point_b, {
                stiffness = self.stiffness * 0.4,
                damping = self.damping * 0.5
            })
            table.insert(self.cross_springs, spring)
        end
    end

    -- Movement state
    self.target = vec2.new(x, y)
    self.velocity = vec2.new(0, 0)
    self.is_grounded = false
    self.is_climbing = false

    -- Sound system reference (set externally)
    self.synth = nil
    self.was_grounded = false  -- Track for landing detection
    self.jump_start_x = nil  -- Track horizontal position at jump start
    self.min_jump_distance = 30  -- Must move this far horizontally before landing
    self.air_time = 0  -- Track time spent in air

    return self
end

-- Get position (center position)
function Blob:get_position()
    return self.center.pos.x, self.center.pos.y
end

-- Get all points for collision
function Blob:get_points()
    local points = {self.center}
    for _, p in ipairs(self.outer_points) do
        table.insert(points, p)
    end
    return points
end

-- Apply movement from controller
function Blob:apply_movement(movement, dt)
    if movement.type == 'walk' then
        local force = vec2.mul(movement.direction, self.move_speed * 4)
        self.center:apply_force(force)
        self.is_climbing = false
        -- Play sliding sound while moving on ground
        if self.is_grounded and self.synth then
            self.synth:start_slide()
            self.synth:update_slide(dt, self.move_speed)
        end

    elseif movement.type == 'jump' then
        -- Apply jump as velocity to all points - only if grounded
        if self.is_grounded then
            self.is_grounded = false
            self.is_climbing = false
            self.jump_start_x = self.center.pos.x  -- Record start position for landing check
            -- Give initial impulse to all points (scaled down for soft body)
            local impulse = vec2.mul(movement.velocity, 0.3)
            self.center:set_velocity(impulse)
            for _, point in ipairs(self.outer_points) do
                point:set_velocity(vec2.mul(impulse, 0.8 + math.random() * 0.4))
            end
            -- Play jump sound
            if self.synth then
                local intensity = math.min(vec2.length(impulse) / 150, 1)
                self.synth:play_jump(intensity)
                self.synth:stop_slide()
            end
        end

    elseif movement.type == 'air_control' then
        -- Limited air control
        local force = vec2.mul(movement.direction, self.move_speed * 0.5)
        self.center:apply_force(force)

    elseif movement.type == 'climb' then
        local force = vec2.mul(movement.direction, self.move_speed * 2)
        self.center:apply_force(force)
        self.is_climbing = true
    end

    if movement.target then
        self.target = movement.target
    end

    -- Stop slide sound if not walking
    if movement.type ~= 'walk' and self.synth then
        self.synth:stop_slide()
    end
end

-- Main update - now takes level for collision
function Blob:update(dt, target_pos, gravity, level)
    gravity = gravity or vec2.new(0, 980)

    -- Direct control mode (if no level)
    if not level then
        if target_pos then
            self.target = target_pos
        end

        local to_target = vec2.sub(self.target, self.center.pos)
        local distance = vec2.length(to_target)
        if distance > 1 then
            local follow_force = vec2.mul(to_target, 80)
            self.center:apply_force(follow_force)
        end

        -- Apply spring forces
        for _, spring in ipairs(self.radial_springs) do
            spring:apply_forces()
        end
        for _, spring in ipairs(self.structural_springs) do
            spring:apply_forces()
        end
        for _, spring in ipairs(self.cross_springs) do
            spring:apply_forces()
        end

        -- Update all points
        self.center:update(dt, gravity)
        for _, point in ipairs(self.outer_points) do
            point:update(dt, gravity)
        end

        -- Ground collision
        self.center:constrain_to_ground(550 - 10, 0.4, 0.9)
        for _, point in ipairs(self.outer_points) do
            point:constrain_to_ground(550, 0.5, 0.85)
        end
        return
    end

    -- Apply spring forces
    for _, spring in ipairs(self.radial_springs) do
        spring:apply_forces()
    end
    for _, spring in ipairs(self.structural_springs) do
        spring:apply_forces()
    end
    for _, spring in ipairs(self.cross_springs) do
        spring:apply_forces()
    end

    -- Apply gravity (reduced when climbing)
    local effective_gravity = self.is_climbing and vec2.mul(gravity, 0.2) or gravity

    -- Update all points
    self.center:update(dt, effective_gravity)
    for _, point in ipairs(self.outer_points) do
        point:update(dt, effective_gravity)
    end

    -- Level collision
    local all_points = self:get_points()
    local contacts = level:constrain_points(all_points)

    -- Check grounded state using proper surface detection
    local center_on_surface = level:is_point_on_surface(self.center.pos.x, self.center.pos.y, 20)
    local now_grounded = false

    -- Track time in air
    if not self.is_grounded then
        self.air_time = self.air_time + dt
    end

    -- Only allow landing after moving minimum distance from jump start
    local can_land = true
    if self.jump_start_x then
        local dist_from_start = math.abs(self.center.pos.x - self.jump_start_x)
        can_land = dist_from_start >= self.min_jump_distance

        -- Time-based fallback: if in air too long, force landing
        if self.air_time > 0.5 and center_on_surface then
            can_land = true
        end
    end

    if can_land then
        if center_on_surface then
            now_grounded = true
        else
            -- Check if any outer point is grounded
            for _, point in ipairs(self.outer_points) do
                if level:is_point_on_surface(point.pos.x, point.pos.y, 10) then
                    now_grounded = true
                    break
                end
            end
        end
    end

    -- Detect landing (transition from air to ground)
    if now_grounded and not self.was_grounded then
        -- Calculate impact from center velocity
        local vel = self.center:get_velocity()
        if self.synth and vel.y > 30 then
            local impact = math.min(vel.y / 300, 1)
            self.synth:play_land(impact)
        end
        self.jump_start_x = nil  -- Clear jump tracking
        self.air_time = 0  -- Reset air time
    end

    self.was_grounded = self.is_grounded
    self.is_grounded = now_grounded
    self.is_climbing = false
end

function Blob:draw()
    -- Draw body as filled polygon
    local points = {}
    for _, point in ipairs(self.outer_points) do
        table.insert(points, point.pos.x)
        table.insert(points, point.pos.y)
    end

    -- Fill
    love.graphics.setColor(self.body_color)
    if #points >= 6 then
        love.graphics.polygon('fill', points)
    end

    -- Outline
    love.graphics.setColor(self.outline_color)
    love.graphics.setLineWidth(3)
    if #points >= 6 then
        table.insert(points, points[1])
        table.insert(points, points[2])
        love.graphics.line(points)
    end
    love.graphics.setLineWidth(1)

    -- Draw eyes
    self:draw_eyes()
end

function Blob:draw_eyes()
    local center = self.center.pos
    local vel = self.center:get_velocity()

    local look_dir
    if vec2.length(vel) > 2 then
        look_dir = vec2.normalize(vel)
    else
        look_dir = vec2.normalize(vec2.sub(self.target, center))
    end

    local eye_offset = 12
    local eye_size = 8
    local pupil_size = 4
    local perp = vec2.perpendicular(look_dir)

    local eye1 = vec2.add(center, vec2.add(vec2.mul(look_dir, 5), vec2.mul(perp, eye_offset)))
    local eye2 = vec2.add(center, vec2.sub(vec2.mul(look_dir, 5), vec2.mul(perp, eye_offset)))

    local pupil_offset = vec2.mul(look_dir, 2)

    love.graphics.setColor(1, 1, 1)
    love.graphics.circle('fill', eye1.x, eye1.y, eye_size)
    love.graphics.circle('fill', eye2.x, eye2.y, eye_size)

    love.graphics.setColor(self.eye_color)
    love.graphics.circle('fill', eye1.x + pupil_offset.x, eye1.y + pupil_offset.y, pupil_size)
    love.graphics.circle('fill', eye2.x + pupil_offset.x, eye2.y + pupil_offset.y, pupil_size)
end

function Blob:draw_debug()
    -- Draw springs
    love.graphics.setLineWidth(1)

    love.graphics.setColor(0.8, 0.4, 0.4, 0.7)
    for _, spring in ipairs(self.radial_springs) do
        spring:draw()
    end

    love.graphics.setColor(0.4, 0.8, 0.4, 0.7)
    for _, spring in ipairs(self.structural_springs) do
        spring:draw()
    end

    love.graphics.setColor(0.4, 0.4, 0.8, 0.5)
    for _, spring in ipairs(self.cross_springs) do
        spring:draw()
    end

    self.center:draw_debug()
    for i, point in ipairs(self.outer_points) do
        point:draw_debug()
        love.graphics.setColor(1, 1, 0)
        love.graphics.print(i, point.pos.x + 8, point.pos.y - 8)
    end

    love.graphics.setColor(1, 0, 0, 0.5)
    love.graphics.circle('line', self.target.x, self.target.y, 10)

    -- Draw state
    local x, y = self:get_position()
    love.graphics.setColor(1, 1, 1, 0.8)
    local state = self.is_grounded and "grounded" or (self.is_climbing and "climbing" or "air")
    love.graphics.print("State: " .. state, x + 50, y - 30)
end

function Blob:reset(x, y)
    x = x or 400
    y = y or 300

    self.center:set_position(x, y)
    for i, point in ipairs(self.outer_points) do
        local angle = (i - 1) * (2 * math.pi / self.outer_count)
        local px = x + math.cos(angle) * self.radius
        local py = y + math.sin(angle) * self.radius
        point:set_position(px, py)
    end

    self.velocity = vec2.new(0, 0)
    self.is_grounded = false
    self.is_climbing = false
    self.target = vec2.new(x, y)
end

function Blob:get_name()
    return "Spring Blob"
end

function Blob:get_description()
    return "Spring-damper soft body with radial and structural springs"
end

return Blob
