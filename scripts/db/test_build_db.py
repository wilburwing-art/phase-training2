"""Tests for build_db.py's rename guard. Run: python3 -m unittest scripts/db/test_build_db.py"""

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_db  # noqa: E402


class RenameGuardTests(unittest.TestCase):

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.shipped = self.tmp / "shipped.db"
        c = sqlite3.connect(self.shipped)
        c.execute("CREATE TABLE exercises (id INTEGER PRIMARY KEY, name TEXT)")
        c.executemany("INSERT INTO exercises VALUES (?, ?)", [(1, "Bench Press"), (2, "Pull-Up"), (3, "Plank")])
        c.commit()
        c.close()

    def write_source(self, exercises, aliases):
        (self.tmp / "exercises.json").write_text(json.dumps([{"id": i, "name": n} for i, n in exercises]))
        (self.tmp / "exercise_aliases.json").write_text(json.dumps(
            [{"id": k, "exercise_id": i, "alias": a} for k, (i, a) in enumerate(aliases)]))

    def test_unchanged_names_pass(self):
        self.write_source([(1, "Bench Press"), (2, "Pull-Up"), (3, "Plank")], [])
        self.assertEqual(build_db.renamed_without_alias(self.shipped, self.tmp), [])

    def test_rename_without_alias_is_reported(self):
        self.write_source([(1, "Barbell Bench Press"), (2, "Pull-Up"), (3, "Plank")], [])
        self.assertEqual(build_db.renamed_without_alias(self.shipped, self.tmp),
                         [(1, "Bench Press", "Barbell Bench Press")])

    def test_rename_with_old_name_as_alias_passes_case_insensitively(self):
        self.write_source([(1, "Barbell Bench Press"), (2, "Pull-Up"), (3, "Plank")], [(1, "bench press")])
        self.assertEqual(build_db.renamed_without_alias(self.shipped, self.tmp), [])

    def test_new_and_deleted_exercises_are_not_renames(self):
        self.write_source([(1, "Bench Press"), (2, "Pull-Up"), (4, "Nordic Curl")], [])
        self.assertEqual(build_db.renamed_without_alias(self.shipped, self.tmp), [])

    def test_no_shipped_db_means_nothing_to_guard(self):
        self.write_source([(1, "X")], [])
        self.assertEqual(build_db.renamed_without_alias(self.tmp / "absent.db", self.tmp), [])


if __name__ == "__main__":
    unittest.main()
