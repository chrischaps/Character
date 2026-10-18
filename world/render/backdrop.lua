-- Backdrop: the dusk sky through the cave mouth, and the back wall around it.
--
-- The sky is drawn live (clouds drift, the first stars come out); the back
-- wall is baked once into a canvas at render resolution with the mouth cut
-- out of it, so the sky shows through a ragged hole in the stone.

local P = require('world.render.palette')

local Backdrop = {}
Backdrop.__index = Backdrop

local noise = love.math.noise
local sin, cos, pi = math.sin, math.cos, math.pi

function Backdrop.new(level)
    local self = setmetatable({}, Backdrop)
    self.level = level
    self.mouth = level.data.mouth
    self.seed = level.data.seed or 1
    local gen = love.math.newRandomGenerator(self.seed * 97)
    self.stars = {}
    for i = 1, 26 do
        self.stars[i] = {
            x = self.mouth.x + (gen:random() - 0.5) * self.mouth.rx * 2,
            y = self.mouth.y + (gen:random() - 0.9) * self.mouth.ry * 1.2,
            s = 0.5 + gen:random() * 0.9, p = gen:random() * 6,
        }
    end
    self.clouds = {}
    for i = 1, 5 do
        self.clouds[i] = {
            x = gen:random() * 400, y = self.mouth.y - 10 + gen:random() * 70,
            w = 50 + gen:random() * 70, speed = 2 + gen:random() * 3,
        }
    end
    self.mouth_poly = self:make_mouth_poly()
    return self
end

