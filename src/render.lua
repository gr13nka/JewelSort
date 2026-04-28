-- render.lua
-- Draws the grid, jewels, shelf, hover cluster, win celebration, menu,
-- and the jewel flight overlay (celebration -> counter).
-- The layout module computes rectangles once per frame; draw reads them.

local M = {}

local Level = require("src.level")
local wood = require("src.wood")
local i18n = require("src.i18n")

local P = wood.palette

local FLASH_COLOR = { 0.80, 0.20, 0.18 }

-- Alegreya Bold (Huerta Tipográfica, SIL OFL) — humanist serif text
-- face with full Latin + Cyrillic coverage. Bold weight holds up on
-- painted leather book covers and gold-foil treatments where the
-- Regular weight reads too thin. No Cyrillic fallback is needed —
-- Alegreya covers Russian directly, which sidesteps the love.js
-- --compatibility build's stripped default-font table that previously
-- broke Cyrillic for partial-coverage faces. The Regular static
-- (`Alegreya-Regular.ttf`) sits in `assets/fonts/` alongside this
-- file but is currently unreferenced.
local FONT_PATH = "assets/fonts/Alegreya-Bold.ttf"
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

-- Octagonal bevelled slot tile. Cream-colored art; tinted at draw time
-- with setColor(target * SLOT_TINT) so each cell's slot reads as a
-- darkened version of its target color.
local SLOT_IMAGE_PATH = "assets/jewel_slot_8edges.png"
local _slot_img
local function slot_image()
    if _slot_img == nil then
        _slot_img = love.graphics.newImage(SLOT_IMAGE_PATH)
        _slot_img:setFilter("linear", "linear")
    end
    return _slot_img
end

-- Grey faceted octagonal gem. Tinted at draw time with setColor(jewel_color)
-- so every jewel on screen is this single asset multiplied by its color.
local JEWEL_IMAGE_PATH = "assets/Jewel_8edges.png"
local _jewel_img
local function jewel_image()
    if _jewel_img == nil then
        _jewel_img = love.graphics.newImage(JEWEL_IMAGE_PATH)
        _jewel_img:setFilter("linear", "linear")
    end
    return _jewel_img
end

local BACKGROUND_IMAGE_PATH = "assets/wooden_background.png"
local _background_img
local function background_image()
    if _background_img == nil then
        _background_img = love.graphics.newImage(BACKGROUND_IMAGE_PATH)
        _background_img:setFilter("linear", "linear")
    end
    return _background_img
end

-- Menu (book-select) assets. All hand-painted PNGs are 2x retina
-- (display at half scale on the 540x960 portrait window). Books are
-- keyed by box.id so a future box without an asset falls back cleanly
-- to the procedural leather-cover render in draw_box_card.
local MENU_ASSET_DIR = "assets/jewelsort_assets/png/"
local BOOK_IMAGE_PATHS = {
    starter = MENU_ASSET_DIR .. "book_first_steps.png",
    forest  = MENU_ASSET_DIR .. "book_forest_harvest.png",
    animals = MENU_ASSET_DIR .. "book_forest_friends.png",
    shapes  = MENU_ASSET_DIR .. "book_shapes_symbols.png",
}
local _menu_imgs = {}
local function menu_image(key, path)
    local img = _menu_imgs[key]
    if img ~= nil then return img end
    if path == nil then return nil end
    img = love.graphics.newImage(path)
    img:setFilter("linear", "linear")
    _menu_imgs[key] = img
    return img
end
local function book_image(box_id)
    local path = box_id and BOOK_IMAGE_PATHS[box_id] or nil
    if path == nil then return nil end
    return menu_image("book_" .. box_id, path)
end
local function menu_bg_image()    return menu_image("bg",      MENU_ASSET_DIR .. "bg_wood.png")          end
local function ribbon_image()     return menu_image("ribbon",  MENU_ASSET_DIR .. "bookmark_ribbon.png")  end
local function book_medal_image() return menu_image("medal",   MENU_ASSET_DIR .. "medal_completion.png") end
local function counter_image()    return menu_image("counter", MENU_ASSET_DIR .. "counter_jewels.png")   end
local function book_lock_image()  return menu_image("lock",    MENU_ASSET_DIR .. "book_lock.png")        end

