"""Coverage-map identity and comparison tests; no emulator or ROM build."""
import unittest
from unittest.mock import patch

import autoplay_coverage


def summary(*, counts=None, files=None, once=(), dead=()):
    data = {
        "totals": {"routines": 0, "routines_run": 0},
        "files": files or {},
        "once": list(once),
        "known_dead": {"scoped": list(dead)} if dead else {},
    }
    if counts is not None:
        data["routine_identity"] = "source-name-v1"
        data["routine_run_counts"] = counts
        data["routine_names"] = {
            identity: identity.rsplit("::", 1)[-1] for identity in counts
        }
        data["routine_files"] = {
            identity: identity.rsplit("::", 1)[0] for identity in counts
        }
    return data


class SummariseTest(unittest.TestCase):
    def test_keeps_complete_routine_identity_and_hit_counts(self):
        labels = [
            {"name": "RoutineA", "file": "a.asm", "global": True},
            {"name": "RoutineA.loop", "file": "a.asm", "global": False},
            {"name": "RoutineB", "file": "b.asm", "global": True},
        ]
        with patch.object(autoplay_coverage.coverage_inventory, "plan",
                          return_value=(labels, {"RoutineA": (0, 0)}, {})):
            result = autoplay_coverage.summarise({"seed1": ["RoutineA"], "seed2": []})

        self.assertEqual(result["routine_run_counts"],
                         {"a.asm::RoutineA": 1, "b.asm::RoutineB": 0})
        self.assertEqual(result["routine_files"],
                         {"a.asm::RoutineA": "a.asm", "b.asm::RoutineB": "b.asm"})
        self.assertEqual(result["files"]["b.asm"]["never"], ["RoutineB"])
        self.assertEqual(result["files"]["a.asm"]["branches_never"], ["RoutineA.loop"])


class CompareTest(unittest.TestCase):
    def test_complete_inventory_distinguishes_hits_from_added_and_removed_names(self):
        old = summary(counts={"a.asm::Keep": 0, "a.asm::ItemUseBall": 0,
                              "a.asm::OldRoutine": 3},
                      dead=("ItemUseBall",))
        new = summary(counts={"a.asm::Keep": 2, "a.asm::ItemUseBall": 4,
                              "a.asm::NewRoutine": 0},
                      dead=("ItemUseBall",))

        result = autoplay_coverage.compare(old, new)

        self.assertEqual(result["gained"], ["a.asm::Keep"])
        self.assertEqual(result["lost"], [])
        self.assertEqual(result["removed"], ["a.asm::OldRoutine"])
        self.assertEqual(result["added"], ["a.asm::NewRoutine"])
        self.assertTrue(result["inventory_complete"])

    def test_legacy_never_and_once_evidence_is_conservative_about_dead_entries(self):
        old = summary(files={"a.asm": {"never": ["NeverRoutine", "ItemUseBall"]}},
                      once=("OnceRoutine",), dead=("ItemUseBall",))
        new = summary(counts={"a.asm::NeverRoutine": 1, "a.asm::OnceRoutine": 0,
                              "a.asm::ItemUseBall": 3},
                      dead=("ItemUseBall",))

        result = autoplay_coverage.compare(old, new)

        self.assertEqual(result["gained"], ["a.asm::NeverRoutine"])
        self.assertEqual(result["lost"], ["a.asm::OnceRoutine"])
        self.assertNotIn("ItemUseBall", result["gained"] + result["lost"])
        self.assertFalse(result["inventory_complete"])

    def test_same_label_moved_to_another_source_is_inventory_drift(self):
        old = summary(counts={"old.asm::Shared": 0})
        new = summary(counts={"new.asm::Shared": 1})

        result = autoplay_coverage.compare(old, new)

        self.assertEqual(result["gained"], [])
        self.assertEqual(result["removed"], ["old.asm::Shared"])
        self.assertEqual(result["added"], ["new.asm::Shared"])

    def test_two_legacy_maps_do_not_turn_inventory_drift_into_coverage_claims(self):
        old = summary(files={"a.asm": {"never": ["OldName", "Shared"]}})
        new = summary(files={"a.asm": {"never": ["Shared", "NewName"]}})

        result = autoplay_coverage.compare(old, new)

        self.assertEqual(result["gained"], [])
        self.assertEqual(result["lost"], [])
        self.assertEqual(result["uncertain"], ["a.asm::NewName", "a.asm::OldName"])
        self.assertFalse(result["inventory_complete"])


if __name__ == "__main__":
    unittest.main()
