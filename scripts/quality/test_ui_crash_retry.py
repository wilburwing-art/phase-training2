#!/usr/bin/env python3
"""Unit tests for scripts/quality/ui_crash_retry.py.

Run directly:  python3 scripts/quality/test_ui_crash_retry.py

The three fixtures are trimmed `xcresulttool get test-results tests` output
from real main runs: 44805314849 (flows shard, runner crash),
44793901523 (taps shard, assertion failure on all three iterations) and
45869446240 (taps shard, execution time allowance kill).
"""

import copy
import importlib.util
import json
import os
import unittest

HERE = os.path.dirname(__file__)
SCRIPT = os.path.join(HERE, "ui_crash_retry.py")
spec = importlib.util.spec_from_file_location("ui_crash_retry", SCRIPT)
assert spec is not None and spec.loader is not None
ucr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ucr)


def fixture(name):
    with open(os.path.join(HERE, "fixtures", name)) as f:
        return json.load(f)


def suites(tests):
    return tests["testNodes"][0]["children"][0]["children"]


class UICrashRetryTests(unittest.TestCase):
    def test_crash_failure_yields_only_testing_arg(self):
        args = ucr.rerun_args(fixture("xcresult-tests-crash.json"))
        self.assertEqual(
            args,
            [
                "-only-testing:PhaseTrainingUITests/KettleSportUITests/"
                "test_snowSportDay_presentsWithCarvingKettle"
            ],
        )

    def test_timeout_yields_only_testing_arg(self):
        args = ucr.rerun_args(fixture("xcresult-tests-timeout.json"))
        self.assertEqual(
            args,
            [
                "-only-testing:PhaseTrainingUITests/MotivationBatchUITests/"
                "test_progressStrengthRowShowsSelfDelta"
            ],
        )

    def test_crash_plus_timeout_yields_two_args(self):
        tests = fixture("xcresult-tests-crash.json")
        suites(tests).extend(suites(fixture("xcresult-tests-timeout.json")))
        self.assertEqual(len(ucr.rerun_args(tests)), 2)

    def test_timeout_plus_assertion_yields_none(self):
        tests = fixture("xcresult-tests-timeout.json")
        suites(tests).extend(suites(fixture("xcresult-tests-assertion.json")))
        self.assertIsNone(ucr.rerun_args(tests))

    def test_assertion_failure_yields_none(self):
        self.assertIsNone(
            ucr.rerun_args(fixture("xcresult-tests-assertion.json"))
        )

    def test_skipped_cases_are_not_failures(self):
        # The assertion fixture's skipped cases carry "Failure Message"
        # children; with the failed case removed nothing is left to retry.
        tests = fixture("xcresult-tests-assertion.json")
        for suite in suites(tests):
            suite["children"] = [
                c for c in suite["children"] if c.get("result") != "Failed"
            ]
        self.assertIsNone(ucr.rerun_args(tests))

    def test_crash_plus_assertion_yields_none(self):
        tests = fixture("xcresult-tests-crash.json")
        suites(tests).extend(suites(fixture("xcresult-tests-assertion.json")))
        self.assertIsNone(ucr.rerun_args(tests))

    def test_two_crashes_yield_two_args(self):
        tests = fixture("xcresult-tests-crash.json")
        extra = copy.deepcopy(suites(tests)[-1])
        extra["name"] = "OtherUITests"
        for case in extra["children"]:
            case["nodeIdentifier"] = case["nodeIdentifier"].replace(
                "KettleSportUITests", "OtherUITests"
            )
        suites(tests).append(extra)
        args = ucr.rerun_args(tests)
        self.assertEqual(len(args), 2)
        self.assertIn(
            "-only-testing:PhaseTrainingUITests/OtherUITests/"
            "test_snowSportDay_presentsWithCarvingKettle",
            args,
        )

    def test_failed_case_without_message_yields_none(self):
        tests = fixture("xcresult-tests-crash.json")
        for suite in suites(tests):
            for case in suite["children"]:
                if case.get("result") == "Failed":
                    case["children"] = []
        self.assertIsNone(ucr.rerun_args(tests))

    def test_main_exit_codes(self):
        path = os.path.join(HERE, "fixtures", "xcresult-tests-crash.json")
        self.assertEqual(ucr.main(["x", "--json", path]), 0)
        path = os.path.join(HERE, "fixtures", "xcresult-tests-assertion.json")
        self.assertEqual(ucr.main(["x", "--json", path]), 1)
        self.assertEqual(ucr.main(["x", "--json", "/nonexistent.json"]), 2)

    def test_annotations_name_each_failed_case_once_per_message(self):
        lines = ucr.failure_annotations(fixture("xcresult-tests-assertion.json"))
        self.assertEqual(
            lines,
            [
                "::error::PhaseTrainingUITests/LogFlowTests/testRestExpiryShowsDoneFlash: "
                "LogFlowTests.swift:209: XCTAssertTrue failed - rest card should appear "
                "after first set done",
                "::error::PhaseTrainingUITests/LogFlowTests/testRestExpiryShowsDoneFlash: "
                "LogFlowTests.swift:213: XCTAssertTrue failed - DONE flash card should "
                "appear within ~3s",
            ],
        )

    def test_annotations_name_the_timed_out_case(self):
        tests = fixture("xcresult-tests-timeout.json")
        suites(tests).extend(suites(fixture("xcresult-tests-crash.json")))
        self.assertEqual(
            ucr.failure_annotations(tests),
            [
                "::error::PhaseTrainingUITests/MotivationBatchUITests/"
                "test_progressStrengthRowShowsSelfDelta: "
                "Test exceeded execution time allowance of 3 minutes",
                "::error::PhaseTrainingUITests/KettleSportUITests/"
                "test_snowSportDay_presentsWithCarvingKettle: "
                "Test crashed with signal term.",
            ],
        )

    def test_annotations_escape_newlines_and_percent(self):
        tests = fixture("xcresult-tests-crash.json")
        for suite in suites(tests):
            for case in suite["children"]:
                if case.get("result") == "Failed":
                    case["children"] = [
                        {"nodeType": "Failure Message", "name": "100% sure\nsecond line"}
                    ]
        (line,) = ucr.failure_annotations(tests)
        self.assertTrue(line.endswith(": 100%25 sure%0Asecond line"), line)

    def test_annotations_empty_when_nothing_failed(self):
        tests = fixture("xcresult-tests-assertion.json")
        for suite in suites(tests):
            suite["children"] = [
                c for c in suite["children"] if c.get("result") != "Failed"
            ]
        self.assertEqual(ucr.failure_annotations(tests), [])

    def test_main_annotate_exit_codes(self):
        path = os.path.join(HERE, "fixtures", "xcresult-tests-assertion.json")
        self.assertEqual(ucr.main(["x", "--annotate", "--json", path]), 0)
        self.assertEqual(
            ucr.main(["x", "--annotate", "--json", "/nonexistent.json"]), 2
        )


if __name__ == "__main__":
    unittest.main()
