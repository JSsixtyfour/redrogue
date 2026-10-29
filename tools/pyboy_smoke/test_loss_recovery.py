"""Direct-loss transaction: cold SRAM recovery, lifecycle gates and integrity."""
import io
import unittest
import zlib
import tempfile
from pathlib import Path
from harness import RedRogueHarness
from test_save_header import ColdBoot, dump_sram, ARTIFACTS, REPO_ROOT, HEADER_OFFSET
from source_constants import parse_map_constants, parse_rgbds_constants

MAPS = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
EVENTS = parse_rgbds_constants(REPO_ROOT / 'constants/event_constants.asm')
MARKER = 3 * 8192 + 8191

class CgbColdBoot(ColdBoot):
    def __init__(self,image):
        self.tmp=tempfile.TemporaryDirectory()
        ram=Path(self.tmp.name)/'game.sav';ram.write_bytes(image)
        self.h=RedRogueHarness(REPO_ROOT,ARTIFACTS,ram_path=ram,cgb_mode=True)
        self.menu=self.h.hook_flag('MainMenu.mainMenuLoop')
        self.refused=self.h.hook_flag('TryLoadSaveFile.refuse')
        self.chose=self.h.hook_flag('MainMenu.choseContinue')
        self.pressed=self.h.hook_flag('MainMenu.pressedA')
        self.entered=self.h.hook_flag('SpecialEnterMap')

def record(image):
    return image[8192+0x1e00:16384] + image[3*8192+0x1a53:3*8192+0x1c44] + image[3*8192+0x1e00:32768]

def blackout_after_battle_palette(h):
    """Reproduce battle-black selection and EndOfBattle's white-out before loss."""
    armed=[True];notes=[]
    def note(_):notes.append({'holds':0})
    def hold(_):
        row=notes[-1];row['holds']+=1
        if row['holds']==15:
            row['bgp']=h.pyboy.memory[0xff47]
            row['colors']=len(h.pyboy.screen.image.getcolors(24000) or [])
    def enter(_):
        if not armed[0]:return
        armed[0]=False;h.write8('hIsInBattle',255)
        registers=h.pyboy.register_file
        # Chain HOME routines on the real stack; interrupts remain enabled.
        for label in ('HandleBlackOut','GBPalWhiteOut'):
            address=h.address(label);sp=registers.SP-2
            h.pyboy.memory[sp]=address&255;h.pyboy.memory[sp+1]=address>>8
            registers.SP=sp
        registers.B=0 # SET_PAL_BATTLE_BLACK
        registers.PC=h.address('RunPaletteCommand')
    h.register_hook('LossRecoveryNotice',note)
    h.register_hook('LossRecoveryNotice.hold',hold)
    h.register_hook('OverworldLoop',enter)
    h.tick(450,render=True)
    return notes

class LossRecoveryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        h=RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            cls.baseline=io.BytesIO();h.save_state(cls.baseline)
        finally:h.close()

    def fixture(self):
        h=RedRogueHarness(REPO_ROOT, ARTIFACTS);self.addCleanup(h.close)
        h.load_state(io.BytesIO(self.baseline.getvalue()))
        h.write8('wStatusFlags6',h.read8('wStatusFlags6') & ~0x82)
        h.write8('wRentalState',0)
        h.write8('wPlayerCoins',0x12);h.write8('wPlayerCoins',0x34,1)
        h.write8('wCreditsEarnedThisRun',3)
        h.call_routine('LossRecoveryDiscard')
        return h

    def prepared(self,h):
        expected=[]
        def at_publication(_):
            expected.append(bytes(h.read_bytes('wPlayerName',11)+h.read_bytes('wMainDataStart',h.address('wGameProgressFlags')-h.address('wMainDataStart'))
                +h.read_bytes('wGameProgressFlagsEnd',790)+h.read_bytes('wGymsUsedMask',2)
                +[h.read8('wCreditsEarnedThisRun')]))
        h.register_hook('LossRecoveryPrepare.publish',at_publication)
        h.call_routine('LossRecoveryPrepare')
        image=dump_sram(h);r=record(image)
        self.assertEqual(len(r),1521)
        self.assertEqual(r[-1],0xa5)
        self.assertEqual(int.from_bytes(r[-5:-1],'little'),zlib.crc32(r[:-5]))
        # The resumed lobby changes toggles and the play timer after return.
        # Compare at the publication seam, not against later live WRAM.
        body=len(expected[0])
        self.assertEqual(expected,[r[16:16+body]])
        self.assertEqual(r[16+body:-5],bytes(len(r)-21-body)) # unused tail is zeroed
        return image

    def cold(self,image):
        boot=ColdBoot(image);self.addCleanup(boot.close);return boot

    def await_recovered(self,boot):
        h=boot.h;done=h.hook_flag('LossRecoveryFinish.retire')
        h.tick(240)
        for _ in range(400):
            h.tap('start',2)
            if done['count']:break
        self.assertEqual(done['count'],1)
        h.tick(100)
        self.assertEqual(h.read8('hCurMap'),MAPS['SILPH_CO_DORM'])
        self.assertEqual(h.read8('wPartyCount'),0)
        self.assertEqual(h.read8('wPartySpecies'),255)
        self.assertEqual(h.read8('wBoxCount'),0)
        self.assertEqual(h.read_bytes('wPlayerCoins',2),[0x12,0x34])
        self.assertEqual(h.read8('wLossRecoveryPending'),0)
        self.assertEqual(dump_sram(h)[MARKER],0)
        self.assertFalse(h.hook_errors,h.hook_errors)
        return dump_sram(h)

    def test_real_blackout_saves_once_and_debug_skips(self):
        for flags,credits in ((0,0),(0,3),(2,3),(128,0)):
            with self.subTest(flags=flags,credits=credits):
                h=self.fixture();h.write8('wStatusFlags6',flags)
                h.write8('wCreditsEarnedThisRun',credits)
                saves=h.hook_flag('SaveGameData')
                armed=[True]
                def enter(_):
                    if armed[0]:
                        armed[0]=False
                        h.pyboy.register_file.PC=h.address('HandleBlackOut')
                h.register_hook('OverworldLoop',enter)
                h.tick(450)
                self.assertEqual(h.read8('hCurMap'),MAPS['SILPH_CO_DORM'])
                self.assertEqual(h.read8('wPartyCount'),0)
                self.assertEqual(saves['count'],0 if flags else 1)
                h.tick(120)
                self.assertEqual(saves['count'],0 if flags else 1)
                self.assertEqual(h.read8('wLossRecoveryPending'),0)
                self.assertEqual(dump_sram(h)[MARKER],0)
                self.assertFalse(h.hook_errors,h.hook_errors)

    def test_saving_notice_is_visible_after_battle_whiteout(self):
        h=self.fixture()
        notes=blackout_after_battle_palette(h)
        self.assertEqual([row['holds'] for row in notes],[30,30])
        for row in notes:
            self.assertNotEqual(row['bgp'],0)
            self.assertGreater(row['colors'],1)
        self.assertFalse(h.hook_errors,h.hook_errors)

    def test_record_crc_and_cold_recovery_without_main_header(self):
        h=self.fixture();image=bytearray(self.prepared(h))
        image[HEADER_OFFSET:HEADER_OFFSET+8]=b'\0'*8
        boot=self.cold(bytes(image));saved=self.await_recovered(boot)
        second=self.cold(saved)
        self.assertEqual(second.to_menu(),2)
        second.continue_game()
        self.assertEqual(second.h.read8('hCurMap'),MAPS['SILPH_CO_DORM'])
        self.assertEqual(second.h.read_bytes('wPlayerCoins',2),[0x12,0x34])

    def test_debug_and_rental_do_not_arm(self):
        for flags,rental in ((2,0),(128,0),(0,1),(0,255)):
            with self.subTest(flags=flags,rental=rental):
                h=self.fixture();h.write8('wStatusFlags6',flags);h.write8('wRentalState',rental)
                before=dump_sram(h)
                h.call_routine('LossRecoveryCapture')
                self.assertEqual(dump_sram(h),before)
                self.assertEqual(h.read8('wLossRecoveryPending'),0)

    def test_ai_loss_recovery_preserves_attempt_without_manufacturing_victory(self):
        h=self.fixture()
        h.write8('hCurMap',MAPS['AI_LAIR'])
        h.set_event(EVENTS['EVENT_AI_ATTEMPT_SPENT'])
        for name in ('EVENT_AI_DEFEATED','EVENT_POST_GAME'):
            event=EVENTS[name]
            addr=h.address('wEventFlags')+event//8
            h.pyboy.memory[addr] &= ~(1 << (event%8))
        image=self.prepared(h)
        boot=self.cold(image);self.await_recovered(boot)
        self.assertTrue(boot.h.event_is_set(EVENTS['EVENT_AI_ATTEMPT_SPENT']))
        self.assertFalse(boot.h.event_is_set(EVENTS['EVENT_AI_DEFEATED']))
        self.assertFalse(boot.h.event_is_set(EVENTS['EVENT_POST_GAME']))

    def test_corrupt_active_record_refuses_even_valid_old_main(self):
        h=self.fixture();h.call_routine('SaveGameData');image=bytearray(self.prepared(h))
        image[8192+0x1e30]^=1
        boot=self.cold(bytes(image))
        damaged=boot.h.hook_flag('LossRecoveryBoot.damaged')
        boot.h.tick(240)
        for _ in range(400):
            boot.h.tap('start',2)
            if damaged['count']:boot.h.tap('a',2)
            if boot.menu['count']:break
        self.assertEqual(damaged['count'],1)
        self.assertGreater(boot.menu['count'],0)
        self.assertEqual(boot.h.read8('wSaveFileStatus'),1)
        self.assertEqual(boot.refused['count'],0)
        self.assertEqual(dump_sram(boot.h)[MARKER],0xa5)

    def test_unpublished_record_does_not_replace_old_save(self):
        h=self.fixture();h.call_routine('SaveGameData');image=bytearray(self.prepared(h))
        image[MARKER]=0
        boot=self.cold(bytes(image))
        self.assertEqual(boot.to_menu(),2)
        self.assertEqual(boot.h.read8('wPartyCount'),h.read8('wPartyCount'))

    def test_interruption_during_recovery_replays_same_record(self):
        h=self.fixture();image=self.prepared(h)
        for seam in ('RogueResetRunState','SaveGameData.copyParty','LossRecoveryFinish.retire'):
            with self.subTest(seam=seam):
                boot=self.cold(image);cuts=[]
                def capture(_):
                    if cuts:return
                    cuts.append(dump_sram(boot.h))
                    boot.h.pyboy.memory[0]=10
                    boot.h.pyboy.memory[0x4000]=1
                boot.h.register_hook(seam,capture)
                self.await_recovered(boot)
                self.assertEqual(len(cuts),1)
                self.assertEqual(cuts[0][MARKER],0xa5)
                resumed=self.cold(cuts[0]);self.await_recovered(resumed)

if __name__=='__main__':unittest.main()
