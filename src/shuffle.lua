-- shuffle.lua
-- Fisher-Yates shuffle of jewels across cells.
--
-- Why not a forward-play scrambler?
--   Forward moves in this game only place a jewel into a cell whose TARGET
--   matches the jewel color. So forward play from the solved state can never
--   produce a real mismatch (a cell holding a jewel of the wrong target). A
--   true scramble requires permuting jewels across cells directly.
--
-- Solvability:
--   With a generous shelf capacity (12 for the default palette sizes of
--   3–6 colors) any Fisher-Yates permutation on the sample levels is
--   solvable. As a safety net, we run a cheap greedy solver on the shuffled
--   state; if it can't solve within a step budget, we reshuffle.
--
-- No goto, no recursion, iterative loops only (love.js / Fengari friendly).

local cluster = require("src.cluster")

local M = {}

M.SHELF_CAPACITY = 12

local function copy_color(c)
    return { c[1], c[2], c[3] }
end

local function rand(n)
    if love and love.math and love.math.random then
        return love.math.random(n)
    end
    return math.random(n)
end

local function is_solved(cells)
    for i = 1, #cells do
        local c = cells[i]
        if c.jewel == nil then return false end
        if not cluster.color_eq(c.jewel, c.target) then return false end
    end
    return true
end
M.is_solved = is_solved

