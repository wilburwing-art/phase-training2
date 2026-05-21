#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "httpx",
#     "thefuzz",
#     "python-Levenshtein",
# ]
# ///
"""Match suspect exercises against the wger.de public exercise catalog.

Reads `db/quality/suspects.jsonl`, fetches the full English exercise catalog
from wger.de's `/api/v2/exerciseinfo/` endpoint (images are inline), fuzzy-
matches each suspect name against wger exercise names, and writes top-3
candidates per suspect to `db/quality/candidates_wger.jsonl` (one row per
suspect, even when no match).

License filter: wger licenses are 1=CC-BY-SA 3, 2=CC-BY-SA 4, 3=CC0, 4=CC-BY 4,
5=ODbL. All clean for our use; we still record per-image license_id and a
short name in the output for downstream attribution.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import httpx
from thefuzz import fuzz, process

REPO_ROOT = Path(__file__).resolve().parents[3]
SUSPECTS_PATH = REPO_ROOT / "db" / "quality" / "suspects.jsonl"
OUTPUT_PATH = REPO_ROOT / "db" / "quality" / "candidates_wger.jsonl"
CACHE_PATH = Path("/tmp/wger-exercises.json")

API_BASE = "https://wger.de/api/v2"
ENGLISH_LANGUAGE_ID = 2
PAGE_SIZE = 200
REQUEST_SLEEP_SECONDS = 0.25

# wger license IDs -> short names (verified via /api/v2/license/).
LICENSE_NAMES = {
    1: "CC-BY-SA 3",
    2: "CC-BY-SA 4",
    3: "CC0",
    4: "CC-BY 4",
    5: "ODbL",
}
# License IDs we accept for image candidates. All five wger licenses are
# permissive enough for our attribution model; we keep the full set so we
# don't silently drop valid images.
ALLOWED_LICENSE_IDS = {1, 2, 3, 4, 5}

MATCH_THRESHOLD = 75
TOP_N = 3
MAX_IMAGES_PER_CANDIDATE = 2


def fetch_catalog() -> list[dict]:
    """Fetch the full English exerciseinfo catalog (paginated), caching locally.

    Each entry includes inline `images` and `translations` arrays, so we do not
    need a second endpoint call for images.
    """
    if CACHE_PATH.exists():
        with CACHE_PATH.open() as f:
            data = json.load(f)
        print(
            f"Loaded {len(data)} wger exercises from cache {CACHE_PATH}",
            file=sys.stderr,
        )
        return data

    results: list[dict] = []
    offset = 0
    with httpx.Client(timeout=30.0, follow_redirects=True) as client:
        while True:
            url = (
                f"{API_BASE}/exerciseinfo/"
                f"?language={ENGLISH_LANGUAGE_ID}&limit={PAGE_SIZE}&offset={offset}"
            )
            print(f"GET {url}", file=sys.stderr)
            resp = client.get(url)
            if resp.status_code == 429:
                # Back off and retry once.
                retry_after = int(resp.headers.get("Retry-After", "10"))
                print(f"429; sleeping {retry_after}s and retrying", file=sys.stderr)
                time.sleep(retry_after)
                resp = client.get(url)
            resp.raise_for_status()
            payload = resp.json()
            page = payload.get("results", [])
            results.extend(page)
            if not payload.get("next") or not page:
                break
            offset += PAGE_SIZE
            time.sleep(REQUEST_SLEEP_SECONDS)

    CACHE_PATH.write_text(json.dumps(results))
    print(
        f"Cached {len(results)} wger exercises to {CACHE_PATH}", file=sys.stderr
    )
    return results


def english_name(entry: dict) -> str | None:
    """Return the English translation name for an exerciseinfo entry."""
    for t in entry.get("translations") or []:
        # The `/exerciseinfo/?language=2` filter restricts to entries that
        # have an English translation, but translation entries inside still
        # include all languages — pick by language id explicitly.
        if t.get("language") == ENGLISH_LANGUAGE_ID:
            name = (t.get("name") or "").strip()
            if name:
                return name
    return None


def build_match_index(
    catalog: list[dict],
) -> tuple[list[str], dict[str, dict]]:
    """Return (names, by_name) for fuzzy matching against English names."""
    by_name: dict[str, dict] = {}
    names: list[str] = []
    for entry in catalog:
        name = english_name(entry)
        if not name:
            continue
        # Prefer the first occurrence; wger occasionally lists near-dupes.
        if name not in by_name:
            by_name[name] = entry
            names.append(name)
    return names, by_name


def license_short_name(license_id: int | None) -> str:
    if license_id is None:
        return "unknown"
    return LICENSE_NAMES.get(license_id, f"license_id={license_id}")


def candidate_for(entry: dict, matched_name: str, score: int) -> dict:
    """Build a candidate dict from a wger exerciseinfo entry."""
    images = entry.get("images") or []
    # Prefer is_main=true first, then the rest. Keep license-clean only.
    sorted_imgs = sorted(images, key=lambda i: 0 if i.get("is_main") else 1)
    image_urls: list[str] = []
    image_license_ids: list[int] = []
    for img in sorted_imgs:
        lic_id = img.get("license")
        if lic_id is not None and lic_id not in ALLOWED_LICENSE_IDS:
            continue
        url = img.get("image")
        if not url:
            continue
        image_urls.append(url)
        if isinstance(lic_id, int):
            image_license_ids.append(lic_id)
        if len(image_urls) >= MAX_IMAGES_PER_CANDIDATE:
            break

    # Per-candidate license: use the first image's license if available,
    # else fall back to the exerciseinfo-level license.
    if image_license_ids:
        primary_license_id = image_license_ids[0]
    else:
        primary_license_id = (entry.get("license") or {}).get("id")
    primary_license_name = license_short_name(primary_license_id)

    author = (entry.get("license_author") or "").strip() or "unknown"
    attribution = f"wger.de, {primary_license_name} (author from API: {author})"

    return {
        "wger_name": matched_name,
        "wger_id": entry.get("id"),
        "match_score": int(score),
        "image_urls": image_urls,
        "license": primary_license_name,
        "license_id": primary_license_id,
        "attribution": attribution,
    }


def match_one(
    name: str, names: list[str], by_name: dict[str, dict]
) -> list[dict]:
    """Return top-N candidates (with >=1 license-clean image) above threshold."""
    matches = process.extract(
        name,
        names,
        scorer=fuzz.token_set_ratio,
        # Pull a few extra so we can drop ones with zero clean images.
        limit=TOP_N * 3,
    )
    out: list[dict] = []
    for matched_name, score in matches:
        if score < MATCH_THRESHOLD:
            continue
        entry = by_name[matched_name]
        cand = candidate_for(entry, matched_name, score)
        if not cand["image_urls"]:
            # No usable image — skip this match. Try the next one in line.
            continue
        out.append(cand)
        if len(out) >= TOP_N:
            break
    return out


def main() -> int:
    catalog = fetch_catalog()
    names, by_name = build_match_index(catalog)
    print(f"Indexed {len(names)} unique English wger names", file=sys.stderr)

    suspects: list[dict] = []
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
                "source": "wger",
                "candidates": cands,
            }
            out.write(json.dumps(row) + "\n")

    pct = 100.0 * with_candidates / len(suspects) if suspects else 0.0
    print(
        f"Wrote {len(suspects)} rows to {OUTPUT_PATH}; "
        f"{with_candidates} have >=1 candidate ({pct:.1f}% coverage)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
