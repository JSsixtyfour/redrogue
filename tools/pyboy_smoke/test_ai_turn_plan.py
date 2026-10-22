"""The enemy plans its turn before the player's battle menu (2026-10-22).

ai_turn_plan.asm: the move, a T2+ switch and the switch's replacement are
decided from the board the player sees at the menu, so a player switch-in
cannot inform them. A trainer's switch then goes before every move (Gen 2).
AIPsychicClasses (FINAL_AI) decide after the player's choice instead.
"""
from pathlib import Path
import re
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
PLANNED = 1 << AI['AI_TURN_PLANNED_BIT']
SLOT_MASK = AI['AI_TURN_SLOT_MASK']
STALE = MOVES['HYPER_BEAM']  # a move no enemy below knows


def mon(name, moves, level=50):
    return dict(species=SPECIES[name], level=level, moves=[MOVES[m] for m in moves])


class TurnPlanBattle:
    """One FIGHT 2 battle, driven turn by turn. switch_on_turn: the player
    picks PKMN at that turn's battle menu and switches to party slot 1."""

    def __init__(self, player, enemy, trainer, tier, switch_on_turn=None,
                 player_slot=0, prepare=None, cancel_first_move_menu=False,
                 extra_labels=(), hooks=()):
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
        for label in ('AIPlanEnemyTurn', 'SwitchEnemyMon', 'ExecutePlayerMove', *extra_labels):
            h.hook_flag(label, action=lambda label=label: self.events.append((self.turn, label)))
        h.hook_flag('ExecuteEnemyMove', action=lambda: self.events.append(
            (self.turn, 'ExecuteEnemyMove', h.read8('wEnemySelectedMove'),
             h.read8('wPlayerMonNumber'))))
        for label, callback in hooks:  # (label, f(h)), live for turn 1's plan too
            h.register_hook(label, lambda _c, callback=callback: callback(h))
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
            'JUGGLER', tier=2, player_slot=1, prepare=prepare,
            extra_labels=('AIRankSendOutCandidates',))
        try:
            b.run_until(lambda: any(e[1] == 'ExecutePlayerMove' for e in b.events))
            self.assertTrue(b.menus[0]['plan'] & SWITCH, b.menus)
            turn1 = [e[1] for e in b.events if e[0] <= 1]
            # the KO-threat trigger ranked the reserves; the plan reuses its
            # pick rather than ranking again (Codex review 2026-10-22)
            self.assertNotIn('AIRankSendOutCandidates', turn1, turn1)
            self.assertEqual(b.menus[0]['plan'] & SLOT_MASK, 2, 'Geodude, slot 1')
            turn1 = [e[1] for e in b.events if e[0] == 1]
            self.assertIn('SwitchEnemyMon', turn1)
            self.assertLess(turn1.index('SwitchEnemyMon'), turn1.index('ExecutePlayerMove'),
                            turn1)
            self.assertNotIn('ExecuteEnemyMove', turn1, 'the switch spent the turn')
            self.assertEqual(b.h.read8('wEnemyMonPartyPos'), 1, 'Geodude came in')
        finally:
            b.close()


class BothSidesSwitchTest(unittest.TestCase):
    """EnemySwitchGoesFirstTest's board, but the player switches too. The
    player's switch happens in the menu; the enemy's planned switch still
    goes, to the replacement ranked before the menu (no ranking after it)."""

    def test_enemy_switch_after_a_player_switch_uses_the_planned_slot(self):
        def prepare(h):
            h.write8('wAICount', 0)
            h.reveal_player_moves(0, [1])
            if h.read8('wEnemyMonPartyPos') == 0:
                hp = int.from_bytes(bytes(h.read_bytes('wEnemyMonMaxHP', 2)), 'big') // 4 + 1
                h.write8('wEnemyMonHP', hp >> 8)
                h.write8('wEnemyMonHP', hp & 255, 1)

        b = TurnPlanBattle(
            [mon('ELECTRODE', ['SPLASH', 'THUNDERBOLT']), mon('STARYU', ['TACKLE'])],
            [mon('SLOWPOKE', ['TACKLE']), mon('GEODUDE', ['TACKLE'])],
            'JUGGLER', tier=2, switch_on_turn=1, prepare=prepare,
            extra_labels=('AIRankSendOutCandidates', 'BattleTurnCommitted'))
        try:
            b.run_until(lambda: any(e[1] == 'ExecutePlayerMove' for e in b.events))
            plan = b.menus[0]['plan']
            self.assertTrue(plan & SWITCH, b.menus)
            turn1 = [e[1] for e in b.events if e[0] == 1]
            self.assertNotIn('AIRankSendOutCandidates',
                             turn1[turn1.index('BattleTurnCommitted'):], turn1)
            self.assertEqual(b.h.read8('wPlayerMonNumber'), 1, 'the player switched first')
            self.assertEqual(b.h.read8('wEnemyMonPartyPos'), (plan & SLOT_MASK) - 1)
        finally:
            b.close()


