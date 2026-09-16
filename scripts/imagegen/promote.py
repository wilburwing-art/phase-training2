#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "numpy", "scipy"]
# ///
"""Promote generated frames from a run directory into the app bundle.

Per catalogue exercise, four files under PhaseTraining/Resources/ExerciseImages:

    <id>.webp           line art start, themed, RGBA   (thumbnail, frame 1)
    <id>_end.webp       line art end,   themed, RGBA   (thumbnail, frame 2)
    <id>_hero.webp      mannequin start, as rendered   (detail page, left)
    <id>_hero_end.webp  mannequin end,   as rendered   (detail page, right)

Line art goes through theme.py; the mannequin is a shaded render and ships as
generated. Also marks the row `image_source: generated` in
db/source/exercises.json and clears the network image URLs, then the caller
rebuilds coach.db:

    uv run scripts/imagegen/promote.py --run scripts/imagegen/out/run_2 \\
        --provider or-openai --only pallof-press,bulgarian-split-squat
    uv run scripts/db/build_db.py

Bake-off ids differ from catalogue slugs; map them with
`--alias barbell-romanian-deadlift=romanian-deadlift`. `--scores scores.json`
(the contact sheet export) promotes only pairs scored "pass" in BOTH styles.
Nothing is deleted: a slug not promoted keeps whatever it had.

Theme change (palette, stroke weight): re-theme every promoted exercise's
line art from its source frames without touching heroes or exercises.json:

    uv run scripts/imagegen/promote.py --refresh-line-art \
        --runs run_4,run_3,run_2,manual --alias barbell-romanian-deadlift=romanian-deadlift

`--runs` is a search order, first hit wins; an exercise generated in two
runs must be listed so the run that was actually promoted comes first
(goblet-squat: run_4, not manual, checked against the bundle 2026-09-15).
"""

import argparse
import io
import json
import sys
from pathlib import Path

from PIL import Image

from theme import LINE_ART_DIM, STROKE_PT_AT_THUMB, theme_line_art

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
IMAGES = REPO / "PhaseTraining" / "Resources" / "ExerciseImages"
EXERCISES_JSON = REPO / "db" / "source" / "exercises.json"

# Line art is thumbnail-only now (84pt at 3x = 252px), the mannequin is the
# hero at half width (190pt at 3x = 570px). Sized to fit 575 x 4 files in a
# ~30 MB bundle: measured 15 KB per themed line-art frame at 480px with lossy
# alpha, 10 KB per mannequin frame at 640px. The line-art edge lives in
# theme.py, which sizes the stroke against it.
LINE_ART_QUALITY, LINE_ART_ALPHA_QUALITY = 85, 50
HERO_DIM, HERO_QUALITY = 640, 80
MODEL_LABEL = "generated: openai/gpt-5.4-image-2 via OpenRouter"


def to_webp(img: Image.Image, keep_alpha: bool) -> bytes:
    dim = LINE_ART_DIM if keep_alpha else HERO_DIM
    w, h = img.size
    scale = min(1.0, dim / max(w, h))
    if scale < 1.0:
        img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
    out = io.BytesIO()
    if keep_alpha:
        img.convert("RGBA").save(out, format="WEBP", quality=LINE_ART_QUALITY,
                                 alpha_quality=LINE_ART_ALPHA_QUALITY, method=6)
    else:
        img.convert("RGB").save(out, format="WEBP", quality=HERO_QUALITY, method=6)
    return out.getvalue()


def frame_path(run: Path, provider: str, style: str, run_id: str, frame: str) -> Path:
    return run / f"{provider}__{style}__{run_id}__{frame}.png"


def passing_ids(scores_path: Path, provider: str) -> set[str]:
    scores = json.loads(scores_path.read_text())
    ok: dict[str, set[str]] = {}
    for key, verdict in scores.items():
        prov, style, run_id = key.split("__", 2)
        if prov == provider and verdict == "pass":
            ok.setdefault(run_id, set()).add(style)
    return {rid for rid, styles in ok.items() if {"line_art", "mannequin"} <= styles}


