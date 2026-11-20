#!/usr/bin/env python3
"""Decide whether a red UI-test shard failed only on test-runner crashes.

xcodebuild's -retry-tests-on-failure re-runs a failed case only when the
runner survives to report it. When the runner dies ("Test crashed with
signal term."), the relaunched runner logs "Executed 0 tests" and the case
gets no retry (main run 44805314849, KettleSportUITests). This script reads
the result bundle and prints one -only-testing argument per crashed case so
the workflow can re-run them once.

Usage:
  python3 scripts/quality/ui_crash_retry.py build/TestResults.xcresult
  python3 scripts/quality/ui_crash_retry.py --json tests.json

Exit codes:
  0  every failed case is a crash; the -only-testing args are on stdout
  1  at least one failed case has a non-crash failure, or nothing failed;
     the shard result stands
  2  the bundle could not be read
"""

import json
import subprocess
import sys

CRASH_MARKER = "Test crashed with signal"


def _failure_messages(node):
    for child in node.get("children", []):
        if child.get("nodeType") == "Failure Message":
            yield child.get("name", "")
        else:
            yield from _failure_messages(child)


def _failed_cases(node, bundle=None):
    kind = node.get("nodeType")
    if kind in ("UI test bundle", "Unit test bundle"):
        bundle = node.get("name")
    if kind == "Test Case":
        if node.get("result") == "Failed":
            yield bundle, node
        return
    for child in node.get("children", []):
        yield from _failed_cases(child, bundle)


def crash_only_retry_args(tests):
    """Return -only-testing args when every failed case crashed, else None."""
    args = []
    for root in tests.get("testNodes", []):
        for bundle, case in _failed_cases(root):
            messages = list(_failure_messages(case))
            if not messages or not all(CRASH_MARKER in m for m in messages):
                return None
            ident = case.get("nodeIdentifier", "").removesuffix("()")
            if not bundle or not ident:
                return None
            arg = f"-only-testing:{bundle}/{ident}"
            if arg not in args:
                args.append(arg)
    return args or None


def load_bundle(path):
    out = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == "--json":
            with open(argv[2]) as f:
                tests = json.load(f)
        elif len(argv) == 2:
            tests = load_bundle(argv[1])
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError, subprocess.CalledProcessError) as e:
        print(f"ui_crash_retry: cannot read results: {e}", file=sys.stderr)
        return 2
    args = crash_only_retry_args(tests)
    if args is None:
        return 1
    print("\n".join(args))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
