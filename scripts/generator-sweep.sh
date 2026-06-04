#!/usr/bin/env bash
# Run the WorkoutGenerator controlled-variable sweep and open the report.
#
# Fast inner loop for generator validation: tweak focusBias / prescription /
# a context signal, run this, scroll the doc, see exactly what moved. Each
# variable is swept one-at-a-time against a fixed baseline; cells that differ
# from baseline are highlighted, and any variable whose variants all match
# baseline is flagged as a DEAD signal.
#
# Emits TWO files: report.html (open it, side-by-side) and report.md
# (paste-friendly for Cowork / another session — a remote agent can't read
# this /tmp path, so the .md is the thing you copy into the chat).
#
# Usage: scripts/generator-sweep.sh
set -euo pipefail
cd "$(dirname "$0")/.."

HTML=/tmp/generator-sweep/report.html
MD=/tmp/generator-sweep/report.md

# Regenerate the project so a freshly-added test file is picked up.
command -v xcodegen >/dev/null && xcodegen generate >/dev/null

# Pick the first available iPhone simulator.
DEST=$(xcrun simctl list devices available | grep -Eo "iPhone 1[0-9][^(]*\([0-9A-F-]{36}\)" | head -1 | grep -Eo "[0-9A-F-]{36}")
if [ -z "$DEST" ]; then echo "No iPhone simulator available" >&2; exit 1; fi

xcodebuild test \
  -project PhaseTraining.xcodeproj \
  -scheme PhaseTraining \
  -destination "platform=iOS Simulator,id=$DEST" \
  -only-testing:PhaseTrainingTests/GeneratorSweepReportTest \
  2>&1 | grep -E "GeneratorSweepReport|error:|\*\* TEST"

[ -f "$HTML" ] && open "$HTML"
[ -f "$MD" ] && echo "Markdown for paste: $MD   (copy to clipboard: pbcopy < $MD)"
