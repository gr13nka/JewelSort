-- render.lua
-- Draws the grid, jewels, shelf, hover cluster, win celebration, menu,
-- and the jewel flight overlay (celebration -> counter).
-- The layout module computes rectangles once per frame; draw reads them.

local M = {}

local Level = require("src.level")
local wood = require("src.wood")

local P = wood.palette

local FLASH_COLOR = { 0.80, 0.20, 0.18 }

-- Fredoka One (Google Fonts, SIL OFL) — rounded warm display font that
-- matches the cozy puzzle / Picross 3D vibe. 2.5x over LÖVE default (~13 -> 32).
local FONT_PATH = "assets/fonts/FredokaOne-Regular.ttf"
local FONT_BODY_SIZE = 32
local FONT_SMALL_SIZE = 22
local _font_body, _font_small

local function font_body()
    if _font_body == nil then
        _font_body = love.graphics.newFont(FONT_PATH, FONT_BODY_SIZE)
    end
    return _font_body
end

local function font_small()
    if _font_small == nil then
        _font_small = love.graphics.newFont(FONT_PATH, FONT_SMALL_SIZE)
    end
    return _font_small
end

local function use_body() love.graphics.setFont(font_body()) end
local function use_small() love.graphics.setFont(font_small()) end

local MEDAL_COLORS = {
    bronze = { 0.80, 0.50, 0.20 },
    silver = { 0.80, 0.82, 0.86 },
    gold   = { 1.00, 0.84, 0.30 },
}

-- Counter badge visual. Kept centralized so menu:badge_rect matches.
local BADGE_W = 96
local BADGE_H = 34

-- Celebration timeline (seconds since celebration.t = 0).
-- First-time solve path:
local CEL = {
    SCRIM_END        = 0.22,
    CARD_START       = 0.10,
    CARD_END         = 0.45,
    TITLE_START      = 0.35,
    TITLE_END        = 0.60,
    MEDAL_START      = 0.55,
    MEDAL_END        = 0.95,
    CONFETTI_TIMES   = { 0.60, 0.90, 1.20 },
    COUNT_START      = 0.95,
    COUNT_END        = 1.55,
    BUTTON_START     = 1.70,
    BUTTON_READY     = 2.00,
    -- Replay short-path skips medal bounce / count / confetti and brings
    -- the button in earlier so the replayer can get out.
    REPLAY_BUTTON_START = 0.70,
    REPLAY_BUTTON_READY = 1.00,
}

-- Celebration card layout. `celebration_button_rect` must recompute using
-- the same numbers so hit-testing matches the drawn button position.
local CEL_PW_MAX   = 420
local CEL_PW_PAD   = 60
local CEL_PH       = 280
local CEL_BTN_W    = 200
local CEL_BTN_H    = 64
local CEL_BTN_BOT  = 20  -- button bottom padding inside card

-- Compute layout rects for the current window + level.
-- Returns a table with:
--   grid_area, shelf_area, progress_area, back_button_rect,
--   cell_size, origin_x, origin_y, cols, rows
function M.compute_layout(level, win_w, win_h)
    local margin = 16
    -- Top header band holds the in-puzzle back button.
    local back_button_w = 110
    local back_button_h = 44
    local header_h = back_button_h + 8 -- 4px top pad (= margin residual), 8px bottom gap
    -- Shelf is now a 2-row tray. Height is clamped so tall windows don't bloat it.
    local shelf_h = math.min(math.floor(win_h * 0.20), 180)
    -- Dedicated strip for the solve-progress bar, sitting just above the shelf.
    local progress_h = 20
    local shelf_y = win_h - margin - shelf_h
    local progress_y = shelf_y - progress_h - 4 -- 4px gap between bar and shelf top
    local grid_top = margin + header_h
    local grid_area = {
        x = margin,
        y = grid_top,
        w = win_w - margin * 2,
        h = progress_y - grid_top - 4,
    }
    local progress_area = {
        x = margin,
        y = progress_y,
        w = win_w - margin * 2,
        h = progress_h,
    }
    local shelf_area = {
        x = margin,
        y = shelf_y,
        w = win_w - margin * 2,
        h = shelf_h,
    }
    local back_button_rect = {
        x = margin,
        y = margin,
        w = back_button_w,
        h = back_button_h,
    }
    local cols = level.width
    local rows = level.height
    local cell_w = grid_area.w / cols
    local cell_h = grid_area.h / rows
    local cell_size = math.floor(math.min(cell_w, cell_h))
    local grid_pixel_w = cell_size * cols
    local grid_pixel_h = cell_size * rows
    local origin_x = grid_area.x + math.floor((grid_area.w - grid_pixel_w) / 2)
    local origin_y = grid_area.y + math.floor((grid_area.h - grid_pixel_h) / 2)
    return {
        grid_area = grid_area,
        shelf_area = shelf_area,
        progress_area = progress_area,
        back_button_rect = back_button_rect,
        cell_size = cell_size,
        origin_x = origin_x,
        origin_y = origin_y,
        cols = cols,
        rows = rows,
    }
end

-- Screen coordinates -> grid (gx, gy) or nil if outside grid.
function M.screen_to_grid(layout, sx, sy)
    local gx = math.floor((sx - layout.origin_x) / layout.cell_size)
    local gy = math.floor((sy - layout.origin_y) / layout.cell_size)
    if gx < 0 or gy < 0 or gx >= layout.cols or gy >= layout.rows then
        return nil
    end
    return gx, gy
end

-- Shelf layout: 2 rows × 6 columns, capacity 12 total.
local SHELF_COLS = 6
local SHELF_ROWS = 2

-- Pixel edge length of one shelf slot. Derived from the shelf area so
-- the 12 slots always fit as a 2×6 grid with ~10% vertical padding.
local function shelf_slot_size(area)
    local slot = math.min(
        math.floor(area.w / SHELF_COLS),
        math.floor(area.h / SHELF_ROWS * 0.9)
    )
    return math.max(slot, 8)
end

-- Return pixel center (cx, cy) and slot edge for shelf slot `index` (1-based).
-- Fills left-to-right, top-to-bottom: 1..6 top row, 7..12 bottom row.
local function shelf_slot_center(area, index)
    local i = index - 1
    local col = i % SHELF_COLS
    local row = math.floor(i / SHELF_COLS)
    local slot = shelf_slot_size(area)
    local grid_w = slot * SHELF_COLS
    local grid_h = slot * SHELF_ROWS
    local ox = area.x + math.floor((area.w - grid_w) / 2)
    local oy = area.y + math.floor((area.h - grid_h) / 2)
    return ox + (col + 0.5) * slot, oy + (row + 0.5) * slot, slot
end

