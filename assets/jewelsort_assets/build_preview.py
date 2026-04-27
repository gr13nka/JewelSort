#!/usr/bin/env python3
"""Composite preview — shows how all assets assemble into the book-select screen."""

from PIL import Image
import pathlib

ROOT = pathlib.Path(__file__).parent
PNG = ROOT / "png"
OUT = ROOT / "preview.png"

# Display target: 540x960 (1x). We'll render the preview at 1080x1920 (2x) and shrink at the end.
W, H = 1080, 1920

# Load assets (PNGs at 2x — drop directly onto a 2x preview canvas)
bg     = Image.open(PNG / "bg_wood.png").convert("RGBA")
books  = {
    "fs": Image.open(PNG / "book_first_steps.png").convert("RGBA"),
    "fh": Image.open(PNG / "book_forest_harvest.png").convert("RGBA"),
    "ff": Image.open(PNG / "book_forest_friends.png").convert("RGBA"),
    "ss": Image.open(PNG / "book_shapes_symbols.png").convert("RGBA"),
}
ribbon  = Image.open(PNG / "bookmark_ribbon.png").convert("RGBA")
medal   = Image.open(PNG / "medal_completion.png").convert("RGBA")
counter = Image.open(PNG / "counter_jewels.png").convert("RGBA")
lock    = Image.open(PNG / "book_lock.png").convert("RGBA")

canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
canvas.paste(bg, (0, 0), bg)

# --- Header area (top ~190px) ---
# Counter pill in upper-right
counter_x = W - counter.width - 40
counter_y = 50
canvas.paste(counter, (counter_x, counter_y), counter)


# --- Books list ---
# Each book displayed at 1000px wide (a bit smaller than the asset's 1040 to add side margins)
# Top of first book around y=200, gap of ~50 between books
BOOK_W = 1000
SCALE = BOOK_W / 1040  # ~0.96
BOOK_H = int(360 * SCALE)
BOOK_X = (W - BOOK_W) // 2

GAP = 50
START_Y = 220

book_layout = [
    ("fs", "completed"),     # First Steps (2/2 done — gets medal)
    ("fh", "in_progress"),   # Forest Harvest (0/2 — gets ribbon)
    ("ff", "locked"),        # Forest Friends (locked)
    ("ss", "locked"),        # Shapes & Symbols (locked)
]

def tint(img, r, g, b, a=1.0):
    """Apply a multiplicative tint to an RGBA image."""
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            pr, pg, pb, pa = px[x, y]
            px[x, y] = (
                int(pr * r),
                int(pg * g),
                int(pb * b),
                int(pa * a),
            )
    return out

for i, (key, state) in enumerate(book_layout):
    book_img = books[key].resize((BOOK_W, BOOK_H), Image.LANCZOS)
    y = START_Y + i * (BOOK_H + GAP)

    if state == "locked":
        book_img = tint(book_img, 0.40, 0.32, 0.22)

    canvas.paste(book_img, (BOOK_X, y), book_img)

    # Overlay state markers (in book coordinate space)
    if state == "in_progress":
        # Ribbon near top of book, on the right side of the empty cover area
        rib_x = BOOK_X + int(580 * SCALE)
        rib_y = y - 8
        canvas.paste(ribbon, (rib_x, rib_y), ribbon)
    elif state == "completed":
        # Medal in upper-right
        med_x = BOOK_X + int(540 * SCALE)
        med_y = y - 16
        canvas.paste(medal, (med_x, med_y), medal)
    elif state == "locked":
        # Lock icon centered on the right half of the cover
        lk_x = BOOK_X + int(720 * SCALE) - lock.width // 2
        lk_y = y + (BOOK_H // 2) - lock.height // 2
        canvas.paste(lock, (lk_x, lk_y), lock)

# Save preview at 1x display size for easier viewing
preview_1x = canvas.resize((540, 960), Image.LANCZOS)
preview_1x.save(OUT)
print(f"Preview saved to {OUT}")
