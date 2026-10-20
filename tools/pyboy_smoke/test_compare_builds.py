"""Build comparison bookkeeping (compare_builds.py): where two runs of a seed
part ways, and which failures or checks only one build hits. Source-only: no
emulator, synthetic run rows."""
import unittest

import compare_builds


def ev(frame, kind, **fields):
    return {"frame": frame, "kind": kind, **fields}


def row(seed, outcome="blackout", anomalies=()):
    return {"seed": seed, "outcome": outcome, "anomalies": [{"check": c} for c in anomalies],
            "run_records": [], "report": None}


class FirstSplitTest(unittest.TestCase):
    def test_frames_do_not_split_runs(self) -> None:
        a = [ev(0, "start", map="PALLET_TOWN"), ev(900, "enter_map", map="OAKS_LAB")]
        b = [ev(0, "start", map="PALLET_TOWN"), ev(960, "enter_map", map="OAKS_LAB")]
        split = compare_builds.first_split(a, b)
        self.assertTrue(split["identical"])
        self.assertEqual(split["shared_events"], 2)

    def test_split_names_both_sides_and_the_gap_before(self) -> None:
        a = [ev(0, "start", map="PALLET_TOWN"), ev(700, "enter_map", map="OAKS_LAB"),
             ev(1500, "battle_start", opponent="RIVAL1")]
        b = [ev(0, "start", map="PALLET_TOWN"), ev(750, "enter_map", map="OAKS_LAB"),
             ev(1400, "enter_map", map="PALLET_TOWN")]
        split = compare_builds.first_split(a, b)
        self.assertFalse(split["identical"])
        self.assertEqual(split["shared_events"], 2)
        self.assertEqual(split["frame_gap_before"], 50)
        self.assertEqual([e["kind"] for e in split["split"]], ["battle_start", "enter_map"])

    def test_a_run_that_ends_early_splits_at_its_end(self) -> None:
        a = [ev(0, "start", map="PALLET_TOWN")]
        b = [ev(0, "start", map="PALLET_TOWN"), ev(10, "blackout", map="ROUTE_1")]
        split = compare_builds.first_split(a, b)
        self.assertEqual(split["split"][0], None)
        self.assertFalse(split["identical"])

    def test_only_path_events_are_compared(self) -> None:
        report = {"events": [ev(0, "start", map="X"), ev(5, "no_path", goals="door"),
                             ev(9, "buy", item="POTION")]}
        self.assertEqual([e["kind"] for e in compare_builds.path_events(report)], ["start"])


class OnlyInOneBuildTest(unittest.TestCase):
    def test_a_check_or_failure_one_build_never_hits_is_flagged(self) -> None:
        results = {
            "pokeblue_debug": {1: row(1), 2: row(2, anomalies=["party"])},
            "pokeblue": {1: row(1, outcome="stalled"), 2: row(2, anomalies=["party"])},
        }
        report = compare_builds.compare(results)
        self.assertEqual([(r["build"], r["what"], r["seeds"]) for r in report["only_in_one_build"]],
                         [("pokeblue", "stalled", [1])])
        self.assertEqual(report["totals"]["pokeblue"]["failed_seeds"], [1])


if __name__ == "__main__":
    unittest.main()
