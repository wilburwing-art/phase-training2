#!/usr/bin/env python3
"""Backfill missing image_license / image_attribution in db/source/exercises.json.

85 shipped exercises had an image_url but no license/attribution — a copyright
gap before App Store submission. By verified provenance:

  - free-exercise-db  -> The Unlicense (public domain). Deterministic.
  - wikimedia         -> per-file license, recovered by matching the shipped
                         image_url against db/quality/candidates_wikimedia.jsonl
                         (each candidate carries its real license + attribution).
  - exrx.net ("other")-> NOT license-clean (and the URLs are article pages, not
                         image files). The image reference is removed, not
                         licensed. The app falls back to its bundled thumbnail.

No license is invented: wikimedia rows that can't be matched to provenance are
left untouched and reported so they can be handled by hand. Run build_db.py
afterward to regenerate coach.db.
"""
import json
import re
import sys
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXERCISES = ROOT / "db" / "source" / "exercises.json"
WIKIMEDIA = ROOT / "db" / "quality" / "candidates_wikimedia.jsonl"

FEDB_LICENSE = "Unlicense"
FEDB_ATTRIB = "free-exercise-db (github.com/yuhonas/free-exercise-db)"


def commons_filename(url: str) -> str:
    """Underlying Commons file name from a (possibly thumbnailed) upload URL."""
    if not url:
        return ""
    path = urllib.parse.unquote(url)
    if "/thumb/" in path:
        # .../thumb/3/3d/Name.JPG/250px-Name.JPG  -> Name.JPG
        parts = path.split("/thumb/")[1].split("/")
        return parts[2].lower() if len(parts) >= 3 else ""
    return path.rsplit("/", 1)[-1].lower()


def load_wikimedia_index() -> dict:
    """exercise_id -> list of {filename, license, attribution} candidates."""
    idx: dict[int, list] = {}
    for line in WIKIMEDIA.read_text().splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        eid = d.get("exercise_id")
        cands = []
        for c in d.get("candidates", []):
            title = (c.get("commons_title") or "").removeprefix("File:")
            cands.append({
                "names": {
                    urllib.parse.unquote(title).lower(),
                    commons_filename(c.get("image_url", "")),
                    commons_filename(c.get("thumb_url", "")),
                },
                "license": c.get("license"),
                "attribution": c.get("attribution"),
            })
        idx[eid] = cands
    return idx


def main() -> int:
    data = json.loads(EXERCISES.read_text())
    rows = data if isinstance(data, list) else data.get("exercises", data)
    wiki = load_wikimedia_index()

    fedb = wiki_ok = wiki_miss = exrx = other = 0
    misses = []

    for r in rows:
        url = (r.get("image_url") or "").strip()
        if not url:
            continue
        if r.get("image_license"):
            continue  # already licensed

        src = (r.get("image_source") or "").lower()
        if src == "free-exercise-db":
            r["image_license"] = FEDB_LICENSE
            r["image_attribution"] = FEDB_ATTRIB
            fedb += 1
        elif src == "wikimedia":
            fname = commons_filename(url)
            hit = next((c for c in wiki.get(r.get("id"), [])
                        if c["license"] and fname in c["names"]), None)
            if hit:
                r["image_license"] = hit["license"]
                r["image_attribution"] = hit["attribution"]
                wiki_ok += 1
            else:
                wiki_miss += 1
                misses.append((r.get("id"), r.get("name"), fname))
        elif "exrx.net" in url:
            # Unlicensed page URL — drop the reference entirely.
            r["image_url"] = None
            r["image_source"] = None
            r["image_license"] = None
            r["image_attribution"] = None
            exrx += 1
        else:
            other += 1
            misses.append((r.get("id"), r.get("name"), url))

    EXERCISES.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")

    print(f"free-exercise-db -> Unlicense : {fedb}")
    print(f"wikimedia matched from provenance: {wiki_ok}")
    print(f"exrx.net references removed   : {exrx}")
    print(f"wikimedia UNMATCHED (left as-is): {wiki_miss}")
    print(f"other UNHANDLED                : {other}")
    if misses:
        print("\nNeeds manual handling:")
        for mid, name, key in misses:
            print(f"  id={mid}  {name}  [{key}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
