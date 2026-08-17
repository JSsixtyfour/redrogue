from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from route_contracts import ROUTE_CONTRACTS
from source_constants import (
    parse_map_constants,
    parse_object_events,
    parse_rgbds_constants,
    parse_trainer_constants,
)
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
                test is self or getattr(test, "test_case", None) is self
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


class RouteContractSmokeTest(HarnessTestCase):
    def test_representative_route_contracts(self) -> None:
        maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
        events = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
        trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")

        for index, contract in enumerate(ROUTE_CONTRACTS):
            with self.subTest(route=contract.name):
                objects = parse_object_events(
                    REPO_ROOT / "data" / "maps" / "objects" / contract.object_file
                )
                self.assertEqual(len(objects), contract.sprite_count)
                self.assertTrue(all(len(obj) == 8 for obj in objects[:5]))
                self.assertIn("_RANDOM", objects[5][5])
                for reward_index, obj in enumerate(objects[6:9], start=1):
                    self.assertIn(f"_ROGUE_REWARD_POKEBALL_{reward_index}", obj[5])
                self.assertIn("_ROGUE_TRADE_NPC", objects[9][5])
                self.assertEqual(objects[6][:2], objects[9][:2])

                if index:
                    assert self.harness is not None
                    self.harness.close()
                    self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
                assert self.harness is not None
                map_id = maps[contract.map_constant]
                self.harness.boot_to_lobby()
                self.harness.enter_stage_door1(map_id, description=contract.name)

                self.assertEqual(self.harness.read8("hCurMap"), map_id)
                expected_warps = [
                    [
                        y,
                        x,
                        warp_id,
                        self.harness.WARP_NO_RETURN
                        if destination == "WARP_NO_RETURN"
                        else maps[destination],
                    ]
                    for y, x, warp_id, destination in contract.expected_warps
                ]
                self.assertEqual(self.harness.warp_entries(), expected_warps)
                self.assertEqual(self.harness.read8("wNumSprites"), contract.sprite_count)
                self.assertIn(self.harness.read8(contract.script_symbol), range(4))

                trainer_classes = self.harness.read_bytes("wMapSpriteExtraData", 10)[::2]
                self.assertEqual(
                    trainer_classes,
                    [trainers[name] for name in contract.trainer_classes],
                )

                for event_name in contract.trainer_events:
                    self.harness.set_event(events[event_name])
                offered_event = events["EVENT_ROGUE_POKEMON_OFFERED"]
                self.harness.wait_until(
                    lambda: self.harness.event_is_set(offered_event),
                    f"{contract.name} reward offer",
                    600,
                )


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
