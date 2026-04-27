# JewelSort

A casual jewel-sorting puzzle in LÖVE2D 11.x. The player restores a
pixel-art image by shuffling colored jewels into cells whose target color
matches. Levels are PNG files dropped into `levels/` — every opaque pixel
becomes one grid cell whose target color is that pixel's RGB; alpha 0
means "no cell here."

## Run / build

- Desktop: `love .`
- Web: `./tools/build_web.sh` — packs a `.love`, runs `love.js
  --compatibility`, then calls `./tools/patch_web.sh` to overwrite the
  generated `index.html` + `yabridge.js` with Yandex-CSP-safe versions.
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

The Yandex target uses **Davidobot's love.js** (Emscripten + WebAssembly,
LÖVE 11.5) built with `--compatibility`. The `Fengari` note in earlier
revisions of this doc was wrong — there is no Fengari involved. The
remaining hygiene rules still apply because they're cheap and help
every web target:

- **Zero `goto` statements** in any `.lua` file. Use early returns, break,
  or extracted helpers. Verify with
  `grep -rn "goto" --include="*.lua" .` — only comments should match.
- **No recursion** in flood-fill. `src/cluster.lua` uses an explicit queue
  with a head index.
- No `os.execute`, `io.popen`, FFI, `love.thread`, or screen-capture
  callbacks. All asset access goes through `love.filesystem`.

## Yandex Games deployment (status + architecture)

The game targets `yandex.ru/games/app/522978` as a developer draft.
A lot of decisions here are load-bearing and non-obvious — read before
touching `tools/patch_web.sh`, `src/platform.lua`, `src/i18n.lua`, or
the font-loading in `src/render.lua`.

### Build pipeline

```
./tools/build_web.sh
  → zips main.lua/conf.lua/src/levels/assets/locale → /tmp/*.love
  → runs `npx love.js --compatibility` → build/web/{game.js,game.data,love.js,love.wasm}
  → ./tools/patch_web.sh overwrites build/web/{index.html,yabridge.js}
  → zips build/web → build/jewelsort.zip   (upload this to the Yandex console)
```

Every build stamps `BUILD_SHA` (short git sha + `+dirty` if uncommitted)
and `BUILT_AT` (UTC ISO) into three places so we can confirm which
code is actually deployed:

1. `<!-- build-id: <sha> built <ts> -->` in `index.html <head>`
2. `<canvas data-build="<sha>">` attribute (visible in devtools Elements)
3. `console.info('[yabridge] build <sha> loaded (<ts>)')` as the very
   first statement in `yabridge.js`

**If you don't see the `[yabridge] build …` log in devtools, the zip
did not deploy.** Check the Yandex console's build list — uploads may
require a separate "set as active draft" action.

### What the love.js build actually exports

`--compatibility` mode (needed because Yandex's host doesn't set
COOP+COEP, so SharedArrayBuffer is unavailable) exposes a specific
subset on `window.Module`:

- `Module["arguments"]` — set before `Love(Module)`; LÖVE reads as `love.load(args)`
- `Module["FS_createDataFile"]`, `Module["FS_unlink"]`, `Module["FS_createPath"]`
- `Module["onRuntimeInitialized"]`, `Module["print"]`, `Module["printErr"]`
- **Not exported**: `Module.FS`, `Module.FS.readFile`, `Module.FS.writeFile`.
  Prior bridge versions tried to use these and failed silently. Do not
  reintroduce them.

### SDK bridge architecture (asymmetric on purpose)

- **Lua → JS**: Lua emits `print("YA_CMD:<cmd> <args>")`. JS overrides
  `Module.print` (see `onLuaPrint` in `yabridge.js`), intercepts the
  `YA_CMD:` prefix, and dispatches to `ysdk.*`. Non-prefixed lines fall
  through to `console.log`.
- **JS → Lua**: JS writes events to `/__ya_in` via
  `Module.FS_unlink` + `Module.FS_createDataFile` (single-slot). Lua
  reads via `io.open` in `src/platform.lua:tick()` each frame. Lua-side
  FS access works; only the JS side lacks readFile.
