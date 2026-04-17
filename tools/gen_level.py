#!/usr/bin/env python3
"""
Generate a JewelSort level by prompting ComfyUI for an object illustration,
cropping it to the subject, and downsampling to pixel art via Pyxelate.

Usage:
    python tools/gen_level.py --theme "autumn leaves" --name autumn

Prerequisites:
    - ComfyUI running at --comfy-url (default http://127.0.0.1:8188).
    - Flux stack already present in ~/ComfyUI/models/: flux1-dev GGUF
      UNet, t5xxl + clip_l text encoders, ae.safetensors VAE, and one
      of the Envy/icon Flux LoRAs.
    - pip install -r tools/requirements.txt

Pipeline: diffusion → corner-bg detect → crop to subject bbox →
Lanczos resize to size*16 → Pyxelate (gradient-oriented downsample +
Bayesian-GMM palette) → cut background to alpha 0.
"""
import argparse
import io
import json
import random
import sys
import time
import uuid
from collections import Counter
from pathlib import Path

import numpy as np
import requests
from PIL import Image, ImageChops
from pyxelate import Pyx

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
LEVELS_DIR = PROJECT / "levels"
WORKFLOW_PATH = HERE / "comfy_workflows" / "pixel_art_flux.json"
CACHE_DIR = HERE / "_gen_cache"

# Pyxelate downsample ratio; input side = size * PYX_FACTOR.
PYX_FACTOR = 16

POSITIVE_TEMPLATE = (
    "kawaii sticker of a single {theme}, centered, isolated object "
    "on plain white background, cute cartoon illustration, full color, "
    "bold outline, clean shapes"
)
# Flux runs at cfg=1, so negative conditioning is largely a no-op.
NEGATIVE_PROMPT = ""


def build_workflow(theme: str, seed: int, lora_name: str,
                   width: int = 1024, height: int = 1024) -> dict:
    wf = json.loads(WORKFLOW_PATH.read_text())
    wf["4"]["inputs"]["lora_name"] = lora_name
    wf["5"]["inputs"]["text"] = POSITIVE_TEMPLATE.format(theme=theme)
    wf["6"]["inputs"]["text"] = NEGATIVE_PROMPT
    wf["9"]["inputs"]["seed"] = seed
    wf["8"]["inputs"]["width"] = width
    wf["8"]["inputs"]["height"] = height
    return wf


def submit_workflow(comfy_url: str, workflow: dict) -> str:
    client_id = str(uuid.uuid4())
    resp = requests.post(
        f"{comfy_url}/prompt",
        json={"prompt": workflow, "client_id": client_id},
        timeout=30,
    )
    if resp.status_code >= 400:
        raise RuntimeError(
            f"ComfyUI rejected workflow ({resp.status_code}): {resp.text}"
        )
    data = resp.json()
    prompt_id = data.get("prompt_id")
    if not prompt_id:
        raise RuntimeError(f"ComfyUI did not return prompt_id: {data}")
    return prompt_id


def wait_for_output(comfy_url: str, prompt_id: str, timeout: int = 600) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        resp = requests.get(f"{comfy_url}/history/{prompt_id}", timeout=10)
        resp.raise_for_status()
        data = resp.json()
        entry = data.get(prompt_id)
        if entry:
            status_str = entry.get("status", {}).get("status_str")
            if status_str == "error":
                raise RuntimeError(
                    f"ComfyUI reported error: {entry.get('status')}"
                )
            if entry.get("outputs"):
                return entry["outputs"]
        time.sleep(1)
    raise TimeoutError(
        f"ComfyUI did not complete prompt {prompt_id} within {timeout}s"
    )


def fetch_image(comfy_url: str, outputs: dict) -> Image.Image:
    for node_outputs in outputs.values():
        for img_info in node_outputs.get("images", []):
            params = {
                "filename": img_info["filename"],
                "subfolder": img_info.get("subfolder", ""),
                "type": img_info.get("type", "output"),
            }
            resp = requests.get(
                f"{comfy_url}/view", params=params, timeout=30
            )
            resp.raise_for_status()
            return Image.open(io.BytesIO(resp.content)).copy()
    raise RuntimeError("No image found in ComfyUI outputs")


def find_bg_color(img: Image.Image) -> tuple:
    w, h = img.size
    corners = [
        img.getpixel((0, 0)),
        img.getpixel((w - 1, 0)),
        img.getpixel((0, h - 1)),
        img.getpixel((w - 1, h - 1)),
    ]
    return Counter(corners).most_common(1)[0][0][:3]