-- Level-select assets (page parchment, polaroid cards, pushpins, etc.).
-- Each card variant has an inner-frame rect (in 1x display coordinates)
-- where the level's pixel-art thumbnail is composited. Values come from
-- assets/jewelsort_assets/README.md (2x asset coords halved for 1x).
local CARD_FRAME = {
    s  = { x = 11, y = 11, w =  88, h =  88 },
    m  = { x = 11, y = 11, w = 128, h = 130 },
    l  = { x = 20, y = 11, w = 230, h = 132 },
    xl = { x = 18, y = 18, w = 244, h = 244 },
}
-- Display sizes (1x). PNG asset is 2x; we draw at 0.5 scale.
local CARD_DISPLAY_SIZE = {
    s  = { w = 110, h = 130 },
    m  = { w = 150, h = 180 },
    l  = { w = 270, h = 168 },
    xl = { w = 280, h = 320 },
}
-- Recommended star size per card variant (README §"Star size is also
-- scaled per card").
local STAR_DISPLAY_SIZE = { s = 30, m = 38, l = 38, xl = 52 }

local function card_image(size, locked)
    local key = "card_" .. size .. (locked and "_locked" or "")
    local path = MENU_ASSET_DIR .. key .. ".png"
    return menu_image(key, path)
end

local function pushpin_image(color)
    local key = "pushpin_" .. color
    local path = MENU_ASSET_DIR .. key .. ".png"
    return menu_image(key, path)
end

local function level_star_image() return menu_image("level_star",  MENU_ASSET_DIR .. "level_star.png")          end
local function page_parchment_image() return menu_image("page_parchment", MENU_ASSET_DIR .. "page_parchment.png") end
local function page_ribbon_image()    return menu_image("page_ribbon",    MENU_ASSET_DIR .. "page_ribbon_burgundy.png") end
local function back_button_image()    return menu_image("back_button",    MENU_ASSET_DIR .. "back_button.png") end

-- Visible gem occupies ~85% of the asset frame (rest is soft shadow halo).
-- Callers pass a desired gem_diameter and the helper scales the asset so
-- the gem matches that diameter; the halo naturally extends past it.
local JEWEL_GEM_FRAC = 0.85

local function draw_jewel_asset(cx, cy, gem_diameter, color, lifted)
    local img = jewel_image()
    local iw, ih = img:getDimensions()
    local footprint = gem_diameter / JEWEL_GEM_FRAC
    local sx = footprint / iw
    local sy = footprint / ih
    local dx = cx - footprint / 2
    local dy = cy - footprint / 2
    if lifted then
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.draw(img, dx + 2, dy + 8, 0, sx, sy)
    end
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.draw(img, dx, dy, 0, sx, sy)
    love.graphics.setColor(1, 1, 1, 1)
end

local MEDAL_COLORS = {
    bronze = { 0.80, 0.50, 0.20 },
    silver = { 0.80, 0.82, 0.86 },
    gold   = { 1.00, 0.84, 0.30 },
}

-- Counter badge visual. Matches counter_jewels.png (200x96, half-scale).
-- Kept centralized so menu:badge_rect matches.
local BADGE_W = 100
local BADGE_H = 48

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
-- `view` (optional) carries zoom + pan offsets so large levels can scale up
-- past fit-to-board. { zoom = 1, pan_x = 0, pan_y = 0 } is the "fit centered"
-- baseline. Pan is clamped here (and written back to the view) so the grid
-- never drifts past `grid_area` edges when it overflows.
-- Returns a table with:
--   grid_area, shelf_area, progress_area, back_button_rect,
--   cell_size, fit_cell, origin_x, origin_y, cols, rows,
--   grid_pixel_w, grid_pixel_h
function M.compute_layout(level, win_w, win_h, view)
    local margin = 16
    local back_button_w = 110
    local back_button_h = 44
    local hint_button_w = 110
    -- Shelf is a 2-row tray. Height is clamped so tall windows don't bloat it.
    local shelf_h = math.min(math.floor(win_h * 0.20), 180)
    -- Puzzle artwork is full-bleed; chrome (back, progress, hint, shelf)
    -- overlays on top. Cells whose target lands behind chrome are
    -- visible only at the chrome edges and unreachable by tap; that
    -- tradeoff is intentional.
    local grid_area = { x = 0, y = 0, w = win_w, h = win_h }
    local back_button_rect = {
        x = margin,
        y = margin,
        w = back_button_w,
        h = back_button_h,
    }
    local hint_button_rect = {
        x = win_w - margin - hint_button_w,
        y = margin,
        w = hint_button_w,
        h = back_button_h,
    }
    -- Progress bar lives in the top header band, between the back and
    -- hint plaques.
    local progress_x = back_button_rect.x + back_button_rect.w + 8
    local progress_area = {
        x = progress_x,
        y = margin,
        w = hint_button_rect.x - progress_x - 8,
        h = back_button_h,
    }
    local shelf_area = {
        x = margin,
        y = win_h - margin - shelf_h,
        w = win_w - margin * 2,
        h = shelf_h,
    }
    local cols = level.width
    local rows = level.height
    local cell_w = grid_area.w / cols
    local cell_h = grid_area.h / rows
    local fit_cell = math.max(1, math.floor(math.min(cell_w, cell_h)))
    local zoom = (view and view.zoom) or 1
    local cell_size = math.max(1, math.floor(fit_cell * zoom))
    local grid_pixel_w = cell_size * cols
    local grid_pixel_h = cell_size * rows
    local fit_ox = grid_area.x + math.floor((grid_area.w - grid_pixel_w) / 2)
    local fit_oy = grid_area.y + math.floor((grid_area.h - grid_pixel_h) / 2)

    -- Pan freedom: clamp only enough to keep one cell of the grid
    -- visible on each axis. Anything tighter (e.g. corner-at-center,
    -- corner-at-edge) feels restrictive when zoomed in because the
    -- player can't push a region of interest into the comfortable
    -- middle of the screen. The trailing edge of the grid stays at
    -- least `cell_size` inside the visible area, which keeps the grid
    -- findable without locking out reachable space.
    local pan_x = (view and view.pan_x) or 0
    local pan_y = (view and view.pan_y) or 0
    local keep = cell_size
    local over_x = (grid_area.w + grid_pixel_w) / 2 - keep
    local over_y = (grid_area.h + grid_pixel_h) / 2 - keep
    if over_x < 0 then over_x = 0 end
    if over_y < 0 then over_y = 0 end
    if pan_x < -over_x then pan_x = -over_x end
    if pan_x >  over_x then pan_x =  over_x end
    if pan_y < -over_y then pan_y = -over_y end
    if pan_y >  over_y then pan_y =  over_y end
    if view ~= nil then
        view.pan_x = pan_x
        view.pan_y = pan_y
    end

    local origin_x = fit_ox + math.floor(pan_x)
    local origin_y = fit_oy + math.floor(pan_y)
    return {
        grid_area = grid_area,
        shelf_area = shelf_area,
        progress_area = progress_area,
        back_button_rect = back_button_rect,
        hint_button_rect = hint_button_rect,
        cell_size = cell_size,
        fit_cell = fit_cell,
        origin_x = origin_x,
        origin_y = origin_y,
        cols = cols,
        rows = rows,
        grid_pixel_w = grid_pixel_w,
        grid_pixel_h = grid_pixel_h,
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

-- Pixel center of grid cell (gx, gy) under the current layout.
function M.grid_cell_pixel(layout, gx, gy)
    local s = layout.cell_size
    return layout.origin_x + gx * s + s / 2,
        layout.origin_y + gy * s + s / 2
end

-- Shelf layout: 3 rows × 8 columns, capacity 24 total.
local SHELF_COLS = 8
local SHELF_ROWS = 3

-- Pixel edge length of one shelf slot. Derived from the shelf area so
-- the 24 slots always fit as a 3×8 grid with ~10% vertical padding.
local function shelf_slot_size(area)
    local slot = math.min(
        math.floor(area.w / SHELF_COLS),
        math.floor(area.h / SHELF_ROWS * 0.9)
    )
    return math.max(slot, 8)
end

-- Return pixel center (cx, cy) and slot edge for shelf slot `index` (1-based).
-- Fills left-to-right, top-to-bottom: 1..8 top row, 9..16 middle, 17..24 bottom.
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

-- Pixel center of shelf slot `index` (1-based) under the current layout.
-- Module-level wrapper so level.lua can resolve shelf origins to pixels
-- when sorting cluster flights by distance from the player's tap.
function M.shelf_slot_pixel(layout, index)
    local cx, cy = shelf_slot_center(layout.shelf_area, index)
    return cx, cy
end

-- Screen coords -> shelf index (1..N) or nil.
-- Taps inside the shelf area but outside the 3×8 slot grid (or past the
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
    local img = background_image()
    local iw, ih = img:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0, 0, win_w / iw, win_h / ih)
end

-- Layer stack per cell (bottom -> top):
--   1. drop shadow beneath the tile
--   2. bright target-color rounded square (the color cue)
--   3. octagonal bevelled slot tinted to a darker version of the target
--      (sits inside the square; the square's corners read as a colored
--      rim around the slot)
--   4. jewel (when settled and not being lifted)
local SLOT_TINT = 0.50
local CELL_CORNER = 0
local function draw_cell(x, y, size, jewel_color, hovering, target_color)
    local cx = x + size / 2
    local cy = y + size / 2
    local corner = size * CELL_CORNER

    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", x, y + 2, size, size, corner, corner)

    if target_color ~= nil then
        love.graphics.setColor(target_color[1], target_color[2], target_color[3], 1)
    else
        love.graphics.setColor(P.plaque)
    end
    love.graphics.rectangle("fill", x, y, size, size, corner, corner)

    local tr, tg, tb
    if target_color ~= nil then
        tr, tg, tb = target_color[1], target_color[2], target_color[3]
    else
        tr, tg, tb = P.plaque[1], P.plaque[2], P.plaque[3]
    end
    love.graphics.setColor(tr * SLOT_TINT, tg * SLOT_TINT, tb * SLOT_TINT, 1)
    local img = slot_image()
    local iw, ih = img:getDimensions()
    love.graphics.draw(img, x, y, 0, size / iw, size / ih)
    love.graphics.setColor(1, 1, 1, 1)

    if jewel_color ~= nil and not hovering then
        draw_jewel_asset(cx, cy, size * 0.68, jewel_color, false)
    end
end

-- Draw just the jewel asset inside a cell, at a scale factor around the
-- cell center. Used for cascade stomp pulse.
local function draw_cell_jewel_scaled(x, y, size, color, scale)
    scale = scale or 1
    local cx = x + size / 2
    local cy = y + size / 2
    draw_jewel_asset(cx, cy, size * 0.68 * scale, color, false)
end

local function draw_jewel(cx, cy, radius, color, lifted)
    draw_jewel_asset(cx, cy, radius * 2, color, lifted)
end

-- Text with a soft darker "engraved" shadow underneath.
local function print_engraved(text, x, y, w, align, ink, shadow_alpha)
    shadow_alpha = shadow_alpha or 0.35
    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.printf(text, x, y + 1, w, align)
    love.graphics.setColor(ink[1], ink[2], ink[3], 1)
    love.graphics.printf(text, x, y, w, align)
end

-- Small engraved pictograms for the zoom/pan controls hint. `size` is
-- the overall icon footprint in pixels; `ink` is the fill color (usually
-- P.ink_light on a dark plaque, P.ink on parchment).
local function draw_wheel_icon(cx, cy, size, ink)
    ink = ink or P.ink_light
    local mouse_w = math.floor(size * 0.55)
    local mouse_h = math.floor(size * 0.85)
    local x = cx - mouse_w / 2
    local y = cy - mouse_h / 2
    -- Shadow.
    love.graphics.setColor(0, 0, 0, 0.30)
    love.graphics.rectangle("fill", x, y + 1, mouse_w, mouse_h, mouse_w / 2, mouse_w / 2)
    -- Mouse silhouette.
    love.graphics.setColor(ink[1], ink[2], ink[3], 1)
    love.graphics.rectangle("fill", x, y, mouse_w, mouse_h, mouse_w / 2, mouse_w / 2)
    -- Scroll wheel — small foil capsule near the top.
    local ww = math.max(2, math.floor(size * 0.10))
    local wh = math.max(3, math.floor(size * 0.20))
    local wx = cx - ww / 2
    local wy = y + math.floor(size * 0.12)
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 1)
    love.graphics.rectangle("fill", wx, wy, ww, wh, ww / 2, ww / 2)
    -- Up/down arrows flanking the wheel to read "scroll".
    local ah = math.max(3, math.floor(size * 0.18))
    local aw = math.max(3, math.floor(size * 0.16))
    love.graphics.setColor(ink[1], ink[2], ink[3], 0.95)
    love.graphics.polygon("fill",
        cx,             y - ah - 2,
        cx - aw / 2,    y - 2,
        cx + aw / 2,    y - 2)
    love.graphics.polygon("fill",
        cx,             y + mouse_h + ah + 2,
        cx - aw / 2,    y + mouse_h + 2,
        cx + aw / 2,    y + mouse_h + 2)
    love.graphics.setColor(1, 1, 1, 1)
end

local function draw_hand_icon(cx, cy, size, ink)
    -- Four-way arrow cross reads as "drag / pan in any direction".
    ink = ink or P.ink_light
    local arm = math.floor(size * 0.40)
    local thick = math.max(2, math.floor(size * 0.10))
    local head = math.max(4, math.floor(size * 0.18))
    local function cross(ox, oy, r, g, b, a)
        love.graphics.setColor(r, g, b, a)
        love.graphics.rectangle("fill", cx - arm + ox, cy - thick / 2 + oy, arm * 2, thick)
        love.graphics.rectangle("fill", cx - thick / 2 + ox, cy - arm + oy, thick, arm * 2)
        love.graphics.polygon("fill",
            cx - arm - head + ox, cy + oy,
            cx - arm + ox,        cy - head + oy,
            cx - arm + ox,        cy + head + oy)
        love.graphics.polygon("fill",
            cx + arm + head + ox, cy + oy,
            cx + arm + ox,        cy - head + oy,
            cx + arm + ox,        cy + head + oy)
        love.graphics.polygon("fill",
            cx + ox,              cy - arm - head + oy,
            cx - head + ox,       cy - arm + oy,
            cx + head + ox,       cy - arm + oy)
        love.graphics.polygon("fill",
            cx + ox,              cy + arm + head + oy,
            cx - head + ox,       cy + arm + oy,
            cx + head + ox,       cy + arm + oy)
    end
    cross(0, 1, 0, 0, 0, 0.30)
    cross(0, 0, ink[1], ink[2], ink[3], 1)
    love.graphics.setColor(1, 1, 1, 1)
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

    -- Shelf geometry is computed early so the hover branch can reference
    -- the slot size when the lift is sourced from the shelf.
    local s = layout.shelf_area
    local shelf_len = #level.shelf
    local capacity = level.shelf_capacity or shelf_len
    local slot = shelf_slot_size(s)
    local r = math.floor(slot * 0.38)

    -- Hover cluster floats at origin positions, preserving cluster shape.
    -- Drawn before the shelf so a lifted grid cluster near the bottom
    -- reads as held *behind* the tray, not floating over it. Lift eases
    -- in from 0 over Level.LIFT_DURATION so the pick-up reads as a
    -- smooth jump rather than a teleport.
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
                -- Occasional twinkle while held aloft. Spawned into the
                -- "behind" layer so the glitter is occluded by the shelf
                -- when it drifts down past the tray top edge.
                if particles ~= nil and math.random() < 12 * dt then
                    particles:spawn(cx, cy2, col, 1, "behind")
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
                    particles:spawn(cx, cy2 + bob, col, 1, "behind")
                end
            end
        end
    end

    -- Behind-shelf particles render between the hover cluster and the
    -- shelf panel so hover-twinkle glitter gets occluded by the tray.
    if particles ~= nil then
        particles:draw("behind")
    end

    -- Shelf: recessed walnut tray with octagonal wood-tinted slots that
    -- mirror the grid slot shape (just neutrally tinted instead of
    -- target-colored, since shelf slots aren't keyed to a color).
    wood.draw_panel("shelf_tray", s.x, s.y, s.w, s.h, 10)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", s.x + 2, s.y + 2, s.w - 4, 3)

    local slot_img = slot_image()
    local siw, sih = slot_img:getDimensions()
    local slot_asset_size = math.floor(slot * 0.9)
    for i = 1, capacity do
        local cx, cy = shelf_slot_center(s, i)
        love.graphics.setColor(P.walnut_dark[1], P.walnut_dark[2], P.walnut_dark[3], 1)
        love.graphics.draw(
            slot_img,
            cx - slot_asset_size / 2,
            cy - slot_asset_size / 2,
            0,
            slot_asset_size / siw,
            slot_asset_size / sih
        )
    end
    love.graphics.setColor(1, 1, 1, 1)

    for i = 1, shelf_len do
        local jewel = level.shelf[i]
        local cx, cy = shelf_slot_center(s, i)
        draw_jewel(cx, cy, r, jewel.color, false)
    end

    if level.flash ~= nil and level.flash.t and level.flash.t > 0 then
        local alpha = math.min(1, level.flash.t)
        love.graphics.setColor(0, 0, 0, alpha * 0.45)
        love.graphics.printf(level.flash.text or "", s.x, s.y + 5, s.w, "center")
        love.graphics.setColor(FLASH_COLOR[1], FLASH_COLOR[2], FLASH_COLOR[3], alpha)
        love.graphics.printf(level.flash.text or "", s.x, s.y + 4, s.w, "center")
    end

    -- Fly animation: every placement. Each jewel runs on its own clock
    -- (pa.t - f.t0) so deposits cascade outward from the tap. Before its
    -- t0, a jewel waits at its source in the lifted pose; then it arcs
    -- (smoothstep) and lands with a squash + ring flash + glitter burst.
    if pa ~= nil then
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

            local local_t = pa.t - (f.t0 or 0)
            if local_t < 0 then
                -- Not launched yet: sit at the source in the lifted pose.
                draw_jewel(fx, fy, base_r, f.color, true)
            else
                local travel_t = math.min(local_t, Level.FLY_DURATION)
                local u = travel_t / Level.FLY_DURATION
                -- Smoothstep eases both ends for a more natural toss.
                local eu = u * u * (3 - 2 * u)
                local landing_scale = 1
                local pt = 0
                local landing = false
                if local_t > Level.FLY_DURATION then
                    landing = true
                    pt = (local_t - Level.FLY_DURATION) / Level.LANDING_PULSE
                    if pt < 0 then pt = 0 elseif pt > 1 then pt = 1 end
                    landing_scale = 1 + (Level.STOMP_PEAK - 1) * math.sin(math.pi * pt)
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
                        local nparts = math.floor(rate * dt + math.random())
                        if nparts > 0 then
                            particles:spawn(cx, cy2, f.color, nparts)
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
        print_engraved(i18n.t("back"), b.x, ly, b.w, "center", P.ink_light, 0.4)
        use_body()
    end

    -- Solve progress: 8 segments of gold foil, housed in the top header
    -- band between the back and hint plaques. Wrapped in its own plaque
    -- so it reads as part of the same chrome row.
    local p = layout.progress_area
    if p ~= nil and p.w > 0 then
        wood.draw_panel("plaque", p.x, p.y, p.w, p.h, 8)
        love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.45)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", p.x + 0.5, p.y + 0.5, p.w - 1, p.h - 1, 8, 8)

        local segments = 8
        local solved, total = level:progress()
        local filled = (total > 0) and math.floor((solved / total) * segments + 0.0001) or 0
        local bar_h = 10
        local bar_w = p.w - 16
        local bar_x = p.x + 8
        local bar_y = p.y + math.floor((p.h - bar_h) / 2)
        local seg_gap = 3
        local seg_w = (bar_w - seg_gap * (segments - 1)) / segments

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
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Persistent controls hint (top-right header band). Tapping it
    -- reopens the zoom/pan tutorial; hit-test lives in main.lua.
    local hb = layout.hint_button_rect
    if hb ~= nil then
        wood.draw_panel("plaque", hb.x, hb.y, hb.w, hb.h, 8)
        love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.45)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", hb.x + 0.5, hb.y + 0.5, hb.w - 1, hb.h - 1, 8, 8)
        -- Three engraved glyphs evenly spaced: wheel, hand, "?".
        local slot_w = hb.w / 3
        local cy = hb.y + hb.h / 2
        local icon_size = math.min(hb.h - 12, 22)
        draw_wheel_icon(hb.x + slot_w * 0.5, cy, icon_size)
        draw_hand_icon(hb.x + slot_w * 1.5, cy, icon_size)
        use_small()
        local fh = love.graphics.getFont():getHeight()
        local qx = hb.x + slot_w * 2
        local qy = cy - fh / 2 - 1
        print_engraved("?", qx, qy, slot_w, "center", P.ink_light, 0.4)
        use_body()
    end