- **Locale**: uses neither channel. Passed as `--lang=<code>` in
  `Module.arguments` (set synchronously from `?lang=` URL param in
  `yabridge.js`) and parsed in `main.lua:love.load`.

### Russian localization

- Strings in `locale/{en,ru}.lua` via `src/i18n.lua`
- `i18n.t()` for plain strings, `i18n.t_plural(key, n)` for CLDR plural
  forms (Russian needs `one/few/many`)
- **Font with Cyrillic**: `assets/fonts/Alegreya-Bold.ttf` is the
  single bundled face for both locales — Alegreya has full Latin +
  Cyrillic coverage, and the Bold weight reads cleanly on painted
  leather and gold-foil titles where Regular looks too thin. No
  fallback chain is needed.
  Background: LÖVE's built-in default font would work for Latin-only,
  but the love.js `--compatibility` build strips the default font
  table, so any face with partial Cyrillic coverage rendered Russian
  as invisible zero-width glyphs. Shipping a single full-coverage TTF
  sidesteps that. `Alegreya-Regular.ttf`, `Rubik-Regular.ttf`, and
  `FredokaOne-Regular.ttf` remain in `assets/fonts/` for now but are
  unreferenced from code; see `src/render.lua:font_body/font_small`.

### Publishing gate

Yandex moderation requires:

- `features.LoadingAPI.ready()` fires — handled early in `yabridge.js`
  `connectSdk()` so Yandex's preloader gets out of the way while the
  game's own splash animates
- `features.GameplayAPI.start/stop` wraps each puzzle session
- Game pauses (`game.paused = true`) and audio mutes during fullscreen
  ads — we don't ship audio, and `love.update` is gated on the flag
- ≥10 min gameplay, no crashes on resize — the CSS letterbox
  (`min(100vw, calc(100vh * 9 / 16))`) handles resize with no Lua-side
  cooperation; LÖVE stays at its `conf.lua` 540×960 buffer

See `.claude/plans/vectorized-twirling-squid.md` for the most recent
deployment postmortem.

## Web loading splash (pre-Lua)

The animated splash shown while `love.js` / `love.wasm` / `game.data`
download lives in `tools/patch_web.sh` as a heredoc that writes
`build/web/yabridge.js`. It runs in plain Canvas2D **before Lua is
alive**, so:

- **Palette is duplicated.** The splash can't `require` `src/wood.lua`;
  its `PAL` / `JEWELS` tables in yabridge.js are hand-copied hex. If
  you retune `wood.palette`, re-tune the splash too or it'll read as a
  different game.
- **Strings are duplicated.** The `STRINGS` table (en/ru "Loading…")
  can't pull from `locale/*.lua` — those are inside `game.data`, which
  is the thing we're waiting on. Keep the two strings short and
  re-sync on any localization pass.
- **Locale comes from the URL.** `?lang=xx` query param first (Yandex
  always embeds with it), `navigator.language` fallback. The Lua-side
  locale read via `/__ya_locale` only arrives post-splash.
- **Single `rAF` loop**, canceled in `Module.setStatus('')` when
  `remainingDependencies === 0`. Don't leak it past the teardown.

## UI / visuals

Full contract in **`UI-SPEC.md`** at the repo root — font sizes,
palette, layout proportions, interaction states, copywriting rules,
per-element source references. Read it before changing anything the
player sees.

Key invariants (so the aesthetic doesn't drift between edits):

- **Saturation discipline.** The only saturated pixels on screen should
  be jewels, their target rings, medals, the jewel badge, and the red
  flash text. All chrome is wood / parchment / ink / foil.
- **Two font sizes only:** 32 px body, 22 px small — both Alegreya
  Bold from `assets/fonts/Alegreya-Bold.ttf`. Adding a third size
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
tools/build_web.sh      packs .love, runs love.js --compatibility, patches
tools/patch_web.sh      writes build/web/{index.html, yabridge.js}; holds
                        the animated pre-Lua loading splash as a heredoc
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
