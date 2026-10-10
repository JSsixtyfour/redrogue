"""FOLLOWUPS #64: preload must wait for live lobby work to finish."""
import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]


class WildAreaPreloadTest(unittest.TestCase):
    def test_facility_entry_from_lobby_initialization_timing(self):
        """Offset zero reproduced the live evolution-pointer corruption.

        Restoring CPU registers/banks was insufficient: a nested preload
        overwrote wEvoDataBuffer while the interrupted caller still used it.
        Replay nearby timings too, without a build-specific saved state.
        """
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.boot_to_lobby(battle_count=11, encounter_kind=4)
            baseline = io.BytesIO()
            h.save_state(baseline)
            facility = parse_map_constants(ROOT / "constants/map_constants.asm")["PROCEDURAL_FACILITY"]
            for offset in (0, 1, 2, 7, 24):
                with self.subTest(offset=offset):
                    h.load_state(baseline)
                    h.tick(offset)
                    # Disable arrival theft so it cannot legitimately change
                    # the party while we check for corrupt execution.
                    h.write8("wStageEvent", 0)
                    party = h.read_bytes("wPartySpecies", 7)
                    original_hooks = set(h._hook_callbacks)
                    h.preload_and_enter_wild_area(facility, "facility")
                    self.assertEqual(h.read8("hCurMap"), facility)
                    self.assertEqual(h.read_bytes("wPartySpecies", 7), party)
                    self.assertEqual(set(h._hook_callbacks), original_hooks)
                    h.move_tile("up")
                    self.assertLess(h.read8("wYCoord"), 39, "player cannot move after entry")
        finally:
            h.close()

    def test_preload_preserves_existing_script_hook_and_does_not_repeat(self):
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.boot_to_lobby()
            observer = h.hook_flag("IndigoPlateauLobby_Script")
            preloads = h.hook_flag("ProcPreloadAssignedWildArea")
            facility = parse_map_constants(ROOT / "constants/map_constants.asm")["PROCEDURAL_FACILITY"]
            h.preload_wild_area(facility)
            observed = observer["count"]
            generated = preloads["count"]
            h.tick(30)
            self.assertGreater(observer["count"], observed)
            self.assertEqual(preloads["count"], generated)
            self.assertEqual(h.read8("wLobbyDoor1StageMap"), facility)
        finally:
            h.close()
