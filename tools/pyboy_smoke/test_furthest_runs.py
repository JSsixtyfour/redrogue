"""The furthest-runs table (custom_functions/run_records.asm, RECORDS_PC_PLAN_2026-11-03.md).

Five (wEndlessDepth, wBattleCount) pairs in saved padding, best first. The commit
runs once per ended run, before anything wipes run state: at the top of
LossRecoveryCapture (blackout, END RUN) and in the Hall of Fame's normal-clear branch.
"""
import unittest

import test_dex_forms
import test_loss_recovery as loss
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT, ColdBoot, dump_sram

EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
DEBUG_BITS = 0x82  # BIT_DEBUG_MODE | BIT_DEBUG2_MODE


class Table:
    """Shared helpers: self.h is a booted harness."""

    def table(self, h=None):
        h = h or self.h
        raw = h.read_bytes("wFurthestRunsFirst", 8) + h.read_bytes("wFurthestRunsLast", 2)
        return [tuple(raw[i:i + 2]) for i in range(0, 10, 2) if raw[i] or raw[i + 1]]

    def run_state(self, depth, count):
        self.h.write8("wEndlessDepth", depth)
        self.h.write8("wBattleCount", count)

    def non_debug(self):
        self.h.write8("wStatusFlags6", self.h.read8("wStatusFlags6") & ~DEBUG_BITS)

    def clear_table(self):
        for label, size in (("wFurthestRunsFirst", 8), ("wFurthestRunsLast", 2)):
            for i in range(size):
                self.h.write8(label, 0, offset=i)


