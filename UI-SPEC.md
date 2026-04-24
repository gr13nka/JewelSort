---
project: JewelSort
engine: LÖVE 11.4
status: reference
created: 2026-04-14
---

# JewelSort — UI Design Contract

> Visual and interaction reference for the game's existing UI. Captures
> the "cozy wooden puzzle box" aesthetic already realized in
> `src/render.lua` + `src/wood.lua` so future changes stay coherent.
>
> Not a planning document — if something here and the code disagree,
> the code wins and this file should be updated.

---

## Design System

| Property | Value |
|----------|-------|
| Engine | LÖVE 11.4 (Lua 5.1 via Fengari for web) |
| Rendering | 100% procedural — `love.graphics` primitives + baked Canvas panels |
| Component library | none (see `wood.draw_panel`, `render.draw_cell`, `render.draw_medal`) |
| Icon library | none — all glyphs are circles, rings, or text |
| Font | Fredoka One Regular (Google Fonts, SIL OFL) — `assets/fonts/FredokaOne-Regular.ttf` |
| Window | 540 × 960 portrait, non-resizable, vsync on (`conf.lua`) |
| Design space | 1080 × 1920 (2× the window; assume retina) |

**Aesthetic intent:** a wooden toy box. Warm pine desk, oak plaques,
walnut insets, parchment pages, leather-bound level "books". Jewels are
the only saturated elements — they pop against muted wood tones.

---

## Layout Scale

All layout is computed per-frame from the window size; there is no CSS
spacing scale. These are the declared constants.

| Token | Value | Usage | Source |
|-------|-------|-------|--------|
| `margin` | 16 px | Outer window margin (grid_area, shelf_area, parchment pages) | `render.compute_layout`, `render.draw_menu` |
| `grid_h_fraction` | 2/3 | Grid area occupies top ⅔ of the window, shelf the bottom ⅓ | `render.compute_layout` |
| `cell_size` | `floor(min(grid_w/cols, grid_h/rows))` | Square cell, centered in grid_area with leftover pixels as gutter | `render.compute_layout` |
| `board_pad` | 6 px | Extra padding of the "board" plaque outside `grid_area` | `render.draw` |
| `shelf slot` | `min(shelf_w / 8, shelf_h / 3 · 0.9)`, min 8 | Slot edge on the 3×8 shelf grid (8 columns, 3 rows, capacity 24) | `render.shelf_slot_size` |
| `shelf jewel r` | `floor(slot · 0.38)` | Shelf jewel radius (gem diameter through `draw_jewel_asset`) | `render.draw` |
| `grid jewel r` | `cell_size · 0.34` | Resting jewel radius in a cell (gem diameter through `draw_jewel_asset`) | `render.draw_cell` |
| `cell corner` | `cell_size · 0.08` | Rounded-corner radius on the target-color square tile | `render.draw_cell` |
| `slot tint` | `target_color · 0.35` | Multiplicative tint applied to the cream slot PNG so each cell's slot reads as a darker version of its target color | `render.draw_cell` |
| `jewel gem frac` | `0.85` | Fraction of the jewel PNG occupied by the visible gem (halo outside). Callers pass gem diameter; footprint derived as `gem / 0.85` | `render.draw_jewel_asset` |
| `lift` | `floor(cell_size · 0.18)` | Vertical offset for the hovering cluster | `render.draw` |
| `book spine` | 36 px | Left spine strip on a box card | `render.draw_box_card` |
| `medal small` / `medal celebration` | 22 / 56 px | Medal sizes (level tile / celebration card) | `render.draw_level_tile`, `render.draw_celebration` |
| `celebration panel` | `min(W-60, 420) × 280` | Multi-phase celebration parchment card | `render.draw_celebration` |
| `celebration title y` | `py + 20` (scale pivot `py + 36`) | "Solved!" title offset inside the card | `render.draw_celebration` |
| `celebration medal y` | `py + 74` | Medal top-left y inside the card (medal is 56 px, centered on `W/2`) | `render.draw_celebration` |
| `celebration line y` | `py + 156` | "+N jewel(s)" / "Already mastered" baseline y inside the card | `render.draw_celebration` |
| `complete button` | 200 × 64 px, 20 px from card bottom | Button on the celebration card | `render.celebration_button_rect` |
| `parchment edge frame` | 4 concentric 1 px line insets at alpha `0.10 + i · 0.05` (i = 0..3), drawn as explicit top/bottom/left/right `love.graphics.line` segments | Thin brown darkening around every parchment surface — must include the bottom edge (`rectangle("line", …)` at sub-pixel coords on a canvas drops the last row) | `wood.bake_parchment` |
| `jewel badge` | 96 × 34 px | Plaque-backed counter top-right on both menu screens | `render.draw_jewel_badge`, `menu:badge_rect` |
| `progress bar` | 8 segments, 10 px tall, 3 px gap | Solve-progress strip in its own 20 px band between the grid and the shelf (`p.w - 24` wide, 12 px inset) | `render.draw` |
| `in-puzzle back button` | 110 × 44 px, top-left at `(margin, margin)`, oak plaque + engraved "< Back" at 22 px | Returns to menu from gameplay; Escape still works as a shortcut | `render.draw`, `main.lua:handle_press` |
| `HUD title y` | 4 px | Top-centered "JewelSort — {level}" | `render.draw` |
| `HUD subtitle y` | 22 px | Hover hint text under the title | `render.draw` |

