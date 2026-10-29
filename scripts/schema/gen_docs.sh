#!/usr/bin/env bash
# Regenerate the schema docs under docs/schema/ from the real databases.
#   scripts/schema/gen_docs.sh          regenerate
#   scripts/schema/gen_docs.sh --check  fail if committed docs are stale (tbls diff)
# Needs: tbls (brew install k1LoW/tap/tbls), sourcery, d2 (brew), uv, node (npx for Liam).
set -euo pipefail
cd "$(dirname "$0")/../.."

uv run scripts/schema/build_user_db.py

if [[ "${1:-}" == "--check" ]]; then
  tbls diff -c docs/schema/tbls-coach.yml
  tbls diff -c docs/schema/tbls-user.yml
  echo "schema docs are current"
  exit 0
fi

tbls doc -c docs/schema/tbls-coach.yml --rm-dist
tbls doc -c docs/schema/tbls-user.yml --rm-dist
tbls lint -c docs/schema/tbls-user.yml
# coach.db lint is informational: routine_exercises.exercise_id has no index.
tbls lint -c docs/schema/tbls-coach.yml || true

# UserDefaults layer (Sourcery): key registry with wipe/backup coverage, and
# every Codable struct's stored properties.
rm -rf build/sourcery
sourcery --sources PhaseTraining --sources Shared --templates scripts/schema/templates \
  --output build/sourcery --disableCache --quiet
cp build/sourcery/codable-models.md docs/schema/codable-models.md
uv run scripts/schema/userdefaults_registry.py build/sourcery/userdefaults-keys.tsv

# Interactive ERD sites (Liam) from the tbls schema.json. Output is gitignored.
# View: npx http-server -c-1 build/erd/coach
# Liam reads declared FKs only; the tbls `relations:` entries do not carry over.
for db in coach user; do
  npx -y @liam-hq/cli@0.7.24 erd build --format tbls \
    --input "docs/schema/$db/schema.json" --output-dir "build/erd/$db" >/dev/null
done
echo "ERD sites: build/erd/coach, build/erd/user"

# D2 diagrams: every docs/schema/*.d2 -> .svg (ELK layout; sequence diagrams ignore it).
for f in docs/schema/*.d2; do
  d2 --layout=elk "$f" "${f%.d2}.svg"
done
