"""Real trainer loss -> run reset -> special warp -> controllable Dorm.

Only HP/KO Defiance are forced at the first live battle-loop entry. All
faint handling, battle cleanup, map scripts and warps execute normally.
"""
import unittest
from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_constants

class BlackoutFixture:
    def run_loss(self, *, leader=False):
        h = self.harness
        maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        stride = h.address('wPartyMon2HP') - h.address('wPartyMon1HP')
        h.boot_to_lobby()
        h.enter_stage_door1(maps['PEWTER_GYM'], description='Brock gym')
        if leader:
            events = parse_rgbds_constants(REPO_ROOT / 'constants/event_constants.asm')
            for i in range(3):
                event = events[f'EVENT_BEAT_PEWTER_GYM_TRAINER_{i}']
                addr = h.address('wEventFlags') + event // 8
                h.pyboy.memory[addr] |= 1 << (event % 8)
        trace = []
        def record(label):
            trace.append((label, h.read8('hCurMap'), h.read8('wLastBlackoutMap'),
                          h.read8('wPartyCount'), h.read8('wBattleResult')))
        for label in ('HandlePlayerBlackOut', 'HandleBlackOut',
                      'ResetStatusAndHalveMoneyOnBlackout', 'HealParty',
                      'PrepareForSpecialWarp', 'SpecialEnterMap', 'CrashScreen'):
            h.register_hook(label, lambda _, label=label: record(label))
        fainted = []
        def faint(_):
            if fainted:
                return
            fainted.append(h.read8('wCurOpponent'))
            h.write8('wKODefianceUsages', 0)
            h.write8('wBattleMonHP', 0)
            h.write8('wBattleMonHP', 0, 1)
            for i in range(h.read8('wPartyCount')):
                h.write8('wPartyMon1HP', 0, i * stride)
                h.write8('wPartyMon1HP', 0, i * stride + 1)
        h.register_hook('MainInBattleLoop', faint)
        # The lower trainer sees (4,7); Brock is spoken to from (4,2).
        for _ in range(11 if leader else 7):
            h.move_tile('up')
            if leader and h.read8('wYCoord') == 2:
                h.tap('a', 4)
            for _ in range(20):
                h.tap('a', 2)
                h.tick(8)
                if fainted:
                    break
            if fainted:
                break
        self.assertTrue(fainted, h.diagnostic_state())
        for _ in range(250):
            h.tap('a', 2)
            h.tick(8)
            if h.read8('hCurMap') == maps['SILPH_CO_DORM'] and h.read8('hJoyIgnore') == 0:
                break
        labels = [row[0] for row in trace]
        self.assertNotIn('CrashScreen', labels, trace)
        self.assertNotIn('HealParty', labels, trace)
        self.assertEqual(labels, ['HandlePlayerBlackOut', 'HandleBlackOut',
                                 'ResetStatusAndHalveMoneyOnBlackout',
                                 'PrepareForSpecialWarp', 'SpecialEnterMap'], trace)
        self.assertEqual(trace[0][-1], 1, trace)  # a genuine loss, not a debug win
        self.assertEqual(trace[-1][1:4], (maps['SILPH_CO_DORM'], maps['SILPH_CO_DORM'], 0), trace)
        self.assertEqual(h.read8('hCurMap'), maps['SILPH_CO_DORM'], h.diagnostic_state())
        self.assertEqual((h.read8('wXCoord'), h.read8('wYCoord')), (1, 7))
        self.assertEqual(h.read8('wPartyCount'), 0)
        self.assertEqual(h.read8('wPartySpecies'), 0xff)
        self.assertEqual(h.read8('wBattleCount'), 0)
        self.assertEqual(h.read8('hIsInBattle'), 0)
        h.tick(120)
        self.assertEqual(h.read8('hCurMap'), maps['SILPH_CO_DORM'])
        h.move_tile('right')
        self.assertEqual((h.read8('wXCoord'), h.read8('wYCoord')), (2, 7))
        if leader:
            trainers = parse_trainer_constants(REPO_ROOT / 'constants/trainer_constants.asm')
            self.assertEqual(fainted, [trainers['BROCK']])


class TrainerBlackoutTest(BlackoutFixture, HarnessTestCase):
    def test_regular_trainer_blackout(self):
        self.run_loss()

    def test_brock_blackout(self):
        self.run_loss(leader=True)

if __name__ == '__main__':
    unittest.main()
