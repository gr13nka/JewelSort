-- shuffle.lua
-- Fisher-Yates shuffle using love.math.random.
-- Guarantees the shuffled state is NOT already solved. Solvability is
-- trivially guaranteed because we only permute jewels across existing cells:
-- the multiset of jewels equals the multiset of target colors, so a solution
-- always exists.

local cluster = require("src.cluster")

local M = {}

local function rand(n)
    if love and love.math and love.math.random then
        return love.math.random(n)
    end
    return math.random(n)
end

function M.shuffle_in_place(arr)
    local n = #arr
    for i = n, 2, -1 do
        local j = rand(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

-- Returns true if every cell's jewel matches its target color.
local function is_solved(cells)
    for i = 1, #cells do
        local c = cells[i]
        if c.jewel == nil then return false end
        if not cluster.color_eq(c.jewel, c.target) then return false end
    end
    return true
end

-- Swap two cells whose target colors differ, so shuffled state isn't solved.
local function swap_any_mismatched_pair(cells)
    for i = 1, #cells do
        for j = i + 1, #cells do
            if not cluster.color_eq(cells[i].target, cells[j].target) then
                cells[i].jewel, cells[j].jewel = cells[j].jewel, cells[i].jewel
                return true
            end
        end
    end
    return false
end

-- Shuffle jewels across the given cells list. Each cell already has .target;
-- initially each cell.jewel = copy of .target. We shuffle the jewel values
-- among cells, preserving the multiset.
function M.shuffle_jewels(cells)
    local jewels = {}
    for i = 1, #cells do
        jewels[i] = cells[i].jewel
    end
    M.shuffle_in_place(jewels)
    for i = 1, #cells do
        cells[i].jewel = jewels[i]
    end
    if is_solved(cells) then
        swap_any_mismatched_pair(cells)
    end
end

M.is_solved = is_solved

return M
