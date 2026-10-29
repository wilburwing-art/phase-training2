#!/usr/bin/env bash
# Browse coach.db and a schema-only user.db in Datasette at http://127.0.0.1:8001
#   scripts/schema/browse.sh
# Pass a real device user.db (e.g. pulled from a simulator container) to inspect data:
#   scripts/schema/browse.sh path/to/user.db
set -euo pipefail
cd "$(dirname "$0")/../.."

user_db="${1:-}"
if [[ -z "$user_db" ]]; then
  uv run scripts/schema/build_user_db.py >/dev/null
  user_db=build/schema/user.db
fi

# --immutable opens read-only. Pinned: 1.0 moves facets out of metadata into -c config.
exec uvx datasette@0.65.5 serve --immutable db/coach.db --immutable "$user_db" \
  --metadata docs/schema/datasette.yml --port 8001 --setting sql_time_limit_ms 5000
