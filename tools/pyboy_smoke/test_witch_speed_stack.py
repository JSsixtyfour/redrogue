"""Every player stat-stage effect keeps the earned boost and witch challenge 8.

ApplySingleEarnedStatBoost runs after the battle engine rebuilt one stat from its
unmodified copy, so it must recognise every stat-mod effect range. It used to reduce
only the +1 range to a stat index and returned early for the rest, which lost the
Speed halving after String Shot or Agility and the Special boost after Amnesia.
"""
from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
EFFECTS = parse_rgbds_constants(REPO_ROOT / "constants/move_effect_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")

STATS = ("Attack", "Defense", "Speed", "Special")
UP = tuple(f"{stat.upper()}_UP{n}_EFFECT" for stat in STATS for n in (1, 2))
DOWN = tuple(f"{stat.upper()}_{kind}_EFFECT" for stat in STATS for kind in ("DOWN1", "DOWN2", "DOWN_SIDE"))
NO_STORED_STAT = tuple(f"{stat}_{kind}_EFFECT" for stat in ("ACCURACY", "EVASION")
                       for kind in ("UP1", "UP2", "DOWN1", "DOWN2"))
START = 800


class WitchSpeedStackTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        cls.h.boot_to_lobby()
        cls.baseline = io.BytesIO()
        cls.h.save_state(cls.baseline)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.h.close()

    def stat(self, name: str) -> int:
        return self.h.read8(f"wBattleMon{name}") << 8 | self.h.read8(f"wBattleMon{name}", 1)

    def run_effect(self, effect: str, *, turn: int, earned: int, sluggish: bool) -> dict[str, int]:
        h = self.h
        h.load_state(self.baseline)
        h.write8("wLinkState", 0)
        h.write8("wEarnedStatBoosts", earned)
        h.write8("wWitchChallenge", RAM["CHALLENGE_SLOWED_POKEMON"] if sluggish else 0)
        flags = h.read8("wRogueFlagsBitfield") & ~(1 << RAM["BIT_WITCH_ACCEPTED"])
        h.write8("wRogueFlagsBitfield", flags | (1 << RAM["BIT_WITCH_ACCEPTED"] if sluggish else 0))
        for name in STATS:
            h.write8(f"wBattleMon{name}", START >> 8)
            h.write8(f"wBattleMon{name}", START & 0xFF, offset=1)
        h.write8("hWhoseTurn", turn)
        h.write8("wPlayerMoveEffect" if turn == 0 else "wEnemyMoveEffect", EFFECTS[effect])
        h.call_routine("ApplySingleEarnedStatBoost")
        return {name: self.stat(name) for name in STATS}

    def expected(self, changed: str, *, earned: int, sluggish: bool) -> dict[str, int]:
        result = dict.fromkeys(STATS, START)
        value = START
        if changed == "Speed" and sluggish:
            value //= 2
        if earned >> STATS.index(changed) & 1:
            value += value // 8
        result[changed] = value
        return result

    def test_every_stat_effect_on_the_player(self) -> None:
        for earned, sluggish in ((0x0F, True), (0x0F, False), (0x00, True), (0x00, False)):
            for turn, names in ((0, UP), (1, DOWN)):
                for effect in names:
                    with self.subTest(effect=effect, earned=earned, sluggish=sluggish):
                        changed = next(s for s in STATS if effect.startswith(s.upper()))
                        self.assertEqual(self.run_effect(effect, turn=turn, earned=earned, sluggish=sluggish),
                                         self.expected(changed, earned=earned, sluggish=sluggish))

    def test_the_enemys_stat_changes_leave_the_player_alone(self) -> None:
        untouched = dict.fromkeys(STATS, START)
        for turn, names in ((1, UP), (0, DOWN)):
            for effect in names:
                with self.subTest(effect=effect):
                    self.assertEqual(self.run_effect(effect, turn=turn, earned=0x0F, sluggish=True), untouched)

    def test_accuracy_and_evasion_rebuild_nothing(self) -> None:
        untouched = dict.fromkeys(STATS, START)
        for effect in NO_STORED_STAT:
            turn = 0 if "_UP" in effect else 1
            with self.subTest(effect=effect):
                self.assertEqual(self.run_effect(effect, turn=turn, earned=0x0F, sluggish=True), untouched)

    def test_speed_floor_after_halving(self) -> None:
        h = self.h
        self.run_effect("SPEED_UP1_EFFECT", turn=0, earned=0, sluggish=True)
        h.write8("wBattleMonSpeed", 0)
        h.write8("wBattleMonSpeed", 1, offset=1)
        h.call_routine("HalvePlayerSpeedIfSluggish")
        self.assertEqual(self.stat("Speed"), 1)

    # The player's Transform copies the target's stats, then this restores the effects.
    def run_transform(self, *, turn: int, status: int) -> int:
        h = self.h
        h.load_state(self.baseline)
        h.write8("wLinkState", 0)
        h.write8("wEarnedStatBoosts", 1 << STATS.index("Speed"))
        h.write8("wWitchChallenge", RAM["CHALLENGE_SLOWED_POKEMON"])
        h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | 1 << RAM["BIT_WITCH_ACCEPTED"])
        h.write8("wBattleMonStatus", status)
        h.write8("wBattleMonSpeed", START >> 8)
        h.write8("wBattleMonSpeed", START & 0xFF, offset=1)
        h.write8("hWhoseTurn", turn)
        h.call_routine("ReapplyPlayerStatEffectsAfterTransform")
        self.assertEqual(h.read8("hWhoseTurn"), turn)
        return self.stat("Speed")

    def test_player_transform_stacks_boost_halving_and_paralysis(self) -> None:
        boosted = START + START // 8
        self.assertEqual(self.run_transform(turn=0, status=0), boosted // 2)
        self.assertEqual(self.run_transform(turn=0, status=1 << 6), boosted // 2 // 4)

    def test_enemy_transform_leaves_the_player_alone(self) -> None:
        self.assertEqual(self.run_transform(turn=1, status=1 << 6), START)


if __name__ == "__main__":
    unittest.main()
