#!/usr/bin/env python3
"""Decide whether a red UI-test shard failed only on cases xcodebuild never retried.

xcodebuild's -retry-tests-on-failure skips two kinds of failure:
- a runner crash ("Test crashed with signal term."): the relaunched runner
  logs "Executed 0 tests" (main run 44805314849, KettleSportUITests);
- an execution time allowance kill ("Test exceeded execution time
  allowance of 3 minutes"): the case runs once (main run 45869446240,
  MotivationBatchUITests at 211 s after seven runs at 52 to 66 s).
A launch timeout ("Timed out while launching application via Xcode")
does get retried, but the retries land on the same cold simulator a few
seconds later and fail the same way (main run 45919860804,
AppLaunchSmokeTests failed all three iterations at about 100 s each
while the 39 cases after it passed), so it is re-run once at the end too.
The same cold launch can also log "Failed to get launch progress" and
"Timed out while requesting screenshot" beside the timeout (main run
45951067374, ArcDeloadNoticeUITests, the screens shard's first case);
those two re-run too.
This script reads the result bundle and prints one -only-testing argument
per such case so the workflow can re-run them once. A case that hangs
again on the re-run keeps the shard red.

--annotate prints one GitHub `::error::` line per failed case and distinct
failure message instead. xcbeautify can print an allowance-killed case as
passed and put the step's only error on a case that passed (main run
45869446240), so the workflow calls this on a red shard to name the real
failures.

Usage:
  python3 scripts/quality/ui_crash_retry.py build/TestResults.xcresult
  python3 scripts/quality/ui_crash_retry.py --json tests.json
  python3 scripts/quality/ui_crash_retry.py --annotate build/TestResults.xcresult
  python3 scripts/quality/ui_crash_retry.py --annotate --json tests.json

Exit codes (--annotate: 0 when the bundle was read, 2 when it was not):
  0  every failed case is a crash or a timeout; the -only-testing args
     are on stdout
  1  at least one failed case has another failure, or nothing failed;
     the shard result stands
  2  the bundle could not be read
"""

import json
import subprocess
import sys

RERUN_MARKERS = (
    "Test crashed with signal",
    "Test exceeded execution time allowance",
    "Timed out while launching application",
    "Failed to get launch progress",
    "Timed out while requesting screenshot",
    "Stall on main thread",
)


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


def _rerunnable(message):
    return any(marker in message for marker in RERUN_MARKERS)


def rerun_args(tests):
    """Return -only-testing args when every failed case crashed or timed out, else None."""
    args = []
    for root in tests.get("testNodes", []):
        for bundle, case in _failed_cases(root):
            messages = list(_failure_messages(case))
            if not messages or not all(_rerunnable(m) for m in messages):
                return None
            ident = case.get("nodeIdentifier", "").removesuffix("()")
            if not bundle or not ident:
                return None
            arg = f"-only-testing:{bundle}/{ident}"
            if arg not in args:
                args.append(arg)
    return args or None


def _escape(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def failure_annotations(tests):
    """Return one `::error::` line per failed case and distinct failure message."""
    lines = []
    for root in tests.get("testNodes", []):
        for bundle, case in _failed_cases(root):
            ident = f"{bundle}/{case.get('nodeIdentifier', '').removesuffix('()')}"
            messages = list(dict.fromkeys(_failure_messages(case))) or ["failed, no message"]
            for message in messages:
                line = f"::error::{_escape(ident)}: {_escape(message)}"
                if line not in lines:
                    lines.append(line)
    return lines


def load_bundle(path):
    out = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)


def main(argv):
    annotate = len(argv) > 1 and argv[1] == "--annotate"
    if annotate:
        argv = argv[:1] + argv[2:]
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
    if annotate:
        lines = failure_annotations(tests)
        if lines:
            print("\n".join(lines))
        return 0
    args = rerun_args(tests)
    if args is None:
        return 1
    print("\n".join(args))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