-- Ragged outline of the cave mouth
function Backdrop:make_mouth_poly()
    local m = self.mouth
    local pts = {}
    local n = 48
    for i = 0, n - 1 do
        local a = i / n * 2 * pi
        local wob = 1 + 0.16 * (noise(cos(a) * 1.7 + self.seed, sin(a) * 1.7) - 0.5) * 2
            + 0.05 * (noise(cos(a) * 5 + 9, sin(a) * 5 + self.seed) - 0.5) * 2
        -- flatten the bottom a little: a lip of rock
        local ry = m.ry * (sin(a) > 0 and 0.82 or 1)
        pts[#pts + 1] = m.x + cos(a) * m.rx * wob
        pts[#pts + 1] = m.y + sin(a) * ry * wob
    end
    return pts
end

local function vgradient(x, y, w, h, stops)
    -- stops: {{t, {r,g,b}}, ...}
    local verts = {}
    for _, st in ipairs(stops) do
        local c = st[2]
        verts[#verts + 1] = {x, y + h * st[1], 0, 0, c[1], c[2], c[3], c[4] or 1}
        verts[#verts + 1] = {x + w, y + h * st[1], 0, 0, c[1], c[2], c[3], c[4] or 1}
    end
    local map = {}
    for i = 0, #stops - 2 do
        local a = i * 2 + 1
        map[#map + 1] = a; map[#map + 1] = a + 1; map[#map + 1] = a + 2
        map[#map + 1] = a + 1; map[#map + 1] = a + 3; map[#map + 1] = a + 2
    end
    local mesh = love.graphics.newMesh(verts, 'triangles', 'static')
    mesh:setVertexMap(map)
    return mesh
end
Backdrop.vgradient = vgradient

-- Live sky, drawn first (it only shows through the mouth)
function Backdrop:draw_sky(time)
    local m = self.mouth
    if not self.sky_mesh then
        self.sky_mesh = vgradient(m.x - m.rx * 1.4, m.y - m.ry * 1.3, m.rx * 2.8, m.ry * 2.6, {
            {0, P.sky_top}, {0.38, P.sky_mid}, {0.7, P.sky_low}, {1, P.sky_low},
        })
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.sky_mesh)

    -- Stars fade in at the top of the sky
    for _, s in ipairs(self.stars) do
        local tw = 0.5 + 0.5 * sin(time * 1.3 + s.p)
        local fade = math.max(0, math.min(1, (m.y - s.y) / 60))
        love.graphics.setColor(1, 0.95, 0.9, 0.55 * tw * fade)
        love.graphics.circle('fill', s.x, s.y, s.s)
    end

    -- Low sun glow on the horizon
    local hx, hy = m.x + 30, m.y + m.ry * 0.62
    for k = 6, 1, -1 do
        love.graphics.setColor(P.sun[1], P.sun[2], P.sun[3], 0.08)
        love.graphics.circle('fill', hx, hy, 14 + k * 11)
    end
    love.graphics.setColor(1, 0.95, 0.82, 0.9)
    love.graphics.circle('fill', hx, hy, 11)

    -- Drifting clouds
    for _, c in ipairs(self.clouds) do
        local cx = m.x - m.rx * 1.3 + ((c.x + time * c.speed) % (m.rx * 2.8 + c.w)) - c.w * 0.5
        love.graphics.setColor(P.cloud_dark[1], P.cloud_dark[2], P.cloud_dark[3], 0.55)
        love.graphics.ellipse('fill', cx, c.y + 3, c.w * 0.5, 5)
        love.graphics.setColor(P.cloud[1], P.cloud[2], P.cloud[3], 0.6)
        love.graphics.ellipse('fill', cx - 4, c.y, c.w * 0.42, 4)
    end

    -- Distant hills under the sun
    love.graphics.setColor(P.hill_far)
    local pts = {}
    local x0, x1 = m.x - m.rx * 1.2, m.x + m.rx * 1.2
    for x = x0, x1, 8 do
        pts[#pts + 1] = x
        pts[#pts + 1] = m.y + m.ry * 0.55 - noise(x * 0.012, self.seed) * 22
    end
    pts[#pts + 1] = x1; pts[#pts + 1] = m.y + m.ry * 2
    pts[#pts + 1] = x0; pts[#pts + 1] = m.y + m.ry * 2
    for _, tri in ipairs(love.math.triangulate(pts)) do love.graphics.polygon('fill', tri) end
    love.graphics.setColor(P.hill_near)
    pts = {}
    for x = x0, x1, 6 do
        pts[#pts + 1] = x
        pts[#pts + 1] = m.y + m.ry * 0.72 - noise(x * 0.02, self.seed + 4) * 16
    end
    pts[#pts + 1] = x1; pts[#pts + 1] = m.y + m.ry * 2
    pts[#pts + 1] = x0; pts[#pts + 1] = m.y + m.ry * 2
    for _, tri in ipairs(love.math.triangulate(pts)) do love.graphics.polygon('fill', tri) end
end

-- Smooth radial falloff texture (shared)
function Backdrop.radial()
    if not Backdrop._radial then
        local data = love.image.newImageData(256, 256)
        data:mapPixel(function(x, y)
            local dx, dy = (x - 127.5) / 127.5, (y - 127.5) / 127.5
            local v = math.max(0, 1 - math.sqrt(dx * dx + dy * dy))
            return 1, 1, 1, v * v * (3 - 2 * v)
        end)
        Backdrop._radial = love.graphics.newImage(data)
    end
    return Backdrop._radial
end

-- Bake the back wall at the current render scale
function Backdrop:bake(scale)
    local W, H = self.level.width, self.level.height
    local canvas = love.graphics.newCanvas(math.ceil(W * scale), math.ceil(H * scale), {msaa = 4})
    love.graphics.push('all')
    love.graphics.setCanvas({canvas, stencil = true})
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.scale(scale)

    -- Base wall gradient
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(vgradient(0, 0, W, H, {
        {0, P.wall_top}, {0.55, P.wall_mid}, {1, P.wall_low},
    }))

    -- Receding rock layers: farther = lighter and hazier
    local layers = {
        {color = P.wall_far, base = 0.66, amp = 70, freq = 0.006, alpha = 0.55},
        {color = P.wall_mid, base = 0.78, amp = 60, freq = 0.009, alpha = 0.8},
    }
    for li, L in ipairs(layers) do
        love.graphics.setColor(L.color[1], L.color[2], L.color[3], L.alpha)
        local pts = {}
        for x = 0, W, 10 do
            pts[#pts + 1] = x
            pts[#pts + 1] = H * L.base - noise(x * L.freq, self.seed + li * 3) * L.amp
        end
        pts[#pts + 1] = W; pts[#pts + 1] = H
        pts[#pts + 1] = 0; pts[#pts + 1] = H
        for _, tri in ipairs(love.math.triangulate(pts)) do love.graphics.polygon('fill', tri) end
    end

    -- Hanging silhouettes from the roof (distant stalactites)
    local gen = love.math.newRandomGenerator(self.seed * 13)
    for i = 1, 34 do
        local x = gen:random() * W
        local len = 20 + gen:random() * 70
        local w = 6 + gen:random() * 14
        local t = gen:random()
        love.graphics.setColor(P.wall_top[1] + t * 0.05, P.wall_top[2] + t * 0.04, P.wall_top[3] + t * 0.06, 0.9)
        love.graphics.polygon('fill', x - w, 0, x + w, 0, x + w * 0.2, len, x - w * 0.15, len * 0.94)
    end

    -- Faint strata and speckle
    for i = 1, 140 do
        local x, y = gen:random() * W, gen:random() * H
        love.graphics.setColor(1, 1, 1, 0.025 + gen:random() * 0.03)
        love.graphics.circle('fill', x, y, 0.6 + gen:random() * 1.6)
    end
    love.graphics.setLineWidth(1)
    for i = 1, 18 do
        local y = 60 + gen:random() * (H - 120)
        local x = gen:random() * W
        local len = 40 + gen:random() * 120
        love.graphics.setColor(0, 0, 0, 0.12)
        local pts = {}
        for k = 0, 8 do
            pts[#pts + 1] = x + len * k / 8
            pts[#pts + 1] = y + (noise((x + len * k / 8) * 0.05, y) - 0.5) * 6
        end
        love.graphics.line(pts)
    end

    -- Warm wash around the mouth where dusk light hits the stone
    local m = self.mouth
    local glow = Backdrop.radial()
    love.graphics.setColor(P.mouth[1], P.mouth[2], P.mouth[3], 0.32)
    love.graphics.draw(glow, m.x, m.y + 20, 0, m.rx * 4.2 / 256, m.ry * 4.6 / 256, 128, 128)

    -- Cut the mouth out (alpha 0) with a rim of lit stone around it
    love.graphics.setColor(P.rock_lip[1], P.rock_lip[2], P.rock_lip[3], 0.9)
    love.graphics.setLineWidth(5)
    local poly = {}
    for i = 1, #self.mouth_poly do poly[i] = self.mouth_poly[i] end
    poly[#poly + 1], poly[#poly + 2] = poly[1], poly[2]
    love.graphics.line(poly)
    love.graphics.setBlendMode('replace')
    love.graphics.setColor(0, 0, 0, 0)
    for _, tri in ipairs(love.math.triangulate(self.mouth_poly)) do
        love.graphics.polygon('fill', tri)
    end
    love.graphics.setBlendMode('alpha')

    love.graphics.pop()
    self.canvas, self.scale = canvas, scale
    return canvas
end

function Backdrop:draw(time)
    self:draw_sky(time)
    if self.canvas then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(self.canvas, 0, 0, 0, 1 / self.scale, 1 / self.scale)
    end
end

return Backdrop
