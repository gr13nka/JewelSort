-- progression.lua
-- Tracks per-puzzle completion and a cumulative jewel count that gates box
-- unlocks. Medals reflect each puzzle's *inherent* difficulty tier (authored
-- in levels/boxes.lua), awarded on any successful completion — there is no
-- performance metric. First completion credits jewels; replays are idempotent.

local save_format = require("src.save_format")
local platform = require("src.platform")

local M = {}

local SAVE_PATH = "progress.lua"

local TIER_VALUE = {
    bronze = 1,
    silver = 2,
    gold = 3,
}

function M.tier_value(tier)
    return TIER_VALUE[tier] or 0
end

-- Fresh, empty progression state.
local function fresh_state()
    return {
        jewels = 0,
        completed = {},    -- [puzzle_id] = tier string (medal already earned)
        tutorial_seen = {}, -- [tutorial_key] = true, once the overlay has been dismissed
    }
end

-- Sandbox-load a Lua file via love.filesystem.load. Returns table or nil.
local function read_save()
    if love == nil or love.filesystem == nil then return nil end
    if not love.filesystem.getInfo(SAVE_PATH) then return nil end
    local chunk, err = love.filesystem.load(SAVE_PATH)
    if chunk == nil then return nil end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function sanitize(loaded)
    local s = fresh_state()
    if type(loaded.jewels) == "number" and loaded.jewels >= 0 then
        s.jewels = math.floor(loaded.jewels)
    end
    if type(loaded.completed) == "table" then
        for k, v in pairs(loaded.completed) do
            if type(k) == "string" and type(v) == "string" and TIER_VALUE[v] then
                s.completed[k] = v
            end
        end
    end
    if type(loaded.tutorial_seen) == "table" then
        for k, v in pairs(loaded.tutorial_seen) do
            if type(k) == "string" and v == true then
                s.tutorial_seen[k] = true
            end
        end
    end
    return s
end

function M.load()
    local raw = read_save()
    if raw == nil then return fresh_state() end
    return sanitize(raw)
end

function M.save(state)
    if love == nil or love.filesystem == nil then return false end
    local ok, encoded = pcall(save_format.serialize, state)
    if not ok then return false end
    local wrote = love.filesystem.write(SAVE_PATH, encoded)
    -- Mirror to Yandex Player Data on web. Fire-and-forget — local
    -- save is source of truth within a session, cloud is for
    -- cross-device continuity. `encoded` starts with "return ..." —
    -- an opaque blob to the JS side, decoded only when we load it
    -- back via parse_blob below.
    if platform.is_web() then
        platform.cloud_save(encoded)
    end
    return wrote == true
end

-- Parse a serialized blob (same format as M.save emits) back into a
-- sanitized state table. Returns nil on any failure.
local function parse_blob(blob)
    if type(blob) ~= "string" or blob == "" then return nil end
    local chunk, err = load(blob, "=cloud", "t")
    if chunk == nil then return nil end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil end
    return sanitize(data)
end

-- Merge `remote` (cloud snapshot) into `state` (live, in-place).
-- Rule: keep whichever source shows more progress per field.
-- Jewels: max. Completed puzzles: union, choosing the better medal
-- per id (gold > silver > bronze via TIER_VALUE). Tutorials: union
-- — once seen anywhere, considered seen.
--
-- Returns true iff `state` actually changed, so the caller knows
-- whether to re-save locally.
function M.merge_remote(state, remote)
    if type(remote) ~= "table" then return false end
    local changed = false
    if type(remote.jewels) == "number" and remote.jewels > (state.jewels or 0) then
        state.jewels = math.floor(remote.jewels)
        changed = true
    end
    if type(remote.completed) == "table" then
        for id, tier in pairs(remote.completed) do
            local cur = state.completed[id]
            if cur == nil then
                state.completed[id] = tier
                changed = true
            elseif M.tier_value(tier) > M.tier_value(cur) then
                state.completed[id] = tier
                changed = true
            end
        end
    end
    if type(remote.tutorial_seen) == "table" then
        for k, v in pairs(remote.tutorial_seen) do
            if v == true and state.tutorial_seen[k] ~= true then
                state.tutorial_seen[k] = true
                changed = true
            end
        end
    end
    return changed
end

-- Asynchronously fetch the cloud save and merge it into `state`.
-- `on_complete` is called after the merge (may be nil) with a
-- boolean `changed` indicating whether `state` was actually mutated.
-- On desktop / non-web this resolves immediately with `false`.
function M.cloud_sync(state, on_complete)
    if not platform.is_web() then
        if on_complete ~= nil then on_complete(false) end
        return
    end
    platform.cloud_load(function(blob)
        local remote = parse_blob(blob)
        local changed = false
        if remote ~= nil then
            changed = M.merge_remote(state, remote)
        end
        if changed then
            -- Re-serialize the merged state locally so next boot
            -- has the newer snapshot even before cloud replies.
            local ok, encoded = pcall(save_format.serialize, state)
            if ok and love and love.filesystem then
                love.filesystem.write(SAVE_PATH, encoded)
            end
        end
        if on_complete ~= nil then on_complete(changed) end
    end)
end

-- Wipe progression back to a fresh state *in place*, so any held references
-- (menu controller, Level.award snapshots) keep seeing the same table.
function M.reset(state)
    state.jewels = 0
    state.completed = {}
    state.tutorial_seen = {}
    return state
end

function M.is_tutorial_seen(state, key)
    if state == nil or state.tutorial_seen == nil then return false end
    return state.tutorial_seen[key] == true
end

function M.mark_tutorial_seen(state, key)
    if state == nil then return end
    if state.tutorial_seen == nil then state.tutorial_seen = {} end
    state.tutorial_seen[key] = true
end

function M.is_box_unlocked(state, box)
    if box == nil then return false end
    local cost = box.jewel_cost or 0
    return state.jewels >= cost
end

function M.is_puzzle_completed(state, puzzle_id)
    return state.completed[puzzle_id] ~= nil
end

function M.puzzle_medal(state, puzzle_id)
    return state.completed[puzzle_id] -- nil | "bronze"|"silver"|"gold"
end

-- Count how many puzzles in `box` have been completed.
function M.box_completed_count(state, box)
    if box == nil or box.puzzles == nil then return 0 end
    local n = 0
    for i = 1, #box.puzzles do
        if state.completed[box.puzzles[i].id] ~= nil then
            n = n + 1
        end
    end
    return n
end

-- Record a win. Returns { first_time = bool, tier = string, jewels_delta = N }.
function M.award(state, puzzle)
    local tier = puzzle.tier or "bronze"
    if not TIER_VALUE[tier] then tier = "bronze" end

    if state.completed[puzzle.id] ~= nil then
        -- Replay: no additional jewels, medal unchanged.
        return { first_time = false, tier = state.completed[puzzle.id], jewels_delta = 0 }
    end

    state.completed[puzzle.id] = tier
    local delta = TIER_VALUE[tier]
    state.jewels = state.jewels + delta
    return { first_time = true, tier = tier, jewels_delta = delta }
end

return M
