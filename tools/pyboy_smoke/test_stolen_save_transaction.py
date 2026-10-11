"""The raw theft holder must roll back with the saved party and run state."""
import unittest

from harness import RedRogueHarness
from test_save_header import ARTIFACTS, REPO_ROOT


class StolenSaveTransactionTest(unittest.TestCase):
    def test_continue_restores_complete_holder_and_party_from_same_save(self):
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            party = h.read_bytes("wPartyMons", 44)
            for kind in (0, 1, 2, 255):
                with self.subTest(kind=kind):
                    holder = [kind] + [(i * 17 + 3) & 255 for i in range(1, 57)]
                    h.write_sram_bytes("sStolenRecord", holder)
                    h.call_routine("SaveGameData")
                    h.write_sram_bytes("sStolenRecord", [0xA5] * 57)
                    h.write8("wPartyMon1Species", 0)
                    h.call_routine("LoadMainData")
                    # Party data is restored by the ordinary separate loader.
                    h.call_routine("LoadPartyAndDexData")
                    self.assertEqual(h.read_sram_bytes("sStolenRecord", 57), holder)
                    self.assertEqual(h.read_bytes("wPartyMons", 44), party)
            # Failed validation must leave the live holder alone.
            h.write_sram_bytes("sStolenRecord", [0xA5] * 57)
            checksum = h.read_sram_bytes("sMainDataCheckSum", 1)[0]
            h.write_sram_bytes("sMainDataCheckSum", [checksum ^ 1])
            h.call_routine("LoadMainData")
            self.assertEqual(h.read_sram_bytes("sStolenRecord", 57), [0xA5] * 57)
        finally:
            h.close()
