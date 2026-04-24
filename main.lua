-- main.lua
-- LÖVE entry point for JewelSort. Owns the game-state machine:
--   mode = "menu"    -> box / level select (src/menu.lua)
--   mode = "playing" -> active puzzle (existing level/input/render flow)
-- Progression (medals + cumulative jewel unlocks) persists via
-- love.filesystem through src/progression.lua.

local level_loader = require("src.level_loader")
local Level = require("src.level")
local render = require("src.render")
local input = require("src.input")
local progression = require("src.progression")
local Menu = require("src.menu")
local Particles = require("src.particles")

local game = {
    mode = "menu",              -- "menu" | "playing"
    boxes = {},                 -- from levels/boxes.lua
    descriptors = {},           -- [puzzle_id] = level descriptor (cached)
    thumbnails = {},            -- [puzzle_id] = Canvas
    progress = nil,             -- progression state
    menu = nil,                 -- menu controller
    level = nil,                -- active Level instance
    layout = nil,               -- active level layout
    view = nil,                 -- { zoom, pan_x, pan_y, rmb_drag, touches, gesture }
    current = nil,              -- { box_idx, puzzle_idx, puzzle }
    mouse = { x = 0, y = 0 },
    particles = nil,            -- sparkle system (flying-jewel glitter)
    confetti = nil,             -- paper-confetti list, drawn inside the
                                -- celebration overlay (see draw_celebration)
    f1_hold = 0,                -- seconds F1 has been held this press
    f1_fired = false,           -- true once the reset has fired for this press
    -- Celebration overlay state, built when a puzzle is won. Lives here
    -- (not on Level) because it needs to outlive the Level instance when
    -- the flight-to-counter animation starts on the menu screen.
    celebration = nil,
    -- Post-celebration flight state: jewels fly from the celebration card
    -- center into the menu's jewel badge. Stored here because the menu
    -- stays dumb and the flight needs to render on top of the menu chrome.
    pending_flight = nil,
    -- Badge pulse fired when a flight jewel arrives. Single channel:
    -- overlapping arrivals restart the pulse (feels like one organ).
    counter_pulse = nil,
    -- Zoom/pan tutorial overlay. Populated on first Forest puzzle entry,
    -- or when the player taps the persistent controls hint plaque.
    tutorial = nil,
}

-- Key of the only tutorial in the game right now. Kept as a constant so
-- the progression save-file stays stable if more tutorials are added later.
local TUTORIAL_ZOOM_PAN = "zoom_pan"
-- Box id that triggers the zoom/pan tutorial on first entry. Forest is the
-- first book whose puzzles are large enough for the auto-zoom path to kick
-- in (see MIN_PLAYABLE_CELL below), so this is where players first need
-- to know about wheel-zoom and drag-pan.
local TUTORIAL_TRIGGER_BOX_ID = "forest"

local F1_RESET_HOLD_SECONDS = 3

-- 9:16 portrait is the design aspect. When the host viewport differs,
-- we letterbox the content rect so nothing is ever clipped. Yandex
-- Games in particular may hand us any aspect depending on frame chrome.
local TARGET_ASPECT = 9 / 16

-- Inscribed 9:16 rect inside the current window. Returns
-- (content_w, content_h, offset_x, offset_y). All game code works
-- inside this rect; the draw root translates by (ox, oy) and the
-- input handlers subtract (ox, oy) from incoming coords.
local function viewport()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    if W <= 0 or H <= 0 then return W, H, 0, 0 end
    if W / H > TARGET_ASPECT then
        local vw = math.floor(H * TARGET_ASPECT)
        return vw, H, math.floor((W - vw) / 2), 0
    else
        local vh = math.floor(W / TARGET_ASPECT)
        return W, vh, 0, math.floor((H - vh) / 2)
    end
end

-- Translate raw window coords into the letterboxed content space.
local function to_content(x, y)
    local _, _, ox, oy = viewport()
    return x - ox, y - oy
end