end

-- --- Zoom/pan tutorial overlay -------------------------------------------
-- Simple one-page primer shown the first time a player enters a Forest
-- puzzle. Tapping anywhere on the overlay dismisses it.

local TUT_PW_MAX = 420
local TUT_PW_PAD = 60
local TUT_PH     = 340
local TUT_BTN_W  = 200
local TUT_BTN_H  = 64
local TUT_BTN_BOT = 24

local function tutorial_card_rect(W, H)
    local pw = math.min(W - TUT_PW_PAD, TUT_PW_MAX)
    local ph = TUT_PH
    local px = math.floor((W - pw) / 2)
    local py = math.floor((H - ph) / 2 - 20)
    return px, py, pw, ph
end

-- Public: rect of the "Got it" button on the tutorial card.
function M.tutorial_dismiss_rect(W, H)
    local px, py, pw, ph = tutorial_card_rect(W, H)
    local bw = TUT_BTN_W
    local bh = TUT_BTN_H
    local bx = px + math.floor((pw - bw) / 2)
    local by = py + ph - bh - TUT_BTN_BOT
    return bx, by, bw, bh
end

function M.draw_tutorial_overlay(tutorial, W, H)
    if tutorial == nil or not tutorial.active then return end

    -- Scrim.
    love.graphics.setColor(0, 0, 0, 0.60)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Parchment card.
    local px, py, pw, ph = tutorial_card_rect(W, H)
    love.graphics.setColor(1, 1, 1, 1)
    wood.draw_panel("parchment", px, py, pw, ph, 14)
    love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.35)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", px + 1, py + 1, pw - 2, ph - 2, 14, 14)

    -- Title.
    use_body()
    local title_fh = love.graphics.getFont():getHeight()
    print_engraved(i18n.t("tutorial_title"), px, py + 22, pw, "center", P.ink, 0.4)

    -- Two icon rows. Each row: icon on the left, caption to its right.
    use_small()
    local small_fh = love.graphics.getFont():getHeight()
    local row_y1 = py + 22 + title_fh + 28
    local row_y2 = row_y1 + 72
    local icon_cx = px + 56
    local icon_size = 40
    local text_x = px + 96
    local text_w = pw - (text_x - px) - 20

    draw_wheel_icon(icon_cx, row_y1 + 20, icon_size, P.ink)
    print_engraved(i18n.t("tutorial_wheel"),
        text_x, row_y1 + 20 - small_fh / 2, text_w, "left", P.ink, 0.35)

    draw_hand_icon(icon_cx, row_y2 + 20, icon_size, P.ink)
    print_engraved(i18n.t("tutorial_drag"),
        text_x, row_y2 + 20 - small_fh / 2, text_w, "left", P.ink, 0.35)

    -- "Got it" button — same style as Complete.
    local bx, by, bw, bh = M.tutorial_dismiss_rect(W, H)
    wood.draw_panel("plaque", bx, by, bw, bh, 10)
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.9)
    love.graphics.rectangle("fill", bx + 10, by + 8, bw - 20, 3)
    love.graphics.rectangle("fill", bx + 10, by + bh - 11, bw - 20, 3)
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", bx + 1, by + 1, bw - 2, bh - 2, 10, 10)
    use_body()
    local btn_fh = love.graphics.getFont():getHeight()
    local btn_ly = by + math.floor((bh - btn_fh) / 2) - 1
    local got_it = i18n.t("got_it")
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.printf(got_it, bx, btn_ly + 1, bw, "center")
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 1)
    love.graphics.printf(got_it, bx, btn_ly, bw, "center")
    use_body()
    love.graphics.setColor(1, 1, 1, 1)
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
    love.graphics.printf(i18n.t("complete"), x, ly + 1, w, "center")
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], label_alpha * alpha)
    love.graphics.printf(i18n.t("complete"), x, ly, w, "center")

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
        local solved = i18n.t("solved")
        love.graphics.printf(solved, px, py + 20 + 1, pw, "center")
        love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], title_alpha)
        love.graphics.printf(solved, px, py + 20, pw, "center")
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
                local line = i18n.t_plural("jewel_delta", display_n)
                love.graphics.setColor(0, 0, 0, 0.3)
                love.graphics.printf(line, px, line_y + 1, pw, "center")
                love.graphics.setColor(P.ink_soft[1], P.ink_soft[2], P.ink_soft[3], 1)
                love.graphics.printf(line, px, line_y, pw, "center")
            end
        else
            love.graphics.setColor(0, 0, 0, 0.3)
            local mastered = i18n.t("already_mastered")
            love.graphics.printf(mastered, px, line_y + 1, pw, "center")
            love.graphics.setColor(P.ink_soft[1], P.ink_soft[2], P.ink_soft[3], 1)
            love.graphics.printf(mastered, px, line_y, pw, "center")
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
    love.graphics.printf(i18n.t("resetting"), px, py + 17, pw, "center")
    love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], fade)
    love.graphics.printf(i18n.t("resetting"), px, py + 16, pw, "center")

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

