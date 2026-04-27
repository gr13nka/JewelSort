-- menu.lua
-- Two-screen navigation layer between boot and gameplay:
--   screen = "boxes" -> list of boxes (unlocked/locked, completion ratio)
--   screen = "levels" -> tiles for the selected box's puzzles
--
-- Input is split press/release so tiles can run a press-down scale tween:
--   menu:handle_tap(sx, sy, w, h)      -- start press (pointer down)
--   menu:handle_release(sx, sy, w, h)  -- resolve release (pointer up)
-- Release commits the action only if the pointer is still over the same
-- rect it pressed. menu.play_pending is the post-release side-effect — set
-- to { box_idx, puzzle_idx } when a puzzle tile releases inside; the
-- caller (main.lua) consumes and clears it.

local progression = require("src.progression")

local M = {}
M.__index = M

-- Card display sizes (1x). Asset PNGs are 2x retina; we draw at 0.5
-- scale on the 540x960 buffer so these are the actual on-screen dims.
-- Source of truth for both layout (here) and rendering (render.lua) —
-- if you change these, change CARD_DISPLAY_SIZE in render.lua too.
M.CARD_SIZE = {
    s  = { w = 110, h = 130 },
    m  = { w = 150, h = 180 },
    l  = { w = 270, h = 168 },
    xl = { w = 280, h = 320 },
}

-- Bucket a level's cropped opaque-pixel bbox into one of the four card
-- variants. Square-ish small puzzles get S/M; wide puzzles get the
-- landscape L card; everything else falls into XL.
local function pick_card_size(w, h)
    if w == nil or h == nil or w <= 0 or h <= 0 then return "m" end
    local maxd = math.max(w, h)
    local ar = w / h
    if maxd <= 12 then return "s" end
    if ar >= 1.30 and maxd <= 56 then return "l" end
    if maxd <= 24 then return "m" end
    return "xl"
end

local PUSHPIN_COLORS = { "red", "gold", "silver", "teal" }

-- Stable hash of a string -> small integer. Used to deterministically
-- pick a pushpin color per puzzle so the same level always wears the
-- same pin, but adjacent levels rarely share one.
local function string_hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 2147483647
    end
    return h
end

-- Layout constants are recomputed each frame from window size; these are
-- just the fractions / paddings used by both menu.lua and render.lua.
M.LAYOUT = {
    -- 173 = 360 (book asset h) * 500 (usable w on 540 screen) / 1040 (book asset w);
    -- the book PNG is fit-to-width, so card height tracks asset aspect.
    box_card_height = 173,
    box_card_gap = 16,
    boxes_top_padding = 130,  -- room for big header + "Select a book" subtitle
    levels_top_padding = 90,  -- room for back button + book title
    side_margin = 20,
    -- counter_jewels.png is 200x96 at 2x retina; half-scale = 100x48.
    badge_w = 100,
    badge_h = 48,
    badge_margin_right = 20,
    badge_margin_top = 14,
    -- page_parchment.png is 1020x1660 at 2x; half-scale = 510x830.
    page_w = 510,
    page_h = 830,
    -- Inset from page edge before card placement starts. Leaves room
    -- for the parchment's painted border (~20px) plus a little air.
    page_pad_x = 28,
    page_pad_y = 36,
    level_row_gap = 18,
    level_col_gap = 14,
    -- back_button.png is 180x80 at 2x; half-scale = 90x40.
    back_w = 90,
    back_h = 40,
}

-- Press animation timings, shared by all pressable elements.
M.PRESS_DOWN_DURATION = 0.14
M.PRESS_RELEASE_DURATION = 0.26
M.PRESS_SCALE_MIN = 0.94
M.PRESS_OVERLAY_MAX = 0.22
-- Hover (pointer-over, no button) ramp. Same easing as press; gentle so
-- it doesn't fight the press-down scale when the user actually clicks.
M.HOVER_DURATION = 0.18

-- Drag threshold (pixels). Pointer movement greater than this between
-- press-down and current position cancels the press and converts the
-- gesture into a scroll on the levels page.
M.DRAG_THRESHOLD = 8
-- Wheel scroll amount per notch in 1x display pixels.
M.WHEEL_STEP = 60

