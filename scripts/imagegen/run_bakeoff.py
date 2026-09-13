#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///
"""Run the exercise image bake-off.

    export OPENROUTER_API_KEY=...
    uv run scripts/imagegen/run_bakeoff.py

Generates, for every exercise x style x provider, a start frame and then an end
frame conditioned on that start frame. Writes PNGs plus contact_sheet.html to
scripts/imagegen/out/<run>/ (gitignored).

Default set is the 10 hard cases in prompts.py. To run against the catalogue
instead:

    uv run scripts/imagegen/run_bakeoff.py --db db/coach.db --limit 10

The catalogue has no start/end position text yet. --db reads it from
db/source/exercise_positions.json, keyed by exercise slug, and only exercises
present in that file are eligible. Without position text the model invents
joint angles, so the loader refuses rather than falling back to instructions.
"""

import argparse
import concurrent.futures as futures
import html
import json
import os
import sqlite3
import sys
import traceback
from pathlib import Path

from prompts import BAKEOFF_EXERCISES, build_end_prompt, build_hold_prompt, build_start_prompt
from providers import PROVIDERS

STYLES = ["line_art", "mannequin"]
HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
POSITIONS = REPO / "db" / "source" / "exercise_positions.json"

# coach.db keeps pattern, equipment and muscles in join tables. An exercise
# with several patterns takes the lowest pattern id; "None (Bodyweight)" is
# the catalogue's spelling for no equipment.
# Equipment rows the body never touches during the movement. Listing them
# draws them: "Squat Rack" put a rack in all four back-squat frames (run 3),
# which is scenery in a thumbnail. Benches, bars and machines stay because
# the figure is on or holding them.
SCENERY = {"Squat Rack", "Wall", "Yoga Mat", "Cones", "None (Bodyweight)"}

SELECT = """
SELECT e.slug AS id, e.name, e.contraction_type,
  (SELECT mp.slug FROM exercise_movement_patterns emp
     JOIN movement_patterns mp ON mp.id = emp.movement_pattern_id
    WHERE emp.exercise_id = e.id ORDER BY mp.id LIMIT 1)          AS movement_pattern,
  COALESCE((SELECT group_concat(q.name, ', ') FROM exercise_equipment ee
     JOIN equipment q ON q.id = ee.equipment_id
    WHERE ee.exercise_id = e.id AND ee.is_required = 1), 'bodyweight only') AS equipment,
  COALESCE((SELECT group_concat(m.name, ', ') FROM exercise_muscles em
     JOIN muscle_groups m ON m.id = em.muscle_group_id
    WHERE em.exercise_id = e.id AND em.role = 'primary'), '')      AS primary_muscles
FROM exercises e
ORDER BY e.slug
"""


def load_from_db(db_path, limit):
    if not POSITIONS.exists():
        sys.exit(f"{POSITIONS} does not exist. --db needs start/end position "
                 "text per exercise slug; write that file first (see README).")
    positions = json.loads(POSITIONS.read_text())
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    try:
        rows = [dict(r) for r in con.execute(SELECT)]
    finally:
        con.close()
    out = []
    for r in rows:
        pos = positions.get(r["id"])
        if not pos or not pos.get("start_position") or not pos.get("end_position"):
            continue
        kept = [q.strip() for q in r["equipment"].split(",") if q.strip() not in SCENERY]
        r["equipment"] = ", ".join(kept) or "bodyweight only"
        r["isometric"] = r.pop("contraction_type") == "isometric"
        r["start_position"] = pos["start_position"]
        r["end_position"] = pos["end_position"]
        out.append(r)
    if not out:
        sys.exit(f"No exercise in {db_path} has both positions in {POSITIONS.name}.")
    unknown = sorted(set(positions) - {r["id"] for r in rows})
    if unknown:
        print(f"warning: {len(unknown)} slugs in {POSITIONS.name} are not in the "
              f"catalogue: {', '.join(unknown[:5])}{'...' if len(unknown) > 5 else ''}")
    return out[:limit]


def run_one(provider, style, exercise, outdir, size):
    slug = exercise["id"]
    stem = outdir / f"{provider.name}__{style}__{slug}"
    start_path = stem.with_name(stem.name + "__start.png")
    end_path = stem.with_name(stem.name + "__end.png")

    transparent = provider.native_transparency
    if exercise.get("isometric"):
        # A hold has one frame, the hold itself. Asked for a "before the
        # hold" start, every model drew the hold anyway (side plank, run 3),
        # so the second call bought an identical image.
        if start_path.exists():
            return slug, provider.name, style, None
        start_path.write_bytes(provider.generate(
            build_hold_prompt(exercise, style, transparent), size))
        return slug, provider.name, style, None

    if start_path.exists() and end_path.exists():
        return slug, provider.name, style, None

    start_png = provider.generate(
        build_start_prompt(exercise, style, transparent), size)
    start_path.write_bytes(start_png)

    end_png = provider.generate_with_ref(
        build_end_prompt(exercise, style, transparent), start_png, size
    )
    end_path.write_bytes(end_png)
    return slug, provider.name, style, None


