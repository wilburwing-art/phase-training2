#!/usr/bin/env python3
"""Diff tap-budget actuals from a test log against the committed baseline.

The TapBudgetTests print one machine-readable line per flow:

    TAP-BUDGET-JSON {"flow":"log-workout-full","actual":10,"reference":10,
                     "seconds":41.2,"swipes":2,"max_gap_s":12.4}

`seconds`/`swipes` are optional (older markers omit them); `max_gap_s` is the
longest single inter-tap wait the counter observed.

The baseline (PhaseTrainingUITests/tap-budget-baseline.json) maps flow ->
either a plain int (taps only, legacy) or {"taps": int, "seconds": float}.

Gating contract (revised 2026-09-05 from the original always-exit-0 design):
  - Exit 1 (harness broken, should fail CI) when:
      * a baseline flow emitted no marker while OTHER flows did (a tracked
        flow stopped being tracked — silent coverage loss),
      * the TapBudget tests ran in the log but emitted NO markers at all
        (tracking calls removed — the test job may still pass),
      * the baseline file exists but is corrupt / non-numeric.
  - Exit 0 (visibility only) when:
      * taps != baseline (product drift — accept by editing the baseline),
      * seconds over the baseline time budget (advisory; sim timing is noisy),
      * NO markers at all (the whole suite likely crashed; the test job is
        already red — the test log's job, not this step's),
      * reference != baseline (report for reconciliation).
  - With -test-iterations retries the log can hold several markers per flow.
    Identical counts collapse to one row. Divergent counts are reported as
    UNSTABLE and the worst (max) count / slowest time is diffed.

History: each run appends one JSON line per flow to
build/tap-budget-history.jsonl (or TAP_BUDGET_HISTORY) — {date, sha, flow,
actual, seconds} — giving a trend view across accepted bumps. CI uploads the
file as an artifact so the trend survives the runner.

To accept a new cost as the baseline, edit tap-budget-baseline.json and commit.
"""

import json
import os
import re
import subprocess
import sys

# Non-greedy so trailing braces elsewhere on the same physical log line can't
# over-extend the capture (the marker JSON has no nested objects).
MARKER = re.compile(r"TAP-BUDGET-JSON\s+(\{.*?\})")
BASELINE_PATH = os.environ.get(
    "TAP_BUDGET_BASELINE",
    os.path.join(
        os.path.dirname(__file__), "..", "..",
        "PhaseTrainingUITests", "tap-budget-baseline.json",
    ),
)
DEFAULT_HISTORY_PATH = os.path.join(
    os.path.dirname(__file__), "..", "..",
    "build", "tap-budget-history.jsonl",
)
# Wall-clock on a shared CI sim is noisy; a flow must exceed the baseline by
# this fraction before it's flagged (and it's advisory regardless — exit 0).
# The baselines are calibrated to CI hardware (macos-26 runners), so these
# thresholds measure real growth, not machine variance.
TIME_DRIFT_FRACTION = 0.5
# Above this the flag escalates: not plausibly noise, look at the flow.
TIME_CRITICAL_FRACTION = 1.0


def parse_actuals(text):
    """flow -> list of marker records (one per attempt; retries repeat)."""
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
            out.setdefault(flow, []).append(rec)
    return out


def load_baseline():
    """Return (baseline_dict, error_or_None).

    Values normalize to {"taps": int|None, "seconds": float|None}: a plain int
    is the legacy taps-only form. A MISSING file is legitimate (no baseline
    committed yet) → ({}, None). A file that EXISTS but won't parse is
    corruption → ({}, msg) so the caller can FAIL instead of silently
    reclassifying every flow as brand-new.
    """
    try:
        with open(BASELINE_PATH) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}, None
    except (OSError, json.JSONDecodeError) as e:
        return {}, f"unreadable/corrupt ({type(e).__name__}: {e})"
    if not isinstance(data, dict):
        return {}, "not a JSON object"
    norm = {}
    for flow, v in data.items():
        if isinstance(v, dict):
            norm[flow] = {"taps": v.get("taps"), "seconds": v.get("seconds")}
        elif isinstance(v, (int, float)):
            norm[flow] = {"taps": int(v), "seconds": None}
        else:
            # Bad hand-edit (e.g. a string). Keep the raw value; the per-flow
            # isinstance checks in main() will classify it as BASELINE ERROR.
            norm[flow] = {"taps": v, "seconds": None}
    return norm, None


def git_sha():
    try:
        return subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip() or "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


