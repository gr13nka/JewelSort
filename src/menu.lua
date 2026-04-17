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

-- Layout constants are recomputed each frame from window size; these are
-- just the fractions / paddings used by both menu.lua and render.lua.
M.LAYOUT = {
    box_card_height = 150,    -- bigger to fit 32px Fredoka title + medals
    box_card_gap = 16,
    boxes_top_padding = 130,  -- room for big header + "Select a book" subtitle
    level_tile_size = 200,    -- bigger so puzzle id label (~22px) fits cleanly
    level_tile_gap = 16,
    levels_top_padding = 150, -- room for big back button + header + subtitle
    side_margin = 20,
    badge_w = 96,
    badge_h = 34,
    badge_margin_right = 20,
    badge_margin_top = 14,
}

-- Press animation timings, shared by all pressable elements.
M.PRESS_DOWN_DURATION = 0.14
M.PRESS_RELEASE_DURATION = 0.26
M.PRESS_SCALE_MIN = 0.94
M.PRESS_OVERLAY_MAX = 0.22

function M.new(boxes, progress)
    local self = setmetatable({}, M)
    self.boxes = boxes or {}
    self.progress = progress
    self.screen = "boxes"
    self.selected_box = nil
    self.scroll = 0 -- pixel offset, currently unused (content fits window)
    -- Press-animation state. `pressed` is nil unless the pointer is down
    -- over a pressable element (box card / level tile / back button).
    --   kind   = "box" | "level" | "back"
    --   idx    = integer (ignored for "back")
    --   rect   = snapshot of the element's rect at press time
    --   t      = seconds since press-down started
    --   released     = boolean: pointer has been released
    --   release_t    = seconds since release fired (0 until released)
    --   release_ok   = boolean: release happened inside the original rect
    self.pressed = nil
    self.play_pending = nil
    return self
end

-- Rect helpers (no persistent layout; menus are small).

local function box_card_rect(i, win_w)
    local L = M.LAYOUT
    local x = L.side_margin
    local w = win_w - L.side_margin * 2
    local y = L.boxes_top_padding + (i - 1) * (L.box_card_height + L.box_card_gap)
    return x, y, w, L.box_card_height
end

local function level_tile_rect(i, win_w)
    local L = M.LAYOUT
    local usable = win_w - L.side_margin * 2
    local tile = L.level_tile_size
    local gap = L.level_tile_gap
    local cols = math.max(1, math.floor((usable + gap) / (tile + gap)))
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    -- Center the grid horizontally
    local grid_w = cols * tile + (cols - 1) * gap
    local x0 = L.side_margin + math.floor((usable - grid_w) / 2)
    local x = x0 + col * (tile + gap)
    local y = L.levels_top_padding + row * (tile + gap)
    return x, y, tile, tile
end

-- Back-button rect (top-left area on levels screen).
local function back_button_rect()
    local L = M.LAYOUT
    return L.side_margin, L.side_margin, 140, 56
end

-- Jewel badge rect (top-right, on both menu screens). This is the single
-- source of truth used by render.lua (drawing) and main.lua (flight target).
local function badge_rect(win_w, _win_h)
    local L = M.LAYOUT
    local x = win_w - L.badge_w - L.badge_margin_right
    local y = L.badge_margin_top
    return x, y, L.badge_w, L.badge_h
end

function M:layout_box_card(i, win_w)
    return box_card_rect(i, win_w)
end

function M:layout_level_tile(i, win_w)
    return level_tile_rect(i, win_w)
end

function M:back_button_rect()
    return back_button_rect()
end

function M:badge_rect(win_w, win_h)
    return badge_rect(win_w, win_h)
end

local function point_in_rect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

-- Cubic ease-out, reused by the press tween. Matches the easing shape
-- already used for hover-lift / fly-travel in render.lua.
local function ease_out(u)
    if u < 0 then return 0 end
    if u > 1 then return 1 end
    return 1 - (1 - u) ^ 3
end

-- Scale factor for a pressable element at its current anim position.
-- Returns 1 when this element isn't the one being pressed.
function M:press_scale_for(kind, idx)
    local p = self.pressed
    if p == nil then return 1 end
    if p.kind ~= kind then return 1 end
    if (kind == "box" or kind == "level") and p.idx ~= idx then return 1 end
    if not p.released then
        local u = math.min(p.t / M.PRESS_DOWN_DURATION, 1)
        return 1 + (M.PRESS_SCALE_MIN - 1) * ease_out(u)
    end
    -- Release phase: rise back to 1 with a tiny overshoot.
    local u = math.min(p.release_t / M.PRESS_RELEASE_DURATION, 1)
    local base = M.PRESS_SCALE_MIN + (1 - M.PRESS_SCALE_MIN) * ease_out(u)
    local overshoot = 0.07 * math.sin(math.pi * u)
    return base + overshoot
end

-- Dark-scrim alpha for a pressable element: ramps up while pressed,
-- fades out quickly on release. Returns 0 for non-matching elements.
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

-- Advance press-animation state. Safe to call every frame regardless of
-- screen (cheap; lets the release tail finish after a quick transition).
function M:update(dt)
    local p = self.pressed
    if p == nil then return end
    p.t = p.t + dt
    if p.released then
        p.release_t = p.release_t + dt
        if p.release_t >= M.PRESS_RELEASE_DURATION then
            self.pressed = nil
        end
    end
end

local function hit_press_target(self, sx, sy, win_w)
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
            local x, y, w, h = level_tile_rect(i, win_w)
            if point_in_rect(sx, sy, x, y, w, h) then
                return { kind = "level", idx = i, rect = { x, y, w, h } }
            end
        end
        return nil
    end
    return nil
end

-- Pointer-down. Starts the press-animation on a pressable element (if any).
-- Does NOT commit the action — that happens in handle_release.
-- Returns nil (legacy signature preserved; callers ignore return).
function M:handle_tap(sx, sy, win_w, _win_h)
    local hit = hit_press_target(self, sx, sy, win_w)
    if hit == nil then
        self.pressed = nil
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
    return nil
end

-- Pointer-up. If released inside the original rect, runs the post-release
-- action (screen change for box/back, sets play_pending for level).
function M:handle_release(sx, sy, _win_w, _win_h)
    local p = self.pressed
    if p == nil then return end
    -- Already released (multi-touch edge case): ignore extras.
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
    elseif p.kind == "back" then
        self.screen = "boxes"
        self.selected_box = nil
    elseif p.kind == "level" then
        self.play_pending = { box_idx = self.selected_box, puzzle_idx = p.idx }
    end
end

function M:handle_key(key)
    if key == "escape" then
        if self.screen == "levels" then
            self.screen = "boxes"
            self.selected_box = nil
            self.pressed = nil
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
    self.pressed = nil
    self.play_pending = nil
end

return M
