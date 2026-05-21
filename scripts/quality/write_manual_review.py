#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Write manual_review.md — a markdown queue of borderline swaps for human Y/N.

Reads:
  db/quality/swap_decisions.jsonl
  db/quality/vision_scores.jsonl   (for the current-image reason)
  db/quality/all_candidates.jsonl  (for the candidate's match metadata)

Output:
  manual_review.md
"""
from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
QDIR = REPO_ROOT / "db" / "quality"
DECISIONS = QDIR / "swap_decisions.jsonl"
VISION = QDIR / "vision_scores.jsonl"
OUT = REPO_ROOT / "manual_review.md"


def load_jsonl(path: Path) -> list[dict]:
    out = []
    with path.open() as f:
        for line in f:
            out.append(json.loads(line))
    return out


def main() -> int:
    decisions = load_jsonl(DECISIONS)
    vis = {r["exercise_id"]: r for r in load_jsonl(VISION)}

    manual = [d for d in decisions if d["decision"] == "manual"]
    print(f"Manual-review queue size: {len(manual)}")

    # Order by: largest improvement first (so the most-impactful Y/Ns are at top).
    manual.sort(key=lambda d: -(((d.get("candidate_score") or 0) - (d.get("current_score") or 0))))

    lines: list[str] = []
    lines.append("# Manual swap review queue")
    lines.append("")
    lines.append(
        f"Generated from `db/quality/swap_decisions.jsonl`. {len(manual)} borderline "
        "swap candidates that the auto-accept rules wouldn't touch. For each one:"
    )
    lines.append("")
    lines.append("- Look at the current image vs the candidate image.")
    lines.append("- Edit `YES` or `NO` after `Replace with this candidate?`.")
    lines.append("- After editing, run `scripts/quality/apply_manual_swaps.py` to land approved swaps.")
    lines.append("")

    for d in manual:
        eid = d["exercise_id"]
        cand = d["chosen_candidate"]
        cur = vis.get(eid, {})
        cur_score = d.get("current_score")
        cs = d.get("candidate_score")
        conf = d.get("candidate_confidence")
        sha = cand["url_sha1"]

        lines.append(f"## ex {eid}")
        lines.append("")
        lines.append(
            f"Current (score {cur_score}): _{cur.get('reason', '(no reason)')}_  "
            f"![current](PhaseTraining/Resources/ExerciseImages/{eid}.webp)"
        )
        lines.append("")
        lines.append(
            f"Candidate ({cand['source']}, license={cand['license']}, score={cs}/{conf}): "
            f"_{cand.get('reason', '')}_  "
            f"![candidate](db/quality/candidate_thumbs/{sha}.webp)"
        )
        lines.append("")
        lines.append(f"- URL: `{cand['url']}`")
        lines.append(f"- Attribution: {cand['attribution']}")
        lines.append("")
        lines.append("- Replace with this candidate? **NO**")
        lines.append("")
        lines.append("---")
        lines.append("")

    OUT.write_text("\n".join(lines))
    print(f"Wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
