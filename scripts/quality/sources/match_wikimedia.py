#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "httpx",
# ]
# ///
"""Match suspect exercises against Wikimedia Commons images.

Reads `db/quality/suspects.jsonl`, searches Wikimedia Commons File namespace
for each exercise name, verifies licenses against an allowlist, and writes
license-clean candidate image URLs to `db/quality/candidates_wikimedia.jsonl`
(one row per suspect, even when no match).
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

import httpx

REPO_ROOT = Path(__file__).resolve().parents[3]
SUSPECTS_PATH = REPO_ROOT / "db" / "quality" / "suspects.jsonl"
OUTPUT_PATH = REPO_ROOT / "db" / "quality" / "candidates_wikimedia.jsonl"

API_URL = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "phase-training2 image-quality-pass (wilburwing@gmail.com)"
SLEEP_SECONDS = 0.10  # rate-limit politeness

# Allowed licenses (case-insensitive contains-match on LicenseShortName).
# Per Wikimedia conventions, LicenseShortName values are typically things
# like "CC BY-SA 4.0", "CC BY 3.0", "CC0", "Public domain", with hyphens or
# spaces. Normalize before comparison.
ALLOWED_LICENSES = {
    "CC0",
    "CC-BY-3.0",
    "CC-BY-4.0",
    "CC-BY-SA-3.0",
    "CC-BY-SA-4.0",
    "PUBLIC-DOMAIN",
}

TOP_N = 2
SEARCH_LIMIT = 8  # over-fetch so we have room after filtering noise

# Skip non-image media: PDFs (book scans), DjVu (more book scans), audio.
# These dominate Commons search noise for "<exercise name> exercise" because
# 19th-century PE textbooks have "exercise" in the title.
REJECTED_EXTENSIONS = (".pdf", ".djvu", ".ogg", ".oga", ".wav", ".mid")


def normalize_license(raw: str) -> str:
    """Normalize a LicenseShortName for allowlist comparison.

    Examples:
      "CC BY-SA 4.0"   -> "CC-BY-SA-4.0"
      "CC BY 3.0"      -> "CC-BY-3.0"
      "Public domain"  -> "PUBLIC-DOMAIN"
      "CC0"            -> "CC0"
    """
    s = raw.strip().upper()
    s = re.sub(r"\s+", "-", s)
    s = s.replace("--", "-")
    return s


def strip_html(s: str) -> str:
    """Strip HTML tags from extmetadata values (Artist often has <a> tags)."""
    return re.sub(r"<[^>]+>", "", s or "").strip()


def search_files(client: httpx.Client, query: str) -> list[str]:
    """Search Commons File namespace for files matching query.

    Returns a list of "File:..." titles.
    """
    params = {
        "action": "query",
        "format": "json",
        "list": "search",
        "srnamespace": 6,  # File namespace
        "srsearch": query,
        "srlimit": SEARCH_LIMIT,
    }
    try:
        resp = client.get(API_URL, params=params, timeout=30.0)
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        print(f"  search error for {query!r}: {e}", file=sys.stderr)
        return []

    hits = data.get("query", {}).get("search", [])
    titles: list[str] = []
    for hit in hits:
        title = hit.get("title")
        if title:
            titles.append(title)
    return titles


def fetch_imageinfo(client: httpx.Client, title: str) -> dict | None:
    """Fetch imageinfo (url + extmetadata) for a single file title."""
    params = {
        "action": "query",
        "format": "json",
        "prop": "imageinfo",
        "iiprop": "url|extmetadata",
        "titles": title,
    }
    try:
        resp = client.get(API_URL, params=params, timeout=30.0)
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        print(f"  imageinfo error for {title!r}: {e}", file=sys.stderr)
        return None

    pages = data.get("query", {}).get("pages", {})
    for _page_id, page in pages.items():
        infos = page.get("imageinfo") or []
        if not infos:
            continue
        return infos[0]
    return None


def thumb_url_from_image(image_url: str, width: int = 320) -> str:
    """Derive a Commons thumbnail URL from a full-res upload URL.

    Commons convention:
      https://upload.wikimedia.org/wikipedia/commons/a/ab/Foo.jpg
      ->
      https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Foo.jpg/320px-Foo.jpg
    """
    if "/commons/" not in image_url or "/commons/thumb/" in image_url:
        return image_url
    parts = image_url.rsplit("/", 1)
    if len(parts) != 2:
        return image_url
    prefix, filename = parts
    thumb_prefix = prefix.replace("/commons/", "/commons/thumb/", 1)
    return f"{thumb_prefix}/{filename}/{width}px-{filename}"


def make_candidate(
    title: str,
    info: dict,
    license_normalized: str,
    license_raw: str,
) -> dict:
    """Build a candidate dict from imageinfo + verified license."""
    image_url = info.get("url", "")
    extmeta = info.get("extmetadata", {}) or {}
    artist = strip_html(extmeta.get("Artist", {}).get("value", "")) or "Unknown"
    return {
        "commons_title": title,
        "image_url": image_url,
        "thumb_url": thumb_url_from_image(image_url),
        "license": license_normalized,
        "attribution": (
            f"Wikimedia Commons, {license_raw}, author: {artist}"
        ),
        "match_method": "search_with_exercise_keyword",
    }


def match_one(client: httpx.Client, exercise_name: str) -> list[dict]:
    """Return up to TOP_N license-clean candidates for one exercise."""
    query = f"{exercise_name} exercise"
    titles = search_files(client, query)
    time.sleep(SLEEP_SECONDS)

    candidates: list[dict] = []
    for title in titles:
        if len(candidates) >= TOP_N:
            break
        # Skip non-image / book-scan formats up front (no API call needed).
        if title.lower().endswith(REJECTED_EXTENSIONS):
            continue
        info = fetch_imageinfo(client, title)
        time.sleep(SLEEP_SECONDS)
        if not info:
            continue
        extmeta = info.get("extmetadata", {}) or {}
        license_raw = (extmeta.get("LicenseShortName", {}) or {}).get("value", "")
        if not license_raw:
            continue
        license_norm = normalize_license(license_raw)
        if license_norm not in ALLOWED_LICENSES:
            continue
        candidates.append(make_candidate(title, info, license_norm, license_raw))

    return candidates


def main() -> int:
    suspects = []
    with SUSPECTS_PATH.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            suspects.append(json.loads(line))
    print(f"Loaded {len(suspects)} suspects", file=sys.stderr)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    headers = {"User-Agent": USER_AGENT}
    with_candidates = 0
    license_histogram: dict[str, int] = {}

    with httpx.Client(headers=headers) as client, OUTPUT_PATH.open("w") as out:
        for i, s in enumerate(suspects, 1):
            try:
                cands = match_one(client, s["name"])
            except Exception as e:  # noqa: BLE001 — defensive; keep going
                print(f"[{i}] {s['name']!r}: unexpected error: {e}", file=sys.stderr)
                cands = []

            if cands:
                with_candidates += 1
            for c in cands:
                license_histogram[c["license"]] = (
                    license_histogram.get(c["license"], 0) + 1
                )

            row = {
                "exercise_id": s["exercise_id"],
                "name": s["name"],
                "source": "wikimedia",
                "candidates": cands,
            }
            out.write(json.dumps(row) + "\n")
            out.flush()

            if i % 20 == 0:
                print(
                    f"  [{i}/{len(suspects)}] {with_candidates} matched so far",
                    file=sys.stderr,
                )

    print(
        f"\nWrote {len(suspects)} rows to {OUTPUT_PATH}",
        file=sys.stderr,
    )
    print(
        f"Coverage: {with_candidates}/{len(suspects)} "
        f"({100.0 * with_candidates / len(suspects):.1f}%) "
        f"have >=1 license-clean candidate",
        file=sys.stderr,
    )
    print("License histogram:", file=sys.stderr)
    for lic, n in sorted(license_histogram.items(), key=lambda kv: -kv[1]):
        print(f"  {lic}: {n}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
