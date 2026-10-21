"""Full saves publish once; standalone partial saves keep their old regions."""
import io
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT


class SaveWriterTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()

    def data(self, label, end):
        return self.h.read_sram_bytes(label, self.h.address(end) - self.h.address(label))

    def test_full_save_copies_regions_and_publishes_one_fused_checksum(self):
        h = self.h
        regions = (("wPlayerName", "sPlayerName", 11),
                   ("wMainDataStart", "sMainData", h.address("wMainDataEnd") - h.address("wMainDataStart")),
                   ("wSpriteDataStart", "sSpriteData", h.address("wSpriteDataEnd") - h.address("wSpriteDataStart")),
                   ("wPartyDataStart", "sPartyData", h.address("wPartyDataEnd") - h.address("wPartyDataStart")),
                   ("wBoxDataStart", "sCurBoxData", h.address("wBoxDataEnd") - h.address("wBoxDataStart")))
        visits, scans, commits, expected = [], [], [], {}
        seams = ("copyName", "copyMain", "copySprites", "copyParty", "copyBox")
        for seam, (source, dest, length) in zip(seams, regions):
            def capture(_, source=source, dest=dest, length=length):
                visits.append(dest)
                expected[dest] = h.read_bytes(source, length)
            h.register_hook("SaveGameData." + seam, capture)
        h.register_hook("CalcCheckSum", lambda _: scans.append(True))
        h.register_hook("StoreSaveChecksum", lambda _: commits.append(tuple(visits)))
        h.call_routine("SaveGameData")
        self.assertCountEqual(visits, [r[1] for r in regions])
        self.assertEqual(commits, [tuple(visits)])
        self.assertEqual(scans, [], "full saves must not reread the payload")
        for _source, dest, length in regions:
            self.assertEqual(h.read_sram_bytes(dest, length), expected[dest], dest)
        payload = self.data("sGameData", "sGameDataEnd")
        self.assertEqual(h.read_sram_bytes("sMainDataCheckSum", 1), [~sum(payload) & 255])
        self.assertFalse(h.hook_errors, h.hook_errors)

    def test_fused_copy_handles_zero_tails_pages_and_checksum_wrap(self):
        h = self.h
        state = io.BytesIO()
        h.save_state(state)
        source = h.address("wOverworldMap")
        dest = h.address("sSpriteBuffer0") + 1
        request, result = {}, {}

        def start(_):
            registers = h.pyboy.register_file
            registers.A = request["seed"]
            registers.B = request["length"] >> 8
            registers.C = request["length"] & 255
            registers.HL = source
            registers.D, registers.E = dest >> 8, dest & 255
            h.pyboy.memory[0x0000] = 0x0A
            h.pyboy.memory[0x4000] = 0

        def done(_):
            length = request["length"]
            result.update(checksum=h.pyboy.register_file.C,
                          source_end=h.pyboy.register_file.HL,
                          dest_end=h.pyboy.register_file.D << 8 | h.pyboy.register_file.E,
                          data=bytes(h.pyboy.memory[0, dest - 1 + i] for i in range(length + 2)))

        h.register_hook("CopySaveDataAndSum", start)
        h.register_hook("CopySaveDataAndSum.done", done)
        for length in (0, 1, 3, 4, 255, 256, 257, 511, 512, 1024, 1025):
            with self.subTest(length=length):
                h.load_state(io.BytesIO(state.getvalue()))
                request.update(length=length, seed=(length * 73 + 19) & 255)
                result.clear()
                data = bytes((i * 37 + length + 17) & 255 for i in range(length))
                for i, value in enumerate(data):
                    h.pyboy.memory[source + i] = value
                for i, value in enumerate(bytes([0xD3]) + bytes([0x55]) * length + bytes([0xAC])):
                    h.pyboy.memory[0, dest - 1 + i] = value
                h.call_routine("CopySaveDataAndSum", limit=60)
                self.assertEqual(result["data"], bytes([0xD3]) + data + bytes([0xAC]))
                self.assertEqual(result["checksum"], (request["seed"] + sum(data)) & 255)
                self.assertEqual(result["source_end"], source + length)
                self.assertEqual(result["dest_end"], dest + length)
        self.assertFalse(h.hook_errors, h.hook_errors)

    def test_partial_saves_preserve_unrelated_regions_and_theft_snapshot(self):
        h = self.h
        h.call_routine("SaveGameData")
        baseline = io.BytesIO()
        h.save_state(baseline)
        spans = (("sMainData", "sSpriteData"), ("sPartyData", "sCurBoxData"),
                 ("sCurBoxData", "sTileAnimations"))
        for routine in ("SaveMainData", "SaveCurrentBoxData", "SavePartyAndDexData"):
            with self.subTest(routine=routine):
                h.load_state(io.BytesIO(baseline.getvalue()))
                before = {start: self.data(start, end) for start, end in spans}
                old_snapshot = h.read_sram_bytes("sMainData", len(before["sMainData"]))
                # Distinct edits identify which save regions the entry owns.
                h.write8("wPlayerMoney", h.read8("wPlayerMoney") ^ 1)
                h.write8("wPokedexOwned", h.read8("wPokedexOwned") ^ 1)
                h.write8("wPartyMon1HP", h.read8("wPartyMon1HP") ^ 1, offset=1)
                h.write8("wBoxCount", h.read8("wBoxCount") ^ 1)
                h.write_sram_bytes("sStolenRecord", [0xA5] * 57)
                h.call_routine(routine)
                after = {start: self.data(start, end) for start, end in spans}
                expected_changed = {
                    "SaveMainData": {"sMainData", "sCurBoxData"},
                    "SaveCurrentBoxData": {"sCurBoxData"},
                    "SavePartyAndDexData": {"sMainData", "sPartyData"},
                }[routine]
                self.assertEqual({key for key in before if before[key] != after[key]}, expected_changed)
                offset = h.address("wStolenSaveSnapshot") - h.address("wMainDataStart")
                expected_holder = [0xA5] * 57 if routine == "SaveMainData" else old_snapshot[offset:offset + 57]
                self.assertEqual(after["sMainData"][offset:offset + 57], expected_holder)
                if routine == "SavePartyAndDexData":
                    dex_len = h.address("wPokedexSeenEnd") - h.address("wPokedexOwned")
                    self.assertEqual(after["sMainData"][dex_len:], before["sMainData"][dex_len:])
                payload = self.data("sGameData", "sGameDataEnd")
                self.assertEqual(h.read_sram_bytes("sMainDataCheckSum", 1), [~sum(payload) & 255])

    def test_dmg_full_save_preserves_gamma_preference(self):
        h = self.h
        event = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")["EVENT_GAMMA_SHADER"]
        h.set_event(event)
        h.call_routine("SaveGameData")
        self.assertTrue(h.event_is_set(event))
