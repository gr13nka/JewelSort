#!/usr/bin/env python3
"""Composite preview — shows level select assembled with sample pixel art."""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math

ROOT = Path(__file__).parent
PNG = ROOT / "png"
FONTS = ROOT / "fonts"
OUT = ROOT / "preview_levels.png"

# Display target: 540×960 — render at 1080×1920 (2x) and resize at the end.
W, H = 1080, 1920

# Load assets
bg          = Image.open(PNG / "bg_wood.png").convert("RGBA")
page        = Image.open(PNG / "page_parchment.png").convert("RGBA")
page_ribbon = Image.open(PNG / "page_ribbon_burgundy.png").convert("RGBA")
back_btn    = Image.open(PNG / "back_button.png").convert("RGBA")
counter     = Image.open(PNG / "counter_jewels.png").convert("RGBA")

card_s  = Image.open(PNG / "card_s.png").convert("RGBA")
card_s_locked = Image.open(PNG / "card_s_locked.png").convert("RGBA")
card_m  = Image.open(PNG / "card_m.png").convert("RGBA")
card_l  = Image.open(PNG / "card_l.png").convert("RGBA")
card_xl = Image.open(PNG / "card_xl.png").convert("RGBA")

pushpin_red    = Image.open(PNG / "pushpin_red.png").convert("RGBA")
pushpin_gold   = Image.open(PNG / "pushpin_gold.png").convert("RGBA")
pushpin_silver = Image.open(PNG / "pushpin_silver.png").convert("RGBA")
pushpin_teal   = Image.open(PNG / "pushpin_teal.png").convert("RGBA")

level_star    = Image.open(PNG / "level_star.png").convert("RGBA")

font_title = ImageFont.truetype(str(FONTS / "Alegreya-Bold.ttf"), 56)
font_button = ImageFont.truetype(str(FONTS / "Alegreya-Bold.ttf"), 36)


def make_pixel_art_image(svg_pixel_art_str, target_w, target_h):
    """Render 16x16 (or larger viewBox) pixel art SVG into a target-sized PIL Image."""
    import cairosvg
    import io
    png_bytes = cairosvg.svg2png(
        bytestring=svg_pixel_art_str.encode(),
        output_width=target_w,
        output_height=target_h,
    )
    return Image.open(io.BytesIO(png_bytes)).convert("RGBA")


# Sample pixel-art images for demo levels
PA_FOREST_SCENE = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" shape-rendering="crispEdges">
  <g fill="#7BA8D9"><rect x="0" y="0" width="24" height="14"/></g>
  <g fill="#FFF6D8"><rect x="17" y="3" width="3" height="3"/><rect x="16" y="4" width="5" height="1"/></g>
  <g fill="#7B5A2E"><rect x="6" y="10" width="2" height="6"/></g>
  <g fill="#558238"><rect x="3" y="6" width="8" height="6"/><rect x="2" y="7" width="10" height="4"/></g>
  <g fill="#7BB04A"><rect x="4" y="6" width="2" height="2"/><rect x="7" y="7" width="2" height="1"/></g>
  <g fill="#6B4226"><rect x="0" y="14" width="24" height="3"/></g>
  <g fill="#8B5A2B"><rect x="0" y="14" width="24" height="1"/></g>
  <g fill="#558238"><rect x="0" y="17" width="24" height="2"/></g>
  <g fill="#A87A4D"><rect x="16" y="11" width="6" height="6"/></g>
  <g fill="#6B4226"><rect x="16" y="10" width="2" height="1"/><rect x="20" y="10" width="2" height="1"/></g>
  <g fill="#FFF6D8"><rect x="17" y="12" width="2" height="2"/><rect x="20" y="12" width="2" height="2"/></g>
  <g fill="#1a1a1a"><rect x="18" y="13" width="1" height="1"/><rect x="21" y="13" width="1" height="1"/></g>
  <g fill="#E5A82A"><rect x="19" y="14" width="1" height="1"/></g>
  <g fill="#C2272C"><rect x="2" y="18" width="3" height="2"/></g>
  <g fill="#FFFFFF"><rect x="3" y="18" width="1" height="1"/></g>
  <g fill="#F4E0B8"><rect x="3" y="20" width="1" height="2"/></g>
  <g fill="#FFB0C8"><rect x="13" y="19" width="1" height="1"/><rect x="14" y="20" width="1" height="1"/></g>
  <g fill="#FFF6D8"><rect x="2" y="2" width="1" height="1"/><rect x="14" y="3" width="1" height="1"/><rect x="9" y="1" width="1" height="1"/></g>
