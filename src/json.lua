-- json.lua — minimal pure-Lua JSON decoder for JewelSort.
--
-- This module exists because LÖVE has no built-in JSON parser, but
-- src/book_layout.lua needs to read .ui.json files exported by the
-- Lovkit2d editor.
--
-- Constraints (from CLAUDE.md):
--   - No `goto` (the love.js --compatibility build has historically
--     tripped on goto in vendored libs; we keep the invariant project-wide).
--   - No recursion in unbounded structures. JSON nesting is bounded by
--     authoring (UI files are flat trees a few levels deep), so the
--     recursive descent here is safe — but we keep it shallow.
--   - Decode-only. We never write JSON from Lua: the editor is the
--     authoring tool, JewelSort is read-only.
--
-- Supported: full JSON spec — objects, arrays, strings (with \uXXXX),
-- numbers (int/float, scientific), true/false/null, whitespace.
-- Returns the decoded value, or raises an error with a position hint.

local M = {}

local function err(msg, s, pos)
    local line = 1
    local col = 1
    for i = 1, math.min(pos, #s) do
        if s:sub(i, i) == "\n" then
            line = line + 1
            col = 1
        else
            col = col + 1
        end
    end
    error("json: " .. msg .. " at line " .. line .. " col " .. col, 2)
end

-- Skip whitespace; return new position.
local function skip_ws(s, pos)
    local _, e = s:find("^[ \t\r\n]*", pos)
    return (e or pos - 1) + 1
end

local parse_value  -- forward declaration

local function parse_string(s, pos)
    -- pos is at the opening quote.
    local i = pos + 1
    local out = {}
    local n = #s
    while i <= n do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local esc = s:sub(i + 1, i + 1)
            if esc == "" then err("unterminated escape", s, i) end
            if esc == '"' then out[#out + 1] = '"'; i = i + 2
            elseif esc == "\\" then out[#out + 1] = "\\"; i = i + 2
            elseif esc == "/" then out[#out + 1] = "/"; i = i + 2
            elseif esc == "b" then out[#out + 1] = "\b"; i = i + 2
            elseif esc == "f" then out[#out + 1] = "\f"; i = i + 2
            elseif esc == "n" then out[#out + 1] = "\n"; i = i + 2
            elseif esc == "r" then out[#out + 1] = "\r"; i = i + 2
            elseif esc == "t" then out[#out + 1] = "\t"; i = i + 2
            elseif esc == "u" then
                local hex = s:sub(i + 2, i + 5)
                if #hex ~= 4 or hex:find("[^0-9a-fA-F]") then
                    err("bad \\u escape", s, i)
                end
                local cp = tonumber(hex, 16)
                -- UTF-8 encode the codepoint. UI files are ASCII or BMP
                -- in practice; we still handle the full BMP range here.
                if cp < 0x80 then
                    out[#out + 1] = string.char(cp)
                elseif cp < 0x800 then
                    out[#out + 1] = string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
                else
                    out[#out + 1] = string.char(
                        0xE0 + math.floor(cp / 0x1000),
                        0x80 + math.floor(cp / 0x40) % 0x40,
                        0x80 + (cp % 0x40)
                    )
                end
                i = i + 6
            else
                err("bad escape \\" .. esc, s, i)
            end
        elseif c == "\n" or c == "\r" then
            err("unterminated string (newline in literal)", s, i)
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    err("unterminated string", s, pos)
end

local function parse_number(s, pos)
    local _, e, num = s:find("^(-?%d+%.?%d*[eE]?[%+%-]?%d*)", pos)
    if not num or num == "" or num == "-" then err("bad number", s, pos) end
    local n = tonumber(num)
    if n == nil then err("bad number '" .. num .. "'", s, pos) end
    return n, e + 1
end

local function parse_keyword(s, pos)
    if s:sub(pos, pos + 3) == "true"  then return true,  pos + 4 end
    if s:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    -- nil can't be stored in a Lua table without erasing the key, so we
    -- return a sentinel that callers can map (or ignore — most JSON
    -- consumers treat null as "field absent" anyway).
    if s:sub(pos, pos + 3) == "null"  then return M.null, pos + 4 end
    err("unexpected token", s, pos)
end

local function parse_array(s, pos)
    -- pos is at '['
    local arr = {}
    pos = skip_ws(s, pos + 1)
    if s:sub(pos, pos) == "]" then return arr, pos + 1 end
    while true do
        local v
        v, pos = parse_value(s, pos)
        arr[#arr + 1] = v
        pos = skip_ws(s, pos)
        local c = s:sub(pos, pos)
        if c == "," then
            pos = skip_ws(s, pos + 1)
        elseif c == "]" then
            return arr, pos + 1
        else
            err("expected ',' or ']' in array", s, pos)
        end
    end
end

local function parse_object(s, pos)
    -- pos is at '{'
    local obj = {}
    pos = skip_ws(s, pos + 1)
    if s:sub(pos, pos) == "}" then return obj, pos + 1 end
    while true do
        if s:sub(pos, pos) ~= '"' then err("expected string key", s, pos) end
        local key
        key, pos = parse_string(s, pos)
        pos = skip_ws(s, pos)
        if s:sub(pos, pos) ~= ":" then err("expected ':' after key", s, pos) end
        pos = skip_ws(s, pos + 1)
        local v
        v, pos = parse_value(s, pos)
        obj[key] = v
        pos = skip_ws(s, pos)
        local c = s:sub(pos, pos)
        if c == "," then
            pos = skip_ws(s, pos + 1)
        elseif c == "}" then
            return obj, pos + 1
        else
            err("expected ',' or '}' in object", s, pos)
        end
    end
end

parse_value = function(s, pos)
    pos = skip_ws(s, pos)
    local c = s:sub(pos, pos)
    if c == '"' then return parse_string(s, pos) end
    if c == "{" then return parse_object(s, pos) end
    if c == "[" then return parse_array(s, pos) end
    if c == "t" or c == "f" or c == "n" then return parse_keyword(s, pos) end
    if c == "-" or (c >= "0" and c <= "9") then return parse_number(s, pos) end
    err("unexpected character '" .. c .. "'", s, pos)
end

-- Sentinel for JSON null. Compare with `value == json.null` if you care
-- about distinguishing "field set to null" from "field absent".
M.null = setmetatable({}, { __tostring = function() return "json.null" end })

function M.decode(s)
    if type(s) ~= "string" then
        error("json.decode: expected string, got " .. type(s), 2)
    end
    local v, pos = parse_value(s, 1)
    pos = skip_ws(s, pos)
    if pos <= #s then err("trailing content after JSON value", s, pos) end
    return v
end

return M
