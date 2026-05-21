#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "httpx>=0.27",
#   "Pillow>=10.0",
# ]
# ///
"""Download each unique candidate URL, convert to WebP (q85, max-dim 320), cache.

Reads:  db/quality/all_candidates.jsonl
Writes: db/quality/candidate_thumbs/<sha1>.webp    (gitignored — temp files)
        db/quality/candidate_dl_failures.jsonl     (failures, one per url)

Idempotent: skips URLs whose hashed WebP is already on disk.

Convert pipeline mirrors scripts/download_exercise_images.py (same q85, 320px,
RGBA-to-RGB-on-white, palette unpack, etc.) so the scored WebPs are pixel-grade
comparable to the ones already shipping in the app.
"""
from __future__ import annotations

import hashlib
import io
import json
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import httpx
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
QDIR = REPO_ROOT / "db" / "quality"
IN_PATH = QDIR / "all_candidates.jsonl"
OUT_DIR = QDIR / "candidate_thumbs"
FAIL_PATH = QDIR / "candidate_dl_failures.jsonl"

MAX_DIM = 320
QUALITY = 85
TIMEOUT = 20.0
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 "
    "PhaseTrainingBundler/1.0 (wilburwing@gmail.com)"
)


def sha1_of(url: str) -> str:
    return hashlib.sha1(url.encode("utf-8")).hexdigest()


def fetch(client: httpx.Client, url: str) -> tuple[bytes | None, str | None]:
    host = (urlparse(url).hostname or "").lower()
    if "wikimedia.org" in host:
        time.sleep(1.1)
    last_err: str | None = None
    for attempt in range(3):
        try:
            r = client.get(url, timeout=TIMEOUT, follow_redirects=True)
            if r.status_code == 429:
                wait = float(r.headers.get("retry-after", 2 ** (attempt + 1)))
                time.sleep(min(wait, 20))
                continue
            if r.status_code >= 400:
                last_err = f"HTTP {r.status_code}"
                if r.status_code in (403, 404):
                    return None, last_err  # no point retrying
                time.sleep(1.5 * (attempt + 1))
                continue
            ct = r.headers.get("content-type", "").lower()
            if "html" in ct or "text/" in ct:
                return None, f"non-image content-type: {ct}"
            return r.content, None
        except Exception as e:
            last_err = f"{type(e).__name__}: {e}"
            time.sleep(1.5 * (attempt + 1))
    return None, last_err or "unknown"


def to_webp(blob: bytes) -> bytes | None:
    try:
        img = Image.open(io.BytesIO(blob))
        if img.size == (480, 360):
            img = img.crop((0, 45, 480, 315))
        if img.mode in ("RGBA", "LA", "P"):
            bg = Image.new("RGB", img.size, (255, 255, 255))
            if img.mode == "P":
                img = img.convert("RGBA")
            bg.paste(img, mask=img.split()[-1] if img.mode in ("RGBA", "LA") else None)
            img = bg
        elif img.mode != "RGB":
            img = img.convert("RGB")
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
    if not IN_PATH.exists():
        print(f"missing input: {IN_PATH}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Collect unique URLs (prefer thumb_url for wikimedia gifs since they're
    # smaller; for the others, image_url is what we have).
    # NOTE: wikimedia's thumb endpoint 400s on animated GIFs (no auto-derived
    # thumbs). We keep a parallel `fallback_url` (full image_url) per entry
    # and the fetch step retries with it on 400.
    unique: dict[str, dict] = {}  # url -> first row that mentioned it
    fallback: dict[str, str] = {}  # url -> full image_url to retry on 400
    with IN_PATH.open() as f:
        for line in f:
            row = json.loads(line)
            # For wikimedia, prefer the source-supplied thumb (already 320px JPEG of the
            # gif/jpg). For the others, image_url IS the canonical fetch URL.
            if row["source"] == "wikimedia":
                url = row.get("thumb_url") or row["image_url"]
                fb = row["image_url"]
            else:
                url = row["image_url"]
                fb = url
            if not url:
                continue
            unique.setdefault(url, row)
            fallback.setdefault(url, fb)

    total = len(unique)
    print(f"Unique candidate URLs to download: {total}")

    n_skipped = 0
    n_fetched = 0
    n_converted = 0
    failures: list[dict] = []

    with httpx.Client(headers={"User-Agent": USER_AGENT}) as client:
        for i, (url, row) in enumerate(unique.items(), 1):
            sha = sha1_of(url)
            out_path = OUT_DIR / f"{sha}.webp"
            if out_path.exists():
                n_skipped += 1
                continue
            if i % 25 == 0 or i <= 5:
                print(f"[{i}/{total}] ex={row['exercise_id']} src={row['source']} {url[:80]}")
            blob, err = fetch(client, url)
            # Wikimedia thumb endpoint 400s on animated GIFs (no auto-derived
            # thumbs). Retry against the full image_url.
            if blob is None and err and "400" in err:
                fb = fallback.get(url)
                if fb and fb != url:
                    blob, err = fetch(client, fb)
            if blob is None:
                failures.append({"exercise_id": row["exercise_id"], "url": url, "source": row["source"], "error": err})
                continue
            n_fetched += 1
            webp = to_webp(blob)
            if webp is None:
                failures.append({"exercise_id": row["exercise_id"], "url": url, "source": row["source"], "error": "convert_failed"})
                continue
            out_path.write_bytes(webp)
            n_converted += 1

    # Failure log
    if failures:
        with FAIL_PATH.open("w") as f:
            for fl in failures:
                f.write(json.dumps(fl) + "\n")

    present = list(OUT_DIR.glob("*.webp"))
    total_bytes = sum(p.stat().st_size for p in present)
    print()
    print("=" * 60)
    print("Candidate download report:")
    print(f"  Unique URLs:          {total}")
    print(f"  Skipped (cached):     {n_skipped}")
    print(f"  Fetched:              {n_fetched}")
    print(f"  Converted:            {n_converted}")
    print(f"  Failed:               {len(failures)}")
    print(f"  Cached WebPs on disk: {len(present)}")
    print(f"  Cache size:           {total_bytes / 1024 / 1024:.2f} MB")
    if failures:
        print(f"\nFailures written to {FAIL_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