def export_prompts(exercises, styles, outdir):
    """One .txt per prompt under <dir>/<slug>/<style>/, for pasting into a
    web UI (gemini.com, chatgpt.com) that generates for free. Files that
    come back are named for `promote.py --provider manual`."""
    outdir.mkdir(parents=True, exist_ok=True)
    n = 0
    for ex in exercises:
        for style in styles:
            d = outdir / ex["id"] / style
            d.mkdir(parents=True, exist_ok=True)
            if ex.get("isometric"):
                (d / "hold.txt").write_text(build_hold_prompt(ex, style))
                n += 1
            else:
                (d / "1-start.txt").write_text(build_start_prompt(ex, style))
                (d / "2-end.txt").write_text(build_end_prompt(ex, style))
                n += 2
    (outdir / "README.md").write_text(MANUAL_README)
    print(f"{n} prompts for {len(exercises)} exercises under {outdir}")


MANUAL_README = """# Hand-generated frames

Each exercise folder holds one prompt per frame per style. In the web UI:

1. Paste `1-start.txt` as the whole message. Save the PNG.
2. In the SAME chat, attach that PNG and paste `2-end.txt`. The prompt calls
   it "the attached reference image". If the reply is the start pose again,
   say "the joints must move; draw the end position" and retry once or twice.
3. A `hold.txt` exercise gets one image, no second step.

Save files next to this README, named exactly:

    manual__<style>__<slug>__start.png
    manual__<style>__<slug>__end.png      (pairs only)

e.g. `manual__line_art__goblet-squat__start.png`. Then:

    uv run scripts/imagegen/promote.py --run <this dir> --provider manual --only goblet-squat
    uv run scripts/db/build_db.py

The line art must be black on white with the orange accent as prompted;
that is the generator's job. Matching the app (ink lines, lime accent,
transparent ground) happens in post, in promote.py via theme.py. To see how
a file will look in the app before promoting it:

    uv run scripts/imagegen/theme.py manual__line_art__goblet-squat__start.png preview.png --preview
"""


def build_contact_sheet(exercises, outdir, combos):
    cells = []
    for ex in exercises:
        row = {"id": ex["id"], "name": ex["name"], "cells": []}
        for prov, style in combos:
            stem = f"{prov}__{style}__{ex['id']}"
            row["cells"].append({
                "key": stem,
                "label": f"{prov} / {style.replace('_', ' ')}",
                "start": f"{stem}__start.png",
                "end": f"{stem}__end.png",
                "hold": bool(ex.get("isometric")),
            })
        cells.append(row)

    body = []
    for row in cells:
        body.append(f'<h2>{html.escape(row["name"])}</h2><div class="grid">')
        for c in row["cells"]:
            body.append(
                f'<div class="cell"><div class="lbl">{html.escape(c["label"])}</div>'
                f'<div class="pair"><img src="{c["start"]}" alt="start" loading="lazy">'
                + ("" if c["hold"] else f'<img src="{c["end"]}" alt="end" loading="lazy">') + '</div>'
                f'<div class="score" data-key="{c["key"]}">'
                f'<button data-v="pass">form ok</button>'
                f'<button data-v="style">style drift</button>'
                f'<button data-v="fail">form wrong</button>'
                f'</div></div>'
            )
        body.append("</div>")

    doc = CONTACT_SHEET_TEMPLATE.replace("__BODY__", "\n".join(body))
    (outdir / "contact_sheet.html").write_text(doc, encoding="utf-8")


