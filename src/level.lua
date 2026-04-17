-- level.lua
-- Runtime level state: grid, shelf, hover cluster, simple tap state machine.

local cluster = require("src.cluster")
local shuffle = require("src.shuffle")

local M = {}
M.__index = M

-- Animation timing. Read by render.lua through the module table.
M.FLY_DURATION = 0.22 -- hover position -> target cell
M.FLY_ARC_HEIGHT = 0.85 -- in units of cell size; parabolic apex above midpoint
M.LANDING_PULSE = 0.16 -- after fly, a brief squash-stomp at landing
M.STOMP_PEAK = 1.32
M.STOMP_DURATION = 0.26
M.CASCADE_STAGGER = 0.05 -- seconds per unit of radial distance from center
M.OVERLAY_DELAY = 0.18 -- pause between cascade finishing and overlay
M.LIFT_DURATION = 0.12 -- hover cluster ease-up from the cell on pick-up

-- Radial distances from grid center for each cell, used to stagger the
-- cascade stomp on win. Returned as { [key] = dist, ... } and the max dist.
local function compute_cell_delays(level)
	local cx = (level.width - 1) / 2
	local cy = (level.height - 1) / 2
	local max_d = 0
	local delays = {}
	for i = 1, #level.cell_list do
		local c = level.cell_list[i]
		local dx = c.x - cx
		local dy = c.y - cy
		local d = math.sqrt(dx * dx + dy * dy)
		if d > max_d then
			max_d = d
		end
		delays[c.x .. "," .. c.y] = d
	end
	return delays, max_d
