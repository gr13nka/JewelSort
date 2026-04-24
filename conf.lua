-- LÖVE configuration for JewelSort.
-- Portrait window sized 540x960 (design space 1080x1920, i.e. 2x). The
-- window is resizable for the web / Yandex Games target; the game
-- letterboxes a 9:16 content area inside whatever viewport the host
-- gives us (see `viewport()` in main.lua).
function love.conf(t)
    t.identity = "jewelsort"
    t.window.title = "JewelSort"
    t.window.width = 540
    t.window.height = 960
    t.window.minwidth = 360
    t.window.minheight = 640
    t.window.resizable = true
    t.window.vsync = 1
    t.window.highdpi = true

    -- Web-friendly: disable modules we don't use so love.js bundle is lean.
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.thread = false
    t.console = false
end
