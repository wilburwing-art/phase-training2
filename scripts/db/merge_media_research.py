#!/usr/bin/env python3
"""Merge per-cluster media research JSONLs into db/source/exercises.json,
then rebuild coach.db. Idempotent — re-running with the same JSONLs is a
no-op because we only fill empty fields.

Per-row JSONL spec (agent output):
  {"slug": "<existing slug>",
   "image_url": "https://..." | null,
   "thumbnail_url": "https://..." | null,
   "video_url": "https://www.youtube.com/watch?v=..." | null,
   "source_video_attribution": "Channel Name (YouTube)" | null,
   "confidence": "high" | "medium" | "low" | "none",
   "notes": "free text"}

Validation:
  - slug must exist in exercises.json
  - URLs must be HTTPS
  - URL domain must be on whitelist per medium type
  - if video_url set, source_video_attribution must be non-empty
  - never overwrite a non-empty existing field

Run:
    python3 scripts/db/merge_media_research.py
    # then:
    python3 scripts/db/build_db.py
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source" / "exercises.json"
RESEARCH_DIR = REPO_ROOT / "db" / "source" / "media" / "research"

# Domain whitelists per medium type.
IMAGE_DOMAINS = {
    "raw.githubusercontent.com",
    "upload.wikimedia.org",
    "commons.wikimedia.org",
    "en.wikipedia.org",
    "www.physio-pedia.com",
    "physio-pedia.com",
    "www.nhs.uk",
    "nhs.uk",
    "exrx.net",
    "www.exrx.net",
    "strengthlevel.com",
    "www.strengthlevel.com",
}
VIDEO_DOMAINS = {
    "www.youtube.com",
    "youtube.com",
    "youtu.be",
    "vimeo.com",
    "www.vimeo.com",
}


def host(url: str) -> str:
    return (urlparse(url).hostname or "").lower()


def is_https(url: str) -> bool:
    return urlparse(url).scheme == "https"


def validate_row(row: dict, valid_slugs: set[str]) -> list[str]:
    errs: list[str] = []
    if "slug" not in row:
        return ["missing slug"]
    if row["slug"] not in valid_slugs:
        errs.append(f"unknown slug: {row['slug']}")
        return errs

    img = row.get("image_url")
    thumb = row.get("thumbnail_url")
    vid = row.get("video_url")
    attr = row.get("source_video_attribution")

    for label, url in (("image_url", img), ("thumbnail_url", thumb), ("video_url", vid)):
        if url is None:
            continue
        if not isinstance(url, str) or not url.strip():
            errs.append(f"{label} must be string or null")
            continue
        if not is_https(url):
            errs.append(f"{label} must be HTTPS: {url}")
            continue
        if label == "video_url":
            if host(url) not in VIDEO_DOMAINS:
                errs.append(f"{label} domain not whitelisted: {host(url)}")
        else:
            if host(url) not in IMAGE_DOMAINS:
                errs.append(f"{label} domain not whitelisted: {host(url)}")

    if vid and not (attr and isinstance(attr, str) and attr.strip()):
        errs.append("video_url present but source_video_attribution empty")

    return errs


def main() -> int:
    if not RESEARCH_DIR.exists():
        print(f"No research dir at {RESEARCH_DIR}", file=sys.stderr)
        return 1

    with SOURCE.open() as f:
        exercises = json.load(f)
    by_slug = {e["slug"]: e for e in exercises}
    valid_slugs = set(by_slug)

    files = sorted(RESEARCH_DIR.glob("*.jsonl"))
    if not files:
        print(f"No JSONL files in {RESEARCH_DIR}", file=sys.stderr)
        return 1

    stats = {
        "rows_seen": 0, "rows_invalid": 0, "rows_applied": 0,
        "image_filled": 0, "thumb_filled": 0,
        "video_filled": 0, "attribution_filled": 0,
        "skipped_already_filled": 0,
    }
    invalid_log: list[str] = []

    for path in files:
        with path.open() as f:
            for lineno, line in enumerate(f, 1):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as e:
                    invalid_log.append(f"{path.name}:{lineno} json error: {e}")
                    stats["rows_invalid"] += 1
                    continue
                stats["rows_seen"] += 1
                errs = validate_row(row, valid_slugs)
                if errs:
                    invalid_log.append(f"{path.name}:{lineno} {row.get('slug')}: {'; '.join(errs)}")
                    stats["rows_invalid"] += 1
                    continue
                target = by_slug[row["slug"]]
                applied_any = False
                for field in ("image_url", "thumbnail_url", "video_url", "source_video_attribution"):
                    incoming = row.get(field)
                    if incoming and not target.get(field):
                        target[field] = incoming
                        applied_any = True
                        stats[{
                            "image_url": "image_filled",
                            "thumbnail_url": "thumb_filled",
                            "video_url": "video_filled",
                            "source_video_attribution": "attribution_filled",
                        }[field]] += 1
                if applied_any:
                    stats["rows_applied"] += 1
                else:
                    stats["skipped_already_filled"] += 1

    print("Merge stats:")
    for k, v in stats.items():
        print(f"  {k:30s} {v}")

    if invalid_log:
        print(f"\n{len(invalid_log)} invalid rows (first 20):")
        for line in invalid_log[:20]:
            print(f"  {line}")

    with SOURCE.open("w") as f:
        json.dump(exercises, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # Coverage report
    total = len(exercises)
    has_img = sum(1 for e in exercises if e.get("image_url"))
    has_vid = sum(1 for e in exercises if e.get("video_url"))
    has_either = sum(1 for e in exercises if e.get("image_url") or e.get("video_url"))
    print(f"\nCoverage after merge ({total} total):")
    print(f"  image_url:           {has_img} ({100*has_img/total:.1f}%)")
    print(f"  video_url:           {has_vid} ({100*has_vid/total:.1f}%)")
    print(f"  any media (img|vid): {has_either} ({100*has_either/total:.1f}%)")
    print("\nDone. Next: python3 scripts/db/build_db.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
