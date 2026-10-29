"""Real title-menu discard consent, before New Game's persistent initializers."""
import unittest

from harness import RedRogueHarness
from test_save_header import ARTIFACTS, REPO_ROOT, ColdBoot, HEADER_OFFSET, dump_sram


class NewGameConsentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            h.call_routine("SaveGameData")
            cls.saved = dump_sram(h)
        finally:
            h.close()

    def prompt(self, image, debug=False, disposable=False):
        boot = ColdBoot(image)
        self.addCleanup(boot.close)
        h = boot.h
        if disposable:
            h.enable_disposable_sram_consent()
        prompt = h.hook_flag("ConfirmNewGameOverwrite.prompt")
        menu = h.hook_flag("DisplayTwoOptionMenu.storeCurrentMenuItem")
        self.entered = []
        h.register_hook("OakSpeech", lambda _: self.entered.append(dump_sram(h)))
        if debug:
            debug_menu = h.hook_flag("DebugMenu")
            h.tick(240)
            h.pyboy.button_press("select")
            for _ in range(300):
                h.tap("start")
                if debug_menu["count"]:
                    break
            h.pyboy.button_release("select")
            self.assertGreater(debug_menu["count"], 0)
            h.tick(60)
            h.tap("down")
            h.tap("down")  # DEBUG
            if debug == 2:
                h.tap("down")  # DEBUG 2
        else:
            status = boot.to_menu()
            h.tick(60)
            if status == 2:
                h.tap("down")  # NEW GAME after CONTINUE
        # Boot-time title pictures use SRAM scratch buffers. The cancellation
        # contract starts at the New Game choice, after that unrelated rendering.
        self.before_gate = dump_sram(h)
        h.tap("a")
        h.wait_until(lambda: prompt["count"] > 0, "New Game discard warning", 300)
        self.assertGreater(prompt["count"], 0)
        # The warning's cont pauses once before presenting the yes/no choice.
        for _ in range(120):
            if menu["count"]:
                break
            h.tap("a")
        self.assertGreater(menu["count"], 0)
        h.tick(20)
        self.assertEqual(h.read8("hCurrentMenuItem"), 1)  # NO by default
        self.assertEqual(dump_sram(h), self.before_gate)
        self.assertEqual(self.entered, [])
        return boot

    def cancel(self, image, button="a", debug=False):
        boot = self.prompt(image, debug)
        boot.h.tap(button)
        boot.h.tick(90)
        self.assertEqual(dump_sram(boot.h), self.before_gate)
        self.assertEqual(self.entered, [])
        if not debug:
            self.assertEqual(boot.h.read8("wSaveFileStatus"), 2 if image == self.saved else 1)

    def test_no_keeps_all_32k_and_continue(self):
        self.cancel(self.saved)

    def test_b_keeps_all_32k_and_continue(self):
        self.cancel(self.saved, "b")

    def test_incompatible_profile_is_protected(self):
        image = bytearray(self.saved)
        image[HEADER_OFFSET + 4] ^= 1
        self.cancel(bytes(image))

    def test_header_with_damaged_name_is_protected(self):
        image = bytearray(self.saved)
        # No name terminator, so the normal title save detection skips loading.
        from test_save_header import SRAM_LABELS
        bank, address = SRAM_LABELS["sPlayerName"]
        offset = bank * 8192 + address - 0xA000
        image[offset:offset + 11] = b"\xff" * 11
        self.cancel(bytes(image))

    def test_debug_start_also_requires_consent(self):
        self.cancel(self.saved, debug=True)

    def test_debug2_start_also_requires_consent(self):
        self.cancel(self.saved, debug=2)

    def test_blank_sram_starts_without_discard_prompt(self):
        boot = ColdBoot(bytes([255]) * 32768)
        self.addCleanup(boot.close)
        prompt = boot.h.hook_flag("ConfirmNewGameOverwrite.prompt")
        oak = boot.h.hook_flag("OakSpeech")
        self.assertEqual(boot.to_menu(), 1)
        boot.h.tick(60)
        boot.h.tap("a")
        boot.h.wait_until(lambda: oak["count"] > 0, "fresh New Game", 300)
        self.assertEqual(prompt["count"], 0)

    def test_yes_invalidates_only_header_before_oak_speech(self):
        boot = self.prompt(self.saved)
        boot.h.tap("up")
        boot.h.tap("a")
        boot.h.wait_until(lambda: bool(self.entered), "consented Oak speech", 300)
        expected = bytearray(self.before_gate)
        expected[HEADER_OFFSET:HEADER_OFFSET + 8] = bytes(8)
        self.assertEqual(self.entered[0], bytes(expected))
        # A cold boot at this boundary cannot Continue the discarded profile.
        reset = ColdBoot(self.entered[0])
        self.addCleanup(reset.close)
        self.assertEqual(reset.to_menu(), 1)

    def test_explicit_disposable_policy_uses_existing_consent_lifecycle(self):
        from sram_fuzz import fill_bytes
        from test_save_header import SRAM_LABELS
        damaged = bytearray(self.saved)
        bank, address = SRAM_LABELS["sPlayerName"]
        offset = bank * 8192 + address - 0xA000
        damaged[offset:offset + 11] = b"\xff" * 11
        for debug in (False, 2):
            for image in (self.saved, bytes(damaged), fill_bytes("random1", 1), fill_bytes("random2", 7)):
                with self.subTest(debug=debug, header=image[HEADER_OFFSET:HEADER_OFFSET + 8].hex()):
                    boot = self.prompt(image, debug=debug, disposable=True)
                    h = boot.h
                    for _ in range(150):
                        if self.entered:
                            break
                        if not h.step_disposable_sram_consent():
                            h.tick(1)
                    self.assertTrue(self.entered)
                    kinds = [event["kind"] for event in h.disposable_sram_consent["events"]]
                    self.assertEqual(kinds.count("consent_accepted"), 1)
                    self.assertIn("initialization_entered", kinds)
                    self.doCleanups()

    def test_random_header_cancellation_preserves_sram_on_both_boot_paths(self):
        from sram_fuzz import fill_bytes
        for debug in (False, 2):
            for button in ("a", "b"):
                with self.subTest(debug=debug, button=button):
                    self.cancel(fill_bytes("random1", 1), button=button, debug=debug)
                    self.doCleanups()


if __name__ == "__main__":
    unittest.main()
