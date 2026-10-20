"""Garbled-screen checks (autoplay_screen.py): real play in the lobby passes
every pointer, and each kind of bad pointer is reported when planted."""
import autoplay
import autoplay_screen
from test_smoke import HarnessTestCase


class AutoplayScreenTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        autoplay.boot(self.harness, seed=1)
        self.agent = autoplay.AutoplayAgent(self.harness, seed=1)
        self.checks = self.agent.checks
        self.screen = self.checks.screen

    def found(self, kind: str) -> list[str]:
        return [a["detail"] for a in self.checks.anomalies if a["check"] == f"screen_{kind}"]

    def far_text(self, bank: int, address: int) -> int:
        buffer = self.harness.address("wStringBuffer")
        for i, value in enumerate((address & 0xFF, address >> 8, bank)):
            self.harness.pyboy.memory[buffer + i] = value
        return buffer

    def test_lobby_play_passes_every_pointer(self) -> None:
        for _ in range(4000):
            self.agent.step()
            if all(self.screen.calls.get(kind) for kind in ("glyph", "text_pointer", "text_command", "text_far")):
                break
        self.assertTrue(all(self.screen.calls.get(kind) for kind in ("glyph", "text_pointer", "text_far")),
                        self.screen.calls)
        self.assertEqual([a for a in self.checks.anomalies if a["check"].startswith("screen_")], [])

    def test_text_far_to_a_text_label_passes(self) -> None:
        bank, address = self.harness.symbols.get("_PokemartGreetingText")
        self.screen.check_text_far(self.far_text(bank, address))
        self.assertEqual(self.found("text_far"), [])

    def test_text_far_with_the_wrong_bank(self) -> None:
        bank, address = self.harness.symbols.get("_PokemartGreetingText")
        self.screen.check_text_far(self.far_text(bank + 1, address))
        self.assertTrue(self.found("text_far"), self.checks.anomalies)

    def test_text_far_past_the_last_bank(self) -> None:
        _, address = self.harness.symbols.get("_PokemartGreetingText")
        self.screen.check_text_far(self.far_text(self.checks.rom_banks, address))
        self.assertTrue(any(d.startswith("bad target") for d in self.found("text_far")), self.checks.anomalies)

    def test_non_glyph_byte_placed(self) -> None:
        self.screen.check_glyph(0x20, self.harness.address("wStringBuffer"))
        self.assertTrue(self.found("glyph"), self.checks.anomalies)

    def test_byte_that_is_not_a_text_command(self) -> None:
        self.screen.check_text_command(0x30, self.harness.address("wStringBuffer"))
        self.assertTrue(self.found("text_command"), self.checks.anomalies)

    def test_graphics_copied_from_code(self) -> None:
        code_bank, code_address = self.harness.symbols.get("Random")
        screen = autoplay_screen.ScreenChecks(self.checks, code=[{"bank": code_bank, "address": code_address}])
        font_bank, font_address = self.harness.symbols.get("FontGraphics")
        screen.check_source("gfx_source", font_bank, font_address)
        self.assertEqual(self.found("gfx_source"), [])
        screen.check_source("gfx_source", code_bank, code_address + 1)  # before Random.body
        self.assertTrue(any("source inside code" in d for d in self.found("gfx_source")), self.checks.anomalies)