-- Counter widget: counter_jewels.png supplies the wood pill + sapphire,
-- we overlay only the count numeral. `pulse_scale` scales the whole
-- badge from its center; a soft foil-color glow draws behind when
-- pulsed above 1.0 (set by the flight-arrival handler in main.lua).
-- Falls back to the procedural plaque if the asset is missing so the
-- HUD never disappears.
local function draw_jewel_badge(x, y, count, pulse_scale)
    pulse_scale = pulse_scale or 1
    local w, h = BADGE_W, BADGE_H
    local cx, cy = x + w / 2, y + h / 2

    push_scale_around(cx, cy, pulse_scale)

    -- Glow ring behind the badge when pulsing.
    if pulse_scale > 1.001 then
        local glow_t = math.min((pulse_scale - 1) / 0.18, 1)
        love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.35 * glow_t)
        love.graphics.circle("fill", cx, cy, math.max(w, h) * (0.6 + glow_t * 0.5))
    end

    local img = counter_image()
    if img ~= nil then
        local iw, ih = img:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x, y, 0, w / iw, h / ih)
    else
        -- Asset-missing fallback: keep the old procedural plaque + jewel.
        wood.draw_panel("plaque", x, y, w, h, 6)
        love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.9)
        love.graphics.rectangle("fill", x + 6, y + 4, w - 12, 2)
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
        draw_jewel(x + 16, y + h / 2 + 1, 9, BADGE_BLUE, false)
    end

    -- Count numeral. Asset reserves left ~45% for the sapphire; numeral
    -- centers in the right area. Same math drives the fallback path.
    use_small()
    local fh = love.graphics.getFont():getHeight()
    local ty = y + (h - fh) / 2
    local tx = x + math.floor(w * 0.45)
    local tw = w - math.floor(w * 0.45) - 8
    print_engraved(tostring(count), tx, ty, tw, "center", P.ink_light, 0.4)
    use_body()

    love.graphics.pop()
