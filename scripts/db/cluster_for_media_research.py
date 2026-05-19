#!/usr/bin/env python3
"""Cluster exercises missing image_url into 8 buckets for parallel research
agents, then write one input file per cluster under db/source/media/inputs/.

Each agent gets:
  - cluster name + source whitelist (in the agent prompt, not the file)
  - a JSONL of exercises with the context they need to research

Run:
    python3 scripts/db/cluster_for_media_research.py
"""
from __future__ import annotations
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "db" / "source" / "exercises.json"
OUT_DIR = REPO_ROOT / "db" / "source" / "media" / "inputs"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def classify(ex: dict) -> str:
    """Return one of 8 cluster names. Order matters — first hit wins."""
    name = ex["name"].lower()
    modality = (ex.get("modality") or "").lower()

    # 1. Climbing-specific: finger / hangboard / lock-off / campus etc.
    climbing_terms = [
        "hangboard", "lock-off", "lock off", "campus", "typewriter",
        "archer", "one-arm hang", "one arm hang", "front lever",
        "dead hang", "rice bucket", "finger flexor", "finger extensor",
        "theraputty", "open-hand", "open hand", "moonboard", "crimp",
        "via ferrata", "rappel",
    ]
    if any(t in name for t in climbing_terms):
        return "climbing-finger"

    # 2. PT / rehab / prehab modalities
    if modality in ("pt_rehab", "prehab"):
        return "pt-rehab"

    # 3. Mobility / flexibility / cool_down
    if modality in ("mobility", "flexibility", "cool_down"):
        return "mobility-stretch"
    if "stretch" in name or "cars" in name or " car " in name or name.endswith(" car"):
        return "mobility-stretch"

    # 4. Plyometric / power / speed / agility
    if modality in ("plyometric", "power", "speed", "agility"):
        return "plyo-power"

    # 5. Sport-specific drills
    if modality == "sport_drill":
        return "sport-drill"

    # 6. Breathing / endurance / recovery
    if modality in ("breathing", "endurance", "recovery"):
        return "conditioning-cardio"

    # 7. Strength variants
    if modality in ("strength",):
        return "strength-other"

    # 8. Catch-all: warm_up, balance, coordination, etc.
    return "warmup-balance-other"


def main() -> int:
    with SOURCE.open() as f:
        all_ex = json.load(f)

    # Only research exercises without an image_url; preserve free-exercise-db's
    # 136 (user said keep). They can still gain a video_url later via the
    # merger (it fills empty fields per row).
    needs_image = [e for e in all_ex if not e.get("image_url")]
    needs_video = [e for e in all_ex if not e.get("video_url")]
    print(f"Total exercises: {len(all_ex)}")
    print(f"  missing image_url: {len(needs_image)}")
    print(f"  missing video_url: {len(needs_video)}")

    # Cluster the union (any missing media). Per user: rows don't need
    # uniform media. Research agents fill what they can per row.
    todo_slugs = {e["slug"]: e for e in all_ex if not e.get("image_url") or not e.get("video_url")}
    todo = list(todo_slugs.values())
    print(f"  to research (missing image OR video): {len(todo)}")

    clusters: dict[str, list[dict]] = {}
    for ex in todo:
        bucket = classify(ex)
        clusters.setdefault(bucket, []).append(ex)

    print("\nCluster sizes:")
    for name in sorted(clusters):
        print(f"  {name:25s} {len(clusters[name]):4d}")

    # Cap each agent at MAX_PER_CLUSTER exercises; split alphabetically
    # within oversized clusters so each agent has a manageable load.
    MAX_PER_CLUSTER = 75
    final_clusters: dict[str, list[dict]] = {}
    for name in sorted(clusters):
        items = sorted(clusters[name], key=lambda e: e["name"].lower())
        if len(items) <= MAX_PER_CLUSTER:
            final_clusters[name] = items
            continue
        # Split into N chunks of <=MAX_PER_CLUSTER, suffixed -a -b -c ...
        n_chunks = (len(items) + MAX_PER_CLUSTER - 1) // MAX_PER_CLUSTER
        chunk_size = (len(items) + n_chunks - 1) // n_chunks
        for i in range(n_chunks):
            suffix = chr(ord("a") + i)
            final_clusters[f"{name}-{suffix}"] = items[i * chunk_size : (i + 1) * chunk_size]

    print(f"\nFinal agent buckets ({len(final_clusters)}):")
    for name in sorted(final_clusters):
        print(f"  {name:30s} {len(final_clusters[name]):4d}")

    # Write one JSONL per cluster with the context each agent needs.
    for name, items in final_clusters.items():
        out_path = OUT_DIR / f"{name}.jsonl"
        with out_path.open("w") as f:
            for ex in items:
                f.write(json.dumps({
                    "slug": ex["slug"],
                    "name": ex["name"],
                    "modality": ex.get("modality"),
                    "difficulty": ex.get("difficulty"),
                    "description": (ex.get("description") or "")[:200],
                    "instructions_excerpt": (ex.get("instructions") or "")[:300],
                    "has_image": bool(ex.get("image_url")),
                    "has_video": bool(ex.get("video_url")),
                }) + "\n")
        print(f"  wrote {out_path.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
