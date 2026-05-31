-- tools/make_card_thumbs.lua
--
-- Render each puzzle in levels/boxes.lua as a static polaroid card —
-- body asset + inner pixel-art preview + pushpin — and save it to
-- assets/card_thumbs/<safe_id>.png. The Lovkit2d editor uses these
-- PNGs as drag sources when authoring screens/<book_id>.ui.json
-- layouts (see CLAUDE.md → "Authoring book layouts").
--
-- Run with:  love . --make-card-thumbs
-- main.lua handles the flag, runs us, then quits.
--
-- Why standalone: the in-game card draw uses sway + press-scale + the
-- completion star, none of which belong in a dragable thumbnail. We
-- reuse render.draw_card_static (a shared helper introduced for this
-- exact split) so the editor preview stays byte-identical to the
-- in-game body+thumbnail+pushpin.

local M = {}

local render = require("src.render")

local CARD_DISPLAY_SIZE = {
    s  = { w = 110, h = 130 },
    m  = { w = 150, h = 180 },
    l  = { w = 270, h = 168 },
    xl = { w = 280, h = 320 },
}

-- Pushpin's vertical extent above the card top edge: 22 px tall, 0.35
-- of which sits above y=0 in the card's local frame. The pushpin is
-- visible above the card, so we pad the canvas by enough to fit it
-- plus a hair of breathing room.
local PUSHPIN_PAD_TOP = 12

-- Replace path-unsafe characters in a puzzle id so the file system
-- doesn't see "starter/smile.png" as a subdirectory traversal.
local function safe_filename(id)
    return (id:gsub("[/\\:]", "__")) .. ".png"
end

-- Write a PNG to a project-relative path using raw Lua I/O. We can't
-- use love.filesystem.write — that's rooted at the love save directory,
-- and we want the PNGs in the actual repo's assets/ tree so the editor
-- and git see them.
local function write_png(canvas, target_path)
    local image_data = canvas:newImageData()
    local file_data = image_data:encode("png")
    local bytes = file_data:getString()
    local f, err = io.open(target_path, "wb")
    if f == nil then
        error("make_card_thumbs: failed to open " .. target_path .. ": " .. tostring(err))
    end
    f:write(bytes)
    f:close()
end

-- Ensure assets/card_thumbs/ exists in the project root. love.filesystem
-- can't help (wrong root); fall back to os-agnostic plain Lua via an
-- io.open probe + a mkdir best-effort. We keep it simple: the user is
-- expected to run this command in the repo root, which already has
-- `assets/`. The subdir is created via a love.filesystem helper that
-- *can* see the project source dir for read, then we shell-free-ly
-- mkdir by writing a sentinel file (which fails iff dir doesn't exist
-- and we can't create it).
local function ensure_dir(path)
    -- Probe: is this already a directory?
    local probe = io.open(path .. "/.probe", "wb")
    if probe ~= nil then
        probe:close()
        os.remove(path .. "/.probe")
        return
    end
    -- Fall back to love.filesystem.createDirectory, which only works
    -- inside the save dir — but on desktop with --fused or run from
    -- the source dir, the source dir is also writable for our purposes.
    -- If we still can't write, surface a clear error so the user knows
    -- to mkdir manually.
    error("make_card_thumbs: directory not writable: " .. path ..
          "\nRun `mkdir -p " .. path .. "` and retry.")
end

function M.run(boxes, descriptors, thumbnails)
    local out_dir = "assets/card_thumbs"
    ensure_dir(out_dir)

    local count = 0
    local skipped = 0

    for bi = 1, #boxes do
        local box = boxes[bi]
        local puzzles = box.puzzles or {}
        for pi = 1, #puzzles do
            local p = puzzles[pi]
            local desc = descriptors[p.id]
            local thumb = thumbnails[p.id]
            if desc == nil or thumb == nil then
                print(string.format("[card-thumbs] skip %s (no descriptor/thumbnail)", p.id))
                skipped = skipped + 1
            else
                -- Pick card size from level bbox dims, same rules as in-game.
                local size = "m"
                local maxd = math.max(desc.width, desc.height)
                local ar = desc.width / desc.height
                if maxd <= 12 then size = "s"
                elseif ar >= 1.30 and maxd <= 56 then size = "l"
                elseif maxd <= 24 then size = "m"
                else size = "xl" end

                local cdim = CARD_DISPLAY_SIZE[size] or CARD_DISPLAY_SIZE.m
                local cw, ch = cdim.w, cdim.h

                -- Pushpin color: hash the puzzle id, same algorithm as
                -- menu._ensure_visuals so editor previews match in-game.
                local h = 5381
                for k = 1, #p.id do
                    h = (h * 33 + p.id:byte(k)) % 2147483647
                end
                local PUSHPIN = { "red", "gold", "silver", "teal" }
                local pushpin = PUSHPIN[(h % #PUSHPIN) + 1]

                -- Canvas: card + pushpin headroom. Card draws at (0, PAD).
                local canvas = love.graphics.newCanvas(cw, ch + PUSHPIN_PAD_TOP)
                love.graphics.push("all")
                love.graphics.setCanvas(canvas)
                love.graphics.clear(0, 0, 0, 0)
                render.draw_card_static(size, 0, PUSHPIN_PAD_TOP, cw, ch, thumb, pushpin)
                love.graphics.setCanvas()
                love.graphics.pop()

                local fname = safe_filename(p.id)
                local target = out_dir .. "/" .. fname
                write_png(canvas, target)
                print(string.format("[card-thumbs] wrote %s (%dx%d, size=%s, pin=%s)",
                    target, cw, ch + PUSHPIN_PAD_TOP, size, pushpin))
                count = count + 1
            end
        end
    end

    print(string.format("[card-thumbs] done: wrote %d, skipped %d", count, skipped))
end

return M
