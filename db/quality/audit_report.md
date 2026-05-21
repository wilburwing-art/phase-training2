# Image quality — Phase 3 audit report

## Summary

- Suspects from L1/L3 pipeline: **318**
- Auto-accepted swaps: **62**
- Queued for manual review: **15**
- Skipped (no usable candidate): **241**
- Bundle size after rebuild: **5.75 MB** (525 webps)

## Score histograms — the 318 suspects

```
Before (L1 scores on current images):
  5:   14  #
  4:   10  #
  3:   20  ##
  2:   62  #######
  1:  212  ##########################
  err:    0  

After (post-swap re-score for auto-swapped, original for the rest):
  5:   42  #####
  4:   18  ##
  3:   17  ##
  2:   60  #######
  1:  181  ######################
  err:    0  
```

## Score histograms — all bundled webps (525)

```
Before:
  5:  150  ###########
  4:   81  ######
  3:   20  #
  2:   62  ####
  1:  212  ################
  err:    0  

After:
  5:  178  #############
  4:   89  ######
  3:   17  #
  2:   60  ####
  1:  181  #############
  err:    0  
```

## Per-swap score change (auto-swapped only)

```
  +4:   22  ############################################
  +3:    9  ##################
  +2:    4  ########
  +1:   11  ######################
  +0:   10  ####################
  -1:    6  ############
```

## Source breakdown — new images

- **free-exercise-db**: 46
- **wger**: 12
- **wikimedia**: 4

## License breakdown — new images

- **MIT**: 46
- **CC-BY-SA 4**: 9
- **CC-BY-SA 3**: 3
- **CC-BY-SA-3.0**: 2
- **PUBLIC-DOMAIN**: 1
- **CC-BY-SA-4.0**: 1

## Files

- Auto-accept audit: `db/quality/swaps_applied.jsonl`
- All swap decisions: `db/quality/swap_decisions.jsonl`
- Candidate scores: `db/quality/candidate_scores.jsonl`
- Manual-review queue: `manual_review.md` (root)
- Post-swap re-scores: `db/quality/post_swap_scores.jsonl`
