"""Wild-area balls hold real rolled items.

From 2026-09-16 to 2026-10-14 every Facility stored the same four "items"
(SUPER POTION, X ACCURACY or LIFT KEY, POKE DOLL, RARE CANDY): PFacPlaceItems
rolled into wBuffer 12-15 and PFacFinalize copied them out only after
PFacDecorateCorridorWalls had reused those bytes as its own scratch. The game
then handed out the leftovers. Nothing checked the items themselves.

This test generates several real layouts of each procedural stage and asserts
that every ball's item is one Random_Item_Selection can produce (an entry of
engine/items/item_rarity.asm's pools, or a TM/HM), that what the pickup reads
(wRogueItem's four slots) is what was saved, and that the items are not the
same in every layout.
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
LAYOUTS = 12
TM_HM = set(range(0xC4, 0x100))         # HM01-HM05, TM01-TM50 (macro-defined ids)


def pool_items() -> set[int]:
    names = {}
    for line in (ROOT / "constants/item_constants.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*const (\w+)\s*; \$([0-9A-Fa-f]+)", line)
        if m:
            names[m.group(1)] = int(m.group(2), 16)
    text = (ROOT / "engine/items/item_rarity.asm").read_text(encoding="utf-8")
    return {names[tok] for tok in re.findall(r"^db (\w+)", text, re.M) if tok in names} | TM_HM


class WildAreaBallItemsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.pool = pool_items()
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def check(self, layouts: list[list[int]], stage: str) -> None:
        for items in layouts:
            for item in items:
                self.assertIn(item, self.pool, f"{stage}: item {item:#x} is in no pool ({items})")
        self.assertGreater(len({tuple(items) for items in layouts}), 1,
                           f"{stage}: every layout has the same items {layouts[0]}")

    def test_facility_balls(self) -> None:
        h = self.h
        h.boot_to_lobby()
        h.call_routine("PFacPreload", limit=60000)
        base = io.BytesIO()
        h.save_state(base)
        layouts = []
        for n in range(LAYOUTS):
            h.load_state(base)
            h.write_sram_bytes("sProcFacilityExitEdge", [0])
            h.seed_rng([n + 1, 7 * n + 3, 13 * n + 5, 29 * n + 11])
            h.call_routine("PFacFinalize", limit=4000)
            saved = h.read_sram_bytes("sProcFacilityBallItems", 4)
            self.assertEqual([h.read8("wRogueItem", offset=2 * k) for k in range(4)], saved,
                             "the pickup slots differ from the saved items")
            layouts.append(saved)
        self.check(layouts, "Facility")

    def test_cave_balls(self) -> None:
        h = self.h
        cave = parse_map_constants(ROOT / "constants/map_constants.asm")["PROCEDURAL_CAVE_1"]
        h.boot_to_lobby()
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        layouts = []
        for n in range(LAYOUTS // 3):
            h.load_state(lobby)
            h.tick(n * 7)
            h.preload_and_enter_wild_area(cave, "cave")
            saved = h.read_sram_bytes("sProcCaveBallItems", 4, bank=0)
            self.assertEqual([h.read8("wRogueItem", offset=2 * k) for k in range(4)], saved,
                             "the pickup slots differ from the saved items")
            layouts.append(saved)
        self.check(layouts, "cave")


if __name__ == "__main__":
    unittest.main()
