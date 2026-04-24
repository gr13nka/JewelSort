-- i18n.lua
-- Tiny localization layer. Locale files live under `locale/<lang>.lua`
-- and return a flat table keyed by i18n key. Missing keys fall back to
-- the English table, then to the raw key — so a stale RU file never
-- blanks out the UI.
--
-- Plurals: values may be either a plain string or a table of plural
-- forms `{ one = ..., few = ..., many = ... }`. `t_plural(key, n)`
-- picks the right form using the active locale's plural rule.

local M = {}

local EN = require("locale.en")
local active = EN
local active_lang = "en"

-- Plural category selectors. Return "one" | "few" | "many".
-- English: 1 → one, else → many. (We don't distinguish few.)
-- Russian: Slavic three-way. Matches CLDR rules.
local PLURAL_RULES = {
    en = function(n)
        if n == 1 then return "one" end
        return "many"
    end,
    ru = function(n)
        local mod10, mod100 = n % 10, n % 100
        if mod10 == 1 and mod100 ~= 11 then return "one" end
        if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14) then
            return "few"
        end
        return "many"
    end,
}

local function plural_of(n)
    local rule = PLURAL_RULES[active_lang] or PLURAL_RULES.en
    return rule(n)
end

-- Pick the active locale. Falls back silently to English if the file
-- is missing so a bad locale setting never crashes the game.
function M.set_locale(lang)
    if type(lang) ~= "string" or lang == "" then lang = "en" end
    if lang == active_lang then return end
    local ok, mod = pcall(require, "locale." .. lang)
    if ok and type(mod) == "table" then
        active = mod
        active_lang = lang
    else
        active = EN
        active_lang = "en"
    end
end

function M.locale()
    return active_lang
end

-- Look up a key and optionally substitute positional args via
-- string.format. Missing keys return the raw key so lookup failures
-- are visible in-game instead of rendering empty strings.
function M.t(key, ...)
    local s = active[key]
    if s == nil then s = EN[key] end
    if s == nil then return key end
    if type(s) == "table" then
        -- Caller meant `t_plural`, but was called with `t`. Pick
        -- `other` / `many` as the best single-form guess.
        s = s.many or s.other or s.one or key
    end
    if select("#", ...) > 0 then
        return string.format(s, ...)
    end
    return s
end

-- Plural-aware lookup. The value at `key` must be a table of plural
-- forms; otherwise behaves like `t` with n substituted.
function M.t_plural(key, n, ...)
    local s = active[key]
    if s == nil then s = EN[key] end
    if s == nil then return key end
    if type(s) == "table" then
        local form = plural_of(n)
        s = s[form] or s.many or s.other or s.one
        if s == nil then return key end
    end
    return string.format(s, n, ...)
end

return M
