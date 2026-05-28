# Plan: Exercise Image Quality Pass (3 stacked layers)

## Context

Track A of the tile-system work landed 525 bundled WebPs at `PhaseTraining/Resources/ExerciseImages/<id>.webp` (99.1% `image_url` coverage in `coach.db`). The fast win was extracting YouTube `mqdefault` thumbnails from existing `video_url` rows — but YouTube thumbnails are *not* curated for exercise demonstration. Failure modes we expect to find:

- **Host-face frames**: thumbnail picks the YouTuber's face, not the exercise.
- **Watermark-dominated**: channel branding fills most of the 320×180 frame.
- **Wrong but related exercise**: thumb shows barbell row when the row name is "incline dumbbell row" (catastrophic for tutorial value).
- **B-roll / studio shot**: gym wide-angle, no athlete visible.
- **Stale/dead YouTube channels**: thumbnail is just the YouTube placeholder.

Three layers stacked, in order of cost-effectiveness. Each layer's output feeds the next.

## Done =

- Every exercise in the seeded onboarding plan (≈30 common lifts) scores 5/5 on Layer 1.
- Tail of all 525 bundled images: ≥90% score ≥4/5.
- Suspect set produced by L1 ∪ L3 has a swap candidate from L2 for ≥70% of entries.
- Bundle stays under 20 MB after refresh.
- `db/quality/audit_report.md` summarizes flagged + replaced + unresolved.

## Out of scope

- Image *aesthetic* curation (lighting, composition). Only "is this the named exercise."
- Video URL quality (handle separately).
- Re-sourcing for the 26 long-tail exercises with no current image (different problem).
- Hand-shooting custom photos (cost prohibitive).

---

## Layer 1 — AI-vision triage (does this depict the named exercise?)

### Goal
Score each of the 525 bundled images 1-5 on "does this image show this exercise being performed?" Flag scores ≤3 for replacement.

### Inputs
- `PhaseTraining/Resources/ExerciseImages/<id>.webp` × 525
- `coach.db`: `id`, `name`, `primary_muscles`, `equipment`, `instructions` per exercise

### Implementation

New script: `scripts/quality/vision_triage.py` (uv-run, PEP 723 deps: `anthropic`, `sqlite-utils`, `pillow`).

- Model: `claude-haiku-4-5-20251001` via the **Messages Batches API** (50% cost discount, non-urgent).
- One batch of 525 requests. Each request:
  - System prompt: defines the 1-5 rubric (5=clearly this exercise mid-motion, 4=likely with minor issue, 3=ambiguous, 2=wrong but related exercise, 1=unrelated/host-face/watermark).
  - User content: image + `Exercise name: <name>\nMuscles: <primary_muscles>\nEquipment: <equipment>\n\nReturn JSON: {score: 1-5, brief_reason: <≤20 words>, confidence: low|med|high}`.
- Output: `db/quality/vision_scores.jsonl`. One row per image: `{exercise_id, name, score, reason, confidence, batch_id, scored_at}`.
- Cost estimate: 525 images × ~$0.0005 (Haiku batch w/ small text + image) ≈ **$0.30**.

### Verify
- Spot-check 20 random rows manually — does the score match human judgment?
- Histogram of scores: a healthy distribution skews to 4-5 with a tail at 1-2. If everything is 5, the rubric isn't biting.

### Team shape: **1 agent**
Batch API is single-threaded by nature. One agent runs the script and writes the JSONL.

---

## Layer 2 — Cross-reference + swap candidates

### Goal
For every flagged image from L1 (and later L3), find a higher-quality replacement from an open-source catalog.

### Inputs
- Suspect set: union of L1 scores ≤3 and L3 outliers (run L1 first, L3 in parallel; merge after both done).
- Per suspect: exercise name, primary_muscles, equipment.

### Sources (priority order)

