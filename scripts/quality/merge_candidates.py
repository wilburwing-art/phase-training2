#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Merge per-source candidate JSONLs into one (suspect, candidate) tuple stream.

Inputs (one row per suspect; same exercise_id appears in all three):
  db/quality/candidates_fedb.jsonl
  db/quality/candidates_wger.jsonl
  db/quality/candidates_wikimedia.jsonl

Output:
  db/quality/all_candidates.jsonl — one row per (suspect, candidate) tuple.

Schema of output rows:
  {
    "exercise_id": int,
    "name": str,
    "source": "free-exercise-db" | "wger" | "wikimedia",
    "image_url": str,            # canonical full-size URL we'll download
    "thumb_url": str | None,     # smaller variant if the source gave one
    "license": str,
    "attribution": str,
    "match_meta": { ... }        # source-specific fields for provenance
  }

Dedup rule:
  Same image_url within a single suspect collapses to one row (first wins).

Source-shape notes:
  - fedb candidates have list[image_urls] — we explode to one row per URL.
  - wger candidates have list[image_urls] — same.
  - wikimedia candidates have a single image_url + thumb_url.
"""
from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
QDIR = REPO_ROOT / "db" / "quality"
IN_FEDB = QDIR / "candidates_fedb.jsonl"
IN_WGER = QDIR / "candidates_wger.jsonl"
IN_WIKI = QDIR / "candidates_wikimedia.jsonl"
OUT = QDIR / "all_candidates.jsonl"


def iter_jsonl(path: Path):
    with path.open() as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def merge() -> None:
    # exercise_id -> list of (source, candidate-row)
    by_id: dict[int, list[dict]] = {}

    # fedb
    for row in iter_jsonl(IN_FEDB):
        eid = row["exercise_id"]
        cands = row.get("candidates") or []
        for c in cands:
            for url in c.get("image_urls") or []:
                if not url:
                    continue
                by_id.setdefault(eid, []).append(
                    {
                        "exercise_id": eid,
                        "name": row["name"],
                        "source": "free-exercise-db",
                        "image_url": url,
                        "thumb_url": None,
                        "license": c.get("license") or "",
                        "attribution": c.get("attribution") or "",
                        "match_meta": {
                            "fedb_name": c.get("fedb_name"),
                            "fedb_id": c.get("fedb_id"),
                            "match_score": c.get("match_score"),
                        },
                    }
                )

    # wger
    for row in iter_jsonl(IN_WGER):
        eid = row["exercise_id"]
        cands = row.get("candidates") or []
        for c in cands:
            for url in c.get("image_urls") or []:
                if not url:
                    continue
                by_id.setdefault(eid, []).append(
                    {
                        "exercise_id": eid,
                        "name": row["name"],
                        "source": "wger",
                        "image_url": url,
                        "thumb_url": None,
                        "license": c.get("license") or "",
                        "attribution": c.get("attribution") or "",
                        "match_meta": {
                            "wger_name": c.get("wger_name"),
                            "wger_id": c.get("wger_id"),
                            "match_score": c.get("match_score"),
                            "license_id": c.get("license_id"),
                        },
                    }
                )

    # wikimedia
    for row in iter_jsonl(IN_WIKI):
        eid = row["exercise_id"]
        cands = row.get("candidates") or []
        for c in cands:
            url = c.get("image_url")
            if not url:
                continue
            by_id.setdefault(eid, []).append(
                {
                    "exercise_id": eid,
                    "name": row["name"],
                    "source": "wikimedia",
                    "image_url": url,
                    "thumb_url": c.get("thumb_url"),
                    "license": c.get("license") or "",
                    "attribution": c.get("attribution") or "",
                    "match_meta": {
                        "commons_title": c.get("commons_title"),
                        "match_method": c.get("match_method"),
                    },
                }
            )

    # Dedup per-suspect by image_url (first wins). Then write out.
    n_out = 0
    n_dupes_within_suspect = 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w") as f:
        for eid in sorted(by_id):
            seen: set[str] = set()
            for row in by_id[eid]:
                url = row["image_url"]
                if url in seen:
                    n_dupes_within_suspect += 1
                    continue
                seen.add(url)
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
                n_out += 1

    n_suspects_with_any = sum(1 for v in by_id.values() if v)
    print(f"Suspects with at least one candidate: {n_suspects_with_any}")
    print(f"Output rows (after per-suspect dedup): {n_out}")
    print(f"Dropped intra-suspect dupes: {n_dupes_within_suspect}")
    print(f"Wrote: {OUT}")


if __name__ == "__main__":
    merge()