def append_history(actuals):
    """Append one line per flow to the history file. Best-effort."""
    path = os.environ.get("TAP_BUDGET_HISTORY", DEFAULT_HISTORY_PATH)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        sha = git_sha()
        with open(path, "a") as f:
            for flow, recs in sorted(actuals.items()):
                r = recs[-1]
                f.write(json.dumps({
                    "date": r.get("date"),
                    "sha": sha,
                    "flow": flow,
                    "actual": r.get("actual"),
                    "seconds": r.get("seconds"),
                }) + "\n")
    except OSError:
        pass  # history is best-effort; never fail the step over it


def fmt_num(v, unit=""):
    return (str(v) + unit) if v is not None else "—"


def main():
    # A missing/unreadable LOG is not a gate: the CI step runs `if: always()`,
    # and a crashed test job is already red — failing the diff step too adds
    # noise, not signal. Every other harness-broken signal below exits 1.
    if len(sys.argv) > 1:
        try:
            with open(sys.argv[1], errors="replace") as f:
                text = f.read()
        except OSError as e:
            print(f"tap-budget: could not read log '{sys.argv[1]}': {e} "
                  "(test job already reflects this; not gating)")
            return 0
    else:
        text = sys.stdin.read()

    actuals = parse_actuals(text)
    baseline, baseline_err = load_baseline()

    if not actuals:
        # No markers at all. Two cases:
        #   - The suite never ran / job crashed: the test job is already red;
        #     report and stay green.
        #   - The TapBudget tests RAN but emitted nothing: harness broken in a
        #     way the test job may not catch (e.g. recordTapBudget calls
        #     dropped). Gate on that.
        ran = "TapBudgetTests" in text
        if ran:
            print("tap-budget: TapBudgetTests ran but emitted no markers — "
                  "tracking calls likely removed. Failing (coverage loss).")
            return 1
        print("tap-budget: no TAP-BUDGET-JSON markers found in log — did the "
              "TapBudget tests run? (non-gating, continuing)")
        return 0

    rows = []
    drift = []       # taps moved vs baseline, or a brand-new flow
    missing = []     # in baseline but no marker emitted (test removed / crashed)
    errored = []     # baseline value isn't a number (bad hand-edit)
    divergent = []   # actual==baseline but the in-code reference disagrees
    unstable = []    # retries of one flow reported different actuals
    slow_flows = []  # retry-worst seconds over budget

    for flow in sorted(set(actuals) | set(baseline)):
        recs = actuals.get(flow, [])
        base = baseline.get(flow) or {"taps": None, "seconds": None}
        if not recs:
            status, delta = "MISSING (in baseline, not run)", ""
            missing.append(flow)
            rows.append((flow, base["taps"], None, None, None, None, None, None,
                         status, delta))
            continue

        counts = [r.get("actual") for r in recs]
        times = [r.get("seconds") for r in recs if r.get("seconds") is not None]
        gaps = [r.get("max_gap_s") for r in recs if r.get("max_gap_s") is not None]
        p95s = [r.get("p95_gap_s") for r in recs if r.get("p95_gap_s") is not None]
        ref = recs[-1].get("reference")
        seconds = max(times) if times else None
        max_gap = max(gaps) if gaps else None
        p95_gap = max(p95s) if p95s else None
        actual = counts[-1]

        base_taps = base["taps"]
        if base_taps is None and flow not in baseline:
            status, delta = "NEW (no baseline)", ""
            drift.append(flow)
        elif not isinstance(base_taps, int):
            # A baseline entry that isn't a number (string from a bad
            # hand-edit) would otherwise crash `actual - base`.
            status, delta = "BASELINE ERROR (non-numeric)", ""
            errored.append(flow)
        elif not all(isinstance(c, int) for c in counts):
            # bool is an int subclass; that's fine. Strings from a bad baseline
            # edit would otherwise crash `actual - base`.
            status, delta = "BASELINE ERROR (non-numeric)", ""
            errored.append(flow)
        elif len(set(counts)) > 1 or (len(times) > 1 and len(set(times)) > 1):
            # -test-iterations retry reported different counts or different
            # times for this flow. Taps should be deterministic; times flake
            # with sim load. Either way: UNSTABLE, and diff the worst (max
            # count, max seconds) against baseline.
            actual = max(c for c in counts if isinstance(c, int))
            shown = ",".join(str(c) for c in counts)
            if len(times) > 1 and len(set(times)) > 1:
                shown += "s"
            status, delta = f"UNSTABLE ({shown})", ""
            unstable.append(flow)
            if actual != base_taps:
                d = actual - base_taps
                status += f"; {'REGRESSED' if d > 0 else 'improved'} vs baseline"
                delta = f"{d:+d}"
                drift.append(flow)
        elif actual != base_taps:
            d = actual - base_taps
            status = "REGRESSED" if d > 0 else "improved"
            delta = f"{d:+d}"
            drift.append(flow)
        elif isinstance(ref, int) and ref != base_taps:
            # The expected count lives in two files (the test's in-code
            # `reference` and this baseline). Catch them silently diverging.
            status, delta = f"ref≠baseline ({ref} vs {base_taps})", "0"
            divergent.append(flow)
        else:
            status, delta = "unchanged", "0"

        # Time budget: visibility-only. Baselines are calibrated to CI
        # hardware; +50% is SLOW (usually noise), +100% is a likely real
        # stall worth investigating even if taps held.
        base_seconds = base.get("seconds")
        if (isinstance(base_seconds, (int, float))
                and isinstance(seconds, (int, float))
                and seconds > base_seconds * (1 + TIME_DRIFT_FRACTION)):
            tier = ("CRITICAL" if seconds > base_seconds * (1 + TIME_CRITICAL_FRACTION)
                    else "SLOW")
            status += f" · {tier} (baseline {base_seconds:g}s, test {seconds:g}s)"
            slow_flows.append((flow, tier))

        rows.append((flow, base["taps"], counts[-1], ref, seconds, max_gap,
                     p95_gap, base.get("seconds"), status, delta))

    # Human/markdown table. Columns are named so the two currencies don't blur:
    # taps are the PRODUCT metric (user interaction cost); test-s is the
    # HARNESS metric (sim wall-clock), never a UX cost.
    header = ("| flow | baseline taps | actual taps | reference "
              "| test-s | test-s-budget | max-gap s | p95-gap s "
              "| status | Δ |")
    sep = "|---|---|---|---|---|---|---|---|---|---|"
    lines = [header, sep]
    for (flow, base, actual, ref, seconds, max_gap, p95_gap, s_budget,
         status, delta) in rows:
        lines.append(
            f"| {flow} | {fmt_num(base)} | {fmt_num(actual)} | {fmt_num(ref)} | "
            f"{fmt_num(seconds)} | {fmt_num(s_budget)} | {fmt_num(max_gap)} | "
            f"{fmt_num(p95_gap)} | {status} | {delta} |"
        )
    table = "\n".join(lines)

    footer = []
    if baseline_err:
        footer.append(f"**Baseline {baseline_err}** — fix "
                      "PhaseTrainingUITests/tap-budget-baseline.json; until then "
                      "every flow shows as NEW (not a real regression).")
    if drift:
        footer.append(f"**Drift:** {', '.join(drift)} — update "
                      "tap-budget-baseline.json to accept, or investigate.")
    if missing:
        footer.append(f"**Not run (in baseline, no marker):** {', '.join(missing)} "
                      "— a tracked flow stopped emitting its marker; investigate.")
    if errored:
        footer.append(f"**Baseline error (non-numeric):** {', '.join(errored)} "
                      "— fix the value in tap-budget-baseline.json.")
    if unstable:
        footer.append(f"**UNSTABLE (retry counts disagree):** {', '.join(unstable)} "
                      "— the tap count for these flows should be deterministic; "
                      "a UI-test flake is leaking into the measurement.")
    if slow_flows:
        slow = [f for f, tier in slow_flows if tier == "SLOW"]
        critical = [f for f, tier in slow_flows if tier == "CRITICAL"]
        if slow:
            footer.append(f"**SLOW (over baseline +50%):** {', '.join(slow)} "
                          "— taps held but wall-clock grew; usually sim noise, "
                          "worth a re-run before investigating.")
        if critical:
            footer.append(f"**CRITICAL (over baseline +100%):** {', '.join(critical)} "
                          "— not plausibly machine noise. A per-step stall or an "
                          "app-side latency regression; investigate even though "
                          "taps held.")
    if divergent:
        footer.append(f"**Reference ≠ baseline:** {', '.join(divergent)} — the "
                      "test's in-code reference and tap-budget-baseline.json "
                      "disagree; reconcile them.")
    # A flow renamed in the test shows as MISSING (old id) + NEW (new id) in
    # the same run. Connect the dots so it reads as a rename, not two anomalies.
    if missing and drift:
        renamed = [f for f in missing if f not in errored]
        if renamed:
            footer.append(f"**Likely rename:** {', '.join(renamed)} have no "
                          "marker but NEW flows appeared — if a flow id was "
                          "renamed, update tap-budget-baseline.json to match.")
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

    # Trend history: one JSONL line per flow per run (best-effort).
    append_history(actuals)

    # Gate on harness-broken signals only (see docstring): a tracked flow that
    # stopped emitting, or a corrupt baseline. Actual-vs-baseline drift and
    # slow flows stay visibility-only, honoring the track-don't-gate decision.
    if missing or errored or baseline_err:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