-- View / zoom constants. Levels whose fit-to-board cell size falls below
-- MIN_PLAYABLE_CELL get auto-zoomed in on start so the first tap target is
-- always finger-sized; the player can pan (RMB drag / two-finger drag) to
-- reach the parts of the grid that now overflow the board, and scroll-wheel
-- / pinch to adjust zoom themselves. MAX_ZOOM caps how far in they can go.
local MIN_PLAYABLE_CELL = 44
local MIN_ZOOM = 1.0
local MAX_ZOOM = 6.0
local WHEEL_ZOOM_STEP = 0.14

-- Tween timings kept close to the state they drive. Must match the
-- celebration schedule in render.lua.
local CELEBRATION_FLIGHT_STAGGER = 0.10
local CELEBRATION_FLIGHT_DURATION = 0.55
local CELEBRATION_FLIGHT_CAP = 12     -- beyond this, flights pair up
local COUNTER_PULSE_DURATION = 0.35
local COUNTER_PULSE_PEAK = 0.18       -- added on top of base scale 1.0

local function ensure_samples_exist()
    local files = level_loader.list_level_files()
    if #files > 0 then return end
    local ok, make_samples = pcall(require, "tools.make_samples")
    if ok and make_samples and make_samples.generate then
        make_samples.generate()
    end
end

local function load_boxes()
    local ok, boxes = pcall(require, "levels.boxes")
    if ok and type(boxes) == "table" then return boxes end
    return {}
end

-- Preload descriptors + thumbnails for every puzzle referenced by boxes.lua.
-- Silently skips puzzles whose PNG is missing so new/empty boxes don't crash.
local function preload_puzzles()
    for bi = 1, #game.boxes do
        local box = game.boxes[bi]
        local puzzles = box.puzzles or {}
        for pi = 1, #puzzles do
            local p = puzzles[pi]
            if game.descriptors[p.id] == nil then
                local desc = level_loader.load_by_file(p.file)
                if desc ~= nil then
                    game.descriptors[p.id] = desc
                    game.thumbnails[p.id] = level_loader.render_thumbnail(desc, 96)
                end
            end
        end
    end
end

-- Adjust view zoom while keeping the grid point under (sx, sy) fixed, so
-- scrolling the wheel / pinching feels anchored to the cursor or pinch
-- center. Pan is updated to compensate; compute_layout will clamp it on
-- the next layout build so the grid can't drift past the board edges.
local function zoom_view_at(view, layout, sx, sy, factor)
    if view == nil or layout == nil then return end
    local new_zoom = view.zoom * factor
    if new_zoom < MIN_ZOOM then new_zoom = MIN_ZOOM end
    if new_zoom > MAX_ZOOM then new_zoom = MAX_ZOOM end
    if new_zoom == view.zoom then return end
    local old_cell = layout.cell_size
    local new_cell = math.max(1, math.floor(layout.fit_cell * new_zoom))
    if old_cell == new_cell then
        view.zoom = new_zoom
        return
    end
    local world_x = (sx - layout.origin_x) / old_cell
    local world_y = (sy - layout.origin_y) / old_cell
    local ga = layout.grid_area
    local new_grid_w = new_cell * layout.cols
    local new_grid_h = new_cell * layout.rows
    local new_fit_ox = ga.x + math.floor((ga.w - new_grid_w) / 2)
    local new_fit_oy = ga.y + math.floor((ga.h - new_grid_h) / 2)
    view.zoom = new_zoom
    view.pan_x = (sx - world_x * new_cell) - new_fit_ox
    view.pan_y = (sy - world_y * new_cell) - new_fit_oy
end

