"""Substitute protection, exact breaks, and self-damage routing in both directions."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
SUB = 1 << 4
INVULNERABLE = 1 << 6
MIST = 1 << 1
SPECIAL_FORM = 1 << 3


class SubstituteFixesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.species = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
        cls.moves = parse_rgbds_constants(ROOT / 'constants/move_constants.asm')
        cls.effects = parse_rgbds_constants(ROOT / 'constants/move_effect_constants.asm')
        cls.trainers = parse_trainer_constants(ROOT / 'constants/trainer_constants.asm')

    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        self.h.boot_to_lobby()

    def tearDown(self):
        self.h.close()

    def word(self, name, value):
        self.h.write8(name, value >> 8)
        self.h.write8(name, value & 255, offset=1)

    def hit_test(self, turn, effect, *, no_guard=None, substitute=False,
                 invulnerable=False, mist=False, sleeping=False, x_accuracy=False):
        h = self.h
        h.park_before_hijack()
        h.write8('hWhoseTurn', turn)
        h.write8('wMoveMissed', 0)
        self.word('wDamage', 20)
        attacker = 'wPlayer' if turn == 0 else 'wEnemy'
        defender = 'wEnemy' if turn == 0 else 'wPlayer'
        for prefix, mon in (('wPlayer', 'wBattleMon'), ('wEnemy', 'wEnemyMon')):
            guard = no_guard == ('attacker' if prefix == attacker else 'target')
            h.write8(mon, self.species['MACHOP' if guard else 'SNORLAX'])
            h.write8(mon + 'CatchRate', SPECIAL_FORM if guard else 0)
            h.write8(mon + 'Status', 0)
            h.write8(prefix + 'BattleStatus1', 0)
            h.write8(prefix + 'BattleStatus2', 0)
            h.write8(prefix + 'MonAccuracyMod', 7)
            h.write8(prefix + 'MonEvasionMod', 7)
        h.write8(defender + 'BattleStatus1', INVULNERABLE if invulnerable else 0)
        h.write8(defender + 'BattleStatus2', (SUB if substitute else 0) | (MIST if mist else 0))
        h.write8(('wEnemyMon' if turn == 0 else 'wBattleMon') + 'Status', 2 if sleeping else 0)
        h.write8(attacker + 'BattleStatus2', 1 if x_accuracy else 0)
        h.write8(attacker + 'MoveEffect', self.effects[effect])
        h.write8(attacker + 'MoveAccuracy', 0)  # only No Guard / X Accuracy can hit
        h.call_routine('MoveHitTest', limit=240)
        return h.read8('wMoveMissed')

    def test_no_guard_cannot_seed_through_substitute(self):
        for turn in (0, 1):
            for guard in ('attacker', 'target'):
                for effect in ('LEECH_SEED_EFFECT',):
                    with self.subTest(turn=turn, guard=guard, effect=effect):
                        self.assertEqual(self.hit_test(turn, effect, no_guard=guard, substitute=True), 1)

    def test_drain_can_hit_substitute_with_or_without_no_guard(self):
        for turn in (0, 1):
            for guard in (None, 'attacker', 'target'):
                with self.subTest(turn=turn, guard=guard):
                    self.assertEqual(self.hit_test(turn, 'DRAIN_HP_EFFECT', no_guard=guard,
                                                  substitute=True, x_accuracy=True), 0)

    def test_no_guard_dream_eater_requires_sleep_and_cannot_drain_substitute(self):
        for turn in (0, 1):
            for sleeping, substitute in ((False, False), (True, True), (True, False)):
                with self.subTest(turn=turn, sleeping=sleeping, substitute=substitute):
                    self.assertEqual(self.hit_test(turn, 'DREAM_EATER_EFFECT', no_guard='attacker',
                                                  sleeping=sleeping, substitute=substitute),
                                     0 if sleeping and not substitute else 1)

    def test_no_guard_still_hits_fly_dig_and_ignores_accuracy_both_sides(self):
        for turn in (0, 1):
            for guard in ('attacker', 'target'):
                with self.subTest(turn=turn, guard=guard):
                    self.assertEqual(self.hit_test(turn, 'NO_ADDITIONAL_EFFECT', no_guard=guard,
                                                  invulnerable=True), 0)

    def test_no_guard_cannot_bypass_mist(self):
        for turn in (0, 1):
            for guard in ('attacker', 'target'):
                with self.subTest(turn=turn, guard=guard):
                    self.assertEqual(self.hit_test(turn, 'ATTACK_DOWN1_EFFECT', no_guard=guard, mist=True), 1)

    def test_ordinary_and_x_accuracy_moves_still_respect_fly_dig(self):
        for turn in (0, 1):
            for x_accuracy in (False, True):
                with self.subTest(turn=turn, x_accuracy=x_accuracy):
                    self.assertEqual(self.hit_test(turn, 'NO_ADDITIONAL_EFFECT',
                                                  invulnerable=True, x_accuracy=x_accuracy), 1)
            self.assertEqual(self.hit_test(turn, 'NO_ADDITIONAL_EFFECT', x_accuracy=True), 0)

    def test_substitute_damage_boundary_both_sides(self):
        h = self.h
        for turn in (0, 1):
            for damage in (19, 20, 21, 256):
                h.park_before_hijack()
                target = 'wEnemy' if turn == 0 else 'wPlayer'
                h.write8('hWhoseTurn', turn)
                h.write8(target + 'SubstituteHP', 20)
                h.write8(target + 'BattleStatus2', SUB)
                self.word('wDamage', damage)
                captured = []
                bank, addr = h.symbols.get('AttackSubstitute.applyDamageToSubstitute')
                def enter(_context):
                    de = h.address(target + 'SubstituteHP')
                    bc = h.address(target + 'BattleStatus2')
                    h.pyboy.register_file.D = de >> 8
                    h.pyboy.register_file.E = de & 255
                    h.pyboy.register_file.B = bc >> 8
                    h.pyboy.register_file.C = bc & 255
                h.pyboy.hook_register(bank, addr, enter, None)
                stop_bank, stop_addr = h.symbols.get('AttackSubstitute.substituteBroke')
                def outcome(value):
                    def capture(_context):
                        if value == 'survive' and h.pyboy.register_file.F & 0x10:
                            return  # ret nc is not taken after an underflow
                        if not captured:
                            captured.append((value, h.read8(target + 'SubstituteHP')))
                    return capture
                h.pyboy.hook_register(stop_bank, stop_addr, outcome('break'), None)
                # ret nc immediately precedes .substituteBroke. Stop there too,
                # before a surviving shield can return out of the parked probe.
                h.pyboy.hook_register(stop_bank, stop_addr - 1, outcome('survive'), None)
                try:
                    h.probe_routine_until('AttackSubstitute.applyDamageToSubstitute', lambda: bool(captured), limit=60)
                finally:
                    h.pyboy.hook_deregister(bank, addr)
                    h.pyboy.hook_deregister(stop_bank, stop_addr)
                    h.pyboy.hook_deregister(stop_bank, stop_addr - 1)
                self.assertEqual(captured[0][0], 'survive' if damage < 20 else 'break', (turn, damage))
                if damage < 20:
                    self.assertEqual(captured[0][1], 1)

    def test_self_damage_hits_owner_hp_with_both_substitutes_intact(self):
        h = self.h
        for target, mon, turn in (('Player', 'wBattleMon', 0), ('Enemy', 'wEnemyMon', 1)):
            for damage in (1, 23, 150):
                h.park_before_hijack()
                h.write8('hWhoseTurn', turn)
                for prefix in ('wPlayer', 'wEnemy'):
                    h.write8(prefix + 'BattleStatus2', SUB)
                    h.write8(prefix + 'SubstituteHP', 30)
                self.word('wBattleMonHP', 100)
                self.word('wEnemyMonHP', 100)
                self.word('wDamage', damage)
                captured = []
                bank, addr = h.symbols.get(f'ApplyDamageTo{target}Pokemon.animateHpBar')
                def capture(_context):
                    captured.append((h.read_bytes(mon + 'HP', 2), h.read_bytes('wPlayerSubstituteHP', 2),
                                     h.read8('wPlayerBattleStatus2'), h.read8('wEnemyBattleStatus2')))
                h.pyboy.hook_register(bank, addr, capture, None)
                try:
                    h.probe_routine_until(f'ApplyDamageTo{target}Pokemon.directDamage', lambda: bool(captured), limit=60)
                finally:
                    h.pyboy.hook_deregister(bank, addr)
                hp, shields, player_flags, enemy_flags = captured[0]
                self.assertEqual(int.from_bytes(bytes(hp), 'big'), max(0, 100 - damage))
                self.assertEqual(shields, [30, 30])
                self.assertEqual((player_flags, enemy_flags), (SUB, SUB))

    def battle_self_damage(self, turn, kind):
        # Exercise the real caller, text/animation, and damage route with the
        # game owning its stack and interrupts. No routine or RNG is mocked.
        self.h.close()
        h = self.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        def mon(move):
            return {'species': self.species['SNORLAX'], 'level': 50, 'moves': [self.moves[move]]}
        move = 'JUMP_KICK' if kind == 'crash' else 'SPLASH'
        h.inject_fight2_spec([mon(move if turn == 0 else 'SPLASH')],
                            [mon(move if turn == 1 else 'SPLASH')],
                            trainer_class=self.trainers['COOLTRAINER_M'], ai_tier=0)
        h.boot_fight2(seed=1)
        primed = []
        side = 'Player' if turn == 0 else 'Enemy'
        mon_prefix = 'wBattleMon' if turn == 0 else 'wEnemyMon'
        other_mon = 'wEnemyMon' if turn == 0 else 'wBattleMon'
        target_side = 'wEnemy' if turn == 0 else 'wPlayer'
        def prime(_context):
            if primed:
                return
            primed.append(True)
            for prefix in ('wPlayer', 'wEnemy'):
                h.write8(prefix + 'BattleStatus2', SUB)
                h.write8(prefix + 'SubstituteHP', 30)
            self.word('wBattleMonHP', 100)
            self.word('wEnemyMonHP', 100)
            if kind == 'confusion':
                h.write8('w' + side + 'BattleStatus1', 1 << 7)
                h.write8('w' + side + 'ConfusedCounter', 255)
        h.register_hook('Execute' + side + 'Move', prime)
        if kind == 'crash':
            def force_miss(_context):
                if h.read8('hWhoseTurn') == turn:
                    h.write8(target_side + 'BattleStatus1', INVULNERABLE)
            h.register_hook('MoveHitTest', force_miss)
        captured = []
        def capture(_context):
            captured.append((int.from_bytes(bytes(h.read_bytes(mon_prefix + 'HP', 2)), 'big'),
                             int.from_bytes(bytes(h.read_bytes(other_mon + 'HP', 2)), 'big'),
                             h.read_bytes('wPlayerSubstituteHP', 2),
                             h.read8('wPlayerBattleStatus2'), h.read8('wEnemyBattleStatus2')))
        h.register_hook('ApplyDamageTo' + side + 'Pokemon.animateHpBar', capture)
        h.hook_flag('DisplayBattleMenu', action=lambda: h.write8('wBattleAndStartSavedMenuItem', 0))
        h.hook_flag('MoveSelectionMenu', action=lambda: h.write8('wPlayerMoveListIndex', 0))
        for _ in range(900):
            h.tap('a', 1)
            h.tick(8)
            if captured:
                break
        self.assertTrue(captured, h.diagnostic_state())
        hp, other_hp, shields, player_flags, enemy_flags = captured[0]
        self.assertLess(hp, 100)
        if kind == 'crash':
            self.assertEqual(hp, 99)  # preserve Gen 1's existing crash amount
        self.assertEqual(other_hp, 100)
        self.assertEqual(shields, [30, 30])
        self.assertEqual((player_flags & SUB, enemy_flags & SUB), (SUB, SUB))

    def test_player_confusion_damages_self_in_real_battle(self):
        self.battle_self_damage(0, 'confusion')

    def test_enemy_confusion_damages_self_in_real_battle(self):
        self.battle_self_damage(1, 'confusion')

    def test_player_jump_kick_crash_damages_self_in_real_battle(self):
        self.battle_self_damage(0, 'crash')

    def test_enemy_jump_kick_crash_damages_self_in_real_battle(self):
        self.battle_self_damage(1, 'crash')

    def test_drain_attacks_damage_dolls_without_healing_both_sides(self):
        for turn in (0, 1):
            for move in ('ABSORB', 'MEGA_DRAIN', 'LEECH_LIFE'):
                for shield in (100, 1, None):
                    with self.subTest(turn=turn, move=move, shield=shield):
                        self.drain_battle(turn, move, shield)

    def drain_battle(self, turn, move, shield):
        self.h.close()
        h = self.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        def mon(attack):
            return {'species': self.species['SNORLAX'], 'level': 50, 'moves': [self.moves[attack]]}
        h.inject_fight2_spec([mon(move if turn == 0 else 'SPLASH')],
                            [mon(move if turn == 1 else 'SPLASH')],
                            trainer_class=self.trainers['COOLTRAINER_M'], ai_tier=0)
        h.boot_fight2(seed=1)
        side = 'Player' if turn == 0 else 'Enemy'
        owner = 'wBattleMon' if turn == 0 else 'wEnemyMon'
        target = 'wEnemyMon' if turn == 0 else 'wBattleMon'
        target_side = 'wEnemy' if turn == 0 else 'wPlayer'
        primed = []
        def prime(_context):
            if primed:
                return
            primed.append(True)
            self.word(owner + 'HP', 100)
            self.word(owner + 'MaxHP', 200)
            self.word(target + 'HP', 150)
            h.write8('w' + side + 'BattleStatus2', 1)  # X Accuracy
            h.write8(target_side + 'BattleStatus2', SUB if shield is not None else 0)
            h.write8(target_side + 'SubstituteHP', shield or 0)
        h.register_hook('Execute' + side + 'Move', prime)
        captured = []
        def capture(_context):
            if primed and not captured:
                captured.append((int.from_bytes(bytes(h.read_bytes(owner + 'HP', 2)), 'big'),
                                 int.from_bytes(bytes(h.read_bytes(target + 'HP', 2)), 'big'),
                                 h.read8(target_side + 'SubstituteHP'),
                                 bool(h.read8(target_side + 'BattleStatus2') & SUB)))
        h.register_hook('Execute' + side + 'MoveDone', capture)
        h.hook_flag('DisplayBattleMenu', action=lambda: h.write8('wBattleAndStartSavedMenuItem', 0))
        h.hook_flag('MoveSelectionMenu', action=lambda: h.write8('wPlayerMoveListIndex', 0))
        for _ in range(500):
            h.tap('a', 1)
            h.tick(8)
            if captured:
                break
        self.assertTrue(captured, h.diagnostic_state())
        hp, target_hp, doll_hp, doll_up = captured[0]
        if shield is None:
            self.assertGreater(hp, 100)
            self.assertLess(target_hp, 150)
        else:
            self.assertEqual(hp, 100)
            self.assertEqual(target_hp, 150)
            self.assertEqual(doll_up, shield > 1)
            if doll_up:
                self.assertLess(doll_hp, shield)


if __name__ == '__main__':
    unittest.main()
