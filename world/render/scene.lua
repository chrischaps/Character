-- Scene: draws the whole cave in layers, back to front.
--
--   sky + back wall          (backdrop)
--   vines, stone, grass      (flora behind, baked rock)
--   mushrooms, drips, trail
--   creatures                (selected one last, on top)
--   dust, front grass
--   x light map              (everything above is multiplied by it)
--   + glow                   (mushroom caps, fireflies, spores, eyes, motes)
--   + shafts of light
--   marker, path

local Backdrop = require('world.render.backdrop')
local Rock = require('world.render.rock')
local Lighting = require('world.render.lighting')
local Flora = require('world.flora')
local Ambience = require('world.ambience')
local Particles = require('fx.particles')
local Marker = require('fx.marker')
local P = require('world.render.palette')

local Scene = {}
Scene.__index = Scene

function Scene.new(world)
    local self = setmetatable({}, Scene)
    self.world = world
    local level = world.level
    self.backdrop = Backdrop.new(level)
    self.rock = Rock.new(level)
    self.lighting = Lighting.new(level)
    self.marker = Marker.new()

    world.flora = Flora.new(level, world)
    world.ambience = Ambience.new(level, world)
    world.fx = Particles.new()
    world.events:on(function(ev) world.fx:on_event(ev) end)
    world.events:on(function(ev) self:on_event(ev) end)

    self.shake = 0
    self.path_alpha = 0
    self.show_nav = false
    self.debug = false
    return self
end

function Scene:bake(scale)
    self.backdrop:bake(scale)
    self.rock:bake(scale)
end

function Scene:on_event(ev)
    if ev.kind == 'land' and (ev.impact or 0) > 520 then
        self.shake = math.max(self.shake, math.min(1, (ev.impact - 520) / 400))
    elseif ev.kind == 'arrived' and ev.who == self.world:selected_creature() then
        self.marker:clear()
    end
end

function Scene:update(dt)
    self.marker:update(dt)
    self.shake = math.max(0, self.shake - dt * 3)
    self.path_alpha = math.max(0.3, self.path_alpha - dt * 0.4)
end

function Scene:set_goal(node, ok)
    local c = self.world:selected_creature()
    if node and ok then
        self.marker:set(node.x, node.y, node.nx, node.ny, c.color_name)
        self.path_alpha = 1
    end
end

-- Offset for screen shake (virtual px)
function Scene:shake_offset(time)
    if self.shake <= 0 then return 0, 0 end
    local s = self.shake * self.shake * 3
    return math.sin(time * 83) * s, math.cos(time * 71) * s
end

function Scene:draw(time, alpha)
    local world = self.world
    local level = world.level
    local light_dir = world.light_dir
    local ctx = {light_dir = light_dir}
    local selected = world:selected_creature()

    world:interpolate(alpha or 1)

    -- Light map for this frame
    local lighting = self.lighting
    lighting:begin()
    world.flora:add_lights(lighting, time)
    world.ambience:add_lights(lighting, time)
    world.fx:add_lights(lighting)
    for _, c in ipairs(world.creatures) do
        local x, y, r, g, b, radius = c:light()
        if radius > 0 then lighting:add(x, y, r, g, b, radius, 0.55) end
    end
    -- A soft lantern follows whoever you're guiding
    local sx, sy = selected:anchor()
    lighting:add(sx, sy - 14, 1, 0.86, 0.7, 120, 0.5)
    lighting:render(time)

    -- Back to front
    self.backdrop:draw(time)
    world.flora:draw_vines(light_dir)
    self.rock:draw()
    world.flora:draw_grass(false)
    world.flora:draw_mushrooms(time)
    world.ambience:draw(time)
    for _, c in ipairs(world.creatures) do
        if c.draw_trail then c:draw_trail() end
    end
    if not self.xray then
        for _, c in ipairs(world.creatures) do
            if c ~= selected then c:draw(ctx) end
        end
        selected:draw(ctx)
    end
    world.fx:draw()
    world.flora:draw_grass(true)

    if not self.nolight then lighting:apply() end

    -- Glow
    world.flora:draw_glow(lighting, time)
    world.ambience:draw_glow(lighting, time)
    world.fx:draw_glow(lighting)
    love.graphics.push('all')
    love.graphics.setBlendMode('add')
    for _, c in ipairs(world.creatures) do
        if c.draw_emissive then c:draw_emissive() end
        if c.key == 'blob' then
            local x, y = c:centroid()
            lighting:glow(x, y, 40, 0.35, 1, 0.85, 0.06)
        end
    end
    love.graphics.pop()
    lighting:draw_rays(time)

    -- X-ray: a faint blueprint of the selected creature's graph, then every
    -- body as the simulation sees it, glowing
    if self.xray then
        love.graphics.push('all')
        love.graphics.setBlendMode('add')
        world.graphs[world.selected]:draw_debug(0.45)
        for _, c in ipairs(world.creatures) do c:draw_xray(ctx) end
        love.graphics.pop()
    end

    -- Guidance
    local ctrl = world.controllers[world.selected]
    if ctrl:has_path() then
        ctrl:draw_path(self.path_alpha, selected.color_name, time)
    end
    if not self.hide_marker then self.marker:draw(lighting, time) end

    if self.show_nav then
        world.graphs[world.selected]:draw_debug()
    end
    if self.debug then
        for _, c in ipairs(world.creatures) do c:draw_debug() end
    end

    world:restore()
end

return Scene
