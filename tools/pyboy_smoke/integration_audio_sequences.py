"""Authored credits path and alarm/menu interruption fixtures with sound enabled.

AI victory is configured at the map-script dispatch, not earned in battle.
Low-health fields are configured at the real battle menu. Joypad input, audio
updates, credits fades and the return to Init remain owned by the ROM.
"""
import json
from pathlib import Path
import unittest

import autoplay
from audio_trace import PyBoyAudioTrace
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=Path(__file__).parent/'artifacts/audio_sequences'
MAPS=parse_map_constants(ROOT/'constants/map_constants.asm')


class AuthoredAudioSequenceIntegrationTest(unittest.TestCase):
    cgb_mode=False

    def harness(self):
        h=RedRogueHarness(ROOT,OUTPUT/self.__class__.__name__/self._testMethodName,
                          sound_emulated=True,cgb_mode=self.cgb_mode)
        self.addCleanup(h.close)
        return h

    def finish(self,h,trace,details):
        path=trace.close()
        self.assertEqual(trace.pointer_error_frames,0,trace.pointer_error_examples)
        self.assertEqual(trace.music_sfx_frames,0)
        errors=[(row['label'],trace.active_pointer_errors(row['state'])) for row in trace.events]
        self.assertFalse([(label,values) for label,values in errors if values])
        self.assertGreater(trace._signal_frames,0)
        self.assertEqual(h.hook_errors,[])
        (trace.output_dir/'acceptance.json').write_text(json.dumps({
            'provenance':__doc__,'hardware_mode':h.hardware_mode,
            'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256,
            'trace':str(path),'details':details,'listening_acceptance':False},indent=2)+'\n')

    def test_low_health_three_pairs_with_repeated_real_menu_sfx(self):
        h=self.harness()
        h.boot_fight2(seed=1)
        trace=PyBoyAudioTrace(h,OUTPUT,self.id())
        self.addCleanup(trace.close)
        starts=[]
        def alarm(_):
            if h.read8('wLowHealthAlarm')==0x80:
                starts.append(h.pyboy.frame_count)
                trace.mark('low_health_pair_boundary',{'pair_boundary':len(starts)},capture=True)
        trace.attach('RedRogueLowHealthAlarm',alarm)
        h.write8('wPlayerHPBarColor',2)
        h.write8('wLowHealthTonePairs',4)
        h.write8('wLowHealthAlarm',0x80)
        for i in range(20):
            h.tap('left' if i%2 else 'right',1)
            h.tick(10)
        self.assertEqual(len(starts),4)
        self.assertEqual([b-a for a,b in zip(starts,starts[1:])],[30]*3)
        self.assertEqual(h.read8('wLowHealthAlarm'),0)
        self.assertEqual(h.read8('wLowHealthTonePairs'),0)
        h.tick(120)
        self.assertEqual(len(starts),4,'red bar retriggered after allotment was spent')
        h.write8('wPlayerHPBarColor',0); h.tick(2)
        self.assertEqual(h.read8('wLowHealthTonePairs'),4)
        self.finish(h,trace,{'alarm_pair_boundaries':starts,'menu_inputs':20,
                            'rearmed_after_green':True})

    def test_configured_ai_victory_runs_authored_credits_and_returns_to_title(self):
        h=self.harness()
        autoplay.boot(h,31,battle_count=1,difficulty='VERY_EASY')
        h.write8('wWarpEntries',0,2)
        h.write8('wWarpEntries',MAPS['AI_LAIR'],3)
        trace=PyBoyAudioTrace(h,OUTPUT,self.id())
        trace.MAX_CLIPS=30
        self.addCleanup(trace.close)
        entered=[]
        def victory_dispatch(_):
            if not entered:
                h.write8('wSilphCo1FCurScript',0xfe)
                h.write8('hIsInBattle',0)
                entered.append(h.pyboy.frame_count)
        trace.attach('AILair_Script',victory_dispatch)
        counts={'credits':0,'the_end':0,'init':0}
        for label,key in (('AIVictoryCredits','credits'),('Credits.showTheEnd','the_end'),('Init','init')):
            def record(_,name=key):
                counts[name]+=1
                trace.mark(name,{'count':counts[name]},capture=True)
            trace.attach(label,record)
        agent=autoplay.AutoplayAgent(h,seed=31,player='strong')
        agent.walk('up'); agent.walk('down')
        start=h.pyboy.frame_count
        for i in range(45_000):
            if counts['init']: break
            if i%12==0: h.pyboy.button_press('a')
            elif i%12==2: h.pyboy.button_release('a')
            h.tick(1)
        else: self.fail('credits did not return to title initialization')
        h.pyboy.button_release('a')
        h.tick(120)
        self.assertEqual(counts['credits'],1)
        self.assertEqual(counts['the_end'],1)
        self.assertEqual(counts['init'],1)
        self.finish(h,trace,{'counts':counts,'frames':h.pyboy.frame_count-start,
                            'configured_dispatch_frame':entered})


class CGBAuthoredAudioSequenceIntegrationTest(AuthoredAudioSequenceIntegrationTest):
    cgb_mode=True


if __name__=='__main__':
    unittest.main(verbosity=2)
