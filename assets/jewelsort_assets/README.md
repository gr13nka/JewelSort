# JewelSort UI Assets — Book Select & Level Select

Vector + raster assets for both redesigned screens. Both formats provided — SVG for clean scaling and code editing, PNG for direct use in LÖVE2D.

## Book-select assets

| File | Size (PNG) | Purpose |
|---|---|---|
| `bg_wood.svg/png` | 1080×1920 | Full-screen wood panel background (shared with level select) |
| `book_first_steps.svg/png` | 1040×360 | Book 1 — burgundy + sapling emblem |
| `book_forest_harvest.svg/png` | 1040×360 | Book 2 — forest green + basket emblem |
| `book_forest_friends.svg/png` | 1040×360 | Book 3 — teal + owl emblem |
| `book_shapes_symbols.svg/png` | 1040×360 | Book 4 — plum + compass rose emblem |
| `bookmark_ribbon.svg/png` | 72×140 | Cream ribbon for in-progress books |
| `medal_completion.svg/png` | 128×176 | Gold rosette + ribbons for completed books |
| `counter_jewels.svg/png` | 200×96 | Wood pill + faceted rose-magenta gem (jewel counter) |
| `book_lock.svg/png` | 76×76 | Iron padlock for locked books and locked levels |

## Level-select assets

| File | Size (PNG) | Purpose |
|---|---|---|
| `page_parchment.svg/png` | 1020×1660 | Cream parchment "page" of the open book |
| `page_ribbon_burgundy.svg/png` | 64×120 | Burgundy ribbon hanging from top of the page |
| `back_button.svg/png` | 180×80 | Wooden pill for the Back button (game draws "Back" / "Назад" text on top) |
| `card_s.svg/png` | 220×260 | Small polaroid level card |
| `card_m.svg/png` | 300×360 | Medium polaroid level card |
| `card_l.svg/png` | 540×336 | Landscape polaroid level card |
| `card_xl.svg/png` | 560×640 | Large polaroid level card with gold corner brackets |
| `card_s_locked.svg/png` | 220×260 | Sepia small polaroid with pixel-art "?" baked in (locked levels) |
| `card_m_locked.svg/png` | 300×360 | Sepia medium polaroid with pixel-art "?" baked in (locked levels) |
| `card_l_locked.svg/png` | 540×336 | Sepia landscape polaroid with pixel-art "?" baked in (locked levels) |
| `card_xl_locked.svg/png` | 560×640 | Sepia XL with tarnished-brass corners and "?" baked in (locked levels) |
| `pushpin_red.svg/png` | 44×44 | Rose-magenta pushpin |
| `pushpin_gold.svg/png` | 44×44 | Gold pushpin |
| `pushpin_silver.svg/png` | 44×44 | Silver pushpin |
| `pushpin_teal.svg/png` | 44×44 | Teal pushpin |
| `level_star.svg/png` | 76×76 | Small gold rosette star sticker for completed levels |

**Card inner-frame coordinates** (where the level pixel art is rendered, in card-local 2× coordinates):

| Card | Inner frame X,Y | Inner frame W,H |
|---|---|---|
| `card_s` | 22, 22 | 176 × 176 |
| `card_m` | 22, 22 | 256 × 260 |
| `card_l` | 40, 22 | 460 × 264 |
| `card_xl` | 36, 36 | 488 × 488 |

All assets are **2× retina resolution**. Display them at half size on a 540×960 screen for crisp output.

The four book emblems (sapling, mushroom basket, owl, compass rose) are **16×16 pixel art** rendered at integer scale 13 inside the cream parchment plates — crisp pixels with no anti-aliasing, ties directly to the in-game pixel-art puzzle reveals. The painted leather covers, gold spine bands, and embossed frame around the pixel art are the same on every book.

## Layering rules

Per-book composition order, top to bottom:

1. `bg_wood` (full screen)
2. `book_*` (one of the four book covers)
3. State overlays:
   - **In-progress** → draw `bookmark_ribbon` near top-right of book
   - **Completed** → draw `medal_completion` near top-right of book (rotated -7° already baked in)
   - **Locked** → see "Locked treatment" below
