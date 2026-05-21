#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "httpx",
#     "thefuzz",
#     "python-Levenshtein",
# ]
# ///
"""Match suspect exercises against the yuhonas/free-exercise-db catalog.

Reads `db/quality/suspects.jsonl`, fuzzy-matches each exercise name against
the free-exercise-db catalog, and writes candidate image URLs to
`db/quality/candidates_fedb.jsonl` (one row per suspect, even when no match).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import httpx
from thefuzz import fuzz, process

REPO_ROOT = Path(__file__).resolve().parents[3]
SUSPECTS_PATH = REPO_ROOT / "db" / "quality" / "suspects.jsonl"
OUTPUT_PATH = REPO_ROOT / "db" / "quality" / "candidates_fedb.jsonl"
CACHE_PATH = Path("/tmp/fedb-catalog.json")

CATALOG_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
IMAGE_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

MATCH_THRESHOLD = 75
TOP_N = 3


def fetch_catalog() -> list[dict]:
    """Fetch the fedb catalog, caching locally."""
    if CACHE_PATH.exists():
        with CACHE_PATH.open() as f:
            data = json.load(f)
        print(f"Loaded {len(data)} exercises from cache {CACHE_PATH}", file=sys.stderr)
        return data

    print(f"Fetching catalog from {CATALOG_URL}", file=sys.stderr)
    resp = httpx.get(CATALOG_URL, timeout=30.0, follow_redirects=True)
    resp.raise_for_status()
    data = resp.json()
    CACHE_PATH.write_text(json.dumps(data))
    print(f"Cached {len(data)} exercises to {CACHE_PATH}", file=sys.stderr)
    return data


def build_match_index(catalog: list[dict]) -> tuple[list[str], dict[str, dict]]:
    """Return (names, by_name) for fuzzy matching."""
    by_name: dict[str, dict] = {}
    names: list[str] = []
    for entry in catalog:
        name = entry.get("name")
        if not name:
            continue
        # If duplicate names exist, keep the first.
        if name not in by_name:
            by_name[name] = entry
            names.append(name)
    return names, by_name


def candidate_for(entry: dict, score: int) -> dict:
    """Build a candidate dict from a fedb catalog entry."""
    images = entry.get("images") or []
    urls = [IMAGE_BASE + img for img in images]
    return {
        "fedb_name": entry.get("name"),
        "match_score": score,
        "image_urls": urls,
        "fedb_id": entry.get("id") or entry.get("name", "").replace(" ", "_"),
        "license": "MIT",
        "attribution": "free-exercise-db (yuhonas), MIT",
    }


def match_one(name: str, names: list[str], by_name: dict[str, dict]) -> list[dict]:
    """Return top-N candidates above threshold for `name`."""
    matches = process.extract(
        name,
        names,
        scorer=fuzz.token_set_ratio,
        limit=TOP_N,
    )
    out: list[dict] = []
    for matched_name, score in matches:
        if score < MATCH_THRESHOLD:
            continue
        entry = by_name[matched_name]
        out.append(candidate_for(entry, int(score)))
    return out


def main() -> int:
    catalog = fetch_catalog()
    names, by_name = build_match_index(catalog)
    print(f"Indexed {len(names)} unique fedb names", file=sys.stderr)

    suspects = []
    with SUSPECTS_PATH.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            suspects.append(json.loads(line))
    print(f"Loaded {len(suspects)} suspects", file=sys.stderr)

    with_candidates = 0
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w") as out:
        for s in suspects:
            cands = match_one(s["name"], names, by_name)
            if cands:
                with_candidates += 1
            row = {
                "exercise_id": s["exercise_id"],
                "name": s["name"],
                "source": "free-exercise-db",
                "candidates": cands,
            }
            out.write(json.dumps(row) + "\n")

    print(
        f"Wrote {len(suspects)} rows to {OUTPUT_PATH}; "
        f"{with_candidates} have >=1 candidate "
        f"({100.0 * with_candidates / len(suspects):.1f}% coverage)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
