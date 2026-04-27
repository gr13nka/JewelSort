#!/usr/bin/env python3
"""Generate JewelSort book-select screen assets as SVG + PNG."""

import cairosvg
import pathlib
import sys

ROOT = pathlib.Path(__file__).parent
SVG_DIR = ROOT / "svg"
PNG_DIR = ROOT / "png"
SVG_DIR.mkdir(exist_ok=True)
PNG_DIR.mkdir(exist_ok=True)

# ============================================================
# Reusable SVG fragments — emblems live inside each book's plate
# All emblems use viewBox 0 0 100 100, so they can be transformed
# ============================================================

EMBLEM_SAPLING = """
<g transform="translate({x} {y}) scale({s})" shape-rendering="crispEdges">
  <g fill="#7BB04A">
    <rect x="3" y="3" width="2" height="1"/>
    <rect x="2" y="4" width="4" height="1"/>
    <rect x="2" y="5" width="4" height="1"/>
    <rect x="3" y="6" width="3" height="1"/>
    <rect x="4" y="7" width="2" height="1"/>
  </g>
  <g fill="#558238">
    <rect x="3" y="5" width="3" height="1"/>
    <rect x="4" y="6" width="2" height="1"/>
  </g>
  <g fill="#7BB04A">
    <rect x="11" y="3" width="2" height="1"/>
    <rect x="10" y="4" width="4" height="1"/>
    <rect x="10" y="5" width="4" height="1"/>
    <rect x="10" y="6" width="3" height="1"/>
    <rect x="10" y="7" width="2" height="1"/>
  </g>
  <g fill="#558238">
    <rect x="10" y="5" width="3" height="1"/>
    <rect x="10" y="6" width="2" height="1"/>
  </g>
  <g fill="#7B5A2E">
    <rect x="7" y="5" width="2" height="6"/>
  </g>
  <g fill="#5A3F1A">
    <rect x="8" y="5" width="1" height="6"/>
  </g>
  <g fill="#6B4226">
    <rect x="3" y="11" width="10" height="1"/>
    <rect x="2" y="12" width="12" height="1"/>
    <rect x="1" y="13" width="14" height="1"/>
  </g>
  <g fill="#3F230E">
    <rect x="2" y="13" width="12" height="1"/>
    <rect x="4" y="12" width="1" height="1"/>
    <rect x="9" y="12" width="1" height="1"/>
    <rect x="11" y="11" width="1" height="1"/>
  </g>
</g>
"""

EMBLEM_BASKET = """
<g transform="translate({x} {y}) scale({s})" shape-rendering="crispEdges">
  <g fill="#C2272C">
    <rect x="2" y="2" width="3" height="1"/>
    <rect x="1" y="3" width="5" height="2"/>
  </g>
  <g fill="#FF5446"><rect x="1" y="3" width="2" height="1"/></g>
  <g fill="#FFFFFF">
    <rect x="2" y="3" width="1" height="1"/>
    <rect x="4" y="4" width="1" height="1"/>
  </g>
  <g fill="#F4E0B8"><rect x="2" y="5" width="3" height="1"/></g>
  <g fill="#E5A82A">
    <rect x="9" y="2" width="3" height="1"/>
    <rect x="8" y="3" width="5" height="2"/>
  </g>
  <g fill="#F1CB6E"><rect x="8" y="3" width="2" height="1"/></g>
  <g fill="#7A5518"><rect x="10" y="4" width="1" height="1"/></g>
  <g fill="#F4E0B8"><rect x="9" y="5" width="3" height="1"/></g>
  <g fill="#5A3A1A"><rect x="0" y="6" width="16" height="1"/></g>
  <g fill="#7B5A2E"><rect x="0" y="7" width="16" height="1"/></g>
  <g fill="#9F6638"><rect x="0" y="8" width="16" height="5"/></g>
  <g fill="#5A3A1A">
    <rect x="1" y="9" width="2" height="1"/>
    <rect x="5" y="9" width="2" height="1"/>
    <rect x="9" y="9" width="2" height="1"/>
    <rect x="13" y="9" width="2" height="1"/>
    <rect x="3" y="11" width="2" height="1"/>
    <rect x="7" y="11" width="2" height="1"/>
    <rect x="11" y="11" width="2" height="1"/>
  </g>
  <g fill="#C29568">
    <rect x="3" y="9" width="2" height="1"/>
    <rect x="7" y="9" width="2" height="1"/>
    <rect x="11" y="9" width="2" height="1"/>
    <rect x="15" y="9" width="1" height="1"/>
    <rect x="0" y="11" width="3" height="1"/>
    <rect x="5" y="11" width="2" height="1"/>
    <rect x="9" y="11" width="2" height="1"/>
    <rect x="13" y="11" width="2" height="1"/>
  </g>
  <g fill="#3F230E"><rect x="0" y="13" width="16" height="1"/></g>
</g>
"""

