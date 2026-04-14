-- level_loader.lua
-- Scans the `levels/` directory, reads each PNG as ImageData, walks pixels,
-- and emits a level descriptor: width, height, cells, palette.
-- Alpha 0 in the source PNG means "no cell here".

local M = {}

local function clone_color(r, g, b)
    return { r, g, b }
end

local function palette_key(r, g, b)
    -- Snap to 0-255 bucket so near-identical floats merge.
    local ir = math.floor(r * 255 + 0.5)
    local ig = math.floor(g * 255 + 0.5)
    local ib = math.floor(b * 255 + 0.5)
    return ir .. "_" .. ig .. "_" .. ib
end

function M.load_level_from_image_data(image_data, name)
    local w, h = image_data:getDimensions()
    local cells = {}
    local palette_map = {}
    local palette = {}

    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local r, g, b, a = image_data:getPixel(x, y)
            if a > 0 then
                local key = palette_key(r, g, b)
                if palette_map[key] == nil then
                    palette_map[key] = true
                    palette[#palette + 1] = clone_color(r, g, b)
                end
                cells[#cells + 1] = {
                    gx = x,
                    gy = y,
                    target = clone_color(r, g, b),
                }
            end
        end
    end

    return {
        name = name or "level",
        width = w,
        height = h,
        cells = cells,
        palette = palette,
    }
end

-- List all .png files in the `levels/` directory (love.filesystem).
function M.list_level_files()
    local out = {}
    if love == nil or love.filesystem == nil then return out end
    local items = love.filesystem.getDirectoryItems("levels") or {}
    for i = 1, #items do
        local f = items[i]
        if f:lower():match("%.png$") then
            out[#out + 1] = "levels/" .. f
        end
    end
    table.sort(out)
    return out
end

function M.load_level_from_path(path)
    if love == nil or love.image == nil then return nil end
    local data = love.image.newImageData(path)
    local name = path:match("([^/]+)%.png$") or path
    return M.load_level_from_image_data(data, name)
end

function M.load_all()
    local files = M.list_level_files()
    local levels = {}
    for i = 1, #files do
        local ok, lvl = pcall(M.load_level_from_path, files[i])
        if ok and lvl ~= nil and #lvl.cells > 0 then
            levels[#levels + 1] = lvl
        end
    end
    return levels
end

return M