function M.new(boxes, progress)
    local self = setmetatable({}, M)
    self.boxes = boxes or {}
    self.progress = progress
    self.descriptors = nil      -- set externally via :bind_descriptors
    self.screen = "boxes"
    self.selected_box = nil
    self.scroll = 0             -- pixel offset on the levels page
    self.pressed = nil
    self.play_pending = nil
    self._hover = {}
    -- Per-box visual data, lazily filled on first entry to that box's
    -- levels screen. Keyed by box index. Each entry is an array
    -- [puzzle_idx] = { size, pushpin, rotation, sway_phase, sway_speed }.
    self._level_visuals = {}
    -- Per-box layout cache. Keyed by box index. Each entry is
    -- { win_w, rects = { [puzzle_idx] = { x, y, w, h } }, content_h }.
    -- Invalidated when win_w changes.
    self._level_layout = {}
    -- Drag tracking on the levels page. Set on press-down so we can
    -- (a) detect when motion exceeds DRAG_THRESHOLD and convert the
    -- press into a scroll, and (b) clamp scroll updates against
    -- content height.
    self._drag = nil
    return self
end

-- Optional hook so the menu can read level dimensions for card-size
-- bucketing. main.lua already preloads all level descriptors at boot;
-- this just hands the table over so menu.lua can look up dims on
-- demand without re-parsing PNGs.
function M:bind_descriptors(descriptors)
    self.descriptors = descriptors or {}
    -- Drop any visuals computed before descriptors arrived (defensive;
    -- normal call order is bind_descriptors before first render).
    self._level_visuals = {}
    self._level_layout = {}
end

-- Rect helpers (no persistent layout; menus are small).

local function box_card_rect(i, win_w)
    local L = M.LAYOUT
    local x = L.side_margin
    local w = win_w - L.side_margin * 2
    local y = L.boxes_top_padding + (i - 1) * (L.box_card_height + L.box_card_gap)
    return x, y, w, L.box_card_height
end

-- Centered parchment-page rect on the levels screen.
local function page_rect(win_w, win_h)
    local L = M.LAYOUT
    local pw = math.min(L.page_w, win_w - L.side_margin * 2)
    local ph = L.page_h
    local px = math.floor((win_w - pw) / 2)
    local py = L.levels_top_padding
    if win_h ~= nil then
        local max_h = win_h - py - 12
        if ph > max_h then ph = max_h end
    end
    return px, py, pw, ph
end

local function back_button_rect()
    local L = M.LAYOUT
    return L.side_margin, L.side_margin + 4, L.back_w, L.back_h
end

local function badge_rect(win_w, _win_h)
    local L = M.LAYOUT
    local x = win_w - L.badge_w - L.badge_margin_right
    local y = L.badge_margin_top
    return x, y, L.badge_w, L.badge_h
end

function M:layout_box_card(i, win_w)
    return box_card_rect(i, win_w)
end

function M:back_button_rect()
    return back_button_rect()
end

function M:badge_rect(win_w, win_h)
    return badge_rect(win_w, win_h)
end

function M:page_rect(win_w, win_h)
    return page_rect(win_w, win_h)
end

local function point_in_rect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