end

-- Procedural book fallback used when no PNG is mapped for a box.id.
-- Keeps the old leather-cover look so future books without art still
-- render reasonably; not the path the four shipped books take.
local function draw_box_card_procedural(box, i, x, y, w, h, unlocked)
    local LEATHER = { "leather_red", "leather_green", "leather_blue" }
    local kind = unlocked and LEATHER[((i - 1) % 3) + 1] or "locked"
    wood.draw_panel(kind, x, y, w, h, 10)
    local spine_w = 36
    wood.draw_panel("locked", x, y, spine_w, h, 10)
    love.graphics.setColor(P.foil[1], P.foil[2], P.foil[3], 0.9)
    love.graphics.rectangle("fill", x, y + 18, spine_w, 3)
    love.graphics.rectangle("fill", x, y + h - 22, spine_w, 3)
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2, 10, 10)
end

-- Draw one book tile for a box card. The PNG (book_<box.id>.png) carries
-- the painted leather cover, gold spine, embossed plate, and pixel-art
-- emblem; we overlay state (ribbon/medal/lock) and dynamic text.
local function draw_box_card(menu, progression, box, i, win_w)
    local x, y, w, h = menu:layout_box_card(i, win_w)
    local unlocked = progression.is_box_unlocked(menu.progress, box)
    local done = progression.box_completed_count(menu.progress, box)
    local total = box.puzzles and #box.puzzles or 0
    local completed = unlocked and total > 0 and done >= total
    local in_progress = unlocked and done > 0 and not completed

    -- Hover: cubic ease-out for a snappy rise/fall. 0 when locked or
    -- empty (hit_press_target rejects those, so hover_t stays at 0).
    local hover_raw = menu:hover_t_for("box", i)
    local hover_t = 1 - (1 - hover_raw) ^ 3
    local lift = 6 * hover_t

    -- Lift the whole card up by `lift`. All subsequent x/y math (cover,
    -- overlays, text, press scrim) uses this shifted y.
    y = y - lift

    local press_scale = menu:press_scale_for("box", i)
    local cx, cy = x + w / 2, y + h / 2
    push_scale_around(cx, cy, press_scale)

    -- 1. Cover. Image is fit-to-rect so card_h tracks asset aspect
    --    (LAYOUT.box_card_height = 173 for the 1040x360 source).
    local img = book_image(box.id)
    if img ~= nil then
        local iw, ih = img:getDimensions()
        local sx, sy = w / iw, h / ih
        if unlocked then
            love.graphics.setColor(1, 1, 1, 1)
        else
            -- Warm dark tint per asset README — dims the cover and
            -- desaturates the emblem in one multiply.
            love.graphics.setColor(0.40, 0.32, 0.22, 1.0)
        end
        love.graphics.draw(img, x, y, 0, sx, sy)
        love.graphics.setColor(1, 1, 1, 1)
    else
        draw_box_card_procedural(box, i, x, y, w, h, unlocked)
    end

    -- Hover highlight: very subtle warm additive glow. Sits between
    -- cover and state overlays so the lock/medal/ribbon stay vivid.
    if hover_t > 0.01 then
        love.graphics.setBlendMode("add", "alphamultiply")
        love.graphics.setColor(0.18, 0.15, 0.08, 0.10 * hover_t)
        love.graphics.rectangle("fill", x, y, w, h, 10, 10)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- 2. State overlay (mutually exclusive: locked > completed > in-progress).
    if not unlocked then
        local lock = book_lock_image()
        if lock ~= nil then
            local lw, lh = lock:getDimensions()
            -- Half-scale per asset (2x retina source); centered on cover.
            local s = 0.5
            local dw, dh = lw * s, lh * s
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(lock, x + w / 2 - dw / 2, y + h / 2 - dh / 2, 0, s, s)
        end
    elseif completed then
        local medal = book_medal_image()
        if medal ~= nil then
            local mw, mh = medal:getDimensions()
            local s = 0.5
            local dw, dh = mw * s, mh * s
            -- Top-right of the book; rotation is baked into the asset.
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(medal, x + w - dw - 8, y - 6, 0, s, s)
        end
    elseif in_progress then
        local ribbon = ribbon_image()
        if ribbon ~= nil then
            local rw, rh = ribbon:getDimensions()
            local s = 0.5
            local dw = rw * s
            -- Hangs off the top of the book near the right edge.
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(ribbon, x + w - dw - 24, y - 8, 0, s, s)
        end
    end

    -- 3. Dynamic text. The book's parchment plate occupies ~the left
    --    third; title + status sit on the empty right side.
    local title_x = x + math.floor(w * 0.34)
    local title_w = w - (title_x - x) - 16
    local title_color = unlocked and P.foil or P.ink_soft
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.printf(box.title or box.id, title_x + 2, y + 26, title_w, "left")
    love.graphics.setColor(title_color[1], title_color[2], title_color[3], unlocked and 1 or 0.7)
    love.graphics.printf(box.title or box.id, title_x, y + 24, title_w, "left")

    use_small()
    if unlocked then
        love.graphics.setColor(P.ink_light[1], P.ink_light[2], P.ink_light[3], 0.95)
        love.graphics.printf(done .. " / " .. total, title_x, y + 62, title_w, "left")
    else
        love.graphics.setColor(P.ink_light[1], P.ink_light[2], P.ink_light[3], 0.85)
        love.graphics.printf(
            i18n.t_plural("locked_needs", box.jewel_cost or 0),
            title_x, y + h - 50, title_w, "left"
        )
    end
    use_body()

    -- 4. Press scrim, drawn flat over the whole card.
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
    print_engraved(i18n.t("sealed"), -r, -fh / 2, r * 2, "center", ink_r, 0.2)
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
    love.graphics.printf(i18n.t("no_preview"), px, py + (ph - fh) / 2, pw, "center")
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
    print_engraved(i18n.t("unsolved"), -label_w / 2, -fh / 2, label_w, "center", ink_r, 0.25)
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

