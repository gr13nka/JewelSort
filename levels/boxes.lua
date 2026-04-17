-- boxes.lua
-- Ordered list of puzzle boxes ("books"). Each box has a jewel_cost gate
-- (cumulative lifetime jewel count required to unlock it), a title, and an
-- ordered list of puzzles. Each puzzle has a stable id (used for save state),
-- the PNG file under levels/, and an inherent difficulty tier.
--
-- Tier -> jewel reward (defined in src/progression.lua):
--   bronze = 1, silver = 2, gold = 3
--
-- Layout convention: each book gets its own subfolder under levels/, named
-- the same as the book's id. Puzzle PNGs live inside that subfolder, and
-- puzzle ids follow the "<book>/<filename>" pattern so two books can share
-- a base filename without colliding in the save file.
--
-- Authoring a new puzzle: drop its PNG into levels/<book>/, then add an
-- entry to the right box here. The PNG alone is not enough to appear
-- in-game; the registry is still the source of truth for ordering and
-- difficulty.

return {
    {
        id = "starter",
        title = "First Steps",
        jewel_cost = 0,
        puzzles = {
            { id = "starter/smile", file = "starter/smile.png", tier = "bronze" },
            { id = "starter/heart", file = "starter/heart.png", tier = "silver" },
        },
    },
    -- Example locked box (no PNGs yet). Safe to leave in: the menu shows it
    -- as locked until enough jewels are earned; selecting it does nothing.
    {
        id = "shapes",
        title = "Shapes & Symbols",
        jewel_cost = 3,
        puzzles = {
            -- Add puzzles here as you author more PNGs, e.g.:
            -- { id = "shapes/star", file = "shapes/star.png", tier = "gold" },
        },
    },
}
