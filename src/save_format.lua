-- save_format.lua
-- Tiny, deterministic Lua-table serializer for save state. Only accepts
-- strings, numbers, booleans, and nested tables. Keys are written as
-- bracketed string literals (or integer indices). Good enough for the
-- progression save; avoids pulling in a JSON library.

local M = {}

local function escape_string(s)
    -- %q would work but produces \n escapes that confuse love.js loaders
    -- occasionally. Plain-quote with manual escapes for backslash and quote.
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. s .. '"'
end

local function is_array(t)
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then return false end
        if k > n then n = k end
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true, n
end

local encode -- forward

local function encode_key(k)
    if type(k) == "number" then
        return "[" .. tostring(k) .. "]"
    end
    return "[" .. escape_string(tostring(k)) .. "]"
end

encode = function(v, indent)
    indent = indent or 0
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "0" -- non-finite -> safe default
        end
        return tostring(v)
    end
    if t == "string" then return escape_string(v) end
    if t == "table" then
        local arr, n = is_array(v)
        local pad = string.rep("  ", indent + 1)
        local close_pad = string.rep("  ", indent)
        local parts = { "{" }
        if arr then
            for i = 1, n do
                parts[#parts + 1] = pad .. encode(v[i], indent + 1) .. ","
            end
        else
            -- Deterministic order: sort keys by string form.
            local keys = {}
            for k, _ in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for i = 1, #keys do
                local k = keys[i]
                parts[#parts + 1] = pad
                    .. encode_key(k) .. " = "
                    .. encode(v[k], indent + 1) .. ","
            end
        end
        parts[#parts + 1] = close_pad .. "}"
        return table.concat(parts, "\n")
    end
    return "nil"
end

function M.serialize(tbl)
    return "return " .. encode(tbl, 0) .. "\n"
end

return M
