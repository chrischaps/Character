-- HUD: quiet text that gets out of the way.
--
-- The selected creature's name and a line about how it works fade in when you
-- switch and fade out after a few seconds. A small roster sits in the corner.
-- H brings up a card with the controls. Drawn in screen space with fonts sized
-- to the window so text stays crisp at any scale.

local Hud = {}
Hud.__index = Hud

function Hud.new()
    local self = setmetatable({}, Hud)
    self.title_t = 0
    self.help = false
    self.hint = 1
    self.paused = false
    self.muted = false
    self.scale = 0
    return self
end

function Hud:fonts(scale)
    if self.scale == scale then return end
    self.scale = scale
    local function f(px) return love.graphics.newFont(math.max(8, math.floor(px * scale + 0.5))) end
    self.f_title, self.f_body, self.f_small = f(22), f(12.5), f(10.5)
end

function Hud:announce()
    self.title_t = 0
end

function Hud:clicked()
    self.hint = math.min(self.hint, 0.999)
end

function Hud:update(dt)
    self.title_t = self.title_t + dt
    if self.hint < 1 then self.hint = math.max(0, self.hint - dt * 0.8) end
end

local function shadow_print(text, font, x, y, r, g, b, a, align, width)
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, a * 0.55)
    if align then
        love.graphics.printf(text, x + 1, y + 1, width, align)
        love.graphics.setColor(r, g, b, a)
        love.graphics.printf(text, x, y, width, align)
    else
        love.graphics.print(text, x + 1, y + 1)
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(text, x, y)
    end
end

-- to_screen: function(vx, vy) -> sx, sy ; scale: virtual->screen
function Hud:draw(world, to_screen, scale)
    self:fonts(scale)
    local c = world:selected_creature()
    local cc = c.color_name

    -- Title card
    local t = self.title_t
    local a = (t < 0.4) and (t / 0.4) or ((t < 4.5) and 1 or math.max(0, 1 - (t - 4.5) / 1.5))
    if a > 0 then
        local x, y = to_screen(34, 46)
        shadow_print(c:get_name(), self.f_title, x, y, cc[1], cc[2], cc[3], a)
        shadow_print(c:get_description(), self.f_body, x, y + 30 * scale, 0.92, 0.88, 0.95, a * 0.85)
    end

    -- Roster
    local x, y = to_screen(34, 512)
    love.graphics.setFont(self.f_small)
    for i, cr in ipairs(world.creatures) do
        local sel = i == world.selected
        local label = i .. "  " .. cr:get_name()
        local col = cr.color_name
        local alpha = sel and 0.9 or 0.38
        love.graphics.setColor(col[1], col[2], col[3], alpha)
        love.graphics.circle('fill', x + 3 * scale, y + 7 * scale, (sel and 3 or 2) * scale)
        shadow_print(label, self.f_small, x + 10 * scale, y, 0.95, 0.92, 0.97, alpha)
        x = x + (self.f_small:getWidth(label) + 30 * scale)
    end
    local hx, hy = to_screen(926, 512)
    local right = "H help" .. (self.muted and "   muted" or "") .. (self.paused and "   paused" or "")
    shadow_print(right, self.f_small, hx - 300 * scale, hy, 0.9, 0.88, 0.95, 0.38, 'right', 300 * scale)

    -- First hint
    if self.hint > 0 then
        local h = self.hint
        local mx, my = to_screen(480, 268)
        shadow_print("click anywhere to guide the " .. c.key, self.f_body, mx - 200 * scale, my, 1, 0.95, 0.88,
            0.75 * h * math.min(1, t / 1.2), 'center', 400 * scale)
    end

    if self.help then self:draw_help(to_screen, scale) end
end

function Hud:draw_help(to_screen, scale)
    local x, y = to_screen(310, 140)
    local w, h = 340 * scale, 268 * scale
    love.graphics.setColor(0.07, 0.06, 0.11, 0.82)
    love.graphics.rectangle('fill', x, y, w, h, 10 * scale, 10 * scale)
    love.graphics.setColor(1, 0.85, 0.6, 0.35)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle('line', x, y, w, h, 10 * scale, 10 * scale)
    local lines = {
        {"Left click", "guide the selected creature"},
        {"1  2  3  /  Tab", "choose a creature"},
        {"N", "show the navigation graph"},
        {"X", "x-ray: see what they're made of"},
        {"D", "debug view"},
        {"W", "others wander on / off"},
        {"P", "pause"},
        {"M", "mute"},
        {"R", "reset everyone"},
        {"F", "fullscreen"},
        {"Esc", "quit"},
    }
    shadow_print("The Dusk Cave", self.f_title, x + 18 * scale, y + 14 * scale, 1, 0.84, 0.6, 1)
    local ly = y + 52 * scale
    for _, l in ipairs(lines) do
        shadow_print(l[1], self.f_body, x + 18 * scale, ly, 1, 0.9, 0.75, 0.95)
        shadow_print(l[2], self.f_body, x + 134 * scale, ly, 0.88, 0.86, 0.94, 0.85)
        ly = ly + 18 * scale
    end
end

return Hud