-- Fisher-Yates on an array, in place.
local function fisher_yates(arr)
    local n = #arr
    for i = n, 2, -1 do
        local j = rand(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

-- Snapshot / restore helpers — we shuffle, then run the greedy solver on a
-- copy so we don't mutate the real grid while sanity-checking.
local function snapshot_jewels(cell_list)
    local snap = {}
    for i = 1, #cell_list do
        local c = cell_list[i]
        snap[i] = c.jewel and copy_color(c.jewel) or nil
    end
    return snap
end

local function restore_jewels(cell_list, snap)
    for i = 1, #cell_list do
        cell_list[i].jewel = snap[i] and copy_color(snap[i]) or nil
    end
end

-- Greedy solver over a virtual shelf and the live grid. Returns true if the
-- state is solvable within the step budget; mutates the grid in the process.
-- Strategy per step, in priority order:
--   1. If shelf has a jewel of some color C, and the grid has an empty cell
--      with target C, deposit (flood-fill) and continue.
--   2. Else lift the smallest 8-connected same-color cluster from any cell
--      currently in a WRONG target cell, onto the shelf (if it fits).
-- Termination: either solved, step budget exhausted, or no legal move.
local function greedy_solve(grid, cell_list, shelf_cap, budget)
    local shelf = {}
    local steps = 0
    while steps < budget do
        steps = steps + 1
        if is_solved(cell_list) then return true end

        -- 1. Try shelf→grid.
        local placed = false
        if #shelf > 0 then
            -- Pick any shelf color that has a matching empty hole.
            for i = 1, #shelf do
                local color = shelf[i].color
                -- Find an empty target-matching hole.
                local target_cell = nil
                for ci = 1, #cell_list do
                    local c = cell_list[ci]
                    if c.jewel == nil and cluster.color_eq(c.target, color) then
                        target_cell = c
                        break
                    end
                end
                if target_cell ~= nil then
                    local holes = cluster.flood_empty_holes(
                        grid, target_cell.x, target_cell.y, color
                    )
                    -- Count shelf jewels of this color.
                    local shelf_ct = 0
                    for si = 1, #shelf do
                        if cluster.color_eq(shelf[si].color, color) then
                            shelf_ct = shelf_ct + 1
                        end
                    end
                    local n = math.min(#holes, shelf_ct)
                    if n > 0 then
                        for j = 1, n do
                            holes[j].cell.jewel = copy_color(color)
                        end
                        local removed = 0
                        for si = #shelf, 1, -1 do
                            if removed >= n then break end
                            if cluster.color_eq(shelf[si].color, color) then
                                table.remove(shelf, si)
                                removed = removed + 1
                            end
                        end
                        placed = true
                        break
                    end
                end
            end
        end

        if not placed then
            -- 2. Lift a cluster from a misplaced cell onto shelf. Prefer the
            -- smallest cluster to avoid exceeding cap. Scan non-locked cells.
            local best = nil
            local best_size = math.huge
            for ci = 1, #cell_list do
                local c = cell_list[ci]
                if c.jewel ~= nil and not cluster.color_eq(c.jewel, c.target) then
                    -- Use an UNLOCKED flood: the normal flood skips
                    -- correctly-placed cells, which is fine here since we
                    -- want the exact cluster the player would lift.
                    local picks = cluster.flood_jewel_cluster(grid, c.x, c.y)
                    if #picks > 0 and #picks < best_size
                        and (#shelf + #picks) <= shelf_cap
                    then
                        best = picks
                        best_size = #picks
                    end
                end
            end
            if best == nil then
                return false
            end
            for i = 1, #best do
                local p = best[i]
                shelf[#shelf + 1] = { color = copy_color(p.cell.jewel) }
                p.cell.jewel = nil
            end
        end
    end
    return is_solved(cell_list)
end

-- Count jewels per target color across the level. The multiset of jewels
-- equals the multiset of targets (scramble is a permutation of the solved
-- board), so this doubles as the jewel-pool histogram.
local function count_color_multiset(cell_list)
    local keys = {}      -- stable string key -> canonical color array
    local counts = {}    -- same key -> count
    for i = 1, #cell_list do
        local t = cell_list[i].target
        local k = string.format("%.4f,%.4f,%.4f", t[1], t[2], t[3])
        if counts[k] == nil then
            keys[k] = t
            counts[k] = 1
        else
            counts[k] = counts[k] + 1
        end
    end
    return keys, counts
end

-- Count how many of a cell's 8 neighbors carry a jewel of the given color.
-- Pure color adjacency — no lock/mismatch filter. Used by the repair pass
-- to decide "is this jewel lonely?" without paying for a full BFS.
local function neighbor_color_count(grid, x, y, color)
    local n = 0
    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nc = grid[cluster.key(x + dx, y + dy)]
                if nc ~= nil and nc.jewel ~= nil
                    and cluster.color_eq(nc.jewel, color)
                then
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- Grow tiny (≤ 2 same-color neighbors) clusters by swapping lonely jewels
-- with an 8-neighbor, but only if the swap keeps the derangement (neither
-- jewel lands on its own target) AND strictly improves the sum of the two
-- cells' same-color neighbor counts. Monotone, so bounded passes suffice.
local function repair_clusters(grid, cell_list)
    local REPAIR_PASSES = 4
    local offsets = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
    }
    for _ = 1, REPAIR_PASSES do
        local changed = false
        for i = 1, #cell_list do
            local c = cell_list[i]
            if c.jewel ~= nil then
                local c_same = neighbor_color_count(grid, c.x, c.y, c.jewel)
                if c_same <= 2 then
                    for oi = 1, 8 do
                        local nx = c.x + offsets[oi][1]
                        local ny = c.y + offsets[oi][2]
                        local n = grid[cluster.key(nx, ny)]
                        if n ~= nil and n.jewel ~= nil
                            and not cluster.color_eq(n.jewel, c.jewel)
                            -- Derangement check: after the swap, c holds
                            -- n.jewel and n holds c.jewel.
                            and not cluster.color_eq(n.jewel, c.target)
                            and not cluster.color_eq(c.jewel, n.target)
                        then
                            local n_same = neighbor_color_count(grid, nx, ny, n.jewel)
                            -- Simulate the swap by measuring what the new
                            -- neighbor counts WOULD be for each jewel at
                            -- the other's location. c and n are each other's
                            -- 8-neighbors, so each currently contributes 1
                            -- to the other's post-swap count — that's stale
                            -- self-contribution, not real clustering, strip
                            -- it from both sides.
                            local c_new = neighbor_color_count(grid, c.x, c.y, n.jewel) - 1
                            local n_new = neighbor_color_count(grid, nx, ny, c.jewel) - 1
                            if (c_new + n_new) > (c_same + n_same) then
                                c.jewel, n.jewel = n.jewel, c.jewel
                                changed = true
                                break
                            end
                        end
                    end
                end
            end
        end
        if not changed then break end
    end
end

-- Count how many non-locked mismatched jewels end up in tiny (size ≤ 2)
-- clusters using the same lock-aware BFS the player sees. Returns
-- (small_jewels, total_mismatched). Lower ratio = nicer puzzle: the
-- player gets chunky lifts, not a confetti of 1-2 point dribbles.
local function count_small_cluster_jewels(grid, cell_list)
    local visited = {}
    local small = 0
    local total = 0
    for i = 1, #cell_list do
        local c = cell_list[i]
        if c.jewel ~= nil and not cluster.color_eq(c.jewel, c.target) then
            total = total + 1
            local k = cluster.key(c.x, c.y)
            if not visited[k] then
                local picks = cluster.flood_jewel_cluster(grid, c.x, c.y)
                if #picks == 0 then
                    -- Shouldn't happen for a mismatched non-locked cell, but
                    -- be defensive: treat as singleton.
                    visited[k] = true
                    small = small + 1
                else
                    for j = 1, #picks do
                        visited[cluster.key(picks[j].x, picks[j].y)] = true
                    end
                    if #picks <= 2 then
                        small = small + #picks
                    end
                end
            end
        end
    end
    return small, total
end

-- Shuffle jewels across all cells via Fisher-Yates + a local-swap cluster
-- repair pass. Targets are feasibility-aware:
--   * fixed points = `min_fixed_points` (usually 0 — strict derangement).
--     The floor is nonzero only when one target color occupies more than
--     half the cells, in which case pigeonhole forces overlap.
--   * jewels in size ≤ 2 clusters = `unavoidable_small`. The floor counts
--     jewels whose color's total pool in the level is ≤ 2, so they
--     physically cannot form a ≥ 3 cluster.
-- Attempts are ranked lexicographically by (fixed_points, small_jewels);
-- the first attempt that hits both floors and passes the greedy solver
-- wins outright.
function M.scramble(grid, cell_list, shelf, shelf_cap, _unused_steps)
    shelf_cap = shelf_cap or M.SHELF_CAPACITY
    -- `shelf` is expected to be empty on entry; clear defensively.
    for i = #shelf, 1, -1 do shelf[i] = nil end

    local max_tries = 120
    local solve_budget = 2000

    -- Feasibility floors derived from the level's color histogram.
    local _, color_counts = count_color_multiset(cell_list)
    local n_cells = #cell_list
    local max_color = 0
    local unavoidable_small = 0
    for _, ct in pairs(color_counts) do
        if ct > max_color then max_color = ct end
        if ct <= 2 then unavoidable_small = unavoidable_small + ct end
    end
    local min_fixed_points = math.max(0, 2 * max_color - n_cells)

    local best_snap = nil
    local best_fixed = math.huge
    local best_small = math.huge

    for _ = 1, max_tries do
        -- Collect current jewels, shuffle, reassign.
        local jewels = {}
        for i = 1, #cell_list do
            jewels[i] = cell_list[i].jewel and copy_color(cell_list[i].jewel)
                or copy_color(cell_list[i].target)
        end
        fisher_yates(jewels)
        for i = 1, #cell_list do
            cell_list[i].jewel = jewels[i]
        end

        -- Grow chunky clusters via derangement-preserving local swaps.
        repair_clusters(grid, cell_list)

        -- Score: fewer fixed points first, then fewer tiny-cluster jewels.
        local fixed_points = 0
        for i = 1, #cell_list do
            if cluster.color_eq(cell_list[i].jewel, cell_list[i].target) then
                fixed_points = fixed_points + 1
            end
        end

        -- Sanity-check solvability on a snapshot (greedy_solve mutates).
        local snap = snapshot_jewels(cell_list)
        local ok = greedy_solve(grid, cell_list, shelf_cap, solve_budget)
        restore_jewels(cell_list, snap)
        if ok then
            local small, _ = count_small_cluster_jewels(grid, cell_list)
            local better = fixed_points < best_fixed
                or (fixed_points == best_fixed and small < best_small)
            if better then
                best_fixed = fixed_points
                best_small = small
                best_snap = snapshot_jewels(cell_list)
            end
            if fixed_points <= min_fixed_points
                and small <= unavoidable_small
            then
                return
            end
        end
    end

    -- No attempt hit the feasibility floors, but we still have the best
    -- solvable shuffle we saw. Use that.
    if best_snap ~= nil then
        restore_jewels(cell_list, best_snap)
        return
    end

    -- If every try failed the solvability check (vanishingly rare), fall
    -- back to a constructive path: start solved, walk every cell and swap
    -- its jewel with the next differently-targeted cell we haven't paired
    -- yet. This yields a full derangement for any level whose histogram
    -- admits one. Then one repair pass grows the pairs into clusters.
    for i = 1, #cell_list do
        cell_list[i].jewel = copy_color(cell_list[i].target)
    end
    local swapped = {}
    for i = 1, #cell_list do
        if not swapped[i] then
            for j = i + 1, #cell_list do
                if not swapped[j]
                    and not cluster.color_eq(cell_list[i].target, cell_list[j].target)
                then
                    cell_list[i].jewel, cell_list[j].jewel =
                        cell_list[j].jewel, cell_list[i].jewel
                    swapped[i] = true
                    swapped[j] = true
                    break
                end
            end
        end
    end
    repair_clusters(grid, cell_list)
end

return M
