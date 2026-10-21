"""S5 small items from the 2026-10-21 AI review.

- AISmart_Heal values Rest's status cure (heal.asm cures burn, paralysis, poison,
  freeze): below half HP it is encouraged, healthy it is no longer discouraged.
- AIRedundant_Transform eliminates Transform when either side is transformed
  (transform.asm makes it fail).
maxHP is 200 in the shared fixture (quarter 50, half 100).
"""
from __future__ import annotations

import unittest

import test_ai_heuristic_gaps as gaps  # module import: its test classes are not re-collected here


class S5SmallTest(gaps._MoveLayerGapsBase):
    def test_rest_with_a_status_to_cure(self) -> None:
        brn = {"wEnemyMonStatus": 1 << self.battle["BRN"]}
        # Control: a plain Recover is unchanged by the enemy's status.
        self.assertEqual(self.smart_score("RECOVER", {"wEnemyMonHP": (150,), **brn}), 22)
        self.assertEqual(self.smart_score("REST", {"wEnemyMonHP": (70,), **brn}), 18)   # cure + heal
        self.assertEqual(self.smart_score("REST", {"wEnemyMonHP": (150,), **brn}), 20)  # no longer discouraged
        self.assertEqual(self.smart_score("REST", {"wEnemyMonHP": (150,)}), 22)         # nothing to cure

    def test_rest_over_sleep_alone_is_not_a_cure(self) -> None:
        self.assertEqual(self.smart_score("REST", {"wEnemyMonHP": (150,), "wEnemyMonStatus": 2}), 22)

    def test_transform_redundant_once_either_side_is_transformed(self) -> None:
        t = 1 << self.battle["TRANSFORMED"]
        self.assertEqual(self.redundant_score("TRANSFORM"), 20)
        self.assertEqual(self.redundant_score("TRANSFORM", {"wEnemyBattleStatus3": t}), 79)
        self.assertEqual(self.redundant_score("TRANSFORM", {"wPlayerBattleStatus3": t}), 79)


if __name__ == "__main__":
    unittest.main()
