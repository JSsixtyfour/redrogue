"""Jessie and James each say their own line once beaten, on all four wild areas.

Their object slots differ per stage, so StageEventPrintAfterLine tells them apart by
picture. Each case enters a real stage with the event armed, dismisses the greeting,
marks both beaten, and opens the sprite's text through DisplayTextID.
"""

from __future__ import annotations

import io
import unittest
from pathlib import Path

from audit_stage_hideout_partner import stage_const
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
# (map, the pair's first slot, the first of its two beat flags)
STAGES = {"cave": ("PROCEDURAL_CAVE_1", 6, 262), "forest": ("PROCEDURAL_FOREST", 6, 262),
          "facility": ("PROCEDURAL_FACILITY", 10, 266),
          "cemetery": ("PROCEDURAL_CEMETERY_1", 2, 266)}
MASK, SHIFT = stage_const("STAGE_EVENT_PHASE_MASK"), stage_const("STAGE_EVENT_PHASE_SHIFT")
TYPE_MASK = stage_const("STAGE_EVENT_TYPE_MASK")
HIDING, SETTLED = stage_const("STAGE_EVENT_PHASE_HIDING"), stage_const("STAGE_EVENT_PHASE_SETTLED")
JESSIE_JAMES, PSYCHIC = stage_const("STAGE_EVENT_JESSIE_JAMES"), stage_const("STAGE_EVENT_PSYCHIC")


class StagePairAfterLinesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()
        self.lobby = io.BytesIO()
        self.h.save_state(self.lobby)

    def enter_beaten(self, stage: str, event: int) -> int:
        """In the stage, the greeting dismissed and the encounter settled. Returns the first slot."""
        h = self.h
        name, slot, flag = STAGES[stage]
        h.load_state(self.lobby)
        h.write8("wStageEvent", event)
        h.preload_and_enter_wild_area(self.maps[name], stage)
        for _ in range(120):
            if (h.read8("wStageEvent") & MASK) >> SHIFT == HIDING:
                break
            h.tap("a", 2)
            h.tick(18)
        self.assertEqual((h.read8("wStageEvent") & MASK) >> SHIFT, HIDING, "the greeting never ended")
        h.tick(120)
        h.write8("wStageEvent", h.read8("wStageEvent") & ~MASK & 0xFF | SETTLED << SHIFT)
        self.assertEqual(h.read8("wStageEvent") & TYPE_MASK, event)
        for bit in (flag, flag + 1):
            h.write8("wEventFlags", h.read8("wEventFlags", bit // 8) | 1 << bit % 8, offset=bit // 8)
        return slot

    def talk(self, slot: int) -> list[tuple[int, int]]:
        """(bank, address) of every text PrintText was given in bank $3A's handler."""
        h = self.h
        opened = []
        printed: list[tuple[int, int]] = []

        def open_box(_context) -> None:
            if not opened:
                opened.append(True)
                h.write8("hSpriteIndex", slot)
                h.pyboy.register_file.PC = h.symbols.get("DisplayTextID")[1]

        def printing(_context) -> None:
            printed.append((h.read8("hLoadedROMBank"), h.pyboy.register_file.HL))

        h.register_hook("JoypadOverworld", open_box)
        h.register_hook("PrintText", printing)
        try:
            for frame in range(500):
                h.tick(1)
                if opened and frame % 20 == 0:
                    h.tap("a", 2)
        finally:
            h.unregister_hook("JoypadOverworld", open_box)
            h.unregister_hook("PrintText", printing)
        self.assertTrue(opened, "the overworld never came back")
        self.assertEqual(h.read8("hIsInBattle"), 0)
        after = h.symbols.bank("StageEventPrintAfterLine")
        return [line for line in printed if line[0] == after]

    def test_each_of_the_pair_has_a_line(self) -> None:
        h = self.h
        for stage in STAGES:
            with self.subTest(stage=stage):
                slot = self.enter_beaten(stage, JESSIE_JAMES)
                state = io.BytesIO()
                h.save_state(state)
                for which, sprite, label in ((slot, "SPRITE_JESSIE", "StageEventAfterJessie"),
                                             (slot + 1, "SPRITE_JAMES", "StageEventAfterJames")):
                    state.seek(0)
                    h.load_state(state)
                    self.assertEqual(h.read8(f"wSprite{which:02d}StateData1PictureID"),
                                     self.sprites[sprite])
                    self.assertEqual(self.talk(which), [h.symbols.get(label)])

    def test_a_single_villain_still_uses_the_table(self) -> None:
        slot = self.enter_beaten("cave", PSYCHIC)
        self.assertEqual(self.talk(slot), [self.h.symbols.get("StageEventAfterPsychic")])


if __name__ == "__main__":
    unittest.main()
