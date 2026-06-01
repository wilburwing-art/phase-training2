#!/usr/bin/env python3
"""Fetch real license + attribution for Wikimedia-sourced exercise images.

Many wikimedia rows in db/source/exercises.json have an image_url but no
license/attribution and no entry in the quality provenance (they were added
after the image-quality pass). Commons only hosts freely-licensed files, but
CC-BY-SA still requires correct attribution — so we pull the actual
LicenseShortName + Artist from the Commons API (extmetadata) rather than
guess. Files that can't be resolved are left untouched and reported.

Run backfill_image_licenses.py first (handles free-exercise-db + exrx), then
this, then build_db.py.
"""
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXERCISES = ROOT / "db" / "source" / "exercises.json"
API = "https://commons.wikimedia.org/w/api.php"
TAGS = re.compile(r"<[^>]+>")


def commons_filename(url: str) -> str:
    path = urllib.parse.unquote(url or "")
    if "/thumb/" in path:
        parts = path.split("/thumb/")[1].split("/")
        return parts[2] if len(parts) >= 3 else ""
    return path.rsplit("/", 1)[-1]


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", TAGS.sub("", html.unescape(text or ""))).strip()


def fetch(titles: list[str]) -> dict:
    """title -> (license, artist) for a batch (<=50)."""
    q = {
        "action": "query", "format": "json", "prop": "imageinfo",
        "iiprop": "extmetadata", "titles": "|".join(titles),
    }
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(q),
                                 headers={"User-Agent": "phase-training/1.0 (license audit)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    out = {}
    pages = data.get("query", {}).get("pages", {})
    norm = {n["to"]: n["from"] for n in data.get("query", {}).get("normalized", [])}
    for p in pages.values():
        if "imageinfo" not in p:
            continue
        em = p["imageinfo"][0].get("extmetadata", {})
        lic = clean(em.get("LicenseShortName", {}).get("value", ""))
        artist = clean(em.get("Artist", {}).get("value", ""))
        title = p["title"]
        out[title] = (lic, artist)
        if title in norm:
            out[norm[title]] = (lic, artist)
    return out


def main() -> int:
    rows = json.loads(EXERCISES.read_text())
    targets = []  # (row, "File:<name>")
    for r in rows:
        if (r.get("image_source") or "").lower() != "wikimedia":
            continue
        if r.get("image_license") or not (r.get("image_url") or "").strip():
            continue
        name = commons_filename(r["image_url"])
        if name:
            targets.append((r, "File:" + name))

    print(f"wikimedia rows needing a license: {len(targets)}")
    resolved = unresolved = 0
    misses = []
    for i in range(0, len(targets), 40):
        batch = targets[i:i + 40]
        result = fetch([t for _, t in batch])
        for row, title in batch:
            lic, artist = result.get(title, ("", ""))
            if lic:
                row["image_license"] = lic
                row["image_attribution"] = (
                    f"Wikimedia Commons — {artist} ({lic})" if artist
                    else f"Wikimedia Commons ({lic})")
                resolved += 1
            else:
                unresolved += 1
                misses.append((row.get("id"), row.get("name"), title))
        time.sleep(0.5)

    EXERCISES.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
    print(f"resolved: {resolved}   unresolved: {unresolved}")
    for mid, name, title in misses:
        print(f"  UNRESOLVED id={mid} {name} [{title}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
