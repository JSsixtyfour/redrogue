"""The Pokedex flags (base + form, wPokedexOwned..wPokedexDataEnd) through every save path.

POKEDEX_FORMS_OAK_SOL_PLAN_2026-11-01.md, Checkpoint E: ordinary and partial saves,
run loss and recovery, and New Game clearing them. Every test seeds all the flag
bytes with a non-uniform pattern first: a zeroed form array would pass any of these.
"""
import unittest

import test_dex_forms
import test_loss_recovery as loss
from harness import RedRogueHarness
from test_save_header import ARTIFACTS, REPO_ROOT, ColdBoot, dump_sram

SIZE = 2 * 32 + 2 * 7
PATTERN = [(i * 37 + 0x5B) & 0xFF or 0xA5 for i in range(SIZE)]
SCRAMBLED = [b ^ 0xFF for b in PATTERN]


class DexFormsSaveTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()

    def write_flags(self, values):
        for i, value in enumerate(values):
            self.h.write8("wPokedexOwned", value, offset=i)

    def flags(self, h=None):
        return (h or self.h).read_bytes("wPokedexOwned", SIZE)

    def main_data(self):
        h = self.h
        return h.read_sram_bytes("sMainData", h.address("wMainDataEnd") - h.address("wMainDataStart"))

    def test_the_span_is_every_flag_byte(self):
        a = self.h.address
        self.assertEqual(a("wPokedexDataEnd") - a("wPokedexOwned"), SIZE)
        self.assertEqual(a("wPokedexOwned"), a("wMainDataStart"), "the partial save copies to sMainData+0")

    def test_full_save_and_load_keep_every_flag_byte(self):
        self.write_flags(PATTERN)
        self.h.call_routine("SaveGameData")
        self.assertEqual(self.main_data()[:SIZE], PATTERN)
        self.write_flags(SCRAMBLED)
        self.h.call_routine("LoadMainData")
        self.assertEqual(self.flags(), PATTERN)

    def test_partial_dex_save_copies_exactly_the_flags(self):
        h = self.h
        h.call_routine("SaveGameData")
        before = self.main_data()
        self.write_flags(PATTERN)
        h.write8("wPokedexDataEnd", h.read8("wPokedexDataEnd") ^ 0xFF)  # first byte past the span
        h.call_routine("SavePartyAndDexData")
        after = self.main_data()
        self.assertEqual(after[:SIZE], PATTERN)
        self.assertEqual(after[SIZE:], before[SIZE:], "nothing past the flags")

    def test_partial_dex_load_restores_exactly_the_flags(self):
        h = self.h
        self.write_flags(PATTERN)
        h.call_routine("SaveGameData")
        self.write_flags(SCRAMBLED)
        past = h.read8("wPokedexDataEnd") ^ 0xFF
        h.write8("wPokedexDataEnd", past)
        h.call_routine("LoadPartyAndDexData")
        self.assertEqual(self.flags(), PATTERN)
        self.assertEqual(h.read8("wPokedexDataEnd"), past, "nothing past the flags")

    def test_run_reset_keeps_every_flag_byte(self):
        self.write_flags(PATTERN)
        self.h.call_routine("RogueResetRunState")
        self.assertEqual(self.flags(), PATTERN)

    def loss_fixture(self):
        h = self.h
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") & ~0x82)
        h.write8("wRentalState", 0)
        h.write8("wPlayerCoins", 0x12)
        h.write8("wPlayerCoins", 0x34, 1)
        h.write8("wCreditsEarnedThisRun", 3)
        h.call_routine("LossRecoveryDiscard")
        self.write_flags(PATTERN)

    def test_loss_recovery_restores_every_flag_byte(self):
        h = self.h
        self.loss_fixture()
        h.call_routine("LossRecoveryPrepare")
        self.write_flags(SCRAMBLED)
        h.call_routine("LossRecoveryRestore")
        self.assertEqual(self.flags(), PATTERN)
        h.call_routine("RogueResetRunState")
        self.assertEqual(self.flags(), PATTERN)

    def test_cold_loss_recovery_keeps_every_flag_byte_and_saves_them(self):
        h = self.h
        self.loss_fixture()
        image = loss.LossRecoveryTest.prepared(self, h)
        boot = ColdBoot(image)
        self.addCleanup(boot.close)
        recovered = loss.LossRecoveryTest.await_recovered(self, boot)
        self.assertEqual(self.flags(boot.h), PATTERN)
        start = 0x2000 + h.address("sMainData") - 0xA000
        self.assertEqual(list(recovered[start:start + SIZE]), PATTERN, "the recovery's own save")

    def test_new_game_from_the_menu_clears_a_loaded_save_s_flags(self):
        """The main menu has already loaded the save into WRAM when NEW GAME is chosen."""
        h = self.h
        self.write_flags(PATTERN)
        h.call_routine("SaveGameData")
        image = dump_sram(h)
        boot = ColdBoot(image)
        self.addCleanup(boot.close)
        game = boot.h
        at_prepare, at_init = [], []
        game.register_hook("PrepareOakSpeech", lambda _: at_prepare.append(self.flags(game)))
        game.register_hook("InitPlayerData2", lambda _: at_init.append(self.flags(game)))
        prompt = game.hook_flag("ConfirmNewGameOverwrite.prompt")
        menu = game.hook_flag("DisplayTwoOptionMenu.storeCurrentMenuItem")
        self.assertEqual(boot.to_menu(), 2)
        game.tick(60)
        game.tap("down")  # NEW GAME after CONTINUE
        game.tap("a")
        game.wait_until(lambda: prompt["count"] > 0, "New Game discard warning", 300)
        for _ in range(120):
            if menu["count"]:
                break
            game.tap("a")
        game.tick(20)
        game.tap("up")  # YES
        game.tap("a")
        game.wait_until(lambda: bool(at_init), "InitPlayerData2", 900)
        self.assertEqual(at_prepare[0], PATTERN, "the flags really were loaded before New Game")
        self.assertEqual(at_init[0], [0] * SIZE)
        self.assertFalse(game.hook_errors, game.hook_errors)

    def test_base_and_form_stay_independent_across_a_load(self):
        h = self.h
        runner = test_dex_forms.DexFormsTest()
        runner.h = h
        runner.clear_dex()
        meowth = test_dex_forms.SPECIES["MEOWTH"]
        self.assertEqual(runner.register(meowth, 1, test_dex_forms.BOTH), 0, "new form")
        h.call_routine("SaveGameData")
        self.write_flags(SCRAMBLED)
        h.call_routine("LoadMainData")
        form_bit = test_dex_forms.DEX["DEX_FORM_A_MEOWTH"]
        self.assertEqual(runner.bits("wPokedexFormOwned", test_dex_forms.FORM_BYTES), [form_bit])
        self.assertEqual(runner.bits("wPokedexOwned", test_dex_forms.BASE_BYTES), [], "no base credit")
        self.assertEqual(runner.register(meowth, 1, test_dex_forms.BOTH), 1, "the form is a duplicate")
        self.assertEqual(runner.register(meowth, 0, test_dex_forms.BOTH), 0, "the base is still new")


if __name__ == "__main__":
    unittest.main()
