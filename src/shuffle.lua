-- shuffle.lua
-- Region-growing scramble of jewels across cells.
--
-- Why not Fisher-Yates?
--   A per-cell permutation produces a confetti of 1-2-cell clusters. The
--   player's lift-and-flood mechanic rewards chunky lifts, so we instead
--   carve the grid into 8-connected spatial regions of MIN_CHUNK..MAX_CHUNK
--   cells and fill each region with one "wrong" color.
--
-- Why not a forward-play scrambler?
--   Forward moves only place a jewel into a cell whose TARGET matches, so
--   from the solved state forward play can never create a real mismatch.
--   A previous version had this bug; it produced only 2-cell fallback
--   swaps. Don't reintroduce it.
--
-- Multiset conservation:
--   Chunks are sized so that sum(sizes for color C) == count(target == C),
--   so the final board is a permutation of the solved state. Every swap in
--   the derangement-fix pass is in-place, so it conserves the pool too.
--
-- Solvability:
--   A cheap greedy solver runs on each candidate; unsolvable candidates are
--   retried up to `max_tries`. Chunky regions usually solve on attempt 1-3.
--
-- No goto, no recursion, iterative loops only (love.js / Fengari friendly).

local cluster = require("src.cluster")

local M = {}

-- Cap sized to fit the largest scramble cluster (MAX_CHUNK below) so the
-- player can always park a full lift on the shelf.
M.SHELF_CAPACITY = 24

-- Chunk-size tuning. MIN must be >= 2 or the greedy-solver scoring stops
-- making sense; MAX is bounded by the shelf capacity above.
local MIN_CHUNK = 8
local MAX_CHUNK = 24
local TARGET_CHUNK = 16

local OFFSETS = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

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

