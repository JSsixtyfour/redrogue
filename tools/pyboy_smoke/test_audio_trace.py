"""Audio pointer oracle distinguishes disabled loader state from consumption."""
import unittest
from types import SimpleNamespace
from audio_trace import PyBoyAudioTrace


class AudioPointerOracleTest(unittest.TestCase):
    def test_per_frame_oracle_counts_transient_faults_without_transition_events(self):
        trace=PyBoyAudioTrace.__new__(PyBoyAudioTrace)
        trace.rom_bank_count=64
        trace.harness=SimpleNamespace(pyboy=SimpleNamespace(frame_count=7))
        trace.pointer_error_frames=trace.music_sfx_frames=0
        trace.pointer_error_examples=[]
        snapshot={'music_playing':True,'channels':[
            {'on':True,'sfx':True,'bank':50,'address':0,'channel':1}]}
        trace._assess_frame(snapshot)
        self.assertEqual(trace.pointer_error_frames,1)
        self.assertEqual(trace.music_sfx_frames,1)
        self.assertEqual(trace.pointer_error_examples[0]['frame'],7)
        snapshot['music_playing']=False
        trace._assess_frame(snapshot)
        self.assertEqual(trace.pointer_error_frames,1)
        self.assertEqual(trace.music_sfx_frames,1)
    def test_enabled_invalid_pointer_is_reported(self):
        trace = PyBoyAudioTrace.__new__(PyBoyAudioTrace)
        trace.rom_bank_count = 64
        snapshot = {'music_playing': True, 'channels': [
            {'on': True, 'bank': 50, 'address': 0, 'channel': 1}]}
        self.assertTrue(trace.active_pointer_errors(snapshot))
        snapshot['channels'][0]['address'] = 0x4000
        self.assertEqual(trace.active_pointer_errors(snapshot), [])

    def test_loading_headers_are_retained_but_not_consumed(self):
        trace = PyBoyAudioTrace.__new__(PyBoyAudioTrace)
        trace.rom_bank_count = 64
        snapshot = {'music_playing': False, 'channels': [
            {'on': True, 'bank': 50, 'address': 0, 'channel': 1}]}
        self.assertEqual(trace.active_pointer_errors(snapshot), [])
