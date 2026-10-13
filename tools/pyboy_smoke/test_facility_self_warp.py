"""A warp from the Facility back into itself must not change stage state.

PROCEDURAL_SUBROOMS_PLAN Phase 1. Until warp pads and subrooms, nothing ever
re-entered a Facility in the same stage, so three latent problems were never
exercised:

  * every warp clears EVENT_ENTER_ROOM, and the map script's fresh-entry block
    re-showed all four item balls, so a collected ball came back (item dupe);
  * the +5 wild-area exit credit keys on wWarpedFromWhichMap, which a
    self-warp rewrites to PROCEDURAL_FACILITY;
  * the LAST_MAP exit relies on wLastMap still naming the lobby.

The self-warp is a real engine warp: warp 0 (the south entrance, normally
LAST_MAP) is retargeted at the Facility's own warp 0 and the player steps off
the south edge, so WarpFound2's indoor path runs exactly as a pad would.
"""

from __future__ import annotations

import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SELF_WARPS = 3
BIT_PFAC_OBJECTS_SHOWN = 7  # scripts/ProceduralFacility.asm
LAST_MAP = 0xFF


class FacilitySelfWarpTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        self.events = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
        rounds = parse_rgbds_constants(ROOT / "constants/round_constants.asm")
        self.exit_battles = parse_rgbds_constants(
            ROOT / "constants/balance_constants.asm", rounds
        )["WILD_AREA_EXIT_BATTLES"]
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def hidden(self, toggle: str) -> bool:
        index = self.toggles[toggle]
        return bool(self.h.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8)

    def hide(self, toggle: str) -> None:
        index = self.toggles[toggle]
        byte = self.h.read8("wToggleableObjectFlags", offset=index // 8)
        self.h.write8("wToggleableObjectFlags", byte | 1 << index % 8, offset=index // 8)

    def step_off_south_edge(self, arrive_map: int, description: str) -> None:
        h = self.h
        h.wait_until(lambda: h.read8("wYCoord") == 39, f"{description}: back on the entrance", 600)
        start = h.read8("wWarpedFromWhichMap"), h.pyboy.frame_count
        h.pyboy.button_press("down")
        try:
            h.wait_until(
                lambda: h.read8("hCurMap") == arrive_map
                and h.read8("wWarpedFromWhichMap") == self.maps["PROCEDURAL_FACILITY"]
                and h.pyboy.frame_count - start[1] > 20,
                description,
                600,
            )
        finally:
            h.pyboy.button_release("down")
        h.tick(180)

    def test_self_warp_keeps_balls_boss_count_and_exit(self) -> None:
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        lobby = self.maps["INDIGO_PLATEAU_LOBBY"]
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)  # no arrival text box to block the walk
        h.preload_and_enter_wild_area(facility, "facility")
        self.assertEqual(h.read8("wWarpedFromWhichMap"), lobby)
        # The harness retargets the lobby doors straight at the Facility, so the
        # warp skips WarpFound2's .randomStage path, the one place a real
        # ROGUE_MAP lobby door writes wLastMap = lobby. Restore what play has.
        h.write8("wLastMap", lobby)

        # As if ball 1 were picked up and the boss beaten (and its join offer
        # already shown, so that one-shot text cannot block input).
        self.hide("TOGGLE_WILD_AREA_POKEBALL_1")
        self.hide("TOGGLE_WILD_AREA_BOSS")
        h.set_event(self.events["EVENT_BEAT_PC_BOSS"])
        h.set_event(self.events["EVENT_PC_BOSS_OFFERED"])

        battle_count = h.read8("wBattleCount")
        last_map = h.read8("wLastMap")
        layout = h.read_bytes("wOverworldMap", 601)
        self.assertEqual(h.warp_entries()[0][2:], [0, LAST_MAP],
                         "entrance warp is no longer the LAST_MAP warp this test retargets")
        self.assertTrue(
            h.read_sram_bytes("sProcFacilityItemGot", 1)[0] & 1 << BIT_PFAC_OBJECTS_SHOWN,
            "first entry did not record that the stage's objects were shown",
        )

        for warp in range(SELF_WARPS):
            # wWarpEntries is reloaded from ROM on every map load: re-patch.
            h.write8("wWarpEntries", 0, offset=2)          # dest warp 0 (0-based)
            h.write8("wWarpEntries", facility, offset=3)   # dest map: here
            self.step_off_south_edge(facility, f"self-warp {warp + 1}")

            with self.subTest(warp=warp + 1):
                self.assertTrue(self.hidden("TOGGLE_WILD_AREA_POKEBALL_1"),
                                "collected ball re-shown by the re-entry")
                self.assertTrue(self.hidden("TOGGLE_WILD_AREA_BOSS"), "beaten boss re-shown")
                for ball in (2, 3, 4):
                    self.assertFalse(self.hidden(f"TOGGLE_WILD_AREA_POKEBALL_{ball}"),
                                     f"uncollected ball {ball} hidden")
                self.assertEqual(h.read8("wBattleCount"), battle_count)
                self.assertEqual(h.read8("wLastMap"), last_map)
                self.assertEqual(h.read_bytes("wOverworldMap", 601), layout,
                                 "re-entry regenerated the layout")

        # Leaving through the untouched entrance still reaches the lobby and is
        # still credited exactly once, after any number of self-warps.
        self.step_off_south_edge(lobby, "exit to lobby")
        self.assertEqual(h.read8("wBattleCount"), battle_count + self.exit_battles)


if __name__ == "__main__":
    unittest.main()
