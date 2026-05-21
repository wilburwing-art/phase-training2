# Modality misclassification audit — 2026-05-20

Read-only sample-check of the `strength` (223), `power` (49), and `plyometric` (8) buckets in `db/coach.db`. The schema `CHECK` constraint defines the rubric:

```
modality IN ('strength','power','endurance','flexibility','mobility',
             'balance','coordination','agility','speed','plyometric',
             'sport_drill','pt_rehab','prehab','breathing','recovery',
             'warm_up','cool_down')
```

Method:
- Joined `modality` with `contraction_type`, `default_reps`, and name semantics.
- Flagged rows where the `modality` value disagrees with either the contraction-type tag, the duration unit (`sec`/`min` vs rep count), or the name's obvious intent.
- No edits made — this is a worklist, not a fix.

## Summary by bucket

| Bucket | Total | Flagged | Top class of issue |
| --- | --- | --- | --- |
| `strength` | 223 | 30 | Many isometric **holds** (`Hollow Hold`, `Side Plank`, `Wall Sit`, ...) priced in seconds, not reps — these are functionally endurance/core stability, not strength. |
| `power` | 49 | 14 | 14 rows have `contraction_type = 'plyometric'` (e.g. `Box Jump`, `Broad Jump`, `Depth Jump`, `Split Squat Jump`, `Tuck Jump`) yet sit under `modality='power'`. Plyometric is its own bucket — these should likely move. |
| `plyometric` | 8 | 2 | 2 of 8 are timed (`Jump Rope Double-Unders`, `Pogo Hops`) — duration-based plyo is debatable but inconsistent with the rest of the bucket which uses rep counts. |

## Flagged rows — `strength` bucket

These are tagged `strength` but the row data (contraction-type `isometric` plus reps measured in seconds) reads as core/postural endurance. Reviewer call: leave as `strength` (current convention treats positional holds as strength), reclassify a subset as `endurance`, or introduce an `isometric_strength` modality.

