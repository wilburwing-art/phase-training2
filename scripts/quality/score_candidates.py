#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "anthropic>=0.45.0",
#   "sqlite-utils>=3.36",
#   "pillow>=10.0",
# ]
# ///
"""Layer 2 vision scoring on downloaded candidate WebPs.

Reuses the same rubric / model / batch API as scripts/quality/vision_triage.py.
Each (suspect, candidate-URL) tuple becomes one request; the custom_id encodes
both the exercise_id and the URL hash so we can fan results back out.

Inputs:
  db/quality/all_candidates.jsonl   (one row per (suspect, candidate))
  db/quality/candidate_thumbs/<sha1>.webp  (downloaded by download_candidates.py)
  PhaseTraining/Resources/coach.db  (for the suspect's muscles + equipment)

Output:
  db/quality/candidate_scores.jsonl — one row per scored tuple.

Schema of each output row:
  {
    "exercise_id": int,
    "url_sha1": str,
    "image_url": str,
    "source": str,
    "score": int | null,
    "reason": str | null,
    "confidence": "low" | "med" | "high" | null,
    "scored_at": iso8601,
    "batch_id": str,
  }
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import sqlite3
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

import anthropic
from anthropic.types.messages.batch_create_params import Request
from anthropic.types.message_create_params import MessageCreateParamsNonStreaming

REPO_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = REPO_ROOT / "PhaseTraining" / "Resources" / "coach.db"
QDIR = REPO_ROOT / "db" / "quality"
IN_PATH = QDIR / "all_candidates.jsonl"
THUMB_DIR = QDIR / "candidate_thumbs"
OUT_PATH = QDIR / "candidate_scores.jsonl"
MODEL = "claude-haiku-4-5-20251001"
COST_CAP_USD = 2.00
BATCH_CHUNK_SIZE = 100

SYSTEM_PROMPT = """You are an expert lifting coach scoring exercise demonstration images.

You will be shown ONE image and told the name of an exercise. Your job is to judge whether the image depicts that named exercise being performed.

Rubric (output an integer 1-5):
  5 = clearly the exercise, mid-motion, recognizable
  4 = likely the exercise but a minor issue (text overlay, awkward angle, partial frame)
  3 = ambiguous — could be the exercise, could be a similar movement
  2 = wrong but related exercise (e.g. barbell row when asked dumbbell row; squat when asked lunge)
  1 = unrelated entirely (host face close-up, B-roll/gym wide-shot with no athlete, watermark-dominated, YouTube placeholder)

Be strict at 5 — reserve it for images that unambiguously show the named lift mid-motion. If you see a host face filling the frame with no exercise happening, score 1. If the lift is wrong (e.g. shoulder press shown for chest press), score 2.

