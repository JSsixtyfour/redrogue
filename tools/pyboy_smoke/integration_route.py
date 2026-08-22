from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class RouteBattleIntegrationTest(unittest.TestCase):
    harness: RedRogueHarness | None = None

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, sound_emulated=True)

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

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
        return completed_result

    def test_route1_first_trainer_battle(self) -> None:
        assert self.harness is not None
        maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
        events = parse_rgbds_constants(
            REPO_ROOT / "constants" / "event_constants.asm"
        )
        route_map = maps["ROUTE_1"]
        trainer_event = events["EVENT_BEAT_ROUTE_1_TRAINER_0"]
        battle_started = self.harness.hook_flag("StartBattle")
        battle_ended = self.harness.hook_flag("EndTrainerBattle")
        battle_menu = self.harness.hook_flag("DisplayBattleMenu")
        move_menu = self.harness.hook_flag("MoveSelectionMenu")
        player_move = self.harness.hook_flag("ExecutePlayerMove")
        player_move_done = self.harness.hook_flag("ExecutePlayerMoveDone")
        player_damage = self.harness.hook_flag("PlayerCalcMoveDamage")
        enemy_damage_applied = self.harness.hook_flag("ApplyDamageToEnemyPokemon")
        hp_bar_updated = self.harness.hook_flag("UpdateHPBar2")
        hud_drawn = self.harness.hook_flag("DrawHUDsAndHPBars")
        enemy_fainted = self.harness.hook_flag("HandleEnemyMonFainted")
        enemy_sent_out = self.harness.hook_flag("EnemySendOut")
        faint_text = self.harness.hook_flag("EnemyMonFaintedText")
        experience = self.harness.hook_flag("GainExperience")
        experience_done = self.harness.hook_flag("GainExperience.done")
        level_up = self.harness.hook_flag("GainExperience.printGrewLevelText")
        learn_move_check = self.harness.hook_flag("LearnMoveFromLevelUp")
        enemy_replaced = self.harness.hook_flag("ReplaceFaintedEnemyMon")
        trainer_victory = self.harness.hook_flag("TrainerBattleVictory")
        enemy_balls_drawn = self.harness.hook_flag("DrawEnemyPokeballs")
        screen_restored = self.harness.hook_flag("LoadScreenTilesFromBuffer1")
        party_menu = self.harness.hook_flag("DisplayPartyMenu")

        # Keep the journey at the earliest difficulty tier. This minimizes
        # unrelated level-up churn while still exercising a real trainer battle.
        self.harness.boot_to_lobby(battle_count=1)
        starting_battle_count = self.harness.read8("wBattleCount")
        self.harness.enter_stage_door1(route_map, description="Route 1")
        self.assertEqual(
            [self.harness.read8("wXCoord"), self.harness.read8("wYCoord")],
            [10, 31],
        )

        for _ in range(3):
            self.harness.move_tile("up")
        for _ in range(8):
            self.harness.move_tile("left")
            if self.harness.read8("wRoute1CurScript") == 1:
                break
        self.assertEqual(self.harness.read8("wRoute1CurScript"), 1)

        for _ in range(300):
            self.harness.tap("a")
            if battle_started["count"]:
                break
        else:
            self.fail("Route 1 trainer pre-battle dialogue did not start battle")

        handled_move_menus = 0
        handled_party_menus = 0
        for _ in range(1200):
            if party_menu["count"] > handled_party_menus:
                self.harness.tick(60)
                self.harness.tap("b")
                handled_party_menus = party_menu["count"]
            elif move_menu["count"] > handled_move_menus:
                # Debug 2's lead knows Fly, Cut, Surf, and Strength. Move off
                # Fly so this journey exercises an ordinary one-turn attack.
                self.harness.tick(120)
                self.harness.tap("down")
                self.harness.tap("down")
                self.harness.tap("down")
                self.harness.tap("a")
                self.harness.tick(600)
                handled_move_menus = move_menu["count"]
            else:
                self.harness.tap("a")
            if (
                self.harness.event_is_set(trainer_event)
                and battle_ended["count"] > 0
                and self.harness.read8("hCurMap") == route_map
                and self.harness.read8("wRoute1CurScript") == 0
            ):
                break
        else:
            self.fail(
                "Route 1 trainer battle did not complete through real input: "
                f"started={battle_started['count']} ended={battle_ended['count']} "
                f"event={self.harness.event_is_set(trainer_event)} "
                f"result={self.harness.read8('wBattleResult')} "
                f"battle_count={self.harness.read8('wBattleCount')} "
                f"battle_menu={battle_menu['count']} move_menu={move_menu['count']} "
                f"player_move={player_move['count']} "
                f"player_move_done={player_move_done['count']} "
                f"player_damage={player_damage['count']} "
                f"enemy_damage_applied={enemy_damage_applied['count']} "
                f"hp_bar_updated={hp_bar_updated['count']} "
                f"hud_drawn={hud_drawn['count']} "
                f"enemy_fainted={enemy_fainted['count']} "
                f"enemy_sent_out={enemy_sent_out['count']} "
                f"faint_text={faint_text['count']} experience={experience['count']} "
                f"experience_done={experience_done['count']} "
                f"level_up={level_up['count']} "
                f"learn_move_check={learn_move_check['count']} "
                f"enemy_replaced={enemy_replaced['count']} "
                f"trainer_victory={trainer_victory['count']} "
                f"enemy_balls_drawn={enemy_balls_drawn['count']} "
                f"screen_restored={screen_restored['count']} "
                f"party_menu={party_menu['count']} "
                f"link_state={self.harness.read8('wLinkState')} "
                f"pc={self.harness.pyboy.register_file.PC:#06x} "
                f"damage={self.harness.read_bytes('wDamage', 2)} "
                f"base_exp={self.harness.read8('wEnemyMonBaseExp')} "
                f"hp_bar_old={self.harness.read_bytes('wHPBarOldHP', 2)} "
                f"hp_bar_new={self.harness.read_bytes('wHPBarNewHP', 2)} "
                f"player_hp={self.harness.read_bytes('wBattleMonHP', 2)} "
                f"enemy_hp={self.harness.read_bytes('wEnemyMonHP', 2)} "
                f"move_index={self.harness.read8('wPlayerMoveListIndex')} "
                f"moves={self.harness.read_bytes('wBattleMonMoves', 4)}"
            )

        self.assertEqual(battle_started["count"], 1)
        self.assertGreaterEqual(battle_ended["count"], 1)
        self.assertTrue(self.harness.event_is_set(trainer_event))
        self.assertGreaterEqual(experience["count"], 1)
        self.assertEqual(experience_done["count"], experience["count"])
        # Party generation and encounter generation are deterministic for a
        # given ROM, but they are allowed to change as the game evolves. A
        # legitimate victory need not produce a level or a new-move check.
        # Those hooks remain in the failure report as useful telemetry.
        self.assertEqual(
            self.harness.read8("wBattleCount"), (starting_battle_count + 1) & 0xFF
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