| id | name | contraction | default_reps |
| --- | --- | --- | --- |
| 2 | Hangboard Max Hang (20mm Edge) | isometric | 7-10 sec |
| 4 | Lock-Off Hold (90°) | isometric | 5-10 sec hold |
| 5 | One-Arm Hang (Assisted) | isometric | 5-10 sec per arm |
| 6 | Front Lever Progression (Tuck / Advanced Tuck) | isometric | 5-15 sec hold |
| 121 | Neck Bridge (Wrestler's Bridge) | isometric | 10-20 sec |
| 125 | Wall Sit | isometric | 30-60 sec |
| 131 | Hollow Hold | isometric | 15-30 sec |
| 132 | Side Plank | isometric | 20-45 sec per side |
| 220 | Superman Hold | isometric | 20-40 sec |
| 302 | Plate Pinch Hold | isometric | 20-45 sec per hand |
| 303 | Fat-Grip Dead Hang | isometric | 20-45 sec |
| 362 | Split-Stance Iso Hold | isometric | 20-30 sec per side |
| 380 | Bent-Arm Bar Hang | isometric | 15-30 sec |
| 486 | Hollow Body Hold | isometric | 20-45 sec |
| 487 | Arch Body Hold (Reverse Hollow) | isometric | 20-45 sec |
| 488 | Tuck L-Sit Progression | isometric | 10-20 sec |
| 490 | Handstand Wall Hold | isometric | 20-45 sec |
| 550 | Adductor Ball Squeeze (Supine) | isometric | 8-10 x 5 sec |
| 551 | Rider Wall Sit with Ball Squeeze | isometric | 30-60 sec |
| 561 | Archer Draw Isometric Hold | isometric | 15-30 sec per side |
| 562 | Scapular Retraction Hold | isometric | 6-8 x 10 sec |
| 600 | Wall Sit (Ski Tuck) | isometric | 30-90 sec |
| 607 | Split-Stance Isometric (Telemark Sit) | isometric | 30-60 sec per side |
| 619 | Tuck Hold (Skiing-Specific) | isometric | 30-60 sec |
| 638 | Dead Hang with Pack | isometric | 15-45 sec |
| 641 | Ice Tool Dead Hang (Tool-Grip Sim) | isometric | 15-45 sec |
| 732 | Trapeze Plank Hold | isometric | 30-45 sec |
| 824 | Ski-Jumping In-Run Tuck Isometric | isometric | 20-45 sec |
| 830 | Kung-Fu Horse-Stance Conditioning | isometric | 30-90 sec |
| 888 | Archery Draw-Hold Isometric | isometric | 10-20 sec per side |
| 974 | Front Plank | isometric | — |

Reviewer recommendation: keep `Hollow Hold`, `Side Plank`, `Wall Sit`, `Plank` family as `strength` (industry convention treats anti-extension/anti-rotation drills as strength). The sport-specific stance holds (`Ski Tuck`, `Telemark Sit`, `Horse-Stance Conditioning`, `Archery Draw-Hold`) are arguably `endurance` since they're sport-specific positional fatigue tolerance. Decide as a group, not row-by-row.

## Flagged rows — `power` bucket (likely `plyometric`)

These have `contraction_type='plyometric'` and rep ranges 2-8 — exactly the shape of the existing `plyometric` bucket. The split between `power` and `plyometric` looks arbitrary in the current data.

| id | name | contraction | default_reps |
| --- | --- | --- | --- |
| 47 | Campus Board Ladder (1-3-5) | plyometric | 3-5 reps |
| 48 | Explosive Pull-Up | plyometric | 3-5 |
| 49 | Box Jump | plyometric | 3-5 |
| 51 | Dynamic Lock-Off (Campus-Lite) | plyometric | 3-5 per side |
| 52 | Broad Jump | plyometric | 3-5 |
| 130 | Split Squat Jump | plyometric | 4-6 per side |
| 214 | Box Jump Over | plyometric | 10-15 |
| 230 | Squat Jump (Counter-Movement) | plyometric | 4-6 |
| 232 | Depth Jump | plyometric | 3-5 |
| 233 | Tuck Jump | plyometric | 6-8 |
| 329 | Lateral Bound to Stick | plyometric | 5-6 per side *(duplicate — see Agent B)* |
| 469 | Drop to Vertical Jump | plyometric | 4-6 |
| 473 | Lateral Bound to Stick | plyometric | 5-6 per side *(duplicate — see Agent B)* |
| 478 | Push-Up Plyo (Wrist Fall Prep) | plyometric | 5-8 |
| 492 | Muscle-Up Transition Drill | plyometric | 2-3 |
| 526 | Single-Leg Hop (Dance Tempo) | plyometric | 10-20 per side |
| 539 | Snatch Balance | plyometric | 3-5 |
| 540 | Hang Power Clean | plyometric | 2-3 |
| 670 | Board Pop-Up on Foam | plyometric | 8-10 |

Reviewer recommendation: most of these belong in `plyometric`. The Olympic-derivative rows (`Snatch Balance`, `Hang Power Clean`) are legitimately `power` — they're concentric triple-extensions with a barbell, not stretch-shortening-cycle jumps. The bar-and-bodyweight jumps (`Box Jump`, `Broad Jump`, `Depth Jump`, `Squat Jump`, `Split Squat Jump`, `Tuck Jump`, `Drop to Vertical Jump`, `Lateral Bound to Stick`, `Push-Up Plyo`, `Single-Leg Hop`) are textbook plyometric.

Keep in `power`: rows where `contraction_type='ballistic'` (med-ball throws, KB swings) or `concentric` (Oly lifts). Move to `plyometric`: the SSC-based bodyweight jumps listed above.

## Flagged rows — `plyometric` bucket

| id | name | contraction | default_reps |
| --- | --- | --- | --- |
| 609 | Jump Rope Double-Unders (Ski Foot-Quickness) | plyometric | 30-45 sec |
| 613 | Pogo Hops (Ski-Specific Ankle Stiffness) | plyometric | 20-30 sec |

Reviewer recommendation: leave both. Continuous low-amplitude plyo prescribed in seconds is standard (think pogo-hop sets in physio + ski-prep literature). They're consistent with the `contraction_type` tag.

## Suggested follow-up

1. Decide policy on `isometric` strength rows: stay `strength` (status quo) or split out sport-specific stance holds into `endurance`.
2. Move the 17 SSC bodyweight-jump rows from `power` to `plyometric` (Box Jump, Broad Jump, Depth Jump, Squat Jump, Split Squat Jump, Tuck Jump, Box Jump Over, Drop to Vertical Jump, Lateral Bound to Stick x2, Push-Up Plyo, Campus Board Ladder, Dynamic Lock-Off, Explosive Pull-Up, Single-Leg Hop, Board Pop-Up on Foam, Muscle-Up Transition Drill).
3. Keep `Hang Power Clean` and `Snatch Balance` in `power` despite the `plyometric` contraction tag — they're concentric Oly-lift derivatives.
4. Re-run this audit after any reclassification to confirm bucket counts make sense (target: power ~30, plyometric ~25).
