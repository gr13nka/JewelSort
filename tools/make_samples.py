#!/usr/bin/env python3
"""
Fallback sample-PNG generator used when running `love tools/make_samples.lua`
isn't convenient. Writes minimal RGBA PNGs using only the Python standard
library (zlib + struct), so no PIL/Pillow dependency.

Run:
    python3 tools/make_samples.py

Outputs:
    levels/sample_smile.png   (8x8)
    levels/sample_heart.png   (12x12)
"""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
LEVELS = os.path.join(PROJECT, "levels")


def write_png(path, pixels, width, height):
    """pixels: list of (r, g, b, a) rows, row-major, length = width*height."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: None
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw.extend([r, g, b, a])
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
        )
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # RGBA, 8bpp
    idat = zlib.compress(bytes(raw), 9)
    iend = b""
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", iend))


def render_grid(grid, palette):
    height = len(grid)
    width = len(grid[0])
    pixels = [(0, 0, 0, 0)] * (width * height)
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            if ch == ".":
                pixels[y * width + x] = (0, 0, 0, 0)
            else:
                r, g, b = palette[ch]
                pixels[y * width + x] = (r, g, b, 255)
    return pixels, width, height


def make_smile():
    palette = {
        "Y": (250, 210, 60),
        "K": (30, 30, 30),
        "R": (220, 60, 70),
    }
    grid = [
        "..YYYY..",
        ".YYYYYY.",
        "YYKYYKYY",
        "YYYYYYYY",
        "YYYYYYYY",
        "YRYYYYRY",
        ".YRRRRY.",
        "..YYYY..",
    ]
    return render_grid(grid, palette)


def make_heart():
    palette = {
        "R": (220, 40, 60),
        "P": (255, 180, 200),
        "K": (80, 10, 20),
    }
    grid = [
        "............",
        "..KKK..KKK..",
        ".KPPRKKRPPK.",
        "KPPRRRRRRPPK",
        "KPRRRRRRRRRK",
        "KRRRRRRRRRRK",
        ".KRRRRRRRRK.",
        "..KRRRRRRK..",
        "...KRRRRK...",
        "....KRRK....",
        ".....KK.....",
        "............",
    ]
    return render_grid(grid, palette)


def main():
    os.makedirs(LEVELS, exist_ok=True)
    for name, builder in [("sample_smile", make_smile), ("sample_heart", make_heart)]:
        pixels, w, h = builder()
        path = os.path.join(LEVELS, f"{name}.png")
        write_png(path, pixels, w, h)
        print(f"wrote {path} ({w}x{h})")


if __name__ == "__main__":
    main()
