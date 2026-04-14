-- main.lua
-- LÖVE entry point for JewelSort.

local level_loader = require("src.level_loader")
local Level = require("src.level")
local render = require("src.render")
local input = require("src.input")
local shuffle = require("src.shuffle")

local game = {
    levels = {},
    current = 1,
    level = nil,
    layout = nil,
    mouse = { x = 0, y = 0 },
}

local function current_level_desc()
    if #game.levels == 0 then return nil end
    return game.levels[game.current]
end

local function rebuild_current()
    local desc = current_level_desc()
    if desc == nil then return end
    game.level = Level.new(desc)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    game.layout = render.compute_layout(game.level, w, h)
end

local function ensure_samples_exist()
    -- If levels/ has no PNGs, generate them via the bundled sample generator.
    local files = level_loader.list_level_files()
    if #files > 0 then return end
    local ok, make_samples = pcall(require, "tools.make_samples")
    if ok and make_samples and make_samples.generate then
        make_samples.generate()
    end
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest", 0)
    if love.math and love.math.setRandomSeed then
        love.math.setRandomSeed(os.time())
    end

    ensure_samples_exist()
    game.levels = level_loader.load_all()
    if #game.levels == 0 then
        return
    end
    game.current = 1
    rebuild_current()
end

function love.update(dt)
    if love.mouse then
        game.mouse.x, game.mouse.y = love.mouse.getPosition()
    end
end

function love.draw()
    if game.level == nil then
        love.graphics.clear(0.1, 0.1, 0.13)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.printf(
            "No levels found.\nDrop a PNG into levels/ and restart.",
            0, love.graphics.getHeight() / 2 - 20,
            love.graphics.getWidth(), "center"
        )
        return
    end
    render.draw(game.level, game.layout, game.mouse.x, game.mouse.y)
end

local function handle_tap(sx, sy)
    if game.level == nil then return end
    local tap = input.classify(game.level, game.layout, sx, sy)
    input.dispatch(game.level, tap)
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    handle_tap(x, y)
end

function love.touchpressed(id, x, y)
    handle_tap(x, y)
end

function love.keypressed(key)
    if key == "r" then
        rebuild_current()
    elseif key == "n" then
        if #game.levels > 0 then
            game.current = (game.current % #game.levels) + 1
            rebuild_current()
        end
    elseif key == "escape" then
        love.event.quit()
    end
end
