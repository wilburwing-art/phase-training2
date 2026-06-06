#!/usr/bin/env bash
#
# verify_coachdb_sync.sh — guard against coach.db source↔artifact drift (audit N1).
#
# PhaseTraining/Resources/coach.db is BUILT from db/source/*.json by build_db.py.
# So rebuilding and finding a CONTENT diff means source and the shipped artifact
# have diverged — either source was edited without a rebuild, or the binary was
# hand-edited without reflecting back to source. That divergence is the footgun
# that silently re-shipped 191 pruned exercises once already; this guard makes it
# a hard CI failure instead.
#
# Why not a raw `git diff` on the binary: the SQLite on-disk format is NOT
# stable across libsqlite versions — the file header carries the writing
# library's version stamp (offsets 92–99), and page layout / freelist ordering
# can differ too. The committed artifact was written by one libsqlite; a CI
# runner's python3 links another, so a byte compare went red even when every
# table was identical (observed: a 2-byte version-stamp diff locally, larger
# layout diffs on the macos-26 runner).
#
# So compare LOGICAL content instead: a SHA-256 over each DB's `iterdump()`
# (schema + every row as SQL). iterdump is pure-Python, and both sides are
# dumped by the SAME interpreter in one run, so any format/version quirk cancels
# and only genuine data drift survives. This is the actual source↔artifact
# invariant we care about.
#
# Fix when it fails:  python3 scripts/db/build_db.py  (then commit the result)
# Reconcile a binary-only edit: python3 scripts/db/extract_to_source.py first.
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 scripts/db/build_db.py >/dev/null

# db/source is JSON — deterministic, so a plain diff is the right check there.
if ! git diff --quiet -- db/source/; then
    echo "::error::db/source changed during rebuild — commit the source edits." >&2
    git --no-pager diff --stat -- db/source/ >&2
    exit 1
fi

# Logical-content digest of a SQLite file. The program is fed to `python3 -` via
# the heredoc on stdin, so the DB path is passed as an argv.
logical_digest() {  # $1 = path to a coach.db file
    python3 - "$1" <<'PY'
import sqlite3, hashlib, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
h = hashlib.sha256()
for stmt in con.iterdump():
    h.update(stmt.encode("utf-8"))
    h.update(b"\n")
con.close()
print(h.hexdigest())
PY
}

tmp_committed=$(mktemp)
trap 'rm -f "$tmp_committed"' EXIT
git show HEAD:PhaseTraining/Resources/coach.db > "$tmp_committed"
committed_digest=$(logical_digest "$tmp_committed")
rebuilt_digest=$(logical_digest PhaseTraining/Resources/coach.db)

if [ "$committed_digest" != "$rebuilt_digest" ]; then
    echo "::error::coach.db content out of sync with db/source — rebuild from source and commit." >&2
    exit 1
fi

echo "coach.db is in sync with db/source ✓ (compared logical content)"
