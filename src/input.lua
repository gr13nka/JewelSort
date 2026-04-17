-- input.lua
-- Unified mouse+touch → semantic tap events.
-- Each tap produces one of:
--   {kind = "grid", gx, gy}
--   {kind = "shelf", index}       -- index may be 0 for empty-shelf region
--   {kind = "outside"}

local render = require("src.render")

local M = {}

function M.classify(level, layout, sx, sy)
    -- Shelf area first (it sits below the grid area).
    local a = layout.shelf_area
    if sx >= a.x and sx <= a.x + a.w and sy >= a.y and sy <= a.y + a.h then
        local idx = render.screen_to_shelf(
            layout, #level.shelf, sx, sy, level.shelf_capacity
        ) or 0
        return { kind = "shelf", index = idx }
    end

    local gx, gy = render.screen_to_grid(layout, sx, sy)
    if gx ~= nil then
        return { kind = "grid", gx = gx, gy = gy }
    end
    return { kind = "outside" }
end

function M.dispatch(level, tap)
    if tap.kind == "grid" then
        level:tap_cell(tap.gx, tap.gy)
    elseif tap.kind == "shelf" then
        if tap.index > 0 then
            level:tap_shelf_jewel(tap.index)
        else
            level:tap_shelf_empty()
        end
    else
        level:cancel_hover()
    end
end

return M
