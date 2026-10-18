-- Rock: bakes the cave's solids into organic stone.
--
-- Physics sees rectangles; you see jittered stone with a warm lit lip, a
-- shaded body, cracks and specks, soft moss caps with hanging tongues, and a
-- fallen log with bark and an end ring. Everything is baked once per render
-- scale into a single canvas.

local P = require('world.render.palette')
local Backdrop = require('world.render.backdrop')

local Rock = {}
Rock.__index = Rock

local noise = love.math.noise
local min, max, abs = math.min, math.max, math.abs

function Rock.new(level)
    local self = setmetatable({}, Rock)
    self.level = level
    self.seed = level.data.seed or 1
    return self
end

local function is_frame(s) return s.kind == 'wall' or (s.kind == 'ceiling' and s.id == 'ceiling') end

-- Organic outline around a rectangle. amp = {top, side, bottom}
local function outline(s, amp, seed, W, H)
    local pts = {}
    local x0, y0 = s.x, s.y
    local x1, y1 = s.x + s.w, s.y + s.h
    -- Keep huge frame pieces to the visible area plus a margin
    x0, x1 = max(x0, -30), min(x1, W + 30)
    y0, y1 = max(y0, -30), min(y1, H + 30)
    local step = 5
    local function push(x, y) pts[#pts + 1] = x; pts[#pts + 1] = y end
    local function corner_pull(x, y)
        -- round the corners in by a few pixels
        local cx = min(x - x0, x1 - x)
        local cy = min(y - y0, y1 - y)
        local k = max(0, 5 - min(cx, cy) * 0.5) * (cx < 6 and cy < 6 and 1 or 0)
        local mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        local dx, dy = mx - x, my - y
        local d = math.sqrt(dx * dx + dy * dy)
        return x + dx / d * k, y + dy / d * k
    end
    for x = x0, x1 - 0.01, step do
        local n = noise(x * 0.07, seed) * 0.7 + noise(x * 0.3, seed + 2) * 0.3
        push(corner_pull(x, y0 - n * amp[1]))
    end
    for y = y0, y1 - 0.01, step do
        local n = noise(y * 0.06, seed + 5) * 0.75 + noise(y * 0.25, seed + 6) * 0.25
        push(corner_pull(x1 + (n - 0.35) * amp[2], y))
    end
    for x = x1, x0 + 0.01, -step do
        local n = noise(x * 0.05, seed + 9)
        local drip = max(0, noise(x * 0.11, seed + 11) - 0.62) * 3
        push(corner_pull(x, y1 + n * amp[3] + drip * amp[3]))
    end
    for y = y1, y0 + 0.01, -step do
        local n = noise(y * 0.06, seed + 13) * 0.75 + noise(y * 0.25, seed + 14) * 0.25
        push(corner_pull(x0 - (n - 0.35) * amp[2], y))
    end
    return pts
end

local function fill(pts)
    local ok, tris = pcall(love.math.triangulate, pts)
    if not ok then return end
    for _, t in ipairs(tris) do love.graphics.polygon('fill', t) end
end

local function stencil_to(pts)
    love.graphics.stencil(function() fill(pts) end, 'replace', 1)
    love.graphics.setStencilTest('greater', 0)
end

function Rock:draw_stone(s, gen, W, H, light_x)
    local frame = is_frame(s)
    local amp = frame and {9, 10, 12} or {1.8, 3.5, 6}
    if s.kind == 'ceiling' and not frame then amp = {6, 5, 10} end
    local pts = outline(s, amp, self.seed + s.index * 7.3, W, H)

    -- Silhouette
    local base = frame and P.rock_frame or P.rock_base
    love.graphics.setColor(base)
    fill(pts)

    stencil_to(pts)
    local x0, y0 = max(s.x, -30) - 12, max(s.y, -30) - 12
    local x1, y1 = min(s.x + s.w, W + 30) + 12, min(s.y + s.h, H + 30) + 14

    if not frame then
        -- Body: lighter near the top, sinking into shadow below
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(Backdrop.vgradient(x0, y0, x1 - x0, min(y1 - y0, 140), {
            {0, P.rock_mid}, {0.35, P.rock_mid}, {1, {P.rock_base[1], P.rock_base[2], P.rock_base[3], 0}},
        }))
        -- Light from the mouth warms the side that faces it
        local cx = (s.x + s.w / 2)
        local side = (light_x > cx) and 1 or -1
        for k = 1, 8 do
            local t = k / 8
            love.graphics.setColor(P.rock_lip[1], P.rock_lip[2], P.rock_lip[3], 0.05)
            local w = s.w * 0.5 * t
            local sx = side > 0 and (s.x + s.w - w) or s.x
            love.graphics.rectangle('fill', sx, s.y, w, s.h)
        end
    else
        -- Frame rock: near-black, with a faint cool sheen on inner faces
        love.graphics.setColor(P.wall_mid[1], P.wall_mid[2], P.wall_mid[3], 0.5)
        if s.id == 'wall_l' then love.graphics.rectangle('fill', s.x + s.w - 10, 0, 22, H) end
        if s.id == 'wall_r' then love.graphics.rectangle('fill', s.x - 12, 0, 22, H) end
        if s.id == 'ceiling' then love.graphics.rectangle('fill', 0, s.y + s.h - 10, W, 22) end
    end

    -- Cracks
    love.graphics.setLineWidth(1)
    local area = (min(s.w, W) * min(s.h, H))
    local cracks = math.floor(min(14, area / 2600))
    for i = 1, cracks do
        local cx = x0 + gen:random() * (x1 - x0)
        local cy = y0 + 6 + gen:random() * (y1 - y0 - 6)
        local seg = {cx, cy}
        local ang = gen:random() * math.pi
        for k = 1, 4 do
            ang = ang + (gen:random() - 0.5) * 1.2
            cx, cy = cx + math.cos(ang) * (4 + gen:random() * 9), cy + math.sin(ang) * (3 + gen:random() * 7)
            seg[#seg + 1], seg[#seg + 2] = cx, cy
        end
        love.graphics.setColor(P.rock_crack[1], P.rock_crack[2], P.rock_crack[3], frame and 0.4 or 0.75)
        love.graphics.line(seg)
        love.graphics.setColor(P.rock_lip[1], P.rock_lip[2], P.rock_lip[3], frame and 0.05 or 0.16)
        for k = 1, #seg - 2, 2 do seg[k + 1] = seg[k + 1] + 1 end
        love.graphics.line(seg)
    end
    -- Specks
    for i = 1, math.floor(area / 300) do
        local px, py = x0 + gen:random() * (x1 - x0), y0 + gen:random() * (y1 - y0)
        love.graphics.setColor(1, 0.95, 0.9, (frame and 0.02 or 0.05) + gen:random() * 0.05)
        love.graphics.circle('fill', px, py, 0.5 + gen:random() * 1.4)
    end
    love.graphics.setStencilTest()

    -- Lit lip along exposed top edges
    if not frame and s.kind ~= 'ceiling' then
        local lip = {}
        for i = 1, #pts, 2 do
            if pts[i + 1] <= s.y + 1 and pts[i] > s.x - 2 and pts[i] < s.x + s.w + 2 then
                lip[#lip + 1] = pts[i]; lip[#lip + 1] = pts[i + 1] + 1
            end
        end
        if #lip >= 4 then
            love.graphics.setColor(P.rock_lip[1], P.rock_lip[2], P.rock_lip[3], 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.line(lip)
            love.graphics.setLineWidth(1)
        end
    end
    return pts
end

function Rock:draw_log(s, gen)
    local x0, y0, x1, y1 = s.x - 6, s.y, s.x + s.w, s.y + s.h
    -- Body
    love.graphics.setColor(P.wood_dark)
    love.graphics.rectangle('fill', x0, y0 - 1, x1 - x0, y1 - y0 + 3, 7, 7)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(Backdrop.vgradient(x0 + 1, y0, x1 - x0 - 2, y1 - y0, {
        {0, P.wood_ring}, {0.25, P.wood}, {1, P.wood_dark},
    }))
    -- Bark grain
    love.graphics.setLineWidth(1)
    for k = 1, 5 do
        local y = y0 + 3 + k * (s.h - 4) / 6
        local pts = {}
        for x = x0 + 2, x1 - 4, 6 do
            pts[#pts + 1] = x
            pts[#pts + 1] = y + (noise(x * 0.06, k + self.seed) - 0.5) * 3
        end
        love.graphics.setColor(P.wood_dark[1], P.wood_dark[2], P.wood_dark[3], 0.7)
        love.graphics.line(pts)
    end
    -- Knots
    for k = 1, 3 do
        local kx = x0 + 30 + gen:random() * (x1 - x0 - 60)
        love.graphics.setColor(P.wood_dark)
        love.graphics.ellipse('fill', kx, y0 + s.h * 0.55, 4, 2.5)
        love.graphics.setColor(P.wood_ring[1], P.wood_ring[2], P.wood_ring[3], 0.5)
        love.graphics.ellipse('line', kx, y0 + s.h * 0.55, 5.5, 3.5)
    end
    -- Broken end with rings
    local ex, ey = x1 - 2, y0 + s.h / 2
    love.graphics.setColor(P.wood_dark)
    love.graphics.ellipse('fill', ex, ey, 6, s.h / 2 + 1.5)
    love.graphics.setColor(P.wood_ring)
    love.graphics.ellipse('fill', ex, ey, 4.6, s.h / 2 - 0.5)
    love.graphics.setColor(P.wood_dark[1], P.wood_dark[2], P.wood_dark[3], 0.6)
    for r = 1, 3 do love.graphics.ellipse('line', ex, ey, r * 1.3, r * 2.6) end
    -- Top highlight
    love.graphics.setColor(P.wood_ring[1], P.wood_ring[2], P.wood_ring[3], 0.8)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(x0 + 4, y0 + 1, x1 - 6, y0 + 1)
    love.graphics.setLineWidth(1)
end

-- Moss cap with hanging tongues along a top edge
function Rock:draw_moss(s, gen, W)
    local x0, x1 = max(s.x, 22), min(s.x + s.w, W - 22)
    if x1 - x0 < 8 then return end
    local top, bottom = {}, {}
    for x = x0, x1, 3 do
        local n = noise(x * 0.09, self.seed + s.index)
        local tongue = max(0, noise(x * 0.05, s.index * 3.1) - 0.55) * 26
        top[#top + 1] = {x, s.y - 1.5 - n * 2}
        bottom[#bottom + 1] = {x, s.y + 3 + n * 4 + tongue}
    end
    -- Polygon: top edge left->right, bottom edge right->left
    local poly = {}
    for _, p in ipairs(top) do poly[#poly + 1] = p[1]; poly[#poly + 1] = p[2] end
    for i = #bottom, 1, -1 do poly[#poly + 1] = bottom[i][1]; poly[#poly + 1] = bottom[i][2] end
    love.graphics.setColor(P.moss_dark)
    fill(poly)
    -- Inner lighter band
    local band = {}
    for _, p in ipairs(top) do band[#band + 1] = p[1]; band[#band + 1] = p[2] + 0.5 end
    for i = #top, 1, -1 do
        local b = bottom[i]
        band[#band + 1] = b[1]; band[#band + 1] = top[i][2] + (b[2] - top[i][2]) * 0.45
    end
    love.graphics.setColor(P.moss_mid)
    fill(band)
    -- Sunlit fuzz along the very top
    love.graphics.setColor(P.moss_lit[1], P.moss_lit[2], P.moss_lit[3], 0.8)
    love.graphics.setLineWidth(1.2)
    local line = {}
    for _, p in ipairs(top) do line[#line + 1] = p[1]; line[#line + 1] = p[2] + 0.4 end
    if #line >= 4 then love.graphics.line(line) end
    love.graphics.setLineWidth(1)
    for i = 1, math.floor((x1 - x0) / 5) do
        local x = x0 + gen:random() * (x1 - x0)
        love.graphics.setColor(P.moss_lit[1], P.moss_lit[2], P.moss_lit[3], 0.3 + gen:random() * 0.4)
        love.graphics.circle('fill', x, s.y + gen:random() * 3, 0.6 + gen:random() * 1.1)
    end
end

function Rock:draw_stalactite(st, gen)
    local w = 3 + st.len * 0.18
    local pts = {st.x - w, st.y - 2, st.x + w, st.y - 2, st.x + w * 0.3, st.y + st.len * 0.7, st.x, st.y + st.len, st.x - w * 0.35, st.y + st.len * 0.6}
    love.graphics.setColor(P.rock_base)
    fill(pts)
    love.graphics.setColor(P.rock_lip[1], P.rock_lip[2], P.rock_lip[3], 0.45)
    love.graphics.setLineWidth(1.2)
    love.graphics.line(st.x + w, st.y, st.x + w * 0.3, st.y + st.len * 0.7, st.x, st.y + st.len)
    love.graphics.setLineWidth(1)
end

function Rock:bake(scale)
    local level = self.level
    local W, H = level.width, level.height
    local canvas = love.graphics.newCanvas(math.ceil(W * scale), math.ceil(H * scale), {msaa = 4})
    love.graphics.push('all')
    love.graphics.setCanvas({canvas, stencil = true})
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.scale(scale)

    local gen = love.math.newRandomGenerator(self.seed * 1009)
    local light_x = level.data.mouth.x

    -- Order: inner stone first, frame last so the walls overlap ledge ends
    local order = {}
    for _, s in ipairs(level.solids) do if not is_frame(s) and s.kind ~= 'log' then order[#order + 1] = s end end
    for _, s in ipairs(level.solids) do if s.kind == 'log' then order[#order + 1] = s end end
    for _, s in ipairs(level.solids) do if is_frame(s) then order[#order + 1] = s end end

    for _, s in ipairs(order) do
        if s.kind == 'log' then
            self:draw_log(s, gen)
        else
            self:draw_stone(s, gen, W, H, light_x)
        end
    end
    for _, st in ipairs(level.data.stalactites or {}) do self:draw_stalactite(st, gen) end
    for _, s in ipairs(level.solids) do
        if s.moss then self:draw_moss(s, gen, W) end
    end
    -- Mossy patches on the log
    for _, s in ipairs(level.solids) do
        if s.kind == 'log' then
            for k = 1, 4 do
                local mx = s.x + 20 + gen:random() * (s.w - 40)
                love.graphics.setColor(P.moss_mid[1], P.moss_mid[2], P.moss_mid[3], 0.9)
                love.graphics.ellipse('fill', mx, s.y + 1, 8 + gen:random() * 10, 3)
                love.graphics.setColor(P.moss_lit[1], P.moss_lit[2], P.moss_lit[3], 0.7)
                love.graphics.ellipse('fill', mx - 2, s.y, 5, 1.2)
            end
        end
    end

    love.graphics.pop()
    self.canvas, self.scale = canvas, scale
    return canvas
end

function Rock:draw()
    if not self.canvas then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.canvas, 0, 0, 0, 1 / self.scale, 1 / self.scale)
end

return Rock
