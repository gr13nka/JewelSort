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
    local min_x, min_y, max_x, max_y

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
                if min_x == nil or x < min_x then min_x = x end
                if min_y == nil or y < min_y then min_y = y end
                if max_x == nil or x > max_x then max_x = x end
                if max_y == nil or y > max_y then max_y = y end
            end
        end
    end

    -- Crop to the opaque-pixel bounding box so the playable grid matches
    -- the art extent rather than the authored PNG canvas. Levels authored
    -- with transparent padding (e.g. a 20×20 silhouette on a 64×64 canvas)
    -- would otherwise render with tiny cells because compute_layout divides
    -- the board by the full PNG dimensions.
    local width, height = w, h
    if min_x ~= nil then
        for i = 1, #cells do
            cells[i].gx = cells[i].gx - min_x
            cells[i].gy = cells[i].gy - min_y
        end
        width = max_x - min_x + 1
        height = max_y - min_y + 1
    end

    return {
        name = name or "level",
        width = width,
        height = height,
        cells = cells,
        palette = palette,
    }
end

-- List all .png files under `levels/`, scanning one level of subfolders.
-- Books live as subfolders (levels/<book>/*.png); top-level PNGs still count
-- (e.g. an orphaned WIP asset) so the "is levels/ empty?" presence check in
-- main.lua stays accurate. Depth is intentionally capped at 1 -- the book/
-- puzzle structure is flat two-level by design.
function M.list_level_files()
    local out = {}
    if love == nil or love.filesystem == nil then return out end
    local items = love.filesystem.getDirectoryItems("levels") or {}
    for i = 1, #items do
        local name = items[i]
        local path = "levels/" .. name
        local info = love.filesystem.getInfo(path)
        if info and info.type == "directory" then
            local inner = love.filesystem.getDirectoryItems(path) or {}
            for j = 1, #inner do
                local f = inner[j]
                if f:lower():match("%.png$") then
                    out[#out + 1] = path .. "/" .. f
                end
            end
        elseif name:lower():match("%.png$") then
            out[#out + 1] = path
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

-- Load one level descriptor by its path under levels/ (e.g.
-- "starter/smile.png"). Returns descriptor or nil on failure.
function M.load_by_file(file)
    if file == nil then return nil end
    local path = file
    if not path:match("^levels/") then
        path = "levels/" .. path
    end
    if love == nil or love.filesystem == nil then return nil end
    if not love.filesystem.getInfo(path) then return nil end
    local ok, lvl = pcall(M.load_level_from_path, path)
    if ok and lvl ~= nil and #lvl.cells > 0 then return lvl end
    return nil
end

-- Render a small canvas thumbnail of a level descriptor. Each opaque cell
-- becomes a target-color pixel block. Callers should cache the result.
function M.render_thumbnail(desc, max_px)
    if desc == nil or love == nil or love.graphics == nil then return nil end
    max_px = max_px or 96
    local cell = math.max(1, math.floor(max_px / math.max(desc.width, desc.height)))
    local w = desc.width * cell
    local h = desc.height * cell
    local canvas = love.graphics.newCanvas(w, h)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    for i = 1, #desc.cells do
        local c = desc.cells[i]
        love.graphics.setColor(c.target[1], c.target[2], c.target[3], 1)
        love.graphics.rectangle("fill", c.gx * cell, c.gy * cell, cell, cell)
    end
    love.graphics.setCanvas()
    love.graphics.pop()
    return canvas
end

return M
