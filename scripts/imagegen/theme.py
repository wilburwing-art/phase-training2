#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "numpy", "scipy"]
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
from scipy import ndimage

INK = (0xF5, 0xF5, 0xF0)      # Color.ink
ACCENT = (0xD4, 0xFF, 0x3D)   # Color.accent
SURFACE = (0x14, 0x16, 0x1A)  # Color.surface

# The line-art asset edge. The thumbnail is 84pt at 3x = 252px, so 480 leaves
# headroom to a 160pt slot before anything upsamples.
LINE_ART_DIM = 480

# Stroke weight as the thumbnail shows it: points at the 84pt slot. This is
# the one knob. The first pass dilated by a fixed 9px at the 1024px source
# and then cropped each figure to its own square, so the resize factor, and
# with it the shipped stroke, varied per figure. Now the stroke is measured
# on the output-sized asset and grown until it reaches this value, so the
# crop no longer decides the weight. The measure moves in 2px steps at 480
# (0.35pt at the slot), so a target between steps lands on the step above:
# 1.5 ships as 1.75pt measured, 36 of 47 assets on that exact value and the
# rest within one step. Owner picked this from a 1.5 / 2.0 / 2.5 sheet
# rendered at the real slot size, 2026-09-15.
STROKE_PT_AT_THUMB = 1.5
THUMB_PT = 84


# The detail-page hero: one figure, animated, at ~240pt. 720px is 1:1 at 3x
# for that slot and keeps a lossy-alpha WebP near 30 KB.
HERO_DIM, HERO_SLOT_PT = 720, 240


def stroke_target_px(stroke_pt: float, out_dim: int = LINE_ART_DIM, slot_pt: float = THUMB_PT) -> float:
    """Points on screen in a slot_pt slot -> pixels in an out_dim asset."""
    return stroke_pt * out_dim / slot_pt


def measure_stroke_px(mask: np.ndarray) -> float:
    """Typical stroke width of a line mask, in pixels: the median of twice the
    distance-to-edge over RIDGE pixels (local maxima of the distance
    transform, the stroke's centre line). Ridge pixels weight by stroke
    length, so the outline that the eye reads as the line weight decides
    the number. An area-weighted mean does not: a filled plate or two
    outlines merged by dilation contribute far more pixels than their length
    and read as 2x the visible weight."""
    if not mask.any():
        return 0.0
    dt = ndimage.distance_transform_edt(mask)
    ridge = mask & (dt >= ndimage.maximum_filter(dt, size=3)) & (dt > 0.5)
    return float(2 * np.median(dt[ridge])) if ridge.any() else 0.0


