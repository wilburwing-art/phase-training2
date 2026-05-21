#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "open_clip_torch>=2.24",
#   "torch>=2.2",
#   "numpy>=1.26",
#   "scikit-learn>=1.4",
#   "sqlite-utils>=3.36",
#   "pillow>=10.0",
# ]
# ///
"""
Layer 3 of the image-quality plan: CLIP embedding cluster outliers.

For each bundled exercise WebP, compute a 512-dim image embedding with
open_clip ViT-B/32 (laion2b_s34b_b79k). Group by primary muscle bucket
(chest/back/shoulders/biceps/triceps/forearms/quads/hamstrings/glutes/calves/core)
and flag images whose cosine distance to the bucket centroid is > 1 standard
deviation above the bucket's mean distance.

For each outlier, also report the 3 closest exercises from *other* buckets —
the actionable signal: "this image clusters with chest exercises even though
it's tagged as a back exercise."

Outputs:
  db/quality/embeddings.npy     — (N, 512) float32, L2-normalized
  db/quality/id_index.json      — {"ids": [...], "image_paths": [...]}
  db/quality/cluster_outliers.jsonl — one row per outlier

Cached: re-running reuses embeddings.npy/id_index.json when image set unchanged.
"""
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
COACH_DB = REPO / "db" / "coach.db"
IMAGES_DIR = REPO / "PhaseTraining" / "Resources" / "ExerciseImages"
OUT_DIR = REPO / "db" / "quality"
EMB_PATH = OUT_DIR / "embeddings.npy"
ID_INDEX_PATH = OUT_DIR / "id_index.json"
OUTLIERS_PATH = OUT_DIR / "cluster_outliers.jsonl"

# Mirrors PhaseTraining/Data/ExerciseFilters.swift MuscleBucket.memberSlugs.
# Order matters: when an exercise has multiple primary muscles spanning
# buckets (e.g. hip thrust → glute-max + glutes), the first bucket wins.
BUCKETS: list[tuple[str, list[str]]] = [
    ("chest", ["chest", "pec-major-sternal", "pec-major-clav", "pec-minor", "serratus-anterior"]),
    ("back", ["back", "lats", "mid-traps", "rhomboids", "lower-traps", "upper-traps",
              "traps", "teres-major", "teres-minor", "levator-scapulae",
              "erector-thoracic", "erector-lumbar", "multifidus"]),
    ("shoulders", ["shoulders", "delt-anterior", "delt-lateral", "delt-posterior",
                   "rotator-cuff", "infraspinatus", "supraspinatus", "subscapularis"]),
    ("biceps", ["biceps", "brachialis", "brachioradialis"]),
    ("triceps", ["triceps"]),
    ("forearms", ["forearm-flexors", "forearm-extensors", "finger-flexors", "finger-extensors",
                  "grip-crush", "grip-pinch", "grip-support"]),
    ("quads", ["quadriceps", "vastus-medialis", "vastus-lateralis",
               "vastus-intermedius", "rectus-femoris", "sartorius"]),
    ("hamstrings", ["hamstrings", "biceps-femoris", "semimembranosus", "semitendinosus"]),
    ("glutes", ["glutes", "glute-max", "glute-med", "glute-min", "tfl", "piriformis", "hip-rotators"]),
    ("calves", ["calves", "gastrocnemius", "soleus", "tib-anterior",
                "peroneals", "intrinsic-foot"]),
    ("core", ["core", "rectus-abdominis", "external-obliques", "internal-obliques",
              "transverse-abdominis", "quadratus-lumborum", "pelvic-floor", "diaphragm",
              "hip-flexors", "iliopsoas"]),
]
SLUG_TO_BUCKET: dict[str, str] = {}
BUCKET_ORDER = [b for b, _ in BUCKETS]
BUCKET_RANK = {b: i for i, b in enumerate(BUCKET_ORDER)}
for bucket, slugs in BUCKETS:
    for slug in slugs:
        SLUG_TO_BUCKET.setdefault(slug, bucket)