-- Screen coords -> shelf index (1..N) or nil.
-- Taps inside the shelf area but outside the 2×6 slot grid (or past the
-- current shelf_len) resolve to 0 meaning "empty shelf region".
function M.screen_to_shelf(layout, shelf_len, sx, sy, _capacity)
    local a = layout.shelf_area
    if sx < a.x or sx > a.x + a.w or sy < a.y or sy > a.y + a.h then
        return nil
    end
    if shelf_len <= 0 then return 0 end
    local slot = shelf_slot_size(a)
    local grid_w = slot * SHELF_COLS
    local grid_h = slot * SHELF_ROWS
    local ox = a.x + math.floor((a.w - grid_w) / 2)
    local oy = a.y + math.floor((a.h - grid_h) / 2)
    local col = math.floor((sx - ox) / slot)
    local row = math.floor((sy - oy) / slot)
    if col < 0 or col >= SHELF_COLS or row < 0 or row >= SHELF_ROWS then
        return 0
    end
    local idx = row * SHELF_COLS + col + 1
    if idx > shelf_len then return 0 end
    return idx
end

local function draw_desk(win_w, win_h)
    wood.draw_panel("desk", 0, 0, win_w, win_h)
end

-- Each cell is a painted target-color ring around a recessed dark hole,
-- sitting on the wooden board. The ring IS the color cue — the player
-- needs to see which color goes where, so this can't be wooden.
local function draw_cell(x, y, size, jewel_color, hovering, target_color)
    local cx = x + size / 2
    local cy = y + size / 2
    local ring_r = size * 0.46
    local hole_r = size * 0.36

    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.circle("fill", cx, cy + 2, ring_r)

    -- Painted target-color ring.
    if target_color ~= nil then
        love.graphics.setColor(target_color[1], target_color[2], target_color[3], 1)
    else
        love.graphics.setColor(P.plaque)
    end
    love.graphics.circle("fill", cx, cy, ring_r)
    -- Subtle top-edge highlight + bottom shade on the painted ring.
    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(1, 1, 1, 0.28)
    love.graphics.arc("line", "open", cx, cy, ring_r - 1, math.pi * 1.1, math.pi * 1.9)
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.arc("line", "open", cx, cy, ring_r - 1, math.pi * 0.1, math.pi * 0.9)

    -- Recessed dark hole inside the ring.
    love.graphics.setColor(P.walnut_dark[1], P.walnut_dark[2], P.walnut_dark[3], 1)
    love.graphics.circle("fill", cx, cy, hole_r)
    love.graphics.setColor(0, 0, 0, 0.30)
    love.graphics.arc("fill", cx, cy - hole_r * 0.15, hole_r * 0.95,
                      math.pi * 0.85, math.pi * 2.15)

    if jewel_color ~= nil and not hovering then
        love.graphics.setColor(jewel_color[1], jewel_color[2], jewel_color[3], 1)
        love.graphics.circle("fill", cx, cy, size * 0.34)
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.circle(
            "fill",
            cx - size * 0.08,
            cy - size * 0.10,
            size * 0.10
        )
    end
end

-- Draw just the jewel circle (+ highlight) inside a cell, at a scale
-- factor around the cell center. Used for cascade stomp pulse.
local function draw_cell_jewel_scaled(x, y, size, color, scale)
    scale = scale or 1
    local cx = x + size / 2
    local cy = y + size / 2
    local r = size * 0.34 * scale
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.circle(
        "fill",
        cx - size * 0.08 * scale,
        cy - size * 0.10 * scale,
        size * 0.10 * scale
    )
end

local function draw_jewel(cx, cy, radius, color, lifted)
    if lifted then
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.circle("fill", cx + 2, cy + 8, radius)
    end
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.circle("fill", cx, cy, radius)
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.circle("fill", cx - radius * 0.25, cy - radius * 0.3, radius * 0.3)
end

-- Text with a soft darker "engraved" shadow underneath.
local function print_engraved(text, x, y, w, align, ink, shadow_alpha)
    shadow_alpha = shadow_alpha or 0.35
    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.printf(text, x, y + 1, w, align)
    love.graphics.setColor(ink[1], ink[2], ink[3], 1)
    love.graphics.printf(text, x, y, w, align)
end

-- Wrap a draw block in a uniform scale around (cx, cy). Caller must
-- emit a matching love.graphics.pop() after the draw body.
local function push_scale_around(cx, cy, s)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(s, s)
    love.graphics.translate(-cx, -cy)
end

