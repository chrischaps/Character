-- Ambience: the small living things of the cave.
--
--   fireflies  drift on slow noise, scatter from creatures, blink warm
--   drips      beads swell on stalactite tips, fall, and splash
--   motes      dust that only shows where the shafts of light catch it

local P = require('world.render.palette')

local Ambience = {}
Ambience.__index = Ambience

local sin, cos, sqrt, abs, min, max, pi = math.sin, math.cos, math.sqrt, math.abs, math.min, math.max, math.pi
local noise = love.math.noise

function Ambience.new(level, world)
    local self = setmetatable({}, Ambience)
    self.level = level
    self.world = world
    local gen = love.math.newRandomGenerator((level.data.seed or 1) * 313)
    self.gen = gen
    local W, H = level.width, level.height

    self.flies = {}
    for i = 1, 16 do
        local x, y
        repeat
            x, y = 60 + gen:random() * (W - 120), 70 + gen:random() * (H - 180)
        until not level:solid_at(x, y, 6)
        self.flies[i] = {x = x, y = y, vx = 0, vy = 0, seed = gen:random() * 100, phase = gen:random() * 6,
            rate = 0.6 + gen:random() * 0.8}
    end

    self.drips = {}
    for _, st in ipairs(level.data.stalactites or {}) do
        if st.drip then
            self.drips[#self.drips + 1] = {x = st.x, tip = st.y + st.len, grow = gen:random(),
                rate = 0.25 + gen:random() * 0.3, falling = nil}
        end
    end

    self.motes = {}
    for i = 1, 90 do
        self.motes[i] = {x = gen:random() * W, y = gen:random() * H, s = 0.5 + gen:random() * 1.2,
            vx = (gen:random() - 0.5) * 4, vy = 2 + gen:random() * 5, phase = gen:random() * 6}
    end
    return self
end

function Ambience:update(dt, world)
    local level = self.level
    local influencers = world:influencers()
    local t = world.time

    -- Fireflies: wander on noise, flee creatures, avoid stone
    for _, f in ipairs(self.flies) do
        local ax = (noise(f.seed, t * 0.15) - 0.5) * 140
        local ay = (noise(f.seed + 50, t * 0.15) - 0.5) * 110
        for _, inf in ipairs(influencers) do
            local dx, dy = f.x - inf.x, f.y - inf.y
            local d2 = dx * dx + dy * dy
            local r = inf.r + 46
            if d2 < r * r and d2 > 1 then
                local d = sqrt(d2)
                local k = (1 - d / r) * 600
                ax, ay = ax + dx / d * k, ay + dy / d * k
            end
        end
        -- Keep to open air inside the cave
        if f.y < 80 then ay = ay + 60 end
        if f.y > level.height - 110 then ay = ay - 60 end
        if f.x < 50 then ax = ax + 60 end
        if f.x > level.width - 50 then ax = ax - 60 end
        f.vx = (f.vx + ax * dt) * (1 - dt * 1.2)
        f.vy = (f.vy + ay * dt) * (1 - dt * 1.2)
        local sp = sqrt(f.vx * f.vx + f.vy * f.vy)
        if sp > 70 then f.vx, f.vy = f.vx / sp * 70, f.vy / sp * 70 end
        local nx, ny = f.x + f.vx * dt, f.y + f.vy * dt
        if level:solid_at(nx, ny, 4) then
            f.vx, f.vy = -f.vx, -f.vy
        else
            f.x, f.y = nx, ny
        end
    end

    -- Drips
    for _, d in ipairs(self.drips) do
        if d.falling then
            local fl = d.falling
            fl.vy = fl.vy + 900 * dt
            local ny = fl.y + fl.vy * dt
            local hit = level:raycast(d.x, fl.y, 0, 1, ny - fl.y + 1)
            if hit then
                world.events:emit('splash', {x = d.x, y = fl.y + hit, speed = fl.vy})
                d.falling = nil
                d.grow = 0
            else
                fl.y = ny
            end
        else
            d.grow = d.grow + dt * d.rate
            if d.grow >= 1 then
                d.falling = {y = d.tip + 2, vy = 0}
            end
        end
    end

    -- Motes drift and wrap
    local W, H = level.width, level.height
    for _, m in ipairs(self.motes) do
        m.x = m.x + (m.vx + sin(t * 0.5 + m.phase) * 3) * dt
        m.y = m.y + m.vy * dt
        if m.y > H then m.y = 0 end
        if m.x < 0 then m.x = W elseif m.x > W then m.x = 0 end
    end
end

function Ambience:add_lights(lighting, time)
    for _, f in ipairs(self.flies) do
        local b = self:blink(f, time)
        if b > 0.05 then
            lighting:add(f.x, f.y, P.firefly[1], P.firefly[2], P.firefly[3], 30, 0.35 * b)
        end
    end
end

function Ambience:blink(f, time)
    local v = sin(time * f.rate + f.phase)
    return max(0, v) ^ 0.6
end

-- Water drops: drawn in the lit scene (they catch the light)
function Ambience:draw(time)
    for _, d in ipairs(self.drips) do
        if d.falling then
            love.graphics.setColor(P.water[1], P.water[2], P.water[3], 0.85)
            love.graphics.ellipse('fill', d.x, d.falling.y, 1.2, 2.4)
        else
            local r = 0.4 + d.grow * 1.6
            love.graphics.setColor(P.water[1], P.water[2], P.water[3], 0.75)
            love.graphics.circle('fill', d.x, d.tip + r * 0.8, r)
        end
    end
end

-- Emissive: fireflies, glinting drops and motes in the shafts
function Ambience:draw_glow(lighting, time)
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    for _, f in ipairs(self.flies) do
        local b = self:blink(f, time)
        lighting:glow(f.x, f.y, 14, P.firefly[1], P.firefly[2], P.firefly[3], 0.35 * b + 0.04)
        love.graphics.setColor(P.firefly[1], P.firefly[2], P.firefly[3], 0.25 + 0.75 * b)
        love.graphics.circle('fill', f.x, f.y, 1.3)
    end
    for _, d in ipairs(self.drips) do
        local y = d.falling and d.falling.y or (d.tip + d.grow * 1.3)
        love.graphics.setColor(1, 0.95, 0.85, 0.35)
        love.graphics.circle('fill', d.x - 0.4, y - 0.6, 0.6)
    end
    for _, m in ipairs(self.motes) do
        local s = lighting:ray_strength(m.x, m.y, time)
        if s > 0.02 then
            local tw = 0.6 + 0.4 * sin(time * 2 + m.phase)
            love.graphics.setColor(1, 0.88, 0.7, s * tw * 0.9)
            love.graphics.circle('fill', m.x, m.y, m.s)
        end
    end
    love.graphics.pop()
end

return Ambience