EMBLEM_OWL = """
<g transform="translate({x} {y}) scale({s})" shape-rendering="crispEdges">
  <g fill="#6B4226">
    <rect x="2" y="0" width="2" height="3"/>
    <rect x="12" y="0" width="2" height="3"/>
  </g>
  <g fill="#8B5A2B">
    <rect x="2" y="2" width="2" height="1"/>
    <rect x="12" y="2" width="2" height="1"/>
  </g>
  <g fill="#6B4226"><rect x="1" y="3" width="14" height="1"/></g>
  <g fill="#A87A4D">
    <rect x="0" y="4" width="16" height="9"/>
    <rect x="1" y="13" width="14" height="1"/>
    <rect x="2" y="14" width="12" height="1"/>
  </g>
  <g fill="#8B5A2B">
    <rect x="0" y="4" width="1" height="9"/>
    <rect x="15" y="4" width="1" height="9"/>
    <rect x="1" y="13" width="1" height="1"/>
    <rect x="14" y="13" width="1" height="1"/>
  </g>
  <g fill="#3A2418">
    <rect x="2" y="5" width="4" height="4"/>
    <rect x="10" y="5" width="4" height="4"/>
  </g>
  <g fill="#FFF6D8">
    <rect x="3" y="6" width="2" height="2"/>
    <rect x="11" y="6" width="2" height="2"/>
  </g>
  <g fill="#1a1a1a">
    <rect x="4" y="6" width="1" height="2"/>
    <rect x="12" y="6" width="1" height="2"/>
  </g>
  <g fill="#FFFFFF">
    <rect x="3" y="6" width="1" height="1"/>
    <rect x="11" y="6" width="1" height="1"/>
  </g>
  <g fill="#E5A82A"><rect x="7" y="8" width="2" height="2"/></g>
  <g fill="#9F6638"><rect x="7" y="10" width="2" height="1"/></g>
  <g fill="#E8C896">
    <rect x="3" y="10" width="2" height="1"/>
    <rect x="2" y="11" width="12" height="2"/>
    <rect x="11" y="10" width="2" height="1"/>
  </g>
  <g fill="#8B5A2B">
    <rect x="5" y="11" width="1" height="1"/>
    <rect x="7" y="12" width="1" height="1"/>
    <rect x="9" y="11" width="1" height="1"/>
  </g>
  <g fill="#E5A82A">
    <rect x="3" y="14" width="2" height="1"/>
    <rect x="11" y="14" width="2" height="1"/>
    <rect x="3" y="15" width="2" height="1"/>
    <rect x="11" y="15" width="2" height="1"/>
  </g>
</g>
"""

EMBLEM_COMPASS = """
<g transform="translate({x} {y}) scale({s})" shape-rendering="crispEdges">
  <g fill="#D4A845">
    <rect x="6" y="6" width="4" height="4"/>
    <rect x="5" y="7" width="6" height="2"/>
    <rect x="7" y="5" width="2" height="6"/>
    <rect x="7" y="2" width="2" height="3"/>
    <rect x="6" y="3" width="4" height="1"/>
    <rect x="7" y="11" width="2" height="3"/>
    <rect x="6" y="12" width="4" height="1"/>
    <rect x="2" y="7" width="3" height="2"/>
    <rect x="3" y="6" width="1" height="4"/>
    <rect x="11" y="7" width="3" height="2"/>
    <rect x="12" y="6" width="1" height="4"/>
    <rect x="2" y="2" width="2" height="2"/>
    <rect x="12" y="2" width="2" height="2"/>
    <rect x="2" y="12" width="2" height="2"/>
    <rect x="12" y="12" width="2" height="2"/>
  </g>
  <g fill="#7A5518"><rect x="7" y="7" width="2" height="2"/></g>
  <g fill="#F1CB6E">
    <rect x="6" y="6" width="1" height="1"/>
    <rect x="2" y="2" width="1" height="1"/>
    <rect x="12" y="2" width="1" height="1"/>
  </g>
</g>
"""


