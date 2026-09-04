# 2026-09-03 critique suite

Thirteen critiques, each a different lens. Run in order, one at a time, findings
written into this directory as they land. Nothing here is a code edit: this
cycle is report-only, and the output is a tiered backlog assembled at the end.

## Why these thirteen

Two heavy code-side sweeps are already spent (`audits/2026-06-01-app-audit.md`,
`audits/2026-08-23-backlog.md` with 213 findings from a 97-agent run) plus a
per-input-variable generator sweep (`docs/generator-audit.md`), a modality data
check, a tab-overflow IA pass, and the niche acquisition research. A third
part-by-part code critique would mostly re-find the 7 unchecked backlog items.
Every lens below is one those passes did not use.

## Budget discipline

The 2026-08-23 cycle notes two workflow attempts that died on usage limits
having landed zero edits. This run is deliberately cheap:

- Sequential. One critique at a time, no agent fan-out.
- Evidence by `grep -n` and `sed -n` ranges. No whole-file reads of the large
  Swift files.
- Findings written to disk as each critique closes, so a killed session loses
  at most one critique.
- Depth is stated per critique. Where a lens wanted a device, a build, or a
  simulator run that the budget did not cover, the doc says so rather than
  implying full coverage.

## Evidence rules

Carried from the prior cycles, both of which produced false positives that cost
real time:

1. Every finding cites `file:line` read this session, or it is not a finding.
2. An absence claim ("nothing handles X") needs the grep that failed, quoted.
3. Findings the evidence refutes go in a "refuted" section rather than being
   deleted, so the next pass does not re-chase them.
4. Severity is about user impact, not about how interesting the bug is.

## Status

| # | Critique | Lens | Status |
|---|---|---|---|
| 01 | Coaching quality of generated programs | output | CLOSED — 11 findings, 2 refuted |
| 02 | Niche expert teardown | output | CLOSED — 8 findings, 1 refuted |
| 03 | Safety and contraindication | output | CLOSED — 7 findings, 2 refuted |
| 04 | Coach red-team as a product | output | CLOSED — 6 findings, 3 refuted |
| 05 | Cold-install funnel | experience | CLOSED — 6 findings, 3 refuted |
| 06 | Lifecycle and recovery paths | experience | CLOSED — 6 findings, 3 refuted |
| 07 | Gym-context accessibility | experience | CLOSED — 6 findings, 1 refuted |
| 08 | Copy and voice | experience | CLOSED — 6 findings, 2 refuted |
| 09 | Paywall and gate | business | CLOSED — 7 findings, 2 refuted |
| 10 | Competitor teardown | business | CLOSED — 4 findings, 2 refuted |
| 11 | App Review and privacy label | business | CLOSED — 7 findings, 3 refuted |
| 12 | Backlog re-verification | meta | CLOSED — 4 findings, backlog largely holds |
| 13 | Test-suite critique | meta | CLOSED — 7 findings, 2 refuted |

## Output

`BACKLOG.md`, written 2026-09-03 after all 13 closed: severity-tiered,
one checkbox per item, each carrying the critique it came from.
