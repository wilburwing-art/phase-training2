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

MARKER = re.compile(r"TAP-BUDGET-JSON\s+(\{.*\})")
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
    if len(sys.argv) > 1:
        with open(sys.argv[1], errors="replace") as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    actuals = parse_actuals(text)
    baseline = load_baseline()

    if not actuals:
        print("tap-budget: no TAP-BUDGET-JSON markers found in log — did the "
              "TapBudget tests run? (non-gating, continuing)")
        return 0

    rows = []
    drift = []
    for flow in sorted(set(actuals) | set(baseline)):
        a = actuals.get(flow, {})
        actual = a.get("actual")
        ref = a.get("reference")
        base = baseline.get(flow)
        if actual is None:
            status, delta = "MISSING (in baseline, not run)", ""
        elif base is None:
            status, delta = "NEW (no baseline)", ""
            drift.append(flow)
        elif actual == base:
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

    print("## Tap budget\n")
    print(table)
    if drift:
        print(f"\n**Drift:** {', '.join(drift)} — "
              "update tap-budget-baseline.json to accept, or investigate.")
    else:
        print("\nAll flows match baseline.")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("## Tap budget\n\n")
            f.write(table + "\n")
            if drift:
                f.write(f"\n**Drift:** {', '.join(drift)} — update "
                        "tap-budget-baseline.json to accept, or investigate.\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