def load_exercise_metadata() -> dict[int, dict]:
    """Map exercise id -> {name, bucket} for every exercise that has a webp on disk."""
    conn = sqlite3.connect(str(COACH_DB))
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT e.id AS id, e.name AS name, mg.slug AS slug
        FROM exercises e
        JOIN exercise_muscles em ON em.exercise_id = e.id
        JOIN muscle_groups mg ON mg.id = em.muscle_group_id
        WHERE em.role = 'primary'
        ORDER BY e.id, mg.slug
        """
    ).fetchall()
    conn.close()

    by_id: dict[int, dict] = {}
    for row in rows:
        exercise_id = row["id"]
        slug = row["slug"]
        bucket = SLUG_TO_BUCKET.get(slug)
        if bucket is None:
            continue
        existing = by_id.get(exercise_id)
        # Pick lowest BUCKET_RANK so chest beats back beats... (mirrors Swift order).
        if existing is None:
            by_id[exercise_id] = {"name": row["name"], "bucket": bucket}
        elif BUCKET_RANK[bucket] < BUCKET_RANK[existing["bucket"]]:
            existing["bucket"] = bucket
    return by_id


def gather_images(meta: dict[int, dict]) -> tuple[list[int], list[Path]]:
    """Walk ExerciseImages/ and return (ids, paths) for files we have metadata for."""
    ids: list[int] = []
    paths: list[Path] = []
    skipped_no_meta = 0
    for p in sorted(IMAGES_DIR.glob("*.webp"), key=lambda x: int(x.stem)):
        try:
            exercise_id = int(p.stem)
        except ValueError:
            continue
        if exercise_id not in meta:
            skipped_no_meta += 1
            continue
        ids.append(exercise_id)
        paths.append(p)
    if skipped_no_meta:
        print(f"  skipped {skipped_no_meta} webps with no primary-muscle bucket", file=sys.stderr)
    return ids, paths


def compute_embeddings(image_paths: list[Path]) -> np.ndarray:
    """Compute L2-normalized 512-dim embeddings for all images. CPU/MPS."""
    import torch
    import open_clip  # type: ignore

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"  loading open_clip ViT-B-32 laion2b_s34b_b79k on {device}...")
    model, _, preprocess = open_clip.create_model_and_transforms(
        "ViT-B-32", pretrained="laion2b_s34b_b79k"
    )
    model.eval()
    model.to(device)

    embs: list[np.ndarray] = []
    batch_size = 32
    total = len(image_paths)
    print(f"  embedding {total} images...")
    with torch.no_grad():
        for i in range(0, total, batch_size):
            chunk = image_paths[i : i + batch_size]
            tensors = []
            for p in chunk:
                img = Image.open(p).convert("RGB")
                tensors.append(preprocess(img))
            batch = torch.stack(tensors).to(device)
            feats = model.encode_image(batch)
            feats = feats / feats.norm(dim=-1, keepdim=True)
            embs.append(feats.cpu().numpy().astype(np.float32))
            done = min(i + batch_size, total)
            if done % 64 == 0 or done == total:
                print(f"    {done}/{total}")
    return np.concatenate(embs, axis=0)


def load_or_compute(image_paths: list[Path], ids: list[int]) -> np.ndarray:
    """Reuse cached embeddings only if the id list matches exactly."""
    if EMB_PATH.exists() and ID_INDEX_PATH.exists():
        try:
            cached = json.loads(ID_INDEX_PATH.read_text())
            if cached.get("ids") == ids:
                arr = np.load(EMB_PATH)
                if arr.shape[0] == len(ids):
                    print(f"  cache hit: {EMB_PATH} ({arr.shape})")
                    return arr
        except Exception as exc:
            print(f"  cache invalid ({exc}); recomputing", file=sys.stderr)

    arr = compute_embeddings(image_paths)
    np.save(EMB_PATH, arr)
    ID_INDEX_PATH.write_text(
        json.dumps(
            {"ids": ids, "image_paths": [str(p.relative_to(REPO)) for p in image_paths]},
            indent=2,
        )
    )
    print(f"  saved {EMB_PATH} (shape={arr.shape})")
    return arr


def find_outliers(
    ids: list[int],
    embeddings: np.ndarray,
    meta: dict[int, dict],
    z_threshold: float = 1.0,
) -> list[dict]:
    """Per-bucket centroid distance + z-score; flag z > threshold."""
    by_bucket: dict[str, list[int]] = {}
    for idx, exercise_id in enumerate(ids):
        by_bucket.setdefault(meta[exercise_id]["bucket"], []).append(idx)

    rows: list[dict] = []
    for bucket, idxs in by_bucket.items():
        if len(idxs) < 4:
            # Too small to derive a meaningful z-score.
            continue
        members = embeddings[idxs]  # already L2-normalized
        centroid = members.mean(axis=0)
        centroid = centroid / (np.linalg.norm(centroid) + 1e-12)
        # cosine distance = 1 - cosine similarity (vectors are unit norm)
        dists = 1.0 - members @ centroid
        mean_d = float(dists.mean())
        std_d = float(dists.std(ddof=0))
        if std_d < 1e-9:
            continue
        zs = (dists - mean_d) / std_d
        for local_i, idx in enumerate(idxs):
            z = float(zs[local_i])
            if z <= z_threshold:
                continue
            exercise_id = ids[idx]
            # Find nearest 3 exercises from a DIFFERENT bucket.
            sims = embeddings @ embeddings[idx]  # cosine similarity
            order = np.argsort(-sims)  # most similar first
            neighbors: list[dict] = []
            for cand_idx in order:
                if cand_idx == idx:
                    continue
                cand_id = ids[int(cand_idx)]
                cand_bucket = meta[cand_id]["bucket"]
                if cand_bucket == bucket:
                    continue
                neighbors.append(
                    {
                        "id": int(cand_id),
                        "name": meta[cand_id]["name"],
                        "bucket": cand_bucket,
                        "similarity": float(sims[int(cand_idx)]),
                    }
                )
                if len(neighbors) == 3:
                    break
            rows.append(
                {
                    "exercise_id": int(exercise_id),
                    "name": meta[exercise_id]["name"],
                    "bucket": bucket,
                    "distance_to_centroid": float(dists[local_i]),
                    "z_score": z,
                    "neighbors_in_other_bucket": neighbors,
                }
            )
    rows.sort(key=lambda r: (-r["z_score"], r["bucket"]))
    return rows


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if not COACH_DB.exists():
        print(f"missing {COACH_DB}", file=sys.stderr)
        return 1
    if not IMAGES_DIR.is_dir():
        print(f"missing {IMAGES_DIR}", file=sys.stderr)
        return 1

    print("loading exercise -> bucket metadata from coach.db...")
    meta = load_exercise_metadata()
    print(f"  {len(meta)} exercises with a primary bucket")

    print("gathering bundled images...")
    ids, paths = gather_images(meta)
    print(f"  {len(ids)} images with metadata")

    print("computing or loading CLIP embeddings...")
    embeddings = load_or_compute(paths, ids)

    # Bucket counts for the audit log.
    counts: dict[str, int] = {}
    for exercise_id in ids:
        b = meta[exercise_id]["bucket"]
        counts[b] = counts.get(b, 0) + 1
    print("bucket sizes:", ", ".join(f"{b}={counts[b]}" for b in BUCKET_ORDER if b in counts))

    print("finding outliers (z > 1.0)...")
    rows = find_outliers(ids, embeddings, meta)
    print(f"  flagged {len(rows)} outliers ({len(rows) / max(len(ids), 1):.1%} of images)")

    with OUTLIERS_PATH.open("w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")
    print(f"  wrote {OUTLIERS_PATH}")

    # Per-bucket outlier counts.
    per_bucket: dict[str, int] = {}
    for r in rows:
        per_bucket[r["bucket"]] = per_bucket.get(r["bucket"], 0) + 1
    print("outliers per bucket:")
    for b in BUCKET_ORDER:
        if b in counts:
            print(f"  {b}: {per_bucket.get(b, 0)} / {counts[b]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
