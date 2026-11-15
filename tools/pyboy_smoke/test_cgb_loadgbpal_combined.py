"""LoadGBPal_ reaches all three CGB palette updates through one far call.

FOLLOWUPS #12 Step B (2026-11-14) replaced three HOME UpdateGBCPal_* stubs,
each a full Bankswitch round trip, with one farcall to UpdateGBCPal_All_. The
three banked bodies still run in order and still compare against their own
WRAM-bank-2 cache, so this checks the visible contract: after a palette change
every cache follows its register and CGB palette RAM is rewritten, and an
unchanged call leaves palette RAM alone.
"""

import unittest

from harness import RedRogueHarness
from test_smoke import ARTIFACTS, REPO_ROOT

W2_LAST_BGP = 0xD010  # w2LastBGP / w2LastOBP0 / w2LastOBP1, WRAM bank 2
RBGPI, RBGPD, ROBPI, ROBPD = 0xFF68, 0xFF69, 0xFF6A, 0xFF6B


class LoadGBPalCombinedTest(unittest.TestCase):
    def setUp(self):
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)

    def tearDown(self):
        self.harness.close()

    def caches(self):
        mem = self.harness.pyboy.memory
        return [mem[2, W2_LAST_BGP + i] for i in range(3)]

    def registers(self):
        mem = self.harness.pyboy.memory
        return [mem[0xFF47], mem[0xFF48], mem[0xFF49]]

    def palette_ram(self, index_port, data_port):
        mem = self.harness.pyboy.memory
        saved = mem[index_port]
        out = []
        for i in range(64):
            mem[index_port] = i
            out.append(mem[data_port])
        mem[index_port] = saved
        return out

    def test_one_far_call_updates_all_three(self):
        h = self.harness
        h.boot_to_lobby()
        h.call_routine("LoadGBPal")
        self.assertEqual(self.caches(), self.registers(), "caches current after a settled call")
        bg_before = self.palette_ram(RBGPI, RBGPD)
        obj_before = self.palette_ram(ROBPI, ROBPD)

        # wMapPalOffset steps back from FadePal4 three bytes per fade stage;
        # one stage darker changes all three DMG registers.
        old = h.read8("wMapPalOffset")
        h.write8("wMapPalOffset", old + 3)
        h.call_routine("LoadGBPal")
        regs = self.registers()
        self.assertEqual(self.caches(), regs, "every cache follows its register")
        self.assertNotEqual(self.palette_ram(RBGPI, RBGPD), bg_before, "BG palette RAM rewritten")
        self.assertNotEqual(self.palette_ram(ROBPI, ROBPD), obj_before, "OBJ palette RAM rewritten")

        bg_changed = self.palette_ram(RBGPI, RBGPD)
        h.call_routine("LoadGBPal")
        self.assertEqual(self.palette_ram(RBGPI, RBGPD), bg_changed, "unchanged call leaves BG RAM alone")

        h.write8("wMapPalOffset", old)
        h.call_routine("LoadGBPal")
        self.assertEqual(self.caches(), self.registers())
        self.assertEqual(self.palette_ram(RBGPI, RBGPD), bg_before, "BG palette RAM restored")
        self.assertEqual(self.palette_ram(ROBPI, ROBPD), obj_before, "OBJ palette RAM restored")
        self.assertEqual(h.hook_errors, [])

    def test_each_body_runs_on_its_own(self):
        # Changing all three registers cannot tell the bodies apart: the
        # Enhanced BGP update also stages changed sprite palettes and marks
        # their caches current. A stale cache with unchanged registers reaches
        # exactly one body, so each must refresh its own (measured 2026-11-14:
        # a build whose UpdateGBCPal_All_ skipped OBP1 passed the test above).
        h = self.harness
        h.boot_to_lobby()
        h.call_routine("LoadGBPal")
        mem = h.pyboy.memory
        for i, name in enumerate(("BGP", "OBP0", "OBP1")):
            with self.subTest(cache=name):
                regs = self.registers()
                mem[2, W2_LAST_BGP + i] = regs[i] ^ 0xFF
                h.call_routine("LoadGBPal")
                self.assertEqual(self.caches(), self.registers(), f"{name} body refreshed its cache")


if __name__ == "__main__":
    unittest.main()
