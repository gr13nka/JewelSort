-- wood.lua
-- Procedural wooden panel + parchment renderer. Bakes each unique-sized
-- surface into a Canvas once at first use and caches it forever (windows
-- are non-resizable, so the cache is bounded in practice). All drawing
-- uses LÖVE primitives — no PNG assets, no FFI, no goto, no recursion.
--
-- Public API:
--   wood.palette                         -- named colors
--   wood.panel(kind, w, h)               -- returns a Canvas, baking if needed
--   wood.draw_panel(kind, x, y, w, h, r) -- draws a panel at (x,y), optionally
--                                           clipped to a rounded rect of radius r
--   wood.invalidate()                    -- drops the cache (used if we ever
--                                           need to force a rebake)
--
-- Available kinds: "desk" | "plaque" | "plaque_light" | "cork" | "shelf_tray"
--                  | "parchment" | "board"

local M = {}

M.palette = {
    -- Backdrop: warm pine "desk"
    desk        = { 0.71, 0.54, 0.35 },
    desk_dark   = { 0.48, 0.33, 0.18 },
    desk_light  = { 0.84, 0.67, 0.45 },

    -- Mid-tone oak: used for cards / "books" / cells frame
    plaque      = { 0.58, 0.40, 0.24 },
    plaque_dark = { 0.36, 0.23, 0.12 },
    plaque_light= { 0.76, 0.56, 0.33 },

    -- Dark walnut: used for shelf tray (the recessed channel)
    walnut      = { 0.32, 0.20, 0.10 },
    walnut_dark = { 0.18, 0.10, 0.05 },
    walnut_light= { 0.50, 0.33, 0.18 },

    -- Stained "locked" wood (grayer / cooler)
    locked      = { 0.40, 0.33, 0.25 },
    locked_dark = { 0.22, 0.18, 0.13 },
    locked_light= { 0.55, 0.47, 0.37 },

    -- Cork-board tile (level tiles)
    cork        = { 0.66, 0.49, 0.29 },
    cork_dark   = { 0.44, 0.30, 0.16 },
    cork_light  = { 0.82, 0.65, 0.42 },

    -- Parchment / page
    parchment       = { 0.92, 0.84, 0.66 },
    parchment_edge  = { 0.66, 0.54, 0.36 },
    parchment_speck = { 0.74, 0.60, 0.42 },

    -- Ink (text / lines engraved on wood)
    ink        = { 0.16, 0.09, 0.04 },
    ink_soft   = { 0.32, 0.22, 0.13 },
    ink_light  = { 0.95, 0.88, 0.72 }, -- for text on dark wood

    -- Leather book covers: pale, warm, muted; used on the box-select page.
    leather_red       = { 0.72, 0.40, 0.38 },
    leather_red_dark  = { 0.45, 0.20, 0.20 },
    leather_red_light = { 0.86, 0.58, 0.55 },
    leather_green     = { 0.48, 0.60, 0.42 },
    leather_green_dark= { 0.25, 0.36, 0.22 },
    leather_green_light= { 0.66, 0.78, 0.58 },
    leather_blue      = { 0.44, 0.55, 0.70 },
    leather_blue_dark = { 0.22, 0.30, 0.44 },
    leather_blue_light = { 0.64, 0.74, 0.86 },

    -- Foil gilding for leather-cover titles.
    foil       = { 0.94, 0.82, 0.48 },
}

-- --- cache ---------------------------------------------------------------

local cache = {}

local function cache_key(kind, w, h)
    return kind .. ":" .. w .. "x" .. h
end

function M.invalidate()
    cache = {}
end

-- --- palette lookup ------------------------------------------------------

-- Return (base, dark, light) tone triple for a wood kind.
local function tones(kind)
    local p = M.palette
    if kind == "desk"        then return p.desk,   p.desk_dark,   p.desk_light   end
    if kind == "plaque"      then return p.plaque, p.plaque_dark, p.plaque_light end
    if kind == "plaque_light"then return p.plaque_light, p.plaque, p.desk_light  end
    if kind == "cork"        then return p.cork,   p.cork_dark,   p.cork_light   end
    if kind == "shelf_tray"  then return p.walnut, p.walnut_dark, p.walnut_light end
    if kind == "board"       then return p.walnut, p.walnut_dark, p.plaque       end
    if kind == "locked"      then return p.locked, p.locked_dark, p.locked_light end
    if kind == "leather_red"   then return p.leather_red,   p.leather_red_dark,   p.leather_red_light   end
    if kind == "leather_green" then return p.leather_green, p.leather_green_dark, p.leather_green_light end
    if kind == "leather_blue"  then return p.leather_blue,  p.leather_blue_dark,  p.leather_blue_light  end
    return p.desk, p.desk_dark, p.desk_light
end

-- Test whether a kind is leather — leather bakes differently (no long horizontal grain).
local function is_leather(kind)
    return kind == "leather_red" or kind == "leather_green" or kind == "leather_blue"
end

-- --- bakers --------------------------------------------------------------

-- Deterministic seed per kind so the same panel kind looks like the same
-- kind of wood no matter its size.
local function seed_for(kind)
    local sum = 0
    for i = 1, #kind do sum = sum + string.byte(kind, i) * i end
    return 1000 + sum
