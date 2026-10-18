-- Flora: the cave's plants, all of which notice the creatures.
--
--   vines     LoveLibs verlet chains hanging from undersides; creatures brush
--             them aside and they swing back in the cave's draught
--   grass     spring blades on every mossy top; they lean away underfoot
--   mushrooms glowing caps that squash when stepped on, flare, and puff spores

local Verlet = require('LoveLibs.physics.verlet')
local P = require('world.render.palette')

local Flora = {}
Flora.__index = Flora

local sin, cos, sqrt, abs, min, max, pi = math.sin, math.cos, math.sqrt, math.abs, math.min, math.max, math.pi
local noise = love.math.noise

function Flora.new(level, world)
    local self = setmetatable({}, Flora)
    self.level = level
    self.world = world
    local gen = love.math.newRandomGenerator((level.data.seed or 1) * 71)
    self.gen = gen

    -- Vines
    self.vines = {}
    for _, v in ipairs(level.data.vines or {}) do
        local seg = 8 + gen:random() * 2
        local chain = Verlet.Chain(v.x, v.y, v.n, seg, {friction = 0.996, radius = 2, constraint_iterations = 4})
        chain:get_head().pinned = true
        local leaves = {}
        for i = 2, v.n do
            if gen:random() < 0.8 then
                leaves[#leaves + 1] = {i = i, side = (i % 2 == 0) and 1 or -1,
                    size = 3.5 + gen:random() * 3, tilt = (gen:random() - 0.5) * 0.6}
            end
        end
        self.vines[#self.vines + 1] = {chain = chain, leaves = leaves, phase = gen:random() * 6,
            flower = gen:random() < 0.35}
    end

    -- Grass on every mossy top
    self.blades = {}
    for _, span in ipairs(level:top_spans()) do
        if span.solid.moss then
            local x = span.x0 + 2
            while x < span.x1 - 2 do
                local h = 5 + noise(x * 0.05, 3.3) * 10 + gen:random() * 4
                if noise(x * 0.02, 7.7) > 0.35 then
                    self.blades[#self.blades + 1] = {
                        x = x, y = span.y - 0.5, h = h, w = 1.2 + gen:random() * 1.1,
                        rest = (gen:random() - 0.5) * 0.35, ang = 0, vel = 0,
                        front = gen:random() < 0.28, shade = gen:random(),
                    }
                end
                x = x + 2.2 + gen:random() * 2.6
            end
        end
    end

    -- Mushroom clusters
    self.shrooms = {}
    for _, cl in ipairs(level.data.mushrooms or {}) do
        local s = level.by_id[cl.solid]
        for k = 1, cl.n do
            local x = cl.x + (k - (cl.n + 1) / 2) * (7 + gen:random() * 4)
            local h = 7 + gen:random() * 9
            self.shrooms[#self.shrooms + 1] = {
                x = x, y = s.y, h = h, r = 3.2 + h * 0.28, lean = (gen:random() - 0.5) * 0.4,
                squash = 0, vel = 0, flare = 0, phase = gen:random() * 6, touched = false,
            }
        end
    end
    return self
end