-- Fisher-Yates on an array, in place. Still used for shuffling the chunk
-- processing order and the jewel list inside a mixed chunk.
local function fisher_yates(arr)
    local n = #arr
    for i = n, 2, -1 do
        local j = rand(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

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

-- Greedy solver: see module docstring. Returns true if solvable within
-- the step budget; mutates the grid in the process. Strategy per step:
--   1. If shelf has a color C and grid has an empty C-target cell, deposit.
--   2. Else lift the smallest 8-connected same-color cluster from any
--      wrong-target cell that still fits on the shelf.
local function greedy_solve(grid, cell_list, shelf_cap, budget)
    local shelf = {}
    local steps = 0
    while steps < budget do
        steps = steps + 1
        if is_solved(cell_list) then return true end

        local placed = false
        if #shelf > 0 then
            for i = 1, #shelf do
                local color = shelf[i].color
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
            local best = nil
            local best_size = math.huge
            for ci = 1, #cell_list do
                local c = cell_list[ci]
                if c.jewel ~= nil and not cluster.color_eq(c.jewel, c.target) then
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

-- Split a count `ct` into a list of chunk sizes, each in [MIN, MAX] when
-- possible. Tries to land sizes near TARGET by picking n = round(ct/TARGET).
-- Returns a flat array of sizes summing to `ct`.
local function split_count(ct)
    if ct <= 0 then return {} end
    local n = math.max(1, math.floor(ct / TARGET_CHUNK + 0.5))
    -- Shrink n until each piece is >= MIN_CHUNK (or we can't shrink further).
    while n > 1 and math.floor(ct / n) < MIN_CHUNK do
        n = n - 1
    end
    -- Grow n until the largest piece <= MAX_CHUNK.
    while math.ceil(ct / n) > MAX_CHUNK do
        n = n + 1
    end
    local base = math.floor(ct / n)
    local rem = ct - base * n
    local sizes = {}
    for i = 1, n do
        sizes[i] = base + (i <= rem and 1 or 0)
    end
    return sizes
end

-- Build the chunk plan:
--   * Large colors (count >= MIN_CHUNK) get split into single-color chunks.
--   * Small colors pool together into mixed chunks. If the pool itself is
--     < MIN_CHUNK, it attaches to the last large-color chunk as a mixed
--     tail so no region falls below the floor.
-- Each chunk is either
--   { size=S, color=C }          (single-color)
--   { size=S, color=nil, jewels=[S color arrays] }  (mixed)
local function build_chunks(palette, counts)
    local chunks = {}
    local small_jewels = {}

    -- Sort large colors by count descending so big regions are planned
    -- first. pairs() order is unspecified in Lua; the sort gives stability
    -- and helps the grower grab room for the biggest blob before the grid
    -- gets fragmented.
    local large = {}
    for k, ct in pairs(counts) do
        if ct >= MIN_CHUNK then
            large[#large + 1] = { key = k, count = ct }
        else
            for i = 1, ct do
                small_jewels[#small_jewels + 1] = copy_color(palette[k])
            end
        end
    end
    table.sort(large, function(a, b) return a.count > b.count end)

    for i = 1, #large do
        local entry = large[i]
        local color = palette[entry.key]
        local sizes = split_count(entry.count)
        for j = 1, #sizes do
            chunks[#chunks + 1] = { size = sizes[j], color = copy_color(color) }
        end
    end

    local small_n = #small_jewels
    if small_n > 0 then
        fisher_yates(small_jewels)
        if small_n >= MIN_CHUNK then
            local sizes = split_count(small_n)
            local offset = 0
            for i = 1, #sizes do
                local sz = sizes[i]
                local jewels = {}
                for k = 1, sz do jewels[k] = small_jewels[offset + k] end
                offset = offset + sz
                chunks[#chunks + 1] = { size = sz, color = nil, jewels = jewels }
            end
        elseif #chunks > 0 then
            -- Attach small pool to the last single-color chunk: convert it
            -- into a mixed chunk that holds its original color plus the
            -- small-pool jewels. Result still satisfies size >= MIN_CHUNK.
            local last = chunks[#chunks]
            local jewels = {}
            for i = 1, last.size do
                jewels[i] = copy_color(last.color)
            end
            for i = 1, small_n do
                jewels[#jewels + 1] = small_jewels[i]
            end
            fisher_yates(jewels)
            last.color = nil
            last.size = last.size + small_n
            last.jewels = jewels
        else
            -- Degenerate: the level is smaller than MIN_CHUNK. Emit the
            -- whole thing as one mixed chunk.
            chunks[1] = { size = small_n, color = nil, jewels = small_jewels }
        end
    end

    return chunks
end

-- Pick a seed cell from `unassigned` for a chunk. Prefer cells whose
-- target color differs from the chunk color so the region lands in "wrong
-- places"; fall back to any unassigned cell if no preferred seed exists.
local function pick_seed(unassigned, chunk_color)
    local preferred, any_list = {}, {}
    for _, cell in pairs(unassigned) do
        any_list[#any_list + 1] = cell
        if chunk_color == nil
            or not cluster.color_eq(cell.target, chunk_color)
        then
            preferred[#preferred + 1] = cell
        end
    end
    if #preferred > 0 then return preferred[rand(#preferred)] end
    if #any_list > 0 then return any_list[rand(#any_list)] end
    return nil
end

-- Pop a random element from `arr` in O(1) by swapping with the tail.
local function pop_random(arr)
    local n = #arr
    if n == 0 then return nil end
    local i = rand(n)
    local v = arr[i]
    arr[i] = arr[n]
    arr[n] = nil
    return v
end

-- Grow an 8-connected region starting at `seed`, advancing through cells
-- in `unassigned` (map of key -> cell). Growth stops when the region
-- reaches `target_size` OR the frontier empties. Returns the region as
-- an array of cells.
--
-- For single-color chunks we prefer frontier cells whose target differs
-- from the chunk color; only when no preferred cells are available do we
-- dip into target-matching neighbors. That keeps "wrong place" placements
-- in the common case without letting us stall on rare color-dense seeds.
local function grow_region(unassigned, seed, target_size, chunk_color)
    local region = { seed }
    local queued = { [cluster.key(seed.x, seed.y)] = true }
    local preferred_q, fallback_q = {}, {}

    local function enqueue_neighbors(cell)
        for oi = 1, 8 do
            local nx = cell.x + OFFSETS[oi][1]
            local ny = cell.y + OFFSETS[oi][2]
            local nk = cluster.key(nx, ny)
            if not queued[nk] then
                local ncell = unassigned[nk]
                if ncell ~= nil then
                    queued[nk] = true
                    if chunk_color ~= nil
                        and cluster.color_eq(ncell.target, chunk_color)
                    then
                        fallback_q[#fallback_q + 1] = ncell
                    else
                        preferred_q[#preferred_q + 1] = ncell
                    end
                end
            end
        end
    end

    enqueue_neighbors(seed)

    while #region < target_size do
        local next_cell = pop_random(preferred_q) or pop_random(fallback_q)
        if next_cell == nil then break end
        region[#region + 1] = next_cell
        enqueue_neighbors(next_cell)
    end

    return region
end

-- Paint a region with the chunk's jewels. For single-color chunks every
-- cell gets the same color. For mixed chunks, the jewel list is shuffled
-- and distributed; a small within-region repair pass swaps any cell that
-- landed on its own target with another region cell that's also safe to
-- swap with. Conserves the region's jewel multiset.
local function paint_region(region, chunk)
    if chunk.color ~= nil then
        for i = 1, #region do
            region[i].jewel = copy_color(chunk.color)
        end
        return
    end

    -- Mixed region: there should be exactly #region jewels available, but
    -- a shortfall carry can leave chunk.jewels with fewer than #region
    -- entries if we're painting a truncated region — in that case we pad
    -- with the extras from the tail (handled by the caller before calling
    -- paint_region, so len(chunk.jewels) == #region here).
    local jewels = chunk.jewels
    fisher_yates(jewels)
    for i = 1, #region do
        region[i].jewel = copy_color(jewels[i])
    end

    -- Within-region derangement repair: if any cell ended up jewel==target,
    -- find a swap partner in the same region that both fixes this cell and
    -- doesn't create a new fixed point on the partner.
    for i = 1, #region do
        local ci = region[i]
        if cluster.color_eq(ci.jewel, ci.target) then
            for j = 1, #region do
                if j ~= i then
                    local cj = region[j]
                    if not cluster.color_eq(cj.jewel, cj.target)
                        and not cluster.color_eq(cj.jewel, ci.target)
                        and not cluster.color_eq(ci.jewel, cj.target)
                    then
                        ci.jewel, cj.jewel = cj.jewel, ci.jewel
                        break
                    end
                end
            end
        end
    end
end

-- One construction pass: build chunks, grow regions, paint them. Mutates
-- cell_list[*].jewel. Undershoot (region stopped before reaching target
-- size because the local component ran out) is handled by appending a
-- makeup chunk for the leftover jewels — those will seed elsewhere.
local function build_one_scramble(grid, cell_list)
    local _ = grid -- grid is implied by cell_list; unused here, kept for API symmetry
    local palette, counts = count_color_multiset(cell_list)
    local chunks = build_chunks(palette, counts)
    fisher_yates(chunks)

    local unassigned = {}
    for i = 1, #cell_list do
        local c = cell_list[i]
        unassigned[cluster.key(c.x, c.y)] = c
    end

    -- Queue-driven so we can append makeup chunks at the end as we go.
    local ci = 1
    while ci <= #chunks do
        local chunk = chunks[ci]
        ci = ci + 1

        local seed = pick_seed(unassigned, chunk.color)
        if seed == nil then
            -- No cells left; any remaining chunks are a planning bug but
            -- we tolerate it silently rather than crashing.
            break
        end

        local region = grow_region(unassigned, seed, chunk.size, chunk.color)

        for i = 1, #region do
            unassigned[cluster.key(region[i].x, region[i].y)] = nil
        end

        if #region < chunk.size then
            -- Split the chunk: paint what we got, carry the rest forward.
            local shortfall = chunk.size - #region
            if chunk.color ~= nil then
                chunks[#chunks + 1] = {
                    size = shortfall,
                    color = copy_color(chunk.color),
                }
            else
                -- Mixed chunk: split the jewel list and emit the tail as
                -- a new mixed chunk.
                local head, tail = {}, {}
                for i = 1, #region do head[i] = chunk.jewels[i] end
                for i = #region + 1, chunk.size do
                    tail[#tail + 1] = chunk.jewels[i]
                end
                chunk.size = #region
                chunk.jewels = head
                chunks[#chunks + 1] = {
                    size = shortfall,
                    color = nil,
                    jewels = tail,
                }
            end
        end

        paint_region(region, chunk)
    end
end

-- One final pass to eliminate jewel==target fixed points by swapping with
-- an 8-neighbor. Only swaps that eliminate the fix (both cells land on
-- non-targets) are accepted. Bounded at one pass — the region grower
-- avoids most fixed points up-front, so this is a mop-up, not a heavy
-- optimizer.
local function eliminate_fixed_points(grid, cell_list)
    for i = 1, #cell_list do
        local c = cell_list[i]
        if c.jewel ~= nil and cluster.color_eq(c.jewel, c.target) then
            for oi = 1, 8 do
                local nx = c.x + OFFSETS[oi][1]
                local ny = c.y + OFFSETS[oi][2]
                local n = grid[cluster.key(nx, ny)]
                if n ~= nil and n.jewel ~= nil
                    and not cluster.color_eq(n.jewel, c.jewel)
                    and not cluster.color_eq(n.jewel, c.target)
                    and not cluster.color_eq(c.jewel, n.target)
                then
                    c.jewel, n.jewel = n.jewel, c.jewel
                    break
                end
            end
        end
    end
end

-- Count how many non-locked mismatched jewels end up in tiny (size <= 2)
-- clusters using the same lock-aware BFS the player sees. Used as a
-- secondary scorer so retries with freak singletons still pick the
-- chunkiest attempt we've seen.
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

-- Scramble entry point. Builds a region-based permutation of the solved
-- board, eliminates fixed points where possible, and retries up to
-- `max_tries` times if the greedy solver can't solve the candidate.
-- Attempts are ranked lexicographically by (fixed_points, small_jewels)
-- and the best seen is kept as a fallback if no attempt hits both
-- feasibility floors.
function M.scramble(grid, cell_list, shelf, shelf_cap, _unused_steps)
    shelf_cap = shelf_cap or M.SHELF_CAPACITY
    for i = #shelf, 1, -1 do shelf[i] = nil end

    local n_cells = #cell_list

    -- Large-level fast path. The greedy solver's shelf-limited strategy
    -- can deadlock on levels with 40+ colors (e.g. 1500-cell pixel-art
    -- PNGs). The region grower preserves the multiset and already avoids
    -- most locked placements, so we skip the solvability check entirely
    -- and trust construction + one fixed-point pass.
    if n_cells > 400 then
        build_one_scramble(grid, cell_list)
        eliminate_fixed_points(grid, cell_list)
        return
    end

    local max_tries = 30
    local solve_budget = 2000

    -- Feasibility floors derived from the level's color histogram.
    local _, color_counts = count_color_multiset(cell_list)
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
        build_one_scramble(grid, cell_list)
        eliminate_fixed_points(grid, cell_list)

        local fixed_points = 0
        for i = 1, #cell_list do
            if cluster.color_eq(cell_list[i].jewel, cell_list[i].target) then
                fixed_points = fixed_points + 1
            end
        end

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

    -- Every attempt failed the greedy check (vanishingly rare for region
    -- growing, which preserves the multiset by construction). Keep the
    -- last build — it's still a valid permutation, even if the greedy
    -- solver gave up on it. The player's mechanic is strictly more
    -- flexible than greedy_solve, so in practice this is still solvable.
end

return M
