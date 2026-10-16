"""Shin Red import Phase 13 (2026-10-16): gap-scan battle fixes.

Probed directly in a live FIGHT 2 battle:
  13.1  AnyMoveToSelect masks PP Ups, so Struggle triggers with a Disabled move
        and every other move at 0 PP carrying PP Ups.
  13.3  BattleRoundStartFixups restores Rage/Thrash accuracy and clears
        MOVING_SECOND each round.
  13.6  Haze zeroes both toxic counters and cures both sides' status; a cured
        sleeper loses its stale move unless it is locked into one.
  13.7  DisableEffect's fresh n + 8 encoding, decoded by DisableCounterFixup.

Not probed here: Rest (13.2), the AI HUD redraw (13.4) and Substitute (13.5)
reach their seams only after DelayFrames, text or an animation, which the
parked harness cannot run. Those are BGB acceptance items.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]

THRASHING_ABOUT = 1 << 1   # BattleStatus1
USING_RAGE = 1 << 6        # BattleStatus2
MOVING_SECOND = 1 << 3     # BattleStatus2
BADLY_POISONED = 1 << 0    # BattleStatus3
BRN = 1 << 4               # MonStatus
CANNOT_MOVE = 0xFF
ZERO_FLAG = 1 << 7
DISABLED_SLOT = 2          # high nibble: move slot 1-4


class ShinRedPhase13Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        cls.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        cls.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        team = [{"species": self.species["SNORLAX"], "level": 50,
                 "moves": [self.moves[m] for m in ("TACKLE", "HAZE", "REST", "SPLASH")]}]
        self.h.inject_fight2_spec(
            team, [dict(m) for m in team],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=1)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    # --- 13.7 Disable ------------------------------------------------------
    def fixup(self, side: int, byte: int, *, moving_second: bool) -> tuple[int, int]:
        """Run DisableCounterFixup as the tick site would; return (byte, HL)."""
        h = self.h
        h.park_before_hijack()
        prefix = "wPlayer" if side == 0 else "wEnemy"
        target = h.address(prefix + "DisabledMove")
        h.write8(prefix + "DisabledMove", byte)
        other = "wEnemy" if side == 0 else "wPlayer"
        h.write8(prefix + "BattleStatus2", MOVING_SECOND if moving_second else 0)
        # The other side's flag must not leak into this side's decision.
        h.write8(other + "BattleStatus2", 0 if moving_second else MOVING_SECOND)
        h.write8("hWhoseTurn", side)
        # GetPredefRegisters reads the caller's hl back from here (big-endian).
        h.write8("wPredefHL", target >> 8)
        h.write8("wPredefHL", target & 0xFF, offset=1)
        h.call_routine("DisableCounterFixup")
        return h.read8(prefix + "DisabledMove"), h.last_call_registers["HL"]

    @staticmethod
    def fresh(n: int) -> int:
        """What DisableEffect now stores for a roll of n (1-8)."""
        return (DISABLED_SLOT << 4) | ((n + 8) & 0x0F)

    def test_fresh_counts_decode_unchanged_when_moving_first(self) -> None:
        for side in (0, 1):
            for n in range(1, 9):
                with self.subTest(side=side, n=n):
                    got, _ = self.fixup(side, self.fresh(n), moving_second=False)
                    self.assertEqual(got, (DISABLED_SLOT << 4) | n)

    def test_moving_second_turns_a_roll_of_1_into_8_blocked_turns(self) -> None:
        for side in (0, 1):
            for n in range(1, 9):
                with self.subTest(side=side, n=n):
                    got, _ = self.fixup(side, self.fresh(n), moving_second=True)
                    # 9 ticks to 8 in the caller; 2-8 tick to 1-7.
                    self.assertEqual(got, (DISABLED_SLOT << 4) | (9 if n == 1 else n))

    def test_live_counts_are_left_alone(self) -> None:
        for count in range(1, 9):
            with self.subTest(count=count):
                byte = (DISABLED_SLOT << 4) | count
                got, _ = self.fixup(0, byte, moving_second=True)
                self.assertEqual(got, byte)

    def test_hl_returns_to_the_tick_site_intact(self) -> None:
        for side in (0, 1):
            prefix = "wPlayer" if side == 0 else "wEnemy"
            _, hl = self.fixup(side, self.fresh(3), moving_second=True)
            self.assertEqual(hl, self.h.address(prefix + "DisabledMove"))

    # --- 13.3 Rage / Thrash accuracy ----------------------------------------
    def test_round_start_restores_locked_move_accuracy_and_clears_order(self) -> None:
        h = self.h
        h.park_before_hijack()
        h.write8("wPlayerBattleStatus1", THRASHING_ABOUT)
        h.write8("wPlayerBattleStatus2", MOVING_SECOND)
        h.write8("wEnemyBattleStatus1", 0)
        h.write8("wEnemyBattleStatus2", USING_RAGE | MOVING_SECOND)
        h.write8("wPlayerMoveAccuracy", 0x80)
        h.write8("wEnemyMoveAccuracy", 0x60)
        h.call_routine("BattleRoundStartFixups")
        self.assertEqual(h.read8("wPlayerMoveAccuracy"), 0xFF)
        self.assertEqual(h.read8("wEnemyMoveAccuracy"), 0xFF)
        self.assertEqual(h.read8("wPlayerBattleStatus2"), 0)
        self.assertEqual(h.read8("wEnemyBattleStatus2"), USING_RAGE)
        self.assertEqual(h.read8("wPlayerBattleStatus1"), THRASHING_ABOUT)

    def test_round_start_leaves_unlocked_accuracy_alone(self) -> None:
        h = self.h
        h.park_before_hijack()
        for prefix in ("wPlayer", "wEnemy"):
            h.write8(prefix + "BattleStatus1", 0)
            h.write8(prefix + "BattleStatus2", MOVING_SECOND)
            h.write8(prefix + "MoveAccuracy", 0x80)
        h.call_routine("BattleRoundStartFixups")
        for prefix in ("wPlayer", "wEnemy"):
            self.assertEqual(h.read8(prefix + "MoveAccuracy"), 0x80)
            self.assertEqual(h.read8(prefix + "BattleStatus2"), 0)

    # --- 13.1 Struggle -------------------------------------------------------
    def set_pp(self, pp: list[int]) -> None:
        for i, value in enumerate(pp):
            self.h.write8("wBattleMonPP", value, offset=i)

    def test_struggle_triggers_past_pp_ups_with_a_disabled_move(self) -> None:
        h = self.h
        h.park_before_hijack()
        h.write8("wPlayerDisabledMove", (1 << 4) | 3)  # slot 1 disabled
        self.set_pp([0x05, 0xC0, 0x80, 0x40])           # others: 0 PP, PP Ups
        hit = {}

        def seam(_context) -> None:
            # Read here: the probe restores the pre-probe state when it returns.
            hit.setdefault("selected", h.read8("wPlayerSelectedMove"))

        bank, address = h.symbols.get("AnyMoveToSelect.noMovesLeft")
        h.pyboy.hook_register(bank, address, seam, None)
        try:
            h.probe_routine_until("AnyMoveToSelect", lambda: "selected" in hit, limit=60)
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(hit["selected"], self.moves["STRUGGLE"])

    def test_a_move_with_real_pp_still_counts(self) -> None:
        h = self.h
        h.park_before_hijack()
        h.write8("wPlayerDisabledMove", (1 << 4) | 3)
        self.set_pp([0x05, 0xC1, 0x80, 0x40])           # slot 2: 1 PP + PP Ups
        h.call_routine("AnyMoveToSelect")
        self.assertEqual(h.last_call_registers["F"] & ZERO_FLAG, 0)

    # --- 13.6 Haze -----------------------------------------------------------
    def test_haze_zeroes_both_toxic_counters(self) -> None:
        h = self.h
        h.park_before_hijack()
        h.write8("hWhoseTurn", 0)
        h.write8("wPlayerToxicCounter", 5)
        h.write8("wEnemyToxicCounter", 7)
        h.write8("wPlayerBattleStatus3", BADLY_POISONED)
        h.write8("wEnemyBattleStatus3", BADLY_POISONED)
        hit = {}

        def seam(_context) -> None:
            if "state" not in hit:
                hit["state"] = (h.read8("wPlayerToxicCounter"), h.read8("wEnemyToxicCounter"))

        bank, address = h.symbols.get("CureVolatileStatuses")
        h.pyboy.hook_register(bank, address, seam, None)
        try:
            h.probe_routine_until("HazeEffect_", lambda: "state" in hit, limit=60)
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(hit["state"], (0, 0))


    def haze_state(self, user: int) -> dict:
        """Run HazeEffect_ for `user` up to CureVolatileStatuses; return state there."""
        h = self.h
        h.write8("hWhoseTurn", user)
        hit = {}

        def seam(_context) -> None:
            if "state" not in hit:
                hit["state"] = {name: h.read8(name) for name in (
                    "wBattleMonStatus", "wEnemyMonStatus",
                    "wPlayerSelectedMove", "wEnemySelectedMove")}

        bank, address = h.symbols.get("CureVolatileStatuses")
        h.pyboy.hook_register(bank, address, seam, None)
        try:
            h.probe_routine_until("HazeEffect_", lambda: "state" in hit, limit=60)
        finally:
            h.pyboy.hook_deregister(bank, address)
        return hit["state"]

    def test_haze_cures_both_sides(self) -> None:
        h = self.h
        h.park_before_hijack()
        h.write8("wBattleMonStatus", BRN)        # the Haze user's own status
        h.write8("wEnemyMonStatus", BRN)
        h.write8("wPlayerSelectedMove", self.moves["HAZE"])
        h.write8("wEnemySelectedMove", self.moves["TACKLE"])
        state = self.haze_state(user=0)
        self.assertEqual((state["wBattleMonStatus"], state["wEnemyMonStatus"]), (0, 0))
        # Neither side was asleep or frozen, so no move is cancelled.
        self.assertEqual(state["wPlayerSelectedMove"], self.moves["HAZE"])
        self.assertEqual(state["wEnemySelectedMove"], self.moves["TACKLE"])

    def test_haze_cancels_a_cured_sleepers_stale_move(self) -> None:
        h = self.h
        h.park_before_hijack()
        h.write8("wEnemyMonStatus", 3)           # asleep: skipped selection
        h.write8("wEnemySelectedMove", 0)        # battle-start value
        h.write8("wEnemyBattleStatus1", 0)
        h.write8("wEnemyBattleStatus2", 0)
        state = self.haze_state(user=0)
        self.assertEqual(state["wEnemyMonStatus"], 0)
        self.assertEqual(state["wEnemySelectedMove"], CANNOT_MOVE)

    def test_haze_leaves_a_locked_sleepers_move(self) -> None:
        h = self.h
        for status1, status2 in ((THRASHING_ABOUT, 0), (0, USING_RAGE)):
            with self.subTest(status1=status1, status2=status2):
                h.park_before_hijack()
                h.write8("wBattleMonStatus", 2)
                h.write8("wPlayerSelectedMove", self.moves["TACKLE"])
                h.write8("wPlayerBattleStatus1", status1)
                h.write8("wPlayerBattleStatus2", status2)
                state = self.haze_state(user=1)
                self.assertEqual(state["wBattleMonStatus"], 0)
                self.assertEqual(state["wPlayerSelectedMove"], self.moves["TACKLE"])


if __name__ == "__main__":
    unittest.main()
