#!/usr/bin/env bash
#
# verify_font_tokens.sh — no raw Font.custom(_:size:) outside the token table.
#
# Every font the app draws comes through PhaseTraining/Theme/Typography.swift:
# the nine TypeStyle tokens, or Font.scaled(_:size:) for a one-off size. Both
# apply the screen-width factor and a Dynamic Type curve. A bare
# `.custom("Inter-Regular", size: 13)` does neither, and until 2026-09-15 there
# were 123 of them across 50 files, a third of the app's type frozen while the
# rest scaled. This makes the next one a CI failure instead of a slow drift.
#
# Fix when it fails: change `.custom(name, size: N)` to `.scaled(name, size: N)`,
# or better, use a TypeStyle token via `.styled(...)`.
set -euo pipefail
cd "$(dirname "$0")/../.."

offenders=$(grep -rn '\.custom(' --include='*.swift' PhaseTraining | grep -v '^PhaseTraining/Theme/Typography.swift:' || true)
if [ -n "$offenders" ]; then
  echo "Raw Font.custom outside Theme/Typography.swift (use Font.scaled or a TypeStyle):" >&2
  echo "$offenders" >&2
  exit 1
fi
echo "font tokens: ok (no raw .custom( outside Theme/Typography.swift)"
