-- cluster.lua
-- Iterative BFS flood-fill helpers.
-- IMPORTANT: no recursion and no jump-label statements anywhere.
-- love.js / Fengari has a small JS stack and buggy support for those jumps,
-- so everything here uses explicit queues and early returns.

local M = {}

-- Color equality with a little tolerance (PNG roundtrip can shift by 1/255).
local function color_eq(a, b)
    if a == nil or b == nil then return false end
    local tol = 2 / 255
    return math.abs(a[1] - b[1]) <= tol
        and math.abs(a[2] - b[2]) <= tol
        and math.abs(a[3] - b[3]) <= tol
end
M.color_eq = color_eq

local function key(x, y)
    return x .. "," .. y
end

-- Given a grid (map of key -> cell) and a starting (x,y), return a list of
-- {x,y} positions forming the 8-connected cluster (orthogonal + diagonal)
-- of cells where predicate(cell) is true AND matches the starting cell
-- under the predicate `same(a, b)`. Iterative BFS.
function M.flood_cells(grid, sx, sy, predicate, same)
    local result = {}
    local seen = {}
    local start = grid[key(sx, sy)]
    if start == nil then return result end
    if not predicate(start) then return result end

    local queue = { { sx, sy } }
    seen[key(sx, sy)] = true

    local head = 1
    while head <= #queue do
        local node = queue[head]
        head = head + 1
        local x, y = node[1], node[2]
        local cell = grid[key(x, y)]
        if cell ~= nil and predicate(cell) and same(cell, start) then
            result[#result + 1] = { x = x, y = y, cell = cell }
            local neighbors = {
                { x + 1, y     }, { x - 1, y     },
                { x,     y + 1 }, { x,     y - 1 },
                { x + 1, y + 1 }, { x + 1, y - 1 },
                { x - 1, y + 1 }, { x - 1, y - 1 },
            }
            for i = 1, 8 do
                local nx, ny = neighbors[i][1], neighbors[i][2]
                local nk = key(nx, ny)
                if not seen[nk] then
                    seen[nk] = true
                    local ncell = grid[nk]
                    if ncell ~= nil and predicate(ncell) and same(ncell, start) then
                        queue[#queue + 1] = { nx, ny }
                    end
                end
            end
        end
    end
    return result
end

-- Flood-fill connected cells whose JEWEL matches a given color, starting at (sx,sy).
-- grid is map key -> {x, y, target_color, jewel_color (or nil)}.
--
-- Locked-jewel rule: a cell where color_eq(cell.jewel, cell.target) is
-- "locked" — the player cannot lift it, and it also acts as a barrier
-- breaking flood-connectivity (two wrong-color jewels on either side of a
-- locked jewel are NOT part of the same cluster).
function M.flood_jewel_cluster(grid, sx, sy)
    local start = grid[key(sx, sy)]
    if start == nil or start.jewel == nil then return {} end
    -- Can't lift a jewel already in its correct cell.
    if color_eq(start.jewel, start.target) then return {} end
    local target = start.jewel
    return M.flood_cells(
        grid, sx, sy,
        -- Predicate: must have a jewel, AND must not be locked (jewel
        -- matches its own target). Locked cells act as walls.
        function(c)
            if c.jewel == nil then return false end
            if color_eq(c.jewel, c.target) then return false end
            return true
        end,
        function(c, _) return color_eq(c.jewel, target) end
    )
end

-- Flood-fill connected EMPTY holes whose target_color matches the given color.
function M.flood_empty_holes(grid, sx, sy, cluster_color)
    local start = grid[key(sx, sy)]
    if start == nil or start.jewel ~= nil then return {} end
    if not color_eq(start.target, cluster_color) then return {} end
    return M.flood_cells(
        grid, sx, sy,
        function(c) return c.jewel == nil end,
        function(c, _) return color_eq(c.target, cluster_color) end
    )
end

-- Pick up all shelf jewels matching a color. Shelf is a flat array of jewels.
function M.shelf_same_color(shelf, color)
    local picks = {}
    for i = 1, #shelf do
        if color_eq(shelf[i].color, color) then
            picks[#picks + 1] = i
        end
    end
    return picks
end

M.key = key

return M