function M.draw(level, layout, mouse_x, mouse_y, particles)
    use_body()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    draw_desk(W, H)

    -- Recessed "game board" plaque behind the grid area.
    local ga = layout.grid_area
    wood.draw_panel("board", ga.x - 6, ga.y - 6, ga.w + 12, ga.h + 12, 12)

    local origin_x, origin_y = layout.origin_x, layout.origin_y
    local size = layout.cell_size

    local hovering_cells = {}
    if level.state.kind == "hovering" and level.state.source == "grid" then
        for i = 1, #(level.state.origin_cells or {}) do
            local oc = level.state.origin_cells[i]
            hovering_cells[oc.x .. "," .. oc.y] = true
        end
    end

    local pa = level.place_anim
    local wa = level.win_anim
    local cascade_active = wa ~= nil
    local fly_suppress = pa ~= nil and pa.fly_cells_set or nil

    for i = 1, #level.cell_list do
        local c = level.cell_list[i]
        local x = origin_x + c.x * size
        local y = origin_y + c.y * size
        local key = c.x .. "," .. c.y
        local hv = hovering_cells[key] == true
        local suppress = hv or (fly_suppress and fly_suppress[key])
        draw_cell(x, y, size, nil, false, c.target)
        if c.jewel ~= nil and not suppress then
            local scale = 1
            if cascade_active then
                local d = wa.cell_delays[key] or 0
                local local_t = wa.t - d * Level.CASCADE_STAGGER
                if local_t >= 0 and local_t <= Level.STOMP_DURATION then
                    local u = local_t / Level.STOMP_DURATION
                    scale = 1 + (Level.STOMP_PEAK - 1) * math.sin(math.pi * u)
                end
            end
            draw_cell_jewel_scaled(x, y, size, c.jewel, scale)
        end
    end

    -- Shelf: recessed walnut tray with slot outlines.
    local s = layout.shelf_area
    wood.draw_panel("shelf_tray", s.x, s.y, s.w, s.h, 10)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", s.x + 2, s.y + 2, s.w - 4, 3)

    local shelf_len = #level.shelf
    local capacity = level.shelf_capacity or shelf_len
    local slot = shelf_slot_size(s)
    local r = math.floor(slot * 0.38)

    love.graphics.setLineWidth(1)
    for i = 1, capacity do
        local cx, cy = shelf_slot_center(s, i)
        love.graphics.setColor(P.walnut_dark[1], P.walnut_dark[2], P.walnut_dark[3], 0.85)
        love.graphics.circle("fill", cx, cy, r)
        love.graphics.setColor(P.plaque_light[1], P.plaque_light[2], P.plaque_light[3], 0.55)
        love.graphics.circle("line", cx, cy, r)
    end

    for i = 1, shelf_len do
        local jewel = level.shelf[i]
        local cx, cy = shelf_slot_center(s, i)
        draw_jewel(cx, cy, r, jewel.color, false)
    end

    -- Solve progress: 8 segments of gold foil in the dedicated strip
    -- between the grid and the shelf.
    local p = layout.progress_area
    local segments = 8
    local solved, total = level:progress()
    local filled = (total > 0) and math.floor((solved / total) * segments + 0.0001) or 0
    local bar_h = 10
    local bar_w = p.w - 24
    local bar_x = p.x + 12
    local bar_y = p.y + math.floor((p.h - bar_h) / 2)
    local seg_gap = 3
    local seg_w = (bar_w - seg_gap * (segments - 1)) / segments

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", bar_x - 2, bar_y - 2, bar_w + 4, bar_h + 4, 4, 4)

    for i = 1, segments do
        local sx = bar_x + (i - 1) * (seg_w + seg_gap)
        if i <= filled then
            love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.95)
        else
            love.graphics.setColor(P.walnut_dark[1], P.walnut_dark[2], P.walnut_dark[3], 0.85)
        end
        love.graphics.rectangle("fill", sx, bar_y, seg_w, bar_h, 3, 3)
        if i <= filled then
            love.graphics.setColor(1, 1, 1, 0.35)
            love.graphics.rectangle("fill", sx, bar_y, seg_w, 2)
        end
    end

    if level.flash ~= nil and level.flash.t and level.flash.t > 0 then
        local alpha = math.min(1, level.flash.t)
        love.graphics.setColor(0, 0, 0, alpha * 0.45)
        love.graphics.printf(level.flash.text or "", s.x, s.y + 5, s.w, "center")
        love.graphics.setColor(FLASH_COLOR[1], FLASH_COLOR[2], FLASH_COLOR[3], alpha)
        love.graphics.printf(level.flash.text or "", s.x, s.y + 4, s.w, "center")
    end

    -- Hover cluster floats at origin positions, preserving cluster shape.
    -- Lift eases in from 0 over Level.LIFT_DURATION so the pick-up reads as
    -- a smooth jump rather than a teleport.
    if level.state.kind == "hovering" then
        local col = level.state.color
        local lift_t = level.state.lift_t or 0
        local lu = math.min(lift_t / Level.LIFT_DURATION, 1)
        local lift_eased = 1 - (1 - lu) ^ 3
        -- Tiny overshoot near the top of the lift for springiness.
        local overshoot = (lu < 1) and math.sin(math.pi * lu) * 0.08 or 0
        local lift = math.floor(size * (0.18 * lift_eased + overshoot))
        local t_now = love.timer.getTime()
        local dt = love.timer.getDelta()
        if level.state.source == "grid" then
            local r2 = math.floor(size * 0.34)
            for i = 1, #level.state.origin_cells do
                local oc = level.state.origin_cells[i]
                local cx = origin_x + oc.x * size + size / 2
                local bob = math.sin(t_now * 4 + oc.x * 0.7 + oc.y * 0.5) * 2
                local cy2 = origin_y + oc.y * size + size / 2 - lift + bob
                draw_jewel(cx, cy2, r2, col, true)
                -- Occasional twinkle while held aloft.
                if particles ~= nil and math.random() < 12 * dt then
                    particles:spawn(cx, cy2, col, 1)
                end
            end
        else
            local n = #level.state.jewels
            local r2 = math.floor(slot * 0.38)
            local total_w = n * slot
            local start_x = s.x + (s.w - total_w) / 2 + slot / 2
            local cy2 = s.y - r2 - 6
            for i = 1, n do
                local cx = start_x + (i - 1) * slot
                local bob = math.sin(t_now * 4 + i * 0.5) * 2
                draw_jewel(cx, cy2 + bob, r2, col, true)
                if particles ~= nil and math.random() < 12 * dt then
                    particles:spawn(cx, cy2 + bob, col, 1)
                end
            end
        end
    end

    -- Fly animation: every placement. Travel phase follows a smoothstep
    -- arc, then a brief landing squash + expanding ring flash + glitter
    -- burst before the jewel settles into the cell.
    if pa ~= nil then
        local travel_t = math.min(pa.t, Level.FLY_DURATION)
        local u = travel_t / Level.FLY_DURATION
        -- Smoothstep eases both ends for a more natural toss.
        local eu = u * u * (3 - 2 * u)
        local landing_scale = 1
        local pt = 0
        local landing = false
        if pa.t > Level.FLY_DURATION then
            landing = true
            pt = (pa.t - Level.FLY_DURATION) / Level.LANDING_PULSE
            if pt < 0 then pt = 0 elseif pt > 1 then pt = 1 end
            landing_scale = 1 + (Level.STOMP_PEAK - 1) * math.sin(math.pi * pt)
        end
        local base_r = size * 0.34
        local lift = math.floor(size * 0.18)
        local arc_h = size * Level.FLY_ARC_HEIGHT
        local dt = love.timer.getDelta()
        for i = 1, #pa.fly do
            local f = pa.fly[i]
            local fx, fy
            if f.from.source == "grid" then
                fx = origin_x + f.from.gx * size + size / 2
                fy = origin_y + f.from.gy * size + size / 2 - lift
            else
                local shelf_r = math.floor(slot * 0.38)
                local total_w = #pa.fly * slot
                local start_x = s.x + (s.w - total_w) / 2 + slot / 2
                fx = start_x + (f.from.shelf_index - 1) * slot
                fy = s.y - shelf_r - 6
            end
            local tx, ty
            if f.to.source == "shelf" then
                tx, ty = shelf_slot_center(s, f.to.shelf_index)
            else
                tx = origin_x + f.to.gx * size + size / 2
                ty = origin_y + f.to.gy * size + size / 2
            end
            local cx = fx + (tx - fx) * eu
            local cy2 = fy + (ty - fy) * eu
            cy2 = cy2 - arc_h * math.sin(math.pi * u)
            -- Squash+stretch during travel: slightly narrower/taller at
            -- apex. Not visible on a circle, but tweaks the radius to
            -- hint at speed — a touch bigger in mid-flight.
            local travel_scale = 1 + 0.06 * math.sin(math.pi * u)
            local r2 = math.floor(base_r * landing_scale * travel_scale)

            -- Landing ring flash at the target cell.
            if landing then
                local ring_r = base_r * (1 + pt * 1.35)
                local ring_a = (1 - pt) * 0.7
                love.graphics.setLineWidth(2)
                love.graphics.setColor(f.color[1], f.color[2], f.color[3], ring_a)
                love.graphics.circle("line", tx, ty, ring_r)
                love.graphics.setColor(1, 1, 1, ring_a * 0.55)
                love.graphics.circle("line", tx, ty, ring_r * 0.75)
            end

            draw_jewel(cx, cy2, r2, f.color, true)

            if particles ~= nil then
                -- Trail: spawn ~90 sparkles/sec per jewel during travel.
                if not landing then
                    local rate = 90
                    local n = math.floor(rate * dt + math.random())
                    if n > 0 then
                        particles:spawn(cx, cy2, f.color, n)
                    end
                else
                    -- Burst concentrated in the first frames of landing.
                    local burst = math.floor(240 * (1 - pt) * dt + math.random())
                    if burst > 0 then
                        particles:spawn(tx, ty, f.color, burst)
                    end
                end
            end
        end
    end

    -- Particles (glitter) render above the board but below the celebration.
    if particles ~= nil then
        particles:draw()
    end

    -- In-puzzle back button (top-left header band). Hit-test lives in
    -- main.lua so the tap never reaches input.classify / tap_cell.
    local b = layout.back_button_rect
    if b ~= nil then
        wood.draw_panel("plaque", b.x, b.y, b.w, b.h, 8)
        love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.45)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", b.x + 0.5, b.y + 0.5, b.w - 1, b.h - 1, 8, 8)
        use_small()
        local fh = love.graphics.getFont():getHeight()
        local ly = b.y + math.floor((b.h - fh) / 2) - 1
        print_engraved("< Back", b.x, ly, b.w, "center", P.ink_light, 0.4)
        use_body()
    end
