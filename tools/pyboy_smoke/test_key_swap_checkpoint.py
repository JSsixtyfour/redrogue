"""Checkpoint eligibility, dynamic visibility and arrival announcement seams."""
import io
from source_constants import parse_map_constants, parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT
from test_move_tutor_prices import return_from_call

MAPS = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
EVENTS = parse_rgbds_constants(REPO_ROOT / 'constants/event_constants.asm')

class KeySwapCheckpointTest(HarnessTestCase):
    def boot(self):
        h = self.harness
        h.boot_fight2(seed=17)
        self.baseline = io.BytesIO()
        h.save_state(self.baseline)
        return h

    def fixture(self, source='REWARD_ROOM', badges=7, count=29, cleared=False, current='INDIGO_PLATEAU_LOBBY'):
        h = self.harness
        self.baseline.seek(0)
        h.load_state(self.baseline)
        h.write8('hCurMap',MAPS[current])
        h.write8('wWarpedFromWhichMap',MAPS[source])
        h.write8('wObtainedBadges',badges)
        h.write8('wBattleCount',count)
        bit = EVENTS['EVENT_VICTORY_ROAD_CLEARED']
        addr = h.address('wEventFlags') + bit//8
        h.pyboy.memory[addr] = (h.pyboy.memory[addr] & ~(1 << (bit%8))) | (int(cleared) << (bit%8))
        return h

    def test_only_three_arrival_windows_open(self):
        self.boot()
        cases = [({},True),({'badges':0x85},True),({'badges':63,'count':53},True),
                 ({'badges':0x7e,'count':53},True),
                 ({'source':'VICTORY_ROAD_1F','badges':255,'count':69,'cleared':True},True),
                 ({'badges':0},False),({'badges':15},False),({'count':28},False),
                 ({'count':30},False),({'badges':63,'count':54},False),
                 ({'source':'SAFFRON_GYM'},False),({'source':'LORELEIS_ROOM','badges':255,'count':69,'cleared':True},False),
                 ({'source':'VICTORY_ROAD_1F','badges':255,'count':69},False),
                 ({'source':'VICTORY_ROAD_1F','badges':255,'count':70,'cleared':True},False),
                 ({'current':'SAFFRON_GYM'},False)]
        for params,expected in cases:
            with self.subTest(params=params):
                h=self.fixture(**params)
                h.call_routine('LobbyKeySwapOpen')
                self.assertEqual(h.last_call_registers['A'],int(expected))

    def test_attendant_visibility_uses_same_gate_without_saved_toggle(self):
        self.boot()
        for source,hidden in [('REWARD_ROOM',0),('SAFFRON_GYM',1)]:
            h=self.fixture(source=source)
            h.write8('hCurrentSpriteOffset',13*16)
            flags=h.read_bytes('wToggleableObjectFlags',32)
            h.call_routine('IsObjectHidden')
            self.assertEqual(h.read8('hIsToggleableObjectOff'),hidden)
            self.assertEqual(h.read_bytes('wToggleableObjectFlags',32),flags)

    def test_access_survives_save_state_and_rejects_stage_return(self):
        self.boot()
        h=self.fixture()
        saved=io.BytesIO();h.save_state(saved);saved.seek(0);h.load_state(saved)
        h.call_routine('PlayerPCAllowed')
        self.assertEqual(h.last_call_registers['A'],1)
        for current,source,allowed in [('SAFFRON_GYM','INDIGO_PLATEAU_LOBBY',0),
                                       ('INDIGO_PLATEAU_LOBBY','SAFFRON_GYM',0),
                                       ('SILPH_CO_DORM','SAFFRON_GYM',1)]:
            h=self.fixture(current=current,source=source)
            h.call_routine('PlayerPCAllowed')
            self.assertEqual(h.last_call_registers['A'],allowed)

    def test_announcement_updates_sprites_before_text_and_skips_closed_window(self):
        h=self.boot();calls=[]
        for name in ('UpdateSprites','DisplayTextID'):
            def callback(_,name=name):
                calls.append(name)
                return_from_call(h)
            h.pyboy.hook_register(*h.symbols.get(name),callback,None)
        self.fixture()
        h.call_routine('LobbyKeySwapAnnounce')
        self.assertEqual(calls,['UpdateSprites','DisplayTextID'])
        self.assertEqual(h.read8('hTextID'),16)
        calls.clear();self.fixture(source='SAFFRON_GYM')
        h.call_routine('LobbyKeySwapAnnounce')
        self.assertEqual(calls,[])