# ============================================================
# Each book is generated by this template
# All books are 1040x360 at 2x scale
# ============================================================

def book_svg(tag, cover_main, cover_dark, cover_light_overlay,
             spine_main_a, spine_main_b, spine_main_c,
             emblem_svg):
    """Generate a book SVG with the given color theme and emblem."""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1040 360" width="1040" height="360">
  <defs>
    <linearGradient id="cover_{tag}" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="{cover_light_overlay}"/>
      <stop offset="50%" stop-color="{cover_main}"/>
      <stop offset="100%" stop-color="{cover_dark}"/>
    </linearGradient>
    <radialGradient id="cover_hl_{tag}" cx="30%" cy="20%" r="0.6">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.15"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="spine_{tag}" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="{spine_main_a}"/>
      <stop offset="50%" stop-color="{spine_main_b}"/>
      <stop offset="100%" stop-color="{spine_main_c}"/>
    </linearGradient>
    <linearGradient id="pages_{tag}" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FBF0D2"/>
      <stop offset="100%" stop-color="#E8D4A6"/>
    </linearGradient>
    <linearGradient id="plate_{tag}" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#F4E0B8"/>
      <stop offset="100%" stop-color="#D9BB7E"/>
    </linearGradient>
    <filter id="shadow_{tag}" x="-2%" y="-2%" width="104%" height="115%">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#281808" flood-opacity="0.35"/>
    </filter>
  </defs>

  <!-- Pages background (extends below cover for visible page edge) -->
  <rect x="8" y="8" width="1024" height="344" rx="14" fill="url(#pages_{tag})"
        filter="url(#shadow_{tag})"/>

  <!-- Pages edge texture: thin striations at the bottom -->
  <g opacity="0.18">
    {''.join(f'<rect x="{8 + i*4}" y="340" width="2" height="8" fill="#8C6432"/>' for i in range(255))}
  </g>

  <!-- Main cover (sits on top, leaves 12px page edge below) -->
  <rect x="0" y="0" width="1040" height="338" rx="14" fill="url(#cover_{tag})"/>
  <rect x="0" y="0" width="1040" height="338" rx="14" fill="url(#cover_hl_{tag})"/>

  <!-- Spine (left section, slightly darker) -->
  <path d="M 0 14 Q 0 0 14 0 L 52 0 L 52 338 L 14 338 Q 0 338 0 324 Z" fill="url(#spine_{tag})"/>
  <line x1="52" y1="0" x2="52" y2="338" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>

  <!-- Spine bands -->
  <rect x="8" y="44" width="36" height="6" rx="2" fill="#D4A845"/>
  <rect x="8" y="50" width="36" height="2" fill="#8a6520"/>
  <rect x="8" y="288" width="36" height="6" rx="2" fill="#D4A845"/>
  <rect x="8" y="294" width="36" height="2" fill="#8a6520"/>

  <!-- Embossed inner frame -->
  <rect x="68" y="16" width="956" height="306" rx="8"
        fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="4"/>
  <rect x="64" y="12" width="964" height="314" rx="10"
        fill="none" stroke="rgba(0,0,0,0.20)" stroke-width="2"/>

  <!-- Art plate -->
  <rect x="92" y="50" width="220" height="220" rx="8" fill="url(#plate_{tag})"/>
  <rect x="92" y="50" width="220" height="220" rx="8"
        fill="none" stroke="rgba(80,50,20,0.35)" stroke-width="3"/>

  <!-- Emblem -->
  {emblem_svg}
