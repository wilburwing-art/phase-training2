# Exercise image bake-off

Decides two things before committing to ~1,150 assets (575 exercises x
start/end): which provider holds a figure consistent across a start/end pair,
and which art style survives the hardest movements.

## Run

```
export OPENROUTER_API_KEY=...        # same key Hermes uses, ~/.hermes/.env
uv run scripts/imagegen/run_bakeoff.py --dry-run     # jobs + first prompt, no calls
uv run scripts/imagegen/run_bakeoff.py               # 2 providers x 2 styles x 10 = 80 images
```

Output lands in `scripts/imagegen/out/run_1/` (gitignored). Re-running skips
pairs that already have both PNGs, so a partial run resumes. Open
`contact_sheet.html` to score, then `export scores.json`.

Narrow a run:

```
uv run scripts/imagegen/run_bakeoff.py --providers or-google --styles line_art --limit 3
```

## Providers

| name | model | route | state |
|---|---|---|---|
| `or-google` | `google/gemini-3-pro-image` | OpenRouter `/api/v1/images` | verified 2026-09-11 |
| `or-openai` | `openai/gpt-5.4-image-2` | OpenRouter `/api/v1/images` | verified 2026-09-11 |
| `openai` | `gpt-image-2.5-sunburst` | native, `OPENAI_API_KEY` | written to current docs, no key here |
| `google` | `gemini-3-pro-image` | native `/v1beta/interactions`, `GOOGLE_API_KEY` | written to current docs, no key here |

Model ids came from the vendors' docs on 2026-09-11 (`developers.openai.com/api/docs/models`,
`ai.google.dev/gemini-api/docs/image-generation`); the two the original
bake-off hardcoded (`gpt-image-2`, `generateContent`) no longer appear there.
OpenRouter's catalogue is behind OpenAI's own on image models, so `or-openai`
is one generation older than `openai`.

**Transparency.** Only native OpenAI has a real `background: transparent`
parameter. Asked for a transparent background in prose, both OpenRouter models
painted a Photoshop checkerboard into the pixels. Every route without the
parameter now asks for flat `#FFFFFF` instead (`prompts.py`,
`BACKGROUND_WHITE`); keying that out is a post-processing step for production
assets, and it does not change what the bake-off measures.

## Running against the catalogue

```
uv run scripts/imagegen/run_bakeoff.py --db db/coach.db --limit 10
```

`coach.db` keeps pattern, equipment and muscles in join tables; the loader
joins them and uses `exercises.slug` for filenames. An exercise with several
patterns uses its lowest-id one; the 106 with none get `DEFAULT_CAMERA`.
`CAMERA_BY_PATTERN` in `prompts.py` covers all 40 `movement_patterns.slug`
values.

Position text is read from **`db/source/exercise_positions.json`**, keyed by
slug:

```json
{
  "romanian-deadlift": {
    "start_position": "Standing tall, feet hip width, knees softly bent ...",
    "end_position": "Hips pushed back behind the heels, torso hinged ..."
  }
}
```

Only exercises present there with both fields are eligible; the loader refuses
to run without the file rather than fall back to `instructions`, because
without joint angles the model invents them. Writing those two paragraphs for
575 exercises is the real work of this project. They also become coaching cue
text in the app, and they give an asset-coverage test something to assert
against. Write them the way the ten in `prompts.py` are written: name the joint
angles, name what stays fixed, name what must not happen.

## Scoring

Score the pair, not the individual image. Three buttons:

- **form ok**: joint angles match the position text, grip is physically
  possible, equipment contacts the body correctly
- **style drift**: form is right but the two frames are not the same figure:
  limb proportions changed, camera moved, line weight or value shifted, figure
  rescaled in frame, accent moved to a different muscle
- **form wrong**: anything a coach would correct

Style drift decides the provider. Form errors can be prompted away; a model
that cannot hold a figure across two conditioned calls will never produce a
coherent library, and 80 images finds that out instead of 1,150.

## After the bake-off

The winning start frame for each style becomes the style reference. Add it as
a second reference image on every subsequent call so the whole library anchors
to one approved look rather than drifting run to run.
