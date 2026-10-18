-- Lighting: a light map multiplied over the scene, then glow on top.
--
-- The light map starts at the cave's ambient violet and gathers additive
-- lights: dusk pouring through the mouth, the shafts it casts, glowing
-- mushrooms, fireflies, the blob's bioluminescence and a soft lantern around
-- whichever creature you're guiding. Multiplying it over the scene darkens
-- what's unlit and leaves lit things their true colour.

local P = require('world.render.palette')

local Lighting = {}
Lighting.__index = Lighting

local sin, cos = math.sin, math.cos

local function radial_image(size, power)
    local data = love.image.newImageData(size, size)
    local c = (size - 1) / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x - c) / c, (y - c) / c
        local d = math.sqrt(dx * dx + dy * dy)
        local v = math.max(0, 1 - d)
        v = v ^ power
        return 1, 1, 1, v
    end)
    local img = love.graphics.newImage(data)
    img:setFilter('linear', 'linear')
    return img
end

function Lighting.new(level)
    local self = setmetatable({}, Lighting)
    self.level = level
    self.W, self.H = level.width, level.height
    self.canvas = love.graphics.newCanvas(self.W, self.H)
    self.soft = radial_image(128, 1.6)
    self.hard = radial_image(64, 3.0)
    self.lights = {}
    self.ambient = P.ambient
    self.rays = self:make_rays()
    return self
end

-- Shafts of light from the mouth, angled down and to the left.
-- Each is a 3x3 vertex grid: transparent edges, a bright core that fades in
-- just below the mouth's lip and out toward the floor.
function Lighting:make_rays()
    local m = self.level.data.mouth
    local rays = {}
    local specs = {
        {dx = -40, w0 = 40, w1 = 120, len = 520, a = 0.16, ang = 0.60, phase = 0.0},
        {dx = 10,  w0 = 26, w1 = 80,  len = 470, a = 0.12, ang = 0.68, phase = 1.7},
        {dx = 60,  w0 = 34, w1 = 130, len = 430, a = 0.10, ang = 0.76, phase = 3.1},
        {dx = -90, w0 = 18, w1 = 60,  len = 420, a = 0.08, ang = 0.54, phase = 4.4},
    }
    for _, s in ipairs(specs) do
        local ox, oy = m.x + s.dx, m.y + m.ry * 0.5
        local dirx, diry = -sin(s.ang), cos(s.ang)
        local px, py = -diry, dirx
        local verts = {}
        local rows = {{0, 0}, {0.14, 1}, {0.55, 0.45}, {1, 0}}
        for _, row in ipairs(rows) do
            local t, a = row[1], row[2]
            local w = s.w0 + (s.w1 - s.w0) * t
            local cx, cy = ox + dirx * s.len * t, oy + diry * s.len * t
            verts[#verts + 1] = {cx + px * w / 2, cy + py * w / 2, 0, 0, P.ray[1], P.ray[2], P.ray[3], 0}
            verts[#verts + 1] = {cx, cy, 0, 0, P.ray[1], P.ray[2], P.ray[3], a}
            verts[#verts + 1] = {cx - px * w / 2, cy - py * w / 2, 0, 0, P.ray[1], P.ray[2], P.ray[3], 0}
        end
        local map = {}
        for r = 0, #rows - 2 do
            for c = 0, 1 do
                local a = r * 3 + c + 1
                local b = a + 3
                map[#map + 1] = a; map[#map + 1] = a + 1; map[#map + 1] = b
                map[#map + 1] = a + 1; map[#map + 1] = b + 1; map[#map + 1] = b
            end
        end
        local mesh = love.graphics.newMesh(verts, 'triangles', 'static')
        mesh:setVertexMap(map)
        rays[#rays + 1] = {
            mesh = mesh, alpha = s.a, phase = s.phase,
            ox = ox, oy = oy, dirx = dirx, diry = diry, w0 = s.w0, w1 = s.w1, len = s.len,
        }
    end
    return rays
end

-- Is (x, y) inside a light shaft? Returns brightness 0..1
function Lighting:ray_strength(x, y, time)
    local best = 0
    for _, r in ipairs(self.rays) do
        local rx, ry = x - r.ox, y - r.oy
        local along = rx * r.dirx + ry * r.diry
        if along > 0 and along < r.len then
            local across = math.abs(rx * -r.diry + ry * r.dirx)
            local t = along / r.len
            local half = (r.w0 + (r.w1 - r.w0) * t) / 2
            if across < half then
                local v = (1 - across / half) * (1 - t) * (0.7 + 0.3 * sin(time * 0.5 + r.phase))
                if v > best then best = v end
            end
        end
    end
    return best
end

function Lighting:begin()
    self.lights = {}
end

-- Queue a light: position, colour, radius, intensity
function Lighting:add(x, y, r, g, b, radius, intensity, hard)
    self.lights[#self.lights + 1] = {x, y, r, g, b, radius, intensity or 1, hard}
end

function Lighting:render(time)
    local m = self.level.data.mouth
    love.graphics.push('all')
    love.graphics.setCanvas(self.canvas)
    love.graphics.origin()
    love.graphics.clear(self.ambient[1], self.ambient[2], self.ambient[3], 1)
    love.graphics.setBlendMode('add')

    -- Dusk through the mouth: a broad warm pool and a hot core
    local breathe = 1 + 0.03 * sin(time * 0.4)
    love.graphics.setColor(P.mouth[1] * 0.42, P.mouth[2] * 0.42, P.mouth[3] * 0.42, 1)
    love.graphics.draw(self.soft, m.x - 120, m.y + 200, 0, 1300 * breathe / 128, 1000 * breathe / 128, 64, 64)
    love.graphics.setColor(P.mouth[1] * 0.8, P.mouth[2] * 0.8, P.mouth[3] * 0.8, 1)
    love.graphics.draw(self.soft, m.x, m.y, 0, 460 / 128, 400 / 128, 64, 64)
    -- The shafts brighten what they cross
    for _, r in ipairs(self.rays) do
        local a = r.alpha * 1.6 * (0.7 + 0.3 * sin(time * 0.5 + r.phase))
        love.graphics.setColor(a, a * 0.85, a * 0.65, 1)
        love.graphics.draw(r.mesh)
    end

    for _, L in ipairs(self.lights) do
        local img = L[8] and self.hard or self.soft
        local k = L[7]
        love.graphics.setColor(L[3] * k, L[4] * k, L[5] * k, 1)
        local s = L[6] * 2 / img:getWidth()
        love.graphics.draw(img, L[1], L[2], 0, s, s, img:getWidth() / 2, img:getHeight() / 2)
    end
    love.graphics.pop()
end

-- Multiply the light map over whatever has been drawn (in virtual coords)
function Lighting:apply()
    love.graphics.push('all')
    love.graphics.setBlendMode('multiply', 'premultiplied')
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, 0, 0)
    love.graphics.pop()
end

-- Additive shafts drawn over the lit scene: visible air, not just lit stone
function Lighting:draw_rays(time)
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    for _, r in ipairs(self.rays) do
        local a = r.alpha * (0.65 + 0.35 * sin(time * 0.5 + r.phase))
        love.graphics.setColor(a, a, a, 1)
        love.graphics.draw(r.mesh)
    end
    love.graphics.pop()
end

-- A soft additive glow sprite (for emissive things after lighting)
function Lighting:glow(x, y, radius, r, g, b, a)
    love.graphics.setColor(r, g, b, a)
    local s = radius * 2 / self.soft:getWidth()
    love.graphics.draw(self.soft, x, y, 0, s, s, 64, 64)
end

return Lighting