| Source | License | Coverage | Match strategy |
|---|---|---|---|
| **free-exercise-db** (`yuhonas/free-exercise-db`) | MIT | 873 exercises, 2 photos each | Fuzzy name match (`thefuzz` ratio ≥80). Already in repo's lineage. |
| **wger.de** API (`/api/v2/exerciseimage/`) | CC-BY-SA | ~400 exercises with photos | API search by name, filter `license_id in [CC-BY, CC-BY-SA]`. |
| **Wikimedia Commons** | CC-BY-SA, public domain | thousands tagged "Exercise" | Commons API search + license filter. |
| **ExRx.net** | proprietary, scrape carefully | ~1800 exercises with thumbs | Already used in earlier fanout. ToS allows hotlinking for non-commercial; this is borderline — check before re-using. **Lowest priority for that reason.** |

### Implementation

New scripts (one per source) under `scripts/quality/sources/`:
- `match_free_exercise_db.py`
- `match_wger.py`
- `match_wikimedia.py`
- `match_exrx.py` (gated behind a `--allow-exrx` flag; default off pending license review)

Each script:
- Reads suspect set from `db/quality/suspects.jsonl`.
- For each suspect, queries its source, returns top-3 candidate URLs with confidence scores.
- Writes to `db/quality/candidates_<source>.jsonl`.

Merger: `scripts/quality/merge_candidates.py`:
- For each suspect, picks the best candidate across sources by (a) source priority, (b) match confidence, (c) license cleanliness.
- Outputs `db/quality/swap_candidates.jsonl`: one row per suspect with `{exercise_id, current_url, new_url, source, license, attribution, confidence}`.

### Verify
- Coverage: how many suspects got a candidate? Aim for ≥70%.
- License check: every candidate row has explicit `license` field set.
- Self-test: run Layer 1's vision script on a sample of candidates *before* swapping. New candidate should score ≥4.

### Team shape: **4 parallel agents + 1 merger**
- 4 source-specific agents run in parallel (no dependencies between them).
- 1 merger runs after all 4 finish.

---

## Layer 3 — CLIP embedding cluster outliers

### Goal
Catch the "image is of an exercise, just not THIS exercise" cases that Layer 1 might rubberstamp (it sees a person lifting and scores high; doesn't notice it's the wrong lift).

### Inputs
- All 525 bundled WebPs.
- Bucket assignment per exercise (`PhaseTraining/Data/ExerciseFilters.swift` → 11 buckets).

### Implementation

New script: `scripts/quality/clip_outliers.py` (uv-run, PEP 723 deps: `open_clip_torch`, `torch`, `numpy`, `scikit-learn`).

- Model: `open_clip` ViT-B/32 `laion2b_s34b_b79k` (open, ~150 MB, runs on CPU in ~3 min for 525 images on Apple Silicon).
- For each image: compute 512-dim image embedding. Cache to `db/quality/embeddings.npy` (re-run is fast).
- Group by primary muscle bucket. For each group:
  - Compute centroid embedding.
  - Compute cosine distance of every member to centroid.
  - Flag top 15% by distance (z-score > 1.0) as outliers.
- Output: `db/quality/cluster_outliers.jsonl`: `{exercise_id, name, bucket, distance_to_centroid, z_score}`.

### Verify
- Manually inspect 5 flagged outliers from the chest bucket and 5 from the back bucket. Are they obviously off-cluster (e.g., a face close-up in a bucket otherwise full of full-body shots)?
- Tune the z-score threshold if signal/noise is bad.

### Team shape: **1 agent**
Local Python compute, no API parallelism needed. Single-threaded, ~5 min wallclock.

---

## Apply swap candidates

### Goal
Merge suspect set, apply approved swap candidates, rebuild bundle.

### Inputs
- `db/quality/swap_candidates.jsonl` from Layer 2.
- `db/quality/vision_scores.jsonl` from Layer 1 (to auto-accept high-confidence swaps).

### Implementation

New script: `scripts/quality/apply_swaps.py`:
1. For each candidate: if Layer 1 scored the *candidate* ≥4 with `confidence: high`, auto-accept. Otherwise add to manual-review queue.
2. Auto-accepted swaps: update `db/source/exercises.json`, set new `image_url`, `image_source`, `image_license`, `image_attribution`.
3. Rebuild `coach.db` via `scripts/db/build_db.py`.
4. Re-run `scripts/download_exercise_images.py` (idempotent — only fetches the newly-changed rows).
5. Re-run Layer 1 vision triage on the changed set only. New scores should be ≥4.

