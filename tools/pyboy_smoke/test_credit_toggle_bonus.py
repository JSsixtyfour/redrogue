"""Runtime contract for expansion-sensitive credit awards.

Credits are boosted by the live PC toggle mask, not merely by progression
events or unlock eligibility. Set both persistent activation events so both
expansion groups are eligible, then exercise every toggle combination directly
through the shipped award routine.
"""

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT


GROUP_CONSTANTS = REPO_ROOT / "constants" / "rogue_species_groups.asm"
RAM_CONSTANTS = REPO_ROOT / "constants" / "ram_constants.asm"
EVENT_CONSTANTS = REPO_ROOT / "constants" / "event_constants.asm"


class CreditToggleBonusTest(HarnessTestCase):
    def test_live_expansion_toggles_control_bonus(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)

        groups = parse_rgbds_constants(GROUP_CONSTANTS)
        ram = parse_rgbds_constants(RAM_CONSTANTS)
        events = parse_rgbds_constants(EVENT_CONSTANTS)
        johto = 1 << groups["BIT_GROUP_JOHTO"]
        warp = 1 << groups["BIT_GROUP_WARP"]

        # Debug 2 bypasses the SRAM toggles, so explicitly keep the ordinary
        # progression path active for this contract.
        flags = h.read8("wStatusFlags6")
        flags &= ~(1 << ram["BIT_DEBUG2_MODE"]) & 0xFF
        h.write8("wStatusFlags6", flags)
        h.set_event(events["EVENT_JOHTO_ACTIVATED"])
        h.set_event(events["EVENT_KANTO_TIMEWARP_ACTIVATED"])

        for enabled, expected in (
            (0, 1),
            (johto, 2),
            (warp, 2),
            (johto | warp, 3),
        ):
            with self.subTest(enabled=enabled):
                h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled], bank=1)
                h.write8("wPlayerCoins", 0)
                h.write8("wPlayerCoins", 0, offset=1)
                h.write8("wCreditsEarnedThisRun", 0)
                h.park_before_hijack()
                h.call_routine("RogueAwardCredits1")
                self.assertEqual(h.read_bytes("wPlayerCoins", 2), [0, expected])
                self.assertEqual(h.read8("wCreditsEarnedThisRun"), expected)