Rationale: the grid is fluid (levels are arbitrary widths × heights from
PNGs), so there is no fixed spacing scale — everything derives from
`cell_size`. Proportional constants (0.18, 0.34, 0.38, 0.08 corner,
0.35 slot tint) are the real design tokens and should be preserved if
touched.

---

## Typography

| Role | Size | Font | Where |
|------|------|------|-------|
| Body / titles | 32 px | Fredoka One | HUD title, level name, win panel, book titles |
| Small | 22 px | Fredoka One | Level tile label, box card progress ("3 / 8"), back button, locked-box hint, "Select a book" subtitle |

Only two sizes exist. Do not add a third without updating this file.
All text uses the `print_engraved` helper: a single-pixel-down black
shadow at 0.35α (or 0.2–0.5 per caller) behind the ink color. This is
the project's "typography primitive" — never draw bare text on wood.

---

## Color

Palette lives in `wood.palette`. Categories, not a 60/30/10 split —
this is a game, not a marketing page.

### Surfaces (muted, desaturated)

| Role | Token | Value | Where |
|------|-------|-------|-------|
| Desk backdrop | `desk` | 0.71 · 0.54 · 0.35 | Full-window background |
| Board inset | `walnut` (via `board`) | 0.32 · 0.20 · 0.10 | Recessed plaque behind grid |
| Oak plaque | `plaque` | 0.58 · 0.40 · 0.24 | Back button, empty target fallback |
| Shelf tray | `walnut` | 0.32 · 0.20 · 0.10 | Recessed shelf channel |
| Empty hole | `walnut_dark` | 0.18 · 0.10 · 0.05 | Empty shelf slot wells (grid cells now show a darkened-target-color slot via asset tint, not walnut) |
| Parchment page | `parchment` | 0.92 · 0.84 · 0.66 | Menu backdrops, win overlay |
| Cork tile | `cork` | 0.66 · 0.49 · 0.29 | Level thumbnail tiles |
| Locked wood | `locked` | 0.40 · 0.33 · 0.25 | Locked box cards, book spines |
| Leather (red/green/blue) | `leather_*` | see `wood.palette` | Box card covers, rotating by index mod 3 |

### Ink (text + engraved lines)

| Role | Token | Value | Usage |
|------|-------|-------|-------|
| Ink | `ink` | 0.16 · 0.09 · 0.04 | Primary text on parchment / light wood |
| Ink soft | `ink_soft` | 0.32 · 0.22 · 0.13 | Secondary text, hints |
| Ink light | `ink_light` | 0.95 · 0.88 · 0.72 | Text on dark wood (shelf count, back button) |
| Foil | `foil` | 0.94 · 0.82 · 0.48 | Gold-stamped book titles, spine bands, unlocked tile frame |

### Semantic / state

| Role | Value | Usage |
|------|-------|-------|
| Flash (error) | 0.80 · 0.20 · 0.18 | "Shelf full!" flash text only |
| Jewel highlight | rgba(1,1,1,0.25) | Specular dot on every jewel |
| Lift shadow | rgba(0,0,0,0.4) | Drop shadow under a lifted jewel |
| Medal bronze / silver / gold | see `MEDAL_COLORS` | Per-puzzle award tier |
| Badge blue | 0.35 · 0.85 · 1.00 | Jewel-count badge on menus |

### Jewels

Jewel colors are **data, not design tokens** — they come from the source
PNG pixels in `levels/*.png`. The design contract is: keep levels to a
small number of saturated, distinguishable colors; avoid near-grays and
near-blacks (they collide with walnut/ink). Each cell's target-color
square uses the jewel's color verbatim, and the slot asset on top is
tinted to the same color at 35% brightness.

**Accent discipline:** the only saturated pixels on screen should be
jewels, grid cells (target-color square + darkened slot), medals, the
jewel badge, and the flash. Everything else is wood, parchment, ink, or
foil. Do not tint UI chrome with jewel colors.

---

## Interaction States

The tap state machine lives in `src/level.lua`; visual treatment is
here.