class CommitTest(Table, unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()
        self.non_debug()
        self.clear_table()
        self.runner = test_dex_forms.DexFormsTest()
        self.runner.h = self.h

    def commit(self, depth, count):
        self.run_state(depth, count)
        self.runner.run_routine("FurthestRunsCommit")

    def test_order_ties_and_the_sixth_run_drops(self):
        seen = []
        for run in ((0, 30), (0, 73), (1, 2), (0, 10), (3, 50), (0, 30), (2, 73), (0, 5), (4, 1)):
            self.commit(*run)
            seen.append(run)
            # Stable sort: a tie keeps the older run first (they are identical anyway).
            self.assertEqual(self.table(), sorted(seen, reverse=True)[:5], run)

    def test_a_run_with_no_wins_does_not_rank(self):
        for run in ((0, 0), (0, 1)):
            self.commit(*run)
            self.assertEqual(self.table(), [], run)
        self.commit(0, 2)
        self.assertEqual(self.table(), [(0, 2)])
        self.commit(1, 1)  # the first step of a continuation has still gone further
        self.assertEqual(self.table(), [(1, 1), (0, 2)])

    def test_debug_modes_do_not_rank(self):
        for bits in (0x02, 0x80):
            self.h.write8("wStatusFlags6", self.h.read8("wStatusFlags6") | bits)
            self.commit(0, 40)
            self.assertEqual(self.table(), [], bits)
            self.non_debug()

    def test_rank_uses_saved_values_not_the_saturated_progress(self):
        self.commit(255, 73)
        self.commit(255, 74)
        self.assertEqual(self.table(), [(255, 74), (255, 73)])

    def test_the_table_lives_through_a_run_reset_and_a_reload_undoes_a_later_run(self):
        h = self.h
        self.commit(1, 20)
        h.call_routine("RogueResetRunState")
        self.assertEqual(self.table(), [(1, 20)])
        self.assertEqual((h.read8("wEndlessDepth"), h.read8("wBattleCount")), (0, 0))
        h.call_routine("SaveGameData")
        self.commit(2, 20)
        self.assertEqual(self.table(), [(2, 20), (1, 20)])
        h.call_routine("LoadMainData")
        self.assertEqual(self.table(), [(1, 20)], "a reload forgets a run that ended after the save")

    def test_run_records_init_clears_it(self):
        self.commit(1, 20)
        self.h.call_routine("RunRecordsInit")
        self.assertEqual(self.table(), [])


class RealRunEndTest(Table, unittest.TestCase):
    def boot(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()
        self.non_debug()
        self.h.write8("wRentalState", 0)
        self.h.write8("wPlayerCoins", 0x12)
        self.h.write8("wPlayerCoins", 0x34, 1)
        self.h.write8("wCreditsEarnedThisRun", 3)
        self.h.call_routine("LossRecoveryDiscard")
        self.clear_table()

    def blackout(self):
        h = self.h
        armed = [True]

        def enter(_):
            if armed[0]:
                armed[0] = False
                h.pyboy.register_file.PC = h.address("HandleBlackOut")
        h.register_hook("OverworldLoop", enter)

    def test_blackout_records_the_run_and_the_save_holds_it(self):
        h = self.h = None
        self.boot()
        h = self.h
        self.run_state(1, 30)
        self.blackout()
        h.tick(450)
        self.assertEqual(h.read8("wBattleCount"), 0, "the run really was reset")
        self.assertEqual(self.table(), [(1, 30)])
        self.assertFalse(h.hook_errors, h.hook_errors)
        start = 0x2000 + h.address("sMainData") - 0xA000 + h.address("wFurthestRunsFirst") - h.address("wMainDataStart")
        self.assertEqual(list(dump_sram(h)[start:start + 2]), [1, 30], "the blackout's own save")

    def test_a_run_ending_on_a_rental_still_ranks(self):
        self.boot()
        h = self.h
        self.run_state(0, 25)
        h.write8("wRentalState", 1)
        h.call_routine("LossRecoveryCapture")
        self.assertEqual(self.table(), [(0, 25)])

    def test_debug_blackout_does_not_rank(self):
        self.boot()
        h = self.h
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") | 0x02)
        self.run_state(0, 25)
        h.call_routine("LossRecoveryCapture")
        self.assertEqual(self.table(), [])

    def test_power_loss_mid_blackout_keeps_the_entry(self):
        """The record holds the table but not wBattleCount, which is why the commit comes first."""
        self.boot()
        h = self.h
        self.run_state(1, 30)
        images = []
        h.register_hook("SaveGameData", lambda _: images.append(dump_sram(h)) if not images else None)
        self.blackout()
        h.wait_until(lambda: bool(images), "the blackout's save", 900)
        boot = ColdBoot(images[0])
        self.addCleanup(boot.close)
        loss.LossRecoveryTest.await_recovered(self, boot)
        self.assertEqual(self.table(boot.h), [(1, 30)])
        self.assertEqual(boot.h.read8("wBattleCount"), 0)

    def test_new_game_from_the_menu_clears_it(self):
        self.boot()
        h = self.h
        self.run_state(1, 30)
        h.call_routine("FurthestRunsCommit")
        h.write8("wSpecialCollected", 0x5A)
        h.write8("wSpecialCollected", 0xA5, offset=1)
        h.call_routine("SaveGameData")
        boot = ColdBoot(dump_sram(h))
        self.addCleanup(boot.close)
        game = boot.h
        at_prepare, at_init = [], []
        fields = lambda: game.read_bytes("wFurthestRunsFirst", 8) + game.read_bytes("wFurthestRunsLast", 2) \
            + game.read_bytes("wSpecialCollected", 2)
        game.register_hook("PrepareOakSpeech", lambda _: at_prepare.append(fields()))
        game.register_hook("InitPlayerData2", lambda _: at_init.append(fields()))
        prompt = game.hook_flag("ConfirmNewGameOverwrite.prompt")
        menu = game.hook_flag("DisplayTwoOptionMenu.storeCurrentMenuItem")
        self.assertEqual(boot.to_menu(), 2)
        game.tick(60)
        game.tap("down")
        game.tap("a")
        game.wait_until(lambda: prompt["count"] > 0, "New Game discard warning", 300)
        for _ in range(120):
            if menu["count"]:
                break
            game.tap("a")
        game.tick(20)
        game.tap("up")
        game.tap("a")
        game.wait_until(lambda: bool(at_init), "InitPlayerData2", 900)
        self.assertEqual(at_prepare[0][:2], [1, 30], "really loaded first")
        self.assertEqual(at_prepare[0][-2:], [0x5A, 0xA5])
        self.assertEqual(at_init[0], [0] * 12)


class HallOfFameTest(Table, unittest.TestCase):
    """HallOfFameResetEventsAndSaveScript itself, its presentation and offer stubbed out."""

    def run_script(self, accept):
        h = self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        self.non_debug()
        self.clear_table()
        self.run_state(1, 73)
        h.pyboy.memory[h.address("wEventFlags") + EVENTS["EVENT_AI_DEFEATED"] // 8] |= 1 << (EVENTS["EVENT_AI_DEFEATED"] % 8)
        h.write8("wStatusFlags3", h.read8("wStatusFlags3") & ~(1 << RAM["BIT_WARP_FROM_CUR_SCRIPT"]))
        stub = h.address("wStringBuffer") + 16
        memory = h.pyboy.memory
        memory[stub], memory[stub + 1] = 0x18, 0xFE  # jr @
        regs = h.pyboy.register_file

        def force_ret():
            regs.PC = memory[regs.SP] | memory[regs.SP + 1] << 8
            regs.SP = regs.SP + 2

        def offer(_):
            if accept:
                h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << RAM["BIT_WARP_FROM_CUR_SCRIPT"])
            force_ret()
        h.register_hook("EndlessOffer", offer)
        h.register_hook("HallOfFamePC", lambda _: force_ret())
        h.register_hook("RunRecordsCommit", lambda _: force_ret())
        snapshot = []
        h.register_hook("HallOfFameResetEventsAndSaveScript.presented", lambda _: snapshot.append(self.table()))
        armed = [True]

        def enter(_):
            if not armed[0]:
                return
            armed[0] = False
            bank, address = h.symbols.get("HallOfFameResetEventsAndSaveScript")
            h.write8("hLoadedROMBank", bank)
            memory[0x2000] = bank
            regs.SP = regs.SP - 2
            memory[regs.SP], memory[regs.SP + 1] = stub & 0xFF, stub >> 8
            regs.PC = address
        h.register_hook("OverworldLoop", enter)
        return snapshot, stub

    def test_declining_endless_records_the_run(self):
        snapshot, _ = self.run_script(accept=False)
        self.h.wait_until(lambda: bool(snapshot), "the normal-clear branch", 600)
        self.assertEqual(snapshot[0], [(1, 73)])
        self.assertFalse(self.h.hook_errors, self.h.hook_errors)

    def test_accepting_endless_records_nothing_because_the_run_goes_on(self):
        snapshot, _ = self.run_script(accept=True)
        branch = self.h.hook_flag("HallOfFameResetEventsAndSaveScript.endless")
        self.h.wait_until(lambda: branch["count"] > 0, "the Endless branch", 600)
        self.h.tick(30)
        self.assertEqual(snapshot, [], "took the normal-clear branch")
        self.assertEqual(self.table(), [])
        self.assertEqual((self.h.read8("wEndlessDepth"), self.h.read8("wBattleCount")), (1, 73))
        self.assertFalse(self.h.hook_errors, self.h.hook_errors)


if __name__ == "__main__":
    unittest.main()
