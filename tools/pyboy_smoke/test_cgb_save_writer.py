"""Internal full saves capture the live CGB gamma state before Main Data."""
import io
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT


class CGBSaveWriterTest(unittest.TestCase):
    def test_internal_full_save_updates_gamma_in_saved_events(self):
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)
        try:
            h.boot_to_lobby()
            baseline = io.BytesIO()
            h.save_state(baseline)
            event = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")["EVENT_GAMMA_SHADER"]
            offset = h.address("wEventFlags") - h.address("wMainDataStart") + event // 8
            mask = 1 << (event % 8)
            for live_mode in (1, 2):
                with self.subTest(live_mode=live_mode):
                    h.load_state(io.BytesIO(baseline.getvalue()))
                    h.write8("hGBC", live_mode)
                    # Start with the opposite preference to prove synchronization.
                    address = h.address("wEventFlags") + event // 8
                    h.pyboy.memory[address] = (h.pyboy.memory[address] & ~mask) | (mask if live_mode == 1 else 0)
                    h.call_routine("SaveGameData")
                    saved = h.read_sram_bytes("sMainData", offset + 1)[offset]
                    self.assertEqual(bool(saved & mask), live_mode == 2)
            self.assertFalse(h.hook_errors, h.hook_errors)
        finally:
            h.close()
