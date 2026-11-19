"""Bridge selected-effect records: four of them, and a full registry stops
offering the gifts that need one (2026-11-19).

The grant (BridgeGrantSelectedEffect) refuses when every record is taken, and
the gift menu's failure path is silent, so the pick was lost. Endless keeps the
records across circuits while every circuit offers two more bridges, so this
happened from the second circuit on. BridgeGiftIsEligible now offers a
selected-effect gift only while a record is free; DETOX, which takes the same
gift path but costs no record, stays eligible.
"""

from __future__ import annotations

import io
import re
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
RECORDS = 4
CARRY = 0x10


def warden_index(param: str) -> int:
    """The Warden's gift-list index of the entry whose parameter is `param`."""
    text = (ROOT / "engine/events/bridge_gift_menu.asm").read_text()
    body = text.split("WardenGiftList:", 1)[1].split("\n\n", 1)[0]
    entries = re.findall(r"^\s*gift_entry\s+(\w+),\s*(\w+)", body, re.M)
    return next(i for i, (_kind, p) in enumerate(entries) if p == param)


class BridgeRegistryRoomTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_to_lobby(battle_count=11, encounter_kind=4)
        # A fresh park point per call: chained call_routines corrupt it.
        self.baseline = io.BytesIO()
        self.h.save_state(self.baseline)

    def tearDown(self) -> None:
        self.h.close()

    def set_records(self, owners: list[int]) -> None:
        h = self.h
        for i in range(RECORDS):
            owner = owners[i] if i < len(owners) else 0
            h.write8("wBridgeSelectedEffects", owner, offset=2 * i)
            h.write8("wBridgeSelectedEffects", 3 if owner else 0, offset=2 * i + 1)

    def eligible(self, index: int, owners: list[int]) -> bool:
        h = self.h
        self.baseline.seek(0)
        h.load_state(self.baseline)
        self.set_records(owners)
        real_map = h.read8("hCurMap")
        h.write8("hCurMap", MAPS["WARDENS_HOUSE"])   # GetGiverIndex reads it: the Warden's list
        h.write8("wBuffer", index, offset=3)
        seen = {}
        try:
            h.call_routine("BridgeGiftIsEligible",
                           capture=lambda hh: seen.update(f=hh.pyboy.register_file.F))
        finally:
            h.write8("hCurMap", real_map)
        return bool(seen["f"] & CARRY)

    def test_four_records_exist(self) -> None:
        h = self.h
        size = h.address("wBridgeSelectedEffectsEnd") - h.address("wBridgeSelectedEffects")
        self.assertEqual(size, 2 * RECORDS)

    def test_selected_gift_only_while_a_record_is_free(self) -> None:
        flinch = warden_index("BRIDGE_SELECTED_EFFECT_FLINCH")
        detox = warden_index("BRIDGE_GIFT_STRIP_POISON")
        for owners, room in (([], True), ([1], True), ([1, 2, 3], True), ([1, 2, 3, 4], False),
                             ([1, 0, 3, 4], True)):
            with self.subTest(owners=owners):
                self.assertEqual(self.eligible(flinch, owners), room, "selected-effect gift")
                self.assertTrue(self.eligible(detox, owners), "DETOX costs no record")


if __name__ == "__main__":
    unittest.main()