</svg>
"""

# Pixel-art emblems use a 16x16 viewBox. Plate is 220x220 at (92, 50).
# Scale 13 gives 16*13 = 208 pixels — fits with 6px margin each side.
# Integer scale ensures every emblem pixel becomes exactly 13 output pixels (no anti-aliasing).
EMBLEM_X = 98
EMBLEM_Y = 56
EMBLEM_S = 13


# ============================================================
# Generate the 4 books
# ============================================================

books = {
    "first_steps": dict(
        cover_main="#8E2A2A", cover_dark="#5C1718", cover_light_overlay="#B8443F",
        spine_main_a="#5C1718", spine_main_b="#7A1F20", spine_main_c="#6E1A1B",
        emblem=EMBLEM_SAPLING,
    ),
    "forest_harvest": dict(
        cover_main="#4A6B3A", cover_dark="#2D4422", cover_light_overlay="#6B8E5A",
        spine_main_a="#2D4422", spine_main_b="#3E5A2E", spine_main_c="#345126",
        emblem=EMBLEM_BASKET,
    ),
    "forest_friends": dict(
        cover_main="#2E5566", cover_dark="#173544", cover_light_overlay="#4A7585",
        spine_main_a="#173544", spine_main_b="#25455A", spine_main_c="#1F3A4D",
        emblem=EMBLEM_OWL,
    ),
    "shapes_symbols": dict(
        cover_main="#5A3661", cover_dark="#311738", cover_light_overlay="#7A4F82",
        spine_main_a="#311738", spine_main_b="#4A2750", spine_main_c="#3D1E45",
        emblem=EMBLEM_COMPASS,
    ),
}

for name, p in books.items():
    emblem_filled = p["emblem"].format(x=EMBLEM_X, y=EMBLEM_Y, s=EMBLEM_S, tag=name)
    svg = book_svg(
        tag=name,
        cover_main=p["cover_main"], cover_dark=p["cover_dark"],
        cover_light_overlay=p["cover_light_overlay"],
        spine_main_a=p["spine_main_a"], spine_main_b=p["spine_main_b"],
        spine_main_c=p["spine_main_c"],
        emblem_svg=emblem_filled,
    )
    (SVG_DIR / f"book_{name}.svg").write_text(svg)


# ============================================================
# Background — wood panel
# ============================================================

BG_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1080 1920" width="1080" height="1920">
  <defs>
    <linearGradient id="woodMain" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#D89456"/>
      <stop offset="60%" stop-color="#9F6638"/>
      <stop offset="100%" stop-color="#583519"/>
    </linearGradient>
    <radialGradient id="woodHl" cx="30%" cy="20%" r="0.7">
      <stop offset="0%" stop-color="#FFE6B4" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="#FFE6B4" stop-opacity="0"/>
    </radialGradient>
    <!-- Wood grain: dense dark stripes (2px every 12px = original 1px every 6px at 2x) -->
    <pattern id="grainDark" patternUnits="userSpaceOnUse" width="12" height="200">
      <rect x="0" y="0" width="2" height="200" fill="#3C1E0A" opacity="0.18"/>
    </pattern>
    <!-- Wood grain: sparser light stripes (4px every 26px = original 2px every 13px at 2x) -->
    <pattern id="grainLight" patternUnits="userSpaceOnUse" width="26" height="200">
      <rect x="0" y="0" width="4" height="200" fill="#FFE6B4" opacity="0.08"/>
    </pattern>
  </defs>
  <rect width="1080" height="1920" fill="url(#woodMain)"/>
  <rect width="1080" height="1920" fill="url(#woodHl)"/>
  <rect width="1080" height="1920" fill="url(#grainDark)"/>
  <rect width="1080" height="1920" fill="url(#grainLight)"/>
</svg>
"""
(SVG_DIR / "bg_wood.svg").write_text(BG_SVG)


# ============================================================
# Bookmark ribbon
# ============================================================

RIBBON_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 140" width="72" height="140">
  <defs>
    <linearGradient id="ribbonG" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#F4E0B8"/>
      <stop offset="100%" stop-color="#DCC499"/>
    </linearGradient>
    <filter id="ribbonShadow" x="-15%" y="-5%" width="130%" height="115%">
      <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <g filter="url(#ribbonShadow)">
    <path d="M 0 0 L 72 0 L 72 140 L 36 112 L 0 140 Z" fill="url(#ribbonG)"/>
    <rect x="0" y="0" width="72" height="6" fill="#000" opacity="0.18"/>
    <rect x="0" y="0" width="4" height="140" fill="#FFFFFF" opacity="0.4"/>
    <rect x="68" y="0" width="4" height="140" fill="#000" opacity="0.12"/>
  </g>
