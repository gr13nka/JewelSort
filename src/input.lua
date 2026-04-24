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
        return { kind = "shelf", index = idx, sx = sx, sy = sy }
    end

    -- Only accept grid taps that fall inside the visible board rect. With
    -- zoom > 1 the grid can extend past the board, and without this gate a
    -- tap outside the board would still resolve to a grid cell through
    -- screen_to_grid's inverse math.
    local ga = layout.grid_area
    if sx >= ga.x and sx <= ga.x + ga.w and sy >= ga.y and sy <= ga.y + ga.h then
        local gx, gy = render.screen_to_grid(layout, sx, sy)
        if gx ~= nil then
            return { kind = "grid", gx = gx, gy = gy, sx = sx, sy = sy }
        end
    end
    return { kind = "outside", sx = sx, sy = sy }
end

function M.dispatch(level, tap)
    if tap.kind == "grid" then
        level:tap_cell(tap.gx, tap.gy, tap.sx, tap.sy)
    elseif tap.kind == "shelf" then
        if tap.index > 0 then
            level:tap_shelf_jewel(tap.index, tap.sx, tap.sy)
        else
            level:tap_shelf_empty(tap.sx, tap.sy)
        end
    else
        level:cancel_hover()
    end
end

return M
