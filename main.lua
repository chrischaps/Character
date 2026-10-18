-- Character v2: The Dusk Cave
-- Procedural creatures living in an overgrown cave at dusk.
-- Click to guide the selected creature; the others wander on their own.
-- Press H in-game for controls; see dev.lua for headless verification modes.

love.filesystem.setRequirePath("libs/?.lua;libs/?/init.lua;" .. love.filesystem.getRequirePath())

local scaling = require('LoveLibs.graphics.scaling')
local PostFX = require('LoveLibs.graphics.postfx')
local music = require('LoveLibs.audio.music')
local overlay = require('LoveLibs.core.debug')

local dev = require('dev')
local log = require('core.log')
local rng = require('core.rng')
local Synth = require('core.synth')
local World = require('world.world')
local Scene = require('world.render.scene')
local Hud = require('ui.hud')
local cave = require('world.levels.cave')

local VW, VH = cave.width, cave.height
local FIXED_DT = 1 / 120

local args = dev.parse(arg or {})
local world, scene, hud, synth
local acc = 0
local paused = false
local snap_frames = nil
local snap_shot = nil
local bench = nil
local render_scale = 0
local capture = nil      -- --script mode: {co = coroutine, last = canvas}
local script_api        -- defined below love.load; forward-declared so load can see it

-- Fit the virtual cave into a w x h target (letterboxed), optionally zoomed
-- around a virtual point: zoom = {x, y, z}
local function view(w, h, zoom)
    w, h = w or love.graphics.getWidth(), h or love.graphics.getHeight()
    local s = math.min(w / VW, h / VH)
    local ox, oy = (w - VW * s) / 2, (h - VH * s) / 2
    zoom = zoom or args.zoom
    if zoom then
        s = s * (zoom.z or 2)
        ox = w / 2 - zoom.x * s
        oy = h / 2 - zoom.y * s
    end
    return s, ox, oy
end

-- Static layers are baked at render resolution (capped: past 4x the extra
-- pixels cost memory without adding anything you can see)
local function rebake(s)
    s = math.min(s, 4)
    if math.abs(s - render_scale) > 1e-3 then
        render_scale = s
        scene:bake(s)
    end
end

-- Draw one whole frame (scene, post effects, HUD) into the current target.
-- opts: zoom, hud (default true), alpha
local function draw_frame(w, h, opts)
    opts = opts or {}
    local s, ox, oy = view(w, h, opts.zoom)
    rebake(s)
    local time = world.time

    PostFX.beginScene()
    love.graphics.clear(0.03, 0.025, 0.05, 1)
    love.graphics.push()
    local sx, sy = scene:shake_offset(time)
    love.graphics.translate(ox + sx * s, oy + sy * s)
    love.graphics.scale(s)
    if not opts.zoom then love.graphics.setScissor(ox, oy, VW * s, VH * s) end
    scene:draw(time, opts.alpha or 1)
    love.graphics.setScissor()
    love.graphics.pop()
    -- PostFX draws its canvases with the current colour: make sure it's white
    love.graphics.setColor(1, 1, 1, 1)
    PostFX.endScene(1, 0, 0)

    if opts.hud ~= false then
        hud.paused, hud.muted = paused, synth.muted
        hud:draw(world, function(x, y) return ox + x * s, oy + y * s end, s)
    end
end

local function select_creature(i)
    if i == world.selected or not world.creatures[i] then return end
    world:select(i)
    hud:announce()
    local x = world:selected_creature():anchor()
    synth:chime(i + 1, x)
end