4. Dynamic text on top:
   - Title text (gold-foil) over the empty right half of the book
   - Progress count ("2 / 2") below title
   - Counter number drawn over `counter_jewels` empty area

## Level-select layering rules

Per-screen composition order, top to bottom:

1. `bg_wood` (full screen, continuous from book select — no transition jolt)
2. Header strip (drawn directly on the wood, no separate background asset):
   - `back_button` at left, with "‹ Back" / "‹ Назад" text drawn on top in Alegreya-Bold
   - Book title centered (gold-foil engraved text on wood — same render technique as the book covers)
   - `counter_jewels` at right with the jewel count drawn on top
3. `page_parchment` positioned below the header, centered horizontally (with ~16 px margin each side at 1×)
4. `page_ribbon_burgundy` overlapping the top edge of the page
5. **Per level card**, in this order:
   - **If unlocked** → one of `card_s` / `card_m` / `card_l` / `card_xl` + the level's pixel art rendered into the inner frame area
   - **If locked** → one of `card_s_locked` / `card_m_locked` / `card_l_locked` / `card_xl_locked` — the sepia frame and pixel-art "?" are already baked in, no further compositing needed
   - One `pushpin_*` near top center of the card (color is purely visual rhythm — no semantic meaning)
   - **If completed** → `level_star` overlapping upper-right corner (rotate ~15° for stuck-on look). Never on locked cards.

The locked cards are full sepia variants with a chunky pixel-art question mark already inside the frame — not a runtime tint and not a separate "?" overlay. The level select screen no longer uses `book_lock.png` at all (that asset is only for the locked book covers in book select). Locked cards aren't tappable; they also skip the sway animation, so motion alone signals "tappable."

Star size is also scaled per card; recommended:

| Card | Star display size |
|---|---|
| S | 30 px (1×) |
| M | 38 px |
| L | 38 px |
| XL | 52 px |

## Sway animation (tap affordance)

Each unlocked card sways gently — small rotation plus tiny vertical bob — on a 4–5 second cycle. Locked cards stay still. Motion itself becomes the "this is tappable" signal.

Drop this into your level-render module:

```lua
-- One-time setup per card (when entering the level select screen)
function LevelCard:init(base_rotation, is_locked)
  self.base_rotation = base_rotation        -- card's resting tilt in radians (e.g. -0.035 for -2°)
  self.is_locked = is_locked
  self.sway_phase = math.random() * math.pi * 2     -- random phase so cards never sync
  self.sway_speed = 1.2 + math.random() * 0.5       -- per-card variation, 1.2-1.7 rad/s
  self.sway_amount = 0.009                          -- ±0.5° in radians
  self.bob_amount = 1.5                             -- pixels (in display coordinates, so 1.5 px at 1×)
  self.press_offset = 0                             -- nudged on tap-down for press feedback
end

-- Per-frame, in your draw loop
function LevelCard:get_transform()
  if self.is_locked then
    return self.base_rotation, 0, 0
  end
  local t = love.timer.getTime()
  local rot = self.base_rotation + math.sin(t * self.sway_speed + self.sway_phase) * self.sway_amount
  local bob = math.sin(t * self.sway_speed + self.sway_phase) * self.bob_amount
  return rot, 0, bob + self.press_offset
end

-- In your draw function:
function LevelCard:draw()
  local rot, dx, dy = self:get_transform()
  love.graphics.push()
  -- Translate to card center, rotate around top (where the pushpin is), draw, pop
  local cx, cy = self.x + self.w/2, self.y + self.h * 0.2  -- pivot near pushpin (top 20%)
  love.graphics.translate(cx + dx, cy + dy)
  love.graphics.rotate(rot)
  love.graphics.translate(-cx, -cy)

  -- Pick the right card asset for this state. The _locked variant has the
  -- sepia frame and pixel-art "?" already baked in — no runtime compositing.
  local card_image = self.is_locked and self.card_locked_image or self.card_image
  love.graphics.draw(card_image, self.x, self.y, 0, 0.5, 0.5)

  -- Draw the level pixel art into the inner frame ONLY when unlocked.
  -- (Locked cards already show the question mark from the asset itself.)
  if not self.is_locked then
    love.graphics.draw(self.pixel_art, self.x + self.frame_x * 0.5, self.y + self.frame_y * 0.5,
                       0, (self.frame_w * 0.5) / self.pixel_art:getWidth(),
                          (self.frame_h * 0.5) / self.pixel_art:getHeight())
  end

  -- Pushpin (drawn for both locked and unlocked — they're still pinned to the page)
  love.graphics.draw(self.pushpin_image, self.x + self.w/2 - 11, self.y - 8, 0, 0.5, 0.5)

  -- Completion star — only for unlocked + completed
  if self.is_completed and not self.is_locked then
    love.graphics.draw(self.star_image, self.x + self.w - 14, self.y - 14, math.rad(15), 0.5, 0.5)
  end

  love.graphics.pop()
end

-- Tap-down press feedback
function LevelCard:on_press()
  self.press_offset = 4   -- nudge down on press
end

function LevelCard:on_release()
  self.press_offset = 0   -- spring back
  -- ... start scene transition into the puzzle
end
```

