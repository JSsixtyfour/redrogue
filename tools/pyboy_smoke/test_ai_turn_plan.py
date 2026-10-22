"""The enemy plans its turn before the player's battle menu (2026-10-22).

ai_turn_plan.asm: the move, a T2+ switch and the switch's replacement are
decided from the board the player sees at the menu, so a player switch-in
cannot inform them. A trainer's switch then goes before every move (Gen 2).
AIPsychicClasses (FINAL_AI) decide after the player's choice instead.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from run_ai_benchmark import prepare_party_driver
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / 'tools/pyboy_smoke/artifacts'

SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
MOVES = parse_rgbds_constants(ROOT / 'constants/move_constants.asm')
TRAINERS = parse_trainer_constants(ROOT / 'constants/trainer_constants.asm')
AI = parse_rgbds_constants(ROOT / 'constants/ai_constants.asm')
MOVE_CHOSEN = 1 << AI['AI_TURN_MOVE_CHOSEN_BIT']
SWITCH = 1 << AI['AI_TURN_SWITCH_BIT']


def mon(name, moves, level=50):
    return dict(species=SPECIES[name], level=level, moves=[MOVES[m] for m in moves])


class TurnPlanBattle:
    """One FIGHT 2 battle, driven turn by turn. switch_on_turn: the player
    picks PKMN at that turn's battle menu and switches to party slot 1."""

    def __init__(self, player, enemy, trainer, tier, switch_on_turn=None,
                 player_slot=0, prepare=None, cancel_first_move_menu=False):
        self.h = h = RedRogueHarness(ROOT, ARTIFACTS)
        self.events = []
        self.menus = []
        self.turn = 0
        self.next_press = None  # one button to press instead of A
        self.cancels = 1 if cancel_first_move_menu else 0
        h.inject_fight2_spec(player, enemy, trainer_class=TRAINERS[trainer], ai_tier=tier)
        if prepare:
            h.hook_flag('AIPlanEnemyTurn', action=lambda: prepare(h))
        self.voluntary = {'target': None, 'count': 0}

        def menu():
            self.turn += 1
            self.menus.append(dict(turn=self.turn, plan=h.read8('wAITurnPlan'),
                                   move=h.read8('wEnemySelectedMove')))
            wants = self.turn == switch_on_turn
            self.voluntary['target'] = 1 if wants else None
            h.write8('wBattleAndStartSavedMenuItem', 2 if wants else 0)

        h.hook_flag('DisplayBattleMenu', action=menu)
        def move_menu():  # never press inside a hook: queue it for the loop
            h.write8('wPlayerMoveListIndex', player_slot)
            if self.cancels:
                self.cancels -= 1
                self.next_press = 'b'

        h.hook_flag('MoveSelectionMenu', action=move_menu)
        self.party_inputs, self.party_modes, _ = prepare_party_driver(h, self.voluntary)
        for label in ('AIPlanEnemyTurn', 'SwitchEnemyMon', 'ExecutePlayerMove'):
            h.hook_flag(label, action=lambda label=label: self.events.append((self.turn, label)))
        h.hook_flag('ExecuteEnemyMove', action=lambda: self.events.append(
            (self.turn, 'ExecuteEnemyMove', h.read8('wEnemySelectedMove'),
             h.read8('wPlayerMonNumber'))))
        h.boot_fight2(seed=1)

    def run_until(self, done, steps=3000):
        h = self.h
        handled = self.party_inputs['count']
        index = len(self.party_modes)
        for _ in range(steps):
            if done():
                return
            if self.party_inputs['count'] > handled:
                h.tick(2)
                h.tap('a' if self.party_modes[index] else 'b')
                handled = self.party_inputs['count']
                index += 1
            else:
                button, self.next_press = self.next_press or 'a', None
                h.tap(button, 1)
                h.tick(8)
        raise AssertionError(f'battle did not get there: {self.events[-12:]}')

    def close(self):
        self.h.close()