end

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
			jewel = copy_color(src.target), -- start solved, then scramble
		}
		self.grid[cluster.key(cell.x, cell.y)] = cell
		self.cell_list[#self.cell_list + 1] = cell
	end

	-- Canonical shelf capacity lives in shuffle.lua.
	self.shelf_capacity = shuffle.SHELF_CAPACITY
	self.shelf = {} -- array of {color = {r,g,b}}

	-- Forward-play scramble from the solved state. By construction the
	-- resulting puzzle is solvable (just replay the scramble in reverse).
	shuffle.scramble(self.grid, self.cell_list, self.shelf, self.shelf_capacity, 40)

	self.state = { kind = "idle" } -- or {kind="hovering", source, color, jewels}
	self.won = false
	self.place_anim = nil -- fly animation per placement; see place_cluster_into_holes
	self.win_anim = nil -- cascade + overlay delay; started by place_anim handoff
	self.flash = nil -- { text = "...", t = seconds_remaining }
	return self
end

-- Per-frame update: tick the flash timer (for transient HUD messages like
-- "Shelf full!"). Safe to call even when there is no flash.
function M:update(dt)
	if self.flash ~= nil then
		self.flash.t = self.flash.t - dt
		if self.flash.t <= 0 then
			self.flash = nil
		end
	end
	if self.state.kind == "hovering" then
		self.state.lift_t = (self.state.lift_t or 0) + dt
	end
	if self.place_anim ~= nil then
		local pa = self.place_anim
		pa.t = pa.t + dt
		if pa.t >= (M.FLY_DURATION + M.LANDING_PULSE) then
			if pa.pending_shelf ~= nil then
				for i = 1, #pa.pending_shelf do
					self.shelf[#self.shelf + 1] = pa.pending_shelf[i]
				end
			end
			if pa.win_after then
				-- Promote to cascade phase. Fly suppression lingers until
				-- cascade pulses over these cells (they're also in the grid
				-- now, so cascade renders them normally anyway).
				local delays, max_d = compute_cell_delays(self)
				self.win_anim = {
					t = 0,
					cell_delays = delays,
					cascade_total = max_d * M.CASCADE_STAGGER + M.STOMP_DURATION + M.OVERLAY_DELAY,
				}
			end
			self.place_anim = nil
		end
	end
	if self.win_anim ~= nil then
		local wa = self.win_anim
		wa.t = wa.t + dt
		if wa.t >= wa.cascade_total then
			self.won = true
			self.win_anim = nil
		end
	end
end

-- Win = every cell holds a jewel matching its target color. Shelf may be nonempty.
function M:check_win()
	for i = 1, #self.cell_list do
		local c = self.cell_list[i]
		if c.jewel == nil then
			return false
		end
		if not cluster.color_eq(c.jewel, c.target) then
			return false
		end
	end
	return true
end

-- Returns (solved, total) where solved is cells whose jewel matches target.
function M:progress()
	local total = #self.cell_list
	local solved = 0
	for i = 1, total do
		local c = self.cell_list[i]
		if c.jewel ~= nil and cluster.color_eq(c.jewel, c.target) then
			solved = solved + 1
		end
	end
	return solved, total
end

-- Tap a grid cell at grid (x,y). Returns nothing; mutates state.
function M:tap_cell(gx, gy)
	if self.won or self.place_anim or self.win_anim then
		return
	end
	local k = cluster.key(gx, gy)
	local cell = self.grid[k]
	if cell == nil then
		-- Tapped outside grid bounds: cancel any hover.
		self:cancel_hover()
		return
	end

	if self.state.kind == "idle" then
		-- Must have a jewel to pick up.
		if cell.jewel == nil then
			return
		end
		local picks = cluster.flood_jewel_cluster(self.grid, gx, gy)
		if #picks == 0 then
			return
		end
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
		-- Auto-swap QoL: tapping a differently-colored grid jewel returns
		-- the held cluster to source and immediately lifts the new one.
		-- The recursive tap_cell re-enters in the "idle" branch; locked
		-- jewels still resolve to a no-op via flood_jewel_cluster.
		if cell.jewel ~= nil and not cluster.color_eq(cell.jewel, self.state.color) then
			self:cancel_hover()
			self:tap_cell(gx, gy)
			return
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
		-- Keep hovering with the leftover jewels so the player can keep
		-- tapping matching holes without re-selecting the cluster. Source,
		-- color, and origin_cells stay pinned — any non-matching tap still
		-- runs through cancel_hover, which returns the remainder to the
		-- still-empty origin cells (or shelf if source was shelf).
		state.jewels = remaining
	end

	-- Every placement animates. Pair each placed jewel with its source
	-- position (origin cell or shelf slot). Render resolves grid/shelf
	-- coords to pixels each frame so animation survives window resizes.
	local fly = {}
	local fly_cells_set = {}
	for i = 1, n do
		local from
		if state.source == "grid" then
			local oc = state.origin_cells[i].cell
			from = { source = "grid", gx = oc.x, gy = oc.y }
		else
			from = { source = "shelf", shelf_index = i }
		end
		fly[#fly + 1] = {
			color = copy_color(state.color),
			from = from,
			to = { gx = holes[i].cell.x, gy = holes[i].cell.y },
		}
		fly_cells_set[holes[i].cell.x .. "," .. holes[i].cell.y] = true
	end
	self.place_anim = {
		t = 0,
		fly = fly,
		fly_cells_set = fly_cells_set,
		-- Checked now because placement already mutated the grid — if the
		-- puzzle is complete at this instant, fly hands off to cascade.
		win_after = self:check_win(),
	}
end

-- Tap the shelf strip (empty space). Deposits grid-cluster onto shelf.
function M:tap_shelf_empty()
	if self.won or self.place_anim or self.win_anim then
		return
	end
	if self.state.kind == "hovering" and self.state.source == "grid" then
		-- Partial placement: park as many jewels as fit; overflow keeps
		-- hovering so the player can still place them into matching holes.
		local space = self.shelf_capacity - #self.shelf
		if space <= 0 then
			return
		end
		local fit = math.min(space, #self.state.jewels)
		local fly = {}
		local base = #self.shelf
		local pending = {}
		for i = 1, fit do
			local oc = self.state.origin_cells[i].cell
			fly[#fly + 1] = {
				color = copy_color(self.state.color),
				from = { source = "grid", gx = oc.x, gy = oc.y },
				to = { source = "shelf", shelf_index = base + i },
			}
			pending[i] = self.state.jewels[i]
		end
		self.place_anim = {
			t = 0,
			fly = fly,
			fly_cells_set = {},
			pending_shelf = pending,
		}
		if fit < #self.state.jewels then
			local rem_j, rem_o = {}, {}
			for i = fit + 1, #self.state.jewels do
				rem_j[#rem_j + 1] = self.state.jewels[i]
				rem_o[#rem_o + 1] = self.state.origin_cells[i]
			end
			self.state.jewels = rem_j
			self.state.origin_cells = rem_o
		else
			self.state = { kind = "idle" }
		end
		return
	end
	if self.state.kind == "hovering" then
		self:cancel_hover()
	end
end

-- Tap a specific shelf jewel (by index). If idle, lift all same-color on shelf.
function M:tap_shelf_jewel(index)
	if self.won or self.place_anim or self.win_anim then
		return
	end
	if index == nil or self.shelf[index] == nil then
		self:tap_shelf_empty()
		return
	end
	if self.state.kind == "idle" then
		local target_color = copy_color(self.shelf[index].color)
		local picks = cluster.shelf_same_color(self.shelf, target_color)
		if #picks == 0 then
			return
		end
		local jewels = {}
		-- Iterate from highest index down so removals are safe.
		table.sort(picks, function(a, b)
			return a > b
		end)
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
	-- Hovering path.
	-- Auto-swap QoL: tapping a differently-colored shelf jewel returns
	-- the held cluster to source and immediately lifts the shelf cluster.
	local shelf_jewel = self.shelf[index]
	if shelf_jewel ~= nil and not cluster.color_eq(shelf_jewel.color, self.state.color) then
		self:cancel_hover()
		self:tap_shelf_jewel(index)
		return
	end
	-- Same color (or index past shelf length): keep original "deposit to shelf" behavior.
	self:tap_shelf_empty()
end

function M:cancel_hover()
	if self.state.kind ~= "hovering" then
		return
	end
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
