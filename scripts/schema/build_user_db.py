"""Build a schema-only user.db from the migrations in UserDatabase.swift.

The app creates user.db at runtime, so there is no file on disk for schema
tools (tbls, datasette) to read. This script pulls every SQL string literal out
of the `migrations` array, applies them in order to a fresh SQLite file, and
stamps `PRAGMA user_version` the same way the app does.

    uv run scripts/schema/build_user_db.py [out_path]

Default output: build/schema/user.db (gitignored build dir).
"""

import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SWIFT = REPO / "PhaseTraining" / "Data" / "UserDatabase.swift"
DEFAULT_OUT = REPO / "build" / "schema" / "user.db"

# One migration entry: `(N, [ ... ])`. Statements are either Swift multi-line
# literals ("""...""") or single-line literals ("...").
ENTRY = re.compile(r"\(\s*(\d+)\s*,\s*\[(.*?)\]\s*\)", re.S)
LITERAL = re.compile(r'"""\n(.*?)\n\s*"""|"((?:[^"\\\n]|\\.)*)"', re.S)


def migrations(source: str) -> list[tuple[int, list[str]]]:
    start = source.index("private static let migrations")
    end = source.index("static var latestSchemaVersion", start)
    block = source[start:end]
    out = []
    for version, body in ENTRY.findall(block):
        stmts = []
        for multi, single in LITERAL.findall(body):
            sql = (multi or single).strip()
            if sql:
                stmts.append(sql)
        out.append((int(version), stmts))
    return out


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)

    found = migrations(SWIFT.read_text())
    if not found:
        sys.exit(f"no migrations parsed from {SWIFT}")

    db = sqlite3.connect(out)
    db.execute("PRAGMA foreign_keys = ON")
    for version, stmts in found:
        with db:
            for sql in stmts:
                db.execute(sql)
            db.execute(f"PRAGMA user_version = {version}")
    tables = [r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    db.close()

    total = sum(len(s) for _, s in found)
    print(f"{out}: {len(found)} migrations, {total} statements, "
          f"user_version={found[-1][0]}, {len(tables)} tables: {', '.join(tables)}")


if __name__ == "__main__":
    main()
