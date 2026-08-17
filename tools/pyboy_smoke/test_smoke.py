from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from text_contract import EndBattleContract, overlong_segments, rendered_end_battle_width


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class HarnessTestCase(unittest.TestCase):
    harness: RedRogueHarness | None = None

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)

    def run(self, result=None):
        completed_result = super().run(result)
        if self.harness is not None:
            failed = any(
                test is self
                for test, _ in completed_result.failures + completed_result.errors
            )
            if failed:
                image, state = self.harness.write_failure_artifacts(self.id())
                print(f"\nFailure artifacts: {image} {state}")
            self.harness.close()
        return completed_result


class BootSmokeTest(HarnessTestCase):
    def test_boot_to_lobby(self) -> None:
        assert self.harness is not None
        self.harness.boot_to_lobby()
        self.assertEqual(self.harness.read8("hCurMap"), self.harness.LOBBY_MAP)
        self.assertEqual(
            [self.harness.read8("wXCoord"), self.harness.read8("wYCoord")],
            [7, 11],
        )
        self.assertEqual(self.harness.read8("wNumberOfWarps"), 4)
        self.assertNotEqual(self.harness.read8("wLobbyDoor1StageMap"), 0)
        self.assertNotEqual(self.harness.read8("wLobbyDoor2StageMap"), 0)


class UndergroundRouteSmokeTest(HarnessTestCase):
    def test_standard_route_contract_and_reward_trigger(self) -> None:
        assert self.harness is not None
        self.harness.boot_to_lobby()
        self.harness.enter_route_door1()

        self.assertEqual(self.harness.read8("hCurMap"), self.harness.TARGET_ROUTE)
        self.assertEqual(self.harness.read8("wYCoord"), 5)
        self.assertGreaterEqual(self.harness.read8("wXCoord"), 5)
        self.assertEqual(
            self.harness.warp_entries(),
            [
                [5, 2, 0, self.harness.WARP_NO_RETURN],
                [2, 47, 0, self.harness.LOBBY_MAP],
            ],
        )
        self.assertEqual(self.harness.read8("wNumSprites"), 10)

        trainer_classes = self.harness.read_bytes("wMapSpriteExtraData", 10)[::2]
        self.assertEqual(trainer_classes, [0xD2, 0xDD, 0xD3, 0xD2, 0xD8])

        # Trainer events $3F9-$3FD are bits 1-5 of event byte $7F.
        event_address = self.harness.address("wEventFlags") + 0x7F
        self.harness.pyboy.memory[event_address] |= 0x3E

        events = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
        offered_event = events["EVENT_ROGUE_POKEMON_OFFERED"]
        offered_address = self.harness.address("wEventFlags") + offered_event // 8
        offered_mask = 1 << (offered_event % 8)
        self.harness.wait_until(
            lambda: bool(self.harness.pyboy.memory[offered_address] & offered_mask),
            "EVENT_ROGUE_POKEMON_OFFERED",
            600,
        )

    def test_giovanni_replaces_slot_five(self) -> None:
        assert self.harness is not None
        self.harness.boot_to_lobby()
        self.harness.enter_route_door1(giovanni=True)

        slot_five_picture = self.harness.read8(
            "wSprite01StateData1PictureID", offset=4 * 16
        )
        slot_five_class = self.harness.read8("wMapSpriteExtraData", offset=4 * 2)
        self.assertTrue(self.harness.read8("wRogueFlagsBitfield") & 0x80)
        self.assertEqual(slot_five_picture, 0x17)  # SPRITE_GIOVANNI
        self.assertEqual(slot_five_class, 0xF9)  # OPP_GIOVANNI_MINIBOSS


class TextContractSmokeTest(unittest.TestCase):
    def test_underground_route_text_fits(self) -> None:
        route_text = REPO_ROOT / "text" / "UndergroundPathWestEast.asm"
        self.assertEqual(overlong_segments(route_text), [])

    def test_end_battle_prefixes_fit(self) -> None:
        route_text = REPO_ROOT / "text" / "UndergroundPathWestEast.asm"
        rogue_text = REPO_ROOT / "data" / "text" / "text_rogue.asm"
        contracts = [
            EndBattleContract(
                route_text, "_UndergroundPathWestEastBiker1EndBattleText", "BIKER"
            ),
            EndBattleContract(
                route_text, "_UndergroundPathWestEastJugglerEndBattleText", "JUGGLER"
            ),
            EndBattleContract(
                route_text, "_UndergroundPathWestEastBurglarEndBattleText", "BURGLAR"
            ),
            EndBattleContract(
                route_text, "_UndergroundPathWestEastBiker2EndBattleText", "BIKER"
            ),
            EndBattleContract(
                route_text, "_UndergroundPathWestEastCueBallEndBattleText", "CUE BALL"
            ),
            EndBattleContract(
                rogue_text, "_GiovanniMiniBossEndBattleText", "GIOVANNI"
            ),
        ]
        failures = [
            (contract.label, rendered_end_battle_width(contract))
            for contract in contracts
            if rendered_end_battle_width(contract) > 17
        ]
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