local function start_puzzle(box_idx, puzzle_idx)
    local box = game.boxes[box_idx]
    if box == nil then return end
    local puzzle = (box.puzzles or {})[puzzle_idx]
    if puzzle == nil then return end
    local desc = game.descriptors[puzzle.id]
    if desc == nil then return end
    game.level = Level.new(desc)
    local w, h = viewport()
    -- Fresh view per puzzle. Auto-zoom kicks in when fit-to-board cells
    -- would be too small to tap comfortably.
    game.view = {
        zoom = 1.0,
        pan_x = 0,
        pan_y = 0,
        rmb_drag = nil,     -- { last_x, last_y } while RMB is held
        lmb_drag = nil,     -- { last_x, last_y } while LMB is held on bg
        touches = {},       -- id -> { x, y } for active touches
        gesture = nil,      -- { midx, midy, dist } last pinch state
    }
    local fit_layout = render.compute_layout(game.level, w, h, game.view)
    if fit_layout.fit_cell < MIN_PLAYABLE_CELL then
        local needed = MIN_PLAYABLE_CELL / fit_layout.fit_cell
        game.view.zoom = math.min(MAX_ZOOM, needed)
    end
    game.layout = render.compute_layout(game.level, w, h, game.view)
    game.level.layout = game.layout
    game.current = { box_idx = box_idx, puzzle_idx = puzzle_idx, puzzle = puzzle }
    game.mode = "playing"
    game.celebration = nil
    game.pending_flight = nil
    if game.particles then game.particles:clear() end
    -- First entry to the Forest book (or any puzzle in it) teaches
    -- zoom/pan, since that's the first book where auto-zoom kicks in.
    if box.id == TUTORIAL_TRIGGER_BOX_ID
        and not progression.is_tutorial_seen(game.progress, TUTORIAL_ZOOM_PAN) then
        game.tutorial = { active = true, key = TUTORIAL_ZOOM_PAN }
    else
        game.tutorial = nil
    end
end

local function return_to_menu()
    game.level = nil
    game.layout = nil
    game.view = nil
    game.current = nil
    game.mode = "menu"
    game.celebration = nil
    game.tutorial = nil
    -- NOTE: pending_flight intentionally preserved across this transition —
    -- it's what makes jewels fly into the menu's counter.
    if game.menu then game.menu:go_to_boxes() end
end

-- Unique target colors in the puzzle, in first-seen order. Used to tint
-- the flight jewels + confetti so the celebration reflects the puzzle.
local function puzzle_palette(level)
    local seen = {}
    local out = {}
    for i = 1, #level.cell_list do
        local t = level.cell_list[i].target
        local k = tostring(math.floor(t[1] * 255)) .. ","
              .. tostring(math.floor(t[2] * 255)) .. ","
              .. tostring(math.floor(t[3] * 255))
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = { t[1], t[2], t[3] }
        end
    end
    if #out == 0 then out[1] = { 1, 1, 1 } end
    return out
end

local function begin_celebration()
    if game.level == nil then return end
    game.celebration = {
        t = 0,
        award = game.level.award,
        palette = puzzle_palette(game.level),
        count_display = 0,
        button_pressed = false,
        confetti_fired = { false, false, false },
    }
end

