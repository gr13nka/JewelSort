-- platform.lua
-- Thin façade over host-platform features. On desktop every call is a
-- no-op (except `locale` which returns the system language). On web
-- (love.js / Emscripten) we bridge to the Yandex Games SDK by writing
-- commands to a virtual-filesystem file (`/__ya_out`) that a small JS
-- poller — injected into index.html by tools/patch_web.sh — reads and
-- dispatches to `ysdk`. Events flowing back (ad closed, cloud payload)
-- arrive via `/__ya_in`, which we drain on every `tick(dt)`.
--
-- Design choices worth knowing:
--   • Plain `io.open` against MEMFS paths; Emscripten's virtual FS is
--     synchronously visible to JS as Module.FS, so no async plumbing.
--   • Line-oriented protocol: one command per line, space-separated,
--     escape-free. Payloads (cloud_save) are appended verbatim on the
--     same line after an explicit length prefix.
--   • At most one interstitial and one cloud_load pending at a time;
--     overlapping calls coalesce onto the newest callback.
--
-- The only stringly-typed contract shared with the JS side is the
-- command vocabulary below — keep it in lockstep with patch_web.sh.

local M = {}

local IS_WEB = love and love.system and love.system.getOS() == "Web"

local OUT_PATH = "/__ya_out"   -- Lua → JS, append-only
local IN_PATH  = "/__ya_in"    -- JS → Lua, read-and-truncate
local LOCALE_PATH = "/__ya_locale"  -- JS writes once on init

-- Single-slot callbacks. Nil when nothing is pending.
local on_ad_closed = nil
local on_cloud_loaded = nil
local cached_locale = nil   -- lazily read from LOCALE_PATH on web

local function emit(line)
    if not IS_WEB then return end
    local f = io.open(OUT_PATH, "a")
    if f == nil then return end
    f:write(line)
    f:write("\n")
    f:close()
end

function M.is_web()
    return IS_WEB == true
end

function M.loading_ready()
    emit("loading_ready")
end

function M.gameplay_start()
    emit("gameplay_start")
end

function M.gameplay_stop()
    emit("gameplay_stop")
end

function M.banner_show()
    emit("banner_show")
end

function M.banner_hide()
    emit("banner_hide")
end

-- Request an interstitial. `cb` (optional) is called with a boolean
-- `was_shown` when the ad closes. Only one interstitial is tracked;
-- a new request replaces any pending callback.
function M.interstitial(cb)
    on_ad_closed = cb
    emit("interstitial")
end

-- Returns the best-effort user locale ("ru", "en", "tr", ...). On
-- desktop we don't have a reliable source, so default to "en" — the
-- caller can override. On web, JS writes the lang code to LOCALE_PATH
-- immediately after YaGames.init() resolves; we cache it the first
-- time we see it.
function M.locale()
    if not IS_WEB then return "en" end
    if cached_locale ~= nil then return cached_locale end
    local f = io.open(LOCALE_PATH, "r")
    if f == nil then return "en" end
    local s = f:read("*a") or ""
    f:close()
    s = s:gsub("%s+$", "")
    if s == "" then return "en" end
    cached_locale = s
    return s
end

-- Fire-and-forget. `blob` is an opaque string (we use the existing
-- save_format Lua-table literal). JS stores it as `{ state: <blob> }`
-- in the Yandex Player Data object.
function M.cloud_save(blob)
    if not IS_WEB or type(blob) ~= "string" then return end
    -- Prefix with byte length so the JS parser knows exactly how much
    -- to consume regardless of newlines inside the blob.
    emit("cloud_save " .. #blob .. " " .. blob)
end

-- Request the remote save. `cb(blob_or_nil)` fires when JS replies.
-- Only one load is tracked at a time.
function M.cloud_load(cb)
    on_cloud_loaded = cb
    emit("cloud_load")
end

-- Called once per frame from main.lua love.update. Drains the inbound
-- command file and fires registered callbacks.
function M.tick()
    if not IS_WEB then return end
    local f = io.open(IN_PATH, "r")
    if f == nil then return end
    local body = f:read("*a") or ""
    f:close()
    if body == "" then return end
    -- Truncate: the JS side appends; we consume-and-clear atomically
    -- enough (single-threaded JS poller won't interleave a write
    -- while we're between the read and the clear).
    local clear = io.open(IN_PATH, "w")
    if clear ~= nil then clear:close() end

    for line in string.gmatch(body, "[^\n]+") do
        local cmd, rest = line:match("^(%S+)%s?(.*)$")
        if cmd == "ad_closed" then
            local was_shown = rest == "1"
            local cb = on_ad_closed
            on_ad_closed = nil
            if cb ~= nil then cb(was_shown) end
        elseif cmd == "ad_error" then
            local cb = on_ad_closed
            on_ad_closed = nil
            if cb ~= nil then cb(false) end
        elseif cmd == "cloud_loaded" then
            -- rest is either the full blob or the single token "nil"
            -- to mean "no save present".
            local cb = on_cloud_loaded
            on_cloud_loaded = nil
            if cb ~= nil then
                if rest == "" or rest == "nil" then cb(nil) else cb(rest) end
            end
        end
        -- Unknown commands are silently ignored so the JS side can
        -- add new events without breaking older Lua clients.
    end
end

return M
