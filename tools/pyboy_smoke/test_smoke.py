from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from route_contracts import ROUTE_CONTRACTS, RewardGate
from source_constants import (
    parse_map_constants,
    parse_db_table,
    parse_object_events,
    parse_rgbds_integer,
    parse_rgbds_constants,
    parse_trainer_constants,
    parse_warp_events,
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
    def test_all_selectable_route_contracts(self) -> None:
        maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
        events = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
        trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")

        for index, contract in enumerate(ROUTE_CONTRACTS):
            with self.subTest(route=contract.name):
                objects = parse_object_events(
                    REPO_ROOT / "data" / "maps" / "objects" / contract.object_file
                )
                if contract.standard_object_slots:
                    self.assertTrue(all(len(obj) == 8 for obj in objects[:5]))
                    self.assertIn("_RANDOM", objects[5][5])
                    for reward_index, obj in enumerate(objects[6:9], start=1):
                        self.assertIn(
                            f"_ROGUE_REWARD_POKEBALL_{reward_index}", obj[5]
                        )
                    self.assertIn("_ROGUE_TRADE_NPC", objects[9][5])
                    self.assertEqual(objects[6][:2], objects[9][:2])

                source_warps = parse_warp_events(
                    REPO_ROOT / "data" / "maps" / "objects" / contract.object_file
                )

                if index:
                    assert self.harness is not None
                    self.harness.close()
                    self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
                assert self.harness is not None
                map_id = maps[contract.map_constant]
                self.harness.boot_to_lobby()
                self.harness.enter_stage_door1(map_id, description=contract.name)

                self.assertEqual(self.harness.read8("hCurMap"), map_id)
                expected_warps = []
                for x, y, destination, warp_id in source_warps:
                    destination_id = (
                        self.harness.WARP_NO_RETURN
                        if destination == "WARP_NO_RETURN"
                        else maps[destination]
                    )
                    expected_warps.append(
                        [
                            parse_rgbds_integer(y),
                            parse_rgbds_integer(x),
                            parse_rgbds_integer(warp_id) - 1,
                            destination_id,
                        ]
                    )
                self.assertEqual(self.harness.warp_entries(), expected_warps)
                self.assertEqual(self.harness.read8("wNumSprites"), len(objects))
                self.harness.read8(contract.script_symbol)

                if contract.standard_object_slots:
                    source_classes = [
                        obj[6].removeprefix("OPP_") for obj in objects[:5]
                    ]
                    trainer_classes = self.harness.read_bytes(
                        "wMapSpriteExtraData", 10
                    )[::2]
                    self.assertEqual(
                        trainer_classes,
                        [trainers[name] for name in source_classes],
                    )

                if contract.reward_gate is RewardGate.STANDARD_FIVE_TRAINERS:
                    for event_name in contract.trainer_events:
                        self.harness.set_event(events[event_name])
                    offered_event = events["EVENT_ROGUE_POKEMON_OFFERED"]
                    self.harness.wait_until(
                        lambda: self.harness.event_is_set(offered_event),
                        f"{contract.name} reward offer",
                        600,
                    )

    def test_contract_registry_matches_engine_tables(self) -> None:
        stage_rows = parse_db_table(
            REPO_ROOT / "custom_functions" / "random_stage_selection.asm",
            "RogueStageMapTable",
        )
        miniboss_rows = parse_db_table(
            REPO_ROOT / "custom_functions" / "miniboss.asm",
            "MiniBossStageSlots",
        )
        self.assertEqual(
            [contract.map_constant for contract in ROUTE_CONTRACTS],
            [row[0] for row in stage_rows],
        )
        self.assertEqual(
            {
                contract.map_constant
                for contract in ROUTE_CONTRACTS
                if contract.miniboss_eligible
            },
            {row[0] for row in miniboss_rows},
        )
        self.assertEqual(
            {
                contract.map_constant: contract.reward_gate
                for contract in ROUTE_CONTRACTS
                if contract.reward_gate is not RewardGate.STANDARD_FIVE_TRAINERS
            },
            {
                "ROUTE_24": RewardGate.NUGGET_BRIDGE,
                "SS_ANNE_B1F": RewardGate.SS_ANNE_ROOMS,
            },
        )


class SaveLoadSmokeTest(HarnessTestCase):
    def test_run_state_survives_real_save_and_load(self) -> None:
        assert self.harness is not None
        self.harness.boot_to_lobby()

        sentinels = {
            "wVisitedStagesBitfield": [0xA5, 0x5A, 0x3C, 0xC3],
            "wRogueFlagsBitfield": [0x35],
            "wBattleCount": [0x47],
            "wRoutesSinceSpecial": [0x02],
            "wMiniBossCount": [0x01],
            "wWildAreaState": [0x19],
            "wBridgeOfferedLo": [0x96],
            "wBridgeState": [0x42],
        }
        for label, values in sentinels.items():
            for offset, value in enumerate(values):
                self.harness.write8(label, value, offset)

        saved_map = self.harness.read8("hCurMap")
        transient_address = self.harness.address("wOverworldMap")
        self.harness.pyboy.memory[transient_address] = 0xA6

        self.harness.call_routine("SaveGameData")
        self.assertEqual(
            self.harness.pyboy.memory[self.harness.address("sGameData")], 0xFF
        )

        for label, values in sentinels.items():
            for offset in range(len(values)):
                self.harness.write8(label, 0, offset)
        self.harness.write8("hCurMap", 0)
        self.harness.pyboy.memory[transient_address] = 0x6A

        self.harness.call_routine("LoadMainData")
        self.assertEqual(
            self.harness.pyboy.memory[self.harness.address("sGameData")], 0xFF
        )

        for label, values in sentinels.items():
            self.assertEqual(self.harness.read_bytes(label, len(values)), values)
        self.assertEqual(self.harness.read8("hCurMap"), saved_map)
        self.assertEqual(self.harness.pyboy.memory[transient_address], 0x6A)


class ProceduralStageSmokeTest(HarnessTestCase):
    def assert_generation_contract(
        self,
        name: str,
        map_name: str,
        width: int,
        height: int,
        sprites: int,
        has_boss: bool,
    ) -> None:
        maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
        assert self.harness is not None
        map_id = maps[map_name]
        self.harness.boot_to_lobby()
        self.harness.preload_and_enter_wild_area(map_id, name)

        self.assertEqual(self.harness.read8("hCurMap"), map_id)
        self.assertEqual(self.harness.read8("wNumSprites"), sprites)
        warps = self.harness.warp_entries()
        self.assertGreaterEqual(len(warps), 2)
        for y, x, _warp_id, _destination in warps:
            self.assertIn(y, range(height))
            self.assertIn(x, range(width))

        positions = self.harness.sprite_positions(sprites)
        for y, x in positions:
            self.assertIn(y, range(height))
            self.assertIn(x, range(width))
        self.assertEqual(len({tuple(position) for position in positions}), sprites)

        if has_boss:
            boss_species = self.harness.read8("wMapSpriteExtraData")
            self.assertNotEqual(boss_species, 0)
            item_ids = self.harness.read_bytes("wRogueItem", 7)[::2]
            self.assertTrue(all(item_id != 0 for item_id in item_ids))

    def test_procedural_cave_generation(self) -> None:
        self.assert_generation_contract(
            "Procedural Cave", "PROCEDURAL_CAVE_1", 40, 40, 5, True
        )

    def test_procedural_forest_generation(self) -> None:
        self.assert_generation_contract(
            "Procedural Forest", "PROCEDURAL_FOREST", 40, 40, 5, True
        )

    def test_procedural_cemetery_generation(self) -> None:
        self.assert_generation_contract(
            "Procedural Cemetery", "PROCEDURAL_CEMETERY_1", 20, 18, 1, False
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
