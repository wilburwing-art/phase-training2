#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "anthropic>=0.45.0",
#   "pillow>=10.0",
# ]
# ///
"""Re-run L1 vision on just the auto-swapped exercises.

Reads:
  db/quality/swaps_applied.jsonl  (the audit emitted by apply_swaps.py)
  PhaseTraining/Resources/ExerciseImages/<id>.webp   (refreshed by Track A)

Writes:
  db/quality/post_swap_scores.jsonl

Uses the same Batches API + rubric as vision_triage.py.
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
APPLIED_PATH = REPO_ROOT / "db" / "quality" / "swaps_applied.jsonl"
OUT_PATH = REPO_ROOT / "db" / "quality" / "post_swap_scores.jsonl"
MODEL = "claude-haiku-4-5-20251001"
BATCH_CHUNK_SIZE = 100

SYSTEM_PROMPT = """You are an expert lifting coach scoring exercise demonstration images.

You will be shown ONE image and told the name of an exercise. Your job is to judge whether the image depicts that named exercise being performed.

Rubric (output an integer 1-5):
  5 = clearly the exercise, mid-motion, recognizable
  4 = likely the exercise but a minor issue (text overlay, awkward angle, partial frame)
  3 = ambiguous — could be the exercise, could be a similar movement
  2 = wrong but related exercise (e.g. barbell row when asked dumbbell row; squat when asked lunge)
  1 = unrelated entirely (host face close-up, B-roll/gym wide-shot with no athlete, watermark-dominated, YouTube placeholder)

Respond with JSON only — no prose, no markdown fences. Schema:
{"score": <1-5>, "reason": "<<=20 words>", "confidence": "low" | "med" | "high"}
"""


def load_swapped_ids() -> list[int]:
    ids: list[int] = []
    with APPLIED_PATH.open() as f:
        for line in f:
            ids.append(json.loads(line)["exercise_id"])
    return ids


def load_meta(ids: list[int]) -> dict[int, dict]:
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    placeholders = ",".join("?" * len(ids))
    rows = con.execute(
        f"""
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
        WHERE e.id IN ({placeholders})
        """,
        ids,
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


def build_request(meta: dict, webp: Path) -> Request:
    image_b64 = base64.standard_b64encode(webp.read_bytes()).decode("ascii")
    user_text = (
        f"Exercise: {meta['name']}\n"
        f"Muscles: {meta['primary_muscles']}\n"
        f"Equipment: {meta['equipment']}\n\n"
        'Return JSON only: {"score": 1-5, "reason": "<=20 words", "confidence": "low|med|high"}'
    )
    return Request(
        custom_id=f"ex-{meta['id']}",
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


def submit_batch(client: anthropic.Anthropic, requests: list[Request]) -> str:
    last_err = None
    for attempt in range(1, 6):
        try:
            batch = client.messages.batches.create(requests=requests)
            return batch.id
        except (
            anthropic.InternalServerError,
            anthropic.APIConnectionError,
            anthropic.APITimeoutError,
        ) as e:
            last_err = e
            time.sleep(5 * attempt)
    raise RuntimeError(f"batch submit failed: {last_err}")


def poll_batch(client: anthropic.Anthropic, batch_id: str) -> None:
    last = None
    while True:
        b = client.messages.batches.retrieve(batch_id)
        if b.processing_status != last:
            print(f"[{datetime.now(UTC).isoformat(timespec='seconds')}] {batch_id} {b.processing_status}", flush=True)
            last = b.processing_status
        if b.processing_status == "ended":
            return
        time.sleep(15)


def main() -> int:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ANTHROPIC_API_KEY not set", file=sys.stderr)
        return 2

    ids = load_swapped_ids()
    print(f"Swapped exercises to verify: {len(ids)}")
    if not ids:
        OUT_PATH.write_text("")
        return 0

    meta = load_meta(ids)

    # Only score ones whose webp exists post-rebuild.
    requests = []
    by_cid: dict[str, dict] = {}
    for eid in ids:
        webp = IMG_DIR / f"{eid}.webp"
        if not webp.exists():
            print(f"  miss: {eid}.webp does not exist post-rebuild")
            continue
        m = meta.get(eid)
        if m is None:
            continue
        req = build_request(m, webp)
        requests.append(req)
        by_cid[req["custom_id"]] = m

    if not requests:
        OUT_PATH.write_text("")
        return 0

    client = anthropic.Anthropic(api_key=api_key)

    chunks: list[list[Request]] = []
    for i in range(0, len(requests), BATCH_CHUNK_SIZE):
        chunks.append(requests[i : i + BATCH_CHUNK_SIZE])

    batch_ids: list[str] = []
    for i, chunk in enumerate(chunks, 1):
        print(f"submit chunk {i}/{len(chunks)} ({len(chunk)} reqs)", flush=True)
        batch_ids.append(submit_batch(client, chunk))

    for bid in batch_ids:
        poll_batch(client, bid)

    n_written = 0
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w") as f:
        for bid in batch_ids:
            for result in client.messages.batches.results(bid):
                cid = result.custom_id
                meta_row = by_cid.get(cid)
                if meta_row is None:
                    continue
                row = {
                    "exercise_id": meta_row["id"],
                    "name": meta_row["name"],
                    "score": None,
                    "reason": None,
                    "confidence": None,
                    "scored_at": datetime.now(UTC).isoformat(timespec="seconds"),
                    "batch_id": bid,
                }
                if result.result.type == "succeeded":
                    msg = result.result.message
                    text = "".join(b.text for b in msg.content if b.type == "text")
                    parsed = parse_result_text(text)
                    if parsed:
                        try:
                            row["score"] = int(parsed.get("score"))
                        except (TypeError, ValueError):
                            row["score"] = None
                        row["reason"] = (parsed.get("reason") or "")[:200]
                        row["confidence"] = parsed.get("confidence")
                f.write(json.dumps(row) + "\n")
                n_written += 1
    print(f"Wrote {n_written} -> {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
