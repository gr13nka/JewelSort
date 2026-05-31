-- src/book_layout.lua
--
-- Reader for hand-authored book layout files exported by the Lovkit2d
-- editor (schema/ui.schema.md v1 or v2). Looked up by book id; if a
-- file doesn't exist, the caller falls back to the greedy auto-packer
-- in src/menu.lua. See CLAUDE.md → "Authoring book layouts" for the
-- workflow.
--
-- File location convention:
--   screens/<book_id>.ui.json   (relative to repo root)
-- which matches the editor's default save path.
--
-- Element id ↔ puzzle id mapping:
--   The editor's id grammar forbids slashes ([a-zA-Z_][a-zA-Z0-9_]*),
--   but puzzle ids in levels/boxes.lua use slashes (e.g.
--   "starter/smile"). Element ids in the JSON therefore use double-
--   underscores in place of slashes — same convention as the
--   thumbnail filenames produced by tools/make_card_thumbs.lua. The
--   loader undoes the substitution before matching.

local json = require("src.json")

local M = {}

local function read_text(path)
    -- love.filesystem reads from the LÖVE source dir on desktop and the
    -- mounted `game.data` filesystem on web — both paths see screens/
    -- when packed via tools/build_web.sh.
    if love and love.filesystem and love.filesystem.getInfo then
        local info = love.filesystem.getInfo(path)
        if info == nil or info.type ~= "file" then return nil end
        return love.filesystem.read(path)
    end
    -- Headless fallback (test harness): plain Lua I/O.
    local f = io.open(path, "rb")
    if f == nil then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function unmangle_id(s)
    -- "starter__smile" -> "starter/smile". Only one occurrence per id
    -- in practice (book/puzzle), but gsub handles N safely.
    return (s:gsub("__", "/"))
end

local function flatten_children(node, out)
    if node == nil then return out end
    if node.children == nil then return out end
    for i = 1, #node.children do
        local c = node.children[i]
        out[#out + 1] = c
        if c.children ~= nil then flatten_children(c, out) end
    end
    return out
end

-- Read screens/<book_id>.ui.json and return a layout descriptor:
--   { rects = { [puzzle_idx] = {x, y, w, h, rotation, pivot_x, pivot_y} },
--     content_h = number,
--     screen_w = number, screen_h = number }
-- Or `nil, reason` if the file is missing / malformed.
function M.load(book_id, puzzles)
    local path = "screens/" .. book_id .. ".ui.json"
    local text = read_text(path)
    if text == nil then return nil, "no layout file at " .. path end

    local ok, doc_or_err = pcall(json.decode, text)
    if not ok then return nil, "json error: " .. tostring(doc_or_err) end
    local doc = doc_or_err

    if doc.schema_version ~= 1 and doc.schema_version ~= 2 then
        return nil, "unsupported schema_version " .. tostring(doc.schema_version)
    end
    if type(doc.screen) ~= "table"
        or type(doc.screen.w) ~= "number"
        or type(doc.screen.h) ~= "number" then
        return nil, "missing or invalid screen size"
    end
    if type(doc.root) ~= "table" then
        return nil, "missing root"
    end

    -- Build a lookup so element id -> puzzle index is O(1).
    local idx_by_id = {}
    for i = 1, #puzzles do
        idx_by_id[puzzles[i].id] = i
    end

    local elems = flatten_children(doc.root, {})
    local rects = {}
    local max_y = 0
    local matched, unmatched = 0, 0

    for i = 1, #elems do
        local e = elems[i]
        if type(e) == "table" and type(e.id) == "string" and type(e.rect) == "table" then
            local pid = unmangle_id(e.id)
            local pi = idx_by_id[pid]
            if pi ~= nil then
                local r = e.rect
                local rot = (type(e.rotation) == "number") and e.rotation or 0
                local pvx, pvy = 0.5, 0.5
                if type(e.pivot) == "table" then
                    if type(e.pivot.x) == "number" then pvx = e.pivot.x end
                    if type(e.pivot.y) == "number" then pvy = e.pivot.y end
                end
                rects[pi] = {
                    r.x or 0, r.y or 0, r.w or 0, r.h or 0,
                    rot, pvx, pvy,
                }
                local bottom = (r.y or 0) + (r.h or 0)
                if bottom > max_y then max_y = bottom end
                matched = matched + 1
            else
                unmatched = unmatched + 1
            end
        end
    end

    if matched == 0 then
        return nil, "no element ids in " .. path .. " match puzzle ids in book '" .. book_id .. "'"
    end
    if unmatched > 0 then
        print(string.format("[book_layout] %s: %d elements ignored (id didn't match any puzzle)",
            path, unmatched))
    end

    return {
        rects = rects,
        content_h = max_y,
        screen_w = doc.screen.w,
        screen_h = doc.screen.h,
    }
end

return M