end

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Draw wobbly horizontal "grain" streaks. Each streak is a chain of short
-- line segments with noise-driven vertical wobble — convincing grain at a
-- fraction of the cost of per-pixel work.
local function draw_grain(w, h, base, dark, light, rng, seed)
    love.graphics.setLineWidth(1)
    local streak_count = math.max(40, math.floor(h * 0.9))
    for i = 1, streak_count do
        local y = rng:random() * h
        local bias = (rng:random() - 0.5) * 1.2 -- negative => darker, positive => lighter
        local target = bias >= 0 and light or dark
        local t = math.abs(bias)
        local r = lerp(base[1], target[1], t * 0.85)
        local g = lerp(base[2], target[2], t * 0.85)
        local b = lerp(base[3], target[3], t * 0.85)
        local a = 0.18 + rng:random() * 0.22
        love.graphics.setColor(r, g, b, a)
        local segs = 18
        local px, py = 0, y
        for s = 1, segs do
            local nx = (s / segs) * w
            local wobble = love.math.noise(nx * 0.012, y * 0.05, seed * 0.01) * 3.5
            local ny = y + wobble - 1.75
            love.graphics.line(px, py, nx, ny)
            px, py = nx, ny
        end
    end
end

local function bake_wood(w, h, kind)
    local base, dark, light = tones(kind)
    local seed = seed_for(kind)
    local canvas = love.graphics.newCanvas(w, h)
    local rng = love.math.newRandomGenerator(seed)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.setBlendMode("alpha")
    love.graphics.clear(base[1], base[2], base[3], 1)

    if is_leather(kind) then
        -- Leather pebbling: many tiny speckles with a slight shade variation,
        -- no long grain streaks. Reads as a soft pebbled hide.
        local specks = math.floor(w * h / 40)
        for _ = 1, specks do
            local x = rng:random() * w
            local y = rng:random() * h
            local mix = (rng:random() - 0.5) * 1.0
            local target = mix >= 0 and light or dark
            local t = math.abs(mix)
            local r = lerp(base[1], target[1], t * 0.5)
            local g = lerp(base[2], target[2], t * 0.5)
            local b = lerp(base[3], target[3], t * 0.5)
            love.graphics.setColor(r, g, b, 0.35)
            love.graphics.rectangle("fill", x, y, 1, 1)
        end
    else
        draw_grain(w, h, base, dark, light, rng, seed)
    end

    -- Inner bevel: darker line just inside the edge + a lighter highlight
    -- one pixel in from that. Reads as "slightly recessed plank".
    love.graphics.setLineWidth(1)
    love.graphics.setColor(dark[1], dark[2], dark[3], 0.55)
    love.graphics.rectangle("line", 0.5, 0.5, w - 1, h - 1)
    love.graphics.setColor(light[1], light[2], light[3], 0.25)
    love.graphics.rectangle("line", 1.5, 1.5, w - 3, h - 3)

    love.graphics.pop()
    return canvas
end

local function bake_parchment(w, h)
    local p = M.palette
    local canvas = love.graphics.newCanvas(w, h)
    local rng = love.math.newRandomGenerator(seed_for("parchment"))
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.setBlendMode("alpha")
    love.graphics.clear(p.parchment[1], p.parchment[2], p.parchment[3], 1)

    -- Age specks
    local specks = math.floor(w * h / 600)
    for _ = 1, specks do
        local x = rng:random() * w
        local y = rng:random() * h
        local s = rng:random() < 0.9 and 1 or 2
        local shade = (rng:random() - 0.5) * 0.25
        local r = clamp01(p.parchment_speck[1] + shade)
        local g = clamp01(p.parchment_speck[2] + shade)
        local b = clamp01(p.parchment_speck[3] + shade)
        love.graphics.setColor(r, g, b, 0.35 + rng:random() * 0.25)
        love.graphics.rectangle("fill", x, y, s, s)
    end

    -- Soft edge darkening (vignette-ish) via concentric inset rectangles.
    -- Drawn as four explicit line segments per inset so the bottom edge
    -- renders reliably — rectangle("line", ...) at sub-pixel coordinates
    -- on a canvas can drop the last-row pixel once it's composited
    -- through draw_panel's rounded-rect stencil.
    love.graphics.setLineWidth(1)
    for i = 0, 3 do
        local a = 0.10 + i * 0.05
        love.graphics.setColor(p.parchment_edge[1], p.parchment_edge[2],
                               p.parchment_edge[3], a)
        local x1 = 0.5 + i
        local y1 = 0.5 + i
        local x2 = w - 0.5 - i
        local y2 = h - 0.5 - i
        love.graphics.line(x1, y1, x2, y1)
        love.graphics.line(x1, y2, x2, y2)
        love.graphics.line(x1, y1, x1, y2)
        love.graphics.line(x2, y1, x2, y2)
    end

    love.graphics.pop()
    return canvas
end

-- --- public panel getter -------------------------------------------------

function M.panel(kind, w, h)
    w = math.max(8, math.floor(w))
    h = math.max(8, math.floor(h))
    local k = cache_key(kind, w, h)
    local hit = cache[k]
    if hit ~= nil then return hit end
    local canvas
    if kind == "parchment" then
        canvas = bake_parchment(w, h)
    else
        canvas = bake_wood(w, h, kind)
    end
    cache[k] = canvas
    return canvas
end

-- Draw a panel rect, optionally clipped to rounded corners. The clip is
-- done at draw time via stencil so we can reuse a rectangular baked canvas
-- at many different rounding radii.
function M.draw_panel(kind, x, y, w, h, radius)
    local canvas = M.panel(kind, w, h)
    if radius and radius > 0 then
        love.graphics.stencil(function()
            love.graphics.rectangle("fill", x, y, w, h, radius, radius)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, x, y)
        love.graphics.setStencilTest()
    else
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, x, y)
    end
end

return M
