-- Particles: small consequences of things happening.
--
-- Listens to world events: landings kick up dust (and pebbles when hard),
-- jumps puff, spider feet tick dust, mushrooms breathe out glowing spores,
-- and drips splash with a ripple.

local P = require('world.render.palette')

local Particles = {}
Particles.__index = Particles

local sin, cos, min, max, pi = math.sin, math.cos, math.min, math.max, math.pi

function Particles.new()
    local self = setmetatable({}, Particles)
    self.list = {}
    self.rings = {}
    self.gen = love.math.newRandomGenerator(4242)
    return self
end

function Particles:r(a, b) return a + self.gen:random() * (b - a) end

function Particles:add(p)
    p.age = 0
    self.list[#self.list + 1] = p
    if #self.list > 600 then table.remove(self.list, 1) end
end

function Particles:dust(x, y, count, power, color)
    color = color or {0.66, 0.58, 0.58}
    for i = 1, count do
        local side = (i % 2 == 0) and 1 or -1
        self:add({
            kind = 'dust', x = x + self:r(-6, 6), y = y - self:r(0, 3),
            vx = side * self:r(20, 120) * power, vy = -self:r(10, 70) * power,
            g = 90, drag = 3.2, life = self:r(0.45, 0.95), size = self:r(1.4, 3.2),
            grow = self:r(2, 5), color = color, alpha = 0.55,
        })
    end
end

function Particles:on_event(ev)
    if ev.kind == 'land' then
        local impact = ev.impact or 0
        if impact > 140 then
            local power = min(1.6, impact / 450)
            self:dust(ev.x, ev.y, math.floor(4 + power * 10), power)
            if impact > 520 then
                for i = 1, 3 do
                    self:add({kind = 'pebble', x = ev.x + self:r(-8, 8), y = ev.y - 2,
                        vx = self:r(-90, 90), vy = -self:r(80, 200), g = 900, drag = 0.5,
                        life = self:r(0.4, 0.7), size = self:r(0.9, 1.6), color = {0.22, 0.18, 0.24}, alpha = 1})
                end
            end
        end
    elseif ev.kind == 'jump' then
        self:dust(ev.x, ev.y, 5, 0.5)
    elseif ev.kind == 'step' then
        if ev.near and self.gen:random() < 0.25 then self:dust(ev.x, ev.y, 1, 0.25) end
    elseif ev.kind == 'spores' then
        for i = 1, ev.n or 6 do
            self:add({kind = 'spore', x = ev.x + self:r(-4, 4), y = ev.y + self:r(-2, 2),
                vx = self:r(-12, 12), vy = -self:r(8, 26), g = -4, drag = 0.6,
                life = self:r(1.8, 3.2), size = self:r(0.7, 1.4), color = P.shroom, alpha = 0.9,
                phase = self:r(0, 6)})
        end
    elseif ev.kind == 'splash' then
        for i = 1, 6 do
            self:add({kind = 'drop', x = ev.x, y = ev.y - 1, vx = self:r(-50, 50), vy = -self:r(60, 150),
                g = 900, drag = 0.2, life = self:r(0.25, 0.45), size = self:r(0.6, 1.1), color = P.water, alpha = 0.9})
        end
        self.rings[#self.rings + 1] = {x = ev.x, y = ev.y - 0.5, age = 0, life = 0.6}
    end
end

function Particles:update(dt)
    for i = #self.list, 1, -1 do
        local p = self.list[i]
        p.age = p.age + dt
        if p.age >= p.life then
            table.remove(self.list, i)
        else
            p.vy = p.vy + p.g * dt
            local d = max(0, 1 - p.drag * dt)
            p.vx, p.vy = p.vx * d, p.vy * d
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            if p.kind == 'spore' then p.x = p.x + sin(p.age * 3 + p.phase) * 6 * dt end
        end
    end
    for i = #self.rings, 1, -1 do
        local r = self.rings[i]
        r.age = r.age + dt
        if r.age >= r.life then table.remove(self.rings, i) end
    end
end

-- Lit particles (drawn before the light map is applied)
function Particles:draw()
    for _, p in ipairs(self.list) do
        if p.kind ~= 'spore' then
            local t = p.age / p.life
            local a = p.alpha * (1 - t) * (p.kind == 'dust' and (1 - t * 0.3) or 1)
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
            local s = p.size + (p.grow or 0) * t
            if p.kind == 'drop' then
                love.graphics.ellipse('fill', p.x, p.y, s * 0.8, s * 1.4)
            else
                love.graphics.circle('fill', p.x, p.y, s)
            end
        end
    end
    for _, r in ipairs(self.rings) do
        local t = r.age / r.life
        love.graphics.setColor(P.water[1], P.water[2], P.water[3], 0.6 * (1 - t))
        love.graphics.ellipse('line', r.x, r.y, 2 + t * 12, 0.6 + t * 1.8)
    end
end

-- Emissive particles (after the light map)
function Particles:draw_glow(lighting)
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    for _, p in ipairs(self.list) do
        if p.kind == 'spore' then
            local t = p.age / p.life
            local a = (t < 0.15 and t / 0.15 or 1 - (t - 0.15) / 0.85)
            lighting:glow(p.x, p.y, 7, p.color[1], p.color[2], p.color[3], 0.25 * a)
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], 0.9 * a)
            love.graphics.circle('fill', p.x, p.y, p.size)
        end
    end
    love.graphics.pop()
end

function Particles:add_lights(lighting)
    for _, p in ipairs(self.list) do
        if p.kind == 'spore' then
            lighting:add(p.x, p.y, P.shroom[1], P.shroom[2], P.shroom[3], 16, 0.2)
        end
    end
end

return Particles