class SwitchInDoesNotInformTheMoveTest(unittest.TestCase):
    """Electrode (faster) holds Thunderbolt and Tackle against Staryu, with
    Dugtrio (immune to Thunderbolt) in the back. The player switches to
    Dugtrio on turn 1."""

    def battle(self, trainer):
        return TurnPlanBattle(
            [mon('STARYU', ['TACKLE']), mon('DUGTRIO', ['TACKLE'])],
            [mon('ELECTRODE', ['THUNDERBOLT', 'TACKLE'])],
            trainer, tier=3, switch_on_turn=1)

    def first_enemy_move(self, b):
        b.run_until(lambda: any(e[1] == 'ExecuteEnemyMove' for e in b.events))
        return next(e for e in b.events if e[1] == 'ExecuteEnemyMove')

    def test_planned_move_targets_the_mon_the_player_showed(self):
        b = self.battle('JUGGLER')
        try:
            _, _, move, player_slot = self.first_enemy_move(b)
            self.assertEqual(player_slot, 1, 'the player should have switched to Dugtrio')
            self.assertEqual(move, MOVES['THUNDERBOLT'],
                             'chosen against Staryu, before the switch')
            menu = b.menus[0]
            self.assertTrue(menu['plan'] & MOVE_CHOSEN, 'planned before the menu')
            self.assertEqual(menu['move'], MOVES['THUNDERBOLT'])
        finally:
            b.close()

    def test_psychic_class_reads_the_switch(self):
        b = self.battle('FINAL_AI')
        try:
            _, _, move, player_slot = self.first_enemy_move(b)
            self.assertEqual(player_slot, 1)
            self.assertEqual(move, MOVES['TACKLE'], 'FINAL_AI saw Dugtrio come in')
            self.assertEqual(b.menus[0]['plan'], 0, 'no plan before the menu')
        finally:
            b.close()


class EnemySwitchGoesFirstTest(unittest.TestCase):
    """test_cgb_ai_switch_speed's board: a faster player Electrode with a
    revealed Thunderbolt against a Slowpoke at a quarter HP + 1, Geodude in
    reserve. The T2 trainer plans a switch; it must happen before the
    player's faster attack, so the Thunderbolt hits Geodude."""

    def test_switch_before_the_faster_players_move(self):
        def prepare(h):
            h.write8('wAICount', 0)
            h.reveal_player_moves(0, [1])
            if h.read8('wEnemyMonPartyPos') == 0:
                hp = int.from_bytes(bytes(h.read_bytes('wEnemyMonMaxHP', 2)), 'big') // 4 + 1
                h.write8('wEnemyMonHP', hp >> 8)
                h.write8('wEnemyMonHP', hp & 255, 1)

        b = TurnPlanBattle(
            [mon('ELECTRODE', ['SPLASH', 'THUNDERBOLT'])],
            [mon('SLOWPOKE', ['TACKLE']), mon('GEODUDE', ['TACKLE'])],
            'JUGGLER', tier=2, player_slot=1, prepare=prepare)
        try:
            b.run_until(lambda: any(e[1] == 'ExecutePlayerMove' for e in b.events))
            self.assertTrue(b.menus[0]['plan'] & SWITCH, b.menus)
            turn1 = [e[1] for e in b.events if e[0] == 1]
            self.assertIn('SwitchEnemyMon', turn1)
            self.assertLess(turn1.index('SwitchEnemyMon'), turn1.index('ExecutePlayerMove'),
                            turn1)
            self.assertNotIn('ExecuteEnemyMove', turn1, 'the switch spent the turn')
            self.assertEqual(b.h.read8('wEnemyMonPartyPos'), 1, 'Geodude came in')
        finally:
            b.close()


class CancelledMoveMenuKeepsThePlanTest(unittest.TestCase):
    def test_one_plan_per_turn(self):
        b = TurnPlanBattle(
            [mon('STARYU', ['TACKLE'])],
            [mon('ELECTRODE', ['THUNDERBOLT', 'TACKLE'])],
            'JUGGLER', tier=3, cancel_first_move_menu=True)
        try:
            b.run_until(lambda: any(e[1] == 'ExecuteEnemyMove' for e in b.events))
            self.assertEqual(b.cancels, 0)
            plans = [e for e in b.events if e[1] == 'AIPlanEnemyTurn']
            self.assertGreaterEqual(len(b.menus), 2, 'the menu came back after B')
            self.assertEqual(len(plans), 1, b.events)
        finally:
            b.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
