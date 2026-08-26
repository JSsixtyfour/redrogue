from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import (
    parse_rgbds_constants,
    parse_trainer_constants,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class AISelectSendOutTest(unittest.TestCase):
    harness: RedRogueHarness | None = None

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants" / "pokemon_constants.asm"
        )
        self.moves = parse_rgbds_constants(
            REPO_ROOT / "constants" / "move_constants.asm"
        )
        self.trainers = parse_trainer_constants(
            REPO_ROOT / "constants" / "trainer_constants.asm"
        )

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

    def mon(self, species: str) -> dict[str, object]:
        return {
            "species": self.species[species],
            "level": 50,
            "moves": [self.moves["TACKLE"]],
        }

    def boot_fixture(self, player: str, enemy: list[str]) -> None:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon(player)],
            [self.mon(species) for species in enemy],
            trainer_class=self.trainers["COOLTRAINER_M"],
            ai_tier=3,
        )
        self.harness.boot_fight2(seed=1)

    def call_selector_with_sentinels(self) -> tuple[int, int]:
        assert self.harness is not None
        sentinels = self.harness.plant_sentinels(
            {
                "wEnemyMonType1": 0xA1,
                "wEnemyMonType2": 0xB2,
                "wPlayerMoveType": 0xC3,
            }
        )

        self.harness.call_routine("AISelectSendOut")
        self.harness.assert_sentinels(sentinels)

        return (
            self.harness.read8("hWhichPokemon"),
            self.harness.read8("wBuffer", 18),
        )

    def test_excludes_active_mon_and_restores_borrowed_state(self) -> None:
        # All three matchups are neutral. If the current mon were not excluded,
        # the deterministic earliest-tie rule would incorrectly return slot 0.
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)

        selected, multiplier = self.call_selector_with_sentinels()

        self.assertEqual(selected, 1)
        self.assertEqual(multiplier, 20)

    def test_skips_fainted_best_counter(self) -> None:
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemyMon2HP", 0)
        self.harness.write8("wEnemyMon2HP", 0, offset=1)

        selected, multiplier = self.call_selector_with_sentinels()

        self.assertEqual(selected, 2)
        self.assertEqual(multiplier, 20)

    def test_equal_matchups_choose_the_earliest_living_slot(self) -> None:
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)

        selected, multiplier = self.call_selector_with_sentinels()

        self.assertEqual(selected, 1)
        self.assertEqual(multiplier, 20)

    def test_enemy_send_out_full_flow_uses_effectiveness_ranking(self) -> None:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("BLASTOISE")],
            [self.mon("CHARIZARD"), self.mon("GEODUDE"), self.mon("GENGAR")],
            trainer_class=self.trainers["COOLTRAINER_M"],
            ai_tier=3,
        )
        send_outs = self.harness.hook_enemy_send_out()

        self.harness.boot_fight2(seed=1)

        # The trainer's opening mon is chosen before the player's battle-mon
        # block is loaded, so it cannot prove matchup-aware replacement. Start
        # a real later EnemySendOut with the player type now authoritative.
        send_outs.clear()
        self.harness.write8("wEnemyMon3HP", 0)
        self.harness.write8("wEnemyMon3HP", 0, offset=1)
        self.harness.write8("wEnemyMonHP", 0)
        self.harness.write8("wEnemyMonHP", 0, offset=1)
        self.harness.probe_routine_until(
            "EnemySendOutFirstMon.next",
            lambda: bool(send_outs),
            limit=12000,
        )

        self.assertTrue(send_outs)
        first = send_outs[0]
        self.assertEqual(first["previous_slot"], 2)
        self.assertEqual(first["best_score"], 40, first)
        self.assertEqual(first["ranked_slot"], 0)
        self.assertEqual(first["selected_slot"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
