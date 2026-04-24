-- English locale. Master reference — every new string goes here first.
-- Keys intentionally use snake_case; format strings use %d / %s tokens.
return {
    back            = "< Back",
    got_it          = "Got it",
    complete        = "Complete",
    solved          = "Solved!",
    already_mastered = "Already mastered",
    resetting       = "Resetting progress...",
    select_book     = "Select a book",
    sealed          = "SEALED",
    unsolved        = "UNSOLVED",
    no_preview      = "? ? ?",

    tutorial_title  = "Zoom & Pan",
    tutorial_wheel  = "Scroll wheel  -  zoom in/out",
    tutorial_drag   = "Drag background  -  pan",

    -- "%d" is the jewel count. Plural forms keyed by CLDR category.
    jewel_delta = {
        one  = "+%d jewel",
        many = "+%d jewels",
    },
    locked_needs = {
        one  = "Locked — needs %d jewel",
        many = "Locked — needs %d jewels",
    },
}
