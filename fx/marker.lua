-- Marker: where you asked a creature to go.
--
-- A soft ring blooms where the click landed on a surface and settles into a
-- gentle pulse until the creature arrives. A click nowhere reachable gets a
-- small grey ring that shrugs and fades.

local Marker = {}
Marker.__index = Marker

local sin, pi, min, max = math.sin, math.pi, math.min, math.max

function Marker.new()
    return setmetatable({goal = nil, nope = {}}, Marker)
end

-- Goal on a surface (with its normal so the ring lies flat on it)
function Marker:set(x, y, nx, ny, color)
    self.goal = {x = x, y = y, nx = nx or 0, ny = ny or -1, age = 0, color = color or {1, 0.9, 0.7}}
end

function Marker:reject(x, y)
    self.nope[#self.nope + 1] = {x = x, y = y, age = 0}
end

function Marker:clear()
    if self.goal then self.goal.leaving = 0 end
end

function Marker:update(dt)
    local g = self.goal
    if g then
        g.age = g.age + dt
        if g.leaving then
            g.leaving = g.leaving + dt
            if g.leaving > 0.6 then self.goal = nil end
        end
    end
    for i = #self.nope, 1, -1 do
        local n = self.nope[i]
        n.age = n.age + dt
        if n.age > 0.6 then table.remove(self.nope, i) end
    end
end

-- Drawn after lighting, additively, so it glows through the bloom
function Marker:draw(lighting, time)
    love.graphics.push('all')
    local g = self.goal
    if g then
        love.graphics.setBlendMode('add')
        local c = g.color
        local fade = g.leaving and max(0, 1 - g.leaving / 0.6) or 1
        local bloom = min(1, g.age / 0.5)
        local ease = 1 - (1 - bloom) ^ 3
        -- Ring lies flat against its surface
        local ang = math.atan2(g.ny, g.nx) + pi / 2
        love.graphics.translate(g.x, g.y)
        love.graphics.rotate(ang)
        lighting:glow(0, -3, 26, c[1], c[2], c[3], 0.35 * fade)
        local r = 6 + 16 * ease
        love.graphics.setColor(c[1], c[2], c[3], (1 - bloom * 0.7) * fade)
        love.graphics.setLineWidth(1.5)
        love.graphics.ellipse('line', 0, -1, r, r * 0.32)
        local pulse = 0.5 + 0.5 * sin(time * 3)
        love.graphics.setColor(c[1], c[2], c[3], (0.35 + 0.35 * pulse) * fade * bloom)
        love.graphics.ellipse('line', 0, -1, 7 + pulse * 2, (7 + pulse * 2) * 0.32)
        love.graphics.setColor(c[1], c[2], c[3], 0.9 * fade)
        love.graphics.circle('fill', 0, -3 - pulse * 1.5, 1.4)
        love.graphics.setLineWidth(1)
    end
    love.graphics.pop()

    love.graphics.push('all')
    for _, n in ipairs(self.nope) do
        local t = n.age / 0.6
        local shake = sin(n.age * 50) * 2 * (1 - t)
        love.graphics.setColor(0.75, 0.72, 0.8, 0.7 * (1 - t))
        love.graphics.setLineWidth(1.2)
        love.graphics.circle('line', n.x + shake, n.y, 6 * (1 - t * 0.5))
        love.graphics.line(n.x + shake - 3, n.y - 3, n.x + shake + 3, n.y + 3)
    end
    love.graphics.pop()
end

return Marker
