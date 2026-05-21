#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "anthropic>=0.45.0",
#   "sqlite-utils>=3.36",
#   "pillow>=10.0",
# ]
# ///
"""Layer 1 vision triage for PhaseTraining bundled exercise images.

Scores each of the 525 bundled WebPs at PhaseTraining/Resources/ExerciseImages/<id>.webp
using claude-haiku-4-5 via the Messages Batches API. Writes one JSONL row per image to
db/quality/vision_scores.jsonl.

Rubric (1-5):
  5  clearly the exercise, mid-motion, recognizable
  4  likely the exercise but minor issue (text overlay, weird angle)
  3  ambiguous - could be the exercise, could be similar
  2  wrong but related exercise (e.g. barbell row when asked dumbbell row)
  1  unrelated entirely (host face, B-roll, watermark-dominated)
"""
from __future__ import annotations

import base64
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
IMG_DIR = REPO_ROOT / "PhaseTraining" / "Resources" / "ExerciseImages"
OUT_PATH = REPO_ROOT / "db" / "quality" / "vision_scores.jsonl"
MODEL = "claude-haiku-4-5-20251001"
COST_CAP_USD = 2.00
# Anthropic Batches API allows up to 100k requests / 256MB body per batch, but Cloudflare
# in front returns 502 on multi-MB JSON POSTs in practice. Chunk to keep each batch body
# well under 2 MB (about 100 webps * ~14KB base64 each).
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


def load_exercises_with_bundled_images() -> list[dict]:
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
        WHERE e.image_url IS NOT NULL
        ORDER BY e.id
        """
    ).fetchall()
    con.close()

    out: list[dict] = []
    for r in rows:
        webp = IMG_DIR / f"{r['id']}.webp"
        if not webp.exists():
            continue
        out.append(
            {
                "id": r["id"],
                "name": r["name"],
                "primary_muscles": r["primary_muscles"] or "(unspecified)",
                "equipment": r["equipment"] or "(bodyweight)",
                "webp_path": webp,
            }
        )
    return out


def build_request(row: dict) -> Request:
    image_b64 = base64.standard_b64encode(row["webp_path"].read_bytes()).decode("ascii")
    user_text = (
        f"Exercise: {row['name']}\n"
        f"Muscles: {row['primary_muscles']}\n"
        f"Equipment: {row['equipment']}\n\n"
        'Return JSON only: {"score": 1-5, "reason": "<=20 words", "confidence": "low|med|high"}'
    )
    return Request(
        custom_id=f"ex-{row['id']}",
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


def estimate_cost(n_requests: int) -> float:
    # Haiku 4.5 batch pricing (50% off standard, as of 2026-05):
    #   Input:  $0.50 / 1M tokens (batch)
    #   Output: $2.50 / 1M tokens (batch)
    # Each request: small webp (~10KB -> ~600 image tokens at low-res) + ~150 text input tokens.
    # Estimate ~750 input tokens, ~80 output tokens per request.
    in_tok = 750 * n_requests
    out_tok = 80 * n_requests
    return (in_tok / 1_000_000) * 0.50 + (out_tok / 1_000_000) * 2.50


def submit_batch(client: anthropic.Anthropic, requests: list[Request]) -> str:
    print(f"Submitting batch of {len(requests)} requests...", flush=True)
    last_err: Exception | None = None
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
    """Tolerate stray prose / markdown fences."""
    text = text.strip()
    if text.startswith("```"):
        # strip ```json ... ```
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    # Find first { and last }
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
    by_id: dict[int, dict],
) -> int:
    n_written = 0
    n_errored = 0
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w") as f:
        for batch_id in batch_ids:
            for result in client.messages.batches.results(batch_id):
                cid = result.custom_id  # "ex-<id>"
                exercise_id = int(cid.split("-", 1)[1])
                meta = by_id[exercise_id]
                row = {
                    "exercise_id": exercise_id,
                    "name": meta["name"],
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


def histogram(path: Path) -> None:
    counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, None: 0}
    with path.open() as f:
        for line in f:
            row = json.loads(line)
            counts[row.get("score")] = counts.get(row.get("score"), 0) + 1
    total = sum(counts.values())
    print(f"\nScore histogram (n={total}):")
    for s in [5, 4, 3, 2, 1, None]:
        n = counts.get(s, 0)
        bar = "#" * int(60 * n / max(1, total))
        label = "err" if s is None else s
        print(f"  {label}: {n:4d}  {bar}")


def main() -> int:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ANTHROPIC_API_KEY not set", file=sys.stderr)
        return 2

    rows = load_exercises_with_bundled_images()
    print(f"{len(rows)} exercises with bundled webp", flush=True)

    est = estimate_cost(len(rows))
    print(f"Estimated batch cost: ${est:.3f} (cap ${COST_CAP_USD:.2f})", flush=True)
    if est > COST_CAP_USD:
        print(f"STOP: estimated cost ${est:.2f} exceeds cap ${COST_CAP_USD:.2f}", file=sys.stderr)
        return 3

    by_id = {r["id"]: r for r in rows}

    client = anthropic.Anthropic(api_key=api_key)

    # Chunk to keep each batch's request body small enough that Cloudflare doesn't 502.
    chunks: list[list[Request]] = []
    cur: list[Request] = []
    for r in rows:
        cur.append(build_request(r))
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

    # Poll each batch in order. Anthropic processes them concurrently server-side.
    for i, bid in enumerate(batch_ids, 1):
        print(f"\nPolling batch {i}/{len(batch_ids)} ({bid})", flush=True)
        poll_batch(client, bid)

    write_results(client, batch_ids, by_id)
    histogram(OUT_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
