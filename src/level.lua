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
-- Per-jewel launch delay in a deposit fly. Jewels are sorted by distance
-- from the tap (nearest first) and each one leaves STAGGER s after the
-- previous, so the cascade visually emanates from the tap point.
M.PLACE_STAGGER_STEP = 0.04

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
		local retire_at = pa.total_duration or (M.FLY_DURATION + M.LANDING_PULSE)
		if pa.t >= retire_at then
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

-- Tap a grid cell at grid (x,y). sx,sy are the tap pixel coords (optional);
-- they're used by the deposit path to order per-jewel flight by distance
-- from the tap so the cascade emanates from the touch point.
function M:tap_cell(gx, gy, sx, sy)
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
				self:place_cluster_into_holes(holes, sx, sy)
				return
			end
		end
		-- Auto-swap QoL: tapping a differently-colored grid jewel returns
		-- the held cluster to source and immediately lifts the new one.
		-- The recursive tap_cell re-enters in the "idle" branch; locked
		-- jewels still resolve to a no-op via flood_jewel_cluster.
		if cell.jewel ~= nil and not cluster.color_eq(cell.jewel, self.state.color) then
			self:cancel_hover()
			self:tap_cell(gx, gy, sx, sy)
			return
		end
		-- Anything else cancels.
		self:cancel_hover()
		return
	end
end

