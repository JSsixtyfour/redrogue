"""Sound-enabled later-circuit journey; configured first HOF, real play thereafter."""
import json
from pathlib import Path
import unittest

import autoplay
from audio_trace import PyBoyAudioTrace
from harness import RedRogueHarness
import integration_endless_journey as endless

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=Path(__file__).parent/'artifacts/audio_later'


class LaterCircuitAudioIntegrationTest(unittest.TestCase):
    cgb_mode=False

    def test_later_circuit_healing_and_second_continuation_audio(self):
        self.output=OUTPUT/self.__class__.__name__
        self.output.mkdir(parents=True,exist_ok=True)
        self.h=RedRogueHarness(ROOT,self.output,sound_emulated=True,cgb_mode=self.cgb_mode)
        self.addCleanup(self.h.close)
        h=self.h
        autoplay.boot(h,31,battle_count=73,difficulty='VERY_EASY')
        h.set_event(endless.EVENTS['EVENT_AI_DEFEATED'])
        h.write8('wWarpEntries',0,2)
        h.write8('wWarpEntries',endless.MAPS['HALL_OF_FAME'],3)
        trace=PyBoyAudioTrace(h,self.output,self.id())
        trace.MAX_CLIPS=60
        self.addCleanup(trace.close)
        counts={'healing':0,'continuation':0,'victory':0}
        def event(kind):
            def record(_):
                counts[kind]+=1
                trace.mark(kind,{'count':counts[kind],'depth':h.read8('wEndlessDepth')},capture=counts[kind]<=2)
            return record
        for label,kind in (('AnimateHealingMachine','healing'),('EndlessContinue','continuation'),
                           ('EndOfBattle','victory')):
            trace.attach(label,event(kind))
        agent=endless.EndlessJourneyIntegrationTest.journey(self,True,target_continuations=2)
        self.assertEqual(agent.report.outcome,'completed',agent.report.detail)
        self.assertEqual(len(agent.continuation_frames),2)
        self.assertGreaterEqual(agent.report.stages_cleared,8)
        self.assertGreaterEqual(agent.report.battles_won,8)
        self.assertGreater(counts['healing'],0,'no authored healing-machine exposure')
        trace.mark('later_stage_restored',capture=True)
        h.tick(120)
        path=trace.close()
        self.assertEqual(trace.pointer_error_frames,0,trace.pointer_error_examples)
        self.assertEqual(trace.music_sfx_frames,0)
        errors=[(row['label'],trace.active_pointer_errors(row['state'])) for row in trace.events]
        self.assertEqual([(label,values) for label,values in errors if values],[])
        self.assertGreater(trace._signal_frames,0)
        final=trace.state_snapshot()
        self.assertEqual(final['music_id'],h.read8('wMapMusicSoundID'))
        self.assertFalse(any(channel['on'] for channel in final['channels'][4:]))
        self.assertFalse(any(channel['sfx'] for channel in final['channels'][:4]))
        self.assertEqual(h.hook_errors,[])
        (self.output/'audio_acceptance.json').write_text(json.dumps({
            'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256,'hardware_mode':h.hardware_mode,
            'counts':counts,'trace':str(path),'natural_intervening_circuit':True,
            'first_hof_configured':True,'stages':agent.report.stages_cleared,
            'battles':agent.report.battles_won,'listening_acceptance':False},indent=2)+'\n')


class CGBLaterCircuitAudioIntegrationTest(LaterCircuitAudioIntegrationTest):
    cgb_mode=True


if __name__=='__main__':
    unittest.main(verbosity=2)
