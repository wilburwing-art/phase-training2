# Schema docs

Generated from the real databases and Swift source. Regenerate with `scripts/schema/gen_docs.sh`; check for drift with `scripts/schema/gen_docs.sh --check`.

| Path | What | Tool |
|---|---|---|
| [coach/](coach/README.md) | Bundled catalog `db/coach.db`: ERD plus one page per table | tbls |
| [user/](user/README.md) | On-device `user.db`, built from the migrations in `UserDatabase.swift` | tbls |
| [userdefaults-keys.md](userdefaults-keys.md) | Every UserDefaults key, whether Erase All Data deletes it, whether the backup carries it | Sourcery |
| [codable-models.md](codable-models.md) | Every Codable struct and its stored properties | Sourcery |
| [architecture.svg](architecture.svg) | App architecture, from [architecture.d2](architecture.d2) | D2 |
| `build/erd/coach`, `build/erd/user` | Interactive ERDs, gitignored. View with `npx http-server -c-1 build/erd/coach` | Liam |

Browse either database with facets: `scripts/schema/browse.sh` (Datasette at http://127.0.0.1:8001). Pass a real `user.db` path to inspect device data.

Tools: `brew install k1LoW/tap/tbls sourcery d2`, plus `uv` and `node`.
