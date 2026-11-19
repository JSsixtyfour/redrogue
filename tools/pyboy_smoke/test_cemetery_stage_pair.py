"""The Cemetery's stage-event pair: never seals a floor, and an OWED pair stays to be collected from.

A pair stays solid until the floor next loads, and an OWED pair stays across loads, so a
rolled hideout must not cut off the exit (it did on 3 of 40 rolled floors). An OWED villain still
holds the player's goods: it used to be parked off the map by the next load, losing them.
"""
from __future__ import annotations

import io
import random
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

    def test_premade_entrance_cell_is_floor_for_every_prefab(self) -> None:
        # Floor 1's arrival pair is hardcoded onto block (2,4). Four prefabs
        # (DropE, Tower4F/5F/6F) had a grave there, so the ambush stood on a
        # tombstone; PCemClearPremadeEntrance now opens each floor's inner
        # entrance cell, with the prefab's own floor block (54 for the Towers).
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        floors = [maps[f"PROCEDURAL_CEMETERY_{n}"] for n in (1, 2, 3, 4)]
        entrance = [(2, 4), (8, 4), (2, 4), (8, 4)]  # PCemFloorGeometry entX/entY
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.park_before_hijack()
        baseline = io.BytesIO()
        h.pyboy.save_state(baseline)
        rng = random.Random(0)
        for floor, (x, y) in enumerate(entrance):
            seen: set[int] = set()
            for _ in range(120):
                if len(seen) == 11:
                    break
                baseline.seek(0)
                h.pyboy.load_state(baseline)
                for offset in range(10):
                    h.write8("wRandomTable", rng.randrange(1, 256), offset=offset)
                h.write_sram_bytes("sProcCemeteryReady", [0], bank=0)
                h.write_sram_bytes("sProcCemeteryUsedPrefabs", [0, 0], bank=0)
                h.write8("wProcCemDebugMode", 3)  # force the premade branch
                h.write8("hCurMap", floors[floor])
                h.call_routine("PCemFinalizeMap", limit=200000)
                prefab = h.read8("wBuffer", 19)  # wCemPrefabIndex
                seen.add(prefab)
                cell = h.read_sram_bytes("sProcCemeteryMaps", 90 * (floor + 1), bank=0)[
                    90 * floor + y * 10 + x]
                with self.subTest(floor=floor + 1, prefab=prefab):
                    self.assertEqual(cell, 14 if prefab < 7 else 54)
            self.assertEqual(len(seen), 11, f"floor {floor + 1} only rolled prefabs {sorted(seen)}")

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