CONTACT_SHEET_TEMPLATE = """<!doctype html>
<meta charset="utf-8"><title>Exercise image bake-off</title>
<style>
 body{font:15px/1.5 system-ui,sans-serif;margin:24px;background:#faf9f7;color:#1c1c1a}
 h1{font-size:20px;font-weight:500}
 h2{font-size:16px;font-weight:500;margin:32px 0 8px;border-bottom:1px solid #ddd;padding-bottom:6px}
 .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px}
 .cell{border:1px solid #e2e0da;border-radius:8px;padding:10px;background:#fff}
 .lbl{font-size:12px;color:#6a685f;margin-bottom:6px}
 .pair{display:flex;gap:6px}
 .pair img{width:50%;background:#f1efe8;border-radius:4px;aspect-ratio:1}
 .score{display:flex;gap:6px;margin-top:8px}
 .score button{flex:1;font:12px system-ui;padding:5px 0;border:1px solid #d3d1c7;
   border-radius:5px;background:#fff;cursor:pointer}
 .score button.on[data-v=pass]{background:#c0dd97;border-color:#639922}
 .score button.on[data-v=style]{background:#fac775;border-color:#ba7517}
 .score button.on[data-v=fail]{background:#f7c1c1;border-color:#a32d2d}
 #bar{position:sticky;top:0;background:#faf9f7;padding:10px 0;z-index:5;
   border-bottom:1px solid #ddd;display:flex;gap:12px;align-items:center}
 #bar button{font:13px system-ui;padding:6px 12px;border:1px solid #d3d1c7;
   border-radius:6px;background:#fff;cursor:pointer}
</style>
<div id="bar"><h1 style="margin:0;flex:1">Exercise image bake-off</h1>
<span id="count"></span><button id="export">export scores.json</button></div>
__BODY__
<script>
const KEY='phasetraining-bakeoff-scores';
const scores=JSON.parse(localStorage.getItem(KEY)||'{}');
function paint(){
  document.querySelectorAll('.score').forEach(s=>{
    const v=scores[s.dataset.key];
    s.querySelectorAll('button').forEach(b=>b.classList.toggle('on',b.dataset.v===v));
  });
  const total=document.querySelectorAll('.score').length;
  document.getElementById('count').textContent=Object.keys(scores).length+' / '+total+' scored';
}
document.querySelectorAll('.score button').forEach(b=>{
  b.onclick=()=>{
    const k=b.parentElement.dataset.key;
    scores[k]=scores[k]===b.dataset.v?undefined:b.dataset.v;
    if(!scores[k])delete scores[k];
    localStorage.setItem(KEY,JSON.stringify(scores));paint();
  };
});
document.getElementById('export').onclick=()=>{
  const blob=new Blob([JSON.stringify(scores,null,2)],{type:'application/json'});
  const a=document.createElement('a');
  a.href=URL.createObjectURL(blob);a.download='scores.json';a.click();
};
paint();
</script>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(HERE / "out" / "run_1"))
    ap.add_argument("--db", help="path to the SQLite catalogue")
    ap.add_argument("--limit", type=int, default=10)
    ap.add_argument("--only", help="comma list of exercise ids/slugs to run (re-rolls)")
    ap.add_argument("--size", default="1024x1024")
    ap.add_argument("--providers", default="or-google,or-openai",
                    help=f"comma list from {', '.join(PROVIDERS)}")
    ap.add_argument("--styles", default=",".join(STYLES))
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--dry-run", action="store_true",
                    help="list the jobs and print the first start prompt, call nothing")
    ap.add_argument("--export-prompts", type=Path, metavar="DIR",
                    help="write every prompt as a text file for hand-feeding a web UI, call nothing")
    args = ap.parse_args()

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    exercises = (load_from_db(args.db, args.limit) if args.db
                 else BAKEOFF_EXERCISES[:args.limit])
    if args.only:
        wanted = {w.strip() for w in args.only.split(",")}
        exercises = [ex for ex in exercises if ex["id"] in wanted]
        if not exercises:
            sys.exit(f"--only matched nothing in the loaded set: {sorted(wanted)}")
    prov_names = [p.strip() for p in args.providers.split(",") if p.strip()]
    styles = [s.strip() for s in args.styles.split(",") if s.strip()]
    if args.export_prompts:
        export_prompts(exercises, styles, args.export_prompts)
        return
    if args.dry_run:
        n = len(prov_names) * len(styles) * len(exercises)
        per = len(prov_names) * len(styles)
        n_images = sum(per * (1 if ex.get("isometric") else 2) for ex in exercises)
        print(f"{n} pairs, {n_images} images total")
        for ex in exercises:
            kind = "hold " if ex.get("isometric") else "pair "
            print(f"  {kind}{ex['id']:40s} {ex.get('movement_pattern') or '-':24s} {ex['equipment']}")
        print("\n--- first start prompt (white background variant) ---")
        print(build_start_prompt(exercises[0], styles[0]))
        return
    providers = {n: PROVIDERS[n]() for n in prov_names}

    jobs = [(providers[p], s, ex)
            for p in prov_names for s in styles for ex in exercises]
    n_images = sum(1 if ex.get("isometric") else 2 for _, _, ex in jobs)
    print(f"{len(jobs)} pairs, {n_images} images total")

    failures = []
    with futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        fut = {pool.submit(run_one, p, s, ex, outdir, args.size): (p.name, s, ex["id"])
               for p, s, ex in jobs}
        for i, f in enumerate(futures.as_completed(fut), 1):
            tag = fut[f]
            try:
                f.result()
                print(f"[{i}/{len(jobs)}] ok   {tag[0]} {tag[1]} {tag[2]}")
            except Exception as exc:
                failures.append((tag, str(exc)))
                print(f"[{i}/{len(jobs)}] FAIL {tag[0]} {tag[1]} {tag[2]}: {exc}")

    combos = [(p, s) for p in prov_names for s in styles]
    build_contact_sheet(exercises, outdir, combos)
    (outdir / "manifest.json").write_text(json.dumps(
        {"exercises": [e["id"] for e in exercises], "combos": combos,
         "failures": [{"job": list(t), "error": e} for t, e in failures]},
        indent=2))

    print(f"\ndone. {len(failures)} failures.")
    print(f"open {outdir / 'contact_sheet.html'}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception:
        traceback.print_exc()
        sys.exit(1)