**Tuning the sway amount.** `0.009` rad ≈ 0.5°, and `1.5 px` of bob at 1× display scale, are intentionally subtle. Anything bigger and it reads as a glitch. Anything smaller and players miss the affordance entirely. The current values are "obviously alive but never distracting."

**Reduced motion.** Honor the player's accessibility setting — on mobile/web you can detect `prefers-reduced-motion` and disable sway:

```lua
if love.system.getOS() == "Web" and reducedMotionRequested() then
  -- skip sway, draw static
end
```

## Locked treatment

Locked books reuse the same full-color book asset with a runtime tint + the lock icon overlaid:

```lua
-- Drawing a locked book
love.graphics.setColor(0.40, 0.32, 0.22, 1.0)  -- warm dark tint
love.graphics.draw(book_image, x, y, 0, 0.5, 0.5)  -- 0.5x = display size

love.graphics.setColor(1, 1, 1, 1)
love.graphics.draw(lock_image, x + lock_offset_x, y + lock_offset_y, 0, 0.5, 0.5)
```

The tint dims the cover and desaturates the emblem in one step. The lock icon stays at full color so it reads cleanly against the dimmed cover.

## Suggested LÖVE2D loader

```lua
local function load_book_assets()
  local assets = {
    bg = love.graphics.newImage("assets/png/bg_wood.png"),
    books = {
      first_steps     = love.graphics.newImage("assets/png/book_first_steps.png"),
      forest_harvest  = love.graphics.newImage("assets/png/book_forest_harvest.png"),
      forest_friends  = love.graphics.newImage("assets/png/book_forest_friends.png"),
      shapes_symbols  = love.graphics.newImage("assets/png/book_shapes_symbols.png"),
    },
    ribbon  = love.graphics.newImage("assets/png/bookmark_ribbon.png"),
    medal   = love.graphics.newImage("assets/png/medal_completion.png"),
    counter = love.graphics.newImage("assets/png/counter_jewels.png"),
    lock    = love.graphics.newImage("assets/png/book_lock.png"),
  }
  for _, img in pairs(assets.books) do img:setFilter("linear", "linear") end
  assets.bg:setFilter("linear", "linear")
  return assets
end
```

`linear` filtering on the books matches the soft-painted leather. The pixel-art emblems are baked into the book PNGs at 2× resolution with their pixels already enlarged 13× — so at typical display scales they stay crisp without needing `nearest` filtering. Use `nearest` filtering only on your in-game puzzle assets where individual source pixels need to remain perfectly square at runtime.

## Editing the assets

The SVG files are the source of truth. They're vector and edit cleanly in any SVG tool (Inkscape, Affinity Designer, Figma, or just a text editor).

To regenerate PNGs after editing an SVG:

```bash
# requires cairosvg: pip install cairosvg
python3 -c "import cairosvg; cairosvg.svg2png(url='svg/book_first_steps.svg', write_to='png/book_first_steps.png')"
```

Or use the included `build.py` to regenerate everything at once.

## Customization tips

**Adding a 5th book** — copy any book SVG, change the cover gradient stops to one of the unused palette colors (ochre `#9F6E2A`, chestnut `#6B4226`, slate `#3F5872`, wine `#5F2233`), and replace the emblem `<g>` with your own pixel art (or copy an existing emblem and recolor).

