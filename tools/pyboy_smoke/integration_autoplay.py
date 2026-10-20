from __future__ import annotations

import unittest

import autoplay


class AutoplayIntegrationTest(unittest.TestCase):
    """The autoplay agent plays the first stages of a seeded run through real
    input: lobby doors, trainer fights, the reward picker and the walk back.

    Seed 2 currently opens with a trainer stage, a gym and a procedural cave.
    Which stages a seed rolls is allowed to change as the game does, so only
    the outcome is asserted; a failed run leaves its report, screenshot and
    state dump in artifacts/ (rerun with autoplay.py --seed 2 --stages 3)."""

    def test_seeded_run_clears_three_stages(self) -> None:
        data = autoplay.play(2, stages=3, max_frames=200_000)
        summary = {key: data[key] for key in ("outcome", "detail", "stages_cleared", "battles_won")}
        self.assertEqual(data["outcome"], "completed", summary)
        self.assertEqual(data["stages_cleared"], 3, summary)
        self.assertGreaterEqual(data["battles_won"], 4, summary)
        self.assertEqual(data["blackouts"], 0, summary)
        self.assertEqual(data["anomalies"], [], summary)

    def test_new_game_plays_into_a_second_run(self) -> None:
        """From power-on: title screen, NEW GAME, naming, the intro tour, a
        starter and the rival in Oak's Lab, a run to its end, then the Silph
        Co hub back into the next run."""
        data = autoplay.play(1, new_game=True, runs=2, max_frames=300_000)
        summary = {key: data[key] for key in ("outcome", "detail", "runs")}
        self.assertEqual(data["outcome"], "completed", summary)
        self.assertEqual(len(data["runs"]), 2, summary)
        self.assertEqual(data["anomalies"], [], summary)
        for run in data["runs"]:
            self.assertIn(run["outcome"], ("champion", "blackout"), summary)
            self.assertGreaterEqual(run["battles_won"], 1, summary)


if __name__ == "__main__":
    unittest.main(verbosity=2)
