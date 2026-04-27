-- particles.lua
-- Lightweight particle list. Hand-rolled (not LÖVE's ParticleSystem) so
-- every field is inspectable and the module has zero dependencies beyond
-- love.graphics — important under love.js / Fengari.
--
-- Two kinds of particles share one list:
--   "sparkle"  - glow + white core + twinkle cross, biased upward. Used
--                for jewel hover / fly / count-up glitter.
--   "confetti" - flat rotating rectangle under gravity with a sideways
--                wobble. Used for the win-celebration cannon bursts.

local M = {}
M.__index = M

local function rand()
    if love and love.math and love.math.random then
        return love.math.random()
    end
    return math.random()
end

function M.new()
    return setmetatable({ list = {} }, M)
end

-- Spawn `count` sparkles originating at (x,y) with the given jewel color.
-- Spread is biased slightly upward so the glitter reads as floating /
-- lingering rather than falling off.
-- `layer` ("above" / "behind") decides whether this batch renders on top
-- of the shelf chrome or under it. Hover-twinkles use "behind" so the
-- glitter doesn't float over the shelf tray. Default is "above".
function M:spawn(x, y, color, count, layer)
    count = count or 1
    layer = layer or "above"
    for _ = 1, count do
        local ang = rand() * math.pi * 2
        local spd = 18 + rand() * 55
        self.list[#self.list + 1] = {
            kind = "sparkle",
            x = x + (rand() - 0.5) * 6,
            y = y + (rand() - 0.5) * 6,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd - 30,
            life = 0,
            max_life = 0.28 + rand() * 0.32,
            size = 1.4 + rand() * 1.6,
            color = color,
            layer = layer,
        }
    end
end

-- Spawn `count` paper-confetti rectangles from (x,y) with initial
-- velocity biased by (vx0, vy0) inside a `spread_rad` half-angle cone.
-- Colors cycle through the passed palette (one color per particle, so
-- the burst reads as multi-colored even on a puzzle with few targets).
function M:spawn_confetti(x, y, vx0, vy0, spread_rad, palette, count)
    count = count or 1
    local base_ang = math.atan2(vy0, vx0)
    local base_spd = math.sqrt(vx0 * vx0 + vy0 * vy0)
    for i = 1, count do
        -- Sample an angle in the cone + a speed jitter so the cannon
        -- fan isn't a hard-edged wedge.
        local ang = base_ang + (rand() - 0.5) * 2 * spread_rad
        local spd = base_spd * (0.70 + rand() * 0.55)
        local color = palette[((i - 1) % #palette) + 1]
        self.list[#self.list + 1] = {
            kind = "confetti",
            x = x,
            y = y,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd,
            rot = rand() * math.pi * 2,
            vrot = (rand() - 0.5) * 12,      -- ~[-6, 6] rad/s
            w = 7 + rand() * 3,              -- ~7..10 px long
            h = 3 + rand() * 2,              -- ~3..5 px tall
            life = 0,
            max_life = 1.8 + rand() * 1.7,   -- 1.8..3.5 s
            color = { color[1], color[2], color[3] },
            wobble_phase = rand() * math.pi * 2,
            wobble_amp = 18 + rand() * 14,   -- px/s sideways sway
            layer = "above",
        }
    end
end

function M:update(dt)
    local list = self.list
    local n = #list
    local write = 0
    for i = 1, n do
        local p = list[i]
        p.life = p.life + dt
        if p.life < p.max_life then
            if p.kind == "confetti" then
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                -- Heavier gravity than sparkles so pieces actually fall
                -- instead of drifting off the top of the screen.
                p.vy = p.vy + 480 * dt
                -- Mild horizontal drag + sideways sway (per-particle
                -- phase so pieces don't flutter in sync).
                local d = 1 - 0.6 * dt
                if d < 0 then d = 0 end
                p.vx = p.vx * d
                p.wobble_phase = p.wobble_phase + dt * 4
                p.x = p.x + math.cos(p.wobble_phase) * p.wobble_amp * dt
                p.rot = p.rot + p.vrot * dt
            else
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                -- Mild gravity + linear damping.
                p.vy = p.vy + 90 * dt
                local d = 1 - 2.2 * dt
                if d < 0 then d = 0 end
                p.vx = p.vx * d
                p.vy = p.vy * d
            end
            write = write + 1
            list[write] = p
        end
    end
    for i = n, write + 1, -1 do
        list[i] = nil
    end
end

-- `layer` ("above" / "behind") filters which particles to draw. Default
-- is "above" so existing call sites keep their behavior; the renderer
-- inserts an extra `:draw("behind")` pass before the shelf so hover
-- twinkles don't bleed over the tray.
function M:draw(layer)
    layer = layer or "above"
    local prev_lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(1)
    for i = 1, #self.list do
        local p = self.list[i]
        if (p.layer or "above") ~= layer then
            -- skip
        elseif p.kind == "confetti" then
            local u = p.life / p.max_life
            -- Hold full alpha until the last 25% of life, then fade.
            local alpha = 1
            if u > 0.75 then alpha = 1 - (u - 0.75) / 0.25 end
            love.graphics.push()
            love.graphics.translate(p.x, p.y)
            love.graphics.rotate(p.rot)
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
            love.graphics.rectangle("fill", -p.w / 2, -p.h / 2, p.w, p.h)
            love.graphics.pop()
        else
            local u = p.life / p.max_life
            local alpha = 1 - u
            -- Jewel-tinted glow halo (larger, softer).
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha * 0.55)
            love.graphics.circle("fill", p.x, p.y, p.size * 2.1)
            -- Bright white core.
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.circle("fill", p.x, p.y, p.size * (1 - u * 0.6))
            -- Twinkle cross — shrinks as particle fades.
            local s = p.size * 2.4 * (1 - u * 0.5)
            love.graphics.setColor(1, 1, 1, alpha * 0.85)
            love.graphics.line(p.x - s, p.y, p.x + s, p.y)
            love.graphics.line(p.x, p.y - s, p.x, p.y + s)
        end
    end
    love.graphics.setLineWidth(prev_lw)
end

function M:clear()
    self.list = {}
end

return M