-- Draw one pinned-polaroid level card on the parchment book page.
-- Card variant (S/M/L/XL) is determined by menu.lua from the level's
-- bbox dims; the inner pixel-art thumbnail is composited into the
-- card's frame rect (CARD_FRAME). Pushpin sits at the top center;
-- a gold rosette star overlays the top-right corner for completed
-- levels. Unlocked cards sway gently around their pushpin pivot to
-- advertise tappability.
local function draw_level_tile(menu, progression, thumbnails, box, i, win_w)
    local p = box.puzzles[i]
    local x, y, w, h = menu:layout_level_tile(i, win_w)
    if w <= 0 or h <= 0 then return end
    local v = menu:level_visuals(menu.selected_box, i)
    if v == nil then v = { size = "m", pushpin = "red", rotation = 0,
                           sway_phase = 0, sway_speed = 1.4 } end
    local size = v.size
    local frame = CARD_FRAME[size] or CARD_FRAME.m

    local completed = progression.is_puzzle_completed(menu.progress, p.id)
    -- Unsolved puzzles wear the "?" locked-card asset so the inner pixel-art
    -- preview doesn't spoil the picture. Tapping is not gated by `locked`
    -- (only per-box gating exists in menu.lua), so a "locked" card still
    -- accepts taps and starts the puzzle.
    local locked = not completed

    -- Press-scale wrap (so press feedback survives sway).
    local press_scale = menu:press_scale_for("level", i)
    local cx, cy = x + w / 2, y + h / 2
    push_scale_around(cx, cy, press_scale)

    -- Sway: gentle rotation + vertical bob on a per-card phase, pivoting
    -- near the pushpin (top 20% of the card) so the polaroid reads as
    -- hanging from a pin. Locked cards skip motion (per asset README).
    local rot = v.rotation or 0
    local bob = 0
    if not locked then
        local t = (love and love.timer and love.timer.getTime() or 0)
        rot = rot + math.sin(t * v.sway_speed + v.sway_phase) * 0.009
        bob = math.sin(t * v.sway_speed + v.sway_phase) * 1.5
    end

    -- Pivot: top-center of card (where the pushpin lives).
    local pivot_x = x + w / 2
    local pivot_y = y + h * 0.2
    love.graphics.push()
    love.graphics.translate(pivot_x, pivot_y + bob)
    love.graphics.rotate(rot)
    love.graphics.translate(-pivot_x, -pivot_y)

    -- Card body (PNG asset @ 0.5x). The asset's painted shadow already
    -- sits inside its bounds, so no extra drop-shadow draw needed.
    local card_img = card_image(size, locked)
    if card_img ~= nil then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(card_img, x, y, 0, 0.5, 0.5)
    else
        -- Fallback: cream rectangle so the card never disappears if the
        -- asset is missing during development.
        love.graphics.setColor(0.95, 0.92, 0.84, 1)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    end

    -- Inner pixel-art thumbnail (only on unlocked cards — locked variants
    -- bake the "?" into the asset).
    if not locked then
        local thumb = thumbnails and thumbnails[p.id] or nil
        if thumb ~= nil then
            -- Frame coords are in 1x display space relative to card top-left.
            local fx = x + frame.x
            local fy = y + frame.y
            local fw = frame.w
            local fh = frame.h
            local tw, th = thumb:getDimensions()
            -- Fit-largest-side, integer-snap so puzzle pixels stay square.
            local scale = math.min(fw / tw, fh / th)
            if scale <= 0 then scale = 1 end
            local dw = tw * scale
            local dh = th * scale
            local dx = fx + (fw - dw) / 2
            local dy = fy + (fh - dh) / 2
            local prev_min, prev_mag = thumb:getFilter()
            thumb:setFilter("nearest", "nearest")
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(thumb, dx, dy, 0, scale, scale)
            thumb:setFilter(prev_min, prev_mag)
        end
    end

    -- Completion star — only for unlocked + completed.
    if completed and not locked then
        local star = level_star_image()
        if star ~= nil then
            local target = STAR_DISPLAY_SIZE[size] or 38
            local sw, sh = star:getDimensions()
            local s = target / math.max(sw, sh)
            -- Top-right corner, slightly overlapping the card edge.
            local sx = x + w - target * 0.7
            local sy = y - target * 0.25
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(star, sx, sy, math.rad(15), s, s, sw / 2, sh / 2)
        end
    end

    love.graphics.pop() -- end sway transform

    -- Pushpin sits OUTSIDE the sway transform so it reads as fixed to
    -- the page; the card swings under it. 22x22 display, centered above
    -- the card top edge.
    local pin = pushpin_image(v.pushpin)
    if pin ~= nil then
        local pw, ph = pin:getDimensions()
        local pin_w, pin_h = 22, 22
        local pin_sx = pin_w / pw
        local pin_sy = pin_h / ph
        local px = x + w / 2 - pin_w / 2
        local py = y - pin_h * 0.35
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(pin, px, py, 0, pin_sx, pin_sy)
    end

    -- Press scrim (drawn after sway/pop, in card-local rect).
    local oa = menu:press_overlay_alpha_for("level", i)
    if oa > 0 then
        love.graphics.setColor(0, 0, 0, oa)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)
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
    -- back_button.png is 180x80 (2x); draw at 0.5 -> 90x40 to match
    -- menu.LAYOUT.back_w/back_h. Falls back to a procedural plaque if
    -- the asset is missing.
    local img = back_button_image()
    if img ~= nil then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, bx, by, 0, 0.5, 0.5)
    else
        wood.draw_panel("plaque", bx, by, bw, bh, 8)
        love.graphics.setColor(P.ink[1], P.ink[2], P.ink[3], 0.45)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", bx + 0.5, by + 0.5, bw - 1, bh - 1, 8, 8)
    end
    use_small()
    -- Vertically centre "Back" / "Назад" inside the wooden pill. Small
    -- font is 22 px tall in our setup; ~y+10 looks correct for a 40 px
    -- pill (asset baseline sits a touch above geometric center).
    print_engraved(i18n.t("back"), bx, by + 8, bw, "center", P.ink_light, 0.4)
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
    -- bg_wood.png is the menu's full-screen background per the asset
    -- README. Falls through to draw_desk if the asset is missing so the
    -- screen never goes blank.
    local bg = menu_bg_image()
    if bg ~= nil then
        local iw, ih = bg:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(bg, 0, 0, 0, win_w / iw, win_h / ih)
    else
        draw_desk(win_w, win_h)
    end

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
        -- bg_wood already paints the full backdrop; books are designed
        -- to sit directly on the wood (no parchment "page" between).
        print_engraved("JewelSort", 0, 22, win_w, "center", P.ink, 0.4)
        use_small()
        love.graphics.setColor(P.ink_soft[1], P.ink_soft[2], P.ink_soft[3], 0.85)
        love.graphics.printf(i18n.t("select_book"), 0, 62, win_w, "center")
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

        -- Parchment "page" of the open book — PNG asset preferred, with
        -- procedural fallback so the screen never goes blank.
        local px, py, pw, ph = menu:page_rect(win_w, win_h)
        local parchment = page_parchment_image()
        if parchment ~= nil then
            local iw, ih = parchment:getDimensions()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(parchment, px, py, 0, pw / iw, ph / ih)
        else
            wood.draw_panel("parchment", px, py, pw, ph, 14)
        end

        -- Burgundy ribbon hanging from the top edge of the page.
        local ribbon = page_ribbon_image()
        if ribbon ~= nil then
            local rw_disp, rh_disp = 32, 60
            local riw, rih = ribbon:getDimensions()
            local rsx = rw_disp / riw
            local rsy = rh_disp / rih
            local rx = px + pw - rw_disp - 36
            local ry = py - 8
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(ribbon, rx, ry, 0, rsx, rsy)
        end

        draw_back_button(menu)

        print_engraved(box.title or box.id, 0, 22, win_w, "center", P.ink, 0.4)
        local bx, by = menu:badge_rect(win_w, win_h)
        draw_jewel_badge(bx, by, badge_count, pulse_scale)

        -- Clip cards to the parchment-page rect so scrolling content
        -- doesn't bleed onto the wood background or the header strip.
        love.graphics.setScissor(px, py, pw, ph)
        for i = 1, #(box.puzzles or {}) do
            draw_level_tile(menu, progression, thumbnails, box, i, win_w)
        end
        love.graphics.setScissor()
        return
    end
end

return M