def content_box(alpha: np.ndarray, pad: float = 0.06) -> tuple[int, int, int, int]:
    """Square crop around the drawn pixels. The models leave the figure in
    roughly half the frame; at 48pt that empty margin is what made the art
    small. Keeps 1:1 so scaledToFill in the thumbnail never clips a limb."""
    h, w = alpha.shape
    ys, xs = np.nonzero(alpha > 16)
    if len(xs) == 0:
        return 0, 0, w, h
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(max(x1 - x0, y1 - y0) * (1 + 2 * pad))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    side = min(side, w, h)
    left = min(max(cx - side // 2, 0), w - side)
    top = min(max(cy - side // 2, 0), h - side)
    return left, top, left + side, top + side


def _ink(img: Image.Image) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Line alpha, accent mask and saturation for a black-on-white frame."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    # Distance from white drives line alpha; the 1.4 gain keeps anti-aliased
    # edges soft while making mid-grey strokes read as full ink.
    line_alpha = np.clip((255 - lum) / 255 * 1.4, 0, 1)
    # The models' "white" is speckled (253..255); without a floor that speckle
    # becomes a noisy alpha plane and a 400px WebP weighs 45 KB instead of 8.
    line_alpha[line_alpha < 0.08] = 0
    sat = (a.max(axis=-1) - a.min(axis=-1)) / 255
    accent = (sat > 0.25) & (r > g) & (r > b)
    return line_alpha, accent, sat


def pair_box(frames: list[Image.Image]) -> tuple[int, int, int, int]:
    """One crop box for a start/end pair: the union of both frames' ink.
    Cropping each frame to its own content rescales the figure between the
    two (a rollout's extended frame is wider, so its figure came out
    smaller), and the flip read as a zoom. Both frames are generated at
    one camera, so a shared box keeps the figure the same size and the
    movement is the only thing that changes."""
    union = np.zeros(np.asarray(frames[0].convert("L")).shape, np.float32)
    for f in frames:
        la, _, _ = _ink(f)
        if la.shape == union.shape:
            union = np.maximum(union, la)
    return content_box(union * 255)


def theme_line_art(img: Image.Image, stroke_pt: float = STROKE_PT_AT_THUMB,
                   out_dim: int = LINE_ART_DIM, slot_pt: float = THUMB_PT,
                   box: tuple[int, int, int, int] | None = None) -> Image.Image:
    """Black-on-white line art with one saturated accent -> themed RGBA,
    cropped to content (or to `box`, see pair_box), strokes widened so they
    measure `stroke_pt` on screen in a `slot_pt` slot once the caller
    resizes to `out_dim`. Returned at source resolution: dilating before
    the downscale keeps the edges soft."""
    line_alpha, accent, sat = _ink(img)

    # Crop on the undilated ink, then size the dilation to the crop: the
    # resize factor is what varied per figure, so the target is expressed in
    # output pixels and divided back into source pixels here.
    x0, y0, x1, y1 = box or content_box(line_alpha * 255)
    line_alpha = line_alpha[y0:y1, x0:x1]
    accent = accent[y0:y1, x0:x1]
    resize = out_dim / (x1 - x0)
    target = stroke_target_px(stroke_pt, out_dim, slot_pt)
    # Grow at source, measure on the OUTPUT-sized alpha, grow again. The
    # number the knob names is the stroke in the shipped asset, and the
    # downscale plus the alpha threshold shifts it by a pixel or two from
    # what the source measures, so the loop closes on the resized copy.
    accent_out = np.asarray(Image.fromarray((accent * 255).astype(np.uint8), "L")
                            .resize((out_dim, out_dim), Image.LANCZOS)) > 128
    for _ in range(4):
        out_alpha = np.asarray(Image.fromarray((line_alpha * 255).astype(np.uint8), "L")
                               .resize((out_dim, out_dim), Image.LANCZOS)).astype(np.float32) / 255
        short = target - measure_stroke_px((out_alpha > 0.5) & ~accent_out)
        if short < 1:  # within one output pixel: the measure moves in 2px steps
            break
        widen = short / resize
        size = 2 * max(1, round(widen / 2)) + 1  # MaxFilter grows a stroke by size - 1
        widened = Image.fromarray((line_alpha * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(size))
        line_alpha = np.asarray(widened).astype(np.float32) / 255

    out = np.zeros(line_alpha.shape + (4,), np.float32)
    out[..., :3] = INK
    out[..., 3] = line_alpha * 255
    out[accent, :3] = ACCENT
    out[accent, 3] = np.clip(sat[y0:y1, x0:x1][accent] * 2.2, 0, 1) * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def composite_on_surface(rgba: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", rgba.size, SURFACE + (255,))
    bg.alpha_composite(rgba)
    return bg.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--preview", action="store_true", help="flatten onto the surface colour")
    ap.add_argument("--stroke-pt", type=float, default=STROKE_PT_AT_THUMB,
                    help="stroke weight in points at the 84pt thumbnail")
    args = ap.parse_args()
    themed = theme_line_art(Image.open(args.src), stroke_pt=args.stroke_pt)
    (composite_on_surface(themed) if args.preview else themed).save(args.dst)


if __name__ == "__main__":
    main()