end

-- --- Celebration + Complete button ---------------------------------------

-- Card rect matches draw_celebration's final (post-rise) position.
local function celebration_card_rect(W, H)
    local pw = math.min(W - CEL_PW_PAD, CEL_PW_MAX)
    local ph = CEL_PH
    local px = (W - pw) / 2
    local py = (H - ph) / 2 - 20
    return px, py, pw, ph
end

-- Public: rect of the Complete button on the celebration card. Used by
-- main.lua for press/release hit-testing and by draw_complete_button.
function M.celebration_button_rect(W, H)
    local px, py, pw, ph = celebration_card_rect(W, H)
    local bw = CEL_BTN_W
    local bh = CEL_BTN_H
    local bx = px + (pw - bw) / 2
    local by = py + ph - bh - CEL_BTN_BOT
    return bx, by, bw, bh
end

-- Public: card center — flight start position for the jewel flight.
function M.celebration_card_center(W, H)
    local px, py, pw, ph = celebration_card_rect(W, H)
    return px + pw / 2, py + ph / 2 - 30
end

-- Public: is the celebration in its "button tappable" phase? Used by
-- main.lua to gate pointer-down on the Complete button.
function M.celebration_button_ready(celebration)
    if celebration == nil then return false end
    local first = celebration.award and celebration.award.first_time
    if first then
        return celebration.t >= CEL.BUTTON_READY
    else
        return celebration.t >= CEL.REPLAY_BUTTON_READY
    end
end

local function draw_complete_button(rect, pressed, alpha, press_scale)
    local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
    press_scale = press_scale or 1
    local cx, cy = x + w / 2, y + h / 2
    local offset_y = pressed and 2 or 0

    love.graphics.push()
    love.graphics.translate(cx, cy + offset_y)
    love.graphics.scale(press_scale, press_scale)
    love.graphics.translate(-cx, -cy)

    love.graphics.setColor(1, 1, 1, alpha)
    wood.draw_panel("plaque", x, y, w, h, 10)

    -- Two foil bands (book-spine language) framing the label.
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.9 * alpha)
    love.graphics.rectangle("fill", x + 10, y + 8, w - 20, 3)
    love.graphics.rectangle("fill", x + 10, y + h - 11, w - 20, 3)

    -- Dark frame line.
    love.graphics.setColor(0, 0, 0, 0.45 * alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2, 10, 10)

    -- Label: foil-stamped "Complete" (paired with "< Back" as the other
    -- capitalized-verb button label).
    use_body()
    local fh = love.graphics.getFont():getHeight()
    local ly = y + (h - fh) / 2 - 1
    local label_alpha = pressed and 0.9 or 1.0
    love.graphics.setColor(0, 0, 0, 0.4 * alpha)
    love.graphics.printf("Complete", x, ly + 1, w, "center")
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], label_alpha * alpha)
    love.graphics.printf("Complete", x, ly, w, "center")

    love.graphics.pop()
end

function M.draw_complete_button(rect, pressed, alpha, press_scale)
    return draw_complete_button(rect, pressed, alpha, press_scale)
end

