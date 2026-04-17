# JewelSort

A casual jewel-sorting puzzle in LÖVE2D 11.x. The player restores a
pixel-art image by shuffling colored jewels into cells whose target color
matches. Levels are PNG files dropped into `levels/` — every opaque pixel
becomes one grid cell whose target color is that pixel's RGB; alpha 0
means "no cell here."

## Run / build

- Desktop: `love .`
- Web: `npx love.js . build/web --title "JewelSort"`
- Reshuffle current level: press **R**. Next level: **N**. Quit: **Esc**.

## Core mechanic

1. Tap a jewel in a grid cell → it and its 8-connected same-color neighbors
   "lift" as a cluster.
2. Tap the shelf while hovering → the cluster parks on the shelf (rejected
   if capacity would be exceeded; hover state stays, red "Shelf full!"
   flash shows).
3. Tap a shelf jewel → lifts all same-color jewels on the shelf as one
   cluster.
4. Tap an empty hole while hovering, if the hole's target color matches
   the cluster → cluster flood-fills into that hole and every 8-connected
   empty hole of the same target. Overflow returns to source.
5. Tap anywhere else while hovering → cancel (jewels return to source).
6. **Win** = every grid cell holds a jewel of its target color. Shelf may
   be nonempty.

## Non-obvious rules

- **Locked jewels.** A jewel whose color already matches its cell's target
  is locked: it can't be lifted and acts as a flood-fill barrier. This
  is enforced in `cluster.flood_jewel_cluster` — the starting cell
  returns `{}` if locked, and other locked cells are skipped during BFS
  expansion. No special visual: the jewel color already matches its
  target ring, so a locked cell reads as "settled" by sitting flush
  inside its own color.
- **Cells are tinted with their target color** (dimmed 55% / hole 25%) so
  an empty hole always visually advertises which color it needs.
- **Shelf cap** is a single constant: `M.SHELF_CAPACITY` in
  `src/shuffle.lua`. `level.lua` reads it at construction.

## Shuffle + solvability

- Fisher-Yates permutation across cells, validated by a cheap greedy
  solver on a snapshot before acceptance. Reshuffles up to 20 times if
  the greedy solver fails. Minimum 30% mismatch ratio enforced so the
  puzzle isn't trivially pre-solved.
- **Why not a forward-play scrambler?** Forward moves only deposit a
  jewel into a target-matching cell, so from the solved state forward
  play can never create a true mismatch. A previous version had this bug;
  it produced only 2-cell fallback swaps. Don't reintroduce it.

## Web-build constraints (hard)

These are non-negotiable because love.js runs Lua through Fengari on a
small JS stack with incomplete `goto` support:

- **Zero `goto` statements** in any `.lua` file. Use early returns, break,
  or extracted helpers. Verify with
  `grep -rn "goto" --include="*.lua" .` — only comments should match.
- **No recursion** in flood-fill. `src/cluster.lua` uses an explicit queue
  with a head index.
- No `os.execute`, `io.popen`, FFI, `love.thread`, or screen-capture
  callbacks. All asset access goes through `love.filesystem`.

## UI / visuals

Full contract in **`UI-SPEC.md`** at the repo root — font sizes,
palette, layout proportions, interaction states, copywriting rules,
per-element source references. Read it before changing anything the
player sees.

Key invariants (so the aesthetic doesn't drift between edits):

- **Saturation discipline.** The only saturated pixels on screen should
  be jewels, their target rings, medals, the jewel badge, and the red
  flash text. All chrome is wood / parchment / ink / foil.
- **Two font sizes only:** 32 px body, 22 px small — both Fredoka One
  from `assets/fonts/FredokaOne-Regular.ttf`. Adding a third size
  requires updating `UI-SPEC.md`.
- **Text goes through `print_engraved`** (in `render.lua`), not raw
  `love.graphics.print` — every label carries its 1px engraved shadow.
- **Panels go through `wood.draw_panel`**, not raw rectangles. New
  surface kinds are added in `wood.lua`'s `tones()` table and cached by
  `wood.panel`.
- **Palette is centralized in `wood.palette`.** Do not inline RGB
  triples in `render.lua` for chrome colors; jewel colors are the
  exception — they're data from the level PNG.
- **Layout is proportional to `cell_size`.** The magic numbers 0.18
  (lift), 0.34 (jewel r), 0.36 (hole r), 0.38 (shelf jewel r), 0.46
  (ring r) are the real design tokens. Don't hardcode pixel radii.

## File layout

```
main.lua                LÖVE entry; input dispatch; R/N/Esc keys
conf.lua                540×960 portrait window, trimmed modules
src/level_loader.lua    PNG → level descriptor (alpha 0 = no cell)
src/level.lua           runtime state, tap state machine, win check,
                        flash timer, shelf-cap rejection
src/cluster.lua         iterative BFS flood-fill; lock rule enforced
src/shuffle.lua         Fisher-Yates + greedy-solver sanity check;
                        holds SHELF_CAPACITY
src/input.lua           mouse/touch → semantic tap (grid/shelf/outside)
src/render.lua          grid, holes, jewels, lock rings, shelf slots,
                        shelf-count label, flash text, win overlay
tools/make_samples.lua  in-engine sample generator (runs on empty levels/)
tools/make_samples.py   pure-stdlib repo-seeding PNG generator
levels/*.png            source-of-truth level data
```

## Adding a level

Save any small PNG (a few dozen pixels per axis is ideal) into `levels/`.
Each opaque pixel becomes a cell with that pixel's color as its target.
No code changes, no naming convention. Restart the game; the loader
scans `levels/` on startup.

## Tap→semantic coord translation

`src/input.lua` converts raw mouse/touch coords into one of:

- `{ kind = "grid", gx, gy }`
- `{ kind = "shelf", index }` (0 = tapped empty shelf region)
- `{ kind = "outside" }`

The grid/shelf pixel rects live in the layout table produced by
`render.compute_layout`. `render.screen_to_shelf` takes the shelf
capacity so slot widths are based on the cap (empty slots visible on
the right), not the current shelf length.