Manual-review queue: write `db/quality/manual_review.md` listing each candidate with current and proposed image side-by-side (Markdown image syntax pointing at local files). User scans the file in Markdown preview, deletes lines for rejections, runs `apply_swaps.py --apply-manual db/quality/manual_review.md`.

### Verify
- `sqlite3 coach.db "SELECT COUNT(*) FROM exercises WHERE image_url IS NOT NULL"` unchanged (no regressions in coverage).
- `du -sh PhaseTraining/Resources/ExerciseImages/` ≤ 20 MB.
- `xcodebuild ... build` clean.
- Library screen screenshot via XcodeBuildMCP — visual spot-check of 5 previously-flagged exercises.

### Team shape: **1 agent**

---

## Agent team execution plan

### Phase 1 (parallel) — diagnostic layers
Spawn 2 agents in parallel:
- **`vision-triage`** (owns Layer 1)
- **`clip-outliers`** (owns Layer 3)

Both depend only on the bundled images + `coach.db`. No write conflicts (each writes to its own `db/quality/<name>.jsonl`).

### Phase 2 (gated on Phase 1) — sourcing
Once L1's `vision_scores.jsonl` exists and L3's `cluster_outliers.jsonl` exists, a coordinator merges them into `db/quality/suspects.jsonl`. Then spawn 4 agents in parallel:
- **`match-fedb`** (free-exercise-db)
- **`match-wger`** (wger.de)
- **`match-wikimedia`** (Wikimedia Commons)
- **`match-exrx`** (gated, default skip)

Each writes to `db/quality/candidates_<source>.jsonl`. No conflicts.

### Phase 3 (gated on Phase 2) — synthesize and apply
One synthesizer agent:
- Runs `merge_candidates.py` → `swap_candidates.jsonl`
- Runs `apply_swaps.py` (auto-accepts safe swaps, writes `manual_review.md` for the rest)
- Rebuilds DB + WebPs
- Re-runs Layer 1 on changed set
- Writes `db/quality/audit_report.md` summary

### Critical constraints

- **Shared working tree**: scoped `git add` per agent (per `scoped-commit-with-dirty-tree` skill). The four Phase-2 agents write *disjoint* JSONL files, so commits don't conflict — but `git status` will show changes from siblings. Use explicit paths.
- **Parallel builds avoidance**: Only Phase 3 needs to build; Phases 1-2 are data-only. Build conflicts not a concern this round.
- **API cost ceiling**: cap total Anthropic spend at $5 (Layer 1 ~$0.30, Layer 1 re-run on changed set ~$0.05, candidate pre-screening in Layer 2 ~$1). Bail if exceeded.
- **No self-attribution** in commit messages.
- **License hygiene**: every swap candidate must record `image_source`, `image_license`, `image_attribution` in `exercises.json`. Build a sanity-check that fails CI if a row has `image_url` set but no license metadata.

### Final commit shape

Two commits expected:
1. **`image-quality: vision triage + cluster outliers + source candidates`** — adds `scripts/quality/`, `db/quality/*.jsonl`, `db/quality/manual_review.md`. No app behavior change.
2. **`image-quality: swap N images with higher-confidence candidates`** — modifies `db/source/exercises.json`, `coach.db`, `PhaseTraining/Resources/ExerciseImages/<id>.webp` × N. App behavior changes only in which photo loads.

---

## What this plan does NOT do

- **Replace the long-tail 26 with no current image.** That's the residue of Track A's fanout; needs a different sourcing pass (likely a Track A v2, not a quality pass).
- **Validate exercise *form*.** "Is this person doing the lift correctly" is an LLM-vision rabbit hole — skip.
- **Curate aesthetics.** Sharpness, lighting, composition. Out of scope.
- **Touch video URLs.** Quality pass is stills only. Videos are a separate problem.
