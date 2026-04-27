#!/usr/bin/env python3
"""Generate JewelSort level-select screen assets — adds to the same png/ and svg/ folders."""

import cairosvg
import pathlib

ROOT = pathlib.Path(__file__).parent
SVG_DIR = ROOT / "svg"
PNG_DIR = ROOT / "png"
SVG_DIR.mkdir(exist_ok=True)
PNG_DIR.mkdir(exist_ok=True)


# ============================================================
# 1. Parchment page background — 1020×1660 (2× the 510×830 page area)
# ============================================================
PAGE_PARCHMENT_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1020 1660" width="1020" height="1660">
  <defs>
    <linearGradient id="pageBase" x1="20%" y1="0%" x2="80%" y2="100%">
      <stop offset="0%" stop-color="#F4E0B8"/>
      <stop offset="60%" stop-color="#E5CFA0"/>
      <stop offset="100%" stop-color="#C49E68"/>
    </linearGradient>
    <radialGradient id="pageGlow" cx="30%" cy="20%" r="0.7">
      <stop offset="0%" stop-color="#FBF0D2" stop-opacity="0.55"/>
      <stop offset="100%" stop-color="#FBF0D2" stop-opacity="0"/>
    </radialGradient>
    <filter id="pageShadow" x="-3%" y="-2%" width="106%" height="104%">
      <feDropShadow dx="0" dy="14" stdDeviation="20" flood-color="#000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <rect width="1020" height="1660" rx="28" fill="url(#pageBase)" filter="url(#pageShadow)"/>
  <rect width="1020" height="1660" rx="28" fill="url(#pageGlow)"/>
  <!-- Subtle paper specks for tactile feel -->
  <circle cx="200" cy="1300" r="180" fill="#8c6432" opacity="0.04"/>
  <circle cx="800" cy="240" r="160" fill="#8c6432" opacity="0.03"/>
  <circle cx="900" cy="1100" r="120" fill="#8c6432" opacity="0.03"/>
  <circle cx="320" cy="780" r="100" fill="#8c6432" opacity="0.025"/>
  <!-- Inset edge stroke for paper-fiber suggestion -->
  <rect x="2" y="2" width="1016" height="1656" rx="26" fill="none" stroke="rgba(140,100,50,0.20)" stroke-width="2"/>
</svg>
"""


# ============================================================
# 2. Burgundy page ribbon — 64×120 (2× of 32×60)
# ============================================================
PAGE_RIBBON_BURGUNDY_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 120" width="64" height="120">
  <defs>
    <linearGradient id="ribbonB" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#B8443F"/>
      <stop offset="100%" stop-color="#5C1718"/>
    </linearGradient>
    <filter id="ribbonShadow" x="-15%" y="-5%" width="130%" height="115%">
      <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <g filter="url(#ribbonShadow)">
    <path d="M 0 0 L 64 0 L 64 120 L 32 96 L 0 120 Z" fill="url(#ribbonB)"/>
    <rect x="0" y="0" width="64" height="6" fill="#000" opacity="0.18"/>
    <rect x="0" y="0" width="3" height="120" fill="#FFFFFF" opacity="0.18"/>
    <rect x="61" y="0" width="3" height="120" fill="#000" opacity="0.18"/>
  </g>
</svg>
"""


# ============================================================
# 3. Back button — empty wooden pill (180×80 = 90×40 at 1×). Game draws "Back" text on top.
# ============================================================
BACK_BUTTON_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 80" width="180" height="80">
  <defs>
    <linearGradient id="backG" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#9F6638"/>
      <stop offset="100%" stop-color="#583519"/>
    </linearGradient>
    <filter id="backShadow" x="-5%" y="-5%" width="110%" height="120%">
      <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity="0.3"/>
    </filter>
  </defs>
  <g filter="url(#backShadow)">
    <rect x="6" y="6" width="168" height="64" rx="16" fill="url(#backG)" stroke="#3a2410" stroke-width="3"/>
    <rect x="14" y="10" width="152" height="3" rx="1.5" fill="#FFFFFF" opacity="0.25"/>
  </g>
</svg>
"""


# ============================================================
# 4-7. Polaroid card templates — S, M, L, XL
# Each has a white-cream paper card with a dark inset frame for the level pixel art.
# Game draws pixel art into the inner frame area (coordinates documented in README).
# ============================================================

def question_mark_inline(frame_x, frame_y, frame_w, frame_h):
    """Return a nested SVG element with a pixel-art '?' centered in the given frame."""
    qm_size = int(min(frame_w, frame_h) * 0.7)
    qm_x = frame_x + (frame_w - qm_size) // 2
    qm_y = frame_y + (frame_h - qm_size) // 2
    return f"""
  <svg x="{qm_x}" y="{qm_y}" width="{qm_size}" height="{qm_size}" viewBox="0 0 16 16">
    <g fill="#E5D4B0" shape-rendering="crispEdges">
      <rect x="5" y="1" width="6" height="1"/>
      <rect x="4" y="2" width="2" height="1"/>
      <rect x="10" y="2" width="2" height="1"/>
      <rect x="3" y="3" width="2" height="1"/>
      <rect x="11" y="3" width="2" height="1"/>
      <rect x="11" y="4" width="2" height="1"/>
      <rect x="10" y="5" width="2" height="1"/>
      <rect x="9" y="6" width="2" height="1"/>
      <rect x="8" y="7" width="2" height="1"/>
      <rect x="7" y="8" width="2" height="4"/>
      <rect x="7" y="13" width="2" height="2"/>
    </g>
    <g fill="#7A5F32" opacity="0.55" shape-rendering="crispEdges">
      <rect x="11" y="2" width="1" height="1"/>
      <rect x="12" y="3" width="1" height="1"/>
      <rect x="12" y="4" width="1" height="1"/>
      <rect x="11" y="5" width="1" height="1"/>
      <rect x="10" y="6" width="1" height="1"/>
      <rect x="9" y="7" width="1" height="1"/>
      <rect x="8" y="8" width="1" height="4"/>
      <rect x="8" y="13" width="1" height="2"/>
    </g>
  </svg>"""


def card_svg(W, H, paper_inset, frame_x, frame_y, frame_w, frame_h, frame_radius=4,
             paper_radius=7, with_corners=False, tag="",
             paper_top="#FFFFFF", paper_bot="#F6EEDC",
             frame_top="#0E0904", frame_bot="#1a1108",
             corner_top="#F1CB6E", corner_bot="#8a6520",
             corner_stroke="#6a4f15",
             embed_question_mark=False):
    """Build a polaroid card SVG with the given dimensions and color scheme."""
    corners = ""
    if with_corners:
        # Four gold L-shaped corner brackets (XL only). Each L is 36x36 with 6-thick arms.
        gold_grad = f"""
    <linearGradient id="goldCorner{tag}" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="{corner_top}"/>
      <stop offset="100%" stop-color="{corner_bot}"/>
    </linearGradient>"""
        ix = paper_inset + 12
        iy = paper_inset + 12
        ax = W - paper_inset - 12
        ay = H - paper_inset - 12
        arm = 28
        thick = 6
        corners_path = f"""
  <!-- Top-left bracket -->
  <path d="M {ix} {iy} L {ix + arm} {iy} L {ix + arm} {iy + thick} L {ix + thick} {iy + thick} L {ix + thick} {iy + arm} L {ix} {iy + arm} Z" fill="url(#goldCorner{tag})" stroke="{corner_stroke}" stroke-width="0.5"/>
  <!-- Top-right bracket -->
  <path d="M {ax} {iy} L {ax - arm} {iy} L {ax - arm} {iy + thick} L {ax - thick} {iy + thick} L {ax - thick} {iy + arm} L {ax} {iy + arm} Z" fill="url(#goldCorner{tag})" stroke="{corner_stroke}" stroke-width="0.5"/>
  <!-- Bottom-left bracket -->
  <path d="M {ix} {ay} L {ix + arm} {ay} L {ix + arm} {ay - thick} L {ix + thick} {ay - thick} L {ix + thick} {ay - arm} L {ix} {ay - arm} Z" fill="url(#goldCorner{tag})" stroke="{corner_stroke}" stroke-width="0.5"/>
  <!-- Bottom-right bracket -->
  <path d="M {ax} {ay} L {ax - arm} {ay} L {ax - arm} {ay - thick} L {ax - thick} {ay - thick} L {ax - thick} {ay - arm} L {ax} {ay - arm} Z" fill="url(#goldCorner{tag})" stroke="#6a4f15" stroke-width="0.5"/>
"""
        corners = corners_path
    else:
        gold_grad = ""

    qm = question_mark_inline(frame_x, frame_y, frame_w, frame_h) if embed_question_mark else ""

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">
  <defs>
    <linearGradient id="paper{tag}" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="{paper_top}"/>
      <stop offset="100%" stop-color="{paper_bot}"/>
    </linearGradient>
    <linearGradient id="frame{tag}" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="{frame_top}"/>
      <stop offset="100%" stop-color="{frame_bot}"/>
    </linearGradient>
    <filter id="cardShadow{tag}" x="-15%" y="-15%" width="130%" height="130%">
      <feDropShadow dx="0" dy="6" stdDeviation="6" flood-color="#000" flood-opacity="0.25"/>
    </filter>{gold_grad}
  </defs>
  <g filter="url(#cardShadow{tag})">
    <!-- Paper card -->
    <rect x="{paper_inset}" y="{paper_inset}" width="{W - 2*paper_inset}" height="{H - 2*paper_inset}" rx="{paper_radius}" fill="url(#paper{tag})"/>
    <!-- Top-edge highlight on paper -->
    <rect x="{paper_inset + 4}" y="{paper_inset + 3}" width="{W - 2*paper_inset - 8}" height="2" rx="1" fill="#FFFFFF" opacity="0.35"/>
    <!-- Inset frame for pixel art -->
    <rect x="{frame_x}" y="{frame_y}" width="{frame_w}" height="{frame_h}" rx="{frame_radius}" fill="url(#frame{tag})"/>
    <!-- Top inner shadow on frame -->
    <rect x="{frame_x}" y="{frame_y}" width="{frame_w}" height="2" fill="#000" opacity="0.45"/>
  </g>{corners}{qm}
</svg>
"""


# ============================================================
# 8-11. Pushpin variants
# ============================================================
def pushpin_svg(name, light, mid, dark):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 44 44" width="44" height="44">
  <defs>
    <radialGradient id="pin{name}" cx="35%" cy="30%" r="0.6">
      <stop offset="0%" stop-color="{light}"/>
      <stop offset="60%" stop-color="{mid}"/>
      <stop offset="100%" stop-color="{dark}"/>
    </radialGradient>
    <filter id="pinShadow{name}" x="-15%" y="-5%" width="130%" height="130%">
      <feDropShadow dx="0" dy="3" stdDeviation="2.5" flood-color="#000" flood-opacity="0.5"/>
    </filter>
  </defs>
  <g filter="url(#pinShadow{name})">
    <circle cx="22" cy="22" r="18" fill="url(#pin{name})"/>
    <!-- inner rim shadow -->
    <circle cx="22" cy="22" r="18" fill="none" stroke="{dark}" stroke-width="1.5" opacity="0.5"/>
    <!-- top sparkle -->
    <ellipse cx="15" cy="14" rx="5.5" ry="3.5" fill="#FFFFFF" opacity="0.55"/>
    <ellipse cx="14" cy="13" rx="2" ry="1.4" fill="#FFFFFF" opacity="0.85"/>
  </g>
</svg>
"""


# ============================================================
# 12. Level completion star — small gold rosette without ribbons
# ============================================================
LEVEL_STAR_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 76 76" width="76" height="76">
  <defs>
    <linearGradient id="starG2" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#F1CB6E"/>
      <stop offset="100%" stop-color="#8a6520"/>
    </linearGradient>
    <filter id="starShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity="0.45"/>
    </filter>
  </defs>
  <g filter="url(#starShadow)">
    <!-- Dark gold outer ring -->
    <circle cx="38" cy="38" r="34" fill="#6a4f15"/>
    <!-- 12 scallop bumps -->
    <circle cx="38" cy="6"  r="4.5" fill="#6a4f15"/>
    <circle cx="54" cy="11" r="4.5" fill="#6a4f15"/>
    <circle cx="65" cy="22" r="4.5" fill="#6a4f15"/>
    <circle cx="70" cy="38" r="4.5" fill="#6a4f15"/>
    <circle cx="65" cy="54" r="4.5" fill="#6a4f15"/>
    <circle cx="54" cy="65" r="4.5" fill="#6a4f15"/>
    <circle cx="38" cy="70" r="4.5" fill="#6a4f15"/>
    <circle cx="22" cy="65" r="4.5" fill="#6a4f15"/>
    <circle cx="11" cy="54" r="4.5" fill="#6a4f15"/>
    <circle cx="6"  cy="38" r="4.5" fill="#6a4f15"/>
    <circle cx="11" cy="22" r="4.5" fill="#6a4f15"/>
    <circle cx="22" cy="11" r="4.5" fill="#6a4f15"/>
    <!-- Gold face -->
    <circle cx="38" cy="38" r="29" fill="url(#starG2)"/>
    <ellipse cx="30" cy="28" rx="9" ry="6" fill="#F1CB6E" opacity="0.6"/>
    <!-- Inner darker ring -->
    <circle cx="38" cy="38" r="22" fill="none" stroke="#8a6520" stroke-width="1.5"/>
    <!-- 5-point star -->
    <polygon points="38,19 42.5,32 56,32 45,40 49,53 38,45 27,53 31,40 20,32 33.5,32" fill="#7A5518"/>
    <polygon points="38,19 39.7,25 42.5,32 38,32" fill="#F1CB6E" opacity="0.5"/>
  </g>
</svg>
"""


# ============================================================
# 13. Question-mark stamp — pixel-art "?" for locked levels
# Rendered as 16×16 pixel art at large scale so it stays crisp
# when the game scales it to fit any card frame size.
# ============================================================
QUESTION_MARK_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="320" height="320" shape-rendering="crispEdges">
  <g fill="#E5D4B0">
    <!-- Top of curve -->
    <rect x="5" y="1" width="6" height="1"/>
    <!-- Sides of curve -->
    <rect x="4" y="2" width="2" height="1"/>
    <rect x="10" y="2" width="2" height="1"/>
    <rect x="3" y="3" width="2" height="1"/>
    <rect x="11" y="3" width="2" height="1"/>
    <!-- Tail descending diagonally from upper-right -->
    <rect x="11" y="4" width="2" height="1"/>
    <rect x="10" y="5" width="2" height="1"/>
    <rect x="9" y="6" width="2" height="1"/>
    <rect x="8" y="7" width="2" height="1"/>
    <!-- Stem -->
    <rect x="7" y="8" width="2" height="4"/>
    <!-- Dot -->
    <rect x="7" y="13" width="2" height="2"/>
  </g>
  <!-- Subtle 1-pixel shadow on the right edge for depth -->
  <g fill="#7A5F32" opacity="0.5">
    <rect x="11" y="2" width="1" height="1"/>
    <rect x="12" y="3" width="1" height="1"/>
    <rect x="12" y="4" width="1" height="1"/>
    <rect x="11" y="5" width="1" height="1"/>
    <rect x="10" y="6" width="1" height="1"/>
    <rect x="9" y="7" width="1" height="1"/>
    <rect x="8" y="8" width="1" height="4"/>
    <rect x="8" y="13" width="1" height="2"/>
  </g>
</svg>
"""


# ============================================================
# Generate everything
# ============================================================

# Card geometries: (W, H, paper_inset, frame_x, frame_y, frame_w, frame_h, with_corners)
CARDS = {
    # S — 220×260 at 2x. Picture: 176×176 at (22, 22). Bottom margin 60.
    "card_s":  (220, 260, 10, 22,  22, 176, 176, False),
    # M — 300×360 at 2x. Picture: 256×260 at (22, 22). Bottom margin 78.
    "card_m":  (300, 360, 10, 22,  22, 256, 260, False),
    # L — 540×336 at 2x. Picture: 460×264 at (40, 22). Bottom margin 50.
    "card_l":  (540, 336, 10, 40,  22, 460, 264, False),
    # XL — 560×640 at 2x. Picture: 488×488 at (36, 36). Bottom margin 116. Has corner brackets.
    "card_xl": (560, 640, 14, 36,  36, 488, 488, True),
}

PUSHPINS = {
    "red":    ("#FFB4B4", "#C24878", "#6E1A48"),
    "gold":   ("#FFE090", "#D4A845", "#6a4f15"),
    "silver": ("#FFFFFF", "#B8B8B8", "#555555"),
    "teal":   ("#B0E0F0", "#4A7585", "#173544"),
}

files = {
    "page_parchment.svg": PAGE_PARCHMENT_SVG,
    "page_ribbon_burgundy.svg": PAGE_RIBBON_BURGUNDY_SVG,
    "back_button.svg": BACK_BUTTON_SVG,
    "level_star.svg": LEVEL_STAR_SVG,
}

# Sepia palette for locked cards — warm aged-paper tones, not pure black
SEPIA_LOCKED = dict(
    paper_top="#E5D4B0",     # warm cream
    paper_bot="#B8966C",     # tan
    frame_top="#5A3F22",     # warm dark brown (not black)
    frame_bot="#3D2814",     # darker warm brown
    corner_top="#A88848",    # tarnished brass (XL only)
    corner_bot="#5A4018",
    corner_stroke="#3A2810",
)

# Generate normal + sepia-locked variant of each card
for tag_short, params in CARDS.items():
    W, H, pi, fx, fy, fw, fh, corners = params
    # Normal (unlocked) variant — empty frame, game draws pixel art into it
    files[f"{tag_short}.svg"] = card_svg(
        W, H, pi, fx, fy, fw, fh,
        with_corners=corners, tag=tag_short
    )
    # Sepia-locked variant — pixel-art "?" baked in, no game-side compositing needed
    files[f"{tag_short}_locked.svg"] = card_svg(
        W, H, pi, fx, fy, fw, fh,
        with_corners=corners, tag=f"{tag_short}_locked",
        embed_question_mark=True,
        **SEPIA_LOCKED,
    )

for color, (light, mid, dark) in PUSHPINS.items():
    files[f"pushpin_{color}.svg"] = pushpin_svg(color, light, mid, dark)

print("Writing SVGs:")
for name, svg in files.items():
    path = SVG_DIR / name
    path.write_text(svg)
    print(f"  {name} ({path.stat().st_size:,} bytes)")

print("\nConverting to PNG:")
for name in files.keys():
    svg_path = SVG_DIR / name
    png_path = PNG_DIR / (svg_path.stem + ".png")
    cairosvg.svg2png(url=str(svg_path), write_to=str(png_path))
    print(f"  {png_path.name} ({png_path.stat().st_size:,} bytes)")

print("\nDone.")