-- The main celebration overlay. `celebration` is the game.celebration
-- table owned by main.lua. This function also advances fire-and-forget
-- state on the celebration (count_display, confetti_fired) — those need
-- to cross into particles:spawn which is stateful, so we do it here.
function M.draw_celebration(celebration, particles, confetti, W, H)
    if celebration == nil then return end
    local t = celebration.t
    local award = celebration.award
    local is_first = award ~= nil and award.first_time

    -- Scrim fade-in.
    local scrim_u = math.min(t / CEL.SCRIM_END, 1)
    local scrim_a = 0.55 * (1 - (1 - scrim_u) ^ 3)
    love.graphics.setColor(0, 0, 0, scrim_a)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Paper confetti renders above the scrim but below the card, so the
    -- paper reads as being in the room rather than dimmed by the overlay.
    -- Sparkle particles (the shared `particles` list) already drew during
    -- render.draw() — this dedicated list is for celebration confetti only.
    if confetti ~= nil then
        confetti:draw()
    end

    -- Card position: final + rise-offset that decays to 0 as rise eases in.
    local final_px, final_py, pw, ph = celebration_card_rect(W, H)
    local rise_u = 0
    if t >= CEL.CARD_START then
        rise_u = math.min((t - CEL.CARD_START) / (CEL.CARD_END - CEL.CARD_START), 1)
    end
    local rise_eu = 1 - (1 - rise_u) ^ 3
    local y_offset = 80 * (1 - rise_eu)
    local card_scale = 0.92 + 0.08 * rise_eu
    local px, py = final_px, final_py + y_offset
    local card_cx = px + pw / 2
    local card_cy = py + ph / 2

    push_scale_around(card_cx, card_cy, card_scale)

    wood.draw_panel("parchment", px, py, pw, ph, 12)

    -- "Solved!" title: fades + scales in with sin overshoot.
    if t >= CEL.TITLE_START then
        local tu = math.min((t - CEL.TITLE_START) / (CEL.TITLE_END - CEL.TITLE_START), 1)
        local teu = 1 - (1 - tu) ^ 3
        local title_scale = 1.20 - 0.20 * teu + 0.06 * math.sin(math.pi * tu)
        local title_alpha = teu
        local title_cx = px + pw / 2
        local title_cy = py + 36
        use_body()
        push_scale_around(title_cx, title_cy, title_scale)
        love.graphics.setColor(0, 0, 0, 0.4 * title_alpha)
        love.graphics.printf("Solved!", px, py + 20 + 1, pw, "center")
        love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], title_alpha)
        love.graphics.printf("Solved!", px, py + 20, pw, "center")
        love.graphics.pop()
    end

    -- Medal: first-time bounces from above; replay is static (appears with
    -- a quick fade so the card isn't medal-less at rest).
    if award ~= nil and t >= CEL.MEDAL_START then
        local mu = math.min((t - CEL.MEDAL_START) / (CEL.MEDAL_END - CEL.MEDAL_START), 1)
        local medal_size = 56
        local base_x = W / 2 - medal_size / 2
        local base_y = py + 74
        local medal_y_offset = 0
        local medal_scale = 1
        if is_first then
            local meu = 1 - (1 - mu) ^ 3
            medal_y_offset = -30 * (1 - meu)
            -- Landing squash concentrated in the last 30% of the bounce.
            local land_t = math.max(0, math.min((mu - 0.7) / 0.3, 1))
            medal_scale = 1 + (Level.STOMP_PEAK - 1) * math.sin(math.pi * land_t) * 0.35
        end
        local mcx = base_x + medal_size / 2
        local mcy = base_y + medal_size / 2 + medal_y_offset
        push_scale_around(mcx, mcy, medal_scale)
        M.draw_medal(base_x, base_y + medal_y_offset, medal_size, award.tier)
        love.graphics.pop()
    end

    -- Confetti bursts — first-time only. Two cannons at the bottom
    -- corners shoot paper up and inward; gravity + drag carry pieces
    -- across the screen. Fires once per CONFETTI_TIMES entry.
    if is_first and confetti ~= nil and celebration.confetti_fired ~= nil then
        local palette = celebration.palette or { { 1, 1, 1 } }
        local per_cannon = 40
        local spread = 0.55
        local lx, ly = W * 0.08, H - 10
        local rx, ry = W * 0.92, H - 10
        for i = 1, #CEL.CONFETTI_TIMES do
            if (not celebration.confetti_fired[i]) and t >= CEL.CONFETTI_TIMES[i] then
                celebration.confetti_fired[i] = true
                confetti:spawn_confetti(lx, ly,  520, -900, spread, palette, per_cannon)
                confetti:spawn_confetti(rx, ry, -520, -900, spread, palette, per_cannon)
            end
        end
    end

    -- Count-up (first-time) OR "Already mastered" static line (replay).
    if award ~= nil then
        local line_y = py + 156
        use_body()
        if is_first then
            if t >= CEL.COUNT_START then
                local cu = math.min((t - CEL.COUNT_START) / (CEL.COUNT_END - CEL.COUNT_START), 1)
                local ceu = 1 - (1 - cu) ^ 3
                local new_display = math.floor(award.jewels_delta * ceu + 0.0001)
                -- Sparkle per integer tick so the count feels earned.
                if new_display > (celebration.count_display or 0) and particles ~= nil then
                    local palette = celebration.palette or { { 1, 1, 1 } }
                    local color = palette[((new_display - 1) % #palette) + 1]
                    particles:spawn(card_cx, line_y + 16, color, 12)
                end
                celebration.count_display = new_display
                local display_n = celebration.count_display or 0
                local line = "+" .. tostring(display_n) .. " jewel"
                if display_n ~= 1 then line = line .. "s" end
                love.graphics.setColor(0, 0, 0, 0.3)
                love.graphics.printf(line, px, line_y + 1, pw, "center")
                love.graphics.setColor(P.ink_soft[1], P.ink_soft[2], P.ink_soft[3], 1)
                love.graphics.printf(line, px, line_y, pw, "center")
            end
        else
            love.graphics.setColor(0, 0, 0, 0.3)
            love.graphics.printf("Already mastered", px, line_y + 1, pw, "center")
            love.graphics.setColor(P.ink_soft[1], P.ink_soft[2], P.ink_soft[3], 1)
            love.graphics.printf("Already mastered", px, line_y, pw, "center")
        end
    end

    love.graphics.pop() -- end card scale

    -- Complete button: fade in + 6px rise, then hold until pressed.
    local btn_start = is_first and CEL.BUTTON_START or CEL.REPLAY_BUTTON_START
    local btn_end = is_first and CEL.BUTTON_READY or CEL.REPLAY_BUTTON_READY
    if t >= btn_start then
        local bu = math.min((t - btn_start) / (btn_end - btn_start), 1)
        local beu = 1 - (1 - bu) ^ 3
        local btn_alpha = beu
        local bx, by, bw, bh = M.celebration_button_rect(W, H)
        local rise_off = 6 * (1 - beu)
        local rect = { bx, by + rise_off, bw, bh }
        -- Slight scale-down while held; overshoot is handled via the
        -- offset_y + press_scale combo inside draw_complete_button.
        local press_scale = celebration.button_pressed and 0.96 or 1.0
        draw_complete_button(rect, celebration.button_pressed == true, btn_alpha, press_scale)
    end
end

-- Draws the jewel flight in progress. Called after draw_menu so flights
-- render on top of the menu chrome.
function M.draw_flight_overlay(pending_flight, particles, menu, W, H)
    if pending_flight == nil then return end
    local bx, by, bw, bh = menu:badge_rect(W, H)
    local tx = bx + bw / 2
    local ty = by + bh / 2
    local sx = pending_flight.start_world.x
    local sy = pending_flight.start_world.y
    local dt = love.timer.getDelta()
    local duration = pending_flight.duration or 0.55

    local dx_total = tx - sx
    local dy_total = ty - sy
    local len = math.sqrt(dx_total * dx_total + dy_total * dy_total)
    if len < 1 then len = 1 end
    local perp_x = -dy_total / len
    local perp_y = dx_total / len

    for i = 1, #pending_flight.jewels do
        local j = pending_flight.jewels[i]
        if not j.arrived then
            local rel = pending_flight.t - j.t0
            if rel >= 0 then
                local u = math.min(rel / duration, 1)
                local eu = 1 - (1 - u) ^ 3
                local cx = sx + dx_total * eu
                local cy = sy + dy_total * eu
                local sign = (i % 2 == 0) and 1 or -1
                local amp = (60 + 40 * math.sin(i * 1.7)) * sign
                local off = math.sin(math.pi * u) * amp
                cx = cx + perp_x * off
                cy = cy + perp_y * off
                draw_jewel(cx, cy, 14, j.color, false)
                if particles ~= nil then
                    local n = math.floor(80 * dt + math.random())
                    if n > 0 then
                        particles:spawn(cx, cy, j.color, n)
                    end
                end
            end
        end
    end
end

-- Hold-to-reset overlay. `progress` is 0..1 (hold time / required duration).
-- Shown above whichever screen is active while F1 is held.
function M.draw_reset_overlay(progress, win_w, win_h)
    progress = math.max(0, math.min(progress, 1))
    -- Linear fade-in over the first 0.5s-worth of progress so a tap-and-
    -- release doesn't flash the UI.
    local fade = math.min(progress / (0.5 / 3), 1)
    if fade <= 0 then return end

    use_body()

    love.graphics.setColor(0, 0, 0, 0.35 * fade)
    love.graphics.rectangle("fill", 0, 0, win_w, win_h)

    local pw = math.min(win_w - 60, 380)
    local ph = 96
    local px = math.floor((win_w - pw) / 2)
    local py = math.floor((win_h - ph) / 2) - 20

    love.graphics.setColor(1, 1, 1, fade)
    wood.draw_panel("parchment", px, py, pw, ph, 12)

    love.graphics.setColor(0, 0, 0, 0.3 * fade)
    love.graphics.printf("Resetting progress...", px, py + 17, pw, "center")
    love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], fade)
    love.graphics.printf("Resetting progress...", px, py + 16, pw, "center")

    local bar_w = pw - 40
    local bar_h = 8
    local bar_x = px + 20
    local bar_y = py + ph - bar_h - 18

    love.graphics.setColor(0, 0, 0, 0.45 * fade)
    love.graphics.rectangle("fill", bar_x - 2, bar_y - 2, bar_w + 4, bar_h + 4, 3, 3)
    love.graphics.setColor(P.walnut_dark[1], P.walnut_dark[2], P.walnut_dark[3], 0.85 * fade)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 2, 2)

    local fill_w = math.floor(progress * bar_w)
    if fill_w > 0 then
        love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.95 * fade)
        love.graphics.rectangle("fill", bar_x, bar_y, fill_w, bar_h, 2, 2)
        love.graphics.setColor(1, 1, 1, 0.35 * fade)
        love.graphics.rectangle("fill", bar_x, bar_y, fill_w, 1)
    end
