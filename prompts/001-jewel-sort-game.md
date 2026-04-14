<objective>
Build a playable prototype of a casual jewel-sorting puzzle game in LÖVE2D, web-build ready (love.js compatible — no `goto` statements anywhere). The player restores a pixel-art image by sorting colored jewels into matching slots. The game must load levels purely from PNG files dropped into a folder, with zero per-level config required.

End goal: a runnable prototype that proves the core sort-by-tap-and-chain mechanic, builds for desktop LÖVE and for the web via love.js, and lets a non-programmer add a new level by saving a PNG.
</objective>

<context>
- Engine: LÖVE2D 11.x (latest stable)
- Target builds: desktop LÖVE for development; love.js web build for distribution
- Orientation: portrait mobile (9:16 reference, 1080×1920 design space), input via mouse/touch
- Polish target: playable prototype — solid mechanics, minimal art (flat-color jewels, simple UI), no sound or animation polish required beyond what makes the game readable
- The web build constraint means: no `goto` statements (love.js / Fengari does not support them), no FFI, no os.execute, no threading. Stick to portable Lua + LÖVE APIs.
- No existing codebase — this is greenfield in the working directory.
</context>

<inspiration>
The mechanic is inspired by the "Pixle / jewel coloring sort" mobile game. Key gameplay rules to implement:

