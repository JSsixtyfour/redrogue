"""Balance Phase 0: wild battles pay the same EXP as trainer battles.

Vanilla Gen 1 applies BoostExp (x1.5) only to trainer battles, so a wild mon
of the same species and level paid 2/3 as much. Wild areas and their bosses
(OW_POKEMON, so wild battles too) were the losers. WILD_EXP_MATCHES_TRAINER in
constants/balance_constants.asm now decides it, and this test checks the built
ROM agrees with whatever that knob says.

Method: run GainExperience from a parked FIGHT2 battle, once with hIsInBattle
= 1 (wild) and once with 2 (trainer), and read the EXP total at
GainExperience.noWitchExpBoost - after every multiplier, before any text. The
routine prints and waits for VBlank past that point, so it is probed rather
than called (see harness.probe_routine_until).

The trainer value is also checked against the formula, so a seam that read
two zeroes, or read before the boost ran, cannot pass as "equal".
"""
import unittest

from source_constants import parse_rgbds_constants
from harness import RedRogueHarness
from test_smoke import ARTIFACTS, HarnessTestCase, REPO_ROOT

BASE_EXP = 100
ENEMY_LEVEL = 20
WILD, TRAINER = 1, 2


def boosted(value: int) -> int:
    """BoostExp: value + value/2, floor."""
    return value + (value >> 1)


class WildExpParityTest(HarnessTestCase):
    def exp_for(self, battle_kind: int) -> int:
        harness = self.harness
        assert harness is not None
        harness.boot_fight2(seed=1)
        captured: list[int] = []
        quotient = harness.address("hQuotient")

        def capture() -> None:
            memory = harness.pyboy.memory
            captured.append((memory[quotient + 2] << 8) | memory[quotient + 3])

        seam = harness.hook_flag("GainExperience.noWitchExpBoost", capture)

        harness.write8("hIsInBattle", battle_kind)
        harness.write8("wLinkState", 0)
        harness.write8("wEnemyMonBaseExp", BASE_EXP)
        harness.write8("wEnemyMonLevel", ENEMY_LEVEL)
        harness.write8("wPartyGainExpFlags", 1)      # party slot 0 only
        harness.write8("wWitchPrizesEarned", 0)      # no +10% witch prize
        # Same OT as the player, so the traded-mon boost cannot fire.
        harness.write8("wPartyMon1OTID", harness.read8("wPlayerID"))
        harness.write8("wPartyMon1OTID", harness.read8("wPlayerID", 1), 1)

        harness.probe_routine_until("GainExperience", lambda: seam["count"] > 0)
        self.assertTrue(captured, "GainExperience never reached .noWitchExpBoost")
        return captured[0]

    def test_wild_exp_matches_knob(self) -> None:
        knob = parse_rgbds_constants(
            REPO_ROOT / "constants/balance_constants.asm"
        )["WILD_EXP_MATCHES_TRAINER"]
        base = BASE_EXP * ENEMY_LEVEL // 7

        trainer = self.exp_for(TRAINER)
        self.harness.close()
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        wild = self.exp_for(WILD)

        self.assertEqual(trainer, boosted(base), "trainer EXP != formula x1.5")
        if knob:
            self.assertEqual(wild, trainer)
        else:
            self.assertEqual(wild, base)


if __name__ == "__main__":
    unittest.main()