end

-- Draw a coin-like medal icon. `tier` is "bronze"|"silver"|"gold".
function M.draw_medal(x, y, size, tier)
    local color = MEDAL_COLORS[tier] or MEDAL_COLORS.bronze
    local r = size / 2
    local cx, cy = x + r, y + r
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.circle("fill", cx + 1, cy + 3, r)
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7, 1)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", cx, cy, r * 0.72)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.circle("fill", cx - r * 0.28, cy - r * 0.32, r * 0.28)
end

local BADGE_BLUE = { 0.35, 0.85, 1.00 }

-- Plaque-backed jewel counter. `pulse_scale` scales the whole badge from
-- its center; a soft foil-color glow ring draws behind when pulsed above
-- 1.0 (set by the flight-arrival handler in main.lua).
local function draw_jewel_badge(x, y, count, pulse_scale)
    pulse_scale = pulse_scale or 1
    local w, h = BADGE_W, BADGE_H
    local cx, cy = x + w / 2, y + h / 2

    push_scale_around(cx, cy, pulse_scale)

    -- Glow ring behind the plaque when pulsing.
    if pulse_scale > 1.001 then
        local glow_t = math.min((pulse_scale - 1) / 0.18, 1)
        love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.35 * glow_t)
        love.graphics.circle("fill", cx, cy, math.max(w, h) * (0.6 + glow_t * 0.5))
    end

    wood.draw_panel("plaque", x, y, w, h, 6)
    -- Foil top band.
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.9)
    love.graphics.rectangle("fill", x + 6, y + 4, w - 12, 2)
    -- Dark frame line.
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)

    -- Jewel icon on the left.
    local jx = x + 16
    local jy = y + h / 2 + 1
    draw_jewel(jx, jy, 9, BADGE_BLUE, false)

    -- Count numeral on the right, centered in the remaining space.
    use_small()
    local fh = love.graphics.getFont():getHeight()
    local ty = y + (h - fh) / 2
    local tx = x + 30
    local tw = w - 34
    print_engraved(tostring(count), tx, ty, tw, "center", P.ink_light, 0.4)
    use_body()

    love.graphics.pop()
end

-- Draw one "book" tile for a box card. A wooden plaque with a darker
-- "spine" strip down the left edge to evoke a closed book lying flat.
local function draw_box_card(menu, progression, box, i, win_w)
    local x, y, w, h = menu:layout_box_card(i, win_w)
    local unlocked = progression.is_box_unlocked(menu.progress, box)
    local done = progression.box_completed_count(menu.progress, box)
    local total = box.puzzles and #box.puzzles or 0

    local press_scale = menu:press_scale_for("box", i)
    local cx, cy = x + w / 2, y + h / 2
    push_scale_around(cx, cy, press_scale)

    -- Leather book cover, rotating colors per index. Locked boxes use
    -- the gray "locked" wood instead so they read as inert.
    local LEATHER = { "leather_red", "leather_green", "leather_blue" }
    local kind = unlocked and LEATHER[((i - 1) % 3) + 1] or "locked"
    wood.draw_panel(kind, x, y, w, h, 10)

    -- Spine strip on the left in a darker shade.
    local spine_w = 36
    wood.draw_panel(unlocked and "locked" or "locked", x, y, spine_w, h, 10)
    -- Two thin gold-foil bands around the spine like a hardback book.
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.9)
    love.graphics.rectangle("fill", x, y + 18, spine_w, 3)
    love.graphics.rectangle("fill", x, y + h - 22, spine_w, 3)

    -- Outer cover frame line.
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2, 10, 10)

    local title_x = x + spine_w + 18
    -- Foil-stamped title on leather (gold for unlocked, soft for locked).
    local title_color = unlocked and P.foil or P.ink_soft
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.print(box.title or box.id, title_x + 2, y + 22)
    love.graphics.setColor(title_color[1], title_color[2], title_color[3], unlocked and 1 or 0.7)
    love.graphics.print(box.title or box.id, title_x, y + 20)

    if unlocked then
        use_small()
        love.graphics.setColor(P.ink_light[1], P.ink_light[2], P.ink_light[3], 0.95)
        love.graphics.print(done .. " / " .. total, title_x, y + h - 38)
        -- Only earned medals render; unearned puzzles stay blank.
        local shown = 0
        for pi = 1, total do
            local p = box.puzzles[pi]
            local earned = progression.puzzle_medal(menu.progress, p.id)
            if earned then
                local dx = title_x + shown * 26
                local dy = y + 70
                M.draw_medal(dx, dy, 22, earned)
                shown = shown + 1
            end
        end
        use_body()
    else
        use_small()
        love.graphics.setColor(P.ink_light[1], P.ink_light[2], P.ink_light[3], 0.85)
        love.graphics.printf(
            "Locked — needs " .. tostring(box.jewel_cost or 0) .. " jewels",
            title_x, y + h / 2 - 12, w - spine_w - 32, "left"
        )
        use_body()
    end

    local oa = menu:press_overlay_alpha_for("box", i)
    if oa > 0 then
        love.graphics.setColor(0, 0, 0, oa)
        love.graphics.rectangle("fill", x, y, w, h, 10, 10)
    end
    love.graphics.pop()
