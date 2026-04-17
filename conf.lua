-- LÖVE configuration for JewelSort.
-- Portrait window sized 540x960 (design space 1080x1920, i.e. 2x).
function love.conf(t)
    t.identity = "jewelsort"
    t.window.title = "JewelSort"
    t.window.width = 540
    t.window.height = 960
    t.window.resizable = false
    t.window.vsync = 1
    t.window.highdpi = true

    -- Web-friendly: disable modules we don't use so love.js bundle is lean.
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.thread = false
    t.console = false
end