</svg>"""

PA_BIRD = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">
  <g fill="#4FA3D9"><rect x="4" y="6" width="6" height="1"/><rect x="3" y="7" width="8" height="3"/><rect x="4" y="10" width="6" height="1"/></g>
  <g fill="#1F5A82"><rect x="3" y="9" width="2" height="2"/><rect x="9" y="9" width="2" height="2"/></g>
  <g fill="#1a1a1a"><rect x="5" y="8" width="1" height="1"/></g>
  <g fill="#E5A82A"><rect x="10" y="7" width="3" height="1"/></g>
  <g fill="#FFFFFF" opacity="0.7"><rect x="0" y="3" width="3" height="1"/><rect x="13" y="2" width="3" height="1"/></g>
</svg>"""

PA_CAT = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">
  <g fill="#7B5A2E">
    <rect x="2" y="2" width="2" height="3"/><rect x="12" y="2" width="2" height="3"/>
    <rect x="3" y="4" width="10" height="1"/><rect x="2" y="5" width="12" height="8"/><rect x="3" y="13" width="10" height="1"/>
  </g>
  <g fill="#1a1a1a">
    <rect x="5" y="7" width="1" height="2"/><rect x="10" y="7" width="1" height="2"/><rect x="7" y="10" width="2" height="1"/>
  </g>
  <g fill="#FFB0C8" opacity="0.7">
    <rect x="3" y="9" width="2" height="1"/><rect x="11" y="9" width="2" height="1"/>
  </g>
</svg>"""

PA_PAW = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">
  <g fill="#888">
    <rect x="6" y="8" width="4" height="3"/><rect x="5" y="9" width="6" height="2"/>
    <rect x="3" y="5" width="2" height="2"/><rect x="11" y="5" width="2" height="2"/>
    <rect x="6" y="3" width="2" height="2"/><rect x="9" y="3" width="2" height="2"/>
  </g>
</svg>"""

PA_LEAF = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">
  <g fill="#558238">
    <rect x="7" y="2" width="3" height="1"/><rect x="6" y="3" width="5" height="1"/>
    <rect x="5" y="4" width="6" height="2"/><rect x="4" y="6" width="8" height="3"/>
    <rect x="5" y="9" width="6" height="2"/><rect x="6" y="11" width="4" height="1"/>
  </g>
  <g fill="#7BB04A"><rect x="6" y="4" width="3" height="2"/><rect x="5" y="6" width="3" height="1"/></g>
  <g fill="#3F5A1F"><rect x="8" y="3" width="1" height="9"/></g>
  <g fill="#7B5A2E"><rect x="7" y="12" width="2" height="2"/></g>