end

-- Deterministic 1..3 placeholder style per book, hashed from box.id so the
-- style is stable across frames/runs but varies between books.
local function book_placeholder_style(box)
    local seed = (box and box.id) or "default"
    local sum = 0
    for k = 1, #seed do sum = sum + seed:byte(k) end
    return (sum % 3) + 1
end

-- Rubber-stamp placeholder: worn red double-ring with "SEALED" inside,
-- slightly rotated so it reads as hand-stamped on the cork backing.
local function draw_placeholder_stamp(x, y, w, h)
    local cx, cy = x + w / 2, y + h / 2
    local r = math.min(w, h) * 0.38
    local ink_r = { P.leather_red_dark[1], P.leather_red_dark[2], P.leather_red_dark[3] }
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(-0.14) -- ~-8 degrees
    love.graphics.setLineWidth(3)
    love.graphics.setColor(ink_r[1], ink_r[2], ink_r[3], 0.85)
    love.graphics.circle("line", 0, 0, r)
    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(ink_r[1], ink_r[2], ink_r[3], 0.7)
    love.graphics.circle("line", 0, 0, r * 0.82)
    use_small()
    local fh = love.graphics.getFont():getHeight()
    print_engraved("SEALED", -r, -fh / 2, r * 2, "center", ink_r, 0.2)
    use_body()
    love.graphics.pop()
end

-- Polaroid placeholder: parchment card covering the cork inner rect, with a
-- darker "photo area" above a cream caption strip reading "No preview".
-- Returns the photo-area rect so callers (stamped polaroid) can overprint.
local function draw_placeholder_polaroid(x, y, w, h)
    love.graphics.setColor(P.parchment[1], P.parchment[2], P.parchment[3], 0.96)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(P.parchment_edge[1], P.parchment_edge[2], P.parchment_edge[3], 0.7)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)

    local inset = 8
    local caption_h = 22
    local px = x + inset
    local py = y + inset
    local pw = w - inset * 2
    local ph = h - inset * 2 - caption_h
    love.graphics.setColor(P.cork_dark[1], P.cork_dark[2], P.cork_dark[3], 0.55)
    love.graphics.rectangle("fill", px, py, pw, ph, 3, 3)

    use_small()
    local fh = love.graphics.getFont():getHeight()
    love.graphics.setColor(P.ink_soft[1], P.ink_soft[2], P.ink_soft[3], 0.55)
    love.graphics.printf("? ? ?", px, py + (ph - fh) / 2, pw, "center")
    use_body()

    return px, py, pw, ph
end

-- Polaroid with a diagonal "UNSOLVED" rubber-stamp overprint across the
-- photo area, framed by two thin stroke lines to sell the stamp look.
local function draw_placeholder_stamped_polaroid(x, y, w, h)
    local px, py, pw, ph = draw_placeholder_polaroid(x, y, w, h)
    local cx, cy = px + pw / 2, py + ph / 2
    local ink_r = { P.leather_red_dark[1], P.leather_red_dark[2], P.leather_red_dark[3] }
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(-0.35) -- ~-20 degrees
    use_small()
    local fh = love.graphics.getFont():getHeight()
    local label_w = math.min(pw, ph) * 1.2
    love.graphics.setLineWidth(2)
    love.graphics.setColor(ink_r[1], ink_r[2], ink_r[3], 0.8)
    love.graphics.line(-label_w / 2, -fh / 2 - 4, label_w / 2, -fh / 2 - 4)
    love.graphics.line(-label_w / 2,  fh / 2 + 4, label_w / 2,  fh / 2 + 4)
    print_engraved("UNSOLVED", -label_w / 2, -fh / 2, label_w, "center", ink_r, 0.25)
    use_body()
    love.graphics.pop()
end

-- Deterministic tilt + tape-corner choice per puzzle, hashed from id.
-- Keeps the scrapbook layout stable across frames/runs: each puzzle has
-- a memorable crooked angle and tape placement.
local function puzzle_tile_style(p)
    local seed = (p and p.id) or "default"
    local sum = 0
    for k = 1, #seed do sum = sum + seed:byte(k) end
    -- Tilt in ~[-0.055, 0.055] rad (~±3.2°). 11 buckets so neighbors
    -- look scattered without any one tile reading as "broken".
    local tilt = ((sum % 11) - 5) / 5 * 0.055
    -- Corner pair: 0 -> top-left + bottom-right, 1 -> top-right + bottom-left.
    local corners = math.floor(sum / 11) % 2
    return tilt, corners
end

-- Parchment photo card: cream rect, hairline edge, soft drop shadow.
-- Drawn at the current transform so callers can tilt it freely.
local function draw_photo_card(x, y, w, h)
    love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.25)
    love.graphics.rectangle("fill", x + 2, y + 3, w, h, 4, 4)
    love.graphics.setColor(P.parchment[1], P.parchment[2], P.parchment[3], 1)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(P.parchment_edge[1], P.parchment_edge[2], P.parchment_edge[3], 0.7)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
end

-- Semi-transparent cream tape strip centered at (cx,cy), rotated.
-- Uses desaturated parchment per the saturation discipline rule.
local function draw_tape_strip(cx, cy, length, angle_rad)
    local tw = length
    local th = 18
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(angle_rad)
    love.graphics.setColor(P.parchment[1], P.parchment[2], P.parchment[3], 0.58)
    love.graphics.rectangle("fill", -tw / 2, -th / 2, tw, th)
    -- Sheen highlight near the top edge.
    love.graphics.setColor(1, 1, 1, 0.22)
    love.graphics.rectangle("fill", -tw / 2 + 1, -th / 2 + 2, tw - 2, 1)
    -- Faint ink lines along the two long edges for depth.
    love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.18)
    love.graphics.setLineWidth(1)
    love.graphics.line(-tw / 2, -th / 2 + 0.5, tw / 2, -th / 2 + 0.5)
    love.graphics.line(-tw / 2,  th / 2 - 0.5, tw / 2,  th / 2 - 0.5)
    love.graphics.pop()