</svg>
"""
(SVG_DIR / "bookmark_ribbon.svg").write_text(RIBBON_SVG)


# ============================================================
# Completion medal — gold rosette + burgundy ribbon tails
# ============================================================

MEDAL_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 176" width="128" height="176">
  <defs>
    <filter id="medalShadow" x="-10%" y="-5%" width="120%" height="115%">
      <feDropShadow dx="0" dy="4" stdDeviation="4" flood-color="#000" flood-opacity="0.4"/>
    </filter>
  </defs>
  <g transform="rotate(-7 64 64)" filter="url(#medalShadow)">
    <!-- ribbon tails -->
    <path d="M 36 76 L 24 160 L 44 148 L 48 100 Z" fill="#8E2A2A"/>
    <path d="M 28 152 L 24 160 L 38 152 Z" fill="#5C1718"/>
    <path d="M 92 76 L 104 160 L 84 148 L 80 100 Z" fill="#8E2A2A"/>
    <path d="M 100 152 L 104 160 L 90 152 Z" fill="#5C1718"/>
    <path d="M 38 80 L 34 116 L 38 116 Z" fill="#FFFFFF" opacity="0.18"/>
    <path d="M 90 80 L 94 116 L 90 116 Z" fill="#FFFFFF" opacity="0.18"/>

    <!-- medallion outer dark ring -->
    <circle cx="64" cy="64" r="52" fill="#6a4f15"/>

    <!-- 12 scallop bumps -->
    <circle cx="64" cy="12" r="7"  fill="#6a4f15"/>
    <circle cx="90" cy="19" r="7"  fill="#6a4f15"/>
    <circle cx="109" cy="38" r="7" fill="#6a4f15"/>
    <circle cx="116" cy="64" r="7" fill="#6a4f15"/>
    <circle cx="109" cy="90" r="7" fill="#6a4f15"/>
    <circle cx="90" cy="109" r="7" fill="#6a4f15"/>
    <circle cx="64" cy="116" r="7" fill="#6a4f15"/>
    <circle cx="38" cy="109" r="7" fill="#6a4f15"/>
    <circle cx="19" cy="90" r="7"  fill="#6a4f15"/>
    <circle cx="12" cy="64" r="7"  fill="#6a4f15"/>
    <circle cx="19" cy="38" r="7"  fill="#6a4f15"/>
    <circle cx="38" cy="19" r="7"  fill="#6a4f15"/>

    <!-- gold face -->
    <circle cx="64" cy="64" r="44" fill="#D4A845"/>
    <ellipse cx="50" cy="48" rx="18" ry="12" fill="#F1CB6E" opacity="0.6"/>

    <!-- inner darker ring -->
    <circle cx="64" cy="64" r="34" fill="none" stroke="#8a6520" stroke-width="3"/>

    <!-- 5-point star -->
    <polygon points="64,36 71.4,57 94,57 76,70 83,92 64,78 45,92 52,70 34,57 56.6,57"
             fill="#7A5518"/>
    <polygon points="64,36 67,48 71.4,57 64,57" fill="#F1CB6E" opacity="0.5"/>
  </g>
</svg>
"""
(SVG_DIR / "medal_completion.svg").write_text(MEDAL_SVG)


# ============================================================
# Jewel counter pill — wood panel + blue gem (no number)
# ============================================================