def refresh_line_art(runs: list[Path], alias: dict[str, str], stroke_pt: float, dry_run: bool) -> None:
    """Re-theme <id>.webp and <id>_end.webp for every `generated` row from
    the first run in `runs` that holds its line-art start frame."""
    rows = json.loads(EXERCISES_JSON.read_text())
    run_id_for = {v: k for k, v in alias.items()}  # slug -> bake-off id
    done, missing = 0, []
    for row in rows:
        if row.get("image_source") != "generated":
            continue
        slug = row["slug"]
        hit = None
        for run in runs:
            for rid in (slug, run_id_for.get(slug)):
                if rid is None:
                    continue
                starts = sorted(run.glob(f"*__line_art__{rid}__start.png"))
                if starts:
                    hit = (run, starts[0])
                    break
            if hit:
                break
        if hit is None:
            missing.append(slug)
            continue
        run, start = hit
        end = start.with_name(start.name.replace("__start.png", "__end.png"))
        ex_id = row["id"]
        outputs = {IMAGES / f"{ex_id}.webp": to_webp(theme_line_art(Image.open(start), stroke_pt=stroke_pt), True)}
        if end.exists():
            outputs[IMAGES / f"{ex_id}_end.webp"] = to_webp(theme_line_art(Image.open(end), stroke_pt=stroke_pt), True)
        total = sum(len(b) for b in outputs.values())
        print(f"{slug} (id {ex_id}) <- {run.name}: {len(outputs)} files, {total/1024:.0f} KB")
        if not dry_run:
            for path, data in outputs.items():
                path.write_bytes(data)
        done += 1
    print(f"\nre-themed {done}" + (f"; NO SOURCE FRAME for {missing}" if missing else ""))
    if missing:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, help="run directory to promote from")
    ap.add_argument("--refresh-line-art", action="store_true",
                    help="re-theme every promoted exercise's line art from --runs; heroes untouched")
    ap.add_argument("--runs", help="comma list of run dirs (under out/ or paths), searched in order")
    ap.add_argument("--stroke-pt", type=float, default=STROKE_PT_AT_THUMB,
                    help="line-art stroke weight in points at the 84pt thumbnail")
    ap.add_argument("--provider", default="or-openai")
    ap.add_argument("--only", help="comma list of run ids (bake-off ids or slugs)")
    ap.add_argument("--scores", type=Path, help="contact sheet scores.json; promote pass/pass only")
    ap.add_argument("--alias", action="append", default=[],
                    help="run-id=catalogue-slug, repeatable")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    alias = dict(a.split("=", 1) for a in args.alias)
    if args.refresh_line_art:
        if not args.runs:
            sys.exit("--refresh-line-art needs --runs")
        runs = [(p if p.is_dir() else HERE / "out" / p) for p in (Path(r.strip()) for r in args.runs.split(","))]
        for r in runs:
            if not r.is_dir():
                sys.exit(f"no such run dir: {r}")
        refresh_line_art(runs, alias, args.stroke_pt, args.dry_run)
        return
    if args.run is None:
        sys.exit("--run is required (or --refresh-line-art)")
    rows = json.loads(EXERCISES_JSON.read_text())
    by_slug = {r["slug"]: r for r in rows}

    run_ids = sorted({p.name.split("__")[2] for p in args.run.glob(f"{args.provider}__*__start.png")})
    if args.only:
        wanted = {s.strip() for s in args.only.split(",")}
        run_ids = [r for r in run_ids if r in wanted]
    if args.scores:
        ok = passing_ids(args.scores, args.provider)
        run_ids = [r for r in run_ids if r in ok]
    if not run_ids:
        sys.exit("nothing to promote")

    promoted = []
    for run_id in run_ids:
        slug = alias.get(run_id, run_id)
        row = by_slug.get(slug)
        if row is None:
            print(f"skip {run_id}: no catalogue slug {slug!r} (use --alias)")
            continue
        frames = {
            (style, frame): frame_path(args.run, args.provider, style, run_id, frame)
            for style in ("line_art", "mannequin") for frame in ("start", "end")
        }
        # A hold (isometric) run has start frames only; a pair has both.
        # Each style is promoted on its own when its frames are complete, so
        # a hand-generated batch with only the mannequin pair still lands
        # (the hero uses it; the thumbnail keeps whatever image it had).
        hold = not frames[("line_art", "end")].exists() and not frames[("mannequin", "end")].exists()
        wanted = ["start"] if hold else ["start", "end"]
        complete = {style for style in ("line_art", "mannequin")
                    if all(frames[(style, fr)].exists() for fr in wanted)}
        if not complete:
            missing = [f"{st}/{fr}" for st in ("line_art", "mannequin") for fr in wanted if not frames[(st, fr)].exists()]
            print(f"skip {run_id}: missing {', '.join(missing)}")
            continue

        ex_id = row["id"]
        outputs = {}
        stale = []
        if "line_art" in complete:
            outputs[IMAGES / f"{ex_id}.webp"] = to_webp(theme_line_art(Image.open(frames[("line_art", "start")]), stroke_pt=args.stroke_pt), True)
            if hold:
                stale.append(IMAGES / f"{ex_id}_end.webp")
            else:
                outputs[IMAGES / f"{ex_id}_end.webp"] = to_webp(theme_line_art(Image.open(frames[("line_art", "end")]), stroke_pt=args.stroke_pt), True)
        if "mannequin" in complete:
            outputs[IMAGES / f"{ex_id}_hero.webp"] = to_webp(Image.open(frames[("mannequin", "start")]), False)
            if hold:
                stale.append(IMAGES / f"{ex_id}_hero_end.webp")
            else:
                outputs[IMAGES / f"{ex_id}_hero_end.webp"] = to_webp(Image.open(frames[("mannequin", "end")]), False)
        total = sum(len(b) for b in outputs.values())
        print(f"{run_id} -> {slug} (id {ex_id}): {'hold, ' if hold else ''}{'+'.join(sorted(complete))}, {len(outputs)} files, {total/1024:.0f} KB")
        if args.dry_run:
            continue
        for path, data in outputs.items():
            path.write_bytes(data)
        for path in stale:
            path.unlink(missing_ok=True)
        if "line_art" in complete:
            # The row's image_* fields describe <id>.webp, the thumbnail.
            # A mannequin-only promote leaves that file and its source alone.
            row["image_url"] = None
            row["thumbnail_url"] = None
            row["image_source"] = "generated"
            row["image_license"] = None
            row["image_attribution"] = MODEL_LABEL
        promoted.append(slug)

    if promoted and not args.dry_run:
        EXERCISES_JSON.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
        print(f"\npromoted {len(promoted)}; now run: uv run scripts/db/build_db.py")


if __name__ == "__main__":
    main()
