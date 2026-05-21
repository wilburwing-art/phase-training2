#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""For each suspect, choose the best candidate and classify the swap.

Reads:
  db/quality/vision_scores.jsonl     (current-image scores on the 525 bundled webps)
  db/quality/all_candidates.jsonl    (provenance for each (suspect, candidate) tuple)
  db/quality/candidate_scores.jsonl  (vision score per scored candidate)

Pick:
  For each suspect, group its scored candidates. Choose the highest score; break
  ties by source priority (fedb > wger > wikimedia), then by confidence
  (high > med > low).

  Track a claimed_urls set across all swaps so two suspects can NEVER end up
  pointing at the same replacement URL. (See L3 note: ex 390 + 498 currently
  share an identical thumb.) Process suspects in score-ascending order so the
  WORST current-image gets first pick of the URL pool.

Decision:
  auto     : candidate score >= 4 AND confidence == "high" AND candidate > current
  manual   : candidate score == 3 OR (>=4 but not high-confidence) OR
             (==5 but only 1 point better than current)
  skip     : no candidate scored >= 3

Output:
  db/quality/swap_decisions.jsonl — one row per of the 318 suspects, even skips.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
QDIR = REPO_ROOT / "db" / "quality"

VISION_PATH = QDIR / "vision_scores.jsonl"
CANDS_PATH = QDIR / "all_candidates.jsonl"
SCORES_PATH = QDIR / "candidate_scores.jsonl"
SUSPECTS_PATH = QDIR / "suspects.jsonl"
OUT_PATH = QDIR / "swap_decisions.jsonl"

SOURCE_PRIORITY = {"free-exercise-db": 0, "wger": 1, "wikimedia": 2}
CONF_PRIORITY = {"high": 0, "med": 1, "low": 2, None: 3}


def load_current_scores() -> dict[int, dict]:
    by_id: dict[int, dict] = {}
    with VISION_PATH.open() as f:
        for line in f:
            row = json.loads(line)
            by_id[row["exercise_id"]] = row
    return by_id


def load_candidate_meta() -> dict[tuple[int, str], dict]:
    """Keyed by (exercise_id, url_sha1) so we can attach provenance to scores."""
    out: dict[tuple[int, str], dict] = {}
    import hashlib

    with CANDS_PATH.open() as f:
        for line in f:
            row = json.loads(line)
            url = (row.get("thumb_url") or row["image_url"]) if row["source"] == "wikimedia" else row["image_url"]
            if not url:
                continue
            sha = hashlib.sha1(url.encode("utf-8")).hexdigest()
            out[(row["exercise_id"], sha)] = {**row, "_fetch_url": url}
    return out


def load_candidate_scores() -> dict[int, list[dict]]:
    out: dict[int, list[dict]] = defaultdict(list)
    with SCORES_PATH.open() as f:
        for line in f:
            row = json.loads(line)
            out[row["exercise_id"]].append(row)
    return out


def load_suspects() -> list[int]:
    ids = []
    with SUSPECTS_PATH.open() as f:
        for line in f:
            ids.append(json.loads(line)["exercise_id"])
    return ids


def sort_key(scored: dict, prov: dict | None) -> tuple:
    score = scored.get("score") or 0
    conf = scored.get("confidence")
    src = prov["source"] if prov else "zzz"
    # Higher score first → negate. Lower priority number first.
    return (
        -score,
        SOURCE_PRIORITY.get(src, 99),
        CONF_PRIORITY.get(conf, 99),
    )


def main() -> int:
    current = load_current_scores()
    cand_meta = load_candidate_meta()
    cand_scores = load_candidate_scores()
    suspects = load_suspects()

    # Build per-suspect ordered candidate list with provenance attached.
    enriched: dict[int, list[dict]] = {}
    for eid in suspects:
        scored = cand_scores.get(eid, [])
        rows = []
        for s in scored:
            prov = cand_meta.get((eid, s["url_sha1"]))
            if prov is None:
                continue
            rows.append({"score": s, "prov": prov})
        rows.sort(key=lambda r: sort_key(r["score"], r["prov"]))
        enriched[eid] = rows

    # Process worst current-image first so they get first pick of URLs.
    def current_score(eid: int) -> int:
        c = current.get(eid)
        return (c.get("score") if c else None) or 0

    suspects_sorted = sorted(suspects, key=current_score)

    claimed: set[str] = set()
    decisions: dict[int, dict] = {}

    n_auto = n_manual = n_skip = 0
    for eid in suspects_sorted:
        cur_score = current_score(eid)
        cands = enriched.get(eid, [])
        chosen = None
        for r in cands:
            url = r["prov"]["_fetch_url"]
            if url in claimed:
                continue
            chosen = r
            break

        # No candidates with scores
        if chosen is None or (chosen["score"].get("score") or 0) < 3:
            decisions[eid] = {
                "exercise_id": eid,
                "decision": "skip",
                "current_score": cur_score,
                "candidate_score": None,
                "candidate_confidence": None,
                "chosen_candidate": None,
                "reason": "no candidate with score>=3" if cands else "no candidates",
            }
            n_skip += 1
            continue

        cs = chosen["score"].get("score") or 0
        conf = chosen["score"].get("confidence")
        prov = chosen["prov"]
        url = prov["_fetch_url"]

        # Classify
        if cs >= 4 and conf == "high" and cs > cur_score:
            decision = "auto"
            n_auto += 1
            claimed.add(url)
        elif cs == 5 and cur_score == 4:
            # +1 over current = marginal; manual review
            decision = "manual"
            n_manual += 1
        elif cs == 3:
            decision = "manual"
            n_manual += 1
        elif cs >= 4 and conf != "high":
            decision = "manual"
            n_manual += 1
        elif cs >= 4 and cs <= cur_score:
            decision = "manual"
            n_manual += 1
        else:
            decision = "manual"
            n_manual += 1

        decisions[eid] = {
            "exercise_id": eid,
            "decision": decision,
            "current_score": cur_score,
            "candidate_score": cs,
            "candidate_confidence": conf,
            "chosen_candidate": {
                "url": url,
                "url_sha1": chosen["score"]["url_sha1"],
                "source": prov["source"],
                "license": prov["license"],
                "attribution": prov["attribution"],
                "image_url": prov["image_url"],
                "thumb_url": prov.get("thumb_url"),
                "reason": chosen["score"].get("reason"),
            },
            "reason": chosen["score"].get("reason"),
        }

    # Write in exercise_id order so the file diffs nicely.
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w") as f:
        for eid in sorted(decisions):
            f.write(json.dumps(decisions[eid], ensure_ascii=False) + "\n")

    print(f"Suspects: {len(suspects)}")
    print(f"  auto:   {n_auto}")
    print(f"  manual: {n_manual}")
    print(f"  skip:   {n_skip}")
    print(f"Wrote {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
