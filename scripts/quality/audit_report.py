#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Write db/quality/audit_report.md summarizing Phase 3.

Reads:
  db/quality/vision_scores.jsonl       (pre-swap scores on 525 bundled webps)
  db/quality/swap_decisions.jsonl
  db/quality/swaps_applied.jsonl
  db/quality/post_swap_scores.jsonl   (re-scored auto-swapped webps)
  PhaseTraining/Resources/ExerciseImages/  (for bundle size)
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
QDIR = REPO_ROOT / "db" / "quality"
IMG_DIR = REPO_ROOT / "PhaseTraining" / "Resources" / "ExerciseImages"

VISION = QDIR / "vision_scores.jsonl"
DECISIONS = QDIR / "swap_decisions.jsonl"
APPLIED = QDIR / "swaps_applied.jsonl"
POST = QDIR / "post_swap_scores.jsonl"
OUT = QDIR / "audit_report.md"


def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open() as f:
        return [json.loads(line) for line in f if line.strip()]


def hist(scores: list[int | None]) -> dict:
    c = Counter(scores)
    return {s: c.get(s, 0) for s in [5, 4, 3, 2, 1, None]}


def fmt_hist(h: dict, total: int) -> str:
    lines = []
    for s in [5, 4, 3, 2, 1, None]:
        n = h.get(s, 0)
        bar_len = int(40 * n / max(1, total))
        label = "err" if s is None else str(s)
        lines.append(f"  {label}: {n:4d}  {'#' * bar_len}")
    return "\n".join(lines)


def main() -> int:
    vision = load_jsonl(VISION)
    decisions = load_jsonl(DECISIONS)
    applied = load_jsonl(APPLIED)
    post = load_jsonl(POST)

    auto = [d for d in decisions if d["decision"] == "auto"]
    manual = [d for d in decisions if d["decision"] == "manual"]
    skip = [d for d in decisions if d["decision"] == "skip"]

    # Before histogram on suspects only (the 318)
    suspect_ids = {d["exercise_id"] for d in decisions}
    pre_suspect = [v["score"] for v in vision if v["exercise_id"] in suspect_ids]

    # After histogram: pre scores for non-swapped suspects + post scores for swapped.
    swapped_ids = {a["exercise_id"] for a in applied}
    post_by_id = {p["exercise_id"]: p["score"] for p in post}
    after_suspect = []
    for v in vision:
        eid = v["exercise_id"]
        if eid not in suspect_ids:
            continue
        if eid in swapped_ids and eid in post_by_id:
            after_suspect.append(post_by_id[eid])
        else:
            after_suspect.append(v["score"])

    # All bundled-image histogram, before + after
    pre_all = [v["score"] for v in vision]
    after_all = []
    for v in vision:
        eid = v["exercise_id"]
        if eid in swapped_ids and eid in post_by_id:
            after_all.append(post_by_id[eid])
        else:
            after_all.append(v["score"])

    # License breakdown of NEW images (only for auto-swapped)
    license_counts: Counter = Counter()
    source_counts: Counter = Counter()
    for a in applied:
        license_counts[a.get("license") or "(none)"] += 1
        source_counts[a.get("source") or "(none)"] += 1

    # Bundle size
    files = list(IMG_DIR.glob("*.webp"))
    bundle_mb = sum(p.stat().st_size for p in files) / 1024 / 1024

    # Score delta histogram on swapped exercises
    delta_counts: Counter = Counter()
    pre_by_id = {v["exercise_id"]: v["score"] for v in vision}
    for a in applied:
        eid = a["exercise_id"]
        before = pre_by_id.get(eid)
        after = post_by_id.get(eid)
        if before is None or after is None:
            continue
        delta_counts[after - before] += 1

    lines: list[str] = []
    lines.append("# Image quality — Phase 3 audit report")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- Suspects from L1/L3 pipeline: **{len(decisions)}**")
    lines.append(f"- Auto-accepted swaps: **{len(auto)}**")
    lines.append(f"- Queued for manual review: **{len(manual)}**")
    lines.append(f"- Skipped (no usable candidate): **{len(skip)}**")
    lines.append(f"- Bundle size after rebuild: **{bundle_mb:.2f} MB** ({len(files)} webps)")
    lines.append("")

    lines.append("## Score histograms — the 318 suspects")
    lines.append("")
    lines.append("```")
    lines.append("Before (L1 scores on current images):")
    lines.append(fmt_hist(hist(pre_suspect), len(pre_suspect)))
    lines.append("")
    lines.append("After (post-swap re-score for auto-swapped, original for the rest):")
    lines.append(fmt_hist(hist(after_suspect), len(after_suspect)))
    lines.append("```")
    lines.append("")

    lines.append("## Score histograms — all bundled webps (525)")
    lines.append("")
    lines.append("```")
    lines.append("Before:")
    lines.append(fmt_hist(hist(pre_all), len(pre_all)))
    lines.append("")
    lines.append("After:")
    lines.append(fmt_hist(hist(after_all), len(after_all)))
    lines.append("```")
    lines.append("")

    if delta_counts:
        lines.append("## Per-swap score change (auto-swapped only)")
        lines.append("")
        lines.append("```")
        for delta in sorted(delta_counts, reverse=True):
            n = delta_counts[delta]
            sign = "+" if delta > 0 else ""
            lines.append(f"  {sign}{delta:+d}: {n:4d}  {'#' * (n * 2)}".replace("++", "+"))
        lines.append("```")
        lines.append("")

    if source_counts:
        lines.append("## Source breakdown — new images")
        lines.append("")
        for src, n in source_counts.most_common():
            lines.append(f"- **{src}**: {n}")
        lines.append("")

    if license_counts:
        lines.append("## License breakdown — new images")
        lines.append("")
        for lic, n in license_counts.most_common():
            lines.append(f"- **{lic}**: {n}")
        lines.append("")

    lines.append("## Files")
    lines.append("")
    lines.append("- Auto-accept audit: `db/quality/swaps_applied.jsonl`")
    lines.append("- All swap decisions: `db/quality/swap_decisions.jsonl`")
    lines.append("- Candidate scores: `db/quality/candidate_scores.jsonl`")
    lines.append("- Manual-review queue: `manual_review.md` (root)")
    lines.append("- Post-swap re-scores: `db/quality/post_swap_scores.jsonl`")
    lines.append("")

    OUT.write_text("\n".join(lines))
    print(f"Wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
