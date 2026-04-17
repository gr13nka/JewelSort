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
}

local F1_RESET_HOLD_SECONDS = 3

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

local function start_puzzle(box_idx, puzzle_idx)
    local box = game.boxes[box_idx]
    if box == nil then return end
    local puzzle = (box.puzzles or {})[puzzle_idx]
    if puzzle == nil then return end
    local desc = game.descriptors[puzzle.id]
    if desc == nil then return end
    game.level = Level.new(desc)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    game.layout = render.compute_layout(game.level, w, h)
    game.current = { box_idx = box_idx, puzzle_idx = puzzle_idx, puzzle = puzzle }
    game.mode = "playing"
    game.celebration = nil
    game.pending_flight = nil
    if game.particles then game.particles:clear() end
end

local function return_to_menu()
    game.level = nil
    game.layout = nil
    game.current = nil
    game.mode = "menu"
    game.celebration = nil
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
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
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
                    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
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
        game.mouse.x, game.mouse.y = love.mouse.getPosition()
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
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
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
        render.draw(game.level, game.layout, game.mouse.x, game.mouse.y, game.particles)
        render.draw_celebration(game.celebration, game.particles, game.confetti, W, H)
    end
    draw_reset_hint(W, H)
end

-- Press-inside-button sets celebration.button_pressed; only armed once
-- celebration has reached its tappable phase.
local function try_press_complete_button(sx, sy)
    if not celebration_button_active() then return false end
    local bx, by, bw, bh = render.celebration_button_rect(
        love.graphics.getWidth(), love.graphics.getHeight()
    )
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
    local bx, by, bw, bh = render.celebration_button_rect(
        love.graphics.getWidth(), love.graphics.getHeight()
    )
    if sx >= bx and sx <= bx + bw and sy >= by and sy <= by + bh then
        begin_return_flight()
        return true
    end
    return false
end

local function handle_press(sx, sy)
    if game.mode == "menu" then
        game.menu:handle_tap(sx, sy, love.graphics.getWidth(), love.graphics.getHeight())
        return
    end
    -- Playing mode.
    if game.level == nil then return end
    if game.celebration ~= nil then
        try_press_complete_button(sx, sy)
        return
    end
    -- Back button (top-left header) bails to the menu. Intercept before
    -- the tap reaches the grid/shelf classifier. Return any held cluster
    -- cleanly first so the level state is tidy if the player comes back.
    local b = game.layout and game.layout.back_button_rect
    if b ~= nil
        and sx >= b.x and sx <= b.x + b.w
        and sy >= b.y and sy <= b.y + b.h then
        if game.level.state and game.level.state.kind == "hovering" then
            game.level:cancel_hover()
        end
        return_to_menu()
        return
    end
    local tap = input.classify(game.level, game.layout, sx, sy)
    input.dispatch(game.level, tap)
end

local function handle_release(sx, sy)
    if game.mode == "menu" then
        game.menu:handle_release(sx, sy, love.graphics.getWidth(), love.graphics.getHeight())
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

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    handle_press(x, y)
end

function love.mousereleased(x, y, button)
    if button ~= 1 then return end
    handle_release(x, y)
end

function love.touchpressed(_id, x, y)
    handle_press(x, y)
end

function love.touchreleased(_id, x, y)
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
