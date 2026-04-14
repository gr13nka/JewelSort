-- level.lua
-- Runtime level state: grid, shelf, hover cluster, simple tap state machine.

local cluster = require("src.cluster")
local shuffle = require("src.shuffle")

local M = {}
M.__index = M

local function copy_color(c)
    return { c[1], c[2], c[3] }
end

-- Build a Level instance from a level descriptor (from level_loader).
function M.new(desc)
    local self = setmetatable({}, M)
    self.desc = desc
    self.width = desc.width
    self.height = desc.height

    -- Grid is keyed by "x,y"; only cells where the source PNG had alpha > 0.
    self.grid = {}
    self.cell_list = {}
    for i = 1, #desc.cells do
        local src = desc.cells[i]
        local cell = {
            x = src.gx,
            y = src.gy,
            target = copy_color(src.target),
            jewel = copy_color(src.target), -- start solved, then shuffle
        }
        self.grid[cluster.key(cell.x, cell.y)] = cell
        self.cell_list[#self.cell_list + 1] = cell
    end

    shuffle.shuffle_jewels(self.cell_list)

    self.shelf = {} -- array of {color = {r,g,b}}
    self.state = { kind = "idle" } -- or {kind="hovering", source, color, jewels}
    self.won = false
    return self
end

-- Win = every cell holds a jewel matching its target color. Shelf may be nonempty.
function M:check_win()
    for i = 1, #self.cell_list do
        local c = self.cell_list[i]
        if c.jewel == nil then return false end
        if not cluster.color_eq(c.jewel, c.target) then return false end
    end
    return true
end

-- Tap a grid cell at grid (x,y). Returns nothing; mutates state.
function M:tap_cell(gx, gy)
    if self.won then return end
    local k = cluster.key(gx, gy)
    local cell = self.grid[k]
    if cell == nil then
        -- Tapped outside grid bounds: cancel any hover.
        self:cancel_hover()
        return
    end

    if self.state.kind == "idle" then
        -- Must have a jewel to pick up.
        if cell.jewel == nil then return end
        local picks = cluster.flood_jewel_cluster(self.grid, gx, gy)
        if #picks == 0 then return end
        local color = copy_color(cell.jewel)
        local jewels = {}
        for i = 1, #picks do
            local p = picks[i]
            jewels[#jewels + 1] = { color = copy_color(p.cell.jewel) }
            p.cell.jewel = nil
        end
        self.state = {
            kind = "hovering",
            source = "grid",
            color = color,
            jewels = jewels,
            origin_cells = picks,
        }
        return
    end

    if self.state.kind == "hovering" then
        if cell.jewel == nil and cluster.color_eq(cell.target, self.state.color) then
            -- Drop into this hole and flood to adjacent empty matching holes.
            local holes = cluster.flood_empty_holes(self.grid, gx, gy, self.state.color)
            if #holes > 0 then
                self:place_cluster_into_holes(holes)
                return
            end
        end
        -- Anything else cancels.
        self:cancel_hover()
        return
    end
end

-- Place as many jewels from current hover cluster as possible into `holes`.
-- Excess jewels return to the source (shelf or scattered grid origins).
function M:place_cluster_into_holes(holes)
    local state = self.state
    local jewels = state.jewels
    local n = math.min(#holes, #jewels)
    for i = 1, n do
        holes[i].cell.jewel = copy_color(state.color)
    end
    -- Remove the placed jewels from the cluster.
    local remaining = {}
    for i = n + 1, #jewels do
        remaining[#remaining + 1] = jewels[i]
    end

    if #remaining == 0 then
        self.state = { kind = "idle" }
    else
        -- Remainder returns to source.
        if state.source == "shelf" then
            -- Put back on shelf.
            for i = 1, #remaining do
                self.shelf[#self.shelf + 1] = remaining[i]
            end
            self.state = { kind = "idle" }
        else
            -- Grid source: put remainder back into the origin_cells that are
            -- still empty (pick the leftover original positions).
            local leftover_cells = {}
            for i = 1, #state.origin_cells do
                local oc = state.origin_cells[i].cell
                if oc.jewel == nil then
                    leftover_cells[#leftover_cells + 1] = oc
                end
            end
            -- Assign remaining jewels back into leftover cells, if any.
            local placed = 0
            for i = 1, math.min(#leftover_cells, #remaining) do
                leftover_cells[i].jewel = copy_color(remaining[i].color)
                placed = placed + 1
            end
            -- Any remaining beyond that go to shelf.
            for i = placed + 1, #remaining do
                self.shelf[#self.shelf + 1] = remaining[i]
            end
            self.state = { kind = "idle" }
        end
    end

    if self:check_win() then
        self.won = true
    end
end

-- Tap the shelf strip (empty space). Deposits grid-cluster onto shelf.
function M:tap_shelf_empty()
    if self.won then return end
    if self.state.kind == "hovering" and self.state.source == "grid" then
        -- Move all hovered jewels onto shelf.
        for i = 1, #self.state.jewels do
            self.shelf[#self.shelf + 1] = self.state.jewels[i]
        end
        self.state = { kind = "idle" }
        return
    end
    if self.state.kind == "hovering" then
        self:cancel_hover()
    end
end

-- Tap a specific shelf jewel (by index). If idle, lift all same-color on shelf.
function M:tap_shelf_jewel(index)
    if self.won then return end
    if index == nil or self.shelf[index] == nil then
        self:tap_shelf_empty()
        return
    end
    if self.state.kind == "idle" then
        local target_color = copy_color(self.shelf[index].color)
        local picks = cluster.shelf_same_color(self.shelf, target_color)
        if #picks == 0 then return end
        local jewels = {}
        -- Iterate from highest index down so removals are safe.
        table.sort(picks, function(a, b) return a > b end)
        for i = 1, #picks do
            local idx = picks[i]
            jewels[#jewels + 1] = { color = copy_color(self.shelf[idx].color) }
            table.remove(self.shelf, idx)
        end
        self.state = {
            kind = "hovering",
            source = "shelf",
            color = target_color,
            jewels = jewels,
        }
        return
    end
    -- Hovering: treat shelf-jewel tap as "deposit to shelf" (same as empty shelf).
    self:tap_shelf_empty()
end

function M:cancel_hover()
    if self.state.kind ~= "hovering" then return end
    local state = self.state
    if state.source == "grid" then
        -- Return jewels to their original origin cells (in order; if some got
        -- partly placed, fill only the still-empty ones first, then shelf).
        local empty_cells = {}
        for i = 1, #state.origin_cells do
            local oc = state.origin_cells[i].cell
            if oc.jewel == nil then
                empty_cells[#empty_cells + 1] = oc
            end
        end
        local n = math.min(#empty_cells, #state.jewels)
        for i = 1, n do
            empty_cells[i].jewel = copy_color(state.jewels[i].color)
        end
        for i = n + 1, #state.jewels do
            self.shelf[#self.shelf + 1] = state.jewels[i]
        end
    else
        for i = 1, #state.jewels do
            self.shelf[#self.shelf + 1] = state.jewels[i]
        end
    end
    self.state = { kind = "idle" }
end

return M