| State | Visual treatment | Source |
|-------|------------------|--------|
| Idle jewel | Tinted octagonal gem asset (`assets/Jewel_8edges.png`) at gem diameter `cell_size · 0.68`, drawn through `draw_jewel_asset` | `render.draw_cell` |
| Locked jewel | Same as idle — intentional. The lock is conveyed by the jewel color matching its cell's target color (same square tint beneath), so the cell reads as "settled". No extra decoration. | `src/cluster.lua` |
| Hovering (lifted) | Source cells suppressed; cluster floats at origin positions, lifted by `cell_size · 0.18`, bobbing `sin(t · 4 + x · 0.7 + y · 0.5) · 2`, with a soft drop shadow | `render.draw` |
| Shelf hover | Cluster floats above the shelf tray, centered, bobbing | `render.draw` |
| Flash | Red text (`FLASH_COLOR`) with a darker shadow, alpha = `min(1, flash.t)` | `render.draw` |
| Win — fly | Each shelf/source jewel eases to its target cell over `FLY_DURATION = 0.55s`, cubic-out (`1 - (1-u)³`), with a landing pulse reaching `1.15×` radius | `render.draw`, `level.lua` |
| Win — cascade stomp | Each cell pulses to `STOMP_PEAK = 1.30×` over `STOMP_DURATION = 0.28s`, staggered by `CASCADE_STAGGER = 0.06s` × radial distance | `render.draw`, `level.lua` |
| Win — overlay | `OVERLAY_DELAY = 0.20s` after cascade, parchment panel dims background to 55% black and shows "Solved!" + medal + delta | `render.draw` |

**Animation budget:** ~1.1s from the winning tap to the overlay. Do not
extend without reason — it's the dwell between puzzles.

---

## Copywriting Contract

All user-facing strings. Tone: warm, terse, no punctuation bloat, no
exclamation marks except on the flash.

| Element | Copy | Source |
|---------|------|--------|
| Window title | `JewelSort` | `conf.lua` |
| HUD title | `JewelSort — {level name}` | `render.draw` |
| Hover hint | `Tap a matching hole, the shelf, or elsewhere to cancel` | `render.draw` |
| Shelf-full flash | `Shelf full!` | (flash caller in `level.lua`) |
| Win heading | `Solved!` | `render.draw` |
| Win delta (first time) | `+{N} jewel` / `+{N} jewels` | `render.draw` |
| Win delta (repeat) | `Already mastered` | `render.draw` |
| Win footer | `Tap anywhere to return to menu` | `render.draw` |
| Menu title | `JewelSort` | `render.draw_menu` |
| Box-select subtitle | `Select a book` | `render.draw_menu` |
| Levels subtitle | `Tap a puzzle to play` | `render.draw_menu` |
| Back button | `< Back` | `render.draw_menu` |
| Locked box | `Locked — needs {N} jewels` | `render.draw_box_card` |
| Missing thumbnail | `missing` | `render.draw_level_tile` |

**Rules of thumb:**
- Lowercase sentence case, not Title Case (except "JewelSort", "Solved!").
- Never pluralize by appending "(s)". Branch copy explicitly.
- Em dash with spaces (` — `), never hyphen, for separators.
- No emoji. No icons. The aesthetic is hand-lettered wood, not modern app.

---

## Asset & Build Safety

Equivalent of "registry safety" for this codebase. Hard constraints
from the web build (Fengari on love.js):

| Constraint | Rule | Check |
|------------|------|-------|
| No `goto` statements | Any `.lua` file | `grep -rn "goto" --include="*.lua" .` — only comment matches allowed |
| No recursion in flood-fill | `src/cluster.lua` uses an explicit queue | Code review |
| No `os.execute`, `io.popen`, FFI, `love.thread`, screen-capture callbacks | All `.lua` | Code review |
| All filesystem access through `love.filesystem` | All `.lua` | Code review |
| Only bundled font | `assets/fonts/FredokaOne-Regular.ttf` | `render.lua` FONT_PATH |
| PNG asset dependency kept minimal | Wood/parchment chrome is procedural in `wood.lua`. Permitted PNGs: `levels/*.png` (data), `assets/jewel_slot_8edges.png` (bevelled slot), `assets/Jewel_8edges.png` (faceted gem). No additional image assets without a contract update. | File listing under `assets/` |

Adding a new visual element: **prefer extending `wood.lua`** (new `kind`
in `tones()` + cache key) over loading an asset. Assets cost bundle
size and break the "procedural toy box" promise.

---

## Checklist — Before Changing UI

- [ ] Change respects the 32 / 22 px font scale (or this file is updated)
- [ ] New color is added to `wood.palette` or justified as jewel data
- [ ] Saturated colors are limited to jewels / rings / medals / badge / flash
- [ ] Text routed through `print_engraved`, not raw `love.graphics.print`
- [ ] Panels drawn via `wood.draw_panel`, not raw `rectangle("fill")`
- [ ] No `goto`, no recursion, no forbidden modules
- [ ] Copy follows the tone rules above
- [ ] `grep -rn "goto" --include="*.lua" .` is clean