function love.load()
    rng.seed(args.seed or 7)
    if args.selftest then
        love.event.quit(dev.selftest(World, cave, FIXED_DT) and 0 or 1)
        return
    end
    if args.navdump then
        dev.navdump(World, cave, args.navdump.who, args.navdump.solid)
        love.event.quit()
        return
    end

    love.graphics.setDefaultFilter('linear', 'linear')
    scaling.init(VW, VH)
    PostFX.init(love.graphics.getWidth(), love.graphics.getHeight(), {
        distortion = {enabled = false},
        bloom = {enabled = true, threshold = 0.7, softness = 0.18, intensity = 0.5, radius = 3.2},
        colorGrade = {
            enabled = true, saturation = 0.08, contrast = 0.07, warmth = 0.02,
            vignetteStrength = 0.3, vignetteRadius = 0.78,
            shadowTint = {0.12, 0.05, 0.24}, highlightTint = {1.0, 0.95, 0.88},
        },
    })

    world = World.new(cave, {wander = not args.nowander})
    scene = Scene.new(world)
    hud = Hud.new()
    synth = Synth.new()
    world.events:on(function(ev) synth:on_event(ev, world:selected_creature()) end)
    rebake(view())

    overlay.addGlobalInfo("sim time", function() return world.time end)
    function world:getDebugInfo()
        local c = self:selected_creature()
        local ctrl = self.controllers[self.selected]
        local step = ctrl.path and ctrl.path[ctrl.i]
        local x, y = c:anchor()
        return {
            {section = c:get_name()},
            {key = "anchor", value = string.format("%.0f, %.0f", x, y)},
            {key = "state", value = c.mode or c.mover.state},
            {key = "support", value = (c.solid or c.mover.solid or {}).id or "-"},
            {section = "Navigation"},
            {key = "graph", value = #self.graphs[self.selected].nodes .. " nodes"},
            {key = "step", value = step and (ctrl.i .. "/" .. #ctrl.path .. " " .. (step.edge and step.edge.kind or "walk")) or "idle"},
            {key = "repaths", value = tostring(ctrl.repaths)},
        }
    end

    if args.snap then
        synth.muted = true
        for i, def in ipairs(World.CREATURES) do
            if def.key == args.snap.who then world:select(i) end
        end
        if args.goal then
            local node, ok = world:click(args.goal.x, args.goal.y)
            scene:set_goal(node, ok)
        end
        scene.debug = args.debug
        scene.show_nav = args.nav
        scene.nolight = args.nolight
        PostFX.bypass = args.nopost or false
        local steps = math.floor((args.snap.seconds or 1) / FIXED_DT)
        for s = 1, steps do
            world:snapshot()
            world:step(FIXED_DT)
            scene:update(FIXED_DT)
        end
        hud.title_t = 1
        hud.hint = 0
        hud.help = args.help
        if args.debug then overlay.show() end
        snap_frames = 0
    elseif not args.script then
        music.play('calm')
        music.setVolume(0.55)
    end
    if args.script then
        synth.muted = true
        local chunk, err = love.filesystem.load(args.script)
        if not chunk then error(err) end
        local script = chunk()
        local api = script_api()
        capture = {co = coroutine.create(function() script.run(api) end)}
    end
    if args.bench then
        love.window.setVSync(0)
        love.window.setMode(1920, 1080, {vsync = 0, resizable = true, msaa = 4})
        scaling.resize(1920, 1080)
        PostFX.resize(1920, 1080)
        synth.muted = true
        music.setVolume(0)
        bench = {t = 0, frames = 0, worst = 0}
    end
end

-- The API a --script capture file drives. Rendering is offscreen at any size,
-- and time only moves when the script steps it, so captures are exact.
function script_api()
    local api = {world = world, scene = scene, hud = hud, PostFX = PostFX, FIXED_DT = FIXED_DT, VW = VW, VH = VH}
    local canvases = {}
    local post_size = {0, 0}

    -- Advance the simulation (and everything that animates) by `seconds`
    function api.step(seconds)
        local n = math.max(1, math.floor(seconds / FIXED_DT + 0.5))
        for _ = 1, n do
            world:snapshot()
            world:step(FIXED_DT)
        end
        scene:update(n * FIXED_DT)
        hud:update(n * FIXED_DT)
    end

    -- Render a full frame into a w x h canvas and return it.
    -- opts: zoom = {x, y, z}, hud = bool, plus scene flags (xray, show_nav, debug, nolight, hide_marker)
    function api.render(w, h, opts)
        opts = opts or {}
        local key = w .. 'x' .. h
        local target = canvases[key]
        if not target then
            target = love.graphics.newCanvas(w, h)
            canvases[key] = target
        end
        if post_size[1] ~= w or post_size[2] ~= h then
            PostFX.resize(w, h)
            post_size[1], post_size[2] = w, h
        end
        local flags = {'xray', 'show_nav', 'debug', 'nolight', 'hide_marker'}
        local saved = {}
        for i, k in ipairs(flags) do
            saved[i] = scene[k]
            if opts[k] ~= nil then scene[k] = opts[k] end
        end
        -- PostFX ends by drawing "to the screen" (setCanvas()); send that to our target
        local set = love.graphics.setCanvas
        love.graphics.setCanvas = function(...)
            if select('#', ...) == 0 or (...) == nil then return set(target) end
            return set(...)
        end
        set(target)
        love.graphics.clear(0, 0, 0, 1)
        local ok, err = pcall(draw_frame, w, h, {zoom = opts.zoom, hud = opts.hud == true, alpha = 1})
        love.graphics.setCanvas = set
        set()
        for i, k in ipairs(flags) do scene[k] = saved[i] end  -- nil-safe restore
        if not ok then error(err, 0) end
        capture.last = target
        return target
    end

    -- Save a canvas as PNG in the save directory
    function api.save(canvas, file)
        canvas:newImageData():encode('png', file)
        log.info('dev', 'saved %s/%s', love.filesystem.getSaveDirectory(), file)
    end

    function api.click(x, y)
        local node, ok = world:click(x, y)
        if node and ok then scene:set_goal(node, ok) end
        return node, ok
    end

    function api.select(i) world:select(i) end
    function api.yield() coroutine.yield() end
    api.log = function(...) log.info('dev', ...) end
    return api
end

function love.update(dt)
    if not world then return end
    if capture then
        local ok, err = coroutine.resume(capture.co)
        if not ok then
            print('[script] ' .. tostring(err))
            print(debug.traceback(capture.co))
            love.event.quit(1)
        elseif coroutine.status(capture.co) == 'dead' then
            love.event.quit(0)
        end
        return
    end
    if snap_frames then return end
    if bench then
        bench.t, bench.frames = bench.t + dt, bench.frames + 1
        if bench.t > 1 then bench.worst = math.max(bench.worst, dt) end
        if bench.t > 1 and bench.frames % 240 == 0 then
            -- keep everyone busy: send the selected creature somewhere new
            select_creature(bench.frames / 240 % 3 + 1)
            local g = world.graphs[world.selected]
            world.controllers[world.selected]:go_to(g:random_node(rng.look))
        end
        if bench.t > args.bench then
            log.info('dev', '%d frames in %.1fs: avg %.2f ms (%.0f fps), worst %.2f ms, mem %.1f MB',
                bench.frames, bench.t, bench.t / bench.frames * 1000, bench.frames / bench.t,
                bench.worst * 1000, collectgarbage('count') / 1024)
            love.event.quit()
        end
    end
    dt = math.min(dt, 0.1)

    if not paused then
        acc = acc + dt
        while acc >= FIXED_DT do
            world:snapshot()
            world:step(FIXED_DT)
            acc = acc - FIXED_DT
        end
        scene:update(dt)
    end
    hud:update(dt)
    synth:update(dt, world)
    music.update(dt)
    PostFX.update(dt)
end

function love.draw()
    if not world then return end
    if capture then
        -- Show the last captured frame while a script runs
        if capture.last then
            local cw, ch = capture.last:getDimensions()
            local k = math.min(love.graphics.getWidth() / cw, love.graphics.getHeight() / ch)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(capture.last, 0, 0, 0, k, k)
        end
        return
    end
    draw_frame(nil, nil, {alpha = snap_frames and 1 or (acc / FIXED_DT)})
    overlay.draw(world)

    if snap_frames then
        snap_frames = snap_frames + 1
        local fr = args.frames or {n = 1, every = 0}
        local file = args.snap.file or 'snap.png'
        if fr.n > 1 then file = file:gsub('%.png$', '') .. '_' .. (snap_shot or 1) .. '.png' end
        if snap_frames == 2 then
            love.graphics.captureScreenshot(file)
        elseif snap_frames > 3 then
            log.info('dev', 'saved %s/%s', love.filesystem.getSaveDirectory(), file)
            snap_shot = (snap_shot or 1) + 1
            if snap_shot > fr.n then
                love.event.quit()
            else
                for _ = 1, math.floor(fr.every / FIXED_DT) do
                    world:snapshot()
                    world:step(FIXED_DT)
                    scene:update(FIXED_DT)
                end
                snap_frames = 0
            end
        end
    end
end

function love.resize(w, h)
    scaling.resize(w, h)
    PostFX.resize(w, h)
end

function love.mousepressed(x, y, button)
    if not world or snap_frames or button ~= 1 then return end
    local vx, vy = scaling.toVirtual(x, y)
    if vx < 0 or vy < 0 or vx > VW or vy > VH then return end
    local node, ok = world:click(vx, vy)
    hud:clicked()
    if node and ok then
        scene:set_goal(node, ok)
        synth:chime(1 + (math.floor(node.x / 120) % 5), node.x)
    else
        scene.marker:reject(vx, vy)
        synth:nope(vx)
    end
end

function love.keypressed(key)
    if not world then return end
    if key == 'escape' then love.event.quit()
    elseif key == 'tab' then select_creature(world.selected % #world.creatures + 1)
    elseif key == '1' or key == '2' or key == '3' then select_creature(tonumber(key))
    elseif key == 'h' then hud.help = not hud.help
    elseif key == 'n' then scene.show_nav = not scene.show_nav
    elseif key == 'x' then scene.xray = not scene.xray
    elseif key == 'd' then
        scene.debug = not scene.debug
        log.enabled = scene.debug
        overlay.toggle()
    elseif key == 'w' then world.wander = not world.wander
    elseif key == 'p' then paused = not paused
    elseif key == 'm' then
        synth.muted = not synth.muted
        music.setVolume(synth.muted and 0 or 0.55)
    elseif key == 'r' then
        world:reset()
        scene.marker:clear()
    elseif key == 'f' then
        love.window.setFullscreen(not love.window.getFullscreen(), 'desktop')
    else
        PostFX.handleKeyPress(key)
    end
end
