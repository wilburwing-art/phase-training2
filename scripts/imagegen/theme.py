#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "numpy"]
# ///
"""Recolour generated line art to the app theme, in post.

The generator draws black lines on white with one saturated accent, because
that is what every image model keys cleanly. Theming happens here, not in the
prompt: line darkness becomes alpha, the accent fill becomes the app accent,
white becomes transparent. Deterministic and free, so a palette change is a
re-run rather than a regeneration.

    uv run scripts/imagegen/theme.py in.png out.png            # RGBA PNG
    uv run scripts/imagegen/theme.py in.png out.png --preview  # composited on surface

Tokens mirror PhaseTraining/Theme/Theme.swift. Shaded renders (the mannequin
style) do not key cleanly and are left alone by promote.py.
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

INK = (0xF5, 0xF5, 0xF0)      # Color.ink
ACCENT = (0xD4, 0xFF, 0x3D)   # Color.accent
SURFACE = (0x14, 0x16, 0x1A)  # Color.surface


# Stroke dilation in source pixels. The models draw ~3px lines at 1024px,
# which is half a point at a 48pt thumbnail; the lines had to be squinted at
# on the phone. Applied to the line alpha before downscaling.
STROKE_DILATE_PX = 9


def theme_line_art(img: Image.Image, dilate_px: int = STROKE_DILATE_PX) -> Image.Image:
    """Black-on-white line art with one saturated accent -> themed RGBA."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    # Distance from white drives line alpha; the 1.4 gain keeps anti-aliased
    # edges soft while making mid-grey strokes read as full ink.
    line_alpha = np.clip((255 - lum) / 255 * 1.4, 0, 1)
    # The models' "white" is speckled (253..255); without a floor that speckle
    # becomes a noisy alpha plane and a 400px WebP weighs 45 KB instead of 8.
    line_alpha[line_alpha < 0.08] = 0
    if dilate_px > 1:
        size = dilate_px | 1  # MaxFilter needs an odd size
        widened = Image.fromarray((line_alpha * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(size))
        line_alpha = np.asarray(widened).astype(np.float32) / 255
    sat = (a.max(axis=-1) - a.min(axis=-1)) / 255
    accent = (sat > 0.25) & (r > g) & (r > b)

    out = np.zeros(a.shape[:2] + (4,), np.float32)
    out[..., :3] = INK
    out[..., 3] = line_alpha * 255
    out[accent, :3] = ACCENT
    out[accent, 3] = np.clip(sat[accent] * 2.2, 0, 1) * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def crop_to_content(rgba: Image.Image, pad: float = 0.06) -> Image.Image:
    """Square crop around the drawn pixels. The models leave the figure in
    roughly half the frame; at 48pt that empty margin is what made the art
    small. Keeps 1:1 so scaledToFill in the thumbnail never clips a limb."""
    alpha = np.asarray(rgba.split()[-1])
    ys, xs = np.nonzero(alpha > 16)
    if len(xs) == 0:
        return rgba
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(max(x1 - x0, y1 - y0) * (1 + 2 * pad))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    w, h = rgba.size
    side = min(side, w, h)
    left = min(max(cx - side // 2, 0), w - side)
    top = min(max(cy - side // 2, 0), h - side)
    return rgba.crop((left, top, left + side, top + side))


def composite_on_surface(rgba: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", rgba.size, SURFACE + (255,))
    bg.alpha_composite(rgba)
    return bg.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--preview", action="store_true", help="flatten onto the surface colour")
    ap.add_argument("--dilate", type=int, default=STROKE_DILATE_PX, help="stroke widening in source px")
    args = ap.parse_args()
    themed = crop_to_content(theme_line_art(Image.open(args.src), dilate_px=args.dilate))
    (composite_on_surface(themed) if args.preview else themed).save(args.dst)


if __name__ == "__main__":
    main()
