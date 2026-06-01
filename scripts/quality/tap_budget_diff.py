#!/usr/bin/env python3
"""Diff tap-budget actuals from a test log against the committed baseline.

The TapBudgetTests print one machine-readable line per flow:

    TAP-BUDGET-JSON {"flow":"log-workout-full","actual":10,"reference":10}

This script greps those out of an xcodebuild log (path as argv[1], or stdin),
keeps the LAST occurrence per flow (so test retries don't double-count), and
compares each flow's `actual` against PhaseTrainingUITests/tap-budget-baseline.json.

It is NON-GATING by design (honors the 2026-05-31 track-don't-gate decision):
it always exits 0. Its job is visibility — it prints a markdown table and, when
run under GitHub Actions, appends that table to the step summary so a flow whose
tap count moved shows up in the PR run instead of dying in an artifact bundle.

To accept a new cost as the baseline, edit tap-budget-baseline.json and commit.
"""

import json
import os
import re
import sys

# Non-greedy so trailing braces elsewhere on the same physical log line can't
# over-extend the capture (the marker JSON has no nested objects).
MARKER = re.compile(r"TAP-BUDGET-JSON\s+(\{.*?\})")
BASELINE_PATH = os.path.join(
    os.path.dirname(__file__), "..", "..",
    "PhaseTrainingUITests", "tap-budget-baseline.json",
)


def parse_actuals(text):
    """flow -> {'actual': int, 'reference': int}, last occurrence wins."""
    out = {}
    for line in text.splitlines():
        m = MARKER.search(line)
        if not m:
            continue
        try:
            rec = json.loads(m.group(1))
        except json.JSONDecodeError:
            continue
        flow = rec.get("flow")
        if flow:
            out[flow] = {"actual": rec.get("actual"), "reference": rec.get("reference")}
    return out


def load_baseline():
    try:
        with open(BASELINE_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def main():
    # NON-GATING contract: this must never raise / exit non-zero, even on a
    # missing or unreadable log. The CI step runs `if: always()`, so a crash
    # here would red an otherwise-passing job.
    if len(sys.argv) > 1:
        try:
            with open(sys.argv[1], errors="replace") as f:
                text = f.read()
        except OSError as e:
            print(f"tap-budget: could not read log '{sys.argv[1]}': {e} "
                  "(non-gating, continuing)")
            return 0
    else:
        text = sys.stdin.read()

    actuals = parse_actuals(text)
    baseline = load_baseline()

    if not actuals:
        print("tap-budget: no TAP-BUDGET-JSON markers found in log — did the "
              "TapBudget tests run? (non-gating, continuing)")
        return 0

    rows = []
    drift = []       # actual moved vs baseline, or a brand-new flow
    missing = []     # in baseline but no marker emitted (test removed / crashed)
    errored = []     # baseline value isn't a number (bad hand-edit)
    divergent = []   # actual==baseline but the in-code reference disagrees
    for flow in sorted(set(actuals) | set(baseline)):
        a = actuals.get(flow, {})
        actual = a.get("actual")
        ref = a.get("reference")
        base = baseline.get(flow)
        if actual is None:
            status, delta = "MISSING (in baseline, not run)", ""
            missing.append(flow)
        elif base is None:
            status, delta = "NEW (no baseline)", ""
            drift.append(flow)
        elif not isinstance(actual, int) or not isinstance(base, int):
            # bool is an int subclass; that's fine. Strings/floats-as-strings
            # from a bad baseline edit would otherwise crash `actual - base`.
            status, delta = "BASELINE ERROR (non-numeric)", ""
            errored.append(flow)
        elif actual == base:
            # The expected count lives in two files (the test's in-code
            # `reference` and this baseline). Catch them silently diverging.
            if isinstance(ref, int) and ref != base:
                status, delta = f"ref≠baseline ({ref} vs {base})", "0"
                divergent.append(flow)
            else:
                status, delta = "unchanged", "0"
        else:
            d = actual - base
            status = "REGRESSED" if d > 0 else "improved"
            delta = f"{d:+d}"
            drift.append(flow)
        rows.append((flow, base, actual, ref, status, delta))

    # Human/markdown table.
    header = "| flow | baseline | actual | reference | status | Δ |"
    sep = "|---|---|---|---|---|---|"
    lines = [header, sep]
    for flow, base, actual, ref, status, delta in rows:
        lines.append(
            f"| {flow} | {base if base is not None else '—'} | "
            f"{actual if actual is not None else '—'} | "
            f"{ref if ref is not None else '—'} | {status} | {delta} |"
        )
    table = "\n".join(lines)

    footer = []
    if drift:
        footer.append(f"**Drift:** {', '.join(drift)} — update "
                      "tap-budget-baseline.json to accept, or investigate.")
    if missing:
        footer.append(f"**Not run (in baseline, no marker):** {', '.join(missing)} "
                      "— a tracked flow stopped emitting its marker; investigate.")
    if errored:
        footer.append(f"**Baseline error (non-numeric):** {', '.join(errored)} "
                      "— fix the value in tap-budget-baseline.json.")
    if divergent:
        footer.append(f"**Reference ≠ baseline:** {', '.join(divergent)} — the "
                      "test's in-code reference and tap-budget-baseline.json "
                      "disagree; reconcile them.")
    if not footer:
        footer.append("All flows match baseline.")

    print("## Tap budget\n")
    print(table)
    for line in footer:
        print("\n" + line)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        try:
            with open(summary, "a") as f:
                f.write("## Tap budget\n\n" + table + "\n")
                for line in footer:
                    f.write("\n" + line + "\n")
        except OSError:
            pass  # step summary is best-effort; never fail the step over it

    return 0


if __name__ == "__main__":
    sys.exit(main())