function Flora:update(dt, influencers, time)
    local gravity = {x = 0, y = 600}

    -- Vines: draught, gravity, then get pushed out of creatures
    for _, v in ipairs(self.vines) do
        local chain = v.chain
        for i, p in ipairs(chain.points) do
            if i > 1 then
                local wind = (noise(time * 0.25 + v.phase, i * 0.1) - 0.5) * 120 + sin(time * 0.6 + v.phase) * 25
                p:apply_force({x = wind, y = 0})
            end
        end
        chain:update(dt, gravity)
        for i, p in ipairs(chain.points) do
            if i > 1 then
                for _, inf in ipairs(influencers) do
                    local dx, dy = p.pos.x - inf.x, p.pos.y - inf.y
                    local d2 = dx * dx + dy * dy
                    local r = inf.r + 3
                    if d2 < r * r and d2 > 1e-4 then
                        local d = sqrt(d2)
                        local push = (r - d) / d
                        p.pos.x, p.pos.y = p.pos.x + dx * push, p.pos.y + dy * push
                        -- carry a little of the creature's motion
                        p.old_pos.x = p.old_pos.x - (inf.vx or 0) * dt * 0.15
                    end
                end
                -- vines don't pass through stone
                if self.level:solid_at(p.pos.x, p.pos.y) then
                    p.pos.x, p.pos.y = p.old_pos.x, p.old_pos.y
                end
            end
        end
    end

    -- Grass: damped angular springs pushed by anything nearby
    local k, c = 140, 9
    for _, b in ipairs(self.blades) do
        local target = b.rest + sin(time * 1.3 + b.x * 0.05) * 0.08 + (noise(time * 0.3, b.x * 0.01) - 0.5) * 0.25
        for _, inf in ipairs(influencers) do
            local dx = b.x - inf.x
            local dy = (b.y - b.h * 0.5) - inf.y
            local r = inf.r + 6
            if abs(dx) < r and abs(dy) < r + b.h then
                local s = 1 - abs(dx) / r
                target = target + (dx >= 0 and 1 or -1) * 1.2 * s
            end
        end
        local acc = -k * (b.ang - target) - c * b.vel
        b.vel = b.vel + acc * dt
        b.ang = b.ang + b.vel * dt
    end

    -- Mushrooms: squash under a creature, spring back, flare
    for _, m in ipairs(self.shrooms) do
        local pressed = false
        for _, inf in ipairs(influencers) do
            local dx, dy = m.x - inf.x, (m.y - m.h) - inf.y
            if abs(dx) < inf.r + m.r and abs(dy) < inf.r + 3 then pressed = true end
        end
        local target = pressed and 0.55 or 0
        local acc = -260 * (m.squash - target) - 12 * m.vel
        m.vel = m.vel + acc * dt
        m.squash = m.squash + m.vel * dt
        if pressed and not m.touched then
            m.flare = 1
            if self.world then
                self.world.events:emit('spores', {x = m.x, y = m.y - m.h, n = 7})
            end
        end
        m.touched = pressed
        m.flare = max(0, m.flare - dt * 0.9)
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function leaf(x, y, ang, size, color)
    local ca, sa = cos(ang), sin(ang)
    local pts = {}
    for k = 0, 6 do
        local t = k / 6
        local along = t * size * 2
        local across = sin(t * pi) * size * 0.55
        pts[#pts + 1] = x + ca * along - sa * across
        pts[#pts + 1] = y + sa * along + ca * across
    end
    for k = 5, 1, -1 do
        local t = k / 6
        local along = t * size * 2
        local across = -sin(t * pi) * size * 0.45
        pts[#pts + 1] = x + ca * along - sa * across
        pts[#pts + 1] = y + sa * along + ca * across
    end
    love.graphics.setColor(color)
    local ok, tris = pcall(love.math.triangulate, pts)
    if ok then for _, t in ipairs(tris) do love.graphics.polygon('fill', t) end end
end

function Flora:draw_vines(light_dir)
    for _, v in ipairs(self.vines) do
        local pts = v.chain.points
        local line = {}
        for _, p in ipairs(pts) do line[#line + 1] = p.pos.x; line[#line + 1] = p.pos.y end
        love.graphics.setColor(0.08, 0.10, 0.08, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.line(line)
        love.graphics.setColor(P.vine)
        love.graphics.setLineWidth(1.8)
        love.graphics.line(line)
        love.graphics.setLineWidth(1)
        for _, lf in ipairs(v.leaves) do
            local a, b = pts[lf.i - 1], pts[lf.i]
            local ang = math.atan2(b.pos.y - a.pos.y, b.pos.x - a.pos.x) + lf.side * 1.0 + lf.tilt
            local lx, ly = light_dir(b.pos.x, b.pos.y)
            local lit = max(0, cos(ang) * lx + sin(ang) * ly)
            local col = {P.leaf[1] + (P.leaf_lit[1] - P.leaf[1]) * lit, P.leaf[2] + (P.leaf_lit[2] - P.leaf[2]) * lit,
                         P.leaf[3] + (P.leaf_lit[3] - P.leaf[3]) * lit}
            leaf(b.pos.x, b.pos.y, ang, lf.size, col)
        end
        if v.flower then
            local tail = pts[#pts]
            love.graphics.setColor(0.98, 0.72, 0.80)
            for k = 0, 4 do
                local a = k / 5 * 2 * pi
                love.graphics.circle('fill', tail.pos.x + cos(a) * 2.2, tail.pos.y + 2 + sin(a) * 2.2, 1.6)
            end
            love.graphics.setColor(1, 0.9, 0.5)
            love.graphics.circle('fill', tail.pos.x, tail.pos.y + 2, 1.1)
        end
    end
end

function Flora:draw_grass(front)
    love.graphics.setLineWidth(1)
    for _, b in ipairs(self.blades) do
        if b.front == front then
            local ang = b.ang
            local tx, ty = b.x + sin(ang) * b.h, b.y - cos(ang) * b.h
            local mx, my = b.x + sin(ang * 0.5) * b.h * 0.55, b.y - cos(ang * 0.5) * b.h * 0.55
            local t = b.shade
            local r = P.grass[1] + (P.grass_lit[1] - P.grass[1]) * t
            local g = P.grass[2] + (P.grass_lit[2] - P.grass[2]) * t
            local bl = P.grass[3] + (P.grass_lit[3] - P.grass[3]) * t
            if front then r, g, bl = r * 0.7, g * 0.7, bl * 0.75 end
            love.graphics.setColor(r, g, bl)
            love.graphics.polygon('fill', b.x - b.w, b.y, b.x + b.w, b.y, mx + b.w * 0.4, my, tx, ty, mx - b.w * 0.4, my)
        end
    end
end

function Flora:draw_mushrooms(time)
    for _, m in ipairs(self.shrooms) do
        local h = m.h * (1 - m.squash * 0.6)
        local w = 1 + m.squash * 0.5
        local tx, ty = m.x + sin(m.lean) * h, m.y - cos(m.lean) * h
        love.graphics.setColor(P.stem)
        love.graphics.setLineWidth(2.2)
        love.graphics.line(m.x, m.y, (m.x + tx) / 2 + m.lean * 2, (m.y + ty) / 2, tx, ty)
        love.graphics.setLineWidth(1)
        -- Cap
        love.graphics.setColor(0.12, 0.28, 0.36)
        love.graphics.arc('fill', tx, ty + 0.5, m.r * w + 0.8, pi, 2 * pi)
        love.graphics.setColor(P.shroom[1] * 0.7, P.shroom[2] * 0.75, P.shroom[3] * 0.8)
        love.graphics.arc('fill', tx, ty, m.r * w, pi, 2 * pi)
        love.graphics.setColor(0.08, 0.18, 0.24, 0.8)
        love.graphics.line(tx - m.r * w, ty, tx + m.r * w, ty)
    end
end

-- Emissive caps, drawn after the light map (stays bright through the dark)
function Flora:draw_glow(lighting, time)
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    for _, m in ipairs(self.shrooms) do
        local h = m.h * (1 - m.squash * 0.6)
        local tx, ty = m.x + sin(m.lean) * h, m.y - cos(m.lean) * h
        local pulse = 0.55 + 0.2 * sin(time * 1.4 + m.phase) + m.flare * 0.8
        lighting:glow(tx, ty - m.r * 0.4, m.r * 4, P.shroom[1], P.shroom[2], P.shroom[3], 0.22 * pulse)
        love.graphics.setColor(P.shroom[1] * pulse, P.shroom[2] * pulse, P.shroom[3] * pulse, 0.7)
        love.graphics.arc('fill', tx, ty - 0.5, m.r * (1 + m.squash * 0.5) * 0.85, pi, 2 * pi)
        love.graphics.setColor(1, 1, 1, 0.5 * pulse)
        love.graphics.circle('fill', tx - m.r * 0.3, ty - m.r * 0.45, 0.9)
        love.graphics.circle('fill', tx + m.r * 0.25, ty - m.r * 0.3, 0.6)
    end
    love.graphics.pop()
end

-- Add the mushroom glow to the light map
function Flora:add_lights(lighting, time)
    for _, m in ipairs(self.shrooms) do
        local pulse = 0.7 + 0.15 * sin(time * 1.4 + m.phase) + m.flare * 0.8
        lighting:add(m.x, m.y - m.h, P.shroom[1], P.shroom[2], P.shroom[3], 42 + m.r * 4, 0.42 * pulse)
    end
end

return Flora