-- Place as many jewels from current hover cluster as possible into `holes`.
-- Excess jewels return to the source (shelf or scattered grid origins).
-- tap_sx, tap_sy (pixels, optional) anchor the cascade: origins and holes
-- are sorted by distance to the tap so the jewel nearest the tap flies
-- first, and the rest follow, staggered by PLACE_STAGGER_STEP.
function M:place_cluster_into_holes(holes, tap_sx, tap_sy)
	local state = self.state
	local jewels = state.jewels
	local n = math.min(#holes, #jewels)

	local render = require("src.render")
	local layout = self.layout

	-- Anchor: tap pixel, else fall back to the tapped hole's pixel center.
	-- Fallback matters for non-pointer entry points (tests, debug paths).
	local ax, ay
	if tap_sx ~= nil and tap_sy ~= nil then
		ax, ay = tap_sx, tap_sy
	elseif layout ~= nil then
		ax, ay = render.grid_cell_pixel(layout, holes[1].cell.x, holes[1].cell.y)
	end

	local function origin_pixel(i)
		if layout == nil then return nil, nil end
		if state.source == "grid" then
			local oc = state.origin_cells[i].cell
			return render.grid_cell_pixel(layout, oc.x, oc.y)
		end
		return render.shelf_slot_pixel(layout, i)
	end
	local function hole_pixel(i)
		if layout == nil then return nil, nil end
		return render.grid_cell_pixel(layout, holes[i].cell.x, holes[i].cell.y)
	end
	local function dist2(px, py)
		if ax == nil or px == nil then return 0 end
		local dx, dy = px - ax, py - ay
		return dx * dx + dy * dy
	end

	-- Sort origin + hole indices by proximity to the tap.
	local origin_order = {}
	local origin_d = {}
	for i = 1, #jewels do
		origin_order[i] = i
		local px, py = origin_pixel(i)
		origin_d[i] = dist2(px, py)
	end
	table.sort(origin_order, function(a, b) return origin_d[a] < origin_d[b] end)

	local hole_order = {}
	local hole_d = {}
	for i = 1, #holes do
		hole_order[i] = i
		local px, py = hole_pixel(i)
		hole_d[i] = dist2(px, py)
	end
	table.sort(hole_order, function(a, b) return hole_d[a] < hole_d[b] end)

	-- Place jewels into holes in sorted order (all same color — order only
	-- changes which indices are "used" for the fly list).
	for i = 1, n do
		holes[hole_order[i]].cell.jewel = copy_color(state.color)
	end

	-- Build fly list before mutating the hover cluster. Nearest-to-tap
	-- origin pairs with nearest-to-tap hole; stagger grows with rank so
	-- the cascade radiates outward from the tap.
	local fly = {}
	local fly_cells_set = {}
	local max_t0 = 0
	for i = 1, n do
		local oi = origin_order[i]
		local hi = hole_order[i]
		local from
		if state.source == "grid" then
			local oc = state.origin_cells[oi].cell
			from = { source = "grid", gx = oc.x, gy = oc.y }
		else
			from = { source = "shelf", shelf_index = oi }
		end
		local t0 = (i - 1) * M.PLACE_STAGGER_STEP
		if t0 > max_t0 then max_t0 = t0 end
		local hc = holes[hi].cell
		fly[#fly + 1] = {
			color = copy_color(state.color),
			from = from,
			to = { gx = hc.x, gy = hc.y },
			t0 = t0,
		}
		fly_cells_set[hc.x .. "," .. hc.y] = true
	end

	-- Reduce the cluster: drop the jewels that actually flew (by origin
	-- index), keeping the remainder hovering so the player can keep
	-- depositing into more matching holes.
	local placed = {}
	for i = 1, n do placed[origin_order[i]] = true end
	local rem_j, rem_o = {}, {}
	for i = 1, #jewels do
		if not placed[i] then
			rem_j[#rem_j + 1] = jewels[i]
			if state.source == "grid" then
				rem_o[#rem_o + 1] = state.origin_cells[i]
			end
		end
	end
	if #rem_j == 0 then
		self.state = { kind = "idle" }
	else
		state.jewels = rem_j
		if state.source == "grid" then
			state.origin_cells = rem_o
		end
	end

	self.place_anim = {
		t = 0,
		fly = fly,
		fly_cells_set = fly_cells_set,
		total_duration = max_t0 + M.FLY_DURATION + M.LANDING_PULSE,
		-- Checked now because placement already mutated the grid — if the
		-- puzzle is complete at this instant, fly hands off to cascade.
		win_after = self:check_win(),
	}
end

-- Tap the shelf strip (empty space). Deposits grid-cluster onto shelf.
-- sx, sy are the tap pixel coords (optional) — origins nearest the tap
-- hop onto the shelf first so the cascade radiates from the touch point.
function M:tap_shelf_empty(sx, sy)
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

		local render = require("src.render")
		local layout = self.layout

		-- Anchor: tap pixel, else the first empty shelf slot as a sensible
		-- fallback (players that reach this path without a pointer event).
		local ax, ay
		if sx ~= nil and sy ~= nil then
			ax, ay = sx, sy
		elseif layout ~= nil then
			ax, ay = render.shelf_slot_pixel(layout, #self.shelf + 1)
		end

		local function origin_pixel(i)
			if layout == nil then return nil, nil end
			local oc = self.state.origin_cells[i].cell
			return render.grid_cell_pixel(layout, oc.x, oc.y)
		end
		local function dist2(px, py)
			if ax == nil or px == nil then return 0 end
			local dx, dy = px - ax, py - ay
			return dx * dx + dy * dy
		end

		local order = {}
		local d = {}
		for i = 1, #self.state.jewels do
			order[i] = i
			local px, py = origin_pixel(i)
			d[i] = dist2(px, py)
		end
		table.sort(order, function(a, b) return d[a] < d[b] end)

		local fly = {}
		local base = #self.shelf
		local pending = {}
		local max_t0 = 0
		for i = 1, fit do
			local oi = order[i]
			local oc = self.state.origin_cells[oi].cell
			local t0 = (i - 1) * M.PLACE_STAGGER_STEP
			if t0 > max_t0 then max_t0 = t0 end
			fly[#fly + 1] = {
				color = copy_color(self.state.color),
				from = { source = "grid", gx = oc.x, gy = oc.y },
				to = { source = "shelf", shelf_index = base + i },
				t0 = t0,
			}
			pending[i] = self.state.jewels[oi]
		end
		self.place_anim = {
			t = 0,
			fly = fly,
			fly_cells_set = {},
			pending_shelf = pending,
			total_duration = max_t0 + M.FLY_DURATION + M.LANDING_PULSE,
		}
		if fit < #self.state.jewels then
			local placed = {}
			for i = 1, fit do placed[order[i]] = true end
			local rem_j, rem_o = {}, {}
			for i = 1, #self.state.jewels do
				if not placed[i] then
					rem_j[#rem_j + 1] = self.state.jewels[i]
					rem_o[#rem_o + 1] = self.state.origin_cells[i]
				end
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
-- sx, sy are the tap pixel coords (optional) — forwarded to tap_shelf_empty
-- for the auto-swap path that falls back to parking the current cluster.
function M:tap_shelf_jewel(index, sx, sy)
	if self.won or self.place_anim or self.win_anim then
		return
	end
	if index == nil or self.shelf[index] == nil then
		self:tap_shelf_empty(sx, sy)
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
		self:tap_shelf_jewel(index, sx, sy)
		return
	end
	-- Same color (or index past shelf length): keep original "deposit to shelf" behavior.
	self:tap_shelf_empty(sx, sy)
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
