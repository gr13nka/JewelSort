-- progression.lua
-- Tracks per-puzzle completion and a cumulative jewel count that gates box
-- unlocks. Medals reflect each puzzle's *inherent* difficulty tier (authored
-- in levels/boxes.lua), awarded on any successful completion — there is no
-- performance metric. First completion credits jewels; replays are idempotent.

local save_format = require("src.save_format")

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
        completed = {}, -- [puzzle_id] = tier string (medal already earned)
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
    return wrote == true
end

-- Wipe progression back to a fresh state *in place*, so any held references
-- (menu controller, Level.award snapshots) keep seeing the same table.
function M.reset(state)
    state.jewels = 0
    state.completed = {}
    return state
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