class StayingPlanSkipsTheRankingTest(unittest.TestCase):
    def test_no_replacement_is_ranked_when_staying(self):
        # Geodude is immune to the Electrode's believed electric moves
        b = TurnPlanBattle(
            [mon('ELECTRODE', ['SPLASH'])],
            [mon('GEODUDE', ['TACKLE']), mon('SLOWPOKE', ['TACKLE'])],
            'JUGGLER', tier=2, extra_labels=('AIRankSendOutCandidates',))
        try:
            b.run_until(lambda: any(e[1] == 'ExecuteEnemyMove' for e in b.events))
            plan = b.menus[0]['plan']
            self.assertEqual(plan & (SWITCH | SLOT_MASK), 0, b.menus)
            self.assertNotIn('AIRankSendOutCandidates', [e[1] for e in b.events], b.events)
        finally:
            b.close()


class LockedPlanRescansTheThreatTest(unittest.TestCase):
    """Codex review 2026-10-22: a short sleep returns from SelectEnemyMove
    before move choice clears the decision caches, and the switch check then
    trusted the last decision's KO answer. The Slowpoke (one sleep turn left,
    a quarter HP + 1) is KO'd by the revealed Thunderbolt; a stale "no KO"
    planted before the plan must not keep it in."""

    def test_stale_no_ko_answer_is_not_trusted(self):
        once = {'done': False}

        def prepare(h):
            if once['done']:
                return
            once['done'] = True
            h.write8('wAICount', 0)
            h.reveal_player_moves(0, [1])
            hp = int.from_bytes(bytes(h.read_bytes('wEnemyMonMaxHP', 2)), 'big') // 4 + 1
            h.write8('wEnemyMonHP', hp >> 8)
            h.write8('wEnemyMonHP', hp & 255, 1)
            h.write8('wEnemyMonStatus', 1)  # wakes next turn: not "badly statused"
            h.write8('wAIPlayerKOCache', AI['AI_KO_CACHE_NO'])

        b = TurnPlanBattle(
            [mon('ELECTRODE', ['SPLASH', 'THUNDERBOLT'])],
            [mon('SLOWPOKE', ['TACKLE']), mon('GEODUDE', ['TACKLE'])],
            'JUGGLER', tier=2, player_slot=1, prepare=prepare)
        try:
            b.run_until(lambda: b.menus)
            plan = b.menus[0]['plan']
            self.assertFalse(plan & MOVE_CHOSEN, 'asleep: no move chosen')
            self.assertTrue(plan & SWITCH, f'plan {plan:#04x}')
            self.assertEqual(plan & SLOT_MASK, 2, 'Geodude, slot 1')
        finally:
            b.close()