local function begin_return_flight()
    if game.celebration == nil or game.level == nil then
        return_to_menu()
        return
    end
    local award = game.celebration.award
    local W, H = viewport()
    local start_cx, start_cy = render.celebration_card_center(W, H)

    if award == nil or not award.first_time or award.jewels_delta <= 0 then
        -- Replay / already-mastered: no flight. Just return.
        game.pending_flight = nil
        return_to_menu()
        return
    end

    local count = math.min(award.jewels_delta, CELEBRATION_FLIGHT_CAP)
    local jewels = {}
    local palette = game.celebration.palette
    for i = 1, count do
        -- Past the visible cap, pair later jewels with earlier t0 values
        -- so the full delta still "lands" in reasonable time.
        local t0 = (i - 1) * CELEBRATION_FLIGHT_STAGGER
        if award.jewels_delta > CELEBRATION_FLIGHT_CAP then
            t0 = ((i - 1) % count) * CELEBRATION_FLIGHT_STAGGER
        end
        jewels[i] = {
            t0 = t0,
            color = palette[((i - 1) % #palette) + 1],
            arrived = false,
        }
    end
    game.pending_flight = {
        t = 0,
        duration = CELEBRATION_FLIGHT_DURATION,
        jewels = jewels,
        arrived_count = 0,
        start_world = { x = start_cx, y = start_cy },
        base_count = game.progress.jewels - award.jewels_delta,
        displayed_count = game.progress.jewels - award.jewels_delta,
    }
    return_to_menu()
end

-- Gate: true once the celebration has reached "button tappable" phase.
local function celebration_button_active()
    return game.celebration ~= nil and render.celebration_button_ready(game.celebration)
end

local function skip_celebration_to_menu()
    -- Esc during celebration: drop celebration + any pending flight and
    -- go straight back to menu. Intentionally misses the jewel flight —
    -- it's the "I'm done" path.
    game.celebration = nil
    game.pending_flight = nil
    if game.particles then game.particles:clear() end
    return_to_menu()
end

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest", 0)
    if love.math and love.math.setRandomSeed then
        love.math.setRandomSeed(os.time())
    end

    ensure_samples_exist()
    game.boxes = load_boxes()
    game.progress = progression.load()
    preload_puzzles()
    game.menu = Menu.new(game.boxes, game.progress)
    game.particles = Particles.new()
    game.confetti = Particles.new()

    -- Dev CLI flags. Checked once at boot so later code can inspect them.
    game.dev = { auto_win = false, quit_after = nil }
    if args ~= nil then
        for i = 1, #args do
            if args[i] == "--dev-win" then game.dev.auto_win = true end
            if args[i] == "--dev-press" then game.dev.auto_press = true end
            if args[i] == "--dev-quit" then
                local n = tonumber(args[i + 1])
                if n then game.dev.quit_after = n end
            end
        end
    end
    if game.dev.auto_win then
        -- Start the first playable puzzle in the first unlocked box so the
        -- celebration has a real level to sit on. Force-win after a brief
        -- delay so we can see the very first few frames of celebration.t.
        local bi, pi = 1, 1
        if game.boxes[bi] and game.boxes[bi].puzzles and game.boxes[bi].puzzles[pi] then
            start_puzzle(bi, pi)
            game.dev.auto_win_trigger_t = 0.15
            print("[DEV] auto-win armed; will force-win in 0.15s")
        else
            print("[DEV] --dev-win: no puzzle to start")
        end
    end
end

local function reset_progress()
    progression.reset(game.progress)
    progression.save(game.progress)
    game.celebration = nil
    game.pending_flight = nil
    game.counter_pulse = nil
    if game.mode == "playing" then
        return_to_menu()
    elseif game.menu ~= nil then
        game.menu:go_to_boxes()
    end
end

-- Advance in-flight jewels, mark arrivals, pulse the counter, and clear
-- the flight when all jewels have landed.
local function update_pending_flight(dt)
    local pf = game.pending_flight
    if pf == nil then return end
    pf.t = pf.t + dt
    for i = 1, #pf.jewels do
        local j = pf.jewels[i]
        if not j.arrived then
            local rel = pf.t - j.t0
            if rel >= pf.duration then
                j.arrived = true
                pf.arrived_count = pf.arrived_count + 1
                pf.displayed_count = pf.displayed_count + 1
                game.counter_pulse = { t = 0, duration = COUNTER_PULSE_DURATION }
                if game.particles then
                    local W, H = viewport()
                    local bx, by, bw, bh = game.menu:badge_rect(W, H)
                    game.particles:spawn(bx + bw / 2, by + bh / 2, j.color, 40)
                end
            end
        end
    end
    if pf.arrived_count >= #pf.jewels then
        game.pending_flight = nil
    end
end

local function update_counter_pulse(dt)
    local cp = game.counter_pulse
    if cp == nil then return end
    cp.t = cp.t + dt
    if cp.t >= cp.duration then
        game.counter_pulse = nil
    end
end

-- Normalize counter pulse into a scale factor > 1 while the pulse is
-- active. sin(pi*u) peaks at u=0.5 and returns to 0 at u=1.
local function counter_pulse_scale()
    local cp = game.counter_pulse
    if cp == nil then return 1 end
    local u = math.min(cp.t / cp.duration, 1)
    return 1 + COUNTER_PULSE_PEAK * math.sin(math.pi * u)
end

function love.update(dt)
    if love.mouse then
        local mx, my = love.mouse.getPosition()
        game.mouse.x, game.mouse.y = to_content(mx, my)
    end
    if game.dev ~= nil then
        if game.dev.auto_win_trigger_t ~= nil then
            game.dev.auto_win_trigger_t = game.dev.auto_win_trigger_t - dt
            if game.dev.auto_win_trigger_t <= 0 and game.level ~= nil and not game.level.won then
                for i = 1, #game.level.cell_list do
                    local c = game.level.cell_list[i]
                    c.jewel = { c.target[1], c.target[2], c.target[3] }
                end
                game.level.win_anim = nil
                game.level.place_anim = nil
                game.level.won = true
                game.dev.auto_win_trigger_t = nil
                print("[DEV] forced level win")
            end
        end
        if game.dev.auto_press and not game.dev.auto_press_fired
           and game.celebration ~= nil
           and render.celebration_button_ready(game.celebration) then
            game.dev.auto_press_fired = true
            print(string.format("[DEV] auto-pressing Complete at t=%.2f; mode=%s level=%s",
                game.celebration.t, game.mode, tostring(game.level ~= nil)))
            begin_return_flight()
            print(string.format("[DEV] after begin_return_flight: mode=%s pending_flight=%s celebration=%s",
                game.mode, tostring(game.pending_flight ~= nil), tostring(game.celebration ~= nil)))
            if game.pending_flight ~= nil then
                print(string.format("[DEV]   pending_flight: #jewels=%d start=(%.1f,%.1f) base=%d displayed=%d",
                    #game.pending_flight.jewels,
                    game.pending_flight.start_world.x, game.pending_flight.start_world.y,
                    game.pending_flight.base_count, game.pending_flight.displayed_count))
            end
        end
        if game.dev.quit_after ~= nil then
            game.dev.quit_after = game.dev.quit_after - dt
            if game.dev.quit_after <= 0 then
                love.event.quit()
            end
        end
    end
    if love.keyboard ~= nil and love.keyboard.isDown("f1") then
        if not game.f1_fired then
            game.f1_hold = game.f1_hold + dt
            if game.f1_hold >= F1_RESET_HOLD_SECONDS then
                game.f1_fired = true
                reset_progress()
            end
        end
    else
        game.f1_hold = 0
        game.f1_fired = false
    end
    if game.particles ~= nil then
        game.particles:update(dt)
    end
    if game.confetti ~= nil then
        game.confetti:update(dt)
    end
    if game.menu ~= nil then
        game.menu:update(dt)
    end
    if game.mode == "playing" and game.level ~= nil then
        game.level:update(dt)
        -- Detect win transition: award + save exactly once, and kick off
        -- the celebration overlay at the same moment.
        if game.level.won and game.level.award == nil and game.current ~= nil then
            local puzzle = game.current.puzzle
            local award = progression.award(game.progress, puzzle)
            game.level.award = award
            progression.save(game.progress)
            begin_celebration()
        end
        if game.celebration ~= nil then
            game.celebration.t = game.celebration.t + dt
        end
    end
    update_pending_flight(dt)
    update_counter_pulse(dt)
end

local function draw_reset_hint(W, H)
    if game.f1_hold <= 0 or game.f1_fired then return end
    render.draw_reset_overlay(game.f1_hold / F1_RESET_HOLD_SECONDS, W, H)
end

function love.draw()
    local W, H, ox, oy = viewport()
    -- Letterbox any host viewport that isn't already 9:16: fill with
    -- black, then translate into the inscribed content rect.
    if ox > 0 or oy > 0 then
        love.graphics.clear(0, 0, 0)
    end
    love.graphics.push()
    love.graphics.translate(ox, oy)
    if game.mode == "menu" then
        if #game.boxes == 0 then
            love.graphics.clear(0.1, 0.1, 0.13)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.printf(
                "No boxes configured.\nEdit levels/boxes.lua to add some.",
                0, H / 2 - 20, W, "center"
            )
        else
            -- Display-state: show the lagging count while a flight is
            -- in progress so the badge can tick up jewel-by-jewel.
            local display_state = nil
            if game.pending_flight ~= nil or game.counter_pulse ~= nil then
                local displayed = game.progress.jewels
                if game.pending_flight ~= nil then
                    displayed = game.pending_flight.displayed_count
                end
                display_state = {
                    displayed_count = displayed,
                    pulse_scale = counter_pulse_scale(),
                }
            end
            render.draw_menu(game.menu, progression, game.thumbnails, W, H, display_state)
            if game.pending_flight ~= nil and game.particles ~= nil then
                -- Particles must draw on top of the menu chrome during flight.
                game.particles:draw()
            end
            render.draw_flight_overlay(game.pending_flight, game.particles, game.menu, W, H)
        end
    elseif game.level == nil then
        love.graphics.clear(0.1, 0.1, 0.13)
    else
        -- Rebuild layout from the live view each frame so pan/zoom changes
        -- apply immediately and compute_layout re-clamps pan to the board.
        game.layout = render.compute_layout(game.level, W, H, game.view)
        game.level.layout = game.layout
        render.draw(game.level, game.layout, game.mouse.x, game.mouse.y, game.particles)
        render.draw_celebration(game.celebration, game.particles, game.confetti, W, H)
        -- Tutorial sits above everything but the F1-reset hint so a player
        -- can always bail. Gated to "playing" mode so it can't co-occur
        -- with the menu.
        if game.celebration == nil then
            render.draw_tutorial_overlay(game.tutorial, W, H)
        end
    end
    draw_reset_hint(W, H)
    love.graphics.pop()
end

-- Press-inside-button sets celebration.button_pressed; only armed once
-- celebration has reached its tappable phase.
local function try_press_complete_button(sx, sy)
    if not celebration_button_active() then return false end
    local bx, by, bw, bh = render.celebration_button_rect(viewport())
    if sx >= bx and sx <= bx + bw and sy >= by and sy <= by + bh then
        game.celebration.button_pressed = true
        return true
    end
    return false
end

-- Release on Complete button: fires the return if release lands inside
-- the same button rect.
local function try_release_complete_button(sx, sy)
    if game.celebration == nil or not game.celebration.button_pressed then
        return false
    end
    game.celebration.button_pressed = false
    local bx, by, bw, bh = render.celebration_button_rect(viewport())
    if sx >= bx and sx <= bx + bw and sy >= by and sy <= by + bh then
        begin_return_flight()
        return true
    end
    return false
end

-- Hit-test helper: is (sx, sy) inside rect-with-xywh shape?
local function point_in_rect(rect, sx, sy)
    return rect ~= nil
        and sx >= rect.x and sx <= rect.x + rect.w
        and sy >= rect.y and sy <= rect.y + rect.h
end

local function dismiss_tutorial()
    if game.tutorial == nil then return end
    game.tutorial.active = false
    game.tutorial = nil
    progression.mark_tutorial_seen(game.progress, TUTORIAL_ZOOM_PAN)
    progression.save(game.progress)
end

local function handle_press(sx, sy)
    if game.mode == "menu" then
        local W, H = viewport()
        game.menu:handle_tap(sx, sy, W, H)
        return
    end
    -- Playing mode.
    if game.level == nil then return end
    -- Tutorial overlay swallows all presses: any click closes it so the
    -- player never gets stuck behind the modal.
    if game.tutorial ~= nil and game.tutorial.active then
        dismiss_tutorial()
        return
    end
    if game.celebration ~= nil then
        try_press_complete_button(sx, sy)
        return
    end
    -- Back button (top-left header) bails to the menu. Intercept before
    -- the tap reaches the grid/shelf classifier. Return any held cluster
    -- cleanly first so the level state is tidy if the player comes back.
    if point_in_rect(game.layout and game.layout.back_button_rect, sx, sy) then
        if game.level.state and game.level.state.kind == "hovering" then
            game.level:cancel_hover()
        end
        return_to_menu()
        return
    end
    -- Controls hint plaque (top-right header) reopens the tutorial.
    if point_in_rect(game.layout and game.layout.hint_button_rect, sx, sy) then
        game.tutorial = { active = true, key = TUTORIAL_ZOOM_PAN }
        return
    end
    local tap = input.classify(game.level, game.layout, sx, sy)
    input.dispatch(game.level, tap)
end

local function handle_release(sx, sy)
    if game.mode == "menu" then
        local W, H = viewport()
        game.menu:handle_release(sx, sy, W, H)
        if game.menu.play_pending ~= nil then
            local pending = game.menu.play_pending
            game.menu.play_pending = nil
            start_puzzle(pending.box_idx, pending.puzzle_idx)
        end
        return
    end
    if game.mode == "playing" and game.celebration ~= nil then
        try_release_complete_button(sx, sy)
    end
end

-- Decide whether LMB should start a background pan drag instead of
-- tapping through to the level. Returns true iff pan was started.
local function maybe_start_lmb_pan(x, y)
    if game.mode ~= "playing" then return false end
    if game.level == nil or game.view == nil or game.layout == nil then return false end
    if game.celebration ~= nil then return false end
    if game.tutorial ~= nil and game.tutorial.active then return false end
    -- Don't interleave with an already-active RMB drag; one pan at a time.
    if game.view.rmb_drag ~= nil then return false end
    -- Header-band controls (Back / hint) are not "background".
    if point_in_rect(game.layout.back_button_rect, x, y) then return false end
    if point_in_rect(game.layout.hint_button_rect, x, y) then return false end
    -- If a cluster is being hovered, LMB-outside must fall through to
    -- cancel_hover (dropping-outside semantics), not start a pan.
    if game.level.state and game.level.state.kind ~= "idle" then return false end
    local tap = input.classify(game.level, game.layout, x, y)
    if tap.kind ~= "outside" then return false end
    game.view.lmb_drag = { last_x = x, last_y = y }
    return true
end

function love.mousepressed(x, y, button)
    x, y = to_content(x, y)
    if button == 2 then
        -- RMB starts a pan drag on the puzzle screen. Swallowed on the
        -- menu so right-clicks never fire selection/back-button presses.
        if game.mode == "playing" and game.view ~= nil then
            game.view.rmb_drag = { last_x = x, last_y = y }
        end
        return
    end
    if button ~= 1 then return end
    if maybe_start_lmb_pan(x, y) then return end
    handle_press(x, y)
end

function love.mousereleased(x, y, button)
    x, y = to_content(x, y)
    if button == 2 then
        if game.view ~= nil then
            game.view.rmb_drag = nil
        end
        return
    end
    if button ~= 1 then return end
    if game.view ~= nil and game.view.lmb_drag ~= nil then
        -- LMB was claimed by a background-pan drag; swallow the release so
        -- it can't be interpreted as a tap-release on any button.
        game.view.lmb_drag = nil
        return
    end
    handle_release(x, y)
end

function love.mousemoved(x, y, _dx, _dy)
    x, y = to_content(x, y)
    if game.mode ~= "playing" or game.view == nil then return end
    -- Integrate against our own last-position so pan tracks cleanly even
    -- if love's dx/dy is frame-batched differently than events. Both LMB
    -- (background) and RMB drags share the same pan accumulator.
    local drag = game.view.rmb_drag or game.view.lmb_drag
    if drag ~= nil then
        game.view.pan_x = game.view.pan_x + (x - drag.last_x)
        game.view.pan_y = game.view.pan_y + (y - drag.last_y)
        drag.last_x = x
        drag.last_y = y
    end
end

function love.wheelmoved(_dx, dy)
    if dy == 0 then return end
    if game.mode ~= "playing" or game.view == nil or game.layout == nil then return end
    local factor = 1 + dy * WHEEL_ZOOM_STEP
    local mx, my = love.mouse.getPosition()
    mx, my = to_content(mx, my)
    zoom_view_at(game.view, game.layout, mx, my, factor)
end

local function count_touches()
    if game.view == nil then return 0 end
    local n = 0
    for _ in pairs(game.view.touches) do n = n + 1 end
    return n
end

local function two_touch_centroid()
    local a, b
    for _, t in pairs(game.view.touches) do
        if a == nil then a = t
        elseif b == nil then b = t; break end
    end
    if a == nil or b == nil then return nil end
    local midx = (a.x + b.x) / 2
    local midy = (a.y + b.y) / 2
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dist = math.sqrt(dx * dx + dy * dy)
    return midx, midy, dist
end

function love.touchpressed(id, x, y)
    x, y = to_content(x, y)
    if game.mode == "playing" and game.view ~= nil then
        game.view.touches[id] = { x = x, y = y }
        if count_touches() >= 2 then
            -- Second finger down: switch into a gesture. If a tap from the
            -- first finger already opened a hover cluster, that hover stays
            -- — gesture is pan/zoom only and doesn't mutate game state.
            local mx, my, d = two_touch_centroid()
            game.view.gesture = { midx = mx, midy = my, dist = d }
            return
        end
    end
    handle_press(x, y)
end

function love.touchmoved(id, x, y, _dx, _dy)
    x, y = to_content(x, y)
    if game.mode ~= "playing" or game.view == nil then return end
    local t = game.view.touches[id]
    if t == nil then return end
    t.x = x
    t.y = y
    if count_touches() < 2 or game.view.gesture == nil then return end
    local mx, my, d = two_touch_centroid()
    if mx == nil then return end
    local last = game.view.gesture
    if d > 0 and last.dist > 0 then
        zoom_view_at(game.view, game.layout, mx, my, d / last.dist)
    end
    -- Pan the view by the drift of the midpoint.
    game.view.pan_x = game.view.pan_x + (mx - last.midx)
    game.view.pan_y = game.view.pan_y + (my - last.midy)
    game.view.gesture = { midx = mx, midy = my, dist = d }
end

function love.touchreleased(id, x, y)
    x, y = to_content(x, y)
    if game.mode == "playing" and game.view ~= nil then
        local was_gesture = game.view.gesture ~= nil
        if game.view.touches[id] ~= nil then
            game.view.touches[id] = nil
        end
        if count_touches() < 2 then
            game.view.gesture = nil
        end
        -- Any release that was part of a gesture is swallowed — we don't
        -- want lifting the last finger of a pinch to fire a tap-release.
        if was_gesture then return end
    end
    handle_release(x, y)
end

function love.keypressed(key)
    if game.mode == "menu" then
        local consumed = game.menu:handle_key(key)
        if consumed ~= nil then return end
        if key == "escape" then
            love.event.quit()
        end
        return
    end

    -- Playing mode
    if game.celebration ~= nil then
        -- Esc skips the celebration + any flight (power-user exit).
        -- R / N are ignored while celebration is on screen so the player
        -- doesn't blow past the reward they just earned.
        if key == "escape" then
            skip_celebration_to_menu()
        end
        return
    end

    if key == "escape" then
        return_to_menu()
    elseif key == "r" then
        -- Reshuffle current puzzle.
        if game.current ~= nil then
            start_puzzle(game.current.box_idx, game.current.puzzle_idx)
        end
    elseif key == "n" then
        -- Advance to next puzzle in same box; if past last, return to menu.
        if game.current ~= nil then
            local box = game.boxes[game.current.box_idx]
            local next_idx = game.current.puzzle_idx + 1
            if box and box.puzzles and next_idx <= #box.puzzles then
                start_puzzle(game.current.box_idx, next_idx)
            else
                return_to_menu()
            end
        end
    end
end
