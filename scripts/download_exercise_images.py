#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "httpx>=0.27",
#   "Pillow>=10.0",
# ]
# ///
"""Download exercise image_url/thumbnail_url from coach.db, convert to WebP,
and write to PhaseTraining/Resources/ExerciseImages/<id>.webp.

Idempotent: skips files already present. Logs a final report.

Usage:
    uv run scripts/download_exercise_images.py
"""
from __future__ import annotations

import io
import sqlite3
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import httpx
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
DB_PATH = REPO_ROOT / "PhaseTraining" / "Resources" / "coach.db"
OUT_DIR = REPO_ROOT / "PhaseTraining" / "Resources" / "ExerciseImages"

MAX_DIM = 320  # 56pt @3x = 168px; 88pt presentation density = 264px; 320 covers both.
QUALITY = 85
TIMEOUT = 20.0
# Wikimedia rate-limits / blocks default httpx UA. Use a browser-style UA and
# include a contact-style Mozilla string per Wikimedia's API etiquette.
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 "
    "PhaseTrainingBundler/1.0 (wilburwing@gmail.com)"
)

# exrx.net URLs in the research output point at HTML exercise pages, not image
# files. Skip them — they're a research-artifact bug, not real image URLs.
SKIP_HOST_PREFIXES = ("https://exrx.net/", "https://www.exrx.net/")


def fetch(client: httpx.Client, url: str) -> bytes | None:
    if any(url.startswith(p) for p in SKIP_HOST_PREFIXES):
        return None
    host = (urlparse(url).hostname or "").lower()
    # Wikimedia recommends <= ~1 req/sec from non-API consumers. Throttle.
    if "wikimedia.org" in host:
        time.sleep(1.1)
    last_err: str | None = None
    for attempt in range(3):
        try:
            r = client.get(url, timeout=TIMEOUT, follow_redirects=True)
            if r.status_code == 429:
                # Honor Retry-After if present; otherwise exponential backoff.
                wait = float(r.headers.get("retry-after", 2 ** (attempt + 1)))
                time.sleep(min(wait, 20))
                continue
            r.raise_for_status()
            ct = r.headers.get("content-type", "").lower()
            if "html" in ct or "text/" in ct:
                return None
            return r.content
        except Exception as e:
            last_err = str(e)
            time.sleep(1.5 * (attempt + 1))
    print(f"  fetch failed: {url} -> {last_err}", file=sys.stderr)
    return None


def to_webp(blob: bytes) -> bytes | None:
    try:
        img = Image.open(io.BytesIO(blob))
        # YouTube hqdefault images have black letterbox bars top/bottom (480x360
        # but actual content is 480x270). Crop them off for a clean square.
        if img.size == (480, 360):
            img = img.crop((0, 45, 480, 315))  # 480x270 active region
        # Convert palette/transparent modes to RGB on white background — these
        # WebPs sit on a white surface in ExerciseThumbnail.
        if img.mode in ("RGBA", "LA", "P"):
            bg = Image.new("RGB", img.size, (255, 255, 255))
            if img.mode == "P":
                img = img.convert("RGBA")
            bg.paste(img, mask=img.split()[-1] if img.mode in ("RGBA", "LA") else None)
            img = bg
        elif img.mode != "RGB":
            img = img.convert("RGB")
        # Resize so the longest dimension is <= MAX_DIM.
        w, h = img.size
        scale = min(1.0, MAX_DIM / max(w, h))
        if scale < 1.0:
            img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, format="WEBP", quality=QUALITY, method=6)
        return out.getvalue()
    except Exception as e:
        print(f"  convert failed: {e}", file=sys.stderr)
        return None


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    con = sqlite3.connect(str(DB_PATH))
    rows = con.execute(
        "SELECT id, name, image_url, thumbnail_url FROM exercises "
        "WHERE image_url IS NOT NULL OR thumbnail_url IS NOT NULL"
    ).fetchall()
    con.close()

    total = len(rows)
    print(f"coach.db rows with image: {total}")

    skipped_existing = 0
    fetched = 0
    converted = 0
    failed: list[tuple[int, str, str]] = []

    with httpx.Client(headers={"User-Agent": USER_AGENT}) as client:
        for i, (ex_id, name, image_url, thumb_url) in enumerate(rows, 1):
            out_path = OUT_DIR / f"{ex_id}.webp"
            if out_path.exists():
                skipped_existing += 1
                continue
            # Prefer thumbnail_url (often smaller/closer to target); fall back
            # to image_url.
            url = thumb_url or image_url
            if not url:
                continue
            if i % 25 == 0 or i <= 5:
                print(f"[{i}/{total}] {ex_id} {name[:40]}")
            blob = fetch(client, url)
            if blob is None:
                # If we fell back to thumbnail, try image_url too.
                if thumb_url and image_url and url == thumb_url:
                    blob = fetch(client, image_url)
                # YouTube hqdefault sometimes 404s; mqdefault is the safe
                # fallback that's always present.
                if blob is None and "img.youtube.com/vi/" in url and "hqdefault" in url:
                    blob = fetch(client, url.replace("hqdefault", "mqdefault"))
                if blob is None:
                    failed.append((ex_id, name, url))
                    continue
            fetched += 1
            webp = to_webp(blob)
            if webp is None:
                failed.append((ex_id, name, url))
                continue
            out_path.write_bytes(webp)
            converted += 1

    # Final report
    present = sorted(OUT_DIR.glob("*.webp"))
    total_bytes = sum(p.stat().st_size for p in present)
    print()
    print("=" * 60)
    print("Download report:")
    print(f"  Rows with image:      {total}")
    print(f"  Skipped (existing):   {skipped_existing}")
    print(f"  Fetched:              {fetched}")
    print(f"  Converted:            {converted}")
    print(f"  Failed:               {len(failed)}")
    print(f"  Total bundled files:  {len(present)}")
    print(f"  Total size:           {total_bytes / 1024 / 1024:.2f} MB")
    if failed:
        print()
        print("First 20 failures:")
        for ex_id, name, url in failed[:20]:
            print(f"  {ex_id} {name[:40]}  {url}")
    return 0 if not failed else 0  # don't fail CI on individual misses


if __name__ == "__main__":
    raise SystemExit(main())
