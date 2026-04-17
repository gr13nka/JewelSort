-- tools/make_samples.lua
-- One-shot generator for example level PNGs. Produces:
--   levels/starter/smile.png  (8x8)
--   levels/starter/heart.png  (12x12)
--
-- Usage (in-game auto-run): main.lua requires this and calls .generate() when
-- levels/ is empty.
--
-- Usage (standalone LÖVE project): `love tools/` works because tools/conf.lua
-- is provided and tools/main.lua calls .generate() on load.
--
-- Writes PNGs via love.image.ImageData:encode, which is save-dir relative;
-- we then copy the bytes into the project's levels/ folder using
-- love.filesystem. When run as part of the real game, the write goes directly
-- into the save directory -- for the standalone runner we copy back via a
-- shell-less approach (love.filesystem.write to "levels/name.png").

local M = {}

local function new_data(w, h)
    return love.image.newImageData(w, h)
end

local function set(data, x, y, r, g, b, a)
    data:setPixel(x, y, r / 255, g / 255, b / 255, (a or 255) / 255)
end

-- Returns the raw PNG bytes (as a string) from an ImageData.
local function encode_png(data)
    local fd = data:encode("png")
    return fd:getString()
end

local function write_png(path, data)
    local bytes = encode_png(data)
    -- love.filesystem.write writes into the save directory; to also appear
    -- inside the mounted game source, we make sure the path is relative.
    local ok, err = love.filesystem.write(path, bytes)
    if not ok then
        print("Failed to write " .. path .. ": " .. tostring(err))
    end
end

-- Simple smile face, 8x8 pixels.
-- Colors: yellow face, black eyes, red smile.
local function make_smile()
    local W, H = 8, 8
    local data = new_data(W, H)
    -- Everything transparent initially.
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            set(data, x, y, 0, 0, 0, 0)
        end
    end

    local Y = { 250, 210, 60 }    -- yellow face
    local K = { 30, 30, 30 }      -- eyes (dark)
    local R = { 220, 60, 70 }     -- mouth (red)

    -- Face: circle-ish 8x8
    local face = {
        "..YYYY..",
        ".YYYYYY.",
        "YYKYYKYY",
        "YYYYYYYY",
        "YYYYYYYY",
        "YRYYYYRY",
        ".YRRRRY.",
        "..YYYY..",
    }
    for y = 1, #face do
        local row = face[y]
        for x = 1, #row do
            local ch = row:sub(x, x)
            if ch == "Y" then
                set(data, x - 1, y - 1, Y[1], Y[2], Y[3], 255)
            elseif ch == "K" then
                set(data, x - 1, y - 1, K[1], K[2], K[3], 255)
            elseif ch == "R" then
                set(data, x - 1, y - 1, R[1], R[2], R[3], 255)
            end
        end
    end
    return data
end

-- Heart 12x12: red body, pink highlight, dark outline.
local function make_heart()
    local W, H = 12, 12
    local data = new_data(W, H)
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            set(data, x, y, 0, 0, 0, 0)
        end
    end
    local R = { 220, 40, 60 }    -- red
    local P = { 255, 180, 200 }  -- pink highlight
    local K = { 80, 10, 20 }     -- dark edge

    local heart = {
        "............",
        "..KKK..KKK..",
        ".KPPRKKRPPK.",
        "KPPRRRRRRPPK",
        "KPRRRRRRRRRK",
        "KRRRRRRRRRRK",
        ".KRRRRRRRRK.",
        "..KRRRRRRK..",
        "...KRRRRK...",
        "....KRRK....",
        ".....KK.....",
        "............",
    }
    for y = 1, #heart do
        local row = heart[y]
        for x = 1, #row do
            local ch = row:sub(x, x)
            if ch == "R" then
                set(data, x - 1, y - 1, R[1], R[2], R[3], 255)
            elseif ch == "P" then
                set(data, x - 1, y - 1, P[1], P[2], P[3], 255)
            elseif ch == "K" then
                set(data, x - 1, y - 1, K[1], K[2], K[3], 255)
            end
        end
    end
    return data
end

function M.generate()
    local smile = make_smile()
    write_png("levels/starter/smile.png", smile)
    local heart = make_heart()
    write_png("levels/starter/heart.png", heart)
end

return M