end

-- Draw one pinned-photo level tile on the scrapbook "book page".
-- Every tile is a parchment photo card, taped at two opposing corners.
-- Solved tiles show the cached colored-block thumbnail; unsolved tiles
-- show one of the SEALED / polaroid / stamped-polaroid placeholders.
-- The medal badge sits at the untilted tile corner as a UI indicator
-- rather than something taped to the photo.
local function draw_level_tile(menu, progression, thumbnails, box, i, win_w)
    local p = box.puzzles[i]
    local x, y, w, h = menu:layout_level_tile(i, win_w)
    local earned = progression.puzzle_medal(menu.progress, p.id)
    local completed = progression.is_puzzle_completed(menu.progress, p.id)

    local press_scale = menu:press_scale_for("level", i)
    local cx, cy = x + w / 2, y + h / 2
    push_scale_around(cx, cy, press_scale)

    local tilt, corner_style = puzzle_tile_style(p)

    -- Photo card fills most of the tile with a small inset so tape can
    -- extend slightly past the card edges onto the page.
    local pad = 10
    local cardx = x + pad
    local cardy = y + pad
    local cardw = w - pad * 2
    local cardh = h - pad * 2

    -- Tilt around the tile center so the photo + its tape share one frame.
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(tilt)
    love.graphics.translate(-cx, -cy)

    draw_photo_card(cardx, cardy, cardw, cardh)

    local inner_pad = 6
    local ix = cardx + inner_pad
    local iy = cardy + inner_pad
    local iw = cardw - inner_pad * 2
    local ih = cardh - inner_pad * 2

    local thumb = thumbnails and thumbnails[p.id] or nil
    if thumb and completed then
        local tw, th = thumb:getDimensions()
        local inner = math.min(iw, ih)
        local scale = inner / math.max(tw, th)
        local dw = tw * scale
        local dh = th * scale
        local dx = ix + (iw - dw) / 2
        local dy = iy + (ih - dh) / 2
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(thumb, dx, dy, 0, scale, scale)
    else
        local style = book_placeholder_style(box)
        if style == 1 then
            draw_placeholder_stamp(ix, iy, iw, ih)
        elseif style == 2 then
            draw_placeholder_polaroid(ix, iy, iw, ih)
        else
            draw_placeholder_stamped_polaroid(ix, iy, iw, ih)
        end
    end

    -- Two tape strips at opposing corners, tilted ~30° so they look
    -- hand-placed. Rendered after the photo so tape sits on top.
    local tape_len = 46
    if corner_style == 0 then
        draw_tape_strip(cardx + 6,         cardy + 6,         tape_len, -math.pi / 4)
        draw_tape_strip(cardx + cardw - 6, cardy + cardh - 6, tape_len, -math.pi / 4)
    else
        draw_tape_strip(cardx + cardw - 6, cardy + 6,         tape_len,  math.pi / 4)
        draw_tape_strip(cardx + 6,         cardy + cardh - 6, tape_len,  math.pi / 4)
    end

    love.graphics.pop() -- end tilt

    -- Medal in the untilted tile corner, on top of any tape it might overlap.
    if earned then
        local medal_size = 22
        local mx = x + w - medal_size - 8
        local my = y + 8
        M.draw_medal(mx, my, medal_size, earned)
    end

    local oa = menu:press_overlay_alpha_for("level", i)
    if oa > 0 then
        love.graphics.setColor(0, 0, 0, oa)
        love.graphics.rectangle("fill", x, y, w, h)
    end
    love.graphics.pop() -- end press-scale
end

-- Draw the back button with press-scale applied. Pulled out of draw_menu
-- so the press-down visual wraps the entire button, not just its body.
local function draw_back_button(menu)
    local bx, by, bw, bh = menu:back_button_rect()
    local press_scale = menu:press_scale_for("back", 0)
    local cx, cy = bx + bw / 2, by + bh / 2
    push_scale_around(cx, cy, press_scale)
    wood.draw_panel("plaque", bx, by, bw, bh, 8)
    love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.45)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, bh - 1, 8, 8)
    use_small()
    print_engraved("< Back", bx, by + 14, bw, "center", P.ink_light, 0.4)
    use_body()
    local oa = menu:press_overlay_alpha_for("back", 0)
    if oa > 0 then
        love.graphics.setColor(0, 0, 0, oa)
        love.graphics.rectangle("fill", bx, by, bw, bh, 8, 8)
    end
    love.graphics.pop()
end

-- Draw the menu (boxes or level tiles for the selected box).
-- `display_state` is an optional table { displayed_count, pulse_scale } that
-- the jewel-flight overlay flow uses to show a lagging count + pulse while
-- jewels are en-route from the celebration card to the badge.
function M.draw_menu(menu, progression, thumbnails, win_w, win_h, display_state)
    use_body()
    draw_desk(win_w, win_h)

    local badge_count = menu.progress.jewels
    local pulse_scale = 1
    if display_state ~= nil then
        if display_state.displayed_count ~= nil then
            badge_count = display_state.displayed_count
        end
        if display_state.pulse_scale ~= nil then
            pulse_scale = display_state.pulse_scale
        end
    end

    if menu.screen == "boxes" then
        -- Parchment "library page" backdrop behind the leather books.
        local margin = 16
        local page_y = 110
        local page_h = win_h - page_y - margin
        wood.draw_panel("parchment", margin, page_y, win_w - margin * 2, page_h, 14)

        print_engraved("JewelSort", 0, 22, win_w, "center", P.ink, 0.4)
        use_small()
        love.graphics.setColor(P.ink_soft[1], P.ink_soft[2], P.ink_soft[3], 0.85)
        love.graphics.printf("Select a book", 0, 62, win_w, "center")
        use_body()
        local bx, by = menu:badge_rect(win_w, win_h)
        draw_jewel_badge(bx, by, badge_count, pulse_scale)

        for i = 1, #menu.boxes do
            draw_box_card(menu, progression, menu.boxes[i], i, win_w)
        end
        return
    end

    if menu.screen == "levels" then
        local box = menu:current_box()
        if box == nil then return end

        local margin = 16
        local page_y = 74
        local page_h = win_h - page_y - margin
        wood.draw_panel("parchment", margin, page_y, win_w - margin * 2, page_h, 14)

        draw_back_button(menu)

        print_engraved(box.title or box.id, 0, 22, win_w, "center", P.ink, 0.4)
        local bx, by = menu:badge_rect(win_w, win_h)
        draw_jewel_badge(bx, by, badge_count, pulse_scale)

        for i = 1, #(box.puzzles or {}) do
            draw_level_tile(menu, progression, thumbnails, box, i, win_w)
        end
        return
    end
end

return M
