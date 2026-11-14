"""Super Transform takes the target's max HP and current HP (2026-11-11).

SuperTransformEffect_ (engine/battle/move_effects/transform.asm) copies the
target's max HP along with the other stats, then its current HP. Only the
battle copy borrows that pool: every battle-to-party write-back ends in
ClampPartyMonHPToMax, so the party mon never holds more than its own max HP.

The battle test plays the move through the menu: a Ditto against a Snorlax
whose HP is set just under its max. Snorlax only knows SPLASH, so no damage
muddies the numbers. The write-back test calls ReadPlayerMonCurHPAndStatus
directly on the boundary cases.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
TRANSFORMED_BIT = 3


class SuperTransformHPTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.h.inject_fight2_spec(
            [{"species": species["DITTO"], "level": 50, "moves": [moves["SUPER_TRANSFORM"]]}],
            [{"species": species["SNORLAX"], "level": 50, "moves": [moves["SPLASH"]]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)

    def tearDown(self) -> None:
        self.h.close()

    def word(self, label: str, offset: int = 0) -> int:
        return (self.h.read8(label, offset) << 8) | self.h.read8(label, offset + 1)

    def set_word(self, label: str, value: int, offset: int = 0) -> None:
        self.h.write8(label, value >> 8, offset)
        self.h.write8(label, value & 0xFF, offset + 1)

    def test_borrows_the_targets_pool_and_the_party_keeps_its_own(self) -> None:
        h = self.h
        snap = {}

        def at_transform_end() -> None:
            snap.update(hp=self.word("wBattleMonHP"), max=self.word("wBattleMonMaxHP"),
                        status3=h.read8("wPlayerBattleStatus3"))

        transformed = h.hook_flag("ReapplyPlayerStatEffectsAfterTransform", at_transform_end)
        loops = h.hook_flag("MainInBattleLoop")
        h.boot_fight2(seed=1)

        own_max = self.word("wPartyMon1MaxHP")
        enemy_max = self.word("wEnemyMonMaxHP")
        self.assertGreater(enemy_max, own_max + 20, "Snorlax must out-HP Ditto for this test")
        enemy_hp = enemy_max - 7  # above Ditto's own max, below Snorlax's
        self.set_word("wEnemyMonHP", enemy_hp)

        start_loops = loops["count"]
        for _ in range(400):
            h.tap("a", 1)
            h.tick(8)
            if transformed["count"] and loops["count"] > start_loops:
                break
        self.assertTrue(transformed["count"], "Super Transform never finished")
        self.assertTrue(snap["status3"] & (1 << TRANSFORMED_BIT))
        self.assertEqual(snap["max"], enemy_max, "battle max HP is the target's")
        self.assertEqual(snap["hp"], enemy_hp, "battle HP is the target's current HP")

        self.assertGreater(loops["count"], start_loops, "the next turn never started")
        self.assertEqual(self.word("wPartyMon1MaxHP"), own_max,
                         "the party max HP is never touched")
        self.assertEqual(self.word("wPartyMon1HP"), own_max,
                         "the write-back caps HP at the party mon's own max HP")
        self.assertEqual(self.word("wBattleMonMaxHP"), enemy_max, "the battle pool stays borrowed")

    def run_slot_two_level_up(self, move: str) -> None:
        """A Transformed mon in party slot 2 levels up mid-battle.

        GainExperience's in-battle check used to load wPlayerMonNumber into b,
        and .transformedLevelUp then added bc as "max HP gained": 256 per party
        index on top of the real gain. Slot 1 hid it (b = 0). Ditto leads from
        slot 2 because slot 1 is fainted at the first send-out; its level byte
        is lowered by one at GainExperience entry so the award crosses exactly
        one level with a known party max HP change.
        """
        h = self.h
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h.inject_fight2_spec(
            [{"species": species["MAGIKARP"], "level": 50, "moves": [moves["SPLASH"]]},
             {"species": species["DITTO"], "level": 50, "moves": [moves[move]]}],
            [{"species": species["SNORLAX"], "level": 50,
              "moves": [moves["TACKLE"], moves["SPLASH"]]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)

        h.register_hook("StartBattle.playerSendOutFirstMon",
                        lambda _: self.set_word("wPartyMon1HP", 0))
        transformed = h.hook_flag(
            "ReapplyPlayerStatEffectsAfterTransform",
            lambda: self.set_word("wEnemyMonHP", 1))
        before, after = {}, {}

        def at_gain() -> None:
            if before:
                return
            h.write8("wPartyMon2Level", h.read8("wPartyMon2Level") - 1)
            before.update(battle=self.word("wBattleMonMaxHP"),
                          party=self.word("wPartyMon2MaxHP"),
                          active=h.read8("wPlayerMonNumber"),
                          status3=h.read8("wPlayerBattleStatus3"))

        h.hook_flag("GainExperience", at_gain)
        h.hook_flag("GainExperience.recalcStatChanges",
                    lambda: after or after.update(battle=self.word("wBattleMonMaxHP"),
                                                  party=self.word("wPartyMon2MaxHP")))
        crashed = h.hook_flag("CrashScreen")
        h.boot_fight2(seed=1)
        for _ in range(900):
            if after or crashed["count"]:
                break
            h.tap("a", 1)
            h.tick(8)
        self.assertEqual(crashed["count"], 0)
        self.assertTrue(transformed["count"], f"{move} never finished")
        self.assertTrue(after, "the Transformed mon never levelled up in battle")
        self.assertEqual(before["active"], 1, "Ditto must be the active mon, from slot 2")
        self.assertTrue(before["status3"] & (1 << TRANSFORMED_BIT))
        gain = after["party"] - before["party"]
        self.assertLess(gain, 256)
        self.assertEqual(after["battle"] - before["battle"], gain,
                         "battle max HP grows by exactly the party's max HP gain")

    def test_slot_two_level_up_after_transform(self) -> None:
        self.run_slot_two_level_up("TRANSFORM")

    def test_slot_two_level_up_after_super_transform(self) -> None:
        self.run_slot_two_level_up("SUPER_TRANSFORM")

    def test_write_back_caps_only_above_max(self) -> None:
        h = self.h
        h.boot_fight2(seed=1)
        party_max = 0x0123
        cases = [  # battle HP -> expected party HP
            (0x0000, 0x0000),
            (0x0122, 0x0122),
            (0x0123, 0x0123),
            (0x0124, 0x0123),   # low byte above
            (0x0200, 0x0123),   # high byte above
            (0x00FF, 0x00FF),   # high byte below, low byte above max's
        ]
        for battle_hp, expected in cases:
            with self.subTest(battle_hp=hex(battle_hp)):
                h.park_before_hijack()
                h.write8("wPlayerMonNumber", 0)
                self.set_word("wPartyMon1MaxHP", party_max)
                self.set_word("wBattleMonHP", battle_hp)
                h.call_routine("ReadPlayerMonCurHPAndStatus", limit=600)
                self.assertEqual(self.word("wPartyMon1HP"), expected)
                self.assertEqual(self.word("wPartyMon1MaxHP"), party_max)


if __name__ == "__main__":
    unittest.main()