Respond with JSON only — no prose, no markdown fences. Schema:
{"score": <1-5>, "reason": "<<=20 words>", "confidence": "low" | "med" | "high"}
"""


def sha1_of(url: str) -> str:
    return hashlib.sha1(url.encode("utf-8")).hexdigest()


def load_exercise_meta() -> dict[int, dict]:
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        """
        SELECT
          e.id, e.name,
          (SELECT GROUP_CONCAT(mg.name, ', ')
             FROM exercise_muscles em
             JOIN muscle_groups mg ON mg.id = em.muscle_group_id
            WHERE em.exercise_id = e.id AND em.role = 'primary') AS primary_muscles,
          (SELECT GROUP_CONCAT(eq.name, ', ')
             FROM exercise_equipment ee
             JOIN equipment eq ON eq.id = ee.equipment_id
            WHERE ee.exercise_id = e.id) AS equipment
        FROM exercises e
        ORDER BY e.id
        """
    ).fetchall()
    con.close()
    return {
        r["id"]: {
            "id": r["id"],
            "name": r["name"],
            "primary_muscles": r["primary_muscles"] or "(unspecified)",
            "equipment": r["equipment"] or "(bodyweight)",
        }
        for r in rows
    }


def iter_tuples() -> list[dict]:
    """Each input row corresponds to one (suspect, candidate) tuple. We resolve
    to the actual cached WebP path. Skip tuples whose download failed.
    """
    out = []
    with IN_PATH.open() as f:
        for line in f:
            row = json.loads(line)
            url = (row.get("thumb_url") or row["image_url"]) if row["source"] == "wikimedia" else row["image_url"]
            if not url:
                continue
            sha = sha1_of(url)
            webp = THUMB_DIR / f"{sha}.webp"
            if not webp.exists():
                continue
            out.append({**row, "_fetch_url": url, "_sha": sha, "_webp": webp})
    return out


def build_request(tup: dict, meta: dict) -> Request:
    image_b64 = base64.standard_b64encode(tup["_webp"].read_bytes()).decode("ascii")
    user_text = (
        f"Exercise: {meta['name']}\n"
        f"Muscles: {meta['primary_muscles']}\n"
        f"Equipment: {meta['equipment']}\n\n"
        'Return JSON only: {"score": 1-5, "reason": "<=20 words", "confidence": "low|med|high"}'
    )
    custom_id = f"ex-{tup['exercise_id']}-{tup['_sha'][:12]}"
    return Request(
        custom_id=custom_id,
        params=MessageCreateParamsNonStreaming(
            model=MODEL,
            max_tokens=200,
            system=SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/webp",
                                "data": image_b64,
                            },
                        },
                        {"type": "text", "text": user_text},
                    ],
                }
            ],
        ),
    )


def estimate_cost(n: int) -> float:
    in_tok = 750 * n
    out_tok = 80 * n
    return (in_tok / 1_000_000) * 0.50 + (out_tok / 1_000_000) * 2.50


def submit_batch(client: anthropic.Anthropic, requests: list[Request]) -> str:
    print(f"Submitting batch of {len(requests)} requests...", flush=True)
    last_err = None
    for attempt in range(1, 6):
        try:
            batch = client.messages.batches.create(requests=requests)
            print(f"  batch_id: {batch.id}", flush=True)
            print(f"  status: {batch.processing_status}", flush=True)
            return batch.id
        except (
            anthropic.InternalServerError,
            anthropic.APIConnectionError,
            anthropic.APITimeoutError,
        ) as e:
            last_err = e
            wait = 5 * attempt
            print(f"  attempt {attempt} failed: {type(e).__name__}; retry in {wait}s", flush=True)
            time.sleep(wait)
    raise RuntimeError(f"batch submit failed after 5 attempts: {last_err}")


def poll_batch(client: anthropic.Anthropic, batch_id: str) -> None:
    last_status = None
    while True:
        b = client.messages.batches.retrieve(batch_id)
        if b.processing_status != last_status:
            print(
                f"[{datetime.now(UTC).isoformat(timespec='seconds')}] "
                f"status={b.processing_status} "
                f"processing={b.request_counts.processing} "
                f"succeeded={b.request_counts.succeeded} "
                f"errored={b.request_counts.errored} "
                f"canceled={b.request_counts.canceled} "
                f"expired={b.request_counts.expired}",
                flush=True,
            )
            last_status = b.processing_status
        if b.processing_status == "ended":
            return
        time.sleep(15)


def parse_result_text(text: str) -> dict | None:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        return None
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None


def write_results(
    client: anthropic.Anthropic,
    batch_ids: list[str],
    by_cid: dict[str, dict],
) -> int:
    n_written = 0
    n_errored = 0
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w") as f:
        for batch_id in batch_ids:
            for result in client.messages.batches.results(batch_id):
                cid = result.custom_id
                tup = by_cid.get(cid)
                if tup is None:
                    continue
                row = {
                    "exercise_id": tup["exercise_id"],
                    "url_sha1": tup["_sha"],
                    "image_url": tup["_fetch_url"],
                    "source": tup["source"],
                    "score": None,
                    "reason": None,
                    "confidence": None,
                    "scored_at": datetime.now(UTC).isoformat(timespec="seconds"),
                    "batch_id": batch_id,
                }
                if result.result.type == "succeeded":
                    msg = result.result.message
                    text_parts = [b.text for b in msg.content if b.type == "text"]
                    text = "".join(text_parts)
                    parsed = parse_result_text(text)
                    if parsed is None:
                        row["reason"] = f"parse_error: {text[:80]!r}"
                        n_errored += 1
                    else:
                        score = parsed.get("score")
                        try:
                            score = int(score)
                        except (TypeError, ValueError):
                            score = None
                        row["score"] = score
                        row["reason"] = (parsed.get("reason") or "")[:200]
                        row["confidence"] = parsed.get("confidence")
                else:
                    row["reason"] = f"batch_error:{result.result.type}"
                    n_errored += 1
                f.write(json.dumps(row) + "\n")
                n_written += 1
    print(f"Wrote {n_written} rows ({n_errored} errored) -> {OUT_PATH}", flush=True)
    return n_written


def main() -> int:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ANTHROPIC_API_KEY not set", file=sys.stderr)
        return 2

    meta_by_id = load_exercise_meta()
    tuples = iter_tuples()
    print(f"Candidate tuples with cached WebP: {len(tuples)}", flush=True)

    est = estimate_cost(len(tuples))
    print(f"Estimated batch cost: ${est:.3f} (cap ${COST_CAP_USD:.2f})", flush=True)
    if est > COST_CAP_USD:
        print(f"STOP: estimated ${est:.2f} exceeds cap ${COST_CAP_USD:.2f}", file=sys.stderr)
        return 3

    client = anthropic.Anthropic(api_key=api_key)

    by_cid: dict[str, dict] = {}
    chunks: list[list[Request]] = []
    cur: list[Request] = []
    for tup in tuples:
        if tup["exercise_id"] not in meta_by_id:
            continue
        req = build_request(tup, meta_by_id[tup["exercise_id"]])
        by_cid[req["custom_id"]] = tup
        cur.append(req)
        if len(cur) >= BATCH_CHUNK_SIZE:
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)
    print(f"Will submit {len(chunks)} batches of up to {BATCH_CHUNK_SIZE} requests", flush=True)

    batch_ids: list[str] = []
    for i, chunk in enumerate(chunks, 1):
        print(f"\n--- chunk {i}/{len(chunks)} ({len(chunk)} requests) ---", flush=True)
        batch_ids.append(submit_batch(client, chunk))

    for i, bid in enumerate(batch_ids, 1):
        print(f"\nPolling batch {i}/{len(batch_ids)} ({bid})", flush=True)
        poll_batch(client, bid)

    write_results(client, batch_ids, by_cid)

    # Histogram
    counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, None: 0}
    with OUT_PATH.open() as f:
        for line in f:
            counts[json.loads(line).get("score")] = counts.get(json.loads(line).get("score"), 0) + 1
    total = sum(counts.values())
    print(f"\nCandidate score histogram (n={total}):")
    for s in [5, 4, 3, 2, 1, None]:
        n = counts.get(s, 0)
        bar = "#" * int(60 * n / max(1, total))
        label = "err" if s is None else s
        print(f"  {label}: {n:4d}  {bar}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