COUNTER_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 96" width="200" height="96">
  <defs>
    <linearGradient id="pillG" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#9F6638"/>
      <stop offset="100%" stop-color="#583519"/>
    </linearGradient>
    <linearGradient id="gemBody" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#E04B8E"/>
      <stop offset="100%" stop-color="#8E2A48"/>
    </linearGradient>
    <linearGradient id="gemTable" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FFB0D8"/>
      <stop offset="100%" stop-color="#D85088"/>
    </linearGradient>
    <filter id="counterShadow" x="-5%" y="-5%" width="110%" height="120%">
      <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity="0.3"/>
    </filter>
    <filter id="gemShadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#000" flood-opacity="0.4"/>
    </filter>
  </defs>
  <g filter="url(#counterShadow)">
    <!-- Wooden pill -->
    <rect x="6" y="6" width="188" height="78" rx="20" fill="url(#pillG)" stroke="#3a2410" stroke-width="3"/>
    <!-- Top-edge highlight -->
    <rect x="14" y="10" width="172" height="3" rx="1.5" fill="#FFFFFF" opacity="0.25"/>
  </g>

  <!-- Faceted rose-magenta gem -->
  <g transform="translate(45 45)" filter="url(#gemShadow)">
    <!-- Main octagonal silhouette -->
    <polygon points="-9,-22 9,-22 22,-8 22,8 9,22 -9,22 -22,8 -22,-8"
             fill="url(#gemBody)" stroke="#5C1838" stroke-width="2.2" stroke-linejoin="round"/>

    <!-- Top crown facet (lighter, the "table" of the cut) -->
    <polygon points="-9,-22 9,-22 14,-10 -14,-10"
             fill="url(#gemTable)" stroke="#5C1838" stroke-width="1" opacity="0.95"/>

    <!-- Crown side facets -->
    <polygon points="-9,-22 -22,-8 -14,-10" fill="#A03862" opacity="0.85"/>
    <polygon points="9,-22 22,-8 14,-10" fill="#A03862" opacity="0.85"/>

    <!-- Girdle line (widest part of gem) -->
    <line x1="-22" y1="-1" x2="22" y2="-1" stroke="#FFB0D8" stroke-width="0.8" opacity="0.45"/>
    <line x1="-22" y1="1" x2="22" y2="1" stroke="#5C1838" stroke-width="0.6" opacity="0.4"/>

    <!-- Pavilion (lower half) facet lines radiating to bottom -->
    <line x1="-22" y1="8" x2="0" y2="22" stroke="#5C1838" stroke-width="0.9" opacity="0.55"/>
    <line x1="22" y1="8" x2="0" y2="22" stroke="#5C1838" stroke-width="0.9" opacity="0.55"/>
    <line x1="-9" y1="22" x2="0" y2="0" stroke="#5C1838" stroke-width="0.6" opacity="0.4"/>
    <line x1="9" y1="22" x2="0" y2="0" stroke="#5C1838" stroke-width="0.6" opacity="0.4"/>

    <!-- Specular highlight on table -->
    <polygon points="-7,-19 0,-20 -2,-14 -7,-13" fill="#FFFFFF" opacity="0.75"/>
    <!-- Tiny secondary sparkle -->
    <circle cx="11" cy="-15" r="1.2" fill="#FFFFFF" opacity="0.7"/>
  </g>
</svg>
"""
(SVG_DIR / "counter_jewels.svg").write_text(COUNTER_SVG)


# ============================================================
# Lock clasp — iron padlock
# ============================================================

LOCK_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 76 76" width="76" height="76">
  <defs>
    <linearGradient id="lockBody" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#6e6e6e"/>
      <stop offset="50%" stop-color="#3a3a3a"/>
      <stop offset="100%" stop-color="#1f1f1f"/>
    </linearGradient>
    <filter id="lockShadow" x="-10%" y="-5%" width="120%" height="115%">
      <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity="0.4"/>
    </filter>
  </defs>
  <g filter="url(#lockShadow)">
    <!-- shackle -->
    <path d="M 22 35 L 22 26 a 16 16 0 0 1 32 0 L 54 35"
          stroke="#a8a8a8" stroke-width="6" fill="none" stroke-linecap="round"/>
    <path d="M 22 35 L 22 26 a 16 16 0 0 1 32 0 L 54 35"
          stroke="#3a3a3a" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.5"/>
    <!-- body -->
    <rect x="14" y="34" width="48" height="32" rx="6" fill="url(#lockBody)" stroke="#1a1a1a" stroke-width="2"/>
    <!-- top edge highlight -->
    <rect x="18" y="36" width="40" height="2" fill="#FFFFFF" opacity="0.25"/>
    <!-- keyhole -->
    <circle cx="38" cy="48" r="3" fill="#1a1a1a"/>
    <rect x="36.5" y="50" width="3" height="6" fill="#1a1a1a"/>
    <!-- horizontal embossed line -->
    <line x1="20" y1="60" x2="56" y2="60" stroke="#FFFFFF" opacity="0.08" stroke-width="1"/>
  </g>
</svg>
"""
(SVG_DIR / "book_lock.svg").write_text(LOCK_SVG)


# ============================================================
# Convert all SVG to PNG
# ============================================================

print("Generated SVGs:")
for f in sorted(SVG_DIR.iterdir()):
    print(f"  {f.name} ({f.stat().st_size} bytes)")

print("\nConverting to PNG...")
for svg_file in sorted(SVG_DIR.iterdir()):
    png_file = PNG_DIR / (svg_file.stem + ".png")
    cairosvg.svg2png(
        url=str(svg_file),
        write_to=str(png_file),
    )
    print(f"  {png_file.name} ({png_file.stat().st_size} bytes)")

print("\nDone.")