-- Fill self._level_visuals[box_idx] for every puzzle in that box.
-- Idempotent: skips if already computed and descriptors haven't changed.
function M:_ensure_visuals(box_idx)
    if self._level_visuals[box_idx] ~= nil then return end
    local box = self.boxes[box_idx]
    if box == nil or box.puzzles == nil then
        self._level_visuals[box_idx] = {}
        return
    end
    local entries = {}
    for i = 1, #box.puzzles do
        local p = box.puzzles[i]
        local desc = self.descriptors and self.descriptors[p.id] or nil
        local size = "m"
        if desc ~= nil then
            size = pick_card_size(desc.width, desc.height)
        end
        local h = string_hash(p.id or tostring(i))
        local pushpin = PUSHPIN_COLORS[(h % #PUSHPIN_COLORS) + 1]
        -- Deterministic pseudo-random rotation in [-0.05, +0.05] rad.
        local rot = (((h / 7) % 1000) / 1000 - 0.5) * 0.10
        -- Sway phase + speed: also deterministic so the page looks the
        -- same every visit. Phase covers full 0..2pi; speed 1.2..1.7.
        local sway_phase = ((h / 13) % 6283) / 1000.0
        local sway_speed = 1.2 + ((h / 17) % 500) / 1000.0
        entries[i] = {
            size = size,
            pushpin = pushpin,
            rotation = rot,
            sway_phase = sway_phase,
            sway_speed = sway_speed,
        }
    end
    self._level_visuals[box_idx] = entries
end

function M:level_visuals(box_idx, puzzle_idx)
    self:_ensure_visuals(box_idx)
    local entries = self._level_visuals[box_idx] or {}
    return entries[puzzle_idx]
end

-- Pack puzzle cards into rows that fit the page width. Cards keep
-- per-puzzle widths/heights from CARD_SIZE; rows wrap greedily and
-- are centered horizontally. y origin is the top of the first row
-- (no scroll applied here — scroll is added at lookup time in
-- :layout_level_tile so we can scissor the page rect cleanly).
function M:_ensure_levels_layout(win_w)
    local cached = self._level_layout[self.selected_box]
    if cached ~= nil and cached.win_w == win_w then return cached end

    self:_ensure_visuals(self.selected_box)
    local box = self.boxes[self.selected_box]
    local visuals = self._level_visuals[self.selected_box] or {}
    local L = M.LAYOUT

    local px, py, pw, _ph = page_rect(win_w)
    local inner_x = px + L.page_pad_x
    local inner_w = pw - L.page_pad_x * 2

    local rects = {}
    if box == nil or box.puzzles == nil or inner_w <= 0 then
        local out = { win_w = win_w, rects = rects, content_h = 0,
                      page_x = px, page_y = py, page_w = pw }
        self._level_layout[self.selected_box] = out
        return out
    end

    -- Greedy row pack. Row state: list of card sizes + max height.
    local rows = {}
    local cur_row, cur_w, cur_max_h = {}, 0, 0
    for i = 1, #box.puzzles do
        local v = visuals[i] or { size = "m" }
        local sz = M.CARD_SIZE[v.size] or M.CARD_SIZE.m
        local cw, ch = sz.w, sz.h
        local need = cw + (#cur_row > 0 and L.level_col_gap or 0)
        if cur_w + need > inner_w and #cur_row > 0 then
            table.insert(rows, { items = cur_row, w = cur_w, h = cur_max_h })
            cur_row, cur_w, cur_max_h = {}, 0, 0
            need = cw  -- no leading gap on a fresh row
        end
        table.insert(cur_row, { idx = i, w = cw, h = ch })
        cur_w = cur_w + need
        if ch > cur_max_h then cur_max_h = ch end
    end
    if #cur_row > 0 then
        table.insert(rows, { items = cur_row, w = cur_w, h = cur_max_h })
    end

    local y = py + L.page_pad_y
    for _, row in ipairs(rows) do
        local x = inner_x + math.floor((inner_w - row.w) / 2)
        for j, item in ipairs(row.items) do
            -- Top-align within the row so taller cards don't push
            -- shorter ones around mid-row.
            rects[item.idx] = { x, y, item.w, item.h }
            x = x + item.w + L.level_col_gap
            -- guard unused (lint quiet)
            local _ = j
        end
        y = y + row.h + L.level_row_gap
    end
    local content_h = (y - (py + L.page_pad_y)) + L.page_pad_y

    local out = { win_w = win_w, rects = rects, content_h = content_h,
                  page_x = px, page_y = py, page_w = pw }
    self._level_layout[self.selected_box] = out
    return out
end

-- Returns the on-screen rect (post-scroll) of the i-th puzzle on the
-- current levels page. The unshifted rect comes from the cached row
-- pack; we apply self.scroll to y at lookup time.
function M:layout_level_tile(i, win_w)
    local layout = self:_ensure_levels_layout(win_w)
    local r = layout.rects[i]
    if r == nil then return 0, 0, 0, 0 end
    return r[1], r[2] - self.scroll, r[3], r[4]
end

-- Total content height (for scroll clamping) and the visible page rect.
function M:levels_metrics(win_w, win_h)
    local layout = self:_ensure_levels_layout(win_w)
    local _px, _py, _pw, ph = page_rect(win_w, win_h)
    return layout.content_h, ph, layout.page_x, layout.page_y, layout.page_w
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M:_clamp_scroll(win_w, win_h)
    local content_h, page_h = self:levels_metrics(win_w, win_h)
    local max_scroll = math.max(0, content_h - page_h)
    self.scroll = clamp(self.scroll, 0, max_scroll)
end

-- Forward declaration so :update can hover-test before the press
-- handlers (which define the body) appear.
local hit_press_target

local function ease_out(u)
    if u < 0 then return 0 end
    if u > 1 then return 1 end
    return 1 - (1 - u) ^ 3
end

function M:press_scale_for(kind, idx)
    local p = self.pressed
    if p == nil then return 1 end
    if p.kind ~= kind then return 1 end
    if (kind == "box" or kind == "level") and p.idx ~= idx then return 1 end
    if not p.released then
        local u = math.min(p.t / M.PRESS_DOWN_DURATION, 1)
        return 1 + (M.PRESS_SCALE_MIN - 1) * ease_out(u)
    end
    local u = math.min(p.release_t / M.PRESS_RELEASE_DURATION, 1)
    local base = M.PRESS_SCALE_MIN + (1 - M.PRESS_SCALE_MIN) * ease_out(u)
    local overshoot = 0.07 * math.sin(math.pi * u)
    return base + overshoot
end

function M:press_overlay_alpha_for(kind, idx)
    local p = self.pressed
    if p == nil then return 0 end
    if p.kind ~= kind then return 0 end
    if (kind == "box" or kind == "level") and p.idx ~= idx then return 0 end
    if not p.released then
        return math.min(p.t / M.PRESS_DOWN_DURATION, 1) * M.PRESS_OVERLAY_MAX
    end
    local u = math.min(p.release_t / (M.PRESS_RELEASE_DURATION * 0.35), 1)
    return (1 - u) * M.PRESS_OVERLAY_MAX
end

function M:hover_t_for(kind, idx)
    local p = self.pressed
    if p ~= nil and p.kind == kind then
        if kind == "back" or p.idx == idx then return 0 end
    end
    return self._hover[kind .. ":" .. idx] or 0
end

function M:update(dt, mouse_x, mouse_y, win_w, win_h)
    local p = self.pressed
    if p ~= nil then
        p.t = p.t + dt
        if p.released then
            p.release_t = p.release_t + dt
            if p.release_t >= M.PRESS_RELEASE_DURATION then
                self.pressed = nil
            end
        end
    end

    -- Keep scroll inside content bounds even if window resized.
    if self.screen == "levels" and win_w ~= nil then
        self:_clamp_scroll(win_w, win_h)
    end

    local hovered_key = nil
    if mouse_x ~= nil and mouse_y ~= nil and win_w ~= nil and self.pressed == nil then
        local hit = hit_press_target(self, mouse_x, mouse_y, win_w)
        if hit ~= nil then
            hovered_key = hit.kind .. ":" .. hit.idx
        end
    end

    local step = dt / M.HOVER_DURATION
    if hovered_key ~= nil then
        local cur = self._hover[hovered_key] or 0
        self._hover[hovered_key] = math.min(cur + step, 1)
    end
    for k, t in pairs(self._hover) do
        if k ~= hovered_key then
            local nt = t - step
            if nt <= 0 then
                self._hover[k] = nil
            else
                self._hover[k] = nt
            end
        end
    end
end

function hit_press_target(self, sx, sy, win_w)
    if self.screen == "boxes" then
        for i = 1, #self.boxes do
            local x, y, w, h = box_card_rect(i, win_w)
            if point_in_rect(sx, sy, x, y, w, h) then
                local box = self.boxes[i]
                if not progression.is_box_unlocked(self.progress, box) then
                    return nil
                end
                if box.puzzles == nil or #box.puzzles == 0 then
                    return nil
                end
                return { kind = "box", idx = i, rect = { x, y, w, h } }
            end
        end
        return nil
    end
    if self.screen == "levels" then
        local bx, by, bw, bh = back_button_rect()
        if point_in_rect(sx, sy, bx, by, bw, bh) then
            return { kind = "back", idx = 0, rect = { bx, by, bw, bh } }
        end
        local box = self.boxes[self.selected_box]
        if box == nil or box.puzzles == nil then return nil end
        for i = 1, #box.puzzles do
            local x, y, w, h = self:layout_level_tile(i, win_w)
            if w > 0 and h > 0 and point_in_rect(sx, sy, x, y, w, h) then
                return { kind = "level", idx = i, rect = { x, y, w, h } }
            end
        end
        return nil
    end
    return nil
end

function M:handle_tap(sx, sy, win_w, win_h)
    local hit = hit_press_target(self, sx, sy, win_w)
    if hit == nil then
        self.pressed = nil
        -- Even on empty space we want drag-to-scroll on the levels page.
        if self.screen == "levels" then
            self._drag = { x0 = sx, y0 = sy, last_y = sy,
                           scroll0 = self.scroll, win_w = win_w, win_h = win_h,
                           became_drag = true }
        else
            self._drag = nil
        end
        return nil
    end
    self.pressed = {
        kind = hit.kind,
        idx = hit.idx,
        rect = hit.rect,
        t = 0,
        released = false,
        release_t = 0,
        release_ok = false,
    }
    if self.screen == "levels" then
        self._drag = { x0 = sx, y0 = sy, last_y = sy,
                       scroll0 = self.scroll, win_w = win_w, win_h = win_h,
                       became_drag = false }
    else
        self._drag = nil
    end
    return nil
end

-- Pointer move while a press / drag is active. Two effects:
--   1. If movement exceeds DRAG_THRESHOLD, cancel the press (no level
--      tap will fire on release) and convert the gesture to a scroll.
--   2. While in drag mode, update self.scroll based on dy from press
--      origin, clamped to content height.
function M:handle_drag(sx, sy, win_w, win_h)
    local d = self._drag
    if d == nil then return end
    if win_w ~= nil then d.win_w = win_w end
    if win_h ~= nil then d.win_h = win_h end
    local dy_total = sy - d.y0
    if not d.became_drag then
        local dx = sx - d.x0
        if math.abs(dx) > M.DRAG_THRESHOLD or math.abs(dy_total) > M.DRAG_THRESHOLD then
            d.became_drag = true
            -- Cancel the in-flight press so handle_release won't fire.
            self.pressed = nil
        end
    end
    if d.became_drag then
        -- Drag-up (negative dy) scrolls content up (scroll increases).
        self.scroll = d.scroll0 - dy_total
        self:_clamp_scroll(d.win_w or win_w, d.win_h or win_h)
    end
    d.last_y = sy
end

function M:handle_release(sx, sy, win_w, win_h)
    -- Drag wins over press: if the gesture became a scroll, drop the
    -- press without firing its action.
    local was_drag = self._drag and self._drag.became_drag or false
    self._drag = nil
    if was_drag then
        self.pressed = nil
        return
    end
    local p = self.pressed
    if p == nil then return end
    if p.released then return end
    local r = p.rect
    local inside = point_in_rect(sx, sy, r[1], r[2], r[3], r[4])
    p.released = true
    p.release_t = 0
    p.release_ok = inside
    if not inside then
        return
    end
    if p.kind == "box" then
        self.selected_box = p.idx
        self.screen = "levels"
        self.scroll = 0
        -- Pre-warm visuals + layout for the new box so first frame is
        -- correct (otherwise the very first hit-test sees an empty
        -- layout and could miss a tap on the same frame as entry).
        self:_ensure_visuals(self.selected_box)
        if win_w ~= nil then
            self:_ensure_levels_layout(win_w)
            self:_clamp_scroll(win_w, win_h)
        end
    elseif p.kind == "back" then
        self.screen = "boxes"
        self.selected_box = nil
        self.scroll = 0
    elseif p.kind == "level" then
        self.play_pending = { box_idx = self.selected_box, puzzle_idx = p.idx }
    end
end

-- Mouse wheel scroll on the levels page. dy > 0 (wheel up) scrolls
-- content up (scroll decreases).
function M:wheel(dy, win_w, win_h)
    if self.screen ~= "levels" or dy == 0 then return end
    self.scroll = self.scroll - dy * M.WHEEL_STEP
    if win_w ~= nil then
        self:_clamp_scroll(win_w, win_h)
    end
end

function M:handle_key(key)
    if key == "escape" then
        if self.screen == "levels" then
            self.screen = "boxes"
            self.selected_box = nil
            self.scroll = 0
            self.pressed = nil
            self._drag = nil
            return { kind = "consumed" }
        end
    end
    return nil
end

function M:current_box()
    if self.selected_box == nil then return nil end
    return self.boxes[self.selected_box]
end

function M:go_to_boxes()
    self.screen = "boxes"
    self.selected_box = nil
    self.scroll = 0
    self.pressed = nil
    self._drag = nil
    self.play_pending = nil
end

return M