**Different emblem** — emblems are pixel art drawn in a 16×16 viewBox `<g>`, placed at `translate(98 56) scale(13)` on the cover. Each emblem `<rect>` in the source is one pixel; integer scaling × `shape-rendering="crispEdges"` keeps the pixels sharp at any output size. Replace the `<g>` contents with any 16×16 pixel-art design.

**The pixel art style is intentional** — it ties the book covers directly to your in-game puzzle art, since the gameplay reveals are pixel art too. The covers themselves stay painted (smooth gradients on leather, parchment, foil) so the emblems read as little framed pixel-art crests sitting on storybook covers. That contrast is the whole design idea.

**Tighter or looser book proportions** — the book viewBox is `0 0 1040 360`. The actual visible book occupies ~1024×340. Adjust the cover/spine/plate rect dimensions proportionally if you change the viewBox.

**Different palette** — main color stops live in the `<linearGradient id="cover_*">` and `<linearGradient id="spine_*">` definitions at the top of each book SVG. Replace the three `stop-color` values with your hex codes.

## Known limitations

- The page-edge stripe at the bottom of each book is a row of small `<rect>` elements. If you scale the SVG much larger than 2× (e.g., for marketing materials), regenerate at higher resolution rather than upscaling the PNG.
- The medal's `-7°` rotation is baked into the SVG. If you want the medal upright for some reason, edit the `<g transform="rotate(-7 64 64)">` line in `medal_completion.svg`.
- All assets are linear-color sRGB PNGs. If your LÖVE2D project uses gamma-correct rendering, you may want to load them with `{linear = false}` (the default).

## Fonts

The `fonts/` folder contains four font families that all support both Latin and Cyrillic — pick one and ship just that family. See `fonts/font_comparison.png` and `fonts/font_in_context.png` for visual comparisons of all four.

| Font | License | Best for |
|---|---|---|
| **Alegreya** (Regular + Bold) | OFL | **Recommended** — designed specifically for literature, has the most "storybook" character. Slight quirky charm in letterforms gives it a hand-set fairy tale book feel. |
| **PT Serif** (Regular + Bold) | OFL | Russian-designed serif (ParaType). Most authentic feel for the RU audience; reads as a Russian literature classic. Heavier, more authoritative. |
| **Lora** (Regular + Bold) | OFL | Classic balanced book serif. Most refined and traditional. Mentioned in the project knowledge as a Russian-supporting recommendation. |
| **Bitter** (Regular + Bold) | OFL | Slab serif designed for screens. More modern and game-UI-friendly while still having book character. |

**My pick: Alegreya for cozy storybook feel, or PT Serif if you want maximum Russian-book authenticity.** Both render Cyrillic beautifully (no fallback needed) and have proper Bold weights for gold-foil titles.

### LÖVE2D usage

```lua
-- Replace your current Fredoka One + Rubik fallback with one consistent family
local font_title = love.graphics.newFont("assets/fonts/Alegreya-Bold.ttf",    32)
local font_body  = love.graphics.newFont("assets/fonts/Alegreya-Regular.ttf", 22)
local font_small = love.graphics.newFont("assets/fonts/Alegreya-Regular.ttf", 18)

-- All three handle EN + RU automatically — no need for a separate Cyrillic fallback
-- (Alegreya, PT Serif, Lora, and Bitter all have full Cyrillic glyph coverage built in)
```

**Removing the old Cyrillic fallback workaround.** Per your `CLAUDE.md`, you currently bundle Rubik-Regular as a Cyrillic fallback for Fredoka One. With any of the four bundled fonts, that workaround can go away — the new font handles both scripts in one file. This simplifies font loading and removes one TTF from your shipped build.

### Font sizing notes

The CLAUDE.md UI spec calls for 32 px body and 22 px small. These four fonts all hold up at those sizes. For book titles on the cover (gold foil), I'd suggest **38–44 px** since the book covers are large UI elements where titles can breathe a bit more. Test at your actual display scale.

If you previously rendered text with `print_engraved` (your existing 1px shadow render path), it works the same with these fonts — the engraved-foil effect actually reads *better* on a serif than on a chunky sans like Fredoka, because the serifs catch the highlight/shadow lines more crisply.
