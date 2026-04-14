-- render.lua
-- Draws the grid, jewels, shelf, hover cluster, win overlay.
-- The layout module computes rectangles once per frame; draw reads them.

local M = {}

local BG = { 0.09, 0.10, 0.14 }
local CELL_BG = { 0.18, 0.18, 0.24 }
local HOLE = { 0.07, 0.07, 0.10 }
local SHELF_BG = { 0.13, 0.14, 0.18 }
local SHELF_EDGE = { 0.24, 0.25, 0.32 }

-- Compute layout rects for the current window + level.
-- Returns a table with:
--   grid_area, shelf_area, cell_size, origin_x, origin_y, cols, rows
function M.compute_layout(level, win_w, win_h)
    local margin = 16
    local grid_h_fraction = 2 / 3
    local grid_area = {
        x = margin,
        y = margin,
        w = win_w - margin * 2,
        h = math.floor(win_h * grid_h_fraction) - margin * 2,
    }
    local shelf_area = {
        x = margin,
        y = math.floor(win_h * grid_h_fraction),
        w = win_w - margin * 2,
        h = win_h - math.floor(win_h * grid_h_fraction) - margin,
    }
    local cols = level.width
    local rows = level.height
    local cell_w = grid_area.w / cols
    local cell_h = grid_area.h / rows
    local cell_size = math.floor(math.min(cell_w, cell_h))
    local grid_pixel_w = cell_size * cols
    local grid_pixel_h = cell_size * rows
    local origin_x = grid_area.x + math.floor((grid_area.w - grid_pixel_w) / 2)
    local origin_y = grid_area.y + math.floor((grid_area.h - grid_pixel_h) / 2)
    return {
        grid_area = grid_area,
        shelf_area = shelf_area,
        cell_size = cell_size,
        origin_x = origin_x,
        origin_y = origin_y,
        cols = cols,
        rows = rows,
    }
end

-- Screen coordinates -> grid (gx, gy) or nil if outside grid.
function M.screen_to_grid(layout, sx, sy)
    local gx = math.floor((sx - layout.origin_x) / layout.cell_size)
    local gy = math.floor((sy - layout.origin_y) / layout.cell_size)
    if gx < 0 or gy < 0 or gx >= layout.cols or gy >= layout.rows then
        return nil
    end
    return gx, gy
end

-- Screen coords -> shelf index (1..N) or nil.
function M.screen_to_shelf(layout, shelf_len, sx, sy)
    local a = layout.shelf_area
    if sx < a.x or sx > a.x + a.w or sy < a.y or sy > a.y + a.h then
        return nil
    end
    if shelf_len <= 0 then return 0 end -- inside shelf but empty
    local slot = math.min(
        math.floor(a.w / math.max(shelf_len, 1)),
        math.floor(a.h * 0.7)
    )
    slot = math.max(slot, 8)
    local rel = sx - a.x
    local idx = math.floor(rel / slot) + 1
    if idx < 1 then return 0 end
    if idx > shelf_len then return 0 end
    return idx
end

local function draw_rounded_rect(x, y, w, h, r)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
end

local function draw_cell(x, y, size, jewel_color, hovering)
    love.graphics.setColor(CELL_BG)
    draw_rounded_rect(x + 2, y + 2, size - 4, size - 4, 6)
    love.graphics.setColor(HOLE)
    love.graphics.circle("fill", x + size / 2, y + size / 2, size * 0.36)
    if jewel_color ~= nil and not hovering then
        love.graphics.setColor(jewel_color[1], jewel_color[2], jewel_color[3], 1)
        love.graphics.circle("fill", x + size / 2, y + size / 2, size * 0.34)
        -- Highlight
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.circle(
            "fill",
            x + size / 2 - size * 0.08,
            y + size / 2 - size * 0.10,
            size * 0.10
        )
    end
end

