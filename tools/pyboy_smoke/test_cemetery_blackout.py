"""A cemetery loss must not queue a boss battle for the empty respawn party."""
from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants


class CemeteryBlackoutTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        self.harness.boot_to_lobby()

    def check_loss_dispatch(self, routine, script):
        h = self.harness
        maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        events = parse_rgbds_constants(REPO_ROOT / 'constants/event_constants.asm')
        h.park_before_hijack()
        h.write8('hCurMap', maps['PROCEDURAL_CEMETERY_4'])
        h.write8('wXCoord', 9)
        h.write8('wYCoord', 15)
        event = events['EVENT_BEAT_PC_BOSS']
        h.pyboy.memory[h.address('wEventFlags') + event // 8] &= ~(1 << (event % 8))
        h.write8('hIsInBattle', 0xff)
        h.write8('wBattleResult', 1)
        h.write8('wCurOpponent', 0)
        h.write8('wProceduralCemetery4CurScript', script)
        h.write8('wCurMapScript', script)
        h.call_routine(routine, limit=240)
        self.assertEqual(h.read8('wCurOpponent'), 0)
        self.assertEqual(h.read8('wProceduralCemetery4CurScript'), 0)
        self.assertEqual(h.read8('wCurMapScript'), 0)

    def test_boss_loss_resets_without_retriggering(self):
        self.check_loss_dispatch('ProceduralCemetery4BossBattleScript', 3)

    def test_ordinary_loss_on_boss_tile_does_not_queue_boss(self):
        self.check_loss_dispatch('ProceduralCemetery4DefaultScript', 0)

    def test_run_reset_discards_a_pending_opponent(self):
        h = self.harness
        h.park_before_hijack()
        h.write8('wCurOpponent', 0x4a)  # Articuno from the reported snapshot.
        h.call_routine('RogueResetRunState', limit=600)
        self.assertEqual(h.read8('wPartyCount'), 0)
        self.assertEqual(h.read8('wCurOpponent'), 0)
