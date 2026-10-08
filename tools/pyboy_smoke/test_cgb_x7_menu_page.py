"""SRAM $BD00-$BDFF must hold nothing, in every bank (FOLLOWUPS #58).

Measured on hardware 2026-10-08: once the EverDrive GB X7's in-game menu is
opened, reads of $BD00-$BDFF return the cartridge's own bytes (01 00 40 3E ...)
in all four SRAM banks until power-off. The procedural forest kept its baked
map there, so the next battle return blitted those bytes into the forest. The
fix reserves the page (ram/sram.asm end, layout.link `org $bd00`) and moved the
forest map, the fallen log tail and the reward offer DVs out of it.
See Red Rogue Files/PFOREST_X7_INVESTIGATION.md.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]
PAGE_LO, PAGE_HI = 0xBD00, 0xBE00
# What the X7 menu leaves readable in the page (first bytes measured on hardware).
X7_STUB = [0x01, 0x00, 0x40, 0x3E]
PF_BASE, PF_STRIDE, PF_SIZE = 81, 26, 20


class X7MenuPageTest(unittest.TestCase):
    def test_no_sram_label_in_the_reserved_page(self):
        # The X7 Menu Page sections reserve the page at link time; this catches a label that
        # reaches it some other way (a fixed address, a section moved in layout.link).
        sym = ROOT / "pokeblue_debug.sym"
        inside = []
        for line in sym.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) != 2 or ":" not in parts[0]:
                continue
            bank, address = parts[0].split(":")
            if not parts[1].startswith("s") or int(bank, 16) > 3:
                continue
            if PAGE_LO <= int(address, 16) < PAGE_HI:
                inside.append(line)
        self.assertEqual(inside, [], "SRAM labels inside the X7 page")

    def test_forest_survives_the_x7_page_being_overwritten(self):
        # Simulate the X7 menu: overwrite the page in all four banks, then run the forest's
        # re-entry path (the fast blit every battle return takes). The map must not change.
        h = RedRogueHarness(ROOT, ROOT / "tmp/x7-menu-page", cgb_mode=True)
        try:
            h.boot_to_lobby()
            h.preload_and_enter_wild_area(0xF2, "forest")
            self.assertEqual(h.read_sram_bytes("sProcForestBaked", 1, bank=0), [1])

            def interior():
                return [h.read8("wOverworldMap", PF_BASE + r * PF_STRIDE + c)
                        for r in range(PF_SIZE) for c in range(PF_SIZE)]

            before = interior()
            stub = (X7_STUB * 64)[:PAGE_HI - PAGE_LO]
            m = h.pyboy.memory
            for bank in range(4):
                m[0x0000] = 0x0A
                m[0x4000] = bank
                for i, value in enumerate(stub):
                    m[PAGE_LO + i] = value
            m[0x4000] = 0
            m[0x0000] = 0
            # Wreck the live map too, so only a correct blit from SRAM can restore it.
            for r in range(PF_SIZE):
                for c in range(PF_SIZE):
                    h.write8("wOverworldMap", 0x99, offset=PF_BASE + r * PF_STRIDE + c)
            h.call_routine("PFinalizeForest", limit=200000)
            self.assertEqual(interior(), before)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main()