def crop_to_subject(img: Image.Image, bg: tuple,
                    tol: int = 24, pad: int = 8) -> Image.Image:
    # Threshold the |pixel - bg| delta and take the resulting bbox, so the
    # subject fills the frame regardless of where the diffusion put it.
    bg_img = Image.new("RGB", img.size, bg)
    diff = ImageChops.difference(img, bg_img).convert("L")
    mask = diff.point(lambda v: 255 if v > tol else 0)
    bbox = mask.getbbox()
    if bbox is None:
        return img
    l, t, r, b = bbox
    w, h = img.size
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(w, r + pad)
    b = min(h, b + pad)
    cropped = img.crop((l, t, r, b))
    # Square-pad so the pyxelate input is 1:1.
    side = max(cropped.size)
    square = Image.new("RGB", (side, side), bg)
    cw, ch = cropped.size
    square.paste(cropped, ((side - cw) // 2, (side - ch) // 2))
    return square


def quantize_to_grid(img: Image.Image, size: int, n_colors: int,
                     debug=None) -> Image.Image:
    src = img.convert("RGB")
    if debug: debug("01_source", src)

    bg = find_bg_color(src)
    cropped = crop_to_subject(src, bg)
    if debug: debug("02_cropped", cropped)

    pyx_side = size * PYX_FACTOR
    resized = cropped.resize((pyx_side, pyx_side), Image.LANCZOS)
    if debug: debug("03_resized", resized)

    arr = np.array(resized)
    pyx = Pyx(factor=PYX_FACTOR, palette=n_colors, dither="none")
    pyx.fit(arr)
    out = pyx.transform(arr)
    if out.dtype != np.uint8:
        out = (out * 255).clip(0, 255).astype(np.uint8)
    result = Image.fromarray(out)
    if debug: debug("04_pyxelated", result)
    return result


def cut_background(img: Image.Image) -> Image.Image:
    bg = find_bg_color(img)
    rgba = img.convert("RGBA")
    pixels = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            if pixels[x, y][:3] == bg:
                pixels[x, y] = (0, 0, 0, 0)
    return rgba


def sanity_check(img: Image.Image) -> None:
    w, h = img.size
    pixels = img.load()
    opaque = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a > 0:
                opaque.append((r, g, b))
    if len(opaque) < 10:
        raise RuntimeError(
            f"Too few opaque cells ({len(opaque)}); the background cut "
            f"consumed the subject. Try a different --seed or rephrase "
            f"--theme with a clearer subject/background separation."
        )
    palette = set(opaque)
    if len(palette) < 2:
        raise RuntimeError(
            f"Only {len(palette)} foreground color; need at least 2 for "
            f"a playable puzzle."
        )
    if len(opaque) >= w * h:
        raise RuntimeError(
            "Every cell is opaque — auto-background detection failed. "
            "Try a prompt that asks for a 'plain white background'."
        )
    print(f"Opaque cells: {len(opaque)} / {w * h}")
    print(f"Foreground palette ({len(palette)}): {sorted(palette)}")


def main() -> int:
    p = argparse.ArgumentParser(
        description="Generate JewelSort levels via ComfyUI + Pyxelate."
    )
    p.add_argument("--theme", required=True,
                   help="Theme string, e.g. 'autumn leaves'.")
    p.add_argument("--name", required=True,
                   help="Output filename stem (no extension).")
    p.add_argument("--size", type=int, default=32,
                   help="Target grid size per axis (default 32).")
    p.add_argument("--colors", type=int, default=5,
                   help="Palette size including background (default 5).")
    p.add_argument("--seed", type=int, default=None,
                   help="Generation seed (random if omitted).")
    p.add_argument("--comfy-url", default="http://127.0.0.1:8188")
    p.add_argument("--lora", default="EnvyFluxKawaiiSticker01.safetensors",
                   help="Flux LoRA filename under ~/ComfyUI/models/loras/ "
                        "(default EnvyFluxKawaiiSticker01.safetensors; "
                        "other installed options: icon_casual.safetensors, "
                        "flux-lora-000004.safetensors).")
    p.add_argument("--keep-raw", action="store_true",
                   help="Save the raw ComfyUI output under "
                        "tools/_gen_cache/.")
    p.add_argument("--debug", action="store_true",
                   help="Dump every pipeline stage into "
                        "tools/_gen_cache/ for inspection.")
    args = p.parse_args()

    if args.size < 8 or args.size > 96:
        print(f"--size {args.size} outside sensible range [8, 96]",
              file=sys.stderr)
        return 2
    if args.colors < 3 or args.colors > 16:
        print(f"--colors {args.colors} outside sensible range [3, 16]",
              file=sys.stderr)
        return 2

    seed = args.seed if args.seed is not None else random.randint(1, 2**31 - 1)
    print(f"Theme: {args.theme!r}  seed: {seed}")

    debug_cb = None
    if args.debug or args.keep_raw:
        CACHE_DIR.mkdir(exist_ok=True)
    if args.debug:
        stem = f"{args.name}_seed{seed}"
        def debug_cb(stage, image):
            path = CACHE_DIR / f"{stem}_{stage}.png"
            image.save(path)
            print(f"  debug: {path}")

    wf = build_workflow(args.theme, seed, args.lora)
    prompt_id = submit_workflow(args.comfy_url, wf)
    print(f"Submitted prompt {prompt_id}; waiting for ComfyUI…")
    outputs = wait_for_output(args.comfy_url, prompt_id)
    raw = fetch_image(args.comfy_url, outputs)

    if args.keep_raw:
        raw_path = CACHE_DIR / f"{args.name}_seed{seed}_raw.png"
        raw.save(raw_path)
        print(f"Raw image: {raw_path}")

    reduced = quantize_to_grid(raw, args.size, args.colors, debug=debug_cb)
    with_alpha = cut_background(reduced)
    sanity_check(with_alpha)

    LEVELS_DIR.mkdir(exist_ok=True)
    out_path = LEVELS_DIR / f"{args.name}.png"
    with_alpha.save(out_path)
    print(f"Wrote {out_path} ({args.size}x{args.size})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