local function draw_jewel(cx, cy, radius, color, lifted)
    if lifted then
        -- Shadow
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.circle("fill", cx + 2, cy + 8, radius)
    end
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.circle("fill", cx, cy, radius)
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.circle("fill", cx - radius * 0.25, cy - radius * 0.3, radius * 0.3)
end

function M.draw(level, layout, mouse_x, mouse_y)
    love.graphics.clear(BG)

    -- Grid
    local origin_x, origin_y = layout.origin_x, layout.origin_y
    local size = layout.cell_size

    -- First collect which cells are "hovering" (origin of current hover cluster)
    local hovering_cells = {}
    if level.state.kind == "hovering" and level.state.source == "grid" then
        for i = 1, #(level.state.origin_cells or {}) do
            local oc = level.state.origin_cells[i]
            hovering_cells[oc.x .. "," .. oc.y] = true
        end
    end

    for i = 1, #level.cell_list do
        local c = level.cell_list[i]
        local x = origin_x + c.x * size
        local y = origin_y + c.y * size
        local hv = hovering_cells[c.x .. "," .. c.y] == true
        draw_cell(x, y, size, c.jewel, hv)
    end

    -- Shelf strip
    local s = layout.shelf_area
    love.graphics.setColor(SHELF_BG)
    draw_rounded_rect(s.x, s.y, s.w, s.h, 10)
    love.graphics.setColor(SHELF_EDGE)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", s.x, s.y, s.w, s.h, 10, 10)

    -- Sort shelf jewels so same colors group adjacent, without mutating.
    local shelf_indices = {}
    for i = 1, #level.shelf do shelf_indices[i] = i end
    table.sort(shelf_indices, function(a, b)
        local ca = level.shelf[a].color
        local cb = level.shelf[b].color
        if ca[1] ~= cb[1] then return ca[1] < cb[1] end
        if ca[2] ~= cb[2] then return ca[2] < cb[2] end
        return ca[3] < cb[3]
    end)

    local shelf_len = #level.shelf
    if shelf_len > 0 then
        local slot = math.min(
            math.floor(s.w / shelf_len),
            math.floor(s.h * 0.7)
        )
        slot = math.max(slot, 8)
        local r = math.floor(slot * 0.38)
        local cy = s.y + s.h / 2
        for i = 1, shelf_len do
            local jewel = level.shelf[shelf_indices[i]]
            local cx = s.x + (i - 0.5) * slot
            draw_jewel(cx, cy, r, jewel.color, false)
        end
    else
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.printf(
            "(empty shelf — tap here to park a cluster)",
            s.x, s.y + s.h / 2 - 8, s.w, "center"
        )
    end

    -- Hover cluster drifts near mouse/tap location.
    if level.state.kind == "hovering" then
        local col = level.state.color
        local n = #level.state.jewels
        local r = math.floor(size * 0.34)
        local row_size = math.ceil(math.sqrt(n))
        for i = 1, n do
            local rowi = math.floor((i - 1) / row_size)
            local coli = (i - 1) % row_size
            local cx = mouse_x + (coli - (row_size - 1) / 2) * (r * 2 + 4)
            local cy = mouse_y + (rowi - (row_size - 1) / 2) * (r * 2 + 4)
            draw_jewel(cx, cy, r, col, true)
        end
    end

    -- HUD / status
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf(
        "JewelSort — " .. (level.desc.name or ""),
        0, 4, love.graphics.getWidth(), "center"
    )
    if level.state.kind == "hovering" then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.printf(
            "Tap a matching hole, the shelf, or elsewhere to cancel",
            0, 22, love.graphics.getWidth(), "center"
        )
    end

    -- Win overlay
    if level.won then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle(
            "fill", 0, 0,
            love.graphics.getWidth(), love.graphics.getHeight()
        )
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(
            "Solved!",
            0, love.graphics.getHeight() / 2 - 20,
            love.graphics.getWidth(), "center"
        )
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.printf(
            "Press N for next level, R to reshuffle",
            0, love.graphics.getHeight() / 2 + 10,
            love.graphics.getWidth(), "center"
        )
    end
end

return M
