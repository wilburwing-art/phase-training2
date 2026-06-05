#!/usr/bin/env bash
#
# verify_coachdb_sync.sh — guard against coach.db source↔artifact drift (audit N1).
#
# PhaseTraining/Resources/coach.db is BUILT from db/source/*.json by build_db.py,
# which is byte-deterministic. So rebuilding and finding ANY diff means source and
# the shipped artifact have diverged — either source was edited without a rebuild,
# or the binary was hand-edited without reflecting back to source. That divergence
# is the footgun that silently re-shipped 191 pruned exercises once already; this
# guard makes it a hard CI failure instead.
#
# Fix when it fails:  python3 scripts/db/build_db.py  (then commit the result)
# Reconcile a binary-only edit: python3 scripts/db/extract_to_source.py first.
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 scripts/db/build_db.py >/dev/null

if ! git diff --quiet -- PhaseTraining/Resources/coach.db db/source/; then
    echo "::error::coach.db is out of sync with db/source — rebuild from source and commit." >&2
    git --no-pager diff --stat -- PhaseTraining/Resources/coach.db db/source/ >&2
    exit 1
fi
echo "coach.db is in sync with db/source ✓"
