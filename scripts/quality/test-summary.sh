#!/usr/bin/env bash
#
# test-summary.sh — summarise an xcodebuild test log without under-reading it.
#
# R3-6. A duplicate key in a sport pool crashed the test HOST three times and
# the run still summarised as "1 failed", because a fatal error kills the
# process instead of failing an assertion. Anything that greps only
# "Test Case .* failed" reads that as one bad test. Two more lines matter:
#
#   Fatal error:                    a crash took the host down mid-run
#   Application failed preflight    the simulator collapsed; the run is void
#
# Usage: scripts/quality/test-summary.sh <log>   (exits non-zero if any is set)
set -uo pipefail
log="${1:?usage: test-summary.sh <xcodebuild log>}"
passed=$(grep -cE "Test Case.*passed" "$log")
failed=$(grep -cE "Test Case.*failed" "$log")
fatal=$(grep -c "Fatal error" "$log")
busy=$(grep -c "failed preflight checks" "$log")
echo "passed=$passed failed=$failed fatal=$fatal busy=$busy"
[ "$fatal" -gt 0 ] && { echo "--- host crashes (NOT counted in 'failed') ---"; grep "Fatal error" "$log" | sort -u | head -5; }
[ "$busy" -gt 0 ] && echo "--- simulator collapsed: this run proves nothing, reboot and re-run ---"
[ "$failed" -gt 0 ] && grep -E "error:.*XCTAssert" "$log" | sed -E 's#^/Users/[^ ]*/##' | cut -c1-200 | sort -u | head -10
[ $((failed + fatal + busy)) -eq 0 ]
