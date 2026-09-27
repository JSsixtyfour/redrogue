"""Scratch probe: do the HM-specific mart purchase routines behave for HM_SURF?

Runs each routine whose behaviour differs between an HM and a TM, for HM_SURF
and a TM control, and prints the results. Not part of make smoke.
"""
import sys
import unittest

from test_smoke import HarnessTestCase

HM_SURF = 0xC6
TM_BODY_SLAM = 0xD0


class ProbeHMPurchase(HarnessTestCase):
    def _probe(self, item: int) -> dict:
        h = self.harness
        h.boot_fight2(seed=1)
        out = {}
        sp = h.pyboy.register_file.SP
        h.write8("wCurItem", item)
        h.write8("wListMenuID", 3)  # PRICEDITEMLISTMENU
        h.call_routine("GetItemPrice", limit=600)
        out["price"] = h.read_bytes("hItemPrice", 3)
        h.write8("wNamedObjectIndex", item)
        h.call_routine("GetItemName", limit=600)
        out["name"] = h.read_bytes("wNameBuffer", 6)
        h.write8("wCurItem", item)
        h.call_routine("AcquireTMHM", limit=600)
        out["bitfield"] = h.read_bytes("sTMBitfield", 7)
        h.write8("wCurItem", item)
        h.call_routine("HasTMHM", limit=600)
        out["sp_after"] = (sp, h.pyboy.register_file.SP)
        out["bank"] = h.read8("hLoadedROMBank")
        return out

    def test_surf(self):
        print("\nHM_SURF", self._probe(HM_SURF), file=sys.stderr)

    def test_tm_control(self):
        print("\nTM_BODY_SLAM", self._probe(TM_BODY_SLAM), file=sys.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
