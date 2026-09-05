#!/usr/bin/env python3
"""Unit tests for scripts/quality/tap_budget_diff.py.

Run directly:  python3 scripts/quality/test_tap_budget_diff.py
(or: python3 -m unittest scripts.quality.test_tap_budget_diff -v)

Covers the signals the CI report acts on: unchanged, drift, brand-new flow,
MISSING (gates), corrupt baseline (gates), non-numeric baseline (gates),
ref≠baseline, UNSTABLE retries (worst count diffed), SLOW time budgets
(visibility only), history append, unreadable log (non-gating), and the
empty-log case.
"""

import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "tap_budget_diff.py")
spec = importlib.util.spec_from_file_location("tap_budget_diff", SCRIPT)
assert spec is not None and spec.loader is not None  # script always exists
tbd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tbd)


def marker(flow, actual, reference=None, seconds=None, max_gap=None):
    parts = [f'"flow":"{flow}"', f'"actual":{actual}']
    if reference is not None:
        parts.append(f'"reference":{reference}')
    if seconds is not None:
        parts.append(f'"seconds":{seconds}')
    if max_gap is not None:
        parts.append(f'"max_gap_s":{max_gap}')
    return "TAP-BUDGET-JSON {" + ",".join(parts) + "}"


class TapBudgetDiffTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.baseline_path = os.path.join(self.tmp.name, "baseline.json")
        self.history_path = os.path.join(self.tmp.name, "history.jsonl")
        self._orig_baseline = tbd.BASELINE_PATH
        self._orig_history = tbd.DEFAULT_HISTORY_PATH
        tbd.BASELINE_PATH = self.baseline_path
        tbd.DEFAULT_HISTORY_PATH = self.history_path
        self.addCleanup(setattr, tbd, "BASELINE_PATH", self._orig_baseline)
        self.addCleanup(setattr, tbd, "DEFAULT_HISTORY_PATH", self._orig_history)

    def write_baseline(self, data):
        with open(self.baseline_path, "w") as f:
            json.dump(data, f)

    def run_diff(self, log_text, log_file=True):
        """Run main() with the log as a file (or stdin); return (output, code)."""
        argv = [tbd.__name__]
        f = None
        if log_file:
            f = tempfile.NamedTemporaryFile("w", suffix=".log", delete=False)
            f.write(log_text)
            f.close()
            argv.append(f.name)
        old_argv, old_stdout = sys.argv, sys.stdout
        sys.argv, buf = argv, io.StringIO()
        sys.stdout = buf
        try:
            code = tbd.main()
        finally:
            sys.stdout, sys.argv = old_stdout, old_argv
            if f:
                os.unlink(f.name)
        return buf.getvalue(), code

    # --- gating: exit 1 -------------------------------------------------

    def test_missing_flow_gates(self):
        """A baseline flow with no marker = silent coverage loss → exit 1."""
        self.write_baseline({"a": 2, "b": 3})
        out, code = self.run_diff(marker("a", 2, 2))
        self.assertEqual(code, 1)
        self.assertIn("MISSING", out)
        self.assertIn("b", out)
        self.assertIn("unchanged", out)  # flow a still reported normally

    def test_corrupt_baseline_gates(self):
        self.write_baseline({"a": 2})
        with open(self.baseline_path, "w") as f:
            f.write("{not json")
        out, code = self.run_diff(marker("a", 2, 2))
        self.assertEqual(code, 1)
        self.assertIn("unreadable/corrupt", out)

    def test_non_numeric_baseline_gates(self):
        self.write_baseline({"a": "two"})
        out, code = self.run_diff(marker("a", 2, 2))
        self.assertEqual(code, 1)
        self.assertIn("BASELINE ERROR", out)

    def test_non_numeric_baseline_entry_gates(self):
        """A dict baseline with a non-numeric taps value also gates."""
        self.write_baseline({"a": {"taps": "two", "seconds": 5.0}})
        out, code = self.run_diff(marker("a", 2, 2))
        self.assertEqual(code, 1)
        self.assertIn("BASELINE ERROR", out)

    def test_ran_but_no_markers_gates(self):
        """TapBudgetTests ran but emitted nothing = tracking calls removed."""
        self.write_baseline({"a": 2})
        out, code = self.run_diff(
            "Test Case '-[PhaseTrainingUITests.TapBudgetTests testTapBudget_x]' passed")
        self.assertEqual(code, 1)
        self.assertIn("no markers", out)

    def test_suite_skipped_stays_green(self):
        """No markers AND no TapBudget test cases = suite skipped; stay green."""
        self.write_baseline({"a": 2})
        out, code = self.run_diff("nothing here", log_file=False)
        self.assertEqual(code, 0)
        self.assertIn("did the", out)

    # --- gating: exit 0 (visibility only) -------------------------------

    def test_unchanged_flows_exit_0(self):
        self.write_baseline({"a": {"taps": 2, "seconds": 4.0},
                             "b": {"taps": 3, "seconds": 8.0}})
        log = (marker("a", 2, 2, seconds=4.1) + "\n" + marker("b", 3, 3, seconds=8.0))
        out, code = self.run_diff(log)
        self.assertEqual(code, 0)
        self.assertIn("All flows match baseline.", out)
        self.assertIn("4.1", out)   # seconds column
        self.assertIn("8.0", out)   # s-budget column

    def test_drift_is_visibility_only(self):
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        out, code = self.run_diff(marker("a", 4, 2))
        self.assertEqual(code, 0)
        self.assertIn("REGRESSED", out)
        self.assertIn("+2", out)

    def test_slow_flow_flagged_not_gated(self):
        """seconds in (baseline+50%, baseline+100%] → SLOW flag, exit still 0."""
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        out, code = self.run_diff(marker("a", 2, 2, seconds=9.0))
        self.assertEqual(code, 0)
        self.assertIn("SLOW", out)
        self.assertIn("SLOW (over baseline +50%)", out)

    def test_critical_slow_escalates(self):
        """seconds > baseline+100% → CRITICAL tier, exit still 0."""
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        out, code = self.run_diff(marker("a", 2, 2, seconds=11.0))
        self.assertEqual(code, 0)
        self.assertIn("CRITICAL (over baseline +100%)", out)

    def test_fast_flow_not_flagged(self):
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        out, code = self.run_diff(marker("a", 2, 2, seconds=7.4))  # +48%, under 50%
        self.assertEqual(code, 0)
        self.assertNotIn("SLOW", out)

    def test_legacy_int_baseline_still_works(self):
        self.write_baseline({"a": 2})
        out, code = self.run_diff(marker("a", 2, 2, seconds=6.0))
        self.assertEqual(code, 0)
        self.assertIn("unchanged", out)

    def test_rename_detection_footer(self):
        """Old flow MISSING + new flow NEW in one run → likely-rename footer."""
        self.write_baseline({"old-flow": {"taps": 2, "seconds": 5.0}})
        out, code = self.run_diff(marker("new-flow", 2, 2))
        self.assertEqual(code, 1)  # missing still gates
        self.assertIn("Likely rename", out)
        self.assertIn("old-flow", out)

    def test_missing_log_is_non_gating(self):
        out, code = self.run_diff("nothing here", log_file=False)
        self.assertEqual(code, 0)
        self.assertIn("no TAP-BUDGET-JSON markers", out)

    def test_unreadable_log_file_is_non_gating(self):
        old_argv, old_stdout = sys.argv, sys.stdout
        sys.argv = [tbd.__name__, "/nonexistent/path/x.log"]
        sys.stdout = buf = io.StringIO()
        try:
            code = tbd.main()
        finally:
            sys.stdout, sys.argv = old_stdout, old_argv
        self.assertEqual(code, 0)
        self.assertIn("could not read log", buf.getvalue())

    # --- retry / UNSTABLE semantics -------------------------------------

    def test_retry_identical_counts_collapse(self):
        """-test-iterations retries with the same count: one clean row."""
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        m = marker("a", 2, 2, seconds=5.0)
        out, code = self.run_diff(f"{m}\n{m}\n{m}")
        self.assertEqual(code, 0)
        self.assertEqual(out.count("| a |"), 1)
        self.assertIn("unchanged", out)
        self.assertNotIn("UNSTABLE", out)

    def test_retry_divergent_counts_reported_unstable(self):
        """Retry flake: different counts across attempts → UNSTABLE + worst."""
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        log = marker("a", 2, 2) + "\n" + marker("a", 5, 2)
        out, code = self.run_diff(log)
        self.assertEqual(code, 0)  # unstable is visibility, drift gates nothing
        self.assertIn("UNSTABLE (2,5)", out)
        self.assertIn("REGRESSED", out)  # worst count 5 vs baseline 2
        self.assertIn("+3", out)

    def test_retry_divergent_times_use_worst(self):
        """Retry with same taps but different seconds: worst time is diffed."""
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        log = marker("a", 2, 2, seconds=4.0) + "\n" + marker("a", 2, 2, seconds=9.0)
        out, code = self.run_diff(log)
        self.assertEqual(code, 0)
        self.assertIn("UNSTABLE (2,2s)", out)

    def test_last_marker_wins_per_flow(self):
        """Non-retry repeats (re-printed markers) parse to one row."""
        self.write_baseline({"a": {"taps": 3, "seconds": 7.0}})
        log = marker("a", 2, 2) + "\n" + marker("a", 3, 3)
        out, code = self.run_diff(log)
        self.assertEqual(code, 0)
        self.assertIn("UNSTABLE (2,3)", out)  # divergent = unstable, not last-wins

    # --- report details ---------------------------------------------------

    def test_new_flow_reported(self):
        self.write_baseline({})
        out, code = self.run_diff(marker("new-thing", 5, 5))
        self.assertEqual(code, 0)
        self.assertIn("NEW (no baseline)", out)

    def test_ref_baseline_divergence_reported(self):
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        out, code = self.run_diff(marker("a", 2, 7))
        self.assertEqual(code, 0)
        self.assertIn("ref≠baseline (7 vs 2)", out)

    def test_missing_baseline_file_ok(self):
        out, code = self.run_diff(marker("a", 2, 2))
        self.assertEqual(code, 0)
        self.assertIn("NEW (no baseline)", out)

    def test_max_gap_column_rendered(self):
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        out, code = self.run_diff(marker("a", 2, 2, seconds=5.0, max_gap=3.2))
        self.assertEqual(code, 0)
        self.assertIn("3.2", out)

    # --- history ----------------------------------------------------------

    def test_history_appended(self):
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        self.run_diff(marker("a", 2, 2, seconds=5.1) + "\n" + marker("b", 3, 3))
        with open(self.history_path) as f:
            entries = [json.loads(line) for line in f if line.strip()]
        flows = {e["flow"] for e in entries}
        self.assertEqual(flows, {"a", "b"})
        a = next(e for e in entries if e["flow"] == "a")
        self.assertEqual(a["actual"], 2)
        self.assertEqual(a["seconds"], 5.1)
        self.assertIn("sha", a)
        self.assertIn("date", a)

    def test_history_env_override(self):
        custom = os.path.join(self.tmp.name, "custom-hist.jsonl")
        os.environ["TAP_BUDGET_HISTORY"] = custom
        self.addCleanup(os.environ.pop, "TAP_BUDGET_HISTORY", None)
        self.write_baseline({"a": {"taps": 2, "seconds": 5.0}})
        self.run_diff(marker("a", 2, 2, seconds=5.0))
        with open(custom) as f:
            entries = [json.loads(line) for line in f if line.strip()]
        self.assertEqual(len(entries), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
