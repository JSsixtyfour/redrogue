"""Interrupted writers must not publish a checksum-colliding partial save."""
import io
import unittest
from pathlib import Path

from harness import RedRogueHarness
import save_reload
from autoplay_branch import Snapshot

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent / "artifacts" / "save_commit_guard"


class SaveCommitGuardTest(unittest.TestCase):
    cgb = False

    def setUp(self):
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.cgb)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()

    def boot(self, image):
        boot = save_reload.Reboot(image, cgb_mode=self.cgb)
        self.addCleanup(boot.close)
        texts = []
        boot.h.register_hook("PrintText", lambda _: texts.append(boot.h.pyboy.register_file.HL))
        boot.load()
        self.assertFalse(boot.h.hook_errors)
        return boot, texts

    def test_checksum_collision_cut_is_refused_and_completed_save_loads(self):
        h = self.h
        # Both legal BCD amounts sum to $10. The partial new main-data block
        # therefore collides with the old checksum, while party HP differs.
        for i, value in enumerate((0, 0x10, 0)):
            h.write8("wPlayerMoney", value, offset=i)
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", 1, offset=1)
        h.call_routine("SaveGameData")
        old = save_reload.sram_image(h)
        for i, value in enumerate((0, 9, 7)):
            h.write8("wPlayerMoney", value, offset=i)
        h.write8("wPartyMon1HP", 2, offset=1)
        cuts = []
        h.register_hook("SaveGameData.copySprites", lambda _: cuts.append(save_reload.sram_image(h)))
        h.call_routine("SaveGameData")
        self.assertEqual(len(cuts), 1)
        image = cuts[0]
        bank, start = h.symbols.get("sGameData")
        begin = bank * 8192 + start - 0xA000
        end = begin + h.address("sGameDataEnd") - start
        cb, address = h.symbols.get("sMainDataCheckSum")
        checksum_offset = cb * 8192 + address - 0xA000
        self.assertEqual((~sum(image[begin:end])) & 255, image[checksum_offset],
                         "fixture must reproduce an actual old-checksum collision")
        self.assertEqual(image[checksum_offset], old[checksum_offset])
        boot, texts = self.boot(image)
        self.assertEqual(boot.status, 1, "colliding partial save was accepted")
        self.assertIn(boot.h.address("FileDataDestroyedText"), texts)
        self.assertNotIn(boot.h.address("SaveNeedsConvertingText"), texts)
        boot, _ = self.boot(save_reload.sram_image(h))
        self.assertEqual(boot.status, 2)
        self.assertTrue(boot.overworld)

    def test_all_writer_paths_hold_invalid_header_until_checksum_commit(self):
        h = self.h
        headers = []
        h.register_hook("StoreSaveChecksum", lambda _: headers.append(
            save_reload.sram_image(h)[0x2040:0x2048]))
        for routine in ("SaveGameData", "SaveMainData", "SaveCurrentBoxData", "SavePartyAndDexData"):
            with self.subTest(routine=routine):
                headers.clear()
                h.call_routine(routine)
                self.assertEqual(len(headers), 1)
                self.assertEqual(headers[0][0], 0xAD)
                self.assertEqual(headers[0][1:4], b"RSG")
                self.assertEqual(save_reload.sram_image(h)[0x2040:0x2044], b"RRSG")
        self.assertFalse(h.hook_errors)

    def test_wrong_schema_marker_still_uses_conversion_refusal(self):
        h = self.h
        h.call_routine("SaveGameData")
        image = bytearray(save_reload.sram_image(h))
        image[0x2040] = 0xAD
        image[0x2046] ^= 1
        boot, texts = self.boot(bytes(image))
        self.assertEqual(boot.status, 1)
        self.assertIn(boot.h.address("SaveNeedsConvertingText"), texts)

    def test_sampled_full_save_cuts_never_load_a_mixed_checkpoint(self):
        h = self.h
        stream = io.BytesIO()
        h.save_state(stream)
        older = Snapshot("lobby", 1, 0, {}, stream.getvalue())
        h.write8("wPlayerMoney", 0)
        h.write8("wPlayerMoney", 9, offset=1)
        h.write8("wPlayerMoney", 7, offset=2)
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", 2, offset=1)
        stream = io.BytesIO()
        h.save_state(stream)
        newer = Snapshot("lobby", 2, 0, {}, stream.getvalue())
        cuts = save_reload.power_cuts(h, older, newer, cgb_mode=self.cgb)
        self.assertGreaterEqual(len(cuts), 8)
        self.assertTrue(any(cut["loads"] == "refused" for cut in cuts))
        self.assertTrue(all(cut["loads"] in ("old", "new", "unchanged", "refused")
                            and not cut["detector_errors"] for cut in cuts), cuts)
        self.assertIn(cuts[-1]["loads"], ("new", "unchanged"))
