"""The Cemetery's stage-event pair: never seals a floor, and an OWED pair stays to be collected from.

A pair stays solid until the floor next loads, and an OWED pair stays across loads, so a
rolled hideout must not cut off the exit (it did on 3 of 40 rolled floors). An OWED villain still
holds the player's goods: it used to be parked off the map by the next load, losing them.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from audit_stage_hideout_partner import stage_const
from harness import RedRogueHarness
from source_constants import parse_map_constants
from witch_probe_cem_seal import measure

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"


class CemeteryStagePairTest(unittest.TestCase):
    def test_rolled_hideouts_do_not_seal_the_floor(self) -> None:
        rolled = 0
        for seed in range(8):
            for row in measure(seed):
                self.assertNotIn("error", row)
                self.assertTrue(row["exit_reachable"], row)
                if row["rolled_cell"]:
                    rolled += 1
                    self.assertFalse(row["rolled_seals"], row)
        self.assertGreater(rolled, 0, "no hideout was rolled, so this proved nothing")

    def test_phase_decides_whether_the_pair_stays(self) -> None:
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        floors = [maps[f"PROCEDURAL_CEMETERY_{n}"] for n in (1, 2, 3, 4)]
        shift = stage_const("STAGE_EVENT_PHASE_SHIFT")
        jessie = stage_const("STAGE_EVENT_JESSIE_JAMES")
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.write8("wStageEvent", jessie | (1 << shift))
        h.preload_and_enter_wild_area(floors[0], "Procedural Cemetery 1")
        h.tick(60)
        rolled = h.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
        h.park_before_hijack()
        h.write8("hCurMap", floors[rolled])
        h.call_routine("PCemFinalizeMap", limit=200000)
        x = h.read_sram_bytes("sStageEventHideoutX", 1, bank=0)[0]
        y = h.read_sram_bytes("sStageEventHideoutY", 1, bank=0)[0]
        for name, stays in (("HIDING", True), ("OWED", True), ("SETTLED", False)):
            h.write8("wStageEvent", jessie | (stage_const(f"STAGE_EVENT_PHASE_{name}") << shift))
            h.write8("wSprite02StateData2MapY", 0x77)
            h.write8("wSprite02StateData2MapX", 0x77)
            h.park_before_hijack()
            h.write8("hCurMap", floors[rolled])
            h.call_routine("PCemPlaceStageEventNpcs", limit=20000)
            where = (h.read8("wSprite02StateData2MapX") - 4, h.read8("wSprite02StateData2MapY") - 4)
            self.assertEqual(where, (x * 2, y * 2) if stays else (-4, -4), name)


if __name__ == "__main__":
    unittest.main()