class LowTierRankingTest(unittest.TestCase):
    """T0/T1 rank a replacement before the menu only for a class whose
    TrainerAI handler can roll a switch (AILowTierSwitchClasses)."""

    def plan_of(self, trainer):
        b = TurnPlanBattle(
            [mon('STARYU', ['TACKLE'])],
            [mon('GEODUDE', ['TACKLE']), mon('SLOWPOKE', ['TACKLE'])],
            trainer, tier=1, extra_labels=('AIRankSendOutCandidates',))
        try:
            b.run_until(lambda: b.menus)
            ranked = [e for e in b.events if e[1] == 'AIRankSendOutCandidates']
            return b.menus[0]['plan'], ranked
        finally:
            b.close()

    def test_a_class_that_never_switches_ranks_nothing(self):
        plan, ranked = self.plan_of('YOUNGSTER')
        self.assertEqual(plan & SLOT_MASK, 0, f'plan {plan:#04x}')
        self.assertEqual(ranked, [])

    def test_a_switching_class_still_ranks_before_the_menu(self):
        plan, ranked = self.plan_of('JUGGLER')
        self.assertEqual(plan & SLOT_MASK, 2, f'plan {plan:#04x}')
        self.assertEqual(len(ranked), 1)

    def test_the_class_list_matches_the_handler_table(self):
        trainer_ai = (ROOT / 'engine/battle/trainer_ai.asm').read_text(encoding='utf-8')
        switching = set()
        handler = None
        for line in trainer_ai.splitlines():
            label = re.match(r'^(\w+AI):', line)
            if label:
                handler = label.group(1)
            elif re.match(r'^\w', line) and not re.match(r'^(IF|ELSE|ENDC)\b', line):
                handler = None
            elif handler and 'AISwitchIfEnoughMons' in line.split(';', 1)[0]:
                switching.add(handler)
        self.assertEqual(switching, {'JugglerAI', 'CooltrainerFAI', 'AgathaAI'})
        rows = re.findall(r'^\s*dbw \d+, (\w+)',
                          (ROOT / 'data/trainers/ai_pointers.asm').read_text(encoding='utf-8'),
                          re.M)
        first = TRAINERS['YOUNGSTER']  # class 1
        by_id = {value - first + 1: name for name, value in TRAINERS.items()}
        expected = {by_id[i + 1] for i, row in enumerate(rows) if row in switching}
        plan_src = (ROOT / 'engine/battle/ai/ai_turn_plan.asm').read_text(encoding='utf-8')
        block = plan_src.split('AILowTierSwitchClasses:', 1)[1].split('db $ff', 1)[0]
        listed = set(re.findall(r'^\s*db (\w+)', block, re.M))
        self.assertEqual(listed, expected)


PREDICT = 1 << AI['AI_TURN_PREDICT_BIT']


class SwitchPredictionTest(unittest.TestCase):
    """AIPredictPlayerSwitch: the player's mon is outclassed (a super effective
    ThunderShock (too weak to KO), nothing believed to KO the Electrode) and has a mon behind it,
    so a T3 trainer whose roll comes up hedges with a close-scoring move. The
    roll is forced at the .rolled seam (0 = always, $ff = never)."""

    def first_turn(self, player, enemy, roll=0, seen=0, prepare=None, tier=3):
        def prime(h):
            h.write8('wAICount', 0)
            if seen:
                h.write8('wAISeenPlayerMons', h.read8('wAISeenPlayerMons') | seen)
            if prepare:
                prepare(h)

        b = TurnPlanBattle(player, enemy, 'JUGGLER', tier=tier, prepare=prime,
                           extra_labels=('AIPredictPlayerSwitch.predicts',
                                         'AIPredictPlayerSwitch.hedged'),
                           hooks=[('AIPredictPlayerSwitch.rolled',
                                   lambda h: setattr(h.pyboy.register_file, 'A', roll))])
        try:
            b.run_until(lambda: any(e[1] == 'ExecuteEnemyMove' for e in b.events))
            move = next(e for e in b.events if e[1] == 'ExecuteEnemyMove')[2]
            labels = [e[1] for e in b.events if e[0] <= 1]
            return b.menus[0]['plan'], move, labels
        finally:
            b.close()

    STARYU = [mon('STARYU', ['TACKLE'], level=60), mon('RATTATA', ['TACKLE'])]

    def test_status_when_the_player_should_switch(self):
        plan, move, labels = self.first_turn(
            self.STARYU, [mon('ELECTRODE', ['THUNDERSHOCK', 'TOXIC'])])
        self.assertIn('AIPredictPlayerSwitch.hedged', labels)
        self.assertTrue(plan & PREDICT, f'plan {plan:#04x}')
        self.assertEqual(move, MOVES['TOXIC'])

    def test_a_failed_roll_attacks(self):
        plan, move, labels = self.first_turn(
            self.STARYU, [mon('ELECTRODE', ['THUNDERSHOCK', 'TOXIC'])], roll=0xff)
        self.assertNotIn('AIPredictPlayerSwitch.predicts', labels)
        self.assertFalse(plan & PREDICT)
        self.assertEqual(move, MOVES['THUNDERSHOCK'])

    def test_no_reserve_means_no_prediction(self):
        plan, move, _ = self.first_turn(
            self.STARYU[:1], [mon('ELECTRODE', ['THUNDERSHOCK', 'TOXIC'])])
        self.assertFalse(plan & PREDICT)
        self.assertEqual(move, MOVES['THUNDERSHOCK'])

    def test_a_ko_on_the_board_is_taken(self):
        def low(h):
            h.write8('wBattleMonHP', 0)
            h.write8('wBattleMonHP', 5, 1)
        plan, move, _ = self.first_turn(
            self.STARYU, [mon('ELECTRODE', ['THUNDERSHOCK', 'TOXIC'])], prepare=low)
        self.assertFalse(plan & PREDICT)
        self.assertEqual(move, MOVES['THUNDERSHOCK'])

    def test_t1_never_predicts(self):
        plan, _, labels = self.first_turn(
            self.STARYU, [mon('ELECTRODE', ['THUNDERSHOCK', 'TOXIC'])], tier=1)
        self.assertNotIn('AIPredictPlayerSwitch.predicts', labels)
        self.assertFalse(plan & PREDICT)

    def test_coverage_for_a_seen_counter(self):
        # Dugtrio (seen) is immune to ThunderShock; Body Slam hits both neutrally
        party = [mon('STARYU', ['TACKLE'], level=60), mon('DUGTRIO', ['TACKLE'])]
        plan, move, _ = self.first_turn(
            party, [mon('ELECTRODE', ['THUNDERSHOCK', 'BODY_SLAM'])], seen=0b10)
        self.assertTrue(plan & PREDICT, f'plan {plan:#04x}')
        self.assertEqual(move, MOVES['BODY_SLAM'])

    def test_an_unseen_counter_is_not_known(self):
        party = [mon('STARYU', ['TACKLE'], level=60), mon('DUGTRIO', ['TACKLE'])]
        plan, move, labels = self.first_turn(
            party, [mon('ELECTRODE', ['THUNDERSHOCK', 'BODY_SLAM'])])
        self.assertIn('AIPredictPlayerSwitch.predicts', labels)
        self.assertFalse(plan & PREDICT, 'no seen counter, no setup or status: no hedge')
        self.assertEqual(move, MOVES['THUNDERSHOCK'])


