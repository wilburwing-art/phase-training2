#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Apply auto-accept swap decisions to db/source/exercises.json.

Reads:
  db/quality/swap_decisions.jsonl

Writes (in place):
  db/source/exercises.json — updates image_url, thumbnail_url,
  image_source, image_license, image_attribution for each auto-accept row.

Also:
  - Ensures every exercises row has all three new fields (image_source,
    image_license, image_attribution) — null where unknown. This guarantees
    build_db.py's `cols = list(rows[0].keys())` picks them up regardless of
    which row appears first.
  - For YouTube hqdefault image_urls left untouched (no swap), backfills the
    new attribution columns from existing source_video_attribution so the
    schema doesn't have a giant NULL column.

After this script, the caller must run:
  uv run scripts/db/build_db.py
  uv run scripts/download_exercise_images.py
"""
from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DECISIONS = REPO_ROOT / "db" / "quality" / "swap_decisions.jsonl"
EX_JSON = REPO_ROOT / "db" / "source" / "exercises.json"
APPLIED_OUT = REPO_ROOT / "db" / "quality" / "swaps_applied.jsonl"

NEW_FIELDS = ("image_source", "image_license", "image_attribution")


def load_decisions() -> dict[int, dict]:
    out: dict[int, dict] = {}
    with DECISIONS.open() as f:
        for line in f:
            row = json.loads(line)
            out[row["exercise_id"]] = row
    return out


def infer_source_from_url(url: str) -> str | None:
    if not url:
        return None
    if "free-exercise-db" in url or "yuhonas" in url:
        return "free-exercise-db"
    if "wger.de" in url:
        return "wger"
    if "wikimedia.org" in url or "wikipedia.org" in url:
        return "wikimedia"
    if "img.youtube.com" in url or "youtube.com" in url or "youtu.be" in url:
        return "youtube"
    return "other"


def main() -> int:
    decisions = load_decisions()
    autos = {eid: d for eid, d in decisions.items() if d["decision"] == "auto"}
    print(f"Auto-accept count: {len(autos)}")

    data = json.loads(EX_JSON.read_text())

    # First — make sure EVERY row carries the new fields. None where unknown.
    # And backfill existing license/attribution context from source_video_attribution
    # when an image_url is present.
    for row in data:
        for k in NEW_FIELDS:
            row.setdefault(k, None)
        if row.get("image_url") and row.get("image_source") is None:
            row["image_source"] = infer_source_from_url(row["image_url"])
            # Backfill license + attribution from source_video_attribution where we can.
            sva = row.get("source_video_attribution") or ""
            if "Unlicense" in sva or "free-exercise-db" in sva:
                row["image_license"] = row["image_license"] or "Unlicense"
                row["image_attribution"] = row["image_attribution"] or sva or "yuhonas/free-exercise-db"
            elif "YouTube" in sva:
                row["image_license"] = row["image_license"] or "YouTube ToS"
                row["image_attribution"] = row["image_attribution"] or sva

    # Now apply auto-accepts.
    by_id = {r["id"]: r for r in data}
    applied: list[dict] = []
    now = datetime.now(UTC).isoformat(timespec="seconds")

    for eid, dec in autos.items():
        cand = dec["chosen_candidate"]
        row = by_id.get(eid)
        if row is None:
            print(f"  WARNING: ex {eid} not in exercises.json, skip")
            continue

        new_image_url = cand["image_url"]  # canonical full-size
        new_thumb_url = cand.get("thumb_url") or cand["image_url"]
        applied.append(
            {
                "exercise_id": eid,
                "name": row["name"],
                "before_image_url": row.get("image_url"),
                "before_source_video_attribution": row.get("source_video_attribution"),
                "after_image_url": new_image_url,
                "after_thumbnail_url": new_thumb_url,
                "source": cand["source"],
                "license": cand["license"],
                "attribution": cand["attribution"],
                "candidate_score": dec["candidate_score"],
                "current_score": dec["current_score"],
                "applied_at": now,
            }
        )
        row["image_url"] = new_image_url
        row["thumbnail_url"] = new_thumb_url
        row["image_source"] = cand["source"]
        row["image_license"] = cand["license"]
        row["image_attribution"] = cand["attribution"]
        row["updated_at"] = now

    # Write back with stable formatting.
    EX_JSON.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")

    APPLIED_OUT.parent.mkdir(parents=True, exist_ok=True)
    with APPLIED_OUT.open("w") as f:
        for a in applied:
            f.write(json.dumps(a, ensure_ascii=False) + "\n")

    print(f"Applied {len(applied)} auto-accept swaps to {EX_JSON.name}")
    print(f"Per-swap audit: {APPLIED_OUT}")

    # Sanity: count rows that now carry image_source.
    with_src = sum(1 for r in data if r.get("image_source"))
    print(f"Rows with image_source set: {with_src} / {len(data)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
