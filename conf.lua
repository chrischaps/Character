function love.conf(t)
    t.identity = "character"
    t.window.title = "Character - The Dusk Cave"
    t.window.width = 1280
    t.window.height = 720
    t.window.vsync = 1
    t.window.resizable = true
    t.window.minwidth = 480
    t.window.minheight = 270
    t.window.msaa = 4

    t.console = true  -- Enable console on Windows for debugging
end
