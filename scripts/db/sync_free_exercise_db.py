#!/usr/bin/env python3
"""Sync image_url + thumbnail_url on db/source/exercises.json from the
yuhonas/free-exercise-db public catalog.

The catalog ships ~873 strength/conditioning exercises with stepwise photos
under MIT-friendly terms and a stable raw.githubusercontent.com host. Our
own catalog has ~789 entries with only 61 image_urls hand-populated. This
script matches by name (normalized) and fills the rest.

Run:
    python3 scripts/db/sync_free_exercise_db.py
Then:
    python3 scripts/db/build_db.py
to regenerate coach.db before committing.

Idempotent — running twice is a no-op. Only fills entries where image_url
is null/empty. Never overwrites existing values.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
OURS_PATH = REPO_ROOT / "db" / "source" / "exercises.json"
THEIRS_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
IMAGE_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

# A short manual override list for high-value exercises whose names diverge
# enough that normalization won't find them. Maps our slug → their id.
MANUAL_OVERRIDES: dict[str, str] = {
    # add as discovered, e.g. "barbell-back-squat": "Barbell_Squat",
}


_PLURAL_STRIP = re.compile(r"(?<=[a-z])s\b")


def normalize(name: str) -> str:
    """Lowercase, drop punctuation, collapse whitespace, strip trailing 's' on
    words. Aggressive enough that 'Push-Up' and 'Pushups' both become
    'pushup'. Used for both sides."""
    s = name.lower()
    s = s.replace("-", "")  # join hyphenated compounds: push-up → pushup
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = _PLURAL_STRIP.sub("", s)
    return s


def token_set(s: str) -> frozenset[str]:
    """Bag of word tokens for fuzzy fallback."""
    return frozenset(normalize(s).split())


def main() -> int:
    print(f"Downloading {THEIRS_URL}...")
    with urllib.request.urlopen(THEIRS_URL) as resp:
        theirs = json.load(resp)
    print(f"  free-exercise-db catalog: {len(theirs)} entries")

    by_norm: dict[str, dict] = {}
    by_tokens: dict[frozenset[str], dict] = {}
    by_id: dict[str, dict] = {}
    for ex in theirs:
        n = normalize(ex["name"])
        by_norm.setdefault(n, ex)
        by_tokens.setdefault(token_set(ex["name"]), ex)
        by_id[ex["id"]] = ex

    print(f"Reading {OURS_PATH}...")
    with OURS_PATH.open() as f:
        ours = json.load(f)
    print(f"  our catalog: {len(ours)} entries")

    already_with_image = sum(1 for e in ours if e.get("image_url"))
    print(f"  already with image_url: {already_with_image}")

    exact_hits = 0
    fuzzy_hits = 0
    manual_hits = 0
    misses = 0
    miss_names: list[str] = []

    for ex in ours:
        if ex.get("image_url"):
            continue  # never overwrite existing

        match = None
        # 1. manual override by our slug
        if ex.get("slug") in MANUAL_OVERRIDES:
            match = by_id.get(MANUAL_OVERRIDES[ex["slug"]])
            if match:
                manual_hits += 1

        # 2. exact normalized name match
        if not match:
            match = by_norm.get(normalize(ex["name"]))
            if match:
                exact_hits += 1

        # 3. fuzzy: Jaccard-similarity over token sets, gated by a high
        #    threshold. Picks the strongest peer above the threshold; ties go
        #    to the shorter (closer-fit) name. ≥2 distinguishing tokens
        #    required on our side to avoid noise like "Pull-Up" → random pulls.
        if not match:
            ours_tokens = token_set(ex["name"])
            if len(ours_tokens) >= 2:
                best: tuple[float, int, dict] | None = None
                for theirs_tokens, theirs_ex in by_tokens.items():
                    if len(theirs_tokens) < 2:
                        continue
                    intersect = len(ours_tokens & theirs_tokens)
                    union = len(ours_tokens | theirs_tokens)
                    if intersect < 2 or union == 0:
                        continue
                    sim = intersect / union
                    if sim < 0.6:
                        continue
                    score = (sim, -len(theirs_ex["name"]))
                    if best is None or score > (best[0], best[1]):
                        best = (sim, -len(theirs_ex["name"]), theirs_ex)
                if best:
                    match = best[2]
                    fuzzy_hits += 1

        if not match:
            misses += 1
            miss_names.append(ex["name"])
            continue

        images = match.get("images") or []
        if not images:
            misses += 1
            miss_names.append(ex["name"])
            continue

        url = IMAGE_BASE + images[0]
        ex["image_url"] = url
        ex["thumbnail_url"] = url

    print()
    print("Match summary:")
    print(f"  manual overrides:   {manual_hits}")
    print(f"  exact name matches: {exact_hits}")
    print(f"  fuzzy matches:      {fuzzy_hits}")
    print(f"  unmatched:          {misses}")

    filled = sum(1 for e in ours if e.get("image_url"))
    pct = filled / len(ours) * 100
    print(f"  total image_url coverage now: {filled}/{len(ours)} ({pct:.1f}%)")

    print(f"\nWriting {OURS_PATH}...")
    with OURS_PATH.open("w") as f:
        json.dump(ours, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("Done. Run: python3 scripts/db/build_db.py")

    if "--show-misses" in sys.argv:
        print("\nUnmatched names (first 30):")
        for n in miss_names[:30]:
            print(f"  - {n}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