1. Each opaque pixel of the source PNG becomes a square cell on a grid, with a round hole in the middle and a target color (the pixel's RGB).
2. Each cell expects a jewel of its target color seated in the hole. At level start, jewels are shuffled into wrong cells.
3. A shelf (panel below the image grid) holds jewels temporarily — initially empty.
4. **Tap a jewel**: that jewel and all flood-filled adjacent same-color jewels currently sitting in cells "lift" together (hover state, visually offset above their cells).
5. **Tap the shelf** while a cluster is hovering: the hovered cluster flies to the shelf, leaving those cells empty (holes visible).
6. **Tap a jewel cluster on the shelf**: it lifts (hovers) the same way — all same-color jewels on the shelf hover as one cluster.
7. **Tap an empty hole** while a hovered cluster's color matches that hole's target color: the cluster flies into that hole AND flood-fills into all adjacent connected empty holes of the same target color, consuming jewels from the cluster until either the cluster is empty or no more matching adjacent holes exist.
8. **Win condition**: every cell holds a jewel of its correct target color. The shelf may or may not be empty — choose the simpler rule (cells-only) and document the choice in the README.
</inspiration>

<requirements>

**Project structure** (create all of these):
- `main.lua` — LÖVE entry point (`love.load`, `love.update`, `love.draw`, `love.mousepressed` / `love.touchpressed`)
- `conf.lua` — LÖVE config: window 540×960 (portrait, scaled down from 1080×1920), title, identity, web-friendly settings
- `src/level_loader.lua` — scans `levels/` folder, loads each PNG via `love.image.newImageData`, walks pixels to build a level table: `{ width, height, cells = {{x, y, color}, ...}, palette = {color1, color2, ...} }`. Treats alpha == 0 as empty (no cell).
- `src/level.lua` — runtime level state: grid of cells, shelf contents, current hover cluster, win check
- `src/input.lua` — unified tap handler that works for both mouse and touch (web/desktop), translating screen coords to grid/shelf coords
- `src/render.lua` — draws the cell grid, holes, jewels, shelf, hover cluster
- `src/cluster.lua` — flood-fill helper (4-connected) for finding same-color adjacent jewels in cells, and same-color jewels on the shelf
- `src/shuffle.lua` — deterministic-or-random shuffle that guarantees the start state is solvable but not already solved
- `levels/` — folder containing example PNGs (include 2-3 tiny example levels, e.g. an 8×8 smiley and a 12×12 heart). If you cannot author binary PNGs directly, write a one-off generator at `tools/make_samples.lua` that uses `love.image.newImageData` + `setPixel` + `:encode('png', ...)` and run it once, then commit the resulting PNGs.
- `README.md` — one page: how to run desktop, how to build web with love.js, how to add a level (just drop a PNG)

**Core mechanics** (in `src/level.lua` + `src/cluster.lua`):
- On level load, build cells from PNG, then shuffle jewels among cells so most cells start with the wrong color.
- State machine for hover: `idle` → `hovering(color, source)` where source is `:grid` or `:shelf`.
- Tap dispatch:
  - Tap on a jewel in a cell while idle → enter `hovering` with flood-filled cluster of that color from that cell.
  - Tap on a jewel on the shelf while idle → enter `hovering` with all same-color jewels on shelf.
  - Tap on the shelf while hovering a grid cluster → move all hovered jewels to shelf, return to idle.
  - Tap on an empty hole while hovering, IF hole's target color == cluster color → flood-fill the cluster into that hole and all 4-connected adjacent empty holes with the same target color; if cluster runs out partway, stop; remaining cluster jewels go back where they came from (or stay on shelf). Return to idle.
  - Tap anywhere else while hovering → cancel hover (jewels return to source).
- Win: every cell's current jewel color == cell's target color. Show a simple "Solved!" overlay.

**Web compatibility** — these are non-negotiable:
- ZERO `goto` statements anywhere in the codebase. Use early returns, `break` from loops, or restructured conditionals instead.
- No `os.execute`, no `io.popen`, no LuaJIT FFI, no `love.thread`, no `love.system.openURL` in core loop.
- Use `love.filesystem` for all asset access (works in love.js sandbox).
- Avoid `love.graphics.captureScreenshot` callback patterns that some love.js versions miss — render straight to screen.

</requirements>

<implementation>

**Why no `goto`**: love.js compiles Lua to JavaScript via Fengari, which historically has incomplete or buggy support for `goto`/labels. Restructure any "continue" patterns as nested `if` blocks or extracted helper functions returning early.

**Why PNG-only levels**: the user explicitly wants level creation to be "just drop a PNG in a folder." Color is the only metadata needed — pixel color = target jewel color, alpha 0 = no cell. Group same-RGB pixels into the palette automatically. No JSON, no Lua config, no naming convention required.

**Why flood-fill clusters**: matches the source game's feel where tapping one jewel reacts with all touching same-color neighbors as a single unit. Use iterative BFS with a stack/queue (NOT recursion — recursion can blow the small JS stack in love.js for large levels). 4-connected only.

**Layout for portrait**:
- Top 2/3 of screen: the puzzle grid, scaled so the longest pixel-art axis fits with margin.
- Bottom 1/3: the shelf, a horizontally-scrollable strip showing displaced jewels grouped/spaced so same-color jewels appear adjacent (so tapping one selects the visual cluster).
- Cell size: `min(grid_area_w / cols, grid_area_h / rows)`.

**Render style for prototype**:
- Cells: dark gray rounded-rect background (`love.graphics.rectangle('fill', ..., r, r)`) with a darker circular hole punched visually (just draw a dark circle on top).
- Jewels: filled circle of cell's current jewel color, slightly smaller than the hole, drawn raised when hovering (offset Y by ~10px and add a soft shadow rectangle below).
- Shelf jewels: same circles, lined up.

**Shuffle**: collect all expected jewels (one per cell), shuffle the list with Fisher-Yates using `love.math.random`, assign back to cells. After shuffle, if accidentally solved, swap two non-matching jewels.

</implementation>

<output>
Create the following files with relative paths from the project root:

- `./main.lua` — LÖVE entry, wires modules together, calls level_loader on startup, dispatches input
- `./conf.lua` — window/build config
- `./src/level_loader.lua` — PNG → level data
- `./src/level.lua` — runtime level state + tap state machine + win check
- `./src/cluster.lua` — iterative BFS flood-fill helpers (NO recursion, NO goto)
- `./src/shuffle.lua` — Fisher-Yates with solvability guard
- `./src/input.lua` — unified mouse/touch → semantic tap
- `./src/render.lua` — draws grid, shelf, hover cluster, win overlay
- `./tools/make_samples.lua` — one-off generator for example PNGs (run via `love tools/make_samples.lua` or similar)
- `./levels/sample_smile.png` — 8×8 example level
- `./levels/sample_heart.png` — 12×12 example level
- `./README.md` — run instructions (desktop + love.js web build), how to add a level

</output>

<verification>

Before declaring complete, verify ALL of the following:

1. **Grep self-check**: search the entire codebase for `goto` — must return zero matches in `.lua` files. Run: `grep -rn "goto" --include="*.lua" .` (output must be empty).
2. **Desktop run**: `love .` launches into a level showing a shuffled puzzle with visible cells, holes, jewels, and a shelf.
3. **Tap flow**: tapping a jewel visibly hovers it + same-color neighbors; tapping the shelf moves them; tapping a matching empty hole fills it and floods adjacent matching holes.
4. **Win detection**: solving the level (manually or trivially by un-shuffling) triggers a "Solved!" overlay.
5. **Add-a-level test**: copying a new tiny PNG into `levels/` and restarting picks it up automatically — no code changes needed.
6. **Web-build readiness**: no FFI, no threads, no os.execute, no love.thread, no goto. README documents the love.js build command (e.g. `npx love.js . build/web --title "JewelSort"`).
7. **No recursion in flood-fill**: `cluster.lua` uses an explicit stack/queue, not recursive function calls. (Justification: love.js JS-stack is small.)

</verification>

<success_criteria>

- Project runs on desktop LÖVE 11.x with `love .`
- Zero `goto` statements anywhere in the Lua source
- A level loads from a PNG in `./levels/` with no extra config
- Player can tap-hover-cluster, move clusters to shelf, and refill matching holes via flood-fill
- Win state is detected and shown
- Adding a new level requires only adding a PNG file
- README explains both desktop run and love.js web build steps

</success_criteria>