class MenuFreesALockedEnemyTest(unittest.TestCase):
    """The plan is made while the enemy is locked, so SelectEnemyMove picks
    nothing; the player's menu action then frees it. The enemy must choose
    its move at commit, not run whatever wEnemySelectedMove held (shipped
    2026-10-22: it ran STALE, a move it does not know)."""

    def run_case(self, lock, free_at_commit=None, switch_on_turn=None):
        once = {'done': False}

        def prepare(h):
            if once['done']:
                return
            once['done'] = True
            h.write8('wEnemySelectedMove', STALE)
            lock(h)

        b = TurnPlanBattle(
            [mon('STARYU', ['TACKLE']), mon('DUGTRIO', ['TACKLE'])],
            [mon('ELECTRODE', ['THUNDERBOLT', 'TACKLE'])],
            'JUGGLER', tier=3, prepare=prepare, switch_on_turn=switch_on_turn)
        if free_at_commit:  # the item's effect, after the menu, before commit
            b.h.hook_flag('BattleTurnCommitted', action=lambda: free_at_commit(b.h))
        try:
            b.run_until(lambda: any(e[1] == 'ExecuteEnemyMove' for e in b.events))
            menu = b.menus[0]
            self.assertTrue(menu['plan'] & PLANNED, b.menus)
            self.assertFalse(menu['plan'] & MOVE_CHOSEN, 'locked: nothing was chosen')
            move = next(e for e in b.events if e[1] == 'ExecuteEnemyMove')[2]
            self.assertIn(move, (MOVES['THUNDERBOLT'], MOVES['TACKLE']))
        finally:
            b.close()

    def test_poke_flute_wakes_it(self):
        self.run_case(lambda h: h.write8('wEnemyMonStatus', 3),
                      free_at_commit=lambda h: h.write8('wEnemyMonStatus', 0))

    def test_player_switch_ends_its_wrap(self):
        # SendOutMon clears the enemy's USING_TRAPPING_MOVE
        def wrap(h):
            h.write8('wEnemyBattleStatus1', h.read8('wEnemyBattleStatus1') | (1 << 5))
            h.write8('wEnemyNumAttacksLeft', 3)
        self.run_case(wrap, switch_on_turn=1)

    def test_players_wrap_ends_during_the_menu(self):
        # the plan saw CANNOT_MOVE; an item on the wrap's last turn frees it
        def trapped(h):
            h.write8('wPlayerBattleStatus1', h.read8('wPlayerBattleStatus1') | (1 << 5))
        def freed(h):
            h.write8('wPlayerBattleStatus1', h.read8('wPlayerBattleStatus1') & ~(1 << 5))
        self.run_case(trapped, free_at_commit=freed)


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
