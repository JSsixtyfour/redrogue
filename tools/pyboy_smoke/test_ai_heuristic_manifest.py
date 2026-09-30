"""Guard for the reviewed AI heuristic coverage manifest (AI_BACKLOG L3).

Pure Python, no ROM. Keeps three things in step:
- the source-derived inventory (ai_heuristics.py, parsed from the dispatch
  tables) and the manifest's entries, so a new or renamed heuristic cannot go
  unlisted and a deleted one cannot linger;
- every test the manifest cites, which must exist;
- the number of declared gaps (cases with no asserting test), which may only
  go DOWN: lower MAX_GAPS when a gap is closed.

To see which tests EXECUTE a heuristic (a starting point for filling a gap, not
proof of coverage), run the suite with REDROGUE_AI_COVERAGE=<file.jsonl>.
"""
import ast
import json
from pathlib import Path
import unittest

import ai_heuristics

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MANIFEST = HERE / "ai_heuristic_manifest.json"
MAX_GAPS = 127  # measured 2026-09-30; ratchet down as gaps close
CASES = ("positive", "negative", "boundary")


def existing_test_ids() -> set[str]:
    ids = set()
    for path in HERE.glob("test_*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for cls in tree.body:
            if isinstance(cls, ast.ClassDef):
                for fn in cls.body:
                    if isinstance(fn, ast.FunctionDef) and fn.name.startswith("test"):
                        ids.add(f"{path.stem}.{cls.name}.{fn.name}")
    return ids


class AIHeuristicManifestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))["heuristics"]
        cls.inventory = ai_heuristics.inventory(ROOT)

    def test_manifest_matches_the_source_inventory(self):
        missing = sorted(set(self.inventory) - set(self.manifest))
        stale = sorted(set(self.manifest) - set(self.inventory))
        self.assertEqual(missing, [], "heuristics in source but not in the manifest")
        self.assertEqual(stale, [], "manifest entries with no heuristic in source")

    def test_every_cited_test_exists(self):
        known = existing_test_ids()
        cited = {t for entry in self.manifest.values() for case in CASES
                 for t in entry.get(case, {}).get("tests", [])}
        self.assertEqual(sorted(cited - known), [])

    def test_every_entry_states_its_requirements(self):
        for key, entry in self.manifest.items():
            with self.subTest(key):
                self.assertTrue(entry.get("summary"))
                for case in ("positive", "negative"):
                    self.assertTrue(entry[case]["requirement"], f"{key} {case}")

    def test_declared_gaps_only_shrink(self):
        gaps = [(key, case) for key, entry in self.manifest.items() for case in CASES
                if case in entry and not entry[case]["tests"]]
        untested = sorted({key for key, _ in gaps
                           if not any(self.manifest[key][c]["tests"]
                                      for c in CASES if c in self.manifest[key])})
        print(f"\nAI heuristic manifest: {len(self.manifest)} heuristics, {len(gaps)} gap "
              f"cases, {len(untested)} with no asserting test at all")
        self.assertLessEqual(len(gaps), MAX_GAPS,
                             "a new gap was declared; add the test instead")


if __name__ == "__main__":
    unittest.main(verbosity=2)