</svg>"""


def rotate_image(img, deg):
    return img.rotate(deg, resample=Image.BICUBIC, expand=True)


def composite_card(canvas, card_img, x, y, pixel_art, frame_x, frame_y, frame_w, frame_h,
                   pushpin=None, star=None, rotation=0,
                   star_size=76, locked=False):
    """Draw a card onto canvas with all its overlays.

    For locked cards, pass card_img as the *_locked variant — the sepia frame
    and pixel-art question mark are already baked into the asset, so we skip
    the pixel-art render step entirely.
    """
    card_with_art = card_img.copy()

    # Render the level pixel art into the dark frame area (only when unlocked)
    if not locked and pixel_art is not None:
        pa_img = make_pixel_art_image(pixel_art, frame_w, frame_h)
        card_with_art.paste(pa_img, (frame_x, frame_y), pa_img)

    # Pushpin (top center) — drawn for both locked and unlocked
    if pushpin is not None:
        cw, _ = card_with_art.size
        ppin_x = (cw - pushpin.width) // 2
        ppin_y = -8
        card_with_art.paste(pushpin, (ppin_x, ppin_y), pushpin)

    if rotation != 0:
        card_with_art = rotate_image(card_with_art, rotation)

    canvas.paste(card_with_art, (x, y), card_with_art)

    # Completion star — only for unlocked-completed cards
    if star is not None and not locked:
        star_resized = star.resize((star_size, star_size), Image.LANCZOS)
        star_rotated = star_resized.rotate(15, resample=Image.BICUBIC, expand=True)
        sx = x + card_with_art.width - star_rotated.width // 2 - 5
        sy = y - star_rotated.height // 3
        canvas.paste(star_rotated, (sx, sy), star_rotated)


# ============================================================
# Build canvas
# ============================================================

canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
canvas.paste(bg, (0, 0), bg)

# --- Header ---
HEADER_PAD = 44
header_y = 36

# Back button (left)
canvas.paste(back_btn, (HEADER_PAD, header_y + 12), back_btn)
# Draw "‹ Back" text on top of the back button
draw = ImageDraw.Draw(canvas)
draw.text((HEADER_PAD + 30, header_y + 22), "‹ Back",
          font=font_button, fill=(241, 203, 110))

# Counter (right)
counter_x = W - HEADER_PAD - counter.width
canvas.paste(counter, (counter_x, header_y + 24), counter)
# Draw "3" on top
draw.text((counter_x + 110, header_y + 28), "3",
          font=font_button, fill=(241, 203, 110))

# Title (center) — engraved on wood
title = "Forest Friends"
bbox = draw.textbbox((0, 0), title, font=font_title)
tw = bbox[2] - bbox[0]
title_x = (W - tw) // 2
title_y = header_y + 16
# Engraved effect: dark shadow below, light highlight above, ink fill
draw.text((title_x, title_y + 3), title, font=font_title, fill=(20, 4, 4))
draw.text((title_x, title_y + 1), title, font=font_title, fill=(110, 60, 20))
draw.text((title_x, title_y - 2), title, font=font_title, fill=(255, 235, 200))
draw.text((title_x, title_y), title, font=font_title, fill=(74, 44, 20))

# --- Page parchment ---
page_x = 32
page_y = 200
canvas.paste(page, (page_x, page_y), page)

# Bookmark ribbon hanging from top of page
ribbon_x = page_x + page.width - 140
ribbon_y = page_y - 16
canvas.paste(page_ribbon, (ribbon_x, ribbon_y), page_ribbon)


# --- Levels ---
# All positions are relative to canvas, but they sit on top of the page
# The page area is page_x..page_x+page.width on x, page_y..page_y+page.height on y
# Page is 1020 x 1660. So page interior runs from (32, 200) to (1052, 1860).

# XL — Forest scene (top center, slight tilt left), completed
composite_card(canvas, card_xl,
               x=page_x + 130, y=page_y + 60,
               pixel_art=PA_FOREST_SCENE,
               frame_x=36, frame_y=36, frame_w=488, frame_h=488,
               pushpin=pushpin_red,
               star=level_star,
               star_size=88,
               rotation=-1)

# L — Bird postcard (lower-left), completed
composite_card(canvas, card_l,
               x=page_x + 70, y=page_y + 760,
               pixel_art=PA_BIRD,
               frame_x=40, frame_y=22, frame_w=460, frame_h=264,
               pushpin=pushpin_teal,
               star=level_star,
               star_size=72,
               rotation=1.5)

# M — Cat polaroid (right of L), unlocked-not-played
composite_card(canvas, card_m,
               x=page_x + 660, y=page_y + 770,
               pixel_art=PA_CAT,
               frame_x=22, frame_y=22, frame_w=256, frame_h=260,
               pushpin=pushpin_red,
               rotation=3)

# S — paw print spot (lower-left), LOCKED — sepia card with baked-in "?"
composite_card(canvas, card_s_locked,
               x=page_x + 200, y=page_y + 1190,
               pixel_art=None,
               frame_x=22, frame_y=22, frame_w=176, frame_h=176,
               pushpin=pushpin_silver,
               locked=True,
               rotation=-8)

# S — leaf (lower-right), unlocked-not-played
composite_card(canvas, card_s,
               x=page_x + 540, y=page_y + 1380,
               pixel_art=PA_LEAF,
               frame_x=22, frame_y=22, frame_w=176, frame_h=176,
               pushpin=pushpin_gold,
               rotation=6)

# Save preview at 1x for easier viewing
preview_1x = canvas.resize((540, 960), Image.LANCZOS)
preview_1x.save(OUT)
print(f"Preview saved to {OUT}")
